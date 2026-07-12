-- Adds enabled_tools column to room_agents.
-- null = all enabled MCP tools, [] = none, ['srv:tool'] = specific subset.
ALTER TABLE room_agents
    ADD COLUMN IF NOT EXISTS enabled_tools JSONB DEFAULT NULL;