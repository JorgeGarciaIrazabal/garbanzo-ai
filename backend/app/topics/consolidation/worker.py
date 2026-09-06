"""Worker lease claiming, queue draining, and failure backoff."""

from __future__ import annotations

import uuid
from datetime import UTC, datetime, timedelta

from sqlalchemy import exists, func, or_, select, update
from sqlalchemy.ext.asyncio import AsyncSession

from app.topics.models import (
    Topic,
    TopicIngestionEvent,
    TopicIngestionState,
)
from app.topics.topic_semantic_curator import TopicSemanticCurator


class ConsolidationWorker:
    """Manages worker leases and error backoff for consolidation queues."""

    @staticmethod
    async def claim_dirty_users(
        db: AsyncSession, *, limit: int = 100, owner: str | None = None
    ) -> tuple[list[str], str]:
        now = datetime.now(UTC)
        lease_owner = owner or str(uuid.uuid4())
        dirty_reasons = [
            TopicIngestionState.last_realtime_event_id
            > TopicIngestionState.last_consolidated_event_id,
            exists(
                select(1).where(
                    TopicIngestionEvent.user_id == TopicIngestionState.user_id,
                    TopicIngestionEvent.processed_at.is_(None),
                )
            ),
        ]
        curator_signature = TopicSemanticCurator.configuration_signature()
        if curator_signature is not None:
            dirty_reasons.append(
                exists(
                    select(1).where(
                        Topic.user_id == TopicIngestionState.user_id,
                        Topic.status == "active",
                        func.coalesce(
                            Topic.topic_metadata["graph_curator_signature"].as_string(),
                            "",
                        )
                        != curator_signature,
                    )
                )
            )
        candidates = list(
            (
                await db.scalars(
                    select(TopicIngestionState.user_id)
                    .where(
                        or_(*dirty_reasons),
                        or_(
                            TopicIngestionState.retry_at.is_(None),
                            TopicIngestionState.retry_at <= now,
                        ),
                        or_(
                            TopicIngestionState.lease_expires_at.is_(None),
                            TopicIngestionState.lease_expires_at <= now,
                        ),
                    )
                    .order_by(TopicIngestionState.updated_at)
                    .limit(limit)
                )
            ).all()
        )
        claimed: list[str] = []
        for user_id in candidates:
            result = await db.execute(
                update(TopicIngestionState)
                .where(
                    TopicIngestionState.user_id == user_id,
                    or_(
                        TopicIngestionState.lease_expires_at.is_(None),
                        TopicIngestionState.lease_expires_at <= now,
                    ),
                )
                .values(
                    lease_owner=lease_owner,
                    lease_expires_at=now + timedelta(minutes=15),
                )
            )
            if result.rowcount == 1:
                claimed.append(user_id)
        await db.commit()
        return claimed, lease_owner

    @staticmethod
    async def record_failure(db: AsyncSession, user_id: str, error: Exception) -> None:
        state = await db.get(TopicIngestionState, user_id)
        if state is None:
            return
        failures = (state.consecutive_failures or 0) + 1
        state.consecutive_failures = failures
        state.last_error = str(error)[:2000]
        state.retry_at = datetime.now(UTC) + timedelta(minutes=min(60, 2**failures))
        state.lease_owner = None
        state.lease_expires_at = None
        await db.commit()
