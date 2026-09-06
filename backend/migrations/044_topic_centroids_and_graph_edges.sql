-- Topic centroid vector embeddings and cross-topic graph relationship edges.

ALTER TABLE topics
    ADD COLUMN IF NOT EXISTS centroid_embedding vector(768);

CREATE TABLE IF NOT EXISTS topic_relations (
    id                 VARCHAR(36) PRIMARY KEY,
    user_id            VARCHAR(255) NOT NULL REFERENCES users(email) ON DELETE CASCADE,
    source_topic_id    VARCHAR(36) NOT NULL REFERENCES topics(id) ON DELETE CASCADE,
    target_topic_id    VARCHAR(36) NOT NULL REFERENCES topics(id) ON DELETE CASCADE,
    relation_type      VARCHAR(40) NOT NULL,
    confidence         DOUBLE PRECISION NOT NULL DEFAULT 1.0,
    metadata           JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_at         TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at         TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (user_id, source_topic_id, target_topic_id, relation_type)
);

CREATE INDEX IF NOT EXISTS ix_topic_relations_user_source
    ON topic_relations (user_id, source_topic_id);
CREATE INDEX IF NOT EXISTS ix_topic_relations_user_target
    ON topic_relations (user_id, target_topic_id);

-- IVFFlat cosine similarity index for topic centroid embeddings.
CREATE INDEX IF NOT EXISTS ix_topics_centroid_embedding_cosine
    ON topics USING ivfflat (centroid_embedding vector_cosine_ops)
    WITH (lists = 100);

-- IVFFlat cosine similarity index for grounded topic assertions.
CREATE INDEX IF NOT EXISTS ix_topic_assertions_embedding_cosine
    ON topic_assertions USING ivfflat (embedding vector_cosine_ops)
    WITH (lists = 100);
