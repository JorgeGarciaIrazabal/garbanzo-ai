-- User.default_style_id has been authoritative since migration 035.
-- Do not backfill from legacy flags: they can be stale even when the user
-- deliberately cleared their default pointer. Preserve existing pointers,
-- including NULL and shared built-in selections, exactly as they are.
DROP INDEX IF EXISTS ix_styles_one_default_per_user;
ALTER TABLE styles DROP COLUMN IF EXISTS is_default;
