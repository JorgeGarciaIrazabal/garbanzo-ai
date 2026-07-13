"""Integration tests for the /api/v1/rooms REST endpoints.

The service layer is covered by test_rooms_service.py; these tests pin the
HTTP contract: status codes, authorization (owner vs member vs outsider),
and the export formats.
"""

import uuid

import pytest
from httpx import ASGITransport, AsyncClient

from app.core.config import Settings, get_settings
from app.core.security import get_current_user, hash_password
from app.db.session import get_db
from app.main import app
from app.models.room import RoomMessage
from app.models.user import User

pytestmark = pytest.mark.asyncio


_TEST_SETTINGS = Settings(
    secret_key="test-secret-key-do-not-use-in-prod",
    database_url="sqlite+aiosqlite:///:memory:",
    access_token_expire_minutes=30,
)

OWNER = "test@example.com"  # seeded by conftest
MEMBER = "member@example.com"
OUTSIDER = "outsider@example.com"


class _UserSwitch:
    """Mutable auth override so one test can act as several users."""

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
    # Intentionally do NOT pop get_settings — sibling test modules install a
    # process-wide override at import time; popping it here exposes later
    # tests to the real settings (and real DATABASE_URL).


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


# ---------------------------------------------------------------------- CRUD


async def test_create_room_includes_owner_and_invitees(db_session):
    await _seed_users(db_session, MEMBER)
    switch = _UserSwitch()
    _install_overrides(db_session, switch)
    try:
        async with _client() as c:
            room = await _create_room(c, member_emails=[MEMBER])
        assert room["owner_id"] == OWNER
        member_ids = {m["user_id"] for m in room["members"]}
        assert member_ids == {OWNER, MEMBER}
    finally:
        _clear_overrides()


async def test_create_room_with_unknown_invitee_400(db_session):
    switch = _UserSwitch()
    _install_overrides(db_session, switch)
    try:
        async with _client() as c:
            resp = await c.post(
                "/api/v1/rooms",
                json={"name": "Bad room", "member_emails": ["ghost@example.com"]},
            )
        assert resp.status_code == 400
        assert "ghost@example.com" in resp.json()["detail"]
    finally:
        _clear_overrides()


async def test_list_rooms_only_shows_memberships(db_session):
    await _seed_users(db_session, OUTSIDER)
    switch = _UserSwitch()
    _install_overrides(db_session, switch)
    try:
        async with _client() as c:
            await _create_room(c, name="Mine")
            switch.email = OUTSIDER
            await _create_room(c, name="Theirs")

            switch.email = OWNER
            resp = await c.get("/api/v1/rooms")
        assert resp.status_code == 200
        body = resp.json()
        assert body["total"] == 1
        assert body["items"][0]["name"] == "Mine"
    finally:
        _clear_overrides()


async def test_get_private_room_as_outsider_404(db_session):
    await _seed_users(db_session, OUTSIDER)
    switch = _UserSwitch()
    _install_overrides(db_session, switch)
    try:
        async with _client() as c:
            room = await _create_room(c)
            switch.email = OUTSIDER
            resp = await c.get(f"/api/v1/rooms/{room['id']}")
        assert resp.status_code == 404
    finally:
        _clear_overrides()


async def test_update_room_owner_only(db_session):
    await _seed_users(db_session, MEMBER)
    switch = _UserSwitch()
    _install_overrides(db_session, switch)
    try:
        async with _client() as c:
            room = await _create_room(c, member_emails=[MEMBER])

            resp = await c.patch(f"/api/v1/rooms/{room['id']}", json={"name": "Renamed"})
            assert resp.status_code == 200
            assert resp.json()["name"] == "Renamed"

            switch.email = MEMBER
            resp = await c.patch(f"/api/v1/rooms/{room['id']}", json={"name": "Hijacked"})
            assert resp.status_code == 403
    finally:
        _clear_overrides()


