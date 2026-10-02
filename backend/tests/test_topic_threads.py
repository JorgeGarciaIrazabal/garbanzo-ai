"""Independent topic thread and identity-preserving archive resume regressions."""

import asyncio
import uuid
from datetime import UTC, datetime
from unittest.mock import AsyncMock

import pytest
import pytest_asyncio
from sqlalchemy import func, select

from app.models.conversation import Conversation
from app.models.message import Message
from app.models.user import User
from app.models.workflow_run import WorkflowRun
from app.services.chat_service import ChatService
from app.services.conversation_service import ConversationService
from app.services.llm_provider import ChatChunk
from app.topics.generation_state import active_streams
from app.topics.models import (
    ActiveContextItem,
    MessageTopic,
    Topic,
    TopicArchive,
    TopicExclusion,
    TopicIngestionEvent,
    TopicSwitchOperation,
)
from app.topics.topic_context_compiler import TopicContextCompiler
from app.topics.topic_ingestion_service import TopicIngestionService
from app.topics.topic_switch_service import TopicSwitchService
from tests.test_topic_switch import (
    OTHER,
    OWNER,
    _clear_overrides,
    _client,
    _install_overrides,
    _UserSwitch,
)

pytestmark = pytest.mark.asyncio


@pytest_asyncio.fixture
async def topic_client(db_session):
    user = _UserSwitch()
    _install_overrides(db_session, user)
    try:
        async with _client() as client:
            yield client, user
    finally:
        _clear_overrides()


async def _topic(db, label="Travel", user_id=OWNER):
    topic = Topic(
        id=str(uuid.uuid4()),
        user_id=user_id,
        label=label,
        normalized_label=label.casefold(),
        origin="history",
        status="active",
    )
    db.add(topic)
    await db.commit()
    return topic


async def _source(db, topic):
    source = await ConversationService(db).get_or_create_primary(OWNER)
    source.active_topic_id = topic.id
    source.title = "Existing session"
    source.model = "source-model"
    source.system_prompt = "A chosen style."
    source.thinking_level = "high"
    source.enabled_tools = ["test:chosen"]
    source.use_memory = False
    source.use_knowledge_base = False
    source.context_summary = "Existing summary"
    source.context_version = 8
    source.session_epoch = 4
    db.add(
        Message(
            id=str(uuid.uuid4()),
            conversation_id=source.id,
            role="user",
            content="Existing visible session",
            session_epoch=4,
        )
    )
    await db.commit()
    await db.refresh(source)
    return source


async def _start(client, source_id, topic_id=None, label=None, key="start-test-key", **settings):
    target = {"topic_id": topic_id} if topic_id else {"label": label}
    return await client.post(
        f"/api/v1/chat/conversations/{source_id}/topics/switch",
        json={"mode": "start", "idempotency_key": key, **target, **settings},
    )


async def test_start_same_topic_twice_replays_one_thread_and_leaves_source_unchanged(
    db_session,
    topic_client,
):
    client, _ = topic_client
    topic = await _topic(db_session)
    source = await _source(db_session, topic)
    source_id, topic_id = source.id, topic.id
    source_state = {
        column.name: getattr(source, column.name) for column in Conversation.__table__.columns
    }
    old_ids = list((await db_session.scalars(select(Message.id))).all())
    first = await _start(client, source_id, topic_id)
    replay = await _start(client, source_id, topic_id)
    second = await _start(client, source_id, topic_id, key="another-start-key")
    assert first.status_code == second.status_code == replay.status_code == 200
    assert replay.json() == first.json()
    assert first.json()["conversation_id"] != second.json()["conversation_id"] != source.id
    assert first.json()["archived"] is False
    await db_session.refresh(source)
    assert {
        column.name: getattr(source, column.name) for column in Conversation.__table__.columns
    } == source_state
    assert list((await db_session.scalars(select(Message.id))).all()) == old_ids
    assert await db_session.scalar(select(func.count(TopicArchive.id))) == 0
    assert await db_session.scalar(select(func.count(TopicSwitchOperation.id))) == 2
    for response in (first, second):
        thread = await ConversationService(db_session).get(
            response.json()["conversation_id"], OWNER
        )
        assert thread.is_primary is False
        assert thread.active_topic_id == topic.id and thread.topic_is_pinned
        assert thread.messages == []
        for field in (
            "model",
            "system_prompt",
            "thinking_level",
            "use_memory",
            "use_knowledge_base",
            "enabled_tools",
        ):
            assert getattr(thread, field) == source_state[field]
    listed = await client.get(f"/api/v1/chat/topics/{topic.id}/conversations")
    assert listed.status_code == 200
    assert {conv["id"] for conv in listed.json()["conversations"]} == {
        source.id,
        first.json()["conversation_id"],
        second.json()["conversation_id"],
    }
    limited = await client.get(f"/api/v1/chat/topics/{topic.id}/conversations?limit=1")
    assert len(limited.json()["conversations"]) == 1
    assert (
        await client.get(f"/api/v1/chat/topics/{topic.id}/conversations?limit=201")
    ).status_code == 422


