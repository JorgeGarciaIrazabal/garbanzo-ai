"""Main-chat generated UI interactions. Authentication stays on the server."""

from typing import Annotated, Any

from fastapi import APIRouter, Depends, Query
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.security import get_current_user
from app.db.session import get_db
from app.schemas.visual_ui import UISubmission
from app.services.visual_ui import UIActionService

router = APIRouter()


@router.get("/conversations/{conversation_id}/ui-actions")
async def ui_action_state(
    conversation_id: str,
    tool_call_id: Annotated[str, Query(min_length=1, max_length=100)],
    current_user: Annotated[dict[str, Any], Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
) -> dict:
    return await UIActionService(db).state(conversation_id, current_user["email"], tool_call_id)


@router.post("/conversations/{conversation_id}/ui-actions")
async def submit_ui_action(
    conversation_id: str,
    data: UISubmission,
    current_user: Annotated[dict[str, Any], Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
) -> dict:
    return await UIActionService(db).submit(conversation_id, current_user["email"], data)
