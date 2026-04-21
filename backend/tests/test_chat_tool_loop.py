"""Tests for the tool-calling loop in ChatService.send_message."""

from collections.abc import AsyncIterator
from unittest.mock import AsyncMock, patch

import pytest

from app.schemas.chat import ChatOptions
from app.services.chat_service import MAX_TOOL_ITERATIONS, ChatService
from app.services.conversation_service import ConversationService
from app.services.llm_provider import ChatChunk, LLMProvider, ModelInfo
from app.services.llm_provider import Message as LLMMessage

pytestmark = pytest.mark.asyncio


class _ScriptedProvider(LLMProvider):
    """Provider that plays back a scripted sequence of chunks per iteration.

    ``responses`` is a list where each entry is the chunk list to emit for that
    iteration. When the loop runs past the end of the list the last entry is
    reused.
    """

    def __init__(self, responses: list[list[ChatChunk]]):
        self.responses = responses
        self.calls: list[dict] = []
        self.iteration = 0

    @property
    def name(self) -> str:
        return "scripted"

    async def stream_chat(
        self,
        messages: list[LLMMessage],
        model: str,
        options: ChatOptions | None = None,
        cancel_event=None,
        tools=None,
    ) -> AsyncIterator[ChatChunk]:
        self.calls.append({"messages": list(messages), "tools": tools})
        idx = min(self.iteration, len(self.responses) - 1)
        chunks = self.responses[idx]
        self.iteration += 1
        for c in chunks:
            yield c

    async def chat(self, messages, model, options=None, tools=None) -> str:  # pragma: no cover
        return ""

    async def list_models(self) -> list[ModelInfo]:  # pragma: no cover
        return []

    async def health_check(self) -> bool:  # pragma: no cover
        return True


async def _make_service(db_session, provider: _ScriptedProvider) -> ChatService:
    # Bypass OllamaProvider registration by injecting the scripted provider.
    service = ChatService(db_session, provider_name="scripted")
    from app.services.llm_provider import ProviderRegistry

    ProviderRegistry.register(provider)
    return service


async def _new_conversation(db, user_id: str, *, enabled_tools=None) -> str:
    convs = ConversationService(db)
    conv = await convs.create(user_id=user_id, title="Tool test")
    if enabled_tools is not None:
        conv.enabled_tools = enabled_tools
    await db.commit()
    return conv.id


async def test_no_tool_calls_behaves_like_before(db_session, test_user_email):
    provider = _ScriptedProvider(
        [
            [
                ChatChunk(content="hello ", is_finished=False),
                ChatChunk(content="world", is_finished=False),
                ChatChunk(content="", is_finished=True, metadata={"tokens_generated": 2}),
            ]
        ]
    )
    service = await _make_service(db_session, provider)
    conv_id = await _new_conversation(db_session, test_user_email, enabled_tools=[])

    chunks = []
    async for c in service.send_message(
        conversation_id=conv_id,
        user_id=test_user_email,
        content="hi",
    ):
        chunks.append(c)

    # One scripted iteration, no tool calls.
    assert provider.iteration == 1
    assert any(c.is_finished for c in chunks)
    assert "".join(c.content for c in chunks if c.content and not c.is_thinking) == "hello world"


async def test_tool_call_persists_messages_and_loops(db_session, test_user_email):
    tool_calls = [{"id": "call-1", "name": "srv:echo", "arguments": {"x": 1}}]
    provider = _ScriptedProvider(
        [
            [
                ChatChunk(content="", is_finished=False, tool_calls=tool_calls),
                ChatChunk(content="", is_finished=True, metadata={"has_tool_calls": True}),
            ],
            [
                ChatChunk(content="final answer", is_finished=False),
                ChatChunk(content="", is_finished=True, metadata={}),
            ],
        ]
    )
    service = await _make_service(db_session, provider)
    conv_id = await _new_conversation(db_session, test_user_email, enabled_tools=[])

    # Patch MCPService.call_tool so we don't need a real MCP server. The
    # conversation has enabled_tools=[] which means "no tools advertised to
    # the LLM", but the scripted provider emits a tool_call anyway — we still
    # need the execution path to work.
    async def _fake_call_tool(server_id, tool_name, args):
        return {"ok": True, "content": f"echo:{args}", "is_error": False}

    with patch(
        "app.services.chat_service.MCPService.call_tool",
        new=AsyncMock(side_effect=_fake_call_tool),
    ):
        collected = []
        async for c in service.send_message(
            conversation_id=conv_id,
            user_id=test_user_email,
            content="please echo",
        ):
            collected.append(c)

    # Provider should have been invoked twice (initial + after tool result).
    assert provider.iteration == 2

    # Verify persisted messages include tool_call + tool_result roles.
    from sqlalchemy import select

    from app.models.message import Message

    result = await db_session.execute(
        select(Message).where(Message.conversation_id == conv_id).order_by(Message.created_at)
    )
    roles = [m.role for m in result.scalars().all()]
    assert "tool_call" in roles
    assert "tool_result" in roles
    assert roles[-1] == "assistant"  # final answer


async def test_iteration_cap_enforced(db_session, test_user_email):
    tool_calls = [{"id": "call", "name": "srv:loop", "arguments": {}}]
    # Every iteration keeps emitting tool_calls → loop should cap out.
    chunks_per_iter = [
        ChatChunk(content="", is_finished=False, tool_calls=tool_calls),
        ChatChunk(content="", is_finished=True, metadata={"has_tool_calls": True}),
    ]
    provider = _ScriptedProvider([chunks_per_iter])  # repeats indefinitely
    service = await _make_service(db_session, provider)
    conv_id = await _new_conversation(db_session, test_user_email, enabled_tools=[])

    async def _fake_call_tool(server_id, tool_name, args):
        return {"ok": True, "content": "ok"}

    with patch(
        "app.services.chat_service.MCPService.call_tool",
        new=AsyncMock(side_effect=_fake_call_tool),
    ):
        collected = []
        async for c in service.send_message(
            conversation_id=conv_id,
            user_id=test_user_email,
            content="loop",
        ):
            collected.append(c)

    assert provider.iteration == MAX_TOOL_ITERATIONS
    # Last chunk should be the soft-error "tool_iteration_cap".
    assert any(
        (c.metadata or {}).get("error_type") == "tool_iteration_cap" for c in collected
    )
