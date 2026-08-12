CREATE TABLE public.expense_auto_approve_rule_members (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  rule_id uuid NOT NULL REFERENCES public.expense_auto_approve_rules(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES public.users(id),
  UNIQUE(rule_id, user_id)
);

ALTER TABLE public.expense_auto_approve_rule_members ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view rule members for their company"
  ON public.expense_auto_approve_rule_members FOR SELECT
  USING (rule_id IN (
    SELECT id FROM public.expense_auto_approve_rules
    WHERE company_id IN (SELECT company_id FROM public.users WHERE id = auth.uid())
  ));

CREATE POLICY "Admins can insert rule members"
  ON public.expense_auto_approve_rule_members FOR INSERT
  WITH CHECK (rule_id IN (
    SELECT id FROM public.expense_auto_approve_rules
    WHERE company_id IN (
      SELECT company_id FROM public.users
      WHERE id = auth.uid() AND (role = 'admin' OR is_company_admin = true)
    )
  ));

CREATE POLICY "Admins can delete rule members"
  ON public.expense_auto_approve_rule_members FOR DELETE
  USING (rule_id IN (
    SELECT id FROM public.expense_auto_approve_rules
    WHERE company_id IN (
      SELECT company_id FROM public.users
      WHERE id = auth.uid() AND (role = 'admin' OR is_company_admin = true)
    )
  ));
