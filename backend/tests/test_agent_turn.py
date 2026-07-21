"""Tests for the transport-agnostic ``run_agent_turn`` engine.

Focused on the tool-progress channel: a tool can stream live chunks (via the
emitter) that interleave into the turn's output while it runs, before the
tool_result / tool_execution-finished markers.
"""

import asyncio
from collections.abc import AsyncIterator

import pytest

from app.schemas.chat import ChatOptions, ModelInfo
from app.services.agent_turn import run_agent_turn
from app.services.llm_provider import ChatChunk
from app.services.llm_provider import Message as LLMMessage

pytestmark = pytest.mark.asyncio


class _ScriptedProvider:
    """Yields one chunk script per streaming call (one script per iteration)."""

    def __init__(self, scripts: list[list[ChatChunk]]):
        self._scripts = scripts
        self._call = 0

    @property
    def name(self) -> str:
        return "scripted"

    async def stream_chat(
        self, messages, model, options=None, cancel_event=None, tools=None
    ) -> AsyncIterator[ChatChunk]:
        script = self._scripts[self._call]
        self._call += 1
        for chunk in script:
            yield chunk

    async def chat(self, *a, **k) -> str:  # pragma: no cover
        return ""

    async def list_models(self) -> list[ModelInfo]:  # pragma: no cover
        return []

    async def health_check(self) -> bool:  # pragma: no cover
        return True


class _NoopSink:
    async def persist_assistant(self, content, meta):  # noqa: D401
        pass

    async def persist_tool_call(self, tool_calls):
        pass

    async def persist_tool_result(self, content, meta):
        pass

    async def commit(self):
        pass

    async def rollback(self):
        pass


def _tool_execution_status(chunk: ChatChunk) -> str | None:
    if chunk.metadata and "tool_execution" in chunk.metadata:
        return chunk.metadata["tool_execution"].get("status")
    return None


async def test_tool_progress_interleaves_before_result(monkeypatch):
    # Skip the real context-length probe (no provider round-trip in the test).
    monkeypatch.setattr(
        "app.services.agent_turn.resolve_context_length",
        lambda provider, model: _async_return(4096),
    )

    provider = _ScriptedProvider(
        [
            # Iteration 0: the model asks for one tool.
            [
                ChatChunk(content="", tool_calls=[{"id": "c1", "name": "micro_app"}]),
                ChatChunk(content="", is_finished=True, metadata={}),
            ],
            # Iteration 1: the model answers from the tool result.
            [ChatChunk(content="all done"), ChatChunk(content="", is_finished=True, metadata={})],
        ]
    )

    async def execute_tool(call, emit):
        # Stream two live progress steps while "running".
        await emit(ChatChunk(content="", tool_calls=[{"id": "s1", "name": "read"}]))
        await emit(
            ChatChunk(content="", metadata={"tool_result": {"tool_call_id": "s1", "result": "ok"}})
        )
        return {"ok": True, "summary": "edited"}

    chunks = [
        chunk
        async for chunk in run_agent_turn(
            provider=provider,
            model="fake",
            llm_messages=[LLMMessage(role="user", content="edit it")],
            sink=_NoopSink(),
            options=ChatOptions(),
            tools=[{"type": "function"}],
            execute_tool=execute_tool,
        )
    ]

    # Reconstruct a coarse timeline of the tool phase.
    timeline = []
    for c in chunks:
        status = _tool_execution_status(c)
        if status:
            timeline.append(f"exec:{status}")
        elif c.tool_calls and c.tool_calls[0]["name"] == "read":
            timeline.append("progress:tool_call")
        elif c.metadata and c.metadata.get("tool_result", {}).get("tool_call_id") == "s1":
            timeline.append("progress:tool_result")
        elif c.metadata and c.metadata.get("tool_result"):
            timeline.append("outer:tool_result")

    # The live progress arrives strictly between started and finished, and the
    # outer tool_result follows the finished marker.
    assert timeline == [
        "exec:started",
        "progress:tool_call",
        "progress:tool_result",
        "exec:finished",
        "outer:tool_result",
    ]


async def test_provider_error_chunk_calls_error_reporter(monkeypatch):
    monkeypatch.setattr(
        "app.services.agent_turn.resolve_context_length",
        lambda provider, model: _async_return(4096),
    )
    provider = _ScriptedProvider(
        [
            [
                ChatChunk(
                    content="Ollama stopped responding",
                    is_finished=True,
                    metadata={"error": True, "stack_trace": "provider trace"},
                )
            ]
        ]
    )
    reported: list[tuple[Exception, str | None, str | None]] = []

    async def on_error(error, tool_call_id, trace):
        reported.append((error, tool_call_id, trace))

    chunks = [
        chunk
        async for chunk in run_agent_turn(
            provider=provider,
            model="fake",
            llm_messages=[LLMMessage(role="user", content="hello")],
            sink=_NoopSink(),
            options=ChatOptions(),
            on_error=on_error,
        )
    ]

    assert len(chunks) == 1
    assert str(reported[0][0]) == "Ollama stopped responding"
    assert reported[0][2] == "provider trace"


class _CancellingProvider:
    """Streams a couple of chunks, then simulates a client disconnect."""

    @property
    def name(self) -> str:
        return "cancelling"

    async def stream_chat(
        self, messages, model, options=None, cancel_event=None, tools=None
    ) -> AsyncIterator[ChatChunk]:
        yield ChatChunk(content="Hello ")
        yield ChatChunk(content="there")
        raise asyncio.CancelledError()

    async def chat(self, *a, **k) -> str:  # pragma: no cover
        return ""

    async def list_models(self) -> list[ModelInfo]:  # pragma: no cover
        return []

    async def health_check(self) -> bool:  # pragma: no cover
        return True


class _RecordingSink:
    def __init__(self):
        self.persisted: list[tuple[str, dict | None]] = []
        self.committed = False
        self.rolled_back = False

    async def persist_assistant(self, content, meta):
        self.persisted.append((content, meta))

    async def persist_tool_call(self, tool_calls):
        pass

    async def persist_tool_result(self, content, meta):
        pass

    async def commit(self):
        self.committed = True

    async def rollback(self):
        self.rolled_back = True


async def test_cancellation_persists_partial_content(monkeypatch):
    """A client disconnect (CancelledError) must not silently drop the reply.

    B-01: Android backgrounding tears down the socket mid-stream. Before this
    fix, CancelledError (a BaseException, not Exception) skipped the
    persist-on-error branch entirely and the accumulated content vanished.
    """
    monkeypatch.setattr(
        "app.services.agent_turn.resolve_context_length",
        lambda provider, model: _async_return(4096),
    )

    sink = _RecordingSink()

    with pytest.raises(asyncio.CancelledError):
        async for _ in run_agent_turn(
            provider=_CancellingProvider(),
            model="fake",
            llm_messages=[LLMMessage(role="user", content="hi")],
            sink=sink,
            options=ChatOptions(),
        ):
            pass

    assert sink.persisted == [("Hello there", None)]
    assert sink.committed is True
    assert sink.rolled_back is False


async def _async_return(value):
    return value
