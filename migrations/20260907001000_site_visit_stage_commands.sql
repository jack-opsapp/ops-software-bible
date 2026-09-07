-- Additive manual site-visit stage delivery. Legacy stage RPC is unchanged.
-- Apply only with explicit production migration approval. See P1-5 HANDOFF.
begin;

create table private.site_visit_stage_revisions (
  opportunity_id uuid primary key references public.opportunities(id) on delete cascade,
  revision uuid not null
);
alter table private.site_visit_stage_revisions enable row level security;
revoke all on private.site_visit_stage_revisions from public, anon, authenticated, service_role;

-- No FK cascade for receipts: deleting/recreating an entity must never make an
-- old command executable again. The minimal receipt has no customer content.
create table private.site_visit_stage_command_receipts (
  command_id uuid primary key,
  actor_user_id uuid not null,
  company_id uuid not null,
  request jsonb not null check (jsonb_typeof(request) = 'object'),
  result jsonb not null check (jsonb_typeof(result) = 'object'),
  created_at timestamptz not null default clock_timestamp()
);
alter table private.site_visit_stage_command_receipts enable row level security;
revoke all on private.site_visit_stage_command_receipts from public, anon, authenticated, service_role;

create function private.rotate_site_visit_stage_revision()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  -- AFTER row trigger sees the final values produced by existing BEFORE
  -- triggers. No company/advisory/visit locks here: the writer owns the parent
  -- row already. Existing rows use the reserved zero token until first change.
  if tg_op = 'UPDATE' and row(
    new.stage, new.stage_entered_at, new.stage_manually_set,
    new.stage_manual_boundary_event_id, new.stage_manual_boundary_at,
    new.stage_manual_corrected_at, new.assigned_to, new.assignment_version,
    new.company_id, new.deleted_at, new.archived_at,
    new.merged_into_opportunity_id, new.project_id, new.project_ref
  ) is not distinct from row(
    old.stage, old.stage_entered_at, old.stage_manually_set,
    old.stage_manual_boundary_event_id, old.stage_manual_boundary_at,
    old.stage_manual_corrected_at, old.assigned_to, old.assignment_version,
    old.company_id, old.deleted_at, old.archived_at,
    old.merged_into_opportunity_id, old.project_id, old.project_ref
  ) then
    return new;
  end if;
  insert into private.site_visit_stage_revisions(opportunity_id, revision)
  values (new.id, gen_random_uuid())
  on conflict (opportunity_id) do update set revision = excluded.revision;
  return new;
end;
$$;
revoke all on function private.rotate_site_visit_stage_revision() from public, anon, authenticated, service_role;
create trigger site_visit_stage_revision
after insert or update on public.opportunities
for each row execute function private.rotate_site_visit_stage_revision();

