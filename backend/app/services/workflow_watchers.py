"""Tracks which workflow runs a client is actively watching.

A push notification is only worth sending when the user *isn't* looking at the
app — otherwise the run's own progress line already told them, and the phone
buzzes for nothing.

The signal is free: a desktop app with the conversation open polls
``GET /workflows/{id}`` every ~1.5 s for as long as the run is live. So "the
last poll was seconds ago" means someone is watching, and silence means the app
is closed (or asleep).

In-memory and single-process, like :mod:`client_tool_bridge` — the polling
endpoint and the runner share the process. A restart just means the next run
is treated as unwatched, which errs toward notifying.
"""

from __future__ import annotations

import time

# How recently a run must have been polled to count as "being watched". The
# client polls every 1.5 s, so this tolerates a slow request or a brief hiccup
# without being long enough to suppress a genuinely missed completion.
WATCHING_WINDOW_SECONDS = 15.0

# Entries older than this are dead weight: the runner forgets a run when it
# completes, so anything this stale belongs to a run that never got there
# (crashed runner, deleted row, client polling a ghost). A run itself can't
# exceed its 15-minute budget, so an hour is safely past any live poll.
_STALE_AFTER_SECONDS = 3600.0

_last_seen: dict[str, float] = {}


def mark_watching(run_id: str) -> None:
    """Record that a client just polled ``run_id``."""
    now = time.monotonic()
    # Self-cleaning: completion normally removes entries, but a run that never
    # completes would leak its entry forever. The map holds at most a handful
    # of live runs, so sweeping it on every poll is nothing.
    for stale in [rid for rid, t in _last_seen.items() if now - t > _STALE_AFTER_SECONDS]:
        del _last_seen[stale]
    _last_seen[run_id] = now


def is_watched(run_id: str, within_seconds: float | None = None) -> bool:
    """True when a client polled ``run_id`` within ``within_seconds``.

    The window is read at call time rather than bound as a default argument,
    so adjusting :data:`WATCHING_WINDOW_SECONDS` actually takes effect.
    """
    window = WATCHING_WINDOW_SECONDS if within_seconds is None else within_seconds
    last = _last_seen.get(run_id)
    return last is not None and (time.monotonic() - last) <= window


def forget(run_id: str) -> None:
    """Drop a finished run's entry so the map doesn't grow unbounded."""
    _last_seen.pop(run_id, None)
