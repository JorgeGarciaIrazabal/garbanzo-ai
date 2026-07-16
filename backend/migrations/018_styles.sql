-- Saved "styles" (Idea 2: "Styles", subtask 2) — a named, reusable bundle of
-- model + thinking level + system prompt that a user can compose ad hoc per
-- conversation or save for reuse (e.g. "Deep Work", "Quick Answers"). This is
-- deliberately a standalone table rather than new columns on
-- system_prompt_templates: a style *references* a system prompt template (or
-- none), it doesn't replace the template library, and a template can be
-- reused by many styles (or none). Structurally this mirrors
-- scheduled_actions: a simple user-owned resource with its own id, FK to
-- users(email) ON DELETE CASCADE (styles are meaningless without their
-- owner), and created_at/updated_at.
--
-- thinking_level reuses the exact off/low/medium/high representation from
-- 017_conversation_thinking_level.sql (see that file for why a plain
-- VARCHAR rather than an ENUM/CHECK: the value set is validated at the API
-- boundary by the shared Pydantic ThinkingLevel literal, not by raw SQL).
--
-- system_prompt_template_id is nullable with ON DELETE SET NULL rather than
-- CASCADE: a style is a bundle of independently-useful settings (model,
-- thinking level, prompt), and deleting the *template* the user happened to
-- pick shouldn't destroy the *style* — that would silently discard the
-- model/thinking-level choices too, which the user never asked to lose.
-- Losing just the prompt reference (falling back to "no system prompt", same
-- as Conversation.system_prompt = NULL) is the smaller, more recoverable
-- surprise. This mirrors user_memories.source_conversation_id, which also
-- uses ON DELETE SET NULL for the same "don't cascade-destroy a record over
-- a dangling reference to something else" reasoning.
--
-- is_default marks the style used to seed brand-new conversations. Rather
-- than a CHECK constraint (Postgres can't express "at most one row per
-- user" that way) or an application-only check (races under concurrent
-- writes), uniqueness is enforced with a partial unique index over
-- (user_id) WHERE is_default — Postgres's standard idiom for "at most one
-- flagged row per group". The service layer still unsets any prior default
-- before setting a new one so callers never hit the constraint in normal
-- use; the index exists to make that invariant hold even under a race or a
-- future bug, not as the primary UX guard.
CREATE TABLE IF NOT EXISTS styles (
    id VARCHAR(36) PRIMARY KEY,
    user_id VARCHAR(255) NOT NULL REFERENCES users(email) ON DELETE CASCADE,
    name VARCHAR(100) NOT NULL,
    model_id VARCHAR(100) NOT NULL,
    thinking_level VARCHAR(10),
    system_prompt_template_id VARCHAR(36)
        REFERENCES system_prompt_templates(id) ON DELETE SET NULL,
    is_default BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS ix_styles_user_id ON styles (user_id);

CREATE UNIQUE INDEX IF NOT EXISTS ix_styles_one_default_per_user
    ON styles (user_id) WHERE is_default;
