"""Unit tests for RAG injection into the chat system prompt."""

import pytest

from app.services.chat_service import ChatService
from app.services.knowledge_base_service import RetrievedChunk

pytestmark = pytest.mark.asyncio


async def _make_service(db_session):
    svc = ChatService(db_session)
    # Keep memories out of the equation so we assert only KB content.
    svc._memories.get_relevant_memories = _always_empty  # type: ignore[assignment]
    return svc


async def _always_empty(*args, **kwargs):
    return []


async def _fake_matches(*_args, **_kwargs):
    return [
        RetrievedChunk(
            document_id="doc-1",
            document_filename="report.pdf",
            content="Quarterly revenue was $42M.",
            score=0.91,
        ),
        RetrievedChunk(
            document_id="doc-2",
            document_filename="notes.txt",
            content="Team met on Tuesday to discuss Q2 plans.",
            score=0.83,
        ),
    ]


async def _no_matches(*_args, **_kwargs):
    return []


async def test_rag_chunks_are_injected_when_enabled(db_session, monkeypatch):
    service = await _make_service(db_session)
    monkeypatch.setattr(service._kb, "search", _fake_matches)

    prompt, _stats = await service._context.build_system_prompt(
        user_id="test@example.com",
        use_memory=False,
        use_knowledge_base=True,
        rag_query="Tell me about Q2",
        conversation_system_prompt="You are a helpful assistant.",
    )

    assert "You are a helpful assistant." in prompt
    assert "report.pdf" in prompt
    assert "Quarterly revenue was $42M." in prompt
    assert "notes.txt" in prompt
    assert "Q2 plans" in prompt


async def test_rag_is_skipped_when_disabled(db_session, monkeypatch):
    service = await _make_service(db_session)
    monkeypatch.setattr(service._kb, "search", _fake_matches)

    prompt, _stats = await service._context.build_system_prompt(
        user_id="test@example.com",
        use_memory=False,
        use_knowledge_base=False,
        rag_query="Tell me about Q2",
        conversation_system_prompt="You are a helpful assistant.",
    )

    assert prompt == "You are a helpful assistant."
    assert "report.pdf" not in prompt


async def test_rag_skipped_when_query_is_empty(db_session, monkeypatch):
    service = await _make_service(db_session)
    called = {"hit": False}

    async def _search(*a, **kw):
        called["hit"] = True
        return await _fake_matches()

    monkeypatch.setattr(service._kb, "search", _search)

    prompt, _stats = await service._context.build_system_prompt(
        user_id="test@example.com",
        use_memory=False,
        use_knowledge_base=True,
        rag_query=None,
        conversation_system_prompt="You are a helpful assistant.",
    )
    assert prompt == "You are a helpful assistant."
    assert called["hit"] is False


async def test_rag_block_omitted_when_no_matches(db_session, monkeypatch):
    service = await _make_service(db_session)
    monkeypatch.setattr(service._kb, "search", _no_matches)

    prompt, _stats = await service._context.build_system_prompt(
        user_id="test@example.com",
        use_memory=False,
        use_knowledge_base=True,
        rag_query="anything",
        conversation_system_prompt="Base prompt.",
    )
    assert prompt == "Base prompt."


async def test_rag_uses_default_prompt_when_base_is_empty(db_session, monkeypatch):
    service = await _make_service(db_session)
    monkeypatch.setattr(service._kb, "search", _fake_matches)

    prompt, _stats = await service._context.build_system_prompt(
        user_id="test@example.com",
        use_memory=False,
        use_knowledge_base=True,
        rag_query="Tell me about Q2",
        conversation_system_prompt=None,
    )
    assert prompt.startswith("You are a helpful AI assistant.")
    assert "report.pdf" in prompt


async def test_rag_error_swallowed_and_returns_base_prompt(db_session, monkeypatch):
    service = await _make_service(db_session)

    async def _boom(*a, **kw):
        raise RuntimeError("vector db exploded")

    monkeypatch.setattr(service._kb, "search", _boom)

    prompt, _stats = await service._context.build_system_prompt(
        user_id="test@example.com",
        use_memory=False,
        use_knowledge_base=True,
        rag_query="something",
        conversation_system_prompt="Base prompt.",
    )
    assert prompt == "Base prompt."


async def test_kb_sources_collected_into_stats(db_session, monkeypatch):
    """Distinct source filenames of injected chunks are reported in stats so
    the client can render citation chips."""
    service = await _make_service(db_session)
    monkeypatch.setattr(service._kb, "search", _fake_matches)

    _prompt, stats = await service._context.build_system_prompt(
        user_id="test@example.com",
        use_memory=False,
        use_knowledge_base=True,
        rag_query="Tell me about Q2",
        conversation_system_prompt="You are a helpful assistant.",
    )

    assert stats["kb_chunks_used"] == 2
    assert stats["kb_sources"] == ["report.pdf", "notes.txt"]
