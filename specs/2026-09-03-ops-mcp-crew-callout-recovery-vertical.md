# OPS MCP Crew Call-Out Recovery Vertical

- **Designed and built:** 2026-09-03
- **Status:** Production database released; web main pushed; exact Vercel deployment binding pending; dormant, not activated
- **OPS-Web base:** `dcfa2d64e68860d31798303ed0ce30f7dc5acfd1`
- **OPS-Web implementation:** `464a8cbf42b515ff4845852ab4f566366874ce14`
- **OPS-Web pushed main:** `1ea480b0e38d3a1b920395cbe4c91309901659b6`
- **Bible base:** `a87480ff869dd742182b655cdf57809532a347ec`
- **Production migration:** `20260903220000_agent_crew_callout_recovery_preview`
- **Production ledger:** `20260904033119_agent_crew_callout_recovery_preview`
- **Migration artifact:** 66,665 bytes; SHA-256 `0d9e7b34baf465e9c62deab84f41d36de0de11e85e29d065da3dd368ecfbe4bc`

## Purpose

The tenth Invisible Office vertical handles the golden task:

> Mike called out tomorrow. Cover his jobs and tell the crew and clients.

`prepare_crew_callout_recovery` returns one exact, evidence-bounded recovery proposal and deterministic exact-recipient internal/client draft previews. This is preparation only. It changes no assignment, task, site visit, calendar event, OPS/provider draft, message, or delivery state, persists no preview body, and sends nothing. No commit, apply, assign, reschedule, or send sibling exists.

## Immutable surface

- Result schema: `2026-09-03.v1`
- Policy: `crew-callout-recovery-policy:v1`
- Capability manifest: `2026-09-03.capability-manifest.v18`
- Dormant exposure: `2026-09-03.mcp-exposure.v12`
- Consent catalogue: `2026-09-03.mcp-consent-catalog.v7`
- Capability revision: `prepare_crew_callout_recovery:2026-09-03.v1`
- Input: exact `crew_member_name` plus canonical `target_date` in `YYYY-MM-DD`
- Operation: high-risk `prepare`
- Active production exposure: unchanged read-only v2

Manifest v18 re-mints v17 and adds only this capability. Exposure v12 is additive to v11 and does not change any existing grant. The immutable v7 consent labels disclose both inherited weather work and crew-recovery schedule/message preparation.

## Exact identity and affected work

The database resolves an active same-company crew member only from an exact normalized full-name match or a unique exact first/last-name match. No fuzzy, nickname, or inferred identity is accepted. Zero or multiple matches return a non-retryable identity error before schedule facts cross the boundary.

The company timezone turns the requested date into one exact civil window. Affected work includes every authorized active project task and booked, non-cancelled site visit assigned to that member and overlapping that window. Each item carries its project/status version, schedule version, exact timing and coverage interval, all current assignees, lock/recurrence/pairing/dependency facts, current recipient lineage, safe future options, and source hash.

## Candidate evidence and qualification boundary

Every active same-company member other than the called-out person is evaluated from current OPS facts:

- current role membership;
- completed history for an affected task's exact task type;
- project continuity from existing assignments;
- company working hours;
- approved or neutral time off; and
- overlapping project tasks, booked site visits, and personal calendar events.

A task replacement is proven only when the candidate has at least one role overlapping the unavailable member and completed history for that exact task type. A site visit requires overlapping role evidence and reports `no_requirement_recorded`. Same-task completion is experience, not licensure. OPS has no authoritative crew licence/certificate source in the operational schema, so the response declares `licence_or_certificate_source: not_available` and cannot claim certification.

## Deterministic recovery policy

The exact bounded search first maximizes same-day covered work. Among equally complete plans it minimizes distinct replacement people, then assignment changes, then prefers project continuity, higher same-task history, less existing committed time, and stable member/item identity order. One candidate can cover non-overlapping items but can never be double-booked across overlapping recovery intervals.

Existing crew remain assigned; only the called-out member is removed. When another existing assignee already provides proven coverage, the proposal retains that person without adding a new crew member. A proposed assignment can never become empty.

Work without same-day coverage uses the earliest source-proven reschedule option. Future options are emitted only for unlocked, non-recurring, unpaired, dependency-free work, preserving duration and crew, on an allowed company workday, with no time off or task/site-visit/personal-event collision for any retained assignee. Work with neither proven cover nor a safe option remains explicitly uncovered.

## Draft truth and recipient boundary

Internal email previews are emitted only for selected replacement members with a current normalized email. Client previews are emitted only for rescheduled work with one exact current client or primary sub-client, non-merged parent lineage, valid normalized address, no global suppression, unique company ownership, and current view authority. Missing evidence becomes `exact_recipient_unavailable`; unresolved work becomes `recovery_plan_unresolved`.

Every draft states that it is a proposal and that nothing has changed yet. No raw business text is treated as an instruction; names, roles, projects, and work titles remain marked untrusted data and the shared MCP transport serializes the result through the prompt-safety boundary.

## Authority and replay

The exact OAuth grant must contain:

- `ops.communications.prepare`
- `ops.company.read`
- `ops.customer_contacts.read`
- `ops.customers.read`
- `ops.jobs.read`
- `ops.schedule.prepare`
- `ops.schedule.read`
- `ops.site_visits.read`
- `ops.tasks.read`
- `ops.team.read`

