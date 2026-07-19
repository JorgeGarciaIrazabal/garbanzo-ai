"""API endpoints for saved styles (Idea 2: "Styles")."""

from typing import Annotated, Any

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.security import get_current_user
from app.db.session import get_db
from app.schemas.style import StyleCreate, StyleOut, StyleUpdate
from app.services.style_service import BuiltinReadOnlyError, StyleService

router = APIRouter()


def get_service(db: Annotated[AsyncSession, Depends(get_db)]) -> StyleService:
    return StyleService(db)


@router.post(
    "",
    response_model=StyleOut,
    status_code=status.HTTP_201_CREATED,
    summary="Create a saved style",
)
async def create_style(
    data: StyleCreate,
    current_user: Annotated[dict[str, Any], Depends(get_current_user)],
    service: Annotated[StyleService, Depends(get_service)],
) -> StyleOut:
    try:
        style = await service.create(
            user_id=current_user["email"],
            name=data.name,
            model_id=data.model_id,
            thinking_level=data.thinking_level,
            system_prompt_template_id=data.system_prompt_template_id,
            is_default=data.is_default,
        )
    except ValueError as exc:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(exc)) from exc
    return StyleOut.model_validate(style)


@router.get(
    "",
    response_model=list[StyleOut],
    summary="List the user's saved styles plus built-ins",
)
async def list_styles(
    current_user: Annotated[dict[str, Any], Depends(get_current_user)],
    service: Annotated[StyleService, Depends(get_service)],
) -> list[StyleOut]:
    styles = await service.list_for_user(current_user["email"])
    return [StyleOut.model_validate(s) for s in styles]


@router.get(
    "/{style_id}",
    response_model=StyleOut,
    summary="Get a single saved or built-in style",
)
async def get_style(
    style_id: str,
    current_user: Annotated[dict[str, Any], Depends(get_current_user)],
    service: Annotated[StyleService, Depends(get_service)],
) -> StyleOut:
    style = await service.get(style_id, current_user["email"])
    if style is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Style not found")
    return StyleOut.model_validate(style)


@router.patch(
    "/{style_id}",
    response_model=StyleOut,
    summary="Update a saved style (built-ins are read-only)",
)
async def update_style(
    style_id: str,
    data: StyleUpdate,
    current_user: Annotated[dict[str, Any], Depends(get_current_user)],
    service: Annotated[StyleService, Depends(get_service)],
) -> StyleOut:
    # thinking_level / system_prompt_template_id both need three-way
    # semantics — null is itself a meaningful target value (reset to
    # provider default / clear the template), so the column is only
    # touched when the key was actually present in the request payload.
    # Mirrors ConversationUpdate handling in chat.py.
    payload_set = data.model_fields_set
    set_thinking_level = "thinking_level" in payload_set
    set_template_id = "system_prompt_template_id" in payload_set

    try:
        style = await service.update(
            style_id=style_id,
            user_id=current_user["email"],
            name=data.name,
            model_id=data.model_id,
            thinking_level=data.thinking_level,
            set_thinking_level=set_thinking_level,
            system_prompt_template_id=data.system_prompt_template_id,
            set_template_id=set_template_id,
            is_default=data.is_default,
        )
    except BuiltinReadOnlyError as exc:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Built-in styles are read-only",
        ) from exc
    except ValueError as exc:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(exc)) from exc

    if style is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Style not found")
    return StyleOut.model_validate(style)


@router.delete(
    "/{style_id}",
    status_code=status.HTTP_204_NO_CONTENT,
    summary="Delete a saved style (built-ins are read-only)",
)
async def delete_style(
    style_id: str,
    current_user: Annotated[dict[str, Any], Depends(get_current_user)],
    service: Annotated[StyleService, Depends(get_service)],
) -> None:
    try:
        deleted = await service.delete(style_id, current_user["email"])
    except BuiltinReadOnlyError as exc:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Built-in styles are read-only",
        ) from exc
    if not deleted:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Style not found")
