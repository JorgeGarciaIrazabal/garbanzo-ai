"""Scheduler module for background jobs using APScheduler."""

import logging
from datetime import UTC

from apscheduler.schedulers.asyncio import AsyncIOScheduler
from apscheduler.triggers.cron import CronTrigger
from apscheduler.triggers.interval import IntervalTrigger

from app.core.config import get_settings
from app.db.session import async_session_maker
from app.jobs.extract_memories_job import run_memory_extraction_job
from app.jobs.microapps_sync_job import run_microapps_sync_job
from app.jobs.scheduled_action_job import run_scheduled_action
from app.models.scheduled_action import ScheduledAction
from app.services.scheduled_action_service import (
    ScheduledActionService,
    build_trigger,
)
from app.topics.jobs import run_topic_consolidation_job

logger = logging.getLogger(__name__)

# Global scheduler instance
_scheduler: AsyncIOScheduler | None = None


def _job_id(action_id: str) -> str:
    return f"scheduled-action:{action_id}"


def get_scheduler() -> AsyncIOScheduler:
    """Get or create the global scheduler."""
    global _scheduler
    if _scheduler is None:
        _scheduler = AsyncIOScheduler()
    return _scheduler


def start_scheduler() -> None:
    """Start the scheduler and register all jobs."""
    scheduler = get_scheduler()

    # Register daily memory extraction job at 2 AM
    scheduler.add_job(
        run_memory_extraction_job,
        CronTrigger(hour=2, minute=0),  # Daily at 2:00 AM
        id="daily-memory-extraction",
        name="Daily Memory Extraction",
        replace_existing=True,
    )

    # Load every active user-defined scheduled action from the DB.
    scheduler.add_job(
        _load_active_scheduled_actions,
        id="bootstrap-scheduled-actions",
        name="Bootstrap Scheduled Actions",
        next_run_time=None,
    )

    # Micro-apps repo sync (deployments only): clone on first run, then
    # periodically fetch + rebase clean worktrees. See microapps_sync_job.
    settings = get_settings()
    if settings.topic_context_enabled and settings.topic_consolidation_interval_minutes > 0:
        scheduler.add_job(
            run_topic_consolidation_job,
            IntervalTrigger(minutes=settings.topic_consolidation_interval_minutes),
            id="topic-context-consolidation",
            name="Topic Context Consolidation",
            replace_existing=True,
            coalesce=True,
            max_instances=1,
            misfire_grace_time=300,
        )
    if settings.microapps_git_url and settings.microapps_pull_interval_minutes > 0:
        scheduler.add_job(
            run_microapps_sync_job,
            IntervalTrigger(minutes=settings.microapps_pull_interval_minutes),
            id="microapps-repo-sync",
            name="Micro-apps Repo Sync",
            replace_existing=True,
            coalesce=True,
            misfire_grace_time=60,
        )

    scheduler.start()
    # Trigger the bootstrap job right after startup so actions persisted from
    # a previous run are registered against this scheduler instance.
    scheduler.modify_job("bootstrap-scheduled-actions", next_run_time=_now())
    # Kick the repo sync immediately so a fresh deployment clones at startup
    # instead of waiting a full interval.
    if scheduler.get_job("microapps-repo-sync") is not None:
        scheduler.modify_job("microapps-repo-sync", next_run_time=_now())
    # Existing installations may have years of messages that were queued by
    # the topic-history backfill migration. Process them at startup instead of
    # showing an empty Personal map until the first hourly tick.
    if scheduler.get_job("topic-context-consolidation") is not None:
        scheduler.modify_job("topic-context-consolidation", next_run_time=_now())
    logger.info("Scheduler started with %d jobs", len(scheduler.get_jobs()))


def stop_scheduler() -> None:
    """Stop the scheduler gracefully."""
    global _scheduler
    if _scheduler is not None:
        _scheduler.shutdown()
        logger.info("Scheduler stopped")
        _scheduler = None


def add_memory_extraction_job(
    hour: int = 2,
    minute: int = 0,
    day_of_week: str = "*",
) -> None:
    """Add or update the daily memory extraction job."""
    scheduler = get_scheduler()
    scheduler.add_job(
        run_memory_extraction_job,
        CronTrigger(hour=hour, minute=minute, day_of_week=day_of_week),
        id="daily-memory-extraction",
        name="Daily Memory Extraction",
        replace_existing=True,
    )
    logger.info(
        "Memory extraction job scheduled for %02d:%02d (%s)",
        hour,
        minute,
        day_of_week,
    )


# ---------------------------------------------------------------------------
# User-defined scheduled actions
# ---------------------------------------------------------------------------


def register_scheduled_action(action: ScheduledAction) -> None:
    """Add or replace an APScheduler job for a user's scheduled action."""
    if not action.is_active:
        unregister_scheduled_action(action.id)
        return
    try:
        trigger = build_trigger(action.cron_expr, action.run_at)
    except ValueError:
        logger.exception("Cannot register scheduled action %s: invalid trigger", action.id)
        return
    scheduler = get_scheduler()
    scheduler.add_job(
        run_scheduled_action,
        trigger=trigger,
        id=_job_id(action.id),
        name=action.title or f"Scheduled action {action.id[:8]}",
        args=[action.id],
        replace_existing=True,
        misfire_grace_time=300,
        coalesce=True,
    )
    logger.info("Registered scheduled action job %s", action.id)


def unregister_scheduled_action(action_id: str) -> None:
    """Remove a scheduled action job if present."""
    scheduler = get_scheduler()
    job_id = _job_id(action_id)
    if scheduler.get_job(job_id) is not None:
        scheduler.remove_job(job_id)
        logger.info("Unregistered scheduled action job %s", action_id)


async def _load_active_scheduled_actions() -> None:
    """One-shot bootstrap: register every active scheduled action on startup."""
    async with async_session_maker() as db:
        svc = ScheduledActionService(db)
        actions = await svc.list_active()
        for action in actions:
            register_scheduled_action(action)
        logger.info("Bootstrapped %d active scheduled action(s)", len(actions))


def _now():
    from datetime import datetime

    return datetime.now(tz=UTC)
