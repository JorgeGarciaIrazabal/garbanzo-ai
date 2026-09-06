"""Evidence-grounded topic graph and dynamic-context persistence models."""

from __future__ import annotations

from datetime import datetime
from typing import TYPE_CHECKING, Any

from pgvector.sqlalchemy import Vector
from sqlalchemy import (
    BigInteger,
    Boolean,
    DateTime,
    Float,
    ForeignKey,
    Index,
    Integer,
    String,
    Text,
    UniqueConstraint,
    func,
)
from sqlalchemy.dialects.postgresql import JSONB
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db.base import Base

if TYPE_CHECKING:
    from app.models.conversation import Conversation
    from app.models.message import Message


class Topic(Base):
    """A stable, user-owned node in the automatically curated topic graph."""

    __tablename__ = "topics"

    id: Mapped[str] = mapped_column(String(36), primary_key=True)
    user_id: Mapped[str] = mapped_column(
        ForeignKey("users.email", ondelete="CASCADE"), nullable=False, index=True
    )
    parent_id: Mapped[str | None] = mapped_column(
        ForeignKey("topics.id", ondelete="SET NULL"), nullable=True
    )
    label: Mapped[str] = mapped_column(String(200), nullable=False)
    normalized_label: Mapped[str] = mapped_column(String(200), nullable=False)
    origin: Mapped[str] = mapped_column(String(20), nullable=False, default="history")
    base_score: Mapped[float] = mapped_column(Float, nullable=False, default=0.5)
    signal: Mapped[str | None] = mapped_column(String(120), nullable=True)
    signal_expires_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True
    )
    last_active_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )
    mention_count: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    status: Mapped[str] = mapped_column(String(20), nullable=False, default="active")
    canonical_topic_id: Mapped[str | None] = mapped_column(
        ForeignKey("topics.id", ondelete="SET NULL"), nullable=True
    )
    current_context_version_id: Mapped[str | None] = mapped_column(
        ForeignKey("topic_context_versions.id", ondelete="SET NULL"), nullable=True
    )
    centroid_embedding: Mapped[list[float] | None] = mapped_column(Vector(768), nullable=True)
    dirty_since: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    last_consolidated_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True
    )
    topic_metadata: Mapped[dict[str, Any]] = mapped_column(
        "metadata", JSONB, nullable=False, default=dict
    )
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now(), nullable=False
    )

    parent: Mapped[Topic | None] = relationship(
        remote_side="Topic.id", foreign_keys=[parent_id], back_populates="children"
    )
    children: Mapped[list[Topic]] = relationship(foreign_keys=[parent_id], back_populates="parent")
    aliases: Mapped[list[TopicAlias]] = relationship(
        back_populates="topic", cascade="all, delete-orphan"
    )
    assertions: Mapped[list[TopicAssertion]] = relationship(
        back_populates="topic", cascade="all, delete-orphan"
    )
    context_versions: Mapped[list[TopicContextVersion]] = relationship(
        back_populates="topic",
        cascade="all, delete-orphan",
        foreign_keys="TopicContextVersion.topic_id",
    )
    outgoing_relations: Mapped[list[TopicRelation]] = relationship(
        "TopicRelation",
        foreign_keys="TopicRelation.source_topic_id",
        back_populates="source_topic",
        cascade="all, delete-orphan",
        lazy="selectin",
    )
    incoming_relations: Mapped[list[TopicRelation]] = relationship(
        "TopicRelation",
        foreign_keys="TopicRelation.target_topic_id",
        back_populates="target_topic",
        cascade="all, delete-orphan",
        lazy="selectin",
    )

    __table_args__ = (
        Index("ix_topics_user_parent", "user_id", "parent_id"),
        Index("ix_topics_user_last_active", "user_id", "last_active_at"),
        Index(
            "uq_topics_user_parent_normalized_label",
            "user_id",
            func.coalesce(parent_id, ""),
            "normalized_label",
            unique=True,
        ),
    )


