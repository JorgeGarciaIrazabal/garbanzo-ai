"""System prompt template library + user default prompt endpoints."""

from typing import Annotated, Any

from fastapi import APIRouter, Depends, HTTPException, Query, status
from fastapi.responses import StreamingResponse
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.rate_limit import rate_limit
from app.core.security import get_current_user
from app.db.session import get_db
from app.schemas.chat import ChatResponseChunk
from app.schemas.system_prompt import (
    SystemPromptGenerateRequest,
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


_SSE_HEADERS = {
    "Cache-Control": "no-cache",
    "Connection": "keep-alive",
    "X-Accel-Buffering": "no",
}


# ---- Templates --------------------------------------------------------------


@router.get(
    "/templates",
    response_model=list[SystemPromptTemplateOut],
    summary="List system prompt templates visible to the user (builtins + own)",
)
async def list_templates(
    current_user: Annotated[dict[str, Any], Depends(get_current_user)],
    service: Annotated[SystemPromptService, Depends(get_service)],
    locale: str | None = Query(
        default=None,
        description=(
            "BCP-47 language tag. When set and builtin templates exist for "
            "the resolved language, only those builtins surface (plus the "
            "user's own). Omit to surface builtins in every language."
        ),
    ),
) -> list[SystemPromptTemplateOut]:
    templates = await service.list_templates(user_id=current_user["email"], locale=locale)
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


# ---- AI-assisted generation -------------------------------------------------


async def _generate_sse_stream(
    service: SystemPromptService,
    request: SystemPromptGenerateRequest,
) -> Any:
    """Serialize the provider's ChatChunks into SSE frames."""
    try:
        async for chunk in service.generate_system_prompt(
            intent=request.intent,
            existing_prompt=request.existing_prompt,
            feedback=request.feedback,
            model=request.model,
        ):
            if chunk.metadata and chunk.metadata.get("error"):
                response = ChatResponseChunk(
                    type="error", error=chunk.content, metadata=chunk.metadata
                )
            elif chunk.is_finished:
                response = ChatResponseChunk(type="done", metadata=chunk.metadata)
            elif chunk.is_thinking:
                response = ChatResponseChunk(type="thinking", content=chunk.content)
            else:
                response = ChatResponseChunk(type="chunk", content=chunk.content)
            yield f"data: {response.model_dump_json()}\n\n"
    except Exception as e:
        error_response = ChatResponseChunk(type="error", error=str(e), metadata={"error": True})
        yield f"data: {error_response.model_dump_json()}\n\n"


@router.post(
    "/generate",
    summary="Generate or refine a system prompt via the LLM (SSE stream)",
    response_class=StreamingResponse,
    dependencies=[Depends(rate_limit("system_prompt_generate"))],
)
async def generate_system_prompt(
    data: SystemPromptGenerateRequest,
    current_user: Annotated[dict[str, Any], Depends(get_current_user)],
    service: Annotated[SystemPromptService, Depends(get_service)],
) -> StreamingResponse:
    """Stream an AI-drafted system prompt as SSE chunks.

    Send ``intent`` for a fresh draft, or ``existing_prompt`` + ``feedback``
    to refine an existing draft. The SSE chunk shape matches the chat
    endpoint (``chunk``, ``thinking``, ``done``, ``error``).
    """
    return StreamingResponse(
        _generate_sse_stream(service, data),
        media_type="text/event-stream",
        headers=_SSE_HEADERS,
    )
