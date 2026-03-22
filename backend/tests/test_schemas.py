"""Tests for Pydantic schemas (auth, chat, user)."""

from datetime import datetime

import pytest
from pydantic import ValidationError

from app.schemas.auth import LoginRequest, TokenPayload, TokenResponse
from app.schemas.chat import (
    AttachmentIn,
    ChatMessage,
    ChatMessageOut,
    ChatOptions,
    ChatRequest,
    ChatResponseChunk,
    ConversationCreate,
    ConversationList,
    ConversationOut,
    ConversationUpdate,
    MessageMetadata,
    ModelInfo,
    ModelList,
)
from app.schemas.user import UserCreate, UserInDB, UserOut

# ============================================================================
# Auth schemas
# ============================================================================


class TestLoginRequest:
    def test_valid(self):
        req = LoginRequest(email="user@example.com", password="secret")
        assert req.email == "user@example.com"
        assert req.password == "secret"

    def test_invalid_email(self):
        with pytest.raises(ValidationError):
            LoginRequest(email="not-an-email", password="secret")

    def test_empty_password_rejected(self):
        with pytest.raises(ValidationError):
            LoginRequest(email="user@example.com", password="")


class TestTokenResponse:
    def test_defaults(self):
        resp = TokenResponse(access_token="abc123")
        assert resp.token_type == "bearer"


class TestTokenPayload:
    def test_fields(self):
        payload = TokenPayload(sub="user@example.com", exp=9999999999)
        assert payload.sub == "user@example.com"


# ============================================================================
# User schemas
# ============================================================================


class TestUserCreate:
    def test_valid(self):
        user = UserCreate(email="a@b.com", password="hunter2!")
        assert user.email == "a@b.com"

    def test_short_password(self):
        with pytest.raises(ValidationError):
            UserCreate(email="a@b.com", password="hi")

    def test_password_exceeds_72_bytes(self):
        long_pw = "a" * 73
        with pytest.raises(ValidationError, match="72 bytes"):
            UserCreate(email="a@b.com", password=long_pw)

    def test_full_name_max_length(self):
        with pytest.raises(ValidationError):
            UserCreate(email="a@b.com", password="hunter2!", full_name="x" * 101)

    def test_optional_full_name(self):
        user = UserCreate(email="a@b.com", password="hunter2!")
        assert user.full_name is None


class TestUserOut:
    def test_from_attributes(self):
        now = datetime.now()
        out = UserOut(email="a@b.com", created_at=now)
        assert out.email == "a@b.com"
        assert out.full_name is None


class TestUserInDB:
    def test_inherits_user_out(self):
        now = datetime.now()
        user = UserInDB(email="a@b.com", created_at=now, hashed_password="hashed")
        assert user.hashed_password == "hashed"


# ============================================================================
# Chat schemas
# ============================================================================


class TestChatOptions:
    def test_defaults(self):
        opts = ChatOptions()
        assert opts.temperature == 0.7
        assert opts.max_tokens is None
        assert opts.top_p is None
        assert opts.stream is True

    def test_temperature_bounds(self):
        ChatOptions(temperature=0.0)
        ChatOptions(temperature=2.0)
        with pytest.raises(ValidationError):
            ChatOptions(temperature=-0.1)
        with pytest.raises(ValidationError):
            ChatOptions(temperature=2.1)

    def test_top_p_bounds(self):
        ChatOptions(top_p=0.0)
        ChatOptions(top_p=1.0)
        with pytest.raises(ValidationError):
            ChatOptions(top_p=-0.1)
        with pytest.raises(ValidationError):
            ChatOptions(top_p=1.1)

    def test_max_tokens_minimum(self):
        ChatOptions(max_tokens=1)
        with pytest.raises(ValidationError):
            ChatOptions(max_tokens=0)


class TestChatMessage:
    def test_valid_roles(self):
        for role in ("user", "assistant", "system"):
            msg = ChatMessage(role=role, content="hi")
            assert msg.role == role

    def test_invalid_role(self):
        with pytest.raises(ValidationError):
            ChatMessage(role="admin", content="hi")


