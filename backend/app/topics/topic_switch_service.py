"""Single-call topic switch: archive old thread, clear messages, activate new topic, seed carryover."""

from __future__ import annotations

import logging
import uuid
from dataclasses import dataclass
from datetime import UTC, datetime
from typing import Any

from sqlalchemy import delete, or_, select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.models.conversation import Conversation
from app.models.message import Message
from app.models.user import User
from app.topics.active_context_schemas import (
    ActiveContextItemOut,
    ActiveContextTopic,
    TopicSwitchResponse,
)
from app.topics.carryover_extractor import CarryoverExtractor, make_carryover_context_items
from app.topics.models import ActiveContextItem, Topic, TopicArchive, TopicAssertion, TopicRelation
from app.topics.topic_context_compiler import invalidate_prewarm_cache
from app.topics.topic_description_helper import (
    get_topic_high_level_description,
    synthesize_high_level_sentence,
)
from app.topics.topic_service import (
    PrimaryConversationRequiredError,
    TopicNotFoundError,
    TopicService,
)

logger = logging.getLogger(__name__)


class TopicSwitchError(Exception):
    pass


@dataclass(slots=True)
class _ArchiveSnapshot:
    archive_id: str
    message_count: int
    payload: list[dict[str, Any]]


class TopicSwitchService:
    def __init__(self, db: AsyncSession):
        self.db = db
        self.topics = TopicService(db)

    async def switch(
        self,
        *,
        conversation_id: str,
        user: User,
        topic_id: str | None,
        label: str | None,
        archive: bool,
        carryover_enabled: bool,
        carryover_max_items: int,
        carryover_max_tokens: int,
    ) -> TopicSwitchResponse:
        """Archive → clear → activate → carryover → prepare; tolerated errors log and fall back."""
        conversation = await self._get_primary(conversation_id, user.email)
        prior_topic = (
            conversation.active_topic
            if conversation.active_topic is not None
            else (
                await self.db.get(Topic, conversation.active_topic_id)
                if conversation.active_topic_id
                else None
            )
        )

        # 1. Archive (best-effort)
        archive_id: str | None = None
        if archive:
            try:
                archive_id = (
                    await self._archive(
                        conversation=conversation, user=user, prior_topic=prior_topic
                    )
                ).archive_id
            except Exception as exc:  # pragma: no cover
                logger.warning("Topic switch archive failed; continuing without archive: %s", exc)

        # 2. Clear messages (must succeed)
        try:
            await self._clear_messages(conversation)
        except Exception as exc:  # pragma: no cover
            logger.error("Topic switch message clear failed: %s", exc)
            raise TopicSwitchError("primary_clear_failed") from exc

        # 3. Activate new topic
        try:
            _, new_topic = await self.topics.activate(
                conversation_id=conversation.id, user_id=user.email, topic_id=topic_id, label=label
            )
            conversation.title = new_topic.label
            conversation.context_summary = None
            conversation.context_summary_until_id = None
        except TopicNotFoundError as exc:
            raise TopicSwitchError("topic_not_found") from exc
        except PrimaryConversationRequiredError as exc:
            raise TopicSwitchError("primary_required") from exc

        # 4. Carryover (best-effort)
        carryover_items: list[ActiveContextItemOut] = []
        if archive_id and carryover_enabled:
            try:
                carryover_items = await self._seed_carryover(
                    conversation=conversation,
                    new_topic=new_topic,
                    user=user,
                    archive_id=archive_id,
                    max_items=carryover_max_items,
                    max_tokens=carryover_max_tokens,
                )
            except Exception as exc:  # pragma: no cover
                logger.warning("Topic switch carryover seeding failed; continuing: %s", exc)

        # 5. Prepare pack (best-effort, async)
        try:
            await self.topics.prepare(new_topic)
        except Exception as exc:  # pragma: no cover
            logger.info("Topic switch prepare did not produce a ready pack yet: %s", exc)

        await self.db.commit()
        await self.db.refresh(conversation)

        parent = await self.db.get(Topic, new_topic.parent_id) if new_topic.parent_id else None
        topic_desc = get_topic_high_level_description(new_topic, parent)

        return TopicSwitchResponse(
            conversation_id=conversation.id,
            topic=ActiveContextTopic(
                id=new_topic.id,
                label=new_topic.label,
                parent_id=new_topic.parent_id,
                parent_label=parent.label if parent else None,
                description=topic_desc,
                pinned=conversation.topic_is_pinned,
            ),
            context_version=conversation.context_version,
            session_epoch=conversation.session_epoch,
            archived=bool(archive_id),
            archive_id=archive_id,
            carryover=carryover_items,
            next_turn_summary=(
                f"Switched to {new_topic.label}. "
                f"Context initialized with focus on {new_topic.label.casefold()}."
            ),
        )

    async def combine(
        self,
        *,
        conversation_id: str,
        user: User,
        topic_id: str | None,
        label: str | None,
    ) -> TopicSwitchResponse:
        """Combine an additional topic with the active topic without archiving or clearing messages."""
        conversation = await self._get_primary(conversation_id, user.email)
        prior_topic = (
            conversation.active_topic
            if conversation.active_topic is not None
            else (
                await self.db.get(Topic, conversation.active_topic_id)
                if conversation.active_topic_id
                else None
            )
        )

        # Resolve target topic
        if topic_id:
            target_topic = await self.topics.get_owned_topic(topic_id, user.email)
        elif label:
            target_topic = await self.topics.resolve_or_create(user.email, label)
        else:
            raise TopicSwitchError("topic_not_found")

        # If there was no prior topic, activate target_topic directly without clearing
        if not prior_topic:
            conversation.active_topic_id = target_topic.id
            conversation.title = target_topic.label
            # Pin on first combine: an unpinned selection is invisible to
            # _consider_active_topic's fill-only semantics, and combine is
            # always an explicit user intent.
            conversation.topic_is_pinned = True
            conversation.context_version += 1
            await self.db.commit()
            await self.db.refresh(conversation)
            parent = (
                await self.db.get(Topic, target_topic.parent_id) if target_topic.parent_id else None
            )
            topic_desc = get_topic_high_level_description(target_topic, parent)
            return TopicSwitchResponse(
                conversation_id=conversation.id,
                topic=ActiveContextTopic(
                    id=target_topic.id,
                    label=target_topic.label,
                    parent_id=target_topic.parent_id,
                    parent_label=parent.label if parent else None,
                    description=topic_desc,
                    pinned=conversation.topic_is_pinned,
                ),
                context_version=conversation.context_version,
                session_epoch=conversation.session_epoch,
                archived=False,
                archive_id=None,
                carryover=[],
                next_turn_summary=f"Active topic set to {target_topic.label}.",
            )

        # If already same topic, return cleanly
        if prior_topic.id == target_topic.id:
            parent = (
                await self.db.get(Topic, prior_topic.parent_id) if prior_topic.parent_id else None
            )
            topic_desc = get_topic_high_level_description(prior_topic, parent)
            return TopicSwitchResponse(
                conversation_id=conversation.id,
                topic=ActiveContextTopic(
                    id=prior_topic.id,
                    label=prior_topic.label,
                    parent_id=prior_topic.parent_id,
                    parent_label=parent.label if parent else None,
                    description=topic_desc,
                    pinned=conversation.topic_is_pinned,
                ),
                context_version=conversation.context_version,
                session_epoch=conversation.session_epoch,
                archived=False,
                archive_id=None,
                carryover=[],
                next_turn_summary=f"Topic is already {prior_topic.label}.",
            )

        # 1. Create bidirectional TopicRelation if not existing
        rel1 = await self.db.scalar(
            select(TopicRelation).where(
                TopicRelation.user_id == user.email,
                TopicRelation.source_topic_id == prior_topic.id,
                TopicRelation.target_topic_id == target_topic.id,
                TopicRelation.relation_type == "combined",
            )
        )
        if not rel1:
            self.db.add(
                TopicRelation(
                    id=str(uuid.uuid4()),
                    user_id=user.email,
                    source_topic_id=prior_topic.id,
                    target_topic_id=target_topic.id,
                    relation_type="combined",
                    confidence=1.0,
                    metadata_json={"user_combined": True},
                )
            )

        rel2 = await self.db.scalar(
            select(TopicRelation).where(
                TopicRelation.user_id == user.email,
                TopicRelation.source_topic_id == target_topic.id,
                TopicRelation.target_topic_id == prior_topic.id,
                TopicRelation.relation_type == "combined",
            )
        )
        if not rel2:
            self.db.add(
                TopicRelation(
                    id=str(uuid.uuid4()),
                    user_id=user.email,
                    source_topic_id=target_topic.id,
                    target_topic_id=prior_topic.id,
                    relation_type="combined",
                    confidence=1.0,
                    metadata_json={"user_combined": True},
                )
            )

        # 2. Update conversation title to show combination
        if target_topic.label.lower() not in (conversation.title or "").lower():
            combined_title = f"{prior_topic.label} + {target_topic.label}"
            if len(combined_title) <= 100:
                conversation.title = combined_title

        # 3. Seed active assertions from target topic into active_context_items
        target_assertions = list(
            (
                await self.db.scalars(
                    select(TopicAssertion)
                    .where(
                        TopicAssertion.topic_id == target_topic.id,
                        TopicAssertion.status == "active",
                    )
                    .limit(5)
                )
            ).all()
        )
        for assertion in target_assertions:
            existing = await self.db.scalar(
                select(ActiveContextItem).where(
                    ActiveContextItem.conversation_id == conversation.id,
                    ActiveContextItem.source_type == "assertion",
                    ActiveContextItem.source_id == assertion.id,
                )
            )
            if not existing:
                self.db.add(
                    ActiveContextItem(
                        id=str(uuid.uuid4()),
                        conversation_id=conversation.id,
                        source_type="assertion",
                        source_id=assertion.id,
                        source_meta={"content": assertion.content, "kind": assertion.kind},
                        topic_id=target_topic.id,
                        state="dynamic",
                        reason=f"Combined from {target_topic.label}",
                        relevance_score=0.9,
                        token_count=max(len(assertion.content) // 4, 1),
                    )
                )

        conversation.context_version += 1
        invalidate_prewarm_cache(conversation.id)

        try:
            await self.topics.prepare(target_topic)
        except Exception as exc:  # pragma: no cover
            logger.info("Topic prepare during combine: %s", exc)

        await self.db.commit()
        await self.db.refresh(conversation)

        # Collect all combined topics linked to prior_topic
        all_combined_relations = list(
            (
                await self.db.scalars(
                    select(TopicRelation).where(
                        TopicRelation.user_id == user.email,
                        TopicRelation.relation_type == "combined",
                        or_(
                            TopicRelation.source_topic_id == prior_topic.id,
                            TopicRelation.target_topic_id == prior_topic.id,
                        ),
                    )
                )
            ).all()
        )
        combined_ids = set()
        for r in all_combined_relations:
            if r.source_topic_id != prior_topic.id:
                combined_ids.add(r.source_topic_id)
            if r.target_topic_id != prior_topic.id:
                combined_ids.add(r.target_topic_id)
        combined_topics_list = (
            list((await self.db.scalars(select(Topic).where(Topic.id.in_(combined_ids)))).all())
            if combined_ids
            else []
        )
        combined_labels = [t.label for t in combined_topics_list]

        parent = await self.db.get(Topic, prior_topic.parent_id) if prior_topic.parent_id else None
        topic_desc = get_topic_high_level_description(prior_topic, parent)

        combined_summary = (
            f"Combined {prior_topic.label} and {target_topic.label}. "
            "Context now covers both topics in this conversation."
        )

        return TopicSwitchResponse(
            conversation_id=conversation.id,
            topic=ActiveContextTopic(
                id=prior_topic.id,
                label=conversation.title,
                parent_id=prior_topic.parent_id,
                parent_label=parent.label if parent else None,
                description=topic_desc,
                pinned=conversation.topic_is_pinned,
                combined_topics=combined_labels,
            ),
            context_version=conversation.context_version,
            session_epoch=conversation.session_epoch,
            archived=False,
            archive_id=None,
            carryover=[],
            next_turn_summary=combined_summary,
        )

    async def list_archives(self, topic_id: str, user: User) -> list[TopicArchive]:
        topic = await self.topics.get_owned_topic(topic_id, user.email)
        if topic is None:
            raise TopicNotFoundError
        return list(
            (
                await self.db.scalars(
                    select(TopicArchive)
                    .where(TopicArchive.topic_id == topic_id)
                    .order_by(TopicArchive.created_at.desc())
                )
            ).all()
        )

    async def _get_primary(self, conversation_id: str, user_email: str) -> Conversation:
        conversation = await self.db.scalar(
            Conversation.active(user_email)
            .where(Conversation.id == conversation_id)
            .options(selectinload(Conversation.active_topic))
        )
        if conversation is None or not conversation.is_primary:
            raise PrimaryConversationRequiredError
        return conversation

    async def _archive(
        self, *, conversation: Conversation, user: User, prior_topic: Topic | None
    ) -> _ArchiveSnapshot:
        messages = list(
            (
                await self.db.scalars(
                    select(Message)
                    .where(
                        Message.conversation_id == conversation.id,
                        Message.session_epoch == conversation.session_epoch,
                    )
                    .order_by(Message.seq)
                )
            ).all()
        )
        payload = [
            {
                "id": m.id,
                "role": m.role,
                "content": m.content,
                "created_at": m.created_at.isoformat() if m.created_at else None,
                "meta": m.meta or {},
            }
            for m in messages
        ]
        archive = TopicArchive(
            id=str(uuid.uuid4()),
            user_id=user.email,
            topic_id=prior_topic.id if prior_topic else None,
            from_topic_id=prior_topic.id if prior_topic else None,
            conversation_id=conversation.id,
            message_count=len(messages),
            payload={
                "messages": payload,
                "topic_label": prior_topic.label if prior_topic else None,
                "conversation_title": conversation.title,
                "session_epoch": conversation.session_epoch,
            },
            short_summary=None,
            created_at=datetime.now(UTC),
        )
        self.db.add(archive)
        await self.db.flush()
        return _ArchiveSnapshot(archive_id=archive.id, message_count=len(messages), payload=payload)

    async def _clear_messages(self, conversation: Conversation) -> None:
        conversation.session_epoch += 1
        conversation.context_version += 1
        conversation.context_summary = None
        conversation.context_summary_until_id = None
        await self.db.execute(
            delete(ActiveContextItem).where(ActiveContextItem.conversation_id == conversation.id)
        )
        invalidate_prewarm_cache(conversation.id)
        await self.db.flush()

    async def _seed_carryover(
        self,
        *,
        conversation: Conversation,
        new_topic: Topic,
        user: User,
        archive_id: str,
        max_items: int,
        max_tokens: int,
    ) -> list[ActiveContextItemOut]:
        archive = await self.db.get(TopicArchive, archive_id)
        if archive is None or not archive.payload:
            return []
        archived_messages: list[dict[str, Any]] = list((archive.payload or {}).get("messages", []))
        extractor = CarryoverExtractor(self.db)
        extracted = await extractor.extract(
            user=user,
            archived_payload=archived_messages,
            new_topic_label=new_topic.label,
            max_items=max_items,
            max_tokens=max_tokens,
        )
        if not extracted:
            return []
        now = datetime.now(UTC)
        items: list[ActiveContextItem] = []
        specs = await make_carryover_context_items(extracted)
        for spec in specs:
            content = spec["content"]
            sentence = synthesize_high_level_sentence(content, "carryover")
            item = ActiveContextItem(
                id=str(uuid.uuid4()),
                conversation_id=conversation.id,
                source_type=spec["source_type"],
                source_id=spec["source_id"],
                source_meta={
                    **spec["source_meta"],
                    "carryover_archive_id": archive_id,
                    "content": content,
                    "summary": sentence,
                    "preview": sentence,
                },
                topic_id=new_topic.id,
                state="dynamic",
                reason=sentence or spec["reason"],
                relevance_score=0.5,
                token_count=0,
                last_selected_at=now,
                created_at=now,
            )
            self.db.add(item)
            items.append(item)
        conversation.context_version += 1
        await self.db.commit()
        for item in items:
            await self.db.refresh(item)
        outs: list[ActiveContextItemOut] = []
        for item in items:
            raw_text = (
                (item.source_meta or {}).get("summary")
                or (item.source_meta or {}).get("content")
                or item.reason
                or ""
            )
            out = ActiveContextItemOut.model_validate(item)
            out.summary = synthesize_high_level_sentence(raw_text, "carryover")
            out.display_text = out.summary
            out.category_label = "Carried Over Context"
            outs.append(out)
        return outs
