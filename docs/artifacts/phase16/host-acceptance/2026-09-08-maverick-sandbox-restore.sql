-- Executed cleanup of the explicitly approved temporary sandbox pause.
-- Exact connection only; never disconnect or alter credentials.
begin;
set local lock_timeout='3s';
set local statement_timeout='15s';
do $restore$
declare
 prior public.accounting_connections%rowtype;
 after_row public.accounting_connections%rowtype;
 fixture_ids uuid[]:=array[
  'db03d9e2-5753-46db-8a61-7a2d72164da8','0adfdd7c-7f7f-4851-8f53-6cbed9549131',
  '775d8bc4-edd6-4e45-854f-c7e1cf12e3e7','ebb45d42-dd6a-4282-ac73-6a2e1af74278',
  '323f486f-1a05-496b-9e4f-d725384d007d','eb654ed0-28fd-4428-b9f4-42ee173b6811']::uuid[];
begin
 select * into prior from public.accounting_connections where id='956dfa13-821f-45c4-ba30-7286d3178896' for update;
 if prior.id is null or prior.company_id is distinct from 'ddee107c-33cd-483e-8278-0f8d8a180181'
 or prior.provider is distinct from 'quickbooks' or prior.provider_environment is distinct from 'sandbox'
 or prior.is_connected is distinct from true or prior.sync_enabled is distinct from false
 or prior.sync_direction is distinct from 'bidirectional'
 then raise exception 'SANDBOX_RESTORE_TARGET_CHANGED'; end if;
 if exists(select 1 from public.accounting_sync_queue where company_id=prior.company_id::uuid and entity_id=any(fixture_ids))
 then raise exception 'SANDBOX_RESTORE_FIXTURE_QUEUE_NOT_EMPTY'; end if;
 update public.accounting_connections set sync_enabled=true where id=prior.id returning * into after_row;
 if (to_jsonb(prior)-array['sync_enabled','updated_at']) is distinct from (to_jsonb(after_row)-array['sync_enabled','updated_at'])
 then raise exception 'SANDBOX_RESTORE_UNRELATED_FIELD_CHANGED'; end if;
 if exists(select 1 from public.accounting_sync_queue where company_id=prior.company_id::uuid and entity_id=any(fixture_ids))
 then raise exception 'SANDBOX_RESTORE_CREATED_FIXTURE_QUEUE'; end if;
 perform set_config('ops.p16_sandbox_restore',jsonb_build_object(
  'connection_id',prior.id,'company_id',prior.company_id,'provider','quickbooks','environment','sandbox',
  'before_sync_enabled',prior.sync_enabled,'after_sync_enabled',after_row.sync_enabled,
  'is_connected',after_row.is_connected,'direction',after_row.sync_direction,
  'unrelated_fields_unchanged',true,'fixture_queue_rows',0,'restored_at',after_row.updated_at,
  'authority','Jackson explicitly approved temporary sandbox sync pause and restoration',
  'reason','Fixture setup complete; stop at exact owner enrollment gate without leaving accounting paused'
 )::text,true);
end $restore$;
select current_setting('ops.p16_sandbox_restore')::jsonb as restore_receipt;
commit;

