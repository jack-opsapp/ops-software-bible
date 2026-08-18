-- Agent-wave reshape: return prod to pre-wave state so the gated (44f6401c)
-- migration set applies onto the base it was written for. Jackson's Option B
-- ruling, 2026-08-17. All ten release-applied migrations touched only
-- zero-row tables and replaceable functions; this transaction drops the
-- release layer and restores every replaced pre-existing object BYTE-EXACT by
-- slicing the original definitions out of supabase_migrations.schema_migrations
-- (statements[1] is the authoritative byte-exact applied SQL).

create function pg_temp._reshape_row_sql(p_version text) returns text
language plpgsql as $helper$
declare v_sql text;
begin
  select statements[1] into v_sql
    from supabase_migrations.schema_migrations where version = p_version;
  if v_sql is null then
    raise exception 'reshape: ledger row % missing', p_version;
  end if;
  return v_sql;
end $helper$;

create function pg_temp._reshape_slice_dollar(p_version text, p_header text)
returns text language plpgsql as $helper$
declare
  v_sql text := pg_temp._reshape_row_sql(p_version);
  v_start int := strpos(lower(v_sql), lower(p_header));
  v_rest text;
  v_tag text;
  v_open int;
  v_close_rel int;
  v_end int;
begin
  if v_start = 0 then
    raise exception 'reshape: header % not found in %', p_header, p_version;
  end if;
  v_rest := substr(v_sql, v_start);
  v_tag := (regexp_match(v_rest, '(\$[a-zA-Z0-9_]*\$)'))[1];
  if v_tag is null then
    raise exception 'reshape: no dollar tag after % in %', p_header, p_version;
  end if;
  v_open := position(v_tag in v_rest);
  v_close_rel := position(v_tag in substr(v_rest, v_open + length(v_tag)));
  if v_close_rel = 0 then
    raise exception 'reshape: unterminated % in %', v_tag, p_version;
  end if;
  v_end := v_open + length(v_tag) + v_close_rel - 1 + length(v_tag) - 1;
  if v_end < 200 then
    raise exception 'reshape: suspiciously short slice for %', p_header;
  end if;
  return substr(v_rest, 1, v_end);
end $helper$;

create function pg_temp._reshape_slice_semicolon(p_version text, p_header text)
returns text language plpgsql as $helper$
declare
  v_sql text := pg_temp._reshape_row_sql(p_version);
  v_start int := strpos(lower(v_sql), lower(p_header));
  v_end_rel int;
begin
  if v_start = 0 then
    raise exception 'reshape: header % not found in %', p_header, p_version;
  end if;
  v_end_rel := position(';' in substr(v_sql, v_start));
  if v_end_rel = 0 then
    raise exception 'reshape: no terminator for % in %', p_header, p_version;
  end if;
  return substr(v_sql, v_start, v_end_rel - 1);
end $helper$;

do $reshape$
declare
  v_n bigint;
  v_names text[];
  v_rec record;
