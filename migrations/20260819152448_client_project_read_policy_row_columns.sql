-- ============================================================================
-- APPLIED to production 2026-08-19, ledger version 20260819152448.
--
-- Verified BY OBJECT after apply (recipe at the bottom), never by version key:
--   * both role_scope_read policies now point at the row-shaped predicates
--   * neither *_columns function re-reads its own table
--   * grants match the sibling pair (*_row → anon/authenticated, *_columns → owner only)
--   * behaviour, as the company owner, inside a rolled-back transaction:
--       INSERT .. RETURNING into clients  → ACCEPTED (was 42501)
--       INSERT .. RETURNING into projects → ACCEPTED (was 42501)
--       zero probe rows left behind in either table
--   * authorization did NOT widen: a crew account (no pipeline/admin rights)
--     still sees 45 of 541 clients and 55 of 349 projects — its prior scoped view
-- ============================================================================
--
-- WHAT BREAKS TODAY
--
-- `public.clients` carries a RESTRICTIVE SELECT policy `role_scope_read` whose
-- predicate is `private.current_user_can_view_client(id)`. That function calls
-- `private.user_can_view_client(actor, company, client_id)`, whose FIRST gate
-- re-reads `public.clients` by id:
--
--     ... or not exists (
--       select 1 from public.clients client
--       where client.id = p_client_id
--         and client.company_id = p_actor_company_id
--         and client.deleted_at is null
--     ) then return false;
--
-- Postgres applies SELECT policies to an INSERT that has a RETURNING clause
-- (rowsecurity.c adds them as WCO_RLS_INSERT_CHECK when SELECT rights are
-- required). Those with-check expressions are evaluated in ExecInsert BEFORE
-- table_tuple_insert, so the row the predicate is being asked about does not
-- exist in the heap yet. The self-lookup finds nothing, the gate returns false,
-- and the whole statement aborts with:
--
--     42501: new row violates row-level security policy "role_scope_read"
--            for table "clients"
--
-- The admin branch sits BELOW that existence check, so being a company admin
-- does not save it. PostgREST asks for RETURNING whenever a client requests a
-- representation (`.insert(...).select()`), so every such create is rejected
-- and the customer record is permanently lost.
--
-- Observed in prod: analytics_events `sync_parked`, company
-- a612edc0-5c18-4c4d-af97-55b9410dd077, 2026-08-19 02:54:40Z, entity `client`,
-- operation `create`, retry_count 0, with exactly that message. A real customer
-- ("Peter athlone Dr") never reached the server.
--
-- `public.projects` has the identical shape: `role_scope_read` →
-- `private.current_user_can_view_project_scoped(id)` →
-- `private.user_can_view_project(actor, project_id)`, whose first statement is
-- `select p.company_id from public.projects p where p.id = p_project_id`.
--
-- THE FIX
--
-- Evaluate the row's OWN columns instead of re-reading its table — the shape
-- `public.project_tasks` already uses:
--
--     private.current_user_can_view_task_row(
--       company_id, project_id, team_member_ids, deleted_at)
--
-- The authorization ladder is preserved EXACTLY. Nothing is widened:
--   clients:  active company member → admin → clients.view='all'
--             → clients.view='assigned' AND on a task of a project of this
--               client (deliberately team-assignment-only, note preserved)
--   projects: active member of the project's company
--             → projects.view='all' (has_permission short-circuits for admins)
--             → projects.view='assigned' AND on a task of, or mentioned in a
--               note on, this project
-- Only the self-lookup is dropped. Every remaining lookup targets a DIFFERENT
-- table (users, companies, projects, project_tasks, project_notes), which is
-- committed before the statement runs and therefore visible to a STABLE
-- function under the statement snapshot.
--
-- The existing `private.user_can_view_client` (both arities),
-- `private.current_user_can_view_client`, `private.user_can_view_project` and
-- `private.current_user_can_view_project_scoped` are LEFT IN PLACE and
-- unchanged. They have many other callers — user_can_view_sub_client,
-- current_user_can_view_activity, current_user_can_view_deck_design,
-- current_user_can_view_site_visit, current_user_can_view_duplicate_review,
-- user_can_view_calendar_event, user_can_view_task_columns,
-- current_user_can_view_job_conversation — and in every one of those the
-- lookup targets a table OTHER than the one being written, where it is correct.
-- Only the two `role_scope_read` policies are repointed.
--
-- REPLICA PROOF (PostgreSQL 17.11, real function + policy bodies)
--   before: admin INSERT..RETURNING clients  → 42501 role_scope_read   ← the bug
--           admin INSERT..RETURNING projects → 42501 role_scope_read
--   after:  both ACCEPTED
--   unchanged in both runs (authorization did not widen):
--           admin / clients.view=all      see: Linked, Live Unlinked
--           clients.view=assigned         sees: Linked only
--           other-company admin           sees: only its own company's row
--           deactivated member            sees: nothing
--           soft-deleted client           invisible to everyone
--           cross-tenant INSERT..RETURNING       → still 42501
--           deactivated member INSERT..RETURNING → still 42501 (role_scope_insert)
--           INSERT of a born-deleted row         → still 42501 (deleted_at guard)
-- ============================================================================

