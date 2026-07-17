"""Pydantic schemas for bug/feature reports."""

from __future__ import annotations

from datetime import datetime
from typing import Literal

from pydantic import BaseModel, Field

ReportType = Literal["bug", "feature"]
ReportStatus = Literal["open", "in_progress", "closed"]


class ReportCreate(BaseModel):
    """User submission of a bug report or feature request."""

    type: ReportType
    title: str = Field(..., min_length=1, max_length=200)
    description: str = Field(..., min_length=1, max_length=10000)


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
    status: ReportStatus
    created_at: datetime
    updated_at: datetime

    model_config = {"from_attributes": True}
