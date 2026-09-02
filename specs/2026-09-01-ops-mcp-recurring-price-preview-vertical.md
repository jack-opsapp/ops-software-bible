# OPS MCP Recurring Service Price Preview Vertical

- **Designed:** 2026-09-01
- **Status:** Local release candidate; dormant and unapplied
- **Authoritative Web base:** `50bd43bcaee080de310eee9ad7d18325b37d0738`
- **Authoritative Bible base:** `c791ac1ce14ef2b19da8204b9a43520b2c58f42e`
- **Source migration:** `ops-web/supabase/migrations/20260902010000_agent_recurring_service_price_change.sql`

## Purpose

The seventh Invisible Office vertical handles golden task 14:

> Raise every selected recurring-service account by a validated percentage in a requested month, draft the notices, and flag evidence-backed churn risk.

`prepare_recurring_service_price_change` stops at a truthful, ephemeral preview package. It cannot send, approve, confirm, commit, persist preview or notice business content, change a price or contract, issue or edit an invoice, or alter service. The shared MCP transport still records ordinary audit and rate-limit metadata, never the preview body.

## Versioned contracts

- Result schema: `2026-09-01.v1`
- Capability manifest: `2026-09-01.capability-manifest.v15`
- Dormant exposure: `2026-09-01.mcp-exposure.v9`
- Price-preview consent catalogue: `2026-09-01.mcp-consent-catalog.v4`
- Tool: `prepare_recurring_service_price_change`
- Tool input: exactly `service_selector`, `increase_percent`, and `effective_month`
- Service-resolution ceiling: one exact match plus one ambiguity sentinel
- Account ceiling: 100 unique client/service identities; the database reads one extra identity to prove overflow
- Recurrence catalog ceiling: 10,000 rows plus one fail-closed sentinel
- Aggregate recurrence-classification work ceiling: 100,000 units shared across the initial and same-snapshot revalidation catalogs
- Recurrence-exception ceiling: 100 per account plus one overflow sentinel
- Provider-source ceiling: 1,000 per account plus one overflow sentinel; 20,000 UTF-8 bytes per source body
- Catalog construction threshold: 3,500,000 conservative UTF-8 bytes, or 10,001 target-month exception rows
- Serialized catalog and complete detail-wrapper ceiling: 4,000,000 UTF-8 bytes each
- Result ceiling: 4,000,000 characters
- Supporting-record ceiling: 3,000 exact references
- Exact decimal source ceiling: 64 characters
- Preview lifetime: 24 hours
- Correspondence normalization: `ops.correspondence.normalized-text.v2`

The percentage is a positive canonical decimal string no greater than 100 with at most four fractional digits and no fractional trailing zero. The effective month is canonical `YYYY-MM` from the current company-local month through 24 months ahead. The host cannot provide a tenant, actor, account list, recipient, price, currency, cadence, date, tax, notice rule, risk label, source record, or effect flag.

Manifest v15 re-mints v14 and adds only this high-risk preparation. Exposure v9 is additive to v8: `analyze_hiring_break_even`, `check_customer_reply`, `analyze_sales_truth`, `check_payroll_readiness`, and `prepare_recurring_service_price_change`. Active production exposure remains v2.

The additive bundle preserves real authority, not just discovery. Each inherited tool accepts only its historical manifest/exposure pair or v15/v9. On the v15/v9 route, the database additionally requires the exact 16-scope registered client ceiling and serialized scope, v4 consent revision, and exact accepted labels; cross-paired revisions, client drift, historical consent, or label drift fail before the inherited domain read. Historical routes retain their existing scope and consent behavior.

## Authoritative data and eligibility

Private `agent_recurring_service_price_policies` is the fail-closed contractual bridge. One active row binds a company, client, recurring task type, exact accepted price-source line item and hash, the exact authorized percentage and effective month, notice contact, notice days, adjustment permission, optional grandfathering, and policy-source reference/hash. No row means `terms_unavailable`, never permission.

An account is eligible only when all of these are current and unambiguous:

