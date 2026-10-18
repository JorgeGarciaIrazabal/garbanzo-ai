"""Tests for the tool-calling loop in ChatService.send_message."""

import uuid
from collections.abc import AsyncIterator
from types import SimpleNamespace
from unittest.mock import AsyncMock, patch

import pytest
from sqlalchemy import select

from app.models.message import Message
from app.schemas.chat import ChatOptions
from app.schemas.visual_ui import Presentation, UISubmission
from app.services.chat_service import MAX_TOOL_ITERATIONS, ChatService
from app.services.conversation_service import ConversationService
from app.services.detached_chat_stream import DetachedChatStream
from app.services.llm_provider import ChatChunk, LLMProvider, ModelInfo
from app.services.llm_provider import Message as LLMMessage
from app.services.visual_ui import UIActionService

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


async def test_iteration_cap_forces_final_no_tools_answer(db_session, test_user_email):
    tool_calls = [{"id": "call", "name": "srv:loop", "arguments": {}}]
    # Every iteration keeps emitting tool_calls → after the cap the engine
    # must run ONE extra pass without tools so the model produces an answer.
    loop_iter = [
        ChatChunk(content="", is_finished=False, tool_calls=tool_calls),
        ChatChunk(content="", is_finished=True, metadata={"has_tool_calls": True}),
    ]
    answer_iter = [
        ChatChunk(content="forced answer", is_finished=False),
        ChatChunk(content="", is_finished=True, metadata={}),
    ]
    provider = _ScriptedProvider([loop_iter] * MAX_TOOL_ITERATIONS + [answer_iter])
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

    # Capped iterations plus the final forced-answer pass.
    assert provider.iteration == MAX_TOOL_ITERATIONS + 1
    # The final pass must not be offered tools.
    assert provider.calls[-1]["tools"] is None
    final_messages = provider.calls[-1]["messages"]
    assert any(m.role == "tool" and "ok" in m.content for m in final_messages)
    assert "Finish the user's original request now" in final_messages[-1].content
    # No error chunk — the turn ends cleanly with the forced answer.
    assert not any((c.metadata or {}).get("error_type") for c in collected)
    text = "".join(c.content for c in collected if c.content and not c.is_thinking)
    assert "forced answer" in text
    # The finish chunk of the forced pass is flagged so clients can surface it.
    finish = [c for c in collected if c.is_finished]
    assert (finish[-1].metadata or {}).get("tool_iteration_cap") is True

    from sqlalchemy import select

    from app.models.message import Message

    result = await db_session.execute(
        select(Message).where(Message.conversation_id == conv_id).order_by(Message.created_at)
    )
    messages = list(result.scalars().all())
    assert messages[-1].role == "assistant"
    assert messages[-1].content == "forced answer"


async def test_capped_pass_drops_stray_tool_calls(db_session, test_user_email):
    tool_calls = [{"id": "call", "name": "srv:loop", "arguments": {}}]
    # The model asks for tools on EVERY pass, including the final no-tools
    # one — those stray calls must be dropped, not executed past the budget.
    loop_iter = [
        ChatChunk(content="", is_finished=False, tool_calls=tool_calls),
        ChatChunk(content="", is_finished=True, metadata={"has_tool_calls": True}),
    ]
    provider = _ScriptedProvider([loop_iter])  # repeats indefinitely
    service = await _make_service(db_session, provider)
    conv_id = await _new_conversation(db_session, test_user_email, enabled_tools=["srv:loop"])
    service._resolve_tools_for_conversation = AsyncMock(
        return_value=([], {"loop": ("srv", "loop")})
    )

    executions = []

    async def _fake_call_tool(server_id, tool_name, args):
        executions.append(tool_name)
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

    assert provider.iteration == MAX_TOOL_ITERATIONS + 2
    assert len(executions) == MAX_TOOL_ITERATIONS
    # The stray tool_call chunk from the capped pass is not forwarded.
    tool_call_chunks = [c for c in collected if c.tool_calls]
    assert len(tool_call_chunks) == MAX_TOOL_ITERATIONS
    assert (collected[-1].metadata or {}).get("error") is True


