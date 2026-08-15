-- CRIT-3 Phase A — observability for the identity-linkage backfill.
-- Records a daily snapshot of public.users linkage status. `unlinked_with_email`
-- is the Phase C gate metric: the RLS email->sub re-key must NOT be applied
-- until it is ~0 (re-keying locks out any active user whose row is not yet
-- linked by auth_id/firebase_uid).

create table if not exists private.identity_linkage_metrics (
  id bigint generated always as identity primary key,
  captured_at timestamptz not null default now(),
  active_total integer not null,
  active_auth_id_null integer not null,
  active_firebase_uid_null integer not null,
  active_both_null integer not null,
  unlinked_with_email integer not null,
  unlinked_no_email integer not null,
  active_any_linked integer not null
);

comment on table private.identity_linkage_metrics is
  'CRIT-3 observability: daily snapshot of public.users identity linkage. unlinked_with_email is the Phase C gate metric — the RLS email->sub re-key must NOT ship until it is ~0.';

-- Internal table in the unexposed `private` schema. Enable RLS with no policies
-- so it stays inaccessible to anon/authenticated even if `private` were ever
-- exposed; only postgres/service_role (which bypass RLS) read or write it.
alter table private.identity_linkage_metrics enable row level security;

create or replace function private.capture_identity_linkage_metrics()
returns private.identity_linkage_metrics
language sql
security definer
set search_path to 'public', 'pg_temp'
as $fn$
  insert into private.identity_linkage_metrics (
    active_total, active_auth_id_null, active_firebase_uid_null,
    active_both_null, unlinked_with_email, unlinked_no_email, active_any_linked
  )
  select
    count(*) filter (where deleted_at is null),
    count(*) filter (where deleted_at is null and auth_id is null),
    count(*) filter (where deleted_at is null and firebase_uid is null),
    count(*) filter (where deleted_at is null and auth_id is null and firebase_uid is null),
    count(*) filter (where deleted_at is null and auth_id is null and firebase_uid is null and email is not null),
    count(*) filter (where deleted_at is null and auth_id is null and firebase_uid is null and email is null),
    count(*) filter (where deleted_at is null and (auth_id is not null or firebase_uid is not null))
  from public.users
  returning *;
$fn$;

comment on function private.capture_identity_linkage_metrics() is
  'CRIT-3 observability: inserts a public.users linkage snapshot and returns it. Called daily by the cron job crit3-identity-linkage-daily.';

-- SECURITY DEFINER hardening: not a callable API endpoint.
revoke all on function private.capture_identity_linkage_metrics() from public;
revoke all on function private.capture_identity_linkage_metrics() from anon;
revoke all on function private.capture_identity_linkage_metrics() from authenticated;

-- Daily snapshot at 08:07 UTC. cron.schedule upserts by job name (pg_cron 1.6).
select cron.schedule(
  'crit3-identity-linkage-daily',
  '7 8 * * *',
  $cron$ select private.capture_identity_linkage_metrics(); $cron$
);

-- Seed a baseline data point for today.
select private.capture_identity_linkage_metrics();
