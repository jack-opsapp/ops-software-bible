# Invisible Office Phase 12 — Exact customer and opportunity updates

Status: implementation and local verification complete; dormant application code deployed and verified. The exact production database migration was rejected by automatic approval review and is unapplied pending Jackson's authorization. Phase 11 production deployment and ledger were independently verified before development. Production MCP remains read-only v2. This phase creates no live write grants, clients, consent, recurring work, canary records, messages or customer mutations.

## Product boundary

A named OPS operator can approve one exact evidence-backed update to an existing active opportunity, optionally including its linked customer's notes. Allowed opportunity fields are title, description, assigned owner and next-follow-up timestamp. Customer updates are notes only. Empty/unchanged proposals, clearing fields, terminal/archived/deleted/merged opportunities, ambiguous customer links, and unsupported fields fail closed. The timestamp is an internal follow-up reminder, not a scheduled visit or message. There is no dedicated next-step column: description records the next step, and next_follow_up_at records its reminder.

This scope excludes contact/address identity changes, client creation/merges, lead creation/conversion/closing, stage changes, schedules, task creation, quotes/invoices/prices, provider drafts, sending, bulk updates, automated approval and recurring routines. No human or agent can use a model-authored field to broaden this authority.

## Contracts and shared domain path

- New manifest: `2026-09-04.capability-manifest.v20`.
- Dormant exposure: `2026-09-04.mcp-exposure.v14`, with the same 34 production read tools plus only `prepare_customer_update`.
- Consent catalogue: `2026-09-04.mcp-consent-catalog.v9`. Twenty read scopes plus `ops.customers.prepare`; no commit tool or sending scope is externally exposed.
- Immutable active exposure stays `2026-08-29.mcp-exposure.v2`.
- The shared capability facade composes CustomerUpdateService with the existing domain services. Host adapters supply verified identity and dispatch calls; they do not decide effects or bypass approval. For v20 read calls only, the existing trusted reauthorization adapter resolves the identical principal/grant/scope ceiling under the preserved v8 read contracts with fresh permissions. Preparation retains v20 authority. Live SQL inspection found no agent read function pinned to v2 exposure or v1 consent; downstream grant checks keep the actual pinned client/grant identities.

Input supplies an exact opportunity id and updated_at, whitelisted field changes, optional reciprocal customer id/version/notes, a bounded idempotency key, and one to five evidence entries. Every changed field must have exactly one supporting evidence entry; extraneous, duplicate or conflicting attribution fails closed. Correspondence requires an exact, same-opportunity, same-company, company-mailbox activity and verbatim clean-body excerpt, plus current email/inbox permissions. Operator statements remain visibly unverified statements attributed to the requesting actor. All business text is untrusted data and confers no authority. Input is bounded to 32 KiB; previews to 44 KiB before persistence.

The nominal service and repository reauthorize current identity, bind server-owned revisions and scopes, call the service-only database RPC, and validate returned target, field values, source version, evidence and effects against the request. Preparation persists an approval package but does not modify a business record.

## Database and transaction boundary

Source migration: `ops-web/supabase/migrations/20260904233000_agent_customer_opportunity_update.sql`.

`private.agent_customer_updates` is the durable run/change-set record: distinct run/action/change-set ids, actor/company/grant/client identity, original request, authority snapshot, source/evidence/input hashes, policy and preview digest, 30-minute expiry, and single-use confirmation/commit receipt. `private.agent_customer_update_policy` stores the installed reviewed effect fingerprint. These relations enable RLS and deny application-role table access. They contain no customer-specific seed. The technical effect policy row is not tenant write authority.

Public service-only RPCs prepare, commit, reject, filter readable action ids, and enforce a durable prepare limit (6 actor / 6 grant / 30 company per minute). The browser-accessible can_read predicate reveals only whether the current authenticated subject can view the specified proposal. All security-definer entry points use an empty search path; private helpers are not callable by application roles.

Preparation and commit require current agent.review, pipeline.view/edit and team.view at all scope; customer notes additionally require clients.view/edit and exact record access. Assignment additionally requires pipeline.assign and an active same-company assignee with pipeline access. The database validates the exact v14 client ceiling, v9 accepted labels, live client/grant, current permission provenance and capability revision. Company/actor/grant/permission/record locks fence concurrent changes; per-client/actor idempotency and full source hashes detect content changes even when timestamps remain equal. A different grant cannot reuse a proposal key.

The effect fingerprint includes all noninternal triggers on touched business/action tables and the recursive schema-qualified helper graph, explicitly rooted at the canonical assignment core and provider-draft enqueue helper. Later trigger/helper drift invalidates preparation/commit until a reviewed policy migration replaces the fingerprint. Release compares the full live graph before and after application; the installed graph is recorded as release evidence.

Commit binds the exact action id, change-set id and displayed preview digest to the named actor. It locks the private proposal and public queue action, compares the public display copy against the private canonical proposal, rechecks expiry/current source/evidence/policy/authority, performs the whitelisted mutation, independently selects the resulting snapshot, and commits the confirmation, immutable receipt, queue status and notification resolution in the same transaction. A readback mismatch rolls everything back. An uncertain response retries only the identical commit once. Same-key completed replay reauthorizes access and returns the historical receipt without a second write; it does not claim the record has remained unchanged since that receipt.

Rejection leaves business records unchanged and clears the persistent approval notice. It requires the current named actor and agent.review but permits declining an old proposal after its external grant is revoked. Generic cancellation, automatic execution, generic proposal creation and bulk approval cannot handle this action type.

## Side-effect controls

