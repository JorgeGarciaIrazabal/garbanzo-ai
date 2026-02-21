"""Service for conversation CRUD operations."""

import logging
import uuid
from typing import Optional

from sqlalchemy import desc, func, select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.models.conversation import Conversation
from app.models.message import Message

logger = logging.getLogger(__name__)


class ConversationService:
    """Handles creation, retrieval, updating, and deletion of conversations.

    Decoupled from LLM provider details — messaging and streaming live in
    ``ChatService``.
    """

    def __init__(self, db: AsyncSession):
        self.db = db

    async def create(
        self,
        user_id: str,
        title: Optional[str] = None,
        model: str = "llama3.2",
        initial_message: Optional[str] = None,
    ) -> Conversation:
        conversation_id = str(uuid.uuid4())

        if title is None and initial_message:
            title = initial_message[:50] + ("..." if len(initial_message) > 50 else "")

        conversation = Conversation(
            id=conversation_id,
            user_id=user_id,
            title=title,
            model=model,
        )

        self.db.add(conversation)

        if initial_message:
            message = Message(
                id=str(uuid.uuid4()),
                conversation_id=conversation_id,
                role="user",
                content=initial_message,
            )
            self.db.add(message)

        await self.db.commit()

        result = await self.db.execute(
            select(Conversation)
            .where(Conversation.id == conversation_id)
            .options(selectinload(Conversation.messages))
        )
        conversation = result.scalar_one()

        logger.info("Created conversation %s for user %s", conversation_id, user_id)
        return conversation

    async def get(
        self,
        conversation_id: str,
        user_id: str,
        include_messages: bool = True,
    ) -> Optional[Conversation]:
        query = select(Conversation).where(
            Conversation.id == conversation_id,
            Conversation.user_id == user_id,
            Conversation.is_deleted == False,  # noqa: E712
        )

        if include_messages:
            query = query.options(selectinload(Conversation.messages))

        result = await self.db.execute(query)
        return result.scalar_one_or_none()

    async def list(
        self,
        user_id: str,
        page: int = 1,
        page_size: int = 20,
    ) -> tuple[list[Conversation], int]:
        count_query = select(func.count()).select_from(Conversation).where(
            Conversation.user_id == user_id,
            Conversation.is_deleted == False,  # noqa: E712
        )
        total_result = await self.db.execute(count_query)
        total = total_result.scalar() or 0

        query = (
            select(Conversation)
            .where(
                Conversation.user_id == user_id,
                Conversation.is_deleted == False,  # noqa: E712
            )
            .options(selectinload(Conversation.messages))
            .order_by(desc(Conversation.updated_at))
            .offset((page - 1) * page_size)
            .limit(page_size)
        )

        result = await self.db.execute(query)
        conversations = list(result.scalars().all())

        return conversations, total

    async def update(
        self,
        conversation_id: str,
        user_id: str,
        title: Optional[str] = None,
        model: Optional[str] = None,
    ) -> Optional[Conversation]:
        conversation = await self.get(conversation_id, user_id, include_messages=False)
        if not conversation:
            return None

        if title is not None:
            conversation.title = title
        if model is not None:
            conversation.model = model

        await self.db.commit()
        await self.db.refresh(conversation)

        return conversation

    async def delete(
        self,
        conversation_id: str,
        user_id: str,
        soft_delete: bool = True,
    ) -> bool:
        conversation = await self.get(conversation_id, user_id, include_messages=False)
        if not conversation:
            return False

        if soft_delete:
            conversation.is_deleted = True
            await self.db.commit()
        else:
            await self.db.delete(conversation)
            await self.db.commit()

        logger.info("Deleted conversation %s for user %s", conversation_id, user_id)
        return True
