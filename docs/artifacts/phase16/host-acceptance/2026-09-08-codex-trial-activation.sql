-- Jackson approved the bounded 30-minute MAVERICK Codex/Claude trial.
-- Exact reviewed effect literal only. This activation starts Codex; Claude starts when its host setup is ready.
begin;
set local lock_timeout='3s';
set local statement_timeout='30s';
set local timezone='UTC';
do $guard$
declare prior text; affected integer;
begin
 select effect_revision into prior from private.financial_document_effect_policy
 where revision='financial-document-draft:2026-09-07.v1' for update;
 if prior is distinct from 'sha256:1dbb20f58a47881a7838a77a2ae69cb55aea8142ba41e5c9b62c0b73a21ae4c5'
 or private.financial_document_effect_revision() is distinct from 'sha256:077c377b70d9531b436800593907f1c465d7ce668faa4a27baeac500d648ffa9'
 then raise exception 'TRIAL_REVIEWED_EFFECT_CHANGED';end if;
 if (select count(*) from private.mcp_oauth_clients where 'ops.financial_documents.prepare'=any(scope_ceiling))<>2
 or not exists(select 1 from private.mcp_oauth_clients where client_id='c15e9551-c7d3-4960-ac9a-e24439bc958f' and client_name='OPS Phase16 MAVERICK Codex Acceptance' and redirect_uris=array['http://127.0.0.1:63821/callback/ops_p16_codex_20260908'] and disabled_at is null)
 or not exists(select 1 from private.mcp_oauth_clients where client_id='0769a35e-8d80-48e1-b6b6-c91c69895f7c' and client_name='OPS Phase16 MAVERICK Claude Acceptance' and disabled_at is null)
 or exists(select 1 from private.mcp_oauth_canary_bindings where financial_policy_id is not null)
 then raise exception 'TRIAL_CLIENT_BASELINE_CHANGED';end if;
 if not exists(select 1 from private.financial_document_policies p join public.project_notes n on n.id=p.source_document_id
 where p.id='d815e12d-f12a-47a2-9e91-a54dd37ab813' and p.company_id='ddee107c-33cd-483e-8278-0f8d8a180181' and p.status='active'
 and private.financial_document_hash(to_jsonb(p))='sha256:f27b2ac1d237f72ff1214994394126928e78a6d87f91cc77b1602680b97fea87'
 and private.financial_document_hash(to_jsonb(n))='sha256:4b18713abd825a5a8f469f2e2ee3ed5b9408f7a9efb3fd1803f021ceeffac811')
 then raise exception 'TRIAL_ENROLLED_POLICY_CHANGED';end if;
 update private.financial_document_effect_policy set effect_revision='sha256:077c377b70d9531b436800593907f1c465d7ce668faa4a27baeac500d648ffa9'
 where revision='financial-document-draft:2026-09-07.v1';
 get diagnostics affected=row_count;
 if affected<>1 then raise exception 'TRIAL_EFFECT_ROW_COUNT';end if;
 perform set_config('ops.p16_codex_expires_at',(statement_timestamp()+interval '30 minutes')::text,true);
end $guard$;
set local role service_role;
select set_config('request.jwt.claims','{"role":"service_role"}',true);
select set_config('ops.p16_codex_binding_id',public.provision_mcp_oauth_canary_as_system(
 'c15e9551-c7d3-4960-ac9a-e24439bc958f','8e811f98-9f2b-4f64-b409-ed56074b7dc8','ddee107c-33cd-483e-8278-0f8d8a180181',
 '2026-09-07.mcp-exposure.v17','2026-09-07.mcp-consent-catalog.v12',
 current_setting('ops.p16_codex_expires_at')::timestamptz,'d815e12d-f12a-47a2-9e91-a54dd37ab813',
 'sha256:f27b2ac1d237f72ff1214994394126928e78a6d87f91cc77b1602680b97fea87',
 'sha256:077c377b70d9531b436800593907f1c465d7ce668faa4a27baeac500d648ffa9')::text,true);
reset role;
select jsonb_build_object('binding',(select to_jsonb(b) from private.mcp_oauth_canary_bindings b where id=current_setting('ops.p16_codex_binding_id')::uuid),
 'effect_installed',(select effect_revision from private.financial_document_effect_policy where revision='financial-document-draft:2026-09-07.v1'),
 'effect_current',private.financial_document_effect_revision(),'recorded_at',clock_timestamp(),'documents_created',0,'claude_binding_started',false) as activation_receipt;
commit;
