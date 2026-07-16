"""Tests for room notification muting (Idea 7).

Covers:
  * the ``PATCH /rooms/{id}/members/me/mute`` endpoint (set + unmute)
  * ``RoomChatService._notify_offline_members`` skipping muted members
  * a mute expiring naturally once ``muted_until`` is in the past
  * non-muted members being unaffected
"""

from datetime import UTC, datetime, timedelta
from types import SimpleNamespace
from unittest.mock import AsyncMock, MagicMock, patch

import pytest
from httpx import ASGITransport, AsyncClient

from app.core.config import Settings, get_settings
from app.core.security import get_current_user, hash_password
from app.db.session import get_db
from app.main import app
from app.models.user import User
from app.services.room_chat_service import RoomChatService, _is_muted
from app.services.room_service import MUTE_FOREVER, RoomService

_TEST_SETTINGS = Settings(
    secret_key="test-secret-key-do-not-use-in-prod",
    database_url="sqlite+aiosqlite:///:memory:",
    access_token_expire_minutes=30,
)

OWNER = "test@example.com"  # seeded by conftest
MEMBER = "member@example.com"


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


async def _create_room(client: AsyncClient, **overrides) -> dict:
    payload = {"name": "Test room", **overrides}
    resp = await client.post("/api/v1/rooms", json=payload)
    assert resp.status_code == 201, resp.text
    return resp.json()


def _as_aware(dt: datetime) -> datetime:
    """SQLite (used in tests) round-trips ``DateTime(timezone=True)`` values as
    naive datetimes even though production Postgres preserves the offset —
    treat a naive value as UTC, same as ``room_chat_service._is_muted`` does.
    """
    return dt if dt.tzinfo is not None else dt.replace(tzinfo=UTC)


# ---------------------------------------------------------------- Endpoint


