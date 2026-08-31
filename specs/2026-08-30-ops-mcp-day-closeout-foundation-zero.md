# OPS MCP — Foundation Zero / Day Closeout Vertical

**Status:** Production Foundation Zero and its operator-owned configuration boundary are live but dormant. The active customer contract remains read-only v2, production has no v3 client, grant, or routine, and the worker flag is absent. An exact-subject v3 synthetic-canary release candidate is locally complete and verified but has not been pushed, deployed, or applied. Authenticated v3 live-host proof, v3 activation, and worker activation have not been performed.
**Parent vision:** `specs/2026-08-30-ops-mcp-vision-handoff.md`
**Release:** OPS-Web Foundation Zero `1742861a`; production-readiness release `1945c60b`, contained by live production head `4d9f0313`; Vercel `dpl_5A9VnK1bmMMkwhPCsnVUxNufYvjZ` (`Ready`, production, `app.opsapp.co`).

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
- The deployed application contains an **inactive** v3 exposure. No client or grant selects it. It is not activated until each host passes authenticated discovery, tool-call, refresh/revocation, confirmation, commit, receipt, and routine-handoff acceptance.
- The production-readiness release does not change the active exposure constant. V2 remains the only active production contract, with the same 34 read-only tools and 20 scopes.
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

The three production-applied migrations define private OPS-owned routine state for schedule, timezone, named actor, OAuth client/grant binding, required scopes, enabled state, next run, leased claim, bounded retry state, last run, failure state, change cursor, schedule revision, and covering foreign-key indexes. Due claims use `FOR UPDATE SKIP LOCKED` plus an exact token and expiry. The worker claims exactly one occurrence immediately before executing it, then claims the next only while at least 60 seconds remain in its 240-second execution budget; unstarted rows never spend attempts. It cancels routine work at 210 seconds, preserving the final 30 seconds for truthful finalization. Work-budget expiry follows the same bounded 5/15-minute retry ladder as transient execution failure. Successful or terminal occurrences compute the next occurrence from the stored local wall-clock time, IANA timezone, and ISO weekdays, so daylight-saving changes do not shift the operator's chosen time. The host is never the scheduler or system of record.

The due-row claim/finalization service, valid run history, separate terminal-failure history, change cursor, and cron adapter are deployed. The route is fail-closed behind `CRON_SECRET` plus `OPS_DAY_CLOSEOUT_ROUTINES_ENABLED=true`, uses the shared OPS cron workload lease, and processes at most ten occurrences within its hard budget. Production currently has no registered schedule, no v3 client or grant, no routine rows, and no enabled worker.

The production release adds the smallest operator-owned configuration boundary over the private routine table:

- service-role-only list and upsert RPCs bind the current session actor and company to one exact live v3 grant, its reviewed seven-scope ceiling, and `settings.integrations: all`;
- creating or enabling a routine requires every current granular closeout permission; an existing operator-owned routine remains visible and can be disabled after data-authority loss, while re-enabling still fails closed;
- OPS owns the company timezone, all-seven-day cadence, next-run calculation, schedule revision, lease invalidation, and retry reset;
- identical saves are no-ops; authority, time, grant, or enabled-state changes invalidate any outstanding lease and increment the schedule revision;
- OAuth grant or token revocation disables and de-leases the bound routine in the same transaction; and
- direct table access remains revoked, tenant isolation remains inside the database boundary, and no generic automation builder is introduced.

The production release registers `/api/cron/day-closeout-routines` on the offset `2-59/5 * * * *` lane. That preserves the production cron collision budget and adds 288 function invocations per day, approximately 8,640 in a 30-day month. Registration alone cannot execute routine work because `OPS_DAY_CLOSEOUT_ROUTINES_ENABLED` is absent in production. Scheduled closeouts use no OPS-paid model call; they compute deterministic findings and communication briefs. Vercel bills cron runs as ordinary function invocations, so the marginal charge is zero while the project remains inside its included allocation; beyond that allocation, invocation and compute charges apply. Host-authored reactive drafts may ride on the user’s host subscription; any future OPS-owned drafting or extraction cost must be measured before pricing or activation.

## Interface choice

The authenticated OPS approval queue remains the confirmation surface. For an eligible v3 connection, the production release includes one compact control inside **Settings → Integrations → Connected agents**: “Close out my day,” a daily switch, one company-local time, the company timezone, last-review state, and an explicit save. It states **Sends nothing. Moves no money.** The control is absent for v1/v2 grants and disappears when the grant is revoked. With zero production v3 grants, it is not currently visible to a customer. There is no standalone routine dashboard or generic builder.

A closeout-specific approval detail block shows:

1. business date and exact OAuth client name;
2. the exact filing statement;
3. grouped finding counts and outstanding balance by currency;
4. correspondence coverage and suppressed-draft warnings; and
5. the irreversible truth boundary: **no messages sent · no money moved**.

The existing card layout, typography, semantic tokens, focus behavior, and reduced-motion path remain unchanged. The candidate was checked at desktop and 390×844 mobile widths; its time input, switch, save state, truth boundary, and server readback remain visible without horizontal clipping.

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

