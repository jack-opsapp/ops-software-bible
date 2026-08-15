-- Add completed_at column to projects table
-- Tracks when a project was marked as completed, used for "X days since completion"
-- in the iOS Close Out Review feature and equivalent web review screens.
ALTER TABLE projects ADD COLUMN IF NOT EXISTS completed_at timestamp with time zone;

-- Backfill: any project currently with status='completed' gets its completed_at
-- set to its most recent updated_at (best approximation we have for historical data).
UPDATE projects
SET completed_at = updated_at
WHERE status = 'completed' AND completed_at IS NULL;
