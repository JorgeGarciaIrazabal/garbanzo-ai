"""End-to-end coverage for the topic switch endpoint and archives list."""

from __future__ import annotations

import uuid

import pytest
from httpx import ASGITransport, AsyncClient
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import Settings, get_settings
from app.core.security import get_current_user, hash_password
from app.db.session import get_db
from app.main import app
from app.models.conversation import Conversation
from app.models.message import Message
from app.models.user import User
from app.services.conversation_service import ConversationService
from app.topics.models import ActiveContextItem, Topic, TopicArchive, TopicRelation

pytestmark = pytest.mark.asyncio

OWNER = "test@example.com"
OTHER = "other@example.com"
_TEST_SETTINGS = Settings(
    secret_key="test-secret-key-do-not-use-in-prod",
    database_url="sqlite+aiosqlite:///:memory:",
    access_token_expire_minutes=30,
    topic_curator_provider="",
    topic_curator_model="",
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
    # Clear the lru_cache so direct get_settings() calls pick up test settings
    get_settings.cache_clear()


def _clear_overrides() -> None:
    for dependency in (get_db, get_settings, get_current_user):
        app.dependency_overrides.pop(dependency, None)


def _client() -> AsyncClient:
    return AsyncClient(transport=ASGITransport(app=app), base_url="http://test")


async def _ensure_owner(db: AsyncSession) -> None:
    db.add(User(email=OWNER, hashed_password=hash_password("pw")))
    await db.commit()


async def _seed_messages(
    db: AsyncSession, conversation_id: str, contents: list[str]
) -> list[Message]:
    messages: list[Message] = []
    for content in contents:
        messages.append(
            Message(
                id=str(uuid.uuid4()),
                conversation_id=conversation_id,
                role="user",
                content=content,
            )
        )
    db.add_all(messages)
    await db.commit()
    return messages


async def test_switch_topic_archives_and_partitions_messages(
    db_session: AsyncSession,
) -> None:
    switch = _UserSwitch()
    _install_overrides(db_session, switch)
    try:
        async with _client() as client:
            primary = await ConversationService(db_session).get_or_create_primary(OWNER)
            await _seed_messages(db_session, primary.id, ["Old topic line 1", "Old topic line 2"])
            assert primary.session_epoch == 0

            switched = await client.post(
                f"/api/v1/chat/conversations/{primary.id}/topics/switch",
                json={"label": "New Topic", "archive": True},
            )
            assert switched.status_code == 200, switched.text
            data = switched.json()
            assert data["archived"] is True
            assert data["archive_id"] is not None
            assert data["session_epoch"] == 1

            # 1. Primary conversation session_epoch incremented
            await db_session.refresh(primary)
            assert primary.session_epoch == 1

            # 2. Messages from prior epoch are NOT deleted in database
            all_messages = list(
                (
                    await db_session.scalars(
                        select(Message).where(Message.conversation_id == primary.id)
                    )
                ).all()
            )
            assert len(all_messages) == 2
            assert all(m.session_epoch == 0 for m in all_messages)

            # 3. GET conversation for active primary view returns 0 messages for epoch 1
            conv_resp = await client.get(
                f"/api/v1/chat/conversations/{primary.id}?message_limit=50"
            )
            assert conv_resp.status_code == 200
            assert conv_resp.json()["messages"] == []
            assert conv_resp.json()["message_count"] == 0

            # 4. Archive contains the archived messages
            archive = await db_session.get(TopicArchive, data["archive_id"])
            assert archive is not None
            assert archive.message_count == 2
    finally:
        _clear_overrides()


async def test_switch_topic_into_existing_owned_topic(
    db_session: AsyncSession,
) -> None:
    switch = _UserSwitch()
    _install_overrides(db_session, switch)
    try:
        async with _client() as client:
            primary = await ConversationService(db_session).get_or_create_primary(OWNER)
            topic = Topic(
                id=str(uuid.uuid4()),
                user_id=OWNER,
                label="Existing Projects",
                normalized_label="existing projects",
                origin="history",
                base_score=0.8,
            )
            db_session.add(topic)
            await db_session.commit()

            switched = await client.post(
                f"/api/v1/chat/conversations/{primary.id}/topics/switch",
                json={"topic_id": topic.id, "archive": False},
            )
            assert switched.status_code == 200, switched.text
            assert switched.json()["topic"]["id"] == topic.id
            assert switched.json()["topic"]["label"] == "Existing Projects"
    finally:
        _clear_overrides()


async def test_switch_topic_rejects_legacy_conversation(
    db_session: AsyncSession,
) -> None:
    switch = _UserSwitch()
    _install_overrides(db_session, switch)
    try:
        async with _client() as client:
            legacy = Conversation(
                id=str(uuid.uuid4()),
                user_id=OWNER,
                title="Legacy thread",
                model="test-model",
            )
            db_session.add(legacy)
            await db_session.commit()
            rejected = await client.post(
                f"/api/v1/chat/conversations/{legacy.id}/topics/switch",
                json={"label": "Travel"},
            )
        assert rejected.status_code == 409
    finally:
        _clear_overrides()


async def test_switch_topic_without_archive_keeps_no_snapshot(
    db_session: AsyncSession,
) -> None:
    switch = _UserSwitch()
    _install_overrides(db_session, switch)
    try:
        async with _client() as client:
            primary = await ConversationService(db_session).get_or_create_primary(OWNER)
            await _seed_messages(db_session, primary.id, ["A line."])
            switched = await client.post(
                f"/api/v1/chat/conversations/{primary.id}/topics/switch",
                json={"label": "Travel", "archive": False},
            )
            archive_total = await db_session.scalar(select(func.count(TopicArchive.id)))
        assert switched.status_code == 200, switched.text
        assert switched.json()["archived"] is False
        assert switched.json()["archive_id"] is None
        assert archive_total == 0
    finally:
        _clear_overrides()


async def test_switch_topic_clears_existing_active_context_items(
    db_session: AsyncSession,
) -> None:
    switch = _UserSwitch()
    _install_overrides(db_session, switch)
    try:
        async with _client() as client:
            primary = await ConversationService(db_session).get_or_create_primary(OWNER)
            legacy = Conversation(
                id=str(uuid.uuid4()),
                user_id=OWNER,
                title="Legacy thread",
                model="test-model",
            )
            db_session.add(legacy)
            await db_session.commit()
            source = Message(
                id=str(uuid.uuid4()),
                conversation_id=legacy.id,
                role="user",
                content="Pinned source.",
            )
            db_session.add(source)
            await db_session.commit()
            activate_resp = await client.post(
                f"/api/v1/chat/conversations/{primary.id}/topics/activate",
                json={"label": "Original"},
            )
            await client.post(
                f"/api/v1/chat/conversations/{primary.id}/context/items",
                json={
                    "source_type": "message",
                    "source_id": source.id,
                    "state": "pinned",
                    "context_version": activate_resp.json()["context_version"],
                },
            )
            await _seed_messages(db_session, primary.id, ["Hello."])
            switched = await client.post(
                f"/api/v1/chat/conversations/{primary.id}/topics/switch",
                json={"label": "Travel", "archive": True, "carryover": {"enabled": False}},
            )
            carryover_count = await db_session.scalar(
                select(func.count(ActiveContextItem.id)).where(
                    ActiveContextItem.conversation_id == primary.id
                )
            )
        assert switched.status_code == 200, switched.text
        assert carryover_count == 0
    finally:
        _clear_overrides()


async def test_switch_topic_clears_context_summary_and_updates_title(
    db_session: AsyncSession,
) -> None:
    switch = _UserSwitch()
    _install_overrides(db_session, switch)
    try:
        async with _client() as client:
            primary = await ConversationService(db_session).get_or_create_primary(OWNER)
            primary.title = "⏰ ai news"
            primary.context_summary = "The user requests AI news summaries restricted to 24 hours."
            primary.context_summary_until_id = str(uuid.uuid4())
            await db_session.commit()

            switched = await client.post(
                f"/api/v1/chat/conversations/{primary.id}/topics/switch",
                json={"label": "Guadarrama & Aranjuez Property Search", "archive": True},
            )
            assert switched.status_code == 200, switched.text

            await db_session.refresh(primary)
            assert primary.context_summary is None
            assert primary.context_summary_until_id is None
            assert primary.title == "Guadarrama & Aranjuez Property Search"
    finally:
        _clear_overrides()


async def test_combine_topics_keeps_messages_and_links_relation(
    db_session: AsyncSession,
) -> None:
    switch = _UserSwitch()
    _install_overrides(db_session, switch)
    try:
        async with _client() as client:
            primary = await ConversationService(db_session).get_or_create_primary(OWNER)
            topic_a = Topic(
                id=str(uuid.uuid4()),
                user_id=OWNER,
                label="Family",
                normalized_label="family",
                status="active",
            )
            topic_b = Topic(
                id=str(uuid.uuid4()),
                user_id=OWNER,
                label="Retirement",
                normalized_label="retirement",
                status="active",
            )
            db_session.add_all([topic_a, topic_b])
            primary.active_topic_id = topic_a.id
            primary.title = "Family"
            await db_session.commit()

            await _seed_messages(db_session, primary.id, ["Talking about family plans."])

            # Call combine mode
            res = await client.post(
                f"/api/v1/chat/conversations/{primary.id}/topics/switch",
                json={"topic_id": topic_b.id, "mode": "combine"},
            )
            assert res.status_code == 200, res.text
            data = res.json()
            assert data["archived"] is False
            assert "Retirement" in data["topic"]["combined_topics"]
            assert "Family + Retirement" in data["topic"]["label"]

            # Verify messages were NOT cleared
            remaining_messages = await db_session.scalar(
                select(func.count(Message.id)).where(Message.conversation_id == primary.id)
            )
            assert remaining_messages == 1

            # Verify TopicRelation was established
            rel = await db_session.scalar(
                select(TopicRelation).where(
                    TopicRelation.source_topic_id == topic_a.id,
                    TopicRelation.target_topic_id == topic_b.id,
                    TopicRelation.relation_type == "combined",
                )
            )
            assert rel is not None
            assert rel.confidence == 1.0
    finally:
        _clear_overrides()


async def test_combine_first_topic_pins_it(db_session: AsyncSession) -> None:
    """Bug 1ba9a9f8: combine without a prior topic must pin, like activate."""
    switch = _UserSwitch()
    _install_overrides(db_session, switch)
    try:
        async with _client() as client:
            primary = await ConversationService(db_session).get_or_create_primary(OWNER)
            target = Topic(
                id=str(uuid.uuid4()),
                user_id=OWNER,
                label="Gardening",
                normalized_label="gardening",
                status="active",
            )
            db_session.add(target)
            await db_session.commit()

            res = await client.post(
                f"/api/v1/chat/conversations/{primary.id}/topics/switch",
                json={"topic_id": target.id, "mode": "combine"},
            )
            assert res.status_code == 200, res.text
            await db_session.refresh(primary)
            assert primary.active_topic_id == target.id
            assert primary.topic_is_pinned is True
    finally:
        _clear_overrides()


async def test_patch_topic_selection_pins_it(db_session: AsyncSession) -> None:
    """PATCH topic_id is an explicit user intent and pins like activate."""
    switch = _UserSwitch()
    _install_overrides(db_session, switch)
    try:
        async with _client() as client:
            primary = await ConversationService(db_session).get_or_create_primary(OWNER)
            target = Topic(
                id=str(uuid.uuid4()),
                user_id=OWNER,
                label="Kayaking",
                normalized_label="kayaking",
                status="active",
            )
            db_session.add(target)
            await db_session.commit()

            res = await client.patch(
                f"/api/v1/chat/conversations/{primary.id}/topic",
                json={"topic_id": target.id},
            )
            assert res.status_code == 200, res.text
            await db_session.refresh(primary)
            assert primary.active_topic_id == target.id
            assert primary.topic_is_pinned is True
    finally:
        _clear_overrides()
