"""Best-effort persistence for unexpected errors that affect a user."""

from __future__ import annotations

import contextlib
import hashlib
import time
import traceback
from collections.abc import Mapping
from typing import Any

from app.core.config import get_settings
from app.services.report_service import ReportService

_REPORT_WINDOW_SECONDS = 5 * 60
_LAST_REPORTED: dict[tuple[str, str], float] = {}


def error_fingerprint(error: BaseException, trace: str) -> str:
    """Stable-enough per-process identity for a repeated failure."""
    # The exception class plus traceback location catches retry/render loops
    # without making different errors with the same text look identical.
    source = f"{type(error).__qualname__}\n{trace}"
    return hashlib.sha256(source.encode("utf-8", errors="replace")).hexdigest()


def should_report_error(user_id: str, fingerprint: str) -> bool:
    """Allow one report per user/error fingerprint within the short window."""
    now = time.monotonic()
    stale_before = now - _REPORT_WINDOW_SECONDS
    for key, reported_at in list(_LAST_REPORTED.items()):
        if reported_at < stale_before:
            del _LAST_REPORTED[key]
    key = (user_id, fingerprint)
    if key in _LAST_REPORTED:
        return False
    _LAST_REPORTED[key] = now
    return True


def clear_error_report_rate_limit() -> None:
    """Test hook for the in-memory dedupe state."""
    _LAST_REPORTED.clear()


def error_title(prefix: str, error: BaseException) -> str:
    message = " ".join(str(error).split()) or "No message"
    return f"{prefix}: {type(error).__name__}: {message}"[:200]


async def create_auto_error_report(
    *,
    user_id: str,
    error: BaseException,
    trace: str,
    title_prefix: str,
    metadata: Mapping[str, Any] | None = None,
    conversation_id: str | None = None,
) -> None:
    """File an auto-report in a new session; reporting can never raise back."""
    if not get_settings().auto_error_reports:
        return
    fingerprint = error_fingerprint(error, trace)
    if not should_report_error(user_id, fingerprint):
        return

    # Import lazily so test fixtures replacing the session maker are honored.
    from app.db import session as db_session

    report_metadata = dict(metadata or {})
    report_metadata.setdefault("stack_trace", trace[:10000])
    report_metadata.setdefault("exception_fingerprint", fingerprint)
    try:
        async with db_session.async_session_maker() as db:
            service = ReportService(db)
            report = await service.create(
                user_id=user_id,
                type_="bug",
                title=error_title(title_prefix, error),
                description=trace[:10000],
                metadata=report_metadata,
                conversation_id=conversation_id,
                severity="error",
                source="backend",
            )
            with contextlib.suppress(Exception):
                await service.notify_admins(report)
    except Exception:
        # Intentionally no logging here: this commonly means the database is
        # itself the original failure, and a second traceback adds no value.
        pass


async def report_chat_error(
    *,
    user_id: str,
    conversation_id: str,
    message_id: str | None,
    model: str,
    last_user_turn: str,
    error: BaseException,
    tool_call_id: str | None = None,
    trace: str | None = None,
) -> None:
    """Persist an LLM/chat stream failure with enough context to reproduce it."""
    trace = trace or "".join(traceback.format_exception(type(error), error, error.__traceback__))
    await create_auto_error_report(
        user_id=user_id,
        error=error,
        trace=trace,
        title_prefix="Chat stream error",
        conversation_id=conversation_id,
        metadata={
            "conversation_id": conversation_id,
            "message_id": message_id,
            "tool_call_id": tool_call_id,
            "model": model,
            "last_user_turn": last_user_turn[:2000],
        },
    )
