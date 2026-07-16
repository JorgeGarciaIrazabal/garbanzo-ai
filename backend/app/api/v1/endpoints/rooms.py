"""REST endpoints for multi-person chat rooms."""

from __future__ import annotations

import logging
from typing import Annotated, Any

from fastapi import APIRouter, Depends, HTTPException, Query, status
from fastapi.responses import PlainTextResponse
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.security import get_current_user
from app.db.session import get_db
from app.schemas.mute import MuteUpdate
from app.schemas.room import (
    RoomAgentCreate,
    RoomAgentOut,
    RoomAgentUpdate,
    RoomChatPost,
    RoomCreate,
    RoomDetailOut,
    RoomExport,
    RoomList,
    RoomMemberAdd,
    RoomMemberOut,
    RoomMessageList,
    RoomMessageOut,
    RoomOut,
    RoomUpdate,
)
from app.services.room_service import (
    RoomNotFoundError,
    RoomPermissionError,
    RoomService,
    UnknownUserError,
)

logger = logging.getLogger(__name__)
router = APIRouter()


def _service(db: AsyncSession = Depends(get_db)) -> RoomService:
    return RoomService(db)


async def _require_visible_room(service: RoomService, room_id: str, user_id: str):
    room = await service.get(room_id, viewer_id=user_id)
    if room is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, detail="Room not found")
    return room


async def _require_member(service: RoomService, room_id: str, user_id: str):
    room = await _require_visible_room(service, room_id, user_id)
    if not any(m.user_id == user_id for m in room.members):
        raise HTTPException(status.HTTP_403_FORBIDDEN, detail="Not a room member")
    return room


# ---------------------------------------------------------------------- Rooms


@router.post(
    "",
    response_model=RoomDetailOut,
    status_code=status.HTTP_201_CREATED,
    summary="Create a new room",
)
async def create_room(
    data: RoomCreate,
    current_user: Annotated[dict[str, Any], Depends(get_current_user)],
    service: Annotated[RoomService, Depends(_service)],
) -> RoomDetailOut:
    try:
        room = await service.create(
            owner_id=current_user["email"],
            name=data.name,
            description=data.description,
            is_public=data.is_public,
            max_agent_turn_depth=data.max_agent_turn_depth,
            mode=data.mode,
            member_emails=data.member_emails,
        )
    except UnknownUserError as e:
        raise HTTPException(
            status.HTTP_400_BAD_REQUEST,
            detail=f"Unknown user email(s): {', '.join(e.emails)}",
        ) from e
    except RoomPermissionError as e:
        raise HTTPException(status.HTTP_403_FORBIDDEN, detail=str(e)) from e
    return RoomDetailOut.from_model(room)


@router.get("", response_model=RoomList, summary="List rooms the user belongs to")
async def list_rooms(
    current_user: Annotated[dict[str, Any], Depends(get_current_user)],
    service: Annotated[RoomService, Depends(_service)],
    page: int = Query(1, ge=1),
    page_size: int = Query(20, ge=1, le=100),
) -> RoomList:
    rooms, total = await service.list_for_user(
        current_user["email"], page=page, page_size=page_size
    )
    return RoomList(
        items=[RoomOut.from_model(r, viewer_email=current_user["email"]) for r in rooms],
        total=total,
        page=page,
        page_size=page_size,
    )


@router.get("/search", response_model=RoomList, summary="Search rooms")
async def search_rooms(
    current_user: Annotated[dict[str, Any], Depends(get_current_user)],
    service: Annotated[RoomService, Depends(_service)],
    q: str = Query(..., min_length=1),
    scope: str = Query("all", pattern="^(all|mine|public)$"),
    page: int = Query(1, ge=1),
    page_size: int = Query(20, ge=1, le=100),
) -> RoomList:
    hits, total = await service.search(
        viewer_id=current_user["email"],
        query=q,
        scope=scope,
        page=page,
        page_size=page_size,
    )
    return RoomList(
        items=[RoomOut.from_model(h.room, viewer_email=current_user["email"]) for h in hits],
        total=total,
        page=page,
        page_size=page_size,
    )


