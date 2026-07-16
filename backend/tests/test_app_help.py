"""Tests for the app_help native tool and its guide retrieval."""

import pytest

from app.services import app_help
from app.services.app_help import search_help
from app.services.native_tools import (
    ALL_NATIVE_TOOLS,
    APP_HELP_TOOL,
    execute_native_tool,
    native_tool_descriptors,
    native_tool_lookup,
)

pytestmark = pytest.mark.asyncio


class TestSearchHelp:
    async def test_finds_exact_how_do_i_question(self):
        results = search_help("how do I pin a conversation")
        assert results, "expected at least one result"
        assert "pin" in results[0]["heading"].lower()
        assert results[0]["area"] == "Chat"
        assert results[0]["content"]

    async def test_area_words_steer_between_twin_features(self):
        # Both chat and rooms have a mute section; "room" must win Rooms.
        results = search_help("mute a room")
        assert "Rooms" in results[0]["area"]
        assert "mute" in results[0]["heading"].lower()

    async def test_what_is_questions_hit_the_intro_section(self):
        results = search_help("what are rooms")
        assert "Rooms" in results[0]["area"]
        assert results[0]["heading"].startswith("What is")

    async def test_no_overlap_returns_empty(self):
        assert search_help("zzqx flurbo grommit") == []

    async def test_blank_query_returns_empty(self):
        assert search_help("   ") == []

    async def test_limit_caps_results(self):
        assert len(search_help("how do I delete a conversation", limit=1)) == 1

    async def test_corpus_loads_once_and_is_nonempty(self):
        sections = app_help._sections()
        assert len(sections) > 30
        assert app_help._sections() is sections  # cached, not re-parsed


class TestAppHelpTool:
    async def test_registered_as_native_tool(self):
        assert APP_HELP_TOOL in ALL_NATIVE_TOOLS
        names = [d["function"]["name"] for d in native_tool_descriptors()]
        assert APP_HELP_TOOL in names
        assert APP_HELP_TOOL in native_tool_lookup()

    async def test_execute_returns_guide_sections(self, db_session):
        result = await execute_native_tool(
            name=APP_HELP_TOOL,
            args={"query": "how do I mute a room"},
            db=db_session,
            user_id="test@example.com",
        )
        assert result["ok"] is True
        assert result["results"]
        assert "mute" in result["results"][0]["heading"].lower()

    async def test_execute_no_match_says_so(self, db_session):
        result = await execute_native_tool(
            name=APP_HELP_TOOL,
            args={"query": "zzqx flurbo grommit"},
            db=db_session,
            user_id="test@example.com",
        )
        assert result["ok"] is True
        assert result["results"] == []
        assert "note" in result

    async def test_execute_requires_query(self, db_session):
        result = await execute_native_tool(
            name=APP_HELP_TOOL,
            args={},
            db=db_session,
            user_id="test@example.com",
        )
        assert result["ok"] is False
