from datetime import datetime

from sqlalchemy import DateTime, ForeignKey, String, func
from sqlalchemy.dialects.postgresql import JSONB
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base


class SharedItem(Base):
    """A style or prompt template shared with a friend, pending acceptance
    (Idea 9). ``payload`` is a snapshot taken at share time — copy-on-accept,
    never a live reference — so the sender editing (or deleting) the original
    afterwards doesn't change what the recipient receives. Accepting creates
    the recipient's own copy and deletes this row; declining just deletes it.
    """

    __tablename__ = "shared_items"

    id: Mapped[str] = mapped_column(String(36), primary_key=True)
    sender_email: Mapped[str] = mapped_column(
        ForeignKey("users.email", ondelete="CASCADE"),
        nullable=False,
    )
    recipient_email: Mapped[str] = mapped_column(
        ForeignKey("users.email", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    kind: Mapped[str] = mapped_column(
        String(10),
        nullable=False,
        comment="'style' or 'prompt' — validated at the API boundary.",
    )
    payload: Mapped[dict] = mapped_column(
        JSONB,
        nullable=False,
        comment=(
            "Snapshot of the shared thing. prompt: {name, description, "
            "content}. style: {name, model_id, thinking_level, prompt?} "
            "with the referenced template inlined the same way."
        ),
    )
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        server_default=func.now(),
    )
