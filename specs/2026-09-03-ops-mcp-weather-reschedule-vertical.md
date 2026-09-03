# OPS MCP Weather Reschedule Vertical

- **Designed and built:** 2026-09-03
- **Status:** Locally implemented and verified; unreleased, unapplied, dormant
- **Authoritative Web base:** `1cacc2df8b483689cc4f3cd183c5be981ad0c9f2`
- **Authoritative Bible base:** `6839b6f`
- **OPS-Web component commits:** `53ed2a08`, `3e212eae`, `315c6b41`, `a8ed67a1`, `d0f1b2bd`, `74fc4682`, `f27f57fa`, `a9c83ab5`, `5c8f99b0`
- **Candidate migration:** `ops-web/supabase/migrations/20260903123200_agent_weather_reschedule_preview.sql`

## Purpose

The ninth Invisible Office vertical handles the golden task:

> Rain Thursday. Slide the outdoor work, keep the indoor job, tell everyone.

`prepare_weather_reschedule` returns one exact weather-bound schedule proposal and deterministic recipient-bound email drafts. This is preparation only. It changes no project, task, calendar event, provider draft, message, or delivery state, persists no preview body, and sends nothing. No commit, apply, or send sibling exists.

## Immutable surface

- Result schema: `2026-09-03.v1`
- Policy: `rain-reschedule-policy:v1`
- Capability manifest: `2026-09-03.capability-manifest.v17`
- Dormant exposure: `2026-09-03.mcp-exposure.v11`
- Consent catalogue: `2026-09-03.mcp-consent-catalog.v6`
- Capability revision: `prepare_weather_reschedule:2026-09-03.v1`
- Input: exactly one canonical `target_date` in `YYYY-MM-DD`
- Operation: high-risk `prepare`
- Active production exposure: unchanged read-only v2

Manifest v17 re-mints v16 and adds only this capability. Exposure v11 is additive to v10. Its registered client ceiling adds `ops.communications.prepare` and `ops.schedule.prepare`; existing exposures and grants remain immutable and cannot widen silently.

## Server-owned schedule and weather rule

The request applies to active, non-deleted project tasks on one company-local date. Each source task must be one civil day with a valid interval and one same-company task type. Outdoor status comes only from `companies.schedule_settings.outdoor_task_type_ids`. Titles, notes, conditions text, and caller phrasing never classify work or change authority.

The first version rejects locked, recurring, paired, multi-day, or dependency-bearing target work. Outdoor work must have current same-company crew assignments. Stored UUIDs are canonicalized before collision comparison. Tasks for the same project move together to the first valid candidate date from the next day through `optimization_window_days`, capped at 14 days. The proposal preserves time, duration, task order, and crew. A candidate is rejected when the project or any assigned crew member already has overlapping active work, including a future assignment spanning multiple dates. Indoor work remains on its current date.

`rain-reschedule-policy:v1` classifies rain from numeric evidence only:

- rain-affected when precipitation probability is at least 60 percent or precipitation is at least 10 millimetres;
- clear only when both values are below those thresholds;
- exact source `open-meteo`;
- cache retrieval no more than 12 hours before the observation instant and never from the future; and
- complete project/day evidence for the target date and every candidate date.

Human-readable weather conditions cross the boundary only as marked untrusted external data. The MCP call never invokes Open-Meteo. Missing, stale, malformed, or incomplete cache evidence rejects the whole request; there is no partial proposal.

## Recipient rule and copy truth

Each project resolves exactly one contact. The explicit current `primary_sub_client_id` wins only when it belongs to the project's active, non-deleted, non-merged parent client; otherwise the active primary client is used. The parent-client revision is part of the recipient source identity. The email must be normalized, syntactically valid, not globally suppressed, and owned by exactly one active client or sub-client in the company. Shared addresses are ambiguous and fail closed.

One draft covers each exact project and recipient. Every target task appears in exactly one draft. The draft calls weather a forecast, moved dates proposals, indoor work unchanged, and says explicitly that nothing has changed yet. It is returned as text only; OPS and provider draft tables remain untouched.

## Authority and stale-source proof

The OAuth grant must contain all seven scopes:

- `ops.communications.prepare`
- `ops.company.read`
- `ops.customer_contacts.read`
- `ops.customers.read`
- `ops.jobs.read`
- `ops.schedule.prepare`
- `ops.schedule.read`

The current actor must have company-wide `calendar.edit`, `calendar.view`, `clients.view`, `inbox.send`, `inbox.view`, `projects.edit`, `projects.view`, `tasks.edit`, and `tasks.view`. The repository supplies the exact server-owned 103-key permission registry used to create the actor-context revision; PostgreSQL recomputes against that full registry before checking the nine capability permissions. The database also rechecks view/edit entity authority for every target task/project and view authority for every recipient and conflict exposed.

The application authorizes the initial actor, re-resolves authority before reading, and parses one strict source snapshot. After deterministic calculation and prompt-safe output bounding, it re-resolves authority again. A final service-role-only PostgreSQL assertion rebuilds the same snapshot using the original observation instant and requires the exact source revision. Any changed schedule, task/project version, setting, forecast, crew, recipient, suppression, grant, label, scope, permission, manifest, exposure, or entity authority fails closed before return.

The public read and assertion RPCs are stable `SECURITY DEFINER` functions with an empty search path. Execution is revoked from `public`, `anon`, and `authenticated` and granted only to `service_role`. Private helpers have no app-role execution grant. All relations are fully qualified.

## Bounds and determinism

The fixed source limits are 100 target tasks, 25 projects, 500 relevant conflicts, 100 outdoor task types, 50 assignees per task, and a 14-day optimization window. PostgreSQL reads one extra sentinel and rejects a reached task/project/conflict limit. The source and result ceilings are each 1,000,000 characters/bytes.

Every settings, task, recipient, forecast, and conflict source carries a SHA-256. One canonical source revision binds the entire read. TypeScript uses stable ID ordering, checked date arithmetic, complete project groups, exact interval overlap, and canonical serialization. Identical input and unchanged evidence therefore produce identical proposal, draft, and preview hashes independent of transport request id.

## Truthful result

The response keeps current facts, forecast evidence, proposal, and drafts separate. `ready` means the preview completed, not that anything changed. It explicitly reports zero project writes, task writes, calendar writes, provider-draft writes, message writes, and messages sent. Source-derived names and conditions are marked untrusted data and pass through the shared prompt-safety serializer.

## Verification evidence

The focused application suite passes 82 tests across strict contract calculation, exact copy, exposure/manifest/grant pinning, inherited dispatch compatibility, repository envelopes and cancellation, double reauthorization, source drift, ambiguity, output bounds, and SQL shape. The entire TypeScript project passes `tsc --noEmit` with the established 8 GB heap.

The SHA-256-pinned PostgreSQL 17 harness compiles Phases 7, 8, and 9 in order against a uniquely named disposable database. It runs the Phase 9 proof twice and verifies deterministic source replay, exact v17/v11/v6 authority, full-registry actor-revision parity, current typed settings/forecast/recipient/task facts, case-insensitive UUID collision identity, multi-day future conflict capture, final revision binding, missing-scope and truncated-registry rejection, changed-forecast rejection, shared-recipient rejection, parent-client drift and merge rejection, locked-task rejection, multi-day target rejection, missing task-type rejection, string-impostor settings rejection, service-role-only ACL/catalog shape, zero business mutation, transaction rollback, safe database naming, and isolated non-default-port cleanup.

## Cost boundary

This local build introduces no subscription, external provider request, model call, scheduled job, table, index, durable preview storage, or fixed vendor cost. If separately released and activated later, a call uses existing Vercel MCP execution plus two bounded Supabase reads. Forecast population remains the responsibility and cost profile of the existing OPS weather cache; this tool adds no Open-Meteo request.

## Release boundary

Phase 9 is committed only in isolated local OPS-Web and Bible worktrees. The migration is not applied. Nothing is pushed or deployed. No OAuth client is registered or edited, no v6 consent or grant is minted, no production canary or outside-host acceptance is run, and active exposure remains v2. The capability is not customer-live.

Push, production deployment, migration apply, migration archive mirroring, client registration, grant creation, authenticated canary, host acceptance, and any active-exposure change are separate Jackson-approved gates.
