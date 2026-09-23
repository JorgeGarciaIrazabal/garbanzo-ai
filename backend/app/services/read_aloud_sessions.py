"""Owned, bounded read-aloud sessions backed by one continuous MP3 file."""

from __future__ import annotations

import asyncio
import json
import logging
import os
import time
import uuid
from collections.abc import AsyncIterator
from contextlib import suppress
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

import httpx
import numpy as np

from app.core.config import get_settings
from app.services.read_aloud_text import SpeechUnit, prepare_speech_units
from app.services.tts_service import _AudioEncoder

logger = logging.getLogger(__name__)
SAMPLE_RATE = 24_000
SEEK_PAUSE_MS = 72
MP3_FRAME_SAMPLES = 576
MP3_FRAME_BYTES = 384
SEEK_PREROLL_FRAMES = 2
MAX_CACHE_BYTES = 512 * 1024 * 1024
IDLE_EXPIRY_SECONDS = 30 * 60
MAX_AHEAD_MS = 30_000
TERMINAL_STATES = frozenset({"completed", "failed", "cancelled", "expired"})
VOICE_CATALOG = (
    {
        "id": "alba",
        "name": "Alba",
        "language": "en",
        "preview_url": "/api/v1/tts/read-aloud/voices/alba/preview",
    },
    {
        "id": "lola",
        "name": "Lola",
        "language": "es",
        "preview_url": "/api/v1/tts/read-aloud/voices/lola/preview",
    },
)
PREVIEW_TEXT = {
    "alba": "Good morning. I can read your messages aloud in English.",
    "lola": "Buenos días. Puedo leerte los mensajes en español de España.",
}


class ReadAloudError(Exception):
    def __init__(self, code: str, message: str, status: int = 400) -> None:
        super().__init__(message)
        self.code = code
        self.status = status


@dataclass(slots=True)
class ReadAloudSession:
    id: str
    owner: str
    units: list[SpeechUnit]
    total_paragraphs: int
    voice_en: str
    voice_es: str
    path: Path
    created_at: float = field(default_factory=time.monotonic)
    last_used_at: float = field(default_factory=time.monotonic)
    state: str = "preparing"
    playback_state: str = "playing"
    position_ms: int = 0
    last_update_seq: int = -1
    generated_duration_ms: int = 0
    audio_bytes: int = 0
    stream_readers: int = 0
    segments: list[dict[str, Any]] = field(default_factory=list)
    error: str | None = None
    error_code: str | None = None
    events: list[dict[str, Any]] = field(default_factory=list)
    revision: int = 0
    condition: asyncio.Condition = field(default_factory=asyncio.Condition)
    task: asyncio.Task[None] | None = None

    def status(self) -> dict[str, Any]:
        return {
            "id": self.id,
            "state": self.state,
            "generated_duration_ms": self.generated_duration_ms,
            "position_ms": self.position_ms,
            "total_paragraphs": self.total_paragraphs,
            "segments": list(self.segments),
            "error": self.error,
            "error_code": self.error_code,
        }