- recurrence series that overlaps the requested month or has an exact reschedule into it, plus an active client, accepted/in-progress project, task type, and same-company ownership;
- one exact service match and one client/service account identity; multiple relevant recurrence rows produce one `duplicate_account_service` exclusion with the first two recurrence source references and hashes;
- policy allows adjustment and any grandfathering has ended;
- price still resolves from the policy-pinned accepted estimate or delivered invoice line item with the same hash;
- the price line is a simple per-unit line: quantity exactly one, non-null optional-selection flags, line-item and parent-document discounts exactly zero, no positive minimum charge, and no unselected optional line;
- company currency has a supported ISO minor-unit exponent;
- line-item tax treatment and active tax rate are complete; missing, inactive, unsafe, or out-of-range tax preserves the verified price facts but yields `tax_unavailable`;
- policy contact resolves to one active normalized email owned by the client;
- requested month contains an actual service occurrence after recurrence exceptions;
- the first effective occurrence meets the recorded notice period; and
- provider correspondence for that address is completely readable under normalization v2.

The database first returns the bounded recurrence-driving catalog. Before estimating or constructing JSON, it rejects any RRULE outside the non-expanding canonical uppercase recurrence alphabet. TypeScript removes a history only when exact, conservative recurrence semantics prove it ended before the requested month. Invalid or overflowing target-month exception data stays in scope, and one aggregate classification work budget spans both source catalogs and rejects computationally dense input. A second database phase accepts the selected recurrence IDs and returns both a freshly recomputed catalog and all selected details under one PostgreSQL statement snapshot. Canonical catalog equality, recomputed selection equality, and exact recurrence-to-account evidence are mandatory. Ended historical series and future-only series therefore do not spend the account bound, while an exact recorded reschedule into the month remains eligible for evaluation. Any missing, ambiguous, stale, unsupported, invalid, unreadable, duplicated, or bounded evidence fails closed. An affected account receives exact exclusion reasons when the rest of the package remains valid; package-level staleness or overflow rejects the entire request.

## Price, schedule, notice, and risk

Money uses checked integer arithmetic. Current decimal prices convert exactly to the company currency minor unit. Proposed price is the current minor value multiplied by the exact percentage and rounded half away from zero at that minor unit. Tax is recomputed from the pinned line-item treatment and active tax rate. No currency conversion occurs.

The effective date is the first real recurrence occurrence in the requested month after bounded RRULE expansion and recorded skip/reschedule exceptions. The exact RRULE returns with the preview. Long-running sparse COUNT series, including century-old yearly schedules, and bounded long-distance reschedules remain supported; invalid frequency/key combinations, conflicting RRULE `UNTIL` and database end anchors, a phantom exception, or a dense complex history that cannot be proven inside the fixed work budget fails closed. The notice draft states the contact name, service, effective date, current and proposed rates, unit, explicit tax treatment, unchanged schedule, and company name. It invents no reason for the increase, and its subject is capped at 200 UTF-8 bytes without splitting a Unicode code point.

Churn risk is explainable classification, not prediction:

- `high`: the latest classified state in a category is explicit cancellation or price objection;
- `medium`: the latest classified state is service/overcharge complaint, or there is recent coherent positive collectible late-payment evidence; or
- `unknown`: no current classified signal, or evidence is incomplete, unreadable, insufficient, resolved, or contradictory.

There is deliberately no `low` label. A later noun-bound explicit resolution supersedes an older negative in the same category, while unrelated materials, logistics, or quantity text cannot; same-time contradictory states cannot produce a definitive signal. Evidence is limited to the exact 8,760-elapsed-hour window disclosed in the result, so session timezone and daylight-saving changes cannot move the cutoff. The result carries only fixed signal codes and hash-bound source references. Raw provider body, subject, snippet, normalized text, and instruction-like content never enter the snapshot or result. All returned business values are serialized as untrusted data.

## Authority and database boundary

The capability requires these OAuth scopes:

- `ops.catalog.read`
- `ops.company.read`
- `ops.correspondence.read`
- `ops.customer_contacts.read`
- `ops.customers.read`
- `ops.financial_documents.read`
- `ops.operations.prepare`
- `ops.schedule.read`

It also requires current company-wide `calendar.view`, `catalog.products.view`, `catalog.view`, `clients.view`, `email.view`, `estimates.view`, `invoices.view`, and `settings.company` permissions.

