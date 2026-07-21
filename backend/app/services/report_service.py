"""Service for bug/feature report CRUD and admin triage."""

from __future__ import annotations

import contextlib
import logging
import uuid
from typing import Any

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.report import Report
from app.models.user import User
from app.services import fcm_service

logger = logging.getLogger(__name__)


class ReportService:
    def __init__(self, db: AsyncSession) -> None:
        self.db = db

    async def create(
        self,
        *,
        user_id: str,
        type_: str,
        title: str,
        description: str,
        metadata: dict[str, Any] | None = None,
        conversation_id: str | None = None,
        severity: str | None = None,
        source: str | None = None,
    ) -> Report:
        report = Report(
            id=str(uuid.uuid4()),
            user_id=user_id,
            type=type_,
            title=title,
            description=description,
            metadata_=metadata,
            conversation_id=conversation_id,
            severity=severity,
            source=source,
            status="open",
        )
        self.db.add(report)
        await self.db.commit()
        await self.db.refresh(report)
        logger.info("Created %s report %s for user %s", type_, report.id, user_id)
        return report

    async def notify_admins(self, report: Report) -> None:
        """Best-effort heads-up to every admin (in-app + push, ``system_alerts``
        channel) when a report lands. The submitter isn't notified about their
        own submission, and a delivery failure never breaks the caller."""
        result = await self.db.execute(
            select(User.email).where(User.is_admin.is_(True), User.email != report.user_id)
        )
        label = "Bug report" if report.type == "bug" else "Feature request"
        for email in result.scalars().all():
            with contextlib.suppress(Exception):
                await fcm_service.send_to_user(
                    self.db,
                    email,
                    title=f"{label}: {report.title}",
                    body=f"From {report.user_id} — triage it in Admin → Reports.",
                    channel="system_alerts",
                    data={"type": "report"},
                )

    async def list_for_user(self, user_id: str) -> list[Report]:
        result = await self.db.execute(
            select(Report).where(Report.user_id == user_id).order_by(Report.created_at.desc())
        )
        return list(result.scalars().all())

    async def list_all(self, status: str | None = None) -> list[Report]:
        """Every report across all users, newest first (admin triage)."""
        query = select(Report).order_by(Report.created_at.desc())
        if status is not None:
            query = query.where(Report.status == status)
        result = await self.db.execute(query)
        return list(result.scalars().all())

    async def update_status(self, report_id: str, status: str) -> Report | None:
        result = await self.db.execute(select(Report).where(Report.id == report_id))
        report = result.scalar_one_or_none()
        if report is None:
            return None
        report.status = status
        await self.db.commit()
        await self.db.refresh(report)
        return report
