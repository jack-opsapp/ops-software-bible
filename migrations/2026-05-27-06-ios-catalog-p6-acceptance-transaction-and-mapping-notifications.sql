-- iOS Catalog Phase 6 authenticated acceptance transaction and keyed
-- missing-mapping notification persistence. Review-gate draft only. Do not
-- apply without explicit PM approval.
--
-- This migration exposes public.accept_estimate_to_job as SECURITY INVOKER so
-- live auth/RLS remains authoritative. It calls the P6-3 project/task sync
-- helper and the P6-5 booking projection helper in the same database
-- transaction, derives the actor server-side, and persists mapping warnings
-- only from the P6-5 returned missing_mappings array.

begin;

do $$
begin
  if to_regprocedure('private.sync_accepted_estimate_project_tasks(uuid)') is null then
    raise exception 'p6_3_project_task_sync_helper_required'
      using errcode = '42883';
  end if;

  if to_regprocedure('private.persist_estimate_material_booking_projection(uuid, uuid)') is null then
    raise exception 'p6_5_booking_projection_helper_required'
      using errcode = '42883';
  end if;

  if to_regprocedure('private.try_parse_uuid(text)') is null then
    raise exception 'p6_4_try_parse_uuid_required'
      using errcode = '42883';
  end if;

  if to_regprocedure('public.users_with_permission(uuid, text, text)') is null then
    raise exception 'users_with_permission_required'
      using errcode = '42883';
  end if;

  if exists (
    select 1
      from pg_proc proc_row
      join pg_namespace namespace_row
        on namespace_row.oid = proc_row.pronamespace
     where namespace_row.nspname = 'private'
       and proc_row.proname in (
         'sync_accepted_estimate_project_tasks',
         'persist_estimate_material_booking_projection'
       )
       and proc_row.prosecdef
  ) then
    raise exception 'p6_acceptance_helpers_must_be_security_invoker'
      using errcode = '42501';
  end if;

  if not exists (
    select 1
      from pg_policies policy_row
     where policy_row.schemaname = 'public'
       and policy_row.tablename = 'project_tasks'
       and policy_row.cmd = 'UPDATE'
       and coalesce(policy_row.qual, '') like '%tasks.edit%'
  ) then
    raise exception 'project_tasks_tasks_edit_update_policy_required'
      using errcode = '42501';
  end if;

  if not exists (
    select 1
      from information_schema.columns column_row
     where column_row.table_schema = 'public'
       and column_row.table_name = 'notifications'
       and column_row.column_name = 'dedupe_key'
  ) then
    raise exception 'p6_2_notification_dedupe_key_required'
      using errcode = '42703';
  end if;

  if not exists (
    select 1
      from information_schema.columns column_row
     where column_row.table_schema = 'public'
       and column_row.table_name = 'notifications'
       and column_row.column_name = 'resolved_at'
  ) then
    raise exception 'p6_2_notification_resolved_at_required'
      using errcode = '42703';
  end if;

  if not exists (
    select 1
      from information_schema.columns column_row
     where column_row.table_schema = 'public'
       and column_row.table_name = 'notifications'
       and column_row.column_name = 'resolved_by'
  ) then
    raise exception 'p6_2_notification_resolved_by_required'
      using errcode = '42703';
  end if;

  if not exists (
    select 1
      from information_schema.columns column_row
     where column_row.table_schema = 'public'
       and column_row.table_name = 'notifications'
       and column_row.column_name = 'resolution_reason'
  ) then
    raise exception 'p6_2_notification_resolution_reason_required'
      using errcode = '42703';
  end if;

  if not exists (
    select 1
      from pg_indexes index_row
     where index_row.schemaname = 'public'
       and index_row.tablename = 'notifications'
       and index_row.indexname = 'notifications_open_dedupe_key'
       and index_row.indexdef like '%dedupe_key%'
       and index_row.indexdef like '%resolved_at IS NULL%'
  ) then
    raise exception 'p6_2_notification_open_dedupe_index_required'
      using errcode = '42P07';
  end if;
end;
$$;

