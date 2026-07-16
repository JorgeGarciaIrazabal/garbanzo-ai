-- Adds thinking_level to conversations so users can control how hard the
-- model reasons, per conversation (Idea 2: "Styles"). NULL preserves today's
-- implicit behavior: ollama_provider auto-enables thinking whenever the
-- model advertises the "thinking" capability (think=True). An explicit value
-- overrides that default — "off" force-disables thinking even for a capable
-- model, while "low" / "medium" / "high" pass straight through as Ollama's
-- reasoning-effort level (the installed ollama-py SDK types `think` as
-- `bool | Literal["low", "medium", "high"]` — see ollama/_types.py — so no
-- new provider API is being invented here).
--
-- A plain nullable VARCHAR rather than a Postgres ENUM type or a CHECK
-- constraint: the four-value set is validated at the API boundary by the
-- Pydantic schema (Literal["off","low","medium","high"]), no raw SQL writes
-- this column directly, and a VARCHAR is one less migration to alter later
-- if the value set grows. Mirrors the reasoning in 016_conversation_mute.sql
-- for keeping simple per-conversation settings as plain columns.
ALTER TABLE conversations
    ADD COLUMN IF NOT EXISTS thinking_level VARCHAR(10) DEFAULT NULL;
