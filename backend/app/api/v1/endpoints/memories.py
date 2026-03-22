"""Memory API endpoints for CRUD operations."""

from typing import Annotated, Any

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.security import get_current_user
from app.db.session import get_db
from app.schemas.memory import MemoryCreate, MemoryResponse, MemoryUpdate
from app.services.memory_service import MemoryService

router = APIRouter()


def get_memory_service(db: Annotated[AsyncSession, Depends(get_db)]) -> MemoryService:
    """Get memory service instance."""
    return MemoryService(db)


@router.post(
    "",
    response_model=MemoryResponse,
    status_code=status.HTTP_201_CREATED,
    summary="Create a new memory",
)
async def create_memory(
    data: MemoryCreate,
    current_user: Annotated[dict[str, Any], Depends(get_current_user)],
    service: Annotated[MemoryService, Depends(get_memory_service)],
) -> MemoryResponse:
    """Create a new memory for the authenticated user."""
    memory = await service.create_memory(
        user_id=current_user["email"],
        content=data.content,
        source_conversation_id=data.source_conversation_id,
    )
    return MemoryResponse.model_validate(memory)


@router.get(
    "",
    response_model=list[MemoryResponse],
    summary="List user's active memories",
)
async def list_memories(
    current_user: Annotated[dict[str, Any], Depends(get_current_user)],
    service: Annotated[MemoryService, Depends(get_memory_service)],
) -> list[MemoryResponse]:
    """Get all active memories for the authenticated user."""
    memories = await service.get_active_memories(user_id=current_user["email"])
    return [MemoryResponse.model_validate(m) for m in memories]


@router.get(
    "/{memory_id}",
    response_model=MemoryResponse,
    summary="Get a specific memory",
)
async def get_memory(
    memory_id: str,
    current_user: Annotated[dict[str, Any], Depends(get_current_user)],
    service: Annotated[MemoryService, Depends(get_memory_service)],
) -> MemoryResponse:
    """Get a specific memory by ID."""
    memory = await service.get_memory(memory_id=memory_id, user_id=current_user["email"])

    if not memory:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Memory not found",
        )

    return MemoryResponse.model_validate(memory)


@router.patch(
    "/{memory_id}",
    response_model=MemoryResponse,
    summary="Update a memory",
)
async def update_memory(
    memory_id: str,
    data: MemoryUpdate,
    current_user: Annotated[dict[str, Any], Depends(get_current_user)],
    service: Annotated[MemoryService, Depends(get_memory_service)],
) -> MemoryResponse:
    """Update a memory's content or active status."""
    memory = await service.update_memory(
        memory_id=memory_id,
        user_id=current_user["email"],
        content=data.content,
        is_active=data.is_active,
    )

    if not memory:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Memory not found",
        )

    return MemoryResponse.model_validate(memory)


@router.delete(
    "/{memory_id}",
    status_code=status.HTTP_204_NO_CONTENT,
    summary="Deactivate a memory",
)
async def deactivate_memory(
    memory_id: str,
    current_user: Annotated[dict[str, Any], Depends(get_current_user)],
    service: Annotated[MemoryService, Depends(get_memory_service)],
) -> None:
    """Soft-deactivate a memory (set is_active=False)."""
    deactivated = await service.deactivate_memory(
        memory_id=memory_id,
        user_id=current_user["email"],
    )

    if not deactivated:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Memory not found",
        )
