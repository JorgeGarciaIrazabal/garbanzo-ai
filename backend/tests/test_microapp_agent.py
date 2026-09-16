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
    # A tool now also reports its live execution state (started/finished with
    # the label and duration) so the UI can show what is being worked on
    # instead of only learning about it after the fact.
    assert types == [
        "chunk",
        "chunk",
        "thinking",
        "tool_call",
        "tool_execution",
        "tool_execution",
        "tool_result",
        "done",
    ]
    assert chunks[0].content == "Hello"
    assert chunks[1].content == " world"  # incremental delta
    assert chunks[2].content == "let me think"
    assert chunks[3].tool_calls[0]["name"] == "edit"
    assert chunks[3].tool_calls[0]["id"] == "c1"
    started = chunks[4].metadata["tool_execution"]
    assert started["status"] == "started"
    # While running there is no title yet, so the label comes from the input —
    # this is what the collapsed progress line shows mid-call.
    assert started["title"] == "x.house.json"
    finished = chunks[5].metadata["tool_execution"]
    assert finished["status"] == "finished"
    assert chunks[6].tool_result["tool_call_id"] == "c1"
    assert chunks[6].tool_result["result"] == "done"
    assert chunks[6].tool_result["is_error"] is False
    assert chunks[7].metadata == {"session_id": SID}
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
    types = [c.type for c in chunks]
    assert types == ["tool_call", "tool_execution", "tool_result"]
    assert chunks[1].metadata["tool_execution"]["status"] == "failed"
    assert chunks[2].tool_result["result"] == "boom"
    assert chunks[2].tool_result["is_error"] is True


def test_server_heartbeat_becomes_a_heartbeat_chunk():
    """opencode's own liveness tick must reach the client.

    Regression guard: this frame used to be dropped (it was mistaken for an SSE
    comment line, which is a different wire format), leaving a long turn with no
    signal at all between tool calls.
    """
    chunks, _ = _drive([{"type": "server.heartbeat", "properties": {}}])
    assert [c.type for c in chunks] == ["heartbeat"]
    payload = chunks[0].metadata["heartbeat"]
    assert payload["phase"] == "working"
    assert payload["schema_version"] == 1


def test_step_boundaries_advance_the_heartbeat_counter():
    """Steps give the heartbeat a number that moves while the model thinks."""
    events = [
        {
            "type": "message.part.updated",
            "properties": {"part": {"id": "s1", "type": "step-start", "sessionID": SID}},
        },
        {
            "type": "message.part.updated",
            "properties": {"part": {"id": "s1", "type": "step-finish", "sessionID": SID}},
        },
    ]
    chunks, state = _drive(events)
    assert state.steps == 1
    beats = [c for c in chunks if c.type == "heartbeat"]
    assert len(beats) == 1
    assert beats[0].metadata["heartbeat"]["steps"] == 1


def test_out_of_order_tool_frames_do_not_duplicate_or_regress():
    """opencode emits completed before pending/running; that must not double-count.

    Verified against a live 1.18.30 server, where a ``completed`` frame arrived
    ahead of its own ``pending`` and ``running`` siblings.
    """
    base = {
        "id": "t1",
        "type": "tool",
        "tool": "write",
        "callID": "c1",
        "sessionID": SID,
    }
    events = [
        {
            "type": "message.part.updated",
            "properties": {
                "part": {
                    **base,
                    "state": {
                        "status": "completed",
                        "input": {"filePath": "a/b/notes.md"},
                        "output": "ok",
                        "title": "a/b/notes.md",
                        "time": {"start": 1000, "end": 1400},
                    },
                }
            },
        },
        {
            "type": "message.part.updated",
            "properties": {"part": {**base, "state": {"status": "pending", "input": {}}}},
        },
        {
            "type": "message.part.updated",
            "properties": {
                "part": {
                    **base,
                    "state": {"status": "running", "input": {"filePath": "a/b/notes.md"}},
                }
            },
        },
    ]
    chunks, state = _drive(events)
    assert state.tools_completed == 1
    # The late, lower-ranked frames must not produce a second terminal result.
    assert [c.type for c in chunks].count("tool_result") == 1
    assert [c.type for c in chunks].count("tool_call") == 1
    # Duration is derived from the start seen on the running/completed frame.
    result = next(c for c in chunks if c.type == "tool_result")
    assert result.tool_result["duration_ms"] == 400
    # opencode's own title is passed through verbatim (it is already a
    # display-ready relative path); only labels derived from ``input`` are
    # reduced to a basename, because those carry absolute host paths that
    # should not be shipped to the client.
    assert result.tool_result["title"] == "a/b/notes.md"


def test_running_bash_reports_its_command_as_the_label():
    """The collapsed line must name the command, not the word "bash"."""
    events = [
        {
            "type": "message.part.updated",
            "properties": {
                "part": {
                    "id": "t1",
                    "type": "tool",
                    "tool": "bash",
                    "callID": "c1",
                    "sessionID": SID,
                    "state": {
                        "status": "running",
                        "input": {"command": "pytest -q"},
                        "time": {"start": 5},
                    },
                }
            },
        }
    ]
    chunks, state = _drive(events)
    started = [c for c in chunks if c.type == "tool_execution"][0]
    assert started.metadata["tool_execution"]["title"] == "pytest -q"
    assert state.last_activity == "pytest -q"


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