async def test_start_settings_explicit_null_inheritance_and_idempotency_conflicts(
    db_session, topic_client
):
    client, _ = topic_client
    topic = await _topic(db_session)
    source = await _source(db_session, topic)
    source_id, topic_id = source.id, topic.id
    first = await _start(
        client, source_id, topic_id, model="chosen-model", system_prompt=None, thinking_level=None
    )
    assert first.status_code == 200, first.text
    thread = await db_session.get(Conversation, first.json()["conversation_id"])
    assert (
        thread.model == "chosen-model"
        and thread.system_prompt is None
        and thread.thinking_level is None
    )
    replay = await _start(
        client, source_id, topic_id, model="chosen-model", system_prompt=None, thinking_level=None
    )
    assert replay.json() == first.json()
    for changed in ({}, {"model": "another-model", "system_prompt": None, "thinking_level": None}):
        conflict = await _start(client, source_id, topic_id, **changed)
        assert conflict.status_code == 409 and conflict.json()["detail"] == "idempotency_key_reused"
    for mode in ("switch", "combine"):
        response = await client.post(
            f"/api/v1/chat/conversations/{source_id}/topics/switch",
            json={"idempotency_key": "start-test-key", "mode": mode, "topic_id": topic_id},
        )
        assert response.status_code == 409 and response.json()["detail"] == "idempotency_key_reused"
        invalid = await client.post(
            f"/api/v1/chat/conversations/{source_id}/topics/switch",
            json={
                "idempotency_key": "invalid-settings",
                "mode": mode,
                "topic_id": topic_id,
                "system_prompt": None,
            },
        )
        assert invalid.status_code == 422


async def test_start_free_label_and_suggested_topic_and_reject_foreign_targets(
    db_session, topic_client
):
    client, user = topic_client
    source = await ConversationService(db_session).get_or_create_primary(OWNER)
    source_id = source.id
    manual = await _start(client, source_id, label="  Kayaking  ")
    assert manual.status_code == 200
    # Discover the authoritative suggested IDs rather than hard-coding presentation slugs.
    explore = await client.get("/api/v1/chat/topics?mode=explore")
    assert explore.status_code == 200 and explore.json()["topics"]
    suggested = await _start(
        client, source_id, topic_id=explore.json()["topics"][0]["id"], key="valid-suggested-key"
    )
    assert suggested.status_code == 200, suggested.text
    assert manual.json()["topic"]["label"] == "Kayaking"
    db_session.add(User(email=OTHER, hashed_password="unused"))
    await db_session.commit()
    foreign = await _topic(db_session, "Foreign", OTHER)
    foreign_id = foreign.id
    invalid = await _start(client, source_id, topic_id=foreign_id, key="foreign-target-key")
    assert invalid.status_code == 404
    invalid_create = await client.post(
        "/api/v1/chat/conversations", json={"active_topic_id": foreign_id}
    )
    assert invalid_create.status_code == 404
    missing_create = await client.post(
        "/api/v1/chat/conversations", json={"active_topic_id": "missing"}
    )
    assert missing_create.status_code == 404
    user.email = OTHER
    assert (
        await _start(client, source_id, label="Stolen", key="stolen-source-key")
    ).status_code == 404
    assert (
        await client.get(f"/api/v1/chat/topics/{manual.json()['topic']['id']}/conversations")
    ).status_code == 404


