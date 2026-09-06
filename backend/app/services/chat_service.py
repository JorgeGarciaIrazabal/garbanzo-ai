"""Service for sending messages and streaming LLM responses."""

import asyncio
import base64
import json
import logging
import uuid
from collections.abc import AsyncIterator

from sqlalchemy import delete, func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import get_settings
from app.db.session import async_session_maker
from app.models.conversation import Conversation
from app.models.message import Message
from app.models.user import User
from app.schemas.chat import AttachmentIn, ChatOptions, ModelInfo
from app.services.agent_turn import (
    ProgressEmit,
    TurnResult,
    run_agent_turn,
    stringify_tool_result,
    truncate_tool_result,
)
from app.services.chat_context import (
    ChatContextBuilder,
    build_dynamic_context_block,
)
from app.services.chat_title import generate_and_persist_title
from app.services.client_file_extract import extract_file_text
from app.services.client_tool_bridge import client_tool_bridge
from app.services.conversation_service import ConversationService
from app.services.conversation_turn_sink import ConversationTurnSink
from app.services.document_parser import decode_attachment_bytes, extract_attachment_text
from app.services.error_reporting import report_chat_error
from app.services.image_utils import downscale_image_b64
from app.services.knowledge_base_service import KnowledgeBaseService
from app.services.llm_provider import (
    ChatChunk,
    LLMProvider,
    ProviderRegistry,
    resolve_context_length,
)
from app.services.llm_provider import Message as LLMMessage
from app.services.mcp_service import (
    MCPService,
    build_tool_payload,
    split_tool_key,
    tool_key,
)
from app.services.memory_service import MemoryService
from app.services.microapp_chat_tool import (
    MICRO_APP_TOOL,
    NATIVE_SERVER_ID,
    list_registry_apps,
    micro_app_descriptor,
    run_micro_app,
)
from app.services.microapp_workspace import manager as microapp_manager
from app.services.native_tools import (
    APP_HELP_NUDGE,
    APP_HELP_TOOL,
    DELEGATE_RESEARCH_NUDGE,
    DELEGATE_WORKFLOW_TOOL,
    FOLDER_TOOLS,
    NATIVE_GARBO_SERVER_ID,
    READ_FILE_TOOL,
    client_folder_nudge,
    execute_native_tool,
    folder_tool_descriptors,
    native_tool_descriptors,
    native_tool_lookup,
)
from app.services.system_prompt_service import SystemPromptService
from app.services.token_counter import get_token_counter
from app.topics.topic_context_compiler import TopicContextCompiler
from app.topics.topic_ingestion_service import (
    TopicIngestionService,
    enqueue_message_event,
)

MAX_TOOL_ITERATIONS = 5

logger = logging.getLogger(__name__)


def _forced_agent_instruction(content: str) -> str | None:
    """Return the brief after a leading ``/agent`` command, if present."""
    parts = content.lstrip().split(maxsplit=1)
    if not parts or parts[0].casefold() != "/agent":
        return None
    return parts[1].strip() if len(parts) == 2 else ""


def _error_chunk(content: str, error_type: str) -> ChatChunk:
    return ChatChunk(
        content=content, is_finished=True, metadata={"error": True, "error_type": error_type}
    )


def _summary_text_parts(messages_to_summarize: list) -> str:
    parts: list[str] = []
    for msg in messages_to_summarize:
        if msg.role == "tool_call":
            calls = (msg.meta or {}).get("tool_calls") or []
            names = ", ".join(c.get("name", "?") for c in calls) or "unknown"
            parts.append(f"[Called tools: {names}]")
        elif msg.role == "tool_result":
            name = (msg.meta or {}).get("tool_name", "tool")
            parts.append(f"[Result from {name}]: {msg.content[:300]}")
        else:
            parts.append(f"{msg.role.upper()}: {msg.content[:800]}")
    return "\n\n".join(parts)


def _summary_prompt(summary_input: str) -> str:
    return (
        "Condense the following conversation excerpt into rolling context notes (at most 8 sentences, plain prose). "
        "You MUST preserve:\n- the user's goals, preferences, and constraints\n- key facts, names, numbers, and decisions made\n"
        "- important results returned by tools\n- any open questions or unfinished work\n"
        "Omit pleasantries and repetition. Do not address the user; write neutral notes.\n\n"
        + summary_input
    )


