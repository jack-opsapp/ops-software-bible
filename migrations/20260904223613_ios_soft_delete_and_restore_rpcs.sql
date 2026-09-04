-- iOS soft-delete and restore move behind definer-owned RPCs.
-- Bugs 2a55c78f (client deletion, observed on the founder's phone 2026-09-04
-- 17:15 UTC as two sync_parked rows carrying "new row violates row-level
-- security policy role_scope_read" for clients) and db15baf2 (iOS twin of the
-- web task-delete 403 fixed in ledger 20260902160624).
--
-- Root cause class: Postgres attaches SELECT policies as WITH CHECK options to
-- every UPDATE whose target requires ACL_SELECT, and `where id = $1` requires
-- it. On clients/projects/project_tasks the RESTRICTIVE SELECT policy judges
-- the row's own deleted_at, so no client role can set OR clear deleted_at
-- through PostgREST: setting it raises 42501; clearing it matches zero rows
-- silently, because the tombstoned row is invisible to the USING clause.
--
-- RLS is untouched. Both directions run inside SECURITY DEFINER functions owned
-- by postgres so the WITH CHECK never applies, and authorization is re-stated
-- explicitly. Row triggers fire exactly as they did for the PATCH — including
-- public.enforce_project_opportunity_link, which still reads the caller's JWT
-- and still demands pipeline.manage 'all' to mutate an opportunity-linked
-- project's link contract, in BOTH directions.
--
-- Ladder choice, deliberate: the client and project RPCs require the table's
-- delete permission at scope 'all', matching what each table's
-- role_scope_delete policy already demands for a hard delete. Restore ladders
-- are written out inline because private.user_can_edit_task and
-- user_can_edit_project both filter `deleted_at is null` and would refuse every
-- restore.

create or replace function private.soft_delete_client_for_actor(
  p_actor_user_id uuid,
  p_client_id uuid
)
returns jsonb
language plpgsql security definer
set search_path to 'pg_catalog', 'public', 'private', 'pg_temp'
as $fn$
declare
  v_company_id uuid;
  v_client public.clients;
begin
  if p_actor_user_id is null or p_client_id is null then
    raise exception 'client_delete_forbidden' using errcode = '42501';
  end if;

  select actor.company_id into v_company_id
  from public.users actor
  where actor.id = p_actor_user_id
    and actor.deleted_at is null
    and coalesce(actor.is_active, false);
  if not found or v_company_id is null then
    raise exception 'client_delete_forbidden' using errcode = '42501';
  end if;

  -- Company-scoped lookup: a foreign or unknown client is refused, never
  -- disclosed as "already deleted".
  select c.* into v_client
  from public.clients c
  where c.id = p_client_id
    and c.company_id = v_company_id
  for update;
  if not found then
    raise exception 'client_delete_forbidden' using errcode = '42501';
  end if;

  -- Idempotent: a second delete (two operators, a retried sync op) is done.
  if v_client.deleted_at is not null then
    return jsonb_build_object(
      'ok', true,
      'deleted', false,
      'client_id', p_client_id,
      'deleted_at', v_client.deleted_at
    );
  end if;

  -- Same ladder public.clients.role_scope_delete expresses for a hard delete.
  if not public.has_permission(p_actor_user_id, 'clients.delete', 'all') then
    raise exception 'client_delete_forbidden' using errcode = '42501';
  end if;

  update public.clients c
  set deleted_at = now(),
      updated_at = now()
  where c.id = p_client_id
  returning c.* into v_client;

  return jsonb_build_object(
    'ok', true,
    'deleted', true,
    'client_id', p_client_id,
    'deleted_at', v_client.deleted_at
  );
end;
$fn$;

create or replace function public.soft_delete_client(p_client_id uuid)
returns jsonb
language plpgsql security definer
set search_path to 'pg_catalog', 'public', 'private', 'pg_temp'
as $fn$
declare
  v_actor_user_id uuid;
begin
  if auth.role() not in ('anon', 'authenticated') then
    raise exception 'access_denied' using errcode = '42501';
  end if;
  v_actor_user_id := private.get_current_user_id();
  if v_actor_user_id is null then
    raise exception 'access_denied' using errcode = '42501';
  end if;
  return private.soft_delete_client_for_actor(v_actor_user_id, p_client_id);
