"""Regression coverage for hard topic-context source eligibility."""

from __future__ import annotations

import hashlib
import uuid
from datetime import UTC, datetime, timedelta

import pytest
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import Settings
from app.models.conversation import Conversation
from app.models.message import Message
from app.topics.models import (
    ActiveContextItem,
    MessageTopic,
    Topic,
    TopicAssertion,
    TopicAssertionEvidence,
    TopicExclusion,
    TopicRelation,
)
from app.topics.topic_context_compiler import TopicContextCompiler

pytestmark = pytest.mark.asyncio

OWNER = "test@example.com"
ASSERTION_CONTENT = "Use the orchid route for the launch itinerary."


class _NoEmbeddings:
    async def embed(self, texts: list[str]) -> list[list[float]]:  # noqa: ARG002
        return []


async def _conversation(
    db: AsyncSession,
    *,
    title: str,
    primary: bool = False,
) -> Conversation:
    conversation = Conversation(
        id=str(uuid.uuid4()),
        user_id=OWNER,
        title=title,
        model="test-model",
        is_primary=primary,
    )
    db.add(conversation)
    await db.commit()
    await db.refresh(conversation, attribute_names=["messages", "active_topic"])
    return conversation


async def _message(db: AsyncSession, conversation: Conversation, content: str) -> Message:
    message = Message(
        id=str(uuid.uuid4()),
        conversation_id=conversation.id,
        role="user",
        content=content,
    )
    db.add(message)
    await db.commit()
    return message


async def _assertion(
    db: AsyncSession,
    topic: Topic,
    evidence: Message,
    content: str = ASSERTION_CONTENT,
) -> TopicAssertion:
    assertion = TopicAssertion(
        id=str(uuid.uuid4()),
        topic_id=topic.id,
        kind="preference",
        content=content,
        normalized_key=str(uuid.uuid4()),
        status="active",
        authority="explicit_user_statement",
        confidence=0.9,
    )
    db.add(assertion)
    await db.flush()
    db.add(
        TopicAssertionEvidence(
            assertion_id=assertion.id,
            message_id=evidence.id,
            segment_start=0,
            segment_end=len(evidence.content),
            relation="supports",
            source_span_hash=hashlib.sha256(evidence.content.encode()).hexdigest(),
        )
    )
    await db.commit()
    return assertion


async def _pinned_assertion_fixture(
    db: AsyncSession,
) -> tuple[Conversation, Conversation, Topic, Message, TopicAssertion]:
    primary = await _conversation(db, title="Primary", primary=True)
    evidence_thread = await _conversation(db, title="Evidence")
    topic = Topic(
        id=str(uuid.uuid4()),
        user_id=OWNER,
        label="Launch planning",
        normalized_label="launch planning",
    )
    db.add(topic)
    await db.commit()
    primary.active_topic_id = topic.id
    evidence = await _message(db, evidence_thread, "I want to use the orchid route.")
    assertion = await _assertion(db, topic, evidence)
    db.add(
        ActiveContextItem(
            id=str(uuid.uuid4()),
            conversation_id=primary.id,
            source_type="topic_assertion",
            source_id=assertion.id,
            topic_id=topic.id,
            state="pinned",
            reason="Pinned by you",
        )
    )
    await db.commit()
    return primary, evidence_thread, topic, evidence, assertion


def _settings() -> Settings:
    return Settings(
        secret_key="test-secret-key-do-not-use-in-prod",
        database_url="sqlite+aiosqlite:///:memory:",
        topic_context_enabled=True,
        topic_context_token_budget=12000,
    )


async def test_live_pinned_assertion_uses_canonical_type_and_evidence(
    db_session: AsyncSession,
    monkeypatch: pytest.MonkeyPatch,
):
    primary, _, _, _, assertion = await _pinned_assertion_fixture(db_session)
    monkeypatch.setattr("app.topics.topic_context_compiler.get_settings", _settings)

    result = await TopicContextCompiler(
        db_session,
        embedding_provider=_NoEmbeddings(),
    ).compile(primary, current_query="launch route")

    assert ASSERTION_CONTENT in result.block
    assert f'type="topic_assertion" id="{assertion.id}"' in result.block
    assert 'type="assertion"' not in result.block
    assert result.context_update["pinned_count"] == 1


