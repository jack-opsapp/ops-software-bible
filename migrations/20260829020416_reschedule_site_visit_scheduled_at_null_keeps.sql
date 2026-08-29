-- reschedule_site_visit: p_scheduled_at becomes optional — NULL (or an omitted
-- arg) keeps the stored time, matching the NULL-keeps grammar the function
-- already gives duration / assignees / reminder, the documented client
-- contract (bible 04_API), and the iOS wire encoding (unchanged fields are
-- omitted). Before this, a crew/duration/heads-up-only reschedule omitted
-- p_scheduled_at and PostgREST could not resolve the function at all.
-- The past-time guard now runs only when the time actually moves, so a
-- crew-only edit to a visit already inside its window still lands.
create or replace function public.reschedule_site_visit(
  p_site_visit_id uuid,
  p_scheduled_at timestamptz default null,
  p_duration_minutes int default null,
  p_assignee_ids text[] default null,
  p_reminder_lead_minutes int default null
) returns uuid
language plpgsql
security definer
set search_path to 'pg_catalog', 'public', 'private', 'pg_temp'
as $function$
declare
  v_actor_user_id uuid;
  v_company_id uuid;
  v_visit public.site_visits%rowtype;
  v_new_scheduled timestamptz;
  v_new_duration int;
  v_new_reminder int;
  v_raw_assignees text[];
  v_new_assignees text[];
  v_current_sorted text[];
  v_member_count int;
  v_changed boolean;
begin
  if p_site_visit_id is null then
    raise exception 'site_visit_id_required' using errcode = '22004';
  end if;

  v_actor_user_id := private.get_current_user_id();
  v_company_id := private.get_user_company_id();
  if v_actor_user_id is null or v_company_id is null then
    raise exception 'site_visit_actor_not_found' using errcode = '42501';
  end if;

  select * into v_visit
    from public.site_visits
   where id = p_site_visit_id
   for update;
  if not found then
    raise exception 'site_visit_not_found' using errcode = 'P0002';
  end if;

  if not private.current_user_can_edit_site_visit(
    v_visit.company_id, v_visit.opportunity_id, v_visit.project_id, v_visit.project_ref
  ) then
    raise exception 'site_visit_edit_denied' using errcode = '42501';
  end if;
  if private.try_parse_uuid(v_visit.company_id) is distinct from v_company_id then
    raise exception 'site_visit_company_mismatch' using errcode = '42501';
  end if;
  if v_visit.deleted_at is not null then
    raise exception 'cannot_reschedule_deleted_site_visit' using errcode = '55000';
  end if;
  if v_visit.booked_at is null then
    raise exception 'site_visit_not_a_booking' using errcode = '55000';
  end if;
  if v_visit.status::text <> 'scheduled' then
    raise exception 'site_visit_not_reschedulable' using errcode = '55000';
  end if;

  -- NULL / same time = keep, and the past-time rule only judges a real move.
  if p_scheduled_at is null or p_scheduled_at = v_visit.scheduled_at then
    v_new_scheduled := v_visit.scheduled_at;
  else
    if p_scheduled_at <= now() - interval '5 minutes' then
      raise exception 'site_visit_time_in_past' using errcode = '22023';
    end if;
    v_new_scheduled := p_scheduled_at;
  end if;

  v_new_duration := coalesce(p_duration_minutes, v_visit.duration_minutes);
  if v_new_duration < 15 or v_new_duration > 480 then
    raise exception 'site_visit_duration_out_of_range' using errcode = '22023';
  end if;

  -- Reminder override semantics: NULL = keep, -1 = clear back to the user default,
  -- 0..1440 = set. Documented for iOS/web/MCP callers.
  if p_reminder_lead_minutes is null then
    v_new_reminder := v_visit.reminder_lead_minutes;
  elsif p_reminder_lead_minutes = -1 then
    v_new_reminder := null;
  elsif p_reminder_lead_minutes between 0 and 1440 then
    v_new_reminder := p_reminder_lead_minutes;
  else
    raise exception 'site_visit_reminder_out_of_range' using errcode = '22023';
  end if;

  if p_assignee_ids is null or p_assignee_ids = '{}'::text[] then
    v_new_assignees := v_visit.assignee_ids;
  else
    v_raw_assignees := p_assignee_ids;
    if exists (
      select 1 from unnest(v_raw_assignees) a
       where a is null or private.try_parse_uuid(a) is null
    ) then
      raise exception 'site_visit_assignees_invalid' using errcode = '22023';
    end if;
    select array_agg(distinct a order by a) into v_new_assignees from unnest(v_raw_assignees) a;
    select count(*) into v_member_count
      from public.users u
     where u.id::text = any(v_new_assignees)
       and u.company_id = v_company_id
       and u.deleted_at is null;
    if v_member_count <> array_length(v_new_assignees, 1) then
      raise exception 'site_visit_assignees_invalid' using errcode = '22023';
    end if;
  end if;

  select array_agg(x order by x) into v_current_sorted from unnest(coalesce(v_visit.assignee_ids, '{}'::text[])) x;
  v_changed := v_visit.scheduled_at is distinct from v_new_scheduled
    or v_visit.duration_minutes is distinct from v_new_duration
    or v_current_sorted is distinct from (select array_agg(x order by x) from unnest(coalesce(v_new_assignees, '{}'::text[])) x)
    or v_visit.reminder_lead_minutes is distinct from v_new_reminder;
  if not v_changed then
    return p_site_visit_id;
  end if;

  update public.site_visits
     set scheduled_at = v_new_scheduled,
         duration_minutes = v_new_duration,
         assignee_ids = v_new_assignees,
         reminder_lead_minutes = v_new_reminder
   where id = p_site_visit_id;

  insert into public.activities (
    company_id, opportunity_id, client_id, type, subject, content,
    duration_minutes, created_by, attachments, is_read, site_visit_id
  ) values (
    v_company_id,
    v_visit.opportunity_id,
    coalesce(v_visit.client_ref, private.try_parse_uuid(v_visit.client_id)),
    'site_visit_scheduled', 'Site visit rescheduled',
    to_char(v_new_scheduled at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"'),
    v_new_duration, v_actor_user_id, '{}'::text[], true, p_site_visit_id
  );

  return p_site_visit_id;
end;
$function$;
