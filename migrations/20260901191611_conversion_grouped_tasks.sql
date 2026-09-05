-- Task groups — conversion paths (lead→project, estimate acceptance) can compose sold
-- LABOR line items into visits, gated per company by companies.task_groups_conversion_enabled
-- (default false ⇒ byte-identical legacy behavior). The material demand plan maps a line
-- carried as a scope to its grouped task. See ops-software-bible/specs/2026-09-01-task-groups-design.md.
alter table public.companies add column if not exists task_groups_conversion_enabled boolean not null default false;
comment on column public.companies.task_groups_conversion_enabled is 'Rollout gate: when true, lead/estimate conversion composes LABOR line items into grouped tasks (task_scopes). Flipped per company by SQL only after its crew builds render scopes. Not a product setting.';

create or replace function private.materialize_line_item_tasks_grouped(p_company_id uuid, p_project_id uuid, p_lines jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog', 'public', 'private', 'pg_temp'
as $$
declare
  v_now timestamptz := now();
  v_line jsonb;
  v_estimate_id text;
  v_composition jsonb;
  v_visit jsonb;
  v_scope jsonb;
  v_primary_line jsonb;
  v_task_id uuid;
  v_task_ids uuid[] := array[]::uuid[];
  v_task_count integer := 0;
  v_scope_count integer := 0;
  v_scopes_payload jsonb;
  v_pending jsonb;
begin
  if p_company_id is null or p_project_id is null then
    raise exception 'materialize_company_project_required' using errcode = '22023';
  end if;
  if p_lines is null or jsonb_typeof(p_lines) <> 'array' then
    raise exception 'materialize_lines_array_required' using errcode = '22023';
  end if;

  -- Lines already carried by a live task (as its provenance) or by a live scope are done.
  select coalesce(jsonb_agg(l.elem order by l.ord), '[]'::jsonb)
    into v_pending
    from jsonb_array_elements(p_lines) with ordinality as l(elem, ord)
   where not exists (
           select 1 from public.project_tasks pt
            where pt.company_id = p_company_id
              and pt.project_id = p_project_id
              and pt.deleted_at is null
              and pt.source_line_item_id = l.elem ->> 'line_item_id')
     and not exists (
           select 1 from public.task_scopes s
             join public.project_tasks st on st.id = s.task_id
            where s.company_id = p_company_id
              and s.deleted_at is null
              and s.source_line_item_id = l.elem ->> 'line_item_id'
              and st.project_id = p_project_id
              and st.deleted_at is null);

  -- Untyped LABOR lines cannot be composed: one task each, exactly as the legacy path.
  for v_line in select elem from jsonb_array_elements(v_pending) as l(elem) where nullif(l.elem ->> 'task_type_ref', '') is null loop
    v_task_id := gen_random_uuid();
    insert into public.project_tasks (id, company_id, project_id, task_type_id, custom_title, source_line_item_id, source_estimate_id, status, display_order, duration, task_color, team_member_ids, created_at, updated_at)
    values (v_task_id, p_company_id, p_project_id, null, v_line ->> 'name', v_line ->> 'line_item_id', v_line ->> 'estimate_id', 'active', coalesce((v_line ->> 'sort_order')::integer, 0), coalesce((v_line ->> 'default_duration')::integer, 1), coalesce(nullif(v_line ->> 'default_color', ''), '#417394'), array[]::text[], v_now, v_now);
    v_task_ids := v_task_ids || v_task_id;
    v_task_count := v_task_count + 1;
  end loop;

  -- Typed lines compose per estimate (a task carries one source_estimate_id).
  for v_estimate_id in select distinct l.elem ->> 'estimate_id' from jsonb_array_elements(v_pending) as l(elem) where nullif(l.elem ->> 'task_type_ref', '') is not null order by 1 loop
    select public.compose_task_scopes(
             p_company_id,
             (select jsonb_agg(jsonb_build_object('task_type_id', l.elem ->> 'task_type_ref', 'note', l.elem ->> 'name', 'source_line_item_id', l.elem ->> 'line_item_id')
                               order by coalesce((l.elem ->> 'sort_order')::integer, 0), l.elem ->> 'line_item_id')
                from jsonb_array_elements(v_pending) as l(elem)
               where nullif(l.elem ->> 'task_type_ref', '') is not null
                 and l.elem ->> 'estimate_id' is not distinct from v_estimate_id))
      into v_composition;

    for v_visit in select elem from jsonb_array_elements(v_composition -> 'visits') as v(elem) loop
      v_scope := v_visit -> 'scopes' -> 0;
      select l.elem into v_primary_line from jsonb_array_elements(v_pending) as l(elem) where l.elem ->> 'line_item_id' = v_scope ->> 'source_line_item_id' limit 1;
      v_task_id := gen_random_uuid();
      insert into public.project_tasks (id, company_id, project_id, task_type_id, custom_title, source_line_item_id, source_estimate_id, status, display_order, duration, task_color, team_member_ids, created_at, updated_at)
      values (
        v_task_id, p_company_id, p_project_id,
        (v_visit ->> 'primary_task_type_id')::uuid,
        case when jsonb_array_length(v_visit -> 'scopes') > 1 then null else v_primary_line ->> 'name' end,
        v_primary_line ->> 'line_item_id',
        v_primary_line ->> 'estimate_id',
        'active',
        coalesce((v_primary_line ->> 'sort_order')::integer, 0),
        coalesce((v_primary_line ->> 'default_duration')::integer, 1),
        coalesce(nullif(v_primary_line ->> 'default_color', ''), '#417394'),
        array[]::text[], v_now, v_now);
      v_task_ids := v_task_ids || v_task_id;
      v_task_count := v_task_count + 1;

      if jsonb_array_length(v_visit -> 'scopes') > 1 then
        select jsonb_agg(jsonb_build_object('task_type_id', s.elem ->> 'task_type_id', 'note', s.elem ->> 'note', 'source_line_item_id', s.elem ->> 'source_line_item_id', 'display_order', s.ord - 1) order by s.ord)
          into v_scopes_payload
          from jsonb_array_elements(v_visit -> 'scopes') with ordinality as s(elem, ord);
        v_scope_count := v_scope_count + private.insert_task_scopes(v_task_id, p_company_id, (v_visit ->> 'primary_task_type_id')::uuid, v_scopes_payload);
      end if;
    end loop;
  end loop;

  return jsonb_build_object('task_count', v_task_count, 'scope_count', v_scope_count, 'task_ids', to_jsonb(v_task_ids));
end;
$$;
revoke all on function private.materialize_line_item_tasks_grouped(uuid, uuid, jsonb) from public, anon, authenticated;

CREATE OR REPLACE FUNCTION private.execute_opportunity_conversion_core(p_company_id uuid, p_opportunity_id uuid, p_actual_value numeric DEFAULT NULL::numeric, p_expected_stage text DEFAULT NULL::text, p_decided_by uuid DEFAULT NULL::uuid, p_notes text DEFAULT NULL::text, p_title_override text DEFAULT NULL::text, p_link_to_project_id uuid DEFAULT NULL::uuid, p_source_path text DEFAULT NULL::text, p_win_opportunity boolean DEFAULT true, p_project_status text DEFAULT NULL::text, p_evidence jsonb DEFAULT '{}'::jsonb, p_expected_assignment_version bigint DEFAULT NULL::bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'private', 'pg_temp'
AS $function$
declare
  v_opp public.opportunities%rowtype;
  v_is_service boolean := coalesce(auth.role(), '') = 'service_role';
  v_actor_user_id uuid;
  v_actor_company_id uuid;
  v_decided_by uuid;
  v_convert_scope text;
  v_project_id uuid;
  v_project_opportunity_ref uuid;
  v_project_opportunity_id text;
  v_status text;
  v_value numeric;
  v_platform jsonb;
  v_disposition_id uuid;
  v_conversion_event_id uuid;
  v_relinked bigint := 0;
  v_tasks bigint := 0;
  v_photos bigint := 0;
  v_lead_photos bigint := 0;
  v_decks bigint := 0;
  v_won boolean := false;
  v_already_converted boolean := false;
  v_linked_existing boolean := p_link_to_project_id is not null;
  v_created_by uuid;
  v_groups_enabled boolean := false;
  v_grouped jsonb;
begin
  if p_company_id is null or p_opportunity_id is null then
    raise exception 'company and opportunity ids are required'
      using errcode = '22023';
  end if;

  -- Assignment authorization and every optimistic guard are evaluated from
  -- this one locked snapshot. No link, stage, disposition, projection, or
  -- conversion event is written before the guards below have passed.
  select *
    into v_opp
    from public.opportunities o
   where o.id = p_opportunity_id
     and o.company_id = p_company_id
   for update;

  if not found then
    raise exception 'opportunity_not_found'
      using errcode = 'P0002';
  end if;
  if v_opp.deleted_at is not null then
    raise exception 'opportunity is soft-deleted'
      using errcode = '22023';
  end if;

  if v_is_service then
    -- Service callers may omit an actor for system work. If supplied, the
    -- actor is always an active same-company OPS public.users.id.
    if p_decided_by is not null then
      perform 1
        from public.users service_actor
       where service_actor.id = p_decided_by
         and service_actor.company_id = p_company_id
         and service_actor.deleted_at is null
         and coalesce(service_actor.is_active, false)
       for share;
      if not found then
        raise exception 'conversion_actor_ineligible'
          using errcode = '22023';
      end if;
    end if;
    v_actor_user_id := p_decided_by;
    v_actor_company_id := p_company_id;
    v_decided_by := p_decided_by;
  else
    v_actor_user_id := private.get_current_user_id();
    v_actor_company_id := private.get_user_company_id();

    if v_actor_user_id is null
      or v_actor_company_id is null
      or v_actor_company_id is distinct from p_company_id
      or not exists (
        select 1
          from public.users actor_user
         where actor_user.id = v_actor_user_id
           and actor_user.company_id = p_company_id
           and actor_user.deleted_at is null
           and coalesce(actor_user.is_active, false)
      )
    then
      raise exception 'access_denied'
        using errcode = '42501';
    end if;

    if p_decided_by is not null
      and p_decided_by is distinct from v_actor_user_id
    then
      raise exception 'access_denied'
        using errcode = '42501';
    end if;

    -- Human attribution is server-derived even when the caller omits the
    -- legacy p_decided_by argument.
    v_decided_by := v_actor_user_id;
    v_convert_scope := private.current_user_scope_for('pipeline.convert');
    if v_convert_scope is null
      and private.should_use_pipeline_manage_compat(
        v_actor_user_id,
        v_actor_company_id,
        'pipeline.convert'
      )
    then
      v_convert_scope := 'all';
    end if;

    if v_convert_scope = 'assigned'
      and v_opp.assigned_to is distinct from v_actor_user_id
    then
      raise exception 'access_denied'
        using errcode = '42501';
    elsif v_convert_scope is distinct from 'all'
      and v_convert_scope is distinct from 'assigned'
    then
      raise exception 'access_denied'
        using errcode = '42501';
    end if;
  end if;

  if p_expected_assignment_version is not null
    and v_opp.assignment_version is distinct from p_expected_assignment_version
  then
    return jsonb_build_object(
      'converted', false,
      'already_converted', false,
      'guard_reason', 'assignment_snapshot_mismatch',
      'opportunity_id', p_opportunity_id,
      'assigned_to', v_opp.assigned_to,
      'assignment_version', v_opp.assignment_version
    );
  end if;

  if p_expected_stage is not null
    and v_opp.stage is distinct from p_expected_stage
  then
    return jsonb_build_object(
      'converted', false,
      'already_converted', false,
      'guard_reason', 'snapshot_mismatch',
      'opportunity_id', p_opportunity_id,
      'assigned_to', v_opp.assigned_to,
      'assignment_version', v_opp.assignment_version
    );
  end if;

  if v_opp.project_ref is not null
    and v_opp.project_id is not null
    and v_opp.project_ref is distinct from v_opp.project_id
  then
    raise exception 'opportunity project mirrors disagree'
      using errcode = '23505';
  end if;

  v_project_id := coalesce(v_opp.project_ref, v_opp.project_id);
  if v_project_id is not null then
    v_already_converted := true;

    if p_link_to_project_id is not null
      and p_link_to_project_id is distinct from v_project_id
    then
      raise exception 'opportunity is already linked to another project'
        using errcode = '23505';
    end if;

    select p.opportunity_ref, p.opportunity_id
      into v_project_opportunity_ref, v_project_opportunity_id
      from public.projects p
     where p.id = v_project_id
       and p.company_id = p_company_id
       and p.deleted_at is null
     for update;
    if not found then
      raise exception 'linked project not found in opportunity company'
        using errcode = 'P0002';
    end if;
    if v_project_opportunity_ref is not null
      and v_project_opportunity_ref is distinct from p_opportunity_id
    then
      raise exception 'linked project belongs to another opportunity'
        using errcode = '23505';
    end if;
    if v_project_opportunity_ref is null
      and v_project_opportunity_id is not null
      and btrim(v_project_opportunity_id) ~*
        '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
      and v_project_opportunity_id::uuid is distinct from p_opportunity_id
    then
      raise exception 'linked project legacy mirror belongs to another opportunity'
        using errcode = '23505';
    end if;
  elsif p_link_to_project_id is not null then
    select p.id, p.opportunity_ref, p.opportunity_id
      into v_project_id, v_project_opportunity_ref, v_project_opportunity_id
      from public.projects p
     where p.id = p_link_to_project_id
       and p.company_id = p_company_id
       and p.deleted_at is null
     for update;
    if not found then
      raise exception 'link target project not found'
        using errcode = 'P0002';
    end if;
    if v_project_opportunity_ref is not null
      and v_project_opportunity_ref is distinct from p_opportunity_id
    then
      raise exception 'link target project already belongs to another opportunity'
        using errcode = '23505';
    end if;
    if v_project_opportunity_ref is null
      and v_project_opportunity_id is not null
      and btrim(v_project_opportunity_id) ~*
        '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
      and v_project_opportunity_id::uuid is distinct from p_opportunity_id
    then
      raise exception 'link target project legacy mirror belongs to another opportunity'
        using errcode = '23505';
    end if;
  else
    v_status := coalesce(
      p_project_status,
      case when p_win_opportunity then 'accepted' else 'rfq' end
    );
    v_value := coalesce(
      p_actual_value,
      v_opp.actual_value,
      v_opp.estimated_value
    );
    v_platform := case
      when v_opp.source is not null or v_opp.source_email_id is not null
        then jsonb_build_object(
          'source', v_opp.source,
          'source_email_id', v_opp.source_email_id
        )
      else null
    end;

    -- projects.created_by references auth.users.id. Map the validated OPS
    -- actor only through canonical auth_id/firebase_uid identities; an actor
    -- without a UUID-backed auth row leaves creator attribution null.
    if v_actor_user_id is not null then
      select au.id
        into v_created_by
        from public.users actor_user
        join auth.users au
          on au.id::text = actor_user.auth_id
          or au.id::text = actor_user.firebase_uid
       where actor_user.id = v_actor_user_id
         and actor_user.company_id = p_company_id
         and actor_user.deleted_at is null
         and coalesce(actor_user.is_active, false)
       order by case
         when au.id::text = actor_user.auth_id then 0
         else 1
       end
       limit 1;
    end if;

    v_project_id := gen_random_uuid();
  end if;

  -- Mint exactly one private marker for the immediately following project
  -- write. The AFTER trigger consumes it; the BEFORE normalizer still runs.
  if v_already_converted or p_link_to_project_id is not null then
    insert into private.opportunity_conversion_project_link_tokens (
      transaction_id,
      backend_pid,
      project_id,
      opportunity_id,
      company_id,
      operation
    ) values (
      txid_current(),
      pg_backend_pid(),
      v_project_id,
      p_opportunity_id,
      p_company_id,
      'update'
    );

    update public.projects
       set opportunity_ref = p_opportunity_id,
           opportunity_id = p_opportunity_id::text,
           updated_at = now()
     where id = v_project_id
       and company_id = p_company_id;
    if not found then
      raise exception 'conversion project link update matched zero rows'
        using errcode = 'P0002';
    end if;
  else
    insert into private.opportunity_conversion_project_link_tokens (
      transaction_id,
      backend_pid,
      project_id,
      opportunity_id,
      company_id,
      operation
    ) values (
      txid_current(),
      pg_backend_pid(),
      v_project_id,
      p_opportunity_id,
      p_company_id,
      'insert'
    );

    insert into public.projects (
      id,
      company_id,
      client_id,
      opportunity_id,
      opportunity_ref,
      title,
      title_is_auto,
      address,
      latitude,
      longitude,
      status,
      source,
      estimated_value,
      platform_metadata,
      notes,
      team_member_ids,
      created_by,
      created_at,
      updated_at
    ) values (
      v_project_id,
      p_company_id,
      v_opp.client_id,
      p_opportunity_id::text,
      p_opportunity_id,
      coalesce(p_title_override, 'New project'),
      p_title_override is null,
      v_opp.address,
      v_opp.latitude,
      v_opp.longitude,
      v_status,
      v_opp.source,
      v_value,
      v_platform,
      p_notes,
      array[]::text[],
      v_created_by,
      now(),
      now()
    );
  end if;

  update public.opportunities
     set project_ref = v_project_id,
         project_id = v_project_id,
         updated_at = now()
   where id = p_opportunity_id
     and company_id = p_company_id
     and (project_ref is null or project_ref = v_project_id)
     and (project_id is null or project_id = v_project_id);
  if not found then
    raise exception 'opportunity link update matched zero rows (concurrent conversion?)'
      using errcode = 'P0002';
  end if;

  -- Common idempotent conversion projections. This block intentionally runs
  -- for both first conversions and already-converted repair calls.
  update public.estimates
     set project_ref = v_project_id,
         project_id = v_project_id::text,
         updated_at = now()
   where opportunity_id = p_opportunity_id
     and company_id = p_company_id
     and deleted_at is null;
  get diagnostics v_relinked = row_count;

  select coalesce(company_row.task_groups_conversion_enabled, false)
    into v_groups_enabled
    from public.companies company_row
   where company_row.id = p_company_id;

  if not coalesce(v_groups_enabled, false) then
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
    team_member_ids,
    created_at,
    updated_at
  )
  select
    gen_random_uuid(),
    p_company_id,
    v_project_id,
    li.task_type_ref,
    li.name,
    li.id::text,
    li.estimate_id::text,
    'active',
    coalesce(li.sort_order, 0),
    coalesce(tt.default_duration, 1),
    coalesce(tt.color, '#417394'),
    array[]::text[],
    now(),
    now()
  from public.line_items li
  left join public.task_types tt on tt.id = li.task_type_ref
  where li.estimate_id in (
    select e.id
      from public.estimates e
     where e.opportunity_id = p_opportunity_id
       and e.company_id = p_company_id
       and e.deleted_at is null
  )
    and li.company_id = p_company_id
    and li.type = 'LABOR'
    and not exists (
      select 1
        from public.project_tasks pt
       where pt.project_id = v_project_id
         and pt.source_line_item_id = li.id::text
    );
  get diagnostics v_tasks = row_count;
  else
    -- Task groups rollout gate ON: sold LABOR lines compose into visits
    -- (predecessors sequenced, same-crew leaves grouped into one task + scopes).
    v_grouped := private.materialize_line_item_tasks_grouped(
      p_company_id,
      v_project_id,
      (select coalesce(jsonb_agg(jsonb_build_object(
                 'line_item_id', li.id::text,
                 'estimate_id', li.estimate_id::text,
                 'task_type_ref', li.task_type_ref::text,
                 'name', li.name,
                 'sort_order', coalesce(li.sort_order, 0),
                 'default_duration', coalesce(tt.default_duration, 1),
                 'default_color', coalesce(tt.color, '#417394')
               ) order by li.estimate_id, coalesce(li.sort_order, 0), li.id), '[]'::jsonb)
         from public.line_items li
         left join public.task_types tt on tt.id = li.task_type_ref
        where li.estimate_id in (
          select e.id
            from public.estimates e
           where e.opportunity_id = p_opportunity_id
             and e.company_id = p_company_id
             and e.deleted_at is null
        )
          and li.company_id = p_company_id
          and li.type = 'LABOR')
    );
    v_tasks := coalesce((v_grouped ->> 'task_count')::bigint, 0);
  end if;

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
    p_company_id::text,
    photo_url,
    'site_visit',
    sv.id,
    sv.created_by,
    null,
    now()
  from public.site_visits sv
  cross join lateral unnest(coalesce(sv.photos, array[]::text[])) as photo_url
  where sv.opportunity_id = p_opportunity_id
    and sv.company_id = p_company_id::text
    and sv.deleted_at is null
    and photo_url is not null
    and photo_url <> ''
    and not exists (
      select 1
        from public.project_photos pp
       where pp.project_id = v_project_id::text
         and pp.site_visit_id = sv.id
         and pp.url = photo_url
    );
  get diagnostics v_photos = row_count;

  -- Lead-owned photos follow the opportunity onto the project. Deduplicate by
  -- URL across every source so a site-visit copy is never repeated.
  insert into public.project_photos (
    id,
    project_id,
    company_id,
    url,
    source,
    uploaded_by,
    taken_at,
    created_at
  )
  select
    gen_random_uuid(),
    v_project_id::text,
    p_company_id::text,
    lead_image_url,
    'other',
    coalesce(v_decided_by::text, ''),
    null,
    now()
  from unnest(coalesce(v_opp.images, array[]::text[])) as lead_image_url
  where lead_image_url is not null
    and lead_image_url <> ''
    and not exists (
      select 1
        from public.project_photos pp
       where pp.project_id = v_project_id::text
         and pp.url = lead_image_url
    );
  get diagnostics v_lead_photos = row_count;

  -- Re-parent only unparented lead decks; opportunity_id remains intact as
  -- provenance, and a deck already attached to another project is never stolen.
  update public.deck_designs
     set project_id = v_project_id,
         updated_at = now()
   where opportunity_id = p_opportunity_id
     and company_id = p_company_id
     and deleted_at is null
     and project_id is null;
  get diagnostics v_decks = row_count;

  if p_win_opportunity then
    if v_opp.stage is distinct from 'won' then
      update public.opportunities
         set stage = 'won',
             stage_entered_at = now(),
             stage_manually_set = true,
             actual_value = coalesce(p_actual_value, actual_value),
             actual_close_date = coalesce(actual_close_date, now()::date),
             updated_at = now()
       where id = p_opportunity_id
         and company_id = p_company_id;

      insert into public.stage_transitions (
        company_id,
        opportunity_id,
        from_stage,
        to_stage,
        transitioned_at,
        transitioned_by,
        duration_in_stage
      ) values (
        p_company_id,
        p_opportunity_id,
        v_opp.stage,
        'won',
        now(),
        v_decided_by,
        now() - coalesce(v_opp.stage_entered_at, now())
      );
      v_won := true;
    else
      update public.opportunities
         set actual_value = coalesce(p_actual_value, actual_value),
             updated_at = now()
       where id = p_opportunity_id
         and company_id = p_company_id;
    end if;
  end if;

  -- Keep the disposition idempotent on repair while healing older linked rows
  -- that never received a conversion disposition.
  select od.id
    into v_disposition_id
    from public.opportunity_dispositions od
   where od.opportunity_id = p_opportunity_id
     and od.company_id = p_company_id
     and od.disposition = 'converted_to_project'
     and od.converted_project_ref = v_project_id
   order by od.created_at desc, od.id desc
   limit 1
   for update;

  if v_disposition_id is null then
    update public.opportunity_dispositions
       set superseded_at = now()
     where opportunity_id = p_opportunity_id
       and company_id = p_company_id
       and superseded_at is null;

    insert into public.opportunity_dispositions (
      company_id,
      opportunity_id,
      disposition,
      reason_code,
      decided_via,
      decided_by,
      evidence,
      converted_project_ref
    ) values (
      p_company_id,
      p_opportunity_id,
      'converted_to_project',
      null,
      'project_conversion',
      v_decided_by,
      coalesce(p_evidence, '{}'::jsonb) || jsonb_build_object(
        'source_path', p_source_path,
        'actual_value', coalesce(
          p_actual_value,
          v_opp.actual_value,
          v_opp.estimated_value
        ),
        'relinked_estimates', v_relinked,
        'linked_existing', v_linked_existing,
        'already_converted', v_already_converted,
        'won', v_won
      ),
      v_project_id
    )
    returning id into v_disposition_id;
  end if;

  insert into public.opportunity_conversion_events (
    company_id,
    opportunity_id,
    project_id,
    event_type,
    actor_user_id,
    assignment_version,
    payload
  ) values (
    p_company_id,
    p_opportunity_id,
    v_project_id,
    'converted_to_project',
    v_decided_by,
    v_opp.assignment_version,
    jsonb_build_object(
      'source_path', p_source_path,
      'disposition_id', v_disposition_id,
      'linked_existing', v_linked_existing,
      'already_converted', v_already_converted,
      'won', v_won
    )
  )
  on conflict (opportunity_id, project_id, event_type) do nothing
  returning id into v_conversion_event_id;

  if v_conversion_event_id is null then
    select oce.id
      into v_conversion_event_id
      from public.opportunity_conversion_events oce
     where oce.opportunity_id = p_opportunity_id
       and oce.project_id = v_project_id
       and oce.event_type = 'converted_to_project';
  end if;

  return jsonb_build_object(
    'converted', not v_already_converted,
    'already_converted', v_already_converted,
    'guard_reason', case
      when v_already_converted then 'already_converted'
      else null
    end,
    'project_id', v_project_id,
    'opportunity_id', p_opportunity_id,
    'assigned_to', v_opp.assigned_to,
    'assignment_version', v_opp.assignment_version,
    'disposition_id', v_disposition_id,
    'conversion_event_id', v_conversion_event_id,
    'relinked_estimates', v_relinked,
    'materialized_tasks', v_tasks,
    'attached_photos', v_photos,
    'attached_lead_photos', v_lead_photos,
    'relinked_decks', v_decks,
    'linked_existing', v_linked_existing,
    'links_repaired', true,
    'won', v_won
  );
end;
$function$;

CREATE OR REPLACE FUNCTION private.sync_accepted_estimate_project_tasks(p_estimate_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'public', 'private', 'pg_temp'
AS $function$
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
  v_groups_enabled boolean := false;
  v_grouped jsonb;
  v_scope_count integer := 0;
begin
  if p_estimate_id is null then
    raise exception 'estimate_id_required' using errcode = '22023';
  end if;

  v_actor_user_id := private.get_current_user_id();

  if v_actor_user_id is null then
    raise exception 'actor_not_found' using errcode = '42501';
  end if;

  -- CRIT-3 fix: the uid() builtin casts the request.jwt sub to uuid and throws
  -- for Firebase (non-uuid) subjects. Resolve the actor id through a SECURITY
  -- DEFINER helper instead -- this function is SECURITY INVOKER and the in-app
  -- caller runs as anon/authenticated, which cannot read the auth schema.
  v_actor_auth_id := private.current_actor_auth_user_id();

  if v_actor_auth_id is null then
    raise exception 'actor_auth_not_found' using errcode = '42501';
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

  select coalesce(company_row.task_groups_conversion_enabled, false)
    into v_groups_enabled
    from public.companies company_row
   where company_row.id = v_estimate.company_id;

  if not coalesce(v_groups_enabled, false) then
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
  else
    -- Task groups rollout gate ON. Single (scope-less) tasks still take the
    -- legacy field backfill; grouped tasks keep their auto-title (null custom_title).
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
    )
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
       and not exists (
         select 1 from public.task_scopes scope_row
          where scope_row.task_id = task_row.id
            and scope_row.deleted_at is null
       )
       and (
         (task_row.task_type_id is null and accepted_lines.task_type_ref is not null)
         or nullif(task_row.custom_title, '') is null
         or task_row.display_order is null
         or task_row.duration is null
         or nullif(task_row.task_color, '') is null
       );

    select count(*)
      into v_required_task_count
      from public.line_items line_item
     where line_item.estimate_id = v_estimate.id
       and line_item.company_id = v_estimate.company_id
       and line_item.type = 'LABOR'
       and coalesce(line_item.is_selected, true) = true;

    v_grouped := private.materialize_line_item_tasks_grouped(
      v_estimate.company_id,
      v_project_id,
      (select coalesce(jsonb_agg(jsonb_build_object(
                 'line_item_id', line_item.id::text,
                 'estimate_id', v_estimate.id::text,
                 'task_type_ref', line_item.task_type_ref::text,
                 'name', line_item.name,
                 'sort_order', coalesce(line_item.sort_order, 0),
                 'default_duration', coalesce(task_type.default_duration, 1),
                 'default_color', coalesce(task_type.color, '#417394')
               ) order by coalesce(line_item.sort_order, 0), line_item.id), '[]'::jsonb)
         from public.line_items line_item
         left join public.task_types task_type
           on task_type.id = line_item.task_type_ref
        where line_item.estimate_id = v_estimate.id
          and line_item.company_id = v_estimate.company_id
          and line_item.type = 'LABOR'
          and coalesce(line_item.is_selected, true) = true)
    );
    v_inserted_task_count := coalesce((v_grouped ->> 'task_count')::integer, 0);
    v_scope_count := coalesce((v_grouped ->> 'scope_count')::integer, 0);

    -- Every accepted LABOR line must be carried by a live task (its provenance)
    -- or by a live scope on a live task of this project and estimate.
    select count(*)
      into v_verified_task_count
      from public.line_items line_item
     where line_item.estimate_id = v_estimate.id
       and line_item.company_id = v_estimate.company_id
       and line_item.type = 'LABOR'
       and coalesce(line_item.is_selected, true) = true
       and (
         exists (
           select 1 from public.project_tasks task_row
            where task_row.company_id = v_estimate.company_id
              and task_row.project_id = v_project_id
              and task_row.source_estimate_id = v_estimate.id::text
              and task_row.source_line_item_id = line_item.id::text
              and task_row.deleted_at is null
         )
         or exists (
           select 1 from public.task_scopes scope_row
             join public.project_tasks scope_task on scope_task.id = scope_row.task_id
            where scope_row.company_id = v_estimate.company_id
              and scope_row.deleted_at is null
              and scope_row.source_line_item_id = line_item.id::text
              and scope_task.project_id = v_project_id
              and scope_task.source_estimate_id = v_estimate.id::text
              and scope_task.deleted_at is null
         )
       );

    if v_verified_task_count <> v_required_task_count then
      raise exception 'accepted_estimate_task_sync_incomplete'
        using errcode = '23514';
    end if;

    -- Count reported to callers = live tasks for this estimate on the project.
    select count(*)
      into v_verified_task_count
      from public.project_tasks task_row
     where task_row.company_id = v_estimate.company_id
       and task_row.project_id = v_project_id
       and task_row.source_estimate_id = v_estimate.id::text
       and task_row.source_line_item_id is not null
       and task_row.deleted_at is null;
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
    'scope_count', v_scope_count,
    'grouping_enabled', coalesce(v_groups_enabled, false),
    'stage_transition_inserted', v_stage_transition_inserted,
    'linked_site_visit_count', v_linked_site_visit_count,
    'attached_photo_count', v_attached_photo_count,
    'material_demand_performed', false
  );
