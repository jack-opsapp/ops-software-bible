begin;

insert into public.role_permissions (role_id, permission, scope)
values
  ('00000000-0000-0000-0000-000000000001','catalog.run_setup','all'), -- ADMIN preset
  ('00000000-0000-0000-0000-000000000002','catalog.run_setup','all'), -- OWNER preset
  ('00000000-0000-0000-0000-000000000003','catalog.run_setup','all')  -- OFFICE preset
on conflict (role_id, permission) do nothing;

do $$
begin
  if not exists (
    select 1 from public.role_permissions
    where role_id = '00000000-0000-0000-0000-000000000003'
      and permission = 'catalog.run_setup'
  ) then
    raise exception 'catalog_run_setup_grant_sentinel: OFFICE preset grant missing';
  end if;
end $$;

commit;
