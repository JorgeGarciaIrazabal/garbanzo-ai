"""Current active-context API schemas (no historical activity feed)."""

from __future__ import annotations

from datetime import datetime
from typing import Any, Literal

from pydantic import BaseModel, Field, model_validator

from app.topics.schemas import TopicContextStatus

ContextSourceType = Literal[
    "topic_assertion",
    "message",
    "thread",
    "memory",
    "knowledge",
    "attachment",
    "carryover",
]
ContextItemState = Literal["dynamic", "pinned", "excluded"]


class ActiveContextTopic(BaseModel):
    id: str
    label: str
    parent_id: str | None = None
    parent_label: str | None = None
    description: str | None = None
    pinned: bool = False
    combined_topics: list[str] = Field(default_factory=list)


class ActiveContextItemOut(BaseModel):
    id: str
    source_type: ContextSourceType
    source_id: str
    source_meta: dict[str, Any] = Field(default_factory=dict)
    topic_id: str | None = None
    state: ContextItemState
    reason: str | None = None
    relevance_score: float = 0
    token_count: int = 0
    last_selected_at: datetime
    summary: str | None = None
    display_text: str | None = None
    category_label: str | None = None

    model_config = {"from_attributes": True}


class ActiveContextResponse(BaseModel):
    conversation_id: str
    context_version: int
    topic: ActiveContextTopic | None = None
    status: TopicContextStatus
    token_count: int = 0
    token_budget: int
    pinned_items: list[ActiveContextItemOut] = Field(default_factory=list)
    dynamic_items: list[ActiveContextItemOut] = Field(default_factory=list)
    excluded_items: list[ActiveContextItemOut] = Field(default_factory=list)
    next_turn_summary: str | None = None
    topic_description: str | None = None
    context_summary: str | None = None
    context_sections: list[dict[str, Any]] = Field(default_factory=list)


class ActiveContextItemCreate(BaseModel):
    source_type: ContextSourceType
    source_id: str = Field(min_length=1, max_length=255)
    source_meta: dict[str, Any] = Field(default_factory=dict)
    topic_id: str | None = None
    state: ContextItemState = "pinned"
    reason: str | None = Field(default=None, max_length=500)
    context_version: int = Field(ge=0)


class ActiveContextItemUpdate(BaseModel):
    state: ContextItemState
    context_version: int = Field(ge=0)


class FreshStartRequest(BaseModel):
    keep_pins: bool
    context_version: int = Field(ge=0)


class ContextMutationResponse(BaseModel):
    item: ActiveContextItemOut | None = None
    context_version: int


class ContextConflict(BaseModel):
    detail: str = "context_version_conflict"
    current_context_version: int


class ContextUpdateEvent(BaseModel):
    context_version: int
    active_topic: ActiveContextTopic | None = None
    pinned_count: int = 0
    dynamic_count: int = 0
    excluded_count: int = 0


class ContextSourceLocator(BaseModel):
    source_type: ContextSourceType
    source_id: str

    @model_validator(mode="after")
    def nonempty_source(self) -> ContextSourceLocator:
        if not self.source_id.strip():
            raise ValueError("source_id must not be empty")
        return self


class CarryoverRequest(BaseModel):
    enabled: bool = True
    max_items: int = Field(default=5, ge=0, le=20)
    max_tokens: int = Field(default=400, ge=0, le=2000)


class TopicSwitchRequest(BaseModel):
    topic_id: str | None = None
    label: str | None = Field(default=None, max_length=200)
    archive: bool = True
    carryover: CarryoverRequest = Field(default_factory=CarryoverRequest)
    mode: Literal["switch", "combine"] = "switch"


class TopicSwitchResponse(BaseModel):
    conversation_id: str
    topic: ActiveContextTopic | None = None
    context_version: int
    session_epoch: int = 0
    archived: bool
    archive_id: str | None = None
    carryover: list[ActiveContextItemOut] = Field(default_factory=list)
    next_turn_summary: str | None = None


class TopicArchiveOut(BaseModel):
    id: str
    topic_id: str | None = None
    from_topic_id: str | None = None
    conversation_id: str
    message_count: int
    short_summary: str | None = None
    created_at: datetime

    model_config = {"from_attributes": True}


class TopicArchiveListResponse(BaseModel):
    topic_id: str
    archives: list[TopicArchiveOut] = Field(default_factory=list)
