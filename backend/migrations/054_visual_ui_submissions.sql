CREATE TABLE IF NOT EXISTS ui_submissions (
    id VARCHAR(80) PRIMARY KEY,
    message_id VARCHAR(36) NOT NULL REFERENCES messages(id) ON DELETE CASCADE,
    action_id VARCHAR(80) NOT NULL,
    status VARCHAR(16) NOT NULL DEFAULT 'pending',
    values JSONB NOT NULL,
    result JSONB,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (message_id, action_id)
);
CREATE INDEX IF NOT EXISTS ix_ui_submissions_message_id ON ui_submissions(message_id);
