"""Durable user files, independently reusable by conversation threads."""

from datetime import datetime

from sqlalchemy import (
    DateTime,
    ForeignKey,
    Integer,
    LargeBinary,
    String,
    Text,
    UniqueConstraint,
    func,
)
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base


class VirtualFolder(Base):
    __tablename__ = "virtual_folders"

    id: Mapped[str] = mapped_column(String(36), primary_key=True)
    user_id: Mapped[str] = mapped_column(ForeignKey("users.email", ondelete="CASCADE"), index=True)
    name: Mapped[str] = mapped_column(String(200))
    description: Mapped[str] = mapped_column(Text, default="", server_default="")
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now()
    )


class VirtualFile(Base):
    __tablename__ = "virtual_files"
    __table_args__ = (UniqueConstraint("folder_id", "path"),)

    id: Mapped[str] = mapped_column(String(36), primary_key=True)
    folder_id: Mapped[str] = mapped_column(
        ForeignKey("virtual_folders.id", ondelete="CASCADE"), index=True
    )
    path: Mapped[str] = mapped_column(String(1024))
    media_type: Mapped[str] = mapped_column(String(255))
    size_bytes: Mapped[int] = mapped_column(Integer)
    sha256: Mapped[str] = mapped_column(String(64))
    revision: Mapped[int] = mapped_column(Integer, default=1, server_default="1")
    data: Mapped[bytes] = mapped_column(LargeBinary, deferred=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now()
    )


class ConversationFolder(Base):
    __tablename__ = "conversation_folders"

    conversation_id: Mapped[str] = mapped_column(
        ForeignKey("conversations.id", ondelete="CASCADE"), primary_key=True
    )
    folder_id: Mapped[str] = mapped_column(
        ForeignKey("virtual_folders.id", ondelete="CASCADE"), primary_key=True, index=True
    )
