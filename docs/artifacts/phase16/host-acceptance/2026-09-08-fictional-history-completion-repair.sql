-- Correct only the coordinator-created fictional historical project's missing completion timestamp.
-- This is test-source repair, not a real completion event, customer approval, quote save, or weakened eligibility rule.
begin;
set local lock_timeout='3s';
set local statement_timeout='25s';
set local timezone='UTC';
do $repair$
declare before_project public.projects%rowtype; after_project public.projects%rowtype;
 before_connection public.accounting_connections%rowtype; after_connection public.accounting_connections%rowtype;
begin
 select * into before_project from public.projects where id='0adfdd7c-7f7f-4851-8f53-6cbed9549131' for update;
 if before_project.company_id is distinct from 'ddee107c-33cd-483e-8278-0f8d8a180181'::uuid
 or before_project.client_id is distinct from 'db03d9e2-5753-46db-8a61-7a2d72164da8'::uuid
 or before_project.title is distinct from 'MCP P16 TEST ONLY — Deck history'
 or before_project.platform_metadata->>'fixture' is distinct from 'ops-mcp-p16-20260908'
 or before_project.status is distinct from 'completed' or before_project.completed_at is not null
 or before_project.created_at is null or before_project.deleted_at is not null
 or before_project.title_is_auto is distinct from false
 or before_project.opportunity_id is not null or before_project.opportunity_ref is not null
 or exists(select 1 from public.opportunities where project_ref=before_project.id or project_id=before_project.id)
 or exists(select 1 from private.financial_document_proposals where oauth_client_id='c15e9551-c7d3-4960-ac9a-e24439bc958f')
 then raise exception 'P16_EXACT_FICTIONAL_HISTORY_REPAIR_GATE';end if;
 select * into before_connection from public.accounting_connections where id='956dfa13-821f-45c4-ba30-7286d3178896' for update;
 if before_connection.company_id is distinct from 'ddee107c-33cd-483e-8278-0f8d8a180181'
 or before_connection.provider is distinct from 'quickbooks' or before_connection.provider_environment is distinct from 'sandbox'
 or before_connection.is_connected is distinct from true or before_connection.sync_enabled is distinct from true
 or before_connection.sync_direction is distinct from 'bidirectional'
 then raise exception 'P16_SANDBOX_STATE_CHANGED';end if;
 -- The reviewed project completion-date update has no accounting trigger or status transition.
 -- Keep the exact approved sandbox isolation guard within this transaction and restore before commit.
 update public.accounting_connections set sync_enabled=false where id=before_connection.id;
 update public.projects set completed_at=created_at where id=before_project.id returning * into after_project;
 if (to_jsonb(before_project)-array['completed_at','updated_at']) is distinct from (to_jsonb(after_project)-array['completed_at','updated_at'])
 or after_project.completed_at is distinct from before_project.created_at
 then raise exception 'P16_UNRELATED_PROJECT_CHANGE';end if;
 if exists(select 1 from public.accounting_sync_queue where entity_id in(before_project.id,'323f486f-1a05-496b-9e4f-d725384d007d'::uuid,'db03d9e2-5753-46db-8a61-7a2d72164da8'::uuid))
 or exists(select 1 from public.project_status_lifecycle_outbox where project_id=before_project.id)
 then raise exception 'P16_UNEXPECTED_OUTBOUND_EFFECT';end if;
 update public.accounting_connections set sync_enabled=true where id=before_connection.id returning * into after_connection;
 if (to_jsonb(before_connection)-'updated_at') is distinct from (to_jsonb(after_connection)-'updated_at')
 then raise exception 'P16_ACCOUNTING_RESTORE_MISMATCH';end if;
 perform set_config('ops.p16_repair_receipt',jsonb_build_object(
 'project_id',before_project.id,'company_id',before_project.company_id,
 'before_completed_at',before_project.completed_at,'after_completed_at',after_project.completed_at,
 'before_project_sha256',private.financial_document_hash(to_jsonb(before_project)),
 'after_project_sha256',private.financial_document_hash(to_jsonb(after_project)),
 'unrelated_project_fields_unchanged',true,'sandbox_sync_restored',true,'sandbox_pause_committed',false,
 'accounting_queue_rows',0,'status_lifecycle_events',0,'synthetic_fixture_only',true,'recorded_at',clock_timestamp())::text,true);
end $repair$;
select current_setting('ops.p16_repair_receipt')::jsonb as repair_receipt;
commit;
