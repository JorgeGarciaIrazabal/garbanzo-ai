"""Integration tests for /api/v1/memories endpoints."""

import pytest
from httpx import ASGITransport, AsyncClient

from app.core.config import Settings, get_settings
from app.core.security import get_current_user
from app.db.session import get_db
from app.main import app
from app.services.memory_service import MemoryService

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


async def test_create_memory(db_session):
    _install_overrides(db_session)
    try:
        async with await _client() as c:
            resp = await c.post(
                "/api/v1/memories",
                json={"content": "User loves Python"},
            )
        assert resp.status_code == 201
        body = resp.json()
        assert body["content"] == "User loves Python"
        assert body["is_active"] is True
    finally:
        _clear_overrides()


async def test_list_memories(db_session):
    svc = MemoryService(db_session)
    await svc.create_memory(user_id="test@example.com", content="m1")
    await svc.create_memory(user_id="test@example.com", content="m2")

    _install_overrides(db_session)
    try:
        async with await _client() as c:
            resp = await c.get("/api/v1/memories")
        assert resp.status_code == 200
        contents = {m["content"] for m in resp.json()}
        assert contents == {"m1", "m2"}
    finally:
        _clear_overrides()


async def test_get_memory(db_session):
    svc = MemoryService(db_session)
    m = await svc.create_memory(user_id="test@example.com", content="x")

    _install_overrides(db_session)
    try:
        async with await _client() as c:
            resp = await c.get(f"/api/v1/memories/{m.id}")
        assert resp.status_code == 200
        assert resp.json()["id"] == m.id
    finally:
        _clear_overrides()


async def test_get_missing_404(db_session):
    _install_overrides(db_session)
    try:
        async with await _client() as c:
            resp = await c.get("/api/v1/memories/missing")
        assert resp.status_code == 404
    finally:
        _clear_overrides()


async def test_update_memory(db_session):
    svc = MemoryService(db_session)
    m = await svc.create_memory(user_id="test@example.com", content="old")

    _install_overrides(db_session)
    try:
        async with await _client() as c:
            resp = await c.patch(
                f"/api/v1/memories/{m.id}", json={"content": "new"}
            )
        assert resp.status_code == 200
        assert resp.json()["content"] == "new"
    finally:
        _clear_overrides()


async def test_update_missing_404(db_session):
    _install_overrides(db_session)
    try:
        async with await _client() as c:
            resp = await c.patch("/api/v1/memories/missing", json={"content": "x"})
        assert resp.status_code == 404
    finally:
        _clear_overrides()


async def test_delete_memory_soft_deactivates(db_session):
    svc = MemoryService(db_session)
    m = await svc.create_memory(user_id="test@example.com", content="x")

    _install_overrides(db_session)
    try:
        async with await _client() as c:
            resp = await c.delete(f"/api/v1/memories/{m.id}")
        assert resp.status_code == 204
        # Soft-deactivated, so not in active list.
        active = await svc.get_active_memories("test@example.com")
        assert active == []
    finally:
        _clear_overrides()


async def test_delete_missing_404(db_session):
    _install_overrides(db_session)
    try:
        async with await _client() as c:
            resp = await c.delete("/api/v1/memories/missing")
        assert resp.status_code == 404
    finally:
        _clear_overrides()


async def test_cross_user_isolation(db_session):
    from app.core.security import hash_password
    from app.models.user import User

    db_session.add(
        User(email="other@example.com", hashed_password=hash_password("x"))
    )
    await db_session.commit()

    svc = MemoryService(db_session)
    others_memory = await svc.create_memory(
        user_id="other@example.com", content="secret"
    )

    _install_overrides(db_session, email="test@example.com")
    try:
        async with await _client() as c:
            resp = await c.get(f"/api/v1/memories/{others_memory.id}")
        assert resp.status_code == 404
    finally:
        _clear_overrides()
