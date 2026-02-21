from datetime import datetime
from typing import Any, Literal, Optional

from pydantic import BaseModel, Field


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

    id: str = Field(..., description="Unique message ID")
    created_at: datetime = Field(..., description="When the message was created")
    meta: Optional[dict[str, Any]] = Field(
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
    max_tokens: Optional[int] = Field(
        default=None,
        ge=1,
        description="Maximum tokens to generate",
    )
    top_p: Optional[float] = Field(
        default=None,
        ge=0.0,
        le=1.0,
        description="Nucleus sampling parameter",
    )
    stream: bool = Field(
        default=True,
        description="Whether to stream the response",
    )


class ChatRequest(BaseModel):
    """Request to send a message in a conversation."""

    message: str = Field(..., min_length=1, description="The user's message")
    options: ChatOptions = Field(
        default_factory=ChatOptions,
        description="Generation options",
    )


class ChatResponseChunk(BaseModel):
    """A chunk of a streaming chat response."""

    type: Literal["chunk", "done", "error"] = Field(
        ...,
        description="The type of response chunk",
    )
    content: Optional[str] = Field(
        None,
        description="The content chunk (for type='chunk')",
    )
    error: Optional[str] = Field(
        None,
        description="Error message (for type='error')",
    )
    metadata: Optional[dict[str, Any]] = Field(
        None,
        description="Final metadata (for type='done')",
    )


# ============================================================================
# Conversation Schemas
# ============================================================================

class ConversationCreate(BaseModel):
    """Request to create a new conversation."""

    title: Optional[str] = Field(
        None,
        max_length=200,
        description="Optional conversation title",
    )
    model: str = Field(
        default="llama3.2",
        max_length=100,
        description="The model to use for this conversation",
    )
    initial_message: Optional[str] = Field(
        None,
        description="Optional first message to start the conversation",
    )


class ConversationUpdate(BaseModel):
    """Request to update a conversation."""

    title: Optional[str] = Field(
        None,
        max_length=200,
        description="New title for the conversation",
    )
    model: Optional[str] = Field(
        None,
        max_length=100,
        description="Change the model for future messages",
    )


class ConversationOut(BaseModel):
    """Conversation as returned by the API."""

    id: str = Field(..., description="Unique conversation ID")
    title: Optional[str] = Field(None, description="Conversation title")
    model: str = Field(..., description="Model used for this conversation")
    created_at: datetime = Field(..., description="When the conversation was created")
    updated_at: datetime = Field(..., description="When the conversation was last updated")
    message_count: int = Field(
        default=0,
        description="Number of messages in the conversation",
    )

    model_config = {"from_attributes": True}

    @classmethod
    def from_model(cls, conv: "Any") -> "ConversationOut":
        """Build from an ORM ``Conversation`` instance."""
        return cls(
            id=conv.id,
            title=conv.title,
            model=conv.model,
            created_at=conv.created_at,
            updated_at=conv.updated_at,
            message_count=len(conv.messages) if hasattr(conv, "messages") and conv.messages else 0,
        )


class ConversationDetailOut(ConversationOut):
    """Conversation with full message history."""

    messages: list[ChatMessageOut] = Field(
        default_factory=list,
        description="All messages in the conversation",
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
        )


class ConversationList(BaseModel):
    """List of conversations with pagination."""

    items: list[ConversationOut] = Field(..., description="The conversations")
    total: int = Field(..., description="Total number of conversations")
    page: int = Field(default=1, description="Current page number")
    page_size: int = Field(default=20, description="Items per page")


# ============================================================================
# Model Info Schemas
# ============================================================================

class ModelInfo(BaseModel):
    """Information about an available LLM model."""

    id: str = Field(..., description="Model identifier")
    name: str = Field(..., description="Human-readable model name")
    description: Optional[str] = Field(None, description="Model description")
    context_length: Optional[int] = Field(
        None,
        description="Maximum context length in tokens",
    )
    provider: str = Field(default="ollama", description="Provider name (e.g., 'ollama')")


class ModelList(BaseModel):
    """List of available models."""

    models: list[ModelInfo] = Field(..., description="Available models")
