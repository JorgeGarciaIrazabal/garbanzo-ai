"""Shape-pinning tests for the room WebSocket wire contract.

These tests pin the exact serialized shape (field names, order, types and
optionality) of every event the server emits and every command the client
sends. They are a tripwire: if a future refactor changes the wire format, one
of these assertions fails loudly instead of silently breaking the Flutter
client, which parses these payloads by field name.

The events historically were hand-rolled ``dict`` literals in ``rooms_ws.py``,
``room_chat_service.py`` and ``room_connection_manager.py``. They are now
Pydantic models in ``app.schemas.room``; the dicts pinned here are the
pre-refactor bytes.
"""

from datetime import UTC, datetime
from types import SimpleNamespace

from app.schemas.room import (
    RoomChunkEvent,
    RoomDoneEvent,
    RoomErrorEvent,
    RoomMessageEvent,
    RoomPostCommand,
    RoomPresenceEvent,
    RoomStreamStartEvent,
    RoomThinkingEvent,
    RoomTypingCommand,
    RoomTypingEvent,
    RoomWSMessage,
)


def _keys(dump: dict) -> list[str]:
    return list(dump.keys())


# --------------------------------------------------------------- server events


def test_message_event_shape():
    msg = RoomWSMessage(
        id="m1",
        room_id="r1",
        role="assistant",
        sender_user_id=None,
        sender_agent_id="a1",
        content="hello",
        meta={"tokens": 5},
        created_at="2026-07-11T00:00:00+00:00",
    )
    dump = RoomMessageEvent(message=msg).model_dump()
    assert dump == {
        "type": "message",
        "message": {
            "id": "m1",
            "room_id": "r1",
            "role": "assistant",
            "sender_user_id": None,
            "sender_agent_id": "a1",
            "content": "hello",
            "meta": {"tokens": 5},
            "created_at": "2026-07-11T00:00:00+00:00",
        },
    }
    # Field order is part of the byte contract.
    assert _keys(dump) == ["type", "message"]
    assert _keys(dump["message"]) == [
        "id",
        "room_id",
        "role",
        "sender_user_id",
        "sender_agent_id",
        "content",
        "meta",
        "created_at",
    ]


def test_ws_message_from_model_matches_legacy_wire():
    """``RoomWSMessage.from_model`` reproduces the historic ``_message_to_wire``
    dict exactly, including ISO-8601 ``created_at`` and ``None`` fields."""
    created = datetime(2026, 7, 11, 12, 30, tzinfo=UTC)
    fake = SimpleNamespace(
        id="m9",
        room_id="r9",
        role="user",
        sender_user_id="user@example.com",
        sender_agent_id=None,
        content="hi there",
        meta=None,
        created_at=created,
    )
    dump = RoomWSMessage.from_model(fake).model_dump()
    assert dump == {
        "id": "m9",
        "room_id": "r9",
        "role": "user",
        "sender_user_id": "user@example.com",
        "sender_agent_id": None,
        "content": "hi there",
        "meta": None,
        "created_at": "2026-07-11T12:30:00+00:00",
    }


def test_ws_message_from_model_handles_null_created_at():
    fake = SimpleNamespace(
        id="m0",
        room_id="r0",
        role="assistant",
        sender_user_id=None,
        sender_agent_id="a0",
        content="x",
        meta=None,
        created_at=None,
    )
    assert RoomWSMessage.from_model(fake).model_dump()["created_at"] is None


def test_stream_start_event_shape():
    dump = RoomStreamStartEvent(message_id="m1", agent_id="a1", agent_name="Ada").model_dump()
    assert dump == {
        "type": "stream_start",
        "message_id": "m1",
        "agent_id": "a1",
        "agent_name": "Ada",
    }
    assert _keys(dump) == ["type", "message_id", "agent_id", "agent_name"]


def test_chunk_event_shape():
    dump = RoomChunkEvent(message_id="m1", agent_id="a1", content="tok").model_dump()
    assert dump == {
        "type": "chunk",
        "message_id": "m1",
        "agent_id": "a1",
        "content": "tok",
    }
    assert _keys(dump) == ["type", "message_id", "agent_id", "content"]


def test_thinking_event_shape_uses_canonical_type():
    dump = RoomThinkingEvent(message_id="m1", agent_id="a1", content="hmm").model_dump()
    # Must be the canonical "thinking", never the legacy "thinking_chunk".
    assert dump == {
        "type": "thinking",
        "message_id": "m1",
        "agent_id": "a1",
        "content": "hmm",
    }
    assert dump["type"] == "thinking"
    assert _keys(dump) == ["type", "message_id", "agent_id", "content"]


def test_done_event_shape():
    dump = RoomDoneEvent(message_id="m1", agent_id="a1").model_dump()
    assert dump == {"type": "done", "message_id": "m1", "agent_id": "a1"}
    assert _keys(dump) == ["type", "message_id", "agent_id"]


def test_presence_event_shape():
    dump = RoomPresenceEvent(online=["a@x.com", "b@x.com"]).model_dump()
    assert dump == {"type": "presence", "online": ["a@x.com", "b@x.com"]}
    assert _keys(dump) == ["type", "online"]


def test_typing_event_shape():
    dump = RoomTypingEvent(user_id="a@x.com", typing=True).model_dump()
    assert dump == {"type": "typing", "user_id": "a@x.com", "typing": True}
    assert _keys(dump) == ["type", "user_id", "typing"]


def test_error_event_shape():
    dump = RoomErrorEvent(error="Invalid JSON").model_dump()
    assert dump == {"type": "error", "error": "Invalid JSON"}
    assert _keys(dump) == ["type", "error"]


# ------------------------------------------------------------- client commands


def test_post_command_parses_client_payload():
    cmd = RoomPostCommand.model_validate({"type": "post", "content": "hello"})
    assert cmd.content == "hello"
    assert cmd.type == "post"


def test_typing_command_parses_and_defaults():
    assert RoomTypingCommand.model_validate({"type": "typing", "typing": True}).typing
    # ``typing`` defaults to False when omitted, matching the old
    # ``bool(event.get("typing", False))`` behaviour.
    assert RoomTypingCommand.model_validate({"type": "typing"}).typing is False
