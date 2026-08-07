# Phase C Catalog Authoring + Agent Control Plane Integration Implementation Plan

> **For implementation agents:** REQUIRED SUB-SKILL: Use `custom-skills:executing-plans` to implement this plan task-by-task. Use isolated worktrees. Do not edit the active `ops-web-agent-control-plane` worktree until its current actor/email work is committed or moved. Do not apply production migrations, push, deploy, register an external MCP client, or expose catalog write tools without Jackson's explicit authorization.

**Goal:** Make Phase C capable of adding, changing, and archiving one complete catalog service at a time—including options, pricing modifiers, tax, materials, bundles, and supported tool bindings—through the same guarded OPS agent control plane used by REST and MCP. Every review must show plain-language consequences and editable, server-calculated sample quotes before one atomic, verified commit.

**Architecture:** `CatalogAuthoringKernel` is the catalog domain implementation beneath `OpsAgentDomainService`. Phase C calls the internal adapter directly; REST and MCP call their adapters. All three receive the same strict contracts, capability registry, immutable change sets, confirmation receipts, atomic service-level commit, and readback. The language model supplies evidence-backed facts and a server-owned question intent; it never authors database actions or authoritative prices.

**Tech stack:** Next.js 15, React 19, TypeScript 5.9, Vitest, Playwright, Supabase Postgres, the agent-control-plane Zod 4 contract boundary, existing OPS Zod 3 application schemas, Swift/SwiftData, XCTest, and the existing OPS-Web/iOS design systems.

**Required skills:** `custom-skills:executing-plans`, `superpowers:using-git-worktrees`, `superpowers:test-driven-development`, `superpowers:systematic-debugging` for any failure, `supabase:supabase`, `supabase:supabase-postgres-best-practices`, `plugin-dev:mcp-integration`, `ops-design`, `frontend-design:frontend-design`, `custom-skills:interface-design`, `custom-skills:ui-ux-pro-max`, `ops-copywriter:ops-copywriter`, `custom-skills:wizard-audit`, `animation-studio:animation-architect`, `animation-studio:web-animations`, `custom-skills:audit-design-system`, `superpowers:verification-before-completion`, and `superpowers:requesting-code-review`.

---

## Sources of truth

Read before implementation:

- `/Users/jacksonsweet/Projects/OPS/ops-software-bible/specs/2026-08-07-phase-c-catalog-authoring-control-plane-integration.md`
- `/Users/jacksonsweet/Projects/OPS/ops-software-bible/specs/2026-08-07-ops-agent-control-plane-mcp-foundation.md`
- `/Users/jacksonsweet/Projects/OPS/ops-software-bible/specs/plans/2026-08-07-ops-agent-control-plane-mcp-foundation-implementation.md`
- `/Users/jacksonsweet/Projects/OPS/ops-web/AGENTS.md`
- `/Users/jacksonsweet/Projects/OPS/ops-ios/AGENTS.md`
- `/Users/jacksonsweet/Projects/OPS/ops-design-system/project/DESIGN.md` before UI work
- the implementation worktree's `.interface-design/system.md` before modifying Guided Catalog UI

The design spec wins when this plan is terse. Production schema and released runtime behavior win over both; if either differs, verify the exact state, correct the design and plan, and do not guess.

---

## Execution gates

### Gate 0 — authorization boundaries

This plan is not authorization to mutate production or publish anything.

- [ ] Jackson explicitly authorizes implementation.
- [ ] Treat commit, push, production migration, deployment, MCP exposure, and App Store release as separate gates unless Jackson explicitly groups them.
- [ ] Use Supabase read tools to inspect schema/RLS; apply migrations only to local/test until separately authorized.
- [ ] Keep every catalog MCP write capability dark even after internal tests pass.
- [ ] Report any new vendor/tier cost before incurring it. This design adds no new paid service by default.

### Gate 1 — preserve parallel work

The current `ops-web-agent-control-plane` checkout contains active uncommitted actor/email work. Do not build catalog work in it until its owner lands or relocates that work.

- [ ] Fetch `origin` and record exact `origin/main`, control-plane branch, and Guided Catalog commit ancestry.
- [ ] Gate internal catalog integration on stable committed control-plane Tasks 3, 4, 10, 14, 17, and 18: actor authority, registry, domain service, internal adapter, change-set persistence, and prepare/confirm/commit/readback engine.
- [ ] Gate the MCP portion separately on stable committed control-plane Tasks 25–28. Catalog kernel and internal Phase C work may proceed earlier, but this plan must not create substitute MCP server/adapter files while those foundation tasks are absent.
- [ ] Create a new origin-based worktree, recommended path `/Users/jacksonsweet/Projects/OPS/ops-web-catalog-authoring-control-plane`, branch `feat/catalog-authoring-control-plane-20260808`.
- [ ] Integrate only committed control-plane work; never copy uncommitted files from the active control-plane checkout.
- [ ] Do not re-port `ops-web-receipt-upload`. Its Guided Catalog lineage is already in current `origin/main` through ancestor `f0736697`.
- [ ] Create a separate iOS worktree from current `origin/main`, recommended path `/Users/jacksonsweet/Projects/OPS/ops-ios-catalog-authoring-control-plane`, with its own `.spm-local`, `Secrets.xcconfig`, and DerivedData paths.
- [ ] Prove both worktrees are clean before editing.

### Gate 2 — live contract inventory

Use Supabase tooling read-only before defining any migration or RPC.

- [ ] Verify live columns, constraints, enums, RLS, grants, trigger behavior, FKs, and indexes for every table the service graph can touch.
- [ ] Verify the production migration ledger and choose timestamps newer than every applied migration.
- [ ] Inspect the canonical `catalog_setup_save` function body from the database and Bible mirror; do not rely on the partial web migration history.
- [ ] Snapshot existing signed/accepted estimate pricing behavior so the new resolver cannot rewrite financial history.
- [ ] Record the exact released web and iOS consumers for each capability. A missing consumer makes that module `discover_only` or `unavailable`.

Expected live pricing enums to re-verify, not assume:

```text
option kinds: select | integer | boolean
modifier kinds: add_per_unit | add_flat | add_per_count | multiply_unit_price
```

### Gate 3 — baseline proof

Before the first implementation commit:

```bash
cd /Users/jacksonsweet/Projects/OPS/ops-web-catalog-authoring-control-plane
npm test -- src/lib/products src/lib/catalog-setup/phase-c src/components/catalog/setup
npm run type-check

cd /Users/jacksonsweet/Projects/OPS/ops-ios-catalog-authoring-control-plane
xcodebuild test -project OPS.xcodeproj -scheme OPS \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' \
  -derivedDataPath /private/tmp/ops-catalog-authoring-baseline \
  -clonedSourcePackagesDirPath .spm-local \
  -only-testing:OPSTests/ProductConfigurationResolverTests \
  -only-testing:OPSTests/DesignToEstimateAdapterTests
```

Record exact failures and baseline-compare them later. Do not explain away new failures as pre-existing without reproducing them on the exact base commit.

---

## Invariants that every task must preserve

1. One change set owns one service scope and one operation: `add`, `adopt`, `edit`, or `archive`.
2. A service-level change is one aggregate operation even if it contains more than 25 database row effects. It may not be split to satisfy the generic 25-operation limit.
3. A change may mutate or archive only records explicitly owned by its service scope. Shared/referenced records remain intact.
4. Starting Vinyl after Railings preserves Railings and starts from newly verified live catalog state.
5. Catalog edits create a new immutable revision and invalidate the previous confirmation. Sample-scenario edits do not.
6. Server code calculates all prices, totals, material effects, diffs, hashes, and capability availability.
7. Phase C, REST, and MCP adapters contain no catalog SQL or pricing arithmetic.
8. Unsupported capabilities never become interview questions, proposal fields, or write actions.
9. Historical estimates and invoices keep frozen price/tax meaning after catalog edits.
10. Existing/null-version products retain released pricing behavior; no modifier meaning changes in place.
11. The generic control-plane engine is the sole confirmation/receipt/audit coordinator; the catalog participant owns only catalog validation, effects, and catalog readback.
12. Transport-neutral catalog proposal hashes may match across adapters; actor/grant-bound change-set hashes must not be expected to match.
13. No UI task is complete without design-token, geometry, accessibility, and reduced-motion proof.

