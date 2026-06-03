-- OPS iOS Catalog P6-20
-- Task-completion stock consumption contract.
-- Draft only. Do not apply until PM approves the task-completion server RPC.

begin;

create table if not exists public.task_material_consumption_requests (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  task_id uuid not null references public.project_tasks(id) on delete cascade,
  idempotency_key text not null,
  request_hash text not null,
  status text not null default 'processing',
  response jsonb not null default '{}'::jsonb,
  created_by uuid references public.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint task_material_consumption_requests_key_not_blank
    check (length(btrim(idempotency_key)) > 0),
  constraint task_material_consumption_requests_status_check
    check (status in ('processing', 'completed')),
  constraint task_material_consumption_requests_response_object_check
    check (jsonb_typeof(response) = 'object'),
  constraint task_material_consumption_requests_company_key_unique
    unique (company_id, idempotency_key),
  constraint task_material_consumption_requests_company_task_unique
    unique (company_id, task_id)
);

create index if not exists task_material_consumption_requests_task_idx
  on public.task_material_consumption_requests(company_id, task_id, created_at desc);

comment on column public.project_tasks.inventory_deducted is
  'Deprecated compatibility flag. Do not read for task-completion stock consumption or iOS idempotency; task_material_consumption_requests plus project_material_snapshot_items are authoritative.';

create or replace function private.current_user_can_complete_task_material_consumption(
  p_company_id uuid,
  p_task_id uuid
) returns boolean
language plpgsql
stable
set search_path to 'public', 'private', 'pg_temp'
as $function$
declare
  v_actor uuid;
  v_scope text;
begin
  if p_company_id is null
     or p_task_id is null
     or p_company_id is distinct from private.get_user_company_id() then
    return false;
  end if;

  if coalesce(current_setting('ops.complete_project_task_rpc', true), '') <> 'on' then
    return false;
  end if;

  v_actor := private.get_current_user_id();
  if v_actor is null then
    return false;
  end if;

  if private.current_user_is_admin() then
    return true;
  end if;

  v_scope := private.current_user_scope_for('tasks.edit');

  if v_scope = 'all' then
    return true;
  end if;

  if v_scope = 'assigned' then
    return exists (
      select 1
        from public.project_tasks task_row
       where task_row.id = p_task_id
         and task_row.company_id = p_company_id
         and task_row.deleted_at is null
         and (
           v_actor::text = any(coalesce(task_row.team_member_ids, array[]::text[]))
           or private.current_user_in_project(task_row.project_id)
         )
    );
  end if;

  return false;
end;
$function$;

create or replace function private.current_user_can_write_project_material_workflow(
  p_company_id uuid
) returns boolean
language plpgsql
stable
set search_path to 'public', 'private', 'pg_temp'
as $function$
declare
  v_estimate_scope text;
  v_tasks_edit_scope text;
begin
  if p_company_id is null
     or p_company_id is distinct from private.get_user_company_id() then
    return false;
  end if;

  if coalesce(current_setting('ops.project_material_workflow', true), '') <> 'on' then
    return false;
  end if;

  if coalesce(current_setting('ops.company_inventory_settings_rpc', true), '') = 'on' then
    return private.current_user_has_permission('catalog.manage', 'all');
  end if;

  if coalesce(current_setting('ops.complete_project_task_rpc', true), '') = 'on' then
    v_tasks_edit_scope := private.current_user_scope_for('tasks.edit');
    return private.current_user_is_admin()
      or coalesce(v_tasks_edit_scope, '') in ('all', 'assigned');
  end if;

  if coalesce(current_setting('ops.accept_estimate_to_job_rpc', true), '') <> 'on' then
    return false;
  end if;

  v_estimate_scope := private.current_user_scope_for('estimates.edit');
  v_tasks_edit_scope := private.current_user_scope_for('tasks.edit');

  return (
    private.current_user_is_admin()
    or coalesce(v_estimate_scope, '') in ('all', 'own')
  )
  and (
    private.current_user_is_admin()
    or coalesce(v_tasks_edit_scope, '') in ('all', 'assigned')
  )
  and private.current_user_has_permission('projects.create', 'all')
  and private.current_user_has_permission('projects.edit', 'all')
  and private.current_user_has_permission('tasks.create', 'all')
  and private.current_user_has_permission('pipeline.manage', 'all');
end;
$function$;

