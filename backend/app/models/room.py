from datetime import datetime
from typing import TYPE_CHECKING

from sqlalchemy import (
    Boolean,
    DateTime,
    ForeignKey,
    Integer,
    Select,
    String,
    Text,
    func,
    select,
)
from sqlalchemy.dialects.postgresql import JSONB
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db.base import Base

if TYPE_CHECKING:
    from app.models.user import User


class Room(Base):
    """A multi-person / multi-agent chat room."""

    __tablename__ = "rooms"

    id: Mapped[str] = mapped_column(String(36), primary_key=True)
    name: Mapped[str] = mapped_column(String(200), nullable=False)
    description: Mapped[str | None] = mapped_column(Text, nullable=True)
    owner_id: Mapped[str] = mapped_column(
        ForeignKey("users.email", onupdate="CASCADE", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    is_public: Mapped[bool] = mapped_column(
        Boolean, nullable=False, default=False, server_default="false", index=True
    )
    is_deleted: Mapped[bool] = mapped_column(
        Boolean, nullable=False, default=False, server_default="false"
    )
    max_agent_turn_depth: Mapped[int] = mapped_column(
        Integer, nullable=False, default=3, server_default="3"
    )
    mode: Mapped[str] = mapped_column(
        String(20),
        nullable=False,
        default="chat",
        server_default="chat",
        comment="'chat' | 'debate'",
    )
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now()
    )

    owner: Mapped["User"] = relationship(foreign_keys=[owner_id])
    members: Mapped[list["RoomMember"]] = relationship(
        back_populates="room",
        cascade="all, delete-orphan",
        order_by="RoomMember.joined_at",
    )
    agents: Mapped[list["RoomAgent"]] = relationship(
        back_populates="room",
        cascade="all, delete-orphan",
        order_by="RoomAgent.turn_order",
    )
    messages: Mapped[list["RoomMessage"]] = relationship(
        back_populates="room",
        cascade="all, delete-orphan",
        order_by="RoomMessage.created_at",
    )

    @classmethod
    def active(cls) -> Select["Room"]:
        """SELECT for rooms that are not soft-deleted."""
        return select(cls).where(cls.is_deleted == False)  # noqa: E712


class RoomMember(Base):
    """Membership record: a user participating in a room."""

    __tablename__ = "room_members"

    room_id: Mapped[str] = mapped_column(
        ForeignKey("rooms.id", ondelete="CASCADE"), primary_key=True
    )
    user_id: Mapped[str] = mapped_column(
        ForeignKey("users.email", onupdate="CASCADE", ondelete="CASCADE"),
        primary_key=True,
        index=True,
    )
    role: Mapped[str] = mapped_column(
        String(20),
        nullable=False,
        default="member",
        server_default="member",
        comment="'owner' | 'member'",
    )
    joined_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())

    room: Mapped["Room"] = relationship(back_populates="members")
    # Read-only link to the underlying user, eager-loaded so ``full_name`` is
    # available wherever members are serialized without triggering a lazy
    # (sync) load on the async session. ``viewonly`` because membership writes
    # go through ``user_id`` directly.
    user: Mapped["User"] = relationship(
        "User",
        primaryjoin="RoomMember.user_id == User.email",
        foreign_keys=[user_id],
        viewonly=True,
        lazy="selectin",
    )


class RoomAgent(Base):
    """An AI agent participant in a room."""

    __tablename__ = "room_agents"

    id: Mapped[str] = mapped_column(String(36), primary_key=True)
    room_id: Mapped[str] = mapped_column(
        ForeignKey("rooms.id", ondelete="CASCADE"), nullable=False, index=True
    )
    name: Mapped[str] = mapped_column(String(100), nullable=False)
    avatar: Mapped[str | None] = mapped_column(String(20), nullable=True)
    provider: Mapped[str] = mapped_column(
        String(50), nullable=False, default="ollama", server_default="ollama"
    )
    model: Mapped[str] = mapped_column(String(100), nullable=False)
    system_prompt: Mapped[str | None] = mapped_column(Text, nullable=True)
    response_mode: Mapped[str] = mapped_column(
        String(20),
        nullable=False,
        default="mention",
        server_default="mention",
        comment="'mention' | 'always' | 'round_robin' | 'auto'",
    )
    turn_order: Mapped[int] = mapped_column(Integer, nullable=False, default=0, server_default="0")
    is_active: Mapped[bool] = mapped_column(
        Boolean, nullable=False, default=True, server_default="true"
    )
    is_moderator: Mapped[bool] = mapped_column(
        Boolean, nullable=False, default=False, server_default="false"
    )
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())

    room: Mapped["Room"] = relationship(back_populates="agents")


class RoomMessage(Base):
    """A single message posted in a room (from a user or an agent)."""

    __tablename__ = "room_messages"

    id: Mapped[str] = mapped_column(String(36), primary_key=True)
    room_id: Mapped[str] = mapped_column(
        ForeignKey("rooms.id", ondelete="CASCADE"), nullable=False, index=True
    )
    role: Mapped[str] = mapped_column(
        String(20),
        nullable=False,
        comment="One of: user, assistant, system, tool_call, tool_result",
    )
    sender_user_id: Mapped[str | None] = mapped_column(
        ForeignKey("users.email", onupdate="CASCADE", ondelete="SET NULL"),
        nullable=True,
    )
    sender_agent_id: Mapped[str | None] = mapped_column(
        ForeignKey("room_agents.id", ondelete="SET NULL"),
        nullable=True,
    )
    content: Mapped[str] = mapped_column(Text, nullable=False)
    meta: Mapped[dict | None] = mapped_column(JSONB, nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())

    room: Mapped["Room"] = relationship(back_populates="messages")
