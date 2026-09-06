"""Ollama LLM provider using ollama-py SDK."""

import asyncio
import contextlib
import logging
import traceback
from collections.abc import AsyncIterator
from typing import Any

import httpx
from ollama import AsyncClient, RequestError, ResponseError

from app.services.llm_provider import ChatChunk, ChatOptions, LLMProvider, Message, ModelInfo

logger = logging.getLogger(__name__)

_TRANSIENT_ERRORS = (RequestError, httpx.TransportError, ConnectionError)
_CONNECT_ATTEMPTS = 3
_RETRY_BACKOFF_SECONDS = 0.75

FIRST_CHUNK_TIMEOUT = 300.0
CHUNK_TIMEOUT = 120.0

_RETIRED_MODEL_ALIASES = {"deepseek-v4-flash:0731-cloud", "deepseek-v4-pro:0813-cloud"}
_UNSUPPORTED_IMAGE_MESSAGE = (
    "This model cannot process image attachments. Switch to a model marked Vision and try again."
)


def _is_server_error(e: Exception) -> bool:
    return isinstance(e, ResponseError) and (e.status_code or 0) >= 500


def _is_glm_model(model: str) -> bool:
    """Check if model belongs to the GLM family.

    GLM models (e.g. glm-5.2, glm-5.3) do not support disabling thinking via
    think: False in Ollama — doing so disables Ollama's thinking parser, causing
    the model's raw chain-of-thought and </think> tag to leak into message content.
    """
    return "glm" in model.lower()


def _resolve_think_kwarg(
    model: str, requested_level: str | None, capabilities: list[str]
) -> tuple[Any, bool]:
    """Map a requested ThinkingLevel to Ollama's `think` argument and suppression flag.

    Returns (think_kwarg, suppress_thinking):
      - If model does not support thinking: (None, False)
      - If requested_level is 'off':
          * GLM models: ('low', True) -> run minimal reasoning without breaking Ollama's
            thinking parser, but suppress thinking chunks so user sees zero thinking.
          * other models: (False, False) -> disable thinking natively.
      - If requested_level is in ('low', 'medium', 'high'): (requested_level, False)
      - If requested_level is None (auto/default): (True, False)
    """
    if "thinking" not in capabilities:
        return (None, False)
    if requested_level == "off":
        if _is_glm_model(model):
            return ("low", True)
        return (False, False)
    if requested_level in ("low", "medium", "high"):
        return (requested_level, False)
    return (True, False)


def _unsupported_image_chunk(status_code: int = 400) -> ChatChunk:
    return ChatChunk(
        content=_UNSUPPORTED_IMAGE_MESSAGE,
        is_finished=True,
        metadata={
            "error": True,
            "error_type": "unsupported_image_input",
            "status_code": status_code,
            "auto_report": False,
        },
    )


def _is_unsupported_image_error(error: ResponseError) -> bool:
    return "does not support image input" in str(error.error).lower()


def _retry_delay(attempt: int) -> float:
    return _RETRY_BACKOFF_SECONDS * (2 ** (attempt - 1))


def _to_ollama_messages(messages: list[Message]) -> list[dict[str, Any]]:
    out: list[dict[str, Any]] = []
    for msg in messages:
        entry: dict[str, Any] = {"role": msg.role, "content": msg.content}
        if msg.images:
            entry["images"] = msg.images
        if msg.tool_calls:
            entry["tool_calls"] = [
                {"function": {"name": tc.get("name", ""), "arguments": tc.get("arguments") or {}}}
                for tc in msg.tool_calls
            ]
        out.append(entry)
    return out


def _build_options(opts: ChatOptions) -> dict[str, Any]:
    o: dict[str, Any] = {"temperature": opts.temperature}
    if opts.max_tokens is not None:
        o["num_predict"] = opts.max_tokens
    if opts.top_p is not None:
        o["top_p"] = opts.top_p
    if opts.num_ctx is not None:
        o["num_ctx"] = opts.num_ctx
    return o


def _fallback_context_length(model_name: str, param_size: str | None) -> int | None:
    if ":cloud" in model_name.lower():
        return 100000
    if not param_size or "B" not in param_size:
        return None
    try:
        size = float(param_size.replace("B", ""))
    except ValueError:
        return None
    for limit, ctx in [(3, 4096), (8, 8192), (20, 32768)]:
        if size <= limit:
            return ctx
    return 131072


