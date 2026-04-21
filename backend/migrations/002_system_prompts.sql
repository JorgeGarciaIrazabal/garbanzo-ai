-- Per-conversation system prompt
ALTER TABLE conversations
    ADD COLUMN IF NOT EXISTS system_prompt TEXT;

-- Global default system prompt per user
ALTER TABLE users
    ADD COLUMN IF NOT EXISTS default_system_prompt TEXT;

-- Template library (personas + user-saved prompts)
CREATE TABLE IF NOT EXISTS system_prompt_templates (
    id VARCHAR(36) PRIMARY KEY,
    user_id VARCHAR(255) REFERENCES users(email) ON DELETE CASCADE,
    name VARCHAR(100) NOT NULL,
    description VARCHAR(500),
    content TEXT NOT NULL,
    is_builtin BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS ix_system_prompt_templates_user_id
    ON system_prompt_templates (user_id);
