ALTER TABLE companies
  ADD COLUMN priority_support_period TEXT
    CHECK (priority_support_period IN ('monthly','annual'));

COMMENT ON COLUMN companies.priority_support_period IS
  'Billing cadence for the active Priority Support subscription. Mirrors the Stripe price ID. NULL when has_priority_support = false.';
