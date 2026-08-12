-- 062: Per-company locale for server-rendered client-facing text.
ALTER TABLE companies
  ADD COLUMN IF NOT EXISTS locale TEXT NOT NULL DEFAULT 'en';

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'companies_locale_check'
  ) THEN
    ALTER TABLE companies
      ADD CONSTRAINT companies_locale_check
      CHECK (locale IN ('en', 'es'));
  END IF;
END $$;

COMMENT ON COLUMN companies.locale IS
  'IETF language tag for server-rendered client-facing text. Supported values mirror src/i18n/config.ts supportedLocales.';
