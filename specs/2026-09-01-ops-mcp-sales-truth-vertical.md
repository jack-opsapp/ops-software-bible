# OPS MCP Phase 5 — Sales Truth Vertical

**Status:** Locally implemented and verified on 2026-09-01. Dormant release candidate only. Not pushed, deployed, migrated, registered, granted, activated, or customer-live.

**Approved source:** `specs/2026-08-30-ops-mcp-vision-handoff.md`

**OPS-Web lineage:** local branch `feat/ops-mcp-sales-truth-p5`, rooted at authoritative Phase 4 commit `cf858e0d2d65e9642be8a9aa7b791246b78af8fb`

**Source migration:** `ops-web/supabase/migrations/20260901153000_agent_sales_truth_read.sql`

**Bible mirror:** `supabase/migrations/20260901153000_agent_sales_truth_read.sql`

## Product answer

The fifth Invisible Office vertical answers one bounded question:

> Why are we losing leads, and what should I fix first?

One read-only call returns recent lead population, resolved close rate, unresolved sensitivity, canonical attribution, recorded loss reasons, first-response time, pipeline velocity, explicit coverage/confidence, and at most three ranked operational repairs. Every recommendation is linked to structured source references and carries `causal_claim: false`; OPS reports measured associations and data-quality gaps, never an invented cause.

This is a pure analytical read. It creates no result record, action, notification, routine, draft, message, approval, model/provider call, or UI.

## Immutable control-plane identity

- Capability: `analyze_sales_truth`
- Input schema: strict empty object
- Result schema: `2026-09-01.v1`
- Metric definition: `sales-truth:2026-09-01.v1`
- Capability manifest: `2026-09-01.capability-manifest.v13`
- Dormant exposure: `2026-09-01.mcp-exposure.v7`
- Active production exposure remains `2026-08-29.mcp-exposure.v2`.
- V7 contains `analyze_hiring_break_even`, `check_customer_reply`, and `analyze_sales_truth`. V1 through v6 remain immutable.

The tool requires OAuth scopes `ops.operations.read` and `ops.correspondence.read`, plus current company-wide `pipeline.view` and `email.view` permissions. Tenant, actor, company, OAuth client/grant, grant revision, scope ceiling, permission snapshot, source window, metric definition, and authority policy are never caller-selectable.

## Cohort and metric definitions

The cohort is every non-deleted, non-merged opportunity created during the 180 company-local calendar days ending on the business date at the server-owned observation instant.

Qualified stages are `qualifying`, `quoting`, `quoted`, `follow_up`, `negotiation`, `won`, and `lost`. `new_lead` and `discarded` remain visible population counts but do not enter qualified metrics. Resolved means current `won` or `lost`; open qualified opportunities are disclosed and excluded from the canonical close-rate denominator.

### Close rate

- Canonical rate: `won / (won + lost)`.
- Minimum usable resolved sample: 10.
- Statistical interval: Wilson 95% interval on the resolved population.
- Unresolved sensitivity: lower bound `won / (won + lost + open)` and upper bound `(won + open) / (won + lost + open)`.

The sensitivity band is a scenario range, not a forecast.

### Attribution

Attribution uses only constrained `opportunities.source`. The service never infers source from a title, customer identity, message, note, or model. Each non-empty segment reports cohort, qualified, won, lost, open-qualified, resolved close rate where usable, and confidence. Null source is explicit `missing`.

### Loss reasons

For current lost opportunities, the latest non-superseded structured `opportunity_dispositions.reason_code` wins. Legacy `opportunities.lost_reason` is a disclosed fallback only when structured evidence is absent. Code-owned normalization maps the raw value to `price`, `timing_or_budget`, `competition`, `scope_mismatch`, `no_response`, `customer_declined`, `other`, `unmapped`, or `missing`. Raw labels and disposition notes never cross the MCP boundary.

### First response

The measurable population contains cohort opportunities with an exact linked inbound `email` or `text_message` activity at or after lead creation. Response time is elapsed minutes to the first later linked outbound email/text activity. Leads with an inbound but no later outbound are disclosed as unresponded. The answer separately reports overall correspondence-linkage coverage so missing links cannot masquerade as fast response performance. No business-hours assumption is made.

### Pipeline velocity

Per-stage velocity uses non-negative completed `stage_transitions.duration_in_stage` observations when the transition exits a qualified, non-terminal stage. Qualification-to-close duration uses the first transition into a qualified stage and the first later transition to `won` or `lost`. Current-stage timestamps do not substitute for missing transition history. Each usable duration carries sample, median, p75, coverage, confidence, and stable transition references.

## Confidence and recommendations

Confidence is deterministic:

- high: sample at least 30 and relevant coverage at least 90%;
- medium: sample at least 20 and coverage at least 80%;
- low: sample at least 10 and coverage at least 70%;
- insufficient: any smaller or less complete population.

