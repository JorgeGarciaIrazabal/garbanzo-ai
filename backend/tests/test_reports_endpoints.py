"""Integration tests for /api/v1/reports and /api/v1/admin/reports endpoints."""

import pytest
from httpx import ASGITransport, AsyncClient

from app.core.config import Settings, get_settings
from app.core.security import get_current_admin_user, get_current_user, hash_password
from app.db.session import get_db
from app.main import app
from app.models.user import User

pytestmark = pytest.mark.asyncio

_TEST_SETTINGS = Settings(
    secret_key="test-secret-key-do-not-use-in-prod",
    database_url="sqlite+aiosqlite:///:memory:",
    access_token_expire_minutes=30,
)


def _install_overrides(db_session, email: str = "test@example.com", admin: bool = False):
    async def _override_db():
        yield db_session

    async def _override_user():
        return {"email": email, "token_payload": {}}

    app.dependency_overrides[get_db] = _override_db
    app.dependency_overrides[get_settings] = lambda: _TEST_SETTINGS
    app.dependency_overrides[get_current_user] = _override_user
    if admin:
        app.dependency_overrides[get_current_admin_user] = _override_user


def _clear_overrides():
    app.dependency_overrides.pop(get_db, None)
    app.dependency_overrides.pop(get_current_user, None)
    app.dependency_overrides.pop(get_current_admin_user, None)


# Note: conftest's db_session fixture already seeds test@example.com.
async def _seed_user(db_session, email: str):
    db_session.add(User(email=email, hashed_password=hash_password("x")))
    await db_session.commit()


def _client():
    return AsyncClient(transport=ASGITransport(app=app), base_url="http://test")


async def test_create_and_list_own_reports(db_session):
    _install_overrides(db_session)
    try:
        async with _client() as c:
            resp = await c.post(
                "/api/v1/reports",
                json={"type": "bug", "title": "Crash on send", "description": "Steps: …"},
            )
            assert resp.status_code == 201
            body = resp.json()
            assert body["type"] == "bug"
            assert body["status"] == "open"
            assert body["user_id"] == "test@example.com"

            resp = await c.get("/api/v1/reports/mine")
            assert resp.status_code == 200
            mine = resp.json()
            assert len(mine) == 1
            assert mine[0]["title"] == "Crash on send"
    finally:
        _clear_overrides()


async def test_create_rejects_bad_type(db_session):
    _install_overrides(db_session)
    try:
        async with _client() as c:
            resp = await c.post(
                "/api/v1/reports",
                json={"type": "complaint", "title": "t", "description": "d"},
            )
        assert resp.status_code == 422
    finally:
        _clear_overrides()


async def test_mine_excludes_other_users_reports(db_session):
    await _seed_user(db_session, "a@example.com")
    await _seed_user(db_session, "b@example.com")

    _install_overrides(db_session, email="a@example.com")
    try:
        async with _client() as c:
            await c.post(
                "/api/v1/reports",
                json={"type": "feature", "title": "Dark mode", "description": "please"},
            )
    finally:
        _clear_overrides()

    _install_overrides(db_session, email="b@example.com")
    try:
        async with _client() as c:
            resp = await c.get("/api/v1/reports/mine")
        assert resp.json() == []
    finally:
        _clear_overrides()


async def test_admin_lists_all_and_filters_by_status(db_session):
    await _seed_user(db_session, "a@example.com")
    await _seed_user(db_session, "admin@example.com")

    _install_overrides(db_session, email="a@example.com")
    try:
        async with _client() as c:
            r1 = (
                await c.post(
                    "/api/v1/reports",
                    json={"type": "bug", "title": "One", "description": "d"},
                )
            ).json()
            await c.post(
                "/api/v1/reports",
                json={"type": "feature", "title": "Two", "description": "d"},
            )
    finally:
        _clear_overrides()

    _install_overrides(db_session, email="admin@example.com", admin=True)
    try:
        async with _client() as c:
            resp = await c.get("/api/v1/admin/reports")
            assert resp.status_code == 200
            assert len(resp.json()) == 2

            # Triage one to in_progress, then filter on it.
            resp = await c.patch(
                f"/api/v1/admin/reports/{r1['id']}",
                json={"status": "in_progress"},
            )
            assert resp.status_code == 200
            assert resp.json()["status"] == "in_progress"

            resp = await c.get("/api/v1/admin/reports", params={"status": "in_progress"})
            assert [r["id"] for r in resp.json()] == [r1["id"]]

            resp = await c.get("/api/v1/admin/reports", params={"status": "open"})
            assert len(resp.json()) == 1
    finally:
        _clear_overrides()


async def test_admin_patch_unknown_report_404(db_session):
    await _seed_user(db_session, "admin@example.com")
    _install_overrides(db_session, email="admin@example.com", admin=True)
    try:
        async with _client() as c:
            resp = await c.patch(
                "/api/v1/admin/reports/nope",
                json={"status": "closed"},
            )
        assert resp.status_code == 404
    finally:
        _clear_overrides()


async def test_admin_patch_rejects_bad_status(db_session):
    await _seed_user(db_session, "admin@example.com")
    _install_overrides(db_session, email="admin@example.com", admin=True)
    try:
        async with _client() as c:
            resp = await c.patch(
                "/api/v1/admin/reports/nope",
                json={"status": "resolved"},
            )
        assert resp.status_code == 422
    finally:
        _clear_overrides()
