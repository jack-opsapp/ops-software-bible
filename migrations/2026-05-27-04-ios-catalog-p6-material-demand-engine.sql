-- iOS Catalog Phase 6 material demand engine contract.
-- Review-gate draft only. Do not apply without explicit PM approval.
--
-- This migration intentionally exposes no public accept_estimate_to_job RPC.
-- The public acceptance RPC remains gated until project/task sync and
-- tracked-inventory material planning run in one future acceptance transaction.
--
-- The helpers below are side-effect-free. They read accepted estimate lines,
-- product recipes, product-to-catalog mappings, variants, and stock units, then
-- return a deterministic JSONB plan. They do not insert projected demand rows,
-- create notifications, allocate stock, deduct stock, mutate stock-unit events,
-- or change actual inventory balances.
--
-- Execution model: these helpers are private-schema only but must execute as
-- the authenticated caller through future SECURITY INVOKER workflow functions.
-- They are granted to authenticated because downstream helpers derive company
-- scope from the user JWT; they are not service_role-only helpers.

begin;

create schema if not exists private;

create or replace function private.try_parse_uuid(p_value text)
returns uuid
language plpgsql
immutable
security invoker
set search_path to 'public', 'private', 'pg_temp'
as $$
begin
  if p_value is null then
    return null;
  end if;

  if btrim(p_value) ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
    return btrim(p_value)::uuid;
  end if;

  return null;
end;
$$;

revoke all on function private.try_parse_uuid(text)
  from public, anon, authenticated, service_role;
grant execute on function private.try_parse_uuid(text)
  to authenticated;

comment on function private.try_parse_uuid(text)
  is 'Private utility for draft Phase 6 material demand planning. Returns a UUID for canonical UUID text and null otherwise.';

create or replace function private.catalog_variant_available_stock_summary(
  p_company_id uuid,
  p_catalog_variant_id uuid
)
returns jsonb
language sql
stable
security invoker
set search_path to 'public', 'private', 'pg_temp'
as $$
with available_units as (
  select
    unit_row.id,
    unit_row.catalog_variant_id,
    unit_row.unit_kind,
    unit_row.label,
    unit_row.lot_code,
    unit_row.width_value,
    unit_row.width_unit,
    unit_row.original_length_value,
    unit_row.remaining_length_value,
    unit_row.length_unit,
    unit_row.quantity_value,
    unit_row.location,
    unit_row.status,
    unit_row.updated_at,
    coalesce(nullif(lower(btrim(unit_row.length_unit)), ''), 'unit') as length_key,
    coalesce(nullif(lower(btrim(unit_row.width_unit)), ''), 'unit') as width_key
  from public.catalog_stock_units unit_row
  where unit_row.company_id = p_company_id
    and unit_row.catalog_variant_id = p_catalog_variant_id
    and unit_row.deleted_at is null
    and unit_row.status in ('full', 'partial')
),
length_totals as (
  select
    length_key,
    sum(remaining_length_value) as total_quantity
  from available_units
  where remaining_length_value is not null
    and remaining_length_value > 0
  group by length_key
),
length_summary as (
  select
    count(*)::integer as bucket_count,
    max(length_key) as only_key,
    coalesce(sum(total_quantity), 0)::numeric as total_quantity
  from length_totals
),
area_totals as (
  select
    ('sq ' || length_key) as area_key,
    sum(remaining_length_value * width_value) as total_quantity
  from available_units
  where unit_kind in ('roll', 'offcut')
    and remaining_length_value is not null
    and remaining_length_value > 0
    and width_value is not null
    and width_value > 0
    and length_key <> 'unit'
    and length_key = width_key
  group by ('sq ' || length_key)
),
area_summary as (
  select
    count(*)::integer as bucket_count,
    max(area_key) as only_key,
    coalesce(sum(total_quantity), 0)::numeric as total_quantity
  from area_totals
),
quantity_summary as (
  select
    count(*)::integer as active_stock_unit_count,
    coalesce(sum(greatest(quantity_value, 0)), 0)::numeric as total_quantity
  from available_units
),
stock_unit_payload as (
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'catalog_stock_unit_id', id,
        'catalog_variant_id', catalog_variant_id,
        'unit_kind', unit_kind,
        'label', label,
        'lot_code', lot_code,
        'width_value', width_value,
        'width_unit', width_unit,
        'original_length_value', original_length_value,
        'remaining_length_value', remaining_length_value,
        'length_unit', length_unit,
        'quantity_value', quantity_value,
        'location', location,
        'status', status,
        'captured_at', now()
      )
      order by updated_at desc, id
    ),
    '[]'::jsonb
  ) as stock_units
  from available_units
)
select jsonb_build_object(
  'catalog_variant_id', p_catalog_variant_id,
  'active_stock_unit_count', coalesce(quantity_summary.active_stock_unit_count, 0),
  'quantity_value_available', coalesce(quantity_summary.total_quantity, 0),
  'length_available', jsonb_build_object(
    'bucket_count', coalesce(length_summary.bucket_count, 0),
    'unit', length_summary.only_key,
    'quantity', coalesce(length_summary.total_quantity, 0)
  ),
  'area_available', jsonb_build_object(
    'bucket_count', coalesce(area_summary.bucket_count, 0),
    'unit', area_summary.only_key,
    'quantity', coalesce(area_summary.total_quantity, 0)
  ),
  'effective_available_quantity',
    case
      when coalesce(area_summary.bucket_count, 0) = 1
        then coalesce(area_summary.total_quantity, 0)
      when coalesce(area_summary.bucket_count, 0) = 0
       and coalesce(length_summary.bucket_count, 0) = 1
        then coalesce(length_summary.total_quantity, 0)
      else coalesce(quantity_summary.total_quantity, 0)
    end,
  'availability_basis',
    case
      when coalesce(area_summary.bucket_count, 0) = 1
        then 'area:' || area_summary.only_key
      when coalesce(area_summary.bucket_count, 0) = 0
       and coalesce(length_summary.bucket_count, 0) = 1
        then 'length:' || length_summary.only_key
      else 'count'
    end,
  'stock_units', stock_unit_payload.stock_units
)
from quantity_summary
cross join length_summary
cross join area_summary
cross join stock_unit_payload;
$$;

