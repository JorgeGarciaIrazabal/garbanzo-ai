"""Released OpenCode V2 stream contracts and failure regression coverage."""

from __future__ import annotations

import json
from types import SimpleNamespace

import httpx
import pytest

from app.core.config import Settings
from app.services import microapp_agent
from app.services.microapp_agent import MicroappAgent, StreamState, _iter_sse_data, translate_event

SID = "ses_test"


def event(kind, **data):
    return {"type": kind, "created": 1000, "data": {"sessionID": SID, **data}}


def test_text_and_reasoning_deltas_reconcile_terminal_values():
    state = StreamState(SID)
    chunks = []
    for kind in ("text", "reasoning"):
        data = {"assistantMessageID": "msg_a", "ordinal": 0}
        for frame in [
            event(f"session.{kind}.delta", **data, delta="Hello"),
            event(f"session.{kind}.ended", **data, text="Hello world"),
            event(f"session.{kind}.delta", **data, delta="late"),
        ]:
            chunks.extend(translate_event(frame, state))
    assert [(c.type, c.content) for c in chunks] == [
        ("chunk", "Hello"),
        ("chunk", " world"),
        ("thinking", "Hello"),
        ("thinking", " world"),
    ]


def test_completion_is_gated_on_our_inbox_delivery():
    state = StreamState(SID, prompt_id="msg_ours")
    assert translate_event(event("session.execution.succeeded"), state) == []
    assert translate_event(event("session.idle"), state) == []
    translate_event(event("session.inbox.delivered", inboxID="msg_other"), state)
    assert not state.prompt_delivered
    translate_event(event("session.inbox.delivered", inboxID="msg_ours"), state)
    chunks = translate_event(event("session.execution.succeeded"), state)
    assert [c.type for c in chunks] == ["done"]
    assert translate_event(event("session.execution.succeeded"), state) == []


def test_tool_progress_terminal_dedup_and_stale_frames():
    state = StreamState(SID)
    frames = [
        event("session.tool.input.started", id="call_1", name="shell"),
        event("session.tool.called", id="call_1", input={"command": "git status"}),
        {
            **event(
                "session.tool.success",
                id="call_1",
                content=[{"type": "text", "text": "clean"}],
                metadata={"title": "Git status"},
            ),
            "created": 1400,
        },
        event("session.tool.called", id="call_1", input={"command": "stale"}),
        event("session.tool.success", id="call_1", content=[{"type": "text", "text": "clean"}]),
    ]
    chunks = [chunk for frame in frames for chunk in translate_event(frame, state)]
    assert [c.type for c in chunks] == [
        "tool_call",
        "tool_execution",
        "tool_execution",
        "tool_result",
    ]
    assert chunks[1].metadata["tool_execution"]["title"] == "git status"
    assert chunks[-1].tool_result["result"] == "clean"
    assert chunks[-1].tool_result["duration_ms"] == 400
    assert state.last_activity == "Git status"
    assert state.tools_completed == 1


def test_duplicate_step_event_does_not_double_count():
    state = StreamState(SID)
    frame = {**event("session.step.started"), "id": "evt_step"}
    assert len(translate_event(frame, state)) == 1
    assert translate_event(frame, state) == []
    assert state.steps == 1


@pytest.mark.parametrize("raw", ['{"command":', "not-json"])
def test_malformed_tool_input_relays_failure_and_allows_model_recovery(raw):
    state = StreamState(SID)
    frames = [
        event("session.tool.input.started", id="bad", name="shell"),
        event("session.tool.input.ended", id="bad", text=raw),
        event("session.tool.failed", id="bad", error={"message": "Invalid tool arguments"}),
        event("session.tool.input.started", id="retry", name="shell"),
        event("session.tool.called", id="retry", input={"command": "git status"}),
        event("session.tool.success", id="retry", content=[{"type": "text", "text": "clean"}]),
        event("session.text.delta", assistantMessageID="answer", ordinal=0, delta="Recovered."),
        event("session.execution.succeeded"),
    ]
    chunks = [chunk for frame in frames for chunk in translate_event(frame, state)]
    results = [chunk.tool_result for chunk in chunks if chunk.type == "tool_result"]
    assert [result["is_error"] for result in results] == [True, False]
    assert results[0]["result"] == "Invalid tool arguments"
    assert any(chunk.content == "Recovered." for chunk in chunks)
    assert chunks[-1].type == "done"
    assert not any(chunk.type == "error" for chunk in chunks)


@pytest.mark.parametrize(
    "kind,data",
    [
        ("session.execution.failed", {"error": {"type": "provider", "message": "kaboom"}}),
        ("session.execution.interrupted", {"reason": "inactivity"}),
        ("permission.asked", {}),
        ("form.created", {"form": {"sessionID": SID}}),
    ],
)
def test_terminal_errors_surface(kind, data):
    state = StreamState(SID)
    chunks = translate_event(event(kind, **data), state)
    assert [c.type for c in chunks] == ["error"]
    assert state.done


