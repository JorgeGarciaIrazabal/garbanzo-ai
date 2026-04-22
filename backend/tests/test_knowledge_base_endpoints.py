"""Integration tests for the /api/v1/kb endpoints."""

import pytest
from httpx import ASGITransport, AsyncClient

from app.api.v1.endpoints.knowledge_base import get_kb_service
from app.core.config import Settings, get_settings
from app.core.security import get_current_user, hash_password
from app.db.session import get_db
from app.main import app
from app.models.user import User
from app.services.embedding_provider import set_embedding_provider
from app.services.knowledge_base_service import KnowledgeBaseService

pytestmark = pytest.mark.asyncio


_TEST_SETTINGS = Settings(
    secret_key="test-secret-key-do-not-use-in-prod",
    database_url="sqlite+aiosqlite:///:memory:",
    access_token_expire_minutes=30,
    kb_max_file_size_mb=1,  # small to exercise the limit
    kb_background_embedding=False,
)


class _FakeEmbeddingProvider:
    dim = 3

    async def embed(self, texts):
        return [[0.1, 0.2, 0.3] for _ in texts]


def _install_overrides(db_session, email: str = "test@example.com"):
    async def _override_db():
        yield db_session

    async def _override_user():
        return {"email": email, "token_payload": {}}

    def _override_service():
        return KnowledgeBaseService(
            db_session,
            embedding_provider=_FakeEmbeddingProvider(),
            settings=_TEST_SETTINGS,
        )

    app.dependency_overrides[get_db] = _override_db
    app.dependency_overrides[get_settings] = lambda: _TEST_SETTINGS
    app.dependency_overrides[get_current_user] = _override_user
    app.dependency_overrides[get_kb_service] = _override_service
    set_embedding_provider(_FakeEmbeddingProvider())


def _clear_overrides():
    app.dependency_overrides.pop(get_db, None)
    app.dependency_overrides.pop(get_settings, None)
    app.dependency_overrides.pop(get_current_user, None)
    app.dependency_overrides.pop(get_kb_service, None)
    set_embedding_provider(None)


async def _client():
    return AsyncClient(transport=ASGITransport(app=app), base_url="http://test")


async def test_upload_document(db_session):
    _install_overrides(db_session)
    try:
        async with await _client() as c:
            resp = await c.post(
                "/api/v1/kb/documents",
                files={"file": ("notes.txt", b"Some useful text." * 20, "text/plain")},
            )
        assert resp.status_code == 201, resp.text
        body = resp.json()
        assert body["filename"] == "notes.txt"
        assert body["chunk_count"] >= 1
        assert body["status"] in {"pending", "processing", "ready"}
    finally:
        _clear_overrides()


async def test_upload_rejects_empty_file(db_session):
    _install_overrides(db_session)
    try:
        async with await _client() as c:
            resp = await c.post(
                "/api/v1/kb/documents",
                files={"file": ("empty.txt", b"", "text/plain")},
            )
        assert resp.status_code == 400
    finally:
        _clear_overrides()


async def test_upload_rejects_oversized_file(db_session):
    _install_overrides(db_session)
    try:
        # 2 MB body against the 1 MB test cap.
        payload = b"x" * (2 * 1024 * 1024)
        async with await _client() as c:
            resp = await c.post(
                "/api/v1/kb/documents",
                files={"file": ("big.txt", payload, "text/plain")},
            )
        assert resp.status_code == 413
    finally:
        _clear_overrides()


async def test_upload_rejects_unextractable_file(db_session):
    _install_overrides(db_session)
    try:
        async with await _client() as c:
            resp = await c.post(
                "/api/v1/kb/documents",
                files={"file": ("blank.txt", b"   \n  \n  ", "text/plain")},
            )
        assert resp.status_code == 400
    finally:
        _clear_overrides()


async def test_list_documents(db_session):
    service = KnowledgeBaseService(db_session, embedding_provider=_FakeEmbeddingProvider())
    await service.create_document(
        user_id="test@example.com",
        filename="a.txt",
        mime_type="text/plain",
        file_bytes=b"alpha" * 20,
    )
    await service.create_document(
        user_id="test@example.com",
        filename="b.txt",
        mime_type="text/plain",
        file_bytes=b"beta" * 20,
    )

    _install_overrides(db_session)
    try:
        async with await _client() as c:
            resp = await c.get("/api/v1/kb/documents")
        assert resp.status_code == 200
        body = resp.json()
        assert body["total"] == 2
        filenames = {d["filename"] for d in body["items"]}
        assert filenames == {"a.txt", "b.txt"}
    finally:
        _clear_overrides()


async def test_get_document_404_for_other_user(db_session):
    # Seed a second user with one doc.
    db_session.add(
        User(email="other@example.com", hashed_password=hash_password("x"))
    )
    await db_session.commit()
    service = KnowledgeBaseService(db_session, embedding_provider=_FakeEmbeddingProvider())
    other_doc = await service.create_document(
        user_id="other@example.com",
        filename="secret.txt",
        mime_type="text/plain",
        file_bytes=b"secret" * 20,
    )

    # Logged-in user is test@example.com; must not be able to see the other doc.
    _install_overrides(db_session)
    try:
        async with await _client() as c:
            resp = await c.get(f"/api/v1/kb/documents/{other_doc.id}")
        assert resp.status_code == 404
    finally:
        _clear_overrides()


async def test_delete_document(db_session):
    service = KnowledgeBaseService(db_session, embedding_provider=_FakeEmbeddingProvider())
    doc = await service.create_document(
        user_id="test@example.com",
        filename="tmp.txt",
        mime_type="text/plain",
        file_bytes=b"xxx" * 80,
    )

    _install_overrides(db_session)
    try:
        async with await _client() as c:
            resp = await c.delete(f"/api/v1/kb/documents/{doc.id}")
            assert resp.status_code == 204

            resp2 = await c.get(f"/api/v1/kb/documents/{doc.id}")
            assert resp2.status_code == 404
    finally:
        _clear_overrides()


async def test_delete_refuses_other_users_document(db_session):
    db_session.add(
        User(email="other@example.com", hashed_password=hash_password("x"))
    )
    await db_session.commit()
    service = KnowledgeBaseService(db_session, embedding_provider=_FakeEmbeddingProvider())
    other_doc = await service.create_document(
        user_id="other@example.com",
        filename="secret.txt",
        mime_type="text/plain",
        file_bytes=b"secret" * 20,
    )

    _install_overrides(db_session)  # logged in as test@example.com
    try:
        async with await _client() as c:
            resp = await c.delete(f"/api/v1/kb/documents/{other_doc.id}")
            assert resp.status_code == 404
    finally:
        _clear_overrides()
