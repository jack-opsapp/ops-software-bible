# 03: Data Architecture

**Last Updated**: 2026-05-07
**Status**: Comprehensive Reference
**Purpose**: Complete data layer specification for OPS iOS/Android applications

---

## Table of Contents

1. [Overview](#overview)
2. [SwiftData Models (48 Registered Entities)](#swiftdata-models-48-registered-entities)
3. [Subscription Add-ons — `data_setup_requests`](#subscription-add-ons--data_setup_requests)
4. [Project Workspace Modal Tables (Web-Only)](#project-workspace-modal-tables-web-only)
5. [Permissions System Tables](#permissions-system-tables)
6. [Catalog & Variant Model](#catalog--variant-model)
7. [Bridge & Audit Tables](#bridge--audit-tables)
8. [Enums Reference](#enums-reference)
9. [Relationship Map](#relationship-map)
10. [BubbleFields Constants (Legacy/Deprecated)](#bubblefields-constants-legacydeprecated)
11. [Data Transfer Objects (DTOs)](#data-transfer-objects-dtos)
12. [Supabase DTOs](#supabase-dtos)
13. [Soft Delete Strategy](#soft-delete-strategy)
14. [Computed Properties & Business Logic](#computed-properties--business-logic)
15. [Migration History](#migration-history)
16. [Query Predicates & Filtering](#query-predicates--filtering)
17. [Defensive Programming Patterns](#defensive-programming-patterns)

---

## Phase 13 — Catalog & Variant Model (2026-05-07)

This document was significantly refactored on 2026-05-07 as Phase 13 of `2026-05-06-ios-catalog-variant-model.md`. Key changes:

- § 21 (Product) gained 9 new fields (`pricingUnit`, `basePrice`, `kind`, `sku`, `isFavorite`, `minimumCharge`, `minimumQuantity`, `showBomOnEstimate`, `showInStorefront`, `tieredPricingJSON`) and a Configurable Products subsection.
- § Inventory Models (5 file-only entities) was replaced with § Catalog & Variant Model (14 registered catalog entities + 4 product extensions).
- The wire-field bug in `ProductDTOs.swift` (writing `unit_price`/`cost_price` to non-existent columns) was fixed; DTOs now correctly map `base_price`/`unit_cost`.
- DTO listings added for `CatalogDTOs.swift`, `ProductExtensionDTOs.swift`, `CompanyDefaultProductDTOs.swift`, `CatalogOrderDTOs.swift`, `TaskMaterialDTOs.swift`.
- New § Bridge & Audit Tables documents `product_materials`, `task_materials`, `line_item_materials`, `inventory_deductions` (FK renamed to `catalog_variant_id`), `client_product_overrides`, `product_tax_rates`, `company_default_products`, `catalog_orders`, `catalog_order_items`.
- Schema bumped V2 → V3. Total registered models: 25 → 48.

---

## Overview

### Data Layer Architecture

The OPS data layer follows a **three-tier architecture**:

1. **SwiftData Models**: Persistent entities stored locally (iOS: SwiftData, Android: Room)
2. **DTOs (Data Transfer Objects)**: API response mapping layer (both Bubble legacy and Supabase)
3. **Supabase Backend**: PostgreSQL database accessed via Supabase DTOs with snake_case column mapping

### Core Principles

- **Soft Delete**: Most entities support `deletedAt: Date?` for reversible deletion
- **Offline-First**: All data persists locally with sync tracking (`needsSync`, `lastSyncedAt`)
- **Type Safety**: DTOs handle field name mapping and type conversion
- **Task-Based Scheduling**: Project dates are computed from task start/end dates (CalendarEvent entity has been removed)

### The 49 Registered Schema Models

As defined in `OPSSchemaCommon.unchangedModels` (48 entries) + `WizardState` (per-version, schema V3 today). The schema container is built via `OPSSchemaV3` in `OPSApp.swift`.

**Core Entities (11):**
1. **User** -- Team member with role-based permissions
2. **Project** -- Central entity for field crew work
3. **Company** -- Organization/subscription management
4. **TeamMember** -- Lightweight user cache (company-scoped)
5. **Client** -- Customer/client management
6. **SubClient** -- Additional client contacts
7. **ProjectTask** -- Task-based scheduling within projects
8. **TaskType** -- Reusable task templates per company
8a. **TaskTemplate** -- Sub-task scaffolding under a TaskType (renders one ProjectTask per row at estimate-approval)
9. **TaskStatusOption** -- Company-customizable task status colors
10. **SyncOperation** -- Queued offline sync operations
11. **OpsContact** -- OPS support contact information

**Supabase-Backed Entities (14):**
12. **Opportunity** -- Pipeline deal/lead
13. **Activity** -- Timeline event per opportunity
14. **FollowUp** -- Scheduled reminder
15. **StageTransition** -- Immutable stage history record
16. **Estimate** -- Quote document
17. **EstimateLineItem** -- Line item on an estimate
18. **Invoice** -- Billing document
19. **InvoiceLineItem** -- Line item on an invoice
20. **Payment** -- Payment record (insert-only)
21. **Product** -- Billable line-item template (barebones or configurable; see § 21)
22. **SiteVisit** -- Scope assessment visit
23. **ProjectNote** -- Per-project message board note
24. **PhotoAnnotation** -- Drawing overlay and text note for project photos
25. **CalendarUserEvent** -- User-owned personal events and time-off requests

**Offline-First Sync Models (4):**
26. **TimeEntry** -- Field crew time tracking
27. **SignatureCapture** -- Stored signatures for estimates/invoices/job approvals
28. **FormSubmission** -- Submitted forms (custom checklists)
29. **LocalPhoto** -- Local photo cache pending S3 upload

**Catalog Models (14) — replaces legacy Inventory* file-only models:**
30. **CatalogCategory** -- Nested category for catalog items (parent_id self-FK)
31. **CatalogItem** -- Variant family (name, default price/cost/threshold/unit)
32. **CatalogVariant** -- The SKU (quantity, threshold, unit, sku, override prices)
33. **CatalogOption** -- A variant axis on a family ("Color", "Mount Type")
34. **CatalogOptionValue** -- A possible value for a CatalogOption
35. **CatalogVariantOptionValue** -- Junction (variant ↔ option_value)
36. **CatalogTag** -- Free-form FAMILY-level label
37. **CatalogItemTag** -- Junction (family ↔ tag)
38. **CatalogUnit** -- Unit of measure (replaces InventoryUnit; exposes dimension + abbreviation)
39. **CatalogSnapshot** -- Variant-aware historical stock snapshot
40. **CatalogSnapshotItem** -- One row per variant in a snapshot
41. **CatalogOrder** -- Threshold-driven restock order (status: suggested / draft / sent / fulfilled / cancelled)
42. **CatalogOrderItem** -- One line per variant on an order
43. **CompanyDefaultProduct** -- (company_id, component_type) → product_id; drives drawing→estimate adapter

**Configurable Product Extensions (4):**
44. **ProductOption** -- A configurable knob on a Product (kind: select / integer / boolean)
45. **ProductOptionValue** -- A possible value for a ProductOption
46. **ProductPricingModifier** -- Price bump rule per option/value match
47. **ProductMaterial** -- Recipe row (variant-pinned or family-pinned with selector)
48. **ProductBundleItem** -- Child row of a bundle product (kind=package); enumerates bundle composition with per-row quantity + display order. See `product_bundle_items` table.

**Deck Builder (1):**
49. **DeckDesign** -- Canvas drawing data for design components (railing, deck_board, stair_set, gate, post_set)

**Per-Schema-Version (1):**
- **WizardState** -- Onboarding wizard state (schema-versioned; appended in `OPSSchemaV3.models`)

> Legacy note: `InventoryItem`, `InventorySnapshot`, `InventorySnapshotItem`, `InventoryTag`, `InventoryUnit` files remain on disk through the V2→V3 migration window for compile-time references but are NOT registered in `OPSSchemaCommon`. They are removed by Phase 4 of the catalog plan. SQL-side, the `inventory_*` tables are renamed to `catalog_*` by migration `2026-05-06-01-catalog-schema.sql`.

---

## SwiftData Models (48 Registered Entities)

### 1. Project

**File**: `DataModels/Project.swift`
**Purpose**: Central entity representing a construction/trade project.

**Properties**:

```swift
@Model
final class Project: Identifiable {
    var id: String
    var title: String
    var address: String?
    var latitude: Double?
    var longitude: Double?
    var startDate: Date?
    var endDate: Date?
    var duration: Int?
    var status: Status
    var notes: String?
    var companyId: String
    var clientId: String?
    var opportunityId: String?       // Supabase Opportunity UUID
    var allDay: Bool
    var projectDescription: String?
    var projectImagesString: String = ""
    var unsyncedImagesString: String = ""
    var teamMemberIdsString: String = ""

    // Relationships
    @Relationship(deleteRule: .nullify) var client: Client?
    @Relationship(deleteRule: .noAction) var teamMembers: [User]
    @Relationship(deleteRule: .cascade, inverse: \ProjectTask.project) var tasks: [ProjectTask] = []

    // Sync
    var lastSyncedAt: Date?
    var needsSync: Bool = false
    var syncPriority: Int = 1
    var deletedAt: Date?

    // Audit — added 2026-05-10 (bug 9d5c2535) to power the "start from
    // recent" suggestions strip on the project form. Nil for projects
    // synced down before the column existed.
    var createdAt: Date?
    var createdBy: String?

    // Transient
    @Transient var lastTapped: Date?
    @Transient var coordinatorData: [String: Any]?

    // Project Workspace Modal columns (Supabase only — added 2026-05-06)
    // visibility       TEXT DEFAULT 'all' CHECK ∈ {all, office, private} — portal exposure; private projects do not appear in the client portal
    //   Partial index idx_projects_visibility WHERE visibility != 'all' speeds the office/private filter on company dashboards.

    // Audit columns (Supabase) — also surfaced as SwiftData properties
    // created_at       TIMESTAMPTZ — auto-populated by Supabase default
    // created_by       UUID FK → auth.users(id) — populated by iOS on insert; index idx_projects_created_by_created_at (created_by, created_at DESC) WHERE deleted_at IS NULL speeds the recency strip query.
}
```

**Key Computed Properties**:

```swift
var computedStartDate: Date? { tasks.compactMap { $0.startDate }.min() }
var computedEndDate: Date? { tasks.compactMap { $0.endDate }.max() }
var effectiveClientName: String { client?.name ?? "" }
var effectiveClientEmail: String? { ... }   // Cascades to sub-clients
var effectiveClientPhone: String? { ... }   // Cascades to sub-clients
var coordinate: CLLocationCoordinate2D? { ... }  // Validates ranges, rejects 0,0
var computedStatus: Status { ... }          // Derives from task statuses
var hasTasks: Bool { !tasks.isEmpty }
var effectiveEndDate: Date? { ... }         // Falls back to duration
var isMultiDay: Bool { ... }
var daySpan: Int { ... }
var spannedDates: [Date] { ... }
```

**Array Accessors**: `getTeamMemberIds()`, `setTeamMemberIds(_:)`, `getProjectImageURLs()`, `setProjectImageURLs(_:)`, `getUnsyncedImages()`, `addUnsyncedImage(_:)`, `markImageAsSynced(_:)`, `clearUnsyncedImages()`

**Key Methods**: `updateTeamMembersFromTasks(in:)` -- collects unique team member IDs from all tasks and updates project.

---

### 2. ProjectTask

**File**: `DataModels/ProjectTask.swift`
**Purpose**: Task within a project. Scheduling dates are stored directly on the task (CalendarEvent has been removed).

**Properties**:

```swift
@Model
final class ProjectTask {
    var id: String
    var projectId: String
    var companyId: String
    var status: TaskStatus               // .active, .completed, .cancelled
    var taskColor: String                // Hex color code
    var taskNotes: String?
    var taskTypeId: String
    var taskIndex: Int?
    var displayOrder: Int = 0
    var customTitle: String?
    var sourceLineItemId: String?        // Supabase LineItem UUID
    var sourceEstimateId: String?        // Supabase Estimate UUID

    // Scheduling (merged from former CalendarEvent)
    var startDate: Date?
    var endDate: Date?
    var duration: Int = 1

    // Phase 3 — Time precision (added 2026-04-27)
    var startTime: String?               // "HH:mm:ss" local clock; null when allDay
    var endTime: String?                 // "HH:mm:ss" local clock; null when allDay
    var allDay: Bool = true              // Source of truth. When true, start_time/end_time are ignored by rendering and conflict logic.

    // Phase 3 — Recurrence link (added 2026-04-27)
    var recurrenceId: String?            // FK -> task_recurrences.id; null for one-off tasks
    var recurrenceOriginDate: String?    // YYYY-MM-DD; the original (un-shifted) date this occurrence was generated for. Used by the cron worker for idempotency and by the exception lookup.

    var teamMemberIdsString: String = ""

    // Dependency overrides (per-task override of taskType.dependencies)
    var dependencyOverridesJSON: String?

    // Pair linkage — added 2026-05-11 (bug f4bbd11c)
    var pairedFromTaskId: String?        // Predecessor task that auto-spawned this one
    var scheduleLocked: Bool = false     // True once user manually edits startDate;
                                         // cascade ignores locked tasks

    // Relationships
    @Relationship(deleteRule: .nullify) var project: Project?
    @Relationship(deleteRule: .nullify) var taskType: TaskType?
    @Relationship(deleteRule: .noAction) var teamMembers: [User] = []

    // Sync
    var lastSyncedAt: Date?
    var needsSync: Bool = false
    var deletedAt: Date?

    // Audit — added 2026-05-10 (bug 9d5c2535). Powers the recency-sorted
    // task type and team-member pickers on the task form. Prefers
    // task.createdAt; falls back to lastSyncedAt for pre-migration rows.
    var createdAt: Date?
}
```

**Pair-linkage semantics** (added 2026-05-11):
- `paired_from_task_id` populated when this task was spawned by `TaskPairSpawner`
  on creation of a predecessor task whose type was the target of an `auto_create`
  dependency. NULL for manually-created tasks.
- Hard delete / soft delete / cancel of the predecessor cascades to all paired
  descendants via `pairedFromTaskId` lookup (one-way; deleting a paired task does
  not affect its predecessor).
- `schedule_locked` is set to `true` automatically by `DataController.updateTaskSchedule`
  whenever `manualEdit: true` (the default) is passed. System-driven shifts
  (cascade application, auto-schedule placement, undo cascade) pass `manualEdit: false`
  to preserve auto-tracking.
- `SchedulingEngine.calculateCascade()` skips tasks where `schedulingLocked == true`
  — predecessor movements no longer auto-shift them. The lock is reset only by
  deleting & recreating the paired task (no UI to unlock manually).

**Phase 3 — Time precision semantics** (added 2026-04-27):
- `allDay = true` → the task is treated as a date-only block. `startTime` and `endTime` are stored but ignored by the calendar grid, conflict detection, and notifications. Pre-Phase-3 rows default to `true` regardless of the historical `08:00–17:00` time values.
- `allDay = false` → `startTime` and `endTime` are authoritative local-clock times (no timezone — the company's local clock). Hourly Day view kicks in when at least one event on a day is timed.
- `companies.default_work_start` / `default_work_end` (Phase 3) seed `startTime` / `endTime` when the user toggles `allDay = false` from the task detail panel.

**Phase 3 — Recurrence link semantics** (added 2026-04-27):
- A task with `recurrenceId NOT NULL` was generated by `/api/cron/recurrence-generate` from a `task_recurrences` row. It is otherwise a normal `project_tasks` record — editable in place, completable, deletable.
- `recurrenceOriginDate` is the calendar date the cron used as the candidate. The unique partial index `uq_project_tasks_recurrence_origin` on `(recurrence_id, recurrence_origin_date) WHERE recurrence_id IS NOT NULL AND deleted_at IS NULL` enforces idempotency on cron re-runs.
- Editing a generated task: scope choice (`this` / `this_and_following` / `all`) decides whether to write a `task_recurrence_exceptions` row, fork a new template, or patch the original template. See **TaskRecurrence** below.

**TaskStatus Enum** (defined in ProjectTask.swift):

```swift
enum TaskStatus: String, Codable, CaseIterable {
    case active = "active"
    case completed = "completed"
    case cancelled = "cancelled"

    // Custom decoder handles legacy values:
    // "Scheduled", "Booked", "booked", "In Progress", "in_progress" -> .active
    // "Completed" -> .completed
    // "Cancelled" -> .cancelled
}
```

**Key Computed Properties**:

```swift
var displayTitle: String { customTitle ?? taskType?.display ?? "Task" }
var effectiveColor: String { taskType?.color ?? taskColor }
var scheduledDate: Date? { startDate }
var completionDate: Date? { endDate }
var isOverdue: Bool { ... }
var isToday: Bool { ... }
var isMultiDay: Bool { ... }
var spannedDates: [Date] { ... }
var swiftUIColor: Color { Color(hex: effectiveColor) }
var displayIcon: String? { taskType?.icon }
```

---

### 2a. TaskRecurrence (Phase 3 — added 2026-04-27)

**Table**: `task_recurrences`
**Purpose**: RFC 5545 RRULE template that the cron worker `/api/cron/recurrence-generate` materializes into concrete `project_tasks` rows on a 60-day rolling horizon.

**Schema**:

```sql
CREATE TABLE task_recurrences (
  id                      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id              UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
  project_id              UUID REFERENCES projects(id) ON DELETE SET NULL,
  client_id               UUID REFERENCES clients(id) ON DELETE SET NULL,
  task_type_id            UUID REFERENCES task_types(id) ON DELETE SET NULL,
  title                   TEXT NOT NULL,
  team_member_ids         UUID[] NOT NULL DEFAULT '{}',
  rrule                   TEXT NOT NULL,        -- e.g. 'FREQ=WEEKLY;BYDAY=MO'
  start_anchor            DATE NOT NULL,        -- DTSTART
  end_anchor              DATE,                 -- UNTIL (inclusive); null = forever
  all_day                 BOOLEAN NOT NULL DEFAULT TRUE,
  start_time              TIME,                 -- when all_day = false
  end_time                TIME,
  duration                INT NOT NULL DEFAULT 1, -- in days
  notes                   TEXT,
  next_generation_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  created_by              UUID REFERENCES users(id) ON DELETE SET NULL,
  created_at              TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at              TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  deleted_at              TIMESTAMPTZ
);
```

**Indexes**:
- `idx_task_recurrences_active_due ON (company_id, next_generation_at) WHERE deleted_at IS NULL` — cron's primary scan path.
- `idx_task_recurrences_project ON (project_id) WHERE deleted_at IS NULL` — drives the project-detail series list.

**RLS**: company-scoped via `users.company_id` lookup, mirrors `project_tasks`.

**Cron checkpoint (`next_generation_at`)**:
- Default = `NOW()` on insert; cron picks up immediately.
- After every cron run, set to `NOW() + 4 hours`.
- Set back to `NOW()` on any update that changes `rrule`, `start_anchor`, `end_anchor`, `start_time`, `end_time`, `all_day`, `duration`, `team_member_ids`, or `task_type_id` — these force regeneration.

**Soft-delete**: `RecurrenceService.softDelete(id)` cascades — it stamps `deleted_at` on the template AND soft-deletes every un-started future `project_tasks` row that points at it (`status = 'active' AND start_date > NOW()`). Past, in-progress, and completed occurrences are preserved as historical records.

---

### 2b. TaskRecurrenceException (Phase 3 — added 2026-04-27)

**Table**: `task_recurrence_exceptions`
**Purpose**: Per-occurrence override on a recurrence series. Allows "skip this week" or "reschedule this one" without forking the entire template.

**Schema**:

```sql
CREATE TABLE task_recurrence_exceptions (
  id                      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  recurrence_id           UUID NOT NULL REFERENCES task_recurrences(id) ON DELETE CASCADE,
  original_date           DATE NOT NULL,           -- The date the RRULE candidate fell on
  action                  TEXT NOT NULL CHECK (action IN ('skip','reschedule')),
  new_date                DATE,                    -- When action = reschedule
  new_start_time          TIME,
  new_end_time            TIME,
  new_team_member_ids     UUID[],
  notes                   TEXT,
  created_at              TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (recurrence_id, original_date)
);
```

**Edit-this scope flow**:
1. User drags a single occurrence in month / week / crew / day-hourly view.
2. The recurrence prompt asks: this / this_and_following / all.
3. Choosing **this** writes (or upserts) an exception row with `action = 'reschedule'` and the new date/time/team. The live `project_tasks` row is patched in place so the user sees the move immediately. The cron will respect the exception on the next regen.

**Edit-following scope flow**: cap original template's `end_anchor` at `originalDate - 1`, fork a new template starting at `originalDate` with the patch applied, re-point future generated tasks (`recurrence_origin_date >= originalDate`) to the new template.

**Edit-all scope flow**: patch the original template directly. Cron regenerates all forward occurrences from `next_generation_at = NOW()`.

**Example exception record**:

```json
{
  "recurrence_id": "0e6f...",
  "original_date": "2026-05-04",
  "action": "skip",
  "new_date": null,
  "new_start_time": null,
  "new_end_time": null,
  "new_team_member_ids": null,
  "notes": "Holiday — Mike off"
}
```

---

### 3. TaskType

**File**: `DataModels/TaskType.swift`
**Purpose**: Reusable task templates with visual identity. Carries scheduling
dependencies and pair-spawning rules in `dependenciesJSON`.

**Properties**:

```swift
@Model
final class TaskType: Identifiable {
    var id: String
    var color: String                        // Hex color code
    var display: String                      // Display name (e.g., "Installation")
    var icon: String?                        // SF Symbol name
    var isDefault: Bool
    var companyId: String
    var displayOrder: Int = 0
    var defaultTeamMemberIdsString: String = "" // Default crew user IDs
    var dependenciesJSON: String = "[]"      // JSON array of TaskTypeDependency objects
    var isWeatherDependent: Bool = false     // Stub for future weather-aware scheduling
    var defaultDuration: Int = 1             // Default duration (days) for spawned tasks of this type

    @Relationship(deleteRule: .nullify, inverse: \ProjectTask.taskType)
    var tasks: [ProjectTask] = []

    var lastSyncedAt: Date?
    var needsSync: Bool = false
    var deletedAt: Date?
}
```

**NOTE**: The display property is `display`, NOT `name`.

**Default Task Types**: Site Estimate, Quote/Proposal, Material Order, Installation, Inspection, Completion.

**Supabase mapping**: Table is `task_types` (not `task_types_v2` — that name appears
elsewhere in this document but is outdated). The `dependencies` JSONB column on
`task_types` stores an array of `TaskTypeDependency` structs (see below).

#### TaskTypeDependency (JSONB schema)

```swift
struct TaskTypeDependency: Codable {
    // Scheduling
    let dependsOnTaskTypeId: String          // Predecessor task type
    let overlapPercentage: Int               // 0–100, used when overlapMode == "percentage"
    let overlapMode: String                  // "percentage" | "constant" | "after_end"
    let overlapConstantDays: Double          // Used when overlapMode == "constant"
    let minGapDaysAfterEnd: Int              // Used when overlapMode == "after_end" — days after pred end
    let weekdayConstraint: Int?              // ISO 1=Mon…7=Sun, nil = any day (after_end only)

    // Pair behavior — added 2026-05-10 (bug f4bbd11c)
    let autoCreate: Bool                     // When predecessor is created, auto-spawn this task
    let inheritCrew: Bool                    // Copy predecessor's team_member_ids onto the spawn
}
```

JSON keys are snake_case (`depends_on_task_type_id`, `overlap_mode`, `auto_create`, etc.).
Backward-compatible decoder applies safe defaults for older payloads missing the new fields.

The `after_end` mode + `weekdayConstraint` together expresses rules like
"glass panels installed first Wednesday on or after 1 week after glass rail ends" —
the predecessor's end date is computed, the gap is added, then the result is rounded
UP to the next occurrence of the target weekday.

#### Catalog interlink surfaces on iOS (2026-05-11 — bug 4dadd96c)

The TaskType ↔ Product ↔ TaskTemplate triangle is now bidirectionally exposed
in iOS. Previously the FKs existed (`products.task_type_ref`, the `task_templates`
table) but no UI surfaced them, so operators who set up either side first had
to retroactively edit the other.

- **`Product.taskTypeRef`** — Service-category products (`type = LABOR`) now
  surface a required Task Type picker in `QuickAddProductSheet` and
  `ProductDetailView`. The picker writes both `task_type_ref` (uuid FK) and
  `task_type_id` (legacy text mirror) in lockstep so legacy reads and new
  reads land on the same parent. Material and Fee products show the same
  picker as optional — they don't participate in task generation but can
  still group on the schedule. Picker source: `TaskTypePickerSheet.swift`
  (Views/Catalog/Products/) with inline `+ NEW TASK TYPE` that pushes
  `TaskTypeSheet` in create mode and auto-selects the result.

- **`TaskType` → linked products section** — `TaskTypeSheet` (edit mode)
  now lists every Product whose `task_type_ref` points at this type, with
  two affordances:
  - `ATTACH EXISTING` → opens `LinkedProductsAttachSheet`, which lists
    LABOR-type products not currently pinned here. Reassigning a product
    that already points at another task type surfaces a confirm dialog
    (`REASSIGN PRODUCT?`). The line-item snapshot semantics still hold —
    existing estimate line items carry their own frozen `task_type_id`.
  - `NEW PRODUCT` → opens `NewLinkedProductSheet`, a 3-field mini-form
    (name + price + unit) that creates a LABOR/service Product
    pre-bound to this task type.

- **`task_templates` (sub-task scaffolding)** — `TaskTypeSheet` now also
  exposes the `DEFAULT SUB-TASKS` section, which lists `task_templates`
  rows for this task type. Operators can add/edit/delete templates inline
  via `TaskTemplateEditSheet`. When an estimate's LABOR line item is
  approved, one `project_tasks` row is generated per template (per the
  task-generation logic in `10_JOB_LIFECYCLE_AND_DATA_RELATIONSHIPS.md`).
  Soft-delete via `deleted_at`. iOS model lives at
  `DataModels/Supabase/TaskTemplate.swift`; DTO at
  `Network/Supabase/DTOs/TaskTemplateDTOs.swift`; repository at
  `Network/Supabase/Repositories/TaskTemplateRepository.swift`.

- **Merge propagation** — `TaskTypeMergeSheet` now re-pins all linked
  products and sub-task templates to the merge target before soft-deleting
  the source. Previously products and templates were silently orphaned
  on the source row.

No schema changes. All work is additive over already-shipped FKs and
existing tables (`products.task_type_ref` exists since Phase 13; the
`task_templates` table already exists).

---

### 4. Client

**File**: `DataModels/Client.swift`
**Purpose**: Customer/client management with sub-client support.

**Properties**:

```swift
@Model
final class Client: Identifiable {
    var id: String
    var name: String
    var email: String?                       // Property is `email`, NOT `emailAddress`
    var phoneNumber: String?
    var address: String?
    var latitude: Double?
    var longitude: Double?
    var profileImageURL: String?
    var notes: String?
    var companyId: String?

    @Relationship(deleteRule: .noAction, inverse: \Project.client)
    var projects: [Project]
    @Relationship(deleteRule: .cascade)
    var subClients: [SubClient]

    var lastSyncedAt: Date?
    var needsSync: Bool = false
    var createdAt: Date?
    var deletedAt: Date?
}
```

**NOTE**: The email property is `email`, NOT `emailAddress`.

---

### 5. SubClient

**File**: `DataModels/SubClient.swift`
**Purpose**: Additional contacts for a client.

**Properties**:

```swift
@Model
final class SubClient: Identifiable {
    var id: String
    var name: String
    var title: String?
    var email: String?
    var phoneNumber: String?
    var address: String?
    var client: Client?

    var createdAt: Date
    var updatedAt: Date
    var lastSyncedAt: Date?
    var needsSync: Bool = false
    var deletedAt: Date?
}
```

---

### 6. User

**File**: `DataModels/User.swift`
**Purpose**: Team member with role-based permissions.

**Properties**:

```swift
@Model
final class User {
    var id: String
    var firstName: String                    // Property is `firstName`, NOT `nameFirst`
    var lastName: String                     // Property is `lastName`, NOT `nameLast`
    var email: String?
    var phone: String?
    var profileImageURL: String?
    var profileImageData: Data?
    var role: UserRole                       // .admin, .owner, .office, .operator, .crew, .unassigned
    var companyId: String?
    var userType: UserType?                  // .employee, .company
    var latitude: Double?
    var longitude: Double?
    var locationName: String?
    var homeAddress: String?
    var clientId: String?
    var isActive: Bool?
    var userColor: String?
    var devPermission: Bool = false
    var hasCompletedAppOnboarding: Bool = false
    var hasCompletedAppTutorial: Bool = false
    var isCompanyAdmin: Bool = false
    var inventoryAccess: Bool = false
    var specialPermissions: [String] = []    // Beta feature flags (e.g. "pipeline")
    var stripeCustomerId: String?
    var deviceToken: String?

    @Relationship(deleteRule: .noAction, inverse: \Project.teamMembers)
    var assignedProjects: [Project]

    var lastSyncedAt: Date?
    var needsSync: Bool = false
    var deletedAt: Date?
}
```

**NOTE**: Properties are `firstName`/`lastName`, NOT `nameFirst`/`nameLast` (those are Bubble field names, not model properties).

**PERMISSION SYSTEM (March 2026)**: The legacy fields `role`, `isCompanyAdmin`, `inventoryAccess`, `specialPermissions`, and `devPermission` on the User model are being superseded by a proper RBAC+ABAC permissions system stored in Supabase (see [Permissions System Tables](#permissions-system-tables) below). The new system uses three dedicated tables (`roles`, `role_permissions`, `user_roles`) with 5 preset roles and ~55 granular permissions. The legacy fields remain on the User model for backward compatibility during the transition but are no longer the source of truth for access control. UI gating should use the `PermissionStore` (web) or equivalent iOS permission service, not these fields.

---

### 7. Company

**File**: `DataModels/Company.swift`
**Purpose**: Organization entity managing subscription and defaults.

**Properties**:

```swift
@Model
final class Company {
    var id: String
    var name: String
    var logoURL: String?
    var logoData: Data?
    var externalId: String?
    var companyDescription: String?
    var address: String?
    var phone: String?
    var email: String?
    var website: String?
    var latitude: Double?
    var longitude: Double?
    var openHour: String?
    var closeHour: String?
    var industryString: String = ""
    var companySize: String?
    var companyAge: String?
    var referralMethod: String?
    var projectIdsString: String = ""
    var teamIdsString: String = ""
    var adminIdsString: String = ""
    var accountHolderId: String?
    var defaultProjectColor: String = "#9CA3AF"
    var teamMembersSynced: Bool = false

    // Subscription
    var subscriptionStatus: String?          // "trial", "active", "grace", "expired", "cancelled"
    var subscriptionPlan: String?            // "trial", "starter", "team", "business"
    var subscriptionEnd: Date?
    var subscriptionPeriod: String?          // "Monthly", "Annual"
    var maxSeats: Int = 10
    var seatedEmployeeIds: String = ""
    var seatGraceStartDate: Date?
    var subscriptionIdsJson: String?
    var trialStartDate: Date?
    var trialEndDate: Date?
    var hasPrioritySupport: Bool = false       // Stripe-driven entitlement (Priority Support add-on)
    var prioritySupportPeriod: String?         // 'monthly' | 'annual' — billing cadence cache for the active Priority Support sub
    var dataSetupPurchased: Bool = false       // Stripe-driven entitlement (Data Setup add-on, one-time)
    var dataSetupCompleted: Bool = false       // Flipped by ops staff in admin once migration is done
    var dataSetupScheduledDate: Date?          // Mirrors data_setup_requests.scheduled_at for the iOS read path
    var stripeCustomerId: String?

    // Phase 3 — Default work hours (added 2026-04-27)
    // Used as seed values for project_tasks.start_time / end_time when the
    // user toggles a task to all_day = false. Stored as TIME (no timezone)
    // because trades work clocks are local to the company.
    var defaultWorkStart: String = "08:00:00"
    var defaultWorkEnd: String = "17:00:00"

    // Relationships
    @Relationship(deleteRule: .cascade) var teamMembers: [TeamMember] = []
    @Relationship(deleteRule: .cascade) var taskTypes: [TaskType] = []
    @Relationship(deleteRule: .cascade) var inventoryUnits: [InventoryUnit] = []

    // Sync
    var lastSyncedAt: Date?
    var needsSync: Bool = false
    var deletedAt: Date?
}
```

---

### 8. TeamMember

**File**: `DataModels/TeamMember.swift`
**Purpose**: Lightweight team member cache (reduces need for full User fetches).

**Properties**:

```swift
@Model
final class TeamMember {
    var id: String
    var firstName: String
    var lastName: String
    var role: String                         // Role as plain String (not enum)
    var avatarURL: String?
    var email: String?
    var phone: String?
    var lastUpdated: Date

    @Relationship(deleteRule: .cascade, inverse: \Company.teamMembers)
    var company: Company?
}
```

**Factory Method**: `static func fromUser(_ user: User) -> TeamMember`

---

### 9. TaskStatusOption

**File**: `DataModels/TaskStatusOption.swift`
**Purpose**: Company-customizable display colors for task statuses.

**Properties**:

```swift
@Model
final class TaskStatusOption {
    var id: String
    var display: String
    var color: String
    var index: Int
    var companyId: String

    var lastSyncedAt: Date?
    var needsSync: Bool = false
}
```

Extends `TaskStatus` with `func color(from options: [TaskStatusOption]) -> Color` to look up custom colors.

---

### 10. SyncOperation

**File**: `DataModels/SyncOperation.swift`
**Purpose**: Queued sync operations for offline-first outbound sync.

**Properties**:

```swift
@Model
final class SyncOperation {
    var id: UUID
    var entityType: String
    var entityId: String
    var operationType: String
    var payload: Data
    var changedFields: String                // Comma-separated
    var createdAt: Date
    var retryCount: Int = 0
    var status: String = "pending"           // "pending", "inProgress", "failed", "completed"
    var lastError: String?
}
```

**Computed**: `isPending`, `isInProgress`, `isFailed`, `isCompleted`, `canRetry` (retryCount < 5).

---

### 11. OpsContact

**File**: `DataModels/OpsContact.swift`
**Purpose**: OPS support contact information.

**Properties**:

```swift
@Model
final class OpsContact {
    var id: String
    var email: String
    var name: String
    var phone: String
    var display: String
    var role: String                         // "jack", "priority support", etc.
    var lastSynced: Date
}
```

**OpsContactRole Enum**: `.jack`, `.prioritySupport`, `.dataSetup`, `.generalSupport`, `.webAppAutoSend`

---

### 12. Opportunity (Supabase-Backed)

**File**: `DataModels/Supabase/Opportunity.swift`
**Purpose**: Pipeline deal/lead.

**Properties**:

```swift
@Model
class Opportunity: Identifiable {
    @Attribute(.unique) var id: String
    var companyId: String
    var title: String?              // mirrors NOT NULL DB column; Optional in SwiftData for store-migration safety
    var contactName: String
    var contactEmail: String?
    var contactPhone: String?
    var jobDescription: String?
    var estimatedValue: Double?
    var stage: PipelineStage
    var source: String?
    var projectId: String?
    var clientId: String?
    var lossReason: String?
    var createdAt: Date
    var updatedAt: Date
    var lastActivityAt: Date?

    // Email system columns (Supabase only — not in SwiftData model)
    // stage_manually_set BOOLEAN NOT NULL DEFAULT false — true when user manually drags card to new stage;
    //   prevents AI/deterministic stage override. Cleared to false when new inbound email arrives
    //   (situation evolved, AI can re-evaluate)
    // ai_summary         TEXT — 1-2 sentence AI-generated summary of the opportunity, cached and
    //   refreshed each sync cycle that touches the thread via evaluateStagesWithSummary()
    // title              TEXT NOT NULL — deal display title (e.g. "Renata Shoop - Lead").
    //   Not stored in SwiftData (iOS displays via contactName). Web sets explicit title in
    //   create-lead-modal.tsx; iOS sets "{contactName} - Lead" in LogActivityViewModel.save().
    //   Defense-in-depth trigger trg_opportunities_default_title (BEFORE INSERT) auto-fills
    //   title from contact_name when null/empty, falling back to "New Lead".
}
```

**Computed**: `weightedValue`, `daysInStage`, `isStale`.

**Title invariant**: `opportunities.title` is `TEXT NOT NULL`. Every insert path must supply it. A `BEFORE INSERT` trigger (`trg_opportunities_default_title` — migration `add_opportunities_title_default_trigger`) populates it from `contact_name` if a client forgets, so the column constraint never fails an otherwise valid insert. Clients should still send an explicit title to match the human-readable convention used across the product (`"{contactName} - Lead"` for manual creation, `"{fromName} — Email Inquiry"` for email triage).

---

### 13. Activity (Supabase-Backed)

**File**: `DataModels/Supabase/Activity.swift`
**Purpose**: Timeline event per opportunity.

**Properties**:

```swift
@Model
class Activity: Identifiable {
    @Attribute(.unique) var id: String
    var opportunityId: String
    var companyId: String
    var type: ActivityType
    var subject: String?            // mirrors NOT NULL DB column; Optional locally for migration safety
    var body: String?               // maps to DB `content`
    var direction: String?          // 'inbound' | 'outbound', meaningful for call/email
    var outcome: String?            // free-form result, set from Log Activity metadata
    var durationMinutes: Int?       // meaningful for call/meeting
    var createdBy: String?
    var createdAt: Date
    var metadata: String?

    // Email fields (Supabase columns — not in SwiftData model)
    // to_emails       TEXT[] DEFAULT '{}'          — recipient email addresses
    // cc_emails       TEXT[] DEFAULT '{}'          — CC'd email addresses
    // body_text       TEXT                         — full email body (markdown from compose, plain text from sync)
    // has_attachments BOOLEAN NOT NULL DEFAULT false — whether email has attachments
    // attachment_count INT NOT NULL DEFAULT 0      — number of attachments
    // subject         TEXT NOT NULL                — display title for the activity timeline
    //   (web reads as `subject || activityTypeLabel(type)`); for emails this is the actual
    //   email subject, for manually-logged activities a derived label like "Call with {contact}"
    //   or the first line of notes truncated to 100 chars
    // direction       TEXT CHECK ∈ {inbound, outbound} — only meaningful for call/email
    // outcome         TEXT                         — free-form result of the activity
    // duration_minutes INT                          — only meaningful for call/meeting

    // Project Workspace Modal column (Supabase only — added 2026-05-06)
    // attachment_ids  UUID[] DEFAULT ARRAY[]::UUID[] — references to project_photos.id for activity entries with photo attachments.
    //   Distinct from the legacy `attachments` text[] column (free-form URLs/keys). The workspace timeline reads attachment_ids
    //   to resolve thumbnails + URLs reliably without parsing free-form strings. GIN partial index idx_activities_attachments
    //   WHERE array_length(attachment_ids, 1) > 0 covers the populated case.
}
```

**Subject invariant**: `activities.subject` is `TEXT NOT NULL` with no default. Trigger `trg_activities_default_subject` (migration `add_activities_subject_default_trigger`, BEFORE INSERT) auto-fills it as a defense-in-depth measure: first non-empty line of `content` (truncated to 100 chars), else a type-derived label (`Call`, `Note`, `Site visit`, etc.), else `Activity`. Clients should send an explicit `subject` for best UX — iOS Log Activity flow derives `"{first line of notes}"` or `"Call with {contactName}"` style from form state.

**iOS payload (CreateActivityDTO)** sends: `opportunity_id, company_id, type, subject, content, direction (call/email only), outcome (when non-empty), duration_minutes (call/meeting only and >0), created_by`. Other columns rely on Postgres defaults (`is_read`, `match_needs_review`, `has_attachments`, `attachment_count`, `sent_by_agent`, `created_at`).

---

### 14. FollowUp (Supabase-Backed)

**File**: `DataModels/Supabase/FollowUp.swift`
**Purpose**: Scheduled reminder.

**Properties**:

```swift
@Model
class FollowUp: Identifiable {
    @Attribute(.unique) var id: String
    var opportunityId: String
    var companyId: String
    var type: FollowUpType
    var status: FollowUpStatus
    var dueAt: Date
    var assignedTo: String?
    var notes: String?
    var createdAt: Date
}
```

**Computed**: `isOverdue`, `isDueToday`.

---

### 15. StageTransition (Supabase-Backed)

**File**: `DataModels/Supabase/StageTransition.swift`
**Purpose**: Immutable stage history record.

**Properties**:

```swift
@Model
class StageTransition: Identifiable {
    @Attribute(.unique) var id: String
    var opportunityId: String
    var fromStage: PipelineStage
    var toStage: PipelineStage
    var changedBy: String?
    var createdAt: Date
}
```

---

### 16. Estimate (Supabase-Backed)

**File**: `DataModels/Supabase/Estimate.swift`
**Purpose**: Quote document.

**Properties**:

```swift
@Model
class Estimate: Identifiable {
    @Attribute(.unique) var id: String
    var companyId: String
    var estimateNumber: String
    var status: EstimateStatus
    var clientId: String?
    var projectId: String?
    var opportunityId: String?
    var title: String?
    var clientMessage: String?
    var internalNotes: String?
    var taxRate: Double
    var discountPercent: Double
    var subtotal: Double
    var taxAmount: Double
    var total: Double
    var validUntil: Date?
    var sentAt: Date?
    var version: Int
    var parentId: String?
    var createdAt: Date
    var updatedAt: Date
}
```

---

### 17. EstimateLineItem (Supabase-Backed)

**File**: `DataModels/Supabase/EstimateLineItem.swift`
**Purpose**: Line item on an estimate.

**Properties**:

```swift
@Model
class EstimateLineItem: Identifiable {
    @Attribute(.unique) var id: String
    var estimateId: String
    var productId: String?
    var name: String
    var itemDescription: String?
    var type: LineItemType
    var quantity: Double
    var unit: String?
    var unitPrice: Double
    var discountPercent: Double
    var taxable: Bool
    var optional: Bool
    var lineTotal: Double
    var displayOrder: Int
    var taskTypeId: String?
    var createdAt: Date
}
```

---

### 18. Invoice (Supabase-Backed)

**File**: `DataModels/Supabase/Invoice.swift`
**Purpose**: Billing document.

**Properties**:

```swift
@Model
class Invoice: Identifiable {
    @Attribute(.unique) var id: String
    var companyId: String
    var invoiceNumber: String
    var status: InvoiceStatus
    var clientId: String?
    var projectId: String?
    var opportunityId: String?
    var estimateId: String?
    var title: String?
    var subtotal: Double
    var taxAmount: Double
    var total: Double
    var amountPaid: Double
    var balanceDue: Double
    var taxRate: Double
    var dueDate: Date?
    var sentAt: Date?
    var paidAt: Date?
    var createdAt: Date
    var updatedAt: Date
}
```

**Computed**: `isOverdue` -- checks `balanceDue > 0 && due < Date() && status != .void`.

---

### 19. InvoiceLineItem (Supabase-Backed)

**File**: `DataModels/Supabase/InvoiceLineItem.swift`
**Purpose**: Line item on an invoice.

**Properties**:

```swift
@Model
class InvoiceLineItem: Identifiable {
    @Attribute(.unique) var id: String
    var invoiceId: String
    var name: String
    var itemDescription: String?
    var type: LineItemType
    var quantity: Double
    var unit: String?
    var unitPrice: Double
    var lineTotal: Double
    var displayOrder: Int
    var createdAt: Date
}
```

---

### 20. Payment (Supabase-Backed)

**File**: `DataModels/Supabase/Payment.swift`
**Purpose**: Payment record (insert-only).

**Properties**:

```swift
@Model
class Payment: Identifiable {
    @Attribute(.unique) var id: String
    var invoiceId: String
    var companyId: String
    var amount: Double
    var method: PaymentMethod
    var paidAt: Date
    var notes: String?
    var voidedAt: Date?
    var voidedBy: String?
    var createdAt: Date
}
```

**Computed**: `isVoided` -- `voidedAt != nil`.

---

### 21. Product (Supabase-Backed)

**File**: `DataModels/Supabase/Product.swift`
**Purpose**: Billable line-item template (Stripe/Shopify "product"). Two tiers of richness:
- **Barebones**: `name + basePrice + pricingUnit + taxable` is one form-fill away.
- **Configurable**: carries `ProductOption`/`ProductOptionValue`/`ProductPricingModifier`/`ProductMaterial` rows that drive the iOS resolver (price snapshot) and `CutListMaterializer` (recipe → `task_materials`).

**Properties**:

```swift
@Model
class Product: Identifiable {
    @Attribute(.unique) var id: String
    var companyId: String
    var name: String
    var productDescription: String?
    var type: LineItemType                 // LABOR | MATERIAL | OTHER (load-bearing classifier)
    var kind: ProductKind                  // .service | .good | .package
    var basePrice: Double                  // primary unit price column (was `default_price`)
    var unitCost: Double?
    var pricingUnit: ProductPricingUnit    // .each | .flatRate | .linearFoot | .sqft | .hour | .day
    var unit: String?                      // legacy free-text unit (kept for back-compat)
    var category: String?                  // legacy free-text category (kept for back-compat)
    var categoryId: String?                // FK catalog_categories.id; authoritative going forward
    var sku: String?
    var taxable: Bool
    var isActive: Bool
    var isFavorite: Bool
    var minimumCharge: Double?
    var minimumQuantity: Double?
    var showBomOnEstimate: Bool
    var showInStorefront: Bool
    var tieredPricingJSON: String?         // raw jsonb passthrough
    var taskTypeId: String?
    var taskTypeRef: String?
    var unitId: String?                    // FK catalog_units.id
    var linkedCatalogItemId: String?       // FK catalog_items.id (added 2026-05-10, bug 164e0595)
    var bundlePricingMode: String?         // 'auto' | 'override' | nil — only set when kind=.package (added 2026-05-10, bugs e0229b57/41d6f2b4)
    var createdAt: Date

    /// Derived user-facing 4-way taxonomy.
    var category3Way: ProductCategory {
        ProductCategory.from(type: type, kind: kind)
    }
}

enum ProductPricingUnit: String, CaseIterable, Codable {
    case each
    case flatRate     = "flat_rate"
    case linearFoot   = "linear_foot"
    case sqft
    case hour
    case day
}

enum ProductKind: String, CaseIterable, Codable {
    case service
    case good     // wire value "material" — Swift case is legacy
    case package  // surfaces as user-facing "Bundle"
}

/// User-facing 4-way taxonomy (added 2026-05-10, bug 164e0595). Replaces
/// the iOS two-axis confusion of Kind + LineItemType on entry forms. Save
/// derives both legacy columns from this so old App Store iOS builds and
/// the web app keep reading sensible values.
enum ProductCategory: String, CaseIterable, Codable, Identifiable {
    case service      // wire: kind=service, type=LABOR    — labor / time / expertise
    case material     // wire: kind=material, type=MATERIAL — physical product
    case fee          // wire: kind=service, type=OTHER    — permit / disposal / passthrough
    case bundle       // wire: kind=package, type=OTHER    — services + goods sold as one
}
```

**Computed**: `marginPercent` -- `((basePrice - unitCost) / basePrice) * 100`.

**Wire-field fix (Phase 3)**: earlier builds wrote `unit_price`/`cost_price` — columns that **do not exist** in Supabase. The DTO now correctly reads/writes `base_price`/`unit_cost`. `base_price` is the new primary column. The legacy `default_price` column is preserved and kept in sync via a Postgres trigger (migration `2026-05-06-02-catalog-views-triggers.sql`) until ops-web cuts over to `base_price`; the trigger and `default_price` are removed in that follow-up session.

**Catalog FKs (added 2026-05-08)**: `unit_id uuid REFERENCES catalog_units(id) ON DELETE SET NULL` and `category_id uuid REFERENCES catalog_categories(id) ON DELETE SET NULL` link Products into the same catalog backbone Stock uses. The legacy `unit` and `category` text columns stay in place for backwards compat — new writes (both create and edit, on iOS and ops-web) populate the FK **and** the legacy text column so reads from either path see the same vocabulary. An iOS-only backfill (`OPS/Migrations/2026-05-08-backfill-products-category-id.sql`) walks existing rows and sets `category_id` from the matching `catalog_categories` row by case-insensitive name within the same company.

**Stock link FK (added 2026-05-10, bug 164e0595)**: `linked_catalog_item_id uuid REFERENCES catalog_items(id) ON DELETE SET NULL` ties a Material-category Product to a stock-tracked inventory family. Set from the iOS New Product sheet's `// SHOW IN STOCK` toggle, which either picks an existing `catalog_items` row or auto-creates one (plus a default `catalog_variants` row) via `CatalogRepository.createDefaultItemForProduct`. **Auto-deduction on sale is not yet wired** — that's P1-28's scope. The column is present so P1-28 can deliver it without further iOS work. Old App Store iOS builds neither read nor write the column, so back-compat is preserved.

**Taxonomy redesign on the New Product sheet (added 2026-05-10, bug 164e0595)**: the legacy iOS form forced two overlapping pickers — `Kind` (Service/Good) and `Line item type` (Labor/Material/Other). Live data showed the pair was always redundant (`service+LABOR` or `material+MATERIAL`) and defaults disagreed (`kind=service` but `type=other`). The new form replaces both with a single 4-way `ProductCategory` picker (Service / Material / Fee / Bundle). Save derives `kind` + `type` from the choice per the mapping above. The legacy iOS columns and the web app continue to read sensible values without any client-side change.

**Kind-first create flow (added 2026-05-10, bugs e0229b57 / 41d6f2b4)**: a follow-up redesign of the same surface replaced the single `QuickAddProductSheet` with a **kind-first flow** — the PRODUCTS-segment FAB now opens `ProductKindPickerSheet` (three cards: SERVICE / GOOD / BUNDLE), which routes to one of three kind-tailored sheets:

- `NewServiceSheet` — kind locked to `.service`, default pricing unit `.hour`, no unit cost / no margin / no thumbnail
- `NewGoodSheet` — kind locked to `.good` (DB `material`), default `.each`, unit cost + live margin + thumbnail + SHOW IN STOCK toggle
- `NewBundleSheet` — kind locked to `.package`, inline child picker drawer + selected-children stepper list + AUTO/OVERRIDE pricing

`QuickAddProductSheet.swift` is **deleted**. Shared form components extracted to `OPS/Views/Catalog/Products/Shared/` (CategoryPickerField, UnitPickerField, ThumbnailPickerField). See `OPS/Views/Catalog/Products/{ProductKindPickerSheet,NewServiceSheet,NewGoodSheet,NewBundleSheet}.swift`.

#### Configurable Products (NEW)

Four extension models, all in `OPS/DataModels/Supabase/Catalog/`, drive the configurable layer. Each is empty by default — a "barebones" Product has zero rows in every layer and behaves identically to the original flat product.

- **`ProductOption`** — a configuration knob (e.g., "Mount Type", "Color", "Corners"). Has `kind` ∈ {`select`, `integer`, `boolean`}, `affectsPrice`/`affectsRecipe` flags, optional `defaultValue`, and `optionDefaultSource` ("$design.color", "$design.mount_type", …) used by the drawing→estimate adapter.
- **`ProductOptionValue`** — selectable values for `kind = .select` options.
- **`ProductPricingModifier`** — bumps unit price when an option matches a trigger. `modifierKind` ∈ {`add_per_unit`, `add_flat`, `add_per_count`, `multiply_unit_price`}; trigger by `triggerValueId` (select) or `triggerIntMin`/`triggerIntMax` (integer).
- **`ProductMaterial`** — recipe row. Either pinned to a `catalogVariantId` (specific SKU) or pinned to a `catalogItemId` (family head) with a `variantSelectorJSON` like `{"color":"$option.color","mount":"$option.mount_type"}`. `quantityPerUnit` is per Product's `pricingUnit`; `scaledByOptionId` lets a row scale by an integer-kind option (e.g., corner hardware kits scaled by Corners count). Family pins and variant pins are mutually exclusive (CHECK constraint).

Resolver flow:

1. **Estimate-line creation** — `ProductConfigurationResolver` reads the product's options + modifiers + the user's choices, computes `resolved_unit_price`, snapshots `configured_options` jsonb + `resolved_options_label` to the line item. Pricing is frozen at this moment.
2. **Install-task creation** — `RecipeResolver` walks `product_materials`, applies `configured_options` to family-pinned rows via `variantSelectorJSON`, multiplies by quantity (and `scaledByOptionId` if present), emits `task_materials` rows pinned to specific `catalog_variants`. The cut list materializes here, not at estimate time.

#### Authoring surface (Web)

The configurable layer is read-only on iOS. Authoring lives in OPS-Web at:

- **Route**: `/products/[id]/options` (deep-link from the product list and product edit modal)
- **Permission**: `products.manage`
- **Sections**:
  - **Options** — list of `product_options` rows with drag-reorder (`sort_order`), inline edit, hard delete with confirmation. Modal handles create/edit including the `kind`/`affectsPrice`/`affectsRecipe`/`required`/`defaultValue`/`optionDefaultSource` fields. For `kind = select`, the modal also exposes the nested `product_option_values` editor (add / rename / drag-reorder / delete).
  - **Pricing modifiers** — list of `product_pricing_modifiers` rendered as humanized rules (e.g. "When Color = Red → +$5.00 per unit"). Modal handles create/edit with an option picker, kind-aware trigger (value picker, integer min/max range, or implicit-when-true for boolean), modifier-kind segmented control, and amount input with live preview.
- **Services**: `ProductOptionsService` and `ProductPricingModifiersService` in `src/lib/api/services/`. RLS enforces company isolation through the parent product (existing policies — no new RLS).
- **Hooks**: `useProductOptions`, `useProductOptionValues`, `useProductPricingModifiers` and the matching `useCreate*` / `useUpdate*` / `useDelete*` / `useReorder*` mutations in `src/lib/hooks/`.

The iOS new-product sheets (NewServiceSheet / NewGoodSheet) include a footer pointing users to the web for Options + Pricing modifiers; once a product is created on iOS, the operator opens it on web to author the configurable layer.

#### Bundles (added 2026-05-10, bugs e0229b57 / 41d6f2b4)

A **bundle** is a product with `kind='package'` (the third value of the existing `products_kind_check` CHECK constraint, which already accepted `service | material | package`). A bundle composes other products (services + goods) into a single sellable line item with one of two pricing modes.

**Composition table — `product_bundle_items`**:

```sql
CREATE TABLE public.product_bundle_items (
  id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id          uuid NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
  bundle_product_id   uuid NOT NULL REFERENCES products(id)  ON DELETE CASCADE,
  child_product_id    uuid NOT NULL REFERENCES products(id)  ON DELETE RESTRICT,
  quantity            numeric NOT NULL DEFAULT 1 CHECK (quantity > 0),
  display_order       int     NOT NULL DEFAULT 0,
  created_at          timestamptz NOT NULL DEFAULT now(),
  updated_at          timestamptz NOT NULL DEFAULT now(),
  deleted_at          timestamptz NULL,
  CONSTRAINT no_self_reference CHECK (bundle_product_id <> child_product_id)
);
```

Indexes on `bundle_product_id`, `child_product_id`, `company_id` (all partial `WHERE deleted_at IS NULL`). RLS: single `company_isolation` policy matching the existing pattern on `products` / `product_materials` — `company_id = (SELECT private.get_user_company_id())`. Permission gating (`catalog.products.manage`) lives in iOS/web permission_store before mutation, not in RLS.

**Pricing mode — `products.bundle_pricing_mode`**:

Nullable text column on `products`, CHECK `bundle_pricing_mode IS NULL OR bundle_pricing_mode IN ('auto', 'override')`. NULL for non-bundles.

- `auto` — bundle's `base_price` is rewritten on save as `Σ(child.base_price × quantity)`. The UI shows the rolled total read-only.
- `override` — bundle's `base_price` is whatever the user typed; the rolled sum and a live margin percent ((override − rolled) / override × 100) are shown alongside for awareness but don't overwrite.

**Constraints**:
- `no_self_reference` CHECK: a bundle cannot include itself as a child.
- **Bundle nesting (bundles whose children include another bundle) is disallowed for v1 in the iOS UI** — the child picker drawer filters out `kind='package'` products. Not enforced at the DB; defer to v2 if a real need emerges.

**iOS surfaces**:
- `ProductBundleItem` SwiftData @Model (`DataModels/Supabase/Catalog/ProductBundleItem.swift`) — local cache with `lastSyncedAt` + `needsSync` per the standard sync pattern.
- `ProductBundleItemRepository` — fetch / create / update / soft-delete.
- `NewBundleSheet` — full create flow (V4 hybrid layout: inline child picker drawer + selected-children list with integer steppers + AUTO/OVERRIDE pricing segmented control).
- `BundleCompositionEditSheet` — diff-based edit of an existing bundle's children.
- `BundleCompositionReadOnlyView` — embedded in `ProductDetailView` when `kind == .package`, replaces the recipe section.
- `InboundProcessor.syncProductBundleItems` — pulls server rows, preserves pending local edits via `needsSync` guard, reconciles deletions scoped to the company's product space.
- `SyncEntityType.productBundleItem` — priority 13, alongside other product-richness tables.

**Old-iOS degradation**: pre-bundle App Store builds decode `kind='package'` via the existing `?? .service` fallback in `ProductDTO.toModel()` (line 81). They render bundles as regular service products — billable on estimates as a single line item, but the composition is invisible. `UpdateProductDTO` is sparse and the iOS detail view never exposes a `kind` picker, so old clients cannot clobber `kind='package'` on edit. Verified by reading the codebase at spec time; documented in `docs/superpowers/specs/2026-05-10-products-services-bundles-design.md`.

**Coupling (deferred — tracked as P1-22 follow-up)**:
- Estimate / Invoice bundle expansion on the line item (uses existing `show_bom_on_estimate` flag — web concern).
- `CutListMaterializer` recursive expansion when a task is linked to a bundle product.

**Reverse stock→product link (added 2026-05-10, same bugs)**: `VariantDetailView` (Stock segment) now shows a **USED IN** section listing every product whose recipe (`product_materials`) references this variant **or** whose `linked_catalog_item_id` points at the variant's family. Each row taps through to `ProductDetailView`. Closes the discoverability gap that previously left the stock→product relationship one-way.

---

### 22. SiteVisit (Supabase-Backed)

**File**: `DataModels/Supabase/SiteVisit.swift`
**Purpose**: Scope assessment visit.

**Properties**:

```swift
@Model
class SiteVisit: Identifiable {
    @Attribute(.unique) var id: String
    var opportunityId: String
    var companyId: String
    var status: SiteVisitStatus
    var scheduledAt: Date?
    var completedAt: Date?
    var notes: String?
    var address: String?
    var assignedTo: String?
    var createdAt: Date
}
```

---

### 23. ProjectNote (Supabase-Backed)

**File**: `DataModels/Supabase/ProjectNote.swift`
**Purpose**: Per-project message board note with @mentions and attachments.

**Properties**:

```swift
@Model
class ProjectNote: Identifiable {
    @Attribute(.unique) var id: String
    var projectId: String
    var companyId: String
    var authorId: String
    var content: String
    var attachmentsJSON: String              // JSON array of URL strings
    var mentionedUserIdsString: String       // Comma-separated user IDs
    var createdAt: Date
    var updatedAt: Date?
    var deletedAt: Date?

    var lastSyncedAt: Date?
    var needsSync: Bool = false
}
```

**Computed Accessors**: `mentionedUserIds: [String]` (get/set), `attachments: [String]` (get/set via JSON).

---

### 24. PhotoAnnotation (Supabase-Backed)

**File**: `DataModels/Supabase/PhotoAnnotation.swift`
**Purpose**: Drawing overlay and text note for a project photo.

**Properties**:

```swift
@Model
class PhotoAnnotation: Identifiable {
    @Attribute(.unique) var id: String
    var projectId: String
    var companyId: String
    var photoURL: String
    var annotationURL: String?
    var note: String
    var authorId: String
    var createdAt: Date
    var updatedAt: Date?
    var deletedAt: Date?

    var lastSyncedAt: Date?
    var needsSync: Bool = false
    var localDrawingData: Data?              // PKDrawing data for offline editing
}
```

---

### 25. CalendarUserEvent (Supabase-Backed)

**File**: `DataModels/Supabase/CalendarUserEvent.swift`
**Purpose**: User-owned calendar events — personal events (birthdays, appointments) and time-off requests requiring admin approval. Separate from project-linked CalendarEvents.

**Properties**:

```swift
@Model
class CalendarUserEvent: Identifiable {
    @Attribute(.unique) var id: String
    var userId: String
    var companyId: String
    var type: String                 // CalendarUserEventType.rawValue: "personal" | "time_off"
    var title: String
    var startDate: Date
    var endDate: Date
    var allDay: Bool
    var notes: String?
    var status: String               // CalendarUserEventStatus.rawValue: "confirmed" | "pending" | "approved" | "rejected"
    var reviewedBy: String?          // User ID of admin who reviewed time-off request
    var reviewedAt: Date?
    var createdAt: Date
    var updatedAt: Date?
    var deletedAt: Date?

    var lastSyncedAt: Date?
    var needsSync: Bool = false
}
```

**Supporting Enums**:
```swift
enum CalendarUserEventType: String, Codable {
    case personal = "personal"
    case timeOff = "time_off"
}

enum CalendarUserEventStatus: String, Codable {
    case confirmed = "confirmed"   // No approval needed (personal events)
    case pending = "pending"       // Time-off awaiting admin review
    case approved = "approved"
    case rejected = "rejected"
}
```

**Key Computed Properties**:
- `eventType: CalendarUserEventType` — typed accessor for `type` string
- `eventStatus: CalendarUserEventStatus` — typed accessor for `status` string
- `isTimeOff: Bool`, `isPersonal: Bool`, `isPending: Bool`
- `overlaps(date:) -> Bool` — used by calendar views to show events on relevant days

**Business Rules**:
- Personal events: `status` is set to `.confirmed`, no approval workflow
- Time-off requests: created as `.pending`, admin approves (`.approved`) or rejects (`.rejected`)
- Only the owning user (`userId`) can create/edit their own events
- Admin can review (approve/deny) time-off requests from any user in their company
- Soft-delete via `deletedAt` (consistent with all Supabase-backed models)

**Supabase Table**: `calendar_user_events`

**RLS Note**: The `calendar_user_events` table uses `CAST(auth.uid() AS TEXT)` in its RLS policies because `users.id` is a UUID type while `calendar_user_events.user_id` is a text column. Standard `auth.uid() = user_id` comparisons fail without the explicit cast.

**Added**: 2026-03-02 (Schedule Tab Redesign)

---

## Subscription Add-ons — `data_setup_requests`

**Added**: 2026-04-29 (Migration `20260429120000_data_setup_requests.sql`, applied to prod via Supabase MCP)
**Purpose**: Operations queue behind the one-time Data Setup add-on. Each Stripe Checkout completion (`mode=payment`, price = `STRIPE_PRICE_DATA_SETUP`) creates a row here for ops to track from purchase through migration.

### Source-of-truth split

The `companies` row holds three Stripe-driven entitlement bits read by the rest of the app:

- `companies.has_priority_support BOOLEAN` — flipped by `customer.subscription.created/updated/deleted` events when the line item is the priority-support price.
- `companies.data_setup_purchased BOOLEAN` — flipped by `checkout.session.completed` when the line item is the data-setup price.
- `companies.data_setup_completed BOOLEAN` + `companies.data_setup_scheduled TIMESTAMPTZ` — admin-managed; reflect the latest non-cancelled `data_setup_requests` row for the company.

The `data_setup_requests` table is the operations log behind those flags. iOS / web reads the entitlement bits from `companies`; ops staff and the Subscription tab (status detail) read the request rows.

### Table

```sql
CREATE TABLE data_setup_requests (
  id                          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id                  UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
  requested_by                UUID NOT NULL REFERENCES users(id),
  status                      TEXT NOT NULL DEFAULT 'pending'
                                CHECK (status IN ('pending','scheduled','in_progress','completed','cancelled')),
  scheduled_at                TIMESTAMPTZ,
  completed_at                TIMESTAMPTZ,
  notes                       TEXT,
  stripe_payment_intent_id    TEXT,           -- unique partial index (defense in depth vs webhook replay)
  amount_paid_cents           INTEGER,
  source_software             TEXT,
  contact_email               TEXT,
  contact_phone               TEXT,
  created_at                  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at                  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
```

### RLS

- `SELECT` — any user in the same company.
- `INSERT` — any user in the same company; webhook bypasses RLS via service role.
- `UPDATE` — admins only (`users.is_company_admin = TRUE`).
- Auth identity matches the existing `/api/auth/join-company` pattern: `users.auth_id = auth.uid()::text` OR `users.firebase_uid = auth.uid()::text`.

### Lifecycle

`pending` → `scheduled` (when ops books a date) → `in_progress` → `completed` (flips `companies.data_setup_completed = true`). `cancelled` covers refunds and admin overrides.

### Stripe price IDs

- `STRIPE_PRICE_DATA_SETUP` — one-time charge, `mode=payment`.
- `STRIPE_PRICE_PRIORITY_SUPPORT_MONTHLY` / `STRIPE_PRICE_PRIORITY_SUPPORT_ANNUAL` — recurring, `mode=subscription`.
- Mapping helpers live in `OPS-Web/src/lib/stripe/subscription-mapping.ts`: `ADDON_PRICE_MAP`, `addonFromPriceId()`, `isPrioritySupportPrice()`. The webhook routes off these helpers.

---

## Project Workspace Modal Tables (Web-Only)

**Added**: 2026-05-06 (migrations `20260506120000_project_site_metadata` through `20260506120400_weather_forecasts`, plus rollback `20260506140000_rollback_unused_project_fields`)
**Purpose**: Schema additions powering the unified `ProjectWorkspace` modal in OPS-Web (replaces the legacy `project-detail-modal` / `project-detail-sheet` / `create-project-modal` / `edit-project-modal` / `project-detail-popover` / `[id]` route page surfaces). All additions are web-only and not mirrored in the iOS SwiftData store.

> **Scope cut (2026-05-06 design review)** — `scope`, `site_notes`, `gate_code`, `site_conditions`, `color`, `buffer_days` columns and the `project_tags` / `project_tag_assignments` tables were dropped via migration `20260506140000_rollback_unused_project_fields.sql` after the design review collapsed the SITE card, the Context tab, and the user-picked color into status-driven chrome. Status hex drives all chrome (no `color`); buffer is a future derived value from task scheduling; `description` covers what `scope` was meant to. Re-add tags only when filter/saved-view features actually require them.

### `projects.visibility` (Migration `20260506120000`, only surviving column)

- `visibility TEXT DEFAULT 'all' CHECK ∈ {all, office, private}` — portal exposure. `private` projects do not appear in the client portal. Partial index `idx_projects_visibility ON projects(visibility) WHERE visibility != 'all'` covers the office/private filter on company dashboards.

### `clients` / `opportunities` lat/lng (Migration `20260506120200`)

```sql
ALTER TABLE clients       ADD COLUMN IF NOT EXISTS latitude DOUBLE PRECISION, ADD COLUMN IF NOT EXISTS longitude DOUBLE PRECISION;
ALTER TABLE opportunities ADD COLUMN IF NOT EXISTS latitude DOUBLE PRECISION, ADD COLUMN IF NOT EXISTS longitude DOUBLE PRECISION;
CREATE INDEX idx_clients_geo       ON clients       (latitude, longitude) WHERE latitude IS NOT NULL AND longitude IS NOT NULL;
CREATE INDEX idx_opportunities_geo ON opportunities (latitude, longitude) WHERE latitude IS NOT NULL AND longitude IS NOT NULL;
```

`clients` already had these columns in production — the `IF NOT EXISTS` guards make the migration a safe no-op there. `opportunities` gains lat/lng for the first time so the workspace map can fall back to opportunity coordinates when a project lacks them. Mapbox Geocoding populates both on address change.

### `activities.attachment_ids` (Migration `20260506120300`)

Documented inline on the `Activity` SwiftData model (Section 13) as a Supabase-only column. Distinct from the legacy `attachments` text[] column. GIN partial index covers populated entries.

### `weather_forecasts` (Migration `20260506120400`)

Cached Open-Meteo forecasts per project. Refreshed via the weather route handler when entries age past 12h. Attribution to Open-Meteo.com is required by their courtesy policy and embedded in the table comment.

```sql
CREATE TABLE weather_forecasts (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  project_id      UUID NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
  company_id      UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
  forecast_date   DATE NOT NULL,
  temp_high_c     NUMERIC(4,1),
  temp_low_c      NUMERIC(4,1),
  temp_current_c  NUMERIC(4,1),
  precipitation_mm           NUMERIC(5,2),
  precipitation_probability  SMALLINT CHECK (precipitation_probability BETWEEN 0 AND 100),
  wind_speed_kmh  NUMERIC(5,1),
  conditions      TEXT,
  retrieved_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  source          TEXT NOT NULL DEFAULT 'open-meteo',
  UNIQUE (project_id, forecast_date)
);
CREATE INDEX idx_weather_project_date ON weather_forecasts(project_id, forecast_date);
CREATE INDEX idx_weather_retrieved_at ON weather_forecasts(retrieved_at);
```

**RLS** — `SELECT` scoped to the requesting company via `private.get_user_company_id()`. Writes (`INSERT`/`UPDATE`/`DELETE`) require `auth.role() = 'service_role'` — only the Next.js weather route handler (using `SUPABASE_SERVICE_ROLE_KEY`) can refresh the cache. Service role bypasses RLS, but the explicit `service_role` policies are kept for intent clarity if the role surface ever changes.

### `project_notes.event_kind` + `project_notes.content_metadata` (Migration `20260507130000_project_notes_event_kind`)

Inverts the unified-timeline consolidation direction. Originally the workspace was going to migrate `project_notes` rows into the `activities` table; that direction would have required iOS schema changes that break sync between App Store releases. Instead, `project_notes` becomes the iOS-canonical timeline source for the workspace's Activity tab — system events written by web (status changes, estimate sent, payment received, photo uploaded, etc.) are inserted as `project_notes` rows tagged with `event_kind`, alongside user-authored notes (where `event_kind IS NULL`).

```sql
ALTER TABLE project_notes
  ADD COLUMN IF NOT EXISTS event_kind TEXT,
  ADD COLUMN IF NOT EXISTS content_metadata JSONB;

CREATE INDEX idx_project_notes_event_kind
  ON project_notes(project_id, event_kind, created_at DESC)
  WHERE event_kind IS NOT NULL;
```

**iOS-additive contract** — both columns are nullable, no `CHECK`, default `NULL`. Existing rows are untouched. The current iOS Codable types decode unknown columns gracefully, and rows with `event_kind` set still have a populated `content` field, so they render on iOS as plain notes (slightly weird visually, fixed in the next iOS release). No iOS schema migration is required during the workspace rollout.

**`event_kind` discriminator values** — `status_change`, `estimate_sent`, `estimate_approved`, `estimate_declined`, `invoice_sent`, `payment_received`, `expense_logged`, `photo_uploaded`, `project_created`, `project_archived`, `task_completed`. `NULL` = user-authored note (default). The web `useProjectActivity` hook maps `NULL` to the `kind: 'note'` enum branch and uses non-null values to dispatch icon / color / dot styling on the timeline.

**`content_metadata` payload shapes** — JSONB blob keyed by event kind. Examples:

| Event kind | Payload |
|---|---|
| `status_change` | `{ "from": "Accepted", "to": "InProgress" }` |
| `estimate_sent` | `{ "estimateId": "<uuid>", "estimateNumber": "EST-00128", "total": 12450 }` |
| `estimate_approved` | `{ "estimateId": "<uuid>", "estimateNumber": "EST-00128" }` |
| `payment_received` | `{ "paymentId": "<uuid>", "amount": 5000, "method": "etransfer" }` |
| `invoice_sent` | `{ "invoiceId": "<uuid>", "invoiceNumber": "INV-00284", "total": 9800 }` |
| `expense_logged` | `{ "expenseId": "<uuid>", "amount": 184.5, "vendor": "..." }` |
| `photo_uploaded` | `{ "photoId": "<uuid>", "url": "..." }` |
| `project_created` | `{}` |
| `project_archived` | `{}` |
| `task_completed` | `{ "taskId": "<uuid>", "title": "..." }` |

**Write paths** — `ProjectLifecycleService.onProjectStageChange` writes `status_change` rows with the `{from, to}` payload. The workspace `useProjectMutations` hook writes `project_created`, `project_archived`, and `photo_uploaded` rows. Estimate / invoice / payment / expense writes happen inside their respective services as those features are wired into the workspace timeline (later phases).

**Read path** — `useProjectActivity` selects `id, content, content_metadata, event_kind, created_at, attachments, mentioned_user_ids, author_id` from `project_notes` ordered by `created_at DESC`, hydrates authors via a follow-up `users` join, and maps each row to a `ProjectActivityEntry` with `kind = event_kind ?? 'note'`. The legacy `activities` table is no longer the primary read source for the workspace timeline.

### `projects.trade` (Migration `20260507140000_projects_trade`)

Adds an optional trade category enum-as-text to projects so the workspace IdentityTab can scope workflow defaults (task templates, weather alert thresholds, default work hours) to the trade.

```sql
ALTER TABLE projects
  ADD COLUMN IF NOT EXISTS trade TEXT;

ALTER TABLE projects
  ADD CONSTRAINT projects_trade_check
  CHECK (trade IS NULL OR trade IN ('roofing', 'hvac', 'plumbing'));
```

**iOS-additive contract** — nullable column, no default, no `NOT NULL`. Existing rows are untouched. iOS `Codable` decoders ignore unknown columns so the prior App Store release continues to sync without modification. iOS will surface the field in a future release.

**Encoding choice — `text + CHECK` rather than `CREATE TYPE`** — extending a Postgres enum requires `ALTER TYPE` which is a stronger schema change. CHECK constraints evolve more cheaply as the trade catalogue grows. Lowercase values match the OPS DB convention (project status, visibility, employee role all follow the same pattern). The workspace UI uppercases for display ("ROOFING" / "HVAC" / "PLUMBING").

**NULL semantics** — `NULL` = unset (legacy projects created before this migration). The IdentityTab leaves the field optional in editing mode for them, required when creating a new project.

### `project_pipeline_summary(p_project_id UUID)` RPC (Migration `20260506130000`)

Single-call aggregate that powers the workspace ACCOUNTING tab's 4-cell pipeline. Returns one row with:

| Column | Type | Source |
|---|---|---|
| `quoted_total` | NUMERIC | `SUM(estimates.total)` where `status = 'approved'` |
| `quoted_record_id` | TEXT | latest approved estimate's `estimate_number` |
| `invoiced_total` | NUMERIC | `SUM(invoices.total)` where `status NOT IN ('void','draft')` |
| `invoiced_record_id` | TEXT | latest non-void/draft invoice's `invoice_number` |
| `change_orders_count` | INT | invoices with `estimate_id IS NOT NULL` created after the project's first invoice |
| `received_total` | NUMERIC | `SUM(payments.amount)` for non-voided payments on this project's invoices |
| `received_record_id` | TEXT | latest non-voided payment's `reference_number` (NULL when blank) |
| `deposit_pct` | INT | `ROUND(received / invoiced * 100)` — NULL when invoiced = 0 |
| `outstanding_total` | NUMERIC | `GREATEST(invoiced - received, 0)` |
| `outstanding_due_date` | DATE | `MIN(due_date)` of invoices with `status NOT IN ('void','paid','draft')` |
| `days_aged` | INT | `EXTRACT(DAY FROM NOW() - MIN(due_date))` of invoices with `status = 'past_due'` — NULL when none |

**Schema notes (load-bearing — required because of mixed UUID/TEXT FKs):**

- `projects.id` is `uuid`. `invoices.project_id` is `uuid` (1:1 type match).
- `estimates.project_id` is `text` (legacy from a prior migration). The RPC casts `p_project_id::TEXT` for the estimates lookup; do not remove this cast.
- `payments` has no `project_id` column — the join goes through `invoices.id`.
- `payments` has no number column. The RPC surfaces `reference_number` as the user-visible identifier; UI should fall back to a generic "Payment" label when null.

**Security** — `LANGUAGE SQL STABLE`, `SECURITY INVOKER` (default), `SET search_path = public, pg_temp`. The function relies on table-level RLS for company scoping — any user that can already `SELECT` from estimates / invoices / payments has the rows it aggregates. `EXECUTE` granted to `authenticated`.

**Soft-deletes** — every CTE filters `deleted_at IS NULL` so soft-deleted records do not contribute to totals.

---

## Permissions System Tables

**Added**: March 2026 (Migration 015 + 016)
**Purpose**: RBAC+ABAC permission system augmenting the 6-role enum (`UserRole`: admin, owner, office, operator, crew, unassigned) with granular per-permission control, replacing ad-hoc boolean flags.

### Architecture Overview

The permissions system uses three Supabase tables and an RPC function to provide granular, role-based access control with scope support:

- **`roles`** — Defines preset and custom roles with a hierarchy
- **`role_permissions`** — Maps each role to specific permissions with scopes
- **`user_roles`** — Assigns one role per user (1:1 mapping)
- **`has_permission()` RPC** — Server-side permission check function

**Four enforcement layers:**
1. **Supabase RLS** — Data-level floor (financial tables only; core operational tables use company isolation only)
2. **Client-side route guard** — Blocks navigation to unauthorized pages (web)
3. **UI gating** — Hides unauthorized UI elements (sidebar, PermissionGate, FAB, tabs)
4. **Server-side API checks** — Guards mutations via `checkPermission()` (web API routes)

### Roles Table

```sql
CREATE TABLE roles (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name        text NOT NULL,
  description text,
  is_preset   boolean DEFAULT false,
  company_id  uuid REFERENCES companies(id) ON DELETE CASCADE,
  hierarchy   integer NOT NULL,  -- 1=Admin (highest), 5=Crew (lowest)
  created_at  timestamptz DEFAULT now(),
  updated_at  timestamptz DEFAULT now(),

  CONSTRAINT roles_unique_name UNIQUE (company_id, name),
  CONSTRAINT roles_preset_no_company CHECK (NOT is_preset OR company_id IS NULL)
);
```

**5 Preset Roles (fixed UUIDs, `is_preset=true`, `company_id=NULL`):**

| UUID | Name | Hierarchy | Description |
|------|------|-----------|-------------|
| `00000000-0000-0000-0000-000000000001` | Admin | 1 | Full system access including billing and roles |
| `00000000-0000-0000-0000-000000000002` | Owner | 2 | Full access, company settings and integrations |
| `00000000-0000-0000-0000-000000000003` | Office | 3 | Office staff, full project and financial access |
| `00000000-0000-0000-0000-000000000004` | Operator | 4 | Lead tech, quotes jobs, manages assigned work |
| `00000000-0000-0000-0000-000000000005` | Crew | 5 | Basic field access, view assigned work only |

**Custom roles**: Companies can create custom roles (`is_preset=false`, `company_id` set). Custom roles cannot use the same name as preset roles within the same company. Preset roles cannot be edited or deleted.

### Role Permissions Table

```sql
CREATE TABLE role_permissions (
  role_id     uuid REFERENCES roles(id) ON DELETE CASCADE,
  permission  app_permission NOT NULL,  -- enum of ~59 dot-notation permissions
  scope       permission_scope DEFAULT 'all',  -- enum: 'all', 'assigned', 'own'

  PRIMARY KEY (role_id, permission)
);
```

### User Roles Table

```sql
CREATE TABLE user_roles (
  user_id     uuid PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
  role_id     uuid NOT NULL REFERENCES roles(id) ON DELETE RESTRICT,
  assigned_at timestamptz DEFAULT now(),
  assigned_by uuid REFERENCES users(id)
);
```

**One role per user** — the `user_id` is the primary key, enforcing a 1:1 relationship.

### Permission Enums

```sql
CREATE TYPE app_permission AS ENUM (
  -- Core Operations (20)
  'projects.view', 'projects.create', 'projects.edit', 'projects.delete',
  'projects.archive', 'projects.assign_team',
  'tasks.view', 'tasks.create', 'tasks.edit', 'tasks.delete',
  'tasks.assign', 'tasks.change_status',
  'clients.view', 'clients.create', 'clients.edit', 'clients.delete',
  'calendar.view', 'calendar.create', 'calendar.edit', 'calendar.delete',
  'job_board.view', 'job_board.manage_sections',
  -- Financial (22)
  'estimates.view', 'estimates.create', 'estimates.edit', 'estimates.delete', 'estimates.send', 'estimates.convert',
  'invoices.view', 'invoices.create', 'invoices.edit', 'invoices.delete',
  'invoices.send', 'invoices.record_payment', 'invoices.void',
  'pipeline.view', 'pipeline.manage', 'pipeline.configure_stages',
  'products.view', 'products.manage',
  'expenses.view', 'expenses.create', 'expenses.edit', 'expenses.delete', 'expenses.approve', 'expenses.configure',
  'accounting.view', 'accounting.manage_connections',
  -- Resources (8)
  'inventory.view', 'inventory.manage', 'inventory.import',
  'photos.view', 'photos.upload', 'photos.annotate', 'photos.delete',
  'documents.view', 'documents.manage_templates',
  -- People & Location (7)
  'team.view', 'team.manage', 'team.assign_roles',
  'map.view', 'map.view_crew_locations',
  'notifications.view', 'notifications.manage_preferences',
  -- Email Integration (4)
  'email.connect', 'email.view', 'email.manage', 'email.configure_ai',
  -- Admin (7)
  'settings.company', 'settings.billing', 'settings.integrations', 'settings.preferences',
  'portal.view', 'portal.manage_branding',
  'reports.view'
);

CREATE TYPE permission_scope AS ENUM ('all', 'assigned', 'own');
```

### Scope Hierarchy

Scopes follow a containment hierarchy: `all` > `assigned` > `own`.

- **`all`** — Can perform the action on any record in the company
- **`assigned`** — Can only perform the action on records the user is assigned to (team member on project)
- **`own`** — Can only perform the action on records the user created/owns

Having scope `all` automatically satisfies checks for `assigned` and `own`. Having `assigned` satisfies `own`.

### Preset Role Permission Summary

| Permission | Admin | Owner | Office | Operator | Crew |
|-----------|-------|-------|--------|----------|------|
| projects.view | all | all | all | all | **assigned** |
| projects.create | all | all | all | all | — |
| projects.edit | all | all | all | **assigned** | — |
| projects.delete | all | all | — | — | — |
| tasks.view | all | all | all | all | **assigned** |
| tasks.create | all | all | all | all | — |
| tasks.edit | all | all | all | **assigned** | **assigned** |
| tasks.change_status | all | all | all | **assigned** | **assigned** |
| clients.view | all | all | all | all | **assigned** |
| clients.create | all | all | all | all | — |
| pipeline.view | all | all | all | — | — |
| estimates.view | all | all | all | all | — |
| estimates.convert | all | all | all | — | — |
| invoices.view | all | all | all | all | — |
| invoices.void | all | all | all | — | — |
| expenses.view | all | all | all | **own** | **own** |
| expenses.delete | all | all | all | **own** | **own** |
| expenses.approve | all | all | all | — | — |
| expenses.configure | all | all | all | — | — |
| inventory.view | all | all | all | — | — |
| team.assign_roles | all | — | — | — | — |
| settings.company | all | all | — | — | — |
| settings.billing | all | — | — | — | — |
| map.view_crew_locations | all | all | all | — | — |

*This is a subset — see migration 015 for the complete permission grants per role.*

**Scope expansions (added March 2026):**
- `expenses.approve`: now supports `assigned` scope (approve expenses on assigned projects)
- `pipeline.manage`: now supports `own` scope (manage own pipeline deals)

### has_permission() RPC Function

The production function accepts **`text`** for both the permission name and scope — not the `app_permission` / `permission_scope` enums the original 015 draft called for. The actually-deployed migration (`20260303054857 create_roles_and_permissions`) stored `role_permissions.permission` as `text`, and the v2 inbox permissions (migration 072, 2026-04-20) insert string values directly against that text column. Migration 075 (2026-04-20) creates the RPC server-side callers rely on — a predecessor with the enum signature never existed in prod, which caused every `checkPermissionById` call to return 403 until 075 landed.

```sql
CREATE OR REPLACE FUNCTION public.has_permission(
  p_user_id        uuid,
  p_permission     text,
  p_required_scope text DEFAULT 'all'
) RETURNS boolean
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = 'public', 'pg_temp'
AS $$
DECLARE
  v_is_admin boolean;
  v_scope    text;
BEGIN
  IF p_user_id IS NULL OR p_permission IS NULL THEN
    RETURN false;
  END IF;

  -- 1. Admin / account-holder / company-admin bypass (mirrors the client
  --    PermissionStore and private.current_user_is_admin).
  SELECT EXISTS (
    SELECT 1
    FROM public.users u
    LEFT JOIN public.companies c ON c.id = u.company_id
    WHERE u.id = p_user_id
      AND u.deleted_at IS NULL
      AND (
        COALESCE(u.is_company_admin, false)
        OR u.id::text = c.account_holder_id
        OR u.id::text = ANY(COALESCE(c.admin_ids, ARRAY[]::text[]))
      )
  ) INTO v_is_admin;
  IF v_is_admin THEN RETURN true; END IF;

  -- 2. Role-based scope lookup (widest scope wins).
  SELECT rp.scope
  INTO v_scope
  FROM public.user_roles ur
  JOIN public.role_permissions rp ON rp.role_id = ur.role_id
  WHERE ur.user_id = p_user_id::text            -- user_roles.user_id is text
    AND rp.permission = p_permission
  ORDER BY CASE rp.scope
    WHEN 'all' THEN 1
    WHEN 'assigned' THEN 2
    WHEN 'own' THEN 3
    ELSE 4
  END
  LIMIT 1;

  IF v_scope IS NULL THEN RETURN false; END IF;

  -- 3. Scope hierarchy check.
  IF v_scope = 'all' THEN RETURN true; END IF;
  IF v_scope = 'assigned' THEN
    RETURN p_required_scope IN ('assigned', 'own');
  END IF;
  IF v_scope = 'own' THEN
    RETURN p_required_scope = 'own';
  END IF;

  RETURN false;
END;
$$;
```

**Callers:**
- Server: `checkPermissionById(userId, permission, requiredScope?)` in
  `OPS-Web/src/lib/supabase/check-permission.ts`. Fail-closed with
  structured error logging on RPC failure.
- RLS: `private.current_user_has_permission(text, text)` for the same
  logic in an `auth.uid()`-scoped context. Used in policies.

### RLS on Permission Tables

Permission tables have their own RLS policies:
- **Read**: All authenticated users can read preset roles and their own company's custom roles
- **Write**: Only users with `team.assign_roles` permission can create/modify custom roles, assign roles, and modify role permissions
- Preset roles cannot be updated or deleted (enforced by `NOT is_preset` checks on write policies)

### Mention-Based Project Access (Migration 074, 2026-04-20)

**Rule**: a user tagged in any live (non-soft-deleted) `project_notes.mentioned_user_ids` entry for a project gains read-only view access to the project and its tasks, regardless of `projects.team_member_ids` membership.

**Scope of grant**:
- Read: `projects`, `project_tasks` — extended via new helper.
- Write: **no extension**. Mention-granted users cannot edit project fields, tasks, schedule, team, estimates, invoices, or expenses. Enforced at the DB via unchanged `role_scope_update` policies calling the original `current_user_in_project` helper.
- Client-side surfaces: mention-granted projects appear in Universal Search + iOS Spotlight only. Hidden from Job Board "My Projects", Calendar, Schedule, and Map by design — discoverability limited to push-notification deep link and search.

**SQL (Migration 074):**

```sql
-- New read-only helper — superset of current_user_in_project with mention branch.
CREATE OR REPLACE FUNCTION private.current_user_can_view_project(p_project_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
  SELECT private.current_user_in_project(p_project_id)
      OR EXISTS (
        SELECT 1 FROM public.project_notes pn
        WHERE pn.project_id = p_project_id::text
          AND pn.deleted_at IS NULL
          AND private.get_current_user_id()::text = ANY(COALESCE(pn.mentioned_user_ids, ARRAY[]::text[]))
      );
$$;
```

**Policies updated** (read-only — write policies intentionally untouched):
- `projects.role_scope_read` — `assigned` branch now calls `current_user_can_view_project(projects.id)`.
- `project_tasks.role_scope_read` — `assigned` branch now calls `current_user_can_view_project(project_id)`.

**Policies NOT changed** (to keep mention-grant view-only):
- `projects.role_scope_update`, `project_tasks.role_scope_update`, `estimates.role_scope_update`, `invoices.role_scope_update` — continue to call the team-only `current_user_in_project`.

**iOS client integration**:
- `MentionAccessIndex` (`OPS/Utilities/`) — on-device index of projectIds the current user has mention access to. Rebuilt from cached `ProjectNote` rows on login, sync completion, Realtime note events.
- `ProjectAccessHelper.narrowVisible` vs `.wideVisible` — surface-specific predicates. Job Board uses narrow; Search/Spotlight use wide.
- `PermissionStore.canViewProject(_ project:, userId:)` — per-record check combining base-role scope + mention-grant.
- Mention-only users see a read-locked `ProjectQuickActionsBar` with only the "NOTE" action available (reply-only, per Bug G9 Rule 2).

**Context**: Bug G9 (2026-04-20). Source of truth: `docs/superpowers/plans/2026-04-20-mention-based-project-access.md`.

### Auth ID Resolution

**Critical**: Supabase `auth.uid()` returns the Supabase Auth UUID, which is different from `users.id` (the application-level UUID). The `users` table has an `auth_id` column that maps the Supabase Auth UUID to the app user. A helper function resolves this:

```sql
CREATE OR REPLACE FUNCTION private.get_current_user_id()
RETURNS uuid LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = '' AS $$
  SELECT id FROM public.users
  WHERE auth_id = (SELECT auth.uid())::text
  LIMIT 1
$$;
```

All RLS policies on permission tables use `private.get_current_user_id()` instead of `auth.uid()` directly.

### Web Implementation Reference

The web app (OPS-Web) implements the permission system with:
- **`permissions-store.ts`** — Zustand store with `can(permission, scope?)` method
- **`permission-gate.tsx`** — React component that conditionally renders children based on permissions
- **`check-permission.ts`** — Server-side utility calling `has_permission()` RPC
- **`roles-service.ts`** — CRUD operations for roles, role permissions, and user role assignments
- **Sidebar** — Nav items filtered by permission (e.g., `permission: "invoices.view"`)
- **Route guard** — Dashboard layout blocks render of gated routes until permissions load
- **Settings** — Roles sub-tab gated behind `team.assign_roles`

### Permission Enforcement Matrix

Every page, tab, and action button in OPS-Web must be gated. This matrix is the source of truth.

#### Route-Level Gates (layout.tsx → ROUTE_PERMISSIONS)

| Route | Permission | Feature Flag |
|-------|-----------|-------------|
| /projects | projects.view | — |
| /calendar | calendar.view | — |
| /clients | clients.view | — |
| /job-board | job_board.view | — |
| /team | team.view | — |
| /map | map.view | — |
| /pipeline | pipeline.view | pipeline |
| /estimates | estimates.view | estimates |
| /invoices | invoices.view | invoices |
| /products | products.view | products |
| /inventory | inventory.view | inventory |
| /accounting | accounting.view | accounting |
| /portal-inbox | portal.view | portal |

#### Settings Tab Gates (SUB_TAB_PERMISSIONS)

| Tab ID | Permission Required |
|--------|-------------------|
| company-details | settings.company |
| team | team.view |
| roles | team.assign_roles |
| task-types | settings.company |
| inventory | inventory.manage |
| expenses | expenses.configure |
| subscription | settings.billing |
| payment | settings.billing |
| email | settings.integrations |
| portal | portal.manage_branding |
| templates | documents.manage_templates |
| accounting | accounting.manage_connections |
| setup-wizards | settings.company |

Tabs without entries (profile, appearance, notifications, shortcuts, preferences-general, map, data-privacy) are personal settings accessible to all authenticated users.

#### Action Button Gating Pattern

When building any feature with user actions, gate with `<PermissionGate>` or `can()`:

| Action Pattern | Permission Required |
|---------------|-------------------|
| Create [resource] | [module].create |
| Edit [resource] | [module].edit |
| Delete [resource] | [module].delete |
| Send [document] | [module].send |
| Void [document] | [module].void |
| Convert [document] | [module].convert |
| Approve [item] | [module].approve |
| Configure [settings] | [module].configure or settings.* |
| Manage [integration] | [module].manage_connections |

### Legacy Fields Being Replaced

| Legacy Field | Replaced By | Status |
|-------------|-------------|--------|
| `user.role` (UserRole enum) | `user_roles` table + `roles` table | Kept for backward compat, no longer source of truth |
| `user.isCompanyAdmin` | `settings.company` + `settings.billing` permissions | Kept for backward compat |
| `user.inventoryAccess` | `inventory.view` permission | Never synced from Supabase, always `false` |
| `user.specialPermissions` (pipeline flag) | `pipeline.view` permission | Only set on first insert, not updated on sync |
| `user.devPermission` | No replacement needed | Synced but never checked in any view logic |

---

## Catalog & Variant Model

The Catalog domain replaces the legacy file-only `Inventory*` models with a fully registered, variant-aware schema. Stockable SKUs (variants) and billable templates (Products) are separate concerns bridged by `ProductMaterial` recipe rows. All 14 catalog entities + 4 product extensions live in `OPS/DataModels/Supabase/Catalog/` and are registered in `OPSSchemaCommon.unchangedModels`.

```
catalog_categories (nested via parent_id, 2-level UI)
  └─ catalog_items (variant family)
        ├─ catalog_options (variant axis: "Color", "Mount Type")
        │     └─ catalog_option_values (selectable values)
        ├─ catalog_variants (the SKU — has quantity, threshold, unit)
        │     └─ catalog_variant_option_values (M2M: variant ↔ option_value combo)
        └─ catalog_item_tags ─→ catalog_tags (FAMILY-level free-form labels)

catalog_units (renamed from inventory_units)
catalog_snapshots / catalog_snapshot_items (variant-aware point-in-time)
catalog_orders / catalog_order_items (threshold-driven restock — NEW)
company_default_products (component_type → product_id mapping — NEW)
```

**IMPORTANT change from legacy:** tags now apply at the **family** level, not the variant level. A "Corner" family carries tags like `discontinued`; not each variant separately. The legacy threshold columns on `catalog_tags` are preserved in storage but no longer surfaced in the iOS UI — effective-threshold compute now flows variant-override → family-default → category-default.

### CatalogCategory

**File**: `DataModels/Supabase/Catalog/CatalogCategory.swift`
**Purpose**: Nested category for catalog items. 2-level max in UI; cycle-prevention enforced by Postgres trigger.

```swift
@Model
final class CatalogCategory: Identifiable {
    @Attribute(.unique) var id: String
    var companyId: String
    var name: String
    var parentId: String?                 // self-FK (nested)
    var sortOrder: Int
    var colorHex: String?
    var defaultWarningThreshold: Double?  // cascades to family/variant when null at lower levels
    var defaultCriticalThreshold: Double?

    var lastSyncedAt: Date?
    var needsSync: Bool = false
    var deletedAt: Date?
}
```

**RLS**: company_isolation. **Indexes**: `(company_id, parent_id)`, `(company_id, deleted_at)`.

### CatalogItem

**File**: `DataModels/Supabase/Catalog/CatalogItem.swift`
**Purpose**: Variant family — one row per logical product (e.g., "Corner") that may have N variants differing by option values. Carries default price/cost/threshold; variants override per-SKU.

```swift
@Model
final class CatalogItem: Identifiable {
    @Attribute(.unique) var id: String
    var companyId: String
    var categoryId: String?
    var name: String
    var itemDescription: String?
    var defaultPrice: Double?
    var defaultUnitCost: Double?
    var defaultWarningThreshold: Double?
    var defaultCriticalThreshold: Double?
    var defaultUnitId: String?            // FK catalog_units.id
    var imageUrl: String?
    var notes: String?
    var isActive: Bool

    var lastSyncedAt: Date?
    var needsSync: Bool = false
    var deletedAt: Date?
}
```

**RLS**: company_isolation. **Indexes**: `(company_id, category_id, deleted_at)`.

### CatalogVariant

**File**: `DataModels/Supabase/Catalog/CatalogVariant.swift`
**Purpose**: The concrete SKU. Belongs to a `CatalogItem` (family) and references one `CatalogOptionValue` per `CatalogOption` on that family via `CatalogVariantOptionValue` rows.

```swift
@Model
final class CatalogVariant: Identifiable {
    @Attribute(.unique) var id: String
    var companyId: String
    var catalogItemId: String
    var sku: String?
    var quantity: Double
    var priceOverride: Double?            // falls back to family default_price
    var unitCostOverride: Double?         // falls back to family default_unit_cost
    var warningThreshold: Double?         // fallback chain: variant → family → category
    var criticalThreshold: Double?        // same fallback chain
    var unitId: String?                   // FK catalog_units.id; falls back to family default
    var isActive: Bool

    var lastSyncedAt: Date?
    var needsSync: Bool = false
    var deletedAt: Date?
}
```

**Threshold fallback** (canonical): variant override → family default → category default → null. **Indexes**: `(catalog_item_id, deleted_at)`, `(sku) WHERE deleted_at IS NULL`. **RLS**: company_isolation joined via `catalog_items.company_id`.

`ThresholdStatus` enum (`.normal`, `.warning`, `.critical`) currently lives in `InventoryItem.swift` for backward source compatibility; will move to `DataModels/Enums/ThresholdStatus.swift` when the legacy file is deleted.

### CatalogOption

**File**: `DataModels/Supabase/Catalog/CatalogOption.swift`
**Purpose**: A variant axis on a `CatalogItem` (e.g., "Color" or "Mount Type"). Distinct from `ProductOption` — that lives on `Product`, this lives on the variant family.

```swift
@Model
final class CatalogOption: Identifiable {
    @Attribute(.unique) var id: String
    var catalogItemId: String
    var name: String
    var sortOrder: Int

    var lastSyncedAt: Date?
    var needsSync: Bool = false
}
```

### CatalogOptionValue

**File**: `DataModels/Supabase/Catalog/CatalogOptionValue.swift`
**Purpose**: A possible value for a `CatalogOption` (e.g., "Black" on Color).

```swift
@Model
final class CatalogOptionValue: Identifiable {
    @Attribute(.unique) var id: String
    var optionId: String
    var value: String
    var sortOrder: Int

    var lastSyncedAt: Date?
    var needsSync: Bool = false
}
```

UNIQUE constraint on `(option_id, value)`.

### CatalogVariantOptionValue

**File**: `DataModels/Supabase/Catalog/CatalogVariantOptionValue.swift`
**Purpose**: Junction — `CatalogVariant` ↔ `CatalogOptionValue`. Each variant has exactly one row per `CatalogOption` on its family.

```swift
@Model
final class CatalogVariantOptionValue {
    var variantId: String
    var optionValueId: String

    var lastSyncedAt: Date?
}
```

PRIMARY KEY `(variant_id, option_value_id)`.

### CatalogTag

**File**: `DataModels/Supabase/Catalog/CatalogTag.swift`
**Purpose**: Free-form label applied at FAMILY level. The legacy threshold columns are preserved in storage but the UI no longer reads them; they will be dropped in a future session once we confirm zero callers.

```swift
@Model
final class CatalogTag: Identifiable {
    @Attribute(.unique) var id: String
    var companyId: String
    var name: String
    var warningThreshold: Double?         // legacy, no longer surfaced
    var criticalThreshold: Double?        // legacy, no longer surfaced

    var lastSyncedAt: Date?
    var needsSync: Bool = false
    var deletedAt: Date?
}
```

### CatalogItemTag

**File**: `DataModels/Supabase/Catalog/CatalogItemTag.swift`
**Purpose**: Junction — `CatalogItem` (family) ↔ `CatalogTag`. NOT variant-level. **This is a deliberate change from the legacy `inventory_item_tags` model.**

```swift
@Model
final class CatalogItemTag {
    @Attribute(.unique) var id: String
    var catalogItemId: String
    var tagId: String

    var lastSyncedAt: Date?
}
```

### CatalogUnit

**File**: `DataModels/Supabase/Catalog/CatalogUnit.swift`
**Purpose**: Unit of measure. Renamed from `inventory_units`. Today's iOS DTO bug — which silently dropped `dimension` and `abbreviation` — is fixed: both now flow through.

```swift
@Model
final class CatalogUnit: Identifiable {
    @Attribute(.unique) var id: String
    var companyId: String
    var display: String                   // e.g., "ea", "box", "ft"
    var abbreviation: String?
    var dimension: String                 // 'count' | 'length' | 'area' | 'volume' | 'mass' | 'time'
    var isDefault: Bool
    var sortOrder: Int

    var lastSyncedAt: Date?
    var needsSync: Bool = false
    var deletedAt: Date?
}
```

### CatalogSnapshot

**File**: `DataModels/Supabase/Catalog/CatalogSnapshot.swift`
**Purpose**: Variant-aware historical snapshot of stock at a point in time. The legacy `inventory_snapshots` shape is preserved; only the items it captures are now variant-keyed.

```swift
@Model
final class CatalogSnapshot: Identifiable {
    @Attribute(.unique) var id: String
    var companyId: String
    var createdById: String?
    var isAutomatic: Bool
    var itemCount: Int
    var notes: String?
    var createdAt: Date

    var lastSyncedAt: Date?
    var needsSync: Bool = false
}
```

### CatalogSnapshotItem

**File**: `DataModels/Supabase/Catalog/CatalogSnapshotItem.swift`
**Purpose**: One row per variant captured in a snapshot. Carries denormalized `familyName` + `variantLabel` ("Black · Topmount") so historical snapshots survive even after a family/variant is renamed or soft-deleted.

```swift
@Model
final class CatalogSnapshotItem: Identifiable {
    @Attribute(.unique) var id: String
    var snapshotId: String
    var originalVariantId: String?
    var familyName: String                // denormalized
    var variantLabel: String?             // e.g., "Black · Topmount"
    var quantity: Double
    var unitDisplay: String?
    var sku: String?
    var itemDescription: String?

    var lastSyncedAt: Date?
    var needsSync: Bool = false
}
```

### CatalogOrder (NEW)

**File**: `DataModels/Supabase/Catalog/CatalogOrder.swift`
**Purpose**: Threshold-driven restock order. Closes Bug `e08c63a2`. Suggested orders are computed on demand (variants where `quantity < effective_warning_threshold`) until the user opens the Orders sheet — at which point a `.suggested` row may be drafted into `.draft`.

```swift
enum CatalogOrderStatus: String, CaseIterable, Codable {
    case suggested
    case draft
    case sent
    case fulfilled
    case cancelled
}

@Model
final class CatalogOrder: Identifiable {
    @Attribute(.unique) var id: String
    var companyId: String
    var status: CatalogOrderStatus
    var title: String?
    var supplierName: String?
    var supplierContact: String?
    var expectedDeliveryDate: Date?
    var notes: String?
    var createdById: String?
    var createdAt: Date
    var updatedAt: Date
    var sentAt: Date?
    var fulfilledAt: Date?
    var cancelledAt: Date?

    var lastSyncedAt: Date?
    var needsSync: Bool = false
    var deletedAt: Date?
}
```

**RLS**: company_isolation.

### CatalogOrderItem

**File**: `DataModels/Supabase/Catalog/CatalogOrderItem.swift`
**Purpose**: One line per variant on an order. `costPerUnit` is snapshotted at order creation so later cost edits don't mutate the order's history.

```swift
@Model
final class CatalogOrderItem: Identifiable {
    @Attribute(.unique) var id: String
    var orderId: String
    var catalogVariantId: String
    var quantityRequested: Double
    var costPerUnit: Double?
    var notes: String?

    var lastSyncedAt: Date?
    var needsSync: Bool = false
}
```

### CompanyDefaultProduct (NEW)

**File**: `DataModels/Supabase/Catalog/CompanyDefaultProduct.swift`
**Purpose**: Per-company default `Product` per Deck Builder `component_type`. Drives the one-click drawing→estimate adapter (see `07_SPECIALIZED_FEATURES.md` § Catalog Management → Drawing→Estimate adapter).

```swift
enum DesignComponentType: String, CaseIterable, Codable {
    case railing
    case deckBoard = "deck_board"
    case stairSet  = "stair_set"
    case gate
    case postSet   = "post_set"
}

@Model
final class CompanyDefaultProduct {
    var companyId: String
    var componentType: DesignComponentType
    var productId: String
    var createdAt: Date
    var updatedAt: Date

    var lastSyncedAt: Date?
    var needsSync: Bool = false
}
```

PRIMARY KEY `(company_id, component_type)`.

### Configurable Product extensions

The four Product-side extensions live alongside the catalog models in `DataModels/Supabase/Catalog/`. See § 21 (Product) → "Configurable Products (NEW)" for resolver flow and worked examples.

**`ProductOption`** — knob the user configures on a line item. Affects price, recipe, or both.

```swift
enum ProductOptionKind: String, CaseIterable, Codable {
    case select
    case integer
    case boolean
}

@Model
final class ProductOption: Identifiable {
    @Attribute(.unique) var id: String
    var productId: String
    var name: String
    var kind: ProductOptionKind
    var affectsPrice: Bool
    var affectsRecipe: Bool
    var required: Bool
    var defaultValue: String?
    var optionDefaultSource: String?      // e.g. "$design.color" — read by drawing adapter
    var sortOrder: Int

    var lastSyncedAt: Date?
    var needsSync: Bool = false
}
```

**`ProductOptionValue`** — selectable values for `kind = .select`.

```swift
@Model
final class ProductOptionValue: Identifiable {
    @Attribute(.unique) var id: String
    var optionId: String
    var value: String
    var sortOrder: Int

    var lastSyncedAt: Date?
    var needsSync: Bool = false
}
```

**`ProductPricingModifier`** — bumps unit price when an option matches a trigger.

```swift
enum PricingModifierKind: String, CaseIterable, Codable {
    case addPerUnit         = "add_per_unit"
    case addFlat            = "add_flat"
    case addPerCount        = "add_per_count"
    case multiplyUnitPrice  = "multiply_unit_price"
}

@Model
final class ProductPricingModifier: Identifiable {
    @Attribute(.unique) var id: String
    var productId: String
    var optionId: String
    var triggerValueId: String?           // for kind = .select
    var triggerIntMin: Int?               // for kind = .integer
    var triggerIntMax: Int?
    var modifierKind: PricingModifierKind
    var amount: Double

    var lastSyncedAt: Date?
    var needsSync: Bool = false
}
```

**`ProductMaterial`** — recipe row. Family-pinned + selector OR variant-pinned (mutually exclusive).

```swift
@Model
final class ProductMaterial: Identifiable {
    @Attribute(.unique) var id: String
    var productId: String
    var catalogVariantId: String?         // pinned variant
    var catalogItemId: String?            // family head — resolved via selector
    var variantSelectorJSON: String?      // jsonb — {"color":"$option.color","mount":"$option.mount_type"}
    var quantityPerUnit: Double           // per Product's pricing_unit
    var scaledByOptionId: String?         // multiply by line.configured_options[this option]
    var unitId: String?                   // FK catalog_units.id (expression unit)
    var notes: String?

    var lastSyncedAt: Date?
    var needsSync: Bool = false
}
```

CHECK: `(catalog_variant_id IS NOT NULL) <> (catalog_item_id IS NOT NULL)`.

> **Legacy note:** the older `Inventory*` SwiftData files (`InventoryItem`, `InventorySnapshot`, `InventorySnapshotItem`, `InventoryTag`, `InventoryUnit`) remain on disk for compile-time references during the V2→V3 migration window but are **no longer registered in `OPSSchemaCommon`**. They are removed by Phase 4 of plan `2026-05-06-ios-catalog-variant-model.md`. SQL-side, the `inventory_*` tables are renamed to `catalog_*` by migration `2026-05-06-01-catalog-schema.sql`.

### Catalog Import RPCs (added 2026-05-08)

Two SECURITY DEFINER plpgsql functions on the `public` schema power the iOS bulk-CSV import flow. SQL lives at `OPS/OPS/Migrations/2026-05-08-catalog-import-rpc.sql` (also documented in `OPS/OPS/Migrations/2026-05-08-catalog-import-rpc.md`); the iOS client calls them through `CatalogImportRepository`.

| Function | Behaviour |
|---|---|
| `public.catalog_import_validate(p_company_id uuid, p_payload jsonb) RETURNS jsonb` | Pure validator — runs every per-row check, returns success/failure shape, never INSERTs. |
| `public.catalog_import_apply(p_company_id uuid, p_payload jsonb) RETURNS jsonb` | Runs the same validation; on success, INSERTs every family + variant in a single transaction. ROLLBACK on any failure. |

Both are gated by `private.get_user_company_id() = p_company_id`. `EXECUTE` granted to `authenticated`.

**Payload shape**:

```json
{
  "families": [{"row_index":0,"name":"...","category_id":null,"default_unit_id":null,"default_price":null,...}],
  "variants": [{"row_index":0,"family_row_index":0,"sku":"...","quantity":12,...}]
}
```

`row_index` is 0-based and unique within its array. Variants reference their parent family by `family_row_index`; the `apply` RPC resolves that index to the freshly INSERTed family uuid and returns both maps in `created_family_ids` / `created_variant_ids`.

**Result shape**:

- Success: `{"success": true, "created_family_ids": {...}, "created_variant_ids": {...}, "totals": {"families": N, "variants": M}}`
- Failure: `{"success": false, "errors": [{"scope":"family|variant|payload","row_index":N,"field":"...","reason":"..."}]}`

**Validation rules** (single source of truth — both RPCs share the same plpgsql block):

- Caller's `private.get_user_company_id()` must equal `p_company_id`.
- `families` array non-empty; `name` required + non-blank.
- `category_id` / `default_unit_id` / variant `unit_id` (if set) must reference active rows in the same company.
- All numeric fields >= 0.
- Variant `quantity` required + numeric; `family_row_index` must reference a family in the same payload.
- Non-empty `sku` cannot collide with an existing active variant in the company (DB has no unique constraint on SKU — the RPC enforces it).

**Atomicity**: both functions return normally on validation failure (returning the failure object), so the implicit transaction does NOT commit when a failure path is taken. The `apply` function's INSERT statements run only inside the success path; any error during INSERT raises and rolls back the transaction. The client never sees partial state.

**No update path**: import is INSERT-only. Re-importing the same CSV creates duplicate families. Use Snapshots (kebab Setup → Snapshots) to roll back a bad import.

### Products Import RPCs (added 2026-05-08)

Sibling to the catalog import RPCs above. Drives the second tab (`PRODUCTS`) in the iOS `CatalogImportSheet` — bulk-creates rows in the `products` table (services + goods). SQL lives at `OPS/OPS/Migrations/2026-05-08-products-import-rpc.sql` (also documented in `OPS/OPS/Migrations/2026-05-08-products-import-rpc.md`); the iOS client calls them through `ProductsImportRepository`. Same `SECURITY DEFINER`, same `EXECUTE TO authenticated`, same caller-vs-`p_company_id` guard.

| Function | Behaviour |
|---|---|
| `public.products_import_validate(p_company_id uuid, p_payload jsonb) RETURNS jsonb` | Pure validator — runs every per-row check, returns success/failure shape, never INSERTs. |
| `public.products_import_apply(p_company_id uuid, p_payload jsonb) RETURNS jsonb` | Runs the same validation; on success, INSERTs every product row in a single transaction. ROLLBACK on any failure. |

**Payload shape**:

```json
{
  "products": [
    {
      "row_index": 0,
      "name": "Composite deck install",
      "description": "...",
      "base_price": 25.00,
      "unit_cost": 12.00,
      "category_id": "uuid-or-null",
      "unit_id": "uuid-or-null",
      "category": "Hardware",
      "unit": "sqft",
      "pricing_unit": "sqft",
      "sku": "DECK-INST",
      "kind": "service",
      "type": "LABOR",
      "is_taxable": true
    }
  ]
}
```

`row_index` is 0-based and unique within `products`. The `apply` RPC returns the row_index → uuid mapping under `created_product_ids`.

**Result shape**:

- Success: `{"success": true, "created_product_ids": {...}, "totals": {"products": N}}`
- Failure: `{"success": false, "errors": [{"scope":"product|payload","row_index":N,"field":"...","reason":"..."}]}`

**Validation rules** (single source of truth):

- Caller's `private.get_user_company_id()` must equal `p_company_id`.
- `products` array non-empty.
- `name` required + non-blank; `base_price` required, numeric, >= 0.
- `unit_cost` optional; if present must be numeric and >= 0.
- `category_id` / `unit_id` (if set) must reference active rows in the same company.
- `kind` if set must be `'service'` or `'good'` (table NOT NULL default `'service'`).
- `type` if set must be `'LABOR'`, `'MATERIAL'`, or `'OTHER'` (table NOT NULL default `'LABOR'`).
- `pricing_unit` accepted as free text (table NOT NULL default `'each'`).
- `sku` is **not** uniqueness-checked — `products` has no unique constraint on SKU and the import explicitly opts out of a soft-fail.

**Atomicity**: same model as the catalog import — failure path returns the error object normally (no commit), success path runs all INSERTs inside the implicit transaction. The mirror of `base_price` → `default_price` is handled by an existing Postgres trigger on the table, so the RPC writes only `base_price`.

**No update path**: INSERT-only. Re-importing the same CSV creates duplicate product rows.

### CatalogImportSheet UI (iOS)

`OPS/Views/Catalog/Import/CatalogImportSheet.swift` is a single sheet hosting both flows. A tab strip at the top of the sheet (`STOCK | PRODUCTS`) selects the target; each tab uses its own column-mapping struct, parser/mapper, repository, and apply notification:

- `STOCK` → `CatalogCSVMapper` + `CatalogImportRepository` → posts `CatalogImportApplied` with `{families, variants}` on success.
- `PRODUCTS` → `ProductsCSVMapper` + `ProductsImportRepository` → posts `ProductsImportApplied` with `{products}` on success.

Both tabs share the same four-step flow (PICK → MAP → PREVIEW → APPLY) and the same atomic preview/apply contract — the user never sees half-imported state on either tab.

---

## DeckDesign — drawing data and components projection

**File**: `OPS/DataModels/DeckDesign.swift` (SwiftData model)
**Drawing data Codable struct**: `OPS/DeckBuilder/Models/DeckGeometry.swift` (`DeckDrawingData`)
**Emitter**: `OPS/DeckBuilder/Engine/ComponentEmitter.swift`
**Adapter contract (consumer)**: `OPS/Services/DesignToEstimateAdapter.swift`

### SwiftData row

```swift
@Model
final class DeckDesign: Identifiable {
    @Attribute(.unique) var id: String
    var companyId: String
    var projectId: String?           // nil for standalone sketches
    var title: String
    var drawingDataJSON: String      // DeckDrawingData serialized as JSON (jsonb on Supabase)
    var thumbnailURL: String?        // S3 URL of rendered PNG
    var localThumbnailPath: String?
    var version: Int
    var createdBy: String?

    // Sync fields
    var needsSync: Bool
    var lastSyncedAt: Date?
    var syncPriority: Int
    var deletedAt: Date?

    var createdAt: Date
    var updatedAt: Date?
}
```

### `drawingDataJSON` schema

`drawingDataJSON` is the serialized form of `DeckDrawingData`. The catalog-relevant subset is:

```jsonc
{
  "vertices":         [ ... ],
  "edges":            [ ... ],
  "footprint":        { ... },
  "surfaces":         [ ... ],
  "config":           { ... },
  "scaleFactor":      <Double>,
  "overallElevation": <Double>,
  "levels":           [ ... ],          // multi-level only
  "levelConnections": [ ... ],          // multi-level only

  // CATALOG PROJECTION — derived from geometry on every save by
  // ComponentEmitter.emit(self). One row per visible component.
  // Forward-compatible: clients that don't recognize the key
  // ignore it; legacy JSON without the key decodes with
  // `components == nil` and the iOS load path backfills it.
  "components": [
    { "component_type": "railing",   "metadata": { ... } },
    { "component_type": "post_set",  "metadata": { ... } },
    { "component_type": "stair_set", "metadata": { ... } },
    { "component_type": "deck_board","metadata": { ... } },
    { "component_type": "gate",      "metadata": { ... } }
  ]
}
```

### `components[]` projection — per-type metadata schema

`component_type` matches `DesignComponentType` raw values exactly. Adding new component_type strings is fine; renaming is a contract break with `DesignToEstimateAdapter`. Metadata keys map 1:1 to the keys the adapter reads via `option_default_source = "$design.<key>"` and via `computeQuantity(unit:metadata:)`.

| `component_type` | Source in geometry | Required metadata keys |
|---|---|---|
| `railing` | One per `DeckEdge` with `railingConfig` | `linear_feet` (Double, edge length minus stair span minus all gate widths), `corners_count` (Int — currently always 0; corners live at vertex boundaries, not inside edges, so per-edge attribution would double-count), `color` (String, `RailingConfig.color`), `mount_type` (String, `RailingConfig.mountType`), `mount_surface` (String, `RailingConfig.mountSurface`), `edge_id` (String), optional `level_id` (String) |
| `post_set` | One per railing — co-emitted alongside the railing component | `count` (Int, `DimensionEngine.postCount`), `height` (Double inches, `RailingConfig.postHeight`), `color` (mirrors railing), `mount_type` (mirrors railing), `edge_id`, optional `level_id` |
| `stair_set` | One per `DeckEdge` with `stairConfig`, plus one per `LevelConnection` (multi-level) | `tread_count` (Int, `StairConfig.calculateTreadCount` or override), `width` (Double inches, `StairConfig.width`), `color` (String, `StairConfig.color`), `mount_type` (String — vocabulary `Surface | Top | Side`, distinct from railing), `edge_id` OR `connection_id` + `level_id` (upper level) |
| `deck_board` | One per `DeckSurface` with a detected face match (per-face area), or one per legacy footprint when surfaces empty | `sqft` (Double, `PolygonMath.realWorldArea(face) / 144.0`), `color` (String, `DeckSurface.color`), `material` (String, `DeckSurface.boardMaterial`), `surface_id` (String — the persisted DeckSurface id, or sentinel `"footprint"` for the legacy fallback), optional `level_id` |
| `gate` | One per `isGate=true` AssignedItem on an edge | `count` (Int — 1 per row), `width` (Double inches — default 36), `color` / `mount_type` / `mount_surface` (mirror parent railing or fall back to defaults Black / Topmount / Surface), `edge_id`, optional `level_id` |

Default vocabulary on partially-configured drawings — emitter still fires so a barebones design produces line items via the company's `CompanyDefaultProduct` mapping:

| Field | Default | Rationale |
|---|---|---|
| `color` | "Black" (railing/stair) / "Brown" (deck board) | Most common single-color systems. |
| `mount_type` (railing) | "Topmount" | Most common deck attachment. |
| `mount_surface` (railing) | "Surface" | Wood-frame assumption; user overrides for concrete. |
| `mount_type` (stair) | "Surface" | Stairs land on grade in the typical case. |
| `material` (deck board) | "composite" | Most common new-construction. |
| `post_height` | 36.0 inches | IRC R312 minimum. |

### Recompute discipline

- Every `DeckDrawingData.toJSON()` invocation recomputes `components` from `ComponentEmitter.emit(self)` — never read for rendering, only read by the adapter. This keeps the projection in sync with whatever geometry is about to be persisted.
- `DeckBuilderViewModel.init(...)` backfills `components` on legacy designs (JSON saved before the catalog vocabulary landed). The next save persists the projection; designs the user never reopens stay legacy on disk forever (the adapter no-ops on them).
- ops-web round-trips the same `drawingDataJSON` and ignores keys it doesn't recognize, so the components key is forward-compatible. iOS backfills on load if web has stripped the key on round-trip.

### Typed metadata fields on geometry structs

These are the user-facing knobs the projection reads. All non-optional fields default to a sensible per-type value so existing JSON round-trips through custom `init(from:)` decoders that use `decodeIfPresent` for the new fields:

```swift
// RailingConfig (additions)
var color: String = "Black"
var mountType: String = "Topmount"      // Topmount | Sidemount | Surface
var mountSurface: String = "Surface"    // Surface | Concrete | other
var postHeight: Double = 36.0           // inches

// StairConfig (additions)
var color: String = "Black"
var mountType: String = "Surface"       // Surface | Top | Side

// DeckSurface (additions)
var color: String = "Brown"
var boardMaterial: String = "composite" // composite | pvc | cedar | treated | other

// AssignedItem (additions)
var isGate: Bool = false                // drives gate component emission
```

Free-text strings, not enums, because companies author option values per Product (`product_option_values.value`). The assignment sheet renders a Picker over the matching axis when the company default Product exposes one bound to `$design.<key>`; otherwise free-text.

---

## Bridge & Audit Tables

These tables sit between the Product domain and the Catalog domain, capture audit trails for stock movement, or hold per-relationship overrides. None map 1:1 to a SwiftData model registered in `OPSSchemaCommon` — they are accessed through DTOs, repository helpers, or as side-effect rows.

### `product_materials`

**Purpose**: Recipe row. Resolves "how much of which catalog variant a Product consumes per unit."
**SwiftData**: `ProductMaterial` (registered).
**Schema**:

```sql
product_materials
  id                    uuid PK
  product_id            uuid FK products(id)
  catalog_variant_id    uuid FK catalog_variants(id) NULL
  catalog_item_id       uuid FK catalog_items(id)    NULL
  variant_selector      jsonb                        NULL  -- e.g. {"color":"$option.color"}
  quantity_per_unit     numeric NOT NULL
  scaled_by_option_id   uuid FK product_options(id)  NULL
  unit_id               uuid FK catalog_units(id)    NULL
  notes                 text                         NULL
  CHECK ((catalog_variant_id IS NOT NULL) <> (catalog_item_id IS NOT NULL))
```

**RLS**: company_isolation joined via `products.company_id`. **Resolution**: variant-pinned rows resolve immediately; family-pinned rows resolve at install task creation by walking `variant_selector` against `line_items.configured_options`.

**iOS recipe authoring (added 2026-05-08)**: `RecipeManageSheet` (entered from `ProductDetailView`'s recipe section EDIT button when the operator has `catalog.products.manage`) lists every existing `product_materials` row and lets the user add new variant-pinned rows via `AddProductMaterialSheet` — pick a `catalog_items` family, pick a variant, set `quantity_per_unit` and notes. iOS authoring writes variant-pinned rows only; family-pinned rows with `variant_selector` jsonb mapping options to variant attributes remain web-only. No row-edit on iOS yet — to change a quantity, delete and re-add. Repository: `ProductRichnessRepository.createMaterial` / `deleteMaterial`. The full advanced authoring (family-pinned recipes, scaled-by-option rows, custom selectors) stays on ops-web.

### `task_materials`

**Purpose**: Cut-list row. Inserted at install task creation by `CutListMaterializer`. This is what the field crew sees on the task — pinned to specific variants, ready to deduct from stock when consumed.
**SwiftData**: not stored locally as a registered model — written via `CreateTaskMaterialDTO`, read via `TaskMaterialDTO`.
**Schema**:

```sql
task_materials
  id                  uuid PK (default gen_random_uuid())
  task_id             uuid FK project_tasks(id)
  inventory_item_id   uuid                                   -- legacy column, nullable for pre-catalog rows
  quantity            double precision NOT NULL
  source              text NOT NULL DEFAULT 'stock'
  catalog_variant_id  uuid FK catalog_variants(id) NULL      -- new rows always populate this
```

**RLS**: company_isolation joined via `project_tasks → projects.company_id`. The legacy `inventory_item_id` column is preserved for back-compat — it is null on all new rows.

### `line_item_materials`

**Purpose**: Optional per-line-item materials snapshot. Used by line items that need a frozen materials list distinct from the recipe template (e.g., a one-off custom build where the user manually overrode the BOM).
**Verification**: this table exists in `Network/Supabase/Repositories/EstimatesRepository.swift` queries; no dedicated SwiftData model. If the catalog/variant work later requires it, a DTO will be added.

### `inventory_deductions`

**Purpose**: Audit trail of stock movement. Insert-only.
**SwiftData**: not registered (audit-only table).
**Schema** (post-rename):

```sql
inventory_deductions
  id                  uuid PK
  catalog_variant_id  uuid FK catalog_variants(id) NOT NULL  -- renamed from inventory_item_id
  task_id             uuid FK project_tasks(id) NULL
  quantity            numeric NOT NULL                       -- positive = deducted, negative = returned
  reason              text                                   -- 'consumed' | 'returned' | 'manual_adjust' | 'snapshot'
  created_by_id       uuid FK users(id)
  created_at          timestamptz NOT NULL
  notes               text
```

**RLS**: company_isolation joined via `catalog_variants → catalog_items.company_id`. **Migration note**: the table is empty as of the catalog migration (0 rows globally), so the FK rename + re-FK to `catalog_variants` carries no data risk.

### `client_product_overrides`

**Purpose**: Per-client price override for a Product. Used when a recurring client has negotiated rates.
**Schema**:

```sql
client_product_overrides
  id              uuid PK
  client_id       uuid FK clients(id) NOT NULL
  product_id      uuid FK products(id) NOT NULL
  price_override  numeric NOT NULL
  notes           text
  created_at      timestamptz NOT NULL
  updated_at      timestamptz NOT NULL
  UNIQUE (client_id, product_id)
```

**RLS**: company_isolation joined via `clients.company_id`. Override is applied at line-item creation time by ops-web's price resolver; iOS reads it via `ProductRepository.fetchOverridesForClient()` when adding a line item.

### `product_tax_rates`

**Purpose**: Junction between Products and tax rates. A Product can have N applicable tax rates (e.g., GST + PST in BC).
**Schema**:

```sql
product_tax_rates
  product_id   uuid FK products(id)
  tax_rate_id  uuid FK tax_rates(id)
  PRIMARY KEY (product_id, tax_rate_id)
```

**RLS**: company_isolation joined via `products.company_id`. Tax computation at line-item time pulls every row for the line's product and applies all matching rates against the line subtotal.

### `company_default_products`

**Purpose**: Per-company mapping from Deck Builder `component_type` to default `Product`. Drives the one-click drawing→estimate adapter.
**SwiftData**: `CompanyDefaultProduct` (registered).
**Schema**:

```sql
company_default_products
  company_id      uuid FK companies(id) NOT NULL
  component_type  text NOT NULL                  -- 'railing' | 'deck_board' | 'stair_set' | 'gate' | 'post_set'
  product_id      uuid FK products(id) NOT NULL
  created_at      timestamptz NOT NULL
  updated_at      timestamptz NOT NULL
  PRIMARY KEY (company_id, component_type)
```

**RLS**: company_isolation. Only one default per (company, component_type). Missing mapping → adapter logs to `app_events.adapter_skip_component` and continues.

### `catalog_orders` and `catalog_order_items`

**Purpose**: Threshold-driven restock orders. See § "Catalog & Variant Model" → `CatalogOrder` / `CatalogOrderItem` for SwiftData declarations.
**Lifecycle**: `suggested` (computed on demand from variants below warning threshold) → `draft` (user opened the suggestion sheet and committed) → `sent` (PO emitted to supplier) → `fulfilled` (stock arrived; quantity is added back to `catalog_variants`) → `cancelled`.
**RLS**: company_isolation on both tables.

---

## Enums Reference

### Status (Project Status)

**File**: `DataModels/Status.swift`

```swift
enum Status: String, Codable, CaseIterable {
    case rfq = "rfq"
    case estimated = "estimated"
    case accepted = "accepted"
    case inProgress = "in_progress"
    case completed = "completed"
    case closed = "closed"
    case archived = "archived"
}
```

Legacy title-case values ("Pending", "RFQ", "Estimated", etc.) are handled by custom decoder.

### TaskStatus

**File**: `DataModels/ProjectTask.swift` (defined inline)

```swift
enum TaskStatus: String, Codable, CaseIterable {
    case active = "active"
    case completed = "completed"
    case cancelled = "cancelled"
}
```

Legacy mapping: "Scheduled"/"Booked"/"booked"/"In Progress"/"in_progress" all map to `.active`.

### UserRole

**File**: `DataModels/UserRole.swift`

```swift
enum UserRole: String, Codable {
    case admin = "admin"
    case owner = "owner"
    case office = "office"
    case operator = "operator"
    case crew = "crew"
    case unassigned = "unassigned"
}
```

Default role for company creator: `.owner`. Default role for new users: `.unassigned`.
Legacy title-case ("Field Crew", "Office Crew", "Admin") and legacy snake_case ("field_crew", "office_crew") handled by custom decoder.

### UserType

**File**: `DataModels/UserRole.swift`

```swift
enum UserType: String, CaseIterable, Codable {
    case employee = "employee"
    case company = "company"
}
```

### PipelineStage

**File**: `DataModels/Enums/PipelineStage.swift`

```swift
enum PipelineStage: String, Codable, CaseIterable, Identifiable {
    case newLead      = "new_lead"       // 10% win probability
    case qualifying   = "qualifying"     // 20%
    case quoting      = "quoting"        // 40%
    case quoted       = "quoted"         // 60%
    case followUp     = "follow_up"      // 50%
    case negotiation  = "negotiation"    // 75%
    case won          = "won"            // 100%
    case lost         = "lost"           // 0%
    case discarded    = "discarded"      // 0% — lead not worth pursuing (ad quality signal)
}
```

Properties: `displayName`, `isTerminal`, `next`, `winProbability`, `staleThresholdDays`.

Terminal stages: `won`, `lost`, `discarded`. Discarded is a third terminal state meaning "not worth pursuing" — the lead contacted us (counts as an ad conversion) but was junk quality. Used for ad targeting quality analytics: compare won+lost (real leads) vs discarded (bad quality).

### ActivityType

**File**: `DataModels/Enums/ActivityType.swift`

Cases: `note`, `email`, `call`, `meeting`, `estimateSent`, `estimateApproved`, `estimateDeclined`, `invoiceSent`, `paymentReceived`, `stageChange`, `created`, `won`, `lost`, `siteVisit`, `system`.

Properties: `icon` (SF Symbol), `isSystemGenerated`.

### Financial Enums

**File**: `DataModels/Enums/FinancialEnums.swift`

- **EstimateStatus**: `draft`, `sent`, `viewed`, `approved`, `converted`, `declined`, `expired`
- **InvoiceStatus**: `draft`, `sent`, `awaitingPayment`, `partiallyPaid`, `paid`, `pastDue`, `void`
- **PaymentMethod**: `cash`, `check`, `creditCard`, `ach`, `bankTransfer`, `stripe`, `other`
- **LineItemType**: `labor` ("LABOR"), `material` ("MATERIAL"), `other` ("OTHER")
- **FollowUpType**: `call`, `email`, `meeting`, `quoteFollowUp`, `invoiceFollowUp`, `custom`
- **FollowUpStatus**: `pending`, `completed`, `skipped`
- **SiteVisitStatus**: `scheduled`, `completed`, `cancelled`
- **ExpenseStatus**: `draft`, `submitted`, `approved`, `rejected`, `reimbursed`
- **ExpensePaymentMethod**: `cash`, `personalCard` ("personal_card"), `companyCard` ("company_card")
- **ReviewFrequency**: `perJob` ("per_job"), `weekly`, `biweekly`, `monthly`, `quarterly`
- **AccountingSyncStatus**: `pending`, `synced`, `error`

### Subscription Enums

**File**: `DataModels/SubscriptionEnums.swift`

- **SubscriptionStatus**: `trial`, `active`, `grace`, `expired`, `cancelled`
- **SubscriptionPlan**: `trial`, `starter`, `team`, `business` (with `maxSeats`, pricing, Stripe IDs)
- **PaymentSchedule**: `monthly` ("Monthly"), `annual` ("Annual")

---

## Relationship Map

Built from actual `@Relationship` declarations in the source code:

```
Company
├── teamMembers: [TeamMember]          (cascade)
├── taskTypes: [TaskType]              (cascade)
└── inventoryUnits: [InventoryUnit]    (cascade)

Project
├── client: Client?                     (nullify)
├── teamMembers: [User]                 (noAction)
└── tasks: [ProjectTask]                (cascade, inverse: ProjectTask.project)

ProjectTask
├── project: Project?                   (nullify)
├── taskType: TaskType?                 (nullify)
└── teamMembers: [User]                 (noAction)

Client
├── projects: [Project]                 (noAction, inverse: Project.client)
└── subClients: [SubClient]             (cascade)

SubClient
└── client: Client?                     (implicit inverse)

User
└── assignedProjects: [Project]         (noAction, inverse: Project.teamMembers)

TeamMember
└── company: Company?                   (cascade, inverse: Company.teamMembers)

TaskType
└── tasks: [ProjectTask]                (nullify, inverse: ProjectTask.taskType)

InventoryItem
├── unit: InventoryUnit?                (nullify)
└── tags: [InventoryTag]                (nullify)

InventoryTag
└── items: [InventoryItem]              (nullify, inverse: InventoryItem.tags)

InventoryUnit
└── items: [InventoryItem]              (nullify, inverse: InventoryItem.unit)

InventorySnapshot
└── items: [InventorySnapshotItem]?     (cascade, inverse: InventorySnapshotItem.snapshot)

InventorySnapshotItem
└── snapshot: InventorySnapshot?        (nullify)
```

**Supabase-backed models** (Opportunity, Estimate, Invoice, etc.) use **String foreign keys** (e.g., `opportunityId`, `companyId`, `projectId`) rather than `@Relationship` declarations. They are linked by ID lookup, not SwiftData relationships.

---

## BubbleFields Constants (Legacy/Deprecated)

`BubbleFields.swift` has been **removed from the codebase**. The file no longer exists. It previously contained byte-perfect field name mappings between Bubble.io and Swift models.

The system has migrated to Supabase DTOs with snake_case `CodingKeys` for API communication. Legacy Bubble DTOs (ProjectDTO, TaskDTO, CalendarEventDTO, UserDTO, CompanyDTO, ClientDTO, SubClientDTO, TaskTypeDTO) documented in earlier versions of this file may still exist in the codebase but are no longer the primary data pathway.

---

## Data Transfer Objects (DTOs)

### Legacy Bubble DTOs

The Bubble DTOs (ProjectDTO, TaskDTO, UserDTO, CompanyDTO, ClientDTO, SubClientDTO, TaskTypeDTO) were the original API mapping layer between Bubble.io and SwiftData models. These may still exist for backward compatibility but are being superseded by Supabase DTOs.

---

## Supabase DTOs

All Supabase DTOs live under `Network/Supabase/DTOs/`. They use snake_case `CodingKeys` to match Supabase column names and include `toModel()` methods for conversion to SwiftData objects.

### CoreEntityDTOs.swift

Contains DTOs for the 9 core entities migrated from Bubble:

| DTO | Target Model | Key CodingKeys Notes |
|-----|-------------|---------------------|
| `SupabaseCompanyDTO` | `Company` | `bubble_id`, `logo_url`, `admin_ids`, `seated_employee_ids`, `stripe_customer_id` |
| `SupabaseUserDTO` | `User` | `first_name`, `last_name`, `profile_image_url`, `user_color`, `is_company_admin`, `special_permissions` |
| `SupabaseClientDTO` | `Client` | `phone_number` (not `phone`), `profile_image_url` |
| `SupabaseSubClientDTO` | `SubClient` | `client_id`, `phone_number`; exposes `parentClientId` for relationship wiring |
| `SupabaseTaskTypeDTO` | `TaskType` | Table is `task_types`; column is `display` (not `name`) |
| `SupabaseProjectDTO` | `Project` | `team_member_ids`, `project_images` as arrays; `opportunity_id`; `created_at` + `created_by` round-trip the new audit columns (added 2026-05-10, bug 9d5c2535). Client sets both on insert; never updated on edit. |
| `SupabaseProjectTaskDTO` | `ProjectTask` | `task_type_id`, `custom_title`, `task_notes`, `source_line_item_id`, `source_estimate_id`, `start_date`, `end_date`; `created_at` round-tripped for recency-sorted pickers (added 2026-05-10). |
| `SupabaseOpsContactDTO` | `OpsContact` | `bubble_id` |

### CoreEntityConverters.swift

Extension methods `toModel()` on each DTO. Key deviations documented in code comments:

- Company: `adminIdsString` is comma-separated (not array), `logoURL` (not `logoUrl`)
- User: init requires `(id:firstName:lastName:role:companyId:)` -- role and companyId not optional
- SubClient: No `clientId` stored property -- parent Client relationship set by sync layer
- TaskType: Uses `display` not `name`

### OpportunityDTOs.swift

| DTO | Purpose |
|-----|---------|
| `OpportunityDTO` | Read; `toModel() -> Opportunity` |
| `CreateOpportunityDTO` | Create |
| `UpdateOpportunityDTO` | Partial update |
| `ActivityDTO` | Read; `toModel() -> Activity` |
| `CreateActivityDTO` | Create |
| `FollowUpDTO` | Read; `toModel() -> FollowUp` |
| `CreateFollowUpDTO` | Create |

### EstimateDTOs.swift

| DTO | Purpose |
|-----|---------|
| `EstimateDTO` | Read with nested `lineItems`; `toModel() -> Estimate` |
| `EstimateLineItemDTO` | Read; `toModel() -> EstimateLineItem` |
| `CreateEstimateDTO` | Create |
| `CreateLineItemDTO` | Create line item |
| `UpdateLineItemDTO` | Partial update |

### InvoiceDTOs.swift

| DTO | Purpose |
|-----|---------|
| `InvoiceDTO` | Read with nested `lineItems` and `payments`; `toModel() -> Invoice` |
| `InvoiceLineItemDTO` | Read; `toModel() -> InvoiceLineItem` |
| `PaymentDTO` | Read; `toModel() -> Payment` |
| `CreatePaymentDTO` | Create |

### ProductDTOs.swift

DTOs for the `products` table. The wire-field bug from earlier builds — DTOs mapping `unit_price`/`cost_price` to columns that don't exist — is fixed: `base_price` and `unit_cost` are the canonical column names. ops-web continues to read `default_price` while the Postgres mirror trigger is in place; iOS reads/writes `base_price`.

| DTO | Purpose |
|-----|---------|
| `ProductDTO` | Read with all 18 fields including `kind`, `pricingUnit`, `sku`, `isFavorite`, `minimumCharge`, `minimumQuantity`, `showBomOnEstimate`, `showInStorefront`, `tieredPricing`, `unitId`. `toModel() -> Product` |
| `CreateProductDTO` | Create — `companyId`, `name`, `basePrice`, `pricingUnit`, etc. |
| `UpdateProductDTO` | Partial update — supports the same fields plus `isActive`, `isFavorite` |
| `RawJSONColumn` | Type-erased jsonb passthrough used by `tieredPricing` |

### CatalogDTOs.swift

DTOs for the 12 catalog tables and the variant ↔ option-value join. All include snake_case `CodingKeys` for Supabase column mapping.

| DTO | Purpose |
|-----|---------|
| `CatalogCategoryDTO` / `CreateCatalogCategoryDTO` / `UpdateCatalogCategoryDTO` | `catalog_categories` |
| `CatalogItemDTO` / `CreateCatalogItemDTO` / `UpdateCatalogItemDTO` | `catalog_items` |
| `CatalogVariantDTO` / `CreateCatalogVariantDTO` / `UpdateCatalogVariantDTO` | `catalog_variants` |
| `CatalogOptionDTO` / `CreateCatalogOptionDTO` | `catalog_options` |
| `CatalogOptionValueDTO` / `CreateCatalogOptionValueDTO` | `catalog_option_values` |
| `CatalogVariantOptionValueDTO` / `CreateCatalogVariantOptionValueDTO` | `catalog_variant_option_values` (M2M join) |
| `CatalogTagDTO` / `CreateCatalogTagDTO` / `UpdateCatalogTagDTO` | `catalog_tags` |
| `CatalogItemTagDTO` / `CreateCatalogItemTagDTO` | `catalog_item_tags` (M2M join) |
| `CatalogUnitDTO` / `CreateCatalogUnitDTO` / `UpdateCatalogUnitDTO` | `catalog_units` — exposes `dimension` and `abbreviation` (was a bug pre-V3) |
| `CatalogSnapshotDTO` / `CreateCatalogSnapshotDTO` | `catalog_snapshots` |
| `CatalogSnapshotItemDTO` / `CreateCatalogSnapshotItemDTO` | `catalog_snapshot_items` (variant-aware) |

### ProductExtensionDTOs.swift

DTOs for the four Product-extension tables that drive Configurable Products.

| DTO | Purpose |
|-----|---------|
| `ProductOptionDTO` / `CreateProductOptionDTO` | `product_options` — knob definitions |
| `ProductOptionValueDTO` / `CreateProductOptionValueDTO` | `product_option_values` — `kind=select` selectable values |
| `ProductPricingModifierDTO` / `CreateProductPricingModifierDTO` | `product_pricing_modifiers` — price bumps per option/value |
| `ProductMaterialDTO` / `CreateProductMaterialDTO` / `UpdateProductMaterialDTO` | `product_materials` — recipe rows (variant-pinned or family-pinned) |

### CompanyDefaultProductDTOs.swift

| DTO | Purpose |
|-----|---------|
| `CompanyDefaultProductDTO` | Read; `toModel() -> CompanyDefaultProduct` |
| `UpsertCompanyDefaultProductDTO` | Insert/update for `(company_id, component_type) → product_id` mapping |

### CatalogOrderDTOs.swift

| DTO | Purpose |
|-----|---------|
| `CatalogOrderDTO` / `CreateCatalogOrderDTO` / `UpdateCatalogOrderDTO` | `catalog_orders` (status: suggested / draft / sent / fulfilled / cancelled) |
| `CatalogOrderItemDTO` / `CreateCatalogOrderItemDTO` | `catalog_order_items` (variant-pinned) |

### TaskMaterialDTOs.swift

DTOs for the cut-list rows materialized at install task creation time. The `inventory_item_id` column is preserved for legacy material rows; new rows go through `catalog_variant_id`.

| DTO | Purpose |
|-----|---------|
| `TaskMaterialDTO` | Read |
| `CreateTaskMaterialDTO` | Insert — defaults `source = 'stock'` |

### ExpenseDTOs.swift

| DTO | Purpose |
|-----|---------|
| `ExpenseDTO` | Read with nested `allocations` and `category` |
| `CreateExpenseDTO` | Create expense |
| `UpdateExpenseDTO` | Partial update (draft editing) |
| `ExpenseAllocationDTO` | Read project allocation |
| `CreateExpenseAllocationDTO` | Create allocation |
| `ExpenseCategoryDTO` | Read category |
| `CreateExpenseCategoryDTO` | Create custom category |
| `ExpenseBatchDTO` | Read batch |
| `ExpenseSettingsDTO` | Read/write company settings |
| `AccountingCategoryMappingDTO` | Read accounting category mapping (QB/Sage) |
| `CreateAccountingCategoryMappingDTO` | Create/upsert mapping |

### InventoryDTOs.swift (LEGACY — being removed)

These DTOs targeted the now-renamed `inventory_*` tables. They are retained for compile-time references during the V2→V3 migration window and are deleted by Phase 4 of plan `2026-05-06-ios-catalog-variant-model.md`. **Do not write new code against them — use `CatalogDTOs.swift` instead.**

### ProjectNoteDTOs.swift

| DTO | Purpose |
|-----|---------|
| `ProjectNoteDTO` | Read; `toModel() -> ProjectNote` |
| `CreateProjectNoteDTO` | Create (includes `mentioned_user_ids`) |

### PhotoAnnotationDTOs.swift

| DTO | Purpose |
|-----|---------|
| `PhotoAnnotationDTO` | Read; `toModel() -> PhotoAnnotation` |
| `UpsertPhotoAnnotationDTO` | Create/update |

### NotificationDTO.swift

```swift
struct NotificationDTO: Codable, Identifiable {
    let id: String
    let userId: String          // user_id
    let companyId: String       // company_id
    let type: String
    let title: String
    let body: String
    let projectId: String?      // project_id
    let noteId: String?         // note_id
    var isRead: Bool            // is_read
    let createdAt: String       // created_at
}
```

No corresponding SwiftData model -- used for push notification display only.

### SupabaseDateParsing.swift

Shared date parsing utility:

```swift
enum SupabaseDate {
    static func parse(_ string: String) -> Date?
    // Tries ISO8601 with fractional seconds first, then without
}
```

---

## Soft Delete Strategy

### Overview

Most models support **soft delete** via `deletedAt: Date?` timestamp.

### Default Query Pattern

**Always exclude soft-deleted items** unless explicitly querying for them:

```swift
// CORRECT
@Query(filter: #Predicate<Project> { $0.deletedAt == nil }) var projects: [Project]

// INCORRECT - shows deleted items
@Query var projects: [Project]
```

---

## Computed Properties & Business Logic

### Project Computed Dates (Task-Based)

Project dates are computed from task start/end dates directly (CalendarEvent entity removed):

```swift
var computedStartDate: Date? {
    tasks.compactMap { $0.startDate }.min()
}
var computedEndDate: Date? {
    tasks.compactMap { $0.endDate }.max()
}
```

### Client Contact Cascading

Client contact info checks client first, then sub-clients:

```swift
var effectiveClientEmail: String? {
    if let clientEmail = client?.email, !clientEmail.isEmpty { return clientEmail }
    // Falls through to sub-clients...
}
```

### Role Detection Logic

Role is determined by the `role: UserRole` property on the User model. The Supabase DTO maps `role` string directly.

### Project Team Computation

Project team members are computed from task team members via `updateTeamMembersFromTasks(in:)`. Call after any task creation, update, or deletion.

---

## Migration History

### Project / Task Recency Audit (2026-05-10, bug 9d5c2535)

Additive migration to support the "start from recent" suggestions strip on
the project form and the recency-sorted task type + team-member pickers on
the task form.

- `projects.created_by` (uuid, nullable, FK → `auth.users.id`) — populated by
  the iOS client on insert. `NULL` for projects created before 2026-05-10.
  Indexed by `idx_projects_created_by_created_at (created_by, created_at DESC) WHERE deleted_at IS NULL`.
- `Project.createdAt` / `Project.createdBy` — new SwiftData properties
  round-tripped through `SupabaseProjectDTO`.
- `ProjectTask.createdAt` — new SwiftData property round-tripped through
  `SupabaseProjectTaskDTO`. The Supabase column already existed; the iOS
  side now mirrors it so the recency-sorted pickers have a stable signal
  that doesn't drift on every edit-sync.
- Recency helpers live on `DataController` (`DataController+Recency.swift`):
  `recentlyCreatedProjects(by:from:limit:)`, `recentTeamMemberIds(forTaskType:companyId:)`, `recentTaskTypeIds(companyId:)`.

Safe per the iOS-sync constraint — every change is a new nullable column.
Older app versions ignore the new fields (Codable optionals).

### CalendarEvent Removal (February 2026)

CalendarEvent is no longer a model in the codebase. Scheduling dates (`startDate`, `endDate`, `duration`) are now stored directly on `ProjectTask`. The CalendarEvent model file has been deleted. All calendar display flows through ProjectTask properties.

### Task-Only Scheduling Migration (November 2025)

- Removed project-level calendar events
- Added `computedStartDate` / `computedEndDate` computed properties on Project
- Simplified calendar filtering to use task dates

### Status Value Migration

- **Project Status**: Changed from title-case ("RFQ", "In Progress") to snake_case ("rfq", "in_progress"). Custom decoders handle both.
- **TaskStatus**: Simplified to 3 states: `.active`, `.completed`, `.cancelled`. Legacy values ("Scheduled", "Booked", "In Progress") all map to `.active`.
- **UserRole**: Expanded from 3 roles (admin, office_crew, field_crew) to 6 roles (admin, owner, office, operator, crew, unassigned). Legacy values ("Field Crew", "field_crew", "Office Crew", "office_crew") mapped to `.crew` and `.office` respectively by custom decoder.

---

## Query Predicates & Filtering

### Active Projects

```swift
@Query(
    filter: #Predicate<Project> {
        $0.deletedAt == nil &&
        $0.status != .closed &&
        $0.status != .archived
    }
) var activeProjects: [Project]
```

### Tasks by Status

```swift
func tasksByStatus(_ status: TaskStatus) -> [ProjectTask] {
    let descriptor = FetchDescriptor<ProjectTask>(
        predicate: #Predicate { $0.deletedAt == nil && $0.status == status }
    )
    return try? modelContext.fetch(descriptor) ?? []
}
```

---

## Defensive Programming Patterns

### 1. Never Pass Models to Background Tasks

```swift
// CORRECT: Pass IDs
Task.detached { await processProject(projectId: project.id) }

// INCORRECT: Passing model causes crashes
Task.detached { await processProject(project: project) }
```

SwiftData models are tied to their ModelContext. Passing models across thread boundaries causes crashes.

**For off-main writes, use `DataActor`** (see `06_TECHNICAL_ARCHITECTURE.md` → "DataActor (Background SwiftData Writes)"). Cross the actor boundary with `PersistentIdentifier` (Sendable) and re-fetch via `modelContext.model(for: id)` on the receiving side. Never hand `@Model` instances to an actor.

### 2. Always Fetch Fresh Models

```swift
func processProject(projectId: String) async {
    let context = ModelContext(sharedModelContainer)
    let descriptor = FetchDescriptor<Project>(predicate: #Predicate { $0.id == projectId })
    guard let project = try? context.fetch(descriptor).first else { return }
    // Work with fresh model
}
```

Inside `DataActor` methods, use `self.modelContext` (the actor's background context); do not create ad-hoc `ModelContext(sharedModelContainer)` instances from within an actor.

### 3. Use @MainActor for UI Operations

### 4. Context-Specific Save Semantics

**Main context (`sharedModelContainer.mainContext`):** autosave on. Explicit `try context.save()` still required after mutations for deterministic persistence; do not rely solely on autosave timing.

**DataActor's background context:** autosave off. Wrap all mutation sequences in `try modelContext.transaction { ... }` — atomic at the SQLite level, persists on block exit, composes cleanly with SwiftData inverse-relationship cascades. Do NOT call `save()` inside a DataActor method; the transaction block handles commit.

### 5. Complete Data Wipe on Logout

Delete all 24 model types to prevent cross-user contamination.

---

## Summary

This data architecture provides:

- **24 registered SwiftData entities** (11 core + 13 Supabase-backed) plus 5 inventory models
- **Soft delete support** for data integrity
- **Supabase DTOs** for clean API separation with snake_case column mapping
- **Task-based scheduling** with dates stored directly on ProjectTask (CalendarEvent removed)
- **Computed properties** for project dates, client contact cascading, and team aggregation
- **Defensive patterns** to prevent SwiftData threading crashes, plus `@ModelActor DataActor` isolation for all background writes (Phase 1 of ModelActor refactor complete 2026-04-19)
- **Complete enum system** for statuses, roles, pipeline stages, and financial types

**Key Principles**:
1. Always filter out soft-deleted items
2. Never pass models across threads
3. Compute project dates from tasks
4. TaskType uses `display` property (not `name`)
5. Client uses `email` property (not `emailAddress`)
6. User uses `firstName`/`lastName` (not `nameFirst`/`nameLast`)
7. TaskStatus has 3 states: `.active`, `.completed`, `.cancelled`

---

## Email Integration Tables (Web Only)

These tables exist in Supabase only (not in SwiftData). See `10_JOB_LIFECYCLE_AND_DATA_RELATIONSHIPS.md` for full integration documentation including the sync engine, pattern detection, AI classification, and provider abstraction layer.

### Migration Notes

- **`gmail_connections` → `email_connections`** (migration 034): Table renamed. New columns added: `provider` (TEXT, default `'gmail'`), `webhook_subscription_id`, `webhook_expires_at`, `ops_label_id`, `ai_review_enabled`, `ai_memory_enabled`, `status`. All existing rows backfilled with `provider = 'gmail'`. No re-auth required for existing Gmail connections.
- **`gmail_scan_jobs` was NOT renamed.** The table retains its original name `gmail_scan_jobs` in both the database and all code references. Only `gmail_connections` was renamed.
- **`sync_filters` column was NOT renamed.** Migration 034 contains a comment noting the intent to rename `sync_filters` to `sync_profile`, but the rename was deferred. The DB column remains `sync_filters`. The TypeScript type `SyncProfile` maps to this column via the `syncFilters` field on `EmailConnection`.
- **Migration 035** added: `opportunity_email_threads`, `admin_feature_overrides`, and correspondence tracking columns on `opportunities`.
- **Migration 036** added: `agent_memories` (with pgvector), `agent_knowledge_graph`, `agent_writing_profiles`.
- **Migration 037-040** (Phase C Memory Bank): `graph_entities` table, entity FK columns on `agent_knowledge_graph` (source_entity_id, target_entity_id, link_type), `profile_type` on `agent_writing_profiles` (new unique constraint), `entity_id`/`valid_from`/`valid_to` on `agent_memories`.
- **Email compose/auto-send migrations**: New columns on `activities` (to_emails, cc_emails, body_text, has_attachments, attachment_count), new columns on `opportunities` (stage_manually_set, ai_summary), new JSONB column on `email_connections` (auto_send_settings), new tables `email_templates`, `ai_draft_history`, `pending_auto_sends`.

### email_connections

Renamed from `gmail_connections`. Supports Gmail and Microsoft 365 via provider abstraction. Existing Gmail connections backfilled with `provider = 'gmail'` — no re-auth required.

```sql
CREATE TABLE email_connections (
  id                      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id              UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
  provider                TEXT NOT NULL,                   -- 'gmail' | 'microsoft365'
  access_token            TEXT NOT NULL,                   -- encrypted at rest
  refresh_token           TEXT NOT NULL,                   -- encrypted at rest
  token_expires_at        TIMESTAMPTZ NOT NULL,
  user_email              TEXT NOT NULL,
  user_name               TEXT,
  sync_filters            JSONB DEFAULT '{}',              -- pattern detection rules (estimate patterns, company domains, platform senders, etc.)
  sync_interval_minutes   INTEGER DEFAULT 60,
  last_sync_history_id    TEXT,                            -- Gmail historyId or M365 deltaLink
  last_sync_at            TIMESTAMPTZ,
  ops_label_id            TEXT,                            -- Gmail label ID or M365 category ID for "OPS Pipeline" tag
  webhook_subscription_id TEXT,                            -- Gmail Pub/Sub watch ID or M365 subscription ID
  webhook_expires_at      TIMESTAMPTZ,
  ai_review_enabled       BOOLEAN DEFAULT false,           -- ongoing AI classification (feature-gated)
  ai_memory_enabled       BOOLEAN DEFAULT false,           -- memory accumulation (feature-gated)
  auto_send_settings      JSONB,                            -- auto-send config: { enabled, business_hours_start, business_hours_end, timezone, delay_min_minutes, delay_max_minutes, enabled_at }
  status                  TEXT DEFAULT 'setup_incomplete',  -- 'active' | 'paused' | 'error' | 'setup_incomplete'
  created_at              TIMESTAMPTZ DEFAULT NOW(),
  updated_at              TIMESTAMPTZ DEFAULT NOW()
);
```

`sync_filters` stores the pattern detection output as JSONB. **Note:** The DB column retains the name `sync_filters` for backward compatibility (migration 034 commented out the rename). The TypeScript type `SyncProfile` maps to this column via the `syncFilters` field on `EmailConnection`.

```json
{
  "estimateSubjectPatterns": ["Canpro Deck and Rail Estimate"],
  "companyDomains": ["canprodeckandrail.com"],
  "teamForwarders": ["jared@canprodeckandrail.com"],
  "knownPlatformSenders": ["notifications@wix-forms.com"],
  "formSubjectPatterns": ["got a new submission", "new form entry"],
  "userEmailAddresses": ["canprojack@gmail.com"],
  "aiClassificationThreshold": 0.7
}
```

`auto_send_settings` stores the per-connection auto-send configuration as JSONB:

```json
{
  "enabled": true,
  "business_hours_start": "08:00",
  "business_hours_end": "18:00",
  "timezone": "America/Toronto",
  "delay_min_minutes": 30,
  "delay_max_minutes": 60,
  "enabled_at": "2026-03-19T14:30:00Z"
}
```

Token columns (`access_token`, `refresh_token`) are accessed via service role only in API routes — not exposed to client via RLS column-level restrictions.

### gmail_scan_jobs

Tracks async inbox analysis jobs during wizard Step 2. **Note:** This table was NOT renamed during the gmail → email migration (only `gmail_connections` was renamed to `email_connections`). The table name `gmail_scan_jobs` persists in the DB and all code references.

```sql
CREATE TABLE gmail_scan_jobs (
  id                          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  connection_id               UUID NOT NULL,
  company_id                  TEXT NOT NULL,
  status                      TEXT NOT NULL DEFAULT 'pending',
  progress                    JSONB DEFAULT '{"stage": "pending", "current": 0, "total": 0, "message": "Starting scan..."}',
  result                      JSONB,
  error_message               TEXT,
  -- Phase C row-level execution lock (migration 070_phase_c_row_lock.sql).
  -- NULL on both = no lock held. See RPC functions below.
  phase_c_lock_holder_id      TEXT,
  phase_c_lock_expires_at     TIMESTAMPTZ,
  created_at                  TIMESTAMPTZ DEFAULT now(),
  updated_at                  TIMESTAMPTZ DEFAULT now()
);
```

**Phase C lock columns** (added 2026-04-19 via migration `070_phase_c_row_lock.sql`):

- `phase_c_lock_holder_id TEXT` — Opaque string identifying the Phase C runner currently processing this row. Composed by callers as `"<stage>:<uuid>"` (e.g. `"entry:9f3c…"` or `"continuation:b81a…"`) so log grepping can tell which invocation last held the lock. NULL means no lock.
- `phase_c_lock_expires_at TIMESTAMPTZ` — Wall-clock expiry for `phase_c_lock_holder_id`. Covers the crash case where a runner dies mid-chunk without calling release; the next attempt treats an expired lock as free.

Chosen over `pg_try_advisory_xact_lock` because xact-level advisory locks release at transaction end — which for chunked Phase C means per-chunk (too short — doesn't protect the multi-chunk run). Session-level advisory locks are keyed to the Postgres connection, which for a pooled service-role client is ambient and can't be released by a different invocation after a crash. Row-level with an expiry avoids both problems.

**Status values** (set by the analyze route during background processing):
- `pending` — Job created, analysis not yet started
- `analyzing_sent` — Phase 1: scanning sent emails for estimate patterns and company domains
- `detecting_platforms` — Phase 1 complete, known platform senders identified
- `classifying_ai` — Phase 2: OpenAI classifying unmatched personal emails as leads vs noise
- `analyzing_threads` — Phase 3: fetching full threads for AI-detected leads, analyzing stage placement
- `complete` — All phases done, results written
- `error` — Analysis failed (see `error_message`)

**`progress` JSONB structure** (updated at each phase transition):
```json
{
  "stage": "classifying_ai",
  "message": "Classifying 47 emails with AI...",
  "percent": 50
}
```

**`result` JSONB structure** (written on completion):
```json
{
  "estimatePattern": "Canpro Deck and Rail Estimate",
  "estimatePatternConfidence": 0.95,
  "estimateThreadCount": 23,
  "detectedSources": [
    { "type": "form_platform", "sender": "notifications@wix-forms.com", "count": 12 }
  ],
  "companyDomains": ["canprodeckandrail.com"],
  "teamForwarders": ["jared@canprodeckandrail.com"],
  "leads": [
    {
      "id": "lead-threadId123",
      "threadId": "threadId123",
      "client": { "name": "John Smith", "email": "john@example.com", "phone": null, "description": "Deck quote" },
      "stage": "qualifying",
      "stageConfidence": 0.85,
      "estimatedValue": 15000,
      "correspondenceCount": 3,
      "outboundCount": 1,
      "source": "ai",
      "sourceLabel": "AI detected",
      "enabled": true,
      "matchResult": { "existingClientId": null, "existingClientName": null, "action": "create", "confidence": 0.0 }
    }
  ],
  "totalScanned": 450
}
```

**RLS:** None — queried via service-role client only.

**Phase C lock RPC functions** (migration `070_phase_c_row_lock.sql`):

```sql
-- Atomic acquisition. Claims the lock iff currently unheld or expired.
-- Returns TRUE on success, FALSE on contention. The WHERE clause is the
-- atomicity guarantee: PostgreSQL evaluates it under row-level locking,
-- so two concurrent callers see serialized access to the same row.
CREATE FUNCTION acquire_phase_c_lock(
  p_job_id UUID,
  p_holder TEXT,
  p_lease_seconds INT DEFAULT 900
) RETURNS BOOLEAN
LANGUAGE plpgsql
AS $$
DECLARE v_rows INT;
BEGIN
  UPDATE gmail_scan_jobs
  SET phase_c_lock_holder_id = p_holder,
      phase_c_lock_expires_at = NOW() + (p_lease_seconds || ' seconds')::INTERVAL
  WHERE id = p_job_id
    AND (phase_c_lock_holder_id IS NULL
         OR phase_c_lock_expires_at < NOW());
  GET DIAGNOSTICS v_rows = ROW_COUNT;
  RETURN v_rows = 1;
END;
$$;

-- Fenced release. Only clears the lock if the supplied holder still owns
-- it. Calling twice with the same holder, or after another runner has
-- stolen an expired lock, is a no-op.
CREATE FUNCTION release_phase_c_lock(
  p_job_id UUID,
  p_holder TEXT
) RETURNS VOID
LANGUAGE plpgsql
AS $$
BEGIN
  UPDATE gmail_scan_jobs
  SET phase_c_lock_holder_id = NULL,
      phase_c_lock_expires_at = NULL
  WHERE id = p_job_id
    AND phase_c_lock_holder_id = p_holder;
END;
$$;
```

**Lease duration:** 900s (default). Chosen slightly longer than the Phase C route's 800s `maxDuration` so a hard crash between the final `runPhaseCChunks` yield and the outer `finally()` can't block a retry for much more than one invocation lifetime. The TypeScript helper in `OPS-Web/src/lib/api/services/phase-c-pipeline-helpers.ts` (`PHASE_C_LOCK_LEASE_SECONDS = 900`) must match this default.

**Fenced-release semantics:** The release UPDATE matches on both `id` and `phase_c_lock_holder_id`, so a double-release is a no-op. This is critical because the inner Phase C runner releases ahead of dispatching a continuation (so the next runner can acquire immediately instead of racing the still-held lock), then the outer route handler's `finally()` runs a second release as a crash safety net. Without fencing, the outer `finally()` could stomp on a fresh lock acquired in the interim by the next runner.

**Caller contract:** `OPS-Web/src/lib/api/services/phase-c-pipeline-helpers.ts` wraps both RPCs as `acquirePhaseCLock(supabase, jobId, "entry" | "continuation")` (returns the holder ID string or null on contention) and `releasePhaseCLock(supabase, jobId, holderId)`. Both Phase C routes (`/api/integrations/email/analyze-memory`, `/api/integrations/email/analyze-memory-continue`) use this pattern; contention means skip without retrying — duplicate dispatch is treated as benign because the holding runner will carry progress forward.

### opportunity_email_threads

Junction table linking opportunities to email thread IDs. Enables fast O(1) sync lookup ("is this thread already linked to an opportunity?") via unique index on `thread_id`.

```sql
CREATE TABLE opportunity_email_threads (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  opportunity_id  UUID NOT NULL REFERENCES opportunities(id) ON DELETE CASCADE,
  thread_id       TEXT NOT NULL,           -- Gmail threadId or M365 conversationId
  connection_id   UUID REFERENCES email_connections(id),
  created_at      TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(thread_id, connection_id)
);

CREATE INDEX idx_oet_thread ON opportunity_email_threads(thread_id);
CREATE INDEX idx_oet_opportunity ON opportunity_email_threads(opportunity_id);
```

### admin_feature_overrides

Per-company OPS admin toggles for gated AI features. Separate from the product-level feature flags — both must be true for a feature to be active. Accessed via service role only (no user-facing RLS).

```sql
CREATE TABLE admin_feature_overrides (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id   UUID NOT NULL REFERENCES companies(id),
  feature_key  TEXT NOT NULL,       -- 'ai_email_review', 'ai_email_memory'
  enabled      BOOLEAN DEFAULT false,
  enabled_by   UUID,                -- OPS admin user ID
  enabled_at   TIMESTAMPTZ,
  metadata     JSONB,               -- cost tracking, notes
  UNIQUE(company_id, feature_key)
);
```

### graph_entities

First-class entity nodes for the knowledge graph. Every person, company, project, service, and material discovered in emails becomes a UUID-keyed entity. Added in Phase C (memory bank).

```sql
CREATE TABLE graph_entities (
  id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id       UUID NOT NULL REFERENCES companies(id),
  entity_type      TEXT NOT NULL,       -- 'person', 'company', 'project', 'service', 'material', 'document'
  name             TEXT NOT NULL,       -- Display name: "John Henderson", "Vitrum Glass"
  normalized_name  TEXT NOT NULL,       -- Lowercase trimmed for dedup: "john henderson", "vitrum glass"
  email            TEXT,                -- Primary email (nullable — companies/services may not have one)
  properties       JSONB DEFAULT '{}',  -- Flexible: phone, role, address, domain, industry, etc.
  confidence       REAL DEFAULT 1.0,    -- How confident this entity is real/accurate (0.0-1.0)
  source           TEXT DEFAULT 'email_import',
  embedding        vector(1536),        -- For semantic entity matching (future fuzzy dedup)
  created_at       TIMESTAMPTZ DEFAULT now(),
  updated_at       TIMESTAMPTZ DEFAULT now(),
  UNIQUE (company_id, entity_type, normalized_name)
);
```

**Entity types:** person (keyed by email), company (keyed by domain), project (name + client), service (normalized name), material (normalized name), document (reference number).

**Entity resolution:** Deterministic — people by email address, companies by email domain. Longer/more-complete name wins on conflict. Confidence threshold 0.7 minimum.

### agent_memories

Core memory entries with pgvector embeddings. Feature-gated behind `ai_email_memory`. Uses ADD/UPDATE/NOOP conflict resolution inspired by Mem0.

```sql
CREATE TABLE agent_memories (
  id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id       UUID NOT NULL REFERENCES companies(id),
  user_id          UUID REFERENCES users(id),
  memory_type      TEXT,              -- 'fact', 'preference', 'trait', 'relationship', 'correction'
  category         TEXT,              -- 16 categories: pricing, commitment, client_preference, client_behavior, budget_signal, material_usage, supplier_pricing, supplier_relationship, employee_pattern, project_event, seasonal_pattern, service_capability, service_area, process, relationship_health, promotion
  content          TEXT,
  embedding        halfvec(1536),     -- pgvector embedding for semantic search
  confidence       FLOAT DEFAULT 1.0,
  source           TEXT,              -- 'email', 'invoice', 'project', 'user_upload', 'draft_edit'
  source_id        TEXT,
  entity_id        UUID REFERENCES graph_entities(id),  -- Phase C: links fact to entity it's about
  valid_from       TIMESTAMPTZ,       -- Phase C: temporal validity start
  valid_to         TIMESTAMPTZ,       -- Phase C: temporal validity end (null = still valid)
  created_at       TIMESTAMPTZ DEFAULT NOW(),
  last_accessed_at TIMESTAMPTZ,
  access_count     INT DEFAULT 0,
  decay_score      FLOAT DEFAULT 1.0
);
```

**Conflict resolution:** Similar fact exists (first-50-chars ilike match) → NOOP (reinforce confidence +0.05, bump access_count). New fact → ADD. Contradictory facts → keep both with valid_from/valid_to timestamps.

### agent_knowledge_graph

Entity relationship edges with temporal validity. Feature-gated behind `ai_email_memory`. Supports both legacy string-based edges and Phase C entity-ID-based edges.

```sql
CREATE TABLE agent_knowledge_graph (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id        UUID NOT NULL REFERENCES companies(id),
  -- Legacy string-based columns (deprecated, preserved for backward compat)
  subject_type      TEXT,              -- 'person', 'company', 'project', 'invoice'
  subject_id        TEXT,
  predicate         TEXT,              -- 'works_for', 'client_of', 'vendor_of', 'subtrade_of', 'quoted_for', 'uses_material', 'supplied_by', 'worked_on', 'communicates_with', 'contact_for'
  object_type       TEXT,
  object_id         TEXT,
  properties        JSONB,
  -- Phase C entity-ID-based columns
  source_entity_id  UUID REFERENCES graph_entities(id),  -- Source node
  target_entity_id  UUID REFERENCES graph_entities(id),  -- Target node
  link_type         TEXT DEFAULT 'extracted',             -- 'extracted', 'manual', 'inferred'
  -- Temporal
  confidence        NUMERIC,
  valid_from        TIMESTAMPTZ,
  valid_to          TIMESTAMPTZ,
  created_at        TIMESTAMPTZ DEFAULT NOW()
);
-- Constraints: (company_id, subject_type, subject_id, predicate, object_type, object_id) for legacy
-- Constraint: akg_entity_edge_unique (company_id, source_entity_id, predicate, target_entity_id) for Phase C
```

**Relationship predicates:** works_for (person→company), contact_for (person→company), client_of (company→company), vendor_of (company→company), subtrade_of (company→company), quoted_for (person/company→service), uses_material (service→material), supplied_by (material→company), worked_on (person→project), communicates_with (person→person).

### agent_writing_profiles

Per-user per-company per-relationship-type communication style profiles. Feature-gated behind `ai_email_memory`. Phase C builds profiles per relationship type (10 types).

```sql
CREATE TABLE agent_writing_profiles (
  id                      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id              UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
  user_id                 UUID NOT NULL REFERENCES users(id),
  profile_type            TEXT NOT NULL DEFAULT 'general',  -- Phase C: relationship type
  formality_score         FLOAT,
  avg_sentence_length     FLOAT,
  greeting_patterns       JSONB,
  closing_patterns        JSONB,
  vocabulary_preferences  JSONB,   -- Also stores common_phrases, hedging_tendency, punctuation_habits
  tone_traits             JSONB,
  emails_analyzed         INT DEFAULT 0,
  updated_at              TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(company_id, user_id, profile_type)
);
```

**Profile types:** client_new_inquiry, client_quoting, client_active_project, client_followup, vendor_ordering, vendor_inquiry, subtrade_coordination, warranty_claim, internal, general. Clustered for galaxy visualization: client, vendor, subtrade, internal, general.

### email_templates

Company-scoped email templates with merge field support. Used by the compose flow and AI draft generation.

```sql
CREATE TABLE email_templates (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  subject TEXT NOT NULL DEFAULT '',
  body TEXT NOT NULL DEFAULT '',
  category TEXT NOT NULL CHECK (category IN ('follow_up','scheduling','estimate','invoice','introduction','general')),
  sort_order INT NOT NULL DEFAULT 0,
  is_active BOOLEAN NOT NULL DEFAULT true,
  created_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
```

**RLS:** Company-scoped (SELECT/INSERT/UPDATE/DELETE).

**Index:** `(company_id, category, sort_order) WHERE is_active = true`

**Merge fields:** `{{client_name}}`, `{{project_title}}`, `{{company_name}}` — resolved at send time by the compose/draft layer.

### ai_draft_history

Tracks AI-generated email drafts for edit tracking and writing profile learning. Each draft records the original AI output and the final user-edited version, enabling edit distance computation and auto-send confidence scoring.

```sql
CREATE TABLE ai_draft_history (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id UUID NOT NULL,
  user_id UUID NOT NULL,
  opportunity_id UUID,
  connection_id UUID,
  thread_id TEXT,
  original_draft TEXT NOT NULL,
  final_version TEXT,
  status TEXT NOT NULL DEFAULT 'drafted' CHECK (status IN ('drafted','sent','discarded')),
  sent_without_changes BOOLEAN DEFAULT false,
  edit_distance INT DEFAULT 0,
  changes_made JSONB DEFAULT '{}',
  sent_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
```

- `edit_distance`: Word-level Levenshtein distance between `original_draft` and `final_version`.
- `changes_made`: Structured diff — `{ greeting?: {from, to}, closing?: {from, to}, tone?: string }`.
- When `sent_without_changes` reaches 95% over 20+ drafts, auto-send is suggested to the user.

### pending_auto_sends

Auto-send queue for AI-generated email drafts held for randomized delay before sending. Business hours enforced (default 8am-6pm in user's timezone). Processed by cron job `/api/cron/auto-send` every 5 minutes.

```sql
CREATE TABLE pending_auto_sends (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id UUID NOT NULL,
  connection_id UUID NOT NULL,
  opportunity_id UUID,
  thread_id TEXT,
  in_reply_to TEXT,
  to_emails TEXT[] DEFAULT '{}',
  cc_emails TEXT[] DEFAULT '{}',
  subject TEXT NOT NULL,
  draft_text TEXT NOT NULL,
  draft_history_id UUID REFERENCES ai_draft_history(id),
  scheduled_send_at TIMESTAMPTZ NOT NULL,
  status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','sent','cancelled','failed')),
  retry_count INT NOT NULL DEFAULT 0,
  sent_at TIMESTAMPTZ,
  cancelled_at TIMESTAMPTZ,
  error TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
```

- **Delay:** Randomized between `delay_min_minutes` and `delay_max_minutes` from `email_connections.auto_send_settings` (default 30-60 min).
- **Business hours:** Sends only within `business_hours_start`-`business_hours_end` in the user's timezone. If scheduled outside hours, deferred to next business window.
- **Retries:** Max 3 retries, then permanently set to `failed`.
- **Cancellation:** User can cancel pending sends from the UI before `scheduled_send_at`.

### Modified Tables: opportunities

New columns added to `opportunities` for email correspondence tracking:

```sql
ALTER TABLE opportunities ADD COLUMN correspondence_count INT DEFAULT 0;
ALTER TABLE opportunities ADD COLUMN outbound_count INT DEFAULT 0;
ALTER TABLE opportunities ADD COLUMN inbound_count INT DEFAULT 0;
ALTER TABLE opportunities ADD COLUMN last_inbound_at TIMESTAMPTZ;
ALTER TABLE opportunities ADD COLUMN last_outbound_at TIMESTAMPTZ;
ALTER TABLE opportunities ADD COLUMN last_message_direction TEXT;    -- 'in' | 'out'
ALTER TABLE opportunities ADD COLUMN ai_stage_confidence FLOAT;
ALTER TABLE opportunities ADD COLUMN ai_stage_signals TEXT[];
ALTER TABLE opportunities ADD COLUMN detected_value INT;
ALTER TABLE opportunities ADD COLUMN stage_manually_set BOOLEAN NOT NULL DEFAULT false;
ALTER TABLE opportunities ADD COLUMN ai_summary TEXT;
```

- `stage_manually_set`: Set to `true` when user manually drags card to new stage; prevents AI/deterministic stage override. Cleared to `false` when new inbound email arrives (situation evolved, AI can re-evaluate).
- `ai_summary`: 1-2 sentence AI-generated summary of the opportunity, cached and refreshed each sync cycle that touches the thread via `evaluateStagesWithSummary()`.

These columns are used by the sync engine's correspondence-count stage rules (free tier) and AI stage evaluation (gated tier).

### Note: companies.industry Column

The `companies` table has an `industries` column (TEXT array, from migration 004) but does **not** have an `industry` (singular) column. The email pipeline code does `.select("name, industry")` on companies, but PostgREST returns `null` for the nonexistent column. The code falls back to `"trades"` via `(company?.industry as string) || "trades"`. No migration was created to add this column. If per-company industry classification is needed in the future, either use the existing `industries` array or add an `industry TEXT` column via a new migration.

### email_filter_presets

```sql
CREATE TABLE email_filter_presets (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  category    TEXT NOT NULL,          -- e.g., 'newsletters', 'notifications', 'retailers'
  type        TEXT NOT NULL,          -- 'domain' | 'keyword'
  value       TEXT NOT NULL,          -- e.g., 'noreply.github.com' or 'unsubscribe'
  is_active   BOOLEAN DEFAULT true,
  created_at  TIMESTAMPTZ DEFAULT NOW()
);
```

Seeded with ~100+ common noise sources across categories.

### email_threads (Inbox v2, migration 071 — 2026-04-20)

Per-thread state for the rebuilt inbox. Every email the company sees gets a
row here — denormalized so list queries are a single-table scan.

```sql
CREATE TABLE public.email_threads (
  id                          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id                  uuid NOT NULL REFERENCES companies(id),
  connection_id               uuid NOT NULL REFERENCES email_connections(id),
  provider_thread_id          text NOT NULL,          -- Gmail threadId | M365 conversationId

  -- Primary classification (exactly one)
  primary_category            text NOT NULL DEFAULT 'OTHER'
    CHECK (primary_category IN ('LEAD','CLIENT','VENDOR','SUBTRADE','PLATFORM_BID',
                                 'LEGAL','JOB_SEEKER','COLLECTIONS','MARKETING',
                                 'RECEIPT','PERSONAL','INTERNAL','OTHER')),
  category_confidence         numeric(3,2) DEFAULT 0.0,
  category_classified_at      timestamptz,
  category_classifier_version text DEFAULT 'v1',
  category_manually_set       boolean NOT NULL DEFAULT false,

  -- Secondary labels (multi)
  labels                      text[] NOT NULL DEFAULT '{}',

  -- Triage
  archived_at                 timestamptz,
  snoozed_until               timestamptz,
  priority_score              numeric(4,2) DEFAULT 0.0,
  ai_summary                  text,

  -- Denormalized summary (updated from latest message on each sync tick)
  subject                     text,
  participants                text[] DEFAULT '{}',
  first_message_at            timestamptz NOT NULL,
  last_message_at             timestamptz NOT NULL,
  message_count               int NOT NULL DEFAULT 0,
  unread_count                int NOT NULL DEFAULT 0,
  latest_direction            text CHECK (latest_direction IN ('inbound','outbound')),
  latest_sender_email         text,
  latest_sender_name          text,
  latest_snippet              text,

  -- Linkage (nullable — VENDOR/LEGAL/etc. threads won't have these)
  opportunity_id              uuid REFERENCES opportunities(id),
  client_id                   uuid REFERENCES clients(id),

  created_at                  timestamptz NOT NULL DEFAULT now(),
  updated_at                  timestamptz NOT NULL DEFAULT now(),

  CONSTRAINT email_threads_unique_provider UNIQUE (connection_id, provider_thread_id)
);
```

**Indexes (migration 071):**
- `idx_email_threads_company_lastmsg` — `(company_id, last_message_at DESC) WHERE archived_at IS NULL AND snoozed_until IS NULL` — drives the Everything rail
- `idx_email_threads_company_category` — `(company_id, primary_category, last_message_at DESC) WHERE archived_at IS NULL` — drives category filter chips
- `idx_email_threads_snoozed` — `(snoozed_until) WHERE snoozed_until IS NOT NULL` — drives `/api/cron/unsnooze`
- `idx_email_threads_opportunity` — `(opportunity_id) WHERE opportunity_id IS NOT NULL` — back-reference from pipeline

The 13 primary categories and the 6 secondary labels (`URGENT`,
`AWAITING_REPLY`, `HAS_ATTACHMENT`, `HAS_QUOTE`, `HAS_INVOICE`,
`FROM_NEW_SENDER`) are enforced only in application code (the CHECK covers
primary only; labels are an application-level contract).

### email_thread_category_corrections (migration 071)

Learning feedback for Phase C. Every time the user recategorizes a thread
manually, we record the from/to categories plus signals (sender email,
domain, participant hash, subject keywords) so the classifier can fan out
the correction to similar threads.

```sql
CREATE TABLE public.email_thread_category_corrections (
  id                   uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id           uuid NOT NULL REFERENCES companies(id),
  thread_id            uuid NOT NULL REFERENCES email_threads(id) ON DELETE CASCADE,
  user_id              uuid NOT NULL REFERENCES users(id),
  from_category        text NOT NULL,
  to_category          text NOT NULL,
  sender_email         text,
  sender_domain        text,
  participants_hash    text,
  subject_keywords     text[],
  note                 text,
  applied_to_similar   boolean NOT NULL DEFAULT false,
  similar_count        int NOT NULL DEFAULT 0,
  created_at           timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX idx_corrections_company_domain
  ON email_thread_category_corrections(company_id, sender_domain)
  WHERE sender_domain IS NOT NULL;
```

### Column additions (migration 071)

```sql
-- First-archive write-back preference per email connection
ALTER TABLE email_connections
  ADD COLUMN archive_writeback_preference text
    CHECK (archive_writeback_preference IN ('ask','archive_in_gmail','mark_read_only','ops_only'))
    DEFAULT 'ask';

-- Per-message classifier provenance
ALTER TABLE activities
  ADD COLUMN classified_at timestamptz,
  ADD COLUMN classifier_version text;
```

### Column addition: `activities.draft_history_id` (migration 20260508120000)

Links an activity row (a sent email) back to the `ai_draft_history` entry that produced it, so the inbox UI can render an AI-edit diff toggle on AI-authored outbound bubbles. Populated by `/api/integrations/email/send` from `pending_auto_sends.draft_history_id` when an auto-send actually fires.

```sql
ALTER TABLE activities
  ADD COLUMN IF NOT EXISTS draft_history_id UUID
  REFERENCES ai_draft_history(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_activities_draft_history
  ON activities(draft_history_id)
  WHERE draft_history_id IS NOT NULL;
```

- **Additive only:** nullable column, no destructive changes — safe under the iOS App Store sync constraint (no breakage for users still on the prior iOS build).
- **`ON DELETE SET NULL`:** if the draft history row is purged for cleanup, the activity stays but loses its diff capability.
- **Partial index:** only indexes rows with a non-null FK (the vast majority of activities are inbound or non-AI outbound, so the index stays small).
- **UI consumer:** `MessageBubble.originalAiBody` prop. When the activity has a `draft_history_id`, the renderer joins to `ai_draft_history.original_draft` and passes it down. The bubble shows a `DIFF` toggle that opens an inline word-diff (deletions strikethrough, insertions white on lavender highlight — preserving the rule that lavender = Claude-authored, white = operator).

### Phase C category autonomy (JSONB on email_connections — no new columns)

Per-primary-category autonomy lives under
`email_connections.auto_send_settings.category_autonomy`, keyed by
`primary:<CATEGORY>`. Example stored value:

```jsonb
{
  "primary:LEAD":         "auto_draft",
  "primary:CLIENT":       "auto_send",
  "primary:VENDOR":       "auto_draft",
  "primary:PLATFORM_BID": "auto_archive",
  "primary:LEGAL":        "draft_on_request",
  "primary:RECEIPT":      "auto_archive",
  "client_new_inquiry":   "auto_send",       // legacy per-relationship key
  "vendor_ordering":      "auto_draft"       // legacy per-relationship key
}
```

The legacy per-relationship keys (`client_new_inquiry`, `vendor_ordering`,
etc.) continue to drive the ai-draft-service writing-profile graduation
checks. Inbox v2 adds the `primary:*` namespace alongside — no migration
touches this column since it's JSONB.

### RPC get_inbox_density_per_client (migration 073)

Used by the Intel galaxy to size client-node thread-density halos.

```sql
CREATE OR REPLACE FUNCTION public.get_inbox_density_per_client(p_company_id uuid)
RETURNS TABLE (client_id uuid, thread_count int, last_message_at timestamptz)
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = public
AS $$
  SELECT client_id, COUNT(*)::int, MAX(last_message_at)
  FROM public.email_threads
  WHERE company_id = p_company_id
    AND client_id IS NOT NULL
    AND archived_at IS NULL
  GROUP BY client_id;
$$;
```

### RLS Policies (Email Integration)

All new tables require Row-Level Security:

```sql
-- email_connections: company-scoped
ALTER TABLE email_connections ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can view own company connections"
  ON email_connections FOR SELECT USING (company_id = auth.jwt()->>'company_id');
CREATE POLICY "Users can manage own company connections"
  ON email_connections FOR ALL USING (company_id = auth.jwt()->>'company_id');

-- opportunity_email_threads: via opportunity's company
ALTER TABLE opportunity_email_threads ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Company-scoped thread access"
  ON opportunity_email_threads FOR ALL
  USING (opportunity_id IN (SELECT id FROM opportunities WHERE company_id = auth.jwt()->>'company_id'));

-- admin_feature_overrides: OPS admin only (service role)
ALTER TABLE admin_feature_overrides ENABLE ROW LEVEL SECURITY;
-- No user-facing RLS — accessed via service role in admin API routes only

-- graph_entities: company-scoped (Phase C)
ALTER TABLE graph_entities ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Company members can view their entities"
  ON graph_entities FOR SELECT USING (company_id = (auth.jwt()->>'company_id')::uuid);
CREATE POLICY "Service role has full access to entities"
  ON graph_entities FOR ALL USING (auth.role() = 'service_role');

-- agent_memories, agent_knowledge_graph, agent_writing_profiles: company-scoped
ALTER TABLE agent_memories ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Company-scoped memories"
  ON agent_memories FOR ALL USING (company_id = auth.jwt()->>'company_id');

ALTER TABLE agent_knowledge_graph ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Company-scoped knowledge graph"
  ON agent_knowledge_graph FOR ALL USING (company_id = auth.jwt()->>'company_id');

ALTER TABLE agent_writing_profiles ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Company-scoped writing profiles"
  ON agent_writing_profiles FOR ALL USING (company_id = auth.jwt()->>'company_id');
```

---

### 26. TaskTypeReminder (Supabase-Backed) — bug 4f00c2d7

**File**: `DataModels/TaskTypeReminder.swift`
**Purpose**: Reminder template attached to a TaskType. Materialized server-side via triggers into per-task `TaskReminder` rows whenever a `project_tasks` row is created or the template is added/edited on an open task.

**Properties**:

```swift
@Model
final class TaskTypeReminder: Identifiable {
    @Attribute(.unique) var id: String
    var taskTypeId: String
    var companyId: String
    var label: String
    var leadTimeDays: Int
    var fireTimeLocalSeconds: Int     // 0..86399, in companies.timezone
    var requiresAck: Bool
    var recipientModeRaw: String      // 'task_crew'|'admins'|'permission'|'users'
    var recipientConfigJSON: String   // encoded ReminderRecipientConfig
    var displayOrder: Int
    var lastSyncedAt: Date?
    var needsSync: Bool
    var deletedAt: Date?
    @Relationship(deleteRule: .nullify) var taskType: TaskType?
}
```

Inverse on `TaskType.reminderTemplates: [TaskTypeReminder]` (cascade delete).

**Computed**: `recipientMode`, `recipientConfig`, `fireTimeOfDay`, `leadTimeDisplay`.

Postgres table: `public.task_type_reminders` — see `07_SPECIALIZED_FEATURES.md` §24 for the full schema and triggers. RLS scoped to `private.get_user_company_id()`.

---

### 27. TaskReminder (Supabase-Backed) — bug 4f00c2d7

**File**: `DataModels/TaskReminder.swift`
**Purpose**: Per-ProjectTask reminder instance. Carries a snapshot of the template that materialized it (live-linked while the parent task is open and the reminder is unacknowledged) plus per-instance state — `fires_at`, `acknowledged_at`, `acknowledged_by`, `dismissed_at`, `notified_at`.

**Properties**:

```swift
@Model
final class TaskReminder: Identifiable {
    @Attribute(.unique) var id: String
    var taskId: String
    var companyId: String
    var sourceTemplateId: String?
    var label: String
    var leadTimeDays: Int
    var fireTimeLocalSeconds: Int
    var requiresAck: Bool
    var recipientModeRaw: String
    var recipientConfigJSON: String
    var firesAt: Date?
    var acknowledgedAt: Date?
    var acknowledgedBy: String?
    var dismissedAt: Date?
    var notifiedAt: Date?
    var lastSyncedAt: Date?
    var needsSync: Bool
    var deletedAt: Date?
    @Relationship(deleteRule: .nullify) var task: ProjectTask?
}
```

Inverse on `ProjectTask.reminders: [TaskReminder]` (cascade delete).

**Computed**: `isAcknowledged`, `isDismissed`, `isCleared`, `leadTimeDisplay`, `dueDisplay`.

Postgres table: `public.task_reminders`. Live-link / freeze / soft-delete propagation via the triggers documented in `07_SPECIALIZED_FEATURES.md` §24. Cron dispatcher `fire_due_task_reminders()` writes one `notifications` row per resolved recipient when `fires_at <= now()`.

### 28. CalendarMirrorMap (iOS Client-Local) — bug 68123654

**File**: `DataModels/CalendarMirrorMap.swift`
**Purpose**: Side-table powering the iPhone Calendar Mirror feature. Maps OPS row IDs (`CalendarUserEvent.id`, `ProjectTask.id`) to the EventKit `EKEvent.eventIdentifier` written into the user's iPhone Calendar's dedicated "OPS" calendar.

**Storage:** SwiftData `@Model`, additive in `OPSSchemaV3` (lightweight migration from V2). **Never synced to Supabase.** Wiped on logout, company switch, or feature disable. No Postgres counterpart — this is purely a client-local mapping that lets the reconciler perform O(1) lookups instead of scanning the calendar.

**Properties**:

```swift
@Model
final class CalendarMirrorMap {
    @Attribute(.unique) var opsId: String         // CalendarUserEvent.id or ProjectTask.id
    var ekEventIdentifier: String                 // EKEvent.eventIdentifier (stable across edits)
    var sourceType: String                        // MirrorSource.rawValue
    var contentHash: String                       // SHA-256 of "title|start|end|notes|allDay"
    var lastMirroredAt: Date
}
```

Companion enum (lives in the same file):

```swift
enum MirrorSource: String, Codable {
    case calendarUserEvent
    case projectTask
}
```

The `contentHash` field doubles as drift detection — on reconcile, a mismatch between the stored hash and the live row's hash means "user edited the EKEvent in iOS Calendar" and triggers a silent revert (one-way mirror invariant).

Related: see `07_SPECIALIZED_FEATURES.md` §26 "iPhone Calendar Mirror".

---

## Cashflow Forecast (2026-05-11)

Supabase schema deltas for the Cashflow Forecast feature (Card 6 of the BOOKS hero carousel). All deltas are **additive** — no rename, retype, or drop. Detailed semantics in `09_FINANCIAL_SYSTEM.md § Cashflow Forecast`. iOS SwiftData parity ships in `OPSSchemaV6` (adds `PaymentMilestone` and `RecurringExpense` models).

### New tables

| Table | Purpose |
|-------|---------|
| `recurring_expenses` | Owner-managed recurring outflows (rent, insurance, payroll, subscriptions). Drives the recurring layer of the forecast. Forecast-only — does NOT auto-create rows in `expenses`. |
| `forecast_alerts` | Per-company anti-spam ledger for the persistent `forecast_dip` notification. Tracks last-notified state and "don't show again" dismissals. |

**`recurring_expenses` columns:**

```
id              uuid PRIMARY KEY DEFAULT gen_random_uuid()
company_id      uuid NOT NULL → companies(id) ON DELETE CASCADE
name            text NOT NULL
amount          numeric(12,2) NOT NULL CHECK (amount >= 0)
currency        text NOT NULL DEFAULT 'USD'
cadence         text NOT NULL CHECK (cadence IN ('weekly','biweekly','monthly','quarterly','annually'))
next_due_date   date NOT NULL
end_date        date NULL
category_id     uuid NULL → expense_categories(id)
notes           text NULL
created_by      uuid NULL → users(id)
created_at      timestamptz NOT NULL DEFAULT now()
updated_at      timestamptz NOT NULL DEFAULT now()  -- maintained by trigger
deleted_at      timestamptz NULL
```

RLS: `company_isolation` policy using `company_id = (SELECT private.get_user_company_id())` — matches `estimates`/`invoices`/`opportunities` pattern.

**`forecast_alerts` columns:**

```
company_id              uuid PRIMARY KEY → companies(id) ON DELETE CASCADE
last_dip_notified_at    timestamptz NULL
last_dip_min_balance    numeric(12,2) NULL
last_dip_min_week_start date NULL
last_cleared_at         timestamptz NULL
dismissed_until_balance numeric(12,2) NULL
updated_at              timestamptz NOT NULL DEFAULT now()  -- maintained by trigger
```

RLS: same `company_isolation` pattern.

### Additive columns on existing tables

| Table | Column | Type | Default | Purpose |
|-------|--------|------|---------|---------|
| `payment_milestones` | `expected_date` | `date NULL` | NULL | When this milestone is expected to be invoiced. Drives contracted-layer forecast projection. Existing rows backfill to NULL; engine falls back to project-span derivation. |
| `expense_settings` | `forecast_low_water_threshold` | `numeric(12,2) NULL` | `5000` | Amber-warning trigger for the forecast chart. |
| `expense_settings` | `forecast_current_balance` | `numeric(12,2) NULL` | NULL | Manually-entered current bank balance — the starting balance for the forecast projection. |
| `expense_settings` | `forecast_balance_updated_at` | `timestamptz NULL` | NULL | Timestamp of the last `forecast_current_balance` update. Drives the "AS OF [date]" stale-balance UI hint. |

### iOS SwiftData parity (OPSSchemaV6)

V6 is purely additive over V5 (Calendar Mirror). Adds two new `@Model` entities:

- `PaymentMilestone` — iOS parity for the existing server table (deferred from earlier estimate work). Read-side only in v1; estimate form writes via `EstimateService` payload.
- `RecurringExpense` — CRUD-capable, mirrors the server table.

Migration: `OPSMigrationPlan` registers a lightweight `V5 → V6` stage. No data transform, no field rename.

**End of Data Architecture Documentation**
