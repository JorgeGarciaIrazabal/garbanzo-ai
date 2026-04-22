-- Knowledge Base / RAG support.
-- Creates the pgvector extension plus the document + chunk tables, and
-- adds the per-conversation use_knowledge_base toggle.

CREATE EXTENSION IF NOT EXISTS vector;

CREATE TABLE IF NOT EXISTS knowledge_documents (
    id VARCHAR(36) PRIMARY KEY,
    user_id VARCHAR(255) NOT NULL REFERENCES users(email) ON UPDATE CASCADE ON DELETE CASCADE,
    filename VARCHAR(500) NOT NULL,
    mime_type VARCHAR(200) NOT NULL DEFAULT '',
    file_size INTEGER NOT NULL DEFAULT 0,
    status VARCHAR(20) NOT NULL DEFAULT 'pending',
    chunk_count INTEGER NOT NULL DEFAULT 0,
    error_message TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS ix_knowledge_documents_user_id
    ON knowledge_documents (user_id);

CREATE TABLE IF NOT EXISTS knowledge_chunks (
    id VARCHAR(36) PRIMARY KEY,
    document_id VARCHAR(36) NOT NULL REFERENCES knowledge_documents(id) ON DELETE CASCADE,
    user_id VARCHAR(255) NOT NULL REFERENCES users(email) ON UPDATE CASCADE ON DELETE CASCADE,
    chunk_index INTEGER NOT NULL DEFAULT 0,
    content TEXT NOT NULL,
    embedding vector(768),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS ix_knowledge_chunks_document_id
    ON knowledge_chunks (document_id);
CREATE INDEX IF NOT EXISTS ix_knowledge_chunks_user_id
    ON knowledge_chunks (user_id);

-- IVF flat index on embedding for fast cosine-similarity search.
-- Lists = 100 is a reasonable default for up to ~1M vectors.
CREATE INDEX IF NOT EXISTS ix_knowledge_chunks_embedding_cosine
    ON knowledge_chunks USING ivfflat (embedding vector_cosine_ops)
    WITH (lists = 100);

ALTER TABLE conversations
    ADD COLUMN IF NOT EXISTS use_knowledge_base BOOLEAN NOT NULL DEFAULT TRUE;
