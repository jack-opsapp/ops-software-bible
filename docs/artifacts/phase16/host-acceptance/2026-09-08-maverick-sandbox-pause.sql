begin;
set local lock_timeout='3s';
set local statement_timeout='15s';
do $pause$
declare prior public.accounting_connections%rowtype; after_row public.accounting_connections%rowtype;
begin
 select * into prior from public.accounting_connections where id='956dfa13-821f-45c4-ba30-7286d3178896' for update;
 if prior.id is null or prior.company_id<>'ddee107c-33cd-483e-8278-0f8d8a180181'
 or prior.provider<>'quickbooks' or prior.provider_environment<>'sandbox'
 or prior.is_connected is distinct from true or prior.sync_enabled is distinct from true
 or prior.sync_direction<>'bidirectional'
 then raise exception 'SANDBOX_PAUSE_TARGET_CHANGED'; end if;
 update public.accounting_connections set sync_enabled=false where id=prior.id returning * into after_row;
 if (to_jsonb(prior)-array['sync_enabled','updated_at']) is distinct from (to_jsonb(after_row)-array['sync_enabled','updated_at'])
 then raise exception 'SANDBOX_PAUSE_UNRELATED_FIELD_CHANGED'; end if;
 perform set_config('ops.p16_sandbox_pause',jsonb_build_object(
 'connection_id',prior.id,'company_id',prior.company_id,'provider','quickbooks','environment','sandbox',
 'before_sync_enabled',prior.sync_enabled,'after_sync_enabled',after_row.sync_enabled,'is_connected',after_row.is_connected,
 'direction',after_row.sync_direction,'unrelated_fields_unchanged',true,
 'restore_sync_enabled_to',true,'paused_at',after_row.updated_at,'authority','Jackson explicitly approved temporary sandbox sync pause and restoration'
 )::text,true);
end $pause$;
select current_setting('ops.p16_sandbox_pause')::jsonb as pause_receipt;
commit;
