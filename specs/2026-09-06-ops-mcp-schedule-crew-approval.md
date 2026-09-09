# OPS MCP approved schedule and crew changes — Phase 14

**Status:** production migrations approved, applied and independently verified on 2026-09-07. The web release is READY on the production domain, verified at 06:07 UTC. Candidate capability manifest v22 / exposure v16 / consent v11 remain dormant; consent v11 is deliberately absent. Active v20 / v14 / v9 and Phase 13's dormant v21 / v15 are preserved. No customer task changes, real proposal/approval canary, OAuth changes, sending, provider-calendar writes or routine activation are authorized by this implementation.

## Exact operation

`prepare_schedule_change` accepts 1–25 explicitly enumerated existing task occurrences. Each supplies `task_id`, full-precision `expected_updated_at`, `expected_schedule_version`, destination company civil date, and an explicit unique crew set. A reason and idempotency key complete the strict request. Company and actor come from trusted authority, never the request. There is no saved target query, general-purpose patch, date inference from viewer timezone, or external MCP commit sibling.

A task is the scheduled visit. Its `task_scopes` are included work on that same visit, displayed and sealed in the preview; changing schedule or crew never splits or changes those scopes. Tasks must be active, unlocked, already scheduled and finite. Recurrence, incoming/outgoing task pairs, split scopes, unresolved project dependencies or dependency overrides are rejected. The operation preserves duration and all unapproved task fields. Task completion, new tasks, project dates, bookings, recurrence, money, customer correspondence and scope composition are outside the contract.

Availability includes current active company members, recorded working hours, noncancelled operational sources as specifically defined below, and recorded work experience for newly assigned crew. Retained crew need no invented credential. New crew need completed same-type or completed same-scope work. No licence/certification or external-calendar availability is asserted.

## Civil dates and timezone gate

All-day task timestamps are UTC **date carriers**; their UTC clock portion is retained, not required to be midnight. The UTC start/end dates are inclusive civil labels. Company-local midnight at the first date and midnight after the final date are resolved independently. A civil day is never assumed to be 24 elapsed hours. The bounded operation supports 1–14 all-day civil days and dates no more than 366 days ahead, respecting recorded weekend/work-hour policy.

Existing timed task readers disagree: task detail consumes the raw instant, while the Phase 2 availability reader uses the UTC date part plus local `start_time`/`end_time`. This vertical accepts timed sources only when both interpretations agree, local times are unique, the occurrence stays within one local day and working hours, and moving it preserves both wall clocks and elapsed duration. The protective guard on subsequent ordinary task writes checks **both** existing interpretations separately, so a nonconflicting timestamp across UTC midnight is not globally rejected.

The server resolves local boundaries against its ICU timezone rules and compares every database probe before preparing a proposal. A known Vancouver November 2026 rule assertion prevents two stale runtimes from silently agreeing. The database seals these conversions, including rescheduled reminder times, and recomputes them at approval. A mismatch produces no task write.

**Unresolved hosted operation:** live Supabase PostgreSQL 17.6 still returned Vancouver `2026-11-02 00:00` as `08:00Z` on 2026-09-06; current B.C. rules require `07:00Z`. Node v24.19.0's bundled tzdata2026b and local PostgreSQL resolve `07:00Z`. This software guard does not update hosted tzdata. Supabase's documented upgrade may take the project offline and must not be initiated without exact operational approval and confirmation of the target tzdata. IANA's current release is 2026c. Sources: [B.C. announcement](https://news.gov.bc.ca/releases/2026AG0013-000209), [IANA release notes](https://data.iana.org/time-zones/tzdb-2026c/NEWS), [Supabase upgrade operations](https://supabase.com/docs/guides/platform/upgrading).

## Authorization, sealing and approval

The domain service is host-neutral. Human MCP hosts and durable agents use the same trusted `OpsAgentDomainService` facade and actor-bound repository. Required all-scope permissions are `agent.review`, `calendar.edit`, `calendar.view`, `projects.view`, `tasks.assign`, `tasks.edit`, `tasks.view`, `team.view`. Required scopes are `ops.jobs.read`, `ops.schedule.prepare`, `ops.schedule.read`, `ops.site_visits.read`, `ops.tasks.read`, `ops.team.read`.