The application resolves current authority before the source phases and again after their same-snapshot comparison. It calculates and bounds the ephemeral package, then runs a separate SQL assertion immediately before return. Every stable security-definer RPC phase independently verifies actor, company, client, live OAuth grant, exact grant revision, the exact eight granted/tool scopes, the exact sixteen-scope registered v9 client ceiling and serialized scope, permission snapshot, manifest v15, exposure v9, capability id/revision, consent labels, and a five-minute observation window. Consent-label compatibility remains exact: v2 closeout, v3 collections/customer drafts, and v4 recurring-price/customer notices have separate immutable labels.

The private table has RLS and no browser policy. Direct table privileges are revoked from browser and service roles. The private assertion has no app-role execute grant. The public read RPC has an empty pinned search path, revokes execution from `public`, `anon`, and `authenticated`, and grants only `service_role`.

## Identity, effects, and replay

Every account preview receives a SHA-256 identity over the tenant, company name, currency/minor exponent, business date, client, task type, recurrence, policy, price-source hash, account source revision, percentage, effective date, and recipient. The ordered package receives one canonical plan hash over authoritative request, selection, every evaluated account source revision, previews, exclusions, and supporting records. Observation/generation instants and the moving evidence-window endpoints are informational and do not alter stable identity; the fixed 8,760-elapsed-hour window rule does.

The safety envelope is literal: `ephemeral: true`; `preview_content_stored: false`; `transport_audit_metadata_recorded: true`; sent, prices changed, contracts changed, invoices changed, and service changed false; commit capability available false. No mutation RPC, commit sibling, send sibling, durable draft, approval, queue item, notification, routine, receipt, or provider request exists.

## Verification evidence

The permanent suite proves strict input and output contracts, manifest/exposure/consent pinning, current-authority revalidation, tenant isolation, stale grant/selection/price denial, unique service/contact/account resolution, non-null optional flags, zero parent-document discount, exact `tax_unavailable` source semantics, RRULE alphabet/combination/termination validation, sparse old series and long-distance exceptions, notice and grandfathering gates, Unicode-safe subject bounds, exact percentage/tax rounding across currency exponents, deterministic context/source-bound hashes, latest-state risk resolution and materials/logistics counterexamples, coherent late-payment evidence, provider raw-content omission, prompt-injection serialization, duplicate account/service identity exclusion with two recurrence sources, source/result/evidence/transport/shared-work bounds, exact 100-account success and 101-account rejection, historical/future recurrence omission, and zero business mutation.

A SHA-256-pinned disposable PostgreSQL 17 runner proves migration compile and deterministic read replay, table/function ACL and RLS shape, exact index definitions and bounded plans, exact v15/v9/v4 authority, all four inherited tools under a real v9 grant, historical v5-v8 authority preservation, rejection of cross-paired revisions and corrupt v9 client/consent/label state, historical v1-v3 consent preservation, two-phase golden source transport, server-side catalog/detail bounds including escape-heavy RRULE rejection before materialization, tenant and stale-authority denial, provider evidence without raw mail, common-address tenant/window composition, before/after digests for every in-scope source including companies, historical/future recurrence omission, exact reschedule inclusion, duplicate recurrence identity grouping, and the exact 101-identity overflow sentinel.

## Cost boundary

This local candidate adds no paid service, provider send, model call, scheduled job, or durable preview-business-content storage. If deployment is separately approved, the private policy rows and shared transport audit/rate metadata consume PostgreSQL storage. The migration also builds B-tree and GIN indexes on existing recurrence, exception, provider, invoice, contact, policy, line-item, and service tables; deployment therefore has real one-time build-lock/IO and storage cost plus ongoing write amplification. Each tool call performs two bounded service-role source reads and one final authority assertion. No new vendor or subscription is introduced, but migration timing and database headroom require a separate production review.

## Release boundary

Phase 7 does not push, deploy, apply the migration, register a client, mint a grant, change active OAuth metadata, run a production canary, activate exposure v9, send a notice, or alter any customer record. Live readback on 2026-09-01 found seven active v1 clients/two active v1 grants, one active v2 client/one active v2 grant, no other exposure revisions, zero active task recurrences, and no price-policy table or price-preview RPC. Active production exposure remains v2.

A later release requires separate explicit approval for push/deployment and migration application. Data population for explicit account policies, client registration, consent/grant creation, authenticated tool proof, activation, and customer-live status are separate gates after release.
