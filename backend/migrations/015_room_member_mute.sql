-- Adds muted_until to room_members for per-member notification muting
-- (Idea 7: room notification muting). NULL = not muted. "Mute forever" is
-- represented with a far-future sentinel timestamp rather than a separate
-- boolean column, so all call sites need only compare muted_until to now().
ALTER TABLE room_members
    ADD COLUMN IF NOT EXISTS muted_until TIMESTAMPTZ DEFAULT NULL;
