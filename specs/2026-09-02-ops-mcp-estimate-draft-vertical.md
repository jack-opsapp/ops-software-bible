# OPS MCP Estimate Draft Vertical

- **Designed:** 2026-09-02
- **Released:** 2026-09-03
- **Status:** Production-released; dormant and unactivated
- **Authoritative Web base:** `dd187ba32`
- **Authoritative Bible base:** `35284e5`
- **OPS-Web release commit:** `1cacc2df8b483689cc4f3cd183c5be981ad0c9f2`
- **Component commits:** `8accd449`, `16221d55`, `7a6f8542`, `46840d55`, `e091b648`, `1cacc2df`
- **Source migration:** `ops-web/supabase/migrations/20260902231632_agent_estimate_draft_preview.sql`
- **Production ledger:** `20260903110828_agent_estimate_draft_preview`
- **Production archive:** `migrations/20260903110828_agent_estimate_draft_preview.sql`
- **Vercel deployment:** `dpl_2tZT6cbyw1eBuWAAbSAwP1xc1obA` (`READY`, owns `app.opsapp.co`)

## Purpose

The eighth Invisible Office vertical handles the golden task:

> Quote this new lead like that past job, plus 8%.

`prepare_estimate_from_past_job` returns one exact, ephemeral draft estimate preview. The operator or host must identify both the open target opportunity and the specific approved past estimate. OPS does not infer which lead or past job was intended.

This is preparation only. It creates no estimate row, reserves no estimate number, issues no document, approves or publishes nothing, sends no message, commits no price, and persists no preview business content. No commit sibling exists.

## Versioned contract

- Result schema: `2026-09-02.v1`
- Capability manifest: `2026-09-02.capability-manifest.v16`
- Dormant exposure: `2026-09-02.mcp-exposure.v10`
- Consent catalogue: `2026-09-02.mcp-consent-catalog.v5`
- Capability revision: `prepare_estimate_from_past_job:2026-09-02.v1`
- Tool input: exactly `target_opportunity_id`, `source_estimate_id`, and `increase_percent`
- Percentage: positive canonical decimal, at most 100, at most four fractional digits, no fractional trailing zero
- Source-line ceiling: 100; the database reads one extra sentinel and rejects 101
- Source snapshot ceiling: 1,000,000 UTF-8 bytes in PostgreSQL and 1,000,000 serialized characters in the repository
- Result ceiling: 1,000,000 serialized prompt-safe characters
- Supporting-record ceiling: 220
- Observation tolerance: five minutes

Manifest v16 re-mints v15 and adds only this high-risk preparation capability. Exposure v10 is additive to v9: the four inherited analyses, recurring-service price preview, and estimate draft preview remain callable. Every inherited tool accepts its historical manifest/exposure pair or the exact v16/v10 bridge. The v16/v10 route additionally requires the exact registered 17-scope client ceiling and serialization, v5 consent, and exact accepted labels. Historical grants retain their prior behavior.

Active production exposure remains read-only v2. Exposure v10 is deployed in application code and its service-role-only database boundary is applied, but it has no production client, grant, canary, or activation.

## Explicit target and source

The target must be one current, non-deleted, non-archived, non-merged opportunity in the actor's company, with one current non-merged client. Its stage must be `new_lead`, `qualifying`, `quoting`, `quoted`, `negotiation`, or `follow_up`. A won, lost, closed, archived, deleted, merged, cross-company, clientless, or client-inconsistent opportunity is not eligible.

The source must be the exact estimate id provided by the caller. It must be non-deleted, `approved` or `converted`, and tied to one non-deleted same-company project for the same client. The project must be `completed` or `closed` with a recorded completion instant. The source client must still be active and unmerged. The database rejects stale text mirrors for client or project identity.

The source estimate must have complete, internally consistent stored totals. Document-level discounts are deliberately unsupported: `discount_type` and `discount_value` must both be null. Deposit fields must be all absent or all present as a valid fixed/percentage deposit. Client message, internal notes, terms, estimate notes, project notes, and opportunity descriptions are never copied.

