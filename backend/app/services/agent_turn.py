"""Transport-agnostic single-agent turn engine.

Runs one assistant turn — provider streaming, thinking accumulation, and
optional tool-call iterations — and yields ``ChatChunk`` events for the
caller to adapt to its wire format (SSE for 1:1 chat, WebSocket broadcast
for rooms). Persistence is delegated to a ``TurnSink`` so each mode keeps
its own storage schema (``Message`` vs ``RoomMessage``).
"""

from __future__ import annotations

import asyncio
import json
import logging
from collections.abc import AsyncIterator, Awaitable, Callable
from dataclasses import dataclass
from typing import Any, Protocol

from app.core.config import get_settings
from app.schemas.chat import ChatOptions
from app.services.llm_provider import (
    ChatChunk,
    LLMProvider,
    resolve_context_length,
)
from app.services.llm_provider import Message as LLMMessage

logger = logging.getLogger(__name__)

DEFAULT_MAX_TOOL_ITERATIONS = 5

ToolExecutor = Callable[[dict[str, Any]], Awaitable[dict[str, Any]]]


def stringify_tool_result(result: Any) -> str:
    """Coerce a tool-call result dict into a string suitable for persistence."""
    try:
        return json.dumps(result, default=str)
    except Exception:
        return str(result)


def truncate_tool_result(text: str, max_chars: int) -> str:
    """Cap a stringified tool result with an explicit truncation marker.

    Applied before persisting and before feeding the result back to the
    model — a tool returning megabytes must not blow the context window.
    """
    if max_chars <= 0 or len(text) <= max_chars:
        return text
    dropped = len(text) - max_chars
    return f"{text[:max_chars]}... [truncated {dropped} chars]"


class TurnSink(Protocol):
    """Storage adapter for one agent turn.

    ``persist_*`` methods stage rows on the caller's session (add + flush);
    ``commit`` / ``rollback`` control the transaction. The engine calls
    ``commit`` at the end of each tool iteration and on clean completion,
    mirroring the transaction boundaries the 1:1 chat flow always had.
    """

    async def persist_assistant(self, content: str, meta: dict | None) -> None: ...

    async def persist_tool_call(self, tool_calls: list[dict]) -> None: ...

    async def persist_tool_result(self, content: str, meta: dict) -> None: ...

    async def commit(self) -> None: ...

    async def rollback(self) -> None: ...


@dataclass
class TurnResult:
    """Out-of-band summary of a turn, populated as the generator runs.

    Async generators can't return values, so callers that need the final
    response after streaming (e.g. title generation, mention recursion)
    pass one in and read it once iteration completes.
    """

    content: str = ""  # last persisted assistant content
    thinking: str = ""  # combined thinking attached to that message
    metadata: dict | None = None
    completed: bool = False  # reached the clean no-tool-call finish
    error: bool = False


