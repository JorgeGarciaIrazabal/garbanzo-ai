"""Integration tests for /api/v1/auth endpoints."""

import pytest
from httpx import ASGITransport, AsyncClient

from app.core.config import Settings, get_settings
from app.core.security import create_access_token, hash_password
from app.db.session import get_db
from app.main import app
from app.models.user import User

pytestmark = pytest.mark.asyncio


_TEST_SETTINGS = Settings(
    secret_key="test-secret-key-do-not-use-in-prod",
    database_url="sqlite+aiosqlite:///:memory:",
    access_token_expire_minutes=30,
)


def _install_overrides(db_session):
    async def _override_db():
        yield db_session

    app.dependency_overrides[get_db] = _override_db
    app.dependency_overrides[get_settings] = lambda: _TEST_SETTINGS


def _clear_overrides():
    app.dependency_overrides.pop(get_db, None)


async def _client():
    return AsyncClient(transport=ASGITransport(app=app), base_url="http://test")


class TestRegister:
    async def test_register_new_user(self, db_session):
        _install_overrides(db_session)
        try:
            async with await _client() as c:
                resp = await c.post(
                    "/api/v1/auth/register",
                    json={
                        "email": "alice@example.com",
                        "password": "password123",
                        "full_name": "Alice",
                    },
                )
            assert resp.status_code == 201
            body = resp.json()
            assert body["email"] == "alice@example.com"
            assert body["full_name"] == "Alice"
        finally:
            _clear_overrides()

    async def test_register_existing_email_400(self, db_session):
        # test@example.com is seeded by the fixture.
        _install_overrides(db_session)
        try:
            async with await _client() as c:
                resp = await c.post(
                    "/api/v1/auth/register",
                    json={"email": "test@example.com", "password": "password123"},
                )
            assert resp.status_code == 400
        finally:
            _clear_overrides()

    async def test_register_normalizes_email(self, db_session):
        _install_overrides(db_session)
        try:
            async with await _client() as c:
                resp = await c.post(
                    "/api/v1/auth/register",
                    json={"email": "MixedCase@Example.com", "password": "password123"},
                )
            assert resp.status_code == 201
            assert resp.json()["email"] == "mixedcase@example.com"
        finally:
            _clear_overrides()


class TestLogin:
    async def test_login_success(self, db_session):
        _install_overrides(db_session)
        try:
            async with await _client() as c:
                resp = await c.post(
                    "/api/v1/auth/login",
                    json={"email": "test@example.com", "password": "password123"},
                )
            assert resp.status_code == 200
            assert "access_token" in resp.json()
        finally:
            _clear_overrides()

    async def test_login_wrong_password_401(self, db_session):
        _install_overrides(db_session)
        try:
            async with await _client() as c:
                resp = await c.post(
                    "/api/v1/auth/login",
                    json={"email": "test@example.com", "password": "wrong"},
                )
            assert resp.status_code == 401
        finally:
            _clear_overrides()

    async def test_login_missing_user_401(self, db_session):
        _install_overrides(db_session)
        try:
            async with await _client() as c:
                resp = await c.post(
                    "/api/v1/auth/login",
                    json={"email": "ghost@example.com", "password": "pw"},
                )
            assert resp.status_code == 401
        finally:
            _clear_overrides()

    async def test_login_disabled_user_403(self, db_session):
        db_session.add(
            User(
                email="banned@example.com",
                hashed_password=hash_password("pw"),
                is_disabled=True,
            )
        )
        await db_session.commit()

        _install_overrides(db_session)
        try:
            async with await _client() as c:
                resp = await c.post(
                    "/api/v1/auth/login",
                    json={"email": "banned@example.com", "password": "pw"},
                )
            assert resp.status_code == 403
        finally:
            _clear_overrides()


class TestMe:
    async def test_me_returns_user(self, db_session):
        _install_overrides(db_session)
        from app.core.security import get_current_user

        async def _override_user():
            return {"email": "test@example.com", "token_payload": {}}

        app.dependency_overrides[get_current_user] = _override_user
        try:
            async with await _client() as c:
                token = create_access_token(
                    {"sub": "test@example.com"}, _TEST_SETTINGS
                )
                resp = await c.get(
                    "/api/v1/auth/me",
                    headers={"Authorization": f"Bearer {token}"},
                )
            assert resp.status_code == 200
            assert resp.json()["email"] == "test@example.com"
        finally:
            app.dependency_overrides.pop(get_current_user, None)
            _clear_overrides()

    async def test_me_unauthenticated_rejected(self, db_session):
        _install_overrides(db_session)
        try:
            async with await _client() as c:
                resp = await c.get("/api/v1/auth/me")
            # HTTPBearer raises 403 when the Authorization header is missing.
            assert resp.status_code in (401, 403)
        finally:
            _clear_overrides()
