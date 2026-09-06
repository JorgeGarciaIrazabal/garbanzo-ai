"""Bounded carry-over extraction from archived primary thread (single-shot LLM + deterministic fallback)."""

from __future__ import annotations

import json
import logging
from typing import Any

from pydantic import BaseModel, ConfigDict, Field, ValidationError
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import get_settings
from app.models.user import User
from app.schemas.chat import ChatOptions
from app.services.llm_provider import Message as LLMMessage
from app.services.llm_provider import ProviderRegistry
from app.services.token_counter import get_token_counter

logger = logging.getLogger(__name__)

CARRYOVER_PROMPT_VERSION = "topic-switch-carryover-v1"


class CarryoverItem(BaseModel):
    model_config = ConfigDict(extra="forbid")
    title: str = Field(min_length=1, max_length=120)
    content: str = Field(min_length=1, max_length=500)
    source_message_id: str | None = None


class CarryoverOutput(BaseModel):
    model_config = ConfigDict(extra="forbid")
    items: list[CarryoverItem] = Field(default_factory=list, max_length=20)


class CarryoverExtractor:
    def __init__(self, db: AsyncSession):
        self.db = db

    async def extract(
        self,
        *,
        user: User,
        archived_payload: list[dict[str, Any]],
        new_topic_label: str,
        max_items: int,
        max_tokens: int,
    ) -> list[CarryoverItem]:
        if not archived_payload:
            return []
        candidates = self._deterministic_fallback(archived_payload, max_items)
        try:
            curated = await self._call_model(
                user=user,
                archived_payload=archived_payload,
                new_topic_label=new_topic_label,
                max_items=max_items,
            )
        except Exception as exc:
            logger.warning("Carryover extractor fell back to deterministic; %s", exc)
            return candidates
        return self._cap(curated or candidates, max_items, max_tokens)

    async def _call_model(
        self,
        *,
        user: User,
        archived_payload: list[dict[str, Any]],
        new_topic_label: str,
        max_items: int,
    ) -> list[CarryoverItem] | None:
        provider_name = get_settings().topic_curator_provider
        model = get_settings().topic_curator_model
        if not provider_name or not model:
            return None
        provider = ProviderRegistry.get(provider_name)
        if provider is None:
            return None
        if not provider.supports_structured_output and ":cloud" not in model.casefold():
            return None
        payload = {
            "from_topic": archived_payload[0].get("topic_label") if archived_payload else None,
            "to_topic": new_topic_label,
            "max_items": max_items,
            "messages": [
                {"id": m.get("id"), "role": m.get("role"), "content": m.get("content", "")[:1200]}
                for m in archived_payload[-40:]
            ],
        }
        system_prompt = "You extract a tiny, high-signal carry-over set from a prior chat topic that the user is leaving. Each item must be a fact, decision, preference, or open loop that is still relevant to the user's broader goals and worth surfacing in the new topic. Do not invent facts. Quote message IDs when known. Return one raw JSON object matching the schema. No markdown, no prose."
        messages = [
            LLMMessage(role="system", content=system_prompt),
            LLMMessage(
                role="user", content=json.dumps(payload, ensure_ascii=False, separators=(",", ":"))
            ),
        ]
        options = ChatOptions(
            temperature=0,
            max_tokens=1500,
            think=False,
            response_format=CarryoverOutput.model_json_schema(),
        )
        for attempt in range(2):
            try:
                response = await provider.chat(messages=messages, model=model, options=options)
            except Exception:
                return None
            try:
                return CarryoverOutput.model_validate_json(response).items
            except (ValidationError, ValueError, TypeError, json.JSONDecodeError) as exc:
                if attempt == 1:
                    logger.info("Carryover extractor invalid output twice: %s", exc)
                    return None
                messages = [
                    *messages,
                    LLMMessage(role="assistant", content=response[:6000]),
                    LLMMessage(
                        role="user",
                        content="Your previous response was invalid. Return exactly one raw JSON object matching the schema. No markdown.",
                    ),
                ]

        return None

    def _deterministic_fallback(
        self, archived_payload: list[dict[str, Any]], max_items: int
    ) -> list[CarryoverItem]:
        fallback: list[CarryoverItem] = []
        for message in reversed(archived_payload):
            if message.get("role") != "user":
                continue
            content = (message.get("content") or "").strip()
            if not content:
                continue
            fallback.append(
                CarryoverItem(
                    title=content[:80].splitlines()[0],
                    content=content[:500],
                    source_message_id=message.get("id"),
                )
            )
            if len(fallback) >= max_items:
                break
        return fallback

    def _cap(
        self, items: list[CarryoverItem], max_items: int, max_tokens: int
    ) -> list[CarryoverItem]:
        capped = items[:max_items]
        counter = get_token_counter()
        budget = max_tokens
        result: list[CarryoverItem] = []
        for item in capped:
            used = counter.count_messages([item.content])
            if used > budget:
                break
            result.append(item)
            budget -= used
        return result


async def make_carryover_context_items(items: list[CarryoverItem]) -> list[dict[str, Any]]:
    out: list[dict[str, Any]] = []
    for index, item in enumerate(items):
        out.append(
            {
                "source_type": "carryover",
                "source_id": item.source_message_id or f"carryover-{index}",
                "source_meta": {"title": item.title, "version": CARRYOVER_PROMPT_VERSION},
                "reason": f"Carryover from previous topic: {item.title}",
                "content": item.content,
            }
        )
    return out