---

## Phase 1 — freeze pricing semantics across every released consumer

### Task 1: Define the versioned canonical pricing contract and golden vectors

**Web files:**

- Create: `src/lib/products/product-configuration-contract.ts`
- Create: `src/lib/products/__fixtures__/product-configuration-contracts.json`
- Create: `src/lib/products/__tests__/product-configuration-contract.test.ts`
- Modify: `src/lib/types/product-options.ts`

**iOS files:**

- Create: `OPSTests/Fixtures/Catalog/product-configuration-contracts.json`
- Create: `OPSTests/Catalog/ProductConfigurationContractTests.swift`

- [ ] Write `legacy_v1` vectors from the exact released iOS resolver/tier tests and verified live rows before proposing new behavior. Explicitly prove a two-unit `$180 + $50 add_flat` tier remains `$460`, not `$410`.
- [ ] Add `catalog_v2` vectors for select, integer minimum/maximum/inclusive range, max-only, boolean true/false, all four existing modifier kinds, multiple modifiers, deterministic ordering, negative adjustments, zero/negative quantity guards, missing required choices, default selection, discount, minimum charge, and half-cent rounding boundaries.
- [ ] Preserve `add_flat` as a unit-price delta in both versions. A true once-per-line fee requires a new future modifier kind; this plan must not reinterpret live rows.
- [ ] Pin `contract_version`, normalized output shape, and fixture hashes. The iOS fixture must be byte-for-byte identical to the web fixture.
- [ ] Assert cross-option/value trigger references fail closed.
- [ ] Audit live boolean/max-only rows. If corrected `catalog_v2` triggers would change them, keep those products on `legacy_v1` and include an explicit adoption/migration diff; never silently opt them into v2.
- [ ] Run the new web test and XCTest. Expected: fail because the versioned contract and fixture reader do not exist.
- [ ] Implement only schemas/types and fixture loading in this task. Do not yet change runtime calculations.
- [ ] Verify fixture identity:

```bash
cmp src/lib/products/__fixtures__/product-configuration-contracts.json \
  ../ops-ios-catalog-authoring-control-plane/OPSTests/Fixtures/Catalog/product-configuration-contracts.json
```

- [ ] Commit separately in each repository:

```bash
git commit -m "test(catalog): freeze pricing conformance contract"
```

### Task 2: Replace the web/server pricing resolver with the canonical evaluator

**Files:**

- Modify: `src/lib/products/product-configuration-resolver.ts`
- Modify: `src/lib/products/__tests__/product-configuration-resolver.test.ts`
- Modify: `src/lib/api/services/product-configuration-service.ts`
- Modify: `src/lib/hooks/use-product-configuration.ts`
- Modify: `src/components/ops/product-configuration-fields.tsx`
- Modify: `src/components/ops/line-item-editor.tsx`
- Modify: `src/components/ops/__tests__/line-item-editor-pricing.test.ts`
- Modify: `tests/integration/configured-estimate-line.test.ts`

- [ ] Add failing tests proving the resolver rejects obsolete `set_price`, `add_percent`, and `multiply`, dispatches by pricing-contract version, maps `trigger_int_min/max`, supports v2 boolean/max-only triggers, preserves v1 trigger behavior, keeps `add_flat` in unit price, and returns a structured calculation trace.
- [ ] Implement the calculation order in the design spec using integer minor units or one explicit cent-rounding primitive.
- [ ] Make missing required options a blocker, not a zero-price or fallback result.
- [ ] Load every modifier field from Supabase; do not discard integer trigger bounds.
- [ ] Make the line-item editor consume the evaluator result rather than duplicate quantity/minimum logic.
- [ ] Run focused resolver, line-editor, and configured-estimate integration tests.
- [ ] Commit:

```bash
git commit -m "fix(catalog): unify web configurable pricing semantics"
```

### Task 3: Persist pricing-contract version and an explainable line snapshot without changing history

**Files:**

- Create: `supabase/migrations/<timestamp>_catalog_pricing_contract_and_line_trace.sql`
- Create: `tests/unit/supabase/catalog-pricing-contract-and-line-trace-migration.test.ts`
- Modify: `src/lib/api/services/estimate-service.ts`
- Modify: `src/lib/types/database.types.ts` only from generated schema output
- Modify: `tests/integration/configured-estimate-line.test.ts`
- Mirror after local verification: `ops-software-bible/migrations/<same-file>.sql`

- [ ] Re-read live `line_items` schema, accepted/signed estimate invariants, invoice copy behavior, and tax relationships.
- [ ] Write a failing migration contract for additive `products.pricing_contract_version` (existing/null rows normalize to `legacy_v1`) plus nullable `line_items.resolved_pricing_snapshot jsonb`, validation/version shape, RLS/grants, and preservation through estimate-to-invoice flows.
- [ ] Apply locally/test only.
- [ ] Snapshot the authoritative contract version and calculation trace when a configurable catalog product becomes a real line item. Never recalculate historical lines from the current catalog.
- [ ] Verify old rows remain valid and new rows round-trip exactly.
- [ ] Commit:

```bash
git commit -m "feat(catalog): snapshot resolved line-item pricing"
```

### Task 4: Bring iOS pricing and estimate consumers to conformance

**Files:**

- Modify: `OPS/Services/ProductConfigurationResolver.swift`
- Modify: `OPSTests/Catalog/ProductConfigurationResolverTests.swift`
- Modify: `OPSTests/Catalog/ProductConfigurationContractTests.swift`
- Modify as required: `OPS/DataModels/Supabase/Catalog/ProductOption.swift`
- Modify as required: `OPS/DataModels/Supabase/Catalog/ProductOptionValue.swift`
- Modify as required: `OPS/DataModels/Supabase/Catalog/ProductPricingModifier.swift`
- Modify: `OPS/DataModels/Supabase/Product.swift`
- Modify: `OPS/Network/Supabase/DTOs/ProductDTOs.swift`
- Modify: `OPS/Network/Supabase/DTOs/ProductExtensionDTOs.swift`
- Modify: `OPS/Network/Supabase/Repositories/ProductRichnessRepository.swift`
- Modify: `OPS/Views/Estimates/LineItemEditSheet.swift`
- Modify: `OPS/Services/DesignToEstimateAdapter.swift`
- Modify: `OPSTests/Catalog/DesignToEstimateAdapterTests.swift`
- Modify: `OPS/Network/Supabase/DTOs/EstimateDTOs.swift`
- Modify: `OPS/DataModels/Supabase/EstimateLineItem.swift`
- Run: `OPSTests/GuidedCatalogSetupTierTests.swift`
- Run: `OPSTests/Catalog/RecipeResolverTests.swift`

- [ ] Make the Swift evaluator consume every golden vector and produce the same normalized result/trace as TypeScript.
- [ ] Implement dual `legacy_v1`/`catalog_v2` readers. Preserve v1 `add_flat`/trigger totals exactly; implement v2 boolean, min-only/max-only integer triggers, `add_per_count`, deterministic modifier ordering, required options, minimum charge, discount, and trace output.
- [ ] Make both manual line editing and Deck Designer estimate adaptation call the resolver instead of recomputing totals.
- [ ] Preserve CRLF/mixed line endings in existing Swift files.
- [ ] Run the focused XCTest set with an isolated DerivedData path, then a generic-device build.
- [ ] Commit:

```bash
git commit -m "fix(catalog): align iOS configured pricing contract"
```

### Task 4A: Make product tax and `1 @ total` presentation executable end to end

**Web files:**

- Create: `src/lib/tax/document-tax-resolver.ts`
- Create: `src/lib/tax/__tests__/document-tax-resolver.test.ts`
- Modify/retire: `src/lib/tax/estimate-tax.ts`
- Modify: `src/lib/types/pipeline.ts`
- Modify: `src/components/ops/create-estimate-modal.tsx`
- Modify: `src/components/ops/line-item-editor.tsx`
- Modify: `src/components/books/modals/estimate-form-modal.tsx`
- Modify: `src/components/books/modals/invoice-form-modal.tsx`
- Modify: `src/lib/api/services/estimate-service.ts`
- Modify: `src/lib/api/services/invoice-service.ts`
- Modify: `src/components/portal/portal-estimate-view.tsx`
- Modify: `src/lib/pdf/render-document-html.ts`
- Modify: `src/lib/api/services/qbo-push-mappers.ts`
- Add/modify corresponding unit, integration, portal, PDF, and accounting-map tests

