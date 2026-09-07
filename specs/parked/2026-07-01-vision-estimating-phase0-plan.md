> **PARKED 2026-09-05 (Jackson: not ready for this yet).** Salvaged verbatim from ops-web branch `claude/hungry-khorana-d20ede` (`docs/inbox/vision-estimating-phase0-plan.md`, authored 2026-06-30 / 2026-07-01) before that branch is dropped. Not scheduled; the INBOX CLEAN STATE layer it builds on has shipped. Revisit when vision estimating is back on the roadmap.

# Vision Estimating — Phase 0 Implementation Plan (Takeoff schema + extraction)

> **For agentic workers:** REQUIRED SUB-SKILL: use `superpowers:subagent-driven-development` to implement this plan task-by-task. Steps use `- [ ]` checkboxes.
> **Execution artifact — proofs only, not for Jackson review.** Spec: `docs/inbox/vision-estimating-spec.md`.

**Goal:** Turn the inert `attachment_inspections.facts` bag into a structured, trade-agnostic **Takeoff** (measurements + quantified items, each tagged READ or MISSING), extracted by the existing vision call (upgraded), validated deterministically, and persisted to a new `inbox_takeoffs` row. **No pricing, no UI, no estimate creation in Phase 0** — this phase produces a testable Takeoff object and nothing customer-visible.

**Architecture:** ONE vision call per customer attachment (not two — cost). The existing `INSPECTOR_SYSTEM_PROMPT` is extended *additively* to also return a `takeoff` object; `max_completion_tokens` is raised; a `TAKEOFF_SCHEMA_VERSION` is stamped so the cost-once cache re-inspects when the contract evolves. Pure cores (`parseTakeoffResponse`, `buildThreadTakeoff`) hold all tested logic; thin wrappers do I/O. All schema additions are additive/nullable/iOS-safe.

**Tech Stack:** TypeScript, OpenAI (`getSyncOpenAI`, `gpt-5.4` vision via `inboxModel`), Supabase (Postgres + RLS), Vitest.

**Spec refinement made here (my call, sync into spec):** the spec's § Model policy proposed a *separate* `takeoffExtraction` model concern / second call. Phase 0 instead **upgrades the single existing inspection call** (additive prompt key + raised token budget + version stamp). Rationale: a second vision pass doubles per-attachment cost for no quality gain, and an additive prompt key keeps the stable `summary`/`isSignedEstimate` signed-estimate path untouched. The `attachmentVision` model concern stays; only its call's token budget and prompt grow.

**Build base:** `origin/main` (this worktree branch is 509 commits behind and lacks the clean-state layer). Task 0 establishes the correct worktree.

---

## File structure

| File | Responsibility | New/Modify |
|---|---|---|
| `src/lib/api/services/conversation-state/takeoff-types.ts` | The `Takeoff` / `TakeoffMeasurement` / `TakeoffItem` / `TakeoffGap` contracts + `TAKEOFF_SCHEMA_VERSION`. Pure types + one pure validator export surface. | **Create** |
| `src/lib/api/services/conversation-state/attachment-inspector.ts` | Extend `INSPECTOR_SYSTEM_PROMPT` (additive `takeoff` key); raise `max_completion_tokens`; add `parseTakeoffResponse` (pure) and thread `takeoff` through `parseInspectionResponse` → `AttachmentInspection`. | Modify |
| `src/lib/api/services/conversation-state/types.ts` | Add `takeoff?: Takeoff \| null` to `AttachmentInspection`. | Modify |
| `src/lib/api/services/conversation-state/attachment-ingest.ts` | Persist `takeoff` + `prompt_version` on the `attachment_inspections` upsert. | Modify |
| `src/lib/api/services/conversation-state/takeoff-builder.ts` | Pure `buildThreadTakeoff(inspections[])` → merged thread-level `Takeoff`; impure `persistThreadTakeoff()` → `inbox_takeoffs` upsert. | **Create** |
| `supabase/migrations/<ts>_vision_estimating_phase0.sql` | Additive: `attachment_inspections.prompt_version text`, `attachment_inspections.takeoff jsonb`; new `inbox_takeoffs` table + RLS. | **Create** |
| `tests/unit/inbox/conversation-state/takeoff-types.test.ts` | Validator unit tests. | **Create** |
| `tests/unit/inbox/conversation-state/attachment-inspector-takeoff.test.ts` | `parseTakeoffResponse` unit tests. | **Create** |
| `tests/unit/inbox/conversation-state/takeoff-builder.test.ts` | `buildThreadTakeoff` unit tests. | **Create** |

---

## Task 0: Establish the build worktree off origin/main

**Files:** none (git setup).

- [ ] **Step 1: Create a fresh worktree off origin/main**

