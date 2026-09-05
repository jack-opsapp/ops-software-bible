-- project_tasks soft-delete moves behind definer-owned RPCs.
--
-- Defect (web bug found 2026-09-01 during TASK GROUPS Phase 4 verification):
-- deleting a task from OPS-Web returned PostgREST 403 and the row stayed live,
-- with nothing shown to the user.
--
-- Root cause, proven 2026-09-02 by rolled-back probe on prod as the Maverick
-- admin (tasks.edit all). Since ledger 20260818014340
-- (project_tasks_returning_visibility) role_scope_read judges the row's own
-- columns and is false for any row with deleted_at set. Postgres attaches
-- SELECT policies as WITH CHECK options to every UPDATE whose target requires
-- ACL_SELECT (rowsecurity.c) — and `where id = $1` requires it — so
--   update project_tasks set updated_at = now() where id = $1   -> ok
--   update project_tasks set deleted_at = now() where id = $1   -> 42501
--   with pgrst_source as (update ... returning 1) select ...    -> 42501
-- RETURNING is irrelevant and `Prefer: return=minimal` does not help: no
-- client role can soft-delete a project task through PostgREST at all.
-- Before 2026-08-18 the by-id policy re-fetched the OLD row (deleted_at null)
-- under the statement snapshot, which is the only reason soft-deletes passed.
--
-- Broken callers: ops-web TaskService.deleteTask (single task),
-- ops-web RecurrenceService.softDelete (future occurrences of a series — the
-- template PATCH succeeded first, stranding the occurrences), and iOS
-- TaskRepository.softDelete (OutboundProcessor projectTask delete). The
-- 2026-08-18 shipped-client audit ("iOS soft-deletes are minimal-returning so
-- the deleted arm cannot bite; web does not write project_tasks via
-- PostgREST") was wrong on both counts.
--
-- Fix: RLS is untouched — no policy change, no weaker reads. Soft-delete runs
-- inside SECURITY DEFINER functions owned by postgres (table owner, bypassrls)
-- so the WITH CHECK never applies, and authorization is enforced explicitly
-- with private.user_can_edit_task — the same ladder role_scope_update
-- expresses (active same-company actor, live parent project, tasks.edit all,
-- or tasks.edit assigned + team/project membership; admins pass inside
-- public.has_permission). Who may delete is unchanged. Row triggers (schedule
-- version, parent-lifecycle guard, project team recompute, agent read
-- revisions, reminders) fire exactly as they did for the PATCH.
--
-- Shape mirrors update_task_with_event: an actor-parameterised core in
-- private (postgres-only) and a JWT-resolving wrapper in public granted to
-- anon + authenticated (the app executes as anon under the Firebase JWT
-- bridge). Behavioral contract: ops-web tests/sql/soft-delete-project-task-rpc-contract.sql.

create or replace function private.soft_delete_project_task_for_actor(
  p_actor_user_id uuid,
  p_task_id uuid
) returns jsonb
language plpgsql security definer
set search_path to 'pg_catalog', 'public', 'private', 'pg_temp'
as $fn$
declare
  v_company_id uuid;
  v_task public.project_tasks;
  v_previous_actor text := current_setting('ops.task_mutation_actor_id', true);
begin
  if p_actor_user_id is null or p_task_id is null then
    raise exception 'task_delete_forbidden' using errcode = '42501';
  end if;

  select actor.company_id into v_company_id
  from public.users actor
  where actor.id = p_actor_user_id
    and actor.deleted_at is null
    and coalesce(actor.is_active, false);
  if not found or v_company_id is null then
    raise exception 'task_delete_forbidden' using errcode = '42501';
  end if;
  perform private.lock_lead_assignment_company(v_company_id);

  -- Company-scoped lookup: a foreign or unknown task is refused, never
  -- disclosed as "already deleted".
  select task.* into v_task
  from public.project_tasks task
  where task.id = p_task_id
    and task.company_id = v_company_id
  for update;
  if not found then
    raise exception 'task_delete_forbidden' using errcode = '42501';
  end if;

  -- Idempotent: a second delete (two operators, a retried sync op) is done.
  if v_task.deleted_at is not null then
    return jsonb_build_object(
      'ok', true,
      'deleted', false,
      'task_id', p_task_id,
      'deleted_at', v_task.deleted_at
    );
  end if;

  if not private.user_can_edit_task(p_actor_user_id, p_task_id) then
    raise exception 'task_delete_forbidden' using errcode = '42501';
  end if;

  perform set_config('ops.task_mutation_actor_id', p_actor_user_id::text, true);
  begin
    update public.project_tasks task
    set deleted_at = now(),
        updated_at = now()
    where task.id = p_task_id
    returning task.* into v_task;
  exception when others then
    perform set_config(
      'ops.task_mutation_actor_id',
      coalesce(v_previous_actor, ''),
      true
    );
    raise;
  end;
  perform set_config(
    'ops.task_mutation_actor_id',
    coalesce(v_previous_actor, ''),
    true
  );

  return jsonb_build_object(
    'ok', true,
    'deleted', true,
    'task_id', p_task_id,
    'deleted_at', v_task.deleted_at
  );
end;
$fn$;

create or replace function public.soft_delete_project_task(p_task_id uuid)
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
  return private.soft_delete_project_task_for_actor(v_actor_user_id, p_task_id);
end;
$fn$;

create or replace function private.soft_delete_task_recurrence_for_actor(
  p_actor_user_id uuid,
  p_recurrence_id uuid
) returns jsonb
language plpgsql security definer
set search_path to 'pg_catalog', 'public', 'private', 'pg_temp'
as $fn$
declare
  v_company_id uuid;
  v_recurrence public.task_recurrences;
  v_task record;
  v_now timestamptz := now();
  v_recurrence_deleted boolean := false;
  v_deleted_count integer := 0;
  v_skipped_count integer := 0;
  v_previous_actor text := current_setting('ops.task_mutation_actor_id', true);
begin
  if p_actor_user_id is null or p_recurrence_id is null then
    raise exception 'task_recurrence_delete_forbidden' using errcode = '42501';
  end if;

  select actor.company_id into v_company_id
  from public.users actor
  where actor.id = p_actor_user_id
    and actor.deleted_at is null
    and coalesce(actor.is_active, false);
  if not found or v_company_id is null then
    raise exception 'task_recurrence_delete_forbidden' using errcode = '42501';
  end if;
  perform private.lock_lead_assignment_company(v_company_id);

  select recurrence.* into v_recurrence
  from public.task_recurrences recurrence
  where recurrence.id = p_recurrence_id
    and recurrence.company_id = v_company_id
  for update;
  if not found then
    raise exception 'task_recurrence_delete_forbidden' using errcode = '42501';
  end if;

  perform set_config('ops.task_mutation_actor_id', p_actor_user_id::text, true);
  begin
    -- The template is company-scoped (task_recurrences carries only company
    -- isolation), exactly as the PATCH it replaces.
    if v_recurrence.deleted_at is null then
      update public.task_recurrences recurrence
      set deleted_at = v_now,
          updated_at = v_now
      where recurrence.id = p_recurrence_id;
      v_recurrence_deleted := true;
    end if;

    -- Future, still-active occurrences retire; past, in-progress, and
    -- completed occurrences stay as history. Occurrences the actor may not
    -- edit are skipped, as row security skipped them before.
    for v_task in
      select task.id
      from public.project_tasks task
      where task.recurrence_id = p_recurrence_id
        and task.company_id = v_company_id
        and task.deleted_at is null
        and task.status = 'active'
        and task.start_date > v_now
      order by task.id
      for update
    loop
      if private.user_can_edit_task(p_actor_user_id, v_task.id) then
        update public.project_tasks task
        set deleted_at = v_now,
            updated_at = v_now
        where task.id = v_task.id;
        v_deleted_count := v_deleted_count + 1;
      else
        v_skipped_count := v_skipped_count + 1;
      end if;
    end loop;
  exception when others then
    perform set_config(
      'ops.task_mutation_actor_id',
      coalesce(v_previous_actor, ''),
      true
    );
    raise;
  end;
  perform set_config(
    'ops.task_mutation_actor_id',
    coalesce(v_previous_actor, ''),
    true
  );

  return jsonb_build_object(
    'ok', true,
    'recurrence_id', p_recurrence_id,
    'recurrence_deleted', v_recurrence_deleted,
    'deleted_count', v_deleted_count,
    'skipped_count', v_skipped_count
  );
end;
$fn$;

create or replace function public.soft_delete_task_recurrence(p_recurrence_id uuid)
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
  return private.soft_delete_task_recurrence_for_actor(v_actor_user_id, p_recurrence_id);
end;
$fn$;

revoke all on function private.soft_delete_project_task_for_actor(uuid, uuid) from public, anon, authenticated;
revoke all on function private.soft_delete_task_recurrence_for_actor(uuid, uuid) from public, anon, authenticated;
revoke all on function public.soft_delete_project_task(uuid) from public;
grant execute on function public.soft_delete_project_task(uuid) to anon, authenticated;
revoke all on function public.soft_delete_task_recurrence(uuid) from public;
grant execute on function public.soft_delete_task_recurrence(uuid) to anon, authenticated;
