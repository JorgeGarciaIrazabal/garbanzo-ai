"""Tests for conversation notification muting (Idea 8).

Mirrors ``test_room_mute.py`` (Idea 7 — room muting), which this feature
reuses the mute mechanism from. Covers:
  * the ``PATCH /chat/conversations/{id}/mute`` endpoint (set + unmute)
  * ``ConversationService.set_mute`` (forever sentinel, unmute, wrong owner)
  * the disconnect-mid-stream push callback (``_make_push_callback`` in
    ``app/api/v1/endpoints/chat.py``) skipping the push while muted, and
    delivering it once the mute has expired or was never set
"""

from datetime import UTC, datetime, timedelta
from unittest.mock import AsyncMock, MagicMock, patch

import pytest
from httpx import ASGITransport, AsyncClient

from app.api.v1.endpoints.chat import _make_push_callback
from app.core.config import Settings, get_settings
from app.core.security import get_current_user, hash_password
from app.db.session import get_db
from app.main import app
from app.models.user import User
from app.services.conversation_service import ConversationService
from app.services.mute_util import MUTE_FOREVER

_TEST_SETTINGS = Settings(
    secret_key="test-secret-key-do-not-use-in-prod",
    database_url="sqlite+aiosqlite:///:memory:",
    access_token_expire_minutes=30,
)

OWNER = "test@example.com"  # seeded by conftest
OTHER = "other@example.com"


class _UserSwitch:
    def __init__(self, email: str = OWNER):
        self.email = email

    async def __call__(self):
        return {"email": self.email, "token_payload": {}}


def _install_overrides(db_session, switch: _UserSwitch):
    async def _override_db():
        yield db_session

    app.dependency_overrides[get_db] = _override_db
    app.dependency_overrides[get_settings] = lambda: _TEST_SETTINGS
    app.dependency_overrides[get_current_user] = switch


def _clear_overrides():
    app.dependency_overrides.pop(get_db, None)
    app.dependency_overrides.pop(get_current_user, None)


def _client() -> AsyncClient:
    return AsyncClient(transport=ASGITransport(app=app), base_url="http://test")


async def _seed_users(db_session, *emails: str):
    for email in emails:
        db_session.add(User(email=email, hashed_password=hash_password("x")))
    await db_session.commit()


async def _create_conversation(client: AsyncClient, **overrides) -> dict:
    payload = {"title": "Test conversation", **overrides}
    resp = await client.post("/api/v1/chat/conversations", json=payload)
    assert resp.status_code == 201, resp.text
    return resp.json()


def _as_aware(dt: datetime) -> datetime:
    """SQLite (used in tests) round-trips ``DateTime(timezone=True)`` values as
    naive datetimes even though production Postgres preserves the offset —
    treat a naive value as UTC, same as ``mute_util.is_muted`` does.
    """
    return dt if dt.tzinfo is not None else dt.replace(tzinfo=UTC)


# ---------------------------------------------------------------- Endpoint


@pytest.mark.asyncio
async def test_mute_endpoint_8h_sets_future_muted_until(db_session):
    switch = _UserSwitch()
    _install_overrides(db_session, switch)
    try:
        async with _client() as c:
            conv = await _create_conversation(c)
            before = datetime.now(UTC)
            resp = await c.patch(
                f"/api/v1/chat/conversations/{conv['id']}/mute", json={"duration": "8h"}
            )
        assert resp.status_code == 200
        body = resp.json()
        assert body["muted_until"] is not None
        muted_until = _as_aware(datetime.fromisoformat(body["muted_until"]))
        assert (
            before + timedelta(hours=7, minutes=59)
            < muted_until
            < before + timedelta(hours=8, minutes=1)
        )
    finally:
        _clear_overrides()


@pytest.mark.asyncio
async def test_mute_endpoint_forever_uses_sentinel(db_session):
    switch = _UserSwitch()
    _install_overrides(db_session, switch)
    try:
        async with _client() as c:
            conv = await _create_conversation(c)
            resp = await c.patch(
                f"/api/v1/chat/conversations/{conv['id']}/mute",
                json={"duration": "forever"},
            )
        assert resp.status_code == 200
        muted_until = datetime.fromisoformat(resp.json()["muted_until"])
        assert muted_until.year == MUTE_FOREVER.year
    finally:
        _clear_overrides()


@pytest.mark.asyncio
async def test_mute_endpoint_unmute_clears_muted_until(db_session):
    switch = _UserSwitch()
    _install_overrides(db_session, switch)
    try:
        async with _client() as c:
            conv = await _create_conversation(c)
            resp = await c.patch(
                f"/api/v1/chat/conversations/{conv['id']}/mute", json={"duration": "1w"}
            )
            assert resp.json()["muted_until"] is not None

            resp = await c.patch(
                f"/api/v1/chat/conversations/{conv['id']}/mute",
                json={"duration": "unmute"},
            )
        assert resp.status_code == 200
        assert resp.json()["muted_until"] is None
    finally:
        _clear_overrides()


@pytest.mark.asyncio
async def test_mute_endpoint_requires_ownership(db_session):
    """A conversation belongs to exactly one user — another user can't see it
    at all, so muting it 404s just like any other conversation action."""
    await _seed_users(db_session, OTHER)
    switch = _UserSwitch()
    _install_overrides(db_session, switch)
    try:
        async with _client() as c:
            conv = await _create_conversation(c)
            switch.email = OTHER
            resp = await c.patch(
                f"/api/v1/chat/conversations/{conv['id']}/mute", json={"duration": "8h"}
            )
        assert resp.status_code == 404
    finally:
        _clear_overrides()