create table if not exists public.accept_estimate_to_job_requests (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  estimate_id uuid not null references public.estimates(id) on delete cascade,
  idempotency_key text not null,
  status text not null default 'in_progress',
  response jsonb,
  error_code text,
  created_by uuid not null references public.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint accept_estimate_to_job_requests_key_not_blank
    check (btrim(idempotency_key) <> ''),
  constraint accept_estimate_to_job_requests_key_length
    check (char_length(idempotency_key) <= 200),
  constraint accept_estimate_to_job_requests_status_check
    check (status in ('in_progress', 'completed'))
);

create unique index if not exists accept_estimate_to_job_requests_idempotency_key
  on public.accept_estimate_to_job_requests(company_id, estimate_id, idempotency_key);

create index if not exists accept_estimate_to_job_requests_actor_idx
  on public.accept_estimate_to_job_requests(company_id, created_by, created_at desc);

create or replace function public.accept_estimate_to_job_requests_write_guard()
returns trigger
language plpgsql
security invoker
set search_path to 'public', 'private', 'pg_temp'
as $$
begin
  if coalesce(current_setting('ops.accept_estimate_to_job_rpc', true), '') <> 'on' then
    raise exception 'accept_estimate_to_job_requests can only be changed by accept_estimate_to_job'
      using errcode = '42501';
  end if;

  if tg_op in ('INSERT', 'UPDATE') then
    if new.company_id is distinct from private.get_user_company_id() then
      raise exception 'acceptance_request_company_scope_mismatch'
        using errcode = '42501';
    end if;

    if new.created_by is distinct from private.get_current_user_id() then
      raise exception 'acceptance_request_actor_mismatch'
        using errcode = '42501';
    end if;

    new.updated_at := now();
    return new;
  end if;

  return old;
end;
$$;

drop trigger if exists trg_accept_estimate_to_job_requests_write_guard
  on public.accept_estimate_to_job_requests;
create trigger trg_accept_estimate_to_job_requests_write_guard
  before insert or update or delete on public.accept_estimate_to_job_requests
  for each row
  execute function public.accept_estimate_to_job_requests_write_guard();

alter table public.accept_estimate_to_job_requests enable row level security;

drop policy if exists accept_estimate_to_job_requests_select_actor
  on public.accept_estimate_to_job_requests;
create policy accept_estimate_to_job_requests_select_actor
  on public.accept_estimate_to_job_requests
  for select
  using (
    company_id = (select private.get_user_company_id())
    and created_by = (select private.get_current_user_id())
  );

drop policy if exists accept_estimate_to_job_requests_insert_actor
  on public.accept_estimate_to_job_requests;
create policy accept_estimate_to_job_requests_insert_actor
  on public.accept_estimate_to_job_requests
  for insert
  with check (
    company_id = (select private.get_user_company_id())
    and created_by = (select private.get_current_user_id())
  );

drop policy if exists accept_estimate_to_job_requests_update_actor
  on public.accept_estimate_to_job_requests;
create policy accept_estimate_to_job_requests_update_actor
  on public.accept_estimate_to_job_requests
  for update
  using (
    company_id = (select private.get_user_company_id())
    and created_by = (select private.get_current_user_id())
  )
  with check (
    company_id = (select private.get_user_company_id())
    and created_by = (select private.get_current_user_id())
  );

revoke all on table public.accept_estimate_to_job_requests from public;
revoke all on table public.accept_estimate_to_job_requests from anon;
revoke all on table public.accept_estimate_to_job_requests from authenticated;
grant select, insert, update on table public.accept_estimate_to_job_requests to authenticated;

create or replace function private.persist_catalog_mapping_notifications_from_missing_mappings(
  p_company_id uuid,
  p_missing_mappings jsonb
)
returns jsonb
language plpgsql
security invoker
set search_path to 'public', 'private', 'pg_temp'
as $$
declare
  v_now timestamptz := now();
  v_mapping record;
  v_recipient uuid;
  v_inserted_count integer := 0;
  v_updated_count integer := 0;
  v_recipient_count integer := 0;
  v_dedupe_keys text[] := '{}'::text[];
  v_action_url text;
  v_was_inserted boolean;
