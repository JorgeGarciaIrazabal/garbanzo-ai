-- Owner bookmarks are separate from message metadata and topic context pins.
ALTER TABLE messages
    ADD COLUMN IF NOT EXISTS is_starred BOOLEAN NOT NULL DEFAULT FALSE;
