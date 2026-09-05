-- Scopes ride the task-creation RPCs in the same transaction.
--   * create_task_with_event: p_payload gains an optional "scopes" array of
--     {id?, task_type_id, note?, display_order?, source_line_item_id?}. Absent/null/[]
--     ⇒ exactly today's behavior. First scope's task_type_id must equal the task's
--     task_type_id (scope_primary_mismatch, 23514). Only a freshly inserted task takes
--     scopes, so an idempotent retry never duplicates rows.
--   * create_task_with_event_as_system: trailing optional p_scopes jsonb (old 11-arg
--     signature dropped and recreated with the 12th defaulted param; grants restored to
--     service_role only — Supabase default privileges would otherwise add anon/authenticated).
create or replace function private.insert_task_scopes(p_task_id uuid, p_company_id uuid, p_task_type_id uuid, p_scopes jsonb) returns integer
language plpgsql security definer set search_path to 'pg_catalog', 'public', 'private', 'pg_temp' as $$
declare v_count integer := 0; v_elem jsonb; v_idx integer := 0; v_scope_id uuid; v_scope_type uuid; v_display_order integer;
begin
  if p_scopes is null or jsonb_typeof(p_scopes) = 'null' then return 0; end if;
  if jsonb_typeof(p_scopes) <> 'array' then raise exception 'invalid_task_payload' using errcode = '22023'; end if;
  for v_elem in select value from jsonb_array_elements(p_scopes) loop
    if jsonb_typeof(v_elem) <> 'object'
       or exists (select 1 from jsonb_object_keys(v_elem) as k(key_name) where not (key_name = any(array['id','task_type_id','note','display_order','source_line_item_id']::text[])))
       or nullif(v_elem ->> 'task_type_id', '') is null then
      raise exception 'invalid_task_payload' using errcode = '22023';
    end if;
    begin
      v_scope_type := (v_elem ->> 'task_type_id')::uuid;
      v_scope_id := coalesce(nullif(v_elem ->> 'id', '')::uuid, gen_random_uuid());
      v_display_order := coalesce((v_elem ->> 'display_order')::integer, v_idx);
    exception when invalid_text_representation or numeric_value_out_of_range then
      raise exception 'invalid_task_payload' using errcode = '22023';
    end;
    if v_idx = 0 and v_scope_type is distinct from p_task_type_id then raise exception 'scope_primary_mismatch' using errcode = '23514'; end if;
    if v_display_order < 0 then raise exception 'invalid_task_payload' using errcode = '22023'; end if;
    insert into public.task_scopes (id, company_id, task_id, task_type_id, note, display_order, source_line_item_id)
    values (v_scope_id, p_company_id, p_task_id, v_scope_type, nullif(btrim(v_elem ->> 'note'), ''), v_display_order, nullif(btrim(v_elem ->> 'source_line_item_id'), ''));
    v_count := v_count + 1; v_idx := v_idx + 1;
  end loop;
  return v_count;
end; $$;
revoke all on function private.insert_task_scopes(uuid, uuid, uuid, jsonb) from public, anon, authenticated;

