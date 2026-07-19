"""Tests for POST /chat/conversations/{id}/client-tool-result (idea 17).

The desktop client posts here to complete a parked read_file/list_files call.
Covers ownership (404), no-pending-request (409), and the success path where a
parked bridge request is resolved (204).
"""

import asyncio

import pytest
from httpx import ASGITransport, AsyncClient

from app.core.config import Settings, get_settings
from app.core.security import get_current_user, hash_password
from app.db.session import get_db
from app.main import app
from app.models.user import User
from app.services.client_tool_bridge import client_tool_bridge

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
    app.dependency_overrides.pop(get_settings, None)
    app.dependency_overrides.pop(get_current_user, None)


def _client() -> AsyncClient:
    return AsyncClient(transport=ASGITransport(app=app), base_url="http://test")


async def _seed_users(db_session, *emails: str):
    for email in emails:
        db_session.add(User(email=email, hashed_password=hash_password("x")))
    await db_session.commit()


async def _create_conversation(client: AsyncClient) -> dict:
    resp = await client.post("/api/v1/chat/conversations", json={"title": "T"})
    assert resp.status_code == 201, resp.text
    return resp.json()


@pytest.mark.asyncio
async def test_result_409_when_no_pending_request(db_session):
    switch = _UserSwitch()
    _install_overrides(db_session, switch)
    try:
        async with _client() as c:
            conv = await _create_conversation(c)
            resp = await c.post(
                f"/api/v1/chat/conversations/{conv['id']}/client-tool-result",
                json={"tool_call_id": "nope", "ok": True, "entries": []},
            )
        assert resp.status_code == 409
    finally:
        _clear_overrides()


@pytest.mark.asyncio
async def test_result_404_for_non_owner(db_session):
    await _seed_users(db_session, OTHER)
    switch = _UserSwitch()
    _install_overrides(db_session, switch)
    try:
        async with _client() as c:
            conv = await _create_conversation(c)
            switch.email = OTHER
            resp = await c.post(
                f"/api/v1/chat/conversations/{conv['id']}/client-tool-result",
                json={"tool_call_id": "x", "ok": True},
            )
        assert resp.status_code == 404
    finally:
        _clear_overrides()


@pytest.mark.asyncio
async def test_result_resolves_a_parked_request(db_session):
    switch = _UserSwitch()
    _install_overrides(db_session, switch)
    try:
        async with _client() as c:
            conv = await _create_conversation(c)

            received: dict = {}

            async def _emit() -> None:
                pass

            async def _park() -> None:
                received["payload"] = await client_tool_bridge.request(
                    conversation_id=conv["id"],
                    tool_call_id="tc",
                    on_registered=_emit,
                    timeout_seconds=3,
                )

            task = asyncio.create_task(_park())
            # Let the request register its future before we post the result.
            await asyncio.sleep(0.05)

            resp = await c.post(
                f"/api/v1/chat/conversations/{conv['id']}/client-tool-result",
                json={"tool_call_id": "tc", "ok": True, "entries": [{"path": "a.txt"}]},
            )
            assert resp.status_code == 204
            await task

        assert received["payload"]["ok"] is True
        assert received["payload"]["entries"] == [{"path": "a.txt"}]
    finally:
        _clear_overrides()
