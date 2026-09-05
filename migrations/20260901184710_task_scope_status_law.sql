-- Status law: completing a task (by ANY write path — RPC, direct web update, agent)
-- stamps every open scope in the same transaction. Reopening leaves stamps in place.
create or replace function private.stamp_scopes_on_task_completion() returns trigger
language plpgsql security definer set search_path to 'public','private','pg_temp' as $$
begin
  if new.status = 'completed' and old.status is distinct from 'completed' then
    update public.task_scopes
       set completed_at = coalesce(completed_at, now()),
           completed_by = coalesce(completed_by, private.get_current_user_id()),
           updated_at = now()
     where task_id = new.id and deleted_at is null and completed_at is null;
  end if;
  return new;
end $$;
create trigger project_tasks_stamp_scopes_on_completion after update of status
  on public.project_tasks for each row execute function private.stamp_scopes_on_task_completion();