create function private.read_site_visit_stage_snapshot(p_opportunity_id uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  v_actor uuid := private.get_current_user_id();
  v_company uuid := private.get_user_company_id();
  v_result jsonb;
begin
  if coalesce(auth.jwt()->>'role', '') <> 'authenticated'
     or v_actor is null or v_company is null then
    raise exception 'site_visit_stage_access_denied' using errcode = '42501';
  end if;
  -- Single statement/MVCC snapshot: opportunity and its revision cannot come
  -- from different commits. No lazy INSERT and no timestamp round trip.
  select jsonb_build_object(
    'contract_version', 1, 'capability', 'site_visit_stage_command_v1',
    'actor_id', v_actor, 'company_id', v_company,
    'opportunity_id', o.id, 'stage', o.stage,
    'stage_revision', coalesce(r.revision, '00000000-0000-0000-0000-000000000000'::uuid)::text,
    'stage_entered_at', to_char(o.stage_entered_at at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),
    'can_move', o.archived_at is null and o.deleted_at is null
      and o.merged_into_opportunity_id is null
      and o.project_id is null and o.project_ref is null
      and o.stage not in ('won', 'lost', 'discarded')
  ) into v_result
  from public.opportunities o
  left join private.site_visit_stage_revisions r on r.opportunity_id = o.id
  where o.id = p_opportunity_id and o.company_id = v_company
    and private.user_can_edit_opportunity(v_actor, o.id);
  if v_result is null then
    raise exception 'site_visit_stage_access_denied' using errcode = '42501';
  end if;
  return v_result;
end;
$$;

create function public.read_site_visit_stage_snapshot(p_opportunity_id uuid)
returns jsonb language sql stable security invoker set search_path = '' as $$
  select private.read_site_visit_stage_snapshot(p_opportunity_id);
$$;

create function private.apply_site_visit_stage_command(
  p_command_id uuid, p_site_visit_id uuid, p_opportunity_id uuid,
  p_to_stage text, p_expected_stage text, p_expected_revision text,
  p_expected_actor_id uuid, p_expected_company_id uuid
)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_actor uuid := private.get_current_user_id();
  v_company uuid := private.get_user_company_id();
  v_visit public.site_visits%rowtype;
  v_opportunity public.opportunities%rowtype;
  v_stored private.site_visit_stage_command_receipts%rowtype;
  v_request jsonb;
  v_result jsonb;
  v_revision text;
  v_reason text;
  v_outcome text := 'applied';
  v_transition uuid;
  v_visit_found boolean;
  v_phase_c text := current_setting('ops.phase_c_stage_apply', true);
  v_source text := current_setting('ops.lifecycle_source', true);
  v_source_actor text := current_setting('ops.lifecycle_actor_user_id', true);
begin
  if coalesce(auth.jwt()->>'role', '') <> 'authenticated'
     or v_actor is null or v_company is null
     or p_expected_actor_id is distinct from v_actor
     or p_expected_company_id is distinct from v_company then
    raise exception 'site_visit_stage_access_denied' using errcode = '42501';
  end if;
  if p_command_id is null or p_site_visit_id is null or p_opportunity_id is null
     or p_to_stage is null or p_expected_stage is null
     or p_to_stage not in ('qualifying', 'quoting', 'quoted', 'follow_up', 'negotiation')
     or p_expected_stage not in ('new_lead', 'qualifying', 'quoting', 'quoted', 'follow_up', 'negotiation', 'won', 'lost', 'discarded')
     or p_expected_revision is null
     or p_expected_revision !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
    raise exception 'invalid_site_visit_stage_command' using errcode = '22023';
  end if;
  v_request := jsonb_build_object(
    'expected_actor_id', p_expected_actor_id, 'expected_company_id', p_expected_company_id,
    'site_visit_id', p_site_visit_id, 'opportunity_id', p_opportunity_id,
    'to_stage', p_to_stage, 'expected_stage', p_expected_stage,
    'expected_revision', p_expected_revision
  );

  -- Canonical company lock precedes every row lock. Command lock serializes
  -- even accidental cross-company UUID reuse without exposing any receipt.
  perform private.lock_lead_assignment_company(v_company);
  perform pg_advisory_xact_lock(hashtextextended('site-visit-stage-command:' || p_command_id::text, 0));

  -- Completion owns visit then opportunity; booking can own opportunity then
  -- request the canonical company lock. Never wait for either row while
  -- holding company: NOWAIT breaks those reverse-order cycles with 55P03.
  -- The caller retries the unchanged command; no receipt/state is committed.
  select * into v_visit from public.site_visits
    where id = p_site_visit_id and company_id = v_company::text for update nowait;
  v_visit_found := found;
  -- Reject a foreign visit using an ordinary MVCC read. Do not probe/lock a
  -- different tenant's row (including its lock contention) before denial.
  if not v_visit_found and exists (
    select 1 from public.site_visits
    where id = p_site_visit_id and company_id is distinct from v_company::text
  ) then
    raise exception 'site_visit_stage_access_denied' using errcode = '42501';
  end if;
  select * into v_opportunity from public.opportunities
  where id = p_opportunity_id and company_id = v_company for update nowait;
  if not found or not private.user_can_edit_opportunity(v_actor, p_opportunity_id) then
    raise exception 'site_visit_stage_access_denied' using errcode = '42501';
  end if;
  if v_visit_found and (
    v_visit.company_id is distinct from v_company::text
    or not private.current_user_can_edit_site_visit(
      v_visit.company_id, v_visit.opportunity_id, v_visit.project_id, v_visit.project_ref
    )
  ) then
    raise exception 'site_visit_stage_access_denied' using errcode = '42501';
  end if;

  select * into v_stored from private.site_visit_stage_command_receipts
  where command_id = p_command_id;
  if found then
    if v_stored.actor_user_id is distinct from v_actor
       or v_stored.company_id is distinct from v_company then
      raise exception 'site_visit_stage_access_denied' using errcode = '42501';
    end if;
    if v_stored.request is distinct from v_request then
      raise exception 'command_payload_mismatch' using errcode = '22023';
    end if;
    if v_stored.result->>'outcome' = 'applied' then
      return jsonb_set(v_stored.result, '{outcome}', '"already_applied"'::jsonb);
    end if;
    return v_stored.result;
  end if;

  select coalesce((select revision from private.site_visit_stage_revisions
    where opportunity_id = p_opportunity_id), '00000000-0000-0000-0000-000000000000'::uuid)::text
  into v_revision;

  if v_opportunity.archived_at is not null or v_opportunity.deleted_at is not null
     or v_opportunity.merged_into_opportunity_id is not null
     or v_opportunity.project_id is not null or v_opportunity.project_ref is not null
     or v_opportunity.stage in ('won', 'lost', 'discarded') then
    v_reason := 'opportunity_unavailable';
  elsif v_visit_found and (v_visit.deleted_at is not null or v_visit.status::text = 'cancelled') then
    v_reason := 'visit_unavailable';
  elsif v_visit_found and v_visit.opportunity_id is distinct from p_opportunity_id then
    v_reason := 'visit_binding_changed';
  elsif v_opportunity.stage is distinct from p_to_stage and (
    v_opportunity.stage is distinct from p_expected_stage
    or v_revision is distinct from p_expected_revision
  ) then
    v_reason := 'snapshot_mismatch';
  elsif not v_visit_found or v_visit.status::text <> 'completed' or v_visit.completed_at is null then
    return jsonb_build_object('contract_version', 1, 'command_id', p_command_id,
      'outcome', 'not_ready', 'reason', 'visit_not_ready', 'receipt', null);
  elsif v_opportunity.stage = p_to_stage then
    -- Completion or another writer already supplied the requested stage.
    -- Acknowledge current satisfaction only: no stage/transition/manual write,
    -- no rebase of the original request, and no claim this command caused it.
    -- Original immutable receipts were resolved before this current-state test.
    v_outcome := 'already_satisfied';
  end if;

  if v_reason is null and v_outcome = 'applied' then
    -- Reuse canonical manual attribution, manual boundary, external lifecycle,
    -- transition and delegate notification behavior, under our held guards.
    perform set_config('ops.phase_c_stage_apply', '0', true);
    select * into v_opportunity from public.move_opportunity_stage(
      p_opportunity_id, p_to_stage, v_actor, null
    );
    perform set_config('ops.phase_c_stage_apply', coalesce(v_phase_c, ''), true);
    perform set_config('ops.lifecycle_source', coalesce(v_source, ''), true);
    perform set_config('ops.lifecycle_actor_user_id', coalesce(v_source_actor, ''), true);
    select revision::text into strict v_revision
      from private.site_visit_stage_revisions where opportunity_id = p_opportunity_id;
    select id into strict v_transition from public.stage_transitions
      where opportunity_id = p_opportunity_id and company_id = v_company
        and from_stage = p_expected_stage and to_stage = p_to_stage
        and transitioned_by = v_actor and transitioned_at = v_opportunity.stage_entered_at;
  end if;

  v_result := jsonb_build_object(
    'contract_version', 1, 'command_id', p_command_id,
    'outcome', case when v_reason is null then v_outcome else 'conflict' end,
    'reason', v_reason,
    'receipt', jsonb_build_object(
      'opportunity_id', p_opportunity_id, 'stage', v_opportunity.stage,
      'stage_revision', v_revision,
      'stage_entered_at', to_char(v_opportunity.stage_entered_at at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),
      'transition_id', v_transition,
      'recorded_at', to_char(clock_timestamp() at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"')
    )
  );
  insert into private.site_visit_stage_command_receipts(command_id, actor_user_id, company_id, request, result)
  values (p_command_id, v_actor, v_company, v_request, v_result);
  return v_result;
end;
$$;

create function public.apply_site_visit_stage_command(
  p_command_id uuid, p_site_visit_id uuid, p_opportunity_id uuid,
  p_to_stage text, p_expected_stage text, p_expected_revision text,
  p_expected_actor_id uuid, p_expected_company_id uuid
)
returns jsonb language sql security invoker set search_path = '' as $$
  select private.apply_site_visit_stage_command(
    p_command_id, p_site_visit_id, p_opportunity_id,
    p_to_stage, p_expected_stage, p_expected_revision,
    p_expected_actor_id, p_expected_company_id
  );
$$;

revoke all on function private.read_site_visit_stage_snapshot(uuid), public.read_site_visit_stage_snapshot(uuid),
  private.apply_site_visit_stage_command(uuid,uuid,uuid,text,text,text,uuid,uuid),
  public.apply_site_visit_stage_command(uuid,uuid,uuid,text,text,text,uuid,uuid)
from public, anon, authenticated, service_role;
grant usage on schema private to authenticated;
grant execute on function private.read_site_visit_stage_snapshot(uuid), public.read_site_visit_stage_snapshot(uuid),
  private.apply_site_visit_stage_command(uuid,uuid,uuid,text,text,text,uuid,uuid),
  public.apply_site_visit_stage_command(uuid,uuid,uuid,text,text,text,uuid,uuid)
to authenticated;

notify pgrst, 'reload schema';
commit;
