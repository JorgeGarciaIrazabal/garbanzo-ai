"""Durable and best-effort realtime ingestion for topic evidence."""

from __future__ import annotations

import asyncio
import hashlib
import json
import logging
import re
import uuid
from datetime import UTC, datetime
from typing import Any

from sqlalchemy import delete, exists, select
from sqlalchemy.exc import InvalidRequestError, NoResultFound
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import aliased

from app.core.config import get_settings
from app.db import session as db_session
from app.models.conversation import Conversation
from app.models.message import Message
from app.services.embedding_provider import EmbeddingProvider, get_embedding_provider
from app.topics.models import (
    MessageTopic,
    Topic,
    TopicAssertion,
    TopicAssertionEvidence,
    TopicExclusion,
    TopicIngestionEvent,
    TopicIngestionState,
)
from app.topics.topic_normalization import normalize_topic_label

logger = logging.getLogger(__name__)

# fmt: off
_STOP_WORDS = set(
    ["about", "after", "again", "also", "and", "are", "can", "could", "for", "from", "have", "help", "hello", "hear", "how", "into", "just", "like", "need", "please", "simple", "some", "should", "that", "the", "this", "want", "what", "when", "where", "which", "with", "would", "you", "thanks", "thank", "terms", "tool", "use", "using", "explain", "find", "search", "check", "tell", "give", "make", "create", "show", "open", "look", "your", "there", "here", "more", "many", "does", "will", "who", "whom", "hay", "que", "como", "cual", "cuales", "donde", "cuando", "quien", "quienes", "por", "para", "este", "esta", "estos", "estas", "ese", "esa", "esos", "esas", "opinas", "crees", "sabes", "dime", "cuenta", "quiero", "puedo", "podemos", "hacer", "unos", "unas", "algo", "nada", "hola", "buenos", "buenas", "muchas", "muchos", "algun", "alguna", "algunos", "algunas", "sobre", "entre"]  # noqa: SIM905
)
# fmt: on

_ASSERTION_PATTERNS: tuple[tuple[str, re.Pattern[str]], ...] = (
    (
        "decision",
        re.compile(
            r"\b(?:i|we) (?:decided|chose|agreed)\b|\b(?:hemos? decidido|elegido|acordado)\b", re.I
        ),
    ),
    (
        "preference",
        re.compile(
            r"\b(?:i prefer|my preference is|i like)\b|\b(?:prefiero|mi preferencia es|me gusta)\b",
            re.I,
        ),
    ),
    (
        "constraint",
        re.compile(
            r"\b(?:must|cannot|can't|need to|has to|within a budget)\b|\b(?:debe|debemos|no puede|no puedo|tiene que|con presupuesto)\b",
            re.I,
        ),
    ),
    (
        "goal",
        re.compile(
            r"\b(?:my goal is|i want to|i am trying to|i'm trying to)\b|\b(?:mi objetivo es|quiero|estoy intentando|trato de)\b",
            re.I,
        ),
    ),
    (
        "deadline",
        re.compile(
            r"\b(?:deadline|due (?:on|by)|by \w+day|by \d{4}-\d{2}-\d{2})\b|\b(?:fecha l[íi]mite|plazo|para el \w+|antes del? \d{4}-\d{2}-\d{2})\b",
            re.I,
        ),
    ),
)

_REJECTION_RE = re.compile(
    r"\b(?P<action>don't use|do not use|we ruled out|i rejected|forget|remove|no uses?|no utilices?|descart(?:ar?|amos?|o)?|rechac[eé]|rechaz(?:o|ar|amos)?|olvida|elimina)\s+(?P<target>[^.!?]{3,200})",
    re.I,
)

_realtime_users: set[str] = set()
_realtime_tasks: set[asyncio.Task[None]] = set()


def _source_version(operation: str, source_id: str, content: str, meta: Any = None) -> str:
    canonical = json.dumps(meta, sort_keys=True, default=str) if meta is not None else ""
    return hashlib.sha256(f"{operation}\0{source_id}\0{content}\0{canonical}".encode()).hexdigest()[
        :40
    ]