**Schema:**

- Create: `supabase/migrations/<timestamp>_line_tax_and_quote_presentation_snapshots.sql`
- Create: `tests/unit/supabase/line-tax-and-presentation-migration.test.ts`
- Modify generated: `src/lib/types/database.types.ts`

**iOS files:**

- Modify: `OPS/DataModels/Supabase/Product.swift`
- Modify: `OPS/Network/Supabase/DTOs/ProductDTOs.swift`
- Modify: `OPS/DataModels/Supabase/EstimateLineItem.swift`
- Modify: `OPS/DataModels/Supabase/InvoiceLineItem.swift`
- Modify: `OPS/DataModels/Supabase/Estimate.swift`
- Modify: `OPS/Network/Supabase/DTOs/EstimateDTOs.swift`
- Modify: `OPS/Network/Supabase/DTOs/InvoiceDTOs.swift`
- Modify: `OPS/Views/Estimates/LineItemEditSheet.swift`
- Modify: `OPS/Views/Estimates/EstimateFormSheet.swift`
- Modify: `OPS/Views/Estimates/EstimateDetailView.swift`
- Create: `OPSTests/Catalog/DocumentTaxContractTests.swift`
- Create: `OPSTests/Catalog/QuotePresentationContractTests.swift`
- Modify relevant share/export rendering tests and estimate/invoice repository tests

- [ ] Start with failing end-to-end fixtures proving GST-only 5%, non-taxable lines, multiple line tax components, mixed rates, discounts/minimums, estimate-to-invoice copying, PDF/portal totals, and QuickBooks mapping never disagree.
- [ ] Add an additive product `quote_presentation_mode` whose default preserves current detailed quantity/unit-price output. Add frozen line tax and customer-presentation snapshots; retain actual staff measurement quantity/unit/price on the line.
- [ ] For `single_total`, customer documents render quantity `1` and one pre-tax line price/total while staff editing and the pricing trace retain the real square-foot quantity and unit rate. Never overwrite the internal measurement to fake the display.
- [ ] Resolve explicit `product_tax_rates` into ordered frozen line components. Aggregate and snapshot the document tax breakdown; do not derive a signed/historical document from current tax rows.
- [ ] Update every web and iOS estimate/invoice/customer/export consumer together. A surface that cannot faithfully map mixed components must fail closed or use an explicitly verified mapping—not collapse them silently.
- [ ] Keep both registry modules `unavailable` until the compatible web deployment and iOS build are customer-live and incompatible supported clients are blocked. Before then, Phase C may only use existing `is_taxable` plus an already-configured company default and must say that product-specific tax/`1 @ total` is unresolved.
- [ ] Commit schema/runtime and iOS changes atomically within each repository with cross-platform fixture proof.

**Phase 1 pricing gate:** Do not write `catalog_v2` or advertise its additional modifier behavior until web/server and iOS pass the exact fixture revision and every supported customer client can read it. If an enforceable minimum-client gate does not exist, keep v2 authoring unavailable.

**Phase 1 tax/presentation gate:** Do not advertise product-specific tax or `1 @ total` until every named runtime above passes the shared fixtures and the compatibility release gate is proven customer-live.

---

## Phase 2 — build the transport-independent Catalog Authoring Kernel

### Task 5: Add durable service scope and ownership schema

**Files:**

- Create: `supabase/migrations/<timestamp>_catalog_service_scopes.sql`
- Create: `tests/unit/supabase/catalog-service-scopes-migration.test.ts`
- Modify generated: `src/lib/types/database.types.ts`
- Mirror after local verification: `ops-software-bible/migrations/<same-file>.sql`

- [ ] Verify every member table's company key, soft-delete/archive convention, FK behavior, and version signal from live schema.
- [ ] Write failing schema/RLS tests for `catalog_service_scopes` plus typed product/task-type/family/tax/specialized-binding membership tables. Do not use an unenforceable polymorphic `entity_kind + entity_id` FK.
- [ ] Store stable service identity, lifecycle, monotonic version, provenance, actor stamps, typed root FKs, role, and `owned|shared|referenced` ownership. Child options/modifiers/materials/bundle rows and variants/mappings are reached through verified root FKs.
- [ ] Add uniqueness, typed FKs, company consistency constraints/triggers, and indexes that prevent duplicate active scope identities, two active owners, or cross-company membership even under service-role writes.
- [ ] Existing records remain unclaimed until an operator-approved `adopt` change set names the exact roots and ownership modes.
- [ ] Apply local/test only, regenerate types, and prove anon/Firebase JWT requests cannot bypass company/role rules.
- [ ] Commit:

```bash
git commit -m "feat(catalog): add versioned service ownership scopes"
```

### Task 6: Define strict catalog service contracts

**Files:**

- Create: `src/lib/catalog-authoring/contracts/service-graph.ts`
- Create: `src/lib/catalog-authoring/contracts/service-change.ts`
- Create: `src/lib/catalog-authoring/contracts/review-projection.ts`
- Create: `src/lib/catalog-authoring/contracts/index.ts`
- Create: `src/lib/catalog-authoring/__fixtures__/railing-service.ts`
- Create: `src/lib/catalog-authoring/__fixtures__/vinyl-service.ts`
- Create: `src/lib/catalog-authoring/__fixtures__/existing-mixed-catalog.ts`
- Create: `src/lib/catalog-authoring/__tests__/service-graph.test.ts`

- [ ] Write strict-schema tests first, including unknown-key rejection, stable client references, exact money/currency representation, add/adopt/edit/archive operations, typed root ownership, expected versions, archives, source evidence, tool bindings, and baseline/test scenarios.
- [ ] Model the complete graph: task link, product core, pricing-contract version, internal measurement and customer presentation, options/values, pricing modifiers, explicit product tax policy, materials/recipes, bundles, catalog families/options/values/variants/mappings, supported purchasing fields, supported tool bindings, and archive intent.
- [ ] Prohibit implicit deletion. Every archive is an explicit effect with ownership and reference evidence.
- [ ] Keep domain contracts independent from MCP SDK schemas. Parsed plain values cross the boundary.
- [ ] Commit:

```bash
git commit -m "feat(catalog): define complete service authoring contracts"
```

### Task 7: Load the complete live service graph and preservation context

**Files:**

- Create: `src/lib/catalog-authoring/load-live-service-graph.ts`
- Create: `src/lib/catalog-authoring/catalog-service-repository.ts`
- Create: `src/lib/catalog-authoring/__tests__/preserve-other-services.test.ts`
- Modify: `src/lib/catalog-setup/phase-c/live-catalog-context.ts`
- Modify: `src/lib/catalog-setup/phase-c/session-service.ts`

- [ ] Write failing repository tests for a company with Railings, Vinyl, shared tax rates, shared families, bundle references, and externally-created products.
- [ ] Load all service modules plus references from other services that constrain edit/archive behavior.
- [ ] Include `product_bundle_items`, `product_tax_rates`, modifiers, recipes, mappings, and scope membership; do not summarize away records needed for exact diff/readback.
- [ ] Discover unscoped candidate service roots for adoption without assigning ownership. Return the exact candidate graph and ambiguous/shared relationships for operator review.
- [ ] Freeze scope version, entity versions, live snapshot hash, and capability revision in session/change-set state.
- [ ] Prove adding Vinyl leaves every Railing record byte-equivalent and that archiving Vinyl cannot remove a shared family or rate.
- [ ] Commit:

```bash
git commit -m "feat(catalog): load scoped service graphs without collateral changes"
```

### Task 8: Consolidate capability truth into the control-plane registry

**Files:**

- Create/complete: `src/lib/agent-control-plane/registry/capability-types.ts`
- Create/complete: `src/lib/agent-control-plane/registry/capability-manifest.ts`
- Create/complete: `src/lib/agent-control-plane/registry/read-tools.ts`
- Create/complete: `src/lib/agent-control-plane/registry/write-tools.ts`
- Create: `src/lib/catalog-authoring/module-registry.ts`
- Create: `src/lib/catalog-authoring/__tests__/module-registry.test.ts`
- Modify: `src/lib/catalog-setup/phase-c/catalog-capability-manifest.ts`
- Modify: `src/lib/ops-capabilities/registry.ts`
- Run: current registry and Phase C capability tests

