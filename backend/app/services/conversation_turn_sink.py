"""Persists an agent turn's output (assistant/tool_call/tool_result) as Messages."""

import json
import uuid

from sqlalchemy.ext.asyncio import AsyncSession

from app.models.message import Message


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
            # Keep the in-session relationship collection in sync
            # (raw FK writes don't update conversation.messages),
            # so a later turn on the same session sees this one.
            conversation=self.conversation,
        )
        self.db.add(message)
        await self.db.flush()

    async def persist_tool_call(self, tool_calls: list[dict]) -> None:
        self.db.add(
            Message(
                id=str(uuid.uuid4()),
                conversation_id=self.conversation.id,
                role="tool_call",
                content=json.dumps(tool_calls),
                meta={"tool_calls": tool_calls},
            )
        )
        await self.db.flush()

    async def persist_tool_result(self, content: str, meta: dict) -> None:
        self.db.add(
            Message(
                id=str(uuid.uuid4()),
                conversation_id=self.conversation.id,
                role="tool_result",
                content=content,
                meta=meta,
            )
        )
        await self.db.flush()

    async def commit(self) -> None:
        await self.db.commit()

    async def rollback(self) -> None:
        await self.db.rollback()
