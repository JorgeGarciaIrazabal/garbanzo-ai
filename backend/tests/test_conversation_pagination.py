"""Tests for windowed message loading (B-03).

Messages persisted in the same DB transaction commonly share an identical
``created_at`` (Postgres ``now()`` is transaction-start time), so ordering
must key off ``Message.seq`` — these tests deliberately give every message
the *same* ``created_at`` to prove ``created_at`` alone can't be trusted.
"""

from datetime import UTC, datetime

import pytest
import pytest_asyncio
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.message import Message
from app.services.conversation_service import ConversationService

pytestmark = pytest.mark.asyncio

USER_ID = "test@example.com"
SAME_INSTANT = datetime(2026, 1, 1, tzinfo=UTC)


@pytest_asyncio.fixture()
async def service(db_session: AsyncSession) -> ConversationService:
    return ConversationService(db_session)


async def _seed(service: ConversationService, db_session: AsyncSession, count: int):
    """Create a conversation with ``count`` messages, all sharing one
    timestamp but with distinct, ordered ``seq`` values."""
    conv = await service.create(USER_ID, title="Long chat")
    for i in range(count):
        db_session.add(
            Message(
                id=f"m{i}",
                conversation_id=conv.id,
                role="user" if i % 2 == 0 else "assistant",
                content=f"message {i}",
                created_at=SAME_INSTANT,
                seq=i,
            )
        )
    await db_session.commit()
    return conv


class TestGetRecentMessages:
    async def test_returns_the_last_n_in_chronological_order(
        self, service: ConversationService, db_session: AsyncSession
    ):
        conv = await _seed(service, db_session, 10)

        messages, total, has_more = await service.get_recent_messages(conv.id, limit=3)

        assert total == 10
        assert has_more is True
        assert [m.content for m in messages] == ["message 7", "message 8", "message 9"]

    async def test_no_more_when_the_limit_covers_everything(
        self, service: ConversationService, db_session: AsyncSession
    ):
        conv = await _seed(service, db_session, 3)

        messages, total, has_more = await service.get_recent_messages(conv.id, limit=50)

        assert total == 3
        assert has_more is False
        assert [m.content for m in messages] == ["message 0", "message 1", "message 2"]

    async def test_identical_created_at_does_not_break_ordering(
        self, service: ConversationService, db_session: AsyncSession
    ):
        # Every message here has the exact same created_at — only seq
        # distinguishes them. If ordering fell back to created_at, this
        # would return messages in an arbitrary (DB-dependent) order.
        conv = await _seed(service, db_session, 5)

        messages, _, _ = await service.get_recent_messages(conv.id, limit=5)

        assert [m.seq for m in messages] == [0, 1, 2, 3, 4]


class TestGetMessagesBefore:
    async def test_pages_in_older_messages(
        self, service: ConversationService, db_session: AsyncSession
    ):
        conv = await _seed(service, db_session, 10)

        page, has_more = await service.get_messages_before(conv.id, "m7", limit=3)

        assert has_more is True
        assert [m.content for m in page] == ["message 4", "message 5", "message 6"]

    async def test_reaches_the_start_with_no_more(
        self, service: ConversationService, db_session: AsyncSession
    ):
        conv = await _seed(service, db_session, 5)

        page, has_more = await service.get_messages_before(conv.id, "m2", limit=50)

        assert has_more is False
        assert [m.content for m in page] == ["message 0", "message 1"]

    async def test_unknown_anchor_returns_empty(
        self, service: ConversationService, db_session: AsyncSession
    ):
        conv = await _seed(service, db_session, 3)

        page, has_more = await service.get_messages_before(conv.id, "does-not-exist")

        assert page == []
        assert has_more is False
