> **PARKED 2026-09-05 (Jackson: not ready for this yet).** Salvaged verbatim from ops-web branch `claude/hungry-khorana-d20ede` (`docs/inbox/vision-estimating-spec.md`, authored 2026-06-30 / 2026-07-01) before that branch is dropped. Not scheduled; the INBOX CLEAN STATE layer it builds on has shipped. Revisit when vision estimating is back on the roadmap.

# Vision Estimating — Draft-Estimate-From-Attachments Spec

> **Status:** Authored 2026-06-30; revised 2026-07-01 with Jackson's review decisions (§ Decisions locked). Design spec for review (decisions + contracts + phased build plan) — no code written.
> **Initiative:** VISION ESTIMATING. **Builds on:** INBOX CLEAN STATE (`docs/inbox/clean-state-layer-spec.md`), shipped PR #100.
> **All schemas below verified live against Supabase project `ijeekuhbatykdomumfjx` (2026-06-30). All code cited from `origin/main`.**

## Goal

When a customer emails a drawing or photos of the work (a deck layout, a fence line, a room), OPS
should **read it, do the measurement takeoff, price it against the owner's OWN catalog, and produce a
DRAFT estimate the owner reviews** — instead of the owner manually measuring and quoting. Trade-agnostic,
graceful under missing information, and **continuously learning** from the operator's corrections.

This is not a new AI pipeline. It is a **consumer + learning loop bolted onto three things that already
ship**: (1) the inbox vision step already extracts structured `facts` from customer attachments and throws
them away; (2) `EstimateService.createEstimate` already writes a `status='draft'` estimate with line items;
(3) the Phase-C learning layer already turns operator corrections into durable, embedded memories. Vision
Estimating connects these with a trade-agnostic **Takeoff** layer in between.

## The one-paragraph architecture

The inbox vision pass (`attachment-inspector.ts`) is upgraded to emit a **structured, trade-agnostic
Takeoff** (measurements + quantified items, each tagged with its source) instead of a free-form
`facts` bag. A deterministic normalizer validates it. A new **Takeoff card** renders inline on the thread,
echoing every measurement, its source (read off the drawing, or a gap to ask about), and the pricing math. The
operator confirms or corrects in-inbox; on confirm, the takeoff is priced against the company's own
`products` catalog (via a **learned** item→product map) and materialized into a `status='draft'` estimate
through the existing `EstimateService.createEstimate`. Every operator correction — a measurement, a
quantity, a rate, an item mapping, or a whole-draft accept/discard — is captured and fed back into
**per-company, per-trade learned tables** (plus an embedded `agent_memories` row so it surfaces at draft
time). Whether a trade can even be priced-from-email is itself learned from accept/discard rates. **No price
is ever auto-sent.** The estimate is always a draft the operator reviews.

## Product decisions (Jackson, 2026-06-30)

1. **v1 = inbox email only.** Customer emails a drawing/photos → the shipped web inbox vision pipeline →
   draft estimate. iOS on-site photo capture is a documented **later** entry point that reuses the same
   takeoff→estimate core (§ Phases / Later). No iOS work in v1.
2. **Review surface = in-inbox card → draft estimate on confirm.** The thread shows a proposed-takeoff card
   (measurements + source + math); the operator confirms in-inbox, which materializes the draft
   estimate. Review stays where the operator already is.
3. **Attempt silently, learn priceability from accept/reject.** On any inbound with a labeled drawing, a
   takeoff is attempted in the background. Whether a trade/company can be priced-from-email is **learned**
   from accept-vs-discard rates — not pre-configured. Nothing is ever sent automatically.
4. **Catalog mapping = auto-match by name + operator corrects, system learns.** Best-effort match detected
   items to existing `products`; the operator fixes wrong matches on the draft; corrections train a
   per-company/per-trade item→product map. Degrades to an un-priced line when no match exists.

