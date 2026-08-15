-- W3 security posture sweep (follow-up) — revoke anon/authenticated grants on the
-- asc_conversion_daily security_invoker view. Read path already closed by
-- 20260703170300 (base-table revoke); this removes the vestigial view grants.
-- Operator dashboard reads via getAdminSupabase()/service_role.
begin;

revoke all on public.asc_conversion_daily from anon, authenticated;

do $do$
declare v_bad int;
begin
  select count(*) into v_bad
  from information_schema.role_table_grants
  where table_schema = 'public' and table_name = 'asc_conversion_daily'
    and grantee in ('anon', 'authenticated');
  if v_bad <> 0 then
    raise exception 'sec_w3_asc_view_sentinel: % residual anon/authenticated grant(s)', v_bad;
  end if;
end
$do$;

commit;
