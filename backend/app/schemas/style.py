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
    """Partial update for a saved style. Omitted fields are left unchanged.

    Built-in styles are read-only for content fields (name/model/thinking/
    template) — the endpoint returns 403 for those. ``is_default`` is the
    exception: it writes a per-user pointer, so a built-in can be set as
    the user's default for new chats.
    """

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
        description=(
            "Make/unmake this the default style for new conversations. "
            "Allowed for built-in styles too — it sets a per-user pointer "
            "rather than mutating the shared row."
        ),
    )


class StyleOut(BaseModel):
    """A saved style as returned by the API. Includes built-in flag,
    locale, and description so the picker can render built-ins consistently
    with user-saved styles and filter them by the user's language.
    """

    id: str
    name: str
    description: str | None = None
    model_id: str
    thinking_level: ThinkingLevel | None = None
    system_prompt_template_id: str | None = None
    is_builtin: bool = False
    locale: str | None = None
    is_default: bool
    created_at: datetime
    updated_at: datetime

    model_config = {"from_attributes": True}
