# Phase C Catalog Authoring + Agent Control Plane Integration (2026-08-07)

**Status:** Approved product direction; implementation pending
**Owner:** OPS catalog + agent control plane
**Related:** `specs/2026-08-07-ops-agent-control-plane-mcp-foundation.md`
**Implementation plan:** `specs/plans/2026-08-07-phase-c-catalog-authoring-control-plane-integration-implementation.md`

## 1. Outcome

Phase C must be able to set up one complete, usable catalog service at a time, prove the result with realistic sample quotes, and commit the service as one guarded operation. The operator can later return to add another service, change an existing service, or archive one without disturbing unrelated catalog records.

The same catalog capability must be available through the shared OPS agent control plane. Internal Phase C, REST, and remote MCP are adapters over one server-owned domain service. MCP is transport and discovery; it does not own catalog rules.

The finished customer experience is:

```text
choose add/change/archive
  -> choose one service
  -> answer short, plain-language questions
  -> review the service in plain language
  -> test and edit sample quotes
  -> confirm the exact revision
  -> apply the whole service atomically
  -> verify live readback
  -> set up another service or open the catalog
```

## 2. Non-negotiable product rules

1. Phase C proposes only behavior OPS can execute and verify now.
2. A released OPS tool may be described without being configurable only when Phase C clearly says so. It must not turn a discover-only ability into a setup question or proposed write.
3. One authoritative capability registry serves every agent and adapter.
4. One versioned pricing contract serves prepared previews and every released quote runtime. Web/server and iOS must pass the same conformance fixtures before a contract version is advertised as available.
5. The model extracts facts and chooses from server-owned question intents. It does not invent database actions or executable payloads.
6. Every catalog service change is one immutable, versioned change set with one confirmation receipt owned by the generic control-plane engine.
7. A service graph is one aggregate. It is never split into partially committed batches to satisfy a generic write-count limit.
8. The database applies the complete service graph in one transaction or applies nothing.
9. Readback verifies every material field and relationship before the UI reports completion.
10. Existing services and unrelated catalog records are preserved unless the exact reviewed change set names them.

## 3. Relationship to the agent control plane

The shared control plane remains the outer governance layer:

```text
Phase C UI        REST adapter        Remote MCP adapter
     \                 |                    /
              OpsAgentDomainService
                       |
          prepare/confirm/commit engine
                       |
             CatalogAuthoringKernel
                       |
       atomic catalog service-change RPC
```

The control plane owns:

- actor and company authority;
- capability discovery and rollout policy;
- evidence and source provenance;
- immutable change sets and hashes;
- confirmation receipts;
- receipt issuance/consumption, idempotency, generic audit, expiry, and replay protection;
- adapter-neutral contracts;
- post-commit receipt shape.

The catalog authoring kernel owns:

- the complete catalog service graph;
- required-fact and interview completeness rules;
- deterministic compilation from confirmed facts to catalog changes;
- pricing and quote projections;
- catalog-specific preflight, conflicts, and impact analysis;
- a catalog transaction participant that validates/applies catalog effects and returns catalog-specific readback inside the generic commit transaction.

There is one commit coordinator. The generic control-plane database wrapper locks and reauthorizes the immutable change set and actor/grant, validates and consumes the receipt, dispatches the catalog transaction participant, writes generic audit/readback records, and commits. The catalog participant never mints or consumes a receipt and never writes a second commit record.

The remote MCP adapter must never contain catalog SQL, pricing arithmetic, prompt policy, or field mapping. It validates the MCP contract, calls `OpsAgentDomainService`, and returns the parsed result.

## 4. Existing work that is retained

The merged Guided Catalog lineage already provides useful foundations:

- durable sessions, conversation history, answer revision/removal, and queued follow-ups;
- server-owned question templates;
- supplier-neutral evidence handling;
- scoped company-knowledge retrieval;
- live catalog snapshot hashes;
- guarded review/approval/commit/readback concepts;
- compact floating composer, transcript-owned scrolling, activity ripple, and response typewriter;
- an internal fail-closed OPS capability registry introduced by web commit `c055c285`.

