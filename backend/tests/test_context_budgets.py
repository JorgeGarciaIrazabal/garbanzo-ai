"""Tests for context-window resolution and memory/KB token budgets."""

from collections.abc import AsyncIterator
from types import SimpleNamespace

import pytest

from app.core.config import Settings
from app.schemas.chat import ChatOptions
from app.services.chat_service import ChatService
from app.services.conversation_service import ConversationService
from app.services.knowledge_base_service import RetrievedChunk
from app.services.llm_provider import (
    ChatChunk,
    LLMProvider,
    ModelInfo,
    ProviderRegistry,
)

pytestmark = pytest.mark.asyncio


async def _always_empty(*args, **kwargs):
    return []


# ============================================================================
# _get_context_length
# ============================================================================


class _FixedContextProvider(LLMProvider):
    def __init__(self, context_length=None, raise_on_lookup=False):
        self._context_length = context_length
        self._raise = raise_on_lookup
        self.last_options: ChatOptions | None = None

    @property
    def name(self) -> str:
        return "fixed-context"

    async def get_model_context_length(self, model: str) -> int | None:
        if self._raise:
            raise RuntimeError("provider down")
        return self._context_length

    async def stream_chat(
        self, messages, model, options=None, cancel_event=None, tools=None
    ) -> AsyncIterator[ChatChunk]:
        self.last_options = options
        yield ChatChunk(content="hi", is_finished=False)
        yield ChatChunk(content="", is_finished=True, metadata={"tokens_generated": 1})

    async def chat(self, messages, model, options=None, tools=None) -> str:  # pragma: no cover
        return ""

    async def list_models(self) -> list[ModelInfo]:  # pragma: no cover
        return []

    async def health_check(self) -> bool:  # pragma: no cover
        return True


def _service_with_provider(db_session, provider) -> ChatService:
    service = ChatService(db_session, provider_name=provider.name)
    ProviderRegistry.register(provider)
    return service


async def test_context_length_capped_by_settings(db_session):
    service = _service_with_provider(db_session, _FixedContextProvider(131072))
    assert await service._get_context_length("any-model") == Settings().llm_context_window


async def test_context_length_uses_model_max_when_below_cap(db_session):
    service = _service_with_provider(db_session, _FixedContextProvider(2048))
    assert await service._get_context_length("any-model") == 2048


async def test_context_length_falls_back_to_heuristic_when_unknown(db_session):
    service = _service_with_provider(db_session, _FixedContextProvider(None))
    # "7b" in the name → 8192 heuristic
    assert await service._get_context_length("somemodel:7b") == 8192


async def test_context_length_survives_provider_errors(db_session):
    service = _service_with_provider(
        db_session, _FixedContextProvider(raise_on_lookup=True)
    )
    assert await service._get_context_length("somemodel:1b") == 4096


# ============================================================================
# num_ctx allocation + context_length stamping on the done chunk
# ============================================================================


async def test_stream_sets_num_ctx_and_stamps_context_length(
    db_session, test_user_email
):
    provider = _FixedContextProvider(2048)
    service = _service_with_provider(db_session, provider)
    conv = await ConversationService(db_session).create(
        user_id=test_user_email, title="ctx test"
    )
    conv.enabled_tools = []
    await db_session.commit()

    chunks = []
    async for chunk in service.send_message(conv.id, test_user_email, "hello"):
        chunks.append(chunk)

    assert provider.last_options is not None
    assert provider.last_options.num_ctx == 2048

    done = chunks[-1]
    assert done.is_finished
    assert done.metadata["context_length"] == 2048


async def test_client_num_ctx_is_clamped_to_server_ceiling(
    db_session, test_user_email
):
    """A client may shrink the window but never grow it past the server's
    effective context — an oversized num_ctx would make the runtime allocate
    an arbitrarily large KV cache."""
    provider = _FixedContextProvider(2048)
    service = _service_with_provider(db_session, provider)
    conv = await ConversationService(db_session).create(
        user_id=test_user_email, title="clamp test"
    )
    conv.enabled_tools = []
    await db_session.commit()

    async for _ in service.send_message(
        conv.id, test_user_email, "hello", options=ChatOptions(num_ctx=1_000_000)
    ):
        pass
    assert provider.last_options.num_ctx == 2048

    async for _ in service.send_message(
        conv.id, test_user_email, "hello", options=ChatOptions(num_ctx=1024)
    ):
        pass
    assert provider.last_options.num_ctx == 1024


# ============================================================================
# Memory / KB token budgets
# ============================================================================


def _patch_settings(monkeypatch, **overrides):
    settings = Settings(**overrides)
    monkeypatch.setattr(
        "app.services.chat_service.get_settings", lambda: settings
    )


async def test_memory_budget_trims_overflow(db_session, monkeypatch):
    service = ChatService(db_session)
    _patch_settings(monkeypatch, memory_token_budget=30)

    long = "word " * 100  # ~130 tokens each — only the first fits
    memories = [
        SimpleNamespace(content=f"memory-one {long}"),
        SimpleNamespace(content=f"memory-two {long}"),
        SimpleNamespace(content=f"memory-three {long}"),
    ]

    async def fake_memories(*args, **kwargs):
        return memories

    monkeypatch.setattr(service._memories, "get_relevant_memories", fake_memories)
    service._kb.search = _always_empty  # type: ignore[assignment]

    prompt, _stats = await service._build_system_prompt(
        user_id="test@example.com", use_memory=True, use_knowledge_base=False
    )

    # The first memory is always kept, even over budget; the rest are dropped.
    assert "memory-one" in prompt
    assert "memory-two" not in prompt
    assert "memory-three" not in prompt


async def test_memory_within_budget_all_injected(db_session, monkeypatch):
    service = ChatService(db_session)
    _patch_settings(monkeypatch, memory_token_budget=1000)

    memories = [
        SimpleNamespace(content="likes Python"),
        SimpleNamespace(content="works at Acme"),
    ]

    async def fake_memories(*args, **kwargs):
        return memories

    monkeypatch.setattr(service._memories, "get_relevant_memories", fake_memories)
    service._kb.search = _always_empty  # type: ignore[assignment]

    prompt, _stats = await service._build_system_prompt(
        user_id="test@example.com", use_memory=True, use_knowledge_base=False
    )

    assert "likes Python" in prompt
    assert "works at Acme" in prompt


async def test_kb_budget_trims_overflow(db_session, monkeypatch):
    service = ChatService(db_session)
    _patch_settings(monkeypatch, kb_token_budget=50)
    service._memories.get_relevant_memories = _always_empty  # type: ignore[assignment]

    long = "data " * 200  # ~260 tokens each — only the first chunk fits
    matches = [
        RetrievedChunk(
            document_id="d1",
            document_filename="first.pdf",
            content=f"chunk-one {long}",
            score=0.9,
        ),
        RetrievedChunk(
            document_id="d2",
            document_filename="second.pdf",
            content=f"chunk-two {long}",
            score=0.8,
        ),
    ]

    async def fake_search(*args, **kwargs):
        return matches

    monkeypatch.setattr(service._kb, "search", fake_search)

    prompt, _stats = await service._build_system_prompt(
        user_id="test@example.com",
        use_memory=False,
        use_knowledge_base=True,
        rag_query="anything",
    )

    assert "chunk-one" in prompt
    assert "first.pdf" in prompt
    assert "chunk-two" not in prompt
