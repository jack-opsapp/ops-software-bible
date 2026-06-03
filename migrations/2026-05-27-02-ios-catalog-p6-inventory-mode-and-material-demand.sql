-- iOS Catalog Phase 6 schema foundation: inventory mode, projected material
-- demand, material snapshots, task material allocations, and keyed
-- notification resolution. Review-gate draft only. Do not apply without
-- explicit PM approval.

begin;

create schema if not exists private;

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

create table if not exists public.company_inventory_settings (
  company_id uuid primary key references public.companies(id) on delete cascade,
  inventory_mode text not null default 'off',
  enabled_at timestamptz,
  disabled_at timestamptz,
  updated_by uuid references public.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint company_inventory_settings_mode_check
    check (inventory_mode in ('off', 'tracked')),
  constraint company_inventory_settings_enabled_at_check
    check (
      (inventory_mode = 'tracked' and enabled_at is not null)
      or inventory_mode = 'off'
    )
);

drop trigger if exists trg_company_inventory_settings_updated_at
  on public.company_inventory_settings;
create trigger trg_company_inventory_settings_updated_at
  before update on public.company_inventory_settings
  for each row
  execute function public.fn_set_updated_at();

create table if not exists public.project_material_demands (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  project_id uuid not null references public.projects(id) on delete cascade,
  task_id uuid references public.project_tasks(id) on delete set null,
  estimate_id uuid references public.estimates(id) on delete set null,
  line_item_id uuid references public.line_items(id) on delete set null,
  product_id uuid references public.products(id) on delete set null,
  product_material_id uuid references public.product_materials(id) on delete set null,
  catalog_variant_id uuid references public.catalog_variants(id) on delete set null,
  unit_id uuid references public.catalog_units(id) on delete set null,
  demand_key text not null,
  source text not null default 'estimate_acceptance',
  status text not null default 'projected',
  required_quantity numeric not null,
  available_quantity_at_booking numeric,
  projected_overrun_quantity numeric not null default 0,
  resolver_payload jsonb not null default '{}'::jsonb,
  warning_payload jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  constraint project_material_demands_status_check
    check (status in ('projected', 'warning', 'allocated', 'consumed', 'released', 'superseded')),
  constraint project_material_demands_required_quantity_check
    check (required_quantity >= 0),
  constraint project_material_demands_available_quantity_check
    check (available_quantity_at_booking is null or available_quantity_at_booking >= 0),
  constraint project_material_demands_overrun_check
    check (projected_overrun_quantity >= 0),
  constraint project_material_demands_resolver_payload_object_check
    check (jsonb_typeof(resolver_payload) = 'object'),
  constraint project_material_demands_warning_payload_object_check
    check (jsonb_typeof(warning_payload) = 'object')
);

create unique index if not exists project_material_demands_active_key
  on public.project_material_demands(company_id, demand_key)
  where deleted_at is null;

create index if not exists project_material_demands_project_status_idx
  on public.project_material_demands(company_id, project_id, status)
  where deleted_at is null;

create index if not exists project_material_demands_task_status_idx
  on public.project_material_demands(company_id, task_id, status)
  where deleted_at is null and task_id is not null;

create index if not exists project_material_demands_estimate_idx
  on public.project_material_demands(company_id, estimate_id)
  where deleted_at is null and estimate_id is not null;

create index if not exists project_material_demands_line_item_idx
  on public.project_material_demands(company_id, line_item_id)
  where deleted_at is null and line_item_id is not null;

create index if not exists project_material_demands_variant_status_idx
  on public.project_material_demands(company_id, catalog_variant_id, status)
  where deleted_at is null and catalog_variant_id is not null;

create table if not exists public.project_material_snapshots (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  project_id uuid not null references public.projects(id) on delete cascade,
  task_id uuid references public.project_tasks(id) on delete set null,
  estimate_id uuid references public.estimates(id) on delete set null,
  snapshot_kind text not null,
  created_by uuid references public.users(id) on delete set null,
  notes text,
  payload jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  constraint project_material_snapshots_kind_check
    check (snapshot_kind in (
      'booking_projection',
      'inventory_mode_released',
      'crew_adjustment',
      'task_completion_consumption',
      'release'
    )),
  constraint project_material_snapshots_payload_object_check
    check (jsonb_typeof(payload) = 'object')
);

