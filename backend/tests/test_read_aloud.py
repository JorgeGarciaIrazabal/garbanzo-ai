"""Focused read-aloud text and owned streaming-session behavior."""

import asyncio
import os
import time
from io import BytesIO

import av
import numpy as np
import pytest
from httpx import ASGITransport, AsyncClient

from app.core.security import get_current_user
from app.main import app
from app.services import read_aloud_sessions
from app.services.read_aloud_sessions import (
    ReadAloudError,
    ReadAloudManager,
    get_read_aloud_manager,
)
from app.services.read_aloud_text import detect_language, prepare_speech_units

pytestmark = pytest.mark.asyncio


async def test_short_spanish_and_embedded_foreign_word_detection() -> None:
    assert detect_language("Hola.", "auto") == "es"
    assert detect_language("No.", "auto") == "en"
    assert detect_language("This sentence has hola inside it.", "auto") == "en"


class FakePocketManager(ReadAloudManager):
    async def check_ready(self) -> None:
        return None

    async def _worker_pcm(self, text: str, language: str, voice: str):
        assert 0 < len(text) <= 300
        assert (language, voice) in {("en", "alba"), ("es", "lola")}
        yield np.zeros(2400, dtype="<i2").tobytes()


class LongChunkManager(FakePocketManager):
    async def _worker_pcm(self, text: str, language: str, voice: str):
        for _ in range(35):
            yield np.zeros(24_000, dtype="<i2").tobytes()


class TwoToneManager(FakePocketManager):
    first_samples = 24_000

    async def _worker_pcm(self, text: str, language: str, voice: str):
        frequency = 440 if "First" in text else 880
        samples_count = self.first_samples if frequency == 440 else 24_000
        times = np.arange(samples_count) / 24_000
        samples = (np.sin(2 * np.pi * frequency * times) * 10_000).astype("<i2")
        yield samples.tobytes()


async def test_markdown_preparation_preserves_table_values_and_long_unpunctuated_text() -> None:
    source = (
        "Hello [friend](https://example.com).\n\n"
        "```python\nsecret_call()\n```\n\n"
        "| Item | Value |\n| --- | --- |\n| Uno | España |\n\n"
        "Buenos días, ¿cómo estás?\n\n" + "unbroken " * 140
    )
    units = prepare_speech_units(source)
    spoken = " ".join(unit.text for unit in units)
    assert "friend" in spoken and "https://" not in spoken
    assert "secret_call" not in spoken
    assert "Item: Uno" in spoken and "Value: España" in spoken
    assert any(unit.language == "es" and "Buenos días" in unit.text for unit in units)
    assert spoken.count("unbroken") == 140
    assert all(len(unit.text) <= 300 for unit in units)


async def test_owned_session_streams_one_ordered_mp3_and_terminal_event(tmp_path) -> None:
    manager = FakePocketManager(worker_token="test", cache_dir=tmp_path)
    session = await manager.create("alice", "First paragraph.\n\nSegundo párrafo.")
    with pytest.raises(ReadAloudError) as denied:
        await manager.get(session.id, "bob")
    assert denied.value.status == 404

    stream = await manager.audio(session.id, "alice", 0)
    audio_task = asyncio.create_task(_collect_bytes(stream))
    await asyncio.wait_for(session.task, 5)
    audio = await asyncio.wait_for(audio_task, 5)
    assert audio.startswith(b"ID3") or audio[:2] == b"\xff\xfb"
    assert len(audio) > 100
    with av.open(BytesIO(audio), format="mp3") as container:
        decoded_samples = sum(frame.samples for frame in container.decode(audio=0))
    assert decoded_samples >= 4800
    assert [segment["index"] for segment in session.segments] == [0, 1]
    assert [segment["paragraph"] for segment in session.segments] == [0, 1]
    second = await _collect_bytes(await manager.audio(session.id, "alice", 1))
    assert len(second) > 0
    with av.open(BytesIO(second), format="mp3") as container:
        assert sum(frame.samples for frame in container.decode(audio=0)) > 0
    assert session.state == "completed"
    events = await manager.events(session.id, "alice")
    payload = [event async for event in events]
    assert sum("event: segment_ready" in event for event in payload) == 2
    assert payload[-1].startswith("id: 3\nevent: completed")
    await manager.shutdown()


