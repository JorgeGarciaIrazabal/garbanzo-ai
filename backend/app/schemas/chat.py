from datetime import datetime
from typing import Any, Literal

from pydantic import BaseModel, Field, model_validator

from app.core.config import get_settings

ThinkingLevel = Literal["off", "low", "medium", "high"]  # shared; see 017 migration


# Attachments


class AttachmentIn(BaseModel):
    """File attached to a chat message."""

    name: str = Field(..., description="Original filename")
    mime_type: str = Field(..., description="MIME type")
    type: Literal["image", "document"] = Field(..., description="Attachment category")
    encoding: Literal["base64", "utf-8"] | None = Field(
        default=None, description="Encoding; base64 for new clients, omitted for legacy UTF-8 docs"
    )
    data: str = Field(..., description="File payload using declared encoding")


# Chat messages


class ChatMessage(BaseModel):
    role: Literal["user", "assistant", "system"] = Field(..., description="Sender role")
    content: str = Field(..., description="Message content")


class ChatMessageOut(ChatMessage):
    role: Literal["user", "assistant", "system", "tool_call", "tool_result"] = Field(
        ..., description="Sender role"
    )  # type: ignore[assignment]
    id: str = Field(..., description="Unique message ID")
    created_at: datetime = Field(..., description="When created")
    meta: dict[str, Any] | None = Field(None, description="Metadata (tokens, timing, etc.)")
    session_epoch: int = Field(default=0, description="Session epoch within primary conversation")
    model_config = {"from_attributes": True}

    @model_validator(mode="after")
    def clean_thinking_tags(self) -> "ChatMessageOut":
        if self.role == "assistant" and "</think>" in self.content:
            parts = self.content.split("</think>", 1)
            raw_thinking = parts[0].replace("<think>", "").strip()
            self.content = parts[1].strip()
            if raw_thinking:
                if self.meta is None:
                    self.meta = {}
                existing = self.meta.get("thinking")
                if existing:
                    self.meta["thinking"] = f"{raw_thinking}\n\n{existing}"
                else:
                    self.meta["thinking"] = raw_thinking
        return self


# Chat request / options


class ChatOptions(BaseModel):
    temperature: float = Field(default=0.7, ge=0.0, le=2.0, description="Sampling temperature")
    max_tokens: int | None = Field(default=None, ge=1, description="Maximum tokens to generate")
    top_p: float | None = Field(default=None, ge=0.0, le=1.0, description="Nucleus sampling")
    stream: bool = Field(default=True, description="Whether to stream")
    response_format: dict | str | None = Field(
        default=None, description="Structured output spec passed to provider (Ollama `format`)"
    )
    num_ctx: int | None = Field(
        default=None, ge=512, description="Context window tokens (server-set; Ollama num_ctx)"
    )
    think: ThinkingLevel | None = Field(
        default=None, description="Reasoning depth; None=provider default, off=disable"
    )


class ChatRequest(BaseModel):
    message: str = Field(..., min_length=1, description="User message")
    attachments: list[AttachmentIn] = Field(default_factory=list, description="Files attached")
    options: ChatOptions = Field(default_factory=ChatOptions, description="Generation options")
    has_client_folder: bool = Field(
        default=False,
        description="Desktop client has folder attached (enables client-served file tools)",
    )
    client_folder_label: str | None = Field(
        default=None, max_length=255, description="Base name of attached folder (display only)"
    )
    talk_mode_instruction: str | None = Field(
        default=None,
        min_length=1,
        max_length=2000,
        description="Spoken-response instruction (ephemeral, not persisted)",
    )


class ClientToolResult(BaseModel):
    """Client answer to a client_tool_request (idea 17)."""

    tool_call_id: str = Field(..., description="Correlates with request chunk")
    ok: bool = Field(default=True, description="False when client couldn't serve")
    filename: str | None = Field(None, description="read_file: filename")
    data: str | None = Field(None, description="read_file: base64 bytes")
    entries: list[dict] | None = Field(None, description="list_files: directory entries")
    error: str | None = Field(None, description="Client error when ok is false")


class RegenerateRequest(BaseModel):
    options: ChatOptions = Field(default_factory=ChatOptions, description="Generation options")


class EditMessageRequest(BaseModel):
    content: str = Field(..., min_length=1, description="New message content")
    options: ChatOptions = Field(default_factory=ChatOptions, description="Generation options")


class ChatResponseChunk(BaseModel):
    type: Literal[
        "chunk",
        "thinking",
        "done",
        "error",
        "tool_call",
        "tool_result",
        "tool_execution",
        "action_proposal",
        "session",
        "client_tool_request",
        "topic_update",
        "context_preparing",
        "context_update",
    ] = Field(..., description="Chunk type")
    content: str | None = Field(None, description="Content for chunk/thinking")
    error: str | None = Field(None, description="Error message for type=error")
    metadata: dict[str, Any] | None = Field(None, description="Final metadata for type=done")
    tool_calls: list[dict[str, Any]] | None = Field(
        None, description="Tool calls for type=tool_call"
    )
    tool_result: dict[str, Any] | None = Field(None, description="Tool result for type=tool_result")


