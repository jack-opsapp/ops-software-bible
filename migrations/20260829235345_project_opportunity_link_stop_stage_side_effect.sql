-- D3 of ops-software-bible/specs/plans/2026-08-18-lead-project-identity-design.md
-- — bug 9a89b951. The link trigger stops winning the linked lead as a side
-- effect of project status. It keeps enforcing the link contract (mirrors,
-- unlink, permission gates — its legitimate job). Winning now always has a
-- human actor: iOS and web prompt on entering accepted/in_progress/completed/
-- closed and commit through public.win_linked_opportunity (ledger
-- 20260829074731); conversion continues to set 'won' itself inside its own
-- token-guarded transaction and is unaffected.
--
-- Base: the LIVE body fetched via pg_get_functiondef immediately before this
-- apply (2026-08-29), with exactly two write-side deletions and nothing else:
-- the four stage-bookkeeping assignments in the final UPDATE, and the
-- trailing stage_transitions INSERT block. v_from_stage / v_stage_entered_at
-- remain declared and selected.
--
-- Rollback: re-apply the body from
-- ops-software-bible/migrations/20260818184224_project_opportunity_link_crew_status_unblock.sql

CREATE OR REPLACE FUNCTION public.enforce_project_opportunity_link()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'private', 'pg_temp'
AS $function$
declare
  v_new_opportunity_id uuid;
  v_old_opportunity_id uuid;
  v_from_stage text;
  v_stage_entered_at timestamptz;
  v_existing_project_ref uuid;
  v_existing_project_legacy uuid;
  v_conversion_link_owned boolean := false;
  v_existing_project_id uuid;
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

  if v_new_opportunity_id is not null or v_old_opportunity_id is not null then
    if coalesce(auth.role(), '') <> 'service_role' then
      if new.company_id is distinct from private.get_user_company_id() then
        raise exception 'access_denied'
          using errcode = '42501';
      end if;

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
         updated_at = now()
   where id = v_new_opportunity_id
     and company_id = new.company_id;

  return new;
end;
$function$;
