-- Read-only archive of a primary conversation's message history, attached
-- to the topic that was active when the user switched away. The archive
-- preserves the full message payload so a future "enhance this topic"
-- pass can re-derive evidence without touching the primary conversation,
-- which has already been cleared for the new topic.

CREATE TABLE IF NOT EXISTS topic_archives (
    id VARCHAR(36) PRIMARY KEY,
    user_id TEXT NOT NULL REFERENCES users(email) ON DELETE CASCADE,
    topic_id TEXT REFERENCES topics(id) ON DELETE SET NULL,
    from_topic_id TEXT REFERENCES topics(id) ON DELETE SET NULL,
    conversation_id TEXT NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
    message_count INTEGER NOT NULL DEFAULT 0,
    payload JSONB NOT NULL,
    short_summary TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS ix_topic_archives_user_created
    ON topic_archives (user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS ix_topic_archives_topic
    ON topic_archives (topic_id);