async def test_delete_room_owner_only_then_404(db_session):
    await _seed_users(db_session, MEMBER)
    switch = _UserSwitch()
    _install_overrides(db_session, switch)
    try:
        async with _client() as c:
            room = await _create_room(c, member_emails=[MEMBER])

            switch.email = MEMBER
            resp = await c.delete(f"/api/v1/rooms/{room['id']}")
            assert resp.status_code == 403

            switch.email = OWNER
            resp = await c.delete(f"/api/v1/rooms/{room['id']}")
            assert resp.status_code == 204

            resp = await c.get(f"/api/v1/rooms/{room['id']}")
            assert resp.status_code == 404
    finally:
        _clear_overrides()


async def test_delete_missing_room_404(db_session):
    switch = _UserSwitch()
    _install_overrides(db_session, switch)
    try:
        async with _client() as c:
            resp = await c.delete("/api/v1/rooms/no-such-room")
        assert resp.status_code == 404
    finally:
        _clear_overrides()


# -------------------------------------------------------------------- Members


async def test_member_add_list_remove_flow(db_session):
    await _seed_users(db_session, MEMBER)
    switch = _UserSwitch()
    _install_overrides(db_session, switch)
    try:
        async with _client() as c:
            room = await _create_room(c)

            resp = await c.post(f"/api/v1/rooms/{room['id']}/members", json={"user_id": MEMBER})
            assert resp.status_code == 201
            assert resp.json()["user_id"] == MEMBER

            resp = await c.get(f"/api/v1/rooms/{room['id']}/members")
            assert resp.status_code == 200
            assert {m["user_id"] for m in resp.json()} == {OWNER, MEMBER}

            resp = await c.delete(f"/api/v1/rooms/{room['id']}/members/{MEMBER}")
            assert resp.status_code == 204

            resp = await c.get(f"/api/v1/rooms/{room['id']}/members")
            assert {m["user_id"] for m in resp.json()} == {OWNER}
    finally:
        _clear_overrides()


async def test_member_cannot_add_members(db_session):
    await _seed_users(db_session, MEMBER, OUTSIDER)
    switch = _UserSwitch()
    _install_overrides(db_session, switch)
    try:
        async with _client() as c:
            room = await _create_room(c, member_emails=[MEMBER])
            switch.email = MEMBER
            resp = await c.post(f"/api/v1/rooms/{room['id']}/members", json={"user_id": OUTSIDER})
        assert resp.status_code == 403
    finally:
        _clear_overrides()


async def test_owner_cannot_be_removed(db_session):
    switch = _UserSwitch()
    _install_overrides(db_session, switch)
    try:
        async with _client() as c:
            room = await _create_room(c)
            resp = await c.delete(f"/api/v1/rooms/{room['id']}/members/{OWNER}")
        assert resp.status_code == 403
    finally:
        _clear_overrides()


async def test_outsider_cannot_list_members_of_public_room(db_session):
    await _seed_users(db_session, OUTSIDER)
    switch = _UserSwitch()
    _install_overrides(db_session, switch)
    try:
        async with _client() as c:
            room = await _create_room(c, is_public=True)
            switch.email = OUTSIDER
            resp = await c.get(f"/api/v1/rooms/{room['id']}/members")
        # Public rooms are visible to outsiders, but member-only actions
        # still require membership.
        assert resp.status_code == 403
    finally:
        _clear_overrides()


# --------------------------------------------------------------------- Agents


async def test_agent_crud_flow(db_session):
    switch = _UserSwitch()
    _install_overrides(db_session, switch)
    try:
        async with _client() as c:
            room = await _create_room(c)

            resp = await c.post(
                f"/api/v1/rooms/{room['id']}/agents",
                json={"name": "Ada", "model": "llama3.2"},
            )
            assert resp.status_code == 201
            agent = resp.json()
            assert agent["name"] == "Ada"

            resp = await c.get(f"/api/v1/rooms/{room['id']}/agents")
            assert resp.status_code == 200
            assert [a["id"] for a in resp.json()] == [agent["id"]]

            resp = await c.patch(
                f"/api/v1/rooms/{room['id']}/agents/{agent['id']}",
                json={"name": "Grace", "response_mode": "always"},
            )
            assert resp.status_code == 200
            assert resp.json()["name"] == "Grace"
            assert resp.json()["response_mode"] == "always"

            resp = await c.delete(f"/api/v1/rooms/{room['id']}/agents/{agent['id']}")
            assert resp.status_code == 204

            resp = await c.get(f"/api/v1/rooms/{room['id']}/agents")
            assert resp.json() == []
    finally:
        _clear_overrides()