class OllamaProvider(LLMProvider):
    """Ollama provider (local or remote). Default http://localhost:11434"""

    def __init__(self, base_url: str = "http://localhost:11434"):
        self.base_url = base_url.rstrip("/")
        self._client: AsyncClient | None = None
        self._model_meta: dict[str, tuple[int | None, list[str]]] = {}

    @property
    def name(self) -> str:
        return "ollama"

    @property
    def supports_structured_output(self) -> bool:
        return True

    def _get_client(self) -> AsyncClient:
        if self._client is None:
            self._client = AsyncClient(host=self.base_url, timeout=300.0)
        return self._client

    async def _get_model_meta(self, model: str) -> tuple[int | None, list[str]]:
        """Return (context_length, capabilities) from `ollama show`; cached successes only."""
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
        context_length, _ = await self._get_model_meta(model)
        return context_length

    async def _stream_with_retry(
        self, client: AsyncClient, chat_kwargs: dict[str, Any]
    ) -> AsyncIterator[Any]:
        """Retry stream establishment on transient/5xx before any token delivered."""
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
            except ResponseError as e:
                if not _is_server_error(e) or attempt == _CONNECT_ATTEMPTS:
                    raise
                delay = _retry_delay(attempt)
                logger.warning(
                    "Ollama server error %d (attempt %d/%d): %s — retrying in %.1fs",
                    e.status_code,
                    attempt,
                    _CONNECT_ATTEMPTS,
                    e,
                    delay,
                )
                await asyncio.sleep(delay)
            except _TRANSIENT_ERRORS as e:
                if attempt == _CONNECT_ATTEMPTS:
                    raise
                delay = _retry_delay(attempt)
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
        import uuid

        client = self._get_client()
        opts = options or ChatOptions()
        ollama_messages = _to_ollama_messages(messages)
        request_options = _build_options(opts)
        accumulated_thinking = ""
        accumulated_tool_calls: list[dict[str, Any]] = []
        try:
            chat_kwargs: dict[str, Any] = {
                "model": model,
                "messages": ollama_messages,
                "stream": True,
                "options": request_options,
            }
            _, capabilities = await self._get_model_meta(model)
            if any(m.images for m in messages) and capabilities and "vision" not in capabilities:
                yield _unsupported_image_chunk()
                return
            think_kwarg, suppress_thinking = _resolve_think_kwarg(model, opts.think, capabilities)
            if think_kwarg is not None:
                chat_kwargs["think"] = think_kwarg
            if tools:
                chat_kwargs["tools"] = tools
            in_think_tag = False
            async for chunk in self._stream_with_retry(client, chat_kwargs):
                if cancel_event and cancel_event.is_set():
                    yield ChatChunk(content="", is_finished=True, metadata={"cancelled": True})
                    return
                message = chunk.get("message")
                if message is not None:
                    content = message.get("content", "") or ""
                    thinking = message.get("thinking", "") or ""
                    tool_calls = message.get("tool_calls") or []
                    if thinking:
                        accumulated_thinking += thinking
                        if not suppress_thinking:
                            yield ChatChunk(content=thinking, is_finished=False, is_thinking=True)
                    if content:
                        if in_think_tag:
                            if "</think>" in content:
                                think_part, answer_part = content.split("</think>", 1)
                                in_think_tag = False
                                clean_think = think_part.replace("<think>", "").strip()
                                if clean_think:
                                    accumulated_thinking += clean_think
                                    if not suppress_thinking:
                                        yield ChatChunk(
                                            content=clean_think, is_finished=False, is_thinking=True
                                        )
                                content = answer_part
                            else:
                                clean_think = content.replace("<think>", "")
                                if clean_think:
                                    accumulated_thinking += clean_think
                                    if not suppress_thinking:
                                        yield ChatChunk(
                                            content=clean_think, is_finished=False, is_thinking=True
                                        )
                                content = ""
                        elif "<think>" in content:
                            if "</think>" in content:
                                before_think, rest = content.split("<think>", 1)
                                think_part, answer_part = rest.split("</think>", 1)
                                if before_think:
                                    yield ChatChunk(content=before_think, is_finished=False)
                                clean_think = think_part.strip()
                                if clean_think:
                                    accumulated_thinking += clean_think
                                    if not suppress_thinking:
                                        yield ChatChunk(
                                            content=clean_think, is_finished=False, is_thinking=True
                                        )
                                content = answer_part
                            else:
                                before_think, think_part = content.split("<think>", 1)
                                in_think_tag = True
                                if before_think:
                                    yield ChatChunk(content=before_think, is_finished=False)
                                clean_think = think_part.strip()
                                if clean_think:
                                    accumulated_thinking += clean_think
                                    if not suppress_thinking:
                                        yield ChatChunk(
                                            content=clean_think, is_finished=False, is_thinking=True
                                        )
                                content = ""
                        elif "</think>" in content:
                            think_part, answer_part = content.split("</think>", 1)
                            clean_think = think_part.strip()
                            if clean_think:
                                accumulated_thinking += clean_think
                                if not suppress_thinking:
                                    yield ChatChunk(
                                        content=clean_think, is_finished=False, is_thinking=True
                                    )
                            content = answer_part

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
                                {"id": str(uuid.uuid4()), "name": name, "arguments": arguments}
                            )
                        accumulated_tool_calls.extend(normalized)
                if chunk.get("done", False):
                    if accumulated_tool_calls:
                        yield ChatChunk(
                            content="", is_finished=False, tool_calls=accumulated_tool_calls
                        )
                    metadata: dict[str, Any] = {}
                    if chunk.eval_count is not None:
                        metadata["tokens_generated"] = chunk.eval_count
                    if chunk.prompt_eval_count is not None:
                        metadata["tokens_prompt"] = chunk.prompt_eval_count
                    if chunk.total_duration is not None:
                        metadata["total_duration_ns"] = chunk.total_duration
                    if accumulated_thinking and not suppress_thinking:
                        metadata["thinking"] = accumulated_thinking
                    if accumulated_tool_calls:
                        metadata["has_tool_calls"] = True
                    yield ChatChunk(content="", is_finished=True, metadata=metadata)
                    break
        except ResponseError as e:
            logger.error("Ollama response error: %s", e)
            if _is_unsupported_image_error(e):
                yield _unsupported_image_chunk(e.status_code)
                return
            content = (
                "The model backend failed repeatedly. Please try again in a minute, or switch to a different model."
                if _is_server_error(e)
                else f"Ollama error: {e.error}"
            )
            yield ChatChunk(
                content=content,
                is_finished=True,
                metadata={
                    "error": True,
                    "status_code": e.status_code,
                    "model": model,
                    "message_count": len(ollama_messages),
                    "prompt_chars": sum(len(m["content"]) for m in ollama_messages),
                    "stack_trace": traceback.format_exc(),
                },
            )
        except TimeoutError:
            logger.error("Ollama stream timed out for model %s", model)
            yield ChatChunk(
                content="Ollama stopped responding mid-stream (timeout).",
                is_finished=True,
                metadata={
                    "error": True,
                    "error_type": "stream_timeout",
                    "stack_trace": traceback.format_exc(),
                },
            )
        except _TRANSIENT_ERRORS as e:
            logger.error("Ollama request error after retries: %s", e)
            detail = getattr(e, "error", None) or str(e)
            yield ChatChunk(
                content=f"Failed to connect to Ollama: {detail}",
                is_finished=True,
                metadata={"error": True, "stack_trace": traceback.format_exc()},
            )
        except Exception as e:
            logger.exception("Unexpected error in Ollama streaming")
            yield ChatChunk(
                content=f"Unexpected error: {e}",
                is_finished=True,
                metadata={"error": True, "stack_trace": traceback.format_exc()},
            )

    async def list_models(self) -> list[ModelInfo]:
        client = self._get_client()
        try:
            response = await client.list()
            visible_models = [
                m for m in response.models if (m.model or "") not in _RETIRED_MODEL_ALIASES
            ]
            model_names = [m.model or "" for m in visible_models]
            metas = await asyncio.gather(*(self._get_model_meta(name) for name in model_names))
            models = []
            for m, (real_context, capabilities) in zip(visible_models, metas, strict=True):
                model_name = m.model or ""
                details = m.details
                display_name = model_name.split(":")[0].replace("-", " ").title()
                if ":" in model_name and model_name.split(":")[1] not in ("latest", "cloud"):
                    display_name += f" ({model_name.split(':')[1]})"
                context_length = (
                    real_context
                    if real_context is not None
                    else _fallback_context_length(
                        model_name, details.parameter_size if details else None
                    )
                )
                param_size = details.parameter_size if details else None
                description = " ".join(
                    p
                    for p in [param_size or "Unknown size", details.family if details else ""]
                    if p
                )
                models.append(
                    ModelInfo(
                        id=model_name,
                        name=display_name,
                        description=description,
                        context_length=context_length,
                        supports_tools="tools" in capabilities if capabilities else None,
                        supports_vision="vision" in capabilities if capabilities else None,
                        supports_thinking="thinking" in capabilities if capabilities else None,
                        thinking_levels=(
                            ["off", "low", "medium", "high"] if "thinking" in capabilities else None
                        ),
                        default_thinking_level=("high" if "thinking" in capabilities else None),
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
        try:
            await self._get_client().list()
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
        client = self._get_client()
        opts = options or ChatOptions()
        ollama_messages = _to_ollama_messages(messages)
        request_options = _build_options(opts)
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
                chat_kwargs["format"] = opts.response_format
            _, capabilities = await self._get_model_meta(model)
            think_kwarg, _ = _resolve_think_kwarg(model, opts.think, capabilities)
            if think_kwarg is not None:
                chat_kwargs["think"] = think_kwarg
            response = None
            for attempt in range(1, _CONNECT_ATTEMPTS + 1):
                try:
                    response = await client.chat(**chat_kwargs)
                    break
                except _TRANSIENT_ERRORS as e:
                    if attempt == _CONNECT_ATTEMPTS:
                        raise
                    delay = _retry_delay(attempt)
                    logger.warning(
                        "Ollama chat failed (attempt %d/%d): %s — retrying in %.1fs",
                        attempt,
                        _CONNECT_ATTEMPTS,
                        e,
                        delay,
                    )
                    await asyncio.sleep(delay)
            content = response.message.content or ""
            if "</think>" in content:
                content = content.split("</think>", 1)[1].strip()
            return content
        except (ResponseError, RequestError) as e:
            logger.error("Ollama chat error: %s", e)
            raise
        except Exception:
            logger.exception("Unexpected error in Ollama chat")
            raise

    async def close(self) -> None:
        if self._client is not None:
            if hasattr(self._client, "_client") and self._client._client is not None:
                await self._client._client.aclose()
            self._client = None
