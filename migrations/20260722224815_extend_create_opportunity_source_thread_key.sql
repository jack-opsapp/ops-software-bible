-- SYNC RECOVERY T1 · M1
-- Extend private.create_opportunity_company_serialized_internal to accept and
-- honor `source_thread_key` for idempotent lead auto-creation from iOS.
--
-- RC1 (2026-07-22 outage): iOS `ClientLeadAutocreate` sends a deterministic
-- `source_thread_key` = `client-autocreate:<client uuid>`; the internal function
-- rejected any key outside `v_allowed_keys` (errcode 22023 -> HTTP 400
-- `unsupported_opportunity_field: source_thread_key`), so three clients' auto-leads
-- 400'd forever. This migration:
--   (a) allows the key,
--   (b) parses it (nullif(btrim(...),'')),
--   (c) reads back an existing (company_id, source_thread_key) row BEFORE any
--       write and returns it as ok:true/conflict:true (idempotent retry),
--   (d) writes the key on INSERT, and
--   (e) catches unique_violation (the concurrent-insert race) and returns the
--       same conflict shape.
-- Additive-only: callers that never send the key see byte-identical behavior.
--
-- Precondition (verified in prod 2026-07-22): public.opportunities.source_thread_key
-- exists (text, nullable) and a UNIQUE index opportunities_company_source_thread_key_key
-- exists on (company_id, source_thread_key).

create or replace function private.create_opportunity_company_serialized_internal(
  p_opportunity jsonb,
  p_assignment_mode text default 'self'::text,
  p_initial_assigned_to uuid default null::uuid,
  p_metadata jsonb default '{}'::jsonb
)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'pg_catalog', 'public', 'private', 'pg_temp'
as $function$
declare
  v_allowed_keys text[] := array[
    'client_id',
    'client_ref',
    'title',
    'description',
    'contact_name',
    'contact_email',
    'contact_phone',
    'stage',
    'source',
    'priority',
    'estimated_value',
    'win_probability',
    'expected_close_date',
    'quote_delivery_method',
    'address',
    'latitude',
    'longitude',
    'tags',
    'source_thread_key'
  ];
  v_invalid_key text;
  v_actor_user_id uuid := private.get_current_user_id();
  v_company_id uuid := private.get_user_company_id();
  v_create_scope text;
  v_assign_scope text;
  v_client_id uuid;
  v_client_id_legacy uuid;
  v_client_ref uuid;
  v_assigned_to uuid;
  v_assignment_version bigint := 0;
  v_opportunity_id uuid := gen_random_uuid();
  v_stage text;
  v_tags text[];
  v_source_thread_key text := nullif(btrim(p_opportunity ->> 'source_thread_key'), '');
  v_existing public.opportunities%rowtype;
  v_created public.opportunities%rowtype;
  v_event_id uuid;
