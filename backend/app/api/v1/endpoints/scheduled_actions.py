"""API endpoints for user-defined scheduled actions."""

from typing import Annotated, Any

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.security import get_current_user
from app.db.session import get_db
from app.scheduler import register_scheduled_action, unregister_scheduled_action
from app.schemas.scheduled_action import (
    ScheduledActionCreate,
    ScheduledActionResponse,
    ScheduledActionUpdate,
)
from app.services.scheduled_action_service import ScheduledActionService

router = APIRouter()


def get_service(db: Annotated[AsyncSession, Depends(get_db)]) -> ScheduledActionService:
    return ScheduledActionService(db)


@router.post(
    "",
    response_model=ScheduledActionResponse,
    status_code=status.HTTP_201_CREATED,
    summary="Create a scheduled action",
)
async def create_scheduled_action(
    data: ScheduledActionCreate,
    current_user: Annotated[dict[str, Any], Depends(get_current_user)],
    service: Annotated[ScheduledActionService, Depends(get_service)],
) -> ScheduledActionResponse:
    try:
        action = await service.create(
            user_id=current_user["email"],
            prompt=data.prompt,
            title=data.title,
            cron_expr=data.cron_expr,
            run_at=data.run_at,
            model=data.model,
            system_prompt=data.system_prompt,
            is_active=data.is_active,
        )
    except ValueError as exc:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(exc)) from exc

    register_scheduled_action(action)
    return ScheduledActionResponse.model_validate(action)


@router.get(
    "",
    response_model=list[ScheduledActionResponse],
    summary="List the user's scheduled actions",
)
async def list_scheduled_actions(
    current_user: Annotated[dict[str, Any], Depends(get_current_user)],
    service: Annotated[ScheduledActionService, Depends(get_service)],
) -> list[ScheduledActionResponse]:
    actions = await service.list_for_user(current_user["email"])
    return [ScheduledActionResponse.model_validate(a) for a in actions]


@router.get(
    "/{action_id}",
    response_model=ScheduledActionResponse,
    summary="Get a single scheduled action",
)
async def get_scheduled_action(
    action_id: str,
    current_user: Annotated[dict[str, Any], Depends(get_current_user)],
    service: Annotated[ScheduledActionService, Depends(get_service)],
) -> ScheduledActionResponse:
    action = await service.get(action_id, current_user["email"])
    if action is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND, detail="Scheduled action not found"
        )
    return ScheduledActionResponse.model_validate(action)


@router.patch(
    "/{action_id}",
    response_model=ScheduledActionResponse,
    summary="Update a scheduled action",
)
async def update_scheduled_action(
    action_id: str,
    data: ScheduledActionUpdate,
    current_user: Annotated[dict[str, Any], Depends(get_current_user)],
    service: Annotated[ScheduledActionService, Depends(get_service)],
) -> ScheduledActionResponse:
    raw = data.model_dump(exclude_unset=True)
    try:
        action = await service.update(
            action_id=action_id,
            user_id=current_user["email"],
            title=data.title,
            prompt=data.prompt,
            cron_expr=data.cron_expr,
            run_at=data.run_at,
            model=data.model,
            system_prompt=data.system_prompt,
            is_active=data.is_active,
            set_cron="cron_expr" in raw,
            set_run_at="run_at" in raw,
        )
    except ValueError as exc:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(exc)) from exc

    if action is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND, detail="Scheduled action not found"
        )

    # Replace the live job to reflect the new schedule / active flag.
    if action.is_active:
        register_scheduled_action(action)
    else:
        unregister_scheduled_action(action.id)

    return ScheduledActionResponse.model_validate(action)


@router.delete(
    "/{action_id}",
    status_code=status.HTTP_204_NO_CONTENT,
    summary="Delete a scheduled action",
)
async def delete_scheduled_action(
    action_id: str,
    current_user: Annotated[dict[str, Any], Depends(get_current_user)],
    service: Annotated[ScheduledActionService, Depends(get_service)],
) -> None:
    deleted = await service.delete(action_id, current_user["email"])
    if not deleted:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND, detail="Scheduled action not found"
        )
    unregister_scheduled_action(action_id)
