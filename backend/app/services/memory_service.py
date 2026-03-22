"""Service for user memory CRUD operations."""

import logging
import uuid

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.memory import UserMemory

logger = logging.getLogger(__name__)


class MemoryService:
    """Handles creation, retrieval, update, and deletion of user memories."""

    def __init__(self, db: AsyncSession):
        self.db = db

    async def create_memory(
        self,
        user_id: str,
        content: str,
        source_conversation_id: str | None = None,
    ) -> UserMemory:
        """Create a new memory for a user."""
        memory = UserMemory(
            id=str(uuid.uuid4()),
            user_id=user_id,
            content=content,
            source_conversation_id=source_conversation_id,
        )

        self.db.add(memory)
        await self.db.commit()
        await self.db.refresh(memory)

        logger.info("Created memory %s for user %s", memory.id, user_id)
        return memory

    async def get_memory(self, memory_id: str, user_id: str) -> UserMemory | None:
        """Get a specific memory by ID, verifying ownership."""
        query = select(UserMemory).where(
            UserMemory.id == memory_id,
            UserMemory.user_id == user_id,
        )
        result = await self.db.execute(query)
        return result.scalar_one_or_none()

    async def get_active_memories(self, user_id: str) -> list[UserMemory]:
        """Get all active memories for a user."""
        query = UserMemory.active(user_id).order_by(UserMemory.created_at.desc())
        result = await self.db.execute(query)
        return list(result.scalars().all())

    async def get_relevant_memories(
        self,
        user_id: str,
        query: str | None = None,
        limit: int = 10,
    ) -> list[UserMemory]:
        """Get relevant active memories for a user.

        If a query is provided, performs a simple text search matching
        the query against memory content. Otherwise returns most recent
        active memories up to the limit.

        Args:
            user_id: The user ID to fetch memories for
            query: Optional search query to filter memories
            limit: Maximum number of memories to return

        Returns:
            List of active memories, filtered by query if provided
        """
        if query:
            # Simple text search: match query substring in content
            from sqlalchemy import or_

            query = select(UserMemory).where(
                UserMemory.user_id == user_id,
                UserMemory.is_active == True,  # noqa: E712
                or_(
                    UserMemory.content.ilike(f"%{query}%"),
                ),
            ).limit(limit)
        else:
            # Return most recent active memories
            query = (
                select(UserMemory)
                .where(
                    UserMemory.user_id == user_id,
                    UserMemory.is_active == True,  # noqa: E712
                )
                .order_by(UserMemory.created_at.desc())
                .limit(limit)
            )

        result = await self.db.execute(query)
        return list(result.scalars().all())

    async def update_memory(
        self,
        memory_id: str,
        user_id: str,
        content: str | None = None,
        is_active: bool | None = None,
    ) -> UserMemory | None:
        """Update a memory's content or active status."""
        memory = await self.get_memory(memory_id, user_id)
        if not memory:
            return None

        if content is not None:
            memory.content = content
        if is_active is not None:
            memory.is_active = is_active

        await self.db.commit()
        await self.db.refresh(memory)

        logger.info("Updated memory %s for user %s", memory_id, user_id)
        return memory

    async def deactivate_memory(self, memory_id: str, user_id: str) -> bool:
        """Soft-deactivate a memory by setting is_active=False."""
        memory = await self.get_memory(memory_id, user_id)
        if not memory:
            return False

        memory.is_active = False
        await self.db.commit()

        logger.info("Deactivated memory %s for user %s", memory_id, user_id)
        return True

    async def delete_memory(self, memory_id: str, user_id: str) -> bool:
        """Permanently delete a memory."""
        memory = await self.get_memory(memory_id, user_id)
        if not memory:
            return False

        await self.db.delete(memory)
        await self.db.commit()

        logger.info("Deleted memory %s for user %s", memory_id, user_id)
        return True