create index if not exists project_material_snapshots_project_idx
  on public.project_material_snapshots(company_id, project_id, created_at desc);

create index if not exists project_material_snapshots_task_idx
  on public.project_material_snapshots(company_id, task_id, created_at desc)
  where task_id is not null;

create index if not exists project_material_snapshots_estimate_idx
  on public.project_material_snapshots(company_id, estimate_id, created_at desc)
  where estimate_id is not null;

create table if not exists public.project_material_snapshot_items (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  snapshot_id uuid not null references public.project_material_snapshots(id) on delete cascade,
  demand_id uuid references public.project_material_demands(id) on delete set null,
  task_material_id uuid references public.task_materials(id) on delete set null,
  allocation_id uuid,
  inventory_deduction_id uuid references public.inventory_deductions(id) on delete set null,
  catalog_variant_id uuid references public.catalog_variants(id) on delete set null,
  catalog_stock_unit_id uuid references public.catalog_stock_units(id) on delete set null,
  source_event_id uuid references public.catalog_stock_unit_events(id) on delete set null,
  unit_id uuid references public.catalog_units(id) on delete set null,
  quantity numeric not null default 0,
  projected_overrun_quantity numeric not null default 0,
  stock_unit_snapshot jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  constraint project_material_snapshot_items_quantity_check
    check (quantity >= 0),
  constraint project_material_snapshot_items_overrun_check
    check (projected_overrun_quantity >= 0),
  constraint project_material_snapshot_items_stock_snapshot_object_check
    check (jsonb_typeof(stock_unit_snapshot) = 'object')
);

create index if not exists project_material_snapshot_items_snapshot_idx
  on public.project_material_snapshot_items(company_id, snapshot_id);

create index if not exists project_material_snapshot_items_demand_idx
  on public.project_material_snapshot_items(company_id, demand_id)
  where demand_id is not null;

create index if not exists project_material_snapshot_items_stock_unit_idx
  on public.project_material_snapshot_items(company_id, catalog_stock_unit_id)
  where catalog_stock_unit_id is not null;

create index if not exists project_material_snapshot_items_allocation_idx
  on public.project_material_snapshot_items(company_id, allocation_id)
  where allocation_id is not null;

create table if not exists public.task_material_allocations (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  task_material_id uuid references public.task_materials(id) on delete set null,
  demand_id uuid references public.project_material_demands(id) on delete set null,
  catalog_variant_id uuid references public.catalog_variants(id) on delete set null,
  catalog_stock_unit_id uuid references public.catalog_stock_units(id) on delete set null,
  inventory_deduction_id uuid references public.inventory_deductions(id) on delete set null,
  allocation_key text not null,
  allocation_status text not null default 'projected',
  allocated_quantity numeric not null default 0,
  consumed_quantity numeric not null default 0,
  overrun_quantity numeric not null default 0,
  stock_unit_snapshot jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  constraint task_material_allocations_status_check
    check (allocation_status in ('projected', 'overrun', 'consumed', 'released', 'superseded')),
  constraint task_material_allocations_allocated_quantity_check
    check (allocated_quantity >= 0),
  constraint task_material_allocations_consumed_quantity_check
    check (consumed_quantity >= 0),
  constraint task_material_allocations_overrun_quantity_check
    check (overrun_quantity >= 0),
  constraint task_material_allocations_stock_snapshot_object_check
    check (jsonb_typeof(stock_unit_snapshot) = 'object')
);

alter table public.project_material_snapshot_items
  drop constraint if exists project_material_snapshot_items_allocation_id_fkey,
  add constraint project_material_snapshot_items_allocation_id_fkey
    foreign key (allocation_id)
    references public.task_material_allocations(id)
    on delete set null;