```bash
cd /Users/jacksonsweet/Projects/OPS/ops-web
git fetch origin
git worktree add -b feat/vision-estimating .git/worktrees-ext/vision-estimating origin/main
cd .git/worktrees-ext/vision-estimating
```

Expected: a clean checkout at `origin/main` containing `src/lib/api/services/conversation-state/attachment-inspector.ts` (verify with `ls src/lib/api/services/conversation-state/`).

- [ ] **Step 2: Verify the base has the clean-state layer**

Run: `ls src/lib/api/services/conversation-state/attachment-ingest.ts && npx vitest run tests/unit/inbox/conversation-state/ 2>&1 | tail -5`
Expected: file exists; existing conversation-state unit tests PASS (green baseline before we change anything).

- [ ] **Step 3: Copy the spec + this plan into the new worktree** (they live on the stale branch)

```bash
git show <stale-branch>:docs/inbox/vision-estimating-spec.md > docs/inbox/vision-estimating-spec.md
git show <stale-branch>:docs/inbox/vision-estimating-phase0-plan.md > docs/inbox/vision-estimating-phase0-plan.md
git add docs/inbox/vision-estimating-spec.md docs/inbox/vision-estimating-phase0-plan.md
git commit -m "docs(inbox): vision-estimating spec + phase 0 plan"
```

---

## Task 1: The `Takeoff` contract + validator

**Files:**
- Create: `src/lib/api/services/conversation-state/takeoff-types.ts`
- Test: `tests/unit/inbox/conversation-state/takeoff-types.test.ts`

- [ ] **Step 1: Write the failing test**

```ts
// tests/unit/inbox/conversation-state/takeoff-types.test.ts
import { describe, it, expect } from "vitest";
import { validateTakeoff, TAKEOFF_SCHEMA_VERSION } from "@/lib/api/services/conversation-state/takeoff-types";

describe("validateTakeoff", () => {
  it("coerces a well-formed object and stamps the schema version", () => {
    const t = validateTakeoff({
      trade: "decking",
      drawingPresent: true,
      priceable: true,
      measurements: [
        { label: "deck length", value: 20, unit: "ft", dimension: "length", source: "read_from_drawing", rawText: "20ft", confidence: 0.9 },
      ],
      items: [
        { key: "deck_board", label: "PT decking", quantity: 280, unit: "sqft", dimension: "area", derivedFrom: ["deck length", "deck width"], computation: "20 × 14 = 280 sqft", source: "read_from_drawing", confidence: 0.8 },
      ],
      gaps: [],
      confidence: 0.85,
      notes: "",
    });
    expect(t.schemaVersion).toBe(TAKEOFF_SCHEMA_VERSION);
    expect(t.measurements[0].value).toBe(20);
    expect(t.items[0].quantity).toBe(280);
  });

  it("degrades garbage to an empty, non-throwing takeoff", () => {
    const t = validateTakeoff("not an object");
    expect(t.measurements).toEqual([]);
    expect(t.items).toEqual([]);
    expect(t.priceable).toBe(false);
  });

  it("never invents a value: a null measurement stays null and yields no crash", () => {
    const t = validateTakeoff({ measurements: [{ label: "width", value: null, unit: "ft", dimension: "length", source: "read_from_drawing", rawText: "", confidence: 0 }], items: [], gaps: [{ need: "deck width", reason: "unlabeled", blocksItems: ["deck_board"] }] });
    expect(t.measurements[0].value).toBeNull();
    expect(t.gaps[0].need).toBe("deck width");
  });

  it("drops non-finite / coerces string numbers rather than trusting model output", () => {
    const t = validateTakeoff({ measurements: [{ label: "len", value: "20", unit: "ft", dimension: "length", source: "read_from_drawing", rawText: "20ft", confidence: "0.9" }], items: [], gaps: [] });
    expect(t.measurements[0].value).toBe(20);
    expect(t.measurements[0].confidence).toBe(0.9);
  });
});
```

- [ ] **Step 2: Run it to verify it fails**

Run: `npx vitest run tests/unit/inbox/conversation-state/takeoff-types.test.ts`
Expected: FAIL — cannot import `validateTakeoff` (module missing).

- [ ] **Step 3: Implement `takeoff-types.ts`**