The agent control plane branch already has the MCP SDK boundary and stable v1 contract foundation at commits `c53b4664`, `99b30cfc`, and `2969debe`.

These foundations are composed, not duplicated. The internal `src/lib/ops-capabilities/registry.ts` registry is migrated into the control-plane registry after that registry lands. It remains the active safety source until every Guided Catalog consumer has switched; then the old module is removed.

## 5. Current gaps this design closes

| Current behavior | Required behavior |
|---|---|
| The model may emit extensible `z.record(unknown)` action payloads | The model emits facts/question decisions; the server compiler emits strict actions |
| Guided setup omits pricing modifiers, bundle composition, product tax associations, and product archive | The service graph covers every released catalog module |
| Web pricing recognizes obsolete modifier names | Web/server use the production modifier enum under an explicit pricing-contract version |
| iOS and web differ on modifier triggers, minimum charges, and required options | Both run the same literal versioned conformance cases before a new contract becomes configurable |
| Released `add_flat` behavior already prices tier deltas per unit | Existing rows remain on legacy v1; corrected v2 semantics require dual readers and a compatibility-gated migration |
| Product-specific tax rows and customer quantity presentation are not executed by every quote surface | Those modules remain unavailable until web, iOS, portal/PDF, invoice, and export consumers pass conformance |
| Families, products, task types, taxes, rules, and archives commit in separate calls | One outer database transaction applies the whole service |
| Review shows counts and a few product fields | Review explains the service and proves it with editable sample quotes |
| Completion exits or asks for inventory | Completion offers `SET UP ANOTHER SERVICE` and `OPEN CATALOG` |
| A service has no durable aggregate identity | A service scope anchors membership, versioning, provenance, edit, and archive |
| The catalog-local capability manifest can drift from the new control plane | One registry derives availability from executable adapters and consumers |

## 6. Catalog service aggregate

### 6.1 Service scope

A catalog service is an internal aggregate, not a replacement for `products` or `task_types`. It groups the exact records Phase C manages as one unit.

`catalog_service_scopes` stores:

- stable service scope ID and company ID;
- operator-facing name and normalized identity key;
- lifecycle state (`active` or `archived`);
- monotonic version;
- primary task type when applicable;
- source/provenance summary;
- created/updated/archived actor and timestamps.

Typed membership tables store roots with real foreign keys:

- `catalog_service_product_members` for sellable and bundle products;
- `catalog_service_task_type_members` for task behavior;
- `catalog_service_family_members` for material families and their derived variant graph;
- `catalog_service_tax_rate_members` for explicit service tax references;
- a typed membership table for each future specialized binding whose existing table cannot be safely reached through an owned product.

Each membership stores the service scope ID, a typed target FK, its role, and ownership mode (`owned`, `shared`, or `referenced`). Product options/values/modifiers/materials/bundle rows and family options/values/variants/mappings are children of typed roots and are included through their verified FK graph; they are not polymorphic orphan references.

Ownership determines archive behavior:

- `owned`: created for this service and eligible for guarded archive with it;
- `shared`: explicitly shared with another service and never archived from one service alone;
- `referenced`: reused live data that remains untouched.

Existing catalog records created outside Phase C are never silently claimed. `CHANGE EXISTING SERVICE` discovers candidate roots and relationships, shows the exact proposed membership and ownership modes, and prepares an `adopt` change when no scope exists. Adoption and any requested edit commit atomically after one review/confirmation.

### 6.2 Service operations

Every prepared change declares one operation:

- `add`: create a new scope and its graph while reusing confirmed shared records;
- `adopt`: claim an operator-confirmed existing graph as a new scope, with optional edits in the same reviewed change set;
- `edit`: load the complete current scope graph, preserve omitted records, and apply an exact diff against an expected version;
- `archive`: show all affected owned members and every blocking/shared reference before confirmation.

Each session freezes its scope ID, operation, expected scope version, target entity versions, live snapshot hash, and capability revision. A second tab or later edit that changes any target makes the prepared revision stale.

## 7. Complete service graph

The kernel treats the following as modules. A module is configurable only when the registry proves a compiler, persistence adapter, runtime consumer, and readback verifier.