async def test_empty_capped_pass_recovers_an_answer_in_same_turn(db_session, test_user_email):
    """An empty final pass recovers from collected evidence without a user nudge."""
    tool_calls = [{"id": "call", "name": "web_search", "arguments": {"query": "x"}}]
    # Every iteration emits a tool call; the capped pass emits NOTHING (no
    # content, no stray tool call) — the dead-end shape that used to silently
    # return with no assistant message.
    loop_iter = [
        ChatChunk(content="", is_finished=False, tool_calls=tool_calls),
        ChatChunk(content="", is_finished=True, metadata={"has_tool_calls": True}),
    ]
    empty_capped_iter = [ChatChunk(content="", is_finished=True, metadata={})]
    answer = "The robot is available by contacting the vendor at https://example.com/buy."
    provider = _ScriptedProvider(
        [loop_iter] * MAX_TOOL_ITERATIONS
        + [empty_capped_iter, [ChatChunk(content=answer), ChatChunk(content="", is_finished=True)]]
    )
    service = await _make_service(db_session, provider)
    conv_id = await _new_conversation(db_session, test_user_email, enabled_tools=[])
    service._resolve_tools_for_conversation = AsyncMock(
        return_value=([], {"web_search": ("srv", "search")})
    )

    async def _fake_call_tool(server_id, tool_name, args):
        return {"ok": True, "content": "Buy the robot: https://example.com/buy"}

    with patch(
        "app.services.chat_service.MCPService.call_tool",
        new=AsyncMock(side_effect=_fake_call_tool),
    ):
        collected = []
        async for c in service.send_message(
            conversation_id=conv_id,
            user_id=test_user_email,
            content="How can I buy this robot?",
        ):
            collected.append(c)

    assert provider.iteration == MAX_TOOL_ITERATIONS + 2
    assert all(call["tools"] is None for call in provider.calls[-2:])
    for call in provider.calls[-2:]:
        assert any(
            m.role == "tool" and "https://example.com/buy" in m.content for m in call["messages"]
        )
    assert "previous attempt returned no answer" in provider.calls[-1]["messages"][-1].content
    assert not any((c.metadata or {}).get("error") for c in collected)
    text = "".join(c.content for c in collected if c.content and not c.is_thinking)
    assert text == answer
    # No successful finish for the empty attempt may escape before recovery.
    # The finish chunk is flagged so clients can surface the cap.
    finish = [c for c in collected if c.is_finished]
    assert len(finish) == MAX_TOOL_ITERATIONS + 1
    assert (finish[-1].metadata or {}).get("tool_iteration_cap") is True
    # The actual answer is persisted, never the internal synthesis prompt.
    from sqlalchemy import select

    from app.models.message import Message

    res = await db_session.execute(
        select(Message).where(Message.conversation_id == conv_id).order_by(Message.created_at)
    )
    messages = list(res.scalars().all())
    assert messages[-1].role == "assistant"
    assert messages[-1].content == text
    assert not any("Finish the user's original request" in m.content for m in messages)


async def test_clean_function_name_resolves_via_lookup(db_session, test_user_email):
    """When the model emits a clean (no-colon) function name, the chat
    service must resolve it back to the right (server_id, tool_name) via
    the per-request lookup built from the advertised tool list. Regression
    against the bug where colon-prefixed names broke spec-compliant LLMs."""
    server_id = "abc-123-server"
    fake_tools = [
        {
            "server_id": server_id,
            "server_name": "time",
            "name": "get_current_time",
            "description": "",
            "input_schema": {"type": "object", "properties": {}},
        }
    ]

    # Model emits a clean name ("get_current_time"), no server prefix.
    tool_calls = [{"id": "c1", "name": "get_current_time", "arguments": {"timezone": "UTC"}}]
    provider = _ScriptedProvider(
        [
            [
                ChatChunk(content="", is_finished=False, tool_calls=tool_calls),
                ChatChunk(content="", is_finished=True, metadata={}),
            ],
            [
                ChatChunk(content="done", is_finished=False),
                ChatChunk(content="", is_finished=True, metadata={}),
            ],
        ]
    )
    service = await _make_service(db_session, provider)
    conv_id = await _new_conversation(db_session, test_user_email)

    captured: dict = {}

    async def _fake_call_tool(srv, tool_name, args):
        captured["server_id"] = srv
        captured["tool_name"] = tool_name
        captured["args"] = args
        return {"ok": True, "content": "12:00"}

    with (
        patch(
            "app.services.chat_service.MCPService.list_all_tools",
            new=AsyncMock(return_value=fake_tools),
        ),
        patch(
            "app.services.chat_service.MCPService.call_tool",
            new=AsyncMock(side_effect=_fake_call_tool),
        ),
    ):
        async for _ in service.send_message(
            conversation_id=conv_id,
            user_id=test_user_email,
            content="what time is it",
        ):
            pass

    assert captured == {
        "server_id": server_id,
        "tool_name": "get_current_time",
        "args": {"timezone": "UTC"},
    }


