-- INCIDENT FIX — "permission denied for function normalize_address" on every
-- project update from the app.
--
-- public.projects carries a partial index whose expression calls the function:
--
--   CREATE INDEX projects_active_company_normalized_address_idx
--     ON public.projects (company_id, private.normalize_address(address))
--     WHERE deleted_at IS NULL AND status IN ('rfq','estimated','accepted','in_progress');
--
-- Postgres evaluates an index expression in the CALLING role's context on every
-- INSERT/UPDATE that maintains the index — it is not covered by any SECURITY
-- DEFINER wrapper. private.normalize_address(text) was left with its default
-- owner-only ACL (postgres=X/postgres), so the app roles could not execute it
-- and every qualifying project write failed with:
--
--   permission denied for function normalize_address
--
-- The function is a pure text normalizer (SECURITY INVOKER, no table access, no
-- data returned beyond a folded copy of the string it was handed), so granting
-- EXECUTE exposes nothing the caller did not already supply. The grant is what
-- makes the existing index maintainable by the roles the app actually runs as.

grant execute on function private.normalize_address(text)
  to anon, authenticated, service_role;
