ALTER TABLE users ADD COLUMN IF NOT EXISTS password_reset_code_hash VARCHAR(64);
ALTER TABLE users ADD COLUMN IF NOT EXISTS password_reset_code_expires_at TIMESTAMPTZ;
