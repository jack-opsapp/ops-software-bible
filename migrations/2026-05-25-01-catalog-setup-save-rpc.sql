-- Catalog setup atomic save RPC foundation.
-- Approved draft target only. Do not apply without explicit migration approval.

begin;

create or replace function public.fn_set_updated_at()
returns trigger
language plpgsql
set search_path to 'public', 'pg_temp'
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

create table if not exists public.catalog_setup_save_requests (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  idempotency_key text not null,
  request_hash text not null,
  status text not null,
  response jsonb,
  error jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  completed_at timestamptz,
  constraint catalog_setup_save_requests_status_check
    check (status in ('processing', 'succeeded', 'failed')),
  constraint catalog_setup_save_requests_company_key_unique
    unique (company_id, idempotency_key)
);

create index if not exists idx_catalog_setup_save_requests_company_status
  on public.catalog_setup_save_requests(company_id, status, updated_at);

create index if not exists idx_catalog_setup_save_requests_company_completed
  on public.catalog_setup_save_requests(company_id, completed_at)
  where completed_at is not null;

drop trigger if exists trg_catalog_setup_save_requests_updated_at
  on public.catalog_setup_save_requests;
create trigger trg_catalog_setup_save_requests_updated_at
  before update on public.catalog_setup_save_requests
  for each row
  execute function public.fn_set_updated_at();

create or replace function public.catalog_setup_save_requests_write_guard()
returns trigger
language plpgsql
security invoker
set search_path to 'public', 'pg_temp'
as $$
begin
  if coalesce(current_setting('ops.catalog_setup_save_rpc', true), '') <> 'on' then
    raise exception 'catalog_setup_save_requests can only be changed by catalog_setup_save'
      using errcode = '42501';
  end if;

  return coalesce(new, old);
end;
$$;

drop trigger if exists trg_catalog_setup_save_requests_00_write_guard
  on public.catalog_setup_save_requests;
create trigger trg_catalog_setup_save_requests_00_write_guard
  before insert or update or delete on public.catalog_setup_save_requests
  for each row
  execute function public.catalog_setup_save_requests_write_guard();

alter table public.catalog_setup_save_requests enable row level security;

drop policy if exists company_isolation on public.catalog_setup_save_requests;
create policy company_isolation
  on public.catalog_setup_save_requests
  for all
  to authenticated
  using (company_id = (select private.get_user_company_id()))
  with check (company_id = (select private.get_user_company_id()));

revoke all on table public.catalog_setup_save_requests from public;
revoke all on table public.catalog_setup_save_requests from anon;
grant select, insert, update on table public.catalog_setup_save_requests to authenticated;

create table if not exists public.catalog_stock_unit_events (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  catalog_stock_unit_id uuid not null references public.catalog_stock_units(id) on delete cascade,
  catalog_variant_id uuid not null references public.catalog_variants(id) on delete cascade,
  related_catalog_stock_unit_id uuid references public.catalog_stock_units(id) on delete set null,
  event_type text not null,
  from_status text,
  to_status text,
  quantity_delta numeric,
  remaining_length_delta numeric,
  payload jsonb not null default '{}'::jsonb,
  marker text,
  notes text,
  created_by uuid default auth.uid(),
  created_at timestamptz not null default now(),
  constraint catalog_stock_unit_events_type_check
    check (event_type in (
      'receive',
      'consume',
      'scrap',
      'offcut_create',
      'adjust',
      'reserve',
      'release',
      'restore',
      'delete'
    )),
  constraint catalog_stock_unit_events_from_status_check
    check (
      from_status is null
      or from_status in ('full', 'partial', 'reserved', 'consumed', 'scrapped')
    ),
  constraint catalog_stock_unit_events_to_status_check
    check (
      to_status is null
      or to_status in ('full', 'partial', 'reserved', 'consumed', 'scrapped')
    )
);

create index if not exists idx_catalog_stock_unit_events_company_time
  on public.catalog_stock_unit_events(company_id, created_at desc);

create index if not exists idx_catalog_stock_unit_events_unit_time
  on public.catalog_stock_unit_events(catalog_stock_unit_id, created_at desc);

create index if not exists idx_catalog_stock_unit_events_variant_time
  on public.catalog_stock_unit_events(catalog_variant_id, created_at desc);

create index if not exists idx_catalog_stock_unit_events_related_unit
  on public.catalog_stock_unit_events(related_catalog_stock_unit_id)
  where related_catalog_stock_unit_id is not null;

create index if not exists idx_catalog_stock_unit_events_company_type_time
  on public.catalog_stock_unit_events(company_id, event_type, created_at desc);

create or replace function public.catalog_stock_unit_events_company_guard()
returns trigger
language plpgsql
security invoker
set search_path to 'public', 'pg_temp'
as $$
begin
  if not exists (
    select 1
      from public.catalog_stock_units unit_row
     where unit_row.id = new.catalog_stock_unit_id
       and unit_row.company_id = new.company_id
       and unit_row.catalog_variant_id = new.catalog_variant_id
  ) then
    raise exception 'catalog_stock_unit_events stock unit must belong to event company and variant'
      using errcode = '42501';
  end if;

  if not exists (
    select 1
      from public.catalog_variants variant_row
     where variant_row.id = new.catalog_variant_id
       and variant_row.company_id = new.company_id
  ) then
    raise exception 'catalog_stock_unit_events variant must belong to event company'
      using errcode = '42501';
  end if;

  if new.related_catalog_stock_unit_id is not null
     and not exists (
       select 1
         from public.catalog_stock_units related_unit_row
        where related_unit_row.id = new.related_catalog_stock_unit_id
          and related_unit_row.company_id = new.company_id
     ) then
    raise exception 'catalog_stock_unit_events related stock unit must belong to event company'
      using errcode = '42501';
  end if;

  return new;
end;
$$;

drop trigger if exists trg_catalog_stock_unit_events_company_guard
  on public.catalog_stock_unit_events;
create trigger trg_catalog_stock_unit_events_company_guard
  before insert or update on public.catalog_stock_unit_events
  for each row
  execute function public.catalog_stock_unit_events_company_guard();

alter table public.catalog_options
  add column if not exists updated_at timestamptz not null default now(),
  add column if not exists deleted_at timestamptz;

alter table public.catalog_option_values
  add column if not exists id uuid default gen_random_uuid(),
  add column if not exists created_at timestamptz not null default now(),
  add column if not exists updated_at timestamptz not null default now(),
  add column if not exists deleted_at timestamptz;

alter table public.catalog_option_values
  drop constraint if exists catalog_option_values_option_id_value_key;

create unique index if not exists catalog_option_values_option_value_active_unique
  on public.catalog_option_values(option_id, lower(btrim(value)))
  where deleted_at is null;

alter table public.catalog_variant_option_values
  add column if not exists id uuid default gen_random_uuid(),
  add column if not exists created_at timestamptz not null default now(),
  add column if not exists updated_at timestamptz not null default now(),
  add column if not exists deleted_at timestamptz;

update public.catalog_variant_option_values
   set id = gen_random_uuid()
 where id is null;

alter table public.catalog_variant_option_values
  alter column id set not null,
  drop constraint if exists catalog_variant_option_values_pkey;

do $$
begin
  if not exists (
    select 1
      from pg_constraint
     where conname = 'catalog_variant_option_values_pkey'
       and conrelid = 'public.catalog_variant_option_values'::regclass
  ) then
    alter table public.catalog_variant_option_values
      add constraint catalog_variant_option_values_pkey primary key (id);
  end if;
end;
$$;

create unique index if not exists catalog_variant_option_values_active_unique
  on public.catalog_variant_option_values(variant_id, option_value_id)
  where deleted_at is null;

alter table public.product_options
  add column if not exists updated_at timestamptz not null default now(),
  add column if not exists deleted_at timestamptz;

alter table public.product_option_values
  add column if not exists created_at timestamptz not null default now(),
  add column if not exists updated_at timestamptz not null default now(),
  add column if not exists deleted_at timestamptz;

alter table public.product_option_values
  drop constraint if exists product_option_values_option_id_value_key;

create unique index if not exists product_option_values_option_value_active_unique
  on public.product_option_values(option_id, lower(btrim(value)))
  where deleted_at is null;

alter table public.product_pricing_modifiers
  add column if not exists updated_at timestamptz not null default now(),
  add column if not exists deleted_at timestamptz;

alter table public.product_materials
  add column if not exists updated_at timestamptz not null default now(),
  add column if not exists deleted_at timestamptz;

create index if not exists idx_catalog_options_item_active
  on public.catalog_options(catalog_item_id, sort_order)
  where deleted_at is null;

create index if not exists idx_catalog_option_values_option_active
  on public.catalog_option_values(option_id, sort_order)
  where deleted_at is null;

create index if not exists idx_catalog_variant_option_values_variant_active
  on public.catalog_variant_option_values(variant_id)
  where deleted_at is null;

create index if not exists idx_product_options_product_active
  on public.product_options(product_id, sort_order)
  where deleted_at is null;

create index if not exists idx_product_option_values_option_active
  on public.product_option_values(option_id, sort_order)
  where deleted_at is null;

create index if not exists idx_product_pricing_modifiers_product_active
  on public.product_pricing_modifiers(product_id)
  where deleted_at is null;

create index if not exists idx_product_materials_product_active
  on public.product_materials(product_id)
  where deleted_at is null;

drop trigger if exists trg_catalog_options_updated_at
  on public.catalog_options;
create trigger trg_catalog_options_updated_at
  before update on public.catalog_options
  for each row
  execute function public.fn_set_updated_at();

drop trigger if exists trg_catalog_option_values_updated_at
  on public.catalog_option_values;
create trigger trg_catalog_option_values_updated_at
  before update on public.catalog_option_values
  for each row
  execute function public.fn_set_updated_at();

drop trigger if exists trg_catalog_variant_option_values_updated_at
  on public.catalog_variant_option_values;
create trigger trg_catalog_variant_option_values_updated_at
  before update on public.catalog_variant_option_values
  for each row
  execute function public.fn_set_updated_at();

drop trigger if exists trg_product_options_updated_at
  on public.product_options;
create trigger trg_product_options_updated_at
  before update on public.product_options
  for each row
  execute function public.fn_set_updated_at();

drop trigger if exists trg_product_option_values_updated_at
  on public.product_option_values;
create trigger trg_product_option_values_updated_at
  before update on public.product_option_values
  for each row
  execute function public.fn_set_updated_at();

drop trigger if exists trg_product_pricing_modifiers_updated_at
  on public.product_pricing_modifiers;
create trigger trg_product_pricing_modifiers_updated_at
  before update on public.product_pricing_modifiers
  for each row
  execute function public.fn_set_updated_at();

drop trigger if exists trg_product_materials_updated_at
  on public.product_materials;
create trigger trg_product_materials_updated_at
  before update on public.product_materials
  for each row
  execute function public.fn_set_updated_at();

alter table public.catalog_stock_unit_events enable row level security;

drop policy if exists catalog_stock_unit_events_select_company on public.catalog_stock_unit_events;
create policy catalog_stock_unit_events_select_company
  on public.catalog_stock_unit_events
  for select
  to authenticated
  using (company_id = (select private.get_user_company_id()));

drop policy if exists catalog_stock_unit_events_insert_company on public.catalog_stock_unit_events;
create policy catalog_stock_unit_events_insert_company
  on public.catalog_stock_unit_events
  for insert
  to authenticated
  with check (
    company_id = (select private.get_user_company_id())
    and exists (
      select 1
        from public.catalog_stock_units unit_row
       where unit_row.id = catalog_stock_unit_events.catalog_stock_unit_id
         and unit_row.company_id = catalog_stock_unit_events.company_id
         and unit_row.catalog_variant_id = catalog_stock_unit_events.catalog_variant_id
    )
    and exists (
      select 1
        from public.catalog_variants variant_row
       where variant_row.id = catalog_stock_unit_events.catalog_variant_id
         and variant_row.company_id = catalog_stock_unit_events.company_id
    )
    and (
      related_catalog_stock_unit_id is null
      or exists (
        select 1
          from public.catalog_stock_units related_unit_row
         where related_unit_row.id = catalog_stock_unit_events.related_catalog_stock_unit_id
           and related_unit_row.company_id = catalog_stock_unit_events.company_id
      )
    )
  );

revoke all on table public.catalog_stock_unit_events from public;
revoke all on table public.catalog_stock_unit_events from anon;
grant select, insert on table public.catalog_stock_unit_events to authenticated;

create or replace function public.catalog_setup_save(
  p_company_id uuid,
  p_idempotency_key text,
  p_payload jsonb
) returns jsonb
language plpgsql
security invoker
set search_path to 'public', 'private', 'pg_temp'
as $$
declare
  v_now timestamptz := now();
  v_request_hash text;
  v_request public.catalog_setup_save_requests%rowtype;
  v_mode text;
  v_blockers jsonb := '[]'::jsonb;
  v_warnings jsonb := '[]'::jsonb;
  v_tmp jsonb := '[]'::jsonb;
  v_response jsonb;
  v_id_map jsonb := '{}'::jsonb;
  v_array_key text;
  v_catalog_options jsonb := '[]'::jsonb;
  v_variants jsonb := '[]'::jsonb;
  v_stock_units jsonb := '[]'::jsonb;
  v_stock_unit_events jsonb := '[]'::jsonb;
  v_products jsonb := '[]'::jsonb;
  v_product_materials jsonb := '[]'::jsonb;
  v_deleted_ids jsonb := '{}'::jsonb;
  v_uuid_pattern constant text := '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$';
  v_client_id text;
  v_candidate_text text;
  v_ref_text text;
  v_candidate_uuid uuid;
  v_ref_uuid uuid;
  v_family_id uuid;
  v_catalog_option_id uuid;
  v_catalog_option_value_id uuid;
  v_catalog_variant_id uuid;
  v_catalog_stock_unit_id uuid;
  v_product_id uuid;
  v_product_option_id uuid;
  v_product_option_value_id uuid;
  v_product_catalog_item_id uuid;
  v_related_stock_unit_id uuid;
  v_product_doc jsonb;
  v_product_ord integer;
  v_option_doc jsonb;
  v_value_doc jsonb;
  v_variant_doc jsonb;
  v_stock_doc jsonb;
  v_modifier_doc jsonb;
  v_material_doc jsonb;
  v_mapping_doc jsonb;
  v_bundle_doc jsonb;
  v_stock_event_doc jsonb;
  v_existing_stock_status text;
  v_existing_stock_quantity numeric;
  v_existing_stock_remaining numeric;
  v_existing_stock_deleted_at timestamptz;
  v_existing_stock_variant_id uuid;
  v_event_type text;
  v_quantity_delta numeric;
  v_remaining_length_delta numeric;
  v_write_count integer := 0;
  v_catalog_items_count integer := 0;
  v_catalog_options_count integer := 0;
  v_catalog_option_values_count integer := 0;
  v_catalog_variants_count integer := 0;
  v_catalog_variant_option_values_count integer := 0;
  v_catalog_stock_units_count integer := 0;
  v_products_count integer := 0;
  v_product_options_count integer := 0;
  v_product_option_values_count integer := 0;
  v_product_pricing_modifiers_count integer := 0;
  v_product_materials_count integer := 0;
  v_catalog_product_option_mappings_count integer := 0;
  v_product_bundle_items_count integer := 0;
  v_catalog_stock_unit_events_count integer := 0;
  v_deleted_catalog_items_count integer := 0;
  v_deleted_catalog_options_count integer := 0;
  v_deleted_catalog_option_values_count integer := 0;
  v_deleted_catalog_variants_count integer := 0;
  v_deleted_catalog_variant_option_values_count integer := 0;
  v_deleted_catalog_stock_units_count integer := 0;
  v_deleted_products_count integer := 0;
  v_deleted_product_options_count integer := 0;
  v_deleted_product_option_values_count integer := 0;
  v_deleted_product_pricing_modifiers_count integer := 0;
  v_deleted_product_materials_count integer := 0;
  v_deleted_catalog_product_option_mappings_count integer := 0;
  v_deleted_product_bundle_items_count integer := 0;
  v_write_sections jsonb := jsonb_build_array(
    'catalog_family',
    'catalog_options',
    'catalog_option_values',
    'catalog_variants',
    'catalog_variant_option_values',
    'catalog_stock_units',
    'products',
    'product_options',
    'product_option_values',
    'product_pricing_modifiers',
    'product_materials',
    'catalog_product_option_mappings',
    'product_bundle_items',
    'catalog_stock_unit_events'
  );
