"""Tests for Conversation.thinking_level (Idea 2, "Styles" — subtask 1).

Mirrors ``test_conversation_mute.py`` in structure. Covers:
  * the column default (unset → None, preserving the provider's implicit
    auto-enable-when-capable behavior)
  * setting/reading the level through the conversation CRUD endpoints
    (``POST /chat/conversations``, ``PATCH /chat/conversations/{id}``)
  * ``ConversationService`` three-way update semantics (not provided →
    unchanged, explicit null → reset, explicit level → set)
  * the level reaching the LLM provider as ``ChatOptions.think`` when a
    message is sent
"""

from collections.abc import AsyncIterator
from typing import Any

import pytest
from httpx import ASGITransport, AsyncClient

from app.api.v1.endpoints.chat import get_chat_service
from app.core.config import Settings, get_settings
from app.core.security import get_current_user
from app.db.session import get_db
from app.main import app
from app.schemas.chat import ChatOptions
from app.services.chat_service import ChatService
from app.services.conversation_service import ConversationService
from app.services.llm_provider import ChatChunk, LLMProvider, ModelInfo, ProviderRegistry
from app.services.llm_provider import Message as LLMMessage

pytestmark = pytest.mark.asyncio


@pytest.fixture(autouse=True)
def _no_background_title(monkeypatch):
    """Stop first-exchange auto-titling from spawning a real background task.

    Same rationale as ``test_chat_sse_endpoint.py``: ``_spawn_title_generation``
    fires ``asyncio.create_task`` against the global ``async_session_maker``
    (the real DATABASE_URL engine), which outlives the test and binds a
    pooled connection to a soon-closed event loop.
    """
    monkeypatch.setattr(
        ChatService,
        "_spawn_title_generation",
        lambda *a, **k: None,
    )


_TEST_SETTINGS = Settings(
    secret_key="test-secret-key-do-not-use-in-prod",
    database_url="sqlite+aiosqlite:///:memory:",
    access_token_expire_minutes=30,
)

OWNER = "test@example.com"  # seeded by conftest


class _RecordingProvider(LLMProvider):
    """Streams a single 'done' chunk and records the ChatOptions it was
    called with, so tests can assert what reached the provider layer."""

    def __init__(self):
        self.received_options: list[ChatOptions] = []

    @property
    def name(self) -> str:
        return "recording"

    async def stream_chat(
        self,
        messages: list[LLMMessage],
        model: str,
        options: ChatOptions | None = None,
        cancel_event=None,
        tools=None,
    ) -> AsyncIterator[ChatChunk]:
        self.received_options.append(options or ChatOptions())
        yield ChatChunk(content="hi", is_finished=False)
        yield ChatChunk(content="", is_finished=True, metadata={"tokens_generated": 1})

    async def chat(self, messages, model, options=None, tools=None) -> str:
        return ""

    async def list_models(self) -> list[ModelInfo]:
        return []

    async def health_check(self) -> bool:
        return True


def _install_overrides(db_session, provider: LLMProvider | None = None):
    async def _override_db():
        yield db_session

    async def _override_user():
        return {"email": OWNER, "token_payload": {}}

    app.dependency_overrides[get_db] = _override_db
    app.dependency_overrides[get_settings] = lambda: _TEST_SETTINGS
    app.dependency_overrides[get_current_user] = _override_user
    if provider is not None:
        ProviderRegistry.register(provider)
        app.dependency_overrides[get_chat_service] = lambda: ChatService(
            db_session, provider_name=provider.name
        )


def _clear_overrides():
    for dep in (get_db, get_current_user, get_chat_service):
        app.dependency_overrides.pop(dep, None)


def _client() -> AsyncClient:
    return AsyncClient(transport=ASGITransport(app=app), base_url="http://test")


async def _create_conversation(client: AsyncClient, **overrides: Any) -> dict:
    payload = {"title": "Test conversation", **overrides}
    resp = await client.post("/api/v1/chat/conversations", json=payload)
    assert resp.status_code == 201, resp.text
    return resp.json()


# --------------------------------------------------------------- Column default


@pytest.mark.asyncio
async def test_thinking_level_defaults_to_none(db_session):
    _install_overrides(db_session)
    try:
        async with _client() as c:
            conv = await _create_conversation(c)
        assert conv["thinking_level"] is None
    finally:
        _clear_overrides()


# ---------------------------------------------------------------- Endpoint: create


@pytest.mark.asyncio
async def test_create_conversation_with_thinking_level(db_session):
    _install_overrides(db_session)
    try:
        async with _client() as c:
            conv = await _create_conversation(c, thinking_level="high")
        assert conv["thinking_level"] == "high"
    finally:
        _clear_overrides()


@pytest.mark.asyncio
async def test_create_conversation_rejects_invalid_thinking_level(db_session):
    _install_overrides(db_session)
    try:
        async with _client() as c:
            resp = await c.post(
                "/api/v1/chat/conversations",
                json={"title": "x", "thinking_level": "bogus"},
            )
        assert resp.status_code == 422
    finally:
        _clear_overrides()


