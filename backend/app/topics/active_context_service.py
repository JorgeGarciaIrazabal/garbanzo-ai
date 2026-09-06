"""Ownership-safe active-context control plane with optimistic versioning."""

from __future__ import annotations

import uuid
from datetime import UTC, datetime
from typing import Any

from sqlalchemy import delete, or_, select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.core.config import get_settings
from app.models.conversation import Conversation
from app.models.knowledge_base import KnowledgeChunk, KnowledgeDocument
from app.models.memory import UserMemory
from app.models.message import Message
from app.topics.active_context_schemas import (
    ActiveContextItemOut,
    ActiveContextResponse,
    ActiveContextTopic,
)
from app.topics.models import (
    ActiveContextItem,
    Topic,
    TopicAssertion,
    TopicExclusion,
    TopicRelation,
)
from app.topics.schemas import TopicContextStatus
from app.topics.topic_description_helper import (
    get_context_summary_and_sections,
    get_topic_high_level_description,
    synthesize_high_level_sentence,
)
from app.topics.topic_service import TopicService


class ContextVersionConflictError(Exception):
    def __init__(self, current_version: int):
        self.current_version = current_version


class ContextSourceNotFoundError(Exception):
    """Raised for missing and cross-user sources alike to avoid disclosure."""


_CATEGORY_LABELS: dict[str, str] = {
    "carryover": "Carried Over Context",
    "topic_assertion": "Topic Knowledge",
    "memory": "Personal Memory",
    "knowledge": "Knowledge Base",
    "attachment": "Attached File",
    "message": "Recent Context",
}