begin
  if p_company_id is null then
    raise exception 'company_id_required' using errcode = '22023';
  end if;

  if p_company_id is distinct from private.get_user_company_id() then
    raise exception 'notification_company_scope_mismatch'
      using errcode = '42501';
  end if;

  if jsonb_typeof(coalesce(p_missing_mappings, '[]'::jsonb)) <> 'array' then
    raise exception 'missing_mappings_array_required'
      using errcode = '23514';
  end if;

  for v_mapping in
    select distinct on (nullif(mapping_item.value ->> 'dedupe_key', ''))
      nullif(mapping_item.value ->> 'dedupe_key', '') as dedupe_key,
      mapping_item.value as payload
    from jsonb_array_elements(coalesce(p_missing_mappings, '[]'::jsonb)) as mapping_item(value)
    where nullif(mapping_item.value ->> 'dedupe_key', '') is not null
    order by nullif(mapping_item.value ->> 'dedupe_key', ''), mapping_item.value::text
  loop
    v_dedupe_keys := array_append(v_dedupe_keys, v_mapping.dedupe_key);
    v_action_url := 'ops://catalog/setup?missingMapping=' || v_mapping.dedupe_key;

    for v_recipient in
      select permission_user.permission_user_id
        from public.users_with_permission(p_company_id, 'catalog.manage', 'all')
          as permission_user(permission_user_id)
    loop
      v_recipient_count := v_recipient_count + 1;

      with upserted_notification as (
        insert into public.notifications (
          id,
          user_id,
          company_id,
          type,
          title,
          body,
          project_id,
          note_id,
          is_read,
          created_at,
          deep_link_type,
          persistent,
          action_url,
          action_label,
          dedupe_key,
          resolved_at,
          resolved_by,
          resolution_reason
        ) values (
          gen_random_uuid(),
          v_recipient::text,
          p_company_id::text,
          'catalog_mapping_needed',
          'Stock mapping needed',
          'Map this product before the next booked job.',
          null,
          null,
          false,
          v_now,
          'catalogSetup',
          true,
          v_action_url,
          'FIX MAPPING',
          v_mapping.dedupe_key,
          null,
          null,
          null
        )
        on conflict (user_id, company_id, type, dedupe_key)
          where is_read = false
            and resolved_at is null
            and dedupe_key is not null
        do update
          set body = excluded.body,
              is_read = false,
              persistent = true,
              action_url = excluded.action_url,
              action_label = excluded.action_label,
              resolved_at = null,
              resolved_by = null,
              resolution_reason = null
        returning (xmax = 0) as inserted
      )
      select upserted_notification.inserted
        into v_was_inserted
        from upserted_notification;

      if v_was_inserted then
        v_inserted_count := v_inserted_count + 1;
      else
        v_updated_count := v_updated_count + 1;
      end if;
    end loop;
  end loop;

  return jsonb_build_object(
    'notification_persistence_performed', true,
    'dedupe_keys', to_jsonb(v_dedupe_keys),
    'recipient_count', v_recipient_count,
    'inserted_notification_count', v_inserted_count,
    'updated_notification_count', v_updated_count
  );
end;
$$;

revoke all on function private.persist_catalog_mapping_notifications_from_missing_mappings(uuid, jsonb)
  from public, anon, authenticated, service_role;
grant execute on function private.persist_catalog_mapping_notifications_from_missing_mappings(uuid, jsonb)
  to authenticated;

create or replace function public.accept_estimate_to_job(
  p_estimate_id uuid,
  p_idempotency_key text
)
returns jsonb
language plpgsql
security invoker
set search_path to 'public', 'private', 'pg_temp'
as $$
declare
  v_now timestamptz := now();
  v_actor_user_id uuid;
  v_actor_company_id uuid;
  v_tasks_edit_scope text;
  v_estimate_company_id uuid;
  v_request_status text;
  v_request_response jsonb;
  v_project_result jsonb;
  v_booking_result jsonb;
  v_notification_result jsonb;
  v_project_id uuid;
  v_missing_mappings jsonb := '[]'::jsonb;
  v_response jsonb;
