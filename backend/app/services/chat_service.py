"""Service for sending messages and streaming LLM responses."""

import asyncio
import json
import logging
import uuid
from collections.abc import AsyncIterator

from sqlalchemy import delete, func
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.message import Message
from app.models.user import User
from app.schemas.chat import AttachmentIn, ChatOptions, ModelInfo
from app.services.agent_turn import ProgressEmit, TurnResult, run_agent_turn
from app.services.chat_context import ChatContextBuilder, build_dynamic_context_block
from app.services.chat_title import generate_and_persist_title
from app.services.conversation_service import ConversationService
from app.services.conversation_turn_sink import ConversationTurnSink
from app.services.document_parser import extract_attachment_text
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
    NATIVE_GARBO_SERVER_ID,
    execute_native_tool,
    native_tool_descriptors,
    native_tool_lookup,
)
from app.services.system_prompt_service import SystemPromptService
from app.services.token_counter import get_token_counter

MAX_TOOL_ITERATIONS = 5

logger = logging.getLogger(__name__)


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
                    entry["data"] = await downscale_image_b64(att.data)
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

        await self._maybe_summarize_context(conversation, existing_messages)

        # Usually a no-op hit on the session's identity map — the user row
        # rode in with the conversation's auth check earlier in the request.
        user = await self.db.get(User, conversation.user_id)

        llm_messages, context_stats = await self._context.build_history_with_system_prompt(
            conversation.messages,
            conversation.user_id,
            use_memory=conversation.use_memory,
            use_knowledge_base=conversation.use_knowledge_base,
            context_summary=conversation.context_summary,
            context_summary_until_id=conversation.context_summary_until_id,
            conversation_system_prompt=conversation.system_prompt,
            dynamic_context=build_dynamic_context_block(
                timezone=user.timezone if user else None,
            ),
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
            ollama_tools, tool_lookup = await self._resolve_tools_for_conversation(conversation)

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
        self, conversation
    ) -> tuple[list[dict], dict[str, tuple[str, str]]]:
        """Return ``(ollama_tools, lookup)`` for this conversation.

        ``lookup`` maps the function name advertised to the LLM back to
        ``(server_id, tool_name)`` so the executor can resolve calls.
        """
        enabled = getattr(conversation, "enabled_tools", None)
        if enabled is not None and not enabled:
            # [] → opt out of all tools (including the native house_designer)
            return [], {}

        try:
            all_tools = await self._mcp.list_all_tools(enabled_only=True)
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
        all_native_descs = native_tool_descriptors()
        if enabled is None:
            for desc in all_native_descs:
                ollama_tools.append(desc)
            lookup.update(native_tool_lookup())
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
