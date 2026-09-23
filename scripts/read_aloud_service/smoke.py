"""Measure first streamed PCM and validate both warm Pocket voices."""

import json
import os
import time
from urllib.request import Request, urlopen

WORKER_URL = os.environ.get("READ_ALOUD_WORKER_URL", "http://127.0.0.1:8021")
TOKEN = os.environ["READ_ALOUD_WORKER_TOKEN"]

for language, voice, text in (
    ("en", "alba", "Good morning. This is a short English read-aloud check."),
    ("es", "lola", "Buenos días. Esta es una prueba breve en español de España."),
):
    request = Request(
        WORKER_URL + "/internal/synthesize",
        data=json.dumps({"language": language, "voice": voice, "text": text}).encode(),
        headers={"Content-Type": "application/json", "X-Read-Aloud-Worker-Token": TOKEN},
        method="POST",
    )
    started = time.monotonic()
    with urlopen(request, timeout=20) as response:
        assert response.status == 200
        assert response.headers["X-Audio-Sample-Rate"] == "24000"
        first = response.read(2048)
        first_seconds = time.monotonic() - started
        rest = response.read()
    pcm = first + rest
    assert len(pcm) > 4800 and len(pcm) % 2 == 0
    print(json.dumps({"language": language, "first_pcm_seconds": round(first_seconds, 3), "audio_seconds": round(len(pcm) / 48000, 2)}))
