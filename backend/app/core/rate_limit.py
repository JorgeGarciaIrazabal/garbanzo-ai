"""Per-user token-bucket rate limiting for expensive endpoints.

Disabled by default so development stays unlimited. Enable with
``RATE_LIMIT_ENABLED=true`` and tune the per-scope
``RATE_LIMIT_<SCOPE>_PER_MINUTE`` settings (0 disables a single scope).

Buckets are in-process (one per user x scope), which matches the
single-process deployment; revisit if the backend ever goes multi-process.
"""

import time
from dataclasses import dataclass
from typing import Annotated, Any

from fastapi import Depends, HTTPException, status

from app.core.config import Settings, get_settings
from app.core.security import get_current_user


@dataclass
class _Bucket:
    tokens: float
    updated_at: float


_buckets: dict[tuple[str, str], _Bucket] = {}


def take_token(
    key: tuple[str, str], rate_per_minute: int, now: float | None = None
) -> float | None:
    """Try to take one token from the bucket for ``key``.

    Returns None on success, or the number of seconds until a token frees up.
    The bucket holds at most ``rate_per_minute`` tokens (burst == sustained
    rate) and refills continuously.
    """
    if now is None:
        now = time.monotonic()
    capacity = float(rate_per_minute)
    refill_per_second = rate_per_minute / 60.0

    bucket = _buckets.get(key)
    if bucket is None:
        bucket = _Bucket(tokens=capacity, updated_at=now)
        _buckets[key] = bucket
    else:
        elapsed = max(0.0, now - bucket.updated_at)
        bucket.tokens = min(capacity, bucket.tokens + elapsed * refill_per_second)
        bucket.updated_at = now

    if bucket.tokens >= 1.0:
        bucket.tokens -= 1.0
        return None
    return (1.0 - bucket.tokens) / refill_per_second


def reset_buckets() -> None:
    """Test helper: drop all bucket state."""
    _buckets.clear()


def rate_limit(scope: str):
    """FastAPI dependency limiting requests per user for ``scope``.

    The per-minute limit comes from the ``rate_limit_<scope>_per_minute``
    setting. Responds 429 with a Retry-After header when exhausted.
    """

    async def dependency(
        current_user: Annotated[dict[str, Any], Depends(get_current_user)],
        settings: Annotated[Settings, Depends(get_settings)],
    ) -> None:
        if not settings.rate_limit_enabled:
            return
        limit: int = getattr(settings, f"rate_limit_{scope}_per_minute")
        if limit <= 0:
            return
        retry_after = take_token((current_user["email"], scope), limit)
        if retry_after is not None:
            raise HTTPException(
                status_code=status.HTTP_429_TOO_MANY_REQUESTS,
                detail=f"Rate limit exceeded for {scope}; try again shortly.",
                headers={"Retry-After": str(max(1, int(retry_after + 0.999)))},
            )

    return dependency
