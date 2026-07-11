"""Integration tests for the /api/v1/usage endpoints."""

import uuid
from datetime import UTC, datetime, timedelta

import pytest
from httpx import ASGITransport, AsyncClient

from app.core.config import Settings, get_settings
from app.core.security import get_current_user
from app.db.session import get_db
from app.main import app
from app.models.conversation import Conversation
from app.models.message import Message

pytestmark = pytest.mark.asyncio


_TEST_SETTINGS = Settings(
    secret_key="test-secret-key-do-not-use-in-prod",
    database_url="sqlite+aiosqlite:///:memory:",
    access_token_expire_minutes=30,
)


def _install(db_session):
    async def _override_db():
        yield db_session

    async def _override_user():
        return {"email": "test@example.com", "token_payload": {}}

    app.dependency_overrides[get_db] = _override_db
    app.dependency_overrides[get_settings] = lambda: _TEST_SETTINGS
    app.dependency_overrides[get_current_user] = _override_user


def _clear():
    app.dependency_overrides.pop(get_db, None)
    app.dependency_overrides.pop(get_settings, None)
    app.dependency_overrides.pop(get_current_user, None)


async def _seed(db_session):
    conv_a = Conversation(
        id=str(uuid.uuid4()),
        user_id="test@example.com",
        title="Conversation A",
        model="llama3.2",
    )
    conv_b = Conversation(
        id=str(uuid.uuid4()),
        user_id="test@example.com",
        title="Conversation B",
        model="gpt-4o",
    )
    db_session.add_all([conv_a, conv_b])
    await db_session.flush()

    now = datetime.now(UTC)
    db_session.add_all(
        [
            Message(
                id=str(uuid.uuid4()),
                conversation_id=conv_a.id,
                role="user",
                content="hi",
                created_at=now,
            ),
            Message(
                id=str(uuid.uuid4()),
                conversation_id=conv_a.id,
                role="assistant",
                content="hello",
                meta={"tokens_prompt": 10, "tokens_generated": 20},
                created_at=now,
            ),
            Message(
                id=str(uuid.uuid4()),
                conversation_id=conv_a.id,
                role="assistant",
                content="again",
                meta={"tokens_prompt": 5, "tokens_generated": 15},
                created_at=now - timedelta(days=1),
            ),
            Message(
                id=str(uuid.uuid4()),
                conversation_id=conv_b.id,
                role="assistant",
                content="hi from b",
                meta={"tokens_prompt": 50, "tokens_generated": 100},
                created_at=now,
            ),
            # Out-of-window message (should be excluded when days=7)
            Message(
                id=str(uuid.uuid4()),
                conversation_id=conv_b.id,
                role="assistant",
                content="ancient",
                meta={"tokens_prompt": 999, "tokens_generated": 999},
                created_at=now - timedelta(days=60),
            ),
        ]
    )
    await db_session.commit()
    return conv_a, conv_b


async def test_usage_summary_totals(db_session):
    await _seed(db_session)
    _install(db_session)
    try:
        async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as c:
            resp = await c.get(
                "/api/v1/usage/summary?days=7",
                headers={"Authorization": "Bearer x"},
            )
        assert resp.status_code == 200, resp.text
        body = resp.json()
        assert body["total_tokens_prompt"] == 65  # 10 + 5 + 50
        assert body["total_tokens_generated"] == 135  # 20 + 15 + 100
        assert body["total_messages"] == 3
        # Out-of-window message not counted
        assert body["total_tokens_prompt"] != 65 + 999
    finally:
        _clear()


async def test_usage_summary_by_model(db_session):
    await _seed(db_session)
    _install(db_session)
    try:
        async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as c:
            resp = await c.get(
                "/api/v1/usage/summary?days=7",
                headers={"Authorization": "Bearer x"},
            )
        body = resp.json()
        by_model = {row["model"]: row for row in body["by_model"]}
        assert by_model["llama3.2"]["tokens_prompt"] == 15
        assert by_model["llama3.2"]["tokens_generated"] == 35
        assert by_model["gpt-4o"]["tokens_generated"] == 100
    finally:
        _clear()


async def test_usage_summary_by_day(db_session):
    await _seed(db_session)
    _install(db_session)
    try:
        async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as c:
            resp = await c.get(
                "/api/v1/usage/summary?days=7",
                headers={"Authorization": "Bearer x"},
            )
        body = resp.json()
        # Today + yesterday => 2 buckets
        assert len(body["by_day"]) >= 2
        total = sum(d["tokens_generated"] for d in body["by_day"])
        assert total == 135
    finally:
        _clear()


async def test_usage_summary_empty_for_new_user(db_session):
    _install(db_session)
    try:
        async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as c:
            resp = await c.get(
                "/api/v1/usage/summary",
                headers={"Authorization": "Bearer x"},
            )
        body = resp.json()
        assert body["total_tokens_prompt"] == 0
        assert body["total_tokens_generated"] == 0
        assert body["by_model"] == []
        assert body["by_day"] == []
    finally:
        _clear()
