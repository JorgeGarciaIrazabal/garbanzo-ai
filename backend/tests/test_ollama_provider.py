"""Provider-level tests for OllamaProvider.

We mock the Ollama AsyncClient at the SDK boundary so we can assert the
exact kwargs the provider sends, without needing a running Ollama process.
"""

from collections.abc import AsyncIterator
from typing import Any
from unittest.mock import AsyncMock, MagicMock, patch

import pytest
from ollama import ResponseError

from app.schemas.chat import ChatOptions
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


class _MultiChunkStream:
    """Async-iterable yielding multiple scripted chunks."""

    def __init__(self, chunks: list[dict]):
        self._chunks = list(chunks)
        self._idx = 0

    def __aiter__(self) -> AsyncIterator[Any]:
        return self

    async def __anext__(self) -> Any:
        if self._idx >= len(self._chunks):
            raise StopAsyncIteration
        data = self._chunks[self._idx]
        self._idx += 1
        chunk = MagicMock()
        chunk.get = lambda key, default=None: data.get(key, default)
        chunk.eval_count = data.get("eval_count")
        chunk.prompt_eval_count = data.get("prompt_eval_count")
        chunk.total_duration = data.get("total_duration")
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


async def test_non_streaming_chat_passes_normalized_thinking_effort():
    """Internal curator calls use ``chat`` and must honor their effort setting."""
    provider = OllamaProvider()
    provider._model_meta["glm-5.3-flash:cloud"] = (
        100000,
        ["completion", "thinking"],
    )
    response = MagicMock()
    response.message.content = '{"topics":[]}'
    mock_client = MagicMock()
    mock_client.chat = AsyncMock(return_value=response)

    with patch.object(provider, "_get_client", return_value=mock_client):
        content = await provider.chat(
            messages=[Message(role="user", content="curate")],
            model="glm-5.3-flash:cloud",
            options=ChatOptions(think="medium", response_format={"type": "object"}),
        )

    assert content == '{"topics":[]}'
    kwargs = mock_client.chat.await_args.kwargs
    assert kwargs["think"] == "medium"
    assert kwargs["format"] == {"type": "object"}
    assert kwargs["stream"] is False


async def test_stream_chat_rejects_images_before_calling_text_only_model():
    """A known text-only model gets a useful capability error, not Ollama's
    raw 400 response (user report ac2647df)."""
    provider = OllamaProvider()
    provider._model_meta["text-only"] = (131072, ["completion", "tools"])

    mock_client = MagicMock()
    mock_client.chat = AsyncMock()

    chunks = []
    with patch.object(provider, "_get_client", return_value=mock_client):
        async for chunk in provider.stream_chat(
            messages=[Message(role="user", content="describe this", images=["base64-image"])],
            model="text-only",
        ):
            chunks.append(chunk)

    mock_client.chat.assert_not_awaited()
    assert len(chunks) == 1
    assert chunks[0].content == (
        "This model cannot process image attachments. "
        "Switch to a model marked Vision and try again."
    )
    assert chunks[0].metadata == {
        "error": True,
        "error_type": "unsupported_image_input",
        "status_code": 400,
        "auto_report": False,
    }


async def test_stream_chat_translates_image_400_when_metadata_is_unknown():
    """The runtime response remains a safety net when `ollama show` was
    temporarily unavailable and the provider could not preflight capabilities."""
    provider = OllamaProvider()
    mock_client = MagicMock()
    mock_client.chat = AsyncMock(
        side_effect=ResponseError("this model does not support image input", 400)
    )

    chunks = []
    with (
        patch.object(provider, "_get_model_meta", new=AsyncMock(return_value=(None, []))),
        patch.object(provider, "_get_client", return_value=mock_client),
    ):
        async for chunk in provider.stream_chat(
            messages=[Message(role="user", content="describe this", images=["base64-image"])],
            model="unknown-capabilities",
        ):
            chunks.append(chunk)

    mock_client.chat.assert_awaited_once()
    assert len(chunks) == 1
    assert chunks[0].metadata == {
        "error": True,
        "error_type": "unsupported_image_input",
        "status_code": 400,
        "auto_report": False,
    }


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


