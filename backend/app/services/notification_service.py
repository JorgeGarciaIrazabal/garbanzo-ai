"""Persist and query in-app notifications and user preferences."""

import uuid
from typing import Any

from sqlalchemy import delete, func, select, update
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.notification import Notification, NotificationPreferences


class NotificationService:
    def __init__(self, db: AsyncSession) -> None:
        self.db = db

    # ---- notifications ----

    async def create(
        self,
        *,
        user_id: str,
        title: str,
        body: str,
        channel: str = "chat_responses",
        data: dict[str, Any] | None = None,
    ) -> Notification:
        notif = Notification(
            id=str(uuid.uuid4()),
            user_id=user_id,
            channel=channel,
            title=title,
            body=body,
            data=data,
        )
        self.db.add(notif)
        await self.db.commit()
        await self.db.refresh(notif)
        return notif

    async def list_for_user(self, user_id: str, *, limit: int = 50) -> list[Notification]:
        result = await self.db.execute(
            select(Notification)
            .where(Notification.user_id == user_id)
            .order_by(Notification.created_at.desc())
            .limit(limit)
        )
        return list(result.scalars().all())

    async def unread_count(self, user_id: str) -> int:
        result = await self.db.execute(
            select(func.count(Notification.id)).where(
                Notification.user_id == user_id,
                Notification.is_read.is_(False),
            )
        )
        return int(result.scalar_one() or 0)

    async def mark_read(self, user_id: str, notification_id: str) -> bool:
        result = await self.db.execute(
            update(Notification)
            .where(
                Notification.id == notification_id,
                Notification.user_id == user_id,
            )
            .values(is_read=True)
            .returning(Notification.id)
        )
        hit = result.scalar_one_or_none()
        if hit is not None:
            await self.db.commit()
            return True
        return False

    async def mark_all_read(self, user_id: str) -> int:
        result = await self.db.execute(
            update(Notification)
            .where(
                Notification.user_id == user_id,
                Notification.is_read.is_(False),
            )
            .values(is_read=True)
            .returning(Notification.id)
        )
        ids = list(result.scalars().all())
        if ids:
            await self.db.commit()
        return len(ids)

    async def delete(self, user_id: str, notification_id: str) -> bool:
        result = await self.db.execute(
            delete(Notification)
            .where(
                Notification.id == notification_id,
                Notification.user_id == user_id,
            )
            .returning(Notification.id)
        )
        hit = result.scalar_one_or_none()
        if hit is not None:
            await self.db.commit()
            return True
        return False

    # ---- preferences ----

    async def get_preferences(self, user_id: str) -> NotificationPreferences:
        """Return prefs for ``user_id``, creating a default row if missing."""
        result = await self.db.execute(
            select(NotificationPreferences).where(NotificationPreferences.user_id == user_id)
        )
        prefs = result.scalar_one_or_none()
        if prefs is not None:
            return prefs

        prefs = NotificationPreferences(user_id=user_id)
        self.db.add(prefs)
        await self.db.commit()
        await self.db.refresh(prefs)
        return prefs

    async def update_preferences(
        self,
        user_id: str,
        *,
        chat_responses_enabled: bool | None = None,
        reminders_enabled: bool | None = None,
        system_alerts_enabled: bool | None = None,
    ) -> NotificationPreferences:
        prefs = await self.get_preferences(user_id)
        if chat_responses_enabled is not None:
            prefs.chat_responses_enabled = chat_responses_enabled
        if reminders_enabled is not None:
            prefs.reminders_enabled = reminders_enabled
        if system_alerts_enabled is not None:
            prefs.system_alerts_enabled = system_alerts_enabled
        await self.db.commit()
        await self.db.refresh(prefs)
        return prefs

    async def is_channel_enabled(self, user_id: str, channel: str) -> bool:
        """Fast path: return whether ``channel`` is enabled for the user."""
        prefs = await self.get_preferences(user_id)
        if channel == "chat_responses":
            return prefs.chat_responses_enabled
        if channel == "reminders":
            return prefs.reminders_enabled
        if channel == "system_alerts":
            return prefs.system_alerts_enabled
        return True
