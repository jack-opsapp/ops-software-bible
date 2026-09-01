# OPS MCP Phase 3 — Hiring What-If Vertical

**Status:** Locally implemented and verified on 2026-09-01. Dormant release candidate only. Not pushed, deployed, migrated, activated, granted, or customer-live.

**Approved source:** `specs/2026-08-30-ops-mcp-vision-handoff.md`

**OPS-Web source:** `cd72a74f5ff26d0ff85ffad3778a8851aecc5ea1`

**Source migration:** `ops-web/supabase/migrations/20260901045000_agent_hiring_what_if_read.sql`

**Bible mirror:** `supabase/migrations/20260901045000_agent_hiring_what_if_read.sql`

## Product answer

The third Invisible Office vertical answers one bounded question:

> If I hire a second member in this current role at this all-in hourly cost, when does that standard week stop costing me money?

The host supplies only an exact current role name and an all-in employer cost per paid hour. OPS owns the tenant, actor, grant, current permissions, company currency, timezone, workweek, observation window, source populations, formula, confidence rules, and answer. The tool returns a low/base/high observed sensitivity with an explicit break-even or no-break-even result. It refuses a numeric claim when the available OPS record cannot support one.

This is a pure analytical read. It creates no scenario, snapshot, action, notification, routine, message, ledger row, or other durable state. It makes no model/provider call and has no UI.

## Immutable control-plane identity

- Capability: `analyze_hiring_break_even`
- Input schema: `2026-08-31.v1`
- Metric definition: `hiring-break-even:2026-08-31.v1`
- Capability manifest: `2026-08-31.capability-manifest.v11`
- Dormant exposure: `2026-08-31.mcp-exposure.v5`
- Active production exposure remains `2026-08-29.mcp-exposure.v2`.
- V5 contains exactly this one tool. V1 through v4 remain immutable.

Required OAuth scopes are `ops.company.read`, `ops.expenses.read`, `ops.financial_documents.read`, `ops.financials.read`, `ops.jobs.read`, `ops.payments.read`, `ops.schedule.read`, `ops.site_visits.read`, `ops.tasks.read`, and `ops.team.read`.

Every current granular permission must be company-wide: `calendar.view`, `expenses.view`, `invoices.view`, `projects.view`, `projects.view_financials`, `reports.view`, `settings.company`, `tasks.view`, and `team.view`. There is no prepare scope, write permission, relation-scoped fallback, role-name authorization, or caller-selectable authority.

## Input semantics and fixed bounds

The public input is strict and contains exactly:

- `role`: trimmed, non-empty, no control characters, maximum 80 characters;
- `hourly_cost`: positive finite all-in employer cost in the company currency, maximum 100,000 and at most four decimal places at the host boundary. After OPS resolves the company currency, the value must be exactly representable in that currency's canonical minor unit; OPS rejects incompatible precision instead of rounding it (for example, fractional JPY or a third decimal in CAD).

The server does not add payroll burden, benefits, hiring fees, overtime, or a wage multiplier. The source read is fixed at:

- 13 complete company-local ISO weeks immediately before the current local week;
- at most 25 active comparable role members;
- 5,000 schedule source rows, with the 5,001st row proving overflow;
- 5,000 payment rows and 5,000 expense allocations, with the 5,001st row proving overflow;
- 250 role-linked projects, with the 251st proving overflow;
- 100 unique supporting records;
- at most 500,000 expanded schedule member-days and 100 assignments per schedule source row.

Any exceeded source bound returns insufficient data. The query never silently truncates a numeric answer.

The response clock is also server-owned and self-validating. `observed_at` must exactly equal the instant requested by the service, `business_date` must be that instant's date in the returned IANA timezone, and the window end must be the ISO-week Monday for that business date. The start and next-week dates are derived from that same anchor. A shifted but internally spaced window is rejected.

## Server-owned metric definition

### Comparison population

Role resolution is exact after trimming and case folding against canonical `roles`, including company roles and shared canonical roles. Membership comes only from active, non-deleted company `users` joined through `user_roles`. Legacy `users.role`, fuzzy matching, and company-wide fallback are forbidden. Missing, ambiguous, empty, or over-bound populations return insufficient data.

### Capacity and productive work