```ts
// src/lib/api/services/conversation-state/takeoff-types.ts
//
// Trade-agnostic Takeoff contract. Extraction target that replaces the inert
// free-form `facts` bag. NOTHING here is trade-specific: measurements + quantified
// items with LEARNED item keys. v1 uses source "read_from_drawing" | "asked" only;
// "inferred" is reserved for later scaled/photo phases (v1 never guesses).
//
// PURE MODULE — no I/O. `validateTakeoff` coerces untrusted model JSON into the
// typed shape and NEVER throws (garbage → an empty, non-priceable takeoff).

/** Bump when the extraction prompt/shape changes → busts the cost-once cache. */
export const TAKEOFF_SCHEMA_VERSION = "takeoff-v1" as const;

export type MeasurementSource = "read_from_drawing" | "asked" | "inferred";
export type PhysicalDimension =
  | "length" | "area" | "volume" | "count" | "mass" | "time" | "angle" | "unknown";

export interface TakeoffMeasurement {
  label: string;
  value: number | null;
  unit: string;
  dimension: PhysicalDimension;
  source: MeasurementSource;
  rawText: string;
  confidence: number; // internal learning signal only — never a UX gate
  evidence?: { attachmentId?: string; region?: string; page?: number };
}

export interface TakeoffItem {
  key: string;
  label: string;
  quantity: number | null;
  unit: string;
  dimension: PhysicalDimension;
  derivedFrom: string[];
  computation: string;
  source: MeasurementSource;
  confidence: number;
}

export interface TakeoffGap {
  need: string;
  reason: "unlabeled" | "illegible" | "ambiguous_unit" | "out_of_frame";
  blocksItems: string[];
}

export interface Takeoff {
  schemaVersion: string;
  trade: string | null;
  drawingPresent: boolean;
  priceable: boolean;
  measurements: TakeoffMeasurement[];
  items: TakeoffItem[];
  gaps: TakeoffGap[];
  confidence: number;
  notes: string;
}

const DIMENSIONS: ReadonlySet<string> = new Set([
  "length", "area", "volume", "count", "mass", "time", "angle", "unknown",
]);
const SOURCES: ReadonlySet<string> = new Set(["read_from_drawing", "asked", "inferred"]);
const GAP_REASONS: ReadonlySet<string> = new Set([
  "unlabeled", "illegible", "ambiguous_unit", "out_of_frame",
]);

function asRecord(v: unknown): Record<string, unknown> {
  return v && typeof v === "object" && !Array.isArray(v) ? (v as Record<string, unknown>) : {};
}
function asArray(v: unknown): unknown[] {
  return Array.isArray(v) ? v : [];
}
function str(v: unknown, fallback = ""): string {
  return typeof v === "string" ? v : fallback;
}
/** Coerce a model-supplied number: accept number or numeric string; else null. */
function numOrNull(v: unknown): number | null {
  if (typeof v === "number" && Number.isFinite(v)) return v;
  if (typeof v === "string" && v.trim() !== "") {
    const n = Number(v.replace(/[$,]/g, ""));
    if (Number.isFinite(n)) return n;
  }
  return null;
}
/** Confidence clamped to [0,1]; unparseable → 0. */
function conf(v: unknown): number {
  const n = numOrNull(v);
  if (n === null) return 0;
  return Math.min(1, Math.max(0, n));
}
function dimension(v: unknown): PhysicalDimension {
  const s = str(v);
  return (DIMENSIONS.has(s) ? s : "unknown") as PhysicalDimension;
}
function source(v: unknown): MeasurementSource {
  const s = str(v);
  return (SOURCES.has(s) ? s : "read_from_drawing") as MeasurementSource;
}

function measurement(raw: unknown): TakeoffMeasurement {
  const o = asRecord(raw);
  return {
    label: str(o.label),
    value: numOrNull(o.value),
    unit: str(o.unit),
    dimension: dimension(o.dimension),
    source: source(o.source),
    rawText: str(o.rawText),
    confidence: conf(o.confidence),
    evidence: undefined,
  };
}
function item(raw: unknown): TakeoffItem {
  const o = asRecord(raw);
  return {
    key: str(o.key),
    label: str(o.label),
    quantity: numOrNull(o.quantity),
    unit: str(o.unit),
    dimension: dimension(o.dimension),
    derivedFrom: asArray(o.derivedFrom).map((x) => str(x)).filter(Boolean),
    computation: str(o.computation),
    source: source(o.source),
    confidence: conf(o.confidence),
  };
}
function gap(raw: unknown): TakeoffGap {
  const o = asRecord(raw);
  const reason = str(o.reason);
  return {
    need: str(o.need),
    reason: (GAP_REASONS.has(reason) ? reason : "unlabeled") as TakeoffGap["reason"],
    blocksItems: asArray(o.blocksItems).map((x) => str(x)).filter(Boolean),
  };
}

/** Coerce untrusted JSON → Takeoff. NEVER throws; garbage → empty non-priceable. */
export function validateTakeoff(raw: unknown): Takeoff {
  const o = asRecord(raw);
  const measurements = asArray(o.measurements).map(measurement);
  const items = asArray(o.items).map(item);
  const gaps = asArray(o.gaps).map(gap);
  const trade = typeof o.trade === "string" && o.trade.trim() ? o.trade.trim() : null;
  return {
    schemaVersion: TAKEOFF_SCHEMA_VERSION,
    trade,
    drawingPresent: o.drawingPresent === true,
    priceable: o.priceable === true && items.length > 0,
    measurements,
    items,
    gaps,
    confidence: conf(o.confidence),
    notes: str(o.notes),
  };
}

/** True when the takeoff carries at least one quantified, priceable item. */
export function hasQuantifiedItems(t: Takeoff): boolean {
  return t.items.some((i) => i.quantity !== null && i.quantity > 0);
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `npx vitest run tests/unit/inbox/conversation-state/takeoff-types.test.ts`
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git add src/lib/api/services/conversation-state/takeoff-types.ts tests/unit/inbox/conversation-state/takeoff-types.test.ts
git commit -m "feat(inbox): trade-agnostic Takeoff contract + non-throwing validator"
```

