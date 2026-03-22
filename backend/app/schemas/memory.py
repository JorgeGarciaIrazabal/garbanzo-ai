from datetime import datetime

from pydantic import BaseModel, Field


class MemoryCreate(BaseModel):
    """Request to create a new memory."""

    content: str = Field(..., min_length=1, max_length=5000, description="The memory content")
    source_conversation_id: str | None = Field(
        None,
        description="Optional conversation ID this memory was extracted from",
    )


class MemoryUpdate(BaseModel):
    """Request to update a memory."""

    content: str | None = Field(
        None,
        min_length=1,
        max_length=5000,
        description="New memory content",
    )
    is_active: bool | None = Field(None, description="Active status of the memory")


class MemoryResponse(BaseModel):
    """Memory as returned by the API."""

    id: str = Field(..., description="Unique memory ID")
    user_id: str = Field(..., description="Owner user email")
    content: str = Field(..., description="The memory content")
    source_conversation_id: str | None = Field(
        None,
        description="Source conversation ID if applicable",
    )
    created_at: datetime = Field(..., description="When the memory was created")
    is_active: bool = Field(..., description="Whether the memory is active")

    model_config = {"from_attributes": True}
