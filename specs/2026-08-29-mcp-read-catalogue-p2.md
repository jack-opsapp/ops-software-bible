# MCP Complete Read Catalogue — P2 (2026-08-29)

**Status:** **PRODUCTION-DEPLOYED, EXTERNALLY DARK.** All thirty-nine ordered P2 migrations are production-applied, and OPS-Web production HEAD `87abc02ac3205254c1446bb50f7eda3607000140` is served by READY Vercel deployment `dpl_6oUh3jTry9DWRAuTD1pnPSqKLRaA` at `app.opsapp.co`. The final deployment includes the live post-release auth continuation repair, which preserves the sanitized MCP authorization return path after sign-in. Production runs capability manifest `2026-08-22.capability-manifest.v8` with thirty-four implemented reads. External MCP exposure remains immutable `2026-08-22.mcp-exposure.v1`: exactly eleven tools and seven grantable read scopes. The other twenty-three reads are deployed dark, no thirty-four-read exposure revision has been built, and all external writes remain unavailable. OAuth metadata and the MCP bearer challenge passed live checks. Codex DCR discovery and registration work in production, but the full host canary is awaiting the user's final browser consent and Codex is not yet accepted.

## Outcome

P2 adds twenty-three purpose-built, actor- and company-scoped reads to the eleven production reads. The production capability manifest therefore contains thirty-four implemented reads. The immutable external exposure remains `2026-08-22.mcp-exposure.v1`, which advertises only the original eleven reads. All fourteen prepare/commit capabilities remain unavailable and absent from external registration.

This is complete business-data access, not generic database access. Every tool has a closed input grammar, fixed permission variants, bounded source scan, strict private projection, proof/revision binding, bounded public result, and untrusted-business-data marking. There is no table browser, arbitrary SQL, arbitrary filter/sort/column selection, caller-supplied company identity, raw export, or unrestricted notes/memory endpoint.

## Codex desktop connector compatibility

The deployed authorization server accepts the observed Codex native DCR callback without broadening the OAuth grant or tool surface. Codex registers one complete ephemeral loopback URI after binding its port. OPS accepts only literal `http://127.0.0.1:<1-65535>/callback/<bounded-base64url-id>` and preserves that complete value byte-for-byte through consent, code creation, and token exchange. Claude's hosted callbacks remain exact. CIMD, wildcard ports, host aliases, mixed callback families, and multiple Codex callbacks remain closed.

The captured registration payload and adversarial application tests pass, and the complete thirty-nine-migration PostgreSQL 17 wave passes with exact redirect lifecycle and replay proof. The migration and application code are now production-live, including the post-release auth continuation repair, and OAuth metadata plus the MCP bearer challenge passed live checks. Codex DCR discovery and registration work against production, but the full host canary is awaiting the user's final browser consent; no completed token exchange, authenticated tool list/call, or accepted Codex host is claimed yet. ChatGPT remains a separate host proof.

## P2 catalogue

| Capability                  | Business purpose                                                                                                                                             |
| --------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `get_customer_context`      | Current customer identity, permitted business contacts/preferences, duplicate state, and job rollup                                                          |
| `list_tasks`                | Bounded actor-visible task views                                                                                                                             |
| `get_task_context`          | Exact task, schedule, dependency, readiness, assignee, and requested note context                                                                            |
| `list_job_artifacts`        | Safe metadata for photos, visit artifacts, attachments, generated documents, deck designs, and permitted job notes                                           |
| `get_job_artifact_evidence` | Exact bounded text evidence or a short-lived, single-use OPS binary resource                                                                                 |
| `list_site_visits`          | Booked appointments or visit history using their canonical time fields                                                                                       |
| `get_site_visit_context`    | Exact visit identity, checklist, measurements, artifacts, timeline, and opaque deck-design references                                                        |
| `get_deck_design_geometry`  | Exact bounded 2D topology plus independently qualified deck area and guard/railing measurements                                                              |
| `list_sales_documents`      | Bounded permitted estimates/invoices                                                                                                                         |
| `get_sales_document`        | Exact permitted estimate/invoice detail                                                                                                                      |
| `list_payments`             | Bounded recorded payment facts                                                                                                                               |
| `list_expenses`             | Bounded expense/reimbursement views                                                                                                                          |
| `get_expense_context`       | Exact permitted expense, receipt state, approval, and reimbursement context                                                                                  |
| `list_work_queue`           | One bounded operational queue across authorized task, correspondence, lead, commitment, match-review, expense, payment, sales-document, and schedule sources |
| `search_catalog_items`      | Bounded product/service catalogue lookup                                                                                                                     |
| `get_catalog_item`          | Exact permitted catalogue item and closed pricing/stock sections                                                                                             |
| `list_purchase_orders`      | Bounded permitted purchase orders                                                                                                                            |
| `get_purchase_order`        | Exact purchase-order detail                                                                                                                                  |
| `get_company_context`       | Safe company operating identity, settings summaries, and requested operational sections                                                                      |
| `list_team_members`         | Safe team directory without private identity/authentication data                                                                                             |
| `list_team_availability`    | Bounded schedule/time-off availability                                                                                                                       |
| `get_integration_health`    | Safe mailbox/accounting connection health without tokens or provider payloads                                                                                |
| `get_operational_overview`  | Selected independently authorized attention summaries with per-component proof and inspection accounting                                                     |