## Production-readiness implementation proof

The isolated OPS-Web implementation at commit `2c23cb8e`, released through merge commit `1945c60b`, includes the routine configuration migration and runtime SQL contract, authenticated settings API, Connected agents control, offset Vercel schedule, Node 22 CI alignment, and a direct authenticated MCP host-acceptance runner. The runner performs protocol initialization, the initialized notification, exact single-tool discovery, and one schema-valid `prepare_day_closeout` call. Its output contains only contract revision and aggregate state; it never prints the bearer, business contents, entity identifiers, or transport error bodies.

Fresh local proof on Node 22.23.2 includes:

- both real PostgreSQL migration contracts passing inside rollback transactions, including cross-tenant denial, exact scope/grant binding, permission loss, safe disable, idempotent replay, lease invalidation, grant/token revocation, and reconnect;
- 723/723 focused MCP, OAuth, closeout, routine, settings, and cron-isolation tests passing;
- TypeScript typecheck and Prettier checks passing;
- repository lint exiting successfully with only the inherited warning backlog;
- the complete 419-route candidate build and fresh 426-route release-merge build passing; and
- desktop and 390×844 browser proof of toggle → save → authoritative server readback, with v2 connections unchanged.

The repository-wide Vitest sweep passes 15,318 tests and remains red on 29 unrelated pre-existing email, pipeline, hook, schedule, and summary-refresh tests. The exact failures do not touch this vertical. `npm audit --omit=dev` also reports 33 inherited production-dependency advisories (3 critical, 16 high, 13 moderate, 1 low); this candidate adds no dependency or lockfile change. Those are separate repository health work, not evidence that this vertical's authority or routine contracts failed.

## Production proof and remaining activation gate

Production ledger versions `20260831042518_agent_day_closeout_foundation_zero`, `20260831042631_agent_day_closeout_routine_worker`, `20260831042924_agent_day_closeout_fk_indexes`, and `20260831061700_agent_day_closeout_routine_configuration` are applied to `ops-app` and mirrored byte-exact in this Bible. Live readback proves all six tables have RLS enabled, zero policies, zero direct `anon`/`authenticated`/`service_role` table grants, and zero rows; every public closeout RPC is search-path pinned and executable only by `service_role`. The configuration list RPC is stable; its upsert RPC is volatile. Both pin `pg_catalog, public, private, extensions, pg_temp`, bind the current actor and company to the exact inactive v3 grant, and remain executable only by `postgres` and `service_role`. Supabase's scoped security and performance advisors report no warning or error for this slice. Their remaining informational notices are expected on empty dormant tables: fail-closed RLS with no policies and indexes not yet used.

OPS-Web merge commit `1945c60b` reached production in Vercel deployment `dpl_omGcXfSXUiEX8bHH2aT86vTsCby3`; current live head `4d9f0313` is a verified descendant containing that release and is `Ready` in deployment `dpl_5A9VnK1bmMMkwhPCsnVUxNufYvjZ`. The release merge passed 723/723 focused closeout, authority, MCP, OAuth, settings, and cron tests, followed by a fresh 426-route Node 22 production build. A later concurrent analytics merge was confirmed to contain `1945c60b` and passed its own production build before taking the live alias.

Post-alias live readback at `app.opsapp.co` proves that MCP metadata still advertises exactly the twenty read-only v2 scopes and excludes `ops.operations.prepare`. Unauthenticated probes of MCP transport, routine configuration, and routine cron routes each return 401. Vercel has a production `CRON_SECRET`, but `OPS_DAY_CLOSEOUT_ROUTINES_ENABLED` is absent. The first observed authenticated scheduled invocation on the live descendant returned 200 through the fail-closed disabled path. Subsequent database readback still found zero v3 OAuth clients, zero v3 grants, zero routines, zero closeout runs, and zero routine failures. The exact deployment and scoped routes showed no error or fatal runtime entries after release.

Deployment and schema proof are not host acceptance. Existing Codex proof remains a bounded read-only v1 path; production v2 discovery exists but authenticated v2 host acceptance remains pending. Claude, ChatGPT, Codex, and any future supported host require separate live proof for the new v3 consent, composite prepare call, exact OPS confirmation, receipt readback, refresh, revocation, attachments or stable references where applicable, and routine handoff. Until that matrix passes and Jackson explicitly authorizes activation, v3 stays inactive and this capability is not customer-live.

### Exact-subject synthetic-canary candidate (local only, 2026-08-31)

OPS-Web commits `9df17e32`, `7b2acd91`, `429f36e9`, `e6794bc6`, and review-hardening commit `6915f9be` form the production candidate for the first authenticated v3 acceptance. The verified reconciled local head is `f0dd81be`. Candidate migration `20260831190000_mcp_v3_synthetic_canary.sql` is intentionally **not applied** and therefore is not yet mirrored into this Bible's production migration archive.

