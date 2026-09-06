"""Service for conversation CRUD operations."""

from __future__ import annotations

import logging
import time
import uuid
from dataclasses import dataclass

from sqlalchemy import desc, func, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.core.config import get_settings
from app.models.conversation import Conversation
from app.models.message import Message
from app.services.mute_util import resolve_mute_until
from app.topics.models import Topic, TopicAssertion
from app.topics.topic_description_helper import (
    get_topic_high_level_description,
    synthesize_high_level_sentence,
)
from app.topics.topic_ingestion_service import (
    TopicIngestionService,
    enqueue_conversation_event,
    enqueue_message_event,
)

logger = logging.getLogger(__name__)

SNIPPET_CONTEXT_CHARS = 100


def _build_snippet(content: str, query: str, context: int = SNIPPET_CONTEXT_CHARS) -> str:
    """Short excerpt around first occurrence of query (case-insensitive); fallback to head."""
    if not content:
        return ""
    lower_content = content.lower()
    lower_query = (query or "").lower().strip()
    idx = lower_content.find(lower_query) if lower_query else -1
    if idx == -1:
        head = content[: context * 2]
        return head + ("..." if len(content) > context * 2 else "")
    start = max(0, idx - context)
    end = min(len(content), idx + len(lower_query) + context)
    prefix = "..." if start > 0 else ""
    suffix = "..." if end < len(content) else ""
    return f"{prefix}{content[start:end]}{suffix}"


def _like_pattern(raw: str) -> str:
    """Escape LIKE wildcards so % and _ match literally."""
    return f"%{raw.replace(chr(92), chr(92) * 2).replace('%', r'\%').replace('_', r'\_')}%"


def _offset(page: int, page_size: int) -> int:
    return (page - 1) * page_size


@dataclass
class ConversationSearchHit:
    """Internal search result: conversation plus matching messages."""

    conversation: Conversation
    matched_messages: list[Message]


