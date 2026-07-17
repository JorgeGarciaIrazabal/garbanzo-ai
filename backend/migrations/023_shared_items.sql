-- Idea 9: share styles / prompt templates with friends (copy-on-accept).
-- The payload is a snapshot taken at share time, so later edits by the
-- sender never leak through ("no live sync"); accept/decline delete the row.

CREATE TABLE IF NOT EXISTS shared_items (
    id VARCHAR(36) PRIMARY KEY,
    sender_email VARCHAR(255) NOT NULL REFERENCES users(email) ON DELETE CASCADE,
    recipient_email VARCHAR(255) NOT NULL REFERENCES users(email) ON DELETE CASCADE,
    kind VARCHAR(10) NOT NULL,
    payload JSONB NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS ix_shared_items_recipient_email
    ON shared_items (recipient_email);
