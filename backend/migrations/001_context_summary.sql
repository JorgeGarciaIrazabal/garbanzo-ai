-- Add context summarization columns to conversations
ALTER TABLE conversations
    ADD COLUMN IF NOT EXISTS context_summary TEXT,
    ADD COLUMN IF NOT EXISTS context_summary_until_id VARCHAR(36);
