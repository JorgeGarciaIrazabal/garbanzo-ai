"""Tests for the proposal-returning native tools (create_room, set_conversation_style)."""

from collections.abc import AsyncIterator

import pytest

from app.schemas.chat import ChatOptions
from app.services.chat_service import ChatService
from app.services.conversation_service import ConversationService
from app.services.llm_provider import ChatChunk, LLMProvider, ModelInfo, ProviderRegistry
from app.services.llm_provider import Message as LLMMessage
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


class _ScriptedProvider(LLMProvider):
    """First iteration calls create_room; second gives the final answer."""

    def __init__(self, tool_args: dict):
        self.iteration = 0
        self.tool_args = tool_args

    @property
    def name(self) -> str:
        return "proposal-scripted"

    async def stream_chat(
        self,
        messages: list[LLMMessage],
        model: str,
        options: ChatOptions | None = None,
        cancel_event=None,
        tools=None,
    ) -> AsyncIterator[ChatChunk]:
        self.iteration += 1
        if self.iteration == 1:
            yield ChatChunk(
                content="",
                is_finished=False,
                tool_calls=[
                    {"id": "call-1", "name": CREATE_ROOM_TOOL, "arguments": self.tool_args}
                ],
            )
            yield ChatChunk(content="", is_finished=True, metadata={"has_tool_calls": True})
        else:
            yield ChatChunk(content="please confirm", is_finished=False)
            yield ChatChunk(content="", is_finished=True, metadata={})

    async def chat(self, messages, model, options=None, tools=None) -> str:  # pragma: no cover
        return ""

    async def list_models(self) -> list[ModelInfo]:  # pragma: no cover
        return []

    async def health_check(self) -> bool:  # pragma: no cover
        return True


class TestActionProposalChunk:
    async def test_proposal_tool_call_emits_action_proposal_chunk(
        self, db_session, test_user_email
    ):
        """A create_room tool call must surface an action_proposal chunk
        (IDEAS.md 4.6) alongside the persisted tool_result."""
        provider = _ScriptedProvider({"name": "Research"})
        ProviderRegistry.register(provider)
        service = ChatService(db_session, provider_name=provider.name)
        conv = await ConversationService(db_session).create(
            user_id=test_user_email, title="Proposal test"
        )
        await db_session.commit()

        chunks = []
        async for c in service.send_message(
            conversation_id=conv.id,
            user_id=test_user_email,
            content="make a room",
        ):
            chunks.append(c)

        proposals = [
            c.metadata["action_proposal"]
            for c in chunks
            if c.metadata and c.metadata.get("action_proposal")
        ]
        assert len(proposals) == 1
        assert proposals[0]["type"] == CREATE_ROOM_TOOL
        assert proposals[0]["tool_call_id"] == "call-1"
        assert proposals[0]["payload"]["name"] == "Research"
        # The regular tool_result chunk (and thus its persisted message,
        # which reloads render the card from) still flows.
        assert any(c.metadata and c.metadata.get("tool_result") for c in chunks)

    async def test_direct_tools_emit_no_proposal_chunk(self, db_session, test_user_email):
        """A failed/direct tool result (no 'proposal' key) must not fabricate
        a proposal chunk."""
        provider = _ScriptedProvider({"name": ""})  # invalid → ok:False result
        ProviderRegistry.register(provider)
        service = ChatService(db_session, provider_name=provider.name)
        conv = await ConversationService(db_session).create(
            user_id=test_user_email, title="No proposal"
        )
        await db_session.commit()

        chunks = []
        async for c in service.send_message(
            conversation_id=conv.id,
            user_id=test_user_email,
            content="make a room",
        ):
            chunks.append(c)

        assert not any(c.metadata and c.metadata.get("action_proposal") for c in chunks)


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
