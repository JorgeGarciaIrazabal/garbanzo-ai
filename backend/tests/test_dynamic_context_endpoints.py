"""Focused API coverage for primary chat, topics, and active context."""

import asyncio
import uuid

import pytest
from httpx import ASGITransport, AsyncClient
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import (
    AsyncSession,
    async_sessionmaker,
    create_async_engine,
)

from app.core.config import Settings, get_settings
from app.core.security import get_current_user, hash_password
from app.db.base import Base
from app.db.session import get_db
from app.main import app
from app.models.conversation import Conversation
from app.models.message import Message
from app.models.user import User
from app.services.conversation_service import ConversationService
from app.topics.models import Topic, TopicAssertion

pytestmark = pytest.mark.asyncio

OWNER = "test@example.com"
OTHER = "other@example.com"
_TEST_SETTINGS = Settings(
    secret_key="test-secret-key-do-not-use-in-prod",
    database_url="sqlite+aiosqlite:///:memory:",
    access_token_expire_minutes=30,
)


class _UserSwitch:
    def __init__(self, email: str = OWNER):
        self.email = email

    async def __call__(self):
        return {"email": self.email, "token_payload": {}}


def _install_overrides(db: AsyncSession, user: _UserSwitch) -> None:
    async def _override_db():
        yield db

    app.dependency_overrides[get_db] = _override_db
    app.dependency_overrides[get_settings] = lambda: _TEST_SETTINGS
    app.dependency_overrides[get_current_user] = user


def _clear_overrides() -> None:
    for dependency in (get_db, get_settings, get_current_user):
        app.dependency_overrides.pop(dependency, None)


def _client() -> AsyncClient:
    return AsyncClient(transport=ASGITransport(app=app), base_url="http://test")


async def _ensure_primary(client: AsyncClient) -> dict:
    response = await client.post("/api/v1/chat/conversations/primary")
    assert response.status_code == 200, response.text
    return response.json()


async def _legacy_conversation(db: AsyncSession, user_id: str = OWNER) -> Conversation:
    conversation = Conversation(
        id=str(uuid.uuid4()),
        user_id=user_id,
        title="Legacy thread",
        model="test-model",
    )
    db.add(conversation)
    await db.commit()
    return conversation


async def test_primary_ensure_is_idempotent_and_threads_exclude_it(db_session: AsyncSession):
    switch = _UserSwitch()
    _install_overrides(db_session, switch)
    try:
        async with _client() as client:
            first = await _ensure_primary(client)
            second = await _ensure_primary(client)
            legacy = await _legacy_conversation(db_session)
            threads = await client.get("/api/v1/chat/conversations", params={"kind": "thread"})
            primary = await client.get("/api/v1/chat/conversations", params={"kind": "primary"})
        assert first["id"] == second["id"]
        assert first["is_primary"] is True
        assert [item["id"] for item in threads.json()["items"]] == [legacy.id]
        assert [item["id"] for item in primary.json()["items"]] == [first["id"]]
    finally:
        _clear_overrides()


async def test_concurrent_primary_ensure_creates_exactly_one_row(tmp_path):
    """Independent request sessions converge on the database uniqueness authority."""
    engine = create_async_engine(
        f"sqlite+aiosqlite:///{tmp_path / 'primary-race.db'}",
        connect_args={"timeout": 5},
    )
    async with engine.begin() as connection:
        await connection.run_sync(Base.metadata.create_all)
    session_maker = async_sessionmaker(
        engine,
        class_=AsyncSession,
        expire_on_commit=False,
        autoflush=False,
    )
    async with session_maker() as seed_session:
        seed_session.add(User(email=OWNER, hashed_password=hash_password("pw")))
        await seed_session.commit()

    async def ensure() -> str:
        async with session_maker() as session:
            primary = await ConversationService(session).get_or_create_primary(OWNER)
            return primary.id

    try:
        primary_ids = await asyncio.gather(ensure(), ensure())
        async with session_maker() as verification_session:
            count = await verification_session.scalar(
                select(func.count(Conversation.id)).where(
                    Conversation.user_id == OWNER,
                    Conversation.is_primary.is_(True),
                    Conversation.is_deleted.is_(False),
                )
            )
        assert primary_ids[0] == primary_ids[1]
        assert count == 1
    finally:
        await engine.dispose()


async def test_topic_activation_requires_primary_and_creates_manual_topic(db_session: AsyncSession):
    switch = _UserSwitch()
    _install_overrides(db_session, switch)
    try:
        async with _client() as client:
            legacy = await _legacy_conversation(db_session)
            rejected = await client.post(
                f"/api/v1/chat/conversations/{legacy.id}/topics/activate",
                json={"label": "Retirement planning"},
            )
            primary = await _ensure_primary(client)
            activated = await client.post(
                f"/api/v1/chat/conversations/{primary['id']}/topics/activate",
                json={"label": "Retirement planning"},
            )
            topics = await client.get("/api/v1/chat/topics", params={"mode": "personal"})
        assert rejected.status_code == 409
        assert activated.status_code == 200, activated.text
        body = activated.json()
        assert body["topic"]["label"] == "Retirement planning"
        assert body["topic_is_pinned"] is True
        assert body["context_version"] == 1
        assert topics.json()["mode"] == "personal"
        assert [topic["label"] for topic in topics.json()["topics"]] == ["Retirement planning"]
    finally:
        _clear_overrides()