begin;

-- ---------------------------------------------------------------- clients ---

create or replace function private.user_can_view_client_columns(
  p_actor_user_id uuid,
  p_actor_company_id uuid,
  p_client_id uuid,
  p_company_id uuid,
  p_deleted_at timestamptz
)
returns boolean
language plpgsql
stable security definer
set search_path to 'pg_catalog', 'public', 'private', 'pg_temp'
as $function$
declare
  v_scope text;
begin
  -- The row's own columns stand in for the self-lookup the old function did.
  -- Identical predicate, evaluated against the tuple instead of the heap, so it
  -- is correct for a row that has not been inserted yet.
  if p_deleted_at is not null then
    return false;
  end if;
  if p_company_id is null
    or p_company_id is distinct from p_actor_company_id
  then
    return false;
  end if;
  if not private.user_is_active_company_member(
    p_actor_user_id,
    p_actor_company_id
  ) then
    return false;
  end if;

  if private.user_is_company_admin(
    p_actor_user_id,
    p_actor_company_id
  ) then
    return true;
  end if;

  v_scope := private.effective_permission_scope_for_user(
    p_actor_user_id,
    p_actor_company_id,
    'clients.view'
  );
  if v_scope = 'all' then
    return true;
  end if;
  if v_scope is distinct from 'assigned' then
    return false;
  end if;

  -- Deliberately team-assignment-only. A project note mention grants the
  -- project/task read surface, not the customer's full contact record.
  return exists (
    select 1
    from public.projects project
    join public.project_tasks task
      on task.project_id = project.id
     and task.company_id = project.company_id
     and task.deleted_at is null
    where project.client_id = p_client_id
      and project.company_id = p_actor_company_id
      and project.deleted_at is null
      and p_actor_user_id::text = any(
        coalesce(task.team_member_ids, array[]::text[])
      )
  );
end;
$function$;

create or replace function private.current_user_can_view_client_row(
  p_client_id uuid,
  p_company_id uuid,
  p_deleted_at timestamptz
)
returns boolean
language sql
stable security definer
set search_path to 'pg_catalog', 'public', 'private', 'pg_temp'
as $function$
  select private.user_can_view_client_columns(
    private.get_current_user_id(),
    private.get_user_company_id(),
    p_client_id,
    p_company_id,
    p_deleted_at
  );
$function$;

-- --------------------------------------------------------------- projects ---

create or replace function private.user_can_view_project_columns(
  p_actor_user_id uuid,
  p_project_id uuid,
  p_company_id uuid,
  p_deleted_at timestamptz
)
returns boolean
language plpgsql
stable security definer
set search_path to 'pg_catalog', 'public', 'private', 'pg_temp'
as $function$
begin
  if p_deleted_at is not null then
    return false;
  end if;
  -- Membership is checked against the PROJECT's company, exactly as
  -- private.user_can_view_project does with the company it read off the row.
  if p_company_id is null or not exists (
    select 1
      from public.users u
     where u.id = p_actor_user_id
       and u.company_id = p_company_id
       and u.deleted_at is null
       and coalesce(u.is_active, false)
  ) then
    return false;
  end if;

  -- No explicit admin branch, matching the original: public.has_permission
  -- short-circuits to true for a company admin.
  if public.has_permission(p_actor_user_id, 'projects.view', 'all') then
    return true;
  end if;

  if not public.has_permission(
    p_actor_user_id,
    'projects.view',
    'assigned'
  ) then
    return false;
  end if;

  return exists (
    select 1
      from public.project_tasks pt
     where pt.project_id = p_project_id
       and pt.deleted_at is null
       and p_actor_user_id::text = any(
         coalesce(pt.team_member_ids, array[]::text[])
       )
  ) or exists (
    select 1
      from public.project_notes pn
     where pn.project_id = p_project_id::text
       and pn.deleted_at is null
       and p_actor_user_id::text = any(
         coalesce(pn.mentioned_user_ids, array[]::text[])
       )
  );
