"""Tests for STT and TTS audio endpoints."""

from unittest.mock import AsyncMock, MagicMock, patch

import pytest
from httpx import ASGITransport, AsyncClient

from app.core.config import Settings
from app.core.security import create_access_token
from app.main import app
from app.schemas.audio import TranscriptionResponse

pytestmark = pytest.mark.asyncio


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

_TEST_SETTINGS = Settings(
    secret_key="test-secret-key-do-not-use-in-prod",
    database_url="sqlite+aiosqlite:///:memory:",
    access_token_expire_minutes=30,
)


def _auth_header() -> dict[str, str]:
    """Return an Authorization header with a valid JWT."""
    token = create_access_token({"sub": "test@example.com"}, _TEST_SETTINGS)
    return {"Authorization": f"Bearer {token}"}


def _override_settings() -> Settings:
    return _TEST_SETTINGS


# Apply settings override for all tests in this module.
app.dependency_overrides[
    __import__("app.core.config", fromlist=["get_settings"]).get_settings
] = _override_settings


# ---------------------------------------------------------------------------
# STT endpoint tests -- POST /api/v1/stt/transcribe
# ---------------------------------------------------------------------------


class TestSTTTranscribe:
    """Tests for the speech-to-text transcription endpoint."""

    async def test_requires_authentication(self):
        transport = ASGITransport(app=app)
        async with AsyncClient(transport=transport, base_url="http://test") as client:
            response = await client.post(
                "/api/v1/stt/transcribe",
                files={"file": ("audio.wav", b"fake-audio-data")},
            )
        # HTTPBearer returns 403 when no credentials are provided
        assert response.status_code == 403

    async def test_empty_file_returns_400(self):
        transport = ASGITransport(app=app)
        async with AsyncClient(transport=transport, base_url="http://test") as client:
            response = await client.post(
                "/api/v1/stt/transcribe",
                files={"file": ("audio.wav", b"")},
                headers=_auth_header(),
            )
        assert response.status_code == 400
        assert "Empty audio file" in response.json()["detail"]

    @patch("app.services.stt_service.STTService.get_instance", new_callable=AsyncMock)
    async def test_successful_transcription(self, mock_get_instance):
        mock_service = AsyncMock()
        mock_service.transcribe.return_value = TranscriptionResponse(
            text="Hello world", language="en", duration=1.5
        )
        mock_get_instance.return_value = mock_service

        transport = ASGITransport(app=app)
        async with AsyncClient(transport=transport, base_url="http://test") as client:
            response = await client.post(
                "/api/v1/stt/transcribe",
                files={"file": ("audio.wav", b"fake-audio-data")},
                headers=_auth_header(),
            )
        assert response.status_code == 200
        data = response.json()
        assert data["text"] == "Hello world"
        assert data["language"] == "en"
        assert data["duration"] == 1.5
        mock_service.transcribe.assert_awaited_once()

    @patch("app.services.stt_service.STTService.get_instance", new_callable=AsyncMock)
    async def test_stt_service_unavailable_returns_502(self, mock_get_instance):
        mock_get_instance.side_effect = Exception("Connection refused")

        transport = ASGITransport(app=app)
        async with AsyncClient(transport=transport, base_url="http://test") as client:
            response = await client.post(
                "/api/v1/stt/transcribe",
                files={"file": ("audio.wav", b"fake-audio-data")},
                headers=_auth_header(),
            )
        assert response.status_code == 502
        assert "STT service unavailable" in response.json()["detail"]


# ---------------------------------------------------------------------------
# STT health endpoint -- GET /api/v1/stt/health
# ---------------------------------------------------------------------------


class TestSTTHealth:
    """Tests for the STT health check endpoint (no auth required)."""

    @patch("app.services.stt_service.STTService.get_instance", new_callable=AsyncMock)
    async def test_health_ok(self, mock_get_instance):
        mock_service = AsyncMock()
        mock_get_instance.return_value = mock_service

        transport = ASGITransport(app=app)
        async with AsyncClient(transport=transport, base_url="http://test") as client:
            response = await client.get("/api/v1/stt/health")
        assert response.status_code == 200
        assert response.json() == {"status": "ok"}

    @patch("app.services.stt_service.STTService.get_instance", new_callable=AsyncMock)
    async def test_health_unavailable(self, mock_get_instance):
        mock_get_instance.side_effect = Exception("Model not loaded")

        transport = ASGITransport(app=app)
        async with AsyncClient(transport=transport, base_url="http://test") as client:
            response = await client.get("/api/v1/stt/health")
        assert response.status_code == 200
        assert response.json() == {"status": "unavailable"}


# ---------------------------------------------------------------------------
# TTS endpoint tests -- POST /api/v1/tts/speak
# ---------------------------------------------------------------------------


