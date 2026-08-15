-- W3 security posture sweep — revoke erroneous anon/authenticated TABLE grants on
-- the eight App Store Connect analytics tables (asc_*). RLS already denies anon;
-- the grants are a latent landmine. Only lib/admin/app-store-*.ts (service_role)
-- touches them. service_role retains full access.

begin;

do $do$
declare
  t text;
  asc_tables constant text[] := array[
    'asc_discovery_engagement', 'asc_downloads', 'asc_raw_rows', 'asc_report_instances',
    'asc_report_requests', 'asc_report_segments', 'asc_reports', 'asc_sync_status'
  ];
begin
  foreach t in array asc_tables loop
    execute format('revoke all on table public.%I from anon, authenticated', t);
  end loop;
end
$do$;

do $do$
declare
  v_leak int;
  v_svc int;
  asc_tables constant text[] := array[
    'asc_discovery_engagement', 'asc_downloads', 'asc_raw_rows', 'asc_report_instances',
    'asc_report_requests', 'asc_report_segments', 'asc_reports', 'asc_sync_status'
  ];
begin
  select count(*) into v_leak
  from information_schema.role_table_grants
  where table_schema = 'public' and table_name = any (asc_tables) and grantee in ('anon', 'authenticated');
  if v_leak <> 0 then
    raise exception 'sec_w3_asc_grants_sentinel: % residual anon/authenticated grant(s)', v_leak;
  end if;

  select count(distinct table_name) into v_svc
  from information_schema.role_table_grants
  where table_schema = 'public' and table_name = any (asc_tables)
    and grantee = 'service_role' and privilege_type = 'SELECT';
  if v_svc <> 8 then
    raise exception 'sec_w3_asc_grants_sentinel: service_role lost access (expected 8 tables, found %)', v_svc;
  end if;
end
$do$;

commit;
