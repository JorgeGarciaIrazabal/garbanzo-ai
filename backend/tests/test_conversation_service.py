"""Tests for ConversationService (async, backed by in-memory SQLite)."""

import uuid

import pytest
import pytest_asyncio
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.security import hash_password
from app.models.message import Message
from app.models.user import User
from app.services.conversation_service import ConversationService, _build_snippet

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
        assert conv.model == "minimax-m3:cloud"
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


# ============================================================================
# Search
# ============================================================================


async def _add_message(
    db: AsyncSession,
    conversation_id: str,
    role: str,
    content: str,
) -> Message:
    msg = Message(
        id=str(uuid.uuid4()),
        conversation_id=conversation_id,
        role=role,
        content=content,
    )
    db.add(msg)
    await db.commit()
    await db.refresh(msg)
    return msg


class TestSearch:
    async def test_empty_query_returns_empty(self, service: ConversationService):
        await service.create(USER_ID, title="Hello World")
        hits, total = await service.search(USER_ID, "")
        assert hits == []
        assert total == 0

    async def test_whitespace_only_query_returns_empty(self, service: ConversationService):
        await service.create(USER_ID, title="Hello World")
        hits, total = await service.search(USER_ID, "   ")
        assert hits == []
        assert total == 0

    async def test_matches_title_case_insensitive(self, service: ConversationService):
        await service.create(USER_ID, title="Project Alpha Notes")
        await service.create(USER_ID, title="Unrelated Conversation")

        hits, total = await service.search(USER_ID, "alpha")
        assert total == 1
        assert len(hits) == 1
        assert hits[0].conversation.title == "Project Alpha Notes"
        assert hits[0].matched_messages == []

    async def test_matches_message_content(
        self, service: ConversationService, db_session: AsyncSession
    ):
        conv = await service.create(USER_ID, title="Random Title")
        await _add_message(db_session, conv.id, "user", "Tell me about kubernetes operators")
        await _add_message(db_session, conv.id, "assistant", "Operators extend the API.")

        hits, total = await service.search(USER_ID, "kubernetes")
        assert total == 1
        assert len(hits) == 1
        assert hits[0].conversation.id == conv.id
        assert len(hits[0].matched_messages) == 1
        assert "kubernetes" in hits[0].matched_messages[0].content.lower()

    async def test_matches_both_title_and_message(
        self, service: ConversationService, db_session: AsyncSession
    ):
        conv = await service.create(USER_ID, title="Docker tips")
        await _add_message(db_session, conv.id, "user", "What is docker compose?")
        await _add_message(db_session, conv.id, "assistant", "It orchestrates containers.")

        hits, total = await service.search(USER_ID, "docker")
        assert total == 1
        # Both messages containing "docker" should be attached.
        contents = {m.content for m in hits[0].matched_messages}
        assert "What is docker compose?" in contents

    async def test_user_isolation(self, service: ConversationService, db_session: AsyncSession):
        # Create a second user and a conversation belonging to them.
        other = User(
            email="other@example.com",
            hashed_password=hash_password("pw"),
        )
        db_session.add(other)
        await db_session.commit()

        other_service = ConversationService(db_session)
        other_conv = await other_service.create(
            "other@example.com", title="Secret topic from other user"
        )
        await _add_message(db_session, other_conv.id, "user", "Private payload mentioning topic")

        await service.create(USER_ID, title="My own topic notes")

        # USER_ID must only see their own conversation.
        hits, total = await service.search(USER_ID, "topic")
        assert total == 1
        assert hits[0].conversation.user_id == USER_ID
        assert hits[0].conversation.title == "My own topic notes"

    async def test_no_results(self, service: ConversationService):
        await service.create(USER_ID, title="Hello")
        hits, total = await service.search(USER_ID, "nonexistent-term-xyz")
        assert total == 0
        assert hits == []

    async def test_excludes_soft_deleted(
        self, service: ConversationService, db_session: AsyncSession
    ):
        keep = await service.create(USER_ID, title="python tricks")
        drop = await service.create(USER_ID, title="python gone")
        await service.delete(drop.id, USER_ID, soft_delete=True)

        hits, total = await service.search(USER_ID, "python")
        assert total == 1
        assert hits[0].conversation.id == keep.id

    async def test_special_characters_do_not_break_search(
        self, service: ConversationService, db_session: AsyncSession
    ):
        conv = await service.create(USER_ID, title="Report 100% done")
        await _add_message(db_session, conv.id, "user", "Summary_with_underscores and 50% progress")

        # '%' should be treated literally, not as a LIKE wildcard.
        hits, total = await service.search(USER_ID, "100%")
        assert total == 1
        assert hits[0].conversation.id == conv.id

        # Another conversation that shouldn't match when '%' is literal.
        await service.create(USER_ID, title="No numeric data")
        hits2, total2 = await service.search(USER_ID, "100%")
        assert total2 == 1

        # Underscore is a LIKE wildcard too — ensure literal matching.
        hits3, total3 = await service.search(USER_ID, "Summary_with")
        assert total3 == 1

    async def test_pagination(self, service: ConversationService):
        for i in range(5):
            await service.create(USER_ID, title=f"python topic {i}")

        page1, total = await service.search(USER_ID, "python", page=1, page_size=2)
        assert total == 5
        assert len(page1) == 2

        page3, _ = await service.search(USER_ID, "python", page=3, page_size=2)
        assert len(page3) == 1


@pytest.mark.asyncio
async def test_build_snippet_returns_empty_for_empty_content():
    assert _build_snippet("", "anything") == ""


@pytest.mark.asyncio
async def test_build_snippet_trims_context_around_match():
    content = "a" * 200 + "MATCH" + "b" * 200
    out = _build_snippet(content, "MATCH", context=20)
    assert "MATCH" in out
    assert out.startswith("...")
    assert out.endswith("...")


@pytest.mark.asyncio
async def test_build_snippet_no_ellipsis_when_match_at_edges():
    out = _build_snippet("hello world", "hello", context=100)
    assert out == "hello world"


@pytest.mark.asyncio
async def test_build_snippet_case_insensitive():
    out = _build_snippet("The Docker Engine", "docker", context=5)
    assert "Docker" in out


@pytest.mark.asyncio
async def test_build_snippet_fallback_when_query_not_found():
    out = _build_snippet("some content", "xyz", context=5)
    # Falls back to head of content.
    assert out.startswith("some content") or out.startswith("some ")
