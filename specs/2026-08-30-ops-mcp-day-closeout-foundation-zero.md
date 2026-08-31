# OPS MCP — Foundation Zero / Day Closeout Vertical

**Status:** Implemented locally on isolated OPS-Web/Bible branches; not migrated, activated, pushed, deployed, host-accepted, or customer-live.
**Parent vision:** `specs/2026-08-30-ops-mcp-vision-handoff.md`
**Target:** Local-only implementation. No production migration, exposure activation, host support claim, push, or deployment in this phase.

## Outcome

Once inactive v3 is deliberately activated, a connected assistant can resolve **“Close out my day. What did I forget?”** in one tool call. OPS, not the assistant host, computes the closeout from current authorized data and returns:

- tomorrow’s scheduled work and exact readiness gaps;
- work due now, stalled leads, unresolved correspondence, and outstanding invoices;
- bounded communication briefs that a host may turn into drafts, with no send authority;
- explicit coverage, freshness, source revisions, assumptions, metric-definition revision, and supporting OPS references;
- one durable run record when authorized preparation returns findings, clear, or partial source coverage;
- when findings exist, an exact OPS approval-queue preview for filing the closeout; and
- a truthful receipt after the current operator confirms that immutable preview in OPS.

Quiet is a first-class outcome. A clear scheduled run remains inspectable but does not create a notification or approval item.

## Current boundary

- Active MCP exposure `2026-08-29.mcp-exposure.v2` remains immutable and read-only.
- Existing v1 grants remain pinned to v1.
- This phase introduces an **inactive** v3 exposure. It is not activated until each host passes authenticated discovery, tool-call, refresh/revocation, confirmation, commit, receipt, and routine-handoff acceptance.
- V3 grants only `ops.operations.prepare` in addition to the read scopes required by the closeout. It grants no communication-send, financial-write, payment, deletion, mass-action, or regulatory authority.
- Existing dark write families remain unavailable. This vertical does not imply that their host acceptance or confirmation paths are finished.

## Foundation Zero slice

### Current actor and tenant

Every reactive call uses the already resolved MCP actor context. Actor and company IDs never come from tool input. The local routine record and dormant worker bind every scheduled run to one OPS actor, OAuth client, grant, and company. Before any business read, every claimed occurrence rechecks, at execution time:

1. routine enabled and due;
2. company and user active;
3. OAuth client enabled and grant unrevoked;
4. grant still pinned to the routine’s exposure revision and still contains every required scope;
5. current granular OPS permissions; and
6. the exact company binding across every read and write.

The reactive and routine paths fail closed before reads or persistence when current authority is absent. For a routine, the trusted auth adapter itself reads the exact current routine/actor/company/grant/client/scope binding from the database before it can mint an actor context; raw claim fields cannot mint authority. Persistence rechecks that binding again so revocation during the read window cannot become a prepared run. Authority loss creates a typed durable `blocked` failure record, disables that exact routine, and raises a persistent operator notification. Transient execution failures retry after 5 then 15 minutes; the third failure creates a typed durable `failed` failure record and persistent notification. A defensive fourth claim performs no business read. Before any retry or failure is recorded, finalization recovers an exact closeout run that may already have committed when its response was lost. No failure is fabricated as a partial `DayCloseoutResult`, and no failure becomes a quiet success.

### Server-owned closeout definition

Metric definition `day-closeout:2026-08-30.v1` owns the population and result semantics:

- **Tomorrow readiness:** active scheduled occurrences whose company-local start falls in the next local calendar day. Readiness issues use the existing OPS readiness rules. The population and numerator are returned separately.
- **Work due:** bounded current work-queue items from task, schedule, lead, correspondence, commitment, and financial-document sources.
- **Stalled pipeline:** work-queue lead items whose server-derived reason is `follow_up_due` or `operator_action_required`.
- **Outstanding money:** invoices in `awaiting_payment`, `partially_paid`, `past_due`, or `sent`, with server-summed balance by ISO currency. Mixed currencies are never combined.
- **Correspondence:** unresolved correspondence and commitments are included only when the source is normalized and readable. Rejected, missing, or truncated source coverage marks the correspondence component incomplete and suppresses draft claims that depend on missing bodies.

Every component reports its time window, timezone, currency where applicable, population, numerator/denominator where applicable, coverage state, inspected count, omitted count, freshness, source revisions, and evidence references. Bounded reads return `partial` coverage rather than a false exact total.

### Prompt-safety boundary

Names, subjects, snippets, notes, and email bodies remain `untrusted_business_data`. The closeout service may classify only closed server-owned states and reason codes. Returned business strings cannot select tools, widen authority, change recipients, or create side effects.

### Preparation and exact filing

`prepare_day_closeout` is a prepare action. It may persist operational state but does not change a customer, job, schedule, invoice, payment, or external system.

For a closeout with findings, OPS atomically persists:

- the immutable run result;
- a closeout-specific change set containing only the exact proposed internal filing;
- a SHA-256 digest over canonical preview bytes and the authority binding;
- one pending `file_day_closeout` approval action; and
- one review notification pointing to the existing OPS approval queue.