begin
  if p_opportunity is null or jsonb_typeof(p_opportunity) <> 'object' then
    raise exception 'opportunity_payload_must_be_object'
      using errcode = '22023';
  end if;

  if p_metadata is null or jsonb_typeof(p_metadata) <> 'object' then
    raise exception 'assignment_metadata_must_be_object'
      using errcode = '22023';
  end if;

  select key
    into v_invalid_key
    from jsonb_object_keys(p_opportunity) as supplied(key)
   where not (key = any (v_allowed_keys))
   order by key
   limit 1;

  if v_invalid_key is not null then
    raise exception 'unsupported_opportunity_field: %', v_invalid_key
      using errcode = '22023';
  end if;

  if p_assignment_mode is null
    or p_assignment_mode not in ('self', 'unassigned', 'explicit')
  then
    raise exception 'invalid_assignment_mode'
      using errcode = '22023';
  end if;

  if v_actor_user_id is null or v_company_id is null then
    raise exception 'access_denied'
      using errcode = '42501';
  end if;

  perform 1
    from public.users u
   where u.id = v_actor_user_id
     and u.company_id = v_company_id
     and u.deleted_at is null
     and coalesce(u.is_active, false)
   for share;
  if not found then
    raise exception 'access_denied'
      using errcode = '42501';
  end if;

  v_create_scope := private.current_user_scope_for('pipeline.create');
  if v_create_scope is null
    and private.should_use_pipeline_manage_compat(
      v_actor_user_id,
      v_company_id,
      'pipeline.create'
    )
  then
    v_create_scope := 'all';
  end if;
  if v_create_scope is distinct from 'all' then
    raise exception 'access_denied'
      using errcode = '42501';
  end if;

  v_assign_scope := private.current_user_scope_for('pipeline.assign');
  if v_assign_scope is null
    and private.should_use_pipeline_manage_compat(
      v_actor_user_id,
      v_company_id,
      'pipeline.assign'
    )
  then
    v_assign_scope := 'all';
  end if;

  if p_assignment_mode in ('unassigned', 'explicit')
    and v_assign_scope is distinct from 'all'
  then
    raise exception 'pipeline.assign:all required for assignment mode'
      using errcode = '42501';
  end if;

  if nullif(btrim(p_opportunity ->> 'title'), '') is null then
    raise exception 'opportunity_title_required'
      using errcode = '22023';
  end if;

  v_stage := coalesce(nullif(p_opportunity ->> 'stage', ''), 'new_lead');
  if v_stage not in (
    'new_lead',
    'qualifying',
    'quoting',
    'quoted',
    'follow_up',
    'negotiation'
  ) then
    raise exception 'manual_create_stage_invalid'
      using errcode = '22023';
  end if;

  if p_opportunity ? 'tags'
    and p_opportunity -> 'tags' is not null
    and jsonb_typeof(p_opportunity -> 'tags') <> 'array'
  then
    raise exception 'opportunity_tags_must_be_array'
      using errcode = '22023';
  end if;
  select coalesce(array_agg(value), '{}'::text[])
    into v_tags
    from jsonb_array_elements_text(
      case
        when p_opportunity ? 'tags'
          and jsonb_typeof(p_opportunity -> 'tags') = 'array'
          then p_opportunity -> 'tags'
        else '[]'::jsonb
      end
    ) as tag(value);

  v_client_id_legacy := nullif(p_opportunity ->> 'client_id', '')::uuid;
  v_client_ref := nullif(p_opportunity ->> 'client_ref', '')::uuid;
  if v_client_id_legacy is not null
    and v_client_ref is not null
    and v_client_id_legacy is distinct from v_client_ref
  then
    raise exception 'client_mirrors_disagree'
      using errcode = '22023';
  end if;
  v_client_id := coalesce(v_client_ref, v_client_id_legacy);

  if v_client_id is not null
    and not exists (
      select 1
        from public.clients c
       where c.id = v_client_id
         and c.company_id = v_company_id
         and c.deleted_at is null
    )
  then
    raise exception 'client_not_found_in_company'
      using errcode = '22023';
  end if;

  -- Idempotent lead auto-creation (RC1): if a row already exists for this
  -- (company_id, source_thread_key), return it as a success instead of raising.
  -- Placed BEFORE assignment resolution and the assignment-write-token mint so
  -- the readback path never leaves an orphan token. create_opportunity_guarded
  -- holds lock_lead_assignment_company before we run, so same-company creates
  -- are serialized and this readback is authoritative on the wrapper path.
  if v_source_thread_key is not null then
    select *
      into v_existing
      from public.opportunities o
     where o.company_id = v_company_id
       and o.source_thread_key = v_source_thread_key
     limit 1;
    if found then
      return jsonb_build_object(
        'ok', true,
        'conflict', true,
        'opportunity', to_jsonb(v_existing),
        'assigned_to', v_existing.assigned_to,
        'assignment_version', v_existing.assignment_version,
        'event_id', null
      );
    end if;
  end if;

  if p_assignment_mode = 'self' then
    if p_initial_assigned_to is not null
      and p_initial_assigned_to is distinct from v_actor_user_id
    then
      raise exception 'self_assignment_target_must_be_actor'
        using errcode = '22023';
    end if;

    if exists (
      select 1
        from public.users u
       where u.id = v_actor_user_id
         and u.company_id = v_company_id
         and u.deleted_at is null
         and coalesce(u.is_active, false)
         and public.has_permission(
           v_actor_user_id,
           'pipeline.view',
           'assigned'
         )
    ) then
      v_assigned_to := v_actor_user_id;
    end if;
  elsif p_assignment_mode = 'unassigned' then
    if p_initial_assigned_to is not null then
      raise exception 'unassigned_mode_requires_null_target'
        using errcode = '22023';
    end if;
    v_assigned_to := null;
  else
    if p_initial_assigned_to is null then
      raise exception 'explicit_mode_requires_target'
        using errcode = '22023';
    end if;
    perform 1
      from public.users u
     where u.id = p_initial_assigned_to
       and u.company_id = v_company_id
       and u.deleted_at is null
       and coalesce(u.is_active, false)
       and public.has_permission(
         p_initial_assigned_to,
         'pipeline.view',
         'assigned'
       )
     for share;
    if not found then
      raise exception 'assignment_target_ineligible'
        using errcode = '22023';
    end if;
    v_assigned_to := p_initial_assigned_to;
  end if;

  if v_assigned_to is not null then
    v_assignment_version := 1;
    insert into private.opportunity_assignment_write_tokens (
      transaction_id,
      backend_pid,
      opportunity_id,
      operation,
      assigned_to,
      assignment_version
    ) values (
      txid_current(),
      pg_backend_pid(),
      v_opportunity_id,
      'insert',
      v_assigned_to,
      v_assignment_version
    );
  end if;

  begin
    insert into public.opportunities (
      id,
      company_id,
      client_id,
      client_ref,
      title,
      description,
      contact_name,
      contact_email,
      contact_phone,
      stage,
      source,
      assigned_to,
      assignment_version,
      priority,
      estimated_value,
      win_probability,
      expected_close_date,
      quote_delivery_method,
      address,
      latitude,
      longitude,
      tags,
      source_thread_key
    ) values (
      v_opportunity_id,
      v_company_id,
      v_client_id,
      v_client_id,
      btrim(p_opportunity ->> 'title'),
      nullif(p_opportunity ->> 'description', ''),
      nullif(p_opportunity ->> 'contact_name', ''),
      nullif(p_opportunity ->> 'contact_email', ''),
      nullif(p_opportunity ->> 'contact_phone', ''),
      v_stage,
      nullif(p_opportunity ->> 'source', ''),
      v_assigned_to,
      v_assignment_version,
      nullif(p_opportunity ->> 'priority', ''),
      nullif(p_opportunity ->> 'estimated_value', '')::numeric,
      coalesce(nullif(p_opportunity ->> 'win_probability', '')::integer, 10),
      nullif(p_opportunity ->> 'expected_close_date', '')::date,
      nullif(p_opportunity ->> 'quote_delivery_method', ''),
      nullif(p_opportunity ->> 'address', ''),
      nullif(p_opportunity ->> 'latitude', '')::double precision,
      nullif(p_opportunity ->> 'longitude', '')::double precision,
      v_tags,
      v_source_thread_key
    )
    returning * into v_created;
  exception
    when unique_violation then
      -- Concurrent-insert race on (company_id, source_thread_key): another
      -- transaction committed the same key between our readback and INSERT.
      -- The assignment-write token minted above had its guard-trigger consume
      -- rolled back by this sub-block's savepoint, so remove the resulting
      -- orphan (keyed by the phantom v_opportunity_id, unique to this call)
      -- before returning the idempotent conflict.
      delete from private.opportunity_assignment_write_tokens t
       where t.transaction_id = txid_current()
         and t.backend_pid = pg_backend_pid()
         and t.opportunity_id = v_opportunity_id;
      if v_source_thread_key is not null then
        select *
          into v_existing
          from public.opportunities o
         where o.company_id = v_company_id
           and o.source_thread_key = v_source_thread_key
         limit 1;
        if found then
          return jsonb_build_object(
            'ok', true,
            'conflict', true,
            'opportunity', to_jsonb(v_existing),
            'assigned_to', v_existing.assigned_to,
            'assignment_version', v_existing.assignment_version,
            'event_id', null
          );
        end if;
      end if;
      raise;
  end;

  if v_assigned_to is not null then
    insert into public.opportunity_assignment_events (
      company_id,
      opportunity_id,
      previous_assignee_id,
      new_assignee_id,
      actor_user_id,
      source,
      assignment_version,
      previous_assignee_snapshot,
      new_assignee_snapshot,
      actor_snapshot,
      metadata
    ) values (
      v_company_id,
      v_opportunity_id,
      null,
      v_assigned_to,
      v_actor_user_id,
      'manual_create',
      v_assignment_version,
      null,
      private.user_assignment_snapshot(v_assigned_to),
      private.user_assignment_snapshot(v_actor_user_id),
      p_metadata
    )
    returning id into v_event_id;

    insert into public.opportunity_assignment_deliveries (
      assignment_event_id,
      company_id,
      opportunity_id,
      assignment_version,
      recipient_user_id,
      access_after,
      notify
    ) values (
      v_event_id,
      v_company_id,
      v_opportunity_id,
      v_assignment_version,
      v_assigned_to,
      true,
      v_assigned_to is distinct from v_actor_user_id
    )
    on conflict (assignment_event_id, recipient_user_id) do nothing;
  end if;

  return jsonb_build_object(
    'ok', true,
    'conflict', false,
    'opportunity', to_jsonb(v_created),
    'assigned_to', v_assigned_to,
    'assignment_version', v_assignment_version,
    'event_id', v_event_id
  );
end;
$function$;
