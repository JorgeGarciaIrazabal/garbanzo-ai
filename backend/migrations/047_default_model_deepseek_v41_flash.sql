-- Switch the app's preconfigured model to deepseek-v4.1-flash:cloud.
--
-- Surfaces rewritten here:
--   * built-in styles — seeded once and never re-seeded, so an existing
--     deployment keeps their old model_id unless we rewrite the shared rows.
--     Only built-ins (is_builtin TRUE) move: styles a user saved themselves
--     keep whatever model they chose.
--   * users.default_model — the per-user default model for new chats.
--   * room_agents.model — agents created before the switch.
--   * scheduled_actions.model — per-action overrides; NULL keeps falling back
--     to settings.scheduled_action_model (now the new model).
--
-- Conversations keep their model: an in-flight thread's model is part of that
-- conversation's history and is not silently changed here. User-saved styles
-- likewise keep their chosen model.
UPDATE styles
SET model_id = 'deepseek-v4.1-flash:cloud'
WHERE is_builtin = TRUE;

UPDATE users
SET default_model = 'deepseek-v4.1-flash:cloud'
WHERE default_model IS NOT NULL;

UPDATE room_agents
SET model = 'deepseek-v4.1-flash:cloud'
WHERE model IS NOT NULL;

UPDATE scheduled_actions
SET model = 'deepseek-v4.1-flash:cloud'
WHERE model IS NOT NULL;

-- Register the new model in the admin visibility catalog so it is selectable
-- in production before the next admin model sync. Existing rows keep their
-- enabled/disabled choice.
INSERT INTO available_models (model_id, is_enabled, updated_at)
VALUES ('deepseek-v4.1-flash:cloud', TRUE, NOW())
ON CONFLICT (model_id) DO NOTHING;
