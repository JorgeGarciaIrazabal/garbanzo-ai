"""Service for saved styles (Idea 2: "Styles") — CRUD + default-selection +
built-in seeding.

Built-in styles are shared across all users (``user_id`` NULL, ``is_builtin``
TRUE) and read-only — [update][StyleService.update] and [delete][
StyleService.delete] refuse them. They are seeded at startup from
[BUILTIN_STYLES] using the built-in system prompt templates of the same name
as the prompt half of the bundle, so the picker surfaces them as one-tap cards
in the user's language alongside the user's own saved styles.
"""

from __future__ import annotations

import logging
import uuid
from dataclasses import dataclass

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.style import Style
from app.models.system_prompt import SystemPromptTemplate

logger = logging.getLogger(__name__)


@dataclass
class BuiltinReadOnlyError(Exception):
    """Raised when an update or delete targets a built-in style."""

    style_id: str

    def __init__(self, style_id: str) -> None:
        super().__init__(f"Built-in style {style_id!r} is read-only")
        self.style_id = style_id


# Built-in styles: predefined bundles shipped with the app and shown as
# one-tap cards in the style picker. Each entry references its prompt half by
# the (name, locale) of a built-in SystemPromptTemplate — resolved at seed
# time — so the seeder never hardcodes template IDs (which are random UUIDs)
# and stays in lock-step with SystemPromptService.BUILTIN_TEMPLATES.
#
# Model IDs name Ollama models as the /chat/models endpoint reports them
# (e.g. "minimax-m3:cloud"); the picker hides a built-in whose model isn't
# installed, so a built-in pointing at a model the deployment lacks simply
# won't surface until the model is pulled.
#
# thinking_level is left NULL (provider default) everywhere: the conciser/
# reasoning styles here ride the model's own thinking behaviour rather than
# forcing a level — same as a user-saved style that picks only a model + a
# prompt.
BUILTIN_STYLES: list[dict[str, str | None]] = [
    {
        "locale": "en",
        "name": "Concise",
        "description": "Short, direct, to-the-point answers.",
        "model_id": "minimax-m3:cloud",
        "template_name": "Concise",
        "thinking_level": None,
    },
    {
        "locale": "en",
        "name": "Truth Seeker",
        "description": "Verifies claims, cites sources, flags uncertainty.",
        "model_id": "glm-5.2:cloud",
        "template_name": "Truth Seeker",
        "thinking_level": "medium",
    },
    {
        "locale": "en",
        "name": "Writing & Stories",
        "description": "Storytelling partner for fiction and non-fiction.",
        "model_id": "minimax-m3:cloud",
        "template_name": "Writing Coach",
        "thinking_level": None,
    },
    {
        "locale": "en",
        "name": "Coding",
        "description": "Focused, pragmatic software engineering helper.",
        "model_id": "kimi-k2.7-code:cloud",
        "template_name": "Coding Assistant",
        "thinking_level": None,
    },
    {
        "locale": "en",
        "name": "Tutoring",
        "description": "Teaches by asking guiding questions.",
        "model_id": "glm-5.2:cloud",
        "template_name": "Socratic Tutor",
        "thinking_level": "medium",
    },
    {
        "locale": "en",
        "name": "Brainstorm",
        "description": "Generates varied ideas quickly.",
        "model_id": "minimax-m3:cloud",
        "template_name": "Brainstorm Partner",
        "thinking_level": None,
    },
    {
        "locale": "es",
        "name": "Conciso",
        "description": "Respuestas breves, directas y al punto.",
        "model_id": "minimax-m3:cloud",
        "template_name": "Conciso",
        "thinking_level": None,
    },
    {
        "locale": "es",
        "name": "Buscador de la verdad",
        "description": "Verifica afirmaciones, cita fuentes y marca la incertidumbre.",
        "model_id": "glm-5.2:cloud",
        "template_name": "Buscador de la verdad",
        "thinking_level": "medium",
    },
    {
        "locale": "es",
        "name": "Escritura e historias",
        "description": "Compañero de narración para ficción y no ficción.",
        "model_id": "minimax-m3:cloud",
        "template_name": "Coach de escritura",
        "thinking_level": None,
    },
    {
        "locale": "es",
        "name": "Programación",
        "description": "Ayuda de ingeniería de software enfocada y pragmática.",
        "model_id": "kimi-k2.7-code:cloud",
        "template_name": "Asistente de programación",
        "thinking_level": None,
    },
    {
        "locale": "es",
        "name": "Tutoría",
        "description": "Enseña haciendo preguntas guía.",
        "model_id": "glm-5.2:cloud",
        "template_name": "Tutor socrático",
        "thinking_level": "medium",
    },
    {
        "locale": "es",
        "name": "Lluvia de ideas",
        "description": "Genera ideas variadas rápidamente.",
        "model_id": "minimax-m3:cloud",
        "template_name": "Compañero de lluvia de ideas",
        "thinking_level": None,
    },
]