async def test_each_iteration_yields_a_done_chunk(db_session, test_user_email):
    """Regression: the backend yields ONE ``done`` chunk per iteration of
    the tool-calling loop (one before tool execution, one after the final
    answer). Frontends must therefore treat ``done`` as iteration-scoped
    metadata and only finalize on the SSE stream's own end — otherwise a
    mid-stream reload races against in-flight chunks and erases them.
    This test pins the contract."""
    tool_calls = [{"id": "call-x", "name": "echo", "arguments": {"q": "hi"}}]
    provider = _ScriptedProvider(
        [
            [
                ChatChunk(content="", is_finished=False, tool_calls=tool_calls),
                ChatChunk(
                    content="",
                    is_finished=True,
                    metadata={"has_tool_calls": True},
                ),
            ],
            [
                ChatChunk(content="all done", is_finished=False),
                ChatChunk(content="", is_finished=True, metadata={}),
            ],
        ]
    )
    service = await _make_service(db_session, provider)
    conv_id = await _new_conversation(db_session, test_user_email)

    async def _fake_call_tool(server_id, tool_name, args):
        return {"ok": True, "content": "echo!"}

    with patch(
        "app.services.chat_service.MCPService.call_tool",
        new=AsyncMock(side_effect=_fake_call_tool),
    ):
        chunks = []
        async for c in service.send_message(
            conversation_id=conv_id,
            user_id=test_user_email,
            content="please",
        ):
            chunks.append(c)

    done_chunks = [c for c in chunks if c.is_finished]
    # Exactly one done per iteration (2 total here).
    assert len(done_chunks) == 2
    # The last one is the real end-of-turn — its metadata has no
    # has_tool_calls flag because no tool calls were emitted in iter 2.
    assert "has_tool_calls" not in (done_chunks[-1].metadata or {})


async def test_thinking_carries_across_iterations_to_final_assistant(db_session, test_user_email):
    """The model often emits reasoning during the tool-calling iteration
    (which produces no `content` and so was historically dropped) and then
    just an answer in the next iteration. We accumulate that prior thinking
    onto the next assistant message that does have content, so the persisted
    state has one assistant message per turn with cumulative reasoning —
    not an orphaned thinking block + a separate answer message."""
    tool_calls = [{"id": "c1", "name": "srv:t", "arguments": {}}]
    provider = _ScriptedProvider(
        [
            # Iteration 1: pure thinking + tool call, no content.
            [
                ChatChunk(
                    content="reasoning step one ",
                    is_finished=False,
                    is_thinking=True,
                ),
                ChatChunk(content="", is_finished=False, tool_calls=tool_calls),
                ChatChunk(content="", is_finished=True, metadata={}),
            ],
            # Iteration 2: more thinking + final content.
            [
                ChatChunk(
                    content="reasoning step two",
                    is_finished=False,
                    is_thinking=True,
                ),
                ChatChunk(content="the answer", is_finished=False),
                ChatChunk(content="", is_finished=True, metadata={}),
            ],
        ]
    )
    service = await _make_service(db_session, provider)
    conv_id = await _new_conversation(db_session, test_user_email)

    async def _fake_call_tool(server_id, tool_name, args):
        return {"ok": True, "content": "tool-output"}

    with patch(
        "app.services.chat_service.MCPService.call_tool",
        new=AsyncMock(side_effect=_fake_call_tool),
    ):
        async for _ in service.send_message(
            conversation_id=conv_id,
            user_id=test_user_email,
            content="ask",
        ):
            pass

    from sqlalchemy import select

    from app.models.message import Message

    result = await db_session.execute(
        select(Message).where(Message.conversation_id == conv_id).order_by(Message.created_at)
    )
    rows = list(result.scalars().all())
    assistants = [m for m in rows if m.role == "assistant"]
    # Exactly one assistant message — the iter-1 placeholder is folded in.
    assert len(assistants) == 1
    final = assistants[0]
    assert final.content == "the answer"
    thinking = (final.meta or {}).get("thinking", "")
    assert "reasoning step one" in thinking
    assert "reasoning step two" in thinking