async def test_rejected_assertion_remains_a_dynamic_guardrail(
    db_session: AsyncSession,
    monkeypatch: pytest.MonkeyPatch,
):
    primary, evidence_thread, topic, _, assertion = await _pinned_assertion_fixture(db_session)
    assertion.status = "rejected"
    db_session.add(
        TopicExclusion(
            id=str(uuid.uuid4()),
            user_id=OWNER,
            topic_id=topic.id,
            scope="assertion",
            target_id=assertion.id,
            origin="explicit_user_statement",
            reason="Explicitly rejected by the user",
            is_privacy_deletion=False,
        )
    )
    await db_session.commit()
    monkeypatch.setattr("app.topics.topic_context_compiler.get_settings", _settings)

    result = await TopicContextCompiler(
        db_session,
        embedding_provider=_NoEmbeddings(),
    ).compile(primary, current_query="launch route")

    assert ASSERTION_CONTENT not in result.block
    assert "Do not reintroduce a previously rejected option" in result.block
    assert result.context_update["pinned_count"] == 0
    assert result.context_update["dynamic_count"] == 1


async def test_excluding_a_related_topic_does_not_suppress_the_active_topic(
    db_session: AsyncSession,
    monkeypatch: pytest.MonkeyPatch,
):
    primary, evidence_thread, topic, _, assertion = await _pinned_assertion_fixture(db_session)
    related = Topic(
        id=str(uuid.uuid4()),
        user_id=OWNER,
        label="Unrelated private project",
        normalized_label="unrelated private project",
    )
    db_session.add(related)
    await db_session.flush()
    related_message = await _message(
        db_session,
        evidence_thread,
        "The excluded related topic says to use the ember detour.",
    )
    db_session.add_all(
        [
            TopicRelation(
                id=str(uuid.uuid4()),
                user_id=OWNER,
                source_topic_id=topic.id,
                target_topic_id=related.id,
                relation_type="related",
                confidence=0.9,
            ),
            TopicExclusion(
                id=str(uuid.uuid4()),
                user_id=OWNER,
                topic_id=related.id,
                scope="topic",
                target_id=related.id,
                origin="context_panel",
            ),
            MessageTopic(
                message_id=related_message.id,
                topic_id=related.id,
                confidence=0.9,
                is_primary=True,
                segment_start=0,
                segment_end=len(related_message.content),
                source_authority="explicit_user_statement",
            ),
            TopicExclusion(
                id=str(uuid.uuid4()),
                user_id=OWNER,
                topic_id=related.id,
                scope="concept",
                target_id="orchid route",
                origin="context_panel",
            ),
        ]
    )
    await db_session.commit()
    monkeypatch.setattr("app.topics.topic_context_compiler.get_settings", _settings)

    result = await TopicContextCompiler(
        db_session,
        embedding_provider=_NoEmbeddings(),
    ).compile(primary, current_query="launch route")

    assert assertion.id in {source["id"] for source in result.snapshot["sources"]}
    assert ASSERTION_CONTENT in result.block
    assert related_message.id not in {source["id"] for source in result.snapshot["sources"]}
    assert "ember detour" not in result.block


