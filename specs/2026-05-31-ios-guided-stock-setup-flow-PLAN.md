# Guided Stock Setup — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship the iOS **Guided Stock Setup** flow — a conversational, multiple-choice, first-run inventory setup that captures everything an operator stocks/sells, infers the correct catalog structure across the whole list, teaches the OPS equivalent at each step, and creates the data through the existing atomic catalog engine.

**Architecture:** A new self-contained full-screen SwiftUI flow (`GuidedStockSetup*`) builds the same `CatalogSetup*Draft` structs the Advanced flow uses and commits **per-family** through a new shared `CatalogSetupCommitService` (extracted from `CatalogSetupFlowSheet`) via the atomic `catalog_setup_save` RPC. Deterministic name-clustering proposes structure; the operator confirms via multiple choice. Reuses `CatalogSetupWorkflow.generateVariantDrafts` + `makeSavePayload`. No parallel write path. Steel-blue `primaryAccent` styling (NOT the coach-mark `wizardAccent`).

**Tech Stack:** SwiftUI, SwiftData, OPSStyle tokens, existing `CatalogRepository` / `CatalogSetupWorkflow`, Supabase RPC `catalog_setup_save`, XCTest. Spec: `ops-software-bible/specs/2026-05-31-ios-guided-stock-setup-flow-design.md`.

**Resolved decisions (verified against prod schema 2026-05-31):**
- **D1** — per-family loop over `catalog_setup_save` (import RPC is flat families+variants only).
- **D2** — `catalog_units` must pre-exist; flow ensures unit-per-dimension exists before commit.
- **D3** — clustering = normalized-token stem + Jaccard similarity; threshold tuned by tests (Task 3.x).
- **D4** — no migration; `product_bundle_items.relationship_kind/suggestion_reason/compatibility_selector` already exist.

---

## File Structure

**Create:**
- `ops-ios/OPS/Services/Catalog/CatalogSetupCommitService.swift` — shared commit + reconcile (extracted from `CatalogSetupFlowSheet`), hardened. One responsibility: take a `CatalogSetupSavePayload` (or a family draft) → commit via RPC → reconcile SwiftData. Used by Advanced + Guided.
- `ops-ios/OPS/Services/Catalog/GuidedStockStructuring.swift` — pure deterministic clustering/structure inference. No UI, no I/O. Fully unit-tested.
- `ops-ios/OPS/Services/Catalog/GuidedStockSetupModel.swift` — `@MainActor ObservableObject` state machine: stages, captured items, per-group answers, derived families/variants/stock drafts, blueprint, commit progress.
- `ops-ios/OPS/Services/Catalog/GuidedStockSetupDraftStore.swift` — Codable snapshot + file persistence (mirrors `CatalogSetupDraftStore`, distinct context key `guided`).
- `ops-ios/OPS/Views/Catalog/Stock/GuidedStockSetup/GuidedStockSetupFlow.swift` — full-screen container: stage switch, top progress, bottom primary CTA, nav, offline/permission banners.
- `.../GuidedStockSetup/GuidedStockCaptureView.swift` — stage 1.
- `.../GuidedStockSetup/GuidedStockStructureView.swift` — stage 2 (hosts grouping/attributes/measurement/stock/products subviews).
- `.../GuidedStockSetup/GuidedStockBlueprintView.swift` — stage 3.
- `.../GuidedStockSetup/GuidedStockDoneView.swift` — stage 4.

