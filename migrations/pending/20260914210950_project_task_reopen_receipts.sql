-- Scheduling on an explicitly archived project carries one durable reopen
-- command. This is separate from task PATCHes: stale offline schedules never
-- acquire permission to reopen a project as a trigger side effect.
create table private.project_task_reopen_receipts (
  command_id uuid primary key,
  actor_user_id uuid not null references public.users(id) on delete cascade,
  company_id uuid not null references public.companies(id) on delete cascade,
  project_id uuid not null references public.projects(id) on delete cascade,
  expected_updated_at timestamptz not null,
  target_status text not null check (target_status in ('accepted', 'in_progress')),
  result_updated_at timestamptz not null,
  created_at timestamptz not null default clock_timestamp()
);
create index project_task_reopen_receipts_actor_idx
  on private.project_task_reopen_receipts(actor_user_id);
create index project_task_reopen_receipts_company_idx
  on private.project_task_reopen_receipts(company_id);
create index project_task_reopen_receipts_project_idx
  on private.project_task_reopen_receipts(project_id);
alter table private.project_task_reopen_receipts enable row level security;
revoke all on table private.project_task_reopen_receipts
  from public, anon, authenticated, service_role;

create function public.reopen_project_for_task(
  p_command_id uuid,
  p_project_id uuid,
  p_expected_updated_at timestamptz,
  p_target_status text
) returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog', 'public', 'private', 'pg_temp'
as $function$
declare
  v_actor_user_id uuid := private.get_current_user_id();
  v_company_id uuid := private.get_user_company_id();
  v_project public.projects%rowtype;
  v_receipt private.project_task_reopen_receipts%rowtype;
  v_updated_at timestamptz;
begin
  if coalesce(auth.role(), '') not in ('anon', 'authenticated')
     or v_actor_user_id is null or v_company_id is null then
    raise exception 'project_reopen_forbidden' using errcode = '42501';
  end if;
  if p_command_id is null or p_project_id is null
     or p_expected_updated_at is null or not isfinite(p_expected_updated_at)
     or p_target_status is null
     or p_target_status not in ('accepted', 'in_progress') then
    raise exception 'invalid_project_reopen_command' using errcode = '22023';
  end if;

  -- Same authority order as change_project_status: company advisory lock,
  -- company and actor rows, then the project. Existing status triggers keep
  -- their nonblocking provider/address identity locks and outbox attribution.
  perform private.lock_lead_assignment_company(v_company_id);
  perform 1 from public.companies company where company.id = v_company_id for share;
  if not found then
    raise exception 'project_reopen_forbidden' using errcode = '42501';
  end if;
  perform 1 from public.users actor
   where actor.id = v_actor_user_id
     and actor.company_id = v_company_id
     and actor.deleted_at is null and coalesce(actor.is_active, false)
   for share;
  if not found or not private.user_can_edit_project(v_actor_user_id, p_project_id) then
    raise exception 'project_reopen_forbidden' using errcode = '42501';
  end if;
  perform pg_advisory_xact_lock(hashtextextended(
    'project-task-reopen:' || p_command_id::text, 14210950
  ));

  select * into v_project from public.projects
   where id = p_project_id and company_id = v_company_id and deleted_at is null
   for update;
  if not found or not private.user_can_edit_project(v_actor_user_id, p_project_id) then
    raise exception 'project_reopen_forbidden' using errcode = '42501';
  end if;

  select * into v_receipt from private.project_task_reopen_receipts
   where command_id = p_command_id;
  if found then
    if v_receipt.actor_user_id is distinct from v_actor_user_id
       or v_receipt.company_id is distinct from v_company_id
       or v_receipt.project_id is distinct from p_project_id
       or v_receipt.expected_updated_at is distinct from p_expected_updated_at
       or v_receipt.target_status is distinct from p_target_status then
      raise exception 'project_reopen_command_conflict' using errcode = '22023';
    end if;
    -- This is historical proof, never a current-state projection. In
    -- particular a retry MUST NOT undo a later archive or status decision.
    return jsonb_build_object(
      'command_id', p_command_id, 'project_id', p_project_id,
      'company_id', v_company_id, 'status', v_receipt.target_status,
      'updated_at', v_receipt.result_updated_at, 'changed', true, 'replayed', true
    );
  end if;

  if v_project.status is distinct from 'archived'
     or v_project.updated_at is distinct from p_expected_updated_at then
    raise exception 'project_reopen_snapshot_conflict' using errcode = 'P0001';
  end if;
  update public.projects set status = p_target_status
   where id = p_project_id and company_id = v_company_id
   returning updated_at into v_updated_at;
  insert into private.project_task_reopen_receipts(
    command_id, actor_user_id, company_id, project_id,
    expected_updated_at, target_status, result_updated_at
  ) values (
    p_command_id, v_actor_user_id, v_company_id, p_project_id,
    p_expected_updated_at, p_target_status, v_updated_at
  );
  return jsonb_build_object(
    'command_id', p_command_id, 'project_id', p_project_id,
    'company_id', v_company_id, 'status', p_target_status,
    'updated_at', v_updated_at, 'changed', true, 'replayed', false
  );
end;
$function$;
revoke all on function public.reopen_project_for_task(uuid, uuid, timestamptz, text)
  from public, anon, authenticated, service_role;
-- The Firebase bridge uses anon with a resolvable signed-in actor. The body
-- always requires that actor and the canonical active-company edit scope.
grant execute on function public.reopen_project_for_task(uuid, uuid, timestamptz, text)
  to anon, authenticated;
