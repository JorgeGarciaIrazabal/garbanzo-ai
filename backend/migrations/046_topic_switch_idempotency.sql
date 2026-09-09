-- Idempotent topic-switch results. The conversation row serializes competing
-- switches; this table lets a client safely replay a request after response loss.

CREATE TABLE IF NOT EXISTS topic_switch_operations (
    id                  VARCHAR(36) PRIMARY KEY,
    conversation_id     VARCHAR(36) NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
    user_id             VARCHAR(255) NOT NULL REFERENCES users(email) ON DELETE CASCADE,
    idempotency_key     VARCHAR(120) NOT NULL,
    request_fingerprint VARCHAR(64) NOT NULL,
    response_json       JSONB NOT NULL,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (conversation_id, idempotency_key)
);

CREATE INDEX IF NOT EXISTS ix_topic_switch_operations_user_id
    ON topic_switch_operations (user_id);
