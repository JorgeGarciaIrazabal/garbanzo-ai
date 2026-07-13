"""Tests for room message file attachments (WS + REST + agent context).

Covers the attachment path added in commit f98430b: attachments posted with a
room message are persisted on the ``RoomMessage`` (document text inlined into
content, image base64 kept in meta), ride into agent context as images, and
are accepted through both the WebSocket command loop and the REST fallback.
"""

import base64
import uuid
from collections.abc import AsyncIterator
from unittest.mock import AsyncMock

import pytest
from fastapi import WebSocketDisconnect
from httpx import ASGITransport, AsyncClient
from sqlalchemy import select

from app.api.v1.endpoints.rooms_ws import room_websocket
from app.core.config import Settings, get_settings
from app.core.security import create_access_token, get_current_user
from app.db.session import get_db
from app.main import app
from app.models.room import RoomAgent, RoomMessage
from app.schemas.chat import AttachmentIn, ChatOptions, ModelInfo
from app.schemas.room import RoomPostCommand
from app.services.llm_provider import ChatChunk, ProviderRegistry
from app.services.llm_provider import Message as LLMMessage
from app.services.room_chat_service import RoomChatService
from app.services.room_service import RoomService

_TEST_SETTINGS = Settings(
    secret_key="test-secret-key-do-not-use-in-prod",
    database_url="sqlite+aiosqlite:///:memory:",
    access_token_expire_minutes=30,
)


class _RecordingProvider:
    """Streams a fixed reply and records every message list it receives."""

    def __init__(self):
        self.calls: list[list[LLMMessage]] = []

    @property
    def name(self) -> str:
        return "recording-room"

    async def stream_chat(
        self,
        messages: list[LLMMessage],
        model: str,
        options: ChatOptions | None = None,
        cancel_event=None,
        tools=None,
    ) -> AsyncIterator[ChatChunk]:
        self.calls.append(list(messages))
        yield ChatChunk(content="noted", is_finished=False)
        yield ChatChunk(content="", is_finished=True, metadata={})

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

    async def connect(self, room_id: str, user_id: str, websocket) -> None:
        pass

    async def disconnect(self, room_id: str, user_id: str, websocket) -> None:
        pass

    def is_user_online(self, room_id: str, user_id: str) -> bool:
        return True


def _image(data: str = "aW1hZ2VieXRlcw==") -> AttachmentIn:
    return AttachmentIn(name="photo.png", mime_type="image/png", type="image", data=data)


def _document(text: str = "hello from the doc") -> AttachmentIn:
    return AttachmentIn(
        name="notes.txt",
        mime_type="text/plain",
        type="document",
        data=base64.b64encode(text.encode()).decode(),
    )


async def _make_room(db, *, with_agent: bool = False, provider=None) -> str:
    room = await RoomService(db).create(owner_id="test@example.com", name="Attach room")
    if with_agent:
        ProviderRegistry.register(provider)
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
    return room.id


async def _user_message(db, room_id: str) -> RoomMessage:
    return (
        (
            await db.execute(
                select(RoomMessage).where(
                    RoomMessage.room_id == room_id, RoomMessage.role == "user"
                )
            )
        )
        .scalars()
        .one()
    )


# ---------------------------------------------------------------- service


@pytest.mark.asyncio
async def test_document_attachment_text_inlined_into_content(db_session, monkeypatch):
    room_id = await _make_room(db_session)
    fake = _FakeRoomManager()
    monkeypatch.setattr("app.services.room_chat_service.room_manager", fake)
    svc = RoomChatService(db_session)

    posted = await svc.handle_user_post(
        room_id, "test@example.com", "check this", attachments=[_document("hello from the doc")]
    )

    assert posted.content == "check this\n\n[Attached file: notes.txt]\nhello from the doc"
    # Document data is not duplicated into meta — only the descriptor.
    assert posted.meta["attachments"] == [
        {"name": "notes.txt", "mime_type": "text/plain", "type": "document"}
    ]
    # The broadcast message event carries the stored (inlined) content.
    message_event = next(e for _, e in fake.events if e["type"] == "message")
    assert message_event["message"]["content"] == posted.content


@pytest.mark.asyncio
async def test_image_attachment_kept_in_meta_content_untouched(db_session, monkeypatch):
    room_id = await _make_room(db_session)
    fake = _FakeRoomManager()
    monkeypatch.setattr("app.services.room_chat_service.room_manager", fake)
    svc = RoomChatService(db_session)

    posted = await svc.handle_user_post(
        room_id, "test@example.com", "look at this", attachments=[_image("b64data")]
    )

    assert posted.content == "look at this"
    assert posted.meta["attachments"] == [
        {"name": "photo.png", "mime_type": "image/png", "type": "image", "data": "b64data"}
    ]


@pytest.mark.asyncio
async def test_image_only_post_with_empty_content_is_persisted(db_session, monkeypatch):
    room_id = await _make_room(db_session)
    fake = _FakeRoomManager()
    monkeypatch.setattr("app.services.room_chat_service.room_manager", fake)
    svc = RoomChatService(db_session)

    posted = await svc.handle_user_post(room_id, "test@example.com", "", attachments=[_image()])

    assert posted.content == ""
    assert posted.meta["attachments"][0]["type"] == "image"