---

## Task 2: Extract the Takeoff in the existing vision call

**Files:**
- Modify: `src/lib/api/services/conversation-state/types.ts` (add `takeoff` to `AttachmentInspection`)
- Modify: `src/lib/api/services/conversation-state/attachment-inspector.ts:129-135` (prompt), `:159-189` (parse), `:206-218` (`runVisionCall` token budget)
- Test: `tests/unit/inbox/conversation-state/attachment-inspector-takeoff.test.ts`

- [ ] **Step 1: Write the failing test**

```ts
// tests/unit/inbox/conversation-state/attachment-inspector-takeoff.test.ts
import { describe, it, expect } from "vitest";
import { parseInspectionResponse } from "@/lib/api/services/conversation-state/attachment-inspector";
import { TAKEOFF_SCHEMA_VERSION } from "@/lib/api/services/conversation-state/takeoff-types";

describe("parseInspectionResponse — takeoff", () => {
  it("parses an embedded takeoff object alongside summary/isSignedEstimate", () => {
    const raw = JSON.stringify({
      summary: "hand-drawn deck ~20x14",
      isSignedEstimate: false,
      facts: { area: "280 sqft" },
      takeoff: {
        trade: "decking", drawingPresent: true, priceable: true,
        measurements: [{ label: "length", value: 20, unit: "ft", dimension: "length", source: "read_from_drawing", rawText: "20ft", confidence: 0.9 }],
        items: [{ key: "deck_board", label: "decking", quantity: 280, unit: "sqft", dimension: "area", derivedFrom: ["length", "width"], computation: "20×14", source: "read_from_drawing", confidence: 0.8 }],
        gaps: [], confidence: 0.85, notes: "",
      },
    });
    const insp = parseInspectionResponse(raw, "gpt-5.4");
    expect(insp.summary).toContain("deck");
    expect(insp.takeoff).not.toBeNull();
    expect(insp.takeoff!.schemaVersion).toBe(TAKEOFF_SCHEMA_VERSION);
    expect(insp.takeoff!.items[0].quantity).toBe(280);
  });

  it("keeps the signed-estimate path intact when no takeoff key is present", () => {
    const raw = JSON.stringify({ summary: "signed estimate #1042 $8,400", isSignedEstimate: true, facts: {} });
    const insp = parseInspectionResponse(raw, "gpt-5.4");
    expect(insp.isSignedEstimate).toBe(true);
    expect(insp.takeoff).toBeNull();
  });

  it("a malformed takeoff degrades to null (never throws), summary still parses", () => {
    const raw = JSON.stringify({ summary: "photo", isSignedEstimate: false, facts: {}, takeoff: "garbage" });
    const insp = parseInspectionResponse(raw, "gpt-5.4");
    expect(insp.summary).toBe("photo");
    expect(insp.takeoff).toBeNull();
  });
});
```

- [ ] **Step 2: Run it to verify it fails**

Run: `npx vitest run tests/unit/inbox/conversation-state/attachment-inspector-takeoff.test.ts`
Expected: FAIL — `insp.takeoff` is undefined (property not yet on the type / not parsed).

- [ ] **Step 3a: Add `takeoff` to `AttachmentInspection`** (`types.ts`, the interface at ~:47-56)

```ts
// add the import at the top of types.ts:
import type { Takeoff } from "./takeoff-types";

// in AttachmentInspection, after `facts`:
  /** Structured trade-agnostic takeoff (Phase 0). null when none was extracted. */
  takeoff?: Takeoff | null;
```

- [ ] **Step 3b: Extend the vision prompt additively** (`attachment-inspector.ts`, `INSPECTOR_SYSTEM_PROMPT` at ~:129-135)

Append a fourth key to the existing prompt — DO NOT alter the existing three keys' wording (keeps the signed-estimate path stable):

