from datetime import datetime
from typing import Any, Literal

from pydantic import BaseModel, Field

from app.core.config import get_settings

# ============================================================================
# Attachment Schemas
# ============================================================================


class AttachmentIn(BaseModel):
    """A file attached to a chat message."""

    name: str = Field(..., description="Original filename")
    mime_type: str = Field(..., description="MIME type of the file")
    type: Literal["image", "document"] = Field(..., description="Attachment category")
    data: str = Field(
        ...,
        description="Base64-encoded bytes for images; plain text for documents",
    )


# ============================================================================
# Chat Message Schemas
# ============================================================================


class ChatMessage(BaseModel):
    """A single message in the chat."""

    role: Literal["user", "assistant", "system"] = Field(
        ...,
        description="The role of the message sender",
    )
    content: str = Field(..., description="The message content")


class ChatMessageOut(ChatMessage):
    """Message as returned by the API, with metadata."""

    role: Literal[  # type: ignore[assignment]
        "user", "assistant", "system", "tool_call", "tool_result"
    ] = Field(..., description="The role of the message sender")
    id: str = Field(..., description="Unique message ID")
    created_at: datetime = Field(..., description="When the message was created")
    meta: dict[str, Any] | None = Field(
        None,
        description="Additional metadata (tokens, timing, etc.)",
    )

    model_config = {"from_attributes": True}


# ============================================================================
# Chat Request/Response Schemas
# ============================================================================


class ChatOptions(BaseModel):
    """Options for the chat completion."""

    temperature: float = Field(
        default=0.7,
        ge=0.0,
        le=2.0,
        description="Sampling temperature",
    )
    max_tokens: int | None = Field(
        default=None,
        ge=1,
        description="Maximum tokens to generate",
    )
    top_p: float | None = Field(
        default=None,
        ge=0.0,
        le=1.0,
        description="Nucleus sampling parameter",
    )
    stream: bool = Field(
        default=True,
        description="Whether to stream the response",
    )
    response_format: dict | str | None = Field(
        default=None,
        description=(
            "Optional structured-output spec passed straight through to the "
            "provider. For Ollama this maps to the `format` parameter — "
            "either the literal string 'json' or a JSON Schema dict."
        ),
    )
    num_ctx: int | None = Field(
        default=None,
        ge=512,
        description=(
            "Context window to allocate, in tokens. Normally set by the "
            "server (min of the model's maximum and the configured cap), "
            "not by clients. For Ollama this maps to options.num_ctx."
        ),
    )


class ChatRequest(BaseModel):
    """Request to send a message in a conversation."""

    message: str = Field(..., min_length=1, description="The user's message")
    attachments: list[AttachmentIn] = Field(
        default_factory=list,
        description="Files attached to this message",
    )
    options: ChatOptions = Field(
        default_factory=ChatOptions,
        description="Generation options",
    )


class RegenerateRequest(BaseModel):
    """Request to regenerate an assistant response."""

    options: ChatOptions = Field(
        default_factory=ChatOptions,
        description="Generation options",
    )


class EditMessageRequest(BaseModel):
    """Request to edit a user message and re-run the conversation from it."""

    content: str = Field(..., min_length=1, description="The new message content")
    options: ChatOptions = Field(
        default_factory=ChatOptions,
        description="Generation options",
    )


class ChatResponseChunk(BaseModel):
    """A chunk of a streaming chat response."""

    type: Literal[
        "chunk",
        "thinking",
        "done",
        "error",
        "tool_call",
        "tool_result",
        # Live tool-progress marker (started / finished + duration). Already
        # emitted by the chat streamer; declared here so validation passes.
        "tool_execution",
        # Session handshake emitted by the micro-apps agent relay so the
        # client learns the opencode session id early enough to abort it.
        "session",
    ] = Field(
        ...,
        description="The type of response chunk",
    )
    content: str | None = Field(
        None,
        description="The content chunk (for type='chunk' or 'thinking')",
    )
    error: str | None = Field(
        None,
        description="Error message (for type='error')",
    )
    metadata: dict[str, Any] | None = Field(
        None,
        description="Final metadata (for type='done')",
    )
    tool_calls: list[dict[str, Any]] | None = Field(
        None,
        description=(
            "Tool calls requested by the model (for type='tool_call'). "
            "Each call has {id, name, arguments}."
        ),
    )
    tool_result: dict[str, Any] | None = Field(
        None,
        description=(
            "The result of a single tool invocation (for type='tool_result'). "
            "Shape: {tool_call_id, tool_name, result}."
        ),
    )


