-- Scope check-off / uncheck with the status law enforced in one transaction:
--   * the last open scope checked off completes the parent task through
--     complete_project_task (materials consumed exactly once, idempotency-keyed);
--   * unchecking a scope on a completed task reopens the task (materials stay consumed);
--   * optimistic concurrency mirrors update_task_with_event: a stale
--     p_expected_updated_at returns {ok:false, conflict:true} rather than raising.
-- Permission = the completion gate complete_project_task already uses; reopening a
-- completed task additionally requires the task status-change permission.
create or replace function public.set_task_scope_completion(
  p_scope_id uuid,
  p_completed boolean,
  p_expected_updated_at timestamptz default null,
  p_idempotency_key text default null
) returns jsonb
language plpgsql
security definer
set search_path to 'public', 'private', 'pg_temp'
as $$
declare
  v_now timestamptz := now();
  v_actor uuid;
  v_company_id uuid;
  v_task public.project_tasks%rowtype;
  v_scope public.task_scopes%rowtype;
  v_open integer;
  v_auto_completed boolean := false;
  v_completion jsonb;
begin
  if auth.role() not in ('anon', 'authenticated') then
    raise exception 'access_denied' using errcode = '42501';
  end if;
  if p_scope_id is null or p_completed is null then
    raise exception 'scope_id_and_completed_required' using errcode = '22023';
  end if;
  if nullif(btrim(coalesce(p_idempotency_key, '')), '') is null then
    raise exception 'idempotency_key_required' using errcode = '22023';
  end if;

  v_actor := private.get_current_user_id();
  v_company_id := private.get_user_company_id();
  if v_actor is null or v_company_id is null then
    raise exception 'actor_company_not_found' using errcode = '42501';
  end if;

  -- Lock the parent task first, then the scope (same order as complete_project_task).
  select t.*
    into v_task
    from public.project_tasks t
   where t.id = (select s.task_id from public.task_scopes s where s.id = p_scope_id)
     and t.deleted_at is null
     for update;
  if not found then
    raise exception 'scope_not_found' using errcode = 'P0002';
  end if;

  select s.*
    into v_scope
    from public.task_scopes s
   where s.id = p_scope_id
     and s.deleted_at is null
     for update;
  if not found then
    raise exception 'scope_not_found' using errcode = 'P0002';
  end if;

  if v_task.company_id is distinct from v_company_id
     or v_scope.company_id is distinct from v_company_id then
    raise exception 'task_company_scope_mismatch' using errcode = '42501';
  end if;

  -- A scope check-off is a completion act: same gate as complete_project_task.
  perform set_config('ops.complete_project_task_rpc', 'on', true);
  if not private.current_user_can_complete_task_material_consumption(v_company_id, v_task.id) then
    raise exception 'tasks_edit_required' using errcode = '42501';
  end if;

  if p_expected_updated_at is not null
     and v_scope.updated_at is distinct from p_expected_updated_at then
    return jsonb_build_object(
      'ok', false,
      'conflict', true,
      'scope_id', p_scope_id,
      'completed', v_scope.completed_at is not null,
      'updated_at', v_scope.updated_at,
      'task_status', v_task.status
    );
  end if;

  if p_completed then
    if v_scope.completed_at is null then
      update public.task_scopes
         set completed_at = v_now,
             completed_by = v_actor,
             updated_at = v_now
       where id = p_scope_id;
    end if;

    select count(*)
      into v_open
      from public.task_scopes s
     where s.task_id = v_task.id
       and s.deleted_at is null
       and s.completed_at is null;

    if v_open = 0 and v_task.status <> 'completed' then
      v_completion := public.complete_project_task(v_task.id, p_idempotency_key, '{}'::jsonb);
      v_auto_completed := true;
    end if;
  else
    if v_task.status = 'completed'
       and not private.user_can_change_task_status(v_actor, v_task.id) then
      raise exception 'task_status_forbidden' using errcode = '42501';
    end if;

    if v_scope.completed_at is not null then
      update public.task_scopes
         set completed_at = null,
             completed_by = null,
             updated_at = v_now
       where id = p_scope_id;
    end if;

    if v_task.status = 'completed' then
      update public.project_tasks
         set status = 'active',
             updated_at = v_now
       where id = v_task.id;
    end if;
  end if;

  select t.status into v_task.status from public.project_tasks t where t.id = v_task.id;
  select s.* into v_scope from public.task_scopes s where s.id = p_scope_id;

  return jsonb_build_object(
    'ok', true,
    'conflict', false,
    'scope_id', p_scope_id,
    'completed', v_scope.completed_at is not null,
    'completed_at', v_scope.completed_at,
    'completed_by', v_scope.completed_by,
    'updated_at', v_scope.updated_at,
    'task_status', v_task.status,
    'task_auto_completed', v_auto_completed
  ) || case when v_completion is null then '{}'::jsonb else jsonb_build_object('completion', v_completion) end;
end;
$$;
grant execute on function public.set_task_scope_completion(uuid, boolean, timestamptz, text) to authenticated, anon;
notify pgrst, 'reload schema';