@pytest.mark.asyncio
async def test_mute_endpoint_rejects_unknown_duration(db_session):
    switch = _UserSwitch()
    _install_overrides(db_session, switch)
    try:
        async with _client() as c:
            conv = await _create_conversation(c)
            resp = await c.patch(
                f"/api/v1/chat/conversations/{conv['id']}/mute",
                json={"duration": "bogus"},
            )
        assert resp.status_code == 422
    finally:
        _clear_overrides()


@pytest.mark.asyncio
async def test_mute_endpoint_404_for_missing_conversation(db_session):
    switch = _UserSwitch()
    _install_overrides(db_session, switch)
    try:
        async with _client() as c:
            resp = await c.patch(
                "/api/v1/chat/conversations/does-not-exist/mute",
                json={"duration": "8h"},
            )
        assert resp.status_code == 404
    finally:
        _clear_overrides()


@pytest.mark.asyncio
async def test_list_conversations_surfaces_muted_until(db_session):
    switch = _UserSwitch()
    _install_overrides(db_session, switch)
    try:
        async with _client() as c:
            conv = await _create_conversation(c, title="Muted convo")
            resp = await c.patch(
                f"/api/v1/chat/conversations/{conv['id']}/mute", json={"duration": "1w"}
            )
            assert resp.json()["muted_until"] is not None

            resp = await c.get("/api/v1/chat/conversations")
        assert resp.status_code == 200
        items = resp.json()["items"]
        listed = next(i for i in items if i["id"] == conv["id"])
        assert listed["muted_until"] is not None
    finally:
        _clear_overrides()


# ------------------------------------------- ConversationService.set_mute


@pytest.mark.asyncio
async def test_conversation_service_set_mute_forever_and_unmute(db_session):
    svc = ConversationService(db_session)
    conv = await svc.create(user_id=OWNER, title="Muting convo")

    updated = await svc.set_mute(conv.id, OWNER, "forever")
    assert updated is not None
    assert _as_aware(updated.muted_until) == MUTE_FOREVER

    updated = await svc.set_mute(conv.id, OWNER, "unmute")
    assert updated is not None
    assert updated.muted_until is None


@pytest.mark.asyncio
async def test_conversation_service_set_mute_returns_none_for_wrong_owner(db_session):
    await _seed_users(db_session, OTHER)
    svc = ConversationService(db_session)
    conv = await svc.create(user_id=OWNER, title="Private convo")

    assert await svc.set_mute(conv.id, OTHER, "8h") is None


@pytest.mark.asyncio
async def test_conversation_service_set_mute_returns_none_for_missing_conversation(
    db_session,
):
    svc = ConversationService(db_session)
    assert await svc.set_mute("does-not-exist", OWNER, "8h") is None


# -------------------------------------- disconnect-mid-stream push callback


class _SessionCtx:
    """Hands the test's own ``db_session`` back through the async-with
    protocol, so ``_push``'s ``async_session_maker()`` call sees the same
    in-memory SQLite data the test set up directly."""

    def __init__(self, session):
        self._session = session

    async def __aenter__(self):
        return self._session

    async def __aexit__(self, *_exc):
        return False


async def _push_after_disconnect(db_session, user_id: str, conversation_id: str, body: str):
    """Invoke the real ``_make_push_callback`` callback with FCM IO stubbed
    and ``async_session_maker`` rerouted to the test's own session."""
    send_stub = AsyncMock(return_value=1)
    with (
        patch("app.services.fcm_service.send_to_user", send_stub),
        patch(
            "app.db.session.async_session_maker",
            MagicMock(return_value=_SessionCtx(db_session)),
        ),
    ):
        callback = _make_push_callback(user_id, conversation_id)
        await callback(body)
    return send_stub


@pytest.mark.asyncio
async def test_push_skipped_while_conversation_actively_muted(db_session):
    svc = ConversationService(db_session)
    conv = await svc.create(user_id=OWNER, title="Muted convo")
    await svc.set_mute(conv.id, OWNER, "forever")

    send_stub = await _push_after_disconnect(db_session, OWNER, conv.id, "hi there")
    send_stub.assert_not_called()


@pytest.mark.asyncio
async def test_push_delivered_after_mute_expired(db_session):
    svc = ConversationService(db_session)
    conv = await svc.create(user_id=OWNER, title="Expired mute convo")
    conv.muted_until = datetime.now(UTC) - timedelta(minutes=1)
    await db_session.commit()

    send_stub = await _push_after_disconnect(db_session, OWNER, conv.id, "hi there")
    send_stub.assert_awaited_once()
    assert send_stub.await_args.kwargs["title"] == "Response ready"


@pytest.mark.asyncio
async def test_push_delivered_when_conversation_not_muted(db_session):
    svc = ConversationService(db_session)
    conv = await svc.create(user_id=OWNER, title="Unmuted convo")

    send_stub = await _push_after_disconnect(db_session, OWNER, conv.id, "hi there")
    send_stub.assert_awaited_once()


@pytest.mark.asyncio
async def test_push_skips_empty_accumulated_content_regardless_of_mute(db_session):
    svc = ConversationService(db_session)
    conv = await svc.create(user_id=OWNER, title="Empty body convo")

    send_stub = await _push_after_disconnect(db_session, OWNER, conv.id, "   ")
    send_stub.assert_not_called()
