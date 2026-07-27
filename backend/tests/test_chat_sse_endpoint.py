"""Wire-contract tests for POST /api/v1/chat/conversations/{id}/chat.

The service-level streaming loop is covered by test_chat_tool_loop.py; these
tests pin the HTTP/SSE surface both the Flutter ``sse_parser`` and the
push-notification-on-disconnect logic depend on: ``data: {...}\\n\\n`` framing,
the serialized chunk field names, the chunk/thinking/done/error event types,
and auth.
"""

import asyncio
import json
import uuid
from collections.abc import AsyncIterator

import pytest
from httpx import ASGITransport, AsyncClient
from sqlalchemy import select

from app.api.v1.endpoints.chat import get_chat_service
from app.core.config import Settings, get_settings
from app.core.security import get_current_user
from app.db.session import get_db
from app.main import app
from app.models.conversation import Conversation
from app.models.message import Message
from app.schemas.chat import ChatOptions
from app.services.chat_service import ChatService
from app.services.detached_chat_stream import DetachedChatStream
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


class _ScriptedProvider(LLMProvider):
    """Streams a fixed chunk script; optionally raises mid-stream."""

    def __init__(self, chunks: list[ChatChunk], *, raise_after: int | None = None):
        self.chunks = chunks
        self.raise_after = raise_after

    @property
    def name(self) -> str:
        return "scripted-sse"

    async def stream_chat(
        self,
        messages: list[LLMMessage],
        model: str,
        options: ChatOptions | None = None,
        cancel_event=None,
        tools=None,
    ) -> AsyncIterator[ChatChunk]:
        for i, chunk in enumerate(self.chunks):
            if self.raise_after is not None and i >= self.raise_after:
                raise RuntimeError("provider blew up")
            yield chunk

    async def chat(self, messages, model, options=None, tools=None) -> str:
        return ""

    async def list_models(self) -> list[ModelInfo]:
        return []

    async def health_check(self) -> bool:
        return True


class _GatedProvider(_ScriptedProvider):
    """Pause after the first token so the SSE consumer can disconnect."""

    def __init__(self):
        super().__init__([])
        self.finish = asyncio.Event()

    async def stream_chat(
        self,
        messages: list[LLMMessage],
        model: str,
        options: ChatOptions | None = None,
        cancel_event=None,
        tools=None,
    ) -> AsyncIterator[ChatChunk]:
        yield ChatChunk(content="partial ")
        await self.finish.wait()
        yield ChatChunk(content="response")
        yield ChatChunk(content="", is_finished=True, metadata={})


def _install_overrides(db_session, provider: LLMProvider):
    ProviderRegistry.register(provider)

    async def _override_db():
        yield db_session

    async def _override_user():
        return {"email": "test@example.com", "token_payload": {}}

    app.dependency_overrides[get_db] = _override_db
    app.dependency_overrides[get_settings] = lambda: _TEST_SETTINGS
    app.dependency_overrides[get_current_user] = _override_user
    app.dependency_overrides[get_chat_service] = lambda: ChatService(
        db_session, provider_name=provider.name
    )


def _clear_overrides():
    # get_settings intentionally stays overridden — sibling test modules
    # install a process-wide override at import time; popping it here exposes
    # later tests to the real settings (and real DATABASE_URL).
    for dep in (get_db, get_current_user, get_chat_service):
        app.dependency_overrides.pop(dep, None)


def _client() -> AsyncClient:
    return AsyncClient(transport=ASGITransport(app=app), base_url="http://test")


async def _make_conversation(db_session) -> str:
    conv = Conversation(
        id=str(uuid.uuid4()),
        user_id="test@example.com",
        title="SSE test",
        model="llama3.2",
    )
    db_session.add(conv)
    await db_session.commit()
    return conv.id


async def test_sse_framing_and_event_sequence(db_session):
    provider = _ScriptedProvider(
        [
            ChatChunk(content="pondering", is_thinking=True),
            ChatChunk(content="Hello ", is_finished=False),
            ChatChunk(content="world", is_finished=False),
            ChatChunk(
                content="",
                is_finished=True,
                metadata={"tokens_generated": 2, "model": "llama3.2"},
            ),
        ]
    )
    conv_id = await _make_conversation(db_session)
    _install_overrides(db_session, provider)
    try:
        async with _client() as c:
            resp = await c.post(
                f"/api/v1/chat/conversations/{conv_id}/chat",
                json={"message": "hi"},
                headers={"Accept": "text/event-stream"},
            )
        assert resp.status_code == 200
        assert resp.headers["content-type"].startswith("text/event-stream")
        assert resp.headers["cache-control"] == "no-cache"

        # Byte-level framing: every event is a `data: {json}\n\n` frame.
        body = resp.text
        frames = body.split("\n\n")
        assert frames[-1] == ""  # stream ends with a frame terminator
        frames = frames[:-1]
        assert all(f.startswith("data: ") for f in frames)

        events = [json.loads(f[len("data: ") :]) for f in frames]
        assert [e["type"] for e in events] == ["thinking", "chunk", "chunk", "done"]

        # Serialized chunk shape: all schema fields present by name.
        chunk = events[1]
        assert set(chunk.keys()) == {
            "type",
            "content",
            "error",
            "metadata",
            "tool_calls",
            "tool_result",
        }
        assert chunk["content"] == "Hello "

        thinking = events[0]
        assert thinking["content"] == "pondering"

        done = events[-1]
        assert done["content"] is None
        assert done["metadata"]["tokens_generated"] == 2
    finally:
        _clear_overrides()


