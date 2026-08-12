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
  'Public-schema PostgREST-callable wrapper around private.refresh_spec_board_snapshot(). EXECUTE granted to service_role only; the OPS-Web /api/admin/spec/board/refresh route calls this via supabase-js after re-asserting private.is_spec_operator() on the calling user. anon/authenticated have no EXECUTE. The pg_cron job continues to call private.refresh_spec_board_snapshot() directly as postgres.';
