# OPS MCP P16-2: independent live effect review
Date: 2026-09-08
Project: ijeekuhbatykdomumfjx
Reviewer: ops_mcp_p16_tax_review
Mode: read-only database/code inspection. No live activation, business RPC, repository/index/HEAD changes, or subagents.

## Verdict
APPROVE THE EXACT LITERAL EFFECT SEAL for the authorized bounded MAVERICK trial:
sha256:077c377b70d9531b436800593907f1c465d7ce668faa4a27baeac500d648ffa9

No blocking finding in the transitive database prepare/save effect graph reviewed below.
This verdict is for exact-literal effect-policy installation and the requested two 30-minute, MAVERICK-only connections, followed by one separately OPS-approved private quote per host. It is not blanket certification of unrelated database functions or all application workers.

## Independent live identity and current state
- Complete public/private function inventory fetched from pg_proc with pg_get_functiondef: 1,811 functions.
- Complete public/private noninternal trigger inventory fetched from pg_trigger with pg_get_triggerdef: 510 triggers.
- Live private.financial_document_effect_revision() computed exactly the seal above, on both initial and final reads.
- Installed financial-document-draft:2026-09-07.v1 seal remained sha256:1dbb20f58a47881a7838a77a2ae69cb55aea8142ba41e5c9b62c0b73a21ae4c5.
- Financial v17 OAuth clients: 0. Financial v17 canary bindings: 0. Financial v17 OAuth grants: 0.
- Active policy d815e12d-f12a-47a2-9e91-a54dd37ab813 belongs to MAVERICK company ddee107c-33cd-483e-8278-0f8d8a180181 and was approved by 8e811f98-9f2b-4f64-b409-ed56074b7dc8.
- Live policy hash: sha256:f27b2ac1d237f72ff1214994394126928e78a6d87f91cc77b1602680b97fea87.
- Policy source: ebb45d42-dd6a-4282-ac73-6a2e1af74278; source seal sha256:4b18713abd825a5a8f469f2e2ee3ed5b9408f7a9efb3fd1803f021ceeffac811.
- Exact effect-policy table has zero triggers, zero rewrite rules, zero outbound FKs, and zero inbound FKs found.

## What the inventory seal covers
Read live private.financial_document_effect_revision() and private.financial_document_hash(jsonb). The former hashes sorted public/private noninternal trigger relation/name/enabled state/definitions, plus sorted public/private function signatures, definitions, security-definer status and proconfig. The latter hashes canonical jsonb text with SHA-256 via extensions.digest.
The complete inventory was retrieved; only reachable financial effects and relevant authority helpers were manually audited. Do not represent this as manual review of all 1,811 unrelated functions.
The seal does not include table defaults, generated expressions, constraints, rewrite rules, privileges, extension implementations or application code. Relevant reachable defaults, generated expressions, constraints, internal triggers, rules and key function grants were checked separately.

## Entry points and exact approval
Read live:
- public.prepare_financial_document_as_system(uuid,uuid,uuid,uuid,text,text[],text,text[],text,text,text,text,text,jsonb)
- public.commit_financial_document_as_actor(uuid,uuid,uuid,uuid,text,text)
- private.assert_financial_document_authority(uuid,uuid,uuid,uuid,text,text[],text,text[],text,text,text,text)
- private.financial_document_reauthorize(private.financial_document_proposals)
- private.financial_document_source(uuid,uuid,jsonb)
- private.persist_private_financial_document(uuid,uuid,jsonb,jsonb)
- private.financial_document_lock(uuid)
- private.financial_document_calculate(jsonb,numeric), private.financial_document_money(numeric)
- private.mcp_oauth_canary_is_current(uuid,uuid,uuid,text,text), private.resolve_agent_actor_authority(uuid,uuid,text[]), private.user_is_active_company_member(uuid,uuid), and scope/label helpers.

Preparation writes a private sealed proposal, pending approve_financial_document action and internal notification only. No estimate or number is allocated.
Commit is service-role-only. It requires exact company/actor/action/change-set binding, preview hash, idempotency key, active original OAuth grant and permissions, current canary, current effect seal, unexpired pending action and unchanged action payload/source. It reauthorizes before replay. Repeat commit returns the existing receipt without another estimate.
Authority checks require the exact narrow five-scope financial client and v17/v12 binding. Canary validity requires matching owner policy receipt/hash, source hash, tax snapshot, effect seal and active company-member authority.
The financial lock protects company scope and serializes source, estimate, line and sequence operations. Source validation ties each client/project/opportunity/catalog/history/policy to the company, uses exact source hashes and recomputes totals.

## Transitive write inventory
Commit writes:
1. public.document_sequences: create missing estimate sequence and increment last_number.
2. private.financial_document_write_tokens: insert then delete transaction/backend/document-specific token.
3. public.estimates: one new draft, distribution_hold=true, no provider IDs/sent/viewed/approved fields.
4. public.line_items: new lines for that estimate, invoice_id remains null.
5. public.audit_log: estimate audit record; its ordinary audit sequence may advance.
6. private.agent_job_history_revisions, private.agent_operational_read_revisions, private.agent_read_domain_revisions: internal revision counters.
7. private.financial_document_proposals: committed receipt/key/time.
8. public.agent_actions: execution and review receipt metadata.
9. public.notifications: resolve internal review notification.

Persisted estimate/line fields and computed totals are read back exactly. No existing estimate, invoice, project total or customer-acceptance row is written.

