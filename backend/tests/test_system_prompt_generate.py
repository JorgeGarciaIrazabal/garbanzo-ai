"""Tests for the AI-assisted system prompt generation endpoint and service."""

import json
from collections.abc import AsyncIterator
from unittest.mock import patch

import pytest
from httpx import ASGITransport, AsyncClient

from app.core.config import Settings, get_settings
from app.core.security import get_current_user
from app.db.session import get_db
from app.main import app
from app.schemas.chat import ChatOptions
from app.services.llm_provider import ChatChunk, LLMProvider, Message, ModelInfo
from app.services.system_prompt_service import SystemPromptService

pytestmark = pytest.mark.asyncio


_TEST_SETTINGS = Settings(
    secret_key="test-secret-key-do-not-use-in-prod",
    database_url="sqlite+aiosqlite:///:memory:",
    access_token_expire_minutes=30,
    default_model="test-model",
)


def _install_overrides(db_session, email: str = "test@example.com"):
    async def _override_db():
        yield db_session

    async def _override_user():
        return {"email": email, "token_payload": {}}

    app.dependency_overrides[get_db] = _override_db
    app.dependency_overrides[get_settings] = lambda: _TEST_SETTINGS
    app.dependency_overrides[get_current_user] = _override_user


def _clear_overrides():
    app.dependency_overrides.pop(get_db, None)
    app.dependency_overrides.pop(get_current_user, None)
    app.dependency_overrides.pop(get_settings, None)


async def _client():
    return AsyncClient(transport=ASGITransport(app=app), base_url="http://test")


class _FakeProvider(LLMProvider):
    """A minimal fake LLM provider for testing streaming generation."""

    def __init__(self, chunks: list[ChatChunk]):
        self._chunks = chunks
        self.calls: list[dict] = []

    @property
    def name(self) -> str:
        return "fake"

    async def stream_chat(
        self,
        messages: list[Message],
        model: str,
        options: ChatOptions | None = None,
        cancel_event=None,
        tools=None,
    ) -> AsyncIterator[ChatChunk]:
        self.calls.append(
            {
                "messages": messages,
                "model": model,
                "options": options,
            }
        )
        for chunk in self._chunks:
            yield chunk

    async def chat(self, messages, model, options=None, tools=None) -> str:
        return "".join(c.content for c in self._chunks if c.content)

    async def list_models(self) -> list[ModelInfo]:
        return []

    async def health_check(self) -> bool:
        return True

    async def get_model_context_length(self, model: str) -> int | None:
        return None


def _make_chunks(*contents: str) -> list[ChatChunk]:
    """Build a list of ChatChunks: one content chunk per arg, then a finished chunk."""
    chunks = [ChatChunk(content=c) for c in contents if c]
    chunks.append(ChatChunk(content="", is_finished=True, metadata={"model": "test"}))
    return chunks


class TestGenerateService:
    async def test_generate_initial(self, db_session):
        svc = SystemPromptService(db_session)
        chunks_gen = _make_chunks("You are ", "a concise ", "assistant.")
        fake = _FakeProvider(chunks_gen)

        with patch(
            "app.services.system_prompt_service.ProviderRegistry.get",
            return_value=fake,
        ):
            result = []
            async for chunk in svc.generate_system_prompt(intent="Make me a coding mentor"):
                result.append(chunk)

        contents = "".join(c.content for c in result if c.content and not c.is_finished)
        assert "You are a concise assistant." in contents
        assert fake.calls[0]["model"] is not None
        assert fake.calls[0]["options"].temperature == 0.7

    async def test_generate_refine_mode(self, db_session):
        svc = SystemPromptService(db_session)
        chunks_gen = _make_chunks("You are a friendly coding mentor.")
        fake = _FakeProvider(chunks_gen)

        with patch(
            "app.services.system_prompt_service.ProviderRegistry.get",
            return_value=fake,
        ):
            result = []
            async for chunk in svc.generate_system_prompt(
                intent="a coding mentor",
                existing_prompt="You are a coding mentor.",
                feedback="make it friendlier",
            ):
                result.append(chunk)

        assert len(fake.calls) == 1
        messages = fake.calls[0]["messages"]
        assert (
            "existing prompt" in messages[0].content.lower()
            or "current system prompt" in messages[0].content.lower()
        )
        assert "make it friendlier" in messages[0].content

    async def test_generate_uses_specified_model(self, db_session):
        svc = SystemPromptService(db_session)
        chunks_gen = _make_chunks("test")
        fake = _FakeProvider(chunks_gen)

        with patch(
            "app.services.system_prompt_service.ProviderRegistry.get",
            return_value=fake,
        ):
            async for _ in svc.generate_system_prompt(intent="x", model="qwen3:32b"):
                pass

        assert fake.calls[0]["model"] == "qwen3:32b"

    async def test_generate_no_provider_raises(self, db_session):
        svc = SystemPromptService(db_session)

        with (
            patch(
                "app.services.system_prompt_service.ProviderRegistry.get",
                return_value=None,
            ),
            pytest.raises(RuntimeError, match="No LLM provider"),
        ):
            async for _ in svc.generate_system_prompt(intent="x"):
                pass