- [ ] First land/integrate the control-plane registry task from its owning branch; do not recreate it independently.
- [ ] Write invariant tests: `configure` requires strict contract, validator, compiler, persistence handler, readback handler, every required released runtime consumer, conformance/minimum-client revision, and rollout permission. Product tax and customer presentation remain unavailable if any web/iOS/portal/PDF/invoice/export witness is missing.
- [ ] Expose `discover_only` separately from `configure`; never let discoverability produce a setup question or write.
- [ ] Move current Deck Designer/released-tool knowledge into this registry. Keep Deck Designer `discover_only` until a real catalog binding and runtime bridge meet every gate.
- [ ] Make Guided Catalog derive its manifest from this registry. Delete the old hand-authored registry only after `rg` proves every consumer migrated.
- [ ] Prove removing any implementation witness automatically downgrades the capability.
- [ ] Commit:

```bash
git commit -m "feat(agent-control-plane): unify catalog capability truth"
```

### Task 9: Build deterministic graph validation and compilation modules

**Files:**

- Create: `src/lib/catalog-authoring/validate-service-graph.ts`
- Create: `src/lib/catalog-authoring/compile-service-change.ts`
- Create: `src/lib/catalog-authoring/modules/core-products.ts`
- Create: `src/lib/catalog-authoring/modules/task-behavior.ts`
- Create: `src/lib/catalog-authoring/modules/configurable-pricing.ts`
- Create: `src/lib/catalog-authoring/modules/stock-structure.ts`
- Create: `src/lib/catalog-authoring/modules/materials-recipes.ts`
- Create: `src/lib/catalog-authoring/modules/bundles.ts`
- Create: `src/lib/catalog-authoring/modules/supplier-purchasing.ts`
- Create: `src/lib/catalog-authoring/modules/tax-policy.ts`
- Create: `src/lib/catalog-authoring/modules/quote-presentation.ts`
- Create: `src/lib/catalog-authoring/modules/tool-bindings.ts`
- Create: `src/lib/catalog-authoring/__tests__/validate-service-graph.test.ts`
- Create: `src/lib/catalog-authoring/__tests__/compile-service-change.test.ts`
- Create: `src/lib/catalog-authoring/__tests__/stock-structure.test.ts`
- Create: `src/lib/catalog-authoring/__tests__/supplier-purchasing.test.ts`
- Modify/delegate: `src/lib/catalog-setup/commit/payload-builder.ts`
- Modify/delegate: `src/lib/catalog-setup/commit/payload-builder.types.ts`
- Modify/delegate: `src/lib/catalog-setup/phase-c/execution-plan.ts`
- Modify/delegate: `src/lib/catalog-setup/phase-c/reconcile.ts`

- [ ] Write one red test per released module and every illegal reference/unsupported module case.
- [ ] Make `stock-structure.ts` compile create/update/archive effects for catalog families, option axes, option values, variants, variant-option joins, product-option mappings, units, SKU/cost fields, and warning/critical thresholds. Its tests must prove complete readback, shared-record preservation, deterministic matrix identity, duplicate-signature rejection, and exact threshold inheritance/override behavior.
- [ ] Make `supplier-purchasing.ts` compile create/update/archive effects for `catalog_supplier_cost_profiles` and `product_material_quantity_rules`, including default-profile uniqueness, variant/material ownership, calculation kind, measure source, required inputs, coverage, waste, purchase rounding, package quantity, activation/fallback rules, and provenance. Its tests must prove exact persistence/readback and reject rules that no released consumer can execute.
- [ ] Use stable client references during compilation; resolve database IDs only inside the guarded repository/RPC boundary.
- [ ] Compile explicit create/update/archive effects and a normalized target graph. Do not force every product to own a family or task type when the released data model does not.
- [ ] Remove illegal `text` option support; compile only verified live option/modifier kinds.
- [ ] Extend the existing payload builder only as a temporary implementation primitive. The kernel is the public domain boundary; no second compiler may survive.
- [ ] Prove compilation is deterministic across object key order and identical inputs.
- [ ] Commit:

```bash
git commit -m "feat(catalog): compile complete service changes deterministically"
```

### Task 9A: Complete stock and purchasing runtime consumers before capability exposure

**OPS-Web files:**

- Create: `supabase/migrations/<timestamp>_catalog_order_item_purchasing_snapshot.sql`
- Create: `tests/unit/supabase/catalog-order-item-purchasing-snapshot-migration.test.ts`
- Create: `src/lib/catalog/material-quantity-rule-resolver.ts`
- Create: `src/lib/catalog/supplier-cost-profile-resolver.ts`
- Create: `src/lib/catalog/__fixtures__/purchasing-rule-contracts.json`
- Create: `src/lib/catalog/__tests__/material-quantity-rule-resolver.test.ts`
- Create: `src/lib/catalog/__tests__/supplier-cost-profile-resolver.test.ts`
- Modify/regenerate: `src/lib/types/database.types.ts`
- Modify: `src/lib/api/services/catalog-stock-service.ts`
- Modify: `src/lib/api/services/metrics-service.ts`
- Modify: `src/lib/catalog-setup/phase-c/session-service.ts`
- Modify: `src/lib/catalog-setup/phase-c/readback-verifier.ts`

**iOS files:**

- Create: `OPS/DataModels/Supabase/Catalog/CatalogSupplierCostProfile.swift`
- Create: `OPS/DataModels/Supabase/Catalog/ProductMaterialQuantityRule.swift`
- Create: `OPS/Network/Supabase/DTOs/CatalogPurchasingDTOs.swift`
- Create: `OPS/Network/Supabase/Repositories/CatalogPurchasingRepository.swift`
- Create: `OPS/Services/MaterialQuantityRuleResolver.swift`
- Create: `OPS/Services/SupplierCostProfileResolver.swift`
- Create: `OPSTests/Fixtures/Catalog/purchasing-rule-contracts.json`
- Create: `OPSTests/Catalog/MaterialQuantityRuleResolverTests.swift`
- Create: `OPSTests/Catalog/SupplierCostProfileResolverTests.swift`
- Create after re-verifying the latest schema number: `OPS/DataModels/Migrations/OPSSchemaV23.swift` (or the next unused version)
- Create: `OPSTests/DataModels/CatalogPurchasingSnapshotMigrationTests.swift`
- Modify: `OPS/DataModels/Supabase/Catalog/CatalogOrderItem.swift`
- Modify: `OPS/Network/Supabase/DTOs/CatalogOrderDTOs.swift`
- Modify: `OPS/Services/RecipeResolver.swift`
- Modify: `OPS/Services/CutListMaterializer.swift`
- Modify: `OPS/Views/Catalog/Orders/OrdersSheet.swift`
- Modify: `OPS/DeckBuilder/Views/VinylOrderSheet.swift`
- Modify: `OPS/DataModels/Migrations/OPSSchemaCommon.swift`
- Modify: `OPS/DataModels/Migrations/OPSMigrationPlan.swift`
- Modify: `OPS/Network/Sync/InboundProcessor.swift`
- Modify: `OPS/Network/Sync/RealtimeProcessor.swift`
- Modify: `OPS/Utilities/DataActor.swift`