create unique index if not exists task_material_allocations_active_key
  on public.task_material_allocations(company_id, allocation_key)
  where deleted_at is null;

create index if not exists task_material_allocations_task_material_idx
  on public.task_material_allocations(company_id, task_material_id)
  where deleted_at is null and task_material_id is not null;

create index if not exists task_material_allocations_demand_idx
  on public.task_material_allocations(company_id, demand_id)
  where deleted_at is null and demand_id is not null;

create index if not exists task_material_allocations_stock_unit_idx
  on public.task_material_allocations(company_id, catalog_stock_unit_id)
  where deleted_at is null and catalog_stock_unit_id is not null;

create index if not exists task_material_allocations_inventory_deduction_idx
  on public.task_material_allocations(company_id, inventory_deduction_id)
  where deleted_at is null and inventory_deduction_id is not null;

drop trigger if exists trg_project_material_demands_updated_at
  on public.project_material_demands;
create trigger trg_project_material_demands_updated_at
  before update on public.project_material_demands
  for each row
  execute function public.fn_set_updated_at();

drop trigger if exists trg_task_material_allocations_updated_at
  on public.task_material_allocations;
create trigger trg_task_material_allocations_updated_at
  before update on public.task_material_allocations
  for each row
  execute function public.fn_set_updated_at();

create or replace function public.company_inventory_settings_write_guard()
returns trigger
language plpgsql
set search_path to 'public', 'pg_temp'
as $$
begin
  if coalesce(current_setting('ops.company_inventory_settings_rpc', true), '') <> 'on' then
    raise exception 'company_inventory_settings can only be changed by set_company_inventory_mode'
      using errcode = '42501';
  end if;

  if new.updated_by is not null
     and not exists (
       select 1
         from public.users user_row
        where user_row.id = new.updated_by
          and user_row.company_id = new.company_id
          and user_row.deleted_at is null
     ) then
    raise exception 'company_inventory_settings updated_by must belong to settings company'
      using errcode = '42501';
  end if;

  return new;
end;
$$;

drop trigger if exists trg_company_inventory_settings_00_write_guard
  on public.company_inventory_settings;
create trigger trg_company_inventory_settings_00_write_guard
  before insert or update on public.company_inventory_settings
  for each row
  execute function public.company_inventory_settings_write_guard();

create or replace function private.current_user_can_write_project_material_workflow(
  p_company_id uuid
)
returns boolean
language plpgsql
security invoker
stable
set search_path to 'public', 'private', 'pg_temp'
as $$
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
$$;

create or replace function public.project_material_workflow_write_guard()
returns trigger
language plpgsql
security invoker
set search_path to 'public', 'private', 'pg_temp'
as $$
declare
  v_company_id uuid;
begin
  v_company_id := case
    when tg_op = 'DELETE' then old.company_id
    else new.company_id
  end;

  if not private.current_user_can_write_project_material_workflow(v_company_id) then
    raise exception 'project material workflow tables can only be changed by an approved material workflow RPC'
      using errcode = '42501';
  end if;

  if tg_op = 'DELETE' then
    return old;
  end if;

  return new;
end;
$$;

