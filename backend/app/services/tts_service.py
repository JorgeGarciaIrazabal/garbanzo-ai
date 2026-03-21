"""In-process text-to-speech synthesis using Kokoro."""

import asyncio
import logging
import os
from collections.abc import AsyncIterator
from io import BytesIO

import av
import numpy as np
import torch
from kokoro import KModel, KPipeline

from app.core.config import get_settings
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

SAMPLE_RATE = 24000


class _AudioEncoder:
    """Encodes raw audio samples to mp3/wav/opus using PyAV."""

    def __init__(self, fmt: str = "mp3", sample_rate: int = SAMPLE_RATE):
        self.fmt = fmt.lower()
        self.sample_rate = sample_rate
        self.pts = 0

        codec_map = {"wav": "pcm_s16le", "mp3": "mp3", "opus": "libopus"}
        if self.fmt == "pcm":
            return

        self._buf = BytesIO()
        container_opts = {"write_xing": "0"} if self.fmt == "mp3" else {}
        self._container = av.open(self._buf, mode="w", format=self.fmt, options=container_opts)
        self._stream = self._container.add_stream(
            codec_map.get(self.fmt, self.fmt), rate=sample_rate, layout="mono"
        )
        if self.fmt in ("mp3", "opus", "aac"):
            self._stream.bit_rate = 128_000

    def encode_chunk(self, samples: np.ndarray) -> bytes:
        """Encode a chunk of int16 samples and return output bytes."""
        if self.fmt == "pcm":
            return samples.tobytes()

        frame = av.AudioFrame.from_ndarray(samples.reshape(1, -1), format="s16", layout="mono")
        frame.sample_rate = self.sample_rate
        frame.pts = self.pts
        self.pts += frame.samples

        for pkt in self._stream.encode(frame):
            self._container.mux(pkt)

        data = self._buf.getvalue()
        self._buf.seek(0)
        self._buf.truncate(0)
        return data

    def finalize(self) -> bytes:
        """Flush encoder and return remaining bytes."""
        if self.fmt == "pcm":
            return b""
        for pkt in self._stream.encode(None):
            self._container.mux(pkt)
        data = self._buf.getvalue()
        self._container.close()
        self._buf.close()
        return data


class TTSService:
    """In-process TTS using Kokoro KPipeline."""

    _instance: "TTSService | None" = None
    _lock = asyncio.Lock()

    def __init__(self, model: KModel, voices_dir: str):
        self._model = model
        self._voices_dir = voices_dir
        self._pipelines: dict[str, KPipeline] = {}

    @classmethod
    async def get_instance(cls) -> "TTSService":
        """Lazy singleton — loads the model on first call."""
        if cls._instance is not None:
            return cls._instance
        async with cls._lock:
            if cls._instance is not None:
                return cls._instance
            settings = get_settings()
            model_dir = os.path.abspath(settings.kokoro_model_dir)
            voices_dir = os.path.abspath(settings.kokoro_voices_dir)
            config_path = os.path.join(model_dir, "config.json")
            model_path = os.path.join(model_dir, "kokoro-v1_0.pth")
            logger.info("Loading Kokoro model from %s", model_path)
            model = KModel(config=config_path, model=model_path).eval().cpu()
            cls._instance = cls(model, voices_dir)
            # Warmup
            logger.info("Warming up Kokoro…")
            pipeline = cls._instance._get_pipeline("a")
            for _ in pipeline("Warmup.", voice=cls._instance._voice_path("af_heart"), speed=1.0):
                pass
            logger.info("Kokoro ready.")
            return cls._instance

    def _get_pipeline(self, lang_code: str) -> KPipeline:
        if lang_code not in self._pipelines:
            self._pipelines[lang_code] = KPipeline(
                lang_code=lang_code, model=self._model, device="cpu"
            )
        return self._pipelines[lang_code]

    def _voice_path(self, voice_id: str) -> str:
        return os.path.join(self._voices_dir, f"{voice_id}.pt")

    def _generate_chunks(
        self, text: str, voice: str, speed: float
    ) -> list[np.ndarray]:
        """Run KPipeline (CPU-bound) and collect audio chunks."""
        lang_code = voice[0].lower() if voice else "a"
        pipeline = self._get_pipeline(lang_code)
        voice_path = self._voice_path(voice)
        chunks = []
        for result in pipeline(text, voice=voice_path, speed=speed, model=self._model):
            if result.audio is not None:
                # Convert float32 → int16
                audio_int16 = (result.audio.numpy() * 32767).astype(np.int16)
                chunks.append(audio_int16)
        return chunks

    async def speak(
        self,
        text: str,
        voice: str = "af_heart",
        speed: float = 1.0,
        response_format: str = "mp3",
    ) -> bytes:
        """Generate complete audio for text (non-streaming)."""
        chunks = await asyncio.to_thread(self._generate_chunks, text, voice, speed)
        encoder = _AudioEncoder(response_format)
        parts = [encoder.encode_chunk(c) for c in chunks]
        parts.append(encoder.finalize())
        return b"".join(parts)

    async def stream_speak(
        self,
        text: str,
        voice: str = "af_heart",
        speed: float = 1.0,
        response_format: str = "mp3",
    ) -> AsyncIterator[bytes]:
        """Stream encoded audio chunks as they are generated."""
        encoder = _AudioEncoder(response_format)
        lang_code = voice[0].lower() if voice else "a"
        pipeline = self._get_pipeline(lang_code)
        voice_path = self._voice_path(voice)

        def _next_chunk(iterator):
            try:
                return next(iterator)
            except StopIteration:
                return None

        iterator = iter(pipeline(text, voice=voice_path, speed=speed, model=self._model))
        while True:
            result = await asyncio.to_thread(_next_chunk, iterator)
            if result is None:
                break
            if result.audio is not None:
                audio_int16 = (result.audio.numpy() * 32767).astype(np.int16)
                data = encoder.encode_chunk(audio_int16)
                if data:
                    yield data

        tail = encoder.finalize()
        if tail:
            yield tail

    def list_voices(self) -> list[VoiceInfo]:
        return list(_VOICES)