async def test_active_topic_concept_exclusion_blocks_raw_and_pinned_messages(
    db_session: AsyncSession,
    monkeypatch: pytest.MonkeyPatch,
):
    primary, evidence_thread, topic, _, assertion = await _pinned_assertion_fixture(db_session)
    raw_message = await _message(
        db_session,
        evidence_thread,
        "The orchid route should appear through neither raw evidence nor a pin.",
    )
    db_session.add_all(
        [
            MessageTopic(
                message_id=raw_message.id,
                topic_id=topic.id,
                confidence=0.95,
                is_primary=True,
                segment_start=0,
                segment_end=len(raw_message.content),
                source_authority="explicit_user_statement",
            ),
            ActiveContextItem(
                id=str(uuid.uuid4()),
                conversation_id=primary.id,
                source_type="message",
                source_id=raw_message.id,
                state="pinned",
                reason="Pinned by you",
            ),
            TopicExclusion(
                id=str(uuid.uuid4()),
                user_id=OWNER,
                topic_id=topic.id,
                scope="concept",
                target_id="orchid route",
                origin="context_panel",
            ),
        ]
    )
    await db_session.commit()
    monkeypatch.setattr("app.topics.topic_context_compiler.get_settings", _settings)

    result = await TopicContextCompiler(
        db_session,
        embedding_provider=_NoEmbeddings(),
    ).compile(primary, current_query="orchid route")

    source_ids = {source["id"] for source in result.snapshot["sources"]}
    assert assertion.id not in source_ids
    assert raw_message.id not in source_ids
    assert "orchid route" not in result.block.casefold()


async def test_priority_sources_cannot_exceed_the_rendered_context_budget(
    db_session: AsyncSession,
    monkeypatch: pytest.MonkeyPatch,
):
    primary, _, _, _, assertion = await _pinned_assertion_fixture(db_session)
    assertion.content = "distinctive oversized pinned fact " * 600
    await db_session.commit()
    settings = Settings(
        secret_key="test-secret-key-do-not-use-in-prod",
        database_url="sqlite+aiosqlite:///:memory:",
        topic_context_enabled=True,
        topic_context_token_budget=80,
    )
    monkeypatch.setattr(
        "app.topics.topic_context_compiler.get_settings",
        lambda: settings,
    )

    result = await TopicContextCompiler(
        db_session,
        embedding_provider=_NoEmbeddings(),
    ).compile(primary, current_query="oversized fact")

    assert result.snapshot["token_total"] <= settings.topic_context_token_budget


@pytest.mark.parametrize(
    "invalidation",
    [
        "expired",
        "superseded",
        "source_excluded",
        "evidence_deleted",
        "concept_excluded",
    ],
)
async def test_pinned_assertion_is_omitted_after_hard_invalidation(
    db_session: AsyncSession,
    monkeypatch: pytest.MonkeyPatch,
    invalidation: str,
):
    primary, evidence_thread, topic, evidence, assertion = await _pinned_assertion_fixture(
        db_session
    )
    if invalidation == "expired":
        assertion.valid_until = datetime.now(UTC) - timedelta(seconds=1)
    elif invalidation == "superseded":
        replacement_evidence = await _message(
            db_session,
            evidence_thread,
            "Use the cedar route instead.",
        )
        replacement = await _assertion(
            db_session,
            topic,
            replacement_evidence,
            "Use the cedar route for the launch itinerary.",
        )
        assertion.superseded_by_id = replacement.id
    elif invalidation == "source_excluded":
        db_session.add(
            TopicExclusion(
                id=str(uuid.uuid4()),
                user_id=OWNER,
                topic_id=topic.id,
                scope="source",
                target_id=evidence.id,
                origin="context_panel",
            )
        )
    elif invalidation == "evidence_deleted":
        await db_session.delete(evidence)
    elif invalidation == "concept_excluded":
        db_session.add(
            TopicExclusion(
                id=str(uuid.uuid4()),
                user_id=OWNER,
                topic_id=topic.id,
                scope="concept",
                target_id="orchid route",
                origin="context_panel",
            )
        )
    await db_session.commit()
    monkeypatch.setattr("app.topics.topic_context_compiler.get_settings", _settings)

    result = await TopicContextCompiler(
        db_session,
        embedding_provider=_NoEmbeddings(),
    ).compile(primary, current_query="launch route")

    assert result.snapshot["fallback"] != "recent_turns"
    assert ASSERTION_CONTENT not in result.block
    assert all(source["id"] != assertion.id for source in result.snapshot["sources"])
    assert result.context_update["pinned_count"] == 0