begin
  select
    (select count(*) from public.email_send_intents)
    + (select count(*) from public.approved_action_email_intents)
    + (select count(*) from public.pending_auto_sends)
    + (select count(*) from public.job_conversations)
    + (select count(*) from public.job_conversation_anchors)
    + (select count(*) from public.job_conversation_turns)
    + (select count(*) from public.job_conversation_redaction_events)
    + (select count(*) from public.job_memory_versions)
    + (select count(*) from public.job_memory_version_evidence)
    + (select count(*) from private.phase_c_auto_send_source_fences)
    + (select count(*) from private.phase_c_auto_send_generation_reservations)
    + (select count(*) from private.agent_provider_delivery_sources)
    + (select count(*) from private.agent_provider_delivery_turn_sources)
    into v_n;
  if v_n <> 0 then
    raise exception 'reshape: wave tables no longer empty (% rows) — pure-DDL window closed, ABORT', v_n;
  end if;

  drop trigger if exists email_send_intent_enforce_provider_delivery_source on public.email_send_intents;
  drop trigger if exists approved_email_intent_enforce_provider_delivery_source on public.approved_action_email_intents;
  drop trigger if exists email_send_intents_phase_c_source_delivery_fence on public.email_send_intents;
  drop trigger if exists email_send_intents_system_handoff_delivery_guard on public.email_send_intents;
  drop trigger if exists seal_provider_turn_source_after_event on public.opportunity_correspondence_events;

  drop table if exists public.job_memory_version_evidence cascade;
  drop table if exists public.job_memory_versions cascade;
  drop table if exists public.job_conversation_redaction_events cascade;
  drop table if exists public.job_conversation_turns cascade;
  drop table if exists public.job_conversation_anchors cascade;
  drop table if exists public.job_conversations cascade;
  drop table if exists private.phase_c_auto_send_source_fences cascade;
  drop table if exists private.phase_c_auto_send_generation_reservations cascade;
  drop table if exists private.agent_provider_delivery_turn_sources cascade;
  drop table if exists private.agent_provider_delivery_sources cascade;

  v_names := array[
    'actorless_postal_region_is_consistent','agent_email_send_intent_is_authorized',
    'agent_job_memory_document_is_valid','agent_job_memory_evidence_ids_are_valid',
    'agent_job_memory_redaction_revision','agent_job_memory_turn_source_revision',
    'agent_job_memory_utc_timestamp_is_valid','agent_prompt_identity_array_is_canonical',
    'agent_prompt_text_is_safe','agent_provider_delivery_source_matches_plan',
    'agent_provider_delivery_text_array_is_canonical','append_job_memory_version_as_system',
    'assert_approved_email_delivery_authorized','capture_agent_provider_delivery_source_as_system',
    'claim_approved_email_provider_send_request','claim_email_send_provider_send_request',
    'convert_opportunity_to_project','current_user_can_view_job_conversation',
    'enforce_agent_provider_delivery_source_binding','enforce_job_conversation_anchor_company',
    'enforce_job_conversation_turn_source','enforce_phase_c_auto_send_source_delivery_fence',
    'find_phase_c_auto_send_by_identity_as_system','guard_system_handoff_email_send_delivery',
    'ingest_job_conversation_turn_as_system','invalidate_job_memory_before_redaction',
    'lock_job_memory_before_turn_insert','mark_approved_action_email_delivery_unknown',
    'mark_approved_action_email_provider_accepted','mark_approved_action_email_provider_rejected',
    'mark_email_send_provider_accepted','mark_email_send_provider_rejected',
    'normalize_actorless_project_address_identity','normalize_phase_c_email_header_address',
    'prepare_approved_action_email_intent','purge_company_rows',
    'read_actor_scoped_job_memory_generation_snapshot_as_system',
    'read_agent_correspondence_evidence_as_system','read_agent_provider_delivery_source_as_system',
    'read_agent_provider_delivery_source_receipt_as_system','read_job_conversation_context_as_system',
    'read_job_memory_generation_snapshot_as_system','read_phase_c_actor_scoped_job_memory_generation_snapshot_as_sys',
    'read_phase_c_job_conversation_context_as_system','read_phase_c_routed_actor_fence_as_system',
    'read_phase_c_source_turn_as_system','recover_prepared_provider_delivery_as_system',
    'reject_agent_job_memory_mutation','reserve_approved_email_prepared_provider_recovery',
    'reserve_email_send_prepared_provider_recovery','reserve_phase_c_auto_send_generation_as_system',
    'resolve_manual_email_contact_form_draft_recipient_as_system',
    'resolve_phase_c_auto_send_generation_as_system','schedule_phase_c_auto_send_fenced',
    'seal_agent_provider_delivery_turn_source','seal_provider_turn_source_after_event',
    'validate_phase_c_auto_send_source_for_delivery','claim_approved_action_email_delivery'
  ];
  for v_rec in
    select format('drop function %I.%I(%s);', n.nspname, p.proname,
                  pg_get_function_identity_arguments(p.oid)) as ddl
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname in ('public','private') and p.proname = any (v_names)
  loop
    execute v_rec.ddl;
  end loop;

  alter table public.email_send_intents
    drop column if exists prepared_provider_recovery_id,
    drop column if exists provider_recovery_reserved_at,
    drop column if exists provider_send_requested_at,
    drop column if exists provider_send_request_provider,
    drop column if exists provider_send_request_connection_id,
    drop column if exists provider_send_request_revision,
    drop column if exists provider_send_request_sha256,
    drop column if exists provider_delivery_source_id,
    drop column if exists provider_delivery_source_sha256,
    drop column if exists provider_delivery_origin,
    drop column if exists provider_delivery_protocol;
  alter table public.approved_action_email_intents
    drop column if exists prepared_provider_recovery_id,
    drop column if exists provider_recovery_reserved_at,
    drop column if exists provider_send_requested_at,
    drop column if exists provider_send_request_provider,
    drop column if exists provider_send_request_connection_id,
    drop column if exists provider_send_request_revision,
    drop column if exists provider_send_request_sha256,
    drop column if exists provider_delivery_source_id,
    drop column if exists provider_delivery_source_sha256,
    drop column if exists provider_delivery_origin,
    drop column if exists provider_delivery_protocol;

  execute pg_temp._reshape_slice_dollar('20260715162000', 'create or replace function public.mark_email_send_provider_accepted(');
  execute pg_temp._reshape_slice_dollar('20260715162000', 'create or replace function public.mark_email_send_provider_rejected(');
  execute 'revoke all on function public.mark_email_send_provider_accepted(uuid, text, text, timestamptz) from public, anon, authenticated, service_role';
  execute 'grant execute on function public.mark_email_send_provider_accepted(uuid, text, text, timestamptz) to service_role';
  execute 'revoke all on function public.mark_email_send_provider_rejected(uuid, text) from public, anon, authenticated, service_role';
  execute 'grant execute on function public.mark_email_send_provider_rejected(uuid, text) to service_role';

  execute pg_temp._reshape_slice_dollar('20260715171000', 'create or replace function public.prepare_approved_action_email_intent(');
  execute pg_temp._reshape_slice_dollar('20260715171000', 'create or replace function public.mark_approved_action_email_delivery_unknown(');
  execute pg_temp._reshape_slice_dollar('20260715171000', 'create or replace function public.mark_approved_action_email_provider_accepted(');
  execute pg_temp._reshape_slice_dollar('20260715171000', 'create or replace function public.mark_approved_action_email_provider_rejected(');
  for v_rec in
    select format(
      'revoke all on function public.%I(%s) from public, anon, authenticated, service_role',
      p.proname, pg_get_function_identity_arguments(p.oid)) as rv,
      format('grant execute on function public.%I(%s) to service_role',
      p.proname, pg_get_function_identity_arguments(p.oid)) as gr
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and p.proname in (
       'prepare_approved_action_email_intent','mark_approved_action_email_delivery_unknown',
       'mark_approved_action_email_provider_accepted','mark_approved_action_email_provider_rejected')
  loop
    execute v_rec.rv; execute v_rec.gr;
  end loop;

  execute pg_temp._reshape_slice_dollar('20260721102146', 'create or replace function public.claim_approved_action_email_delivery(');
  execute 'revoke all on function public.claim_approved_action_email_delivery(uuid) from public, anon, authenticated, service_role';
  execute 'grant execute on function public.claim_approved_action_email_delivery(uuid) to service_role';

  execute pg_temp._reshape_slice_dollar('20260723233348', 'create or replace function private.guard_system_handoff_email_send_delivery(');
  execute 'revoke all on function private.guard_system_handoff_email_send_delivery() from public, anon, authenticated, service_role';
  execute pg_temp._reshape_slice_semicolon('20260723233348', 'create trigger email_send_intents_system_handoff_delivery_guard');

  execute pg_temp._reshape_slice_dollar('20260731170226', 'create or replace function public.purge_company_rows(');
  execute 'revoke all on function public.purge_company_rows(text, uuid) from public';
  execute 'revoke all on function public.purge_company_rows(text, uuid) from anon';
  execute 'revoke all on function public.purge_company_rows(text, uuid) from authenticated';
  execute 'grant execute on function public.purge_company_rows(text, uuid) to service_role';

  execute pg_temp._reshape_slice_dollar('20260722155351', 'create or replace function public.convert_opportunity_to_project(');
  execute pg_temp._reshape_slice_dollar('20260729155043', 'do $migration$');
  execute pg_temp._reshape_slice_dollar('20260817193707', 'do $migration$');
  execute 'revoke all on function public.convert_opportunity_to_project(uuid,uuid,numeric,text,uuid,text,text,uuid,text,boolean,text,jsonb,bigint) from public, anon';
  execute 'grant execute on function public.convert_opportunity_to_project(uuid,uuid,numeric,text,uuid,text,text,uuid,text,boolean,text,jsonb,bigint) to authenticated, service_role';

  if to_regprocedure('public.mark_email_send_provider_accepted(uuid,text,text,timestamptz)') is null
     or to_regprocedure('public.mark_email_send_provider_rejected(uuid,text)') is null
     or to_regprocedure('public.mark_approved_action_email_provider_accepted(uuid,text,text,timestamptz)') is null
     or to_regprocedure('public.claim_approved_action_email_delivery(uuid)') is null
     or to_regprocedure('private.guard_system_handoff_email_send_delivery()') is null
     or to_regprocedure('public.purge_company_rows(text,uuid)') is null
     or to_regprocedure('public.convert_opportunity_to_project(uuid,uuid,numeric,text,uuid,text,text,uuid,text,boolean,text,jsonb,bigint)') is null then
    raise exception 'reshape: a restored function is missing — ABORT';
  end if;
  select count(*) into v_n
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('public','private')
     and p.proname in ('reserve_phase_c_auto_send_generation_as_system',
       'schedule_phase_c_auto_send_fenced','enforce_agent_provider_delivery_source_binding',
       'seal_agent_provider_delivery_turn_source','append_job_memory_version_as_system');
  if v_n <> 0 then
    raise exception 'reshape: % release functions survived the drop — ABORT', v_n;
  end if;
  if to_regclass('public.job_conversations') is not null
     or to_regclass('private.agent_provider_delivery_sources') is not null then
    raise exception 'reshape: release tables survived the drop — ABORT';
  end if;
  select count(*) into v_n from information_schema.columns
   where table_schema = 'public' and table_name in ('email_send_intents','approved_action_email_intents')
     and column_name like 'provider_send_request%';
  if v_n <> 0 then
    raise exception 'reshape: orphan columns survived — ABORT';
  end if;
  select count(*) into v_n from pg_trigger t join pg_class c on c.oid = t.tgrelid
   where not t.tgisinternal and c.relname = 'email_send_intents'
     and t.tgname = 'email_send_intents_system_handoff_delivery_guard';
  if v_n <> 1 then
    raise exception 'reshape: handoff guard trigger not restored — ABORT';
  end if;
  select count(*) into v_n from pg_trigger t join pg_class c on c.oid = t.tgrelid
   where not t.tgisinternal and c.relname = 'email_send_intents'
     and t.tgname = 'email_send_intents_phase_c_queue_fence';
  if v_n <> 1 then
    raise exception 'reshape: July queue fence missing — ABORT';
  end if;

  raise notice 'reshape complete: pre-wave state restored';
end $reshape$;
