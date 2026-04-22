-- User-scheduled prompts that fire via APScheduler on a cron expression or
-- at a specific datetime. When triggered, the backend creates a new
-- conversation seeded with the prompt and streams an assistant response.

CREATE TABLE IF NOT EXISTS scheduled_actions (
    id VARCHAR(36) PRIMARY KEY,
    user_id VARCHAR(255) NOT NULL REFERENCES users(email) ON DELETE CASCADE,
    title VARCHAR(200),
    prompt TEXT NOT NULL,
    cron_expr VARCHAR(100),
    run_at TIMESTAMPTZ,
    model VARCHAR(100),
    system_prompt TEXT,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    next_run TIMESTAMPTZ,
    last_run_at TIMESTAMPTZ,
    last_run_status VARCHAR(32),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS ix_scheduled_actions_user_id ON scheduled_actions (user_id);
CREATE INDEX IF NOT EXISTS ix_scheduled_actions_active_next
    ON scheduled_actions (is_active, next_run);