```ts
export const INSPECTOR_SYSTEM_PROMPT = `You are inspecting an attachment a customer sent to a trades business.
Return ONLY a JSON object with exactly these keys:
- "summary": a one-line plain-text description for the business owner (e.g. "hand-drawn deck layout ~14ft x 20ft", "photo of storm-damaged fence", "signed estimate #1042, total $8,400").
- "isSignedEstimate": boolean — true ONLY if this is (or contains) an estimate/quote/contract that the CUSTOMER has signed or explicitly accepted in writing.
- "facts": an object of any structured details you can read (dimensions, totals, dates, estimate numbers, materials). Use {} if none.
- "takeoff": if (and only if) this is a DRAWING/PLAN/SKETCH of work to be done, a structured takeoff:
    { "trade": string|null, "drawingPresent": true, "priceable": boolean,
      "measurements": [ { "label": string, "value": number|null, "unit": string, "dimension": "length"|"area"|"volume"|"count"|"mass"|"time"|"angle"|"unknown", "source": "read_from_drawing", "rawText": string, "confidence": 0..1 } ],
      "items": [ { "key": string, "label": string, "quantity": number|null, "unit": string, "dimension": string, "derivedFrom": string[], "computation": string, "source": "read_from_drawing", "confidence": 0..1 } ],
      "gaps": [ { "need": string, "reason": "unlabeled"|"illegible"|"ambiguous_unit"|"out_of_frame", "blocksItems": string[] } ],
      "confidence": 0..1, "notes": string }
    RULES for "takeoff": ONLY read dimensions that are WRITTEN on the drawing. NEVER guess or estimate a missing measurement — if a needed dimension is not labeled, set its value to null and add a "gaps" entry. Omit "takeoff" entirely (or null) if the attachment is not a drawing of work.
Do not include any text outside the JSON object.`;
```

- [ ] **Step 3c: Add the pure takeoff parse + thread it into `parseInspectionResponse`** (`attachment-inspector.ts` ~:159-189)

At the top of the file add: `import { validateTakeoff, type Takeoff } from "./takeoff-types";`

In `emptyInspection`, add `takeoff: null`:

```ts
function emptyInspection(model: string): AttachmentInspection {
  return { summary: "", isSignedEstimate: false, facts: {}, takeoff: null, model };
}
```

Add the pure helper:

```ts
/** Pull a structured Takeoff out of a parsed inspection object; null if absent/garbage. */
export function parseTakeoffResponse(obj: Record<string, unknown>): Takeoff | null {
  const t = obj.takeoff;
  if (!t || typeof t !== "object" || Array.isArray(t)) return null;
  const takeoff = validateTakeoff(t);
  // A takeoff with no measurements AND no items AND no gaps is noise → null.
  if (takeoff.measurements.length === 0 && takeoff.items.length === 0 && takeoff.gaps.length === 0) {
    return null;
  }
  return takeoff;
}
```

In `parseInspectionResponse`, after `facts` is resolved and before the `return`, add `const takeoff = parseTakeoffResponse(obj);` and include it:

```ts
  const takeoff = parseTakeoffResponse(obj);
  return { summary, isSignedEstimate, facts, takeoff, model };
```

- [ ] **Step 3d: Raise the token budget on the vision call** (`attachment-inspector.ts` `runVisionCall` ~:217)

```ts
    response_format: { type: "json_object" },
    max_completion_tokens: 1500, // was 500 — a structured takeoff emits far more than a one-line summary
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `npx vitest run tests/unit/inbox/conversation-state/attachment-inspector-takeoff.test.ts tests/unit/inbox/conversation-state/attachment-inspector.test.ts`
Expected: PASS — new takeoff tests green AND the pre-existing `attachment-inspector.test.ts` still green (no regression to summary/isSignedEstimate).

- [ ] **Step 5: Commit**

```bash
git add src/lib/api/services/conversation-state/types.ts src/lib/api/services/conversation-state/attachment-inspector.ts tests/unit/inbox/conversation-state/attachment-inspector-takeoff.test.ts
git commit -m "feat(inbox): extract structured takeoff in the vision call (additive prompt key + parse)"
```

---

## Task 3: Additive migration — `prompt_version`, `takeoff`, and `inbox_takeoffs`

**Files:**
- Create: `supabase/migrations/<timestamp>_vision_estimating_phase0.sql`

> **iOS-safety:** every statement below is additive + nullable, no CHECK on existing columns, no enum tightening, no rename. Safe to apply to prod without an iOS release. **Do NOT apply to prod yet** — apply after the code lands + is verified (flag the apply to Jackson: it's a live multi-tenant DB write). Column defaults keep old rows valid.

- [ ] **Step 1: Write the migration**

```sql
-- supabase/migrations/<timestamp>_vision_estimating_phase0.sql
-- Vision Estimating Phase 0 — structured takeoff extraction storage.
-- Additive + nullable only (iOS-safe): no CHECK/enum/rename on existing columns.

-- 1) Cache-bust + structured takeoff on the per-attachment inspection cache.
alter table public.attachment_inspections
  add column if not exists prompt_version text,
  add column if not exists takeoff jsonb;

