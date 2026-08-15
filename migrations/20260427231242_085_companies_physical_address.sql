ALTER TABLE public.companies
  ADD COLUMN IF NOT EXISTS physical_address text;

COMMENT ON COLUMN public.companies.physical_address IS
  'Postal mailing address used in compliance footers of whitelabel portal emails. Format: "Street, City, Province/State Postal, Country". Operator-set in Settings → Company.';