# Conversations


class ConversationCreate(BaseModel):
    title: str | None = Field(None, max_length=200, description="Optional title")
    model: str = Field(
        default_factory=lambda: get_settings().default_model,
        max_length=100,
        description="Model for this conversation",
    )
    initial_message: str | None = Field(None, description="Optional first message")
    system_prompt: str | None = Field(None, description="Per-conversation system prompt")
    thinking_level: ThinkingLevel | None = Field(
        None, description="Reasoning depth; None=provider default"
    )
    active_topic_id: str | None = Field(
        None, description="Optional topic to associate with this conversation"
    )


class ConversationUpdate(BaseModel):
    title: str | None = Field(None, max_length=200, description="New title")
    model: str | None = Field(None, max_length=100, description="Change model for future messages")
    use_memory: bool | None = Field(None, description="Enable/disable memory injection")
    use_knowledge_base: bool | None = Field(None, description="Enable/disable KB retrieval")
    system_prompt: str | None = Field(
        None, description="Per-conversation system prompt (empty to clear)"
    )
    enabled_tools: list[str] | None = Field(
        None, description='Allowed tool keys. None=all, []=none, ["srv:tool"]=subset'
    )
    is_pinned: bool | None = Field(None, description="Pin/unpin in sidebar")
    thinking_level: ThinkingLevel | None = Field(
        None, description="Reasoning depth; null=reset to provider default"
    )


def _active_topic_dict(conv: Any) -> dict[str, Any] | None:
    try:
        from sqlalchemy import inspect as sa_inspect

        state = sa_inspect(conv)
        if "active_topic" not in state.unloaded and conv.active_topic is not None:
            topic = conv.active_topic
            parent = getattr(topic, "parent", None)
            from app.topics.topic_description_helper import get_topic_high_level_description

            desc = get_topic_high_level_description(topic, parent)
            return {
                "id": topic.id,
                "label": topic.label,
                "parent_id": topic.parent_id,
                "parent_label": parent.label if parent else None,
                "description": desc,
                "starter_prompts": [
                    f"Continue with {topic.label}",
                    f"What should I do next about {topic.label}?",
                ],
                "context_status": "ready",
            }
    except Exception:
        pass
    return None


def _conv_base_kwargs(conv: Any, message_count: int, active_topic: dict | None) -> dict[str, Any]:
    return dict(
        id=conv.id,
        title=conv.title,
        model=conv.model,
        created_at=conv.created_at,
        updated_at=conv.updated_at,
        message_count=message_count,
        use_memory=getattr(conv, "use_memory", True),
        use_knowledge_base=getattr(conv, "use_knowledge_base", True),
        system_prompt=getattr(conv, "system_prompt", None),
        enabled_tools=getattr(conv, "enabled_tools", None),
        is_pinned=getattr(conv, "is_pinned", False),
        muted_until=getattr(conv, "muted_until", None),
        thinking_level=getattr(conv, "thinking_level", None),
        is_primary=getattr(conv, "is_primary", False),
        active_topic_id=getattr(conv, "active_topic_id", None),
        active_topic=active_topic,
        topic_is_pinned=getattr(conv, "topic_is_pinned", False),
        context_version=getattr(conv, "context_version", 0),
        session_epoch=getattr(conv, "session_epoch", 0),
    )


class ConversationOut(BaseModel):
    id: str = Field(..., description="Unique conversation ID")
    title: str | None = Field(None, description="Conversation title")
    model: str = Field(..., description="Model used")
    created_at: datetime = Field(..., description="When created")
    updated_at: datetime = Field(..., description="When last updated")
    message_count: int = Field(default=0, description="Number of messages")
    use_memory: bool = Field(default=True, description="Whether memory injection enabled")
    use_knowledge_base: bool = Field(default=True, description="Whether KB retrieval enabled")
    system_prompt: str | None = Field(None, description="Per-conversation system prompt, if set")
    enabled_tools: list[str] | None = Field(
        None, description='Allowed tool keys. None=all, []=none, ["srv:tool"]=subset'
    )
    is_pinned: bool = Field(default=False, description="Whether pinned")
    thinking_level: ThinkingLevel | None = Field(
        None, description="Reasoning depth or null for provider default"
    )
    is_primary: bool = Field(default=False, description="Whether unified primary chat")
    active_topic_id: str | None = Field(
        default=None, description="Currently selected/detected topic"
    )
    active_topic: dict[str, Any] | None = Field(
        default=None, description="Compact active topic with id, label, parent_id"
    )
    topic_is_pinned: bool = Field(
        default=False, description="Whether auto topic switching disabled"
    )
    context_version: int = Field(default=0, description="Monotonic active-context version")
    session_epoch: int = Field(default=0, description="Current primary chat session epoch")
    muted_until: datetime | None = Field(None, description="When muting expires or null")

    model_config = {"from_attributes": True}

    @classmethod
    def from_model(cls, conv: Any) -> "ConversationOut":
        from sqlalchemy import inspect as sa_inspect
        from sqlalchemy.orm import InstanceState

        message_count = 0
        try:
            state: InstanceState = sa_inspect(conv)
            if "messages" not in state.unloaded:
                message_count = len(conv.messages) if conv.messages else 0
        except Exception:
            pass
        return cls(**_conv_base_kwargs(conv, message_count, _active_topic_dict(conv)))


