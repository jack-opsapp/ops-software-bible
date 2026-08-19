-- ============================================================================
-- APPLIED to production 2026-08-19, ledger version 20260819171736.
--
-- Verified BY OBJECT after apply (recipe below), never by version key:
--   * all five policies now point at the row-shaped predicates
--   * grants match the applied sibling pair: *_row -> anon+authenticated,
--     except job_conversation_row -> authenticated only (its policy is TO
--     authenticated); *_columns functions stay owner-only
--   * behaviour, as the company owner, inside a rolled-back transaction:
--       INSERT .. RETURNING into calendar_user_events -> ACCEPTED (was 42501)
--       zero probe rows left behind
--   * authorization did NOT widen: a crew account (no admin/pipeline rights)
--     still sees 37 sub_clients and 0 calendar_events / 0 calendar_user_events /
--     0 opportunities / 0 job_conversations -- its prior scoped view exactly
-- Apply, then verify BY OBJECT using the recipe at the bottom — never by
-- ledger version key. (Verify-by-object recipe covers all five tables.)
--
-- Sibling of, and identical in shape to, 20260819152448 (clients + projects,
-- applied 2026-08-19). This finishes the class sweep: it is the complete
-- remaining set. A catalog scan of every RESTRICTIVE SELECT policy in `public`
-- confirms no other table has this shape — every other restrictive read
-- predicate is already row-shaped or targets a DIFFERENT table.
--
-- ============================== WHAT BREAKS ================================
--
-- A RESTRICTIVE SELECT policy whose predicate RE-READS ITS OWN TABLE can never
-- pass for a statement that needs SELECT rights on the row being inserted.
-- rowsecurity.c adds SELECT/ALL policies to an INSERT as WCO_RLS_INSERT_CHECK
-- whenever the target RTE requires ACL_SELECT; ExecInsert evaluates those with-
-- check expressions BEFORE table_tuple_insert, so the row the predicate is
-- being asked about does not exist in the heap yet. The self-lookup finds
-- nothing and the statement aborts with 42501.
--
-- ACL_SELECT is required — and the trap therefore springs — for BOTH:
--   * INSERT ... RETURNING  (PostgREST asks for this on `.insert(...).select()`,
--     and also by default whenever `Prefer: return=representation` is in play)
--   * INSERT ... ON CONFLICT DO UPDATE, even with NO RETURNING clause at all
--     (an upsert sent with `returning: .minimal` is NOT safe from this)
--
-- The admin branch sits BELOW the self-lookup in every one of these functions,
-- so being a company admin does not save it. The record is permanently lost.
--
-- ---------------------------- the five tables -----------------------------
--
-- BROKEN ON A LIVE CLIENT WRITE PATH:
--
--   public.sub_clients        policy `role_scope_read`
--                             -> private.current_user_can_view_sub_client(id)
--                             -> private.user_can_view_sub_client(...), whose
--                                first statement selects client_id FROM
--                                public.sub_clients WHERE id = p_sub_client_id.
--     iOS ClientRepository.createSubClient does .insert(payload).select()
--     .single() and LeadDetailViewModel.addContactToClient CONSUMES the
--     returned DTO (appends it to the published `subClients` array), so the
--     client cannot simply drop .select() — the server fix is required.
--     Scope note: the durable-queue path (DataActor.genericTablePush) is NOT
--     affected. supabase-swift's `insert(_:returning:count:)` defaults
--     `returning` to nil and emits NO `Prefer` header, so PostgREST applies its
--     own default of return=minimal and no RETURNING is requested. Only
--     `.select()` sets `Prefer: return=representation`. The replica confirms
--     the same insert without RETURNING is accepted even before this fix.
--
--   public.calendar_user_events   policy `calendar_user_event_read_scope_guard`
--                             -> private.current_user_can_view_calendar_user_event(id)
--                             -> private.user_can_view_calendar_user_event(...),
--                                which does `select event.* into v_event from
--                                public.calendar_user_events where event.id = ...`.
--     Corroborated in prod: 2 rows total, 0 inserted in 30 days, newest
--     2026-05-01. The live iOS path (CalendarUserEventRepository.upsertEvent)
--     sends an UPSERT with `returning: .minimal` and is STILL refused, per the
--     ON CONFLICT DO UPDATE case above — which is why nothing has landed.
--
-- LATENT — same shape, no client insert path reaching it today. Fixed anyway:
-- leaving latent instances in place is how this defect recurred.
--
--   public.opportunities      policy `role_scope_read`, first conjunct
--                             -> private.current_user_can_view_opportunity(id)
--                             -> private.user_can_view_opportunity(...), which
--                                selects company_id, assigned_to FROM
--                                public.opportunities WHERE o.id = ...
--     iOS creates opportunities only through the SECURITY DEFINER RPC
--     create_opportunity_guarded, which bypasses RLS. Prod: 75 inserted in 30d.
--
--   public.calendar_events    policy `calendar_event_read_scope_guard`
--                             -> private.current_user_can_view_calendar_event(id)
--                             -> private.user_can_view_calendar_event(...), which
--                                does `select event.* into v_event from
--                                public.calendar_events where event.id = ...`.
--     No iOS write path exists (the app writes calendar_user_events instead).
--     Prod: 0 rows, ever.
--
--   public.job_conversations  policy `job_conversations_job_scope_select`
--                             -> private.current_user_can_view_job_conversation(id),
--                                whose FIRST `exists` reads public.job_conversations.
--     `authenticated` holds SELECT only on this table (no INSERT grant), so a
--     client insert fails at the privilege check before RLS is consulted. The
--     self-lookup is removed here for hygiene and read cost, NOT to enable an
--     insert. NOTE: the SECOND gate requires a matching row in
--     public.job_conversation_anchors, which by construction cannot exist yet
--     at the moment the conversation row is inserted. That gate is a deliberate
--     authorization rule, not the class defect, and is left EXACTLY as is —
--     widening it would widen authorization. Writes continue to go through
--     service_role / SECURITY DEFINER paths.
--
-- ================================ THE FIX ==================================
--
-- Evaluate the row's OWN columns instead of re-reading its table — the shape
-- public.project_tasks, public.clients and public.projects already use.
--
-- The authorization ladder is preserved EXACTLY for each table. Only the
-- self-lookup is dropped; every remaining lookup targets a DIFFERENT table
-- (users, companies, clients, projects, project_tasks, project_notes,
-- job_conversation_anchors, opportunities-as-merge-target), each of which is
-- committed before the statement runs and therefore visible to a STABLE
-- function under the statement snapshot.
--
-- The existing by-id functions -- private.user_can_view_sub_client,
-- private.current_user_can_view_sub_client, private.user_can_view_calendar_event,
-- private.current_user_can_view_calendar_event,
-- private.user_can_view_calendar_user_event,
-- private.current_user_can_view_calendar_user_event,
-- private.user_can_view_opportunity, private.current_user_can_view_opportunity
-- and private.current_user_can_view_job_conversation -- are LEFT IN PLACE AND
-- UNCHANGED. They have many other callers where the lookup targets a table
-- OTHER than the one being written and is correct there: follow_ups,
-- stage_transitions and the opportunities merge-target conjunct all call
-- current_user_can_view_opportunity; job_conversation_anchors,
-- job_conversation_turns, job_conversation_redaction_events,
-- job_memory_versions and job_memory_version_evidence all call
-- current_user_can_view_job_conversation(conversation_id). Only the five
-- read policies are repointed.
--
-- ========================== REPLICA PROOF (PG 17.11) ========================
-- Throwaway local cluster loaded with the REAL prod function and policy bodies.
--
--   BEFORE                                                          AFTER
--   sub_clients          INSERT..RETURNING   42501 role_scope_read   ACCEPTED
--   calendar_events      INSERT..RETURNING   42501 calendar_event_read_scope_guard        ACCEPTED
--   calendar_user_events INSERT..RETURNING   42501 calendar_user_event_read_scope_guard   ACCEPTED
--   calendar_user_events UPSERT (no RETURNING) 42501 same guard                           ACCEPTED
--   opportunities        INSERT..RETURNING   42501 role_scope_read   ACCEPTED
--   job_conversations    INSERT..RETURNING   42501 permission denied (grant, not RLS) -- unchanged
--   sub_clients          INSERT (no RETURNING)  ACCEPTED (both) -- isolates ACL_SELECT as the trigger
--
--   AUTHORIZATION DID NOT WIDEN -- byte-identical visible sets before and after
--   for every persona (company admin / scope='all' / scope='assigned' /
--   deactivated member / foreign-company admin) across all five tables, and:
--     cross-tenant INSERT..RETURNING (A->B and B->A)  -> still refused
--     born-deleted row INSERT..RETURNING (all 4)      -> still refused
--     deactivated member INSERT..RETURNING (all 4)    -> still refused
--     scope='assigned' inserting a row it could not then read
--       (sub_client under an unlinked client; opportunity assigned_to=NULL;
--        calendar_event with empty team and no project) -> still refused
--   Zero probe rows left behind in any table.
-- ============================================================================