async def test_stream_chat_glm_think_off_passes_low_and_suppresses_thinking():
    """GLM models leak raw reasoning if think=False is sent to Ollama.
    The provider maps think='off' to think='low' with suppression so
    reasoning chunks are discarded and zero thinking is surfaced to user."""
    provider = OllamaProvider()
    provider._model_meta["glm-5.2:cloud"] = (1048576, ["completion", "thinking", "tools"])

    captured_kwargs: dict = {}

    chunks_data = [
        {"message": {"thinking": "Internal reasoning step", "content": ""}, "done": False},
        {"message": {"thinking": "", "content": "Clean answer"}, "done": False},
        {"message": {"thinking": "", "content": ""}, "done": True, "eval_count": 10},
    ]

    async def _fake_chat(**kwargs):
        captured_kwargs.update(kwargs)
        return _MultiChunkStream(chunks_data)

    mock_client = MagicMock()
    mock_client.chat = AsyncMock(side_effect=_fake_chat)

    emitted_chunks = []
    with patch.object(provider, "_get_client", return_value=mock_client):
        async for chunk in provider.stream_chat(
            messages=[Message(role="user", content="Who is Clara?")],
            model="glm-5.2:cloud",
            options=ChatOptions(think="off"),
        ):
            emitted_chunks.append(chunk)

    assert captured_kwargs.get("think") == "low"
    assert not any(c.is_thinking for c in emitted_chunks)
    content_chunks = [c for c in emitted_chunks if not c.is_finished]
    assert len(content_chunks) == 1
    assert content_chunks[0].content == "Clean answer"
    done_chunk = emitted_chunks[-1]
    assert done_chunk.is_finished
    assert "thinking" not in done_chunk.metadata


async def test_stream_chat_splits_think_tags_across_chunks():
    """When a model emits raw <think>...</think> tags in content, the state
    machine extracts thinking chunks and emits only clean answer content."""
    provider = OllamaProvider()
    provider._model_meta["glm-5.2:cloud"] = (1048576, ["completion", "thinking"])

    chunks_data = [
        {"message": {"content": "<think>First thought "}, "done": False},
        {"message": {"content": "second thought</think>The answer"}, "done": False},
        {"message": {"content": ""}, "done": True},
    ]

    mock_client = MagicMock()
    mock_client.chat = AsyncMock(return_value=_MultiChunkStream(chunks_data))

    emitted_chunks = []
    with patch.object(provider, "_get_client", return_value=mock_client):
        async for chunk in provider.stream_chat(
            messages=[Message(role="user", content="hi")],
            model="glm-5.2:cloud",
            options=ChatOptions(think="high"),
        ):
            emitted_chunks.append(chunk)

    thinking_chunks = [c for c in emitted_chunks if c.is_thinking]
    content_chunks = [c for c in emitted_chunks if not c.is_thinking and not c.is_finished]
    assert len(thinking_chunks) >= 1
    assert "First thought" in "".join(c.content for c in thinking_chunks)
    assert "second thought" in "".join(c.content for c in thinking_chunks)
    assert len(content_chunks) == 1
    assert content_chunks[0].content == "The answer"


async def test_list_models_advertises_all_thinking_levels():
    """Models with 'thinking' capability advertise off, low, medium, high."""
    response = MagicMock()
    model = MagicMock()
    model.model = "glm-5.2:cloud"
    model.details = None
    response.models = [model]

    provider = OllamaProvider()
    mock_client = MagicMock()
    mock_client.list = AsyncMock(return_value=response)

    with (
        patch.object(provider, "_get_client", return_value=mock_client),
        patch.object(
            provider,
            "_get_model_meta",
            new=AsyncMock(return_value=(1048576, ["completion", "thinking"])),
        ),
    ):
        models = await provider.list_models()

    assert len(models) == 1
    assert models[0].supports_thinking is True
    assert models[0].thinking_levels == ["off", "low", "medium", "high"]
    assert models[0].default_thinking_level == "high"


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


