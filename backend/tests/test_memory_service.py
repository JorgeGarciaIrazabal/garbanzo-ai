"""Tests for MemoryService — user memory CRUD operations."""

import pytest

from app.services.memory_service import MemoryService

pytestmark = pytest.mark.asyncio


class TestMemoryService:
    """Tests for MemoryService CRUD operations."""

    async def test_create_memory(self, db_session, test_user_email):
        """Test creating a new memory."""
        service = MemoryService(db_session)

        memory = await service.create_memory(
            user_id=test_user_email,
            content="User prefers Python for backend development",
        )

        assert memory.id is not None
        assert memory.user_id == test_user_email
        assert memory.content == "User prefers Python for backend development"
        assert memory.is_active is True
        assert memory.source_conversation_id is None

    async def test_create_memory_with_source_conversation(
        self, db_session, test_user_email, test_conversation
    ):
        """Test creating a memory linked to a source conversation."""
        service = MemoryService(db_session)

        memory = await service.create_memory(
            user_id=test_user_email,
            content="User is working on a FastAPI project",
            source_conversation_id=test_conversation.id,
        )

        assert memory.source_conversation_id == test_conversation.id

    async def test_get_active_memories(self, db_session, test_user_email):
        """Test retrieving all active memories for a user."""
        service = MemoryService(db_session)

        # Create multiple memories
        await service.create_memory(
            user_id=test_user_email,
            content="Memory 1",
        )
        await service.create_memory(
            user_id=test_user_email,
            content="Memory 2",
        )
        await service.create_memory(
            user_id=test_user_email,
            content="Memory 3",
        )

        memories = await service.get_active_memories(user_id=test_user_email)

        assert len(memories) == 3
        assert all(m.is_active for m in memories)
        assert all(m.user_id == test_user_email for m in memories)

    async def test_get_memory(self, db_session, test_user_email):
        """Test retrieving a specific memory by ID."""
        service = MemoryService(db_session)

        memory = await service.create_memory(
            user_id=test_user_email,
            content="Test memory content",
        )

        fetched = await service.get_memory(memory_id=memory.id, user_id=test_user_email)

        assert fetched is not None
        assert fetched.id == memory.id
        assert fetched.content == "Test memory content"

    async def test_get_memory_wrong_user(self, db_session, test_user_email):
        """Test that a user cannot access another user's memory."""
        service = MemoryService(db_session)

        memory = await service.create_memory(
            user_id=test_user_email,
            content="Secret memory",
        )

        # Try to fetch with different user email
        fetched = await service.get_memory(
            memory_id=memory.id,
            user_id="other@example.com",
        )

        assert fetched is None

    async def test_deactivate_memory(self, db_session, test_user_email):
        """Test soft-deactivating a memory."""
        service = MemoryService(db_session)

        memory = await service.create_memory(
            user_id=test_user_email,
            content="To be deactivated",
        )

        result = await service.deactivate_memory(
            memory_id=memory.id,
            user_id=test_user_email,
        )

        assert result is True

        # Verify memory is now inactive
        fetched = await service.get_memory(memory_id=memory.id, user_id=test_user_email)
        assert fetched is not None
        assert fetched.is_active is False

        # Verify it's not in active memories list
        active = await service.get_active_memories(user_id=test_user_email)
        assert memory.id not in [m.id for m in active]

    async def test_deactivate_nonexistent_memory(self, db_session, test_user_email):
        """Test deactivating a memory that doesn't exist."""
        service = MemoryService(db_session)

        result = await service.deactivate_memory(
            memory_id="nonexistent-id",
            user_id=test_user_email,
        )

        assert result is False

    async def test_delete_memory(self, db_session, test_user_email):
        """Test permanently deleting a memory."""
        service = MemoryService(db_session)

        memory = await service.create_memory(
            user_id=test_user_email,
            content="To be deleted",
        )

        result = await service.delete_memory(
            memory_id=memory.id,
            user_id=test_user_email,
        )

        assert result is True

        # Verify memory is gone
        fetched = await service.get_memory(memory_id=memory.id, user_id=test_user_email)
        assert fetched is None

    async def test_delete_nonexistent_memory(self, db_session, test_user_email):
        """Test deleting a memory that doesn't exist."""
        service = MemoryService(db_session)

        result = await service.delete_memory(
            memory_id="nonexistent-id",
            user_id=test_user_email,
        )

        assert result is False
