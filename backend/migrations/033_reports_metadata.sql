-- Structured diagnostics for automatically filed error reports (idea 22).
-- Existing manual reports remain valid with every new field NULL.

ALTER TABLE reports ADD COLUMN IF NOT EXISTS metadata JSONB;
ALTER TABLE reports ADD COLUMN IF NOT EXISTS conversation_id VARCHAR(36);
ALTER TABLE reports ADD COLUMN IF NOT EXISTS severity VARCHAR(16);
ALTER TABLE reports ADD COLUMN IF NOT EXISTS source VARCHAR(16);

CREATE INDEX IF NOT EXISTS ix_reports_conversation_id ON reports (conversation_id);