Private authority checks require the exact current actor/company/client/grant, accepted consent labels and revisions, registered permission snapshot and candidate capability identity. Existing subset grant semantics are preserved. Revocation, client disablement or permission loss blocks preparation and receipt replay. Another administrator cannot approve or read the named actor's proposal through the action queue. Application roles have no direct access to the private ledger or write tokens; browser roles cannot execute the public mutation RPCs.

Preparation writes only a private sealed proposal, a pending actor-owned `approve_schedule_change` action and a persistent review notification. The action expires after 30 minutes. Whole-preview hashes bind task identities, before/after schedules and crew, scopes, source evidence, timezone proof, effects and authority. Same-key/different-input requests fail. Cancellation before commit changes no task; correction after commit requires a fresh proposal and approval.

The approval desk displays company timezone, current/proposed dates and crew, all included scopes/notes, confirmation clearing, project crew changes, internal notification/reminder effects, capacity protection and the explicit external-evidence limits. It sends only `change_set_id` and `preview_sha256`. Bulk, row-shortcut and autonomous execution are disabled. The service retries an uncertain RPC using the same deterministic key, then independently verifies the executed action and receipt.

## Concurrency and competing work

Source building takes the existing company assignment advisory lock, a company capacity advisory lock and NOWAIT table locks. These fence insertion phantoms in availability/authority sources. It prelocks exact affected project, task and reminder rows with NOWAIT to avoid deadlocking behind a preexisting row-only writer. These are deliberately short bounded transactions; table locks are global to their tables, so competing company writes can receive a retryable busy result. Bounds: 2,000 tasks/visits/calendar events/current holds, 5,000 scopes, 1,000 company members/types, 100 affected reminders and 25 selected tasks. Evidence is never silently truncated.

Conflicts include active assigned tasks; scheduled or in-progress booked visits, with empty assignees treated as company-wide; personal events with status `none`; time off with `approved` or `none`; and unexpired `held` or `verified` guest intents. All-day personal/time-off endpoints use the existing availability reader's inclusive company-local dates. Proposed tasks are checked against one another. Malformed or ambiguous relevant evidence fails closed.

The transaction locks the task automation outbox and approved-email intent table. It refuses outstanding noninternal automatic task work and selected-task email intents whose provider ownership is not settled (`reconciled` or `provider_rejected`). A request already claimed as `sending` or `delivery_unknown` cannot be revoked by changing a task version. After approval commits, existing unclaimed schedule-email work still has to pass its established current-task/version guard.

A private capacity fence protects each approved task version from newly introduced overlapping staff bookings, guest holds and other task writes. Actual booking routes hit the table guard. Protection follows current company timezone and ends when the task's schedule version changes, it becomes inactive/deleted, or it is hard-deleted. Superseded fence rows are removed on later commits; immutable proposal/receipt evidence remains in the ledger. The guards require READ COMMITTED, because fixed transaction snapshots cannot see newly committed fences. With no current fence, they do not acquire the extra company advisory lock. Existing conflicting pairs are not retroactively rewritten. All selected write tokens are installed before the first update, permitting an atomic two-task swap.

## Canonical writes and precise effects

Commit invokes `private.update_task_with_event_for_actor`, never direct task replacement. It preserves native schedule-version increments, history, project crew aggregation and reminders. A private transaction/backend/task token binds the full original row and complete permitted resulting row. The canonical producer consumes it exactly once after internal assignment/schedule events and before cascade/full-auto/customer dispatch. Caller-controlled settings cannot mint this authority. Missing consumption, unexpected trigger changes or mismatched full-row/project/reminder readback rolls back all task and effect writes, including the receipt.

Two existing scheduling defects are repaired through exact live-definition fingerprints:

- `20260906234703_task_mutation_time_validation.sql`: casts the native `time` columns to text for existing format validation. The actual canonical RPC previously failed with `time without time zone !~ text`.
- `20260906235016_agent_schedule_crew_approval.sql`: updates the existing reminder rescheduler to interpret all-day UTC civil labels correctly before applying company-local reminder time. It performs no bulk timestamp rewrite. Existing timed behavior is retained.

The sealed effects report task count, cleared confirmations, complete project crew rollups, reminder rescheduling, and **in-app plus OneSignal crew push notifications subject to preferences**. Push delivery is not claimed. Automatic schedule cascades, automatic confirmation, new customer messages and external calendar push intents are zero. Calendar subscription consumers may later fetch changed OPS records; their synchronization is unknown. Customer notification is a separately approved messaging operation.

