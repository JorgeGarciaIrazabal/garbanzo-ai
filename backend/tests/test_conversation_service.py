"""Tests for ConversationService (async, backed by in-memory SQLite)."""

import pytest
import pytest_asyncio
from sqlalchemy.ext.asyncio import AsyncSession

from app.services.conversation_service import ConversationService

pytestmark = pytest.mark.asyncio


@pytest_asyncio.fixture()
async def service(db_session: AsyncSession) -> ConversationService:
    return ConversationService(db_session)


USER_ID = "test@example.com"


# ============================================================================
# Create
# ============================================================================


class TestCreate:
    async def test_basic_creation(self, service: ConversationService):
        conv = await service.create(USER_ID, title="Hello")
        assert conv.id is not None
        assert conv.title == "Hello"
        assert conv.model == "llama3.2"
        assert conv.user_id == USER_ID

    async def test_auto_title_from_initial_message(self, service: ConversationService):
        msg = "A" * 60
        conv = await service.create(USER_ID, initial_message=msg)
        assert conv.title == msg[:50] + "..."

    async def test_short_initial_message_title_no_ellipsis(self, service: ConversationService):
        conv = await service.create(USER_ID, initial_message="Short msg")
        assert conv.title == "Short msg"

    async def test_initial_message_creates_first_message(self, service: ConversationService):
        conv = await service.create(USER_ID, initial_message="Hi there")
        assert len(conv.messages) == 1
        assert conv.messages[0].role == "user"
        assert conv.messages[0].content == "Hi there"

    async def test_no_initial_message(self, service: ConversationService):
        conv = await service.create(USER_ID, title="Empty")
        assert len(conv.messages) == 0

    async def test_custom_model(self, service: ConversationService):
        conv = await service.create(USER_ID, model="gpt-4")
        assert conv.model == "gpt-4"


# ============================================================================
# Get
# ============================================================================


class TestGet:
    async def test_returns_conversation(self, service: ConversationService):
        conv = await service.create(USER_ID, title="Find me")
        found = await service.get(conv.id, USER_ID)
        assert found is not None
        assert found.title == "Find me"

    async def test_wrong_user_returns_none(self, service: ConversationService):
        conv = await service.create(USER_ID, title="Private")
        found = await service.get(conv.id, "other@example.com")
        assert found is None

    async def test_soft_deleted_not_returned(self, service: ConversationService):
        conv = await service.create(USER_ID, title="Deletable")
        await service.delete(conv.id, USER_ID, soft_delete=True)
        found = await service.get(conv.id, USER_ID)
        assert found is None

    async def test_nonexistent_id(self, service: ConversationService):
        found = await service.get("nonexistent-id", USER_ID)
        assert found is None


# ============================================================================
# List
# ============================================================================


class TestList:
    async def test_empty_list(self, service: ConversationService):
        conversations, total = await service.list(USER_ID)
        assert total == 0
        assert conversations == []

    async def test_pagination(self, service: ConversationService):
        for i in range(5):
            await service.create(USER_ID, title=f"Conv {i}")

        page1, total = await service.list(USER_ID, page=1, page_size=2)
        assert total == 5
        assert len(page1) == 2

        page3, _ = await service.list(USER_ID, page=3, page_size=2)
        assert len(page3) == 1  # 5 items, page_size 2, page 3 = 1 item

    async def test_excludes_soft_deleted(self, service: ConversationService):
        conv = await service.create(USER_ID, title="Will delete")
        await service.create(USER_ID, title="Keep")
        await service.delete(conv.id, USER_ID, soft_delete=True)

        conversations, total = await service.list(USER_ID)
        assert total == 1
        assert conversations[0].title == "Keep"


# ============================================================================
# Update
# ============================================================================


class TestUpdate:
    async def test_update_title(self, service: ConversationService):
        conv = await service.create(USER_ID, title="Old")
        updated = await service.update(conv.id, USER_ID, title="New")
        assert updated is not None
        assert updated.title == "New"

    async def test_update_model(self, service: ConversationService):
        conv = await service.create(USER_ID)
        updated = await service.update(conv.id, USER_ID, model="mistral")
        assert updated is not None
        assert updated.model == "mistral"

    async def test_update_nonexistent(self, service: ConversationService):
        result = await service.update("no-such-id", USER_ID, title="X")
        assert result is None

    async def test_partial_update_preserves_other_fields(self, service: ConversationService):
        conv = await service.create(USER_ID, title="Keep", model="llama3.2")
        updated = await service.update(conv.id, USER_ID, title="Changed")
        assert updated.model == "llama3.2"


# ============================================================================
# Delete
# ============================================================================


class TestDelete:
    async def test_soft_delete(self, service: ConversationService):
        conv = await service.create(USER_ID, title="Soft")
        result = await service.delete(conv.id, USER_ID, soft_delete=True)
        assert result is True

        # Should not be found via get (which filters deleted)
        assert await service.get(conv.id, USER_ID) is None

    async def test_hard_delete(self, service: ConversationService):
        conv = await service.create(USER_ID, title="Hard")
        result = await service.delete(conv.id, USER_ID, soft_delete=False)
        assert result is True
        assert await service.get(conv.id, USER_ID) is None

    async def test_delete_nonexistent(self, service: ConversationService):
        result = await service.delete("no-such-id", USER_ID)
        assert result is False

    async def test_delete_wrong_user(self, service: ConversationService):
        conv = await service.create(USER_ID, title="Mine")
        result = await service.delete(conv.id, "other@example.com")
        assert result is False
