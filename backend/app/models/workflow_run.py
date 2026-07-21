from datetime import datetime
from typing import Any

from sqlalchemy import DateTime, ForeignKey, String, Text, func
from sqlalchemy.dialects.postgresql import JSONB
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base


class WorkflowRun(Base):
    """One delegated opencode workflow (idea 18).

    The user's folder lives only on the desktop client (idea 17), so a run
    works on a *server-side snapshot*: the client uploads the folder, opencode
    edits that copy, and the resulting git diff is sent back for the client to
    apply locally. Keeping the copy server-side is what lets the run outlive a
    client disconnect — which is the whole point of persisting this row.

    ``status`` flows ``draft`` → ``uploading`` → ``queued`` → ``running`` →
    ``done`` | ``error`` | ``cancelled``. ``progress`` accumulates the
    translated opencode chunks so a client that reconnects can replay the
    timeline it missed.
    """

    __tablename__ = "workflow_runs"

    id: Mapped[str] = mapped_column(String(36), primary_key=True)
    user_id: Mapped[str] = mapped_column(
        ForeignKey("users.email", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    conversation_id: Mapped[str | None] = mapped_column(
        ForeignKey("conversations.id", ondelete="CASCADE"),
        nullable=True,
        index=True,
    )
    room_id: Mapped[str | None] = mapped_column(String(36), nullable=True, index=True)
    # The proposal's tool_call_id — lets the client find the run belonging to a
    # confirm card after a reload without storing anything extra locally.
    tool_call_id: Mapped[str | None] = mapped_column(String(64), nullable=True, index=True)

    status: Mapped[str] = mapped_column(
        String(16), nullable=False, default="draft", server_default="draft", index=True
    )
    instruction: Mapped[str] = mapped_column(Text, nullable=False)
    scope: Mapped[dict[str, Any] | None] = mapped_column(
        JSONB,
        nullable=True,
        comment=(
            "Run mode + permission envelope: mode (folder/research), file_count, "
            "total_bytes, MCP allowance, permissions, and the client's folder "
            "label (never a host path the backend would act on)."
        ),
    )
    # Absolute path of the server-side temp snapshot. Internal only — never
    # returned to a client, and never a path the client supplied.
    workdir: Mapped[str | None] = mapped_column(Text, nullable=True)
    opencode_session_id: Mapped[str | None] = mapped_column(String(64), nullable=True)
    summary: Mapped[str | None] = mapped_column(Text, nullable=True)
    error: Mapped[str | None] = mapped_column(Text, nullable=True)
    progress: Mapped[list[dict[str, Any]] | None] = mapped_column(
        JSONB,
        nullable=True,
        comment="Appended translated opencode chunks, replayed via ?since=<n>.",
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
    completed_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
