"""Atomic topic-thread creation, legacy switching, and archive resumption."""

from __future__ import annotations

import hashlib
import json
import uuid
from dataclasses import dataclass
from datetime import UTC, datetime

from sqlalchemy import delete, func, or_, select, update
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.models.conversation import Conversation
from app.models.message import Message
from app.models.user import User
from app.models.workflow_run import WorkflowRun
from app.topics.active_context_schemas import (
    ActiveContextItemOut,
    ActiveContextTopic,
    TopicSwitchResponse,
)
from app.topics.generation_state import has_active_generation
from app.topics.models import (
    ActiveContextItem,
    Topic,
    TopicArchive,
    TopicIngestionEvent,
    TopicRelation,
    TopicSwitchOperation,
)
from app.topics.topic_context_compiler import TopicContextCompiler
from app.topics.topic_description_helper import get_topic_high_level_description
from app.topics.topic_service import (
    PrimaryConversationRequiredError,
    TopicNotFoundError,
    TopicService,
)


class TopicSwitchError(Exception):
    pass


@dataclass(slots=True)
class _ArchiveSnapshot:
    archive_id: str


class TopicSwitchService:
    def __init__(self, db: AsyncSession):
        self.db = db
        self.topics = TopicService(db)

    @staticmethod
    def _new_thread(source: Conversation, topic: Topic) -> Conversation:
        return Conversation(
            id=str(uuid.uuid4()),
            user_id=source.user_id,
            title=topic.label,
            model=source.model,
            system_prompt=source.system_prompt,
            thinking_level=source.thinking_level,
            use_memory=source.use_memory,
            use_knowledge_base=source.use_knowledge_base,
            enabled_tools=list(source.enabled_tools) if source.enabled_tools is not None else None,
            is_primary=False,
            context_version=1,
            session_epoch=0,
        )

    async def start(
        self,
        *,
        conversation_id: str,
        user: User,
        topic_id: str | None,
        label: str | None,
        idempotency_key: str,
        archive: bool,
        retain_pinned: bool,
        settings: dict | None = None,
    ) -> TopicSwitchResponse:
        """Create an independent topic thread without changing the source session."""
        settings = settings or {}
        fingerprint = self._request_fingerprint(
            topic_id=topic_id,
            label=label,
            archive=archive,
            retain_pinned=retain_pinned,
            mode="start",
            settings=settings,
        )
        try:
            source = await self._get_owned(conversation_id, user.email, for_update=True)
            previous = await self.db.scalar(
                select(TopicSwitchOperation).where(
                    TopicSwitchOperation.conversation_id == source.id,
                    TopicSwitchOperation.idempotency_key == idempotency_key,
                    TopicSwitchOperation.user_id == user.email,
                )
            )
            if previous is not None:
                if previous.request_fingerprint != fingerprint:
                    raise TopicSwitchError("idempotency_key_reused")
                return TopicSwitchResponse.model_validate(previous.response_json)
            topic = await self.topics.resolve_target(user.email, topic_id=topic_id, label=label)
            target = self._new_thread(source, topic)
            for field, value in settings.items():
                if field == "model" and value is None:
                    continue
                setattr(target, field, value)
            self.db.add(target)
            self.topics.apply_activation(target, topic)
            await self.db.flush()
            compiler = TopicContextCompiler(self.db)
            retained = []
            if retain_pinned:
                pins = list(
                    (
                        await self.db.scalars(
                            select(ActiveContextItem).where(
                                ActiveContextItem.conversation_id == source.id,
                                ActiveContextItem.state == "pinned",
                            )
                        )
                    ).all()
                )
                eligible, _ = await compiler.eligible_context_state(topic, pins)
                for item in eligible:
                    copied = ActiveContextItem(
                        id=str(uuid.uuid4()),
                        conversation_id=target.id,
                        source_type=item.source_type,
                        source_id=item.source_id,
                        source_meta=dict(item.source_meta or {}),
                        topic_id=item.topic_id,
                        state="pinned",
                        reason=item.reason,
                        relevance_score=item.relevance_score,
                        token_count=item.token_count,
                    )
                    self.db.add(copied)
                    retained.append(copied)
                await self.db.flush()
            await compiler.materialize_baseline(target, topic)
            parent = await self.db.get(Topic, topic.parent_id) if topic.parent_id else None
            response = TopicSwitchResponse(
                idempotency_key=idempotency_key,
                conversation_id=target.id,
                topic=ActiveContextTopic(
                    id=topic.id,
                    label=topic.label,
                    parent_id=topic.parent_id,
                    parent_label=parent.label if parent else None,
                    description=get_topic_high_level_description(topic, parent),
                    pinned=True,
                ),
                context_version=target.context_version,
                session_epoch=target.session_epoch,
                archived=False,
                context_status=await self.topics.context_status(topic),
                retained_items=[ActiveContextItemOut.model_validate(item) for item in retained],
                next_turn_summary=f"Started a new thread about {topic.label}.",
            )
            self.db.add(
                TopicSwitchOperation(
                    id=str(uuid.uuid4()),
                    conversation_id=source.id,
                    user_id=user.email,
                    idempotency_key=idempotency_key,
                    request_fingerprint=fingerprint,
                    response_json=response.model_dump(mode="json"),
                )
            )
            await self.db.commit()
            return response
        except Exception:
            await self.db.rollback()
            raise

    async def switch(
        self,
        *,
        conversation_id: str,
        user: User,
        topic_id: str | None,
        label: str | None,
        idempotency_key: str,
        archive: bool,
        retain_pinned: bool,
    ) -> TopicSwitchResponse:
        """Commit one serialized session boundary and replay its stored response on retry."""
        fingerprint = self._request_fingerprint(
            topic_id=topic_id,
            label=label,
            archive=archive,
            retain_pinned=retain_pinned,
        )
        try:
            conversation = await self._get_primary(conversation_id, user.email, for_update=True)
            previous = await self.db.scalar(
                select(TopicSwitchOperation).where(
                    TopicSwitchOperation.conversation_id == conversation.id,
                    TopicSwitchOperation.idempotency_key == idempotency_key,
                )
            )
            if previous is not None:
                if previous.request_fingerprint != fingerprint:
                    raise TopicSwitchError("idempotency_key_reused")
                return TopicSwitchResponse.model_validate(previous.response_json)

            new_topic = await self.topics.resolve_target(user.email, topic_id=topic_id, label=label)
            prior_topic = (
                conversation.active_topic
                if conversation.active_topic is not None
                else (
                    await self.db.get(Topic, conversation.active_topic_id)
                    if conversation.active_topic_id
                    else None
                )
            )
            archive_id = (
                (
                    await self._archive(
                        conversation=conversation, user=user, prior_topic=prior_topic
                    )
                ).archive_id
                if archive
                else None
            )
            retained_items = await self._advance_session(conversation, retain_pinned=retain_pinned)
            self.topics.apply_activation(conversation, new_topic)
            conversation.title = new_topic.label
            conversation.context_summary = None
            conversation.context_summary_until_id = None
            await TopicContextCompiler(self.db).materialize_baseline(
                conversation,
                new_topic,
            )
            await self.db.flush()
            await self.db.refresh(new_topic)

            parent = await self.db.get(Topic, new_topic.parent_id) if new_topic.parent_id else None
            topic_desc = get_topic_high_level_description(new_topic, parent)
            context_status = await self.topics.context_status(new_topic)
            response = TopicSwitchResponse(
                idempotency_key=idempotency_key,
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
                context_status=context_status,
                retained_items=retained_items,
                next_turn_summary=(
                    f"Switched to {new_topic.label}. "
                    f"{len(retained_items)} pinned source(s) retained."
                ),
            )
            self.db.add(
                TopicSwitchOperation(
                    id=str(uuid.uuid4()),
                    conversation_id=conversation.id,
                    user_id=user.email,
                    idempotency_key=idempotency_key,
                    request_fingerprint=fingerprint,
                    response_json=response.model_dump(mode="json"),
                )
            )
            await self.db.commit()
            return response
        except TopicNotFoundError as exc:
            await self.db.rollback()
            raise TopicSwitchError("topic_not_found") from exc
        except PrimaryConversationRequiredError as exc:
            await self.db.rollback()
            raise TopicSwitchError("primary_required") from exc
        except TopicSwitchError:
            await self.db.rollback()
            raise
        except Exception:
            await self.db.rollback()
            raise

    async def combine(
        self,
        *,
        conversation_id: str,
        user: User,
        topic_id: str | None,
        label: str | None,
        idempotency_key: str,
    ) -> TopicSwitchResponse:
        """Combine an additional topic with the active topic without archiving or clearing messages."""
        fingerprint = self._request_fingerprint(
            topic_id=topic_id,
            label=label,
            archive=False,
            retain_pinned=True,
            mode="combine",
        )
        try:
            conversation = await self._get_owned(conversation_id, user.email, for_update=True)
            if not conversation.is_primary and not conversation.active_topic_id:
                raise PrimaryConversationRequiredError
            previous = await self.db.scalar(
                select(TopicSwitchOperation).where(
                    TopicSwitchOperation.conversation_id == conversation.id,
                    TopicSwitchOperation.idempotency_key == idempotency_key,
                )
            )
            if previous is not None:
                if previous.request_fingerprint != fingerprint:
                    raise TopicSwitchError("idempotency_key_reused")
                return TopicSwitchResponse.model_validate(previous.response_json)

            target_topic = await self.topics.resolve_target(
                user.email, topic_id=topic_id, label=label
            )
            prior_topic = (
                conversation.active_topic
                if conversation.active_topic is not None
                else (
                    await self.db.get(Topic, conversation.active_topic_id)
                    if conversation.active_topic_id
                    else None
                )
            )
            if prior_topic is None:
                self.topics.apply_activation(conversation, target_topic)
                active_topic = target_topic
                combined_labels: list[str] = []
            else:
                active_topic = prior_topic
                if prior_topic.id != target_topic.id:
                    for source, target in (
                        (prior_topic.id, target_topic.id),
                        (target_topic.id, prior_topic.id),
                    ):
                        relation = await self.db.scalar(
                            select(TopicRelation).where(
                                TopicRelation.user_id == user.email,
                                TopicRelation.source_topic_id == source,
                                TopicRelation.target_topic_id == target,
                                TopicRelation.relation_type == "combined",
                            )
                        )
                        if relation is None:
                            self.db.add(
                                TopicRelation(
                                    id=str(uuid.uuid4()),
                                    user_id=user.email,
                                    source_topic_id=source,
                                    target_topic_id=target,
                                    relation_type="combined",
                                    confidence=1.0,
                                    metadata_json={"user_combined": True},
                                )
                            )
                    conversation.title = f"{prior_topic.label} + {target_topic.label}"[:200]
                    target_topic.dirty_since = target_topic.dirty_since or datetime.now(UTC)
                    await self.db.flush()
                relations = list(
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
                combined_ids = {
                    relation.target_topic_id
                    if relation.source_topic_id == prior_topic.id
                    else relation.source_topic_id
                    for relation in relations
                }
                combined_labels = (
                    list(
                        (
                            await self.db.scalars(
                                select(Topic.label).where(Topic.id.in_(combined_ids))
                            )
                        ).all()
                    )
                    if combined_ids
                    else []
                )

            conversation.context_version += 1
            await self.db.flush()
            await self.db.refresh(active_topic)
            parent = (
                await self.db.get(Topic, active_topic.parent_id) if active_topic.parent_id else None
            )
            response = TopicSwitchResponse(
                idempotency_key=idempotency_key,
                conversation_id=conversation.id,
                topic=ActiveContextTopic(
                    id=active_topic.id,
                    label=conversation.title or active_topic.label,
                    parent_id=active_topic.parent_id,
                    parent_label=parent.label if parent else None,
                    description=get_topic_high_level_description(active_topic, parent),
                    pinned=conversation.topic_is_pinned,
                    combined_topics=combined_labels,
                ),
                context_version=conversation.context_version,
                session_epoch=conversation.session_epoch,
                archived=False,
                context_status=await self.topics.context_status(active_topic),
                retained_items=[],
                next_turn_summary=(
                    f"Context now covers {active_topic.label}"
                    + (f" and {target_topic.label}." if prior_topic else ".")
                ),
            )
            self.db.add(
                TopicSwitchOperation(
                    id=str(uuid.uuid4()),
                    conversation_id=conversation.id,
                    user_id=user.email,
                    idempotency_key=idempotency_key,
                    request_fingerprint=fingerprint,
                    response_json=response.model_dump(mode="json"),
                )
            )
            await self.db.commit()
            return response
        except (TopicNotFoundError, PrimaryConversationRequiredError):
            await self.db.rollback()
            raise
        except Exception:
            await self.db.rollback()
            raise

    async def list_archives(self, topic_id: str, user: User) -> list[TopicArchive]:
        topic = await self.topics.get_owned_topic(topic_id, user.email)
        if topic is None:
            raise TopicNotFoundError
        return list(
            (
                await self.db.scalars(
                    select(TopicArchive)
                    .where(TopicArchive.topic_id == topic_id, TopicArchive.user_id == user.email)
                    .order_by(TopicArchive.created_at.desc())
                )
            ).all()
        )

    async def list_conversations(
        self, topic_id: str, user: User, *, limit: int
    ) -> list[Conversation]:
        if await self.topics.get_owned_topic(topic_id, user.email) is None:
            raise TopicNotFoundError
        return list(
            (
                await self.db.scalars(
                    Conversation.active(user.email)
                    .where(Conversation.active_topic_id == topic_id)
                    .options(selectinload(Conversation.active_topic))
                    .order_by(Conversation.updated_at.desc(), Conversation.id)
                    .limit(limit)
                )
            ).all()
        )

    async def message_counts(self, conversations: list[Conversation]) -> dict[str, int]:
        """Count visible messages without loading entire topic transcripts."""
        if not conversations:
            return {}
        return dict(
            (
                await self.db.execute(
                    select(Message.conversation_id, func.count(Message.id))
                    .join(Conversation, Conversation.id == Message.conversation_id)
                    .where(
                        Conversation.id.in_([conversation.id for conversation in conversations]),
                        or_(
                            Conversation.is_primary.is_(False),
                            Message.session_epoch == Conversation.session_epoch,
                        ),
                    )
                    .group_by(Message.conversation_id)
                )
            ).all()
        )

    async def _archive_source(
        self, topic_id: str, archive_id: str, user: User, *, for_update: bool = False
    ) -> tuple[TopicArchive, Conversation, int]:
        if await self.topics.get_owned_topic(topic_id, user.email) is None:
            raise TopicNotFoundError
        statement = select(TopicArchive).where(
            TopicArchive.id == archive_id,
            TopicArchive.topic_id == topic_id,
            TopicArchive.user_id == user.email,
        )
        if for_update:
            statement = statement.with_for_update()
        archive = await self.db.scalar(statement)
        if archive is None:
            raise TopicNotFoundError
        # An active producer holds the source conversation row until its final
        # commit. Check before locking it so Continue fails promptly instead
        # of waiting for the whole turn and then silently promoting the epoch.
        if (
            for_update
            and not (archive.payload or {}).get("resumed_conversation_id")
            and has_active_generation(archive.conversation_id)
        ):
            raise TopicSwitchError("archive_inflight")
        source = await self._get_owned(archive.conversation_id, user.email, for_update=for_update)
        epoch = (archive.payload or {}).get("session_epoch")
        if isinstance(epoch, bool) or not isinstance(epoch, int) or epoch < 0:
            raise TopicSwitchError("invalid_archive_epoch")
        return archive, source, epoch

    async def resume_archive(self, topic_id: str, archive_id: str, user: User) -> Conversation:
        """Move a closed epoch once, preserving message identities and provenance."""
        try:
            archive, source, epoch = await self._archive_source(
                topic_id,
                archive_id,
                user,
                for_update=True,
            )
            resumed_id = (archive.payload or {}).get("resumed_conversation_id")
            if resumed_id:
                return await self._get_owned(resumed_id, user.email)
            if epoch >= source.session_epoch:
                raise TopicSwitchError("archive_not_closed")
            if has_active_generation(source.id):
                raise TopicSwitchError("archive_inflight")
            runs = list(
                (
                    await self.db.scalars(
                        select(WorkflowRun)
                        .where(
                            WorkflowRun.conversation_id == source.id,
                            WorkflowRun.user_id == user.email,
                            or_(
                                WorkflowRun.session_epoch == epoch,
                                WorkflowRun.session_epoch.is_(None),
                            ),
                        )
                        .with_for_update()
                    )
                ).all()
            )
            if any(run.status not in {"done", "error", "cancelled"} for run in runs):
                raise TopicSwitchError("archive_inflight")
            topic = await self.topics.get_owned_topic(topic_id, user.email)
            target = self._new_thread(source, topic)
            target.title = (archive.payload or {}).get("conversation_title") or topic.label
            target.session_epoch = epoch
            target.context_summary = (archive.payload or {}).get("context_summary")
            target.context_summary_until_id = (archive.payload or {}).get(
                "context_summary_until_id"
            )
            self.db.add(target)
            self.topics.apply_activation(target, topic)
            await self.db.flush()
            message_ids = list(
                (
                    await self.db.scalars(
                        select(Message.id).where(
                            Message.conversation_id == source.id,
                            Message.session_epoch == epoch,
                        )
                    )
                ).all()
            )
            await self.db.execute(
                update(Message)
                .where(
                    Message.conversation_id == source.id,
                    Message.session_epoch == epoch,
                )
                .values(conversation_id=target.id)
            )
            if message_ids:
                await self.db.execute(
                    update(TopicIngestionEvent)
                    .where(
                        TopicIngestionEvent.user_id == user.email,
                        TopicIngestionEvent.conversation_id == source.id,
                        TopicIngestionEvent.source_type == "message",
                        TopicIngestionEvent.source_id.in_(message_ids),
                    )
                    .values(conversation_id=target.id)
                )
            for run in runs:
                if run.session_epoch == epoch:
                    run.conversation_id = target.id
            archive.payload = dict(archive.payload or {}) | {"resumed_conversation_id": target.id}
            await TopicContextCompiler(self.db).materialize_baseline(target, topic)
            await self.db.commit()
            await self.db.refresh(target)
            return target
        except Exception:
            await self.db.rollback()
            raise

    async def get_archive_messages(
        self,
        topic_id: str,
        archive_id: str,
        user: User,
        *,
        before: str | None,
        limit: int,
    ) -> tuple[TopicArchive, int, list[Message], bool]:
        """Return one owned archive epoch as a bounded, read-only message page."""
        archive, source, epoch = await self._archive_source(topic_id, archive_id, user)
        resumed_id = (archive.payload or {}).get("resumed_conversation_id")
        if resumed_id:
            source = await self._get_owned(resumed_id, user.email)

        query = select(Message).where(
            Message.conversation_id == source.id,
            Message.session_epoch == epoch,
        )
        if before is not None:
            anchor_seq = await self.db.scalar(
                select(Message.seq).where(
                    Message.id == before,
                    Message.conversation_id == source.id,
                    Message.session_epoch == epoch,
                )
            )
            if anchor_seq is None:
                raise TopicNotFoundError
            query = query.where(Message.seq < anchor_seq)
        rows = list(
            (await self.db.scalars(query.order_by(Message.seq.desc()).limit(limit + 1))).all()
        )
        has_more = len(rows) > limit
        messages = rows[:limit]
        messages.reverse()
        return archive, epoch, messages, has_more

    async def _get_primary(
        self, conversation_id: str, user_email: str, *, for_update: bool = False
    ) -> Conversation:
        statement = (
            Conversation.active(user_email)
            .where(Conversation.id == conversation_id)
            .options(selectinload(Conversation.active_topic))
        )
        if for_update:
            statement = statement.with_for_update()
        conversation = await self.db.scalar(statement)
        if conversation is None or not conversation.is_primary:
            raise PrimaryConversationRequiredError
        return conversation

    async def _get_owned(
        self, conversation_id: str, user_email: str, *, for_update: bool = False
    ) -> Conversation:
        statement = (
            Conversation.active(user_email)
            .where(Conversation.id == conversation_id)
            .options(selectinload(Conversation.active_topic))
        )
        if for_update:
            statement = statement.with_for_update()
        conversation = await self.db.scalar(statement)
        if conversation is None:
            raise TopicNotFoundError
        return conversation

    async def _archive(
        self, *, conversation: Conversation, user: User, prior_topic: Topic | None
    ) -> _ArchiveSnapshot:
        message_count = (
            await self.db.scalar(
                select(func.count(Message.id)).where(
                    Message.conversation_id == conversation.id,
                    Message.session_epoch == conversation.session_epoch,
                )
            )
            or 0
        )
        archive = TopicArchive(
            id=str(uuid.uuid4()),
            user_id=user.email,
            topic_id=prior_topic.id if prior_topic else None,
            from_topic_id=prior_topic.id if prior_topic else None,
            conversation_id=conversation.id,
            message_count=message_count,
            payload={
                "topic_label": prior_topic.label if prior_topic else None,
                "conversation_title": conversation.title,
                "session_epoch": conversation.session_epoch,
                "context_summary": conversation.context_summary,
                "context_summary_until_id": conversation.context_summary_until_id,
            },
            short_summary=None,
            created_at=datetime.now(UTC),
        )
        self.db.add(archive)
        await self.db.flush()
        return _ArchiveSnapshot(archive_id=archive.id)

    async def _advance_session(
        self, conversation: Conversation, *, retain_pinned: bool
    ) -> list[ActiveContextItemOut]:
        retained = (
            list(
                (
                    await self.db.scalars(
                        select(ActiveContextItem).where(
                            ActiveContextItem.conversation_id == conversation.id,
                            ActiveContextItem.state == "pinned",
                        )
                    )
                ).all()
            )
            if retain_pinned
            else []
        )
        conversation.session_epoch += 1
        conversation.context_version += 1
        conversation.context_summary = None
        conversation.context_summary_until_id = None
        delete_items = delete(ActiveContextItem).where(
            ActiveContextItem.conversation_id == conversation.id
        )
        if retain_pinned:
            delete_items = delete_items.where(ActiveContextItem.state != "pinned")
        await self.db.execute(delete_items)
        await self.db.flush()
        return [ActiveContextItemOut.model_validate(item) for item in retained]

    @staticmethod
    def _request_fingerprint(
        *,
        topic_id: str | None,
        label: str | None,
        archive: bool,
        retain_pinned: bool,
        mode: str = "switch",
        settings: dict | None = None,
    ) -> str:
        payload = json.dumps(
            {
                "archive": archive,
                "label": " ".join((label or "").split()).casefold() or None,
                "mode": mode,
                "retain_pinned": retain_pinned,
                "topic_id": topic_id,
                **({"settings": settings} if settings is not None else {}),
            },
            sort_keys=True,
            separators=(",", ":"),
        )
        return hashlib.sha256(payload.encode()).hexdigest()
