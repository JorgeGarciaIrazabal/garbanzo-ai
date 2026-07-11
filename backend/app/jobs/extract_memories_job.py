"""Daily job for extracting user memories from conversations."""

import logging

from app.core.config import get_settings
from app.db.session import async_session_maker
from app.services.memory_extraction import MemoryExtractionService

logger = logging.getLogger(__name__)

# Job configuration defaults
DEFAULT_HOUR = 2  # 2 AM
DEFAULT_LOOKBACK_HOURS = 24


async def run_memory_extraction_job(
    hour: int = DEFAULT_HOUR,
    model: str | None = None,
    lookback_hours: int = DEFAULT_LOOKBACK_HOURS,
) -> None:
    """Run the memory extraction job.

    This job:
    1. Finds all users with conversations from the last N hours
    2. Calls the LLM to extract memorable facts about each user
    3. Stores the extracted facts as UserMemory records

    Args:
        hour: The hour of day to run (for logging purposes)
        model: The LLM model to use for extraction (defaults to
            ``settings.default_model``)
        lookback_hours: How many hours of conversation history to analyze
    """
    model = model or get_settings().default_model
    logger.info("Starting memory extraction job (model=%s, lookback=%dh)", model, lookback_hours)

    async with async_session_maker() as db:
        service = MemoryExtractionService(db)

        try:
            results = await service.extract_memories_for_all_users(
                hours=lookback_hours,
                model=model,
            )

            # Backfill embeddings for memories created while the embedder
            # was unavailable, so semantic ranking covers the whole store.
            from app.services.memory_service import MemoryService

            memory_service = MemoryService(db)
            for user_id in results:
                try:
                    await memory_service.backfill_missing_embeddings(user_id)
                except Exception as e:
                    logger.warning("Embedding backfill failed for %s: %s", user_id, e)

            total_memories = sum(len(memories) for memories in results.values())
            users_with_memories = sum(1 for memories in results.values() if memories)

            logger.info(
                "Memory extraction complete: %d users processed, %d total memories created",
                users_with_memories,
                total_memories,
            )

            for user_id, memories in results.items():
                if memories:
                    logger.info("User %s: %d memories created", user_id, len(memories))

        except Exception as e:
            logger.exception("Memory extraction job failed: %s", e)
            raise

    logger.info("Memory extraction job finished")