def _summary_bounds(conversation, messages: list) -> tuple[int, int] | None:
    start_idx = 0
    if conversation.context_summary_until_id:
        for i, m in enumerate(messages):
            if m.id == conversation.context_summary_until_id:
                start_idx = i + 1
                break
    end_idx = max(start_idx, len(messages) - 10)
    return None if end_idx <= start_idx else (start_idx, end_idx)


async def _prepare_attachments(
    content: str, attachments: list[AttachmentIn] | None
) -> tuple[str, list[dict]]:
    if not attachments:
        return content, []
    stored_content = content
    attachment_meta: list[dict] = []
    doc_texts: list[str] = []
    for att in attachments:
        entry = {"name": att.name, "mime_type": att.mime_type, "type": att.type}
        if att.type == "image" and att.data:
            entry["data"] = await downscale_image_b64(att.data, mime_type=att.mime_type)
            entry["encoding"] = "base64"
        elif att.type == "document" and att.data:
            extracted_text = await extract_attachment_text(att)
            doc_texts.append(f"[Attached file: {att.name}]\n{extracted_text}")
            try:
                raw = decode_attachment_bytes(att)
            except (ValueError, UnicodeError):
                entry["workflow_unavailable"] = "The attachment payload is invalid."
            else:
                entry["data"] = base64.b64encode(raw).decode("ascii")
                entry["encoding"] = "base64"
        attachment_meta.append(entry)
    if doc_texts:
        stored_content = content + "\n\n" + "\n\n".join(doc_texts)
    return stored_content, attachment_meta


def _build_dynamic_context(
    user,
    tool_lookup: dict,
    has_client_folder: bool,
    client_folder_label: str | None,
    talk_mode_instruction: str | None,
) -> str:
    block = build_dynamic_context_block(
        timezone=user.timezone if user else None,
        location=user.location if user else None,
        suggest_location_when_missing=True,
    )
    if APP_HELP_TOOL in tool_lookup:
        block += f"\n\n{APP_HELP_NUDGE}"
    if has_client_folder:
        block += f"\n\n{client_folder_nudge(client_folder_label)}"
    elif DELEGATE_WORKFLOW_TOOL in tool_lookup:
        block += f"\n\n{DELEGATE_RESEARCH_NUDGE}"
    if talk_instruction := (talk_mode_instruction or "").strip():
        block += f"\n\n<talk_mode>\n{talk_instruction}\n</talk_mode>"
    return block


