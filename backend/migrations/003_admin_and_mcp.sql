-- Admin flags on users
ALTER TABLE users
    ADD COLUMN IF NOT EXISTS is_admin BOOLEAN NOT NULL DEFAULT FALSE;

ALTER TABLE users
    ADD COLUMN IF NOT EXISTS is_disabled BOOLEAN NOT NULL DEFAULT FALSE;

-- Per-conversation MCP tool selection. NULL means "all enabled tools".
ALTER TABLE conversations
    ADD COLUMN IF NOT EXISTS enabled_tools JSONB;

-- MCP servers registry
CREATE TABLE IF NOT EXISTS mcp_servers (
    id VARCHAR(36) PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    description TEXT,
    url TEXT,
    transport VARCHAR(20) NOT NULL,
    command TEXT,
    args JSONB,
    env JSONB,
    auth_header TEXT,
    enabled BOOLEAN NOT NULL DEFAULT TRUE,
    created_by VARCHAR(255) REFERENCES users(email) ON DELETE SET NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS ix_mcp_servers_enabled ON mcp_servers (enabled);
