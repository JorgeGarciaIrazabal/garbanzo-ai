-- Adds thinking_level to room_agents so each agent's reasoning depth can be
-- configured like a conversation's (see 017_conversation_thinking_level.sql
-- for the semantics and for why this is a plain nullable VARCHAR rather than
-- an ENUM/CHECK: the four-value set is validated by the Pydantic schema).
-- NULL keeps the provider default (auto-enable thinking for capable models).
ALTER TABLE room_agents
    ADD COLUMN IF NOT EXISTS thinking_level VARCHAR(10) DEFAULT NULL;