**Derived (my calls on the parts you didn't need to decide — flag any at review):**

5. **Takeoff is a NEW general schema, not the iOS `component_type` enum.** Requirement #4 (the system must
   *learn what a trade's takeoff even looks like*) is incompatible with the fixed, deck/rail-specific
   `DesignComponentType` enum behind `company_default_products`. The extraction target is a general
   `Takeoff` (measurements + items with **learned** item keys). `company_default_products` is read as an
   optional *seed* for the learned map where it exists — never a requirement (it is **empty in prod**).
6. **Takeoff lives in a new `inbox_takeoffs` table**, not overloaded onto `attachment_inspections.facts`.
   A takeoff spans multiple attachments, has confirmation lifecycle state, and must be an audit record
   (cloning the `ai_draft_history` "AI proposed → operator edited → disposition" pattern). The per-attachment
   `facts` jsonb stays as the cheap extraction cache; `inbox_takeoffs` is the aggregated, confirmable artifact.
7. **The customer-facing draft REPLY never contains the price.** It acknowledges the attachment and says a
   quote is coming (existing drafter behavior). The price exists only inside the operator-reviewed draft
   estimate. Estimate-bearing threads are hard-barred from the `auto_send` path.

**Review refinements (Jackson, 2026-07-01):**

8. **No confidence thresholds — nothing gates on a score.** Either the system attempts a draft or it doesn't
   (that binary *is* the learned priceability decision, #3) — and once it drafts, **everything is
   operator-reviewed**. A 0–1 confidence float never branches the UX or auto-accepts anything. The only
   distinction that matters is **source**: a number is either **READ off the drawing** (used in the draft) or
   **MISSING** (a gap → ask for it, never guess). **v1 does no inference at all** (drawings are labeled;
   unlabeled → ask), so there is no "inferred / medium-confidence" middle state to gate. Confidence survives
   only as an internal learning signal (which auto-matches to double-check), never a surface the operator must
   read.
9. **This feature auto-sends NOTHING.** Not the estimate, not the ask-for-measurement reply — nothing. Every
   outbound (estimate and email alike) is a draft the operator sends. Stronger than "estimate-bearing threads
   are held": the whole feature is send-nothing-autonomously, full stop.
10. **Missing measurement → ASK (draft a reply the operator sends).** When a number needed to price the job is
    missing/unreadable, the system drafts a short reply asking the customer for that specific dimension; the
    operator reviews and sends it; the takeoff resumes when the customer answers (`source='asked'`). *(The
    "ask the customer" path — confirmed 2026-07-01: draft the question for the operator to send, not merely
    flag the gap. Matches the send-nothing-but-draft-everything model.)*
11. **Un-priced lines do NOT block the draft.** An unmapped/unpriceable item still appears on the draft
    estimate, marked "needs price"; the operator prices it (which trains the map) before **sending**. The
    estimate exists immediately; only *sending* waits on pricing.
12. **First dogfood trade = decking/railing.** The design stays trade-agnostic; this is only which trade we
    prove first.
13. **Model = `gpt-5.4` vision from the start** (quality-first policy); regress to a cheaper tier only if
    accuracy holds.
14. **Priceability autonomy trip:** rolling window of the last 10 attempts per `(company, trade)`; flip
    `attempt → manual` below 30% accept.

## What exists today (verified) — the seams we build on

| Seam | Truth (file:line, `origin/main`) | How we use it |
|---|---|---|
| Vision extraction | `attachment-inspector.ts` runs OpenAI vision → `{summary, isSignedEstimate, facts}`; `facts: Record<string,unknown>` (`types.ts:47-56`) is **captured, persisted to `attachment_inspections.facts` jsonb, rehydrated on every state build — and read by NOTHING downstream** (confirmed: only `summary` + `isSignedEstimate` are consumed). | `facts` becomes the structured `Takeoff`; the dead seam gets a consumer. |
| Cost-once cache | `attachment-ingest.ts` inspects each attachment once, UNIQUE `(company_id, message_id, attachment_id)`; **no prompt/schema-version column** → enriching the prompt will NOT re-inspect cached rows. | Add `prompt_version` (cache-bust) so takeoff extraction can evolve. |
| Model config | `inbox-models.ts` — OpenAI single-provider, quality-first; `attachmentVision = TOP = "gpt-5.4"`. The `max_completion_tokens: 500` vision ceiling is on the call itself (`attachment-inspector.ts:217`). | **Upgrade the existing `attachmentVision` call** — additive `takeoff` prompt key + raise the token budget (~1500) + stamp `TAKEOFF_SCHEMA_VERSION`. One call, not a second paid pass (see Model policy). |
| Draft injection seam | `draft-context.ts` builds `attachmentBlock`/`sentLedgerBlock` (pure, unit-tested) → woven into the system prompt at `ai-draft-service.ts:922`. | Add an `estimateAckBlock` here (acknowledge quote-in-progress; never quote a number). |
| Estimate creation | `EstimateService.createEstimate(data, lineItems[])` — RPC `get_next_document_number` → insert `estimates` (DB column defaults `status='draft'`; the estimator passes it explicitly) → insert `line_items`. `line_total` is `GENERATED ALWAYS` (never write). Header totals are app-computed (`calculateDocumentTotals`, `pipeline.ts:1091-1108`). | The materialization target. Reused verbatim + provenance columns. |
| Catalog price | `products.default_price`/`base_price` (SELL, trigger-synced — write `base_price`), `unit_cost` (COST), `pricing_unit` CHECK `{each,flat_rate,linear_foot,sqft,hour,day}`. No markup column (margin computed). Line picks snapshot `default_price`. | Rate source. Estimator owns unit↔dimension matching. |
| Component→product map | `company_default_products(company_id, component_type, product_id)` exists; vocabulary is deck/rail-specific; **0 rows in prod.** | Read as optional seed; superseded by the learned `company_item_product_map`. |
| Learning loop template | `phase-c-learning-service.ts:213-235` writes durable `memory_type='preference', source='inbox_correction', confidence=0.9` on operator correction. `agent_memories` has a `pricing` category (282 rows), pgvector retrieval, category floors. | The exact template for the takeoff/pricing correction loop. |
| Audit-row template | `ai_draft_history` (original draft, final, edit_distance, changes_made jsonb, status, disposition timestamps). | `inbox_takeoffs` clones this shape for auditable takeoffs. |
| Guardrail reality | "never auto-send" is only *scoped*: `auto_send` tenants DO dispatch email via `pending_auto_sends` + cron (`phase-c-autonomy-router.ts` `doAutoSend`). No redaction layer — "acknowledge, don't recite" is prompt-wording only. | Estimate-bearing threads forced to `draft`/hold; guardrails authored into prompt + tested for omission. |

## End-to-end flow

```
inbound customer email
  │  (existing Gmail→sync pipeline; sync-engine.ts:1091 ingestAndInspectThreadAttachments)
  ▼
1. VISION EXTRACTION  (attachment-inspector.ts, upgraded)
     per customer attachment → structured Takeoff fragment into attachment_inspections
     (cost-once, prompt_version-stamped). NEVER guesses a missing measurement.
  ▼
2. TAKEOFF ASSEMBLY  (new: takeoff-builder.ts, deterministic)
     merge per-attachment fragments → one normalized Takeoff for the thread;
     coerce units, compute item quantities from measurements (learned takeoff_rules),
     tag each number READ (off the drawing) or its gap MISSING; write inbox_takeoffs (status='proposed').
  ▼
3. CATALOG / PRICING MAPPING  (new: takeoff-pricing.ts, deterministic + learned lookups)
     each TakeoffItem.key → company_item_product_map (learned) → products (rate by pricing_unit↔dimension)
     → learned rate override (company_pricing_profile) → line preview. Unmapped item → un-priced line.
  ▼
4. IN-INBOX CONFIRMATION  (new: TakeoffCard on the thread)
     echo measurements + source chips (READ / MISSING) + auditable math. No score to eyeball —
     everything is operator-reviewed. Operator edits / asks-customer / dismisses.
  ▼
5. DRAFT ESTIMATE  (existing: EstimateService.createEstimate)
     on confirm → status='draft' estimate + line_items from confirmed TakeoffItems;
     provenance columns link estimate ↔ takeoff; persistent→resolved notification, deep-link REVIEW.
     (In parallel: customer-facing draft REPLY acknowledges attachment, no price.)
  ▼
6. LEARNING CAPTURE  (new: takeoff-learning.ts, extends phase-c-learning-service)
     every correction (measurement / quantity / rate / mapping / accept-discard) →
     learned tables (per company, per trade) + embedded agent_memories pricing memory.
     Accept/discard rate → priceability autonomy state per (company, trade).
```

## Trade-agnostic data model

The design principle: **nothing in the schema is decking-specific.** A takeoff is generic measurements +
quantified items with **learned** item keys; pricing rules and item→product mappings are learned per
`(company, trade)`; the trade vocabulary itself is learned. The system starts empty and learns a trade's
shape from usage.

### The `Takeoff` contract (extraction target)

Replaces the free-form `facts` bag with a stable, general structure. New file:
`src/lib/api/services/conversation-state/takeoff-types.ts`.

```ts
// v1 uses "read_from_drawing" | "asked" ONLY. "inferred" is reserved for the later
// scaled/photo-measurement phases (v1 never guesses a number — see decision #8).
export type MeasurementSource = "read_from_drawing" | "asked" | "inferred";
export type PhysicalDimension =
  | "length" | "area" | "volume" | "count" | "mass" | "time" | "angle" | "unknown";

/** A dimension read off the drawing (v1), or supplied by a customer answer (source='asked'). */
export interface TakeoffMeasurement {
  label: string;                 // "deck length", "fence run", "room A", as read/normalized
  value: number | null;          // null → a gap → drives the "ask the customer" path (never a guess)
  unit: string;                  // normalized: ft, in, m, cm, sqft, sqm, lf, ea, deg, hr
  dimension: PhysicalDimension;
  source: MeasurementSource;     // provenance — the ONLY thing the card gates on (READ vs MISSING)
  rawText: string;               // "14ft x 20ft" verbatim, for audit
  confidence: number;            // 0..1 — INTERNAL learning signal only; never a UX gate (decision #8)
  evidence?: { attachmentId: string; region?: string; page?: number };
}

/** A quantified work item — the takeoff proper. `key` is a LEARNED normalized token. */
export interface TakeoffItem {
  key: string;                   // learned item key: "deck_board", "railing_section", "fence_panel", "gate"…
  label: string;                 // human label as read ("pressure-treated 2x6 decking")
  quantity: number | null;
  unit: string;                  // matches a company pricing_unit family
  dimension: PhysicalDimension;
  derivedFrom: string[];         // measurement labels used → makes the math auditable
  computation: string;           // "20ft × 14ft = 280 sqft" — shown in the card, never hidden
  source: MeasurementSource;
  confidence: number;            // internal only (learning signal), never a UX gate
}

/** What the vision step could NOT read → the ask-the-customer driver. */
export interface TakeoffGap {
  need: string;                  // "deck width", "fence height"
  reason: "unlabeled" | "illegible" | "ambiguous_unit" | "out_of_frame";
  blocksItems: string[];         // item keys that can't be quantified without it
}

export interface Takeoff {
  schemaVersion: string;         // pin — cache-bust + audit which contract produced it
  trade: string | null;          // inferred trade label (learned vocab); null = unknown
  drawingPresent: boolean;
  priceable: boolean;            // model's own read on "can this be quantified?"
  measurements: TakeoffMeasurement[];
  items: TakeoffItem[];
  gaps: TakeoffGap[];            // non-empty → degrade to ask-customer for the missing numbers
  confidence: number;            // 0..1 overall — internal/telemetry only, never gates the UX
  notes: string;                 // free text for the operator
}
```

The vision prompt (the existing inspection call, extended with a `takeoff` key) is authored to emit exactly
this JSON, and **must keep `summary` populated** whenever it emits items — an empty `summary` is read by the
router as "failed inspection" and forces human review (`router.ts:57-61`). Extraction **never fabricates a
missing number**: an unreadable dimension yields `value: null` + a `TakeoffGap`, never a guess
(requirement #2/#3).

### Learned tables (per company, per trade) — start empty, learn from usage

All new tables: `company_id uuid NOT NULL`, `user_id text` where a user is referenced (Firebase-bridged —
never cast `sub`→uuid, per the crit3 gotcha), free-text `trade` (there is **no `trade` column anywhere in
the catalog/company model today** — this is the genuinely new axis), nullable-additive, RLS company-scoped,
and **exempt from memory-decay GC** (unlike `agent_memories`, which prunes unaccessed rows — corrected rates
must not evaporate).

| Table | Grain / purpose | Key columns |
|---|---|---|
| `inbox_takeoffs` | One per thread's takeoff attempt; the auditable artifact + lifecycle. Clones `ai_draft_history`. | `id, company_id, provider_thread_id, opportunity_id?, trade?, status ('proposed'\|'confirmed'\|'estimated'\|'awaiting_customer'\|'dismissed'), takeoff jsonb, confidence, model, schema_version, source_message_ids text[], estimate_id?, created_at, confirmed_at?, confirmed_by uuid?, disposition text?` |
| `company_item_product_map` | Learned item→product resolution (Q4). Sibling of `company_default_products` but learned + trade-scoped. | `company_id, trade, item_key, product_id, label_aliases text[], confidence, samples int, last_corrected_at` — UNIQUE `(company_id, trade, item_key)` |
| `company_pricing_profile` | Learned rate per item/unit (rolling average). Sibling of `agent_writing_profiles`. | `company_id, trade, item_key, unit, learned_rate numeric, rate_low numeric, rate_high numeric, samples int, confidence, last_corrected_at` — UNIQUE `(company_id, trade, item_key, unit)` |
| `takeoff_rules` | Learned quantity math per trade ("deck area = L×W", "railing lf = perimeter − gate widths", "+10% waste"). This is *how a trade's takeoff is computed* — learned, not coded. | `company_id, trade, rule_key, rule jsonb, confidence, samples, last_corrected_at` |
| `company_trade_estimating_state` | Learned priceability + autonomy (Q3). | `company_id, trade, attempts int, accepts int, discards int, autonomy_state ('attempt'\|'manual'\|'disabled'), updated_at` — UNIQUE `(company_id, trade)` |

The takeoff item `key` vocabulary is **not a fixed enum** — it is whatever the model emits, normalized and
reinforced through `company_item_product_map`. A brand-new trade starts with an empty map; the first few
estimates auto-match by name (Q4) and the operator's corrections seed the vocabulary. `company_default_products`
(existing, empty) is consulted as a seed when a `component_type` happens to match an `item_key`.

## Pricing — mapping to each company's own catalog

Pricing is deterministic given the learned lookups; the AI never invents a price.

1. **Item → product.** For each `TakeoffItem.key`, resolve a `products` row via `company_item_product_map`
   (learned; Q4). On a miss: best-effort name/kind match against `products` (fuzzy on `name`, filter by
   `type`/`kind`), proposed to the operator as a **suggested** mapping. Still a miss → **un-priced line**
   (line kept, `unit_price = 0`, flagged "needs price"). Never blocks the takeoff — the draft estimate is
   still created with the un-priced line present; only *sending* waits until the operator prices it
   (decision #11).
2. **Unit match.** The takeoff item's `dimension` must match the product's `pricing_unit` family
   (`sqft`→`area`, `linear_foot`→`length`, `each`→`count`, `hour`→`time`, `flat_rate`→whole). There is **no
   DB link between `pricing_unit` and `catalog_units.dimension`** — the estimator owns this matching. A unit
   mismatch (sqft takeoff, each-priced product) → surface for operator, don't auto-price.
3. **Rate.** SELL rate = learned override in `company_pricing_profile` if present (operator has corrected
   this item's rate before), else `products.base_price`/`default_price` (snapshot-copied, per current line
   behavior). COST = `products.unit_cost` (nullable). **Markup is computed, never stored** — no markup
   column exists; if the operator prices from cost, the estimator writes the resulting sell price into
   `unit_price`.
4. **Line total.** Never written — `line_items.line_total` is `GENERATED ALWAYS =
   round(quantity*unit_price*(1-discount%/100), 2)`. Header `subtotal/tax_amount/total` are computed
   app-side and snapshotted — the estimator must replicate the `calculateDocumentTotals` rollup
   (`pipeline.ts:1091`); the web create modal hand-rolls the equivalent inline reduce
   (`create-estimate-modal.tsx:109-142`).
5. **BOM (later phase).** `product_materials.quantity_per_unit` explodes a line into material demand
   (`line qty × quantity_per_unit → line_item_materials`). Not in v1 pricing; noted for the materials phase.

Web does **not** resolve `product_pricing_modifiers` (option/tier pricing is iOS-only via
`configured_options`/`resolved_unit_price`, which the web estimate path never writes). v1 prices off flat
`base_price`; option-adjusted pricing is out of scope and flagged for the operator when a product has
modifiers.

## The learning loop — signals, storage, feedback

Extends the Phase-C learning layer; does not fork it. Every operator interaction on the Takeoff card or the
draft estimate is a labeled training signal.

| # | Signal (operator action) | Captured as | Stored where | Feeds back into |
|---|---|---|---|---|
| 1 | Corrects a **measurement** (e.g. 14ft → 16ft) | measurement-correction event + provenance | `lead_field_provenance`-style row on `inbox_takeoffs`; a `takeoff_rule` only if systematic (e.g. always adds waste) | future extraction prompt hints + takeoff math |
| 2 | Corrects a **quantity / computation** | rule-correction | `takeoff_rules(trade, rule_key)` (rolling reinforce) | quantity computation for that trade |
| 3 | **Remaps** an item to a different product | mapping-correction | `company_item_product_map` upsert + reinforce (`confidence += `, `samples++`) | item→product resolution |
| 4 | Changes a **unit price** | rate-correction | `company_pricing_profile` rolling-average update **+ embedded `agent_memories` row** (`memory_type='correction', category='pricing', source='estimate_correction', source_id=<takeoff/estimate id>, confidence=0.9`, natural-language content so it embeds and surfaces at draft time) | rate resolution + draft-time pricing context |
| 5 | **Confirms** the whole draft (→ estimate) | positive priceability + all above as accepted | `company_trade_estimating_state.accepts++` | autonomy for that trade |
| 6 | **Dismisses** the draft | negative priceability | `company_trade_estimating_state.discards++` | autonomy for that trade |

**Priceability learning (Q3).** `company_trade_estimating_state.autonomy_state` transitions on a rolling
window of the **last 10 attempts** per `(company, trade)`: stays `attempt` (keep trying silently) while the
accept-rate holds; **below 30% accept → `manual`** (stop auto-attempting; require the per-thread trigger);
explicit operator opt-out → `disabled`. This is how "whether a trade CAN price-from-email" is learned rather
than configured (decision #14).

**Two storage grains, deliberately.** Structured numeric learning (rates, mappings, rules) lives in the new
typed tables (queryable, decay-exempt, keyed). A **mirror `agent_memories` row** is also written for rate
corrections so the existing embedded retrieval (`match_memories`, category floors) surfaces the operator's
own corrected prices at draft/quote time **with zero new retrieval code**. The typed table is the source of
truth; the memory is the retrieval convenience. (Rationale: `agent_memories` dedup is a fuzzy
ILIKE-first-50-chars proxy and its GC prunes unaccessed rows — unsafe as the *only* home for money.)

**Cost discipline.** Any "re-price similar items" fan-out inherits the existing hard cap
(`phase-c-learning-service` caps reclassify fan-out at 10) — no unbounded re-embedding.

## Graceful-degradation decision tree

The feature detects what's available and does what's possible — never assumes a drawing exists or that a
price can be produced. When it can't, it degrades to asking the customer or handing to the operator.

```
inbound customer email (existing pipeline)
│
├─ customer-sent attachment present?  ── no ──▶ existing draft path; NO estimate attempted
│
├─ inspectable image/PDF (drawing or work photo)?  ── no ──▶ acknowledge attachment (existing); no estimate
│
├─ (company, trade) autonomy_state?
│     ├─ disabled ──▶ operator-only; no attempt
│     ├─ manual ────▶ no auto attempt; show "draft an estimate from this" affordance on the thread
│     └─ attempt / unknown ──▶ continue
│
├─ Takeoff extracted. drawingPresent && items quantifiable?
│     │
│     ├─ LABELED & readable (gaps empty) ──▶ build Takeoff (source=read_from_drawing)
│     │     ├─ all items mapped+priced ──▶ propose PRICED draft (in-inbox card)
│     │     └─ some items unmapped/unpriced ──▶ propose draft with un-priced lines flagged "needs price"
│     │
│     ├─ PARTIAL (some gaps) ──▶ quantify what's readable; for each gap:
│     │     └─ draft a reply ASKING the customer for the specific missing dimension (operator reviews/sends);
│     │        set inbox_takeoffs.status='awaiting_customer'; resume (source=asked) when they reply.
│     │
│     └─ UNLABELED / unreadable (all gaps) ──▶ NEVER guess.
│           └─ draft a reply asking for measurements (operator reviews/sends); no estimate yet.
│
└─ ALWAYS:
      • echo each measurement with its source: READ (off the drawing) or MISSING (a gap);
      • NEVER guess a missing number — a gap becomes an ask, not an estimate line;
      • no confidence score gates anything — the operator reviews every drafted number;
      • NEVER auto-send anything — the estimate AND any reply are drafts the operator sends.
```

Edge cases the tree handles explicitly:
- **Trade genuinely can't price from email** → learned to `manual`/`disabled`; degrades silently to
  operator-handled. Over time this becomes the known state for that trade.
- **Unlabeled/scaled sketch** (dimensions absent) → v1 asks the customer; scaled inference is a later phase,
  not a v1 guess.
- **Photo of the work (not a drawing)** → v1 acknowledges + may ask for measurements; photo-based
  measurement is a later phase.
- **Customer forwards your own estimate back** → operator-sent attachments are already excluded from
  inspection (`isOperatorSender`); a forwarded-unsigned PDF must not be read as a new customer takeoff (war-game
  in the accept-detector interaction).

## Confirmation UX (in-inbox)

A **Takeoff card** renders inline on the thread (between the latest message and the composer), following the
inbox design system: glass surface + hairline border, `//` tactical section headers in Cake Mono Light
uppercase, all numbers in JetBrains Mono (tabular, slashed zero), steel-blue accent on the single primary
action only, single `EASE_SMOOTH` curve, `prefers-reduced-motion` honored. Copy runs through
`ops-copywriter`.

Anatomy:

```
// TAKEOFF · <trade or "unclassified">
────────────────────────────────────────────────────────────────
// MEASUREMENTS
  deck length      20 ft     [READ]                ·  "20ft"
  deck width       14 ft     [READ]                ·  "14ft"
  stair count       — ea     [MISSING]   ask ▸     ← gap → drafts a question for you to send
// LINE ITEMS                                    qty    rate     total
  Pressure-treated decking (sqft)              280    $6.20   $1,736   ▸ math
  Railing section (lf)                          48   $32.00   $1,536   ▸ math
  Gate (each)                                    1  $240.00     $240
  Post set (each)                     [NEEDS PRICE]    6      —    —    ▸ map product
────────────────────────────────────────────────────────────────
  subtotal $3,512 · tax — · total $3,512
  [ REVIEW ESTIMATE ]   EDIT   ASK CUSTOMER   DISMISS
```

- **Source chips** — `READ` (a number read off the drawing) or `MISSING` (a gap). No confidence score is
  shown; there is nothing to "confirm before it's relied on," because the whole card is a draft you review
  (decision #8). A `MISSING` measurement exposes "ask", which drafts the missing-measurement reply for you to
  send (decision #10).
- **`▸ math`** discloses the auditable computation (`TakeoffItem.computation`) — the takeoff math is never
  hidden.
- **EDIT** lets the operator correct any measurement, quantity, or rate inline — each edit is a learning
  signal (§ Learning loop).
- **`[NEEDS PRICE]`** lines map to a product picker; the mapping is learned. The draft estimate is still
  created with the un-priced line present — only *sending* waits until it's priced (decision #11).
- **REVIEW ESTIMATE** (primary) materializes the draft estimate and opens it. **DISMISS** discards (negative
  priceability signal).
- The customer-facing draft **reply** (separate composer content) acknowledges the attachment and says a
  quote is being prepared — **it contains no price** (decision #7). The `estimateAckBlock` in `draft-context.ts`
  authors this wording, and a unit test asserts the reply omits figures (there is no runtime redaction layer —
  the prompt is the only control).

## Estimate materialization

On confirm, call the **existing** `EstimateService.createEstimate(data, lineItems[])`:

- **Header:** `company_id`, `opportunity_id` (from the thread's `email_threads.opportunity_id`), `client_id`
  **and** `client_ref` (set both — `client_id` has no FK; the enforced FK is on `client_ref`), `project_id`
  (text) **and** `project_ref` if a project exists, `status='draft'`, `issue_date=today`,
  `subtotal/tax_amount/total` via `calculateDocumentTotals`.
- **Line items:** one per confirmed `TakeoffItem` → `name`, `description`, `quantity`, `unit`, `unit_price`
  (resolved rate), `product_id` (mapped, nullable), `type` coerced to the CHECK vocabulary
  `{LABOR, MATERIAL, OTHER}`, `sort_order`. **Never** write `line_total` (generated).
- **Provenance (new, additive):** `estimates.source_takeoff_id → inbox_takeoffs.id` and
  `line_items.source_takeoff_item_id` (a stable id per `TakeoffItem`) so every estimate line traces back to
  the measurement + source it came from. Both nullable → iOS-safe.
- **Permissions:** creation requires `estimates.create`; a server/cron path must run under a company-scoped
  identity that satisfies RLS `company_isolation` + `role_scope_insert` (or `service_role` + explicit
  `company_id` + a re-checked permission). Never filter by role.
- **Notification:** fire `persistent: true` while extraction/pricing is in flight ("// ANALYZING DRAWING…"),
  then resolve it and fire a standard row: `type='vision_estimate_ready'`, body with concrete refs
  ("// DRAFT ESTIMATE READY · <PROJECT> · 6 LINE ITEMS · $3,512"), `action_label='REVIEW'`, a **new**
  `deep_link_type='visionEstimateReview'`. The new `type` + `deep_link_type` must be registered in
  `notification-meta.ts`, the web `NotificationType` union, and iOS routing (dead link otherwise). Recipients
  resolved via `users_with_permission(company_id, 'estimates.create', 'all')` — permission, never role.

**Re-estimation** honors the freeze contract: line items are frozen snapshots, so a re-run on new photos
creates a **new estimate version** (`parent_id` + `version` + set the prior to `superseded` — nothing writes
`superseded` today, so the estimator does it), never mutates a sent line.

## Model policy + cost + cache-busting

- **One upgraded vision call, not a second pass (my engineering call, 2026-07-01).** Rather than a separate
  `takeoffExtraction` model concern + second paid call per attachment (which would double per-attachment cost
  for no quality gain), the existing `attachmentVision` call is upgraded: an **additive `takeoff` prompt key**
  (the stable `summary`/`isSignedEstimate` keys are untouched), a **raised `max_completion_tokens` (~1500)**
  since a takeoff emits far more than a one-line summary, and a **`TAKEOFF_SCHEMA_VERSION` stamp**. Default
  model stays `gpt-5.4` (quality-first: start high, regress only if quality holds). Same `getSyncOpenAI()`
  client; PDFs sent natively (no OCR
  fallback — verify PDF+vision support before any model bump, exactly as `inbox-models.ts` already flags for
  `gpt-5.5`).
- **Cache-busting:** add `attachment_inspections.prompt_version text` (nullable). The cost-once planner skips
  an attachment only if it's cached **at the current `prompt_version`** — so evolving the extraction prompt
  re-inspects, while re-runs at the same version stay free. Without this, enriched prompts silently never run
  on already-seen attachments.
- **Cost (transparency rule).** At `gpt-5.4`, per-attachment vision is ~$0.01–0.02 today (sibling spec);
  takeoff extraction, with a larger structured output, is ~$0.02–0.05 per attachment. A multi-photo job
  multiplies per attachment (cap `MAX_INSPECTIONS_PER_RUN = 10` already applies). At current tenancy this is
  low-tens-of-dollars/month; **surface the projected per-estimate cost to Jackson before enabling** and
  before any model bump. No auto-send means no runaway send cost.

## Guardrails (non-negotiable — liability)

1. **Auto-send NOTHING (decision #9).** This feature never dispatches any email on its own — not the
   estimate, not the ask-for-measurement reply. If `inbox_takeoffs` exists for a thread (or a draft estimate
   is attached), the autonomy router forces `routing='draft'`/hold **regardless of autonomy level or
   `ai_auto_send`**. This closes the real auto-send path (`pending_auto_sends` → cron) that the "never
   auto-send" comments falsely imply is absent. Every outbound is a draft the operator sends.
2. **Always a DRAFT the operator reviews.** The estimate is `status='draft'`; the customer-facing reply
   carries no price.
3. **Always echo measurements + source.** The card shows every number and where it came from (READ off the
   drawing, or MISSING → asked). No confidence score gates anything — the operator reviews every drafted
   number, so there is no "auto-accepted" path to guard (decision #8).
4. **Show the takeoff math.** Every item's `computation` is disclosable and auditable.
5. **Never guess a missing measurement.** Unreadable → `value:null` + a `TakeoffGap` → ask the customer
   (a drafted question the operator sends).
6. **Auditable end-to-end.** `inbox_takeoffs` retains the original AI takeoff, the operator's edits, and the
   disposition (clone of `ai_draft_history`); provenance columns link every estimate line to its source.

## Schema additions (all additive, nullable, iOS-safe)

Per the standing iOS-sync constraint: additive + nullable only — no `NOT NULL`-without-safe-default, no
`CHECK` on existing columns, no enum tightening, no renames. iOS Codable ignores unknown columns; it opts in
on its next App Store release. Prefer a JSONB blob over scalar columns (LiDAR precedent).

- **New tables:** `inbox_takeoffs`, `company_item_product_map`, `company_pricing_profile`, `takeoff_rules`,
  `company_trade_estimating_state` (schemas in § Learned tables). RLS company-scoped via
  `private.get_user_company_id()`; `user_id`/actor columns typed `text` where Firebase-bridged, `uuid` where
  `auth.users` (deliberate per column).
- **`attachment_inspections`:** add `prompt_version text` (nullable) — cache-bust. `takeoff jsonb` optional
  (may reuse `facts`).
- **`estimates`:** add `source_takeoff_id uuid` (nullable) → `inbox_takeoffs.id`.
- **`line_items`:** add `source_takeoff_item_id uuid` (nullable) — traceability to the takeoff item.
- **`notifications`:** new `type='vision_estimate_ready'` + `deep_link_type='visionEstimateReview'` (text
  columns — no migration; register in both clients' routing).
- **No changes** to `products`, `catalog_*`, or the `line_total` generated column.

## File map

| File | Responsibility |
|---|---|
| `…/conversation-state/takeoff-types.ts` | `Takeoff` / `TakeoffMeasurement` / `TakeoffItem` / `TakeoffGap` contracts (new). |
| `…/conversation-state/attachment-inspector.ts` | Upgrade the existing vision call: additive `takeoff` prompt key, raised token budget, `TAKEOFF_SCHEMA_VERSION` stamp; keep `summary` populated. |
| `…/conversation-state/inbox-models.ts` | No new concern — `attachmentVision` stays the model source; only the call's token budget grows. |
| `…/conversation-state/attachment-ingest.ts` | Cost-once planner keyed on `(…, prompt_version)`; write `prompt_version`. |
| `…/services/takeoff-builder.ts` | Deterministic: merge per-attachment fragments → one `Takeoff`; unit coercion; apply `takeoff_rules` to compute item quantities; write `inbox_takeoffs`. (new) |
| `…/services/takeoff-pricing.ts` | Deterministic: item→product (learned map + fuzzy fallback), unit↔dimension match, rate resolution, `calculateDocumentTotals`. (new) |
| `…/services/takeoff-learning.ts` | Capture corrections → learned tables + embedded `agent_memories`; priceability autonomy transitions. Extends `phase-c-learning-service`. (new) |
| `…/conversation-state/draft-context.ts` | Add `estimateAckBlock` (acknowledge quote-in-progress, no price). |
| `…/conversation-state/router.ts` | Add estimate-bearing → force `draft`/hold; never `auto_send`. |
| `components/ops/inbox/takeoff-card/*` | The in-inbox Takeoff card (measurements, source chips, math disclosure, edit, ask, dismiss, review). (new) |
| `lib/api/services/estimate-service.ts` | Reused verbatim; add provenance columns to `mapEstimateToDb`/`mapLineItemToDb`. |
| `lib/notifications/notification-meta.ts` (+ iOS) | Register `vision_estimate_ready` / `visionEstimateReview`. |
| Migrations | New tables + additive columns above (all iOS-safe). |
| i18n | `useDictionary("takeoff")` en + es dictionaries. |

## Phases

### Phase 0 — Takeoff schema + extraction (no pricing, no UI) — **detailed plan: `docs/inbox/vision-estimating-phase0-plan.md`**
- `takeoff-types.ts` (contract + non-throwing validator); upgrade the existing `attachment-inspector` vision
  call (additive `takeoff` prompt key, raised token budget, `TAKEOFF_SCHEMA_VERSION`); `prompt_version`
  cache-bust column + planner change; deterministic merge in `takeoff-builder.ts`; `inbox_takeoffs` table
  (status `proposed`). Labeled dimensions only; gaps for unreadable. **No estimate, no card yet.**
- Acceptance: a labeled deck drawing yields a `Takeoff` with correct measurements (source `read_from_drawing`),
  quantified items with auditable `computation`, and gaps for anything unreadable; an unlabeled sketch yields
  all-gaps and no fabricated numbers.

### Phase 1 — In-inbox Takeoff card + confirmation
- Render the card on the thread; source chips (READ / MISSING); `▸ math` disclosure; inline EDIT; ASK-CUSTOMER
  drafts the missing-measurement reply (operator sends) and sets `awaiting_customer`; DISMISS. No confidence
  score shown, no per-number confirm gate — the whole card is operator-reviewed. Still **no estimate
  creation** — confirm/correct the takeoff only.
- Acceptance: operator can correct a measurement and see items recompute; an unlabeled drawing surfaces "ask
  the customer" and drafts a reply that requests the specific missing dimension; the card shows no confidence
  score and no number is auto-accepted.

### Phase 2 — Catalog mapping + pricing + draft estimate
- `takeoff-pricing.ts`: learned map + fuzzy fallback + unit match + rate; `calculateDocumentTotals`;
  materialize `status='draft'` estimate via `EstimateService.createEstimate`; provenance columns; un-priced
  lines when unmapped; persistent→resolved notification with `REVIEW` deep-link. Estimate-bearing threads
  hard-barred from `auto_send` (router change).
- Acceptance: confirming a fully-mapped takeoff creates a draft estimate whose line items match the confirmed
  quantities × the company's own product rates, with header totals matching `calculateDocumentTotals`; an
  unmapped item yields an un-priced line flagged "needs price"; no email is ever auto-sent; the customer draft
  reply contains no price.

### Phase 3 — Learning loop
- `takeoff-learning.ts`: capture measurement/quantity/rate/mapping corrections → `company_item_product_map`,
  `company_pricing_profile`, `takeoff_rules` (+ embedded `agent_memories` for rate corrections);
  accept/discard → `company_trade_estimating_state` priceability autonomy (Q3). Learned tables decay-exempt.
- Acceptance: correcting a rate makes the next estimate for that item use the corrected rate (and the price
  surfaces in draft-time memory retrieval); remapping an item persists for the next takeoff; a trade with a
  sustained low accept-rate transitions to `manual` (stops auto-attempting).

### Phase 4 — Degradation completeness + trade generalization
- Full decision tree wired; trade-vocabulary learning; per-trade priceability states; graceful "can't price
  this trade" path; war-game the forwarded-own-estimate false positive against accept-detection.
- Acceptance: a non-decking trade (e.g. fencing) with a labeled drawing produces a correct takeoff + estimate
  using only learned mappings, with zero decking-specific code paths exercised.

### Later (post-v1 — noted, not built)
- **Unlabeled / scaled-drawing inference** (measure from a scale bar or a known reference) — replaces the
  ask-the-customer path for scaled sketches.
- **Photo-based measurement** (dimension the work from photos, LiDAR-style) — the `project_photo_annotations.dimensions`
  jsonb + `photo_source` precedent is the storage target.
- **iOS on-site capture entry point** — field crews capture photos on iOS → sync to `project_photos` → a
  web/server route runs the same takeoff→estimate core (the bible's "Site Visit → Estimate continuity").
- **`product_pricing_modifiers` / option pricing** and **BOM explosion** (`product_materials` →
  `line_item_materials`).

## Bible updates required when this ships (mandatory, same session)

| File | Change |
|---|---|
| `10_JOB_LIFECYCLE_AND_DATA_RELATIONSHIPS.md` | New § "Photo/Vision → Estimate Adapter" sibling to "Drawing → Estimate Adapter (Phase 13)"; note the learned `company_item_product_map` vs the empty `company_default_products`. |
| `09_FINANCIAL_SYSTEM.md` | Document the vision estimate-creation entry point + the takeoff provenance columns on `estimates`/`line_items`. |
| `07_SPECIALIZED_FEATURES.md` | New § "AI Vision Estimating"; extend §14.3.1 notification table with `vision_estimate_ready` / `visionEstimateReview`. |
| `03_DATA_ARCHITECTURE.md` | New tables + additive columns (with the iOS-additive note); document the learned-tables grain. |
| `04_API_AND_INTEGRATION.md` | Extraction + pricing route/service docs (model, env, confidence/sources shape). |
| `00_EXECUTIVE_SUMMARY.md` | Add to roadmap / active development. |

## Decisions locked (Jackson, 2026-07-01)

**All decisions are locked — the spec is final and ready for implementation planning.**
1. **No confidence thresholds.** Removed entirely as a behavioral gate — everything is operator-reviewed, so
   a score branching the UX was complexity for nothing. The card gates only on binary source (READ vs
   MISSING); confidence survives as an internal learning signal only (decision #8).
2. **Priceability autonomy trip:** last-10-attempt window per `(company, trade)`, flip `attempt → manual`
   below 30% accept (decision #14).
3. **v1 dogfood trade:** decking/railing (decision #12).
4. **Un-priced lines never block the draft:** the estimate is created with the un-priced line marked "needs
   price"; only *sending* waits until the operator prices it (decision #11).
5. **Auto-send nothing:** the whole feature sends no email autonomously — estimate and any reply are drafts
   the operator sends (decision #9).
6. **Model:** `gpt-5.4` vision from the start, quality-first (decision #13).
7. **Ask-the-customer behavior:** when a needed measurement is missing, the system **drafts** the
   ask-for-the-dimension reply for the operator to review + send (option (a)) — never merely flags the gap,
   never auto-sends (decision #10).

## Safety notes

- **iOS-sync:** every migration additive + nullable; no `CHECK`/enum-tightening/renames. New `notifications`
  `type`/`deep_link_type` are text (no migration) but must be registered in both clients before the completion
  tap works.
- **Never auto-send:** the router hard-bar on estimate-bearing threads is the single most important guardrail —
  the `auto_send` path is real (`pending_auto_sends` + cron), the "never auto-send" comments notwithstanding.
- **Operator-exclusion preserved:** the vision step already excludes operator-sent attachments; a customer
  forwarding your own estimate back must not be read as a new takeoff (war-game in Phase 4).
- **Vercel auto-deploys `main` to prod** — keep this work on a feature branch until verified; nothing reaches
  customers from the branch.
- **Cost transparency:** surface projected per-estimate and monthly vision cost before enabling and before any
  model bump.
