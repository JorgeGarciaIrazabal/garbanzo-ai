"""Service for speech-to-text transcription via Faster Whisper."""

import logging

import httpx

from app.schemas.audio import TranscriptionResponse

logger = logging.getLogger(__name__)


class STTService:
    """Transcribes audio using the Faster Whisper server."""

    def __init__(self, base_url: str):
        self.base_url = base_url

    async def transcribe(
        self, audio_bytes: bytes, filename: str
    ) -> TranscriptionResponse:
        """Transcribe audio bytes to text."""
        async with httpx.AsyncClient(timeout=120.0) as client:
            response = await client.post(
                f"{self.base_url}/v1/audio/transcriptions",
                files={"file": (filename, audio_bytes)},
            )
            response.raise_for_status()
            data = response.json()
            return TranscriptionResponse(text=data["text"])

    async def health_check(self) -> bool:
        """Check if the STT service is available."""
        try:
            async with httpx.AsyncClient(timeout=5.0) as client:
                response = await client.get(self.base_url)
                return response.status_code == 200
        except httpx.HTTPError:
            return False
