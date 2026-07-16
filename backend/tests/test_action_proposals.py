"""Tests for the proposal-returning native tools (create_room, set_conversation_style)."""

import pytest

from app.services.native_tools import (
    ALL_NATIVE_TOOLS,
    CREATE_ROOM_TOOL,
    PROPOSAL_TOOLS,
    SET_STYLE_TOOL,
    execute_native_tool,
    native_tool_descriptors,
)

pytestmark = pytest.mark.asyncio

OWNER = "test@example.com"


async def _run(db, name, args):
    return await execute_native_tool(name=name, args=args, db=db, user_id=OWNER)


class TestRegistration:
    async def test_proposal_tools_registered(self):
        for tool in PROPOSAL_TOOLS:
            assert tool in ALL_NATIVE_TOOLS
        names = [d["function"]["name"] for d in native_tool_descriptors()]
        assert CREATE_ROOM_TOOL in names
        assert SET_STYLE_TOOL in names

    async def test_descriptors_say_proposal_not_action(self):
        for d in native_tool_descriptors():
            if d["function"]["name"] in PROPOSAL_TOOLS:
                assert "proposal" in d["function"]["description"].lower()


class TestCreateRoomProposal:
    async def test_valid_proposal_never_touches_db(self, db_session):
        from sqlalchemy import select

        from app.models.room import Room

        result = await _run(
            db_session,
            CREATE_ROOM_TOOL,
            {
                "name": "Research",
                "member_emails": ["Ana@Example.com"],
                "agents": [{"name": "Researcher", "model": "qwen3"}],
            },
        )
        assert result["ok"] is True
        proposal = result["proposal"]
        assert proposal["type"] == CREATE_ROOM_TOOL
        assert proposal["payload"]["name"] == "Research"
        # Emails normalized to lowercase.
        assert proposal["payload"]["member_emails"] == ["ana@example.com"]
        assert proposal["payload"]["agents"][0]["response_mode"] == "mention"
        assert "Research" in proposal["summary"]
        assert "proposal" in result["note"].lower()
        # Proposing must not create anything.
        rooms = (await db_session.execute(select(Room))).scalars().all()
        assert rooms == []

    async def test_name_required(self, db_session):
        result = await _run(db_session, CREATE_ROOM_TOOL, {"name": "  "})
        assert result["ok"] is False

    async def test_invalid_email_rejected(self, db_session):
        result = await _run(
            db_session,
            CREATE_ROOM_TOOL,
            {"name": "R", "member_emails": ["not-an-email"]},
        )
        assert result["ok"] is False
        assert "not-an-email" in result["error"]

    async def test_agent_needs_name_and_model(self, db_session):
        result = await _run(
            db_session,
            CREATE_ROOM_TOOL,
            {"name": "R", "agents": [{"name": "NoModel"}]},
        )
        assert result["ok"] is False

    async def test_bad_response_mode_rejected(self, db_session):
        result = await _run(
            db_session,
            CREATE_ROOM_TOOL,
            {"name": "R", "agents": [{"name": "A", "model": "m", "response_mode": "sometimes"}]},
        )
        assert result["ok"] is False


class TestSetStyleProposal:
    async def test_valid_proposal(self, db_session):
        result = await _run(
            db_session,
            SET_STYLE_TOOL,
            {"model": "qwen3", "thinking_level": "high"},
        )
        assert result["ok"] is True
        proposal = result["proposal"]
        assert proposal["type"] == SET_STYLE_TOOL
        assert proposal["payload"] == {
            "model": "qwen3",
            "thinking_level": "high",
            "system_prompt": None,
        }
        assert "qwen3" in proposal["summary"]

    async def test_requires_at_least_one_change(self, db_session):
        result = await _run(db_session, SET_STYLE_TOOL, {})
        assert result["ok"] is False

    async def test_rejects_unknown_thinking_level(self, db_session):
        result = await _run(db_session, SET_STYLE_TOOL, {"thinking_level": "max"})
        assert result["ok"] is False
