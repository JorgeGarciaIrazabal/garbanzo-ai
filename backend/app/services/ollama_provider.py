"""Ollama LLM provider implementation using the official ollama-py SDK."""

import asyncio
import contextlib
import logging
from collections.abc import AsyncIterator
from typing import Any

import httpx
from ollama import AsyncClient, RequestError, ResponseError

from app.services.llm_provider import (
    ChatChunk,
    ChatOptions,
    LLMProvider,
    Message,
    ModelInfo,
)

logger = logging.getLogger(__name__)

# Transient failures worth retrying: the SDK's request-level error plus the
# underlying transport errors. ResponseError (an HTTP status from Ollama,
# e.g. 400 unknown model) is NOT retryable.
_TRANSIENT_ERRORS = (RequestError, httpx.TransportError, ConnectionError)
_CONNECT_ATTEMPTS = 3
_RETRY_BACKOFF_SECONDS = 0.75

# Per-chunk timeouts. The first chunk may wait on a cold model load (large
# models take minutes), so it gets a much longer budget than steady-state
# token generation.
FIRST_CHUNK_TIMEOUT = 300.0
CHUNK_TIMEOUT = 120.0


class OllamaProvider(LLMProvider):
    """Ollama LLM provider.

    Connects to a local or remote Ollama instance via the official SDK.
    Default endpoint: http://localhost:11434
    """

    def __init__(self, base_url: str = "http://localhost:11434"):
        self.base_url = base_url.rstrip("/")
        self._client: AsyncClient | None = None
        # model name → (context_length, capabilities). Model metadata is
        # immutable for a given tag, so entries never expire.
        self._model_meta: dict[str, tuple[int | None, list[str]]] = {}

    @property
    def name(self) -> str:
        return "ollama"

    def _get_client(self) -> AsyncClient:
        """Get or create the Ollama async client."""
        if self._client is None:
            self._client = AsyncClient(host=self.base_url, timeout=300.0)
        return self._client

    async def _get_model_meta(self, model: str) -> tuple[int | None, list[str]]:
        """Return ``(context_length, capabilities)`` from ``ollama show``.

        modelinfo keys are architecture-prefixed (e.g.
        ``llama.context_length``), so we match on the suffix. Only
        successful lookups are cached — caching a failure (say, Ollama
        briefly down at startup) would permanently disable thinking and
        capability detection for that model until restart, while retrying
        costs one cheap local call.
        """
        cached = self._model_meta.get(model)
        if cached is not None:
            return cached

        try:
            response = await self._get_client().show(model)
        except Exception as e:
            logger.warning("Failed to fetch model metadata for %s: %s", model, e)
            return (None, [])

        context_length: int | None = None
        for key, value in (response.modelinfo or {}).items():
            if key.endswith(".context_length"):
                with contextlib.suppress(TypeError, ValueError):
                    context_length = int(value)
                break
        capabilities = list(response.capabilities or [])

        meta = (context_length, capabilities)
        self._model_meta[model] = meta
        return meta

    async def get_model_context_length(self, model: str) -> int | None:
        """Return the model's maximum context length, if Ollama reports it."""
        context_length, _ = await self._get_model_meta(model)
        return context_length

    async def _stream_with_retry(
        self, client: AsyncClient, chat_kwargs: dict[str, Any]
    ) -> AsyncIterator[Any]:
        """Open the chat stream and yield its chunks with resilience.

        - Establishing the stream (request + first chunk) is retried with
          backoff on transient errors — safe because no tokens have been
          delivered yet.
        - Every chunk is bounded by a timeout so a wedged stream surfaces
          as an error instead of hanging the request forever.
        """
        iterator = None
        first = None
        for attempt in range(1, _CONNECT_ATTEMPTS + 1):
            try:
                stream = await client.chat(**chat_kwargs)
                iterator = stream.__aiter__()
                first = await asyncio.wait_for(iterator.__anext__(), timeout=FIRST_CHUNK_TIMEOUT)
                break
            except StopAsyncIteration:
                return
            except _TRANSIENT_ERRORS as e:
                if attempt == _CONNECT_ATTEMPTS:
                    raise
                delay = _RETRY_BACKOFF_SECONDS * (2 ** (attempt - 1))
                logger.warning(
                    "Ollama connection failed (attempt %d/%d): %s — retrying in %.1fs",
                    attempt,
                    _CONNECT_ATTEMPTS,
                    e,
                    delay,
                )
                await asyncio.sleep(delay)

        yield first
        assert iterator is not None
        while True:
            try:
                chunk = await asyncio.wait_for(iterator.__anext__(), timeout=CHUNK_TIMEOUT)
            except StopAsyncIteration:
                return
            yield chunk

    async def stream_chat(
        self,
        messages: list[Message],
        model: str,
        options: ChatOptions | None = None,
        cancel_event: asyncio.Event | None = None,
        tools: list[dict[str, Any]] | None = None,
    ) -> AsyncIterator[ChatChunk]:
        """Stream chat completion from Ollama using the SDK."""
        import uuid

        client = self._get_client()
        opts = options or ChatOptions()

        # Convert messages to Ollama format
        ollama_messages: list[dict[str, Any]] = []
        for msg in messages:
            entry: dict[str, Any] = {"role": msg.role, "content": msg.content}
            if msg.images:
                entry["images"] = msg.images
            if msg.tool_calls:
                # Ollama expects {function: {name, arguments}} structure.
                entry["tool_calls"] = [
                    {
                        "function": {
                            "name": tc.get("name", ""),
                            "arguments": tc.get("arguments") or {},
                        }
                    }
                    for tc in msg.tool_calls
                ]
            ollama_messages.append(entry)

        # Build options dict
        request_options: dict[str, Any] = {
            "temperature": opts.temperature,
        }
        if opts.max_tokens is not None:
            request_options["num_predict"] = opts.max_tokens
        if opts.top_p is not None:
            request_options["top_p"] = opts.top_p
        if opts.num_ctx is not None:
            request_options["num_ctx"] = opts.num_ctx

        accumulated_thinking = ""
        accumulated_tool_calls: list[dict[str, Any]] = []

        try:
            chat_kwargs: dict[str, Any] = {
                "model": model,
                "messages": ollama_messages,
                "stream": True,
                "options": request_options,
            }
            # Ask Ollama to surface the model's reasoning as a separate
            # `thinking` field rather than burying it inside the final
            # output. For reasoning models (qwen3, deepseek-r1, …) this
            # is what lets the UI render thinking tokens incrementally
            # during the otherwise-silent gap before the answer or tool
            # call. Only set when the model advertises the capability —
            # current Ollama rejects think=True for non-thinking models
            # with a 400 instead of ignoring it.
            _, capabilities = await self._get_model_meta(model)
            if "thinking" in capabilities:
                chat_kwargs["think"] = True
            if tools:
                chat_kwargs["tools"] = tools

            async for chunk in self._stream_with_retry(client, chat_kwargs):
                # Check for cancellation
                if cancel_event and cancel_event.is_set():
                    yield ChatChunk(content="", is_finished=True, metadata={"cancelled": True})
                    return

                # Extract the message payload from intermediate chunks.
                message = chunk.get("message")
                if message is not None:
                    content = message.get("content", "") or ""
                    thinking = message.get("thinking", "") or ""
                    tool_calls = message.get("tool_calls") or []

                    if thinking:
                        accumulated_thinking += thinking
                        yield ChatChunk(content=thinking, is_finished=False, is_thinking=True)

                    if content:
                        yield ChatChunk(content=content, is_finished=False)

                    if tool_calls:
                        normalized: list[dict[str, Any]] = []
                        for tc in tool_calls:
                            func = (
                                tc.get("function")
                                if isinstance(tc, dict)
                                else getattr(tc, "function", None)
                            )
                            name = ""
                            arguments: Any = {}
                            if func is not None:
                                if isinstance(func, dict):
                                    name = func.get("name", "") or ""
                                    arguments = func.get("arguments") or {}
                                else:
                                    name = getattr(func, "name", "") or ""
                                    arguments = getattr(func, "arguments", None) or {}
                            normalized.append(
                                {
                                    "id": str(uuid.uuid4()),
                                    "name": name,
                                    "arguments": arguments,
                                }
                            )
                        accumulated_tool_calls.extend(normalized)

                # Final chunk with metadata
                if chunk.get("done", False):
                    # Emit a tool_call chunk BEFORE the done chunk.
                    if accumulated_tool_calls:
                        yield ChatChunk(
                            content="",
                            is_finished=False,
                            tool_calls=accumulated_tool_calls,
                        )

                    metadata: dict[str, Any] = {}
                    if chunk.eval_count is not None:
                        metadata["tokens_generated"] = chunk.eval_count
                    if chunk.prompt_eval_count is not None:
                        metadata["tokens_prompt"] = chunk.prompt_eval_count
                    if chunk.total_duration is not None:
                        metadata["total_duration_ns"] = chunk.total_duration
                    if accumulated_thinking:
                        metadata["thinking"] = accumulated_thinking
                    if accumulated_tool_calls:
                        metadata["has_tool_calls"] = True

                    yield ChatChunk(content="", is_finished=True, metadata=metadata)
                    break

        except ResponseError as e:
            logger.error("Ollama response error: %s", e)
            yield ChatChunk(
                content=f"Ollama error: {e.error}",
                is_finished=True,
                metadata={"error": True, "status_code": e.status_code},
            )
        except TimeoutError:
            logger.error("Ollama stream timed out for model %s", model)
            yield ChatChunk(
                content="Ollama stopped responding mid-stream (timeout).",
                is_finished=True,
                metadata={"error": True, "error_type": "stream_timeout"},
            )
        except _TRANSIENT_ERRORS as e:
            logger.error("Ollama request error after retries: %s", e)
            detail = getattr(e, "error", None) or str(e)
            yield ChatChunk(
                content=f"Failed to connect to Ollama: {detail}",
                is_finished=True,
                metadata={"error": True},
            )
        except Exception as e:
            logger.exception("Unexpected error in Ollama streaming")
            yield ChatChunk(
                content=f"Unexpected error: {e}",
                is_finished=True,
                metadata={"error": True},
            )

    async def list_models(self) -> list[ModelInfo]:
        """List available models from Ollama."""
        client = self._get_client()

        try:
            response = await client.list()

            model_names = [m.model or "" for m in response.models]
            # Fetch real metadata (context length + capabilities) for every
            # model concurrently; results are cached so this is only slow on
            # the first listing after startup.
            metas = await asyncio.gather(*(self._get_model_meta(name) for name in model_names))

            models = []
            for m, (real_context, capabilities) in zip(response.models, metas, strict=True):
                model_name = m.model or ""
                details = m.details

                # Build a human-readable name
                name_parts = model_name.split(":")
                display_name = name_parts[0].replace("-", " ").title()
                if len(name_parts) > 1 and name_parts[1] != "latest":
                    display_name += f" ({name_parts[1]})"

                context_length = real_context
                if context_length is None:
                    # Fallback estimate from parameter size when `show`
                    # metadata is unavailable (e.g. remote/cloud models).
                    if ":cloud" in model_name.lower():
                        context_length = 100000
                    else:
                        param_size = details.parameter_size if details else None
                        if param_size and "B" in param_size:
                            try:
                                size = float(param_size.replace("B", ""))
                                if size <= 3:
                                    context_length = 4096
                                elif size <= 8:
                                    context_length = 8192
                                elif size <= 20:
                                    context_length = 32768
                                else:
                                    context_length = 131072
                            except ValueError:
                                pass

                param_size = details.parameter_size if details else None
                description_parts = [
                    param_size or "Unknown size",
                    details.family if details else "",
                ]
                description = " ".join(p for p in description_parts if p)

                models.append(
                    ModelInfo(
                        id=model_name,
                        name=display_name,
                        description=description,
                        context_length=context_length,
                        supports_tools="tools" in capabilities if capabilities else None,
                        supports_vision="vision" in capabilities if capabilities else None,
                        supports_thinking="thinking" in capabilities if capabilities else None,
                    )
                )

            return models

        except (ResponseError, RequestError) as e:
            logger.error("Failed to list Ollama models: %s", e)
            return []
        except Exception:
            logger.exception("Unexpected error listing Ollama models")
            return []

    async def health_check(self) -> bool:
        """Check if Ollama is accessible."""
        client = self._get_client()

        try:
            await client.list()
            return True
        except Exception:
            return False

    async def chat(
        self,
        messages: list[Message],
        model: str,
        options: ChatOptions | None = None,
        tools: list[dict[str, Any]] | None = None,
    ) -> str:
        """Non-streaming chat completion from Ollama."""
        client = self._get_client()
        opts = options or ChatOptions()

        # Convert messages to Ollama format
        ollama_messages: list[dict[str, Any]] = []
        for msg in messages:
            entry: dict[str, Any] = {"role": msg.role, "content": msg.content}
            if msg.images:
                entry["images"] = msg.images
            if msg.tool_calls:
                entry["tool_calls"] = [
                    {
                        "function": {
                            "name": tc.get("name", ""),
                            "arguments": tc.get("arguments") or {},
                        }
                    }
                    for tc in msg.tool_calls
                ]
            ollama_messages.append(entry)

        # Build options dict
        request_options: dict[str, Any] = {
            "temperature": opts.temperature,
        }
        if opts.max_tokens is not None:
            request_options["num_predict"] = opts.max_tokens
        if opts.top_p is not None:
            request_options["top_p"] = opts.top_p
        if opts.num_ctx is not None:
            request_options["num_ctx"] = opts.num_ctx

        try:
            chat_kwargs: dict[str, Any] = {
                "model": model,
                "messages": ollama_messages,
                "stream": False,
                "options": request_options,
            }
            if tools:
                chat_kwargs["tools"] = tools
            if opts.response_format is not None:
                # Ollama accepts either the string "json" or a JSON Schema
                # dict; both pass through unchanged.
                chat_kwargs["format"] = opts.response_format
            response = None
            for attempt in range(1, _CONNECT_ATTEMPTS + 1):
                try:
                    response = await client.chat(**chat_kwargs)
                    break
                except _TRANSIENT_ERRORS as e:
                    if attempt == _CONNECT_ATTEMPTS:
                        raise
                    delay = _RETRY_BACKOFF_SECONDS * (2 ** (attempt - 1))
                    logger.warning(
                        "Ollama chat failed (attempt %d/%d): %s — retrying in %.1fs",
                        attempt,
                        _CONNECT_ATTEMPTS,
                        e,
                        delay,
                    )
                    await asyncio.sleep(delay)
            return response.message.content or ""
        except (ResponseError, RequestError) as e:
            logger.error("Ollama chat error: %s", e)
            raise
        except Exception:
            logger.exception("Unexpected error in Ollama chat")
            raise

    async def close(self) -> None:
        """Close the underlying HTTP client."""
        if self._client is not None:
            # The AsyncClient wraps an httpx client internally
            if hasattr(self._client, "_client") and self._client._client is not None:
                await self._client._client.aclose()
            self._client = None
