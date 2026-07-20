-- Delegated opencode workflow runs (idea 18). A run works on a server-side
-- snapshot of the folder the desktop client uploaded, so it survives the
-- client disconnecting; the resulting diff is sent back for local apply.

CREATE TABLE IF NOT EXISTS workflow_runs (
    id VARCHAR(36) PRIMARY KEY,
    user_id VARCHAR(255) NOT NULL REFERENCES users(email) ON DELETE CASCADE,
    conversation_id VARCHAR(36) REFERENCES conversations(id) ON DELETE CASCADE,
    room_id VARCHAR(36),
    tool_call_id VARCHAR(64),
    status VARCHAR(16) NOT NULL DEFAULT 'draft',
    instruction TEXT NOT NULL,
    scope JSONB,
    workdir TEXT,
    opencode_session_id VARCHAR(64),
    summary TEXT,
    error TEXT,
    progress JSONB,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    completed_at TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS ix_workflow_runs_user_id ON workflow_runs (user_id);
CREATE INDEX IF NOT EXISTS ix_workflow_runs_conversation_id ON workflow_runs (conversation_id);
CREATE INDEX IF NOT EXISTS ix_workflow_runs_room_id ON workflow_runs (room_id);
CREATE INDEX IF NOT EXISTS ix_workflow_runs_tool_call_id ON workflow_runs (tool_call_id);
CREATE INDEX IF NOT EXISTS ix_workflow_runs_status ON workflow_runs (status);
