-- iOS Catalog Phase 6 estimate-acceptance project/task sync helper.
-- Review-gate draft only. Do not apply without explicit PM approval.
--
-- This migration intentionally does not create public.accept_estimate_to_job.
-- Material demand is not implemented here, so the public acceptance RPC must
-- wait until projected demand, allocations, snapshots, and notifications can
-- commit in the same transaction.
--
-- Execution model: this helper is private-schema only but must execute as the
-- authenticated caller through the P6-6 SECURITY INVOKER acceptance wrapper.
-- It depends on authenticated-user permission helpers, so keep execution on
-- the authenticated acceptance path.

begin;

do $$
begin
  if exists (
    select 1
      from public.projects project_row
     where project_row.opportunity_id is not null
       and project_row.deleted_at is null
     group by project_row.company_id, project_row.opportunity_id
    having count(*) > 1
  ) then
    raise exception 'duplicate_active_projects_for_opportunity'
      using errcode = '23505';
  end if;

  if exists (
    select 1
      from public.project_tasks task_row
     where task_row.source_estimate_id is not null
       and task_row.source_line_item_id is not null
       and task_row.deleted_at is null
     group by
       task_row.company_id,
       task_row.project_id,
       task_row.source_estimate_id,
       task_row.source_line_item_id
    having count(*) > 1
  ) then
    raise exception 'duplicate_active_project_tasks_for_estimate_line'
      using errcode = '23505';
  end if;

  if exists (
    select 1
      from public.project_photos photo_row
     where photo_row.source = 'site_visit'
       and photo_row.site_visit_id is not null
       and photo_row.deleted_at is null
     group by
       photo_row.company_id,
       photo_row.project_id,
       photo_row.site_visit_id,
       photo_row.url
    having count(*) > 1
  ) then
    raise exception 'duplicate_active_site_visit_project_photos'
      using errcode = '23505';
  end if;
end;
$$;

create unique index if not exists projects_active_opportunity_id_key
  on public.projects(company_id, opportunity_id)
  where deleted_at is null
    and opportunity_id is not null;

create unique index if not exists project_tasks_active_estimate_line_key
  on public.project_tasks(
    company_id,
    project_id,
    source_estimate_id,
    source_line_item_id
  )
  where deleted_at is null
    and source_estimate_id is not null
    and source_line_item_id is not null;

create unique index if not exists project_photos_active_site_visit_url_key
  on public.project_photos(company_id, project_id, site_visit_id, url)
  where deleted_at is null
    and source = 'site_visit'
    and site_visit_id is not null;

create or replace function private.sync_accepted_estimate_project_tasks(
  p_estimate_id uuid
)
returns jsonb
language plpgsql
security invoker
set search_path to 'public', 'private', 'pg_temp'
as $$
declare
  v_now timestamptz := now();
  v_actor_user_id uuid;
  v_actor_auth_id uuid;
  v_actor_company_id uuid;
  v_estimate public.estimates%rowtype;
  v_estimate_scope text;
  v_opportunity public.opportunities%rowtype;
  v_project_id uuid;
  v_project_title text;
  v_project_address text;
  v_project_created boolean := false;
  v_stage_transition_inserted boolean := false;
  v_required_task_count integer := 0;
  v_inserted_task_count integer := 0;
  v_verified_task_count integer := 0;
  v_attached_photo_count integer := 0;
  v_linked_site_visit_count integer := 0;
