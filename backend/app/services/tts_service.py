"""In-process text-to-speech synthesis using Kokoro.

Heavy imports (torch, kokoro) are deferred so the backend starts instantly.
The model loads in the background on startup via `TTSService.start_loading()`.
"""

import asyncio
import logging
import os
from collections.abc import AsyncIterator
from io import BytesIO

import numpy as np

from app.core.config import get_settings
from app.schemas.audio import VoiceInfo

logger = logging.getLogger(__name__)

# Suppress noisy phonemizer "words count mismatch" warnings
logging.getLogger("phonemizer").setLevel(logging.ERROR)

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
        import av

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
        import av

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
        if self.fmt == "pcm":
            return b""
        for pkt in self._stream.encode(None):
            self._container.mux(pkt)
        data = self._buf.getvalue()
        self._container.close()
        self._buf.close()
        return data


class TTSService:
    """In-process TTS using Kokoro KPipeline.

    Call `start_loading()` during app lifespan to begin background init.
    Call `get_instance()` from endpoints — it awaits until the model is ready.
    """

    _instance: "TTSService | None" = None
    _ready = asyncio.Event()
    _error: Exception | None = None

    def __init__(self, model, voices_dir: str):
        self._model = model
        self._voices_dir = voices_dir
        self._pipelines: dict = {}

    @classmethod
    def start_loading(cls) -> None:
        """Kick off model loading in a background thread (non-blocking)."""
        asyncio.create_task(cls._load_in_background())

    @classmethod
    async def _load_in_background(cls) -> None:
        """Load the model off the event loop so startup isn't blocked."""
        try:
            instance = await asyncio.to_thread(cls._load_sync)
            cls._instance = instance
            logger.info("Kokoro TTS ready.")
        except Exception as e:
            logger.error("Failed to load Kokoro TTS: %s", e)
            cls._error = e
        finally:
            cls._ready.set()

    @staticmethod
    def _load_sync() -> "TTSService":
        """Synchronous heavy lifting — runs in a worker thread."""
        from kokoro import KModel

        settings = get_settings()
        model_dir = os.path.abspath(settings.kokoro_model_dir)
        voices_dir = os.path.abspath(settings.kokoro_voices_dir)
        config_path = os.path.join(model_dir, "config.json")
        model_path = os.path.join(model_dir, "kokoro-v1_0.pth")

        logger.info("Loading Kokoro model from %s …", model_path)
        model = KModel(config=config_path, model=model_path).eval().cpu()

        return TTSService(model, voices_dir)

    @classmethod
    async def get_instance(cls) -> "TTSService":
        """Return the singleton, waiting if the model is still loading."""
        await cls._ready.wait()
        if cls._error is not None:
            raise cls._error
        assert cls._instance is not None
        return cls._instance

    def _get_pipeline(self, lang_code: str):
        from kokoro import KPipeline

        if lang_code not in self._pipelines:
            self._pipelines[lang_code] = KPipeline(
                lang_code=lang_code, model=self._model, device="cpu"
            )
        return self._pipelines[lang_code]

    def _voice_path(self, voice_id: str) -> str:
        return os.path.join(self._voices_dir, f"{voice_id}.pt")

    def _generate_chunks(self, text: str, voice: str, speed: float) -> list[np.ndarray]:
        lang_code = voice[0].lower() if voice else "a"
        pipeline = self._get_pipeline(lang_code)
        voice_path = self._voice_path(voice)
        chunks = []
        for result in pipeline(text, voice=voice_path, speed=speed, model=self._model):
            if result.audio is not None:
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
