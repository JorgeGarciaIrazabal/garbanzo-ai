-- Distinguish global (admin) MCP servers from personal (user-owned) ones.
--
-- owner_email NULL  → global server: admin-managed, its tools are available to
--                     every user and to multi-user rooms.
-- owner_email set   → personal server: only that user sees/uses its tools.
--                     Removed automatically when the owning user is deleted.
--
-- Existing rows keep owner_email = NULL, so all currently-registered servers
-- remain global (no behaviour change on upgrade).
ALTER TABLE mcp_servers
    ADD COLUMN IF NOT EXISTS owner_email VARCHAR(255)
    REFERENCES users(email) ON DELETE CASCADE;

CREATE INDEX IF NOT EXISTS ix_mcp_servers_owner_email
    ON mcp_servers (owner_email);
