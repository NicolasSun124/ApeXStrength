CREATE TABLE users (
    id UUID PRIMARY KEY,
    email VARCHAR(320) UNIQUE NOT NULL,
    password_hash TEXT NOT NULL,
    verification_code_hash VARCHAR(64),
    verification_code_expires_at TIMESTAMPTZ,
    email_verified BOOLEAN NOT NULL DEFAULT FALSE,
    name VARCHAR(120),
    session_token_hash VARCHAR(64) UNIQUE,
    sync_data JSONB,
    synced_at TIMESTAMPTZ,
    sync_revision BIGINT NOT NULL DEFAULT 0
);

CREATE TABLE sync_records (
    id UUID PRIMARY KEY,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    entity_type VARCHAR(40) NOT NULL,
    client_uuid VARCHAR(64) NOT NULL,
    data JSONB,
    revision BIGINT NOT NULL,
    deleted_at TIMESTAMPTZ,
    updated_at TIMESTAMPTZ NOT NULL,
    UNIQUE (user_id, entity_type, client_uuid)
);
CREATE INDEX ix_sync_records_user_id ON sync_records(user_id);
CREATE INDEX ix_sync_records_user_revision ON sync_records(user_id, revision);
