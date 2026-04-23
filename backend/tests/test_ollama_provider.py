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


async def test_stream_chat_passes_think_true_to_ollama():
    """Regression: the provider must pass ``think=True`` so reasoning models
    surface their thinking incrementally during the otherwise-silent gap
    before the answer or tool call."""
    provider = OllamaProvider()

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
