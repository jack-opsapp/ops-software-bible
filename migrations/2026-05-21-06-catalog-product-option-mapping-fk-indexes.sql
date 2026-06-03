-- Forward-fix for Supabase performance advisor FK coverage on the active
-- catalog/product option bridge. Keep each FK as the leading indexed column.

create index if not exists idx_catalog_product_option_mappings_catalog_option_active
  on public.catalog_product_option_mappings(catalog_option_id)
  where deleted_at is null;

create index if not exists idx_catalog_product_option_mappings_catalog_option_value_active
  on public.catalog_product_option_mappings(catalog_option_value_id)
  where deleted_at is null;

create index if not exists idx_catalog_product_option_mappings_product_option_active
  on public.catalog_product_option_mappings(product_option_id)
  where deleted_at is null;

create index if not exists idx_catalog_product_option_mappings_product_option_value_active
  on public.catalog_product_option_mappings(product_option_value_id)
  where deleted_at is null;
