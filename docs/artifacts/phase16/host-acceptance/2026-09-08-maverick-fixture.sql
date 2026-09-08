-- Approved test setup: Jackson explicitly selected MAVERICK on 2026-09-08.
-- NOT COMMITTED: rollback dry-run stopped before inserts on active sandbox sync.
-- Do not weaken the guard. Exact sandbox-pause approval and readback are required.
-- Synthetic historical source only; this is NOT a host draft-save acceptance.
-- No policy enrollment, effect seal, OAuth grant, send, sync, or output draft.
-- Re-execution fails closed before inserts if the fixture already exists.
begin isolation level serializable;
set local lock_timeout='3s';
set local statement_timeout='30s';
set local timezone='UTC';

do $fixture$
declare
 company constant uuid := 'ddee107c-33cd-483e-8278-0f8d8a180181';
 owner_id constant uuid := '8e811f98-9f2b-4f64-b409-ed56074b7dc8';
 tax_id constant uuid := 'd0000000-0000-4000-d000-000000000001';
 customer_id uuid; history_project_id uuid; quote_project_id uuid;
 note_id uuid; estimate_id uuid; line_id uuid; fixture_ids uuid[] := '{}';
 relation_name text; baseline jsonb := '{}'; prior_hash text; after_hash text;
 company_hash text; tax_hash text;
