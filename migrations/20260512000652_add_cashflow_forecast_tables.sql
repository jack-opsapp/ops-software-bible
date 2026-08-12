-- Cashflow Forecast feature — additive schema only.
-- Spec: docs/superpowers/specs/2026-05-11-cashflow-forecast-design.md
-- Plan: docs/superpowers/plans/2026-05-11-cashflow-forecast.md

-- 1. New table: recurring_expenses (owner-managed recurring outflows for forecast)
CREATE TABLE public.recurring_expenses (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id      uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
  name            text NOT NULL,
  amount          numeric(12,2) NOT NULL CHECK (amount >= 0),
  currency        text NOT NULL DEFAULT 'USD',
  cadence         text NOT NULL CHECK (cadence IN ('weekly','biweekly','monthly','quarterly','annually')),
  next_due_date   date NOT NULL,
  end_date        date NULL,
  category_id     uuid NULL REFERENCES public.expense_categories(id),
  notes           text NULL,
  created_by      uuid NULL REFERENCES public.users(id),
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now(),
  deleted_at      timestamptz NULL
);

CREATE INDEX recurring_expenses_company_idx
  ON public.recurring_expenses (company_id)
  WHERE deleted_at IS NULL;

ALTER TABLE public.recurring_expenses ENABLE ROW LEVEL SECURITY;

CREATE POLICY company_isolation ON public.recurring_expenses
  FOR ALL
  USING (company_id = (SELECT private.get_user_company_id()))
  WITH CHECK (company_id = (SELECT private.get_user_company_id()));

CREATE TRIGGER recurring_expenses_set_updated_at
  BEFORE UPDATE ON public.recurring_expenses
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at_now();

-- 2. Additive column on payment_milestones — when each milestone is expected to invoice
ALTER TABLE public.payment_milestones
  ADD COLUMN expected_date date NULL;

-- 3. Additive columns on expense_settings (per-company forecast config)
ALTER TABLE public.expense_settings
  ADD COLUMN forecast_low_water_threshold numeric(12,2) NULL DEFAULT 5000,
  ADD COLUMN forecast_current_balance     numeric(12,2) NULL,
  ADD COLUMN forecast_balance_updated_at  timestamptz   NULL;

-- 4. New table: forecast_alerts (anti-spam ledger for persistent dip notifications)
CREATE TABLE public.forecast_alerts (
  company_id              uuid PRIMARY KEY REFERENCES public.companies(id) ON DELETE CASCADE,
  last_dip_notified_at    timestamptz NULL,
  last_dip_min_balance    numeric(12,2) NULL,
  last_dip_min_week_start date NULL,
  last_cleared_at         timestamptz NULL,
  dismissed_until_balance numeric(12,2) NULL,
  updated_at              timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.forecast_alerts ENABLE ROW LEVEL SECURITY;

CREATE POLICY company_isolation ON public.forecast_alerts
  FOR ALL
  USING (company_id = (SELECT private.get_user_company_id()))
  WITH CHECK (company_id = (SELECT private.get_user_company_id()));

CREATE TRIGGER forecast_alerts_set_updated_at
  BEFORE UPDATE ON public.forecast_alerts
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at_now();

COMMENT ON TABLE public.recurring_expenses IS 'Owner-managed recurring outflows (rent, insurance, payroll, subscriptions). Drives the recurring layer of the Cashflow Forecast. Forecast-only — does not auto-create expense rows on due dates.';
COMMENT ON TABLE public.forecast_alerts IS 'Per-company anti-spam ledger for the persistent forecast_dip notification. Re-fire rules: 24h gap + 10% worse min balance, OR cleared-then-redipped.';
COMMENT ON COLUMN public.payment_milestones.expected_date IS 'When this milestone is expected to be invoiced. Drives the contracted-layer forecast projection (offset by company avgDaysToPayment).';
