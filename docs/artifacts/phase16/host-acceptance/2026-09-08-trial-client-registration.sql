-- Approved 2026-09-08: new MAVERICK Codex/Claude trial clients only.
-- Registration confers no active financial access without exact binding and fresh consent.
begin;
set local lock_timeout='3s';
set local statement_timeout='30s';
set local timezone='UTC';
do $guard$
begin
 if private.financial_document_effect_revision()<>'sha256:077c377b70d9531b436800593907f1c465d7ce668faa4a27baeac500d648ffa9'
 then raise exception 'TRIAL_EFFECT_DRIFT'; end if;
 if not exists(select 1 from private.financial_document_policies p
 where p.id='d815e12d-f12a-47a2-9e91-a54dd37ab813' and p.company_id='ddee107c-33cd-483e-8278-0f8d8a180181' and p.status='active'
 and private.financial_document_hash(to_jsonb(p))='sha256:f27b2ac1d237f72ff1214994394126928e78a6d87f91cc77b1602680b97fea87')
 then raise exception 'TRIAL_POLICY_CHANGED'; end if;
 if exists(select 1 from private.mcp_oauth_clients where client_name like 'OPS Phase16 MAVERICK%')
 then raise exception 'TRIAL_CLIENTS_EXIST_READ_BACK_DO_NOT_RECREATE'; end if;
 perform set_config('ops.p16_prior_clients', (select md5(coalesce(jsonb_agg(to_jsonb(c) order by client_id),'[]'::jsonb)::text) from private.mcp_oauth_clients c),true);
end $guard$;
set local role service_role;
select set_config('request.jwt.claims','{"role":"service_role"}',true);
select set_config('ops.p16_new_clients',jsonb_agg(to_jsonb(c))::text,true) from (
 select * from public.register_mcp_oauth_client_as_system(
 'OPS Phase16 MAVERICK Codex Acceptance',
 array['http://127.0.0.1:63821/callback/ops_p16_codex_20260908'],
 'ops.company.read ops.customers.read ops.financial_documents.prepare ops.financial_documents.read ops.jobs.read',
 array['ops.company.read','ops.customers.read','ops.financial_documents.prepare','ops.financial_documents.read','ops.jobs.read'],
 '2026-09-07.mcp-consent-catalog.v12','2026-09-07.mcp-exposure.v17',null,null)
 union all
 select * from public.register_mcp_oauth_client_as_system(
 'OPS Phase16 MAVERICK Claude Acceptance',
 array['https://claude.ai/api/mcp/auth_callback','https://claude.com/api/mcp/auth_callback'],
 'ops.company.read ops.customers.read ops.financial_documents.prepare ops.financial_documents.read ops.jobs.read',
 array['ops.company.read','ops.customers.read','ops.financial_documents.prepare','ops.financial_documents.read','ops.jobs.read'],
 '2026-09-07.mcp-consent-catalog.v12','2026-09-07.mcp-exposure.v17',null,null)
) c;
reset role;
do $verify$
begin
 if jsonb_array_length(current_setting('ops.p16_new_clients')::jsonb)<>2
 or current_setting('ops.p16_prior_clients')<>(select md5(coalesce(jsonb_agg(to_jsonb(c) order by client_id),'[]'::jsonb)::text) from private.mcp_oauth_clients c where client_id not in (select (v->>'client_id')::uuid from jsonb_array_elements(current_setting('ops.p16_new_clients')::jsonb) v))
 then raise exception 'TRIAL_CLIENT_REGISTRATION_INTEGRITY'; end if;
end $verify$;
select jsonb_build_object('clients',current_setting('ops.p16_new_clients')::jsonb,'existing_clients_unchanged',true,'bindings_created',0,'grants_created',0,'recorded_at',clock_timestamp()) as registration_receipt;
commit;
