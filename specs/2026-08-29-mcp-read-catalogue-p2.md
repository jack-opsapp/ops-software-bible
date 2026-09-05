# MCP Complete Read Catalogue — P2 (2026-08-29)

**Status:** **PRODUCTION DISCOVERY-LIVE; AUTHENTICATED V2 ACCEPTANCE PENDING.** OPS-Web commit `d5befc466c7dbf3d67b76cde698c9a9aa4df719c` defines immutable exposure `2026-08-29.mcp-exposure.v2`: exactly thirty-four read-only business tools and twenty grantable read scopes. The P2 data/RPC wave remains production-applied. The exact connector-callback database policy is also production-applied from source migration `20260830113800_mcp_oauth_chatgpt_rfc9207_callback.sql` under production ledger version `20260830004843` and name `20260830113800_mcp_oauth_chatgpt_rfc9207_callback`. Git-backed Vercel deployment `dpl_3DWhhcueWxeFW2AJnEmxT1bFhfNu` is `READY` in production on that exact SHA, with `app.opsapp.co` attached and no alias error. Canonical and query-bypass authorization/protected-resource metadata expose the exact twenty scopes and RFC 9207 support flag; unauthenticated `POST /api/mcp` returns the matching 401 challenge. The untouched v1 Codex connector has authenticated and listed exactly its eleven v1 tools without calling one. Two fresh v2 Codex registrations requested all twenty scopes but expired before approval/token exchange; a separate ChatGPT registration canary proved its exact stable-callback DCR response. All three v2 clients received zero grants and were guarded-disabled. No v2 host acceptance is claimed.

## Outcome

Exposure v2 selects the complete thirty-four-read business catalogue already implemented under capability manifest `2026-08-22.capability-manifest.v8`. Existing clients, grants, access tokens, and refresh families remain pinned to stored exposure `2026-08-22.mcp-exposure.v1`; they continue to receive exactly eleven tools and seven scopes and never widen silently. A Claude, ChatGPT, or Codex host reaches v2 only through fresh dynamic client registration and operator consent. Unknown stored exposure revisions fail closed.

This is complete bounded business-data access, not generic database access. Every tool has a closed input grammar, fixed permission variants, bounded source scan, strict private projection, proof/revision binding, bounded public result, and untrusted-business-data marking. There is no table browser, arbitrary SQL, arbitrary filter/sort/column selection, caller-supplied company identity, raw export, or unrestricted notes/memory endpoint.

All externally callable business tools are reads. No MCP tool creates, updates, deletes, prepares, commits, or sends company data. OAuth issuance/revocation, immutable request-audit append, durable rate limiting, and single-use evidence-token redemption may mutate private security bookkeeping; none is a business-data write tool.

## Connector and OAuth contract

Dynamic registration accepts one callback family per client and keeps the complete registered URI byte-exact through consent, authorization-code creation, and token exchange:

- Claude: only `https://claude.ai/api/mcp/auth_callback` and `https://claude.com/api/mcp/auth_callback`.
- ChatGPT: exactly one `https://chatgpt.com/connector_platform_oauth_redirect`.
- Codex: exactly one `http://127.0.0.1:<1-65535>/callback/<8-128-character-base64url-id>`.

Mixed families, multiple ChatGPT or Codex callbacks, wildcard ports, `localhost`, callback templates, query/fragment variants, aliases, and CIMD remain rejected. The v2 application advertises `authorization_response_iss_parameter_supported: true` and appends the exact issuer `iss=https://app.opsapp.co` to both successful code responses and explicit authorization denials. The server retains RFC 7591 dynamic registration, authorization code with PKCE S256, exact RFC 8707 resource binding, rotating refresh tokens with reuse detection, and RFC 7009 revocation. `offline_access` is not an OPS business-data scope and is not requested; persistent access uses the rotating refresh-token grant.

The callback migration changes no table, column, index, trigger, scope, grant type, tool, or existing client/grant. Its registration RPC remains `SECURITY DEFINER`, `VOLATILE`, search-path pinned, denied to `PUBLIC`, `anon`, and `authenticated`, and executable only by `service_role`.

## Compatibility and acceptance readback

The untouched Codex connector `ops_-_maverick_projects` authenticated against its existing v1 grant and returned exactly the canonical v1 catalogue: `list_scheduled_jobs`, `list_job_readiness_issues`, `get_job_communication_context`, `get_job_conversation_context`, `list_customer_jobs`, `get_job_summary`, `search_job_history`, `get_correspondence_evidence`, `search_customers`, `search_jobs`, and `resolve_job_participants`. The canary made no business tool call. This proves preserved-v1 authenticated listing without reading or changing company data.

Two fresh v2 Codex DCR attempts each requested the exact twenty-scope ceiling. Both OAuth callbacks expired before operator approval or token exchange. Neither client ever held a grant, and both client rows were guarded-disabled after the attempts. The local `ops_-_maverick_projects_v2` configuration entry remains present but unauthenticated.

A separate production ChatGPT DCR canary posted the exact stable callback and received HTTP 201 with `token_endpoint_auth_method=none`, exact grant types `authorization_code` plus `refresh_token`, response type `code`, the exact callback, and the exact twenty-scope string. It received no grant and was immediately guarded-disabled. This proves ChatGPT registration-path compatibility only, not ChatGPT OAuth or tool acceptance.

