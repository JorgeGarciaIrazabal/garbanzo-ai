"""Tests for ChatService — unit tests for helper methods and cancel_stream."""

import asyncio

from app.models.message import Message
from app.services.chat_service import ChatService
from app.services.llm_provider import Message as LLMMessage

# ============================================================================
# _build_message_history
# ============================================================================


class TestBuildMessageHistory:
    """Tests for ChatService._build_message_history (a pure-ish helper)."""

    def _make_msg(self, role: str, content: str) -> Message:
        """Create a minimal Message ORM object (no DB needed)."""
        return Message(
            id="fake-id",
            conversation_id="fake-conv",
            role=role,
            content=content,
        )

    def _build(self, messages, images=None):
        # _build_message_history is an instance method; create a minimal instance.
        service = ChatService.__new__(ChatService)
        return service._build_message_history(messages, images)

    def test_single_message(self):
        msgs = [self._make_msg("user", "hello")]
        result = self._build(msgs)
        assert len(result) == 1
        assert isinstance(result[0], LLMMessage)
        assert result[0].role == "user"
        assert result[0].content == "hello"
        assert result[0].images is None

    def test_multiple_messages(self):
        msgs = [
            self._make_msg("user", "hi"),
            self._make_msg("assistant", "hello!"),
            self._make_msg("user", "how are you?"),
        ]
        result = self._build(msgs)
        assert len(result) == 3
        assert result[0].role == "user"
        assert result[1].role == "assistant"
        assert result[2].role == "user"

    def test_images_attached_to_last_message_only(self):
        msgs = [
            self._make_msg("user", "first"),
            self._make_msg("user", "second with image"),
        ]
        images = ["base64data1", "base64data2"]
        result = self._build(msgs, images)

        assert result[0].images is None
        assert result[1].images == images

    def test_empty_images_list_not_attached(self):
        msgs = [self._make_msg("user", "hi")]
        result = self._build(msgs, [])
        assert result[0].images is None

    def test_no_messages(self):
        result = self._build([])
        assert result == []


# ============================================================================
# cancel_stream
# ============================================================================


class TestCancelStream:
    def setup_method(self):
        # Clear class-level dict between tests
        ChatService._active_streams.clear()

    def test_cancel_existing_stream(self):
        event = asyncio.Event()
        ChatService._active_streams["conv-1"] = event
        assert ChatService.cancel_stream("conv-1") is True
        assert event.is_set()

    def test_cancel_nonexistent_stream(self):
        assert ChatService.cancel_stream("no-such-conv") is False

    def test_cancel_does_not_affect_other_streams(self):
        event1 = asyncio.Event()
        event2 = asyncio.Event()
        ChatService._active_streams["conv-1"] = event1
        ChatService._active_streams["conv-2"] = event2

        ChatService.cancel_stream("conv-1")
        assert event1.is_set()
        assert not event2.is_set()
