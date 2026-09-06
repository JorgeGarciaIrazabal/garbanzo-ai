"""Evidence-first deterministic context-pack consolidation and promotion."""

from __future__ import annotations

import logging
import re
from typing import Any

from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.models.conversation import Conversation
from app.models.message import Message
from app.topics.consolidation.clusterer import TopicClusterer
from app.topics.consolidation.pack_builder import (
    PROMPT_VERSION,
    ContextPackBuilder,
)
from app.topics.consolidation.reconciler import TopicReconciler
from app.topics.consolidation.worker import ConsolidationWorker
from app.topics.models import (
    MessageTopic,
    Topic,
    TopicAssertion,
    TopicContextVersion,
    TopicExclusion,
    TopicIngestionEvent,
    TopicIngestionState,
)
from app.topics.topic_ingestion_service import TopicIngestionService
from app.topics.topic_semantic_curator import (
    CURATOR_PROMPT_VERSION,
    GRAPH_CURATOR_PROMPT_VERSION,
    ContextPackItem,
    CuratedContextPack,
    HierarchyProposal,
    NegativeGuardrailItem,
    SemanticCuratorOutput,
    TopicGraphProposal,
    TopicSemanticCurator,
    UserTopicGraphCuratorOutput,
    UserTopicGraphCuratorResult,
)

logger = logging.getLogger(__name__)

_GRAPH_TOPIC_LIMIT = 45
_GRAPH_EVIDENCE_PER_TOPIC = 3
_GRAPH_CANDIDATES_PER_TOPIC = 6
_GRAPH_EXCERPT_CHARS = 800
_REJECTION_TEXT = re.compile(r"\b(?:don't use|do not use|ruled out|rejected|forget|remove)\b", re.I)

__all__ = [
    "ContextPackItem",
    "CuratedContextPack",
    "NegativeGuardrailItem",
    "TopicConsolidationService",
]


