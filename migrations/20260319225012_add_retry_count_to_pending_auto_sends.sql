
-- Add retry_count to pending_auto_sends for max retry enforcement
ALTER TABLE pending_auto_sends
  ADD COLUMN IF NOT EXISTS retry_count INT NOT NULL DEFAULT 0;

