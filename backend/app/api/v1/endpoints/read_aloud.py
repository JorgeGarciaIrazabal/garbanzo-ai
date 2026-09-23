"""Authenticated Pocket read-aloud sessions, audio, progress, and previews."""

from typing import Annotated, Any

from fastapi import APIRouter, Depends, HTTPException, Query
from fastapi.responses import Response, StreamingResponse

from app.core.rate_limit import rate_limit
from app.core.security import get_current_user
from app.schemas.read_aloud import CreateReadAloudSession, UpdateReadAloudSession
from app.services.read_aloud_sessions import (
    VOICE_CATALOG,
    ReadAloudError,
    ReadAloudManager,
    get_read_aloud_manager,
)

router = APIRouter()
User = Annotated[dict[str, Any], Depends(get_current_user)]
Manager = Annotated[ReadAloudManager, Depends(get_read_aloud_manager)]


def _raise_api_error(exc: ReadAloudError) -> None:
    raise HTTPException(
        status_code=exc.status, detail={"code": exc.code, "message": str(exc)}
    ) from exc


@router.post("/sessions", dependencies=[Depends(rate_limit("tts"))])
async def create_session(
    data: CreateReadAloudSession, user: User, manager: Manager
) -> dict[str, Any]:
    try:
        session = await manager.create(user["email"], **data.model_dump())
        return session.status()
    except ReadAloudError as exc:
        _raise_api_error(exc)


@router.get("/sessions/{session_id}")
async def get_session(session_id: str, user: User, manager: Manager) -> dict[str, Any]:
    try:
        return (await manager.get(session_id, user["email"])).status()
    except ReadAloudError as exc:
        _raise_api_error(exc)


@router.get("/sessions/{session_id}/events")
async def session_events(
    session_id: str,
    user: User,
    manager: Manager,
    after: Annotated[int, Query(ge=0)] = 0,
) -> StreamingResponse:
    try:
        events = await manager.events(session_id, user["email"], after)
        return StreamingResponse(
            events,
            media_type="text/event-stream",
            headers={"Cache-Control": "no-cache", "X-Accel-Buffering": "no"},
        )
    except ReadAloudError as exc:
        _raise_api_error(exc)


@router.get("/sessions/{session_id}/audio")
async def session_audio(
    session_id: str,
    user: User,
    manager: Manager,
    start_segment: Annotated[int, Query(ge=0)] = 0,
) -> StreamingResponse:
    try:
        audio = await manager.audio(session_id, user["email"], start_segment)
        return StreamingResponse(
            audio,
            media_type="audio/mpeg",
            headers={"Cache-Control": "no-store", "X-Accel-Buffering": "no"},
        )
    except ReadAloudError as exc:
        _raise_api_error(exc)


@router.patch("/sessions/{session_id}")
async def update_session(
    session_id: str, data: UpdateReadAloudSession, user: User, manager: Manager
) -> dict[str, Any]:
    try:
        return await manager.update(session_id, user["email"], **data.model_dump())
    except ReadAloudError as exc:
        _raise_api_error(exc)


@router.delete("/sessions/{session_id}")
async def cancel_session(session_id: str, user: User, manager: Manager) -> dict[str, Any]:
    try:
        return await manager.cancel(session_id, user["email"])
    except ReadAloudError as exc:
        _raise_api_error(exc)


@router.get("/voices")
async def list_voices(user: User) -> dict[str, Any]:
    return {"voices": VOICE_CATALOG}


@router.get("/voices/{voice}/preview")
async def voice_preview(voice: str, user: User, manager: Manager) -> Response:
    try:
        return Response(content=await manager.preview(voice), media_type="audio/mpeg")
    except ReadAloudError as exc:
        _raise_api_error(exc)
