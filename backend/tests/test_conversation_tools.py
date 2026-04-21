"""Tests for the per-conversation ``enabled_tools`` setting."""

import pytest
from httpx import ASGITransport, AsyncClient

from app.core.config import Settings, get_settings
from app.core.security import create_access_token
from app.db.session import get_db
from app.main import app
from app.services.conversation_service import ConversationService

pytestmark = pytest.mark.asyncio


_TEST_SETTINGS = Settings(
    secret_key="test-secret-key-do-not-use-in-prod",
    database_url="sqlite+aiosqlite:///:memory:",
    access_token_expire_minutes=30,
)


def _token(email: str) -> str:
    return create_access_token({"sub": email}, _TEST_SETTINGS)


def _install(db_session):
    async def _override_db():
        yield db_session

    app.dependency_overrides[get_db] = _override_db
    app.dependency_overrides[get_settings] = lambda: _TEST_SETTINGS


def _clear():
    app.dependency_overrides.pop(get_db, None)
    # Keep get_settings — sibling test modules install it at import time.


async def test_update_sets_subset(db_session, test_user_email):
    conv = await ConversationService(db_session).create(test_user_email, title="t")
    _install(db_session)
    try:
        transport = ASGITransport(app=app)
        async with AsyncClient(transport=transport, base_url="http://test") as client:
            resp = await client.patch(
                f"/api/v1/chat/conversations/{conv.id}",
                headers={"Authorization": f"Bearer {_token(test_user_email)}"},
                json={"enabled_tools": ["srv-1:foo", "srv-2:bar"]},
            )
        assert resp.status_code == 200
        assert resp.json()["enabled_tools"] == ["srv-1:foo", "srv-2:bar"]
    finally:
        _clear()


async def test_update_empty_list_means_none(db_session, test_user_email):
    conv = await ConversationService(db_session).create(test_user_email, title="t")
    _install(db_session)
    try:
        transport = ASGITransport(app=app)
        async with AsyncClient(transport=transport, base_url="http://test") as client:
            resp = await client.patch(
                f"/api/v1/chat/conversations/{conv.id}",
                headers={"Authorization": f"Bearer {_token(test_user_email)}"},
                json={"enabled_tools": []},
            )
        assert resp.status_code == 200
        assert resp.json()["enabled_tools"] == []
    finally:
        _clear()


async def test_update_null_clears_to_all(db_session, test_user_email):
    conv = await ConversationService(db_session).create(test_user_email, title="t")
    # Pre-populate with a subset.
    conv.enabled_tools = ["a:b"]
    await db_session.commit()

    _install(db_session)
    try:
        transport = ASGITransport(app=app)
        async with AsyncClient(transport=transport, base_url="http://test") as client:
            resp = await client.patch(
                f"/api/v1/chat/conversations/{conv.id}",
                headers={"Authorization": f"Bearer {_token(test_user_email)}"},
                json={"enabled_tools": None},
            )
        assert resp.status_code == 200
        assert resp.json()["enabled_tools"] is None
    finally:
        _clear()


async def test_update_omit_key_preserves_value(db_session, test_user_email):
    conv = await ConversationService(db_session).create(test_user_email, title="t")
    conv.enabled_tools = ["keep:me"]
    await db_session.commit()

    _install(db_session)
    try:
        transport = ASGITransport(app=app)
        async with AsyncClient(transport=transport, base_url="http://test") as client:
            resp = await client.patch(
                f"/api/v1/chat/conversations/{conv.id}",
                headers={"Authorization": f"Bearer {_token(test_user_email)}"},
                json={"title": "renamed"},
            )
        assert resp.status_code == 200
        assert resp.json()["enabled_tools"] == ["keep:me"]
    finally:
        _clear()
