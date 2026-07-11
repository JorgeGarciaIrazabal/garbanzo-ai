"""In-process speech-to-text using faster-whisper, with remote fallback.

Heavy imports (faster_whisper) are deferred so the backend starts instantly.
The model loads in the background on startup via `STTService.start_loading()`.
"""

import asyncio
import io
import logging

import numpy as np

from app.core.config import get_settings
from app.schemas.audio import TranscriptionResponse

logger = logging.getLogger(__name__)


class STTService:
    """In-process STT using faster-whisper.

    Call `start_loading()` during app lifespan to begin background init.
    Call `get_instance()` from endpoints — it awaits until the model is ready.
    """

    _instance: "STTService | None" = None
    _ready = asyncio.Event()
    _error: Exception | None = None

    def __init__(self, model, language: str = "en"):
        self._model = model
        self._language = language

    # ------------------------------------------------------------------
    # Lifecycle
    # ------------------------------------------------------------------

    @classmethod
    def start_loading(cls) -> None:
        """Kick off model loading in a background thread (non-blocking)."""
        settings = get_settings()
        if settings.stt_mode == "remote":
            logger.info("STT mode is 'remote' — skipping local model load.")
            cls._ready.set()
            return
        asyncio.create_task(cls._load_in_background())

    @classmethod
    async def _load_in_background(cls) -> None:
        try:
            instance = await asyncio.to_thread(cls._load_sync)
            cls._instance = instance
            logger.info("Faster-Whisper STT ready.")
        except Exception as e:
            logger.error("Failed to load Faster-Whisper STT: %s", e)
            cls._error = e
        finally:
            cls._ready.set()

    @staticmethod
    def _load_sync() -> "STTService":
        """Synchronous heavy lifting — runs in a worker thread."""
        from faster_whisper import WhisperModel

        settings = get_settings()

        device = settings.stt_device
        if device == "auto":
            try:
                import torch

                device = "cuda" if torch.cuda.is_available() else "cpu"
            except ImportError:
                device = "cpu"

        compute_type = "float16" if device == "cuda" else "int8"

        logger.info(
            "Loading Faster-Whisper model %s on %s (%s) …",
            settings.stt_model,
            device,
            compute_type,
        )
        model = WhisperModel(
            settings.stt_model,
            device=device,
            compute_type=compute_type,
        )

        return STTService(model, language=settings.stt_language)

    @classmethod
    async def get_instance(cls) -> "STTService":
        """Return the singleton, waiting if the model is still loading."""
        await cls._ready.wait()
        if cls._error is not None:
            raise cls._error
        assert cls._instance is not None
        return cls._instance

    # ------------------------------------------------------------------
    # Transcription
    # ------------------------------------------------------------------

    async def transcribe(
        self, audio_bytes: bytes, filename: str, language: str | None = None
    ) -> TranscriptionResponse:
        """Transcribe audio bytes to text using the local model."""
        text = await asyncio.to_thread(
            self._transcribe_sync, audio_bytes, filename, language or self._language
        )
        return TranscriptionResponse(text=text)

    def _transcribe_sync(self, audio_bytes: bytes, filename: str, language: str) -> str:
        import soundfile as sf

        # Decode audio bytes to numpy array
        audio_data, sample_rate = sf.read(io.BytesIO(audio_bytes))

        # Convert stereo to mono if needed
        if audio_data.ndim > 1:
            audio_data = audio_data.mean(axis=1)

        # Ensure float32
        audio_data = audio_data.astype(np.float32)

        segments, _info = self._model.transcribe(
            audio_data,
            language=language,
            vad_filter=True,
            beam_size=5,
        )
        text = " ".join(seg.text.strip() for seg in segments).strip()

        # If VAD removed everything, retry without VAD — the filter can be
        # overly aggressive with certain microphone/sample-rate combinations.
        if not text:
            logger.info("VAD returned empty result, retrying without VAD filter")
            segments, _info = self._model.transcribe(
                audio_data,
                language=language,
                vad_filter=False,
                beam_size=5,
            )
            text = " ".join(seg.text.strip() for seg in segments).strip()

        return text

    # ------------------------------------------------------------------
    # Health
    # ------------------------------------------------------------------

    async def health_check(self) -> bool:
        return True


class RemoteSTTService:
    """Fallback: transcribes via the Docker-based Faster Whisper server."""

    def __init__(self, base_url: str):
        self.base_url = base_url

    async def transcribe(
        self, audio_bytes: bytes, filename: str, language: str = "en"
    ) -> TranscriptionResponse:
        import httpx

        async with httpx.AsyncClient(timeout=120.0) as client:
            response = await client.post(
                f"{self.base_url}/v1/audio/transcriptions",
                files={"file": (filename, audio_bytes)},
                data={"language": language, "vad_filter": "true"},
            )
            response.raise_for_status()
            data = response.json()
            return TranscriptionResponse(text=data["text"])

    async def health_check(self) -> bool:
        import httpx

        try:
            async with httpx.AsyncClient(timeout=5.0) as client:
                response = await client.get(self.base_url)
                return response.status_code == 200
        except httpx.HTTPError:
            return False
