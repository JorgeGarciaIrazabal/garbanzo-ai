"""Assembles the LLM prompt for a turn: message history + system prompt.

Turns a conversation's persisted ``Message`` rows into the ``LLMMessage`` list a
provider expects, prepending a system prompt built from the conversation/user
default plus injected memories and knowledge-base excerpts. Pure assembly — no
DB writes, no provider calls.
"""

import json
import logging
from datetime import UTC, datetime
from typing import Any
from zoneinfo import ZoneInfo

from app.core.config import get_settings
from app.models.message import Message
from app.services.knowledge_base_service import KnowledgeBaseService
from app.services.llm_provider import Message as LLMMessage
from app.services.memory_service import MemoryService
from app.services.system_prompt_service import SystemPromptService
from app.services.token_counter import get_token_counter

logger = logging.getLogger(__name__)


def build_dynamic_context_block(
    timezone: str | None = None,
    location: str | None = None,
    now: datetime | None = None,
    suggest_location_when_missing: bool = False,
) -> str:
    """The per-turn ``<context>`` block: current time, and — when the user
    shared them — their local time/timezone and location.

    Deliberately framed as background the model should only draw on when the
    request actually needs it ("today", "near me"), so it doesn't start
    volunteering the date. A module-level function rather than a builder
    method so the rooms turn path can inject the identical block.

    ``suggest_location_when_missing`` is a 1:1-chat-only flag: when set and no
    ``location`` is stored, the block tells the model to offer to enable
    location sharing *when the request needs it*. Rooms leave it off — a room
    has several members, so no single stored location would fit.

    ``now`` is injectable for tests; production callers leave it None.
    """
    now = now or datetime.now(UTC)
    lines = [
        "<context>",
        "Background information, provided automatically on every message. "
        "Use it only when the user's request actually depends on it (dates, "
        "times, places); never volunteer or mention it otherwise.",
        f"Current UTC time: {now.strftime('%A %Y-%m-%d %H:%M')} UTC",
    ]
    if timezone:
        try:
            local = now.astimezone(ZoneInfo(timezone))
            lines.append(f"User's local time: {local.strftime('%A %Y-%m-%d %H:%M')} ({timezone})")
        except Exception:
            # Validated at the API boundary, so only a zone the server's
            # zoneinfo since dropped lands here — skip the line, keep the turn.
            logger.warning("Unknown user timezone %r; omitting local time", timezone)
    if location:
        lines.append(f"User's location: {location}")
    elif suggest_location_when_missing:
        lines.append(
            "The user has not shared their location. If this request depends on "
            "where they are (nearby places, local recommendations, weather here), "
            "do not guess — briefly suggest they turn on location sharing in "
            "Settings → Profile, then answer as best you can without it."
        )
    lines.append("</context>")
    return "\n".join(lines)


def _maybe_parse_inline_tool_calls(content: str) -> list[dict[str, Any]] | None:
    """If ``content`` is a JSON list of tool-call objects, return them.

    Defensive cleanup for legacy assistant messages that contain raw
    tool-call JSON in their content (an artifact of an earlier bug where
    the call list was stringified into ``content``). Returning the parsed
    calls lets the history-replay path send them via the proper
    ``tool_calls`` field instead of as imitable text.
    """
    stripped = content.strip()
    if not stripped or stripped[0] != "[":
        return None
    try:
        parsed = json.loads(stripped)
    except (ValueError, TypeError):
        return None
    if not isinstance(parsed, list) or not parsed:
        return None
    for item in parsed:
        if not isinstance(item, dict):
            return None
        if "name" not in item or "arguments" not in item:
            return None
    return parsed