def test_other_session_and_user_prompt_are_not_output():
    state = StreamState(SID)
    assert (
        translate_event({"type": "session.text.delta", "data": {"sessionID": "other"}}, state) == []
    )
    assert translate_event(event("session.inbox.enqueued", text="prompt"), state) == []


def test_sse_data_framing():
    buffer = []
    assert _iter_sse_data(": heartbeat", buffer) == []
    assert _iter_sse_data('data: {"a":1}', buffer) == []
    assert _iter_sse_data("", buffer) == ['{"a":1}']


def mock_client(monkeypatch, frames, *, prompt_status=200):
    calls = []

    async def handle(request):
        calls.append(
            (
                request.method,
                request.url.path,
                json.loads(request.content) if request.content else None,
            )
        )
        if request.url.path == "/api/session":
            return httpx.Response(200, json={"data": {"id": SID}})
        if request.url.path == "/api/event":
            greeting = {"type": "server.connected", "data": {}}
            content = "".join(f"data: {json.dumps(f)}\n\n" for f in [greeting, *frames])
            return httpx.Response(
                200, content=content, headers={"content-type": "text/event-stream"}
            )
        if request.url.path.endswith("/prompt"):
            return httpx.Response(prompt_status, json={"data": {"id": "msg_ours"}})
        return httpx.Response(200, json={"interrupted": True})

    factory = httpx.AsyncClient
    monkeypatch.setattr(
        microapp_agent.httpx,
        "AsyncClient",
        lambda **kw: factory(**kw, transport=httpx.MockTransport(handle)),
    )
    return calls


@pytest.mark.asyncio
async def test_stream_uses_v2_endpoints_and_model_reference(monkeypatch):
    calls = mock_client(
        monkeypatch,
        [
            event("session.inbox.delivered", inboxID="msg_ours"),
            event("session.text.delta", assistantMessageID="msg_a", ordinal=0, delta="result"),
            event("session.execution.succeeded"),
        ],
    )
    agent = MicroappAgent(Settings(microapps_opencode_model="ollama/fake#high"))
    chunks = [
        c
        async for c in agent.stream_instruction(
            SimpleNamespace(opencode_base="http://agent", opencode_ready=True), "hello"
        )
    ]
    assert [c.type for c in chunks] == ["session", "chunk", "done"]
    assert calls == [
        (
            "POST",
            "/api/session",
            {"title": "hello", "model": {"providerID": "ollama", "id": "fake", "variant": "high"}},
        ),
        ("GET", "/api/event", None),
        ("POST", f"/api/session/{SID}/prompt", {"text": "hello"}),
    ]


@pytest.mark.asyncio
@pytest.mark.parametrize("prompt_status", [200, 400])
async def test_disconnect_and_failed_prompt_are_errors(monkeypatch, prompt_status):
    calls = mock_client(monkeypatch, [], prompt_status=prompt_status)
    chunks = [
        c
        async for c in MicroappAgent().stream_instruction(
            SimpleNamespace(opencode_base="http://agent", opencode_ready=True), "hello"
        )
    ]
    assert [c.type for c in chunks] == ["session", "error", "done"]
    assert calls[-1][1].endswith("/interrupt")


@pytest.mark.asyncio
async def test_not_ready():
    chunks = [
        c
        async for c in MicroappAgent().stream_instruction(
            SimpleNamespace(opencode_base=None), "hello"
        )
    ]
    assert [c.type for c in chunks] == ["error", "done"]
    assert not await MicroappAgent().abort(SimpleNamespace(opencode_base=None), SID)


def test_code_mode_progress_and_nested_failure_surface():
    state = StreamState(SID)
    translate_event(event("session.tool.input.started", id="call_code", name="execute"), state)
    translate_event(
        event("session.tool.called", id="call_code", input={"code": "await tools.shell(...)"}),
        state,
    )
    progress = translate_event(
        event(
            "session.tool.progress",
            id="call_code",
            metadata={
                "toolCalls": [
                    {"tool": "shell", "status": "running", "input": {"command": "git status"}},
                ]
            },
        ),
        state,
    )
    assert progress[-1].metadata["tool_execution"]["title"] == "git status"
    failed = translate_event(
        event(
            "session.tool.success",
            id="call_code",
            metadata={"error": True},
            content=[{"type": "text", "text": "nested tool failed"}],
        ),
        state,
    )
    assert failed[-1].tool_result["is_error"]
    assert failed[-1].tool_result["result"] == "nested tool failed"