async def test_start_preloads_evidence_copies_only_eligible_pins_and_context_mutations(
    db_session, topic_client
):
    client, _ = topic_client
    topic = await _topic(db_session)
    source = await _source(db_session, topic)
    source_id, topic_id = source.id, topic.id
    evidence_thread = Conversation(id=str(uuid.uuid4()), user_id=OWNER, model="test-model")
    db_session.add(evidence_thread)
    await db_session.flush()
    messages = [
        Message(
            id=str(uuid.uuid4()),
            conversation_id=evidence_thread.id,
            role="user",
            content=content,
        )
        for content in ("The preferred destination is Kyoto.", "Sensitive excluded itinerary.")
    ]
    db_session.add_all(messages)
    await db_session.flush()
    db_session.add_all(
        [
            MessageTopic(
                message_id=message.id,
                topic_id=topic.id,
                confidence=1,
                is_primary=True,
                source_authority="explicit_user_statement",
                segment_start=0,
                segment_end=len(message.content),
            )
            for message in messages
        ]
    )
    db_session.add_all(
        [
            ActiveContextItem(
                id=str(uuid.uuid4()),
                conversation_id=source.id,
                source_type="message",
                source_id=message.id,
                state="pinned",
                topic_id=topic.id,
            )
            for message in messages
        ]
    )
    db_session.add(
        TopicExclusion(
            id=str(uuid.uuid4()),
            user_id=OWNER,
            scope="source",
            target_id=messages[1].id,
            origin="context_panel",
        )
    )
    await db_session.commit()
    started = await _start(client, source_id, topic_id)
    assert started.status_code == 200, started.text
    thread_id = started.json()["conversation_id"]
    assert [item["source_id"] for item in started.json()["retained_items"]] == [messages[0].id]
    context = await client.get(f"/api/v1/chat/conversations/{thread_id}/context")
    assert context.status_code == 200, context.text
    assert [item["source_id"] for item in context.json()["pinned_items"]] == [messages[0].id]
    pin = context.json()["pinned_items"][0]
    exclude = await client.patch(
        f"/api/v1/chat/conversations/{thread_id}/context/items/{pin['id']}",
        json={"state": "excluded", "context_version": context.json()["context_version"]},
    )
    assert exclude.status_code == 200
    unpin = await client.patch(
        f"/api/v1/chat/conversations/{thread_id}/topic",
        json={"pinned": False, "context_version": exclude.json()["context_version"]},
    )
    assert unpin.status_code == 200
    combine = await client.post(
        f"/api/v1/chat/conversations/{thread_id}/topics/switch",
        json={"mode": "combine", "label": "Food", "idempotency_key": "combine-new-thread"},
    )
    assert combine.status_code == 200, combine.text
    switch = await client.post(
        f"/api/v1/chat/conversations/{thread_id}/topics/switch",
        json={"label": "Other", "idempotency_key": "destructive-thread"},
    )
    assert switch.status_code == 409
    created = await client.post("/api/v1/chat/conversations", json={"active_topic_id": topic_id})
    assert created.status_code == 201, created.text
    assert created.json()["topic_is_pinned"] is True
    created_context = await client.get(f"/api/v1/chat/conversations/{created.json()['id']}/context")
    assert created_context.status_code == 200


