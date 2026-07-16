"""Provider-level tests for OllamaProvider.

We mock the Ollama AsyncClient at the SDK boundary so we can assert the
exact kwargs the provider sends, without needing a running Ollama process.
"""

from collections.abc import AsyncIterator
from unittest.mock import AsyncMock, MagicMock, patch

import pytest

from app.services.llm_provider import Message
from app.services.ollama_provider import OllamaProvider

pytestmark = pytest.mark.asyncio


class _FakeStream:
    """Async-iterable that yields a single non-streaming-style 'done' chunk
    so the provider exits its loop cleanly."""

    def __init__(self):
        self._yielded = False

    def __aiter__(self) -> AsyncIterator[dict]:
        return self

    async def __anext__(self) -> dict:
        if self._yielded:
            raise StopAsyncIteration
        self._yielded = True
        chunk = MagicMock()
        chunk.get = lambda key, default=None: {
            "message": {"content": "", "thinking": "", "tool_calls": []},
            "done": True,
        }.get(key, default)
        chunk.eval_count = None
        chunk.prompt_eval_count = None
        chunk.total_duration = None
        return chunk


async def test_stream_chat_passes_think_true_for_thinking_models():
    """Regression: the provider must pass ``think=True`` for models that
    support it, so reasoning models surface their thinking incrementally
    during the otherwise-silent gap before the answer or tool call."""
    provider = OllamaProvider()
    # Seed the metadata cache so no `show` call is needed.
    provider._model_meta["qwen3:1.7b"] = (40960, ["completion", "thinking"])

    captured_kwargs: dict = {}

    async def _fake_chat(**kwargs):
        captured_kwargs.update(kwargs)
        return _FakeStream()

    mock_client = MagicMock()
    mock_client.chat = AsyncMock(side_effect=_fake_chat)

    with patch.object(provider, "_get_client", return_value=mock_client):
        async for _ in provider.stream_chat(
            messages=[Message(role="user", content="hi")],
            model="qwen3:1.7b",
        ):
            pass

    assert captured_kwargs.get("think") is True
    assert captured_kwargs.get("stream") is True
    assert captured_kwargs["model"] == "qwen3:1.7b"


async def test_stream_chat_omits_think_for_non_thinking_models():
    """Regression: current Ollama rejects ``think=True`` with a 400 for
    models without the thinking capability, so the flag must be omitted."""
    provider = OllamaProvider()
    provider._model_meta["llama3.2:3b"] = (131072, ["completion", "tools"])

    captured_kwargs: dict = {}

    async def _fake_chat(**kwargs):
        captured_kwargs.update(kwargs)
        return _FakeStream()

    mock_client = MagicMock()
    mock_client.chat = AsyncMock(side_effect=_fake_chat)

    with patch.object(provider, "_get_client", return_value=mock_client):
        async for _ in provider.stream_chat(
            messages=[Message(role="user", content="hi")],
            model="llama3.2:3b",
        ):
            pass

    assert "think" not in captured_kwargs


async def test_stream_chat_passes_num_ctx_option():
    """num_ctx from ChatOptions must reach Ollama's request options, so the
    runtime actually allocates the window the server budgeted for."""
    from app.schemas.chat import ChatOptions

    provider = OllamaProvider()
    provider._model_meta["llama3.2:3b"] = (131072, ["completion"])

    captured_kwargs: dict = {}

    async def _fake_chat(**kwargs):
        captured_kwargs.update(kwargs)
        return _FakeStream()

    mock_client = MagicMock()
    mock_client.chat = AsyncMock(side_effect=_fake_chat)

    with patch.object(provider, "_get_client", return_value=mock_client):
        async for _ in provider.stream_chat(
            messages=[Message(role="user", content="hi")],
            model="llama3.2:3b",
            options=ChatOptions(num_ctx=8192),
        ):
            pass

    assert captured_kwargs["options"]["num_ctx"] == 8192


@pytest.mark.parametrize("level", ["low", "medium", "high"])
async def test_stream_chat_think_level_passed_through_for_thinking_models(level):
    """A conversation-level ``thinking_level`` of 'low'/'medium'/'high' (see
    Conversation.thinking_level) is mirrored onto ChatOptions.think and must
    reach Ollama verbatim — ollama-py types `think` as
    ``bool | Literal["low", "medium", "high"]`` (ollama/_types.py), so these
    map straight onto the SDK's own accepted values."""
    from app.schemas.chat import ChatOptions

    provider = OllamaProvider()
    provider._model_meta["qwen3:1.7b"] = (40960, ["completion", "thinking"])

    captured_kwargs: dict = {}

    async def _fake_chat(**kwargs):
        captured_kwargs.update(kwargs)
        return _FakeStream()

    mock_client = MagicMock()
    mock_client.chat = AsyncMock(side_effect=_fake_chat)

    with patch.object(provider, "_get_client", return_value=mock_client):
        async for _ in provider.stream_chat(
            messages=[Message(role="user", content="hi")],
            model="qwen3:1.7b",
            options=ChatOptions(think=level),
        ):
            pass

    assert captured_kwargs.get("think") == level


async def test_stream_chat_think_off_disables_thinking_for_capable_model():
    """thinking_level='off' must force-disable thinking even for a model
    that would otherwise get think=True by default."""
    from app.schemas.chat import ChatOptions

    provider = OllamaProvider()
    provider._model_meta["qwen3:1.7b"] = (40960, ["completion", "thinking"])

    captured_kwargs: dict = {}

    async def _fake_chat(**kwargs):
        captured_kwargs.update(kwargs)
        return _FakeStream()

    mock_client = MagicMock()
    mock_client.chat = AsyncMock(side_effect=_fake_chat)

    with patch.object(provider, "_get_client", return_value=mock_client):
        async for _ in provider.stream_chat(
            messages=[Message(role="user", content="hi")],
            model="qwen3:1.7b",
            options=ChatOptions(think="off"),
        ):
            pass

    assert captured_kwargs.get("think") is False