class StyleService:
    def __init__(self, db: AsyncSession) -> None:
        self.db = db

    async def _validate_template(self, template_id: str | None, user_id: str) -> None:
        """Raise ValueError if ``template_id`` isn't visible to ``user_id``.

        Visible = a builtin persona or one of the user's own templates —
        same rule SystemPromptTemplate.visible_to uses elsewhere, so a style
        can't be pointed at another user's private template.
        """
        if template_id is None:
            return
        result = await self.db.execute(
            SystemPromptTemplate.visible_to(user_id).where(SystemPromptTemplate.id == template_id)
        )
        if result.scalar_one_or_none() is None:
            raise ValueError("System prompt template not found")

    async def _clear_other_defaults(self, user_id: str, exclude_id: str | None) -> None:
        """Unset ``is_default`` on every other style owned by ``user_id``.

        Only the user's own styles are considered — built-ins are never
        flagged default, so they stay out of this query naturally. Flushed
        (not just staged) before the caller sets the new default so the
        partial unique index (at most one default per user) never sees two
        true rows at once within the same transaction.
        """
        query = select(Style).where(
            Style.user_id == user_id,
            Style.is_default == True,  # noqa: E712
        )
        if exclude_id is not None:
            query = query.where(Style.id != exclude_id)
        result = await self.db.execute(query)
        for other in result.scalars().all():
            other.is_default = False
        await self.db.flush()

    async def create(
        self,
        *,
        user_id: str,
        name: str,
        model_id: str,
        thinking_level: str | None = None,
        system_prompt_template_id: str | None = None,
        is_default: bool = False,
    ) -> Style:
        await self._validate_template(system_prompt_template_id, user_id)

        if is_default:
            await self._clear_other_defaults(user_id, exclude_id=None)

        style = Style(
            id=str(uuid.uuid4()),
            user_id=user_id,
            name=name,
            model_id=model_id,
            thinking_level=thinking_level,
            system_prompt_template_id=system_prompt_template_id,
            is_default=is_default,
        )
        self.db.add(style)
        await self.db.commit()
        await self.db.refresh(style)
        logger.info("Created style %s for user %s", style.id, user_id)
        return style

    async def get(self, style_id: str, user_id: str) -> Style | None:
        """Return the style if it's a built-in or one owned by ``user_id``."""
        result = await self.db.execute(Style.owned_by(user_id).where(Style.id == style_id))
        return result.scalar_one_or_none()

    async def list_for_user(self, user_id: str) -> list[Style]:
        """Built-ins first (by name within a locale), then the user's own
        styles in creation order — so the picker renders the shared presets
        at the top of the Styles segment and the user's saved styles below.
        """
        result = await self.db.execute(
            Style.owned_by(user_id).order_by(
                Style.is_builtin.desc(),
                Style.locale.asc(),
                Style.name.asc(),
                Style.created_at.asc(),
            )
        )
        return list(result.scalars().all())

    async def update(
        self,
        style_id: str,
        user_id: str,
        *,
        name: str | None = None,
        model_id: str | None = None,
        thinking_level: str | None = None,
        set_thinking_level: bool = False,
        system_prompt_template_id: str | None = None,
        set_template_id: bool = False,
        is_default: bool | None = None,
    ) -> Style | None:
        """Partial update. ``set_thinking_level`` / ``set_template_id`` let
        callers explicitly clear those fields by passing None; otherwise
        None means "leave alone" (mirrors ScheduledActionService.update).

        Returns None when the style isn't visible to the user (404 in the
        endpoint). Built-in styles are read-only — raises
        [BuiltinReadOnlyError] the endpoint maps to 403.
        """
        style = await self.get(style_id, user_id)
        if style is None:
            return None
        if style.is_builtin:
            raise BuiltinReadOnlyError(style_id)

        if name is not None:
            style.name = name
        if model_id is not None:
            style.model_id = model_id
        if set_thinking_level:
            style.thinking_level = thinking_level
        if set_template_id:
            await self._validate_template(system_prompt_template_id, user_id)
            style.system_prompt_template_id = system_prompt_template_id

        if is_default is True:
            await self._clear_other_defaults(user_id, exclude_id=style.id)
            style.is_default = True
        elif is_default is False:
            style.is_default = False

        await self.db.commit()
        await self.db.refresh(style)
        return style

    async def delete(self, style_id: str, user_id: str) -> bool:
        """Return True on success, False when the style isn't visible to the
        user (404 in the endpoint). Raises [BuiltinReadOnlyError] for a
        read-only built-in style (403 in the endpoint).
        """
        style = await self.get(style_id, user_id)
        if style is None:
            return False
        if style.is_builtin:
            raise BuiltinReadOnlyError(style_id)
        await self.db.delete(style)
        await self.db.commit()
        logger.info("Deleted style %s for user %s", style_id, user_id)
        return True

    # ---- Built-in seeding -------------------------------------------------

    async def seed_builtin_styles(self) -> int:
        """Insert any missing built-in styles. Returns count created.

        Idempotency keys on (name, locale): the same name can exist once per
        locale, matching the SystemPromptTemplate seeding contract. Template
        references are resolved by (template_name, locale) against the
        built-in SystemPromptTemplate rows seeded by SystemPromptService — a
        built-in style whose template isn't found (e.g. the system prompt
        seeder hasn't run yet) is skipped until the next startup pass rather
        than written with a dangling NULL template.
        """
        existing_keys = set(
            (
                await self.db.execute(
                    select(Style.name, Style.locale).where(Style.is_builtin == True)  # noqa: E712
                )
            ).all()
        )

        created = 0
        for spec in BUILTIN_STYLES:
            key = (spec["name"], spec["locale"])
            if key in existing_keys:
                continue
            template_id = await self._resolve_builtin_template(
                spec["template_name"], spec["locale"] or ""
            )
            if template_id is None:
                logger.warning(
                    "Skipping built-in style %r (%s): template %r not seeded yet",
                    spec["name"],
                    spec["locale"],
                    spec["template_name"],
                )
                continue
            self.db.add(
                Style(
                    id=str(uuid.uuid4()),
                    user_id=None,
                    name=spec["name"],
                    description=spec["description"],
                    model_id=spec["model_id"],
                    thinking_level=spec["thinking_level"],
                    system_prompt_template_id=template_id,
                    is_builtin=True,
                    locale=spec["locale"],
                    is_default=False,
                )
            )
            created += 1

        if created:
            await self.db.commit()
            logger.info("Seeded %d built-in styles", created)
        return created

    async def _resolve_builtin_template(self, name: str, locale: str) -> str | None:
        result = await self.db.execute(
            select(SystemPromptTemplate.id).where(
                SystemPromptTemplate.is_builtin == True,  # noqa: E712
                SystemPromptTemplate.name == name,
                SystemPromptTemplate.locale == locale,
            )
        )
        return result.scalar_one_or_none()


async def seed_builtin_styles_task() -> None:
    """Run at startup to ensure built-in styles exist. Must run *after*
    seed_builtin_templates_task so the template references resolve.
    """
    from app.db.session import async_session_maker

    async with async_session_maker() as db:
        svc = StyleService(db)
        try:
            await svc.seed_builtin_styles()
        except Exception as e:
            logger.warning("Failed to seed built-in styles: %s", e)
