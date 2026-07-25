from datetime import datetime

from sqlalchemy import Boolean, DateTime, ForeignKey, String, Text, func
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base


class ScheduledAction(Base):
    """A user-defined prompt that runs on a schedule.

    Either ``cron_expr`` (recurring) or ``run_at`` (one-off) must be set.
    When the action fires, the backend creates (or reuses, for recurring
    actions whose ``conversation_id`` is already set) a conversation owned
    by the user, seeds it with ``prompt``, streams an assistant reply, and
    sends a ``reminders`` notification pointing at the conversation.
    """

    __tablename__ = "scheduled_actions"

    id: Mapped[str] = mapped_column(String(36), primary_key=True)
    user_id: Mapped[str] = mapped_column(
        ForeignKey("users.email", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    title: Mapped[str | None] = mapped_column(String(200), nullable=True)
    prompt: Mapped[str] = mapped_column(Text, nullable=False)

    # Exactly one of these should be set.
    cron_expr: Mapped[str | None] = mapped_column(String(100), nullable=True)
    run_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)

    model: Mapped[str | None] = mapped_column(String(100), nullable=True)
    system_prompt: Mapped[str | None] = mapped_column(Text, nullable=True)

    # Optional FK to the conversation recurring runs post into. Populated on
    # the first run and reused thereafter so a scheduled action's history
    # accumulates in one chat instead of spawning a new one each fire. NULL
    # for one-off (``run_at``) actions — those still create a fresh
    # conversation per run since they only fire once.
    conversation_id: Mapped[str | None] = mapped_column(
        ForeignKey("conversations.id", ondelete="SET NULL"),
        nullable=True,
        index=True,
    )

    is_active: Mapped[bool] = mapped_column(
        Boolean, nullable=False, default=True, server_default="true"
    )
    next_run: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    last_run_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    last_run_status: Mapped[str | None] = mapped_column(String(32), nullable=True)

    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        server_default=func.now(),
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        server_default=func.now(),
        onupdate=func.now(),
    )
