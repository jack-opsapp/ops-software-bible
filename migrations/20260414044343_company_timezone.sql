-- 061: Per-company IANA timezone
ALTER TABLE companies
  ADD COLUMN IF NOT EXISTS timezone TEXT NOT NULL DEFAULT 'America/Vancouver';

COMMENT ON COLUMN companies.timezone IS
  'IANA timezone identifier (e.g. America/Vancouver). Used by crons and scheduling features to interpret per-company local times.';
