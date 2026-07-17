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

# Kokoro v1.0 voice packs. The voice ID's first letter is the KPipeline
# lang_code (a=US/b=UK English, e=Spanish, f=French, h=Hindi, i=Italian,
# p=Brazilian Portuguese); packs auto-download from HuggingFace on first use.
# Japanese (j*) and Mandarin (z*) exist upstream but need the misaki[ja] /
# misaki[zh] extras, which aren't installed — the espeak-based languages
# below work with the already-bundled espeakng-loader. Per language, the
# first entry is what `default_voice_for_language` picks (idea 13.3).
_VOICES = [
    VoiceInfo(id="af_heart", name="Heart", language="English", lang_code="en"),
    VoiceInfo(id="af_bella", name="Bella", language="English", lang_code="en"),
    VoiceInfo(id="af_nicole", name="Nicole", language="English", lang_code="en"),
    VoiceInfo(id="af_sarah", name="Sarah", language="English", lang_code="en"),
    VoiceInfo(id="af_sky", name="Sky", language="English", lang_code="en"),
    VoiceInfo(id="am_adam", name="Adam", language="English", lang_code="en"),
    VoiceInfo(id="am_michael", name="Michael", language="English", lang_code="en"),
    VoiceInfo(id="bf_emma", name="Emma", language="English", lang_code="en"),
    VoiceInfo(id="bf_isabella", name="Isabella", language="English", lang_code="en"),
    VoiceInfo(id="bm_george", name="George", language="English", lang_code="en"),
    VoiceInfo(id="bm_lewis", name="Lewis", language="English", lang_code="en"),
    VoiceInfo(id="ef_dora", name="Dora", language="Spanish", lang_code="es"),
    VoiceInfo(id="em_alex", name="Alex", language="Spanish", lang_code="es"),
    VoiceInfo(id="em_santa", name="Santa", language="Spanish", lang_code="es"),
    VoiceInfo(id="ff_siwis", name="Siwis", language="French", lang_code="fr"),
    VoiceInfo(id="hf_alpha", name="Alpha", language="Hindi", lang_code="hi"),
    VoiceInfo(id="hf_beta", name="Beta", language="Hindi", lang_code="hi"),
    VoiceInfo(id="hm_omega", name="Omega", language="Hindi", lang_code="hi"),
    VoiceInfo(id="hm_psi", name="Psi", language="Hindi", lang_code="hi"),
    VoiceInfo(id="if_sara", name="Sara", language="Italian", lang_code="it"),
    VoiceInfo(id="im_nicola", name="Nicola", language="Italian", lang_code="it"),
    VoiceInfo(id="pf_dora", name="Dora", language="Portuguese (BR)", lang_code="pt"),
    VoiceInfo(id="pm_alex", name="Alex", language="Portuguese (BR)", lang_code="pt"),
    VoiceInfo(id="pm_santa", name="Santa", language="Portuguese (BR)", lang_code="pt"),
]

_VOICES_BY_ID = {v.id: v for v in _VOICES}


def default_voice_for_language(language: str) -> str | None:
    """Return the default voice ID for an ISO language code, or None if no
    voice speaks it. Region subtags are ignored ("es-MX" → "es")."""
    code = language.lower().split("-")[0]
    for v in _VOICES:
        if v.lang_code == code:
            return v.id
    return None


def resolve_voice_for_language(voice: str, language: str | None) -> str:
    """Pick the voice to synthesize with, given a requested voice and an
    optional target language (idea 13.3).

    No language (or "auto") keeps the requested voice. Otherwise, a voice
    that already speaks the language is kept (a user-pinned choice wins over
    the per-language default); a mismatched voice is swapped for the
    language's default. Unknown/unsupported languages keep the requested
    voice so a bad detection degrades to today's behavior instead of a 500.
    """
    if not language or language == "auto":
        return voice
    known = _VOICES_BY_ID.get(voice)
    code = language.lower().split("-")[0]
    if known is not None and known.lang_code == code:
        return voice
    return default_voice_for_language(code) or voice


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

    def __init__(self, model):
        self._model = model
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
        config_path = os.path.join(model_dir, "config.json")
        model_path = os.path.join(model_dir, "kokoro-v1_0.pth")

        # Try local files first, fall back to auto-download from HuggingFace
        if os.path.exists(model_path) and os.path.exists(config_path):
            logger.info("Loading Kokoro model from %s …", model_path)
            model = KModel(config=config_path, model=model_path).eval().cpu()
        else:
            logger.info("Local Kokoro model not found, downloading from HuggingFace …")
            model = KModel(repo_id="hexgrad/Kokoro-82M").eval().cpu()

        return TTSService(model)

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

    def _resolve_voice(self, voice_id: str) -> str:
        """Return a local voice path if it exists, otherwise the bare voice ID
        (KPipeline will auto-download from HuggingFace)."""
        settings = get_settings()
        voices_dir = os.path.abspath(settings.kokoro_voices_dir)
        local = os.path.join(voices_dir, f"{voice_id}.pt")
        return local if os.path.exists(local) else voice_id

    def _generate_chunks(self, text: str, voice: str, speed: float) -> list[np.ndarray]:
        lang_code = voice[0].lower() if voice else "a"
        pipeline = self._get_pipeline(lang_code)
        voice_ref = self._resolve_voice(voice)
        chunks = []
        for result in pipeline(text, voice=voice_ref, speed=speed, model=self._model):
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
        voice_ref = self._resolve_voice(voice)

        def _next_chunk(iterator):
            try:
                return next(iterator)
            except StopIteration:
                return None

        iterator = iter(pipeline(text, voice=voice_ref, speed=speed, model=self._model))
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