create or replace function public.project_material_demands_company_guard()
returns trigger
language plpgsql
set search_path to 'public', 'pg_temp'
as $$
begin
  if not exists (
    select 1
      from public.projects project_row
     where project_row.id = new.project_id
       and project_row.company_id = new.company_id
       and project_row.deleted_at is null
  ) then
    raise exception 'project_material_demands project must belong to demand company'
      using errcode = '42501';
  end if;

  if new.task_id is not null
     and not exists (
       select 1
         from public.project_tasks task_row
        where task_row.id = new.task_id
          and task_row.company_id = new.company_id
          and task_row.project_id = new.project_id
          and task_row.deleted_at is null
     ) then
    raise exception 'project_material_demands task must belong to demand company and project'
      using errcode = '42501';
  end if;

  if new.estimate_id is not null
     and not exists (
       select 1
         from public.estimates estimate_row
        where estimate_row.id = new.estimate_id
          and estimate_row.company_id = new.company_id
          and estimate_row.deleted_at is null
     ) then
    raise exception 'project_material_demands estimate must belong to demand company'
      using errcode = '42501';
  end if;

  if new.line_item_id is not null
     and not exists (
       select 1
         from public.line_items line_item_row
        where line_item_row.id = new.line_item_id
          and line_item_row.company_id = new.company_id
          and (
            new.estimate_id is null
            or line_item_row.estimate_id = new.estimate_id
          )
          and (
            new.product_id is null
            or line_item_row.product_id is null
            or line_item_row.product_id = new.product_id
          )
     ) then
    raise exception 'project_material_demands line item must belong to demand company and estimate/product refs'
      using errcode = '42501';
  end if;

  if new.product_id is not null
     and not exists (
       select 1
         from public.products product_row
        where product_row.id = new.product_id
          and product_row.company_id = new.company_id
          and product_row.deleted_at is null
     ) then
    raise exception 'project_material_demands product must belong to demand company'
      using errcode = '42501';
  end if;

  if new.product_material_id is not null
     and not exists (
       select 1
         from public.product_materials material_row
         join public.products product_row
           on product_row.id = material_row.product_id
        where material_row.id = new.product_material_id
          and product_row.company_id = new.company_id
          and product_row.deleted_at is null
          and material_row.deleted_at is null
          and (
            new.product_id is null
            or material_row.product_id = new.product_id
          )
     ) then
    raise exception 'project_material_demands product material must belong to demand company and product'
      using errcode = '42501';
  end if;

  if new.catalog_variant_id is not null
     and not exists (
       select 1
         from public.catalog_variants variant_row
        where variant_row.id = new.catalog_variant_id
          and variant_row.company_id = new.company_id
          and variant_row.deleted_at is null
     ) then
    raise exception 'project_material_demands catalog variant must belong to demand company'
      using errcode = '42501';
  end if;

  if new.unit_id is not null
     and not exists (
       select 1
         from public.catalog_units unit_row
        where unit_row.id = new.unit_id
          and unit_row.company_id = new.company_id
          and unit_row.deleted_at is null
     ) then
    raise exception 'project_material_demands unit must belong to demand company'
      using errcode = '42501';
  end if;

  return new;
end;
$$;

create or replace function public.project_material_snapshots_company_guard()
returns trigger
language plpgsql
set search_path to 'public', 'pg_temp'
as $$
begin
  if not exists (
    select 1
      from public.projects project_row
     where project_row.id = new.project_id
       and project_row.company_id = new.company_id
       and project_row.deleted_at is null
  ) then
    raise exception 'project_material_snapshots project must belong to snapshot company'
      using errcode = '42501';
  end if;

  if new.task_id is not null
     and not exists (
       select 1
         from public.project_tasks task_row
        where task_row.id = new.task_id
          and task_row.company_id = new.company_id
          and task_row.project_id = new.project_id
          and task_row.deleted_at is null
     ) then
    raise exception 'project_material_snapshots task must belong to snapshot company and project'
      using errcode = '42501';
  end if;

  if new.estimate_id is not null
     and not exists (
       select 1
         from public.estimates estimate_row
        where estimate_row.id = new.estimate_id
          and estimate_row.company_id = new.company_id
          and estimate_row.deleted_at is null
     ) then
    raise exception 'project_material_snapshots estimate must belong to snapshot company'
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
    raise exception 'project_material_snapshots created_by must belong to snapshot company'
      using errcode = '42501';
  end if;

  return new;
end;
$$;

