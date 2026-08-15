-- The public app-facing normalizer is used by a projects expression index.
-- Its implementation delegates to private helpers that are intentionally not
-- executable by app roles, so run the wrapper with its owner's privileges.
alter function private.normalize_address(text) security definer;

comment on function private.normalize_address(text) is
  'Canonical project-address normalizer. SECURITY DEFINER is required because the app-executable wrapper delegates to non-public private helpers and is used by a projects expression index.';

create or replace function private.current_user_can_view_deck_design(
  p_company_id uuid,
  p_opportunity_id uuid,
  p_project_id uuid
)
returns boolean
language plpgsql
stable
security definer
set search_path to 'pg_catalog', 'public', 'private', 'pg_temp'
as $function$
declare
  v_actor_user_id uuid := private.get_current_user_id();
begin
  if private.get_user_company_id() is distinct from p_company_id then
    return false;
  end if;

  -- An all-scope user may view every design in their own company, including
  -- historical designs whose parent was later soft-deleted.
  if public.has_permission(
    v_actor_user_id,
    'deck_builder.view',
    'all'
  ) then
    return true;
  end if;

  if p_opportunity_id is null and p_project_id is null then
    return false;
  end if;

  if not public.has_permission(
    v_actor_user_id,
    'deck_builder.view',
    'assigned'
  ) then
    return false;
  end if;

  return (
    p_opportunity_id is not null
    and private.user_can_view_opportunity(v_actor_user_id, p_opportunity_id)
  ) or (
    p_project_id is not null
    and private.user_can_view_project(v_actor_user_id, p_project_id)
  );
end;
$function$;

create or replace function private.current_user_can_edit_deck_design(
  p_company_id uuid,
  p_opportunity_id uuid,
  p_project_id uuid,
  p_permission text
)
returns boolean
language plpgsql
stable
security definer
set search_path to 'pg_catalog', 'public', 'private', 'pg_temp'
as $function$
declare
  v_actor_user_id uuid := private.get_current_user_id();
  v_project_is_live boolean;
  v_opportunity_is_live boolean;
begin
  if p_permission not in ('deck_builder.create', 'deck_builder.edit')
    or private.get_user_company_id() is distinct from p_company_id
  then
    return false;
  end if;

  if public.has_permission(v_actor_user_id, p_permission, 'all') then
    -- Keep parent references inside the row's company. A soft-deleted parent
    -- remains a valid historical reference for edits, but a missing or
    -- cross-company parent is never accepted.
    if p_project_id is not null then
      select p.deleted_at is null
        into v_project_is_live
        from public.projects p
       where p.id = p_project_id
         and p.company_id = p_company_id;

      if not found then
        return false;
      end if;
    end if;

    if p_opportunity_id is not null then
      select o.deleted_at is null
        into v_opportunity_is_live
        from public.opportunities o
       where o.id = p_opportunity_id
         and o.company_id = p_company_id;

      if not found then
        return false;
      end if;
    end if;

    -- New designs may only be attached to live parents. Existing designs may
    -- still be edited after a parent is soft-deleted.
    if p_permission = 'deck_builder.create'
      and (
        (p_project_id is not null and not v_project_is_live)
        or (p_opportunity_id is not null and not v_opportunity_is_live)
      )
    then
      return false;
    end if;

    -- Preserve the live project/opportunity linkage invariant. Historical
    -- rows with a soft-deleted parent can still be opened and repaired.
    if p_opportunity_id is not null
      and p_project_id is not null
      and coalesce(v_opportunity_is_live, false)
      and coalesce(v_project_is_live, false)
      and not private.opportunity_project_relationship_is_valid(
        p_company_id,
        p_opportunity_id,
        p_project_id
      )
    then
      return false;
    end if;

    return true;
  end if;

  -- Assigned-scope users retain the original strict parent and assignment
  -- checks.
  if p_opportunity_id is not null
    and p_project_id is not null
    and not private.opportunity_project_relationship_is_valid(
      p_company_id,
      p_opportunity_id,
      p_project_id
    )
  then
    return false;
  end if;

  if p_opportunity_id is null and p_project_id is null then
    return false;
  end if;

  if not public.has_permission(
    v_actor_user_id,
    p_permission,
    'assigned'
  ) then
    return false;
  end if;

  return (
    p_opportunity_id is not null
    and private.user_can_edit_opportunity(v_actor_user_id, p_opportunity_id)
  ) or (
    p_project_id is not null
    and private.user_can_view_project(v_actor_user_id, p_project_id)
    and private.user_can_edit_project(v_actor_user_id, p_project_id)
  );
end;
$function$;

comment on function private.current_user_can_view_deck_design(uuid, uuid, uuid) is
  'RLS helper for deck_designs SELECT. All-scope users may view all same-company designs, including historical rows with soft-deleted parents; assigned users remain parent-scoped.';

comment on function private.current_user_can_edit_deck_design(uuid, uuid, uuid, text) is
  'RLS helper for deck_designs INSERT/UPDATE. Enforces tenant-safe parent references while allowing all-scope users to edit historical rows whose same-company parent was soft-deleted.';
