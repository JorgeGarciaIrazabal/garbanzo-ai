"""Tests for STT language resolution (idea 13).

`STTService.transcribe` / `RemoteSTTService.transcribe` must translate the
"auto" sentinel (and an unset language) into a real auto-detect request —
`language=None` for faster-whisper, an omitted form field for the remote
OpenAI-compatible server — instead of forcing a single language on every
request the way the pre-fix code always did.
"""

import pytest
import soundfile as sf
from numpy import zeros

from app.services.stt_service import RemoteSTTService, STTService

pytestmark = pytest.mark.asyncio


class _CapturingSTTService(STTService):
    """Bypasses real audio decoding to isolate the language-resolution logic."""

    def __init__(self, language: str):
        super().__init__(model=object(), language=language, beam_size=1)
        self.captured_language: str | None = "unset"

    def _transcribe_sync(self, audio_bytes: bytes, filename: str, language: str | None) -> dict:
        self.captured_language = language
        return {"text": "hi", "language": "en", "duration": 1.0}


class TestSTTServiceLanguageResolution:
    async def test_default_server_language_auto_resolves_to_none(self):
        service = _CapturingSTTService(language="auto")
        await service.transcribe(b"fake", "a.wav")
        assert service.captured_language is None

    async def test_explicit_auto_resolves_to_none(self):
        service = _CapturingSTTService(language="en")  # server forces "en" by default
        await service.transcribe(b"fake", "a.wav", language="auto")
        assert service.captured_language is None

    async def test_explicit_iso_code_overrides_the_server_default(self):
        service = _CapturingSTTService(language="auto")
        await service.transcribe(b"fake", "a.wav", language="es")
        assert service.captured_language == "es"

    async def test_forced_server_default_applies_when_request_omits_language(self):
        service = _CapturingSTTService(language="fr")
        await service.transcribe(b"fake", "a.wav")
        assert service.captured_language == "fr"


class TestSTTServiceInferenceOptions:
    async def test_local_inference_explicitly_transcribes_instead_of_translating(self):
        captured = {}

        class _Segment:
            text = "hola"

        class _Info:
            language = "es"
            duration = 1.0

        class _FakeModel:
            def transcribe(self, audio, **options):
                captured.update(options)
                return iter([_Segment()]), _Info()

        audio = _wav_bytes()
        service = STTService(model=_FakeModel(), language="auto", beam_size=1)

        result = service._transcribe_sync(audio, "a.wav", language=None)

        assert result["text"] == "hola"
        assert captured["task"] == "transcribe"
        assert captured["language"] is None


class TestRemoteSTTServiceLanguageOmission:
    async def test_auto_omits_the_language_field_entirely(self, monkeypatch):
        captured = {}

        class _FakeResponse:
            def raise_for_status(self):
                pass

            def json(self):
                return {"text": "hi", "language": "en", "duration": 1.0}

        class _FakeClient:
            async def post(self, url, files, data):
                captured["data"] = data
                return _FakeResponse()

        service = RemoteSTTService(base_url="http://whisper.local")
        monkeypatch.setattr(service, "_get_client", lambda: _fake_client_future(_FakeClient()))

        await service.transcribe(b"fake", "a.wav", language="auto")

        assert "language" not in captured["data"]

    async def test_explicit_code_is_forwarded(self, monkeypatch):
        captured = {}

        class _FakeResponse:
            def raise_for_status(self):
                pass

            def json(self):
                return {"text": "hola", "language": "es", "duration": 1.0}

        class _FakeClient:
            async def post(self, url, files, data):
                captured["data"] = data
                return _FakeResponse()

        service = RemoteSTTService(base_url="http://whisper.local")
        monkeypatch.setattr(service, "_get_client", lambda: _fake_client_future(_FakeClient()))

        await service.transcribe(b"fake", "a.wav", language="es")

        assert captured["data"]["language"] == "es"


async def _fake_client_future(client):
    return client


def _wav_bytes() -> bytes:
    """One second of silent 16 kHz audio for inference-option tests."""
    from io import BytesIO

    buffer = BytesIO()
    sf.write(buffer, zeros(16_000, dtype="float32"), 16_000, format="WAV")
    return buffer.getvalue()
