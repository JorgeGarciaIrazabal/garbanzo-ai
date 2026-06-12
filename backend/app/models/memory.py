from datetime import datetime
from typing import TYPE_CHECKING

from pgvector.sqlalchemy import Vector
from sqlalchemy import DateTime, ForeignKey, String, func
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.core.config import get_settings
from app.db.base import Base

_EMBEDDING_DIM = get_settings().embedding_dim

if TYPE_CHECKING:
    from app.models.conversation import Conversation
    from app.models.user import User


class UserMemory(Base):
    """A memory stored about a user, extracted from conversations or manually created."""

    __tablename__ = "user_memories"

    id: Mapped[str] = mapped_column(String(36), primary_key=True)
    user_id: Mapped[str] = mapped_column(
        ForeignKey("users.email", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    content: Mapped[str] = mapped_column(nullable=False)
    source_conversation_id: Mapped[str | None] = mapped_column(
        ForeignKey("conversations.id", ondelete="SET NULL"),
        nullable=True,
    )
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        server_default=func.now(),
    )
    is_active: Mapped[bool] = mapped_column(default=True, nullable=False)
    # Semantic embedding of `content` for relevance ranking. Nullable:
    # memories created while the embedder is unavailable are backfilled by
    # the daily extraction job.
    embedding: Mapped[list[float] | None] = mapped_column(
        Vector(_EMBEDDING_DIM),
        nullable=True,
    )

    # Relationships
    user: Mapped["User"] = relationship(back_populates="memories")
    source_conversation: Mapped["Conversation"] = relationship(
        back_populates="memories",
        foreign_keys=[source_conversation_id],
    )

    @classmethod
    def active(cls, user_id: str | None = None) -> list:
        """Return a SELECT query pre-filtered to active memories.

        Optionally scoped to a specific user.
        """
        from sqlalchemy import select

        query = select(cls).where(cls.is_active == True)  # noqa: E712
        if user_id is not None:
            query = query.where(cls.user_id == user_id)
        return query
