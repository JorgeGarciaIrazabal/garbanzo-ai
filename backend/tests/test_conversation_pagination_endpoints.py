"""Endpoint tests for windowed message loading (B-03).

Mirrors ``test_conversation_mute.py``'s override/client scaffolding.
"""

from datetime import UTC, datetime

import pytest
from httpx import ASGITransport, AsyncClient

from app.core.config import Settings, get_settings
from app.core.security import get_current_user
from app.db.session import get_db
from app.main import app
from app.models.message import Message

_TEST_SETTINGS = Settings(
    secret_key="test-secret-key-do-not-use-in-prod",
    database_url="sqlite+aiosqlite:///:memory:",
    access_token_expire_minutes=30,
)

OWNER = "test@example.com"  # seeded by conftest
SAME_INSTANT = datetime(2026, 1, 1, tzinfo=UTC)


class _UserSwitch:
    def __init__(self, email: str = OWNER):
        self.email = email

    async def __call__(self):
        return {"email": self.email, "token_payload": {}}


def _install_overrides(db_session, switch: _UserSwitch):
    async def _override_db():
        yield db_session

    app.dependency_overrides[get_db] = _override_db
    app.dependency_overrides[get_settings] = lambda: _TEST_SETTINGS
    app.dependency_overrides[get_current_user] = switch


def _clear_overrides():
    app.dependency_overrides.pop(get_db, None)
    app.dependency_overrides.pop(get_settings, None)
    app.dependency_overrides.pop(get_current_user, None)


def _client() -> AsyncClient:
    return AsyncClient(transport=ASGITransport(app=app), base_url="http://test")


async def _create_conversation(client: AsyncClient, **overrides) -> dict:
    payload = {"title": "Long chat", **overrides}
    resp = await client.post("/api/v1/chat/conversations", json=payload)
    assert resp.status_code == 201, resp.text
    return resp.json()


async def _seed_messages(db_session, conversation_id: str, count: int):
    for i in range(count):
        db_session.add(
            Message(
                id=f"m{i}",
                conversation_id=conversation_id,
                role="user" if i % 2 == 0 else "assistant",
                content=f"message {i}",
                created_at=SAME_INSTANT,
                seq=i,
            )
        )
    await db_session.commit()


@pytest.mark.asyncio
async def test_message_limit_returns_only_the_recent_window(db_session):
    switch = _UserSwitch()
    _install_overrides(db_session, switch)
    try:
        async with _client() as c:
            conv = await _create_conversation(c)
            await _seed_messages(db_session, conv["id"], 10)

            resp = await c.get(
                f"/api/v1/chat/conversations/{conv['id']}",
                params={"message_limit": 3},
            )
        assert resp.status_code == 200
        body = resp.json()
        assert [m["content"] for m in body["messages"]] == [
            "message 7",
            "message 8",
            "message 9",
        ]
        assert body["has_more_messages"] is True
        assert body["message_count"] == 10
    finally:
        _clear_overrides()


@pytest.mark.asyncio
async def test_omitting_message_limit_returns_everything_unchanged(db_session):
    switch = _UserSwitch()
    _install_overrides(db_session, switch)
    try:
        async with _client() as c:
            conv = await _create_conversation(c)
            await _seed_messages(db_session, conv["id"], 10)

            resp = await c.get(f"/api/v1/chat/conversations/{conv['id']}")
        assert resp.status_code == 200
        body = resp.json()
        assert len(body["messages"]) == 10
        assert body["has_more_messages"] is False
    finally:
        _clear_overrides()


@pytest.mark.asyncio
async def test_messages_before_pages_in_older_messages(db_session):
    switch = _UserSwitch()
    _install_overrides(db_session, switch)
    try:
        async with _client() as c:
            conv = await _create_conversation(c)
            await _seed_messages(db_session, conv["id"], 10)

            resp = await c.get(
                f"/api/v1/chat/conversations/{conv['id']}/messages",
                params={"before": "m7", "limit": 3},
            )
        assert resp.status_code == 200
        body = resp.json()
        assert [m["content"] for m in body["messages"]] == [
            "message 4",
            "message 5",
            "message 6",
        ]
        assert body["has_more"] is True
    finally:
        _clear_overrides()


@pytest.mark.asyncio
async def test_messages_before_404s_for_missing_conversation(db_session):
    switch = _UserSwitch()
    _install_overrides(db_session, switch)
    try:
        async with _client() as c:
            resp = await c.get(
                "/api/v1/chat/conversations/does-not-exist/messages",
                params={"before": "m0"},
            )
        assert resp.status_code == 404
    finally:
        _clear_overrides()
