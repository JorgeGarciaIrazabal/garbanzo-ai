-- Upgrade persisted LLM selections to their current equivalents. Model IDs
-- are denormalized across user preferences, conversations, saved/built-in
-- styles, room agents, scheduled actions, and the admin visibility catalog;
-- every configuration surface must move together or old conversations and
-- presets keep selecting retired models after deploy.
--
-- This is deliberately an explicit allowlist. A prefix rewrite would mutate
-- private/custom Ollama tags that happen to share a vendor-family prefix.
CREATE TEMP TABLE model_replacements (
    old_id VARCHAR(100) PRIMARY KEY,
    new_id VARCHAR(100) NOT NULL
) ON COMMIT DROP;

INSERT INTO model_replacements (old_id, new_id) VALUES
    ('minimax-m3:cloud', 'glm-5.3-flash:cloud'),
    ('glm-5.2:cloud', 'glm-5.3:cloud'),
    ('kimi-k2.7-code:cloud', 'glm-5.3:cloud'),
    ('deepseek-v4-flash:0731-cloud', 'deepseek-v4-flash:cloud'),
    ('deepseek-v4-pro:0813-cloud', 'deepseek-v4-pro:cloud'),
    ('qwen3.6', 'qwen3.8:27b'),
    ('qwen3.6:latest', 'qwen3.8:27b'),
    ('qwen3.6:35b', 'qwen3.8:27b'),
    ('qwen3.6:35b-a3b', 'qwen3.8:27b'),
    ('qwen3.6:27b', 'qwen3.8:27b'),
    ('qwen3.6:27b-mlx', 'qwen3.8:27b-mlx'),
    ('qwen3.6:27b-mlx-bf16', 'qwen3.8:27b-mlx-bf16'),
    ('qwen3.6:27b-mtp-q4_K_M', 'qwen3.8:27b-mtp-q4_K_M'),
    ('qwen3.6:27b-mtp-q8_0', 'qwen3.8:27b-mtp-q8_0'),
    ('qwen3.6:27b-mtp-bf16', 'qwen3.8:27b-mtp-bf16'),
    ('qwen3.6:27b-mxfp8', 'qwen3.8:27b-mxfp8'),
    ('qwen3.6:27b-nvfp4', 'qwen3.8:27b-nvfp4'),
    ('qwen3.6:27b-q4_K_M', 'qwen3.8:27b-q4_K_M'),
    ('qwen3.6:27b-q8_0', 'qwen3.8:27b-q8_0'),
    ('qwen3.6:27b-bf16', 'qwen3.8:27b-bf16');

UPDATE users AS target
SET default_model = replacements.new_id
FROM model_replacements AS replacements
WHERE target.default_model = replacements.old_id;

UPDATE conversations AS target
SET model = replacements.new_id
FROM model_replacements AS replacements
WHERE target.model = replacements.old_id;

UPDATE styles AS target
SET model_id = replacements.new_id
FROM model_replacements AS replacements
WHERE target.model_id = replacements.old_id;

UPDATE room_agents AS target
SET model = replacements.new_id
FROM model_replacements AS replacements
WHERE target.model = replacements.old_id;

UPDATE scheduled_actions AS target
SET model = replacements.new_id
FROM model_replacements AS replacements
WHERE target.model = replacements.old_id;

-- Pending style shares are copy-on-accept JSON snapshots. Upgrade their
-- embedded model too, otherwise accepting an older invitation recreates a
-- retired selection after the relational rows have been migrated.
UPDATE shared_items AS target
SET payload = jsonb_set(target.payload, '{model_id}', to_jsonb(replacements.new_id), false)
FROM model_replacements AS replacements
WHERE target.kind = 'style'
  AND target.payload ->> 'model_id' = replacements.old_id;

-- Preserve admin visibility choices while changing the primary key. If both
-- old and new rows exist, disabled wins so an upgrade never re-enables a model
-- the administrator meant to hide.
INSERT INTO available_models (model_id, is_enabled, updated_at)
SELECT replacements.new_id, BOOL_AND(models.is_enabled), NOW()
FROM available_models AS models
JOIN model_replacements AS replacements ON replacements.old_id = models.model_id
GROUP BY replacements.new_id
ON CONFLICT (model_id) DO UPDATE
SET is_enabled = available_models.is_enabled AND EXCLUDED.is_enabled,
    updated_at = NOW();

DELETE FROM available_models AS target
USING model_replacements AS replacements
WHERE target.model_id = replacements.old_id;
