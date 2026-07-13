"""Regression tests for schema validation this codebase owns.

Framework-level Pydantic behavior (field assignment, defaults, ge/le bounds,
max_length) is intentionally not tested here — those can't fail unless
Pydantic itself breaks. What remains are custom validators and the Literal
guards that protect real wire contracts.
"""

from datetime import datetime

import pytest
from pydantic import ValidationError

from app.schemas.chat import AttachmentIn, ChatMessage, ChatMessageOut, ChatResponseChunk
from app.schemas.user import UserCreate


class TestUserCreate:
    def test_password_exceeds_72_bytes(self):
        """bcrypt silently truncates beyond 72 bytes — the schema must reject
        longer passwords instead of accepting a weaker secret than typed."""
        long_pw = "a" * 73
        with pytest.raises(ValidationError, match="72 bytes"):
            UserCreate(email="a@b.com", password=long_pw)


class TestChatMessage:
    def test_invalid_role(self):
        with pytest.raises(ValidationError):
            ChatMessage(role="admin", content="hi")


class TestChatMessageOut:
    @pytest.mark.parametrize("role", ["tool_call", "tool_result"])
    def test_accepts_tool_roles(self, role):
        """Regression: tool_call/tool_result rows must validate when serialized
        out via ChatMessageOut. Otherwise loading a conversation with tool
        activity 500s with a Pydantic literal_error."""
        msg = ChatMessageOut(
            id="msg-1",
            role=role,
            content="payload",
            created_at=datetime.now(),
            meta=None,
        )
        assert msg.role == role

    def test_rejects_unknown_role(self):
        with pytest.raises(ValidationError):
            ChatMessageOut(
                id="msg-1",
                role="admin",
                content="x",
                created_at=datetime.now(),
                meta=None,
            )


class TestAttachmentIn:
    def test_invalid_type(self):
        with pytest.raises(ValidationError):
            AttachmentIn(name="f", mime_type="x", type="video", data="d")


class TestChatResponseChunk:
    def test_invalid_type(self):
        with pytest.raises(ValidationError):
            ChatResponseChunk(type="invalid")
