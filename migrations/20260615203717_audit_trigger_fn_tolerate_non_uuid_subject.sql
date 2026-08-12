-- audit_trigger_fn: tolerate a non-uuid request.jwt subject.
-- See 20260615211000_audit_trigger_fn_tolerate_non_uuid_subject.sql for rationale.
-- Post crit3, 'sub' is the Firebase subject (non-uuid) for bridged sessions and
-- the synthetic QBO acceptance actor; the bare (auth.jwt()->>'sub')::uuid cast
-- raised 22P02 and aborted audited writes (estimates/invoices/payments). Record
-- the subject only when uuid-shaped, else NULL (changed_by is nullable, no FK).
-- Behavior unchanged for uuid/null subjects. Idempotent + sentinel-guarded.

begin;

create or replace function public.audit_trigger_fn()
 returns trigger
 language plpgsql
 security definer
 set search_path to 'public', 'pg_temp'
as $function$
declare
  v_changed_by uuid := case
    when nullif(auth.jwt() ->> 'sub', '') ~
      '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'
      then (auth.jwt() ->> 'sub')::uuid
    else null
  end;
begin
  if tg_op = 'INSERT' then
    insert into audit_log (table_name, record_id, company_id, action, new_data, changed_by)
    values (tg_table_name, new.id, new.company_id, 'INSERT', to_jsonb(new), v_changed_by);
    return new;
  elsif tg_op = 'UPDATE' then
    insert into audit_log (table_name, record_id, company_id, action, old_data, new_data, changed_by)
    values (tg_table_name, new.id, new.company_id, 'UPDATE', to_jsonb(old), to_jsonb(new), v_changed_by);
    return new;
  elsif tg_op = 'DELETE' then
    insert into audit_log (table_name, record_id, company_id, action, old_data, changed_by)
    values (tg_table_name, old.id, old.company_id, 'DELETE', to_jsonb(old), v_changed_by);
    return old;
  end if;
  return null;
end;
$function$;

do $do$
declare
  v_def text := pg_get_functiondef('public.audit_trigger_fn()'::regprocedure);
  v_secdef boolean;
begin
  select prosecdef into v_secdef from pg_proc where oid = 'public.audit_trigger_fn()'::regprocedure;
  if v_secdef is distinct from true then
    raise exception 'audit_trigger_non_uuid_subject_sentinel: audit_trigger_fn is not SECURITY DEFINER';
  end if;
  if v_def not like '%v_changed_by%' then
    raise exception 'audit_trigger_non_uuid_subject_sentinel: changed_by is not routed through the guarded variable';
  end if;
  if v_def not like '%[0-9a-fA-F]{8}-%' then
    raise exception 'audit_trigger_non_uuid_subject_sentinel: uuid-shape guard missing';
  end if;
end
$do$;

commit;
