"""Topic clusterer: hierarchy proposals, graph repair, merging, and alias propagation."""

from __future__ import annotations

import hashlib
import uuid
from datetime import UTC, datetime
from typing import Any

from sqlalchemy import select, update
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.models.conversation import Conversation
from app.models.message import Message
from app.topics.consolidation.reconciler import TopicReconciler
from app.topics.models import (
    ActiveContextItem,
    MessageTopic,
    Topic,
    TopicAlias,
    TopicAssertion,
    TopicAssertionEvidence,
    TopicExclusion,
)
from app.topics.topic_normalization import normalize_topic_label
from app.topics.topic_semantic_curator import (
    CuratedAssertionProposal,
    HierarchyProposal,
    TopicGraphProposal,
    UserTopicGraphCuratorOutput,
)

# fmt: off
_GENERIC_TOPIC_LABELS = set("doing|general|helping|miscellaneous|need|new topic|not working|not working now|other|something|stuff|working|get|getting|got|going|go|user|great|good|nice|okay|creat|create|summary|summary appli|know|know location|see email|add|add suggestion|send|latest|recent|top|recent developments".split("|"))  # noqa: SIM905
# fmt: on


class TopicClusterer:
    """Manages topic hierarchies, graph synthesis validation, and non-destructive merges."""

    @staticmethod
    def hierarchy_candidates(
        topic: Topic, user_topics: dict[str, Topic]
    ) -> list[dict[str, str | None]]:
        """Expose only active same-user topics as possible semantic parents."""
        candidates = [
            {"id": candidate.id, "label": candidate.label, "parent_id": candidate.parent_id}
            for candidate in user_topics.values()
            if candidate.id != topic.id and candidate.status == "active"
        ]
        return candidates[:100]

    @staticmethod
    async def get_user_topics(db: AsyncSession, user_id: str) -> dict[str, Topic]:
        topics = list((await db.scalars(select(Topic).where(Topic.user_id == user_id))).all())
        return {candidate.id: candidate for candidate in topics}

    @staticmethod
    def validated_hierarchy_proposal(
        topic: Topic,
        proposals: list[HierarchyProposal],
        user_topics: dict[str, Topic],
    ) -> HierarchyProposal | None:
        """Validate ownership, uniqueness, and acyclicity before re-parenting."""
        if not proposals:
            return None
        proposal = proposals[0]
        if proposal.topic_id != topic.id:
            raise ValueError("hierarchy proposal targets another topic")
        parent_id = proposal.parent_topic_id
        if parent_id is None:
            return proposal
        parent = user_topics.get(parent_id)
        if parent is None or parent.status != "active":
            raise ValueError("hierarchy proposal uses an unavailable parent")
        if parent.id == topic.id:
            raise ValueError("hierarchy proposal creates a self-cycle")
        if any(
            candidate.id != topic.id
            and candidate.parent_id == parent.id
            and candidate.normalized_label == topic.normalized_label
            for candidate in user_topics.values()
        ):
            raise ValueError("hierarchy proposal collides with a sibling label")

        visited = {topic.id}
        cursor: Topic | None = parent
        while cursor is not None:
            if cursor.id in visited:
                raise ValueError("hierarchy proposal creates a cycle")
            visited.add(cursor.id)
            cursor = user_topics.get(cursor.parent_id) if cursor.parent_id else None
        return proposal

    @classmethod
    def repair_user_graph_output(
        cls,
        output: UserTopicGraphCuratorOutput,
        topics: dict[str, Topic],
        evidence: dict[str, tuple[set[str], str]],
        *,
        expected_topic_ids: set[str],
    ) -> UserTopicGraphCuratorOutput:
        """Sanitize, harmonize, and complete model graph output prior to strict validation."""
        known_existing_by_norm = {
            t.normalized_label: t.id for t in topics.values() if t.normalized_label
        }
        raw_proposals = [p for p in output.topics if p.topic_id in expected_topic_ids]

        seen_tids: set[str] = set()
        deduped: list[TopicGraphProposal] = []
        for p in raw_proposals:
            if p.topic_id not in seen_tids:
                seen_tids.add(p.topic_id)
                deduped.append(p)

        canonical_ids = {p.topic_id for p in deduped}
        all_merged_ids: set[str] = set()

        for p in deduped:
            clean_label = p.label.strip(" \"'")
            norm_l = normalize_topic_label(clean_label)
            if norm_l in _GENERIC_TOPIC_LABELS or len(norm_l) < 2:
                clean_label = topics[p.topic_id].label
            p.label = clean_label

            valid_merges: list[str] = []
            for mid in p.merge_topic_ids:
                if (
                    mid in expected_topic_ids
                    and mid != p.topic_id
                    and mid not in canonical_ids
                    and mid not in all_merged_ids
                ):
                    valid_merges.append(mid)
                    all_merged_ids.add(mid)
            p.merge_topic_ids = valid_merges

        archived_ids = {
            tid
            for tid in output.archive_topic_ids
            if tid in expected_topic_ids and tid not in canonical_ids and tid not in all_merged_ids
        }
        missing_ids = expected_topic_ids - (canonical_ids | all_merged_ids | archived_ids)
        for mid in missing_ids:
            orig = topics[mid]
            deduped.append(
                TopicGraphProposal(
                    topic_id=mid,
                    label=orig.label,
                    parent_topic_id=None,
                    parent_label=None,
                    merge_topic_ids=[],
                    assertions=[],
                )
            )
            canonical_ids.add(mid)

        for p in deduped:
            norm_l = normalize_topic_label(p.label)
            if p.parent_label and p.parent_topic_id:
                if p.parent_topic_id in topics and p.parent_topic_id != p.topic_id:
                    p.parent_label = None
                else:
                    p.parent_topic_id = None

            if p.parent_label:
                norm_p = normalize_topic_label(p.parent_label.strip(" \"'"))
                if norm_p == norm_l or norm_p in _GENERIC_TOPIC_LABELS or len(norm_p) < 2:
                    p.parent_label = None
                elif norm_p in known_existing_by_norm:
                    target_id = known_existing_by_norm[norm_p]
                    if target_id != p.topic_id and target_id not in all_merged_ids:
                        p.parent_topic_id = target_id
                        p.parent_label = None
                    else:
                        p.parent_label = None

            if p.parent_topic_id and (
                p.parent_topic_id not in topics
                or p.parent_topic_id == p.topic_id
                or p.parent_topic_id in all_merged_ids
            ):
                p.parent_topic_id = None

        for p in deduped:
            allowed_ids = {p.topic_id, *p.merge_topic_ids}
            allowed_ev = {eid for eid, (tids, _) in evidence.items() if tids & allowed_ids}
            clean_assertions: list[CuratedAssertionProposal] = []
            seen_a: set[tuple[str, str]] = set()
            for a in p.assertions:
                ev_set = set(a.evidence_ids)
                if not ev_set or not ev_set.issubset(allowed_ev):
                    continue
                a.evidence_ids = list(ev_set)
                norm_c = normalize_topic_label(a.content)
                key = (a.kind, norm_c)
                if key in seen_a:
                    continue
                if any(
                    eid not in evidence
                    or not TopicReconciler.lexically_grounded(a.content, evidence[eid][1])
                    for eid in a.evidence_ids
                ):
                    continue
                seen_a.add(key)
                clean_assertions.append(a)
            p.assertions = clean_assertions

        siblings: set[tuple[str, str]] = set()
        for p in deduped:
            pk = p.parent_topic_id or normalize_topic_label(p.parent_label or "")
            norm_l = normalize_topic_label(p.label)
            sk = (pk, norm_l)
            if sk in siblings:
                p.label = f"{p.label} - {topics[p.topic_id].label[:30]}"
                norm_l = normalize_topic_label(p.label)
                sk = (pk, norm_l)
            siblings.add(sk)

        proposals_by_id = {p.topic_id: p for p in deduped}
        for start_id, prop in proposals_by_id.items():
            visited: set[str] = {start_id}
            depth = 1
            cursor = prop.parent_topic_id
            has_cycle = False
            while cursor is not None:
                if cursor in visited or depth >= 3:
                    has_cycle = True
                    break
                visited.add(cursor)
                depth += 1
                cursor = (
                    proposals_by_id.get(cursor).parent_topic_id
                    if cursor in proposals_by_id
                    else topics.get(cursor).parent_id
                    if cursor in topics
                    else None
                )
            if has_cycle:
                prop.parent_topic_id = None
                prop.parent_label = None

        valid_archives = list(
            dict.fromkeys(
                tid
                for tid in output.archive_topic_ids
                if tid in expected_topic_ids
                and tid not in canonical_ids
                and tid not in all_merged_ids
            )
        )

        return UserTopicGraphCuratorOutput(topics=deduped, archive_topic_ids=valid_archives)

    @classmethod
    def validate_user_graph_output(
        cls,
        output: UserTopicGraphCuratorOutput,
        topics: dict[str, Topic],
        evidence: dict[str, tuple[set[str], str]],
        *,
        expected_topic_ids: set[str],
    ) -> None:
        pids = [p.topic_id for p in output.topics]
        if len(pids) != len(set(pids)):
            raise ValueError("topic graph contains duplicate canonical targets")
        known = {t.normalized_label for t in topics.values() if t.normalized_label} | {
            normalize_topic_label(p.label) for p in output.topics
        }
        merged_ids: set[str] = set()
        sibling: set[tuple[str, str]] = set()
        for p in output.topics:
            if p.topic_id not in topics:
                raise ValueError("topic graph targets an unknown topic")
            n = normalize_topic_label(p.label)
            if n in _GENERIC_TOPIC_LABELS or len(n) < 2:
                raise ValueError("topic graph proposed a vague label")
            if p.parent_label and normalize_topic_label(p.parent_label) == n:
                raise ValueError("topic graph proposed itself as parent")
            if p.parent_label and p.parent_topic_id:
                raise ValueError("topic graph set two parents for one topic")
            if p.parent_label and normalize_topic_label(p.parent_label) in _GENERIC_TOPIC_LABELS:
                raise ValueError("topic graph proposed a vague parent label")
            if p.parent_label and normalize_topic_label(p.parent_label) in known:
                raise ValueError("topic graph must reference a supplied parent by parent_topic_id")
            if p.parent_topic_id is not None and (
                p.parent_topic_id not in topics or p.parent_topic_id == p.topic_id
            ):
                raise ValueError("topic graph proposed an unavailable parent topic")
            pk = p.parent_topic_id or normalize_topic_label(p.parent_label or "")
            sk = (pk, n)
            if sk in sibling:
                raise ValueError("topic graph proposed duplicate sibling labels")
            sibling.add(sk)
            for mid in p.merge_topic_ids:
                if mid == p.topic_id or mid not in topics or mid in merged_ids:
                    raise ValueError("topic graph contains an invalid merge")
                merged_ids.add(mid)
        cids = set(pids)
        if merged_ids & cids:
            raise ValueError("topic graph merges another canonical target")
        archive_ids = set(output.archive_topic_ids)
        if archive_ids & (cids | merged_ids):
            raise ValueError("topic graph archives a canonical or merged topic")
        if cids | merged_ids | archive_ids != expected_topic_ids:
            raise ValueError("topic graph must partition every eligible topic exactly once")
        if any(
            p.parent_topic_id in merged_ids for p in output.topics if p.parent_topic_id is not None
        ):
            raise ValueError("topic graph parents a topic that is being merged")
        if any(
            p.parent_topic_id in archive_ids for p in output.topics if p.parent_topic_id is not None
        ):
            raise ValueError("topic graph parents a topic that is being archived")
        if len(cids) >= 3 and not any(
            p.parent_topic_id is not None or p.parent_label is not None for p in output.topics
        ):
            raise ValueError("topic graph flattened every eligible topic")
        cls.validate_graph_depth(output, topics, merged_ids)
        for p in output.topics:
            allowed_ids = {p.topic_id, *p.merge_topic_ids}
            allowed_ev = {mid for mid, (tids, _) in evidence.items() if tids & allowed_ids}
            seen: set[tuple[str, str]] = set()
            for a in p.assertions:
                if not set(a.evidence_ids).issubset(allowed_ev):
                    raise ValueError("topic graph assertion cites unowned evidence")
                if len(a.evidence_ids) != len(set(a.evidence_ids)):
                    raise ValueError("topic graph assertion duplicated an evidence ID")
                k = (a.kind, normalize_topic_label(a.content))
                if k in seen:
                    raise ValueError("topic graph duplicated a synthesized assertion")
                seen.add(k)
                if any(
                    not TopicReconciler.lexically_grounded(a.content, evidence[i][1])
                    for i in a.evidence_ids
                ):
                    raise ValueError("topic graph assertion is not grounded in every cited excerpt")

    @staticmethod
    def validate_graph_depth(
        output: UserTopicGraphCuratorOutput,
        topics: dict[str, Topic],
        merged_ids: set[str],
    ) -> None:
        """Reject cycles and hierarchies deeper than the three-level UI contract."""
        proposals = {proposal.topic_id: proposal for proposal in output.topics}
        effective_parent: dict[str, str | None] = {}
        for topic_id, topic in topics.items():
            if topic_id in merged_ids:
                continue
            proposal = proposals.get(topic_id)
            if proposal is None:
                effective_parent[topic_id] = topic.parent_id
            elif proposal.parent_topic_id is not None:
                effective_parent[topic_id] = proposal.parent_topic_id
            elif proposal.parent_label is not None:
                effective_parent[topic_id] = (
                    f"synthetic:{normalize_topic_label(proposal.parent_label)}"
                )
            else:
                effective_parent[topic_id] = None

        for start in proposals:
            visited: set[str] = set()
            cursor: str | None = start
            depth = 0
            while cursor is not None:
                if cursor in visited:
                    raise ValueError("topic graph proposed a hierarchy cycle")
                visited.add(cursor)
                depth += 1
                if depth > 3:
                    raise ValueError("topic graph exceeds three visible levels")
                cursor = effective_parent.get(cursor)

    @staticmethod
    def mark_graph_signature(topics: Any, signature: str) -> None:
        for topic in topics:
            topic.topic_metadata = {
                **(topic.topic_metadata or {}),
                "graph_curator_signature": signature,
            }

    @classmethod
    async def apply_graph_proposal(
        cls,
        db: AsyncSession,
        proposal: TopicGraphProposal,
        topics: dict[str, Topic],
        evidence: dict[str, tuple[set[str], str]],
        *,
        curator_signature: str,
    ) -> None:
        canonical = topics[proposal.topic_id]
        for merged_id in proposal.merge_topic_ids:
            await cls.merge_topic(db, topics[merged_id], canonical)

        normalized = normalize_topic_label(proposal.label)
        new_parent_id = await cls.resolve_curated_parent(
            db,
            canonical,
            proposal.parent_topic_id,
            proposal.parent_label,
            topics,
            curator_signature=curator_signature,
        )
        parent_filter = (
            Topic.parent_id == new_parent_id
            if new_parent_id is not None
            else Topic.parent_id.is_(None)
        )
        collision = await db.scalar(
            select(Topic).where(
                Topic.user_id == canonical.user_id,
                Topic.id != canonical.id,
                parent_filter,
                Topic.normalized_label == normalized,
                Topic.status == "active",
            )
        )
        if collision is not None:
            raise ValueError("curated label collides with another active topic")
        if canonical.normalized_label != normalized:
            await cls.ensure_topic_alias(
                db,
                canonical,
                canonical.label,
                canonical.normalized_label,
            )
        canonical.label = proposal.label.strip()
        canonical.normalized_label = normalized
        canonical.parent_id = new_parent_id
        canonical.origin = "history"
        canonical.topic_metadata = {
            **(canonical.topic_metadata or {}),
            "semantic_curator": True,
            "graph_curator_signature": curator_signature,
        }
        canonical.dirty_since = canonical.dirty_since or datetime.now(UTC)

        for item in proposal.assertions:
            normalized_key = hashlib.sha256(
                f"{item.kind}\0{normalize_topic_label(item.content)}".encode()
            ).hexdigest()
            assertion = await db.scalar(
                select(TopicAssertion).where(
                    TopicAssertion.topic_id == canonical.id,
                    TopicAssertion.normalized_key == normalized_key,
                )
            )
            if assertion is None:
                assertion = TopicAssertion(
                    id=str(uuid.uuid4()),
                    topic_id=canonical.id,
                    kind=item.kind,
                    content=item.content.strip(),
                    normalized_key=normalized_key,
                    status="active",
                    authority="explicit_user_statement",
                    confidence=item.confidence,
                )
                db.add(assertion)
                await db.flush()
            for message_id in item.evidence_ids:
                message = await db.get(Message, message_id)
                if message is None:
                    raise ValueError("curated assertion evidence disappeared")
                key = (assertion.id, message.id, 0, len(message.content))
                if await db.get(TopicAssertionEvidence, key) is None:
                    db.add(
                        TopicAssertionEvidence(
                            assertion_id=assertion.id,
                            message_id=message.id,
                            segment_start=0,
                            segment_end=len(message.content),
                            relation="supports",
                            source_span_hash=hashlib.sha256(message.content.encode()).hexdigest(),
                        )
                    )

    @classmethod
    async def resolve_curated_parent(
        cls,
        db: AsyncSession,
        topic: Topic,
        parent_topic_id: str | None,
        label: str | None,
        topics: dict[str, Topic],
        *,
        curator_signature: str,
    ) -> str | None:
        if parent_topic_id is not None:
            parent = topics.get(parent_topic_id)
            if parent is None or parent.status != "active" or parent.id == topic.id:
                raise ValueError("curated topic uses an unavailable parent")
            return parent.id
        if not label:
            return None
        normalized = normalize_topic_label(label)
        parent = await db.scalar(
            select(Topic).where(
                Topic.user_id == topic.user_id,
                Topic.parent_id.is_(None),
                Topic.normalized_label == normalized,
            )
        )
        if parent is None:
            parent = Topic(
                id=str(uuid.uuid4()),
                user_id=topic.user_id,
                label=label.strip(),
                normalized_label=normalized,
                origin="history",
                base_score=0.55,
                signal=topic.signal,
                last_active_at=topic.last_active_at,
                dirty_since=datetime.now(UTC),
                topic_metadata={
                    "semantic_curator_parent": True,
                    "graph_curator_signature": curator_signature,
                },
            )
            db.add(parent)
            await db.flush()
        elif parent.id == topic.id:
            raise ValueError("curated topic cannot parent itself")
        elif parent.status != "active":
            parent.status = "active"
            parent.canonical_topic_id = None
            parent.dirty_since = datetime.now(UTC)
        parent.topic_metadata = {
            **(parent.topic_metadata or {}),
            "graph_curator_signature": curator_signature,
        }
        return parent.id

    @classmethod
    async def merge_topic(cls, db: AsyncSession, source: Topic, target: Topic) -> None:
        """Archive/redirect one duplicate while preserving its owned evidence."""
        await cls.ensure_topic_alias(
            db, source, source.label, source.normalized_label, target=target
        )
        await cls.move_aliases(db, source, target)
        await cls.move_memberships(db, source, target)
        await cls.move_assertions(db, source, target)
        await cls.redirect_topic_refs(db, source, target)
        source.status = "archived"
        source.canonical_topic_id = target.id
        source.normalized_label = f"merged-{source.id}"
        source.dirty_since = None
        target.mention_count += source.mention_count
        target.last_active_at = max(target.last_active_at, source.last_active_at)
        target.dirty_since = target.dirty_since or datetime.now(UTC)
        await db.flush()

    @staticmethod
    async def move_aliases(db: AsyncSession, source: Topic, target: Topic) -> None:
        for alias in list(
            (await db.scalars(select(TopicAlias).where(TopicAlias.topic_id == source.id))).all()
        ):
            collision = await db.scalar(
                select(TopicAlias).where(
                    TopicAlias.user_id == target.user_id,
                    TopicAlias.normalized_alias == alias.normalized_alias,
                    TopicAlias.id != alias.id,
                )
            )
            if collision is not None:
                await db.delete(alias)
            else:
                alias.topic_id = target.id

    @staticmethod
    async def move_memberships(db: AsyncSession, source: Topic, target: Topic) -> None:
        for m in list(
            (await db.scalars(select(MessageTopic).where(MessageTopic.topic_id == source.id))).all()
        ):
            if await db.get(MessageTopic, (m.message_id, target.id)) is not None:
                await db.delete(m)
            else:
                m.topic_id = target.id

    @staticmethod
    async def move_assertions(db: AsyncSession, source: Topic, target: Topic) -> None:
        for assertion in list(
            (
                await db.scalars(
                    select(TopicAssertion)
                    .where(TopicAssertion.topic_id == source.id)
                    .options(selectinload(TopicAssertion.evidence))
                )
            ).all()
        ):
            existing = await db.scalar(
                select(TopicAssertion).where(
                    TopicAssertion.topic_id == target.id,
                    TopicAssertion.normalized_key == assertion.normalized_key,
                )
            )
            if existing is None:
                assertion.topic_id = target.id
                continue
            for ev in list(assertion.evidence):
                key = (existing.id, ev.message_id, ev.segment_start, ev.segment_end)
                if await db.get(TopicAssertionEvidence, key) is None:
                    db.add(
                        TopicAssertionEvidence(
                            assertion_id=existing.id,
                            message_id=ev.message_id,
                            segment_start=ev.segment_start,
                            segment_end=ev.segment_end,
                            relation=ev.relation,
                            source_span_hash=ev.source_span_hash,
                        )
                    )
            existing.confidence = max(existing.confidence, assertion.confidence)
            await db.execute(
                update(TopicExclusion)
                .where(TopicExclusion.target_id == assertion.id)
                .values(target_id=existing.id, topic_id=target.id)
            )
            await db.delete(assertion)

    @staticmethod
    async def redirect_topic_refs(db: AsyncSession, source: Topic, target: Topic) -> None:
        await db.execute(
            update(Conversation)
            .where(Conversation.active_topic_id == source.id)
            .values(active_topic_id=target.id)
        )
        await db.execute(
            update(Topic).where(Topic.parent_id == source.id).values(parent_id=target.id)
        )
        await db.execute(
            update(TopicExclusion)
            .where(TopicExclusion.topic_id == source.id)
            .values(topic_id=target.id)
        )
        await db.execute(
            update(ActiveContextItem)
            .where(ActiveContextItem.topic_id == source.id)
            .values(topic_id=target.id)
        )

    @staticmethod
    async def ensure_topic_alias(
        db: AsyncSession,
        topic: Topic,
        label: str,
        normalized: str,
        *,
        target: Topic | None = None,
    ) -> None:
        """Preserve a former label without violating the user-wide alias key."""
        if not normalized:
            return
        existing = await db.scalar(
            select(TopicAlias).where(
                TopicAlias.user_id == topic.user_id,
                TopicAlias.normalized_alias == normalized,
            )
        )
        resolved = target or topic
        if existing is not None:
            existing.topic_id = resolved.id
            return
        db.add(
            TopicAlias(
                id=str(uuid.uuid4()),
                user_id=topic.user_id,
                topic_id=resolved.id,
                alias=label,
                normalized_alias=normalized,
            )
        )
