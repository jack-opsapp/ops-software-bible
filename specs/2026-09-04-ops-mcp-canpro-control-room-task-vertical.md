# OPS MCP Canpro Control-Room Task Vertical

- **Designed and built:** 2026-09-03/04
- **Status:** Local implementation and verification complete; not pushed, deployed, migrated, seeded, granted, activated, scheduled, or customer-live
- **OPS-Web branch:** `feat/ops-mcp-canpro-control-room-p11`
- **Source migration:** `20260904050000_agent_dispatch_confirmation_task.sql`
- **Active production exposure:** unchanged read-only v2

## Purpose

The eleventh Invisible Office vertical is the first bounded Canpro control-room proof. It starts from the existing operational overview and work queue, drills into one exact task record, and prepares one prioritized internal-task proposal when the earliest actionable schedule item still requires dispatch confirmation.

It is not a Canpro fork. Canpro is the proving tenant; every tenant-specific rule is represented as a permissioned, versioned company policy record. No company identity, user identity, task type, title, assignee, or policy document hash is hardcoded into the capability.

Host orchestration remains above MCP. A human assistant or durable OPS worker may call the same overview, work-queue, and task-context reads, then call the same `prepare_dispatch_confirmation_task` domain capability. OPS alone owns tenant and actor identity, authority, policy resolution, evidence validation, deterministic priority, exact confirmation, mutation, idempotency, receipt truth, audit, and retention.

## Immutable surface

- Schema: `2026-09-03.v1`
- Prepare capability: `prepare_dispatch_confirmation_task:2026-09-03.v1`
- Commit capability: `commit_dispatch_confirmation_task`
- Manifest: `2026-09-03.capability-manifest.v19`
- Dormant exposure: `2026-09-03.mcp-exposure.v13`
- Consent catalogue: `2026-09-03.mcp-consent-catalog.v8`
- Policy rule: `unacknowledged-dispatch-follow-up`
- Approval action: `approve_dispatch_confirmation_task`

Exposure v13 is additive to v12 and adds only the prepare tool. The commit exists in the shared domain capability layer but is not an MCP tool: it can run only through the authenticated OPS approval queue after an exact Jackson-bound confirmation. Active production exposure remains the byte-stable read-only v2 contract.

The OAuth grant must include `ops.company.read`, `ops.jobs.read`, `ops.operations.prepare`, `ops.operations.read`, `ops.schedule.read`, and `ops.tasks.read`. The current actor must have company-wide `agent.review`, `projects.view`, `tasks.assign`, `tasks.create`, and `tasks.view`. PostgreSQL reconstructs the full registered permission revision and independently binds the exact actor, tenant, OAuth client, grant, scope ceiling, consent labels, manifest, exposure, and capability revision.

## Versioned policy slice

`private.agent_company_policy_versions` stores only the minimum structured rule needed to make this decision:

- exact tenant, policy id, version, capability, and rule key;
- active/draft/retired state;
- source SOP and system-document ids, versions, and SHA-256 digests;
- fixed schedule source and `confirmation_required` reason;
- exact internal task type, title, approver, and assignee;
- evidence retention days and activation identity.

Only one policy may be active for the tenant/rule pair. Missing, duplicated, inactive, malformed, wrong-tenant, wrong-actor, or changed policy state fails closed. The policy and system digests are bound into the run and change set and are recomputed before commit. Raw SOP bodies are never ingested.

The intended Canpro seed is derived only from current `CANPRO-PRD-002` v1.0 and `CANPRO-SYS-001` v1.0: dispatch work requiring confirmation is flagged for exact operator review, while later site truth may be handled through a separately logged override. The migration intentionally contains no Canpro row. Installing that seed requires a fresh production-write approval.

## Prepare and priority contract

The caller supplies only one canonical source task id, its expected schedule version, three existing OPS proof references, and an idempotency key. Tenant, actor, policy, action type, task type, task title, assignee, approval owner, priority, and retention are not caller-selectable.

The database accepts the source only when it is the earliest currently eligible `confirmation_required` item in the tenant's work queue. It validates the current project/task relationship, active status, schedule version and timing, exact project/task authority, active policy identities, and three same-tenant proof references. A later candidate, cross-tenant id, changed version, or missing evidence rejects the entire request.

Preparation writes one private run, three structured evidence references, one immutable change set, one pending public approval action, and one persistent notification. It creates or updates no task, changes no assignment, sends no message, moves no money, and issues no financial document. Identical retries return the same action; a reused idempotency key with changed arguments rejects.

Project and task labels are explicitly marked untrusted business data. They cannot select authority, policy, SQL, output fields, assignee, action type, or truth claims. The prepared result is bounded to one proposal and three proof references.

## Exact approval and atomic commit

The OPS approval queue renders a sealed, non-editable proposal with the source item, project, exact task to create, policy identity, evidence count, expiry, and zero-effect preparation boundary. It uses a dedicated approval path: autonomous execution and bulk approval reject this action family.