begin
 perform pg_advisory_xact_lock(hashtextextended('mcp-p16-fixture:'||company::text,0));
 perform 1 from public.companies where id=company for share;
 perform 1 from public.users where id=owner_id for share;
 perform 1 from public.tax_rates where company_id=company for share;
 perform 1 from public.accounting_connections where company_id=company::text for share;
 if not exists(select 1 from public.companies c join public.users u on u.id=owner_id and u.company_id=c.id
  where c.id=company and c.name='MAVERICK PROJECTS LTD' and lower(c.account_holder_id)=owner_id::text
  and c.currency_code='CAD' and c.deleted_at is null and u.deleted_at is null and u.is_active)
 then raise exception 'FIXTURE_IDENTITY_CHANGED'; end if;
 if (select count(*) from public.tax_rates where company_id=company and is_active and is_default)<>1
  or not exists(select 1 from public.tax_rates where id=tax_id and company_id=company
    and name='CA Sales Tax' and is_active and is_default and rate=0.0775)
 then raise exception 'FIXTURE_TAX_CHANGED'; end if;
 if exists(select 1 from public.accounting_connections where company_id=company::text
  and is_connected and sync_enabled and sync_direction in ('push_only','bidirectional'))
 then raise exception 'FIXTURE_ACCOUNTING_PUSH_ENABLED'; end if;
 if private.financial_document_effect_revision()<>'sha256:077c377b70d9531b436800593907f1c465d7ce668faa4a27baeac500d648ffa9'
 then raise exception 'FIXTURE_TRIGGER_GRAPH_CHANGED'; end if;
 if exists(select 1 from public.clients where company_id=company and name like 'MCP P16 TEST ONLY%')
  or exists(select 1 from public.projects where company_id=company and title like 'MCP P16 TEST ONLY%')
  or exists(select 1 from public.estimates where company_id=company and estimate_number='MCP-P16-FIXTURE-HISTORY-20260908')
 then raise exception 'FIXTURE_ALREADY_EXISTS_READ_BACK_DO_NOT_RECREATE'; end if;
 select md5(to_jsonb(c)::text) into company_hash from public.companies c where id=company;
 select md5(coalesce(jsonb_agg(to_jsonb(t) order by id),'[]'::jsonb)::text) into tax_hash
  from public.tax_rates t where company_id=company;
 foreach relation_name in array array['clients','projects','project_notes','estimates','line_items'] loop
  execute format('select md5(coalesce(jsonb_agg(to_jsonb(t) order by id),''[]''::jsonb)::text) from public.%I t where company_id::text=$1',relation_name)
   into prior_hash using company::text;
  baseline:=baseline||jsonb_build_object(relation_name,prior_hash);
 end loop;

 insert into public.clients(company_id,name,notes)
 values(company,'MCP P16 TEST ONLY — Fictional customer',
  'Synthetic MCP acceptance fixture. No real customer, contact details, delivery, or accounting sync.')
 returning id into customer_id;
 insert into public.projects(company_id,client_id,title,status,description,title_is_auto,visibility,platform_metadata)
 values(company,customer_id,'MCP P16 TEST ONLY — Deck history','completed',
  'Synthetic completed-job fixture for an MCP pricing test. No real job or customer approval.',false,'office',
  jsonb_build_object('fixture','ops-mcp-p16-20260908','synthetic',true,'purpose','historical-price-source'))
 returning id into history_project_id;
 insert into public.projects(company_id,client_id,title,status,description,title_is_auto,visibility,platform_metadata)
 values(company,customer_id,'MCP P16 TEST ONLY — Deck quote','rfq',
  'Synthetic quote request. Every output draft save requires separate exact approval in OPS. No delivery or accounting sync.',false,'office',
  jsonb_build_object('fixture','ops-mcp-p16-20260908','synthetic',true,'purpose','host-acceptance-target'))
 returning id into quote_project_id;
 insert into public.project_notes(project_id,company_id,author_id,content,created_at,content_metadata)
 values(quote_project_id::text,company::text,owner_id::text,
  'TEST ONLY. Prepared by Codex for owner review; not an enrolled policy or a save approval. Currency CAD. Unit hour. Historical line prices and explicit operator prices are permitted for this fictional trial. Terms: Payment on completion. Every save requires exact approval in OPS. No delivery, invoice issue, accounting sync, or hold release.',
  clock_timestamp(),jsonb_build_object('fixture','ops-mcp-p16-20260908','synthetic',true,'prepared_by','Codex','owner_review_required',true))
 returning id into note_id;
 insert into public.estimates(company_id,client_id,client_ref,project_id,project_ref,estimate_number,title,
  internal_notes,terms,subtotal,tax_rate,tax_amount,total,status,created_by,currency_code)
 values(company,customer_id,customer_id,history_project_id::text,history_project_id,
  'MCP-P16-FIXTURE-HISTORY-20260908','MCP P16 TEST ONLY — Synthetic historical estimate',
  'Synthetic historical source inserted for an authorized MCP acceptance test. Status is fixture data, not a real customer approval. No delivery, invoice, or accounting sync. This is not a host-created draft.',
  'Payment on completion',200,0.0775,15.50,215.50,'approved',owner_id,'CAD')
 returning id into estimate_id;
 insert into public.line_items(company_id,estimate_id,name,description,quantity,unit,unit_price,
  discount_percent,is_taxable,tax_rate_id,is_optional,is_selected,sort_order,type,minimum_charge_snapshot,line_total)
 values(company,estimate_id,'Deck labour','TEST ONLY — synthetic historical price source',
  2,'hour',100,0,true,tax_id,false,true,0,'LABOR',0,200)
 returning id into line_id;
 fixture_ids:=array[customer_id,history_project_id,quote_project_id,note_id,estimate_id,line_id];

 foreach relation_name in array array['clients','projects','project_notes','estimates','line_items'] loop
  execute format('select md5(coalesce(jsonb_agg(to_jsonb(t) order by id),''[]''::jsonb)::text) from public.%I t where company_id::text=$1 and not(id=any($2))',relation_name)
   into after_hash using company::text,fixture_ids;
  if after_hash is distinct from baseline->>relation_name then raise exception 'EXISTING_DATA_CHANGED: %',relation_name; end if;
 end loop;
 if company_hash is distinct from (select md5(to_jsonb(c)::text) from public.companies c where id=company)
  or tax_hash is distinct from (select md5(coalesce(jsonb_agg(to_jsonb(t) order by id),'[]'::jsonb)::text) from public.tax_rates t where company_id=company)
 then raise exception 'EXISTING_SETTINGS_CHANGED'; end if;
 if exists(select 1 from public.accounting_sync_queue where company_id=company and entity_id=any(fixture_ids))
 then raise exception 'UNEXPECTED_ACCOUNTING_QUEUE'; end if;
 if exists(select 1 from public.estimates where company_id=company and (project_ref=quote_project_id or project_id=quote_project_id::text))
 then raise exception 'UNAUTHORIZED_OUTPUT_DRAFT'; end if;
 perform set_config('ops.p16_fixture_evidence',jsonb_build_object(
  'company_id',company,'owner_id',owner_id,'customer_id',customer_id,
  'history_project_id',history_project_id,'quote_project_id',quote_project_id,
  'source_note_id',note_id,'historical_estimate_id',estimate_id,'historical_line_id',line_id,
  'tax_id',tax_id,'currency','CAD','tax_rate',0.0775,'history_total',215.50,'expected_quote_total',232.74,
  'inserted_business_rows',6,'existing_data_hashes',baseline,'company_hash',company_hash,'tax_hash',tax_hash,
  'existing_business_records_unchanged',true,'company_and_tax_settings_unchanged',true,
  'output_drafts_created',0,'accounting_queue_rows_for_fixture',0,'recorded_at',clock_timestamp()
 )::text,true);
end $fixture$;
select current_setting('ops.p16_fixture_evidence')::jsonb as fixture_evidence;
commit;
