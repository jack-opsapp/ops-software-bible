-- Guard human lead conversion at the final transaction boundary.
--
-- Active same-address projects are authoritative match candidates. A human
-- create without an explicit target may proceed only when the row-locked scan
-- is empty; otherwise the client must refresh preflight and choose MATCH.
-- Completed/cancelled projects remain review history and do not block a new job.
--
-- The address advisory lock serializes every active-project identity writer at
-- one site. Candidate rows are then locked by id before the opportunity row,
-- preserving the canonical project -> opportunity lock order.

-- Every active-project identity writer shares one address lock domain. This
-- includes ordinary inserts/updates, email conversion, and human conversion;
-- therefore a clean human scan cannot be followed by a same-address phantom.
-- Address locks are always acquired before client locks, with each set sorted,
-- so multi-identity updates have one deterministic global order.

create or replace function private.project_address_dedupe_lock_key(
  p_company_id uuid,
  p_address text
)
returns bigint
language sql
immutable
strict
set search_path to 'pg_catalog', 'public', 'private', 'pg_temp'
as $function$
  select hashtextextended(
    'project_address_dedupe:' || p_company_id::text || ':' ||
      private.normalize_address(p_address),
    0
  );
$function$;

revoke all on function private.project_address_dedupe_lock_key(uuid, text)
  from public, anon, authenticated;

create or replace function private.acquire_project_identity_locks(
  p_address_lock_keys bigint[],
  p_client_lock_keys bigint[],
  p_wait boolean default false
)
returns void
language plpgsql
security definer
set search_path to 'pg_catalog', 'public', 'private', 'pg_temp'
as $function$
declare
  v_lock_key bigint;
  v_lock_acquired boolean;
begin
  for v_lock_key in
    select distinct locks.lock_value
      from unnest(coalesce(p_address_lock_keys, '{}'::bigint[]))
        as locks(lock_value)
     order by locks.lock_value
  loop
    if coalesce(p_wait, false) then
      perform pg_advisory_xact_lock(v_lock_key);
    else
      v_lock_acquired := pg_try_advisory_xact_lock(v_lock_key);
      if not v_lock_acquired then
        raise exception 'project_address_identity_busy'
          using errcode = '40001';
      end if;
    end if;
  end loop;

  for v_lock_key in
    select distinct locks.lock_value
      from unnest(coalesce(p_client_lock_keys, '{}'::bigint[]))
        as locks(lock_value)
     order by locks.lock_value
  loop
    if coalesce(p_wait, false) then
      perform pg_advisory_xact_lock(v_lock_key);
    else
      v_lock_acquired := pg_try_advisory_xact_lock(v_lock_key);
      if not v_lock_acquired then
        raise exception 'email_project_identity_busy'
          using errcode = '40001';
      end if;
    end if;
  end loop;
end;
$function$;

revoke all on function private.acquire_project_identity_locks(
  bigint[], bigint[], boolean
) from public, anon, authenticated;

create or replace function private.serialize_project_email_identity_change()
returns trigger
language plpgsql
security definer
set search_path to 'pg_catalog', 'public', 'private', 'pg_temp'
as $function$
declare
  v_address_lock_keys bigint[] := '{}'::bigint[];
  v_client_lock_keys bigint[] := '{}'::bigint[];
begin
  if tg_op <> 'INSERT'
    and old.company_id is not null
    and old.deleted_at is null
    and old.status in ('rfq', 'estimated', 'accepted', 'in_progress')
  then
    if nullif(private.normalize_address(old.address), '') is not null then
      v_address_lock_keys := array_append(
        v_address_lock_keys,
        private.project_address_dedupe_lock_key(
          old.company_id,
          old.address
        )
      );
    end if;
    if old.client_id is not null then
      v_client_lock_keys := array_append(
        v_client_lock_keys,
        private.email_project_dedupe_lock_key(
          old.company_id,
          old.client_id
        )
      );
    end if;
  end if;

  if tg_op <> 'DELETE'
    and new.company_id is not null
    and new.deleted_at is null
    and new.status in ('rfq', 'estimated', 'accepted', 'in_progress')
  then
    if nullif(private.normalize_address(new.address), '') is not null then
      v_address_lock_keys := array_append(
        v_address_lock_keys,
        private.project_address_dedupe_lock_key(
          new.company_id,
          new.address
        )
      );
    end if;
    if new.client_id is not null then
      v_client_lock_keys := array_append(
        v_client_lock_keys,
        private.email_project_dedupe_lock_key(
          new.company_id,
          new.client_id
        )
      );
    end if;
  end if;

  perform private.acquire_project_identity_locks(
    v_address_lock_keys,
    v_client_lock_keys,
    false
  );

  if tg_op = 'DELETE' then
    return old;
  end if;
  return new;
end;
$function$;

