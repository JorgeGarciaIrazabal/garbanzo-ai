-- Dynamic context (IDEAS.md idea 3): the client reports its IANA timezone and
-- locale at login so every chat turn can carry the user's local time in the
-- system prompt. Persisted on the user (not per-request) so server-initiated
-- turns — room agents, scheduled actions — know the timezone too.
--
-- Plain VARCHARs, validated at the API boundary: IANA zone names are an
-- evolving external registry (zoneinfo on the server is the authority), so a
-- CHECK constraint would just go stale. Longest current zone name is 32 chars
-- ("America/Argentina/ComodRivadavia"); 64 leaves headroom. NULL means the
-- client never reported one, and the context block simply omits local time.
ALTER TABLE users ADD COLUMN IF NOT EXISTS timezone VARCHAR(64) DEFAULT NULL;
ALTER TABLE users ADD COLUMN IF NOT EXISTS locale VARCHAR(32) DEFAULT NULL;
