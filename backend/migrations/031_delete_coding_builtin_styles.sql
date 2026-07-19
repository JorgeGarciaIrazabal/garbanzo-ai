-- Drop the "Coding" (en) and "Programación" (es) built-in styles. They were
-- removed from BUILTIN_STYLES in style_service.py; this prunes the rows the
-- seeder created so they don't linger in the picker as dead entries. Idempotent
-- (re-running on a fresh DB matches no rows) and scoped to built-ins only
-- (is_builtin = TRUE AND user_id IS NULL), so a user-saved style named "Coding"
-- is never touched.
DELETE FROM styles
WHERE is_builtin = TRUE
  AND user_id IS NULL
  AND name IN ('Coding', 'Programación');