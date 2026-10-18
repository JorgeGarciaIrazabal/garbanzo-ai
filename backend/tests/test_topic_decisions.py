"""Decision routing cannot override context ownership, pins or topic choices."""

from types import SimpleNamespace
from unittest.mock import AsyncMock

import pytest
from sqlalchemy import select, update

from app.core.config import Settings
from app.models.conversation import Conversation
from app.models.message import Message
from app.models.user import User
from app.services.decision_service import DecisionError
from app.topics.models import MessageTopic, Topic, TopicExclusion
from app.topics.topic_context_compiler import TopicContextCompiler, _Candidate, _PrimarySelection

pytestmark = pytest.mark.asyncio


def candidate(id, *, group=None, pinned=False, required=False, content=None):
    return _Candidate(
        "message",
        id,
        content or id,
        "evidence",
        0.8,
        pinned=pinned,
        required=required,
        group_id=group,
    )


@pytest.fixture
def decisions(monkeypatch):
    settings = Settings(
        _env_file=None, topic_decisions_enabled=True, topic_context_privacy_mode="cloud_allowed"
    )
    monkeypatch.setattr("app.topics.topic_context_compiler.get_settings", lambda: settings)
    monkeypatch.setattr("app.topics.topic_semantic_curator.get_settings", lambda: settings)
    client = SimpleNamespace(probabilities=AsyncMock())
    monkeypatch.setattr("app.topics.topic_context_compiler.get_decision_service", lambda: client)
    return settings, client


async def topic_conversation(db):
    owner = await db.scalar(select(Conversation.user_id).limit(1))
    if owner is None:
        owner = (await db.scalars(select(User.email))).first()
    topic = Topic(
        id="active",
        user_id=owner,
        label="Cooking",
        normalized_label="cooking",
        centroid_embedding=[1.0] + [0.0] * 767,
    )
    db.add(topic)
    await db.flush()
    conversation = Conversation(
        id="thread", user_id=owner, model="test-model", active_topic_id=topic.id
    )
    db.add(conversation)
    await db.commit()
    await db.refresh(conversation, attribute_names=["messages"])
    return topic, conversation


async def test_optional_units_preserve_pins_required_and_complete_groups(
    db_session, decisions, monkeypatch
):
    _, client = decisions
    topic, conversation = await topic_conversation(db_session)
    items = [
        candidate("pin", pinned=True),
        candidate("guard", required=True),
        candidate("a", group="one"),
        candidate("b", group="one"),
        candidate("drop"),
    ]
    selection = _PrimarySelection(items, [], None, False)
    compiler = TopicContextCompiler(db_session, embedding_provider=None)
    compiler._refresh_decision_sources = AsyncMock()
    compiler._select_primary_candidates = AsyncMock(return_value=selection)
    client.probabilities.return_value = {"unit_0": 0.9, "unit_1": 0.5}
    result = await compiler._relevance_decisions(conversation, topic, selection, "help", None)
    assert [c.source_id for c in result] == ["pin", "guard", "a", "b"]
    assert len(client.probabilities.await_args.kwargs["questions"]) == 2
    state = client.probabilities.await_args.kwargs["state"]
    assert all("pin" not in str(v) and "guard" not in str(v) for v in state["units"].values())
    assert conversation.active_topic_id == topic.id


async def test_no_optional_context_makes_no_call(db_session, decisions):
    _, client = decisions
    topic, conversation = await topic_conversation(db_session)
    items = [
        candidate("pin", pinned=True),
        candidate("same-group", group="g", required=True),
        candidate("part-of-protected-group", group="g"),
    ]
    compiler = TopicContextCompiler(db_session, embedding_provider=None)
    assert (
        await compiler._relevance_decisions(
            conversation, topic, _PrimarySelection(items, [], None, False), "help", None
        )
        == items
    )
    client.probabilities.assert_not_awaited()


@pytest.mark.parametrize(
    "field,value",
    [("session_epoch", 1), ("context_version", 5), ("active_topic_id", None), ("is_deleted", True)],
)
async def test_decision_cannot_cross_context_change(db_session, decisions, field, value):
    _, client = decisions
    topic, conversation = await topic_conversation(db_session)
    compiler = TopicContextCompiler(db_session, embedding_provider=None)

    async def changed(**kwargs):
        await db_session.execute(
            update(Conversation).where(Conversation.id == conversation.id).values(**{field: value})
        )
        await db_session.flush()
        return {"unit_0": 1.0}

    client.probabilities.side_effect = changed
    with pytest.raises(DecisionError, match="changed|unavailable"):
        await compiler._relevance_decisions(
            conversation, topic, _PrimarySelection([candidate("a")], [], None, False), "help", None
        )


async def test_evidence_change_during_call_rejects_result(db_session, decisions):
    _, client = decisions
    topic, conversation = await topic_conversation(db_session)
    compiler = TopicContextCompiler(db_session, embedding_provider=None)
    compiler._refresh_decision_sources = AsyncMock()
    compiler._select_primary_candidates = AsyncMock(
        return_value=_PrimarySelection([], [], None, False)
    )
    client.probabilities.return_value = {"unit_0": 1.0}
    with pytest.raises(DecisionError, match="evidence changed"):
        await compiler._relevance_decisions(
            conversation,
            topic,
            _PrimarySelection([candidate("deleted")], [], None, False),
            "help",
            None,
        )


