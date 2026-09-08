# Phase 16 — financial draft readiness and host acceptance

Status: owner-readiness implementation locally verified; not released, activated or host accepted. Full TypeScript check passed with an 8 GiB heap, exit 0.

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
- Candidate v12 consent paired with v17 exposure and v23 manifest/domain validation; **not selectable**, no public default/grant changes. Actual company-bound financial OAuth activation is a separately authorized gate; v3 canary provisioning does not support v17.
- 160 passing PostgreSQL assertions in disposable fictional databases, including adversarial replay after enrollment and two independent approval sessions; 129 application/protocol tests across 12 files. Real in-app browser fixture reaches the exact approval screen. Synthetic fixtures are not authenticated host proof.
- Latest production read-only snapshot: 2026-09-08 03:11:55 UTC. Phase16 migration absent; zero financial policies/proposals/held estimates/v17 grants. Installed/current Phase15 effect hashes still match. No production mutation by this task.

Web evidence: `docs/artifacts/phase16/README.md`, `production-readonly.json`, `source-readiness.json`, `activation-boundary.md`, `sql-summary.log`, `owner-review.png`. The generated migration is mirrored byte-for-byte under `migrations/20260908024426_financial_policy_readiness.sql` and is **not applied**.

## Exact remaining business and host gates

Recommended first host trial is a clearly fictional isolated company with explicitly approved source/history/tax fixtures, before a real Canpro enrollment. Canpro identity is known, but no target lead/client/job, attributable normalized policy note/hash, tax ID, eligible historical estimate/line, accepted change-order baseline, host client/binding or expiry has been approved. Do not manufacture or retrofit these records under development authority.

Release/migration approval, reviewed effect installation, company policy enrollment, financial OAuth activation and each real financial trial are separate authorities. Candidate code definitions do not provide any of them. Claude and ChatGPT require separate authenticated fresh-consent records, exact OPS approval, durable receipt and independent document/line/hold/no-distribution readback, including revision/change-order and negative controls. Disable exact bindings and revoke grants after the trial; held documents remain held. See the web `activation-boundary.md` for the exact acceptance evidence and stop rules.

## Local implementation commit

Web implementation: `0a2340a8f` (`feat(financial-policy): require exact owner review for draft rules`). Evidence log formatting is a subsequent documentation-only commit. Neither is merged to main, pushed or deployed. Phase16 remains incomplete until the selected activation and separate authenticated host acceptance gates are fulfilled.
