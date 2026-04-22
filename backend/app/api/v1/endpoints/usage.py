from typing import Annotated, Any

from fastapi import APIRouter, Depends, Query
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.security import get_current_user
from app.db.session import get_db
from app.schemas.usage import UsageSummary
from app.services.usage_service import UsageService

router = APIRouter()


@router.get("/summary", response_model=UsageSummary)
async def get_usage_summary(
    current_user: Annotated[dict[str, Any], Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
    days: int = Query(30, ge=1, le=365),
) -> UsageSummary:
    """Aggregate token usage for the authenticated user over the last N days."""
    service = UsageService(db)
    return await service.summary(current_user["email"], days=days)