end;
$fn$;

create or replace function private.restore_client_for_actor(
  p_actor_user_id uuid,
  p_client_id uuid
)
returns jsonb
language plpgsql security definer
set search_path to 'pg_catalog', 'public', 'private', 'pg_temp'
as $fn$
declare
  v_company_id uuid;
  v_client public.clients;
begin
  if p_actor_user_id is null or p_client_id is null then
    raise exception 'client_restore_forbidden' using errcode = '42501';
  end if;

  select actor.company_id into v_company_id
  from public.users actor
  where actor.id = p_actor_user_id
    and actor.deleted_at is null
    and coalesce(actor.is_active, false);
  if not found or v_company_id is null then
    raise exception 'client_restore_forbidden' using errcode = '42501';
  end if;

  select c.* into v_client
  from public.clients c
  where c.id = p_client_id
    and c.company_id = v_company_id
  for update;
  if not found then
    raise exception 'client_restore_forbidden' using errcode = '42501';
  end if;

  -- Restore is symmetric with delete: whoever may delete may put it back.
  if not public.has_permission(p_actor_user_id, 'clients.delete', 'all') then
    raise exception 'client_restore_forbidden' using errcode = '42501';
  end if;

  -- Idempotent: restoring a live client is a no-op success.
  if v_client.deleted_at is null then
    return jsonb_build_object(
      'ok', true, 'restored', false, 'client_id', p_client_id
    );
  end if;

  update public.clients c
  set deleted_at = null,
      updated_at = now()
  where c.id = p_client_id;

  return jsonb_build_object(
    'ok', true, 'restored', true, 'client_id', p_client_id
  );
end;
$fn$;

create or replace function public.restore_client(p_client_id uuid)
returns jsonb
language plpgsql security definer
set search_path to 'pg_catalog', 'public', 'private', 'pg_temp'
as $fn$
declare
  v_actor_user_id uuid;
begin
  if auth.role() not in ('anon', 'authenticated') then
    raise exception 'access_denied' using errcode = '42501';
  end if;
  v_actor_user_id := private.get_current_user_id();
  if v_actor_user_id is null then
    raise exception 'access_denied' using errcode = '42501';
  end if;
  return private.restore_client_for_actor(v_actor_user_id, p_client_id);
end;
$fn$;

create or replace function private.soft_delete_project_for_actor(
  p_actor_user_id uuid,
  p_project_id uuid
)
returns jsonb
language plpgsql security definer
set search_path to 'pg_catalog', 'public', 'private', 'pg_temp'
as $fn$
declare
  v_company_id uuid;
  v_project public.projects;
begin
  if p_actor_user_id is null or p_project_id is null then
    raise exception 'project_delete_forbidden' using errcode = '42501';
  end if;

  select actor.company_id into v_company_id
  from public.users actor
  where actor.id = p_actor_user_id
    and actor.deleted_at is null
    and coalesce(actor.is_active, false);
  if not found or v_company_id is null then
    raise exception 'project_delete_forbidden' using errcode = '42501';
  end if;
  perform private.lock_lead_assignment_company(v_company_id);

  select p.* into v_project
  from public.projects p
  where p.id = p_project_id
    and p.company_id = v_company_id
  for update;
  if not found then
    raise exception 'project_delete_forbidden' using errcode = '42501';
  end if;

  if v_project.deleted_at is not null then
    return jsonb_build_object(
      'ok', true,
      'deleted', false,
      'project_id', p_project_id,
      'deleted_at', v_project.deleted_at
    );
  end if;

  if not public.has_permission(p_actor_user_id, 'projects.delete', 'all') then
    raise exception 'project_delete_forbidden' using errcode = '42501';
  end if;

  -- public.enforce_project_opportunity_link fires here on deleted_at and still
  -- demands pipeline.manage 'all' from the JWT caller for an opportunity-linked
  -- project. That invariant is deliberately left in force.
  update public.projects p
  set deleted_at = now(),
      updated_at = now()
  where p.id = p_project_id
  returning p.* into v_project;

  return jsonb_build_object(
    'ok', true,
    'deleted', true,
    'project_id', p_project_id,
    'deleted_at', v_project.deleted_at
  );
end;
$fn$;

