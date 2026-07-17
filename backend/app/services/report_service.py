"""Service for bug/feature report CRUD and admin triage."""

from __future__ import annotations

import logging
import uuid

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.report import Report

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
    ) -> Report:
        report = Report(
            id=str(uuid.uuid4()),
            user_id=user_id,
            type=type_,
            title=title,
            description=description,
            status="open",
        )
        self.db.add(report)
        await self.db.commit()
        await self.db.refresh(report)
        logger.info("Created %s report %s for user %s", type_, report.id, user_id)
        return report

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
