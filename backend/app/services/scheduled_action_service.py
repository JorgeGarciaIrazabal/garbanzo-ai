"""Service for scheduled action CRUD and scheduler registration."""

from __future__ import annotations

import logging
import uuid
from datetime import UTC, datetime

from apscheduler.triggers.cron import CronTrigger
from apscheduler.triggers.date import DateTrigger
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.scheduled_action import ScheduledAction

logger = logging.getLogger(__name__)


def build_trigger(
    cron_expr: str | None, run_at: datetime | None
) -> CronTrigger | DateTrigger:
    """Build an APScheduler trigger from a cron expression or a datetime."""
    if cron_expr and run_at:
        raise ValueError("Specify cron_expr OR run_at, not both.")
    if cron_expr:
        try:
            return CronTrigger.from_crontab(cron_expr)
        except Exception as exc:
            raise ValueError(f"Invalid cron expression: {exc}") from exc
    if run_at is not None:
        if run_at.tzinfo is None:
            run_at = run_at.replace(tzinfo=UTC)
        return DateTrigger(run_date=run_at)
    raise ValueError("Either cron_expr or run_at is required.")


def compute_next_run(
    cron_expr: str | None, run_at: datetime | None
) -> datetime | None:
    """Compute the next fire time for the trigger, or None if already past."""
    trigger = build_trigger(cron_expr, run_at)
    now = datetime.now(tz=UTC)
    nxt = trigger.get_next_fire_time(None, now)
    if nxt is not None and nxt <= now:
        return None
    return nxt


class ScheduledActionService:
    def __init__(self, db: AsyncSession) -> None:
        self.db = db

    async def create(
        self,
        *,
        user_id: str,
        prompt: str,
        title: str | None = None,
        cron_expr: str | None = None,
        run_at: datetime | None = None,
        model: str | None = None,
        system_prompt: str | None = None,
        is_active: bool = True,
    ) -> ScheduledAction:
        # Validates and computes next_run (raises ValueError on bad trigger).
        next_run = compute_next_run(cron_expr, run_at) if is_active else None

        action = ScheduledAction(
            id=str(uuid.uuid4()),
            user_id=user_id,
            title=title,
            prompt=prompt,
            cron_expr=cron_expr,
            run_at=run_at,
            model=model,
            system_prompt=system_prompt,
            is_active=is_active,
            next_run=next_run,
        )
        self.db.add(action)
        await self.db.commit()
        await self.db.refresh(action)
        logger.info("Created scheduled action %s for user %s", action.id, user_id)
        return action

    async def get(self, action_id: str, user_id: str) -> ScheduledAction | None:
        query = select(ScheduledAction).where(
            ScheduledAction.id == action_id,
            ScheduledAction.user_id == user_id,
        )
        result = await self.db.execute(query)
        return result.scalar_one_or_none()

    async def get_any(self, action_id: str) -> ScheduledAction | None:
        """Fetch by ID without a user check (used by the scheduler job)."""
        result = await self.db.execute(
            select(ScheduledAction).where(ScheduledAction.id == action_id)
        )
        return result.scalar_one_or_none()

    async def list_for_user(self, user_id: str) -> list[ScheduledAction]:
        query = (
            select(ScheduledAction)
            .where(ScheduledAction.user_id == user_id)
            .order_by(ScheduledAction.created_at.desc())
        )
        result = await self.db.execute(query)
        return list(result.scalars().all())

    async def list_active(self) -> list[ScheduledAction]:
        """Every active scheduled action across all users (for scheduler boot)."""
        result = await self.db.execute(
            select(ScheduledAction).where(ScheduledAction.is_active.is_(True))
        )
        return list(result.scalars().all())

    async def update(
        self,
        action_id: str,
        user_id: str,
        *,
        title: str | None = None,
        prompt: str | None = None,
        cron_expr: str | None = None,
        run_at: datetime | None = None,
        model: str | None = None,
        system_prompt: str | None = None,
        is_active: bool | None = None,
        set_cron: bool = False,
        set_run_at: bool = False,
    ) -> ScheduledAction | None:
        """Partial update. ``set_cron`` / ``set_run_at`` let callers explicitly
        clear a field by passing None; otherwise None means "leave alone".
        """
        action = await self.get(action_id, user_id)
        if action is None:
            return None

        if title is not None:
            action.title = title
        if prompt is not None:
            action.prompt = prompt
        if model is not None:
            action.model = model
        if system_prompt is not None:
            action.system_prompt = system_prompt
        if set_cron:
            action.cron_expr = cron_expr
        if set_run_at:
            action.run_at = run_at
        if is_active is not None:
            action.is_active = is_active

        if not action.cron_expr and action.run_at is None:
            raise ValueError("Either cron_expr or run_at is required.")
        if action.cron_expr and action.run_at is not None:
            raise ValueError("Specify cron_expr OR run_at, not both.")

        if action.is_active:
            action.next_run = compute_next_run(action.cron_expr, action.run_at)
        else:
            action.next_run = None

        await self.db.commit()
        await self.db.refresh(action)
        return action

    async def delete(self, action_id: str, user_id: str) -> bool:
        action = await self.get(action_id, user_id)
        if action is None:
            return False
        await self.db.delete(action)
        await self.db.commit()
        logger.info("Deleted scheduled action %s for user %s", action_id, user_id)
        return True

    async def record_run(
        self,
        action_id: str,
        *,
        status_label: str,
        next_run: datetime | None,
    ) -> None:
        action = await self.get_any(action_id)
        if action is None:
            return
        action.last_run_at = datetime.now(tz=UTC)
        action.last_run_status = status_label
        # One-off actions auto-deactivate once they've fired.
        if action.run_at is not None:
            action.is_active = False
            action.next_run = None
        else:
            action.next_run = next_run
        await self.db.commit()