## Trigger closure and accounting
Read every live noninternal trigger on the direct write tables, then every invoked helper and each transitive destination's trigger list:
- estimates_private_draft_custody and line_items_private_draft_custody -> private.guard_financial_document_custody().
- audit_estimates -> public.audit_trigger_fn() -> public.audit_log.
- estimates_bump_agent_artifact_revision, estimates_bump_agent_task_revision, line_items_bump_agent_task_revision -> private.bump_agent_read_domain_revision() -> private.advance_agent_read_domain_revisions(uuid[],text).
- estimates_bump_agent_job_history_revision -> private.bump_agent_job_history_revision() -> private.advance_agent_job_history_revision(uuid).
- estimates_bump_agent_operational_read_revision -> private.bump_agent_operational_read_revision() -> private.advance_agent_operational_read_revision(uuid).
- estimates_bump_agent_sales_document_revision and line_items_bump_agent_sales_document_revision -> private.bump_agent_sales_document_source_revision() -> private.advance_agent_read_domain_revisions(uuid[],text).
- trg_accounting_sync_queue_estimates and trg_accounting_sync_queue_line_items -> public.enqueue_accounting_sync().
- accounting_sync_queue_private_drafts -> private.guard_financial_document_distribution().
- agent_customer_message_action_receipt -> private.agent_customer_message_action_receipt_trigger().
- guard_purpose_schedule_email_action_update -> private.guard_purpose_schedule_email_action_update().
- trg_agent_actions_updated_at -> public.update_agent_actions_updated_at(); trg_estimate_timestamp -> public.update_timestamp().

All relevant noninternal triggers are enabled (O). The accounting enqueue function was read completely. Relevant INSERT paths attempt only queue insertion; no network/provider call occurs. The BEFORE queue trigger returns NULL for a held estimate, preventing a queued outbound write for either estimate or line. Persistence independently aborts if any estimate queue record exists. The accounting-sync-events branch is only for deletion/inactivation/void, not these inserts.
Custody allows held inserts only with the private token, blocks held document/line edits and deletes, and prevents hold removal. The database CHECK also requires draft state and null sent/viewed/approved/provider IDs.
The email receipt trigger only acts on send_customer_follow_up, so it does not call its receipt helper for approve_financial_document. The schedule-email guard likewise excludes this action type. Internal action timestamps are the only remaining action-trigger effect.
No noninternal triggers exist on audit_log, the three revision destinations, document_sequences, notifications, financial_document_proposals or financial_document_write_tokens.

## FK, deferred-trigger, generated-expression and dynamic-SQL closure
Queried pg_constraint and all pg_trigger rows (including internal) for the direct/transitive tables and the effect-policy table.
- All returned triggers are NOT DEFERRABLE, initially immediate. There is no deferred custom trigger waiting beyond the readback.
- Internal trigger functions are standard RI_FKey_check_ins/check_upd/noaction_del/noaction_upd/restrict_del/cascade_del/setnull_del.
- Five delete-cascade and six delete-set-null triggers exist on this table set, but this save path does not delete those parent rows. The only DELETE is the private write token, which has no inbound FK.
- Updates change counters, receipt/status/timestamps and notification read state; no referenced key is modified. There are no inbound FKs on document_sequences, write tokens or revision-counter tables, and no non-NO-ACTION update FK on agent_actions/notifications/proposals.
- Thus inserts perform referential checks, and the reachable writes do not activate FK cascade/set-null mutations elsewhere.
- CHECK constraints are scalar comparisons/regex/JSON/length expressions, including custody, amount/type and proposal bounds; no business function invocation found.
- Defaults are UUID generation, time, sequence allocation or literals. Generated line_total is round(GREATEST(quantity * unit_price * (1 - COALESCE(discount_percent,0)/100), COALESCE(minimum_charge_snapshot,0)),2), matching calculation.
- No rewrite rules on direct/transitive tables.
- Reachable prepare/save, calculation, locking, audit/revision, custody and accounting-enqueue functions contain no dynamic EXECUTE, HTTP, pg_net, dblink or pg_notify dispatch. The inventory hash reads other function definitions as text; it does not execute them.
- DDL event triggers are not invoked by these DML operations or literal effect-policy UPDATE.
Database event routing therefore closes at the listed internal metadata destinations and suppressed accounting queue. External consumers of logical replication/realtime are not exhaustively audited by this database review.

## Application guard spot checks at reviewed worktree HEAD
Read actual guard blocks, not just search hits:
- src/lib/api/services/approval-queue-service.ts:1561 requires operator_approved plus exact change-set and preview confirmation before commit; bulk approval explicitly rejects financial actions.
- src/app/api/cron/accounting/quickbooks/push-queue/route.ts:586 rejects distribution_hold.
- src/lib/api/services/sage-queue-repository.ts:325 rejects distribution_hold.
- src/lib/api/services/sync-orchestrator.ts:137 and :459 select only distribution_hold=false for QuickBooks/Sage estimate pushes.
These substantiate accounting-worker defense in depth but are not a fresh deployment/runtime proof or audit of every external consumer.

## Literal installation collateral and execution conditions
A literal update of the existing financial-document-draft:2026-09-07.v1 row from the installed old seal to the reviewed seal has no trigger/rule/FK side effect. Only four inventory functions reference this table: prepare, commit, readiness, and current-canary validation. No other direct public/private definition reference was found.
Zero current v17 clients/bindings/grants means the update alone cannot activate an existing financial OAuth connection. Preparation and commit still require a valid exact binding; no broad public exposure is enabled.
Installation should require the current computed seal still equals the literal reviewed seal and the stored old seal still equals the reviewed old seal, change exactly one row, then independently read back. Do not install whatever hash happens to exist later.
Provision exactly MAVERICK/owner/policy with each requested 30-minute expiry. The server allows up to two-hour bindings and does not enforce one quote per client; the authorized workflow must set 30 minutes and stop after one independently approved quote per host.
No reachable database effect blocker found. Unrelated manual inventory audit, external realtime consumers, deployed host transport and customer-live canary execution remain outside this review. They must not be represented as verified by this report.
