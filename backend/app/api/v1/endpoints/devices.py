"""Device token registration for push notifications."""

from typing import Annotated, Any

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.security import get_current_user
from app.db.session import get_db
from app.schemas.device import DeviceRegisterRequest, DeviceResponse
from app.services.device_service import DeviceService

router = APIRouter()


def get_device_service(db: Annotated[AsyncSession, Depends(get_db)]) -> DeviceService:
    return DeviceService(db)


@router.post(
    "/register",
    response_model=DeviceResponse,
    status_code=status.HTTP_201_CREATED,
    summary="Register an FCM device token for the current user",
)
async def register_device(
    data: DeviceRegisterRequest,
    current_user: Annotated[dict[str, Any], Depends(get_current_user)],
    service: Annotated[DeviceService, Depends(get_device_service)],
) -> DeviceResponse:
    device = await service.register(
        user_id=current_user["email"],
        token=data.token,
        platform=data.platform,
    )
    return DeviceResponse.model_validate(device)


@router.delete(
    "/register",
    status_code=status.HTTP_204_NO_CONTENT,
    summary="Unregister an FCM device token",
)
async def unregister_device(
    data: DeviceRegisterRequest,
    current_user: Annotated[dict[str, Any], Depends(get_current_user)],
    service: Annotated[DeviceService, Depends(get_device_service)],
) -> None:
    deleted = await service.unregister(
        user_id=current_user["email"],
        token=data.token,
    )
    if not deleted:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Device token not found",
        )
