-- Primary unified chat and durable user-owned topic identity.
-- Additive by design: every existing conversation remains a legacy thread.

ALTER TABLE conversations
    ADD COLUMN IF NOT EXISTS is_primary BOOLEAN NOT NULL DEFAULT FALSE,
    ADD COLUMN IF NOT EXISTS topic_is_pinned BOOLEAN NOT NULL DEFAULT FALSE,
    ADD COLUMN IF NOT EXISTS context_version BIGINT NOT NULL DEFAULT 0;

CREATE UNIQUE INDEX IF NOT EXISTS uq_conversations_active_primary_user
    ON conversations (user_id)
    WHERE is_primary = TRUE AND is_deleted = FALSE;

CREATE TABLE IF NOT EXISTS topics (
    id                         VARCHAR(36) PRIMARY KEY,
    user_id                    VARCHAR(255) NOT NULL REFERENCES users(email) ON DELETE CASCADE,
    parent_id                  VARCHAR(36) REFERENCES topics(id) ON DELETE SET NULL,
    label                      VARCHAR(200) NOT NULL,
    normalized_label           VARCHAR(200) NOT NULL,
    origin                     VARCHAR(20) NOT NULL DEFAULT 'history',
    base_score                 DOUBLE PRECISION NOT NULL DEFAULT 0.5,
    signal                     VARCHAR(120),
    signal_expires_at          TIMESTAMPTZ,
    last_active_at             TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    mention_count              INTEGER NOT NULL DEFAULT 0,
    status                     VARCHAR(20) NOT NULL DEFAULT 'active',
    canonical_topic_id         VARCHAR(36) REFERENCES topics(id) ON DELETE SET NULL,
    dirty_since                TIMESTAMPTZ,
    last_consolidated_at       TIMESTAMPTZ,
    metadata                   JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_at                 TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at                 TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS ix_topics_user_parent
    ON topics (user_id, parent_id);
CREATE INDEX IF NOT EXISTS ix_topics_user_last_active
    ON topics (user_id, last_active_at DESC);
CREATE UNIQUE INDEX IF NOT EXISTS uq_topics_user_parent_normalized_label
    ON topics (user_id, COALESCE(parent_id, ''), normalized_label);

CREATE TABLE IF NOT EXISTS topic_aliases (
    id               VARCHAR(36) PRIMARY KEY,
    user_id          VARCHAR(255) NOT NULL REFERENCES users(email) ON DELETE CASCADE,
    topic_id         VARCHAR(36) NOT NULL REFERENCES topics(id) ON DELETE CASCADE,
    alias             VARCHAR(200) NOT NULL,
    normalized_alias  VARCHAR(200) NOT NULL,
    created_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (user_id, normalized_alias)
);
CREATE INDEX IF NOT EXISTS ix_topic_aliases_topic_id ON topic_aliases (topic_id);

ALTER TABLE conversations
    ADD COLUMN IF NOT EXISTS active_topic_id VARCHAR(36);

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = 'fk_conversations_active_topic_id'
    ) THEN
        ALTER TABLE conversations
            ADD CONSTRAINT fk_conversations_active_topic_id
            FOREIGN KEY (active_topic_id) REFERENCES topics(id) ON DELETE SET NULL;
    END IF;
END $$;