create or replace function public.project_material_snapshot_items_company_guard()
returns trigger
language plpgsql
set search_path to 'public', 'pg_temp'
as $$
begin
  if not exists (
    select 1
      from public.project_material_snapshots snapshot_row
     where snapshot_row.id = new.snapshot_id
       and snapshot_row.company_id = new.company_id
  ) then
    raise exception 'project_material_snapshot_items snapshot must belong to item company'
      using errcode = '42501';
  end if;

  if new.demand_id is not null
     and not exists (
       select 1
         from public.project_material_demands demand_row
        where demand_row.id = new.demand_id
          and demand_row.company_id = new.company_id
          and demand_row.deleted_at is null
     ) then
    raise exception 'project_material_snapshot_items demand must belong to item company'
      using errcode = '42501';
  end if;

  if new.task_material_id is not null
     and not exists (
       select 1
         from public.task_materials task_material_row
         join public.project_tasks task_row
           on task_row.id = task_material_row.task_id
        where task_material_row.id = new.task_material_id
          and task_row.company_id = new.company_id
          and task_row.deleted_at is null
     ) then
    raise exception 'project_material_snapshot_items task material must belong to item company'
      using errcode = '42501';
  end if;

  if new.allocation_id is not null
     and not exists (
       select 1
         from public.task_material_allocations allocation_row
        where allocation_row.id = new.allocation_id
          and allocation_row.company_id = new.company_id
          and allocation_row.deleted_at is null
     ) then
    raise exception 'project_material_snapshot_items allocation must belong to item company'
      using errcode = '42501';
  end if;

  if new.inventory_deduction_id is not null
     and not exists (
       select 1
         from public.inventory_deductions deduction_row
        where deduction_row.id = new.inventory_deduction_id
          and deduction_row.company_id = new.company_id
     ) then
    raise exception 'project_material_snapshot_items inventory deduction must belong to item company'
      using errcode = '42501';
  end if;

  if new.catalog_variant_id is not null
     and not exists (
       select 1
         from public.catalog_variants variant_row
        where variant_row.id = new.catalog_variant_id
          and variant_row.company_id = new.company_id
          and variant_row.deleted_at is null
     ) then
    raise exception 'project_material_snapshot_items catalog variant must belong to item company'
      using errcode = '42501';
  end if;

  if new.catalog_stock_unit_id is not null
     and not exists (
       select 1
         from public.catalog_stock_units unit_row
        where unit_row.id = new.catalog_stock_unit_id
          and unit_row.company_id = new.company_id
          and unit_row.deleted_at is null
          and (
            new.catalog_variant_id is null
            or unit_row.catalog_variant_id = new.catalog_variant_id
          )
     ) then
    raise exception 'project_material_snapshot_items stock unit must belong to item company and variant'
      using errcode = '42501';
  end if;

  if new.source_event_id is not null
     and not exists (
       select 1
         from public.catalog_stock_unit_events event_row
        where event_row.id = new.source_event_id
          and event_row.company_id = new.company_id
          and (
            new.catalog_stock_unit_id is null
            or event_row.catalog_stock_unit_id = new.catalog_stock_unit_id
          )
     ) then
    raise exception 'project_material_snapshot_items stock unit event must belong to item company and stock unit'
      using errcode = '42501';
  end if;

  if new.unit_id is not null
     and not exists (
       select 1
         from public.catalog_units unit_row
        where unit_row.id = new.unit_id
          and unit_row.company_id = new.company_id
          and unit_row.deleted_at is null
     ) then
    raise exception 'project_material_snapshot_items unit must belong to item company'
      using errcode = '42501';
  end if;

  return new;
end;
$$;

