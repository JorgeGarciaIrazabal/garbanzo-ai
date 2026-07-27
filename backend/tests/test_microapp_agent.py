"""Tests for the opencode → ChatResponseChunk event translator + agent guards."""

from __future__ import annotations

import pytest

from app.services.microapp_agent import (
    MicroappAgent,
    StreamState,
    _iter_sse_data,
    translate_event,
)

SID = "s1"


def _drive(events: list[dict]):
    """Run a list of opencode events through the translator; return all chunks."""
    state = StreamState(sid=SID)
    chunks = []
    for ev in events:
        chunks.extend(translate_event(ev, state))
    return chunks, state


def test_translate_full_sequence():
    events = [
        {
            "type": "message.updated",
            "properties": {"info": {"id": "m1", "role": "assistant", "sessionID": SID}},
        },
        {
            "type": "message.part.updated",
            "properties": {
                "part": {
                    "id": "p1",
                    "messageID": "m1",
                    "type": "text",
                    "text": "Hello",
                    "sessionID": SID,
                }
            },
        },
        {
            "type": "message.part.updated",
            "properties": {
                "part": {
                    "id": "p1",
                    "messageID": "m1",
                    "type": "text",
                    "text": "Hello world",
                    "sessionID": SID,
                }
            },
        },
        {
            "type": "message.part.updated",
            "properties": {
                "part": {
                    "id": "p2",
                    "messageID": "m1",
                    "type": "reasoning",
                    "text": "let me think",
                    "sessionID": SID,
                }
            },
        },
        {
            "type": "message.part.updated",
            "properties": {
                "part": {
                    "id": "t1",
                    "messageID": "m1",
                    "type": "tool",
                    "tool": "edit",
                    "callID": "c1",
                    "state": {"status": "running", "input": {"filePath": "houses/x.house.json"}},
                    "sessionID": SID,
                }
            },
        },
        {
            "type": "message.part.updated",
            "properties": {
                "part": {
                    "id": "t1",
                    "messageID": "m1",
                    "type": "tool",
                    "tool": "edit",
                    "callID": "c1",
                    "state": {"status": "completed", "output": "done"},
                    "sessionID": SID,
                }
            },
        },
        {"type": "session.idle", "properties": {"sessionID": SID}},
    ]
    chunks, state = _drive(events)
    types = [c.type for c in chunks]
    assert types == ["chunk", "chunk", "thinking", "tool_call", "tool_result", "done"]
    assert chunks[0].content == "Hello"
    assert chunks[1].content == " world"  # incremental delta
    assert chunks[2].content == "let me think"
    assert chunks[3].tool_calls[0]["name"] == "edit"
    assert chunks[3].tool_calls[0]["id"] == "c1"
    assert chunks[4].tool_result["tool_call_id"] == "c1"
    assert chunks[4].tool_result["result"] == "done"
    assert chunks[4].tool_result["is_error"] is False
    assert chunks[5].metadata == {"session_id": SID}
    assert state.done is True


def test_translate_session_error_is_terminal():
    events = [{"type": "session.error", "properties": {"sessionID": SID, "error": "kaboom"}}]
    chunks, state = _drive(events)
    assert len(chunks) == 1
    assert chunks[0].type == "error"
    assert "kaboom" in chunks[0].error
    assert state.done is True


def test_translate_ignores_other_sessions():
    events = [
        {
            "type": "message.updated",
            "properties": {"info": {"id": "m1", "role": "assistant", "sessionID": "other"}},
        },
        {
            "type": "message.part.updated",
            "properties": {
                "part": {
                    "id": "p1",
                    "messageID": "m1",
                    "type": "text",
                    "text": "nope",
                    "sessionID": "other",
                }
            },
        },
    ]
    chunks, _ = _drive(events)
    assert chunks == []


def test_translate_user_text_suppressed():
    events = [
        {
            "type": "message.updated",
            "properties": {"info": {"id": "m1", "role": "user", "sessionID": SID}},
        },
        {
            "type": "message.part.updated",
            "properties": {
                "part": {
                    "id": "p1",
                    "messageID": "m1",
                    "type": "text",
                    "text": "my prompt",
                    "sessionID": SID,
                }
            },
        },
    ]
    chunks, _ = _drive(events)
    assert chunks == []  # user's own echoed message is not re-streamed


def test_tool_error_result():
    events = [
        {
            "type": "message.part.updated",
            "properties": {
                "part": {
                    "id": "t1",
                    "type": "tool",
                    "tool": "bash",
                    "callID": "c9",
                    "state": {"status": "error", "error": "boom"},
                    "sessionID": SID,
                }
            },
        },
    ]
    chunks, _ = _drive(events)
    assert [c.type for c in chunks] == ["tool_call", "tool_result"]
    assert chunks[1].tool_result["result"] == "boom"
    assert chunks[1].tool_result["is_error"] is True


def test_sse_data_framing():
    buffer: list[str] = []
    assert _iter_sse_data(": comment", buffer) == []
    assert _iter_sse_data('data: {"a":1}', buffer) == []
    completed = _iter_sse_data("", buffer)
    assert completed == ['{"a":1}']
    assert buffer == []


@pytest.mark.asyncio
async def test_stream_instruction_not_ready():
    class Ws:
        opencode_base = None
        opencode_ready = False

    agent = MicroappAgent()
    chunks = [c async for c in agent.stream_instruction(Ws(), "hi")]
    assert [c.type for c in chunks] == ["error", "done"]


@pytest.mark.asyncio
async def test_abort_returns_false_without_base():
    class Ws:
        opencode_base = None

    agent = MicroappAgent()
    assert await agent.abort(Ws(), "s1") is False
