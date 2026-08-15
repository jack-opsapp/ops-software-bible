CREATE TABLE public.expense_auto_approve_rules (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL REFERENCES public.companies(id),
  created_by uuid NOT NULL REFERENCES public.users(id),
  rule_type text NOT NULL CHECK (rule_type IN ('invoice', 'line_item')),
  threshold_amount numeric NOT NULL,
  applies_to_all boolean NOT NULL DEFAULT false,
  is_active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.expense_auto_approve_rules ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view rules for their company"
  ON public.expense_auto_approve_rules FOR SELECT
  USING (company_id IN (SELECT company_id FROM public.users WHERE id = auth.uid()));

CREATE POLICY "Admins can insert rules for their company"
  ON public.expense_auto_approve_rules FOR INSERT
  WITH CHECK (company_id IN (
    SELECT company_id FROM public.users
    WHERE id = auth.uid() AND (role = 'admin' OR is_company_admin = true)
  ));

CREATE POLICY "Admins can update rules for their company"
  ON public.expense_auto_approve_rules FOR UPDATE
  USING (company_id IN (
    SELECT company_id FROM public.users
    WHERE id = auth.uid() AND (role = 'admin' OR is_company_admin = true)
  ));

CREATE POLICY "Admins can delete rules for their company"
  ON public.expense_auto_approve_rules FOR DELETE
  USING (company_id IN (
    SELECT company_id FROM public.users
    WHERE id = auth.uid() AND (role = 'admin' OR is_company_admin = true)
  ));