class ConversationService:
    """Handles creation, retrieval, updating, and deletion of conversations."""

    def __init__(self, db: AsyncSession):
        self.db = db

    async def _load_primary(self, user_id: str) -> Conversation | None:
        return await self.db.scalar(
            Conversation.active(user_id)
            .where(Conversation.is_primary.is_(True))
            .options(selectinload(Conversation.messages), selectinload(Conversation.active_topic))
        )

    async def _generate_topic_greeting(self, topic: Topic) -> str:
        parent = await self.db.get(Topic, topic.parent_id) if topic.parent_id else None
        topic_desc = get_topic_high_level_description(topic, parent)

        assertions = list(
            (
                await self.db.scalars(
                    select(TopicAssertion)
                    .where(TopicAssertion.topic_id == topic.id, TopicAssertion.status == "active")
                    .limit(10)
                )
            ).all()
        )

        sentences: list[str] = []
        for a in assertions:
            s = synthesize_high_level_sentence(a.content, a.kind)
            if s and s not in sentences:
                sentences.append(s)

        lines = [
            f"### Topic: **{topic.label}**",
            "",
            f"*{topic_desc}*",
        ]

        if sentences:
            lines.extend(
                [
                    "",
                    "**Context included in this thread:**",
                    *[f"• {s}" for s in sentences],
                ]
            )
        else:
            lines.extend(
                [
                    "",
                    f"This thread is focused on **{topic.label}**. New facts, decisions, and preferences will be remembered here as we chat.",
                ]
            )

        lines.extend(
            [
                "",
                f"How can I help you with **{topic.label}** today?",
            ]
        )
        return "\n".join(lines)

    async def create(
        self,
        user_id: str,
        title: str | None = None,
        model: str | None = None,
        initial_message: str | None = None,
        system_prompt: str | None = None,
        thinking_level: str | None = None,
        active_topic_id: str | None = None,
    ) -> Conversation:
        conversation_id = str(uuid.uuid4())
        model = model or get_settings().default_model

        topic: Topic | None = None
        if active_topic_id:
            topic = await self.db.scalar(
                select(Topic).where(
                    Topic.id == active_topic_id,
                    Topic.user_id == user_id,
                    Topic.status == "active",
                )
            )

        if title is None:
            if topic:
                title = topic.label
            elif initial_message:
                title = initial_message[:50] + ("..." if len(initial_message) > 50 else "")

        conversation = Conversation(
            id=conversation_id,
            user_id=user_id,
            title=title,
            model=model,
            system_prompt=system_prompt,
            thinking_level=thinking_level,
            active_topic_id=topic.id if topic else None,
        )
        self.db.add(conversation)

        now_ns = time.time_ns()
        if topic:
            greeting = await self._generate_topic_greeting(topic)
            assistant_msg = Message(
                id=str(uuid.uuid4()),
                conversation_id=conversation_id,
                role="assistant",
                content=greeting,
                seq=now_ns,
                session_epoch=conversation.session_epoch,
            )
            self.db.add(assistant_msg)

        if initial_message:
            message = Message(
                id=str(uuid.uuid4()),
                conversation_id=conversation_id,
                role="user",
                content=initial_message,
                seq=now_ns + 1000,
                session_epoch=conversation.session_epoch,
            )
            self.db.add(message)

        await self.db.flush()
        if initial_message:
            event = await enqueue_message_event(self.db, conversation, message, "create")
            await TopicIngestionService(self.db).process_event(event)
        await self.db.commit()
        result = await self.db.execute(
            select(Conversation)
            .where(Conversation.id == conversation_id)
            .options(
                selectinload(Conversation.messages),
                selectinload(Conversation.active_topic),
            )
        )
        conv = result.scalar_one()
        logger.info("Created conversation %s for user %s", conversation_id, user_id)
        return conv

    async def get_or_create_primary(
        self,
        user_id: str,
        *,
        model: str | None = None,
        system_prompt: str | None = None,
        thinking_level: str | None = None,
    ) -> Conversation:
        """Idempotently return the user's non-deleted primary conversation."""
        existing = await self._load_primary(user_id)
        if existing is not None:
            return existing
        conversation = Conversation(
            id=str(uuid.uuid4()),
            user_id=user_id,
            title="Primary chat",
            model=model or get_settings().default_model,
            system_prompt=system_prompt,
            thinking_level=thinking_level,
            is_primary=True,
        )
        self.db.add(conversation)
        try:
            await self.db.commit()
        except IntegrityError:
            await self.db.rollback()
            winner = await self._load_primary(user_id)
            if winner is None:
                raise
            return winner
        return await self.db.scalar(
            select(Conversation)
            .where(Conversation.id == conversation.id)
            .options(selectinload(Conversation.messages), selectinload(Conversation.active_topic))
        )

    async def get(
        self, conversation_id: str, user_id: str, include_messages: bool = True
    ) -> Conversation | None:
        query = Conversation.active(user_id).where(Conversation.id == conversation_id)
        if include_messages:
            query = query.options(selectinload(Conversation.messages))
        query = query.options(selectinload(Conversation.active_topic))
        result = await self.db.execute(query)
        return result.scalar_one_or_none()

    async def get_recent_messages(
        self, conversation_id: str, limit: int = 50, session_epoch: int | None = None
    ) -> tuple[list[Message], int, bool]:
        """Most recent `limit` messages chronologically, total count, and has_more flag."""
        count_stmt = select(func.count()).where(Message.conversation_id == conversation_id)
        msg_stmt = select(Message).where(Message.conversation_id == conversation_id)
        if session_epoch is not None:
            count_stmt = count_stmt.where(Message.session_epoch == session_epoch)
            msg_stmt = msg_stmt.where(Message.session_epoch == session_epoch)
        total = (await self.db.execute(count_stmt)).scalar() or 0
        result = await self.db.execute(msg_stmt.order_by(desc(Message.seq)).limit(limit))
        recent = list(result.scalars().all())
        recent.reverse()
        return recent, total, total > len(recent)

    async def get_messages_before(
        self,
        conversation_id: str,
        before_message_id: str,
        limit: int = 50,
        session_epoch: int | None = None,
    ) -> tuple[list[Message], bool]:
        """`limit` messages older than before_message_id chronologically plus has_more."""
        anchor_seq = await self.db.scalar(
            select(Message.seq).where(
                Message.id == before_message_id, Message.conversation_id == conversation_id
            )
        )
        if anchor_seq is None:
            return [], False
        query = select(Message).where(
            Message.conversation_id == conversation_id, Message.seq < anchor_seq
        )
        if session_epoch is not None:
            query = query.where(Message.session_epoch == session_epoch)
        result = await self.db.execute(query.order_by(desc(Message.seq)).limit(limit + 1))
        rows = list(result.scalars().all())
        has_more = len(rows) > limit
        page = rows[:limit]
        page.reverse()
        return page, has_more

    async def list(
        self, user_id: str, page: int = 1, page_size: int = 20, kind: str = "all"
    ) -> tuple[list[Conversation], int]:
        base = Conversation.active(user_id)
        if kind == "primary":
            base = base.where(Conversation.is_primary.is_(True))
        elif kind == "thread":
            base = base.where(Conversation.is_primary.is_(False))
        total = (
            await self.db.execute(select(func.count()).select_from(base.subquery()))
        ).scalar() or 0
        query = (
            base.options(
                selectinload(Conversation.messages), selectinload(Conversation.active_topic)
            )
            .order_by(desc(Conversation.is_pinned), desc(Conversation.updated_at))
            .offset(_offset(page, page_size))
            .limit(page_size)
        )
        result = await self.db.execute(query)
        return list(result.scalars().all()), total

    async def search(
        self, user_id: str, query: str, page: int = 1, page_size: int = 20
    ) -> tuple[list[ConversationSearchHit], int]:
        """Case-insensitive title/message substring search for user's conversations."""
        normalized = (query or "").strip()
        if not normalized:
            return [], 0
        pattern = _like_pattern(normalized)
        title_match = select(Conversation.id).where(
            Conversation.is_deleted == False,  # noqa: E712
            Conversation.user_id == user_id,
            Conversation.title.ilike(pattern, escape="\\"),
        )
        message_match = (
            select(Conversation.id)
            .join(Message, Message.conversation_id == Conversation.id)
            .where(
                Conversation.is_deleted == False,  # noqa: E712
                Conversation.user_id == user_id,
                Message.content.ilike(pattern, escape="\\"),
            )
        )
        matching_ids_subq = title_match.union(message_match).subquery()
        total = (
            await self.db.execute(select(func.count()).select_from(matching_ids_subq))
        ).scalar() or 0
        if total == 0:
            return [], 0
        convs_query = (
            select(Conversation)
            .where(
                Conversation.is_deleted == False,  # noqa: E712
                Conversation.user_id == user_id,
                Conversation.id.in_(select(matching_ids_subq.c.id)),
            )
            .options(selectinload(Conversation.messages))
            .order_by(desc(Conversation.updated_at))
            .offset(_offset(page, page_size))
            .limit(page_size)
        )
        conversations = list((await self.db.execute(convs_query)).scalars().all())
        if not conversations:
            return [], total
        conv_ids = [c.id for c in conversations]
        matched_msgs_query = (
            select(Message)
            .where(
                Message.conversation_id.in_(conv_ids), Message.content.ilike(pattern, escape="\\")
            )
            .order_by(Message.created_at)
        )
        matched_messages = list((await self.db.execute(matched_msgs_query)).scalars().all())
        msgs_by_conv: dict[str, list[Message]] = {cid: [] for cid in conv_ids}
        for msg in matched_messages:
            msgs_by_conv.setdefault(msg.conversation_id, []).append(msg)
        hits = [
            ConversationSearchHit(conversation=conv, matched_messages=msgs_by_conv.get(conv.id, []))
            for conv in conversations
        ]
        return hits, total

    async def update(
        self,
        conversation_id: str,
        user_id: str,
        title: str | None = None,
        model: str | None = None,
        use_memory: bool | None = None,
        use_knowledge_base: bool | None = None,
        system_prompt: str | None = None,
        clear_system_prompt: bool = False,
        enabled_tools: list[str] | None = None,
        set_enabled_tools: bool = False,
        clear_enabled_tools: bool = False,
        is_pinned: bool | None = None,
        thinking_level: str | None = None,
        set_thinking_level: bool = False,
    ) -> Conversation | None:
        conversation = await self.get(conversation_id, user_id, include_messages=False)
        if not conversation:
            return None
        for attr, val in {
            "title": title,
            "model": model,
            "use_memory": use_memory,
            "use_knowledge_base": use_knowledge_base,
            "is_pinned": is_pinned,
        }.items():
            if val is not None:
                setattr(conversation, attr, val)
        if clear_system_prompt:
            conversation.system_prompt = None
        elif system_prompt is not None:
            conversation.system_prompt = system_prompt or None
        if clear_enabled_tools:
            conversation.enabled_tools = None
        elif set_enabled_tools:
            conversation.enabled_tools = enabled_tools
        if set_thinking_level:
            conversation.thinking_level = thinking_level
        await self.db.commit()
        await self.db.refresh(conversation)
        return conversation

    async def set_mute(
        self, conversation_id: str, user_id: str, duration: str
    ) -> Conversation | None:
        """Mute/unmute; duration validated at API boundary."""
        conversation = await self.get(conversation_id, user_id, include_messages=False)
        if conversation is None:
            return None
        conversation.muted_until = resolve_mute_until(duration)
        await self.db.commit()
        await self.db.refresh(conversation)
        return conversation

    async def delete(self, conversation_id: str, user_id: str, soft_delete: bool = True) -> bool:
        conversation = await self.get(conversation_id, user_id, include_messages=False)
        if not conversation:
            return False
        if conversation.is_primary:
            return False
        if soft_delete:
            conversation.is_deleted = True
            event = await enqueue_conversation_event(self.db, conversation, "delete")
            await TopicIngestionService(self.db).process_event(event)
            await self.db.commit()
        else:
            await self.db.delete(conversation)
            await self.db.commit()
        logger.info("Deleted conversation %s for user %s", conversation_id, user_id)
        return True

    async def branch_from_message(
        self, conversation_id: str, message_id: str, user_id: str
    ) -> Conversation | None:
        """Create a new conversation with messages up to branch point inclusive."""
        source = await self.get(conversation_id, user_id, include_messages=True)
        if source is None:
            return None
        messages = source.messages or []
        branch_idx = next((i for i, m in enumerate(messages) if m.id == message_id), None)
        if branch_idx is None:
            return None
        messages_to_copy = messages[: branch_idx + 1]
        new_id = str(uuid.uuid4())
        new_conv = Conversation(
            id=new_id,
            user_id=user_id,
            title=source.title,
            model=source.model,
            system_prompt=source.system_prompt,
            use_memory=source.use_memory,
            use_knowledge_base=source.use_knowledge_base,
            enabled_tools=source.enabled_tools,
            thinking_level=source.thinking_level,
        )
        self.db.add(new_conv)
        copied_messages: list[Message] = []
        for msg in messages_to_copy:
            copied = Message(
                id=str(uuid.uuid4()),
                conversation_id=new_id,
                role=msg.role,
                content=msg.content,
                meta=msg.meta,
                created_at=msg.created_at,
                seq=msg.seq,
            )
            self.db.add(copied)
            copied_messages.append(copied)
        await self.db.flush()
        for copied in copied_messages:
            event = await enqueue_message_event(self.db, new_conv, copied, "create")
            await TopicIngestionService(self.db).process_event(event)
        await self.db.commit()
        result = await self.db.scalar(
            select(Conversation)
            .where(Conversation.id == new_id)
            .options(selectinload(Conversation.messages))
        )
        logger.info(
            "Branched conversation %s at message %s for user %s",
            conversation_id,
            message_id,
            user_id,
        )
        return result
