"""Room-only playable audio-note API tests."""

import io
import wave
from unittest.mock import AsyncMock, Mock

import pytest
from httpx import ASGITransport, AsyncClient
from sqlalchemy import select

from app.core.config import Settings, get_settings
from app.core.security import get_current_user, hash_password
from app.db.session import get_db
from app.main import app
from app.models.room import RoomAudioNote
from app.models.user import User
from app.schemas.audio import TranscriptionResponse
from app.services.room_service import RoomService

pytestmark = pytest.mark.asyncio

_SETTINGS = Settings(
    secret_key="test-secret-key-do-not-use-in-prod",
    database_url="sqlite+aiosqlite:///:memory:",
    access_token_expire_minutes=30,
)


def _wav(seconds: float = 0.1) -> bytes:
    output = io.BytesIO()
    with wave.open(output, "wb") as recording:
        recording.setnchannels(1)
        recording.setsampwidth(2)
        recording.setframerate(16_000)
        recording.writeframes(b"\x00\x00" * int(16_000 * seconds))
    return output.getvalue()


class _OnlineRoomManager:
    def __init__(self):
        self.events: list[dict] = []

    async def broadcast(self, room_id: str, event: dict) -> None:
        self.events.append(event)

    def is_user_online(self, room_id: str, user_id: str) -> bool:
        return True


def _install_overrides(db_session, email: str = "test@example.com") -> None:
    async def override_db():
        yield db_session

    async def override_user():
        return {"email": email, "token_payload": {}}

    app.dependency_overrides[get_db] = override_db
    app.dependency_overrides[get_current_user] = override_user
    app.dependency_overrides[get_settings] = lambda: _SETTINGS


def _clear_overrides() -> None:
    app.dependency_overrides.pop(get_db, None)
    app.dependency_overrides.pop(get_current_user, None)


async def test_audio_note_is_transcribed_persisted_broadcast_and_downloadable(
    db_session, monkeypatch
):
    room = await RoomService(db_session).create(owner_id="test@example.com", name="Voice room")
    manager = _OnlineRoomManager()
    monkeypatch.setattr("app.services.room_chat_service.room_manager", manager)
    transcribe = AsyncMock(
        return_value=TranscriptionResponse(text="  hello room  ", language="en", duration=0.1)
    )
    monkeypatch.setattr("app.services.stt_service.transcribe_audio_bytes", transcribe)
    schedule = Mock()
    monkeypatch.setattr("app.services.room_chat_service.schedule_room_agent_turns", schedule)
    _install_overrides(db_session)
    audio = _wav()

    try:
        async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as client:
            response = await client.post(
                f"/api/v1/rooms/{room.id}/audio-notes",
                files={"file": ("note.wav", audio, "audio/wav")},
            )
            assert response.status_code == 201, response.text
            message = response.json()["message"]
            note_meta = message["meta"]["audio_note"]

            playback = await client.get(f"/api/v1/rooms/{room.id}/audio-notes/{note_meta['id']}")
    finally:
        _clear_overrides()

    assert message["content"] == "hello room"
    assert note_meta["mime_type"] == "audio/wav"
    assert note_meta["duration_seconds"] == pytest.approx(0.1)
    assert playback.status_code == 200
    assert playback.content == audio
    assert playback.headers["content-type"] == "audio/wav"
    stored = (await db_session.execute(select(RoomAudioNote))).scalar_one()
    assert stored.audio_data == audio
    assert manager.events[0]["message"]["content"] == "hello room"
    transcribe.assert_awaited_once()
    schedule.assert_called_once_with(room.id, "hello room")


@pytest.mark.parametrize(
    ("audio", "status_code", "detail"),
    [
        (b"", 400, "Empty audio recording"),
        (b"not-wav", 422, "Invalid WAV recording"),
        (_wav(121), 422, "between 0 and 120 seconds"),
    ],
)
async def test_audio_note_validation(db_session, monkeypatch, audio, status_code, detail):
    room = await RoomService(db_session).create(owner_id="test@example.com", name="Voice room")
    monkeypatch.setattr("app.services.stt_service.transcribe_audio_bytes", AsyncMock())
    _install_overrides(db_session)
    try:
        async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as client:
            response = await client.post(
                f"/api/v1/rooms/{room.id}/audio-notes",
                files={"file": ("note.wav", audio, "audio/wav")},
            )
    finally:
        _clear_overrides()
    assert response.status_code == status_code
    assert detail in response.json()["detail"]


async def test_audio_note_with_no_speech_is_not_persisted(db_session, monkeypatch):
    room = await RoomService(db_session).create(owner_id="test@example.com", name="Voice room")
    monkeypatch.setattr(
        "app.services.stt_service.transcribe_audio_bytes",
        AsyncMock(return_value=TranscriptionResponse(text="", duration=0.1)),
    )
    _install_overrides(db_session)
    try:
        async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as client:
            response = await client.post(
                f"/api/v1/rooms/{room.id}/audio-notes",
                files={"file": ("note.wav", _wav(), "audio/wav")},
            )
    finally:
        _clear_overrides()
    assert response.status_code == 422
    assert (await db_session.execute(select(RoomAudioNote))).scalars().all() == []


async def test_audio_note_requires_room_membership(db_session):
    room = await RoomService(db_session).create(owner_id="test@example.com", name="Private")
    db_session.add(User(email="outsider@example.com", hashed_password=hash_password("x")))
    await db_session.commit()
    _install_overrides(db_session, "outsider@example.com")
    try:
        async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as client:
            response = await client.post(
                f"/api/v1/rooms/{room.id}/audio-notes",
                files={"file": ("note.wav", _wav(), "audio/wav")},
            )
    finally:
        _clear_overrides()
    assert response.status_code == 404
