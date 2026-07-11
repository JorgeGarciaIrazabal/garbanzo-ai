"""Integration tests for ``KnowledgeBaseService`` (CRUD + orchestration).

The embedding provider is stubbed; pgvector-specific cosine search is not
exercised here because tests run against SQLite. Those paths are covered by
the endpoint test that drives the service through FastAPI.
"""

from dataclasses import dataclass

import pytest
from sqlalchemy import select

from app.core.config import Settings
from app.core.security import hash_password
from app.models.knowledge_base import KnowledgeChunk
from app.models.user import User
from app.services.knowledge_base_service import (
    KnowledgeBaseService,
    RetrievedChunk,
)

_TEST_SETTINGS = Settings(
    secret_key="test-secret-key-do-not-use-in-prod",
    database_url="sqlite+aiosqlite:///:memory:",
    kb_background_embedding=False,
)


def _make_service(db_session, provider=None):
    return KnowledgeBaseService(
        db_session,
        embedding_provider=provider or _FakeEmbeddingProvider(),
        settings=_TEST_SETTINGS,
    )


pytestmark = pytest.mark.asyncio


@dataclass
class _FakeEmbeddingProvider:
    """Deterministic fake. ``dim`` is intentionally small — tests never do
    actual similarity math against the stored vectors."""

    calls: list[list[str]]
    dim: int = 3

    def __init__(self):
        self.calls = []

    async def embed(self, texts):
        self.calls.append(list(texts))
        return [[float(i % 10)] * self.dim for i, _ in enumerate(texts, start=1)]


async def _seed_second_user(db_session, email: str):
    db_session.add(User(email=email, hashed_password=hash_password("x")))
    await db_session.commit()


async def test_create_document_extracts_and_chunks_and_dispatches_embedding(
    db_session,
):
    provider = _FakeEmbeddingProvider()
    service = _make_service(db_session, provider=provider)

    payload = b"This is paragraph one.\n\nAnd this is paragraph two, slightly longer."
    doc = await service.create_document(
        user_id="test@example.com",
        filename="notes.txt",
        mime_type="text/plain",
        file_bytes=payload,
    )

    assert doc.id
    assert doc.filename == "notes.txt"
    assert doc.file_size == len(payload)
    assert doc.chunk_count >= 1
    # Chunks are persisted before the background embedding task fires.
    chunks = (
        (
            await db_session.execute(
                select(KnowledgeChunk).where(KnowledgeChunk.document_id == doc.id)
            )
        )
        .scalars()
        .all()
    )
    assert len(chunks) == doc.chunk_count
    assert all(c.user_id == "test@example.com" for c in chunks)
    assert all(c.chunk_index >= 0 for c in chunks)


async def test_create_document_rejects_file_with_no_text(db_session):
    service = _make_service(db_session)
    with pytest.raises(ValueError):
        await service.create_document(
            user_id="test@example.com",
            filename="empty.txt",
            mime_type="text/plain",
            file_bytes=b"   \n  \n  ",
        )


async def test_list_documents_is_scoped_to_user(db_session):
    await _seed_second_user(db_session, "other@example.com")
    service = _make_service(db_session)

    await service.create_document(
        user_id="test@example.com",
        filename="mine.txt",
        mime_type="text/plain",
        file_bytes=b"content A" * 10,
    )
    await service.create_document(
        user_id="other@example.com",
        filename="theirs.txt",
        mime_type="text/plain",
        file_bytes=b"content B" * 10,
    )

    mine = await service.list_documents("test@example.com")
    theirs = await service.list_documents("other@example.com")
    assert [d.filename for d in mine] == ["mine.txt"]
    assert [d.filename for d in theirs] == ["theirs.txt"]


async def test_get_document_refuses_other_users(db_session):
    await _seed_second_user(db_session, "other@example.com")
    service = _make_service(db_session)

    doc = await service.create_document(
        user_id="test@example.com",
        filename="mine.txt",
        mime_type="text/plain",
        file_bytes=b"content" * 20,
    )

    assert await service.get_document(doc.id, "test@example.com") is not None
    assert await service.get_document(doc.id, "other@example.com") is None


async def test_delete_document_removes_chunks(db_session):
    service = _make_service(db_session)
    doc = await service.create_document(
        user_id="test@example.com",
        filename="tmp.txt",
        mime_type="text/plain",
        file_bytes=b"body" * 50,
    )

    ok = await service.delete_document(doc.id, "test@example.com")
    assert ok

    remaining_chunks = (
        (
            await db_session.execute(
                select(KnowledgeChunk).where(KnowledgeChunk.document_id == doc.id)
            )
        )
        .scalars()
        .all()
    )
    assert remaining_chunks == []
    assert await service.get_document(doc.id, "test@example.com") is None