create or replace function public.soft_delete_project(p_project_id uuid)
returns jsonb
language plpgsql security definer
set search_path to 'pg_catalog', 'public', 'private', 'pg_temp'
as $fn$
declare
  v_actor_user_id uuid;
begin
  if auth.role() not in ('anon', 'authenticated') then
    raise exception 'access_denied' using errcode = '42501';
  end if;
  v_actor_user_id := private.get_current_user_id();
  if v_actor_user_id is null then
    raise exception 'access_denied' using errcode = '42501';
  end if;
  return private.soft_delete_project_for_actor(v_actor_user_id, p_project_id);
end;
$fn$;

create or replace function private.restore_project_for_actor(
  p_actor_user_id uuid,
  p_project_id uuid
)
returns jsonb
language plpgsql security definer
set search_path to 'pg_catalog', 'public', 'private', 'pg_temp'
as $fn$
declare
  v_company_id uuid;
  v_project public.projects;
begin
  if p_actor_user_id is null or p_project_id is null then
    raise exception 'project_restore_forbidden' using errcode = '42501';
  end if;

  select actor.company_id into v_company_id
  from public.users actor
  where actor.id = p_actor_user_id
    and actor.deleted_at is null
    and coalesce(actor.is_active, false);
  if not found or v_company_id is null then
    raise exception 'project_restore_forbidden' using errcode = '42501';
  end if;
  perform private.lock_lead_assignment_company(v_company_id);

  select p.* into v_project
  from public.projects p
  where p.id = p_project_id
    and p.company_id = v_company_id
  for update;
  if not found then
    raise exception 'project_restore_forbidden' using errcode = '42501';
  end if;

  if not public.has_permission(p_actor_user_id, 'projects.delete', 'all') then
    raise exception 'project_restore_forbidden' using errcode = '42501';
  end if;

  if v_project.deleted_at is null then
    return jsonb_build_object(
      'ok', true, 'restored', false, 'project_id', p_project_id
    );
  end if;

  -- Clearing deleted_at also trips enforce_project_opportunity_link's
  -- link-contract check, so restoring an opportunity-linked project requires
  -- pipeline.manage 'all' from the JWT caller exactly as deleting it does.
  update public.projects p
  set deleted_at = null,
      updated_at = now()
  where p.id = p_project_id;

  return jsonb_build_object(
    'ok', true, 'restored', true, 'project_id', p_project_id
  );
end;
$fn$;

create or replace function public.restore_project(p_project_id uuid)
returns jsonb
language plpgsql security definer
set search_path to 'pg_catalog', 'public', 'private', 'pg_temp'
as $fn$
declare
  v_actor_user_id uuid;
begin
  if auth.role() not in ('anon', 'authenticated') then
    raise exception 'access_denied' using errcode = '42501';
  end if;
  v_actor_user_id := private.get_current_user_id();
  if v_actor_user_id is null then
    raise exception 'access_denied' using errcode = '42501';
  end if;
  return private.restore_project_for_actor(v_actor_user_id, p_project_id);
end;
$fn$;

-- project_tasks: restore only. The DELETE direction already shipped as ledger
-- 20260902160624 and is deliberately not redefined here.
create or replace function private.restore_project_task_for_actor(
  p_actor_user_id uuid,
  p_task_id uuid
)
returns jsonb
language plpgsql security definer
set search_path to 'pg_catalog', 'public', 'private', 'pg_temp'
as $fn$
declare
  v_company_id uuid;
  v_task public.project_tasks;
  v_parent_deleted timestamptz;
  v_allowed boolean := false;
  v_previous_actor text := current_setting('ops.task_mutation_actor_id', true);
