"""Tests for the transport-agnostic ``run_agent_turn`` engine.

Focused on the tool-progress channel: a tool can stream live chunks (via the
emitter) that interleave into the turn's output while it runs, before the
tool_result / tool_execution-finished markers.
"""

import asyncio
from collections.abc import AsyncIterator
from unittest.mock import AsyncMock

import pytest

from app.schemas.chat import ChatOptions, ModelInfo
from app.services.agent_turn import TurnResult, run_agent_turn
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
    reported: list[tuple[Exception, str | None, str | None, dict | None]] = []

    async def on_error(error, tool_call_id, trace, error_metadata):  # noqa: ARG001
        reported.append((error, tool_call_id, trace, error_metadata))

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
    # The full error-chunk metadata is passed through so the auto-report can
    # carry request-shape diagnostics (model, message_count, prompt_chars).
    assert reported[0][3] == {"error": True, "stack_trace": "provider trace"}


async def test_expected_capability_error_does_not_file_report(monkeypatch):
    monkeypatch.setattr(
        "app.services.agent_turn.resolve_context_length",
        lambda provider, model: _async_return(4096),
    )
    provider = _ScriptedProvider(
        [
            [
                ChatChunk(
                    content="Switch to a model marked Vision and try again.",
                    is_finished=True,
                    metadata={
                        "error": True,
                        "error_type": "unsupported_image_input",
                        "auto_report": False,
                    },
                )
            ]
        ]
    )
    reports: list[Exception] = []

    async def on_error(error, tool_call_id, trace, error_metadata):  # noqa: ARG001
        reports.append(error)

    chunks = [
        chunk
        async for chunk in run_agent_turn(
            provider=provider,
            model="text-only",
            llm_messages=[LLMMessage(role="user", content="describe the image")],
            sink=_NoopSink(),
            options=ChatOptions(),
            on_error=on_error,
        )
    ]

    assert len(chunks) == 1
    assert reports == []


@pytest.mark.parametrize("persist_partial_on_error", [False, True])
@pytest.mark.parametrize("empty_kind", ["empty", "whitespace", "thinking", "stray_tool"])
async def test_repeated_empty_synthesis_is_reported_as_failure(
    monkeypatch, persist_partial_on_error, empty_kind
):
    monkeypatch.setattr(
        "app.services.agent_turn.resolve_context_length",
        lambda provider, model: _async_return(4096),
    )
    empty_chunks = {
        "empty": [],
        "whitespace": [ChatChunk(content=" \n")],
        "thinking": [ChatChunk(content="Still considering", is_thinking=True)],
        "stray_tool": [ChatChunk(content="", tool_calls=[{"id": "stray", "name": "search"}])],
    }[empty_kind]
    provider = _ScriptedProvider(
        [
            [ChatChunk(content="", tool_calls=[{"id": "first", "name": "search"}])],
            [*empty_chunks, ChatChunk(content="", is_finished=True)],
            [*empty_chunks, ChatChunk(content="", is_finished=True)],
        ]
    )
    sink = AsyncMock(spec=_NoopSink)
    execute_tool = AsyncMock(return_value={"ok": True, "content": "Evidence"})
    on_error = AsyncMock()
    result = TurnResult()
    chunks = [
        chunk
        async for chunk in run_agent_turn(
            provider=provider,
            model="fake",
            llm_messages=[LLMMessage(role="user", content="Research it")],
            sink=sink,
            execute_tool=execute_tool,
            max_tool_iterations=1,
            persist_partial_on_error=persist_partial_on_error,
            on_error=on_error,
            result=result,
        )
    ]

    assert provider._call == 3
    execute_tool.assert_awaited_once()
    on_error.assert_awaited_once()
    assert result.error and not result.completed
    finishes = [c for c in chunks if c.is_finished]
    assert len(finishes) == 1
    assert finishes[0].metadata["error"] is True
    assert "no final answer" in finishes[0].content
    if persist_partial_on_error:
        sink.persist_assistant.assert_awaited_once()
        assert sink.persist_assistant.call_args.args[1]["error"] is True
    else:
        sink.persist_assistant.assert_not_awaited()
        sink.rollback.assert_awaited_once()


