-- H10 — close the legacy convert_lead_to_project door.
--
-- STATUS: NOT YET APPLIED. Authored and committed for review; the founder
-- approves before it runs. The filename timestamp is authoring time, NOT a
-- ledger version — at apply time read the stamped version back out of
-- supabase_migrations.schema_migrations and rename this file to
-- <ledger_version>_<ledger_name>.sql per migrations/README.md.
--
-- WHAT IT IS
--
-- public.convert_lead_to_project(uuid, numeric, text, text, uuid) is a
-- SECURITY DEFINER shim, introduced for iOS and rewired to delegate to the
-- unified RPC by 20260603020001_won_conversion_ios_shim.sql. It is the only
-- door into the convert transaction that skips the concurrency guards:
--
--   * it never passes p_expected_stage, so it cannot lose a snapshot race —
--     it simply converts whatever it finds;
--   * it never passes p_expected_assignment_version;
--   * it hardcodes p_win_opportunity := true;
--   * it accepts p_address and silently discards it — the parameter is
--     declared and then never referenced in the body.
--
-- Its EXECUTE ACL is currently {PUBLIC, postgres, anon, authenticated,
-- service_role}: reachable by any PostgREST caller.
--
-- ZERO CALLERS — evidence (all read-only, 2026-08-18)
--
--   * Durable audit proof. The shim unconditionally stamps
--     p_evidence := jsonb_build_object('legacy_shim', true), so every
--     successful call since the unified RPC's disposition audit went live
--     leaves a row behind. public.opportunity_dispositions holds 26
--     'converted_to_project' rows spanning 2026-06-02 → 2026-08-14, and
--     ZERO carry the legacy_shim marker. No caller of any origin — client,
--     server, or cron — has completed a conversion through this shim in the
--     entire life of the audit trail.
--   * No database caller: scanning pg_proc.prosrc across public, private,
--     auth, storage and cron for 'convert_lead_to_project' returns nothing.
--   * No edge function: all 45 checked-out supabase/functions trees, zero hits.
--   * No current web caller: ops-web-agent-control-plane (the live branch,
--     feat/ops-agent-control-plane-20260807) mentions the name only in the
--     generated src/lib/types/database.types.ts.
--   * No iOS caller: every ops-ios hit is a comment. LeadConversionService.swift
--     states outright that it calls convert_opportunity_to_project and NOT this
--     shim; iOS stopped calling it 2026-07-16 (2bb20485).
--   * The single genuine supabase.rpc("convert_lead_to_project", …) call site
--     left on disk is in ops-web/.claude/worktrees/gracious-booth-d66428, an
--     abandoned agent worktree pinned at 2026-06-29 on a throwaway claude/*
--     branch, under the ops-web checkout that is itself parked on the stale
--     feat/inbox-dark-launch (2026-07-16). Not live code, not deployed.
--
-- WHY REVOKE AND NOT DROP
--
-- A dropped function returns PGRST202 "function not found", which some clients
-- treat as a soft/routing failure. A revoked function returns 42501 permission
-- denied — unambiguous and loud. Any stale client that still reaches for this
-- entry point fails visibly instead of quietly bypassing the concurrency
-- guards, and the definition stays in the catalog for inspection and instant
-- restoration.
--
-- SCOPE OF THE REVOKE
--
-- PUBLIC, anon and authenticated are the PostgREST-reachable roles — the stale
-- client threat this closes. service_role is included as well because the
-- disposition evidence above covers server-side callers too and proves there
-- are none; leaving it would keep the guard-skipping path open for exactly
-- nobody. postgres (owner) retains EXECUTE, so the function stays fully
-- inspectable and the grants are one statement away from restoration.
--
-- If review prefers the narrower posture, drop the service_role line and keep
-- everything else; the crew-facing outcome is identical.
--
-- Additive and shipped-client-compatible: no schema, signature or payload
-- change. A deployed iOS 3.0.5 build never calls this function.

begin;

revoke execute on function public.convert_lead_to_project(
  uuid,
  numeric,
  text,
  text,
  uuid
) from public, anon, authenticated, service_role;

commit;

-- VERIFY AFTER APPLYING — by object, not by ledger version.
--
-- 1. Only the owner retains EXECUTE (expects {postgres}):
--
--      select array(
--               select g.grantee
--                 from information_schema.routine_privileges g
--                 join pg_proc p on p.proname = g.routine_name
--                 join pg_namespace n on n.oid = p.pronamespace
--                                    and n.nspname = g.specific_schema
--                where p.proname = 'convert_lead_to_project'
--                  and n.nspname = 'public'
--                  and g.privilege_type = 'EXECUTE'
--             ) as execute_grantees;
--
-- 2. The function still exists and is inspectable (expects one row):
--
--      select pg_get_functiondef(
--        'public.convert_lead_to_project(uuid,numeric,text,text,uuid)'::regprocedure
--      );
--
-- 3. The real conversion path is untouched — convert_opportunity_to_project
--    keeps its grants (expects authenticated and service_role present):
--
--      select array(
--               select g.grantee
--                 from information_schema.routine_privileges g
--                where g.specific_schema = 'public'
--                  and g.routine_name = 'convert_opportunity_to_project'
--                  and g.privilege_type = 'EXECUTE'
--             ) as execute_grantees;
--
-- 4. Watch for a surprise caller: any new row here after the apply means
--    something still reaches the shim and the revoke is now failing it loudly
--    (expects 0, forever):
--
--      select count(*) from public.opportunity_dispositions
--       where evidence ? 'legacy_shim';
--
-- ROLLBACK:
--
--   grant execute on function public.convert_lead_to_project(
--     uuid, numeric, text, text, uuid
--   ) to anon, authenticated, service_role;
