-- Refresh every DeepSeek-backed style, including user-saved presets, as
-- explicitly requested. Only model selections change; IDs, default pointers,
-- instructions, thinking levels and existing conversations are preserved.
-- Match the DeepSeek model family, leaving namespaced/custom model IDs alone.
UPDATE styles
SET model_id = 'deepseek-v4.1-flash:1017-cloud'
WHERE (model_id LIKE 'deepseek-%' OR model_id LIKE 'deepseek:%')
  AND model_id <> 'deepseek-v4.1-flash:1017-cloud';

-- A pending share must not reintroduce an outdated selection on acceptance.
UPDATE shared_items
SET payload = jsonb_set(payload, '{model_id}', '"deepseek-v4.1-flash:1017-cloud"'::jsonb)
WHERE kind = 'style'
  AND (payload->>'model_id' LIKE 'deepseek-%' OR payload->>'model_id' LIKE 'deepseek:%')
  AND payload->>'model_id' <> 'deepseek-v4.1-flash:1017-cloud';

-- Startup seeds the localized Mistral writing styles after prompt templates.
-- Register both models without overriding existing admin visibility choices.
INSERT INTO available_models (model_id, is_enabled, updated_at)
VALUES ('deepseek-v4.1-flash:1017-cloud', TRUE, NOW()),
       ('mistral-large-4:cloud', TRUE, NOW())
ON CONFLICT (model_id) DO NOTHING;
