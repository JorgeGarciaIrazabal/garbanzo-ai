"""Topic clusterer: hierarchy proposals, graph repair, merging, and alias propagation."""

from __future__ import annotations

import hashlib
import re
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
_GENERIC_TOPIC_LABELS = set("doing|general|helping|miscellaneous|need|new topic|not working|not working now|other|something|stuff|working".split("|"))  # noqa: SIM905
_HIERARCHY_STOP_TOKENS = _GENERIC_TOPIC_LABELS | set(
    ["about", "after", "again", "also", "and", "are", "can", "could", "for", "from", "have", "help", "hello", "hear", "how", "into", "just", "like", "need", "please", "simple", "some", "should", "that", "the", "this", "want", "what", "when", "where", "which", "with", "would", "you", "thanks", "thank", "terms", "tool", "use", "using", "explain", "find", "search", "check", "tell", "give", "make", "create", "show", "open", "look", "your", "there", "here", "more", "many", "does", "will", "who", "whom", "hay", "que", "como", "cual", "cuales", "donde", "cuando", "quien", "quienes", "por", "para", "este", "esta", "estos", "estas", "ese", "esa", "esos", "esas", "opinas", "crees", "sabes", "dime", "cuenta", "quiero", "puedo", "podemos", "hacer", "unos", "unas", "algo", "nada", "hola", "buenos", "buenas", "muchas", "muchos", "algun", "alguna", "algunos", "algunas", "sobre", "entre", "chat", "conversation", "test", "see", "seen", "dont", "don"]  # noqa: SIM905
)
# fmt: on
_OBVIOUS_PARENT_LABELS = {"time": "World time", "tax": "Taxes", "taxes": "Taxes"}

