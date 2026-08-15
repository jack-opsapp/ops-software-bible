-- Make the live task-union the SOLE authority for project team membership.
--
-- Background: projects.team_member_ids is a denormalized cache that trigger
-- project_tasks_sync_project_team_member_ids keeps equal to the union of all
-- non-deleted tasks' team_member_ids (via private.recompute_project_team_member_ids).
-- Previously private.current_user_in_project ORed that cache with the live task
-- union, and clients RLS read the cache directly. A (hypothetically) stale cache
-- could therefore GRANT access a user has no task to back -- exactly the
-- "keeps access after being unassigned from every task" bug.
--
-- This migration removes the cache from every AUTHORIZATION path, so membership
-- is computed only from non-deleted tasks (fail-safe: a stale cache can never
-- grant access). The cache remains in place for fast "my projects" LIST filters
-- only. Proven behavior-preserving on current data: 0 access grants change.
-- Mention-based project view access (current_user_can_view_project) is a
-- SEPARATE branch and is intentionally left untouched.

-- 1) current_user_in_project: pure live task-union (drop the projects-array disjunct).
create or replace function private.current_user_in_project(p_project_id uuid)
 returns boolean
 language sql
 stable security definer
 set search_path to 'public', 'pg_temp'
as $function$
  select exists (
    select 1
    from public.project_tasks pt
    join public.projects p on p.id = pt.project_id
    where pt.project_id = p_project_id
      and pt.deleted_at is null
      and p.deleted_at is null
      and p.company_id = (select private.get_user_company_id())
      and private.get_current_user_id()::text = any(coalesce(pt.team_member_ids, array[]::text[]))
  );
$function$;

-- 2) clients "assigned" visibility now derives through current_user_in_project
--    (was reading projects.team_member_ids directly; this also correctly
--    excludes soft-deleted projects, which the raw cache read did not).
alter policy "role_scope_read" on public.clients
  using (
    private.current_user_is_admin()
    or case private.current_user_scope_for('clients.view')
      when 'all' then true
      when 'assigned' then exists (
        select 1
        from public.projects p
        where p.client_id = clients.id
          and p.deleted_at is null
          and private.current_user_in_project(p.id)
      )
      else false
    end
  );