create or replace function public.task_material_allocations_company_guard()
returns trigger
language plpgsql
set search_path to 'public', 'pg_temp'
as $$
begin
  if new.task_material_id is not null
     and not exists (
       select 1
         from public.task_materials task_material_row
         join public.project_tasks task_row
           on task_row.id = task_material_row.task_id
        where task_material_row.id = new.task_material_id
          and task_row.company_id = new.company_id
          and task_row.deleted_at is null
          and (
            new.catalog_variant_id is null
            or task_material_row.catalog_variant_id is null
            or task_material_row.catalog_variant_id = new.catalog_variant_id
          )
     ) then
    raise exception 'task_material_allocations task material must belong to allocation company and variant'
      using errcode = '42501';
  end if;

  if new.demand_id is not null
     and not exists (
       select 1
         from public.project_material_demands demand_row
        where demand_row.id = new.demand_id
          and demand_row.company_id = new.company_id
          and demand_row.deleted_at is null
          and (
            new.catalog_variant_id is null
            or demand_row.catalog_variant_id is null
            or demand_row.catalog_variant_id = new.catalog_variant_id
          )
     ) then
    raise exception 'task_material_allocations demand must belong to allocation company and variant'
      using errcode = '42501';
  end if;

  if new.catalog_variant_id is not null
     and not exists (
       select 1
         from public.catalog_variants variant_row
        where variant_row.id = new.catalog_variant_id
          and variant_row.company_id = new.company_id
          and variant_row.deleted_at is null
     ) then
    raise exception 'task_material_allocations catalog variant must belong to allocation company'
      using errcode = '42501';
  end if;

  if new.catalog_stock_unit_id is not null
     and not exists (
       select 1
         from public.catalog_stock_units stock_unit_row
        where stock_unit_row.id = new.catalog_stock_unit_id
          and stock_unit_row.company_id = new.company_id
          and stock_unit_row.deleted_at is null
          and (
            new.catalog_variant_id is null
            or stock_unit_row.catalog_variant_id = new.catalog_variant_id
          )
     ) then
    raise exception 'task_material_allocations stock unit must belong to allocation company and variant'
      using errcode = '42501';
  end if;

  if new.inventory_deduction_id is not null
     and not exists (
       select 1
         from public.inventory_deductions deduction_row
        where deduction_row.id = new.inventory_deduction_id
          and deduction_row.company_id = new.company_id
          and (
            new.catalog_variant_id is null
            or deduction_row.catalog_variant_id = new.catalog_variant_id
          )
     ) then
    raise exception 'task_material_allocations inventory deduction must belong to allocation company and variant'
      using errcode = '42501';
  end if;

  return new;
end;
$$;

drop trigger if exists trg_project_material_demands_00_write_guard
  on public.project_material_demands;
create trigger trg_project_material_demands_00_write_guard
  before insert or update or delete on public.project_material_demands
  for each row
  execute function public.project_material_workflow_write_guard();

drop trigger if exists trg_project_material_demands_company_guard
  on public.project_material_demands;
create trigger trg_project_material_demands_company_guard
  before insert or update on public.project_material_demands
  for each row
  execute function public.project_material_demands_company_guard();

drop trigger if exists trg_project_material_snapshots_00_write_guard
  on public.project_material_snapshots;
create trigger trg_project_material_snapshots_00_write_guard
  before insert or update or delete on public.project_material_snapshots
  for each row
  execute function public.project_material_workflow_write_guard();

drop trigger if exists trg_project_material_snapshots_company_guard
  on public.project_material_snapshots;
create trigger trg_project_material_snapshots_company_guard
  before insert or update on public.project_material_snapshots
  for each row
  execute function public.project_material_snapshots_company_guard();

drop trigger if exists trg_project_material_snapshot_items_00_write_guard
  on public.project_material_snapshot_items;
create trigger trg_project_material_snapshot_items_00_write_guard
  before insert or update or delete on public.project_material_snapshot_items
  for each row
  execute function public.project_material_workflow_write_guard();

drop trigger if exists trg_project_material_snapshot_items_company_guard
  on public.project_material_snapshot_items;
create trigger trg_project_material_snapshot_items_company_guard
  before insert or update on public.project_material_snapshot_items
  for each row
  execute function public.project_material_snapshot_items_company_guard();

drop trigger if exists trg_task_material_allocations_00_write_guard
  on public.task_material_allocations;
create trigger trg_task_material_allocations_00_write_guard
  before insert or update or delete on public.task_material_allocations
  for each row
  execute function public.project_material_workflow_write_guard();

drop trigger if exists trg_task_material_allocations_company_guard
  on public.task_material_allocations;
create trigger trg_task_material_allocations_company_guard
  before insert or update on public.task_material_allocations
  for each row
  execute function public.task_material_allocations_company_guard();

