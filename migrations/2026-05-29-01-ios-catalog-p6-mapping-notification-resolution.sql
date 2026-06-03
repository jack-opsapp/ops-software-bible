-- OPS iOS Catalog P6-23: resolve missing mapping notifications when mappings are saved.
-- Forward-only. Resolver runs as invoker and relies on existing RLS/policies.

begin;

create or replace function private.resolve_catalog_mapping_needed_notifications_for_mapping()
returns trigger
language plpgsql
security invoker
set search_path to 'public', 'private', 'pg_temp'
as $$
declare
  v_company_id uuid := new.company_id;
  v_dedupe_key text;
begin
  if tg_op = 'DELETE' then
    return old;
  end if;

  if new.deleted_at is not null then
    return new;
  end if;

  if v_company_id is null
     or v_company_id is distinct from private.get_user_company_id() then
    return new;
  end if;

  if new.mapping_kind = 'axis'
     and new.product_id is not null
     and new.catalog_item_id is not null
     and new.product_option_id is not null then
    v_dedupe_key :=
      'catalog_mapping_needed:product:' || new.product_id::text ||
      ':catalog_item:' || new.catalog_item_id::text ||
      ':option:' || new.product_option_id::text;
  elsif new.mapping_kind = 'value'
     and new.product_id is not null
     and new.catalog_item_id is not null
     and new.product_option_id is not null
     and new.product_option_value_id is not null then
    v_dedupe_key :=
      'catalog_mapping_needed:product:' || new.product_id::text ||
      ':catalog_item:' || new.catalog_item_id::text ||
      ':option:' || new.product_option_id::text ||
      ':value:' || new.product_option_value_id::text;
  else
    return new;
  end if;

  update public.notifications
     set is_read = true,
         resolved_at = now(),
         resolved_by = private.get_current_user_id(),
         resolution_reason = 'catalog_mapping_saved'
   where company_id = v_company_id::text
     and type = 'catalog_mapping_needed'
     and dedupe_key = v_dedupe_key
     and resolved_at is null;

  return new;
end;
$$;

drop trigger if exists trg_catalog_product_option_mappings_resolve_notifications
  on public.catalog_product_option_mappings;

create trigger trg_catalog_product_option_mappings_resolve_notifications
after insert or update of product_id, catalog_item_id, product_option_id, product_option_value_id, mapping_kind, deleted_at
on public.catalog_product_option_mappings
for each row
execute function private.resolve_catalog_mapping_needed_notifications_for_mapping();

create or replace function private.resolve_catalog_mapping_needed_notifications_for_product_link()
returns trigger
language plpgsql
security invoker
set search_path to 'public', 'private', 'pg_temp'
as $$
declare
  v_company_id uuid := new.company_id;
  v_dedupe_key text;
begin
  if tg_op = 'DELETE' then
    return old;
  end if;

  if new.deleted_at is not null
     or new.linked_catalog_item_id is null then
    return new;
  end if;

  if v_company_id is null
     or v_company_id is distinct from private.get_user_company_id() then
    return new;
  end if;

  if not exists (
    select 1
      from public.catalog_items ci
     where ci.id = new.linked_catalog_item_id
       and ci.company_id = v_company_id
       and ci.deleted_at is null
  ) then
    return new;
  end if;

  v_dedupe_key :=
    'catalog_mapping_needed:product:' || new.id::text ||
    ':linked_catalog_item';

  update public.notifications
     set is_read = true,
         resolved_at = now(),
         resolved_by = private.get_current_user_id(),
         resolution_reason = 'catalog_product_linked'
   where company_id = v_company_id::text
     and type = 'catalog_mapping_needed'
     and dedupe_key = v_dedupe_key
     and resolved_at is null;

  return new;
end;
$$;

drop trigger if exists trg_products_resolve_catalog_mapping_notifications
  on public.products;

create trigger trg_products_resolve_catalog_mapping_notifications
after insert or update of linked_catalog_item_id, deleted_at
on public.products
for each row
execute function private.resolve_catalog_mapping_needed_notifications_for_product_link();

revoke all on function private.resolve_catalog_mapping_needed_notifications_for_mapping()
  from public, anon, authenticated, service_role;
revoke all on function private.resolve_catalog_mapping_needed_notifications_for_product_link()
  from public, anon, authenticated, service_role;

comment on function private.resolve_catalog_mapping_needed_notifications_for_mapping()
  is 'P6-23 invoker resolver: closes keyed catalog_mapping_needed notifications after saved product-option mappings.';
comment on function private.resolve_catalog_mapping_needed_notifications_for_product_link()
  is 'P6-23 invoker resolver: closes keyed linked-catalog-item notifications after product catalog linking.';
comment on trigger trg_catalog_product_option_mappings_resolve_notifications
  on public.catalog_product_option_mappings
  is 'P6-23 resolves missing mapping notifications from any mapping save path.';
comment on trigger trg_products_resolve_catalog_mapping_notifications
  on public.products
  is 'P6-23 resolves linked catalog item notifications from any product save path.';

commit;