async def test_cancel_during_preparation_has_single_terminal_event(tmp_path) -> None:
    manager = FakePocketManager(worker_token="test", cache_dir=tmp_path)
    session = await manager.create("alice", "This is a message.")
    await manager.cancel(session.id, "alice")
    assert session.state == "cancelled"
    assert [event["type"] for event in session.events] == ["cancelled"]
    with pytest.raises(ReadAloudError) as denied:
        await manager.update(session.id, "alice", state="playing", position_ms=0, update_seq=0)
    assert denied.value.status == 409
    await manager.shutdown()


async def test_stale_position_update_cannot_override_pause_or_backward_seek(tmp_path) -> None:
    manager = FakePocketManager(worker_token="test", cache_dir=tmp_path)
    session = await manager.create("alice", "First paragraph.\n\nSecond paragraph.")
    await asyncio.wait_for(session.task, 5)
    await manager.update(session.id, "alice", state="paused", position_ms=0, update_seq=3)
    await manager.update(session.id, "alice", state="playing", position_ms=200, update_seq=2)
    assert session.playback_state == "paused"
    assert session.position_ms == 0
    await manager.update(session.id, "alice", state="playing", position_ms=100, update_seq=4)
    await manager.update(session.id, "alice", state="playing", position_ms=200, update_seq=1)
    assert session.position_ms == 100
    await manager.shutdown()


async def test_generation_never_runs_more_than_30_seconds_ahead_within_one_unit(tmp_path) -> None:
    manager = LongChunkManager(worker_token="test", cache_dir=tmp_path)
    session = await manager.create("alice", "One long unit.")

    async with session.condition:
        await asyncio.wait_for(
            session.condition.wait_for(lambda: session.generated_duration_ms >= 30_000),
            5,
        )
    assert session.generated_duration_ms == 30_000
    assert session.task is not None and not session.task.done()
    await manager.update(session.id, "alice", state="playing", position_ms=10_000, update_seq=1)
    await asyncio.wait_for(session.task, 5)
    assert session.generated_duration_ms == 35_000
    await manager.shutdown()


@pytest.mark.parametrize("first_samples", [24_000, 24_192])
async def test_paragraph_offset_begins_with_requested_audio(tmp_path, first_samples) -> None:
    manager = TwoToneManager(worker_token="test", cache_dir=tmp_path)
    manager.first_samples = first_samples
    session = await manager.create("alice", "First tone.\n\nSecond tone.")
    await asyncio.wait_for(session.task, 5)
    suffix = await _collect_bytes(await manager.audio(session.id, "alice", 1))
    with av.open(BytesIO(suffix), format="mp3") as container:
        decoded = np.concatenate(
            [frame.to_ndarray().reshape(-1) for frame in container.decode(audio=0)]
        )
    # A seek may include a short quiet lead-in, but must not repeat the first
    # paragraph's 440 Hz tone or skip the second paragraph's opening audio.
    assert len(decoded) >= 24_000
    assert np.sqrt(np.mean(decoded[:1200].astype(float) ** 2)) < 0.01
    window = decoded[1440:4800]
    assert np.sqrt(np.mean(window.astype(float) ** 2)) > 0.1
    frequencies = np.fft.rfftfreq(window.size, 1 / 24_000)
    dominant = frequencies[np.argmax(np.abs(np.fft.rfft(window)))]
    assert abs(dominant - 880) < 20
    await manager.shutdown()


