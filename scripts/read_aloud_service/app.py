"""Private, single-process Pocket synthesis worker for read-aloud sessions."""

from __future__ import annotations

import asyncio
import ctypes
import gc
import logging
import os
import signal
import threading
import time
from collections.abc import AsyncIterator
from contextlib import asynccontextmanager
from typing import Annotated

import numpy as np
from fastapi import FastAPI, Header, HTTPException
from fastapi.responses import StreamingResponse
from pydantic import BaseModel, Field

logger = logging.getLogger("read_aloud")
_LIBC = ctypes.CDLL("libc.so.6")
SAMPLE_RATE = 24_000
MAX_UNIT_CHARS = 300
STALLED_SECONDS = 15.0
WORKER_TOKEN = os.environ.get("READ_ALOUD_WORKER_TOKEN", "")

VOICE_REFERENCES = {
    ("en", "alba"): "hf://kyutai/tts-voices/alba-mackenna/casual.wav@323332d33f997de8394f24a193e1a76df720e01a",
    ("es", "lola"): "hf://kyutai/pocket-tts/common_voice_es_19762977-enhanced-v2.mp3@64ab7d24c479d736a83b8cc666c4a776fca30fda",
}
LANGUAGE_MODELS = {"en": "english_2026-04", "es": "spanish_24l"}


class SynthesisRequest(BaseModel):
    language: str = Field(pattern="^(en|es)$")
    voice: str = Field(min_length=1, max_length=32)
    text: str = Field(min_length=1, max_length=MAX_UNIT_CHARS)


class Engine:
    def __init__(self) -> None:
        self.models = {}
        self.states = {}
        self._inference_lock = threading.Lock()
        self.ready = False

    def load(self) -> None:
        if not WORKER_TOKEN:
            raise RuntimeError("READ_ALOUD_WORKER_TOKEN is required")

        import torch
        import pocket_tts

        torch.set_num_threads(int(os.environ.get("OMP_NUM_THREADS", "4")))
        utils = __import__("pocket_tts.utils.utils", fromlist=["download_if_necessary"])
        config_module = __import__("pocket_tts.utils.config", fromlist=["CONFIGS_DIR", "load_config"])

        for language, model_name in LANGUAGE_MODELS.items():
            config = config_module.load_config(config_module.CONFIGS_DIR / f"{model_name}.yaml")
            if not config.weights_path:
                raise RuntimeError(f"Pocket {model_name} cloning weights are unavailable")
            # Download gated weights before load_model; Pocket otherwise hides Hub
            # failures behind a public non-cloning checkpoint.
            utils.download_if_necessary(config.weights_path)
            model = pocket_tts.TTSModel.load_model(language=model_name, quantize=True)
            if not model.has_voice_cloning:
                raise RuntimeError(f"Pocket {model_name} loaded without voice cloning")
            self.models[language] = model
            for (voice_language, voice), reference in VOICE_REFERENCES.items():
                if voice_language != language:
                    continue
                self.states[(language, voice)] = model.get_state_for_audio_prompt(reference)

            # Warm one short phrase with the prepared state before reporting ready.
            for _ in model.generate_audio_stream(
                self.states[(language, "alba" if language == "en" else "lola")],
                "Ready.",
            ):
                pass

        self.ready = True
        logger.info("Pocket read-aloud worker is ready for English and Spain Spanish")

    def generate(self, language: str, voice: str, text: str):
        state = self.states[(language, voice)]
        model = self.models[language]
        with self._inference_lock:
            try:
                yield from model.generate_audio_stream(state, text)
            finally:
                # Pocket allocates short-lived decoder and copied conditioning
                # state for every unit. Give glibc those pages back before the
                # next unit so a 100k-character message fits the 6 GiB limit.
                gc.collect()
                _LIBC.malloc_trim(0)


engine = Engine()


@asynccontextmanager
async def lifespan(_: FastAPI):
    await asyncio.to_thread(engine.load)
    yield


app = FastAPI(title="Garbanzo Read-Aloud Worker", lifespan=lifespan)


@app.get("/health/ready")
async def readiness() -> dict[str, object]:
    return {"status": "ready" if engine.ready else "loading", "sample_rate": SAMPLE_RATE}


@app.post("/internal/synthesize")
async def synthesize(
    request: SynthesisRequest,
    worker_token: Annotated[str | None, Header(alias="X-Read-Aloud-Worker-Token")] = None,
) -> StreamingResponse:
    if not WORKER_TOKEN or worker_token != WORKER_TOKEN:
        raise HTTPException(status_code=401, detail="Invalid worker credentials")
    if not engine.ready:
        raise HTTPException(status_code=503, detail="Read-aloud worker is not ready")
    if (request.language, request.voice) not in engine.states:
        raise HTTPException(status_code=422, detail="Voice is not available for this language")

    async def audio() -> AsyncIterator[bytes]:
        iterator = iter(engine.generate(request.language, request.voice, request.text))
        while True:
            started = time.monotonic()

            def next_chunk():
                try:
                    return next(iterator)
                except StopIteration:
                    return None

            try:
                samples = await asyncio.wait_for(asyncio.to_thread(next_chunk), STALLED_SECONDS)
            except TimeoutError:
                logger.exception("Pocket produced no audio for %.1f seconds; recycling worker", STALLED_SECONDS)
                os.kill(os.getpid(), signal.SIGTERM)
                raise HTTPException(status_code=504, detail="Synthesis worker stalled")
            if samples is None:
                break
            if time.monotonic() - started > STALLED_SECONDS:
                logger.error("Pocket chunk exceeded %.1f seconds; recycling worker", STALLED_SECONDS)
                os.kill(os.getpid(), signal.SIGTERM)
                raise HTTPException(status_code=504, detail="Synthesis worker stalled")
            if hasattr(samples, "detach"):
                samples = samples.detach().cpu().numpy()
            pcm = np.clip(np.asarray(samples).reshape(-1) * 32767, -32768, 32767).astype("<i2")
            if pcm.size:
                yield pcm.tobytes()

    return StreamingResponse(
        audio(),
        media_type="application/octet-stream",
        headers={"X-Audio-Sample-Rate": str(SAMPLE_RATE), "Cache-Control": "no-store"},
    )