class TestGenerateEndpoint:
    async def test_generate_streams_chunks(self, db_session):
        _install_overrides(db_session)
        chunks_gen = _make_chunks("You are ", "helpful.")
        fake = _FakeProvider(chunks_gen)

        try:
            with patch(
                "app.services.system_prompt_service.ProviderRegistry.get",
                return_value=fake,
            ):
                async with await _client() as c:
                    resp = await c.post(
                        "/api/v1/system-prompts/generate",
                        json={"intent": "a concise assistant"},
                    )
                assert resp.status_code == 200
                assert resp.headers["content-type"].startswith("text/event-stream")

                lines = resp.text.strip().split("\n")
                data_lines = [line for line in lines if line.startswith("data: ")]
                parsed = [json.loads(line[6:]) for line in data_lines]

                chunk_types = [p["type"] for p in parsed]
                assert "chunk" in chunk_types
                assert "done" in chunk_types

                content = "".join(
                    p["content"] for p in parsed if p["type"] == "chunk" and p.get("content")
                )
                assert "You are helpful." in content
        finally:
            _clear_overrides()

    async def test_generate_refine_flow(self, db_session):
        _install_overrides(db_session)
        chunks_gen = _make_chunks("You are a friendly mentor.")
        fake = _FakeProvider(chunks_gen)

        try:
            with patch(
                "app.services.system_prompt_service.ProviderRegistry.get",
                return_value=fake,
            ):
                async with await _client() as c:
                    resp = await c.post(
                        "/api/v1/system-prompts/generate",
                        json={
                            "intent": "coding mentor",
                            "existing_prompt": "You are a coding mentor.",
                            "feedback": "make it friendlier",
                        },
                    )
                assert resp.status_code == 200
                lines = resp.text.strip().split("\n")
                data_lines = [line for line in lines if line.startswith("data: ")]
                parsed = [json.loads(line[6:]) for line in data_lines]

                content = "".join(p.get("content", "") for p in parsed if p["type"] == "chunk")
                assert "friendly mentor" in content
        finally:
            _clear_overrides()

    async def test_generate_error_emits_error_chunk(self, db_session):
        _install_overrides(db_session)

        try:
            with patch(
                "app.services.system_prompt_service.ProviderRegistry.get",
                return_value=None,
            ):
                async with await _client() as c:
                    resp = await c.post(
                        "/api/v1/system-prompts/generate",
                        json={"intent": "test"},
                    )
                assert resp.status_code == 200
                lines = resp.text.strip().split("\n")
                data_lines = [line for line in lines if line.startswith("data: ")]
                parsed = [json.loads(line[6:]) for line in data_lines]

                error_chunks = [p for p in parsed if p["type"] == "error"]
                assert len(error_chunks) == 1
                assert "No LLM provider" in error_chunks[0]["error"]
        finally:
            _clear_overrides()

    async def test_generate_rejects_empty_intent(self, db_session):
        _install_overrides(db_session)

        try:
            async with await _client() as c:
                resp = await c.post(
                    "/api/v1/system-prompts/generate",
                    json={"intent": ""},
                )
            assert resp.status_code == 422
        finally:
            _clear_overrides()

    async def test_generate_with_custom_model(self, db_session):
        _install_overrides(db_session)
        chunks_gen = _make_chunks("test prompt")
        fake = _FakeProvider(chunks_gen)

        try:
            with patch(
                "app.services.system_prompt_service.ProviderRegistry.get",
                return_value=fake,
            ):
                async with await _client() as c:
                    resp = await c.post(
                        "/api/v1/system-prompts/generate",
                        json={"intent": "mentor", "model": "granite4:micro"},
                    )
                assert resp.status_code == 200
                assert fake.calls[0]["model"] == "granite4:micro"
        finally:
            _clear_overrides()