end;
$function$;

create or replace function private.current_user_can_view_project_row(
  p_project_id uuid,
  p_company_id uuid,
  p_deleted_at timestamptz
)
returns boolean
language sql
stable security definer
set search_path to 'pg_catalog', 'public', 'private', 'pg_temp'
as $function$
  select private.user_can_view_project_columns(
    private.get_current_user_id(),
    p_project_id,
    p_company_id,
    p_deleted_at
  );
$function$;

-- ----------------------------------------------------------------- grants ---
-- Matches the sibling row-shaped pair exactly: the policy-facing wrapper is
-- executable by the client roles; the inner columns function is owner-only.
-- service_role is deliberately absent — it bypasses RLS and never evaluates
-- these.

revoke execute on function private.user_can_view_client_columns(
  uuid, uuid, uuid, uuid, timestamptz
) from public;
revoke execute on function private.user_can_view_project_columns(
  uuid, uuid, uuid, timestamptz
) from public;

revoke execute on function private.current_user_can_view_client_row(
  uuid, uuid, timestamptz
) from public;
revoke execute on function private.current_user_can_view_project_row(
  uuid, uuid, timestamptz
) from public;

grant execute on function private.current_user_can_view_client_row(
  uuid, uuid, timestamptz
) to anon, authenticated;
grant execute on function private.current_user_can_view_project_row(
  uuid, uuid, timestamptz
) to anon, authenticated;

-- --------------------------------------------------------------- policies ---

alter policy role_scope_read on public.clients
  using (private.current_user_can_view_client_row(id, company_id, deleted_at));

alter policy role_scope_read on public.projects
  using (private.current_user_can_view_project_row(id, company_id, deleted_at));

commit;

-- ============================================================================
-- VERIFY BY OBJECT (not by ledger version — this migration has no ledger row)
--
-- 1. Both policies point at the row-shaped predicates:
--
--    select c.relname, pol.polname,
--           pg_get_expr(pol.polqual, pol.polrelid) as using_expr
--    from pg_policy pol
--    join pg_class c on c.oid = pol.polrelid
--    join pg_namespace n on n.oid = c.relnamespace
--    where n.nspname = 'public'
--      and c.relname in ('clients','projects')
--      and pol.polname = 'role_scope_read';
--
--    expected:
--      clients  | role_scope_read | private.current_user_can_view_client_row(id, company_id, deleted_at)
--      projects | role_scope_read | private.current_user_can_view_project_row(id, company_id, deleted_at)
--
-- 2. Neither new predicate re-reads its own table:
--
--    select p.proname,
--           pg_get_functiondef(p.oid) ~ 'public\.clients'  as reads_clients,
--           pg_get_functiondef(p.oid) ~ 'public\.projects' as reads_projects
--    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
--    where n.nspname = 'private'
--      and p.proname in ('user_can_view_client_columns','user_can_view_project_columns');
--
--    expected: user_can_view_client_columns  reads_clients=false,  reads_projects=true
--              user_can_view_project_columns reads_clients=false,  reads_projects=false
--
-- 3. Grants match the sibling row-shaped pair:
--
--    select p.proname, pg_get_userbyid(p.proowner) as owner,
--           array_to_string(p.proacl::text[], ' | ') as acl
--    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
--    where n.nspname = 'private'
--      and p.proname in ('current_user_can_view_client_row','current_user_can_view_project_row',
--                        'user_can_view_client_columns','user_can_view_project_columns');
--
--    expected: *_row      → postgres=X/postgres | anon=X/postgres | authenticated=X/postgres
--              *_columns  → postgres=X/postgres
--
-- 4. Behaviour, on a scratch row inside an aborted transaction (safe on prod:
--    it never commits). Run as a company admin's session:
--
--    begin;
--      insert into public.clients (id, company_id, name)
--      values (gen_random_uuid(), '<your company id>', 'RLS PROBE')
--      returning id;             -- expected: one row, NOT 42501
--    rollback;
--
-- 5. The old functions are untouched and still serve their other callers:
--
--    select proname, pg_get_functiondef(oid) ~ 'from public\.clients' as still_self_reads
--    from pg_proc where pronamespace = 'private'::regnamespace
--      and proname = 'user_can_view_client';   -- expected: true (both arities)
-- ============================================================================