## Line-item fidelity and arithmetic

Every source line returns in canonical `sort_order`. Duplicate sort positions, missing parents, cross-company lines, invoice-linked lines, blank or oversized labels, non-positive quantity, negative unit price, invalid discount, negative minimum charge, null optional/tax flags, negative or missing stored line total, malformed unit/category/type/options text, and more than 100 lines fail closed.

OPS preserves the source line's:

- hierarchy and source/product/task/unit references;
- name, description, quantity, unit, category, type, and resolved options label;
- discount percentage;
- taxable flag;
- optional flag and selected state;
- sort position; and
- deposit type/value at the estimate level.

The requested percentage applies only to unit price and minimum charge. Money math uses checked arbitrary-precision integers after conversion to the company's two-decimal minor unit. Each adjusted value is rounded half away from zero at the minor unit. Quantity extension, percentage discount, minimum-charge floor, line tax, totals, and percentage deposit are then recomputed from those rounded values.

Unselected optional lines remain visible for fidelity but contribute zero to subtotal, discount, taxable total, tax, total, and deposit. A fixed deposit amount is preserved. A percentage deposit keeps its percentage and is recalculated from the new total. Source totals are independently reconstructed before any preview is returned; a mismatch is stale evidence, never silently corrected.

The preview hash excludes request id and observation time. It binds the exact target, source estimate and completed project, every line and source hash, current tax evidence, percentage, calculated lines, totals, and source revision. Equivalent calls over unchanged evidence therefore produce the same preview identity.

## Current tax rule

The source estimate's stored tax rate is used only to validate its historical totals. The draft uses the company's current active default tax rate because the operator is preparing a new estimate now.

Exactly zero or one active default tax row may exist. More than one fails closed. If any selected included line is taxable, one valid current default is mandatory. Its rate must be a fraction from zero through one. Missing, ambiguous, malformed, or out-of-range current tax evidence rejects the request. A historical percentage stored as `13` instead of `0.13` is invalid and is never reinterpreted.

## Authority and stale-source boundary

The capability requires these OAuth scopes:

- `ops.company.read`
- `ops.customers.read`
- `ops.financial_documents.read`
- `ops.financials.prepare`
- `ops.jobs.read`

It also requires current company-wide `clients.view`, `estimates.create`, `estimates.view`, `pipeline.view`, `projects.view`, and `settings.company` permissions. `estimates.create` authorizes preparation under the current actor; it does not cause a create and does not confer issue/send authority.

The application authorizes the resolved MCP actor, immediately re-resolves current authority, reads one service-role-only database snapshot, performs deterministic calculation and output bounding, re-resolves authority again, and then invokes a final service-role-only database assertion. The final assertion rebuilds the source snapshot under current authority and requires the exact source revision read earlier. A changed lead, client, project, estimate, line, tax record, grant, consent label, scope, permission, client ceiling, manifest, or exposure fails closed before return.

Both public RPCs are stable security-definer functions with an empty search path and fully qualified relations. Execution is revoked from `public`, `anon`, and `authenticated` and granted only to `service_role`. Private helpers grant no execution to application roles. There is no browser-write route.

All names and business descriptions in the result remain untrusted data. The MCP transport serializes the complete result through the shared prompt-safety boundary. Business text cannot alter authority, arithmetic, effects, or tool behavior.

## Truthful receipt and effects

The result status is `ready`, meaning the calculation completed—not that an estimate exists. It includes the exact source/target identities, pricing rule, current tax record, deposit rule, every line, totals, supporting hashes, and one stable preview SHA-256.

The safety envelope is literal:

- ephemeral true;
- preview content stored false;
- ordinary transport audit metadata recorded true;
- estimate created false;
- estimate number reserved false;
- estimate issued false;
- estimate approved false;
- estimate published false;
- messages sent zero;
- prices committed false;
- exact confirmation required before any later issue true; and
- commit capability available false.

