"""Tests for ChatService — unit tests for helper methods and cancel_stream."""

import asyncio

from app.models.message import Message
from app.services.chat_context import ChatContextBuilder
from app.services.chat_service import ChatService
from app.services.llm_provider import Message as LLMMessage

# ============================================================================
# build_message_history
# ============================================================================


class TestBuildMessageHistory:
    """Tests for ChatContextBuilder.build_message_history (a pure-ish helper)."""

    def _make_msg(self, role: str, content: str, meta: dict | None = None) -> Message:
        """Create a minimal Message ORM object (no DB needed)."""
        return Message(
            id="fake-id",
            conversation_id="fake-conv",
            role=role,
            content=content,
            meta=meta,
        )

    def _build(self, messages):
        # build_message_history needs no services for the plain (no-prompt) path.
        return ChatContextBuilder(None, None, None).build_message_history(messages)

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

    def test_images_rehydrated_from_meta(self):
        msgs = [
            self._make_msg(
                "user",
                "with image",
                meta={
                    "attachments": [
                        {"name": "a.png", "type": "image", "data": "base64data1"},
                        {"name": "b.txt", "type": "document"},
                    ]
                },
            ),
            self._make_msg("assistant", "nice picture"),
            self._make_msg("user", "no image"),
        ]
        result = self._build(msgs)

        assert result[0].images == ["base64data1"]
        assert result[1].images is None
        assert result[2].images is None

    def test_image_meta_without_data_ignored(self):
        # Messages persisted before image data was stored in meta.
        msgs = [
            self._make_msg(
                "user",
                "legacy image",
                meta={"attachments": [{"name": "a.png", "type": "image"}]},
            )
        ]
        result = self._build(msgs)
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