async def test_member_cannot_manage_agents(db_session):
    await _seed_users(db_session, MEMBER)
    switch = _UserSwitch()
    _install_overrides(db_session, switch)
    try:
        async with _client() as c:
            room = await _create_room(c, member_emails=[MEMBER])
            switch.email = MEMBER
            resp = await c.post(
                f"/api/v1/rooms/{room['id']}/agents",
                json={"name": "Rogue", "model": "llama3.2"},
            )
        assert resp.status_code == 403
    finally:
        _clear_overrides()


async def test_update_missing_agent_404(db_session):
    switch = _UserSwitch()
    _install_overrides(db_session, switch)
    try:
        async with _client() as c:
            room = await _create_room(c)
            resp = await c.patch(
                f"/api/v1/rooms/{room['id']}/agents/no-such-agent",
                json={"name": "Ghost"},
            )
        assert resp.status_code == 404
    finally:
        _clear_overrides()


# ------------------------------------------------------------------- Messages


async def _seed_messages(db_session, room_id: str, *contents: str):
    for content in contents:
        db_session.add(
            RoomMessage(
                id=str(uuid.uuid4()),
                room_id=room_id,
                role="user",
                sender_user_id=OWNER,
                content=content,
            )
        )
    await db_session.commit()


async def test_list_messages_requires_membership(db_session):
    await _seed_users(db_session, OUTSIDER)
    switch = _UserSwitch()
    _install_overrides(db_session, switch)
    try:
        async with _client() as c:
            room = await _create_room(c)
            await _seed_messages(db_session, room["id"], "hello", "world")

            resp = await c.get(f"/api/v1/rooms/{room['id']}/messages")
            assert resp.status_code == 200
            assert resp.json()["total"] == 2

            switch.email = OUTSIDER
            resp = await c.get(f"/api/v1/rooms/{room['id']}/messages")
            assert resp.status_code == 404
    finally:
        _clear_overrides()


# --------------------------------------------------------------------- Export


async def test_export_markdown_contains_transcript(db_session):
    switch = _UserSwitch()
    _install_overrides(db_session, switch)
    try:
        async with _client() as c:
            room = await _create_room(c, name="Export room", description="A test room")
            await _seed_messages(db_session, room["id"], "first message", "second message")

            resp = await c.get(f"/api/v1/rooms/{room['id']}/export")
        assert resp.status_code == 200
        assert resp.headers["content-type"].startswith("text/markdown")
        body = resp.text
        assert "# Export room" in body
        assert "A test room" in body
        assert f"**{OWNER}**" in body
        assert "first message" in body
        assert "second message" in body
    finally:
        _clear_overrides()


async def test_export_json_returns_room_and_messages(db_session):
    switch = _UserSwitch()
    _install_overrides(db_session, switch)
    try:
        async with _client() as c:
            room = await _create_room(c, name="Export room")
            await _seed_messages(db_session, room["id"], "only message")

            resp = await c.get(f"/api/v1/rooms/{room['id']}/export?format=json")
        assert resp.status_code == 200
        body = resp.json()
        assert body["room"]["id"] == room["id"]
        assert [m["content"] for m in body["messages"]] == ["only message"]
    finally:
        _clear_overrides()


async def test_export_rejects_unknown_format(db_session):
    switch = _UserSwitch()
    _install_overrides(db_session, switch)
    try:
        async with _client() as c:
            room = await _create_room(c)
            resp = await c.get(f"/api/v1/rooms/{room['id']}/export?format=csv")
        assert resp.status_code == 422
    finally:
        _clear_overrides()


async def test_export_requires_membership(db_session):
    await _seed_users(db_session, OUTSIDER)
    switch = _UserSwitch()
    _install_overrides(db_session, switch)
    try:
        async with _client() as c:
            room = await _create_room(c)
            switch.email = OUTSIDER
            resp = await c.get(f"/api/v1/rooms/{room['id']}/export")
        assert resp.status_code == 404
    finally:
        _clear_overrides()
