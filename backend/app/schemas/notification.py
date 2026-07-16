from datetime import datetime
from typing import Any, Literal

from pydantic import BaseModel, ConfigDict, Field

NotificationChannel = Literal["chat_responses", "reminders", "system_alerts", "friend_updates"]


class NotificationResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: str
    channel: NotificationChannel
    title: str
    body: str
    data: dict[str, Any] | None = None
    is_read: bool
    created_at: datetime


class NotificationListResponse(BaseModel):
    items: list[NotificationResponse]
    unread_count: int


class UnreadCountResponse(BaseModel):
    unread_count: int


class NotificationPreferencesResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    chat_responses_enabled: bool
    reminders_enabled: bool
    system_alerts_enabled: bool
    friend_updates_enabled: bool


class NotificationPreferencesUpdate(BaseModel):
    chat_responses_enabled: bool | None = Field(None)
    reminders_enabled: bool | None = Field(None)
    system_alerts_enabled: bool | None = Field(None)
    friend_updates_enabled: bool | None = Field(None)
