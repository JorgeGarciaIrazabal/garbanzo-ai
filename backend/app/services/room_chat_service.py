"""Orchestrates user posts → agent turns → broadcasts in a room.

Mention parsing:
  * ``@AgentName`` targets a specific active agent (case-insensitive match on
    the agent's ``name``).
  * ``@all`` targets every active agent.
  * When no mentions are found, agents with ``response_mode='always'`` run,
    followed by the next agent in round-robin order.

Agent-to-agent recursion:
  * Each agent response is itself scanned for mentions. If any are found, the
    mentioned agents run too — up to ``room.max_agent_turn_depth`` levels
    deep.
"""

from __future__ import annotations

import asyncio
import json
import logging
import re
import uuid
from dataclasses import dataclass

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.core.config import get_settings
from app.models.room import Room, RoomAgent, RoomMessage
from app.schemas.chat import AttachmentIn, ChatOptions
from app.schemas.room import (
    RoomChunkEvent,
    RoomDoneEvent,
    RoomMessageEvent,
    RoomStreamStartEvent,
    RoomThinkingEvent,
    RoomToolEvent,
    RoomWSMessage,
)
from app.services.agent_turn import run_agent_turn
from app.services.document_parser import extract_attachment_text
from app.services.image_utils import downscale_image_b64
from app.services.llm_provider import (
    LLMProvider,
    ProviderRegistry,
)
from app.services.llm_provider import (
    Message as LLMMessage,
)
from app.services.mcp_service import (
    MCPService,
    build_tool_payload,
    split_tool_key,
    tool_key,
)
from app.services.room_connection_manager import room_manager

MAX_TOOL_ITERATIONS = 5

logger = logging.getLogger(__name__)


_MENTION_PATTERN = re.compile(r"@([A-Za-z0-9_\-]+|all)", re.IGNORECASE)


@dataclass
class _TurnContext:
    room: Room
    depth: int  # current recursion depth


class _RoomTurnSink:
    """``TurnSink`` writing an agent's reply to a ``RoomMessage`` row.

    The message ID is generated before streaming starts because the
    ``stream_start`` broadcast (and every chunk) carries it so clients can
    address the open bubble.
    """

    def __init__(self, db: AsyncSession, room_id: str, agent: RoomAgent, message_id: str):
        self.db = db
        self.room_id = room_id
        self.agent = agent
        self.message_id = message_id
        self.message: RoomMessage | None = None

    async def persist_assistant(self, content: str, meta: dict | None) -> None:
        # A whitespace-only reply is dropped — no message, no recursion.
        if not content.strip():
            return
        msg_meta = dict(meta) if meta else {}
        msg_meta["agent_name"] = self.agent.name
        msg = RoomMessage(
            id=self.message_id,
            room_id=self.room_id,
            role="assistant",
            content=content,
            sender_agent_id=self.agent.id,
            meta=msg_meta or None,
        )
        self.db.add(msg)
        await self.db.flush()
        self.message = msg

    async def persist_tool_call(self, tool_calls: list[dict]) -> None:
        msg = RoomMessage(
            id=str(uuid.uuid4()),
            room_id=self.room_id,
            role="tool_call",
            content=json.dumps(tool_calls),
            sender_agent_id=self.agent.id,
            meta={"tool_calls": tool_calls},
        )
        self.db.add(msg)
        await self.db.flush()

    async def persist_tool_result(self, content: str, meta: dict) -> None:
        msg = RoomMessage(
            id=str(uuid.uuid4()),
            room_id=self.room_id,
            role="tool_result",
            content=content,
            sender_agent_id=self.agent.id,
            meta=meta,
        )
        self.db.add(msg)
        await self.db.flush()

    async def commit(self) -> None:
        await self.db.commit()

    async def rollback(self) -> None:
        await self.db.rollback()


