"""Persistence invariants for the evidence-grounded topic graph."""

import uuid

import pytest
from sqlalchemy import select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.models.conversation import Conversation
from app.models.message import Message
from app.topics.models import (
    ActiveContextItem,
    MessageTopic,
    Topic,
    TopicAssertion,
    TopicAssertionEvidence,
    TopicContextVersion,
    TopicIngestionEvent,
    TopicRelation,
)

pytestmark = pytest.mark.asyncio

USER_ID = "test@example.com"


async def _conversation(db: AsyncSession, *, primary: bool = False) -> Conversation:
    conversation = Conversation(
        id=str(uuid.uuid4()),
        user_id=USER_ID,
        title="Primary" if primary else "Legacy thread",
        model="test-model",
        is_primary=primary,
    )
    db.add(conversation)
    await db.commit()
    return conversation


async def test_only_one_active_primary_conversation_per_user(db_session: AsyncSession):
    await _conversation(db_session, primary=True)
    db_session.add(
        Conversation(
            id=str(uuid.uuid4()),
            user_id=USER_ID,
            title="Duplicate primary",
            model="test-model",
            is_primary=True,
        )
    )

    with pytest.raises(IntegrityError):
        await db_session.commit()


async def test_topic_context_items_remain_evidence_linked_and_user_owned(
    db_session: AsyncSession,
):
    conversation = await _conversation(db_session, primary=True)
    message = Message(
        id=str(uuid.uuid4()),
        conversation_id=conversation.id,
        role="user",
        content="I will retire in 2045 and prefer a lower-risk plan.",
    )
    topic = Topic(
        id=str(uuid.uuid4()),
        user_id=USER_ID,
        label="Retirement planning",
        normalized_label="retirement planning",
    )
    assertion = TopicAssertion(
        id=str(uuid.uuid4()),
        topic=topic,
        kind="preference",
        content="The user prefers lower risk.",
        normalized_key="retirement-risk-preference",
        authority="explicit_user_statement",
        status="active",
    )
    evidence = TopicAssertionEvidence(
        assertion=assertion,
        message=message,
        segment_start=28,
        segment_end=56,
        relation="supports",
        source_span_hash="a" * 64,
    )
    membership = MessageTopic(
        message=message,
        topic=topic,
        confidence=0.95,
        is_primary=True,
    )
    version = TopicContextVersion(
        id=str(uuid.uuid4()),
        topic=topic,
        version=1,
        context_json={"preferences": [{"assertion_id": assertion.id}]},
        provider="test",
        prompt_version="test-v1",
        validation_status="validated",
    )
    item = ActiveContextItem(
        id=str(uuid.uuid4()),
        conversation=conversation,
        topic=topic,
        source_type="topic_assertion",
        source_id=assertion.id,
        state="dynamic",
        reason="Current topic preference",
    )
    db_session.add_all([message, topic, evidence, membership, version, item])
    await db_session.commit()

    assert membership.message_id == message.id
    assert membership.topic_id == topic.id
    assert evidence.assertion_id == assertion.id
    assert evidence.message_id == message.id
    assert version.topic_id == topic.id
    assert item.conversation_id == conversation.id
    assert item.topic_id == topic.id
    assert assertion.evidence == [evidence]


async def test_ingestion_event_source_operation_is_idempotent(db_session: AsyncSession):
    conversation = await _conversation(db_session)
    event = TopicIngestionEvent(
        user_id=USER_ID,
        conversation_id=conversation.id,
        operation="message_create",
        source_type="message",
        source_id="message-1",
        source_version="1",
    )
    db_session.add(event)
    await db_session.commit()

    db_session.add(
        TopicIngestionEvent(
            user_id=USER_ID,
            conversation_id=conversation.id,
            operation="message_create",
            source_type="message",
            source_id="message-1",
            source_version="1",
        )
    )
    with pytest.raises(IntegrityError):
        await db_session.commit()


async def test_topic_relations_and_centroid_embedding(db_session: AsyncSession):
    topic_a = Topic(
        id=str(uuid.uuid4()),
        user_id=USER_ID,
        label="Machine Learning",
        normalized_label="machine learning",
        centroid_embedding=[0.1] * 768,
    )
    topic_b = Topic(
        id=str(uuid.uuid4()),
        user_id=USER_ID,
        label="Deep Learning",
        normalized_label="deep learning",
        centroid_embedding=[0.2] * 768,
    )
    db_session.add_all([topic_a, topic_b])
    await db_session.commit()

    relation = TopicRelation(
        id=str(uuid.uuid4()),
        user_id=USER_ID,
        source_topic=topic_a,
        target_topic=topic_b,
        relation_type="parent_of",
        confidence=0.95,
        metadata_json={"source": "consolidation"},
    )
    db_session.add(relation)
    await db_session.commit()

    assert relation.source_topic_id == topic_a.id
    assert relation.target_topic_id == topic_b.id

    reloaded_a = await db_session.scalar(
        select(Topic).options(selectinload(Topic.outgoing_relations)).where(Topic.id == topic_a.id)
    )
    assert reloaded_a is not None
    assert len(reloaded_a.outgoing_relations) == 1
    assert reloaded_a.outgoing_relations[0].target_topic_id == topic_b.id
    assert reloaded_a.outgoing_relations[0].relation_type == "parent_of"
    assert len(reloaded_a.centroid_embedding) == 768

    reloaded_b = await db_session.scalar(
        select(Topic).options(selectinload(Topic.incoming_relations)).where(Topic.id == topic_b.id)
    )
    assert reloaded_b is not None
    assert len(reloaded_b.incoming_relations) == 1
    assert reloaded_b.incoming_relations[0].source_topic_id == topic_a.id

    # Duplicate edge check
    dup_relation = TopicRelation(
        id=str(uuid.uuid4()),
        user_id=USER_ID,
        source_topic_id=topic_a.id,
        target_topic_id=topic_b.id,
        relation_type="parent_of",
        confidence=0.8,
    )
    db_session.add(dup_relation)
    with pytest.raises(IntegrityError):
        await db_session.commit()