async def test_cache_pressure_keeps_completed_audio_while_user_is_listening(
    tmp_path, monkeypatch
) -> None:
    manager = FakePocketManager(worker_token="test", cache_dir=tmp_path)
    first = await manager.create("alice", "First message.")
    await asyncio.wait_for(first.task, 5)
    monkeypatch.setattr(read_aloud_sessions, "MAX_CACHE_BYTES", first.audio_bytes + 100)
    second = await manager.create("alice", "Second message.")
    await asyncio.wait_for(second.task, 5)
    assert second.state == "failed" and second.error_code == "cache_full"
    assert first.path.exists()
    await manager.update(
        first.id,
        "alice",
        state="completed",
        position_ms=first.generated_duration_ms,
        update_seq=1,
    )
    third = await manager.create("alice", "Third message.")
    await asyncio.wait_for(third.task, 5)
    assert third.state == "completed"
    assert not first.path.exists()
    await manager.shutdown()


async def test_maximum_message_keeps_every_unit_with_bounded_ahead_generation(tmp_path) -> None:
    text = "word " * 20_000
    assert len(text) == 100_000
    manager = FakePocketManager(worker_token="test", cache_dir=tmp_path)
    session = await manager.create("alice", text)
    sequence = 0
    while session.task is not None and not session.task.done():
        await manager.update(
            session.id,
            "alice",
            state="playing",
            position_ms=session.generated_duration_ms,
            update_seq=sequence,
        )
        sequence += 1
        await asyncio.sleep(0.01)
    assert session.state == "completed"
    assert len(session.segments) == len(session.units)
    assert [segment["index"] for segment in session.segments] == list(range(len(session.units)))
    assert sum(unit.text.count("word") for unit in session.units) == 20_000
    assert session.audio_bytes < 512 * 1024 * 1024
    await manager.shutdown()


@pytest.mark.skipif(not os.getenv("READ_ALOUD_LIVE_TEST"), reason="requires warm Pocket worker")
async def test_real_worker_streams_english_and_spanish(tmp_path) -> None:
    manager = ReadAloudManager(
        worker_url="http://127.0.0.1:8021",
        worker_token=os.environ["READ_ALOUD_WORKER_TOKEN"],
        cache_dir=tmp_path,
    )
    started = time.monotonic()
    session = await manager.create("alice", "Good morning.\n\nBuenos días.")
    stream = await manager.audio(session.id, "alice", 0)
    first = await asyncio.wait_for(anext(stream), 15)
    first_byte_seconds = time.monotonic() - started
    remaining = await asyncio.wait_for(_collect_bytes(stream), 30)
    await asyncio.wait_for(session.task, 30)
    assert len(first + remaining) > 1000
    assert [segment["language"] for segment in session.segments] == ["en", "es"]
    assert session.state == "completed"
    assert first_byte_seconds < 5
    await manager.shutdown()


async def test_session_api_requires_auth_and_hides_other_users_sessions(tmp_path) -> None:
    manager = FakePocketManager(worker_token="test", cache_dir=tmp_path)
    app.dependency_overrides[get_read_aloud_manager] = lambda: manager
    app.dependency_overrides[get_current_user] = lambda: {"email": "alice"}
    try:
        async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as client:
            root = "/api/v1/tts/read-aloud"
            created = await client.post(f"{root}/sessions", json={"text": "Hello there."})
            assert created.status_code == 200
            session_id = created.json()["id"]
            oversized = await client.post(f"{root}/sessions", json={"text": "a" * 100_001})
            assert oversized.status_code == 413
            app.dependency_overrides[get_current_user] = lambda: {"email": "bob"}
            other = await client.get(f"{root}/sessions/{session_id}")
            assert other.status_code == 404
            app.dependency_overrides.pop(get_current_user)
            anonymous = await client.get(f"{root}/sessions/{session_id}")
            assert anonymous.status_code in {401, 403}
    finally:
        app.dependency_overrides.pop(get_read_aloud_manager, None)
        app.dependency_overrides.pop(get_current_user, None)
        await manager.shutdown()


async def _collect_bytes(stream) -> bytes:
    return b"".join([part async for part in stream])
