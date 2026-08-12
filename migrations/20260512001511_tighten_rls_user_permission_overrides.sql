-- RLS HARDENING - P1-3
-- The pre-existing "Admins can manage overrides" policy on user_permission_overrides
-- was gated by `USING true` with no WITH CHECK. Despite its name, every authenticated
-- user had full ALL (SELECT/INSERT/UPDATE/DELETE) access. This let any authenticated
-- user grant themselves any permission by inserting a row — privilege escalation.
--
-- Fix: drop the open policy and replace with four explicit policies, all gated by
-- `private.current_user_is_admin()` AND a company-scope match using
-- `private.get_user_company_id()`. SELECT for the row's own user is already covered
-- by the existing "Users can read own overrides" policy and is left in place.

DROP POLICY IF EXISTS "Admins can manage overrides" ON public.user_permission_overrides;

CREATE POLICY "Admins can read company overrides"
  ON public.user_permission_overrides FOR SELECT
  USING (
    private.current_user_is_admin()
    AND company_id = (SELECT private.get_user_company_id())
  );

CREATE POLICY "Admins can insert company overrides"
  ON public.user_permission_overrides FOR INSERT
  WITH CHECK (
    private.current_user_is_admin()
    AND company_id = (SELECT private.get_user_company_id())
  );

CREATE POLICY "Admins can update company overrides"
  ON public.user_permission_overrides FOR UPDATE
  USING (
    private.current_user_is_admin()
    AND company_id = (SELECT private.get_user_company_id())
  )
  WITH CHECK (
    private.current_user_is_admin()
    AND company_id = (SELECT private.get_user_company_id())
  );

CREATE POLICY "Admins can delete company overrides"
  ON public.user_permission_overrides FOR DELETE
  USING (
    private.current_user_is_admin()
    AND company_id = (SELECT private.get_user_company_id())
  );