async def _enqueue_event(
    db: AsyncSession,
    *,
    user_id: str,
    conversation_id: str,
    operation: str,
    source_type: str,
    source_id: str,
    version: str,
    payload: dict[str, Any],
) -> TopicIngestionEvent:
    existing = await db.scalar(
        select(TopicIngestionEvent).where(
            TopicIngestionEvent.operation == operation,
            TopicIngestionEvent.source_type == source_type,
            TopicIngestionEvent.source_id == source_id,
            TopicIngestionEvent.source_version == version,
        )
    )
    if existing is not None:
        return existing
    event = TopicIngestionEvent(
        user_id=user_id,
        conversation_id=conversation_id,
        operation=operation,
        source_type=source_type,
        source_id=source_id,
        source_version=version,
        payload=payload,
    )
    db.add(event)
    await db.flush()
    return event


async def enqueue_message_event(
    db: AsyncSession,
    conversation: Conversation,
    message: Message,
    operation: str,
    *,
    payload: dict[str, Any] | None = None,
) -> TopicIngestionEvent:
    """Add a message mutation event to the caller's transaction."""
    version = _source_version(operation, message.id, message.content, message.meta)
    return await _enqueue_event(
        db,
        user_id=conversation.user_id,
        conversation_id=conversation.id,
        operation=operation,
        source_type="message",
        source_id=message.id,
        version=version,
        payload={"role": message.role, **(payload or {})},
    )


async def enqueue_conversation_event(
    db: AsyncSession, conversation: Conversation, operation: str
) -> TopicIngestionEvent:
    version = _source_version(operation, conversation.id, str(conversation.updated_at))
    return await _enqueue_event(
        db,
        user_id=conversation.user_id,
        conversation_id=conversation.id,
        operation=operation,
        source_type="conversation",
        source_id=conversation.id,
        version=version,
        payload={"is_deleted": conversation.is_deleted},
    )


def schedule_realtime_ingestion(user_id: str) -> None:
    """Start one process-local catch-up task; the durable queue remains authoritative."""
    if user_id in _realtime_users:
        return
    try:
        task = asyncio.create_task(_run_realtime(user_id))
    except RuntimeError:
        return
    _realtime_users.add(user_id)
    _realtime_tasks.add(task)
    task.add_done_callback(_realtime_tasks.discard)


async def _run_realtime(user_id: str) -> None:
    try:
        async with db_session.async_session_maker() as db:
            service = TopicIngestionService(db)
            while await service.process_user(user_id):
                pass
    except Exception:
        logger.exception("Realtime topic ingestion failed for user %s", user_id)
    finally:
        _realtime_users.discard(user_id)


