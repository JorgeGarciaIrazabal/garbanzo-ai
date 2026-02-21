"""Service for sending messages and streaming LLM responses."""

import asyncio
import logging
import uuid
from collections.abc import AsyncIterator
from typing import Optional

from sqlalchemy import func
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.message import Message
from app.schemas.chat import ChatOptions, ModelInfo
from app.services.conversation_service import ConversationService
from app.services.llm_provider import ChatChunk, Message as LLMMessage, ProviderRegistry
from app.services.ollama_provider import OllamaProvider

logger = logging.getLogger(__name__)


class ChatService:
    """Handles sending messages and streaming LLM responses.

    Conversation CRUD is delegated to ``ConversationService``.
    """

    _active_streams: dict[str, asyncio.Event] = {}

    def __init__(self, db: AsyncSession, *, provider_name: str = "ollama"):
        self.db = db
        self._provider_name = provider_name
        self._conversations = ConversationService(db)
        self._ensure_default_provider()

    @classmethod
    def cancel_stream(cls, conversation_id: str) -> bool:
        """Signal an active stream to stop. Returns True if found."""
        event = cls._active_streams.get(conversation_id)
        if event:
            event.set()
            return True
        return False

    @property
    def conversations(self) -> ConversationService:
        return self._conversations

    def _ensure_default_provider(self) -> None:
        if "ollama" not in ProviderRegistry.list_providers():
            ProviderRegistry.register(OllamaProvider())

    def _get_provider(self) -> OllamaProvider:
        provider = ProviderRegistry.get(self._provider_name)
        if provider is None:
            raise ValueError(f"Unknown provider: {self._provider_name}")
        return provider  # type: ignore[return-value]

    async def send_message(
        self,
        conversation_id: str,
        user_id: str,
        content: str,
        options: Optional[ChatOptions] = None,
    ) -> AsyncIterator[ChatChunk]:
        """Save user message, stream LLM response, and persist the result."""
        conversation = await self._conversations.get(conversation_id, user_id)
        if not conversation:
            yield ChatChunk(
                content="Conversation not found",
                is_finished=True,
                metadata={"error": True, "error_type": "not_found"},
            )
            return

        user_message = Message(
            id=str(uuid.uuid4()),
            conversation_id=conversation_id,
            role="user",
            content=content,
            conversation=conversation,
        )
        self.db.add(user_message)
        await self.db.flush()

        conversation.updated_at = func.now()  # type: ignore[assignment]
        await self.db.flush()

        llm_messages = self._build_message_history(conversation.messages)

        provider = self._get_provider()
        opts = options or ChatOptions()

        full_response = ""
        metadata: Optional[dict] = None

        cancel_event = asyncio.Event()
        ChatService._active_streams[conversation_id] = cancel_event

        try:
            async for chunk in provider.stream_chat(
                messages=llm_messages,
                model=conversation.model,
                options=opts,
                cancel_event=cancel_event,
            ):
                if chunk.content:
                    full_response += chunk.content
                if chunk.is_finished:
                    metadata = chunk.metadata
                yield chunk

            if full_response:
                assistant_message = Message(
                    id=str(uuid.uuid4()),
                    conversation_id=conversation_id,
                    role="assistant",
                    content=full_response,
                    metadata=metadata,
                )
                self.db.add(assistant_message)
                await self.db.commit()

        except Exception as e:
            logger.exception("Error in chat streaming")
            yield ChatChunk(
                content=f"Error: {e}",
                is_finished=True,
                metadata={"error": True, "error_type": "streaming_error"},
            )
            await self.db.rollback()
        finally:
            ChatService._active_streams.pop(conversation_id, None)

    def _build_message_history(self, messages: list[Message]) -> list[LLMMessage]:
        return [LLMMessage(role=msg.role, content=msg.content) for msg in messages]

    async def list_available_models(self) -> list[ModelInfo]:
        provider = self._get_provider()
        models = await provider.list_models()

        return [
            ModelInfo(
                id=m.id,
                name=m.name,
                description=m.description,
                context_length=m.context_length,
                provider=self._provider_name,
            )
            for m in models
        ]

    async def health_check(self) -> dict[str, bool]:
        results = {}
        for name in ProviderRegistry.list_providers():
            provider = ProviderRegistry.get(name)
            if provider:
                results[name] = await provider.health_check()
        return results
