"""Notification center and preferences endpoints."""

from typing import Annotated, Any

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.security import get_current_user
from app.db.session import get_db
from app.schemas.notification import (
    NotificationListResponse,
    NotificationPreferencesResponse,
    NotificationPreferencesUpdate,
    NotificationResponse,
    UnreadCountResponse,
)
from app.services.notification_service import NotificationService

router = APIRouter()


def get_service(db: Annotated[AsyncSession, Depends(get_db)]) -> NotificationService:
    return NotificationService(db)


@router.get(
    "",
    response_model=NotificationListResponse,
    summary="List the authenticated user's notifications",
)
async def list_notifications(
    current_user: Annotated[dict[str, Any], Depends(get_current_user)],
    service: Annotated[NotificationService, Depends(get_service)],
) -> NotificationListResponse:
    items = await service.list_for_user(current_user["email"])
    unread = await service.unread_count(current_user["email"])
    return NotificationListResponse(
        items=[NotificationResponse.model_validate(n) for n in items],
        unread_count=unread,
    )


@router.get(
    "/unread-count",
    response_model=UnreadCountResponse,
    summary="Unread notification count for the authenticated user",
)
async def unread_count(
    current_user: Annotated[dict[str, Any], Depends(get_current_user)],
    service: Annotated[NotificationService, Depends(get_service)],
) -> UnreadCountResponse:
    return UnreadCountResponse(unread_count=await service.unread_count(current_user["email"]))


@router.post(
    "/read-all",
    status_code=status.HTTP_204_NO_CONTENT,
    summary="Mark every notification as read",
)
async def mark_all_read(
    current_user: Annotated[dict[str, Any], Depends(get_current_user)],
    service: Annotated[NotificationService, Depends(get_service)],
) -> None:
    await service.mark_all_read(current_user["email"])


@router.patch(
    "/{notification_id}/read",
    status_code=status.HTTP_204_NO_CONTENT,
    summary="Mark a single notification as read",
)
async def mark_read(
    notification_id: str,
    current_user: Annotated[dict[str, Any], Depends(get_current_user)],
    service: Annotated[NotificationService, Depends(get_service)],
) -> None:
    ok = await service.mark_read(current_user["email"], notification_id)
    if not ok:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Notification not found",
        )


@router.delete(
    "/{notification_id}",
    status_code=status.HTTP_204_NO_CONTENT,
    summary="Delete a notification",
)
async def delete_notification(
    notification_id: str,
    current_user: Annotated[dict[str, Any], Depends(get_current_user)],
    service: Annotated[NotificationService, Depends(get_service)],
) -> None:
    ok = await service.delete(current_user["email"], notification_id)
    if not ok:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Notification not found",
        )


@router.get(
    "/preferences",
    response_model=NotificationPreferencesResponse,
    summary="Get notification preferences",
)
async def get_preferences(
    current_user: Annotated[dict[str, Any], Depends(get_current_user)],
    service: Annotated[NotificationService, Depends(get_service)],
) -> NotificationPreferencesResponse:
    prefs = await service.get_preferences(current_user["email"])
    return NotificationPreferencesResponse.model_validate(prefs)


@router.patch(
    "/preferences",
    response_model=NotificationPreferencesResponse,
    summary="Update notification preferences",
)
async def update_preferences(
    data: NotificationPreferencesUpdate,
    current_user: Annotated[dict[str, Any], Depends(get_current_user)],
    service: Annotated[NotificationService, Depends(get_service)],
) -> NotificationPreferencesResponse:
    prefs = await service.update_preferences(
        current_user["email"],
        chat_responses_enabled=data.chat_responses_enabled,
        reminders_enabled=data.reminders_enabled,
        system_alerts_enabled=data.system_alerts_enabled,
    )
    return NotificationPreferencesResponse.model_validate(prefs)
