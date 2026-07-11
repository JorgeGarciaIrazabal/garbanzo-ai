"""Admin portal endpoint tests."""

import pytest
from httpx import ASGITransport, AsyncClient

from app.core.config import Settings, get_settings
from app.core.security import create_access_token, get_current_admin_user, hash_password
from app.db.session import get_db
from app.main import app
from app.models.user import User

pytestmark = pytest.mark.asyncio


_TEST_SETTINGS = Settings(
    secret_key="test-secret-key-do-not-use-in-prod",
    database_url="sqlite+aiosqlite:///:memory:",
    access_token_expire_minutes=30,
)


def _override_settings() -> Settings:
    return _TEST_SETTINGS


def _token(email: str) -> str:
    return create_access_token({"sub": email}, _TEST_SETTINGS)


async def _seed(db, email: str, *, is_admin: bool = False, is_disabled: bool = False) -> User:
    user = User(
        email=email,
        hashed_password=hash_password("pw"),
        is_admin=is_admin,
        is_disabled=is_disabled,
    )
    db.add(user)
    await db.commit()
    await db.refresh(user)
    return user


def _install_overrides(db_session, admin_email: str | None):
    """Override DB + admin-check dependencies to use the shared in-memory session."""

    async def _override_db():
        yield db_session

    app.dependency_overrides[get_db] = _override_db
    app.dependency_overrides[get_settings] = _override_settings

    if admin_email is not None:
        async def _override_admin():
            return {"email": admin_email, "token_payload": {"sub": admin_email}, "is_admin": True}

        app.dependency_overrides[get_current_admin_user] = _override_admin


def _clear_overrides():
    app.dependency_overrides.pop(get_db, None)
    app.dependency_overrides.pop(get_current_admin_user, None)
    # Note: intentionally do NOT pop get_settings — sibling test modules
    # (e.g. test_audio_endpoints) install a module-level override at import
    # time that is shared process-wide.


async def test_non_admin_gets_403(db_session):
    # Seed a non-admin user (test@example.com already seeded by fixture).
    _install_overrides(db_session, admin_email=None)  # don't override admin dep — let it run
    try:
        transport = ASGITransport(app=app)
        async with AsyncClient(transport=transport, base_url="http://test") as client:
            resp = await client.get(
                "/api/v1/admin/users",
                headers={"Authorization": f"Bearer {_token('test@example.com')}"},
            )
        # The real get_current_admin_user opens a NEW session via async_session_maker
        # which points at the configured DATABASE_URL (not our in-memory fixture), so
        # it won't find the user. Either way the expected result is 403.
        assert resp.status_code == 403
    finally:
        _clear_overrides()


async def test_admin_can_create_user(db_session):
    await _seed(db_session, "admin@example.com", is_admin=True)

    _install_overrides(db_session, admin_email="admin@example.com")
    try:
        transport = ASGITransport(app=app)
        async with AsyncClient(transport=transport, base_url="http://test") as client:
            resp = await client.post(
                "/api/v1/admin/users",
                headers={"Authorization": f"Bearer {_token('admin@example.com')}"},
                json={
                    "email": "newuser@example.com",
                    "password": "password123",
                    "full_name": "New User",
                },
            )
        assert resp.status_code == 201, resp.text
        body = resp.json()
        assert body["email"] == "newuser@example.com"
        assert body["full_name"] == "New User"
        assert body["is_admin"] is False
    finally:
        _clear_overrides()


async def test_admin_can_create_admin_user(db_session):
    await _seed(db_session, "admin@example.com", is_admin=True)

    _install_overrides(db_session, admin_email="admin@example.com")
    try:
        transport = ASGITransport(app=app)
        async with AsyncClient(transport=transport, base_url="http://test") as client:
            resp = await client.post(
                "/api/v1/admin/users",
                headers={"Authorization": f"Bearer {_token('admin@example.com')}"},
                json={
                    "email": "newadmin@example.com",
                    "password": "password123",
                    "is_admin": True,
                },
            )
        assert resp.status_code == 201
        assert resp.json()["is_admin"] is True
    finally:
        _clear_overrides()


async def test_admin_create_user_duplicate_400(db_session):
    await _seed(db_session, "admin@example.com", is_admin=True)
    await _seed(db_session, "existing@example.com")

    _install_overrides(db_session, admin_email="admin@example.com")
    try:
        transport = ASGITransport(app=app)
        async with AsyncClient(transport=transport, base_url="http://test") as client:
            resp = await client.post(
                "/api/v1/admin/users",
                headers={"Authorization": f"Bearer {_token('admin@example.com')}"},
                json={
                    "email": "existing@example.com",
                    "password": "password123",
                },
            )
        assert resp.status_code == 400
    finally:
        _clear_overrides()


