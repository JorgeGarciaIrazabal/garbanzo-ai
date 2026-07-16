from datetime import datetime

from sqlalchemy import DateTime, ForeignKey, Index, String, func
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base


class Friendship(Base):
    """One friend relationship (Idea 5: "Friends").

    Directional at request time — ``requester_email`` sent the request to
    ``addressee_email`` — but symmetric once accepted. Status is one of
    ``pending`` / ``accepted`` / ``blocked`` (validated at the API boundary,
    see 021_friendships.sql for why no DB constraint). Declining or removing
    a friendship deletes the row so either side can try again later;
    blocking keeps the row so the block is durable.

    The unique index on the (requester, addressee) pair stops duplicate
    requests in one direction; ``FriendshipService`` handles the reverse
    direction (accepting instead of mirroring), so a pair has at most one
    row in practice.
    """

    __tablename__ = "friendships"
    __table_args__ = (
        Index("ix_friendships_pair", "requester_email", "addressee_email", unique=True),
    )

    id: Mapped[str] = mapped_column(String(36), primary_key=True)
    requester_email: Mapped[str] = mapped_column(
        ForeignKey("users.email", ondelete="CASCADE", onupdate="CASCADE"),
        nullable=False,
    )
    addressee_email: Mapped[str] = mapped_column(
        ForeignKey("users.email", ondelete="CASCADE", onupdate="CASCADE"),
        nullable=False,
        index=True,
    )
    status: Mapped[str] = mapped_column(String(10), nullable=False, default="pending")
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        server_default=func.now(),
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        server_default=func.now(),
        onupdate=func.now(),
    )
