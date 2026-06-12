-- Semantic memory ranking: store an embedding per user memory so injection
-- can rank by relevance to the current message instead of substring match.
-- NULL embeddings are backfilled by the daily memory-extraction job.

CREATE EXTENSION IF NOT EXISTS vector;

ALTER TABLE user_memories
    ADD COLUMN IF NOT EXISTS embedding vector(768);