async def test_detached_turn_finishes_after_sse_consumer_disconnect(db_session):
    """Losing Android's response socket must not cancel model generation."""
    from app.api.v1.endpoints.chat import _sse_stream

    provider = _GatedProvider()
    ProviderRegistry.register(provider)
    conv_id = await _make_conversation(db_session)
    pushed: list[str] = []

    async def on_disconnected(content: str) -> None:
        pushed.append(content)

    chunks = DetachedChatStream(
        lambda service: service.send_message(
            conversation_id=conv_id,
            user_id="test@example.com",
            content="hi",
        ),
        provider_name=provider.name,
        on_disconnected=on_disconnected,
    )
    frames = _sse_stream(chunks)

    first = await anext(frames)
    assert '"content":"partial "' in first

    # Cancel while the serializer awaits the next queue item, matching the
    # cancellation Starlette delivers after the client socket disappears.
    waiting = asyncio.create_task(anext(frames))
    await asyncio.sleep(0)
    waiting.cancel()
    with pytest.raises(asyncio.CancelledError):
        await waiting

    provider.finish.set()
    await chunks.wait_finished()

    rows = (
        await db_session.execute(
            select(Message).where(Message.conversation_id == conv_id).order_by(Message.seq)
        )
    ).scalars()
    history = [(message.role, message.content) for message in rows]

    assert history == [("user", "hi"), ("assistant", "partial response")]
    assert pushed == ["partial response"]


async def test_client_tool_request_chunk_serializes_with_its_type():
    """A client_tool_request chunk (idea 17) maps to its own SSE event type so
    the desktop client knows to serve the read locally."""
    from app.api.v1.endpoints.chat import _sse_stream

    async def _one() -> AsyncIterator[ChatChunk]:
        yield ChatChunk(
            content="",
            metadata={
                "client_tool_request": {
                    "tool_call_id": "tc-1",
                    "tool_name": "read_file",
                    "args": {"path": "notes.txt"},
                }
            },
        )

    frames = [frame async for frame in _sse_stream(_one())]
    events = [json.loads(f[len("data: ") :]) for f in frames if f.startswith("data: ")]
    assert len(events) == 1
    assert events[0]["type"] == "client_tool_request"
    request = events[0]["metadata"]["client_tool_request"]
    assert request["tool_name"] == "read_file"
    assert request["args"] == {"path": "notes.txt"}


async def test_missing_conversation_yields_error_event_not_http_error(db_session):
    provider = _ScriptedProvider([])
    _install_overrides(db_session, provider)
    try:
        async with _client() as c:
            resp = await c.post(
                "/api/v1/chat/conversations/no-such-conv/chat",
                json={"message": "hi"},
            )
        # The stream is already committed as 200; failures travel as SSE
        # error events.
        assert resp.status_code == 200
        events = [json.loads(f[len("data: ") :]) for f in resp.text.split("\n\n") if f]
        assert len(events) == 1
        assert events[0]["type"] == "error"
        assert events[0]["error"] == "Conversation not found"
        assert events[0]["metadata"]["error_type"] == "not_found"
    finally:
        _clear_overrides()


async def test_provider_crash_mid_stream_emits_error_event(db_session):
    provider = _ScriptedProvider(
        [ChatChunk(content="par", is_finished=False), ChatChunk(content="tial", is_finished=False)],
        raise_after=1,
    )
    conv_id = await _make_conversation(db_session)
    _install_overrides(db_session, provider)
    try:
        async with _client() as c:
            resp = await c.post(
                f"/api/v1/chat/conversations/{conv_id}/chat",
                json={"message": "hi"},
            )
        events = [json.loads(f[len("data: ") :]) for f in resp.text.split("\n\n") if f]
        types = [e["type"] for e in events]
        # The streamed prefix arrives, then the failure is reported as an
        # error event — never a silent truncation.
        assert types[0] == "chunk"
        assert "error" in types
        error = next(e for e in events if e["type"] == "error")
        assert error["metadata"]["error"] is True
    finally:
        _clear_overrides()


async def test_messages_persisted_after_stream(db_session):
    provider = _ScriptedProvider(
        [
            ChatChunk(content="answer", is_finished=False),
            ChatChunk(content="", is_finished=True, metadata={}),
        ]
    )
    conv_id = await _make_conversation(db_session)
    _install_overrides(db_session, provider)
    try:
        async with _client() as c:
            resp = await c.post(
                f"/api/v1/chat/conversations/{conv_id}/chat",
                json={"message": "a question"},
            )
            assert resp.status_code == 200

            detail = await c.get(f"/api/v1/chat/conversations/{conv_id}")
        history = [(m["role"], m["content"]) for m in detail.json()["messages"]]
        assert history == [("user", "a question"), ("assistant", "answer")]
    finally:
        _clear_overrides()


async def test_empty_message_rejected_422(db_session):
    provider = _ScriptedProvider([])
    conv_id = await _make_conversation(db_session)
    _install_overrides(db_session, provider)
    try:
        async with _client() as c:
            resp = await c.post(
                f"/api/v1/chat/conversations/{conv_id}/chat",
                json={"message": ""},
            )
        assert resp.status_code == 422
    finally:
        _clear_overrides()


async def test_chat_stream_requires_auth(db_session):
    async def _override_db():
        yield db_session

    app.dependency_overrides[get_db] = _override_db
    app.dependency_overrides[get_settings] = lambda: _TEST_SETTINGS
    try:
        async with _client() as c:
            resp = await c.post(
                "/api/v1/chat/conversations/x/chat",
                json={"message": "hi"},
            )
        assert resp.status_code in (401, 403)
    finally:
        _clear_overrides()
