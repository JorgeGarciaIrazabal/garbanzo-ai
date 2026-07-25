-- Users: per-user default style pointer (user-report f1af13d5).
--
-- Lets a user set any style — including a shared built-in like "Truth
-- Seeker" — as their default for new conversations, by storing a
-- reference on the user row instead of mutating the shared built-in's
-- is_default flag (which would affect every user).
--
-- ON DELETE SET NULL: deleting the style clears the pointer rather than
-- cascading to the user. The partial unique index
-- ix_styles_one_default_per_user on Style.is_default becomes vestigial
-- (the per-user pointer enforces uniqueness on its own) but is left in
-- place so older code paths that still toggle Style.is_default stay
-- consistent.

ALTER TABLE users
  ADD COLUMN IF NOT EXISTS default_style_id VARCHAR(36)
  REFERENCES styles(id) ON DELETE SET NULL;