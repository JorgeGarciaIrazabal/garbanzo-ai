-- Adds muted_until to conversations for conversation-level notification muting
-- (Idea 8: conversation mute). Mirrors 015_room_member_mute.sql: NULL = not
-- muted, "mute forever" is a far-future sentinel timestamp rather than a
-- separate boolean column, so all call sites need only compare muted_until
-- to now(). A conversation has exactly one owner, so this lives directly on
-- conversations instead of a per-member join table like room_members.
ALTER TABLE conversations
    ADD COLUMN IF NOT EXISTS muted_until TIMESTAMPTZ DEFAULT NULL;
