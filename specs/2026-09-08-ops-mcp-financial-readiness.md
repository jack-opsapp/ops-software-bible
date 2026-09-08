# Phase 16 — financial draft readiness and host acceptance

Status (2026-09-08): released to production with both database migrations applied. Financial preparation/save authority remains disabled; no company policy, financial binding, grant or trial was activated. Authenticated Claude/ChatGPT acceptance remains unproven. Fresh integrated validation passed 670 regression tests, nine real local HTTP/protocol/SQL scenarios, eight focused owner-policy tests and 160 owner-policy SQL assertions. These groups overlap and are not a combined total. Production compilation, full TypeScript validation and 388 generated static pages passed.

## Scope and decision
Extend Phase15's existing private policy and financial approval contracts. An owner reviews an exact versioned source and explicit structured pricing rules in OPS, then enrolls that revision. Enrollment authorizes preparation eligibility only. Each held financial draft still needs exact current named-operator confirmation. No generic policy platform, invoices, payment, delivery or hold release.

Alternatives considered: direct SQL enrollment lacks a durable owner review contract; a general policy/settings platform broadens scope. The selected bounded owner review path reuses company identity, granular permissions, the existing private financial policy and the approval desk.

## Verified starting gates — 2026-09-08 UTC

| Gate | Observed state |
|---|---|
| Remote software | Fresh main fetch web 3812893c2, Bible 779d7cd; matches Phase15 release |
| Database | Phase15 policies/proposals/held drafts/v17 grants zero; installed/current effect SHA256 1dbb20f58a47881a7838a77a2ae69cb55aea8142ba41e5c9b62c0b73a21ae4c5 |
| Public exposure | Source active v20/v14/v9; v17 candidate absent from selectable catalogue |
| Financial consent | v12 absent |
| Canpro | a612edc0-5c18-4c4d-af97-55b9410dd077; CAD; owner Jackson Sweet 283d49df-90a1-4abb-b94c-3e9f17f02c0d; zero usable products, estimates and tax rows (two deleted historical products exist) |
| Existing connector | Authenticated get_company_context succeeds for MAVERICK PROJECTS LTD ddee107c-33cd-483e-8278-0f8d8a180181, not Canpro |
| Host acceptance | Neither Claude nor ChatGPT financial prepare/approve/save acceptance proven |

Current company currency never supplies missing historical currency. No existing estimates may be rewritten to manufacture a trial. External CANPRO-EST-001 and CANPRO-EST-003 were recovered and hashed. EST-003 mandates full plywood replacement while retaining partial-replacement and substrate-allowance passages. These conflicts and the exact logged price-band choice require owner resolution. Live notes contain a job-specific approximate quote and unspecified discount, not an approved company pricing policy.

## Required contract
Owner setup requires exact current account-holder identity plus company-wide settings.company and the existing financial permissions, all resolved server-side. Preview seals source note full row/hash, owner/company, canonical fields, current policy hash, current company currency, exact default tax and expiry. Enrollment consumes that preview once; changed fields require a new preview. Revision content remains immutable, supersession retires prior policy and invalidates outstanding drafts. Revocation never releases held documents.

Readiness differentiates software/effect review, owner policy/source validity, current actor/grant/consent and authenticated host acceptance. No state is called ready merely because a mock or protocol test passed. Candidate consent adds only financial preparation, no save/send/issue authority; public defaults and existing grants remain unchanged.

Financial source or effect changes fail closed. This phase's migration must not automatically renew the Phase15 effect fingerprint. Exact reviewed graph installation remains a separate release gate.

## Acceptance and authority
Local isolated fictional data proves real SQL arithmetic, owner enrollment, authorization, exact preview, staleness, idempotency, custody, revision/change-order boundaries and receipts. Fixtures do not use PERSONA TEST POOL or production business records. Real host trial needs direct exact company/actor/policy/source/lead/history/document authority after all independent work is verified. Claude and ChatGPT evidence is separate; the existing Codex connector read is neither.

## Implemented boundaries and evidence

- Owner session API, strict request/result contracts, existing canonical authority resolver, private durable preview/receipt ledger, immutable revision retirement and exact tax/source/owner bindings.
- Owner review UI with English/Spanish copy, current design-system tokens, escaped source evidence, sealed confirmation, uncertain-response retry and explicit revocation confirmation.
- Restricted v17/v12/v23 trial: company context, financial source inspection and exact draft preparation, with five canonical scopes. Public defaults remain v14/v9. Exact company/actor/client, owner-enrolled policy hash, reviewed effect hash and maximum two-hour expiry bind authorization, code exchange, bearer, refresh, revocation and financial actions. The new nine-argument provisioner is service-only; no route provisions it. The original six-argument v3 provisioner remains unchanged.
- 160 passing PostgreSQL assertions in disposable fictional databases, including adversarial replay after enrollment and two independent approval sessions; 129 application/protocol tests across 12 files. Real in-app browser fixture reaches the exact approval screen. Synthetic fixtures are not authenticated host proof.
- Seven fresh local acceptance scenarios use real owner/consent/token route handlers, production MCP runtime, company/source reads, financial SQL and the actual OPS approval service. They prove one held CAD226.80 draft, exact retry/receipt/readback, bad PKCE and consent replay, wrong/widened subjects, source/tax/owner/effect drift, real-time expiry, immutable binding, concurrent approval/revocation and owner-policy retirement of a pending approval. All seven pass; 670 additional current regression tests pass across 18 files. Prior owner-readiness totals overlap and are not additive.
- Historical pre-release snapshot: 2026-09-08 04:03:39 UTC. Both Phase16 migrations were absent; zero financial policies/proposals/held estimates/v17 grants/financial bindings. Installed/current Phase15 effect hashes matched. The approved release below supersedes this software/schema status, not its dormant financial-authority boundary.

