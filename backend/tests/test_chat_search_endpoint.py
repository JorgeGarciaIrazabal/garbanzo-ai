"""Integration tests for the conversation search endpoint.

Covers GET /api/v1/chat/conversations/search — validates auth, schema,
user isolation, pagination, and edge cases (empty query, no results,
special LIKE characters).
"""

from __future__ import annotations

import uuid

import pytest
from httpx import ASGITransport, AsyncClient

from app.core.config import Settings, get_settings
from app.core.security import create_access_token, hash_password
from app.db.session import get_db
from app.main import app
from app.models.conversation import Conversation
from app.models.message import Message
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


async def _seed_user(db, email: str) -> User:
    user = User(email=email, hashed_password=hash_password("pw"))
    db.add(user)
    await db.commit()
    await db.refresh(user)
    return user


async def _seed_conversation(
    db,
    user_email: str,
    title: str,
    messages: list[tuple[str, str]] | None = None,
) -> Conversation:
    conv = Conversation(
        id=str(uuid.uuid4()),
        user_id=user_email,
        title=title,
        model="llama3.2",
    )
    db.add(conv)
    await db.commit()

    for role, content in messages or []:
        db.add(
            Message(
                id=str(uuid.uuid4()),
                conversation_id=conv.id,
                role=role,
                content=content,
            )
        )
    await db.commit()
    await db.refresh(conv)
    return conv


def _install_overrides(db_session):
    async def _override_db():
        yield db_session

    app.dependency_overrides[get_db] = _override_db
    app.dependency_overrides[get_settings] = _override_settings


def _clear_overrides():
    app.dependency_overrides.pop(get_db, None)


USER_EMAIL = "test@example.com"


async def test_search_requires_auth(db_session):
    _install_overrides(db_session)
    try:
        transport = ASGITransport(app=app)
        async with AsyncClient(transport=transport, base_url="http://test") as client:
            resp = await client.get("/api/v1/chat/conversations/search", params={"q": "hi"})
        assert resp.status_code in (401, 403)
    finally:
        _clear_overrides()


async def test_search_empty_query_is_422(db_session):
    _install_overrides(db_session)
    try:
        transport = ASGITransport(app=app)
        async with AsyncClient(transport=transport, base_url="http://test") as client:
            resp = await client.get(
                "/api/v1/chat/conversations/search",
                params={"q": ""},
                headers={"Authorization": f"Bearer {_token(USER_EMAIL)}"},
            )
        assert resp.status_code == 422
    finally:
        _clear_overrides()


async def test_search_whitespace_query_is_422(db_session):
    _install_overrides(db_session)
    try:
        transport = ASGITransport(app=app)
        async with AsyncClient(transport=transport, base_url="http://test") as client:
            resp = await client.get(
                "/api/v1/chat/conversations/search",
                params={"q": "   "},
                headers={"Authorization": f"Bearer {_token(USER_EMAIL)}"},
            )
        assert resp.status_code == 422
    finally:
        _clear_overrides()


async def test_search_response_schema_matches_expected(db_session):
    await _seed_conversation(
        db_session,
        USER_EMAIL,
        title="Kubernetes deep dive",
        messages=[
            ("user", "explain kubernetes control plane"),
            ("assistant", "The control plane manages worker nodes."),
        ],
    )
    _install_overrides(db_session)
    try:
        transport = ASGITransport(app=app)
        async with AsyncClient(transport=transport, base_url="http://test") as client:
            resp = await client.get(
                "/api/v1/chat/conversations/search",
                params={"q": "kubernetes"},
                headers={"Authorization": f"Bearer {_token(USER_EMAIL)}"},
            )
        assert resp.status_code == 200
        body = resp.json()

        # Top-level schema.
        assert set(body.keys()) >= {"items", "total", "page", "page_size", "query"}
        assert body["query"] == "kubernetes"
        assert body["page"] == 1
        assert body["page_size"] == 20
        assert body["total"] == 1

        item = body["items"][0]
        assert set(item.keys()) == {"conversation", "matched_messages"}

        conv = item["conversation"]
        for field in ("id", "title", "model", "created_at", "updated_at"):
            assert field in conv

        # One message matched (only the user message contains "kubernetes").
        matched = item["matched_messages"]
        assert len(matched) == 1
        msg = matched[0]
        for field in ("id", "role", "content", "snippet", "created_at"):
            assert field in msg
        assert "kubernetes" in msg["content"].lower()
        assert "kubernetes" in msg["snippet"].lower()
    finally:
        _clear_overrides()