create or replace function private.create_task_with_event_for_actor(p_actor_user_id uuid, p_task_id uuid, p_project_id uuid, p_task_type_id uuid, p_payload jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'pg_catalog', 'public', 'private', 'pg_temp' AS $function$
declare
  v_company_id uuid; v_payload jsonb := coalesce(p_payload, '{}'::jsonb); v_status text; v_task_color text; v_task_notes text; v_custom_title text;
  v_team_member_ids uuid[] := array[]::uuid[]; v_team_member_text text[] := array[]::text[]; v_dependency_overrides jsonb;
  v_start_date timestamptz; v_end_date timestamptz; v_duration integer; v_start_time time without time zone; v_end_time time without time zone;
  v_start_time_text text; v_end_time_text text; v_all_day boolean; v_recurrence_id uuid; v_recurrence_origin_date date; v_display_order integer;
  v_existing public.project_tasks; v_previous_actor text := current_setting('ops.task_mutation_actor_id', true); v_inserted_count integer := 0; v_scope_count integer := 0;
begin
  if jsonb_typeof(v_payload) is distinct from 'object'
     or exists (select 1 from jsonb_object_keys(v_payload) as payload_keys(key_name) where not (key_name = any(array['status','task_color','task_notes','custom_title','team_member_ids','dependency_overrides','start_date','end_date','duration','start_time','end_time','all_day','recurrence_id','recurrence_origin_date','display_order','scopes']::text[]))) then
    raise exception 'invalid_task_payload' using errcode = '22023';
  end if;
  if v_payload ? 'scopes' and jsonb_typeof(v_payload -> 'scopes') not in ('array', 'null') then
    raise exception 'invalid_task_payload' using errcode = '22023';
  end if;
  begin
    if v_payload ? 'team_member_ids' then
      if jsonb_typeof(v_payload -> 'team_member_ids') is distinct from 'array' then raise exception 'invalid_task_payload' using errcode = '22023'; end if;
      select coalesce(array_agg(member_id::uuid order by member_id::uuid), array[]::uuid[]) into v_team_member_ids from jsonb_array_elements_text(v_payload -> 'team_member_ids') member(member_id);
    end if;
    v_team_member_text := array(select member_id::text from unnest(v_team_member_ids) member_id order by member_id);
    v_status := coalesce(v_payload ->> 'status', 'active');
    v_task_color := coalesce(nullif(btrim(v_payload ->> 'task_color'), ''), '#417394');
    v_task_notes := v_payload ->> 'task_notes';
    v_custom_title := nullif(btrim(v_payload ->> 'custom_title'), '');
    v_dependency_overrides := case when v_payload ? 'dependency_overrides' and jsonb_typeof(v_payload -> 'dependency_overrides') <> 'null' then v_payload -> 'dependency_overrides' else null end;
    v_start_date := case when nullif(v_payload ->> 'start_date', '') is null then null else (v_payload ->> 'start_date')::timestamptz end;
    v_end_date := case when nullif(v_payload ->> 'end_date', '') is null then null else (v_payload ->> 'end_date')::timestamptz end;
    v_duration := coalesce((v_payload ->> 'duration')::integer, 1);
    v_start_time_text := nullif(btrim(v_payload ->> 'start_time'), '');
    v_end_time_text := nullif(btrim(v_payload ->> 'end_time'), '');
    if (v_start_time_text is not null and v_start_time_text !~ '^([01][0-9]|2[0-3]):[0-5][0-9](:[0-5][0-9])?$')
       or (v_end_time_text is not null and v_end_time_text !~ '^([01][0-9]|2[0-3]):[0-5][0-9](:[0-5][0-9])?$') then
      raise exception 'invalid_task_payload' using errcode = '22023';
    end if;
    v_start_time := v_start_time_text::time; v_end_time := v_end_time_text::time;
    v_all_day := coalesce((v_payload ->> 'all_day')::boolean, true);
    v_recurrence_id := nullif(v_payload ->> 'recurrence_id', '')::uuid;
    v_recurrence_origin_date := nullif(v_payload ->> 'recurrence_origin_date', '')::date;
    v_display_order := coalesce((v_payload ->> 'display_order')::integer, 0);
  exception when invalid_text_representation or numeric_value_out_of_range or invalid_datetime_format or datetime_field_overflow then
    raise exception 'invalid_task_payload' using errcode = '22023';
  end;
  if p_actor_user_id is null or p_task_id is null or p_project_id is null or p_task_type_id is null
     or v_status not in ('active', 'completed', 'cancelled') or v_duration < 1 or v_display_order < 0
     or (v_end_date is not null and v_start_date is null) or (v_end_date is not null and v_end_date < v_start_date)
     or (v_recurrence_origin_date is not null and v_recurrence_id is null)
     or (v_dependency_overrides is not null and jsonb_typeof(v_dependency_overrides) <> 'array')
     or cardinality(v_team_member_ids) <> (select count(distinct member_id) from unnest(v_team_member_ids) member(member_id)) then
    raise exception 'invalid_task_payload' using errcode = '22023';
  end if;
  select actor.company_id into v_company_id from public.users actor where actor.id = p_actor_user_id and actor.deleted_at is null and coalesce(actor.is_active, false);
  if not found then raise exception 'task_create_forbidden' using errcode = '42501'; end if;
  perform private.lock_lead_assignment_company(v_company_id);
  if not exists (select 1 from public.users actor where actor.id = p_actor_user_id and actor.company_id = v_company_id and actor.deleted_at is null and coalesce(actor.is_active, false))
     or not public.has_permission(p_actor_user_id, 'tasks.create', 'all') then
    raise exception 'task_create_forbidden' using errcode = '42501';
  end if;
  if cardinality(v_team_member_ids) > 0 and not public.has_permission(p_actor_user_id, 'tasks.assign', 'all') then raise exception 'task_assignment_forbidden' using errcode = '42501'; end if;
  if v_status <> 'active' and not public.has_permission(p_actor_user_id, 'tasks.change_status', 'all') then raise exception 'task_status_forbidden' using errcode = '42501'; end if;
  perform 1 from public.projects project where project.id = p_project_id and project.company_id = v_company_id and project.deleted_at is null for share;
  if not found then raise exception 'invalid_task_project' using errcode = '22023'; end if;
  perform 1 from public.task_types task_type where task_type.id = p_task_type_id and task_type.company_id = v_company_id and task_type.deleted_at is null for share;
  if not found then raise exception 'invalid_task_type' using errcode = '22023'; end if;
  if v_recurrence_id is not null and not exists (select 1 from public.task_recurrences recurrence where recurrence.id = v_recurrence_id and recurrence.company_id = v_company_id and recurrence.project_id = p_project_id and recurrence.deleted_at is null) then
    raise exception 'invalid_task_recurrence' using errcode = '22023';
  end if;
  if (select count(*) from public.users member where member.id = any(v_team_member_ids) and member.company_id = v_company_id and member.deleted_at is null and coalesce(member.is_active, false)) <> cardinality(v_team_member_ids) then
    raise exception 'invalid_task_team' using errcode = '22023';
  end if;
  perform set_config('ops.task_mutation_actor_id', p_actor_user_id::text, true);
  begin
    insert into public.project_tasks (id, company_id, project_id, task_type_id, custom_title, task_notes, task_color, team_member_ids, dependency_overrides, status, start_date, end_date, duration, start_time, end_time, all_day, recurrence_id, recurrence_origin_date, display_order)
    values (p_task_id, v_company_id, p_project_id, p_task_type_id, v_custom_title, v_task_notes, v_task_color, v_team_member_text, v_dependency_overrides, v_status, v_start_date, v_end_date, v_duration, v_start_time, v_end_time, v_all_day, v_recurrence_id, v_recurrence_origin_date, v_display_order)
    on conflict (id) do nothing;
    get diagnostics v_inserted_count = row_count;
    select task.* into v_existing from public.project_tasks task where task.id = p_task_id for share;
    if not found or v_existing.deleted_at is not null or v_existing.company_id is distinct from v_company_id or v_existing.project_id is distinct from p_project_id
       or v_existing.task_type_id is distinct from p_task_type_id or v_existing.custom_title is distinct from v_custom_title or v_existing.task_notes is distinct from v_task_notes
       or v_existing.task_color is distinct from v_task_color
       or array(select distinct member_id from unnest(coalesce(v_existing.team_member_ids, array[]::text[])) member_id order by member_id) is distinct from v_team_member_text
       or v_existing.dependency_overrides is distinct from v_dependency_overrides or v_existing.status is distinct from v_status or v_existing.start_date is distinct from v_start_date
       or v_existing.end_date is distinct from v_end_date or v_existing.duration is distinct from v_duration or v_existing.start_time is distinct from v_start_time
       or v_existing.end_time is distinct from v_end_time or v_existing.all_day is distinct from v_all_day or v_existing.recurrence_id is distinct from v_recurrence_id
       or v_existing.recurrence_origin_date is distinct from v_recurrence_origin_date or v_existing.display_order is distinct from v_display_order then
      raise exception 'task_id_conflict' using errcode = '23505';
    end if;
    if v_inserted_count = 1 and v_payload ? 'scopes' then
      v_scope_count := private.insert_task_scopes(p_task_id, v_company_id, p_task_type_id, v_payload -> 'scopes');
    end if;
  exception when others then
    perform set_config('ops.task_mutation_actor_id', coalesce(v_previous_actor, ''), true);
    raise;
  end;
  perform set_config('ops.task_mutation_actor_id', coalesce(v_previous_actor, ''), true);
  return jsonb_build_object('task_id', p_task_id, 'created', v_inserted_count = 1, 'schedule_version', v_existing.schedule_version, 'updated_at', v_existing.updated_at, 'scope_count', v_scope_count);
end; $function$;

drop function public.create_task_with_event_as_system(uuid, uuid, uuid, uuid, text, text, text, uuid[], timestamptz, timestamptz, integer);
create or replace function public.create_task_with_event_as_system(p_actor_user_id uuid, p_task_id uuid, p_project_id uuid, p_task_type_id uuid, p_custom_title text, p_task_notes text default null, p_task_color text default null, p_team_member_ids uuid[] default array[]::uuid[], p_start_date timestamptz default null, p_end_date timestamptz default null, p_duration integer default 1, p_scopes jsonb default null)
 returns jsonb language plpgsql security definer set search_path to 'pg_catalog', 'public', 'private', 'pg_temp' as $function$
begin
  if auth.role() is distinct from 'service_role' then raise exception 'access_denied' using errcode = '42501'; end if;
  return private.create_task_with_event_for_actor(p_actor_user_id, p_task_id, p_project_id, p_task_type_id,
    jsonb_build_object('custom_title', p_custom_title, 'task_notes', p_task_notes, 'task_color', p_task_color, 'team_member_ids', to_jsonb(coalesce(p_team_member_ids, array[]::uuid[])),
      'start_date', p_start_date, 'end_date', p_end_date, 'duration', p_duration, 'status', 'active', 'all_day', true, 'display_order', 0)
    || case when p_scopes is null then '{}'::jsonb else jsonb_build_object('scopes', p_scopes) end);
end; $function$;
revoke all on function public.create_task_with_event_as_system(uuid, uuid, uuid, uuid, text, text, text, uuid[], timestamptz, timestamptz, integer, jsonb) from public, anon, authenticated;
grant execute on function public.create_task_with_event_as_system(uuid, uuid, uuid, uuid, text, text, text, uuid[], timestamptz, timestamptz, integer, jsonb) to service_role;
notify pgrst, 'reload schema';
