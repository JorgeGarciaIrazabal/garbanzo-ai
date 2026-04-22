-- Multi-Person & Multi-Agent Chat Rooms.
-- Creates the four room tables: rooms, room_members, room_agents, room_messages.
-- All idempotent so repeated runs are safe.

CREATE TABLE IF NOT EXISTS rooms (
    id VARCHAR(36) PRIMARY KEY,
    name VARCHAR(200) NOT NULL,
    description TEXT,
    owner_id VARCHAR(255) NOT NULL REFERENCES users(email) ON UPDATE CASCADE ON DELETE CASCADE,
    is_public BOOLEAN NOT NULL DEFAULT FALSE,
    is_deleted BOOLEAN NOT NULL DEFAULT FALSE,
    max_agent_turn_depth INTEGER NOT NULL DEFAULT 3,
    mode VARCHAR(20) NOT NULL DEFAULT 'chat',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS ix_rooms_owner_id ON rooms(owner_id);
CREATE INDEX IF NOT EXISTS ix_rooms_is_public ON rooms(is_public);

CREATE TABLE IF NOT EXISTS room_members (
    room_id VARCHAR(36) NOT NULL REFERENCES rooms(id) ON DELETE CASCADE,
    user_id VARCHAR(255) NOT NULL REFERENCES users(email) ON UPDATE CASCADE ON DELETE CASCADE,
    role VARCHAR(20) NOT NULL DEFAULT 'member',
    joined_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (room_id, user_id)
);

CREATE INDEX IF NOT EXISTS ix_room_members_user_id ON room_members(user_id);

CREATE TABLE IF NOT EXISTS room_agents (
    id VARCHAR(36) PRIMARY KEY,
    room_id VARCHAR(36) NOT NULL REFERENCES rooms(id) ON DELETE CASCADE,
    name VARCHAR(100) NOT NULL,
    avatar VARCHAR(20),
    provider VARCHAR(50) NOT NULL DEFAULT 'ollama',
    model VARCHAR(100) NOT NULL,
    system_prompt TEXT,
    response_mode VARCHAR(20) NOT NULL DEFAULT 'mention',
    turn_order INTEGER NOT NULL DEFAULT 0,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    is_moderator BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS ix_room_agents_room_id ON room_agents(room_id);
CREATE UNIQUE INDEX IF NOT EXISTS uq_room_agent_name ON room_agents(room_id, name);

CREATE TABLE IF NOT EXISTS room_messages (
    id VARCHAR(36) PRIMARY KEY,
    room_id VARCHAR(36) NOT NULL REFERENCES rooms(id) ON DELETE CASCADE,
    role VARCHAR(20) NOT NULL,
    sender_user_id VARCHAR(255) REFERENCES users(email) ON UPDATE CASCADE ON DELETE SET NULL,
    sender_agent_id VARCHAR(36) REFERENCES room_agents(id) ON DELETE SET NULL,
    content TEXT NOT NULL,
    meta JSONB,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS ix_room_messages_room_created
    ON room_messages(room_id, created_at);