end;
$function$;

CREATE OR REPLACE FUNCTION private.resolve_estimate_material_demand_plan(p_estimate_id uuid, p_project_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public', 'private', 'pg_temp'
AS $function$
declare
  v_actor_user_id uuid;
  v_actor_company_id uuid;
  v_estimate_company_id uuid;
  v_estimate_status text;
  v_estimate_project_ref uuid;
  v_estimate_project_id_text text;
  v_project_id uuid;
  v_inventory_mode text := 'off';
  v_demands jsonb := '[]'::jsonb;
  v_warnings jsonb := '[]'::jsonb;
  v_missing_mappings jsonb := '[]'::jsonb;
  v_overruns jsonb := '[]'::jsonb;
  v_blockers jsonb := '[]'::jsonb;
  v_line record;
  v_material record;
  v_recipe_count integer;
  v_resolution jsonb;
  v_available jsonb;
  v_catalog_variant_id uuid;
  v_required_quantity numeric;
  v_available_quantity numeric;
  v_projected_overrun_quantity numeric;
  v_demand_key text;
  v_material_warning_payload jsonb;
  v_schema_ready boolean := true;
begin
  if p_estimate_id is null then
    raise exception 'estimate_id_required' using errcode = '22023';
  end if;

  v_actor_user_id := private.get_current_user_id();
  v_actor_company_id := private.get_user_company_id();

  if v_actor_user_id is null or v_actor_company_id is null then
    raise exception 'actor_company_not_found' using errcode = '42501';
  end if;

  select estimate_row.company_id,
         estimate_row.status,
         estimate_row.project_ref,
         estimate_row.project_id
    into v_estimate_company_id,
         v_estimate_status,
         v_estimate_project_ref,
         v_estimate_project_id_text
    from public.estimates estimate_row
   where estimate_row.id = p_estimate_id
     and estimate_row.deleted_at is null;

  if v_estimate_company_id is null then
    raise exception 'estimate_not_found' using errcode = 'P0002';
  end if;

  if v_estimate_company_id is distinct from v_actor_company_id then
    raise exception 'estimate_company_scope_mismatch' using errcode = '42501';
  end if;

  v_project_id := coalesce(
    p_project_id,
    v_estimate_project_ref,
    case
      when v_estimate_project_id_text ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
        then v_estimate_project_id_text::uuid
      else null
    end
  );

  if v_project_id is not null
     and not exists (
       select 1
         from public.projects project_row
        where project_row.id = v_project_id
          and project_row.company_id = v_estimate_company_id
          and project_row.deleted_at is null
     ) then
    raise exception 'project_company_scope_mismatch' using errcode = '42501';
  end if;

  if to_regclass('public.company_inventory_settings') is null then
    v_schema_ready := false;
    v_blockers := v_blockers || jsonb_build_array(jsonb_build_object(
      'code', 'p6_2_inventory_settings_not_installed',
      'detail', 'company_inventory_settings is required before tracked material demand can run'
    ));
    return jsonb_build_object(
      'ok', false,
      'schema_ready', v_schema_ready,
      'estimate_id', p_estimate_id,
      'project_id', v_project_id,
      'company_id', v_estimate_company_id,
      'inventory_mode', 'schema_pending',
      'material_demand_performed', false,
      'demands', v_demands,
      'warnings', v_warnings,
      'missing_mappings', v_missing_mappings,
      'overruns', v_overruns,
      'blockers', v_blockers
    );
  end if;

  execute
    'select coalesce(settings.inventory_mode, ''off'')
       from public.company_inventory_settings settings
      where settings.company_id = $1'
    into v_inventory_mode
    using v_estimate_company_id;

  v_inventory_mode := coalesce(v_inventory_mode, 'off');

  if v_inventory_mode = 'off' then
    return jsonb_build_object(
      'ok', true,
      'schema_ready', v_schema_ready,
      'estimate_id', p_estimate_id,
      'project_id', v_project_id,
      'company_id', v_estimate_company_id,
      'inventory_mode', v_inventory_mode,
      'material_demand_performed', false,
      'demands', v_demands,
      'warnings', v_warnings,
      'missing_mappings', v_missing_mappings,
      'overruns', v_overruns,
      'blockers', v_blockers
    );
  end if;

  if v_inventory_mode <> 'tracked' then
    raise exception 'invalid_inventory_mode' using errcode = '22023';
  end if;

  if v_estimate_status not in ('approved', 'converted') then
    v_warnings := v_warnings || jsonb_build_array(jsonb_build_object(
      'code', 'estimate_not_accepted_for_material_demand',
      'estimate_status', v_estimate_status
    ));

    return jsonb_build_object(
      'ok', true,
      'schema_ready', v_schema_ready,
      'estimate_id', p_estimate_id,
      'project_id', v_project_id,
      'company_id', v_estimate_company_id,
      'inventory_mode', v_inventory_mode,
      'material_demand_performed', false,
      'demands', v_demands,
      'warnings', v_warnings,
      'missing_mappings', v_missing_mappings,
      'overruns', v_overruns,
      'blockers', v_blockers
    );
  end if;

  if v_project_id is null then
    v_blockers := v_blockers || jsonb_build_array(jsonb_build_object(
      'code', 'project_id_required_for_material_demand',
      'estimate_id', p_estimate_id
    ));

    return jsonb_build_object(
      'ok', false,
      'schema_ready', v_schema_ready,
      'estimate_id', p_estimate_id,
      'project_id', v_project_id,
      'company_id', v_estimate_company_id,
      'inventory_mode', v_inventory_mode,
      'material_demand_performed', false,
      'demands', v_demands,
      'warnings', v_warnings,
      'missing_mappings', v_missing_mappings,
      'overruns', v_overruns,
      'blockers', v_blockers
    );
  end if;

  for v_line in
    select
      line_item.id as line_item_id,
      line_item.product_id,
      line_item.name as line_name,
      line_item.description as line_description,
      line_item.quantity::numeric as line_quantity,
      line_item.unit_id,
      line_item.unit,
      line_item.type as line_type,
      line_item.is_optional,
      line_item.is_selected,
      line_item.parent_line_item_id,
      coalesce(line_item.configured_options, '{}'::jsonb) as configured_options,
      product_row.name as product_name,
      product_row.kind as product_kind,
      product_row.type as product_type,
      product_row.linked_catalog_item_id,
      coalesce(task_for_line.id, scope_task_for_line.task_id, task_for_parent.id, scope_task_for_parent.task_id) as task_id
    from public.line_items line_item
    join public.products product_row
      on product_row.id = line_item.product_id
     and product_row.company_id = line_item.company_id
     and product_row.deleted_at is null
    left join public.project_tasks task_for_line
      on task_for_line.company_id = line_item.company_id
     and task_for_line.project_id = v_project_id
     and task_for_line.source_estimate_id = p_estimate_id::text
     and task_for_line.source_line_item_id = line_item.id::text
     and task_for_line.deleted_at is null
    left join public.project_tasks task_for_parent
      on task_for_parent.company_id = line_item.company_id
     and task_for_parent.project_id = v_project_id
     and task_for_parent.source_estimate_id = p_estimate_id::text
     and task_for_parent.source_line_item_id = line_item.parent_line_item_id::text
     and task_for_parent.deleted_at is null
    -- Task groups: a line carried as a scope of a grouped task maps to that task.
    left join lateral (
      select scope_row.task_id
        from public.task_scopes scope_row
        join public.project_tasks scope_task on scope_task.id = scope_row.task_id
       where scope_row.company_id = line_item.company_id
         and scope_row.deleted_at is null
         and scope_row.source_line_item_id = line_item.id::text
         and scope_task.project_id = v_project_id
         and scope_task.source_estimate_id = p_estimate_id::text
         and scope_task.deleted_at is null
       order by scope_row.created_at, scope_row.id
       limit 1
    ) scope_task_for_line on true
    left join lateral (
      select scope_row.task_id
        from public.task_scopes scope_row
        join public.project_tasks scope_task on scope_task.id = scope_row.task_id
       where scope_row.company_id = line_item.company_id
         and scope_row.deleted_at is null
         and scope_row.source_line_item_id = line_item.parent_line_item_id::text
         and scope_task.project_id = v_project_id
         and scope_task.source_estimate_id = p_estimate_id::text
         and scope_task.deleted_at is null
       order by scope_row.created_at, scope_row.id
       limit 1
    ) scope_task_for_parent on true
    where line_item.company_id = v_estimate_company_id
      and line_item.estimate_id = p_estimate_id
      and line_item.product_id is not null
      and coalesce(line_item.is_selected, true) = true
      and (
        coalesce(line_item.is_optional, false) = false
        or line_item.is_selected = true
      )
    order by coalesce(line_item.sort_order, 0), line_item.id
  loop
    select count(*)::integer
      into v_recipe_count
      from public.product_materials material_row
     where material_row.product_id = v_line.product_id
       and material_row.deleted_at is null;

    for v_material in
      select
        material_row.id as product_material_id,
        material_row.catalog_variant_id,
        material_row.catalog_item_id,
        material_row.variant_selector,
        material_row.quantity_per_unit::numeric as quantity_per_unit,
        material_row.scaled_by_option_id,
        material_row.unit_id,
        material_row.notes
      from public.product_materials material_row
      where material_row.product_id = v_line.product_id
        and material_row.deleted_at is null
      order by material_row.id
    loop
      v_catalog_variant_id := v_material.catalog_variant_id;
      v_material_warning_payload := '[]'::jsonb;

      if v_catalog_variant_id is null and v_material.catalog_item_id is not null then
        v_resolution := private.resolve_catalog_variant_for_material_demand(
          v_estimate_company_id,
          v_line.product_id,
          v_material.catalog_item_id,
          v_line.configured_options,
          coalesce(v_material.variant_selector, '{}'::jsonb)
        );

        v_catalog_variant_id := private.try_parse_uuid(v_resolution ->> 'catalog_variant_id');
        v_material_warning_payload := coalesce(v_resolution -> 'warnings', '[]'::jsonb);
        v_warnings := v_warnings || v_material_warning_payload;
        v_missing_mappings := v_missing_mappings || coalesce(v_resolution -> 'missing_mappings', '[]'::jsonb);
      end if;

      if v_catalog_variant_id is null then
        v_warnings := v_warnings || jsonb_build_array(jsonb_build_object(
          'code', 'recipe_material_variant_unresolved',
          'estimate_id', p_estimate_id,
          'line_item_id', v_line.line_item_id,
          'product_id', v_line.product_id,
          'product_material_id', v_material.product_material_id
        ));
        continue;
      end if;

      v_required_quantity := greatest(coalesce(v_material.quantity_per_unit, 0), 0)
        * greatest(coalesce(v_line.line_quantity, 0), 0);

      if v_material.scaled_by_option_id is not null
         and v_line.configured_options ? v_material.scaled_by_option_id::text
         and jsonb_typeof(v_line.configured_options -> v_material.scaled_by_option_id::text) = 'number' then
        v_required_quantity := greatest(coalesce(v_material.quantity_per_unit, 0), 0)
          * greatest(((v_line.configured_options ->> v_material.scaled_by_option_id::text)::numeric), 0);
      end if;

      v_available := private.catalog_variant_available_stock_summary(
        v_estimate_company_id,
        v_catalog_variant_id
      );
      v_available_quantity := coalesce((v_available ->> 'effective_available_quantity')::numeric, 0);
      v_projected_overrun_quantity := greatest(v_required_quantity - v_available_quantity, 0);
      v_demand_key := 'estimate:' || p_estimate_id::text
        || ':line:' || v_line.line_item_id::text
        || ':product_material:' || v_material.product_material_id::text
        || ':variant:' || v_catalog_variant_id::text;

      v_demands := v_demands || jsonb_build_array(jsonb_build_object(
        'demand_key', v_demand_key,
        'source', 'estimate_acceptance',
        'status', case when v_projected_overrun_quantity > 0 then 'warning' else 'projected' end,
        'company_id', v_estimate_company_id,
        'project_id', v_project_id,
        'task_id', v_line.task_id,
        'estimate_id', p_estimate_id,
        'line_item_id', v_line.line_item_id,
        'product_id', v_line.product_id,
        'product_material_id', v_material.product_material_id,
        'catalog_variant_id', v_catalog_variant_id,
        'unit_id', coalesce(v_material.unit_id, v_line.unit_id),
        'required_quantity', v_required_quantity,
        'available_quantity_at_booking', v_available_quantity,
        'projected_overrun_quantity', v_projected_overrun_quantity,
        'resolver_payload', jsonb_build_object(
          'line_name', coalesce(v_line.line_name, v_line.line_description, v_line.product_name),
          'product_name', v_line.product_name,
          'line_quantity', v_line.line_quantity,
          'line_type', v_line.line_type,
          'line_is_optional', v_line.is_optional,
          'line_is_selected', v_line.is_selected,
          'configured_options', v_line.configured_options,
          'availability', v_available
        ),
        'warning_payload', jsonb_build_object(
          'warnings', v_material_warning_payload,
          'available_quantity_at_booking', v_available_quantity,
          'projected_overrun_quantity', v_projected_overrun_quantity
        )
      ));

      if v_projected_overrun_quantity > 0 then
        v_overruns := v_overruns || jsonb_build_array(jsonb_build_object(
          'demand_key', v_demand_key,
          'line_item_id', v_line.line_item_id,
          'product_id', v_line.product_id,
          'catalog_variant_id', v_catalog_variant_id,
          'required_quantity', v_required_quantity,
          'available_quantity_at_booking', v_available_quantity,
          'projected_overrun_quantity', v_projected_overrun_quantity,
          'availability_basis', v_available ->> 'availability_basis'
        ));
      end if;
    end loop;

    if v_recipe_count = 0
       and v_line.linked_catalog_item_id is not null
       and (v_line.product_kind = 'material' or v_line.product_type = 'MATERIAL') then
      v_resolution := private.resolve_catalog_variant_for_material_demand(
        v_estimate_company_id,
        v_line.product_id,
        v_line.linked_catalog_item_id,
        v_line.configured_options,
        '{}'::jsonb
      );

      v_catalog_variant_id := private.try_parse_uuid(v_resolution ->> 'catalog_variant_id');
      v_material_warning_payload := coalesce(v_resolution -> 'warnings', '[]'::jsonb);
      v_warnings := v_warnings || v_material_warning_payload;
      v_missing_mappings := v_missing_mappings || coalesce(v_resolution -> 'missing_mappings', '[]'::jsonb);

      if v_catalog_variant_id is null then
        v_warnings := v_warnings || jsonb_build_array(jsonb_build_object(
          'code', 'linked_product_variant_unresolved',
          'estimate_id', p_estimate_id,
          'line_item_id', v_line.line_item_id,
          'product_id', v_line.product_id,
          'catalog_item_id', v_line.linked_catalog_item_id
        ));
        continue;
      end if;

      v_required_quantity := greatest(coalesce(v_line.line_quantity, 0), 0);
      v_available := private.catalog_variant_available_stock_summary(
        v_estimate_company_id,
        v_catalog_variant_id
      );
      v_available_quantity := coalesce((v_available ->> 'effective_available_quantity')::numeric, 0);
      v_projected_overrun_quantity := greatest(v_required_quantity - v_available_quantity, 0);
      v_demand_key := 'estimate:' || p_estimate_id::text
        || ':line:' || v_line.line_item_id::text
        || ':product:' || v_line.product_id::text
        || ':variant:' || v_catalog_variant_id::text;

      v_demands := v_demands || jsonb_build_array(jsonb_build_object(
        'demand_key', v_demand_key,
        'source', 'estimate_acceptance',
        'status', case when v_projected_overrun_quantity > 0 then 'warning' else 'projected' end,
        'company_id', v_estimate_company_id,
        'project_id', v_project_id,
        'task_id', v_line.task_id,
        'estimate_id', p_estimate_id,
        'line_item_id', v_line.line_item_id,
        'product_id', v_line.product_id,
        'product_material_id', null,
        'catalog_variant_id', v_catalog_variant_id,
        'unit_id', v_line.unit_id,
        'required_quantity', v_required_quantity,
        'available_quantity_at_booking', v_available_quantity,
        'projected_overrun_quantity', v_projected_overrun_quantity,
        'resolver_payload', jsonb_build_object(
          'line_name', coalesce(v_line.line_name, v_line.line_description, v_line.product_name),
          'product_name', v_line.product_name,
          'line_quantity', v_line.line_quantity,
          'line_type', v_line.line_type,
          'line_is_optional', v_line.is_optional,
          'line_is_selected', v_line.is_selected,
          'configured_options', v_line.configured_options,
          'linked_catalog_item_id', v_line.linked_catalog_item_id,
          'availability', v_available
        ),
        'warning_payload', jsonb_build_object(
          'warnings', v_material_warning_payload,
          'available_quantity_at_booking', v_available_quantity,
          'projected_overrun_quantity', v_projected_overrun_quantity
        )
      ));

      if v_projected_overrun_quantity > 0 then
        v_overruns := v_overruns || jsonb_build_array(jsonb_build_object(
          'demand_key', v_demand_key,
          'line_item_id', v_line.line_item_id,
          'product_id', v_line.product_id,
          'catalog_variant_id', v_catalog_variant_id,
          'required_quantity', v_required_quantity,
          'available_quantity_at_booking', v_available_quantity,
          'projected_overrun_quantity', v_projected_overrun_quantity,
          'availability_basis', v_available ->> 'availability_basis'
        ));
      end if;
    elsif v_recipe_count = 0
       and v_line.linked_catalog_item_id is null
       and (v_line.product_kind = 'material' or v_line.product_type = 'MATERIAL') then
      v_missing_mappings := v_missing_mappings || jsonb_build_array(jsonb_build_object(
        'code', 'material_product_catalog_link_missing',
        'dedupe_key', 'catalog_mapping_needed:product:' || v_line.product_id::text || ':linked_catalog_item',
        'estimate_id', p_estimate_id,
        'line_item_id', v_line.line_item_id,
        'product_id', v_line.product_id
      ));
    end if;
  end loop;

  v_warnings := v_warnings || v_missing_mappings;

  return jsonb_build_object(
    'ok', true,
    'schema_ready', v_schema_ready,
    'estimate_id', p_estimate_id,
    'project_id', v_project_id,
    'company_id', v_estimate_company_id,
    'inventory_mode', v_inventory_mode,
    'material_demand_performed', true,
    'selection_rule', jsonb_build_object(
      'estimate_statuses', jsonb_build_array('approved', 'converted'),
      'line_filter', 'selected_non_optional_or_explicitly_selected_optional'
    ),
    'demand_count', jsonb_array_length(v_demands),
    'warning_count', jsonb_array_length(v_warnings),
    'missing_mapping_count', jsonb_array_length(v_missing_mappings),
    'overrun_count', jsonb_array_length(v_overruns),
    'demands', v_demands,
    'warnings', v_warnings,
    'missing_mappings', v_missing_mappings,
    'overruns', v_overruns,
    'blockers', v_blockers
  );
end;
$function$;
notify pgrst, 'reload schema';
