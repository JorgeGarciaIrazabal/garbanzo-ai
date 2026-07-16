"""Service for conversation CRUD operations."""

from __future__ import annotations

import logging
import uuid
from dataclasses import dataclass

from sqlalchemy import desc, func, select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.core.config import get_settings
from app.models.conversation import Conversation
from app.models.message import Message
from app.services.mute_util import resolve_mute_until

logger = logging.getLogger(__name__)


# Number of characters of context to include on each side of a match
# when building a search-result snippet.
SNIPPET_CONTEXT_CHARS = 100


def _build_snippet(content: str, query: str, context: int = SNIPPET_CONTEXT_CHARS) -> str:
    """Return a short excerpt of ``content`` around the first occurrence of ``query``.

    Search is case-insensitive. If ``query`` is not found (e.g. because this
    message was matched via an FTS-style search on another field), the first
    ``context * 2`` chars of the content are returned instead.

    The returned string is prefixed / suffixed with ``"..."`` when truncation
    occurred at that end.
    """
    if not content:
        return ""

    lower_content = content.lower()
    lower_query = (query or "").lower().strip()
    idx = lower_content.find(lower_query) if lower_query else -1

    if idx == -1:
        # Fallback: return the head of the message.
        head = content[: context * 2]
        return head + ("..." if len(content) > context * 2 else "")

    start = max(0, idx - context)
    end = min(len(content), idx + len(lower_query) + context)
    prefix = "..." if start > 0 else ""
    suffix = "..." if end < len(content) else ""
    return f"{prefix}{content[start:end]}{suffix}"


@dataclass
class ConversationSearchHit:
    """Internal search result: a conversation plus the messages that matched.

    The service layer returns these instead of Pydantic models so the
    API layer can shape the response. ``matched_messages`` is empty when
    the match came solely from the conversation's title.
    """

    conversation: Conversation
    matched_messages: list[Message]