create or replace function public.task_material_consumption_requests_write_guard()
returns trigger
language plpgsql
set search_path to 'public', 'private', 'pg_temp'
as $function$
begin
  if coalesce(current_setting('ops.complete_project_task_rpc', true), '') <> 'on' then
    raise exception 'task_material_consumption_requests can only be changed by complete_project_task'
      using errcode = '42501';
  end if;

  if tg_op in ('INSERT', 'UPDATE') then
    if not exists (
      select 1
        from public.project_tasks task_row
       where task_row.id = new.task_id
         and task_row.company_id = new.company_id
         and task_row.deleted_at is null
    ) then
      raise exception 'task_material_consumption_requests task must belong to request company'
        using errcode = '42501';
    end if;

    if new.created_by is not null
       and not exists (
         select 1
           from public.users user_row
          where user_row.id = new.created_by
            and user_row.company_id = new.company_id
            and user_row.deleted_at is null
       ) then
      raise exception 'task_material_consumption_requests created_by must belong to request company'
        using errcode = '42501';
    end if;

    new.updated_at := now();
    return new;
  end if;

  return old;
end;
$function$;

drop trigger if exists trg_task_material_consumption_requests_00_write_guard
  on public.task_material_consumption_requests;
create trigger trg_task_material_consumption_requests_00_write_guard
  before insert or update or delete on public.task_material_consumption_requests
  for each row
  execute function public.task_material_consumption_requests_write_guard();

alter table public.task_material_consumption_requests enable row level security;

drop policy if exists task_material_consumption_requests_select_company
  on public.task_material_consumption_requests;
create policy task_material_consumption_requests_select_company
  on public.task_material_consumption_requests
  for select
  to authenticated
  using (company_id = (select private.get_user_company_id()));

drop policy if exists task_material_consumption_requests_insert_rpc
  on public.task_material_consumption_requests;
create policy task_material_consumption_requests_insert_rpc
  on public.task_material_consumption_requests
  for insert
  to authenticated
  with check (
    private.current_user_can_complete_task_material_consumption(company_id, task_id)
  );

drop policy if exists task_material_consumption_requests_update_rpc
  on public.task_material_consumption_requests;
create policy task_material_consumption_requests_update_rpc
  on public.task_material_consumption_requests
  for update
  to authenticated
  using (
    private.current_user_can_complete_task_material_consumption(company_id, task_id)
  )
  with check (
    private.current_user_can_complete_task_material_consumption(company_id, task_id)
  );

create or replace function private.consume_task_materials_for_completed_task(
  p_task_id uuid,
  p_idempotency_key text,
  p_material_adjustments jsonb default '{}'::jsonb
) returns jsonb
language plpgsql
security invoker
set search_path to 'public', 'private', 'pg_temp'
as $function$
declare
  v_now timestamptz := now();
  v_actor uuid;
  v_company_id uuid;
  v_task public.project_tasks%rowtype;
  v_inventory_mode text := 'off';
  v_request_hash text;
  v_existing public.task_material_consumption_requests%rowtype;
  v_request_id uuid;
  v_snapshot_id uuid;
  v_response jsonb;
  v_demand record;
  v_stock_unit public.catalog_stock_units%rowtype;
  v_adjustment_key text;
  v_adjustment_found boolean;
  v_adjustment jsonb;
  v_requested_quantity numeric;
  v_remaining_quantity numeric;
  v_available_quantity numeric;
  v_new_available_quantity numeric;
  v_consumed_quantity numeric;
  v_overrun_quantity numeric;
  v_stock_take_quantity numeric;
  v_stock_status text;
  v_stock_unit_snapshot jsonb;
  v_stock_unit_unavailable_reason text;
  v_allocation_id uuid;
  v_allocation_key text;
  v_inventory_deduction_id uuid;
  v_stock_event_id uuid;
  v_demand_count integer := 0;
  v_allocation_count integer := 0;
  v_unavailable_allocation_count integer := 0;
  v_stock_unit_count integer := 0;
  v_consumed_total numeric := 0;
  v_overrun_total numeric := 0;
  v_deduction_ids uuid[] := '{}'::uuid[];
  v_stock_event_ids uuid[] := '{}'::uuid[];
  v_stock_row_count integer := 0;
  v_soft_deleted_stock_row_count integer := 0;
  v_live_stock_row_count integer := 0;
  v_exhausted_stock_row_count integer := 0;
  v_status_unavailable_stock_row_count integer := 0;
  v_uuid_pattern constant text := '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$';