async def test_search_no_results(db_session):
    await _seed_conversation(db_session, USER_EMAIL, title="Greetings")
    _install_overrides(db_session)
    try:
        transport = ASGITransport(app=app)
        async with AsyncClient(transport=transport, base_url="http://test") as client:
            resp = await client.get(
                "/api/v1/chat/conversations/search",
                params={"q": "unmatched-string-xyz"},
                headers={"Authorization": f"Bearer {_token(USER_EMAIL)}"},
            )
        assert resp.status_code == 200
        body = resp.json()
        assert body["total"] == 0
        assert body["items"] == []
    finally:
        _clear_overrides()


async def test_search_isolates_users(db_session):
    # Another user whose data must not leak.
    await _seed_user(db_session, "intruder@example.com")
    await _seed_conversation(
        db_session,
        "intruder@example.com",
        title="Kubernetes secret",
        messages=[("user", "kubernetes is cool")],
    )
    # Current user has no matching conversation.
    await _seed_conversation(db_session, USER_EMAIL, title="Cooking recipes")

    _install_overrides(db_session)
    try:
        transport = ASGITransport(app=app)
        async with AsyncClient(transport=transport, base_url="http://test") as client:
            resp = await client.get(
                "/api/v1/chat/conversations/search",
                params={"q": "kubernetes"},
                headers={"Authorization": f"Bearer {_token(USER_EMAIL)}"},
            )
        assert resp.status_code == 200
        body = resp.json()
        assert body["total"] == 0
        assert body["items"] == []
    finally:
        _clear_overrides()


async def test_search_special_characters_treated_literally(db_session):
    await _seed_conversation(
        db_session,
        USER_EMAIL,
        title="Progress: 100% complete",
    )
    await _seed_conversation(
        db_session,
        USER_EMAIL,
        title="Unrelated title",
    )
    _install_overrides(db_session)
    try:
        transport = ASGITransport(app=app)
        async with AsyncClient(transport=transport, base_url="http://test") as client:
            resp = await client.get(
                "/api/v1/chat/conversations/search",
                params={"q": "100%"},
                headers={"Authorization": f"Bearer {_token(USER_EMAIL)}"},
            )
        assert resp.status_code == 200
        body = resp.json()
        assert body["total"] == 1
        assert "100%" in body["items"][0]["conversation"]["title"]
    finally:
        _clear_overrides()


async def test_search_pagination(db_session):
    for i in range(5):
        await _seed_conversation(db_session, USER_EMAIL, title=f"python topic {i}")

    _install_overrides(db_session)
    try:
        transport = ASGITransport(app=app)
        async with AsyncClient(transport=transport, base_url="http://test") as client:
            resp = await client.get(
                "/api/v1/chat/conversations/search",
                params={"q": "python", "page": 1, "page_size": 2},
                headers={"Authorization": f"Bearer {_token(USER_EMAIL)}"},
            )
        assert resp.status_code == 200
        body = resp.json()
        assert body["total"] == 5
        assert body["page"] == 1
        assert body["page_size"] == 2
        assert len(body["items"]) == 2

        async with AsyncClient(transport=transport, base_url="http://test") as client2:
            resp2 = await client2.get(
                "/api/v1/chat/conversations/search",
                params={"q": "python", "page": 3, "page_size": 2},
                headers={"Authorization": f"Bearer {_token(USER_EMAIL)}"},
            )
        assert resp2.status_code == 200
        body2 = resp2.json()
        assert len(body2["items"]) == 1
    finally:
        _clear_overrides()
