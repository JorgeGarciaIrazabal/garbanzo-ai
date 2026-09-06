"""User-scoped topic discovery, activation, and readiness state."""

from __future__ import annotations

import math
import uuid
from datetime import UTC, datetime

from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.models.conversation import Conversation
from app.topics.models import Topic, TopicAssertion, TopicContextVersion
from app.topics.schemas import TopicContextStatus, TopicNode
from app.topics.topic_consolidation_service import TopicConsolidationService
from app.topics.topic_description_helper import get_topic_high_level_description
from app.topics.topic_normalization import normalize_topic_label

_EXPLORE_TOPICS = {
    "explore:learn": "Learn something",
    "explore:plan": "Make a plan",
    "explore:create": "Create something",
    "explore:reflect": "Reflect",
    "explore:new": "Something new",
}
_RECENCY_THRESHOLDS: tuple[tuple[int, float], ...] = ((1, 0.18), (7, 0.12), (30, 0.06))


def _sort_key(node: TopicNode) -> tuple[float, str]:
    return (-node.score, node.label.casefold())


class TopicNotFoundError(Exception):
    pass


class PrimaryConversationRequiredError(Exception):
    pass


class TopicService:
    def __init__(self, db: AsyncSession):
        self.db = db

    async def get_owned_topic(self, topic_id: str, user_id: str) -> Topic | None:
        return await self.db.scalar(
            select(Topic).where(
                Topic.id == topic_id, Topic.user_id == user_id, Topic.status == "active"
            )
        )

    async def list_personal(self, user_id: str) -> list[TopicNode]:
        topics = list(
            (
                await self.db.scalars(
                    select(Topic)
                    .where(Topic.user_id == user_id, Topic.status == "active")
                    .order_by(Topic.last_active_at.desc(), Topic.label)
                )
            ).all()
        )
        statuses = {t.id: await self.context_status(t) for t in topics}
        by_id = {t.id: t for t in topics}
        by_parent: dict[str | None, list[Topic]] = {}
        for t in topics:
            by_parent.setdefault(t.parent_id, []).append(t)
        now = datetime.now(UTC)

        def build(topic: Topic) -> TopicNode:
            children = [build(c) for c in by_parent.get(topic.id, [])]
            children.sort(key=_sort_key)
            parent = by_id.get(topic.parent_id) if topic.parent_id else None
            return self._node(topic, statuses[topic.id], children, parent=parent, now=now)

        roots = [build(t) for t in by_parent.get(None, [])]
        roots.sort(key=_sort_key)
        return roots

    def list_explore(self) -> list[TopicNode]:
        now = datetime.now(UTC)
        return [
            TopicNode(
                id=tid,
                label=lbl,
                origin="suggested",
                score=0.5,
                starter_prompts=[f"Help me explore {lbl.casefold()}"],
                updated_at=now,
            )
            for tid, lbl in _EXPLORE_TOPICS.items()
        ]

    async def activate(
        self, conversation_id: str, user_id: str, *, topic_id: str | None, label: str | None
    ) -> tuple[Conversation, Topic]:
        conversation = await self._get_primary(conversation_id, user_id)
        if topic_id and topic_id in _EXPLORE_TOPICS:
            label = _EXPLORE_TOPICS[topic_id]
            topic_id = None
        if topic_id:
            topic = await self.get_owned_topic(topic_id, user_id)
            if topic is None:
                raise TopicNotFoundError
        else:
            clean_label = " ".join((label or "").split())[:200]
            normalized = normalize_topic_label(clean_label)
            # Any active same-label topic is the one to reuse — including
            # one already grouped under a parent (a root-only lookup would
            # create a duplicate root and later break grouping on the
            # (user, parent, label) unique key).
            topic = await self.db.scalar(
                select(Topic).where(
                    Topic.user_id == user_id,
                    Topic.normalized_label == normalized,
                    Topic.status == "active",
                )
            )
            if topic is None:
                topic = Topic(
                    id=str(uuid.uuid4()),
                    user_id=user_id,
                    label=clean_label,
                    normalized_label=normalized,
                    origin="manual",
                    base_score=0.6,
                    signal="active now",
                    mention_count=0,
                    dirty_since=datetime.now(UTC),
                )
                self.db.add(topic)
                await self.db.flush()
        conversation.active_topic_id = topic.id
        conversation.topic_is_pinned = True
        if conversation.is_primary:
            conversation.title = topic.label
            conversation.context_summary = None
            conversation.context_summary_until_id = None
        topic.last_active_at = datetime.now(UTC)
        topic.signal = "active now"
        topic.dirty_since = topic.dirty_since or datetime.now(UTC)
        await self._bump_and_refresh(conversation, topic)
        return conversation, topic

    async def update_selection(
        self,
        conversation_id: str,
        user_id: str,
        *,
        topic_id: str | None,
        set_topic: bool,
        pinned: bool | None,
    ) -> tuple[Conversation, Topic | None]:
        conversation = await self._get_primary(conversation_id, user_id)
        topic: Topic | None = None
        if set_topic:
            if topic_id is not None:
                topic = await self.get_owned_topic(topic_id, user_id)
                if topic is None:
                    raise TopicNotFoundError
            conversation.active_topic_id = topic_id
            # An explicit selection is always a user intent: pin it (matches
            # activate), so ingestion treats it as deliberate and never
            # re-routes the conversation to a semantic lookalike topic.
            if topic_id is not None:
                conversation.topic_is_pinned = True
            if conversation.is_primary:
                if topic is not None:
                    conversation.title = topic.label
                conversation.context_summary = None
                conversation.context_summary_until_id = None
        elif conversation.active_topic_id:
            topic = await self.get_owned_topic(conversation.active_topic_id, user_id)
        if pinned is not None:
            conversation.topic_is_pinned = pinned
        if conversation.active_topic_id is None:
            conversation.topic_is_pinned = False
        await self._bump_and_refresh(conversation)
        return conversation, topic

    async def _bump_and_refresh(
        self, conversation: Conversation, topic: Topic | None = None
    ) -> None:
        conversation.context_version += 1
        await self.db.commit()
        await self.db.refresh(conversation)
        if topic is not None:
            await self.db.refresh(topic)

    async def context_status(self, topic: Topic) -> TopicContextStatus:
        pack = (
            await self.db.get(TopicContextVersion, topic.current_context_version_id)
            if topic.current_context_version_id
            else None
        )
        live_delta_count = (
            await self.db.scalar(
                select(func.count()).where(
                    TopicAssertion.topic_id == topic.id,
                    TopicAssertion.status.in_(("active", "rejected")),
                    *(
                        (TopicAssertion.updated_at > topic.last_consolidated_at,)
                        if topic.last_consolidated_at
                        else ()
                    ),
                )
            )
            or 0
        )
        readiness = (
            ("live" if live_delta_count else "ready")
            if pack is not None
            else ("preparing" if (topic.dirty_since is not None or live_delta_count) else "empty")
        )
        return TopicContextStatus(
            readiness=readiness,
            context_version_id=pack.id if pack else None,
            pack_version=pack.version if pack else None,
            source_event_watermark=pack.source_event_watermark if pack else 0,
            live_delta_count=live_delta_count,
            is_fresh=topic.dirty_since is None,
            updated_at=(pack.created_at if pack else topic.updated_at),
        )

    async def prepare(self, topic: Topic) -> TopicContextStatus:
        topic.dirty_since = topic.dirty_since or datetime.now(UTC)
        await TopicConsolidationService(self.db).consolidate_topic(topic)
        await self.db.commit()
        await self.db.refresh(topic)
        return await self.context_status(topic)

    async def _get_primary(self, conversation_id: str, user_id: str) -> Conversation:
        conv = await self.db.scalar(
            Conversation.active(user_id)
            .where(Conversation.id == conversation_id)
            .options(selectinload(Conversation.active_topic))
        )
        if conv is None:
            raise TopicNotFoundError
        if not conv.is_primary:
            raise PrimaryConversationRequiredError
        return conv

    @staticmethod
    def _node(
        topic: Topic,
        status: TopicContextStatus,
        children: list[TopicNode] | None = None,
        *,
        parent: Topic | None = None,
        now: datetime | None = None,
    ) -> TopicNode:
        score = TopicService._importance_score(topic, now or datetime.now(UTC))
        if children:
            descendant_score = max(c.score for c in children) * 0.94
            breadth_bonus = min(0.08, math.log1p(len(children)) * 0.04)
            score = max(score, min(1.0, descendant_score + breadth_bonus))
        return TopicNode(
            id=topic.id,
            parent_id=topic.parent_id,
            parent_label=parent.label if parent else None,
            label=topic.label,
            origin=topic.origin,  # type: ignore[arg-type]
            score=score,
            signal=topic.signal,
            child_count=len(children or []),
            children=children or [],
            description=get_topic_high_level_description(topic, parent),
            starter_prompts=[
                f"Continue with {topic.label}",
                f"What should I do next about {topic.label}?",
            ],
            context_status=status,
            updated_at=topic.updated_at,
        )

    @staticmethod
    def _importance_score(topic: Topic, now: datetime) -> float:
        """Combine stable affinity, frequency, recency, and live signals."""
        active_at = (
            topic.last_active_at.replace(tzinfo=UTC)
            if topic.last_active_at.tzinfo is None
            else topic.last_active_at.astimezone(UTC)
        )
        age_days = max(0.0, (now - active_at).total_seconds() / 86400)
        recency = next((s for t, s in _RECENCY_THRESHOLDS if age_days <= t), 0.0)
        if recency == 0.0 and age_days > 180:
            recency = -0.08
        mentions = min(max(topic.mention_count, 0), 20)
        frequency = (math.log1p(mentions) / math.log(21)) * 0.28
        signal = 0.0
        if topic.signal:
            exp = topic.signal_expires_at
            if exp is not None and exp.tzinfo is None:
                exp = exp.replace(tzinfo=UTC)
            if exp is None or exp >= now:
                signal = 0.1 if topic.signal.casefold() == "active now" else 0.04
        return min(1.0, max(0.0, topic.base_score + frequency + recency + signal))
