"""Pydantic schemas for saved styles (Idea 2: "Styles")."""

from datetime import datetime

from pydantic import BaseModel, Field

from app.core.config import get_settings
from app.schemas.chat import ThinkingLevel


class StyleCreate(BaseModel):
    """Request to create a saved style."""

    name: str = Field(..., min_length=1, max_length=100)
    model_id: str = Field(
        default_factory=lambda: get_settings().default_model,
        max_length=100,
        description="The model this style selects",
    )
    thinking_level: ThinkingLevel | None = Field(
        None,
        description=(
            "Reasoning depth for thinking-capable models. None = provider "
            "default (auto-enable thinking when the model supports it)."
        ),
    )
    system_prompt_template_id: str | None = Field(
        None,
        description="A system prompt template this style applies, or null for none",
    )
    is_default: bool = Field(
        False,
        description=(
            "Make this the style used to seed new conversations. Setting "
            "this unsets any previous default for the user."
        ),
    )


class StyleUpdate(BaseModel):
    """Partial update for a saved style. Omitted fields are left unchanged."""

    name: str | None = Field(None, min_length=1, max_length=100)
    model_id: str | None = Field(None, max_length=100)
    thinking_level: ThinkingLevel | None = Field(
        None,
        description=(
            "Reasoning depth for thinking-capable models. Not sent in the "
            "payload -> unchanged. Sent as null -> reset to the provider "
            "default. Sent as 'off'/'low'/'medium'/'high' -> set that level."
        ),
    )
    system_prompt_template_id: str | None = Field(
        None,
        description=("Not sent in the payload -> unchanged. Sent as null -> clear it."),
    )
    is_default: bool | None = Field(
        None,
        description="Make/unmake this the default style for new conversations",
    )


class StyleOut(BaseModel):
    """A saved style as returned by the API."""

    id: str
    name: str
    model_id: str
    thinking_level: ThinkingLevel | None = None
    system_prompt_template_id: str | None = None
    is_default: bool
    created_at: datetime
    updated_at: datetime

    model_config = {"from_attributes": True}
