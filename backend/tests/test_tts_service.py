"""Unit tests for TTS inference resource guardrails."""

import asyncio
import threading
import time

import numpy as np
import pytest

from app.services.tts_service import TTSService, _select_device


@pytest.mark.parametrize(
    ("requested", "cuda_available", "expected"),
    [
        ("cpu", False, "cpu"),
        ("cpu", True, "cpu"),
        ("auto", False, "cpu"),
        ("auto", True, "cuda"),
        ("cuda", True, "cuda"),
    ],
)
def test_select_device(requested: str, cuda_available: bool, expected: str):
    assert _select_device(requested, cuda_available=cuda_available) == expected


def test_select_device_rejects_unavailable_forced_cuda():
    with pytest.raises(RuntimeError, match="CUDA is unavailable"):
        _select_device("cuda", cuda_available=False)


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