create index if not exists projects_active_company_normalized_address_idx
  on public.projects (
    company_id,
    private.normalize_address(address)
  )
  where deleted_at is null
    and status in ('rfq', 'estimated', 'accepted', 'in_progress');

create index if not exists projects_active_company_client_idx
  on public.projects (company_id, client_id)
  where deleted_at is null
    and status in ('rfq', 'estimated', 'accepted', 'in_progress');

CREATE OR REPLACE FUNCTION public.get_conversion_preflight(p_opportunity_id uuid, p_company_id uuid DEFAULT NULL::uuid, p_actor_user_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'private', 'pg_temp'
AS $function$
declare
  v_is_service boolean := coalesce(auth.role(), '') = 'service_role';
  v_actor_user_id uuid;
  v_company_id uuid;
  v_opp public.opportunities%rowtype;
  v_client_id uuid;
  v_client_name text;
  v_project_id uuid;
  v_project_accessible boolean := false;
  v_existing jsonb := null;
  v_candidates jsonb := '[]'::jsonb;
  v_others jsonb := '[]'::jsonb;
  v_creation_blocker text := null;
begin
  if p_opportunity_id is null then
    raise exception 'opportunity_not_found'
      using errcode = 'P0002';
  end if;

  if v_is_service then
    if p_company_id is null or p_actor_user_id is null then
      raise exception 'access_denied'
        using errcode = '42501';
    end if;
    v_company_id := p_company_id;
    v_actor_user_id := p_actor_user_id;
  else
    v_company_id := private.get_user_company_id();
    v_actor_user_id := private.get_current_user_id();
    if v_company_id is null
      or v_actor_user_id is null
      or (p_company_id is not null and p_company_id is distinct from v_company_id)
      or (
        p_actor_user_id is not null
        and p_actor_user_id is distinct from v_actor_user_id
      )
    then
      raise exception 'access_denied'
        using errcode = '42501';
    end if;
  end if;

  select *
    into v_opp
    from public.opportunities o
   where o.id = p_opportunity_id
     and o.company_id = v_company_id
     and o.deleted_at is null;
  if not found then
    raise exception 'opportunity_not_found'
      using errcode = 'P0002';
  end if;

  v_client_id := private.resolve_opportunity_client_id(
    v_opp.client_ref,
    v_opp.client_id
  );

  if not private.user_can_convert_opportunity(
    v_actor_user_id,
    p_opportunity_id
  ) then
    raise exception 'access_denied'
      using errcode = '42501';
  end if;

  if v_client_id is not null then
    select c.name
      into v_client_name
      from public.clients c
     where c.id = v_client_id
       and c.company_id = v_company_id;
  end if;

  v_project_id := coalesce(v_opp.project_ref, v_opp.project_id);
  if v_project_id is not null then
    v_project_accessible := private.user_can_view_project(
      v_actor_user_id,
      v_project_id
    );
    if v_project_accessible then
      select jsonb_build_object('id', p.id, 'title', p.title)
        into v_existing
        from public.projects p
       where p.id = v_project_id
         and p.company_id = v_company_id
         and p.deleted_at is null;
    end if;
  end if;

  -- A linked project outside the actor's project scope is only a recovery
  -- signal. Do not disclose its identity or scan sibling projects: the only
  -- valid follow-up is an idempotent conversion call with no link target.
  if v_project_id is not null
    and not v_project_accessible
  then
    return jsonb_build_object(
      'opportunity_id', p_opportunity_id,
      'assignment_version', v_opp.assignment_version,
      'already_converted', true,
      'project_accessible', false,
      'existing_linked_project', null,
      'duplicate_candidates', '[]'::jsonb,
      'other_client_projects', '[]'::jsonb,
      'creation_blocker', null,
      'suggested_name', private.derive_project_name(v_opp.address, v_client_name)
    );
  end if;

  select coalesce(jsonb_agg(candidate.payload order by candidate.title, candidate.id), '[]'::jsonb)
    into v_candidates
    from (
      select
        p.id,
        p.title,
        jsonb_build_object(
          'project_id', p.id,
          'title', p.title,
          'address', p.address,
          'confidence', case
            when p.client_id is not distinct from v_client_id
              and v_client_id is not null then 'high'
            else 'medium'
          end,
          'signals', case
            when p.client_id is not distinct from v_client_id
              and v_client_id is not null
              then jsonb_build_array('same_client', 'same_address')
            else jsonb_build_array('same_address')
          end
        ) as payload
      from public.projects p
      where p.company_id = v_company_id
        and p.deleted_at is null
        and p.status in ('rfq', 'estimated', 'accepted', 'in_progress')
        and (v_project_id is null or p.id <> v_project_id)
        and nullif(btrim(coalesce(v_opp.address, '')), '') is not null
        and private.normalize_address(p.address) =
          private.normalize_address(v_opp.address)
        and private.normalize_address(p.address) <> ''
        and private.user_can_view_project(v_actor_user_id, p.id)
        and private.user_can_link_opportunity_to_project(v_actor_user_id, p.id)
    ) candidate;

  select coalesce(jsonb_agg(other_project.payload order by other_project.title, other_project.id), '[]'::jsonb)
    into v_others
    from (
      select
        p.id,
        p.title,
        jsonb_build_object(
          'project_id', p.id,
          'title', p.title,
          'address', p.address,
          'status', p.status
        ) as payload
      from public.projects p
      where p.company_id = v_company_id
        and p.deleted_at is null
        and v_client_id is not null
        and p.client_id = v_client_id
        and (v_project_id is null or p.id <> v_project_id)
        and private.user_can_view_project(v_actor_user_id, p.id)
        and not (
          p.status in ('rfq', 'estimated', 'accepted', 'in_progress')
          and nullif(btrim(coalesce(v_opp.address, '')), '') is not null
          and private.normalize_address(p.address) =
            private.normalize_address(v_opp.address)
          and private.normalize_address(p.address) <> ''
          and private.user_can_link_opportunity_to_project(v_actor_user_id, p.id)
        )
    ) other_project;

  if v_project_id is null then
    if nullif(private.normalize_address(v_opp.address), '') is null
      and (
        v_client_id is null
        or exists (
          select 1
            from public.projects p
           where p.company_id = v_company_id
             and p.client_id = v_client_id
             and p.deleted_at is null
             and p.status in ('rfq', 'estimated', 'accepted', 'in_progress')
        )
      )
    then
      v_creation_blocker := 'address_required';
    elsif nullif(private.normalize_address(v_opp.address), '') is not null
      and jsonb_array_length(v_candidates) = 0
      and exists (
        select 1
          from public.projects p
         where p.company_id = v_company_id
           and p.deleted_at is null
           and p.status in ('rfq', 'estimated', 'accepted', 'in_progress')
           and private.normalize_address(p.address) =
             private.normalize_address(v_opp.address)
           and private.normalize_address(p.address) <> ''
      )
    then
      v_creation_blocker := 'project_review_required';
    end if;
  end if;

  return jsonb_build_object(
    'opportunity_id', p_opportunity_id,
    'assignment_version', v_opp.assignment_version,
    'already_converted', v_project_id is not null,
    'project_accessible', coalesce(v_project_accessible, false),
    'existing_linked_project', v_existing,
    'duplicate_candidates', v_candidates,
    'other_client_projects', v_others,
    'creation_blocker', v_creation_blocker,
    'suggested_name', private.derive_project_name(v_opp.address, v_client_name)
  );
end;
$function$;

CREATE OR REPLACE FUNCTION public.convert_opportunity_to_project(p_company_id uuid, p_opportunity_id uuid, p_actual_value numeric DEFAULT NULL::numeric, p_expected_stage text DEFAULT NULL::text, p_decided_by uuid DEFAULT NULL::uuid, p_notes text DEFAULT NULL::text, p_title_override text DEFAULT NULL::text, p_link_to_project_id uuid DEFAULT NULL::uuid, p_source_path text DEFAULT NULL::text, p_win_opportunity boolean DEFAULT true, p_project_status text DEFAULT NULL::text, p_evidence jsonb DEFAULT '{}'::jsonb, p_expected_assignment_version bigint DEFAULT NULL::bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'private', 'pg_temp'
AS $function$
declare
  v_opp public.opportunities%rowtype;
  v_target public.projects%rowtype;
  v_is_service boolean := coalesce(auth.role(), '') = 'service_role';
  v_actor_user_id uuid;
  v_actor_company_id uuid;
  v_result jsonb;
  v_project_id uuid;
  v_link_to_project_id uuid := p_link_to_project_id;
  v_matched_project_id uuid;
  v_candidate_count integer := 0;
  v_candidate_has_conflicting_link boolean := false;
  v_target_legacy_opportunity_id uuid;
  v_initial_client_id uuid;
  v_initial_normalized_address text;
  v_initial_preflight_address text;
  v_initial_project_id uuid;
  v_conversion_event_id uuid;
  v_existing_conversion_complete boolean := false;
  v_existing_conversion_actor_id uuid;
  v_existing_conversion_evidence jsonb;
  v_exact_completed_retry boolean := false;
  v_existing_linked_existing boolean := false;
  v_project_accessible boolean := false;
begin
  if p_company_id is null or p_opportunity_id is null then
    raise exception 'company and opportunity ids are required'
      using errcode = '22023';
  end if;

  select *
    into v_opp
    from public.opportunities o
   where o.id = p_opportunity_id
     and o.company_id = p_company_id;

  if not found or v_opp.deleted_at is not null then
    raise exception 'opportunity_not_found'
      using errcode = 'P0002';
  end if;
  v_initial_client_id := private.resolve_opportunity_client_id(
    v_opp.client_ref,
    v_opp.client_id
  );
  v_initial_normalized_address :=
    private.normalize_email_project_dedupe_address(v_opp.address);
  v_initial_preflight_address := private.normalize_address(v_opp.address);
  if v_opp.project_ref is not null
    and v_opp.project_id is not null
    and v_opp.project_ref is distinct from v_opp.project_id
  then
    raise exception 'opportunity project mirrors disagree'
      using errcode = '23505';
  end if;
  v_initial_project_id := coalesce(v_opp.project_ref, v_opp.project_id);

  if v_is_service then
    if p_expected_assignment_version is null
      or p_expected_assignment_version < 0
    then
      raise exception 'invalid_assignment_snapshot'
        using errcode = '22023';
    end if;

    if p_decided_by is not null then
      if p_source_path not in ('won_dialog', 'approval_queue')
        or not private.user_can_convert_opportunity(
          p_decided_by,
          p_opportunity_id
        )
      then
        raise exception 'access_denied'
          using errcode = '42501';
      end if;
      v_actor_user_id := p_decided_by;
    else
      -- Model-only likely-Won labels remain review notifications. Only the
      -- deterministic complete-conversation decision may authorize an
      -- actorless conversion.
      if p_source_path <> 'email_accept' then
        raise exception 'access_denied'
          using errcode = '42501';
      end if;
    end if;
  else
    v_actor_user_id := private.get_current_user_id();
    v_actor_company_id := private.get_user_company_id();

    if v_actor_user_id is null
      or v_actor_company_id is distinct from p_company_id
      or p_source_path not in ('won_dialog', 'approval_queue', 'ios')
      or (
        p_decided_by is not null
        and p_decided_by is distinct from v_actor_user_id
      )
      or not private.user_can_convert_opportunity(
        v_actor_user_id,
        p_opportunity_id
      )
    then
      raise exception 'access_denied'
        using errcode = '42501';
    end if;

    if p_expected_assignment_version is null
      and p_source_path is distinct from 'ios'
    then
      raise exception 'invalid_assignment_snapshot'
        using errcode = '22023';
    end if;
    if p_expected_assignment_version < 0 then
      raise exception 'invalid_assignment_snapshot'
        using errcode = '22023';
    end if;
  end if;

  -- Existing-project conversions follow project -> opportunity lock order,
  -- matching the bidirectional link trigger. Every actorless create is also
  -- serialized by client. Addressed leads inspect every active exact-street
  -- match (including already-linked rows); no-address leads inspect every active
  -- client project and may create only when that exhaustive set is empty.
  if v_actor_user_id is null and v_initial_client_id is null then
    raise exception 'project_link_unavailable: dedupe_proof_unavailable'
      using errcode = 'P0002';
  end if;

  -- Human conversions without an existing canonical link serialize on the
  -- exact preflight identity before locking candidate project rows. This closes
  -- the clean-preflight/create race while preserving project -> opportunity
  -- row-lock order. Blank-address conversions serialize by client and must
  -- prove that no other active client project exists.
  if v_actor_user_id is not null and v_initial_project_id is null then
    if nullif(v_initial_preflight_address, '') is null then
      if v_initial_client_id is null then
        raise exception 'project_link_unavailable: dedupe_proof_unavailable'
          using errcode = 'P0002';
      end if;
    end if;

    perform private.acquire_project_identity_locks(
      case
        when nullif(v_initial_preflight_address, '') is null
          then '{}'::bigint[]
        else array[
          private.project_address_dedupe_lock_key(
            p_company_id,
            v_opp.address
          )
        ]
      end,
      case
        when v_initial_client_id is null then '{}'::bigint[]
        else array[
          private.email_project_dedupe_lock_key(
            p_company_id,
            v_initial_client_id
          )
        ]
      end,
      true
    );
  end if;

  if v_initial_project_id is not null then
    select target.*
      into v_target
      from public.projects target
     where target.id = v_initial_project_id
       and target.company_id = p_company_id
       and target.deleted_at is null
     for update;
    if not found then
      raise exception 'project_link_unavailable'
        using errcode = 'P0002';
    end if;
    if v_link_to_project_id is not null
      and v_link_to_project_id is distinct from v_initial_project_id
    then
      raise exception 'opportunity is already linked to another project'
        using errcode = '23505';
    end if;
    v_link_to_project_id := v_initial_project_id;
  elsif v_actor_user_id is null then
    perform private.acquire_project_identity_locks(
      case
        when nullif(v_initial_preflight_address, '') is null
          then '{}'::bigint[]
        else array[
          private.project_address_dedupe_lock_key(
            p_company_id,
            v_opp.address
          )
        ]
      end,
      array[
        private.email_project_dedupe_lock_key(
          p_company_id,
          v_initial_client_id
        )
      ],
      false
    );

    -- A caller-proposed existing project is only a hint. Re-prove that it is
    -- the active project for this exact client/street identity.
    if v_link_to_project_id is not null then
      if nullif(v_initial_normalized_address, '') is null then
        raise exception 'project_link_unavailable: dedupe_proof_unavailable'
          using errcode = 'P0002';
      end if;

      select target.*
        into v_target
        from public.projects target
       where target.id = v_link_to_project_id
         and target.company_id = p_company_id
         and target.client_id = v_initial_client_id
         and target.deleted_at is null
         and target.status in ('rfq', 'estimated', 'accepted', 'in_progress')
         and private.normalize_email_project_dedupe_address(target.address) =
           v_initial_normalized_address
       for update;

      if not found then
        raise exception 'project_link_unavailable'
          using errcode = 'P0002';
      end if;
    end if;

    if nullif(v_initial_normalized_address, '') is null then
      for v_target in
        select target.*
        from public.projects target
        where target.company_id = p_company_id
          and target.client_id = v_initial_client_id
          and target.deleted_at is null
          and target.status in ('rfq', 'estimated', 'accepted', 'in_progress')
        order by target.id
        for update
      loop
        v_candidate_count := v_candidate_count + 1;
      end loop;

      if v_candidate_count > 0 then
        raise exception 'project_link_unavailable: dedupe_proof_unavailable'
          using errcode = 'P0002';
      end if;
    else
      for v_target in
        select target.*
        from public.projects target
        where target.company_id = p_company_id
          and target.client_id = v_initial_client_id
          and target.deleted_at is null
          and target.status in ('rfq', 'estimated', 'accepted', 'in_progress')
          and private.normalize_email_project_dedupe_address(target.address) =
            v_initial_normalized_address
        order by target.id
        for update
      loop
        v_candidate_count := v_candidate_count + 1;
        v_matched_project_id := v_target.id;
        v_target_legacy_opportunity_id := private.try_parse_uuid(
          v_target.opportunity_id::text
        );

        -- A non-empty malformed legacy mirror or either mirror pointing at a
        -- different lead makes this street unsafe. A one-way link to this same
        -- opportunity is repairable and remains the sole candidate.
        if (
          nullif(btrim(v_target.opportunity_id::text), '') is not null
          and v_target_legacy_opportunity_id is null
        ) or (
          v_target.opportunity_ref is not null
          and v_target.opportunity_ref is distinct from p_opportunity_id
        ) or (
          v_target_legacy_opportunity_id is not null
          and v_target_legacy_opportunity_id is distinct from p_opportunity_id
        ) then
          v_candidate_has_conflicting_link := true;
        end if;
      end loop;

      if v_candidate_has_conflicting_link then
        raise exception 'project_link_unavailable: matching_project_link_conflict'
          using errcode = 'P0002';
      end if;
      if v_candidate_count > 1 then
        raise exception 'project_link_ambiguous'
          using errcode = 'P0003';
      end if;
      if v_candidate_count = 1 then
        if v_link_to_project_id is not null
          and v_link_to_project_id is distinct from v_matched_project_id
        then
          raise exception 'project_link_unavailable'
            using errcode = 'P0002';
        end if;
        v_link_to_project_id := v_matched_project_id;
      end if;
    end if;
  elsif v_actor_user_id is not null and v_initial_project_id is null then
    if v_link_to_project_id is not null then
      select target.*
        into v_target
        from public.projects target
       where target.id = v_link_to_project_id
         and target.company_id = p_company_id
         and target.deleted_at is null
       for update;

      if not found then
        raise exception 'project_link_unavailable'
          using errcode = 'P0002';
      end if;
    elsif nullif(v_initial_preflight_address, '') is null then
      for v_target in
        select target.*
        from public.projects target
        where target.company_id = p_company_id
          and target.client_id = v_initial_client_id
          and target.deleted_at is null
          and target.status in ('rfq', 'estimated', 'accepted', 'in_progress')
        order by target.id
        for update
      loop
        v_candidate_count := v_candidate_count + 1;
      end loop;

      if v_candidate_count > 0 then
        raise exception 'project_link_unavailable: address_required_for_project_match'
          using errcode = 'P0002';
      end if;
    else
      for v_target in
        select target.*
        from public.projects target
        where target.company_id = p_company_id
          and target.deleted_at is null
          and target.status in ('rfq', 'estimated', 'accepted', 'in_progress')
          and private.normalize_address(target.address) =
            v_initial_preflight_address
        order by target.id
        for update
      loop
        v_candidate_count := v_candidate_count + 1;
      end loop;

      if v_candidate_count > 0 then
        raise exception 'project_link_unavailable: matching_project_requires_review'
          using errcode = 'P0002';
      end if;
    end if;
  end if;

  select *
    into v_opp
    from public.opportunities o
   where o.id = p_opportunity_id
     and o.company_id = p_company_id
   for update;

  if not found or v_opp.deleted_at is not null then
    raise exception 'opportunity_not_found'
      using errcode = 'P0002';
  end if;
  if coalesce(v_opp.project_ref, v_opp.project_id) is distinct from
    v_initial_project_id
  then
    return jsonb_build_object(
      'converted', false,
      'already_converted', false,
      'guard_reason', 'snapshot_mismatch',
      'opportunity_id', p_opportunity_id,
      'assigned_to', v_opp.assigned_to,
      'assignment_version', v_opp.assignment_version,
      'project_accessible', false
    );
  end if;
  if (
    v_actor_user_id is null
    and (
      private.resolve_opportunity_client_id(
        v_opp.client_ref,
        v_opp.client_id
      ) is distinct from v_initial_client_id
      or private.normalize_email_project_dedupe_address(v_opp.address)
        is distinct from
        v_initial_normalized_address
    )
  ) or (
    v_actor_user_id is not null
    and v_initial_project_id is null
    and (
      private.resolve_opportunity_client_id(
        v_opp.client_ref,
        v_opp.client_id
      ) is distinct from v_initial_client_id
      or private.normalize_address(v_opp.address)
        is distinct from
        v_initial_preflight_address
    )
  )
  then
    return jsonb_build_object(
      'converted', false,
      'already_converted', false,
      'guard_reason', 'snapshot_mismatch',
      'opportunity_id', p_opportunity_id,
      'assigned_to', v_opp.assigned_to,
      'assignment_version', v_opp.assignment_version,
      'project_accessible', false
    );
  end if;

  -- The BEFORE INSERT correspondence trigger takes the same opportunity lock,
  -- closing the gap between durable insertion and counter projection. Never
  -- decide a commercial outcome while any meaningful event is pending.
  if v_actor_user_id is null
    and private.opportunity_has_pending_meaningful_email(
      p_company_id,
      p_opportunity_id
    )
  then
    raise exception 'meaningful correspondence projection pending'
      using errcode = '40001';
  end if;

  -- Revalidate durable evidence only after the opportunity lock. New
  -- correspondence projections take the same lock, so the high-water check
  -- and conversion are serialized.
  if v_is_service
    and p_decided_by is null
    and not private.valid_actorless_opportunity_conversion_evidence(
      p_company_id,
      p_opportunity_id,
      p_source_path,
      coalesce(p_evidence, '{}'::jsonb)
    )
  then
    raise exception 'access_denied'
      using errcode = '42501';
  end if;

  -- Authorization was initially checked before project-first locking. Repeat it
  -- from the locked opportunity snapshot so assignment-scoped and snapshotless
  -- iOS callers cannot win a race with reassignment.
  if v_actor_user_id is not null
    and not private.user_can_convert_opportunity(
      v_actor_user_id,
      p_opportunity_id
    )
  then
    raise exception 'access_denied'
      using errcode = '42501';
  end if;

  if p_expected_assignment_version is not null
    and v_opp.assignment_version is distinct from p_expected_assignment_version
  then
    return jsonb_build_object(
      'converted', false,
      'already_converted', false,
      'guard_reason', 'assignment_snapshot_mismatch',
      'opportunity_id', p_opportunity_id,
      'assigned_to', v_opp.assigned_to,
      'assignment_version', v_opp.assignment_version,
      'project_accessible', false
    );
  end if;

  -- A project pointer is not proof that conversion completed. Only the durable
  -- canonical event establishes completion; its linked disposition binds an
  -- actorless repair retry to the exact original email decision.
  if v_link_to_project_id is not null then
    select event.id,
           event.actor_user_id,
           disposition.evidence
      into v_conversion_event_id,
           v_existing_conversion_actor_id,
           v_existing_conversion_evidence
      from public.opportunity_conversion_events event
      left join public.opportunity_dispositions disposition
        on disposition.id = private.try_parse_uuid(
          event.payload ->> 'disposition_id'
        )
       and disposition.company_id = event.company_id
       and disposition.opportunity_id = event.opportunity_id
       and disposition.converted_project_ref = event.project_id
     where event.company_id = p_company_id
       and event.opportunity_id = p_opportunity_id
       and event.project_id = v_link_to_project_id
       and event.event_type = 'converted_to_project'
     order by event.created_at desc, event.id desc
     limit 1;

    v_existing_conversion_complete := found;
    v_exact_completed_retry := v_existing_conversion_complete
      and v_actor_user_id is null
      and v_existing_conversion_actor_id is null
      and v_opp.stage = 'won'
      and coalesce(
        v_existing_conversion_evidence ->> 'source_path' = 'email_accept'
        and v_existing_conversion_evidence @> coalesce(
          p_evidence,
          '{}'::jsonb
        ),
        false
      );
  end if;

  -- A canonical actorless completion sets the Won stage lock itself. Only an
  -- exact retry of that completion may pass it; a mere project pointer or any
  -- later/different email decision remains subordinate to the operator lock.
  if v_actor_user_id is null
    and coalesce(v_opp.stage_manually_set, false)
    and not v_exact_completed_retry
  then
    return jsonb_build_object(
      'converted', false,
      'already_converted', false,
      'guard_reason', 'manual_stage_override',
      'opportunity_id', p_opportunity_id,
      'assigned_to', v_opp.assigned_to,
      'assignment_version', v_opp.assignment_version,
      'project_accessible', false
    );
  end if;

  if p_expected_stage is not null
    and v_opp.stage is distinct from p_expected_stage
    and not v_exact_completed_retry
    and not (
      v_actor_user_id is not null
      and v_initial_project_id is not null
    )
  then
    return jsonb_build_object(
      'converted', false,
      'already_converted', false,
      'guard_reason', 'snapshot_mismatch',
      'opportunity_id', p_opportunity_id,
      'assigned_to', v_opp.assigned_to,
      'assignment_version', v_opp.assignment_version,
      'project_accessible', false
    );
  end if;

  -- A guarded budget/timing Lost lead may reopen from new customer evidence.
  -- An OPS-authored schedule confirmation alone is not customer commitment;
  -- an OPS-authored confirmed payment is unequivocal and may reactivate it.
  if v_actor_user_id is null
    and not v_exact_completed_retry
    and (
      v_existing_conversion_complete
      or (
        v_opp.stage in ('won', 'lost', 'discarded')
        and not (
          v_opp.stage = 'lost'
          and exists (
            select 1
            from public.opportunity_dispositions disposition
            where disposition.company_id = p_company_id
              and disposition.opportunity_id = p_opportunity_id
              and disposition.disposition = 'lost'
              and disposition.reason_code = 'budget_timing'
              and disposition.decided_via = 'guarded_lifecycle'
              and disposition.superseded_at is null
          )
          and (
            p_evidence ->> 'decisive_direction' = 'inbound'
            or p_evidence -> 'signals' ? 'payment_confirmed'
          )
        )
      )
    )
  then
    return jsonb_build_object(
      'converted', false,
      'already_converted', false,
      'guard_reason', 'terminal_stage',
      'opportunity_id', p_opportunity_id,
      'assigned_to', v_opp.assigned_to,
      'assignment_version', v_opp.assignment_version,
      'project_accessible', false
    );
  end if;

  -- The preserved conversion core creates a new project from the legacy
  -- client_id mirror. Repair only a missing side of an already-validated
  -- canonical identity inside this conversion transaction; any failure later
  -- rolls this repair back with the conversion.
  if v_actor_user_id is null
    and (
      v_opp.client_ref is null
      or v_opp.client_id is null
    )
  then
    update public.opportunities opportunity
       set client_ref = v_initial_client_id,
           client_id = v_initial_client_id,
           updated_at = now()
     where opportunity.id = p_opportunity_id
       and opportunity.company_id = p_company_id
       and private.resolve_opportunity_client_id(
         opportunity.client_ref,
         opportunity.client_id
       ) = v_initial_client_id;
    if not found then
      raise exception 'opportunity_client_snapshot_mismatch'
        using errcode = '40001';
    end if;
    v_opp.client_ref := v_initial_client_id;
    v_opp.client_id := v_initial_client_id;
  end if;

  -- Completed conversions may run the canonical idempotent repair core only
  -- after every locked authorization/snapshot/terminal guard above. Preserve
  -- the existing human recovery path, but never mistake an actorless one-way
  -- project link with no conversion event for a completed conversion.
  if v_link_to_project_id is not null
    and (
      (
        v_actor_user_id is null
        and v_exact_completed_retry
      )
      or (
        v_actor_user_id is not null
        and v_initial_project_id is not null
      )
    )
  then
    if (
      v_target.opportunity_ref is not null
      and v_target.opportunity_ref is distinct from p_opportunity_id
    ) or (
      nullif(btrim(v_target.opportunity_id::text), '') is not null
      and private.try_parse_uuid(v_target.opportunity_id::text) is null
    ) or (
      private.try_parse_uuid(v_target.opportunity_id::text) is not null
      and private.try_parse_uuid(v_target.opportunity_id::text)
        is distinct from p_opportunity_id
    ) then
      raise exception 'linked project belongs to another opportunity'
        using errcode = '23505';
    end if;
    v_result := private.execute_opportunity_conversion_core(
      p_company_id,
      p_opportunity_id,
      p_actual_value,
      null,
      case when v_actor_user_id is null then null else v_actor_user_id end,
      p_notes,
      p_title_override,
      v_link_to_project_id,
      p_source_path,
      p_win_opportunity and v_opp.stage = 'won',
      p_project_status,
      coalesce(p_evidence, '{}'::jsonb),
      v_opp.assignment_version
    );

    select event.id,
           coalesce((event.payload ->> 'linked_existing')::boolean, false)
      into v_conversion_event_id, v_existing_linked_existing
      from public.opportunity_conversion_events event
     where event.company_id = p_company_id
       and event.opportunity_id = p_opportunity_id
       and event.project_id = v_link_to_project_id
       and event.event_type = 'converted_to_project'
     order by event.created_at desc, event.id desc
     limit 1;

    return v_result || jsonb_build_object(
      'converted', false,
      'already_converted', true,
      'guard_reason', 'already_converted',
      'project_id', v_link_to_project_id,
      'opportunity_id', p_opportunity_id,
      'assigned_to', v_opp.assigned_to,
      'assignment_version', v_opp.assignment_version,
      'conversion_event_id', coalesce(
        v_conversion_event_id,
        private.try_parse_uuid(v_result ->> 'conversion_event_id')
      ),
      'linked_existing', v_existing_linked_existing,
      'won', v_opp.stage = 'won',
      'project_accessible', false
    );
  end if;

  if v_link_to_project_id is not null then
    if v_actor_user_id is not null then
      if v_initial_project_id is null
        and (
          nullif(v_initial_preflight_address, '') is null
          or v_target.status not in ('rfq', 'estimated', 'accepted', 'in_progress')
          or private.normalize_address(v_target.address)
            is distinct from v_initial_preflight_address
          or not private.user_can_view_project(
            v_actor_user_id,
            v_link_to_project_id
          )
          or not private.user_can_link_opportunity_to_project(
            v_actor_user_id,
            v_link_to_project_id
          )
          or (
            v_target.opportunity_ref is not null
            and v_target.opportunity_ref is distinct from p_opportunity_id
          )
          or (
            nullif(btrim(v_target.opportunity_id::text), '') is not null
            and private.try_parse_uuid(v_target.opportunity_id::text) is null
          )
          or (
            private.try_parse_uuid(v_target.opportunity_id::text) is not null
            and private.try_parse_uuid(v_target.opportunity_id::text)
              is distinct from p_opportunity_id
          )
        )
      then
        raise exception 'project_link_unavailable'
          using errcode = 'P0002';
      end if;
    else
      if v_initial_client_id is null
        or v_target.client_id is distinct from v_initial_client_id
        or (
          v_target.opportunity_ref is not null
          and v_target.opportunity_ref is distinct from p_opportunity_id
        )
        or (
          nullif(btrim(v_target.opportunity_id::text), '') is not null
          and private.try_parse_uuid(v_target.opportunity_id::text) is null
        )
        or (
          private.try_parse_uuid(v_target.opportunity_id::text) is not null
          and private.try_parse_uuid(v_target.opportunity_id::text)
            is distinct from p_opportunity_id
        )
        or v_target.status not in ('rfq', 'estimated', 'accepted', 'in_progress')
        or (
          v_initial_project_id is null
          and (
            private.normalize_email_project_dedupe_address(v_target.address) = ''
            or private.normalize_email_project_dedupe_address(v_target.address)
              is distinct from v_initial_normalized_address
          )
        )
      then
        raise exception 'project_link_unavailable'
          using errcode = 'P0002';
      end if;
    end if;
  end if;

  v_result := private.execute_opportunity_conversion_core(
    p_company_id,
    p_opportunity_id,
    p_actual_value,
    p_expected_stage,
    case when v_actor_user_id is null then null else v_actor_user_id end,
    p_notes,
    p_title_override,
    v_link_to_project_id,
    p_source_path,
    p_win_opportunity,
    p_project_status,
    coalesce(p_evidence, '{}'::jsonb),
    p_expected_assignment_version
  );

  -- Reactivating an engine-owned budget deferral into Won must not leave stale
  -- loss/follow-up state or the deferral date behind on the converted lead.
  if v_opp.stage = 'lost'
    and p_win_opportunity
    and coalesce((v_result ->> 'won')::boolean, false)
  then
    update public.opportunities
       set lost_reason = null,
           lost_notes = null,
           next_follow_up_at = null,
           actual_close_date = now()::date,
           updated_at = now()
     where id = p_opportunity_id
       and company_id = p_company_id;
  end if;

  -- The canonical core historically used the presence of an opportunity-side
  -- project pointer as its `already_converted` signal. Correct the public result
  -- when this call completed a previously unrecorded one-way link and Won it.
  if v_actor_user_id is null
    and v_initial_project_id is not null
    and not v_existing_conversion_complete
  then
    v_result := v_result || jsonb_build_object(
      'converted', true,
      'already_converted', false,
      'guard_reason', null,
      'linked_existing', true
    );
  end if;

  v_project_id := private.try_parse_uuid(v_result ->> 'project_id');
  if v_actor_user_id is not null and v_project_id is not null then
    v_project_accessible := private.user_can_view_project(
      v_actor_user_id,
      v_project_id
    );
  end if;

  return v_result || jsonb_build_object(
    'assigned_to', v_opp.assigned_to,
    'assignment_version', v_opp.assignment_version,
    'project_accessible', coalesce(v_project_accessible, false)
  );
end;
$function$;