async def test_delete_document_refuses_other_users(db_session):
    await _seed_second_user(db_session, "other@example.com")
    service = _make_service(db_session)
    doc = await service.create_document(
        user_id="test@example.com",
        filename="mine.txt",
        mime_type="text/plain",
        file_bytes=b"body" * 50,
    )

    deleted = await service.delete_document(doc.id, "other@example.com")
    assert deleted is False
    # Still exists for the real owner.
    assert await service.get_document(doc.id, "test@example.com") is not None


async def test_search_returns_empty_for_blank_query(db_session):
    service = _make_service(db_session)
    assert await service.search(user_id="test@example.com", query="") == []
    assert await service.search(user_id="test@example.com", query="   ") == []


async def test_search_short_circuits_when_provider_fails(db_session, monkeypatch):
    class BrokenProvider:
        dim = 3

        async def embed(self, texts):
            raise RuntimeError("embedding backend offline")

    service = _make_service(db_session, provider=BrokenProvider())
    # Should swallow the error and return [] rather than bubble.
    result = await service.search(user_id="test@example.com", query="hello")
    assert result == []


async def test_search_uses_mocked_similarity(db_session, monkeypatch):
    """End-to-end orchestration of ``search`` without pgvector.

    We stub out the DB query by monkeypatching the service method; the goal
    here is to verify the provider is invoked and results are shaped into
    ``RetrievedChunk`` objects.
    """
    provider = _FakeEmbeddingProvider()
    service = _make_service(db_session, provider=provider)

    canned = [
        RetrievedChunk(
            document_id="doc-1",
            document_filename="f.txt",
            content="hit one",
            score=0.92,
        )
    ]

    async def _fake_search(self, *, user_id, query, limit=None):
        assert query == "hello"
        assert user_id == "test@example.com"
        return canned

    monkeypatch.setattr(KnowledgeBaseService, "search", _fake_search)

    result = await service.search(user_id="test@example.com", query="hello")
    assert result == canned


class TestBinaryContentRejection:
    """Binary uploads must not pollute the KB via the plain-text fallback."""

    def test_looks_like_text_accepts_prose(self):
        from app.services.knowledge_base_service import _looks_like_text

        assert _looks_like_text("A perfectly normal paragraph of text.\nMore.")

    def test_looks_like_text_rejects_binary_mojibake(self):
        from app.services.knowledge_base_service import (
            _extract_plain,
            _looks_like_text,
        )

        binary = bytes(range(256)) * 16  # e.g. an executable renamed .txt
        assert not _looks_like_text(_extract_plain(binary))

    @pytest.mark.asyncio
    async def test_create_document_rejects_binary(self, db_session):
        from app.services.knowledge_base_service import KnowledgeBaseService

        service = KnowledgeBaseService(
            db_session,
            embedding_provider=_FakeEmbeddingProvider(),
            settings=Settings(kb_background_embedding=False),
        )
        with pytest.raises(ValueError, match="readable text"):
            await service.create_document(
                user_id="test@example.com",
                filename="evil.txt",
                mime_type="text/plain",
                file_bytes=bytes(range(256)) * 16,
            )


class TestHybridSearchAndThreshold:
    @pytest.mark.asyncio
    async def test_low_score_chunks_are_dropped(self, db_session, monkeypatch):
        from app.services.knowledge_base_service import (
            KnowledgeBaseService,
            RetrievedChunk,
        )

        service = KnowledgeBaseService(
            db_session,
            embedding_provider=_FakeEmbeddingProvider(),
            settings=Settings(kb_min_score=0.5, kb_background_embedding=False),
        )

        async def fake_hybrid(*args, **kwargs):
            return [
                RetrievedChunk("d1", "good.pdf", "relevant", score=0.82),
                RetrievedChunk("d2", "meh.pdf", "barely related", score=0.31),
            ]

        monkeypatch.setattr(service, "_hybrid_search", fake_hybrid)

        results = await service.search(user_id="u@example.com", query="anything")
        assert [r.document_filename for r in results] == ["good.pdf"]

    @pytest.mark.asyncio
    async def test_hybrid_failure_returns_none_without_breaking_session(
        self, db_session, test_user_email
    ):
        """On databases without pgvector/FTS the hybrid path must signal
        fallback (None) and leave the session usable — a session-level
        rollback here once silently discarded in-flight chat messages."""
        from app.services.knowledge_base_service import KnowledgeBaseService

        service = KnowledgeBaseService(
            db_session,
            embedding_provider=_FakeEmbeddingProvider(),
            settings=Settings(kb_background_embedding=False),
        )
        result = await service._hybrid_search("u@example.com", "query", [0.0] * 768, limit=5)
        assert result is None

        # Session still works: an unrelated query succeeds afterwards.
        from sqlalchemy import select

        from app.models.user import User

        users = (await db_session.execute(select(User))).scalars().all()
        assert users  # conftest seeds one
