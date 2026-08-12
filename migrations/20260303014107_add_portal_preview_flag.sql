ALTER TABLE portal_tokens
  ADD COLUMN IF NOT EXISTS is_preview boolean NOT NULL DEFAULT false;

ALTER TABLE portal_sessions
  ADD COLUMN IF NOT EXISTS is_preview boolean NOT NULL DEFAULT false;
