"""Service for conversation CRUD operations."""

from __future__ import annotations

import logging
import uuid

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
        title: str | None = None,
        model: str = "llama3.2",
        initial_message: str | None = None,
        system_prompt: str | None = None,
    ) -> Conversation:
        conversation_id = str(uuid.uuid4())

        if title is None and initial_message:
            title = initial_message[:50] + ("..." if len(initial_message) > 50 else "")

        conversation = Conversation(
            id=conversation_id,
            user_id=user_id,
            title=title,
            model=model,
            system_prompt=system_prompt,
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
    ) -> Conversation | None:
        query = Conversation.active(user_id).where(Conversation.id == conversation_id)

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
        base = Conversation.active(user_id)
        count_query = select(func.count()).select_from(base.subquery())
        total_result = await self.db.execute(count_query)
        total = total_result.scalar() or 0

        query = (
            base.options(selectinload(Conversation.messages))
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
        title: str | None = None,
        model: str | None = None,
        use_memory: bool | None = None,
        system_prompt: str | None = None,
        clear_system_prompt: bool = False,
        enabled_tools: list[str] | None = None,
        set_enabled_tools: bool = False,
        clear_enabled_tools: bool = False,
    ) -> Conversation | None:
        conversation = await self.get(conversation_id, user_id, include_messages=False)
        if not conversation:
            return None

        if title is not None:
            conversation.title = title
        if model is not None:
            conversation.model = model
        if use_memory is not None:
            conversation.use_memory = use_memory
        if clear_system_prompt:
            conversation.system_prompt = None
        elif system_prompt is not None:
            conversation.system_prompt = system_prompt or None

        # enabled_tools has three-way semantics:
        #   clear_enabled_tools=True → set column to NULL ("all tools")
        #   set_enabled_tools=True   → use ``enabled_tools`` verbatim ([] means no tools)
        #   neither                   → leave unchanged
        if clear_enabled_tools:
            conversation.enabled_tools = None
        elif set_enabled_tools:
            conversation.enabled_tools = enabled_tools

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
