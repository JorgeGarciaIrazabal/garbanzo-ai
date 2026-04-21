"""SQLAlchemy ORM model for MCP servers."""

from datetime import datetime

from sqlalchemy import Boolean, DateTime, ForeignKey, String, Text, func
from sqlalchemy.dialects.postgresql import JSONB
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base


class MCPServer(Base):
    """A registered Model Context Protocol (MCP) server.

    Admins create these server entries from the admin portal. Servers may
    be reached over HTTP/SSE or spawned as a stdio subprocess.
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