async def _closed_archive(db, topic):
    source = await _source(db, topic)
    source_id, topic_id = source.id, topic.id
    messages = [
        Message(
            id=str(uuid.uuid4()),
            conversation_id=source_id,
            role=role,
            content=content,
            session_epoch=3,
            seq=index + 1,
            is_starred=index == 0,
            meta={"original": index},
            created_at=datetime(2025, 1, index + 1, tzinfo=UTC),
        )
        for index, (role, content) in enumerate(
            [
                ("user", "Original travel constraint: use quiet trains."),
                ("tool_call", "Original call"),
                ("tool_result", "Original result"),
                ("assistant", "Original response"),
            ]
        )
    ]
    db.add_all(messages)
    await db.flush()
    events = [
        TopicIngestionEvent(
            user_id=OWNER,
            conversation_id=source_id,
            operation="create",
            source_type="message",
            source_id=message.id,
            source_version="original",
            payload={"original": True},
            processed_at=datetime.now(UTC),
        )
        for message in messages
    ]
    archive = TopicArchive(
        id=str(uuid.uuid4()),
        user_id=OWNER,
        topic_id=topic_id,
        from_topic_id=topic_id,
        conversation_id=source_id,
        message_count=len(messages),
        payload={
            "session_epoch": 3,
            "topic_label": topic.label,
            "conversation_title": "Original travel session",
        },
    )
    membership = MessageTopic(
        message_id=messages[0].id, topic_id=topic_id, confidence=1, is_primary=True
    )
    completed = WorkflowRun(
        id=str(uuid.uuid4()),
        user_id=OWNER,
        conversation_id=source_id,
        session_epoch=3,
        status="done",
        instruction="Original completed work",
    )
    current = WorkflowRun(
        id=str(uuid.uuid4()),
        user_id=OWNER,
        conversation_id=source_id,
        session_epoch=4,
        status="running",
        instruction="Unrelated active epoch work",
    )
    db.add_all([archive, membership, completed, current, *events])
    await db.commit()
    for message in messages:
        await db.refresh(message)
    return source, archive, messages, events, completed, current


async def test_archive_resume_moves_exact_history_once_preserving_provenance_and_no_ingestion(
    db_session,
    topic_client,
    monkeypatch,
):
    client, _ = topic_client
    topic = await _topic(db_session)
    source, archive, messages, events, completed, current = await _closed_archive(db_session, topic)
    source_id, archive_id, topic_id = source.id, archive.id, topic.id
    original = [
        {column.name: getattr(message, column.name) for column in Message.__table__.columns}
        for message in messages
    ]
    before_source = {
        column.name: getattr(source, column.name) for column in Conversation.__table__.columns
    }
    db_session.add(
        TopicExclusion(
            id=str(uuid.uuid4()),
            user_id=OWNER,
            topic_id=topic_id,
            scope="source",
            target_id=messages[0].id,
            origin="context_panel",
        )
    )
    await db_session.commit()
    process = AsyncMock(side_effect=AssertionError("Resume must not reingest history"))
    monkeypatch.setattr(TopicIngestionService, "process_event", process)
    url = f"/api/v1/chat/topics/{topic_id}/archives/{archive_id}/resume"
    first = await client.post(url)
    assert first.status_code == 200, first.text
    thread_id = first.json()["id"]
    assert thread_id != source_id and first.json()["is_primary"] is False
    assert first.json()["session_epoch"] == 3
    assert first.json()["message_count"] == len(messages)
    assert first.json()["title"] == "Original travel session"
    replay = await client.post(url)
    assert replay.status_code == 200 and replay.json()["id"] == thread_id
    for message, snapshot in zip(messages, original, strict=True):
        await db_session.refresh(message)
        assert {
            column.name: getattr(message, column.name) for column in Message.__table__.columns
        } == snapshot | {"conversation_id": thread_id}
    await db_session.refresh(source)
    assert {
        column.name: getattr(source, column.name) for column in Conversation.__table__.columns
    } == before_source
    for event in events:
        await db_session.refresh(event)
        assert event.conversation_id == thread_id and event.payload == {"original": True}
    await db_session.refresh(completed)
    await db_session.refresh(current)
    assert completed.conversation_id == thread_id
    assert current.conversation_id == source_id
    assert await db_session.scalar(select(func.count(TopicIngestionEvent.id))) == len(events)
    assert (
        await db_session.scalar(
            select(MessageTopic.message_id).where(MessageTopic.message_id == messages[0].id)
        )
        == messages[0].id
    )
    assert await db_session.scalar(select(func.count(TopicExclusion.id))) == 1
    process.assert_not_called()
    detail = await client.get(url.removesuffix("/resume"))
    assert detail.status_code == 200, detail.text
    assert detail.json()["archive"]["resumed_conversation_id"] == thread_id
    assert [message["id"] for message in detail.json()["messages"]] == [
        snapshot["id"] for snapshot in original
    ]
    page = await client.get(
        url.removesuffix("/resume"), params={"before": original[-1]["id"], "limit": 2}
    )
    assert [message["id"] for message in page.json()["messages"]] == [
        snapshot["id"] for snapshot in original[1:3]
    ]
    assert page.json()["has_more"] is True
    deleted = await db_session.get(Conversation, thread_id)
    deleted.is_deleted = True
    await db_session.commit()
    assert (await client.post(url)).status_code == 404
    assert (await client.get(url.removesuffix("/resume"))).status_code == 404