class ActiveContextService:
    def __init__(self, db: AsyncSession):
        self.db = db
        self.topics = TopicService(db)

    async def get(self, conversation_id: str, user_id: str) -> ActiveContextResponse:
        conversation = await self._conversation(conversation_id, user_id)
        items = list(
            (
                await self.db.scalars(
                    select(ActiveContextItem)
                    .where(ActiveContextItem.conversation_id == conversation_id)
                    .order_by(
                        ActiveContextItem.state,
                        ActiveContextItem.relevance_score.desc(),
                        ActiveContextItem.last_selected_at.desc(),
                    )
                )
            ).all()
        )
        topic = conversation.active_topic
        parent = None
        topic_description = None
        context_summary = None
        context_sections: list[dict[str, Any]] = []
        combined_labels: list[str] = []

        if topic is not None:
            if topic.parent_id:
                parent = await self.db.get(Topic, topic.parent_id)
            topic_description = get_topic_high_level_description(topic, parent)
            assertions = list(
                (
                    await self.db.scalars(
                        select(TopicAssertion).where(
                            TopicAssertion.topic_id == topic.id,
                            TopicAssertion.status == "active",
                        )
                    )
                ).all()
            )

            # Query any combined topics linked via TopicRelation
            combined_relations = list(
                (
                    await self.db.scalars(
                        select(TopicRelation).where(
                            TopicRelation.user_id == user_id,
                            TopicRelation.relation_type == "combined",
                            or_(
                                TopicRelation.source_topic_id == topic.id,
                                TopicRelation.target_topic_id == topic.id,
                            ),
                        )
                    )
                ).all()
            )
            combined_ids = {
                r.source_topic_id if r.source_topic_id != topic.id else r.target_topic_id
                for r in combined_relations
            }
            if combined_ids:
                combined_topics_list = list(
                    (await self.db.scalars(select(Topic).where(Topic.id.in_(combined_ids)))).all()
                )
                combined_labels = [t.label for t in combined_topics_list]

            context_summary, context_sections = get_context_summary_and_sections(
                topic, items, assertions, combined_labels=combined_labels
            )

        status = (
            await self.topics.context_status(topic) if topic is not None else self._empty_status()
        )
        typed = [ActiveContextItemOut.model_validate(item) for item in items]
        for t_item in typed:
            raw_text = (
                (t_item.source_meta or {}).get("content")
                or (t_item.source_meta or {}).get("title")
                or t_item.reason
                or ""
            )
            t_item.summary = synthesize_high_level_sentence(raw_text, t_item.source_type)
            t_item.display_text = t_item.summary
            t_item.category_label = _CATEGORY_LABELS.get(t_item.source_type, "Topic Context")

        return ActiveContextResponse(
            conversation_id=conversation.id,
            context_version=conversation.context_version,
            topic=ActiveContextTopic(
                id=topic.id,
                label=conversation.title or topic.label,
                parent_id=topic.parent_id,
                parent_label=parent.label if parent else None,
                description=topic_description,
                pinned=conversation.topic_is_pinned,
                combined_topics=combined_labels,
            )
            if topic
            else None,
            status=status,
            token_count=sum(item.token_count for item in items if item.state != "excluded"),
            token_budget=get_settings().topic_context_token_budget,
            pinned_items=[i for i in typed if i.state == "pinned"],
            dynamic_items=[i for i in typed if i.state == "dynamic"],
            excluded_items=[i for i in typed if i.state == "excluded"],
            next_turn_summary=context_summary,
            topic_description=topic_description,
            context_summary=context_summary,
            context_sections=context_sections,
        )

    async def add_item(
        self,
        conversation_id: str,
        user_id: str,
        *,
        source_type: str,
        source_id: str,
        source_meta: dict[str, Any] | None,
        topic_id: str | None,
        state: str,
        reason: str | None,
        context_version: int,
    ) -> tuple[ActiveContextItem, int]:
        conversation = await self._conversation(conversation_id, user_id)
        self._check_version(conversation, context_version)
        await self._validate_source(source_type, source_id, user_id)
        if topic_id and await self.topics.get_owned_topic(topic_id, user_id) is None:
            raise ContextSourceNotFoundError
        item = await self.db.scalar(
            select(ActiveContextItem).where(
                ActiveContextItem.conversation_id == conversation_id,
                ActiveContextItem.source_type == source_type,
                ActiveContextItem.source_id == source_id,
            )
        )
        if item is None:
            item = ActiveContextItem(
                id=str(uuid.uuid4()),
                conversation_id=conversation_id,
                source_type=source_type,
                source_id=source_id,
                source_meta=source_meta or {},
                topic_id=topic_id,
                state=state,
                reason=reason or "Added by you",
                last_selected_at=datetime.now(UTC),
            )
            self.db.add(item)
        else:
            item.source_meta = source_meta or item.source_meta
            item.topic_id = topic_id or item.topic_id
            item.state = state
            item.reason = reason or item.reason
            item.last_selected_at = datetime.now(UTC)
        if state == "excluded":
            await self._sync_exclusion(user_id, item, True)
        return await self._commit_item(conversation, item)

    async def update_item(
        self, conversation_id: str, item_id: str, user_id: str, *, state: str, context_version: int
    ) -> tuple[ActiveContextItem, int]:
        conversation = await self._conversation(conversation_id, user_id)
        self._check_version(conversation, context_version)
        item = await self.db.scalar(
            select(ActiveContextItem).where(
                ActiveContextItem.id == item_id,
                ActiveContextItem.conversation_id == conversation_id,
            )
        )
        if item is None:
            raise ContextSourceNotFoundError
        item.state = state
        item.last_selected_at = datetime.now(UTC)
        await self._sync_exclusion(user_id, item, state == "excluded")
        return await self._commit_item(conversation, item)

    async def _commit_item(
        self, conversation: Conversation, item: ActiveContextItem
    ) -> tuple[ActiveContextItem, int]:
        conversation.context_version += 1
        await self.db.commit()
        await self.db.refresh(item)
        return item, conversation.context_version

    async def fresh_start(
        self, conversation_id: str, user_id: str, *, keep_pins: bool, context_version: int
    ) -> int:
        conversation = await self._conversation(conversation_id, user_id)
        self._check_version(conversation, context_version)
        states_to_clear = ["dynamic"] if keep_pins else ["dynamic", "pinned"]
        await self.db.execute(
            delete(ActiveContextItem).where(
                ActiveContextItem.conversation_id == conversation_id,
                ActiveContextItem.state.in_(states_to_clear),
            )
        )
        conversation.active_topic_id = None
        conversation.topic_is_pinned = False
        conversation.context_version += 1
        await self.db.commit()
        return conversation.context_version

    async def _conversation(self, conversation_id: str, user_id: str) -> Conversation:
        conv = await self.db.scalar(
            Conversation.active(user_id)
            .where(Conversation.id == conversation_id, Conversation.is_primary.is_(True))
            .options(selectinload(Conversation.active_topic))
        )
        if conv is None:
            raise ContextSourceNotFoundError
        return conv

    @staticmethod
    def _check_version(conversation: Conversation, expected: int) -> None:
        if conversation.context_version != expected:
            raise ContextVersionConflictError(conversation.context_version)

    async def _validate_source(self, source_type: str, source_id: str, user_id: str) -> None:
        exists = False
        if source_type in {"message", "attachment"}:
            exists = bool(
                await self.db.scalar(
                    select(Message.id)
                    .join(Conversation, Conversation.id == Message.conversation_id)
                    .where(
                        Message.id == source_id,
                        Conversation.user_id == user_id,
                        Conversation.is_deleted.is_(False),
                    )
                )
            )
        elif source_type == "thread":
            exists = bool(
                await self.db.scalar(
                    select(Conversation.id).where(
                        Conversation.id == source_id,
                        Conversation.user_id == user_id,
                        Conversation.is_deleted.is_(False),
                        Conversation.is_primary.is_(False),
                    )
                )
            )
        elif source_type == "memory":
            exists = bool(
                await self.db.scalar(
                    select(UserMemory.id).where(
                        UserMemory.id == source_id,
                        UserMemory.user_id == user_id,
                        UserMemory.is_active.is_(True),
                    )
                )
            )
        elif source_type == "knowledge":
            doc = await self.db.scalar(
                select(KnowledgeDocument.id).where(
                    KnowledgeDocument.id == source_id, KnowledgeDocument.user_id == user_id
                )
            )
            chunk = await self.db.scalar(
                select(KnowledgeChunk.id).where(
                    KnowledgeChunk.id == source_id, KnowledgeChunk.user_id == user_id
                )
            )
            exists = bool(doc or chunk)
        elif source_type == "topic_assertion":
            exists = bool(
                await self.db.scalar(
                    select(TopicAssertion.id)
                    .join(Topic, Topic.id == TopicAssertion.topic_id)
                    .where(TopicAssertion.id == source_id, Topic.user_id == user_id)
                )
            )
        if not exists:
            raise ContextSourceNotFoundError

    async def _sync_exclusion(
        self, user_id: str, item: ActiveContextItem, should_exclude: bool
    ) -> None:
        existing = await self.db.scalar(
            select(TopicExclusion).where(
                TopicExclusion.user_id == user_id,
                TopicExclusion.scope == "source",
                TopicExclusion.target_id == item.source_id,
                TopicExclusion.revoked_at.is_(None),
            )
        )
        if should_exclude:
            if existing is None:
                self.db.add(
                    TopicExclusion(
                        id=str(uuid.uuid4()),
                        user_id=user_id,
                        topic_id=item.topic_id,
                        scope="source",
                        target_id=item.source_id,
                        origin="context_panel",
                        reason=item.reason,
                    )
                )
        elif existing is not None and not existing.is_privacy_deletion:
            existing.revoked_at = datetime.now(UTC)

    @staticmethod
    def _empty_status():
        return TopicContextStatus(readiness="empty")