The migration creates no table, durable draft, approval action, queue item, notification, routine, provider request, estimate mutation, or numbering call. Shared MCP rate-limit and transport-audit metadata remain the only durable behavior.

## Verification evidence

The permanent TypeScript suite proves strict three-field input, canonical percentage validation, half-away-from-zero arithmetic, minimum-charge and discount order, current-tax recalculation, optional-line exclusion, deposit handling, source-total reconstruction, deterministic preview hashing, request-id-independent idempotency, supporting provenance, prompt-injection-safe output, source/result bounds, current actor reauthorization before and after calculation, abort propagation, tenant/request/source drift rejection, malformed repository responses, exact v16/v10/v5 registration, inherited-tool discovery and dispatch, and zero effect flags.

The SHA-256-pinned PostgreSQL 17 runner creates only a disposable non-default-port database. It compiles Phase 7 then Phase 8 in order and proves exact consent labels, exact authority, deterministic snapshots, final source binding, source-status rejection, cross-tenant denial, merged-target denial, ambiguous-current-tax denial, 101-line rejection, changed-price rejection, service-role-only ACL/catalog shape, zero estimate creation, zero target numbering, zero business mutation, rollback cleanliness, and two complete replays against the same database.

The final post-integration focused run passed 322 tests across 29 Phase 8 contract/service/runtime, principal-boundary, registry, OAuth, and inherited compatibility files. The separate live PostgreSQL 17 run passed both its lifecycle guard and full disposable-database proof. A repository-wide test run exposed no further Phase 8 failure: its remaining 16 failing assertions and seven test-file load errors are confined to unchanged baseline surfaces (sandbox-denied loopback canaries, date-sensitive timezone fixtures, build/permission/button/approval assertions, and declared dependencies absent from the original stale local install). Restoring the package-lock-defined install changed no source or dependency version. The production build then passed with the repository's established 8 GB Node heap, after the default 4 GB TypeScript process reached its memory ceiling. Every changed TypeScript file passed ESLint. Independent release verification reran all 14 changed non-database test files: 130 tests passed.

The production ledger stores one 42,223-byte statement whose MD5 `a180b8ef634f6aec19b6734d3601a0bf` matches the committed source and archive exactly; their SHA-256 is `a24282619e24c5f0d14135940e7f88a226b93b237c71842d97e779f44c8ce9f7`. Live catalog readback confirms both public functions are owned by `postgres`, are `SECURITY DEFINER`, pin `search_path` to empty, and grant execution only to `postgres` and `service_role`. Post-apply advisors report no Phase 8-related finding and no error-level finding. Exposure v10 has zero active clients and zero active grants.

Vercel built the exact release commit in six minutes, marked deployment `dpl_2tZT6cbyw1eBuWAAbSAwP1xc1obA` `READY`, and attached `app.opsapp.co`. Fresh live probes returned HTTP 200 from both OAuth metadata resources with only the established 20 read scopes, rejected unauthenticated `POST /api/mcp` with HTTP 401 and a Bearer challenge, and found no `/api/mcp` runtime error cluster in the release window.

## Cost boundary

This production release introduces no new subscription, vendor, model call, provider send, scheduled job, or durable preview-content storage. If exposure v10 is separately activated later, each call adds bounded Supabase compute for the source snapshot and final revalidation plus the existing MCP transport audit/rate-limit writes. There is no new table or index storage and no new external-provider charge.

## Release boundary

Phase 8 is pushed to OPS-Web production main and its exact database migration is applied. The release does not register or edit an OAuth client, mint a grant, run a production canary, change active OAuth metadata, activate exposure v10, create an estimate, reserve a number, or contact a customer. It is production-released, verified, and dormant.

Client registration, v5 consent/grant creation, authenticated synthetic proof, host acceptance, active-exposure change, and customer-live status remain separate approval gates after release.