@pytest.mark.asyncio
async def test_image_attachment_reaches_agent_as_llm_images(db_session, monkeypatch):
    provider = _RecordingProvider()
    room_id = await _make_room(db_session, with_agent=True, provider=provider)
    fake = _FakeRoomManager()
    monkeypatch.setattr("app.services.room_chat_service.room_manager", fake)
    svc = RoomChatService(db_session)

    await svc.handle_user_post(
        room_id, "test@example.com", "what is in this image?", attachments=[_image("imgb64")]
    )

    assert provider.calls, "agent turn never ran"
    user_msgs = [m for m in provider.calls[0] if m.role == "user"]
    assert user_msgs[-1].images == ["imgb64"]
    assert user_msgs[-1].content == "[test@example.com]: what is in this image?"


# ---------------------------------------------------------------- wire schema


def test_post_command_parses_attachments():
    cmd = RoomPostCommand.model_validate(
        {
            "type": "post",
            "content": "",
            "attachments": [
                {"name": "a.png", "mime_type": "image/png", "type": "image", "data": "Zm9v"}
            ],
        }
    )
    assert cmd.attachments[0].name == "a.png"
    assert cmd.attachments[0].type == "image"


def test_post_command_attachments_default_empty():
    cmd = RoomPostCommand.model_validate({"type": "post", "content": "hi"})
    assert cmd.attachments == []


# ---------------------------------------------------------------- WebSocket


class _SessionCtx:
    """Async context manager handing out the shared test session without
    closing it (the WS handler opens/closes sessions per post)."""

    def __init__(self, session):
        self._session = session

    async def __aenter__(self):
        return self._session

    async def __aexit__(self, *args):
        return False


@pytest.mark.asyncio
async def test_ws_post_with_attachment_and_empty_content_is_accepted(db_session, monkeypatch):
    room_id = await _make_room(db_session)
    fake = _FakeRoomManager()
    monkeypatch.setattr("app.api.v1.endpoints.rooms_ws.room_manager", fake)
    monkeypatch.setattr("app.services.room_chat_service.room_manager", fake)
    monkeypatch.setattr(
        "app.api.v1.endpoints.rooms_ws.async_session_maker",
        lambda: _SessionCtx(db_session),
    )

    settings = Settings()
    token = create_access_token({"sub": "test@example.com"}, settings)
    ws = AsyncMock()
    frame = (
        '{"type": "post", "content": "", "attachments": '
        '[{"name": "p.png", "mime_type": "image/png", "type": "image", "data": "Zm9v"}]}'
    )
    ws.receive_text.side_effect = [frame, WebSocketDisconnect()]

    await room_websocket(ws, room_id, settings, token=token)

    ws.accept.assert_awaited_once()
    posted = await _user_message(db_session, room_id)
    assert posted.meta["attachments"][0]["data"] == "Zm9v"


@pytest.mark.asyncio
async def test_ws_post_with_no_content_and_no_attachments_is_ignored(db_session, monkeypatch):
    room_id = await _make_room(db_session)
    fake = _FakeRoomManager()
    monkeypatch.setattr("app.api.v1.endpoints.rooms_ws.room_manager", fake)
    monkeypatch.setattr("app.services.room_chat_service.room_manager", fake)
    monkeypatch.setattr(
        "app.api.v1.endpoints.rooms_ws.async_session_maker",
        lambda: _SessionCtx(db_session),
    )

    settings = Settings()
    token = create_access_token({"sub": "test@example.com"}, settings)
    ws = AsyncMock()
    ws.receive_text.side_effect = ['{"type": "post", "content": "  "}', WebSocketDisconnect()]

    await room_websocket(ws, room_id, settings, token=token)

    rows = (
        (await db_session.execute(select(RoomMessage).where(RoomMessage.room_id == room_id)))
        .scalars()
        .all()
    )
    assert rows == []


# ---------------------------------------------------------------- REST


@pytest.mark.asyncio
async def test_rest_post_with_attachment_persists_message(db_session, monkeypatch):
    room_id = await _make_room(db_session)
    fake = _FakeRoomManager()
    monkeypatch.setattr("app.services.room_chat_service.room_manager", fake)

    async def _override_db():
        yield db_session

    async def _override_user():
        return {"email": "test@example.com", "token_payload": {}}

    app.dependency_overrides[get_db] = _override_db
    app.dependency_overrides[get_settings] = lambda: _TEST_SETTINGS
    app.dependency_overrides[get_current_user] = _override_user
    try:
        async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as c:
            resp = await c.post(
                f"/api/v1/rooms/{room_id}/chat",
                json={
                    "content": "see attached",
                    "attachments": [
                        {
                            "name": "notes.txt",
                            "mime_type": "text/plain",
                            "type": "document",
                            "data": base64.b64encode(b"doc body").decode(),
                        }
                    ],
                },
            )
        assert resp.status_code == 200
        posted_id = resp.json()["posted_message_id"]

        posted = await _user_message(db_session, room_id)
        assert posted.id == posted_id
        assert "[Attached file: notes.txt]\ndoc body" in posted.content
        assert posted.meta["attachments"][0]["name"] == "notes.txt"
    finally:
        app.dependency_overrides.pop(get_db, None)
        app.dependency_overrides.pop(get_current_user, None)
        # get_settings intentionally stays overridden — sibling test modules
        # rely on a process-wide override installed at import time.
