"""Hourly dirty-user topic consolidation job."""

import asyncio
import logging
import uuid

from app.core.config import get_settings
from app.db import session as db_session
from app.topics.topic_consolidation_service import TopicConsolidationService

logger = logging.getLogger(__name__)


async def run_topic_consolidation_job() -> None:
    # A single run-wide owner lets the claim transaction and each short-lived
    # processing transaction prove that the lease was not stolen between them.
    # Expired leases are reclaimable on the next scheduler tick.
    lease_owner = f"scheduler:{uuid.uuid4()}"
    async with db_session.async_session_maker() as db:
        service = TopicConsolidationService(db)
        user_ids = await service.claim_dirty_users(owner=lease_owner)
    # Each user has an independent leased state row and its own DB session,
    # so bounded parallelism shortens an hourly backlog without turning one
    # user's large history into a serial bottleneck for everyone else.
    semaphore = asyncio.Semaphore(max(1, get_settings().topic_consolidation_concurrency))

    async def consolidate_one(user_id: str) -> None:
        async with semaphore:
            await _consolidate_one_user(user_id, lease_owner)

    await asyncio.gather(*(consolidate_one(user_id) for user_id in user_ids))


async def _consolidate_one_user(user_id: str, lease_owner: str) -> None:
    """Consolidate a claimed user and release its lease on any failure."""
    async with db_session.async_session_maker() as db:
        service = TopicConsolidationService(db)
        try:
            count = await service.consolidate_user(user_id, lease_owner=lease_owner)
            logger.info("Consolidated %d dirty topic(s) for user %s", count, user_id)
        except asyncio.CancelledError as error:
            # Application shutdown can cancel an in-flight cloud call.
            # Release the short lease first so the next instance can retry
            # promptly instead of waiting for the full lease timeout.
            await db.rollback()
            await service.record_failure(user_id, error)
            raise
        except Exception as error:
            await db.rollback()
            await service.record_failure(user_id, error)
            logger.exception("Topic consolidation failed for user %s", user_id)