| Module | Catalog behavior |
|---|---|
| Product core | name, description, type/kind, SKU, category, customer price, cost, pricing-contract version, pricing unit, unit, minimum charge/quantity, active/favorite, storefront, BOM display, task link |
| Options | select, integer, and boolean options; values, defaults, audience, required state, pricing/recipe flags |
| Pricing modifiers | `add_per_unit`, `add_flat`, `add_per_count`, `multiply_unit_price`, with kind-correct triggers |
| Tax | explicit product tax treatment and rate association only after every quote/document runtime executes and snapshots it; until then, only existing company-default taxable behavior is configurable |
| Quote presentation | internal measurement quantity/unit kept for staff calculation; optional customer `1 @ total` presentation snapshotted per line only after web, iOS, portal/PDF, invoice, and export consumers execute it |
| Task behavior | reuse or create the exact task type when supported |
| Materials and recipes | pinned variants or family selectors, quantities, scaling option, notes, units |
| Bundles | required and suggested child products, quantities, order, pricing mode, rationale/compatibility where released |
| Stock structure | families, axes, values, variants, option joins, units, costs, thresholds, product mappings |
| Supplier/purchasing | supplier cost profile or purchasing rule only when a released consumer executes it |
| Specialized tools | product bindings only when the tool has a released configure adapter and runtime consumer |

Opening inventory counts and physical roll/offcut capture may remain a post-service continuation because they are observations of current stock, not the service definition. Phase C can offer that continuation only when its capability is available.

## 8. Capability availability

The registry distinguishes:

- `configure`: Phase C may ask questions, preview writes, and commit the capability;
- `discover_only`: Phase C may accurately describe a released tool when relevant but cannot propose a binding or write;
- `unavailable`: the capability is omitted from questions and proposals.

Availability is derived from executable evidence, not a hand-written optimistic flag. A catalog capability is `configure` only when all of these are true:

1. strict input and output contracts are registered;
2. the catalog compiler supports the module;
3. the atomic persistence adapter supports it;
4. every required released runtime consumer executes it;
5. those consumers pass the current contract/conformance revision and minimum-client gate;
6. readback verifies it;
7. rollout policy enables it for the actor/company.

Deck Designer remains `discover_only` until an actual catalog binding adapter and released runtime bridge pass those gates. Phase C may say what Deck Designer already does. It may not ask how to connect deck geometry, create `deck-geometry/v1` bindings, or claim that a quote will use Deck Designer until that becomes executable.

### 8.1 Stock and purchasing release boundary

Stock structure is already meaningful to released OPS-Web and iOS stock surfaces, but the new kernel must still prove that authored families, axes, values, variants, joins, mappings, units, costs, and thresholds survive persistence and produce the same visible stock/order behavior. Compiler support or database rows alone are not sufficient.

`catalog_supplier_cost_profiles` and `product_material_quantity_rules` currently have persistence/readback paths but no released quoting, material-demand, or purchasing consumer. They therefore remain `unavailable` while this work begins. They may move to `configure` only after the implementation also ships deterministic web/iOS resolvers, integrates them into the real cut-list/material-demand and suggested/draft-order paths, passes shared conformance vectors, and satisfies the minimum-client gate. Phase C must not ask supplier-cost, waste, coverage, package-rounding, or automated-purchasing questions before that release evidence exists.

Every resolved purchase-order line stores an immutable, versioned purchasing-resolution snapshot beside the requested quantity and unit cost. The server-owned save boundary copies the selected supplier profile, material rule, normalized inputs, calculation trace, currency, source hashes, and capability revision into that snapshot in the same transaction. Existing lines remain null rather than receiving invented history; draft edits recompute the complete tuple; sent/fulfilled lines never re-resolve from mutable catalog rules. Web and iOS render historical purchasing meaning from the snapshot, not current supplier rows.

Opening counts and physical rolls/offcuts/lots are operational observations, not part of the service-definition graph. They use a separate continuation and confirmation boundary after service commit.

## 9. Versioned pricing and quote contracts

### 9.1 Compatibility first