## Carly Hunter deck-design flow

The intended assistant flow is:

1. Resolve Carly Hunter through `search_customers` or an already known customer reference.
2. Resolve the relevant job and site visit through `list_customer_jobs`, `list_site_visits`, and `get_site_visit_context`.
3. Read the returned opaque deck-design reference with `get_deck_design_geometry`.
4. Present the renderable geometry and the measurement results.

The geometry response contains normalized local planes, vertices, edges, surfaces, directed outer loops/holes, levels, and stair/level connections. It separately reports measurement quality per metric. Deck area uses closed surface topology and effective drawing scale. Flat, parapet, edge-stair, and level-stair guard measurements use the authoritative persisted dimensions and DeckKit-compatible formulas. Invalid area never suppresses otherwise valid railing, and one unavailable railing subtype never silently disappears from a combined total.

The public result excludes raw `drawing_data`, persisted component payloads, catalogue/product identifiers, prices/costs, editor recovery blocks, framing, terrain, footings, house openings, photo overlays, permit/zoning payloads, storage paths, creator identity, and private notes. The repository rejects oversized or structurally invalid geometry rather than truncating it.

## Manifest and rollout model

- Frozen compatibility manifest: `2026-08-20.capability-manifest.v7`.
- Production active policy manifest: `2026-08-22.capability-manifest.v8`.
- External exposure: `2026-08-22.mcp-exposure.v1`, unchanged at eleven tools and seven read scopes.
- V7 manifest bytes remain byte-identical. Existing v7 read cursors are accepted only under the exact v8 transition binding, including their legacy query hash; a continued request reissues a v8-only cursor. Unknown manifest versions, changed permissions, changed query identity, or tampering fail closed.
- Existing v6/v7 SQL results are returned unchanged for their own manifest identity. V8 recursively re-proves the same business data without rewriting business strings.
- OAuth consent labels are versioned independently from policy and exposure. A host cannot make a capability grantable by naming it.
- Candidate policy objects are nominal but dormant. Only the central manifest can activate the exact policy identities that passed the complete v7/v8 invariant checks; authorization and every P2 binding reject a newly minted, cloned, structural, or otherwise unactivated policy.

## Data and proof boundaries

Production has applied all thirty-nine ordered Supabase migrations: manifest compatibility, domain revisions, OAuth consent-catalog versioning, strict Codex DCR callback registration, durable MCP rate limits, evidence nonce/redemption, shared attention projections, and the source/RPC boundaries for every P2 domain. The Bible's migration archive mirrors the applied ordered wave.

Every public RPC is service-role only, fixed-name, `SECURITY DEFINER`, search-path pinned, same-statement authorized, and source bounded. P2 paginated reads use a fifteen-minute signed cursor bound to actor, company, OAuth client/grant facts, permission snapshot, capability and schema identity, canonical input, exact source revision vector, and predecessor. A source reaching its sentinel fails with a bounded error; it cannot be reported as an empty or complete result.

Evidence binaries use a separate at-most-five-minute signed token and a one-way nonce ledger. Redemption requires the same bearer, client audience, current grant, actor/company membership, source authority, source revision, safe-scan state, and unused nonce. Tokens, storage paths, and payloads are excluded from logs and MCP audit fields.

Operational-overview child proofs bind only the selected component's authorization, exact component inspection count, and component revisions. The collection proof binds the exact ordered component inspection vector and derived total, preventing cross-component redistribution or authorization substitution.

## Explicit exclusions

The catalogue never returns provider credentials, OAuth/access/refresh tokens, webhook secrets, payment instruments, bank/payroll/tax secrets, private staff contacts or home data, live location/device/auth identifiers, role-administration internals, raw provider payloads, raw settings JSON, raw audit/queue/lease data, permanent file URLs, deleted/superseded rows, or cross-company data.

Writes remain outside this release. Future material assignment, catalogue setup, and deck-geometry creation/editing must use a prepare → deterministic preview → explicit OPS human approval → one-time commit protocol. A geometry source fence is evidence of freshness only; it never authorizes a write.

## Remaining external-exposure release boundary

The database/application release is complete, but it does not make any of the twenty-three added reads customer-live. Exposure v1 remains frozen at eleven tools and seven scopes. A full-catalogue release must separately build and review a new immutable exposure revision, approve its exact capability/scope set, deploy it, and complete host-specific tool-list/call, revocation, authority-change, pagination, rate-limit, evidence, audit-privacy, and rollback proof. No thirty-four-read exposure revision exists today.

The Codex canary must still complete the user's final browser consent, token exchange, authenticated `tools/list` and tool-call proof, revocation, and cleanup readback before Codex is called an accepted host. Claude production proof does not automatically prove Codex or ChatGPT connector compatibility, and eventual Codex proof will not automatically prove ChatGPT. Until a separate external-exposure release completes, the twenty-three P2 reads remain unavailable to every external host.
