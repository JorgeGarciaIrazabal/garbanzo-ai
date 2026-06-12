"""Auth gating tests for the rooms WebSocket endpoint.

The endpoint must mirror the HTTP auth path: only access tokens grant a
connection. Refresh tokens (or garbage) are closed with 1008 before any
database access happens.
"""

from unittest.mock import AsyncMock

import pytest
from starlette import status

from app.api.v1.endpoints.rooms_ws import room_websocket
from app.core.config import Settings
from app.core.security import create_access_token, create_refresh_token

pytestmark = pytest.mark.asyncio


def _ws_mock() -> AsyncMock:
    ws = AsyncMock()
    return ws


async def test_refresh_token_is_rejected_before_accept():
    settings = Settings()
    refresh = create_refresh_token({"sub": "user@example.com"}, settings)
    ws = _ws_mock()

    await room_websocket(ws, "room-1", settings, token=refresh)

    ws.close.assert_awaited_once_with(code=status.WS_1008_POLICY_VIOLATION)
    ws.accept.assert_not_awaited()


async def test_garbage_token_is_rejected_before_accept():
    settings = Settings()
    ws = _ws_mock()

    await room_websocket(ws, "room-1", settings, token="not-a-jwt")

    ws.close.assert_awaited_once_with(code=status.WS_1008_POLICY_VIOLATION)
    ws.accept.assert_not_awaited()


async def test_access_token_passes_the_token_gate(monkeypatch):
    """With a valid access token the handler proceeds to the membership
    check (which we make fail) — proving rejection above was due to the
    token type, not something later in the handler."""
    settings = Settings()
    access = create_access_token({"sub": "user@example.com"}, settings)
    ws = _ws_mock()

    class _FakeRoomService:
        def __init__(self, db):
            pass

        async def get(self, room_id, viewer_id=None):
            return None  # room not found → close, but AFTER the token gate

    monkeypatch.setattr("app.api.v1.endpoints.rooms_ws.RoomService", _FakeRoomService)

    await room_websocket(ws, "room-1", settings, token=access)

    ws.close.assert_awaited_once_with(code=status.WS_1008_POLICY_VIOLATION)
    ws.accept.assert_not_awaited()