alter table public.notifications
  add column if not exists dedupe_key text,
  add column if not exists resolved_at timestamptz,
  add column if not exists resolved_by uuid references public.users(id) on delete set null,
  add column if not exists resolution_reason text;

drop index if exists public.idx_notifications_unread_dedup;

create unique index if not exists notifications_unread_title_dedup_without_key
  on public.notifications(user_id, company_id, type, title)
  where is_read = false
    and dedupe_key is null;

create unique index if not exists notifications_open_dedupe_key
  on public.notifications(user_id, company_id, type, dedupe_key)
  where is_read = false
    and resolved_at is null
    and dedupe_key is not null;

create index if not exists notifications_company_type_dedupe_idx
  on public.notifications(company_id, type, dedupe_key)
  where resolved_at is null
    and dedupe_key is not null;

create index if not exists notifications_resolved_idx
  on public.notifications(company_id, type, resolved_at)
  where dedupe_key is not null;

alter table public.company_inventory_settings enable row level security;
alter table public.project_material_demands enable row level security;
alter table public.project_material_snapshots enable row level security;
alter table public.project_material_snapshot_items enable row level security;
alter table public.task_material_allocations enable row level security;

drop policy if exists company_inventory_settings_select_company
  on public.company_inventory_settings;
create policy company_inventory_settings_select_company
  on public.company_inventory_settings
  for select
  using (company_id = (select private.get_user_company_id()));

drop policy if exists company_inventory_settings_insert_manage
  on public.company_inventory_settings;
create policy company_inventory_settings_insert_manage
  on public.company_inventory_settings
  for insert
  with check (
    company_id = (select private.get_user_company_id())
    and private.current_user_has_permission('catalog.manage', 'all')
  );

drop policy if exists company_inventory_settings_update_manage
  on public.company_inventory_settings;
create policy company_inventory_settings_update_manage
  on public.company_inventory_settings
  for update
  using (
    company_id = (select private.get_user_company_id())
    and private.current_user_has_permission('catalog.manage', 'all')
  )
  with check (
    company_id = (select private.get_user_company_id())
    and private.current_user_has_permission('catalog.manage', 'all')
  );

drop policy if exists project_material_demands_select_company
  on public.project_material_demands;
create policy project_material_demands_select_company
  on public.project_material_demands
  for select
  using (company_id = (select private.get_user_company_id()));

drop policy if exists project_material_demands_insert_manage
  on public.project_material_demands;
drop policy if exists project_material_demands_insert_workflow
  on public.project_material_demands;
create policy project_material_demands_insert_workflow
  on public.project_material_demands
  for insert
  with check (
    private.current_user_can_write_project_material_workflow(company_id)
  );

drop policy if exists project_material_demands_update_manage
  on public.project_material_demands;
drop policy if exists project_material_demands_update_workflow
  on public.project_material_demands;
create policy project_material_demands_update_workflow
  on public.project_material_demands
  for update
  using (
    private.current_user_can_write_project_material_workflow(company_id)
  )
  with check (
    private.current_user_can_write_project_material_workflow(company_id)
  );

drop policy if exists project_material_snapshots_select_company
  on public.project_material_snapshots;
create policy project_material_snapshots_select_company
  on public.project_material_snapshots
  for select
  using (company_id = (select private.get_user_company_id()));

drop policy if exists project_material_snapshots_insert_manage
  on public.project_material_snapshots;
drop policy if exists project_material_snapshots_insert_workflow
  on public.project_material_snapshots;
create policy project_material_snapshots_insert_workflow
  on public.project_material_snapshots
  for insert
  with check (
    private.current_user_can_write_project_material_workflow(company_id)
  );

drop policy if exists project_material_snapshot_items_select_company
  on public.project_material_snapshot_items;
create policy project_material_snapshot_items_select_company
  on public.project_material_snapshot_items
  for select
  using (company_id = (select private.get_user_company_id()));

drop policy if exists project_material_snapshot_items_insert_manage
  on public.project_material_snapshot_items;
drop policy if exists project_material_snapshot_items_insert_workflow
  on public.project_material_snapshot_items;
