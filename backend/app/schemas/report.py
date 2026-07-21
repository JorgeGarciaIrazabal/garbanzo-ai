"""Pydantic schemas for bug/feature reports."""

from __future__ import annotations

from datetime import datetime
from typing import Any, Literal

from pydantic import BaseModel, Field

ReportType = Literal["bug", "feature"]
ReportStatus = Literal["open", "in_progress", "closed"]
ReportSeverity = Literal["info", "warning", "error"]
ReportSource = Literal["frontend", "backend"]


class ReportCreate(BaseModel):
    """User submission of a bug report or feature request."""

    type: ReportType
    title: str = Field(..., min_length=1, max_length=200)
    description: str = Field(..., min_length=1, max_length=10000)
    metadata: dict[str, Any] | None = None
    conversation_id: str | None = Field(default=None, max_length=36)
    severity: ReportSeverity | None = None
    source: ReportSource | None = None


class ReportStatusUpdate(BaseModel):
    """Admin triage: move a report through its status flow."""

    status: ReportStatus


class ReportOut(BaseModel):
    """Report as returned by the API."""

    id: str
    user_id: str
    type: ReportType
    title: str
    description: str
    metadata: dict[str, Any] | None = Field(default=None, validation_alias="metadata_")
    conversation_id: str | None
    severity: ReportSeverity | None
    source: ReportSource | None
    status: ReportStatus
    created_at: datetime
    updated_at: datetime

    model_config = {"from_attributes": True}
