"""Ollama LLM provider implementation."""

import asyncio
import json
import logging
from collections.abc import AsyncIterator
from typing import Any, Optional

import httpx

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

    Connects to a local or remote Ollama instance via HTTP API.
    Default endpoint: http://localhost:11434
    """

    def __init__(self, base_url: str = "http://localhost:11434"):
        self.base_url = base_url.rstrip("/")
        self._client: Optional[httpx.AsyncClient] = None

    @property
    def name(self) -> str:
        return "ollama"

    def _get_client(self) -> httpx.AsyncClient:
        """Get or create HTTP client."""
        if self._client is None or self._client.is_closed:
            self._client = httpx.AsyncClient(
                base_url=self.base_url,
                timeout=httpx.Timeout(300.0),  # 5 minutes for long generations
            )
        return self._client

    async def stream_chat(
        self,
        messages: list[Message],
        model: str,
        options: Optional[ChatOptions] = None,
        cancel_event: Optional[asyncio.Event] = None,
    ) -> AsyncIterator[ChatChunk]:
        """Stream chat completion from Ollama.

        Uses Ollama's /api/chat endpoint with streaming enabled.
        Pass cancel_event to allow the caller to abort mid-stream.
        """
        client = self._get_client()
        opts = options or ChatOptions()

        # Convert messages to Ollama format
        ollama_messages = [
            {"role": msg.role, "content": msg.content}
            for msg in messages
        ]

        # Build options dict
        request_options: dict[str, Any] = {
            "temperature": opts.temperature,
        }
        if opts.max_tokens is not None:
            request_options["num_predict"] = opts.max_tokens
        if opts.top_p is not None:
            request_options["top_p"] = opts.top_p

        payload = {
            "model": model,
            "messages": ollama_messages,
            "stream": True,
            "options": request_options,
        }

        full_content = ""
        accumulated_thinking = ""

        try:
            async with client.stream(
                "POST",
                "/api/chat",
                json=payload,
            ) as response:
                response.raise_for_status()

                async for line in response.aiter_lines():
                    # Check for cancellation on every chunk.
                    if cancel_event and cancel_event.is_set():
                        await response.aclose()
                        yield ChatChunk(content="", is_finished=True, metadata={"cancelled": True})
                        return

                    if not line:
                        continue

                    try:
                        data = json.loads(line)
                    except json.JSONDecodeError:
                        logger.warning(f"Failed to parse Ollama response: {line}")
                        continue

                    # Check for completion
                    if data.get("done", False):
                        metadata: dict[str, Any] = {}
                        if "eval_count" in data:
                            metadata["tokens_generated"] = data["eval_count"]
                        if "prompt_eval_count" in data:
                            metadata["tokens_prompt"] = data["prompt_eval_count"]
                        if "total_duration" in data:
                            metadata["total_duration_ns"] = data["total_duration"]
                        if accumulated_thinking:
                            metadata["thinking"] = accumulated_thinking

                        yield ChatChunk(
                            content="",
                            is_finished=True,
                            metadata=metadata,
                        )
                        break

                    # Extract content and thinking from message
                    message = data.get("message", {})
                    content = message.get("content", "")
                    thinking = message.get("thinking", "")

                    if thinking:
                        accumulated_thinking += thinking
                        yield ChatChunk(content=thinking, is_finished=False, is_thinking=True)

                    if content:
                        full_content += content
                        yield ChatChunk(content=content, is_finished=False)

        except httpx.HTTPStatusError as e:
            logger.error(f"Ollama HTTP error: {e.response.status_code} - {e.response.text}")
            error_msg = f"Ollama error: {e.response.status_code}"
            try:
                error_data = e.response.json()
                if "error" in error_data:
                    error_msg = f"Ollama error: {error_data['error']}"
            except Exception:
                pass
            yield ChatChunk(
                content=error_msg,
                is_finished=True,
                metadata={"error": True, "status_code": e.response.status_code},
            )
        except httpx.RequestError as e:
            logger.error(f"Ollama request error: {e}")
            yield ChatChunk(
                content=f"Failed to connect to Ollama: {e}",
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
            response = await client.get("/api/tags")
            response.raise_for_status()
            data = response.json()

            models = []
            for model in data.get("models", []):
                model_name = model.get("name", "")
                model_details = model.get("details", {})

                # Build a human-readable name
                name_parts = model_name.split(":")
                display_name = name_parts[0].replace("-", " ").title()
                if len(name_parts) > 1 and name_parts[1] != "latest":
                    display_name += f" ({name_parts[1]})"

                # Extract context length if available
                context_length = None
                if "parameter_size" in model_details:
                    # Rough estimate based on model size
                    param_size = model_details["parameter_size"]
                    if "B" in param_size:
                        try:
                            size = float(param_size.replace("B", ""))
                            # Typical 7B models have 4K-8K context
                            # 70B models might have 128K
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

                models.append(ModelInfo(
                    id=model_name,
                    name=display_name,
                    description=f"{model_details.get('parameter_size', 'Unknown size')} {model_details.get('family', '')}",
                    context_length=context_length,
                ))

            return models

        except httpx.HTTPStatusError as e:
            logger.error(f"Failed to list Ollama models: {e.response.status_code}")
            return []
        except httpx.RequestError as e:
            logger.error(f"Failed to connect to Ollama: {e}")
            return []
        except Exception as e:
            logger.exception("Unexpected error listing Ollama models")
            return []

    async def health_check(self) -> bool:
        """Check if Ollama is accessible."""
        client = self._get_client()

        try:
            response = await client.get("/api/tags")
            return response.status_code == 200
        except Exception:
            return False

    async def close(self) -> None:
        """Close the HTTP client."""
        if self._client and not self._client.is_closed:
            await self._client.aclose()
            self._client = None
