-- Catalog setup foundation: bundle relationship semantics and product↔catalog
-- option mappings. Approved target only. Do not apply to production without
-- explicit approval.
--
-- Live preflight found an active Diverter family with two variants sharing the
-- same option-value signature. This migration intentionally does not add a DB
-- uniqueness constraint for matrix signatures; iOS validation blocks new
-- duplicates until production cleanup is separately approved.

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

alter table public.product_bundle_items
  add column if not exists relationship_kind text not null default 'required',
  add column if not exists suggestion_reason text,
  add column if not exists compatibility_selector jsonb;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'product_bundle_items_relationship_kind_check'
      and conrelid = 'public.product_bundle_items'::regclass
  ) then
    alter table public.product_bundle_items
      add constraint product_bundle_items_relationship_kind_check
      check (relationship_kind in ('required', 'suggested'));
  end if;
end;
$$;

create index if not exists idx_product_bundle_items_relationship_active
  on public.product_bundle_items(company_id, bundle_product_id, relationship_kind, display_order)
  where deleted_at is null;

create table if not exists public.catalog_product_option_mappings (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  product_id uuid not null references public.products(id) on delete cascade,
  catalog_item_id uuid not null references public.catalog_items(id) on delete cascade,
  catalog_option_id uuid not null references public.catalog_options(id) on delete cascade,
  product_option_id uuid not null references public.product_options(id) on delete cascade,
  catalog_option_value_id uuid references public.catalog_option_values(id) on delete cascade,
  product_option_value_id uuid references public.product_option_values(id) on delete cascade,
  mapping_kind text not null default 'axis',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  constraint catalog_product_option_mappings_kind_check
    check (mapping_kind in ('axis', 'value')),
  constraint catalog_product_option_mappings_shape_check
    check (
      (
        mapping_kind = 'axis'
        and catalog_option_value_id is null
        and product_option_value_id is null
      )
      or
      (
        mapping_kind = 'value'
        and catalog_option_value_id is not null
        and product_option_value_id is not null
      )
    )
);

create index if not exists idx_catalog_product_option_mappings_company_active
  on public.catalog_product_option_mappings(company_id, updated_at)
  where deleted_at is null;

create index if not exists idx_catalog_product_option_mappings_product_active
  on public.catalog_product_option_mappings(product_id)
  where deleted_at is null;

create index if not exists idx_catalog_product_option_mappings_catalog_item_active
  on public.catalog_product_option_mappings(catalog_item_id)
  where deleted_at is null;

create unique index if not exists catalog_product_option_mappings_axis_unique
  on public.catalog_product_option_mappings(
    company_id,
    product_id,
    catalog_item_id,
    catalog_option_id,
    product_option_id
  )
  where deleted_at is null and mapping_kind = 'axis';

create unique index if not exists catalog_product_option_mappings_value_unique
  on public.catalog_product_option_mappings(
    company_id,
    product_id,
    catalog_item_id,
    catalog_option_id,
    product_option_id,
    catalog_option_value_id,
    product_option_value_id
  )
  where deleted_at is null and mapping_kind = 'value';

-- Live production already has this DB guard. App-level setup validation treats
-- duplicate SKUs as a warning because matrix-signature conflicts are the only
-- catalog setup identity issue that blocks draft construction locally.
create unique index if not exists catalog_variants_sku_unique_per_company
  on public.catalog_variants(company_id, lower(btrim(sku)))
  where deleted_at is null and sku is not null and btrim(sku) <> '';

drop trigger if exists trg_catalog_product_option_mappings_updated_at on public.catalog_product_option_mappings;
create trigger trg_catalog_product_option_mappings_updated_at
  before update on public.catalog_product_option_mappings
  for each row
  execute function public.fn_set_updated_at();

alter table public.catalog_product_option_mappings enable row level security;

drop policy if exists company_isolation on public.catalog_product_option_mappings;
create policy company_isolation
  on public.catalog_product_option_mappings
  for all
  using (company_id = (select private.get_user_company_id()))
  with check (company_id = (select private.get_user_company_id()));

commit;