Released iOS and its Guided Catalog tier fixtures treat `add_flat` as a selected-option delta added to the unit price before quantity. Existing catalog rows and future quotes made from them must not be silently repriced. OPS therefore does not reinterpret `add_flat` as a once-per-line fee.

- `legacy_v1` preserves the exact released trigger and calculation behavior for every existing/null-version product.
- `catalog_v2` adds corrected boolean/max-only triggers, deterministic ordering, required-option blocking, rounding, minimum-charge traces, tax/presentation snapshots, and other cross-platform guarantees while retaining the existing per-unit meaning of `add_flat`.
- A future true line-level fee requires a new, unambiguous modifier kind and its own compatibility rollout; it cannot reuse `add_flat`.

Both web/server and iOS must be dual readers before any `catalog_v2` product is written. `catalog_v2` authoring remains unavailable until every supported quote/document consumer is customer-live with that reader or an enforceable minimum-client gate prevents an incompatible client from quoting it.

### 9.2 Inputs and triggers

The evaluator receives the frozen product and pricing-contract version, options, values, modifiers, configured choices, quantity, discount, and currency.

For `catalog_v2`:

- `select`: a modifier with `trigger_value_id` applies only when that exact option value is selected.
- `integer`: a modifier applies when the configured integer falls within its optional inclusive minimum/maximum; at least one bound is required for a bounded rule.
- `boolean`: an unbound modifier applies only when the configured value is true.
- A modifier cannot reference an option or value outside its product.
- Missing required options block quote resolution; they never silently use an unrelated value.

`legacy_v1` is frozen from released code and verified live data before implementation. Any existing boolean/max-only rows whose current outcome would change are reported and preserved until an explicit reviewed migration.

### 9.3 Calculation order

The `catalog_v2` pre-tax calculation is deterministic and preserves existing tier pricing:

```text
unit additions = sum(add_per_unit) + sum(add_flat) + sum(add_per_count * configured count)
unit multiplier = product(all multiply_unit_price amounts)
resolved unit price = money((base price + unit additions) * unit multiplier)
pre-discount extension = money(resolved unit price * quantity)
discounted extension = money(pre-discount extension * (1 - discount percent / 100))
line subtotal = max(minimum charge, discounted extension)
```

The resolver returns a structured trace containing every trigger, amount, intermediate subtotal, minimum-charge adjustment, and discount. Tax is resolved by the versioned document-tax runtime from the frozen line subtotal and selected line tax-rate snapshot; it is not invented inside the product resolver. The pricing and tax traces are used by sample quotes and snapshotted on real estimate/invoice lines so the result remains explainable after catalog edits.

### 9.4 Product-specific tax and customer presentation gate

Current quote creation uses one document/company default tax rate, and current customer documents do not reliably execute product-specific `product_tax_rates` or per-product `1 @ total` presentation. Until those consumers are upgraded and released:

- Phase C may set existing `is_taxable` behavior and may confirm an already-configured company default rate;
- Phase C may not claim it attached a product-specific tax rate;
- Phase C may not claim that internal square-foot pricing will display as `1 @ total` to customers;
- if the operator requests either behavior, Phase C states the current limitation and leaves the fact unresolved instead of fabricating a setting.

The complete runtime upgrade must snapshot a line's resolved tax rate/components and customer presentation independently from staff measurement quantity/unit. Web estimate/invoice editors, iOS, portal, PDF, exports/accounting mappings, and history must agree before the registry promotes either module to `configure`.

### 9.5 Cross-platform gate

Literal JSON fixtures cover both contract versions, select, integer-min, integer-max, boolean, multiple modifiers, negative adjustments, zero quantity, minimum charge, discount, GST-only/mixed taxable lines, `1 @ total`, missing required options, and rounding boundaries. Web/server and iOS must produce byte-equivalent normalized outputs for every case before the corresponding pricing, tax, or presentation capability is available.

## 10. Interview and compilation

### 10.1 Model boundary

The model may return:

- confirmed/unresolved/contradicted fact candidates with provenance;
- one server-owned question intent plus fact keys and labels;
- `ready_for_review` when it believes required facts are complete.

The model may not return:

- SQL/table names;
- database IDs it was not given;
- executable action payloads;
- capability availability;
- calculated prices or totals treated as authoritative;
- final approval or commit authority.

### 10.2 Durable question and answer identity

Every rendered question is a persisted immutable snapshot containing:

- `question_instance_id`;
- registered `intent_id`;
- service scope ID and service-graph revision;
- one unambiguous `subject_ref` pointing to the exact product/option/module under discussion;
- a registry-validated typed fact path;
- localized question/helper copy revision;
- quick-answer choices with stable `choice_id` and typed value/target IDs; display labels are never used as routing keys.

Every answer references the exact question instance and either a stable choice ID or typed free-text value. Revision/removal records explicit `supersedes_answer_id`/`superseded_by_answer_id` lineage. Refresh, queued follow-up, translation changes, repeated labels, and multi-product conversations cannot retarget an answer by array position or visible string.

### 10.3 Server-owned compiler

The kernel:

1. validates and merges fact candidates;
2. loads the complete live service graph;
3. resolves the current registry revision;
4. identifies required facts for each available module;
5. selects the next allowed question or rejects an unsupported intent;
6. compiles strict deterministic actions from confirmed facts;
7. computes the exact diff and archive impact;
8. runs pricing projections;
9. blocks review on ambiguity, contradiction, unsupported behavior, or incomplete required facts.

Question copy remains in the server-owned question policy and i18n dictionaries. Customers answer as trades business owners, not as developers describing schemas or internal tools.

## 11. Review experience

Review stays inside the familiar conversation. The transcript remains the only vertical scroll owner; the floating composer remains available for corrections.

The latest Phase C turn contains:

1. a concise plain-language summary of what the service will do;
2. a compact before/after disclosure for edits;
3. the modules that will be configured;
4. unresolved warnings, if any;
5. three server-calculated quote checks: `MINIMUM`, `BASE`, and `MODIFIER COVERAGE`, unless the operator supplied representative job scenarios;
6. the exact confirmation action.

The review does not lead with database counts. It leads with operator meaning, for example:

> Vinyl decking will start at $11.35 per sq ft with a $1,500 minimum. Customers choose a DekSmart colour. GST applies. Staff can adjust job quantity before sending.

### 11.1 Inline sample-quote editing

Two edit classes are explicit:

- **Scenario edits:** quantity, chosen options, and optional-line selection. These are explicitly labeled `TEST ONLY — DOES NOT CHANGE CATALOG`; they test a different job and do not change the catalog draft.
- **Catalog edits:** product name, customer price, cost, minimum charge, tax, modifier amount, product inclusion, and bundle composition. These revise the prepared service everywhere.

A catalog edit creates a new immutable change-set revision and proposal hash, recomputes every baseline quote check, invalidates any prior confirmation receipt, and keeps the earlier revision in audit history. Ephemeral scenario state and results live outside the immutable approval projection/hash; changing them cannot alter the confirmation summary or replace the hashed baseline checks. If an inline price/cost/tax field is edited, the UI classifies it as a catalog edit before saving it.

All money is calculated server-side. The browser never supplies an authoritative total.

### 11.2 Visual contract

The review uses OPS-Web design tokens and existing shared inputs:

- pure black canvas and hairline separation;
- Mohave 14px sentence-case content;
- JetBrains Mono for prices, quantities, and metadata;
- Cake Mono Light only for uppercase authority labels and actions;
- 5px input/button radii and 4px chips;
- left alignment throughout;
- steel-blue accent on the one commit action and focus rings only;
- no new shadows or decorative icons;
- Lucide icons at explicit semantic 16/20px sizes;
- `EASE_SMOOTH` only, with reduced-motion opacity fallbacks.

The composer uses the established compact contract: 14px Mohave entry text, 32px actions, 16px upload/send icons, `SEND` capped at 80px, tokenized edge/bottom insets, input radius, no box shadow, and a borderless subordinate upload action. Quick answers use 14px sentence-case Mohave at natural height. Navigation chips remain left-aligned on the approved frosted token surface.

Submitting never locks the composer. The user turn appears immediately; pending analysis is conveyed graphically on that turn without a loading sentence. Additional follow-ups are visibly queued in order and remain revisable/removable until processing begins.

