"""Service for sending messages and streaming LLM responses."""

import asyncio
import logging
import uuid
from collections.abc import AsyncIterator

from sqlalchemy import func
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import get_settings
from app.models.message import Message
from app.schemas.chat import AttachmentIn, ChatOptions, ModelInfo
from app.services.conversation_service import ConversationService
from app.services.llm_provider import ChatChunk, LLMProvider, ProviderRegistry
from app.services.llm_provider import Message as LLMMessage
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
            settings = get_settings()
            ProviderRegistry.register(OllamaProvider(base_url=settings.ollama_base_url))

    def _get_provider(self) -> LLMProvider:
        provider = ProviderRegistry.get(self._provider_name)
        if provider is None:
            raise ValueError(f"Unknown provider: {self._provider_name}")
        return provider

    async def send_message(
        self,
        conversation_id: str,
        user_id: str,
        content: str,
        options: ChatOptions | None = None,
        attachments: list[AttachmentIn] | None = None,
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

        # Build the content that goes into the DB (append document text inline)
        stored_content = content
        attachment_meta: list[dict] = []
        image_b64_list: list[str] = []

        if attachments:
            doc_texts: list[str] = []
            for att in attachments:
                attachment_meta.append(
                    {"name": att.name, "mime_type": att.mime_type, "type": att.type}
                )
                if att.type == "image":
                    image_b64_list.append(att.data)
                elif att.type == "document" and att.data:
                    doc_texts.append(f"[Attached file: {att.name}]\n{att.data}")

            if doc_texts:
                stored_content = content + "\n\n" + "\n\n".join(doc_texts)

        user_message = Message(
            id=str(uuid.uuid4()),
            conversation_id=conversation_id,
            role="user",
            content=stored_content,
            meta={"attachments": attachment_meta} if attachment_meta else None,
            conversation=conversation,
        )
        self.db.add(user_message)
        await self.db.flush()

        conversation.updated_at = func.now()  # type: ignore[assignment]
        await self.db.flush()

        llm_messages = self._build_message_history(conversation.messages, image_b64_list)

        provider = self._get_provider()
        opts = options or ChatOptions()

        full_response = ""
        thinking_content = ""
        metadata: dict | None = None

        cancel_event = asyncio.Event()
        ChatService._active_streams[conversation_id] = cancel_event

        try:
            async for chunk in provider.stream_chat(
                messages=llm_messages,
                model=conversation.model,
                options=opts,
                cancel_event=cancel_event,
            ):
                if chunk.is_thinking:
                    thinking_content += chunk.content
                elif chunk.content:
                    full_response += chunk.content
                if chunk.is_finished:
                    metadata = chunk.metadata
                yield chunk

            if full_response:
                msg_meta = dict(metadata) if metadata else {}
                if thinking_content:
                    msg_meta["thinking"] = thinking_content
                assistant_message = Message(
                    id=str(uuid.uuid4()),
                    conversation_id=conversation_id,
                    role="assistant",
                    content=full_response,
                    meta=msg_meta or None,
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

    def _build_message_history(
        self,
        messages: list[Message],
        pending_images: list[str] | None = None,
    ) -> list[LLMMessage]:
        result: list[LLMMessage] = []
        for i, msg in enumerate(messages):
            is_last = i == len(messages) - 1
            images = pending_images if (is_last and pending_images) else None
            result.append(LLMMessage(role=msg.role, content=msg.content, images=images))
        return result

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
