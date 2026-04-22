"""Schemas for the token usage dashboard."""

from pydantic import BaseModel


class UsageByModel(BaseModel):
    model: str
    tokens_prompt: int
    tokens_generated: int
    message_count: int


class UsageByConversation(BaseModel):
    conversation_id: str
    title: str | None
    tokens_prompt: int
    tokens_generated: int
    message_count: int


class UsageByDay(BaseModel):
    date: str  # ISO date, YYYY-MM-DD
    tokens_prompt: int
    tokens_generated: int


class UsageSummary(BaseModel):
    days: int
    total_tokens_prompt: int
    total_tokens_generated: int
    total_messages: int
    by_model: list[UsageByModel]
    by_conversation: list[UsageByConversation]
    by_day: list[UsageByDay]
