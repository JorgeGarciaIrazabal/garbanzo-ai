-- Available models table — admin-controlled model visibility.
CREATE TABLE IF NOT EXISTS available_models (
    model_id   VARCHAR(100) PRIMARY KEY,
    is_enabled BOOLEAN NOT NULL DEFAULT TRUE,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);