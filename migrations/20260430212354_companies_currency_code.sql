ALTER TABLE companies ADD COLUMN IF NOT EXISTS currency_code TEXT NOT NULL DEFAULT 'CAD'
  CHECK (currency_code IN ('CAD', 'USD', 'EUR', 'GBP', 'AUD', 'NZD', 'MXN', 'BRL', 'JPY', 'INR'));

UPDATE companies SET currency_code = CASE
  WHEN timezone IN (
    'America/New_York', 'America/Chicago', 'America/Denver', 'America/Los_Angeles',
    'America/Phoenix', 'America/Anchorage', 'America/Honolulu', 'America/Detroit',
    'America/Indianapolis', 'America/Boise', 'America/Sitka'
  ) THEN 'USD'
  WHEN timezone LIKE 'America/%' THEN 'CAD'
  WHEN timezone = 'Europe/London' THEN 'GBP'
  WHEN timezone LIKE 'Europe/%' THEN 'EUR'
  WHEN timezone LIKE 'Australia/%' THEN 'AUD'
  WHEN timezone LIKE 'Pacific/Auckland%' THEN 'NZD'
  WHEN timezone = 'Asia/Tokyo' THEN 'JPY'
  WHEN timezone = 'Asia/Kolkata' THEN 'INR'
  WHEN timezone = 'America/Sao_Paulo' THEN 'BRL'
  WHEN timezone LIKE 'America/Mexico%' THEN 'MXN'
  ELSE 'CAD'
END;

COMMENT ON COLUMN companies.currency_code IS
  'ISO 4217 currency code. Drives money formatting and report aggregation app-wide. Defaults to CAD (OPS origin). Admin can change in Settings.';
