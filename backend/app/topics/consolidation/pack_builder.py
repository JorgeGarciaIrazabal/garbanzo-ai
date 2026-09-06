"""Deterministic context-pack assembly and version snapshot persistence."""

from __future__ import annotations

import uuid
from datetime import UTC, datetime
from typing import Any

from sqlalchemy.ext.asyncio import AsyncSession

from app.topics.consolidation.reconciler import TopicReconciler
from app.topics.models import (
    Topic,
    TopicAssertion,
    TopicContextVersion,
    TopicExclusion,
)
from app.topics.topic_semantic_curator import CuratedContextPack

PROMPT_VERSION = "evidence-pack-v1"

_SECTION_BY_KIND = {
    "goal": "goal",
    "fact": "facts",
    "decision": "decisions",
    "preference": "preferences",
    "constraint": "constraints",
    "deadline": "deadlines",
    "open_loop": "open_loops",
}


class ContextPackBuilder:
    """Assembles curated context packs and manages immutable version snapshots."""

    @staticmethod
    def build_deterministic_pack(
        topic: Topic,
        assertions: list[TopicAssertion],
        exclusions: list[TopicExclusion],
        valid_evidence: dict[str, list[str]],
    ) -> CuratedContextPack:
        excluded_assertions, excluded_sources, privacy_assertions, exclude_topic = (
            TopicReconciler.exclusion_sets(exclusions, topic.id)
        )
        pack_data: dict[str, Any] = {
            "topic": {"id": topic.id, "label": topic.label, "parent_id": topic.parent_id},
            **{section: [] for section in _SECTION_BY_KIND.values()},
            "negative_guardrails": [],
        }
        for assertion in assertions:
            evidence_ids = [
                message_id
                for message_id in valid_evidence.get(assertion.id, [])
                if message_id not in excluded_sources
            ]
            if exclude_topic:
                continue
            if not evidence_ids:
                continue
            if assertion.id in privacy_assertions:
                continue
            if assertion.status == "rejected" or assertion.id in excluded_assertions:
                pack_data["negative_guardrails"].append(
                    {
                        "assertion_id": assertion.id,
                        "evidence_ids": evidence_ids,
                        "instruction": (
                            "Do not reintroduce this previously rejected option unless "
                            "the user explicitly reverses the decision."
                        ),
                    }
                )
                continue
            if assertion.status != "active":
                continue
            section = _SECTION_BY_KIND.get(assertion.kind)
            if section is None:
                continue
            pack_data[section].append(
                {
                    "assertion_id": assertion.id,
                    "evidence_ids": evidence_ids,
                    "content": assertion.content,
                    "authority": assertion.authority,
                    "confidence": assertion.confidence,
                }
            )
        return CuratedContextPack.model_validate(pack_data)

    @staticmethod
    def short_summary(topic: Topic, pack: CuratedContextPack) -> str:
        count = sum(len(getattr(pack, section)) for section in _SECTION_BY_KIND.values())
        loops = len(pack.open_loops)
        if count == 0:
            return f"No confirmed context for {topic.label} yet."
        suffix = f"; {loops} open loop{'s' if loops != 1 else ''}" if loops else ""
        return (
            f"{count} grounded context item{'s' if count != 1 else ''} for {topic.label}{suffix}."
        )

    @classmethod
    async def create_context_version(
        cls,
        db: AsyncSession,
        topic: Topic,
        pack: CuratedContextPack,
        *,
        source_event_watermark: int | None,
        current_pack: TopicContextVersion | None,
        current_max: int | None,
        model_id: str | None,
        provider_name: str,
        prompt_version: str,
        is_semantic: bool,
    ) -> TopicContextVersion:
        watermark = max(
            source_event_watermark or 0,
            current_pack.source_event_watermark if current_pack else 0,
        )
        version = TopicContextVersion(
            id=str(uuid.uuid4()),
            topic_id=topic.id,
            version=(current_max or 0) + 1,
            context_json=pack.model_dump(mode="json"),
            short_summary=cls.short_summary(topic, pack),
            source_event_watermark=watermark or 0,
            model_id=model_id,
            provider=provider_name,
            prompt_version=prompt_version,
            validation_status="validated" if is_semantic and model_id else "valid",
        )
        db.add(version)
        await db.flush()

        topic.current_context_version_id = version.id
        topic.last_consolidated_at = datetime.now(UTC)
        topic.dirty_since = None
        await db.flush()

        db.expunge(version)
        return version