Commit receives only the exact action id, change-set id, preview SHA-256, and action-derived idempotency key. In one transaction it locks the action/change set, verifies the authenticated actor is the policy's exact approver, rechecks membership, scopes, permissions, policy digest, expiry, source priority and schedule version, consumes the confirmation once, calls the canonical OPS task-creation RPC, independently reads the new task back, stores a receipt, marks the action executed, and resolves the persistent notification.

The truthful receipt states exactly one internal OPS task created, zero source-task updates, zero assignment changes, zero messages sent, no money moved, and zero financial documents issued. Identical retries return the stored receipt. Changed commit identity, changed preview, stale approval, consumed confirmation, policy drift, source drift, or task-write failure rejects; the task-write failure rolls back the confirmation, task, action, notification, and receipt together.

Rejection records an auditable no-effect receipt, leaves the source task unchanged, and resolves the persistent notification.

## Evidence custody and tenant-local learning

Evidence persistence contains only typed OPS references, display labels, versions, hashes, and proof ids. It never stores raw policy documents, correspondence bodies, browser content, or an indiscriminate tenant corpus. Every run, evidence row, proposal, action, confirmation, receipt, and task identity is tenant-bound.

Each evidence row carries a policy-defined retention date, legal-hold flag, redaction state, and tombstone. Manual redaction requires current `agent.review` authority. The retention primitive redacts expired evidence only when no legal hold exists. Redaction replaces retained display labels with `[redacted]` while preserving hashes, ids, timestamps, result identity, and audit tombstones. No schedule activates automatic retention in this local build.

Learning is tenant-local and limited to the exact policy/evidence/outcome trail. No cross-tenant corpus, shared tenant memory, or external-host memory is created.

## Existing capability reuse and exclusions

The vertical reuses the existing operational overview, work queue, task context, approval queue, notification rail, canonical task mutation, audit, rate-limit, confirmation, and receipt patterns. It does not duplicate Phase 10 crew call-out recovery. If a work-queue item requires crew recovery, the existing `prepare_crew_callout_recovery` capability remains the specialized planning tool; this phase only converts one current unacknowledged-dispatch finding into one internal follow-up task after exact approval.

Free-form SQL is not exposed. QuickBooks capability in OPS is separate from a live Canpro connection: live readback found two Canpro accounting connection records, zero connected states, zero sync, and zero push authority. This vertical contains no accounting scope, provider call, financial write, or consequential browser automation.

## Verification evidence

The final focused suite passes 105 tests across contracts, deterministic shadow orchestration, service/repository behavior, OAuth labels and exposure pinning, principal/runtime dispatch, exact approval UI, bulk/autonomous rejection, and SQL/ACL contracts. The broad agent-control-plane suite records 3,318 passing and 12 failing tests across 253 files; all failures are the unchanged loopback-bind sandbox and schedule-timezone baselines, while every Phase 11 test passes. Changed files have zero ESLint errors, and the repository type check emits no error from the Phase 11 surface; unrelated historical social-test TypeScript errors remain a separate baseline.

A disposable PostgreSQL 17.11 cluster compiled the migration against production-shaped prerequisites and exercised real transactions. It proved tenant isolation, earliest-item priority, zero-effect preparation, marked prompt-injection text, same-input replay, changed-input rejection, changed-preview rejection, exact one-task commit, independent readback, persistent-notification resolution, identical double-commit replay, changed commit-key rejection, task-write rollback atomicity, schedule-version stale rejection, policy-mutation rejection, no-effect rejection, legal-hold blocking, manual redaction, automatic retention redaction, and durable tombstones. The cluster and all temporary data were removed after proof.

The migration is additive and declares no policy seed, OAuth client, grant, exposure activation, routine, retention schedule, accounting connection, or customer-live business mutation. It has not been applied to production.

## Phase 10 boundary carried forward

Phase 10 implementation commit `464a8cbf42b515ff4845852ab4f566366874ce14` and pushed main `1ea480b0e38d3a1b920395cbe4c91309901659b6` are present in source. No-code carrier `2a086736ee7bad081caf6cdf753094b3f35967af` retriggered the same source tree; Vercel deployment `7sgYzredXDaeHfJGK3oEQcSHCrYk` completed successfully at `2026-09-04T04:05:34Z`. Its focused release evidence records 93 changed-vertical tests and a successful 371-route production build. Production ledger `20260904033119_agent_crew_callout_recovery_preview` is applied from the exact Phase 10 migration. Post-deployment public production metadata still exposes only read-only v2.

Phase 10 remains dormant authority: no v12 OAuth client, grant, activation, authenticated host acceptance, commit/apply/send capability, or customer-live mutation authority exists. “Production-deployed” therefore means dormant code and database source are present, not that any assistant can use crew-recovery authority for a customer.

## Activation boundary

Before this vertical can leave the local proving state, separate explicit approvals are required for each consequential step: production migration, application push/deployment, versioned Canpro policy seed, OAuth client and grant, v13 activation, host acceptance, routine/retention scheduling, or customer-live run. Activation must first prove a no-effect shadow preparation and exact authenticated readback against Canpro without changing the active read-only v2 contract for existing clients.

There is no new subscription or paid provider in this build. If later activated, the vertical uses existing OPS Web and Supabase execution; any incremental model or durable-worker cost must be measured and disclosed at that separate activation gate.
