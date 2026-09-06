"""Persists an agent turn's output (assistant/tool_call/tool_result) as Messages."""

import json
import uuid

from sqlalchemy.ext.asyncio import AsyncSession

from app.models.message import Message
from app.topics.topic_ingestion_service import (
    TopicIngestionService,
    enqueue_message_event,
)


class ConversationTurnSink:
    """``TurnSink`` writing a turn's output to a conversation's ``Message`` rows."""

    def __init__(self, db: AsyncSession, conversation):
        self.db = db
        self.conversation = conversation

    async def persist_assistant(self, content: str, meta: dict | None) -> None:
        message = Message(
            id=str(uuid.uuid4()),
            conversation_id=self.conversation.id,
            role="assistant",
            content=content,
            meta=meta,
            session_epoch=self.conversation.session_epoch,
            # Keep the in-session relationship collection in sync
            # (raw FK writes don't update conversation.messages),
            # so a later turn on the same session sees this one.
            conversation=self.conversation,
        )
        self.db.add(message)
        await self.db.flush()
        event = await enqueue_message_event(self.db, self.conversation, message, "create")
        await TopicIngestionService(self.db).process_event(event)

    async def persist_tool_call(self, tool_calls: list[dict]) -> None:
        message = Message(
            id=str(uuid.uuid4()),
            conversation_id=self.conversation.id,
            role="tool_call",
            content=json.dumps(tool_calls),
            meta={"tool_calls": tool_calls},
            session_epoch=self.conversation.session_epoch,
            conversation=self.conversation,
        )
        self.db.add(message)
        await self.db.flush()
        event = await enqueue_message_event(self.db, self.conversation, message, "create")
        await TopicIngestionService(self.db).process_event(event)

    async def persist_tool_result(self, content: str, meta: dict) -> None:
        message = Message(
            id=str(uuid.uuid4()),
            conversation_id=self.conversation.id,
            role="tool_result",
            content=content,
            meta=meta,
            session_epoch=self.conversation.session_epoch,
            conversation=self.conversation,
        )
        self.db.add(message)
        await self.db.flush()
        event = await enqueue_message_event(self.db, self.conversation, message, "create")
        await TopicIngestionService(self.db).process_event(event)

    async def commit(self) -> None:
        await self.db.commit()

    async def rollback(self) -> None:
        await self.db.rollback()
