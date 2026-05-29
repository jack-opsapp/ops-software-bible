# 10_JOB_LIFECYCLE_AND_DATA_RELATIONSHIPS.md

**OPS Software Bible — Complete Job Lifecycle: Inquiry → Close**

**Purpose**: Defines the complete data flow for a trade job from first contact through to a paid invoice. Documents all entity relationships, automation triggers, new entities, and required changes to existing entities. This is the master reference for how leads, pipeline, clients, estimates, projects, tasks, and invoices inter-operate.

**Last Updated**: March 19, 2026
**Designed With**: ops-web codebase + ops-software-bible review session

---

## Table of Contents

1. [Design Philosophy](#design-philosophy)
2. [Complete Flow Overview](#complete-flow-overview)
3. [Pipeline: The Job Spine](#pipeline-the-job-spine)
4. [Data Model Changes (Modified Entities)](#data-model-changes-modified-entities)
5. [New Entities](#new-entities)
6. [Automation Rules & Triggers](#automation-rules--triggers)
7. [Communication Logging](#communication-logging)
8. [Site Visits](#site-visits)
9. [Project Photos](#project-photos)
10. [Email Pipeline Integration](#email-pipeline-integration)
11. [Entity Relationship Map](#entity-relationship-map)
12. [Status & Stage Reference](#status--stage-reference)
13. [Implementation Notes](#implementation-notes)

---

## Design Philosophy

### Project = Folder

A **Project** is a folder that organizes all work for a client job. It can contain:
- Multiple estimates (original scope, phases, revisions)
- Tasks generated from approved estimates
- Photos (site visit, in-progress, completion)
- Invoices tied to approved estimates

**Project total value** = sum of all approved estimates within the project.

### Estimate = The Contract

An estimate is the primary financial document. It drives everything downstream:
- Sending an estimate triggers client + project creation
- Approving an estimate triggers task generation
- An approved estimate converts to an invoice

### Pipeline = The Command Center

The pipeline Kanban board is not just a CRM view — it is the active workflow driver for the entire pre-win lifecycle. Stage transitions are triggered by real actions (sending an estimate, getting a reply), not just manual drags.

### Zero Duplicate Entry

A user should never have to enter the same information twice:
- Estimate line items → tasks (auto-generated, no re-entry)
- Opportunity contact → client (auto-created on first estimate send)
- Opportunity + estimate → project (auto-created on first estimate send)
- Approved estimate → invoice (direct conversion, no re-entry)
- Site visit photos → project photos (auto-attached on job win)

---

## Complete Flow Overview

```
LEAD ENTERS PIPELINE
  Sources: web form, manual entry, email log, Gmail auto-detection
       │
       ▼
Opportunity (new_lead)
  contactName, contactEmail, contactPhone
  source, estimatedValue (rough), notes
  NO clientId yet — client may not exist
       │
       │  first activity logged [AUTO-ADVANCE]
       ▼
Opportunity (qualifying)
  Site visit may be booked here
  Follow-up reminders created
       │
       │  user creates estimate [AUTO-ADVANCE]
       ▼
Opportunity (quoting)
  Estimate(draft) linked to opportunityId
  Line items built:
    [LABOR]    Deck Renovation $12,000  → taskTypeId: "Deck Work"
    [LABOR]    Picket Railing $5,000    → taskTypeId: "Railing"
    [MATERIAL] Lumber $3,500            → no task
    [OTHER]    Permit Fee $150          → no task
       │
       │  user clicks "Send Estimate"
       │
       ▼  ══════════════════════════════
          SEND FLOW — two inline prompts

          STEP 1 — Client
          "Who is this estimate for?"
          → user types name
          → auto-suggests existing clients from DB
          → select existing OR confirm "New Client: [name]"
          → Client auto-created from opportunity contact info
          → estimate.clientId = client.id
          → opportunity.clientId = client.id

          STEP 2 — Project
          "File into a project?"
          → search existing projects OR create new
          → if new: Project auto-created
              (title, clientId, status=RFQ, opportunityId)
          → estimate.projectId = project.id
          → opportunity.projectId = project.id
          ══════════════════════════════
       │
       │  estimate sent [AUTO-ADVANCE]
       ▼
Opportunity (quoted)
Project (Estimated)
  Pipeline card now shows PROJECT data:
    - Project name + client
    - Pending estimate value
    - Estimates: 1 total, 0 approved
       │
       │  X days pass, no client response [AUTO-ADVANCE]
       │  FollowUp reminder auto-created
       ▼
Opportunity (follow_up)
       │
       │  client replies (inbound activity logged) [AUTO-ADVANCE]
       ▼
Opportunity (negotiation)
  Client has questions or wants changes
  Staff may create a new estimate for same project (v2 scenario)
  New estimate sent → loops back to (quoted)
       │
       │  estimate approved [AUTO-ADVANCE]
       ▼
Opportunity (won)
Project (Accepted)
       │
       ▼  ══════════════════════════════
          TASK GENERATION MODAL
          (skippable if company toggle: "Auto-generate tasks")

          "Review Tasks for: Deck Renovation"

          Deck Renovation — $12,000
            [x] Footings           crew: John, Mike  [edit]
            [x] Framing            crew: John, Mike  [edit]
            [x] Vinyl Membrane     crew: John        [edit]
            [+ Add task to this item]

          Picket Railing — $5,000
            [x] Picket Railing Install  crew: Sarah  [edit]
            [+ Add task to this item]

          [Confirm & Create Tasks]
          ══════════════════════════════
       │
       ▼
ProjectTasks created (status: Booked)
  Each task stores: sourceLineItemId, sourceEstimateId
       │
       │  tasks scheduled (dates stored on ProjectTask)
       ▼
Task startDate/endDate set
       │  first task starts
       ▼
Project (InProgress)
       │  all tasks complete
       ▼
Project (Completed)
       │
       ▼  ══════════════════════════════
          INVOICE CREATION
          Convert Estimate → Invoice (1:1)
          invoice.projectId = project.id
          invoice.estimateId = estimate.id
          Partial payments supported on single invoice:
            Payment 1: Deposit   (e.g. 40%)
            Payment 2: Progress  (e.g. 30%)
            Payment 3: Final     (e.g. 30%)
          ══════════════════════════════
       │
       │  invoice fully paid
       ▼
Project (Closed)
```

---

## Pipeline: The Job Spine

### Stage-by-Stage Reference

#### `new_lead`
**How leads enter:**
- Manual entry by office staff
- Web inquiry form submission (auto-creates Opportunity)
- Staff logs a call/email (creates Opportunity from that log)
- Gmail integration — unrecognized inquiry email surfaced for staff review → "Create Lead"

**Card shows:** Contact name, source badge, rough estimated value, age in stage

**Auto-advance trigger:** First Activity logged → `qualifying`

---

#### `qualifying`
Staff is assessing scope. Site visit may be booked.

**Actions available from card:**
- Log activity (call, meeting, site visit)
- Book site visit (creates SiteVisit — scheduling dates stored on the visit/task directly; CalendarEvent model has been removed)
- Create follow-up reminder
- Update estimated value as scope clarifies

**Card shows:** Last activity, next follow-up date, days in stage

**Auto-advance trigger:** User creates an Estimate from this opportunity → `quoting`

---

#### `quoting`
An estimate draft is actively being built.

**Card shows:** Estimate draft value, last edited, line item count

**Auto-advance trigger:** Estimate is sent → triggers Send Flow → `quoted`

---

#### `quoted`
Estimate sent. Client + Project now exist.

**Card shows (PROJECT DATA):**
```
┌──────────────────────────────┐
│ Smith Deck Job               │
│ John Smith                   │
│ ──────────────────────────── │
│ $17,650  ← pending           │
│ 1 estimate / 0 approved      │
│ Sent: 2 days ago             │
└──────────────────────────────┘
```

**Auto-advance trigger:** X days pass with no client response → `follow_up`
- X is configurable: `CompanySettings.followUpReminderDays` (default: 3)
- FollowUp record auto-created: *"Follow up on Estimate #EST-0042 — sent 3 days ago"*
- type: `quote_follow_up`, isAutoGenerated: true

---

#### `follow_up`
Waiting on client. System has nudged staff.

**Card shows:** Days since estimate sent, follow-up due date

**Auto-advance trigger:** Inbound Activity logged (client reply via email, call, text) → `negotiation`

**Manual override:** Staff can drag back to `quoted` or forward to `negotiation`

---

#### `negotiation`
Client has replied but not approved. Price or scope discussion in progress.

**Actions available:**
- Create a new estimate on the same project (revision scenario)
- Log activities (call notes, meeting notes)
- Update expected close date

**Card shows:** Number of estimate versions, latest estimate value

**Auto-advance trigger:** Revised estimate sent → `quoted` (loops back)

**Manual advance:** Drag to `won` for verbal approval before formal estimate sign-off

---

#### `won`
Estimate approved. Project goes live.

**What happens automatically:**
1. `opportunity.stage = won`
2. `opportunity.actualCloseDate = now`
3. `project.status = Accepted`
4. Site visit photos → auto-attached to project as ProjectPhotos (source: `site_visit`)
5. Task Generation modal opens (or silent auto-generate if toggle enabled)

**Card shows (PROJECT DATA):**
```
┌──────────────────────────────┐
│ Smith Deck Job          ✓ WON│
│ John Smith                   │
│ ──────────────────────────── │
│ $15,500  approved            │
│ 2 estimates / 1 approved     │
│ Tasks: 5 / 0 complete        │
│ → View Project               │
└──────────────────────────────┘
```

**Won column behavior:** Shows jobs won within last 30/60/90 days (configurable). Acts as a handoff confirmation before the project fully graduates to the Projects section.

---

#### `lost`
Estimate declined or opportunity abandoned.

**What happens:**
- Prompt for lost reason (uses existing `LOSS_REASONS` list)
- `opportunity.actualCloseDate = now`
- Opportunity soft-deleted (preserved for reporting)
- All activities, estimates, and stage transitions remain in history

---

### Pipeline Card Data by Stage

| Stage | Key Data Shown |
|---|---|
| `new_lead` | Contact name, source, estimated value, age |
| `qualifying` | Last activity, next follow-up |
| `quoting` | Draft estimate value, last edited |
| `quoted` | Project name, pending estimate value, sent date |
| `follow_up` | Days since sent, follow-up due |
| `negotiation` | # estimate versions, latest value |
| `won` | Project name, approved value, task progress |
| `lost` | Contact name, lost reason, estimated value lost |

### Stage Auto-Advance Summary

| Trigger | From | To |
|---|---|---|
| First Activity logged | `new_lead` | `qualifying` |
| Estimate created (draft) | `new_lead` or `qualifying` | `quoting` |
| Estimate sent | `quoting` | `quoted` |
| X days no response (configurable) | `quoted` | `follow_up` |
| Inbound Activity logged | `quoted` or `follow_up` | `negotiation` |
| Revised estimate sent | `negotiation` | `quoted` |
| Estimate approved | any active stage | `won` |
| Estimate declined | any active stage | `lost` (with prompt) |

All auto-advances record a `StageTransition` row. Users can manually drag to any stage at any time (existing Kanban behavior preserved).

---

## Data Model Changes (Modified Entities)

### `LineItem` (Supabase) — MODIFIED

Adds `type`, `taskTypeId`, `estimatedHours`, and the Phase 13 configuration-snapshot fields:

```typescript
type LineItemType = 'LABOR' | 'MATERIAL' | 'OTHER'

interface LineItem {
  // --- existing fields ---
  id: string;
  estimateId: string | null;
  invoiceId: string | null;
  description: string;
  quantity: number;
  unit: string | null;
  unitPrice: number;
  discount: number;          // percentage
  taxable: boolean;
  productId: string | null;  // optional link to product catalog
  displayOrder: number;

  // --- task-generation fields ---
  type: LineItemType;                  // LABOR | MATERIAL | OTHER
  taskTypeId: string | null;           // Bubble TaskType ID — LABOR items only
  estimatedHours: number | null;       // optional, for labor costing

  // --- Phase 13 configuration snapshot ---
  configuredOptions: jsonb | null;       // {option_id: option_value_id_or_int_or_bool}
  resolvedUnitPrice: number | null;      // base + applicable modifiers, frozen at line creation
  resolvedOptionsLabel: string | null;   // "TM · Black · Concrete · 4 corners"
}
```

**Rules:**
- `type` defaults to `LABOR` when linked from a Product with `type = 'LABOR'`
- Only `LABOR` line items participate in task generation
- `MATERIAL` and `OTHER` items are billing-only — no tasks created
- `taskTypeId` is nullable: a LABOR item without a taskTypeId generates one generic task

**Phase 13 snapshot semantics (line items as signed contracts):**

When a line item is created — manually from the line-item editor or programmatically by the drawing→estimate adapter — `ProductConfigurationResolver` runs:

1. Reads the chosen `Product`'s `ProductOption` rows + the user's choices.
2. Walks `ProductPricingModifier` rows whose triggers match. Modifier kinds:
   - `add_per_unit` → `unit_price += amount`
   - `add_flat` → `unit_price += amount`
   - `add_per_count` → `unit_price += amount * configured_options[option_id]`
   - `multiply_unit_price` → `unit_price *= amount`
3. Snapshots the resolved values to the line:
   - `configured_options` (jsonb) — the user's choices keyed by option id
   - `resolved_unit_price` — frozen final unit price
   - `resolved_options_label` — printed-estimate-friendly summary

Once written, these fields **never re-resolve**. Edits to the Product's options/modifiers/recipe after line creation do not retroactively change the estimate. This preserves the contract semantics of the estimate document.

The `configured_options` jsonb is also the input that `RecipeResolver` reads at install task creation (see § Cut-List Materialization below).

---

### `TaskType` (Bubble) — MODIFIED

Add `defaultTeamMemberIds`:

```typescript
interface TaskType {
  // --- existing fields ---
  id: string;
  display: string;
  color: string;
  icon: string;              // SF Symbol name
  isDefault: boolean;
  displayOrder: number;
  companyId: string;
  deletedAt: Date | null;

  // --- NEW field ---
  defaultTeamMemberIds: string[];  // TeamMember IDs — default crew for this task type
}
```

**Usage:** When a task is auto-generated from a line item, it inherits `TaskType.defaultTeamMemberIds`. Users can override at the individual task level in the Review Tasks modal.

---

### `ProjectTask` (Bubble) — MODIFIED

Add traceability fields:

```typescript
interface ProjectTask {
  // --- existing fields ---
  id: string;
  projectId: string;
  companyId: string;
  taskTypeId: string | null;
  status: TaskStatus;          // Booked | InProgress | Completed | Cancelled
  customTitle: string | null;
  taskNotes: string | null;
  taskColor: string | null;
  calendarEventId: string | null;
  teamMemberIds: string[];
  displayOrder: number;
  deletedAt: Date | null;

  // --- NEW fields ---
  sourceLineItemId: string | null;   // Supabase LineItem ID that generated this task
  sourceEstimateId: string | null;   // Supabase Estimate ID that generated this task
}
```

**Usage:** Enables traceability — from any task, you can trace back to the exact estimate line item and estimate that created it. Useful for scope change tracking and audit history.

---

### `Project` (Bubble) — MODIFIED

Add opportunity linkage:

```typescript
interface Project {
  // --- existing fields ---
  id: string;
  title: string;
  status: ProjectStatus;     // RFQ | Estimated | Accepted | InProgress | Completed | Closed | Archived
  clientId: string | null;
  companyId: string;
  address: string | null;
  latitude: number | null;
  longitude: number | null;
  startDate: Date | null;
  endDate: Date | null;
  duration: number | null;
  notes: string | null;
  teamMemberIds: string[];
  defaultProjectColor: string | null;
  deletedAt: Date | null;

  // --- NEW field ---
  opportunityId: string | null;  // Supabase Opportunity ID — trace back to the originating lead
}
```

**Note:** `projectImages` (comma-separated string) is deprecated in favor of the new `ProjectPhoto` entity. See [Project Photos](#project-photos).

---

### `CalendarEvent` (Bubble) — REMOVED

> **NOTE:** The `CalendarEvent` model has been fully removed from the iOS codebase. Scheduling dates are now stored directly on `ProjectTask` (via `startDate`/`endDate` properties). Project dates are computed from their child tasks. The schema below is retained as historical reference for the Bubble backend, which may still have this data type.

```typescript
// REMOVED — Historical reference only.
// Scheduling is now task-based: ProjectTask.startDate / ProjectTask.endDate.
// Site visit scheduling uses SiteVisit entity directly.

type CalendarEventType = 'task' | 'site_visit' | 'other'

interface CalendarEvent {
  // --- existing fields (now optional where marked) ---
  id: string;
  companyId: string;
  title: string;
  color: string | null;
  startDate: Date;
  endDate: Date;
  duration: number | null;
  teamMemberIds: string[];
  deletedAt: Date | null;

  // Previously required — now optional
  projectId: string | null;       // null for pre-project site visits
  taskId: string | null;          // null for site visit events

  // --- NEW fields ---
  eventType: CalendarEventType;   // 'task' | 'site_visit' | 'other'
  opportunityId: string | null;   // for pre-project calendar events
  siteVisitId: string | null;     // links to SiteVisit record
}
```

---

### `Estimate` (Supabase) — MODIFIED

Add project linkage:

```typescript
interface Estimate {
  // --- existing fields ---
  id: string;
  companyId: string;
  clientId: string | null;
  opportunityId: string | null;
  title: string;
  estimateNumber: string;        // EST-0001, EST-0002...
  status: EstimateStatus;
  issueDate: Date;
  expirationDate: Date | null;
  lineItems: LineItem[];
  optionalItems: LineItem[];
  depositSchedule: DepositSchedule | null;
  paymentMilestones: PaymentMilestone[];
  totalAmount: number;
  taxAmount: number;
  discountAmount: number;
  pdfStoragePath: string | null;
  version: number;
  parentId: string | null;       // for revision history
  createdAt: Date;
  updatedAt: Date;
  deletedAt: Date | null;

  // --- NEW field ---
  projectId: string | null;      // Bubble Project ID — which project this estimate belongs to
}
```

**Rules:**
- `projectId` is null until estimate is sent (filing into project is part of the Send Flow)
- A project can have multiple estimates (multiple scopes, phases, revisions)
- Project total value = `SUM(totalAmount) WHERE status = 'approved'`

---

### `Invoice` (Supabase) — MODIFIED

Add project and estimate linkage:

```typescript
interface Invoice {
  // --- existing fields ---
  id: string;
  companyId: string;
  clientId: string | null;
  invoiceNumber: string;         // INV-0001...
  status: InvoiceStatus;
  issueDate: Date;
  dueDate: Date | null;
  paymentTerms: string | null;
  lineItems: InvoiceLineItem[];
  amountDue: number;
  amountPaid: number;            // maintained by DB trigger
  balance: number;               // maintained by DB trigger
  payments: Payment[];
  notes: string | null;
  pdfStoragePath: string | null;
  voidedAt: Date | null;
  createdAt: Date;
  updatedAt: Date;
  deletedAt: Date | null;

  // --- NEW fields ---
  projectId: string | null;      // Bubble Project ID
  estimateId: string | null;     // Supabase Estimate ID this was converted from
}
```

---

### `Product` (Supabase) — MODIFIED (Phase 13)

Phase 13 expanded the Product schema to support both barebones and configurable Products. See `09_FINANCIAL_SYSTEM.md` § Products & Services Catalog and `03_DATA_ARCHITECTURE.md` § 21 (Product) for the canonical schema.

Key Phase 13 additions:
- `basePrice` (replaces `defaultPrice` as the primary unit price column; `default_price` mirrored via Postgres trigger until ops-web cuts over)
- `pricingUnit` enum: `each` / `flat_rate` / `linear_foot` / `sqft` / `hour` / `day`
- `kind` enum: `service` / `good`
- `sku`, `isFavorite`, `minimumCharge`, `minimumQuantity`, `showBomOnEstimate`, `showInStorefront`, `tieredPricing` (jsonb)
- `unitId` FK to `catalog_units.id`
- Wire-field bug fixed — DTO no longer writes to non-existent `unit_price`/`cost_price` columns

Configurable Products carry zero-or-more rows in four extension tables: `product_options`, `product_option_values`, `product_pricing_modifiers`, `product_materials`. A "barebones" Product has zero rows in every layer and behaves identically to a flat product.

**Catalog-driven task auto-fill** (preserved from earlier behavior): when a user adds a Product to an estimate, `product.type` and `product.taskTypeId` automatically populate the line item; the line item's resolved configuration is captured at creation by `ProductConfigurationResolver`.

---

### Cut-List Materialization (Phase 13)

When a project transitions to `.inProgress` and install tasks are generated, recipes resolve to concrete `task_materials` rows pinned to specific `catalog_variants`. This is the canonical cut list the field crew works against.

**Lifecycle:**

```
Estimate approved
  └─ Project status → .accepted
      └─ Tasks auto-generated from LABOR line items (existing flow)
          ↓
Project status → .inProgress (install begins)
  └─ For each ProjectTask with sourceLineItemId:
       1. Load line.configured_options snapshot
       2. Walk ProductMaterial rows for line.productId:
            - Variant-pinned (catalog_variant_id non-null) → use directly
            - Family-pinned (catalog_item_id non-null) → resolve variant_selector against
              configured_options, find the matching variant on that family
       3. Multiply quantity_per_unit by line.quantity
            (and by configured_options[scaled_by_option_id] if scaled_by_option_id set)
       4. Insert task_materials rows pinned to specific catalog_variant_ids
```

`CutListMaterializer` lives in `OPS/Network/Sync/`. Resolution is **idempotent** — re-running for the same task replaces the existing rows in a single transaction. This means an estimate edit (recipe change, option change) followed by a re-materialization gives the field crew the latest cut list without leaving stale rows behind.

**Why install-time, not estimate-time?** The cut list must reflect the configuration the customer signed. Resolving at install creation means:
- Pricing was already frozen on the line item — recipe re-resolution doesn't affect billing.
- Stock state is fresh — variant SKUs that were active at estimate time but later marked inactive can be replaced by an admin before install.
- Family-level recipe edits can flow into pending installs without rebuilding old estimates.

`task_materials` rows write through the legacy `inventory_item_id` column too (null for new rows) — the field crew's view-layer is unchanged; only the FK column it reads has been swapped.

---

### Drawing → Estimate Adapter (Phase 13)

The Deck Builder canvas can emit a fully-populated draft Estimate in one tap. This is the most consequential time-saver in the catalog redesign — hours of estimate writing collapse into a single button. The deck side closed the loop in 2026-05-07: `ComponentEmitter` projects geometry into the catalog's `components[]` vocabulary on every save, the adapter resolves Products + options, and the merge layer reconciles the result with the legacy geometry-driven path.

**Entry point:** Deck Builder canvas → toolbar `Estimate` button → `EstimatePreviewSheet` → "Create Estimate". One button, one flow — the merge layer routes adapter-vs-legacy per component_type based on company state. (UX decision per the deck-catalog spec § 7 — single entrypoint avoids parallel surfaces.)

**End-to-end flow** — drawing → components → adapter → line_items → task_materials:

```
User taps Estimate button on Deck Builder
   ↓
DeckBuilderViewModel.save()
   ├─ DeckDrawingData.toJSON() runs
   │     └─ ComponentEmitter.emit(self) populates `components[]` from
   │        canonical geometry — one row per railing / post_set /
   │        stair_set / deck_board / gate. Per-edge linear_feet is
   │        net of stair span and gate widths; deck_board sqft is
   │        per-detected-face; multi-level connection stairs carry
   │        level_id pinned to the upper level.
   └─ drawingDataJSON written with up-to-date components projection
   ↓
DeckBuilderViewModel.mergedCatalogLineItems()
   ├─ DesignToEstimateAdapter.generate(design, companyId, modelContext)
   │     ├─ Parse drawing_data → walk components[]
   │     ├─ For each component:
   │     │    1. Look up company_default_products[component_type] → Product
   │     │    2. For each ProductOption: pull $design.<key> from metadata,
   │     │       fall back to default_value if missing
   │     │    3. Compute quantity from pricing_unit + metadata
   │     │       (linear_feet, sqft, count, tread_count, etc.)
   │     │    4. Apply ProductPricingModifier rows → resolved_unit_price
   │     │    5. Snapshot configured_options + resolved_unit_price +
   │     │       resolved_options_label
   │     └─ Emit GeneratedLineItem carrying componentType + snapshot
   │
   └─ EstimateGeneratorService.generateLineItems(drawingData)
         └─ Walks vertices/edges/surfaces/connections — emits flat
            rows with categories Surface / Substructure / Railing /
            Stairs / Connecting Stairs / Other, plus warnings (missing
            elevation, AR accuracy notes, multi-level narrative)
   ↓
CatalogEstimateMerger.merge(adapterItems, legacyItems, defaultsCovered)
   ├─ Adapter rows kept (sorted first)
   ├─ Legacy rows in covered categories dropped:
   │     railing or post_set → drop "Railing"
   │     stair_set            → drop "Stairs", "Connecting Stairs"
   │     deck_board           → drop "Surface"
   │     gate                 → drop nothing
   ├─ Legacy rows in uncovered categories pass through
   └─ Warning rows always pass through
   ↓
DeckBuilderViewModel.generateEstimate() persists
   ├─ CatalogEstimateMerger.groupByTaskType(merged, taskTypes)
   ├─ For each group:
   │     - parent CreateLineItemDTO (LABOR / OTHER)
   │     - per child:
   │         * configuredOptions (RawJSONColumn) ← adapter-only
   │         * resolvedUnitPrice                ← adapter-only
   │         * resolvedOptionsLabel             ← adapter-only
   │         * (legacy children leave those fields nil)
   └─ line_items rows persist via EstimateRepository
   ↓
[Project transitions to .accepted → tasks auto-generate from LABOR rows]
   ↓
[Project transitions to .inProgress]
   ↓
CutListMaterializer.materialize(forLineItem:projectTaskId:)
   ├─ Reads line.configured_options snapshot
   ├─ RecipeResolver.resolve(materials, configuredOptions, ...)
   │     - Variant-pinned recipe rows → use directly
   │     - Family-pinned + variant_selector → resolve $option.<name>
   │       to a CatalogOptionValue, match candidate variants
   │     - Scale by configuredOptions[scaledByOptionId] when set
   └─ TaskMaterialRepository.createMaterials([CreateTaskMaterialDTO])
   ↓
task_materials rows pinned to concrete catalog_variant_ids
   = the cut list the field crew works against
```

**Resilience at every hop:**

- `components[]` missing on legacy `drawing_data` JSON → `DeckBuilderViewModel.init` backfills via `ComponentEmitter.emit` so the adapter sees a populated projection on first load. Designs the user never reopens stay legacy on disk; adapter no-ops on them.
- `company_default_products[component_type]` missing → adapter skips the component silently. Merger then falls through to legacy for that category.
- Line items without `configured_options` (legacy rows or barebones flat products) → `CutListMaterializer.materialize` returns 0 rows (no recipe to resolve); install task carries no `task_materials` and the field crew works from the line item directly.
- ops-web round-trips the same `drawingDataJSON`. The components key is forward-compatible (web ignores keys it doesn't recognize). If web strips the key on save, iOS backfills again on next load.

**Reserved metadata keys per `component_type`** — emitted by `ComponentEmitter`, consumed by the adapter via `option_default_source = "$design.<key>"`:

| Component | Metadata keys |
|---|---|
| `railing` | `linear_feet`, `corners_count`, `color`, `mount_type`, `mount_surface`, `edge_id`, optional `level_id` |
| `post_set` | `count`, `height`, `color`, `mount_type`, `edge_id`, optional `level_id` |
| `stair_set` | `tread_count`, `width`, `color`, `mount_type`, `edge_id` OR `connection_id`, `level_id` (multi-level) |
| `deck_board` | `sqft`, `color`, `material`, `surface_id`, optional `level_id` |
| `gate` | `count`, `width`, `color`, `mount_type`, `mount_surface`, `edge_id`, optional `level_id` |

Adding new metadata keys is fine; renaming or removing breaks the adapter contract — see `OPS/DataModels/Supabase/Catalog/CompanyDefaultProduct.swift` (`DesignComponentType` enum) and `OPS/Services/DesignToEstimateAdapter.swift:148-173` (`computeQuantity`).

**Position in the project lifecycle:**

```
Lead/inquiry → Opportunity created
  ↓
Site visit / scope captured
  ↓
Drawing produced in Deck Builder (component_type tagged on each component)
  ↓
USER TAPS GENERATE ESTIMATE  ← drawing→estimate adapter runs here
  ↓
Draft estimate appears with all line items snapshotted
  ↓
User reviews/edits → sends estimate
  ↓
Customer approves → project created → tasks generated → cut list materialized
```

---

### `Opportunity` (Supabase) — MODIFIED

Add Gmail source field:

```typescript
interface Opportunity {
  // --- existing fields (unchanged) ---
  id: string;
  companyId: string;
  clientId: string | null;
  title: string;
  description: string | null;
  contactName: string | null;
  contactEmail: string | null;
  contactPhone: string | null;
  stage: OpportunityStage;
  source: OpportunitySource | null;
  assignedTo: string | null;
  priority: OpportunityPriority | null;
  estimatedValue: number | null;
  actualValue: number | null;
  winProbability: number;
  expectedCloseDate: Date | null;
  actualCloseDate: Date | null;
  stageEnteredAt: Date;
  projectId: string | null;
  lostReason: string | null;
  lostNotes: string | null;
  address: string | null;
  lastActivityAt: Date | null;
  nextFollowUpAt: Date | null;
  tags: string[];
  createdAt: Date;
  updatedAt: Date;
  deletedAt: Date | null;

  // --- NEW field ---
  sourceEmailId: string | null;   // Gmail message ID — set when opportunity created from Gmail
}
```

---

### `Activity` (Supabase) — MODIFIED

Add email threading, attachment support, and site visit linkage:

```typescript
interface Activity {
  // --- existing fields ---
  id: string;
  companyId: string;
  opportunityId: string | null;
  clientId: string | null;
  estimateId: string | null;
  invoiceId: string | null;
  type: ActivityType;
  subject: string | null;
  content: string | null;
  outcome: string | null;
  direction: 'inbound' | 'outbound' | null;
  durationMinutes: number | null;
  createdBy: string;
  createdAt: Date;
  updatedAt: Date;
  deletedAt: Date | null;

  // --- NEW fields ---
  attachments: string[];            // S3 URLs — email attachments, documents
  emailThreadId: string | null;     // Gmail thread ID — groups email chain together
  emailMessageId: string | null;    // Gmail message ID — prevents duplicate auto-logging
  isRead: boolean;                  // false for auto-logged inbound, true for manual entry
  siteVisitId: string | null;       // set if auto-created from a SiteVisit completion
  projectId: string | null;         // direct link to project (for post-win activities)
}
```

**New `ActivityType` values to add:**
- `site_visit` — a scheduled/completed site visit
- `site_visit_scheduled` — system event when site visit is booked

---

### `CompanySettings` (Supabase) — MODIFIED / NEW TABLE

Extend (or create if not exists) to support lifecycle configuration:

```typescript
interface CompanySettings {
  companyId: string;                        // Primary key (1:1 with Company)

  // Task generation
  autoGenerateTasks: boolean;               // Skip review modal on estimate approval (default: false)

  // Follow-up automation
  followUpReminderDays: number;             // Days before auto-moving to follow_up stage (default: 3)

  // Gmail
  gmailAutoLogEnabled: boolean;             // Auto-log emails from connected Gmail accounts (default: true)

  createdAt: Date;
  updatedAt: Date;
}
```

---

## Recurring Task Lifecycle (Phase 3 — added 2026-04-27)

Recurring tasks short-circuit the estimate-driven task generation pipeline. They live as `task_recurrences` templates that the cron worker `/api/cron/recurrence-generate` materializes into concrete `project_tasks` rows on a 60-day rolling horizon. Generated occurrences are otherwise normal tasks — schedulable, completable, deletable.

### Flow diagram

```
                ┌──────────────────────────────────────────┐
  USER ACTION   │ Repeat picker on task detail panel       │
                │ Selects: Off / Daily / Weekly / ... /    │
                │ Custom (RFC 5545 RRULE editor)           │
                └────────────────────┬─────────────────────┘
                                     │
                                     ▼
                ┌──────────────────────────────────────────┐
  TEMPLATE      │ task_recurrences row                     │
  CREATED       │   rrule, start_anchor, end_anchor,       │
                │   all_day, start_time, end_time,         │
                │   duration, team_member_ids,             │
                │   next_generation_at = NOW()             │
                └────────────────────┬─────────────────────┘
                                     │
                                     ▼
                ┌──────────────────────────────────────────┐
  CRON RUN      │ /api/cron/recurrence-generate every 4h:  │
                │ 1. SELECT WHERE next_generation_at<=NOW()│
                │ 2. RRule.between(NOW, NOW+60d)           │
                │ 3. For each candidate:                   │
                │    - lookup exception (skip / override)  │
                │    - INSERT project_tasks (recurrence_id │
                │      + recurrence_origin_date)           │
                │    - emit `schedule_change` notification │
                │ 4. UPDATE next_generation_at = NOW+4h    │
                └────────────────────┬─────────────────────┘
                                     │
                                     ▼
                ┌──────────────────────────────────────────┐
  CALENDAR      │ project_tasks row visible in Day / Week /│
                │ Month / Crew / Hourly views just like    │
                │ any one-off task. Drag / edit triggers   │
                │ the recurrence-edit prompt.              │
                └────────────────────┬─────────────────────┘
                                     │
                  ┌──────────────────┼──────────────────┐
                  │                  │                  │
                  ▼                  ▼                  ▼
            ┌─────────┐      ┌──────────────┐    ┌──────────┐
            │ this    │      │ this+follow  │    │ all      │
            │         │      │              │    │          │
            │ exception│     │ cap original │    │ patch    │
            │ row +   │      │ end_anchor;  │    │ original │
            │ patch   │      │ fork new tpl;│    │ template │
            │ task    │      │ re-point     │    │ (cron    │
            │         │      │ future tasks │    │ regens)  │
            └─────────┘      └──────────────┘    └──────────┘
```

### Idempotency

`uq_project_tasks_recurrence_origin` on `(recurrence_id, recurrence_origin_date) WHERE recurrence_id IS NOT NULL AND deleted_at IS NULL` prevents duplicate inserts on cron re-runs. The cron also pre-fetches existing origins per-recurrence so it skips before attempting the insert (avoiding 23505 noise in logs).

### Soft-delete semantics

`RecurrenceService.softDelete(templateId)` cascades:
1. `task_recurrences.deleted_at = NOW()` — template no longer runs in the cron.
2. `project_tasks.deleted_at = NOW()` for every row where `recurrence_id = templateId AND status = 'active' AND start_date > NOW()` — un-started future occurrences disappear.
3. Past, in-progress, and completed occurrences are preserved as historical records.

### Notification fan-out

Every materialized occurrence fires a `schedule_change` notification per assigned crew member (`team_member_ids`). The web notification rail (Section 14, Edge Tab) picks them up via TanStack Query polling. iOS users will see them via the existing OneSignal push channel once iOS adopts the `recurrenceId` columns (planned post-Phase-3).

---

## New Entities

### `TaskTemplate` (Bubble) — NEW

Defines the default tasks that are proposed when a LABOR line item is tagged with a TaskType. This is what enables "Deck Renovation → [Footings, Framing, Vinyl Membrane]" without any manual input per estimate.

```typescript
interface TaskTemplate {
  id: string;
  companyId: string;
  taskTypeId: string;                   // parent TaskType
  title: string;                        // e.g., "Footings", "Framing", "Vinyl Membrane"
  description: string | null;           // optional instructions
  estimatedHours: number | null;        // optional, for scheduling hints
  displayOrder: number;                 // controls order in Review Tasks modal
  defaultTeamMemberIds: string[];       // overrides TaskType.defaultTeamMemberIds if non-empty
  deletedAt: Date | null;
}
```

**Example data:**
```
TaskType: "Deck Work"
  TaskTemplate 1: "Footings"         order: 1  crew: [John, Mike]
  TaskTemplate 2: "Framing"          order: 2  crew: [John, Mike]
  TaskTemplate 3: "Vinyl Membrane"   order: 3  crew: [John]

TaskType: "Railing"
  TaskTemplate 1: "Picket Railing Install"  order: 1  crew: [Sarah]
```

**Task generation logic:**
```
For each LABOR lineItem in approved estimate:
  taskType = getTaskType(lineItem.taskTypeId)
  templates = getTaskTemplates(lineItem.taskTypeId)  // ordered by displayOrder

  if templates.length > 0:
    for each template in templates:
      proposeTask({
        title: template.title,
        taskTypeId: lineItem.taskTypeId,
        teamMemberIds: template.defaultTeamMemberIds.length > 0
                       ? template.defaultTeamMemberIds
                       : taskType.defaultTeamMemberIds,
        sourceLineItemId: lineItem.id,
        sourceEstimateId: estimate.id
      })
  else:
    // No templates: propose one generic task
    proposeTask({
      title: lineItem.description,
      taskTypeId: lineItem.taskTypeId,
      teamMemberIds: taskType?.defaultTeamMemberIds ?? [],
      sourceLineItemId: lineItem.id,
      sourceEstimateId: estimate.id
    })
```

**iOS authoring (2026-05-11 — bug 4dadd96c)**: `TaskTemplate` rows are
authored from inside `TaskTypeSheet`'s `DEFAULT SUB-TASKS` section
(edit-mode only — the parent task type id must exist before templates
can pin to it). Each template carries `task_type_ref` (uuid FK) and
`task_type_id` (legacy text mirror) so legacy reads and new reads land
on the same parent. Sub-tasks are managed by `TaskTemplateEditSheet`
(create / edit / soft-delete) and synced via
`TaskTemplateRepository`. The Supabase table is `task_templates` —
schema unchanged from the original Bubble-era design.

**Related iOS surfaces for the catalog interlink** (same bug):
- Product create / edit forms now expose `task_type_ref` via a required
  picker for LABOR products (optional for Material / Fee). See bible
  section `03_DATA_ARCHITECTURE.md` § 3 → "Catalog interlink surfaces
  on iOS" for the full set of surfaces and component file paths.
- `TaskTypeMergeSheet` now re-pins linked products and templates onto
  the merge target so neither is silently orphaned on the deleted
  source row.

---

### `ActivityComment` (Supabase) — NEW

Threaded comments on any Activity entry. Internal-only (staff eyes only). Supports future client portal visibility via `isClientVisible` flag.

```typescript
interface ActivityComment {
  id: string;
  companyId: string;
  activityId: string;                   // parent Activity
  userId: string;                       // author
  content: string;                      // plain text or markdown
  isClientVisible: boolean;             // always false for now — future portal
  createdAt: Date;
  updatedAt: Date | null;
  deletedAt: Date | null;
}
```

**UI pattern:**
```
Activity: Sent Estimate #042 to John Smith        ● 2 hours ago
  "Hi John, please find your estimate attached..."
  ────────────────────────────────────────────────
  [INTERNAL] Sarah: "He asked about timeline"
  [INTERNAL] John: "Told him 3 weeks, he's ok"
  [+ Add comment...]
```

**Rules:**
- Any staff member can comment on any activity
- Comments are soft-deleted (preserving audit trail)
- No notifications in v1 — comments are passive notes

---

### `SiteVisit` (Supabase) — NEW

A scheduled or ad-hoc visit to a job site for scope assessment, client meeting, or project check-in. Can exist before a project (on an Opportunity) or after (on a Project).

> **iOS status**: The `SiteVisit` SwiftData model exists (`OPS/OPS/DataModels/Supabase/SiteVisit.swift`) but no dedicated iOS views have been built yet. The site visit UI described below is design spec only at this time.

```typescript
type SiteVisitStatus = 'scheduled' | 'in_progress' | 'completed' | 'cancelled'

interface SiteVisit {
  id: string;
  companyId: string;
  opportunityId: string | null;     // pre-win: linked to opportunity
  projectId: string | null;         // post-win: linked to project
  clientId: string | null;          // denormalized for easy filtering

  // Scheduling
  scheduledAt: Date;
  durationMinutes: number;          // default: 60
  assigneeIds: string[];            // TeamMember IDs attending

  // Lifecycle
  status: SiteVisitStatus;          // scheduled → in_progress → completed | cancelled
  completedAt: Date | null;

  // On-site capture
  notes: string | null;             // scope observations (visible to staff)
  internalNotes: string | null;     // private staff notes (never shared)
  measurements: string | null;      // free-form: "Deck 400sqft, 14ft × 28ft, 6 posts"
  photos: string[];                 // S3 URLs captured on-site

  // Links created on completion
  activityId: string | null;        // auto-created Activity when status → completed
  calendarEventId: string | null;   // the calendar entry for this visit

  createdBy: string;
  createdAt: Date;
  updatedAt: Date;
  deletedAt: Date | null;
}
```

**Site visit lifecycle:**
```
BOOK SITE VISIT (from Opportunity card or Calendar)
  → SiteVisit created (status: scheduled)
  → SiteVisit scheduled (scheduling dates stored on SiteVisit/task directly; CalendarEvent model removed)
  → Activity auto-logged: "Site visit scheduled — Feb 20 @ 10am"
  → Opportunity stage → qualifying (if currently new_lead)

ON-SITE (staff opens visit on mobile/web)
  → SiteVisit.status → in_progress
  → Staff adds photos (camera or gallery)
  → Staff fills notes, measurements

MARK COMPLETE
  → SiteVisit.status → completed, completedAt = now
  → Activity auto-created on Opportunity timeline:
      type: site_visit
      subject: "Site visit completed"
      content: siteVisit.notes (preview)
      siteVisitId: siteVisit.id
  → Opportunity stage prompt: "Ready to build estimate?"
    → if Yes → creates Estimate (draft) → stage → quoting

JOB WON (opportunity converts to project)
  → For each photo in siteVisit.photos:
      ProjectPhoto created (source: 'site_visit', siteVisitId: siteVisit.id)
  → Photos appear in project gallery under "Site Visit" group
```

**SiteVisitService methods:**
- `createSiteVisit(data)` — creates visit + calendar event + activity
- `startSiteVisit(id)` — status → in_progress
- `completeSiteVisit(id, data)` — status → completed, creates completion activity
- `cancelSiteVisit(id)` — status → cancelled
- `uploadSiteVisitPhoto(id, file)` — uploads to S3, appends URL to photos[]
- `fetchSiteVisitsForOpportunity(opportunityId)` — all visits for a lead
- `fetchSiteVisitsForProject(projectId)` — all visits for a project

---

### `ProjectPhoto` (Supabase) — NEW

Replaces the `Project.projectImages` comma-separated string. Enables photos to be source-tagged, grouped in the gallery, and traced back to site visits.

```typescript
type PhotoSource = 'site_visit' | 'in_progress' | 'completion' | 'other'

interface ProjectPhoto {
  id: string;
  projectId: string;                // Bubble Project ID
  companyId: string;
  url: string;                      // S3 URL (full size)
  thumbnailUrl: string | null;      // S3 URL (thumbnail)
  source: PhotoSource;              // groups photos in gallery
  siteVisitId: string | null;       // set if sourced from a SiteVisit
  uploadedBy: string;               // User ID
  takenAt: Date | null;             // EXIF date if available, else upload date
  caption: string | null;
  deletedAt: Date | null;
}
```

**Photo gallery grouping:**
```
Project Photos — Smith Deck Job
  ├─ Site Visit (Feb 20)    [3 photos]   ← auto-attached when job won
  ├─ In Progress            [7 photos]   ← uploaded by field crew during tasks
  └─ Completion             [4 photos]   ← uploaded at project sign-off
```

**Migration from `projectImages` string:**
- Existing `projectImages` comma-separated URLs → create `ProjectPhoto` rows with `source: 'other'`
- New uploads go through `ProjectPhoto` table
- `projectImages` field on Project is deprecated but not removed until migration is complete

---

### `EmailConnection` (Supabase) — Renamed from `GmailConnection`

Multi-provider email connection for pipeline import. Supports Gmail and Microsoft 365 via provider abstraction layer. Stores OAuth tokens, sync profile (pattern detection rules), webhook subscription, and AI feature flags.

```typescript
interface EmailConnection {
  id: string;
  companyId: string;
  provider: 'gmail' | 'microsoft365';
  accessToken: string;              // encrypted at rest
  refreshToken: string;             // encrypted at rest
  tokenExpiresAt: Date;
  userEmail: string;
  userName: string;
  syncProfile: SyncProfile;         // pattern detection rules (JSONB)
  syncIntervalMinutes: number;
  lastSyncHistoryId: string | null;  // Gmail historyId or M365 deltaLink
  lastSyncAt: Date | null;
  opsLabelId: string | null;        // Gmail label ID or M365 category ID
  webhookSubscriptionId: string | null;
  webhookExpiresAt: Date | null;
  aiReviewEnabled: boolean;
  aiMemoryEnabled: boolean;
  status: 'active' | 'paused' | 'error' | 'setup_incomplete';
  createdAt: Date;
  updatedAt: Date;
}
```

**See [Email Pipeline Integration](#email-pipeline-integration) for full sync logic, pattern detection, AI classification, and webhook architecture.**

---

## Automation Rules & Triggers

### Automation A: Estimate Sent → Create Client

**Trigger:** User clicks "Send Estimate" and estimate has no `clientId`

**Flow:**
1. Inline prompt: "Who is this estimate for?"
2. User types name — auto-suggests existing `Client` records (fuzzy search by name + email)
3. User selects existing client OR confirms new
4. If new: `Client` created with `{ name: contactName, email: contactEmail, phone: contactPhone }` from linked Opportunity
5. `estimate.clientId = client.id`
6. `opportunity.clientId = client.id` (if opportunity linked)

**Rule:** This prompt is non-skippable. An estimate cannot be sent without a client.

---

### Automation B: Estimate Sent → Create/Link Project

**Trigger:** User clicks "Send Estimate" (after client step)

**Flow:**
1. Inline prompt: "File into a project?"
2. User searches existing projects for this client OR creates new
3. If new: `Project` created with `{ title: estimate.title, clientId, status: 'RFQ', opportunityId }`
4. `estimate.projectId = project.id`
5. `opportunity.projectId = project.id` (if opportunity linked)
6. `project.status → Estimated`

**Rule:** This prompt can be skipped — estimates can remain standalone. Filing into a project is required before task generation (prompted again at approval if still null).

---

### Automation C: Estimate Approved → Generate Tasks

**Trigger:** `estimate.status` changes to `Approved`

**Prerequisites:** `estimate.projectId` must be set. If null, prompt user to file into a project first.

**Flow:**
1. If `CompanySettings.autoGenerateTasks = false` (default): open Review Tasks modal
2. If `CompanySettings.autoGenerateTasks = true`: generate silently

**Task generation logic (per LABOR line item):**
```
For each lineItem WHERE lineItem.type = 'LABOR':
  If lineItem.taskTypeId is set:
    templates = TaskTemplate[] for that taskTypeId (ordered by displayOrder)
    If templates.length > 0:
      → Propose one task per template
        title: template.title
        crew: template.defaultTeamMemberIds OR taskType.defaultTeamMemberIds
    Else:
      → Propose one generic task
        title: lineItem.description
        crew: taskType.defaultTeamMemberIds
  Else:
    → Propose one generic task
      title: lineItem.description
      crew: []
```

**After confirmation:**
- `ProjectTask` created for each confirmed task
- `task.sourceLineItemId = lineItem.id`
- `task.sourceEstimateId = estimate.id`
- `task.status = 'Booked'`
- `opportunity.stage → won` (if not already)
- `project.status → Accepted`

---

### Automation D: Site Visit Completed → Opportunity Stage Advance

**Trigger:** `SiteVisit.status → completed`

**Flow:**
1. Auto-create Activity on Opportunity timeline (type: `site_visit`)
2. Prompt: "Ready to build an estimate?" (dismissible)
3. If Yes → open Estimate creation form pre-linked to this opportunity → `opportunity.stage → quoting`

---

### Automation E: Opportunity Won → Attach Site Visit Photos

**Trigger:** `opportunity.stage → won`

**Flow:**
```
For each SiteVisit WHERE siteVisit.opportunityId = opportunity.id:
  For each photo URL in siteVisit.photos:
    Create ProjectPhoto {
      projectId: opportunity.projectId,
      url: photo,
      source: 'site_visit',
      siteVisitId: siteVisit.id,
      uploadedBy: siteVisit.createdBy,
      takenAt: null
    }
```

---

### Automation F: Project Status Cascades

| Trigger | Effect |
|---|---|
| Estimate sent (project linked) | `project.status → Estimated` |
| Estimate approved | `project.status → Accepted` |
| First ProjectTask status → InProgress | `project.status → InProgress` |
| All ProjectTasks status = Completed | `project.status → Completed` (prompt) |
| Invoice status → Paid | `project.status → Closed` |

---

### Automation G: Auto Follow-Up on Quoted Stage

**Trigger:** `opportunity.stageEnteredAt` for `quoted` stage + `CompanySettings.followUpReminderDays` days have elapsed

**Implementation:** Scheduled cron job or Supabase Edge Function running every hour

**Flow:**
1. Query: opportunities WHERE stage = `quoted` AND stageEnteredAt < NOW - followUpReminderDays AND no FollowUp with type `quote_follow_up` in last X days
2. For each matching opportunity:
   - Create `FollowUp { type: 'quote_follow_up', isAutoGenerated: true, triggerSource: 'auto_follow_up_timer' }`
   - `opportunity.stage → follow_up`
   - `opportunity.nextFollowUpAt = followUp.dueAt`

---

## Communication Logging

### Manual Communication Logging

Staff can log any communication directly from the Opportunity or Project activity timeline:

**Log a Call:**
```
type: call
direction: inbound | outbound
subject: "Called John re: estimate"
content: call notes
outcome: "left voicemail" | "discussed" | "no answer"
durationMinutes: 5
```

**Log an Email:**
```
type: email
direction: inbound | outbound
subject: email subject line
content: email body / summary
attachments: [S3 URLs]
```

**Log a Meeting:**
```
type: meeting
subject: "Site meeting with John"
content: meeting notes
durationMinutes: 45
outcome: "agreed on scope"
```

**Log a Note:**
```
type: note
subject: optional
content: free-form notes
```

**Log a Text/SMS:**
```
type: note   (no dedicated SMS type in v1)
subject: "Text from John"
content: message content
direction: inbound | outbound
```

### Activity Comments

After any activity is logged, team members can append internal comments:

```
Activity: "Called John Smith — Left voicemail"    ● Yesterday 3:15pm
  [INTERNAL] Sarah: "He texted back, calling tomorrow"
  [INTERNAL] John:  "I'll take the call"
  [+ Add comment]
```

**Rules:**
- Comments are visible to all staff at the company
- Comments are never visible to clients (future portal: `isClientVisible` toggle)
- Comments are soft-deleted only

### Activity Timeline Display

Activities are shown in reverse chronological order on both:
- **Opportunity card** (all activities pre-win + win event)
- **Project detail** (all activities post-project-creation)

Timeline includes:
- Manual activities (calls, emails, meetings, notes)
- System events (estimate sent, estimate approved, stage changes, tasks created)
- Auto-logged Gmail emails
- Site visit completions (with photo count)
- Invoice events (sent, payment received)

---

## Site Visits

### Creating a Site Visit

Site visits can be created from:
1. **Opportunity card** → "Book Site Visit" button
2. **Calendar** → "New Event" → select type "Site Visit" → link to Opportunity/Project
3. **Project detail** → "Book Site Visit" (for post-win check-ins)

**Required fields:** scheduledAt, assigneeIds (at least one), opportunityId OR projectId

### On-Site Experience (Mobile)

When a site visit is due:
1. Staff receives calendar notification
2. Opens site visit from Calendar or Opportunity card
3. Taps "Start Visit" → status → `in_progress`
4. Captures photos (camera or gallery)
5. Fills notes and measurements
6. Taps "Complete Visit" → status → `completed`

### Site Visit Data Capture

```
Notes field:        "Existing deck is 14ft × 28ft (392sqft). 6 existing posts,
                     4 need replacement. Access tight on north side."

Internal Notes:     "Client wants work done before July 4 — firm deadline"

Measurements:       "Deck: 14ft × 28ft = 392sqft
                     Posts: 6 total, 30in above grade
                     Railing: 52 linear feet"

Photos:             [photo1.jpg] [photo2.jpg] [photo3.jpg]
```

### Site Visit → Estimate Continuity

When a user creates an estimate after completing a site visit:
- Site visit notes are shown as a reference panel in the estimate builder (read-only sidebar)
- Photos from the site visit are accessible for attaching to the estimate PDF
- Measurements can be copy-pasted into line item descriptions

---

## Project Photos

### Photo Sources

| Source | How Added | When Added |
|---|---|---|
| `site_visit` | Auto from SiteVisit.photos | When opportunity is won |
| `in_progress` | Uploaded by field crew during task work | During InProgress status |
| `completion` | Uploaded at project sign-off | When all tasks complete |
| `other` | Manual upload from project detail | Any time |

### Gallery UI

```
Project Photos — Smith Deck Job  [Upload Photo ▼]

  Site Visit  Feb 20                         [3]
  ┌────┐ ┌────┐ ┌────┐
  │    │ │    │ │    │
  └────┘ └────┘ └────┘

  In Progress                               [7]
  ┌────┐ ┌────┐ ┌────┐ ┌────┐
  │    │ │    │ │    │ │    │  +3
  └────┘ └────┘ └────┘ └────┘

  Completion                                [4]
  ┌────┐ ┌────┐ ┌────┐ ┌────┐
  │    │ │    │ │    │ │    │
  └────┘ └────┘ └────┘ └────┘
```

### Migration from Legacy `projectImages`

The `Project.projectImages` field (comma-separated string) is deprecated. Migration:
1. Read `projectImages` string, split by comma
2. For each URL: create `ProjectPhoto { source: 'other', url, projectId, companyId }`
3. Mark `projectImages` as empty string once migrated
4. Remove field from API usage after all records migrated

---

## Email Pipeline Integration

> **Platform status**: Email integration is implemented on OPS-Web with support for both Gmail and Microsoft 365. API routes under `/api/integrations/email/`, plus a provider abstraction layer, pattern detection engine, AI classification system, webhook-driven sync, and a 5-step "Import Your Pipeline" wizard. No email integration exists on iOS. The `email_connections` table (renamed from `gmail_connections`) stores per-connection provider, tokens, sync profile, webhook subscription, and AI feature flags.

### Lead Lifecycle Target Intent

The email pipeline's product contract is: messy email becomes a trustworthy pipeline record. Email threads and activities are the proof trail; the opportunity is the working truth the operator uses to run the lead.

Every linked inbound or outbound email should be evaluated against the opportunity, not only against the provider thread. If the opportunity is missing customer name, company name, phone, email, address/location, scope, estimated value, source/platform, contact relationship, or project context, the lifecycle should fill blank fields as that information becomes available. It must preserve source provenance: thread id, message id, extraction source, confidence, and whether a human confirmed or edited the value.

Core principles:
- **Opportunity is canonical**: `clients`, `sub_clients`, `activities`, `email_threads`, and `opportunity_email_threads` support the opportunity. They should not drift into conflicting truths.
- **Progressive enrichment**: every new linked email can improve the opportunity. Fill blanks and improve weak inferred values; do not silently overwrite operator-entered truth.
- **Opportunity-level staleness**: stale logic runs across all linked threads, known contacts, sub-contacts, spouses/partners, phone/email identities, and related new threads. A new thread from a related contact can reactivate the opportunity.
- **Conservative automation**: automate facts, suggest judgments, and require operator control for destructive or ambiguous actions. If OPS cannot determine the correct action with high confidence, preserve the data and make the state clear.
- **Phase C is optional**: the core lifecycle must remain correct with Phase C off. Phase C improves extraction, matching, drafting, and learning when enabled, but is not required for basic lifecycle correctness.
- **Drafts are auditable**: every draft stores its origin, generated text, final sent text, linked opportunity/thread/message context, edit history, and final disposition.

#### P1 Provider ID Guardrails

As of Lead Lifecycle P1, provider-backed email lifecycle writes must reject blank provider identifiers before creating any new activity, `email_threads` cache row, `opportunity_email_threads` link, or correspondence-count update.

Required behavior:
- Provider-backed sync/send/backfill paths require a nonblank provider thread id and nonblank provider message id.
- Import wizard activities are synthetic timeline records, so they may omit provider message id only through the explicit import-synthetic path. They still require a nonblank provider thread id before creating opportunities, thread links, activities, labels, or image-extraction work.
- Rejected provider-backed emails are quarantined by skipping lifecycle writes, logging a structured server warning, and incrementing sync diagnostics. A single invalid email must not crash the entire sync cycle.
- The contact-form parsed sender identity must remain consistent across matching, activity creation, and thread-cache writes for newly processed provider-backed emails.
- Existing bad rows are report-only until an operator approves cleanup. The P1 dry-run artifact lives at `docs/data-cleanup/lead-lifecycle-p1-bad-thread-dry-run-2026-05-26.md`.

#### P2 Canonical Enrichment

As of Lead Lifecycle P2, email ingestion performs conservative canonical enrichment after provider ID validation. Inbound sync, sent-folder safety-net sync, import wizard leads, and historical Gmail import can fill missing opportunity/client fields from deterministic facts that are already present in the email or reviewed import payload.

Allowed P2 writeback targets:
- `opportunities.contact_name`, `contact_email`, `contact_phone`
- `opportunities.address`
- `opportunities.estimated_value` and `detected_value`
- `opportunities.description`
- `opportunities.source` (`email` for email pipeline ingestion)
- `opportunities.source_email_id` (provider thread id)
- `clients.name`, `email`, `phone_number`, `address`

P2 writes only blanks or clearly weak placeholders such as empty values, unknown/new-lead markers, raw email-address names, zero estimated values, and known platform/system email addresses. It must not overwrite operator-entered client or opportunity values. Contact-form submitter identity remains preferred over the platform sender; platform sender emails such as Wix, HomeStars, or website form notifications are not written as customer email addresses.

Existing provenance support:
- `activities.email_thread_id` and `activities.email_message_id` preserve the provider thread/message proof for actual email activities.
- `opportunity_email_threads.thread_id` + `connection_id` preserve the opportunity-to-provider-thread link.
- `email_threads.provider_thread_id` preserves the inbox cache provider thread id.
- `opportunities.source_email_id` can hold the provider thread id for the lead source.

Current schema gaps for full provenance and company/source detail:
- No `clients.company_name` or `opportunities.company_name` column exists. Company name can only fill weak `clients.name` values when that is safe.
- No field-level provenance table or JSON column exists for canonical client/opportunity facts. Needed shape: entity type/id, field name, proposed value, extraction source, confidence, provider thread id, provider message id, confirmed/edited actor, and confirmed/edited timestamp.
- No `opportunities.source_platform` / `source_platform_label` column exists for HomeStars, Wix, website form, or other lead platform names.
- No provider message id column exists on `opportunities`; message-level proof lives on `activities.email_message_id`.
- No explicit contact relationship column exists on opportunities for spouse/PM/site-super relationships; `sub_clients.title` can hold that relationship only after a sub-client exists.

#### P3 Opportunity Relationship Matching

As of Lead Lifecycle P3, provider thread id is no longer the only lifecycle unit. New provider threads are evaluated against existing opportunities before OPS creates a cold duplicate. The matching boundary is the opportunity: once a new thread is deterministically linked, `opportunity_email_threads` receives the new `(thread_id, connection_id)` link, the inbound activity attaches to the winning opportunity, correspondence counters update there, and P2 enrichment runs against that same winning opportunity without overwriting operator-entered canonical values.

P3 deterministic gates:
- **Existing provider thread link**: if `(thread_id, connection_id)` is already linked, use that opportunity deterministically.
- **Exact known contact**: exact `clients.email`, `sub_clients.email`, or `opportunities.contact_email` can link to an existing active opportunity.
- **Existing related contact**: an exact sub-client email relationship links to the parent client's active opportunity.
- **Exact phone**: exact normalized phone match across opportunity/client/sub-client facts can link when the opportunity is active or the linked project is active.
- **Same address, same active job**: exact normalized address can link when the opportunity is active (`new_lead`, `qualifying`, `quoting`, `quoted`, `follow_up`, `negotiation`) or a linked project is active (`rfq`, `estimated`, `accepted`, `in_progress`).
- **Quoted prior-thread scope**: deterministic scope overlap can support a link only when it overlaps known prior opportunity/project text and the candidate is active. This is a strict enhancer, not a freeform guess.

P3 non-linking rules:
- Do not infer spouse, partner, property manager, or site-super relationships from first name or last name alone.
- Do not treat platform senders such as Wix, HomeStars, or website form notification mailboxes as customer identity. Parsed submitter identity wins.
- Do not blindly attach new work to terminal opportunities (`won`, `lost`, `discarded`, and future terminal values such as `merged`, `converted`, or `disqualified`) or archived opportunities.
- If the same customer/address has only a completed, closed, or archived prior project and the incoming scope is distinct, create a separate opportunity.
- If confidence is below the deterministic threshold, create a separate lead and preserve merge evidence through activity/thread/source fields rather than over-linking.

Phase C boundary:
- Phase C may improve extraction quality, relationship suggestions, and future household/project graph confidence.
- Phase C must not be required for P3. With Phase C off, exact contact, exact phone, exact address, active opportunity state, and active project state still drive deterministic matching.
- Phase C must not perform destructive merge, stale/archive/lost automation, or project conversion as part of P3. Those remain later lifecycle phases and operator-controlled flows.

Known P3 schema gaps:
- There is still no durable field-level provenance table for why a thread was linked to an opportunity. Current proof is spread across `opportunity_email_threads`, `activities`, `source_email_id`, and server logs/tests.
- There is no explicit `opportunity_relationship_matches` or merge-candidate table to persist low-confidence duplicate/future-merge suggestions.
- There is no canonical relationship type column for spouse/partner/property-manager/site-super identity unless the contact is represented as a `sub_clients` row.
- There is no structured scope signature column for comparing "same address, new job" versus "same address, same job"; P3 uses conservative deterministic text/address/status gates only.

#### P4 Schema Foundation and Dry-Run Evaluator

As of Lead Lifecycle P4-2, stale/follow-up evaluation has a first-class schema and deterministic dry-run evaluator. P4-2 is still non-destructive: it may create lifecycle proof rows at safe app-code boundaries and may produce read-only dry-run artifacts, but it must not archive opportunities, mark opportunities lost, create provider drafts in production, or send email.

P4 schema contract:
- `opportunity_correspondence_events` stores opportunity-level correspondence proof. It links to company, opportunity, optional activity, optional email connection, provider thread id, optional provider message id, direction (`inbound`/`outbound`), party role (`customer`, `ops`, `internal`, `provider`, `system`, `marketing`, `unknown`), `is_meaningful`, `noise_reason`, occurrence time, optional linked contact reference, source boundary, subject, sender, recipients, and CCs. A partial unique index protects provider message id duplication per company/connection.
- `opportunity_follow_up_drafts` stores auditable lifecycle drafts. It links to company, opportunity, optional connection/thread, optional source correspondence event, origin (`operator`, `template_follow_up`, `phase_c`, `system_handoff`), sequence number, subject, original generated body, current body, final sent body, status (`drafted`, `sent`, `discarded`, `superseded`, `archived`), optional provider draft id, optional `ai_draft_history` id, editors, and lifecycle timestamps. At most one open `template_follow_up` draft exists per opportunity.
- `opportunity_lifecycle_state` stores the opportunity's P4 stale state: last meaningful event/time/direction, unanswered follow-up count, second follow-up sent time, operator follow-up miss time, stale status, protected-until timestamp, and update time.
- `opportunity_lifecycle_action_audit` stores guarded P4 action attempts/results once the P4-12 additive migration is applied. It records company, opportunity, action, approved action key, execution mode, status, guard reason, server-computed before/after values, decision reason/evidence, approval metadata, run id, error code/message provenance, runner, and creation time. A partial unique index prevents duplicate applied rows for the same approved company/opportunity/action/key.
- `lead_lifecycle_settings` stores company-level cadence and template settings. Defaults are 7 days to draft a follow-up after OPS outbound, 7 days to archive after the second unanswered follow-up, 14 days to archive when no meaningful correspondence exists, 30 days to mark beyond-qualified operator no-response as lost, and default template body `Hey there {{first_name}}, just following up on this as I didn't see anything back from you.`

P4 deterministic classifier rules:
- Customer inbound counts as meaningful only when the sender or parsed contact-form submitter is a real external customer/contact. Parsed submitter identity wins over platform sender identity.
- OPS outbound counts as meaningful only when a real OPS account/connection sends to an external customer/contact.
- Provider/platform senders, automated bounces, internal-only/system messages, duplicate provider message ids, and marketing/promotional messages are not meaningful. They are retained as proof rows with `is_meaningful=false` and a `noise_reason`.
- Blank provider thread ids are never meaningful. Provider-backed lifecycle writes still follow the P1 provider-id guardrails before creating P4 events.
- Platform senders such as website form notification mailboxes are never treated as the customer. They can support source/provenance only.

P4 evaluator dry-run behavior:
- Input is an opportunity, optional `opportunity_lifecycle_state`, meaningful correspondence events, settings, and evaluator clock.
- Output is one dry-run decision: `create_follow_up_draft`, `archive_after_two_unanswered_followups`, `archive_no_meaningful_correspondence`, `operator_follow_up_miss`, `move_to_lost_operator_no_response`, `reactivate_on_related_inbound`, or `no_action`.
- Won, lost, discarded, deleted, converted/project-linked, archived, and future terminal/protected opportunities are ignored for stale monitoring. `reactivate_on_related_inbound` is an event-triggered decision only when a new related meaningful inbound arrives; P4 sweeps do not keep monitoring archived opportunities.
- Last meaningful OPS outbound past the configured threshold returns `create_follow_up_draft`. P4-2 does not create or send that draft in production.
- Two tracked unanswered OPS follow-ups past the configured second-follow-up archive threshold returns `archive_after_two_unanswered_followups`. P4-2 does not execute archive.
- No meaningful correspondence past the configured no-correspondence threshold returns `archive_no_meaningful_correspondence`. P4-2 does not execute archive.
- Last meaningful inbound with no later OPS reply returns `operator_follow_up_miss`; if it is beyond the lost threshold and the opportunity is beyond qualified (`quoting`, `quoted`, `follow_up`, `negotiation`), it returns `move_to_lost_operator_no_response`. P4-2 does not execute lost mutations.

Safe P4-2 write boundaries:
- Inbound/outbound sync may create `opportunity_correspondence_events` after provider thread/message ids validate, P3 relationship matching selects the opportunity, and P2 fill-only enrichment remains intact. When the event is meaningful, P4-2 app code may also upsert `opportunity_lifecycle_state` for that opportunity: last meaningful event id/time/direction, clear stale status fields, and reset unanswered follow-up counters for meaningful inbound.
- Email send may create an outbound meaningful correspondence event after the provider returns valid thread/message ids, then upsert `opportunity_lifecycle_state` with the outbound meaningful event when it is the newest meaningful correspondence.
- Import/historical import may create correspondence events only where provider ids satisfy the explicit import boundary. Invalid provider ids create no P4 event and no lifecycle-state upsert.
- P4-2 dry-run scripts are read-only against Supabase and write only a markdown artifact under `docs/data-cleanup/`.
- P4-2 does not execute archive, lost, or reactivation mutations. Those action-execution paths remain P4-3+ only, behind guarded write paths, idempotency, audit, and operator-visible review.

P4-8 non-destructive action-execution boundary:
- P4-8 may execute only non-destructive decisions from the P4 evaluator. `create_follow_up_draft` creates a local `opportunity_follow_up_drafts` row with `origin = 'template_follow_up'`, `status = 'drafted'`, the next template sequence number from stored lifecycle state/prior sent template follow-ups, rendered template subject/body, the triggering `source_event_id`, and optional connection/provider thread context. It does not create a Gmail/M365 provider draft and does not auto-send.
- Template follow-up execution is idempotent. The open-template unique contract remains one open `template_follow_up` draft per opportunity. Existing operator, provider-backed, Phase C, or system-handoff drafts are not overwritten, discarded, or reused by P4-8.
- `operator_follow_up_miss` creates a persistent operator rail notification through the existing notifications table. OPS currently has no dedicated lead-lifecycle notification type, so P4-8 uses the compatible `leads_waiting` type and deterministic title/action URL dedupe. Notifications link to the inbox thread when a provider thread id exists, otherwise to the pipeline.
- Non-destructive actions update `opportunity_lifecycle_state` without pretending an email was sent. Template draft creation uses the live constraint-compatible stale status `follow_up_draft_due` and must persist required lifecycle state before inserting the local draft row, so a failed state update cannot leave a new template draft without the required state. Operator misses set `operator_follow_up_miss_at` and stale status to `operator_follow_up_miss`. Neither path mutates canonical `opportunities.stage`, `archived_at`, `lost_reason`, `project_id`, or project links.
- Meaningful inbound handling clears stale status fields, resets unanswered follow-up counters, clears operator miss state, and supersedes stale open `template_follow_up` draft rows for that opportunity. Manual/operator, provider, Phase C, and system handoff drafts stay intact.
- P4-8 dry-run/apply tooling defaults to dry-run and writes only a markdown artifact unless an explicit non-destructive apply flag is passed after approval. The artifact must count candidates, drafts to create, notifications to create, lifecycle states to update, drafts to supersede, already-existing skips, and destructive-action skips.
- Archive, lost, and reactivation decisions remain skipped in P4-8. Archive/lost execution and related-inbound unarchive/reactivation remain P4-10+ product work behind separate approval, guarded write paths, idempotency, audit, and focused tests.
- P4-8 must not auto-send email, create provider drafts, depend on Phase C, or start P5/P6.

P4-12 guarded destructive action-execution boundary:
- P4-12 may execute only the remaining reviewed P4 evaluator decisions: `archive_after_two_unanswered_followups`, `archive_no_meaningful_correspondence`, `move_to_lost_operator_no_response`, and `reactivate_on_related_inbound`. Production execution is blocked unless a dry-run artifact has been reviewed and an exact opportunity/action approval list is supplied to apply mode.
- The production script remains dry-run by default and writes only a markdown artifact under `/Users/jacksonsweet/Projects/OPS/docs/data-cleanup/`. Apply mode requires `--apply-guarded-p4-actions --approved-actions-file <json>` and refuses to run until `opportunity_lifecycle_action_audit` exists in the target schema.
- Archive execution is reversible and may set only `opportunities.archived_at`. It must not manually set `updated_at` and must not change stage, lost fields, project links, correspondence rows, drafts, notifications, or provider state.
- Operator no-response lost execution is allowed only for beyond-qualified stages (`quoting`, `quoted`, `follow_up`, `negotiation`). It must skip `new_lead`, `qualifying`, won, lost, discarded, deleted, converted, and project-linked opportunities. The only allowed opportunity changes are `stage = 'lost'`, `lost_reason = 'operator_no_response'`, `lost_notes`, and `actual_close_date`; it must not manually set `updated_at`.
- Related-inbound reactivation may clear only `opportunities.archived_at`. It must skip won, lost, discarded, deleted, converted/project-linked opportunities and any archived opportunity whose latest meaningful inbound is not from a related/high-confidence related contact. It does not reopen lost/discarded records and does not change stage.
- Guarded execution is idempotent. Already archived rows, already applied approval keys, disallowed stages, deleted rows, converted/project-linked rows, missing related inbound, and current-evaluator mismatches are skipped and reported. Repeated apply must not duplicate local drafts, notifications, provider drafts, sent email, or opportunity state transitions.
- Each applied archive/lost/reactivation runs through `public.execute_opportunity_lifecycle_guarded_action(...)`, which writes the audit row and the opportunity mutation in one database transaction. This RPC is a service-role/server-only boundary for trusted OPS server code; ordinary authenticated users must not receive `EXECUTE` and must not call it directly through PostgREST. RLS/company checks remain defense in depth, not the approval gate.
- The guarded RPC computes audit `before_values` from the locked live `opportunities` row and computes audit `after_values` from the exact mutation variables it applies. Client payloads may supply expected before/after values for optimistic verification only; they are not the stored audit source of truth. If expected guard/audit values disagree with the live row or the server-computed mutation, the RPC records a guarded skip such as `snapshot_mismatch` and does not report archive/lost/reactivation as applied. The exact audited mutation fields are `archived_at` for archive, `stage`/`lost_reason`/`lost_notes`/`actual_close_date` for lost, and `archived_at` for reactivation. The existing `opportunity_lifecycle_state` table is not sufficient for this audit because it has stale status fields but no action key, mode, guard reason, before/after snapshot, provenance/error fields, or applied-result record.
- P4-12 does not send email, does not create provider drafts, does not call provider send APIs, does not mutate historical data outside the exact approved action set, and does not start P5/P6.

P4-22 legacy correspondence proof boundary:
- Destructive dry-runs against historical opportunities must not treat an empty `opportunity_correspondence_events` table as proof of no meaningful correspondence. The P4 proof tables were introduced after many legacy opportunities already had real customer replies, form submissions, RFQs, site visits, calls, outbound quotes, and follow-ups recorded elsewhere.
- Before any destructive dry-run is eligible for review, legacy opportunities require either a legacy correspondence proof backfill dry-run or a deterministic legacy-evidence adapter. Valid sources are existing `activities`, `email_threads`, `opportunity_email_threads`, provider thread/message ids, `email_connections` sender context, and deterministic opportunity source/title fallback when no activity row exists. The adapter must remain opportunity-scoped; it must not reuse evidence across P3 relationship boundaries or reinterpret a provider thread linked to a different opportunity.
- Backfill planning must be idempotent by provider message id when available, by activity id for legacy activity evidence, and by opportunity id for deterministic opportunity-source fallback. It must not create duplicate meaningful events, and provider-backed rows with blank or invalid provider thread ids remain blocked by the P1 provider-id guardrails. Non-provider legacy evidence may be represented with an explicit legacy source boundary, but it must be labeled as activity/opportunity-scoped rather than provider-backed.
- Provider-backed legacy activity is not sufficient by itself when a linked `email_threads` row has usable latest-message truth. Activity rows without `provider_message_id` are treated as thread-level legacy summaries and must reconcile to the linked thread's latest direction, timestamp, sender/recipient, and party classification. Message-specific activity evidence may coexist with a later linked thread summary so stale/lost decisions use the latest reconciled opportunity truth instead of activity `direction` alone.
- Meaningful legacy inclusion is limited to deterministic customer form submissions, real customer replies, OPS outbound quote/follow-up messages, calls, RFQs, site visits, and meetings. Provider/platform noise, internal/system-only messages, automated bounces, marketing/promotional mail, duplicate provider messages, platform sender identity masquerading as a customer, and ambiguous evidence must be skipped with a reason.
- Forwarded contact-form threads are meaningful only when the adapter can prove a non-internal submitter from parsed form content or an external participant on the linked thread. Internal-only forwarded form shells without submitter or external-contact proof remain ambiguous and must be skipped.
- Guarded archive/lost dry-runs must not promote an opportunity to mutation output when the same opportunity has unresolved legacy evidence (`ambiguous_legacy_evidence`, `relationship_mismatch`, `missing_provider_id`, or `missing_created_at`). Those rows prove the evaluator does not have clean correspondence truth yet, so they must appear in a blocked/skipped section rather than in the approval JSON.
- A legacy backfill dry-run must render the exact `opportunity_correspondence_events` rows that would be inserted and the exact `opportunity_lifecycle_state` rows that would be upserted, including source boundary, confidence, reason, provider ids or legacy synthetic boundary, activity id, opportunity id, direction, party role, meaningful flag, and occurrence time. It must also prove that `opportunities`, P4 proof/state/settings tables, audit tables, guarded RPCs, drafts, notifications, provider drafts, and email sending were not mutated.
- A guarded-action dry-run artifact must render exact projected audit rows, not only `would_record` markers or an approval JSON block. Each projected row must include company id, opportunity id, action, approved action key placeholder, execution mode, status, guard reason, before values, after values, decision reason/evidence, approval metadata placeholders, run id, error fields, runner, and a clear `dry_run_projection_not_approved` marker. Dry-run projected audit rows are not approval and must not imply that apply mode is authorized.

#### Phase C Off vs Phase C On

| Capability | Phase C Off | Phase C On |
|---|---|---|
| Email ingestion, provider thread/message proof, activity logging | Required | Required |
| Conservative client/opportunity matching | Required | Improved by AI context |
| Opportunity field enrichment | Deterministic only when safe | Better freeform extraction and confidence |
| Stage movement | Deterministic, conservative | Context-aware suggestions or high-confidence actions |
| Stale detection | Opportunity-level, deterministic | Better understanding of related contacts and context |
| Follow-up drafting | Template-based from settings | Can also create smarter contextual drafts |
| New-thread relationship matching | Exact contact/phone/address/project-state gates | Better household/project graph suggestions, still non-destructive |
| Merge decisions | Manual operator action | AI may suggest, never destructive by itself |
| Project conversion | Manual, or high-confidence deterministic rule only | Better won-confidence detection and handoff drafting |

Phase C should never be the hidden storage location for canonical lead data. If Phase C extracts a durable fact, that fact belongs on the appropriate client/opportunity/activity/thread record with provenance.

#### Lifecycle States, Visibility, and Outcomes

Visibility is separate from business outcome:

| Concept | Meaning | Reporting impact |
|---|---|---|
| `active` | Visible in active pipeline | Counts as live pipeline |
| `archived` | Hidden from active pipeline, reversible | Does not count as won/lost |
| `won` | Valid opportunity became work | Counts as conversion |
| `lost` | Valid, qualified opportunity did not close | Counts against close rate |
| `disqualified` | Real inquiry, but not a fit | Counts toward lead-quality/ad-targeting analysis, not close-rate loss |
| `discarded` | Should not have been a lead: spam, vendor, applicant, internal, platform noise, test data | Counts toward system/data-quality analysis, not sales performance |
| `merged` | Duplicate/fork created in error and absorbed into another opportunity | Losing record is removed from normal views after its data is integrated |
| `converted_to_project` | Won opportunity has an operational project link | Project inherits sales trail |

Archive means "remove from active pipeline." It does not delete the opportunity, email threads, activities, or source proof. A matched inbound from any known or newly matched related contact should unarchive/reactivate the opportunity.

Merge is different from archive. Merge means one opportunity was created in error as a fork. The merge operation must move useful data, activities, email threads, contacts/sub-contacts, field provenance, estimate/project links, and source message IDs into the winning opportunity, then remove the losing opportunity from normal data views. If hard delete is unsafe for audit or FK constraints, product behavior should still be "deleted after merge," not "archived as a normal stale/lost lead."

#### Stale Lead and Follow-Up Intent

Staleness belongs to the opportunity, not an individual email thread.

Rules:
- Won, lost, converted-to-project, and already archived opportunities are not monitored for stale-lead automation.
- Meaningful correspondence excludes provider noise, automated bounces, marketing, internal-only chatter, duplicate sync rows, and system notifications. In normal client threads, actual client emails should generally count.
- If OPS sent the last meaningful message and the configured threshold passes, mark the opportunity as needing follow-up and create a template follow-up draft.
- Follow-up drafts are lifecycle automation, not Phase C. They are generated from configurable settings templates. Default copy may be: `Hey there {{first_name}}, just following up on this as I didn't see anything back from you.`
- After two OPS follow-ups with no meaningful customer response, archive the opportunity 7 calendar days after the second follow-up.
- If there has been no meaningful correspondence for 14 calendar days, archive the opportunity unless it has a terminal or protected state.
- If the last meaningful email was inbound and unreplied, do not treat it as a cold customer. If it is under 30 calendar days old, surface it as an operator follow-up miss or archive only as a visibility action. If it is over 30 calendar days old and the lead had moved beyond qualified, move it to `lost` with a reason such as `operator_no_response`.
- If a matched inbound arrives from any linked or high-confidence related contact, reset stale timers, unarchive if needed, enrich the opportunity, and re-evaluate stage.

Settings should eventually expose follow-up cadence, follow-up templates, stale thresholds, and any manual keep-active or automation-pause control. If a keep-active/automation-pause control does not exist yet, it is a product gap, not a reason to invent hidden behavior.

#### Drafting and Learning Intent

Drafts can come from multiple origins:

| Origin | Purpose |
|---|---|
| `operator` | Human-created draft |
| `template_follow_up` | Settings-driven stale-lead follow-up |
| `phase_c` | AI/contextual draft |
| `system_handoff` | Future project or lifecycle handoff draft |

Multiple draft origins may coexist for the same opportunity/thread. A manual draft does not block Phase C from creating a Phase C draft, and a template follow-up does not overwrite a manual draft. The operator chooses which draft to edit/send.

Every generated draft must retain:
- original generated body and subject
- final sent body and subject
- origin (`operator`, `template_follow_up`, `phase_c`, etc.)
- linked opportunity id, provider thread id, and source message id where applicable
- generated_at, edited_at, sent_at, discarded_at
- user/editor id
- edit diff or equivalent edit-distance representation
- final disposition: sent, discarded, replaced, expired

Phase C learns from the delta between generated drafts and the sent version. It should learn from sent emails, not abandoned drafts. Template follow-up edits are also learning signal because they show how the operator personalizes lifecycle communication.

#### New Thread, Same Customer, Different Job

Matching must account for repeat customers and households. The same client or same address does not automatically mean the same opportunity.

When a new thread or new contact appears, matching should consider:
- exact known client/sub-contact/participant email
- phone number
- shared address/location
- spouse/partner/project-manager relationship
- quoted prior thread content
- subject/body scope similarity
- timing/recency
- existing opportunity and project state

Guidance:
- If an existing opportunity at the same address is active, RFQ, estimating, quoted, follow-up, or negotiation, the new thread is likely the same job.
- If an existing project at the same address is active/in progress, the new thread is likely project communication or same-job context.
- If the prior project is completed/closed and the scope is distinct, create a new opportunity.
- If confidence is not high, create a separate lead and provide a merge path rather than over-linking.

#### Automation Boundary

| Action | By deterministic algorithm | Phase C-assisted | Do not automate blindly |
|---|---|---|---|
| Deduplicate exact provider message IDs | Yes | Not needed | - |
| Link a message on an already-linked provider thread | Yes | Not needed | - |
| Update correspondence counts from linked activities | Yes | Not needed | - |
| Fill blank fields from explicit contact-form values | Yes | Can improve extraction | Do not overwrite operator truth |
| Generate follow-up drafts from templates | Yes | Can create an alternate smarter draft | Do not auto-send unless separately enabled |
| Reset stale timer on matched inbound | Yes | Can improve matching | Do not reset from provider noise |
| Link a new thread to an opportunity | Only with strict high-confidence gates | Yes, improves confidence | Do not link from weak evidence |
| Determine same customer/new job vs same job | Conservative only | Yes, materially useful | Do not collapse repeat jobs into one opportunity |
| Move to lost for operator no-response after 30+ days beyond qualified | Yes, if state is clear | Can improve classification | Do not mark unqualified noise as lost |
| Archive stale opportunities | Yes, if opportunity-level stale rules pass | Can improve confidence | Do not archive terminal/protected opportunities |
| Merge opportunities | No | Suggest only | Destructive, requires operator confirmation |
| Delete losing fork after merge | No | Not needed | Only after confirmed merge and data migration |
| Auto-convert to project | Only on explicit high-confidence acceptance and configured conversion path | Can improve won confidence | Do not convert vague language |
| Treat platform sender as customer | No | No | Store as source metadata only |

#### Project Conversion Intent

When an opportunity converts to a project, the project must inherit as much sales context as possible. The conversion contract should be maintained against the live `opportunities` and `projects` schemas and should carry over at least:
- client and sub-contact graph
- address/location
- scope/description
- estimated value and quote/estimate context
- source/platform metadata
- linked email threads
- activities and source message IDs
- attachments/photos and estimate files where applicable
- stage/history and field provenance

Project conversion must not sever the sales trail. The project should link back to the opportunity, and the opportunity should link forward to the project.

### Provider Support

| Provider | Auth | Scopes | Incremental Sync | Push Notifications |
|----------|------|--------|-------------------|--------------------|
| Gmail | Google OAuth 2.0 | `gmail.readonly`, `gmail.modify`, `gmail.labels` | History API (`startHistoryId`) | Google Cloud Pub/Sub (`users.watch()`) |
| Microsoft 365 | Microsoft Identity Platform (MSAL) | `Mail.Read`, `Mail.ReadWrite` | Delta queries (`/me/messages/delta`) | Graph Change Notifications (`POST /subscriptions`) |

A single company can connect both providers (e.g., owner uses Gmail, office manager uses M365). Each connection is a separate `email_connections` row with its own sync profile, webhook subscription, and sync token. Client matching and duplicate detection operate across all connections for a company.

### OAuth Flow

```
Settings → Integrations → Email
  ├─ Connect Gmail → Google OAuth → email_connections (provider: gmail)
  └─ Connect Microsoft 365 → MSAL OAuth → email_connections (provider: microsoft365)
```

### Provider Abstraction Layer

All email operations go through a shared `EmailProvider` interface. Each provider (Gmail, M365) implements the interface, translating to provider-specific APIs internally.

```typescript
interface EmailProvider {
  readonly providerType: 'gmail' | 'microsoft365'

  // Auth
  connect(companyId: string): Promise<AuthResult>
  refreshToken(connectionId: string): Promise<void>

  // Incremental sync (Gmail: historyId, M365: deltaLink)
  fetchNewEmailsSince(syncToken: string): Promise<{ emails: Email[]; nextSyncToken: string }>
  fetchSentEmailsSince(syncToken: string): Promise<{ emails: Email[]; nextSyncToken: string }>

  // Search (for wizard Step 2 sent mail analysis)
  searchEmails(query: string, options?: { maxResults?: number; after?: Date }): Promise<Email[]>

  // Thread operations
  fetchThread(threadId: string): Promise<Email[]>

  // Labels/categories
  createLabel(name: string): Promise<string>
  applyLabel(threadId: string, labelId: string): Promise<void>
  removeLabel(threadId: string, labelId: string): Promise<void>
  listLabels(): Promise<Label[]>

  // Drafts (for AI auto-draft)
  createDraft(to: string, subject: string, body: string, threadId?: string): Promise<string>

  // Push notifications
  setupWebhook(webhookUrl: string): Promise<WebhookSubscription>
  renewWebhook(subscriptionId: string): Promise<void>
  validateWebhookRequest(request: Request): Promise<boolean>

  // Profile
  getProfile(): Promise<{ email: string; name: string }>
}
```

The `syncToken` parameter abstracts over Gmail's `historyId` and M365's `deltaLink` — each provider translates internally.

**Key provider differences:**

| Concept | Gmail | Microsoft 365 |
|---------|-------|---------------|
| Thread identifier | `threadId` | `conversationId` |
| Tagging mechanism | Labels (multiple per email) | Categories (color-coded tags) |
| Push notification renewal | Watch expires every 7 days, renew daily | Subscription expires every 3 days, renew every 2 days |
| Email body format | base64-encoded parts | `body.content` directly as HTML/text |
| "OPS Pipeline" tag | Gmail label | M365 category |

### Import Your Pipeline Wizard

A 5-step wizard replaces the previous 6-step filter-based wizard. Located in `src/components/settings/email-setup-wizard.tsx`.

**Steps:**

1. **Connect** — Two buttons: "Connect Gmail" / "Connect Microsoft 365". OAuth flow, auto-proceed on success.

2. **Analyze Your Inbox** — Automatic analysis (~30-60 seconds) with live progress indicator. Three parallel operations:
   - **Sent mail scan** — analyzes most common outbound subjects to non-company addresses to detect estimate/quote patterns
   - **Platform detection** — identifies known form senders (Wix, WordPress, Squarespace, Jotform, HubSpot) and bid platforms (Procore, SmartBidNet, BuilderTrend) in inbox
   - **AI classification** — classifies remaining personal emails not matching any pattern as lead/not-lead
   - Only analyzes threads with activity within last 3 months
   - Uses the `email_scan_jobs` table (renamed from `gmail_scan_jobs`) for async job tracking with progress
   - Error handling: partial results accepted if one operation fails; hard timeout at 120 seconds; resume from saved progress if browser closed mid-scan

3. **Confirm Your Sources** — Displays discovered sources grouped by type:
   - Detected estimate subject pattern with thread count (toggle on/off, editable)
   - Website form submissions with platform name and count (toggle on/off)
   - Bid invitations with platform name and count (toggle on/off)
   - Additional AI-identified inquiries (expandable for individual review)
   - Manual add for additional patterns/sources

4. **Review & Import** — All detected leads with AI-determined pipeline stage:
   - Grouped by stage: New Lead, Qualifying, Quoting, Quoted, Follow-Up, Negotiation, Won, Lost, Discarded
   - Each lead shows: client name, email, last message date, correspondence count, detected stage
   - Duplicates pre-grouped with merge prompt
   - User can adjust stage, remove false positives, merge duplicates
   - "Import All" button with count

5. **Activate Sync** — Confirms "OPS Pipeline" label/category applied to imported leads:
   - Sync frequency selector: 15 min / 1 hour / 2 hours / 24 hours / Manual only
   - Note: real-time via push notifications, scheduled sync as safety net
   - Summary card: leads imported, sync frequency, next sync time

**Wizard state is persisted** on the `email_connections` record via the `sync_filters` JSONB column (mapped as `syncFilters` in TypeScript) and `status` column (`setup_incomplete` during wizard). Note: The DB column retains the name `sync_filters` for backward compatibility — the TypeScript type is `SyncProfile`.

### Pattern Detection Engine

Runs during wizard Step 2. Produces the **sync profile** — the ruleset used by every ongoing sync cycle. Stored as JSONB on the `email_connections.sync_filters` column (TypeScript field: `syncFilters: SyncProfile`).

**2A: Sent Mail Analysis**
1. Fetch sent messages (last 3 months, skip internal company domain addresses)
2. Group by subject line (normalized — strip "Re:", "Fwd:", whitespace)
3. Rank by frequency — the most common subject sent to unique external recipients is the estimate pattern
4. Present to user for confirmation in Step 3
5. User can edit the pattern or add additional patterns (some businesses have multiple — residential vs commercial)

**2B: Known Platform Detection**

Registry of known form notification senders and bid platforms:

| Category | Detected By | Examples |
|----------|-------------|---------|
| Website forms | Sender domain | `notifications@wix-forms.com`, `*@wordpress.com`, `*@squarespace.com`, `*@jotform.com`, `*@typeform.com` |
| Bid platforms | Sender domain | `*@smartbidnet.com`, `*@procore.com`, `*@buildertrend.com`, `*@plangrid.com`, `*@buildingconnected.com` |
| CRM/lead gen | Sender domain | `*@hubspot.com`, `*@salesforce.com`, `*@thumbtack.com`, `*@homeadvisor.com`, `*@houzz.com` |
| Google reviews | Sender address | `businessprofile-noreply@google.com` |
| Forwarded forms | Pattern | Subject contains "got a new submission", "new form entry", "new contact form" + forwarded by known team member |

**2C: Forwarded Lead Detection**

Many trades businesses have an office manager or partner who forwards leads. Detected via: emails where sender is from user's own company domain, subject contains forwarding indicators ("Fwd:", "got a new submission"), body contains a nested forwarded message from a form platform.

**2D: Business Domain Identification**

From sent mail analysis, identify user's company domain(s): domains the user sends from, domains appearing frequently in CC/To on business threads. User confirms in Step 3. Used to exclude internal correspondence and identify the "forwarder" pattern.

**2E: Sync Profile Output**

```json
{
  "estimateSubjectPatterns": ["Canpro Deck and Rail Estimate"],
  "companyDomains": ["canprodeckandrail.com"],
  "teamForwarders": ["jared@canprodeckandrail.com", "victoria@canprodeckandrail.com"],
  "knownPlatformSenders": ["notifications@wix-forms.com", "notifications@com2.smartbidnet.com"],
  "formSubjectPatterns": ["got a new submission", "new form entry"],
  "userEmailAddresses": ["canprojack@gmail.com"],
  "aiClassificationThreshold": 0.7
}
```

`syncIntervalMinutes`, `aiReviewEnabled`, `aiMemoryEnabled`, `lastSyncHistoryId` are stored as top-level columns on `email_connections`, not in the sync profile JSONB. The sync profile contains only pattern/source detection rules. The `aiClassificationThreshold` is configurable per connection (default 0.7).

### AI Classification System

Two modes: **Initial Scan** (during wizard) and **Ongoing Review** (feature-gated via `ai_email_review`).

**3A: Initial Scan — Bulk Classification**

After pattern detection, remaining unmatched emails in `CATEGORY_PERSONAL` go to AI. Skip `CATEGORY_PROMOTIONS`, `CATEGORY_UPDATES`, `CATEGORY_SOCIAL`, `CATEGORY_FORUMS` entirely.

AI validates ALL candidates — even pattern-matched leads go through AI confirmation to:
- Confirm it's actually a lead
- Extract structured data: client name, phone, project description, estimated scope
- Assign pipeline stage
- Detect duplicates across threads

**Output per lead (~50 tokens):**

```json
{
  "id": "abc123",
  "v": "lead",
  "c": 0.95,
  "stage": "quoted",
  "val": 4500,
  "client": {
    "name": "John Knechtel",
    "email": "knechtel.john@gmail.com",
    "phone": null,
    "desc": "Deck railing replacement, 2 decks, glass and picket options"
  },
  "dupes": ["def456", "ghi789"]
}
```

- `v`: verdict — `"lead"`, `"biz"` (subtrade/vendor), `"skip"` (noise)
- `c`: confidence 0-1
- `dupes`: other email IDs AI believes belong to same client/project
- Emails classified as `"lead"` with confidence >= 0.7 imported. Below 0.7 queued for user review in Step 4.

**3B: Thread Analysis — Stage Placement**

For every confirmed lead thread with activity within 3 months, full thread content sent to AI for accurate stage placement. Batching: 5-10 threads per API call to amortize system prompt cost.

**3C: Ongoing AI Review (Feature-Gated)**

When `ai_email_review` is enabled (requires both product-level feature flag AND admin override), every sync cycle includes:

1. **New email classification** — unmatched emails go through AI classification
2. **Stage re-evaluation** — for active leads with new emails, AI reviews thread context and determines stage advancement
3. **Win/loss detection** — AI flags threads where client appears to have confirmed or declined

**3D: Terminal Stage Detection Rules**

AI never auto-advances to `won` or `lost`. Instead:

- Win language detected ("let's go ahead", "we'd like to proceed") → notification: "{Client} may have accepted your estimate. [Review → Won?]"
- Loss language detected ("went with another company", "too expensive") → notification: "{Client} may have declined. [Review → Lost?]"

User clicks through to existing Won/Lost confirmation dialogs.

### 5-Tier Client Matching

**Service:** `src/lib/api/services/email-matching-service.ts`

When emails are imported or synced, each is matched against existing clients via a 5-tier cascade:

| Tier | Strategy | Confidence | Auto-link? |
|------|----------|------------|------------|
| 1 | Exact email match (client or sub-client email) | `exact` | Yes |
| 2 | Domain match (non-public domain, single client) | `domain` | Yes — add as sub-contact |
| 2b | Domain match (multiple clients share domain) | `domain` | No — `needsReview: true` |
| 3 | Name match (AI-extracted name matches existing client last name) | `name` | No — `needsReview: true` |
| 4 | Thread CC association (email CC'd on thread linked to existing client) | `thread` | Yes — add as sub-contact |
| 5 | AI duplicate detection (feature-gated: signatures, phone, addresses in body) | `ai` | No — `needsReview: true` |

**Resolution rules:**
- Exact email match → log activity on existing client
- Domain match (single) → create sub-contact, log activity
- Domain match (multiple) → queue for user review
- Name match → queue for user review
- Thread CC association → create sub-contact, log activity
- AI duplicate detection → queue for user review
- No match at any tier → create new client + opportunity

**Public domains** (gmail.com, yahoo.com, outlook.com, shaw.ca, telus.net, icloud.com, protonmail.com, live.com, comcast.net, att.net, verizon.net, msn.com, me.com, mac.com, ymail.com, mail.com, zoho.com, gmx.com, inbox.com, etc.) are excluded from domain matching. Defined in `PUBLIC_EMAIL_DOMAINS` in `src/lib/types/pipeline.ts`.

### Sync Engine

**4A: Sync Triggers (all four built day one)**

| Trigger | Implementation | Latency |
|---------|---------------|---------|
| **Scheduled** | Cron checks interval (15min/1hr/2hr/24hr) | Up to interval |
| **Manual** | "Sync Now" button | Immediate |
| **Gmail Push** | Google Cloud Pub/Sub → `users.watch()` → webhook endpoint | ~seconds |
| **M365 Push** | Microsoft Graph Change Notifications → subscription on `/me/messages` → webhook endpoint | ~seconds |

**4B: Webhook Architecture**

**Gmail:**
1. On connection setup, call `gmail.users.watch()` with Pub/Sub topic
2. Google publishes to Pub/Sub topic on inbox/sent changes
3. Pub/Sub pushes to: `POST /api/integrations/email/webhook/gmail`
4. Validate, deduplicate, queue sync job, return 200 immediately
5. Watch expires every 7 days — cron renews daily

**Microsoft 365:**
1. On connection setup, create subscription: `POST /subscriptions` on `me/messages`
2. M365 sends change notifications to: `POST /api/integrations/email/webhook/microsoft365`
3. Validate subscription (M365 requires validation handshake), queue sync job, return 200
4. Subscription expires every 3 days — cron renews every 2 days

**Shared webhook endpoint logic:**
1. Validate request authenticity (Pub/Sub signature / M365 validation token)
2. Extract connection ID
3. Debounce — if sync ran for this connection in last 30 seconds, skip
4. Queue sync job (don't run inline)
5. Return 200 immediately

**4C: Sync Cycle — Full Flow**

```
1. Fetch new emails since lastSyncHistoryId
   ├── Inbox (inbound)
   └── Sent (outbound)

2. Pattern matching (fast, free)
   ├── Sender matches known platform? → candidate
   ├── Sender matches team forwarder? → candidate
   ├── Subject matches form submission pattern? → candidate
   ├── Reply in existing OPS lead thread? → auto-link
   └── User sent to new external address with estimate pattern? → new lead

3. Sent folder safety net
   ├── User replied to address not in OPS? → new lead
   ├── User replied in thread already in OPS? → update activity
   └── User sent to known client? → log outbound activity

4. Thread inheritance
   └── Any email in thread linked to OPS client → auto-link, log activity

5. AI classification (feature-gated — skip if disabled)
   └── Remaining unmatched personal emails → AI classify

6. Stage evaluation
   ├── Free tier: correspondence count rules
   │   ├── 0 outbound → new_lead
   │   ├── 1 outbound → qualifying
   │   ├── 2+ exchanges → quoting
   │   └── Stale threshold exceeded → follow_up
   └── AI tier (feature-gated): AI reviews thread context

7. Client matching & sub-contact resolution (5-tier cascade)

8. Apply labels
   └── New lead/activity → apply "OPS Pipeline" label/category

9. Create/update OPS records
   ├── New lead → create Client + Opportunity + Activity
   ├── Existing lead, new email → create Activity, update stage
   └── Duplicate detection → flag for user review

10. AI memory update (feature-gated — see AI Memory System)

11. Notifications
    ├── "3 new emails synced — 1 new lead from john@example.com"
    ├── Win/loss flags
    └── Duplicate flags

12. Update lastSyncHistoryId
```

### Smart Pipeline Staging

**5A: Free Tier — Correspondence Count Rules**

| Thread State | Stage | Detection |
|---|---|---|
| Inbound only, 0 outbound | `new_lead` | outbound_count = 0 |
| User sent 1 reply | `qualifying` | outbound_count = 1, total < 4 |
| 2+ outbound, 4+ total messages | `quoting` | outbound_count >= 2, total >= 4 |
| 3+ outbound, 6+ total messages | `quoted` | outbound_count >= 3, total >= 6 |
| Last message outbound, no reply for X days | `follow_up` | last_message_direction = out, age > autoFollowUpDays (applies at any active stage) |
| Client replied after quiet period | `negotiation` | previous stage was follow_up, new inbound arrived |

**Limitation:** Correspondence-count rules cannot reliably distinguish "discussing scope" from "estimate was sent." They place leads in roughly the right area of the pipeline. Users can always drag to correct on the Kanban board. The AI tier handles this accurately by detecting actual pricing in outbound messages.

**5B: AI Tier — Context-Aware Staging (Feature-Gated)**

AI reads thread content and detects:

| Signal | Stage |
|---|---|
| User asked for photos/measurements | `qualifying` |
| User sent pricing/dollar amounts | `quoted` |
| User mentioned promotion/discount | `quoted` |
| Client comparing quotes | `negotiation` |
| Client discussing scheduling/timing | `negotiation` |
| Client accepted | Flag → `won` prompt |
| Client declined | Flag → `lost` prompt |
| Client silent > 30 days, last was outbound | Flag → possible `lost` |

**AI output per thread (~20 tokens):**

```json
{
  "stage": "quoted",
  "c": 0.9,
  "val": 4500,
  "signals": ["pricing_sent", "promo_mentioned"],
  "terminal_flag": null
}
```

**5C: Correspondence Tracking on Opportunity**

Email threads are linked to opportunities via the `opportunity_email_threads` junction table (not a column on opportunities). This enables fast O(1) sync lookup via a unique index on `thread_id`. See `03_DATA_ARCHITECTURE.md` for the full schema.

Additional columns on `opportunities` for correspondence tracking:

```
correspondence_count: INT DEFAULT 0
outbound_count: INT DEFAULT 0
inbound_count: INT DEFAULT 0
last_inbound_at: TIMESTAMPTZ
last_outbound_at: TIMESTAMPTZ
last_message_direction: TEXT ("in" | "out")
ai_stage_confidence: FLOAT
ai_stage_signals: TEXT[]
detected_value: INT
```

### AI Memory System (Feature-Gated)

Hybrid vector (pgvector) + knowledge graph (Postgres) + Mem0 orchestration. Builds a "company brain" that learns the user's business patterns over time. Gated behind the `ai_email_memory` feature flag (requires both product-level flag AND admin override).

**Three Storage Layers:**

| Layer | Purpose | Storage |
|---|---|---|
| `agent_memories` | Facts, preferences, traits extracted from emails | Postgres + pgvector `halfvec(1536)` embeddings |
| `agent_knowledge_graph` | Entity relationships with temporal validity | Postgres relational edges (subject → predicate → object) |
| `agent_writing_profiles` | Communication style per user | Structured Postgres table |

**Memory Dimensions:**

| Dimension | What It Captures | Source |
|---|---|---|
| Communication Style | Tone, formality, greetings, sign-offs, response length | Sent emails |
| Quoting Patterns | Pricing structure, estimate presentation, discount framing | Outbound estimate emails |
| Sales Methodology | Response speed, info requested first, objection handling, follow-up cadence | Full thread analysis |
| Business Knowledge | Services, service area, materials, limitations, promotions, subtrades | All outbound correspondence |
| Client Handling | Price objection responses, lost deal handling, upselling, referrals | Thread outcomes mapped to correspondence |

**Email Sync → Memory Pipeline:**

On every AI-tier sync cycle, for each outbound email:

```
Extract entities → knowledge graph
  ├── People (names, emails, phones)
  ├── Companies
  ├── Services discussed
  ├── Pricing mentioned
  └── Relationships

Extract facts → agent_memories + pgvector
  ├── "User charges $65-85/LF for aluminum picket railing"
  ├── "User cannot do glass on stairs"
  └── "User services Salt Spring Island frequently"

Update writing profile → agent_writing_profiles
  ├── Greeting patterns
  ├── Sign-off patterns
  ├── Tone markers
  └── Response structure

Embed email content → pgvector
  └── Semantic embedding for future retrieval
```

Key principle: don't store emails verbatim. Extract knowledge, embed for semantic search, discard raw text. Memory consolidation runs periodically to merge redundant entries and prune stale facts.

**Memory-Powered Draft Generation:**

When user clicks "Draft Reply" or auto-draft triggers:

1. Semantic search pgvector for past emails to similar clients about similar projects
2. Graph traversal for client's history, related entities, outstanding quotes
3. Retrieve writing profile — tone, greeting, sign-off, response length
4. Retrieve relevant facts — current promotions, pricing, limitations
5. LLM generates draft in user's exact voice with accurate business details

**Confidence & Progressive Unlock:**

| Emails Analyzed | Confidence | Capabilities |
|---|---|---|
| 0-25 | 0.0-0.2 | Learning only |
| 25-100 | 0.2-0.5 | Analytics dashboard ("your avg response time: 2.3 hours") |
| 100-250 | 0.5-0.75 | "Draft Reply" button available |
| 250+ | 0.75-1.0 | Auto-draft to inbox (saved as draft, never sent without user action) |

**Memory Feedback Loop:**

Each correction creates a new `agent_memories` entry with `memory_type = 'correction'` and a reference to the original memory/action being corrected. Mem0's consolidation merges corrections into the base facts over time. User edits to drafts, stage overrides, rejected client matches, and manually created leads all feed back into the memory system.

### Feature Gate Architecture

**Free vs Gated:**

| Feature | Free (All Users) | AI-Powered (Gated) |
|---|---|---|
| Pattern detection & sync profile | Yes | Yes |
| Sent folder safety net | Yes | Yes |
| Thread inheritance | Yes | Yes |
| Label application (mandatory) | Yes | Yes |
| Webhook push sync (Gmail + M365) | Yes | Yes |
| Initial AI classification during wizard | Yes | Yes |
| Initial AI stage placement (one-time) | Yes | Yes |
| Correspondence-count stage rules | Yes | Yes |
| Stale/follow-up time-based rules | Yes | Yes |
| Ongoing AI classification per sync | No | `ai_email_review` |
| Ongoing AI stage evaluation per sync | No | `ai_email_review` |
| Win/loss detection notifications | No | `ai_email_review` |
| AI duplicate detection | No | `ai_email_review` |
| Memory accumulation | No | `ai_email_memory` |
| Draft reply suggestions (confidence >= 0.5) | No | `ai_email_memory` |
| Auto-draft to inbox (confidence >= 0.75) | No | `ai_email_memory` |

The `ai_email_review` and `ai_email_memory` flags integrate into the existing feature flag system (`feature-flag-definitions.ts`, `feature-flags-store.ts`) but also require per-company OPS admin override via the `admin_feature_overrides` table. See `07_SPECIALIZED_FEATURES.md` §17 for full feature gate documentation.

**Code-level gate check:**

```typescript
async function isAIFeatureEnabled(
  companyId: string,
  feature: 'ai_email_review' | 'ai_email_memory'
): Promise<boolean> {
  const productEnabled = await canAccessFeature(feature)  // existing feature flag system
  const adminEnabled = await checkAdminOverride(companyId, feature)  // admin_feature_overrides table
  return productEnabled && adminEnabled
}
```

### Permissions

New permission module for the email integration, registered in the existing permission system (`permissions.ts`):

| Permission | Scopes | Description |
|---|---|---|
| `email.connect` | `["all"]` | Connect/disconnect email accounts |
| `email.view` | `["all", "own"]` | View imported leads and email activities |
| `email.manage` | `["all"]` | Run wizard, edit sync profile, manual sync |
| `email.configure_ai` | `["all"]` | Toggle AI features (requires admin override to be enabled) |

### Thread Grouping

Emails with the same `emailThreadId` (Gmail `threadId` or M365 `conversationId`) are grouped visually in the Activity timeline:

```
Email thread with John Smith — Deck Estimate          3 days ago
   (4 messages)  [expand]
   - You: "Hi John, your estimate is attached"        3 days ago
   - John: "Thanks, looks good. One question..."      2 days ago
   - You: "Happy to clarify — the membrane..."        2 days ago
   - John: "Perfect, let's proceed"                   Yesterday
```

### Service & Hook Inventory

**Services** (`src/lib/api/services/`):
| Service | File | Purpose |
|---------|------|---------|
| EmailService | `email-service.ts` | Provider abstraction, connection CRUD, OAuth tokens, message fetch |
| EmailMatchingService | `email-matching-service.ts` | 5-tier client matching cascade |
| EmailClassifier | `email-classifier.ts` | AI email classification and stage placement |
| EmailSyncService | `email-sync-service.ts` | Sync cycle orchestration, pattern matching, webhook handling |

**Hooks** (`src/lib/hooks/`):
| Hook | File | Purpose |
|------|------|---------|
| useEmailConnections | `use-email-connections.ts` | TanStack Query: fetch, update, delete connections |
| useEmailImport | `use-email-import.ts` | Start import, poll progress, Action Prompt UX |
| useEmailSyncNotifications | `use-email-sync-notifications.ts` | Real-time sync event notifications |

**Components:**
| Component | File | Purpose |
|-----------|------|---------|
| EmailSetupWizard | `settings/email-setup-wizard.tsx` | 5-step wizard (Connect → Activate Sync) |
| SourceConfirmPanel | `settings/source-confirm-panel.tsx` | Detected source review and toggle UI |
| ImportReviewPanel | `settings/import-review-panel.tsx` | Lead review, stage assignment, duplicate merge UI |

### Data Types

**EmailConnection:**
```typescript
interface EmailConnection {
  id: string;
  companyId: string;
  provider: 'gmail' | 'microsoft365';
  accessToken: string;
  refreshToken: string;
  tokenExpiresAt: Date;
  userEmail: string;
  userName: string;
  syncProfile: SyncProfile;
  syncIntervalMinutes: number;
  lastSyncHistoryId: string | null;
  lastSyncAt: Date | null;
  opsLabelId: string | null;
  webhookSubscriptionId: string | null;
  webhookExpiresAt: Date | null;
  aiReviewEnabled: boolean;
  aiMemoryEnabled: boolean;
  status: 'active' | 'paused' | 'error' | 'setup_incomplete';
  createdAt: Date;
  updatedAt: Date;
}
```

**SyncProfile:**
```typescript
interface SyncProfile {
  estimateSubjectPatterns: string[];
  companyDomains: string[];
  teamForwarders: string[];
  knownPlatformSenders: string[];
  formSubjectPatterns: string[];
  userEmailAddresses: string[];
  aiClassificationThreshold: number;
}
```

### Lead Auto-Creation Logic

When a lead is created from email import:
- `opportunity.source = 'email'`
- `opportunity.stage` = AI-determined or correspondence-count-determined stage
- `opportunity.winProbability` = based on stage
- `opportunity.tags = ['email-import']`
- Existing open opportunities are checked first — no duplicates created
- Correspondence tracking columns populated: `correspondence_count`, `outbound_count`, `inbound_count`, `last_inbound_at`, `last_outbound_at`, `last_message_direction`

---

## Entity Relationship Map

```
EmailConnection ────── Company ──── CompanySettings
                           │
          ┌────────────────┼────────────────┐
          │                │                │
       Client           Project          TaskType
          │            (folder)              │
          │          /    │    \        TaskTemplate[]
    SubClient[]   Est.  Est.  Est.  ←── (default tasks)
                   │     │     │
              LineItem[]  (LABOR → taskTypeId)
                   │
              ProjectTask[] ←── sourceLineItemId
                   │
              (startDate / endDate on task)
                   │
              (schedule)

   Opportunity ──────────────────────────── Project
   (pipeline card)  opportunityId              │
          │                                ProjectPhoto[]
          │                                 (source tagged)
     Activity[]
          │
     ActivityComment[]
          │
     SiteVisit[] ──── (dates stored directly; CalendarEvent removed)
          │
          └── photos[] ──► ProjectPhoto[]
                           (on job win)

   FollowUp[] ─── Opportunity
   StageTransition[] ─── Opportunity
   OpportunityEmailThread[] ─── Opportunity (junction: thread_id ↔ opportunity)

   Invoice ──── Project
      │    └─── Estimate (estimateId)
   Payment[]

   AdminFeatureOverride ─── Company (per-company AI feature gates)

   AgentMemory[] ─── Company (pgvector embeddings, feature-gated)
   AgentKnowledgeGraph[] ─── Company (entity relationship edges)
   AgentWritingProfile ─── Company + User (communication style)
```

---

## Status & Stage Reference

### Opportunity Stages (Pipeline)

| Stage | Slug | Trigger In | Trigger Out |
|---|---|---|---|
| New Lead | `new_lead` | Lead created | First activity logged |
| Qualifying | `qualifying` | Auto | Estimate created |
| Quoting | `quoting` | Estimate created | Estimate sent |
| Quoted | `quoted` | Estimate sent | X days elapsed → Follow Up; client replies → Negotiation |
| Follow Up | `follow_up` | Auto (X days) | Client replies → Negotiation |
| Negotiation | `negotiation` | Inbound activity | Revised estimate sent → Quoted; estimate approved → Won |
| Won | `won` | Estimate approved | Terminal |
| Lost | `lost` | Estimate declined | Terminal |
| Discarded | `discarded` | User marks lead as not worth pursuing | Terminal — ad quality signal |

### Project Statuses

| Status | Meaning | Set When |
|---|---|---|
| `RFQ` | Request for Quote — project stub created, no estimate yet | Project auto-created at estimate send |
| `Estimated` | At least one estimate has been sent | Estimate sent |
| `Accepted` | Estimate approved, work authorized | Estimate approved |
| `InProgress` | Field work started | First task goes InProgress |
| `Completed` | All tasks done, ready to invoice | All tasks Completed |
| `Closed` | Invoice fully paid | Invoice status → Paid |
| `Archived` | Manually archived | Manual action |

### Estimate Statuses

| Status | Meaning |
|---|---|
| `draft` | Being built, not sent |
| `sent` | Sent to client |
| `viewed` | Client opened (if tracked) |
| `approved` | Client accepted |
| `changes_requested` | Client replied with change requests |
| `declined` | Client rejected |
| `converted` | Converted to invoice |
| `expired` | Past expiration date without response |
| `superseded` | Replaced by a newer version |

### Invoice Statuses

| Status | Meaning |
|---|---|
| `draft` | Being prepared |
| `sent` | Sent to client |
| `awaiting_payment` | Client acknowledged, payment pending |
| `partially_paid` | Deposit or progress payment received |
| `past_due` | Past due date, unpaid |
| `paid` | Fully paid — triggers project → Closed |
| `void` | Voided |
| `written_off` | Bad debt, written off |

### SiteVisit Statuses

| Status | Meaning |
|---|---|
| `scheduled` | Booked, upcoming |
| `in_progress` | Staff has arrived, capturing notes/photos |
| `completed` | Visit done, notes and photos saved |
| `cancelled` | Cancelled before completion |

---

## Implementation Notes

### Database Locations

| Entity | Backend | Notes |
|---|---|---|
| `TaskTemplate` | Bubble.io | Same backend as TaskType — same query patterns |
| `ActivityComment` | Supabase | Joins to Activity via `activityId` |
| `SiteVisit` | Supabase | Joins to Opportunity and Project |
| `ProjectPhoto` | Supabase | Replaces Bubble `projectImages` string |
| `EmailConnection` | Supabase | OAuth tokens (encrypted at rest), sync profile, webhook subscription, AI flags. Renamed from `gmail_connections`. |
| `CompanySettings` | Supabase | 1:1 with companyId |

### New Bubble API Endpoints Needed

```
GET  /obj/tasktemplate?constraints=[{"key":"companyId","constraint_type":"equals","value":X}]
POST /obj/tasktemplate
PATCH /obj/tasktemplate/:id
DELETE /obj/tasktemplate/:id

PATCH /obj/tasktype/:id          (add defaultTeamMemberIds field)
PATCH /obj/projecttask/:id       (add sourceLineItemId, sourceEstimateId fields)
PATCH /obj/project/:id           (add opportunityId field)
PATCH /obj/calendarevent/:id     (add eventType, opportunityId, siteVisitId fields)
```

### Supabase Tables — status (corrected 2026-05-10)

The list below was originally written as "tables needed." A live audit on 2026-05-10 found `project_photos` already exists in production — schema and use documented below. Other tables in this list may also be stale; a full audit is a separate follow-up.

```sql
-- activity_comments               (status TBD)
-- site_visits                     (status TBD)
-- project_photos                  EXISTS IN PROD — see schema below
-- email_connections               (renamed from gmail_connections, status TBD)
-- opportunity_email_threads       (status TBD)
-- admin_feature_overrides         (status TBD)
-- agent_memories                  (feature-gated, status TBD)
-- agent_knowledge_graph           (feature-gated, status TBD)
-- agent_writing_profiles          (feature-gated, status TBD)
-- company_settings                (status TBD — alter if table exists)
```

**`project_photos` actual schema (verified live 2026-05-10):**

| Column | Type | Nullable | Default |
|---|---|---|---|
| `id` | uuid | NO | `gen_random_uuid()` |
| `project_id` | text | NO | — |
| `company_id` | text | NO | — |
| `url` | text | NO | — |
| `thumbnail_url` | text | YES | — |
| `source` | enum `photo_source` (`site_visit`, `in_progress`, `completion`, `other`, `measurement`) | NO | `'other'` |
| `site_visit_id` | uuid | YES | — |
| `uploaded_by` | text | NO | — |
| `taken_at` | timestamptz | YES | — |
| `caption` | text | YES | — |
| `is_client_visible` | boolean | NO | `false` |
| `created_at` | timestamptz | YES | `now()` |
| `deleted_at` | timestamptz | YES | — |

`source = 'measurement'` is used by LiDAR Dimensioned Photo Capture (see §07 Section 23) — added 2026-05-10 alongside the spec.

-- Alter existing tables:
ALTER TABLE line_items ADD COLUMN type text DEFAULT 'LABOR';
ALTER TABLE line_items ADD COLUMN task_type_id text;
ALTER TABLE line_items ADD COLUMN estimated_hours numeric;

ALTER TABLE estimates ADD COLUMN project_id text;

ALTER TABLE invoices ADD COLUMN project_id text;
ALTER TABLE invoices ADD COLUMN estimate_id uuid REFERENCES estimates(id);

ALTER TABLE products ADD COLUMN type text DEFAULT 'LABOR';
ALTER TABLE products ADD COLUMN task_type_id text;

ALTER TABLE opportunities ADD COLUMN source_email_id text;

ALTER TABLE activities ADD COLUMN attachments text[] DEFAULT '{}';
ALTER TABLE activities ADD COLUMN email_thread_id text;
ALTER TABLE activities ADD COLUMN email_message_id text;
ALTER TABLE activities ADD COLUMN is_read boolean DEFAULT true;
ALTER TABLE activities ADD COLUMN site_visit_id uuid REFERENCES site_visits(id);
ALTER TABLE activities ADD COLUMN project_id text;
```

### Implementation Priority Order

**Phase 1 — Data layer (no UI changes yet):**
1. Add new Bubble fields: `TaskType.defaultTeamMemberIds`, `Project.opportunityId`, `ProjectTask` source fields (CalendarEvent has been removed — scheduling dates are on ProjectTask directly)
2. Create Bubble `TaskTemplate` data type
3. Supabase: alter `line_items`, `estimates`, `invoices`, `products`, `opportunities`, `activities`
4. Supabase: create `activity_comments`, `site_visits`, `project_photos`, `email_connections`, `opportunity_email_threads`, `admin_feature_overrides`, `agent_memories`, `agent_knowledge_graph`, `agent_writing_profiles`, `company_settings`

**Phase 2 — Automation (backend services):**
5. Estimate send flow: client creation + project creation inline prompts
6. Estimate approval: task generation logic + Review Tasks modal
7. Project status cascades
8. Auto follow-up timer (cron/edge function)

**Phase 3 — New features UI:**
9. Site visit create/edit/complete flow
10. Activity comments on timeline
11. Review Tasks modal
12. Project photo gallery (grouped by source)
13. TaskType settings: default crew + task templates

**Phase 4 — Email Pipeline Integration:**
14. Email OAuth connection flow (Gmail + M365, Settings → Integrations)
15. Pattern detection engine + "Import Your Pipeline" wizard
16. Webhook-driven sync engine with provider abstraction
17. 5-tier client matching + correspondence tracking
18. AI classification and stage placement (feature-gated)
19. AI memory system (feature-gated)

### Implementation Status by Platform (as of February 2026)

#### Pipeline — iOS Views (Built)

The Pipeline tab is fully implemented on iOS with the following views in `OPS/OPS/Views/Pipeline/`:

| File | Purpose |
|---|---|
| `PipelineTabView.swift` | Top-level tab container |
| `PipelineView.swift` | Main Kanban board view |
| `PipelineStageStrip.swift` | Horizontal stage selector strip |
| `PipelinePlaceholderView.swift` | Empty state placeholder |
| `OpportunityCard.swift` | Pipeline card for a single opportunity |
| `OpportunityDetailView.swift` | Full detail view for an opportunity |
| `OpportunityFormSheet.swift` | Create/edit opportunity form |
| `OpportunityBadgeView.swift` | Stage/status badge component |
| `ActivityFormSheet.swift` | Log activity from opportunity |
| `ActivityRowView.swift` | Single activity row in timeline |
| `FollowUpRowView.swift` | Follow-up reminder row |
| `MarkLostSheet.swift` | Mark opportunity as lost (with reason prompt) |

#### Estimates — iOS Views (Built)

Estimates are fully implemented on iOS with the following views in `OPS/OPS/Views/Estimates/`:

| File | Purpose |
|---|---|
| `EstimatesListView.swift` | List of estimates (filterable) |
| `EstimateDetailView.swift` | Full estimate detail view |
| `EstimateFormSheet.swift` | Create/edit estimate |
| `EstimateCard.swift` | Summary card for estimate lists |
| `LineItemEditSheet.swift` | Add/edit individual line items |
| `ProductPickerSheet.swift` | Pick from product catalog when adding line items |

#### Invoices — iOS Views (Built)

Invoices are fully implemented on iOS with the following views in `OPS/OPS/Views/Invoices/`:

| File | Purpose |
|---|---|
| `InvoicesListView.swift` | List of invoices (filterable) |
| `InvoiceDetailView.swift` | Full invoice detail view |
| `InvoiceCard.swift` | Summary card for invoice lists |
| `PaymentRecordSheet.swift` | Record a payment against an invoice |

#### SiteVisit — Model Only (No iOS Views)

The `SiteVisit` data model exists at `OPS/OPS/DataModels/Supabase/SiteVisit.swift` (SwiftData `@Model` with fields: `id`, `opportunityId`, `companyId`, `status`, `scheduledAt`, `completedAt`, `notes`, `address`, `assignedTo`, `createdAt`). However, no dedicated iOS views exist for site visits yet. Site visit UI (create, on-site capture, complete) is not yet built on iOS.

#### Email Pipeline Integration — Web Only (No iOS Implementation)

Email integration API routes exist on the web backend (`OPS-Web/src/app/api/integrations/email/`):
- `route.ts` — main email integration endpoint
- `callback/route.ts` — OAuth callback handler (Gmail + M365)
- `sync/route.ts` — sync trigger
- `webhook/gmail/route.ts` — Gmail Pub/Sub webhook receiver
- `webhook/microsoft365/route.ts` — M365 Change Notifications webhook receiver

Supporting web services: `email-service.ts`, `email-sync-service.ts`, `email-matching-service.ts`, `email-classifier.ts`, `use-email-connections.ts`, `email-setup-wizard.tsx`.

No email integration exists on iOS. The iOS app reads from the same `opportunities` table (which gains new correspondence tracking columns) but does not connect to or sync email accounts.

#### In-App Email Client (Web — Built 2026-03-19)

The web app includes a full in-app email client at `/inbox` (inbox view, compose modal, email templates, AI drafting with 3-phase progression, auto-send, and stage manual override). Sync engine hardened with subscription gating, activity data enrichment, timestamp validation, and OpenAI API key separation across three keys (import/sync/drafting). See `07_SPECIALIZED_FEATURES.md` §19 for the complete in-app email system documentation.

---

*This document supersedes any prior informal notes about entity relationships. All implementation decisions should reference this document.*
