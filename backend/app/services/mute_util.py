"""Shared notification-mute semantics for rooms and conversations.

``RoomMember.muted_until`` and ``Conversation.muted_until`` both use the same
representation: ``NULL`` = not muted, a real timestamp = a timed mute, and a
far-future sentinel = muted forever. Centralizing the sentinel, the duration
table, and the "is this active" check here means every caller — room service,
conversation service, both notification skip-checks — only ever needs one
comparison against "now".
"""

from __future__ import annotations

from datetime import UTC, datetime, timedelta

# "Mute forever" sentinel: a timestamp far enough in the future that it will
# never naturally elapse, instead of a separate ``muted_forever`` boolean
# column. Every call site — the notification skip-checks, the frontend badge —
# only ever needs one comparison: ``muted_until > now()``.
MUTE_FOREVER = datetime(9999, 12, 31, 23, 59, 59, tzinfo=UTC)

_MUTE_DURATIONS: dict[str, timedelta] = {
    "8h": timedelta(hours=8),
    "1w": timedelta(weeks=1),
}


def resolve_mute_until(duration: str) -> datetime | None:
    """Compute the new ``muted_until`` value for a mute ``duration`` string.

    ``duration`` is one of ``"8h"``, ``"1w"``, ``"forever"``, ``"unmute"``
    (validated by the ``MuteUpdate`` schema at the API boundary). Returns
    ``None`` for ``"unmute"`` — callers assign the result straight to the
    ``muted_until`` column.
    """
    if duration == "unmute":
        return None
    if duration == "forever":
        return MUTE_FOREVER
    return datetime.now(UTC) + _MUTE_DURATIONS[duration]


def is_muted(muted_until: datetime | None, now: datetime) -> bool:
    """Whether a ``muted_until`` value is still in effect.

    ``now`` is always tz-aware (UTC). ``muted_until`` is normally tz-aware too
    (``DateTime(timezone=True)``), but SQLite — used in tests — round-trips
    ``DateTime(timezone=True)`` values as naive datetimes, so a naive value is
    treated as UTC rather than raising on comparison.
    """
    if muted_until is None:
        return False
    if muted_until.tzinfo is None:
        muted_until = muted_until.replace(tzinfo=UTC)
    return muted_until > now
