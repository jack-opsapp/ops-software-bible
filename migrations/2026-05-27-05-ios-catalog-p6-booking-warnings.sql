-- iOS Catalog Phase 6 booking warning persistence.
-- Review-gate draft only. Do not apply without explicit PM approval.
--
-- This migration intentionally exposes no public estimate-acceptance RPC.
-- It adds only a private helper that persists the P6-4 material demand plan
-- into the P6-2 projected-demand tables. It does not create mapping
-- notifications, deduct stock, write stock-unit events, mutate physical stock
-- balances, or create task-completion consumption history.
--
-- Execution model: this helper is private-schema only but must execute as the
-- authenticated caller through the P6-6 SECURITY INVOKER acceptance wrapper.
-- It depends on authenticated-user permission helpers, so keep execution on
-- the authenticated acceptance path.

begin;

create schema if not exists private;

do $$
begin
  if to_regclass('public.company_inventory_settings') is null then
    raise exception 'p6_2_company_inventory_settings_required'
      using errcode = '42P01';
  end if;

  if to_regclass('public.project_material_demands') is null then
    raise exception 'p6_2_project_material_demands_required'
      using errcode = '42P01';
  end if;

  if to_regclass('public.project_material_snapshots') is null then
    raise exception 'p6_2_project_material_snapshots_required'
      using errcode = '42P01';
  end if;

  if to_regclass('public.project_material_snapshot_items') is null then
    raise exception 'p6_2_project_material_snapshot_items_required'
      using errcode = '42P01';
  end if;

  if to_regclass('public.task_material_allocations') is null then
    raise exception 'p6_2_task_material_allocations_required'
      using errcode = '42P01';
  end if;

  if to_regprocedure('private.try_parse_uuid(text)') is null then
    raise exception 'p6_4_try_parse_uuid_required'
      using errcode = '42883';
  end if;

  if to_regprocedure('private.resolve_estimate_material_demand_plan(uuid, uuid)') is null then
    raise exception 'p6_4_material_demand_plan_required'
      using errcode = '42883';
  end if;

  if to_regprocedure('private.current_user_can_write_project_material_workflow(uuid)') is null then
    raise exception 'p6_2_material_workflow_authorization_required'
      using errcode = '42883';
  end if;
end;
$$;

