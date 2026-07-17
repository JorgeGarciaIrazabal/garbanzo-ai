-- B-03 follow-up: 024 added and backfilled messages.seq but left the column
-- nullable, while the ORM declares it NOT NULL. The gap matters because
-- pagination orders by seq DESC and Postgres sorts NULLs first in DESC — a
-- stray NULL row would masquerade as the conversation's newest message.
-- Enforce at the schema level so bad rows fail loudly at insert instead.

-- Safety backfill (idempotent, same ordering as 024) in case any NULL rows
-- slipped in between the two migrations; SET NOT NULL fails otherwise.
UPDATE messages SET seq = sub.rn
FROM (
    SELECT id, row_number() OVER (ORDER BY created_at, id) AS rn
    FROM messages
    WHERE seq IS NULL
) AS sub
WHERE messages.id = sub.id AND messages.seq IS NULL;

ALTER TABLE messages ALTER COLUMN seq SET NOT NULL;