- [ ] Freeze shared golden vectors for every supported material calculation and supplier-profile selection. Web and iOS must return the same required material, waste, rounded purchase quantity, selected supplier cost, currency, and explanation trace.
- [ ] Execute `product_material_quantity_rules` in the real material-demand/cut-list path. A rule is not released merely because Phase C can persist it or a sample quote can preview it.
- [ ] Add nullable `catalog_order_items.purchasing_resolution_snapshot jsonb` with an object check and an explicit schema version. Existing rows remain null—never fabricate historical supplier/rule evidence. For new resolved lines the snapshot copies the selected supplier profile ID/key/label, currency and unit cost; material-rule ID and executable fields; normalized inputs; raw, waste-adjusted, and purchase-rounded quantities; contract/capability revision; source hashes; and resolution timestamp.
- [ ] Add a guarded database save boundary that resolves the supplier/rule from live rows, verifies expected versions/hashes, and writes `quantity_requested`, `cost_per_unit`, and the snapshot together. Do not accept an authoritative client-computed snapshot. Allow an explicit draft edit to recompute all three together; reject snapshot mutation once the parent order leaves `draft`.
- [ ] Execute `catalog_supplier_cost_profiles` in the real suggested/draft purchasing path. Resolve the default/activation rule deterministically and render from the stored order-line snapshot after save; later profile/rule edits or deletion must not rewrite an existing order.
- [ ] Test migration shape, strict snapshot schema, company isolation, concurrent profile/rule change, draft recomputation, sent/fulfilled immutability, deletion preservation, and exact database -> generated TypeScript -> Swift DTO/model -> SwiftData round-trip before capability promotion.
- [ ] Prove the current stock consumers read Phase C-authored families, variants, option joins, quantities, units, costs, and thresholds correctly in OPS-Web stock/metrics and iOS STOCK/order surfaces.
- [ ] Add contract/conformance revision checks and a minimum-client gate for every new web/iOS reader. Until those readers are customer-live—or an enforceable minimum version excludes older clients—the registry must return `unavailable`, Phase C must not ask about the module, and prepare must reject it.
- [ ] Keep opening counts, actual rolls/offcuts, lots, and locations outside the service-definition commit. Offer them only as a separately confirmed continuation after the service is committed and only when that inventory capability is released.
- [ ] Add end-to-end readback tests from authored graph -> atomic rows -> runtime resolver -> operator-visible stock/order result. A stored-but-unused rule fails the release gate.
- [ ] Commit web and iOS changes atomically in their respective repositories, with the registry remaining dark until both commits and the compatibility gate are proven.

```bash
git commit -m "feat(catalog): execute authored stock and purchasing rules"
```

### Task 10: Project plain-language review and editable sample quotes

**Files:**

- Create: `src/lib/catalog-authoring/project-service-review.ts`
- Create: `src/lib/catalog-authoring/__tests__/project-service-review.test.ts`
- Reuse: `src/lib/products/product-configuration-resolver.ts`
- Reuse: `src/lib/tax/document-tax-resolver.ts`

- [ ] Write failing projections for deterministic `MINIMUM`, `BASE`, and `MODIFIER COVERAGE` Railing/Vinyl checks, including every available modifier, minimum charge, tax behavior, quote presentation, bundle child, material/stock effect, supplier cost/purchasing rule, and preserved service. Use `SMALL/TYPICAL/COMPLEX` only when those scenarios come from operator-confirmed facts.
- [ ] Generate server-owned baseline checks that cover otherwise-hidden modifier branches without claiming invented quantities are typical jobs.
- [ ] Separate immutable baseline approval checks from ephemeral test-scenario state and catalog edits. Scenario quantity/options recompute only the labeled `TEST ONLY` result outside the proposal/change-set hash; catalog fields create a new service-change revision and baseline projection.
- [ ] Return a structured trace for each line: contract version, base, triggered unit adjustments, multiplier, extension, discount, minimum, tax components, internal measurement, customer presentation, and total.
- [ ] Include concise operator meaning, exact before/after differences, reused/shared records, archive impact, unresolved warnings, and blockers.
- [ ] Use `ops-copywriter:ops-copywriter` for every customer-facing sentence and label.
- [ ] Commit:

```bash
git commit -m "feat(catalog): project reviewable service and quote outcomes"
```

---

## Phase 3 — use the shared control plane for every catalog mutation

### Task 11: Add catalog contracts to the control-plane boundary

**Files:**

- Create: `src/lib/agent-control-plane/contracts/catalog.ts`
- Modify: `src/lib/agent-control-plane/contracts/index.ts`
- Create: `src/lib/agent-control-plane/contracts/__tests__/catalog.test.ts`

- [ ] Add strict Zod 4 MCP-boundary schemas for `get_catalog_authoring_capabilities`, `prepare_catalog_service_change`, `commit_catalog_service_change`, status, and readback.
- [ ] Inputs accept `add|adopt|edit|archive`, identity/scope, evidence-backed facts, provenance mode, expected version, and idempotency key. They never accept SQL, table names, arbitrary action payloads, authoritative totals, or a client-supplied `confirmed` boolean.
- [ ] Results distinguish transport-neutral `catalog_proposal_hash` from actor/grant-bound `change_set_hash` and contain normalized diff, immutable baseline review projection, warnings/blockers, capability revision, target versions, change-set ID, expiry, confirmation metadata, and exact readback.
- [ ] Freeze compatible v1 fixtures and unknown-field rejection.
- [ ] Commit:

```bash
git commit -m "feat(agent-control-plane): add catalog service contracts"
```

### Task 12: Integrate catalog prepare with the generic change-set engine

**Files:**

- Create: `src/lib/agent-control-plane/services/prepare-catalog-service-change.ts`
- Create: `src/lib/agent-control-plane/services/__tests__/catalog-service-change.test.ts`
- Modify: `src/lib/agent-control-plane/services/domain-service.ts`
- Modify: `src/lib/agent-control-plane/services/create-domain-service.ts`
- Reuse: `src/lib/agent-control-plane/changes/normalize-change-set.ts`
- Reuse: `src/lib/agent-control-plane/changes/prepare.ts`

- [ ] First integrate stable control-plane Tasks 17/18; do not fork their change-set or receipt implementation.
- [ ] Write adapter-parity tests showing equivalent internal Phase C and MCP-shaped facts produce the same normalized graph/effects, immutable baseline projection, and transport-neutral `catalog_proposal_hash`. Their actor/client/grant-bound `change_set_hash` values are expected to differ.
- [ ] Treat one service graph as one aggregate business operation with catalog-specific graph bounds. Reject oversized/recursive graphs, but never split one service into partial commits to meet the generic 25-operation limit.
- [ ] Compute `catalog_proposal_hash` from scope/version, capability revision, live snapshot, normalized graph/effects, targets, and immutable baseline approval projection. Compute `change_set_hash` by additionally binding actor/company/client/grant, evidence, expiry, and confirmation context.
- [ ] Keep ephemeral `TEST ONLY` scenario inputs/results outside both hashes and outside the immutable approval projection. Catalog edits create a new immutable revision and revoke prior confirmation; scenario-only edits do neither and cannot change what the confirmation summarizes.
- [ ] Commit:

```bash
git commit -m "feat(agent-control-plane): prepare atomic catalog service changes"
```

### Task 13: Add the catalog transaction participant to the generic atomic commit RPC

**Files:**

- Create: `supabase/migrations/<timestamp>_catalog_authoring_service_change.sql`
- Create: `tests/unit/supabase/catalog-authoring-service-change-migration.test.ts`
- Create: `src/lib/catalog-authoring/apply-service-change.ts`
- Create: `src/lib/catalog-authoring/readback-service-change.ts`
- Create: `src/lib/catalog-authoring/__tests__/apply-service-change.test.ts`
- Create: `src/lib/catalog-authoring/__tests__/readback-service-change.test.ts`
- Modify: `src/lib/catalog-setup/phase-c/commit-service.ts`
- Modify: `src/lib/catalog-setup/phase-c/supabase-commit-adapter.ts`
- Modify: `src/lib/catalog-setup/phase-c/readback-verifier.ts`
- Mirror after local verification: `ops-software-bible/migrations/<same-file>.sql`

- [ ] Start with red local-database tests for direct anon/authenticated invocation, forged actor/company/grant arguments, actor/grant revocation, stale scope/entity/snapshot/capability versions, replayed/expired receipt, conflicting idempotency key, cross-service archive, shared-reference preservation, duplicate client references, and an injected mid-write failure.
- [ ] Extend the foundation's one generic control-plane commit RPC with a catalog dispatch branch. Do not create `public.catalog_authoring_commit_service_change` or a second receipt/audit coordinator.
- [ ] Add a private catalog transaction participant that receives the locked immutable change-set ID from the generic coordinator, revalidates catalog targets, applies all supported task/product/option/modifier/tax/material/bundle/stock-family/variant/mapping/supplier-cost/purchasing-rule/typed-membership/archive effects, increments the scope version, and returns normalized catalog readback.
- [ ] The generic coordinator alone locks/reloads actor/company/client/grant from stored rows, reauthorizes them, verifies/consumes the receipt, writes generic audit/commit/readback records, and commits. The catalog participant never mints/consumes a receipt or writes parallel generic records.
- [ ] The PostgREST-callable generic wrapper uses an explicit fixed `search_path` and security mode, `REVOKE ALL`/`EXECUTE` from `PUBLIC`, `anon`, and `authenticated`, and a narrow `GRANT EXECUTE` to `service_role`. The private participant is not exposed or directly granted to client roles.
- [ ] Reuse/refactor `catalog_setup_save` only inside this database transaction if its verified function body is safe. Do not retain the current begin → multiple RPC calls → TypeScript patch writes → finish flow.
- [ ] Any participant blocker raises and rolls back generic receipt/audit plus every catalog effect.
- [ ] Normalize and compare live readback to the prepared target, including absence checks and preservation checks. A mismatch is not `complete`.
- [ ] Commit:

```bash
git commit -m "feat(catalog): commit complete services atomically"
```

### Task 14: Add catalog commit to `OpsAgentDomainService`

**Files:**

- Create: `src/lib/agent-control-plane/services/commit-catalog-service-change.ts`
- Modify: `src/lib/agent-control-plane/services/domain-service.ts`
- Modify: `src/lib/agent-control-plane/services/create-domain-service.ts`
- Modify: `src/lib/agent-control-plane/services/__tests__/catalog-service-change.test.ts`
- Reuse: generic confirmation/commit/readback engine files

- [ ] Prove commit fails without the exact one-time receipt even when a caller sends `confirmed: true` or a valid change-set ID.
- [ ] Prove permission/grant/capability/scope changes between prepare and commit fail before the first catalog write.
- [ ] Prove lost-response retry returns the original commit/readback receipt and never reapplies.
- [ ] Invoke the generic change-set commit coordinator with the registered catalog transaction participant. No table access, receipt consumption, or pricing logic belongs in the domain-service facade.
- [ ] Commit:

```bash
git commit -m "feat(agent-control-plane): commit verified catalog service changes"
```

### Task 15: Register dark internal, REST, and MCP adapters

**Files:**

- Create/modify: `src/lib/agent-control-plane/adapters/internal.ts`
- Create only if an OPS consumer requires it: `src/lib/agent-control-plane/adapters/rest.ts`
- Modify: `src/lib/agent-control-plane/registry/write-tools.ts`
- Modify: `src/lib/agent-control-plane/mcp/register-tools.ts`
- Modify: `src/lib/agent-control-plane/mcp/tool-adapter.ts`
- Modify: `src/lib/agent-control-plane/mcp/input-required.ts`
- Modify: `src/app/mcp/route.ts`
- Add corresponding adapter/MCP tests

- [ ] Integrate the existing internal adapter and registry from foundation Tasks 4/14; do not recreate missing files. Do not begin MCP file changes until foundation Tasks 25–28 are committed and integrated.
- [ ] Register `prepare_catalog_service_change` and `commit_catalog_service_change`; retire the import-only pair before it becomes public.
- [ ] Keep Phase C on the internal adapter/domain call. It must not make HTTP calls to `/mcp`.
- [ ] MCP handlers parse Zod 4 contracts, require `ops.catalog.read`, `ops.catalog.prepare`, or `ops.catalog.write`, call `OpsAgentDomainService`, and map domain errors. They contain no catalog rule.
- [ ] Keep external exposure false. `input_required` may present the secure OPS approval URL and pending status; its host/model response cannot mint or replace the stored one-time receipt.
- [ ] Run legacy/current MCP transport tests plus semantic internal-vs-MCP parity on `catalog_proposal_hash`, effects, and projections; authorization-bound change-set hashes must remain distinct.
- [ ] Commit:

```bash
git commit -m "feat(agent-control-plane): expose dark catalog authoring adapters"
```

### Task 16: Make imports a provenance mode of the same prepare path

**Files:**

- Modify: `src/lib/catalog-setup/import/qb-drafts-to-cards.ts`
- Modify: `src/lib/catalog-setup/import/qb-import-classify.ts`
- Modify: `src/app/api/catalog/setup/import/quickbooks/route.ts`
- Modify: `src/app/api/catalog/setup/import/quickbooks/__tests__/route.test.ts`
- Modify: `src/app/api/catalog/setup/commit/route.ts`
- Modify: `src/app/api/catalog/setup/commit/__tests__/route.test.ts`
- Modify/retire as appropriate: `src/lib/catalog-setup/commit/*`

- [ ] Write parity tests proving file import, QuickBooks import, and model-transcribed facts compile through the same kernel/change-set engine as guided conversation.
- [ ] Preserve source hashes, row-level evidence, external identities, and lower-assurance labels.
- [ ] Do not silently commit imported cards through the old independent RPC path.
- [ ] Maintain current duplicate/re-import safety and route all accepted imports through the same review, confirmation, atomic commit, and readback.
- [ ] Commit:

```bash
git commit -m "refactor(catalog): route imports through service authoring kernel"
```

---

## Phase 4 — make Phase C an honest conversational adapter

### Task 17: Replace model-authored actions with facts and server-owned intent

**Files:**

- Modify: `src/lib/catalog-setup/agent/proposal-schemas.ts`
- Modify: `src/lib/catalog-setup/agent/setup-agent-service.ts`
- Modify: `src/lib/catalog-setup/phase-c/schemas.ts`
- Modify: `src/lib/catalog-setup/phase-c/types.ts`
- Modify: `src/lib/catalog-setup/phase-c/action-payload-contracts.ts`
- Modify: `src/lib/catalog-setup/phase-c/semantic-validator.ts`
- Modify: `src/lib/catalog-setup/phase-c/question-policy.ts`
- Modify: `src/lib/catalog-setup/phase-c/turn-service.ts`
- Modify corresponding `agent/__tests__` and `phase-c/__tests__`

- [ ] Add red tests showing arbitrary `z.record(unknown)` payloads, unknown fields, unsupported capability claims, SQL/table names, and model-calculated totals cannot reach compilation.
- [ ] Model output is limited to provenance-bearing fact candidates, contradictions/unresolved facts, one registered question intent with fact keys, or `ready_for_review`.
- [ ] The server materializes each accepted intent as an immutable question snapshot with `questionInstanceId`, `intentId`, scope/graph revision, unambiguous `subjectRef`, registry-validated typed fact path, copy revision, and quick answers containing stable `choiceId` plus typed value/target IDs. The model and UI never route an answer by visible label or array position.
- [ ] Resolve question eligibility from the capability/module registry. A discover-only capability may be described but never asked as a configuration decision.
- [ ] Let the kernel determine completeness and compile actions. The model cannot declare a service executable or approved.
- [ ] Preserve plain customer language. No question asks the owner to understand tables, option kinds, modifier enums, inventory algorithms, or internal tool wiring.
- [ ] Commit:

```bash
git commit -m "refactor(phase-c): constrain catalog turns to facts and intents"
```

### Task 18: Make sessions service-scoped, revision-safe, and repeatable

**Files:**

- Modify: `src/lib/catalog-setup/phase-c/session-service.ts`
- Modify: `src/lib/catalog-setup/phase-c/input-ledger.ts`
- Modify: `src/lib/catalog-setup/phase-c/input-service.ts`
- Modify: `src/lib/catalog-setup/phase-c/conversation-reducer.ts`
- Modify: `src/lib/catalog-setup/phase-c/conversation-history.ts`
- Modify: `src/app/api/catalog/setup/sessions/route.ts`
- Modify: `src/app/api/catalog/setup/sessions/[sessionId]/messages/route.ts`
- Modify: `src/app/api/catalog/setup/sessions/[sessionId]/turn/route.ts`
- Modify: `src/app/api/catalog/setup/sessions/[sessionId]/commit/route.ts`
- Modify: `src/app/api/catalog/setup/sessions/[sessionId]/abandon/route.ts`
- Modify all corresponding tests