async def test_list_models_hides_dated_deepseek_preview_aliases():
    """Stable DeepSeek tags replace their dated preview aliases in the UI."""
    response = MagicMock()
    response.models = []
    for model_id in (
        "deepseek-v4-flash:0731-cloud",
        "deepseek-v4-flash:cloud",
        "deepseek-v4-pro:0813-cloud",
        "deepseek-v4-pro:cloud",
    ):
        model = MagicMock()
        model.model = model_id
        model.details = None
        response.models.append(model)

    provider = OllamaProvider()
    mock_client = MagicMock()
    mock_client.list = AsyncMock(return_value=response)

    with (
        patch.object(provider, "_get_client", return_value=mock_client),
        patch.object(
            provider,
            "_get_model_meta",
            new=AsyncMock(return_value=(100_000, ["completion"])),
        ),
    ):
        models = await provider.list_models()

    assert [model.id for model in models] == [
        "deepseek-v4-flash:cloud",
        "deepseek-v4-pro:cloud",
    ]


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


async def test_stream_chat_retries_server_500_errors(monkeypatch):
    """Ollama intermittently returns a bare HTTP 500 while establishing a
    stream with cloud models (user reports 332c4484, 3313e70a, 7dfce5b8,
    4ed52bee): the same request succeeds seconds later. Server-side 5xx
    errors are therefore retried during stream setup, before any token has
    been delivered."""
    import app.services.ollama_provider as op

    monkeypatch.setattr(op, "_RETRY_BACKOFF_SECONDS", 0.001)

    provider = OllamaProvider()
    provider._model_meta["kimi-k3:cloud"] = (1048576, ["thinking", "tools"])

    attempts = 0

    async def _flaky_chat(**kwargs):
        nonlocal attempts
        attempts += 1
        if attempts < 3:
            raise ResponseError("Internal Server Error (ref: abc)", 500)
        return _FakeStream()

    mock_client = MagicMock()
    mock_client.chat = AsyncMock(side_effect=_flaky_chat)

    chunks = []
    with patch.object(provider, "_get_client", return_value=mock_client):
        async for chunk in provider.stream_chat(
            messages=[Message(role="user", content="hi")],
            model="kimi-k3:cloud",
        ):
            chunks.append(chunk)

    assert attempts == 3
    assert chunks[-1].is_finished
    assert not (chunks[-1].metadata or {}).get("error")


async def test_stream_chat_5xx_error_chunk_is_actionable_with_diagnostics(monkeypatch):
    """After the retry budget is exhausted on server 5xx errors, the user sees
    an actionable message (not a raw 'Internal Server Error') and the error
    chunk carries request-shape diagnostics for the auto-report."""
    import app.services.ollama_provider as op

    monkeypatch.setattr(op, "_RETRY_BACKOFF_SECONDS", 0.001)

    provider = OllamaProvider()
    provider._model_meta["kimi-k3:cloud"] = (1048576, ["thinking", "tools"])

    mock_client = MagicMock()
    mock_client.chat = AsyncMock(side_effect=ResponseError("Internal Server Error", 500))

    chunks = []
    with patch.object(provider, "_get_client", return_value=mock_client):
        async for chunk in provider.stream_chat(
            messages=[Message(role="user", content="hi" * 50)],
            model="kimi-k3:cloud",
        ):
            chunks.append(chunk)

    assert mock_client.chat.await_count == 3
    final = chunks[-1]
    assert final.is_finished
    assert final.metadata["error"] is True
    assert final.metadata["status_code"] == 500
    assert "try again" in final.content.lower()
    assert "Internal Server Error" not in final.content
    # Request-shape diagnostics for the auto-filed report.
    assert final.metadata["model"] == "kimi-k3:cloud"
    assert final.metadata["message_count"] == 1
    assert final.metadata["prompt_chars"] == 100


async def test_stream_chat_does_not_retry_client_4xx_errors(monkeypatch):
    """Client errors (400 unknown model, etc.) are deterministic — the retry
    budget is reserved for transient server-side faults."""
    import app.services.ollama_provider as op

    monkeypatch.setattr(op, "_RETRY_BACKOFF_SECONDS", 0.001)

    provider = OllamaProvider()
    provider._model_meta["unknown-model"] = (None, [])

    mock_client = MagicMock()
    mock_client.chat = AsyncMock(side_effect=ResponseError("model not found", 404))

    chunks = []
    with patch.object(provider, "_get_client", return_value=mock_client):
        async for chunk in provider.stream_chat(
            messages=[Message(role="user", content="hi")],
            model="unknown-model",
        ):
            chunks.append(chunk)

    assert mock_client.chat.await_count == 1
    assert chunks[-1].is_finished
    assert (chunks[-1].metadata or {}).get("status_code") == 404


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