The candidate admits only one service-provisioned client/user/company binding for company name `OPS MCP SYNTHETIC CANARY`, exposure `2026-08-30.mcp-exposure.v3`, consent catalogue `2026-08-30.mcp-consent-catalog.v2`, and a maximum 24-hour expiry. It requires the exact seven reviewed scopes, active membership, `settings.integrations: all`, and the current seven granular owner permissions. Public registration, metadata, ordinary consent, existing grants, and the active server exposure remain pinned to read-only v2. The migration lands before the application: its one-argument bearer compatibility wrapper continues resolving only non-v3 grants for the old application while refusing v3, and the new two-argument resolver rechecks the application-selected active exposure for the new application.

The private acceptance runner starts a fresh loopback PKCE receiver, registers and provisions the exact synthetic client, opens production consent without printing the URL, exchanges and rotates tokens, initializes the real MCP transport, lists exactly `prepare_day_closeout`, and requires a schema-valid approval-required result with at least one finding. It retains the prepared run, action, change set, and preview hash only in process memory. It then opens the authenticated OPS review queue and waits on a service-role-only aggregate inspector until the current synthetic operator files that exact immutable closeout and a receipt proves `filed_inside_ops`, `messages_sent = 0`, and `money_moved = false`. The inspector joins those four proof values through the exact tenant, actor, grant, client, run, change set, confirmation, action, and receipt, so another qualifying closeout cannot satisfy acceptance. The runner replays the same commit idempotency key and accepts only the original truthful receipt with `replayed = true`. It next opens Connected agents and waits until the exact OPS-owned routine is enabled. The inspector returns booleans only and cannot return tenant, actor, entity, receipt, token, or business-content identifiers.

After the operator proof, the runner deliberately reuses the spent refresh token. The database revokes that token family and grant and disables/de-leases the bound routine with `OAUTH_GRANT_REVOKED`; the runner proves the rotated bearer is rejected. Provision, refresh, routine configuration, durable v3 OAuth writes, and disablement all take the same transaction-scoped client lock before table mutation, so shutdown is the final authority decision without reverse row-lock order. Cleanup also clears a stale lease even if a row was already marked disabled. The runner's unconditional cleanup disables the binding and client, revokes remaining grants/tokens, disables and de-leases routines, and calls a separate aggregate verifier that independently proves no active binding, client, grant, token, or runnable routine remains. Every service-role acceptance RPC has a hard abort deadline; cleanup uses an independent deadline so cancellation cannot skip revocation. If acceptance and cleanup both fail, both non-disclosing stages are preserved in one aggregate error. Cancellation, denial, callback mismatch, missing fixture, proof timeout, and transport failures all take the same cleanup path. CLI output contains only progress labels and aggregate contract results; OAuth secrets, callback data, UUIDs, business contents, and transport bodies are never printed.

Fresh candidate proof includes 41 focused MCP/day-closeout/collections-coherence files and 874 tests passing, ten loopback acceptance cases, ten migration-source cases, the rollback-isolated PostgreSQL runtime contract, a disposable real two-session concurrency contract for provision/refresh/routine/durable-write races against shutdown, 8 GB TypeScript typecheck, touched-file ESLint, diff hygiene, and an optimized production build. The database fixtures prove exact replay/conflict behavior, unrelated-run rejection, cross-tenant denial, old/new application rolling compatibility, v3 rejection by the legacy resolver, current-authority loss, refresh expiry, spent-refresh theft, routine de-leasing, bearer rejection, ACLs, independent cleanup, common-lock waiting, and final zero-authority readback. The build completed with inherited warnings for `libheif-js`, the existing client-side `async_hooks` fallback, stale Browserslist data, metadata defaults, and unavailable non-production PMF data; it produced the optimized route manifest successfully. This candidate adds no dependency, persistent worker, model/provider call, or new paid service. Its short-lived acceptance polling runs only during the one synthetic canary and adds negligible database/function usage within the existing Supabase/Vercel plans; any future always-on worker cost remains a separate measured activation gate.

The safe release order is fixed. Steps 1 and 2 are complete; steps 3 through 7 remain deliberately gated:

1. **Complete:** apply the routine-configuration migration and independently read back functions, ACLs, and zero customer rows;
2. **Complete:** deploy the application candidate with v2 still active and `OPS_DAY_CLOSEOUT_ROUTINES_ENABLED` unset/false;
3. after Jackson explicitly authorizes release, apply `20260831190000_mcp_v3_synthetic_canary.sql` first and independently verify its functions, ACLs, unchanged v2 metadata, and zero canary bindings;
4. deploy the exact OPS-Web candidate while v2 remains active and the worker remains off;
5. create one dedicated synthetic company/operator plus a safe fixture guaranteed to produce at least one approval-required finding; then run the acceptance runner while Jackson signs in, approves consent, files the exact closeout in OPS, and enables the synthetic routine;
6. require the runner to complete refresh-theft simulation, bearer rejection, routine shutdown, unconditional cleanup, and independent zero-authority readback; and
7. treat the direct production canary as host-neutral protocol proof, not as acceptance for Claude, ChatGPT, Codex, or any other outside host. Consider global v3 only as a separate Jackson-approved release after the chosen launch host also passes its authenticated host-specific matrix. Worker activation remains separate: enable only one synthetic routine first and prove its scheduled receipt before any customer routine is enabled.
