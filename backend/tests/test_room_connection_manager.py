"""Tests for the room WebSocket broker's dead-socket cleanup."""

import pytest

from app.services.room_connection_manager import RoomConnectionManager

pytestmark = pytest.mark.asyncio


class _FakeSocket:
    """Records sent payloads; optionally fails every send."""

    def __init__(self, dead: bool = False):
        self.dead = dead
        self.sent: list[str] = []

    async def send_text(self, payload: str) -> None:
        if self.dead:
            raise ConnectionError("socket closed")
        self.sent.append(payload)


async def _manager_with(room_id, sockets):
    manager = RoomConnectionManager()
    for user_id, ws in sockets:
        # Register directly — connect() would broadcast presence and skew
        # the send counts the tests assert on.
        manager._rooms[room_id][user_id].append(ws)
    return manager


async def test_broadcast_drops_dead_sockets_and_updates_presence():
    alive = _FakeSocket()
    dead = _FakeSocket(dead=True)
    manager = await _manager_with("room-1", [("alice", alive), ("bob", dead)])

    await manager.broadcast("room-1", {"type": "message", "content": "hi"})

    assert manager.online_users("room-1") == ["alice"]
    # Alive socket got the message AND exactly one follow-up presence event.
    assert len(alive.sent) == 2
    assert '"presence"' in alive.sent[1]
    assert '"alice"' in alive.sent[1]
    assert '"bob"' not in alive.sent[1]


async def test_many_dead_sockets_no_recursive_presence_storm():
    """Regression: each dead socket used to trigger disconnect →
    broadcast_presence → disconnect recursion. With N dead sockets the
    survivor must see exactly ONE presence update, not N."""
    alive = _FakeSocket()
    sockets = [("alice", alive)] + [(f"ghost-{i}", _FakeSocket(dead=True)) for i in range(5)]
    manager = await _manager_with("room-1", sockets)

    await manager.broadcast("room-1", {"type": "message", "content": "hi"})

    assert manager.online_users("room-1") == ["alice"]
    presence_events = [p for p in alive.sent if '"presence"' in p]
    assert len(presence_events) == 1


async def test_presence_broadcast_with_dead_socket_terminates():
    # All sockets dead — must clean up without error or infinite recursion.
    manager = await _manager_with(
        "room-1", [("alice", _FakeSocket(dead=True)), ("bob", _FakeSocket(dead=True))]
    )
    await manager.broadcast_presence("room-1")
    assert manager.online_users("room-1") == []


async def test_disconnect_removes_socket_and_notifies_remaining():
    alice_ws = _FakeSocket()
    bob_ws = _FakeSocket()
    manager = await _manager_with("room-1", [("alice", alice_ws), ("bob", bob_ws)])

    await manager.disconnect("room-1", "bob", bob_ws)

    assert manager.online_users("room-1") == ["alice"]
    assert any('"presence"' in p and '"bob"' not in p for p in alice_ws.sent)
