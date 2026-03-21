"""Service for text-to-speech synthesis via Kokoro TTS."""

import logging

import httpx

from app.schemas.audio import VoiceInfo

logger = logging.getLogger(__name__)

_VOICES = [
    VoiceInfo(id="af_heart", name="Heart", language="English"),
    VoiceInfo(id="af_bella", name="Bella", language="English"),
    VoiceInfo(id="af_nicole", name="Nicole", language="English"),
    VoiceInfo(id="af_sarah", name="Sarah", language="English"),
    VoiceInfo(id="af_sky", name="Sky", language="English"),
    VoiceInfo(id="am_adam", name="Adam", language="English"),
    VoiceInfo(id="am_michael", name="Michael", language="English"),
    VoiceInfo(id="bf_emma", name="Emma", language="English"),
    VoiceInfo(id="bf_isabella", name="Isabella", language="English"),
    VoiceInfo(id="bm_george", name="George", language="English"),
    VoiceInfo(id="bm_lewis", name="Lewis", language="English"),
]


class TTSService:
    """Synthesizes speech using the Kokoro TTS server."""

    def __init__(self, base_url: str):
        self.base_url = base_url

    async def speak(
        self,
        text: str,
        voice: str = "af_heart",
        speed: float = 1.0,
        response_format: str = "mp3",
    ) -> bytes:
        """Synthesize text to audio bytes."""
        async with httpx.AsyncClient(timeout=120.0) as client:
            response = await client.post(
                f"{self.base_url}/v1/audio/speech",
                json={
                    "model": "kokoro",
                    "input": text,
                    "voice": voice,
                    "speed": speed,
                    "response_format": response_format,
                },
            )
            response.raise_for_status()
            return response.content

    def list_voices(self) -> list[VoiceInfo]:
        """Return the list of available voices."""
        return list(_VOICES)

    async def health_check(self) -> bool:
        """Check if the TTS service is available."""
        try:
            async with httpx.AsyncClient(timeout=5.0) as client:
                response = await client.get(self.base_url)
                return response.status_code == 200
        except httpx.HTTPError:
            return False
