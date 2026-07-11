"""Device token management for push notifications."""

import uuid

from sqlalchemy import delete, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.device_token import DeviceToken


class DeviceService:
    def __init__(self, db: AsyncSession) -> None:
        self.db = db

    async def register(self, user_id: str, token: str, platform: str) -> DeviceToken:
        """Register a device token for the user, or reassign it if it already exists."""
        result = await self.db.execute(select(DeviceToken).where(DeviceToken.token == token))
        existing = result.scalar_one_or_none()
        if existing is not None:
            existing.user_id = user_id
            existing.platform = platform
            await self.db.commit()
            await self.db.refresh(existing)
            return existing

        device = DeviceToken(
            id=str(uuid.uuid4()),
            user_id=user_id,
            token=token,
            platform=platform,
        )
        self.db.add(device)
        await self.db.commit()
        await self.db.refresh(device)
        return device

    async def unregister(self, user_id: str, token: str) -> bool:
        """Remove a device token. Returns True if a row was deleted."""
        result = await self.db.execute(
            delete(DeviceToken)
            .where(DeviceToken.user_id == user_id, DeviceToken.token == token)
            .returning(DeviceToken.id)
        )
        deleted = result.scalar_one_or_none()
        if deleted is not None:
            await self.db.commit()
            return True
        return False