class ReadAloudManager:
    def __init__(
        self,
        worker_url: str | None = None,
        worker_token: str | None = None,
        cache_dir: Path | None = None,
    ) -> None:
        settings = get_settings()
        self.worker_url = (worker_url or settings.read_aloud_worker_url).rstrip("/")
        self.worker_token = (
            worker_token if worker_token is not None else settings.read_aloud_worker_token
        )
        self.cache_dir = cache_dir or Path(settings.read_aloud_cache_dir)
        self.cache_dir.mkdir(mode=0o700, parents=True, exist_ok=True)
        self.cache_dir.chmod(0o700)
        # Session IDs live only in this process. Audio left by a prior backend
        # process is unreachable and must not consume the bounded cache forever.
        for path in self.cache_dir.glob("*.mp3"):
            if len(path.stem) == 32 and all(char in "0123456789abcdef" for char in path.stem):
                path.unlink()
        self._sessions: dict[str, ReadAloudSession] = {}
        self._expired: dict[str, tuple[str, float]] = {}
        self._lock = asyncio.Lock()
        self._janitor_task: asyncio.Task[None] | None = None

    async def check_ready(self) -> None:
        if not self.worker_token:
            raise ReadAloudError(
                "worker_not_configured", "Read-aloud worker credentials are missing", 503
            )
        try:
            async with httpx.AsyncClient(timeout=3.0) as client:
                response = await client.get(f"{self.worker_url}/health/ready")
                response.raise_for_status()
                if response.json().get("status") != "ready":
                    raise ReadAloudError(
                        "worker_not_ready", "Read-aloud worker is still loading", 503
                    )
        except (httpx.HTTPError, ValueError) as exc:
            raise ReadAloudError(
                "worker_unavailable", "Read-aloud worker is unavailable", 503
            ) from exc

    async def create(
        self,
        owner: str,
        text: str,
        *,
        voice_en: str = "alba",
        voice_es: str = "lola",
        language_mode: str = "auto",
        start_paragraph: int = 0,
    ) -> ReadAloudSession:
        if voice_en != "alba" or voice_es != "lola":
            raise ReadAloudError("invalid_voice", "Choose a voice from the read-aloud catalog", 422)
        if start_paragraph < 0:
            raise ReadAloudError("invalid_paragraph", "start_paragraph must be nonnegative", 422)
        try:
            all_units = prepare_speech_units(text, language_mode)
        except ValueError as exc:
            message = str(exc)
            status = 413 if "exceeds" in message else 422
            raise ReadAloudError("invalid_text", message, status) from exc
        total_paragraphs = max(unit.paragraph for unit in all_units) + 1
        if start_paragraph >= total_paragraphs:
            raise ReadAloudError("invalid_paragraph", "start_paragraph is beyond the message", 422)
        units = [
            SpeechUnit(index, unit.paragraph, unit.language, unit.text)
            for index, unit in enumerate(
                unit for unit in all_units if unit.paragraph >= start_paragraph
            )
        ]
        await self.check_ready()
        async with self._lock:
            await self._expire_idle_locked()
            if self._janitor_task is None or self._janitor_task.done():
                self._janitor_task = asyncio.create_task(self._janitor())
            # Only one live read-aloud session per user. A late client callback
            # cannot make the older generation resume after a new selection.
            prior = [
                session
                for session in self._sessions.values()
                if session.owner == owner and session.state not in TERMINAL_STATES
            ]
            for session in prior:
                await self._cancel_locked(session)
            session_id = uuid.uuid4().hex
            session = ReadAloudSession(
                id=session_id,
                owner=owner,
                units=units,
                total_paragraphs=total_paragraphs,
                voice_en=voice_en,
                voice_es=voice_es,
                path=self.cache_dir / f"{session_id}.mp3",
            )
            self._sessions[session_id] = session
            session.task = asyncio.create_task(self._run(session), name=f"read-aloud-{session_id}")
            return session

    async def get(self, session_id: str, owner: str) -> ReadAloudSession:
        async with self._lock:
            session = self._sessions.get(session_id)
            if session is None or session.owner != owner:
                expired = self._expired.get(session_id)
                if expired is not None and expired[0] == owner:
                    raise ReadAloudError("session_expired", "Read-aloud session expired", 410)
                raise ReadAloudError("session_not_found", "Read-aloud session not found", 404)
            if time.monotonic() - session.last_used_at > IDLE_EXPIRY_SECONDS:
                await self._expire_locked(session)
                raise ReadAloudError("session_expired", "Read-aloud session expired", 410)
            session.last_used_at = time.monotonic()
            return session

    async def update(
        self, session_id: str, owner: str, *, state: str, position_ms: int, update_seq: int
    ) -> dict[str, Any]:
        if state not in {"playing", "paused", "buffering", "completed"}:
            raise ReadAloudError("invalid_state", "Invalid playback state", 422)
        if position_ms < 0:
            raise ReadAloudError("invalid_position", "position_ms must be nonnegative", 422)
        if update_seq < 0:
            raise ReadAloudError("invalid_update_seq", "update_seq must be nonnegative", 422)
        session = await self.get(session_id, owner)
        if update_seq <= session.last_update_seq:
            return session.status()
        if session.state in {"failed", "cancelled", "expired"}:
            raise ReadAloudError("session_finished", "Read-aloud session cannot be resumed", 409)
        if state == "completed" and session.state != "completed":
            raise ReadAloudError("session_generating", "Speech is still being generated", 409)
        session.last_update_seq = update_seq
        session.playback_state = state
        session.position_ms = min(position_ms, session.generated_duration_ms)
        if session.state != "completed":
            session.state = "paused" if state == "paused" else state
        await self._signal(session)
        return session.status()

    async def cancel(self, session_id: str, owner: str) -> dict[str, Any]:
        session = await self.get(session_id, owner)
        await self._cancel_locked(session)
        return session.status()

    async def audio(self, session_id: str, owner: str, start_segment: int) -> AsyncIterator[bytes]:
        session = await self.get(session_id, owner)
        if start_segment < 0 or start_segment > len(session.units):
            raise ReadAloudError("invalid_segment", "Invalid start segment", 422)
        if start_segment > 0 and start_segment >= len(session.segments):
            raise ReadAloudError("segment_unprepared", "That paragraph is not prepared yet", 409)
        offset = 0 if start_segment == 0 else session.segments[start_segment]["start_byte"]

        async def stream() -> AsyncIterator[bytes]:
            session.stream_readers += 1
            try:
                # The writer creates the file in the background. A stream can
                # open immediately after session creation while it prepares.
                while not session.path.exists():
                    if session.state in TERMINAL_STATES:
                        return
                    await self._wait_for_change(session, session.revision)
                with session.path.open("rb") as source:
                    source.seek(offset)
                    while True:
                        data = await asyncio.to_thread(source.read, 64 * 1024)
                        if data:
                            session.last_used_at = time.monotonic()
                            yield data
                            continue
                        if session.state in TERMINAL_STATES:
                            return
                        await self._wait_for_change(session, session.revision)
            finally:
                session.stream_readers -= 1

        return stream()

    async def events(self, session_id: str, owner: str, after: int = 0) -> AsyncIterator[str]:
        session = await self.get(session_id, owner)

        async def stream() -> AsyncIterator[str]:
            cursor = max(0, after)
            while True:
                for event in session.events[cursor:]:
                    cursor = event["seq"]
                    yield f"id: {cursor}\nevent: {event['type']}\ndata: {json.dumps(event)}\n\n"
                if session.state in TERMINAL_STATES:
                    return
                revision = session.revision
                await self._wait_for_change(session, revision)
                if session.revision == revision:
                    yield ": keep-alive\n\n"

        return stream()

    async def preview(self, voice: str) -> bytes:
        if voice not in PREVIEW_TEXT:
            raise ReadAloudError("invalid_voice", "Read-aloud voice not found", 404)
        await self.check_ready()
        preview_file = self.cache_dir / f"voice-{voice}.mp3"
        if preview_file.is_file():
            return preview_file.read_bytes()
        self.cache_dir.mkdir(mode=0o700, parents=True, exist_ok=True)
        encoder = _AudioEncoder("mp3", sample_rate=SAMPLE_RATE)
        encoded = bytearray()
        language = "en" if voice == "alba" else "es"
        remainder = b""
        async for data in self._worker_pcm(PREVIEW_TEXT[voice], language, voice):
            samples, remainder = self._decode_pcm(data, remainder)
            if samples.size:
                encoded.extend(encoder.encode_chunk(samples))
        if remainder:
            raise ReadAloudError("worker_audio_invalid", "Worker returned incomplete PCM", 502)
        encoded.extend(encoder.finalize())
        preview_file.write_bytes(encoded)
        return bytes(encoded)

    async def _run(self, session: ReadAloudSession) -> None:
        try:
            encoder = _AudioEncoder("mp3", sample_rate=SAMPLE_RATE)
            timeline_samples = 0
            fd = os.open(session.path, os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o600)
            with os.fdopen(fd, "wb") as output:
                await self._signal(session)
                for unit in session.units:
                    await self._wait_for_capacity(session)
                    # The MP3 encoder holds several frames before emitting them.
                    # Derive paragraph seek positions from the PCM timeline, not
                    # from bytes emitted at the moment a new unit begins.
                    start_byte = self._mp3_offset_for_sample(timeline_samples, session.path)
                    start_ms = session.generated_duration_ms
                    generated_samples = 0
                    remainder = b""
                    voice = session.voice_en if unit.language == "en" else session.voice_es
                    async for data in self._worker_pcm(unit.text, unit.language, voice):
                        samples, remainder = self._decode_pcm(data, remainder)
                        if samples.size:
                            offset = 0
                            while offset < samples.size:
                                await self._wait_for_capacity(session)
                                ahead_samples = (
                                    (session.generated_duration_ms - session.position_ms)
                                    * SAMPLE_RATE
                                    // 1000
                                )
                                available = MAX_AHEAD_MS * SAMPLE_RATE // 1000 - ahead_samples
                                portion = samples[offset : offset + available]
                                generated_samples += portion.size
                                offset += portion.size
                                session.generated_duration_ms = round(
                                    (timeline_samples + generated_samples) * 1000 / SAMPLE_RATE
                                )
                                await self._write(session, output, encoder.encode_chunk(portion))
                    if remainder:
                        raise ReadAloudError(
                            "worker_audio_invalid", "Worker returned incomplete PCM", 502
                        )
                    if generated_samples == 0:
                        raise ReadAloudError("worker_no_audio", "Worker returned no audio", 502)
                    timeline_samples += generated_samples
                    if unit.index < len(session.units) - 1:
                        # A brief pause gives a frame-aligned paragraph seek a
                        # clean lead-in without repeating or clipping speech.
                        pause = np.zeros(SAMPLE_RATE * SEEK_PAUSE_MS // 1000, dtype="<i2")
                        pause_offset = 0
                        while pause_offset < pause.size:
                            await self._wait_for_capacity(session)
                            ahead_samples = (
                                (session.generated_duration_ms - session.position_ms)
                                * SAMPLE_RATE
                                // 1000
                            )
                            available = MAX_AHEAD_MS * SAMPLE_RATE // 1000 - ahead_samples
                            portion = pause[pause_offset : pause_offset + available]
                            pause_offset += portion.size
                            timeline_samples += portion.size
                            session.generated_duration_ms = round(
                                timeline_samples * 1000 / SAMPLE_RATE
                            )
                            await self._write(session, output, encoder.encode_chunk(portion))
                    duration_ms = round(generated_samples * 1000 / SAMPLE_RATE)
                    if unit.index < len(session.units) - 1:
                        duration_ms += SEEK_PAUSE_MS
                    segment = {
                        "id": str(unit.index),
                        "index": unit.index,
                        "paragraph": unit.paragraph,
                        "language": unit.language,
                        "duration_ms": duration_ms,
                        "start_ms": start_ms,
                        "start_byte": start_byte,
                    }
                    session.segments.append(segment)
                    if session.state == "preparing":
                        session.state = (
                            "playing" if session.playback_state == "playing" else "paused"
                        )
                    await self._event(session, "segment_ready", segment=segment)
                await self._write(session, output, encoder.finalize())
                session.state = "completed"
                await self._event(session, "completed")
        except asyncio.CancelledError:
            if session.state not in {"cancelled", "expired"}:
                session.state = "cancelled"
                await self._event(session, "cancelled")
            raise
        except ReadAloudError as exc:
            session.state = "failed"
            session.error = str(exc)
            session.error_code = exc.code
            await self._event(session, "failed", error_code=exc.code, error=str(exc))
        except Exception:
            logger.exception("Read-aloud session %s failed", session.id)
            session.state = "failed"
            session.error = "Speech generation stopped unexpectedly"
            session.error_code = "worker_failed"
            await self._event(session, "failed", error_code=session.error_code, error=session.error)

    @staticmethod
    def _mp3_offset_for_sample(sample: int, path: Path) -> int:
        if sample == 0:
            return 0
        with path.open("rb") as source:
            header = source.read(10)
            if header[:3] != b"ID3":
                raise ReadAloudError("encoder_invalid", "MP3 stream has no ID3 header", 502)
            tag_size = 10 + sum(
                (header[index] & 0x7F) << shift
                for index, shift in zip(range(6, 10), (21, 14, 7, 0), strict=True)
            )
            source.seek(tag_size)
            frame = source.read(4)
        if (
            len(frame) != 4
            or frame[0] != 0xFF
            or frame[1] & 0xFE != 0xF2  # MPEG-2 Layer III
            or frame[2] >> 4 != 12  # 128 kbps
            or frame[2] & 0x0E != 0x04  # 24 kHz, no frame padding
        ):
            raise ReadAloudError("encoder_invalid", "MP3 frame format changed", 502)

        # At 24 kHz/128 kbps MPEG-2 Layer III, each 576-sample frame is
        # exactly 384 bytes. Two earlier frames lie wholly within the inserted
        # 72 ms pause, including when the boundary is frame-aligned. They give
        # a cold decoder bit-reservoir history without repeating prior speech.
        frame_index = max(0, sample // MP3_FRAME_SAMPLES - SEEK_PREROLL_FRAMES)
        return tag_size + frame_index * MP3_FRAME_BYTES

    async def _worker_pcm(self, text: str, language: str, voice: str) -> AsyncIterator[bytes]:
        timeout = httpx.Timeout(connect=5.0, read=15.0, write=5.0, pool=5.0)
        try:
            async with (
                httpx.AsyncClient(timeout=timeout) as client,
                client.stream(
                    "POST",
                    f"{self.worker_url}/internal/synthesize",
                    headers={"X-Read-Aloud-Worker-Token": self.worker_token},
                    json={"text": text, "language": language, "voice": voice},
                ) as response,
            ):
                if response.status_code != 200:
                    raise ReadAloudError(
                        "worker_failed",
                        f"Synthesis worker returned HTTP {response.status_code}",
                        502,
                    )
                if response.headers.get("X-Audio-Sample-Rate") != str(SAMPLE_RATE):
                    raise ReadAloudError("worker_audio_invalid", "Worker sample rate mismatch", 502)
                async for chunk in response.aiter_bytes(32 * 1024):
                    if chunk:
                        yield chunk
        except httpx.TimeoutException as exc:
            raise ReadAloudError(
                "worker_stalled", "Speech generation made no progress for 15 seconds", 504
            ) from exc
        except httpx.HTTPError as exc:
            raise ReadAloudError("worker_disconnected", "Speech worker disconnected", 502) from exc

    @staticmethod
    def _decode_pcm(chunk: bytes, remainder: bytes) -> tuple[np.ndarray, bytes]:
        complete = remainder + chunk
        aligned_length = len(complete) & ~1
        return np.frombuffer(complete[:aligned_length], dtype="<i2"), complete[aligned_length:]

    async def _write(self, session: ReadAloudSession, output: Any, data: bytes) -> None:
        if not data:
            return
        await self._check_cache_capacity(len(data))
        output.write(data)
        output.flush()
        session.audio_bytes += len(data)
        await self._signal(session)

    async def _check_cache_capacity(self, incoming_bytes: int) -> None:
        total = sum(session.audio_bytes for session in self._sessions.values())
        if total + incoming_bytes <= MAX_CACHE_BYTES:
            return
        async with self._lock:
            disposable = sorted(
                (
                    session
                    for session in self._sessions.values()
                    if session.state in TERMINAL_STATES
                    and session.stream_readers == 0
                    and (
                        session.state in {"failed", "cancelled", "expired"}
                        or session.playback_state == "completed"
                    )
                ),
                key=lambda session: session.last_used_at,
            )
            for session in disposable:
                self._remove_locked(session)
                total -= session.audio_bytes
                if total + incoming_bytes <= MAX_CACHE_BYTES:
                    return
        raise ReadAloudError("cache_full", "Read-aloud cache is full", 507)

    async def _wait_for_capacity(self, session: ReadAloudSession) -> None:
        async with session.condition:
            while (
                session.playback_state == "paused"
                or session.generated_duration_ms - session.position_ms >= MAX_AHEAD_MS
            ):
                if session.state in {"cancelled", "expired"}:
                    raise asyncio.CancelledError
                await session.condition.wait()

    async def _wait_for_change(self, session: ReadAloudSession, revision: int) -> None:
        async with session.condition:
            if session.revision == revision:
                with suppress(TimeoutError):
                    await asyncio.wait_for(session.condition.wait(), 15)

    async def _signal(self, session: ReadAloudSession) -> None:
        async with session.condition:
            session.revision += 1
            session.condition.notify_all()

    async def _event(self, session: ReadAloudSession, event_type: str, **details: Any) -> None:
        event = {"seq": len(session.events) + 1, "type": event_type, **details}
        session.events.append(event)
        await self._signal(session)

    async def _cancel_locked(self, session: ReadAloudSession) -> None:
        if session.state in {"failed", "cancelled", "expired"}:
            return
        session.state = "cancelled"
        session.playback_state = "completed"
        if session.task is not None:
            session.task.cancel()
        await self._event(session, "cancelled")

    async def _expire_locked(self, session: ReadAloudSession) -> None:
        session.state = "expired"
        if session.task is not None:
            session.task.cancel()
        await self._event(session, "expired")
        self._remove_locked(session)

    async def _expire_idle_locked(self) -> None:
        now = time.monotonic()
        stale = [
            session
            for session in self._sessions.values()
            if now - session.last_used_at > IDLE_EXPIRY_SECONDS
        ]
        for session in stale:
            await self._expire_locked(session)
        self._expired = {
            session_id: record
            for session_id, record in self._expired.items()
            if now - record[1] < IDLE_EXPIRY_SECONDS
        }

    async def _janitor(self) -> None:
        while True:
            await asyncio.sleep(60)
            async with self._lock:
                await self._expire_idle_locked()

    async def shutdown(self) -> None:
        tasks = [session.task for session in self._sessions.values() if session.task is not None]
        if self._janitor_task is not None:
            tasks.append(self._janitor_task)
        for task in tasks:
            task.cancel()
        if tasks:
            await asyncio.gather(*tasks, return_exceptions=True)
        self._janitor_task = None

    def _remove_locked(self, session: ReadAloudSession) -> None:
        self._sessions.pop(session.id, None)
        self._expired[session.id] = (session.owner, time.monotonic())
        try:
            session.path.unlink(missing_ok=True)
        except OSError:
            logger.warning("Could not delete expired read-aloud file %s", session.path)


_manager: ReadAloudManager | None = None


def get_read_aloud_manager() -> ReadAloudManager:
    global _manager
    if _manager is None:
        _manager = ReadAloudManager()
    return _manager


async def shutdown_read_aloud_manager() -> None:
    if _manager is not None:
        await _manager.shutdown()