The committed receipt has one durable confirmation ID, exact approval hash, full independent schedule readback and its hash, effect summary, commit timestamp, receipt hash and replay flag. Reauthorization precedes replay, which returns the same receipt without duplicate history or task writes.

## Verification and release boundaries

The disposable PostgreSQL suite uses captured live canonical functions and representative real task/reminder/project/scope triggers. It reproduces the original time validation failure, then verifies successful updates, crew reassignment, scope preservation, Vancouver reminder dates, multi-task commits/swaps, authority/replay rejection, tampered/expired/cancelled previews, source drift, conflict semantics, provider ownership, token corruption rollback and private ACLs. Independent sessions exercise real `reschedule_site_visit` in both race orders, duplicate approvals and a preexisting row-only writer. This is bounded local database proof, not a clone of every production trigger or a provider/customer canary.

Application tests cover strict input/output substitution rejection, microsecond precision, civil-time folds/gaps and 23/25-hour days, runtime dispatch, named-actor approval, UI effects and previous customer-update/message/delivery-source replay paths. The production component was visually inspected at desktop and 390px phone widths using fictional fixtures; phone content width equalled viewport width. The design audit found token-based typography, spacing, borders and colors. Typecheck and a full Next production build pass with inert placeholder build credentials. Existing build warnings are recorded, not represented as new Phase 14 failures.

Exact test counts, source fingerprints and release hashes are recorded in the web `docs/artifacts/phase14/README.md`. This is not Phase 12 changed-update acceptance, Phase 13 sending acceptance, or Phase 14 customer-live acceptance. No new subscription or recurring worker is introduced; existing Supabase/Vercel usage applies. Hosted maintenance costs/downtime require verification before a specific operation is approved.

## Approved code and SQL release record

Web implementation commit: `402b03dd1b3651a8cb30b31d8b775836482def24` (preceded by canonical time repair `c1da9fb26`). Verification: 127 application/regression tests, 51 PostgreSQL assertions and four real concurrency scenarios passed. Jackson subsequently approved the two migrations and web/Bible main pushes. Production recorded `20260907055324_task_mutation_time_validation` and `20260907055344_agent_schedule_crew_approval`; the archived files use those actual ledger versions and retain the exact approved SQL bytes. The web release includes fresh upstream social-editorial work and is pushed at `37da7dee3f3fb379be5939ecc16bf2d62bd3e2d4`. Hosted timezone maintenance remains a separate unresolved operational gate.

## Production SQL readback — 2026-09-07 05:54 UTC

Both stored migration statements match the approved SHA-256 values: `6b2455ec97e4aa06a4e051e37b00f8691405e30a162de7ac8e460d81fc08e158` and `477d0d54baf5f6d8566a763c30cae9dc2c2d091b5d754c71dbff2c27a49d5520`. The canonical native-time casts and all-day reminder correction are installed. Four private relations have force-RLS and no direct service-role SELECT/INSERT access. Public prepare/inspect/commit/reject/filter entry points are postgres-owned, SECURITY DEFINER, empty-search-path and service-role-only. The installed effect policy matches the current production graph. Change sets, capacity fences, write tokens, Phase 14 approval actions, v16 clients and v16 grants are all zero. Vancouver November midnight remains 08:00Z; this release has not updated hosted timezone data.

## Production deployment readback — 2026-09-07 06:07 UTC

Vercel deployment `dpl_3nvLuUUfqSRoXsmGegd9DS3JHmYY` reached READY at 06:06:34 UTC for exact web commit `37da7dee3f3fb379be5939ecc16bf2d62bd3e2d4`. An independent lookup of `app.opsapp.co` resolves to that deployment and commit. The merged release passed all 127 focused application/regression tests and a full local production build; Vercel also completed its production build and generated all 465 pages.

The public `/.well-known/oauth-protected-resource/api/mcp` JSON is exactly equal to its pre-release snapshot: 21 scopes and no `ops.schedule.prepare`. An unauthenticated `tools/list` POST to `/api/mcp` returns HTTP 401 with `{"error":"unauthorized"}`. The deployment-scoped error/fatal log scan from 06:06:00 through 06:07:05 UTC returned no matching logs. This short initial observation is not sustained runtime health or signed-in customer canary proof. No Phase 14 activation or real business mutation was performed.
