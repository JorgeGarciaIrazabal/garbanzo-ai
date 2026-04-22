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
import logging
import re
import uuid
from dataclasses import dataclass

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.core.config import get_settings
from app.models.room import Room, RoomAgent, RoomMessage
from app.schemas.chat import ChatOptions
from app.services.llm_provider import (
    LLMProvider,
    ProviderRegistry,
)
from app.services.llm_provider import (
    Message as LLMMessage,
)
from app.services.ollama_provider import OllamaProvider
from app.services.room_connection_manager import room_manager

logger = logging.getLogger(__name__)


_MENTION_PATTERN = re.compile(r"@([A-Za-z0-9_\-]+|all)", re.IGNORECASE)


@dataclass
class _TurnContext:
    room: Room
    depth: int  # current recursion depth


class RoomChatService:
    def __init__(self, db: AsyncSession):
        self.db = db
        self._ensure_default_provider()

    # ------------------------------------------------------------------ setup

    @staticmethod
    def _ensure_default_provider() -> None:
        if "ollama" not in ProviderRegistry.list_providers():
            settings = get_settings()
            ProviderRegistry.register(OllamaProvider(base_url=settings.ollama_base_url))

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
            await self.db.execute(
                select(RoomMessage)
                .where(RoomMessage.room_id == room_id)
                .order_by(RoomMessage.created_at.desc())
                .limit(limit)
            )
        ).scalars().all()
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
    def _message_to_wire(msg: RoomMessage) -> dict:
        return {
            "id": msg.id,
            "room_id": msg.room_id,
            "role": msg.role,
            "sender_user_id": msg.sender_user_id,
            "sender_agent_id": msg.sender_agent_id,
            "content": msg.content,
            "meta": msg.meta,
            "created_at": msg.created_at.isoformat() if msg.created_at else None,
        }

    # ------------------------------------------------------------- user entry

    async def handle_user_post(
        self, room_id: str, user_id: str, content: str
    ) -> RoomMessage:
        room = await self._load_room(room_id)
        if room is None:
            raise ValueError("Room not found")

        user_msg = await self._persist_message(
            room_id=room_id,
            role="user",
            content=content,
            sender_user_id=user_id,
        )
        await room_manager.broadcast(
            room_id, {"type": "message", "message": self._message_to_wire(user_msg)}
        )

        await self._run_agent_turns(
            _TurnContext(room=room, depth=0),
            triggering_content=content,
            triggering_agent_id=None,
        )
        return user_msg

    # -------------------------------------------------------------- selection

    def _select_agents(
        self,
        room: Room,
        triggering_content: str,
        triggering_agent_id: str | None,
        round_robin_history: list[str],
    ) -> list[RoomAgent]:
        """Pick the agents that should respond to ``triggering_content``.

        Rules:
          1. If explicit @mentions exist → only those agents (if active).
          2. Else → every agent with ``response_mode='always'``.
          3. Else → the next ``round_robin`` agent in ``turn_order``.
          4. An agent never responds to its own message (prevents a
             self-mentioning loop).
        """
        active = [a for a in room.agents if a.is_active]
        if not active:
            return []

        mentions = self.parse_mentions(triggering_content, [a.name for a in active])
        if mentions:
            mentioned = [a for a in active if a.name in mentions]
            # Deterministic order by turn_order
            mentioned.sort(key=lambda a: (a.turn_order, a.created_at))
            return [a for a in mentioned if a.id != triggering_agent_id]

        # Fallback: always-respond agents
        always = sorted(
            [a for a in active if a.response_mode == "always" and a.id != triggering_agent_id],
            key=lambda a: (a.turn_order, a.created_at),
        )
        if always:
            return always

        # Fallback: round robin — pick the agent who hasn't spoken most recently.
        rr = sorted(
            [a for a in active if a.response_mode == "round_robin" and a.id != triggering_agent_id],
            key=lambda a: (a.turn_order, a.created_at),
        )
        if not rr:
            return []
        # Find the next one not in recent history
        recent = list(reversed(round_robin_history))
        for agent in rr:
            if agent.id not in recent[: len(rr) - 1]:
                return [agent]
        return [rr[0]]

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

        agents = self._select_agents(
            ctx.room, triggering_content, triggering_agent_id, rr_history
        )
        if not agents:
            return

        for agent in agents:
            try:
                final_msg = await self._run_single_agent(ctx, agent, history)
            except Exception:
                logger.exception(
                    "Agent turn failed (room=%s agent=%s)", ctx.room.id, agent.name
                )
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

        accumulated = ""
        metadata: dict | None = None
        thinking = ""

        message_id = str(uuid.uuid4())
        # Announce the incoming streaming message so the UI can open a bubble.
        await room_manager.broadcast(
            ctx.room.id,
            {
                "type": "stream_start",
                "message_id": message_id,
                "agent_id": agent.id,
                "agent_name": agent.name,
            },
        )

        try:
            async for chunk in provider.stream_chat(
                messages=llm_messages,
                model=agent.model,
                options=ChatOptions(temperature=0.7),
            ):
                if chunk.is_thinking:
                    thinking += chunk.content
                elif chunk.content:
                    accumulated += chunk.content
                    await room_manager.broadcast(
                        ctx.room.id,
                        {
                            "type": "chunk",
                            "message_id": message_id,
                            "agent_id": agent.id,
                            "content": chunk.content,
                        },
                    )
                if chunk.is_finished:
                    metadata = chunk.metadata
        except asyncio.CancelledError:
            raise
        except Exception as e:
            logger.exception("Provider streaming failed for agent %s", agent.name)
            accumulated = accumulated or f"[agent error: {e}]"
            metadata = {"error": True, "error_type": "streaming_error"}

        if not accumulated.strip():
            return None

        msg_meta = dict(metadata) if metadata else {}
        if thinking:
            msg_meta["thinking"] = thinking
        msg_meta["agent_name"] = agent.name

        msg = RoomMessage(
            id=message_id,
            room_id=ctx.room.id,
            role="assistant",
            content=accumulated,
            sender_agent_id=agent.id,
            meta=msg_meta or None,
        )
        self.db.add(msg)
        await self.db.commit()
        await self.db.refresh(msg)

        await room_manager.broadcast(
            ctx.room.id,
            {
                "type": "message",
                "message": self._message_to_wire(msg),
            },
        )
        await room_manager.broadcast(
            ctx.room.id,
            {"type": "done", "message_id": message_id, "agent_id": agent.id},
        )

        # Notify offline members about @mentions directed at them.
        await self._notify_mentioned_offline_members(ctx.room, agent, accumulated)

        return msg

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

        llm_messages: list[LLMMessage] = [
            LLMMessage(role="system", content="\n\n".join(sys_parts))
        ]

        for msg in history:
            if msg.role not in ("user", "assistant"):
                continue
            if msg.sender_agent_id and msg.sender_agent_id != agent.id:
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
                # A human message
                label = msg.sender_user_id or "user"
                llm_messages.append(
                    LLMMessage(role="user", content=f"[{label}]: {msg.content}")
                )

        return llm_messages

    async def _notify_mentioned_offline_members(
        self, room: Room, agent: RoomAgent, content: str
    ) -> None:
        # A very lightweight heuristic: if an agent's reply mentions @user...
        # Currently we notify members whose email local-part was mentioned.
        mentions = _MENTION_PATTERN.findall(content)
        if not mentions:
            return
        member_emails = {m.user_id for m in room.members}

        from app.db.session import async_session_maker
        from app.services.fcm_service import send_to_user

        local_to_email: dict[str, str] = {}
        for email in member_emails:
            local = email.split("@")[0].lower()
            local_to_email[local] = email

        notified: set[str] = set()
        for raw in mentions:
            target = local_to_email.get(raw.lower())
            if not target or target in notified:
                continue
            if room_manager.is_user_online(room.id, target):
                continue
            notified.add(target)
            try:
                async with async_session_maker() as session:
                    await send_to_user(
                        session,
                        target,
                        title=f"{agent.name} mentioned you in {room.name}",
                        body=content[:160],
                        channel="chat_responses",
                        data={"room_id": room.id},
                    )
            except Exception:
                logger.exception("Failed to FCM-notify offline member %s", target)
