"""SQLAlchemy ORM model for admin-controlled model availability."""

from datetime import datetime

from sqlalchemy import Boolean, DateTime, String, func
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base


class AvailableModel(Base):
    """An LLM model whose visibility is controlled by admins.

    Rows are created when an admin syncs the live provider list into
    the database.  When ``is_enabled`` is ``False`` the model is hidden
    from the ``GET /chat/models`` response returned to all users.
    """

    __tablename__ = "available_models"

    model_id: Mapped[str] = mapped_column(String(100), primary_key=True)
    is_enabled: Mapped[bool] = mapped_column(
        Boolean,
        nullable=False,
        default=True,
        server_default="true",
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        server_default=func.now(),
        onupdate=func.now(),
    )
