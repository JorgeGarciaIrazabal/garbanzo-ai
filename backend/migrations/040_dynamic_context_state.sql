-- Durable ingestion queue/watermarks and the user-editable active context.

CREATE TABLE IF NOT EXISTS topic_ingestion_events (
    id               BIGSERIAL PRIMARY KEY,
    user_id          VARCHAR(255) NOT NULL REFERENCES users(email) ON DELETE CASCADE,
    conversation_id  VARCHAR(36) REFERENCES conversations(id) ON DELETE CASCADE,
    operation        VARCHAR(30) NOT NULL,
    source_type      VARCHAR(30) NOT NULL,
    source_id        VARCHAR(255) NOT NULL,
    source_version   VARCHAR(80) NOT NULL,
    payload          JSONB NOT NULL DEFAULT '{}'::jsonb,
    attempts         INTEGER NOT NULL DEFAULT 0,
    last_error       TEXT,
    processed_at     TIMESTAMPTZ,
    created_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (operation, source_type, source_id, source_version)
);
CREATE INDEX IF NOT EXISTS ix_topic_ingestion_events_user_id
    ON topic_ingestion_events (user_id, id);
CREATE INDEX IF NOT EXISTS ix_topic_ingestion_events_pending
    ON topic_ingestion_events (id) WHERE processed_at IS NULL;

CREATE TABLE IF NOT EXISTS topic_ingestion_state (
    user_id                    VARCHAR(255) PRIMARY KEY REFERENCES users(email) ON DELETE CASCADE,
    last_realtime_event_id     BIGINT NOT NULL DEFAULT 0,
    last_consolidated_event_id BIGINT NOT NULL DEFAULT 0,
    lease_owner                VARCHAR(120),
    lease_expires_at           TIMESTAMPTZ,
    consecutive_failures       INTEGER NOT NULL DEFAULT 0,
    last_error                 TEXT,
    retry_at                   TIMESTAMPTZ,
    updated_at                 TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS active_context_items (
    id                 VARCHAR(36) PRIMARY KEY,
    conversation_id    VARCHAR(36) NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
    source_type        VARCHAR(30) NOT NULL,
    source_id          VARCHAR(255) NOT NULL,
    source_meta        JSONB NOT NULL DEFAULT '{}'::jsonb,
    topic_id           VARCHAR(36) REFERENCES topics(id) ON DELETE CASCADE,
    state              VARCHAR(20) NOT NULL DEFAULT 'dynamic',
    reason             TEXT,
    relevance_score    DOUBLE PRECISION NOT NULL DEFAULT 0,
    token_count        INTEGER NOT NULL DEFAULT 0,
    last_selected_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    created_at         TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at         TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (conversation_id, source_type, source_id)
);
CREATE INDEX IF NOT EXISTS ix_active_context_items_conversation_state
    ON active_context_items (conversation_id, state);