Paid capacity is the selected members' company default work window on configured working days. Approved/current time-off events remove only the member identified by the time-off event's canonical `user_id`; team-member arrays are used only for personal calendar events and cannot spread one person's time off to another member. Productive work is the union of non-cancelled project tasks and booked, non-cancelled site visits assigned to active members. Every interval is clipped to the company work window and overlapping intervals are merged, so utilization cannot double count time. Personal calendar activity is never productive work.

OPS treats these rows as scheduled operational evidence, not time-clock proof. That assumption is always returned with the answer.

### Revenue, direct cost, and role attribution

Revenue is non-void payment cash received inside the window on project-linked, non-deleted invoices. Direct cost is the company-currency amount of project allocations on non-deleted expenses dated inside the window with status `submitted`, `approved`, or `reimbursed`. A null/unsupported currency or an allocation with neither an amount nor a percentage is invalid evidence and forces an insufficient result; it is never silently omitted. Draft/rejected expenses, foreign-currency allocations, unallocated expenses, invoice face value, existing labour, payroll burden, and overhead do not enter cash contribution.

Project cash contribution equals collected payment cash minus allocated direct expense. Each project's contribution is first assigned to the selected role by its share of merged scheduled project minutes among all active assigned members, then distributed across weeks by that role's scheduled minutes on the project. A project counts as financially observed only when it has positive collected payment cash.

### Scenario calculation

Base observed utilization and contribution per productive hour use the complete-window aggregates. Low/base/high sensitivity is the 25th/50th/75th percentile of complete weekly cash contribution per paid-capacity hour.

- Standard weekly hire cost = company standard weekly paid hours × submitted hourly cost.
- Required productive hours = weekly hire cost ÷ observed cash contribution per productive hour.
- Required revenue = weekly hire cost ÷ observed cash contribution margin.
- Required utilization = hourly cost ÷ observed cash contribution per productive hour.

A sensitivity band reaches break-even only when its observed contribution yield per paid-capacity hour covers the submitted hourly cost. Its date is the first configured working day in the next standard workweek when cumulative modeled contribution covers that entire week's hire cost. OPS does not invent demand, a ramp curve, overtime, or a hiring fee. If the observed yield cannot cover one standard week, the date is null and the verdict says it does not break even.

### Completeness and confidence

The result is insufficient when any source explicitly reports incomplete coverage, when fewer than eight weeks have positive capacity, fewer than three role-linked projects have positive collected revenue, total collected revenue is non-positive, cash contribution or productive time is non-positive, schedule/currency evidence is invalid, or a source bound is exceeded.

A ready answer receives:

- high confidence at 13 usable weeks, at least eight financially observed role projects, and zero omissions;
- medium confidence at at least ten usable weeks and five financially observed projects;
- low confidence at the accepted minimum history.

An insufficient answer has zero confidence and contains no scenario numbers or break-even date.

## Database and authority boundary

The migration creates no table, policy, trigger, queue, cron registration, or durable analytical record. It defines:

1. owner-only `private.assert_agent_hiring_what_if_authority(...)`; and
2. service-role-only `public.read_agent_hiring_what_if_as_system(...)`; and
3. one partial covering index, `idx_site_visits_agent_hiring_history_v1`, for the completed/non-cancelled booked-visit history range used by this read.

It also corrects the existing canonical currency helper, without changing its signature, so current two-decimal ISO 4217 currencies CHF, XCG, and ZWG are accepted consistently by the helper, its nullable wrapper, and the shared money-to-minor-units converter. Unsupported fund, metal, test, and reserved units continue to fail closed.

The application validates the strict input and initial actor policy, re-resolves current MCP authority immediately before reading, and authorizes the current snapshot again. The database then independently requires service-role execution and rechecks the exact actor, company, OAuth grant/client, grant revision, scope ceiling, permission snapshot revision, manifest v11, and exposure v5 before touching business data. Both functions are security-definer functions with an empty pinned search path. The public RPC revokes execution from `public`, `anon`, and `authenticated` and grants only `service_role`; the private authority helper has no app-role execution grant.

The output is parsed through the strict source contract before calculation, including reconstruction of its local business date and ISO-week window. The repository independently requires the returned observation instant to equal the requested instant. The calculated answer is parsed again through the result contract, bounded to 120,000 characters, marked as untrusted business data, and returned through the existing MCP prompt-safety and audit boundary.

## Source/index audit

