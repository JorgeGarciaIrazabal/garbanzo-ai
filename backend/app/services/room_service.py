"""Service for Room CRUD + member + agent management."""

from __future__ import annotations

import logging
import uuid
from dataclasses import dataclass

from sqlalchemy import desc, func, or_, select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.models.friendship import Friendship
from app.models.room import Room, RoomAgent, RoomMember, RoomMessage
from app.models.user import User
from app.services.mute_util import resolve_mute_until

logger = logging.getLogger(__name__)


class RoomPermissionError(Exception):
    """Raised when a user is not allowed to perform an action."""


class RoomNotFoundError(Exception):
    """Raised when a room does not exist or the user can't see it."""


class UnknownUserError(Exception):
    """Raised when a referenced user email does not exist."""

    def __init__(self, emails: list[str]):
        self.emails = emails
        super().__init__(f"Unknown user(s): {', '.join(emails)}")


@dataclass
class RoomSearchHit:
    room: Room
    is_member: bool


class RoomService:
    def __init__(self, db: AsyncSession):
        self.db = db

    # ------------------------------------------------------------------ Rooms

    async def create(
        self,
        owner_id: str,
        name: str,
        description: str | None = None,
        is_public: bool = False,
        max_agent_turn_depth: int = 3,
        mode: str = "chat",
        member_emails: list[str] | None = None,
    ) -> Room:
        room_id = str(uuid.uuid4())
        room = Room(
            id=room_id,
            name=name,
            description=description,
            owner_id=owner_id,
            is_public=is_public,
            max_agent_turn_depth=max_agent_turn_depth,
            mode=mode,
        )
        # Dedup invitees, excluding owner
        invitees: list[str] = []
        seen = {owner_id}
        for email in member_emails or []:
            if email in seen:
                continue
            seen.add(email)
            invitees.append(email)

        # Validate invitee emails exist in users table before inserting
        if invitees:
            existing = set(
                (await self.db.execute(select(User.email).where(User.email.in_(invitees))))
                .scalars()
                .all()
            )
            missing = [e for e in invitees if e not in existing]
            if missing:
                raise UnknownUserError(missing)

        # Friend-graph privacy guard: a block between the owner and an
        # invitee makes that invitee unaddable, with a message that doesn't
        # disclose the block (or who placed it).
        for email in invitees:
            if await self._blocked_pair_exists(owner_id, email):
                raise RoomPermissionError(f"Unable to add {email} to the room.")

        self.db.add(room)
        self.db.add(RoomMember(room_id=room_id, user_id=owner_id, role="owner"))
        for email in invitees:
            self.db.add(RoomMember(room_id=room_id, user_id=email, role="member"))

        await self.db.commit()
        return await self._get_with_relations(room_id)

    async def _get_with_relations(self, room_id: str) -> Room:
        result = await self.db.execute(
            select(Room)
            .where(Room.id == room_id)
            .options(
                selectinload(Room.members).selectinload(RoomMember.user),
                selectinload(Room.agents),
            )
        )
        return result.scalar_one()

    async def get(self, room_id: str, *, viewer_id: str | None = None) -> Room | None:
        query = (
            Room.active()
            .where(Room.id == room_id)
            .options(
                selectinload(Room.members).selectinload(RoomMember.user),
                selectinload(Room.agents),
            )
        )
        room = (await self.db.execute(query)).scalar_one_or_none()
        if room is None:
            return None
        # Refresh cached relationships so any in-session mutations (new
        # members, agent edits) are visible.
        await self.db.refresh(room, attribute_names=["members", "agents"])
        if (
            viewer_id is not None
            and not room.is_public
            and not await self.is_member(room_id, viewer_id)
        ):
            return None
        return room

    async def is_member(self, room_id: str, user_id: str) -> bool:
        row = (
            await self.db.execute(
                select(RoomMember.user_id).where(
                    RoomMember.room_id == room_id, RoomMember.user_id == user_id
                )
            )
        ).first()
        return row is not None

    async def list_for_user(
        self, user_id: str, page: int = 1, page_size: int = 20
    ) -> tuple[list[Room], int]:
        base = (
            Room.active()
            .join(RoomMember, RoomMember.room_id == Room.id)
            .where(RoomMember.user_id == user_id)
        )
        count_query = select(func.count()).select_from(base.subquery())
        total = (await self.db.execute(count_query)).scalar() or 0

        query = (
            base.options(selectinload(Room.members), selectinload(Room.agents))
            .order_by(desc(Room.updated_at))
            .offset((page - 1) * page_size)
            .limit(page_size)
        )
        rooms = list((await self.db.execute(query)).scalars().unique().all())
        return rooms, total

    async def search(
        self,
        viewer_id: str,
        query: str,
        scope: str = "all",
        page: int = 1,
        page_size: int = 20,
    ) -> tuple[list[RoomSearchHit], int]:
        """Search rooms by name or description.

        Scope:
          - ``mine`` — only rooms the user is a member of
          - ``public`` — only public rooms (any owner)
          - ``all`` (default) — member rooms + public rooms
        """
        normalized = (query or "").strip()
        if not normalized:
            return [], 0
        escaped = normalized.replace("\\", "\\\\").replace("%", "\\%").replace("_", "\\_")
        pattern = f"%{escaped}%"

        member_rooms_subq = select(RoomMember.room_id).where(RoomMember.user_id == viewer_id)

        base = Room.active().where(
            or_(
                Room.name.ilike(pattern, escape="\\"),
                Room.description.ilike(pattern, escape="\\"),
            )
        )
        if scope == "mine":
            base = base.where(Room.id.in_(member_rooms_subq))
        elif scope == "public":
            base = base.where(Room.is_public == True)  # noqa: E712
        else:  # "all"
            base = base.where(or_(Room.id.in_(member_rooms_subq), Room.is_public == True))  # noqa: E712

        count_query = select(func.count()).select_from(base.subquery())
        total = (await self.db.execute(count_query)).scalar() or 0
        if total == 0:
            return [], 0

        query_stmt = (
            base.options(selectinload(Room.members), selectinload(Room.agents))
            .order_by(desc(Room.updated_at))
            .offset((page - 1) * page_size)
            .limit(page_size)
        )
        rooms = list((await self.db.execute(query_stmt)).scalars().unique().all())

        member_ids = set((await self.db.execute(member_rooms_subq)).scalars().all())
        hits = [RoomSearchHit(room=r, is_member=r.id in member_ids) for r in rooms]
        return hits, total

    async def update(
        self,
        room_id: str,
        user_id: str,
        *,
        name: str | None = None,
        description: str | None = None,
        is_public: bool | None = None,
        max_agent_turn_depth: int | None = None,
        mode: str | None = None,
        owner_id: str | None = None,
    ) -> Room:
        room = await self._require_owner(room_id, user_id)

        if name is not None:
            room.name = name
        if description is not None:
            room.description = description
        if is_public is not None:
            room.is_public = is_public
        if max_agent_turn_depth is not None:
            room.max_agent_turn_depth = max_agent_turn_depth
        if mode is not None:
            room.mode = mode
        if owner_id is not None and owner_id != room.owner_id:
            # New owner must be a member already
            new_owner_row = (
                await self.db.execute(
                    select(RoomMember).where(
                        RoomMember.room_id == room_id,
                        RoomMember.user_id == owner_id,
                    )
                )
            ).scalar_one_or_none()
            if new_owner_row is None:
                raise RoomPermissionError("New owner must already be a member of the room")
            # Demote old owner, promote new owner
            old_owner_row = (
                await self.db.execute(
                    select(RoomMember).where(
                        RoomMember.room_id == room_id,
                        RoomMember.user_id == room.owner_id,
                    )
                )
            ).scalar_one_or_none()
            if old_owner_row is not None:
                old_owner_row.role = "member"
            new_owner_row.role = "owner"
            room.owner_id = owner_id

        await self.db.commit()
        return await self._get_with_relations(room_id)

    async def delete(self, room_id: str, user_id: str) -> None:
        room = await self._require_owner(room_id, user_id)
        room.is_deleted = True
        await self.db.commit()

    # ----------------------------------------------------------------- Members

    async def _blocked_pair_exists(self, a: str, b: str) -> bool:
        """Whether a friend-graph block exists between two users (either
        direction). Rooms respect blocks without caring who placed them."""
        row = (
            await self.db.execute(
                select(Friendship.id).where(
                    Friendship.status == "blocked",
                    or_(
                        (Friendship.requester_email == a) & (Friendship.addressee_email == b),
                        (Friendship.requester_email == b) & (Friendship.addressee_email == a),
                    ),
                )
            )
        ).scalar_one_or_none()
        return row is not None

    async def add_member(
        self, room_id: str, user_id: str, new_user_id: str, role: str = "member"
    ) -> RoomMember:
        await self._require_owner(room_id, user_id)
        if await self._blocked_pair_exists(user_id, new_user_id):
            # Same non-disclosing message as at room creation.
            raise RoomPermissionError(f"Unable to add {new_user_id} to the room.")
        existing = (
            await self.db.execute(
                select(RoomMember).where(
                    RoomMember.room_id == room_id, RoomMember.user_id == new_user_id
                )
            )
        ).scalar_one_or_none()
        if existing:
            return existing
        member = RoomMember(room_id=room_id, user_id=new_user_id, role=role)
        self.db.add(member)
        await self.db.commit()
        return member

    async def remove_member(self, room_id: str, user_id: str, target_user_id: str) -> None:
        room = await self._require_owner(room_id, user_id)
        if target_user_id == room.owner_id:
            raise RoomPermissionError("Cannot remove the owner; transfer ownership first")
        row = (
            await self.db.execute(
                select(RoomMember).where(
                    RoomMember.room_id == room_id,
                    RoomMember.user_id == target_user_id,
                )
            )
        ).scalar_one_or_none()
        if row is None:
            return
        await self.db.delete(row)
        await self.db.commit()

    async def list_members(self, room_id: str) -> list[RoomMember]:
        rows = (
            (
                await self.db.execute(
                    select(RoomMember)
                    .where(RoomMember.room_id == room_id)
                    .options(selectinload(RoomMember.user))
                    .order_by(RoomMember.joined_at)
                )
            )
            .scalars()
            .all()
        )
        return list(rows)

    async def set_mute(self, room_id: str, user_id: str, duration: str) -> RoomMember:
        """Mute or unmute room notifications for ``user_id``.

        ``duration`` is one of ``"8h"``, ``"1w"``, ``"forever"``, ``"unmute"``
        (validated by the ``MuteUpdate`` schema at the API boundary).
        """
        member = (
            await self.db.execute(
                select(RoomMember).where(
                    RoomMember.room_id == room_id, RoomMember.user_id == user_id
                )
            )
        ).scalar_one_or_none()
        if member is None:
            raise RoomNotFoundError("Not a room member")

        member.muted_until = resolve_mute_until(duration)

        await self.db.commit()
        await self.db.refresh(member)
        return member

    # ------------------------------------------------------------------ Agents

    async def add_agent(
        self,
        room_id: str,
        user_id: str,
        *,
        name: str,
        model: str,
        provider: str = "ollama",
        avatar: str | None = None,
        system_prompt: str | None = None,
        thinking_level: str | None = None,
        response_mode: str = "mention",
        turn_order: int = 0,
        is_active: bool = True,
        is_moderator: bool = False,
        enabled_tools: list[str] | None = None,
    ) -> RoomAgent:
        await self._require_owner(room_id, user_id)
        agent = RoomAgent(
            id=str(uuid.uuid4()),
            room_id=room_id,
            name=name,
            avatar=avatar,
            provider=provider,
            model=model,
            system_prompt=system_prompt,
            thinking_level=thinking_level,
            response_mode=response_mode,
            turn_order=turn_order,
            is_active=is_active,
            is_moderator=is_moderator,
            enabled_tools=enabled_tools,
        )
        self.db.add(agent)
        await self.db.commit()
        await self.db.refresh(agent)
        return agent

    async def update_agent(
        self,
        room_id: str,
        user_id: str,
        agent_id: str,
        **fields,
    ) -> RoomAgent:
        await self._require_owner(room_id, user_id)
        agent = (
            await self.db.execute(
                select(RoomAgent).where(RoomAgent.id == agent_id, RoomAgent.room_id == room_id)
            )
        ).scalar_one_or_none()
        if agent is None:
            raise RoomNotFoundError("Agent not found")
        # None means "clear" for nullable columns (the endpoint only forwards
        # fields the client actually sent); other fields ignore None.
        nullable = {"avatar", "system_prompt", "thinking_level", "enabled_tools"}
        for key, value in fields.items():
            if value is None and key not in nullable:
                continue
            setattr(agent, key, value)
        await self.db.commit()
        await self.db.refresh(agent)
        return agent

    async def delete_agent(self, room_id: str, user_id: str, agent_id: str) -> None:
        await self._require_owner(room_id, user_id)
        agent = (
            await self.db.execute(
                select(RoomAgent).where(RoomAgent.id == agent_id, RoomAgent.room_id == room_id)
            )
        ).scalar_one_or_none()
        if agent is None:
            return
        await self.db.delete(agent)
        await self.db.commit()

    async def list_agents(self, room_id: str) -> list[RoomAgent]:
        rows = (
            (
                await self.db.execute(
                    select(RoomAgent)
                    .where(RoomAgent.room_id == room_id)
                    .order_by(RoomAgent.turn_order, RoomAgent.created_at)
                )
            )
            .scalars()
            .all()
        )
        return list(rows)

    # ---------------------------------------------------------------- Messages

    async def list_messages(
        self, room_id: str, page: int = 1, page_size: int = 50
    ) -> tuple[list[RoomMessage], int]:
        base = select(RoomMessage).where(RoomMessage.room_id == room_id)
        count_query = select(func.count()).select_from(base.subquery())
        total = (await self.db.execute(count_query)).scalar() or 0

        rows = (
            (
                await self.db.execute(
                    base.order_by(RoomMessage.created_at)
                    .offset((page - 1) * page_size)
                    .limit(page_size)
                )
            )
            .scalars()
            .all()
        )
        return list(rows), total

    async def all_messages_for_export(self, room_id: str) -> list[RoomMessage]:
        rows = (
            (
                await self.db.execute(
                    select(RoomMessage)
                    .where(RoomMessage.room_id == room_id)
                    .order_by(RoomMessage.created_at)
                )
            )
            .scalars()
            .all()
        )
        return list(rows)

    # --------------------------------------------------------------- Internals

    async def _require_owner(self, room_id: str, user_id: str) -> Room:
        room = (
            await self.db.execute(
                Room.active()
                .where(Room.id == room_id)
                .options(selectinload(Room.members), selectinload(Room.agents))
            )
        ).scalar_one_or_none()
        if room is None:
            raise RoomNotFoundError("Room not found")
        if room.owner_id != user_id:
            raise RoomPermissionError("Only the room owner can perform this action")
        return room