def message_out(msg: Any) -> ChatMessageOut:
    return ChatMessageOut(
        id=msg.id,
        role=msg.role,
        content=msg.content,
        created_at=msg.created_at,
        meta=msg.meta,
        session_epoch=getattr(msg, "session_epoch", 0),
    )


class ConversationDetailOut(ConversationOut):
    messages: list[ChatMessageOut] = Field(
        default_factory=list, description="Messages; all unless message_limit windowing"
    )
    context_summary: str | None = Field(
        None, description="Summary of earlier messages trimmed from context"
    )
    has_more_messages: bool = Field(
        default=False, description="True when windowed and older messages exist"
    )

    @classmethod
    def from_model(cls, conv: Any) -> "ConversationDetailOut":
        messages = list(conv.messages or [])
        if getattr(conv, "is_primary", False):
            epoch = getattr(conv, "session_epoch", 0)
            messages = [m for m in messages if getattr(m, "session_epoch", 0) == epoch]
        return cls.from_model_page(
            conv,
            messages,
            total_message_count=len(messages),
            has_more_messages=False,
        )

    @classmethod
    def from_model_page(
        cls, conv: Any, messages: list[Any], *, total_message_count: int, has_more_messages: bool
    ) -> "ConversationDetailOut":
        """Build from ORM plus explicit message list; avoids touching conv.messages cascade."""
        out_messages = [message_out(msg) for msg in messages]
        base = _conv_base_kwargs(conv, total_message_count, _active_topic_dict(conv))
        return cls(
            **base,
            messages=out_messages,
            has_more_messages=has_more_messages,
            context_summary=getattr(conv, "context_summary", None),
        )


class ConversationList(BaseModel):
    items: list[ConversationOut] = Field(..., description="The conversations")
    total: int = Field(..., description="Total conversations")
    page: int = Field(default=1, description="Current page")
    page_size: int = Field(default=20, description="Items per page")


class MessagePage(BaseModel):
    messages: list[ChatMessageOut] = Field(..., description="Page of messages")
    has_more: bool = Field(..., description="Whether older messages remain")


# Search


class MatchedMessage(BaseModel):
    id: str = Field(..., description="Unique message ID")
    role: Literal["user", "assistant", "system", "tool_call", "tool_result"] = Field(
        ..., description="Sender role"
    )
    content: str = Field(..., description="Full message content")
    snippet: str = Field(..., description="Excerpt around first match (~100 chars + ellipses)")
    created_at: datetime = Field(..., description="When created")
    model_config = {"from_attributes": True}


class ConversationSearchResult(BaseModel):
    conversation: ConversationOut = Field(..., description="Matched conversation")
    matched_messages: list[MatchedMessage] = Field(
        default_factory=list, description="Messages whose content matched (may be empty)"
    )


class ConversationSearchResponse(BaseModel):
    items: list[ConversationSearchResult] = Field(..., description="Search hits")
    total: int = Field(..., description="Total matching conversations")
    page: int = Field(default=1, description="Current page")
    page_size: int = Field(default=20, description="Items per page")
    query: str = Field(..., description="Original query")


# Models


class ModelInfo(BaseModel):
    id: str = Field(..., description="Model identifier")
    name: str = Field(..., description="Human-readable name")
    description: str | None = Field(None, description="Model description")
    context_length: int | None = Field(None, description="Maximum context length tokens")
    provider: str = Field(default="ollama", description="Provider name")
    supports_tools: bool | None = Field(
        None, description="Whether supports tool calling (None=unknown)"
    )
    supports_vision: bool | None = Field(
        None, description="Whether accepts image input (None=unknown)"
    )
    supports_thinking: bool | None = Field(
        None, description="Whether emits thinking tokens (None=unknown)"
    )
    thinking_levels: list[ThinkingLevel] | None = Field(
        None, description="Normalized thinking controls; null=unknown"
    )
    default_thinking_level: ThinkingLevel | None = Field(
        None, description="Provider default thinking level"
    )


class ModelList(BaseModel):
    models: list[ModelInfo] = Field(..., description="Available models")
    default_model: str = Field(
        default_factory=lambda: get_settings().default_model, description="Server default model"
    )


# Message metadata


class MessageMetadata(BaseModel):
    """Structured schema for JSONB Message.meta."""

    tokens_generated: int | None = Field(None, ge=0, description="Tokens in response")
    tokens_prompt: int | None = Field(None, ge=0, description="Tokens in prompt")
    total_duration_ns: int | None = Field(None, ge=0, description="Total duration ns")
    thinking: str | None = Field(None, description="Thinking content")
    error: bool | None = Field(None, description="Whether error")
    error_type: str | None = Field(None, description="Error type")
    status_code: int | None = Field(None, description="HTTP status for errors")
    cancelled: bool | None = Field(None, description="Whether stream cancelled")
    attachments: list[dict[str, Any]] | None = Field(None, description="File attachment metadata")