class ConversationService:
    """Handles creation, retrieval, updating, and deletion of conversations.

    Decoupled from LLM provider details — messaging and streaming live in
    ``ChatService``.
    """

    def __init__(self, db: AsyncSession):
        self.db = db

    async def create(
        self,
        user_id: str,
        title: str | None = None,
        model: str | None = None,
        initial_message: str | None = None,
        system_prompt: str | None = None,
    ) -> Conversation:
        conversation_id = str(uuid.uuid4())
        model = model or get_settings().default_model

        if title is None and initial_message:
            title = initial_message[:50] + ("..." if len(initial_message) > 50 else "")

        conversation = Conversation(
            id=conversation_id,
            user_id=user_id,
            title=title,
            model=model,
            system_prompt=system_prompt,
        )

        self.db.add(conversation)

        if initial_message:
            message = Message(
                id=str(uuid.uuid4()),
                conversation_id=conversation_id,
                role="user",
                content=initial_message,
            )
            self.db.add(message)

        await self.db.commit()

        result = await self.db.execute(
            select(Conversation)
            .where(Conversation.id == conversation_id)
            .options(selectinload(Conversation.messages))
        )
        conversation = result.scalar_one()

        logger.info("Created conversation %s for user %s", conversation_id, user_id)
        return conversation

    async def get(
        self,
        conversation_id: str,
        user_id: str,
        include_messages: bool = True,
    ) -> Conversation | None:
        query = Conversation.active(user_id).where(Conversation.id == conversation_id)

        if include_messages:
            query = query.options(selectinload(Conversation.messages))

        result = await self.db.execute(query)
        return result.scalar_one_or_none()

    async def list(
        self,
        user_id: str,
        page: int = 1,
        page_size: int = 20,
    ) -> tuple[list[Conversation], int]:
        base = Conversation.active(user_id)
        count_query = select(func.count()).select_from(base.subquery())
        total_result = await self.db.execute(count_query)
        total = total_result.scalar() or 0

        query = (
            base.options(selectinload(Conversation.messages))
            .order_by(desc(Conversation.is_pinned), desc(Conversation.updated_at))
            .offset((page - 1) * page_size)
            .limit(page_size)
        )

        result = await self.db.execute(query)
        conversations = list(result.scalars().all())

        return conversations, total

    async def search(
        self,
        user_id: str,
        query: str,
        page: int = 1,
        page_size: int = 20,
    ) -> tuple[list[ConversationSearchHit], int]:
        """Search the user's conversations by title or message content.

        Case-insensitive substring search (``ILIKE``) is performed against:
          * ``Conversation.title``
          * ``Message.content`` for every message in any non-deleted
            conversation owned by ``user_id``.

        Only conversations belonging to ``user_id`` (and not soft-deleted)
        can appear in the results — user isolation is enforced at every
        stage of the query.

        Returns a tuple ``(hits, total)`` where ``hits`` is a paginated list
        of :class:`ConversationSearchHit` ordered by the conversation's
        ``updated_at`` (newest first), and ``total`` is the unpaginated
        count of matching conversations.
        """
        normalized = (query or "").strip()
        if not normalized:
            return [], 0

        # Escape LIKE wildcards in the user-supplied query so characters
        # like '%' and '_' match literally.
        escaped = normalized.replace("\\", "\\\\").replace("%", "\\%").replace("_", "\\_")
        pattern = f"%{escaped}%"

        # Sub-query: distinct conversation IDs that match either by title
        # or by having at least one message whose content matches.
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

        # Total number of matching conversations.
        count_query = select(func.count()).select_from(matching_ids_subq)
        total = (await self.db.execute(count_query)).scalar() or 0

        if total == 0:
            return [], 0

        # Paginated conversations, newest updates first.
        convs_query = (
            select(Conversation)
            .where(
                Conversation.is_deleted == False,  # noqa: E712
                Conversation.user_id == user_id,
                Conversation.id.in_(select(matching_ids_subq.c.id)),
            )
            .options(selectinload(Conversation.messages))
            .order_by(desc(Conversation.updated_at))
            .offset((page - 1) * page_size)
            .limit(page_size)
        )
        conversations = list((await self.db.execute(convs_query)).scalars().all())

        if not conversations:
            return [], total

        # Pull every message whose content matched the query and belongs to
        # one of the conversations on this page, so we can attach snippets.
        conv_ids = [c.id for c in conversations]
        matched_msgs_query = (
            select(Message)
            .where(
                Message.conversation_id.in_(conv_ids),
                Message.content.ilike(pattern, escape="\\"),
            )
            .order_by(Message.created_at)
        )
        matched_messages = list((await self.db.execute(matched_msgs_query)).scalars().all())
        msgs_by_conv: dict[str, list[Message]] = {cid: [] for cid in conv_ids}
        for msg in matched_messages:
            msgs_by_conv.setdefault(msg.conversation_id, []).append(msg)

        hits = [
            ConversationSearchHit(
                conversation=conv,
                matched_messages=msgs_by_conv.get(conv.id, []),
            )
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
    ) -> Conversation | None:
        conversation = await self.get(conversation_id, user_id, include_messages=False)
        if not conversation:
            return None

        if title is not None:
            conversation.title = title
        if model is not None:
            conversation.model = model
        if use_memory is not None:
            conversation.use_memory = use_memory
        if use_knowledge_base is not None:
            conversation.use_knowledge_base = use_knowledge_base
        if is_pinned is not None:
            conversation.is_pinned = is_pinned
        if clear_system_prompt:
            conversation.system_prompt = None
        elif system_prompt is not None:
            conversation.system_prompt = system_prompt or None

        # enabled_tools has three-way semantics:
        #   clear_enabled_tools=True → set column to NULL ("all tools")
        #   set_enabled_tools=True   → use ``enabled_tools`` verbatim ([] means no tools)
        #   neither                   → leave unchanged
        if clear_enabled_tools:
            conversation.enabled_tools = None
        elif set_enabled_tools:
            conversation.enabled_tools = enabled_tools

        await self.db.commit()
        await self.db.refresh(conversation)

        return conversation

    async def set_mute(
        self,
        conversation_id: str,
        user_id: str,
        duration: str,
    ) -> Conversation | None:
        """Mute or unmute notifications for ``user_id``'s conversation.

        ``duration`` is one of ``"8h"``, ``"1w"``, ``"forever"``, ``"unmute"``
        (validated by the ``MuteUpdate`` schema at the API boundary). Returns
        ``None`` if the conversation doesn't exist / isn't owned by
        ``user_id`` (a room needs a separate per-member row since it has many
        members; a conversation has exactly one owner, so the column lives
        directly on ``Conversation``).
        """
        conversation = await self.get(conversation_id, user_id, include_messages=False)
        if conversation is None:
            return None

        conversation.muted_until = resolve_mute_until(duration)

        await self.db.commit()
        await self.db.refresh(conversation)
        return conversation

    async def delete(
        self,
        conversation_id: str,
        user_id: str,
        soft_delete: bool = True,
    ) -> bool:
        conversation = await self.get(conversation_id, user_id, include_messages=False)
        if not conversation:
            return False

        if soft_delete:
            conversation.is_deleted = True
            await self.db.commit()
        else:
            await self.db.delete(conversation)
            await self.db.commit()

        logger.info("Deleted conversation %s for user %s", conversation_id, user_id)
        return True

    async def branch_from_message(
        self,
        conversation_id: str,
        message_id: str,
        user_id: str,
    ) -> Conversation | None:
        """Create a new conversation with messages up to (and including) the branch point."""
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
        )
        self.db.add(new_conv)

        for msg in messages_to_copy:
            self.db.add(
                Message(
                    id=str(uuid.uuid4()),
                    conversation_id=new_id,
                    role=msg.role,
                    content=msg.content,
                    meta=msg.meta,
                    created_at=msg.created_at,
                )
            )

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
