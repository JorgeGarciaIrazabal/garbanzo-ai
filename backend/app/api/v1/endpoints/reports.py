"""User-facing endpoints for bug/feature reports.

Admin triage lives in ``admin.py`` (``GET/PATCH /admin/reports``).
"""

from typing import Annotated, Any

from fastapi import APIRouter, Depends, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.security import get_current_user
from app.db.session import get_db
from app.schemas.report import ReportCreate, ReportOut
from app.services.report_service import ReportService

router = APIRouter()


def get_service(db: Annotated[AsyncSession, Depends(get_db)]) -> ReportService:
    return ReportService(db)


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
) -> ReportOut:
    report = await service.create(
        user_id=current_user["email"],
        type_=data.type,
        title=data.title,
        description=data.description,
        metadata=data.metadata,
        conversation_id=data.conversation_id,
        severity=data.severity,
        source=data.source,
    )
    await service.notify_admins(report)
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
