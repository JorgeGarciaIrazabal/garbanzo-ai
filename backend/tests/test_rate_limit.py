"""Tests for the per-user token-bucket rate limiter."""

import pytest
from fastapi import HTTPException

from app.core.config import Settings
from app.core.rate_limit import rate_limit, reset_buckets, take_token


@pytest.fixture(autouse=True)
def _clean_buckets():
    reset_buckets()
    yield
    reset_buckets()


class TestTakeToken:
    def test_allows_burst_up_to_rate_then_blocks(self):
        key = ("user@example.com", "chat")
        for _ in range(5):
            assert take_token(key, 5, now=100.0) is None
        wait = take_token(key, 5, now=100.0)
        assert wait is not None and wait > 0

    def test_refills_over_time(self):
        key = ("user@example.com", "chat")
        for _ in range(5):
            assert take_token(key, 5, now=100.0) is None
        assert take_token(key, 5, now=100.0) is not None
        # 5/min == one token every 12s.
        assert take_token(key, 5, now=113.0) is None
        assert take_token(key, 5, now=113.0) is not None

    def test_buckets_are_isolated_per_user_and_scope(self):
        assert take_token(("a@x.com", "chat"), 1, now=0.0) is None
        # a@x.com chat is now empty; other user / other scope unaffected.
        assert take_token(("a@x.com", "chat"), 1, now=0.0) is not None
        assert take_token(("b@x.com", "chat"), 1, now=0.0) is None
        assert take_token(("a@x.com", "tts"), 1, now=0.0) is None

    def test_wait_time_matches_refill_rate(self):
        key = ("user@example.com", "stt")
        for _ in range(60):
            assert take_token(key, 60, now=0.0) is None
        wait = take_token(key, 60, now=0.0)
        # 60/min == 1 token per second → ~1s wait.
        assert wait == pytest.approx(1.0, abs=0.01)


class TestRateLimitDependency:
    user = {"email": "user@example.com"}

    @pytest.mark.asyncio
    async def test_disabled_by_default(self):
        settings = Settings(secret_key="test")
        dep = rate_limit("chat")
        for _ in range(100):
            await dep(current_user=self.user, settings=settings)

    @pytest.mark.asyncio
    async def test_enforces_limit_with_retry_after(self):
        settings = Settings(
            secret_key="test",
            rate_limit_enabled=True,
            rate_limit_chat_per_minute=2,
        )
        dep = rate_limit("chat")
        await dep(current_user=self.user, settings=settings)
        await dep(current_user=self.user, settings=settings)
        with pytest.raises(HTTPException) as exc_info:
            await dep(current_user=self.user, settings=settings)
        assert exc_info.value.status_code == 429
        assert int(exc_info.value.headers["Retry-After"]) >= 1

    @pytest.mark.asyncio
    async def test_zero_limit_disables_scope(self):
        settings = Settings(
            secret_key="test",
            rate_limit_enabled=True,
            rate_limit_tts_per_minute=0,
        )
        dep = rate_limit("tts")
        for _ in range(10):
            await dep(current_user=self.user, settings=settings)
