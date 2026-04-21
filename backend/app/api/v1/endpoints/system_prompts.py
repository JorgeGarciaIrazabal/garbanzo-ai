"""System prompt template library + user default prompt endpoints."""

from typing import Annotated, Any

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.security import get_current_user
from app.db.session import get_db
from app.schemas.system_prompt import (
    SystemPromptTemplateCreate,
    SystemPromptTemplateOut,
    SystemPromptTemplateUpdate,
    UserDefaultPromptOut,
    UserDefaultPromptUpdate,
)
from app.services.system_prompt_service import SystemPromptService

router = APIRouter()


def get_service(db: Annotated[AsyncSession, Depends(get_db)]) -> SystemPromptService:
    return SystemPromptService(db)


# ---- Templates --------------------------------------------------------------


@router.get(
    "/templates",
    response_model=list[SystemPromptTemplateOut],
    summary="List system prompt templates visible to the user (builtins + own)",
)
async def list_templates(
    current_user: Annotated[dict[str, Any], Depends(get_current_user)],
    service: Annotated[SystemPromptService, Depends(get_service)],
) -> list[SystemPromptTemplateOut]:
    templates = await service.list_templates(user_id=current_user["email"])
    return [SystemPromptTemplateOut.model_validate(t) for t in templates]


@router.post(
    "/templates",
    response_model=SystemPromptTemplateOut,
    status_code=status.HTTP_201_CREATED,
    summary="Save a new custom system prompt template",
)
async def create_template(
    data: SystemPromptTemplateCreate,
    current_user: Annotated[dict[str, Any], Depends(get_current_user)],
    service: Annotated[SystemPromptService, Depends(get_service)],
) -> SystemPromptTemplateOut:
    template = await service.create_template(
        user_id=current_user["email"],
        name=data.name,
        description=data.description,
        content=data.content,
    )
    return SystemPromptTemplateOut.model_validate(template)


@router.patch(
    "/templates/{template_id}",
    response_model=SystemPromptTemplateOut,
    summary="Update a user-owned system prompt template",
)
async def update_template(
    template_id: str,
    data: SystemPromptTemplateUpdate,
    current_user: Annotated[dict[str, Any], Depends(get_current_user)],
    service: Annotated[SystemPromptService, Depends(get_service)],
) -> SystemPromptTemplateOut:
    template = await service.update_template(
        template_id=template_id,
        user_id=current_user["email"],
        name=data.name,
        description=data.description,
        content=data.content,
    )
    if not template:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Template not found or read-only",
        )
    return SystemPromptTemplateOut.model_validate(template)


@router.delete(
    "/templates/{template_id}",
    status_code=status.HTTP_204_NO_CONTENT,
    summary="Delete a user-owned system prompt template",
)
async def delete_template(
    template_id: str,
    current_user: Annotated[dict[str, Any], Depends(get_current_user)],
    service: Annotated[SystemPromptService, Depends(get_service)],
) -> None:
    deleted = await service.delete_template(
        template_id=template_id,
        user_id=current_user["email"],
    )
    if not deleted:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Template not found or read-only",
        )


# ---- User default prompt ----------------------------------------------------


@router.get(
    "/user-default",
    response_model=UserDefaultPromptOut,
    summary="Get the user's global default system prompt",
)
async def get_user_default(
    current_user: Annotated[dict[str, Any], Depends(get_current_user)],
    service: Annotated[SystemPromptService, Depends(get_service)],
) -> UserDefaultPromptOut:
    prompt = await service.get_user_default_prompt(user_id=current_user["email"])
    return UserDefaultPromptOut(default_system_prompt=prompt)


@router.put(
    "/user-default",
    response_model=UserDefaultPromptOut,
    summary="Set or clear the user's global default system prompt",
)
async def set_user_default(
    data: UserDefaultPromptUpdate,
    current_user: Annotated[dict[str, Any], Depends(get_current_user)],
    service: Annotated[SystemPromptService, Depends(get_service)],
) -> UserDefaultPromptOut:
    value = (data.default_system_prompt or "").strip() or None
    prompt = await service.set_user_default_prompt(
        user_id=current_user["email"],
        prompt=value,
    )
    return UserDefaultPromptOut(default_system_prompt=prompt)