One new index is required. The existing site-visit availability index excludes completed visits, while the general booked-order index is ordered by `booked_at`; neither bounds this vertical's company + `scheduled_at` scan over booked, non-cancelled historical visits. The query now has both scheduled-time bounds—the 13-week window plus a one-day maximum-duration overlap allowance—and `idx_site_visits_agent_hiring_history_v1` keys `(company_id, scheduled_at, id)`, includes the projected visit fields, and is partial on `deleted_at IS NULL`, `booked_at IS NOT NULL`, and `status <> 'cancelled'`. Migration postflight verifies the exact B-tree keys, included fields, ordering options, readiness, uniqueness, and predicate, so `CREATE INDEX IF NOT EXISTS` cannot conceal a same-named drifted definition. The sealed PostgreSQL plan proof forces index-eligible planning and verifies both scheduled-time comparisons appear in the index condition. A separate negative database case installs a wrong same-named index and proves the migration aborts. All other access paths reuse current indexes. Exact role-name resolution remains a bounded scan of the small company/shared role catalogue.

## Verification evidence

- Focused contract, registry, repository, service, SQL, authority, exposure, and runtime proof: 63/63 unique tests passed, including both live PostgreSQL cases.
- Complete sandbox-runnable agent-control-plane suite with only the loopback-dependent acceptance file excluded: 2,940/2,940 passed across 211 files. The comparison run that included that synthetic OAuth acceptance file passed 2,930 tests and reproduced its inherited 10 `loopback_bind` failures because this sandbox cannot open its callback listener; the same baseline existed before this vertical.
- Three broad-run timeout/boundary checks passed in isolation under their declared 20-second budget.
- TypeScript `tsc --noEmit` passed with an 8 GiB Node heap.
- Touched TypeScript lint passed with zero findings; Prettier completed; `git diff --check` passed.
- The complete Next.js production build and type-validity pass succeeded. Its warnings are inherited media/edge/metadata warnings outside this vertical.
- A committed, SHA-256-pinned PostgreSQL 17 runner creates uniquely named disposable databases, applies the complete candidate migration, executes the golden/failure fixtures, and always drops each database. It proves exact function volatility/search-path/ACLs, tenant and revoked-grant denial, fixed bounds, 13 weeks, two comparable members, one-member-only time-off removal (`4,320` minutes in that week; `61,920` total capacity), overlap merging (`1,500` productive minutes), three financial projects, `300,000` CAD minor units of attributed collected cash, inclusion of a completed historical site visit, both time bounds in the candidate index condition, exact index-definition postflight, and rejection of a wrong same-named index. Null expense currency and null allocation amount/percentage independently force `invalid_currency_expense` and an insufficient result.
- TypeScript and PostgreSQL proof covers currency/minor-unit coupling and exact hourly-cost precision for zero-, two-, and three-decimal currencies, including JPY, CAD, CHF, KWD, XCG, and ZWG; no incompatible value is rounded. Contract and repository proof also rejects mismatched local dates, shifted ISO-week windows, and a response returned for any instant other than the requested observation clock.
- Static SQL tests prove transaction framing, exact v11/v5 authority, fixed bounds/populations, pinned search paths, service-role-only execution, the exact single source index, and absence of durable business-state or mutation vocabulary.
- The Bible migration mirror is byte-identical to OPS-Web.
- A read-only production advisor snapshot at 2026-09-01 09:28 UTC recorded the existing unapplied baseline: 329 security notices (92 info, 237 warn) and 920 performance notices (733 info, 187 warn). None can refer to this candidate because neither candidate function exists in production; the migration was not applied.

No Canpro Deck and Rail record and no PERSONA TEST POOL fixture was used.

## Release, activation, and cost boundary

The candidate remains local on isolated worktrees. The migration is not applied. V5 has no client or grant. Production remains on read-only v2; deployed dormant v3 day-closeout and v4 collections remain unchanged, with no new routine, activation, or authority. Shipping requires a separately authorized Web push/deployment and migration apply. Activation requires a later, separately approved v5 OAuth/client/grant and host-acceptance decision.

This vertical adds no paid service, model call, scheduler, or durable result record. If later deployed, the one partial site-visit index will consume ordinary existing Supabase database storage and add maintenance work to qualifying site-visit writes; its exact byte cost depends on live qualifying row count and must be measured during the separately approved rollout. Runtime cost is ordinary existing Vercel MCP request handling plus one bounded PostgreSQL analytical read per call. There is no new subscription or fixed vendor cost.