Any accounting connection for the company blocks customer notes edits, because the current client-update trigger can enqueue accounting sync even for notes. The table lock fences a connection appearing during commit. A future connection may sync the saved record under the ordinary accounting workflow; this phase authorizes no accounting operation.

Assignment uses the existing token-guarded change_opportunity_assignment_core, preserving assignment version, immutable history, suggestion resolution and internal invalidation. The new source `agent_customer_update` still requires an actor. Provider-draft suppression is permanent in the enqueue helper, covering both immediate assignment events and later inbound-activity re-entry. Existing active provider work blocks reassignment. Delivery rows are set notify=false in the same transaction before a worker can observe them. Pending suggestions are hashed under a self-conflicting table lock, so insertions invalidate a preview and concurrent company updates cannot deadlock on a SHARE-to-write upgrade. Preview/receipt count the actual suggestions resolved. Existing internal notification/view reconciliation can occur; there are no outbound messages, provider drafts or schedule changes.

## Approval UI and privacy

The existing approval detail shows changed before/after values, stable owner identities, localized timezone-aware follow-up time, linked customer name, quoted evidence with provenance, effect limits and expiry. The save action submits exactly the displayed seal and change-set id; malformed/expired previews cannot be approved. English/Spanish labels use existing tokens and components. React renders evidence as text, never HTML.

The existing company-wide approval API now filters this type to the named operator. A service-only visibility RPC independently rechecks current record/team/customer/correspondence access. An operator who loses access receives a neutral payload with approval disabled and rejection available. A missing caller identity excludes these rows entirely. Restrictive SELECT RLS also enforces named-actor/current record permission for direct table reads. Separate restrictive INSERT/UPDATE/DELETE policies prevent browser clients from injecting, changing, deleting or retagging these actions. Existing action types retain their existing policy behavior. Aggregate queue statistics remain company-wide.

## Verification

- 52 PostgreSQL 17 checks pass on the exact migration, including true overlapping assignments in two companies, real authority/core/write-token guard, production CHECK constraints, restrictive RLS, replay/stale/tenant/evidence boundaries, provider-draft suppression, exact suggestion effects and complete rollback.
- 396 integrated application tests pass across 41 files, including synthetic loopback OAuth, active catalogue immutability, shared service composition, displayed-seal approval, response-substitution rejection, queue privacy and the latest shared Instagram repairs. Full TypeScript checking also passes with an 8 GiB heap. Focused ESLint passes for all 35 changed TypeScript files (zero errors; one pre-existing unused ClientHealthAlertActionData import warning).
- Isolated browser rendering uses the actual preview and button components with synthetic business data, canonical tokens and local production fonts. It confirms readable before/after details and evidence. This is component verification, not authenticated customer-live acceptance.
- Reproducible database runner: `bash tests/sql/agent-customer-update-run-runtime.sh`. It creates/removes only its own Unix-socket PostgreSQL cluster under /private/tmp.
- Evidence lives in OPS-Web `docs/artifacts/phase12/`, including the exact tested file hash manifest, runtime proof and regression logs.

The repository-wide CI run [33937609750](https://github.com/jack-opsapp/ops-web/actions/runs/33937609750) remains red at the pre-existing delivery-source reprojection SQL contract (`agent_provider_delivery_source_idempotency_conflict`, line 498). Both that fixture and its migration are unchanged by this release. This is separate from the passing 396-test integrated suite, full type-check and 52-check Phase 12 transaction proof.

The local fixture is not a full production clone: unrelated foreign keys, notification/accounting/work-queue trigger execution and provider workers are not reproduced. Live trigger definitions supplement focused transaction proof. Production ACL/RLS installation checks remain blocked with the unapplied migration. No production host acceptance or business canary is claimed.

## Release state

Source implementation commit: `71586d989`; integrated release commit: `3208ed09d`. Vercel production deployment `dpl_8cfLkkruGBGi5ZJQUXKJ8snEweLQ` is READY for commit `3208ed09d23f3750ede50a256e789c7220a4aafc` and serves `app.opsapp.co`. The production build passed type validation, generated all 461 static pages and completed deployment at 2026-09-05 02:06:52 UTC (2026-09-04 Vancouver).

Database: **unapplied, exact approval required**. Automatic approval review rejected the migration because it creates private state, modifies existing assignment functions and constraints, and installs restrictive RLS and function grants; standing software release permission does not cover this production database operation. Independent readback confirms no Phase 12 ledger entry and no private.agent_customer_updates table. The proposed technical effect fingerprint is not tenant write authority. No alternate DDL path or workaround was used.

Exact reviewed source: `supabase/migrations/20260904233000_agent_customer_opportunity_update.sql`, SHA-256 `e478142143fe9ebde253a1231cba34255a8d9757556187a6f324677c981831b2`. It will be archived in migrations/ only after authorized application, using the actual Supabase ledger version. Until then, database behavior described above is implemented and locally proven, not installed in production.

Post-deployment HTTP verification: OAuth discovery returned 200 and exactly the unchanged 20 read-only scopes; unauthenticated GET /api/mcp returned 401 with the same read-only bearer challenge. Independent database readback again found zero Phase 12 ledger rows, no private proposal table, and zero v14 clients/grants/actions. This verifies dormant code deployment, not installed database behavior or authenticated host write acceptance.

Preflight re-read the full reviewed graph (30 triggers and 62 nested helpers), unchanged from development. Production has zero v14 clients, v14 grants and approve_customer_update actions. Active MCP stays read-only v2. Existing queue requests do not call the new visibility RPC unless a Phase 12 action exists, making the dormant application release compatible with the unapplied migration. No activation, hosted write acceptance, customer mutation or production canary is included.

The release uses existing OPS hosting/database resources and introduces no paid service or tier. Existing plan usage applies.
