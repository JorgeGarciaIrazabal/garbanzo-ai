-- Replay existing conversation history through the durable topic pipeline.
-- The operation is intentionally distinct from live `create` events so an
-- installation that received some realtime topic events before this migration
-- can repair weak early labels and memberships exactly once.

INSERT INTO topic_ingestion_events (
    user_id,
    conversation_id,
    operation,
    source_type,
    source_id,
    source_version,
    payload,
    attempts,
    created_at
)
SELECT
    c.user_id,
    c.id,
    'backfill',
    'message',
    m.id,
    'history-backfill-v1',
    jsonb_build_object('role', m.role, 'historical_backfill', TRUE),
    0,
    COALESCE(m.created_at, NOW())
FROM messages AS m
JOIN conversations AS c ON c.id = m.conversation_id
WHERE c.is_deleted = FALSE
ORDER BY c.user_id, c.id, m.seq
ON CONFLICT (operation, source_type, source_id, source_version) DO NOTHING;

INSERT INTO topic_ingestion_state (
    user_id,
    last_realtime_event_id,
    last_consolidated_event_id,
    consecutive_failures,
    updated_at
)
SELECT DISTINCT c.user_id, 0, 0, 0, NOW()
FROM conversations AS c
WHERE c.is_deleted = FALSE
ON CONFLICT (user_id) DO NOTHING;
