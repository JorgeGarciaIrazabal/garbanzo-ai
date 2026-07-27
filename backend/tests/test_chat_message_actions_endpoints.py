"""Integration tests for chat message action endpoints.

Covers the HTTP layer of:
- POST /chat/conversations/{id}/messages/{mid}/regenerate
- POST /chat/conversations/{id}/messages/{mid}/edit  (incl. truncation contract)
- POST /chat/conversations/{id}/messages/{mid}/branch
- DELETE /chat/conversations/{id}/chat  (cancel)

The streaming endpoints always return 200 + SSE; not-found / invalid-role
failures arrive as SSE ``error`` events. Branch is plain JSON and uses real
HTTP status codes.
"""

import asyncio
import json
import uuid
from collections.abc import AsyncIterator
from datetime import UTC, datetime, timedelta

import pytest
from httpx import ASGITransport, AsyncClient

from app.api.v1.endpoints.chat import get_chat_service
from app.core.config import Settings, get_settings
from app.core.security import get_current_user, hash_password
from app.db import session as db_session_module
from app.db.session import get_db
from app.main import app
from app.models.conversation import Conversation
from app.models.message import Message
from app.models.user import User
from app.schemas.chat import ChatOptions
from app.services.chat_service import ChatService
from app.services.llm_provider import ChatChunk, LLMProvider, ModelInfo, ProviderRegistry
from app.services.llm_provider import Message as LLMMessage

pytestmark = pytest.mark.asyncio


