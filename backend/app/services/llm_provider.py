"""Abstract base class for LLM providers."""

import asyncio
from abc import ABC, abstractmethod
from collections.abc import AsyncIterator
from dataclasses import dataclass
from typing import Any, Optional

from app.schemas.chat import ChatOptions


@dataclass
class Message:
    """A message for the LLM."""

    role: str  # "user", "assistant", "system"
    content: str
    images: list[str] | None = None  # base64-encoded images for multimodal models


@dataclass
class ModelInfo:
    """Information about an available model."""

    id: str
    name: str
    description: str | None = None
    context_length: int | None = None


@dataclass
class ChatChunk:
    """A chunk of streaming response."""

    content: str
    is_finished: bool = False
    is_thinking: bool = False
    metadata: dict[str, Any] | None = None


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
