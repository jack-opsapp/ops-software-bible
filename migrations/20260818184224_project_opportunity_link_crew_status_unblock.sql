-- H2 CREW UNBLOCK — scope the project<->opportunity link gate to link mutations.
--
-- STATUS: NOT YET APPLIED. Authored and committed for review; the founder
-- approves before it runs. The filename timestamp is authoring time, NOT a
-- ledger version — at apply time read the stamped version back out of
-- supabase_migrations.schema_migrations and rename this file to
-- <ledger_version>_<ledger_name>.sql per migrations/README.md.
--
-- THE DEFECT
--
-- public.enforce_project_opportunity_link() fires AFTER INSERT OR DELETE OR
-- UPDATE OF opportunity_id, opportunity_ref, company_id, status, deleted_at on
-- public.projects. Before any invariant work, the deployed body requires
--
--     private.current_user_has_permission('pipeline.manage', 'all')
--
-- for ANY write on a project whose opportunity-link mirrors are non-null,
-- whenever auth.role() <> 'service_role'. Because `status` is in the trigger's
-- column list, an ordinary lifecycle write — a crew member marking a converted
-- job in progress — trips that check and raises a raw `access_denied` (42501).
--
-- pipeline.manage is granted only by the Admin, Office and Owner presets. In
-- the founder's company (Canpro Deck and Rail, a612edc0-…dd077) 7 of 8 active
-- users hold no pipeline.manage at any scope: 5 Crew and 2 Operator, including
-- the founder's own Operator account. Only the Owner passes. Company-wide the
-- check fails for 9 of 81 active users across 34 companies. 41 active projects
-- carry link mirrors (30 of them Canpro), spread across closed/in_progress/
-- accepted/completed/estimated. Field work is blocked today.
--
-- WHAT THIS MIGRATION CHANGES
--
-- Exactly one block: the ordinary-write authorization gate. It is split into
-- its two independent halves.
--
--   * Company isolation stays UNCONDITIONAL for every non-service_role write
--     that touches a linked project. A crew member writing their own company's
--     project passes it trivially; a caller that reaches this trigger through
--     some other SECURITY DEFINER path (bypassing the projects RLS
--     company_isolation policy) is still contained. Nothing is relaxed here.
--
--   * pipeline.manage @ all is now required only when the write MUTATES the
--     link contract — the four link columns (projects.opportunity_id,
--     projects.opportunity_ref, opportunities.project_id,
--     opportunities.project_ref). That is the trigger's legitimate job.
--
-- A write mutates the link contract when it attaches a link (INSERT of a
-- linked project), re-points or detaches one (v_old_opportunity_id distinct
-- from v_new_opportunity_id), moves a linked project across tenants
-- (company_id changed), or crosses the soft-delete boundary in either
-- direction — soft-deleting releases the opportunity's reverse mirrors and
-- restoring re-establishes them. Any write on an already-soft-deleted linked
-- project is treated as link-mutating too, so the release branch below can
-- never be reached ungated.
--
-- An ordinary status / lifecycle write on an already-linked project leaves all
-- four link columns exactly as it found them. It passes through.
--
-- WHY THIS IS SOUND
--
-- The only opportunity-side write still reachable without pipeline.manage is
-- the existing activation block at the end of this function, which sets
-- project_ref/project_id to NEW.id. It cannot introduce a link the actor was
-- not already authorized to create: v_new_opportunity_id is derived solely
-- from the project row's own opportunity_ref / opportunity_id, and changing
-- either of those columns is itself link-mutating and therefore gated above.
-- The pre-existing 'opportunity project mirrors disagree' and 'opportunity is
-- already linked to another project' guards still raise before any write, so
-- the reverse mirror can only be completed to agree with a link the project
-- row already, legitimately asserts.
--
-- WHAT THIS MIGRATION PRESERVES — verbatim, byte for byte
--
--   * The DELETE branch and its own company + pipeline.manage @ all gate.
--   * The private.opportunity_conversion_project_link_tokens consumption and
--     its early return (the conversion RPC's owned link write).
--   * The ops.skip_project_opportunity_invariant GUC short-circuit, still
--     positioned after authorization so it cannot be used to bypass it.
--   * The soft-delete reverse-mirror release.
--   * The old-opportunity mirror release on re-point.
--   * The non-activating-status early return.
--   * The FOR UPDATE opportunity lock, the mirror-disagreement guard and the
--     already-linked-elsewhere guard.
--   * The stage='won' / stage_manually_set / actual_close_date activation
--     block and its stage_transitions row — UNTOUCHED. That behavior belongs
--     to D3 (won-authority surgery), owned separately; changing it here would
--     collide. Today it is inert for every real row: all 41 linked pairs in
--     prod are already stage='won' with both reverse mirrors populated and a
--     non-null actual_close_date, so the block writes nothing but updated_at
--     and skips the stage_transitions insert (v_from_stage = 'won').
--   * The service_role bypass.
--   * The function's signature, volatility, SECURITY DEFINER marking, search_path
--     and the existing revokes / trigger wiring (untouched — CREATE OR REPLACE
--     preserves the trigger binding and the ACL).
--
-- No role name is gated on anywhere; authorization is granular permission only.
-- The change is additive and shipped-client-compatible: no schema, signature or
-- payload shape changes, so a deployed iOS 3.0.5 build is unaffected.

begin;

create or replace function public.enforce_project_opportunity_link()
returns trigger
language plpgsql
security definer
set search_path to 'pg_catalog', 'public', 'private', 'pg_temp'
as $function$
declare
  v_new_opportunity_id uuid;
  v_old_opportunity_id uuid;
  v_from_stage text;
  v_stage_entered_at timestamptz;
  v_existing_project_ref uuid;
  v_existing_project_legacy uuid;
  v_existing_project_id uuid;
  v_conversion_link_owned boolean := false;
  v_link_contract_mutated boolean := false;
begin
  if tg_op = 'DELETE' then
    if old.opportunity_ref is not null then
      v_old_opportunity_id := old.opportunity_ref;
    elsif old.opportunity_id is not null
      and btrim(old.opportunity_id) ~*
        '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
    then
      v_old_opportunity_id := old.opportunity_id::uuid;
    end if;

    if v_old_opportunity_id is not null
      and coalesce(auth.role(), '') <> 'service_role'
    then
      if old.company_id is distinct from private.get_user_company_id()
        or not private.current_user_has_permission('pipeline.manage', 'all')
      then
        raise exception 'access_denied'
          using errcode = '42501';
      end if;
    end if;

    if current_setting('ops.skip_project_opportunity_invariant', true) = 'on' then
      return old;
    end if;

    if v_old_opportunity_id is not null then
      update public.opportunities
         set project_ref = null,
             project_id = null,
             updated_at = now()
       where id = v_old_opportunity_id
         and company_id = old.company_id
         and (project_ref = old.id or project_id = old.id);
    end if;
    return old;
  end if;

  if new.opportunity_ref is not null then
    v_new_opportunity_id := new.opportunity_ref;
  elsif new.opportunity_id is not null
    and btrim(new.opportunity_id) ~*
      '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
  then
    v_new_opportunity_id := new.opportunity_id::uuid;
  end if;

  if tg_op = 'UPDATE' then
    if old.opportunity_ref is not null then
      v_old_opportunity_id := old.opportunity_ref;
    elsif old.opportunity_id is not null
      and btrim(old.opportunity_id) ~*
        '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
    then
      v_old_opportunity_id := old.opportunity_id::uuid;
    end if;
  end if;

  -- The token can only be inserted by the revoked SECURITY DEFINER conversion
  -- function. Consume it before ordinary project-write authorization so a
  -- pipeline.convert:assigned actor can reach the RPC-owned project link.
  delete from private.opportunity_conversion_project_link_tokens token
   where token.transaction_id = txid_current()
     and token.backend_pid = pg_backend_pid()
     and token.project_id = new.id
     and token.opportunity_id = v_new_opportunity_id
     and token.company_id = new.company_id
     and token.operation = lower(tg_op)
  returning true into v_conversion_link_owned;

  if coalesce(v_conversion_link_owned, false) then
    return new;
  end if;

  -- Ordinary project writes. Company isolation is unconditional: a linked
  -- project may only ever be written by a member of its own tenant. The
  -- pipeline.manage @ all requirement applies only to writes that mutate the
  -- link contract itself; a crew member marking a converted job in progress is
  -- not performing pipeline management and must pass through. The legacy GUC
  -- remains bounded behind this check for the approval-queue path; setting it
  -- never grants authority by itself.
  if v_new_opportunity_id is not null or v_old_opportunity_id is not null then
    if coalesce(auth.role(), '') <> 'service_role' then
      if new.company_id is distinct from private.get_user_company_id() then
        raise exception 'access_denied'
          using errcode = '42501';
      end if;

      -- OLD is unassigned on INSERT, so branch on tg_op rather than relying on
      -- boolean short-circuiting, which Postgres does not guarantee.
      if tg_op = 'INSERT' then
        v_link_contract_mutated := true;
      else
        v_link_contract_mutated := (
          v_old_opportunity_id is distinct from v_new_opportunity_id
          or old.company_id is distinct from new.company_id
          or old.deleted_at is distinct from new.deleted_at
          or new.deleted_at is not null
        );
      end if;

      if v_link_contract_mutated
        and not private.current_user_has_permission('pipeline.manage', 'all')
      then
        raise exception 'access_denied'
          using errcode = '42501';
      end if;
    end if;
  end if;

  if current_setting('ops.skip_project_opportunity_invariant', true) = 'on' then
    return new;
  end if;

  if new.deleted_at is not null then
    if tg_op = 'UPDATE' and v_old_opportunity_id is not null then
      update public.opportunities
         set project_ref = null,
             project_id = null,
             updated_at = now()
       where id = v_old_opportunity_id
         and company_id = old.company_id
         and (project_ref = new.id or project_id = new.id);
    end if;
    return new;
  end if;

  if tg_op = 'UPDATE' then
    if v_old_opportunity_id is distinct from v_new_opportunity_id
      and v_old_opportunity_id is not null
    then
      update public.opportunities
         set project_ref = null,
             project_id = null,
             updated_at = now()
       where id = v_old_opportunity_id
         and company_id = old.company_id
         and (project_ref = new.id or project_id = new.id);
    end if;
  end if;

  if v_new_opportunity_id is null then
    return new;
  end if;

  if tg_op = 'UPDATE'
    and v_old_opportunity_id is not distinct from v_new_opportunity_id
    and old.company_id is not distinct from new.company_id
    and not (new.status in ('accepted', 'in_progress', 'completed', 'closed'))
  then
    return new;
  end if;

  select o.stage, o.stage_entered_at, o.project_ref, o.project_id
    into v_from_stage, v_stage_entered_at,
         v_existing_project_ref, v_existing_project_legacy
    from public.opportunities o
   where o.id = v_new_opportunity_id
     and o.company_id = new.company_id
     and o.deleted_at is null
   for update;

  if not found then
    raise exception 'project opportunity link target was not found'
      using errcode = '23503';
  end if;

  if v_existing_project_ref is not null
    and v_existing_project_legacy is not null
    and v_existing_project_ref is distinct from v_existing_project_legacy
  then
    raise exception 'opportunity project mirrors disagree'
      using errcode = '23505';
  end if;

  v_existing_project_id := coalesce(
    v_existing_project_ref,
    v_existing_project_legacy
  );

  if v_existing_project_id is not null
    and v_existing_project_id is distinct from new.id
  then
    raise exception 'opportunity is already linked to another project'
      using errcode = '23505';
  end if;

  update public.opportunities
     set project_ref = new.id,
         project_id = new.id,
         stage = 'won',
         stage_entered_at = case
           when v_from_stage is distinct from 'won' then now()
           else stage_entered_at
         end,
         stage_manually_set = true,
         actual_close_date = coalesce(actual_close_date, now()::date),
         updated_at = now()
   where id = v_new_opportunity_id
     and company_id = new.company_id;

  if v_from_stage is distinct from 'won' then
    insert into public.stage_transitions (
      company_id,
      opportunity_id,
      from_stage,
      to_stage,
      transitioned_at,
      transitioned_by,
      duration_in_stage
    ) values (
      new.company_id,
      v_new_opportunity_id,
      v_from_stage,
      'won',
      now(),
      null,
      now() - coalesce(v_stage_entered_at, now())
    );
  end if;

  return new;
end;
$function$;

-- Re-assert the existing ACL. CREATE OR REPLACE preserves it, but the trigger
-- function must never be directly callable.
revoke all on function public.enforce_project_opportunity_link()
  from public, anon, authenticated;

commit;

-- VERIFY AFTER APPLYING — by object, not by ledger version.
--
-- 1. The new gate is live (expects one row containing 'v_link_contract_mutated'):
--
--      select pg_get_functiondef('public.enforce_project_opportunity_link()'::regprocedure)
--             ilike '%v_link_contract_mutated%' as gate_scoped;
--
-- 2. The trigger binding survived unchanged (expects the AFTER INSERT OR DELETE
--    OR UPDATE OF opportunity_id, opportunity_ref, company_id, status,
--    deleted_at definition):
--
--      select pg_get_triggerdef(oid)
--        from pg_trigger
--       where tgrelid = 'public.projects'::regclass
--         and tgname = 'projects_enforce_opportunity_link';
--
-- 3. The activation block is untouched (expects true):
--
--      select pg_get_functiondef('public.enforce_project_opportunity_link()'::regprocedure)
--             ilike '%stage_manually_set = true%' as auto_win_preserved;
--
-- 4. The link contract still holds across every live pair (expects 0):
--
--      select count(*)
--        from public.projects p
--        join public.opportunities o on o.id = p.opportunity_ref
--       where p.deleted_at is null and o.deleted_at is null
--         and (o.project_ref is distinct from p.id
--              or o.project_id is distinct from p.id
--              or o.company_id is distinct from p.company_id);
--
-- 5. Field proof: a crew account with no pipeline.manage moves a linked project
--    to in_progress from the iOS app and it succeeds. Baseline for that account:
--
--      select coalesce(private.raw_permission_scope_for_user(u.id, u.company_id,
--               'pipeline.manage'), '(none)')
--        from public.users u where lower(u.email) = '<crew email>';
--
-- ROLLBACK: re-apply the body from
-- migrations/20260715160000_lead_assignment_foundation.sql, which carries the
-- pre-change definition of this function.