_CANONICAL_DOMAIN_TAXONOMY: dict[str, set[str]] = {
    "Real Estate & Housing": {
        "estate",
        "real",
        "house",
        "housing",
        "property",
        "properties",
        "modular",
        "land",
        "mortgage",
        "mortgages",
        "rent",
        "rental",
        "rentals",
        "tenant",
        "tenants",
        "landlord",
        "piso",
        "casa",
        "venta",
        "alquiler",
        "terreno",
        "parcela",
        "hipoteca",
        "penagrande",
        "peñagrande",
        "aranjuez",
        "guadarrama",
        "greece",
        "greek",
        "intermediation",
        "escritura",
        "notario",
        "inmobiliaria",
        "chalet",
        "construccion",
        "building",
        "home",
        "homes",
        "contrato",
        "compra",
        "comprar",
        "vender",
    },
    "Family & Clara": {
        "clara",
        "daughter",
        "kid",
        "kids",
        "child",
        "children",
        "art",
        "class",
        "classes",
        "school",
        "toddler",
        "parenting",
        "family",
        "wife",
        "marissa",
        "pokey",
        "cat",
        "birthday",
        "playground",
        "cumple",
        "cumpleanos",
        "cumpleaños",
        "hija",
        "familia",
        "cuento",
        "story",
        "stories",
    },
    "Finance & Early Retirement": {
        "fire",
        "retire",
        "retirement",
        "pension",
        "tax",
        "taxes",
        "401k",
        "ira",
        "roth",
        "s&p",
        "sp500",
        "portfolio",
        "asset-backed",
        "stock",
        "stocks",
        "dividend",
        "dividends",
        "investment",
        "investments",
        "investing",
        "pre-ipo",
        "equity",
        "severance",
        "savings",
        "finances",
        "financial",
        "irpf",
        "hacienda",
        "fiscal",
        "patrimonio",
        "non-habitual",
        "nhr",
        "golden",
        "visa",
    },
    "Career & Bloomberg": {
        "bloomberg",
        "swe",
        "career",
        "job",
        "workplace",
        "performance",
        "evaluation",
        "review",
        "promotion",
        "compensation",
        "manager",
        "engineering",
        "colleague",
        "colleagues",
    },
    "AI Research & Frontier Models": {
        "ai",
        "llm",
        "llms",
        "kimi",
        "k3",
        "deepseek",
        "v4",
        "ollama",
        "dflash",
        "quant",
        "quantized",
        "quantization",
        "gguf",
        "llama",
        "mistral",
        "weights",
        "vram",
        "gpu",
        "inference",
        "benchmarks",
        "reasoning",
        "transformer",
        "cuda",
        "model",
        "models",
    },
    "Garbanzo AI Development": {
        "garbanzo",
        "chat",
        "context",
        "topics",
        "topic",
        "room",
        "rooms",
        "micro-app",
        "micro-apps",
        "scheduler",
        "banner",
        "system prompt",
        "fastapi",
        "flutter",
        "migration",
        "e2e",
        "widget",
        "frontend",
        "backend",
    },
    "Automotive & Electric Vehicles": {
        "ev",
        "evs",
        "byd",
        "tesla",
        "fsd",
        "electric",
        "vehicle",
        "vehicles",
        "car",
        "cars",
        "driving",
        "autonomous",
        "autopilot",
        "battery",
        "charging",
        "suv",
    },
    "Madrid & Travel": {
        "madrid",
        "spain",
        "travel",
        "flight",
        "flights",
        "trip",
        "trips",
        "barajas",
        "metro",
        "renfe",
        "hotel",
        "hotels",
        "vacation",
        "airport",
        "viaje",
        "vuelo",
        "espana",
        "españa",
    },
    "Health & Wellness": {
        "health",
        "workout",
        "workouts",
        "fitness",
        "gym",
        "exercise",
        "exercises",
        "recovery",
        "ergonomics",
        "chair",
        "desk",
        "sleep",
        "diet",
        "nutrition",
        "running",
        "routine",
    },
    "Daily AI Radar": {
        "radar",
        "daily",
        "digest",
        "sweep",
        "news",
        "updates",
        "briefing",
    },
}


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
    def classify_text_domain(cls, text: str) -> str | None:
        """Classify a topic label or text snippet into a canonical domain root category."""
        tokens = set(re.findall(r"[\w-]+", text.casefold()))
        best_domain: str | None = None
        best_score = 0
        for domain, keywords in _CANONICAL_DOMAIN_TAXONOMY.items():
            overlap = len(tokens & keywords)
            if overlap > best_score:
                best_score = overlap
                best_domain = domain
        return best_domain if best_score > 0 else None

    @classmethod
    async def _dedupe_sibling_labels(
        cls, db: AsyncSession, parent: Topic | None, children: list[Topic]
    ) -> list[Topic]:
        """Collapse same-label topics before re-parenting them under ``parent``.

        The (user, parent, normalized_label) unique key makes two same-label
        topics under one parent illegal. Collisions come from two places:
        within this batch, and a topic ALREADY under the parent from an
        earlier grouping run (invisible to the roots-only batch). Keep one
        winner and merge the rest into it (memberships/assertions/aliases
        move over, the loser is archived) so grouping never trips the key.
        """
        winners: dict[str, Topic] = {}
        existing: dict[str, Topic] = {}
        if parent is not None:
            for topic in (
                await db.scalars(
                    select(Topic).where(
                        Topic.user_id == parent.user_id,
                        Topic.parent_id == parent.id,
                        Topic.status == "active",
                    )
                )
            ).all():
                existing.setdefault(topic.normalized_label, topic)
        losers: list[tuple[Topic, Topic]] = []
        for child in children:
            winner = winners.get(child.normalized_label) or existing.get(child.normalized_label)
            if winner is None or winner.id == child.id:
                winners[child.normalized_label] = child
                continue
            newer = (
                winner
                if (winner.last_active_at or datetime.min.replace(tzinfo=UTC))
                >= (child.last_active_at or datetime.min.replace(tzinfo=UTC))
                else child
            )
            older = child if newer is winner else winner
            winners[child.normalized_label] = newer
            losers.append((older, newer))
        for older, newer in losers:
            await cls.merge_topic(db, older, newer)
        return list(winners.values())

    @classmethod
    async def apply_obvious_label_hierarchy(cls, db: AsyncSession, user_id: str) -> None:
        """Create high-confidence shared-label parent branches when semantic curator is unavailable."""
        roots = list(
            (
                await db.scalars(
                    select(Topic).where(
                        Topic.user_id == user_id,
                        Topic.status == "active",
                        Topic.parent_id.is_(None),
                    )
                )
            ).all()
        )
        if len(roots) < 2:
            return

        domain_groups: dict[str, list[Topic]] = {}
        unassigned_roots: list[Topic] = []
        for topic in roots:
            domain = cls.classify_text_domain(topic.label)
            if domain:
                domain_groups.setdefault(domain, []).append(topic)
            else:
                unassigned_roots.append(topic)

        for domain_name, children in domain_groups.items():
            normalized_parent = normalize_topic_label(domain_name)
            parent = next(
                (root for root in roots if root.normalized_label == normalized_parent),
                None,
            )
            if parent is None:
                parent = await db.scalar(
                    select(Topic).where(
                        Topic.user_id == user_id,
                        Topic.parent_id.is_(None),
                        Topic.normalized_label == normalized_parent,
                        Topic.status == "active",
                    )
                )
            eligible_children = [c for c in children if parent is None or c.id != parent.id]
            if len(eligible_children) < (1 if parent is not None else 2):
                unassigned_roots.extend(eligible_children)
                continue

            eligible_children = await cls._dedupe_sibling_labels(db, parent, eligible_children)

            if parent is None:
                parent = Topic(
                    id=str(uuid.uuid4()),
                    user_id=user_id,
                    label=domain_name,
                    normalized_label=normalized_parent,
                    origin="history",
                    base_score=max(child.base_score for child in eligible_children),
                    signal=next(
                        (child.signal for child in eligible_children if child.signal),
                        None,
                    ),
                    last_active_at=max(child.last_active_at for child in eligible_children),
                    dirty_since=datetime.now(UTC),
                    topic_metadata={"deterministic_hierarchy": "canonical_domain_taxonomy"},
                )
                db.add(parent)
                await db.flush()
                roots.append(parent)
            for child in eligible_children:
                child.parent_id = parent.id
                child.dirty_since = child.dirty_since or datetime.now(UTC)

        token_groups: dict[str, list[Topic]] = {}
        for topic in unassigned_roots:
            tokens = normalize_topic_label(topic.label).split()
            if not tokens:
                continue
            token = tokens[0]
            if len(token) < 3 or token in _HIERARCHY_STOP_TOKENS:
                continue
            token_groups.setdefault(token, []).append(topic)

        # Two passes: obvious allowlisted parents first (friendly labels),
        # then any shared lead token with >= 2 topics (the deterministic
        # answer to "too many flat topics" — the landing map shows a parent
        # branch instead of N siblings with the same first word).
        ordered_groups: list[tuple[str, list[Topic]]] = [
            (token, children)
            for token, children in token_groups.items()
            if token in _OBVIOUS_PARENT_LABELS or len(children) >= 2
        ]
        for token, children in ordered_groups:
            parent_label = _OBVIOUS_PARENT_LABELS.get(token, token.title())
            normalized_parent = normalize_topic_label(parent_label)
            parent = next(
                (root for root in roots if root.normalized_label == normalized_parent),
                None,
            )
            if parent is None:
                parent = await db.scalar(
                    select(Topic).where(
                        Topic.user_id == user_id,
                        Topic.parent_id.is_(None),
                        Topic.normalized_label == normalized_parent,
                        Topic.status == "active",
                    )
                )
            eligible_children = [c for c in children if parent is None or c.id != parent.id]
            if len(eligible_children) < (1 if parent is not None else 2):
                continue

            eligible_children = await cls._dedupe_sibling_labels(db, parent, eligible_children)
            if not eligible_children:
                continue

            if parent is None:
                parent = Topic(
                    id=str(uuid.uuid4()),
                    user_id=user_id,
                    label=parent_label,
                    normalized_label=normalized_parent,
                    origin="history",
                    base_score=max(child.base_score for child in eligible_children),
                    signal=next(
                        (child.signal for child in eligible_children if child.signal),
                        None,
                    ),
                    last_active_at=max(child.last_active_at for child in eligible_children),
                    dirty_since=datetime.now(UTC),
                    topic_metadata={
                        "deterministic_hierarchy": (
                            "obvious_lead_token"
                            if token in _OBVIOUS_PARENT_LABELS
                            else "shared_lead_token"
                        )
                    },
                )
                db.add(parent)
                await db.flush()
                roots.append(parent)
            for child in eligible_children:
                child.parent_id = parent.id
                child.dirty_since = child.dirty_since or datetime.now(UTC)

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

        missing_ids = expected_topic_ids - (canonical_ids | all_merged_ids)
        for mid in missing_ids:
            orig = topics[mid]
            domain = cls.classify_text_domain(orig.label)
            parent_topic_id = None
            parent_label = None
            if domain:
                norm_d = normalize_topic_label(domain)
                if norm_d in known_existing_by_norm and known_existing_by_norm[norm_d] != mid:
                    parent_topic_id = known_existing_by_norm[norm_d]
                else:
                    parent_label = domain
            deduped.append(
                TopicGraphProposal(
                    topic_id=mid,
                    label=orig.label,
                    parent_topic_id=parent_topic_id,
                    parent_label=parent_label,
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

        has_any_parent = any(
            p.parent_topic_id is not None or p.parent_label is not None for p in deduped
        )
        if not has_any_parent and len(canonical_ids) >= 3:
            for p in deduped:
                domain = cls.classify_text_domain(p.label)
                if domain:
                    p.parent_label = domain
                    break

        return UserTopicGraphCuratorOutput(topics=deduped)

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
        if cids | merged_ids != expected_topic_ids:
            raise ValueError("topic graph must partition every eligible topic exactly once")
        if any(
            p.parent_topic_id in merged_ids for p in output.topics if p.parent_topic_id is not None
        ):
            raise ValueError("topic graph parents a topic that is being merged")
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