class TopicAlias(Base):
    """A preserved former/alternate label resolving to a stable topic."""

    __tablename__ = "topic_aliases"
    __table_args__ = (UniqueConstraint("user_id", "normalized_alias"),)

    id: Mapped[str] = mapped_column(String(36), primary_key=True)
    user_id: Mapped[str] = mapped_column(
        ForeignKey("users.email", ondelete="CASCADE"), nullable=False
    )
    topic_id: Mapped[str] = mapped_column(
        ForeignKey("topics.id", ondelete="CASCADE"), nullable=False, index=True
    )
    alias: Mapped[str] = mapped_column(String(200), nullable=False)
    normalized_alias: Mapped[str] = mapped_column(String(200), nullable=False)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )

    topic: Mapped[Topic] = relationship(back_populates="aliases")


class TopicRelation(Base):
    """An explicit or inferred relationship edge between two topics."""

    __tablename__ = "topic_relations"
    __table_args__ = (
        UniqueConstraint("user_id", "source_topic_id", "target_topic_id", "relation_type"),
        Index("ix_topic_relations_user_source", "user_id", "source_topic_id"),
        Index("ix_topic_relations_user_target", "user_id", "target_topic_id"),
    )

    id: Mapped[str] = mapped_column(String(36), primary_key=True)
    user_id: Mapped[str] = mapped_column(
        ForeignKey("users.email", ondelete="CASCADE"), nullable=False
    )
    source_topic_id: Mapped[str] = mapped_column(
        ForeignKey("topics.id", ondelete="CASCADE"), nullable=False
    )
    target_topic_id: Mapped[str] = mapped_column(
        ForeignKey("topics.id", ondelete="CASCADE"), nullable=False
    )
    relation_type: Mapped[str] = mapped_column(String(40), nullable=False)
    confidence: Mapped[float] = mapped_column(Float, nullable=False, default=1.0)
    metadata_json: Mapped[dict[str, Any]] = mapped_column(
        "metadata", JSONB, nullable=False, default=dict
    )
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now(), nullable=False
    )

    source_topic: Mapped[Topic] = relationship(
        foreign_keys=[source_topic_id], back_populates="outgoing_relations"
    )
    target_topic: Mapped[Topic] = relationship(
        foreign_keys=[target_topic_id], back_populates="incoming_relations"
    )


class MessageTopic(Base):
    """Evidence membership between one message span and one or more topics."""

    __tablename__ = "message_topics"

    message_id: Mapped[str] = mapped_column(
        ForeignKey("messages.id", ondelete="CASCADE"), primary_key=True
    )
    topic_id: Mapped[str] = mapped_column(
        ForeignKey("topics.id", ondelete="CASCADE"), primary_key=True, index=True
    )
    confidence: Mapped[float] = mapped_column(Float, nullable=False, default=0.5)
    is_primary: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)
    segment_start: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    segment_end: Mapped[int | None] = mapped_column(Integer, nullable=True)
    source_authority: Mapped[str] = mapped_column(
        String(40), nullable=False, default="user_statement"
    )
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )

    message: Mapped[Message] = relationship()
    topic: Mapped[Topic] = relationship()


class TopicAssertion(Base):
    """A typed claim grounded in source spans, never in another summary."""

    __tablename__ = "topic_assertions"
    __table_args__ = (UniqueConstraint("topic_id", "normalized_key"),)

    id: Mapped[str] = mapped_column(String(36), primary_key=True)
    topic_id: Mapped[str] = mapped_column(
        ForeignKey("topics.id", ondelete="CASCADE"), nullable=False, index=True
    )
    kind: Mapped[str] = mapped_column(String(30), nullable=False)
    content: Mapped[str] = mapped_column(Text, nullable=False)
    normalized_key: Mapped[str] = mapped_column(String(300), nullable=False)
    embedding: Mapped[list[float] | None] = mapped_column(Vector(768), nullable=True)
    status: Mapped[str] = mapped_column(String(20), nullable=False, default="uncertain")
    authority: Mapped[str] = mapped_column(String(40), nullable=False)
    confidence: Mapped[float] = mapped_column(Float, nullable=False, default=0.5)
    valid_from: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    valid_until: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    superseded_by_id: Mapped[str | None] = mapped_column(
        ForeignKey("topic_assertions.id", ondelete="SET NULL"), nullable=True
    )
    first_seen_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )
    last_confirmed_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now(), nullable=False
    )

    topic: Mapped[Topic] = relationship(back_populates="assertions")
    evidence: Mapped[list[TopicAssertionEvidence]] = relationship(
        back_populates="assertion", cascade="all, delete-orphan"
    )


