"""Service for saved styles (Idea 2: "Styles") — CRUD + default-selection."""

from __future__ import annotations

import logging
import uuid

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.style import Style
from app.models.system_prompt import SystemPromptTemplate

logger = logging.getLogger(__name__)


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

        Flushed (not just staged) before the caller sets the new default so
        the partial unique index (at most one default per user) never sees
        two true rows at once within the same transaction.
        """
        query = select(Style).where(Style.user_id == user_id, Style.is_default == True)  # noqa: E712
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
        result = await self.db.execute(
            select(Style).where(Style.id == style_id, Style.user_id == user_id)
        )
        return result.scalar_one_or_none()

    async def list_for_user(self, user_id: str) -> list[Style]:
        result = await self.db.execute(Style.owned_by(user_id).order_by(Style.created_at.asc()))
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
        """
        style = await self.get(style_id, user_id)
        if style is None:
            return None

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
        style = await self.get(style_id, user_id)
        if style is None:
            return False
        await self.db.delete(style)
        await self.db.commit()
        logger.info("Deleted style %s for user %s", style_id, user_id)
        return True
