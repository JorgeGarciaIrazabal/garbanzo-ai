-- Built-in styles: predefined "Concise", "Truth Seeker", etc. bundles of
-- model + thinking level + system prompt template that ship with the app and
-- appear as one-tap cards in the style picker alongside the user's saved
-- styles. Built-ins are shared across all users (user_id NULL) and read-only
-- (StyleService.update/delete refuse them; the API returns 403).
--
-- Mirrors the SystemPromptTemplate built-in design: ``is_builtin`` marks the
-- shared rows, ``user_id`` is NULL for built-ins (the styles table already
-- allows NULL via users(email) ON DELETE CASCADE — NULL never matches a user),
-- and ``locale`` lets the picker surface them in the user's language without
-- mixing languages in the same view. Existing user styles get
-- is_builtin=FALSE, locale=NULL (language-neutral, same as user-saved prompt
-- templates), and description=NULL (no description has existed so far).
--
-- The partial unique index ix_styles_one_default_per_user (from 018_styles)
-- keys on user_id. NULL user_id rows never collide with a real user's
-- default, and built-ins are never marked is_default anyway, so the existing
-- index needs no change.
ALTER TABLE styles
    ADD COLUMN IF NOT EXISTS is_builtin BOOLEAN NOT NULL DEFAULT FALSE,
    ADD COLUMN IF NOT EXISTS locale VARCHAR(5) DEFAULT NULL,
    ADD COLUMN IF NOT EXISTS description VARCHAR(500) DEFAULT NULL;

ALTER TABLE styles
    ALTER COLUMN user_id DROP NOT NULL;

-- Existing rows are user-owned; keep them that way. locale/description
-- stay NULL for them (NULL acts as a wildcard in any locale query, matching
-- the system_prompt_templates convention).