class ChatService:
    """Handles sending messages and streaming LLM responses.

    Conversation CRUD is delegated to ``ConversationService``; prompt assembly
    to ``ChatContextBuilder``.
    """

    _active_streams: dict[str, asyncio.Event] = {}

    def __init__(self, db: AsyncSession, *, provider_name: str = "ollama"):
        self.db = db
        self._provider_name = provider_name
        self._conversations = ConversationService(db)
        self._memories = MemoryService(db)
        self._system_prompts = SystemPromptService(db)
        self._mcp = MCPService(db)
        self._kb = KnowledgeBaseService(db)
        self._context = ChatContextBuilder(self._memories, self._kb, self._system_prompts)
        self._topic_compiler = TopicContextCompiler(db)

    @property
    def provider_name(self) -> str:
        """Provider key used when a turn moves to an independent DB session."""
        return self._provider_name

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

    def _get_provider(self) -> LLMProvider:
        provider = ProviderRegistry.get(self._provider_name)
        if provider is None:
            raise ValueError(f"Unknown provider: {self._provider_name}")
        return provider

    async def _get_context_length(self, model: str) -> int:
        """Effective context window for ``model`` — see resolve_context_length."""
        return await resolve_context_length(self._get_provider(), model)

    async def _maybe_summarize_context(
        self,
        conversation,
        messages: list,
    ) -> None:
        """Summarize older messages if context window is near full (>80%)."""
        if not messages:
            return
        if conversation.is_primary and get_settings().topic_context_enabled:
            return
        last_assistant = next(
            (m for m in reversed(messages) if m.role == "assistant" and m.meta),
            None,
        )
        tokens_prompt = None
        if last_assistant and last_assistant.meta:
            tokens_prompt = last_assistant.meta.get("tokens_prompt")
        if not tokens_prompt:
            tokens_prompt = get_token_counter().count_messages([m.content or "" for m in messages])
        context_length = await self._get_context_length(conversation.model)
        if tokens_prompt < int(context_length * 0.8):
            return
        bounds = _summary_bounds(conversation, messages)
        if bounds is None:
            return
        start_idx, end_idx = bounds
        messages_to_summarize = messages[start_idx:end_idx]
        prompt = _summary_prompt(_summary_text_parts(messages_to_summarize))
        try:
            provider = self._get_provider()
            summary_parts: list[str] = []
            async for chunk in provider.stream_chat(
                messages=[LLMMessage(role="user", content=prompt)],
                model=conversation.model,
                options=ChatOptions(temperature=0.3, num_ctx=context_length),
            ):
                if not chunk.is_thinking and chunk.content:
                    summary_parts.append(chunk.content)
            new_summary = "".join(summary_parts).strip()
            if not new_summary:
                return
            if conversation.context_summary:
                new_summary = f"{conversation.context_summary}\n\n{new_summary}"
            conversation.context_summary = new_summary
            conversation.context_summary_until_id = messages_to_summarize[-1].id
            await self.db.flush()
        except Exception as e:
            logger.warning("Auto-summarization failed: %s", e)

    async def _maybe_compile_topic_context(
        self, conversation, last_user_text: str, dynamic_context: str
    ) -> tuple[object | None, list, str, list[ChatChunk]]:
        compiled_context = None
        history_for_prompt = conversation.messages
        topic_chunks: list[ChatChunk] = []
        if (
            conversation.is_primary or conversation.active_topic_id
        ) and get_settings().topic_context_enabled:
            try:
                compiled_context = await self._topic_compiler.compile(
                    conversation, current_query=last_user_text
                )
                history_for_prompt = compiled_context.history_messages
                if compiled_context.topic_update is not None:
                    topic_chunks.append(
                        ChatChunk(
                            content="", metadata={"topic_update": compiled_context.topic_update}
                        )
                    )
                if compiled_context.preparing:
                    topic_chunks.append(
                        ChatChunk(
                            content="",
                            metadata={
                                "context_preparing": {
                                    "schema_version": 1,
                                    "context_version": conversation.context_version,
                                    "state": "preparing",
                                    "topic": compiled_context.context_update.get("topic"),
                                }
                            },
                        )
                    )
                topic_chunks.append(
                    ChatChunk(
                        content="", metadata={"context_update": compiled_context.context_update}
                    )
                )
                if conversation.active_topic_id:
                    drift = await self._topic_compiler.detect_drift(conversation, last_user_text)
                    if drift is not None:
                        topic_chunks.append(ChatChunk(content="", metadata={"topic_drift": drift}))
                if compiled_context.block:
                    dynamic_context += f"\n\n{compiled_context.block}"
            except Exception:
                logger.exception("Best-effort primary topic context compilation failed")
        return compiled_context, history_for_prompt, dynamic_context, topic_chunks

    async def send_message(
        self,
        conversation_id: str,
        user_id: str,
        content: str,
        options: ChatOptions | None = None,
        attachments: list[AttachmentIn] | None = None,
        has_client_folder: bool = False,
        client_folder_label: str | None = None,
        talk_mode_instruction: str | None = None,
    ) -> AsyncIterator[ChatChunk]:
        """Save user message, stream LLM response, and persist the result."""
        conversation = await self._conversations.get(conversation_id, user_id)
        if not conversation:
            yield _error_chunk("Conversation not found", "not_found")
            return

        stored_content, attachment_meta = await _prepare_attachments(content, attachments)

        user_message = Message(
            id=str(uuid.uuid4()),
            conversation_id=conversation_id,
            role="user",
            content=stored_content,
            meta={"attachments": attachment_meta} if attachment_meta else None,
            session_epoch=conversation.session_epoch,
            conversation=conversation,
        )
        self.db.add(user_message)
        await self.db.flush()
        event = await enqueue_message_event(self.db, conversation, user_message, "create")
        try:
            await TopicIngestionService(self.db).process_event(event)
        except Exception:
            logger.exception("Best-effort realtime topic classification failed")

        conversation.updated_at = func.now()  # type: ignore[assignment]
        await self.db.flush()

        if attachment_meta:
            # A delegate proposal is emitted before the rest of the turn is
            # committed, and the user can confirm it immediately. Persist the
            # launching message now so the separate /workflows request can
            # copy its attachments into the detached workspace.
            await self.db.commit()

        async for chunk in self._stream_assistant_turn(
            conversation=conversation,
            options=options,
            has_client_folder=has_client_folder,
            client_folder_label=client_folder_label,
            talk_mode_instruction=talk_mode_instruction,
            forced_workflow_instruction=_forced_agent_instruction(content),
        ):
            yield chunk

    async def regenerate_message(
        self,
        conversation_id: str,
        user_id: str,
        message_id: str,
        options: ChatOptions | None = None,
    ) -> AsyncIterator[ChatChunk]:
        """Re-run the LLM from the user message preceding ``message_id``."""
        conversation = await self._conversations.get(
            conversation_id, user_id, include_messages=True
        )
        if not conversation:
            yield _error_chunk("Conversation not found", "not_found")
            return

        messages = list(conversation.messages) if conversation.messages else []
        target = next((m for m in messages if m.id == message_id), None)
        if not target:
            yield _error_chunk("Message not found", "not_found")
            return
        if target.role != "assistant":
            yield _error_chunk("Can only regenerate assistant messages", "invalid_role")
            return

        # Delete the target message and everything after it.
        target_index = next(i for i, m in enumerate(messages) if m.id == message_id)
        ids_to_delete = [m.id for m in messages[target_index:]]
        await self._delete_messages_by_ids(conversation, ids_to_delete)
        await self.db.flush()
        await self.db.refresh(conversation, attribute_names=["messages"])

        conversation.updated_at = func.now()  # type: ignore[assignment]
        await self.db.flush()

        async for chunk in self._stream_assistant_turn(
            conversation=conversation,
            options=options,
        ):
            yield chunk

    async def edit_and_resend(
        self,
        conversation_id: str,
        user_id: str,
        message_id: str,
        new_content: str,
        options: ChatOptions | None = None,
    ) -> AsyncIterator[ChatChunk]:
        """Edit a user message and re-run the conversation from that point."""
        conversation = await self._conversations.get(
            conversation_id, user_id, include_messages=True
        )
        if not conversation:
            yield _error_chunk("Conversation not found", "not_found")
            return

        messages = list(conversation.messages) if conversation.messages else []
        target = next((m for m in messages if m.id == message_id), None)
        if not target:
            yield _error_chunk("Message not found", "not_found")
            return
        if target.role != "user":
            yield _error_chunk("Can only edit user messages", "invalid_role")
            return

        # Preserve the original attachment text block (everything after the
        # first [Attached file: ...] marker) so re-sending keeps the docs.
        appended_block = ""
        marker = "\n\n[Attached file: "
        idx = target.content.find(marker)
        if idx >= 0:
            appended_block = target.content[idx:]
        target.content = new_content + appended_block
        edit_event = await enqueue_message_event(self.db, conversation, target, "edit")
        try:
            await TopicIngestionService(self.db).process_event(edit_event)
        except Exception:
            logger.exception("Best-effort edited-message topic classification failed")

        # Remove everything after this message.
        target_index = next(i for i, m in enumerate(messages) if m.id == message_id)
        ids_to_delete = [m.id for m in messages[target_index + 1 :]]
        await self._delete_messages_by_ids(conversation, ids_to_delete)
        await self.db.flush()
        await self.db.refresh(conversation, attribute_names=["messages"])

        conversation.updated_at = func.now()  # type: ignore[assignment]
        await self.db.flush()

        # Images survive the edit: history building rehydrates them from each
        # message's meta.
        async for chunk in self._stream_assistant_turn(
            conversation=conversation,
            options=options,
            forced_workflow_instruction=_forced_agent_instruction(new_content),
        ):
            yield chunk

    async def _delete_messages_by_ids(
        self, conversation: Conversation, message_ids: list[str]
    ) -> None:
        """Delete messages matching any of the provided IDs."""
        if not message_ids:
            return
        messages = list(
            (await self.db.scalars(select(Message).where(Message.id.in_(message_ids)))).all()
        )
        for message in messages:
            await enqueue_message_event(self.db, conversation, message, "delete")
        await self.db.execute(delete(Message).where(Message.id.in_(message_ids)))

    async def _stream_assistant_turn(
        self,
        conversation,
        options: ChatOptions | None = None,
        has_client_folder: bool = False,
        client_folder_label: str | None = None,
        talk_mode_instruction: str | None = None,
        forced_workflow_instruction: str | None = None,
    ) -> AsyncIterator[ChatChunk]:
        """Stream an LLM response for the current state of ``conversation``."""
        conversation_id = conversation.id
        existing_messages = list(conversation.messages)
        is_first_exchange = not any(m.role == "assistant" for m in existing_messages)
        last_user_text = next(
            (m.content for m in reversed(existing_messages) if m.role == "user"),
            "",
        )
        last_user_message_id = next(
            (m.id for m in reversed(existing_messages) if m.role == "user"),
            None,
        )

        if forced_workflow_instruction is not None:
            confirmation = "I started the autonomous agent. Follow its progress here."
            async for chunk in self._stream_forced_workflow(
                conversation,
                forced_workflow_instruction,
                confirmation,
            ):
                yield chunk
            if is_first_exchange and forced_workflow_instruction:
                self._spawn_title_generation(
                    conversation_id,
                    conversation.model,
                    last_user_text,
                    confirmation,
                )
            return

        is_topic_chat = bool(
            (conversation.is_primary or conversation.active_topic_id)
            and get_settings().topic_context_enabled
        )
        # Topic conversations use the evidence-first compiler below. The
        # legacy summary is intentionally retained for non-topic threads and
        # for users who disable topic context.
        if not is_topic_chat:
            await self._maybe_summarize_context(conversation, existing_messages)

        user = await self.db.get(User, conversation.user_id)
        ollama_tools, tool_lookup = await self._resolve_tools_for_conversation(
            conversation, has_client_folder=has_client_folder
        )
        dynamic_context = _build_dynamic_context(
            user, tool_lookup, has_client_folder, client_folder_label, talk_mode_instruction
        )
        (
            compiled_context,
            history_for_prompt,
            dynamic_context,
            topic_chunks,
        ) = await self._maybe_compile_topic_context(conversation, last_user_text, dynamic_context)
        for chunk in topic_chunks:
            yield chunk
        llm_messages, context_stats = await self._context.build_history_with_system_prompt(
            history_for_prompt,
            conversation.user_id,
            use_memory=conversation.use_memory,
            use_knowledge_base=conversation.use_knowledge_base,
            context_summary=None if is_topic_chat else conversation.context_summary,
            context_summary_until_id=(
                None if is_topic_chat else conversation.context_summary_until_id
            ),
            conversation_system_prompt=conversation.system_prompt,
            dynamic_context=dynamic_context,
        )

        provider = self._get_provider()
        opts = options or ChatOptions()
        opts.think = conversation.thinking_level
        cancel_event = asyncio.Event()
        ChatService._active_streams[conversation_id] = cancel_event
        try:
            extra_meta = {
                k: context_stats[k]
                for k in ("memories_used", "kb_chunks_used", "kb_sources")
                if context_stats.get(k)
            }
            if compiled_context is not None:
                extra_meta["context_snapshot"] = compiled_context.snapshot
                extra_meta["context_version"] = compiled_context.snapshot.get("context_version")

            result = TurnResult()
            async for chunk in run_agent_turn(
                provider=provider,
                model=conversation.model,
                llm_messages=llm_messages,
                sink=ConversationTurnSink(self.db, conversation),
                options=opts,
                tools=ollama_tools or None,
                execute_tool=lambda call, emit: self._execute_tool_call(
                    call, tool_lookup, conversation, emit
                ),
                cancel_event=cancel_event,
                max_tool_iterations=MAX_TOOL_ITERATIONS,
                extra_finish_metadata=extra_meta or None,
                result=result,
                on_error=lambda error, tool_call_id, trace, error_metadata: report_chat_error(
                    user_id=conversation.user_id,
                    conversation_id=conversation_id,
                    message_id=last_user_message_id,
                    model=conversation.model,
                    last_user_turn=last_user_text,
                    error=error,
                    tool_call_id=tool_call_id,
                    trace=trace,
                    error_metadata=error_metadata,
                ),
            ):
                yield chunk

            if result.completed and is_first_exchange and result.content and last_user_text:
                self._spawn_title_generation(
                    conversation_id,
                    conversation.model,
                    last_user_text,
                    result.content,
                )
            if (
                result.completed
                and conversation.is_primary
                and get_settings().topic_context_enabled
            ):
                self._spawn_topic_prewarm(conversation_id)
        finally:
            ChatService._active_streams.pop(conversation_id, None)

    async def _stream_forced_workflow(
        self,
        conversation,
        instruction: str,
        confirmation: str,
    ) -> AsyncIterator[ChatChunk]:
        """Execute ``/agent`` deterministically without asking the LLM first."""
        sink = ConversationTurnSink(self.db, conversation)
        if not instruction:
            message = (
                "Add a task after `/agent`, for example: `/agent research the 2026 World Cup`."
            )
            await sink.persist_assistant(message, None)
            await sink.commit()
            yield ChatChunk(content=message)
            yield ChatChunk(content="", is_finished=True)
            return

        call = {
            "id": str(uuid.uuid4()),
            "name": DELEGATE_WORKFLOW_TOOL,
            "arguments": {"instruction": instruction, "summary": instruction[:120]},
        }
        await sink.persist_tool_call([call])
        yield ChatChunk(content="", tool_calls=[call])
        yield ChatChunk(
            content="",
            metadata={
                "tool_execution": {
                    "tool_call_id": call["id"],
                    "tool_name": DELEGATE_WORKFLOW_TOOL,
                    "status": "started",
                }
            },
        )
        tool_result = await self._execute_garbo_tool(
            DELEGATE_WORKFLOW_TOOL,
            call["arguments"],
            conversation,
        )
        raw_text = stringify_tool_result(tool_result)
        result_text = truncate_tool_result(raw_text, get_settings().tool_result_max_chars)
        result_meta = {
            "tool_call_id": call["id"],
            "tool_name": DELEGATE_WORKFLOW_TOOL,
            "result": tool_result,
            "duration_ms": 0,
        }
        await sink.persist_tool_result(result_text, result_meta)
        yield ChatChunk(
            content="",
            metadata={
                "tool_execution": {
                    "tool_call_id": call["id"],
                    "tool_name": DELEGATE_WORKFLOW_TOOL,
                    "status": "finished",
                    "duration_ms": 0,
                }
            },
        )
        yield ChatChunk(content="", metadata={"tool_result": result_meta})
        proposal = tool_result.get("proposal") if isinstance(tool_result, dict) else None
        if proposal:
            yield ChatChunk(
                content="",
                metadata={"action_proposal": {**proposal, "tool_call_id": call["id"]}},
            )
        await sink.persist_assistant(confirmation, None)
        await sink.commit()
        yield ChatChunk(content=confirmation)
        yield ChatChunk(content="", is_finished=True)

    def _spawn_title_generation(
        self,
        conversation_id: str,
        model: str,
        user_text: str,
        assistant_text: str,
    ) -> None:
        """Fire-and-forget title generation on the conversation's model.

        Uses the already-loaded conversation model rather than a separate
        small model so low-RAM deployments don't pay a second model load.
        """
        asyncio.create_task(
            generate_and_persist_title(
                self._get_provider(),
                conversation_id,
                model,
                user_text,
                assistant_text,
            )
        )

    def _spawn_topic_prewarm(self, conversation_id: str) -> None:
        """Fire-and-forget pre-warming of dynamic topic context for the next turn."""
        asyncio.create_task(self._prewarm_topic_context(conversation_id))

    async def _prewarm_topic_context(self, conversation_id: str) -> None:
        try:
            async with async_session_maker() as db:
                conv = await ConversationService(db).get(conversation_id)
                if conv and conv.is_primary and conv.active_topic_id:
                    compiler = TopicContextCompiler(db)
                    await compiler.prewarm(conv)
        except Exception as e:
            logger.debug("Topic context pre-warm failed for %s: %s", conversation_id, e)

    async def _resolve_tools_for_conversation(
        self, conversation, has_client_folder: bool = False
    ) -> tuple[list[dict], dict[str, tuple[str, str]]]:
        """Return ``(ollama_tools, lookup)`` for this conversation.

        ``lookup`` maps the function name advertised to the LLM back to
        ``(server_id, tool_name)`` so the executor can resolve calls.

        ``delegate_workflow`` is available in both folder and research mode.
        ``has_client_folder`` additionally advertises the client-served
        ``read_file`` / ``list_files`` tools.
        """
        enabled = getattr(conversation, "enabled_tools", None)
        if enabled is not None and not enabled:
            return [], {}
        try:
            all_tools = await self._mcp.list_all_tools(
                enabled_only=True,
                user_email=getattr(conversation, "user_id", None),
            )
        except Exception as exc:
            logger.warning("Failed to list MCP tools: %s", exc)
            all_tools = []
        allowed_set = None if enabled is None else set(enabled)
        filtered = (
            all_tools
            if allowed_set is None
            else [t for t in all_tools if tool_key(t["server_id"], t["name"]) in allowed_set]
        )
        ollama_tools, lookup = build_tool_payload(filtered)
        if microapp_manager.enabled:
            descriptor = micro_app_descriptor(list_registry_apps())
            if descriptor is not None:
                ollama_tools.append(descriptor)
                lookup[MICRO_APP_TOOL] = (NATIVE_SERVER_ID, "micro-app")
        all_native_descs = list(native_tool_descriptors())
        if has_client_folder:
            all_native_descs += folder_tool_descriptors()
        if allowed_set is None:
            ollama_tools.extend(all_native_descs)
            lookup.update(native_tool_lookup())
            if has_client_folder:
                for name in FOLDER_TOOLS:
                    lookup[name] = (NATIVE_GARBO_SERVER_ID, name)
        else:
            for desc in all_native_descs:
                tool_name = desc["function"]["name"]
                key = f"{NATIVE_GARBO_SERVER_ID}:{tool_name}"
                if key in allowed_set:
                    ollama_tools.append(desc)
                    lookup[tool_name] = (NATIVE_GARBO_SERVER_ID, tool_name)
        return ollama_tools, lookup

    async def _execute_tool_call(
        self,
        call: dict,
        lookup: dict[str, tuple[str, str]],
        conversation=None,
        emit: ProgressEmit | None = None,
    ) -> dict:
        """Run a single tool call through ``MCPService`` (or a native tool).

        ``call["name"]`` is the function name we advertised to the LLM. We
        resolve it back to ``(server_id, tool_name)`` via ``lookup``. As a
        legacy fallback we also accept the raw ``"server_id:tool_name"``
        form some older flows produced.

        ``emit`` lets a streaming native tool (``micro_app``) forward live
        progress into the turn; MCP tools ignore it.
        """
        name = call.get("name") or ""
        args = call.get("arguments") or {}
        if isinstance(args, str):
            try:
                args = json.loads(args)
            except Exception:
                args = {}

        target = lookup.get(name)
        if target is None and ":" in name:
            target = split_tool_key(name)
        if target is None:
            return {"ok": False, "error": f"Unknown tool: {name}"}

        server_id, tool_name = target
        if server_id == NATIVE_SERVER_ID:
            return await self._execute_native_tool(name, args, conversation, emit)
        if server_id == NATIVE_GARBO_SERVER_ID and tool_name in FOLDER_TOOLS:
            return await self._execute_client_folder_tool(call, tool_name, args, conversation, emit)
        if server_id == NATIVE_GARBO_SERVER_ID:
            return await self._execute_garbo_tool(tool_name, args, conversation)
        try:
            return await self._mcp.call_tool(server_id, tool_name, args)
        except Exception as exc:
            logger.exception("Tool execution failed: %s", name)
            return {"ok": False, "error": str(exc)}

    # Conversation-scoped "(app, file) the user is currently working on", so
    # follow-up edits without an explicit app/file keep targeting the same one.
    # Ephemeral by design (in-process); the files themselves are durable state.
    _active_target: dict[str, tuple[str | None, str | None]] = {}

    async def _execute_native_tool(
        self, name: str, args: dict, conversation, emit: ProgressEmit | None = None
    ) -> dict:
        """Dispatch a first-class (non-MCP) tool such as ``micro_app``."""
        if name != MICRO_APP_TOOL:
            return {"ok": False, "error": f"Unknown native tool: {name}"}

        conv_id = getattr(conversation, "id", None)
        user_email = getattr(conversation, "user_id", None)
        if not user_email:
            return {"ok": False, "error": "No user for micro_app tool."}

        prior_app, prior_file = (
            self._active_target.get(conv_id, (None, None)) if conv_id else (None, None)
        )
        result = await run_micro_app(
            user_email=user_email,
            args=args,
            prior_app=prior_app,
            prior_file=prior_file,
            emit=emit,
        )
        if conv_id and result.get("app"):
            self._active_target[conv_id] = (result.get("app"), result.get("file"))
        return result

    async def _execute_garbo_tool(self, name: str, args: dict, conversation) -> dict:
        """Dispatch a native garbo tool (scheduled actions, memories, notifications).

        These tools operate on the calling user's own data — ``conversation.user_id``
        is the user identity — and share the turn's ``AsyncSession`` for the DB
        writes.  The ``commit`` happens naturally at the next sink commit, but
        for create/update/delete operations we commit eagerly so the data is
        durable even if the turn is cancelled or errors out later.
        """
        user_email = getattr(conversation, "user_id", None)
        if not user_email:
            return {"ok": False, "error": "No user for this tool."}
        result = await execute_native_tool(
            name=name,
            args=args,
            db=self.db,
            user_id=user_email,
        )
        # Eagerly commit writes so they survive a turn rollback/cancel.
        if result.get("ok"):
            try:
                await self.db.commit()
            except Exception:
                logger.exception("Commit after native tool '%s' failed", name)
                await self.db.rollback()
        return result

    async def _execute_client_folder_tool(
        self,
        call: dict,
        tool_name: str,
        args: dict,
        conversation,
        emit: ProgressEmit | None,
    ) -> dict:
        """Delegate a folder read to the desktop client (idea 17).

        Emits a ``client_tool_request`` chunk and parks on the bridge until the
        client POSTs the result. The backend never touches the host filesystem:
        for ``read_file`` the client returns the file's bytes, which we extract
        into text here; for ``list_files`` it returns the directory listing.
        """
        conv_id = getattr(conversation, "id", None)
        tool_call_id = call.get("id")
        if emit is None or not conv_id or not tool_call_id:
            return {"ok": False, "error": "Folder tools require a live turn."}

        async def _emit_request() -> None:
            await emit(
                ChatChunk(
                    content="",
                    metadata={
                        "client_tool_request": {
                            "tool_call_id": tool_call_id,
                            "tool_name": tool_name,
                            "args": args,
                        }
                    },
                )
            )

        payload = await client_tool_bridge.request(
            conversation_id=conv_id,
            tool_call_id=tool_call_id,
            on_registered=_emit_request,
        )
        if not payload.get("ok"):
            return payload

        if tool_name == READ_FILE_TOOL:
            data_b64 = payload.get("data")
            filename = payload.get("filename") or args.get("path") or ""
            if not data_b64:
                return {"ok": False, "error": "The app returned no file content."}
            try:
                raw = base64.b64decode(data_b64)
            except Exception:
                return {"ok": False, "error": "The app returned invalid file content."}
            content = extract_file_text(filename, raw)
            return {"ok": True, "path": args.get("path"), "content": content}

        # list_files: the client returns the directory entries verbatim.
        return {"ok": True, "path": args.get("path", "."), "entries": payload.get("entries", [])}

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
                supports_tools=m.supports_tools,
                supports_vision=m.supports_vision,
                supports_thinking=m.supports_thinking,
                thinking_levels=m.thinking_levels,
                default_thinking_level=m.default_thinking_level,
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
