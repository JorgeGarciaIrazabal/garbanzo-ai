"""Integration tests for /api/v1/notifications endpoints."""

import pytest
from httpx import ASGITransport, AsyncClient

from app.core.config import Settings, get_settings
from app.core.security import get_current_user
from app.db.session import get_db
from app.main import app
from app.services.notification_service import NotificationService

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


async def test_list_empty(db_session):
    _install_overrides(db_session)
    try:
        async with await _client() as c:
            resp = await c.get("/api/v1/notifications")
        assert resp.status_code == 200
        body = resp.json()
        assert body["items"] == []
        assert body["unread_count"] == 0
    finally:
        _clear_overrides()


async def test_list_and_unread_count(db_session):
    svc = NotificationService(db_session)
    await svc.create(user_id="test@example.com", title="a", body="b")
    await svc.create(user_id="test@example.com", title="c", body="d")

    _install_overrides(db_session)
    try:
        async with await _client() as c:
            resp = await c.get("/api/v1/notifications")
            assert resp.status_code == 200
            assert resp.json()["unread_count"] == 2

            unread_only = await c.get("/api/v1/notifications/unread-count")
            assert unread_only.json()["unread_count"] == 2
    finally:
        _clear_overrides()


async def test_mark_read_endpoint(db_session):
    svc = NotificationService(db_session)
    notif = await svc.create(user_id="test@example.com", title="a", body="b")

    _install_overrides(db_session)
    try:
        async with await _client() as c:
            resp = await c.patch(f"/api/v1/notifications/{notif.id}/read")
            assert resp.status_code == 204

            unread = await c.get("/api/v1/notifications/unread-count")
            assert unread.json()["unread_count"] == 0
    finally:
        _clear_overrides()


async def test_mark_read_missing_404(db_session):
    _install_overrides(db_session)
    try:
        async with await _client() as c:
            resp = await c.patch("/api/v1/notifications/missing/read")
        assert resp.status_code == 404
    finally:
        _clear_overrides()


async def test_mark_all_read(db_session):
    svc = NotificationService(db_session)
    await svc.create(user_id="test@example.com", title="a", body="b")
    await svc.create(user_id="test@example.com", title="c", body="d")

    _install_overrides(db_session)
    try:
        async with await _client() as c:
            resp = await c.post("/api/v1/notifications/read-all")
            assert resp.status_code == 204
            assert (
                (await c.get("/api/v1/notifications/unread-count")).json()[
                    "unread_count"
                ]
                == 0
            )
    finally:
        _clear_overrides()


async def test_delete_notification(db_session):
    svc = NotificationService(db_session)
    notif = await svc.create(user_id="test@example.com", title="a", body="b")

    _install_overrides(db_session)
    try:
        async with await _client() as c:
            resp = await c.delete(f"/api/v1/notifications/{notif.id}")
            assert resp.status_code == 204
            listing = await c.get("/api/v1/notifications")
            assert listing.json()["items"] == []
    finally:
        _clear_overrides()


async def test_delete_missing_404(db_session):
    _install_overrides(db_session)
    try:
        async with await _client() as c:
            resp = await c.delete("/api/v1/notifications/missing")
        assert resp.status_code == 404
    finally:
        _clear_overrides()


async def test_get_preferences_autocreates(db_session):
    _install_overrides(db_session)
    try:
        async with await _client() as c:
            resp = await c.get("/api/v1/notifications/preferences")
        assert resp.status_code == 200
        body = resp.json()
        assert body["chat_responses_enabled"] is True
        assert body["reminders_enabled"] is True
        assert body["system_alerts_enabled"] is True
    finally:
        _clear_overrides()


async def test_update_preferences(db_session):
    _install_overrides(db_session)
    try:
        async with await _client() as c:
            resp = await c.patch(
                "/api/v1/notifications/preferences",
                json={"reminders_enabled": False},
            )
        assert resp.status_code == 200
        assert resp.json()["reminders_enabled"] is False
    finally:
        _clear_overrides()
