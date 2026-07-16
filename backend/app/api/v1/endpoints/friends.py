"""API endpoints for the friends graph (Idea 5: "Friends")."""

import contextlib
from typing import Annotated, Any

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.security import get_current_user
from app.db.session import get_db
from app.schemas.friendship import (
    FriendOut,
    FriendRequestCreate,
    FriendshipOut,
    FriendsListOut,
)
from app.services import fcm_service
from app.services.friendship_service import FriendshipService

router = APIRouter()


async def _notify(db: AsyncSession, recipient: str, title: str, body: str) -> None:
    """Best-effort friend-update notification (in-app + push). Never lets a
    delivery failure break the request that triggered it."""
    with contextlib.suppress(Exception):
        await fcm_service.send_to_user(
            db,
            recipient,
            title=title,
            body=body,
            channel="friend_updates",
            data={"type": "friend_update"},
        )


def get_service(db: Annotated[AsyncSession, Depends(get_db)]) -> FriendshipService:
    return FriendshipService(db)


@router.post(
    "/requests",
    response_model=FriendshipOut,
    status_code=status.HTTP_201_CREATED,
    summary="Send a friend request by email",
)
async def send_request(
    data: FriendRequestCreate,
    current_user: Annotated[dict[str, Any], Depends(get_current_user)],
    service: Annotated[FriendshipService, Depends(get_service)],
    db: Annotated[AsyncSession, Depends(get_db)],
) -> FriendshipOut:
    me = current_user["email"]
    try:
        friendship = await service.send_request(me, data.email)
    except ValueError as exc:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(exc)) from exc

    if friendship.status == "pending":
        await _notify(
            db,
            friendship.addressee_email,
            "Friend request",
            f"{me} wants to be your friend",
        )
    else:
        # Reverse-pending auto-accept: tell the original requester.
        await _notify(
            db,
            friendship.requester_email,
            "Friend request accepted",
            f"{me} accepted your friend request",
        )
    return FriendshipOut.model_validate(friendship)


@router.post(
    "/requests/{request_id}/accept",
    response_model=FriendshipOut,
    summary="Accept an incoming friend request",
)
async def accept_request(
    request_id: str,
    current_user: Annotated[dict[str, Any], Depends(get_current_user)],
    service: Annotated[FriendshipService, Depends(get_service)],
    db: Annotated[AsyncSession, Depends(get_db)],
) -> FriendshipOut:
    friendship = await service.accept(request_id, current_user["email"])
    if friendship is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Friend request not found",
        )
    await _notify(
        db,
        friendship.requester_email,
        "Friend request accepted",
        f"{current_user['email']} accepted your friend request",
    )
    return FriendshipOut.model_validate(friendship)


@router.post(
    "/requests/{request_id}/decline",
    status_code=status.HTTP_204_NO_CONTENT,
    summary="Decline an incoming friend request",
)
async def decline_request(
    request_id: str,
    current_user: Annotated[dict[str, Any], Depends(get_current_user)],
    service: Annotated[FriendshipService, Depends(get_service)],
) -> None:
    ok = await service.decline(request_id, current_user["email"])
    if not ok:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Friend request not found",
        )


@router.get(
    "",
    response_model=FriendsListOut,
    summary="List friends and pending requests",
)
async def list_friends(
    current_user: Annotated[dict[str, Any], Depends(get_current_user)],
    service: Annotated[FriendshipService, Depends(get_service)],
) -> FriendsListOut:
    friends, incoming, outgoing, blocked = await service.list_relationships(current_user["email"])

    def _out(entries: list) -> list[FriendOut]:
        return [
            FriendOut(
                email=f.email,
                full_name=f.full_name,
                friendship_id=f.friendship_id,
                since=f.since,
            )
            for f in entries
        ]

    return FriendsListOut(
        friends=_out(friends),
        incoming_requests=[FriendshipOut.model_validate(r) for r in incoming],
        outgoing_requests=[FriendshipOut.model_validate(r) for r in outgoing],
        blocked=_out(blocked),
    )


@router.get(
    "/search",
    response_model=list[FriendOut],
    summary="Search among accepted friends only",
)
async def search_friends(
    q: str,
    current_user: Annotated[dict[str, Any], Depends(get_current_user)],
    service: Annotated[FriendshipService, Depends(get_service)],
) -> list[FriendOut]:
    results = await service.search(current_user["email"], q)
    return [
        FriendOut(
            email=f.email,
            full_name=f.full_name,
            friendship_id=f.friendship_id,
            since=f.since,
        )
        for f in results
    ]


@router.post(
    "/{email}/block",
    status_code=status.HTTP_204_NO_CONTENT,
    summary="Block a user (replaces any friendship or pending request)",
)
async def block_user(
    email: str,
    current_user: Annotated[dict[str, Any], Depends(get_current_user)],
    service: Annotated[FriendshipService, Depends(get_service)],
) -> None:
    # 204 on purpose: returning the row would disclose a pre-existing block
    # by the other party (its requester orientation names the blocker).
    try:
        await service.block(current_user["email"], email)
    except ValueError as exc:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(exc)) from exc


@router.delete(
    "/{email}/block",
    status_code=status.HTTP_204_NO_CONTENT,
    summary="Unblock a user you blocked",
)
async def unblock_user(
    email: str,
    current_user: Annotated[dict[str, Any], Depends(get_current_user)],
    service: Annotated[FriendshipService, Depends(get_service)],
) -> None:
    ok = await service.unblock(current_user["email"], email)
    if not ok:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Block not found",
        )


@router.delete(
    "/{email}",
    status_code=status.HTTP_204_NO_CONTENT,
    summary="Remove a friend (or cancel your own outgoing request)",
)
async def remove_friend(
    email: str,
    current_user: Annotated[dict[str, Any], Depends(get_current_user)],
    service: Annotated[FriendshipService, Depends(get_service)],
) -> None:
    ok = await service.remove(current_user["email"], email)
    if not ok:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Friendship not found",
        )