async def test_tool_calls_sent_as_structured_field_not_content_json(db_session, test_user_email):
    """Regression: when replaying tool calls back to the LLM in the next
    iteration, send them via the API's native ``tool_calls`` field — never
    as raw JSON in ``content``. If the model sees its own tool-call JSON
    inlined in assistant content, it learns to mimic that format and emits
    raw JSON as a text response on subsequent turns. This pins the contract
    by inspecting what the provider received."""
    tool_calls = [{"id": "c1", "name": "srv:do_thing", "arguments": {"x": 1}}]
    provider = _ScriptedProvider(
        [
            [
                ChatChunk(content="", is_finished=False, tool_calls=tool_calls),
                ChatChunk(content="", is_finished=True, metadata={}),
            ],
            [
                ChatChunk(content="all done", is_finished=False),
                ChatChunk(content="", is_finished=True, metadata={}),
            ],
        ]
    )
    service = await _make_service(db_session, provider)
    conv_id = await _new_conversation(db_session, test_user_email)

    async def _fake_call_tool(server_id, tool_name, args):
        return {"ok": True, "content": "result"}

    with patch(
        "app.services.chat_service.MCPService.call_tool",
        new=AsyncMock(side_effect=_fake_call_tool),
    ):
        async for _ in service.send_message(
            conversation_id=conv_id,
            user_id=test_user_email,
            content="please",
        ):
            pass

    # Iteration 2's call to the provider must contain the assistant's
    # tool_calls as a structured field — NOT as JSON in content.
    iter2_messages = provider.calls[1]["messages"]
    assistant_with_calls = next(
        (m for m in iter2_messages if m.role == "assistant" and m.tool_calls),
        None,
    )
    assert assistant_with_calls is not None, "tool_calls must be on the message"
    assert assistant_with_calls.content == ""
    assert assistant_with_calls.tool_calls == tool_calls
    # Defensively verify no other assistant message smuggled the JSON in.
    for m in iter2_messages:
        if m.role == "assistant" and m.content:
            assert not m.content.lstrip().startswith("[{"), (
                "tool calls leaked into content as raw JSON"
            )


async def test_tool_execution_progress_chunks_emitted(db_session, test_user_email):
    """Each tool call must be bracketed by started/finished progress chunks
    so the UI can show live status (with a duration on finish)."""
    tool_calls = [{"id": "call-9", "name": "srv:echo", "arguments": {}}]
    provider = _ScriptedProvider(
        [
            [
                ChatChunk(content="", is_finished=False, tool_calls=tool_calls),
                ChatChunk(content="", is_finished=True, metadata={}),
            ],
            [
                ChatChunk(content="done", is_finished=False),
                ChatChunk(content="", is_finished=True, metadata={}),
            ],
        ]
    )
    service = await _make_service(db_session, provider)
    conv_id = await _new_conversation(db_session, test_user_email, enabled_tools=[])

    async def _fake_call_tool(server_id, tool_name, args):
        return {"ok": True, "content": "result"}

    chunks = []
    with patch(
        "app.services.chat_service.MCPService.call_tool",
        new=AsyncMock(side_effect=_fake_call_tool),
    ):
        async for c in service.send_message(conv_id, test_user_email, "hi"):
            chunks.append(c)

    executions = [
        c.metadata["tool_execution"]
        for c in chunks
        if c.metadata and "tool_execution" in c.metadata
    ]
    assert [e["status"] for e in executions] == ["started", "finished"]
    assert all(e["tool_call_id"] == "call-9" for e in executions)
    assert all(e["tool_name"] == "srv:echo" for e in executions)
    assert executions[1]["duration_ms"] >= 0

    # The started marker must arrive BEFORE the tool_result chunk.
    kinds = [
        ("execution", c.metadata["tool_execution"]["status"])
        if c.metadata and "tool_execution" in c.metadata
        else ("result", "")
        for c in chunks
        if c.metadata and ("tool_execution" in c.metadata or "tool_result" in c.metadata)
    ]
    assert kinds == [("execution", "started"), ("execution", "finished"), ("result", "")]


