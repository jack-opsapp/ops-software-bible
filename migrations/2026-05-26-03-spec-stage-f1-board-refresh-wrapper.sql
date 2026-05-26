-- SPEC Stage F.1 — public wrapper for `private.refresh_spec_board_snapshot()`
-- Source spec: ops-software-bible/SPEC/02_DATA_MODEL.md § Public board snapshot
-- Applied: 2026-05-26 via Supabase MCP apply_migration as `spec_stage_f1_board_refresh_wrapper`.
--
-- Stage A placed `refresh_spec_board_snapshot()` in the `private` schema per
-- SPEC-SECURITY-DEFINER-PRIVATE-SCHEMA (matches the existing OPS convention for
-- SECURITY DEFINER helpers used by RLS). That works for the pg_cron job (which
-- runs as `postgres`) but not for the operator-facing manual refresh from
-- `POST /api/admin/spec/board/refresh` in OPS-Web. PostgREST only exposes the
-- schemas listed in the project's "Exposed schemas" config (default:
-- `public, storage, graphql_public`); `private` is intentionally NOT in that
-- list so anon/authenticated cannot reach the SECURITY DEFINER helpers
-- directly.
--
-- This wrapper sits in `public` and delegates to the `private` function, so the
-- operator-gated server route can call it as a normal RPC via supabase-js
-- (which targets PostgREST against the `public` schema by default). The wrapper
-- is SECURITY DEFINER and its EXECUTE grant is restricted to `service_role` —
-- anon and authenticated have no EXECUTE on the wrapper, so the only path that
-- can fire a manual refresh is the OPS-Web server route after it has cleared
-- the `private.is_spec_operator()` check.
--
-- Idempotent (CREATE OR REPLACE + REVOKE ALL + explicit GRANT).

create or replace function public.refresh_spec_board_snapshot()
returns void
language sql
security definer
set search_path = public, private, pg_temp
as $$
  select private.refresh_spec_board_snapshot();
$$;

revoke all on function public.refresh_spec_board_snapshot() from public, anon, authenticated;
grant execute on function public.refresh_spec_board_snapshot() to service_role;

comment on function public.refresh_spec_board_snapshot() is
  'Public-schema PostgREST-callable wrapper around private.refresh_spec_board_snapshot(). '
  'EXECUTE granted to service_role only; the OPS-Web /api/admin/spec/board/refresh '
  'route calls this via supabase-js after re-asserting private.is_spec_operator() on '
  'the calling user. anon/authenticated have no EXECUTE. The pg_cron job continues '
  'to call private.refresh_spec_board_snapshot() directly as `postgres`.';