create policy project_material_snapshot_items_insert_workflow
  on public.project_material_snapshot_items
  for insert
  with check (
    private.current_user_can_write_project_material_workflow(company_id)
  );

drop policy if exists task_material_allocations_select_company
  on public.task_material_allocations;
create policy task_material_allocations_select_company
  on public.task_material_allocations
  for select
  using (company_id = (select private.get_user_company_id()));

drop policy if exists task_material_allocations_insert_manage
  on public.task_material_allocations;
drop policy if exists task_material_allocations_insert_workflow
  on public.task_material_allocations;
create policy task_material_allocations_insert_workflow
  on public.task_material_allocations
  for insert
  with check (
    private.current_user_can_write_project_material_workflow(company_id)
  );

drop policy if exists task_material_allocations_update_manage
  on public.task_material_allocations;
drop policy if exists task_material_allocations_update_workflow
  on public.task_material_allocations;
create policy task_material_allocations_update_workflow
  on public.task_material_allocations
  for update
  using (
    private.current_user_can_write_project_material_workflow(company_id)
  )
  with check (
    private.current_user_can_write_project_material_workflow(company_id)
  );

revoke all on table public.company_inventory_settings from public;
revoke all on table public.project_material_demands from public;
revoke all on table public.project_material_snapshots from public;
revoke all on table public.project_material_snapshot_items from public;
revoke all on table public.task_material_allocations from public;

revoke all on table public.company_inventory_settings from anon;
revoke all on table public.project_material_demands from anon;
revoke all on table public.project_material_snapshots from anon;
revoke all on table public.project_material_snapshot_items from anon;
revoke all on table public.task_material_allocations from anon;

revoke all on table public.company_inventory_settings from authenticated;
revoke all on table public.project_material_demands from authenticated;
revoke all on table public.project_material_snapshots from authenticated;
revoke all on table public.project_material_snapshot_items from authenticated;
revoke all on table public.task_material_allocations from authenticated;

grant select, insert, update on table public.company_inventory_settings to authenticated;
grant select, insert, update on table public.project_material_demands to authenticated;
grant select, insert on table public.project_material_snapshots to authenticated;
grant select, insert on table public.project_material_snapshot_items to authenticated;
grant select, insert, update on table public.task_material_allocations to authenticated;

revoke all on function public.company_inventory_settings_write_guard()
  from public, anon, authenticated;
revoke all on function private.current_user_can_write_project_material_workflow(uuid)
  from public, anon, authenticated;
revoke all on function public.project_material_workflow_write_guard()
  from public, anon, authenticated;
revoke all on function public.project_material_demands_company_guard()
  from public, anon, authenticated;
revoke all on function public.project_material_snapshots_company_guard()
  from public, anon, authenticated;
revoke all on function public.project_material_snapshot_items_company_guard()
  from public, anon, authenticated;
revoke all on function public.task_material_allocations_company_guard()
  from public, anon, authenticated;
grant execute on function private.current_user_can_write_project_material_workflow(uuid)
  to authenticated;

create or replace function public.set_company_inventory_mode(
  p_company_id uuid,
  p_inventory_mode text
)
returns jsonb
language plpgsql
set search_path to 'public', 'private', 'pg_temp'
as $$
declare
  v_actor uuid;
  v_now timestamptz := now();
  v_previous_mode text;
  v_released_demands integer := 0;
  v_release_snapshots integer := 0;
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
      returning demand_row.project_id
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
      (select count(*) from inserted_snapshots)
      into v_released_demands, v_release_snapshots;
  end if;

  return jsonb_build_object(
    'ok', true,
    'company_id', p_company_id,
    'inventory_mode', p_inventory_mode,
    'previous_inventory_mode', coalesce(v_previous_mode, 'off'),
    'updated_by', v_actor,
    'released_demands', v_released_demands,
    'release_snapshots', v_release_snapshots
  );
end;
$$;

revoke all on function public.set_company_inventory_mode(uuid, text) from public;
grant execute on function public.set_company_inventory_mode(uuid, text) to authenticated;

commit;
