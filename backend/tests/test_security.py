"""Tests for core.security — JWT and password utilities."""

from datetime import timedelta

import jwt

from app.core.config import Settings
from app.core.security import (
    create_access_token,
    decode_token,
    hash_password,
    verify_password,
)


def _settings() -> Settings:
    return Settings(
        secret_key="test-secret-key-for-tests",
        access_token_expire_minutes=30,
    )


# ============================================================================
# Password hashing
# ============================================================================


class TestPasswordHashing:
    def test_hash_and_verify(self):
        hashed = hash_password("mysecret")
        assert verify_password("mysecret", hashed)

    def test_wrong_password_rejected(self):
        hashed = hash_password("mysecret")
        assert not verify_password("wrong", hashed)

    def test_hashes_differ_across_calls(self):
        h1 = hash_password("same")
        h2 = hash_password("same")
        assert h1 != h2  # bcrypt uses random salt

    def test_verify_with_garbage_hash(self):
        assert not verify_password("pw", "not-a-valid-hash")


# ============================================================================
# JWT tokens
# ============================================================================


class TestJWT:
    def test_create_and_decode(self):
        settings = _settings()
        token = create_access_token({"sub": "user@example.com"}, settings)
        payload = decode_token(token, settings)
        assert payload is not None
        assert payload["sub"] == "user@example.com"
        assert "exp" in payload

    def test_custom_expiry(self):
        settings = _settings()
        token = create_access_token(
            {"sub": "u@e.com"},
            settings,
            expires_delta=timedelta(minutes=5),
        )
        payload = decode_token(token, settings)
        assert payload is not None

    def test_decode_invalid_token(self):
        settings = _settings()
        assert decode_token("garbage.token.here", settings) is None

    def test_decode_wrong_secret(self):
        settings = _settings()
        token = create_access_token({"sub": "u@e.com"}, settings)

        wrong = Settings(secret_key="different-key", access_token_expire_minutes=30)
        assert decode_token(token, wrong) is None

    def test_expired_token_rejected(self):
        settings = _settings()
        token = create_access_token(
            {"sub": "u@e.com"},
            settings,
            expires_delta=timedelta(seconds=-1),
        )
        assert decode_token(token, settings) is None

    def test_token_contains_correct_algorithm(self):
        settings = _settings()
        token = create_access_token({"sub": "u@e.com"}, settings)
        header = jwt.get_unverified_header(token)
        assert header["alg"] == "HS256"
