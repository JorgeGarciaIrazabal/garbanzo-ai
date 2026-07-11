"""Integration tests for /api/v1/auth endpoints."""

import pytest
from httpx import ASGITransport, AsyncClient

from app.core.config import Settings, get_settings
from app.core.security import create_access_token, create_refresh_token, hash_password
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
    async def test_register_is_disabled(self, db_session):
        """Public registration is disabled — this is a private app."""
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
            assert resp.status_code == 403
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
            body = resp.json()
            assert "access_token" in body
            assert body.get("refresh_token")
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


class TestUpdateProfile:
    """PATCH /auth/me — partial updates including email cascade."""

    async def _setup(self, db_session):
        from app.core.security import get_current_user

        _install_overrides(db_session)

        async def _override_user():
            return {"email": "test@example.com", "token_payload": {}}

        app.dependency_overrides[get_current_user] = _override_user

    def _teardown(self):
        from app.core.security import get_current_user

        app.dependency_overrides.pop(get_current_user, None)
        _clear_overrides()

    async def test_update_full_name(self, db_session):
        await self._setup(db_session)
        try:
            async with await _client() as c:
                resp = await c.patch(
                    "/api/v1/auth/me",
                    json={"full_name": "New Name"},
                    headers={"Authorization": "Bearer x"},
                )
            assert resp.status_code == 200, resp.text
            assert resp.json()["full_name"] == "New Name"
        finally:
            self._teardown()

    async def test_update_default_model(self, db_session):
        await self._setup(db_session)
        try:
            async with await _client() as c:
                resp = await c.patch(
                    "/api/v1/auth/me",
                    json={"default_model": "gpt-4o"},
                    headers={"Authorization": "Bearer x"},
                )
            assert resp.status_code == 200
            assert resp.json()["default_model"] == "gpt-4o"
        finally:
            self._teardown()

    async def test_clear_default_model(self, db_session):
        """Passing null explicitly clears the stored default."""
        user = (
            await db_session.execute(
                __import__("sqlalchemy").select(User).where(
                    User.email == "test@example.com"
                )
            )
        ).scalar_one()
        user.default_model = "llama3.2"
        await db_session.commit()

        await self._setup(db_session)
        try:
            async with await _client() as c:
                resp = await c.patch(
                    "/api/v1/auth/me",
                    json={"default_model": None},
                    headers={"Authorization": "Bearer x"},
                )
            assert resp.status_code == 200
            assert resp.json()["default_model"] is None
        finally:
            self._teardown()

    async def test_update_email_rejects_duplicate(self, db_session):
        db_session.add(
            User(
                email="taken@example.com",
                hashed_password=hash_password("pw"),
            )
        )
        await db_session.commit()

        await self._setup(db_session)
        try:
            async with await _client() as c:
                resp = await c.patch(
                    "/api/v1/auth/me",
                    json={"email": "taken@example.com"},
                    headers={"Authorization": "Bearer x"},
                )
            assert resp.status_code == 400
        finally:
            self._teardown()


class TestChangePassword:
    async def _setup(self, db_session):
        from app.core.security import get_current_user

        _install_overrides(db_session)

        async def _override_user():
            return {"email": "test@example.com", "token_payload": {}}

        app.dependency_overrides[get_current_user] = _override_user

    def _teardown(self):
        from app.core.security import get_current_user

        app.dependency_overrides.pop(get_current_user, None)
        _clear_overrides()

    async def test_change_password_success(self, db_session):
        await self._setup(db_session)
        try:
            async with await _client() as c:
                resp = await c.post(
                    "/api/v1/auth/me/password",
                    json={
                        "current_password": "password123",
                        "new_password": "newpassword123",
                    },
                    headers={"Authorization": "Bearer x"},
                )
            assert resp.status_code == 204
        finally:
            self._teardown()

    async def test_change_password_wrong_current(self, db_session):
        await self._setup(db_session)
        try:
            async with await _client() as c:
                resp = await c.post(
                    "/api/v1/auth/me/password",
                    json={
                        "current_password": "wrong",
                        "new_password": "newpassword123",
                    },
                    headers={"Authorization": "Bearer x"},
                )
            assert resp.status_code == 401
        finally:
            self._teardown()


class TestRefresh:
    async def test_refresh_issues_new_tokens(self, db_session):
        _install_overrides(db_session)
        try:
            refresh_token = create_refresh_token(
                {"sub": "test@example.com"}, _TEST_SETTINGS
            )
            async with await _client() as c:
                resp = await c.post(
                    "/api/v1/auth/refresh",
                    json={"refresh_token": refresh_token},
                )
            assert resp.status_code == 200, resp.text
            body = resp.json()
            assert body["access_token"]
            assert body["refresh_token"]
            # Rotation — new refresh token should differ from the one we sent.
            assert body["refresh_token"] != refresh_token
        finally:
            _clear_overrides()

    async def test_refresh_rejects_access_token(self, db_session):
        """An access token is not a refresh token — /refresh must reject it."""
        _install_overrides(db_session)
        try:
            access_token = create_access_token(
                {"sub": "test@example.com"}, _TEST_SETTINGS
            )
            async with await _client() as c:
                resp = await c.post(
                    "/api/v1/auth/refresh",
                    json={"refresh_token": access_token},
                )
            assert resp.status_code == 401
        finally:
            _clear_overrides()

    async def test_refresh_rejects_garbage(self, db_session):
        _install_overrides(db_session)
        try:
            async with await _client() as c:
                resp = await c.post(
                    "/api/v1/auth/refresh",
                    json={"refresh_token": "not-a-real-token"},
                )
            assert resp.status_code == 401
        finally:
            _clear_overrides()

    async def test_refresh_rejects_unknown_user(self, db_session):
        _install_overrides(db_session)
        try:
            refresh_token = create_refresh_token(
                {"sub": "ghost@example.com"}, _TEST_SETTINGS
            )
            async with await _client() as c:
                resp = await c.post(
                    "/api/v1/auth/refresh",
                    json={"refresh_token": refresh_token},
                )
            assert resp.status_code == 401
        finally:
            _clear_overrides()

    async def test_refresh_rejects_disabled_user(self, db_session):
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
            refresh_token = create_refresh_token(
                {"sub": "banned@example.com"}, _TEST_SETTINGS
            )
            async with await _client() as c:
                resp = await c.post(
                    "/api/v1/auth/refresh",
                    json={"refresh_token": refresh_token},
                )
            assert resp.status_code == 401
        finally:
            _clear_overrides()

    async def test_access_token_cannot_impersonate_refresh_on_protected_route(
        self, db_session
    ):
        """A refresh token must not authenticate protected API endpoints."""
        _install_overrides(db_session)
        try:
            refresh_token = create_refresh_token(
                {"sub": "test@example.com"}, _TEST_SETTINGS
            )
            async with await _client() as c:
                resp = await c.get(
                    "/api/v1/auth/me",
                    headers={"Authorization": f"Bearer {refresh_token}"},
                )
            assert resp.status_code == 401
        finally:
            _clear_overrides()
