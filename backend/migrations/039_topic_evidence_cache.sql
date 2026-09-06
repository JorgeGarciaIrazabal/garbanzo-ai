-- Evidence-linked topic state and immutable materialized context packs.

CREATE TABLE IF NOT EXISTS message_topics (
    message_id       VARCHAR(36) NOT NULL REFERENCES messages(id) ON DELETE CASCADE,
    topic_id         VARCHAR(36) NOT NULL REFERENCES topics(id) ON DELETE CASCADE,
    confidence       DOUBLE PRECISION NOT NULL DEFAULT 0.5,
    is_primary       BOOLEAN NOT NULL DEFAULT FALSE,
    segment_start    INTEGER NOT NULL DEFAULT 0,
    segment_end      INTEGER,
    source_authority VARCHAR(40) NOT NULL DEFAULT 'user_statement',
    created_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (message_id, topic_id)
);
CREATE INDEX IF NOT EXISTS ix_message_topics_topic_id ON message_topics (topic_id);

CREATE TABLE IF NOT EXISTS topic_assertions (
    id                    VARCHAR(36) PRIMARY KEY,
    topic_id              VARCHAR(36) NOT NULL REFERENCES topics(id) ON DELETE CASCADE,
    kind                  VARCHAR(30) NOT NULL,
    content               TEXT NOT NULL,
    normalized_key        VARCHAR(300) NOT NULL,
    embedding             vector(768),
    status                VARCHAR(20) NOT NULL DEFAULT 'uncertain',
    authority             VARCHAR(40) NOT NULL,
    confidence            DOUBLE PRECISION NOT NULL DEFAULT 0.5,
    valid_from            TIMESTAMPTZ,
    valid_until           TIMESTAMPTZ,
    superseded_by_id      VARCHAR(36) REFERENCES topic_assertions(id) ON DELETE SET NULL,
    first_seen_at         TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    last_confirmed_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    created_at            TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at            TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (topic_id, normalized_key)
);
CREATE INDEX IF NOT EXISTS ix_topic_assertions_topic_status
    ON topic_assertions (topic_id, status);

CREATE TABLE IF NOT EXISTS topic_assertion_evidence (
    assertion_id     VARCHAR(36) NOT NULL REFERENCES topic_assertions(id) ON DELETE CASCADE,
    message_id       VARCHAR(36) NOT NULL REFERENCES messages(id) ON DELETE CASCADE,
    segment_start    INTEGER NOT NULL DEFAULT 0,
    segment_end      INTEGER NOT NULL,
    relation         VARCHAR(20) NOT NULL DEFAULT 'supports',
    source_span_hash VARCHAR(64) NOT NULL,
    created_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (assertion_id, message_id, segment_start, segment_end)
);
CREATE INDEX IF NOT EXISTS ix_topic_assertion_evidence_message
    ON topic_assertion_evidence (message_id);

CREATE TABLE IF NOT EXISTS topic_exclusions (
    id                  VARCHAR(36) PRIMARY KEY,
    user_id             VARCHAR(255) NOT NULL REFERENCES users(email) ON DELETE CASCADE,
    topic_id            VARCHAR(36) REFERENCES topics(id) ON DELETE CASCADE,
    scope               VARCHAR(30) NOT NULL,
    target_id           VARCHAR(255),
    origin              VARCHAR(40) NOT NULL,
    reason              TEXT,
    source_message_id   VARCHAR(36) REFERENCES messages(id) ON DELETE SET NULL,
    concept_embedding   vector(768),
    is_privacy_deletion BOOLEAN NOT NULL DEFAULT FALSE,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    revoked_at          TIMESTAMPTZ
);
CREATE INDEX IF NOT EXISTS ix_topic_exclusions_user_active
    ON topic_exclusions (user_id, revoked_at);

CREATE TABLE IF NOT EXISTS topic_context_versions (
    id                     VARCHAR(36) PRIMARY KEY,
    topic_id               VARCHAR(36) NOT NULL REFERENCES topics(id) ON DELETE CASCADE,
    version                BIGINT NOT NULL,
    context_json           JSONB NOT NULL,
    short_summary          TEXT,
    source_event_watermark BIGINT NOT NULL DEFAULT 0,
    model_id               VARCHAR(150),
    model_revision         VARCHAR(150),
    provider               VARCHAR(80) NOT NULL,
    prompt_version         VARCHAR(80) NOT NULL,
    input_tokens           INTEGER NOT NULL DEFAULT 0,
    output_tokens          INTEGER NOT NULL DEFAULT 0,
    validation_status      VARCHAR(30) NOT NULL,
    created_at             TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (topic_id, version)
);
CREATE INDEX IF NOT EXISTS ix_topic_context_versions_topic_created
    ON topic_context_versions (topic_id, created_at DESC);

ALTER TABLE topics
    ADD COLUMN IF NOT EXISTS current_context_version_id VARCHAR(36);

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = 'fk_topics_current_context_version_id'
    ) THEN
        ALTER TABLE topics
            ADD CONSTRAINT fk_topics_current_context_version_id
            FOREIGN KEY (current_context_version_id)
            REFERENCES topic_context_versions(id) ON DELETE SET NULL;
    END IF;
END $$;
