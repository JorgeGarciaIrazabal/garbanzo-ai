-- Friendships (Idea 5: "Friends") — a lightweight social graph so rooms and
-- future sharing features stop requiring raw email entry.
--
-- One row per relationship, directional at request time: requester sent the
-- request, addressee received it. status transitions:
--   pending  → accepted   (addressee accepts)
--   pending  → (row deleted) on decline — deleting rather than a 'declined'
--              status lets either side try again later; a permanent tombstone
--              would make one mistaken decline unrecoverable.
--   any      → blocked    (either side blocks; row kept so the block is
--              durable and enforced — the privacy-guard subtask reads it).
-- Removing an accepted friend also deletes the row.
--
-- Plain VARCHAR status validated at the API boundary (same reasoning as
-- thinking_level in 017). FKs cascade on user deletion (a relationship is
-- meaningless without both people) and follow email renames via the users
-- table's ON UPDATE CASCADE pattern used across the schema.
--
-- The unique index on (requester_email, addressee_email) prevents duplicate
-- requests in the same direction; the service layer additionally detects the
-- reverse-direction row (B already asked A) and accepts it instead of
-- creating a mirror row, so a pair has at most one row in practice.
CREATE TABLE IF NOT EXISTS friendships (
    id VARCHAR(36) PRIMARY KEY,
    requester_email VARCHAR(255) NOT NULL REFERENCES users(email) ON DELETE CASCADE ON UPDATE CASCADE,
    addressee_email VARCHAR(255) NOT NULL REFERENCES users(email) ON DELETE CASCADE ON UPDATE CASCADE,
    status VARCHAR(10) NOT NULL DEFAULT 'pending',
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS ix_friendships_pair
    ON friendships (requester_email, addressee_email);
CREATE INDEX IF NOT EXISTS ix_friendships_addressee
    ON friendships (addressee_email);
