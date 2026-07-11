"""Tests for conversation auto-titling."""

from collections.abc import AsyncIterator

import pytest

from app.services.chat_service import (
    ChatService,
    _clean_generated_title,
    generate_conversation_title,
)
from app.services.conversation_service import ConversationService
from app.services.llm_provider import ChatChunk, LLMProvider, ModelInfo, ProviderRegistry

pytestmark = pytest.mark.asyncio


class TestCleanGeneratedTitle:
    def test_strips_quotes_and_trailing_punctuation(self):
        assert _clean_generated_title('"Quantum Computing Basics."') == ("Quantum Computing Basics")

    def test_takes_first_non_empty_line(self):
        assert _clean_generated_title("\n\nPython Debugging Help\nmore") == (
            "Python Debugging Help"
        )

    def test_strips_inline_think_blocks(self):
        raw = "<think>the user wants...</think>Trip Planning Advice"
        assert _clean_generated_title(raw) == "Trip Planning Advice"

    def test_truncates_to_60_chars(self):
        assert len(_clean_generated_title("x" * 200)) == 60

    def test_empty_output_returns_empty(self):
        assert _clean_generated_title("   \n  ") == ""


class _TitleProvider(LLMProvider):
    """Provider whose chat() returns a canned title; stream_chat yields one
    response chunk so a full send_message turn can complete."""

    def __init__(self, title_response: str = '"Test Title"'):
        self.title_response = title_response
        self.chat_calls: list[dict] = []

    @property
    def name(self) -> str:
        return "title-test"

    async def chat(self, messages, model, options=None, tools=None) -> str:
        self.chat_calls.append({"messages": messages, "model": model})
        return self.title_response

    async def stream_chat(
        self, messages, model, options=None, cancel_event=None, tools=None
    ) -> AsyncIterator[ChatChunk]:
        yield ChatChunk(content="answer", is_finished=False)
        yield ChatChunk(content="", is_finished=True, metadata={})

    async def list_models(self) -> list[ModelInfo]:  # pragma: no cover
        return []

    async def health_check(self) -> bool:  # pragma: no cover
        return True


async def test_generate_conversation_title_uses_provider():
    provider = _TitleProvider('"Rust Memory Management"\n')
    title = await generate_conversation_title(
        provider, "llama3.2", "how does ownership work in rust?", "Ownership is..."
    )
    assert title == "Rust Memory Management"
    assert provider.chat_calls[0]["model"] == "llama3.2"
    # The options/prompt should request a title from both sides of the turn.
    prompt = provider.chat_calls[0]["messages"][0].content
    assert "ownership" in prompt
    assert "Ownership is" in prompt


async def test_title_spawned_only_on_first_exchange(db_session, test_user_email):
    provider = _TitleProvider()
    ProviderRegistry.register(provider)
    service = ChatService(db_session, provider_name="title-test")

    conv = await ConversationService(db_session).create(
        user_id=test_user_email, title="raw first message"
    )
    conv.enabled_tools = []
    await db_session.commit()

    spawned: list[tuple] = []
    service._spawn_title_generation = (  # type: ignore[method-assign]
        lambda *args: spawned.append(args)
    )

    # First exchange → title generation spawned.
    async for _ in service.send_message(conv.id, test_user_email, "hello there"):
        pass
    assert len(spawned) == 1
    conversation_id, model, user_text, assistant_text = spawned[0]
    assert conversation_id == conv.id
    assert user_text == "hello there"
    assert assistant_text == "answer"

    # Second exchange → no new title.
    async for _ in service.send_message(conv.id, test_user_email, "and again"):
        pass
    assert len(spawned) == 1