async def test_tool_result_truncated_to_cap(db_session, test_user_email, monkeypatch):
    """Oversized tool results are truncated with an explicit marker before
    persistence and before being fed back to the model."""
    from app.core.config import Settings

    monkeypatch.setattr(
        "app.services.agent_turn.get_settings",
        lambda: Settings(tool_result_max_chars=100),
    )

    tool_calls = [{"id": "call-big", "name": "srv:dump", "arguments": {}}]
    provider = _ScriptedProvider(
        [
            [
                ChatChunk(content="", is_finished=False, tool_calls=tool_calls),
                ChatChunk(content="", is_finished=True, metadata={}),
            ],
            [
                ChatChunk(content="ok", is_finished=False),
                ChatChunk(content="", is_finished=True, metadata={}),
            ],
        ]
    )
    service = await _make_service(db_session, provider)
    conv_id = await _new_conversation(db_session, test_user_email, enabled_tools=["srv:dump"])
    service._resolve_tools_for_conversation = AsyncMock(
        return_value=([], {"dump": ("srv", "dump")})
    )

    async def _fake_call_tool(server_id, tool_name, args):
        return {"ok": True, "content": "x" * 5000}

    with patch(
        "app.services.chat_service.MCPService.call_tool",
        new=AsyncMock(side_effect=_fake_call_tool),
    ):
        async for _c in service.send_message(conv_id, test_user_email, "hi"):
            pass

    from sqlalchemy import select

    from app.models.message import Message as MessageModel

    rows = (
        (await db_session.execute(select(MessageModel).where(MessageModel.role == "tool_result")))
        .scalars()
        .all()
    )
    assert len(rows) == 1
    content = rows[0].content
    assert "[truncated" in content
    assert len(content) < 200  # 100 chars + marker
    assert rows[0].meta.get("truncated") is True

    # The model also received the truncated text, not the full dump.
    tool_msgs = [m for m in provider.calls[1]["messages"] if m.role == "tool"]
    assert len(tool_msgs) == 1
    assert "[truncated" in tool_msgs[0].content


async def test_visual_result_survives_stream_and_history_without_text_truncation(
    db_session,
    test_user_email,
    monkeypatch,
):
    presentation = {
        "summary": "Monthly totals.",
        "surface_id": "totals",
        "components": [
            {
                "id": "root",
                "component": "Chart",
                "kind": "bar",
                "labels": ["January", "February"],
                "series": [{"label": "Sales", "values": [10, 20]}],
            }
        ],
    }
    provider = _ScriptedProvider(
        [
            [
                ChatChunk(
                    content="",
                    tool_calls=[{"id": "visual-1", "name": "render_ui", "arguments": presentation}],
                ),
                ChatChunk(content="", is_finished=True),
            ],
            [ChatChunk(content="February is higher."), ChatChunk(content="", is_finished=True)],
        ]
    )
    service = await _make_service(db_session, provider)
    conv_id = await _new_conversation(db_session, test_user_email, enabled_tools=[])
    monkeypatch.setattr(
        "app.services.agent_turn.get_settings", lambda: SimpleNamespace(tool_result_max_chars=10)
    )
    chunks = [
        chunk
        async for chunk in service.send_message(
            conversation_id=conv_id, user_id=test_user_email, content="Plot monthly totals"
        )
    ]
    live = [
        c.metadata["tool_result"] for c in chunks if c.metadata and "tool_result" in c.metadata
    ][0]
    assert live["result"]["presentation"]["components"] == presentation["components"]
    assert "truncated" not in live
    saved = await db_session.scalar(
        select(Message).where(Message.conversation_id == conv_id, Message.role == "tool_result")
    )
    assert saved.meta == live
    assert saved.content == "Monthly totals."
    assert any(t["function"]["name"] == "render_ui" for t in provider.calls[0]["tools"])
    assert any(
        m.role == "tool" and m.content == "Monthly totals." for m in provider.calls[1]["messages"]
    )