@router.get("/{room_id}", response_model=RoomDetailOut, summary="Get room details")
async def get_room(
    room_id: str,
    current_user: Annotated[dict[str, Any], Depends(get_current_user)],
    service: Annotated[RoomService, Depends(_service)],
) -> RoomDetailOut:
    room = await _require_visible_room(service, room_id, current_user["email"])
    return RoomDetailOut.from_model(room)


@router.patch("/{room_id}", response_model=RoomDetailOut, summary="Update room")
async def update_room(
    room_id: str,
    data: RoomUpdate,
    current_user: Annotated[dict[str, Any], Depends(get_current_user)],
    service: Annotated[RoomService, Depends(_service)],
) -> RoomDetailOut:
    try:
        room = await service.update(
            room_id=room_id,
            user_id=current_user["email"],
            name=data.name,
            description=data.description,
            is_public=data.is_public,
            max_agent_turn_depth=data.max_agent_turn_depth,
            mode=data.mode,
            owner_id=data.owner_id,
        )
    except RoomNotFoundError as e:
        raise HTTPException(status.HTTP_404_NOT_FOUND, detail="Room not found") from e
    except RoomPermissionError as e:
        raise HTTPException(status.HTTP_403_FORBIDDEN, detail=str(e)) from e
    return RoomDetailOut.from_model(room)


@router.delete(
    "/{room_id}",
    status_code=status.HTTP_204_NO_CONTENT,
    response_model=None,
    summary="Delete room",
)
async def delete_room(
    room_id: str,
    current_user: Annotated[dict[str, Any], Depends(get_current_user)],
    service: Annotated[RoomService, Depends(_service)],
) -> None:
    try:
        await service.delete(room_id=room_id, user_id=current_user["email"])
    except RoomNotFoundError as e:
        raise HTTPException(status.HTTP_404_NOT_FOUND, detail="Room not found") from e
    except RoomPermissionError as e:
        raise HTTPException(status.HTTP_403_FORBIDDEN, detail=str(e)) from e


# -------------------------------------------------------------------- Members


@router.get(
    "/{room_id}/members",
    response_model=list[RoomMemberOut],
    summary="List members",
)
async def list_members(
    room_id: str,
    current_user: Annotated[dict[str, Any], Depends(get_current_user)],
    service: Annotated[RoomService, Depends(_service)],
) -> list[RoomMemberOut]:
    await _require_member(service, room_id, current_user["email"])
    members = await service.list_members(room_id)
    return [RoomMemberOut.from_model(m) for m in members]


@router.post(
    "/{room_id}/members",
    response_model=RoomMemberOut,
    status_code=status.HTTP_201_CREATED,
    summary="Add a member to the room",
)
async def add_member(
    room_id: str,
    data: RoomMemberAdd,
    current_user: Annotated[dict[str, Any], Depends(get_current_user)],
    service: Annotated[RoomService, Depends(_service)],
) -> RoomMemberOut:
    try:
        member = await service.add_member(
            room_id=room_id,
            user_id=current_user["email"],
            new_user_id=data.user_id,
            role=data.role,
        )
    except RoomNotFoundError as e:
        raise HTTPException(status.HTTP_404_NOT_FOUND, detail="Room not found") from e
    except RoomPermissionError as e:
        raise HTTPException(status.HTTP_403_FORBIDDEN, detail=str(e)) from e
    return RoomMemberOut.from_model(member)