class ChatContextBuilder:
    """Builds message history and the memory/KB-augmented system prompt.

    Borrows the conversation-scoped service instances from ``ChatService`` so
    tests that patch them (e.g. ``service._memories.get_relevant_memories``)
    see the same objects.
    """

    def __init__(
        self,
        memories: MemoryService,
        kb: KnowledgeBaseService,
        system_prompts: SystemPromptService,
    ):
        self._memories = memories
        self._kb = kb
        self._system_prompts = system_prompts

    @staticmethod
    def _message_images(msg: Message) -> list[str] | None:
        """Base64 image data persisted in the message's attachment meta."""
        atts = (msg.meta or {}).get("attachments") or []
        images = [
            a["data"]
            for a in atts
            if isinstance(a, dict) and a.get("type") == "image" and a.get("data")
        ]
        return images or None

    def build_message_history(self, messages: list[Message]) -> list[LLMMessage]:
        return [
            LLMMessage(
                role=msg.role,
                content=msg.content,
                images=self._message_images(msg),
            )
            for msg in messages
        ]

    async def build_history_with_system_prompt(
        self,
        messages: list[Message],
        user_id: str | None = None,
        use_memory: bool = True,
        use_knowledge_base: bool = True,
        context_summary: str | None = None,
        context_summary_until_id: str | None = None,
        conversation_system_prompt: str | None = None,
        dynamic_context: str | None = None,
    ) -> tuple[list[LLMMessage], dict[str, int]]:
        """Build message history with an optional system prompt prepended.

        If use_memory is True and user_id is provided, fetches relevant memories
        and prepends them to the system prompt. Image attachments are
        rehydrated from each message's meta, so the vision model keeps seeing
        them on follow-up turns, edits, and regenerates.

        Returns ``(messages, stats)`` where the system prompt (if any) is the
        first message and stats counts the injected context.
        """
        result: list[LLMMessage] = []

        # Filter to unsummarized messages if summary exists
        filtered_messages = list(messages)
        if context_summary and context_summary_until_id:
            for i, m in enumerate(filtered_messages):
                if m.id == context_summary_until_id:
                    filtered_messages = filtered_messages[i + 1 :]
                    break

        # Latest user message drives knowledge-base retrieval.
        last_user_query: str | None = None
        for m in reversed(filtered_messages):
            if m.role == "user" and m.content:
                last_user_query = m.content
                break

        # Build system prompt from (conversation || global default) + memories + KB
        system_prompt, context_stats = await self.build_system_prompt(
            user_id=user_id,
            use_memory=use_memory,
            use_knowledge_base=use_knowledge_base,
            rag_query=last_user_query,
            conversation_system_prompt=conversation_system_prompt,
            dynamic_context=dynamic_context,
        )

        if system_prompt:
            result.append(LLMMessage(role="system", content=system_prompt))

        if context_summary:
            result.append(
                LLMMessage(
                    role="system",
                    content=f"[Earlier conversation summary]\n{context_summary}",
                )
            )

        # Add conversation messages
        for msg in filtered_messages:
            images = self._message_images(msg)
            # Normalize tool-related roles for the LLM: Ollama expects "tool"
            # for a tool result; tool_call messages from the assistant collapse
            # back to an assistant turn carrying structured tool_calls. We
            # MUST NOT inline the tool-call JSON into content — the model
            # would imitate that format and emit raw JSON on the next turn.
            if msg.role == "tool_result":
                result.append(LLMMessage(role="tool", content=msg.content))
            elif msg.role == "tool_call":
                tool_calls = (msg.meta or {}).get("tool_calls") or []
                result.append(
                    LLMMessage(
                        role="assistant",
                        content="",
                        tool_calls=tool_calls or None,
                    )
                )
            elif msg.role == "assistant":
                # Legacy hygiene: if a past assistant turn was persisted with
                # raw tool-call JSON in content, recover it as structured
                # tool_calls so the model doesn't see (and imitate) the JSON.
                inline = _maybe_parse_inline_tool_calls(msg.content)
                if inline is not None:
                    result.append(LLMMessage(role="assistant", content="", tool_calls=inline))
                else:
                    result.append(LLMMessage(role=msg.role, content=msg.content, images=images))
            else:
                result.append(LLMMessage(role=msg.role, content=msg.content, images=images))

        return result, context_stats

    async def build_system_prompt(
        self,
        user_id: str | None = None,
        use_memory: bool = True,
        use_knowledge_base: bool = True,
        rag_query: str | None = None,
        conversation_system_prompt: str | None = None,
        dynamic_context: str | None = None,
    ) -> tuple[str, dict[str, int]]:
        """Build the system prompt from (conversation || user default) + memories.

        Preference order for the base prompt:
          1. ``conversation_system_prompt`` if set
          2. The user's ``default_system_prompt`` if set
          3. A generic fallback only if memories will be injected.

        Memories (when enabled and present) are appended after the base prompt.
        ``dynamic_context`` (see :func:`build_dynamic_context_block`) is
        appended last, and — unlike memories/KB — stands on its own without
        forcing the generic fallback prompt in.

        Returns ``(prompt, stats)`` where stats counts the context actually
        injected ({"memories_used": n, "kb_chunks_used": n}) so the client
        can show the user what informed the reply.
        """
        stats: dict[str, Any] = {
            "memories_used": 0,
            "kb_chunks_used": 0,
            "kb_sources": [],
        }
        base_prompt = (conversation_system_prompt or "").strip()

        if not base_prompt and user_id:
            try:
                user_default = await self._system_prompts.get_user_default_prompt(user_id)
                if user_default:
                    base_prompt = user_default.strip()
            except Exception as e:
                logger.warning("Failed to load user default system prompt: %s", e)

        settings = get_settings()
        counter = get_token_counter()

        memory_block = ""
        if user_id and use_memory:
            try:
                # Ranked by semantic relevance to the current message (with
                # recency fallback), capped at top-K — not the whole store.
                memories = await self._memories.get_relevant_memories(
                    user_id=user_id,
                    query=rag_query,
                    limit=settings.memory_top_k,
                )
                if memories:
                    # Keep memories in list order until the budget runs out, so
                    # a large memory store can't crowd out the conversation.
                    budget = settings.memory_token_budget
                    used = 0
                    kept = []
                    for memory in memories:
                        cost = counter.count_text(memory.content) + 2
                        if kept and used + cost > budget:
                            break
                        used += cost
                        kept.append(memory)
                    if len(kept) < len(memories):
                        logger.info(
                            "Memory block over %d-token budget: injecting %d of %d memories",
                            budget,
                            len(kept),
                            len(memories),
                        )
                    lines = ["Relevant memories about the user:"]
                    for memory in kept:
                        lines.append(f"- {memory.content}")
                    lines.append("")
                    lines.append("Use these memories to personalize your responses.")
                    memory_block = "\n".join(lines)
                    stats["memories_used"] = len(kept)
            except Exception as e:
                logger.warning("Failed to load memories for system prompt: %s", e)

        kb_block = ""
        if user_id and use_knowledge_base and rag_query:
            try:
                matches = await self._kb.search(user_id=user_id, query=rag_query)
                if matches:
                    budget = settings.kb_token_budget
                    used = 0
                    lines = [
                        "Relevant excerpts from the user's knowledge base. "
                        "Cite the source filename when you use them; if none "
                        "are relevant, ignore this section.",
                        "",
                    ]
                    injected = 0
                    for m in matches:
                        cost = counter.count_text(m.content) + 10
                        if injected and used + cost > budget:
                            logger.info(
                                "KB block over %d-token budget: injecting %d of %d chunks",
                                budget,
                                injected,
                                len(matches),
                            )
                            break
                        used += cost
                        injected += 1
                        lines.append(
                            f"--- Source: {m.document_filename} (relevance: {m.score:.2f}) ---"
                        )
                        lines.append(m.content)
                        lines.append("")
                    kb_block = "\n".join(lines).rstrip()
                    stats["kb_chunks_used"] = injected
                    # Distinct source filenames, in injection order, for the
                    # client to render as citation chips.
                    stats["kb_sources"] = list(
                        dict.fromkeys(m.document_filename for m in matches[:injected])
                    )
            except Exception as e:
                logger.warning("Failed to load KB context for system prompt: %s", e)

        if not base_prompt and not memory_block and not kb_block:
            return dynamic_context or "", stats

        if not base_prompt and (memory_block or kb_block):
            base_prompt = "You are a helpful AI assistant."

        sections = [base_prompt]
        if memory_block:
            sections.append(memory_block)
        if kb_block:
            sections.append(kb_block)
        if dynamic_context:
            sections.append(dynamic_context)
        return "\n\n".join(sections), stats