begin
  if p_estimate_id is null then
    raise exception 'estimate_id_required' using errcode = '22023';
  end if;

  if nullif(btrim(coalesce(p_idempotency_key, '')), '') is null then
    raise exception 'idempotency_key_required' using errcode = '22023';
  end if;

  if char_length(p_idempotency_key) > 200 then
    raise exception 'idempotency_key_too_long' using errcode = '22023';
  end if;

  v_actor_user_id := private.get_current_user_id();
  v_actor_company_id := private.get_user_company_id();

  if v_actor_user_id is null or v_actor_company_id is null then
    raise exception 'actor_not_found' using errcode = '42501';
  end if;

  v_tasks_edit_scope := private.current_user_scope_for('tasks.edit');
  if not private.current_user_is_admin()
     and coalesce(v_tasks_edit_scope, '') not in ('all', 'assigned') then
    raise exception 'tasks_edit_required' using errcode = '42501';
  end if;

  select estimate_row.company_id
    into v_estimate_company_id
    from public.estimates estimate_row
   where estimate_row.id = p_estimate_id
     and estimate_row.deleted_at is null
   for update;

  if not found then
    raise exception 'estimate_not_found' using errcode = 'P0002';
  end if;

  if v_estimate_company_id is distinct from v_actor_company_id then
    raise exception 'estimate_company_scope_mismatch'
      using errcode = '42501';
  end if;

  perform set_config('ops.accept_estimate_to_job_rpc', 'on', true);

  insert into public.accept_estimate_to_job_requests (
    company_id,
    estimate_id,
    idempotency_key,
    status,
    response,
    error_code,
    created_by,
    created_at,
    updated_at
  ) values (
    v_actor_company_id,
    p_estimate_id,
    btrim(p_idempotency_key),
    'in_progress',
    null,
    null,
    v_actor_user_id,
    v_now,
    v_now
  )
  on conflict (company_id, estimate_id, idempotency_key)
  do update
    set updated_at = v_now
  returning status, response
    into v_request_status, v_request_response;

  if v_request_status = 'completed' and v_request_response is not null then
    return v_request_response || jsonb_build_object(
      'idempotent_replay', true
    );
  end if;

  v_project_result := private.sync_accepted_estimate_project_tasks(p_estimate_id);
  v_project_id := private.try_parse_uuid(v_project_result ->> 'project_id');

  if v_project_id is null then
    raise exception 'accepted_project_id_missing'
      using errcode = '23514';
  end if;

  v_booking_result := private.persist_estimate_material_booking_projection(
    p_estimate_id,
    v_project_id
  );

  v_missing_mappings := coalesce(v_booking_result -> 'missing_mappings', '[]'::jsonb);

  if jsonb_typeof(v_missing_mappings) <> 'array' then
    raise exception 'booking_missing_mappings_array_required'
      using errcode = '23514';
  end if;

  v_notification_result :=
    private.persist_catalog_mapping_notifications_from_missing_mappings(
      v_actor_company_id,
      v_missing_mappings
    );

  v_response := jsonb_build_object(
    'ok', true,
    'estimate_id', p_estimate_id,
    'project_id', v_project_id,
    'actor_user_id', v_actor_user_id,
    'company_id', v_actor_company_id,
    'idempotency_key', btrim(p_idempotency_key),
    'idempotent_replay', false,
    'project_task_result', v_project_result,
    'booking_projection_result', v_booking_result,
    'mapping_notification_result', v_notification_result,
    'inventory_mode', coalesce(v_booking_result ->> 'inventory_mode', 'off'),
    'warnings', coalesce(v_booking_result -> 'warnings', '[]'::jsonb),
    'overruns', coalesce(v_booking_result -> 'overruns', '[]'::jsonb),
    'missing_mappings', v_missing_mappings,
    'demand_ids', coalesce(v_booking_result -> 'demand_ids', '[]'::jsonb),
    'accepted_at', v_now
  );

  update public.accept_estimate_to_job_requests request_row
     set status = 'completed',
         response = v_response,
         error_code = null,
         updated_at = v_now
   where request_row.company_id = v_actor_company_id
     and request_row.estimate_id = p_estimate_id
     and request_row.idempotency_key = btrim(p_idempotency_key)
     and request_row.created_by = v_actor_user_id;

  return v_response;
end;
$$;

revoke all on function public.accept_estimate_to_job(uuid, text)
  from public, anon, authenticated, service_role;
grant execute on function public.accept_estimate_to_job(uuid, text)
  to authenticated;

comment on function public.accept_estimate_to_job(uuid, text)
  is 'Phase 6 estimate acceptance transaction. Runs as the authenticated caller, derives actor and company server-side, calls P6 project/task sync and booking projection helpers, persists keyed missing-mapping notifications from the booking result only, and performs no physical stock deduction.';

revoke all on function public.accept_estimate_to_job_requests_write_guard()
  from public, anon, authenticated, service_role;

commit;