The current actor must have company-wide `calendar.edit`, `calendar.view`, `clients.view`, `inbox.send`, `inbox.view`, `projects.edit`, `projects.view`, `tasks.assign`, `tasks.edit`, `tasks.view`, and `team.view`. The repository supplies the full server-owned permission registry used to mint the actor revision. PostgreSQL independently recomputes authority and verifies the exact v18/v12/v7 client, grant, revision, ceiling, serialized scope, accepted labels, capability, and permission snapshot before reading.

The application authorizes the initial actor and re-resolves authority immediately before the source read. After deterministic calculation and result bounding, it re-resolves authority again. A final service-role-only assertion rebuilds the same snapshot at the original observation instant and requires the exact source revision. Any intervening crew, role, history, project, task, visit, availability, recipient, authority, grant, label, manifest, or exposure change fails closed.

The public read and assertion RPCs are stable `SECURITY DEFINER` functions with empty search paths. Execution is revoked from `public`, `anon`, and `authenticated` and granted only to `service_role`. Private helpers have no app-role execution grant. All relations and built-ins are explicitly qualified.

## Bounds and hashing

The fixed source limits are 25 affected items, 250 candidates, 500 relevant schedule sources, 50 assignees per item, 20 roles per candidate, 250 project-continuity identities per candidate, 500 commitments per candidate/day, 14 future days, 100,000 search nodes, a 2,000,000-byte source snapshot, and a 1,500,000-character result. Reached sentinels fail closed; no truncated population is presented as complete.

Every context, member, role, affected item, recipient, reschedule option, completion-history group, availability day, and commitment carries a SHA-256 source hash. The canonical source revision covers the whole snapshot. Proposal, draft, preview, and receipt hashes exclude request transport identity where needed, so unchanged evidence produces comparable output while current authority and source replay remain mandatory.

## Truthful result

The result status is `ready`, `partial`, or `no_affected_work`. It keeps source facts, qualification limits, candidate assessments, replacements, reschedules, uncovered work, drafts, blockers, and future-confirmation requirements separate. The effect envelope is always zero assignment, task, site-visit, calendar, OPS/provider-draft, message, and delivery writes.

Any future mutation requires a separately implemented guarded commit contract that receives the exact preview hash, reauthorizes the current actor, replays the exact source, checks every row version, and captures explicit change-and-recipient confirmation. That capability does not exist in this release.

## Verification evidence

The focused application suite covers strict input, deterministic search, non-overlap, minimal replacement count, role/history limits, work hours, time off, schedule conflicts, reschedule fallback, uncovered work, exact-recipient drafts, prompt safety, effect truth, manifest/exposure/consent pinning, grant dispatch, repository cancellation/error transport, double reauthorization, final source replay, and SQL function/ACL shape.

The exact migration compiled successfully against the live production schema inside a rolled-back transaction. A safe aggregate probe built a current production-shaped source snapshot without returning business details or retaining any database change.

Production release evidence captured 2026-09-04:

- The byte-exact migration is applied under ledger `20260904033119_agent_crew_callout_recovery_preview`.
- The migration's built-in catalog assertion passes. Both public functions are stable `SECURITY DEFINER` with empty search paths and only `service_role` non-owner execution. Private helpers have no non-owner execution grant.
- Consent v7 returns the exact crew-recovery communication and weather/crew scheduling labels; established v1 read labels remain unchanged.
- v12 has zero OAuth clients and zero grants. No activation or authenticated business-data canary was performed.
- Pre/post business controls remain identical: 212 active team members, 155 active project tasks, 3 booked site visits, and 3 current calendar-user-event rows. The migration contains no business-data DML.
- Fresh security and performance advisor scans contain no Phase 10 function, table, or index finding. Project-wide pre-existing advisor findings remain outside this vertical.
- The focused changed-vertical suite passes all 93 tests. The production Next.js build succeeds and emits all 371 routes.
- The broad suite records 16,755 passing, 15 failing, and 22 skipped tests across 1,658 files. Every failing file is byte-identical to the then-current `origin/main`; failures are existing MCP loopback-sandbox, timezone, registry, template-sync, and queue-order baselines rather than this vertical.
- GitHub Actions run `33831854081` fails only the pre-existing delivery-source normalization SQL contract in an unchanged file; no Phase 10 test fails.
- `https://app.opsapp.co/.well-known/oauth-authorization-server` returns 200 and exactly the established 20 read scopes. Unauthenticated `POST /api/mcp` returns 401 and the same read-only scope challenge.
- GitHub has no Vercel commit status or deployment object for `1ea480b0e38d3a1b920395cbe4c91309901659b6`. The public HTTP proof establishes current active-v2 behavior but cannot bind the running Vercel build to that source commit. Private Vercel dashboard access was not authorized, so application deployment is not claimed.

## Cost boundary

This vertical adds no subscription, paid provider, model request, external API call, scheduled job, table, index, durable preview, or fixed vendor cost. If separately activated later, a call uses the existing Vercel MCP execution path and bounded Supabase reads. No new paid service is required.

## Activation boundary

This release is dormant. It does not create or edit an OAuth client or grant, mint v7 consent, perform an authenticated business-data canary, change `ACTIVE_MCP_EXPOSURE_REVISION`, or prove external-host acceptance. Those remain separate Jackson-approved activation gates. Public OAuth metadata and unauthenticated MCP behavior must remain on the established read-only v2 surface after release.