begin
  if p_task_id is null then
    raise exception 'task_id_required' using errcode = '22023';
  end if;

  if nullif(btrim(coalesce(p_idempotency_key, '')), '') is null then
    raise exception 'idempotency_key_required' using errcode = '22023';
  end if;

  if char_length(p_idempotency_key) > 200 then
    raise exception 'idempotency_key_too_long' using errcode = '22023';
  end if;

  if jsonb_typeof(coalesce(p_material_adjustments, '{}'::jsonb)) <> 'object' then
    raise exception 'material_adjustments_object_required' using errcode = '23514';
  end if;

  v_actor := private.get_current_user_id();
  v_company_id := private.get_user_company_id();

  if v_actor is null or v_company_id is null then
    raise exception 'actor_company_not_found' using errcode = '42501';
  end if;

  select task_row.*
    into v_task
    from public.project_tasks task_row
   where task_row.id = p_task_id
     and task_row.deleted_at is null
   for update;

  if not found then
    raise exception 'task_not_found' using errcode = 'P0002';
  end if;

  if v_task.company_id is distinct from v_company_id then
    raise exception 'task_company_scope_mismatch' using errcode = '42501';
  end if;

  if v_task.status <> 'completed' then
    raise exception 'task_not_completed' using errcode = '23514';
  end if;

  if not private.current_user_can_complete_task_material_consumption(v_company_id, p_task_id) then
    raise exception 'tasks_edit_required' using errcode = '42501';
  end if;

  v_request_hash := encode(
    extensions.digest(
      convert_to(
        jsonb_build_object(
          'task_id', p_task_id,
          'material_adjustments', coalesce(p_material_adjustments, '{}'::jsonb)
        )::text,
        'UTF8'
      ),
      'sha256'
    ),
    'hex'
  );

  select request_row.*
    into v_existing
    from public.task_material_consumption_requests request_row
   where request_row.company_id = v_company_id
     and request_row.idempotency_key = p_idempotency_key
   for update;

  if found then
    if v_existing.request_hash <> v_request_hash then
      raise exception 'idempotency_conflict' using errcode = '23505';
    end if;

    return v_existing.response
      || jsonb_build_object('idempotent_replay', true);
  end if;

  select request_row.*
    into v_existing
    from public.task_material_consumption_requests request_row
   where request_row.company_id = v_company_id
     and request_row.task_id = p_task_id
   for update;

  if found then
    return v_existing.response
      || jsonb_build_object('task_consumption_replay', true);
  end if;

  insert into public.task_material_consumption_requests (
    company_id,
    task_id,
    idempotency_key,
    request_hash,
    status,
    created_by
  ) values (
    v_company_id,
    p_task_id,
    p_idempotency_key,
    v_request_hash,
    'processing',
    v_actor
  )
  returning id into v_request_id;

  select settings.inventory_mode
    into v_inventory_mode
    from public.company_inventory_settings settings
   where settings.company_id = v_company_id;

  v_inventory_mode := coalesce(v_inventory_mode, 'off');

  if v_inventory_mode <> 'tracked' then
    v_response := jsonb_build_object(
      'ok', true,
      'task_id', p_task_id,
      'company_id', v_company_id,
      'inventory_mode', v_inventory_mode,
      'consumption_performed', false,
      'demand_count', 0,
      'allocation_count', 0,
      'stock_unit_count', 0,
      'unavailable_allocation_count', 0,
      'consumed_quantity', 0,
      'overrun_quantity', 0,
      'request_id', v_request_id
    );

    update public.task_material_consumption_requests
       set status = 'completed',
           response = v_response,
           updated_at = v_now
     where id = v_request_id;

    return v_response;
  end if;

  for v_demand in
    select
      demand_row.id,
      demand_row.demand_key,
      demand_row.project_id,
      demand_row.task_id,
      demand_row.estimate_id,
      demand_row.line_item_id,
      demand_row.product_id,
      demand_row.product_material_id,
      demand_row.catalog_variant_id,
      demand_row.unit_id,
      demand_row.required_quantity,
      demand_row.available_quantity_at_booking,
      demand_row.projected_overrun_quantity,
      demand_row.resolver_payload,
      demand_row.warning_payload
    from public.project_material_demands demand_row
    where demand_row.company_id = v_company_id
      and demand_row.task_id = p_task_id
      and demand_row.deleted_at is null
      and demand_row.status in ('projected', 'warning', 'allocated')
    order by demand_row.created_at, demand_row.id
    for update of demand_row
  loop
    v_demand_count := v_demand_count + 1;
    v_adjustment := '{}'::jsonb;
    v_adjustment_found := false;
    v_stock_row_count := 0;
    v_soft_deleted_stock_row_count := 0;
    v_live_stock_row_count := 0;
    v_exhausted_stock_row_count := 0;
    v_status_unavailable_stock_row_count := 0;

    if v_snapshot_id is null then
      insert into public.project_material_snapshots (
        company_id,
        project_id,
        task_id,
        estimate_id,
        snapshot_kind,
        created_by,
        payload,
        created_at
      ) values (
        v_company_id,
        v_task.project_id,
        p_task_id,
        case
          when nullif(v_task.source_estimate_id, '') ~* v_uuid_pattern then v_task.source_estimate_id::uuid
          else v_demand.estimate_id
        end,
        'task_completion_consumption',
        v_actor,
        jsonb_build_object(
          'idempotency_key', p_idempotency_key,
          'material_adjustments', coalesce(p_material_adjustments, '{}'::jsonb),
          'source', 'project_material_demands',
          'resolution_timing', 'task_completion_live_stock'
        ),
        v_now
      )
      returning id into v_snapshot_id;
    end if;

    for v_adjustment_key in
      select key_value
        from unnest(array[
          v_demand.demand_key,
          v_demand.id::text,
          'demand:' || v_demand.id::text,
          'demand_key:' || v_demand.demand_key
        ]) as adjustment_key(key_value)
       where key_value is not null
    loop
      if coalesce(p_material_adjustments, '{}'::jsonb) ? v_adjustment_key then
        v_adjustment := coalesce(p_material_adjustments, '{}'::jsonb) -> v_adjustment_key;
        v_adjustment_found := true;
        exit;
      end if;
    end loop;

    if not v_adjustment_found then
      for v_adjustment_key in
        select adjustment_key
          from (
            select allocation_row.allocation_key as adjustment_key,
                   allocation_row.created_at,
                   1 as key_rank
              from public.task_material_allocations allocation_row
             where allocation_row.company_id = v_company_id
               and allocation_row.demand_id = v_demand.id
               and allocation_row.deleted_at is null
            union all
            select allocation_row.id::text as adjustment_key,
                   allocation_row.created_at,
                   2 as key_rank
              from public.task_material_allocations allocation_row
             where allocation_row.company_id = v_company_id
               and allocation_row.demand_id = v_demand.id
               and allocation_row.deleted_at is null
            union all
            select 'allocation:' || allocation_row.id::text as adjustment_key,
                   allocation_row.created_at,
                   3 as key_rank
              from public.task_material_allocations allocation_row
             where allocation_row.company_id = v_company_id
               and allocation_row.demand_id = v_demand.id
               and allocation_row.deleted_at is null
          ) existing_keys
         where adjustment_key is not null
         order by key_rank, created_at, adjustment_key
      loop
        if coalesce(p_material_adjustments, '{}'::jsonb) ? v_adjustment_key then
          v_adjustment := coalesce(p_material_adjustments, '{}'::jsonb) -> v_adjustment_key;
          v_adjustment_found := true;
          exit;
        end if;
      end loop;
    end if;

    if jsonb_typeof(v_adjustment) <> 'object' then
      raise exception 'material_adjustment_object_required' using errcode = '23514';
    end if;

    v_requested_quantity := coalesce(
      nullif(v_adjustment ->> 'consumed_quantity', '')::numeric,
      nullif(v_adjustment ->> 'final_quantity', '')::numeric,
      nullif(v_demand.required_quantity, 0),
      0
    );

    if v_requested_quantity < 0 then
      raise exception 'consumed_quantity_must_be_nonnegative' using errcode = '23514';
    end if;

    v_remaining_quantity := v_requested_quantity;

    if v_demand.catalog_variant_id is not null and v_remaining_quantity > 0 then
      for v_stock_unit in
        select stock_unit_row.*
          from public.catalog_stock_units stock_unit_row
         where stock_unit_row.company_id = v_company_id
           and stock_unit_row.catalog_variant_id = v_demand.catalog_variant_id
           and stock_unit_row.deleted_at is null
           and stock_unit_row.status in ('full', 'partial')
           and greatest(
                 coalesce(
                   case
                     when stock_unit_row.remaining_length_value is not null
                       then stock_unit_row.remaining_length_value
                     else stock_unit_row.quantity_value
                   end,
                   0
                 ),
                 0
               ) > 0
         order by stock_unit_row.created_at, stock_unit_row.id
         for update of stock_unit_row
      loop
        v_available_quantity := case
          when v_stock_unit.remaining_length_value is not null then v_stock_unit.remaining_length_value
          else v_stock_unit.quantity_value
        end;
        v_available_quantity := greatest(coalesce(v_available_quantity, 0), 0);
        v_stock_take_quantity := least(v_remaining_quantity, v_available_quantity);

        if v_stock_take_quantity <= 0 then
          continue;
        end if;

        v_allocation_key := v_demand.demand_key || ':stock_unit:' || v_stock_unit.id::text;
        v_consumed_quantity := v_stock_take_quantity;
        v_overrun_quantity := 0;
        v_new_available_quantity := greatest(v_available_quantity - v_consumed_quantity, 0);

        v_stock_status := case
          when v_new_available_quantity = 0 then 'consumed'
          when v_stock_unit.remaining_length_value is not null
               and v_stock_unit.original_length_value is not null
               and v_new_available_quantity < v_stock_unit.original_length_value then 'partial'
          when v_stock_unit.remaining_length_value is null
               and v_new_available_quantity < v_stock_unit.quantity_value then 'partial'
          else v_stock_unit.status
        end;

        v_stock_unit_snapshot := jsonb_build_object(
          'id', v_stock_unit.id,
          'catalog_variant_id', v_stock_unit.catalog_variant_id,
          'unit_kind', v_stock_unit.unit_kind,
          'label', v_stock_unit.label,
          'lot_code', v_stock_unit.lot_code,
          'width_value', v_stock_unit.width_value,
          'width_unit', v_stock_unit.width_unit,
          'original_length_value', v_stock_unit.original_length_value,
          'remaining_length_value_before', v_stock_unit.remaining_length_value,
          'quantity_value_before', v_stock_unit.quantity_value,
          'length_unit', v_stock_unit.length_unit,
          'status_before', v_stock_unit.status,
          'location', v_stock_unit.location,
          'requested_quantity', v_requested_quantity,
          'demand_remaining_quantity_before', v_remaining_quantity,
          'consumed_quantity', v_consumed_quantity,
          'overrun_quantity', 0,
          'shortfall_quantity', 0,
          'stock_unit_available', true
        );

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
          v_company_id,
          null,
          v_demand.id,
          v_demand.catalog_variant_id,
          v_stock_unit.id,
          null,
          v_allocation_key,
          'consumed',
          v_consumed_quantity,
          0,
          0,
          v_stock_unit_snapshot,
          v_now,
          v_now,
          null
        )
        on conflict (company_id, allocation_key)
          where deleted_at is null
        do update
          set task_material_id = coalesce(public.task_material_allocations.task_material_id, excluded.task_material_id),
              demand_id = excluded.demand_id,
              catalog_variant_id = excluded.catalog_variant_id,
              catalog_stock_unit_id = excluded.catalog_stock_unit_id,
              allocation_status = 'consumed',
              allocated_quantity = excluded.allocated_quantity,
              consumed_quantity = excluded.consumed_quantity,
              overrun_quantity = 0,
              stock_unit_snapshot = excluded.stock_unit_snapshot,
              updated_at = v_now
        returning id into v_allocation_id;

        if v_stock_unit.remaining_length_value is not null then
          update public.catalog_stock_units
             set remaining_length_value = v_new_available_quantity,
                 status = v_stock_status,
                 updated_at = v_now
           where id = v_stock_unit.id;
        else
          update public.catalog_stock_units
             set quantity_value = v_new_available_quantity,
                 status = v_stock_status,
                 updated_at = v_now
           where id = v_stock_unit.id;
        end if;

        insert into public.inventory_deductions (
          company_id,
          inventory_item_id,
          project_id,
          task_id,
          line_item_id,
          quantity_deducted,
          previous_quantity,
          new_quantity,
          reason,
          deducted_by,
          deducted_at,
          notes,
          catalog_variant_id
        ) values (
          v_company_id,
          null,
          v_task.project_id,
          p_task_id,
          v_demand.line_item_id,
          v_consumed_quantity::double precision,
          v_available_quantity::double precision,
          v_new_available_quantity::double precision,
          'task_completion',
          v_actor,
          v_now,
          'task_material_completion',
          v_demand.catalog_variant_id
        )
        returning id into v_inventory_deduction_id;

        insert into public.catalog_stock_unit_events (
          company_id,
          catalog_stock_unit_id,
          catalog_variant_id,
          related_catalog_stock_unit_id,
          event_type,
          from_status,
          to_status,
          quantity_delta,
          remaining_length_delta,
          payload,
          notes,
          created_by,
          created_at
        ) values (
          v_company_id,
          v_stock_unit.id,
          v_stock_unit.catalog_variant_id,
          null,
          'consume',
          v_stock_unit.status,
          v_stock_status,
          -v_consumed_quantity,
          case when v_stock_unit.remaining_length_value is not null then -v_consumed_quantity else null end,
          jsonb_build_object(
            'task_id', p_task_id,
            'demand_id', v_demand.id,
            'demand_key', v_demand.demand_key,
            'allocation_id', v_allocation_id,
            'allocation_key', v_allocation_key,
            'inventory_deduction_id', v_inventory_deduction_id,
            'requested_quantity', v_requested_quantity,
            'consumed_quantity', v_consumed_quantity,
            'overrun_quantity', 0,
            'source', 'project_material_demands'
          ),
          'task_completion_consumption',
          v_actor,
          v_now
        )
        returning id into v_stock_event_id;

        v_stock_unit_snapshot := v_stock_unit_snapshot || jsonb_build_object(
          'available_quantity_after', v_new_available_quantity,
          'status_after', v_stock_status,
          'inventory_deduction_id', v_inventory_deduction_id,
          'stock_unit_event_id', v_stock_event_id
        );

        update public.task_material_allocations
           set consumed_quantity = v_consumed_quantity,
               stock_unit_snapshot = v_stock_unit_snapshot,
               inventory_deduction_id = v_inventory_deduction_id,
               updated_at = v_now
         where id = v_allocation_id;

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
        ) values (
          v_company_id,
          v_snapshot_id,
          v_demand.id,
          null,
          v_allocation_id,
          v_inventory_deduction_id,
          v_demand.catalog_variant_id,
          v_stock_unit.id,
          v_stock_event_id,
          v_demand.unit_id,
          v_consumed_quantity,
          0,
          v_stock_unit_snapshot,
          v_now
        );

        v_deduction_ids := array_append(v_deduction_ids, v_inventory_deduction_id);
        v_stock_event_ids := array_append(v_stock_event_ids, v_stock_event_id);
        v_remaining_quantity := greatest(v_remaining_quantity - v_consumed_quantity, 0);
        v_consumed_total := v_consumed_total + v_consumed_quantity;
        v_allocation_count := v_allocation_count + 1;
        v_stock_unit_count := v_stock_unit_count + 1;

        exit when v_remaining_quantity <= 0;
      end loop;
    end if;

    if v_remaining_quantity > 0 or v_requested_quantity = 0 then
      if v_requested_quantity = 0 then
        v_stock_unit_unavailable_reason := 'no_quantity_requested';
      elsif v_demand.catalog_variant_id is null then
        v_stock_unit_unavailable_reason := 'catalog_variant_unmapped';
      else
        select
          count(*)::integer,
          count(*) filter (where stock_unit_row.deleted_at is not null)::integer,
          count(*) filter (where stock_unit_row.deleted_at is null)::integer,
          count(*) filter (
            where stock_unit_row.deleted_at is null
              and stock_unit_row.status in ('full', 'partial')
              and greatest(
                    coalesce(
                      case
                        when stock_unit_row.remaining_length_value is not null
                          then stock_unit_row.remaining_length_value
                        else stock_unit_row.quantity_value
                      end,
                      0
                    ),
                    0
                  ) <= 0
          )::integer,
          count(*) filter (
            where stock_unit_row.deleted_at is null
              and stock_unit_row.status not in ('full', 'partial')
          )::integer
          into v_stock_row_count,
               v_soft_deleted_stock_row_count,
               v_live_stock_row_count,
               v_exhausted_stock_row_count,
               v_status_unavailable_stock_row_count
          from public.catalog_stock_units stock_unit_row
         where stock_unit_row.company_id = v_company_id
           and stock_unit_row.catalog_variant_id = v_demand.catalog_variant_id;

        v_stock_unit_unavailable_reason := case
          when coalesce(v_stock_row_count, 0) = 0 then 'stock_unit_missing'
          when coalesce(v_live_stock_row_count, 0) = 0
               and coalesce(v_soft_deleted_stock_row_count, 0) > 0 then 'stock_unit_soft_deleted'
          when coalesce(v_exhausted_stock_row_count, 0) > 0 then 'stock_unit_exhausted'
          when coalesce(v_status_unavailable_stock_row_count, 0) > 0 then 'stock_unit_unavailable_status'
          else 'stock_unit_unavailable'
        end;
      end if;

      v_overrun_quantity := greatest(v_remaining_quantity, 0);
      v_allocation_key := v_demand.demand_key || ':overrun';
      v_stock_unit_snapshot := jsonb_build_object(
        'catalog_variant_id', v_demand.catalog_variant_id,
        'requested_quantity', v_requested_quantity,
        'consumed_quantity', 0,
        'overrun_quantity', v_overrun_quantity,
        'shortfall_quantity', v_overrun_quantity,
        'available_quantity_at_booking', v_demand.available_quantity_at_booking,
        'stock_unit_available', false,
        'stock_unit_unavailable_reason', v_stock_unit_unavailable_reason,
        'inventory_deduction_id', null,
        'stock_unit_event_id', null,
        'source', 'project_material_demands'
      );

      if v_demand.catalog_variant_id is not null then
        v_stock_unit_snapshot := v_stock_unit_snapshot || jsonb_build_object(
          'stock_unit_candidate_count', coalesce(v_stock_row_count, 0),
          'soft_deleted_stock_unit_count', coalesce(v_soft_deleted_stock_row_count, 0),
          'live_stock_unit_count', coalesce(v_live_stock_row_count, 0),
          'exhausted_stock_unit_count', coalesce(v_exhausted_stock_row_count, 0),
          'status_unavailable_stock_unit_count', coalesce(v_status_unavailable_stock_row_count, 0)
        );
      end if;

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
        v_company_id,
        null,
        v_demand.id,
        v_demand.catalog_variant_id,
        null,
        null,
        v_allocation_key,
        'overrun',
        0,
        0,
        v_overrun_quantity,
        v_stock_unit_snapshot,
        v_now,
        v_now,
        null
      )
      on conflict (company_id, allocation_key)
        where deleted_at is null
      do update
        set task_material_id = coalesce(public.task_material_allocations.task_material_id, excluded.task_material_id),
            demand_id = excluded.demand_id,
            catalog_variant_id = excluded.catalog_variant_id,
            catalog_stock_unit_id = null,
            inventory_deduction_id = null,
            allocation_status = 'overrun',
            allocated_quantity = 0,
            consumed_quantity = 0,
            overrun_quantity = excluded.overrun_quantity,
            stock_unit_snapshot = excluded.stock_unit_snapshot,
            updated_at = v_now
      returning id into v_allocation_id;

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
      ) values (
        v_company_id,
        v_snapshot_id,
        v_demand.id,
        null,
        v_allocation_id,
        null,
        v_demand.catalog_variant_id,
        null,
        null,
        v_demand.unit_id,
        0,
        v_overrun_quantity,
        v_stock_unit_snapshot,
        v_now
      );

      v_overrun_total := v_overrun_total + v_overrun_quantity;
      v_allocation_count := v_allocation_count + 1;
      v_unavailable_allocation_count := v_unavailable_allocation_count + 1;
    end if;
  end loop;

  if v_snapshot_id is not null then
    with per_demand_completion as (
      select
        snapshot_item.demand_id,
        coalesce(sum(snapshot_item.quantity), 0) as consumed_quantity,
        coalesce(sum(snapshot_item.projected_overrun_quantity), 0) as overrun_quantity,
        count(*)::integer as allocation_count
      from public.project_material_snapshot_items snapshot_item
      where snapshot_item.company_id = v_company_id
        and snapshot_item.snapshot_id = v_snapshot_id
        and snapshot_item.demand_id is not null
      group by snapshot_item.demand_id
    )
    update public.project_material_demands demand_row
       set status = 'consumed',
           projected_overrun_quantity = greatest(
             demand_row.projected_overrun_quantity,
             per_demand_completion.overrun_quantity
           ),
           warning_payload = demand_row.warning_payload || jsonb_build_object(
             'completion_consumed_quantity', per_demand_completion.consumed_quantity,
             'completion_overrun_quantity', per_demand_completion.overrun_quantity,
             'completion_snapshot_id', v_snapshot_id,
             'completion_allocation_count', per_demand_completion.allocation_count
           ),
           updated_at = v_now
      from per_demand_completion
     where demand_row.id = per_demand_completion.demand_id
       and demand_row.company_id = v_company_id
       and demand_row.deleted_at is null
       and demand_row.status in ('projected', 'warning', 'allocated');
  end if;

  v_response := jsonb_build_object(
    'ok', true,
    'task_id', p_task_id,
    'company_id', v_company_id,
    'inventory_mode', v_inventory_mode,
    'consumption_performed', v_consumed_total > 0,
    'demand_count', v_demand_count,
    'allocation_count', v_allocation_count,
    'stock_unit_count', v_stock_unit_count,
    'unavailable_allocation_count', v_unavailable_allocation_count,
    'consumed_quantity', v_consumed_total,
    'overrun_quantity', v_overrun_total,
    'snapshot_id', v_snapshot_id,
    'inventory_deduction_ids', to_jsonb(v_deduction_ids),
    'stock_unit_event_ids', to_jsonb(v_stock_event_ids),
    'request_id', v_request_id
  );

  update public.task_material_consumption_requests
     set status = 'completed',
         response = v_response,
         updated_at = v_now
   where id = v_request_id;

  return v_response;