class RoomChatService:
    def __init__(self, db: AsyncSession):
        self.db = db

    # ------------------------------------------------------------------ setup

    def _get_provider(self, name: str) -> LLMProvider:
        provider = ProviderRegistry.get(name)
        if provider is None:
            raise ValueError(f"Unknown provider: {name}")
        return provider

    # ------------------------------------------------------------------ utils

    @staticmethod
    def parse_mentions(content: str, agent_names: list[str]) -> set[str]:
        """Return the set of agent names mentioned in ``content``.

        Matches are case-insensitive. ``@all`` expands to every name in
        ``agent_names``.
        """
        mentions = set()
        lowered = {n.lower(): n for n in agent_names}
        for raw in _MENTION_PATTERN.findall(content):
            token = raw.lower()
            if token == "all":
                mentions.update(agent_names)
            elif token in lowered:
                mentions.add(lowered[token])
        return mentions

    async def _load_room(self, room_id: str) -> Room | None:
        return (
            await self.db.execute(
                select(Room)
                .where(Room.id == room_id, Room.is_deleted == False)  # noqa: E712
                .options(
                    selectinload(Room.agents),
                    selectinload(Room.members),
                )
            )
        ).scalar_one_or_none()

    async def _load_history(self, room_id: str, limit: int = 100) -> list[RoomMessage]:
        rows = (
            (
                await self.db.execute(
                    select(RoomMessage)
                    .where(RoomMessage.room_id == room_id)
                    .order_by(RoomMessage.created_at.desc())
                    .limit(limit)
                )
            )
            .scalars()
            .all()
        )
        return list(reversed(rows))

    async def _persist_message(
        self,
        room_id: str,
        role: str,
        content: str,
        *,
        sender_user_id: str | None = None,
        sender_agent_id: str | None = None,
        meta: dict | None = None,
    ) -> RoomMessage:
        msg = RoomMessage(
            id=str(uuid.uuid4()),
            room_id=room_id,
            role=role,
            content=content,
            sender_user_id=sender_user_id,
            sender_agent_id=sender_agent_id,
            meta=meta,
        )
        self.db.add(msg)
        await self.db.commit()
        await self.db.refresh(msg)
        return msg

    @staticmethod
    def _message_event(msg: RoomMessage) -> dict:
        """Serialized ``message`` WS event for a persisted room message."""
        return RoomMessageEvent(message=RoomWSMessage.from_model(msg)).model_dump()

    # ------------------------------------------------------------- user entry

    async def handle_user_post(
        self,
        room_id: str,
        user_id: str,
        content: str,
        attachments: list[AttachmentIn] | None = None,
    ) -> RoomMessage:
        room = await self._load_room(room_id)
        if room is None:
            raise ValueError("Room not found")

        # Mirror the 1:1 chat attachment handling: document text is appended
        # inline to the stored content; images keep their base64 data in meta
        # so every member's client (and later agent turns) can render/see them.
        stored_content = content
        meta: dict | None = None
        if attachments:
            attachment_meta: list[dict] = []
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
                joined = "\n\n".join(doc_texts)
                stored_content = f"{content}\n\n{joined}" if content else joined
            meta = {"attachments": attachment_meta}

        user_msg = await self._persist_message(
            room_id=room_id,
            role="user",
            content=stored_content,
            sender_user_id=user_id,
            meta=meta,
        )
        await room_manager.broadcast(room_id, self._message_event(user_msg))

        # Notify offline members that a user posted a message.
        await self._notify_offline_members(
            room,
            sender_label=user_id,
            body=content or "📎 Attachment",
            message_id=user_msg.id,
            exclude_user_ids={user_id},
        )

        try:
            await self._run_agent_turns(
                _TurnContext(room=room, depth=0),
                triggering_content=stored_content,
                triggering_agent_id=None,
            )
        except Exception:
            # The user's message is already persisted and broadcast — an
            # agent-side failure must not surface as "Failed to post message".
            logger.exception("Agent turns failed after user post (room=%s)", room_id)
        return user_msg

    # -------------------------------------------------------------- selection

    async def _select_agents(
        self,
        room: Room,
        triggering_content: str,
        triggering_agent_id: str | None,
        round_robin_history: list[str],
        history: list[RoomMessage],
    ) -> list[RoomAgent]:
        """Pick the agents that should respond to ``triggering_content``.

        Rules:
          1. If explicit @mentions exist → only those agents (if active).
          2. Else → every agent with ``response_mode='always'``.
          3. Else → the next ``round_robin`` agent in ``turn_order``.
          4. ``auto`` agents are also given a chance to jump in: a small LLM
             judgment is invoked per auto-agent to decide whether the agent's
             persona is relevant to the current discussion. Auto agents are
             added on top of (1)/(2)/(3), but skipped entirely when the
             triggering message contains explicit @mentions (the user is
             targeting specific agents).
          5. An agent never responds to its own message.
        """
        active = [a for a in room.agents if a.is_active]
        if not active:
            return []

        mentions = self.parse_mentions(triggering_content, [a.name for a in active])
        if mentions:
            mentioned = [a for a in active if a.name in mentions]
            mentioned.sort(key=lambda a: (a.turn_order, a.created_at))
            return [a for a in mentioned if a.id != triggering_agent_id]

        selected: list[RoomAgent] = []
        selected_ids: set[str] = set()

        # (2) Always-respond agents
        always = sorted(
            [a for a in active if a.response_mode == "always" and a.id != triggering_agent_id],
            key=lambda a: (a.turn_order, a.created_at),
        )
        for a in always:
            selected.append(a)
            selected_ids.add(a.id)

        # (3) Round robin — only when no 'always' agent already covered it
        if not selected:
            rr = sorted(
                [
                    a
                    for a in active
                    if a.response_mode == "round_robin" and a.id != triggering_agent_id
                ],
                key=lambda a: (a.turn_order, a.created_at),
            )
            if rr:
                recent = list(reversed(round_robin_history))
                picked = None
                for agent in rr:
                    if agent.id not in recent[: len(rr) - 1]:
                        picked = agent
                        break
                picked = picked or rr[0]
                selected.append(picked)
                selected_ids.add(picked.id)

        # (4) Auto agents — ask the LLM whether each should jump in
        auto = [
            a
            for a in active
            if a.response_mode == "auto"
            and a.id != triggering_agent_id
            and a.id not in selected_ids
        ]
        if auto:
            judge_model = get_settings().room_auto_judge_model
            logger.info(
                "[AUTO-JUDGE] room=%s evaluating %d auto-agent(s) with judge=%s: %s",
                room.id,
                len(auto),
                judge_model,
                ", ".join(a.name for a in auto),
            )
        # Judges run concurrently — same benchmark-validated per-agent
        # prompt, but wall-clock is the slowest single call instead of the
        # sum. (A single batched judge call was benchmarked and rejected:
        # 72.1% vs 90.7% accuracy — see scripts/benchmark_auto_judge.py.)
        if auto:
            judge_results = await asyncio.gather(
                *(self._auto_should_respond(room, agent, history) for agent in auto),
                return_exceptions=True,
            )
            for agent, result in zip(auto, judge_results, strict=True):
                if isinstance(result, BaseException):
                    logger.error(
                        "[AUTO-JUDGE] crashed for agent=%s in room=%s",
                        agent.name,
                        room.id,
                        exc_info=result,
                    )
                elif result:
                    selected.append(agent)
                    selected_ids.add(agent.id)

        # Stable ordering for consistent multi-agent turns
        selected.sort(key=lambda a: (a.turn_order, a.created_at))
        return selected

    # JSON Schema for the auto-jump-in judge. Ollama's `format` parameter
    # constrains the model to emit a string that matches this schema.
    _AUTO_JUDGE_SCHEMA = {
        "type": "object",
        "properties": {
            "should_respond": {
                "type": "boolean",
                "description": (
                    "True only if the agent should reply to the most recent message right now."
                ),
            },
            "reason": {
                "type": "string",
                "description": "Short justification (one sentence).",
            },
        },
        "required": ["should_respond", "reason"],
    }

    async def _auto_should_respond(
        self, room: Room, agent: RoomAgent, history: list[RoomMessage]
    ) -> bool:
        """Ask a small judge model whether ``agent`` should jump in.

        Uses the cheap shared model from
        ``settings.room_auto_judge_model`` (default ``llama3.2:1b``) with
        Ollama's structured-output ``format`` parameter so the response is
        always parseable JSON matching ``_AUTO_JUDGE_SCHEMA``. The agent's
        own (potentially heavyweight) model is reserved for the actual
        reply. Fail-quiet: any error / parse failure returns False.
        """
        if not history:
            return False

        provider = self._get_provider(agent.provider or "ollama")
        judge_model = get_settings().room_auto_judge_model

        # Most recent ~8 messages, labeled by speaker
        recent = history[-8:]
        agent_id_to_name = {a.id: a.name for a in room.agents}
        transcript_lines: list[str] = []
        for m in recent:
            if m.sender_agent_id:
                who = agent_id_to_name.get(m.sender_agent_id, "agent")
                transcript_lines.append(f"[{who}]: {m.content}")
            elif m.sender_user_id:
                who = m.sender_user_id.split("@")[0]
                transcript_lines.append(f"[{who}]: {m.content}")
            else:
                transcript_lines.append(m.content)
        transcript = "\n".join(transcript_lines)

        last_msg = recent[-1] if recent else None
        last_preview = (
            (
                last_msg.content[:140].replace("\n", " ")
                + ("…" if last_msg and len(last_msg.content) > 140 else "")
            )
            if last_msg
            else ""
        )
        logger.info(
            "[AUTO-JUDGE] ▶ asking judge=%s — agent=%s room=%s last_msg=%r",
            judge_model,
            agent.name,
            room.id,
            last_preview,
        )

        persona = (agent.system_prompt or "").strip()
        persona_line = (
            f'Persona/instructions: "{persona[:400]}"'
            if persona
            else "No specific persona — general-purpose assistant."
        )
        other_active = [a.name for a in room.agents if a.is_active and a.id != agent.id]
        peer_line = (
            f"Other agents present: {', '.join(other_active)}."
            if other_active
            else "Only agent in the room."
        )

        # Prompt copy validated by ``scripts/benchmark_auto_judge.py``
        # (variant ``v1_strict`` — 100% accuracy on the 28-scenario labeled
        # set when paired with phi4-mini).
        judge_system = (
            "You are a routing classifier for a multi-participant chat room. "
            "Decide whether one specific AI agent should reply to the most "
            "recent message. Respond as JSON matching the provided schema.\n\n"
            f"Agent name: {agent.name}\n"
            f"{persona_line}\n"
            f"{peer_line}\n\n"
            "Set should_respond=true ONLY IF replying would clearly add value: "
            "the most recent message asks a question this agent can answer, "
            "explicitly invites this agent, or directly relates to its "
            "expertise. Set should_respond=false for small-talk between "
            "humans, off-topic chatter, anything already handled by another "
            "agent, or messages that simply don't need a reply."
        )
        judge_user = (
            f"Recent conversation:\n{transcript}\n\n"
            f"Should '{agent.name}' reply to the most recent message?"
        )

        t0 = asyncio.get_event_loop().time()
        try:
            answer = await provider.chat(
                messages=[
                    LLMMessage(role="system", content=judge_system),
                    LLMMessage(role="user", content=judge_user),
                ],
                model=judge_model,
                options=ChatOptions(
                    temperature=0.0,
                    max_tokens=80,
                    response_format=self._AUTO_JUDGE_SCHEMA,
                ),
            )
        except Exception:
            elapsed_ms = int((asyncio.get_event_loop().time() - t0) * 1000)
            logger.exception(
                "[AUTO-JUDGE] ✖ LLM call failed in %dms — agent=%s judge=%s",
                elapsed_ms,
                agent.name,
                judge_model,
            )
            return False

        elapsed_ms = int((asyncio.get_event_loop().time() - t0) * 1000)
        decision, reason = self._parse_judge_answer(answer)
        logger.info(
            "[AUTO-JUDGE] %s decision=%s — agent=%s judge=%s (%dms) reason=%r raw=%r",
            "✅ JUMP IN" if decision else "💤 stay quiet",
            decision,
            agent.name,
            judge_model,
            elapsed_ms,
            (reason[:160] if reason else ""),
            (answer or "")[:200],
        )
        return decision

    @staticmethod
    def _parse_judge_answer(raw: str | None) -> tuple[bool, str]:
        """Parse the structured JSON answer from the judge call.

        Returns ``(should_respond, reason)``. On any parse error or missing
        field, defaults to ``(False, "<parse error>")`` so the agent stays
        quiet rather than spamming.
        """
        if not raw:
            return False, "<empty response>"
        try:
            data = json.loads(raw)
        except json.JSONDecodeError:
            return False, f"<unparseable: {raw[:60]}>"
        if not isinstance(data, dict):
            return False, f"<not object: {type(data).__name__}>"
        decision = bool(data.get("should_respond", False))
        reason = str(data.get("reason", "")) if data.get("reason") else ""
        return decision, reason

    # --------------------------------------------------------------- turn run

    async def _run_agent_turns(
        self,
        ctx: _TurnContext,
        *,
        triggering_content: str,
        triggering_agent_id: str | None,
    ) -> None:
        if ctx.depth >= ctx.room.max_agent_turn_depth:
            logger.info(
                "Agent turn depth cap hit for room %s (depth=%d)",
                ctx.room.id,
                ctx.depth,
            )
            return

        # Build round-robin history from past messages (agent sender IDs).
        history = await self._load_history(ctx.room.id, limit=50)
        rr_history = [m.sender_agent_id for m in history if m.sender_agent_id]

        agents = await self._select_agents(
            ctx.room,
            triggering_content,
            triggering_agent_id,
            rr_history,
            history,
        )
        if not agents:
            return

        for agent in agents:
            try:
                final_msg = await self._run_single_agent(ctx, agent, history)
            except Exception:
                logger.exception("Agent turn failed (room=%s agent=%s)", ctx.room.id, agent.name)
                # A failed flush leaves the shared session in an aborted
                # transaction — clear it so later agents and history queries
                # don't fail on a poisoned session.
                await self.db.rollback()
                continue

            if final_msg is None:
                continue

            # Recurse if this agent mentioned another agent.
            await self._run_agent_turns(
                _TurnContext(room=ctx.room, depth=ctx.depth + 1),
                triggering_content=final_msg.content,
                triggering_agent_id=agent.id,
            )
            # Refresh history so the next agent in the sequence sees the new message.
            history = await self._load_history(ctx.room.id, limit=100)

    async def _run_single_agent(
        self, ctx: _TurnContext, agent: RoomAgent, history: list[RoomMessage]
    ) -> RoomMessage | None:
        provider = self._get_provider(agent.provider or "ollama")
        llm_messages = self._build_llm_history(ctx.room, agent, history)

        # Resolve MCP tools for this agent (null=all, []=none, list=subset)
        ollama_tools, tool_lookup = await self._resolve_tools_for_agent(agent)

        message_id = str(uuid.uuid4())
        # Announce the incoming streaming message so the UI can open a bubble.
        await room_manager.broadcast(
            ctx.room.id,
            RoomStreamStartEvent(
                message_id=message_id,
                agent_id=agent.id,
                agent_name=agent.name,
            ).model_dump(),
        )

        sink = _RoomTurnSink(self.db, ctx.room.id, agent, message_id)
        # persist_partial_on_error: other participants already saw the
        # partial reply stream in, so it must survive as a message.
        async for chunk in run_agent_turn(
            provider=provider,
            model=agent.model,
            llm_messages=llm_messages,
            sink=sink,
            options=ChatOptions(temperature=0.7),
            tools=ollama_tools or None,
            execute_tool=lambda call, _emit: self._execute_tool_call(call, tool_lookup),
            max_tool_iterations=MAX_TOOL_ITERATIONS,
            persist_partial_on_error=True,
        ):
            if chunk.metadata and chunk.metadata.get("error"):
                continue
            # Tool execution progress / result events
            tool_exec = chunk.metadata.get("tool_execution") if chunk.metadata else None
            tool_result_meta = chunk.metadata.get("tool_result") if chunk.metadata else None
            if tool_exec:
                await room_manager.broadcast(
                    ctx.room.id,
                    RoomToolEvent(
                        message_id=message_id,
                        agent_id=agent.id,
                        tool_call_id=tool_exec.get("tool_call_id"),
                        tool_name=tool_exec.get("tool_name"),
                        status=tool_exec.get("status", "started"),
                        duration_ms=tool_exec.get("duration_ms"),
                    ).model_dump(),
                )
                continue
            if tool_result_meta:
                await room_manager.broadcast(
                    ctx.room.id,
                    RoomToolEvent(
                        message_id=message_id,
                        agent_id=agent.id,
                        tool_call_id=tool_result_meta.get("tool_call_id"),
                        tool_name=tool_result_meta.get("tool_name"),
                        status="result",
                        result=tool_result_meta,
                    ).model_dump(),
                )
                continue
            if chunk.is_thinking:
                if chunk.content:
                    await room_manager.broadcast(
                        ctx.room.id,
                        RoomThinkingEvent(
                            message_id=message_id,
                            agent_id=agent.id,
                            content=chunk.content,
                        ).model_dump(),
                    )
            elif chunk.content:
                await room_manager.broadcast(
                    ctx.room.id,
                    RoomChunkEvent(
                        message_id=message_id,
                        agent_id=agent.id,
                        content=chunk.content,
                    ).model_dump(),
                )

        msg = sink.message
        if msg is None:
            # Nothing persisted (empty reply or failed turn) — still close the
            # stream so clients tear down the placeholder bubble instead of
            # showing typing dots forever.
            await room_manager.broadcast(
                ctx.room.id,
                RoomDoneEvent(message_id=message_id, agent_id=agent.id).model_dump(),
            )
            return None
        await self.db.refresh(msg)

        await room_manager.broadcast(ctx.room.id, self._message_event(msg))
        await room_manager.broadcast(
            ctx.room.id,
            RoomDoneEvent(message_id=message_id, agent_id=agent.id).model_dump(),
        )

        # Notify offline members: agent replied + any @mentions in the reply.
        await self._notify_offline_members(
            ctx.room,
            sender_label=agent.name,
            body=msg.content,
            message_id=msg.id,
            exclude_user_ids=set(),
        )

        return msg

    # ----------------------------------------------------------------- tools

    async def _resolve_tools_for_agent(
        self, agent: RoomAgent
    ) -> tuple[list[dict], dict[str, tuple[str, str]]]:
        """Return ``(ollama_tools, lookup)`` for this agent's tool whitelist."""
        enabled = agent.enabled_tools
        if enabled is not None and not enabled:
            return [], {}

        mcp = MCPService(self.db)
        try:
            all_tools = await mcp.list_all_tools(enabled_only=True)
        except Exception as exc:
            logger.warning("Failed to list MCP tools for room agent: %s", exc)
            all_tools = []

        if enabled is None:
            filtered = all_tools
        else:
            allowed = set(enabled)
            filtered = [t for t in all_tools if tool_key(t["server_id"], t["name"]) in allowed]
        ollama_tools, lookup = build_tool_payload(filtered)
        return ollama_tools, lookup

    async def _execute_tool_call(self, call: dict, lookup: dict[str, tuple[str, str]]) -> dict:
        """Run a single tool call through ``MCPService``."""
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
        mcp = MCPService(self.db)
        try:
            return await mcp.call_tool(server_id, tool_name, args)
        except Exception as exc:
            logger.exception("Room agent tool execution failed: %s", name)
            return {"ok": False, "error": str(exc)}

    # ------------------------------------------------------------------- misc

    def _build_llm_history(
        self, room: Room, agent: RoomAgent, history: list[RoomMessage]
    ) -> list[LLMMessage]:
        """Convert room history + agent persona into LLM messages.

        The agent's system prompt is prepended, augmented with a short
        description of the room so it knows it's in a multi-agent setting.
        Other agents' replies are labeled with their name so this agent can
        tell who said what.
        """
        agent_id_to_name = {a.id: a.name for a in room.agents}
        sys_parts = []
        if agent.system_prompt and agent.system_prompt.strip():
            sys_parts.append(agent.system_prompt.strip())
        else:
            sys_parts.append(f"You are {agent.name}, a helpful AI assistant.")
        other_agents = [a.name for a in room.agents if a.is_active and a.id != agent.id]
        room_desc = (
            f"You are participating in a group chat called '{room.name}'. "
            f"Other participants: humans (identified by email) and "
            f"{len(other_agents)} other agent(s)"
        )
        if other_agents:
            room_desc += f": {', '.join(other_agents)}"
        room_desc += (
            ". Messages from humans are marked 'user'; messages from other "
            "agents will be labeled '[AgentName]:'. Reply as yourself — do not "
            "impersonate other participants."
        )
        if agent.is_moderator:
            room_desc += (
                " You are the moderator: summarize discussion, break deadlocks, "
                "and keep the conversation on track."
            )
        sys_parts.append(room_desc)

        llm_messages: list[LLMMessage] = [LLMMessage(role="system", content="\n\n".join(sys_parts))]

        for msg in history:
            if msg.role == "tool_result":
                llm_messages.append(LLMMessage(role="tool", content=msg.content))
            elif msg.role == "tool_call":
                tool_calls = (msg.meta or {}).get("tool_calls") or []
                llm_messages.append(
                    LLMMessage(role="assistant", content="", tool_calls=tool_calls or None)
                )
            elif msg.role not in ("user", "assistant"):
                continue
            elif msg.sender_agent_id and msg.sender_agent_id != agent.id:
                # Another agent's reply — render as 'user' so this agent sees
                # it as an incoming turn, with its name tagged for context.
                other_name = agent_id_to_name.get(
                    msg.sender_agent_id,
                    (msg.meta or {}).get("agent_name", "agent") if msg.meta else "agent",
                )
                llm_messages.append(
                    LLMMessage(role="user", content=f"[{other_name}]: {msg.content}")
                )
            elif msg.sender_agent_id == agent.id:
                llm_messages.append(LLMMessage(role="assistant", content=msg.content))
            else:
                # A human message. Image attachments (stored base64 in meta)
                # ride along so multimodal agents can see them.
                label = msg.sender_user_id or "user"
                llm_messages.append(
                    LLMMessage(
                        role="user",
                        content=f"[{label}]: {msg.content}",
                        images=self._message_images(msg),
                    )
                )

        return llm_messages

    @staticmethod
    def _message_images(msg: RoomMessage) -> list[str] | None:
        """Base64 image data attached to a room message, if any."""
        atts = (msg.meta or {}).get("attachments") or []
        images = [a["data"] for a in atts if a.get("type") == "image" and a.get("data")]
        return images or None

    async def _notify_offline_members(
        self,
        room: Room,
        *,
        sender_label: str,
        body: str,
        message_id: str,
        exclude_user_ids: set[str] | None = None,
    ) -> None:
        """Send FCM + in-app notifications to offline room members.

        Called after both user posts and agent replies. Members who are
        currently connected via WebSocket are skipped (they've already seen
        the message in real-time). ``exclude_user_ids`` prevents notifying
        the sender of the triggering message.
        """
        exclude = exclude_user_ids or set()
        member_emails = {m.user_id for m in room.members}

        from app.db.session import async_session_maker
        from app.services.fcm_service import send_to_user

        for target in member_emails:
            if target in exclude:
                continue
            if room_manager.is_user_online(room.id, target):
                continue
            try:
                async with async_session_maker() as session:
                    await send_to_user(
                        session,
                        target,
                        title=f"{sender_label} in {room.name}",
                        body=body[:160],
                        channel="chat_responses",
                        data={"room_id": room.id, "message_id": message_id},
                    )
            except Exception:
                logger.exception("Failed to FCM-notify offline member %s", target)
