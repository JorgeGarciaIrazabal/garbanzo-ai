"""Ollama LLM provider implementation using the official ollama-py SDK."""

import asyncio
import logging
from collections.abc import AsyncIterator
from typing import Any

from ollama import AsyncClient, RequestError, ResponseError

from app.services.llm_provider import (
    ChatChunk,
    ChatOptions,
    LLMProvider,
    Message,
    ModelInfo,
)

logger = logging.getLogger(__name__)


class OllamaProvider(LLMProvider):
    """Ollama LLM provider.

    Connects to a local or remote Ollama instance via the official SDK.
    Default endpoint: http://localhost:11434
    """

    def __init__(self, base_url: str = "http://localhost:11434"):
        self.base_url = base_url.rstrip("/")
        self._client: AsyncClient | None = None

    @property
    def name(self) -> str:
        return "ollama"

    def _get_client(self) -> AsyncClient:
        """Get or create the Ollama async client."""
        if self._client is None:
            self._client = AsyncClient(host=self.base_url, timeout=300.0)
        return self._client

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
            ollama_messages.append(entry)

        # Build options dict
        request_options: dict[str, Any] = {
            "temperature": opts.temperature,
        }
        if opts.max_tokens is not None:
            request_options["num_predict"] = opts.max_tokens
        if opts.top_p is not None:
            request_options["top_p"] = opts.top_p

        accumulated_thinking = ""
        accumulated_tool_calls: list[dict[str, Any]] = []

        try:
            chat_kwargs: dict[str, Any] = {
                "model": model,
                "messages": ollama_messages,
                "stream": True,
                "options": request_options,
            }
            if tools:
                chat_kwargs["tools"] = tools
            stream = await client.chat(**chat_kwargs)

            async for chunk in stream:
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
        except RequestError as e:
            logger.error("Ollama request error: %s", e)
            yield ChatChunk(
                content=f"Failed to connect to Ollama: {e.error}",
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

            models = []
            for m in response.models:
                model_name = m.model or ""
                details = m.details

                # Build a human-readable name
                name_parts = model_name.split(":")
                display_name = name_parts[0].replace("-", " ").title()
                if len(name_parts) > 1 and name_parts[1] != "latest":
                    display_name += f" ({name_parts[1]})"

                # Extract context length estimate based on parameter size
                context_length = None
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
            ollama_messages.append(entry)

        # Build options dict
        request_options: dict[str, Any] = {
            "temperature": opts.temperature,
        }
        if opts.max_tokens is not None:
            request_options["num_predict"] = opts.max_tokens
        if opts.top_p is not None:
            request_options["top_p"] = opts.top_p

        try:
            chat_kwargs: dict[str, Any] = {
                "model": model,
                "messages": ollama_messages,
                "stream": False,
                "options": request_options,
            }
            if tools:
                chat_kwargs["tools"] = tools
            response = await client.chat(**chat_kwargs)
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
