"""Unit tests for TTS inference resource guardrails."""

import asyncio
import threading
import time

import numpy as np
import pytest

from app.services.tts_service import TTSService


@pytest.mark.asyncio
async def test_speak_serializes_model_inference():
    service = TTSService(model=None)
    state_lock = threading.Lock()
    active = 0
    max_active = 0

    def generate_chunks(text: str, voice: str, speed: float) -> list[np.ndarray]:
        nonlocal active, max_active
        with state_lock:
            active += 1
            max_active = max(max_active, active)
        time.sleep(0.03)
        with state_lock:
            active -= 1
        return [np.zeros(100, dtype=np.int16)]

    service._generate_chunks = generate_chunks

    await asyncio.gather(
        service.speak("first", response_format="pcm"),
        service.speak("second", response_format="pcm"),
    )

    assert max_active == 1