end;
$function$;

create or replace function public.complete_project_task(
  p_task_id uuid,
  p_idempotency_key text,
  p_material_adjustments jsonb default '{}'::jsonb
) returns jsonb
language plpgsql
set search_path to 'public', 'private', 'pg_temp'
as $function$
declare
  v_now timestamptz := now();
  v_actor uuid;
  v_company_id uuid;
  v_task public.project_tasks%rowtype;
  v_status_changed boolean := false;
  v_consumption jsonb;
begin
  if p_task_id is null then
    raise exception 'task_id_required' using errcode = '22023';
  end if;

  if nullif(btrim(coalesce(p_idempotency_key, '')), '') is null then
    raise exception 'idempotency_key_required' using errcode = '22023';
  end if;

  if jsonb_typeof(coalesce(p_material_adjustments, '{}'::jsonb)) <> 'object' then
    raise exception 'material_adjustments_object_required' using errcode = '23514';
  end if;

  v_actor := private.get_current_user_id();
  v_company_id := private.get_user_company_id();

  if v_actor is null or v_company_id is null then
    raise exception 'actor_company_not_found' using errcode = '42501';
  end if;

  perform set_config('ops.complete_project_task_rpc', 'on', true);
  perform set_config('ops.project_material_workflow', 'on', true);

  select task_row.*
    into v_task
    from public.project_tasks task_row
   where task_row.id = p_task_id
     and task_row.deleted_at is null
   for update;

  if not found then
    raise exception 'task_not_found' using errcode = 'P0002';
  end if;

  if v_task.company_id is distinct from v_company_id then
    raise exception 'task_company_scope_mismatch' using errcode = '42501';
  end if;

  if not private.current_user_can_complete_task_material_consumption(v_company_id, p_task_id) then
    raise exception 'tasks_edit_required' using errcode = '42501';
  end if;

  if v_task.status <> 'completed' then
    update public.project_tasks
       set status = 'completed',
           updated_at = v_now
     where id = p_task_id;
    v_status_changed := true;
  end if;

  v_consumption := private.consume_task_materials_for_completed_task(
    p_task_id,
    p_idempotency_key,
    coalesce(p_material_adjustments, '{}'::jsonb)
  );

  return v_consumption || jsonb_build_object(
    'task_status_changed', v_status_changed,
    'completed_by', v_actor,
    'completed_at', v_now
  );
end;
$function$;

revoke all on table public.task_material_consumption_requests from public;
revoke all on table public.task_material_consumption_requests from anon;
revoke all on table public.task_material_consumption_requests from authenticated;
grant select, insert, update on table public.task_material_consumption_requests to authenticated;

revoke execute on function public.task_material_consumption_requests_write_guard()
  from public;
revoke execute on function private.current_user_can_complete_task_material_consumption(uuid, uuid)
  from public;
grant execute on function private.current_user_can_complete_task_material_consumption(uuid, uuid)
  to authenticated;
revoke execute on function private.current_user_can_write_project_material_workflow(uuid)
  from public;
grant execute on function private.current_user_can_write_project_material_workflow(uuid)
  to authenticated;
revoke execute on function private.consume_task_materials_for_completed_task(uuid, text, jsonb)
  from public;
grant execute on function private.consume_task_materials_for_completed_task(uuid, text, jsonb)
  to authenticated;
revoke execute on function public.complete_project_task(uuid, text, jsonb)
  from public;
grant execute on function public.complete_project_task(uuid, text, jsonb)
  to authenticated;

commit;