**Modify:**
- `ops-ios/OPS/Views/Catalog/Stock/CatalogSetupFlowSheet.swift` — replace inline `commitSetup`/`reconcileSuccessfulSave` bodies with calls to `CatalogSetupCommitService`; add `GUIDED SETUP` toolbar entry.
- `ops-ios/OPS/Views/Catalog/Stock/StockView.swift` — empty-state `SET UP STOCK` (Guided) + `// ADVANCED`; persistent `GUIDED SETUP` action when non-empty.
- `ops-ios/OPS/Network/Supabase/CatalogSchemaCapabilityGate.swift` — distinguish table-missing from transient network error in `refresh`/`probe`.
- `ops-ios/OPS/Services/CatalogSetupWorkflow.swift` — add positive-quantity guard surfaced to callers (don't silently `max(0,…)` to zero for guided commits).

**Test:**
- `ops-iosTests/Catalog/GuidedStockStructuringTests.swift`
- `ops-iosTests/Catalog/CatalogSetupCommitServiceTests.swift`
- `ops-iosTests/Catalog/GuidedStockSetupModelTests.swift`
- `ops-iosTests/Catalog/GuidedStockCommitOrchestrationTests.swift`

> **Before Phase 1:** read `CatalogSetupFlowSheet.swift` lines 2303–2700 (the `upsert*`, `resolvedServerId`, `applyExplicitLocalDeletes` helpers) and `CatalogRepository.swift` in full — the commit-service extraction must move these verbatim, not reimplement them. Read `CatalogUnit` create path in `CatalogRepository` before Phase 4 (D2).

---

## Phase 1 — Shared commit service + hardenings

*Unblocks both flows; lowest risk; pure refactor + 3 fixes. Land first.*

### Task 1.1: Extract `CatalogSetupCommitService`

**Files:** Create `Services/Catalog/CatalogSetupCommitService.swift`; Modify `CatalogSetupFlowSheet.swift`.

**Interface (real):**
```swift
@MainActor
final class CatalogSetupCommitService {
    enum CommitOutcome { case committed(CatalogSetupSaveResponse); case rejected(message: String) }
    enum ReconcileResult { case clean; case resynced(reason: String) } // resynced = data saved, cache rebuilt

    init(companyId: String, modelContext: ModelContext)

    /// Atomic single-family commit. Idempotent via saveAttempt.
    func commit(payload: CatalogSetupSavePayload,
                saveAttempt: CatalogSetupSaveAttempt) async throws -> CommitOutcome

    /// Reconcile server IDs into SwiftData. NEVER throws to caller as a "save failed":
    /// returns .resynced on cache-mapping error (server already committed).
    func reconcile(payload: CatalogSetupSavePayload,
                   response: CatalogSetupSaveResponse) -> ReconcileResult
}
```

- [ ] **Step 1:** Move `reconcileSuccessfulSave`, `resolvedServerId`, `resolvedMappedId`, `resolvedOptionalMappedId`, all `upsert*`, `updateLocalProductLink`, `applyExplicitLocalDeletes`, `localISOTimestamp` from `CatalogSetupFlowSheet` into the service **verbatim** (they already exist and work). Make `reconcile` catch `CatalogSetupLocalReconciliationError` internally and return `.resynced(reason:)` + trigger a catalog resync, instead of throwing.
- [ ] **Step 2:** In `CatalogSetupFlowSheet.commitSetup`, replace the inline reconcile + `modelContext.save()` with `let result = service.reconcile(...)`. On `.resynced`, still treat as success (clear draft, success haptic, dismiss).
- [ ] **Step 3:** Build: `cd ops-ios && xcodebuild -scheme OPS -destination 'generic/platform=iOS' build` → clean.
- [ ] **Step 4:** Commit: `git commit -- <service file> <CatalogSetupFlowSheet.swift>` — `refactor(catalog): extract CatalogSetupCommitService from setup sheet`.

### Task 1.2: Reconcile-as-success test
**File:** `CatalogSetupCommitServiceTests.swift`
- [ ] **Step 1 (failing test):** Given a `response.ok == true` with an `idMap` missing a stock unit's variant mapping, `reconcile` returns `.resynced`, NOT a thrown error.
```swift
func test_reconcile_missingMapping_afterOkResponse_returnsResynced_notFailure() {
    let svc = CatalogSetupCommitService(companyId: "c1", modelContext: inMemoryContext())
    let payload = Fixtures.payloadWithStockUnitMissingVariantMapping()
    let response = Fixtures.okResponseMissingStockVariant()
    if case .resynced = svc.reconcile(payload: payload, response: response) { } else { XCTFail("expected .resynced") }
}
```
- [ ] **Step 2:** Run → fails. **Step 3:** Implement the catch→resynced path. **Step 4:** Run → passes. **Step 5:** Commit `test(catalog): commit service treats post-save reconcile error as resync`.

### Task 1.3: Capability-probe transient-error handling
**File:** `CatalogSchemaCapabilityGate.swift` + test.
- [ ] **Step 1 (failing test):** `probe` returns `.unknown` (not `false`) on a thrown URLError; `refresh` on `.unknown` keeps the last-known capability instead of forcing `false`.
- [ ] **Step 2:** Run → fails. **Step 3:** Add `enum ProbeResult { case available, missing, unknown }`; map `PostgrestError`/table-missing → `.missing`, `URLError`/timeouts → `.unknown`; `refresh` only writes `false` on `.missing`. **Step 4:** Pass. **Step 5:** Commit `fix(catalog): capability probe distinguishes missing table from network error`.

### Task 1.4: Positive-quantity guard
**File:** `CatalogSetupWorkflow.swift` + test.
- [ ] **Step 1 (failing test):** a guided commit with a stock unit `quantityValue == 0` is rejected by a new `CatalogSetupWorkflow.validateStockQuantities(variants:) throws` before payload build.
- [ ] **Step 2:** Run → fails. **Step 3:** Add `validateStockQuantities`; call it in the guided commit path (Phase 6). Keep `max(0,…)` for Advanced back-compat but route guided through the stricter guard. **Step 4:** Pass. **Step 5:** Commit `feat(catalog): positive stock-unit quantity validation for guided commit`.

**Phase 1 acceptance:** Advanced flow unchanged in behavior; commit/reconcile live in the shared service; 3 hardenings covered by tests; device-target build clean.

---

## Phase 2 — Guided flow shell, state model, draft persistence, entry points

### Task 2.1: `GuidedStockSetupModel` skeleton
**File:** `GuidedStockSetupModel.swift`
**Interface:**
```swift
@MainActor final class GuidedStockSetupModel: ObservableObject {
    enum Stage: Int, CaseIterable { case prime, capture, structure, blueprint, done }
    struct CapturedItem: Identifiable, Codable, Hashable { var id: String; var name: String; var kind: ItemKind } // stock/sell/both
    @Published var stage: Stage = .prime
    @Published var capturedItems: [CapturedItem] = []
    @Published var groups: [StructuredGroup] = []      // produced in Phase 3
    @Published var commitProgress: CommitProgress = .idle
    let companyId: String
    init(companyId: String, draftStore: GuidedStockSetupDraftStore = .shared)
    func advance(); func back()
    func persist(); func restoreIfAvailable()
}
```
- [ ] Steps: define types → unit test stage advance/back + persistence round-trip → commit `feat(catalog): guided stock setup state model`.

### Task 2.2: `GuidedStockSetupDraftStore`
**File:** `GuidedStockSetupDraftStore.swift` — mirror `CatalogSetupDraftStore` (file-based, `Documents/GuidedStockSetupDrafts/`, context key company+user+`guided`). Snapshot = full model state incl. `commitProgress`.
- [ ] Steps: implement save/load/clear → round-trip test → commit.

### Task 2.3: Flow container + entry points
**Files:** `GuidedStockSetupFlow.swift`; Modify `StockView.swift`, `CatalogSetupFlowSheet.swift`.
- [ ] Container: full-screen, `NavigationStack`, top thin progress (`primaryAccent`), stage `switch`, bottom 52pt primary CTA, offline + permission banners (reuse `setupBanner` patterns). Per spec §7 screens, §16 tokens.
- [ ] Permission gate: `PermissionStore.shared.can("catalog.manage")` to enter; products steps gated on `catalog.products.manage`.
- [ ] Entry: `StockView` empty-state `SET UP STOCK` → Guided; `// ADVANCED` → `CatalogSetupFlowSheet`; non-empty `GUIDED SETUP` action; `CatalogSetupFlowSheet` toolbar `GUIDED SETUP`.
- [ ] Concurrent-draft guard: if an Advanced draft exists, opening Guided prompts resume/replace (distinct context keys — never clobber).
- [ ] Build clean (generic/platform=iOS) → commit `feat(catalog): guided stock setup shell + entry points`.

**Phase 2 acceptance:** flow opens from all entry points, gated by permission, renders PRIME, persists/resumes, no dead controls.

---

## Phase 3 — Capture + deterministic structuring

### Task 3.1: `GuidedStockStructuring` (pure)
**File:** `GuidedStockStructuring.swift`
**Interface:**
```swift
enum GuidedStockStructuring {
    struct Cluster { let stem: String; let memberItemIds: [String]; let differingTokenSets: [[String]] }
    static func normalize(_ name: String) -> [String]          // lowercase, trim, tokenize, strip pure-number/unit tokens
    static func cluster(_ items: [GuidedStockSetupModel.CapturedItem], threshold: Double) -> [Cluster]
    static func proposeValues(for cluster: Cluster) -> [String] // differing tokens → candidate values
}
```
- [ ] **Step 1 (failing tests):** real cases —
```swift
func test_cluster_groupsVinylByColor() {
    let items = ["Vinyl black","Vinyl white","Vinyl grey"].map(capture)
    let c = GuidedStockStructuring.cluster(items, threshold: 0.5)
    XCTAssertEqual(c.count, 1); XCTAssertEqual(c[0].stem, "vinyl")
    XCTAssertEqual(Set(GuidedStockStructuring.proposeValues(for: c[0])), ["black","white","grey"])
}
func test_cluster_doesNotMergeScrewsAndScrewGun() { /* "Screws 2in","Screw gun" → 2 clusters or 2 singles */ }
func test_cluster_allDistinct_returnsNoClusters() { /* unrelated names → 0 multi-member clusters */ }
func test_cluster_twoDimensions_vinyl_color_and_width() { /* "Vinyl black 6ft","Vinyl white 8ft" → 2 differing positions */ }
```
- [ ] **Step 2:** Run → fail. **Step 3:** Implement normalize + clustering (stem match + Jaccard ≥ threshold; never auto-merge below threshold). Tune threshold so the four tests pass. **Step 4:** Pass. **Step 5:** Commit `feat(catalog): deterministic guided stock structuring`.

### Task 3.2: Capture view
**File:** `GuidedStockCaptureView.swift` — per spec §7.1: repeating name input (48pt) + STOCK/SELL/BOTH chip; `+ ADD`; empty `—`/`// ADD YOUR FIRST ITEM`; `ORGANIZE →` enabled ≥1. Writes `model.capturedItems`.
- [ ] Build + snapshot-light test of validity gating → commit `feat(catalog): guided capture step`.

### Task 3.3: Structure view — grouping + attributes
**File:** `GuidedStockStructureView.swift` — per spec §7.2a/2b. Drives `GuidedStockStructuring.cluster` → per-cluster confirm (YES one item / NO separate) → attribute naming chips → editable values (prefilled) → derives `[CatalogSetupAttributeDraft]` and calls `CatalogSetupWorkflow.generateVariantDrafts`. Shows resulting variant count.
- [ ] Model test: confirmed group → correct attribute drafts + variant count. Commit `feat(catalog): guided grouping + attributes`.

**Phase 3 acceptance:** capture → structure produces correct attribute/variant drafts for the four clustering cases; over/under-grouping safe (operator-confirmed).

---

## Phase 4 — Measurement, units, stock reality (the Vinyl fix)

### Task 4.1: Unit resolution (D2)
**File:** extend `GuidedStockSetupModel` + read `CatalogRepository` unit CRUD first.
- [ ] Map measurement → dimension: piece→`count`/'each', length→`length`/'ft', area→`area`/'sq ft'. Look up an active `catalog_units` row for that dimension; if none, create via `CatalogRepository` (confirm method name on read) before commit. Test: missing unit triggers create; existing reused.
- [ ] Commit `feat(catalog): guided unit resolution by dimension`.

### Task 4.2: Stock reality view
**File:** `GuidedStockStructureView.swift` (2c/2d subviews) — per spec §7.2c/2d. By-piece → per-variant count. By-length/area → full-unit (width × length + unit) + count + repeating offcut remaining-lengths → builds `[CatalogSetupStockUnitDraft]` (`.roll` full / `.offcut` partial, `status` set, `quantityValue > 0`). Uses `CatalogSetupWorkflow.mirroredQuantity` for display.
- [ ] Model tests: full+offcut answers → correct stock-unit drafts + mirrored qty; zero blocked (Task 1.4 guard). Commit `feat(catalog): guided stock reality (rolls + offcuts)`.

**Phase 4 acceptance:** the reporter's Vinyl case (6ft×75ft full rolls + offcuts) is set up in plain language; drafts produce a committable payload; units exist.

---

## Phase 5 — Products, bundles, recipes (capability-gated)

**File:** `GuidedStockStructureView.swift` (2e subview) — per spec §7.2e. Gated on `catalog.products.manage`; silently skipped otherwise. Sell-on-its-own → product link; selling-uses-stock → `product_materials` recipe; package → `product_bundle_items` with `relationship_kind` required/suggested (D4 — columns exist). Builds the `selectedProduct` + mappings inputs `makeSavePayload` already accepts.
- [ ] Model tests: recipe link + bundle required/suggested produce correct payload product section. Build clean. Commit `feat(catalog): guided products, bundles, recipes`.

**Phase 5 acceptance:** sell/both items get products/bundles/recipes; permission-absent path completes stock-only with no dead-end.

---

## Phase 6 — Blueprint + orchestrated commit + Done + notification

### Task 6.1: Blueprint view
**File:** `GuidedStockBlueprintView.swift` — per spec §7.3. Renders derived families/products/bundles with variant counts, stock summary, non-blocking warnings; edit routes back to the relevant structure sub-step; `BUILD IT →` (disabled if nothing committable / offline).

### Task 6.2: Commit orchestration (D1)
**File:** `GuidedStockSetupModel.commitAll()` using `CatalogSetupCommitService`.
**Interface:**
```swift
enum CommitProgress: Equatable { case idle, running(done: Int, total: Int), partial(failedFamilyIds: [String]), complete(GuidedStockSummary) }
func commitAll() async   // loop families: makeSavePayload → SaveAttempt.resolve → service.commit → service.reconcile; record committed family ids in draft for resume
```
- [ ] **Failing tests** (`GuidedStockCommitOrchestrationTests`): multi-family success → `.complete` with correct counts; mid-loop failure → `.partial`, prior families committed, draft records progress; retry re-sends only failed (idempotent); offline → `.idle` + held (no calls). Use a `CatalogSetupCommitService` test double.
- [ ] Implement → pass → commit `feat(catalog): guided commit orchestration (per-family, resumable)`.

### Task 6.3: Done + notification
**File:** `GuidedStockDoneView.swift` — per spec §7.4 summary + haptic + actions (DONE / REFINE IN ADVANCED / ADD MORE). Post completion notification per `07_SPECIALIZED_FEATURES.md` §14 (standard, `actionUrl` → stock, `actionLabel` VIEW STOCK).
- [ ] Build clean. Commit `feat(catalog): guided done summary + completion notification`.

**Phase 6 acceptance:** full flow commits a multi-family inventory through the engine, resumable + offline-safe; notification posted; success summary correct.

---

## Phase 7 — Verification + bible

- [ ] **Full build:** `cd ops-ios && xcodebuild -scheme OPS -destination 'generic/platform=iOS' build` → clean (check `lsof`/`ps aux | grep xcodebuild` first for parallel sessions; copy `Secrets.xcconfig` if in a worktree).
- [ ] **Tests:** `xcodebuild -scheme OPS -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' build-for-testing` then `test` → green.
- [ ] **Runtime smoke (optional but preferred):** launch sim, run Guided end-to-end with the Vinyl case; confirm rows in Supabase (`catalog_items/variants/option_values/stock_units`) for the test company.
- [ ] **Bible:** update `07_SPECIALIZED_FEATURES.md` (new "Guided Stock Setup" section + §14 notification entry), `03_DATA_ARCHITECTURE.md` only if any additive change (none expected), and set this spec/plan status to "implemented". Mirror nothing else.
- [ ] **Bug record:** update `bug_reports` `5b3d4c39-…` → `in_progress` then `resolved` with `fix_notes` + commit refs (standing authorization for bug rows).
- [ ] Final atomic commits by name; **do not push** (await explicit permission).

---

## Self-Review (run after writing — done)

- **Spec coverage:** every spec section maps to a phase — engine reuse (§5)→P1/P6; flow/screens (§6/§7)→P2–P6; structuring (§14)→P3; field-completeness (§11)→P3/P4 tests; states (§8)→P2/P6; permissions (§10)→P2/P5; hardenings (§12)→P1; notification (§9)→P6; data mapping (§17)→P3–P6.
- **Decisions:** D1/D2/D4 resolved above; D3 owned by Task 3.1 tests.
- **Type consistency:** `CatalogSetupCommitService`, `GuidedStockSetupModel`, `GuidedStockStructuring`, `CommitProgress` names used consistently across tasks.
- **No placeholders:** logic tasks carry real interfaces + real test cases; view tasks reference the spec's screen designs (source of truth) + token table rather than duplicating them (DRY).

## Execution

Recommended: **subagent-driven-development** — fresh subagent per task, two-stage review, phases in order (P1 first; P3–P5 structure subviews can parallelize after P2). Worktree-isolate if a parallel iOS session is active (copy `Secrets.xcconfig`).