The structured review expands naturally inside the transcript. It has no nested scroll region. Collapsible sections hide detail only; they never hide the current question, warnings, totals, or confirmation state.

The conversation owns the full available route height from its header boundary to the viewport bottom. Computed-layout tests assert those top/bottom bounds at every supported viewport. The route fixes its own height first; `dashboard-layout.tsx` changes only if measured ancestor constraints prevent route ownership. Transcript bottom padding is at least the measured floating composer/control-stack height plus the design-system gap, so the final text is never obscured.

Auto-follow is transcript-local and reading-safe:

- after the operator submits, keep that new answer and the resulting latest assistant turn visible;
- when content arrives asynchronously, follow only if the transcript was already bottom-pinned;
- if the operator scrolled up or expanded an older question, preserve the reading anchor and show a compact `JUMP TO LATEST` control;
- returning to the bottom re-enables follow mode;
- use direct transcript `scrollTop`/`scrollTo` behavior, never `scrollIntoView` or any API that can reposition an ancestor;
- reduced motion uses the same final position without smooth animation.

## 12. Change-set and confirmation lifecycle

The session state is:

```text
loading_live
  -> choosing_scope
  -> interviewing <-> retrying
  -> review_locked
  -> preflight
  -> awaiting_confirmation
  -> applying
  -> verifying
  -> complete
```

Any accepted catalog edit from `review_locked` or `awaiting_confirmation` returns to `preflight` with a new revision. A stale target, registry change, permission change, or source change returns to `interviewing` or a named attention state; it never commits the old proposal.

Internal Phase C uses the same change-set record and confirmation receipt as MCP. There is no second Phase C approval hash that independently authorizes the same mutation.

Two hashes have different jobs:

- `catalog_proposal_hash` is transport-neutral and covers the desired service graph, deterministic effects, baseline approval projection, targets, and capability revision;
- `change_set_hash` additionally binds the proposal to actor, company, client/grant, evidence, expiry, and confirmation context.

Internal and MCP adapters must produce the same `catalog_proposal_hash` and semantic projection for equivalent facts. Their authorization-bound `change_set_hash` values are expected to differ.

## 13. Atomic commit and readback

The browser or MCP host sends only the change-set ID, one-time confirmation receipt, and idempotency key. The server reloads the immutable payload.

The single generic control-plane commit RPC is the transaction coordinator:

1. locks the immutable change set and receipt;
2. reloads the stored actor/company/client/grant instead of trusting caller-supplied actor fields;
3. reauthorizes current membership, permission, OAuth scope/grant where applicable, capability revision, expiry, hashes, and target versions under lock;
4. invokes the private catalog transaction participant for a catalog capability;
5. the participant locks catalog targets in deterministic order, validates the complete graph again, applies task/tax/product/option/modifier/material/bundle/stock/typed-membership/archive effects, increments the service scope version, and returns normalized catalog readback;
6. the generic coordinator consumes the one-time receipt and writes the sole generic audit/commit/readback record;
7. the database commits all generic and catalog rows together and returns exact IDs, versions, hashes, and normalized graph.

The catalog participant owns no confirmation or generic audit state. It is a private database function callable only by the generic coordinator. The only PostgREST-callable wrapper is the generic commit RPC, declared with an explicit fixed `search_path` and security mode. Its migration must `REVOKE ALL`/`EXECUTE` from `PUBLIC`, `anon`, and `authenticated`, grant only `service_role`, and test direct anonymous/authenticated calls plus forged actor/company/grant arguments. `service_role` authority never substitutes for human/MCP actor authorization.

Any blocker raises and rolls back the outer transaction. Existing helper RPCs may be called inside this transaction, but no browser/server loop may commit subgraphs in separate network transactions.

Readback compares the normalized live graph to the prepared target graph, including absence checks for archives. A partial or mismatched readback is not `complete`.

## 14. MCP contract

The catalog write pair is:

- `prepare_catalog_service_change`
- `commit_catalog_service_change`

