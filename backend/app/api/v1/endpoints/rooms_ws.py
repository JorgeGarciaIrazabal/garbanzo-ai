"""WebSocket endpoint for live room updates.

Connect with ``GET /api/v1/ws/rooms/{room_id}?token=<jwt>``. The JWT is the
same token returned by ``/auth/login`` — passed as a query param because
browser WebSocket APIs don't support custom headers.

Events the client can send:
    {"type":"post","content":"..."}          — post a user message
    {"type":"typing","typing":true|false}    — typing indicator broadcast

Events the server sends:
    {"type":"message","message":{...}}       — new message persisted
    {"type":"stream_start","message_id":"...","agent_id":"...","agent_name":"..."}
    {"type":"chunk","message_id":"...","agent_id":"...","content":"..."}
    {"type":"thinking","message_id":"...","agent_id":"...","content":"..."}
    {"type":"done","message_id":"...","agent_id":"..."}
    {"type":"presence","online":[...]}       — online user list
    {"type":"typing","user_id":"...","typing":bool}
    {"type":"error","error":"..."}
"""

from __future__ import annotations

import json
import logging
from typing import Annotated

from fastapi import APIRouter, Depends, Query, WebSocket, WebSocketDisconnect, status

from app.core.config import Settings, get_settings
from app.core.security import decode_token
from app.db.session import async_session_maker
from app.services.room_chat_service import RoomChatService
from app.services.room_connection_manager import room_manager
from app.services.room_service import RoomService

logger = logging.getLogger(__name__)
router = APIRouter()


@router.websocket("/ws/rooms/{room_id}")
async def room_websocket(
    websocket: WebSocket,
    room_id: str,
    settings: Annotated[Settings, Depends(get_settings)],
    token: str = Query(..., description="JWT access token"),
) -> None:
    payload = decode_token(token, settings)
    if payload is None or not payload.get("sub"):
        await websocket.close(code=status.WS_1008_POLICY_VIOLATION)
        return
    # Same rule as the HTTP auth path: refresh tokens must not grant access;
    # tokens issued before the type claim existed count as access tokens.
    if payload.get("type", "access") != "access":
        await websocket.close(code=status.WS_1008_POLICY_VIOLATION)
        return
    user_id = payload["sub"]

    # Verify membership before accepting
    async with async_session_maker() as db:
        svc = RoomService(db)
        room = await svc.get(room_id, viewer_id=user_id)
        if room is None:
            await websocket.close(code=status.WS_1008_POLICY_VIOLATION)
            return
        is_member = any(m.user_id == user_id for m in room.members)
        if not is_member and not room.is_public:
            await websocket.close(code=status.WS_1008_POLICY_VIOLATION)
            return

    await websocket.accept()
    await room_manager.connect(room_id, user_id, websocket)

    try:
        while True:
            raw = await websocket.receive_text()
            try:
                event = json.loads(raw)
            except json.JSONDecodeError:
                await websocket.send_text(
                    json.dumps({"type": "error", "error": "Invalid JSON"})
                )
                continue

            event_type = event.get("type")
            if event_type == "post":
                content = (event.get("content") or "").strip()
                if not content:
                    continue
                async with async_session_maker() as db:
                    # Membership was checked at connect time, but a user can
                    # be removed (or the room deleted/privatized) while the
                    # socket stays open — re-validate before every post.
                    svc = RoomService(db)
                    room = await svc.get(room_id, viewer_id=user_id)
                    still_member = room is not None and (
                        room.is_public
                        or any(m.user_id == user_id for m in room.members)
                    )
                    if not still_member:
                        await websocket.close(
                            code=status.WS_1008_POLICY_VIOLATION
                        )
                        return

                    chat = RoomChatService(db)
                    try:
                        await chat.handle_user_post(
                            room_id=room_id, user_id=user_id, content=content
                        )
                    except Exception:
                        logger.exception("WS handle_user_post failed")
                        await websocket.send_text(
                            json.dumps(
                                {"type": "error", "error": "Failed to post message"}
                            )
                        )
            elif event_type == "typing":
                typing = bool(event.get("typing", False))
                await room_manager.broadcast(
                    room_id,
                    {"type": "typing", "user_id": user_id, "typing": typing},
                )
            else:
                await websocket.send_text(
                    json.dumps(
                        {"type": "error", "error": f"Unknown event: {event_type}"}
                    )
                )
    except WebSocketDisconnect:
        pass
    except Exception:
        logger.exception("WebSocket error in room %s", room_id)
    finally:
        await room_manager.disconnect(room_id, user_id, websocket)