# ---------------------------------------------------------------- Endpoint: update


@pytest.mark.asyncio
async def test_update_conversation_sets_thinking_level(db_session):
    _install_overrides(db_session)
    try:
        async with _client() as c:
            conv = await _create_conversation(c)
            resp = await c.patch(
                f"/api/v1/chat/conversations/{conv['id']}",
                json={"thinking_level": "low"},
            )
        assert resp.status_code == 200
        assert resp.json()["thinking_level"] == "low"
    finally:
        _clear_overrides()


@pytest.mark.asyncio
async def test_update_conversation_omitted_thinking_level_leaves_unchanged(db_session):
    _install_overrides(db_session)
    try:
        async with _client() as c:
            conv = await _create_conversation(c, thinking_level="medium")
            # Update a different field; thinking_level isn't in the payload.
            resp = await c.patch(
                f"/api/v1/chat/conversations/{conv['id']}",
                json={"title": "renamed"},
            )
        assert resp.status_code == 200
        assert resp.json()["thinking_level"] == "medium"
    finally:
        _clear_overrides()


@pytest.mark.asyncio
async def test_update_conversation_explicit_null_resets_thinking_level(db_session):
    _install_overrides(db_session)
    try:
        async with _client() as c:
            conv = await _create_conversation(c, thinking_level="high")
            resp = await c.patch(
                f"/api/v1/chat/conversations/{conv['id']}",
                json={"thinking_level": None},
            )
        assert resp.status_code == 200
        assert resp.json()["thinking_level"] is None
    finally:
        _clear_overrides()


# ------------------------------------------- ConversationService.update


@pytest.mark.asyncio
async def test_conversation_service_update_three_way_semantics(db_session):
    svc = ConversationService(db_session)
    conv = await svc.create(user_id=OWNER, title="Thinking convo", thinking_level="low")
    assert conv.thinking_level == "low"

    # Not provided (set_thinking_level=False) → unchanged.
    updated = await svc.update(conv.id, OWNER, title="renamed")
    assert updated is not None
    assert updated.thinking_level == "low"

    # Explicit level → set.
    updated = await svc.update(conv.id, OWNER, thinking_level="high", set_thinking_level=True)
    assert updated is not None
    assert updated.thinking_level == "high"

    # Explicit None with set_thinking_level=True → reset to provider default.
    updated = await svc.update(conv.id, OWNER, thinking_level=None, set_thinking_level=True)
    assert updated is not None
    assert updated.thinking_level is None


# -------------------------------------------------------- Reaches the provider


@pytest.mark.asyncio
async def test_thinking_level_reaches_provider_as_chat_options_think(db_session):
    """Sending a message on a conversation with thinking_level='high' must
    surface as ChatOptions.think='high' on the provider's stream_chat call —
    the chat_service → ollama_provider hand-off this task wires up."""
    provider = _RecordingProvider()
    _install_overrides(db_session, provider)
    try:
        async with _client() as c:
            conv = await _create_conversation(c, thinking_level="high")
            resp = await c.post(
                f"/api/v1/chat/conversations/{conv['id']}/chat",
                json={"message": "hi"},
                headers={"Accept": "text/event-stream"},
            )
        assert resp.status_code == 200
    finally:
        _clear_overrides()

    assert len(provider.received_options) == 1
    assert provider.received_options[0].think == "high"


@pytest.mark.asyncio
async def test_unset_thinking_level_reaches_provider_as_none(db_session):
    """A conversation that never set thinking_level must pass think=None
    through to the provider, preserving the provider's own default."""
    provider = _RecordingProvider()
    _install_overrides(db_session, provider)
    try:
        async with _client() as c:
            conv = await _create_conversation(c)
            resp = await c.post(
                f"/api/v1/chat/conversations/{conv['id']}/chat",
                json={"message": "hi"},
                headers={"Accept": "text/event-stream"},
            )
        assert resp.status_code == 200
    finally:
        _clear_overrides()

    assert len(provider.received_options) == 1
    assert provider.received_options[0].think is None


async def _seed_users(db_session, *emails: str):
    from app.core.security import hash_password
    from app.models.user import User

    for email in emails:
        db_session.add(User(email=email, hashed_password=hash_password("x")))
    await db_session.commit()


@pytest.mark.asyncio
async def test_branch_from_message_copies_thinking_level(db_session):
    svc = ConversationService(db_session)
    source = await svc.create(
        user_id=OWNER,
        title="Source",
        thinking_level="medium",
        initial_message="hello",
    )
    await db_session.refresh(source, attribute_names=["messages"])
    message_id = source.messages[0].id

    branched = await svc.branch_from_message(source.id, message_id, OWNER)
    assert branched is not None
    assert branched.thinking_level == "medium"
