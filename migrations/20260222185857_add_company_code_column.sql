
-- Add company_code column for employee join flow
ALTER TABLE companies ADD COLUMN IF NOT EXISTS company_code text;

-- Create unique index on company_code (allow NULLs, but enforce uniqueness on non-null values)
CREATE UNIQUE INDEX IF NOT EXISTS idx_companies_company_code ON companies (company_code) WHERE company_code IS NOT NULL;

-- Backfill: use external_id as company_code where it looks like a readable code
-- (not a Bubble numeric ID which matches pattern digits + 'x' + digits)
UPDATE companies
SET company_code = external_id
WHERE external_id IS NOT NULL
  AND external_id !~ '^\d+x\d+$'
  AND company_code IS NULL;

-- For companies with Bubble numeric IDs or no external_id, generate a short code
-- using first 8 chars of the UUID (uppercase, no hyphens)
UPDATE companies
SET company_code = UPPER(REPLACE(LEFT(id::text, 8), '-', ''))
WHERE company_code IS NULL;

