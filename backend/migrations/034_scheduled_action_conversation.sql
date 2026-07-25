-- Scheduled actions: optional FK to the conversation recurring runs post
-- into (user-report 89b954f7). Populated on the first run; reused
-- thereafter so the action's history accumulates in one chat instead of
-- spawning a new conversation each fire. NULL for one-off (run_at) actions.

ALTER TABLE scheduled_actions
  ADD COLUMN IF NOT EXISTS conversation_id VARCHAR(36)
  REFERENCES conversations(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS ix_scheduled_actions_conversation_id
  ON scheduled_actions (conversation_id);