class TestChatMessageOut:
    def test_fields(self):
        now = datetime.now()
        msg = ChatMessageOut(
            id="msg-1", role="user", content="hello", created_at=now, meta=None
        )
        assert msg.id == "msg-1"


class TestChatRequest:
    def test_valid(self):
        req = ChatRequest(message="Hello!")
        assert req.message == "Hello!"
        assert req.attachments == []
        assert req.options.temperature == 0.7

    def test_empty_message_rejected(self):
        with pytest.raises(ValidationError):
            ChatRequest(message="")


class TestAttachmentIn:
    def test_valid_image(self):
        att = AttachmentIn(name="img.png", mime_type="image/png", type="image", data="base64data")
        assert att.type == "image"

    def test_valid_document(self):
        att = AttachmentIn(
            name="doc.txt", mime_type="text/plain", type="document", data="text content"
        )
        assert att.type == "document"

    def test_invalid_type(self):
        with pytest.raises(ValidationError):
            AttachmentIn(name="f", mime_type="x", type="video", data="d")


class TestChatResponseChunk:
    def test_chunk_type(self):
        chunk = ChatResponseChunk(type="chunk", content="hello")
        assert chunk.content == "hello"
        assert chunk.error is None

    def test_error_type(self):
        chunk = ChatResponseChunk(type="error", error="something broke")
        assert chunk.error == "something broke"

    def test_invalid_type(self):
        with pytest.raises(ValidationError):
            ChatResponseChunk(type="invalid")


# ============================================================================
# Conversation schemas
# ============================================================================


class TestConversationCreate:
    def test_defaults(self):
        conv = ConversationCreate()
        assert conv.model == "llama3.2"
        assert conv.title is None

    def test_title_max_length(self):
        ConversationCreate(title="x" * 200)
        with pytest.raises(ValidationError):
            ConversationCreate(title="x" * 201)

    def test_model_max_length(self):
        with pytest.raises(ValidationError):
            ConversationCreate(model="x" * 101)


class TestConversationUpdate:
    def test_partial_update(self):
        update = ConversationUpdate(title="New Title")
        assert update.title == "New Title"
        assert update.model is None


class TestConversationOut:
    def test_fields(self):
        now = datetime.now()
        out = ConversationOut(
            id="conv-1", model="llama3.2", created_at=now, updated_at=now
        )
        assert out.id == "conv-1"
        assert out.message_count == 0


class TestConversationList:
    def test_fields(self):
        now = datetime.now()
        conv = ConversationOut(id="c1", model="llama3.2", created_at=now, updated_at=now)
        cl = ConversationList(items=[conv], total=1, page=1, page_size=20)
        assert cl.total == 1
        assert len(cl.items) == 1


# ============================================================================
# Model Info schemas
# ============================================================================


class TestModelInfo:
    def test_valid(self):
        info = ModelInfo(id="llama3.2", name="Llama 3.2")
        assert info.provider == "ollama"

    def test_optional_fields(self):
        info = ModelInfo(id="x", name="X")
        assert info.description is None
        assert info.context_length is None


class TestModelList:
    def test_valid(self):
        ml = ModelList(models=[ModelInfo(id="m1", name="Model 1")])
        assert len(ml.models) == 1


# ============================================================================
# MessageMetadata schema
# ============================================================================


class TestMessageMetadata:
    def test_all_none(self):
        meta = MessageMetadata()
        assert meta.tokens_generated is None
        assert meta.thinking is None

    def test_valid_values(self):
        meta = MessageMetadata(tokens_generated=100, tokens_prompt=50, total_duration_ns=1000000)
        assert meta.tokens_generated == 100

    def test_negative_tokens_rejected(self):
        with pytest.raises(ValidationError):
            MessageMetadata(tokens_generated=-1)

    def test_negative_duration_rejected(self):
        with pytest.raises(ValidationError):
            MessageMetadata(total_duration_ns=-1)