async def test_admin_can_list_users(db_session):
    await _seed(db_session, "admin@example.com", is_admin=True)
    await _seed(db_session, "alice@example.com")

    _install_overrides(db_session, admin_email="admin@example.com")
    try:
        transport = ASGITransport(app=app)
        async with AsyncClient(transport=transport, base_url="http://test") as client:
            resp = await client.get(
                "/api/v1/admin/users",
                headers={"Authorization": f"Bearer {_token('admin@example.com')}"},
            )
        assert resp.status_code == 200
        emails = {u["email"] for u in resp.json()}
        assert "admin@example.com" in emails
        assert "alice@example.com" in emails
    finally:
        _clear_overrides()


async def test_admin_can_update_user_flags(db_session):
    await _seed(db_session, "admin@example.com", is_admin=True)
    await _seed(db_session, "victim@example.com")

    _install_overrides(db_session, admin_email="admin@example.com")
    try:
        transport = ASGITransport(app=app)
        async with AsyncClient(transport=transport, base_url="http://test") as client:
            resp = await client.patch(
                "/api/v1/admin/users/victim@example.com",
                headers={"Authorization": f"Bearer {_token('admin@example.com')}"},
                json={"is_disabled": True},
            )
        assert resp.status_code == 200
        assert resp.json()["is_disabled"] is True
    finally:
        _clear_overrides()


async def test_admin_cannot_demote_self(db_session):
    await _seed(db_session, "admin@example.com", is_admin=True)

    _install_overrides(db_session, admin_email="admin@example.com")
    try:
        transport = ASGITransport(app=app)
        async with AsyncClient(transport=transport, base_url="http://test") as client:
            resp = await client.patch(
                "/api/v1/admin/users/admin@example.com",
                headers={"Authorization": f"Bearer {_token('admin@example.com')}"},
                json={"is_admin": False},
            )
        assert resp.status_code == 400
    finally:
        _clear_overrides()


async def test_admin_cannot_disable_self(db_session):
    await _seed(db_session, "admin@example.com", is_admin=True)

    _install_overrides(db_session, admin_email="admin@example.com")
    try:
        transport = ASGITransport(app=app)
        async with AsyncClient(transport=transport, base_url="http://test") as client:
            resp = await client.patch(
                "/api/v1/admin/users/admin@example.com",
                headers={"Authorization": f"Bearer {_token('admin@example.com')}"},
                json={"is_disabled": True},
            )
        assert resp.status_code == 400
    finally:
        _clear_overrides()


async def test_admin_mcp_server_crud(db_session):
    await _seed(db_session, "admin@example.com", is_admin=True)

    _install_overrides(db_session, admin_email="admin@example.com")
    try:
        transport = ASGITransport(app=app)
        async with AsyncClient(transport=transport, base_url="http://test") as client:
            headers = {"Authorization": f"Bearer {_token('admin@example.com')}"}

            # Create
            resp = await client.post(
                "/api/v1/admin/mcp-servers",
                headers=headers,
                json={
                    "name": "filesystem",
                    "transport": "stdio",
                    "command": "npx",
                    "args": ["-y", "@modelcontextprotocol/server-filesystem", "/tmp"],
                    "enabled": True,
                },
            )
            assert resp.status_code == 201, resp.text
            server = resp.json()
            server_id = server["id"]
            assert server["name"] == "filesystem"
            assert server["transport"] == "stdio"

            # List
            resp = await client.get("/api/v1/admin/mcp-servers", headers=headers)
            assert resp.status_code == 200
            assert any(s["id"] == server_id for s in resp.json())

            # Update
            resp = await client.patch(
                f"/api/v1/admin/mcp-servers/{server_id}",
                headers=headers,
                json={"enabled": False, "description": "disabled in tests"},
            )
            assert resp.status_code == 200
            assert resp.json()["enabled"] is False
            assert resp.json()["description"] == "disabled in tests"

            # Delete
            resp = await client.delete(
                f"/api/v1/admin/mcp-servers/{server_id}",
                headers=headers,
            )
            assert resp.status_code == 204

            # Confirm gone
            resp = await client.get("/api/v1/admin/mcp-servers", headers=headers)
            assert all(s["id"] != server_id for s in resp.json())
    finally:
        _clear_overrides()
