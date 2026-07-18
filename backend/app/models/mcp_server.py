"""SQLAlchemy ORM model for MCP servers."""

from datetime import datetime

from sqlalchemy import Boolean, DateTime, ForeignKey, String, Text, func
from sqlalchemy.dialects.postgresql import JSONB
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base


class MCPServer(Base):
    """A registered Model Context Protocol (MCP) server.

    Servers may be reached over HTTP/SSE or spawned as a stdio subprocess.

    Ownership is expressed by :attr:`owner_email`:

    * ``NULL`` — a *global* server registered by an admin from the admin
      portal. Its tools are offered to every user and to multi-user rooms.
    * set — a *personal* server the user registered from their own settings.
      Its tools are offered only to that user's conversations; rooms never
      see it. Deleted automatically when the owning user is deleted.
    """

    __tablename__ = "mcp_servers"

    id: Mapped[str] = mapped_column(String(36), primary_key=True)
    name: Mapped[str] = mapped_column(String(100), nullable=False)
    description: Mapped[str | None] = mapped_column(Text, nullable=True)

    # Transport: "http", "sse", or "stdio"
    transport: Mapped[str] = mapped_column(String(20), nullable=False)

    # For HTTP/SSE
    url: Mapped[str | None] = mapped_column(Text, nullable=True)
    auth_header: Mapped[str | None] = mapped_column(Text, nullable=True)

    # For stdio
    command: Mapped[str | None] = mapped_column(Text, nullable=True)
    args: Mapped[list[str] | None] = mapped_column(JSONB, nullable=True)
    env: Mapped[dict[str, str] | None] = mapped_column(JSONB, nullable=True)

    enabled: Mapped[bool] = mapped_column(
        Boolean,
        nullable=False,
        default=True,
        server_default="true",
    )

    # NULL = global (admin-managed); set = personal to this user. Determines
    # who sees the server's tools. See the class docstring.
    owner_email: Mapped[str | None] = mapped_column(
        ForeignKey("users.email", ondelete="CASCADE"),
        nullable=True,
    )
    # Who created the row (audit only; kept even if the creator is deleted).
    created_by: Mapped[str | None] = mapped_column(
        ForeignKey("users.email", ondelete="SET NULL"),
        nullable=True,
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
