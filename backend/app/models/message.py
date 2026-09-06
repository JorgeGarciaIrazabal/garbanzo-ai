import time
from datetime import datetime
from typing import TYPE_CHECKING

from sqlalchemy import BigInteger, DateTime, ForeignKey, Index, Integer, String, Text, func
from sqlalchemy.dialects.postgresql import JSONB
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db.base import Base

if TYPE_CHECKING:
    from app.models.conversation import Conversation


class Message(Base):
    """A single message within a conversation."""

    __tablename__ = "messages"

    id: Mapped[str] = mapped_column(String(36), primary_key=True)
    conversation_id: Mapped[str] = mapped_column(
        ForeignKey("conversations.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    role: Mapped[str] = mapped_column(
        String(20),
        nullable=False,
        comment="One of: user, assistant, system, tool_call, tool_result",
    )
    content: Mapped[str] = mapped_column(Text, nullable=False)
    meta: Mapped[dict | None] = mapped_column(
        JSONB,
        nullable=True,
        comment="Additional data: tokens_used, generation_time, etc.",
    )
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        server_default=func.now(),
    )
    seq: Mapped[int] = mapped_column(
        BigInteger,
        default=time.time_ns,
        nullable=False,
        comment=(
            "App-assigned monotonic insertion order, used to paginate a "
            "conversation's messages (B-03). created_at alone ties for rows "
            "persisted in the same DB transaction (Postgres now() is "
            "transaction-start time), which is the common case for an agent "
            "turn's assistant/tool_call/tool_result rows."
        ),
    )
    session_epoch: Mapped[int] = mapped_column(
        Integer,
        nullable=False,
        default=0,
        server_default="0",
        comment="Primary chat session epoch (increments on topic switch to isolate message view)",
    )

    # Relationships
    conversation: Mapped["Conversation"] = relationship(back_populates="messages")

    __table_args__ = (
        Index("ix_messages_conversation_epoch_seq", "conversation_id", "session_epoch", "seq"),
    )