async def test_private_mode_and_disabled_decisions_never_call(decisions):
    settings, client = decisions
    settings.topic_context_privacy_mode = "local_only"
    assert not TopicContextCompiler._decisions_allowed()
    settings.topic_context_privacy_mode = "cloud_allowed"
    settings.topic_decisions_enabled = False
    assert not TopicContextCompiler._decisions_allowed()
    client.probabilities.assert_not_awaited()


async def test_typed_failure_is_not_sqlite_fallback(db_session, decisions):
    compiler = TopicContextCompiler(db_session, embedding_provider=None)
    compiler._compile_primary = AsyncMock(side_effect=DecisionError("unavailable"))
    conversation = SimpleNamespace(
        messages=[], session_epoch=0, is_primary=True, active_topic_id="a"
    )
    with pytest.raises(DecisionError, match="unavailable"):
        await compiler.compile(conversation, current_query="help")


@pytest.mark.parametrize("score,expected", [(0.9, True), (0.5, False), (0.1, False)])
async def test_drift_is_only_confirmed_advice(db_session, decisions, score, expected):
    _, client = decisions
    active, conversation = await topic_conversation(db_session)
    other = Topic(
        id="other",
        user_id=conversation.user_id,
        label="Travel",
        normalized_label="travel",
        centroid_embedding=[0.0, 1.0] + [0.0] * 766,
    )
    db_session.add(other)
    await db_session.commit()
    embedding = SimpleNamespace(embed=AsyncMock(return_value=[[0.0, 1.0] + [0.0] * 766]))
    compiler = TopicContextCompiler(db_session, embedding_provider=embedding)
    client.probabilities.return_value = {"drift": score}
    result = await compiler.detect_drift(conversation, "book a flight")
    assert bool(result) is expected
    assert conversation.active_topic_id == active.id
    if result:
        assert result["detected_topic_id"] == other.id


async def test_real_compiler_rejects_topic_switch_while_embedding(db_session, monkeypatch):
    settings = Settings(
        _env_file=None, topic_decisions_enabled=True, topic_context_privacy_mode="cloud_allowed"
    )
    monkeypatch.setattr("app.topics.topic_context_compiler.get_settings", lambda: settings)
    monkeypatch.setattr("app.topics.topic_semantic_curator.get_settings", lambda: settings)
    active = Topic(id="active", user_id="test@example.com", label="Old", normalized_label="old")
    other = Topic(id="other", user_id="test@example.com", label="New", normalized_label="new")
    db_session.add_all([active, other])
    await db_session.flush()
    conversation = Conversation(
        id="thread", user_id="test@example.com", model="test", active_topic_id=active.id
    )
    db_session.add(conversation)
    await db_session.flush()
    message = Message(
        id="evidence", conversation_id=conversation.id, role="user", content="old topic evidence"
    )
    db_session.add(message)
    await db_session.flush()
    db_session.add(MessageTopic(message_id=message.id, topic_id=active.id))
    await db_session.commit()

    async def embed(*args):
        await db_session.execute(
            update(Conversation)
            .where(Conversation.id == conversation.id)
            .values(active_topic_id=other.id, context_version=5)
            .execution_options(synchronize_session=False)
        )
        return []

    compiler = TopicContextCompiler(db_session, embedding_provider=SimpleNamespace(embed=embed))
    client = SimpleNamespace(probabilities=AsyncMock(return_value={"unit_0": 1.0}))
    monkeypatch.setattr("app.topics.topic_context_compiler.get_decision_service", lambda: client)
    with pytest.raises(DecisionError, match="changed"):
        await compiler._compile_primary(conversation, "help", [])


@pytest.mark.parametrize("tag", ["clef:27b-cloud", "clef:cloud", "clef:1017-cloud"])
async def test_size_and_dated_cloud_aliases_respect_local_privacy(decisions, tag):
    settings, client = decisions
    settings.topic_context_privacy_mode = "local_only"
    settings.decision_model = tag
    settings.ollama_base_url = "http://localhost:11434"
    assert not TopicContextCompiler._decisions_allowed()
    client.probabilities.assert_not_awaited()


@pytest.mark.parametrize("mutation", ["edit", "exclude"])
async def test_real_source_revalidation_after_decision(db_session, decisions, mutation):
    _, client = decisions
    topic, conversation = await topic_conversation(db_session)
    message = Message(
        id="real-source",
        conversation_id=conversation.id,
        role="user",
        content="The project uses PostgreSQL.",
    )
    db_session.add(message)
    await db_session.flush()
    db_session.add(MessageTopic(message_id=message.id, topic_id=topic.id))
    await db_session.commit()
    compiler = TopicContextCompiler(db_session, embedding_provider=None)

    async def classify(**kwargs):
        if mutation == "edit":
            await db_session.execute(
                update(Message)
                .where(Message.id == message.id)
                .values(content="The source was corrected.")
                .execution_options(synchronize_session=False)
            )
        else:
            db_session.add(
                TopicExclusion(
                    id="exclude-source",
                    user_id=conversation.user_id,
                    topic_id=topic.id,
                    scope="source",
                    target_id=message.id,
                    origin="user",
                )
            )
        await db_session.flush()
        return {key: 1.0 for key in kwargs["questions"]}

    client.probabilities.side_effect = classify
    with pytest.raises(DecisionError, match="evidence changed"):
        await compiler._compile_primary(conversation, "Which database?", [])
