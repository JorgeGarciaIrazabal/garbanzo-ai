-- Conversation UX: pinned conversations.
ALTER TABLE conversations
    ADD COLUMN IF NOT EXISTS is_pinned BOOLEAN NOT NULL DEFAULT FALSE;

CREATE INDEX IF NOT EXISTS ix_conversations_is_pinned ON conversations (is_pinned);