# ============================================================================
# Conversation Schemas
# ============================================================================


class ConversationCreate(BaseModel):
    """Request to create a new conversation."""

    title: str | None = Field(
        None,
        max_length=200,
        description="Optional conversation title",
    )
    model: str = Field(
        default_factory=lambda: get_settings().default_model,
        max_length=100,
        description="The model to use for this conversation",
    )
    initial_message: str | None = Field(
        None,
        description="Optional first message to start the conversation",
    )
    system_prompt: str | None = Field(
        None,
        description="Per-conversation system prompt (overrides the user default)",
    )


class ConversationUpdate(BaseModel):
    """Request to update a conversation."""

    title: str | None = Field(
        None,
        max_length=200,
        description="New title for the conversation",
    )
    model: str | None = Field(
        None,
        max_length=100,
        description="Change the model for future messages",
    )
    use_memory: bool | None = Field(
        None,
        description="Enable/disable memory injection for this conversation",
    )
    use_knowledge_base: bool | None = Field(
        None,
        description="Enable/disable knowledge-base retrieval for this conversation",
    )
    system_prompt: str | None = Field(
        None,
        description=(
            "Per-conversation system prompt. Send an empty string to clear it "
            "and fall back to the user default."
        ),
    )
    enabled_tools: list[str] | None = Field(
        None,
        description=(
            "Allowed tool keys for this conversation. None = all enabled tools, "
            "[] = no tools, [\"srv:tool\"] = specific subset. "
            "Each key is \"{server_id}:{tool_name}\"."
        ),
    )
    is_pinned: bool | None = Field(
        None,
        description="Pin/unpin this conversation in the sidebar",
    )


class ConversationOut(BaseModel):
    """Conversation as returned by the API."""

    id: str = Field(..., description="Unique conversation ID")
    title: str | None = Field(None, description="Conversation title")
    model: str = Field(..., description="Model used for this conversation")
    created_at: datetime = Field(..., description="When the conversation was created")
    updated_at: datetime = Field(..., description="When the conversation was last updated")
    message_count: int = Field(
        default=0,
        description="Number of messages in the conversation",
    )
    use_memory: bool = Field(default=True, description="Whether memory injection is enabled")
    use_knowledge_base: bool = Field(
        default=True, description="Whether knowledge-base retrieval is enabled"
    )
    system_prompt: str | None = Field(
        None,
        description="Per-conversation system prompt, if set",
    )
    enabled_tools: list[str] | None = Field(
        None,
        description=(
            "Allowed tool keys. None = all enabled tools, "
            "[] = none, [\"srv:tool\"] = subset."
        ),
    )
    is_pinned: bool = Field(default=False, description="Whether this conversation is pinned")

    model_config = {"from_attributes": True}

    @classmethod
    def from_model(cls, conv: "Any") -> "ConversationOut":
        """Build from an ORM ``Conversation`` instance."""
        from sqlalchemy import inspect as sa_inspect
        from sqlalchemy.orm import InstanceState

        message_count = 0
        try:
            state: InstanceState = sa_inspect(conv)
            if "messages" not in state.unloaded:
                message_count = len(conv.messages) if conv.messages else 0
        except Exception:
            pass

        return cls(
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
        )


class ConversationDetailOut(ConversationOut):
    """Conversation with full message history."""

    messages: list[ChatMessageOut] = Field(
        default_factory=list,
        description="All messages in the conversation",
    )
    context_summary: str | None = Field(
        None, description="Summary of earlier messages trimmed from context"
    )

    @classmethod
    def from_model(cls, conv: "Any") -> "ConversationDetailOut":
        """Build from an ORM ``Conversation`` with eagerly-loaded messages."""
        messages = [
            ChatMessageOut(
                id=msg.id,
                role=msg.role,  # type: ignore[arg-type]
                content=msg.content,
                created_at=msg.created_at,
                meta=msg.meta,
            )
            for msg in conv.messages
        ]
        return cls(
            id=conv.id,
            title=conv.title,
            model=conv.model,
            created_at=conv.created_at,
            updated_at=conv.updated_at,
            message_count=len(messages),
            messages=messages,
            use_memory=getattr(conv, "use_memory", True),
            use_knowledge_base=getattr(conv, "use_knowledge_base", True),
            context_summary=getattr(conv, "context_summary", None),
            system_prompt=getattr(conv, "system_prompt", None),
            enabled_tools=getattr(conv, "enabled_tools", None),
            is_pinned=getattr(conv, "is_pinned", False),
        )


