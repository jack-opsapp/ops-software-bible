-- W3 security posture sweep — add caller guards to two SECURITY DEFINER functions
-- that accepted a company id with no caller check. Additive CREATE OR REPLACE with
-- unchanged signatures. See docs/artifacts/w3-security-posture-disposition-2026-07-03.md.
begin;

set local search_path = public, private, pg_temp;

-- get_inbox_density_per_client: caller-scope guard (private.get_user_company_id()
-- returns uuid; p_company_id is uuid). Silent-empty on mismatch.
create or replace function public.get_inbox_density_per_client(p_company_id uuid)
  returns table(client_id uuid, thread_count integer, last_message_at timestamp with time zone)
  language sql
  stable
  security definer
  set search_path to 'public'
as $function$
  select
    et.client_id,
    count(*)::int as thread_count,
    max(et.last_message_at) as last_message_at
  from public.email_threads et
  where et.company_id = p_company_id
    and private.get_user_company_id() is not distinct from p_company_id  -- W3 caller-scope guard
    and et.client_id is not null
    and et.archived_at is null
  group by et.client_id;
$function$;

-- remove_seated_employee: only a soft-deleted member's seat may be removed (matches
-- the iOS account-deletion cleanup); blocks eviction of active members. service_role
-- bypasses. (p_company_id / p_user_id are text; users.id / company_id are uuid.)
create or replace function public.remove_seated_employee(p_company_id text, p_user_id text)
  returns void
  language plpgsql
  security definer
  set search_path to 'public'
as $function$
begin
  if coalesce(auth.jwt() ->> 'role', '') is distinct from 'service_role' then
    if not exists (
      select 1
      from public.users u
      where u.id = p_user_id::uuid
        and u.company_id = p_company_id::uuid
        and u.deleted_at is not null
    ) then
      raise exception 'remove_seated_employee: % is not a soft-deleted member of company %', p_user_id, p_company_id
        using errcode = '42501';
    end if;
  end if;

  update companies
     set seated_employee_ids = array_remove(seated_employee_ids, p_user_id),
         updated_at = now()
   where id = p_company_id::uuid;
end;
$function$;

-- Sentinel: both function bodies must now contain their caller guard.
do $do$
declare
  v_density text;
  v_seat text;
begin
  select p.prosrc into v_density
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public' and p.proname = 'get_inbox_density_per_client';
  if v_density is null or position('get_user_company_id()' in v_density) = 0 then
    raise exception 'sec_w3_harden_sentinel: get_inbox_density_per_client missing caller-scope guard';
  end if;

  select p.prosrc into v_seat
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public' and p.proname = 'remove_seated_employee';
  if v_seat is null or position('deleted_at is not null' in v_seat) = 0 then
    raise exception 'sec_w3_harden_sentinel: remove_seated_employee missing soft-deleted-target guard';
  end if;
end
$do$;

commit;