@pytest.fixture(autouse=True)
def _no_background_title(monkeypatch):
    """Stop first-exchange auto-titling from spawning a real background task.

    ``_spawn_title_generation`` fires ``asyncio.create_task`` against the global
    ``async_session_maker`` (the real DATABASE_URL engine), which outlives the
    test and binds a pooled connection to a soon-closed event loop. A later
    test reusing that pool then fails with "Future attached to a different
    loop". Stubbing it keeps these unit tests hermetic — the titling path has
    its own coverage in test_auto_titling.py.
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


class _StubProvider(LLMProvider):
    """Provider that streams a fixed reply."""

    def __init__(self, reply: str = "regenerated reply"):
        self.reply = reply

    @property
    def name(self) -> str:
        return "stub-endpoint"

    async def stream_chat(
        self,
        messages: list[LLMMessage],
        model: str,
        options: ChatOptions | None = None,
        cancel_event=None,
        tools=None,
    ) -> AsyncIterator[ChatChunk]:
        yield ChatChunk(content=self.reply, is_finished=False)
        yield ChatChunk(content="", is_finished=True, metadata={"tokens_generated": 1})

    async def chat(self, messages, model, options=None, tools=None) -> str:
        return ""

    async def list_models(self) -> list[ModelInfo]:
        return []

    async def health_check(self) -> bool:
        return True


def _install_overrides(_db_session, email: str = "test@example.com"):
    ProviderRegistry.register(_StubProvider())

    async def _override_db():
        async with db_session_module.async_session_maker() as session:
            yield session

    async def _override_user():
        return {"email": email, "token_payload": {}}

    async def _override_chat_service():
        async with db_session_module.async_session_maker() as session:
            yield ChatService(session, provider_name="stub-endpoint")

    app.dependency_overrides[get_db] = _override_db
    app.dependency_overrides[get_settings] = lambda: _TEST_SETTINGS
    app.dependency_overrides[get_current_user] = _override_user
    app.dependency_overrides[get_chat_service] = _override_chat_service


def _clear_overrides():
    app.dependency_overrides.pop(get_db, None)
    app.dependency_overrides.pop(get_current_user, None)
    app.dependency_overrides.pop(get_chat_service, None)
    # Intentionally do NOT pop get_settings — sibling test modules install a
    # process-wide override at import time; popping it here exposes later
    # tests to the real settings (and real DATABASE_URL).


def _client() -> AsyncClient:
    return AsyncClient(transport=ASGITransport(app=app), base_url="http://test")


def _parse_sse(body: str) -> list[dict]:
    """Parse `data: {...}\\n\\n` frames into a list of event dicts."""
    events = []
    for frame in body.split("\n\n"):
        frame = frame.strip()
        if not frame:
            continue
        assert frame.startswith("data: "), f"malformed SSE frame: {frame!r}"
        events.append(json.loads(frame[len("data: ") :]))
    return events


async def _seed_conversation(db_session, user_id: str, turns: list[tuple[str, str]]):
    """Create a conversation with the given (role, content) messages.

    Timestamps are seeded in the past with increasing offsets so ordering is
    deterministic and newly generated messages always sort after them.
    """
    conv = Conversation(
        id=str(uuid.uuid4()),
        user_id=user_id,
        title="Actions test",
        model="llama3.2",
    )
    db_session.add(conv)
    base = datetime.now(UTC) - timedelta(hours=1)
    messages = []
    for i, (role, content) in enumerate(turns):
        msg = Message(
            id=str(uuid.uuid4()),
            conversation_id=conv.id,
            role=role,
            content=content,
            created_at=base + timedelta(seconds=i),
        )
        db_session.add(msg)
        messages.append(msg)
    await db_session.commit()
    return conv, messages


async def _get_messages(client: AsyncClient, conversation_id: str) -> list[dict]:
    resp = await client.get(f"/api/v1/chat/conversations/{conversation_id}")
    assert resp.status_code == 200
    return resp.json()["messages"]


# ---------------------------------------------------------------------------
# Regenerate
# ---------------------------------------------------------------------------


async def test_regenerate_replaces_assistant_message(db_session, test_user_email):
    conv, msgs = await _seed_conversation(
        db_session,
        test_user_email,
        [("user", "hi"), ("assistant", "old reply")],
    )
    old_assistant_id = msgs[1].id

    _install_overrides(db_session)
    try:
        async with _client() as c:
            resp = await c.post(
                f"/api/v1/chat/conversations/{conv.id}/messages/{old_assistant_id}/regenerate",
                json={},
            )
            assert resp.status_code == 200
            assert resp.headers["content-type"].startswith("text/event-stream")

            events = _parse_sse(resp.text)
            assert [e["type"] for e in events] == ["chunk", "done"]
            assert events[0]["content"] == "regenerated reply"

            history = await _get_messages(c, conv.id)
        assert [(m["role"], m["content"]) for m in history] == [
            ("user", "hi"),
            ("assistant", "regenerated reply"),
        ]
        # The old assistant message is gone, replaced by a new row.
        assert all(m["id"] != old_assistant_id for m in history)
    finally:
        _clear_overrides()


async def test_regenerate_user_message_yields_invalid_role_error(db_session, test_user_email):
    conv, msgs = await _seed_conversation(
        db_session,
        test_user_email,
        [("user", "hi"), ("assistant", "reply")],
    )

    _install_overrides(db_session)
    try:
        async with _client() as c:
            resp = await c.post(
                f"/api/v1/chat/conversations/{conv.id}/messages/{msgs[0].id}/regenerate",
                json={},
            )
        events = _parse_sse(resp.text)
        assert len(events) == 1
        assert events[0]["type"] == "error"
        assert events[0]["metadata"]["error_type"] == "invalid_role"
    finally:
        _clear_overrides()


async def test_regenerate_other_users_conversation_yields_not_found(db_session, test_user_email):
    db_session.add(User(email="other@example.com", hashed_password=hash_password("x")))
    await db_session.commit()
    conv, msgs = await _seed_conversation(
        db_session,
        "other@example.com",
        [("user", "hi"), ("assistant", "secret reply")],
    )

    _install_overrides(db_session, email=test_user_email)
    try:
        async with _client() as c:
            resp = await c.post(
                f"/api/v1/chat/conversations/{conv.id}/messages/{msgs[1].id}/regenerate",
                json={},
            )
        events = _parse_sse(resp.text)
        assert len(events) == 1
        assert events[0]["type"] == "error"
        assert events[0]["metadata"]["error_type"] == "not_found"
    finally:
        _clear_overrides()


# ---------------------------------------------------------------------------
# Edit
# ---------------------------------------------------------------------------


async def test_edit_updates_content_and_truncates_later_messages(db_session, test_user_email):
    conv, msgs = await _seed_conversation(
        db_session,
        test_user_email,
        [
            ("user", "first question"),
            ("assistant", "first answer"),
            ("user", "second question"),
            ("assistant", "second answer"),
        ],
    )
    first_user_id = msgs[0].id

    _install_overrides(db_session)
    try:
        async with _client() as c:
            resp = await c.post(
                f"/api/v1/chat/conversations/{conv.id}/messages/{first_user_id}/edit",
                json={"content": "edited question"},
            )
            assert resp.status_code == 200
            events = _parse_sse(resp.text)
            assert [e["type"] for e in events] == ["chunk", "done"]

            history = await _get_messages(c, conv.id)
        # Everything after the edited message was dropped; a fresh assistant
        # reply was generated.
        assert [(m["role"], m["content"]) for m in history] == [
            ("user", "edited question"),
            ("assistant", "regenerated reply"),
        ]
        # Edit updates the message in place — the ID is stable.
        assert history[0]["id"] == first_user_id
    finally:
        _clear_overrides()


async def test_edit_assistant_message_yields_invalid_role_error(db_session, test_user_email):
    conv, msgs = await _seed_conversation(
        db_session,
        test_user_email,
        [("user", "hi"), ("assistant", "reply")],
    )

    _install_overrides(db_session)
    try:
        async with _client() as c:
            resp = await c.post(
                f"/api/v1/chat/conversations/{conv.id}/messages/{msgs[1].id}/edit",
                json={"content": "nope"},
            )
        events = _parse_sse(resp.text)
        assert len(events) == 1
        assert events[0]["type"] == "error"
        assert events[0]["metadata"]["error_type"] == "invalid_role"
    finally:
        _clear_overrides()


async def test_edit_missing_message_yields_not_found(db_session, test_user_email):
    conv, _ = await _seed_conversation(db_session, test_user_email, [("user", "hi")])

    _install_overrides(db_session)
    try:
        async with _client() as c:
            resp = await c.post(
                f"/api/v1/chat/conversations/{conv.id}/messages/does-not-exist/edit",
                json={"content": "x"},
            )
        events = _parse_sse(resp.text)
        assert events[0]["type"] == "error"
        assert events[0]["metadata"]["error_type"] == "not_found"
    finally:
        _clear_overrides()


async def test_edit_rejects_empty_content(db_session, test_user_email):
    conv, msgs = await _seed_conversation(db_session, test_user_email, [("user", "hi")])

    _install_overrides(db_session)
    try:
        async with _client() as c:
            resp = await c.post(
                f"/api/v1/chat/conversations/{conv.id}/messages/{msgs[0].id}/edit",
                json={"content": ""},
            )
        assert resp.status_code == 422
    finally:
        _clear_overrides()


# ---------------------------------------------------------------------------
# Branch
# ---------------------------------------------------------------------------


async def test_branch_copies_history_up_to_branch_point(db_session, test_user_email):
    conv, msgs = await _seed_conversation(
        db_session,
        test_user_email,
        [
            ("user", "first question"),
            ("assistant", "first answer"),
            ("user", "second question"),
            ("assistant", "second answer"),
        ],
    )
    branch_point = msgs[1].id  # first answer

    _install_overrides(db_session)
    try:
        async with _client() as c:
            resp = await c.post(
                f"/api/v1/chat/conversations/{conv.id}/messages/{branch_point}/branch",
            )
            assert resp.status_code == 201
            body = resp.json()
            assert body["id"] != conv.id
            assert body["title"] == conv.title
            assert body["model"] == conv.model

            new_history = await _get_messages(c, body["id"])
            old_history = await _get_messages(c, conv.id)

        assert [(m["role"], m["content"]) for m in new_history] == [
            ("user", "first question"),
            ("assistant", "first answer"),
        ]
        # Source conversation is untouched.
        assert len(old_history) == 4
    finally:
        _clear_overrides()


async def test_branch_missing_message_404(db_session, test_user_email):
    conv, _ = await _seed_conversation(db_session, test_user_email, [("user", "hi")])

    _install_overrides(db_session)
    try:
        async with _client() as c:
            resp = await c.post(
                f"/api/v1/chat/conversations/{conv.id}/messages/does-not-exist/branch",
            )
        assert resp.status_code == 404
    finally:
        _clear_overrides()


async def test_branch_other_users_conversation_404(db_session, test_user_email):
    db_session.add(User(email="other@example.com", hashed_password=hash_password("x")))
    await db_session.commit()
    conv, msgs = await _seed_conversation(
        db_session,
        "other@example.com",
        [("user", "hi"), ("assistant", "reply")],
    )

    _install_overrides(db_session, email=test_user_email)
    try:
        async with _client() as c:
            resp = await c.post(
                f"/api/v1/chat/conversations/{conv.id}/messages/{msgs[1].id}/branch",
            )
        assert resp.status_code == 404
    finally:
        _clear_overrides()


# ---------------------------------------------------------------------------
# Cancel (stop stream)
# ---------------------------------------------------------------------------


async def test_cancel_sets_active_stream_event(db_session, test_user_email):
    event = asyncio.Event()
    ChatService._active_streams["conv-cancel-test"] = event

    _install_overrides(db_session)
    try:
        async with _client() as c:
            resp = await c.delete("/api/v1/chat/conversations/conv-cancel-test/chat")
        assert resp.status_code == 204
        assert event.is_set()
    finally:
        ChatService._active_streams.pop("conv-cancel-test", None)
        _clear_overrides()


async def test_cancel_without_active_stream_is_noop_204(db_session, test_user_email):
    _install_overrides(db_session)
    try:
        async with _client() as c:
            resp = await c.delete("/api/v1/chat/conversations/no-such-stream/chat")
        assert resp.status_code == 204
    finally:
        _clear_overrides()


async def test_regenerate_requires_auth(db_session):
    # No get_current_user override: the real dependency must reject
    # unauthenticated requests.
    async def _override_db():
        yield db_session

    app.dependency_overrides[get_db] = _override_db
    app.dependency_overrides[get_settings] = lambda: _TEST_SETTINGS
    try:
        async with _client() as c:
            resp = await c.post(
                "/api/v1/chat/conversations/x/messages/y/regenerate",
                json={},
            )
        assert resp.status_code in (401, 403)
    finally:
        _clear_overrides()
