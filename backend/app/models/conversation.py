from datetime import datetime
from typing import TYPE_CHECKING

from sqlalchemy import DateTime, ForeignKey, Select, String, Text, func, select
from sqlalchemy.dialects.postgresql import JSONB
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.core.config import get_settings
from app.db.base import Base

if TYPE_CHECKING:
    from app.models.memory import UserMemory
    from app.models.message import Message
    from app.models.user import User


class Conversation(Base):
    """A conversation thread between a user and the AI."""

    __tablename__ = "conversations"

    id: Mapped[str] = mapped_column(String(36), primary_key=True)
    user_id: Mapped[str] = mapped_column(
        ForeignKey("users.email", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    title: Mapped[str | None] = mapped_column(String(200), nullable=True)
    model: Mapped[str] = mapped_column(
        String(100),
        nullable=False,
        default=lambda: get_settings().default_model,
    )
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        server_default=func.now(),
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        server_default=func.now(),
        onupdate=func.now(),
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
        comment=(
            "Per-conversation MCP tool selection. NULL = all enabled tools, "
            '[] = no tools, ["srv:tool"] = subset.'
        ),
    )
    muted_until: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True),
        nullable=True,
        comment=(
            "Notifications (push + in-app) are suppressed while now() < muted_until. "
            "NULL = not muted. 'Mute forever' uses a far-future sentinel "
            "(see MUTE_FOREVER in mute_util.py) rather than a separate bool, so "
            "callers only ever need one comparison. Mirrors RoomMember.muted_until, "
            "except a conversation has exactly one owner, so this lives directly "
            "on Conversation instead of a per-member join table."
        ),
    )
    thinking_level: Mapped[str | None] = mapped_column(
        String(10),
        nullable=True,
        comment=(
            "One of 'off' | 'low' | 'medium' | 'high', or NULL. NULL preserves "
            "the provider's implicit default (auto-enable thinking when the "
            "model advertises the capability); 'off' force-disables it even "
            "for a capable model. The other three map straight onto Ollama's "
            "`think` chat option. Ignored by chat_service/ollama_provider for "
            "models that don't advertise the 'thinking' capability."
        ),
    )

    # Relationships
    user: Mapped["User"] = relationship(back_populates="conversations")
    messages: Mapped[list["Message"]] = relationship(
        back_populates="conversation",
        cascade="all, delete-orphan",
        order_by="Message.created_at",
    )
    memories: Mapped[list["UserMemory"]] = relationship(
        back_populates="source_conversation",
        foreign_keys="UserMemory.source_conversation_id",
    )

    @classmethod
    def active(cls, user_id: str | None = None) -> Select["Conversation"]:
        """Return a SELECT query pre-filtered to non-deleted conversations.

        Optionally scoped to a specific user.
        """
        query = select(cls).where(cls.is_deleted == False)  # noqa: E712
        if user_id is not None:
            query = query.where(cls.user_id == user_id)
        return query