@pytest.mark.asyncio
async def test_mute_endpoint_8h_sets_future_muted_until(db_session):
    switch = _UserSwitch()
    _install_overrides(db_session, switch)
    try:
        async with _client() as c:
            room = await _create_room(c)
            before = datetime.now(UTC)
            resp = await c.patch(
                f"/api/v1/rooms/{room['id']}/members/me/mute", json={"duration": "8h"}
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
            room = await _create_room(c)
            resp = await c.patch(
                f"/api/v1/rooms/{room['id']}/members/me/mute", json={"duration": "forever"}
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
            room = await _create_room(c)
            resp = await c.patch(
                f"/api/v1/rooms/{room['id']}/members/me/mute", json={"duration": "1w"}
            )
            assert resp.json()["muted_until"] is not None

            resp = await c.patch(
                f"/api/v1/rooms/{room['id']}/members/me/mute", json={"duration": "unmute"}
            )
        assert resp.status_code == 200
        assert resp.json()["muted_until"] is None
    finally:
        _clear_overrides()


@pytest.mark.asyncio
async def test_mute_endpoint_requires_membership(db_session):
    """A non-member can see a public room but still can't mute it (403)."""
    await _seed_users(db_session, MEMBER)
    switch = _UserSwitch()
    _install_overrides(db_session, switch)
    try:
        async with _client() as c:
            room = await _create_room(c, is_public=True)
            switch.email = MEMBER
            resp = await c.patch(
                f"/api/v1/rooms/{room['id']}/members/me/mute", json={"duration": "8h"}
            )
        assert resp.status_code == 403
    finally:
        _clear_overrides()


@pytest.mark.asyncio
async def test_mute_endpoint_rejects_unknown_duration(db_session):
    switch = _UserSwitch()
    _install_overrides(db_session, switch)
    try:
        async with _client() as c:
            room = await _create_room(c)
            resp = await c.patch(
                f"/api/v1/rooms/{room['id']}/members/me/mute", json={"duration": "bogus"}
            )
        assert resp.status_code == 422
    finally:
        _clear_overrides()


# --------------------------------------------------- GET /rooms surfaces mute


@pytest.mark.asyncio
async def test_list_rooms_returns_muted_until_for_muted_viewer(db_session):
    switch = _UserSwitch()
    _install_overrides(db_session, switch)
    try:
        async with _client() as c:
            room = await _create_room(c, name="Muted room")
            resp = await c.patch(
                f"/api/v1/rooms/{room['id']}/members/me/mute", json={"duration": "1w"}
            )
            assert resp.json()["muted_until"] is not None

            resp = await c.get("/api/v1/rooms")
        assert resp.status_code == 200
        items = resp.json()["items"]
        listed = next(r for r in items if r["id"] == room["id"])
        assert listed["muted_until"] is not None
    finally:
        _clear_overrides()


@pytest.mark.asyncio
async def test_list_rooms_returns_null_muted_until_for_unmuted_viewer(db_session):
    switch = _UserSwitch()
    _install_overrides(db_session, switch)
    try:
        async with _client() as c:
            room = await _create_room(c, name="Unmuted room")
            resp = await c.get("/api/v1/rooms")
        assert resp.status_code == 200
        items = resp.json()["items"]
        listed = next(r for r in items if r["id"] == room["id"])
        assert listed["muted_until"] is None
    finally:
        _clear_overrides()


@pytest.mark.asyncio
async def test_search_rooms_returns_null_muted_until_for_non_member_public_room(db_session):
    """A non-member viewing a public room via search must not see any member's
    mute state — the viewer isn't in ``room.members`` at all, so it's None."""
    await _seed_users(db_session, MEMBER)
    switch = _UserSwitch()
    _install_overrides(db_session, switch)
    try:
        async with _client() as c:
            room = await _create_room(c, name="Public room", is_public=True)
            resp = await c.patch(
                f"/api/v1/rooms/{room['id']}/members/me/mute", json={"duration": "forever"}
            )
            assert resp.json()["muted_until"] is not None

            switch.email = MEMBER
            resp = await c.get("/api/v1/rooms/search", params={"q": "Public", "scope": "public"})
        assert resp.status_code == 200
        items = resp.json()["items"]
        listed = next(r for r in items if r["id"] == room["id"])
        assert listed["muted_until"] is None
    finally:
        _clear_overrides()


# -------------------------------------------------------------- _is_muted


def test_is_muted_naive_and_aware_future():
    now = datetime.now(UTC)
    assert _is_muted(now + timedelta(hours=1), now) is True
    # Naive datetime (as SQLite round-trips DateTime(timezone=True)) still works.
    assert _is_muted((now + timedelta(hours=1)).replace(tzinfo=None), now) is True


def test_is_muted_past_is_false():
    now = datetime.now(UTC)
    assert _is_muted(now - timedelta(hours=1), now) is False


def test_is_muted_none_is_false():
    assert _is_muted(None, datetime.now(UTC)) is False


# ------------------------------------------------- RoomService.set_mute unit


@pytest.mark.asyncio
async def test_room_service_set_mute_forever_and_unmute(db_session):
    # OWNER (test@example.com) is already seeded by the db_session fixture.
    svc = RoomService(db_session)
    room = await svc.create(owner_id=OWNER, name="Muting room")

    member = await svc.set_mute(room.id, OWNER, "forever")
    assert _as_aware(member.muted_until) == MUTE_FOREVER

    member = await svc.set_mute(room.id, OWNER, "unmute")
    assert member.muted_until is None


# ------------------------------------------ Notification fan-out (mute respected)


def _member(user_id: str, muted_until=None):
    return SimpleNamespace(user_id=user_id, muted_until=muted_until)


def _room(members):
    return SimpleNamespace(id="room-1", name="Muting room", members=members)


class _NoopSessionCtx:
    async def __aenter__(self):
        return MagicMock()

    async def __aexit__(self, *_exc):
        return False


async def _notify(room, **kwargs):
    """Call the real ``_notify_offline_members`` with FCM + DB IO stubbed out."""
    svc = RoomChatService.__new__(RoomChatService)
    send_stub = AsyncMock(return_value=1)
    with (
        patch("app.services.fcm_service.send_to_user", send_stub),
        patch("app.db.session.async_session_maker", MagicMock(return_value=_NoopSessionCtx())),
    ):
        await svc._notify_offline_members(room, **kwargs)
    return send_stub


@pytest.mark.asyncio
async def test_notify_skips_actively_muted_member():
    now = datetime.now(UTC)
    room = _room([_member(MEMBER, muted_until=now + timedelta(hours=1))])
    send_stub = await _notify(
        room, sender_label="Alice", body="hi", message_id="m1", exclude_user_ids=set()
    )
    send_stub.assert_not_called()


@pytest.mark.asyncio
async def test_notify_delivers_after_mute_expired():
    now = datetime.now(UTC)
    room = _room([_member(MEMBER, muted_until=now - timedelta(minutes=1))])
    send_stub = await _notify(
        room, sender_label="Alice", body="hi", message_id="m1", exclude_user_ids=set()
    )
    send_stub.assert_awaited_once()
    assert send_stub.await_args.kwargs["title"] == "Alice in Muting room"


@pytest.mark.asyncio
async def test_notify_delivers_to_non_muted_member():
    room = _room([_member(MEMBER, muted_until=None)])
    send_stub = await _notify(
        room, sender_label="Alice", body="hi", message_id="m1", exclude_user_ids=set()
    )
    send_stub.assert_awaited_once()


@pytest.mark.asyncio
async def test_notify_mixed_muted_and_unmuted_members():
    """Only the actively-muted member is skipped; others still get notified."""
    now = datetime.now(UTC)
    other = "other@example.com"
    room = _room(
        [
            _member(MEMBER, muted_until=now + timedelta(days=1)),
            _member(other, muted_until=None),
        ]
    )
    send_stub = await _notify(
        room, sender_label="Alice", body="hi", message_id="m1", exclude_user_ids=set()
    )
    send_stub.assert_awaited_once()
    assert send_stub.await_args.args[1] == other