@router.delete(
    "/{room_id}/members/{user_email}",
    status_code=status.HTTP_204_NO_CONTENT,
    response_model=None,
    summary="Remove a member from the room",
)
async def remove_member(
    room_id: str,
    user_email: str,
    current_user: Annotated[dict[str, Any], Depends(get_current_user)],
    service: Annotated[RoomService, Depends(_service)],
) -> None:
    try:
        await service.remove_member(
            room_id=room_id,
            user_id=current_user["email"],
            target_user_id=user_email,
        )
    except RoomNotFoundError as e:
        raise HTTPException(status.HTTP_404_NOT_FOUND, detail="Room not found") from e
    except RoomPermissionError as e:
        raise HTTPException(status.HTTP_403_FORBIDDEN, detail=str(e)) from e


@router.patch(
    "/{room_id}/members/me/mute",
    response_model=RoomMemberOut,
    summary="Mute or unmute room notifications for the current user",
)
async def mute_room(
    room_id: str,
    data: MuteUpdate,
    current_user: Annotated[dict[str, Any], Depends(get_current_user)],
    service: Annotated[RoomService, Depends(_service)],
) -> RoomMemberOut:
    await _require_member(service, room_id, current_user["email"])
    try:
        member = await service.set_mute(
            room_id=room_id, user_id=current_user["email"], duration=data.duration
        )
    except RoomNotFoundError as e:
        raise HTTPException(status.HTTP_404_NOT_FOUND, detail="Not a room member") from e
    return RoomMemberOut.from_model(member)


# --------------------------------------------------------------------- Agents


@router.get(
    "/{room_id}/agents",
    response_model=list[RoomAgentOut],
    summary="List agents",
)
async def list_agents(
    room_id: str,
    current_user: Annotated[dict[str, Any], Depends(get_current_user)],
    service: Annotated[RoomService, Depends(_service)],
) -> list[RoomAgentOut]:
    await _require_member(service, room_id, current_user["email"])
    agents = await service.list_agents(room_id)
    return [RoomAgentOut.model_validate(a) for a in agents]


@router.post(
    "/{room_id}/agents",
    response_model=RoomAgentOut,
    status_code=status.HTTP_201_CREATED,
    summary="Add an agent to the room",
)
async def add_agent(
    room_id: str,
    data: RoomAgentCreate,
    current_user: Annotated[dict[str, Any], Depends(get_current_user)],
    service: Annotated[RoomService, Depends(_service)],
) -> RoomAgentOut:
    try:
        agent = await service.add_agent(
            room_id=room_id,
            user_id=current_user["email"],
            name=data.name,
            avatar=data.avatar,
            provider=data.provider,
            model=data.model,
            system_prompt=data.system_prompt,
            response_mode=data.response_mode,
            turn_order=data.turn_order,
            is_active=data.is_active,
            is_moderator=data.is_moderator,
            enabled_tools=data.enabled_tools,
        )
    except RoomNotFoundError as e:
        raise HTTPException(status.HTTP_404_NOT_FOUND, detail="Room not found") from e
    except RoomPermissionError as e:
        raise HTTPException(status.HTTP_403_FORBIDDEN, detail=str(e)) from e
    return RoomAgentOut.model_validate(agent)


@router.patch(
    "/{room_id}/agents/{agent_id}",
    response_model=RoomAgentOut,
    summary="Update an agent",
)
async def update_agent(
    room_id: str,
    agent_id: str,
    data: RoomAgentUpdate,
    current_user: Annotated[dict[str, Any], Depends(get_current_user)],
    service: Annotated[RoomService, Depends(_service)],
) -> RoomAgentOut:
    payload = {k: v for k, v in data.model_dump(exclude_unset=True).items()}
    try:
        agent = await service.update_agent(
            room_id=room_id,
            user_id=current_user["email"],
            agent_id=agent_id,
            **payload,
        )
    except RoomNotFoundError as e:
        raise HTTPException(status.HTTP_404_NOT_FOUND, detail="Not found") from e
    except RoomPermissionError as e:
        raise HTTPException(status.HTTP_403_FORBIDDEN, detail=str(e)) from e
    return RoomAgentOut.model_validate(agent)


