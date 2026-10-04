from datetime import datetime

from sqlalchemy import DateTime, ForeignKey, Select, String, func, select
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base


class Style(Base):
    """A saved, reusable bundle of model + thinking level + system prompt
    (Idea 2: "Styles"). Users compose one ad hoc per conversation, or save a
    named style ("Deep Work", "Quick Answers") to reuse later. Built-in styles
    (``is_builtin``) are shared across all users, seeded by ``StyleService``
    at startup, and read-only — the API refuses to update or delete them.

    ``system_prompt_template_id`` is nullable and ``ON DELETE SET NULL``
    (see 018_styles.sql): deleting the referenced template only clears the
    prompt half of the bundle, it never cascades to delete the style itself,
    since the model/thinking-level choices remain meaningful on their own.

    ``user_id`` is NULL for built-in styles (the column was made nullable in
    030_styles_builtin.sql). Owned styles keep it non-null. The FK to
    ``users(email) ON DELETE CASCADE`` is unchanged — NULL never matches a
    user row, so built-ins survive user deletes.

    ``locale`` on built-ins holds a BCP-47 language tag ('en', 'es') so the
    picker surfaces them in the user's language without mixing languages in
    the same view. Owned styles keep it NULL (language-neutral — the user
    named them), matching the ``system_prompt_templates.locale`` convention.

    ``User.default_style_id`` is authoritative for the user's default, including
    shared built-ins. API responses derive ``is_default`` from that pointer;
    no default flag is stored on a style row (migration 052 retires legacy
    storage). Read results must never be assigned to persisted rows.
    """

    __tablename__ = "styles"

    id: Mapped[str] = mapped_column(String(36), primary_key=True)
    # NULL for built-in styles (shared, read-only); a user email for owned.
    user_id: Mapped[str | None] = mapped_column(
        ForeignKey("users.email", ondelete="CASCADE"),
        nullable=True,
        index=True,
    )
    name: Mapped[str] = mapped_column(String(100), nullable=False)
    description: Mapped[str | None] = mapped_column(String(500), nullable=True)
    model_id: Mapped[str] = mapped_column(String(100), nullable=False)
    thinking_level: Mapped[str | None] = mapped_column(
        String(10),
        nullable=True,
        comment=(
            "One of 'off' | 'low' | 'medium' | 'high', or NULL for the "
            "provider default. Same representation as "
            "Conversation.thinking_level (017_conversation_thinking_level.sql) "
            "— validated at the API boundary by the shared Pydantic "
            "ThinkingLevel literal, not by a DB constraint."
        ),
    )
    system_prompt_template_id: Mapped[str | None] = mapped_column(
        ForeignKey("system_prompt_templates.id", ondelete="SET NULL"),
        nullable=True,
    )
    is_builtin: Mapped[bool] = mapped_column(default=False, nullable=False)
    # BCP-47 tag for built-in styles ('en', 'es'); NULL for user-saved styles
    # (language-neutral). NULL acts as a wildcard, surfacing in any locale
    # request — same convention as system_prompt_templates.locale.
    locale: Mapped[str | None] = mapped_column(String(5), nullable=True, default=None)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        server_default=func.now(),
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        server_default=func.now(),
        onupdate=func.now(),
    )

    @classmethod
    def owned_by(cls, user_id: str) -> Select["Style"]:
        """Return a SELECT query scoped to a single user's styles, including
        the shared built-ins (user_id NULL) so the picker and API surface
        both in one list."""
        return select(cls).where(
            (cls.user_id == user_id) | (cls.is_builtin == True)  # noqa: E712
        )