class TestTTSSpeak:
    """Tests for the text-to-speech synthesis endpoint."""

    async def test_requires_authentication(self):
        transport = ASGITransport(app=app)
        async with AsyncClient(transport=transport, base_url="http://test") as client:
            response = await client.post(
                "/api/v1/tts/speak",
                json={"text": "Hello"},
            )
        # HTTPBearer returns 403 when no credentials are provided
        assert response.status_code == 403

    @patch("app.services.tts_service.TTSService.get_instance", new_callable=AsyncMock)
    async def test_successful_speech_synthesis(self, mock_get_instance):
        fake_audio = b"\xff\xfb\x90\x00" * 100  # fake mp3 bytes
        mock_service = AsyncMock()
        mock_service.speak.return_value = fake_audio
        mock_get_instance.return_value = mock_service

        transport = ASGITransport(app=app)
        async with AsyncClient(transport=transport, base_url="http://test") as client:
            response = await client.post(
                "/api/v1/tts/speak",
                json={"text": "Hello world"},
                headers=_auth_header(),
            )
        assert response.status_code == 200
        assert response.headers["content-type"] == "audio/mpeg"
        assert response.content == fake_audio
        mock_service.speak.assert_awaited_once_with(
            text="Hello world",
            voice="af_heart",
            speed=1.0,
            response_format="mp3",
        )

    @patch("app.services.tts_service.TTSService.get_instance", new_callable=AsyncMock)
    async def test_custom_voice_and_speed(self, mock_get_instance):
        fake_audio = b"audio-bytes"
        mock_service = AsyncMock()
        mock_service.speak.return_value = fake_audio
        mock_get_instance.return_value = mock_service

        transport = ASGITransport(app=app)
        async with AsyncClient(transport=transport, base_url="http://test") as client:
            response = await client.post(
                "/api/v1/tts/speak",
                json={
                    "text": "Custom voice test",
                    "voice": "am_adam",
                    "speed": 1.5,
                    "response_format": "wav",
                },
                headers=_auth_header(),
            )
        assert response.status_code == 200
        mock_service.speak.assert_awaited_once_with(
            text="Custom voice test",
            voice="am_adam",
            speed=1.5,
            response_format="wav",
        )

    @patch("app.services.tts_service.TTSService.get_instance", new_callable=AsyncMock)
    async def test_tts_service_unavailable_returns_500(self, mock_get_instance):
        mock_service = AsyncMock()
        mock_service.speak.side_effect = Exception("Connection refused")
        mock_get_instance.return_value = mock_service

        transport = ASGITransport(app=app)
        async with AsyncClient(transport=transport, base_url="http://test") as client:
            response = await client.post(
                "/api/v1/tts/speak",
                json={"text": "Hello"},
                headers=_auth_header(),
            )
        assert response.status_code == 500
        assert "TTS generation failed" in response.json()["detail"]

    async def test_empty_text_rejected(self):
        transport = ASGITransport(app=app)
        async with AsyncClient(transport=transport, base_url="http://test") as client:
            response = await client.post(
                "/api/v1/tts/speak",
                json={"text": ""},
                headers=_auth_header(),
            )
        assert response.status_code == 422  # Pydantic validation error


# ---------------------------------------------------------------------------
# TTS voices endpoint -- GET /api/v1/tts/voices
# ---------------------------------------------------------------------------


class TestTTSVoices:
    """Tests for the TTS voice listing endpoint."""

    async def test_requires_authentication(self):
        transport = ASGITransport(app=app)
        async with AsyncClient(transport=transport, base_url="http://test") as client:
            response = await client.get("/api/v1/tts/voices")
        # HTTPBearer returns 403 when no credentials are provided
        assert response.status_code == 403

    @patch("app.services.tts_service.TTSService.get_instance", new_callable=AsyncMock)
    async def test_returns_voice_list(self, mock_get_instance):
        from app.schemas.audio import VoiceInfo

        mock_service = MagicMock()
        mock_service.list_voices.return_value = [
            VoiceInfo(id="af_heart", name="Heart", language="English"),
            VoiceInfo(id="am_adam", name="Adam", language="English"),
        ]
        mock_get_instance.return_value = mock_service

        transport = ASGITransport(app=app)
        async with AsyncClient(transport=transport, base_url="http://test") as client:
            response = await client.get(
                "/api/v1/tts/voices",
                headers=_auth_header(),
            )
        assert response.status_code == 200
        data = response.json()
        assert "voices" in data
        assert len(data["voices"]) == 2
        assert data["voices"][0]["id"] == "af_heart"
        assert data["voices"][1]["id"] == "am_adam"


# ---------------------------------------------------------------------------
# TTS health endpoint -- GET /api/v1/tts/health
# ---------------------------------------------------------------------------


class TestTTSHealth:
    """Tests for the TTS health check endpoint (no auth required)."""

    @patch("app.services.tts_service.TTSService.get_instance", new_callable=AsyncMock)
    async def test_health_ok(self, mock_get_instance):
        mock_get_instance.return_value = AsyncMock()

        transport = ASGITransport(app=app)
        async with AsyncClient(transport=transport, base_url="http://test") as client:
            response = await client.get("/api/v1/tts/health")
        assert response.status_code == 200
        assert response.json() == {"status": "ok"}

    @patch("app.services.tts_service.TTSService.get_instance", new_callable=AsyncMock)
    async def test_health_unavailable(self, mock_get_instance):
        mock_get_instance.side_effect = Exception("Model not loaded")

        transport = ASGITransport(app=app)
        async with AsyncClient(transport=transport, base_url="http://test") as client:
            response = await client.get("/api/v1/tts/health")
        assert response.status_code == 200
        assert response.json() == {"status": "unavailable"}
