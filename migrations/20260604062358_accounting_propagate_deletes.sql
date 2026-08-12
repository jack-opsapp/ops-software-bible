begin;

-- Additive: accounting_connections.propagate_deletes for the sync-mode toggle.
-- nullable-with-default → iOS-sync-safe. Push path is gated by env
-- ACCOUNTING_WRITE_ENABLED regardless of this flag, so no write to a provider
-- can fire until the outbound engine ships.
alter table public.accounting_connections
  add column if not exists propagate_deletes boolean not null default false;

do $$
begin
  if not exists (
    select 1 from information_schema.columns
    where table_schema = 'public'
      and table_name = 'accounting_connections'
      and column_name = 'propagate_deletes'
  ) then
    raise exception 'accounting_propagate_deletes_sentinel: missing accounting_connections.propagate_deletes';
  end if;
end $$;

commit;
