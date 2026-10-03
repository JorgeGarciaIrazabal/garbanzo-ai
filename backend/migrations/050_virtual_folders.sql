CREATE TABLE IF NOT EXISTS virtual_folders (
    id VARCHAR(36) PRIMARY KEY,
    user_id VARCHAR(255) NOT NULL REFERENCES users(email) ON DELETE CASCADE,
    name VARCHAR(200) NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS ix_virtual_folders_user_id ON virtual_folders(user_id);

CREATE TABLE IF NOT EXISTS virtual_files (
    id VARCHAR(36) PRIMARY KEY,
    folder_id VARCHAR(36) NOT NULL REFERENCES virtual_folders(id) ON DELETE CASCADE,
    path VARCHAR(1024) NOT NULL,
    media_type VARCHAR(255) NOT NULL,
    size_bytes INTEGER NOT NULL,
    sha256 VARCHAR(64) NOT NULL,
    revision INTEGER NOT NULL DEFAULT 1,
    data BYTEA NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (folder_id, path)
);
CREATE INDEX IF NOT EXISTS ix_virtual_files_folder_id ON virtual_files(folder_id);

CREATE TABLE IF NOT EXISTS conversation_folders (
    conversation_id VARCHAR(36) NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
    folder_id VARCHAR(36) NOT NULL REFERENCES virtual_folders(id) ON DELETE CASCADE,
    PRIMARY KEY (conversation_id, folder_id)
);
CREATE INDEX IF NOT EXISTS ix_conversation_folders_folder_id ON conversation_folders(folder_id);
