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
from app.topics.models import (
    ActiveContextItem,
    MessageTopic,
    Topic,
    TopicArchive,
    TopicRelation,
    TopicSwitchOperation,
)

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
            old_topic = Topic(
                id=str(uuid.uuid4()),
                user_id=OWNER,
                label="Old Topic",
                normalized_label="old topic",
                origin="history",
            )
            db_session.add(old_topic)
            primary.active_topic = old_topic
            primary.active_topic_id = old_topic.id
            primary.title = old_topic.label
            await db_session.commit()
            await _seed_messages(
                db_session,
                primary.id,
                ["Old topic line 1", "Old topic line 2"],
            )
            assert primary.session_epoch == 0

            switched = await client.post(
                f"/api/v1/chat/conversations/{primary.id}/topics/switch",
                json={
                    "idempotency_key": "switch-new-topic",
                    "label": "New Topic",
                    "archive": True,
                },
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
            assert archive.payload["session_epoch"] == 0
            assert "messages" not in archive.payload

            # 5. The archive epoch can be reopened read-only and paged backward.
            detail = await client.get(
                f"/api/v1/chat/topics/{old_topic.id}/archives/{archive.id}",
                params={"limit": 1},
            )
            assert detail.status_code == 200, detail.text
            assert detail.json()["session_epoch"] == 0
            assert detail.json()["topic_label"] == "Old Topic"
            assert detail.json()["has_more"] is True
            assert [message["content"] for message in detail.json()["messages"]] == [
                "Old topic line 2"
            ]
            older = await client.get(
                f"/api/v1/chat/topics/{old_topic.id}/archives/{archive.id}",
                params={"limit": 1, "before": detail.json()["messages"][0]["id"]},
            )
            assert older.status_code == 200, older.text
            assert older.json()["has_more"] is False
            assert [message["content"] for message in older.json()["messages"]] == [
                "Old topic line 1"
            ]
            wrong_topic = await client.get(
                f"/api/v1/chat/topics/{data['topic']['id']}/archives/{archive.id}"
            )
            assert wrong_topic.status_code == 404
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
                json={
                    "idempotency_key": "switch-existing-topic",
                    "topic_id": topic.id,
                    "archive": False,
                },
            )
            assert switched.status_code == 200, switched.text
            assert switched.json()["topic"]["id"] == topic.id
            assert switched.json()["topic"]["label"] == "Existing Projects"
    finally:
        _clear_overrides()


async def test_switch_materializes_existing_topic_evidence_before_first_turn(
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
                title="Clara story history",
                model="test-model",
            )
            db_session.add(legacy)
            await db_session.flush()
            evidence = Message(
                id=str(uuid.uuid4()),
                conversation_id=legacy.id,
                role="user",
                content="Clara likes funny stories about a brave purple dragon.",
            )
            topic = Topic(
                id=str(uuid.uuid4()),
                user_id=OWNER,
                label="Fun Stories for Clara",
                normalized_label="fun stories for clara",
                origin="history",
            )
            db_session.add_all([evidence, topic])
            await db_session.flush()
            db_session.add(
                MessageTopic(
                    message_id=evidence.id,
                    topic_id=topic.id,
                    confidence=1.0,
                    is_primary=True,
                    segment_start=0,
                    segment_end=len(evidence.content),
                    source_authority="explicit_user_statement",
                )
            )
            await db_session.commit()

            switched = await client.post(
                f"/api/v1/chat/conversations/{primary.id}/topics/switch",
                json={
                    "idempotency_key": "switch-fun-stories",
                    "topic_id": topic.id,
                    "archive": False,
                },
            )
            context = await client.get(f"/api/v1/chat/conversations/{primary.id}/context")

        assert switched.status_code == 200, switched.text
        assert context.status_code == 200, context.text
        body = context.json()
        assert switched.json()["context_version"] == 1
        assert body["context_version"] == 1
        assert body["token_count"] > 0
        assert [item["source_id"] for item in body["dynamic_items"]] == [evidence.id]
        assert "brave purple dragon" in body["dynamic_items"][0]["source_excerpt"]
        assert any(section["id"] == "active_context" for section in body["context_sections"]), body
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
                json={"idempotency_key": "legacy-switch", "label": "Travel"},
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
                json={
                    "idempotency_key": "switch-without-archive",
                    "label": "Travel",
                    "archive": False,
                },
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
                f"/api/v1/chat/conversations/{primary.id}/topics/switch",
                json={
                    "idempotency_key": "activate-original",
                    "label": "Original",
                    "archive": False,
                },
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
                json={
                    "idempotency_key": "switch-drop-pins",
                    "label": "Travel",
                    "archive": True,
                    "retain_pinned": False,
                },
            )
            active_item_count = await db_session.scalar(
                select(func.count(ActiveContextItem.id)).where(
                    ActiveContextItem.conversation_id == primary.id
                )
            )
        assert switched.status_code == 200, switched.text
        assert active_item_count == 0
    finally:
        _clear_overrides()


