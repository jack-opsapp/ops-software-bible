begin;

alter table public.company_settings
  add column if not exists catalog_setup_completed_at timestamptz;

do $$
begin
  if not exists (
    select 1 from information_schema.columns
    where table_schema='public' and table_name='company_settings'
      and column_name='catalog_setup_completed_at'
  ) then
    raise exception 'catalog_setup_completed_sentinel: column missing after add';
  end if;
end $$;

commit;