- [ ] Add `serviceScopeId`, `serviceOperation`, `serviceGraphRevision`, `changeSetId`, `reviewProjection`, expected versions, capability revision, and immutable question snapshots to persisted/session response state.
- [ ] Freeze each submitted message against the exact `questionInstanceId`, `subjectRef`, typed fact path, service scope, and session version. Quick answers submit stable choice/value IDs; labels are presentation only. A second tab cannot attach an answer to a later or same-label/different-product question.
- [ ] Persist answer revision/removal lineage with explicit supersedes/superseded-by IDs. Test two products with identically labeled options across refresh, rapid follow-up, removal, revision, and locale changes; each fact must remain attached to its original subject.
- [ ] Removing or superseding an answer cancels pending work, retires derived facts/change sets, restores the correct question/options, and does not leave a loader or internal error.
- [ ] Follow-up messages submitted while Phase C is processing enter the ordered ledger and are reconciled before the next question/review.
- [ ] `SET UP ANOTHER SERVICE` creates a fresh add session after live readback; no stale Vinyl facts bleed into Railings or vice versa.
- [ ] `CHANGE EXISTING SERVICE` loads a complete selected scope and asks only for requested changes. If the candidate is unscoped, prepare `adopt` with exact root membership/ownership plus the requested edit in one review. `ARCHIVE SERVICE` shows impact before prepare.
- [ ] Build a role/permission matrix from the current `catalog.run_setup` permission path. Test owner/admin/allowed staff, revoked overrides, inactive/unassigned users, changed permission mid-session, and cross-company scope selection. No role can enter a non-skippable step whose required control is hidden.
- [ ] War-game refresh, back, abandon, browser close/reopen, offline/network loss, provider retry, simultaneous tabs, stale feature/capability flag, and completion navigation. Each state resumes, retries, or exits explicitly; none hard-sticks.
- [ ] Commit:

```bash
git commit -m "feat(phase-c): support safe repeatable service authoring"
```

### Task 19: Put the review and editable sample quotes inside the conversation

**Files:**

- Create: `src/components/catalog/setup/catalog-service-review.tsx`
- Create: `src/components/catalog/setup/catalog-sample-quote.tsx`
- Create: `src/components/catalog/setup/__tests__/catalog-service-review.test.tsx`
- Create: `src/components/catalog/setup/__tests__/catalog-sample-quote.test.tsx`
- Modify: `src/components/catalog/setup/guided-catalog-setup.tsx`
- Modify: `src/components/catalog/setup/__tests__/guided-catalog-setup.test.tsx`
- Modify: `src/components/catalog/setup/catalog-setup-route.tsx`
- Modify: `src/components/catalog/setup/__tests__/catalog-setup-route.test.tsx`
- Modify: `src/components/catalog/setup/catalog-setup-launcher.tsx`
- Modify: `src/components/catalog/setup/__tests__/catalog-setup-launcher.test.tsx`
- Modify: `src/app/(dashboard)/catalog/setup/page.tsx`
- Inspect and modify only if measured ancestor constraints require it: `src/components/layouts/dashboard-layout.tsx`
- Modify: `src/i18n/dictionaries/en/catalog-setup.json`
- Modify: `src/i18n/dictionaries/es/catalog-setup.json`
- Reuse shared: `src/components/ui/button.tsx`, `input.tsx`, `select.tsx`, `checkbox.tsx`

- [ ] Write failing component tests that assert bounding boxes and scroll ownership, not only DOM presence.
- [ ] Diagnose computed height/overflow/positioning at all four required viewports before CSS changes. Record the route, transcript, last turn, composer, action-chip, and viewport bounding boxes.
- [ ] Render the plain-language service summary, before/after change disclosure, warnings, and `MINIMUM`, `BASE`, and `MODIFIER COVERAGE` checks as the latest assistant turn. Use job-size labels only when the operator supplied those representative facts.
- [ ] Let the operator edit a clearly labeled `TEST ONLY — DOES NOT CHANGE CATALOG` scenario quantity/options and see a server-returned recalculation outside approval state. Let catalog field edits submit a correction that creates a new revision/baseline projection and visibly invalidates prior approval.
- [ ] Give the conversation the full route height from the header boundary to the viewport bottom. Keep the transcript as the only vertical scroll owner. The review expands in normal flow; no nested scroll panel. The floating composer remains compact and transcript bottom padding uses the measured composer/control-stack height plus the design-system gap.
- [ ] Implement transcript-local auto-follow: follow after the operator submits and while already bottom-pinned; preserve the reading anchor when the operator scrolls up or expands history; show `JUMP TO LATEST` while new turns arrive off-screen; re-enable follow at bottom. Use the transcript ref's `scrollTop`/`scrollTo`, never `scrollIntoView` or document/ancestor scrolling.
- [ ] Fix height locally in the setup route first. Touch `dashboard-layout.tsx` only when bounding-box proof shows an ancestor constraint prevents route ownership, and protect every other dashboard route with layout regression tests.
- [ ] Preserve the compact prompt `Pick an option above, or type something else` when choices exist; preserve upload inside the composer; keep navigation chips left-aligned on the established frosted surface.
- [ ] Lock the established proportion contract: Mohave `text-body-sm` (computed 14px) for input and natural-language choices; `h-control-32` composer actions; 16×16 upload/send icons via semantic icon tokens; send action no wider than 80px; composer input radius; edge inset equal to composer padding plus one 4px half-step; and the reserved 4px half-step below SEND before the upload divider. Upload remains a borderless subordinate ghost action.
- [ ] Keep the composer usable while Phase C processes. Show the submitted user turn immediately with the OPS activity treatment on that turn and no “Phase C is checking your answer” sentence. A quick follow-up enters the visible ordered queue and can be revised/removed before processing without retargeting its question.
- [ ] Use only OPS tokens: pure black, hairlines/static glass, existing typography, existing shared inputs, one steel-blue commit accent, Lucide icons at explicit 16/20px semantic sizes, and existing radii. Do not add a new shadow language.
- [ ] Use the existing Phase C activity ripple/typewriter behavior only where it aids comprehension. Apply `EASE_SMOOTH`, no bounce/spring, and a reduced-motion opacity fallback.
- [ ] Keep `CONTINUE`, upload, start-over, alternate-method, back, `SET UP ANOTHER SERVICE`, and `OPEN CATALOG` reachable by keyboard, pointer, and narrow responsive layouts.
- [ ] Commit:

```bash
git commit -m "feat(catalog): review services through editable sample quotes"
```

---

## Phase 5 — adversarial verification and release gates

### Task 20: Prove domain, database, and adapter safety

- [ ] Run focused web tests:

```bash
npm test -- \
  src/lib/products \
  src/lib/catalog-authoring \
  src/lib/catalog-setup/commit \
  src/lib/catalog-setup/phase-c \
  src/lib/agent-control-plane/services/__tests__/catalog-service-change.test.ts \
  src/components/catalog/setup \
  tests/integration/configured-estimate-line.test.ts \
  tests/unit/supabase/catalog-pricing-contract-and-line-trace-migration.test.ts \
  tests/unit/supabase/line-tax-and-presentation-migration.test.ts \
  tests/unit/supabase/catalog-authoring-service-change-migration.test.ts
```

- [ ] Run the complete catalog-related suite:

```bash
npm test -- \
  src/lib/catalog \
  src/lib/catalog-setup \
  src/lib/catalog-authoring \
  src/lib/products \
  src/components/catalog \
  src/app/api/catalog/setup \
  tests/unit/catalog-setup \
  tests/integration/configured-estimate-line.test.ts \
  tests/unit/supabase/catalog-pricing-contract-and-line-trace-migration.test.ts \
  tests/unit/supabase/line-tax-and-presentation-migration.test.ts \
  tests/unit/supabase/catalog-order-item-purchasing-snapshot-migration.test.ts \
  tests/unit/supabase/phase-c-catalog-commit-migration.test.ts \
  tests/unit/supabase/phase-c-catalog-onboarding-fk-indexes-migration.test.ts \
  tests/unit/supabase/catalog-authoring-service-change-migration.test.ts
```

- [ ] Run control-plane/MCP suites:

```bash
npm test -- \
  src/lib/agent-control-plane/contracts \
  src/lib/agent-control-plane/registry \
  src/lib/agent-control-plane/changes \
  src/lib/agent-control-plane/services \
  src/lib/agent-control-plane/adapters \
  src/lib/agent-control-plane/mcp \
  src/app/mcp
```