begin
  if p_actor_user_id is null or p_task_id is null then
    raise exception 'task_restore_forbidden' using errcode = '42501';
  end if;

  select actor.company_id into v_company_id
  from public.users actor
  where actor.id = p_actor_user_id
    and actor.deleted_at is null
    and coalesce(actor.is_active, false);
  if not found or v_company_id is null then
    raise exception 'task_restore_forbidden' using errcode = '42501';
  end if;
  perform private.lock_lead_assignment_company(v_company_id);

  select task.* into v_task
  from public.project_tasks task
  where task.id = p_task_id
    and task.company_id = v_company_id
  for update;
  if not found then
    raise exception 'task_restore_forbidden' using errcode = '42501';
  end if;

  -- private.user_can_edit_task filters `deleted_at is null` and is therefore
  -- useless here; re-state the same ladder against the tombstoned row.
  if public.has_permission(p_actor_user_id, 'tasks.edit', 'all') then
    v_allowed := true;
  elsif public.has_permission(p_actor_user_id, 'tasks.edit', 'assigned') then
    v_allowed := (
      p_actor_user_id::text = any(
        coalesce(v_task.team_member_ids, array[]::text[])
      )
      or private.user_is_project_member_for_task(
        p_actor_user_id,
        v_task.company_id,
        v_task.project_id
      )
    );
  end if;
  if not v_allowed then
    raise exception 'task_restore_forbidden' using errcode = '42501';
  end if;

  if v_task.deleted_at is null then
    return jsonb_build_object(
      'ok', true, 'restored', false, 'task_id', p_task_id
    );
  end if;

  -- A live task under a tombstoned project is not a state this schema allows;
  -- the client stages parent-first, so this only fires on a malformed plan.
  select p.deleted_at into v_parent_deleted
  from public.projects p
  where p.id = v_task.project_id
    and p.company_id = v_company_id;
  if not found or v_parent_deleted is not null then
    raise exception 'parent_project_deleted' using errcode = '55000';
  end if;

  perform set_config('ops.task_mutation_actor_id', p_actor_user_id::text, true);
  begin
    update public.project_tasks task
    set deleted_at = null,
        updated_at = now()
    where task.id = p_task_id;
  exception when others then
    perform set_config(
      'ops.task_mutation_actor_id', coalesce(v_previous_actor, ''), true
    );
    raise;
  end;
  perform set_config(
    'ops.task_mutation_actor_id', coalesce(v_previous_actor, ''), true
  );

  return jsonb_build_object(
    'ok', true, 'restored', true, 'task_id', p_task_id
  );
end;
$fn$;

create or replace function public.restore_project_task(p_task_id uuid)
returns jsonb
language plpgsql security definer
set search_path to 'pg_catalog', 'public', 'private', 'pg_temp'
as $fn$
declare
  v_actor_user_id uuid;
begin
  if auth.role() not in ('anon', 'authenticated') then
    raise exception 'access_denied' using errcode = '42501';
  end if;
  v_actor_user_id := private.get_current_user_id();
  if v_actor_user_id is null then
    raise exception 'access_denied' using errcode = '42501';
  end if;
  return private.restore_project_task_for_actor(v_actor_user_id, p_task_id);
end;
$fn$;

-- ACLs. Supabase default privileges hand service_role EXECUTE on every new
-- public function, and `revoke ... from public` does NOT take that back — it is
-- an explicit grant, not the PUBLIC pseudo-role. Mirrors ledger 20260902161850.
revoke all on function private.soft_delete_client_for_actor(uuid, uuid)   from public, anon, authenticated;
revoke all on function private.restore_client_for_actor(uuid, uuid)       from public, anon, authenticated;
revoke all on function private.soft_delete_project_for_actor(uuid, uuid)  from public, anon, authenticated;
revoke all on function private.restore_project_for_actor(uuid, uuid)      from public, anon, authenticated;
revoke all on function private.restore_project_task_for_actor(uuid, uuid) from public, anon, authenticated;

revoke all on function public.soft_delete_client(uuid)   from public;
revoke all on function public.restore_client(uuid)       from public;
revoke all on function public.soft_delete_project(uuid)  from public;
revoke all on function public.restore_project(uuid)      from public;
revoke all on function public.restore_project_task(uuid) from public;

grant execute on function public.soft_delete_client(uuid)   to anon, authenticated;
grant execute on function public.restore_client(uuid)       to anon, authenticated;
grant execute on function public.soft_delete_project(uuid)  to anon, authenticated;
grant execute on function public.restore_project(uuid)      to anon, authenticated;
grant execute on function public.restore_project_task(uuid) to anon, authenticated;

revoke execute on function public.soft_delete_client(uuid)   from service_role;
revoke execute on function public.restore_client(uuid)       from service_role;
revoke execute on function public.soft_delete_project(uuid)  from service_role;
revoke execute on function public.restore_project(uuid)      from service_role;
revoke execute on function public.restore_project_task(uuid) from service_role;
