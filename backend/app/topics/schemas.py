"""API contracts for topic discovery, activation, and context readiness."""

from __future__ import annotations

from datetime import datetime
from typing import Literal

from pydantic import BaseModel, Field, model_validator

TopicOrigin = Literal["history", "suggested", "manual"]


class TopicContextStatus(BaseModel):
    readiness: Literal["empty", "live", "ready", "preparing", "limited"] = "empty"
    context_version_id: str | None = None
    pack_version: int | None = None
    source_event_watermark: int = 0
    live_delta_count: int = 0
    is_fresh: bool = True
    updated_at: datetime | None = None


class TopicNode(BaseModel):
    id: str
    parent_id: str | None = None
    parent_label: str | None = None
    label: str
    origin: TopicOrigin
    score: float = Field(ge=0, le=1)
    signal: str | None = None
    child_count: int = 0
    children: list[TopicNode] = Field(default_factory=list)
    starter_prompts: list[str] = Field(default_factory=list)
    can_start: bool = True
    description: str | None = None
    context_status: TopicContextStatus = Field(default_factory=TopicContextStatus)
    updated_at: datetime


class TopicListResponse(BaseModel):
    mode: Literal["personal", "explore"]
    topics: list[TopicNode]
    generated_at: datetime


class TopicActivationRequest(BaseModel):
    topic_id: str | None = None
    label: str | None = Field(default=None, min_length=1, max_length=200)

    @model_validator(mode="after")
    def require_one_target(self) -> TopicActivationRequest:
        if bool(self.topic_id) == bool(self.label and self.label.strip()):
            raise ValueError("provide exactly one of topic_id or label")
        return self


class TopicSelectionUpdate(BaseModel):
    topic_id: str | None = None
    pinned: bool | None = None

    @model_validator(mode="after")
    def require_change(self) -> TopicSelectionUpdate:
        if "topic_id" not in self.model_fields_set and "pinned" not in self.model_fields_set:
            raise ValueError("provide topic_id and/or pinned")
        return self


class TopicActivationResponse(BaseModel):
    conversation_id: str
    topic: TopicNode | None
    topic_is_pinned: bool
    context_version: int
    context_status: TopicContextStatus


class TopicPrepareResponse(BaseModel):
    topic_id: str
    accepted: bool = True
    context_status: TopicContextStatus