begin
  if p_estimate_id is null then
    raise exception 'estimate_id_required' using errcode = '22023';
  end if;

  v_actor_user_id := private.get_current_user_id();
  v_actor_auth_id := auth.uid();

  if v_actor_user_id is null or v_actor_auth_id is null then
    raise exception 'actor_not_found' using errcode = '42501';
  end if;

  select user_row.company_id
    into v_actor_company_id
    from public.users user_row
   where user_row.id = v_actor_user_id
     and user_row.deleted_at is null
   limit 1;

  if v_actor_company_id is null then
    raise exception 'actor_company_not_found' using errcode = '42501';
  end if;

  select estimate_row.*
    into v_estimate
    from public.estimates estimate_row
   where estimate_row.id = p_estimate_id
     and estimate_row.deleted_at is null
   for update;

  if not found then
    raise exception 'estimate_not_found' using errcode = 'P0002';
  end if;

  if v_estimate.company_id is distinct from v_actor_company_id
     or v_estimate.company_id is distinct from private.get_user_company_id() then
    raise exception 'estimate_company_scope_mismatch' using errcode = '42501';
  end if;

  v_estimate_scope := private.current_user_scope_for('estimates.edit');

  if not private.current_user_is_admin()
     and not (
       v_estimate_scope = 'all'
       or (
         v_estimate_scope = 'own'
         and (
           v_estimate.created_by = v_actor_user_id
           or v_estimate.created_by = v_actor_auth_id
         )
       )
     ) then
    raise exception 'estimates_edit_required' using errcode = '42501';
  end if;

  if not private.current_user_has_permission('projects.create', 'all') then
    raise exception 'projects_create_required' using errcode = '42501';
  end if;

  if not private.current_user_has_permission('projects.edit', 'all') then
    raise exception 'projects_edit_required' using errcode = '42501';
  end if;

  if not private.current_user_has_permission('tasks.create', 'all') then
    raise exception 'tasks_create_required' using errcode = '42501';
  end if;

  if not private.current_user_has_permission('pipeline.manage', 'all') then
    raise exception 'pipeline_manage_required' using errcode = '42501';
  end if;

  if v_estimate.status not in ('draft', 'sent', 'viewed', 'approved', 'converted') then
    raise exception 'estimate_status_not_acceptance_eligible'
      using errcode = '22023';
  end if;

  if v_estimate.opportunity_id is null then
    raise exception 'estimate_opportunity_required' using errcode = '22023';
  end if;

  select opportunity_row.*
    into v_opportunity
    from public.opportunities opportunity_row
   where opportunity_row.id = v_estimate.opportunity_id
     and opportunity_row.deleted_at is null
   for update;

  if not found then
    raise exception 'opportunity_not_found' using errcode = 'P0002';
  end if;

  if v_opportunity.company_id is distinct from v_estimate.company_id then
    raise exception 'opportunity_company_scope_mismatch'
      using errcode = '42501';
  end if;

  v_project_title := coalesce(
    nullif(v_estimate.title, ''),
    nullif(v_opportunity.title, ''),
    'Accepted estimate'
  );
  v_project_address := nullif(v_opportunity.address, '');

  select project_row.id
    into v_project_id
    from public.projects project_row
   where project_row.company_id = v_estimate.company_id
     and project_row.deleted_at is null
     and (
       project_row.id = v_estimate.project_ref
       or project_row.id = (
         case
           when v_estimate.project_id ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
             then v_estimate.project_id::uuid
           else null
         end
       )
       or project_row.id = v_opportunity.project_ref
       or project_row.id = v_opportunity.project_id
       or project_row.opportunity_id = v_opportunity.id::text
     )
   order by
     case
       when project_row.id = v_opportunity.project_ref then 1
       when project_row.id = v_opportunity.project_id then 2
       when project_row.opportunity_id = v_opportunity.id::text then 3
       when project_row.id = v_estimate.project_ref then 4
       else 5
     end
   limit 1
   for update;

  if v_project_id is null then
    v_project_created := true;

    insert into public.projects (
      id,
      company_id,
      client_id,
      opportunity_id,
      title,
      address,
      status,
      created_by,
      created_at,
      updated_at
    ) values (
      gen_random_uuid(),
      v_estimate.company_id,
      coalesce(v_opportunity.client_id, v_estimate.client_id),
      v_opportunity.id::text,
      v_project_title,
      v_project_address,
      'accepted',
      v_actor_auth_id,
      v_now,
      v_now
    )
    on conflict (company_id, opportunity_id)
      where deleted_at is null
        and opportunity_id is not null
    do update
      set client_id = coalesce(
            public.projects.client_id,
            excluded.client_id
          ),
          title = coalesce(nullif(public.projects.title, ''), excluded.title),
          address = coalesce(public.projects.address, excluded.address),
          status = case
            when public.projects.status in ('rfq', 'estimated')
              then 'accepted'
            else public.projects.status
          end,
          updated_at = v_now
    returning id
      into v_project_id;
  else
    update public.projects project_row
       set opportunity_id = coalesce(project_row.opportunity_id, v_opportunity.id::text),
           client_id = coalesce(project_row.client_id, v_opportunity.client_id, v_estimate.client_id),
           title = coalesce(nullif(project_row.title, ''), v_project_title),
           address = coalesce(project_row.address, v_project_address),
           status = case
             when project_row.status in ('rfq', 'estimated')
               then 'accepted'
             else project_row.status
           end,
           updated_at = v_now
     where project_row.id = v_project_id;
  end if;

  update public.estimates estimate_row
     set status = case
           when estimate_row.status = 'converted'
             then estimate_row.status
           else 'approved'
         end,
         approved_at = coalesce(estimate_row.approved_at, v_now),
         project_id = v_project_id::text,
         project_ref = v_project_id,
         updated_at = v_now
   where estimate_row.id = v_estimate.id;

  if v_opportunity.stage <> 'won' then
    insert into public.stage_transitions (
      company_id,
      opportunity_id,
      from_stage,
      to_stage,
      transitioned_at,
      transitioned_by,
      duration_in_stage
    ) values (
      v_estimate.company_id,
      v_opportunity.id,
      v_opportunity.stage,
      'won',
      v_now,
      v_actor_user_id,
      v_now - v_opportunity.stage_entered_at
    );

    v_stage_transition_inserted := true;
  end if;

  update public.opportunities opportunity_row
     set stage = 'won',
         stage_entered_at = case
           when opportunity_row.stage = 'won'
             then opportunity_row.stage_entered_at
           else v_now
         end,
         stage_manually_set = true,
         actual_value = coalesce(opportunity_row.actual_value, v_estimate.total),
         actual_close_date = coalesce(opportunity_row.actual_close_date, v_now::date),
         project_id = v_project_id,
         project_ref = v_project_id,
         updated_at = v_now
   where opportunity_row.id = v_opportunity.id;

  with accepted_lines as (
    select
      line_item.id,
      line_item.task_type_ref,
      line_item.name,
      coalesce(line_item.sort_order, 0) as sort_order,
      coalesce(task_type.default_duration, 1) as default_duration,
      coalesce(task_type.color, '#417394') as default_color
    from public.line_items line_item
    left join public.task_types task_type
      on task_type.id = line_item.task_type_ref
    where line_item.estimate_id = v_estimate.id
      and line_item.company_id = v_estimate.company_id
      and line_item.type = 'LABOR'
      and coalesce(line_item.is_selected, true) = true
  ),
  updated_tasks as (
    update public.project_tasks task_row
       set task_type_id = coalesce(task_row.task_type_id, accepted_lines.task_type_ref),
           custom_title = coalesce(nullif(task_row.custom_title, ''), accepted_lines.name),
           display_order = coalesce(task_row.display_order, accepted_lines.sort_order),
           duration = coalesce(task_row.duration, accepted_lines.default_duration),
           task_color = coalesce(nullif(task_row.task_color, ''), accepted_lines.default_color),
           updated_at = v_now
      from accepted_lines
     where task_row.company_id = v_estimate.company_id
       and task_row.project_id = v_project_id
       and task_row.source_estimate_id = v_estimate.id::text
       and task_row.source_line_item_id = accepted_lines.id::text
       and task_row.deleted_at is null
       and (
         (task_row.task_type_id is null and accepted_lines.task_type_ref is not null)
         or nullif(task_row.custom_title, '') is null
         or task_row.display_order is null
         or task_row.duration is null
         or nullif(task_row.task_color, '') is null
       )
    returning task_row.id
  ),
  inserted_tasks as (
    insert into public.project_tasks (
      id,
      company_id,
      project_id,
      task_type_id,
      custom_title,
      source_line_item_id,
      source_estimate_id,
      status,
      display_order,
      duration,
      task_color,
      created_at,
      updated_at
    )
    select
      gen_random_uuid(),
      v_estimate.company_id,
      v_project_id,
      accepted_lines.task_type_ref,
      accepted_lines.name,
      accepted_lines.id::text,
      v_estimate.id::text,
      'active',
      accepted_lines.sort_order,
      accepted_lines.default_duration,
      accepted_lines.default_color,
      v_now,
      v_now
    from accepted_lines
    where not exists (
      select 1
        from public.project_tasks existing_task
       where existing_task.company_id = v_estimate.company_id
         and existing_task.project_id = v_project_id
         and existing_task.source_estimate_id = v_estimate.id::text
         and existing_task.source_line_item_id = accepted_lines.id::text
         and existing_task.deleted_at is null
    )
    on conflict (company_id, project_id, source_estimate_id, source_line_item_id)
      where deleted_at is null
        and source_estimate_id is not null
        and source_line_item_id is not null
    do nothing
    returning id
  )
  select
    (select count(*) from accepted_lines),
    (select count(*) from inserted_tasks)
  into v_required_task_count, v_inserted_task_count;

  select count(*)
    into v_verified_task_count
    from public.project_tasks task_row
   where task_row.company_id = v_estimate.company_id
     and task_row.project_id = v_project_id
     and task_row.source_estimate_id = v_estimate.id::text
     and task_row.source_line_item_id is not null
     and task_row.deleted_at is null
     and exists (
       select 1
         from public.line_items line_item
        where line_item.id::text = task_row.source_line_item_id
          and line_item.estimate_id = v_estimate.id
          and line_item.company_id = v_estimate.company_id
          and line_item.type = 'LABOR'
          and coalesce(line_item.is_selected, true) = true
     );

  if v_verified_task_count <> v_required_task_count then
    raise exception 'accepted_estimate_task_sync_incomplete'
      using errcode = '23514';
  end if;

  with linked_visits as (
    update public.site_visits visit_row
       set project_id = v_project_id::text,
           project_ref = v_project_id,
           updated_at = v_now
     where visit_row.opportunity_id = v_opportunity.id
       and visit_row.company_id = v_estimate.company_id::text
       and visit_row.deleted_at is null
       and (
         visit_row.project_ref is distinct from v_project_id
         or visit_row.project_id is distinct from v_project_id::text
       )
    returning visit_row.id
  ),
  inserted_photos as (
    insert into public.project_photos (
      id,
      project_id,
      company_id,
      url,
      source,
      site_visit_id,
      uploaded_by,
      taken_at,
      created_at
    )
    select
      gen_random_uuid(),
      v_project_id::text,
      v_estimate.company_id::text,
      photo_url,
      'site_visit',
      visit_row.id,
      v_actor_user_id::text,
      null,
      v_now
    from public.site_visits visit_row
    cross join lateral unnest(visit_row.photos) as photo_url
    where visit_row.opportunity_id = v_opportunity.id
      and visit_row.company_id = v_estimate.company_id::text
      and visit_row.deleted_at is null
      and photo_url is not null
      and photo_url <> ''
    on conflict (company_id, project_id, site_visit_id, url)
      where deleted_at is null
        and source = 'site_visit'
        and site_visit_id is not null
    do nothing
    returning id
  )
  select
    (select count(*) from linked_visits),
    (select count(*) from inserted_photos)
  into v_linked_site_visit_count, v_attached_photo_count;

  return jsonb_build_object(
    'ok', true,
    'estimate_id', v_estimate.id,
    'opportunity_id', v_opportunity.id,
    'project_id', v_project_id,
    'project_created', v_project_created,
    'project_task_count', v_verified_task_count,
    'inserted_task_count', v_inserted_task_count,
    'stage_transition_inserted', v_stage_transition_inserted,
    'linked_site_visit_count', v_linked_site_visit_count,
    'attached_photo_count', v_attached_photo_count,
    'material_demand_performed', false
  );
end;
$$;

revoke all on function private.sync_accepted_estimate_project_tasks(uuid)
  from public, anon, authenticated, service_role;
grant execute on function private.sync_accepted_estimate_project_tasks(uuid)
  to authenticated;

comment on function private.sync_accepted_estimate_project_tasks(uuid)
  is 'Private Phase 6 helper for accepted-estimate project/task synchronization. It runs as the authenticated caller, derives the actor server-side, creates or reuses the lead-backed project, links the accepted estimate, verifies LABOR-derived tasks, attaches site-visit photos with the accepting actor as uploaded_by for RLS, and performs no material demand work.';

commit;
