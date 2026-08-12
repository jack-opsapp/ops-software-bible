-- MED-2: get_company_join_details was anon+PUBLIC executable and returns the
-- seated-team roster (first/last names + avatars) to anyone holding a company
-- code. Fix: restrict execution to authenticated (REVOKE anon, PUBLIC). The
-- payload shape is unchanged — the iOS confirm-company screen renders the team
-- preview (avatars/initials) and uses company_code as the join proof; gating to
-- authenticated callers who already hold the exact code is the fix. Web does not
-- call this RPC; iOS calls it with an authenticated Firebase JWT.
REVOKE EXECUTE ON FUNCTION public.get_company_join_details(text) FROM anon, PUBLIC;