begin;

-- ------------------------------------------------------------ sub_clients ---

create or replace function private.user_can_view_sub_client_columns(
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
begin
  -- The row's own columns stand in for the self-lookup the old function did:
  -- `where sub_client.id = p_sub_client_id and sub_client.company_id =
  -- p_actor_company_id and sub_client.deleted_at is null`, plus `if not found
  -- then return false`. Identical predicate, evaluated against the tuple
  -- instead of the heap, so it is correct for a row not yet inserted.
  if p_deleted_at is not null then
    return false;
  end if;
  if p_company_id is null
    or p_company_id is distinct from p_actor_company_id
  then
    return false;
  end if;

  -- Unchanged delegate. It reads public.clients -- a DIFFERENT table -- where
  -- the lookup is correct, and carries the active-member and admin gates.
  return private.user_can_view_client(
    p_actor_user_id,
    p_actor_company_id,
    p_client_id
  );
end;
$function$;

create or replace function private.current_user_can_view_sub_client_row(
  p_client_id uuid,
  p_company_id uuid,
  p_deleted_at timestamptz
)
returns boolean
language sql
stable security definer
set search_path to 'pg_catalog', 'public', 'private', 'pg_temp'
as $function$
  select private.user_can_view_sub_client_columns(
    private.get_current_user_id(),
    private.get_user_company_id(),
    p_client_id,
    p_company_id,
    p_deleted_at
  );
$function$;

-- -------------------------------------------------------- calendar_events ---

create or replace function private.user_can_view_calendar_event_columns(
  p_actor_user_id uuid,
  p_actor_company_id uuid,
  p_company_id uuid,
  p_project_id uuid,
  p_team_member_ids text[],
  p_deleted_at timestamptz
)
returns boolean
language plpgsql
stable security definer
set search_path to 'pg_catalog', 'public', 'private', 'pg_temp'
as $function$
declare
  v_calendar_scope text;
  v_task_scope text;
begin
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

  v_calendar_scope := private.effective_permission_scope_for_user(
    p_actor_user_id,
    p_actor_company_id,
    'calendar.view'
  );
  v_task_scope := private.effective_permission_scope_for_user(
    p_actor_user_id,
    p_actor_company_id,
    'tasks.view'
  );

  if v_calendar_scope = 'all' or v_task_scope = 'all' then
    return true;
  end if;

  if v_calendar_scope is distinct from 'own'
     and v_task_scope is distinct from 'assigned' then
    return false;
  end if;

  return p_actor_user_id::text = any(
    coalesce(p_team_member_ids, array[]::text[])
  ) or (
    p_project_id is not null
    and private.user_can_view_project(
      p_actor_user_id,
      p_project_id
    )
  );
end;
$function$;

create or replace function private.current_user_can_view_calendar_event_row(
  p_company_id uuid,
  p_project_id uuid,
  p_team_member_ids text[],
  p_deleted_at timestamptz
)
returns boolean
language sql
stable security definer
set search_path to 'pg_catalog', 'public', 'private', 'pg_temp'
as $function$
  select private.user_can_view_calendar_event_columns(
    private.get_current_user_id(),
    private.get_user_company_id(),
    p_company_id,
    p_project_id,
    p_team_member_ids,
    p_deleted_at
  );
$function$;

-- --------------------------------------------------- calendar_user_events ---

create or replace function private.user_can_view_calendar_user_event_columns(
  p_actor_user_id uuid,
  p_actor_company_id uuid,
  p_user_id text,
  p_company_id text,
  p_type text,
  p_team_member_ids text[],
  p_deleted_at timestamptz
)
returns boolean
language plpgsql
stable security definer
set search_path to 'pg_catalog', 'public', 'private', 'pg_temp'
as $function$
declare
  v_calendar_scope text;
  v_task_scope text;
  v_time_off_scope text;
begin
  if p_deleted_at is not null then
    return false;
  end if;
  -- company_id is TEXT on this table; the original compared it against
  -- p_actor_company_id::text. Preserved exactly.
  if p_company_id is null
    or p_company_id is distinct from p_actor_company_id::text
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

  v_calendar_scope := private.effective_permission_scope_for_user(
    p_actor_user_id,
    p_actor_company_id,
    'calendar.view'
  );
  v_task_scope := private.effective_permission_scope_for_user(
    p_actor_user_id,
    p_actor_company_id,
    'tasks.view'
  );
  v_time_off_scope := private.effective_permission_scope_for_user(
    p_actor_user_id,
    p_actor_company_id,
    'time_off.approve'
  );

  if v_calendar_scope = 'all' or v_task_scope = 'all' then
    return true;
  end if;

  -- Preserve the shipped calendar contract: an event's owner and explicit
  -- invitees always see it. Permission scope controls company-wide expansion,
  -- not whether a person can see an event addressed directly to them.
  if p_user_id = p_actor_user_id::text
     or p_actor_user_id::text = any(
       coalesce(p_team_member_ids, array[]::text[])
     ) then
    return true;
  end if;

  return p_type = 'time_off' and v_time_off_scope = 'all';
end;
$function$;

create or replace function private.current_user_can_view_calendar_user_event_row(
  p_user_id text,
  p_company_id text,
  p_type text,
  p_team_member_ids text[],
  p_deleted_at timestamptz
)
returns boolean
language sql
stable security definer
set search_path to 'pg_catalog', 'public', 'private', 'pg_temp'
as $function$
  select private.user_can_view_calendar_user_event_columns(
    private.get_current_user_id(),
    private.get_user_company_id(),
    p_user_id,
    p_company_id,
    p_type,
    p_team_member_ids,
    p_deleted_at
  );
$function$;

-- ---------------------------------------------------------- opportunities ---

create or replace function private.user_can_view_opportunity_columns(
  p_actor_user_id uuid,
  p_company_id uuid,
  p_assigned_to uuid,
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
  if p_deleted_at is not null then
    return false;
  end if;
  if p_company_id is null then
    return false;
  end if;

  -- Scope is computed against the ROW's company, exactly as the original did
  -- with the company it read off the row. effective_pipeline_scope_for_user
  -- returns null unless the actor is an active member of that company, which
  -- is what keeps this tenant-safe.
  v_scope := private.effective_pipeline_scope_for_user(
    p_actor_user_id,
    p_company_id,
    'pipeline.view'
  );

  if v_scope = 'all' then
    return true;
  end if;
  if v_scope = 'assigned'
    and p_assigned_to = p_actor_user_id
  then
    return true;
  end if;
  return false;
end;
$function$;

create or replace function private.current_user_can_view_opportunity_row(
  p_company_id uuid,
  p_assigned_to uuid,
  p_deleted_at timestamptz
)
returns boolean
language sql
stable security definer
set search_path to 'pg_catalog', 'public', 'private', 'pg_temp'
as $function$
  select private.user_can_view_opportunity_columns(
    private.get_current_user_id(),
    p_company_id,
    p_assigned_to,
    p_deleted_at
  );
$function$;

-- ------------------------------------------------------- job_conversations ---

create or replace function private.current_user_can_view_job_conversation_row(
  p_conversation_id uuid,
  p_company_id uuid
)
returns boolean
language sql
stable security definer
set search_path to 'pg_catalog', 'public', 'private', 'pg_temp'
as $function$
  -- The row's own company_id replaces the self-lookup the old predicate did:
  -- an `exists` that re-read THIS SAME TABLE by id and asserted its company_id
  -- equalled private.get_user_company_id(). For the row being tested those are
  -- the same assertion. The anchor gate below is UNCHANGED.
  -- (Deliberately no literal `public.<this table>` anywhere in this body — the
  -- step-2 verification below greps the function text for exactly that.)
  select
    p_conversation_id is not null
    and p_company_id is not null
    and p_company_id = private.get_user_company_id()
    and exists (
      select 1
      from public.job_conversation_anchors anchor
      where anchor.conversation_id = p_conversation_id
        and anchor.company_id = private.get_user_company_id()
        and (
          (
            anchor.anchor_kind = 'opportunity'
            and private.current_user_can_view_opportunity(
              anchor.opportunity_id
            )
          )
          or
          (
            anchor.anchor_kind = 'project'
            and private.current_user_can_view_project_scoped(
              anchor.project_id
            )
          )
        )
    );
$function$;

-- ----------------------------------------------------------------- grants ---
-- Matches the already-applied sibling pair exactly: the policy-facing wrapper
-- is executable by the client roles that the policy applies to; the inner
-- columns function is owner-only. service_role is deliberately absent — it
-- bypasses RLS and never evaluates these.
--
-- job_conversations' policies are `TO authenticated`, and its existing
-- predicate private.current_user_can_view_job_conversation is granted to
-- authenticated only (not anon). The new wrapper matches that exactly.

revoke execute on function private.user_can_view_sub_client_columns(
  uuid, uuid, uuid, uuid, timestamptz
) from public;
revoke execute on function private.user_can_view_calendar_event_columns(
  uuid, uuid, uuid, uuid, text[], timestamptz
) from public;
revoke execute on function private.user_can_view_calendar_user_event_columns(
  uuid, uuid, text, text, text, text[], timestamptz
) from public;
revoke execute on function private.user_can_view_opportunity_columns(
  uuid, uuid, uuid, timestamptz
) from public;

revoke execute on function private.current_user_can_view_sub_client_row(
  uuid, uuid, timestamptz
) from public;
revoke execute on function private.current_user_can_view_calendar_event_row(
  uuid, uuid, text[], timestamptz
) from public;
revoke execute on function private.current_user_can_view_calendar_user_event_row(
  text, text, text, text[], timestamptz
) from public;
revoke execute on function private.current_user_can_view_opportunity_row(
  uuid, uuid, timestamptz
) from public;
revoke execute on function private.current_user_can_view_job_conversation_row(
  uuid, uuid
) from public;

grant execute on function private.current_user_can_view_sub_client_row(
  uuid, uuid, timestamptz
) to anon, authenticated;
grant execute on function private.current_user_can_view_calendar_event_row(
  uuid, uuid, text[], timestamptz
) to anon, authenticated;
grant execute on function private.current_user_can_view_calendar_user_event_row(
  text, text, text, text[], timestamptz
) to anon, authenticated;
grant execute on function private.current_user_can_view_opportunity_row(
  uuid, uuid, timestamptz
) to anon, authenticated;
grant execute on function private.current_user_can_view_job_conversation_row(
  uuid, uuid
) to authenticated;

-- --------------------------------------------------------------- policies ---

alter policy role_scope_read on public.sub_clients
  using (
    private.current_user_can_view_sub_client_row(
      client_id, company_id, deleted_at
    )
  );

alter policy calendar_event_read_scope_guard on public.calendar_events
  using (
    private.current_user_can_view_calendar_event_row(
      company_id, project_id, team_member_ids, deleted_at
    )
  );

alter policy calendar_user_event_read_scope_guard on public.calendar_user_events
  using (
    private.current_user_can_view_calendar_user_event_row(
      user_id, company_id, type, team_member_ids, deleted_at
    )
  );

-- The merge-target conjunct is preserved verbatim: it names a DIFFERENT,
-- already-committed row, so the by-id lookup is correct there.
alter policy role_scope_read on public.opportunities
  using (
    private.current_user_can_view_opportunity_row(
      company_id, assigned_to, deleted_at
    )
    and (
      merged_into_opportunity_id is null
      or private.current_user_can_view_opportunity(merged_into_opportunity_id)
    )
  );

alter policy job_conversations_job_scope_select on public.job_conversations
  using (
    private.current_user_can_view_job_conversation_row(id, company_id)
  );

commit;

-- ============================================================================
-- VERIFY BY OBJECT (not by ledger version)
--
-- 1. All five policies point at the row-shaped predicates:
--
--    select c.relname, pol.polname,
--           pg_get_expr(pol.polqual, pol.polrelid) as using_expr
--    from pg_policy pol
--    join pg_class c on c.oid = pol.polrelid
--    join pg_namespace n on n.oid = c.relnamespace
--    where n.nspname = 'public'
--      and (c.relname, pol.polname) in (
--        ('sub_clients','role_scope_read'),
--        ('calendar_events','calendar_event_read_scope_guard'),
--        ('calendar_user_events','calendar_user_event_read_scope_guard'),
--        ('opportunities','role_scope_read'),
--        ('job_conversations','job_conversations_job_scope_select'))
--    order by c.relname;
--
--    expected:
--      calendar_events      | calendar_event_read_scope_guard      | private.current_user_can_view_calendar_event_row(company_id, project_id, team_member_ids, deleted_at)
--      calendar_user_events | calendar_user_event_read_scope_guard | private.current_user_can_view_calendar_user_event_row(user_id, company_id, type, team_member_ids, deleted_at)
--      job_conversations    | job_conversations_job_scope_select   | private.current_user_can_view_job_conversation_row(id, company_id)
--      opportunities        | role_scope_read                      | (private.current_user_can_view_opportunity_row(company_id, assigned_to, deleted_at) AND ((merged_into_opportunity_id IS NULL) OR private.current_user_can_view_opportunity(merged_into_opportunity_id)))
--      sub_clients          | role_scope_read                      | private.current_user_can_view_sub_client_row(client_id, company_id, deleted_at)
--
-- 2. No new predicate re-reads its own table:
--
--    select p.proname,
--           pg_get_functiondef(p.oid) ~ ('public\.' || t.tbl) as reads_own_table
--    from pg_proc p
--    join pg_namespace n on n.oid = p.pronamespace
--    join (values
--      ('user_can_view_sub_client_columns','sub_clients'),
--      ('user_can_view_calendar_event_columns','calendar_events'),
--      ('user_can_view_calendar_user_event_columns','calendar_user_events'),
--      ('user_can_view_opportunity_columns','opportunities'),
--      ('current_user_can_view_job_conversation_row','job_conversations')
--    ) as t(fn, tbl) on t.fn = p.proname
--    where n.nspname = 'private';
--
--    expected: reads_own_table = false for all five.
--
--    This greps the whole function text, comments included, so a `true` means
--    "the body mentions that table ANYWHERE" — read it before concluding the
--    lookup is real. The bodies above are deliberately written to keep the
--    literal `public.<own table>` out of their comments so this stays clean.
--
-- 3. Grants match the sibling row-shaped pair:
--
--    select p.proname, pg_get_userbyid(p.proowner) as owner,
--           array_to_string(p.proacl::text[], ' | ') as acl
--    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
--    where n.nspname = 'private'
--      and p.proname in (
--        'current_user_can_view_sub_client_row','user_can_view_sub_client_columns',
--        'current_user_can_view_calendar_event_row','user_can_view_calendar_event_columns',
--        'current_user_can_view_calendar_user_event_row','user_can_view_calendar_user_event_columns',
--        'current_user_can_view_opportunity_row','user_can_view_opportunity_columns',
--        'current_user_can_view_job_conversation_row')
--    order by p.proname;
--
--    expected: *_row (4 of them)                  -> postgres=X/postgres | anon=X/postgres | authenticated=X/postgres
--              current_user_can_view_job_conversation_row -> postgres=X/postgres | authenticated=X/postgres
--              *_columns                          -> postgres=X/postgres
--
-- 4. Behaviour, on scratch rows inside an ABORTED transaction (safe on prod:
--    it never commits). Run in a company admin's session:
--
--    begin;
--      insert into public.sub_clients (company_id, client_id, name)
--      values ('<your company id>', '<a client id in it>', 'RLS PROBE')
--      returning id;                             -- expected: one row, NOT 42501
--
--      insert into public.calendar_events (company_id, title)
--      values ('<your company id>', 'RLS PROBE')
--      returning id;                             -- expected: one row, NOT 42501
--
--      insert into public.calendar_user_events
--        (company_id, user_id, type, title, start_date, end_date)
--      values ('<your company id>', '<your user id>', 'personal',
--              'RLS PROBE', now(), now())
--      returning id;                             -- expected: one row, NOT 42501
--
--      insert into public.opportunities (company_id, title)
--      values ('<your company id>', 'RLS PROBE')
--      returning id;                             -- expected: one row, NOT 42501
--    rollback;
--
--    job_conversations is intentionally NOT probed this way: `authenticated`
--    has no INSERT grant on it, so the statement fails on privileges, not RLS.
--
-- 5. Authorization did not widen. As a NON-admin, scope-limited account,
--    compare these counts against the values captured immediately before apply:
--
--    select 'sub_clients' t, count(*) from public.sub_clients
--    union all select 'calendar_events', count(*) from public.calendar_events
--    union all select 'calendar_user_events', count(*) from public.calendar_user_events
--    union all select 'opportunities', count(*) from public.opportunities
--    union all select 'job_conversations', count(*) from public.job_conversations;
--
--    expected: identical before and after.
--
-- 6. The old by-id functions are untouched and still serve their other callers:
--
--    select proname,
--           pg_get_functiondef(oid) ~ 'from public\.sub_clients' as still_self_reads
--    from pg_proc where pronamespace = 'private'::regnamespace
--      and proname = 'user_can_view_sub_client';        -- expected: true
-- ============================================================================
