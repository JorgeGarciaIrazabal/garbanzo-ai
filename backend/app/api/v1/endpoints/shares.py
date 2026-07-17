"""Share styles / prompt templates with friends (Idea 9)."""

import contextlib
from typing import Annotated, Any

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.security import get_current_user
from app.db.session import get_db
from app.schemas.shared_item import ShareAcceptOut, ShareCreate, SharedItemOut
from app.services import fcm_service
from app.services.share_service import ShareService

router = APIRouter()


def get_service(db: Annotated[AsyncSession, Depends(get_db)]) -> ShareService:
    return ShareService(db)


@router.post(
    "",
    response_model=SharedItemOut,
    status_code=status.HTTP_201_CREATED,
    summary="Share a style or prompt template with a friend",
)
async def share_item(
    data: ShareCreate,
    current_user: Annotated[dict[str, Any], Depends(get_current_user)],
    service: Annotated[ShareService, Depends(get_service)],
    db: Annotated[AsyncSession, Depends(get_db)],
) -> SharedItemOut:
    me = current_user["email"]
    try:
        item = await service.share(me, data.recipient_email, data.kind, data.item_id)
    except ValueError as exc:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(exc)) from exc

    noun = "style" if item.kind == "style" else "prompt template"
    with contextlib.suppress(Exception):
        await fcm_service.send_to_user(
            db,
            item.recipient_email,
            title="Something shared with you",
            body=f'{me} shared the {noun} "{item.payload["name"]}" with you',
            channel="friend_updates",
            data={"type": "share"},
        )
    return SharedItemOut.model_validate(item)


@router.get(
    "/incoming",
    response_model=list[SharedItemOut],
    summary="List shares waiting for you",
)
async def incoming_shares(
    current_user: Annotated[dict[str, Any], Depends(get_current_user)],
    service: Annotated[ShareService, Depends(get_service)],
) -> list[SharedItemOut]:
    items = await service.list_incoming(current_user["email"])
    return [SharedItemOut.model_validate(i) for i in items]


@router.post(
    "/{share_id}/accept",
    response_model=ShareAcceptOut,
    summary="Accept a share (creates your own copy)",
)
async def accept_share(
    share_id: str,
    current_user: Annotated[dict[str, Any], Depends(get_current_user)],
    service: Annotated[ShareService, Depends(get_service)],
) -> ShareAcceptOut:
    result = await service.accept(share_id, current_user["email"])
    if result is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Share not found")
    kind, created_id = result
    return ShareAcceptOut(kind=kind, created_id=created_id)


@router.post(
    "/{share_id}/decline",
    status_code=status.HTTP_204_NO_CONTENT,
    summary="Decline a share",
)
async def decline_share(
    share_id: str,
    current_user: Annotated[dict[str, Any], Depends(get_current_user)],
    service: Annotated[ShareService, Depends(get_service)],
) -> None:
    ok = await service.decline(share_id, current_user["email"])
    if not ok:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Share not found")