- [ ] In local/test Supabase, prove add Railings → verified readback → add Vinyl → verified readback, then adopt an unscoped existing service, edit Vinyl, and archive Vinyl. Confirm Railing rows, historical line items, shared tax/family records, and unrelated catalog records remain unchanged.
- [ ] Prove every legacy `add_flat` tier fixture and sampled live row retains its exact future-quote total.
- [ ] Inject a failure after every generic and catalog participant mutation stage and prove receipt/audit/catalog rows all roll back together.
- [ ] Prove prepare/commit replay, stale version, changed capability revision, cross-company IDs, forged receipt, duplicate client refs, and live readback mismatch fail closed.
- [ ] Compare internal-adapter, REST if present, and MCP prepared effects/projections plus `catalog_proposal_hash` after removing transport metadata. They must be semantically identical; assert their actor/grant-bound `change_set_hash` values differ when provenance differs.
- [ ] Commit test fixes separately from production behavior changes.

### Task 21: Prove cross-platform pricing, stock, purchasing, tax, presentation, and iOS build health

- [ ] Verify the exact web/iOS pricing and purchasing fixture identities with `cmp`; run shared pricing, material-quantity, supplier-selection, tax, and presentation vectors through both platforms.
- [ ] Run:

```bash
cmp /Users/jacksonsweet/Projects/OPS/ops-web-catalog-authoring-control-plane/src/lib/catalog/__fixtures__/purchasing-rule-contracts.json \
  /Users/jacksonsweet/Projects/OPS/ops-ios-catalog-authoring-control-plane/OPSTests/Fixtures/Catalog/purchasing-rule-contracts.json
```

- [ ] Before building, check for parallel `xcodebuild`/DerivedData use and copy `Secrets.xcconfig` into the iOS worktree.
- [ ] Run:

```bash
xcodebuild test -project OPS.xcodeproj -scheme OPS \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' \
  -derivedDataPath /private/tmp/ops-catalog-kernel-tests \
  -clonedSourcePackagesDirPath .spm-local \
  -only-testing:OPSTests/ProductConfigurationResolverTests \
  -only-testing:OPSTests/ProductConfigurationContractTests \
  -only-testing:OPSTests/DocumentTaxContractTests \
  -only-testing:OPSTests/QuotePresentationContractTests \
  -only-testing:OPSTests/MaterialQuantityRuleResolverTests \
  -only-testing:OPSTests/SupplierCostProfileResolverTests \
  -only-testing:OPSTests/CatalogPurchasingSnapshotMigrationTests \
  -only-testing:OPSTests/GuidedCatalogSetupTierTests \
  -only-testing:OPSTests/DesignToEstimateAdapterTests \
  -only-testing:OPSTests/RecipeResolverTests

xcodebuild -project OPS.xcodeproj -scheme OPS \
  -destination 'generic/platform=iOS' \
  -derivedDataPath /private/tmp/ops-catalog-kernel-build \
  -clonedSourcePackagesDirPath .spm-local build
```

- [ ] Inspect logs for `TEST SUCCEEDED`/`BUILD SUCCEEDED`; do not trust a piped shell exit code alone.
- [ ] Baseline-compare any unrelated failure on the exact origin commit.

### Task 22: Prove the conversation visually and accessibly

**E2E files:**

- Modify: `tests/e2e/catalog-setup-viewport.spec.ts`
- Modify: `tests/e2e/catalog-setup-wizard.spec.ts`
- Modify as needed: `tests/e2e/helpers/catalog-setup-auth.ts`

- [ ] Capture before/after screenshots to `docs/artifacts/`, not the repository root.
- [ ] Test 915 × 685, 1280 × 720, 1440 × 900, and one narrow responsive viewport.
- [ ] Assert the route/conversation top equals the measured header boundary and its bottom equals the viewport bottom (within one CSS pixel). On first turn, assert the PHASE C label, full question, and helper bounding boxes are all inside the visible transcript and do not intersect the composer. Assert the transcript owns scroll, composer bottom padding clears the last text, short transcripts do not scroll unnecessarily, and long transcripts retain the newest exchange.
- [ ] Assert computed proportions at all four viewports: input/choice text 14px, composer actions 32px high, upload/send icons exactly 16×16px, send width ≤80px, tokenized edge/bottom insets present, upload subordinate/borderless, no composer box shadow, choices natural-height/unclipped, and navigation chips left-aligned on the approved frosted token surface.
- [ ] Assert multiple-choice answers appear in history, collapsed questions can be reopened, choices are not clipped, and remove/supersede restores the right question and options without text or internal error.
- [ ] Assert asynchronous turns auto-follow only while bottom-pinned or immediately after operator submission. Scrolling up/expanding an older question must preserve its anchor, show `JUMP TO LATEST`, and never move the page/dashboard ancestor; activating the control returns to the newest turn. Repeat with reduced motion.
- [ ] Assert a catalog modifier/minimum/tax/presentation edit recomputes baseline checks, changes revision/`catalog_proposal_hash`, and requires fresh confirmation. Assert a labeled `TEST ONLY` scenario edit changes only its ephemeral result and cannot change the approval summary/hash.
- [ ] While a response is pending, submit and then revise/remove a quick follow-up. Assert each user turn appears immediately in order, the composer stays operable, the activity effect is graphical only, and the eventual answer uses the exact persisted question/subject lineage.
- [ ] Assert keyboard order, visible focus, screen-reader names, live-region restraint, touch targets, and `prefers-reduced-motion` behavior.
- [ ] Run:

```bash
npm run test:e2e -- \
  tests/e2e/catalog-setup-viewport.spec.ts \
  tests/e2e/catalog-setup-wizard.spec.ts
```

- [ ] Use `custom-skills:audit-design-system` before calling UI complete. Verify zero new hardcoded color, spacing, radius, typography, icon-size, shadow, or easing values.

### Task 23: Run complete web gates and independent review

```bash
npm run type-check
npm run lint
npm run format:check
npm run build
git diff --check
git status --short --branch
```

- [ ] Request an independent code review focused on financial semantics, atomicity, company isolation, capability honesty, stale/replay behavior, and UI geometry.
- [ ] Resolve every finding and rerun the affected focused test plus the complete gate it belongs to.
- [ ] Record exact test counts, commands, commit SHAs, local migration readback, and screenshot paths.

### Task 24: Update the Bible and hold release boundaries

**Files:**

- Modify: `ops-software-bible/03_DATA_ARCHITECTURE.md`
- Modify: `ops-software-bible/04_FEATURES_CATALOG.md`
- Modify: `ops-software-bible/07_SPECIALIZED_FEATURES.md` if control-plane/catalog behavior lives there
- Modify: both design specs and implementation plans with final paths/contracts
- Add verified migration mirrors under `ops-software-bible/migrations/`

- [ ] Document only behavior proven in code and local/test readback. Mark dark/external capabilities accurately.
- [ ] Commit docs atomically.
- [ ] Stop before push, production migration, deployment, MCP exposure, or App Store release unless Jackson explicitly authorizes each applicable action.
- [ ] After authorization, prove exact commit ancestry, production migration readback, customer alias, deployed runtime behavior, and external MCP host behavior separately. A green build or deployment URL is not customer-live proof.

---

## Completion evidence

The work is complete only when the handoff can show all of the following:

- Phase C sets up a full service with pricing modifiers and creates exactly the reviewed graph.
- The same facts prepared through internal Phase C and MCP produce the same `catalog_proposal_hash`, effects, and projection; authorization-bound change-set hashes remain distinct.
- One generic control-plane confirmation commits receipt/audit/catalog rows together or nothing.
- Legacy `add_flat` tiers retain exact totals, and `catalog_v2` is not authored until every supported consumer is compatible.
- Three editable quote checks match web/iOS pricing, tax, and customer-presentation contracts without treating test scenarios as approved catalog state.
- Railings can be completed first and Vinyl added later without damage or stale context.
- Existing scoped services can be changed/archived, and unscoped services can be explicitly adopted, with exact ownership/before/after/impact review.
- Vinyl can calculate internally from square feet and render customer-facing `1 @ total` only after that presentation module is proven customer-live; before then Phase C states the limitation.
- Authored stock structure appears correctly in released web/iOS stock consumers, and any supplier-cost or purchasing rule Phase C offers is demonstrably executed by the real material/order path rather than merely stored.
- Phase C never asks about or promises an unsupported capability; Deck Designer remains discover-only until executable binding proof exists.
- All requested viewport screenshots and bounding-box assertions pass.
- Focused, catalog-complete, control-plane, cross-platform, type, lint, format, build, database, accessibility, and adversarial gates pass.
- Production remains untouched until separately authorized and verified.