Imports are an input provenance mode of `prepare_catalog_service_change`, not a separate catalog rule engine. The prepare input supports `ops_source`, `model_transcribed`, and guided-session facts while preserving assurance labels.

The same prepared result contains:

- service operation and identity;
- plain-language summary;
- exact itemized diff;
- warnings/blockers;
- sample quote projections and pricing traces;
- source/evidence references;
- target versions and capability revision;
- Firebase-authenticated OPS approval URL, optionally presented through modern MCP `input_required` metadata;
- expiry and change-set ID.

The generic limit of 25 proposed writes applies to top-level business operations. One catalog service graph counts as one aggregate operation and uses catalog-specific bounded graph limits. It cannot be divided into multiple commits merely to fit the generic limit.

External exposure remains dark until OAuth, confirmation, host, adversarial, and catalog-specific conformance gates pass. Internal availability is separate from external exposure.

## 15. Add another, edit, and archive

After verified completion, the operator sees:

- `SET UP ANOTHER SERVICE` — starts a fresh add session with no stale service facts;
- `OPEN CATALOG` — returns to the catalog;
- inventory continuation only when an inventory capability is executable.

The catalog launcher also offers `CHANGE EXISTING SERVICE`. It loads service scopes and unscoped candidate service roots. For a scoped service, Phase C receives the complete live graph and asks only about the requested change. For an unscoped service, Phase C prepares an `adopt` change that shows exactly which products, task types, material families, shared rates, and child relationships will belong to the new scope and whether each root is owned/shared/referenced. Nothing becomes owned without that confirmation.

Archive always previews:

- which products disappear from new quotes/storefront;
- task, recipe, stock, bundle, and shared references;
- records that will remain because they are shared or referenced;
- historical estimates/invoices that remain frozen and untouched.

## 16. Failure and concurrency behavior

- A second tab cannot attach an answer to a different question or scope revision.
- A removed/superseded answer cancels its pending work and restores the correct current question/options.
- Provider failure leaves a retryable input ledger entry, not an endless loader.
- A capability revision change invalidates the draft and recompiles before review.
- A live catalog version change invalidates confirmation before the first write.
- Duplicate prepare calls return the same change-set revision when inputs and targets are identical.
- Duplicate commit calls return the original receipt/readback without applying twice.
- Network loss after commit is recovered by idempotent status/readback polling.
- Cross-company IDs and unowned service scopes fail before any domain query or write.
- Unsupported tool instructions are treated as untrusted input and cannot expand the registry.

## 17. Release proof

The capability cannot ship on claims alone. Required evidence:

- red/green unit tests for every compiler and pricing behavior;
- live-schema contract verification through Supabase tooling before writing migrations;
- local/test migration, RLS, transaction rollback, idempotency, stale-version, and readback tests;
- web/iOS versioned pricing, per-line tax, and customer-presentation conformance fixtures;
- compatibility proof that existing `add_flat` tier rows produce identical future quote totals;
- minimum-client/customer-live proof before enabling `catalog_v2`, product-specific tax, or `1 @ total` authoring;
- Guided Catalog component and complete catalog-related suites;
- type-check, lint, and production build;
- Playwright bounding-box and screenshot proof at 915×685, 1280×720, 1440×900, and a narrow responsive viewport;
- keyboard, screen-reader, focus, and reduced-motion checks;
- external MCP legacy/current protocol and confirmation-host tests while still dark;
- production deployment and customer-live proof only after Jackson explicitly authorizes push/deploy.

## 18. Decisions

- Reuse the shared control plane; do not build a catalog MCP beside it.
- Promote the existing OPS capability registry into the control-plane registry.
- Replace model-authored actions with a server-owned compiler.
- Treat one service as the atomic catalog authoring unit.
- Preserve released `add_flat` unit-price behavior; new semantics require a new version/kind rather than reinterpretation.
- Adopt existing unscoped services only through an explicit reviewed ownership change.
- Put the plain-language review and editable sample quotes inside the conversation.
- Let the generic control plane own the one confirmation receipt and transaction coordinator across Phase C and MCP.
- Keep Deck Designer discover-only until a real binding path is executable.
- Preserve completed services so railings can be set up now and vinyl can be added later.
