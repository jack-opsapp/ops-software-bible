-- Recipient-lookup RPC. Returns user IDs in a company who hold a permission,
-- matching iOS PermissionService logic (role grants + overrides) and the admin
-- escape hatches in public.has_permission (is_company_admin / account_holder /
-- admin_ids array).
--
-- Used by client code to dispatch in-app + push notifications without filtering
-- by role string. Replaces sites that did .in("role", values: [...]).

create or replace function public.users_with_permission(
  p_company_id uuid,
  p_permission text,
  p_required_scope text default 'all'
) returns setof uuid
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_account_holder_uuid uuid;
  v_admin_uuids uuid[];
begin
  if p_company_id is null or p_permission is null then
    return;
  end if;

  -- Resolve company-level admin escape hatches once.
  -- companies.account_holder_id and admin_ids are stored as text/text[].
  select
    nullif(c.account_holder_id, '')::uuid,
    coalesce(
      (select array_agg(x::uuid) from unnest(c.admin_ids) as x where x is not null and x <> ''),
      array[]::uuid[]
    )
  into v_account_holder_uuid, v_admin_uuids
  from public.companies c
  where c.id = p_company_id;

  return query
  with company_users as (
    select u.id, u.is_company_admin
    from public.users u
    where u.company_id = p_company_id
      and u.deleted_at is null
  ),
  -- Tier 1: company admins (always granted, mirroring has_permission).
  company_admins as (
    select cu.id
    from company_users cu
    where coalesce(cu.is_company_admin, false)
       or cu.id = v_account_holder_uuid
       or cu.id = any(coalesce(v_admin_uuids, array[]::uuid[]))
  ),
  -- Tier 2: role-based grants. user_roles.user_id is text, so cast.
  --         Pick the best (lowest-rank) scope per user.
  role_grants as (
    select
      cu.id as user_id,
      min(case rp.scope
            when 'all' then 1
            when 'assigned' then 2
            when 'own' then 3
            else 4
          end) as best_rank
    from company_users cu
    join public.user_roles ur on ur.user_id = cu.id::text
    join public.role_permissions rp on rp.role_id = ur.role_id
    where rp.permission = p_permission
    group by cu.id
  ),
  role_grants_filtered as (
    select user_id from role_grants
    where (best_rank = 1)
       or (best_rank = 2 and p_required_scope in ('assigned','own'))
       or (best_rank = 3 and p_required_scope = 'own')
  ),
  -- Tier 3: explicit user overrides. Match iOS PermissionService.fetchPermissions:
  --   granted=true with scope -> grants at that scope (null scope inherits)
  --   granted=false           -> denies entirely
  override_grants as (
    select uo.user_id
    from public.user_permission_overrides uo
    join company_users cu on cu.id = uo.user_id
    where uo.company_id = p_company_id
      and uo.permission = p_permission
      and uo.granted = true
      and (
        uo.scope is null
        or uo.scope = 'all'
        or (uo.scope = 'assigned' and p_required_scope in ('assigned','own'))
        or (uo.scope = 'own' and p_required_scope = 'own')
      )
  ),
  override_denials as (
    select uo.user_id
    from public.user_permission_overrides uo
    where uo.company_id = p_company_id
      and uo.permission = p_permission
      and uo.granted = false
  ),
  candidates as (
    select id as uid from company_admins
    union
    select user_id from role_grants_filtered
    union
    select user_id from override_grants
  )
  select distinct uid from candidates
  -- Admins bypass denials (matches has_permission semantics).
  where uid not in (select user_id from override_denials)
     or uid in (select id from company_admins);
end;
$$;

comment on function public.users_with_permission(uuid, text, text) is
  'Returns user IDs in a company who hold a given permission at the required '
  'scope or higher. Mirrors iOS PermissionService precedence: company-admin '
  'escape hatches > role grants > user overrides (grant/deny). Use for '
  'recipient lookups (notifications, reviewer dispatch). Never filter by role.';

grant execute on function public.users_with_permission(uuid, text, text) to authenticated, service_role;
