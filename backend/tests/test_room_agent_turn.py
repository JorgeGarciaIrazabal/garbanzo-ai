"""Tests for the room agent streaming turn (engine-backed).

Covers the WS-adapter side of ``run_agent_turn``: wire event sequence,
RoomMessage persistence, the persist-partial-on-error contract, and the
whitespace-only-reply skip.
"""

import uuid
from collections.abc import AsyncIterator

import pytest
from sqlalchemy import select

from app.models.room import RoomAgent, RoomMessage
from app.schemas.chat import ChatOptions, ModelInfo
from app.services.llm_provider import ChatChunk, ProviderRegistry
from app.services.llm_provider import Message as LLMMessage
from app.services.room_chat_service import RoomChatService
from app.services.room_service import RoomService

pytestmark = pytest.mark.asyncio


class _ScriptedRoomProvider:
    """Yields a fixed chunk script; optionally raises mid-stream."""

    def __init__(self, chunks: list[ChatChunk], *, raise_after: int | None = None):
        self.chunks = chunks
        self.raise_after = raise_after

    @property
    def name(self) -> str:
        return "scripted-room"

    async def stream_chat(
        self,
        messages: list[LLMMessage],
        model: str,
        options: ChatOptions | None = None,
        cancel_event=None,
        tools=None,
    ) -> AsyncIterator[ChatChunk]:
        for i, chunk in enumerate(self.chunks):
            if self.raise_after is not None and i >= self.raise_after:
                raise RuntimeError("provider blew up")
            yield chunk

    async def chat(self, messages, model, options=None, tools=None) -> str:  # pragma: no cover
        return ""

    async def list_models(self) -> list[ModelInfo]:  # pragma: no cover
        return []

    async def health_check(self) -> bool:  # pragma: no cover
        return True


class _FakeRoomManager:
    def __init__(self):
        self.events: list[tuple[str, dict]] = []

    async def broadcast(self, room_id: str, event: dict) -> None:
        self.events.append((room_id, event))

    def is_user_online(self, room_id: str, user_id: str) -> bool:
        return True


async def _make_room_with_agent(db, provider) -> tuple[str, RoomChatService]:
    ProviderRegistry.register(provider)
    room = await RoomService(db).create(owner_id="test@example.com", name="Turn room")
    db.add(
        RoomAgent(
            id=str(uuid.uuid4()),
            room_id=room.id,
            name="Echo",
            provider=provider.name,
            model="fake-model",
            response_mode="always",
        )
    )
    await db.commit()
    return room.id, RoomChatService(db)


def _event_types(fake: _FakeRoomManager) -> list[str]:
    return [e["type"] for _, e in fake.events]


async def test_agent_turn_streams_and_persists(db_session, monkeypatch):
    provider = _ScriptedRoomProvider(
        [
            ChatChunk(content="hmm", is_thinking=True),
            ChatChunk(content="Hello "),
            ChatChunk(content="world"),
            ChatChunk(content="", is_finished=True, metadata={"eval_count": 5}),
        ]
    )
    room_id, svc = await _make_room_with_agent(db_session, provider)
    fake = _FakeRoomManager()
    monkeypatch.setattr("app.services.room_chat_service.room_manager", fake)

    await svc.handle_user_post(room_id, "test@example.com", "hello there")

    # user message, bubble open, thinking, 2 content chunks, canonical
    # message, done — in that order.
    assert _event_types(fake) == [
        "message",
        "stream_start",
        "thinking",
        "chunk",
        "chunk",
        "message",
        "done",
    ]

    persisted = (
        (
            await db_session.execute(
                select(RoomMessage).where(
                    RoomMessage.room_id == room_id,
                    RoomMessage.role == "assistant",
                )
            )
        )
        .scalars()
        .one()
    )
    assert persisted.content == "Hello world"
    assert persisted.meta["thinking"] == "hmm"
    assert persisted.meta["agent_name"] == "Echo"
    assert persisted.meta["eval_count"] == 5
    # The engine stamps the allocated window on the finish metadata.
    assert "context_length" in persisted.meta

    # The streaming message_id matches the persisted row so clients can
    # replace their placeholder bubble.
    stream_start = next(e for _, e in fake.events if e["type"] == "stream_start")
    assert stream_start["message_id"] == persisted.id


async def test_agent_turn_persists_partial_on_provider_error(db_session, monkeypatch):
    provider = _ScriptedRoomProvider(
        [
            ChatChunk(content="Hel"),
            ChatChunk(content="lo"),
        ],
        raise_after=1,
    )
    room_id, svc = await _make_room_with_agent(db_session, provider)
    fake = _FakeRoomManager()
    monkeypatch.setattr("app.services.room_chat_service.room_manager", fake)

    await svc.handle_user_post(room_id, "test@example.com", "hi")

    persisted = (
        (
            await db_session.execute(
                select(RoomMessage).where(
                    RoomMessage.room_id == room_id,
                    RoomMessage.role == "assistant",
                )
            )
        )
        .scalars()
        .one()
    )
    # Other participants saw "Hel" stream in — it must survive as a message.
    assert persisted.content == "Hel"
    assert persisted.meta["error"] is True
    assert persisted.meta["error_type"] == "streaming_error"

    types = _event_types(fake)
    # No content/error event after the crash — just the canonical message.
    assert types == ["message", "stream_start", "chunk", "message", "done"]
    final_message = [e for _, e in fake.events if e["type"] == "message"][-1]
    assert final_message["message"]["content"] == "Hel"


async def test_agent_turn_skips_empty_reply(db_session, monkeypatch):
    provider = _ScriptedRoomProvider([ChatChunk(content="", is_finished=True, metadata={})])
    room_id, svc = await _make_room_with_agent(db_session, provider)
    fake = _FakeRoomManager()
    monkeypatch.setattr("app.services.room_chat_service.room_manager", fake)

    await svc.handle_user_post(room_id, "test@example.com", "hi")

    assistants = (
        (
            await db_session.execute(
                select(RoomMessage).where(
                    RoomMessage.room_id == room_id,
                    RoomMessage.role == "assistant",
                )
            )
        )
        .scalars()
        .all()
    )
    assert assistants == []
    # Bubble opened but never resolved to a message — no done event.
    assert _event_types(fake) == ["message", "stream_start"]