class ConversationList(BaseModel):
    """List of conversations with pagination."""

    items: list[ConversationOut] = Field(..., description="The conversations")
    total: int = Field(..., description="Total number of conversations")
    page: int = Field(default=1, description="Current page number")
    page_size: int = Field(default=20, description="Items per page")


# ============================================================================
# Conversation Search Schemas
# ============================================================================


class MatchedMessage(BaseModel):
    """A single message whose content matched a search query."""

    id: str = Field(..., description="Unique message ID")
    role: Literal["user", "assistant", "system", "tool_call", "tool_result"] = Field(
        ...,
        description="The role of the message sender",
    )
    content: str = Field(..., description="The full message content")
    snippet: str = Field(
        ...,
        description=(
            "A short excerpt around the first match location — up to ~100 chars "
            "before and after the matched substring, with ellipses when truncated."
        ),
    )
    created_at: datetime = Field(..., description="When the message was created")

    model_config = {"from_attributes": True}


class ConversationSearchResult(BaseModel):
    """A single conversation search hit.

    Contains the conversation metadata plus any messages within that
    conversation that matched the query. ``matched_messages`` is empty
    when the match was on the title only.
    """

    conversation: ConversationOut = Field(..., description="The matched conversation")
    matched_messages: list[MatchedMessage] = Field(
        default_factory=list,
        description="Messages whose content matched the query (may be empty).",
    )


class ConversationSearchResponse(BaseModel):
    """Paginated list of search results."""

    items: list[ConversationSearchResult] = Field(..., description="Search hits")
    total: int = Field(..., description="Total number of matching conversations")
    page: int = Field(default=1, description="Current page number")
    page_size: int = Field(default=20, description="Items per page")
    query: str = Field(..., description="The original search query")


# ============================================================================
# Model Info Schemas
# ============================================================================


class ModelInfo(BaseModel):
    """Information about an available LLM model."""

    id: str = Field(..., description="Model identifier")
    name: str = Field(..., description="Human-readable model name")
    description: str | None = Field(None, description="Model description")
    context_length: int | None = Field(
        None,
        description="Maximum context length in tokens",
    )
    provider: str = Field(default="ollama", description="Provider name (e.g., 'ollama')")
    supports_tools: bool | None = Field(
        None, description="Whether the model supports tool calling (None = unknown)"
    )
    supports_vision: bool | None = Field(
        None, description="Whether the model accepts image input (None = unknown)"
    )
    supports_thinking: bool | None = Field(
        None, description="Whether the model emits thinking tokens (None = unknown)"
    )


class ModelList(BaseModel):
    """List of available models."""

    models: list[ModelInfo] = Field(..., description="Available models")
    default_model: str = Field(
        default_factory=lambda: get_settings().default_model,
        description="The server's default model, used when a conversation doesn't specify one",
    )


# ============================================================================
# Message Metadata Schema
# ============================================================================


class MessageMetadata(BaseModel):
    """Structured schema for the JSONB `Message.meta` column.

    Validates token counts, timing information, and optional content
    stored alongside each assistant message.
    """

    tokens_generated: int | None = Field(None, ge=0, description="Tokens in the response")
    tokens_prompt: int | None = Field(None, ge=0, description="Tokens in the prompt")
    total_duration_ns: int | None = Field(None, ge=0, description="Total duration in nanoseconds")
    thinking: str | None = Field(None, description="Thinking/reasoning content from the model")
    error: bool | None = Field(None, description="Whether this message is an error")
    error_type: str | None = Field(None, description="Type of error if applicable")
    status_code: int | None = Field(None, description="HTTP status code for error responses")
    cancelled: bool | None = Field(None, description="Whether the stream was cancelled")
    attachments: list[dict[str, Any]] | None = Field(None, description="File attachment metadata")