-- 2) Thread-level takeoff artifact (auditable; clones the ai_draft_history pattern).
create table if not exists public.inbox_takeoffs (
  id                  uuid primary key default gen_random_uuid(),
  company_id          uuid not null,
  provider_thread_id  text not null,
  opportunity_id      uuid,
  trade               text,
  status              text not null default 'proposed',
  takeoff             jsonb not null default '{}'::jsonb,
  confidence          numeric,
  model               text,
  schema_version      text,
  source_message_ids  text[] not null default '{}',
  estimate_id         uuid,
  disposition         text,
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now(),
  confirmed_at        timestamptz,
  confirmed_by        uuid
);

create unique index if not exists inbox_takeoffs_company_thread_uidx
  on public.inbox_takeoffs (company_id, provider_thread_id);
create index if not exists inbox_takeoffs_company_status_idx
  on public.inbox_takeoffs (company_id, status);

alter table public.inbox_takeoffs enable row level security;

-- Company-scoped RLS, mirroring attachment_inspections (service-role sync bypasses RLS).
drop policy if exists inbox_takeoffs_company_isolation on public.inbox_takeoffs;
create policy inbox_takeoffs_company_isolation on public.inbox_takeoffs
  for all
  using (company_id = (auth.jwt() ->> 'company_id')::uuid)
  with check (company_id = (auth.jwt() ->> 'company_id')::uuid);

grant select, insert, update, delete on public.inbox_takeoffs to anon, authenticated, service_role;
```

- [ ] **Step 2: Verify it parses / lints locally** (do NOT push to prod)

Run: `npx supabase db lint --file supabase/migrations/<timestamp>_vision_estimating_phase0.sql 2>/dev/null || echo "lint tool unavailable — visually verify additive-only"`
Expected: no errors, or a manual confirmation the file is additive-only.

- [ ] **Step 3: Commit**

```bash
git add supabase/migrations/<timestamp>_vision_estimating_phase0.sql
git commit -m "feat(inbox): additive migration — attachment_inspections.takeoff/prompt_version + inbox_takeoffs"
```

---

## Task 4: Persist the takeoff + prompt_version at ingest

**Files:**
- Modify: `src/lib/api/services/conversation-state/attachment-ingest.ts:145-157` (the upsert)

- [ ] **Step 1: Extend the upsert** (add `takeoff` + `prompt_version` to the row written for each inspected attachment)

At the top of `attachment-ingest.ts` add: `import { TAKEOFF_SCHEMA_VERSION } from "./takeoff-types";`

In the `attachment_inspections` upsert object (after `facts: inspection.facts,`):

```ts
            facts: inspection.facts,
            takeoff: inspection.takeoff ?? null,
            prompt_version: TAKEOFF_SCHEMA_VERSION,
            model: inspection.model,
```

- [ ] **Step 2: Cache-bust — re-inspect rows cached at an older prompt_version**

In `attachment-ingest.ts`, the cached-keys load (~step 3, before `planAttachmentInspections`) currently keys purely on `(message_id, attachment_id)`. Change it to treat a row cached at a *different* `prompt_version` as NOT cached, so the enriched prompt re-runs once:

```ts
// load only rows already inspected AT THE CURRENT prompt_version as "cached"
const { data: cachedRows } = await supabase
  .from("attachment_inspections")
  .select("message_id, attachment_id, prompt_version")
  .eq("company_id", companyId)
  .eq("provider_thread_id", providerThreadId);
const cachedKeys = new Set(
  (cachedRows ?? [])
    .filter((r) => r.prompt_version === TAKEOFF_SCHEMA_VERSION)
    .map((r) => attachmentInspectionKey(r.message_id, r.attachment_id))
);
```

> Note the upsert `onConflict` stays `company_id,message_id,attachment_id` but must flip `ignoreDuplicates` handling so a re-inspect at a new version OVERWRITES the stale row. Change the upsert to `ignoreDuplicates: false` and rely on the unique key to update-in-place; a concurrent same-version writer is idempotent (same content).

- [ ] **Step 3: Build (typecheck) to verify no type errors**

Run: `npx tsc --noEmit 2>&1 | grep -i "attachment-ingest\|takeoff" || echo "no takeoff/ingest type errors"`
Expected: no errors.

- [ ] **Step 4: Commit**

```bash
git add src/lib/api/services/conversation-state/attachment-ingest.ts
git commit -m "feat(inbox): persist takeoff + prompt_version; re-inspect on schema-version bump"
```

---

## Task 5: Assemble + persist the thread-level Takeoff

**Files:**
- Create: `src/lib/api/services/conversation-state/takeoff-builder.ts`
- Test: `tests/unit/inbox/conversation-state/takeoff-builder.test.ts`

- [ ] **Step 1: Write the failing test**

```ts
// tests/unit/inbox/conversation-state/takeoff-builder.test.ts
import { describe, it, expect } from "vitest";
import { buildThreadTakeoff } from "@/lib/api/services/conversation-state/takeoff-builder";
import { validateTakeoff } from "@/lib/api/services/conversation-state/takeoff-types";

