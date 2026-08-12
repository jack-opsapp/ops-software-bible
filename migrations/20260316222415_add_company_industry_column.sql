ALTER TABLE companies ADD COLUMN IF NOT EXISTS industry text DEFAULT 'trades';
COMMENT ON COLUMN companies.industry IS 'Business industry/vertical — defaults to trades';