class TopicIngestionService:
    """Processes ordered events into conservative topic memberships/assertions."""

    def __init__(
        self,
        db: AsyncSession,
        embedding_provider: EmbeddingProvider | None = None,
    ):
        self.db = db
        self.embedding_provider = (
            embedding_provider if embedding_provider is not None else get_embedding_provider()
        )

    async def process_user(
        self,
        user_id: str,
        limit: int | None = None,
        *,
        until_event_id: int | None = None,
        commit_each: bool = True,
        raise_on_error: bool = False,
    ) -> int:
        """Process a bounded ordered queue for one user."""
        batch_size = limit or get_settings().topic_realtime_batch_size
        filters = [
            TopicIngestionEvent.user_id == user_id,
            TopicIngestionEvent.processed_at.is_(None),
        ]
        if until_event_id is not None:
            filters.append(TopicIngestionEvent.id <= until_event_id)
        events = list(
            (
                await self.db.scalars(
                    select(TopicIngestionEvent)
                    .where(*filters)
                    .order_by(TopicIngestionEvent.id)
                    .limit(batch_size)
                )
            ).all()
        )
        processed = 0
        for event in events:
            event_id = event.id
            try:
                await self.process_event(event)
                if commit_each:
                    await self.db.commit()
                processed += 1
            except Exception as error:
                if raise_on_error:
                    raise
                await self.db.rollback()
                failed = await self.db.get(TopicIngestionEvent, event_id)
                if failed is not None:
                    failed.attempts += 1
                    failed.last_error = str(error)[:2000]
                    await self.db.commit()
                logger.exception("Topic ingestion event %s failed", event.id)
                break
        return processed

    async def process_event(self, event: TopicIngestionEvent) -> list[Topic]:
        if event.processed_at is not None:
            return []
        await self.db.flush()
        if event.id is None:
            try:
                await self.db.refresh(event, attribute_names=["id"])
            except (InvalidRequestError, NoResultFound) as error:
                raise RuntimeError("topic ingestion event is not persisted") from error
        if event.id is None:
            raise RuntimeError("topic ingestion event has no database watermark")
        event_id = event.id
        if event.source_type == "conversation":
            affected = await self._invalidate_conversation(event)
        elif event.operation == "delete":
            affected = await self._revoke_message(event)
        else:
            affected = await self._ingest_message(event)
        now = datetime.now(UTC)
        for topic in affected:
            topic.dirty_since = topic.dirty_since or now
            topic.updated_at = now
        event.processed_at = now
        state = await self.db.get(TopicIngestionState, event.user_id)
        if state is None:
            state = TopicIngestionState(user_id=event.user_id)
            self.db.add(state)
        state.last_realtime_event_id = max(state.last_realtime_event_id or 0, event_id)
        state.updated_at = now
        await self.db.flush()
        return affected

    async def _ingest_message(self, event: TopicIngestionEvent) -> list[Topic]:
        message = await self.db.scalar(
            select(Message)
            .join(Conversation, Conversation.id == Message.conversation_id)
            .where(
                Message.id == event.source_id,
                Conversation.user_id == event.user_id,
                Conversation.is_deleted.is_(False),
            )
        )
        if message is None:
            return await self._revoke_message(event)
        conversation = await self.db.get(Conversation, message.conversation_id)
        if conversation is None:
            return []
        # The conversation may be a stale identity-map instance from a
        # long-lived request session (e.g. an SSE turn that outlived a user
        # topic switch). Reload the authoritative active-topic state so
        # ingestion never clobbers a deliberate user selection.
        await self.db.refresh(conversation, attribute_names=["active_topic_id", "topic_is_pinned"])
        if event.operation in {"edit", "backfill"}:
            await self._remove_message_derivations(message.id)
        topic = await self._choose_topic(conversation, message)
        if topic is None:
            return []
        await self._ensure_membership(message, topic, conversation)
        activity_at = self._as_utc(message.created_at or datetime.now(UTC))
        if topic.last_active_at is not None:
            topic.last_active_at = self._as_utc(topic.last_active_at)
        if topic.last_active_at is None or activity_at > topic.last_active_at:
            topic.last_active_at = activity_at
        topic.signal = (
            self._historical_signal(activity_at) if event.operation == "backfill" else "active now"
        )
        if conversation.is_primary:
            await self._consider_active_topic(conversation, topic)
        if message.role == "user":
            await self._extract_user_assertions(topic, message, event.user_id)
        return [topic]

    async def _ensure_membership(
        self, message: Message, topic: Topic, conversation: Conversation
    ) -> None:
        membership = await self.db.get(MessageTopic, (message.id, topic.id))
        if membership is None:
            membership = MessageTopic(
                message_id=message.id,
                topic_id=topic.id,
                confidence=0.9 if conversation.active_topic_id == topic.id else 0.65,
                is_primary=True,
                segment_start=0,
                segment_end=len(message.content),
                source_authority=self._authority(message.role),
            )
            self.db.add(membership)
            topic.mention_count += 1

    async def _choose_topic(self, conversation: Conversation, message: Message) -> Topic | None:
        if conversation.active_topic_id and conversation.topic_is_pinned:
            return await self.db.get(Topic, conversation.active_topic_id)
        if not conversation.is_primary:
            return await self._choose_thread_topic(conversation, message)
        if message.role != "user":
            return await self._choose_continuation_topic(conversation, message)
        return await self._choose_primary_user_topic(conversation, message)

    async def _choose_thread_topic(
        self, conversation: Conversation, message: Message
    ) -> Topic | None:
        prior = await self._previous_conversation_topic(conversation, message)
        if prior is not None:
            return prior
        if self._is_background_conversation(conversation):
            return None
        label = self._derive_label(conversation.title or message.content)
        if label == "New topic":
            return None
        return await self._get_or_create_history_topic(
            conversation.user_id, label, last_active_at=message.created_at
        )

    async def _choose_continuation_topic(
        self, conversation: Conversation, message: Message
    ) -> Topic | None:
        prior_topic_id = await self.db.scalar(
            select(MessageTopic.topic_id)
            .join(Message, Message.id == MessageTopic.message_id)
            .where(Message.conversation_id == conversation.id, Message.seq < message.seq)
            .order_by(Message.seq.desc())
            .limit(1)
        )
        if prior_topic_id:
            return await self.db.get(Topic, prior_topic_id)
        if conversation.active_topic_id:
            return await self.db.get(Topic, conversation.active_topic_id)
        return None

    async def _choose_primary_user_topic(
        self, conversation: Conversation, message: Message
    ) -> Topic | None:
        # An unpinned primary conversation keeps whatever topic the user last
        # landed on (combine / PATCH topic_id set it without pinning). Route
        # only when no selection exists; _consider_active_topic then seeds it.
        if conversation.active_topic_id:
            return await self.db.get(Topic, conversation.active_topic_id)
        topics = list(
            (
                await self.db.scalars(
                    select(Topic).where(
                        Topic.user_id == conversation.user_id, Topic.status == "active"
                    )
                )
            ).all()
        )
        content_vector: list[float] | None = None
        if self.embedding_provider is not None and message.content:
            try:
                vectors = await self.embedding_provider.embed([message.content[:500]])
                if vectors:
                    content_vector = vectors[0]
            except Exception:
                logger.warning("Failed to embed message content for topic routing", exc_info=True)
                content_vector = None

        best = self._best_topic_match(message.content, topics, content_vector=content_vector)
        if best is not None:
            return best
        label = self._derive_label(message.content)
        return await self._get_or_create_history_topic(
            conversation.user_id, label, last_active_at=message.created_at
        )

    def _best_topic_match(
        self,
        content: str,
        topics: list[Topic],
        *,
        content_vector: list[float] | None = None,
    ) -> Topic | None:
        if content_vector:
            best_semantic: Topic | None = None
            best_sim = 0.0
            for candidate in topics:
                if candidate.centroid_embedding is not None:
                    sim = self._cosine_sim(content_vector, list(candidate.centroid_embedding))
                    if sim > best_sim:
                        best_sim = sim
                        best_semantic = candidate
            if best_semantic is not None and best_sim >= 0.72:
                return best_semantic

        message_terms = self._terms(content)
        best: Topic | None = None
        best_score = 0.0
        for candidate in topics:
            label_terms = self._terms(candidate.label)
            if not label_terms:
                continue
            score = len(message_terms & label_terms) / len(label_terms)
            if score > best_score:
                best, best_score = candidate, score
        return best if best is not None and best_score >= 0.34 else None

    @staticmethod
    def _cosine_sim(vec_a: list[float], vec_b: list[float]) -> float:
        if len(vec_a) != len(vec_b):
            return 0.0
        dot = sum(a * b for a, b in zip(vec_a, vec_b, strict=True))
        norm_a = sum(a * a for a in vec_a) ** 0.5
        norm_b = sum(b * b for b in vec_b) ** 0.5
        return dot / (norm_a * norm_b) if norm_a and norm_b else 0.0

    async def _previous_conversation_topic(
        self, conversation: Conversation, message: Message
    ) -> Topic | None:
        topic_id = await self.db.scalar(
            select(MessageTopic.topic_id)
            .join(Message, Message.id == MessageTopic.message_id)
            .where(Message.conversation_id == conversation.id, Message.id != message.id)
            .order_by(Message.seq)
            .limit(1)
        )
        return await self.db.get(Topic, topic_id) if topic_id else None

    async def _get_or_create_history_topic(
        self, user_id: str, label: str, *, last_active_at: datetime | None
    ) -> Topic:
        normalized = normalize_topic_label(label)
        # Match at ANY depth: a label that deterministic hierarchy or the
        # curator already grouped under a parent must be reused, not
        # re-created as a duplicate root (that duplicate then collides with
        # the (user, parent, label) unique key during the next grouping).
        existing = await self.db.scalar(
            select(Topic).where(
                Topic.user_id == user_id,
                Topic.normalized_label == normalized,
                Topic.status == "active",
            )
        )
        if existing is not None:
            return existing
        topic = Topic(
            id=str(uuid.uuid4()),
            user_id=user_id,
            label=label,
            normalized_label=normalized,
            origin="history",
            base_score=0.5,
            signal=None,
            last_active_at=last_active_at or datetime.now(UTC),
            dirty_since=datetime.now(UTC),
        )
        self.db.add(topic)
        await self.db.flush()
        return topic

    async def _consider_active_topic(self, conversation: Conversation, candidate: Topic) -> None:
        """Seed the active topic when unset; never override a user selection.

        The primary chat's active topic belongs to the user (topic switch /
        activate / landing all pin or set it deliberately). Ingestion may only
        fill in the very first topic for a topic-less conversation; it must
        never redirect an existing selection, pinned or not (bug report
        1ba9a9f8: the view jumped to an unselected topic seconds after
        selection because a routed message force-switched it).
        """
        if conversation.active_topic_id is not None:
            return
        conversation.active_topic_id = candidate.id
        conversation.context_version += 1

    async def _extract_user_assertions(self, topic: Topic, message: Message, user_id: str) -> None:
        await self._apply_rejection(topic, message, user_id)
        candidates: list[tuple[str, str]] = []
        text = " ".join(message.content.split())[:1600]
        for kind, pattern in _ASSERTION_PATTERNS:
            if pattern.search(text):
                candidates.append((kind, text))
        if text.endswith("?"):
            candidates.append(("open_loop", text))
        for kind, content in candidates:
            normalized_key = hashlib.sha256(
                f"{kind}\0{normalize_topic_label(content)}".encode()
            ).hexdigest()
            assertion = await self.db.scalar(
                select(TopicAssertion).where(
                    TopicAssertion.topic_id == topic.id,
                    TopicAssertion.normalized_key == normalized_key,
                )
            )
            if assertion is None:
                assertion = TopicAssertion(
                    id=str(uuid.uuid4()),
                    topic_id=topic.id,
                    kind=kind,
                    content=content,
                    normalized_key=normalized_key,
                    status="active",
                    authority="explicit_user_statement",
                    confidence=0.9,
                )
                if self.embedding_provider is not None:
                    try:
                        vectors = await self.embedding_provider.embed([content])
                        if vectors:
                            emb = vectors[0]
                            assertion.embedding = emb
                            if topic.centroid_embedding is None:
                                topic.centroid_embedding = emb
                            else:
                                old_vec = list(topic.centroid_embedding)
                                if len(old_vec) == len(emb):
                                    blended = [
                                        0.8 * o + 0.2 * n for o, n in zip(old_vec, emb, strict=True)
                                    ]
                                    norm = sum(x * x for x in blended) ** 0.5
                                    topic.centroid_embedding = (
                                        [x / norm for x in blended] if norm > 0 else blended
                                    )
                    except Exception:
                        logger.warning("Failed to generate embedding for assertion", exc_info=True)
                self.db.add(assertion)
                await self.db.flush()
            else:
                assertion.last_confirmed_at = datetime.now(UTC)
                assertion.confidence = min(1.0, assertion.confidence + 0.03)
            evidence = await self.db.get(
                TopicAssertionEvidence, (assertion.id, message.id, 0, len(message.content))
            )
            if evidence is None:
                self.db.add(
                    TopicAssertionEvidence(
                        assertion_id=assertion.id,
                        message_id=message.id,
                        segment_start=0,
                        segment_end=len(message.content),
                        relation="supports",
                        source_span_hash=hashlib.sha256(message.content.encode()).hexdigest(),
                    )
                )

    async def _apply_rejection(self, topic: Topic, message: Message, user_id: str) -> None:
        match = _REJECTION_RE.search(message.content)
        if match is None:
            return
        target = normalize_topic_label(match.group("target"))
        assertions = list(
            (
                await self.db.scalars(
                    select(TopicAssertion).where(
                        TopicAssertion.topic_id == topic.id,
                        TopicAssertion.status.in_(("active", "uncertain")),
                    )
                )
            ).all()
        )
        matched = [
            item
            for item in assertions
            if target in normalize_topic_label(item.content)
            or normalize_topic_label(item.content) in target
        ]
        if len(matched) != 1:
            return
        assertion = matched[0]
        assertion.status = "rejected"
        privacy = match.group("action").casefold() in {"forget", "remove"}
        existing = await self.db.scalar(
            select(TopicExclusion).where(
                TopicExclusion.user_id == user_id,
                TopicExclusion.scope == "assertion",
                TopicExclusion.target_id == assertion.id,
                TopicExclusion.revoked_at.is_(None),
            )
        )
        if existing is None:
            self.db.add(
                TopicExclusion(
                    id=str(uuid.uuid4()),
                    user_id=user_id,
                    topic_id=topic.id,
                    scope="assertion",
                    target_id=assertion.id,
                    origin="explicit_user_statement",
                    reason=None if privacy else "Explicitly rejected by the user",
                    source_message_id=message.id,
                    is_privacy_deletion=privacy,
                )
            )
        self.db.add(
            TopicAssertionEvidence(
                assertion_id=assertion.id,
                message_id=message.id,
                segment_start=match.start(),
                segment_end=match.end(),
                relation="rejects",
                source_span_hash=hashlib.sha256(
                    message.content[match.start() : match.end()].encode()
                ).hexdigest(),
            )
        )

    async def _revoke_message(self, event: TopicIngestionEvent) -> list[Topic]:
        topic_ids = list(
            (
                await self.db.scalars(
                    select(MessageTopic.topic_id).where(MessageTopic.message_id == event.source_id)
                )
            ).all()
        )
        await self._remove_message_derivations(event.source_id)
        return list((await self.db.scalars(select(Topic).where(Topic.id.in_(topic_ids)))).all())

    async def _remove_message_derivations(self, message_id: str) -> None:
        memberships = list(
            (
                await self.db.scalars(
                    select(MessageTopic).where(MessageTopic.message_id == message_id)
                )
            ).all()
        )
        assertion_ids = list(
            (
                await self.db.scalars(
                    select(TopicAssertionEvidence.assertion_id).where(
                        TopicAssertionEvidence.message_id == message_id
                    )
                )
            ).all()
        )
        await self.db.execute(
            delete(TopicAssertionEvidence).where(TopicAssertionEvidence.message_id == message_id)
        )
        await self.db.execute(delete(MessageTopic).where(MessageTopic.message_id == message_id))
        for membership in memberships:
            topic = await self.db.get(Topic, membership.topic_id)
            if topic is not None:
                topic.mention_count = max(0, topic.mention_count - 1)
        for assertion_id in assertion_ids:
            remaining = await self.db.scalar(
                select(TopicAssertionEvidence.assertion_id)
                .where(TopicAssertionEvidence.assertion_id == assertion_id)
                .limit(1)
            )
            if remaining is None:
                assertion = await self.db.get(TopicAssertion, assertion_id)
                if assertion is not None:
                    assertion.status = "uncertain"

    async def _invalidate_conversation(self, event: TopicIngestionEvent) -> list[Topic]:
        topic_ids = list(
            (
                await self.db.scalars(
                    select(MessageTopic.topic_id)
                    .join(Message, Message.id == MessageTopic.message_id)
                    .where(Message.conversation_id == event.source_id)
                    .distinct()
                )
            ).all()
        )
        message_ids = list(
            (
                await self.db.scalars(
                    select(Message.id).where(Message.conversation_id == event.source_id)
                )
            ).all()
        )
        for message_id in message_ids:
            await self._remove_message_derivations(message_id)
        return list((await self.db.scalars(select(Topic).where(Topic.id.in_(topic_ids)))).all())

    @staticmethod
    def _authority(role: str) -> str:
        return {
            "user": "explicit_user_statement",
            "tool_result": "tool_result",
            "assistant": "assistant_proposal",
        }.get(role, "untrusted_context")

    @staticmethod
    def _terms(text: str) -> set[str]:
        return {
            token for token in re.findall(r"[\w-]{3,}", text.casefold()) if token not in _STOP_WORDS
        }

    @classmethod
    def _derive_label(cls, text: str) -> str:
        cleaned = re.sub(r"https?://\S+", "", text)
        words = [
            word
            for word in re.findall(r"[\w-]+", cleaned)
            if len(word) >= 3 and word.casefold() not in _STOP_WORDS
        ][:4]
        return " ".join(words).strip().title()[:200] if words else "New topic"

    @staticmethod
    def _is_background_conversation(conversation: Conversation) -> bool:
        return (conversation.title or "").lstrip().startswith("⏰")

    @staticmethod
    def _historical_signal(activity_at: datetime) -> str | None:
        age = datetime.now(UTC) - TopicIngestionService._as_utc(activity_at)
        if age.days < 2:
            return "recently discussed"
        if age.days < 14:
            return "this month"
        return None

    @staticmethod
    def _as_utc(value: datetime) -> datetime:
        return value.replace(tzinfo=UTC) if value.tzinfo is None else value.astimezone(UTC)

    async def archive_orphaned_history_topics(self, user_id: str) -> int:
        """Hide superseded derived topics after a replay/backfill repair."""
        child_topic = aliased(Topic)
        topics = list(
            (
                await self.db.scalars(
                    select(Topic).where(
                        Topic.user_id == user_id,
                        Topic.origin == "history",
                        Topic.status == "active",
                        ~exists(
                            select(MessageTopic.message_id).where(MessageTopic.topic_id == Topic.id)
                        ),
                        ~exists(
                            select(child_topic.id).where(
                                child_topic.parent_id == Topic.id,
                                child_topic.status == "active",
                            )
                        ),
                    )
                )
            ).all()
        )
        for topic in topics:
            topic.status = "archived"
            topic.dirty_since = None
        return len(topics)
