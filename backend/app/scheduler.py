"""Scheduler module for background jobs using APScheduler."""

import logging

from apscheduler.schedulers.asyncio import AsyncIOScheduler
from apscheduler.triggers.cron import CronTrigger

from app.jobs.extract_memories_job import run_memory_extraction_job

logger = logging.getLogger(__name__)

# Global scheduler instance
_scheduler: AsyncIOScheduler | None = None


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

    scheduler.start()
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
    """Add or update the daily memory extraction job.

    Args:
        hour: Hour of day to run (0-23)
        minute: Minute of hour (0-59)
        day_of_week: Day of week filter (e.g., 'mon-fri', '*', 'sun')
    """
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
