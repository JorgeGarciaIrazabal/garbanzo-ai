from datetime import datetime

from pydantic import BaseModel, Field


class SystemPromptGenerateRequest(BaseModel):
    """Request body for the AI-assisted system prompt generator."""

    intent: str = Field(
        ...,
        min_length=1,
        max_length=1000,
        description="Natural-language description of what the prompt should do.",
    )
    existing_prompt: str | None = Field(
        None,
        max_length=8000,
        description="The current draft to revise (refine mode). When present with feedback, the LLM revises instead of regenerating.",
    )
    feedback: str | None = Field(
        None,
        max_length=1000,
        description='Refinement instructions (e.g. "make it friendlier"). Requires existing_prompt.',
    )
    model: str | None = Field(
        None,
        description="Model to use; falls back to the server default_model.",
    )


class SystemPromptTemplateOut(BaseModel):
    """A system prompt template (persona or user-saved prompt)."""

    id: str
    name: str
    description: str | None = None
    content: str
    is_builtin: bool
    created_at: datetime

    model_config = {"from_attributes": True}


class SystemPromptTemplateCreate(BaseModel):
    """Create a user-owned template."""

    name: str = Field(..., min_length=1, max_length=100)
    description: str | None = Field(None, max_length=500)
    content: str = Field(..., min_length=1)


class SystemPromptTemplateUpdate(BaseModel):
    """Update a user-owned template. Builtins are read-only."""

    name: str | None = Field(None, min_length=1, max_length=100)
    description: str | None = Field(None, max_length=500)
    content: str | None = Field(None, min_length=1)


class UserDefaultPromptOut(BaseModel):
    """The user's global default system prompt."""

    default_system_prompt: str | None = None


class UserDefaultPromptUpdate(BaseModel):
    """Set or clear the user's global default system prompt.

    Send ``None`` or an empty string to clear it.
    """

    default_system_prompt: str | None = None
