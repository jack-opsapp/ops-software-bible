-- SPEC Phase 1 — Migration 3/8: Operator gate (private.is_spec_operator) + SPEC Operator role + permission seed
-- Source spec: ops-software-bible/SPEC/02_DATA_MODEL.md § Operator gate
-- Resolved per SPEC-SECURITY-DEFINER-PRIVATE-SCHEMA + SPEC-LIVE-SCHEMA-MISMATCHES (2026-05-25).

-- Schema already exists; idempotent.
create schema if not exists private;

-- The SPEC operator gate. Consults role_permissions(permission='spec.admin', scope='all')
-- and user_permission_overrides(permission='spec.admin', granted=true) ONLY.
-- Never trusts customer-company admin status (which public.has_permission does).
create or replace function private.is_spec_operator()
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select exists (
    select 1
    from public.role_permissions rp
    join public.user_roles ur on ur.role_id = rp.role_id
    where ur.user_id = public.get_user_id()
      and rp.permission = 'spec.admin'
      and rp.scope = 'all'
  )
  or exists (
    select 1
    from public.user_permission_overrides upo
    where upo.user_id::text = public.get_user_id()
      and upo.permission = 'spec.admin'
      and upo.granted = true
  );
$$;

-- Grants match existing OPS convention for private.* SECURITY DEFINER helpers:
--   private schema USAGE granted to authenticated, service_role (anon explicitly NOT granted).
--   function EXECUTE granted to public (resolves to authenticated, since anon lacks USAGE).
grant usage on schema private to authenticated, service_role;
grant execute on function private.is_spec_operator() to public;

-- SPEC Operator role seed. UUID '..00a1' separates SPEC namespace from existing
-- customer-role namespace (..01..06).
insert into public.roles (id, name, hierarchy, is_preset, company_id, created_at)
values (
  '00000000-0000-0000-0000-0000000000a1',
  'SPEC Operator',
  0,
  true,
  null,
  now()
)
on conflict (id) do nothing;

-- Grant the spec.admin permission to the SPEC Operator role.
insert into public.role_permissions (id, role_id, permission, scope, created_at)
values (
  gen_random_uuid(),
  '00000000-0000-0000-0000-0000000000a1',
  'spec.admin',
  'all',
  now()
)
on conflict do nothing;

-- Add Jackson (j4ckson.sweet@gmail.com, user_id 1746a0c1-be43-45d6-ab4d-584e82594b1b)
-- to the SPEC Operator role. Verified live 2026-05-25.
insert into public.user_roles (id, user_id, role_id, created_at)
values (
  gen_random_uuid(),
  '1746a0c1-be43-45d6-ab4d-584e82594b1b',
  '00000000-0000-0000-0000-0000000000a1',
  now()
)
on conflict do nothing;