class TopicAssertionEvidence(Base):
    """Exact message span supporting/correcting/rejecting an assertion."""

    __tablename__ = "topic_assertion_evidence"

    assertion_id: Mapped[str] = mapped_column(
        ForeignKey("topic_assertions.id", ondelete="CASCADE"), primary_key=True
    )
    message_id: Mapped[str] = mapped_column(
        ForeignKey("messages.id", ondelete="CASCADE"), primary_key=True, index=True
    )
    segment_start: Mapped[int] = mapped_column(Integer, primary_key=True, default=0)
    segment_end: Mapped[int] = mapped_column(Integer, primary_key=True)
    relation: Mapped[str] = mapped_column(String(20), nullable=False, default="supports")
    source_span_hash: Mapped[str] = mapped_column(String(64), nullable=False)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )

    assertion: Mapped[TopicAssertion] = relationship(back_populates="evidence")
    message: Mapped[Message] = relationship()


class TopicExclusion(Base):
    """A hard user/privacy suppression applied before ranking or compilation."""

    __tablename__ = "topic_exclusions"

    id: Mapped[str] = mapped_column(String(36), primary_key=True)
    user_id: Mapped[str] = mapped_column(
        ForeignKey("users.email", ondelete="CASCADE"), nullable=False, index=True
    )
    topic_id: Mapped[str | None] = mapped_column(
        ForeignKey("topics.id", ondelete="CASCADE"), nullable=True
    )
    scope: Mapped[str] = mapped_column(String(30), nullable=False)
    target_id: Mapped[str | None] = mapped_column(String(255), nullable=True)
    origin: Mapped[str] = mapped_column(String(40), nullable=False)
    reason: Mapped[str | None] = mapped_column(Text, nullable=True)
    source_message_id: Mapped[str | None] = mapped_column(
        ForeignKey("messages.id", ondelete="SET NULL"), nullable=True
    )
    concept_embedding: Mapped[list[float] | None] = mapped_column(Vector(768), nullable=True)
    is_privacy_deletion: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )
    revoked_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)


class TopicContextVersion(Base):
    """Immutable, validated materialized context pack for a topic watermark."""

    __tablename__ = "topic_context_versions"
    __table_args__ = (UniqueConstraint("topic_id", "version"),)

    id: Mapped[str] = mapped_column(String(36), primary_key=True)
    topic_id: Mapped[str] = mapped_column(
        ForeignKey("topics.id", ondelete="CASCADE"), nullable=False, index=True
    )
    version: Mapped[int] = mapped_column(BigInteger, nullable=False)
    context_json: Mapped[dict[str, Any]] = mapped_column(JSONB, nullable=False)
    short_summary: Mapped[str | None] = mapped_column(Text, nullable=True)
    source_event_watermark: Mapped[int] = mapped_column(BigInteger, nullable=False, default=0)
    model_id: Mapped[str | None] = mapped_column(String(150), nullable=True)
    model_revision: Mapped[str | None] = mapped_column(String(150), nullable=True)
    provider: Mapped[str] = mapped_column(String(80), nullable=False)
    prompt_version: Mapped[str] = mapped_column(String(80), nullable=False)
    input_tokens: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    output_tokens: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    validation_status: Mapped[str] = mapped_column(String(30), nullable=False)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )

    topic: Mapped[Topic] = relationship(back_populates="context_versions", foreign_keys=[topic_id])