The queue card renders the immutable preview before approval. It does not allow edits or bulk approval. The authenticated approve route passes the current Firebase-resolved actor to a domain-specific database commit function. Commit locks the action and change set, rechecks company and current granular permission, confirms the digest and expiry, consumes the single-use confirmation in the same transaction, records the filing, marks the action executed, and returns the stored receipt. Replays return the original receipt; a different payload under the same idempotency key conflicts.

The receipt states exactly what happened: the closeout was filed inside OPS. It never claims that a draft was sent, money moved, an invoice was issued, or any finding was fixed. Reject/cancel leaves the immutable run inspectable and records that no filing occurred.

### OPS-owned routine foundation

The two local migrations define private OPS-owned routine state for schedule, timezone, named actor, OAuth client/grant binding, required scopes, enabled state, next run, leased claim, bounded retry state, last run, failure state, change cursor, and schedule revision. Due claims use `FOR UPDATE SKIP LOCKED` plus an exact token and expiry. The worker claims exactly one occurrence immediately before executing it, then claims the next only while at least 60 seconds remain in its 240-second execution budget; unstarted rows never spend attempts. It cancels routine work at 210 seconds, preserving the final 30 seconds for truthful finalization. Work-budget expiry follows the same bounded 5/15-minute retry ladder as transient execution failure. Successful or terminal occurrences compute the next occurrence from the stored local wall-clock time, IANA timezone, and ISO weekdays, so daylight-saving changes do not shift the operator's chosen time. The host is never the scheduler or system of record.

The due-row claim/finalization service, valid run history, separate terminal-failure history, change cursor, and cron adapter are implemented locally. The route is fail-closed behind `CRON_SECRET` plus `OPS_DAY_CLOSEOUT_ROUTINES_ENABLED=true`, uses the shared OPS cron workload lease, and processes at most ten occurrences within its hard budget. It is deliberately absent from `vercel.json`, so no schedule is registered. Routine rows default disabled, direct table access remains revoked, and no configuration RPC or interface exists; no routine can be enabled through product code until the exact owner-approved configuration experience is designed and authorized. This phase deliberately does not build a generic automation builder.

Scheduled closeouts use no OPS-paid model call. They compute deterministic findings and communication briefs. With no registered cron and no enabled routine, this local phase adds no runtime cost. Activating the scheduler would add Vercel invocation and database-read cost; that cost must be measured before registration. Host-authored reactive drafts may ride on the user’s host subscription; any future OPS-owned drafting or extraction cost must be measured before pricing or activation.

## Interface choice

The authenticated OPS approval queue is the confirmation surface. A closeout-specific detail block shows:

1. business date and exact OAuth client name;
2. the exact filing statement;
3. grouped finding counts and outstanding balance by currency;
4. correspondence coverage and suppressed-draft warnings; and
5. the irreversible truth boundary: **no messages sent · no money moved**.

The existing card layout, typography, semantic tokens, focus behavior, and reduced-motion path remain unchanged. No separate dashboard or settings acreage is added for a once-per-day review.

## Acceptance matrix

Before activation, dedicated seeded companies must prove:

- company B records never appear in company A’s closeout, change set, action, run, or receipt;
- a missing required owner permission rejects preparation before any source read or durable write;
- crew/operator connections cannot obtain company-wide pipeline or money data;
- revoked membership, client, grant, scope, or permission blocks the next reactive call and, before routine activation, must also block every scheduled run;
- instruction-like customer and email content remains inert business data;
- identical idempotency keys replay the same run/receipt and conflicting payloads fail;
- expired, edited, cross-company, cross-actor, cross-client, and already-consumed confirmation attempts fail closed;
- no closeout path invokes send, payment, financial-document issue, deletion, or mass mutation code;
- correspondence-dependent briefs are suppressed when readability coverage is incomplete;
- a clear authorized run creates no interruption while remaining inspectable;
- a partial result remains a schema-valid closeout run, while blocked and failed outcomes use the separate typed failure ledger; all three create persistent failure signals while clear runs remain quiet;
- overlapping workers cannot claim one occurrence, the worker never charges an attempt to unstarted work, retries stop after the exact bounded sequence, committed-response-loss recovers the stored run, and the next wall-clock occurrence remains stable across DST boundaries;
- the queue card exposes the exact immutable preview before approval; and
- v1/v2 discovery bytes and grant behavior remain unchanged.

## Host acceptance remains a release gate

Local contracts and tests are not host acceptance. Claude, ChatGPT, and any future supported host require separate live, authenticated proof for OAuth consent, tools/list, the composite prepare call, exact OPS confirmation, receipt readback, refresh, revocation, attachments or stable references where applicable, and routine handoff. Until that matrix passes and Jackson explicitly authorizes release, v3 stays inactive and this capability is not customer-live. Migration `20260831004500_agent_day_closeout_routine_worker.sql` is also unapplied. Its static SQL safety contract is verified locally; execution proof remains explicitly unclaimed because migration application was not authorized.