Web implementation evidence is under `docs/artifacts/phase16/` in the web worktree; fresh integrated release evidence is under its `release/` subdirectory. Source migrations are mirrored byte-for-byte under `migrations/20260908024426_financial_policy_readiness.sql` and `migrations/20260908033425_financial_trial_oauth.sql`. Exact production-ledger copies are also archived under versions `20260908054740` and `20260908054759`.

## Exact remaining business and host gates

The web `activation-boundary.md` specifies the proposed first real trial: new **OPS MCP FINANCIAL ACCEPTANCE — FICTIONAL** company, dedicated fixture owner, fictional customer, two-hour CAD100/hour completed history, 5% GST, exact attributable policy note, new deck quote, +8% unit price, CAD216 subtotal/CAD226.80 total, separate Claude/ChatGPT clients, 30-minute bindings and one held draft per host. Fixture creation, actual returned identities/hashes, exact binding/save approval and per-host fresh consent remain required. Do not transfer a real user's company membership or use Canpro/MAVERICK/PERSONA fixtures. No actual production fixture IDs or absolute trial times exist yet.

Jackson directly approved the software release and two migrations in the parent coordinator task. Reviewed effect installation, company policy enrollment, financial OAuth activation and each real financial trial remain separate, ungranted authorities. Local code and fictional fixtures do not grant them. Claude and ChatGPT require separate authenticated fresh-consent records, exact OPS approval, durable receipt and independent document/line/hold/no-distribution readback. Revision/change-order real saves need separately specified authority. Disable exact bindings and revoke grants after an approved trial; held documents remain held. See the web `activation-boundary.md` for evidence and stop rules.

## Local implementation commit

Owner implementation: `0a2340a8f`, with `516a12df4` evidence formatting. Financial trial implementation: `5b6bd5a57`. Release integration merged upstream `f49bba20226f81621c439a5946be6b83b268e094` without rewriting shared history. Commit `2465637815a9a55e671f5b8399409b6fa45be10f` fixes the reproduced timestamp-hash discrepancy across UTC and America/Vancouver sessions by pinning the financial canary predicate to UTC. Nine fresh protocol scenarios pass, including legacy v3 resolution and financial bearer/refresh/expiry checks. Release source is `4bc3221cbd04f645e496d7490d9f6c416f334c0a`.

## Host acceptance checkpoint — 2026-09-08

Jackson will run the Claude test and explicitly directed the coordinator to use its own Codex connection instead of operating ChatGPT. At 16:32 UTC, native authenticated OPS calls in Codex passed company context, bounded estimate listing, exact document/line reading and job financial-rollup reconciliation. The connected company is MAVERICK PROJECTS LTD, not the proposed fictional acceptance company. All four exercised capabilities are read-only; 35 capabilities are available, but neither `inspect_financial_document` nor `prepare_financial_document` is callable. No trial fixture, policy, grant, binding, effect seal or financial save was created or changed.

This proves the current Codex read path only. Financial prepare/approve/save acceptance remains blocked on a dedicated authorized test connection and the existing exact approval gates. Claude evidence must be collected separately; neither Codex nor Claude substitutes for authenticated ChatGPT evidence. See [Codex read-only checkpoint](../docs/artifacts/phase16/host-acceptance/2026-09-08-codex-read-only.json). The earlier ChatGPT-specific trial proposal is historical; a Codex trial must resolve its own actual callback/client and obtain fresh exact consent, never upgrade the existing MAVERICK grant.

## Verified production release — 2026-09-08

- Web main source: `4bc3221cbd04f645e496d7490d9f6c416f334c0a`. Deployment `dpl_6FMCk537aRwSaeRB4EG7qRi3oiJu` is READY; the `app.opsapp.co` alias independently resolves to this source.
- Applied ledger `20260908054740 financial_policy_readiness`: SQL SHA256 `0cd104e43b1388898d97b23c1a0333d1853cadef6197c94daa5480c9e42169fe`.
- Applied ledger `20260908054759 financial_trial_oauth`: SQL SHA256 `20241fc0591d1ce5d54138099af12393646a0a7e1e26977876d226b736ddf10f`. Both ledger hashes match reviewed source and Bible copies.
- Independent SQL readback confirms forced RLS and no direct application-role access for the policy/preview/binding tables. Owner RPCs and both provisioner signatures are service-only; the six-argument legacy provisioner is unchanged. The shared canary predicate pins UTC.
- Financial effect approval was deliberately not renewed. Installed SHA256 remains `1dbb20f58a47881a7838a77a2ae69cb55aea8142ba41e5c9b62c0b73a21ae4c5`; current graph SHA256 is `077c377b70d9531b436800593907f1c465d7ce668faa4a27baeac500d648ffa9`. The mismatch closes financial authority pending separately approved review.
- Final readback at 07:27:54 UTC preserves all 27 estimates, 169 line items and 13 OAuth clients by ordered full-row digest. All five grants retain the same authority digest; only usage metadata changed between release checks. Financial policies, proposals, write tokens, actions, held estimates, bindings and v17 clients/grants remain zero. The migration readback also confirmed zero policy previews.
- Live discovery still advertises 21 scopes and excludes `ops.financial_documents.prepare`. Signed-out MCP and owner-policy requests return 401. No runtime errors were reported for the checked MCP, policy and token routes since 06:40 UTC. These release checks are not authenticated Claude/ChatGPT acceptance.

See [release evidence](../docs/artifacts/phase16/release/release-verification.json), [database preflight](../docs/artifacts/phase16/release/production-preflight.json) and [independent database readback](../docs/artifacts/phase16/release/production-postflight.json). No financial business write, enrollment, fictional production fixture, delivery, host trial or financial effect reseal was performed.