async def test_switch_topic_retains_only_explicitly_pinned_sources(
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
                title="Source thread",
                model="test-model",
            )
            db_session.add(legacy)
            await db_session.flush()
            source = Message(
                id=str(uuid.uuid4()),
                conversation_id=legacy.id,
                role="user",
                content="Distinctive retained launch fact.",
            )
            db_session.add(source)
            await db_session.flush()
            pinned = ActiveContextItem(
                id=str(uuid.uuid4()),
                conversation_id=primary.id,
                source_type="message",
                source_id=source.id,
                state="pinned",
                reason="Pinned by you",
            )
            dynamic = ActiveContextItem(
                id=str(uuid.uuid4()),
                conversation_id=primary.id,
                source_type="thread",
                source_id=legacy.id,
                state="dynamic",
            )
            db_session.add_all([pinned, dynamic])
            await db_session.commit()

            response = await client.post(
                f"/api/v1/chat/conversations/{primary.id}/topics/switch",
                json={
                    "idempotency_key": "switch-retain-pinned",
                    "label": "Launch",
                    "retain_pinned": True,
                },
            )
            assert response.status_code == 200, response.text
            assert [item["id"] for item in response.json()["retained_items"]] == [pinned.id]
            remaining = list(
                (
                    await db_session.scalars(
                        select(ActiveContextItem).where(
                            ActiveContextItem.conversation_id == primary.id
                        )
                    )
                ).all()
            )
            assert [item.id for item in remaining] == [pinned.id]
    finally:
        _clear_overrides()


async def test_switch_topic_idempotency_replays_one_committed_boundary(
    db_session: AsyncSession,
) -> None:
    switch = _UserSwitch()
    _install_overrides(db_session, switch)
    try:
        async with _client() as client:
            primary = await ConversationService(db_session).get_or_create_primary(OWNER)
            await _seed_messages(db_session, primary.id, ["Only archive this once."])
            payload = {
                "idempotency_key": "retry-after-response-loss",
                "label": "Launch",
                "archive": True,
            }
            first = await client.post(
                f"/api/v1/chat/conversations/{primary.id}/topics/switch", json=payload
            )
            replay = await client.post(
                f"/api/v1/chat/conversations/{primary.id}/topics/switch", json=payload
            )

            assert first.status_code == 200, first.text
            assert replay.status_code == 200, replay.text
            assert replay.json() == first.json()
            await db_session.refresh(primary)
            assert primary.session_epoch == 1
            assert await db_session.scalar(select(func.count(TopicArchive.id))) == 1
            assert await db_session.scalar(select(func.count(TopicSwitchOperation.id))) == 1
    finally:
        _clear_overrides()


async def test_switch_topic_rejects_idempotency_key_reuse_for_another_target(
    db_session: AsyncSession,
) -> None:
    switch = _UserSwitch()
    _install_overrides(db_session, switch)
    try:
        async with _client() as client:
            primary = await ConversationService(db_session).get_or_create_primary(OWNER)
            first = await client.post(
                f"/api/v1/chat/conversations/{primary.id}/topics/switch",
                json={"idempotency_key": "reused-switch-key", "label": "Launch"},
            )
            conflict = await client.post(
                f"/api/v1/chat/conversations/{primary.id}/topics/switch",
                json={"idempotency_key": "reused-switch-key", "label": "Travel"},
            )

            assert first.status_code == 200, first.text
            assert conflict.status_code == 409
            assert conflict.json()["detail"] == "idempotency_key_reused"
            await db_session.refresh(primary)
            assert primary.session_epoch == 1
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
                json={
                    "idempotency_key": "switch-property-search",
                    "label": "Guadarrama & Aranjuez Property Search",
                    "archive": True,
                },
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
                json={
                    "idempotency_key": "combine-family-retirement",
                    "topic_id": topic_b.id,
                    "mode": "combine",
                },
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
                json={
                    "idempotency_key": "combine-first-topic",
                    "topic_id": target.id,
                    "mode": "combine",
                },
            )
            assert res.status_code == 200, res.text
            await db_session.refresh(primary)
            assert primary.active_topic_id == target.id
            assert primary.topic_is_pinned is True
    finally:
        _clear_overrides()


async def test_patch_topic_only_updates_pin_with_version_check(
    db_session: AsyncSession,
) -> None:
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
            primary.active_topic_id = target.id
            primary.topic_is_pinned = True
            primary.context_version = 3
            await db_session.commit()

            res = await client.patch(
                f"/api/v1/chat/conversations/{primary.id}/topic",
                json={"pinned": False, "context_version": 3},
            )
            assert res.status_code == 200, res.text
            await db_session.refresh(primary)
            assert primary.active_topic_id == target.id
            assert primary.topic_is_pinned is False
            assert primary.context_version == 4

            stale = await client.patch(
                f"/api/v1/chat/conversations/{primary.id}/topic",
                json={"pinned": True, "context_version": 3},
            )
            bypass = await client.patch(
                f"/api/v1/chat/conversations/{primary.id}/topic",
                json={"topic_id": target.id},
            )
            assert stale.status_code == 409
            assert bypass.status_code == 422
    finally:
        _clear_overrides()
