"""Pydantic schemas for scheduled actions."""

from __future__ import annotations

from datetime import datetime
from typing import Self

from pydantic import BaseModel, Field, model_validator


class ScheduledActionCreate(BaseModel):
    """Request to create a scheduled action.

    Provide exactly one of ``cron_expr`` (recurring) or ``run_at`` (one-off).
    """

    title: str | None = Field(None, max_length=200, description="Short label")
    prompt: str = Field(..., min_length=1, max_length=10000)
    cron_expr: str | None = Field(
        None,
        max_length=100,
        description="5-field crontab expression (e.g. '0 9 * * mon')",
    )
    run_at: datetime | None = Field(None, description="Specific datetime for a one-off action")
    model: str | None = Field(None, max_length=100)
    system_prompt: str | None = Field(None, max_length=20000)
    is_active: bool = True

    @model_validator(mode="after")
    def _require_exactly_one_trigger(self) -> Self:
        has_cron = bool((self.cron_expr or "").strip())
        has_run_at = self.run_at is not None
        if has_cron == has_run_at:
            raise ValueError("Provide exactly one of cron_expr or run_at.")
        return self


class ScheduledActionUpdate(BaseModel):
    """Partial update for a scheduled action."""

    title: str | None = Field(None, max_length=200)
    prompt: str | None = Field(None, min_length=1, max_length=10000)
    cron_expr: str | None = Field(None, max_length=100)
    run_at: datetime | None = None
    model: str | None = Field(None, max_length=100)
    system_prompt: str | None = Field(None, max_length=20000)
    is_active: bool | None = None


class ScheduledActionResponse(BaseModel):
    """Scheduled action as returned by the API."""

    id: str
    user_id: str
    title: str | None
    prompt: str
    cron_expr: str | None
    run_at: datetime | None
    model: str | None
    system_prompt: str | None
    is_active: bool
    next_run: datetime | None
    last_run_at: datetime | None
    last_run_status: str | None
    # Conversation recurring runs post into (NULL until the first run, or
    # for one-off ``run_at`` actions).
    conversation_id: str | None
    created_at: datetime
    updated_at: datetime

    model_config = {"from_attributes": True}
