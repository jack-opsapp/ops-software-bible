-- Catalog setup foundation: physical stock unit identity.
-- Approved target only. Do not apply to production without explicit approval.

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

create table if not exists public.catalog_stock_units (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  catalog_variant_id uuid not null references public.catalog_variants(id) on delete cascade,
  unit_kind text not null default 'each',
  label text,
  lot_code text,
  width_value numeric,
  width_unit text,
  original_length_value numeric,
  remaining_length_value numeric,
  length_unit text,
  quantity_value numeric not null default 1,
  location text,
  status text not null default 'full',
  source_order_item_id uuid references public.catalog_order_items(id) on delete set null,
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  constraint catalog_stock_units_unit_kind_check
    check (unit_kind in ('roll', 'offcut', 'box', 'each', 'lot', 'pallet', 'length')),
  constraint catalog_stock_units_status_check
    check (status in ('full', 'partial', 'reserved', 'consumed', 'scrapped')),
  constraint catalog_stock_units_width_nonnegative_check
    check (width_value is null or width_value >= 0),
  constraint catalog_stock_units_original_length_nonnegative_check
    check (original_length_value is null or original_length_value >= 0),
  constraint catalog_stock_units_remaining_length_nonnegative_check
    check (remaining_length_value is null or remaining_length_value >= 0),
  constraint catalog_stock_units_quantity_nonnegative_check
    check (quantity_value >= 0),
  constraint catalog_stock_units_remaining_lte_original_check
    check (
      remaining_length_value is null
      or original_length_value is null
      or remaining_length_value <= original_length_value
    )
);

create index if not exists idx_catalog_stock_units_company_active
  on public.catalog_stock_units(company_id, updated_at)
  where deleted_at is null;

create index if not exists idx_catalog_stock_units_variant_active
  on public.catalog_stock_units(catalog_variant_id)
  where deleted_at is null;

create index if not exists idx_catalog_stock_units_status_active
  on public.catalog_stock_units(company_id, status)
  where deleted_at is null;

create index if not exists idx_catalog_stock_units_source_order_item
  on public.catalog_stock_units(source_order_item_id)
  where source_order_item_id is not null;

drop trigger if exists trg_catalog_stock_units_updated_at on public.catalog_stock_units;
create trigger trg_catalog_stock_units_updated_at
  before update on public.catalog_stock_units
  for each row
  execute function public.fn_set_updated_at();

alter table public.catalog_stock_units enable row level security;

drop policy if exists company_isolation on public.catalog_stock_units;
create policy company_isolation
  on public.catalog_stock_units
  for all
  using (company_id = (select private.get_user_company_id()))
  with check (company_id = (select private.get_user_company_id()));

commit;
