"""In-memory WebSocket broker for room live events.

Keeps a mapping of ``room_id -> { user_email -> list[WebSocket] }``. Broadcasts
are best-effort: if a send to one socket fails, we drop that socket and keep
going. Presence events are derived from the set of connected user emails for a
room.

This is a single-process broker. Horizontal scaling would require Redis pub/sub
or equivalent — explicitly out of scope for the initial rooms feature.
"""

from __future__ import annotations

import asyncio
import json
import logging
from collections import defaultdict
from typing import Any

from fastapi import WebSocket

from app.schemas.room import RoomPresenceEvent

logger = logging.getLogger(__name__)


class RoomConnectionManager:
    """Singleton broker for room WebSocket fan-out."""

    def __init__(self) -> None:
        self._rooms: dict[str, dict[str, list[WebSocket]]] = defaultdict(
            lambda: defaultdict(list)
        )
        self._lock = asyncio.Lock()

    async def connect(self, room_id: str, user_id: str, ws: WebSocket) -> None:
        async with self._lock:
            self._rooms[room_id][user_id].append(ws)
        logger.debug("WS connect room=%s user=%s", room_id, user_id)
        await self.broadcast_presence(room_id)

    async def _remove(self, room_id: str, user_id: str, ws: WebSocket) -> None:
        """Drop a socket from the registry without any broadcasting."""
        async with self._lock:
            sockets = self._rooms.get(room_id, {}).get(user_id)
            if sockets and ws in sockets:
                sockets.remove(ws)
            # Cleanup empty keys
            if sockets is not None and not sockets:
                self._rooms[room_id].pop(user_id, None)
            if room_id in self._rooms and not self._rooms[room_id]:
                self._rooms.pop(room_id, None)

    async def disconnect(self, room_id: str, user_id: str, ws: WebSocket) -> None:
        await self._remove(room_id, user_id, ws)
        logger.debug("WS disconnect room=%s user=%s", room_id, user_id)
        await self.broadcast_presence(room_id)

    def online_users(self, room_id: str) -> list[str]:
        return sorted(self._rooms.get(room_id, {}).keys())

    def is_user_online(self, room_id: str, user_id: str) -> bool:
        return bool(self._rooms.get(room_id, {}).get(user_id))

    async def _send_to_room(self, room_id: str, payload: str) -> int:
        """Send ``payload`` to every socket in the room.

        Failed sockets are removed from the registry (without broadcasting),
        so a single cleanup pass happens outside the send loop instead of
        recursing disconnect → broadcast_presence → disconnect. Returns the
        number of dead sockets removed.
        """
        async with self._lock:
            sockets = [
                (user_id, ws)
                for user_id, ws_list in self._rooms.get(room_id, {}).items()
                for ws in ws_list
            ]

        dead: list[tuple[str, WebSocket]] = []
        for user_id, ws in sockets:
            try:
                await ws.send_text(payload)
            except Exception:
                dead.append((user_id, ws))

        for user_id, ws in dead:
            logger.debug("WS dropped dead socket room=%s user=%s", room_id, user_id)
            await self._remove(room_id, user_id, ws)
        return len(dead)

    async def broadcast(self, room_id: str, event: dict[str, Any]) -> None:
        """Send ``event`` as JSON to every socket currently in ``room_id``."""
        dropped = await self._send_to_room(room_id, json.dumps(event, default=str))
        if dropped:
            # One presence update reflecting the cleanup — never per-socket.
            await self.broadcast_presence(room_id)

    async def broadcast_presence(self, room_id: str) -> None:
        # Typed event (see app.schemas.room.RoomPresenceEvent). Serialized via
        # json.dumps(model_dump()) so the wire bytes are unchanged.
        event = RoomPresenceEvent(online=self.online_users(room_id)).model_dump()
        # Sockets that die here are removed but deliberately do NOT trigger
        # another presence broadcast — the next presence-changing event
        # carries the corrected list. (This was the recursion source.)
        await self._send_to_room(room_id, json.dumps(event))


# Module-level singleton
room_manager = RoomConnectionManager()