async def run_agent_turn(
    *,
    provider: LLMProvider,
    model: str,
    llm_messages: list[LLMMessage],
    sink: TurnSink,
    options: ChatOptions | None = None,
    tools: list[dict] | None = None,
    execute_tool: ToolExecutor | None = None,
    cancel_event: asyncio.Event | None = None,
    max_tool_iterations: int = DEFAULT_MAX_TOOL_ITERATIONS,
    extra_finish_metadata: dict | None = None,
    persist_partial_on_error: bool = False,
    result: TurnResult | None = None,
) -> AsyncIterator[ChatChunk]:
    """Stream one assistant turn, persisting through ``sink``.

    ``llm_messages`` is mutated in place as tool iterations extend the
    exchange. ``extra_finish_metadata`` entries are merged (setdefault)
    into every finish chunk's metadata alongside ``context_length``.

    ``persist_partial_on_error`` selects the error contract: chat discards
    partial output and rolls back (the client shows an error event), while
    rooms persist whatever streamed — other participants already saw it.
    """
    result = result if result is not None else TurnResult()
    opts = options or ChatOptions()

    # Thinking from tool-calling iterations (which produce no `content` and
    # so don't get persisted on their own) is carried forward and attached
    # to the next assistant message that does have content, so persisted
    # state is one tidy assistant message per turn with cumulative
    # reasoning instead of orphaned thinking + a separate answer message.
    pending_thinking: list[str] = []
    full_response = ""
    thinking_content = ""

    try:
        # Allocate the effective window explicitly — without num_ctx, Ollama
        # runs at its own default (typically 4096) no matter what the model
        # supports, silently truncating long conversations. The server-side
        # value is also a ceiling: a client-supplied num_ctx may shrink the
        # window but never grow it (an oversized request would make the
        # runtime allocate an arbitrarily large KV cache).
        context_length = await resolve_context_length(provider, model)
        opts.num_ctx = min(opts.num_ctx or context_length, context_length)

        # One extra pass beyond the cap, run WITHOUT tools: when the model is
        # still asking for tools after max_tool_iterations, it must answer
        # from the results it already has instead of the turn dying silently.
        for iteration in range(max_tool_iterations + 1):
            capped = iteration >= max_tool_iterations
            full_response = ""
            thinking_content = ""
            metadata: dict | None = None
            tool_calls_this_iter: list[dict] | None = None

            async for chunk in provider.stream_chat(
                messages=llm_messages,
                model=model,
                options=opts,
                cancel_event=cancel_event,
                tools=None if capped else (tools or None),
            ):
                if chunk.tool_calls:
                    if capped:
                        # No tools were offered on this pass; drop stray calls
                        # instead of executing past the budget.
                        continue
                    tool_calls_this_iter = chunk.tool_calls
                    yield chunk
                    continue
                if chunk.is_thinking:
                    thinking_content += chunk.content
                elif chunk.content:
                    full_response += chunk.content
                if chunk.is_finished:
                    # Stamp the window we allocated so persisted message meta
                    # and the live stream both carry the real denominator for
                    # context-usage display, plus caller-supplied context
                    # stats (memories/KB) when present.
                    if chunk.metadata is None:
                        chunk.metadata = {}
                    chunk.metadata.setdefault("context_length", opts.num_ctx)
                    if capped:
                        # Flag that the answer was forced by the iteration
                        # budget, so clients/persisted meta can surface it.
                        chunk.metadata.setdefault("tool_iteration_cap", True)
                        chunk.metadata.setdefault(
                            "max_iterations", max_tool_iterations
                        )
                    for key, value in (extra_finish_metadata or {}).items():
                        chunk.metadata.setdefault(key, value)
                    metadata = chunk.metadata
                yield chunk

            if thinking_content:
                pending_thinking.append(thinking_content)

            if full_response:
                msg_meta = dict(metadata) if metadata else {}
                combined_thinking = "\n\n".join(pending_thinking)
                if combined_thinking:
                    msg_meta["thinking"] = combined_thinking
                pending_thinking = []
                await sink.persist_assistant(full_response, msg_meta or None)
                llm_messages.append(
                    LLMMessage(role="assistant", content=full_response)
                )
                result.content = full_response
                result.thinking = combined_thinking
                result.metadata = metadata

            if not tool_calls_this_iter:
                await sink.commit()
                result.completed = True
                return

            await sink.persist_tool_call(tool_calls_this_iter)

            # Send tool calls via the API's native field — never as raw
            # JSON in content, or the model mimics the format and emits
            # the call as text on subsequent turns.
            llm_messages.append(
                LLMMessage(
                    role="assistant",
                    content="",
                    tool_calls=tool_calls_this_iter,
                )
            )

            for call in tool_calls_this_iter:
                execution = {
                    "tool_call_id": call.get("id"),
                    "tool_name": call.get("name"),
                }
                # Live progress markers so the UI can show "running…"
                # instead of going silent for the duration of the call.
                yield ChatChunk(
                    content="",
                    is_finished=False,
                    metadata={
                        "tool_execution": {**execution, "status": "started"}
                    },
                )
                started_at = asyncio.get_event_loop().time()
                if execute_tool is None:
                    tool_result: dict[str, Any] = {
                        "ok": False,
                        "error": "No tool executor configured",
                    }
                else:
                    tool_result = await execute_tool(call)
                duration_ms = int(
                    (asyncio.get_event_loop().time() - started_at) * 1000
                )
                yield ChatChunk(
                    content="",
                    is_finished=False,
                    metadata={
                        "tool_execution": {
                            **execution,
                            "status": "finished",
                            "duration_ms": duration_ms,
                        }
                    },
                )

                raw_text = stringify_tool_result(tool_result)
                result_text = truncate_tool_result(
                    raw_text, get_settings().tool_result_max_chars
                )
                result_meta = {
                    "tool_call_id": call.get("id"),
                    "tool_name": call.get("name"),
                    # Oversized results are stored truncated too — the
                    # meta JSONB otherwise carries the full payload.
                    "result": tool_result
                    if len(raw_text) == len(result_text)
                    else result_text,
                    "duration_ms": duration_ms,
                }
                if len(raw_text) != len(result_text):
                    result_meta["truncated"] = True
                await sink.persist_tool_result(result_text, result_meta)

                yield ChatChunk(
                    content="",
                    is_finished=False,
                    metadata={"tool_result": result_meta},
                )

                llm_messages.append(LLMMessage(role="tool", content=result_text))

            await sink.commit()

        result.error = True
        yield ChatChunk(
            content="",
            is_finished=True,
            metadata={
                "error": True,
                "error_type": "tool_iteration_cap",
                "max_iterations": max_tool_iterations,
            },
        )

    except Exception as e:
        logger.exception("Error in agent turn streaming")
        result.error = True
        if persist_partial_on_error:
            content = full_response or f"[agent error: {e}]"
            msg_meta: dict[str, Any] = {
                "error": True,
                "error_type": "streaming_error",
            }
            combined_thinking = "\n\n".join(
                [*pending_thinking, thinking_content]
                if thinking_content
                else pending_thinking
            )
            if combined_thinking:
                msg_meta["thinking"] = combined_thinking
            try:
                await sink.persist_assistant(content, msg_meta)
                await sink.commit()
                result.content = content
                result.thinking = combined_thinking
            except Exception:
                logger.exception("Failed to persist partial turn after error")
                await sink.rollback()
        else:
            await sink.rollback()
        yield ChatChunk(
            content=f"Error: {e}",
            is_finished=True,
            metadata={"error": True, "error_type": "streaming_error"},
        )
