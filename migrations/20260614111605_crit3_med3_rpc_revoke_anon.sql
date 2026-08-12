-- The database's default privileges auto-grant EXECUTE to anon/authenticated on
-- new public functions; REVOKE ... FROM public does not remove the direct anon
-- grant. update_company_setup_for_member fails closed for anon (NO_JWT) anyway,
-- but lock it down to match create_company_for_owner and the team's
-- server-only-function hardening convention.
REVOKE EXECUTE ON FUNCTION public.update_company_setup_for_member(text, text[], text, text, boolean) FROM anon;