class TopicConsolidationService:
    """Build immutable packs from original active evidence, never prior prose."""

    def __init__(self, db: AsyncSession):
        self.db = db
        # ``claim_dirty_users`` is also useful to callers that keep the same
        # service/session open (notably tests and one-shot maintenance runs).
        # The scheduled job passes the owner explicitly because its claim and
        # processing sessions are deliberately short-lived.
        self._claim_owner: str | None = None

    async def consolidate_topic(
        self,
        topic: Topic,
        *,
        source_event_watermark: int | None = None,
        graph_curator: UserTopicGraphCuratorResult | None = None,
        use_focused_curator: bool = True,
    ) -> TopicContextVersion:
        assertions = list(
            (
                await self.db.scalars(
                    select(TopicAssertion)
                    .where(TopicAssertion.topic_id == topic.id)
                    .options(selectinload(TopicAssertion.evidence))
                    .order_by(TopicAssertion.last_confirmed_at.desc())
                )
            ).all()
        )
        exclusions = list(
            (
                await self.db.scalars(
                    select(TopicExclusion).where(
                        TopicExclusion.user_id == topic.user_id,
                        (TopicExclusion.topic_id == topic.id) | TopicExclusion.topic_id.is_(None),
                        TopicExclusion.revoked_at.is_(None),
                    )
                )
            ).all()
        )
        valid_evidence = await self._valid_evidence(topic.user_id, topic.id)
        deterministic_pack = ContextPackBuilder.build_deterministic_pack(
            topic, assertions, exclusions, valid_evidence
        )
        await self.validate_pack(topic, deterministic_pack, valid_evidence)

        pack = deterministic_pack
        provider_name = "deterministic"
        model_id: str | None = None
        prompt_version = PROMPT_VERSION
        user_topics = await self._user_topics(topic.user_id)

        async def validate_semantic_output(output: SemanticCuratorOutput) -> None:
            await self.validate_semantic_pack(
                topic,
                output.context_pack,
                deterministic_pack,
                valid_evidence,
            )
            self._validated_hierarchy_proposal(
                topic,
                output.hierarchy_proposals,
                user_topics,
            )

        semantic = None
        if graph_curator is None and use_focused_curator:
            # Explicit single-topic preparation may use a focused model call.
            # The hourly job passes one user-level result to every topic and
            # must not fan out into one model call per topic.
            semantic = await TopicSemanticCurator().curate(
                current_topic=deterministic_pack.topic,
                deterministic_pack=deterministic_pack,
                candidate_topics=self._hierarchy_candidates(topic, user_topics),
                validator=validate_semantic_output,
            )
        if semantic is not None:
            proposal = self._validated_hierarchy_proposal(
                topic,
                semantic.output.hierarchy_proposals,
                user_topics,
            )
            pack = semantic.output.context_pack
            if proposal is not None and proposal.confidence >= 0.75:
                topic.parent_id = proposal.parent_topic_id
                pack.topic["parent_id"] = proposal.parent_topic_id
            provider_name = semantic.provider
            model_id = semantic.model
            prompt_version = CURATOR_PROMPT_VERSION
        elif graph_curator is not None and (topic.topic_metadata or {}).get("semantic_curator"):
            provider_name = graph_curator.provider
            model_id = graph_curator.model
            prompt_version = GRAPH_CURATOR_PROMPT_VERSION
        current_pack = await self._latest_valid_pack(topic.id)
        current_max = await self.db.scalar(
            select(func.max(TopicContextVersion.version)).where(
                TopicContextVersion.topic_id == topic.id
            )
        )
        state = await self.db.get(TopicIngestionState, topic.user_id)
        watermark = source_event_watermark
        if watermark is None:
            watermark = state.last_realtime_event_id if state else 0

        return await ContextPackBuilder.create_context_version(
            self.db,
            topic,
            pack,
            source_event_watermark=watermark,
            current_pack=current_pack,
            current_max=current_max,
            model_id=model_id,
            provider_name=provider_name,
            prompt_version=prompt_version,
            is_semantic=semantic is not None,
        )

    async def validate_pack(
        self,
        topic: Topic,
        pack: CuratedContextPack,
        valid_evidence: dict[str, list[str]] | None = None,
    ) -> None:
        """Reject any unknown, cross-topic, or ungrounded assertion/evidence ID."""
        await TopicReconciler.validate_pack(self.db, topic, pack, valid_evidence)

    async def validate_semantic_pack(
        self,
        topic: Topic,
        pack: CuratedContextPack,
        deterministic_pack: CuratedContextPack,
        valid_evidence: dict[str, list[str]],
    ) -> None:
        """Require model output to be an exact subset of the safe manifest."""
        await TopicReconciler.validate_semantic_pack(
            self.db, topic, pack, deterministic_pack, valid_evidence
        )

    @staticmethod
    def _hierarchy_candidates(
        topic: Topic, user_topics: dict[str, Topic]
    ) -> list[dict[str, str | None]]:
        return TopicClusterer.hierarchy_candidates(topic, user_topics)

    async def _user_topics(self, user_id: str) -> dict[str, Topic]:
        return await TopicClusterer.get_user_topics(self.db, user_id)

    @staticmethod
    def _validated_hierarchy_proposal(
        topic: Topic,
        proposals: list[HierarchyProposal],
        user_topics: dict[str, Topic],
    ) -> HierarchyProposal | None:
        return TopicClusterer.validated_hierarchy_proposal(topic, proposals, user_topics)

    async def _latest_valid_pack(self, topic_id: str) -> TopicContextVersion | None:
        """Return the current valid pack, or the newest valid historical row."""
        return await self.db.scalar(
            select(TopicContextVersion)
            .where(
                TopicContextVersion.topic_id == topic_id,
                TopicContextVersion.validation_status.in_(("valid", "validated")),
            )
            .order_by(TopicContextVersion.version.desc(), TopicContextVersion.created_at.desc())
            .limit(1)
        )

    async def consolidate_user(
        self,
        user_id: str,
        *,
        lease_owner: str | None = None,
        event_watermark: int | None = None,
    ) -> int:
        """Consolidate one user in one atomic transaction."""
        state = await self.db.get(TopicIngestionState, user_id)
        owner = lease_owner or self._claim_owner
        if state is not None and state.lease_owner is not None and owner != state.lease_owner:
            raise RuntimeError("topic consolidation lease is owned by another worker")

        if event_watermark is None:
            event_watermark = await self.db.scalar(
                select(func.max(TopicIngestionEvent.id)).where(
                    TopicIngestionEvent.user_id == user_id
                )
            )
        event_watermark = event_watermark or 0
        ingestion = TopicIngestionService(self.db)
        while await ingestion.process_user(
            user_id,
            commit_each=False,
            until_event_id=event_watermark,
            raise_on_error=True,
        ):
            pass
        await ingestion.archive_orphaned_history_topics(user_id)
        graph_curator = await self.curate_user_graph(user_id)
        if graph_curator is None:
            await self._apply_obvious_label_hierarchy(user_id)
        state = await self.db.get(TopicIngestionState, user_id)
        watermark = state.last_realtime_event_id if state else 0
        topics = list(
            (
                await self.db.scalars(
                    select(Topic).where(
                        Topic.user_id == user_id,
                        Topic.status == "active",
                        Topic.dirty_since.is_not(None),
                    )
                )
            ).all()
        )
        for topic in topics:
            await self.consolidate_topic(
                topic,
                source_event_watermark=watermark,
                graph_curator=graph_curator,
                use_focused_curator=False,
            )
        if state is not None:
            if state.lease_owner is not None and owner != state.lease_owner:
                raise RuntimeError("topic consolidation lease was lost during processing")
            state.last_consolidated_event_id = watermark
            if owner is None or state.lease_owner == owner:
                state.lease_owner = None
                state.lease_expires_at = None
            state.consecutive_failures = 0
            state.last_error = None
            state.retry_at = None
        await self.db.commit()
        return len(topics)

    async def _apply_obvious_label_hierarchy(self, user_id: str) -> None:
        await TopicClusterer.apply_obvious_label_hierarchy(self.db, user_id)

    async def curate_user_graph(self, user_id: str) -> UserTopicGraphCuratorResult | None:
        """Repair provisional labels/hierarchy/assertions from bounded owned evidence."""
        manifest, topics, evidence = await self._user_graph_manifest(user_id)
        signature = TopicSemanticCurator.configuration_signature()
        if signature is None:
            return None
        expected_topic_ids = set(manifest.get("curation_topic_ids", []))
        if not expected_topic_ids:
            TopicClusterer.mark_graph_signature(topics.values(), signature)
            await self.db.flush()
            return None

        async def validate(output: UserTopicGraphCuratorOutput) -> None:
            repaired = TopicClusterer.repair_user_graph_output(
                output,
                topics,
                evidence,
                expected_topic_ids=expected_topic_ids,
            )
            output.topics.clear()
            output.topics.extend(repaired.topics)
            self._validate_user_graph_output(
                output,
                topics,
                evidence,
                expected_topic_ids=expected_topic_ids,
            )

        result = await TopicSemanticCurator().curate_user_graph(
            manifest=manifest,
            validator=validate,
        )
        if result is None:
            return None
        try:
            async with self.db.begin_nested():
                for proposal in result.output.topics:
                    await self._apply_graph_proposal(
                        proposal,
                        topics,
                        evidence,
                        curator_signature=signature,
                    )
                TopicClusterer.mark_graph_signature(topics.values(), signature)
                await self.db.flush()
        except Exception as exc:
            logger.warning("Discarding topic graph curator writes for %s: %s", user_id, exc)
            return None
        return result

    async def _user_graph_manifest(
        self, user_id: str
    ) -> tuple[dict[str, Any], dict[str, Topic], dict[str, tuple[set[str], str]]]:
        """Build a bounded, user-owned manifest and an authoritative evidence map."""
        signature = TopicSemanticCurator.configuration_signature()
        signature_due = func.coalesce(
            Topic.topic_metadata["graph_curator_signature"].as_string(),
            "",
        ) != (signature or "")
        all_topics = list(
            (
                await self.db.scalars(
                    select(Topic)
                    .where(Topic.user_id == user_id, Topic.status == "active")
                    .order_by(signature_due.desc(), Topic.last_active_at.desc())
                    .limit(_GRAPH_TOPIC_LIMIT)
                )
            ).all()
        )
        topics = {topic.id: topic for topic in all_topics}
        if not topics:
            return {"topics": [], "curation_topic_ids": []}, {}, {}
        exclusions = list(
            (
                await self.db.scalars(
                    select(TopicExclusion).where(
                        TopicExclusion.user_id == user_id,
                        TopicExclusion.revoked_at.is_(None),
                    )
                )
            ).all()
        )
        if any(exclusion.scope == "all_topics" for exclusion in exclusions):
            return {"topics": [], "curation_topic_ids": []}, topics, {}
        excluded_sources = {
            exclusion.target_id
            for exclusion in exclusions
            if exclusion.scope == "source" and exclusion.target_id
        }
        ranked_evidence = (
            select(
                MessageTopic.topic_id.label("topic_id"),
                Message.id.label("message_id"),
                Message.content.label("content"),
                Message.created_at.label("created_at"),
                func.row_number()
                .over(
                    partition_by=MessageTopic.topic_id,
                    order_by=Message.created_at.desc(),
                )
                .label("topic_rank"),
            )
            .join(Message, Message.id == MessageTopic.message_id)
            .join(Conversation, Conversation.id == Message.conversation_id)
            .where(
                MessageTopic.topic_id.in_(topics),
                Conversation.user_id == user_id,
                Conversation.is_deleted.is_(False),
                Message.role == "user",
            )
            .subquery()
        )
        rows = (
            await self.db.execute(
                select(
                    ranked_evidence.c.topic_id,
                    ranked_evidence.c.message_id,
                    ranked_evidence.c.content,
                )
                .where(ranked_evidence.c.topic_rank <= _GRAPH_CANDIDATES_PER_TOPIC)
                .order_by(ranked_evidence.c.created_at.desc())
            )
        ).all()
        evidence: dict[str, tuple[set[str], str]] = {}
        by_topic: dict[str, list[dict[str, str]]] = {topic_id: [] for topic_id in topics}
        for topic_id, message_id, content in rows:
            if len(by_topic[topic_id]) >= _GRAPH_EVIDENCE_PER_TOPIC:
                continue
            if message_id in excluded_sources or _REJECTION_TEXT.search(content):
                continue
            excerpt = " ".join(content.split())[:_GRAPH_EXCERPT_CHARS]
            if not excerpt:
                continue
            if message_id in evidence:
                evidence[message_id][0].add(topic_id)
            else:
                evidence[message_id] = ({topic_id}, excerpt)
            by_topic[topic_id].append({"id": message_id, "excerpt": excerpt})

        curation_topic_ids = [topic.id for topic in all_topics if by_topic[topic.id]]
        return (
            {
                "topics": [
                    {
                        "id": topic.id,
                        "label": topic.label,
                        "parent_id": topic.parent_id,
                        "eligible_for_curation": bool(by_topic[topic.id]),
                        "evidence": by_topic[topic.id],
                    }
                    for topic in all_topics
                ],
                "curation_topic_ids": curation_topic_ids,
            },
            topics,
            evidence,
        )

    @classmethod
    def _validate_user_graph_output(
        cls,
        output: UserTopicGraphCuratorOutput,
        topics: dict[str, Topic],
        evidence: dict[str, tuple[set[str], str]],
        *,
        expected_topic_ids: set[str],
    ) -> None:
        TopicClusterer.validate_user_graph_output(
            output, topics, evidence, expected_topic_ids=expected_topic_ids
        )

    @staticmethod
    def _lexically_grounded(content: str, source_text: str) -> bool:
        return TopicReconciler.lexically_grounded(content, source_text)

    @staticmethod
    def _validate_graph_depth(
        output: UserTopicGraphCuratorOutput,
        topics: dict[str, Topic],
        merged_ids: set[str],
    ) -> None:
        TopicClusterer.validate_graph_depth(output, topics, merged_ids)

    @staticmethod
    def _mark_graph_signature(topics: Any, signature: str) -> None:
        TopicClusterer.mark_graph_signature(topics, signature)

    async def _apply_graph_proposal(
        self,
        proposal: TopicGraphProposal,
        topics: dict[str, Topic],
        evidence: dict[str, tuple[set[str], str]],
        *,
        curator_signature: str,
    ) -> None:
        await TopicClusterer.apply_graph_proposal(
            self.db, proposal, topics, evidence, curator_signature=curator_signature
        )

    async def _resolve_curated_parent(
        self,
        topic: Topic,
        parent_topic_id: str | None,
        label: str | None,
        topics: dict[str, Topic],
        *,
        curator_signature: str,
    ) -> str | None:
        return await TopicClusterer.resolve_curated_parent(
            self.db,
            topic,
            parent_topic_id,
            label,
            topics,
            curator_signature=curator_signature,
        )

    async def _merge_topic(self, source: Topic, target: Topic) -> None:
        await TopicClusterer.merge_topic(self.db, source, target)

    async def _move_aliases(self, source: Topic, target: Topic) -> None:
        await TopicClusterer.move_aliases(self.db, source, target)

    async def _move_memberships(self, source: Topic, target: Topic) -> None:
        await TopicClusterer.move_memberships(self.db, source, target)

    async def _move_assertions(self, source: Topic, target: Topic) -> None:
        await TopicClusterer.move_assertions(self.db, source, target)

    async def _redirect_topic_refs(self, source: Topic, target: Topic) -> None:
        await TopicClusterer.redirect_topic_refs(self.db, source, target)

    async def _ensure_topic_alias(
        self,
        topic: Topic,
        label: str,
        normalized: str,
        *,
        target: Topic | None = None,
    ) -> None:
        await TopicClusterer.ensure_topic_alias(self.db, topic, label, normalized, target=target)

    async def claim_dirty_users(self, *, limit: int = 100, owner: str | None = None) -> list[str]:
        claimed, lease_owner = await ConsolidationWorker.claim_dirty_users(
            self.db, limit=limit, owner=owner
        )
        self._claim_owner = lease_owner
        return claimed

    async def record_failure(self, user_id: str, error: Exception) -> None:
        await ConsolidationWorker.record_failure(self.db, user_id, error)

    @staticmethod
    def _exclusion_sets(
        exclusions: list[TopicExclusion], topic_id: str
    ) -> tuple[set[str], set[str], set[str], bool]:
        return TopicReconciler.exclusion_sets(exclusions, topic_id)

    async def _valid_evidence(self, user_id: str, topic_id: str) -> dict[str, list[str]]:
        return await TopicReconciler.valid_evidence(self.db, user_id, topic_id)

    @staticmethod
    def _short_summary(topic: Topic, pack: CuratedContextPack) -> str:
        return ContextPackBuilder.short_summary(topic, pack)
