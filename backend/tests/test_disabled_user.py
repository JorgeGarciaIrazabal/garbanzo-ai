"""Login is rejected when the user is disabled."""

import pytest
from httpx import ASGITransport, AsyncClient

from app.core.config import Settings, get_settings
from app.core.security import hash_password
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


async def test_disabled_user_cannot_login(db_session):
    # Seed a disabled user.
    disabled = User(
        email="blocked@example.com",
        hashed_password=hash_password("letmein"),
        is_disabled=True,
    )
    db_session.add(disabled)
    await db_session.commit()

    async def _override_db():
        yield db_session

    app.dependency_overrides[get_db] = _override_db
    app.dependency_overrides[get_settings] = _override_settings
    try:
        transport = ASGITransport(app=app)
        async with AsyncClient(transport=transport, base_url="http://test") as client:
            resp = await client.post(
                "/api/v1/auth/login",
                json={"email": "blocked@example.com", "password": "letmein"},
            )
        assert resp.status_code == 403
        assert "disabled" in resp.json()["detail"].lower()
    finally:
        app.dependency_overrides.pop(get_db, None)


async def test_active_user_can_still_login(db_session):
    active = User(
        email="active@example.com",
        hashed_password=hash_password("letmein"),
        is_disabled=False,
    )
    db_session.add(active)
    await db_session.commit()

    async def _override_db():
        yield db_session

    app.dependency_overrides[get_db] = _override_db
    app.dependency_overrides[get_settings] = _override_settings
    try:
        transport = ASGITransport(app=app)
        async with AsyncClient(transport=transport, base_url="http://test") as client:
            resp = await client.post(
                "/api/v1/auth/login",
                json={"email": "active@example.com", "password": "letmein"},
            )
        assert resp.status_code == 200
        assert "access_token" in resp.json()
    finally:
        app.dependency_overrides.pop(get_db, None)
