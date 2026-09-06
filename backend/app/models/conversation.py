from datetime import datetime
from typing import TYPE_CHECKING

from sqlalchemy import (
    BigInteger,
    Boolean,
    DateTime,
    ForeignKey,
    Index,
    Integer,
    Select,
    String,
    Text,
    func,
    select,
)
from sqlalchemy.dialects.postgresql import JSONB
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.core.config import get_settings
from app.db.base import Base

if TYPE_CHECKING:
    from app.models.memory import UserMemory
    from app.models.message import Message
    from app.models.user import User
    from app.topics.models import ActiveContextItem, Topic


class Conversation(Base):
    """A conversation thread between a user and the AI."""

    __tablename__ = "conversations"

    id: Mapped[str] = mapped_column(String(36), primary_key=True)
    user_id: Mapped[str] = mapped_column(
        ForeignKey("users.email", ondelete="CASCADE"), nullable=False, index=True
    )
    title: Mapped[str | None] = mapped_column(String(200), nullable=True)
    model: Mapped[str] = mapped_column(
        String(100), nullable=False, default=lambda: get_settings().default_model
    )
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now()
    )
    is_deleted: Mapped[bool] = mapped_column(default=False, nullable=False)
    is_pinned: Mapped[bool] = mapped_column(default=False, nullable=False, index=True)
    use_memory: Mapped[bool] = mapped_column(default=True, nullable=False)
    use_knowledge_base: Mapped[bool] = mapped_column(default=True, nullable=False)
    context_summary: Mapped[str | None] = mapped_column(Text, nullable=True)
    context_summary_until_id: Mapped[str | None] = mapped_column(String(36), nullable=True)
    system_prompt: Mapped[str | None] = mapped_column(Text, nullable=True)
    enabled_tools: Mapped[list[str] | None] = mapped_column(
        JSONB,
        nullable=True,
        comment="NULL=all tools, []=none, [srv:tool]=subset. See docs/database.md",
    )
    muted_until: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True),
        nullable=True,
        comment="NULL=not muted, far-future=mute forever (MUTE_FOREVER). See docs/database.md",
    )
    thinking_level: Mapped[str | None] = mapped_column(
        String(10),
        nullable=True,
        comment="off|low|medium|high or NULL=provider default. See docs/database.md",
    )
    is_primary: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)
    active_topic_id: Mapped[str | None] = mapped_column(
        ForeignKey("topics.id", ondelete="SET NULL"), nullable=True
    )
    topic_is_pinned: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)
    context_version: Mapped[int] = mapped_column(BigInteger, nullable=False, default=0)
    session_epoch: Mapped[int] = mapped_column(
        Integer, nullable=False, default=0, server_default="0"
    )

    # Relationships
    user: Mapped["User"] = relationship(back_populates="conversations")
    messages: Mapped[list["Message"]] = relationship(
        back_populates="conversation", cascade="all, delete-orphan", order_by="Message.created_at"
    )
    memories: Mapped[list["UserMemory"]] = relationship(
        back_populates="source_conversation", foreign_keys="UserMemory.source_conversation_id"
    )
    active_topic: Mapped["Topic | None"] = relationship(foreign_keys=[active_topic_id])
    active_context_items: Mapped[list["ActiveContextItem"]] = relationship(
        back_populates="conversation", cascade="all, delete-orphan"
    )

    __table_args__ = (
        Index(
            "uq_conversations_active_primary_user",
            "user_id",
            unique=True,
            postgresql_where=(is_primary.is_(True) & is_deleted.is_(False)),
            sqlite_where=(is_primary.is_(True) & is_deleted.is_(False)),
        ),
    )

    @classmethod
    def active(cls, user_id: str | None = None) -> Select["Conversation"]:
        """Non-deleted conversations, optionally scoped to a user."""
        q = select(cls).where(cls.is_deleted == False)  # noqa: E712
        if user_id is not None:
            q = q.where(cls.user_id == user_id)
        return q
