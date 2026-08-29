"""Tests for the daily memory extraction background job."""

import logging
from datetime import UTC, datetime, timedelta
from unittest.mock import AsyncMock, MagicMock, patch

import pytest
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.security import hash_password
from app.jobs.extract_memories_job import run_memory_extraction_job
from app.models.conversation import Conversation
from app.models.memory import UserMemory
from app.models.user import User


@pytest.mark.asyncio
async def test_run_memory_extraction_job_happy_path(db_session: AsyncSession, caplog):
    """Job processes users with recent conversations and stores memories."""
    await _seed_users(db_session, ["alice@example.com", "bob@example.com"])
    now = datetime.now(UTC)

    # Alice and Bob have recent conversations
    conv_a = Conversation(id="a1", user_id="alice@example.com", title="A", updated_at=now)
    conv_b = Conversation(id="b1", user_id="bob@example.com", title="B", updated_at=now)
    # Carol has no recent conversation
    await _seed_users(db_session, ["carol@example.com"])
    conv_c = Conversation(
        id="c1", user_id="carol@example.com", title="C", updated_at=now - timedelta(hours=48)
    )

    db_session.add_all([conv_a, conv_b, conv_c])
    await db_session.commit()

    # Mock the MemoryExtractionService
    mock_service = MagicMock()
    mock_service.extract_memories_for_all_users = AsyncMock(
        return_value={
            "alice@example.com": [
                UserMemory(
                    id="m1",
                    user_id="alice@example.com",
                    content="Alice memory",
                    embedding=[0.1] * 384,
                )
            ],
            "bob@example.com": [
                UserMemory(
                    id="m2", user_id="bob@example.com", content="Bob memory", embedding=[0.2] * 384
                )
            ],
            "carol@example.com": [],  # No recent convos
        }
    )

    # Mock MemoryService for backfill
    mock_mem_svc = MagicMock()
    mock_mem_svc.backfill_missing_embeddings = AsyncMock(return_value=0)

    with (
        patch("app.jobs.extract_memories_job.MemoryExtractionService", return_value=mock_service),
        patch("app.services.memory_service.MemoryService", return_value=mock_mem_svc),
        patch("app.jobs.extract_memories_job.async_session_maker") as mock_session_maker,
        caplog.at_level(logging.INFO),
    ):
        mock_session_maker.return_value.__aenter__ = AsyncMock(return_value=db_session)
        mock_session_maker.return_value.__aexit__ = AsyncMock(return_value=False)

        await run_memory_extraction_job(hour=2, model="llama3.2", lookback_hours=24)

    # Service was called with correct params
    mock_service.extract_memories_for_all_users.assert_awaited_once_with(
        hours=24,
        model="llama3.2",
    )

    # Backfill was called for all users in results (including those with empty memory lists)
    assert mock_mem_svc.backfill_missing_embeddings.await_count == 3

    # Logs confirm completion
    assert "Memory extraction complete" in caplog.text
    assert "2 users processed" in caplog.text
    assert "2 total memories created" in caplog.text


@pytest.mark.asyncio
async def test_run_memory_extraction_job_no_users_with_conversations(
    db_session: AsyncSession, caplog
):
    """Job handles empty user set gracefully."""
    await _seed_users(db_session, ["alice@example.com"])
    # No conversations at all

    mock_service = MagicMock()
    mock_service.extract_memories_for_all_users = AsyncMock(return_value={})

    with (
        patch("app.jobs.extract_memories_job.MemoryExtractionService", return_value=mock_service),
        patch("app.jobs.extract_memories_job.async_session_maker") as mock_session_maker,
        patch("app.jobs.extract_memories_job.get_settings") as mock_settings,
        caplog.at_level(logging.INFO),
    ):
        mock_settings.return_value.memory_extraction_model = "glm-5.3:cloud"
        mock_session_maker.return_value.__aenter__ = AsyncMock(return_value=db_session)
        mock_session_maker.return_value.__aexit__ = AsyncMock(return_value=False)

        await run_memory_extraction_job(lookback_hours=24)

    mock_service.extract_memories_for_all_users.assert_awaited_once_with(
        hours=24,
        model="glm-5.3:cloud",
    )
    assert "Memory extraction complete: 0 users processed, 0 total memories created" in caplog.text


@pytest.mark.asyncio
async def test_run_memory_extraction_job_service_error_logged_and_re_raised(
    db_session: AsyncSession, caplog
):
    """Exceptions from the service are logged and re-raised."""
    await _seed_users(db_session, ["alice@example.com"])
    now = datetime.now(UTC)
    conv = Conversation(id="a1", user_id="alice@example.com", title="A", updated_at=now)
    db_session.add(conv)
    await db_session.commit()

    mock_service = MagicMock()
    mock_service.extract_memories_for_all_users = AsyncMock(side_effect=RuntimeError("LLM down"))

    with (
        patch("app.jobs.extract_memories_job.MemoryExtractionService", return_value=mock_service),
        patch("app.jobs.extract_memories_job.async_session_maker") as mock_session_maker,
        caplog.at_level(logging.ERROR),
    ):
        mock_session_maker.return_value.__aenter__ = AsyncMock(return_value=db_session)
        mock_session_maker.return_value.__aexit__ = AsyncMock(return_value=False)

        with pytest.raises(RuntimeError, match="LLM down"):
            await run_memory_extraction_job(lookback_hours=24)

    assert "Memory extraction job failed" in caplog.text


@pytest.mark.asyncio
async def test_run_memory_extraction_job_backfill_error_logged_but_continues(
    db_session: AsyncSession, caplog
):
    """Embedding backfill failure for one user doesn't fail the whole job."""
    await _seed_users(db_session, ["alice@example.com", "bob@example.com"])
    now = datetime.now(UTC)
    conv_a = Conversation(id="a1", user_id="alice@example.com", title="A", updated_at=now)
    conv_b = Conversation(id="b1", user_id="bob@example.com", title="B", updated_at=now)
    db_session.add_all([conv_a, conv_b])
    await db_session.commit()

    mock_service = MagicMock()
    mock_service.extract_memories_for_all_users = AsyncMock(
        return_value={
            "alice@example.com": [UserMemory(id="m1", user_id="alice@example.com", content="A")],
            "bob@example.com": [UserMemory(id="m2", user_id="bob@example.com", content="B")],
        }
    )

    mock_mem_svc = MagicMock()

    # Alice succeeds, Bob fails
    async def backfill(user_id):
        if user_id == "bob@example.com":
            raise RuntimeError("Embedding service down")
        return 0

    mock_mem_svc.backfill_missing_embeddings = backfill

    with (
        patch("app.jobs.extract_memories_job.MemoryExtractionService", return_value=mock_service),
        patch("app.services.memory_service.MemoryService", return_value=mock_mem_svc),
        patch("app.jobs.extract_memories_job.async_session_maker") as mock_session_maker,
        caplog.at_level(logging.WARNING),
    ):
        mock_session_maker.return_value.__aenter__ = AsyncMock(return_value=db_session)
        mock_session_maker.return_value.__aexit__ = AsyncMock(return_value=False)

        await run_memory_extraction_job(lookback_hours=24)

    assert "Embedding backfill failed for bob@example.com" in caplog.text
    # Job still completes (no exception)


async def _seed_users(db: AsyncSession, emails: list[str]):
    for e in emails:
        db.add(User(email=e, hashed_password=hash_password("pw")))
    await db.commit()