begin
  if p_company_id is null then
    return jsonb_build_object(
      'ok', false,
      'warnings', '[]'::jsonb,
      'blockers', jsonb_build_array(jsonb_build_object(
        'code', 'company_id_required',
        'path', 'p_company_id',
        'message', 'Company id is required.'
      ))
    );
  end if;

  if p_company_id is distinct from private.get_user_company_id() then
    return jsonb_build_object(
      'ok', false,
      'warnings', '[]'::jsonb,
      'blockers', jsonb_build_array(jsonb_build_object(
        'code', 'company_scope_mismatch',
        'path', 'p_company_id',
        'message', 'Company scope does not match authenticated user.'
      ))
    );
  end if;

  if nullif(btrim(coalesce(p_idempotency_key, '')), '') is null then
    return jsonb_build_object(
      'ok', false,
      'warnings', '[]'::jsonb,
      'blockers', jsonb_build_array(jsonb_build_object(
        'code', 'idempotency_key_required',
        'path', 'p_idempotency_key',
        'message', 'A stable idempotency key is required for catalog setup save.'
      ))
    );
  end if;

  if p_payload is null or jsonb_typeof(p_payload) <> 'object' then
    return jsonb_build_object(
      'ok', false,
      'warnings', '[]'::jsonb,
      'blockers', jsonb_build_array(jsonb_build_object(
        'code', 'payload_object_required',
        'path', 'p_payload',
        'message', 'Catalog setup save payload must be a JSON object.'
      ))
    );
  end if;

  v_request_hash := encode(extensions.digest(convert_to(p_payload::text, 'utf8'), 'sha256'), 'hex');

  perform set_config('ops.catalog_setup_save_rpc', 'on', true);

  insert into public.catalog_setup_save_requests (
    company_id,
    idempotency_key,
    request_hash,
    status
  )
  values (
    p_company_id,
    btrim(p_idempotency_key),
    v_request_hash,
    'processing'
  )
  on conflict (company_id, idempotency_key) do nothing
  returning * into v_request;

  if v_request.id is null then
    select *
      into v_request
      from public.catalog_setup_save_requests
     where company_id = p_company_id
       and idempotency_key = btrim(p_idempotency_key)
     for update;
  else
    select *
      into v_request
      from public.catalog_setup_save_requests
     where id = v_request.id
     for update;
  end if;

  if v_request.request_hash <> v_request_hash then
    return jsonb_build_object(
      'ok', false,
      'mode', coalesce(p_payload->>'mode', 'unknown'),
      'company_id', p_company_id,
      'idempotency_key', btrim(p_idempotency_key),
      'warnings', '[]'::jsonb,
      'blockers', jsonb_build_array(jsonb_build_object(
        'code', 'idempotency_conflict',
        'path', 'p_idempotency_key',
        'message', 'The same idempotency key was already used for a different catalog setup payload.'
      ))
    );
  end if;

  if v_request.status = 'succeeded' and v_request.response is not null then
    return v_request.response;
  end if;

  update public.catalog_setup_save_requests
     set status = 'processing',
         response = null,
         error = null,
         completed_at = null
   where id = v_request.id
  returning * into v_request;

  v_mode := coalesce(nullif(btrim(p_payload->>'mode'), ''), 'create');

  if v_mode not in ('create', 'edit') then
    v_blockers := v_blockers || jsonb_build_array(jsonb_build_object(
      'code', 'invalid_mode',
      'path', 'mode',
      'message', 'Mode must be create or edit.'
    ));
  end if;

  foreach v_array_key in array array[
    'catalog_options',
    'variants',
    'stock_units',
    'stock_unit_events',
    'products',
    'product_materials'
  ] loop
    if p_payload ? v_array_key
       and jsonb_typeof(p_payload -> v_array_key) <> 'array' then
      v_blockers := v_blockers || jsonb_build_array(jsonb_build_object(
        'code', 'array_required',
        'path', v_array_key,
        'message', v_array_key || ' must be a JSON array when supplied.'
      ));
    end if;
  end loop;

  if p_payload ? 'deleted_ids'
     and jsonb_typeof(p_payload -> 'deleted_ids') <> 'object' then
    v_blockers := v_blockers || jsonb_build_array(jsonb_build_object(
      'code', 'deleted_ids_object_required',
      'path', 'deleted_ids',
      'message', 'Edit deletes must be explicit under deleted_ids.'
    ));
  end if;

  v_catalog_options := case
    when jsonb_typeof(p_payload -> 'catalog_options') = 'array' then p_payload -> 'catalog_options'
    else '[]'::jsonb
  end;
  v_variants := case
    when jsonb_typeof(p_payload -> 'variants') = 'array' then p_payload -> 'variants'
    else '[]'::jsonb
  end;
  v_stock_units := case
    when jsonb_typeof(p_payload -> 'stock_units') = 'array' then p_payload -> 'stock_units'
    else '[]'::jsonb
  end;
  v_stock_unit_events := case
    when jsonb_typeof(p_payload -> 'stock_unit_events') = 'array' then p_payload -> 'stock_unit_events'
    else '[]'::jsonb
  end;
  v_products := case
    when jsonb_typeof(p_payload -> 'products') = 'array' then p_payload -> 'products'
    else '[]'::jsonb
  end;
  v_product_materials := case
    when jsonb_typeof(p_payload -> 'product_materials') = 'array' then p_payload -> 'product_materials'
    else '[]'::jsonb
  end;
  v_deleted_ids := case
    when jsonb_typeof(p_payload -> 'deleted_ids') = 'object' then p_payload -> 'deleted_ids'
    else '{}'::jsonb
  end;

  if v_mode = 'create'
     and (
       jsonb_typeof(p_payload -> 'family') <> 'object'
       or nullif(btrim(coalesce(p_payload #>> '{family,name}', '')), '') is null
     ) then
    v_blockers := v_blockers || jsonb_build_array(jsonb_build_object(
      'code', 'family_name_required',
      'path', 'family.name',
      'message', 'Catalog family name is required.'
    ));
  end if;

  if v_mode = 'edit'
     and nullif(btrim(coalesce(p_payload #>> '{family,id}', p_payload #>> '{family_id}', '')), '') is null
     and not exists (
       select 1
       from jsonb_array_elements(v_products) as product_doc
       where nullif(btrim(coalesce(product_doc->>'id', '')), '') is not null
     )
     and not exists (
       select 1
         from jsonb_each(v_deleted_ids) as deleted_collection(key, value)
        where jsonb_typeof(deleted_collection.value) = 'array'
          and jsonb_array_length(deleted_collection.value) > 0
     ) then
    v_blockers := v_blockers || jsonb_build_array(jsonb_build_object(
      'code', 'edit_target_required',
      'path', 'family.id',
      'message', 'Edit mode requires an existing family id or product id.'
    ));
  end if;

  foreach v_array_key in array array[
    'catalog_items',
    'catalog_options',
    'catalog_option_values',
    'catalog_variants',
    'catalog_variant_option_values',
    'catalog_stock_units',
    'products',
    'product_options',
    'product_option_values',
    'product_pricing_modifiers',
    'product_materials',
    'product_bundle_items',
    'catalog_product_option_mappings'
  ] loop
    if v_deleted_ids ? v_array_key
       and jsonb_typeof(v_deleted_ids -> v_array_key) <> 'array' then
      v_blockers := v_blockers || jsonb_build_array(jsonb_build_object(
        'code', 'deleted_ids_array_required',
        'path', 'deleted_ids.' || v_array_key,
        'message', 'Each deleted_ids collection must be an array.'
      ));
    end if;
  end loop;

  with client_ids as (
    select nullif(btrim(p_payload #>> '{family,client_id}'), '') as client_id,
           'family.client_id' as path
    where jsonb_typeof(p_payload -> 'family') = 'object'
    union all
    select nullif(btrim(option_doc->>'client_id'), ''),
           format('catalog_options[%s].client_id', option_ord - 1)
      from jsonb_array_elements(v_catalog_options) with ordinality as option_item(option_doc, option_ord)
    union all
    select nullif(btrim(value_doc->>'client_id'), ''),
           format('catalog_options[%s].values[%s].client_id', option_ord - 1, value_ord - 1)
      from jsonb_array_elements(v_catalog_options) with ordinality as option_item(option_doc, option_ord)
      cross join lateral jsonb_array_elements(
        case
          when jsonb_typeof(option_doc -> 'values') = 'array' then option_doc -> 'values'
          else '[]'::jsonb
        end
      ) with ordinality as value_item(value_doc, value_ord)
    union all
    select nullif(btrim(variant_doc->>'client_id'), ''),
           format('variants[%s].client_id', variant_ord - 1)
      from jsonb_array_elements(v_variants) with ordinality as variant_item(variant_doc, variant_ord)
    union all
    select nullif(btrim(stock_doc->>'client_id'), ''),
           format('stock_units[%s].client_id', stock_ord - 1)
      from jsonb_array_elements(v_stock_units) with ordinality as stock_item(stock_doc, stock_ord)
    union all
    select nullif(btrim(product_doc->>'client_id'), ''),
           format('products[%s].client_id', product_ord - 1)
      from jsonb_array_elements(v_products) with ordinality as product_item(product_doc, product_ord)
    union all
    select nullif(btrim(option_doc->>'client_id'), ''),
           format('products[%s].options[%s].client_id', product_ord - 1, option_ord - 1)
      from jsonb_array_elements(v_products) with ordinality as product_item(product_doc, product_ord)
      cross join lateral jsonb_array_elements(
        case
          when jsonb_typeof(product_doc -> 'options') = 'array' then product_doc -> 'options'
          else '[]'::jsonb
        end
      ) with ordinality as option_item(option_doc, option_ord)
    union all
    select nullif(btrim(value_doc->>'client_id'), ''),
           format('products[%s].options[%s].values[%s].client_id', product_ord - 1, option_ord - 1, value_ord - 1)
      from jsonb_array_elements(v_products) with ordinality as product_item(product_doc, product_ord)
      cross join lateral jsonb_array_elements(
        case
          when jsonb_typeof(product_doc -> 'options') = 'array' then product_doc -> 'options'
          else '[]'::jsonb
        end
      ) with ordinality as option_item(option_doc, option_ord)
      cross join lateral jsonb_array_elements(
        case
          when jsonb_typeof(option_doc -> 'values') = 'array' then option_doc -> 'values'
          else '[]'::jsonb
        end
      ) with ordinality as value_item(value_doc, value_ord)
    union all
    select nullif(btrim(modifier_doc->>'client_id'), ''),
           format('products[%s].pricing_modifiers[%s].client_id', product_ord - 1, modifier_ord - 1)
      from jsonb_array_elements(v_products) with ordinality as product_item(product_doc, product_ord)
      cross join lateral jsonb_array_elements(
        case
          when jsonb_typeof(product_doc -> 'pricing_modifiers') = 'array' then product_doc -> 'pricing_modifiers'
          else '[]'::jsonb
        end
      ) with ordinality as modifier_item(modifier_doc, modifier_ord)
    union all
    select nullif(btrim(mapping_doc->>'client_id'), ''),
           format('products[%s].catalog_option_mappings[%s].client_id', product_ord - 1, mapping_ord - 1)
      from jsonb_array_elements(v_products) with ordinality as product_item(product_doc, product_ord)
      cross join lateral jsonb_array_elements(
        case
          when jsonb_typeof(product_doc -> 'catalog_option_mappings') = 'array' then product_doc -> 'catalog_option_mappings'
          else '[]'::jsonb
        end
      ) with ordinality as mapping_item(mapping_doc, mapping_ord)
    union all
    select nullif(btrim(material_doc->>'client_id'), ''),
           format('products[%s].product_materials[%s].client_id', product_ord - 1, material_ord - 1)
      from jsonb_array_elements(v_products) with ordinality as product_item(product_doc, product_ord)
      cross join lateral jsonb_array_elements(
        case
          when jsonb_typeof(product_doc -> 'product_materials') = 'array' then product_doc -> 'product_materials'
          else '[]'::jsonb
        end
      ) with ordinality as material_item(material_doc, material_ord)
    union all
    select nullif(btrim(material_doc->>'client_id'), ''),
           format('products[%s].materials[%s].client_id', product_ord - 1, material_ord - 1)
      from jsonb_array_elements(v_products) with ordinality as product_item(product_doc, product_ord)
      cross join lateral jsonb_array_elements(
        case
          when jsonb_typeof(product_doc -> 'materials') = 'array' then product_doc -> 'materials'
          else '[]'::jsonb
        end
      ) with ordinality as material_item(material_doc, material_ord)
    union all
    select nullif(btrim(material_doc->>'client_id'), ''),
           format('product_materials[%s].client_id', material_ord - 1)
      from jsonb_array_elements(v_product_materials) with ordinality as material_item(material_doc, material_ord)
    union all
    select nullif(btrim(bundle_doc->>'client_id'), ''),
           format('products[%s].bundle_items[%s].client_id', product_ord - 1, bundle_ord - 1)
      from jsonb_array_elements(v_products) with ordinality as product_item(product_doc, product_ord)
      cross join lateral jsonb_array_elements(
        case
          when jsonb_typeof(product_doc -> 'bundle_items') = 'array' then product_doc -> 'bundle_items'
          else '[]'::jsonb
        end
      ) with ordinality as bundle_item(bundle_doc, bundle_ord)
  ),
  duplicates as (
    select client_id, jsonb_agg(path order by path) as paths
      from client_ids
     where client_id is not null
     group by client_id
    having count(*) > 1
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'code', 'duplicate_client_id',
    'path', 'client_id',
    'message', 'Client ids must be unique across a catalog setup payload.',
    'client_id', client_id,
    'paths', paths
  )), '[]'::jsonb)
  into v_tmp
  from duplicates;

  if jsonb_array_length(v_tmp) > 0 then
    v_blockers := v_blockers || v_tmp;
  end if;

  with required_catalog_fields as (
    select 'catalog_option_name_required' as code,
           format('catalog_options[%s].name', option_ord - 1) as path,
           'Catalog option name is required.' as message
      from jsonb_array_elements(v_catalog_options) with ordinality as option_item(option_doc, option_ord)
     where nullif(btrim(coalesce(option_doc->>'name', '')), '') is null
    union all
    select 'catalog_option_values_required',
           format('catalog_options[%s].values', option_ord - 1),
           'Catalog options must include at least one value.'
      from jsonb_array_elements(v_catalog_options) with ordinality as option_item(option_doc, option_ord)
     where jsonb_array_length(
       case
         when jsonb_typeof(option_doc -> 'values') = 'array' then option_doc -> 'values'
         else '[]'::jsonb
       end
     ) = 0
    union all
    select 'catalog_option_value_required',
           format('catalog_options[%s].values[%s].label', option_ord - 1, value_ord - 1),
           'Catalog option value label is required.'
      from jsonb_array_elements(v_catalog_options) with ordinality as option_item(option_doc, option_ord)
      cross join lateral jsonb_array_elements(
        case
          when jsonb_typeof(option_doc -> 'values') = 'array' then option_doc -> 'values'
          else '[]'::jsonb
        end
      ) with ordinality as value_item(value_doc, value_ord)
     where nullif(btrim(coalesce(value_doc->>'label', value_doc->>'value', '')), '') is null
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'code', code,
    'path', path,
    'message', message
  )), '[]'::jsonb)
  into v_tmp
  from required_catalog_fields;

  if jsonb_array_length(v_tmp) > 0 then
    v_blockers := v_blockers || v_tmp;
  end if;

  with option_names as (
    select lower(btrim(option_doc->>'name')) as normalized_name,
           jsonb_agg(format('catalog_options[%s].name', option_ord - 1) order by option_ord) as paths
      from jsonb_array_elements(v_catalog_options) with ordinality as option_item(option_doc, option_ord)
     where nullif(btrim(coalesce(option_doc->>'name', '')), '') is not null
     group by lower(btrim(option_doc->>'name'))
    having count(*) > 1
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'code', 'duplicate_catalog_option_name',
    'path', 'catalog_options',
    'message', 'Catalog option names must be unique within the family draft.',
    'paths', paths
  )), '[]'::jsonb)
  into v_tmp
  from option_names;

  if jsonb_array_length(v_tmp) > 0 then
    v_blockers := v_blockers || v_tmp;
  end if;

  with option_values as (
    select option_ord,
           coalesce(nullif(btrim(option_doc->>'client_id'), ''), option_doc->>'id', option_ord::text) as option_key,
           lower(btrim(coalesce(value_doc->>'label', value_doc->>'value', ''))) as normalized_value,
           jsonb_agg(format('catalog_options[%s].values[%s]', option_ord - 1, value_ord - 1) order by value_ord) as paths
      from jsonb_array_elements(v_catalog_options) with ordinality as option_item(option_doc, option_ord)
      cross join lateral jsonb_array_elements(
        case
          when jsonb_typeof(option_doc -> 'values') = 'array' then option_doc -> 'values'
          else '[]'::jsonb
        end
      ) with ordinality as value_item(value_doc, value_ord)
     where nullif(btrim(coalesce(value_doc->>'label', value_doc->>'value', '')), '') is not null
     group by option_ord, option_key, lower(btrim(coalesce(value_doc->>'label', value_doc->>'value', '')))
    having count(*) > 1
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'code', 'duplicate_catalog_option_value',
    'path', 'catalog_options.values',
    'message', 'Catalog option values must be unique within their parent option.',
    'paths', paths
  )), '[]'::jsonb)
  into v_tmp
  from option_values;

  if jsonb_array_length(v_tmp) > 0 then
    v_blockers := v_blockers || v_tmp;
  end if;

  with catalog_value_refs as (
    select nullif(btrim(value_doc->>'client_id'), '') as client_id
      from jsonb_array_elements(v_catalog_options) as option_doc
      cross join lateral jsonb_array_elements(
        case
          when jsonb_typeof(option_doc -> 'values') = 'array' then option_doc -> 'values'
          else '[]'::jsonb
        end
      ) as value_doc
  ),
  variant_refs as (
    select format('variants[%s].option_value_client_ids[%s]', variant_ord - 1, value_ord - 1) as path,
           nullif(btrim(value_ref #>> '{}'), '') as client_id
      from jsonb_array_elements(v_variants) with ordinality as variant_item(variant_doc, variant_ord)
      cross join lateral jsonb_array_elements(
        case
          when jsonb_typeof(variant_doc -> 'option_value_client_ids') = 'array' then variant_doc -> 'option_value_client_ids'
          else '[]'::jsonb
        end
      ) with ordinality as value_item(value_ref, value_ord)
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'code', 'unknown_catalog_option_value_client_id',
    'path', path,
    'message', 'Variant option-value selections must reference catalog option values in the same payload.',
    'client_id', client_id
  )), '[]'::jsonb)
  into v_tmp
  from variant_refs vr
  where vr.client_id is not null
    and not exists (
      select 1
      from catalog_value_refs cvr
      where cvr.client_id = vr.client_id
    );

  if jsonb_array_length(v_tmp) > 0 then
    v_blockers := v_blockers || v_tmp;
  end if;

  with explicit_variant_option_refs as (
    select format('variants[%s].option_value_ids[%s]', variant_ord - 1, value_ord - 1) as path,
           nullif(btrim(value_ref #>> '{}'), '') as option_value_id
      from jsonb_array_elements(v_variants) with ordinality as variant_item(variant_doc, variant_ord)
      cross join lateral jsonb_array_elements(
        case
          when jsonb_typeof(variant_doc -> 'option_value_ids') = 'array' then variant_doc -> 'option_value_ids'
          else '[]'::jsonb
        end
      ) with ordinality as value_item(value_ref, value_ord)
  ),
  invalid_variant_option_refs as (
    select 'invalid_variant_option_value_id' as code,
           path,
           'Variant option value ids must be valid UUIDs.' as message
      from explicit_variant_option_refs
     where option_value_id is null
        or option_value_id !~* v_uuid_pattern
    union all
    select 'variant_option_value_not_found',
           path,
           'Variant option value ids must belong to the current company.'
      from explicit_variant_option_refs
     where option_value_id ~* v_uuid_pattern
       and not exists (
         select 1
           from public.catalog_option_values value_row
           join public.catalog_options option_row on option_row.id = value_row.option_id
           join public.catalog_items item_row on item_row.id = option_row.catalog_item_id
          where value_row.id = option_value_id::uuid
            and item_row.company_id = p_company_id
       )
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'code', code,
    'path', path,
    'message', message
  )), '[]'::jsonb)
  into v_tmp
  from invalid_variant_option_refs;

  if jsonb_array_length(v_tmp) > 0 then
    v_blockers := v_blockers || v_tmp;
  end if;

  with signatures as (
    select jsonb_agg(value_ref #>> '{}' order by value_ref #>> '{}') as signature,
           jsonb_agg(format('variants[%s].option_value_client_ids', variant_ord - 1) order by variant_ord) as paths
      from jsonb_array_elements(v_variants) with ordinality as variant_item(variant_doc, variant_ord)
      cross join lateral jsonb_array_elements(
        case
          when jsonb_typeof(variant_doc -> 'option_value_client_ids') = 'array' then variant_doc -> 'option_value_client_ids'
          else '[]'::jsonb
        end
      ) as value_item(value_ref)
     where lower(coalesce(variant_doc->>'excluded', 'false')) <> 'true'
     group by variant_ord, variant_doc
  ),
  duplicate_signatures as (
    select signature, jsonb_agg(paths) as grouped_paths
      from signatures
     group by signature
    having count(*) > 1
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'code', 'matrix_signature_conflict',
    'path', 'variants.option_value_client_ids',
    'message', 'Variant matrix signature already exists in this draft.',
    'signature', signature,
    'paths', grouped_paths
  )), '[]'::jsonb)
  into v_tmp
  from duplicate_signatures;

  if jsonb_array_length(v_tmp) > 0 then
    v_blockers := v_blockers || v_tmp;
  end if;

  with stock_checks as (
    select stock_doc,
           stock_ord,
           format('stock_units[%s]', stock_ord - 1) as path
      from jsonb_array_elements(v_stock_units) with ordinality as stock_item(stock_doc, stock_ord)
  ),
  invalid_stock as (
    select 'invalid_stock_unit_kind' as code,
           path || '.unit_kind' as path,
           'Stock unit kind is not supported.' as message
      from stock_checks
     where coalesce(nullif(btrim(stock_doc->>'unit_kind'), ''), 'each')
       not in ('roll', 'offcut', 'box', 'each', 'lot', 'pallet', 'length')
    union all
    select 'invalid_stock_unit_status',
           path || '.status',
           'Stock unit status is not supported.'
      from stock_checks
     where coalesce(nullif(btrim(stock_doc->>'status'), ''), 'full')
       not in ('full', 'partial', 'reserved', 'consumed', 'scrapped')
    union all
    select 'stock_unit_variant_required',
           path || '.variant_client_id',
           'Stock units must reference a payload variant or an existing catalog variant id.'
      from stock_checks
     where nullif(btrim(coalesce(stock_doc->>'variant_client_id', '')), '') is null
       and nullif(btrim(coalesce(stock_doc->>'catalog_variant_id', stock_doc->>'variant_id', '')), '') is null
    union all
    select 'negative_stock_quantity',
           path || '.quantity_value',
           'Stock unit quantity must be non-negative.'
      from stock_checks
     where stock_doc ? 'quantity_value'
       and (stock_doc->>'quantity_value') ~ '^-?[0-9]+(\.[0-9]+)?$'
       and (stock_doc->>'quantity_value')::numeric < 0
    union all
    select 'negative_stock_width',
           path || '.width_value',
           'Stock unit width must be non-negative.'
      from stock_checks
     where stock_doc ? 'width_value'
       and (stock_doc->>'width_value') ~ '^-?[0-9]+(\.[0-9]+)?$'
       and (stock_doc->>'width_value')::numeric < 0
    union all
    select 'negative_original_length',
           path || '.original_length_value',
           'Stock unit original length must be non-negative.'
      from stock_checks
     where stock_doc ? 'original_length_value'
       and (stock_doc->>'original_length_value') ~ '^-?[0-9]+(\.[0-9]+)?$'
       and (stock_doc->>'original_length_value')::numeric < 0
    union all
    select 'negative_remaining_length',
           path || '.remaining_length_value',
           'Stock unit remaining length must be non-negative.'
      from stock_checks
     where stock_doc ? 'remaining_length_value'
       and (stock_doc->>'remaining_length_value') ~ '^-?[0-9]+(\.[0-9]+)?$'
       and (stock_doc->>'remaining_length_value')::numeric < 0
    union all
    select 'remaining_length_exceeds_original',
           path || '.remaining_length_value',
           'Stock unit remaining length cannot exceed original length.'
      from stock_checks
     where stock_doc ? 'remaining_length_value'
       and stock_doc ? 'original_length_value'
       and (stock_doc->>'remaining_length_value') ~ '^-?[0-9]+(\.[0-9]+)?$'
       and (stock_doc->>'original_length_value') ~ '^-?[0-9]+(\.[0-9]+)?$'
       and (stock_doc->>'remaining_length_value')::numeric > (stock_doc->>'original_length_value')::numeric
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'code', code,
    'path', path,
    'message', message
  )), '[]'::jsonb)
  into v_tmp
  from invalid_stock;

  if jsonb_array_length(v_tmp) > 0 then
    v_blockers := v_blockers || v_tmp;
  end if;

  with stock_event_checks as (
    select event_doc,
           event_ord,
           format('stock_unit_events[%s]', event_ord - 1) as path
      from jsonb_array_elements(v_stock_unit_events) with ordinality as stock_event_item(event_doc, event_ord)
  ),
  invalid_stock_events as (
    select 'stock_unit_event_type_required' as code,
           path || '.event_type' as path,
           'Stock unit event type is required.' as message
      from stock_event_checks
     where nullif(btrim(coalesce(event_doc->>'event_type', '')), '') is null
    union all
    select 'invalid_stock_unit_event_type',
           path || '.event_type',
           'Stock unit event type is not supported.'
      from stock_event_checks
     where nullif(btrim(coalesce(event_doc->>'event_type', '')), '') is not null
       and nullif(btrim(coalesce(event_doc->>'event_type', '')), '')
           not in ('receive', 'consume', 'scrap', 'offcut_create', 'adjust', 'reserve', 'release', 'restore', 'delete')
    union all
    select 'stock_unit_event_unit_required',
           path || '.stock_unit_client_id',
           'Stock unit events must reference a stock unit client id or server id.'
      from stock_event_checks
     where nullif(btrim(coalesce(event_doc->>'stock_unit_client_id', event_doc->>'catalog_stock_unit_client_id', '')), '') is null
       and nullif(btrim(coalesce(event_doc->>'catalog_stock_unit_id', event_doc->>'stock_unit_id', '')), '') is null
    union all
    select 'invalid_stock_unit_event_from_status',
           path || '.from_status',
           'Stock unit event from_status is not supported.'
      from stock_event_checks
     where nullif(btrim(coalesce(event_doc->>'from_status', '')), '') is not null
       and nullif(btrim(coalesce(event_doc->>'from_status', '')), '')
           not in ('full', 'partial', 'reserved', 'consumed', 'scrapped')
    union all
    select 'invalid_stock_unit_event_to_status',
           path || '.to_status',
           'Stock unit event to_status is not supported.'
      from stock_event_checks
     where nullif(btrim(coalesce(event_doc->>'to_status', '')), '') is not null
       and nullif(btrim(coalesce(event_doc->>'to_status', '')), '')
           not in ('full', 'partial', 'reserved', 'consumed', 'scrapped')
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'code', code,
    'path', path,
    'message', message
  )), '[]'::jsonb)
  into v_tmp
  from invalid_stock_events;

  if jsonb_array_length(v_tmp) > 0 then
    v_blockers := v_blockers || v_tmp;
  end if;

  with product_checks as (
    select product_doc,
           product_ord,
           format('products[%s]', product_ord - 1) as path
      from jsonb_array_elements(v_products) with ordinality as product_item(product_doc, product_ord)
  ),
  invalid_products as (
    select 'product_name_required' as code,
           path || '.name' as path,
           'Product name is required.' as message
      from product_checks
     where nullif(btrim(coalesce(product_doc->>'name', '')), '') is null
    union all
    select 'invalid_product_kind',
           path || '.kind',
           'Product kind must be service, material, or package.'
      from product_checks
     where coalesce(nullif(btrim(product_doc->>'kind'), ''), 'material')
       not in ('service', 'material', 'package')
    union all
    select 'invalid_product_type',
           path || '.type',
           'Product type must be LABOR, MATERIAL, or OTHER.'
      from product_checks
     where upper(coalesce(nullif(btrim(product_doc->>'type'), ''), case when coalesce(product_doc->>'kind', 'material') = 'material' then 'MATERIAL' else 'OTHER' end))
       not in ('LABOR', 'MATERIAL', 'OTHER')
    union all
    select 'invalid_product_pricing_unit',
           path || '.pricing_unit',
           'Product pricing unit must match the live products pricing_unit enum.'
      from product_checks
     where coalesce(nullif(btrim(product_doc->>'pricing_unit'), ''), 'each')
       not in ('each', 'flat_rate', 'linear_foot', 'sqft', 'hour', 'day')
    union all
    select 'invalid_bundle_pricing_mode',
           path || '.bundle_pricing_mode',
           'Bundle pricing mode must be auto or override when supplied.'
      from product_checks
     where nullif(btrim(coalesce(product_doc->>'bundle_pricing_mode', '')), '') is not null
       and product_doc->>'bundle_pricing_mode' not in ('auto', 'override')
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'code', code,
    'path', path,
    'message', message
  )), '[]'::jsonb)
  into v_tmp
  from invalid_products;

  if jsonb_array_length(v_tmp) > 0 then
    v_blockers := v_blockers || v_tmp;
  end if;

  with product_options as (
    select product_ord,
           option_ord,
           option_doc,
           format('products[%s].options[%s]', product_ord - 1, option_ord - 1) as path
      from jsonb_array_elements(v_products) with ordinality as product_item(product_doc, product_ord)
      cross join lateral jsonb_array_elements(
        case
          when jsonb_typeof(product_doc -> 'options') = 'array' then product_doc -> 'options'
          else '[]'::jsonb
        end
      ) with ordinality as option_item(option_doc, option_ord)
  ),
  invalid_product_options as (
    select 'product_option_name_required' as code,
           path || '.name' as path,
           'Product option name is required.' as message
      from product_options
     where nullif(btrim(coalesce(option_doc->>'name', '')), '') is null
    union all
    select 'invalid_product_option_kind',
           path || '.kind' as path,
           'Product option kind must be select, integer, or boolean.'
      from product_options
     where coalesce(nullif(btrim(option_doc->>'kind'), ''), '') not in ('select', 'integer', 'boolean')
    union all
    select 'select_option_values_required',
           path || '.values',
           'Select product options must include at least one value.'
      from product_options
     where option_doc->>'kind' = 'select'
       and jsonb_array_length(
         case
           when jsonb_typeof(option_doc -> 'values') = 'array' then option_doc -> 'values'
           else '[]'::jsonb
         end
       ) = 0
    union all
    select 'product_option_value_required',
           format('%s.values[%s].label', path, value_ord - 1),
           'Product option value label is required.'
      from product_options
      cross join lateral jsonb_array_elements(
        case
          when jsonb_typeof(option_doc -> 'values') = 'array' then option_doc -> 'values'
          else '[]'::jsonb
        end
      ) with ordinality as value_item(value_doc, value_ord)
     where nullif(btrim(coalesce(value_doc->>'label', value_doc->>'value', '')), '') is null
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'code', code,
    'path', path,
    'message', message
  )), '[]'::jsonb)
  into v_tmp
  from invalid_product_options;

  if jsonb_array_length(v_tmp) > 0 then
    v_blockers := v_blockers || v_tmp;
  end if;

  with modifiers as (
    select product_ord,
           modifier_ord,
           modifier_doc,
           format('products[%s].pricing_modifiers[%s]', product_ord - 1, modifier_ord - 1) as path
      from jsonb_array_elements(v_products) with ordinality as product_item(product_doc, product_ord)
      cross join lateral jsonb_array_elements(
        case
          when jsonb_typeof(product_doc -> 'pricing_modifiers') = 'array' then product_doc -> 'pricing_modifiers'
          else '[]'::jsonb
        end
      ) with ordinality as modifier_item(modifier_doc, modifier_ord)
  ),
  invalid_modifiers as (
    select 'modifier_kind_required' as code,
           path || '.modifier_kind' as path,
           'Pricing modifiers must use modifier_kind, not modifier_type.' as message
      from modifiers
     where not (modifier_doc ? 'modifier_kind')
    union all
    select 'modifier_type_not_supported',
           path || '.modifier_type',
           'Pricing modifiers must use the live modifier_kind field.'
      from modifiers
     where modifier_doc ? 'modifier_type'
    union all
    select 'pricing_modifier_option_required',
           path || '.option_client_id',
           'Pricing modifiers must reference a product option.'
      from modifiers
     where nullif(btrim(coalesce(modifier_doc->>'option_client_id', modifier_doc->>'option_id', '')), '') is null
    union all
    select 'invalid_modifier_kind',
           path || '.modifier_kind',
           'Modifier kind must match the live product_pricing_modifiers enum.'
      from modifiers
     where modifier_doc ? 'modifier_kind'
       and modifier_doc->>'modifier_kind' not in (
         'add_per_unit',
         'add_flat',
         'add_per_count',
         'multiply_unit_price'
       )
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'code', code,
    'path', path,
    'message', message
  )), '[]'::jsonb)
  into v_tmp
  from invalid_modifiers;

  if jsonb_array_length(v_tmp) > 0 then
    v_blockers := v_blockers || v_tmp;
  end if;

  with product_option_refs as (
    select product_ord,
           nullif(btrim(product_doc->>'client_id'), '') as product_client_id,
           nullif(btrim(product_doc->>'id'), '') as product_id,
           nullif(btrim(option_doc->>'client_id'), '') as option_client_id,
           nullif(btrim(option_doc->>'id'), '') as option_id
      from jsonb_array_elements(v_products) with ordinality as product_item(product_doc, product_ord)
      cross join lateral jsonb_array_elements(
        case
          when jsonb_typeof(product_doc -> 'options') = 'array' then product_doc -> 'options'
          else '[]'::jsonb
        end
      ) as option_doc
  ),
  product_value_refs as (
    select product_ord,
           nullif(btrim(option_doc->>'client_id'), '') as option_client_id,
           nullif(btrim(option_doc->>'id'), '') as option_id,
           nullif(btrim(value_doc->>'client_id'), '') as value_client_id,
           nullif(btrim(value_doc->>'id'), '') as value_id
      from jsonb_array_elements(v_products) with ordinality as product_item(product_doc, product_ord)
      cross join lateral jsonb_array_elements(
        case
          when jsonb_typeof(product_doc -> 'options') = 'array' then product_doc -> 'options'
          else '[]'::jsonb
        end
      ) as option_doc
      cross join lateral jsonb_array_elements(
        case
          when jsonb_typeof(option_doc -> 'values') = 'array' then option_doc -> 'values'
          else '[]'::jsonb
        end
      ) as value_doc
  ),
  modifier_refs as (
    select product_ord,
           modifier_ord,
           modifier_doc,
           format('products[%s].pricing_modifiers[%s]', product_ord - 1, modifier_ord - 1) as path,
           nullif(btrim(product_doc->>'client_id'), '') as product_client_id,
           nullif(btrim(product_doc->>'id'), '') as product_id,
           nullif(btrim(coalesce(modifier_doc->>'option_client_id', '')), '') as option_client_id,
           nullif(btrim(coalesce(modifier_doc->>'option_id', '')), '') as option_id,
           nullif(btrim(coalesce(modifier_doc->>'option_value_client_id', modifier_doc->>'trigger_value_client_id', '')), '') as value_client_id,
           nullif(btrim(coalesce(modifier_doc->>'trigger_value_id', modifier_doc->>'option_value_id', '')), '') as value_id
      from jsonb_array_elements(v_products) with ordinality as product_item(product_doc, product_ord)
      cross join lateral jsonb_array_elements(
        case
          when jsonb_typeof(product_doc -> 'pricing_modifiers') = 'array' then product_doc -> 'pricing_modifiers'
          else '[]'::jsonb
        end
      ) with ordinality as modifier_item(modifier_doc, modifier_ord)
  ),
  invalid_refs as (
    select 'unknown_pricing_modifier_option' as code,
           path || '.option_client_id' as path,
           'Pricing modifiers must reference a product option in the same product payload.' as message
      from modifier_refs mr
     where mr.option_client_id is not null
       and not exists (
         select 1
         from product_option_refs por
         where por.product_ord = mr.product_ord
           and por.option_client_id = mr.option_client_id
       )
    union all
    select 'unknown_pricing_modifier_value',
           path || '.option_value_client_id',
           'Value-specific pricing modifiers must reference a product option value in the same product payload.'
      from modifier_refs mr
     where mr.value_client_id is not null
       and not exists (
         select 1
         from product_value_refs pvr
         where pvr.product_ord = mr.product_ord
           and pvr.value_client_id = mr.value_client_id
           and (
             mr.option_client_id is null
             or pvr.option_client_id = mr.option_client_id
           )
           and (
             mr.option_id is null
             or mr.option_id !~* v_uuid_pattern
             or (
               pvr.option_id ~* v_uuid_pattern
               and pvr.option_id::uuid = mr.option_id::uuid
             )
           )
       )
    union all
    select 'invalid_pricing_modifier_option_id',
           path || '.option_id',
           'Pricing modifier option ids must be valid UUIDs.'
      from modifier_refs mr
    where mr.option_id is not null
      and mr.option_id !~* v_uuid_pattern
    union all
    select 'pricing_modifier_option_requires_existing_product',
           path || '.option_id',
           'Server pricing modifier option ids are only valid for the existing product being saved; new product/options must use option_client_id.'
      from modifier_refs mr
     where mr.option_id ~* v_uuid_pattern
       and (
         mr.product_id is null
         or mr.product_id !~* v_uuid_pattern
       )
    union all
    select 'pricing_modifier_option_not_found',
           path || '.option_id',
           'Pricing modifier option ids must belong to the same product and company.'
      from modifier_refs mr
     where mr.option_id ~* v_uuid_pattern
       and mr.product_id ~* v_uuid_pattern
       and not exists (
         select 1
           from public.product_options option_row
           join public.products product_row on product_row.id = option_row.product_id
          where option_row.id = mr.option_id::uuid
            and option_row.product_id = mr.product_id::uuid
            and product_row.company_id = p_company_id
       )
    union all
    select 'invalid_pricing_modifier_value_id',
           path || '.trigger_value_id',
           'Pricing modifier value ids must be valid UUIDs.'
      from modifier_refs mr
    where mr.value_id is not null
      and mr.value_id !~* v_uuid_pattern
    union all
    select 'pricing_modifier_value_requires_existing_product',
           path || '.trigger_value_id',
           'Server pricing modifier value ids are only valid for the existing product being saved; new product/options must use option_value_client_id.'
      from modifier_refs mr
     where mr.value_id ~* v_uuid_pattern
       and (
         mr.product_id is null
         or mr.product_id !~* v_uuid_pattern
       )
    union all
    select 'pricing_modifier_value_not_found',
           path || '.trigger_value_id',
           'Pricing modifier value ids must belong to the same product, company, and selected option.'
      from modifier_refs mr
     where mr.value_id ~* v_uuid_pattern
       and mr.product_id ~* v_uuid_pattern
       and not exists (
         select 1
           from public.product_option_values value_row
           join public.product_options option_row on option_row.id = value_row.option_id
           join public.products product_row on product_row.id = option_row.product_id
          where value_row.id = mr.value_id::uuid
            and option_row.product_id = mr.product_id::uuid
            and product_row.company_id = p_company_id
            and (
              mr.option_id is null
              or mr.option_id !~* v_uuid_pattern
              or option_row.id = mr.option_id::uuid
            )
            and (
              mr.option_client_id is null
              or exists (
                select 1
                  from product_option_refs por
                 where por.product_ord = mr.product_ord
                   and por.option_client_id = mr.option_client_id
                   and por.option_id ~* v_uuid_pattern
                   and option_row.id = por.option_id::uuid
              )
            )
       )
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'code', code,
    'path', path,
    'message', message
  )), '[]'::jsonb)
  into v_tmp
  from invalid_refs;

  if jsonb_array_length(v_tmp) > 0 then
    v_blockers := v_blockers || v_tmp;
  end if;

  with product_payloads as (
    select product_doc,
           product_ord,
           nullif(btrim(product_doc->>'client_id'), '') as product_client_id,
           nullif(btrim(product_doc->>'id'), '') as product_id
      from jsonb_array_elements(v_products) with ordinality as product_item(product_doc, product_ord)
  ),
  product_option_refs as (
    select pp.product_ord,
           pp.product_client_id,
           pp.product_id,
           nullif(btrim(option_doc->>'client_id'), '') as option_client_id,
           nullif(btrim(option_doc->>'id'), '') as option_id
      from product_payloads pp
      cross join lateral jsonb_array_elements(
        case
          when jsonb_typeof(pp.product_doc -> 'options') = 'array' then pp.product_doc -> 'options'
          else '[]'::jsonb
        end
      ) as option_doc
  ),
  material_checks as (
    select material_doc,
           format('products[%s].product_materials[%s]', product_ord - 1, material_ord - 1) as path,
           false as requires_product_ref,
           product_ord,
           product_client_id,
           product_id
      from product_payloads
      cross join lateral jsonb_array_elements(
        case
          when jsonb_typeof(product_doc -> 'product_materials') = 'array' then product_doc -> 'product_materials'
          else '[]'::jsonb
        end
      ) with ordinality as material_item(material_doc, material_ord)
    union all
    select material_doc,
           format('products[%s].materials[%s]', product_ord - 1, material_ord - 1),
           false,
           product_ord,
           product_client_id,
           product_id
      from product_payloads
      cross join lateral jsonb_array_elements(
        case
          when jsonb_typeof(product_doc -> 'materials') = 'array' then product_doc -> 'materials'
          else '[]'::jsonb
        end
      ) with ordinality as material_item(material_doc, material_ord)
    union all
    select material_doc,
           format('product_materials[%s]', material_ord - 1),
           true,
           matched_product.product_ord,
           nullif(btrim(coalesce(material_doc->>'product_client_id', '')), ''),
           coalesce(
             nullif(btrim(coalesce(material_doc->>'product_id', '')), ''),
             matched_product.product_id
           )
      from jsonb_array_elements(v_product_materials) with ordinality as material_item(material_doc, material_ord)
      left join product_payloads matched_product
        on matched_product.product_client_id = nullif(btrim(coalesce(material_doc->>'product_client_id', '')), '')
  ),
  invalid_materials as (
    select 'product_material_product_required' as code,
           path || '.product_id' as path,
           'Top-level product materials must reference a product client id or server id.' as message
      from material_checks
     where requires_product_ref
       and nullif(btrim(coalesce(material_doc->>'product_client_id', material_doc->>'product_id', '')), '') is null
    union all
    select 'invalid_product_material_product_id',
           path || '.product_id',
           'Product material product ids must be valid UUIDs.'
      from material_checks
     where nullif(btrim(coalesce(material_doc->>'product_id', '')), '') is not null
       and material_doc->>'product_id' !~* v_uuid_pattern
    union all
    select 'product_material_product_not_found',
           path || '.product_id',
           'Product material product ids must belong to the current company.'
      from material_checks
     where nullif(btrim(coalesce(material_doc->>'product_id', '')), '') ~* v_uuid_pattern
       and not exists (
         select 1
           from public.products product_row
          where product_row.id = (material_doc->>'product_id')::uuid
            and product_row.company_id = p_company_id
       )
    union all
    select 'invalid_product_material_variant_id',
           path || '.catalog_variant_id',
           'Product material variant ids must be valid UUIDs.'
      from material_checks
     where nullif(btrim(coalesce(material_doc->>'catalog_variant_id', material_doc->>'variant_id', '')), '') is not null
       and coalesce(material_doc->>'catalog_variant_id', material_doc->>'variant_id') !~* v_uuid_pattern
    union all
    select 'product_material_variant_not_found',
           path || '.catalog_variant_id',
           'Product material variant ids must belong to the current company.'
      from material_checks
     where nullif(btrim(coalesce(material_doc->>'catalog_variant_id', material_doc->>'variant_id', '')), '') ~* v_uuid_pattern
       and not exists (
         select 1
           from public.catalog_variants variant_row
          where variant_row.id = coalesce(material_doc->>'catalog_variant_id', material_doc->>'variant_id')::uuid
            and variant_row.company_id = p_company_id
       )
    union all
    select 'invalid_product_material_catalog_item_id',
           path || '.catalog_item_id',
           'Product material catalog family ids must be valid UUIDs.'
      from material_checks
     where nullif(btrim(coalesce(material_doc->>'catalog_item_id', '')), '') is not null
       and material_doc->>'catalog_item_id' !~* v_uuid_pattern
    union all
    select 'product_material_catalog_item_not_found',
           path || '.catalog_item_id',
           'Product material catalog family ids must belong to the current company.'
      from material_checks
     where nullif(btrim(coalesce(material_doc->>'catalog_item_id', '')), '') ~* v_uuid_pattern
       and not exists (
         select 1
           from public.catalog_items item_row
          where item_row.id = (material_doc->>'catalog_item_id')::uuid
            and item_row.company_id = p_company_id
       )
    union all
    select 'invalid_product_material_scaled_option_id',
           path || '.scaled_by_option_id',
           'Scaled-by option ids must be valid UUIDs.'
      from material_checks
     where nullif(btrim(coalesce(material_doc->>'scaled_by_option_id', '')), '') is not null
       and material_doc->>'scaled_by_option_id' !~* v_uuid_pattern
    union all
    select 'unknown_product_material_scaled_option',
           path || '.scaled_by_option_client_id',
           'Scaled-by option client ids must reference an option in the same product payload.'
      from material_checks
     where nullif(btrim(coalesce(material_doc->>'scaled_by_option_client_id', '')), '') is not null
       and not exists (
         select 1
           from product_option_refs por
          where por.option_client_id = nullif(btrim(coalesce(material_doc->>'scaled_by_option_client_id', '')), '')
            and (
              por.product_ord = material_checks.product_ord
              or (
                material_checks.product_ord is null
                and material_checks.product_client_id is not null
                and por.product_client_id = material_checks.product_client_id
              )
              or (
                material_checks.product_id is not null
                and material_checks.product_id = por.product_id
              )
            )
       )
    union all
    select 'product_material_scaled_option_requires_existing_product',
           path || '.scaled_by_option_id',
           'Server scaled-by option ids are only valid for the existing product being saved; new product/options must use scaled_by_option_client_id.'
      from material_checks
     where nullif(btrim(coalesce(material_doc->>'scaled_by_option_id', '')), '') ~* v_uuid_pattern
       and (
         material_checks.product_id is null
         or material_checks.product_id !~* v_uuid_pattern
       )
    union all
    select 'product_material_scaled_option_not_found',
           path || '.scaled_by_option_id',
           'Scaled-by option ids must belong to the same product and company.'
      from material_checks
     where nullif(btrim(coalesce(material_doc->>'scaled_by_option_id', '')), '') ~* v_uuid_pattern
       and material_checks.product_id ~* v_uuid_pattern
       and not exists (
         select 1
           from public.product_options option_row
           join public.products product_row on product_row.id = option_row.product_id
          where option_row.id = (material_doc->>'scaled_by_option_id')::uuid
            and option_row.product_id = material_checks.product_id::uuid
            and product_row.company_id = p_company_id
       )
    union all
    select 'product_material_pin_shape_invalid',
           path,
           'Product materials must be pinned to exactly one catalog variant, catalog family, or legacy inventory item.'
      from material_checks
     where (
       case when nullif(btrim(coalesce(material_doc->>'catalog_variant_client_id', material_doc->>'variant_client_id', material_doc->>'catalog_variant_id', material_doc->>'variant_id', '')), '') is not null then 1 else 0 end
       + case when nullif(btrim(coalesce(material_doc->>'catalog_item_client_id', material_doc->>'family_client_id', material_doc->>'catalog_item_id', '')), '') is not null then 1 else 0 end
       + case when nullif(btrim(coalesce(material_doc->>'inventory_item_id', '')), '') is not null then 1 else 0 end
     ) <> 1
    union all
    select 'negative_product_material_quantity',
           path || '.quantity_per_unit',
           'Product material quantity per unit must be non-negative.'
      from material_checks
     where case
       when coalesce(material_doc->>'quantity_per_unit', material_doc->>'quantity', '') ~ '^-?[0-9]+(\.[0-9]+)?$'
         then coalesce(material_doc->>'quantity_per_unit', material_doc->>'quantity')::double precision < 0
       else false
     end
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'code', code,
    'path', path,
    'message', message
  )), '[]'::jsonb)
  into v_tmp
  from invalid_materials;

  if jsonb_array_length(v_tmp) > 0 then
    v_blockers := v_blockers || v_tmp;
  end if;

  with mapping_product_option_refs as (
    select product_ord,
           nullif(btrim(product_doc->>'client_id'), '') as product_client_id,
           nullif(btrim(product_doc->>'id'), '') as product_id,
           nullif(btrim(option_doc->>'client_id'), '') as option_client_id,
           nullif(btrim(option_doc->>'id'), '') as option_id
      from jsonb_array_elements(v_products) with ordinality as product_item(product_doc, product_ord)
      cross join lateral jsonb_array_elements(
        case
          when jsonb_typeof(product_doc -> 'options') = 'array' then product_doc -> 'options'
          else '[]'::jsonb
        end
      ) as option_doc
  ),
  mapping_product_value_refs as (
    select product_ord,
           nullif(btrim(option_doc->>'client_id'), '') as option_client_id,
           nullif(btrim(option_doc->>'id'), '') as option_id,
           nullif(btrim(value_doc->>'client_id'), '') as value_client_id,
           nullif(btrim(value_doc->>'id'), '') as value_id
      from jsonb_array_elements(v_products) with ordinality as product_item(product_doc, product_ord)
      cross join lateral jsonb_array_elements(
        case
          when jsonb_typeof(product_doc -> 'options') = 'array' then product_doc -> 'options'
          else '[]'::jsonb
        end
      ) as option_doc
      cross join lateral jsonb_array_elements(
        case
          when jsonb_typeof(option_doc -> 'values') = 'array' then option_doc -> 'values'
          else '[]'::jsonb
        end
      ) as value_doc
  ),
  mappings as (
    select product_ord,
           mapping_ord,
           mapping_doc,
           format('products[%s].catalog_option_mappings[%s]', product_ord - 1, mapping_ord - 1) as path,
           nullif(btrim(product_doc->>'client_id'), '') as product_client_id,
           nullif(btrim(product_doc->>'id'), '') as product_id
      from jsonb_array_elements(v_products) with ordinality as product_item(product_doc, product_ord)
      cross join lateral jsonb_array_elements(
        case
          when jsonb_typeof(product_doc -> 'catalog_option_mappings') = 'array' then product_doc -> 'catalog_option_mappings'
          else '[]'::jsonb
        end
      ) with ordinality as mapping_item(mapping_doc, mapping_ord)
  ),
  invalid_mappings as (
    select 'invalid_mapping_kind' as code,
           path || '.mapping_kind' as path,
           'Mapping kind must be axis or value.' as message
      from mappings
     where coalesce(nullif(btrim(mapping_doc->>'mapping_kind'), ''), '') not in ('axis', 'value')
    union all
    select 'axis_mapping_shape_invalid',
           path,
           'Axis mappings include catalog and product option refs only.'
      from mappings
     where mapping_doc->>'mapping_kind' = 'axis'
       and (
         nullif(btrim(coalesce(mapping_doc->>'catalog_option_client_id', mapping_doc->>'catalog_option_id', '')), '') is null
         or nullif(btrim(coalesce(mapping_doc->>'product_option_client_id', mapping_doc->>'product_option_id', '')), '') is null
         or nullif(btrim(coalesce(mapping_doc->>'catalog_option_value_client_id', mapping_doc->>'catalog_option_value_id', '')), '') is not null
         or nullif(btrim(coalesce(mapping_doc->>'product_option_value_client_id', mapping_doc->>'product_option_value_id', '')), '') is not null
       )
    union all
    select 'value_mapping_shape_invalid',
           path,
           'Value mappings include catalog option, catalog value, product option, and product value refs.'
      from mappings
     where mapping_doc->>'mapping_kind' = 'value'
       and (
         nullif(btrim(coalesce(mapping_doc->>'catalog_option_client_id', mapping_doc->>'catalog_option_id', '')), '') is null
         or nullif(btrim(coalesce(mapping_doc->>'product_option_client_id', mapping_doc->>'product_option_id', '')), '') is null
         or nullif(btrim(coalesce(mapping_doc->>'catalog_option_value_client_id', mapping_doc->>'catalog_option_value_id', '')), '') is null
         or nullif(btrim(coalesce(mapping_doc->>'product_option_value_client_id', mapping_doc->>'product_option_value_id', '')), '') is null
       )
    union all
    select 'invalid_mapping_catalog_option_id',
           path || '.catalog_option_id',
           'Mapping catalog option ids must be valid UUIDs.'
      from mappings
     where nullif(btrim(coalesce(mapping_doc->>'catalog_option_id', '')), '') is not null
       and mapping_doc->>'catalog_option_id' !~* v_uuid_pattern
    union all
    select 'mapping_catalog_option_not_found',
           path || '.catalog_option_id',
           'Mapping catalog option ids must belong to the current company.'
      from mappings
     where nullif(btrim(coalesce(mapping_doc->>'catalog_option_id', '')), '') ~* v_uuid_pattern
       and not exists (
         select 1
           from public.catalog_options option_row
           join public.catalog_items item_row on item_row.id = option_row.catalog_item_id
          where option_row.id = (mapping_doc->>'catalog_option_id')::uuid
            and item_row.company_id = p_company_id
       )
    union all
    select 'invalid_mapping_product_option_id',
           path || '.product_option_id',
           'Mapping product option ids must be valid UUIDs.'
      from mappings
     where nullif(btrim(coalesce(mapping_doc->>'product_option_id', '')), '') is not null
       and mapping_doc->>'product_option_id' !~* v_uuid_pattern
    union all
    select 'unknown_mapping_product_option',
           path || '.product_option_client_id',
           'Mapping product option client ids must reference an option in the same product payload.'
      from mappings
     where nullif(btrim(coalesce(mapping_doc->>'product_option_client_id', '')), '') is not null
       and not exists (
         select 1
           from mapping_product_option_refs por
          where por.product_ord = mappings.product_ord
            and por.option_client_id = nullif(btrim(coalesce(mapping_doc->>'product_option_client_id', '')), '')
       )
    union all
    select 'mapping_product_option_requires_existing_product',
           path || '.product_option_id',
           'Server mapping product option ids are only valid for the existing product being saved; new product/options must use product_option_client_id.'
      from mappings
     where nullif(btrim(coalesce(mapping_doc->>'product_option_id', '')), '') ~* v_uuid_pattern
       and (
         mappings.product_id is null
         or mappings.product_id !~* v_uuid_pattern
       )
    union all
    select 'mapping_product_option_not_found',
           path || '.product_option_id',
           'Mapping product option ids must belong to the same product and company.'
      from mappings
     where nullif(btrim(coalesce(mapping_doc->>'product_option_id', '')), '') ~* v_uuid_pattern
       and mappings.product_id ~* v_uuid_pattern
       and not exists (
         select 1
           from public.product_options option_row
           join public.products product_row on product_row.id = option_row.product_id
          where option_row.id = (mapping_doc->>'product_option_id')::uuid
            and option_row.product_id = mappings.product_id::uuid
            and product_row.company_id = p_company_id
       )
    union all
    select 'invalid_mapping_catalog_option_value_id',
           path || '.catalog_option_value_id',
           'Mapping catalog option value ids must be valid UUIDs.'
      from mappings
     where nullif(btrim(coalesce(mapping_doc->>'catalog_option_value_id', '')), '') is not null
       and mapping_doc->>'catalog_option_value_id' !~* v_uuid_pattern
    union all
    select 'mapping_catalog_option_value_not_found',
           path || '.catalog_option_value_id',
           'Mapping catalog option values must belong to the referenced catalog option and company.'
      from mappings
     where nullif(btrim(coalesce(mapping_doc->>'catalog_option_value_id', '')), '') ~* v_uuid_pattern
       and not exists (
         select 1
           from public.catalog_option_values value_row
           join public.catalog_options option_row on option_row.id = value_row.option_id
           join public.catalog_items item_row on item_row.id = option_row.catalog_item_id
          where value_row.id = (mapping_doc->>'catalog_option_value_id')::uuid
            and item_row.company_id = p_company_id
            and (
              nullif(btrim(coalesce(mapping_doc->>'catalog_option_id', '')), '') is null
              or nullif(btrim(coalesce(mapping_doc->>'catalog_option_id', '')), '') !~* v_uuid_pattern
              or value_row.option_id = (mapping_doc->>'catalog_option_id')::uuid
            )
       )
    union all
    select 'invalid_mapping_product_option_value_id',
           path || '.product_option_value_id',
           'Mapping product option value ids must be valid UUIDs.'
      from mappings
     where nullif(btrim(coalesce(mapping_doc->>'product_option_value_id', '')), '') is not null
       and mapping_doc->>'product_option_value_id' !~* v_uuid_pattern
    union all
    select 'unknown_mapping_product_option_value',
           path || '.product_option_value_client_id',
           'Mapping product option value client ids must reference a value in the same product payload.'
      from mappings
     where nullif(btrim(coalesce(mapping_doc->>'product_option_value_client_id', '')), '') is not null
       and not exists (
         select 1
           from mapping_product_value_refs pvr
          where pvr.product_ord = mappings.product_ord
            and pvr.value_client_id = nullif(btrim(coalesce(mapping_doc->>'product_option_value_client_id', '')), '')
            and (
              nullif(btrim(coalesce(mapping_doc->>'product_option_client_id', '')), '') is null
              or pvr.option_client_id = nullif(btrim(coalesce(mapping_doc->>'product_option_client_id', '')), '')
            )
            and (
              nullif(btrim(coalesce(mapping_doc->>'product_option_id', '')), '') is null
              or nullif(btrim(coalesce(mapping_doc->>'product_option_id', '')), '') !~* v_uuid_pattern
              or (
                pvr.option_id ~* v_uuid_pattern
                and pvr.option_id::uuid = (mapping_doc->>'product_option_id')::uuid
              )
            )
       )
    union all
    select 'mapping_product_option_value_requires_existing_product',
           path || '.product_option_value_id',
           'Server mapping product option value ids are only valid for the existing product being saved; new product/options must use product_option_value_client_id.'
      from mappings
     where nullif(btrim(coalesce(mapping_doc->>'product_option_value_id', '')), '') ~* v_uuid_pattern
       and (
         mappings.product_id is null
         or mappings.product_id !~* v_uuid_pattern
       )
    union all
    select 'mapping_product_option_value_not_found',
           path || '.product_option_value_id',
           'Mapping product option values must belong to the same product, company, and referenced product option.'
      from mappings
     where nullif(btrim(coalesce(mapping_doc->>'product_option_value_id', '')), '') ~* v_uuid_pattern
       and mappings.product_id ~* v_uuid_pattern
       and not exists (
         select 1
           from public.product_option_values value_row
           join public.product_options option_row on option_row.id = value_row.option_id
           join public.products product_row on product_row.id = option_row.product_id
          where value_row.id = (mapping_doc->>'product_option_value_id')::uuid
            and option_row.product_id = mappings.product_id::uuid
            and product_row.company_id = p_company_id
            and (
              nullif(btrim(coalesce(mapping_doc->>'product_option_id', '')), '') is null
              or nullif(btrim(coalesce(mapping_doc->>'product_option_id', '')), '') !~* v_uuid_pattern
              or value_row.option_id = (mapping_doc->>'product_option_id')::uuid
            )
            and (
              nullif(btrim(coalesce(mapping_doc->>'product_option_client_id', '')), '') is null
              or exists (
                select 1
                  from mapping_product_option_refs por
                 where por.product_ord = mappings.product_ord
                   and por.option_client_id = nullif(btrim(coalesce(mapping_doc->>'product_option_client_id', '')), '')
                   and por.option_id ~* v_uuid_pattern
                   and option_row.id = por.option_id::uuid
              )
            )
       )
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'code', code,
    'path', path,
    'message', message
  )), '[]'::jsonb)
  into v_tmp
  from invalid_mappings;

  if jsonb_array_length(v_tmp) > 0 then
    v_blockers := v_blockers || v_tmp;
  end if;

  with mapping_keys as (
    select mapping_doc->>'mapping_kind' as mapping_kind,
           concat_ws('|',
             coalesce(mapping_doc->>'catalog_option_client_id', mapping_doc->>'catalog_option_id'),
             coalesce(mapping_doc->>'product_option_client_id', mapping_doc->>'product_option_id'),
             coalesce(mapping_doc->>'catalog_option_value_client_id', mapping_doc->>'catalog_option_value_id'),
             coalesce(mapping_doc->>'product_option_value_client_id', mapping_doc->>'product_option_value_id')
           ) as mapping_key,
           jsonb_agg(format('products[%s].catalog_option_mappings[%s]', product_ord - 1, mapping_ord - 1) order by product_ord, mapping_ord) as paths
      from jsonb_array_elements(v_products) with ordinality as product_item(product_doc, product_ord)
      cross join lateral jsonb_array_elements(
        case
          when jsonb_typeof(product_doc -> 'catalog_option_mappings') = 'array' then product_doc -> 'catalog_option_mappings'
          else '[]'::jsonb
        end
      ) with ordinality as mapping_item(mapping_doc, mapping_ord)
     where mapping_doc->>'mapping_kind' in ('axis', 'value')
     group by mapping_doc->>'mapping_kind',
              concat_ws('|',
                coalesce(mapping_doc->>'catalog_option_client_id', mapping_doc->>'catalog_option_id'),
                coalesce(mapping_doc->>'product_option_client_id', mapping_doc->>'product_option_id'),
                coalesce(mapping_doc->>'catalog_option_value_client_id', mapping_doc->>'catalog_option_value_id'),
                coalesce(mapping_doc->>'product_option_value_client_id', mapping_doc->>'product_option_value_id')
              )
    having count(*) > 1
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'code', 'duplicate_catalog_product_option_mapping',
    'path', 'products.catalog_option_mappings',
    'message', 'Catalog/product option mappings must be unique within the active draft graph.',
    'mapping_kind', mapping_kind,
    'paths', paths
  )), '[]'::jsonb)
  into v_tmp
  from mapping_keys;

  if jsonb_array_length(v_tmp) > 0 then
    v_blockers := v_blockers || v_tmp;
  end if;

  with bundle_items as (
    select product_ord,
           bundle_ord,
           product_doc,
           bundle_doc,
           format('products[%s].bundle_items[%s]', product_ord - 1, bundle_ord - 1) as path
      from jsonb_array_elements(v_products) with ordinality as product_item(product_doc, product_ord)
      cross join lateral jsonb_array_elements(
        case
          when jsonb_typeof(product_doc -> 'bundle_items') = 'array' then product_doc -> 'bundle_items'
          else '[]'::jsonb
        end
      ) with ordinality as bundle_item(bundle_doc, bundle_ord)
  ),
  invalid_bundle_items as (
    select 'bundle_child_product_required' as code,
           path || '.child_product_id' as path,
           'Bundle items must reference a child product client id or server id.' as message
      from bundle_items
     where nullif(btrim(coalesce(bundle_doc->>'child_product_client_id', bundle_doc->>'product_client_id', bundle_doc->>'child_product_id', bundle_doc->>'product_id', '')), '') is null
    union all
    select 'invalid_bundle_child_product_id',
           path || '.child_product_id',
           'Bundle child product ids must be valid UUIDs.'
      from bundle_items
     where nullif(btrim(coalesce(bundle_doc->>'child_product_id', bundle_doc->>'product_id', '')), '') is not null
       and coalesce(bundle_doc->>'child_product_id', bundle_doc->>'product_id') !~* v_uuid_pattern
    union all
    select 'bundle_child_product_not_found',
           path || '.child_product_id',
           'Bundle child products must belong to the current company.'
      from bundle_items
     where nullif(btrim(coalesce(bundle_doc->>'child_product_id', bundle_doc->>'product_id', '')), '') ~* v_uuid_pattern
       and not exists (
         select 1
           from public.products product_row
          where product_row.id = coalesce(bundle_doc->>'child_product_id', bundle_doc->>'product_id')::uuid
            and product_row.company_id = p_company_id
       )
    union all
    select 'bundle_self_reference',
           path || '.child_product_id',
           'Bundle items cannot reference the bundle product itself.'
      from bundle_items
     where (
       nullif(btrim(coalesce(bundle_doc->>'child_product_client_id', bundle_doc->>'product_client_id', '')), '') is not null
       and nullif(btrim(coalesce(bundle_doc->>'child_product_client_id', bundle_doc->>'product_client_id', '')), '') = nullif(btrim(coalesce(product_doc->>'client_id', '')), '')
     )
        or (
          nullif(btrim(coalesce(bundle_doc->>'child_product_id', bundle_doc->>'product_id', '')), '') is not null
          and nullif(btrim(coalesce(bundle_doc->>'child_product_id', bundle_doc->>'product_id', '')), '') = nullif(btrim(coalesce(product_doc->>'id', '')), '')
        )
    union all
    select 'invalid_bundle_quantity',
           path || '.quantity',
           'Bundle item quantity must be greater than zero.'
      from bundle_items
     where case
       when coalesce(bundle_doc->>'quantity', '1') ~ '^-?[0-9]+(\.[0-9]+)?$'
         then coalesce(bundle_doc->>'quantity', '1')::numeric <= 0
       else true
     end
    union all
    select 'invalid_bundle_relationship_kind',
           path || '.relationship_kind' as path,
           'Bundle relationship kind must be required or suggested.'
      from bundle_items
     where coalesce(nullif(btrim(bundle_doc->>'relationship_kind'), ''), 'required')
       not in ('required', 'suggested')
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'code', code,
    'path', path,
    'message', message
  )), '[]'::jsonb)
  into v_tmp
  from invalid_bundle_items;

  if jsonb_array_length(v_tmp) > 0 then
    v_blockers := v_blockers || v_tmp;
  end if;

  with suggested_addons as (
    select path
      from (
        select product_ord,
               bundle_ord,
               bundle_doc,
               format('products[%s].bundle_items[%s]', product_ord - 1, bundle_ord - 1) as path
          from jsonb_array_elements(v_products) with ordinality as product_item(product_doc, product_ord)
          cross join lateral jsonb_array_elements(
            case
              when jsonb_typeof(product_doc -> 'bundle_items') = 'array' then product_doc -> 'bundle_items'
              else '[]'::jsonb
            end
          ) with ordinality as bundle_item(bundle_doc, bundle_ord)
      ) b
     where b.bundle_doc->>'relationship_kind' = 'suggested'
       and lower(coalesce(b.bundle_doc->>'has_pricing', 'false')) <> 'true'
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'code', 'suggested_addon_not_priced',
    'path', path,
    'message', 'Suggested add-on has no pricing modifier.'
  )), '[]'::jsonb)
  into v_tmp
  from suggested_addons;

  if jsonb_array_length(v_tmp) > 0 then
    v_warnings := v_warnings || v_tmp;
  end if;

  if v_mode = 'edit' then
    v_candidate_text := nullif(btrim(coalesce(p_payload #>> '{family,id}', p_payload #>> '{family_id}', '')), '');
    v_family_id := null;

    if v_candidate_text is not null then
      if v_candidate_text !~* v_uuid_pattern then
        v_blockers := v_blockers || jsonb_build_array(jsonb_build_object(
          'code', 'invalid_family_id',
          'path', 'family.id',
          'message', 'Edit mode family id must be a valid UUID.'
        ));
      else
        v_family_id := v_candidate_text::uuid;
        if not exists (
          select 1
            from public.catalog_items item_row
           where item_row.id = v_family_id
             and item_row.company_id = p_company_id
        ) then
          v_blockers := v_blockers || jsonb_build_array(jsonb_build_object(
            'code', 'family_not_found',
            'path', 'family.id',
            'message', 'Edit mode family id must belong to the current company.'
          ));
        end if;
      end if;
    end if;

    if v_family_id is null
       and (
         jsonb_array_length(v_catalog_options) > 0
         or jsonb_array_length(v_variants) > 0
         or jsonb_array_length(v_stock_units) > 0
         or case when jsonb_typeof(v_deleted_ids -> 'catalog_options') = 'array' then jsonb_array_length(v_deleted_ids -> 'catalog_options') else 0 end > 0
         or case when jsonb_typeof(v_deleted_ids -> 'catalog_option_values') = 'array' then jsonb_array_length(v_deleted_ids -> 'catalog_option_values') else 0 end > 0
         or case when jsonb_typeof(v_deleted_ids -> 'catalog_variants') = 'array' then jsonb_array_length(v_deleted_ids -> 'catalog_variants') else 0 end > 0
         or case when jsonb_typeof(v_deleted_ids -> 'catalog_variant_option_values') = 'array' then jsonb_array_length(v_deleted_ids -> 'catalog_variant_option_values') else 0 end > 0
         or case when jsonb_typeof(v_deleted_ids -> 'catalog_stock_units') = 'array' then jsonb_array_length(v_deleted_ids -> 'catalog_stock_units') else 0 end > 0
       ) then
      v_blockers := v_blockers || jsonb_build_array(jsonb_build_object(
        'code', 'family_target_required_for_catalog_edit',
        'path', 'family.id',
        'message', 'Editing catalog family, axes, values, variants, joins, or stock units requires a target family id.'
      ));
    end if;

    for v_option_doc in
      select value
        from jsonb_array_elements(v_catalog_options) as option_item(value)
    loop
      v_candidate_text := nullif(btrim(coalesce(v_option_doc->>'id', '')), '');
      if v_candidate_text is not null then
        if v_candidate_text !~* v_uuid_pattern then
          v_blockers := v_blockers || jsonb_build_array(jsonb_build_object(
            'code', 'invalid_catalog_option_id',
            'path', 'catalog_options.id',
            'message', 'Catalog option ids must be valid UUIDs.'
          ));
        elsif not exists (
          select 1
            from public.catalog_options option_row
            join public.catalog_items item_row on item_row.id = option_row.catalog_item_id
           where option_row.id = v_candidate_text::uuid
             and item_row.company_id = p_company_id
             and (v_family_id is null or option_row.catalog_item_id = v_family_id)
        ) then
          v_blockers := v_blockers || jsonb_build_array(jsonb_build_object(
            'code', 'catalog_option_not_found',
            'path', 'catalog_options.id',
            'message', 'Existing catalog options must belong to the edited family and company.'
          ));
        end if;
      end if;

      for v_value_doc in
        select value
          from jsonb_array_elements(
            case
              when jsonb_typeof(v_option_doc -> 'values') = 'array' then v_option_doc -> 'values'
              else '[]'::jsonb
            end
          ) as value_item(value)
      loop
        v_candidate_text := nullif(btrim(coalesce(v_value_doc->>'id', '')), '');
        if v_candidate_text is not null then
          if v_candidate_text !~* v_uuid_pattern then
            v_blockers := v_blockers || jsonb_build_array(jsonb_build_object(
              'code', 'invalid_catalog_option_value_id',
              'path', 'catalog_options.values.id',
              'message', 'Catalog option value ids must be valid UUIDs.'
            ));
          elsif not exists (
            select 1
              from public.catalog_option_values value_row
              join public.catalog_options option_row on option_row.id = value_row.option_id
              join public.catalog_items item_row on item_row.id = option_row.catalog_item_id
             where value_row.id = v_candidate_text::uuid
               and item_row.company_id = p_company_id
               and (v_family_id is null or option_row.catalog_item_id = v_family_id)
          ) then
            v_blockers := v_blockers || jsonb_build_array(jsonb_build_object(
              'code', 'catalog_option_value_not_found',
              'path', 'catalog_options.values.id',
              'message', 'Existing catalog option values must belong to the edited family and company.'
            ));
          end if;
        end if;
      end loop;
    end loop;

    for v_variant_doc in
      select value
        from jsonb_array_elements(v_variants) as variant_item(value)
    loop
      v_candidate_text := nullif(btrim(coalesce(v_variant_doc->>'id', '')), '');
      if v_candidate_text is not null then
        if v_candidate_text !~* v_uuid_pattern then
          v_blockers := v_blockers || jsonb_build_array(jsonb_build_object(
            'code', 'invalid_catalog_variant_id',
            'path', 'variants.id',
            'message', 'Catalog variant ids must be valid UUIDs.'
          ));
        elsif not exists (
          select 1
            from public.catalog_variants variant_row
           where variant_row.id = v_candidate_text::uuid
             and variant_row.company_id = p_company_id
             and (v_family_id is null or variant_row.catalog_item_id = v_family_id)
        ) then
          v_blockers := v_blockers || jsonb_build_array(jsonb_build_object(
            'code', 'catalog_variant_not_found',
            'path', 'variants.id',
            'message', 'Existing catalog variants must belong to the edited family and company.'
          ));
        end if;
      end if;
    end loop;

    for v_stock_doc in
      select value
        from jsonb_array_elements(v_stock_units) as stock_item(value)
    loop
      v_candidate_text := nullif(btrim(coalesce(v_stock_doc->>'id', '')), '');
      if v_candidate_text is not null then
        if v_candidate_text !~* v_uuid_pattern then
          v_blockers := v_blockers || jsonb_build_array(jsonb_build_object(
            'code', 'invalid_catalog_stock_unit_id',
            'path', 'stock_units.id',
            'message', 'Catalog stock unit ids must be valid UUIDs.'
          ));
        elsif not exists (
          select 1
            from public.catalog_stock_units unit_row
            join public.catalog_variants variant_row on variant_row.id = unit_row.catalog_variant_id
           where unit_row.id = v_candidate_text::uuid
             and unit_row.company_id = p_company_id
             and (v_family_id is null or variant_row.catalog_item_id = v_family_id)
        ) then
          v_blockers := v_blockers || jsonb_build_array(jsonb_build_object(
            'code', 'catalog_stock_unit_not_found',
            'path', 'stock_units.id',
            'message', 'Existing catalog stock units must belong to the edited family and company.'
          ));
        end if;
      end if;

      v_ref_text := nullif(btrim(coalesce(v_stock_doc->>'catalog_variant_id', v_stock_doc->>'variant_id', '')), '');
      if v_ref_text is not null then
        if v_ref_text !~* v_uuid_pattern then
          v_blockers := v_blockers || jsonb_build_array(jsonb_build_object(
            'code', 'invalid_stock_unit_variant_id',
            'path', 'stock_units.catalog_variant_id',
            'message', 'Stock unit variant ids must be valid UUIDs.'
          ));
        elsif not exists (
          select 1
            from public.catalog_variants variant_row
           where variant_row.id = v_ref_text::uuid
             and variant_row.company_id = p_company_id
             and (v_family_id is null or variant_row.catalog_item_id = v_family_id)
        ) then
          v_blockers := v_blockers || jsonb_build_array(jsonb_build_object(
            'code', 'stock_unit_variant_not_found',
            'path', 'stock_units.catalog_variant_id',
            'message', 'Stock unit variant ids must belong to the edited company and family.'
          ));
        end if;
      end if;

      v_ref_text := nullif(btrim(coalesce(v_stock_doc->>'related_catalog_stock_unit_id', v_stock_doc->>'source_stock_unit_id', '')), '');
      if v_ref_text is not null then
        if v_ref_text !~* v_uuid_pattern then
          v_blockers := v_blockers || jsonb_build_array(jsonb_build_object(
            'code', 'invalid_related_stock_unit_id',
            'path', 'stock_units.related_catalog_stock_unit_id',
            'message', 'Related stock unit ids must be valid UUIDs.'
          ));
        elsif not exists (
          select 1
            from public.catalog_stock_units related_unit_row
           where related_unit_row.id = v_ref_text::uuid
             and related_unit_row.company_id = p_company_id
        ) then
          v_blockers := v_blockers || jsonb_build_array(jsonb_build_object(
            'code', 'related_stock_unit_not_found',
            'path', 'stock_units.related_catalog_stock_unit_id',
            'message', 'Related stock unit ids must belong to the current company.'
          ));
        end if;
      end if;
    end loop;

    for v_product_doc, v_product_ord in
      select value, ordinality::integer
        from jsonb_array_elements(v_products) with ordinality as product_item(value, ordinality)
    loop
      v_product_id := null;
      v_candidate_text := nullif(btrim(coalesce(v_product_doc->>'id', '')), '');

      if v_candidate_text is not null then
        if v_candidate_text !~* v_uuid_pattern then
          v_blockers := v_blockers || jsonb_build_array(jsonb_build_object(
            'code', 'invalid_product_id',
            'path', format('products[%s].id', v_product_ord - 1),
            'message', 'Product ids must be valid UUIDs.',
            'product_id', v_candidate_text
          ));
        elsif exists (
          select 1
            from public.products product_row
           where product_row.id = v_candidate_text::uuid
             and product_row.company_id <> p_company_id
        ) then
          v_blockers := v_blockers || jsonb_build_array(jsonb_build_object(
            'code', 'product_company_mismatch',
            'path', format('products[%s].id', v_product_ord - 1),
            'message', 'Existing products must belong to the current company.',
            'product_id', v_candidate_text
          ));
        elsif not exists (
          select 1
            from public.products product_row
           where product_row.id = v_candidate_text::uuid
             and product_row.company_id = p_company_id
        ) then
          v_blockers := v_blockers || jsonb_build_array(jsonb_build_object(
            'code', 'product_not_found',
            'path', format('products[%s].id', v_product_ord - 1),
            'message', 'Existing products must belong to the current company.',
            'product_id', v_candidate_text
          ));
        else
          v_product_id := v_candidate_text::uuid;
        end if;
      end if;

      v_ref_text := nullif(btrim(coalesce(v_product_doc->>'linked_catalog_item_id', v_product_doc->>'catalog_item_id', '')), '');
      if v_ref_text is not null then
        if v_ref_text !~* v_uuid_pattern then
          v_blockers := v_blockers || jsonb_build_array(jsonb_build_object(
            'code', 'invalid_product_catalog_item_id',
            'path', 'products.linked_catalog_item_id',
            'message', 'Linked catalog family ids must be valid UUIDs.'
          ));
        elsif not exists (
          select 1
            from public.catalog_items item_row
           where item_row.id = v_ref_text::uuid
             and item_row.company_id = p_company_id
        ) then
          v_blockers := v_blockers || jsonb_build_array(jsonb_build_object(
            'code', 'product_catalog_item_not_found',
            'path', 'products.linked_catalog_item_id',
            'message', 'Linked catalog family ids must belong to the current company.'
          ));
        end if;
      end if;

      for v_option_doc in
        select value
          from jsonb_array_elements(
            case
              when jsonb_typeof(v_product_doc -> 'options') = 'array' then v_product_doc -> 'options'
              else '[]'::jsonb
            end
          ) as option_item(value)
      loop
        v_product_option_id := null;
        v_candidate_text := nullif(btrim(coalesce(v_option_doc->>'id', '')), '');
        if v_candidate_text is not null then
          if v_candidate_text !~* v_uuid_pattern then
            v_blockers := v_blockers || jsonb_build_array(jsonb_build_object(
              'code', 'invalid_product_option_id',
              'path', 'products.options.id',
              'message', 'Product option ids must be valid UUIDs.'
            ));
          elsif not exists (
            select 1
              from public.product_options option_row
              join public.products product_row on product_row.id = option_row.product_id
             where option_row.id = v_candidate_text::uuid
               and product_row.company_id = p_company_id
               and (v_product_id is null or option_row.product_id = v_product_id)
          ) then
            v_blockers := v_blockers || jsonb_build_array(jsonb_build_object(
              'code', 'product_option_not_found',
              'path', 'products.options.id',
              'message', 'Existing product options must belong to the edited product and company.'
            ));
          else
            v_product_option_id := v_candidate_text::uuid;
          end if;
        end if;

        for v_value_doc in
          select value
            from jsonb_array_elements(
              case
                when jsonb_typeof(v_option_doc -> 'values') = 'array' then v_option_doc -> 'values'
                else '[]'::jsonb
              end
            ) as value_item(value)
        loop
          v_candidate_text := nullif(btrim(coalesce(v_value_doc->>'id', '')), '');
          if v_candidate_text is not null then
            if v_candidate_text !~* v_uuid_pattern then
              v_blockers := v_blockers || jsonb_build_array(jsonb_build_object(
                'code', 'invalid_product_option_value_id',
                'path', 'products.options.values.id',
                'message', 'Product option value ids must be valid UUIDs.'
              ));
            elsif not exists (
              select 1
                from public.product_option_values value_row
                join public.product_options option_row on option_row.id = value_row.option_id
                join public.products product_row on product_row.id = option_row.product_id
               where value_row.id = v_candidate_text::uuid
                 and product_row.company_id = p_company_id
                 and (v_product_option_id is null or value_row.option_id = v_product_option_id)
                 and (v_product_id is null or option_row.product_id = v_product_id)
            ) then
              v_blockers := v_blockers || jsonb_build_array(jsonb_build_object(
                'code', 'product_option_value_not_found',
                'path', 'products.options.values.id',
                'message', 'Existing product option values must belong to the edited product option and company.'
              ));
            end if;
          end if;
        end loop;
      end loop;

      for v_modifier_doc in
        select value
          from jsonb_array_elements(
            case
              when jsonb_typeof(v_product_doc -> 'pricing_modifiers') = 'array' then v_product_doc -> 'pricing_modifiers'
              else '[]'::jsonb
            end
          ) as modifier_item(value)
      loop
        v_candidate_text := nullif(btrim(coalesce(v_modifier_doc->>'id', '')), '');
        if v_candidate_text is not null then
          if v_candidate_text !~* v_uuid_pattern then
            v_blockers := v_blockers || jsonb_build_array(jsonb_build_object(
              'code', 'invalid_product_pricing_modifier_id',
              'path', 'products.pricing_modifiers.id',
              'message', 'Product pricing modifier ids must be valid UUIDs.'
            ));
          elsif not exists (
            select 1
              from public.product_pricing_modifiers modifier_row
              join public.products product_row on product_row.id = modifier_row.product_id
             where modifier_row.id = v_candidate_text::uuid
               and product_row.company_id = p_company_id
               and (v_product_id is null or modifier_row.product_id = v_product_id)
          ) then
            v_blockers := v_blockers || jsonb_build_array(jsonb_build_object(
              'code', 'product_pricing_modifier_not_found',
              'path', 'products.pricing_modifiers.id',
              'message', 'Existing product pricing modifiers must belong to the edited product and company.'
            ));
          end if;
        end if;

        v_ref_text := nullif(btrim(coalesce(v_modifier_doc->>'option_id', '')), '');
        if v_ref_text is not null then
          if v_ref_text !~* v_uuid_pattern then
            v_blockers := v_blockers || jsonb_build_array(jsonb_build_object(
              'code', 'invalid_pricing_modifier_option_id',
              'path', 'products.pricing_modifiers.option_id',
              'message', 'Pricing modifier option ids must be valid UUIDs.'
            ));
          elsif not exists (
            select 1
              from public.product_options option_row
              join public.products product_row on product_row.id = option_row.product_id
             where option_row.id = v_ref_text::uuid
               and product_row.company_id = p_company_id
               and (v_product_id is null or option_row.product_id = v_product_id)
          ) then
            v_blockers := v_blockers || jsonb_build_array(jsonb_build_object(
              'code', 'pricing_modifier_option_not_found',
              'path', 'products.pricing_modifiers.option_id',
              'message', 'Pricing modifier option ids must belong to the edited product and company.'
            ));
          end if;
        end if;

        v_ref_text := nullif(btrim(coalesce(v_modifier_doc->>'trigger_value_id', v_modifier_doc->>'option_value_id', '')), '');
        if v_ref_text is not null then
          if v_ref_text !~* v_uuid_pattern then
            v_blockers := v_blockers || jsonb_build_array(jsonb_build_object(
              'code', 'invalid_pricing_modifier_value_id',
              'path', 'products.pricing_modifiers.trigger_value_id',
              'message', 'Pricing modifier value ids must be valid UUIDs.'
            ));
          elsif not exists (
            select 1
              from public.product_option_values value_row
              join public.product_options option_row on option_row.id = value_row.option_id
              join public.products product_row on product_row.id = option_row.product_id
             where value_row.id = v_ref_text::uuid
               and product_row.company_id = p_company_id
               and (v_product_id is null or option_row.product_id = v_product_id)
               and case
                 when nullif(btrim(coalesce(v_modifier_doc->>'option_id', '')), '') is null then true
                 when nullif(btrim(coalesce(v_modifier_doc->>'option_id', '')), '') ~* v_uuid_pattern then option_row.id = (v_modifier_doc->>'option_id')::uuid
                 else true
               end
          ) then
            v_blockers := v_blockers || jsonb_build_array(jsonb_build_object(
              'code', 'pricing_modifier_value_not_found',
              'path', 'products.pricing_modifiers.trigger_value_id',
              'message', 'Pricing modifier value ids must belong to the selected product option and company.'
            ));
          end if;
        end if;
      end loop;

      for v_material_doc in
        select material_value
          from (
            select value as material_value
              from jsonb_array_elements(
                case
                  when jsonb_typeof(v_product_doc -> 'product_materials') = 'array' then v_product_doc -> 'product_materials'
                  else '[]'::jsonb
                end
              ) as material_item(value)
            union all
            select value as material_value
              from jsonb_array_elements(
                case
                  when jsonb_typeof(v_product_doc -> 'materials') = 'array' then v_product_doc -> 'materials'
                  else '[]'::jsonb
                end
              ) as material_item(value)
          ) material_items
      loop
        v_candidate_text := nullif(btrim(coalesce(v_material_doc->>'id', '')), '');
        if v_candidate_text is not null then
          if v_candidate_text !~* v_uuid_pattern then
            v_blockers := v_blockers || jsonb_build_array(jsonb_build_object(
              'code', 'invalid_product_material_id',
              'path', 'products.product_materials.id',
              'message', 'Product material ids must be valid UUIDs.'
            ));
          elsif not exists (
            select 1
              from public.product_materials material_row
              join public.products product_row on product_row.id = material_row.product_id
             where material_row.id = v_candidate_text::uuid
               and product_row.company_id = p_company_id
               and (v_product_id is null or material_row.product_id = v_product_id)
          ) then
            v_blockers := v_blockers || jsonb_build_array(jsonb_build_object(
              'code', 'product_material_not_found',
              'path', 'products.product_materials.id',
              'message', 'Existing product materials must belong to the edited product and company.'
            ));
          end if;
        end if;

        if (
          case when nullif(btrim(coalesce(v_material_doc->>'catalog_variant_client_id', v_material_doc->>'variant_client_id', v_material_doc->>'catalog_variant_id', v_material_doc->>'variant_id', '')), '') is not null then 1 else 0 end
          + case when nullif(btrim(coalesce(v_material_doc->>'catalog_item_client_id', v_material_doc->>'family_client_id', v_material_doc->>'catalog_item_id', '')), '') is not null then 1 else 0 end
          + case when nullif(btrim(coalesce(v_material_doc->>'inventory_item_id', '')), '') is not null then 1 else 0 end
        ) <> 1 then
          v_blockers := v_blockers || jsonb_build_array(jsonb_build_object(
            'code', 'product_material_pin_shape_invalid',
            'path', 'products.product_materials',
            'message', 'Product materials must be pinned to exactly one catalog variant, catalog family, or legacy inventory item.'
          ));
        end if;

        v_ref_text := nullif(btrim(coalesce(v_material_doc->>'catalog_variant_id', v_material_doc->>'variant_id', '')), '');
        if v_ref_text is not null then
          if v_ref_text !~* v_uuid_pattern then
            v_blockers := v_blockers || jsonb_build_array(jsonb_build_object(
              'code', 'invalid_product_material_variant_id',
              'path', 'products.product_materials.catalog_variant_id',
              'message', 'Product material variant ids must be valid UUIDs.'
            ));
          elsif not exists (
            select 1
              from public.catalog_variants variant_row
             where variant_row.id = v_ref_text::uuid
               and variant_row.company_id = p_company_id
          ) then
            v_blockers := v_blockers || jsonb_build_array(jsonb_build_object(
              'code', 'product_material_variant_not_found',
              'path', 'products.product_materials.catalog_variant_id',
              'message', 'Product material variant ids must belong to the current company.'
            ));
          end if;
        end if;

        v_ref_text := nullif(btrim(coalesce(v_material_doc->>'catalog_item_id', '')), '');
        if v_ref_text is not null then
          if v_ref_text !~* v_uuid_pattern then
            v_blockers := v_blockers || jsonb_build_array(jsonb_build_object(
              'code', 'invalid_product_material_catalog_item_id',
              'path', 'products.product_materials.catalog_item_id',
              'message', 'Product material catalog family ids must be valid UUIDs.'
            ));
          elsif not exists (
            select 1
              from public.catalog_items item_row
             where item_row.id = v_ref_text::uuid
               and item_row.company_id = p_company_id
          ) then
            v_blockers := v_blockers || jsonb_build_array(jsonb_build_object(
              'code', 'product_material_catalog_item_not_found',
              'path', 'products.product_materials.catalog_item_id',
              'message', 'Product material catalog family ids must belong to the current company.'
            ));
          end if;
        end if;

        v_ref_text := nullif(btrim(coalesce(v_material_doc->>'scaled_by_option_id', '')), '');
        if v_ref_text is not null then
          if v_ref_text !~* v_uuid_pattern then
            v_blockers := v_blockers || jsonb_build_array(jsonb_build_object(
              'code', 'invalid_product_material_scaled_option_id',
              'path', 'products.product_materials.scaled_by_option_id',
              'message', 'Scaled-by option ids must be valid UUIDs.'
            ));
          elsif not exists (
            select 1
              from public.product_options option_row
              join public.products product_row on product_row.id = option_row.product_id
             where option_row.id = v_ref_text::uuid
               and product_row.company_id = p_company_id
               and (v_product_id is null or option_row.product_id = v_product_id)
          ) then
            v_blockers := v_blockers || jsonb_build_array(jsonb_build_object(
              'code', 'product_material_scaled_option_not_found',
              'path', 'products.product_materials.scaled_by_option_id',
              'message', 'Scaled-by option ids must belong to the edited product and company.'
            ));
          end if;
        end if;
      end loop;

      for v_mapping_doc in
        select value
          from jsonb_array_elements(
            case
              when jsonb_typeof(v_product_doc -> 'catalog_option_mappings') = 'array' then v_product_doc -> 'catalog_option_mappings'
              else '[]'::jsonb
            end
          ) as mapping_item(value)
      loop
        v_candidate_text := nullif(btrim(coalesce(v_mapping_doc->>'id', '')), '');
        if v_candidate_text is not null then
          if v_candidate_text !~* v_uuid_pattern then
            v_blockers := v_blockers || jsonb_build_array(jsonb_build_object(
              'code', 'invalid_catalog_product_option_mapping_id',
              'path', 'products.catalog_option_mappings.id',
              'message', 'Catalog/product option mapping ids must be valid UUIDs.'
            ));
          elsif not exists (
            select 1
              from public.catalog_product_option_mappings mapping_row
             where mapping_row.id = v_candidate_text::uuid
               and mapping_row.company_id = p_company_id
               and (v_product_id is null or mapping_row.product_id = v_product_id)
          ) then
            v_blockers := v_blockers || jsonb_build_array(jsonb_build_object(
              'code', 'catalog_product_option_mapping_not_found',
              'path', 'products.catalog_option_mappings.id',
              'message', 'Existing catalog/product option mappings must belong to the edited product and company.'
            ));
          end if;
        end if;

        v_ref_text := nullif(btrim(coalesce(v_mapping_doc->>'catalog_option_id', '')), '');
        if v_ref_text is not null then
          if v_ref_text !~* v_uuid_pattern then
            v_blockers := v_blockers || jsonb_build_array(jsonb_build_object(
              'code', 'invalid_mapping_catalog_option_id',
              'path', 'products.catalog_option_mappings.catalog_option_id',
              'message', 'Mapping catalog option ids must be valid UUIDs.'
            ));
          elsif not exists (
            select 1
              from public.catalog_options option_row
              join public.catalog_items item_row on item_row.id = option_row.catalog_item_id
             where option_row.id = v_ref_text::uuid
               and item_row.company_id = p_company_id
               and (v_family_id is null or option_row.catalog_item_id = v_family_id)
          ) then
            v_blockers := v_blockers || jsonb_build_array(jsonb_build_object(
              'code', 'mapping_catalog_option_not_found',
              'path', 'products.catalog_option_mappings.catalog_option_id',
              'message', 'Mapping catalog option ids must belong to the edited family and company.'
            ));
          end if;
        end if;

        v_ref_text := nullif(btrim(coalesce(v_mapping_doc->>'product_option_id', '')), '');
        if v_ref_text is not null then
          if v_ref_text !~* v_uuid_pattern then
            v_blockers := v_blockers || jsonb_build_array(jsonb_build_object(
              'code', 'invalid_mapping_product_option_id',
              'path', 'products.catalog_option_mappings.product_option_id',
              'message', 'Mapping product option ids must be valid UUIDs.'
            ));
          elsif not exists (
            select 1
              from public.product_options option_row
              join public.products product_row on product_row.id = option_row.product_id
             where option_row.id = v_ref_text::uuid
               and product_row.company_id = p_company_id
               and (v_product_id is null or option_row.product_id = v_product_id)
          ) then
            v_blockers := v_blockers || jsonb_build_array(jsonb_build_object(
              'code', 'mapping_product_option_not_found',
              'path', 'products.catalog_option_mappings.product_option_id',
              'message', 'Mapping product option ids must belong to the edited product and company.'
            ));
          end if;
        end if;

        v_ref_text := nullif(btrim(coalesce(v_mapping_doc->>'catalog_option_value_id', '')), '');
        if v_ref_text is not null then
          if v_ref_text !~* v_uuid_pattern then
            v_blockers := v_blockers || jsonb_build_array(jsonb_build_object(
              'code', 'invalid_mapping_catalog_option_value_id',
              'path', 'products.catalog_option_mappings.catalog_option_value_id',
              'message', 'Mapping catalog option value ids must be valid UUIDs.'
            ));
          elsif not exists (
            select 1
              from public.catalog_option_values value_row
              join public.catalog_options option_row on option_row.id = value_row.option_id
              join public.catalog_items item_row on item_row.id = option_row.catalog_item_id
             where value_row.id = v_ref_text::uuid
               and item_row.company_id = p_company_id
               and case
                 when nullif(btrim(coalesce(v_mapping_doc->>'catalog_option_id', '')), '') is null then true
                 when nullif(btrim(coalesce(v_mapping_doc->>'catalog_option_id', '')), '') ~* v_uuid_pattern then value_row.option_id = (v_mapping_doc->>'catalog_option_id')::uuid
                 else true
               end
          ) then
            v_blockers := v_blockers || jsonb_build_array(jsonb_build_object(
              'code', 'mapping_catalog_option_value_not_found',
              'path', 'products.catalog_option_mappings.catalog_option_value_id',
              'message', 'Mapping catalog option values must belong to the referenced catalog option and company.'
            ));
          end if;
        end if;

        v_ref_text := nullif(btrim(coalesce(v_mapping_doc->>'product_option_value_id', '')), '');
        if v_ref_text is not null then
          if v_ref_text !~* v_uuid_pattern then
            v_blockers := v_blockers || jsonb_build_array(jsonb_build_object(
              'code', 'invalid_mapping_product_option_value_id',
              'path', 'products.catalog_option_mappings.product_option_value_id',
              'message', 'Mapping product option value ids must be valid UUIDs.'
            ));
          elsif not exists (
            select 1
              from public.product_option_values value_row
              join public.product_options option_row on option_row.id = value_row.option_id
              join public.products product_row on product_row.id = option_row.product_id
             where value_row.id = v_ref_text::uuid
               and product_row.company_id = p_company_id
               and (v_product_id is null or option_row.product_id = v_product_id)
               and case
                 when nullif(btrim(coalesce(v_mapping_doc->>'product_option_id', '')), '') is null then true
                 when nullif(btrim(coalesce(v_mapping_doc->>'product_option_id', '')), '') ~* v_uuid_pattern then value_row.option_id = (v_mapping_doc->>'product_option_id')::uuid
                 else true
               end
          ) then
            v_blockers := v_blockers || jsonb_build_array(jsonb_build_object(
              'code', 'mapping_product_option_value_not_found',
              'path', 'products.catalog_option_mappings.product_option_value_id',
              'message', 'Mapping product option values must belong to the referenced product option and company.'
            ));
          end if;
        end if;
      end loop;

      for v_bundle_doc in
        select value
          from jsonb_array_elements(
            case
              when jsonb_typeof(v_product_doc -> 'bundle_items') = 'array' then v_product_doc -> 'bundle_items'
              else '[]'::jsonb
            end
          ) as bundle_item(value)
      loop
        v_candidate_text := nullif(btrim(coalesce(v_bundle_doc->>'id', '')), '');
        if v_candidate_text is not null then
          if v_candidate_text !~* v_uuid_pattern then
            v_blockers := v_blockers || jsonb_build_array(jsonb_build_object(
              'code', 'invalid_product_bundle_item_id',
              'path', 'products.bundle_items.id',
              'message', 'Product bundle item ids must be valid UUIDs.'
            ));
          elsif not exists (
            select 1
              from public.product_bundle_items bundle_row
             where bundle_row.id = v_candidate_text::uuid
               and bundle_row.company_id = p_company_id
               and (v_product_id is null or bundle_row.bundle_product_id = v_product_id)
          ) then
            v_blockers := v_blockers || jsonb_build_array(jsonb_build_object(
              'code', 'product_bundle_item_not_found',
              'path', 'products.bundle_items.id',
              'message', 'Existing bundle items must belong to the edited product and company.'
            ));
          end if;
        end if;

        v_ref_text := nullif(btrim(coalesce(v_bundle_doc->>'child_product_id', v_bundle_doc->>'product_id', '')), '');
        if v_product_id is not null and v_ref_text ~* v_uuid_pattern and v_product_id = v_ref_text::uuid then
          v_blockers := v_blockers || jsonb_build_array(jsonb_build_object(
            'code', 'bundle_self_reference',
            'path', 'products.bundle_items.child_product_id',
            'message', 'Bundle items cannot reference the bundle product itself.'
          ));
        elsif v_ref_text is not null then
          if v_ref_text !~* v_uuid_pattern then
            v_blockers := v_blockers || jsonb_build_array(jsonb_build_object(
              'code', 'invalid_bundle_child_product_id',
              'path', 'products.bundle_items.child_product_id',
              'message', 'Bundle child product ids must be valid UUIDs.'
            ));
          elsif not exists (
            select 1
              from public.products product_row
             where product_row.id = v_ref_text::uuid
               and product_row.company_id = p_company_id
          ) then
            v_blockers := v_blockers || jsonb_build_array(jsonb_build_object(
              'code', 'bundle_child_product_not_found',
              'path', 'products.bundle_items.child_product_id',
              'message', 'Bundle child products must belong to the current company.'
            ));
          end if;
        end if;
      end loop;
    end loop;

    for v_material_doc in
      select value
        from jsonb_array_elements(v_product_materials) as material_item(value)
    loop
      v_candidate_text := nullif(btrim(coalesce(v_material_doc->>'id', '')), '');
      if v_candidate_text is not null then
        if v_candidate_text !~* v_uuid_pattern then
          v_blockers := v_blockers || jsonb_build_array(jsonb_build_object(
            'code', 'invalid_product_material_id',
            'path', 'product_materials.id',
            'message', 'Product material ids must be valid UUIDs.'
          ));
        elsif not exists (
          select 1
            from public.product_materials material_row
            join public.products product_row on product_row.id = material_row.product_id
           where material_row.id = v_candidate_text::uuid
             and product_row.company_id = p_company_id
        ) then
          v_blockers := v_blockers || jsonb_build_array(jsonb_build_object(
            'code', 'product_material_not_found',
            'path', 'product_materials.id',
            'message', 'Existing product materials must belong to the current company.'
          ));
        end if;
      end if;

      if (
        case when nullif(btrim(coalesce(v_material_doc->>'catalog_variant_client_id', v_material_doc->>'variant_client_id', v_material_doc->>'catalog_variant_id', v_material_doc->>'variant_id', '')), '') is not null then 1 else 0 end
        + case when nullif(btrim(coalesce(v_material_doc->>'catalog_item_client_id', v_material_doc->>'family_client_id', v_material_doc->>'catalog_item_id', '')), '') is not null then 1 else 0 end
        + case when nullif(btrim(coalesce(v_material_doc->>'inventory_item_id', '')), '') is not null then 1 else 0 end
      ) <> 1 then
        v_blockers := v_blockers || jsonb_build_array(jsonb_build_object(
          'code', 'product_material_pin_shape_invalid',
          'path', 'product_materials',
          'message', 'Product materials must be pinned to exactly one catalog variant, catalog family, or legacy inventory item.'
        ));
      end if;

      v_ref_text := nullif(btrim(coalesce(v_material_doc->>'product_id', '')), '');
      if v_ref_text is not null then
        if v_ref_text !~* v_uuid_pattern then
          v_blockers := v_blockers || jsonb_build_array(jsonb_build_object(
            'code', 'invalid_product_material_product_id',
            'path', 'product_materials.product_id',
            'message', 'Product material product ids must be valid UUIDs.'
          ));
        elsif not exists (
          select 1
            from public.products product_row
           where product_row.id = v_ref_text::uuid
             and product_row.company_id = p_company_id
        ) then
          v_blockers := v_blockers || jsonb_build_array(jsonb_build_object(
            'code', 'product_material_product_not_found',
            'path', 'product_materials.product_id',
            'message', 'Product material product ids must belong to the current company.'
          ));
        end if;
      end if;

      v_ref_text := nullif(btrim(coalesce(v_material_doc->>'catalog_variant_id', v_material_doc->>'variant_id', '')), '');
      if v_ref_text is not null then
        if v_ref_text !~* v_uuid_pattern then
          v_blockers := v_blockers || jsonb_build_array(jsonb_build_object(
            'code', 'invalid_product_material_variant_id',
            'path', 'product_materials.catalog_variant_id',
            'message', 'Product material variant ids must be valid UUIDs.'
          ));
        elsif not exists (
          select 1
            from public.catalog_variants variant_row
           where variant_row.id = v_ref_text::uuid
             and variant_row.company_id = p_company_id
        ) then
          v_blockers := v_blockers || jsonb_build_array(jsonb_build_object(
            'code', 'product_material_variant_not_found',
            'path', 'product_materials.catalog_variant_id',
            'message', 'Product material variant ids must belong to the current company.'
          ));
        end if;
      end if;

      v_ref_text := nullif(btrim(coalesce(v_material_doc->>'catalog_item_id', '')), '');
      if v_ref_text is not null then
        if v_ref_text !~* v_uuid_pattern then
          v_blockers := v_blockers || jsonb_build_array(jsonb_build_object(
            'code', 'invalid_product_material_catalog_item_id',
            'path', 'product_materials.catalog_item_id',
            'message', 'Product material catalog family ids must be valid UUIDs.'
          ));
        elsif not exists (
          select 1
            from public.catalog_items item_row
           where item_row.id = v_ref_text::uuid
             and item_row.company_id = p_company_id
        ) then
          v_blockers := v_blockers || jsonb_build_array(jsonb_build_object(
            'code', 'product_material_catalog_item_not_found',
            'path', 'product_materials.catalog_item_id',
            'message', 'Product material catalog family ids must belong to the current company.'
          ));
        end if;
      end if;
    end loop;

    foreach v_array_key in array array[
      'catalog_items',
      'catalog_options',
      'catalog_option_values',
      'catalog_variants',
      'catalog_variant_option_values',
      'catalog_stock_units',
      'products',
      'product_options',
      'product_option_values',
      'product_pricing_modifiers',
      'product_materials',
      'product_bundle_items',
      'catalog_product_option_mappings'
    ] loop
      for v_candidate_text in
        select nullif(btrim(deleted_item.value #>> '{}'), '')
          from jsonb_array_elements(
            case
              when jsonb_typeof(v_deleted_ids -> v_array_key) = 'array' then v_deleted_ids -> v_array_key
              else '[]'::jsonb
            end
          ) as deleted_item(value)
      loop
        if v_candidate_text is null then
          v_blockers := v_blockers || jsonb_build_array(jsonb_build_object(
            'code', 'deleted_id_required',
            'path', 'deleted_ids.' || v_array_key,
            'message', 'Deleted id entries must be non-empty UUID strings.'
          ));
        elsif v_candidate_text !~* v_uuid_pattern then
          v_blockers := v_blockers || jsonb_build_array(jsonb_build_object(
            'code', 'invalid_deleted_id',
            'path', 'deleted_ids.' || v_array_key,
            'message', 'Deleted id entries must be valid UUID strings.',
            'id', v_candidate_text
          ));
        else
          case v_array_key
            when 'catalog_items' then
              if not exists (select 1 from public.catalog_items where id = v_candidate_text::uuid and company_id = p_company_id) then
                v_blockers := v_blockers || jsonb_build_array(jsonb_build_object('code', 'deleted_catalog_item_not_found', 'path', 'deleted_ids.catalog_items', 'message', 'Deleted catalog families must belong to the current company.', 'id', v_candidate_text));
              elsif exists (select 1 from public.catalog_stock_units unit_row join public.catalog_variants variant_row on variant_row.id = unit_row.catalog_variant_id where variant_row.catalog_item_id = v_candidate_text::uuid and unit_row.company_id = p_company_id and unit_row.deleted_at is null and unit_row.status in ('consumed', 'scrapped')) then
                v_blockers := v_blockers || jsonb_build_array(jsonb_build_object('code', 'stock_history_delete_blocked', 'path', 'deleted_ids.catalog_items', 'message', 'Catalog families with consumed or scrapped stock units cannot be deleted by setup edit.', 'id', v_candidate_text));
              elsif exists (select 1 from public.product_materials material_row join public.products product_row on product_row.id = material_row.product_id where material_row.catalog_item_id = v_candidate_text::uuid and product_row.company_id = p_company_id and material_row.deleted_at is null and not exists (select 1 from jsonb_array_elements(case when jsonb_typeof(v_deleted_ids -> 'product_materials') = 'array' then v_deleted_ids -> 'product_materials' else '[]'::jsonb end) as deleted_material(value) where deleted_material.value #>> '{}' = material_row.id::text)) then
                v_blockers := v_blockers || jsonb_build_array(jsonb_build_object('code', 'product_material_dependency_delete_blocked', 'path', 'deleted_ids.catalog_items', 'message', 'Catalog families referenced by active product materials cannot be deleted by setup edit.', 'id', v_candidate_text));
              end if;
            when 'catalog_options' then
              if not exists (select 1 from public.catalog_options option_row join public.catalog_items item_row on item_row.id = option_row.catalog_item_id where option_row.id = v_candidate_text::uuid and item_row.company_id = p_company_id) then
                v_blockers := v_blockers || jsonb_build_array(jsonb_build_object('code', 'deleted_catalog_option_not_found', 'path', 'deleted_ids.catalog_options', 'message', 'Deleted catalog options must belong to the current company.', 'id', v_candidate_text));
              end if;
            when 'catalog_option_values' then
              if not exists (select 1 from public.catalog_option_values value_row join public.catalog_options option_row on option_row.id = value_row.option_id join public.catalog_items item_row on item_row.id = option_row.catalog_item_id where value_row.id = v_candidate_text::uuid and item_row.company_id = p_company_id) then
                v_blockers := v_blockers || jsonb_build_array(jsonb_build_object('code', 'deleted_catalog_option_value_not_found', 'path', 'deleted_ids.catalog_option_values', 'message', 'Deleted catalog option values must belong to the current company.', 'id', v_candidate_text));
              end if;
            when 'catalog_variants' then
              if not exists (select 1 from public.catalog_variants where id = v_candidate_text::uuid and company_id = p_company_id) then
                v_blockers := v_blockers || jsonb_build_array(jsonb_build_object('code', 'deleted_catalog_variant_not_found', 'path', 'deleted_ids.catalog_variants', 'message', 'Deleted catalog variants must belong to the current company.', 'id', v_candidate_text));
              elsif exists (select 1 from public.catalog_stock_units unit_row where unit_row.catalog_variant_id = v_candidate_text::uuid and unit_row.company_id = p_company_id and unit_row.deleted_at is null and unit_row.status in ('consumed', 'scrapped')) then
                v_blockers := v_blockers || jsonb_build_array(jsonb_build_object('code', 'stock_history_delete_blocked', 'path', 'deleted_ids.catalog_variants', 'message', 'Catalog variants with consumed or scrapped stock units cannot be deleted by setup edit.', 'id', v_candidate_text));
              elsif exists (select 1 from public.catalog_stock_unit_events event_row where event_row.catalog_variant_id = v_candidate_text::uuid and event_row.company_id = p_company_id) then
                v_blockers := v_blockers || jsonb_build_array(jsonb_build_object('code', 'stock_unit_event_history_delete_blocked', 'path', 'deleted_ids.catalog_variants', 'message', 'Catalog variants with stock-unit event history cannot be deleted by setup edit.', 'id', v_candidate_text));
              elsif exists (select 1 from public.product_materials material_row join public.products product_row on product_row.id = material_row.product_id where material_row.catalog_variant_id = v_candidate_text::uuid and product_row.company_id = p_company_id and material_row.deleted_at is null and not exists (select 1 from jsonb_array_elements(case when jsonb_typeof(v_deleted_ids -> 'product_materials') = 'array' then v_deleted_ids -> 'product_materials' else '[]'::jsonb end) as deleted_material(value) where deleted_material.value #>> '{}' = material_row.id::text)) then
                v_blockers := v_blockers || jsonb_build_array(jsonb_build_object('code', 'product_material_dependency_delete_blocked', 'path', 'deleted_ids.catalog_variants', 'message', 'Catalog variants referenced by active product materials cannot be deleted by setup edit.', 'id', v_candidate_text));
              end if;
            when 'catalog_variant_option_values' then
              if not exists (select 1 from public.catalog_variant_option_values join public.catalog_variants variant_row on variant_row.id = catalog_variant_option_values.variant_id where catalog_variant_option_values.id = v_candidate_text::uuid and variant_row.company_id = p_company_id) then
                v_blockers := v_blockers || jsonb_build_array(jsonb_build_object('code', 'deleted_catalog_variant_option_value_not_found', 'path', 'deleted_ids.catalog_variant_option_values', 'message', 'Deleted catalog variant option joins must belong to the current company.', 'id', v_candidate_text));
              end if;
            when 'catalog_stock_units' then
              if not exists (select 1 from public.catalog_stock_units where id = v_candidate_text::uuid and company_id = p_company_id) then
                v_blockers := v_blockers || jsonb_build_array(jsonb_build_object('code', 'deleted_catalog_stock_unit_not_found', 'path', 'deleted_ids.catalog_stock_units', 'message', 'Deleted catalog stock units must belong to the current company.', 'id', v_candidate_text));
              end if;
            when 'products' then
              if not exists (select 1 from public.products where id = v_candidate_text::uuid and company_id = p_company_id) then
                v_blockers := v_blockers || jsonb_build_array(jsonb_build_object('code', 'deleted_product_not_found', 'path', 'deleted_ids.products', 'message', 'Deleted products must belong to the current company.', 'id', v_candidate_text));
              elsif exists (select 1 from public.product_bundle_items bundle_row where bundle_row.company_id = p_company_id and bundle_row.deleted_at is null and bundle_row.child_product_id = v_candidate_text::uuid and not exists (select 1 from jsonb_array_elements(case when jsonb_typeof(v_deleted_ids -> 'product_bundle_items') = 'array' then v_deleted_ids -> 'product_bundle_items' else '[]'::jsonb end) as deleted_bundle(value) where deleted_bundle.value #>> '{}' = bundle_row.id::text)) then
                v_blockers := v_blockers || jsonb_build_array(jsonb_build_object('code', 'bundle_dependency_delete_blocked', 'path', 'deleted_ids.products', 'message', 'Products used as active bundle children cannot be deleted by setup edit.', 'id', v_candidate_text));
              elsif exists (select 1 from public.product_materials material_row join public.products product_row on product_row.id = material_row.product_id where material_row.product_id = v_candidate_text::uuid and product_row.company_id = p_company_id and material_row.deleted_at is null and not exists (select 1 from jsonb_array_elements(case when jsonb_typeof(v_deleted_ids -> 'product_materials') = 'array' then v_deleted_ids -> 'product_materials' else '[]'::jsonb end) as deleted_material(value) where deleted_material.value #>> '{}' = material_row.id::text)) then
                v_blockers := v_blockers || jsonb_build_array(jsonb_build_object('code', 'product_material_dependency_delete_blocked', 'path', 'deleted_ids.products', 'message', 'Products with active material rows cannot be deleted by setup edit unless materials are explicitly deleted first.', 'id', v_candidate_text));
              end if;
            when 'product_options' then
              if not exists (select 1 from public.product_options option_row join public.products product_row on product_row.id = option_row.product_id where option_row.id = v_candidate_text::uuid and product_row.company_id = p_company_id) then
                v_blockers := v_blockers || jsonb_build_array(jsonb_build_object('code', 'deleted_product_option_not_found', 'path', 'deleted_ids.product_options', 'message', 'Deleted product options must belong to the current company.', 'id', v_candidate_text));
              elsif exists (select 1 from public.product_pricing_modifiers modifier_row join public.products product_row on product_row.id = modifier_row.product_id where modifier_row.option_id = v_candidate_text::uuid and product_row.company_id = p_company_id and modifier_row.deleted_at is null and not exists (select 1 from jsonb_array_elements(case when jsonb_typeof(v_deleted_ids -> 'product_pricing_modifiers') = 'array' then v_deleted_ids -> 'product_pricing_modifiers' else '[]'::jsonb end) as deleted_modifier(value) where deleted_modifier.value #>> '{}' = modifier_row.id::text)) then
                v_blockers := v_blockers || jsonb_build_array(jsonb_build_object('code', 'pricing_modifier_dependency_delete_blocked', 'path', 'deleted_ids.product_options', 'message', 'Product options with active pricing modifiers cannot be deleted by setup edit unless modifiers are explicitly deleted first.', 'id', v_candidate_text));
              elsif exists (select 1 from public.product_materials material_row join public.products product_row on product_row.id = material_row.product_id where material_row.scaled_by_option_id = v_candidate_text::uuid and product_row.company_id = p_company_id and material_row.deleted_at is null and not exists (select 1 from jsonb_array_elements(case when jsonb_typeof(v_deleted_ids -> 'product_materials') = 'array' then v_deleted_ids -> 'product_materials' else '[]'::jsonb end) as deleted_material(value) where deleted_material.value #>> '{}' = material_row.id::text)) then
                v_blockers := v_blockers || jsonb_build_array(jsonb_build_object('code', 'product_material_dependency_delete_blocked', 'path', 'deleted_ids.product_options', 'message', 'Product options used by active product materials cannot be deleted by setup edit.', 'id', v_candidate_text));
              end if;
            when 'product_option_values' then
              if not exists (select 1 from public.product_option_values value_row join public.product_options option_row on option_row.id = value_row.option_id join public.products product_row on product_row.id = option_row.product_id where value_row.id = v_candidate_text::uuid and product_row.company_id = p_company_id) then
                v_blockers := v_blockers || jsonb_build_array(jsonb_build_object('code', 'deleted_product_option_value_not_found', 'path', 'deleted_ids.product_option_values', 'message', 'Deleted product option values must belong to the current company.', 'id', v_candidate_text));
              elsif exists (select 1 from public.product_pricing_modifiers modifier_row join public.products product_row on product_row.id = modifier_row.product_id where modifier_row.trigger_value_id = v_candidate_text::uuid and product_row.company_id = p_company_id and modifier_row.deleted_at is null and not exists (select 1 from jsonb_array_elements(case when jsonb_typeof(v_deleted_ids -> 'product_pricing_modifiers') = 'array' then v_deleted_ids -> 'product_pricing_modifiers' else '[]'::jsonb end) as deleted_modifier(value) where deleted_modifier.value #>> '{}' = modifier_row.id::text)) then
                v_blockers := v_blockers || jsonb_build_array(jsonb_build_object('code', 'pricing_modifier_dependency_delete_blocked', 'path', 'deleted_ids.product_option_values', 'message', 'Product option values with active pricing modifiers cannot be deleted by setup edit unless modifiers are explicitly deleted first.', 'id', v_candidate_text));
              end if;
            when 'product_pricing_modifiers' then
              if not exists (select 1 from public.product_pricing_modifiers modifier_row join public.products product_row on product_row.id = modifier_row.product_id where modifier_row.id = v_candidate_text::uuid and product_row.company_id = p_company_id) then
                v_blockers := v_blockers || jsonb_build_array(jsonb_build_object('code', 'deleted_product_pricing_modifier_not_found', 'path', 'deleted_ids.product_pricing_modifiers', 'message', 'Deleted product pricing modifiers must belong to the current company.', 'id', v_candidate_text));
              end if;
            when 'product_materials' then
              if not exists (select 1 from public.product_materials material_row join public.products product_row on product_row.id = material_row.product_id where material_row.id = v_candidate_text::uuid and product_row.company_id = p_company_id) then
                v_blockers := v_blockers || jsonb_build_array(jsonb_build_object('code', 'deleted_product_material_not_found', 'path', 'deleted_ids.product_materials', 'message', 'Deleted product materials must belong to the current company.', 'id', v_candidate_text));
              end if;
            when 'product_bundle_items' then
              if not exists (select 1 from public.product_bundle_items where id = v_candidate_text::uuid and company_id = p_company_id) then
                v_blockers := v_blockers || jsonb_build_array(jsonb_build_object('code', 'deleted_product_bundle_item_not_found', 'path', 'deleted_ids.product_bundle_items', 'message', 'Deleted bundle items must belong to the current company.', 'id', v_candidate_text));
              end if;
            when 'catalog_product_option_mappings' then
              if not exists (select 1 from public.catalog_product_option_mappings where id = v_candidate_text::uuid and company_id = p_company_id) then
                v_blockers := v_blockers || jsonb_build_array(jsonb_build_object('code', 'deleted_catalog_product_option_mapping_not_found', 'path', 'deleted_ids.catalog_product_option_mappings', 'message', 'Deleted catalog/product option mappings must belong to the current company.', 'id', v_candidate_text));
              end if;
          end case;
        end if;
      end loop;
    end loop;
  end if;

  if jsonb_array_length(v_blockers) > 0 then
    v_response := jsonb_build_object(
      'ok', false,
      'mode', v_mode,
      'company_id', p_company_id,
      'idempotency_key', btrim(p_idempotency_key),
      'request_hash', v_request_hash,
      'warnings', v_warnings,
      'blockers', v_blockers,
      'id_map', '{}'::jsonb,
      'validated_counts', jsonb_build_object(
        'catalog_options', jsonb_array_length(v_catalog_options),
        'variants', jsonb_array_length(v_variants),
        'stock_units', jsonb_array_length(v_stock_units),
        'stock_unit_events', jsonb_array_length(v_stock_unit_events),
        'products', jsonb_array_length(v_products),
        'product_materials', jsonb_array_length(v_product_materials)
      ),
      'saved_at', null
    );

    update public.catalog_setup_save_requests
       set status = 'failed',
           response = null,
           error = v_response,
           completed_at = v_now
     where id = v_request.id;

    return v_response;
  end if;

  if v_mode = 'edit' then
    v_id_map := '{}'::jsonb;

    v_client_id := nullif(btrim(p_payload #>> '{family,client_id}'), '');
    v_candidate_text := nullif(btrim(coalesce(p_payload #>> '{family,id}', p_payload #>> '{family_id}', '')), '');

    if v_candidate_text ~* v_uuid_pattern then
      v_family_id := v_candidate_text::uuid;
      if v_client_id is not null then
        v_id_map := jsonb_set(v_id_map, array[v_client_id], to_jsonb(v_family_id::text), true);
      end if;

      if jsonb_typeof(p_payload -> 'family') = 'object' then
        update public.catalog_items
           set category_id = case
                 when (p_payload -> 'family') ? 'category_id' and (p_payload #>> '{family,category_id}') ~* v_uuid_pattern then (p_payload #>> '{family,category_id}')::uuid
                 when (p_payload -> 'family') ? 'category_id' then null
                 else category_id
               end,
               name = case
                 when (p_payload -> 'family') ? 'name' then btrim(p_payload #>> '{family,name}')
                 else name
               end,
               description = case
                 when (p_payload -> 'family') ? 'description' then nullif(btrim(coalesce(p_payload #>> '{family,description}', '')), '')
                 else description
               end,
               image_url = case
                 when (p_payload -> 'family') ? 'image_url' then nullif(btrim(coalesce(p_payload #>> '{family,image_url}', '')), '')
                 else image_url
               end,
               default_warning_threshold = case
                 when (p_payload -> 'family') ? 'default_warning_threshold'
                      and coalesce(p_payload #>> '{family,default_warning_threshold}', '') ~ '^-?[0-9]+(\.[0-9]+)?$'
                   then (p_payload #>> '{family,default_warning_threshold}')::double precision
                 when (p_payload -> 'family') ? 'default_warning_threshold' then null
                 else default_warning_threshold
               end,
               default_critical_threshold = case
                 when (p_payload -> 'family') ? 'default_critical_threshold'
                      and coalesce(p_payload #>> '{family,default_critical_threshold}', '') ~ '^-?[0-9]+(\.[0-9]+)?$'
                   then (p_payload #>> '{family,default_critical_threshold}')::double precision
                 when (p_payload -> 'family') ? 'default_critical_threshold' then null
                 else default_critical_threshold
               end,
               default_unit_id = case
                 when ((p_payload -> 'family') ? 'unit_id' or (p_payload -> 'family') ? 'default_unit_id')
                      and coalesce(p_payload #>> '{family,unit_id}', p_payload #>> '{family,default_unit_id}', '') ~* v_uuid_pattern
                   then coalesce(p_payload #>> '{family,unit_id}', p_payload #>> '{family,default_unit_id}')::uuid
                 when ((p_payload -> 'family') ? 'unit_id' or (p_payload -> 'family') ? 'default_unit_id') then null
                 else default_unit_id
               end,
               notes = case
                 when (p_payload -> 'family') ? 'notes' then nullif(btrim(coalesce(p_payload #>> '{family,notes}', '')), '')
                 else notes
               end,
               is_active = true,
               deleted_at = null
         where id = v_family_id
           and company_id = p_company_id;
        v_catalog_items_count := v_catalog_items_count + 1;
      end if;
    end if;

    for v_option_doc in
      select value
        from jsonb_array_elements(v_catalog_options) as option_item(value)
    loop
      v_client_id := nullif(btrim(v_option_doc->>'client_id'), '');
      v_candidate_text := nullif(btrim(coalesce(v_option_doc->>'id', '')), '');
      v_catalog_option_id := case
        when v_candidate_text ~* v_uuid_pattern then v_candidate_text::uuid
        when v_client_id is not null and v_id_map ? v_client_id then (v_id_map ->> v_client_id)::uuid
        else gen_random_uuid()
      end;

      if v_client_id is not null then
        v_id_map := jsonb_set(v_id_map, array[v_client_id], to_jsonb(v_catalog_option_id::text), true);
      end if;

      insert into public.catalog_options (
        id,
        catalog_item_id,
        name,
        sort_order,
        deleted_at
      )
      values (
        v_catalog_option_id,
        v_family_id,
        btrim(v_option_doc->>'name'),
        case
          when coalesce(v_option_doc->>'sort_order', '') ~ '^-?[0-9]+$' then (v_option_doc->>'sort_order')::integer
          else 0
        end,
        null
      )
      on conflict (id) do update
        set catalog_item_id = excluded.catalog_item_id,
            name = excluded.name,
            sort_order = excluded.sort_order,
            deleted_at = null;
      v_catalog_options_count := v_catalog_options_count + 1;

      for v_value_doc in
        select value
          from jsonb_array_elements(
            case
              when jsonb_typeof(v_option_doc -> 'values') = 'array' then v_option_doc -> 'values'
              else '[]'::jsonb
            end
          ) as value_item(value)
      loop
        v_client_id := nullif(btrim(v_value_doc->>'client_id'), '');
        v_candidate_text := nullif(btrim(coalesce(v_value_doc->>'id', '')), '');
        v_catalog_option_value_id := case
          when v_candidate_text ~* v_uuid_pattern then v_candidate_text::uuid
          when v_client_id is not null and v_id_map ? v_client_id then (v_id_map ->> v_client_id)::uuid
          else gen_random_uuid()
        end;

        if v_client_id is not null then
          v_id_map := jsonb_set(v_id_map, array[v_client_id], to_jsonb(v_catalog_option_value_id::text), true);
        end if;

        insert into public.catalog_option_values (
          id,
          option_id,
          value,
          sort_order,
          deleted_at
        )
        values (
          v_catalog_option_value_id,
          v_catalog_option_id,
          btrim(coalesce(v_value_doc->>'label', v_value_doc->>'value')),
          case
            when coalesce(v_value_doc->>'sort_order', '') ~ '^-?[0-9]+$' then (v_value_doc->>'sort_order')::integer
            else 0
          end,
          null
        )
        on conflict (id) do update
          set option_id = excluded.option_id,
              value = excluded.value,
              sort_order = excluded.sort_order,
              deleted_at = null;
        v_catalog_option_values_count := v_catalog_option_values_count + 1;
      end loop;
    end loop;

    for v_variant_doc in
      select value
        from jsonb_array_elements(v_variants) as variant_item(value)
    loop
      v_client_id := nullif(btrim(v_variant_doc->>'client_id'), '');
      v_candidate_text := nullif(btrim(coalesce(v_variant_doc->>'id', '')), '');
      v_catalog_variant_id := case
        when v_candidate_text ~* v_uuid_pattern then v_candidate_text::uuid
        when v_client_id is not null and v_id_map ? v_client_id then (v_id_map ->> v_client_id)::uuid
        else gen_random_uuid()
      end;

      if v_client_id is not null then
        v_id_map := jsonb_set(v_id_map, array[v_client_id], to_jsonb(v_catalog_variant_id::text), true);
      end if;

      insert into public.catalog_variants (
        id,
        company_id,
        catalog_item_id,
        sku,
        quantity,
        price_override,
        warning_threshold,
        critical_threshold,
        unit_id,
        is_active,
        deleted_at
      )
      values (
        v_catalog_variant_id,
        p_company_id,
        v_family_id,
        nullif(btrim(coalesce(v_variant_doc->>'sku', '')), ''),
        case
          when coalesce(v_variant_doc->>'quantity', '') ~ '^-?[0-9]+(\.[0-9]+)?$' then (v_variant_doc->>'quantity')::double precision
          else 0
        end,
        case
          when coalesce(v_variant_doc->>'price', v_variant_doc->>'price_override', '') ~ '^-?[0-9]+(\.[0-9]+)?$' then coalesce(v_variant_doc->>'price', v_variant_doc->>'price_override')::numeric
          else null
        end,
        case
          when coalesce(v_variant_doc->>'warning_threshold', '') ~ '^-?[0-9]+(\.[0-9]+)?$' then (v_variant_doc->>'warning_threshold')::double precision
          else null
        end,
        case
          when coalesce(v_variant_doc->>'critical_threshold', '') ~ '^-?[0-9]+(\.[0-9]+)?$' then (v_variant_doc->>'critical_threshold')::double precision
          else null
        end,
        case
          when coalesce(v_variant_doc->>'unit_id', '') ~* v_uuid_pattern then (v_variant_doc->>'unit_id')::uuid
          else null
        end,
        lower(coalesce(v_variant_doc->>'excluded', 'false')) not in ('true', 't', '1', 'yes', 'on'),
        null
      )
      on conflict (id) do update
        set catalog_item_id = excluded.catalog_item_id,
            sku = excluded.sku,
            quantity = excluded.quantity,
            price_override = excluded.price_override,
            warning_threshold = excluded.warning_threshold,
            critical_threshold = excluded.critical_threshold,
            unit_id = excluded.unit_id,
            is_active = excluded.is_active,
            deleted_at = null;
      v_catalog_variants_count := v_catalog_variants_count + 1;

      for v_value_doc in
        select value
          from jsonb_array_elements(
            case
              when jsonb_typeof(v_variant_doc -> 'option_value_client_ids') = 'array' then v_variant_doc -> 'option_value_client_ids'
              else '[]'::jsonb
            end
          ) as value_item(value)
      loop
        v_ref_text := nullif(btrim(v_value_doc #>> '{}'), '');
        v_ref_uuid := null;

        if v_ref_text is not null and v_id_map ? v_ref_text then
          v_ref_uuid := (v_id_map ->> v_ref_text)::uuid;
        elsif v_ref_text ~* v_uuid_pattern then
          v_ref_uuid := v_ref_text::uuid;
        end if;

        insert into public.catalog_variant_option_values (
          id,
          variant_id,
          option_value_id,
          deleted_at
        )
        values (
          gen_random_uuid(),
          v_catalog_variant_id,
          v_ref_uuid,
          null
        )
        on conflict (variant_id, option_value_id) where deleted_at is null do update
          set deleted_at = null;
        v_catalog_variant_option_values_count := v_catalog_variant_option_values_count + 1;
      end loop;

      for v_value_doc in
        select value
          from jsonb_array_elements(
            case
              when jsonb_typeof(v_variant_doc -> 'option_value_ids') = 'array' then v_variant_doc -> 'option_value_ids'
              else '[]'::jsonb
            end
          ) as value_item(value)
      loop
        v_ref_text := nullif(btrim(v_value_doc #>> '{}'), '');
        v_ref_uuid := case
          when v_ref_text ~* v_uuid_pattern then v_ref_text::uuid
          else null
        end;

        insert into public.catalog_variant_option_values (
          id,
          variant_id,
          option_value_id,
          deleted_at
        )
        values (
          gen_random_uuid(),
          v_catalog_variant_id,
          v_ref_uuid,
          null
        )
        on conflict (variant_id, option_value_id) where deleted_at is null do update
          set deleted_at = null;
        v_catalog_variant_option_values_count := v_catalog_variant_option_values_count + 1;
      end loop;
    end loop;

    for v_stock_doc in
      select value
        from jsonb_array_elements(v_stock_units) as stock_item(value)
    loop
      v_client_id := nullif(btrim(v_stock_doc->>'client_id'), '');
      v_candidate_text := nullif(btrim(coalesce(v_stock_doc->>'id', '')), '');
      v_catalog_stock_unit_id := case
        when v_candidate_text ~* v_uuid_pattern then v_candidate_text::uuid
        when v_client_id is not null and v_id_map ? v_client_id then (v_id_map ->> v_client_id)::uuid
        else gen_random_uuid()
      end;

      if v_client_id is not null then
        v_id_map := jsonb_set(v_id_map, array[v_client_id], to_jsonb(v_catalog_stock_unit_id::text), true);
      end if;

      v_ref_uuid := null;
      v_ref_text := nullif(btrim(coalesce(v_stock_doc->>'variant_client_id', '')), '');

      if v_ref_text is not null and v_id_map ? v_ref_text then
        v_ref_uuid := (v_id_map ->> v_ref_text)::uuid;
      else
        v_ref_text := nullif(btrim(coalesce(v_stock_doc->>'catalog_variant_id', v_stock_doc->>'variant_id', '')), '');
        if v_ref_text ~* v_uuid_pattern then
          v_ref_uuid := v_ref_text::uuid;
        end if;
      end if;

      v_existing_stock_status := null;
      v_existing_stock_quantity := null;
      v_existing_stock_remaining := null;
      v_existing_stock_deleted_at := null;
      v_existing_stock_variant_id := null;

      select status,
             quantity_value,
             remaining_length_value,
             deleted_at,
             catalog_variant_id
        into v_existing_stock_status,
             v_existing_stock_quantity,
             v_existing_stock_remaining,
             v_existing_stock_deleted_at,
             v_existing_stock_variant_id
        from public.catalog_stock_units
       where id = v_catalog_stock_unit_id
         and company_id = p_company_id;

      insert into public.catalog_stock_units (
        id,
        company_id,
        catalog_variant_id,
        unit_kind,
        label,
        lot_code,
        width_value,
        width_unit,
        original_length_value,
        remaining_length_value,
        length_unit,
        quantity_value,
        location,
        status,
        source_order_item_id,
        notes,
        deleted_at
      )
      values (
        v_catalog_stock_unit_id,
        p_company_id,
        v_ref_uuid,
        coalesce(nullif(btrim(v_stock_doc->>'unit_kind'), ''), 'each'),
        nullif(btrim(coalesce(v_stock_doc->>'label', '')), ''),
        nullif(btrim(coalesce(v_stock_doc->>'lot_code', '')), ''),
        case
          when coalesce(v_stock_doc->>'width_value', '') ~ '^-?[0-9]+(\.[0-9]+)?$' then (v_stock_doc->>'width_value')::numeric
          else null
        end,
        nullif(btrim(coalesce(v_stock_doc->>'width_unit', '')), ''),
        case
          when coalesce(v_stock_doc->>'original_length_value', '') ~ '^-?[0-9]+(\.[0-9]+)?$' then (v_stock_doc->>'original_length_value')::numeric
          else null
        end,
        case
          when coalesce(v_stock_doc->>'remaining_length_value', '') ~ '^-?[0-9]+(\.[0-9]+)?$' then (v_stock_doc->>'remaining_length_value')::numeric
          else null
        end,
        nullif(btrim(coalesce(v_stock_doc->>'length_unit', '')), ''),
        coalesce(
          case
            when coalesce(v_stock_doc->>'quantity_value', '') ~ '^-?[0-9]+(\.[0-9]+)?$' then (v_stock_doc->>'quantity_value')::numeric
            else null
          end,
          1
        ),
        nullif(btrim(coalesce(v_stock_doc->>'location', '')), ''),
        coalesce(nullif(btrim(v_stock_doc->>'status'), ''), 'full'),
        case
          when coalesce(v_stock_doc->>'source_order_item_id', '') ~* v_uuid_pattern then (v_stock_doc->>'source_order_item_id')::uuid
          else null
        end,
        nullif(btrim(coalesce(v_stock_doc->>'notes', '')), ''),
        null
      )
      on conflict (id) do update
        set catalog_variant_id = excluded.catalog_variant_id,
            unit_kind = excluded.unit_kind,
            label = excluded.label,
            lot_code = excluded.lot_code,
            width_value = excluded.width_value,
            width_unit = excluded.width_unit,
            original_length_value = excluded.original_length_value,
            remaining_length_value = excluded.remaining_length_value,
            length_unit = excluded.length_unit,
            quantity_value = excluded.quantity_value,
            location = excluded.location,
            status = excluded.status,
            source_order_item_id = excluded.source_order_item_id,
            notes = excluded.notes,
            deleted_at = null;
      v_catalog_stock_units_count := v_catalog_stock_units_count + 1;

      v_quantity_delta := coalesce(
        case
          when coalesce(v_stock_doc->>'quantity_value', '') ~ '^-?[0-9]+(\.[0-9]+)?$' then (v_stock_doc->>'quantity_value')::numeric
          else null
        end,
        1
      ) - coalesce(v_existing_stock_quantity, 0);
      v_remaining_length_delta := coalesce(
        case
          when coalesce(v_stock_doc->>'remaining_length_value', '') ~ '^-?[0-9]+(\.[0-9]+)?$' then (v_stock_doc->>'remaining_length_value')::numeric
          else null
        end,
        0
      ) - coalesce(v_existing_stock_remaining, 0);
      v_event_type := null;

      if v_existing_stock_status is null then
        v_event_type := 'receive';
      elsif v_existing_stock_deleted_at is not null then
        v_event_type := 'restore';
      elsif coalesce(nullif(btrim(v_stock_doc->>'status'), ''), 'full') is distinct from v_existing_stock_status then
        v_event_type := case
          when coalesce(nullif(btrim(v_stock_doc->>'status'), ''), 'full') = 'reserved' then 'reserve'
          when v_existing_stock_status = 'reserved'
               and coalesce(nullif(btrim(v_stock_doc->>'status'), ''), 'full') in ('full', 'partial') then 'release'
          when coalesce(nullif(btrim(v_stock_doc->>'status'), ''), 'full') = 'consumed' then 'consume'
          when coalesce(nullif(btrim(v_stock_doc->>'status'), ''), 'full') = 'scrapped' then 'scrap'
          when v_existing_stock_status in ('consumed', 'scrapped')
               and coalesce(nullif(btrim(v_stock_doc->>'status'), ''), 'full') in ('full', 'partial', 'reserved') then 'restore'
          else 'adjust'
        end;
      elsif v_quantity_delta <> 0 or v_remaining_length_delta <> 0 or v_existing_stock_variant_id is distinct from v_ref_uuid then
        v_event_type := 'adjust';
      end if;

      if v_event_type is not null
         and not exists (
           select 1
             from jsonb_array_elements(v_stock_unit_events) as explicit_event(value)
            where nullif(btrim(coalesce(
                    explicit_event.value->>'stock_unit_client_id',
                    explicit_event.value->>'catalog_stock_unit_client_id',
                    ''
                  )), '') = v_client_id
               or nullif(btrim(coalesce(
                    explicit_event.value->>'catalog_stock_unit_id',
                    explicit_event.value->>'stock_unit_id',
                    ''
                  )), '') = v_catalog_stock_unit_id::text
         ) then
        insert into public.catalog_stock_unit_events (
          company_id,
          catalog_stock_unit_id,
          catalog_variant_id,
          event_type,
          from_status,
          to_status,
          quantity_delta,
          remaining_length_delta,
          payload
        )
        values (
          p_company_id,
          v_catalog_stock_unit_id,
          v_ref_uuid,
          v_event_type,
          v_existing_stock_status,
          coalesce(nullif(btrim(v_stock_doc->>'status'), ''), 'full'),
          case when v_event_type = 'receive' then coalesce(v_quantity_delta, 1) else v_quantity_delta end,
          case when v_event_type = 'receive' then nullif(v_remaining_length_delta, 0) else v_remaining_length_delta end,
          jsonb_build_object(
            'source', 'catalog_setup_save',
            'mode', 'edit',
            'stock_unit_client_id', nullif(btrim(coalesce(v_stock_doc->>'client_id', '')), '')
          )
        );
        v_catalog_stock_unit_events_count := v_catalog_stock_unit_events_count + 1;
      end if;

      if coalesce(nullif(btrim(v_stock_doc->>'unit_kind'), ''), 'each') = 'offcut'
         and v_existing_stock_status is null
         and not exists (
           select 1
             from jsonb_array_elements(v_stock_unit_events) as explicit_event(value)
            where nullif(btrim(coalesce(
                    explicit_event.value->>'stock_unit_client_id',
                    explicit_event.value->>'catalog_stock_unit_client_id',
                    ''
                  )), '') = v_client_id
               or nullif(btrim(coalesce(
                    explicit_event.value->>'catalog_stock_unit_id',
                    explicit_event.value->>'stock_unit_id',
                    ''
                  )), '') = v_catalog_stock_unit_id::text
         ) then
        v_related_stock_unit_id := null;
        v_ref_text := nullif(btrim(coalesce(
          v_stock_doc->>'related_catalog_stock_unit_client_id',
          v_stock_doc->>'source_stock_unit_client_id',
          ''
        )), '');

        if v_ref_text is not null and v_id_map ? v_ref_text then
          v_related_stock_unit_id := (v_id_map ->> v_ref_text)::uuid;
        else
          v_ref_text := nullif(btrim(coalesce(
            v_stock_doc->>'related_catalog_stock_unit_id',
            v_stock_doc->>'source_stock_unit_id',
            ''
          )), '');
          if v_ref_text ~* v_uuid_pattern then
            v_related_stock_unit_id := v_ref_text::uuid;
          end if;
        end if;

        insert into public.catalog_stock_unit_events (
          company_id,
          catalog_stock_unit_id,
          catalog_variant_id,
          related_catalog_stock_unit_id,
          event_type,
          to_status,
          quantity_delta,
          remaining_length_delta,
          payload
        )
        values (
          p_company_id,
          v_catalog_stock_unit_id,
          v_ref_uuid,
          v_related_stock_unit_id,
          'offcut_create',
          coalesce(nullif(btrim(v_stock_doc->>'status'), ''), 'full'),
          coalesce(
            case
              when coalesce(v_stock_doc->>'quantity_value', '') ~ '^-?[0-9]+(\.[0-9]+)?$' then (v_stock_doc->>'quantity_value')::numeric
              else null
            end,
            1
          ),
          case
            when coalesce(v_stock_doc->>'remaining_length_value', '') ~ '^-?[0-9]+(\.[0-9]+)?$' then (v_stock_doc->>'remaining_length_value')::numeric
            else null
          end,
          jsonb_build_object(
            'source', 'catalog_setup_save',
            'mode', 'edit',
            'stock_unit_client_id', nullif(btrim(coalesce(v_stock_doc->>'client_id', '')), ''),
            'related_catalog_stock_unit_client_id', nullif(btrim(coalesce(
              v_stock_doc->>'related_catalog_stock_unit_client_id',
              v_stock_doc->>'source_stock_unit_client_id',
              ''
            )), '')
          )
        );
        v_catalog_stock_unit_events_count := v_catalog_stock_unit_events_count + 1;
      end if;
    end loop;

    for v_stock_event_doc in
      select value
        from jsonb_array_elements(v_stock_unit_events) as stock_event_item(value)
    loop
      v_event_type := nullif(btrim(coalesce(v_stock_event_doc->>'event_type', '')), '');
      v_catalog_stock_unit_id := null;
      v_client_id := nullif(btrim(coalesce(
        v_stock_event_doc->>'stock_unit_client_id',
        v_stock_event_doc->>'catalog_stock_unit_client_id',
        ''
      )), '');

      if v_client_id is not null and v_id_map ? v_client_id then
        v_catalog_stock_unit_id := (v_id_map ->> v_client_id)::uuid;
      else
        v_candidate_text := nullif(btrim(coalesce(
          v_stock_event_doc->>'catalog_stock_unit_id',
          v_stock_event_doc->>'stock_unit_id',
          ''
        )), '');
        if v_candidate_text ~* v_uuid_pattern then
          v_catalog_stock_unit_id := v_candidate_text::uuid;
        end if;
      end if;

      if v_catalog_stock_unit_id is null then
        continue;
      end if;

      v_ref_uuid := null;
      v_ref_text := nullif(btrim(coalesce(v_stock_event_doc->>'variant_client_id', '')), '');
      if v_ref_text is not null and v_id_map ? v_ref_text then
        v_ref_uuid := (v_id_map ->> v_ref_text)::uuid;
      else
        v_ref_text := nullif(btrim(coalesce(
          v_stock_event_doc->>'catalog_variant_id',
          v_stock_event_doc->>'variant_id',
          ''
        )), '');
        if v_ref_text ~* v_uuid_pattern then
          v_ref_uuid := v_ref_text::uuid;
        end if;
      end if;

      if v_ref_uuid is null then
        select catalog_variant_id
          into v_ref_uuid
          from public.catalog_stock_units
         where id = v_catalog_stock_unit_id
           and company_id = p_company_id;
      end if;

      v_related_stock_unit_id := null;
      v_ref_text := nullif(btrim(coalesce(
        v_stock_event_doc->>'related_catalog_stock_unit_client_id',
        v_stock_event_doc->>'source_stock_unit_client_id',
        ''
      )), '');

      if v_ref_text is not null and v_id_map ? v_ref_text then
        v_related_stock_unit_id := (v_id_map ->> v_ref_text)::uuid;
      else
        v_ref_text := nullif(btrim(coalesce(
          v_stock_event_doc->>'related_catalog_stock_unit_id',
          v_stock_event_doc->>'source_stock_unit_id',
          ''
        )), '');
        if v_ref_text ~* v_uuid_pattern then
          v_related_stock_unit_id := v_ref_text::uuid;
        end if;
      end if;

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
        marker,
        notes
      )
      values (
        p_company_id,
        v_catalog_stock_unit_id,
        v_ref_uuid,
        v_related_stock_unit_id,
        v_event_type,
        nullif(btrim(coalesce(v_stock_event_doc->>'from_status', '')), ''),
        nullif(btrim(coalesce(v_stock_event_doc->>'to_status', '')), ''),
        case
          when coalesce(v_stock_event_doc->>'quantity_delta', '') ~ '^-?[0-9]+(\.[0-9]+)?$' then (v_stock_event_doc->>'quantity_delta')::numeric
          else null
        end,
        case
          when coalesce(v_stock_event_doc->>'remaining_length_delta', '') ~ '^-?[0-9]+(\.[0-9]+)?$' then (v_stock_event_doc->>'remaining_length_delta')::numeric
          else null
        end,
        coalesce(
          case
            when jsonb_typeof(v_stock_event_doc -> 'payload') = 'object' then v_stock_event_doc -> 'payload'
            else '{}'::jsonb
          end,
          '{}'::jsonb
        ) || jsonb_build_object(
          'source', 'catalog_setup_save',
          'mode', 'edit',
          'stock_unit_client_id', v_client_id,
          'event_id', nullif(btrim(coalesce(v_stock_event_doc->>'event_id', '')), '')
        ),
        nullif(btrim(coalesce(v_stock_event_doc->>'marker', '')), ''),
        nullif(btrim(coalesce(v_stock_event_doc->>'notes', '')), '')
      );
      v_catalog_stock_unit_events_count := v_catalog_stock_unit_events_count + 1;
    end loop;

    for v_product_doc in
      select value
        from jsonb_array_elements(v_products) as product_item(value)
    loop
      v_client_id := nullif(btrim(v_product_doc->>'client_id'), '');
      v_candidate_text := nullif(btrim(coalesce(v_product_doc->>'id', '')), '');
      v_product_id := case
        when v_candidate_text ~* v_uuid_pattern then v_candidate_text::uuid
        when v_client_id is not null and v_id_map ? v_client_id then (v_id_map ->> v_client_id)::uuid
        else gen_random_uuid()
      end;

      if v_client_id is not null then
        v_id_map := jsonb_set(v_id_map, array[v_client_id], to_jsonb(v_product_id::text), true);
      end if;

      v_ref_uuid := null;
      v_ref_text := nullif(btrim(coalesce(v_product_doc->>'linked_catalog_item_client_id', '')), '');

      if v_ref_text is not null and v_id_map ? v_ref_text then
        v_ref_uuid := (v_id_map ->> v_ref_text)::uuid;
      else
        v_ref_text := nullif(btrim(coalesce(v_product_doc->>'linked_catalog_item_id', v_product_doc->>'catalog_item_id', '')), '');
        if v_ref_text ~* v_uuid_pattern then
          v_ref_uuid := v_ref_text::uuid;
        elsif v_family_id is not null then
          v_ref_uuid := v_family_id;
        end if;
      end if;
      v_product_catalog_item_id := v_ref_uuid;

      insert into public.products (
        id,
        company_id,
        name,
        description,
        default_price,
        unit,
        category,
        is_taxable,
        is_active,
        type,
        unit_id,
        kind,
        sku,
        is_favorite,
        minimum_charge,
        minimum_quantity,
        show_bom_on_estimate,
        show_in_storefront,
        tiered_pricing,
        base_price,
        pricing_unit,
        category_id,
        thumbnail_url,
        linked_catalog_item_id,
        bundle_pricing_mode,
        deleted_at
      )
      values (
        v_product_id,
        p_company_id,
        btrim(v_product_doc->>'name'),
        nullif(btrim(coalesce(v_product_doc->>'description', '')), ''),
        coalesce(
          case
            when coalesce(v_product_doc->>'default_price', v_product_doc->>'base_price', v_product_doc->>'price', '') ~ '^-?[0-9]+(\.[0-9]+)?$' then coalesce(v_product_doc->>'default_price', v_product_doc->>'base_price', v_product_doc->>'price')::numeric
            else null
          end,
          0
        ),
        coalesce(nullif(btrim(v_product_doc->>'unit'), ''), nullif(btrim(v_product_doc->>'pricing_unit'), ''), 'each'),
        nullif(btrim(coalesce(v_product_doc->>'category', '')), ''),
        lower(coalesce(v_product_doc->>'is_taxable', 'true')) not in ('false', 'f', '0', 'no', 'off'),
        lower(coalesce(v_product_doc->>'is_active', 'true')) not in ('false', 'f', '0', 'no', 'off'),
        upper(coalesce(nullif(btrim(v_product_doc->>'type'), ''), case when coalesce(v_product_doc->>'kind', 'material') = 'material' then 'MATERIAL' else 'OTHER' end)),
        case
          when coalesce(v_product_doc->>'unit_id', '') ~* v_uuid_pattern then (v_product_doc->>'unit_id')::uuid
          else null
        end,
        coalesce(nullif(btrim(v_product_doc->>'kind'), ''), 'material'),
        nullif(btrim(coalesce(v_product_doc->>'sku', '')), ''),
        lower(coalesce(v_product_doc->>'is_favorite', 'false')) in ('true', 't', '1', 'yes', 'on'),
        case
          when coalesce(v_product_doc->>'minimum_charge', '') ~ '^-?[0-9]+(\.[0-9]+)?$' then (v_product_doc->>'minimum_charge')::numeric
          else null
        end,
        case
          when coalesce(v_product_doc->>'minimum_quantity', '') ~ '^-?[0-9]+(\.[0-9]+)?$' then (v_product_doc->>'minimum_quantity')::numeric
          else null
        end,
        lower(coalesce(v_product_doc->>'show_bom_on_estimate', 'false')) in ('true', 't', '1', 'yes', 'on'),
        lower(coalesce(v_product_doc->>'show_in_storefront', 'false')) in ('true', 't', '1', 'yes', 'on'),
        case
          when jsonb_typeof(v_product_doc -> 'tiered_pricing') = 'object' then v_product_doc -> 'tiered_pricing'
          else '{}'::jsonb
        end,
        coalesce(
          case
            when coalesce(v_product_doc->>'base_price', v_product_doc->>'default_price', v_product_doc->>'price', '') ~ '^-?[0-9]+(\.[0-9]+)?$' then coalesce(v_product_doc->>'base_price', v_product_doc->>'default_price', v_product_doc->>'price')::numeric
            else null
          end,
          0
        ),
        coalesce(nullif(btrim(v_product_doc->>'pricing_unit'), ''), 'each'),
        case
          when coalesce(v_product_doc->>'category_id', '') ~* v_uuid_pattern then (v_product_doc->>'category_id')::uuid
          else null
        end,
        nullif(btrim(coalesce(v_product_doc->>'thumbnail_url', '')), ''),
        v_ref_uuid,
        nullif(btrim(coalesce(v_product_doc->>'bundle_pricing_mode', '')), ''),
        null
      )
      on conflict (id) do update
        set name = excluded.name,
            description = excluded.description,
            default_price = excluded.default_price,
            unit = excluded.unit,
            category = excluded.category,
            is_taxable = excluded.is_taxable,
            is_active = excluded.is_active,
            type = excluded.type,
            unit_id = excluded.unit_id,
            kind = excluded.kind,
            sku = excluded.sku,
            is_favorite = excluded.is_favorite,
            minimum_charge = excluded.minimum_charge,
            minimum_quantity = excluded.minimum_quantity,
            show_bom_on_estimate = excluded.show_bom_on_estimate,
            show_in_storefront = excluded.show_in_storefront,
            tiered_pricing = excluded.tiered_pricing,
            base_price = excluded.base_price,
            pricing_unit = excluded.pricing_unit,
            category_id = excluded.category_id,
            thumbnail_url = excluded.thumbnail_url,
            linked_catalog_item_id = excluded.linked_catalog_item_id,
            bundle_pricing_mode = excluded.bundle_pricing_mode,
            deleted_at = null;
      v_products_count := v_products_count + 1;

      for v_option_doc in
        select value
          from jsonb_array_elements(
            case
              when jsonb_typeof(v_product_doc -> 'options') = 'array' then v_product_doc -> 'options'
              else '[]'::jsonb
            end
          ) as option_item(value)
      loop
        v_client_id := nullif(btrim(v_option_doc->>'client_id'), '');
        v_candidate_text := nullif(btrim(coalesce(v_option_doc->>'id', '')), '');
        v_product_option_id := case
          when v_candidate_text ~* v_uuid_pattern then v_candidate_text::uuid
          when v_client_id is not null and v_id_map ? v_client_id then (v_id_map ->> v_client_id)::uuid
          else gen_random_uuid()
        end;

        if v_client_id is not null then
          v_id_map := jsonb_set(v_id_map, array[v_client_id], to_jsonb(v_product_option_id::text), true);
        end if;

        insert into public.product_options (
          id,
          product_id,
          name,
          kind,
          affects_price,
          affects_recipe,
          required,
          default_value,
          option_default_source,
          sort_order,
          deleted_at
        )
        values (
          v_product_option_id,
          v_product_id,
          btrim(v_option_doc->>'name'),
          v_option_doc->>'kind',
          lower(coalesce(v_option_doc->>'affects_price', 'false')) in ('true', 't', '1', 'yes', 'on'),
          lower(coalesce(v_option_doc->>'affects_recipe', 'false')) in ('true', 't', '1', 'yes', 'on'),
          lower(coalesce(v_option_doc->>'required', 'true')) not in ('false', 'f', '0', 'no', 'off'),
          nullif(btrim(coalesce(v_option_doc->>'default_value', '')), ''),
          nullif(btrim(coalesce(v_option_doc->>'option_default_source', '')), ''),
          case
            when coalesce(v_option_doc->>'sort_order', '') ~ '^-?[0-9]+$' then (v_option_doc->>'sort_order')::integer
            else 0
          end,
          null
        )
        on conflict (id) do update
          set product_id = excluded.product_id,
              name = excluded.name,
              kind = excluded.kind,
              affects_price = excluded.affects_price,
              affects_recipe = excluded.affects_recipe,
              required = excluded.required,
              default_value = excluded.default_value,
              option_default_source = excluded.option_default_source,
              sort_order = excluded.sort_order,
              deleted_at = null;
        v_product_options_count := v_product_options_count + 1;

        for v_value_doc in
          select value
            from jsonb_array_elements(
              case
                when jsonb_typeof(v_option_doc -> 'values') = 'array' then v_option_doc -> 'values'
                else '[]'::jsonb
              end
            ) as value_item(value)
        loop
          v_client_id := nullif(btrim(v_value_doc->>'client_id'), '');
          v_candidate_text := nullif(btrim(coalesce(v_value_doc->>'id', '')), '');
          v_product_option_value_id := case
            when v_candidate_text ~* v_uuid_pattern then v_candidate_text::uuid
            when v_client_id is not null and v_id_map ? v_client_id then (v_id_map ->> v_client_id)::uuid
            else gen_random_uuid()
          end;

          if v_client_id is not null then
            v_id_map := jsonb_set(v_id_map, array[v_client_id], to_jsonb(v_product_option_value_id::text), true);
          end if;

          insert into public.product_option_values (
            id,
            option_id,
            value,
            sort_order,
            deleted_at
          )
          values (
            v_product_option_value_id,
            v_product_option_id,
            btrim(coalesce(v_value_doc->>'label', v_value_doc->>'value')),
            case
              when coalesce(v_value_doc->>'sort_order', '') ~ '^-?[0-9]+$' then (v_value_doc->>'sort_order')::integer
              else 0
            end,
            null
          )
          on conflict (id) do update
            set option_id = excluded.option_id,
                value = excluded.value,
                sort_order = excluded.sort_order,
                deleted_at = null;
          v_product_option_values_count := v_product_option_values_count + 1;
        end loop;
      end loop;

      for v_modifier_doc in
        select value
          from jsonb_array_elements(
            case
              when jsonb_typeof(v_product_doc -> 'pricing_modifiers') = 'array' then v_product_doc -> 'pricing_modifiers'
              else '[]'::jsonb
            end
          ) as modifier_item(value)
      loop
        v_client_id := nullif(btrim(v_modifier_doc->>'client_id'), '');
        v_candidate_text := nullif(btrim(coalesce(v_modifier_doc->>'id', '')), '');
        v_candidate_uuid := case
          when v_candidate_text ~* v_uuid_pattern then v_candidate_text::uuid
          when v_client_id is not null and v_id_map ? v_client_id then (v_id_map ->> v_client_id)::uuid
          else gen_random_uuid()
        end;

        if v_client_id is not null then
          v_id_map := jsonb_set(v_id_map, array[v_client_id], to_jsonb(v_candidate_uuid::text), true);
        end if;

        v_ref_uuid := null;
        v_ref_text := nullif(btrim(coalesce(v_modifier_doc->>'option_client_id', '')), '');

        if v_ref_text is not null and v_id_map ? v_ref_text then
          v_ref_uuid := (v_id_map ->> v_ref_text)::uuid;
        else
          v_ref_text := nullif(btrim(coalesce(v_modifier_doc->>'option_id', '')), '');
          if v_ref_text ~* v_uuid_pattern then
            v_ref_uuid := v_ref_text::uuid;
          end if;
        end if;

        v_product_option_value_id := null;
        v_ref_text := nullif(btrim(coalesce(v_modifier_doc->>'option_value_client_id', v_modifier_doc->>'trigger_value_client_id', '')), '');

        if v_ref_text is not null and v_id_map ? v_ref_text then
          v_product_option_value_id := (v_id_map ->> v_ref_text)::uuid;
        else
          v_ref_text := nullif(btrim(coalesce(v_modifier_doc->>'trigger_value_id', v_modifier_doc->>'option_value_id', '')), '');
          if v_ref_text ~* v_uuid_pattern then
            v_product_option_value_id := v_ref_text::uuid;
          end if;
        end if;

        insert into public.product_pricing_modifiers (
          id,
          product_id,
          option_id,
          trigger_value_id,
          trigger_int_min,
          trigger_int_max,
          modifier_kind,
          amount,
          deleted_at
        )
        values (
          v_candidate_uuid,
          v_product_id,
          v_ref_uuid,
          v_product_option_value_id,
          case
            when coalesce(v_modifier_doc->>'trigger_int_min', '') ~ '^-?[0-9]+$' then (v_modifier_doc->>'trigger_int_min')::integer
            else null
          end,
          case
            when coalesce(v_modifier_doc->>'trigger_int_max', '') ~ '^-?[0-9]+$' then (v_modifier_doc->>'trigger_int_max')::integer
            else null
          end,
          v_modifier_doc->>'modifier_kind',
          coalesce(
            case
              when coalesce(v_modifier_doc->>'amount', '') ~ '^-?[0-9]+(\.[0-9]+)?$' then (v_modifier_doc->>'amount')::numeric
              else null
            end,
            0
          ),
          null
        )
        on conflict (id) do update
          set product_id = excluded.product_id,
              option_id = excluded.option_id,
              trigger_value_id = excluded.trigger_value_id,
              trigger_int_min = excluded.trigger_int_min,
              trigger_int_max = excluded.trigger_int_max,
              modifier_kind = excluded.modifier_kind,
              amount = excluded.amount,
              deleted_at = null;
        v_product_pricing_modifiers_count := v_product_pricing_modifiers_count + 1;
      end loop;

      for v_material_doc in
        select material_value
          from (
            select value as material_value
              from jsonb_array_elements(
                case
                  when jsonb_typeof(v_product_doc -> 'product_materials') = 'array' then v_product_doc -> 'product_materials'
                  else '[]'::jsonb
                end
              ) as material_item(value)
            union all
            select value as material_value
              from jsonb_array_elements(
                case
                  when jsonb_typeof(v_product_doc -> 'materials') = 'array' then v_product_doc -> 'materials'
                  else '[]'::jsonb
                end
              ) as material_item(value)
          ) material_items
      loop
        v_client_id := nullif(btrim(v_material_doc->>'client_id'), '');
        v_candidate_text := nullif(btrim(coalesce(v_material_doc->>'id', '')), '');
        v_candidate_uuid := case
          when v_candidate_text ~* v_uuid_pattern then v_candidate_text::uuid
          when v_client_id is not null and v_id_map ? v_client_id then (v_id_map ->> v_client_id)::uuid
          else gen_random_uuid()
        end;

        if v_client_id is not null then
          v_id_map := jsonb_set(v_id_map, array[v_client_id], to_jsonb(v_candidate_uuid::text), true);
        end if;

        v_catalog_variant_id := null;
        v_ref_text := nullif(btrim(coalesce(v_material_doc->>'catalog_variant_client_id', v_material_doc->>'variant_client_id', '')), '');

        if v_ref_text is not null and v_id_map ? v_ref_text then
          v_catalog_variant_id := (v_id_map ->> v_ref_text)::uuid;
        else
          v_ref_text := nullif(btrim(coalesce(v_material_doc->>'catalog_variant_id', v_material_doc->>'variant_id', '')), '');
          if v_ref_text ~* v_uuid_pattern then
            v_catalog_variant_id := v_ref_text::uuid;
          end if;
        end if;

        v_ref_uuid := null;
        v_ref_text := nullif(btrim(coalesce(v_material_doc->>'catalog_item_client_id', v_material_doc->>'family_client_id', '')), '');

        if v_ref_text is not null and v_id_map ? v_ref_text then
          v_ref_uuid := (v_id_map ->> v_ref_text)::uuid;
        else
          v_ref_text := nullif(btrim(coalesce(v_material_doc->>'catalog_item_id', '')), '');
          if v_ref_text ~* v_uuid_pattern then
            v_ref_uuid := v_ref_text::uuid;
          elsif v_family_id is not null and v_catalog_variant_id is null then
            v_ref_uuid := v_family_id;
          end if;
        end if;

        v_product_option_id := null;
        v_ref_text := nullif(btrim(coalesce(v_material_doc->>'scaled_by_option_client_id', '')), '');

        if v_ref_text is not null and v_id_map ? v_ref_text then
          v_product_option_id := (v_id_map ->> v_ref_text)::uuid;
        else
          v_ref_text := nullif(btrim(coalesce(v_material_doc->>'scaled_by_option_id', '')), '');
          if v_ref_text ~* v_uuid_pattern then
            v_product_option_id := v_ref_text::uuid;
          end if;
        end if;

        insert into public.product_materials (
          id,
          product_id,
          inventory_item_id,
          quantity_per_unit,
          notes,
          catalog_variant_id,
          catalog_item_id,
          variant_selector,
          scaled_by_option_id,
          unit_id,
          deleted_at
        )
        values (
          v_candidate_uuid,
          v_product_id,
          case
            when coalesce(v_material_doc->>'inventory_item_id', '') ~* v_uuid_pattern then (v_material_doc->>'inventory_item_id')::uuid
            else null
          end,
          coalesce(
            case
              when coalesce(v_material_doc->>'quantity_per_unit', v_material_doc->>'quantity', '') ~ '^-?[0-9]+(\.[0-9]+)?$' then coalesce(v_material_doc->>'quantity_per_unit', v_material_doc->>'quantity')::double precision
              else null
            end,
            1
          ),
          nullif(btrim(coalesce(v_material_doc->>'notes', '')), ''),
          v_catalog_variant_id,
          v_ref_uuid,
          case
            when jsonb_typeof(v_material_doc -> 'variant_selector') = 'object' then v_material_doc -> 'variant_selector'
            else null
          end,
          v_product_option_id,
          case
            when coalesce(v_material_doc->>'unit_id', '') ~* v_uuid_pattern then (v_material_doc->>'unit_id')::uuid
            else null
          end,
          null
        )
        on conflict (id) do update
          set product_id = excluded.product_id,
              inventory_item_id = excluded.inventory_item_id,
              quantity_per_unit = excluded.quantity_per_unit,
              notes = excluded.notes,
              catalog_variant_id = excluded.catalog_variant_id,
              catalog_item_id = excluded.catalog_item_id,
              variant_selector = excluded.variant_selector,
              scaled_by_option_id = excluded.scaled_by_option_id,
              unit_id = excluded.unit_id,
              deleted_at = null;
        v_product_materials_count := v_product_materials_count + 1;
      end loop;

      for v_mapping_doc in
        select value
          from jsonb_array_elements(
            case
              when jsonb_typeof(v_product_doc -> 'catalog_option_mappings') = 'array' then v_product_doc -> 'catalog_option_mappings'
              else '[]'::jsonb
            end
          ) as mapping_item(value)
      loop
        v_client_id := nullif(btrim(v_mapping_doc->>'client_id'), '');
        v_candidate_text := nullif(btrim(coalesce(v_mapping_doc->>'id', '')), '');
        v_candidate_uuid := case
          when v_candidate_text ~* v_uuid_pattern then v_candidate_text::uuid
          when v_client_id is not null and v_id_map ? v_client_id then (v_id_map ->> v_client_id)::uuid
          else gen_random_uuid()
        end;

        if v_client_id is not null then
          v_id_map := jsonb_set(v_id_map, array[v_client_id], to_jsonb(v_candidate_uuid::text), true);
        end if;

        v_catalog_option_id := null;
        v_ref_text := nullif(btrim(coalesce(v_mapping_doc->>'catalog_option_client_id', '')), '');

        if v_ref_text is not null and v_id_map ? v_ref_text then
          v_catalog_option_id := (v_id_map ->> v_ref_text)::uuid;
        else
          v_ref_text := nullif(btrim(coalesce(v_mapping_doc->>'catalog_option_id', '')), '');
          if v_ref_text ~* v_uuid_pattern then
            v_catalog_option_id := v_ref_text::uuid;
          end if;
        end if;

        v_product_option_id := null;
        v_ref_text := nullif(btrim(coalesce(v_mapping_doc->>'product_option_client_id', '')), '');

        if v_ref_text is not null and v_id_map ? v_ref_text then
          v_product_option_id := (v_id_map ->> v_ref_text)::uuid;
        else
          v_ref_text := nullif(btrim(coalesce(v_mapping_doc->>'product_option_id', '')), '');
          if v_ref_text ~* v_uuid_pattern then
            v_product_option_id := v_ref_text::uuid;
          end if;
        end if;

        v_catalog_option_value_id := null;
        v_ref_text := nullif(btrim(coalesce(v_mapping_doc->>'catalog_option_value_client_id', '')), '');

        if v_ref_text is not null and v_id_map ? v_ref_text then
          v_catalog_option_value_id := (v_id_map ->> v_ref_text)::uuid;
        else
          v_ref_text := nullif(btrim(coalesce(v_mapping_doc->>'catalog_option_value_id', '')), '');
          if v_ref_text ~* v_uuid_pattern then
            v_catalog_option_value_id := v_ref_text::uuid;
          end if;
        end if;

        v_product_option_value_id := null;
        v_ref_text := nullif(btrim(coalesce(v_mapping_doc->>'product_option_value_client_id', '')), '');

        if v_ref_text is not null and v_id_map ? v_ref_text then
          v_product_option_value_id := (v_id_map ->> v_ref_text)::uuid;
        else
          v_ref_text := nullif(btrim(coalesce(v_mapping_doc->>'product_option_value_id', '')), '');
          if v_ref_text ~* v_uuid_pattern then
            v_product_option_value_id := v_ref_text::uuid;
          end if;
        end if;

        insert into public.catalog_product_option_mappings (
          id,
          company_id,
          product_id,
          catalog_item_id,
          catalog_option_id,
          product_option_id,
          catalog_option_value_id,
          product_option_value_id,
          mapping_kind,
          deleted_at
        )
        values (
          v_candidate_uuid,
          p_company_id,
          v_product_id,
          coalesce(
            case
            when coalesce(v_mapping_doc->>'catalog_item_id', '') ~* v_uuid_pattern then (v_mapping_doc->>'catalog_item_id')::uuid
              else null
            end,
            v_family_id,
            v_product_catalog_item_id
          ),
          v_catalog_option_id,
          v_product_option_id,
          v_catalog_option_value_id,
          v_product_option_value_id,
          v_mapping_doc->>'mapping_kind',
          null
        )
        on conflict (id) do update
          set product_id = excluded.product_id,
              catalog_item_id = excluded.catalog_item_id,
              catalog_option_id = excluded.catalog_option_id,
              product_option_id = excluded.product_option_id,
              catalog_option_value_id = excluded.catalog_option_value_id,
              product_option_value_id = excluded.product_option_value_id,
              mapping_kind = excluded.mapping_kind,
              deleted_at = null;
        v_catalog_product_option_mappings_count := v_catalog_product_option_mappings_count + 1;
      end loop;

      for v_bundle_doc in
        select value
          from jsonb_array_elements(
            case
              when jsonb_typeof(v_product_doc -> 'bundle_items') = 'array' then v_product_doc -> 'bundle_items'
              else '[]'::jsonb
            end
          ) as bundle_item(value)
      loop
        v_client_id := nullif(btrim(v_bundle_doc->>'client_id'), '');
        v_candidate_text := nullif(btrim(coalesce(v_bundle_doc->>'id', '')), '');
        v_candidate_uuid := case
          when v_candidate_text ~* v_uuid_pattern then v_candidate_text::uuid
          when v_client_id is not null and v_id_map ? v_client_id then (v_id_map ->> v_client_id)::uuid
          else gen_random_uuid()
        end;

        if v_client_id is not null then
          v_id_map := jsonb_set(v_id_map, array[v_client_id], to_jsonb(v_candidate_uuid::text), true);
        end if;

        v_ref_uuid := null;
        v_ref_text := nullif(btrim(coalesce(v_bundle_doc->>'child_product_client_id', v_bundle_doc->>'product_client_id', '')), '');

        if v_ref_text is not null and v_id_map ? v_ref_text then
          v_ref_uuid := (v_id_map ->> v_ref_text)::uuid;
        else
          v_ref_text := nullif(btrim(coalesce(v_bundle_doc->>'child_product_id', v_bundle_doc->>'product_id', '')), '');
          if v_ref_text ~* v_uuid_pattern then
            v_ref_uuid := v_ref_text::uuid;
          end if;
        end if;

        insert into public.product_bundle_items (
          id,
          company_id,
          bundle_product_id,
          child_product_id,
          quantity,
          display_order,
          relationship_kind,
          suggestion_reason,
          compatibility_selector,
          deleted_at
        )
        values (
          v_candidate_uuid,
          p_company_id,
          v_product_id,
          v_ref_uuid,
          coalesce(
            case
              when coalesce(v_bundle_doc->>'quantity', '') ~ '^-?[0-9]+(\.[0-9]+)?$' then (v_bundle_doc->>'quantity')::numeric
              else null
            end,
            1
          ),
          case
            when coalesce(v_bundle_doc->>'display_order', v_bundle_doc->>'sort_order', '') ~ '^-?[0-9]+$' then coalesce(v_bundle_doc->>'display_order', v_bundle_doc->>'sort_order')::integer
            else 0
          end,
          coalesce(nullif(btrim(v_bundle_doc->>'relationship_kind'), ''), 'required'),
          nullif(btrim(coalesce(v_bundle_doc->>'suggestion_reason', '')), ''),
          case
            when jsonb_typeof(v_bundle_doc -> 'compatibility_selector') = 'object' then v_bundle_doc -> 'compatibility_selector'
            else null
          end,
          null
        )
        on conflict (id) do update
          set bundle_product_id = excluded.bundle_product_id,
              child_product_id = excluded.child_product_id,
              quantity = excluded.quantity,
              display_order = excluded.display_order,
              relationship_kind = excluded.relationship_kind,
              suggestion_reason = excluded.suggestion_reason,
              compatibility_selector = excluded.compatibility_selector,
              deleted_at = null;
        v_product_bundle_items_count := v_product_bundle_items_count + 1;
      end loop;
    end loop;

    for v_material_doc in
      select value
        from jsonb_array_elements(v_product_materials) as material_item(value)
    loop
      v_client_id := nullif(btrim(v_material_doc->>'client_id'), '');
      v_candidate_text := nullif(btrim(coalesce(v_material_doc->>'id', '')), '');
      v_candidate_uuid := case
        when v_candidate_text ~* v_uuid_pattern then v_candidate_text::uuid
        when v_client_id is not null and v_id_map ? v_client_id then (v_id_map ->> v_client_id)::uuid
        else gen_random_uuid()
      end;

      if v_client_id is not null then
        v_id_map := jsonb_set(v_id_map, array[v_client_id], to_jsonb(v_candidate_uuid::text), true);
      end if;

      v_product_id := null;
      v_ref_text := nullif(btrim(coalesce(v_material_doc->>'product_client_id', '')), '');

      if v_ref_text is not null and v_id_map ? v_ref_text then
        v_product_id := (v_id_map ->> v_ref_text)::uuid;
      else
        v_ref_text := nullif(btrim(coalesce(v_material_doc->>'product_id', '')), '');
        if v_ref_text ~* v_uuid_pattern then
          v_product_id := v_ref_text::uuid;
        end if;
      end if;

      v_catalog_variant_id := null;
      v_ref_text := nullif(btrim(coalesce(v_material_doc->>'catalog_variant_client_id', v_material_doc->>'variant_client_id', '')), '');

      if v_ref_text is not null and v_id_map ? v_ref_text then
        v_catalog_variant_id := (v_id_map ->> v_ref_text)::uuid;
      else
        v_ref_text := nullif(btrim(coalesce(v_material_doc->>'catalog_variant_id', v_material_doc->>'variant_id', '')), '');
        if v_ref_text ~* v_uuid_pattern then
          v_catalog_variant_id := v_ref_text::uuid;
        end if;
      end if;

      v_ref_uuid := null;
      v_ref_text := nullif(btrim(coalesce(v_material_doc->>'catalog_item_client_id', v_material_doc->>'family_client_id', '')), '');

      if v_ref_text is not null and v_id_map ? v_ref_text then
        v_ref_uuid := (v_id_map ->> v_ref_text)::uuid;
      else
        v_ref_text := nullif(btrim(coalesce(v_material_doc->>'catalog_item_id', '')), '');
        if v_ref_text ~* v_uuid_pattern then
          v_ref_uuid := v_ref_text::uuid;
        elsif v_family_id is not null and v_catalog_variant_id is null then
          v_ref_uuid := v_family_id;
        end if;
      end if;

      v_product_option_id := null;
      v_ref_text := nullif(btrim(coalesce(v_material_doc->>'scaled_by_option_client_id', '')), '');

      if v_ref_text is not null and v_id_map ? v_ref_text then
        v_product_option_id := (v_id_map ->> v_ref_text)::uuid;
      else
        v_ref_text := nullif(btrim(coalesce(v_material_doc->>'scaled_by_option_id', '')), '');
        if v_ref_text ~* v_uuid_pattern then
          v_product_option_id := v_ref_text::uuid;
        end if;
      end if;

      insert into public.product_materials (
        id,
        product_id,
        inventory_item_id,
        quantity_per_unit,
        notes,
        catalog_variant_id,
        catalog_item_id,
        variant_selector,
        scaled_by_option_id,
        unit_id,
        deleted_at
      )
      values (
        v_candidate_uuid,
        v_product_id,
        case
          when coalesce(v_material_doc->>'inventory_item_id', '') ~* v_uuid_pattern then (v_material_doc->>'inventory_item_id')::uuid
          else null
        end,
        coalesce(
          case
            when coalesce(v_material_doc->>'quantity_per_unit', v_material_doc->>'quantity', '') ~ '^-?[0-9]+(\.[0-9]+)?$' then coalesce(v_material_doc->>'quantity_per_unit', v_material_doc->>'quantity')::double precision
            else null
          end,
          1
        ),
        nullif(btrim(coalesce(v_material_doc->>'notes', '')), ''),
        v_catalog_variant_id,
        v_ref_uuid,
        case
          when jsonb_typeof(v_material_doc -> 'variant_selector') = 'object' then v_material_doc -> 'variant_selector'
          else null
        end,
        v_product_option_id,
        case
          when coalesce(v_material_doc->>'unit_id', '') ~* v_uuid_pattern then (v_material_doc->>'unit_id')::uuid
          else null
        end,
        null
      )
      on conflict (id) do update
        set product_id = excluded.product_id,
            inventory_item_id = excluded.inventory_item_id,
            quantity_per_unit = excluded.quantity_per_unit,
            notes = excluded.notes,
            catalog_variant_id = excluded.catalog_variant_id,
            catalog_item_id = excluded.catalog_item_id,
            variant_selector = excluded.variant_selector,
            scaled_by_option_id = excluded.scaled_by_option_id,
            unit_id = excluded.unit_id,
            deleted_at = null;
      v_product_materials_count := v_product_materials_count + 1;
    end loop;

    for v_candidate_text in
      select nullif(btrim(deleted_item.value #>> '{}'), '')
        from jsonb_array_elements(case when jsonb_typeof(v_deleted_ids -> 'catalog_items') = 'array' then v_deleted_ids -> 'catalog_items' else '[]'::jsonb end) as deleted_item(value)
    loop
      update public.catalog_items
         set is_active = false,
             deleted_at = v_now
       where id = v_candidate_text::uuid
         and company_id = p_company_id
         and deleted_at is null;
      get diagnostics v_write_count = row_count;
      v_deleted_catalog_items_count := v_deleted_catalog_items_count + v_write_count;
    end loop;

    for v_candidate_text in
      select nullif(btrim(deleted_item.value #>> '{}'), '')
        from jsonb_array_elements(case when jsonb_typeof(v_deleted_ids -> 'catalog_options') = 'array' then v_deleted_ids -> 'catalog_options' else '[]'::jsonb end) as deleted_item(value)
    loop
      update public.catalog_options
         set deleted_at = v_now
       where id = v_candidate_text::uuid
         and deleted_at is null;
      get diagnostics v_write_count = row_count;
      v_deleted_catalog_options_count := v_deleted_catalog_options_count + v_write_count;
    end loop;

    for v_candidate_text in
      select nullif(btrim(deleted_item.value #>> '{}'), '')
        from jsonb_array_elements(case when jsonb_typeof(v_deleted_ids -> 'catalog_option_values') = 'array' then v_deleted_ids -> 'catalog_option_values' else '[]'::jsonb end) as deleted_item(value)
    loop
      update public.catalog_option_values
         set deleted_at = v_now
       where id = v_candidate_text::uuid
         and deleted_at is null;
      get diagnostics v_write_count = row_count;
      v_deleted_catalog_option_values_count := v_deleted_catalog_option_values_count + v_write_count;
    end loop;

    for v_candidate_text in
      select nullif(btrim(deleted_item.value #>> '{}'), '')
        from jsonb_array_elements(case when jsonb_typeof(v_deleted_ids -> 'catalog_variants') = 'array' then v_deleted_ids -> 'catalog_variants' else '[]'::jsonb end) as deleted_item(value)
    loop
      update public.catalog_variants
         set is_active = false,
             deleted_at = v_now
       where id = v_candidate_text::uuid
         and company_id = p_company_id
         and deleted_at is null;
      get diagnostics v_write_count = row_count;
      v_deleted_catalog_variants_count := v_deleted_catalog_variants_count + v_write_count;
    end loop;

    for v_candidate_text in
      select nullif(btrim(deleted_item.value #>> '{}'), '')
        from jsonb_array_elements(case when jsonb_typeof(v_deleted_ids -> 'catalog_variant_option_values') = 'array' then v_deleted_ids -> 'catalog_variant_option_values' else '[]'::jsonb end) as deleted_item(value)
    loop
      update public.catalog_variant_option_values
         set deleted_at = v_now
       where id = v_candidate_text::uuid
         and deleted_at is null;
      get diagnostics v_write_count = row_count;
      v_deleted_catalog_variant_option_values_count := v_deleted_catalog_variant_option_values_count + v_write_count;
    end loop;

    for v_candidate_text in
      select nullif(btrim(deleted_item.value #>> '{}'), '')
        from jsonb_array_elements(case when jsonb_typeof(v_deleted_ids -> 'catalog_stock_units') = 'array' then v_deleted_ids -> 'catalog_stock_units' else '[]'::jsonb end) as deleted_item(value)
    loop
      v_existing_stock_status := null;
      v_existing_stock_variant_id := null;

      select status, catalog_variant_id
        into v_existing_stock_status, v_existing_stock_variant_id
        from public.catalog_stock_units
       where id = v_candidate_text::uuid
         and company_id = p_company_id;

      update public.catalog_stock_units
         set deleted_at = v_now
       where id = v_candidate_text::uuid
         and company_id = p_company_id
         and deleted_at is null;
      get diagnostics v_write_count = row_count;
      v_deleted_catalog_stock_units_count := v_deleted_catalog_stock_units_count + v_write_count;

      if v_write_count > 0 then
        insert into public.catalog_stock_unit_events (
          company_id,
          catalog_stock_unit_id,
          catalog_variant_id,
          event_type,
          from_status,
          to_status,
          payload
        )
        values (
          p_company_id,
          v_candidate_text::uuid,
          v_existing_stock_variant_id,
          'delete',
          v_existing_stock_status,
          v_existing_stock_status,
          jsonb_build_object(
            'source', 'catalog_setup_save',
            'mode', 'edit',
            'deleted_id', v_candidate_text
          )
        );
        v_catalog_stock_unit_events_count := v_catalog_stock_unit_events_count + 1;
      end if;
    end loop;

    for v_candidate_text in
      select nullif(btrim(deleted_item.value #>> '{}'), '')
        from jsonb_array_elements(case when jsonb_typeof(v_deleted_ids -> 'products') = 'array' then v_deleted_ids -> 'products' else '[]'::jsonb end) as deleted_item(value)
    loop
      update public.products
         set is_active = false,
             deleted_at = v_now
       where id = v_candidate_text::uuid
         and company_id = p_company_id
         and deleted_at is null;
      get diagnostics v_write_count = row_count;
      v_deleted_products_count := v_deleted_products_count + v_write_count;
    end loop;

    for v_candidate_text in
      select nullif(btrim(deleted_item.value #>> '{}'), '')
        from jsonb_array_elements(case when jsonb_typeof(v_deleted_ids -> 'product_options') = 'array' then v_deleted_ids -> 'product_options' else '[]'::jsonb end) as deleted_item(value)
    loop
      update public.product_options
         set deleted_at = v_now
       where id = v_candidate_text::uuid
         and deleted_at is null;
      get diagnostics v_write_count = row_count;
      v_deleted_product_options_count := v_deleted_product_options_count + v_write_count;
    end loop;

    for v_candidate_text in
      select nullif(btrim(deleted_item.value #>> '{}'), '')
        from jsonb_array_elements(case when jsonb_typeof(v_deleted_ids -> 'product_option_values') = 'array' then v_deleted_ids -> 'product_option_values' else '[]'::jsonb end) as deleted_item(value)
    loop
      update public.product_option_values
         set deleted_at = v_now
       where id = v_candidate_text::uuid
         and deleted_at is null;
      get diagnostics v_write_count = row_count;
      v_deleted_product_option_values_count := v_deleted_product_option_values_count + v_write_count;
    end loop;

    for v_candidate_text in
      select nullif(btrim(deleted_item.value #>> '{}'), '')
        from jsonb_array_elements(case when jsonb_typeof(v_deleted_ids -> 'product_pricing_modifiers') = 'array' then v_deleted_ids -> 'product_pricing_modifiers' else '[]'::jsonb end) as deleted_item(value)
    loop
      update public.product_pricing_modifiers
         set deleted_at = v_now
       where id = v_candidate_text::uuid
         and deleted_at is null;
      get diagnostics v_write_count = row_count;
      v_deleted_product_pricing_modifiers_count := v_deleted_product_pricing_modifiers_count + v_write_count;
    end loop;

    for v_candidate_text in
      select nullif(btrim(deleted_item.value #>> '{}'), '')
        from jsonb_array_elements(case when jsonb_typeof(v_deleted_ids -> 'product_materials') = 'array' then v_deleted_ids -> 'product_materials' else '[]'::jsonb end) as deleted_item(value)
    loop
      update public.product_materials
         set deleted_at = v_now
       where id = v_candidate_text::uuid
         and deleted_at is null;
      get diagnostics v_write_count = row_count;
      v_deleted_product_materials_count := v_deleted_product_materials_count + v_write_count;
    end loop;

    for v_candidate_text in
      select nullif(btrim(deleted_item.value #>> '{}'), '')
        from jsonb_array_elements(case when jsonb_typeof(v_deleted_ids -> 'catalog_product_option_mappings') = 'array' then v_deleted_ids -> 'catalog_product_option_mappings' else '[]'::jsonb end) as deleted_item(value)
    loop
      update public.catalog_product_option_mappings
         set deleted_at = v_now
       where id = v_candidate_text::uuid
         and company_id = p_company_id
         and deleted_at is null;
      get diagnostics v_write_count = row_count;
      v_deleted_catalog_product_option_mappings_count := v_deleted_catalog_product_option_mappings_count + v_write_count;
    end loop;

    for v_candidate_text in
      select nullif(btrim(deleted_item.value #>> '{}'), '')
        from jsonb_array_elements(case when jsonb_typeof(v_deleted_ids -> 'product_bundle_items') = 'array' then v_deleted_ids -> 'product_bundle_items' else '[]'::jsonb end) as deleted_item(value)
    loop
      update public.product_bundle_items
         set deleted_at = v_now
       where id = v_candidate_text::uuid
         and company_id = p_company_id
         and deleted_at is null;
      get diagnostics v_write_count = row_count;
      v_deleted_product_bundle_items_count := v_deleted_product_bundle_items_count + v_write_count;
    end loop;

    v_response := jsonb_build_object(
      'ok', true,
      'mode', v_mode,
      'company_id', p_company_id,
      'idempotency_key', btrim(p_idempotency_key),
      'request_hash', v_request_hash,
      'warnings', v_warnings,
      'blockers', '[]'::jsonb,
      'id_map', v_id_map,
      'counts', jsonb_build_object(
        'catalog_items', v_catalog_items_count,
        'catalog_options', v_catalog_options_count,
        'catalog_option_values', v_catalog_option_values_count,
        'catalog_variants', v_catalog_variants_count,
        'catalog_variant_option_values', v_catalog_variant_option_values_count,
        'catalog_stock_units', v_catalog_stock_units_count,
        'products', v_products_count,
        'product_options', v_product_options_count,
        'product_option_values', v_product_option_values_count,
        'product_pricing_modifiers', v_product_pricing_modifiers_count,
        'product_materials', v_product_materials_count,
        'catalog_product_option_mappings', v_catalog_product_option_mappings_count,
        'product_bundle_items', v_product_bundle_items_count,
        'catalog_stock_unit_events', v_catalog_stock_unit_events_count
      ),
      'deleted_counts', jsonb_build_object(
        'catalog_items', v_deleted_catalog_items_count,
        'catalog_options', v_deleted_catalog_options_count,
        'catalog_option_values', v_deleted_catalog_option_values_count,
        'catalog_variants', v_deleted_catalog_variants_count,
        'catalog_variant_option_values', v_deleted_catalog_variant_option_values_count,
        'catalog_stock_units', v_deleted_catalog_stock_units_count,
        'products', v_deleted_products_count,
        'product_options', v_deleted_product_options_count,
        'product_option_values', v_deleted_product_option_values_count,
        'product_pricing_modifiers', v_deleted_product_pricing_modifiers_count,
        'product_materials', v_deleted_product_materials_count,
        'catalog_product_option_mappings', v_deleted_catalog_product_option_mappings_count,
        'product_bundle_items', v_deleted_product_bundle_items_count
      ),
      'validated_counts', jsonb_build_object(
        'catalog_options', jsonb_array_length(v_catalog_options),
        'variants', jsonb_array_length(v_variants),
        'stock_units', jsonb_array_length(v_stock_units),
        'stock_unit_events', jsonb_array_length(v_stock_unit_events),
        'products', jsonb_array_length(v_products),
        'product_materials', jsonb_array_length(v_product_materials)
      ),
      'saved_at', v_now
    );

    update public.catalog_setup_save_requests
       set status = 'succeeded',
           response = v_response,
           error = null,
           completed_at = v_now
     where id = v_request.id;

    return v_response;
  end if;

  v_client_id := nullif(btrim(p_payload #>> '{family,client_id}'), '');
  v_candidate_text := nullif(btrim(coalesce(p_payload #>> '{family,id}', '')), '');
  v_candidate_uuid := null;

  if v_candidate_text ~* v_uuid_pattern then
    v_candidate_uuid := v_candidate_text::uuid;
    if exists (select 1 from public.catalog_items where id = v_candidate_uuid) then
      v_candidate_uuid := null;
    end if;
  end if;

  if v_candidate_uuid is null and v_client_id ~* v_uuid_pattern then
    v_candidate_uuid := v_client_id::uuid;
    if exists (select 1 from public.catalog_items where id = v_candidate_uuid) then
      v_candidate_uuid := null;
    end if;
  end if;

  v_family_id := coalesce(v_candidate_uuid, gen_random_uuid());

  if v_client_id is not null then
    v_id_map := jsonb_set(v_id_map, array[v_client_id], to_jsonb(v_family_id::text), true);
  end if;

  for v_option_doc in
    select value
      from jsonb_array_elements(v_catalog_options) as option_item(value)
  loop
    v_client_id := nullif(btrim(v_option_doc->>'client_id'), '');
    v_candidate_text := nullif(btrim(coalesce(v_option_doc->>'id', '')), '');
    v_candidate_uuid := null;

    if v_candidate_text ~* v_uuid_pattern then
      v_candidate_uuid := v_candidate_text::uuid;
      if exists (select 1 from public.catalog_options where id = v_candidate_uuid) then
        v_candidate_uuid := null;
      end if;
    end if;

    if v_candidate_uuid is null and v_client_id ~* v_uuid_pattern then
      v_candidate_uuid := v_client_id::uuid;
      if exists (select 1 from public.catalog_options where id = v_candidate_uuid) then
        v_candidate_uuid := null;
      end if;
    end if;

    if v_client_id is not null then
      v_id_map := jsonb_set(v_id_map, array[v_client_id], to_jsonb(coalesce(v_candidate_uuid, gen_random_uuid())::text), true);
    end if;

    for v_value_doc in
      select value
        from jsonb_array_elements(
          case
            when jsonb_typeof(v_option_doc -> 'values') = 'array' then v_option_doc -> 'values'
            else '[]'::jsonb
          end
        ) as value_item(value)
    loop
      v_client_id := nullif(btrim(v_value_doc->>'client_id'), '');
      v_candidate_text := nullif(btrim(coalesce(v_value_doc->>'id', '')), '');
      v_candidate_uuid := null;

      if v_candidate_text ~* v_uuid_pattern then
        v_candidate_uuid := v_candidate_text::uuid;
        if exists (select 1 from public.catalog_option_values where id = v_candidate_uuid) then
          v_candidate_uuid := null;
        end if;
      end if;

      if v_candidate_uuid is null and v_client_id ~* v_uuid_pattern then
        v_candidate_uuid := v_client_id::uuid;
        if exists (select 1 from public.catalog_option_values where id = v_candidate_uuid) then
          v_candidate_uuid := null;
        end if;
      end if;

      if v_client_id is not null then
        v_id_map := jsonb_set(v_id_map, array[v_client_id], to_jsonb(coalesce(v_candidate_uuid, gen_random_uuid())::text), true);
      end if;
    end loop;
  end loop;

  for v_variant_doc in
    select value
      from jsonb_array_elements(v_variants) as variant_item(value)
  loop
    v_client_id := nullif(btrim(v_variant_doc->>'client_id'), '');
    v_candidate_text := nullif(btrim(coalesce(v_variant_doc->>'id', '')), '');
    v_candidate_uuid := null;

    if v_candidate_text ~* v_uuid_pattern then
      v_candidate_uuid := v_candidate_text::uuid;
      if exists (select 1 from public.catalog_variants where id = v_candidate_uuid) then
        v_candidate_uuid := null;
      end if;
    end if;

    if v_candidate_uuid is null and v_client_id ~* v_uuid_pattern then
      v_candidate_uuid := v_client_id::uuid;
      if exists (select 1 from public.catalog_variants where id = v_candidate_uuid) then
        v_candidate_uuid := null;
      end if;
    end if;

    if v_client_id is not null then
      v_id_map := jsonb_set(v_id_map, array[v_client_id], to_jsonb(coalesce(v_candidate_uuid, gen_random_uuid())::text), true);
    end if;
  end loop;

  for v_stock_doc in
    select value
      from jsonb_array_elements(v_stock_units) as stock_item(value)
  loop
    v_client_id := nullif(btrim(v_stock_doc->>'client_id'), '');
    v_candidate_text := nullif(btrim(coalesce(v_stock_doc->>'id', '')), '');
    v_candidate_uuid := null;

    if v_candidate_text ~* v_uuid_pattern then
      v_candidate_uuid := v_candidate_text::uuid;
      if exists (select 1 from public.catalog_stock_units where id = v_candidate_uuid) then
        v_candidate_uuid := null;
      end if;
    end if;

    if v_candidate_uuid is null and v_client_id ~* v_uuid_pattern then
      v_candidate_uuid := v_client_id::uuid;
      if exists (select 1 from public.catalog_stock_units where id = v_candidate_uuid) then
        v_candidate_uuid := null;
      end if;
    end if;

    if v_client_id is not null then
      v_id_map := jsonb_set(v_id_map, array[v_client_id], to_jsonb(coalesce(v_candidate_uuid, gen_random_uuid())::text), true);
    end if;
  end loop;

  for v_product_doc in
    select value
      from jsonb_array_elements(v_products) as product_item(value)
  loop
    v_client_id := nullif(btrim(v_product_doc->>'client_id'), '');
    v_candidate_text := nullif(btrim(coalesce(v_product_doc->>'id', '')), '');
    v_candidate_uuid := null;

    if v_candidate_text ~* v_uuid_pattern then
      v_candidate_uuid := v_candidate_text::uuid;
      if exists (
        select 1
          from public.products product_row
         where product_row.id = v_candidate_uuid
           and product_row.company_id = p_company_id
      ) then
        null;
      elsif exists (select 1 from public.products where id = v_candidate_uuid) then
        v_candidate_uuid := null;
      end if;
    end if;

    if v_candidate_uuid is null and v_client_id ~* v_uuid_pattern then
      v_candidate_uuid := v_client_id::uuid;
      if exists (
        select 1
          from public.products product_row
         where product_row.id = v_candidate_uuid
           and product_row.company_id = p_company_id
      ) then
        null;
      elsif exists (select 1 from public.products where id = v_candidate_uuid) then
        v_candidate_uuid := null;
      end if;
    end if;

    if v_client_id is not null then
      v_id_map := jsonb_set(v_id_map, array[v_client_id], to_jsonb(coalesce(v_candidate_uuid, gen_random_uuid())::text), true);
    end if;

    for v_option_doc in
      select value
        from jsonb_array_elements(
          case
            when jsonb_typeof(v_product_doc -> 'options') = 'array' then v_product_doc -> 'options'
            else '[]'::jsonb
          end
        ) as option_item(value)
    loop
      v_client_id := nullif(btrim(v_option_doc->>'client_id'), '');
      v_candidate_text := nullif(btrim(coalesce(v_option_doc->>'id', '')), '');
      v_candidate_uuid := null;

      if v_candidate_text ~* v_uuid_pattern then
        v_candidate_uuid := v_candidate_text::uuid;
        if exists (
          select 1
            from public.product_options option_row
            join public.products product_row on product_row.id = option_row.product_id
           where option_row.id = v_candidate_uuid
             and product_row.company_id = p_company_id
        ) then
          null;
        elsif exists (select 1 from public.product_options where id = v_candidate_uuid) then
          v_candidate_uuid := null;
        end if;
      end if;

      if v_candidate_uuid is null and v_client_id ~* v_uuid_pattern then
        v_candidate_uuid := v_client_id::uuid;
        if exists (
          select 1
            from public.product_options option_row
            join public.products product_row on product_row.id = option_row.product_id
           where option_row.id = v_candidate_uuid
             and product_row.company_id = p_company_id
        ) then
          null;
        elsif exists (select 1 from public.product_options where id = v_candidate_uuid) then
          v_candidate_uuid := null;
        end if;
      end if;

      if v_client_id is not null then
        v_id_map := jsonb_set(v_id_map, array[v_client_id], to_jsonb(coalesce(v_candidate_uuid, gen_random_uuid())::text), true);
      end if;

      for v_value_doc in
        select value
          from jsonb_array_elements(
            case
              when jsonb_typeof(v_option_doc -> 'values') = 'array' then v_option_doc -> 'values'
              else '[]'::jsonb
            end
          ) as value_item(value)
      loop
        v_client_id := nullif(btrim(v_value_doc->>'client_id'), '');
        v_candidate_text := nullif(btrim(coalesce(v_value_doc->>'id', '')), '');
        v_candidate_uuid := null;

        if v_candidate_text ~* v_uuid_pattern then
          v_candidate_uuid := v_candidate_text::uuid;
          if exists (
            select 1
              from public.product_option_values value_row
              join public.product_options option_row on option_row.id = value_row.option_id
              join public.products product_row on product_row.id = option_row.product_id
             where value_row.id = v_candidate_uuid
               and product_row.company_id = p_company_id
          ) then
            null;
          elsif exists (select 1 from public.product_option_values where id = v_candidate_uuid) then
            v_candidate_uuid := null;
          end if;
        end if;

        if v_candidate_uuid is null and v_client_id ~* v_uuid_pattern then
          v_candidate_uuid := v_client_id::uuid;
          if exists (
            select 1
              from public.product_option_values value_row
              join public.product_options option_row on option_row.id = value_row.option_id
              join public.products product_row on product_row.id = option_row.product_id
             where value_row.id = v_candidate_uuid
               and product_row.company_id = p_company_id
          ) then
            null;
          elsif exists (select 1 from public.product_option_values where id = v_candidate_uuid) then
            v_candidate_uuid := null;
          end if;
        end if;

        if v_client_id is not null then
          v_id_map := jsonb_set(v_id_map, array[v_client_id], to_jsonb(coalesce(v_candidate_uuid, gen_random_uuid())::text), true);
        end if;
      end loop;
    end loop;

    for v_modifier_doc in
      select value
        from jsonb_array_elements(
          case
            when jsonb_typeof(v_product_doc -> 'pricing_modifiers') = 'array' then v_product_doc -> 'pricing_modifiers'
            else '[]'::jsonb
          end
        ) as modifier_item(value)
    loop
      v_client_id := nullif(btrim(v_modifier_doc->>'client_id'), '');
      v_candidate_text := nullif(btrim(coalesce(v_modifier_doc->>'id', '')), '');
      v_candidate_uuid := null;

      if v_candidate_text ~* v_uuid_pattern then
        v_candidate_uuid := v_candidate_text::uuid;
        if exists (
          select 1
            from public.product_pricing_modifiers modifier_row
            join public.products product_row on product_row.id = modifier_row.product_id
           where modifier_row.id = v_candidate_uuid
             and product_row.company_id = p_company_id
        ) then
          null;
        elsif exists (select 1 from public.product_pricing_modifiers where id = v_candidate_uuid) then
          v_candidate_uuid := null;
        end if;
      end if;

      if v_candidate_uuid is null and v_client_id ~* v_uuid_pattern then
        v_candidate_uuid := v_client_id::uuid;
        if exists (
          select 1
            from public.product_pricing_modifiers modifier_row
            join public.products product_row on product_row.id = modifier_row.product_id
           where modifier_row.id = v_candidate_uuid
             and product_row.company_id = p_company_id
        ) then
          null;
        elsif exists (select 1 from public.product_pricing_modifiers where id = v_candidate_uuid) then
          v_candidate_uuid := null;
        end if;
      end if;

      if v_client_id is not null then
        v_id_map := jsonb_set(v_id_map, array[v_client_id], to_jsonb(coalesce(v_candidate_uuid, gen_random_uuid())::text), true);
      end if;
    end loop;

    for v_material_doc in
      select material_value
        from (
          select value as material_value
            from jsonb_array_elements(
              case
                when jsonb_typeof(v_product_doc -> 'product_materials') = 'array' then v_product_doc -> 'product_materials'
                else '[]'::jsonb
              end
            ) as material_item(value)
          union all
          select value as material_value
            from jsonb_array_elements(
              case
                when jsonb_typeof(v_product_doc -> 'materials') = 'array' then v_product_doc -> 'materials'
                else '[]'::jsonb
              end
            ) as material_item(value)
        ) material_items
    loop
      v_client_id := nullif(btrim(v_material_doc->>'client_id'), '');
      v_candidate_text := nullif(btrim(coalesce(v_material_doc->>'id', '')), '');
      v_candidate_uuid := null;

      if v_candidate_text ~* v_uuid_pattern then
        v_candidate_uuid := v_candidate_text::uuid;
        if exists (
          select 1
            from public.product_materials material_row
            join public.products product_row on product_row.id = material_row.product_id
           where material_row.id = v_candidate_uuid
             and product_row.company_id = p_company_id
        ) then
          null;
        elsif exists (select 1 from public.product_materials where id = v_candidate_uuid) then
          v_candidate_uuid := null;
        end if;
      end if;

      if v_candidate_uuid is null and v_client_id ~* v_uuid_pattern then
        v_candidate_uuid := v_client_id::uuid;
        if exists (
          select 1
            from public.product_materials material_row
            join public.products product_row on product_row.id = material_row.product_id
           where material_row.id = v_candidate_uuid
             and product_row.company_id = p_company_id
        ) then
          null;
        elsif exists (select 1 from public.product_materials where id = v_candidate_uuid) then
          v_candidate_uuid := null;
        end if;
      end if;

      if v_client_id is not null then
        v_id_map := jsonb_set(v_id_map, array[v_client_id], to_jsonb(coalesce(v_candidate_uuid, gen_random_uuid())::text), true);
      end if;
    end loop;

    for v_mapping_doc in
      select value
        from jsonb_array_elements(
          case
            when jsonb_typeof(v_product_doc -> 'catalog_option_mappings') = 'array' then v_product_doc -> 'catalog_option_mappings'
            else '[]'::jsonb
          end
        ) as mapping_item(value)
    loop
      v_client_id := nullif(btrim(v_mapping_doc->>'client_id'), '');
      v_candidate_text := nullif(btrim(coalesce(v_mapping_doc->>'id', '')), '');
      v_candidate_uuid := null;

      if v_candidate_text ~* v_uuid_pattern then
        v_candidate_uuid := v_candidate_text::uuid;
        if exists (
          select 1
            from public.catalog_product_option_mappings mapping_row
           where mapping_row.id = v_candidate_uuid
             and mapping_row.company_id = p_company_id
        ) then
          null;
        elsif exists (select 1 from public.catalog_product_option_mappings where id = v_candidate_uuid) then
          v_candidate_uuid := null;
        end if;
      end if;

      if v_candidate_uuid is null and v_client_id ~* v_uuid_pattern then
        v_candidate_uuid := v_client_id::uuid;
        if exists (
          select 1
            from public.catalog_product_option_mappings mapping_row
           where mapping_row.id = v_candidate_uuid
             and mapping_row.company_id = p_company_id
        ) then
          null;
        elsif exists (select 1 from public.catalog_product_option_mappings where id = v_candidate_uuid) then
          v_candidate_uuid := null;
        end if;
      end if;

      if v_client_id is not null then
        v_id_map := jsonb_set(v_id_map, array[v_client_id], to_jsonb(coalesce(v_candidate_uuid, gen_random_uuid())::text), true);
      end if;
    end loop;

    for v_bundle_doc in
      select value
        from jsonb_array_elements(
          case
            when jsonb_typeof(v_product_doc -> 'bundle_items') = 'array' then v_product_doc -> 'bundle_items'
            else '[]'::jsonb
          end
        ) as bundle_item(value)
    loop
      v_client_id := nullif(btrim(v_bundle_doc->>'client_id'), '');
      v_candidate_text := nullif(btrim(coalesce(v_bundle_doc->>'id', '')), '');
      v_candidate_uuid := null;

      if v_candidate_text ~* v_uuid_pattern then
        v_candidate_uuid := v_candidate_text::uuid;
        if exists (
          select 1
            from public.product_bundle_items bundle_row
           where bundle_row.id = v_candidate_uuid
             and bundle_row.company_id = p_company_id
        ) then
          null;
        elsif exists (select 1 from public.product_bundle_items where id = v_candidate_uuid) then
          v_candidate_uuid := null;
        end if;
      end if;

      if v_candidate_uuid is null and v_client_id ~* v_uuid_pattern then
        v_candidate_uuid := v_client_id::uuid;
        if exists (
          select 1
            from public.product_bundle_items bundle_row
           where bundle_row.id = v_candidate_uuid
             and bundle_row.company_id = p_company_id
        ) then
          null;
        elsif exists (select 1 from public.product_bundle_items where id = v_candidate_uuid) then
          v_candidate_uuid := null;
        end if;
      end if;

      if v_client_id is not null then
        v_id_map := jsonb_set(v_id_map, array[v_client_id], to_jsonb(coalesce(v_candidate_uuid, gen_random_uuid())::text), true);
      end if;
    end loop;
  end loop;

  for v_material_doc in
    select value
      from jsonb_array_elements(v_product_materials) as material_item(value)
  loop
    v_client_id := nullif(btrim(v_material_doc->>'client_id'), '');
    v_candidate_text := nullif(btrim(coalesce(v_material_doc->>'id', '')), '');
    v_candidate_uuid := null;

    if v_candidate_text ~* v_uuid_pattern then
      v_candidate_uuid := v_candidate_text::uuid;
      if exists (
        select 1
          from public.product_materials material_row
          join public.products product_row on product_row.id = material_row.product_id
         where material_row.id = v_candidate_uuid
           and product_row.company_id = p_company_id
      ) then
        null;
      elsif exists (select 1 from public.product_materials where id = v_candidate_uuid) then
        v_candidate_uuid := null;
      end if;
    end if;

    if v_candidate_uuid is null and v_client_id ~* v_uuid_pattern then
      v_candidate_uuid := v_client_id::uuid;
      if exists (
        select 1
          from public.product_materials material_row
          join public.products product_row on product_row.id = material_row.product_id
         where material_row.id = v_candidate_uuid
           and product_row.company_id = p_company_id
      ) then
        null;
      elsif exists (select 1 from public.product_materials where id = v_candidate_uuid) then
        v_candidate_uuid := null;
      end if;
    end if;

    if v_client_id is not null then
      v_id_map := jsonb_set(v_id_map, array[v_client_id], to_jsonb(coalesce(v_candidate_uuid, gen_random_uuid())::text), true);
    end if;
  end loop;

  insert into public.catalog_items (
    id,
    company_id,
    category_id,
    name,
    description,
    image_url,
    default_warning_threshold,
    default_critical_threshold,
    default_unit_id,
    notes
  )
  values (
    v_family_id,
    p_company_id,
    case
      when (p_payload #>> '{family,category_id}') ~* v_uuid_pattern then (p_payload #>> '{family,category_id}')::uuid
      else null
    end,
    btrim(p_payload #>> '{family,name}'),
    nullif(btrim(coalesce(p_payload #>> '{family,description}', '')), ''),
    nullif(btrim(coalesce(p_payload #>> '{family,image_url}', '')), ''),
    case
      when coalesce(p_payload #>> '{family,default_warning_threshold}', '') ~ '^-?[0-9]+(\.[0-9]+)?$' then (p_payload #>> '{family,default_warning_threshold}')::double precision
      else null
    end,
    case
      when coalesce(p_payload #>> '{family,default_critical_threshold}', '') ~ '^-?[0-9]+(\.[0-9]+)?$' then (p_payload #>> '{family,default_critical_threshold}')::double precision
      else null
    end,
    case
      when coalesce(p_payload #>> '{family,unit_id}', p_payload #>> '{family,default_unit_id}', '') ~* v_uuid_pattern then coalesce(p_payload #>> '{family,unit_id}', p_payload #>> '{family,default_unit_id}')::uuid
      else null
    end,
    nullif(btrim(coalesce(p_payload #>> '{family,notes}', '')), '')
  );
  v_catalog_items_count := v_catalog_items_count + 1;

  for v_option_doc in
    select value
      from jsonb_array_elements(v_catalog_options) as option_item(value)
  loop
    v_client_id := nullif(btrim(v_option_doc->>'client_id'), '');
    v_catalog_option_id := case
      when v_client_id is not null and v_id_map ? v_client_id then (v_id_map ->> v_client_id)::uuid
      else gen_random_uuid()
    end;

    insert into public.catalog_options (
      id,
      catalog_item_id,
      name,
      sort_order
    )
    values (
      v_catalog_option_id,
      v_family_id,
      btrim(v_option_doc->>'name'),
      case
        when coalesce(v_option_doc->>'sort_order', '') ~ '^-?[0-9]+$' then (v_option_doc->>'sort_order')::integer
        else 0
      end
    );
    v_catalog_options_count := v_catalog_options_count + 1;

    for v_value_doc in
      select value
        from jsonb_array_elements(
          case
            when jsonb_typeof(v_option_doc -> 'values') = 'array' then v_option_doc -> 'values'
            else '[]'::jsonb
          end
        ) as value_item(value)
    loop
      v_client_id := nullif(btrim(v_value_doc->>'client_id'), '');
      v_catalog_option_value_id := case
        when v_client_id is not null and v_id_map ? v_client_id then (v_id_map ->> v_client_id)::uuid
        else gen_random_uuid()
      end;

      insert into public.catalog_option_values (
        id,
        option_id,
        value,
        sort_order
      )
      values (
        v_catalog_option_value_id,
        v_catalog_option_id,
        btrim(coalesce(v_value_doc->>'label', v_value_doc->>'value')),
        case
          when coalesce(v_value_doc->>'sort_order', '') ~ '^-?[0-9]+$' then (v_value_doc->>'sort_order')::integer
          else 0
        end
      );
      v_catalog_option_values_count := v_catalog_option_values_count + 1;
    end loop;
  end loop;

  for v_variant_doc in
    select value
      from jsonb_array_elements(v_variants) as variant_item(value)
  loop
    v_client_id := nullif(btrim(v_variant_doc->>'client_id'), '');
    v_catalog_variant_id := case
      when v_client_id is not null and v_id_map ? v_client_id then (v_id_map ->> v_client_id)::uuid
      else gen_random_uuid()
    end;

    insert into public.catalog_variants (
      id,
      company_id,
      catalog_item_id,
      sku,
      quantity,
      price_override,
      warning_threshold,
      critical_threshold,
      unit_id,
      is_active
    )
    values (
      v_catalog_variant_id,
      p_company_id,
      v_family_id,
      nullif(btrim(coalesce(v_variant_doc->>'sku', '')), ''),
      case
        when coalesce(v_variant_doc->>'quantity', '') ~ '^-?[0-9]+(\.[0-9]+)?$' then (v_variant_doc->>'quantity')::double precision
        else 0
      end,
      case
        when coalesce(v_variant_doc->>'price', v_variant_doc->>'price_override', '') ~ '^-?[0-9]+(\.[0-9]+)?$' then coalesce(v_variant_doc->>'price', v_variant_doc->>'price_override')::numeric
        else null
      end,
      case
        when coalesce(v_variant_doc->>'warning_threshold', '') ~ '^-?[0-9]+(\.[0-9]+)?$' then (v_variant_doc->>'warning_threshold')::double precision
        else null
      end,
      case
        when coalesce(v_variant_doc->>'critical_threshold', '') ~ '^-?[0-9]+(\.[0-9]+)?$' then (v_variant_doc->>'critical_threshold')::double precision
        else null
      end,
      case
        when coalesce(v_variant_doc->>'unit_id', '') ~* v_uuid_pattern then (v_variant_doc->>'unit_id')::uuid
        else null
      end,
      lower(coalesce(v_variant_doc->>'excluded', 'false')) not in ('true', 't', '1', 'yes', 'on')
    );
    v_catalog_variants_count := v_catalog_variants_count + 1;

    for v_value_doc in
      select value
        from jsonb_array_elements(
          case
            when jsonb_typeof(v_variant_doc -> 'option_value_client_ids') = 'array' then v_variant_doc -> 'option_value_client_ids'
            else '[]'::jsonb
          end
        ) as value_item(value)
    loop
      v_ref_text := nullif(btrim(v_value_doc #>> '{}'), '');
      v_ref_uuid := null;

      if v_ref_text is not null and v_id_map ? v_ref_text then
        v_ref_uuid := (v_id_map ->> v_ref_text)::uuid;
      elsif v_ref_text ~* v_uuid_pattern then
        v_ref_uuid := v_ref_text::uuid;
      end if;

      insert into public.catalog_variant_option_values (
        variant_id,
        option_value_id
      )
      values (
        v_catalog_variant_id,
        v_ref_uuid
      );
      v_catalog_variant_option_values_count := v_catalog_variant_option_values_count + 1;
    end loop;

    for v_value_doc in
      select value
        from jsonb_array_elements(
          case
            when jsonb_typeof(v_variant_doc -> 'option_value_ids') = 'array' then v_variant_doc -> 'option_value_ids'
            else '[]'::jsonb
          end
        ) as value_item(value)
    loop
      v_ref_text := nullif(btrim(v_value_doc #>> '{}'), '');
      v_ref_uuid := case
        when v_ref_text ~* v_uuid_pattern then v_ref_text::uuid
        else null
      end;

      insert into public.catalog_variant_option_values (
        variant_id,
        option_value_id
      )
      values (
        v_catalog_variant_id,
        v_ref_uuid
      );
      v_catalog_variant_option_values_count := v_catalog_variant_option_values_count + 1;
    end loop;
  end loop;

  for v_stock_doc in
    select value
      from jsonb_array_elements(v_stock_units) as stock_item(value)
  loop
    v_client_id := nullif(btrim(v_stock_doc->>'client_id'), '');
    v_catalog_stock_unit_id := case
      when v_client_id is not null and v_id_map ? v_client_id then (v_id_map ->> v_client_id)::uuid
      else gen_random_uuid()
    end;
    v_ref_uuid := null;
    v_ref_text := nullif(btrim(coalesce(v_stock_doc->>'variant_client_id', '')), '');

    if v_ref_text is not null and v_id_map ? v_ref_text then
      v_ref_uuid := (v_id_map ->> v_ref_text)::uuid;
    else
      v_ref_text := nullif(btrim(coalesce(v_stock_doc->>'catalog_variant_id', v_stock_doc->>'variant_id', '')), '');
      if v_ref_text ~* v_uuid_pattern then
        v_ref_uuid := v_ref_text::uuid;
      end if;
    end if;

    insert into public.catalog_stock_units (
      id,
      company_id,
      catalog_variant_id,
      unit_kind,
      label,
      lot_code,
      width_value,
      width_unit,
      original_length_value,
      remaining_length_value,
      length_unit,
      quantity_value,
      location,
      status,
      source_order_item_id,
      notes
    )
    values (
      v_catalog_stock_unit_id,
      p_company_id,
      v_ref_uuid,
      coalesce(nullif(btrim(v_stock_doc->>'unit_kind'), ''), 'each'),
      nullif(btrim(coalesce(v_stock_doc->>'label', '')), ''),
      nullif(btrim(coalesce(v_stock_doc->>'lot_code', '')), ''),
      case
        when coalesce(v_stock_doc->>'width_value', '') ~ '^-?[0-9]+(\.[0-9]+)?$' then (v_stock_doc->>'width_value')::numeric
        else null
      end,
      nullif(btrim(coalesce(v_stock_doc->>'width_unit', '')), ''),
      case
        when coalesce(v_stock_doc->>'original_length_value', '') ~ '^-?[0-9]+(\.[0-9]+)?$' then (v_stock_doc->>'original_length_value')::numeric
        else null
      end,
      case
        when coalesce(v_stock_doc->>'remaining_length_value', '') ~ '^-?[0-9]+(\.[0-9]+)?$' then (v_stock_doc->>'remaining_length_value')::numeric
        else null
      end,
      nullif(btrim(coalesce(v_stock_doc->>'length_unit', '')), ''),
      coalesce(
        case
          when coalesce(v_stock_doc->>'quantity_value', '') ~ '^-?[0-9]+(\.[0-9]+)?$' then (v_stock_doc->>'quantity_value')::numeric
          else null
        end,
        1
      ),
      nullif(btrim(coalesce(v_stock_doc->>'location', '')), ''),
      coalesce(nullif(btrim(v_stock_doc->>'status'), ''), 'full'),
      case
        when coalesce(v_stock_doc->>'source_order_item_id', '') ~* v_uuid_pattern then (v_stock_doc->>'source_order_item_id')::uuid
        else null
      end,
      nullif(btrim(coalesce(v_stock_doc->>'notes', '')), '')
    );
    v_catalog_stock_units_count := v_catalog_stock_units_count + 1;

    if not exists (
      select 1
        from jsonb_array_elements(v_stock_unit_events) as explicit_event(value)
       where nullif(btrim(coalesce(
               explicit_event.value->>'stock_unit_client_id',
               explicit_event.value->>'catalog_stock_unit_client_id',
               ''
             )), '') = v_client_id
          or nullif(btrim(coalesce(
               explicit_event.value->>'catalog_stock_unit_id',
               explicit_event.value->>'stock_unit_id',
               ''
             )), '') = v_catalog_stock_unit_id::text
    ) then
      insert into public.catalog_stock_unit_events (
        company_id,
        catalog_stock_unit_id,
        catalog_variant_id,
        event_type,
        to_status,
        quantity_delta,
        remaining_length_delta,
        payload
      )
      values (
        p_company_id,
        v_catalog_stock_unit_id,
        v_ref_uuid,
        'receive',
        coalesce(nullif(btrim(v_stock_doc->>'status'), ''), 'full'),
        coalesce(
          case
            when coalesce(v_stock_doc->>'quantity_value', '') ~ '^-?[0-9]+(\.[0-9]+)?$' then (v_stock_doc->>'quantity_value')::numeric
            else null
          end,
          1
        ),
        case
          when coalesce(v_stock_doc->>'remaining_length_value', '') ~ '^-?[0-9]+(\.[0-9]+)?$' then (v_stock_doc->>'remaining_length_value')::numeric
          else null
        end,
        jsonb_build_object(
          'source', 'catalog_setup_save',
          'stock_unit_client_id', nullif(btrim(coalesce(v_stock_doc->>'client_id', '')), '')
        )
      );
      v_catalog_stock_unit_events_count := v_catalog_stock_unit_events_count + 1;
    end if;

    if coalesce(nullif(btrim(v_stock_doc->>'unit_kind'), ''), 'each') = 'offcut'
       and not exists (
         select 1
           from jsonb_array_elements(v_stock_unit_events) as explicit_event(value)
          where nullif(btrim(coalesce(
                  explicit_event.value->>'stock_unit_client_id',
                  explicit_event.value->>'catalog_stock_unit_client_id',
                  ''
                )), '') = v_client_id
             or nullif(btrim(coalesce(
                  explicit_event.value->>'catalog_stock_unit_id',
                  explicit_event.value->>'stock_unit_id',
                  ''
                )), '') = v_catalog_stock_unit_id::text
       ) then
      v_related_stock_unit_id := null;
      v_ref_text := nullif(btrim(coalesce(
        v_stock_doc->>'related_catalog_stock_unit_client_id',
        v_stock_doc->>'source_stock_unit_client_id',
        ''
      )), '');

      if v_ref_text is not null and v_id_map ? v_ref_text then
        v_related_stock_unit_id := (v_id_map ->> v_ref_text)::uuid;
      else
        v_ref_text := nullif(btrim(coalesce(
          v_stock_doc->>'related_catalog_stock_unit_id',
          v_stock_doc->>'source_stock_unit_id',
          ''
        )), '');
        if v_ref_text ~* v_uuid_pattern then
          v_related_stock_unit_id := v_ref_text::uuid;
        end if;
      end if;

      insert into public.catalog_stock_unit_events (
        company_id,
        catalog_stock_unit_id,
        catalog_variant_id,
        related_catalog_stock_unit_id,
        event_type,
        to_status,
        quantity_delta,
        remaining_length_delta,
        payload
      )
      values (
        p_company_id,
        v_catalog_stock_unit_id,
        v_ref_uuid,
        v_related_stock_unit_id,
        'offcut_create',
        coalesce(nullif(btrim(v_stock_doc->>'status'), ''), 'full'),
        coalesce(
          case
            when coalesce(v_stock_doc->>'quantity_value', '') ~ '^-?[0-9]+(\.[0-9]+)?$' then (v_stock_doc->>'quantity_value')::numeric
            else null
          end,
          1
        ),
        case
          when coalesce(v_stock_doc->>'remaining_length_value', '') ~ '^-?[0-9]+(\.[0-9]+)?$' then (v_stock_doc->>'remaining_length_value')::numeric
          else null
        end,
        jsonb_build_object(
          'source', 'catalog_setup_save',
          'stock_unit_client_id', nullif(btrim(coalesce(v_stock_doc->>'client_id', '')), ''),
          'related_catalog_stock_unit_client_id', nullif(btrim(coalesce(
            v_stock_doc->>'related_catalog_stock_unit_client_id',
            v_stock_doc->>'source_stock_unit_client_id',
            ''
          )), '')
        )
      );
      v_catalog_stock_unit_events_count := v_catalog_stock_unit_events_count + 1;
    end if;
  end loop;

  for v_stock_event_doc in
    select value
      from jsonb_array_elements(v_stock_unit_events) as stock_event_item(value)
  loop
    v_event_type := nullif(btrim(coalesce(v_stock_event_doc->>'event_type', '')), '');
    v_catalog_stock_unit_id := null;
    v_client_id := nullif(btrim(coalesce(
      v_stock_event_doc->>'stock_unit_client_id',
      v_stock_event_doc->>'catalog_stock_unit_client_id',
      ''
    )), '');

    if v_client_id is not null and v_id_map ? v_client_id then
      v_catalog_stock_unit_id := (v_id_map ->> v_client_id)::uuid;
    else
      v_candidate_text := nullif(btrim(coalesce(
        v_stock_event_doc->>'catalog_stock_unit_id',
        v_stock_event_doc->>'stock_unit_id',
        ''
      )), '');
      if v_candidate_text ~* v_uuid_pattern then
        v_catalog_stock_unit_id := v_candidate_text::uuid;
      end if;
    end if;

    if v_catalog_stock_unit_id is null then
      continue;
    end if;

    v_ref_uuid := null;
    v_ref_text := nullif(btrim(coalesce(v_stock_event_doc->>'variant_client_id', '')), '');
    if v_ref_text is not null and v_id_map ? v_ref_text then
      v_ref_uuid := (v_id_map ->> v_ref_text)::uuid;
    else
      v_ref_text := nullif(btrim(coalesce(
        v_stock_event_doc->>'catalog_variant_id',
        v_stock_event_doc->>'variant_id',
        ''
      )), '');
      if v_ref_text ~* v_uuid_pattern then
        v_ref_uuid := v_ref_text::uuid;
      end if;
    end if;

    if v_ref_uuid is null then
      select catalog_variant_id
        into v_ref_uuid
        from public.catalog_stock_units
       where id = v_catalog_stock_unit_id
         and company_id = p_company_id;
    end if;

    v_related_stock_unit_id := null;
    v_ref_text := nullif(btrim(coalesce(
      v_stock_event_doc->>'related_catalog_stock_unit_client_id',
      v_stock_event_doc->>'source_stock_unit_client_id',
      ''
    )), '');

    if v_ref_text is not null and v_id_map ? v_ref_text then
      v_related_stock_unit_id := (v_id_map ->> v_ref_text)::uuid;
    else
      v_ref_text := nullif(btrim(coalesce(
        v_stock_event_doc->>'related_catalog_stock_unit_id',
        v_stock_event_doc->>'source_stock_unit_id',
        ''
      )), '');
      if v_ref_text ~* v_uuid_pattern then
        v_related_stock_unit_id := v_ref_text::uuid;
      end if;
    end if;

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
      marker,
      notes
    )
    values (
      p_company_id,
      v_catalog_stock_unit_id,
      v_ref_uuid,
      v_related_stock_unit_id,
      v_event_type,
      nullif(btrim(coalesce(v_stock_event_doc->>'from_status', '')), ''),
      nullif(btrim(coalesce(v_stock_event_doc->>'to_status', '')), ''),
      case
        when coalesce(v_stock_event_doc->>'quantity_delta', '') ~ '^-?[0-9]+(\.[0-9]+)?$' then (v_stock_event_doc->>'quantity_delta')::numeric
        else null
      end,
      case
        when coalesce(v_stock_event_doc->>'remaining_length_delta', '') ~ '^-?[0-9]+(\.[0-9]+)?$' then (v_stock_event_doc->>'remaining_length_delta')::numeric
        else null
      end,
      coalesce(
        case
          when jsonb_typeof(v_stock_event_doc -> 'payload') = 'object' then v_stock_event_doc -> 'payload'
          else '{}'::jsonb
        end,
        '{}'::jsonb
      ) || jsonb_build_object(
        'source', 'catalog_setup_save',
        'mode', 'create',
        'stock_unit_client_id', v_client_id,
        'event_id', nullif(btrim(coalesce(v_stock_event_doc->>'event_id', '')), '')
      ),
      nullif(btrim(coalesce(v_stock_event_doc->>'marker', '')), ''),
      nullif(btrim(coalesce(v_stock_event_doc->>'notes', '')), '')
    );
    v_catalog_stock_unit_events_count := v_catalog_stock_unit_events_count + 1;
  end loop;

  for v_product_doc in
    select value
      from jsonb_array_elements(v_products) as product_item(value)
  loop
    v_client_id := nullif(btrim(v_product_doc->>'client_id'), '');
    v_product_id := case
      when v_client_id is not null and v_id_map ? v_client_id then (v_id_map ->> v_client_id)::uuid
      else gen_random_uuid()
    end;
    v_ref_uuid := null;
    v_ref_text := nullif(btrim(coalesce(v_product_doc->>'linked_catalog_item_client_id', '')), '');

    if v_ref_text is not null and v_id_map ? v_ref_text then
      v_ref_uuid := (v_id_map ->> v_ref_text)::uuid;
    else
      v_ref_text := nullif(btrim(coalesce(v_product_doc->>'linked_catalog_item_id', v_product_doc->>'catalog_item_id', '')), '');
      if v_ref_text ~* v_uuid_pattern then
        v_ref_uuid := v_ref_text::uuid;
      end if;
    end if;
    v_product_catalog_item_id := v_ref_uuid;

    insert into public.products (
      id,
      company_id,
      name,
      description,
      default_price,
      unit,
      category,
      is_taxable,
      is_active,
      type,
      unit_id,
      kind,
      sku,
      is_favorite,
      minimum_charge,
      minimum_quantity,
      show_bom_on_estimate,
      show_in_storefront,
      tiered_pricing,
      base_price,
      pricing_unit,
      category_id,
      thumbnail_url,
      linked_catalog_item_id,
      bundle_pricing_mode
    )
    values (
      v_product_id,
      p_company_id,
      btrim(v_product_doc->>'name'),
      nullif(btrim(coalesce(v_product_doc->>'description', '')), ''),
      coalesce(
        case
          when coalesce(v_product_doc->>'default_price', v_product_doc->>'base_price', v_product_doc->>'price', '') ~ '^-?[0-9]+(\.[0-9]+)?$' then coalesce(v_product_doc->>'default_price', v_product_doc->>'base_price', v_product_doc->>'price')::numeric
          else null
        end,
        0
      ),
      coalesce(nullif(btrim(v_product_doc->>'unit'), ''), nullif(btrim(v_product_doc->>'pricing_unit'), ''), 'each'),
      nullif(btrim(coalesce(v_product_doc->>'category', '')), ''),
      lower(coalesce(v_product_doc->>'is_taxable', 'true')) not in ('false', 'f', '0', 'no', 'off'),
      lower(coalesce(v_product_doc->>'is_active', 'true')) not in ('false', 'f', '0', 'no', 'off'),
      upper(coalesce(nullif(btrim(v_product_doc->>'type'), ''), case when coalesce(v_product_doc->>'kind', 'material') = 'material' then 'MATERIAL' else 'OTHER' end)),
      case
        when coalesce(v_product_doc->>'unit_id', '') ~* v_uuid_pattern then (v_product_doc->>'unit_id')::uuid
        else null
      end,
      coalesce(nullif(btrim(v_product_doc->>'kind'), ''), 'material'),
      nullif(btrim(coalesce(v_product_doc->>'sku', '')), ''),
      lower(coalesce(v_product_doc->>'is_favorite', 'false')) in ('true', 't', '1', 'yes', 'on'),
      case
        when coalesce(v_product_doc->>'minimum_charge', '') ~ '^-?[0-9]+(\.[0-9]+)?$' then (v_product_doc->>'minimum_charge')::numeric
        else null
      end,
      case
        when coalesce(v_product_doc->>'minimum_quantity', '') ~ '^-?[0-9]+(\.[0-9]+)?$' then (v_product_doc->>'minimum_quantity')::numeric
        else null
      end,
      lower(coalesce(v_product_doc->>'show_bom_on_estimate', 'false')) in ('true', 't', '1', 'yes', 'on'),
      lower(coalesce(v_product_doc->>'show_in_storefront', 'false')) in ('true', 't', '1', 'yes', 'on'),
      case
        when jsonb_typeof(v_product_doc -> 'tiered_pricing') = 'object' then v_product_doc -> 'tiered_pricing'
        else '{}'::jsonb
      end,
      coalesce(
        case
          when coalesce(v_product_doc->>'base_price', v_product_doc->>'default_price', v_product_doc->>'price', '') ~ '^-?[0-9]+(\.[0-9]+)?$' then coalesce(v_product_doc->>'base_price', v_product_doc->>'default_price', v_product_doc->>'price')::numeric
          else null
        end,
        0
      ),
      coalesce(nullif(btrim(v_product_doc->>'pricing_unit'), ''), 'each'),
      case
        when coalesce(v_product_doc->>'category_id', '') ~* v_uuid_pattern then (v_product_doc->>'category_id')::uuid
        else null
      end,
      nullif(btrim(coalesce(v_product_doc->>'thumbnail_url', '')), ''),
      v_ref_uuid,
      nullif(btrim(coalesce(v_product_doc->>'bundle_pricing_mode', '')), '')
    )
    on conflict (id) do update
      set name = excluded.name,
          description = excluded.description,
          default_price = excluded.default_price,
          unit = excluded.unit,
          category = excluded.category,
          is_taxable = excluded.is_taxable,
          is_active = excluded.is_active,
          type = excluded.type,
          unit_id = excluded.unit_id,
          kind = excluded.kind,
          sku = excluded.sku,
          is_favorite = excluded.is_favorite,
          minimum_charge = excluded.minimum_charge,
          minimum_quantity = excluded.minimum_quantity,
          show_bom_on_estimate = excluded.show_bom_on_estimate,
          show_in_storefront = excluded.show_in_storefront,
          tiered_pricing = excluded.tiered_pricing,
          base_price = excluded.base_price,
          pricing_unit = excluded.pricing_unit,
          category_id = excluded.category_id,
          thumbnail_url = excluded.thumbnail_url,
          linked_catalog_item_id = excluded.linked_catalog_item_id,
          bundle_pricing_mode = excluded.bundle_pricing_mode,
          deleted_at = null
      where public.products.company_id = p_company_id;
    v_products_count := v_products_count + 1;

    for v_option_doc in
      select value
        from jsonb_array_elements(
          case
            when jsonb_typeof(v_product_doc -> 'options') = 'array' then v_product_doc -> 'options'
            else '[]'::jsonb
          end
        ) as option_item(value)
    loop
      v_client_id := nullif(btrim(v_option_doc->>'client_id'), '');
      v_product_option_id := case
        when v_client_id is not null and v_id_map ? v_client_id then (v_id_map ->> v_client_id)::uuid
        else gen_random_uuid()
      end;

      insert into public.product_options (
        id,
        product_id,
        name,
        kind,
        affects_price,
        affects_recipe,
        required,
        default_value,
        option_default_source,
        sort_order,
        deleted_at
      )
      values (
        v_product_option_id,
        v_product_id,
        btrim(v_option_doc->>'name'),
        v_option_doc->>'kind',
        lower(coalesce(v_option_doc->>'affects_price', 'false')) in ('true', 't', '1', 'yes', 'on'),
        lower(coalesce(v_option_doc->>'affects_recipe', 'false')) in ('true', 't', '1', 'yes', 'on'),
        lower(coalesce(v_option_doc->>'required', 'true')) not in ('false', 'f', '0', 'no', 'off'),
        nullif(btrim(coalesce(v_option_doc->>'default_value', '')), ''),
        nullif(btrim(coalesce(v_option_doc->>'option_default_source', '')), ''),
        case
          when coalesce(v_option_doc->>'sort_order', '') ~ '^-?[0-9]+$' then (v_option_doc->>'sort_order')::integer
          else 0
        end,
        null
      )
      on conflict (id) do update
        set product_id = excluded.product_id,
            name = excluded.name,
            kind = excluded.kind,
            affects_price = excluded.affects_price,
            affects_recipe = excluded.affects_recipe,
            required = excluded.required,
            default_value = excluded.default_value,
            option_default_source = excluded.option_default_source,
            sort_order = excluded.sort_order,
            deleted_at = null;
      v_product_options_count := v_product_options_count + 1;

      for v_value_doc in
        select value
          from jsonb_array_elements(
            case
              when jsonb_typeof(v_option_doc -> 'values') = 'array' then v_option_doc -> 'values'
              else '[]'::jsonb
            end
          ) as value_item(value)
      loop
        v_client_id := nullif(btrim(v_value_doc->>'client_id'), '');
        v_product_option_value_id := case
          when v_client_id is not null and v_id_map ? v_client_id then (v_id_map ->> v_client_id)::uuid
          else gen_random_uuid()
        end;

        insert into public.product_option_values (
          id,
          option_id,
          value,
          sort_order,
          deleted_at
        )
        values (
          v_product_option_value_id,
          v_product_option_id,
          btrim(coalesce(v_value_doc->>'label', v_value_doc->>'value')),
          case
            when coalesce(v_value_doc->>'sort_order', '') ~ '^-?[0-9]+$' then (v_value_doc->>'sort_order')::integer
            else 0
          end,
          null
        )
        on conflict (id) do update
          set option_id = excluded.option_id,
              value = excluded.value,
              sort_order = excluded.sort_order,
              deleted_at = null;
        v_product_option_values_count := v_product_option_values_count + 1;
      end loop;
    end loop;

    for v_modifier_doc in
      select value
        from jsonb_array_elements(
          case
            when jsonb_typeof(v_product_doc -> 'pricing_modifiers') = 'array' then v_product_doc -> 'pricing_modifiers'
            else '[]'::jsonb
          end
        ) as modifier_item(value)
    loop
      v_client_id := nullif(btrim(v_modifier_doc->>'client_id'), '');
      v_candidate_uuid := case
        when v_client_id is not null and v_id_map ? v_client_id then (v_id_map ->> v_client_id)::uuid
        else gen_random_uuid()
      end;
      v_ref_uuid := null;
      v_ref_text := nullif(btrim(coalesce(v_modifier_doc->>'option_client_id', '')), '');

      if v_ref_text is not null and v_id_map ? v_ref_text then
        v_ref_uuid := (v_id_map ->> v_ref_text)::uuid;
      else
        v_ref_text := nullif(btrim(coalesce(v_modifier_doc->>'option_id', '')), '');
        if v_ref_text ~* v_uuid_pattern then
          v_ref_uuid := v_ref_text::uuid;
        end if;
      end if;

      v_product_option_value_id := null;
      v_ref_text := nullif(btrim(coalesce(v_modifier_doc->>'option_value_client_id', v_modifier_doc->>'trigger_value_client_id', '')), '');

      if v_ref_text is not null and v_id_map ? v_ref_text then
        v_product_option_value_id := (v_id_map ->> v_ref_text)::uuid;
      else
        v_ref_text := nullif(btrim(coalesce(v_modifier_doc->>'trigger_value_id', v_modifier_doc->>'option_value_id', '')), '');
        if v_ref_text ~* v_uuid_pattern then
          v_product_option_value_id := v_ref_text::uuid;
        end if;
      end if;

      insert into public.product_pricing_modifiers (
        id,
        product_id,
        option_id,
        trigger_value_id,
        trigger_int_min,
        trigger_int_max,
        modifier_kind,
        amount,
        deleted_at
      )
      values (
        v_candidate_uuid,
        v_product_id,
        v_ref_uuid,
        v_product_option_value_id,
        case
          when coalesce(v_modifier_doc->>'trigger_int_min', '') ~ '^-?[0-9]+$' then (v_modifier_doc->>'trigger_int_min')::integer
          else null
        end,
        case
          when coalesce(v_modifier_doc->>'trigger_int_max', '') ~ '^-?[0-9]+$' then (v_modifier_doc->>'trigger_int_max')::integer
          else null
        end,
        v_modifier_doc->>'modifier_kind',
        coalesce(
          case
            when coalesce(v_modifier_doc->>'amount', '') ~ '^-?[0-9]+(\.[0-9]+)?$' then (v_modifier_doc->>'amount')::numeric
            else null
          end,
          0
        ),
        null
      )
      on conflict (id) do update
        set product_id = excluded.product_id,
            option_id = excluded.option_id,
            trigger_value_id = excluded.trigger_value_id,
            trigger_int_min = excluded.trigger_int_min,
            trigger_int_max = excluded.trigger_int_max,
            modifier_kind = excluded.modifier_kind,
            amount = excluded.amount,
            deleted_at = null;
      v_product_pricing_modifiers_count := v_product_pricing_modifiers_count + 1;
    end loop;

    for v_material_doc in
      select material_value
        from (
          select value as material_value
            from jsonb_array_elements(
              case
                when jsonb_typeof(v_product_doc -> 'product_materials') = 'array' then v_product_doc -> 'product_materials'
                else '[]'::jsonb
              end
            ) as material_item(value)
          union all
          select value as material_value
            from jsonb_array_elements(
              case
                when jsonb_typeof(v_product_doc -> 'materials') = 'array' then v_product_doc -> 'materials'
                else '[]'::jsonb
              end
            ) as material_item(value)
        ) material_items
    loop
      v_client_id := nullif(btrim(v_material_doc->>'client_id'), '');
      v_candidate_uuid := case
        when v_client_id is not null and v_id_map ? v_client_id then (v_id_map ->> v_client_id)::uuid
        else gen_random_uuid()
      end;
      v_catalog_variant_id := null;
      v_ref_text := nullif(btrim(coalesce(v_material_doc->>'catalog_variant_client_id', v_material_doc->>'variant_client_id', '')), '');

      if v_ref_text is not null and v_id_map ? v_ref_text then
        v_catalog_variant_id := (v_id_map ->> v_ref_text)::uuid;
      else
        v_ref_text := nullif(btrim(coalesce(v_material_doc->>'catalog_variant_id', v_material_doc->>'variant_id', '')), '');
        if v_ref_text ~* v_uuid_pattern then
          v_catalog_variant_id := v_ref_text::uuid;
        end if;
      end if;

      v_ref_uuid := null;
      v_ref_text := nullif(btrim(coalesce(v_material_doc->>'catalog_item_client_id', v_material_doc->>'family_client_id', '')), '');

      if v_ref_text is not null and v_id_map ? v_ref_text then
        v_ref_uuid := (v_id_map ->> v_ref_text)::uuid;
      else
        v_ref_text := nullif(btrim(coalesce(v_material_doc->>'catalog_item_id', '')), '');
        if v_ref_text ~* v_uuid_pattern then
          v_ref_uuid := v_ref_text::uuid;
        elsif v_family_id is not null and v_catalog_variant_id is null then
          v_ref_uuid := v_family_id;
        end if;
      end if;

      v_product_option_id := null;
      v_ref_text := nullif(btrim(coalesce(v_material_doc->>'scaled_by_option_client_id', '')), '');

      if v_ref_text is not null and v_id_map ? v_ref_text then
        v_product_option_id := (v_id_map ->> v_ref_text)::uuid;
      else
        v_ref_text := nullif(btrim(coalesce(v_material_doc->>'scaled_by_option_id', '')), '');
        if v_ref_text ~* v_uuid_pattern then
          v_product_option_id := v_ref_text::uuid;
        end if;
      end if;

      insert into public.product_materials (
        id,
        product_id,
        inventory_item_id,
        quantity_per_unit,
        notes,
        catalog_variant_id,
        catalog_item_id,
        variant_selector,
        scaled_by_option_id,
        unit_id,
        deleted_at
      )
      values (
        v_candidate_uuid,
        v_product_id,
        case
          when coalesce(v_material_doc->>'inventory_item_id', '') ~* v_uuid_pattern then (v_material_doc->>'inventory_item_id')::uuid
          else null
        end,
        coalesce(
          case
            when coalesce(v_material_doc->>'quantity_per_unit', v_material_doc->>'quantity', '') ~ '^-?[0-9]+(\.[0-9]+)?$' then coalesce(v_material_doc->>'quantity_per_unit', v_material_doc->>'quantity')::double precision
            else null
          end,
          1
        ),
        nullif(btrim(coalesce(v_material_doc->>'notes', '')), ''),
        v_catalog_variant_id,
        v_ref_uuid,
        case
          when jsonb_typeof(v_material_doc -> 'variant_selector') = 'object' then v_material_doc -> 'variant_selector'
          else null
        end,
        v_product_option_id,
        case
          when coalesce(v_material_doc->>'unit_id', '') ~* v_uuid_pattern then (v_material_doc->>'unit_id')::uuid
          else null
        end,
        null
      )
      on conflict (id) do update
        set product_id = excluded.product_id,
            inventory_item_id = excluded.inventory_item_id,
            quantity_per_unit = excluded.quantity_per_unit,
            notes = excluded.notes,
            catalog_variant_id = excluded.catalog_variant_id,
            catalog_item_id = excluded.catalog_item_id,
            variant_selector = excluded.variant_selector,
            scaled_by_option_id = excluded.scaled_by_option_id,
            unit_id = excluded.unit_id,
            deleted_at = null;
      v_product_materials_count := v_product_materials_count + 1;
    end loop;

    for v_mapping_doc in
      select value
        from jsonb_array_elements(
          case
            when jsonb_typeof(v_product_doc -> 'catalog_option_mappings') = 'array' then v_product_doc -> 'catalog_option_mappings'
            else '[]'::jsonb
          end
        ) as mapping_item(value)
    loop
      v_client_id := nullif(btrim(v_mapping_doc->>'client_id'), '');
      v_candidate_uuid := case
        when v_client_id is not null and v_id_map ? v_client_id then (v_id_map ->> v_client_id)::uuid
        else gen_random_uuid()
      end;
      v_catalog_option_id := null;
      v_ref_text := nullif(btrim(coalesce(v_mapping_doc->>'catalog_option_client_id', '')), '');

      if v_ref_text is not null and v_id_map ? v_ref_text then
        v_catalog_option_id := (v_id_map ->> v_ref_text)::uuid;
      else
        v_ref_text := nullif(btrim(coalesce(v_mapping_doc->>'catalog_option_id', '')), '');
        if v_ref_text ~* v_uuid_pattern then
          v_catalog_option_id := v_ref_text::uuid;
        end if;
      end if;

      v_product_option_id := null;
      v_ref_text := nullif(btrim(coalesce(v_mapping_doc->>'product_option_client_id', '')), '');

      if v_ref_text is not null and v_id_map ? v_ref_text then
        v_product_option_id := (v_id_map ->> v_ref_text)::uuid;
      else
        v_ref_text := nullif(btrim(coalesce(v_mapping_doc->>'product_option_id', '')), '');
        if v_ref_text ~* v_uuid_pattern then
          v_product_option_id := v_ref_text::uuid;
        end if;
      end if;

      v_catalog_option_value_id := null;
      v_ref_text := nullif(btrim(coalesce(v_mapping_doc->>'catalog_option_value_client_id', '')), '');

      if v_ref_text is not null and v_id_map ? v_ref_text then
        v_catalog_option_value_id := (v_id_map ->> v_ref_text)::uuid;
      else
        v_ref_text := nullif(btrim(coalesce(v_mapping_doc->>'catalog_option_value_id', '')), '');
        if v_ref_text ~* v_uuid_pattern then
          v_catalog_option_value_id := v_ref_text::uuid;
        end if;
      end if;

      v_product_option_value_id := null;
      v_ref_text := nullif(btrim(coalesce(v_mapping_doc->>'product_option_value_client_id', '')), '');

      if v_ref_text is not null and v_id_map ? v_ref_text then
        v_product_option_value_id := (v_id_map ->> v_ref_text)::uuid;
      else
        v_ref_text := nullif(btrim(coalesce(v_mapping_doc->>'product_option_value_id', '')), '');
        if v_ref_text ~* v_uuid_pattern then
          v_product_option_value_id := v_ref_text::uuid;
        end if;
      end if;

      insert into public.catalog_product_option_mappings (
        id,
        company_id,
        product_id,
        catalog_item_id,
        catalog_option_id,
        product_option_id,
        catalog_option_value_id,
        product_option_value_id,
        mapping_kind,
        deleted_at
      )
      values (
        v_candidate_uuid,
        p_company_id,
        v_product_id,
        coalesce(
          case
            when coalesce(v_mapping_doc->>'catalog_item_id', '') ~* v_uuid_pattern then (v_mapping_doc->>'catalog_item_id')::uuid
            else null
          end,
          v_family_id,
          v_product_catalog_item_id
        ),
        v_catalog_option_id,
        v_product_option_id,
        v_catalog_option_value_id,
        v_product_option_value_id,
        v_mapping_doc->>'mapping_kind',
        null
      )
      on conflict (id) do update
        set product_id = excluded.product_id,
            catalog_item_id = excluded.catalog_item_id,
            catalog_option_id = excluded.catalog_option_id,
            product_option_id = excluded.product_option_id,
            catalog_option_value_id = excluded.catalog_option_value_id,
            product_option_value_id = excluded.product_option_value_id,
            mapping_kind = excluded.mapping_kind,
            deleted_at = null;
      v_catalog_product_option_mappings_count := v_catalog_product_option_mappings_count + 1;
    end loop;

    for v_bundle_doc in
      select value
        from jsonb_array_elements(
          case
            when jsonb_typeof(v_product_doc -> 'bundle_items') = 'array' then v_product_doc -> 'bundle_items'
            else '[]'::jsonb
          end
        ) as bundle_item(value)
    loop
      v_client_id := nullif(btrim(v_bundle_doc->>'client_id'), '');
      v_candidate_uuid := case
        when v_client_id is not null and v_id_map ? v_client_id then (v_id_map ->> v_client_id)::uuid
        else gen_random_uuid()
      end;
      v_ref_uuid := null;
      v_ref_text := nullif(btrim(coalesce(v_bundle_doc->>'child_product_client_id', v_bundle_doc->>'product_client_id', '')), '');

      if v_ref_text is not null and v_id_map ? v_ref_text then
        v_ref_uuid := (v_id_map ->> v_ref_text)::uuid;
      else
        v_ref_text := nullif(btrim(coalesce(v_bundle_doc->>'child_product_id', v_bundle_doc->>'product_id', '')), '');
        if v_ref_text ~* v_uuid_pattern then
          v_ref_uuid := v_ref_text::uuid;
        end if;
      end if;

      insert into public.product_bundle_items (
        id,
        company_id,
        bundle_product_id,
        child_product_id,
        quantity,
        display_order,
        relationship_kind,
        suggestion_reason,
        compatibility_selector,
        deleted_at
      )
      values (
        v_candidate_uuid,
        p_company_id,
        v_product_id,
        v_ref_uuid,
        coalesce(
          case
            when coalesce(v_bundle_doc->>'quantity', '') ~ '^-?[0-9]+(\.[0-9]+)?$' then (v_bundle_doc->>'quantity')::numeric
            else null
          end,
          1
        ),
        case
          when coalesce(v_bundle_doc->>'display_order', v_bundle_doc->>'sort_order', '') ~ '^-?[0-9]+$' then coalesce(v_bundle_doc->>'display_order', v_bundle_doc->>'sort_order')::integer
          else 0
        end,
        coalesce(nullif(btrim(v_bundle_doc->>'relationship_kind'), ''), 'required'),
        nullif(btrim(coalesce(v_bundle_doc->>'suggestion_reason', '')), ''),
        case
          when jsonb_typeof(v_bundle_doc -> 'compatibility_selector') = 'object' then v_bundle_doc -> 'compatibility_selector'
          else null
        end,
        null
      )
      on conflict (id) do update
        set bundle_product_id = excluded.bundle_product_id,
            child_product_id = excluded.child_product_id,
            quantity = excluded.quantity,
            display_order = excluded.display_order,
            relationship_kind = excluded.relationship_kind,
            suggestion_reason = excluded.suggestion_reason,
            compatibility_selector = excluded.compatibility_selector,
            deleted_at = null;
      v_product_bundle_items_count := v_product_bundle_items_count + 1;
    end loop;
  end loop;

  for v_material_doc in
    select value
      from jsonb_array_elements(v_product_materials) as material_item(value)
  loop
    v_client_id := nullif(btrim(v_material_doc->>'client_id'), '');
    v_candidate_uuid := case
      when v_client_id is not null and v_id_map ? v_client_id then (v_id_map ->> v_client_id)::uuid
      else gen_random_uuid()
    end;
    v_product_id := null;
    v_ref_text := nullif(btrim(coalesce(v_material_doc->>'product_client_id', '')), '');

    if v_ref_text is not null and v_id_map ? v_ref_text then
      v_product_id := (v_id_map ->> v_ref_text)::uuid;
    else
      v_ref_text := nullif(btrim(coalesce(v_material_doc->>'product_id', '')), '');
      if v_ref_text ~* v_uuid_pattern then
        v_product_id := v_ref_text::uuid;
      end if;
    end if;

    v_catalog_variant_id := null;
    v_ref_text := nullif(btrim(coalesce(v_material_doc->>'catalog_variant_client_id', v_material_doc->>'variant_client_id', '')), '');

    if v_ref_text is not null and v_id_map ? v_ref_text then
      v_catalog_variant_id := (v_id_map ->> v_ref_text)::uuid;
    else
      v_ref_text := nullif(btrim(coalesce(v_material_doc->>'catalog_variant_id', v_material_doc->>'variant_id', '')), '');
      if v_ref_text ~* v_uuid_pattern then
        v_catalog_variant_id := v_ref_text::uuid;
      end if;
    end if;

    v_ref_uuid := null;
    v_ref_text := nullif(btrim(coalesce(v_material_doc->>'catalog_item_client_id', v_material_doc->>'family_client_id', '')), '');

    if v_ref_text is not null and v_id_map ? v_ref_text then
      v_ref_uuid := (v_id_map ->> v_ref_text)::uuid;
    else
      v_ref_text := nullif(btrim(coalesce(v_material_doc->>'catalog_item_id', '')), '');
      if v_ref_text ~* v_uuid_pattern then
        v_ref_uuid := v_ref_text::uuid;
      elsif v_family_id is not null and v_catalog_variant_id is null then
        v_ref_uuid := v_family_id;
      end if;
    end if;

    v_product_option_id := null;
    v_ref_text := nullif(btrim(coalesce(v_material_doc->>'scaled_by_option_client_id', '')), '');

    if v_ref_text is not null and v_id_map ? v_ref_text then
      v_product_option_id := (v_id_map ->> v_ref_text)::uuid;
    else
      v_ref_text := nullif(btrim(coalesce(v_material_doc->>'scaled_by_option_id', '')), '');
      if v_ref_text ~* v_uuid_pattern then
        v_product_option_id := v_ref_text::uuid;
      end if;
    end if;

    insert into public.product_materials (
      id,
      product_id,
      inventory_item_id,
      quantity_per_unit,
      notes,
      catalog_variant_id,
      catalog_item_id,
      variant_selector,
      scaled_by_option_id,
      unit_id,
      deleted_at
    )
    values (
      v_candidate_uuid,
      v_product_id,
      case
        when coalesce(v_material_doc->>'inventory_item_id', '') ~* v_uuid_pattern then (v_material_doc->>'inventory_item_id')::uuid
        else null
      end,
      coalesce(
        case
          when coalesce(v_material_doc->>'quantity_per_unit', v_material_doc->>'quantity', '') ~ '^-?[0-9]+(\.[0-9]+)?$' then coalesce(v_material_doc->>'quantity_per_unit', v_material_doc->>'quantity')::double precision
          else null
        end,
        1
      ),
      nullif(btrim(coalesce(v_material_doc->>'notes', '')), ''),
      v_catalog_variant_id,
      v_ref_uuid,
      case
        when jsonb_typeof(v_material_doc -> 'variant_selector') = 'object' then v_material_doc -> 'variant_selector'
        else null
      end,
      v_product_option_id,
      case
        when coalesce(v_material_doc->>'unit_id', '') ~* v_uuid_pattern then (v_material_doc->>'unit_id')::uuid
        else null
      end,
      null
    )
    on conflict (id) do update
      set product_id = excluded.product_id,
          inventory_item_id = excluded.inventory_item_id,
          quantity_per_unit = excluded.quantity_per_unit,
          notes = excluded.notes,
          catalog_variant_id = excluded.catalog_variant_id,
          catalog_item_id = excluded.catalog_item_id,
          variant_selector = excluded.variant_selector,
          scaled_by_option_id = excluded.scaled_by_option_id,
          unit_id = excluded.unit_id,
          deleted_at = null;
    v_product_materials_count := v_product_materials_count + 1;
  end loop;

  v_response := jsonb_build_object(
    'ok', true,
    'mode', v_mode,
    'company_id', p_company_id,
    'idempotency_key', btrim(p_idempotency_key),
    'request_hash', v_request_hash,
    'warnings', v_warnings,
    'blockers', '[]'::jsonb,
    'id_map', v_id_map,
    'counts', jsonb_build_object(
      'catalog_items', v_catalog_items_count,
      'catalog_options', v_catalog_options_count,
      'catalog_option_values', v_catalog_option_values_count,
      'catalog_variants', v_catalog_variants_count,
      'catalog_variant_option_values', v_catalog_variant_option_values_count,
      'catalog_stock_units', v_catalog_stock_units_count,
      'products', v_products_count,
      'product_options', v_product_options_count,
      'product_option_values', v_product_option_values_count,
      'product_pricing_modifiers', v_product_pricing_modifiers_count,
      'product_materials', v_product_materials_count,
      'catalog_product_option_mappings', v_catalog_product_option_mappings_count,
      'product_bundle_items', v_product_bundle_items_count,
      'catalog_stock_unit_events', v_catalog_stock_unit_events_count
    ),
    'validated_counts', jsonb_build_object(
      'catalog_options', jsonb_array_length(v_catalog_options),
      'variants', jsonb_array_length(v_variants),
      'stock_units', jsonb_array_length(v_stock_units),
      'stock_unit_events', jsonb_array_length(v_stock_unit_events),
      'products', jsonb_array_length(v_products),
      'product_materials', jsonb_array_length(v_product_materials)
    ),
    'saved_at', v_now
  );

  update public.catalog_setup_save_requests
     set status = 'succeeded',
         response = v_response,
         error = null,
         completed_at = v_now
   where id = v_request.id;

  return v_response;
exception
  when others then
    update public.catalog_setup_save_requests
       set status = 'failed',
           response = null,
           error = jsonb_build_object(
             'ok', false,
             'warnings', '[]'::jsonb,
             'blockers', jsonb_build_array(jsonb_build_object(
               'code', 'catalog_setup_save_internal_error',
               'path', '$',
               'message', sqlerrm
             ))
           ),
           completed_at = now()
     where id = v_request.id;
    raise;
end;
$$;

revoke all on function public.catalog_setup_save(uuid, text, jsonb) from public;
revoke all on function public.catalog_setup_save(uuid, text, jsonb) from anon;
grant execute on function public.catalog_setup_save(uuid, text, jsonb) to authenticated;

commit;