async def test_text_only_model_retains_plain_chat_without_presentation_tools(
    db_session,
    test_user_email,
    monkeypatch,
):
    provider = _ScriptedProvider(
        [[ChatChunk(content="Plain answer"), ChatChunk(content="", is_finished=True)]]
    )
    monkeypatch.setattr(provider, "get_model_supports_tools", AsyncMock(return_value=False))
    original = provider.stream_chat

    async def rejecting_stream(*args, tools=None, **kwargs):
        assert tools is None, "Text-only model rejects any tool argument"
        async for chunk in original(*args, tools=tools, **kwargs):
            yield chunk

    monkeypatch.setattr(provider, "stream_chat", rejecting_stream)
    service = await _make_service(db_session, provider)
    conv_id = await _new_conversation(db_session, test_user_email, enabled_tools=[])
    chunks = [
        c
        async for c in service.send_message(
            conversation_id=conv_id, user_id=test_user_email, content="Hello"
        )
    ]
    assert any(c.content == "Plain answer" for c in chunks)
    assert not any((c.metadata or {}).get("error") for c in chunks)


@pytest.mark.parametrize("failure_kind", [None, "chunk", "startup"])
async def test_visual_follow_up_is_saved_and_answered_without_client_resend(
    db_session,
    test_user_email,
    monkeypatch,
    failure_kind,
):
    provider = _ScriptedProvider(
        [[ChatChunk(content="A is the best fit."), ChatChunk(content="", is_finished=True)]]
    )
    chat = await _make_service(db_session, provider)
    if failure_kind == "chunk":
        provider.responses = [
            [
                ChatChunk(
                    content="Model unavailable",
                    is_finished=True,
                    metadata={"error": True, "auto_report": False},
                )
            ]
        ]
    if failure_kind == "startup":
        monkeypatch.setattr(
            provider,
            "get_model_supports_tools",
            AsyncMock(side_effect=RuntimeError("Model startup failed")),
        )
    monkeypatch.setattr(ChatService, "_spawn_title_generation", lambda *a: None)
    conv_id = await _new_conversation(db_session, test_user_email, enabled_tools=[])
    args = Presentation.model_validate(
        {
            "summary": "Choose an option",
            "surface_id": "choices",
            "components": [
                {
                    "id": "root",
                    "component": "Choices",
                    "action": "explain",
                    "options": [{"label": "A", "value": "A"}],
                }
            ],
            "actions": [{"id": "explain", "kind": "follow_up", "prompt": "Explain my choice"}],
        }
    )
    db_session.add(
        Message(
            id=str(uuid.uuid4()),
            conversation_id=conv_id,
            role="tool_result",
            content=args.summary,
            meta={
                "tool_call_id": "visual-followup",
                "tool_name": "render_ui",
                "result": args.result(),
            },
        )
    )
    await db_session.commit()
    streams = []

    def capture_stream(*args, **kwargs):
        stream = DetachedChatStream(*args, **kwargs)
        streams.append(stream)
        return stream

    monkeypatch.setattr("app.services.visual_ui.DetachedChatStream", capture_stream)
    ui = UIActionService(db_session)
    ui.chat = chat
    request = UISubmission(
        tool_call_id="visual-followup",
        surface_id="choices",
        action_id="explain",
        submission_id=str(uuid.uuid4()),
        values={"choice": "A"},
    )
    accepted = await ui.submit(conv_id, test_user_email, request)
    await streams[0].wait_finished()
    assert accepted["status"] == "completed"
    replay = await ui.submit(conv_id, test_user_email, request)
    assert replay == accepted
    assert len(streams) == 1
    messages = (
        await db_session.scalars(select(Message).where(Message.conversation_id == conv_id))
    ).all()
    assert len([m for m in messages if m.role == "user"]) == 1
    if failure_kind:
        errors = [m for m in messages if m.role == "assistant" and (m.meta or {}).get("error")]
        assert len(errors) == 1
        assert errors[0].content == (
            "Model unavailable" if failure_kind == "chunk" else "Model startup failed"
        )
    else:
        assert any(m.role == "assistant" and m.content == "A is the best fit." for m in messages)