async def test_archive_resume_rejects_open_epoch_inflight_work_foreign_and_deleted_sources(
    db_session, topic_client
):
    client, user = topic_client
    topic = await _topic(db_session)
    source, archive, _, _, _, _ = await _closed_archive(db_session, topic)
    source_id, archive_id, topic_id = source.id, archive.id, topic.id
    url = f"/api/v1/chat/topics/{topic_id}/archives/{archive_id}/resume"
    archive.payload = dict(archive.payload) | {"session_epoch": 4}
    await db_session.commit()
    opened = await client.post(url)
    assert opened.status_code == 409 and opened.json()["detail"] == "archive_not_closed"
    archive = await db_session.get(TopicArchive, archive_id)
    archive.payload = dict(archive.payload) | {"session_epoch": 3}
    await db_session.commit()
    active_streams[source_id] = asyncio.Event()
    try:
        inflight = await client.post(url)
        assert inflight.status_code == 409 and inflight.json()["detail"] == "archive_inflight"
    finally:
        active_streams.pop(source_id, None)
    run_id = str(uuid.uuid4())
    db_session.add(
        WorkflowRun(
            id=run_id,
            user_id=OWNER,
            conversation_id=source_id,
            session_epoch=3,
            status="running",
            instruction="Unfinished original epoch",
        )
    )
    await db_session.commit()
    inflight = await client.post(url)
    assert inflight.status_code == 409 and inflight.json()["detail"] == "archive_inflight"
    run = await db_session.get(WorkflowRun, run_id)
    run.status = "done"
    await db_session.commit()
    db_session.add(User(email=OTHER, hashed_password="unused"))
    await db_session.commit()
    user.email = OTHER
    assert (await client.post(url)).status_code == 404
    user.email = OWNER
    source = await db_session.get(Conversation, source_id)
    source.is_deleted = True
    await db_session.commit()
    assert (await client.post(url)).status_code == 404


async def test_topic_thread_send_and_regenerate_include_old_own_details_and_summary(
    db_session,
    topic_client,
    monkeypatch,
):
    client, _ = topic_client
    topic = await _topic(db_session)
    source = await _source(db_session, topic)
    source_id, topic_id = source.id, topic.id
    started = await _start(client, source_id, topic_id)
    thread_id = started.json()["conversation_id"]
    thread = await db_session.get(Conversation, thread_id)
    messages = [
        Message(
            id=str(uuid.uuid4()),
            conversation_id=thread_id,
            role="user" if index % 2 == 0 else "assistant",
            content="The original lock code is violet-731." if index == 0 else f"Turn {index}.",
            seq=index + 1,
        )
        for index in range(32)
    ]
    db_session.add_all(messages)
    await db_session.commit()
    prompts = []

    class Provider:
        async def stream_chat(self, messages, **kwargs):
            prompts.append(messages)
            yield ChatChunk(content="Response")
            yield ChatChunk(content="", is_finished=True)

    service = ChatService(db_session)
    monkeypatch.setattr(service, "_get_provider", lambda: Provider())
    monkeypatch.setattr(service, "_get_context_length", AsyncMock(return_value=100000))
    monkeypatch.setattr(
        service, "_resolve_tools_for_conversation", AsyncMock(return_value=([], {}))
    )
    monkeypatch.setattr(TopicIngestionService, "process_event", AsyncMock())
    monkeypatch.setattr(service, "_spawn_title_generation", lambda *args: None)
    sent = [
        chunk
        async for chunk in service.send_message(thread_id, OWNER, "What was the old lock code?")
    ]
    assert any(chunk.is_finished for chunk in sent)
    assert "violet-731" in "\n".join(message.content for message in prompts[-1])
    response = await db_session.scalar(
        select(Message)
        .where(Message.conversation_id == thread_id, Message.role == "assistant")
        .order_by(Message.seq.desc())
    )
    response_id = response.id
    regenerated = [
        chunk async for chunk in service.regenerate_message(thread_id, OWNER, response_id)
    ]
    assert any(chunk.is_finished for chunk in regenerated)
    assert "violet-731" in "\n".join(message.content for message in prompts[-1])
    thread.context_summary = "The original lock code is violet-731, recorded in the summary."
    thread.context_summary_until_id = messages[0].id
    await db_session.commit()
    await db_session.refresh(thread, attribute_names=["messages", "active_topic"])
    compiled = await TopicContextCompiler(db_session).compile(thread, current_query="lock code")
    assert len(compiled.history_messages) > 24
    sent = [
        chunk async for chunk in service.send_message(thread_id, OWNER, "Recall the summary code.")
    ]
    assert any(chunk.is_finished for chunk in sent)
    assert any("recorded in the summary" in message.content for message in prompts[-1])


