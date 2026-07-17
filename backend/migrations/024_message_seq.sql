-- B-03: stable per-row ordering for message pagination.
-- created_at alone ties within a single DB transaction (Postgres now() is
-- transaction-start time, and one agent turn persists assistant/tool_call/
-- tool_result rows before committing), so it can't be used as a pagination
-- cursor without risking skipped/duplicated/misordered rows. `seq` is
-- assigned by the app at insert time (a monotonically increasing value),
-- giving a reliable ordering/cursor key independent of timestamp precision.

ALTER TABLE messages ADD COLUMN IF NOT EXISTS seq BIGINT;

-- One-time backfill for rows that predate this column — best-effort order
-- for historical ties (created_at, id); new rows always get a real
-- insertion-order value from the app, so this only ever runs once.
UPDATE messages SET seq = sub.rn
FROM (
    SELECT id, row_number() OVER (ORDER BY created_at, id) AS rn
    FROM messages
    WHERE seq IS NULL
) AS sub
WHERE messages.id = sub.id AND messages.seq IS NULL;

CREATE INDEX IF NOT EXISTS idx_messages_conversation_seq ON messages (conversation_id, seq);