Production readback now shows v1 with seven active clients and two active grants unchanged; v2 with zero active clients, three disabled clients, and zero grants. These facts prove exact v2 registration/discovery behavior and preserved-v1 authenticated listing, not v2 host acceptance.

## V2 catalogue

- Schedule and jobs: `list_scheduled_jobs`, `list_job_readiness_issues`, `get_job_communication_context`, `get_job_conversation_context`, `list_customer_jobs`, `get_job_summary`, `search_job_history`, `get_correspondence_evidence`, `search_customers`, `search_jobs`, `resolve_job_participants`.
- Customer, task, artifact, visit, and deck context: `get_customer_context`, `list_tasks`, `get_task_context`, `list_job_artifacts`, `get_job_artifact_evidence`, `list_site_visits`, `get_site_visit_context`, `get_deck_design_geometry`.
- Financial and operational data: `list_sales_documents`, `get_sales_document`, `list_payments`, `list_expenses`, `get_expense_context`, `list_work_queue`.
- Catalogue, purchasing, company, team, and integrations: `search_catalog_items`, `get_catalog_item`, `list_purchase_orders`, `get_purchase_order`, `get_company_context`, `list_team_members`, `list_team_availability`, `get_integration_health`, `get_operational_overview`.

The twenty grantable read scopes, in canonical order, are `ops.jobs.read`, `ops.schedule.read`, `ops.customers.read`, `ops.customer_contacts.read`, `ops.photos.read`, `ops.correspondence.read`, `ops.financials.read`, `ops.tasks.read`, `ops.site_visits.read`, `ops.files.read`, `ops.financial_documents.read`, `ops.payments.read`, `ops.expenses.read`, `ops.catalog.read`, `ops.purchasing.read`, `ops.catalog_costs.read`, `ops.company.read`, `ops.team.read`, `ops.integrations.read`, and `ops.operations.read`.

## P2 additions within v2

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
- Production policy manifest: `2026-08-22.capability-manifest.v8`.
- Frozen compatibility exposure: `2026-08-22.mcp-exposure.v1`, exactly eleven tools and seven read scopes.
- V2 release exposure: `2026-08-29.mcp-exposure.v2`, exactly thirty-four tools and twenty read scopes.
- V7 manifest bytes and v1 exposure bytes remain unchanged. Existing v1 grants resolve v1 after the v2 application is live.
- Existing v6/v7 SQL results are returned unchanged for their own manifest identity. V8 recursively re-proves the same business data without rewriting business strings.
- OAuth consent labels are versioned independently from policy and exposure. A host cannot make a capability grantable by naming it.
- Candidate policy objects are nominal but dormant. Only the central manifest can activate the exact policy identities that passed the complete v7/v8 invariant checks; authorization and every P2 binding reject a newly minted, cloned, structural, or otherwise unactivated policy.

## Data and proof boundaries

Production has applied the complete thirty-nine-migration P2 wave plus callback-policy ledger version `20260830004843`. The Bible's migration archive mirrors both the ordered P2 wave and the callback source migration.

Every public RPC is service-role only, fixed-name, `SECURITY DEFINER`, search-path pinned, same-statement authorized, and source bounded. P2 paginated reads use a fifteen-minute signed cursor bound to actor, company, OAuth client/grant facts, permission snapshot, capability and schema identity, canonical input, exact source revision vector, and predecessor. A source reaching its sentinel fails with a bounded error; it cannot be reported as an empty or complete result.

Evidence binaries use a separate at-most-five-minute signed token and a one-way nonce ledger. Redemption requires the same bearer, client audience, current grant, actor/company membership, source authority, source revision, safe-scan state, and unused nonce. Tokens, storage paths, and payloads are excluded from logs and MCP audit fields.

Operational-overview child proofs bind only the selected component's authorization, exact component inspection count, and component revisions. The collection proof binds the exact ordered component inspection vector and derived total, preventing cross-component redistribution or authorization substitution.

## Explicit exclusions

The catalogue never returns provider credentials, OAuth/access/refresh tokens, webhook secrets, payment instruments, bank/payroll/tax secrets, private staff contacts or home data, live location/device/auth identifiers, role-administration internals, raw provider payloads, raw settings JSON, raw audit/queue/lease data, permanent file URLs, deleted/superseded rows, or cross-company data.

Writes remain outside this release. Future material assignment, catalogue setup, and deck-geometry creation/editing must use a prepare → deterministic preview → explicit OPS human approval → one-time commit protocol. A geometry source fence is evidence of freshness only; it never authorizes a write.

## Remaining release proof

READY deployment and production discovery are proven: canonical plus cache-bypass metadata return the exact twenty scopes, the RFC 9207 support flag is true, and the unauthenticated resource returns the matching 401 bearer challenge. Exact Codex and ChatGPT v2 DCR behavior plus preserved-v1 authenticated listing are also proven. V2 still requires a non-expired operator approval, token exchange, authenticated thirty-four-tool listing/calls, token rotation, revocation, and representative deck/site-visit calls before host acceptance. The three disabled, grant-free v2 clients prove none of those authenticated steps. ChatGPT still requires its own OAuth/tool-call proof. Connector acceptance is host-specific.

Rollback is also grant-aware: moving only the active source pointer back to v1 would not narrow already-created v2 grants, because bearer resolution honors each grant's stored exposure revision. A v2 rollback therefore requires a pre-v2 application build (or equivalent code revert) plus revocation/disablement of v2 clients and grants and a forward database repair if the callback policy must be narrowed.