async def test_start_and_resume_rollback_all_materialization_changes(db_session, monkeypatch):
    topic = await _topic(db_session)
    source, archive, messages, events, completed, _ = await _closed_archive(db_session, topic)
    source_id, archive_id, topic_id = source.id, archive.id, topic.id
    message_ids = [message.id for message in messages]
    event_ids = [event.id for event in events]
    completed_id = completed.id
    service = TopicSwitchService(db_session)
    monkeypatch.setattr(
        TopicContextCompiler,
        "materialize_baseline",
        AsyncMock(side_effect=RuntimeError("baseline unavailable")),
    )
    with pytest.raises(RuntimeError, match="baseline unavailable"):
        await service.start(
            conversation_id=source_id,
            user=await db_session.get(User, OWNER),
            topic_id=None,
            label="Never committed",
            idempotency_key="failed-materialization",
            archive=True,
            retain_pinned=False,
        )
    assert await db_session.scalar(select(func.count(Conversation.id))) == 1
    assert await db_session.scalar(select(func.count(TopicSwitchOperation.id))) == 0
    assert (
        await db_session.scalar(select(Topic.id).where(Topic.normalized_label == "never committed"))
        is None
    )
    with pytest.raises(RuntimeError, match="baseline unavailable"):
        await service.resume_archive(topic_id, archive_id, await db_session.get(User, OWNER))
    assert await db_session.scalar(select(func.count(Conversation.id))) == 1
    assert set(
        (
            await db_session.scalars(
                select(Message.conversation_id).where(Message.id.in_(message_ids))
            )
        ).all()
    ) == {source_id}
    assert set(
        (
            await db_session.scalars(
                select(TopicIngestionEvent.conversation_id).where(
                    TopicIngestionEvent.id.in_(event_ids)
                )
            )
        ).all()
    ) == {source_id}
    assert (await db_session.get(WorkflowRun, completed_id)).conversation_id == source_id
    assert "resumed_conversation_id" not in (await db_session.get(TopicArchive, archive_id)).payload


async def test_topic_archive_listing_filters_archive_owner(db_session, topic_client):
    client, _ = topic_client
    topic = await _topic(db_session)
    source, archive, _, _, _, _ = await _closed_archive(db_session, topic)
    archive_id, topic_id = archive.id, topic.id
    db_session.add(User(email=OTHER, hashed_password="unused"))
    await db_session.flush()
    foreign_source = Conversation(id=str(uuid.uuid4()), user_id=OTHER, model="test")
    db_session.add(foreign_source)
    await db_session.flush()
    foreign_archive_id = str(uuid.uuid4())
    db_session.add(
        TopicArchive(
            id=foreign_archive_id,
            user_id=OTHER,
            topic_id=topic_id,
            conversation_id=foreign_source.id,
            message_count=0,
            payload={"session_epoch": 0},
        )
    )
    await db_session.commit()
    listed = await client.get(f"/api/v1/chat/topics/{topic_id}/archives")
    assert listed.status_code == 200
    assert [item["id"] for item in listed.json()["archives"]] == [archive_id]
    assert (
        await client.post(f"/api/v1/chat/topics/{topic_id}/archives/{foreign_archive_id}/resume")
    ).status_code == 404
    assert (
        await client.get(f"/api/v1/chat/topics/{topic_id}/archives/{foreign_archive_id}")
    ).status_code == 404
