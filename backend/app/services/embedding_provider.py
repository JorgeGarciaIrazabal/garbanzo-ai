"""Embedding provider abstraction.

Today we ship a single implementation (Ollama), but keeping the interface
lets us swap in a different backend without touching the knowledge base
service.
"""

from __future__ import annotations

import logging
from abc import ABC, abstractmethod

from ollama import AsyncClient, RequestError, ResponseError

from app.core.config import get_settings

logger = logging.getLogger(__name__)


class EmbeddingProvider(ABC):
    """Produces dense vector embeddings for a batch of input texts."""

    @property
    @abstractmethod
    def dim(self) -> int: ...

    @abstractmethod
    async def embed(self, texts: list[str]) -> list[list[float]]: ...


class OllamaEmbeddingProvider(EmbeddingProvider):
    """Embedding provider backed by Ollama's ``embed`` endpoint."""

    def __init__(
        self,
        base_url: str | None = None,
        model: str | None = None,
        dim: int | None = None,
    ):
        settings = get_settings()
        self._base_url = (base_url or settings.ollama_base_url).rstrip("/")
        self._model = model or settings.embedding_model
        self._dim = dim or settings.embedding_dim
        self._client: AsyncClient | None = None

    @property
    def dim(self) -> int:
        return self._dim

    @property
    def model(self) -> str:
        return self._model

    def _get_client(self) -> AsyncClient:
        if self._client is None:
            self._client = AsyncClient(host=self._base_url, timeout=120.0)
        return self._client

    async def embed(self, texts: list[str]) -> list[list[float]]:
        if not texts:
            return []
        client = self._get_client()
        try:
            response = await client.embed(model=self._model, input=texts)
        except (ResponseError, RequestError):
            logger.exception("Ollama embedding request failed")
            raise
        embeddings = (
            response.get("embeddings")
            if isinstance(response, dict)
            else getattr(response, "embeddings", None)
        )
        if not embeddings:
            raise RuntimeError("Ollama returned no embeddings")
        return [list(map(float, e)) for e in embeddings]


_default_provider: EmbeddingProvider | None = None


def get_embedding_provider() -> EmbeddingProvider:
    global _default_provider
    if _default_provider is None:
        _default_provider = OllamaEmbeddingProvider()
    return _default_provider


def set_embedding_provider(provider: EmbeddingProvider | None) -> None:
    """Override the process-wide embedding provider (used by tests)."""
    global _default_provider
    _default_provider = provider
