ALTER TABLE workflow_runs ADD COLUMN IF NOT EXISTS session_epoch INTEGER;
ALTER TABLE workflow_runs ADD COLUMN IF NOT EXISTS artifacts_status VARCHAR(16) NOT NULL DEFAULT 'unavailable';
ALTER TABLE workflow_runs ADD COLUMN IF NOT EXISTS artifacts_error TEXT;

CREATE TABLE IF NOT EXISTS workflow_artifacts (
    id VARCHAR(36) PRIMARY KEY,
    run_id VARCHAR(36) NOT NULL REFERENCES workflow_runs(id) ON DELETE CASCADE,
    path VARCHAR(1024) NOT NULL,
    media_type VARCHAR(255) NOT NULL,
    size_bytes INTEGER NOT NULL,
    sha256 VARCHAR(64) NOT NULL,
    data BYTEA NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (run_id, path)
);
CREATE INDEX IF NOT EXISTS ix_workflow_artifacts_run_id ON workflow_artifacts(run_id);