async def test_stream_chat_think_level_ignored_for_non_thinking_model():
    """An explicit thinking_level is silently ignored for a model that
    doesn't advertise the 'thinking' capability — same safety net as the
    implicit-default path, since Ollama 400s on an unsupported think value."""
    from app.schemas.chat import ChatOptions

    provider = OllamaProvider()
    provider._model_meta["llama3.2:3b"] = (131072, ["completion", "tools"])

    captured_kwargs: dict = {}

    async def _fake_chat(**kwargs):
        captured_kwargs.update(kwargs)
        return _FakeStream()

    mock_client = MagicMock()
    mock_client.chat = AsyncMock(side_effect=_fake_chat)

    with patch.object(provider, "_get_client", return_value=mock_client):
        async for _ in provider.stream_chat(
            messages=[Message(role="user", content="hi")],
            model="llama3.2:3b",
            options=ChatOptions(think="high"),
        ):
            pass

    assert "think" not in captured_kwargs


async def test_model_meta_failures_are_not_cached():
    """A transient show() failure (e.g. Ollama briefly down) must not be
    cached, or thinking/capability detection stays disabled until restart."""
    provider = OllamaProvider()

    failing_client = MagicMock()
    failing_client.show = AsyncMock(side_effect=ConnectionError("down"))

    with patch.object(provider, "_get_client", return_value=failing_client):
        assert await provider._get_model_meta("qwen3:1.7b") == (None, [])
    assert "qwen3:1.7b" not in provider._model_meta

    # Ollama comes back: the next lookup succeeds and gets cached.
    show_response = MagicMock()
    show_response.modelinfo = {"qwen3.context_length": 40960}
    show_response.capabilities = ["completion", "thinking"]
    healthy_client = MagicMock()
    healthy_client.show = AsyncMock(return_value=show_response)

    with patch.object(provider, "_get_client", return_value=healthy_client):
        assert await provider._get_model_meta("qwen3:1.7b") == (
            40960,
            ["completion", "thinking"],
        )
    assert provider._model_meta["qwen3:1.7b"] == (40960, ["completion", "thinking"])


async def test_stream_chat_retries_transient_connection_errors(monkeypatch):
    """Transient connection failures while establishing the stream are
    retried with backoff; the stream then proceeds normally."""
    from ollama import RequestError

    import app.services.ollama_provider as op

    monkeypatch.setattr(op, "_RETRY_BACKOFF_SECONDS", 0.001)

    provider = OllamaProvider()
    provider._model_meta["llama3.2:3b"] = (131072, ["completion"])

    attempts = 0

    async def _flaky_chat(**kwargs):
        nonlocal attempts
        attempts += 1
        if attempts < 3:
            raise RequestError("connection refused")
        return _FakeStream()

    mock_client = MagicMock()
    mock_client.chat = AsyncMock(side_effect=_flaky_chat)

    chunks = []
    with patch.object(provider, "_get_client", return_value=mock_client):
        async for chunk in provider.stream_chat(
            messages=[Message(role="user", content="hi")],
            model="llama3.2:3b",
        ):
            chunks.append(chunk)

    assert attempts == 3
    assert chunks[-1].is_finished
    assert not (chunks[-1].metadata or {}).get("error")


async def test_stream_chat_gives_up_after_max_retries(monkeypatch):
    from ollama import RequestError

    import app.services.ollama_provider as op

    monkeypatch.setattr(op, "_RETRY_BACKOFF_SECONDS", 0.001)

    provider = OllamaProvider()
    provider._model_meta["llama3.2:3b"] = (131072, ["completion"])

    mock_client = MagicMock()
    mock_client.chat = AsyncMock(side_effect=RequestError("connection refused"))

    chunks = []
    with patch.object(provider, "_get_client", return_value=mock_client):
        async for chunk in provider.stream_chat(
            messages=[Message(role="user", content="hi")],
            model="llama3.2:3b",
        ):
            chunks.append(chunk)

    assert mock_client.chat.await_count == 3
    assert chunks[-1].is_finished
    assert (chunks[-1].metadata or {}).get("error") is True


async def test_stream_chat_times_out_on_wedged_stream(monkeypatch):
    """A stream that stops producing chunks must surface a timeout error
    instead of hanging forever."""
    import asyncio as aio

    import app.services.ollama_provider as op

    monkeypatch.setattr(op, "FIRST_CHUNK_TIMEOUT", 0.05)

    class _WedgedStream:
        def __aiter__(self):
            return self

        async def __anext__(self):
            await aio.sleep(3600)  # never produces a chunk

    async def _fake_chat(**kwargs):
        return _WedgedStream()

    provider = OllamaProvider()
    provider._model_meta["llama3.2:3b"] = (131072, ["completion"])

    mock_client = MagicMock()
    mock_client.chat = AsyncMock(side_effect=_fake_chat)

    chunks = []
    with patch.object(provider, "_get_client", return_value=mock_client):
        async for chunk in provider.stream_chat(
            messages=[Message(role="user", content="hi")],
            model="llama3.2:3b",
        ):
            chunks.append(chunk)

    assert chunks[-1].is_finished
    assert (chunks[-1].metadata or {}).get("error_type") == "stream_timeout"