The service returns at most three fixed-code recommendations in this priority: repair source bounds; capture outcomes; capture loss reasons; repair stage history; repair correspondence linkage; reduce first-response delay; review the leading recorded loss reason; review the weakest measured source; clear the slowest measured stage; otherwise preserve the current process. The first item is the answer to what should be fixed first. Every item includes a structured threshold comparison and bounded supporting-record references.

## Database and source boundary

The candidate migration creates no table, policy, queue, action, or analytical result. It adds:

1. owner-only `private.assert_agent_sales_truth_authority(...)`;
2. service-role-only `public.read_agent_sales_truth_as_system(...)`;
3. private read domain `sales_truth`, seeded for every company;
4. source-revision triggers on `opportunities`, `stage_transitions`, `opportunity_dispositions`, and `activities`;
5. partial cohort index `opportunities_agent_sales_truth_cohort_v1_idx`; and
6. partial linked-correspondence index `activities_agent_sales_truth_history_v1_idx`.

The public RPC is one bounded `STABLE SECURITY DEFINER` read with an empty pinned search path. It revokes execution from `public`, `anon`, and `authenticated`, grants only `service_role`, and independently rechecks current company membership, OAuth client/grant/revision/exposure/scopes, permission snapshot, manifest v13, and exposure v7 before reading. The private authority helper has no app-role execution grant.

Source ceilings use one extra row to prove overflow:

- 5,000 opportunities;
- 20,000 stage transitions;
- 5,000 dispositions;
- 20,000 linked activities; and
- 100 returned supporting records.

Any source ceiling forces an insufficient result. The response carries the `sales_truth` and company-context revisions. Index postflight verifies exact names, keys, predicates, readiness, validity, and uniqueness so `CREATE INDEX IF NOT EXISTS` cannot conceal a drifted same-named definition.

Only opaque IDs, constrained enums, timestamps, counts, normalized categories, and metric values leave the source boundary. Activity bodies, notes, opportunity titles, customer names, email addresses, transport secrets, and raw loss text do not. The result is explicitly marked `untrusted_business_data` with a fixed instruction-safety directive.

## Live source reality at design time

Read-only production inspection on 2026-09-01 found 542 active, non-deleted opportunities: 63 won and 59 lost. Transition history existed for 234, linked activity history for 375, measurable first-response evidence for 91, structured dispositions for 27, and a recorded loss reason for 13. This incompleteness is why coverage is first-class and low-confidence metrics cannot become confident recommendations.

Production MCP remained active on v2 with twenty grantable scopes. No v3-or-later client or grant selected the Phase 5 capability, and production had no Phase 5 migration ledger entry. Those facts were read-only design evidence, not release proof.

## Verification and release boundary

The SHA-256-pinned PostgreSQL 17.11 harness creates a uniquely named disposable database, applies the candidate twice, and drops the database after proof. It verifies exact empty search paths and ACLs; tenant, client, grant-revision, scope-ceiling, manifest, exposure, permission-snapshot, revoked-grant, `pipeline.view`, and `email.view` denial; malformed-duration rejection; source-revision triggers; cohort and metric fixture facts; fixed bounds; exact valid/ready/non-unique B-tree definitions and both index plans; migration replay; and rejection of a drifted same-named index. Focused contract, service, repository, manifest, exposure, dispatch, runtime, server, SQL, bearer, and principal-boundary tests pass. TypeScript and the complete Next.js production build pass. The broader repository suite retains unrelated baseline failures outside this vertical; no Phase 5 test fails.

The migration mirror has SHA-256 `88eb84718a015b7c5428fffafa087692b8890e8dc8fabd022d0069f6b09badab`, byte-identical to OPS-Web.

The candidate remains local on isolated worktrees. Production remains on read-only v2. No migration was applied, no branch was pushed, no deployment occurred, no client or grant was created, and v7 was not activated. Shipping requires separately approved push/deployment and migration gates; exposure activation and external-host acceptance are later, separately approved gates.

There is no new subscription, scheduler, model call, or provider cost. If released later, runtime cost is ordinary existing Vercel request handling plus one bounded PostgreSQL read. The two partial indexes consume ordinary existing Supabase storage and add maintenance to qualifying source writes; exact byte cost depends on live qualifying rows and must be measured during an approved rollout.

## Production release update — 2026-09-02

The schema and application are production-released in OPS-Web `a763f1a0`, with production ledger `20260902194703_agent_sales_truth_read`. The live function remains service-role-only, and v7 has zero clients and zero grants. Active production exposure remains read-only v2; this vertical is deployed but dormant, not host-accepted or customer-live. The release record in `specs/2026-09-02-ops-mcp-phases-3-7-production-release.md` supersedes the earlier local-only release boundary.
