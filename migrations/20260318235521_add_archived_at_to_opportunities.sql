
-- Add archived_at column to opportunities table
ALTER TABLE opportunities
ADD COLUMN archived_at timestamptz DEFAULT NULL;

-- Index for filtering archived opportunities efficiently
CREATE INDEX idx_opportunities_archived_at ON opportunities (archived_at)
WHERE archived_at IS NOT NULL;

-- Comment for documentation
COMMENT ON COLUMN opportunities.archived_at IS 'Timestamp when opportunity was archived (hidden from board but recoverable). NULL = active.';