create or replace function private.persist_estimate_material_booking_projection(
  p_estimate_id uuid,
  p_project_id uuid default null
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
  v_plan jsonb;
  v_plan_ok boolean := false;
  v_plan_company_id uuid;
  v_plan_project_id uuid;
  v_inventory_mode text;
  v_material_demand_performed boolean := false;
  v_demands jsonb := '[]'::jsonb;
  v_warnings jsonb := '[]'::jsonb;
  v_missing_mappings jsonb := '[]'::jsonb;
  v_overruns jsonb := '[]'::jsonb;
  v_blockers jsonb := '[]'::jsonb;
  v_demand jsonb;
  v_demand_key text;
  v_demand_id uuid;
  v_demand_ids uuid[] := '{}'::uuid[];
  v_active_demand_keys text[] := '{}'::text[];
  v_overrun_allocation_keys text[] := '{}'::text[];
  v_demand_company_id uuid;
  v_demand_project_id uuid;
  v_catalog_variant_id uuid;
  v_required_quantity numeric;
  v_available_quantity numeric;
  v_projected_overrun_quantity numeric;
  v_resolver_payload jsonb;
  v_warning_payload jsonb;
  v_warning_count integer;
  v_demand_status text;
  v_upserted_demand_count integer := 0;
  v_released_demand_count integer := 0;
  v_released_allocation_count integer := 0;
  v_superseded_demand_count integer := 0;
  v_superseded_allocation_count integer := 0;
  v_overrun_allocation_count integer := 0;
  v_snapshot_id uuid;
  v_snapshot_item_count integer := 0;
  v_booking_payload jsonb;
begin
  if p_estimate_id is null then
    raise exception 'estimate_id_required' using errcode = '22023';
  end if;

  v_actor_user_id := private.get_current_user_id();
  v_actor_company_id := private.get_user_company_id();

  if v_actor_user_id is null or v_actor_company_id is null then
    raise exception 'actor_company_not_found' using errcode = '42501';
  end if;

  perform set_config('ops.project_material_workflow', 'on', true);

  if coalesce(current_setting('ops.accept_estimate_to_job_rpc', true), '') <> 'on' then
    raise exception 'accept_estimate_to_job_required_for_booking_projection'
      using errcode = '42501';
  end if;

  if not private.current_user_can_write_project_material_workflow(v_actor_company_id) then
    raise exception 'acceptance_material_workflow_permission_required'
      using errcode = '42501';
  end if;

  v_plan := private.resolve_estimate_material_demand_plan(p_estimate_id, p_project_id);
  v_plan_ok := coalesce((v_plan ->> 'ok')::boolean, false);
  v_plan_company_id := private.try_parse_uuid(v_plan ->> 'company_id');
  v_plan_project_id := private.try_parse_uuid(v_plan ->> 'project_id');
  v_inventory_mode := coalesce(v_plan ->> 'inventory_mode', 'off');
  v_material_demand_performed := coalesce((v_plan ->> 'material_demand_performed')::boolean, false);
  v_demands := coalesce(v_plan -> 'demands', '[]'::jsonb);
  v_warnings := coalesce(v_plan -> 'warnings', '[]'::jsonb);
  v_missing_mappings := coalesce(v_plan -> 'missing_mappings', '[]'::jsonb);
  v_overruns := coalesce(v_plan -> 'overruns', '[]'::jsonb);
  v_blockers := coalesce(v_plan -> 'blockers', '[]'::jsonb);

  if v_plan_company_id is null then
    raise exception 'material_plan_company_id_missing' using errcode = '23514';
  end if;

  if v_plan_company_id is distinct from v_actor_company_id then
    raise exception 'material_plan_company_scope_mismatch'
      using errcode = '42501';
  end if;

  if p_project_id is not null
     and v_plan_project_id is distinct from p_project_id then
    raise exception 'material_plan_project_scope_mismatch'
      using errcode = '42501';
  end if;

  if jsonb_typeof(v_demands) <> 'array'
     or jsonb_typeof(v_warnings) <> 'array'
     or jsonb_typeof(v_missing_mappings) <> 'array'
     or jsonb_typeof(v_overruns) <> 'array'
     or jsonb_typeof(v_blockers) <> 'array' then
    raise exception 'material_plan_array_contract_invalid'
      using errcode = '23514';
  end if;

  if v_inventory_mode = 'off' then
    with released_demands as (
      update public.project_material_demands demand_row
         set status = 'released',
             warning_payload = coalesce(demand_row.warning_payload, '{}'::jsonb)
               || jsonb_build_object(
                    'released_by_booking_projection', true,
                    'released_at', v_now,
                    'release_reason', 'company_inventory_mode_off'
                  ),
             updated_at = v_now
       where demand_row.company_id = v_actor_company_id
         and demand_row.estimate_id = p_estimate_id
         and (v_plan_project_id is null or demand_row.project_id = v_plan_project_id)
         and demand_row.deleted_at is null
         and demand_row.status in ('projected', 'warning')
      returning demand_row.id
    ),
    released_allocations as (
      update public.task_material_allocations allocation_row
         set allocation_status = 'released',
             updated_at = v_now
        from released_demands released_row
       where allocation_row.company_id = v_actor_company_id
         and allocation_row.demand_id = released_row.id
         and allocation_row.deleted_at is null
         and allocation_row.allocation_status in ('projected', 'overrun')
      returning allocation_row.id
    )
    select
      (select count(*)::integer from released_demands),
      (select count(*)::integer from released_allocations)
      into v_released_demand_count,
           v_released_allocation_count;

    return v_plan || jsonb_build_object(
      'booking_persistence_performed', false,
      'booking_persistence_reason', 'company_inventory_mode_off',
      'released_demand_count', v_released_demand_count,
      'released_allocation_count', v_released_allocation_count,
      'superseded_demand_count', 0,
      'superseded_allocation_count', 0,
      'upserted_demand_count', 0,
      'overrun_allocation_count', 0,
      'booking_snapshot_id', null,
      'booking_snapshot_item_count', 0,
      'demand_ids', '[]'::jsonb
    );
  end if;

  if not v_plan_ok or not v_material_demand_performed then
    return v_plan || jsonb_build_object(
      'booking_persistence_performed', false,
      'booking_persistence_reason', 'material_plan_not_performed',
      'released_demand_count', 0,
      'released_allocation_count', 0,
      'superseded_demand_count', 0,
      'superseded_allocation_count', 0,
      'upserted_demand_count', 0,
      'overrun_allocation_count', 0,
      'booking_snapshot_id', null,
      'booking_snapshot_item_count', 0,
      'demand_ids', '[]'::jsonb
    );
  end if;

  if v_inventory_mode <> 'tracked' then
    raise exception 'invalid_inventory_mode_for_booking_projection'
      using errcode = '22023';
  end if;

  if v_plan_project_id is null then
    raise exception 'project_id_required_for_booking_projection'
      using errcode = '22023';
  end if;

  select coalesce(
    array_agg(distinct demand_item.value ->> 'demand_key')
      filter (where nullif(demand_item.value ->> 'demand_key', '') is not null),
    '{}'::text[]
  )
    into v_active_demand_keys
    from jsonb_array_elements(v_demands) as demand_item(value);

  with stale_demands as (
    update public.project_material_demands demand_row
       set status = 'superseded',
           warning_payload = coalesce(demand_row.warning_payload, '{}'::jsonb)
             || jsonb_build_object(
                  'superseded_by_booking_projection', true,
                  'superseded_at', v_now,
                  'superseded_reason', 'demand_key_absent_from_latest_plan'
                ),
           updated_at = v_now
     where demand_row.company_id = v_actor_company_id
       and demand_row.estimate_id = p_estimate_id
       and demand_row.project_id = v_plan_project_id
       and demand_row.deleted_at is null
       and demand_row.status in ('projected', 'warning')
       and not (demand_row.demand_key = any(v_active_demand_keys))
    returning demand_row.id
  ),
  stale_allocations as (
    update public.task_material_allocations allocation_row
       set allocation_status = 'superseded',
           updated_at = v_now
      from stale_demands stale_row
     where allocation_row.company_id = v_actor_company_id
       and allocation_row.demand_id = stale_row.id
       and allocation_row.deleted_at is null
       and allocation_row.allocation_status in ('projected', 'overrun')
    returning allocation_row.id
  )
  select
    (select count(*)::integer from stale_demands),
    (select count(*)::integer from stale_allocations)
    into v_superseded_demand_count,
         v_superseded_allocation_count;

  for v_demand in
    select demand_item.value
      from jsonb_array_elements(v_demands) as demand_item(value)
  loop
    v_demand_key := nullif(v_demand ->> 'demand_key', '');
    v_demand_company_id := private.try_parse_uuid(v_demand ->> 'company_id');
    v_demand_project_id := private.try_parse_uuid(v_demand ->> 'project_id');
    v_catalog_variant_id := private.try_parse_uuid(v_demand ->> 'catalog_variant_id');
    v_required_quantity := coalesce(nullif(v_demand ->> 'required_quantity', '')::numeric, 0);
    v_available_quantity := nullif(v_demand ->> 'available_quantity_at_booking', '')::numeric;
    v_projected_overrun_quantity := coalesce(
      nullif(v_demand ->> 'projected_overrun_quantity', '')::numeric,
      0
    );
    v_resolver_payload := coalesce(v_demand -> 'resolver_payload', '{}'::jsonb);
    v_warning_payload := coalesce(v_demand -> 'warning_payload', '{}'::jsonb);

    if v_demand_key is null then
      raise exception 'material_plan_demand_key_missing'
        using errcode = '23514';
    end if;

    if v_demand_company_id is distinct from v_actor_company_id then
      raise exception 'material_plan_demand_company_scope_mismatch'
        using errcode = '42501';
    end if;

    if v_demand_project_id is distinct from v_plan_project_id then
      raise exception 'material_plan_demand_project_scope_mismatch'
        using errcode = '42501';
    end if;

    if jsonb_typeof(v_resolver_payload) <> 'object' then
      v_resolver_payload := jsonb_build_object('raw_resolver_payload', v_resolver_payload);
    end if;

    if jsonb_typeof(v_warning_payload) <> 'object' then
      v_warning_payload := jsonb_build_object('warnings', v_warning_payload);
    end if;

    v_warning_count := case
      when jsonb_typeof(v_warning_payload -> 'warnings') = 'array'
        then jsonb_array_length(v_warning_payload -> 'warnings')
      else 0
    end;

    v_demand_status := case
      when v_projected_overrun_quantity > 0 or v_warning_count > 0
        then 'warning'
      else 'projected'
    end;

    v_warning_payload := v_warning_payload || jsonb_build_object(
      'booking_projection_status', v_demand_status,
      'booking_projection_persisted_at', v_now,
      'projected_overrun_quantity', v_projected_overrun_quantity,
      'warning_count', v_warning_count
    );

    insert into public.project_material_demands (
      company_id,
      project_id,
      task_id,
      estimate_id,
      line_item_id,
      product_id,
      product_material_id,
      catalog_variant_id,
      unit_id,
      demand_key,
      source,
      status,
      required_quantity,
      available_quantity_at_booking,
      projected_overrun_quantity,
      resolver_payload,
      warning_payload,
      created_at,
      updated_at,
      deleted_at
    ) values (
      v_actor_company_id,
      v_plan_project_id,
      private.try_parse_uuid(v_demand ->> 'task_id'),
      p_estimate_id,
      private.try_parse_uuid(v_demand ->> 'line_item_id'),
      private.try_parse_uuid(v_demand ->> 'product_id'),
      private.try_parse_uuid(v_demand ->> 'product_material_id'),
      v_catalog_variant_id,
      private.try_parse_uuid(v_demand ->> 'unit_id'),
      v_demand_key,
      coalesce(nullif(v_demand ->> 'source', ''), 'estimate_acceptance'),
      v_demand_status,
      v_required_quantity,
      v_available_quantity,
      v_projected_overrun_quantity,
      v_resolver_payload,
      v_warning_payload,
      v_now,
      v_now,
      null
    )
    on conflict (company_id, demand_key)
      where deleted_at is null
    do update
      set project_id = case
            when public.project_material_demands.status in ('allocated', 'consumed')
              then public.project_material_demands.project_id
            else excluded.project_id
          end,
          task_id = case
            when public.project_material_demands.status in ('allocated', 'consumed')
              then public.project_material_demands.task_id
            else excluded.task_id
          end,
          estimate_id = case
            when public.project_material_demands.status in ('allocated', 'consumed')
              then public.project_material_demands.estimate_id
            else excluded.estimate_id
          end,
          line_item_id = case
            when public.project_material_demands.status in ('allocated', 'consumed')
              then public.project_material_demands.line_item_id
            else excluded.line_item_id
          end,
          product_id = case
            when public.project_material_demands.status in ('allocated', 'consumed')
              then public.project_material_demands.product_id
            else excluded.product_id
          end,
          product_material_id = case
            when public.project_material_demands.status in ('allocated', 'consumed')
              then public.project_material_demands.product_material_id
            else excluded.product_material_id
          end,
          catalog_variant_id = case
            when public.project_material_demands.status in ('allocated', 'consumed')
              then public.project_material_demands.catalog_variant_id
            else excluded.catalog_variant_id
          end,
          unit_id = case
            when public.project_material_demands.status in ('allocated', 'consumed')
              then public.project_material_demands.unit_id
            else excluded.unit_id
          end,
          source = case
            when public.project_material_demands.status in ('allocated', 'consumed')
              then public.project_material_demands.source
            else excluded.source
          end,
          status = case
            when public.project_material_demands.status in ('allocated', 'consumed')
              then public.project_material_demands.status
            else excluded.status
          end,
          required_quantity = case
            when public.project_material_demands.status in ('allocated', 'consumed')
              then public.project_material_demands.required_quantity
            else excluded.required_quantity
          end,
          available_quantity_at_booking = case
            when public.project_material_demands.status in ('allocated', 'consumed')
              then public.project_material_demands.available_quantity_at_booking
            else excluded.available_quantity_at_booking
          end,
          projected_overrun_quantity = case
            when public.project_material_demands.status in ('allocated', 'consumed')
              then public.project_material_demands.projected_overrun_quantity
            else excluded.projected_overrun_quantity
          end,
          resolver_payload = case
            when public.project_material_demands.status in ('allocated', 'consumed')
              then public.project_material_demands.resolver_payload
            else excluded.resolver_payload
          end,
          warning_payload = case
            when public.project_material_demands.status in ('allocated', 'consumed')
              then public.project_material_demands.warning_payload
            else excluded.warning_payload
          end,
          updated_at = case
            when public.project_material_demands.status in ('allocated', 'consumed')
              then public.project_material_demands.updated_at
            else v_now
          end
    returning id
      into v_demand_id;

    v_demand_ids := array_append(v_demand_ids, v_demand_id);
    v_upserted_demand_count := v_upserted_demand_count + 1;

    if v_projected_overrun_quantity > 0 then
      insert into public.task_material_allocations (
        company_id,
        task_material_id,
        demand_id,
        catalog_variant_id,
        catalog_stock_unit_id,
        inventory_deduction_id,
        allocation_key,
        allocation_status,
        allocated_quantity,
        consumed_quantity,
        overrun_quantity,
        stock_unit_snapshot,
        created_at,
        updated_at,
        deleted_at
      ) values (
        v_actor_company_id,
        null,
        v_demand_id,
        v_catalog_variant_id,
        null,
        null,
        v_demand_key || ':overrun',
        'overrun',
        0,
        0,
        v_projected_overrun_quantity,
        jsonb_build_object(
          'projection_only', true,
          'booking_projection_created_at', v_now,
          'availability', v_resolver_payload -> 'availability',
          'reason', 'projected_overrun'
        ),
        v_now,
        v_now,
        null
      )
      on conflict (company_id, allocation_key)
        where deleted_at is null
      do update
        set task_material_id = case
              when public.task_material_allocations.allocation_status = 'consumed'
                then public.task_material_allocations.task_material_id
              else null
            end,
            demand_id = case
              when public.task_material_allocations.allocation_status = 'consumed'
                then public.task_material_allocations.demand_id
              else excluded.demand_id
            end,
            catalog_variant_id = case
              when public.task_material_allocations.allocation_status = 'consumed'
                then public.task_material_allocations.catalog_variant_id
              else excluded.catalog_variant_id
            end,
            catalog_stock_unit_id = case
              when public.task_material_allocations.allocation_status = 'consumed'
                then public.task_material_allocations.catalog_stock_unit_id
              else null
            end,
            inventory_deduction_id = case
              when public.task_material_allocations.allocation_status = 'consumed'
                then public.task_material_allocations.inventory_deduction_id
              else null
            end,
            allocation_status = case
              when public.task_material_allocations.allocation_status = 'consumed'
                then public.task_material_allocations.allocation_status
              else 'overrun'
            end,
            allocated_quantity = case
              when public.task_material_allocations.allocation_status = 'consumed'
                then public.task_material_allocations.allocated_quantity
              else 0
            end,
            consumed_quantity = case
              when public.task_material_allocations.allocation_status = 'consumed'
                then public.task_material_allocations.consumed_quantity
              else 0
            end,
            overrun_quantity = case
              when public.task_material_allocations.allocation_status = 'consumed'
                then public.task_material_allocations.overrun_quantity
              else excluded.overrun_quantity
            end,
            stock_unit_snapshot = case
              when public.task_material_allocations.allocation_status = 'consumed'
                then public.task_material_allocations.stock_unit_snapshot
              else excluded.stock_unit_snapshot
            end,
            updated_at = case
              when public.task_material_allocations.allocation_status = 'consumed'
                then public.task_material_allocations.updated_at
              else v_now
            end;

      v_overrun_allocation_keys := array_append(
        v_overrun_allocation_keys,
        v_demand_key || ':overrun'
      );
      v_overrun_allocation_count := v_overrun_allocation_count + 1;
    end if;
  end loop;

  with stale_allocations as (
    update public.task_material_allocations allocation_row
       set allocation_status = 'superseded',
           updated_at = v_now
      from public.project_material_demands demand_row
     where allocation_row.company_id = v_actor_company_id
       and allocation_row.demand_id = demand_row.id
       and demand_row.company_id = v_actor_company_id
       and demand_row.estimate_id = p_estimate_id
       and demand_row.project_id = v_plan_project_id
       and demand_row.deleted_at is null
       and allocation_row.deleted_at is null
       and allocation_row.allocation_status in ('projected', 'overrun')
       and not (allocation_row.allocation_key = any(v_overrun_allocation_keys))
    returning allocation_row.id
  )
  select v_superseded_allocation_count + count(*)::integer
    into v_superseded_allocation_count
    from stale_allocations;

  v_booking_payload := jsonb_build_object(
    'estimate_id', p_estimate_id,
    'project_id', v_plan_project_id,
    'company_id', v_actor_company_id,
    'inventory_mode', v_inventory_mode,
    'material_demand_performed', v_material_demand_performed,
    'demand_keys', to_jsonb(v_active_demand_keys),
    'overrun_allocation_keys', to_jsonb(v_overrun_allocation_keys),
    'warnings', v_warnings,
    'missing_mappings', v_missing_mappings,
    'overruns', v_overruns,
    'blockers', v_blockers,
    'upserted_demand_count', v_upserted_demand_count,
    'superseded_demand_count', v_superseded_demand_count,
    'superseded_allocation_count', v_superseded_allocation_count,
    'source_plan', v_plan
  );

  insert into public.project_material_snapshots (
    company_id,
    project_id,
    task_id,
    estimate_id,
    snapshot_kind,
    created_by,
    notes,
    payload,
    created_at
  ) values (
    v_actor_company_id,
    v_plan_project_id,
    null,
    p_estimate_id,
    'booking_projection',
    v_actor_user_id,
    'P6 booking warning projection',
    v_booking_payload,
    v_now
  )
  returning id
    into v_snapshot_id;

  insert into public.project_material_snapshot_items (
    company_id,
    snapshot_id,
    demand_id,
    task_material_id,
    allocation_id,
    inventory_deduction_id,
    catalog_variant_id,
    catalog_stock_unit_id,
    source_event_id,
    unit_id,
    quantity,
    projected_overrun_quantity,
    stock_unit_snapshot,
    created_at
  )
  select
    demand_row.company_id,
    v_snapshot_id,
    demand_row.id,
    null,
    allocation_row.id,
    null,
    demand_row.catalog_variant_id,
    null,
    null,
    demand_row.unit_id,
    demand_row.required_quantity,
    demand_row.projected_overrun_quantity,
    jsonb_build_object(
      'projection_only', true,
      'captured_at', v_now,
      'availability', demand_row.resolver_payload -> 'availability',
      'warning_payload', demand_row.warning_payload,
      'allocation_status', allocation_row.allocation_status
    ),
    v_now
  from public.project_material_demands demand_row
  left join public.task_material_allocations allocation_row
    on allocation_row.company_id = demand_row.company_id
   and allocation_row.demand_id = demand_row.id
   and allocation_row.allocation_key = demand_row.demand_key || ':overrun'
   and allocation_row.deleted_at is null
  where demand_row.company_id = v_actor_company_id
    and demand_row.id = any(v_demand_ids)
    and demand_row.deleted_at is null;

  get diagnostics v_snapshot_item_count = row_count;

  return v_plan || jsonb_build_object(
    'booking_persistence_performed', true,
    'booking_persistence_reason', 'tracked_inventory_booking_projection',
    'released_demand_count', 0,
    'released_allocation_count', 0,
    'superseded_demand_count', v_superseded_demand_count,
    'superseded_allocation_count', v_superseded_allocation_count,
    'upserted_demand_count', v_upserted_demand_count,
    'overrun_allocation_count', v_overrun_allocation_count,
    'booking_snapshot_id', v_snapshot_id,
    'booking_snapshot_item_count', v_snapshot_item_count,
    'demand_ids', to_jsonb(v_demand_ids)
  );
end;
$$;

revoke all on function private.persist_estimate_material_booking_projection(uuid, uuid)
  from public, anon, authenticated, service_role;
grant execute on function private.persist_estimate_material_booking_projection(uuid, uuid)
  to authenticated;

comment on function private.persist_estimate_material_booking_projection(uuid, uuid)
  is 'Private Phase 6 helper that runs inside the authenticated acceptance transaction and persists the P6-4 booking demand plan into projected-demand rows, warning metadata, non-deductive overrun allocations, and booking snapshots without regressing allocated/consumed demand state.';

commit;
