"""Tests for the dynamic <context> block (time / timezone / location)."""

from datetime import UTC, datetime

import pytest

from app.services.chat_context import build_dynamic_context_block
from app.services.chat_service import ChatService

pytestmark = pytest.mark.asyncio

# A fixed instant so assertions are deterministic: a Thursday, 14:30 UTC,
# which is 10:30 in New York (EDT) — crossing no date boundary — and
# 23:30 in Tokyo, crossing one.
_NOW = datetime(2026, 7, 16, 14, 30, tzinfo=UTC)


class TestBlockFormat:
    async def test_utc_time_always_present(self):
        block = build_dynamic_context_block(now=_NOW)
        assert block.startswith("<context>")
        assert block.endswith("</context>")
        assert "Current UTC time: Thursday 2026-07-16 14:30 UTC" in block

    async def test_framed_as_background_only(self):
        block = build_dynamic_context_block(now=_NOW)
        assert "Use it only when the user's request actually depends on it" in block

    async def test_local_time_with_timezone(self):
        block = build_dynamic_context_block(timezone="America/New_York", now=_NOW)
        assert "User's local time: Thursday 2026-07-16 10:30 (America/New_York)" in block

    async def test_local_time_crosses_date_boundary(self):
        block = build_dynamic_context_block(timezone="Asia/Tokyo", now=_NOW)
        assert "User's local time: Thursday 2026-07-16 23:30 (Asia/Tokyo)" in block

    async def test_no_timezone_no_local_line(self):
        block = build_dynamic_context_block(now=_NOW)
        assert "local time" not in block

    async def test_unknown_timezone_skips_line_keeps_block(self):
        # Validated at the API boundary; render must still survive a zone
        # the server's zoneinfo no longer knows.
        block = build_dynamic_context_block(timezone="Mars/Olympus_Mons", now=_NOW)
        assert "local time" not in block
        assert "Current UTC time:" in block

    async def test_location_line_when_shared(self):
        block = build_dynamic_context_block(location="Madrid, Spain", now=_NOW)
        assert "User's approximate location: Madrid, Spain" in block

    async def test_no_location_line_by_default(self):
        block = build_dynamic_context_block(now=_NOW)
        assert "location" not in block


class TestGeocodingFormat:
    async def test_city_and_country(self):
        from app.services.geocoding import format_city

        assert format_city({"address": {"city": "Madrid", "country": "Spain"}}) == "Madrid, Spain"

    async def test_town_fallback(self):
        from app.services.geocoding import format_city

        assert format_city({"address": {"town": "Ronda", "country": "Spain"}}) == "Ronda, Spain"

    async def test_country_only(self):
        from app.services.geocoding import format_city

        assert format_city({"address": {"country": "Spain"}}) == "Spain"

    async def test_nothing_useful_returns_none(self):
        from app.services.geocoding import format_city

        assert format_city({}) is None
        assert format_city({"address": {}}) is None


class TestSystemPromptComposition:
    async def _make_service(self, db_session):
        svc = ChatService(db_session)

        async def _empty(*_args, **_kwargs):
            return []

        svc._memories.get_relevant_memories = _empty  # type: ignore[assignment]
        return svc

    async def test_block_appended_after_base_prompt(self, db_session):
        svc = await self._make_service(db_session)
        block = build_dynamic_context_block(timezone="Europe/Madrid", now=_NOW)
        prompt, _stats = await svc._context.build_system_prompt(
            user_id="test@example.com",
            use_memory=False,
            use_knowledge_base=False,
            conversation_system_prompt="You are a pirate.",
            dynamic_context=block,
        )
        assert prompt.startswith("You are a pirate.")
        assert prompt.endswith("</context>")
        assert "Europe/Madrid" in prompt

    async def test_block_alone_needs_no_fallback_prompt(self, db_session):
        """Unlike memories/KB, the block must not drag in the generic
        'You are a helpful AI assistant.' base prompt."""
        svc = await self._make_service(db_session)
        block = build_dynamic_context_block(now=_NOW)
        prompt, _stats = await svc._context.build_system_prompt(
            user_id="test@example.com",
            use_memory=False,
            use_knowledge_base=False,
            dynamic_context=block,
        )
        assert prompt == block

    async def test_absent_when_not_provided(self, db_session):
        svc = await self._make_service(db_session)
        prompt, _stats = await svc._context.build_system_prompt(
            user_id="test@example.com",
            use_memory=False,
            use_knowledge_base=False,
            conversation_system_prompt="Base.",
        )
        assert "<context>" not in prompt