const mk = (over: object) => validateTakeoff({ drawingPresent: true, priceable: true, measurements: [], items: [], gaps: [], confidence: 0.8, ...over });

describe("buildThreadTakeoff", () => {
  it("returns null when no attachment carried a takeoff", () => {
    expect(buildThreadTakeoff([{ takeoff: null }, { takeoff: null }])).toBeNull();
  });

  it("merges measurements + items across attachments and unions gaps", () => {
    const a = mk({ measurements: [{ label: "length", value: 20, unit: "ft", dimension: "length", source: "read_from_drawing", rawText: "20ft", confidence: 0.9 }], items: [{ key: "deck_board", label: "decking", quantity: 280, unit: "sqft", dimension: "area", derivedFrom: [], computation: "", source: "read_from_drawing", confidence: 0.8 }] });
    const b = mk({ gaps: [{ need: "stair count", reason: "unlabeled", blocksItems: ["stair_set"] }], items: [] });
    const merged = buildThreadTakeoff([{ takeoff: a }, { takeoff: b }])!;
    expect(merged.items).toHaveLength(1);
    expect(merged.measurements).toHaveLength(1);
    expect(merged.gaps).toHaveLength(1);
  });

  it("infers the thread trade from the first attachment that names one", () => {
    const a = mk({ trade: null });
    const b = mk({ trade: "fencing" });
    expect(buildThreadTakeoff([{ takeoff: a }, { takeoff: b }])!.trade).toBe("fencing");
  });
});
```

- [ ] **Step 2: Run it to verify it fails**

Run: `npx vitest run tests/unit/inbox/conversation-state/takeoff-builder.test.ts`
Expected: FAIL — module missing.

- [ ] **Step 3: Implement `takeoff-builder.ts`**

```ts
// src/lib/api/services/conversation-state/takeoff-builder.ts
//
// PURE core: merge per-attachment Takeoffs into one thread-level Takeoff.
// IMPURE tail: persist it to inbox_takeoffs (status='proposed'). No pricing here.

import type { SupabaseClient } from "@supabase/supabase-js";
import {
  type Takeoff,
  TAKEOFF_SCHEMA_VERSION,
  hasQuantifiedItems,
} from "./takeoff-types";

interface InspectionCarrier {
  takeoff?: Takeoff | null;
}

/** Merge the takeoffs from every inspected attachment on a thread. null if none. */
export function buildThreadTakeoff(inspections: InspectionCarrier[]): Takeoff | null {
  const takeoffs = inspections.map((i) => i.takeoff).filter((t): t is Takeoff => !!t);
  if (takeoffs.length === 0) return null;

  const measurements = takeoffs.flatMap((t) => t.measurements);
  const items = takeoffs.flatMap((t) => t.items);
  const gaps = takeoffs.flatMap((t) => t.gaps);
  const trade = takeoffs.map((t) => t.trade).find((x): x is string => !!x) ?? null;
  const confidence =
    takeoffs.reduce((s, t) => s + (Number.isFinite(t.confidence) ? t.confidence : 0), 0) /
    takeoffs.length;

  return {
    schemaVersion: TAKEOFF_SCHEMA_VERSION,
    trade,
    drawingPresent: takeoffs.some((t) => t.drawingPresent),
    priceable: items.length > 0 && takeoffs.some((t) => t.priceable),
    measurements,
    items,
    gaps,
    confidence,
    notes: takeoffs.map((t) => t.notes).filter(Boolean).join(" "),
  };
}

/** Status the takeoff should land in given what was (not) read. */
export function takeoffStatus(t: Takeoff): "proposed" | "awaiting_customer" {
  // Gaps present and nothing priceable yet → we must ask before we can price.
  if (t.gaps.length > 0 && !hasQuantifiedItems(t)) return "awaiting_customer";
  return "proposed";
}