async def test_active_context_rejects_cross_user_source_and_stale_mutation(
    db_session: AsyncSession,
):
    switch = _UserSwitch()
    _install_overrides(db_session, switch)
    try:
        db_session.add(User(email=OTHER, hashed_password=hash_password("pw")))
        await db_session.commit()
        other_conversation = await _legacy_conversation(db_session, OTHER)
        other_message = Message(
            id=str(uuid.uuid4()),
            conversation_id=other_conversation.id,
            role="user",
            content="Private other-user context",
        )
        db_session.add(other_message)
        await db_session.commit()

        async with _client() as client:
            primary = await _ensure_primary(client)
            cross_user = await client.post(
                f"/api/v1/chat/conversations/{primary['id']}/context/items",
                json={
                    "source_type": "message",
                    "source_id": other_message.id,
                    "context_version": 0,
                },
            )
            owner_message = Message(
                id=str(uuid.uuid4()),
                conversation_id=(await _legacy_conversation(db_session)).id,
                role="user",
                content="Owner context source",
            )
            db_session.add(owner_message)
            await db_session.commit()
            added = await client.post(
                f"/api/v1/chat/conversations/{primary['id']}/context/items",
                json={
                    "source_type": "message",
                    "source_id": owner_message.id,
                    "context_version": 0,
                },
            )
            stale = await client.patch(
                f"/api/v1/chat/conversations/{primary['id']}/context/items/"
                f"{added.json()['item']['id']}",
                json={"state": "excluded", "context_version": 0},
            )
        assert cross_user.status_code == 404
        assert added.status_code == 201, added.text
        assert added.json()["context_version"] == 1
        assert stale.status_code == 409
        assert stale.json()["detail"] == {
            "code": "context_version_conflict",
            "current_context_version": 1,
        }
    finally:
        _clear_overrides()


async def test_fresh_start_keeps_messages_and_requested_pins(db_session: AsyncSession):
    switch = _UserSwitch()
    _install_overrides(db_session, switch)
    try:
        async with _client() as client:
            primary = await _ensure_primary(client)
            legacy = await _legacy_conversation(db_session)
            source = Message(
                id=str(uuid.uuid4()),
                conversation_id=legacy.id,
                role="user",
                content="Keep this source message in history.",
            )
            db_session.add(source)
            await db_session.commit()
            added = await client.post(
                f"/api/v1/chat/conversations/{primary['id']}/context/items",
                json={
                    "source_type": "message",
                    "source_id": source.id,
                    "state": "pinned",
                    "context_version": 0,
                },
            )
            fresh = await client.post(
                f"/api/v1/chat/conversations/{primary['id']}/context/fresh-start",
                json={"keep_pins": True, "context_version": 1},
            )
            context = await client.get(f"/api/v1/chat/conversations/{primary['id']}/context")
            message_still_exists = await db_session.get(Message, source.id)
        assert added.status_code == 201, added.text
        assert fresh.status_code == 200, fresh.text
        assert fresh.json()["context_version"] == 2
        assert message_still_exists is not None
        assert [item["id"] for item in context.json()["pinned_items"]] == [
            added.json()["item"]["id"]
        ]
        assert context.json()["topic"] is None
    finally:
        _clear_overrides()


async def test_create_thread_with_active_topic(db_session: AsyncSession):
    switch = _UserSwitch()
    _install_overrides(db_session, switch)
    try:
        topic = Topic(
            id="topic-retirement",
            user_id=OWNER,
            label="Retirement planning",
            normalized_label="retirement planning",
            status="active",
        )
        db_session.add(topic)
        assertion = TopicAssertion(
            id="assert-401k",
            topic_id=topic.id,
            content="Maxing out 401(k) match is priority.",
            normalized_key="401k-match",
            authority="user",
            kind="preference",
            status="active",
        )
        db_session.add(assertion)
        await db_session.commit()

        async with _client() as client:
            resp = await client.post(
                "/api/v1/chat/conversations",
                json={
                    "active_topic_id": topic.id,
                },
            )
            assert resp.status_code == 201, resp.text
            conv = resp.json()
            assert conv["title"] == "Retirement planning"
            assert conv["active_topic_id"] == topic.id
            assert conv["is_primary"] is False
            assert conv["message_count"] == 1

            detail = await client.get(f"/api/v1/chat/conversations/{conv['id']}")
            assert detail.status_code == 200, detail.text
            detail_data = detail.json()
            assert len(detail_data["messages"]) == 1
            first_msg = detail_data["messages"][0]
            assert first_msg["role"] == "assistant"
            assert "Retirement planning" in first_msg["content"]
            assert "Maxing out 401(k) match is priority" in first_msg["content"]
    finally:
        _clear_overrides()
