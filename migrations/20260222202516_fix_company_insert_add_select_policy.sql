
-- Restore the company_self_access ALL policy
CREATE POLICY company_self_access ON public.companies
  FOR ALL
  USING (id = (SELECT private.get_user_company_id()));

-- Add SELECT policy so the creator can read back the row after INSERT RETURNING
-- (account_holder_id matches the authenticated user)
CREATE POLICY company_select_for_creator ON public.companies
  FOR SELECT TO authenticated
  USING (lower(account_holder_id) = lower(auth.uid()::text));

