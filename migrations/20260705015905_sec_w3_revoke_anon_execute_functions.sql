-- W3 security posture sweep — revoke PUBLIC/anon/authenticated EXECUTE on seven
-- SECURITY DEFINER functions with no client caller. service_role retains EXECUTE;
-- the internal SECURITY DEFINER chain runs as the owner regardless.

begin;

revoke all on function public.audit_trigger_fn() from public, anon, authenticated;
revoke all on function public.tr_activity_first_log_auto_advance() from public, anon, authenticated;

revoke all on function public.fire_due_task_reminders() from public, anon, authenticated;
grant execute on function public.fire_due_task_reminders() to service_role;

revoke all on function public.resolve_task_reminder_recipients(uuid, uuid[], text, jsonb) from public, anon, authenticated;
grant execute on function public.resolve_task_reminder_recipients(uuid, uuid[], text, jsonb) to service_role;

revoke all on function public.users_with_permission(uuid, text, text) from public, anon, authenticated;
grant execute on function public.users_with_permission(uuid, text, text) to service_role;

revoke all on function public.increment_opportunity_correspondence(uuid, boolean, timestamp with time zone) from public, anon, authenticated;
grant execute on function public.increment_opportunity_correspondence(uuid, boolean, timestamp with time zone) to service_role;

revoke all on function public.qbo_match_customer_candidates(uuid, text, numeric) from public, anon, authenticated;
grant execute on function public.qbo_match_customer_candidates(uuid, text, numeric) to service_role;

do $do$
declare
  v_bad int;
  v_svc int;
begin
  select count(*) into v_bad
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
    and (p.proname, pg_get_function_identity_arguments(p.oid)) in (
      ('audit_trigger_fn', ''),
      ('tr_activity_first_log_auto_advance', ''),
      ('fire_due_task_reminders', ''),
      ('resolve_task_reminder_recipients', 'p_company_id uuid, p_task_team_members uuid[], p_recipient_mode text, p_recipient_config jsonb'),
      ('users_with_permission', 'p_company_id uuid, p_permission text, p_required_scope text'),
      ('increment_opportunity_correspondence', 'p_opportunity_id uuid, p_is_inbound boolean, p_email_date timestamp with time zone'),
      ('qbo_match_customer_candidates', 'p_company_id uuid, p_name text, p_threshold numeric')
    )
    and (has_function_privilege('anon', p.oid, 'EXECUTE') or has_function_privilege('authenticated', p.oid, 'EXECUTE'));
  if v_bad <> 0 then
    raise exception 'sec_w3_revoke_exec_sentinel: % function(s) still anon/authenticated-executable', v_bad;
  end if;

  select count(*) into v_svc
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
    and (p.proname, pg_get_function_identity_arguments(p.oid)) in (
      ('fire_due_task_reminders', ''),
      ('resolve_task_reminder_recipients', 'p_company_id uuid, p_task_team_members uuid[], p_recipient_mode text, p_recipient_config jsonb'),
      ('users_with_permission', 'p_company_id uuid, p_permission text, p_required_scope text'),
      ('increment_opportunity_correspondence', 'p_opportunity_id uuid, p_is_inbound boolean, p_email_date timestamp with time zone'),
      ('qbo_match_customer_candidates', 'p_company_id uuid, p_name text, p_threshold numeric')
    )
    and has_function_privilege('service_role', p.oid, 'EXECUTE');
  if v_svc <> 5 then
    raise exception 'sec_w3_revoke_exec_sentinel: service_role lost EXECUTE (expected 5, found %)', v_svc;
  end if;
end
$do$;

commit;
