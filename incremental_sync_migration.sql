ALTER TABLE users
    ADD COLUMN IF NOT EXISTS sync_revision BIGINT NOT NULL DEFAULT 0;

CREATE TABLE IF NOT EXISTS sync_records (
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

CREATE INDEX IF NOT EXISTS ix_sync_records_user_id ON sync_records(user_id);
CREATE INDEX IF NOT EXISTS ix_sync_records_user_revision ON sync_records(user_id, revision);
