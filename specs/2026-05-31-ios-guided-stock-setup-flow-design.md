# Guided Stock Setup — Design Spec

**Date:** 2026-05-31
**Project:** IOS GUIDED STOCK SETUP - P1
**Status:** Design approved (PM-delegated). Ready for implementation planning.
**Repos in scope:** `ops-ios`, `ops-software-bible`
**Source bug records (Supabase `bug_reports`, project `ijeekuhbatykdomumfjx`):**
- `5b3d4c39-b05e-4733-b613-8fa1aff27804` — feature_request, ios, `Catalog.Stock.List`, 2026-05-30. "Need to build a wizard to help the user set up their inventory… a series of questions in plain English… at each step we tell the user the equivalent property in OPS."
- (Parked, separate task) `a472ca5d-30b5-4d1b-ae00-f2a86affa58f` — detent sheet for the stock card. **Out of scope for this spec.**

Builds on `2026-05-21-ios-catalog-inventory-setup-redesign.md` (the catalog model + 8-phase plan) and the shipped `CatalogSetupFlowSheet` (the "Advanced" flow, phases 3–6).

---

## 1 · Problem

The catalog/stock system is fully built and the data model is sound: `Family → Attributes → Values → Variants → Physical Stock Units`, committed by an atomic server RPC. But the only setup surface — `CatalogSetupFlowSheet` — is organized around the **schema**: steps named FAMILY / ATTRIBUTES / MATRIX / VARIANTS / STOCK, with a STOCK step that exposes raw model fields (`unitKind`, `widthValue`, `originalLengthValue`, `remainingLengthValue`, `lengthUnit`, `status`). It only makes sense to an operator who already thinks in our terms. Founder's own rating: **4/10** — "fine if you know the database."

The reporter hit the exact failure: setting up Vinyl, they figured out family/variant/stock but couldn't model **"how many cuts at what lengths."** Worse, building one item at a time invites a structural trap — log "black vinyl," log "white vinyl," then realize too late that Vinyl should have been **one family with color as a variant.** A first-run operator who sets it up wrong rarely comes back to fix it. **Setup correctness is a stickiness lever.**

## 2 · Goal

A **conversational, multiple-choice, first-run setup flow** that asks about the operator's physical reality, infers the correct structure across their *whole* list, teaches the OPS equivalent at each step, and **creates the data itself** — through the proven engine, not a parallel path. Material-agnostic (vinyl is a proving case, never hardcoded).

## 3 · Naming & positioning (important)

This is **"Guided Stock Setup"** — a self-contained setup flow, a sibling to the Advanced `CatalogSetupFlowSheet`.