@router.delete(
    "/{room_id}/agents/{agent_id}",
    status_code=status.HTTP_204_NO_CONTENT,
    response_model=None,
    summary="Remove an agent",
)
async def delete_agent(
    room_id: str,
    agent_id: str,
    current_user: Annotated[dict[str, Any], Depends(get_current_user)],
    service: Annotated[RoomService, Depends(_service)],
) -> None:
    try:
        await service.delete_agent(
            room_id=room_id, user_id=current_user["email"], agent_id=agent_id
        )
    except RoomNotFoundError as e:
        raise HTTPException(status.HTTP_404_NOT_FOUND, detail="Not found") from e
    except RoomPermissionError as e:
        raise HTTPException(status.HTTP_403_FORBIDDEN, detail=str(e)) from e


# ------------------------------------------------------------------- Messages


@router.get(
    "/{room_id}/messages",
    response_model=RoomMessageList,
    summary="Paginated message history",
)
async def list_room_messages(
    room_id: str,
    current_user: Annotated[dict[str, Any], Depends(get_current_user)],
    service: Annotated[RoomService, Depends(_service)],
    page: int = Query(1, ge=1),
    page_size: int = Query(50, ge=1, le=200),
) -> RoomMessageList:
    await _require_member(service, room_id, current_user["email"])
    msgs, total = await service.list_messages(room_id, page=page, page_size=page_size)
    return RoomMessageList(
        items=[RoomMessageOut.model_validate(m) for m in msgs],
        total=total,
        page=page,
        page_size=page_size,
    )


@router.post(
    "/{room_id}/chat",
    summary="Post a user message to the room (REST fallback — WebSocket is preferred)",
)
async def post_room_message(
    room_id: str,
    data: RoomChatPost,
    current_user: Annotated[dict[str, Any], Depends(get_current_user)],
    service: Annotated[RoomService, Depends(_service)],
    db: Annotated[AsyncSession, Depends(get_db)],
) -> dict[str, Any]:
    """Non-streaming REST entry point. Used for smoke-testing and fallback clients.

    Agent responses are streamed over WebSocket to any connected members; this
    endpoint returns once all agent turns complete.
    """
    await _require_member(service, room_id, current_user["email"])

    from app.services.room_chat_service import RoomChatService

    chat = RoomChatService(db)
    posted = await chat.handle_user_post(
        room_id=room_id,
        user_id=current_user["email"],
        content=data.content,
        attachments=data.attachments or None,
    )
    return {"posted_message_id": posted.id}


# -------------------------------------------------------------------- Export


@router.get("/{room_id}/export", summary="Export room transcript")
async def export_room(
    room_id: str,
    current_user: Annotated[dict[str, Any], Depends(get_current_user)],
    service: Annotated[RoomService, Depends(_service)],
    format: str = Query("markdown", pattern="^(markdown|json)$"),
):
    room = await _require_member(service, room_id, current_user["email"])
    messages = await service.all_messages_for_export(room_id)

    if format == "json":
        return RoomExport(
            room=RoomDetailOut.from_model(room),
            messages=[RoomMessageOut.model_validate(m) for m in messages],
        )

    # Markdown
    agent_names = {a.id: a.name for a in room.agents}
    lines = [f"# {room.name}", ""]
    if room.description:
        lines.extend([room.description, ""])
    for m in messages:
        if m.sender_user_id:
            author = m.sender_user_id
        elif m.sender_agent_id:
            author = f"🤖 {agent_names.get(m.sender_agent_id, 'agent')}"
        else:
            author = m.role
        ts = m.created_at.isoformat()
        lines.append(f"**{author}** · {ts}")
        lines.append("")
        lines.append(m.content)
        lines.append("")
        lines.append("---")
        lines.append("")
    return PlainTextResponse("\n".join(lines), media_type="text/markdown")
