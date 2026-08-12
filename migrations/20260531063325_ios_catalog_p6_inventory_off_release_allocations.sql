create or replace function public.set_company_inventory_mode(p_company_id uuid, p_inventory_mode text)
 returns jsonb
 language plpgsql
 set search_path to 'public', 'private', 'pg_temp'
as $function$
declare
  v_actor uuid;
  v_now timestamptz := now();
  v_previous_mode text;
  v_released_demands integer := 0;
  v_release_snapshots integer := 0;
  v_released_allocations integer := 0;
begin
  if p_company_id is null then
    raise exception 'company_id_required' using errcode = '22023';
  end if;

  if p_inventory_mode not in ('off', 'tracked') then
    raise exception 'invalid_inventory_mode' using errcode = '22023';
  end if;

  if p_company_id is distinct from private.get_user_company_id() then
    raise exception 'company_scope_mismatch' using errcode = '42501';
  end if;

  v_actor := private.get_current_user_id();

  if v_actor is null then
    raise exception 'actor_not_found' using errcode = '42501';
  end if;

  if not private.current_user_has_permission('catalog.manage', 'all') then
    raise exception 'catalog_manage_required' using errcode = '42501';
  end if;

  select settings.inventory_mode
    into v_previous_mode
    from public.company_inventory_settings settings
   where settings.company_id = p_company_id
   for update;

  perform set_config('ops.company_inventory_settings_rpc', 'on', true);

  insert into public.company_inventory_settings (
    company_id,
    inventory_mode,
    enabled_at,
    disabled_at,
    updated_by,
    created_at,
    updated_at
  ) values (
    p_company_id,
    p_inventory_mode,
    case when p_inventory_mode = 'tracked' then v_now else null end,
    null,
    v_actor,
    v_now,
    v_now
  )
  on conflict (company_id) do update
    set inventory_mode = excluded.inventory_mode,
        enabled_at = case
          when excluded.inventory_mode = 'tracked'
            and public.company_inventory_settings.inventory_mode <> 'tracked'
            then v_now
          when excluded.inventory_mode = 'tracked'
            then coalesce(public.company_inventory_settings.enabled_at, v_now)
          else public.company_inventory_settings.enabled_at
        end,
        disabled_at = case
          when excluded.inventory_mode = 'off'
            and public.company_inventory_settings.inventory_mode <> 'off'
            then v_now
          when excluded.inventory_mode = 'tracked'
            then null
          else public.company_inventory_settings.disabled_at
        end,
        updated_by = v_actor,
        updated_at = v_now;

  if p_inventory_mode = 'off'
     and coalesce(v_previous_mode, 'off') <> 'off' then
    perform set_config('ops.project_material_workflow', 'on', true);

    with released as (
      update public.project_material_demands demand_row
         set status = 'released',
             updated_at = v_now
       where demand_row.company_id = p_company_id
         and demand_row.deleted_at is null
         and demand_row.status in ('projected', 'warning', 'allocated')
      returning demand_row.id, demand_row.project_id
    ),
    released_allocations as (
      update public.task_material_allocations allocation_row
         set allocation_status = 'released',
             updated_at = v_now
        from released released_row
       where allocation_row.company_id = p_company_id
         and allocation_row.demand_id = released_row.id
         and allocation_row.deleted_at is null
         and allocation_row.allocation_status in ('projected', 'overrun')
      returning allocation_row.id
    ),
    inserted_snapshots as (
      insert into public.project_material_snapshots (
        company_id,
        project_id,
        snapshot_kind,
        created_by,
        payload,
        created_at
      )
      select
        p_company_id,
        project_ids.project_id,
        'inventory_mode_released',
        v_actor,
        jsonb_build_object(
          'released_at', v_now,
          'previous_inventory_mode', v_previous_mode,
          'new_inventory_mode', p_inventory_mode
        ),
        v_now
      from (
        select distinct released.project_id
          from released
      ) project_ids
      returning id
    )
    select
      (select count(*) from released),
      (select count(*) from released_allocations),
      (select count(*) from inserted_snapshots)
      into v_released_demands, v_released_allocations, v_release_snapshots;
  end if;

  return jsonb_build_object(
    'ok', true,
    'company_id', p_company_id,
    'inventory_mode', p_inventory_mode,
    'previous_inventory_mode', coalesce(v_previous_mode, 'off'),
    'updated_by', v_actor,
    'released_demands', v_released_demands,
    'released_allocations', v_released_allocations,
    'release_snapshots', v_release_snapshots
  );
end;
$function$;
