--
-- D3 of ops-software-bible/specs/plans/2026-08-18-lead-project-identity-design.md
-- — bug 9a89b951. The one deliberate door around the client's `.won`
-- rejection in OpportunityRepository.validateDirectStageMutation: that
-- guard exists because winning an UNLINKED lead mints a won-without-
-- project orphan. This RPC re-verifies the link under a row lock, so it
-- structurally cannot do that, and it stamps the human actor into
-- stage_transitions — which is the whole point of D3.
--
-- SECURITY INVOKER: RLS `role_scope_update` on opportunities is
-- private.current_user_can_edit_opportunity(id) for both USING and
-- CHECK, so a caller who may not edit this lead selects nothing here and
-- gets opportunity_not_found. Nothing below uses auth.uid(), which is
-- unusable under the Firebase JWT bridge.

create or replace function public.win_linked_opportunity(
  p_opportunity_id uuid,
  p_project_id uuid,
  p_user_id uuid
) returns opportunities
language plpgsql
set search_path to 'public'
as $function$
declare
  v_company_id uuid;
  v_from_stage text;
  v_prior_entered_at timestamptz;
  v_project_ref uuid;
  v_project_legacy uuid;
  v_now timestamptz := now();
  v_updated opportunities;
begin
  -- RLS applies (SECURITY INVOKER): a caller who cannot edit this lead
  -- selects nothing here and gets opportunity_not_found.
  select company_id, stage, stage_entered_at, project_ref, project_id
    into v_company_id, v_from_stage, v_prior_entered_at, v_project_ref, v_project_legacy
    from opportunities
   where id = p_opportunity_id
     and deleted_at is null
   for update;

  if v_company_id is null then
    raise exception 'opportunity_not_found' using errcode = 'P0002';
  end if;

  -- This door is for LINKED leads only. Winning an unlinked lead stays with
  -- the guarded conversion (convert_opportunity_to_project) — that is what
  -- keeps this from minting won-without-project orphans.
  if coalesce(v_project_ref, v_project_legacy) is distinct from p_project_id then
    raise exception 'opportunity_not_linked_to_project' using errcode = '23514';
  end if;

  -- Already won (a concurrent actor got there first): idempotent no-op,
  -- mirroring move_opportunity_stage's same-stage behavior.
  if v_from_stage = 'won' then
    select * into v_updated from opportunities where id = p_opportunity_id;
    return v_updated;
  end if;

  -- A terminal loss is not silently revived by a confirm dialog.
  if v_from_stage in ('lost', 'discarded') then
    raise exception 'opportunity_stage_terminal' using errcode = '22023';
  end if;

  update opportunities
     set stage              = 'won',
         stage_entered_at   = v_now,
         stage_manually_set = true,
         actual_close_date  = coalesce(actual_close_date, v_now::date),
         updated_at         = v_now
   where id = p_opportunity_id
   returning * into v_updated;

  -- RLS role_scope_update filters silently (USING, not CHECK, on an
  -- un-editable row): 0 rows updated must be a loud permission error, not a
  -- null row the client fails to decode.
  if v_updated.id is null then
    raise exception 'access_denied' using errcode = '42501';
  end if;

  -- The actor is the human who confirmed — never null (D3).
  insert into stage_transitions (
    company_id, opportunity_id, from_stage, to_stage,
    transitioned_at, transitioned_by, duration_in_stage
  ) values (
    v_company_id, p_opportunity_id, v_from_stage, 'won',
    v_now, p_user_id, v_now - v_prior_entered_at
  );

  return v_updated;
end;
$function$;