revoke all on function private.catalog_variant_available_stock_summary(uuid, uuid)
  from public, anon, authenticated, service_role;
grant execute on function private.catalog_variant_available_stock_summary(uuid, uuid)
  to authenticated;

comment on function private.catalog_variant_available_stock_summary(uuid, uuid)
  is 'Private Phase 6 helper that summarizes currently available stock units for one catalog variant without mutating inventory.';

create or replace function private.resolve_catalog_variant_for_material_demand(
  p_company_id uuid,
  p_product_id uuid,
  p_catalog_item_id uuid,
  p_configured_options jsonb,
  p_variant_selector jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
stable
security invoker
set search_path to 'public', 'private', 'pg_temp'
as $$
declare
  v_warnings jsonb := '[]'::jsonb;
  v_missing_mappings jsonb := '[]'::jsonb;
  v_required_value_ids uuid[] := '{}'::uuid[];
  v_selector_key text;
  v_selector_expr text;
  v_product_option_id uuid;
  v_product_option_name text;
  v_product_option_kind text;
  v_product_option_affects_recipe boolean;
  v_product_option_required boolean;
  v_config_key text;
  v_config_raw jsonb;
  v_config_text text;
  v_config_uuid uuid;
  v_config_value text;
  v_catalog_option_id uuid;
  v_catalog_option_value_id uuid;
  v_axis_mapping_exists boolean;
  v_candidate_ids uuid[];
  v_candidate_count integer := 0;
  v_selected_variant_id uuid;
begin
  if p_company_id is null or p_product_id is null or p_catalog_item_id is null then
    return jsonb_build_object(
      'catalog_variant_id', null,
      'warnings', jsonb_build_array(jsonb_build_object(
        'code', 'variant_resolution_input_missing',
        'product_id', p_product_id,
        'catalog_item_id', p_catalog_item_id
      )),
      'missing_mappings', '[]'::jsonb,
      'required_catalog_option_value_ids', '[]'::jsonb,
      'matched_variant_count', 0
    );
  end if;

  if jsonb_typeof(coalesce(p_variant_selector, '{}'::jsonb)) = 'object'
     and coalesce(p_variant_selector, '{}'::jsonb) <> '{}'::jsonb then
    for v_selector_key, v_selector_expr in
      select selector_entry.key, selector_entry.value
      from jsonb_each_text(p_variant_selector) as selector_entry(key, value)
      order by selector_entry.key
    loop
      if v_selector_expr not like '$option.%' then
        continue;
      end if;

      v_product_option_name := lower(btrim(substr(v_selector_expr, length('$option.') + 1)));

      select option_row.id, option_row.kind
        into v_product_option_id, v_product_option_kind
        from public.product_options option_row
        join public.products product_row
          on product_row.id = option_row.product_id
       where option_row.product_id = p_product_id
         and product_row.company_id = p_company_id
         and product_row.deleted_at is null
         and option_row.deleted_at is null
         and lower(option_row.name) = v_product_option_name
       order by option_row.sort_order, option_row.id
       limit 1;

      if v_product_option_id is null then
        v_warnings := v_warnings || jsonb_build_array(jsonb_build_object(
          'code', 'selector_product_option_missing',
          'product_id', p_product_id,
          'catalog_item_id', p_catalog_item_id,
          'catalog_option_name', v_selector_key,
          'product_option_name', v_product_option_name
        ));
        continue;
      end if;

      v_config_raw := coalesce(p_configured_options, '{}'::jsonb) -> v_product_option_id::text;

      if v_config_raw is null then
        v_warnings := v_warnings || jsonb_build_array(jsonb_build_object(
          'code', 'selector_configured_option_missing',
          'product_id', p_product_id,
          'catalog_item_id', p_catalog_item_id,
          'catalog_option_name', v_selector_key,
          'product_option_id', v_product_option_id
        ));
        continue;
      end if;

      v_config_text := v_config_raw #>> '{}';
      v_config_uuid := private.try_parse_uuid(v_config_text);

      if v_product_option_kind = 'select' and v_config_uuid is not null then
        select value_row.value
          into v_config_value
          from public.product_option_values value_row
         where value_row.id = v_config_uuid
           and value_row.option_id = v_product_option_id
           and value_row.deleted_at is null
         limit 1;
      else
        v_config_value := v_config_text;
      end if;

      if nullif(v_config_value, '') is null then
        v_warnings := v_warnings || jsonb_build_array(jsonb_build_object(
          'code', 'selector_configured_value_missing',
          'product_id', p_product_id,
          'catalog_item_id', p_catalog_item_id,
          'catalog_option_name', v_selector_key,
          'product_option_id', v_product_option_id
        ));
        continue;
      end if;

      select catalog_option.id
        into v_catalog_option_id
        from public.catalog_options catalog_option
       where catalog_option.catalog_item_id = p_catalog_item_id
         and catalog_option.deleted_at is null
         and lower(catalog_option.name) = lower(v_selector_key)
       order by catalog_option.sort_order, catalog_option.id
       limit 1;

      if v_catalog_option_id is null then
        v_warnings := v_warnings || jsonb_build_array(jsonb_build_object(
          'code', 'selector_catalog_option_missing',
          'product_id', p_product_id,
          'catalog_item_id', p_catalog_item_id,
          'catalog_option_name', v_selector_key
        ));
        continue;
      end if;

      select catalog_value.id
        into v_catalog_option_value_id
        from public.catalog_option_values catalog_value
       where catalog_value.option_id = v_catalog_option_id
         and catalog_value.deleted_at is null
         and lower(catalog_value.value) = lower(v_config_value)
       order by catalog_value.sort_order, catalog_value.id
       limit 1;

      if v_catalog_option_value_id is null then
        v_warnings := v_warnings || jsonb_build_array(jsonb_build_object(
          'code', 'selector_catalog_value_missing',
          'product_id', p_product_id,
          'catalog_item_id', p_catalog_item_id,
          'catalog_option_id', v_catalog_option_id,
          'configured_value', v_config_value
        ));
        continue;
      end if;

      if not (v_catalog_option_value_id = any(v_required_value_ids)) then
        v_required_value_ids := array_append(v_required_value_ids, v_catalog_option_value_id);
      end if;
    end loop;
  else
    for v_config_key, v_config_raw in
      select configured_entry.key, configured_entry.value
      from jsonb_each(coalesce(p_configured_options, '{}'::jsonb)) as configured_entry(key, value)
      order by configured_entry.key
    loop
      v_product_option_id := private.try_parse_uuid(v_config_key);
      if v_product_option_id is null then
        continue;
      end if;

      select option_row.kind, option_row.affects_recipe, option_row.required
        into v_product_option_kind,
             v_product_option_affects_recipe,
             v_product_option_required
        from public.product_options option_row
        join public.products product_row
          on product_row.id = option_row.product_id
       where option_row.id = v_product_option_id
         and option_row.product_id = p_product_id
         and option_row.deleted_at is null
         and product_row.company_id = p_company_id
         and product_row.deleted_at is null
       limit 1;

      if v_product_option_kind is null then
        continue;
      end if;

      if v_product_option_kind <> 'select' then
        continue;
      end if;

      v_config_text := v_config_raw #>> '{}';
      v_config_uuid := private.try_parse_uuid(v_config_text);

      if v_config_uuid is null then
        if v_product_option_affects_recipe then
          v_missing_mappings := v_missing_mappings || jsonb_build_array(jsonb_build_object(
            'code', 'configured_product_option_value_not_uuid',
            'dedupe_key', 'catalog_mapping_needed:product:' || p_product_id::text || ':catalog_item:' || p_catalog_item_id::text || ':option:' || v_product_option_id::text,
            'product_id', p_product_id,
            'catalog_item_id', p_catalog_item_id,
            'product_option_id', v_product_option_id
          ));
        end if;
        continue;
      end if;

      select exists (
        select 1
          from public.catalog_product_option_mappings mapping_row
         where mapping_row.company_id = p_company_id
           and mapping_row.product_id = p_product_id
           and mapping_row.catalog_item_id = p_catalog_item_id
           and mapping_row.product_option_id = v_product_option_id
           and mapping_row.mapping_kind = 'axis'
           and mapping_row.deleted_at is null
      )
      into v_axis_mapping_exists;

      if not v_axis_mapping_exists and v_product_option_affects_recipe then
        v_missing_mappings := v_missing_mappings || jsonb_build_array(jsonb_build_object(
          'code', 'product_catalog_axis_mapping_missing',
          'dedupe_key', 'catalog_mapping_needed:product:' || p_product_id::text || ':catalog_item:' || p_catalog_item_id::text || ':option:' || v_product_option_id::text,
          'product_id', p_product_id,
          'catalog_item_id', p_catalog_item_id,
          'product_option_id', v_product_option_id
        ));
        continue;
      end if;

      select mapping_row.catalog_option_value_id
        into v_catalog_option_value_id
        from public.catalog_product_option_mappings mapping_row
       where mapping_row.company_id = p_company_id
         and mapping_row.product_id = p_product_id
         and mapping_row.catalog_item_id = p_catalog_item_id
         and mapping_row.product_option_id = v_product_option_id
         and mapping_row.product_option_value_id = v_config_uuid
         and mapping_row.mapping_kind = 'value'
         and mapping_row.deleted_at is null
       order by mapping_row.updated_at desc, mapping_row.id
       limit 1;

      if v_catalog_option_value_id is null then
        if v_axis_mapping_exists or v_product_option_affects_recipe then
          v_missing_mappings := v_missing_mappings || jsonb_build_array(jsonb_build_object(
            'code', 'product_catalog_value_mapping_missing',
            'dedupe_key', 'catalog_mapping_needed:product:' || p_product_id::text || ':catalog_item:' || p_catalog_item_id::text || ':option:' || v_product_option_id::text || ':value:' || v_config_uuid::text,
            'product_id', p_product_id,
            'catalog_item_id', p_catalog_item_id,
            'product_option_id', v_product_option_id,
            'product_option_value_id', v_config_uuid
          ));
        end if;
        continue;
      end if;

      if not (v_catalog_option_value_id = any(v_required_value_ids)) then
        v_required_value_ids := array_append(v_required_value_ids, v_catalog_option_value_id);
      end if;
    end loop;

    for v_product_option_id in
      select option_row.id
      from public.product_options option_row
      join public.products product_row
        on product_row.id = option_row.product_id
      where option_row.product_id = p_product_id
        and option_row.kind = 'select'
        and option_row.required = true
        and option_row.affects_recipe = true
        and option_row.deleted_at is null
        and product_row.company_id = p_company_id
        and product_row.deleted_at is null
        and not (coalesce(p_configured_options, '{}'::jsonb) ? option_row.id::text)
      order by option_row.sort_order, option_row.id
    loop
      v_missing_mappings := v_missing_mappings || jsonb_build_array(jsonb_build_object(
        'code', 'required_recipe_option_unconfigured',
        'dedupe_key', 'catalog_mapping_needed:product:' || p_product_id::text || ':catalog_item:' || p_catalog_item_id::text || ':option:' || v_product_option_id::text,
        'product_id', p_product_id,
        'catalog_item_id', p_catalog_item_id,
        'product_option_id', v_product_option_id
      ));
    end loop;
  end if;

  v_warnings := v_warnings || v_missing_mappings;

  select array_agg(candidate.id order by candidate.id), count(*)::integer
    into v_candidate_ids, v_candidate_count
    from public.catalog_variants candidate
   where candidate.company_id = p_company_id
     and candidate.catalog_item_id = p_catalog_item_id
     and candidate.deleted_at is null
     and candidate.is_active = true
     and (
       cardinality(v_required_value_ids) = 0
       or not exists (
         select 1
           from unnest(v_required_value_ids) as required_value(id)
          where not exists (
            select 1
              from public.catalog_variant_option_values candidate_value
             where candidate_value.variant_id = candidate.id
               and candidate_value.option_value_id = required_value.id
               and candidate_value.deleted_at is null
          )
       )
     );

  if v_candidate_count = 1 then
    v_selected_variant_id := v_candidate_ids[1];
  elsif v_candidate_count = 0 then
    v_warnings := v_warnings || jsonb_build_array(jsonb_build_object(
      'code', 'catalog_variant_not_resolved',
      'product_id', p_product_id,
      'catalog_item_id', p_catalog_item_id,
      'required_catalog_option_value_ids', to_jsonb(v_required_value_ids)
    ));
  else
    v_selected_variant_id := v_candidate_ids[1];
    v_warnings := v_warnings || jsonb_build_array(jsonb_build_object(
      'code', 'catalog_variant_resolution_ambiguous',
      'product_id', p_product_id,
      'catalog_item_id', p_catalog_item_id,
      'selected_catalog_variant_id', v_selected_variant_id,
      'matched_variant_count', v_candidate_count,
      'resolution_rule', 'lowest_uuid'
    ));
  end if;

  return jsonb_build_object(
    'catalog_variant_id', v_selected_variant_id,
    'warnings', v_warnings,
    'missing_mappings', v_missing_mappings,
    'required_catalog_option_value_ids', to_jsonb(v_required_value_ids),
    'matched_variant_count', v_candidate_count
  );
end;
$$;

revoke all on function private.resolve_catalog_variant_for_material_demand(uuid, uuid, uuid, jsonb, jsonb)
  from public, anon, authenticated, service_role;
grant execute on function private.resolve_catalog_variant_for_material_demand(uuid, uuid, uuid, jsonb, jsonb)
  to authenticated;

comment on function private.resolve_catalog_variant_for_material_demand(uuid, uuid, uuid, jsonb, jsonb)
  is 'Private Phase 6 resolver that maps configured estimate product options to one catalog variant and returns soft warning metadata when product-to-stock mappings are incomplete.';

create or replace function private.resolve_estimate_material_demand_plan(
  p_estimate_id uuid,
  p_project_id uuid default null
)
returns jsonb
language plpgsql
stable
security invoker
set search_path to 'public', 'private', 'pg_temp'
as $$
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
      coalesce(task_for_line.id, task_for_parent.id) as task_id
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
$$;

revoke all on function private.resolve_estimate_material_demand_plan(uuid, uuid)
  from public, anon, authenticated, service_role;
grant execute on function private.resolve_estimate_material_demand_plan(uuid, uuid)
  to authenticated;

comment on function private.resolve_estimate_material_demand_plan(uuid, uuid)
  is 'Private draft Phase 6 material demand resolver. Returns deterministic JSONB demand, missing-mapping, and projected-overrun metadata for an accepted estimate/project without writing inventory tables.';

commit;
