-- SITE VISIT BOOKING RPCS — the single write path for bookings on every surface
-- (iOS, web, future MCP tools). Design: specs/2026-08-10-site-visit-booking-calendar-design.md
--
-- Actor resolution follows the complete_site_visit_guarded pattern:
-- private.get_current_user_id() / private.get_user_company_id() resolve the JWT
-- sub against users.auth_id OR users.firebase_uid (auth.uid() is unusable under
-- the Firebase bridge). Permission boundary: private.current_user_can_edit_site_visit.
--
-- Google Calendar sync is NOT enqueued here: the deployed
-- trg_site_visits_google_calendar_sync trigger enqueues create/update/delete on
-- exactly the writes these RPCs make (gated on booked_at IS NOT NULL since the
-- site_visit_booking migration).

create or replace function public.book_site_visit(
  p_opportunity_id uuid,
  p_scheduled_at timestamptz,
  p_duration_minutes int default 60,
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
  v_opp public.opportunities%rowtype;
  v_duration int := coalesce(p_duration_minutes, 60);
  v_raw_assignees text[];
  v_assignees text[];
  v_member_count int;
  v_visit_id uuid;
  v_activity_id uuid;
begin
  if p_opportunity_id is null then
    raise exception 'opportunity_id_required' using errcode = '22004';
  end if;
  if p_scheduled_at is null then
    raise exception 'scheduled_at_required' using errcode = '22004';
  end if;

  v_actor_user_id := private.get_current_user_id();
  v_company_id := private.get_user_company_id();
  if v_actor_user_id is null or v_company_id is null then
    raise exception 'site_visit_actor_not_found' using errcode = '42501';
  end if;

  -- The opportunity row lock is the booking mutex: concurrent book calls on the
  -- same lead serialize here, so the one-open-booking check below cannot race.
  select * into v_opp
    from public.opportunities
   where id = p_opportunity_id
     and deleted_at is null
   for update;
  if not found then
    raise exception 'opportunity_not_found' using errcode = 'P0002';
  end if;

  if v_opp.company_id is distinct from v_company_id then
    raise exception 'site_visit_edit_denied' using errcode = '42501';
  end if;
  if not private.current_user_can_edit_site_visit(
    v_opp.company_id::text, p_opportunity_id, null, null
  ) then
    raise exception 'site_visit_edit_denied' using errcode = '42501';
  end if;

  if p_scheduled_at <= now() - interval '5 minutes' then
    raise exception 'site_visit_time_in_past' using errcode = '22023';
  end if;
  if v_duration < 15 or v_duration > 480 then
    raise exception 'site_visit_duration_out_of_range' using errcode = '22023';
  end if;
  if p_reminder_lead_minutes is not null
     and (p_reminder_lead_minutes < 0 or p_reminder_lead_minutes > 1440) then
    raise exception 'site_visit_reminder_out_of_range' using errcode = '22023';
  end if;

  v_raw_assignees := coalesce(nullif(p_assignee_ids, '{}'::text[]), array[v_actor_user_id::text]);
  if exists (
    select 1 from unnest(v_raw_assignees) a
     where a is null or private.try_parse_uuid(a) is null
  ) then
    raise exception 'site_visit_assignees_invalid' using errcode = '22023';
  end if;
  select array_agg(distinct a order by a) into v_assignees from unnest(v_raw_assignees) a;
  select count(*) into v_member_count
    from public.users u
   where u.id::text = any(v_assignees)
     and u.company_id = v_company_id
     and u.deleted_at is null;
  if v_member_count <> array_length(v_assignees, 1) then
    raise exception 'site_visit_assignees_invalid' using errcode = '22023';
  end if;

  if exists (
    select 1 from public.site_visits sv
     where sv.opportunity_id = p_opportunity_id
       and sv.booked_at is not null
       and sv.deleted_at is null
       and sv.status = 'scheduled'
  ) then
    raise exception 'site_visit_already_booked' using errcode = '55000';
  end if;

  insert into public.site_visits (
    company_id, opportunity_id, client_id, client_ref,
    scheduled_at, duration_minutes, assignee_ids, status,
    booked_at, reminder_lead_minutes, created_by
  ) values (
    v_opp.company_id::text,
    p_opportunity_id,
    v_opp.client_id::text,
    v_opp.client_id,
    p_scheduled_at,
    v_duration,
    v_assignees,
    'scheduled',
    now(),
    p_reminder_lead_minutes,
    v_actor_user_id::text
  ) returning id into v_visit_id;

  insert into public.activities (
    company_id, opportunity_id, client_id, type, subject, content,
    duration_minutes, created_by, attachments, is_read, site_visit_id
  ) values (
    v_opp.company_id, p_opportunity_id, v_opp.client_id,
    'site_visit_scheduled', 'Site visit booked',
    to_char(p_scheduled_at at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"'),
    v_duration, v_actor_user_id, '{}'::text[], true, v_visit_id
  ) returning id into v_activity_id;

  update public.site_visits set activity_id = v_activity_id where id = v_visit_id;

  if v_opp.stage = 'new_lead' then
    perform public.move_opportunity_stage(p_opportunity_id, 'qualifying', v_actor_user_id);
  end if;

  return v_visit_id;
end;
$function$;

comment on function public.book_site_visit(uuid, timestamptz, int, text[], int) is
  'Books a site visit as a real appointment on a lead. The single booking write path for every surface (iOS, web, MCP). Side effects: timeline activity, new_lead->qualifying nudge, Google sync enqueue (via trigger).';

revoke all on function public.book_site_visit(uuid, timestamptz, int, text[], int) from public;
grant execute on function public.book_site_visit(uuid, timestamptz, int, text[], int) to anon, authenticated, service_role;

create or replace function public.reschedule_site_visit(
  p_site_visit_id uuid,
  p_scheduled_at timestamptz,
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
  if p_scheduled_at is null then
    raise exception 'scheduled_at_required' using errcode = '22004';
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

  if p_scheduled_at <= now() - interval '5 minutes' then
    raise exception 'site_visit_time_in_past' using errcode = '22023';
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
  v_changed := v_visit.scheduled_at is distinct from p_scheduled_at
    or v_visit.duration_minutes is distinct from v_new_duration
    or v_current_sorted is distinct from (select array_agg(x order by x) from unnest(coalesce(v_new_assignees, '{}'::text[])) x)
    or v_visit.reminder_lead_minutes is distinct from v_new_reminder;
  if not v_changed then
    return p_site_visit_id;
  end if;

  update public.site_visits
     set scheduled_at = p_scheduled_at,
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
    to_char(p_scheduled_at at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"'),
    v_new_duration, v_actor_user_id, '{}'::text[], true, p_site_visit_id
  );

  return p_site_visit_id;
end;
$function$;

comment on function public.reschedule_site_visit(uuid, timestamptz, int, text[], int) is
  'Moves a booked site visit. Only booked (booked_at IS NOT NULL), still-scheduled visits can move. NULL keeps a field; p_reminder_lead_minutes = -1 clears the per-booking override. The changed scheduled_at re-arms prompts by construction (dedupe keys carry the epoch). Idempotent: an identical call makes no writes.';

revoke all on function public.reschedule_site_visit(uuid, timestamptz, int, text[], int) from public;
grant execute on function public.reschedule_site_visit(uuid, timestamptz, int, text[], int) to anon, authenticated, service_role;

create or replace function public.cancel_site_visit_booking(
  p_site_visit_id uuid
) returns uuid
language plpgsql
security definer
set search_path to 'pg_catalog', 'public', 'private', 'pg_temp'
as $function$
declare
  v_actor_user_id uuid;
  v_company_id uuid;
  v_visit public.site_visits%rowtype;
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
    raise exception 'cannot_cancel_deleted_site_visit' using errcode = '55000';
  end if;
  if v_visit.booked_at is null then
    raise exception 'site_visit_not_a_booking' using errcode = '55000';
  end if;
  if v_visit.status::text = 'cancelled' then
    return p_site_visit_id;
  end if;
  if v_visit.status::text = 'completed' then
    raise exception 'cannot_cancel_completed_site_visit' using errcode = '55000';
  end if;
  if v_visit.status::text = 'in_progress' then
    raise exception 'site_visit_already_started' using errcode = '55000';
  end if;

  -- The status flip fires the Google sync trigger, which enqueues the remote
  -- delete when a calendar-scoped connection exists.
  update public.site_visits
     set status = 'cancelled'
   where id = p_site_visit_id;

  -- A cancelled booking must never materialize remotely: neutralize any
  -- still-pending create/update work the booking enqueued earlier.
  update public.google_calendar_sync_queue
     set status = 'skipped',
         skip_reason = 'booking_cancelled',
         updated_at = now()
   where site_visit_id = p_site_visit_id
     and status = 'pending'
     and operation in ('create', 'update');

  insert into public.activities (
    company_id, opportunity_id, client_id, type, subject, content,
    duration_minutes, created_by, attachments, is_read, site_visit_id
  ) values (
    v_company_id,
    v_visit.opportunity_id,
    coalesce(v_visit.client_ref, private.try_parse_uuid(v_visit.client_id)),
    'site_visit_scheduled', 'Site visit cancelled',
    to_char(v_visit.scheduled_at at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"'),
    v_visit.duration_minutes, v_actor_user_id, '{}'::text[], true, p_site_visit_id
  );

  return p_site_visit_id;
end;
$function$;

comment on function public.cancel_site_visit_booking(uuid) is
  'Cancels a booked site visit (status -> cancelled). Idempotent: cancelling a cancelled booking is a no-op success. Started/completed visits are not cancellable through the booking path. Neutralizes pending Google sync work and enqueues the remote delete via trigger.';

revoke all on function public.cancel_site_visit_booking(uuid) from public;
grant execute on function public.cancel_site_visit_booking(uuid) to anon, authenticated, service_role;
