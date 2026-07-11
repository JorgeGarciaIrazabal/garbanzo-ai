"""Integration tests for /api/v1/devices endpoints."""

import pytest
from httpx import ASGITransport, AsyncClient

from app.core.config import Settings, get_settings
from app.core.security import get_current_user
from app.db.session import get_db
from app.main import app
from app.services.device_service import DeviceService

pytestmark = pytest.mark.asyncio


_TEST_SETTINGS = Settings(
    secret_key="test-secret-key-do-not-use-in-prod",
    database_url="sqlite+aiosqlite:///:memory:",
    access_token_expire_minutes=30,
)


def _install_overrides(db_session, email: str = "test@example.com"):
    async def _override_db():
        yield db_session

    async def _override_user():
        return {"email": email, "token_payload": {}}

    app.dependency_overrides[get_db] = _override_db
    app.dependency_overrides[get_settings] = lambda: _TEST_SETTINGS
    app.dependency_overrides[get_current_user] = _override_user


def _clear_overrides():
    app.dependency_overrides.pop(get_db, None)
    app.dependency_overrides.pop(get_current_user, None)


async def _client():
    return AsyncClient(transport=ASGITransport(app=app), base_url="http://test")


async def test_register_device(db_session):
    _install_overrides(db_session)
    try:
        async with await _client() as c:
            resp = await c.post(
                "/api/v1/devices/register",
                json={"token": "fcm-token-1", "platform": "android"},
            )
        assert resp.status_code == 201
        body = resp.json()
        assert body["token"] == "fcm-token-1"
        assert body["platform"] == "android"
    finally:
        _clear_overrides()


async def test_re_registering_token_reassigns_ownership(db_session):
    """A duplicate token registered by another user gets reassigned."""
    from app.core.security import hash_password
    from app.models.user import User

    db_session.add(User(email="other@example.com", hashed_password=hash_password("x")))
    await db_session.commit()

    svc = DeviceService(db_session)
    await svc.register("other@example.com", "shared-token", "android")

    _install_overrides(db_session, email="test@example.com")
    try:
        async with await _client() as c:
            resp = await c.post(
                "/api/v1/devices/register",
                json={"token": "shared-token", "platform": "ios"},
            )
        assert resp.status_code == 201
        assert resp.json()["platform"] == "ios"
    finally:
        _clear_overrides()


async def test_unregister_device(db_session):
    svc = DeviceService(db_session)
    await svc.register("test@example.com", "to-delete", "android")

    _install_overrides(db_session)
    try:
        async with await _client() as c:
            resp = await c.request(
                "DELETE",
                "/api/v1/devices/register",
                json={"token": "to-delete", "platform": "android"},
            )
        assert resp.status_code == 204
    finally:
        _clear_overrides()


async def test_unregister_missing_404(db_session):
    _install_overrides(db_session)
    try:
        async with await _client() as c:
            resp = await c.request(
                "DELETE",
                "/api/v1/devices/register",
                json={"token": "nope", "platform": "android"},
            )
        assert resp.status_code == 404
    finally:
        _clear_overrides()
