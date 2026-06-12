"""Abstract base class for LLM providers."""

import asyncio
import logging
import re
from abc import ABC, abstractmethod
from collections.abc import AsyncIterator
from dataclasses import dataclass
from typing import Any, Optional

from app.core.config import get_settings
from app.schemas.chat import ChatOptions

logger = logging.getLogger(__name__)


@dataclass
class Message:
    """A message for the LLM."""

    role: str  # "user", "assistant", "system", "tool"
    content: str
    images: list[str] | None = None  # base64-encoded images for multimodal models
    # Structured tool calls on an assistant turn. When present the provider
    # MUST send these via the API's native tool_calls field — never stuffed
    # into ``content`` as raw JSON, or the model will mimic the format and
    # emit tool calls as text on subsequent turns.
    tool_calls: list[dict[str, Any]] | None = None


@dataclass
class ModelInfo:
    """Information about an available model.

    Capability flags are tri-state: True/False when the provider reports
    them, None when unknown (callers should treat None as "try and see").
    """

    id: str
    name: str
    description: str | None = None
    context_length: int | None = None
    supports_tools: bool | None = None
    supports_vision: bool | None = None
    supports_thinking: bool | None = None


@dataclass
class ChatChunk:
    """A chunk of streaming response."""

    content: str
    is_finished: bool = False
    is_thinking: bool = False
    metadata: dict[str, Any] | None = None
    # Tool calls requested by the model on this chunk. Each entry has
    # {id, name, arguments}. When set, ``content`` is typically empty and
    # ``is_finished`` is False — the normal "done" chunk follows.
    tool_calls: list[dict[str, Any]] | None = None


class LLMProvider(ABC):
    """Abstract base class for LLM providers.

    This class defines the interface that all LLM providers must implement.
    It supports streaming responses and model discovery.
    """

    @property
    @abstractmethod
    def name(self) -> str:
        """Return the provider name (e.g., 'ollama', 'openai')."""
        ...

    @abstractmethod
    async def stream_chat(
        self,
        messages: list[Message],
        model: str,
        options: ChatOptions | None = None,
        cancel_event: Optional["asyncio.Event"] = None,
        tools: list[dict[str, Any]] | None = None,
    ) -> AsyncIterator[ChatChunk]:
        """Stream chat completion from the LLM.

        Args:
            messages: List of messages in the conversation
            model: The model identifier to use
            options: Optional generation parameters
            cancel_event: Optional event to signal cancellation

        Yields:
            ChatChunk: Chunks of the generated response
        """
        ...

    @abstractmethod
    async def chat(
        self,
        messages: list[Message],
        model: str,
        options: ChatOptions | None = None,
        tools: list[dict[str, Any]] | None = None,
    ) -> str:
        """Non-streaming chat completion from the LLM.

        Args:
            messages: List of messages in the conversation
            model: The model identifier to use
            options: Optional generation parameters

        Returns:
            The complete response content as a string
        """
        ...

    async def get_model_context_length(self, model: str) -> int | None:
        """Return the model's maximum context length in tokens, if known.

        Providers that can query model metadata should override this;
        the default reports "unknown" and callers fall back to estimates.
        """
        return None

    @abstractmethod
    async def list_models(self) -> list[ModelInfo]:
        """List available models from this provider.

        Returns:
            List of available models with their information
        """
        ...

    @abstractmethod
    async def health_check(self) -> bool:
        """Check if the provider is healthy and available.

        Returns:
            True if the provider is accessible, False otherwise
        """
        ...


def estimate_context_length(model_name: str) -> int:
    """Estimate context length from the parameter size in the model name.

    Last-resort fallback for when the provider can't report the model's
    real maximum (e.g. provider unreachable or remote/cloud models).
    """
    match = re.search(r"(\d+(?:\.\d+)?)b", model_name.lower())
    if match:
        size = float(match.group(1))
        if size <= 3:
            return 4096
        elif size <= 8:
            return 8192
        elif size <= 20:
            return 32768
        else:
            return 131072
    return 8192


async def resolve_context_length(provider: LLMProvider, model: str) -> int:
    """Effective context window for ``model``, in tokens.

    min(model's real maximum, configured cap). This is the window callers
    should ask the provider to allocate (num_ctx) and the denominator for
    summarization triggers and usage display — one number everywhere.
    """
    model_max: int | None = None
    try:
        model_max = await provider.get_model_context_length(model)
    except Exception as e:
        logger.warning("Context-length lookup failed for %s: %s", model, e)
    if model_max is None:
        model_max = estimate_context_length(model)
    return max(512, min(model_max, get_settings().llm_context_window))


class ProviderRegistry:
    """Registry for LLM providers.

    This allows multiple providers to be registered and looked up by name.
    Future providers (OpenAI, Anthropic, etc.) can be added here.
    """

    _providers: dict[str, LLMProvider] = {}

    @classmethod
    def register(cls, provider: LLMProvider) -> None:
        """Register a provider."""
        cls._providers[provider.name] = provider

    @classmethod
    def get(cls, name: str) -> LLMProvider | None:
        """Get a provider by name."""
        return cls._providers.get(name)

    @classmethod
    def list_providers(cls) -> list[str]:
        """List all registered provider names."""
        return list(cls._providers.keys())

    @classmethod
    def get_default(cls) -> LLMProvider | None:
        """Get the default provider (first registered)."""
        if cls._providers:
            return next(iter(cls._providers.values()))
        return None
