from datetime import datetime
from typing import TYPE_CHECKING

from sqlalchemy import DateTime, ForeignKey, Select, String, Text, func, select
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db.base import Base

if TYPE_CHECKING:
    from app.models.user import User


class SystemPromptTemplate(Base):
    """A reusable system prompt template (persona).

    A template is either "built-in" (user_id is NULL — seeded and shared
    across all users) or owned by a specific user (their saved library).
    """

    __tablename__ = "system_prompt_templates"

    id: Mapped[str] = mapped_column(String(36), primary_key=True)
    user_id: Mapped[str | None] = mapped_column(
        ForeignKey("users.email", ondelete="CASCADE"),
        nullable=True,
        index=True,
    )
    name: Mapped[str] = mapped_column(String(100), nullable=False)
    description: Mapped[str | None] = mapped_column(String(500), nullable=True)
    content: Mapped[str] = mapped_column(Text, nullable=False)
    is_builtin: Mapped[bool] = mapped_column(default=False, nullable=False)
    # BCP-47 language tag for built-in templates (e.g. 'en', 'es'); NULL for
    # user-saved templates (language-neutral — the user typed them). NULL acts
    # as a wildcard, surfacing in any locale request.
    locale: Mapped[str | None] = mapped_column(String(5), nullable=True, default=None)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        server_default=func.now(),
    )

    user: Mapped["User"] = relationship(back_populates="system_prompt_templates")

    @classmethod
    def visible_to(cls, user_id: str) -> Select["SystemPromptTemplate"]:
        """Return templates the user can see: builtins + their own."""
        return select(cls).where(
            (cls.is_builtin == True) | (cls.user_id == user_id)  # noqa: E712
        )