It is **NOT** an OPS *Wizard* in the existing-framework sense. `OPS/OPS/Wizard/` is a **coach-mark / guided-tour** system (`WizardDefinition`, `.wizardTarget()` glow, instruction-bar overlay, orange `wizardAccent` #EB8C26, `completionNotification`s) that highlights *real* UI and walks a user through it. Coach-marking the existing jargon-heavy sheet would not solve the problem — the flow itself is the problem. Therefore Guided Stock Setup:
- is its own full-screen flow (not a coach-mark overlay),
- uses **standard flow styling** — steel-blue `OPSStyle.Colors.primaryAccent`, **never** `wizardAccent` (orange stays reserved for coach-marks),
- does **not** register a `WizardDefinition`.

Colloquially the team calls this "the wizard." In code it is `GuidedStockSetup*`. (A coach-mark tour that later teaches operators how to *use* inventory is a clean, separate follow-up.)

## 4 · Scope

**In:** end-to-end setup — Stock (families/attributes/variants/physical units) **and** Products **and** Bundles **and** recipe links; capture-everything-up-front; deterministic structure detection + conversational confirmation; offline build with held commit + draft resume; commit through the existing engine; completion notification.

**Out:** the detent sheet (parked); the Advanced flow's internals beyond the three hardenings in §12; any model-assisted/LLM structuring (explicitly declined — deterministic only); web parity; the older `inventory_*` system (this targets the `catalog_*` system, screen `Catalog.Stock.List`).

**Non-goals:** no material-specific code/enums/copy; no new write path; no schema migration unless §11 proves one is strictly required (default: additive-only, reuse existing tables).

## 5 · Architecture — reuse the engine

Verified by direct read of `CatalogSetupFlowSheet.commitSetup()` (lines 2205–2302), `CatalogSetupWorkflow` (`Services/CatalogSetupWorkflow.swift`), `CatalogRepository.saveCatalogSetup` and the server function list.

**Commit contract (reused verbatim):**
1. Build `[CatalogSetupAttributeDraft]` + `[CatalogSetupVariantDraft]` (each with nested `[CatalogSetupStockUnitDraft]`) — the same `Codable` draft structs the Advanced flow uses.
2. `CatalogSetupWorkflow.generateVariantDrafts(attributes:invalidCombinations:)` → the variant matrix.
3. `CatalogSetupWorkflow.makeSavePayload(...)` → `CatalogSetupSavePayload`.
4. `CatalogSetupSaveAttempt.resolve(...)` → idempotency key.
5. `CatalogRepository.saveCatalogSetup(idempotencyKey:payload:)` → **atomic, idempotent** server RPC `catalog_setup_save(p_company_id, p_idempotency_key, p_payload)`. Dedupe via `catalog_setup_save_requests(idempotency_key, request_hash)`.
6. Reconcile server IDs into SwiftData (see §12 — extracted to a shared service).

**Key constraint:** `makeSavePayload` commits **one family (+ at most one linked product) per call.** The guided flow captures *many* items, so commit is **orchestrated**:
- **Default:** per-family loop over `catalog_setup_save` — each call atomic + idempotent, so the loop is **resumable** (a mid-loop failure leaves prior families saved; retry re-sends only unfinished families; idempotency makes re-sends safe).
- **Alternative:** the bulk `catalog_import_apply(p_company_id, p_payload)` / `catalog_import_validate` RPCs.
- **PLAN MUST RESOLVE (D1):** loop-vs-bulk. Decide by reading the `catalog_import_apply` contract (payload shape, atomicity, id-map return, whether it supports stock units + products + bundles). If import covers the full graph atomically, prefer it (one call, one progress state). If not, loop `catalog_setup_save`. Either way the UX is the same: a single "BUILD IT" with progress + resumability.

**No parallel write path. No new server function (unless D1 picks import and it needs an additive extension — additive only).**

## 6 · The flow

Full-screen flow (MOBILE.md §6.3 / §12: *complex multi-step → full-screen push, not a sheet*). Five stages:

```
 entry ──▶ 0 PRIME ──▶ 1 CAPTURE ──▶ 2 STRUCTURE ──▶ 3 BLUEPRINT ──▶ 4 DONE
            intro       brain-dump     conversational   confirm/edit    summary
            (1 screen)  everything     per-group Qs     + warnings      + commit progress
                                       (branching)                       + notification
```

**Entry points:**
- Empty catalog (no active `catalog_items`/`catalog_variants` for company) → Stock empty state primary CTA **`SET UP STOCK`** opens Guided. Secondary: `// ADVANCED` opens `CatalogSetupFlowSheet`.
- Non-empty Stock view → persistent **`GUIDED SETUP`** action (alongside existing add controls).
- Advanced sheet header → **`GUIDED SETUP`** entry (so a stuck operator can switch down to guided).

**Permission gate (entry + commit, granular — never by role):** require `catalog.manage` (family/attribute/variant authoring). Product/bundle/recipe sub-steps additionally require `catalog.products.manage`; if absent, those sub-steps are silently skipped (stock-only path still completes). Stock counts require `catalog.stock.adjust` (held by anyone who can run setup). See §10.

## 7 · Screens

All copy below is the **shipping draft** (ops-copywriter, OPS product voice: terse, foreman-plain, sentence case for content / UPPERCASE for authority, no emoji, no exclamation). Tokens reference `OPSStyle` (iOS) per MOBILE.md.

### 0 · PRIME
One screen. Sets expectation, removes fear.
- Title (Cake Mono): `SET UP STOCK`
- Body (Mohave): "Let's get everything you stock or sell into OPS. First you'll dump it all out — don't worry about organizing. Then we'll sort it into the right shape together."
- Bottom CTA (primaryAccent, 52pt): `START →`
- Note: `// Takes a few minutes. You can stop and pick up where you left off.`

### 1 · CAPTURE — brain-dump
Get the full list out first (prevents the structure trap).
- Title: `WHAT DO YOU STOCK OR SELL?`
- Sub: "Add each thing. We'll organize it next."
- Repeating input rows: name field (text input, 48pt, Mohave 15) + a 3-way picker chip `STOCK · SELL · BOTH` (36pt chip exception, MOBILE.md §4.3).
- Placeholder: "Name it — vinyl, screws, install labor…"
- `+ ADD` row; keyboard "next" adds another.
- Empty state: hero `—` + `// ADD YOUR FIRST ITEM`.
- Bottom CTA: `ORGANIZE →` (enabled at ≥1 item).
- `// IN OPS:` deferred here — capture stays pure.

### 2 · STRUCTURE — the anti-trap engine
The flow reads the whole list, proposes groupings, and branches per group. Conversational, multiple-choice. Each answer is stamped with the OPS equivalent.

**2a · Grouping (per detected cluster):**
- "These look like the same thing:" → the clustered items (e.g. *vinyl black · vinyl white · vinyl grey*).
- `[ YES — ONE ITEM ]` `[ NO — KEEP SEPARATE ]`
- `// IN OPS: one Family, with versions called Variants`
- Singles (no cluster): "Is **{name}** one thing, or does it come in versions?" `[ ONE THING ]` `[ DIFFERENT VERSIONS ]`

**2b · Name the difference (if versions):**
- "What's different between them?" multi-select chips: `COLOR · SIZE · WIDTH · LENGTH · THICKNESS · GRADE · OTHER` (OTHER → name it).
- Detected differing tokens pre-fill the values: "What are the options?" → editable value list pre-populated from capture (e.g. Black / White / Grey).
- `// IN OPS: that's an Attribute; each option is a Value`
- Multiple differing dimensions → repeat for each (Color **and** Width → two attributes). The flow shows the resulting count: "That's **6** versions." `// IN OPS: 6 Variants`

**2c · Measurement (per family):**
- "How do you keep track of how much you have?" `[ BY THE PIECE ]` `[ BY LENGTH ]` `[ BY AREA ]`
- `// IN OPS: sets the Unit and whether stock is counted or measured`

**2d · Stock reality (the Vinyl fix):**
- *By the piece:* "How many do you have?" per variant (numeric). `// IN OPS: on-hand quantity`
- *By length / area:* "What's one full unit?" → `[width]` (area only) × `[length]` + unit pickers. "How many full ones?" → count. "Any leftover or offcut pieces?" → repeating `[remaining length]` (× same width) rows.
- `// IN OPS: each full one and each offcut is a Stock Unit — we track remaining length so cut lists stay honest`

**2e · Products / bundles / recipe (items tagged SELL or BOTH; requires `catalog.products.manage`):**
- "Do you sell **{name}** on its own, or as part of a package?" `[ ON ITS OWN ]` `[ IN A PACKAGE ]` `[ BOTH ]`
- If stocked + sold: "Does selling one use up your stock?" `[ YES ]` `[ NO ]` → recipe link (`product_materials`). `// IN OPS: a recipe link — selling draws down inventory`
- Package: "What goes in the package?" pick from captured items; mark each `REQUIRED` or `SUGGESTED`. `// IN OPS: a Bundle with required + suggested add-ons`

### 3 · BLUEPRINT — confirm before any write
- Title: `YOUR BLUEPRINT`
- Sub: "Here's how we'll set it up. Tap anything to change it."
- Per-family card (L1 surface): name · "Color × Width → 6 variants" · "tracked as rolls + 1 offcut" · inline warnings (`⚠ 2 versions missing a code`, non-blocking).
- Per-product/bundle card: "consumes Vinyl · 1 roll per job" / "Install Kit · 4 items (2 suggested)".
- Edit routes back to the relevant 2x step for that family.
- Bottom CTA: `BUILD IT →`.

### 4 · DONE — commit + summary
- On `BUILD IT`: orchestrated commit (§5) with progress: "Building… 2 of 3." Offline → see §8.
- Success screen: `STOCK SYSTEM BUILT` + summary line (JetBrains Mono numbers): "2 families · 6 variants · 7 rolls · 1 offcut · 1 product · 1 bundle."
- Success haptic (`UINotificationFeedbackGenerator .success`). Completion **notification** (§9).
- Actions: `[ DONE ]` (→ Stock list, scrolled to new families) · `[ REFINE IN ADVANCED ]` (→ `CatalogSetupFlowSheet` on a chosen family) · `[ ADD MORE ]` (→ new Capture).

## 8 · States (every stage)

| State | Behavior |
|---|---|
| **Loading** | Catalog shell + flow render immediately; units/categories/capabilities load behind. Never block capture. |
| **Empty** | Capture with 0 items → `—` + `// ADD YOUR FIRST ITEM`; `ORGANIZE` disabled. Blueprint with 0 committable families → `BUILD IT` disabled with `// NOTHING TO BUILD YET`. |
| **Error (commit)** | Per-family failure surfaces `// ERROR — COULDN'T BUILD {family}` + `RETRY` (rose). Already-built families persist. Draft stays. Idempotency makes retry safe. |
| **Offline** | Capture + structure + blueprint fully usable. `BUILD IT` → `// OFFLINE — BUILD HELD`; CTA disabled, draft held, banner explains. Mirrors Advanced flow's offline lock. Re-enables on reconnect. |
| **Success** | §4 summary + haptic + notification. Draft cleared only after all families commit ok. |
| **Background / kill** | Draft persisted continuously (capture, structure answers, blueprint) via the draft store (§13). Resume re-enters at the last stage. |

## 9 · Notification

On successful completion, post the standard OPS notification (per `07_SPECIALIZED_FEATURES.md` §14): type **standard**, title e.g. `STOCK SYSTEM BUILT`, body the summary counts, `actionUrl` → catalog/stock, `actionLabel` `VIEW STOCK`. If commit is partial (some families failed), no success notification; the in-flow RETRY governs. (iOS posts via the existing notification pathway used by other iOS-originated events.)

## 10 · Permissions (granular — never role)

Per project rule (`feedback_never_filter_by_role`): gate on `has_permission` / granular permission, never `role ==` or `.in("role", …)`.

| Capability | Permission | If absent |
|---|---|---|
| Run Guided Setup; author family/attributes/variants | `catalog.manage` | Entry hidden; flow unreachable |
| Set stock counts / rolls / offcuts | `catalog.stock.adjust` | Stock quantity steps read-only (rare; `catalog.manage` implies adjust in practice — verify in plan) |
| Products / bundles / recipe steps | `catalog.products.manage` | 2e silently skipped; stock-only path completes cleanly |

## 11 · Field-completeness map (no dead-ends)

Every field the commit payload **requires** is collected by a question, so following only the guided flow always yields a committable, complete setup. (Derived from `makeSavePayload`, lines 1389–1582.)

| Payload field | Required? | Collected by |
|---|---|---|
| `family.name` | yes (non-empty) | Capture name / group stem |
| ≥1 enabled variant | yes | Always — single variant if "one thing", else matrix |
| `variant.optionValueClientIds` | for multi-variant | 2b values |
| `variant.quantity` | effectively | 2d (count) or mirrored from stock units |
| `family.unitId` / `variant.unitId` | for length/area | 2c measurement → mapped to a `catalog_units` row |
| `stockUnit.unitKind` / dims / `status` | for length/area | 2d full-unit + offcut answers |
| `stockUnit.quantityValue > 0` | yes (hardening) | 2d count; validated positive (§12) |
| `variant.sku` | optional | Not forced — many operators have no SKUs; offered, never required |

**PLAN MUST RESOLVE (D2):** unit handling. `makeSavePayload` references an existing `catalog_units.id`. The measurement answers (piece → "each", length → "ft", area → "sq ft") must map to real `catalog_units` rows. Verify whether `catalog_setup_save` can create units inline or whether the flow must ensure the company's default units exist first (seed/select). Read `CatalogUnit` seeding + the RPC before building 2c.

## 12 · Existing-flow hardenings (folded into this work)

The audit (verified by direct read) confirmed the engine is **sound — server commit is atomic + idempotent.** The findings are client-side robustness; because the guided flow reuses this path, the fixes ship here and benefit both flows. **Refactor:** extract `commitSetup()` payload-build + `reconcileSuccessfulSave()` from the `CatalogSetupFlowSheet` *view* into a shared `CatalogSetupCommitService` consumed by both Advanced and Guided.

1. **Reconcile-after-success is not a failure.** `CatalogSetupFlowSheet.swift` ~2289–2301: if `reconcileSuccessfulSave`/`modelContext.save()` throws *after* `response.ok`, the server already committed; current code shows an error. Fix: catch reconcile errors separately → log + trigger a catalog resync + show **success** (data exists; local cache will be consistent post-sync). Never report a committed save as failed.
2. **Capability probe transient errors.** `CatalogSchemaCapabilityGate.refresh` treats any probe failure as "feature unavailable," which can block a stock commit on a flaky network. Fix: distinguish table-missing from network error; on network error, don't hard-block — proceed and let the server be the authority.
3. **Zero-qty stock units.** `makeSavePayload` line 1482 `max(0, quantityValue)` permits 0. Fix: guided flow validates `> 0` before blueprint→commit; shared service rejects non-positive stock-unit quantities.

## 13 · Draft persistence

Reuse the `CatalogSetupDraftStore` pattern (file-based, `Documents/…`, context-keyed by company+user). Extend the snapshot to hold the **multi-item guided state**: captured items, per-group answers, measurement + stock answers, product/bundle answers, blueprint edits, and commit progress (which families already committed — for resumable commit). Schema-versioned; on version mismatch, discard silently (acceptable) **but** log. Cleared only after full successful commit.

## 14 · Structuring intelligence (deterministic — D-spec)

No model/LLM. The "intelligence" is clustering + question design; the operator always confirms.

**Clustering (proposes; never auto-merges):**
- Normalize each captured name: lowercase, trim, tokenize, strip pure-number/unit tokens.
- Cluster by shared significant tokens (leading-stem match + token-set similarity above a threshold — exact algorithm + threshold set in plan/tests).
- For a cluster: stem → family-name candidate; the per-item differing tokens → candidate attribute value set; count of differing token *positions* → number of candidate attributes.
- Confirmation is mandatory (2a). Over-grouping is safe — operator taps `NO — KEEP SEPARATE`. Under-grouping is safe — singles fall to the "one thing / versions" path.

**Edge cases (war-gamed, adapted wizard-audit Phase 9):**
- All-distinct list → no false clusters; each item individual.
- Spurious shared token ("screw" in "screws 2in" vs "screw gun") → operator rejects; show full item names so rejection is obvious.
- Ambiguous differing token (could be size or grade) → ask (2b chips); never guess silently.
- Single captured item → skip clustering; straight to versions question.
- Duplicate names → de-dupe with a confirm ("two of these — same thing?").
- Very long list → blueprint is the safety net (full review before any write); commit batched with progress.

## 15 · Edge cases & war-game (adapted)

Coach-mark-specific audit phases (glow targets, instruction-bar, exit-notification wiring, `targetScreen`) are **N/A** (self-contained flow). Applicable:

- **Back-nav within flow:** every stage supports back without losing answers (state held in the flow model + persisted).
- **Skip/empty:** required questions can't be skipped to a dead-end; optional ones (SKU, thresholds, products) skippable.
- **Double-commit:** idempotency key per family payload prevents duplicate server rows on re-tap/retry.
- **App background mid-flow / mid-commit:** draft + commit-progress persisted; resume safe (committed families not re-sent except via idempotent retry).
- **Offline mid-commit / connection drop mid-loop:** committed families persist; remaining held; banner + RETRY.
- **Sync conflict (another user edits catalog during flow):** server is authority; reconcile resyncs; blueprint re-validates on entry.
- **Capability `catalogStockUnits` false:** detected up front (capability refresh on flow entry); if stock units can't commit, surface before blueprint, not as a commit dead-end (and per §12.2, don't false-negative on transient errors).
- **Concurrent setup:** only one setup surface at a time; opening Guided while Advanced has an open draft → prompt to resume/replace (don't silently clobber the Advanced draft — distinct draft context key).

## 16 · Component / token table (MOBILE.md + OPSStyle)

| Element | Token / spec | Notes |
|---|---|---|
| Canvas | L0 `#000` | one optional corner glow max |
| Stage / question card | L1 (`rgba(18,18,20,.58)` + blur, hairline, radius 10) | section container |
| Item / option row | L2 (`rgba(255,255,255,.04)`, hairline, radius 6) | never L2-in-L2 |
| Primary CTA (`START/ORGANIZE/BUILD IT`) | `primaryAccent` fill, 52pt, radius 5, Cake Mono 14 up | one per screen, bottom-anchored |
| Multiple-choice option | option row (≥48pt) or chip (36pt, §4.3) | single-select = rows; multi = checkboxes (olive ✓) |
| Text input (name) | 48pt, `rgba(255,255,255,.04)`, hairline, focus = brighter white (no accent) | |
| Numeric input (dims/counts) | 48pt, decimal pad, JetBrains Mono value | tabular, slashed zero |
| `// IN OPS:` teach line | JetBrains Mono 10–11, `--text-3`, `//` prefix | left-aligned, never decorative |
| Section title | Cake Mono 28, uppercase, left | nav title |
| Progress (stage N of 5) | thin top indicator, `--text` (not accent) | |
| Accent | steel-blue `primaryAccent` ONLY on the one CTA | **never** `wizardAccent` |
| Motion | one curve `cubic-bezier(0.22,1,0.36,1)`; screen push 300ms; reduced-motion → 150ms opacity | no spring/bounce |
| Haptics | light on stage advance; medium on commit; success on done | no spam |

## 17 · Data mapping (questions → tables)

| Question | Reads | Writes (via `catalog_setup_save`) |
|---|---|---|
| Capture name + type | — | staged → `catalog_items` |
| Grouping / versions | — | `catalog_items` (one family) |
| What's different / options | — | `catalog_options`, `catalog_option_values` |
| (derived) variant matrix | — | `catalog_variants`, `catalog_variant_option_values` |
| Measurement | `catalog_units` | `catalog_items.default_unit_id` / variant `unit_id` (+ unit row per D2) |
| Full units + offcuts + counts | — | `catalog_stock_units` (+ `catalog_stock_unit_events` if used) |
| Sell on its own | `products` | `products` / `products.linked_catalog_item_id` |
| Selling uses stock | `products`, `catalog_*` | `product_materials` (recipe) |
| Package | `products` | `products.kind=package`, `product_bundle_items` (+ required/suggested per capability) |

## 18 · Decisions (resolved 2026-05-31 against prod schema; see PLAN)

- **D1 — commit orchestration: RESOLVED → per-family loop over `catalog_setup_save`.** `catalog_import_apply` only inserts flat `catalog_items` + `catalog_variants` (no attributes, option values, variant joins, stock units, products, or bundles), so it cannot build the guided graph. The loop is atomic per family, idempotent, and resumable.
- **D2 — unit handling: RESOLVED → units must pre-exist; flow ensures them.** `catalog_import_validate` (and the save path) reject a `unit_id` that isn't an active `catalog_units` row for the company. The flow maps measurement → dimension (piece→`count`/each, length→`length`/ft, area→`area`/sq ft) and creates the unit if missing before commit. Exact `CatalogRepository` create method confirmed in PLAN Phase 4.
- **D3 — clustering algorithm + threshold:** owned by PLAN Task 3.1 — normalized-token stem + Jaccard similarity, threshold tuned by tests (vinyl colors, screw sizes, two-dimension cases, all-distinct).
- **D4 — required/suggested bundle children: RESOLVED → no migration.** `product_bundle_items` already carries `relationship_kind` (default `'required'`), `suggestion_reason`, and `compatibility_selector`. Use the existing columns.

## 19 · Pre-implementation checklist (acceptance criteria)

**Design-system compliance**
- [ ] All color/spacing/radius/type via `OPSStyle` tokens; zero hardcoded values.
- [ ] `primaryAccent` only on the single bottom CTA per screen; `wizardAccent` never used.
- [ ] Numbers JetBrains Mono, tabular, slashed zero, formatted; empty = `—`.

**Flow & completeness**
- [ ] Every commit-required field (§11) has a collecting question; no path reaches a disabled `BUILD IT` for a valid answer set.
- [ ] Following only the guided flow yields a complete, useful setup (variants, stock, links) — no half-built records.
- [ ] Capture → Structure → Blueprint → Commit reachable and reversible; back-nav loses nothing.

**Engine reuse & robustness**
- [ ] Commit goes through the shared `CatalogSetupCommitService` (no parallel write path).
- [ ] D1 resolved; commit is atomic-per-family, resumable, idempotent.
- [ ] §12 hardenings landed and covered by tests (reconcile-as-success, transient-capability, positive-qty).

**States & lifecycle**
- [ ] Loading / empty / error / offline / success all handled per §8.
- [ ] Draft persists + resumes on background/kill; commit progress survives.
- [ ] Offline builds; commit held with clear copy; re-enables on reconnect.

**Permissions**
- [ ] Entry + each sub-step gate on granular permissions (§10); never role.

**Motion & a11y**
- [ ] One easing curve; reduced-motion fallback; haptics per §16.
- [ ] Touch targets ≥44pt (chips 36pt only); text contrast ≥4.5:1 (outdoor-lifted per MOBILE.md §1); option state not color-only.

**Tests**
- [ ] Clustering/structure-inference unit tests (D3 cases in §14).
- [ ] Variant-matrix generation via `generateVariantDrafts` for guided inputs.
- [ ] Commit orchestration: multi-family success, mid-loop failure + resume, offline hold, idempotent retry.
- [ ] Field-completeness: generated payload always committable for every branch.

**Verification & bible**
- [ ] `xcodebuild -scheme OPS -destination 'generic/platform=iOS'` clean; `build-for-testing` + `test` on simulator green.
- [ ] `03_DATA_ARCHITECTURE.md` (if any additive schema), `07_SPECIALIZED_FEATURES.md` (Guided Stock Setup section + §14 notification), and this spec's status updated in lockstep.

## 20 · Phasing (for the implementation plan)

1. **Shared commit service + hardenings** — extract `CatalogSetupCommitService`; land §12 fixes; tests. (Unblocks both flows; lowest risk.)
2. **Guided flow shell + state model + draft persistence** — full-screen container, stage machine, entry points, permission gates, offline/lifecycle.
3. **Capture + Structure (deterministic clustering)** — D3; the branching question engine; field-completeness.
4. **Stock reality (2d) + measurement/units (D2)** — the Vinyl fix.
5. **Products / bundles / recipes (2e)** — capability-gated; D4 if needed.
6. **Blueprint + orchestrated commit (D1) + Done + notification.**
7. **Verification, device-target build, bible updates.**

---

*Copy is shipping-draft (ops-copywriter). Flow/screens designed via mobile-ux-design against MOBILE.md. Edge cases adapted from wizard-audit (self-contained-flow variant). Engine contract + audit verified by direct read of `CatalogSetupFlowSheet.swift` + `CatalogSetupWorkflow.swift` + the Supabase function list.*
