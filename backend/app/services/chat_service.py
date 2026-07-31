"""Service for sending messages and streaming LLM responses."""

import asyncio
import base64
import json
import logging
import uuid
from collections.abc import AsyncIterator

from sqlalchemy import delete, func
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import get_settings
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
from app.services.document_parser import extract_attachment_text
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

MAX_TOOL_ITERATIONS = 5

logger = logging.getLogger(__name__)


def _forced_agent_instruction(content: str) -> str | None:
    """Return the brief after a leading ``/agent`` command, if present."""
    parts = content.lstrip().split(maxsplit=1)
    if not parts or parts[0].casefold() != "/agent":
        return None
    return parts[1].strip() if len(parts) == 2 else ""


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

        # Prefer the provider-reported prompt size from the last turn (exact);
        # fall back to a TokenCounter estimate so conversations without one
        # (first turns, imported history) still get summarized in time.
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

        # Find start index (respect existing summary boundary)
        start_idx = 0
        if conversation.context_summary_until_id:
            for i, m in enumerate(messages):
                if m.id == conversation.context_summary_until_id:
                    start_idx = i + 1
                    break

        # Keep last 10 messages intact, summarize everything before
        end_idx = max(start_idx, len(messages) - 10)
        if end_idx <= start_idx:
            return

        messages_to_summarize = messages[start_idx:end_idx]

        text_parts = []
        for msg in messages_to_summarize:
            if msg.role == "tool_call":
                # The content is raw JSON; a name list reads better and
                # won't teach the summarizer to emit tool-call syntax.
                calls = (msg.meta or {}).get("tool_calls") or []
                names = ", ".join(c.get("name", "?") for c in calls) or "unknown"
                text_parts.append(f"[Called tools: {names}]")
            elif msg.role == "tool_result":
                name = (msg.meta or {}).get("tool_name", "tool")
                text_parts.append(f"[Result from {name}]: {msg.content[:300]}")
            else:
                text_parts.append(f"{msg.role.upper()}: {msg.content[:800]}")
        summary_input = "\n\n".join(text_parts)

        prompt = (
            "Condense the following conversation excerpt into rolling context "
            "notes (at most 8 sentences, plain prose). You MUST preserve:\n"
            "- the user's goals, preferences, and constraints\n"
            "- key facts, names, numbers, and decisions made\n"
            "- important results returned by tools\n"
            "- any open questions or unfinished work\n"
            "Omit pleasantries and repetition. Do not address the user; "
            "write neutral notes.\n\n" + summary_input
        )

        try:
            provider = self._get_provider()
            summary_parts: list[str] = []
            # The summarize input is by definition ~80% of the window —
            # without num_ctx the request would run at the runtime default
            # (typically 4096) and silently truncate exactly what we're
            # trying to preserve.
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
            yield ChatChunk(
                content="Conversation not found",
                is_finished=True,
                metadata={"error": True, "error_type": "not_found"},
            )
            return

        # Build the content that goes into the DB (append document text inline).
        # Images are downscaled for the vision model and their base64 data kept
        # in meta, so later turns (follow-ups, edit, regenerate) still see them.
        stored_content = content
        attachment_meta: list[dict] = []

        if attachments:
            doc_texts: list[str] = []
            for att in attachments:
                entry = {"name": att.name, "mime_type": att.mime_type, "type": att.type}
                if att.type == "image" and att.data:
                    entry["data"] = await downscale_image_b64(
                        att.data,
                        mime_type=att.mime_type,
                    )
                elif att.type == "document" and att.data:
                    extracted_text = await extract_attachment_text(att)
                    doc_texts.append(f"[Attached file: {att.name}]\n{extracted_text}")
                attachment_meta.append(entry)

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
        """Re-run the LLM from the user message preceding ``message_id``.

        ``message_id`` should identify an assistant message. All messages from
        that message onward (assistant + any trailing tool_call/tool_result)
        are deleted, and the response is re-streamed based on the remaining
        history.
        """
        conversation = await self._conversations.get(
            conversation_id, user_id, include_messages=True
        )
        if not conversation:
            yield ChatChunk(
                content="Conversation not found",
                is_finished=True,
                metadata={"error": True, "error_type": "not_found"},
            )
            return

        messages = list(conversation.messages) if conversation.messages else []
        target = next((m for m in messages if m.id == message_id), None)
        if not target:
            yield ChatChunk(
                content="Message not found",
                is_finished=True,
                metadata={"error": True, "error_type": "not_found"},
            )
            return
        if target.role != "assistant":
            yield ChatChunk(
                content="Can only regenerate assistant messages",
                is_finished=True,
                metadata={"error": True, "error_type": "invalid_role"},
            )
            return

        # Delete the target message and everything after it.
        target_index = next(i for i, m in enumerate(messages) if m.id == message_id)
        ids_to_delete = [m.id for m in messages[target_index:]]
        await self._delete_messages_by_ids(ids_to_delete)
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
        """Edit a user message and re-run the conversation from that point.

        Updates the message's text (attachments are preserved) and deletes
        every message that came after it, then streams a fresh assistant
        response.
        """
        conversation = await self._conversations.get(
            conversation_id, user_id, include_messages=True
        )
        if not conversation:
            yield ChatChunk(
                content="Conversation not found",
                is_finished=True,
                metadata={"error": True, "error_type": "not_found"},
            )
            return

        messages = list(conversation.messages) if conversation.messages else []
        target = next((m for m in messages if m.id == message_id), None)
        if not target:
            yield ChatChunk(
                content="Message not found",
                is_finished=True,
                metadata={"error": True, "error_type": "not_found"},
            )
            return
        if target.role != "user":
            yield ChatChunk(
                content="Can only edit user messages",
                is_finished=True,
                metadata={"error": True, "error_type": "invalid_role"},
            )
            return

        # Preserve the original attachment text block (everything after the
        # first [Attached file: ...] marker) so re-sending keeps the docs.
        appended_block = ""
        marker = "\n\n[Attached file: "
        idx = target.content.find(marker)
        if idx >= 0:
            appended_block = target.content[idx:]
        target.content = new_content + appended_block

        # Remove everything after this message.
        target_index = next(i for i, m in enumerate(messages) if m.id == message_id)
        ids_to_delete = [m.id for m in messages[target_index + 1 :]]
        await self._delete_messages_by_ids(ids_to_delete)
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

    async def _delete_messages_by_ids(self, message_ids: list[str]) -> None:
        """Delete messages matching any of the provided IDs."""
        if not message_ids:
            return
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
        """Stream an LLM response for the current state of ``conversation``.

        Assumes the conversation's messages list already reflects the desired
        history (e.g. user turn appended, or trailing assistant trimmed).
        Builds context (summary, memories, KB, tools) and delegates the
        streaming/tool loop to ``run_agent_turn``.
        """
        conversation_id = conversation.id
        # Captured before streaming: a turn with no prior assistant message
        # is the conversation's first exchange and gets an auto-title.
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

        await self._maybe_summarize_context(conversation, existing_messages)

        # Usually a no-op hit on the session's identity map — the user row
        # rode in with the conversation's auth check earlier in the request.
        user = await self.db.get(User, conversation.user_id)

        # Resolved before prompt assembly so the system prompt only nudges
        # toward tools that are actually available this turn.
        ollama_tools, tool_lookup = await self._resolve_tools_for_conversation(
            conversation, has_client_folder=has_client_folder
        )

        dynamic_context = build_dynamic_context_block(
            timezone=user.timezone if user else None,
            location=user.location if user else None,
            # 1:1 chat has a single user, so nudging them to share location
            # when a turn needs it is safe (rooms deliberately opt out).
            suggest_location_when_missing=True,
        )
        if APP_HELP_TOOL in tool_lookup:
            dynamic_context += f"\n\n{APP_HELP_NUDGE}"
        if has_client_folder:
            dynamic_context += f"\n\n{client_folder_nudge(client_folder_label)}"
        elif DELEGATE_WORKFLOW_TOOL in tool_lookup:
            dynamic_context += f"\n\n{DELEGATE_RESEARCH_NUDGE}"
        talk_instruction = (talk_mode_instruction or "").strip()
        if talk_instruction:
            dynamic_context += f"\n\n<talk_mode>\n{talk_instruction}\n</talk_mode>"

        llm_messages, context_stats = await self._context.build_history_with_system_prompt(
            conversation.messages,
            conversation.user_id,
            use_memory=conversation.use_memory,
            use_knowledge_base=conversation.use_knowledge_base,
            context_summary=conversation.context_summary,
            context_summary_until_id=conversation.context_summary_until_id,
            conversation_system_prompt=conversation.system_prompt,
            dynamic_context=dynamic_context,
        )

        provider = self._get_provider()
        opts = options or ChatOptions()
        # thinking_level is a persisted conversation setting, not a per-request
        # option — it always wins over whatever the client's ChatOptions
        # carried. None reproduces the provider's implicit default.
        opts.think = conversation.thinking_level

        cancel_event = asyncio.Event()
        ChatService._active_streams[conversation_id] = cancel_event

        try:
            # What personal context informed this reply — stamped onto the
            # finish chunk (and thus the persisted message meta) alongside
            # the context_length the engine allocates.
            extra_meta: dict = {}
            for key in ("memories_used", "kb_chunks_used", "kb_sources"):
                if context_stats.get(key):
                    extra_meta[key] = context_stats[key]

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
                on_error=lambda error, tool_call_id, trace: report_chat_error(
                    user_id=conversation.user_id,
                    conversation_id=conversation_id,
                    message_id=last_user_message_id,
                    model=conversation.model,
                    last_user_turn=last_user_text,
                    error=error,
                    tool_call_id=tool_call_id,
                    trace=trace,
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
            # [] → opt out of all tools (including the native house_designer)
            return [], {}

        try:
            all_tools = await self._mcp.list_all_tools(
                enabled_only=True,
                user_email=getattr(conversation, "user_id", None),
            )
        except Exception as exc:
            logger.warning("Failed to list MCP tools: %s", exc)
            all_tools = []

        if enabled is None:
            filtered = all_tools
        else:
            allowed = set(enabled)
            filtered = [t for t in all_tools if tool_key(t["server_id"], t["name"]) in allowed]
        ollama_tools, lookup = build_tool_payload(filtered)

        # The micro_app capability is always offered when the micro-apps feature
        # is configured — it's how the model "detects" a request to view or edit
        # any of the user's micro-apps.
        if microapp_manager.enabled:
            descriptor = micro_app_descriptor(list_registry_apps())
            if descriptor is not None:
                ollama_tools.append(descriptor)
                lookup[MICRO_APP_TOOL] = (NATIVE_SERVER_ID, "micro-app")

        # Native garbo tools (scheduled actions, memories, notifications) are
        # always available so the model can manage the user's data without the
        # user leaving the conversation. They run in-process — no MCP server
        # or admin registration needed, working identically in dev and prod.
        # Folder reads remain client-served and gated by has_client_folder.
        # delegate_workflow is always available: with a folder it edits an
        # uploaded copy; without one it runs as detached research.
        all_native_descs = list(native_tool_descriptors())
        if has_client_folder:
            all_native_descs += folder_tool_descriptors()
        if enabled is None:
            for desc in all_native_descs:
                ollama_tools.append(desc)
            lookup.update(native_tool_lookup())
            if has_client_folder:
                for name in FOLDER_TOOLS:
                    lookup[name] = (NATIVE_GARBO_SERVER_ID, name)
        else:
            allowed = set(enabled)
            for desc in all_native_descs:
                tool_name = desc["function"]["name"]
                key = f"{NATIVE_GARBO_SERVER_ID}:{tool_name}"
                if key in allowed:
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
