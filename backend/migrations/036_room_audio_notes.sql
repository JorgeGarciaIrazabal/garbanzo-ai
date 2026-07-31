-- Raw playable audio for transcribed room messages.

CREATE TABLE IF NOT EXISTS room_audio_notes (
    id VARCHAR(36) PRIMARY KEY,
    message_id VARCHAR(36) NOT NULL UNIQUE
        REFERENCES room_messages(id) ON DELETE CASCADE,
    mime_type VARCHAR(100) NOT NULL,
    duration_seconds DOUBLE PRECISION NOT NULL,
    audio_data BYTEA NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS ix_room_audio_notes_message_id
    ON room_audio_notes(message_id);
