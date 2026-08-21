CREATE TABLE IF NOT EXISTS auth_sessions (
    id UUID PRIMARY KEY,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    token_hash VARCHAR(64) UNIQUE NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS ix_auth_sessions_user_id ON auth_sessions(user_id);

-- Existing tokens remain valid through the legacy users.session_token_hash
-- column. New logins are stored here so devices no longer replace one another.
