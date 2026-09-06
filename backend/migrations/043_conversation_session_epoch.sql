-- Non-destructive topic switching: session_epoch on conversations and messages.
-- Switching topics in the primary chat increments session_epoch, isolating the active
-- message view while preserving all historical messages, message_topics, and topic_assertion_evidence.

ALTER TABLE conversations
    ADD COLUMN IF NOT EXISTS session_epoch INTEGER NOT NULL DEFAULT 0;

ALTER TABLE messages
    ADD COLUMN IF NOT EXISTS session_epoch INTEGER NOT NULL DEFAULT 0;

CREATE INDEX IF NOT EXISTS ix_messages_conversation_epoch_seq
    ON messages (conversation_id, session_epoch, seq);
