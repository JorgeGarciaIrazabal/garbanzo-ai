"""Service for sending messages and streaming LLM responses."""

import asyncio
import base64
import io
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
from app.services.memory_service import MemoryService
from app.services.ollama_provider import OllamaProvider

logger = logging.getLogger(__name__)


async def _extract_pdf_text(data: str) -> str:
    """Extract text from a base64-encoded PDF."""
    try:
        from pypdf import PdfReader

        pdf_bytes = base64.b64decode(data)
        reader = PdfReader(io.BytesIO(pdf_bytes))
        text_pages = []
        for page in reader.pages:
            text = page.extract_text()
            if text:
                text_pages.append(text)
        return "\n".join(text_pages) if text_pages else "[PDF: no extractable text]"
    except Exception as e:
        logger.warning("PDF extraction failed: %s", e)
        return f"[PDF extraction error: {e}]"


async def _extract_csv_text(data: str, filename: str) -> str:
    """Extract and summarize CSV content."""
    text_bytes = base64.b64decode(data)
    text_content = text_bytes.decode("utf-8", errors="replace")
    lines = text_content.splitlines()
    row_count = len(lines)
    summary = f"[CSV: {filename}, {row_count} rows]\n"
    if row_count <= 50:
        summary += text_content
    else:
        summary += "--- Preview (first 50 rows) ---\n"
        summary += "\n".join(lines[:50])
        summary += f"\n... and {row_count - 50} more rows"
    return summary


async def _extract_spreadsheet_text(data: str, filename: str) -> str:
    """Extract and summarize Excel/openoffice spreadsheet content."""
    try:
        from openpyxl import load_workbook

        xls_bytes = base64.b64decode(data)
        wb = load_workbook(filename=io.BytesIO(xls_bytes), read_only=True, data_only=True)
        summary_parts = []
        total_rows = 0
        for sheet_name in wb.sheetnames:
            sheet = wb[sheet_name]
            rows = list(sheet.iter_rows(values_only=True))
            total_rows += len(rows)
            if rows:
                summary_parts.append(f"Sheet: {sheet_name}")
                if len(rows) <= 20:
                    for row in rows:
                        cells = [str(c) if c is not None else "" for c in row]
                        summary_parts.append(" | ".join(cells))
                else:
                    summary_parts.append(f"  {len(rows)} rows")
                    for row in rows[:10]:
                        cells = [str(c) if c is not None else "" for c in row]
                        summary_parts.append(" | ".join(cells))
                    summary_parts.append(f"  ... and {len(rows) - 10} more rows")
            summary_parts.append("")
        return f"[Spreadsheet: {filename}, {total_rows} total rows]\n" + "\n".join(summary_parts)
    except Exception as e:
        logger.warning("Spreadsheet extraction failed: %s", e)
        return f"[Spreadsheet extraction error: {e}]"


class ChatService:
    """Handles sending messages and streaming LLM responses.

    Conversation CRUD is delegated to ``ConversationService``.
    """

    _active_streams: dict[str, asyncio.Event] = {}

    def __init__(self, db: AsyncSession, *, provider_name: str = "ollama"):
        self.db = db
        self._provider_name = provider_name
        self._conversations = ConversationService(db)
        self._memories = MemoryService(db)
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
                    # Try to extract text from PDFs and spreadsheets
                    mime = att.mime_type.lower()
                    filename = att.name
                    extracted_text = att.data  # fallback: use raw text as-is

                    if mime == "application/pdf":
                        extracted_text = await _extract_pdf_text(att.data)
                    elif mime == "text/csv":
                        extracted_text = await _extract_csv_text(att.data, filename)
                    elif mime in ("application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
                                  "application/vnd.ms-excel",
                                  "application/vnd.oasis.opendocument.spreadsheet"):
                        extracted_text = await _extract_spreadsheet_text(att.data, filename)
                    elif mime.startswith("text/") or filename.endswith(('.txt', '.md', '.json', '.py', '.js', '.ts', '.dart', '.csv')):
                        # Plain text files - decode from base64
                        try:
                            extracted_text = base64.b64decode(att.data).decode("utf-8", errors="replace")
                        except Exception:
                            extracted_text = att.data

                    doc_texts.append(f"[Attached file: {filename}]\n{extracted_text}")

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

        llm_messages = await self._build_message_history_with_system_prompt(
            conversation.messages,
            image_b64_list,
            conversation.user_id,
            use_memory=conversation.use_memory,
        )

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

    async def _build_message_history_with_system_prompt(
        self,
        messages: list[Message],
        pending_images: list[str] | None = None,
        user_id: str | None = None,
        use_memory: bool = True,
    ) -> list[LLMMessage]:
        """Build message history with an optional system prompt prepended.

        If use_memory is True and user_id is provided, fetches relevant memories
        and prepends them to the system prompt.

        Args:
            messages: List of conversation messages
            pending_images: Base64-encoded images for multimodal context
            user_id: The user ID to fetch memories for
            use_memory: Whether to inject memories into the system prompt

        Returns:
            List of LLMMessage with system prompt as first message if memories exist
        """
        result: list[LLMMessage] = []

        # Build system prompt with memories if enabled
        system_prompt = await self._build_system_prompt(
            user_id=user_id,
            use_memory=use_memory,
        )

        if system_prompt:
            result.append(LLMMessage(role="system", content=system_prompt))

        # Add conversation messages
        for i, msg in enumerate(messages):
            is_last = i == len(messages) - 1
            images = pending_images if (is_last and pending_images) else None
            result.append(LLMMessage(role=msg.role, content=msg.content, images=images))

        return result

    async def _build_system_prompt(
        self,
        user_id: str | None = None,
        use_memory: bool = True,
    ) -> str:
        """Build the system prompt, optionally with injected memories.

        Args:
            user_id: The user ID to fetch memories for
            use_memory: Whether to inject memories into the system prompt

        Returns:
            System prompt string, empty if no memories or user_id is None
        """
        if not user_id or not use_memory:
            return ""

        try:
            memories = await self._memories.get_relevant_memories(user_id=user_id)

            if not memories:
                return ""

            # Build memory injection text
            memory_lines = ["You are a helpful AI assistant."]
            memory_lines.append("")
            memory_lines.append("Relevant memories about the user:")

            for memory in memories:
                memory_lines.append(f"- {memory.content}")

            memory_lines.append("")
            memory_lines.append("Use these memories to personalize your responses.")

            return "\n".join(memory_lines)

        except Exception as e:
            logger.warning("Failed to build system prompt with memories: %s", e)
            # Graceful fallback: return empty system prompt
            return ""

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
