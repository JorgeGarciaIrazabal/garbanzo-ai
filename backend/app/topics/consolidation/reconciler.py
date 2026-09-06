"""Topic reconciler: evidence verification, assertion grounding, and exclusion resolution."""

from __future__ import annotations

import re

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.conversation import Conversation
from app.models.message import Message
from app.topics.models import (
    Topic,
    TopicAssertion,
    TopicAssertionEvidence,
    TopicExclusion,
)
from app.topics.topic_semantic_curator import CuratedContextPack

_SECTION_BY_KIND = {
    "goal": "goal",
    "fact": "facts",
    "decision": "decisions",
    "preference": "preferences",
    "constraint": "constraints",
    "deadline": "deadlines",
    "open_loop": "open_loops",
}

_REJECTION_TEXT = re.compile(r"\b(?:don't use|do not use|ruled out|rejected|forget|remove)\b", re.I)
_GROUNDING_STOP_WORDS = set(
    [
        "about",
        "also",
        "and",
        "are",
        "for",
        "from",
        "has",
        "have",
        "the",
        "their",
        "this",
        "user",
        "was",
        "with",
    ]
)  # noqa: SIM905


class TopicReconciler:
    """Verifies evidence provenance and ensures assertions are strictly grounded in source spans."""

    @staticmethod
    def exclusion_sets(
        exclusions: list[TopicExclusion], topic_id: str
    ) -> tuple[set[str], set[str], set[str], bool]:
        """Split hard exclusions into deterministic filters for one topic."""
        excluded_assertions: set[str] = set()
        excluded_sources: set[str] = set()
        privacy_assertions: set[str] = set()
        exclude_topic = False
        for exclusion in exclusions:
            if exclusion.scope == "all_topics" or (
                exclusion.scope == "topic"
                and (exclusion.target_id in {None, topic_id} or exclusion.topic_id == topic_id)
            ):
                exclude_topic = True
            elif exclusion.scope == "assertion" and exclusion.target_id:
                excluded_assertions.add(exclusion.target_id)
                if exclusion.is_privacy_deletion:
                    privacy_assertions.add(exclusion.target_id)
            elif exclusion.scope == "source" and exclusion.target_id:
                excluded_sources.add(exclusion.target_id)
        return excluded_assertions, excluded_sources, privacy_assertions, exclude_topic

    @staticmethod
    async def valid_evidence(db: AsyncSession, user_id: str, topic_id: str) -> dict[str, list[str]]:
        """Find valid evidence message IDs for all assertions of a topic."""
        rows = (
            await db.execute(
                select(
                    TopicAssertionEvidence.assertion_id,
                    TopicAssertionEvidence.message_id,
                )
                .join(
                    TopicAssertion,
                    TopicAssertion.id == TopicAssertionEvidence.assertion_id,
                )
                .join(Message, Message.id == TopicAssertionEvidence.message_id)
                .join(Conversation, Conversation.id == Message.conversation_id)
                .where(
                    TopicAssertion.topic_id == topic_id,
                    Conversation.user_id == user_id,
                    Conversation.is_deleted.is_(False),
                )
            )
        ).all()
        result: dict[str, list[str]] = {}
        for assertion_id, message_id in rows:
            result.setdefault(assertion_id, []).append(message_id)
        return result

    @classmethod
    async def validate_pack(
        cls,
        db: AsyncSession,
        topic: Topic,
        pack: CuratedContextPack,
        valid_evidence: dict[str, list[str]] | None = None,
    ) -> None:
        """Reject any unknown, cross-topic, or ungrounded assertion/evidence ID."""
        evidence = valid_evidence or await cls.valid_evidence(db, topic.user_id, topic.id)
        for section in _SECTION_BY_KIND.values():
            for item in getattr(pack, section):
                if item.assertion_id not in evidence:
                    raise ValueError("context pack contains an unknown assertion")
                if not set(item.evidence_ids).issubset(evidence[item.assertion_id]):
                    raise ValueError("context pack contains unowned evidence")
        for item in pack.negative_guardrails:
            if item.assertion_id not in evidence:
                raise ValueError("context pack contains an unknown guardrail")
            if not set(item.evidence_ids).issubset(evidence[item.assertion_id]):
                raise ValueError("context pack contains unowned guardrail evidence")

    @classmethod
    async def validate_semantic_pack(
        cls,
        db: AsyncSession,
        topic: Topic,
        pack: CuratedContextPack,
        deterministic_pack: CuratedContextPack,
        valid_evidence: dict[str, list[str]],
    ) -> None:
        """Require model output to be an exact subset of the safe manifest."""
        await cls.validate_pack(db, topic, pack, valid_evidence)
        if pack.topic != deterministic_pack.topic:
            raise ValueError("context pack changed topic identity")

        seen: set[str] = set()
        expected: set[str] = set()
        for section in (*_SECTION_BY_KIND.values(), "negative_guardrails"):
            allowed = {
                item.assertion_id: item.model_dump(mode="json")
                for item in getattr(deterministic_pack, section)
            }
            expected.update(allowed)
            for item in getattr(pack, section):
                if item.assertion_id in seen:
                    raise ValueError("context pack duplicated an assertion")
                seen.add(item.assertion_id)
                if item.assertion_id not in allowed:
                    raise ValueError("context pack moved or invented an assertion")
                if item.model_dump(mode="json") != allowed[item.assertion_id]:
                    raise ValueError("context pack altered grounded assertion content")
        if seen != expected:
            raise ValueError("context pack omitted grounded assertions")

    @staticmethod
    def lexically_grounded(content: str, source_text: str) -> bool:
        """Verify that synthesis terms are substantially present in the source excerpt."""
        content_terms = {
            term
            for term in re.findall(r"[\w-]{3,}", content.casefold())
            if term not in _GROUNDING_STOP_WORDS
        }
        source_terms = set(re.findall(r"[\w-]{3,}", source_text.casefold()))
        if not content_terms:
            return False
        return len(content_terms & source_terms) / len(content_terms) >= 0.6
