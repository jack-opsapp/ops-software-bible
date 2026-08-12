
-- Rename table
ALTER TABLE gmail_connections RENAME TO email_connections;

-- Add new columns for multi-provider support
ALTER TABLE email_connections ADD COLUMN IF NOT EXISTS provider TEXT NOT NULL DEFAULT 'gmail';
ALTER TABLE email_connections ADD COLUMN IF NOT EXISTS webhook_subscription_id TEXT;
ALTER TABLE email_connections ADD COLUMN IF NOT EXISTS webhook_expires_at TIMESTAMPTZ;
ALTER TABLE email_connections ADD COLUMN IF NOT EXISTS ops_label_id TEXT;
ALTER TABLE email_connections ADD COLUMN IF NOT EXISTS ai_review_enabled BOOLEAN NOT NULL DEFAULT false;
ALTER TABLE email_connections ADD COLUMN IF NOT EXISTS ai_memory_enabled BOOLEAN NOT NULL DEFAULT false;
ALTER TABLE email_connections ADD COLUMN IF NOT EXISTS status TEXT NOT NULL DEFAULT 'active';

