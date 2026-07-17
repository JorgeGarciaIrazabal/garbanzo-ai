"""User-facing endpoints for bug/feature reports.

Admin triage lives in ``admin.py`` (``GET/PATCH /admin/reports``).
"""

import contextlib
from typing import Annotated, Any

from fastapi import APIRouter, Depends, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.security import get_current_user
from app.db.session import get_db
from app.models.user import User
from app.schemas.report import ReportCreate, ReportOut
from app.services import fcm_service
from app.services.report_service import ReportService

router = APIRouter()


def get_service(db: Annotated[AsyncSession, Depends(get_db)]) -> ReportService:
    return ReportService(db)


async def _notify_admins(db: AsyncSession, report: "Any") -> None:
    """Best-effort heads-up to every admin (in-app + push, ``system_alerts``
    channel) when a report lands. The submitter isn't notified about their own
    submission, and a delivery failure never breaks the request."""
    result = await db.execute(
        select(User.email).where(User.is_admin.is_(True), User.email != report.user_id)
    )
    label = "Bug report" if report.type == "bug" else "Feature request"
    for email in result.scalars().all():
        with contextlib.suppress(Exception):
            await fcm_service.send_to_user(
                db,
                email,
                title=f"{label}: {report.title}",
                body=f"From {report.user_id} — triage it in Admin → Reports.",
                channel="system_alerts",
                data={"type": "report"},
            )


@router.post(
    "",
    response_model=ReportOut,
    status_code=status.HTTP_201_CREATED,
    summary="Submit a bug report or feature request",
)
async def create_report(
    data: ReportCreate,
    current_user: Annotated[dict[str, Any], Depends(get_current_user)],
    service: Annotated[ReportService, Depends(get_service)],
    db: Annotated[AsyncSession, Depends(get_db)],
) -> ReportOut:
    report = await service.create(
        user_id=current_user["email"],
        type_=data.type,
        title=data.title,
        description=data.description,
    )
    await _notify_admins(db, report)
    return ReportOut.model_validate(report)


@router.get(
    "/mine",
    response_model=list[ReportOut],
    summary="List the user's own reports",
)
async def list_my_reports(
    current_user: Annotated[dict[str, Any], Depends(get_current_user)],
    service: Annotated[ReportService, Depends(get_service)],
) -> list[ReportOut]:
    reports = await service.list_for_user(current_user["email"])
    return [ReportOut.model_validate(r) for r in reports]
