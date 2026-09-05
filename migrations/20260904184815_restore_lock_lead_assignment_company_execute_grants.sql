-- LIVE OUTAGE FIX. Every iOS lead stage move has been refused since 2026-09-01.
--
-- 20260901232912_external_analytics_lifecycle_evidence rewrote
-- public.move_opportunity_stage to call private.lock_lead_assignment_company,
-- but left move_opportunity_stage as SECURITY INVOKER. The helper's ACL is
-- postgres=X/postgres, so the inner call runs as the CLIENT role and dies with
-- 42501 before a single row is read.
--
-- EXECUTE is checked BEFORE SECURITY DEFINER is honoured, so the helper being
-- DEFINER does not save it — the same mechanism as the 5-day signup blackout
-- (index-expression helpers, ledger restore_users_index_expression_execute_grants).
--
-- Proven as both API roles by rolled-back probe:
--   authenticated -> 42501 permission denied for function lock_lead_assignment_company
--   anon          -> 42501 permission denied for function lock_lead_assignment_company
--
-- The grant is safe: the helper takes a transaction-scoped advisory lock keyed on
-- a company-id hash. It reads no rows, writes nothing, returns nothing, and is
-- SECURITY DEFINER with search_path pinned to pg_catalog, pg_temp.
--
-- The alternative — flipping move_opportunity_stage to SECURITY DEFINER — was
-- rejected: its authorization IS RLS, and opportunities is not FORCE RLS, so
-- that would bypass row security and require hand-written checks throughout.

grant execute on function private.lock_lead_assignment_company(uuid) to anon, authenticated, service_role;

do $$
declare v_missing text;
begin
  select string_agg(r, ', ')
    into v_missing
    from unnest(array['anon','authenticated','service_role']) as r
   where not has_function_privilege(r, 'private.lock_lead_assignment_company(uuid)', 'EXECUTE');
  if v_missing is not null then
    raise exception 'grant did not take for: %', v_missing;
  end if;
end $$;
