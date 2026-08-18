-- project_tasks INSERT..RETURNING self-void fix (bug filed 2026-08-17: "iOS task
-- creation can void itself"). role_scope_read (RESTRICTIVE SELECT) called
-- private.current_user_can_view_task(id), which re-fetches the task row by id.
-- During the INSERT's own RETURNING evaluation that re-fetch runs under the
-- statement snapshot, where the new row does not exist yet -> not found ->
-- false -> 42501 for EVERY PostgREST insert with return=representation (iOS
-- TaskRepository.create uses .insert().select().single()), regardless of the
-- actor's permissions. Proven by rolled-back probe: identical insert succeeds
-- without RETURNING and the very next command's SELECT passes the same policy.
--
-- Fix: evaluate the policy against the candidate row's own columns instead of
-- re-fetching. private.user_can_view_task_columns mirrors
-- private.user_can_view_task exactly (deleted hidden; live same-company
-- project required; active same-company actor required; tasks.view all ->
-- true; tasks.view assigned -> membership or project visibility) but takes
-- the row's columns as arguments, so the new tuple is judged directly.
-- Parity proven on real data pre-apply: 1,383 task x user comparisons
-- (owner + two crew, incl. soft-deleted + foreign-company tasks), 0 mismatches.
-- The by-id functions stay untouched for their existing callers
-- (persist_task_mutation_notification_as_system, agent_user_can_access_entity).
--
-- Shipped-client audit: iOS updates/soft-deletes are minimal-returning, so the
-- deleted-hidden arm can never bite an echo; web does not write project_tasks
-- via PostgREST. An UPDATE that sets deleted_at AND requests representation
-- would now (correctly) refuse the echo of a row the actor can no longer see.

create or replace function private.user_can_view_task_columns(
  p_actor_user_id uuid,
  p_company_id uuid,
  p_project_id uuid,
  p_team_member_ids text[],
  p_deleted_at timestamptz
) returns boolean
language plpgsql stable security definer
set search_path to 'pg_catalog','public','private','pg_temp'
as $fn$
begin
  if p_deleted_at is not null then
    return false;
  end if;
  if not exists (
    select 1 from public.projects project
    where project.id = p_project_id
      and project.company_id = p_company_id
      and project.deleted_at is null
  ) then
    return false;
  end if;
  if not exists (
    select 1 from public.users actor
    where actor.id = p_actor_user_id
      and actor.company_id = p_company_id
      and actor.deleted_at is null
      and coalesce(actor.is_active, false)
  ) then
    return false;
  end if;
  if public.has_permission(p_actor_user_id, 'tasks.view', 'all') then
    return true;
  end if;
  return public.has_permission(p_actor_user_id, 'tasks.view', 'assigned') and (
    p_actor_user_id::text = any(coalesce(p_team_member_ids, array[]::text[]))
    or private.user_can_view_project(p_actor_user_id, p_project_id)
  );
end;
$fn$;

create or replace function private.current_user_can_view_task_row(
  p_company_id uuid,
  p_project_id uuid,
  p_team_member_ids text[],
  p_deleted_at timestamptz
) returns boolean
language sql stable security definer
set search_path to 'pg_catalog','public','private','pg_temp'
as $fn$
  select private.user_can_view_task_columns(
    private.get_current_user_id(), p_company_id, p_project_id, p_team_member_ids, p_deleted_at
  );
$fn$;

revoke all on function private.user_can_view_task_columns(uuid, uuid, uuid, text[], timestamptz) from public, anon, authenticated;
revoke all on function private.current_user_can_view_task_row(uuid, uuid, text[], timestamptz) from public;
grant execute on function private.current_user_can_view_task_row(uuid, uuid, text[], timestamptz) to anon, authenticated;

alter policy role_scope_read on public.project_tasks
  using (private.current_user_can_view_task_row(company_id, project_id, team_member_ids, deleted_at));
