"""Service for user memory CRUD operations and relevance ranking."""

import logging
import uuid

from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.memory import UserMemory
from app.services.embedding_provider import EmbeddingProvider, get_embedding_provider

logger = logging.getLogger(__name__)

# How strongly age discounts relevance: distance penalty per day. At 0.001,
# a memory from ~100 days ago needs to be 0.1 cosine-distance more relevant
# than a fresh one to outrank it — gentle decay, never a hard cutoff.
_AGE_PENALTY_PER_DAY = 0.001

# Candidates at or above this cosine similarity to an existing memory are
# treated as re-learned duplicates and dropped.
_DUPLICATE_SIMILARITY = 0.90


class MemoryService:
    """Handles creation, retrieval, update, and deletion of user memories."""

    def __init__(
        self,
        db: AsyncSession,
        embedding_provider: EmbeddingProvider | None = None,
    ):
        self.db = db
        self._embedder = embedding_provider or get_embedding_provider()

    async def _embed_or_none(self, content: str) -> list[float] | None:
        """Embed ``content``; None when the embedder is unavailable.

        Memories must stay writable when Ollama is down — the daily job
        backfills missing embeddings later.
        """
        try:
            vectors = await self._embedder.embed([content])
            return vectors[0] if vectors else None
        except Exception as e:
            logger.warning("Memory embedding failed (will backfill later): %s", e)
            return None

    async def create_memory(
        self,
        user_id: str,
        content: str,
        source_conversation_id: str | None = None,
        embedding: list[float] | None = None,
    ) -> UserMemory:
        """Create a new memory for a user.

        ``embedding`` may be supplied by callers that already computed it
        (the extraction pipeline embeds candidates for dedup first).
        """
        memory = UserMemory(
            id=str(uuid.uuid4()),
            user_id=user_id,
            content=content,
            source_conversation_id=source_conversation_id,
            embedding=embedding if embedding is not None else await self._embed_or_none(content),
        )

        self.db.add(memory)
        await self.db.commit()
        await self.db.refresh(memory)

        logger.info("Created memory %s for user %s", memory.id, user_id)
        return memory

    async def get_memory(self, memory_id: str, user_id: str) -> UserMemory | None:
        """Get a specific memory by ID, verifying ownership."""
        query = select(UserMemory).where(
            UserMemory.id == memory_id,
            UserMemory.user_id == user_id,
        )
        result = await self.db.execute(query)
        return result.scalar_one_or_none()

    async def get_active_memories(self, user_id: str) -> list[UserMemory]:
        """Get all active memories for a user."""
        query = UserMemory.active(user_id).order_by(UserMemory.created_at.desc())
        result = await self.db.execute(query)
        return list(result.scalars().all())

    async def get_relevant_memories(
        self,
        user_id: str,
        query: str | None = None,
        limit: int = 10,
    ) -> list[UserMemory]:
        """Return the memories most relevant to ``query``, up to ``limit``.

        Ranking is semantic (cosine distance to the query embedding) with a
        gentle recency decay, so a large memory store surfaces what matters
        for *this* message instead of injecting everything. Falls back to
        most-recent-first when no query is given or the embedding path is
        unavailable (embedder down, non-pgvector test database).
        """
        if query:
            try:
                query_vector = (await self._embedder.embed([query]))[0]
                distance = UserMemory.embedding.cosine_distance(query_vector)
                age_days = (
                    func.extract("epoch", func.now() - UserMemory.created_at)
                    / 86400.0
                )
                stmt = (
                    select(UserMemory)
                    .where(
                        UserMemory.user_id == user_id,
                        UserMemory.is_active == True,  # noqa: E712
                        UserMemory.embedding.is_not(None),
                    )
                    .order_by(distance + age_days * _AGE_PENALTY_PER_DAY)
                    .limit(limit)
                )
                ranked = list((await self.db.execute(stmt)).scalars().all())

                # Memories awaiting embedding backfill must not be invisible:
                # top up with the most recent unembedded ones.
                if len(ranked) < limit:
                    fill_stmt = (
                        select(UserMemory)
                        .where(
                            UserMemory.user_id == user_id,
                            UserMemory.is_active == True,  # noqa: E712
                            UserMemory.embedding.is_(None),
                        )
                        .order_by(UserMemory.created_at.desc())
                        .limit(limit - len(ranked))
                    )
                    ranked.extend((await self.db.execute(fill_stmt)).scalars().all())
                return ranked
            except Exception as e:
                logger.warning(
                    "Semantic memory ranking unavailable, using recency: %s", e
                )

        stmt = (
            select(UserMemory)
            .where(
                UserMemory.user_id == user_id,
                UserMemory.is_active == True,  # noqa: E712
            )
            .order_by(UserMemory.created_at.desc())
            .limit(limit)
        )
        result = await self.db.execute(stmt)
        return list(result.scalars().all())

    @staticmethod
    def _cosine(a, b) -> float:
        dot = sum(x * y for x, y in zip(a, b))
        norm_a = sum(x * x for x in a) ** 0.5
        norm_b = sum(y * y for y in b) ** 0.5
        if norm_a == 0 or norm_b == 0:
            return 0.0
        return dot / (norm_a * norm_b)

    async def filter_duplicate_candidates(
        self, user_id: str, candidates: list[str]
    ) -> tuple[list[str], list[list[float] | None]]:
        """Filter out candidates that duplicate existing memories (or each
        other), by exact text and then by embedding similarity.

        Returns ``(kept_texts, embeddings)`` aligned by index, with the
        embeddings reusable for storage. When the embedder is unavailable
        only the text pass applies and embeddings are None.
        """
        existing = await self.get_active_memories(user_id)
        existing_texts = {m.content.strip().lower() for m in existing}

        texts: list[str] = []
        seen: set[str] = set()
        for candidate in candidates:
            key = candidate.strip().lower()
            if key and key not in existing_texts and key not in seen:
                seen.add(key)
                texts.append(candidate.strip())
        if not texts:
            return [], []

        try:
            vectors = await self._embedder.embed(texts)
        except Exception as e:
            logger.warning("Dedup embeddings unavailable (text-only dedup): %s", e)
            return texts, [None] * len(texts)

        existing_vectors = [m.embedding for m in existing if m.embedding is not None]
        kept_texts: list[str] = []
        kept_vectors: list[list[float] | None] = []
        for text, vector in zip(texts, vectors):
            duplicate = any(
                self._cosine(vector, other) >= _DUPLICATE_SIMILARITY
                for other in existing_vectors
            ) or any(
                self._cosine(vector, other) >= _DUPLICATE_SIMILARITY
                for other in kept_vectors
                if other is not None
            )
            if duplicate:
                logger.info("Skipping near-duplicate memory: %.60r", text)
                continue
            kept_texts.append(text)
            kept_vectors.append(vector)
        return kept_texts, kept_vectors

    async def backfill_missing_embeddings(self, user_id: str, batch_size: int = 32) -> int:
        """Embed active memories that have no embedding yet. Returns count."""
        stmt = (
            select(UserMemory)
            .where(
                UserMemory.user_id == user_id,
                UserMemory.is_active == True,  # noqa: E712
                UserMemory.embedding.is_(None),
            )
            .limit(batch_size)
        )
        missing = list((await self.db.execute(stmt)).scalars().all())
        if not missing:
            return 0
        try:
            vectors = await self._embedder.embed([m.content for m in missing])
        except Exception as e:
            logger.warning("Memory embedding backfill skipped: %s", e)
            return 0
        for memory, vector in zip(missing, vectors):
            memory.embedding = vector
        await self.db.commit()
        logger.info(
            "Backfilled embeddings for %d memories (user %s)", len(missing), user_id
        )
        return len(missing)

    async def update_memory(
        self,
        memory_id: str,
        user_id: str,
        content: str | None = None,
        is_active: bool | None = None,
    ) -> UserMemory | None:
        """Update a memory's content or active status."""
        memory = await self.get_memory(memory_id, user_id)
        if not memory:
            return None

        if content is not None:
            memory.content = content
            # Content changed → the old embedding no longer describes it.
            memory.embedding = await self._embed_or_none(content)
        if is_active is not None:
            memory.is_active = is_active

        await self.db.commit()
        await self.db.refresh(memory)

        logger.info("Updated memory %s for user %s", memory_id, user_id)
        return memory

    async def deactivate_memory(self, memory_id: str, user_id: str) -> bool:
        """Soft-deactivate a memory by setting is_active=False."""
        memory = await self.get_memory(memory_id, user_id)
        if not memory:
            return False

        memory.is_active = False
        await self.db.commit()

        logger.info("Deactivated memory %s for user %s", memory_id, user_id)
        return True

    async def delete_memory(self, memory_id: str, user_id: str) -> bool:
        """Permanently delete a memory."""
        memory = await self.get_memory(memory_id, user_id)
        if not memory:
            return False

        await self.db.delete(memory)
        await self.db.commit()

        logger.info("Deleted memory %s for user %s", memory_id, user_id)
        return True