async def test_cancel_during_empty_synthesis_does_not_retry_or_report(monkeypatch):
    monkeypatch.setattr(
        "app.services.agent_turn.resolve_context_length",
        lambda provider, model: _async_return(4096),
    )
    cancel_event = asyncio.Event()

    class CancellingFinalProvider(_ScriptedProvider):
        async def stream_chat(self, *args, **kwargs):
            async for chunk in super().stream_chat(*args, **kwargs):
                if self._call == 2:
                    cancel_event.set()
                yield chunk

    provider = CancellingFinalProvider(
        [
            [ChatChunk(content="", tool_calls=[{"id": "first", "name": "search"}])],
            [ChatChunk(content="", is_finished=True)],
        ]
    )
    sink = AsyncMock(spec=_NoopSink)
    on_error = AsyncMock()
    result = TurnResult()
    chunks = []
    with pytest.raises(asyncio.CancelledError):
        async for chunk in run_agent_turn(
            provider=provider,
            model="fake",
            llm_messages=[LLMMessage(role="user", content="Research it")],
            sink=sink,
            execute_tool=AsyncMock(return_value={"ok": True}),
            max_tool_iterations=1,
            cancel_event=cancel_event,
            result=result,
            on_error=on_error,
        ):
            chunks.append(chunk)

    assert provider._call == 2
    assert not any(c.is_finished for c in chunks)
    assert not result.completed and not result.error
    sink.persist_assistant.assert_not_awaited()
    on_error.assert_not_awaited()


async def test_cancel_before_synthesis_does_not_duplicate_committed_preamble(monkeypatch):
    monkeypatch.setattr(
        "app.services.agent_turn.resolve_context_length",
        lambda provider, model: _async_return(4096),
    )
    cancel_event = asyncio.Event()
    provider = _ScriptedProvider(
        [
            [
                ChatChunk(content="I will look that up."),
                ChatChunk(content="", tool_calls=[{"id": "first", "name": "search"}]),
            ]
        ]
    )
    sink = AsyncMock(spec=_NoopSink)
    result = TurnResult()

    async def execute_tool(call, emit):
        cancel_event.set()
        return {"ok": True, "content": "Evidence"}

    with pytest.raises(asyncio.CancelledError):
        async for _ in run_agent_turn(
            provider=provider,
            model="fake",
            llm_messages=[LLMMessage(role="user", content="Research it")],
            sink=sink,
            execute_tool=execute_tool,
            max_tool_iterations=1,
            cancel_event=cancel_event,
            result=result,
        ):
            pass

    assert provider._call == 1
    sink.persist_assistant.assert_awaited_once_with("I will look that up.", None)
    assert not result.completed and not result.error


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


async def test_agent_turn_separates_thinking_tags_on_persist(monkeypatch):
    """When a model leaks raw <think>...</think> in content, run_agent_turn
    separates reasoning into message metadata and persists clean text."""
    monkeypatch.setattr(
        "app.services.agent_turn.resolve_context_length",
        lambda provider, model: _async_return(4096),
    )

    provider = _ScriptedProvider(
        [
            [
                ChatChunk(
                    content="<think>Evaluating Clara</think>Clara is daughter",
                    is_finished=False,
                ),
                ChatChunk(content="", is_finished=True),
            ]
        ]
    )

    sink = _RecordingSink()

    async for _ in run_agent_turn(
        provider=provider,
        model="fake",
        llm_messages=[LLMMessage(role="user", content="Who is Clara?")],
        sink=sink,
        options=ChatOptions(think="high"),
    ):
        pass

    assert sink.persisted == [
        ("Clara is daughter", {"context_length": 4096, "thinking": "Evaluating Clara"})
    ]
    assert sink.committed is True


async def test_agent_turn_discards_leaked_thinking_when_think_off(monkeypatch):
    """When think='off', any leaked thinking tags are stripped and discarded
    so neither content nor metadata contains reasoning."""
    monkeypatch.setattr(
        "app.services.agent_turn.resolve_context_length",
        lambda provider, model: _async_return(4096),
    )

    provider = _ScriptedProvider(
        [
            [
                ChatChunk(
                    content="<think>Evaluating Clara</think>Clara is daughter",
                    is_finished=False,
                ),
                ChatChunk(content="", is_finished=True),
            ]
        ]
    )

    sink = _RecordingSink()

    async for _ in run_agent_turn(
        provider=provider,
        model="fake",
        llm_messages=[LLMMessage(role="user", content="Who is Clara?")],
        sink=sink,
        options=ChatOptions(think="off"),
    ):
        pass

    assert sink.persisted == [("Clara is daughter", {"context_length": 4096})]
    assert sink.committed is True


async def _async_return(value):
    return value
