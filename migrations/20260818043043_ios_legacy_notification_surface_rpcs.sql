-- iOS legacy notification-surface RPCs (bug e302355c ADDENDUM: the ~25
-- createNotification call sites from feature work landed after the
-- origin/main audit).
--
-- 20260715180500_notification_creation_hardening revoked app-role INSERT on
-- public.notifications. 20260818023254_ios_notification_surface_rpcs rewired
-- the twelve audited iOS surfaces; this migration adds the sanctioned surface
-- for the twenty-nine call sites the audit's ADDENDUM catalogued — task and
-- project lifecycle fan-outs, vinyl order confirmations, guided-setup
-- completions, team management, the time-off REQUEST side, inventory
-- threshold alerts, the photo-storage cap banner, the billable-week nudge,
-- and the cashflow dip rail. One narrow RPC per surface shape.
--
-- Doctrine (mirrors 20260818023254 + request_lockout_admin_notification):
--   * actor identity from private.get_current_user_id(); company from the
--     actor's row; neither is expressible via inputs.
--   * recipients derived server-side — from task/project/event/invitation/
--     stock-unit/inventory rows or public.users_with_permission — never from
--     raw caller input. Where a caller passes an id list (delta assignment
--     notifications), the list may only SUBSET the anchor row's recorded
--     membership.
--   * copy is FIXED server-side, byte-parity with the shipped client
--     strings; the only caller data that reaches a row is clamped counts,
--     validated numerics/dates, and one sanitized self-display string (the
--     photo-storage device name, on a row only its author receives).
--   * type is a server-side literal per RPC.
--   * action_url is an internal path or NULL (notification_action_url_internal
--     forbids the legacy ops:// scheme, which three of these sites carried).
--   * dedupe: persistent surfaces hold at-most-one-unread under per-actor
--     advisory xact locks; event surfaces set discriminating dedupe_keys and
--     ride the platform's partial unique indexes via ON CONFLICT DO NOTHING —
--     rows carrying distinct information get distinct keys so the
--     (user, company, type, COALESCE(dedupe_key, title)) unread index cannot
--     swallow a real update.
--   * where the client pushes via OneSignal, the RPC returns the ids that
--     received NEW rows so push targets exactly what the rail recorded.
--
-- Surfaces → functions:
--   DataController task completion         → notify_task_completed
--   DataController project completion      → notify_project_completed
--   DataController task reschedule         → notify_task_rescheduled
--   DataController dependency ready        → notify_dependency_ready
--   DataController + ProjectFormSheet
--     task assignment                      → notify_task_assigned
--   ProjectFormSheet project assignment    → notify_project_assigned
--   DataController pair spawn              → notify_task_pair_spawned
--   DataController bulk schedule summary   → notify_schedule_run_summary
--   VinylOrderSheet draft confirm          → notify_vinyl_order_drafted
--   VinylBulkOrderWizardView summary       → notify_vinyl_bulk_ordered
--   VinylOffcutInventoryService banked     → notify_vinyl_offcut_banked
--   Guided product/catalog/stock setups    → notify_guided_setup_completed
--   ManageTeamView role change             → notify_role_assigned
--   ManageTeamView invites sent            → notify_team_invites_sent
--   UserEventSheet direct book             → notify_time_off_booked
--   UserEventSheet + TimeOffRequestSheet
--     request fan-out                      → notify_time_off_requested
--   QuantityAdjustmentSheet thresholds     → notify_inventory_threshold_crossed
--   PhotoPrefetchService cap banner        → sync_photo_storage_limit_notification
--   HomeBillableThisWeek dispatcher        → sync_billable_week_notification
--   ForecastNotificationDispatcher dip     → sync_forecast_dip_notification
--   ForecastNotificationDispatcher cleared → sync_forecast_cleared_notification

-- ---------------------------------------------------------------------------
-- Task completed → project crew (others, non-persistent). The task must BE
-- completed on the server row; recipients come from the project row's crew
-- list; task and project names come from their rows. Returns the ids that
-- received NEW rows so the companion push targets rail truth.
create or replace function public.notify_task_completed(
  p_task_id uuid
) returns text[]
language plpgsql security definer
set search_path to 'pg_catalog', 'pg_temp'
as $function$
declare
  v_actor_id uuid;
  v_company_id uuid;
  v_actor_name text;
  v_task public.project_tasks%rowtype;
  v_project public.projects%rowtype;
  v_task_display text;
  v_project_title text;
  v_body text;
  v_created text[] := '{}'::text[];
begin
  v_actor_id := private.get_current_user_id();

  select
    u.company_id,
    coalesce(
      nullif(btrim(concat_ws(' ', u.first_name, u.last_name)), ''),
      'A team member'
    )
  into v_company_id, v_actor_name
  from public.users u
  where u.id = v_actor_id
    and u.company_id is not null
    and u.deleted_at is null
    and coalesce(u.is_active, false);

  if v_actor_id is null or v_company_id is null then
    raise exception 'notification actor is unavailable'
      using errcode = '42501';
  end if;

  select *
  into v_task
  from public.project_tasks t
  where t.id = p_task_id
    and t.company_id = v_company_id
    and t.deleted_at is null
  for share;

  if not found then
    raise exception 'notification task is unavailable'
      using errcode = '42501';
  end if;

  if lower(coalesce(v_task.status, '')) <> 'completed' then
    raise exception 'task is not completed'
      using errcode = '22023';
  end if;

  select *
  into v_project
  from public.projects p
  where p.id = v_task.project_id
    and p.company_id = v_company_id
    and p.deleted_at is null
  for share;

  if not found then
    raise exception 'notification project is unavailable'
      using errcode = '42501';
  end if;

  select coalesce(nullif(btrim(v_task.custom_title), ''), tt.display, 'Task')
  into v_task_display
  from (select 1) one
  left join public.task_types tt on tt.id = v_task.task_type_id;

  v_project_title := coalesce(nullif(btrim(v_project.title), ''), 'Untitled project');
  v_body := v_actor_name || ' completed "' || v_task_display || '" on ' || v_project_title;

  perform pg_advisory_xact_lock(hashtextextended(
    'task-completed:' || p_task_id::text,
    0
  ));

  with ins as (
    insert into public.notifications (
      user_id, company_id, type, title, body,
      is_read, persistent, project_id, deep_link_type, dedupe_key
    )
    select
      crew.user_id, v_company_id::text, 'task_completion', 'Task Completed', v_body,
      false, false, v_task.project_id::text, 'projectDetails',
      'task-completed:' || p_task_id::text
    from (
      select distinct lower(btrim(member.user_id)) as user_id
      from unnest(coalesce(v_project.team_member_ids, '{}'::text[]))
        as member(user_id)
    ) crew
    where crew.user_id ~*
        '^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
      and crew.user_id <> v_actor_id::text
      and exists (
        select 1
        from public.users crew_user
        where crew_user.id = crew.user_id::uuid
          and crew_user.company_id = v_company_id
          and crew_user.deleted_at is null
          and coalesce(crew_user.is_active, false)
      )
    on conflict do nothing
    returning user_id
  )
  select coalesce(array_agg(user_id), '{}'::text[])
  into v_created
  from ins;

  return v_created;
end;
$function$;

revoke all on function public.notify_task_completed(uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.notify_task_completed(uuid)
  to anon, authenticated;

-- ---------------------------------------------------------------------------
-- Project completed → project crew (others, non-persistent).
create or replace function public.notify_project_completed(
  p_project_id uuid
) returns text[]
language plpgsql security definer
set search_path to 'pg_catalog', 'pg_temp'
as $function$
declare
  v_actor_id uuid;
  v_company_id uuid;
  v_project public.projects%rowtype;
  v_project_title text;
  v_body text;
  v_created text[] := '{}'::text[];
begin
  v_actor_id := private.get_current_user_id();

  select u.company_id
  into v_company_id
  from public.users u
  where u.id = v_actor_id
    and u.company_id is not null
    and u.deleted_at is null
    and coalesce(u.is_active, false);

  if v_actor_id is null or v_company_id is null then
    raise exception 'notification actor is unavailable'
      using errcode = '42501';
  end if;

  select *
  into v_project
  from public.projects p
  where p.id = p_project_id
    and p.company_id = v_company_id
    and p.deleted_at is null
  for share;

  if not found then
    raise exception 'notification project is unavailable'
      using errcode = '42501';
  end if;

  if lower(coalesce(v_project.status, '')) <> 'completed' then
    raise exception 'project is not completed'
      using errcode = '22023';
  end if;

  v_project_title := coalesce(nullif(btrim(v_project.title), ''), 'Untitled project');
  v_body := '"' || v_project_title || '" has been marked as completed';

  perform pg_advisory_xact_lock(hashtextextended(
    'project-completed:' || p_project_id::text,
    0
  ));

  with ins as (
    insert into public.notifications (
      user_id, company_id, type, title, body,
      is_read, persistent, project_id, deep_link_type, dedupe_key
    )
    select
      crew.user_id, v_company_id::text, 'project_completion', 'Project Completed', v_body,
      false, false, p_project_id::text, 'projectDetails',
      'project-completed:' || p_project_id::text
    from (
      select distinct lower(btrim(member.user_id)) as user_id
      from unnest(coalesce(v_project.team_member_ids, '{}'::text[]))
        as member(user_id)
    ) crew
    where crew.user_id ~*
        '^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
      and crew.user_id <> v_actor_id::text
      and exists (
        select 1
        from public.users crew_user
        where crew_user.id = crew.user_id::uuid
          and crew_user.company_id = v_company_id
          and crew_user.deleted_at is null
          and coalesce(crew_user.is_active, false)
      )
    on conflict do nothing
    returning user_id
  )
  select coalesce(array_agg(user_id), '{}'::text[])
  into v_created
  from ins;

  return v_created;
end;
$function$;

revoke all on function public.notify_project_completed(uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.notify_project_completed(uuid)
  to anon, authenticated;

-- ---------------------------------------------------------------------------
-- Task rescheduled → task crew (others, non-persistent). Terminal tasks are
-- not announceable (a completed or cancelled task moving must not ping the
-- crew — the shipped client gate, enforced on recorded state). The client
-- only dispatches when dates actually changed; the row copy claims only that
-- the task "has been rescheduled", which the recorded schedule substantiates.
create or replace function public.notify_task_rescheduled(
  p_task_id uuid
) returns text[]
language plpgsql security definer
set search_path to 'pg_catalog', 'pg_temp'
as $function$
declare
  v_actor_id uuid;
  v_company_id uuid;
  v_task public.project_tasks%rowtype;
  v_project public.projects%rowtype;
  v_task_display text;
  v_project_title text;
  v_body text;
  v_created text[] := '{}'::text[];
begin
  v_actor_id := private.get_current_user_id();

  select u.company_id
  into v_company_id
  from public.users u
  where u.id = v_actor_id
    and u.company_id is not null
    and u.deleted_at is null
    and coalesce(u.is_active, false);

  if v_actor_id is null or v_company_id is null then
    raise exception 'notification actor is unavailable'
      using errcode = '42501';
  end if;

  select *
  into v_task
  from public.project_tasks t
  where t.id = p_task_id
    and t.company_id = v_company_id
    and t.deleted_at is null
  for share;

  if not found then
    raise exception 'notification task is unavailable'
      using errcode = '42501';
  end if;

  if lower(coalesce(v_task.status, '')) in ('completed', 'cancelled')
     or v_task.start_date is null
     or v_task.end_date is null then
    raise exception 'task schedule is not announceable'
      using errcode = '22023';
  end if;

  select *
  into v_project
  from public.projects p
  where p.id = v_task.project_id
    and p.company_id = v_company_id
    and p.deleted_at is null
  for share;

  if not found then
    raise exception 'notification project is unavailable'
      using errcode = '42501';
  end if;

  select coalesce(nullif(btrim(v_task.custom_title), ''), tt.display, 'Task')
  into v_task_display
  from (select 1) one
  left join public.task_types tt on tt.id = v_task.task_type_id;

  v_project_title := coalesce(nullif(btrim(v_project.title), ''), 'Untitled project');
  v_body := '"' || v_task_display || '" on ' || v_project_title || ' has been rescheduled';

  perform pg_advisory_xact_lock(hashtextextended(
    'task-rescheduled:' || p_task_id::text,
    0
  ));

  with ins as (
    insert into public.notifications (
      user_id, company_id, type, title, body,
      is_read, persistent, project_id, deep_link_type, dedupe_key
    )
    select
      crew.user_id, v_company_id::text, 'schedule_change', 'Schedule Update', v_body,
      false, false, v_task.project_id::text, 'taskDetails',
      'task-rescheduled:' || p_task_id::text
    from (
      select distinct lower(btrim(member.user_id)) as user_id
      from unnest(coalesce(v_task.team_member_ids, '{}'::text[]))
        as member(user_id)
    ) crew
    where crew.user_id ~*
        '^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
      and crew.user_id <> v_actor_id::text
      and exists (
        select 1
        from public.users crew_user
        where crew_user.id = crew.user_id::uuid
          and crew_user.company_id = v_company_id
          and crew_user.deleted_at is null
          and coalesce(crew_user.is_active, false)
      )
    on conflict do nothing
    returning user_id
  )
  select coalesce(array_agg(user_id), '{}'::text[])
  into v_created
  from ins;

  return v_created;
end;
$function$;

revoke all on function public.notify_task_rescheduled(uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.notify_task_rescheduled(uuid)
  to anon, authenticated;

-- ---------------------------------------------------------------------------
-- Dependency ready → dependent-task crews (others, non-persistent). The
-- completed task anchors everything: dependents are the same-project tasks
-- whose EFFECTIVE dependency list (task-level dependency_overrides when the
-- column holds an array — even an empty one, matching the iOS decode — else
-- the task type's defaults) contains the completed task's type. Copy renders
-- per dependent from server rows. Returns [{task_id, user_ids}] for the
-- created rows only, so the per-task companion push targets rail truth.
create or replace function public.notify_dependency_ready(
  p_completed_task_id uuid
) returns jsonb
language plpgsql security definer
set search_path to 'pg_catalog', 'pg_temp'
as $function$
declare
  v_actor_id uuid;
  v_company_id uuid;
  v_task public.project_tasks%rowtype;
  v_project public.projects%rowtype;
  v_completed_display text;
  v_project_title text;
  v_dependent record;
  v_body text;
  v_created text[];
  v_result jsonb := '[]'::jsonb;
begin
  v_actor_id := private.get_current_user_id();

  select u.company_id
  into v_company_id
  from public.users u
  where u.id = v_actor_id
    and u.company_id is not null
    and u.deleted_at is null
    and coalesce(u.is_active, false);

  if v_actor_id is null or v_company_id is null then
    raise exception 'notification actor is unavailable'
      using errcode = '42501';
  end if;

  select *
  into v_task
  from public.project_tasks t
  where t.id = p_completed_task_id
    and t.company_id = v_company_id
    and t.deleted_at is null
  for share;

  if not found then
    raise exception 'notification task is unavailable'
      using errcode = '42501';
  end if;

  if lower(coalesce(v_task.status, '')) <> 'completed' then
    raise exception 'task is not completed'
      using errcode = '22023';
  end if;

  if v_task.task_type_id is null then
    return v_result;
  end if;

  select *
  into v_project
  from public.projects p
  where p.id = v_task.project_id
    and p.company_id = v_company_id
    and p.deleted_at is null;

  if not found then
    raise exception 'notification project is unavailable'
      using errcode = '42501';
  end if;

  select coalesce(nullif(btrim(v_task.custom_title), ''), tt.display, 'Task')
  into v_completed_display
  from (select 1) one
  left join public.task_types tt on tt.id = v_task.task_type_id;

  v_project_title := coalesce(nullif(btrim(v_project.title), ''), 'Untitled project');

  perform pg_advisory_xact_lock(hashtextextended(
    'dependency-ready:' || p_completed_task_id::text,
    0
  ));

  for v_dependent in
    select
      t.id,
      t.team_member_ids,
      coalesce(nullif(btrim(t.custom_title), ''), tt.display, 'Task') as display
    from public.project_tasks t
    left join public.task_types tt on tt.id = t.task_type_id
    where t.project_id = v_task.project_id
      and t.company_id = v_company_id
      and t.deleted_at is null
      and t.id <> v_task.id
      and exists (
        select 1
        from jsonb_array_elements(
          case
            when jsonb_typeof(t.dependency_overrides) = 'array'
              then t.dependency_overrides
            when jsonb_typeof(tt.dependencies) = 'array'
              then tt.dependencies
            else '[]'::jsonb
          end
        ) dep
        where lower(coalesce(dep.value ->> 'dependsOnTaskTypeId', ''))
          = lower(v_task.task_type_id::text)
      )
    order by t.id
  loop
    v_body := v_dependent.display || ' on ' || v_project_title
      || ' — ' || v_completed_display || ' is complete';

    with ins as (
      insert into public.notifications (
        user_id, company_id, type, title, body,
        is_read, persistent, project_id, deep_link_type, dedupe_key
      )
      select
        crew.user_id, v_company_id::text, 'dependency_completed',
        'Ready to start', v_body,
        false, false, v_task.project_id::text, 'taskDetails',
        'dependency-ready:' || p_completed_task_id::text || ':' || v_dependent.id::text
      from (
        select distinct lower(btrim(member.user_id)) as user_id
        from unnest(coalesce(v_dependent.team_member_ids, '{}'::text[]))
          as member(user_id)
      ) crew
      where crew.user_id ~*
          '^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
        and crew.user_id <> v_actor_id::text
        and exists (
          select 1
          from public.users crew_user
          where crew_user.id = crew.user_id::uuid
            and crew_user.company_id = v_company_id
            and crew_user.deleted_at is null
            and coalesce(crew_user.is_active, false)
        )
      on conflict do nothing
      returning user_id
    )
    select coalesce(array_agg(user_id), '{}'::text[])
    into v_created
    from ins;

    if cardinality(v_created) > 0 then
      v_result := v_result || jsonb_build_array(jsonb_build_object(
        'task_id', v_dependent.id::text,
        'user_ids', to_jsonb(v_created)
      ));
    end if;
  end loop;

  return v_result;
end;
$function$;

revoke all on function public.notify_dependency_ready(uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.notify_dependency_ready(uuid)
  to anon, authenticated;

-- ---------------------------------------------------------------------------
-- Task assigned → assignees (others, non-persistent). The caller may pass the
-- freshly ADDED member ids (team-edit delta — server rows can no longer show
-- which members are new); the list only SUBSETS the task row's recorded
-- team_member_ids. NULL means the row's full crew (creation-time fan-out).
create or replace function public.notify_task_assigned(
  p_task_id uuid,
  p_user_ids text[] default null
) returns text[]
language plpgsql security definer
set search_path to 'pg_catalog', 'pg_temp'
as $function$
declare
  v_actor_id uuid;
  v_company_id uuid;
  v_task public.project_tasks%rowtype;
  v_project public.projects%rowtype;
  v_task_display text;
  v_project_title text;
  v_team text[];
  v_body text;
  v_created text[] := '{}'::text[];
begin
  v_actor_id := private.get_current_user_id();

  select u.company_id
  into v_company_id
  from public.users u
  where u.id = v_actor_id
    and u.company_id is not null
    and u.deleted_at is null
    and coalesce(u.is_active, false);

  if v_actor_id is null or v_company_id is null then
    raise exception 'notification actor is unavailable'
      using errcode = '42501';
  end if;

  if p_user_ids is not null and cardinality(p_user_ids) > 500 then
    raise exception 'too many assignment recipients'
      using errcode = '22023';
  end if;

  select *
  into v_task
  from public.project_tasks t
  where t.id = p_task_id
    and t.company_id = v_company_id
    and t.deleted_at is null
  for share;

  if not found then
    raise exception 'notification task is unavailable'
      using errcode = '42501';
  end if;

  select *
  into v_project
  from public.projects p
  where p.id = v_task.project_id
    and p.company_id = v_company_id
    and p.deleted_at is null;

  if not found then
    raise exception 'notification project is unavailable'
      using errcode = '42501';
  end if;

  select coalesce(nullif(btrim(v_task.custom_title), ''), tt.display, 'Task')
  into v_task_display
  from (select 1) one
  left join public.task_types tt on tt.id = v_task.task_type_id;

  v_project_title := coalesce(nullif(btrim(v_project.title), ''), 'Untitled project');
  v_body := 'You''ve been assigned to "' || v_task_display || '" on ' || v_project_title;

  select coalesce(array_agg(distinct lower(btrim(member.user_id))), '{}'::text[])
  into v_team
  from unnest(coalesce(v_task.team_member_ids, '{}'::text[])) as member(user_id);

  perform pg_advisory_xact_lock(hashtextextended(
    'task-assigned:' || p_task_id::text,
    0
  ));

  with ins as (
    insert into public.notifications (
      user_id, company_id, type, title, body,
      is_read, persistent, project_id, deep_link_type, dedupe_key
    )
    select
      candidate.user_id, v_company_id::text, 'task_assignment',
      'New Task Assignment', v_body,
      false, false, v_task.project_id::text, 'taskDetails',
      'task-assigned:' || p_task_id::text
    from (
      select distinct lower(btrim(requested.user_id)) as user_id
      from unnest(coalesce(p_user_ids, v_task.team_member_ids, '{}'::text[]))
        as requested(user_id)
    ) candidate
    where candidate.user_id ~*
        '^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
      and candidate.user_id = any (v_team)
      and candidate.user_id <> v_actor_id::text
      and exists (
        select 1
        from public.users candidate_user
        where candidate_user.id = candidate.user_id::uuid
          and candidate_user.company_id = v_company_id
          and candidate_user.deleted_at is null
          and coalesce(candidate_user.is_active, false)
      )
    on conflict do nothing
    returning user_id
  )
  select coalesce(array_agg(user_id), '{}'::text[])
  into v_created
  from ins;

  return v_created;
end;
$function$;

revoke all on function public.notify_task_assigned(uuid, text[])
  from public, anon, authenticated, service_role;
grant execute on function public.notify_task_assigned(uuid, text[])
  to anon, authenticated;

-- ---------------------------------------------------------------------------
-- Project assigned → project-only members (others, non-persistent). Fired at
-- project creation for members who hold no task on it (task holders get the
-- task-assignment row instead — the shipped split). The input list subsets
-- the project row's recorded team_member_ids.
create or replace function public.notify_project_assigned(
  p_project_id uuid,
  p_user_ids text[]
) returns text[]
language plpgsql security definer
set search_path to 'pg_catalog', 'pg_temp'
as $function$
declare
  v_actor_id uuid;
  v_company_id uuid;
  v_project public.projects%rowtype;
  v_project_title text;
  v_team text[];
  v_body text;
  v_created text[] := '{}'::text[];
begin
  v_actor_id := private.get_current_user_id();

  select u.company_id
  into v_company_id
  from public.users u
  where u.id = v_actor_id
    and u.company_id is not null
    and u.deleted_at is null
    and coalesce(u.is_active, false);

  if v_actor_id is null or v_company_id is null then
    raise exception 'notification actor is unavailable'
      using errcode = '42501';
  end if;

  if p_user_ids is null or cardinality(p_user_ids) = 0 then
    return v_created;
  end if;

  if cardinality(p_user_ids) > 500 then
    raise exception 'too many assignment recipients'
      using errcode = '22023';
  end if;

  select *
  into v_project
  from public.projects p
  where p.id = p_project_id
    and p.company_id = v_company_id
    and p.deleted_at is null
  for share;

  if not found then
    raise exception 'notification project is unavailable'
      using errcode = '42501';
  end if;

  v_project_title := coalesce(nullif(btrim(v_project.title), ''), 'Untitled project');
  v_body := 'You''ve been added to "' || v_project_title || '"';

  select coalesce(array_agg(distinct lower(btrim(member.user_id))), '{}'::text[])
  into v_team
  from unnest(coalesce(v_project.team_member_ids, '{}'::text[])) as member(user_id);

  perform pg_advisory_xact_lock(hashtextextended(
    'project-assigned:' || p_project_id::text,
    0
  ));

  with ins as (
    insert into public.notifications (
      user_id, company_id, type, title, body,
      is_read, persistent, project_id, deep_link_type, dedupe_key
    )
    select
      candidate.user_id, v_company_id::text, 'project_assignment',
      'Added to Project', v_body,
      false, false, p_project_id::text, 'projectDetails',
      'project-assigned:' || p_project_id::text
    from (
      select distinct lower(btrim(requested.user_id)) as user_id
      from unnest(p_user_ids) as requested(user_id)
    ) candidate
    where candidate.user_id ~*
        '^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
      and candidate.user_id = any (v_team)
      and candidate.user_id <> v_actor_id::text
      and exists (
        select 1
        from public.users candidate_user
        where candidate_user.id = candidate.user_id::uuid
          and candidate_user.company_id = v_company_id
          and candidate_user.deleted_at is null
          and coalesce(candidate_user.is_active, false)
      )
    on conflict do nothing
    returning user_id
  )
  select coalesce(array_agg(user_id), '{}'::text[])
  into v_created
  from ins;

  return v_created;
end;
$function$;

revoke all on function public.notify_project_assigned(uuid, text[])
  from public, anon, authenticated, service_role;
grant execute on function public.notify_project_assigned(uuid, text[])
  to anon, authenticated;

-- ---------------------------------------------------------------------------
-- Auto-spawned pair task → predecessor crew (non-persistent). The spawned
-- task row anchors: its paired_from_task_id names the predecessor whose crew
-- is notified (falling back to the actor when the predecessor has no valid
-- crew — the shipped fallback; the actor is deliberately NOT excluded, since
-- a pair spawn is system-initiated information, not an echo of an explicit
-- action). Copy renders from the spawn's type, schedule, and the
-- predecessor's display name. The iOS dispatcher awaits its outbound push
-- before calling, so the spawn rows exist here; offline the call fails
-- harmlessly (best-effort, matching every surface of this initiative).
create or replace function public.notify_task_pair_spawned(
  p_task_id uuid
) returns text[]
language plpgsql security definer
set search_path to 'pg_catalog', 'pg_temp'
as $function$
declare
  v_actor_id uuid;
  v_company_id uuid;
  v_task public.project_tasks%rowtype;
  v_predecessor public.project_tasks%rowtype;
  v_type_display text;
  v_predecessor_display text;
  v_date_blurb text := '';
  v_body text;
  v_recipients text[];
  v_created text[] := '{}'::text[];
begin
  v_actor_id := private.get_current_user_id();

  select u.company_id
  into v_company_id
  from public.users u
  where u.id = v_actor_id
    and u.company_id is not null
    and u.deleted_at is null
    and coalesce(u.is_active, false);

  if v_actor_id is null or v_company_id is null then
    raise exception 'notification actor is unavailable'
      using errcode = '42501';
  end if;

  select *
  into v_task
  from public.project_tasks t
  where t.id = p_task_id
    and t.company_id = v_company_id
    and t.deleted_at is null
  for share;

  if not found then
    raise exception 'notification task is unavailable'
      using errcode = '42501';
  end if;

  if v_task.paired_from_task_id is null then
    raise exception 'task is not a spawned pair'
      using errcode = '22023';
  end if;

  select *
  into v_predecessor
  from public.project_tasks t
  where t.id = v_task.paired_from_task_id
    and t.company_id = v_company_id
    and t.deleted_at is null;

  if not found then
    raise exception 'notification predecessor is unavailable'
      using errcode = '42501';
  end if;

  select coalesce(nullif(btrim(v_task.custom_title), ''), tt.display, 'Task')
  into v_type_display
  from (select 1) one
  left join public.task_types tt on tt.id = v_task.task_type_id;

  select coalesce(nullif(btrim(v_predecessor.custom_title), ''), tt.display, 'Task')
  into v_predecessor_display
  from (select 1) one
  left join public.task_types tt on tt.id = v_predecessor.task_type_id;

  if v_task.start_date is not null then
    v_date_blurb := ' for '
      || to_char(v_task.start_date at time zone 'utc', 'Dy Mon FMDD');
  end if;

  v_body := 'Auto-scheduled ' || upper(v_type_display) || v_date_blurb
    || ' — paired from ' || v_predecessor_display;

  select coalesce(array_agg(distinct crew.user_id), '{}'::text[])
  into v_recipients
  from (
    select lower(btrim(member.user_id)) as user_id
    from unnest(coalesce(v_predecessor.team_member_ids, '{}'::text[]))
      as member(user_id)
  ) crew
  where crew.user_id ~*
      '^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
    and exists (
      select 1
      from public.users crew_user
      where crew_user.id = crew.user_id::uuid
        and crew_user.company_id = v_company_id
        and crew_user.deleted_at is null
        and coalesce(crew_user.is_active, false)
    );

  if cardinality(v_recipients) = 0 then
    v_recipients := array[v_actor_id::text];
  end if;

  perform pg_advisory_xact_lock(hashtextextended(
    'task-pair-spawned:' || p_task_id::text,
    0
  ));

  with ins as (
    insert into public.notifications (
      user_id, company_id, type, title, body,
      is_read, persistent, project_id, deep_link_type, dedupe_key
    )
    select
      recipient.user_id, v_company_id::text, 'task_pair_spawned',
      '// NEW TASK', v_body,
      false, false, v_task.project_id::text, 'projectDetails',
      'task-pair-spawned:' || p_task_id::text
    from unnest(v_recipients) as recipient(user_id)
    on conflict do nothing
    returning user_id
  )
  select coalesce(array_agg(user_id), '{}'::text[])
  into v_created
  from ins;

  return v_created;
end;
$function$;

revoke all on function public.notify_task_pair_spawned(uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.notify_task_pair_spawned(uuid)
  to anon, authenticated;

-- ---------------------------------------------------------------------------
-- Bulk auto-schedule run summary → affected crew (others, non-persistent).
-- The caller names the tasks the committed plan moved (rows already pushed —
-- the shipped dispatcher runs after pushPending()); the server derives each
-- member's moved-task count from those rows' recorded crews and writes ONE
-- summary row per member. Returns [{user_id, moved_count}] for created rows
-- so the batch push mirrors the rail exactly.
create or replace function public.notify_schedule_run_summary(
  p_task_ids uuid[]
) returns jsonb
language plpgsql security definer
set search_path to 'pg_catalog', 'pg_temp'
as $function$
declare
  v_actor_id uuid;
  v_company_id uuid;
  v_member record;
  v_body text;
  v_dedupe_key text;
  v_inserted integer;
  v_result jsonb := '[]'::jsonb;
begin
  v_actor_id := private.get_current_user_id();

  select u.company_id
  into v_company_id
  from public.users u
  where u.id = v_actor_id
    and u.company_id is not null
    and u.deleted_at is null
    and coalesce(u.is_active, false);

  if v_actor_id is null or v_company_id is null then
    raise exception 'notification actor is unavailable'
      using errcode = '42501';
  end if;

  if p_task_ids is null
     or cardinality(p_task_ids) = 0
     or cardinality(p_task_ids) > 500 then
    raise exception 'schedule run task list is invalid'
      using errcode = '22023';
  end if;

  v_dedupe_key := 'schedule-run:' || md5((
    select string_agg(distinct task_id::text, ',' order by task_id::text)
    from unnest(p_task_ids) as moved(task_id)
  ));

  perform pg_advisory_xact_lock(hashtextextended(v_dedupe_key, 0));

  for v_member in
    select member.user_id, count(distinct t.id)::integer as moved_count
    from public.project_tasks t
    cross join lateral (
      select distinct lower(btrim(raw.user_id)) as user_id
      from unnest(coalesce(t.team_member_ids, '{}'::text[])) as raw(user_id)
    ) member
    where t.id = any (p_task_ids)
      and t.company_id = v_company_id
      and t.deleted_at is null
      and member.user_id ~*
        '^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
      and member.user_id <> v_actor_id::text
      and exists (
        select 1
        from public.users member_user
        where member_user.id = member.user_id::uuid
          and member_user.company_id = v_company_id
          and member_user.deleted_at is null
          and coalesce(member_user.is_active, false)
      )
    group by member.user_id
    order by member.user_id
  loop
    if v_member.moved_count = 1 then
      v_body := '1 of your tasks was rescheduled';
    else
      v_body := v_member.moved_count || ' of your tasks were rescheduled';
    end if;

    insert into public.notifications (
      user_id, company_id, type, title, body,
      is_read, persistent, deep_link_type, dedupe_key
    ) values (
      v_member.user_id, v_company_id::text, 'schedule_change',
      'Schedule updated', v_body,
      false, false, 'jobBoard', v_dedupe_key
    )
    on conflict do nothing;

    get diagnostics v_inserted = row_count;
    if v_inserted = 1 then
      v_result := v_result || jsonb_build_array(jsonb_build_object(
        'user_id', v_member.user_id,
        'moved_count', v_member.moved_count
      ));
    end if;
  end loop;

  return v_result;
end;
$function$;

revoke all on function public.notify_schedule_run_summary(uuid[])
  from public, anon, authenticated, service_role;
grant execute on function public.notify_schedule_run_summary(uuid[])
  to anon, authenticated;

-- ---------------------------------------------------------------------------
-- Vinyl order drafted (self, non-persistent). The note the sheet just wrote
-- anchors the confirmation (author must be the actor); the project title
-- comes from the project row; the square footage is clamped. The legacy
-- ops://catalog/orders action_url is gone — iOS renders REVIEW from
-- deep_link_type; the surface is a phone workflow, so action_url stays NULL
-- (threshold-rail precedent).
create or replace function public.notify_vinyl_order_drafted(
  p_project_id uuid,
  p_note_id uuid,
  p_ordered_sq_ft integer
) returns text
language plpgsql security definer
set search_path to 'pg_catalog', 'pg_temp'
as $function$
declare
  v_actor_id uuid;
  v_company_id uuid;
  v_project_title text;
  v_note public.project_notes%rowtype;
  v_sq_ft integer;
  v_inserted integer := 0;
begin
  v_actor_id := private.get_current_user_id();

  select u.company_id
  into v_company_id
  from public.users u
  where u.id = v_actor_id
    and u.company_id is not null
    and u.deleted_at is null
    and coalesce(u.is_active, false);

  if v_actor_id is null or v_company_id is null then
    raise exception 'notification actor is unavailable'
      using errcode = '42501';
  end if;

  select coalesce(nullif(btrim(p.title), ''), 'Untitled project')
  into v_project_title
  from public.projects p
  where p.id = p_project_id
    and p.company_id = v_company_id
    and p.deleted_at is null;

  if not found then
    raise exception 'notification project is unavailable'
      using errcode = '42501';
  end if;

  select *
  into v_note
  from public.project_notes n
  where n.id = p_note_id
  for share;

  if not found
     or v_note.project_id is distinct from p_project_id::text
     or v_note.company_id is distinct from v_company_id::text
     or v_note.author_id is distinct from v_actor_id::text
     or v_note.deleted_at is not null then
    raise exception 'notification note is unavailable'
      using errcode = '42501';
  end if;

  v_sq_ft := least(greatest(coalesce(p_ordered_sq_ft, 1), 1), 1000000);

  insert into public.notifications (
    user_id, company_id, type, title, body,
    is_read, persistent, project_id, note_id, deep_link_type,
    action_url, action_label, dedupe_key
  ) values (
    v_actor_id::text, v_company_id::text, 'catalog_order_drafted',
    '// VINYL ORDER DRAFTED',
    upper(v_project_title) || ' · ' || v_sq_ft || ' SQ FT READY',
    false, false, p_project_id::text, p_note_id::text, 'catalogOrders',
    null, 'REVIEW',
    'vinyl-order-drafted:' || p_note_id::text
  )
  on conflict do nothing;

  get diagnostics v_inserted = row_count;
  if v_inserted = 1 then
    return 'created';
  end if;
  return 'noop';
end;
$function$;

revoke all on function public.notify_vinyl_order_drafted(uuid, uuid, integer)
  from public, anon, authenticated, service_role;
grant execute on function public.notify_vinyl_order_drafted(uuid, uuid, integer)
  to anon, authenticated;

-- ---------------------------------------------------------------------------
-- Vinyl bulk order summary (self, non-persistent). One row per committed
-- send run; the marked count is clamped and the date renders server-side in
-- the shipped uppercased "MMM. d" shape.
create or replace function public.notify_vinyl_bulk_ordered(
  p_marked_count integer
) returns text
language plpgsql security definer
set search_path to 'pg_catalog', 'pg_temp'
as $function$
declare
  v_actor_id uuid;
  v_company_id uuid;
  v_count integer;
  v_body text;
  v_inserted integer := 0;
begin
  v_actor_id := private.get_current_user_id();

  select u.company_id
  into v_company_id
  from public.users u
  where u.id = v_actor_id
    and u.company_id is not null
    and u.deleted_at is null
    and coalesce(u.is_active, false);

  if v_actor_id is null or v_company_id is null then
    raise exception 'notification actor is unavailable'
      using errcode = '42501';
  end if;

  v_count := least(greatest(coalesce(p_marked_count, 1), 1), 10000);
  v_body := v_count || ' PROJECT'
    || case when v_count = 1 then '' else 'S' end
    || ' · ' || upper(to_char(now(), 'Mon')) || '. ' || to_char(now(), 'FMDD');

  insert into public.notifications (
    user_id, company_id, type, title, body,
    is_read, persistent, dedupe_key
  ) values (
    v_actor_id::text, v_company_id::text, 'vinyl_bulk_ordered',
    '// VINYL ORDERED', v_body,
    false, false,
    'vinyl-bulk-ordered:' || md5(v_body)
  )
  on conflict do nothing;

  get diagnostics v_inserted = row_count;
  if v_inserted = 1 then
    return 'created';
  end if;
  return 'noop';
end;
$function$;

revoke all on function public.notify_vinyl_bulk_ordered(integer)
  from public, anon, authenticated, service_role;
grant execute on function public.notify_vinyl_bulk_ordered(integer)
  to anon, authenticated;

-- ---------------------------------------------------------------------------
-- Vinyl offcut banked (self, non-persistent). The stock-unit row the service
-- just created anchors the copy: the vinyl lane stores feet, the shipped
-- body renders inches — width via the 0.1-rounded inch label (whole inches
-- drop the decimal), length via the feet-and-inches formatter (whole feet
-- render F', mixed F' I", sub-foot I").
create or replace function public.notify_vinyl_offcut_banked(
  p_stock_unit_id uuid,
  p_project_id uuid default null
) returns text
language plpgsql security definer
set search_path to 'pg_catalog', 'pg_temp'
as $function$
declare
  v_actor_id uuid;
  v_company_id uuid;
  v_unit public.catalog_stock_units%rowtype;
  v_width_inches numeric;
  v_length_inches numeric;
  v_width_label text;
  v_length_label text;
  v_length_feet integer;
  v_length_rem numeric;
  v_rem_whole numeric;
  v_inch_text text;
  v_project_ref text := null;
  v_inserted integer := 0;
begin
  v_actor_id := private.get_current_user_id();

  select u.company_id
  into v_company_id
  from public.users u
  where u.id = v_actor_id
    and u.company_id is not null
    and u.deleted_at is null
    and coalesce(u.is_active, false);

  if v_actor_id is null or v_company_id is null then
    raise exception 'notification actor is unavailable'
      using errcode = '42501';
  end if;

  select *
  into v_unit
  from public.catalog_stock_units s
  where s.id = p_stock_unit_id
    and s.company_id = v_company_id
    and s.deleted_at is null
  for share;

  if not found then
    raise exception 'notification stock unit is unavailable'
      using errcode = '42501';
  end if;

  if coalesce(v_unit.unit_kind, '') <> 'offcut' then
    raise exception 'stock unit is not an offcut'
      using errcode = '22023';
  end if;

  if lower(coalesce(v_unit.width_unit, 'ft')) = 'ft' then
    v_width_inches := coalesce(v_unit.width_value, 0) * 12;
  elsif lower(v_unit.width_unit) = 'in' then
    v_width_inches := coalesce(v_unit.width_value, 0);
  else
    raise exception 'offcut width unit is unsupported'
      using errcode = '22023';
  end if;

  if lower(coalesce(v_unit.length_unit, 'ft')) = 'ft' then
    v_length_inches := coalesce(v_unit.remaining_length_value, 0) * 12;
  elsif lower(v_unit.length_unit) = 'in' then
    v_length_inches := coalesce(v_unit.remaining_length_value, 0);
  else
    raise exception 'offcut length unit is unsupported'
      using errcode = '22023';
  end if;

  -- inchLabel: round to a tenth; whole inches drop the decimal.
  v_width_inches := round(v_width_inches * 10) / 10;
  if v_width_inches = trunc(v_width_inches) then
    v_width_label := trunc(v_width_inches)::bigint::text || '"';
  else
    v_width_label := to_char(v_width_inches, 'FM999990.0') || '"';
  end if;

  -- vinylFormatFeetAndInches: round to a tenth of an inch, split feet and
  -- remainder; whole remainders drop the decimal; whole feet drop inches.
  v_length_inches := round(v_length_inches * 10) / 10;
  v_length_feet := trunc(v_length_inches / 12)::integer;
  v_length_rem := v_length_inches - (v_length_feet * 12);
  v_rem_whole := round(v_length_rem);
  if abs(v_length_rem - v_rem_whole) < 0.001 then
    v_inch_text := v_rem_whole::integer::text;
  else
    v_inch_text := to_char(v_length_rem, 'FM999990.0');
  end if;
  if v_length_feet > 0 and abs(v_length_rem) < 0.001 then
    v_length_label := v_length_feet || '''';
  elsif v_length_feet > 0 then
    v_length_label := v_length_feet || ''' ' || v_inch_text || '"';
  else
    v_length_label := v_inch_text || '"';
  end if;

  if p_project_id is not null then
    if exists (
      select 1
      from public.projects p
      where p.id = p_project_id
        and p.company_id = v_company_id
        and p.deleted_at is null
    ) then
      v_project_ref := p_project_id::text;
    end if;
  end if;

  insert into public.notifications (
    user_id, company_id, type, title, body,
    is_read, persistent, project_id, deep_link_type,
    action_url, action_label, dedupe_key
  ) values (
    v_actor_id::text, v_company_id::text, 'standard',
    '// OFFCUT BANKED',
    v_width_label || ' × ' || v_length_label || ' BANKED TO STOCK',
    false, false, v_project_ref, 'catalog_stock',
    '/catalog?segment=stock', 'VIEW STOCK',
    'vinyl-offcut-banked:' || p_stock_unit_id::text
  )
  on conflict do nothing;

  get diagnostics v_inserted = row_count;
  if v_inserted = 1 then
    return 'created';
  end if;
  return 'noop';
end;
$function$;

revoke all on function public.notify_vinyl_offcut_banked(uuid, uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.notify_vinyl_offcut_banked(uuid, uuid)
  to anon, authenticated;

-- ---------------------------------------------------------------------------
-- Guided setup completion (self, non-persistent) — one RPC for the three
-- guided flows' completion confirmations, which share the surface shape
-- (type 'standard', catalog links, count-derived summary copy). Counts are
-- clamped; each kind renders its shipped template verbatim.
create or replace function public.notify_guided_setup_completed(
  p_kind text,
  p_product_count integer default null,
  p_recipe_count integer default null,
  p_service_count integer default null,
  p_good_count integer default null,
  p_assembly_count integer default null,
  p_family_count integer default null,
  p_variant_count integer default null,
  p_roll_count integer default null,
  p_offcut_count integer default null,
  p_bundle_count integer default null
) returns text
language plpgsql security definer
set search_path to 'pg_catalog', 'pg_temp'
as $function$
declare
  v_actor_id uuid;
  v_company_id uuid;
  v_title text;
  v_body text;
  v_deep_link text;
  v_action_url text;
  v_action_label text;
  v_products integer;
  v_recipes integer;
  v_services integer;
  v_goods integer;
  v_assemblies integer;
  v_families integer;
  v_variants integer;
  v_rolls integer;
  v_offcuts integer;
  v_bundles integer;
  v_parts text[] := '{}'::text[];
  v_inserted integer := 0;
begin
  v_actor_id := private.get_current_user_id();

  select u.company_id
  into v_company_id
  from public.users u
  where u.id = v_actor_id
    and u.company_id is not null
    and u.deleted_at is null
    and coalesce(u.is_active, false);

  if v_actor_id is null or v_company_id is null then
    raise exception 'notification actor is unavailable'
      using errcode = '42501';
  end if;

  if p_kind = 'product_setup' then
    v_products := least(greatest(coalesce(p_product_count, 0), 0), 10000);
    v_recipes := least(greatest(coalesce(p_recipe_count, 0), 0), 10000);
    if v_products < 1 then
      raise exception 'product setup has nothing to announce'
        using errcode = '22023';
    end if;
    v_title := 'PRODUCT SETUP COMPLETE';
    v_body := v_products || ' product '
      || case when v_products = 1 then 'row' else 'rows' end
      || case when v_recipes > 0
           then ' and ' || v_recipes || ' recipe '
             || case when v_recipes = 1 then 'row' else 'rows' end
           else ''
         end
      || ' saved for estimating.';
    v_deep_link := 'catalog_products';
    v_action_url := '/catalog?segment=products';
    v_action_label := 'VIEW PRODUCTS';
  elsif p_kind = 'catalog_setup' then
    v_services := least(greatest(coalesce(p_service_count, 0), 0), 10000);
    v_goods := least(greatest(coalesce(p_good_count, 0), 0), 10000);
    v_assemblies := least(greatest(coalesce(p_assembly_count, 0), 0), 10000);
    if v_services + v_goods + v_assemblies < 1 then
      raise exception 'catalog setup has nothing to announce'
        using errcode = '22023';
    end if;
    if v_assemblies > 0 then
      v_parts := v_parts || (v_assemblies || ' '
        || case when v_assemblies = 1 then 'package' else 'packages' end);
    end if;
    if v_services > 0 then
      v_parts := v_parts || (v_services || ' '
        || case when v_services = 1 then 'service' else 'services' end);
    end if;
    if v_goods > 0 then
      v_parts := v_parts || (v_goods || ' '
        || case when v_goods = 1 then 'good' else 'goods' end);
    end if;
    v_title := 'CATALOG SETUP COMPLETE';
    v_body := array_to_string(v_parts, ' · ') || ' saved for estimating.';
    v_deep_link := 'catalog_products';
    v_action_url := '/catalog?segment=products';
    v_action_label := 'VIEW PRODUCTS';
  elsif p_kind = 'stock_setup' then
    v_families := least(greatest(coalesce(p_family_count, 0), 0), 10000);
    v_variants := least(greatest(coalesce(p_variant_count, 0), 0), 10000);
    v_rolls := least(greatest(coalesce(p_roll_count, 0), 0), 10000);
    v_offcuts := least(greatest(coalesce(p_offcut_count, 0), 0), 10000);
    v_products := least(greatest(coalesce(p_product_count, 0), 0), 10000);
    v_bundles := least(greatest(coalesce(p_bundle_count, 0), 0), 10000);
    if v_families + v_variants + v_rolls + v_offcuts + v_products + v_bundles < 1 then
      raise exception 'stock setup has nothing to announce'
        using errcode = '22023';
    end if;
    if v_families > 0 then
      v_parts := v_parts || (v_families || ' '
        || case when v_families = 1 then 'family' else 'families' end);
    end if;
    if v_variants > 0 then
      v_parts := v_parts || (v_variants || ' '
        || case when v_variants = 1 then 'variant' else 'variants' end);
    end if;
    if v_rolls > 0 then
      v_parts := v_parts || (v_rolls || ' '
        || case when v_rolls = 1 then 'roll' else 'rolls' end);
    end if;
    if v_offcuts > 0 then
      v_parts := v_parts || (v_offcuts || ' '
        || case when v_offcuts = 1 then 'offcut' else 'offcuts' end);
    end if;
    if v_products > 0 then
      v_parts := v_parts || (v_products || ' '
        || case when v_products = 1 then 'product' else 'products' end);
    end if;
    if v_bundles > 0 then
      v_parts := v_parts || (v_bundles || ' '
        || case when v_bundles = 1 then 'bundle' else 'bundles' end);
    end if;
    v_title := 'STOCK SYSTEM BUILT';
    v_body := array_to_string(v_parts, ' · ');
    v_deep_link := 'catalog_stock';
    v_action_url := '/catalog?segment=stock';
    v_action_label := 'VIEW STOCK';
  else
    raise exception 'unknown guided setup kind'
      using errcode = '22023';
  end if;

  insert into public.notifications (
    user_id, company_id, type, title, body,
    is_read, persistent, deep_link_type,
    action_url, action_label, dedupe_key
  ) values (
    v_actor_id::text, v_company_id::text, 'standard', v_title, v_body,
    false, false, v_deep_link,
    v_action_url, v_action_label,
    'guided-setup:' || p_kind || ':' || md5(v_body)
  )
  on conflict do nothing;

  get diagnostics v_inserted = row_count;
  if v_inserted = 1 then
    return 'created';
  end if;
  return 'noop';
end;
$function$;

revoke all on function public.notify_guided_setup_completed(
  text, integer, integer, integer, integer, integer, integer, integer, integer, integer, integer
) from public, anon, authenticated, service_role;
grant execute on function public.notify_guided_setup_completed(
  text, integer, integer, integer, integer, integer, integer, integer, integer, integer, integer
) to anon, authenticated;

-- ---------------------------------------------------------------------------
-- Role assigned → the member (other, non-persistent). The actor must hold
-- team.assign_roles at all-scope (the lockout-request archetype's seat
-- permission) and the announced role is the member's RECORDED role — latest
-- user_roles row (RBAC truth), falling back to the legacy users.role field —
-- so the RPC cannot mint role claims that never happened.
create or replace function public.notify_role_assigned(
  p_member_id uuid
) returns text
language plpgsql security definer
set search_path to 'pg_catalog', 'pg_temp'
as $function$
declare
  v_actor_id uuid;
  v_company_id uuid;
  v_role_name text;
  v_display text;
  v_inserted integer := 0;
begin
  v_actor_id := private.get_current_user_id();

  select u.company_id
  into v_company_id
  from public.users u
  where u.id = v_actor_id
    and u.company_id is not null
    and u.deleted_at is null
    and coalesce(u.is_active, false);

  if v_actor_id is null or v_company_id is null then
    raise exception 'notification actor is unavailable'
      using errcode = '42501';
  end if;

  if not public.has_permission(v_actor_id, 'team.assign_roles', 'all') then
    raise exception 'notification actor lacks team.assign_roles'
      using errcode = '42501';
  end if;

  if p_member_id = v_actor_id then
    return 'noop';
  end if;

  if not exists (
    select 1
    from public.users member
    where member.id = p_member_id
      and member.company_id = v_company_id
      and member.deleted_at is null
      and coalesce(member.is_active, false)
  ) then
    raise exception 'notification member is unavailable'
      using errcode = '42501';
  end if;

  select r.name
  into v_role_name
  from public.user_roles ur
  join public.roles r on r.id = ur.role_id
  where ur.user_id = p_member_id::text
  order by ur.created_at desc
  limit 1;

  if v_role_name is null then
    select u.role
    into v_role_name
    from public.users u
    where u.id = p_member_id;
  end if;

  if coalesce(btrim(v_role_name), '') = '' then
    raise exception 'member role is not recorded'
      using errcode = '22023';
  end if;

  v_display := case lower(btrim(v_role_name))
    when 'admin' then 'Admin'
    when 'owner' then 'Owner'
    when 'office' then 'Office'
    when 'operator' then 'Operator'
    when 'crew' then 'Crew'
    when 'unassigned' then 'Unassigned'
    else btrim(v_role_name)
  end;

  insert into public.notifications (
    user_id, company_id, type, title, body,
    is_read, persistent, dedupe_key
  ) values (
    p_member_id::text, v_company_id::text, 'role_assigned',
    'Role Updated',
    'You''ve been assigned the ' || v_display || ' role',
    false, false,
    'role-assigned:' || p_member_id::text || ':' || md5(v_display)
  )
  on conflict do nothing;

  get diagnostics v_inserted = row_count;
  if v_inserted = 1 then
    return 'created';
  end if;
  return 'noop';
end;
$function$;

revoke all on function public.notify_role_assigned(uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.notify_role_assigned(uuid)
  to anon, authenticated;

-- ---------------------------------------------------------------------------
-- Team invites sent (self, non-persistent). The send-invite web API creates
-- team_invitations rows but returns no ids, so the RPC anchors on the rows
-- themselves: contacts count only when a fresh invitation row (created by
-- the actor, in the last ten minutes, not cancelled) records them. Display
-- preserves the typed contact; matching is case-insensitive for emails. The
-- legacy ops://settings/organization/team action_url is gone (iOS navigates
-- by deep_link_type; the surface is phone-side, so action_url stays NULL).
create or replace function public.notify_team_invites_sent(
  p_emails text[] default '{}'::text[],
  p_phones text[] default '{}'::text[]
) returns text
language plpgsql security definer
set search_path to 'pg_catalog', 'pg_temp'
as $function$
declare
  v_actor_id uuid;
  v_company_id uuid;
  v_first text;
  v_matched integer;
  v_body text;
  v_inserted integer := 0;
begin
  v_actor_id := private.get_current_user_id();

  select u.company_id
  into v_company_id
  from public.users u
  where u.id = v_actor_id
    and u.company_id is not null
    and u.deleted_at is null
    and coalesce(u.is_active, false);

  if v_actor_id is null or v_company_id is null then
    raise exception 'notification actor is unavailable'
      using errcode = '42501';
  end if;

  if coalesce(cardinality(p_emails), 0) > 200
     or coalesce(cardinality(p_phones), 0) > 200 then
    raise exception 'too many invite contacts'
      using errcode = '22023';
  end if;

  with typed as (
    select btrim(contact.value) as display,
           lower(btrim(contact.value)) as match_key,
           contact.ordinality as ord,
           true as is_email
    from unnest(coalesce(p_emails, '{}'::text[]))
      with ordinality as contact(value, ordinality)
    union all
    select btrim(contact.value),
           btrim(contact.value),
           contact.ordinality + 1000000,
           false
    from unnest(coalesce(p_phones, '{}'::text[]))
      with ordinality as contact(value, ordinality)
  ),
  candidates as (
    select distinct on (t.match_key) t.display, t.match_key, t.ord
    from typed t
    where t.display <> ''
      and exists (
        select 1
        from public.team_invitations ti
        where ti.company_id = v_company_id
          and ti.invited_by = v_actor_id
          and ti.created_at >= now() - interval '10 minutes'
          and coalesce(ti.status, '') <> 'cancelled'
          and (
            (t.is_email and lower(coalesce(ti.email, '')) = t.match_key)
            or (not t.is_email and btrim(coalesce(ti.phone, '')) = t.match_key)
          )
      )
    order by t.match_key, t.ord
  )
  select count(*)::integer,
         (array_agg(display order by ord))[1]
  into v_matched, v_first
  from candidates;

  if coalesce(v_matched, 0) = 0 then
    return 'noop';
  end if;

  if v_matched = 1 then
    v_body := 'Invitation sent to ' || v_first || '.';
  else
    v_body := v_matched || ' invitations sent to ' || v_first
      || ' + ' || (v_matched - 1) || ' more.';
  end if;

  insert into public.notifications (
    user_id, company_id, type, title, body,
    is_read, persistent, deep_link_type,
    action_url, action_label, dedupe_key
  ) values (
    v_actor_id::text, v_company_id::text, 'team_invite_sent',
    'TEAM INVITES SENT', v_body,
    false, false, 'team',
    null, 'VIEW TEAM',
    'team-invites:' || md5(v_body)
  )
  on conflict do nothing;

  get diagnostics v_inserted = row_count;
  if v_inserted = 1 then
    return 'created';
  end if;
  return 'noop';
end;
$function$;

revoke all on function public.notify_team_invites_sent(text[], text[])
  from public, anon, authenticated, service_role;
grant execute on function public.notify_team_invites_sent(text[], text[])
  to anon, authenticated;

-- ---------------------------------------------------------------------------
-- Time off booked → the target (non-persistent). The direct-book lane: the
-- event row must carry the recorded 'approved' state and the actor must hold
-- time_off.approve at all-scope (parity with the sheet's gate). The
-- recipient is the event row's user; self-bookings confirm to the actor.
create or replace function public.notify_time_off_booked(
  p_event_id uuid
) returns text
language plpgsql security definer
set search_path to 'pg_catalog', 'pg_temp'
as $function$
declare
  v_actor_id uuid;
  v_company_id uuid;
  v_actor_name text;
  v_event public.calendar_user_events%rowtype;
  v_recipient text;
  v_range text;
  v_body text;
  v_inserted integer := 0;
begin
  v_actor_id := private.get_current_user_id();

  select
    u.company_id,
    coalesce(
      nullif(btrim(concat_ws(' ', u.first_name, u.last_name)), ''),
      'A team member'
    )
  into v_company_id, v_actor_name
  from public.users u
  where u.id = v_actor_id
    and u.company_id is not null
    and u.deleted_at is null
    and coalesce(u.is_active, false);

  if v_actor_id is null or v_company_id is null then
    raise exception 'notification actor is unavailable'
      using errcode = '42501';
  end if;

  if not public.has_permission(v_actor_id, 'time_off.approve', 'all') then
    raise exception 'notification actor lacks time_off.approve'
      using errcode = '42501';
  end if;

  select *
  into v_event
  from public.calendar_user_events e
  where e.id = p_event_id
  for share;

  if not found
     or v_event.company_id is distinct from v_company_id::text
     or v_event.type is distinct from 'time_off'
     or v_event.deleted_at is not null then
    raise exception 'notification event is unavailable'
      using errcode = '42501';
  end if;

  if coalesce(v_event.status, '') <> 'approved' then
    raise exception 'time off is not booked'
      using errcode = '22023';
  end if;

  if v_event.start_date is null or v_event.end_date is null then
    raise exception 'time off dates are not recorded'
      using errcode = '22023';
  end if;

  v_recipient := lower(btrim(v_event.user_id));
  if v_recipient !~*
      '^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
     or not exists (
       select 1
       from public.users target
       where target.id = v_recipient::uuid
         and target.company_id = v_company_id
         and target.deleted_at is null
         and coalesce(target.is_active, false)
     ) then
    return 'noop';
  end if;

  if (v_event.start_date at time zone 'utc')::date
     = (v_event.end_date at time zone 'utc')::date then
    v_range := to_char(v_event.start_date at time zone 'utc', 'Mon FMDD');
  else
    v_range := to_char(v_event.start_date at time zone 'utc', 'Mon FMDD')
      || ' – ' || to_char(v_event.end_date at time zone 'utc', 'Mon FMDD');
  end if;

  if v_recipient = v_actor_id::text then
    v_body := 'Your time off for ' || v_range || ' is on the schedule.';
  else
    v_body := v_actor_name || ' booked you off for ' || v_range || '.';
  end if;

  insert into public.notifications (
    user_id, company_id, type, title, body,
    is_read, persistent, deep_link_type, dedupe_key
  ) values (
    v_recipient, v_company_id::text, 'time_off_booked',
    'Time Off Booked', v_body,
    false, false, 'schedule',
    'time-off-booked:' || p_event_id::text
  )
  on conflict do nothing;

  get diagnostics v_inserted = row_count;
  if v_inserted = 1 then
    return 'created';
  end if;
  return 'noop';
end;
$function$;

revoke all on function public.notify_time_off_booked(uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.notify_time_off_booked(uuid)
  to anon, authenticated;

-- ---------------------------------------------------------------------------
-- Time off requested — the REQUEST-side fan-out (requester confirmation,
-- on-behalf target row, approver review rows) for both request sheets. The
-- event row must be a pending time_off in the actor's company; the requester
-- is the ACTOR by definition (calendar_user_events records no creator), the
-- target is the row's user, and approvers are time_off.approve holders
-- derived server-side, minus actor and target. Idempotent per event via
-- per-lane dedupe keys checked at any read state, so a transport retry
-- cannot double-notify. Returns the approver ids that received NEW rows for
-- push targeting, plus whether the on-behalf target row was created.
create or replace function public.notify_time_off_requested(
  p_event_id uuid
) returns jsonb
language plpgsql security definer
set search_path to 'pg_catalog', 'pg_temp'
as $function$
declare
  v_actor_id uuid;
  v_company_id uuid;
  v_actor_name text;
  v_event public.calendar_user_events%rowtype;
  v_target text;
  v_target_name text;
  v_is_self boolean;
  v_range text;
  v_requester_body text;
  v_approver_body text;
  v_target_created boolean := false;
  v_approvers text[] := '{}'::text[];
begin
  v_actor_id := private.get_current_user_id();

  select
    u.company_id,
    coalesce(
      nullif(btrim(concat_ws(' ', u.first_name, u.last_name)), ''),
      'A team member'
    )
  into v_company_id, v_actor_name
  from public.users u
  where u.id = v_actor_id
    and u.company_id is not null
    and u.deleted_at is null
    and coalesce(u.is_active, false);

  if v_actor_id is null or v_company_id is null then
    raise exception 'notification actor is unavailable'
      using errcode = '42501';
  end if;

  select *
  into v_event
  from public.calendar_user_events e
  where e.id = p_event_id
  for share;

  if not found
     or v_event.company_id is distinct from v_company_id::text
     or v_event.type is distinct from 'time_off'
     or v_event.deleted_at is not null then
    raise exception 'notification event is unavailable'
      using errcode = '42501';
  end if;

  if coalesce(v_event.status, '') <> 'pending' then
    raise exception 'time off request is not pending'
      using errcode = '22023';
  end if;

  if v_event.start_date is null or v_event.end_date is null then
    raise exception 'time off dates are not recorded'
      using errcode = '22023';
  end if;

  v_target := lower(btrim(v_event.user_id));
  if v_target !~*
      '^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$' then
    raise exception 'notification event target is unavailable'
      using errcode = '42501';
  end if;

  v_is_self := v_target = v_actor_id::text;

  if not v_is_self then
    select coalesce(
      nullif(btrim(concat_ws(' ', target.first_name, target.last_name)), ''),
      'A team member'
    )
    into v_target_name
    from public.users target
    where target.id = v_target::uuid
      and target.company_id = v_company_id
      and target.deleted_at is null
      and coalesce(target.is_active, false);

    if v_target_name is null then
      raise exception 'notification event target is unavailable'
        using errcode = '42501';
    end if;
  end if;

  if (v_event.start_date at time zone 'utc')::date
     = (v_event.end_date at time zone 'utc')::date then
    v_range := to_char(v_event.start_date at time zone 'utc', 'Mon FMDD');
  else
    v_range := to_char(v_event.start_date at time zone 'utc', 'Mon FMDD')
      || ' – ' || to_char(v_event.end_date at time zone 'utc', 'Mon FMDD');
  end if;

  perform pg_advisory_xact_lock(hashtextextended(
    'time-off-request:' || p_event_id::text,
    0
  ));

  if v_is_self then
    v_requester_body := 'Your request for ' || v_range || ' is pending review.';
    v_approver_body := v_actor_name || ' requested time off: ' || v_range;
  else
    v_requester_body := 'Submitted for ' || v_target_name || ': ' || v_range
      || ' (pending review).';
    v_approver_body := v_actor_name || ' requested time off for '
      || v_target_name || ': ' || v_range;
  end if;

  if not exists (
    select 1
    from public.notifications prior
    where prior.user_id = v_actor_id::text
      and prior.type = 'time_off_requested'
      and prior.dedupe_key = 'time-off-request:' || p_event_id::text || ':requester'
  ) then
    insert into public.notifications (
      user_id, company_id, type, title, body,
      is_read, persistent, deep_link_type, dedupe_key
    ) values (
      v_actor_id::text, v_company_id::text, 'time_off_requested',
      'Time Off Submitted', v_requester_body,
      false, false, 'schedule',
      'time-off-request:' || p_event_id::text || ':requester'
    )
    on conflict do nothing;
  end if;

  if not v_is_self
     and not exists (
       select 1
       from public.notifications prior
       where prior.user_id = v_target
         and prior.type = 'time_off_requested'
         and prior.dedupe_key = 'time-off-request:' || p_event_id::text || ':target'
     ) then
    insert into public.notifications (
      user_id, company_id, type, title, body,
      is_read, persistent, deep_link_type, dedupe_key
    ) values (
      v_target, v_company_id::text, 'time_off_requested',
      'Time Off Submitted For You',
      v_actor_name || ' submitted a time-off request on your behalf for '
        || v_range || '.',
      false, false, 'schedule',
      'time-off-request:' || p_event_id::text || ':target'
    )
    on conflict do nothing;
    if found then
      v_target_created := true;
    end if;
  end if;

  with ins as (
    insert into public.notifications (
      user_id, company_id, type, title, body,
      is_read, persistent, deep_link_type, dedupe_key
    )
    select
      approver.id::text, v_company_id::text, 'time_off_requested',
      'Time Off Request', v_approver_body,
      false, false, 'schedule',
      'time-off-request:' || p_event_id::text || ':approver'
    from public.users_with_permission(
      v_company_id, 'time_off.approve', 'all'
    ) permitted(user_id)
    join public.users approver on approver.id = permitted.user_id
    where approver.company_id = v_company_id
      and approver.id <> v_actor_id
      and approver.id::text <> v_target
      and approver.deleted_at is null
      and coalesce(approver.is_active, false)
      and not exists (
        select 1
        from public.notifications prior
        where prior.user_id = approver.id::text
          and prior.type = 'time_off_requested'
          and prior.dedupe_key =
            'time-off-request:' || p_event_id::text || ':approver'
      )
    on conflict do nothing
    returning user_id
  )
  select coalesce(array_agg(user_id), '{}'::text[])
  into v_approvers
  from ins;

  return jsonb_build_object(
    'approver_user_ids', to_jsonb(v_approvers),
    'target_notified', v_target_created
  );
end;
$function$;

revoke all on function public.notify_time_off_requested(uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.notify_time_off_requested(uuid)
  to anon, authenticated;

-- ---------------------------------------------------------------------------
-- Inventory threshold crossed → inventory.manage holders (others,
-- non-persistent). The item row is the anchor and the server recomputes the
-- item-level threshold state itself — a normal quantity returns an empty
-- recipient list instead of raising, so the post-save call is race-safe.
-- Copy renders the shipped strings with the truncated quantity.
create or replace function public.notify_inventory_threshold_crossed(
  p_item_id uuid
) returns text[]
language plpgsql security definer
set search_path to 'pg_catalog', 'pg_temp'
as $function$
declare
  v_actor_id uuid;
  v_company_id uuid;
  v_item public.inventory_items%rowtype;
  v_status text;
  v_type text;
  v_title text;
  v_body text;
  v_created text[] := '{}'::text[];
begin
  v_actor_id := private.get_current_user_id();

  select u.company_id
  into v_company_id
  from public.users u
  where u.id = v_actor_id
    and u.company_id is not null
    and u.deleted_at is null
    and coalesce(u.is_active, false);

  if v_actor_id is null or v_company_id is null then
    raise exception 'notification actor is unavailable'
      using errcode = '42501';
  end if;

  select *
  into v_item
  from public.inventory_items i
  where i.id = p_item_id
    and i.company_id = v_company_id
    and i.deleted_at is null
  for share;

  if not found then
    raise exception 'notification inventory item is unavailable'
      using errcode = '42501';
  end if;

  if v_item.critical_threshold is not null
     and coalesce(v_item.quantity, 0) <= v_item.critical_threshold then
    v_status := 'critical';
  elsif v_item.warning_threshold is not null
        and coalesce(v_item.quantity, 0) <= v_item.warning_threshold then
    v_status := 'warning';
  else
    return v_created;
  end if;

  if v_status = 'critical' then
    v_type := 'inventory_critical';
    v_title := 'Critical Stock Alert';
    v_body := coalesce(nullif(btrim(v_item.name), ''), 'Inventory item')
      || ' is critically low ('
      || trunc(coalesce(v_item.quantity, 0))::bigint || ' remaining)';
  else
    v_type := 'inventory_warning';
    v_title := 'Low Stock Warning';
    v_body := coalesce(nullif(btrim(v_item.name), ''), 'Inventory item')
      || ' is running low ('
      || trunc(coalesce(v_item.quantity, 0))::bigint || ' remaining)';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(
    'inventory-threshold:' || p_item_id::text,
    0
  ));

  with ins as (
    insert into public.notifications (
      user_id, company_id, type, title, body,
      is_read, persistent, deep_link_type, dedupe_key
    )
    select
      manager.id::text, v_company_id::text, v_type, v_title, v_body,
      false, false, 'inventory',
      'inventory-threshold:' || p_item_id::text || ':' || v_status
    from public.users_with_permission(
      v_company_id, 'inventory.manage', 'all'
    ) permitted(user_id)
    join public.users manager on manager.id = permitted.user_id
    where manager.company_id = v_company_id
      and manager.id <> v_actor_id
      and manager.deleted_at is null
      and coalesce(manager.is_active, false)
    on conflict do nothing
    returning user_id
  )
  select coalesce(array_agg(user_id), '{}'::text[])
  into v_created
  from ins;

  return v_created;
end;
$function$;

revoke all on function public.notify_inventory_threshold_crossed(uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.notify_inventory_threshold_crossed(uuid)
  to anon, authenticated;

-- ---------------------------------------------------------------------------
-- Photo storage cap banner (self, persistent — at-most-one-unread PER
-- DEVICE). The storage cap is a per-device local cache limit, so the device
-- name is load-bearing (bug d5da3d51: the user must know WHICH device
-- filled up) and cannot be derived server-side — it is the one sanitized
-- caller string in this wave, on a row only its author receives. The client
-- keeps its 24-hour cooldown; the server guarantees the rail cannot stack
-- while one banner for that device is still unread. Resolution stays the
-- shipped lane (markAllAsReadByType on budget raise / free-up).
create or replace function public.sync_photo_storage_limit_notification(
  p_photos_remaining integer,
  p_device_name text
) returns text
language plpgsql security definer
set search_path to 'pg_catalog', 'pg_temp'
as $function$
declare
  v_actor_id uuid;
  v_company_id uuid;
  v_count integer;
  v_device text;
  v_phrase text;
  v_dedupe_key text;
begin
  v_actor_id := private.get_current_user_id();

  select u.company_id
  into v_company_id
  from public.users u
  where u.id = v_actor_id
    and u.company_id is not null
    and u.deleted_at is null
    and coalesce(u.is_active, false);

  if v_actor_id is null or v_company_id is null then
    raise exception 'notification actor is unavailable'
      using errcode = '42501';
  end if;

  v_count := least(greatest(coalesce(p_photos_remaining, 1), 1), 1000000);
  v_device := left(
    regexp_replace(btrim(coalesce(p_device_name, '')), '[[:cntrl:]]', '', 'g'),
    64
  );
  if v_device = '' then
    v_device := 'this device';
  end if;

  v_phrase := case when v_count = 1 then '1 photo' else v_count || ' photos' end;
  v_dedupe_key := 'photo-storage-limit:' || md5(v_device);

  perform pg_advisory_xact_lock(hashtextextended(
    'photo-storage:' || v_actor_id::text || ':' || md5(v_device),
    0
  ));

  if exists (
    select 1
    from public.notifications n
    where n.user_id = v_actor_id::text
      and n.type = 'photo_storage_limit'
      and n.dedupe_key = v_dedupe_key
      and n.is_read = false
  ) then
    return 'kept';
  end if;

  insert into public.notifications (
    user_id, company_id, type, title, body,
    is_read, persistent, deep_link_type, action_label, dedupe_key
  ) values (
    v_actor_id::text, v_company_id::text, 'photo_storage_limit',
    'Photo storage limit reached on ' || v_device,
    v_phrase || ' couldn''t download to ' || v_device
      || '. On that device, open Settings → Photo Storage to raise the limit or free up space.',
    false, true, 'photoStorage', 'Manage Storage', v_dedupe_key
  );
  return 'created';
end;
$function$;

revoke all on function public.sync_photo_storage_limit_notification(integer, text)
  from public, anon, authenticated, service_role;
grant execute on function public.sync_photo_storage_limit_notification(integer, text)
  to anon, authenticated;

-- ---------------------------------------------------------------------------
-- Billable-this-week nudge (self, non-persistent, at-most-one per week ANY
-- read state — the shipped dispatcher's read-or-unread remote check, now
-- owned by the server). The actor must hold finances.view at all-scope (the
-- client gate's exact shape). The rollup numbers are the client's — the
-- engine's local candidate model has no server mirror — clamped and
-- interpolated into the fixed template on a self-only row.
create or replace function public.sync_billable_week_notification(
  p_project_count integer,
  p_amount numeric,
  p_week_start date
) returns text
language plpgsql security definer
set search_path to 'pg_catalog', 'pg_temp'
as $function$
declare
  v_actor_id uuid;
  v_company_id uuid;
  v_count integer;
  v_amount numeric;
  v_jobs text;
  v_body text;
  v_dedupe_key text;
begin
  v_actor_id := private.get_current_user_id();

  select u.company_id
  into v_company_id
  from public.users u
  where u.id = v_actor_id
    and u.company_id is not null
    and u.deleted_at is null
    and coalesce(u.is_active, false);

  if v_actor_id is null or v_company_id is null then
    raise exception 'notification actor is unavailable'
      using errcode = '42501';
  end if;

  if not public.has_permission(v_actor_id, 'finances.view', 'all') then
    raise exception 'notification actor lacks finances.view'
      using errcode = '42501';
  end if;

  if p_week_start is null
     or p_week_start < (now() - interval '14 days')::date
     or p_week_start > (now() + interval '7 days')::date then
    raise exception 'billable week is out of range'
      using errcode = '22023';
  end if;

  v_count := least(greatest(coalesce(p_project_count, 1), 1), 10000);
  v_amount := least(greatest(coalesce(p_amount, 0), 0), 1000000000);
  v_dedupe_key := 'billable-week:' || to_char(p_week_start, 'YYYY-MM-DD');

  perform pg_advisory_xact_lock(hashtextextended(
    'billable-week:' || v_actor_id::text || ':' || to_char(p_week_start, 'YYYY-MM-DD'),
    0
  ));

  if exists (
    select 1
    from public.notifications n
    where n.user_id = v_actor_id::text
      and n.type = 'billable_this_week'
      and n.dedupe_key = v_dedupe_key
  ) then
    return 'kept';
  end if;

  v_jobs := v_count || ' job' || case when v_count = 1 then '' else 's' end;
  if v_amount > 0 then
    v_body := v_jobs || ' / $'
      || to_char(round(v_amount), 'FM999,999,999,990') || ' billable';
  else
    v_body := v_jobs || ' ready for billing';
  end if;

  insert into public.notifications (
    user_id, company_id, type, title, body,
    is_read, persistent, deep_link_type, action_label, dedupe_key
  ) values (
    v_actor_id::text, v_company_id::text, 'billable_this_week',
    'BILLABLE THIS WEEK', v_body,
    false, false, 'billableThisWeek', 'OPEN HOME', v_dedupe_key
  )
  on conflict do nothing;

  if found then
    return 'created';
  end if;
  return 'kept';
end;
$function$;

revoke all on function public.sync_billable_week_notification(integer, numeric, date)
  from public, anon, authenticated, service_role;
grant execute on function public.sync_billable_week_notification(integer, numeric, date)
  to anon, authenticated;

-- ---------------------------------------------------------------------------
-- Cashflow dip rail (persistent, company-wide). Recipients are finances.view
-- holders at own-scope or higher — the shipped dispatcher's exact recipient
-- shape, actor INCLUDED (a projected dip is a company condition, not an
-- actor echo). Replace-unread semantics: a dip whose rendered body changed
-- resolves the stale unread row and lands a fresh one; a byte-identical dip
-- keeps the standing row. Fire cadence stays with the client's
-- forecast_alerts ledger; the balance and week are validated numerics
-- interpolated into the fixed template. Returns the ids that received NEW
-- rows (no push lane ships today).
create or replace function public.sync_forecast_dip_notification(
  p_lowest_balance numeric,
  p_week_start date
) returns text[]
language plpgsql security definer
set search_path to 'pg_catalog', 'pg_temp'
as $function$
declare
  v_actor_id uuid;
  v_company_id uuid;
  v_balance numeric;
  v_currency text;
  v_body text;
  v_dedupe_key text;
  v_created text[] := '{}'::text[];
begin
  v_actor_id := private.get_current_user_id();

  select u.company_id
  into v_company_id
  from public.users u
  where u.id = v_actor_id
    and u.company_id is not null
    and u.deleted_at is null
    and coalesce(u.is_active, false);

  if v_actor_id is null or v_company_id is null then
    raise exception 'notification actor is unavailable'
      using errcode = '42501';
  end if;

  if p_lowest_balance is null
     or abs(p_lowest_balance) > 1000000000000
     or p_week_start is null
     or p_week_start < (now() - interval '2 years')::date
     or p_week_start > (now() + interval '2 years')::date then
    raise exception 'forecast dip inputs are out of range'
      using errcode = '22023';
  end if;

  v_balance := round(p_lowest_balance);
  if v_balance < 0 then
    v_currency := '-$' || to_char(abs(v_balance), 'FM999,999,999,999,990');
  else
    v_currency := '$' || to_char(v_balance, 'FM999,999,999,999,990');
  end if;

  v_body := 'Balance drops to ' || v_currency || ' the week of '
    || to_char(p_week_start, 'Mon FMDD') || '.';
  v_dedupe_key := 'forecast-dip:' || v_company_id::text;

  perform pg_advisory_xact_lock(hashtextextended(v_dedupe_key, 0));

  -- A dip that changed shape replaces the standing banner: resolve stale
  -- unread rows so the fresh insert clears the partial unique indexes.
  update public.notifications n
     set is_read = true
   where n.company_id = v_company_id::text
     and n.type = 'forecast_dip'
     and n.is_read = false
     and n.dedupe_key = v_dedupe_key
     and n.body is distinct from v_body;

  with ins as (
    insert into public.notifications (
      user_id, company_id, type, title, body,
      is_read, persistent, deep_link_type,
      action_url, action_label, dedupe_key
    )
    select
      holder.id::text, v_company_id::text, 'forecast_dip',
      '// CASH DIP PROJECTED', v_body,
      false, true, 'cashflow',
      '/books/cashflow', 'REVIEW FORECAST', v_dedupe_key
    from public.users_with_permission(
      v_company_id, 'finances.view', 'own'
    ) permitted(user_id)
    join public.users holder on holder.id = permitted.user_id
    where holder.company_id = v_company_id
      and holder.deleted_at is null
      and coalesce(holder.is_active, false)
      and not exists (
        select 1
        from public.notifications standing
        where standing.user_id = holder.id::text
          and standing.type = 'forecast_dip'
          and standing.is_read = false
          and standing.dedupe_key = v_dedupe_key
      )
    on conflict do nothing
    returning user_id
  )
  select coalesce(array_agg(user_id), '{}'::text[])
  into v_created
  from ins;

  return v_created;
end;
$function$;

revoke all on function public.sync_forecast_dip_notification(numeric, date)
  from public, anon, authenticated, service_role;
grant execute on function public.sync_forecast_dip_notification(numeric, date)
  to anon, authenticated;

-- ---------------------------------------------------------------------------
-- Cashflow dip cleared (non-persistent one-shot). Resolves every standing
-- unread dip banner for the company — a persistent row must not outlive its
-- condition (the legacy client left them dangling forever) — then confirms
-- the clear to the same permission-derived audience.
create or replace function public.sync_forecast_cleared_notification(
) returns text[]
language plpgsql security definer
set search_path to 'pg_catalog', 'pg_temp'
as $function$
declare
  v_actor_id uuid;
  v_company_id uuid;
  v_created text[] := '{}'::text[];
begin
  v_actor_id := private.get_current_user_id();

  select u.company_id
  into v_company_id
  from public.users u
  where u.id = v_actor_id
    and u.company_id is not null
    and u.deleted_at is null
    and coalesce(u.is_active, false);

  if v_actor_id is null or v_company_id is null then
    raise exception 'notification actor is unavailable'
      using errcode = '42501';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(
    'forecast-dip:' || v_company_id::text,
    0
  ));

  update public.notifications n
     set is_read = true
   where n.company_id = v_company_id::text
     and n.type = 'forecast_dip'
     and n.is_read = false;

  with ins as (
    insert into public.notifications (
      user_id, company_id, type, title, body,
      is_read, persistent, deep_link_type,
      action_url, action_label, dedupe_key
    )
    select
      holder.id::text, v_company_id::text, 'forecast_cleared',
      '// CASH DIP CLEARED',
      'Projected balance now stays positive across the forecast horizon.',
      false, false, 'cashflow',
      '/books/cashflow', 'VIEW FORECAST',
      'forecast-cleared:' || v_company_id::text
    from public.users_with_permission(
      v_company_id, 'finances.view', 'own'
    ) permitted(user_id)
    join public.users holder on holder.id = permitted.user_id
    where holder.company_id = v_company_id
      and holder.deleted_at is null
      and coalesce(holder.is_active, false)
    on conflict do nothing
    returning user_id
  )
  select coalesce(array_agg(user_id), '{}'::text[])
  into v_created
  from ins;

  return v_created;
end;
$function$;

revoke all on function public.sync_forecast_cleared_notification()
  from public, anon, authenticated, service_role;
grant execute on function public.sync_forecast_cleared_notification()
  to anon, authenticated;