/** Persist the merged takeoff to inbox_takeoffs (idempotent per company+thread). */
export async function persistThreadTakeoff(
  supabase: SupabaseClient,
  args: {
    companyId: string;
    providerThreadId: string;
    opportunityId?: string | null;
    model: string;
    sourceMessageIds: string[];
    takeoff: Takeoff;
  }
): Promise<void> {
  const { companyId, providerThreadId, opportunityId, model, sourceMessageIds, takeoff } = args;
  const { error } = await supabase.from("inbox_takeoffs").upsert(
    {
      company_id: companyId,
      provider_thread_id: providerThreadId,
      opportunity_id: opportunityId ?? null,
      trade: takeoff.trade,
      status: takeoffStatus(takeoff),
      takeoff,
      confidence: takeoff.confidence,
      model,
      schema_version: takeoff.schemaVersion,
      source_message_ids: sourceMessageIds,
      updated_at: new Date().toISOString(),
    },
    { onConflict: "company_id,provider_thread_id" }
  );
  if (error) {
    console.error("[takeoff-builder] persist failed (non-fatal):", error.message);
  }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `npx vitest run tests/unit/inbox/conversation-state/takeoff-builder.test.ts`
Expected: PASS (3 tests).

- [ ] **Step 5: Wire assembly into the ingest tail** (`attachment-ingest.ts`, after the per-attachment loop finishes)

After the inspection loop, load the thread's inspections (now including `takeoff`) and persist the merged thread takeoff:

```ts
import { buildThreadTakeoff, persistThreadTakeoff } from "./takeoff-builder";
import { validateTakeoff } from "./takeoff-types";
// ...after the for-loop over `plan`:
const { data: allInsp } = await supabase
  .from("attachment_inspections")
  .select("takeoff, message_id")
  .eq("company_id", companyId)
  .eq("provider_thread_id", providerThreadId);
const merged = buildThreadTakeoff(
  (allInsp ?? []).map((r) => ({ takeoff: r.takeoff ? validateTakeoff(r.takeoff) : null }))
);
if (merged) {
  await persistThreadTakeoff(supabase, {
    companyId,
    providerThreadId,
    model: /* the vision model used */ "gpt-5.4",
    sourceMessageIds: (allInsp ?? []).map((r) => r.message_id),
    takeoff: merged,
  });
}
```

- [ ] **Step 6: Typecheck + full conversation-state suite**

Run: `npx tsc --noEmit 2>&1 | grep -i "takeoff\|ingest" || echo ok; npx vitest run tests/unit/inbox/conversation-state/`
Expected: no type errors; all conversation-state unit tests PASS.

- [ ] **Step 7: Commit**

```bash
git add src/lib/api/services/conversation-state/takeoff-builder.ts tests/unit/inbox/conversation-state/takeoff-builder.test.ts src/lib/api/services/conversation-state/attachment-ingest.ts
git commit -m "feat(inbox): assemble + persist thread-level takeoff to inbox_takeoffs"
```

---

## Phase 0 done-definition

- A labeled customer drawing produces an `inbox_takeoffs` row (`status='proposed'`) whose `takeoff` jsonb has the read measurements + quantified items + auditable `computation`, and gaps for anything unlabeled.
- The signed-estimate/summary path is unchanged (regression suite green).
- Nothing is customer-visible; no pricing, no estimate, no email.
- Prod migration written + committed but **not applied** (apply is a flagged, separate step).

## Phases 1–4 (own plans when reached — see spec § Phases)

- **Phase 1** — in-inbox Takeoff card (READ/MISSING chips, `▸ math`, EDIT, ASK-CUSTOMER drafts the reply, DISMISS); no estimate yet.
- **Phase 2** — `takeoff-pricing.ts`: learned map + fuzzy fallback + unit↔dimension + rate; materialize `status='draft'` estimate via `EstimateService.createEstimate`; provenance columns; router hard-bar on auto-send; notification.
- **Phase 3** — `takeoff-learning.ts`: corrections → `company_item_product_map` / `company_pricing_profile` / `takeoff_rules` (+ embedded `agent_memories`); accept/discard → `company_trade_estimating_state`.
- **Phase 4** — full degradation tree; trade generalization; forwarded-own-estimate war-game.

---

## Self-review

- **Spec coverage (Phase 0 scope):** Takeoff contract ✓ (Task 1); structured extraction extending the vision step ✓ (Task 2); additive/iOS-safe schema ✓ (Task 3); cost-once cache-bust via `prompt_version` ✓ (Task 4); thread-level auditable takeoff artifact ✓ (Task 5). Pricing/UI/learning are explicitly deferred to Phases 1–4.
- **Type consistency:** `Takeoff`/`TakeoffMeasurement`/`TakeoffItem`/`TakeoffGap` defined in Task 1 are the exact shapes parsed in Task 2 (`parseTakeoffResponse`), persisted in Task 4, and merged in Task 5 (`buildThreadTakeoff`). `TAKEOFF_SCHEMA_VERSION` is the single source used by the validator, the ingest cache-bust, and the persisted `schema_version`.
- **No placeholders:** every code step carries complete code; the only intentional fill-in is the migration `<timestamp>` (generated at creation) and the vision-model string threaded into `persistThreadTakeoff` (read from the inspection's `model` at wiring time).
- **Guardrails honored:** extraction never guesses (null value + gap); Phase 0 produces nothing customer-visible; migration is additive-only and not auto-applied.
