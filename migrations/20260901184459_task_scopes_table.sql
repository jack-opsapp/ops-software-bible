create table public.task_scopes (
  id uuid primary key,
  company_id uuid not null,
  task_id uuid not null references public.project_tasks(id) on delete cascade,
  task_type_id uuid not null references public.task_types(id),
  note text,
  display_order integer not null default 0,
  completed_at timestamptz,
  completed_by uuid,
  source_line_item_id text,
  split_to_task_id uuid references public.project_tasks(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);
create index task_scopes_task_id_idx on public.task_scopes(task_id) where deleted_at is null;
create index task_scopes_company_id_idx on public.task_scopes(company_id);

alter table public.task_scopes enable row level security;

-- Read: visible iff the parent task is visible (mirrors project_tasks role_scope_read).
create policy scope_read on public.task_scopes for select using (
  exists (select 1 from public.project_tasks t where t.id = task_scopes.task_id
    and private.current_user_can_view_task_row(t.company_id, t.project_id, t.team_member_ids, t.deleted_at))
);
-- Writes: company isolation + the parent task's edit rule (admin OR tasks.edit scope-aware).
create policy scope_write on public.task_scopes for all using (
  company_id = (select private.get_user_company_id())
  and exists (select 1 from public.project_tasks t where t.id = task_scopes.task_id
    and t.deleted_at is null
    and (private.current_user_is_admin() or
      case private.current_user_scope_for('tasks.edit')
        when 'all' then true
        when 'assigned' then ((private.get_current_user_id())::text = any(coalesce(t.team_member_ids, array[]::text[]))
                              or private.current_user_in_project(t.project_id))
        else false end))
) with check (
  company_id = (select private.get_user_company_id())
);

-- Guards: parent task alive + same company; type same company + not deleted (mirrors
-- private.guard_project_task_task_type_reference).
create or replace function private.guard_task_scope_refs() returns trigger
language plpgsql security definer set search_path to 'public','private','pg_temp' as $$
declare v_task public.project_tasks%rowtype;
begin
  select * into v_task from public.project_tasks where id = new.task_id;
  if not found or v_task.deleted_at is not null then
    raise exception 'scope_parent_task_missing' using errcode = '23503';
  end if;
  if v_task.company_id <> new.company_id then
    raise exception 'scope_company_mismatch' using errcode = '42501';
  end if;
  if not exists (select 1 from public.task_types tt where tt.id = new.task_type_id
                 and tt.company_id = new.company_id and tt.deleted_at is null) then
    raise exception 'scope_task_type_invalid' using errcode = '23503';
  end if;
  return new;
end $$;
create trigger task_scopes_guard_refs before insert or update of task_id, task_type_id, company_id
  on public.task_scopes for each row execute function private.guard_task_scope_refs();

create trigger update_task_scopes_timestamp before update on public.task_scopes
  for each row execute function update_timestamp();
-- Agent read-domain freshness (same as project_tasks):
create trigger task_scopes_bump_agent_task_revision after insert or delete or update
  on public.task_scopes for each row
  execute function private.bump_agent_read_domain_revision('tasks', 'company_id');