class TopicIngestionEvent(Base):
    """Idempotent durable source-mutation event, ordered by a DB watermark."""

    __tablename__ = "topic_ingestion_events"
    __table_args__ = (UniqueConstraint("operation", "source_type", "source_id", "source_version"),)

    id: Mapped[int] = mapped_column(
        BigInteger().with_variant(Integer(), "sqlite"), primary_key=True, autoincrement=True
    )
    user_id: Mapped[str] = mapped_column(
        ForeignKey("users.email", ondelete="CASCADE"), nullable=False, index=True
    )
    conversation_id: Mapped[str | None] = mapped_column(
        ForeignKey("conversations.id", ondelete="CASCADE"), nullable=True
    )
    operation: Mapped[str] = mapped_column(String(30), nullable=False)
    source_type: Mapped[str] = mapped_column(String(30), nullable=False)
    source_id: Mapped[str] = mapped_column(String(255), nullable=False)
    source_version: Mapped[str] = mapped_column(String(80), nullable=False)
    payload: Mapped[dict[str, Any]] = mapped_column(JSONB, nullable=False, default=dict)
    attempts: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    last_error: Mapped[str | None] = mapped_column(Text, nullable=True)
    processed_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )


class TopicIngestionState(Base):
    """Per-user realtime/consolidation watermarks and retry lease."""

    __tablename__ = "topic_ingestion_state"

    user_id: Mapped[str] = mapped_column(
        ForeignKey("users.email", ondelete="CASCADE"), primary_key=True
    )
    last_realtime_event_id: Mapped[int] = mapped_column(BigInteger, nullable=False, default=0)
    last_consolidated_event_id: Mapped[int] = mapped_column(BigInteger, nullable=False, default=0)
    lease_owner: Mapped[str | None] = mapped_column(String(120), nullable=True)
    lease_expires_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True
    )
    consecutive_failures: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    last_error: Mapped[str | None] = mapped_column(Text, nullable=True)
    retry_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now(), nullable=False
    )


class ActiveContextItem(Base):
    """One current, pinned, or excluded source in a primary conversation."""

    __tablename__ = "active_context_items"
    __table_args__ = (UniqueConstraint("conversation_id", "source_type", "source_id"),)

    id: Mapped[str] = mapped_column(String(36), primary_key=True)
    conversation_id: Mapped[str] = mapped_column(
        ForeignKey("conversations.id", ondelete="CASCADE"), nullable=False, index=True
    )
    source_type: Mapped[str] = mapped_column(String(30), nullable=False)
    source_id: Mapped[str] = mapped_column(String(255), nullable=False)
    source_meta: Mapped[dict[str, Any]] = mapped_column(JSONB, nullable=False, default=dict)
    topic_id: Mapped[str | None] = mapped_column(
        ForeignKey("topics.id", ondelete="CASCADE"), nullable=True
    )
    state: Mapped[str] = mapped_column(String(20), nullable=False, default="dynamic")
    reason: Mapped[str | None] = mapped_column(Text, nullable=True)
    relevance_score: Mapped[float] = mapped_column(Float, nullable=False, default=0)
    token_count: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    last_selected_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now(), nullable=False
    )

    conversation: Mapped[Conversation] = relationship(back_populates="active_context_items")
    topic: Mapped[Topic | None] = relationship()


class TopicArchive(Base):
    """A read-only snapshot of a primary conversation captured on topic switch.

    The archive preserves the messages that existed under the prior topic so
    that a future "enhance this topic" pass can re-derive evidence without
    re-reading the primary conversation (which is cleared on switch).
    """

    __tablename__ = "topic_archives"

    id: Mapped[str] = mapped_column(String(36), primary_key=True)
    user_id: Mapped[str] = mapped_column(
        ForeignKey("users.email", ondelete="CASCADE"), nullable=False
    )
    topic_id: Mapped[str | None] = mapped_column(
        ForeignKey("topics.id", ondelete="SET NULL"), nullable=True
    )
    from_topic_id: Mapped[str | None] = mapped_column(
        ForeignKey("topics.id", ondelete="SET NULL"), nullable=True
    )
    conversation_id: Mapped[str] = mapped_column(
        ForeignKey("conversations.id", ondelete="CASCADE"), nullable=False
    )
    message_count: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    payload: Mapped[dict[str, Any]] = mapped_column(JSONB, nullable=False, default=dict)
    short_summary: Mapped[str | None] = mapped_column(Text, nullable=True)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )
