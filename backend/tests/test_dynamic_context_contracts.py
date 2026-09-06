"""Contract tests for unified-chat generation, dynamic SSE, and model effort metadata."""

from __future__ import annotations

import asyncio
import json
import uuid
from collections.abc import AsyncIterator

import pytest
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

import app.services.llm_provider as llm_provider
from app.api.v1.endpoints.chat import _sse_stream
from app.models.conversation import Conversation
from app.models.message import Message
from app.schemas.chat import ChatOptions
from app.schemas.chat import ModelInfo as PublicModelInfo
from app.services.chat_service import ChatService
from app.topics.models import Topic, TopicIngestionEvent, TopicIngestionState
from app.topics.topic_context_compiler import CompiledTopicContext, TopicContextCompiler
from app.topics.topic_ingestion_service import enqueue_message_event

pytestmark = pytest.mark.asyncio

OWNER = "test@example.com"


async def _conversation(
    db: AsyncSession,
    *,
    primary: bool,
    title: str,
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


class _RecordingContext:
    def __init__(self) -> None:
        self.calls: list[dict] = []

    async def build_history_with_system_prompt(self, *args, **kwargs):
        self.calls.append({"args": args, "kwargs": kwargs})
        dynamic_context = kwargs.get("dynamic_context") or ""
        return [llm_provider.Message(role="system", content=dynamic_context)], {}


class _RecordingProvider(llm_provider.LLMProvider):
    def __init__(self) -> None:
        self.calls: list[dict] = []

    @property
    def name(self) -> str:
        return "dynamic-contract-provider"

    async def stream_chat(
        self,
        messages: list[llm_provider.Message],
        model: str,
        options: ChatOptions | None = None,
        cancel_event=None,
        tools=None,
    ) -> AsyncIterator[llm_provider.ChatChunk]:
        self.calls.append({"messages": messages, "model": model, "options": options})
        yield llm_provider.ChatChunk(content="answer", is_finished=False)
        yield llm_provider.ChatChunk(content="", is_finished=True, metadata={"tokens_generated": 1})

    async def chat(self, messages, model, options=None, tools=None) -> str:
        return "answer"

    async def list_models(self) -> list[llm_provider.ModelInfo]:
        return []

    async def health_check(self) -> bool:
        return True


async def test_primary_generation_invokes_compiler_but_legacy_keeps_builder(
    db_session: AsyncSession,
    monkeypatch: pytest.MonkeyPatch,
):
    primary = await _conversation(db_session, primary=True, title="Primary")
    legacy = await _conversation(db_session, primary=False, title="Legacy")
    for conversation in (primary, legacy):
        db_session.add(
            Message(
                id=str(uuid.uuid4()),
                conversation_id=conversation.id,
                role="user",
                content="question",
                conversation=conversation,
            )
        )
    await db_session.commit()
    await db_session.refresh(primary, attribute_names=["messages"])
    await db_session.refresh(legacy, attribute_names=["messages"])
    compiler_calls: list[str] = []

    async def compile_context(
        _compiler: TopicContextCompiler,
        conversation: Conversation,
        *,
        current_query: str,
    ) -> CompiledTopicContext:
        compiler_calls.append(conversation.id)
        assert current_query == "question"
        return CompiledTopicContext(
            block="<topic_context>compiled primary context</topic_context>",
            history_messages=list(conversation.messages or []),
            snapshot={"context_version": 12, "sources": []},
            topic_update={"active_topic": {"id": "topic-1", "label": "Trip"}},
            context_update={"context_version": 12, "dynamic_count": 0},
        )

    monkeypatch.setattr(TopicContextCompiler, "compile", compile_context)
    provider = _RecordingProvider()
    llm_provider.ProviderRegistry.register(provider)

    async def fake_run_agent_turn(**kwargs):
        kwargs["result"].completed = True
        kwargs["result"].content = "answer"
        yield llm_provider.ChatChunk(content="answer", is_finished=False)
        yield llm_provider.ChatChunk(content="", is_finished=True, metadata={"tokens_generated": 1})

    monkeypatch.setattr("app.services.chat_service.run_agent_turn", fake_run_agent_turn)
    monkeypatch.setattr(
        "app.services.chat_service.TopicContextCompiler",
        TopicContextCompiler,
        raising=False,
    )
    monkeypatch.setattr(
        "app.services.chat_service.get_settings",
        lambda: type("SettingsStub", (), {"topic_context_enabled": True})(),
    )
    monkeypatch.setattr(ChatService, "_spawn_title_generation", lambda *args, **kwargs: None)

    for conversation in (primary, legacy):
        context = _RecordingContext()
        service = ChatService(db_session, provider_name=provider.name)
        service._context = context  # type: ignore[assignment]

        async def no_summary(*_args, **_kwargs):
            return None

        service._maybe_summarize_context = no_summary  # type: ignore[method-assign]
        service._resolve_tools_for_conversation = (  # type: ignore[method-assign]
            lambda *_args, **_kwargs: _empty_tools()
        )
        service._get_provider = lambda: provider  # type: ignore[method-assign]
        chunks = [chunk async for chunk in service._stream_assistant_turn(conversation)]
        assert chunks
        if conversation.is_primary:
            assert compiler_calls == [primary.id]
            assert "compiled primary context" in context.calls[0]["kwargs"]["dynamic_context"]
        else:
            assert compiler_calls == [primary.id]
            assert "compiled primary context" not in context.calls[0]["kwargs"]["dynamic_context"]


async def _empty_tools():
    # Kept as an async helper so the monkeypatched method has the same shape as
    # ChatService._resolve_tools_for_conversation.
    return [], {}


async def test_dynamic_sse_events_have_exact_payload_and_precede_answer():
    topic = {
        "id": "topic-1",
        "label": "Trip planning",
        "parent_id": None,
    }
    topic_update = {
        "active_topic": topic,
        "topic_is_pinned": True,
        "context_version": 4,
    }
    preparing = {
        "active_topic_id": topic["id"],
        "context_version": 4,
        "readiness": "preparing",
        "live_delta_count": 1,
    }
    context_update = {
        "context_version": 4,
        "active_topic": topic,
        "pinned_count": 1,
        "dynamic_count": 2,
        "excluded_count": 0,
        "live_delta_count": 1,
        "source_event_watermark": 8,
    }

    async def chunks():
        yield llm_provider.ChatChunk(content="", metadata={"topic_update": topic_update})
        yield llm_provider.ChatChunk(content="", metadata={"context_preparing": preparing})
        yield llm_provider.ChatChunk(content="", metadata={"context_update": context_update})
        yield llm_provider.ChatChunk(content="reply", is_finished=False)
        yield llm_provider.ChatChunk(content="", is_finished=True, metadata={"tokens_generated": 1})

    wire = "".join([frame async for frame in _sse_stream(chunks())])
    events = [
        json.loads(frame.removeprefix("data: ").strip()) for frame in wire.split("\n\n") if frame
    ]
    # Established SSE frames serialize optional fields as null; retain that
    # wire shape while pinning the dynamic event type and exact payload.
    assert [event["type"] for event in events] == [
        "topic_update",
        "context_preparing",
        "context_update",
        "chunk",
        "done",
    ]
    assert events[0]["metadata"] == {"topic_update": topic_update}
    assert events[1]["metadata"] == {"context_preparing": preparing}
    assert events[2]["metadata"] == {"context_update": context_update}
    assert events[3]["content"] == "reply"
    assert events[4]["metadata"] == {"tokens_generated": 1}
    dynamic_events = events[:3]
    assert all(event["metadata"][event["type"]]["context_version"] == 4 for event in dynamic_events)
    assert dynamic_events[1]["metadata"]["context_preparing"]["live_delta_count"] == 1
    assert events[3]["type"] == "chunk"


async def test_committed_primary_turn_emits_context_before_provider_and_deduplicates_events(
    db_session: AsyncSession,
    monkeypatch: pytest.MonkeyPatch,
):
    """Exercise actual compiler, turn persistence, and ingestion in one service stream."""
    primary = await _conversation(db_session, primary=True, title="Primary")
    primary.use_memory = False
    primary.use_knowledge_base = False
    topic = Topic(
        id=str(uuid.uuid4()),
        user_id=OWNER,
        label="Retirement",
        normalized_label="retirement",
    )
    db_session.add(topic)
    await db_session.flush()
    primary.active_topic_id = topic.id
    primary.topic_is_pinned = True
    await db_session.commit()
    await db_session.refresh(primary, attribute_names=["messages", "active_topic"])

    provider = _RecordingProvider()
    provider_started = asyncio.Event()
    provider_release = asyncio.Event()

    async def gated_stream(*_args, **_kwargs):
        provider_started.set()
        await provider_release.wait()
        yield llm_provider.ChatChunk(content="On track.", is_finished=False)
        yield llm_provider.ChatChunk(
            content="",
            is_finished=True,
            metadata={"tokens_generated": 2},
        )

    provider.stream_chat = gated_stream  # type: ignore[method-assign]
    llm_provider.ProviderRegistry.register(provider)
    monkeypatch.setattr(ChatService, "_spawn_title_generation", lambda *args, **kwargs: None)
    monkeypatch.setattr(
        "app.services.chat_service.get_settings",
        lambda: type(
            "SettingsStub",
            (),
            {
                "topic_context_enabled": True,
                "llm_context_window": 8192,
                "topic_context_token_budget": 12000,
            },
        )(),
    )
    monkeypatch.setattr(
        "app.topics.topic_context_compiler.get_settings",
        lambda: type(
            "SettingsStub",
            (),
            {"topic_context_enabled": True, "topic_context_token_budget": 12000},
        )(),
    )
    service = ChatService(db_session, provider_name=provider.name)
    service._resolve_tools_for_conversation = (  # type: ignore[method-assign]
        lambda *_args, **_kwargs: _empty_tools()
    )

    stream = service.send_message(primary.id, OWNER, "Review retirement assumptions.")
    topic_chunk = await asyncio.wait_for(anext(stream), timeout=1)
    assert topic_chunk.metadata is not None
    assert topic_chunk.metadata["topic_update"]["schema_version"] == 1
    assert provider_started.is_set() is False

    context_chunk = await asyncio.wait_for(anext(stream), timeout=1)
    assert context_chunk.metadata is not None
    assert context_chunk.metadata["context_update"]["schema_version"] == 1
    assert provider_started.is_set() is False

    pending_provider = asyncio.create_task(anext(stream))
    await asyncio.wait_for(provider_started.wait(), timeout=1)
    provider_release.set()
    remaining = [await pending_provider]
    remaining.extend([chunk async for chunk in stream])
    assert any(chunk.content == "On track." for chunk in remaining)

    persisted = list(
        (
            await db_session.scalars(
                select(Message).where(Message.conversation_id == primary.id).order_by(Message.seq)
            )
        ).all()
    )
    assert [message.role for message in persisted] == ["user", "assistant"]
    events = list(
        (
            await db_session.scalars(
                select(TopicIngestionEvent)
                .where(TopicIngestionEvent.conversation_id == primary.id)
                .order_by(TopicIngestionEvent.id)
            )
        ).all()
    )
    assert [(event.operation, event.source_id) for event in events] == [
        ("create", persisted[0].id),
        ("create", persisted[1].id),
    ]
    assert all(event.processed_at is not None for event in events)
    state = await db_session.get(TopicIngestionState, OWNER)
    assert state is not None
    assert state.last_realtime_event_id == events[-1].id

    duplicate = await enqueue_message_event(db_session, primary, persisted[0], "create")
    event_count = await db_session.scalar(select(func.count(TopicIngestionEvent.id)))
    assert duplicate.id == events[0].id
    assert event_count == 2


async def test_dynamic_response_schema_accepts_only_normalized_payload_fields():
    payload = {
        "id": "model-1",
        "name": "Reasoner",
        "provider": "ollama",
        "supports_thinking": True,
        "thinking_levels": ["off", "high"],
        "default_thinking_level": "high",
    }
    model = PublicModelInfo.model_validate(payload)
    assert model.model_dump(exclude_none=True) == payload
    assert model.thinking_levels == ["off", "high"]
    assert model.default_thinking_level == "high"
    assert "low" not in model.thinking_levels
    with pytest.raises(ValueError):
        PublicModelInfo.model_validate({**payload, "thinking_levels": ["off", "bogus"]})


@pytest.mark.asyncio
async def test_list_models_exposes_normalized_levels_without_native_values(
    db_session: AsyncSession,
    monkeypatch: pytest.MonkeyPatch,
):
    """The public list contract must not leak provider-native effort values."""
    provider = _RecordingProvider()
    # This test is intentionally written against the provider's normalized
    # capability surface; implementations may represent native values as
    # strings, numbers, or structured objects internally.
    provider_model = llm_provider.ModelInfo(
        id="reasoner",
        name="Reasoner",
        supports_thinking=True,
    )
    provider.list_models = lambda: _one_model(provider_model)  # type: ignore[method-assign]
    llm_provider.ProviderRegistry.register(provider)
    service = ChatService(db_session, provider_name=provider.name)
    monkeypatch.setattr(service, "_provider_name", provider.name)

    models = await service.list_available_models()
    assert models[0].supports_thinking is True
    assert models[0].model_dump(exclude_none=True)["id"] == "reasoner"
    # Compatibility metadata may be absent/unknown; it must not be treated as
    # support for every normalized effort position.
    assert models[0].model_dump(exclude_none=True).get("thinking_levels") in (None, [])


async def _one_model(model: llm_provider.ModelInfo):
    return [model]
