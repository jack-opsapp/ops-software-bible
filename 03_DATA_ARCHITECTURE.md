# 03: Data Architecture

**Last Updated**: 2026-08-04
**Status**: Comprehensive Reference
**Purpose**: Complete data layer specification for OPS iOS/Android applications

---

## Table of Contents

1. [Overview](#overview)
2. [SwiftData Models (Registered Entities)](#swiftdata-models-registered-entities)
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

### The Current Registered Schema Models

As defined by the version-scoped model groups in `OPSSchemaCommon`, plus `WizardState` and `CalendarMirrorMap`. The production container is built from `OPSSchemaV16` through `OPSMigrationPlan` in `OPSApp.swift` (ops-ios commit `a554ee7c`, 2026-07-16).

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
49. **DeckDesign** -- Canvas drawing data for design components and deck-scoped JSON blocks (`components[]`, `framing`, `terrain`)

**Per-Schema-Version (1):**
- **WizardState** -- Onboarding wizard state (schema-versioned; appended in each `OPSSchemaV*.models`)

> Legacy note: `InventoryItem`, `InventorySnapshot`, `InventorySnapshotItem`, `InventoryTag`, `InventoryUnit` files remain on disk through the V2→V3 migration window for compile-time references but are NOT registered in `OPSSchemaCommon`. They are removed by Phase 4 of the catalog plan. SQL-side, the `inventory_*` tables are renamed to `catalog_*` by migration `2026-05-06-01-catalog-schema.sql`.

---

## SwiftData Models (Registered Entities)

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
    var primarySubClientId: String? // Explicit project contact from client.subClients
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

    // Server-maintained row-touched timestamp — added 2026-05-15 (bug
    // 70a4d9fd) to power the JobBoard "latest edited" sort. Mirrors
    // `projects.updated_at`, auto-bumped by Supabase on every write.
    // Outbound DTO callers omit this field; inbound DTO reads it.
    // Nil for projects synced down before this column was plumbed —
    // the sort falls back to `createdAt` in that case.
    var updatedAt: Date?

    // Transient
    @Transient var lastTapped: Date?
    @Transient var coordinatorData: [String: Any]?

    // Project Workspace Modal columns (Supabase only — added 2026-05-06)
    // visibility       TEXT DEFAULT 'all' CHECK ∈ {all, office, private} — portal exposure; private projects do not appear in the client portal
    //   Partial index idx_projects_visibility WHERE visibility != 'all' speeds the office/private filter on company dashboards.

    // Audit columns (Supabase) — also surfaced as SwiftData properties
    // created_at       TIMESTAMPTZ — auto-populated by Supabase default
    // created_by       UUID FK → auth.users(id) — populated by iOS on insert; index idx_projects_created_by_created_at (created_by, created_at DESC) WHERE deleted_at IS NULL speeds the recency strip query.
    // updated_at       TIMESTAMPTZ — auto-maintained by Supabase trigger; read-only from iOS, drives the JobBoard "latest edited" sort (see OPS/Views/JobBoard/JobBoardProjectListView.swift `recencyStamp(for:)`).
    // primary_sub_client_id UUID NULL FK → sub_clients(id) ON DELETE SET NULL — explicit project contact; NULL uses the parent client.
    // vinyl_order_status TEXT DEFAULT 'not_ordered' CHECK ∈ {not_ordered, ordered} — Deck Builder marker-only vinyl status.
    // vinyl_ordered_at   TIMESTAMPTZ NULL — when project vinyl was marked ordered.
    // vinyl_ordered_by   UUID FK → public.users(id) ON DELETE SET NULL, NULL — who marked vinyl ordered (retargeted 2026-07-04 from an auth.users default; see note).
    // vinyl_color        TEXT NULL — ordered vinyl color record (added 2026-07-16, VINYL ORDERS board; migration add_projects_vinyl_color_po).
    // vinyl_po           TEXT NULL — supplier PO reference for the vinyl order (added 2026-07-16, same migration).
    // vinyl_source       TEXT NULL CHECK ∈ {supplier, shop} — where the material came from (VINYL ORDER RECORD, 2026-08-18; migration add_projects_vinyl_source). **PENDING: written but NOT YET APPLIED — the iOS build that writes it must not ship first.** NULL = not recorded, read as `supplier`. vinyl_order_status stays 'ordered' for BOTH dispositions: its CHECK admits only not_ordered/ordered and every shipped iOS build decodes an unknown status as `.notOrdered`, which would re-surface a handled job on the VINYL ORDERS board. Deliberately NOT projected onto `ProjectVinylOrderMarker` — the authoritative record is the frozen design snapshot, so no SwiftData schema version was spent on it.
}
```

**Primary project contact contract (production schema live 2026-08-21; iOS
distribution pending):** migration `20260821185843_project_primary_sub_client.sql`
adds nullable `projects.primary_sub_client_id` plus a partial index. A private,
search-path-hardened validation trigger accepts only an active `sub_clients` row
that belongs to the project's current `client_id` and `company_id`. Changing the
project's client through an older caller clears an inherited selection rather
than carrying the wrong person forward; deleting or re-parenting the selected
sub-client also clears affected projects. Existing projects remain NULL and no
customer rows are rewritten by the migration.

iOS persists the nullable id on `Project` and round-trips it through
`SupabaseProjectDTO`, delta pull, realtime/cache merge, local generic updates,
and field-level write protection. `primaryProjectContact` rejects stale,
deleted, and re-parented local relationships. The explicit contact supplies the
project's email, phone, and `effectiveProjectContactName`; without a selection,
OPS uses only the parent client and never chooses an arbitrary first
sub-contact. `effectiveClientName` remains the parent client/company label. An
assignment commits the local selection and its `SyncOperation` in one SwiftData
transaction; failure leaves the prior choice visible and queued state unchanged.
The outbound cross-entity barrier maps `primary_sub_client_id` to `subClient`,
so an assignment to an offline-created contact waits for that contact's create
instead of parking on the server validation trigger.

The migration is applied in production under ledger name
`project_primary_sub_client_20260821185843`. Independent readback confirmed the
column, foreign key, partial index, validation/compatibility triggers, enabled
project RLS, and zero automatic assignments across existing projects. The web
contract is customer-live in OPS-Web production commit `6b69551a`; the iOS
implementation is merged and pushed on `main` commit `677850ee`, ready for a
signed device build but not distributed through Apple by this rollout.

**Deck Builder Vinyl Marker (2026-05-21)**: `projects.vinyl_order_status`,
`projects.vinyl_ordered_at`, and `projects.vinyl_ordered_by` are a
marker-only project field gated in UI by `deck_builder`. They do not create
catalog orders, reserve inventory, deduct stock, resolve recipes, or materialize
`task_materials`. iOS stores an offline projection in `ProjectVinylOrderMarker`
so the Details tab can read the marker without mutating the historical
`Project` SwiftData model shape.

> **`vinyl_ordered_by` FK retarget (applied 2026-07-04, bug 0f86b9b0/c6e90385):**
> the column originally FK'd to `auth.users(id)` (a template default), but under
> the Firebase JWT bridge a user's `public.users.id` is never present in
> `auth.users`, so any real id FK-failed and a Firebase UID 22P02s. It had never
> been successfully written (0 rows). The FK was **retargeted to
> `public.users(id) ON DELETE SET NULL`** (mirrors `catalog_orders.created_by_id`);
> the migration is a no-op on data (0 rows) and transparent to installed iOS
> builds (the column stays uuid). Both "mark ordered" paths (Vinyl Order sheet +
> Job Board vinyl filter) now attribute to the operator's lowercased
> `public.users.id`. The outbound `SupabaseUUID` guard still nulls any non-uuid
> attribution so a legacy queued Firebase-UID write can't wedge the sync queue.
> Migration SQL archived at `ops-ios/docs/artifacts/vinyl-ordered-by-fk-retarget.sql`.

**VINYL ORDERS board (2026-07-16 — replaces the 2026-07-04 inline vinyl
filter)**: the Job Board `VINYL` pill (shown only when the company defines a
task type whose display contains "vinyl") now presents a full-height
procurement board sheet (`OPS/Views/JobBoard/VinylOrdersBoardView.swift`)
instead of an inline list filter; the per-card strip and filter plumbing were
deleted. The board lists company projects with `status ∈ {accepted,
in_progress}` carrying ≥1 incomplete vinyl task, grouped `// TO ORDER`
(earliest vinyl-task start first, unscheduled last) and `// ORDERED`
(`vinyl_ordered_at` desc), all marker-driven (zero geometry at render). Rows
expand to the order record (snapshot-first, marker `vinyl_color`/`vinyl_po`
fallback), client + address, `OPEN PROJECT`, and `CLEAR ORDERED`. Multi-select
offers bulk `MARK ORDERED` (gated `projects.edit`; full snapshot freeze where a
deck drawing resolves materials, marker-fields-only otherwise) and the bulk
`ORDER` wizard (gated deck_builder feature + `deck_builder.view` +
`projects.edit`) which composes ONE combined supplier text (per-job cuts +
aggregated drip/90/clip tubes + glue buckets; `deckBuilder.vinylOrder.
clipPerTube`/`flashingPerTube` @AppStorage, defaults 50/30) and auto-marks
every job on send. New columns `vinyl_color` + `vinyl_po` ride every
mark/order write in the same atomic `updateProjectFields` payload as the
status trio; `clearOrdered` nulls all five. Pure logic:
`VinylOrdersBoardModel`, `VinylConsumablesAggregator`, `VinylBulkOrderComposer`,
`VinylBulkMarkService` (all unit-tested). iOS projection
`ProjectVinylOrderMarker` gained `vinylColor`/`vinylPO` behind SwiftData schema
V17 (V7–V16 marker shape frozen as `OPSSchemaLegacyVinylOrderV16`).

**VINYL ORDER RECORD (2026-08-18)**: what the operator ACTUALLY ordered is now
the record, not what the calculator produced. Every MARK ORDERED path freezes a
`DeckMaterialsOrderConfirmation` carrying the operator's confirmed quantities, a
`VinylOrderDisposition` (`supplier` | `shop` — "use material at shop" is a
sibling outcome of the same act, and zeroing the form is how the shop path
expresses itself), and `[VinylSharedConsumable]` for tubes/buckets bought once
across a batch. Shared lines store the count AS BOUGHT plus the other jobs it
was split with — never a per-job fraction. The bulk ORDER wizard previously
committed the calculated list and discarded both the per-job quantity edits and
the send-page consumable counts; it now records them. A job marked `shop` drops
out of the supplier message and the consumables aggregate but still commits as
handled. Snapshot additions (`disposition`, `sharedConsumables`) are additive
Codable inside `DeckDrawingData` JSON with decode fallbacks — **no SwiftData
`@Model` was touched**. Every mark also writes a `project_notes` row with
`event_kind = 'vinyl_order'` (see 07 § VINYL ORDERS).

**Key Computed Properties**:

```swift
var computedStartDate: Date? { tasks.compactMap { $0.startDate }.min() }
var computedEndDate: Date? { tasks.compactMap { $0.endDate }.max() }
var effectiveClientName: String { client?.name ?? "" }
var primaryProjectContact: SubClient? { ... } // Explicit active same-client selection
var effectiveProjectContactName: String { ... }
var effectiveClientEmail: String? { ... }   // Explicit contact, then parent client
var effectiveClientPhone: String? { ... }   // Explicit contact, then parent client
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

**Scheduling push & cascade semantics** (iOS; rewritten 2026-06-10 — bugs 6aad9984, efb57ffc):
- **Push engine** (`OPS/Utilities/SchedulingEngine.swift`): `pushByDays(task:days:skipWeekends:)`
  is the day-nudge path; `pushByCalendarWeeks(task:weeks:)` is the week path. A **week push**
  ("+1 week" on every surface — Project/Task details, the review reschedule sheet, the
  month-grid "Push 1 week", and the day-canvas single + bulk push) adds `.weekOfYear` —
  exactly +7 calendar days, **weekday-preserving, never weekend-normalized**. The old
  behavior (+7 days then weekend-skip) over-advanced a weekend-anchored task to +9
  (Sat→Mon) on some surfaces; routing every week affordance through `pushByCalendarWeeks`
  unified it. Week-count is derived as `days / 7` everywhere (sign-preserving).
- **Weekend skip by default** (added 2026-06-10): every manual **day** push honors
  `companies.skip_weekends_in_auto_schedule` (default **true** — most trades don't work
  weekends), not just the auto-scheduler. A +1/+2/+3-day nudge that lands on Sat/Sun
  advances to the next weekday unless the company has enabled weekend work. Threaded into
  the views via `DataController.currentCompanySkipsWeekends` (defaults to skip when no
  company is loaded). Week pushes stay no-skip.
- **Dependency cascade** (`calculateCascade`): when a task moves, downstream tasks whose
  `effectiveDependencies` point at a moved predecessor shift forward to satisfy
  `TaskTypeDependency.earliestStart(...)`. Skips `schedulingLocked` tasks; weekend-normalizes
  shifted starts when the company skips weekends. Scoped to the pushed task's **project**
  (predecessors match by `taskTypeId`, so a company-wide set would invent cross-project links).
- **Crew cascade — forward-only consolidate** (added 2026-06-10, bug efb57ffc): pushing a
  task via an explicit **Cascade** action also ripples that task's crew. Every other active,
  unlocked task that shares ≥1 `team_member_id` (evaluated **company-wide / across projects**)
  and starts on/after the pushed task's original day packs tightly **forward** to close the
  gap, but is **never pulled earlier than its current day** (the field-safe direction —
  pushing later is safe, pulling earlier can break a customer/material commitment). Locked
  crew jobs stay put and act as obstacles the moved jobs pack around; completed/cancelled
  jobs are excluded; collisions among auto-moved jobs are impossible by construction.
  Implemented as `calculateCrewConsolidation(...)`; the dependency cascade then runs **on
  top** (seeded with the crew dates via `calculateCascade(seededDates:)`) and can only push
  a task later, never earlier. `DataController.planCascade` computes the merged result once
  for both the preview and the commit, so they cannot diverge. Each
  `CascadeResult.TaskDateChange` carries a `reason` (`.crew` / `.dependency`) driving the
  "Same crew" vs "Dependent tasks" groups in `CascadePreviewSheet`. Trigger is the explicit
  Cascade actions only — plain push, swipe, and month-grid push stay single-task. Cross-project
  dependents of a crew-shifted job are **not** recursively cascaded (v1 boundary).
- **Undo** (`DataController.undoCascade`): restores every task in the merged result from the
  company-wide set (any status) using the pre-push dates captured in the change records.

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

**Selection versus historical resolution (iOS, 2026-07-24)**: Soft-deleted
`TaskType` rows remain in the local SwiftData cache so inbound sync can retain
tombstones and existing tasks can still resolve their original label and color.
They are not valid new choices. Every task-type picker, filter, suggestion, and
reassignment list must use `TaskTypeSelectionPolicy` (or the
`DataController.getSelectableTaskTypes(for:)` wrapper), which requires
`deletedAt == nil` and the active company id while preserving the caller's
ordering. Any stored filter selection is intersected with that selectable set
when options load, preventing a deleted type from remaining as an invisible
active filter.

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

**Web client aggregates (OPS-Web, 2026-06-13):** The rebuilt web Clients surface (WEB OVERHAUL P3.3, see `02_USER_EXPERIENCE_AND_WORKFLOWS.md` § "OPS-Web Clients") derives per-client money + activity entirely client-side from existing query caches — no new tables, columns, or RPCs. `OPS-Web/src/lib/hooks/use-client-financials.ts`: `useClientOutstandingMap()` (list OUTSTANDING column + A/R banner), `useClientFinancials(clientId)` (MONEY tab), `useClientActivity(clientId)` (composed timeline). **Data gotcha:** invoices link to a client via `invoices.client_id` (uuid, NOT NULL in prod), NOT `invoices.client_ref` (the FK'd column is 100% NULL in live data). Outstanding excludes statuses `paid`/`void`/`draft`/`written_off`; "oldest" in the A/R banner means oldest *overdue* (due_date < now). All reads are RLS-scoped (`clients`/`invoices` `company_isolation` + `role_scope_read`), so a scoped-out client returns zero rows and the web window shows a not-found state.

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

**Supabase-only column (not on the iOS model):** `sub_clients.qb_id text` (nullable), added in migration `20260603100000_qbo_company_subclient_mapping.sql` with a partial unique index `sub_clients_company_qb_id_uniq ON (company_id, qb_id) WHERE qb_id IS NOT NULL`. It links a sub-client to the QuickBooks Customer it was imported from, so the read-only QB sync can upsert one canonical contact per `(company, QB customer)`. Additive/nullable → iOS-sync-safe (the SwiftData model above does not map it and ignores it). A QB customer with a `CompanyName` imports as a parent `clients` row + this `sub_clients` contact; see `04_API_AND_INTEGRATION.md § QuickBooks Read-Only Sync`.

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

**Onboarding completion contract (June 2, 2026):** `hasCompletedAppOnboarding` mirrors server-backed platform completion and must be evaluated together with `companyId` and `userType`. A cached `companyId` by itself is not completion proof. OPS iOS completion is acknowledged through `POST /api/onboarding/complete`, which merges `users.onboarding_completed.ios=true`; OPS-Web owner setup uses `POST /api/setup/complete` to merge `users.onboarding_completed.web=true`.

> **iOS onboarding rebuild (2026-06-13 cutover):** the iOS onboarding flow was rebuilt into a single express flow. The completion ACK now tolerates poor connectivity — `OnboardingManager.markOnboardingCompleteOrQueue` ACKs `/api/onboarding/complete` when reachable, otherwise persists `onboarding_completion_pending=true`, admits the user, and lets the SyncEngine (`retryPendingOnboardingCompletion`) drain the queued ACK; `hasCompletedAppOnboarding`/`shouldShowOnboarding` treat a queued completion as complete. Owner creation moved to the shared `create_company_for_owner` RPC and crew joins to the amended `join_user_to_company` RPC (both in `04_API_AND_INTEGRATION.md`). The tutorial-completion write was corrected to the real column **`has_completed_tutorial`** (the old code wrote a non-existent `has_completed_app_tutorial`). Persistent flow state lives in `onboarding_state_v4` (UserDefaults). See `02_USER_EXPERIENCE_AND_WORKFLOWS.md` § *iOS Onboarding — The Rebuilt Express Flow*.

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
    //   Email-generated opportunities use OPS-Web/src/lib/email/opportunity-title.ts.
    //   Email subjects and AI summaries are context only; they must never become title.
    //   Defense-in-depth trigger trg_opportunities_default_title (BEFORE INSERT) auto-fills
    //   title from contact_name when null/empty, falling back to "New Lead".
}
```

**Computed**: `weightedValue`, `daysInStage`, `isStale`.

**Title invariant**: `opportunities.title` is `TEXT NOT NULL`. Every insert path must supply it. A `BEFORE INSERT` trigger (`trg_opportunities_default_title` — migration `add_opportunities_title_default_trigger`) populates it from `contact_name` if a client forgets, so the column constraint never fails an otherwise valid insert. Clients should still send an explicit title to match the human-readable convention used across the product (`"{contactName} - Lead"` for manual creation).

**Priority invariant**: live Supabase project `ijeekuhbatykdomumfjx` enforces `opportunities.priority IN ('low', 'medium', 'high')`. iOS client-created lead autocreation must send `medium` as the default priority; `normal` is invalid and will fail the insert.

**Images contract (2026-07-25; public lead-media repair deployed)**: `opportunities.images text[]` stores **full public S3 URLs**, never storage keys. Three producers: the OPS-Web email-extract pipeline (`src/app/api/integrations/email/extract-images/route.ts`, server-side puts under `email-imports/{companyId}/{opportunityId}/…`, capped 10/lead), iOS lead photos (`OPS/Services/LeadImageService.swift`), and the OPS-Web pipeline detail PHOTOS tab (`pipeline-detail-photos-tab.tsx` → `lead-photo-upload.ts` → `/api/uploads/presign` multipart direct-upload mode, gated on `pipeline.manage`). iOS and web lead-photo uploads now share the public project-media namespace `projects/{companyId}/leads/{opportunityId}/…` (`ops-ios` commit `d763e9df`; `ops-web` commit `bba70ea9`). The prior `opportunities/{companyId}/{opportunityId}/…` namespace was outside the bucket's public-read policy: writes and conversion succeeded, but every resulting lead/project URL returned `403`. Both iOS's immediate upload and restart-surviving queue drain derive the folder through the same `LeadImageStoragePath`; web derives it through `leadMediaFolder`, preventing path drift between producers.

**iOS optimistic photo contract (2026-07-25):** choosing lead photos synchronously reserves their strip positions before decoding begins. The picker payloads decode concurrently, successful siblings retain their selection order when one payload fails, and every viable image is written through `ImageFileManager` plus `pendingLeadImageUploads` before network upload starts. Each staged item carries a stable `displayID` and `batchIndex`, so the reserved tile becomes its local thumbnail without moving. Queue drains reconcile against their starting snapshot instead of replacing current state, preserving photos appended while a network request is in flight. The locally staged thumbnails therefore survive navigation, offline operation, relaunch, and background retry until the remote URLs are confirmed.

The web uploader deliberately does NOT use browser-direct presigned PUTs: `ops-app-files-prod` has no CORS configuration for browser origins, so a cross-origin PUT dies in preflight (verified against the live bucket 2026-07-14; iOS native URLSession and server-side producers never needed CORS). If bucket CORS is ever added, only `uploadOne` in `lead-photo-upload.ts` changes. All writers use the same server-state read-modify-write (iOS `OpportunityRepository.appendImages`/`removeImage`, web `OpportunityService.appendImages`/`removeImage` over pure `mergeImageUrls`/`removeImageUrl` in `src/lib/utils/opportunity-images.ts`: fetch → merge → update) so concurrent producers never clobber each other. On the web, `images` is deliberately excluded from `mapOpportunityToDb` and `CreateOpportunity`; the array is writable only through the RMW methods. iOS offline adds ride a durable local queue (bytes via ImageFileManager, records in UserDefaults, drained on connectivity/retry/appear). At conversion the full URLs copy into `project_photos` (`source='other'`, deduped by URL — see `09_FINANCIAL_SYSTEM.md` § Conversion transaction).

Photo deletion is an array PATCH on every surface; object deletion remains best-effort through `/api/uploads/delete`. The deployed route authenticates the OPS user, normalizes supported S3/Supabase object references, and authorizes recognized namespaces against the underlying resource. Both `opportunities/{companyId}/{opportunityId}/…` (legacy) and `projects/{companyId}/leads/{opportunityId}/…` resolve through the canonical opportunity edit boundary before the generic project namespace. Deterministic receipts require the exact authenticated company/user path; legacy receipts resolve the referenced expense; profile/logo objects resolve the owning user/company; and ordinary project photos resolve the referenced project plus canonical edit/admin authority. Unknown, malformed, or unresolvable namespaces are denied; there is no generic same-company delete fallback.

**Production recovery (2026-07-25):** all 25 legacy lead-photo objects across two opportunities were copied server-side into the public namespace and anonymously verified (`200`, image content type) before any reference changed. The guarded database rewrite preserved array order and replaced the matching URLs in `opportunities.images` and seven carried-over `project_photos.url` rows. Post-write verification found zero legacy references in `opportunities.images`, every `project_photos` URL column, and `projects.project_images`; all 25 URLs returned by the database passed a second anonymous read check. The old S3 objects were retained as a non-destructive recovery fallback.

The lead form's SITE ADDRESS uses the shared `AddressAutocompleteField`; a selection (or use-my-location) writes `latitude`/`longitude`, and any manual re-edit of the address text nulls them — coordinates never outlive the string they were resolved for.

**Deterministic expense receipt retry keys (2026-07-19):** `/api/uploads/presign` accepts `purpose=expense_receipt` only with JPEG content, validated expense/upload UUIDs, and `full|thumbnail`. It ignores the client folder/filename and derives `expenses/{companyId}/{userId}/{expenseId}/{uploadId}-{variant}.jpg` from the authenticated OPS user. Identical tuples therefore return the same S3 key (or a Supabase signed-upload token with `upsert`) while different users, variants, and upload attempts cannot collide. All legacy upload requests retain random server-generated names. The prepared `/api/uploads/delete` hardening cleans up a deterministic receipt only when its company/user path matches the authenticated user; every other supported layout passes through the resource-specific, default-deny authorization contract above. Neither web route change is deployed until OPS-Web `main` is explicitly pushed.

**Client-alongside-lead (bug 1d5ab9aa, fixed on iOS 2026-07-14, web parity 2026-07-14)**: a manually saved lead match-or-creates its `clients` row before the opportunity insert and passes `client_id` into the create, matching the web email/lead-engine paths (`ClientService.createClient → createOpportunity(clientId)`). Both platforms share identical matcher semantics — phone digits-suffix ≥7 → email case-insensitive exact → trimmed-name exact, soft-deleted rows never match (client merges stamp `deleted_at` on the losing row, so merged clients are excluded by the same filter) — iOS in `OPS/Services/LeadClientMatcher.swift`, web in `ops-web src/lib/utils/lead-client-matcher.ts` (wired into the create-lead modal's submit; a geocoded address pin rides onto the created client on both platforms). Client resolution failure never blocks the lead (falls back to an unlinked lead, logged only). The web modal's `resolveLeadClientId` fetches a fresh company client list at submit and falls back to the render-time cache when that fetch fails. Same-session web fix: an untouched ESTIMATED VALUE field used to fail the modal's zod validation silently (RHF submits `""` for a never-focused number input; the field renders no error), dead-ending every submit until some interaction blurred the field — `""` is now the schema's cleared-state sentinel, normalized to null on submit (ops-web commits `6d88e22f` + `f4e85e75`, on local main, not pushed).

**Client-created lead invariant (iOS reliability fix 2026-07-17)**: the client save and selection are authoritative; the matching pipeline lead is a durable secondary delivery owned by `ClientLeadAutocreateQueue`. Every manual client create and phone-contact import persists one pending request per lowercase client id, returns/selects the exact context-managed saved client immediately, then retries delivery on launch, authentication, foreground, connectivity recovery, and a 60-second timer. A delivery first confirms the local-first client is readable from Supabase, then reuses an existing active opportunity linked by `client_id` or the deterministic `source_thread_key = 'client-autocreate:' || lower(client_id)`. Every insert carries that key; the existing live `UNIQUE (company_id, source_thread_key)` constraint prevents duplicate automatic leads under concurrent retries or an ambiguous timeout, with keyed readback reconciling a commit whose response was lost. Only confirmed delivery removes the queue item, and every confirmation publishes `opsLeadsDidChange`. Logout/login/company changes invalidate the in-flight scope generation; an old-company result is never inserted into the new session's SwiftData context or cleared there. The matching lead uses the live-schema-safe `source = 'other'`, customer-derived title/contact, saved client id, and default priority `medium`. Secondary opportunity failure never becomes a false client `SAVE FAILED`; missing contact name or failure to persist the client remains blocking. This uses an existing database constraint and requires no migration.

**Email contact-name and title invariant (updated 2026-07-30)**: Email-created opportunities must build customer identity from explicit evidence, never from `subject`, AI summaries, platform sender names, company/operator identities, company email addresses, or a fabricated email local-part. OPS-Web centralizes mailbox-header qualification and title generation in `src/lib/email/opportunity-title.ts`, then applies the same boundary through conversation contact resolution, canonical enrichment, live sync, import, and historical recovery. Operator-confirmed/import-approved names and parsed contact-form names are authoritative. An exact linked client name may promote the opportunity only when the client, opportunity, and current correspondence share the same normalized email identity. A same-sender full name extracted after an explicit authored sign-off is stronger evidence than both that linked-directory name and a mailbox header. A person-shaped header display name is provisional only; lowercase handles, exact local-parts, mixed-case usernames, digit-bearing aliases, and bare addresses are not canonical names.

Sent-folder safety-net leads evaluate the external recipient and never the operator sender. Imported estimate leads use `"{customerName} — Estimate"` and inbound email leads use `"{customerName} — Email Inquiry"` only when the chosen name passes the applicable authority boundary; otherwise the title is `New Lead — Estimate` or `New Lead — Email Inquiry`. `lead_field_provenance.field_name = 'title'` records the generated-title snapshot and the same evidence strength as its contact name. When stronger same-email evidence promotes `contact_name`, OPS may update only an OPS-generated title whose provenance snapshot still matches; legacy rows without title provenance are eligible only when the title prefix still matches the stored contact/local-part identity or the `New Lead` placeholder. Arbitrary titles, operator-owned titles, and titles changed after their snapshot fail closed and remain untouched. Email subjects remain on activities/thread context, and generated summaries stay in `description`/`ai_summary`.

---

### 13. Activity (Supabase-Backed)

**File**: `DataModels/Supabase/Activity.swift`
**Purpose**: Timeline event parented to EXACTLY ONE of a lead (opportunity), a client, or a job (project).

**Properties**:

```swift
@Model
class Activity: Identifiable {
    @Attribute(.unique) var id: String
    var opportunityId: String?      // lead parent (uuid, FK opportunities); nil for a client/job-scoped row
    var clientId: String?           // client parent (uuid, NO FK); unified-activity widening (OPSSchemaV14)
    var projectId: String?          // job parent (Supabase TEXT, NO FK); unified-activity widening (OPSSchemaV14)
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
    // call_source     TEXT                         — around-call provenance from iOS (post_call_prompt | fab | app_shortcut); nullable (feature 154cb8a3)
    // caller_number   TEXT                         — normalized digits of the call's number, for dedup; nullable
    // call_started_at TIMESTAMPTZ                  — best-effort call start captured around-call by iOS; nullable
    // site_visit_id   UUID FK site_visits          — parent for a completed-site-visit activity; nullable. Legacy iOS completion wrote it through CreateActivityDTO but did not decode it, so a completed visit reached the lead timeline as an unremarkable row. SwiftData **V22** (2026-07-30) added the decode that lets the row render the SITE VISIT RECORD; durable site-visit sync now writes the link only through complete_site_visit_guarded. Chain context: two schema lines were developed in parallel and linearized on 2026-07-30 — **V20** = site-visit cloud sync (SiteVisit server projection + sync bookkeeping; the canonical V20, fingerprint-pinned), **V21** = Activity email identity (`email_message_id`, `email_thread_id`, `from_email`, `to_emails`, `cc_emails`), **V22** = this `site_visit_id` decode. Hard rule learned during that linearization: a NON-OPTIONAL array attribute on a SwiftData model MUST carry a default (`= []`) or lightweight migration refuses to open any store holding rows of that model — empty-store migration proofs cannot catch this, so migration tests must run against populated stores. Defaults are excluded from the schema fingerprint, so adding one is always safe. **V23** (2026-08-17) = the site-visit booking fields (`bookedAt`, `reminderLeadMinutes`, both nullable, server-owned). Incident record: the booking build originally widened the LIVE `SiteVisit` in place (ops-ios `417a7ed5`), silently shifting the V20–V22 fingerprints, and the first post-merge device install died at launch with CoreData 134504 ("unknown model version") — the store was preserved by design and no data was lost. Repair (ops-ios main, same day): freeze the pre-booking shape as `OPSSchemaLegacySiteVisitV22` backing V20–V22, scope the widened live model to `OPSSchemaV23` with an adjacent lightweight stage, extend the committed fingerprint fixture (`OPSTests/Fixtures/swiftdata-released-schema-fingerprints.json` — the apply-day run proved V1–V22 byte-identical to their committed values). Detection gap that let it merge: `AppUpdateMigrationTests.testDeclaredSchemaChecksumsStayImmutable` is exactly the guard for this, but only targeted test classes were run after the model edit — any change to a live `@Model` MUST run that class before commit.

    // Project Workspace Modal column (Supabase only — added 2026-05-06)
    // attachment_ids  UUID[] DEFAULT ARRAY[]::UUID[] — references to project_photos.id for activity entries with photo attachments.
    //   Distinct from the legacy `attachments` text[] column (free-form URLs/keys). The workspace timeline reads attachment_ids
    //   to resolve thumbnails + URLs reliably without parsing free-form strings. GIN partial index idx_activities_attachments
    //   WHERE array_length(attachment_ids, 1) > 0 covers the populated case.
}
```

**Subject invariant**: `activities.subject` is `TEXT NOT NULL` with no default. Trigger `trg_activities_default_subject` (migration `add_activities_subject_default_trigger`, BEFORE INSERT) auto-fills it as a defense-in-depth measure: first non-empty line of `content` (truncated to 100 chars), else a type-derived label (`Call`, `Note`, `Site visit`, etc.), else `Activity`. Clients should send an explicit `subject` for best UX — iOS Log Activity flow derives `"{first line of notes}"` or `"Call with {contactName}"` style from form state.

**Parent invariant (unified-activity widening, OPSSchemaV14)**: every activity has EXACTLY ONE parent — `opportunity_id` (lead, FK), `client_id` (client, no FK), or `project_id` (job, Supabase `TEXT`, no FK). The iOS write path is `ActivityRepository.logActivity(target: ActivityTarget, …)`, where `ActivityTarget` (`.opportunity | .client | .project | .unbound`) makes the single-parent rule unrepresentable-otherwise and drives which column `CreateActivityDTO` sets (the nil parents are omitted from the encoded JSON so PostgREST never receives `opportunity_id: null`). `company_id` (NOT NULL, RLS gate) and `created_by` (Supabase `users.id`, never the Firebase UID) are always stamped. The three legacy iOS loggers (Log Activity / Log a Call / lead-detail LOG) are consolidated into one `UnifiedLogActivitySheet` + `UnifiedLogActivityViewModel` that routes every write through this single path — correspondence types only (`call/email/meeting/note`), with direction/outcome/duration gated per type. Today only the lead timeline renders activities; client- and job-scoped rows persist for the deferred client/job timeline surfaces.

**iOS payload (CreateActivityDTO)** sends: the single parent (`opportunity_id` | `client_id` | `project_id`), `company_id`, `type`, `subject`, `content`, `direction` (call/email only), `outcome` (when non-empty), `duration_minutes` (call/meeting only and >0), `call_source`/`caller_number`/`call_started_at` (call only), legacy `site_visit_id`, and `created_by`. Other columns rely on Postgres defaults (`is_read`, `match_needs_review`, `has_attachments`, `attachment_count`, `sent_by_agent`, `created_at`). New site-visit completion does not send this DTO separately; the guarded server transaction owns the activity.

**Site-visit → timeline completion (guarded server transaction; production-live 2026-08-02).** The durable sync release replaces the former best-effort app-side activity insert. iOS and web call the SECURITY INVOKER Data API wrapper `public.complete_site_visit_guarded(site_visit_id, completion)`, which delegates to the pinned, non-exposed `private.complete_site_visit_guarded` implementation. That implementation locks and authorizes the parent, refreshes the normalized-child compatibility projection, advances the visit monotonically to `completed`, and inserts or updates exactly one `type='site_visit'` activity under the partial unique index on `activities.site_visit_id`. The RPC also stamps `site_visits.activity_id`; retrying after a lost response returns the same completed visit/activity rather than creating a duplicate. Dedicated indexes cover `site_visits.activity_id` and `project_photos.site_visit_id` for completion and handoff FK traversal. Sources: `migrations/20260731235533_site_visit_cloud_sync.sql`, `migrations/20260802093608_site_visit_completion_rpc_security_boundary.sql`, and `migrations/20260802102853_site_visit_fk_indexes.sql`; callers: `ops-ios/OPS/Network/Supabase/Repositories/SiteVisitRepository.swift` and `ops-web/src/lib/api/services/site-visit-service.ts`. The database contract is live; iOS customer distribution remains a separate release gate.

**Around-call provenance (feature 154cb8a3, migration `add_call_provenance_to_activities`).** Three nullable, additive columns — `call_source`, `caller_number`, `call_started_at` — let iOS record where a `call` activity came from when captured via the around-call lead-capture flow. `call_source` ∈ `post_call_prompt | fab | app_shortcut`; `caller_number` is the normalized digit form of the dialed/received number (NANP country code stripped); `call_started_at` is the best-effort call start. NO check constraints / NO defaults / NO NOT NULL — the additive-only rule keeps iOS↔Supabase sync intact across App Store releases. Web and older rows carry nil. See `10_JOB_LIFECYCLE_AND_DATA_RELATIONSHIPS.md` § Around-call lead capture.

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

#### Authoring surface (Web + iOS)

The configurable layer is authorable on OPS-Web and, as of iOS Catalog Setup Phase 5 Task 10, from iOS Product detail through `ProductOptionAuthoringSheet`. Catalog Setup `LINKS` presents that same iOS sheet for the selected Product so newly authored select options and values can be mapped without creating a divergent setup-only editor.

- **Route**: `/products/[id]/options` (deep-link from the product list and product edit modal)
- **Permission**: `products.manage`
- **Sections**:
  - **Options** — list of `product_options` rows with drag-reorder (`sort_order`), inline edit, hard delete with confirmation. Modal handles create/edit including the `kind`/`affectsPrice`/`affectsRecipe`/`required`/`defaultValue`/`optionDefaultSource` fields. For `kind = select`, the modal also exposes the nested `product_option_values` editor (add / rename / drag-reorder / delete).
  - **Pricing modifiers** — list of `product_pricing_modifiers` rendered as humanized rules (e.g. "When Color = Red → +$5.00 per unit"). Modal handles create/edit with an option picker, kind-aware trigger (value picker, integer min/max range, or implicit-when-true for boolean), modifier-kind segmented control, and amount input with live preview.
- **iOS surface**: `OPS/Views/Catalog/Products/ProductOptionAuthoringSheet.swift` is reused by `ProductDetailView` and `CatalogSetupFlowSheet` `LINKS`. It writes narrowly through `ProductRichnessRepository` against existing `product_options`, `product_option_values`, and `product_pricing_modifiers` tables only. It enforces that select values and modifier trigger values belong to the selected Product option before saving, and local cascades keep option values, pricing modifiers, and catalog/product mappings from pointing at removed option rows.
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
  relationship_kind   text    NOT NULL DEFAULT 'required'
    CHECK (relationship_kind IN ('required', 'suggested')),
  suggestion_reason   text NULL,
  compatibility_selector jsonb NULL,
  display_order       int     NOT NULL DEFAULT 0,
  created_at          timestamptz NOT NULL DEFAULT now(),
  updated_at          timestamptz NOT NULL DEFAULT now(),
  deleted_at          timestamptz NULL,
  CONSTRAINT no_self_reference CHECK (bundle_product_id <> child_product_id)
);
```

Indexes on `bundle_product_id`, `child_product_id`, `company_id`, and `(company_id, bundle_product_id, relationship_kind, display_order)` (all partial `WHERE deleted_at IS NULL`). RLS: single `company_isolation` policy matching the existing pattern on `products` / `product_materials` — `company_id = (SELECT private.get_user_company_id())`. Permission gating (`catalog.products.manage`) lives in iOS/web permission_store before mutation, not in RLS.

`relationship_kind` separates always-included bundle children from suggested add-ons. `required` is the backward-compatible default for existing rows and old clients. Required rows participate in bundle rollup price and future materialization. Suggested rows render separately as add-ons and do not change bundle price unless the operator explicitly chooses them downstream. `suggestion_reason` is operator-facing rationale for optional rows. `compatibility_selector` is reserved JSONB for future product-option compatibility filters; current iOS sync preserves it without interpreting it after the target schema capability probe confirms the columns exist.

**Pricing mode — `products.bundle_pricing_mode`**:

Nullable text column on `products`, CHECK `bundle_pricing_mode IS NULL OR bundle_pricing_mode IN ('auto', 'override')`. NULL for non-bundles.

- `auto` — bundle's `base_price` is rewritten on save as `Σ(child.base_price × quantity)`. The UI shows the rolled total read-only.
- `override` — bundle's `base_price` is whatever the user typed; the rolled sum and a live margin percent ((override − rolled) / override × 100) are shown alongside for awareness but don't overwrite.

**Constraints**:
- `no_self_reference` CHECK: a bundle cannot include itself as a child.
- **Bundle nesting (bundles whose children include another bundle) is disallowed for v1 in the iOS UI** — the child picker drawer filters out `kind='package'` products. Not enforced at the DB; defer to v2 if a real need emerges.

**iOS surfaces**:
- `ProductBundleItem` SwiftData @Model (`DataModels/Supabase/Catalog/ProductBundleItem.swift`) — V8 local cache with `relationshipKind`, `suggestionReason`, `compatibilitySelectorJSON`, `lastSyncedAt`, and `needsSync` per the standard sync pattern. V3-V7 schemas use a frozen legacy ProductBundleItem model so those fields do not rewrite historical schema fingerprints.
- `ProductBundleItemRepository` — fetch / create / update / soft-delete. Create/update writes omit relationship columns until `CatalogSchemaCapabilityGate` proves the target has them.
- `NewBundleSheet` — full create flow (V4 hybrid layout: inline child picker drawer + selected-children list with integer steppers + AUTO/OVERRIDE pricing segmented control).
- `BundleCompositionEditSheet` — diff-based edit of required bundle children. Suggested add-ons are displayed separately and preserved; they are not loaded into the required child editor or bundle rollup price.
- `BundleCompositionReadOnlyView` — embedded in `ProductDetailView` when `kind == .package`, replaces the recipe section, and separates required rows from suggested add-ons.
- `InboundProcessor.syncProductBundleItems` — pulls server rows, preserves pending local edits via `needsSync` guard, reconciles deletions scoped to the company's product space.
- `SyncEntityType.productBundleItem` — priority 13, alongside other product-richness tables.

**Old-iOS degradation**: pre-bundle App Store builds decode `kind='package'` via the existing `?? .service` fallback in `ProductDTO.toModel()` (line 81). They render bundles as regular service products — billable on estimates as a single line item, but the composition is invisible. `UpdateProductDTO` is sparse and the iOS detail view never exposes a `kind` picker, so old clients cannot clobber `kind='package'` on edit. Verified by reading the codebase at spec time; documented in `docs/superpowers/specs/2026-05-10-products-services-bundles-design.md`.

**Coupling (deferred — tracked as P1-22 follow-up)**:
- Estimate / Invoice bundle expansion on the line item (uses existing `show_bom_on_estimate` flag — web concern).
- `CutListMaterializer` recursive expansion when a task is linked to a bundle product.

**Reverse stock→product link (added 2026-05-10, same bugs)**: `VariantDetailView` (Stock segment) now shows a **USED IN** section listing every product whose recipe (`product_materials`) references this variant **or** whose `linked_catalog_item_id` points at the variant's family. Each row taps through to `ProductDetailView`. Closes the discoverability gap that previously left the stock→product relationship one-way.

---

### 22. SiteVisit cloud packet (database live 2026-08-02)

**File**: `DataModels/Supabase/SiteVisit.swift`
**Purpose**: Durable, cross-device scope assessment rooted in the existing Supabase `site_visits` parent.

**Release status:** the three normalized child tables, guarded completion boundary, Realtime publication changes, tenant-erasure manifest coverage, and production-generated web database types are live as of 2026-08-02. The public completion RPC is invoker-safe; privileged work is isolated in the private schema behind complete tenant authorization. The iOS implementation is committed and simulator-verified but is not customer-distributed until the signed physical-device/App Store release gate completes.

**Parent contract (`public.site_visits`, existing live table):** `id uuid`; `company_id text`; `opportunity_id uuid?`; legacy `project_id text?` plus canonical `project_ref uuid?`; legacy `client_id text?` plus canonical `client_ref uuid?`; `status site_visit_status` (`scheduled | in_progress | completed | cancelled`); `scheduled_at timestamptz`; `duration_minutes integer`; `assignee_ids text[]?`; completion/notes/measurements/photos/activity/calendar fields; `created_by text`; audit timestamps; `deleted_at timestamptz?`. The iOS `SiteVisit` SwiftData model now round-trips this row through `SiteVisitDTOs.swift`, `SiteVisitRepository.swift`, outbound operations, delta pull, and Realtime.

`ops-ios/OPS/Views/SiteVisits/SiteVisitCaptureView.swift` opens from lead detail, New Lead, or the FAB and creates/reuses an active visit before a project exists. `opportunityId` remains optional so capture is never blocked by client/lead administration. Every local mutation and its `SyncOperation` are committed in one SwiftData transaction by `SiteVisitPersistenceCoordinator`; the queue is a phone-local transport mechanism, not company data. Ordering is parent → child rows → media → `complete_site_visit_guarded`, expressed with durable `dependsOnId` links so a restart cannot complete a visit before its packet exists.

Inbound delta and Realtime subscribe to the parent plus all three children. `SiteVisitServerMerge` preserves dirty local fields, applies authoritative terminal status, and makes an in-progress visit resumable from a second authorized device. `SiteVisitOrphanRecovery` reconstructs a missing legacy parent only from exact same-company, valid, non-conflicting evidence; foreign, malformed, or ambiguous groups are encrypted and quarantined instead of uploaded or deleted.

### 22A. SiteVisitIdentityDraft (cloud-backed snapshot)

**File**: `ops-ios/OPS/DataModels/SiteVisits/SiteVisitIdentityDraft.swift`
**Purpose**: Locally autosaved and durably synced client/lead identity packet for an active visit.

`public.site_visit_identity_drafts` is one active row per visit (`site_visit_id uuid` FK `site_visits.id ON DELETE CASCADE`, partial unique active index). It stores `company_id text`, optional UUID opportunity/client/sub-client links, client/contact/email/phone/address/notes fields, `additional_emails text[]`, `created_by text`, `last_committed_at`, timestamps, and `deleted_at`. The parent guard rejects company or opportunity drift. The draft autosaves locally while the operator types, then syncs through the same parent-first outbox. Project creation remains gated on a linked opportunity; field capture does not.

### 22B. SiteVisitCaptureArtifact (cloud-backed evidence)

**File**: `ops-ios/OPS/DataModels/SiteVisits/SiteVisitCaptureArtifact.swift`
**Purpose**: Pre-project evidence packet that survives app termination, logout recovery, and device changes.

**Properties**:

```swift
@Model
final class SiteVisitCaptureArtifact: Identifiable {
    @Attribute(.unique) var id: String
    var siteVisitId: String
    var companyId: String
    var opportunityId: String?
    var kind: SiteVisitCaptureArtifactKind   // photo, annotatedPhoto, dimensionedPhoto, note, transcript, measurement, deckDesign
    var source: SiteVisitCaptureSource       // camera, gallery, microphone, keyboard, laser, lidar, deckBuilder, manual

    var title: String?
    var body: String?
    var localAssetURL: String?
    var renderedAssetURL: String?
    var thumbnailURL: String?
    var dimensionsJSON: String?
    var deckDesignId: String?

    var includedInProjectReview: Bool
    var capturedAt: Date
    var createdBy: String?
    var createdAt: Date
    var updatedAt: Date?
    var deletedAt: Date?
    var needsSync: Bool
    var lastSyncedAt: Date?
}
```

Prepared table `public.site_visit_artifacts`: `id uuid`; `site_visit_id uuid` FK parent with cascade; `company_id text`; `opportunity_id uuid?`; enumerated `kind` and `source`; title/body; original/rendered/thumbnail URLs; `dimensions jsonb`; `deck_design_id uuid?`; review flag; capture/creation/update/delete timestamps; `created_by text`. Active indexes cover company/visit and opportunity, and the parent guard enforces exact company and opportunity identity.

**Media contract.** `SiteVisitMediaSyncManager` requests a presign only after the parent is server-visible. `POST /api/uploads/presign` accepts `targetType=site_visit`, canonical visit/artifact ids, `variant=original|rendered|thumbnail`, an approved image MIME type, and a bounded size. The server re-authorizes the active parent under the caller's company and derives the object key; the phone cannot choose a folder. Key shape: `site-visits/{company_uuid}/{site_visit_uuid}/{artifact_uuid}/{variant}.{ext}`. The artifact row receives the remote URL only after upload succeeds. Account deletion separately erases the exact `site-visits/{company_uuid}/` prefix without adding a server receipt/outbox table.

**Unrecoverable media (2026-08-05).** A capture's local file is the only copy until it uploads, and it lives in the app container (`Documents/ProjectImages/`) while the SwiftData store lives in the app-group container. Deleting and reinstalling the app therefore erases the bytes while the artifact rows survive, leaving `local://project_images/…` pointers that can never resolve. `SiteVisitMediaSyncManager` distinguishes two failures: `localFileMissing` (the file is absent — terminal) and `localFileUnreadable` (the file exists but this read failed, e.g. Data Protection during a locked-device background drain — transient, classified `.transient` by `SyncErrorClassifier` and retried). An absent variant has its pointer cleared rather than throwing, so the row converges on the null asset URL the server and every other device already hold, the media operation completes, and `needsMediaUpload` stops re-queueing it; the visit, notes, checklist answers and deck designs are untouched. `SiteVisitParkedMediaReconciler` (invoked from `SyncEngine.pushPending`) settles already-parked media operations the same way by re-reading the filesystem — clearing genuinely dead pointers and returning to `pending` any whose file is present. Verified precedent: 32 photo artifacts across 5 site visits (2026-06-29 → 2026-07-15) were orphaned by a 2026-07-17 reinstall; the bytes exist nowhere (device, server `asset_url IS NULL`, recovery vault, camera roll — in-app capture never writes to the photo library).

Project handoff is local-first **and durably synced**:

- **Photos.** If the artifact already has a remote visit URL, `SiteVisitProjectHandoff` reuses that object and creates one lowercased `ProjectPhoto(source: "site_visit", siteVisitId: visit.id)`; it never copies the bytes. If the artifact remains local, the existing restart-surviving image/dimension pipeline uploads it once and heals the local row in place. The partial unique index `(company_id, project_id, site_visit_id, url) WHERE deleted_at IS NULL AND site_visit_id IS NOT NULL` makes conversion retry idempotent across devices.
- **Dimensioned photos.** Original/rendered variants already stored for the visit are reused while `PhotoAnnotation`/`DimensionsData` provenance is preserved. A local-only dimensioned photo remains owned by the annotation pipeline so it cannot double-upload through the generic image queue.
- **Deck link.** Reviewed deck-design artifacts set `DeckDesign.projectId` **and record a durable `deckDesign` update SyncOperation** `{project_id, updated_at}` (bare `markForSync()` was a flag no sweep ever drained). The deck-builder UPDATE payload now carries `project_id` whenever the local design has one — omitted when nil, so a device holding a stale-nil copy can never unlink an attachment made elsewhere. `SyncEngine.enqueueStrandedDeckDesignLinks()` runs in every `pushPending` and re-records the link op for decks stranded by the pre-fix handoff (`needsSync`, linked, no op, no recent op lifecycle).
- **Staging-store loss.** The in-memory `SiteVisitProjectHandoffStore` is now a fast path only: when it is empty at conversion (app killed between review and convert), `SiteVisitProjectHandoff.derivePayload` rebuilds the payload from persisted `SiteVisit` / `SiteVisitCaptureArtifact` / `SiteVisitChecklistAnswer` rows by opportunity id, with two-way visit discovery (visit rows bound to the opportunity, plus visits whose artifacts carry the binding — covering pre-bind captures and unlink-drifted visit rows).

Deck design capture is gated by the `deck_builder` feature and create/edit permissions; it is not a general site-visit feature.

### 22C. SiteVisitType + SiteVisitChecklistAnswer

**File**: `ops-ios/OPS/DataModels/SiteVisits/SiteVisitType.swift`
**Purpose**: Company-scoped visit templates and per-visit checklist answer snapshots layered on top of the base capture packet.

`SiteVisitType` is the phone's local-first cache of the company-wide `public.site_visit_types` template: slug, display name, description, system/default flags, order, and encoded fields (`checkbox`, `yes_no_na`, `short_text`, `long_text`, `measurement`, `photo`, `photo_markup`, `deck_design`). Each field carries its own label, required flag, order, optional help text, and backward-compatible `isVisible` flag (missing means shown). Built-in ids are deterministic per company. Product metadata reconciliation may refresh a built-in label/kind/help value or add a newly shipped field, but it preserves the company's visibility, required, and ordering choices plus all company-added fields.

`public.site_visit_types` is the shared definition record: text `id` and `company_id`; active company-unique slug; at most one active default per company; bounded validated `fields jsonb`; timestamps; `deleted_at`; Realtime with full replica identity. All company members may read templates. Insert/update requires `settings.company`; normal app roles receive no hard-delete grant. iOS create/update/delete writes travel through the durable generic sync queue, and inbound/delta/Realtime use one dirty-field-preserving merge rule. Crew without company-settings authority can still use deterministic local starter types but never enqueue unauthorized template writes.

The durable visit record remains the per-visit field snapshot, not a live pointer. Selecting a type creates `SiteVisitChecklistAnswer` rows containing the label, kind, requirement, help, and order at that moment. Hidden template fields create no answer row. Editing a template can refresh a current completely blank checklist when Settings closes, but once any answer exists the visit stays immutable; later template edits never rewrite history.

**Release status (2026-08-06):** migration `20260806103000_site_visit_checklist_templates.sql` is production-applied as version `20260806211208`. Production readback confirms the table, validated field document, RLS policies, role grants, full replica identity, and Realtime publication membership. OPS-Web database types, live-derived company-data scope/privilege snapshots, export/account-closure manifest, and focused lifecycle tests were refreshed and deployed from commit `7e41c289`. Verified iOS source is on `main` at `fd6d6e7d` with all eight focused checklist/settings simulator tests passing. Signed device/App Store distribution remains a separate release gate; source publication alone is not customer-device proof.

`public.site_visit_checklist_answers` is the cloud record: `id uuid`; `site_visit_id uuid` FK parent with cascade; `company_id text`; `opportunity_id uuid?`; optional local template id; field id/label/kind/required/help/sort snapshot; bounded `answer_value jsonb`; `created_by text`; timestamps; `deleted_at`. One active answer exists per `(site_visit_id, field_id)`. Reassigning the parent propagates its opportunity binding to every child.

Capture UX is field-first: note draft text autosaves into one live note/transcript artifact as the operator types or finishes dictation, clearing the text soft-deletes that draft artifact, and there is no separate Save Note command. Photo artifacts expose `previewAssetURL` (`renderedAssetURL ?? thumbnailURL ?? localAssetURL`) so capture-packet rows can show thumbnails and open a zoomable preview before markup. Checklist fields can auto-link matching captured evidence: photo fields use active photo/dimensioned-photo artifacts, measurement fields use measurement artifact text, and deck-design fields use the active deck-design artifact. The lead/client panel is part of the same capture console, not a pre-step: inline search suggests local active leads and clients, manual fields autosave into `SiteVisitIdentityDraft`, completed fields get completion treatment, and the operator can create/link the lead from the same panel before project handoff. Reassigning a visit moves the open `SiteVisit` plus all active `SiteVisitCaptureArtifact.opportunityId` and `SiteVisitChecklistAnswer.opportunityId` values to another active lead before project creation.

### 22D. Recovery, tenancy, export, and erasure

- **Truthful save.** `SAVE VISIT` and the `// VISIT SAVED` toast mean the parent, children, media operations, and completion command are durably committed on the phone. Pending Work continues to show the visit as waiting/sending until the server acknowledges; the local toast is not a claim that Supabase has received it.
- **Logout.** Voluntary logout performs a bounded flush and warns if visit work remains. Forced/token-driven logout encrypts only unsent/quarantined visit bundles and their referenced media with AES-GCM under a dedicated ThisDeviceOnly Keychain key before the shared SwiftData store is wiped. Archives are exact `(user_id, company_id)` scoped; another account cannot list, restore, or discard them. Explicit discard and device-account deletion erase the matching vault data. This phone-local transport/recovery machinery is not part of the server company-data manifest.
- **Pending Work.** Quarantined packets render as protected, non-retryable entries. They can be exported or explicitly discarded; generic Retry/Retry All cannot send unsafe tenant evidence.
- **Server tenancy.** Child `company_id` is intentionally `text`, matching legacy `site_visits` and `project_photos`; related opportunity/client/deck ids remain UUID. RLS combines exact company isolation with parent view/edit authorization, while service role retains hard-delete for account closure. Never cast the entire legacy path to UUID by assumption.
- **Customer data lifecycle.** `site_visits`, `site_visit_artifacts`, `site_visit_checklist_answers`, `site_visit_identity_drafts`, and `site_visit_types` are company-scoped on `company_id text`, soft-deleted, exported, and registered in `src/lib/data/company-data-manifest.ts`; visit children remain ordered before their parent. `site_visit_types` is company-owned settings data and is included in the live-derived scope/privilege snapshots. `activities` remains company-scoped UUID + hard-delete; `project_photos` remains company-scoped text + soft-delete/export. The migration adds no receipt/event/outbox table. Storage erasure deletes the exact company visit prefix separately.
- **Physical verification requirement.** Simulator tests prove ordering, serialization, merge, logout, and idempotency. Signed iOS release still requires an authenticated physical-phone offline capture/force-quit/reconnect test, a second-device resume test, live readback proving one activity, export proof, and transactional company-purge rehearsal.

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

**Classic markup visibility contract (verified 2026-05-25):** `project_photo_annotations.photo_url` remains the source image URL and `annotation_url` remains the transparent PencilKit overlay PNG. iOS renders classic markup overlays in the fitted display-canvas coordinate space, not raw source-photo pixels, then composites by scaling the overlay over the source image. Project detail/photo viewers must handle a cold cache by downloading both the source photo and the overlay URL before writing the composited image into `ImageCache`; otherwise another device can see only the unmarked source image after sync.

**Collaborative markup — author-scoped layers (2026-06-23).** Markup is now per-author *layers* on the shared annotation row, fixing the bug where a second editor saw a blank canvas and overwrote the first author's marks. Four ADDITIVE nullable columns on `project_photo_annotations` (migration `collaborative_photo_markup_layers`):

- `layers jsonb` — array of `{ layerId, authorId, authorName, overlayUrl, strokeRef, visibleDefault, zIndex, strokeCount, createdAt, updatedAt, clearedAt }`. **Invariant: `layerId == authorId == users.id`** (one layer per author per photo). Each layer owns a transparent overlay PNG (`overlayUrl`) AND the editable `PKDrawing.dataRepresentation` stroke blob (`strokeRef`, an S3 object — never inlined base64). A layer is *active* while `clearedAt` is null.
- `change_log jsonb` — append-only `{ eventId, authorId, authorName, action(added|edited|cleared), strokeDelta, beforeSnapshotUrl, afterSnapshotUrl, at }`.
- `before_snapshot_url text`, `after_snapshot_url text` — most-recent event's baked before/after composites. **Forward-ready: null until the snapshot feature ships** (deferred 2026-06-24; retention cap = last 5 pairs/photo when it lands).

The editor composites every *other* author's overlay as a NON-editable base under the current user's PencilKit canvas; each user edits only their own layer. `annotation_url` (the legacy scalar) is kept synced to the newest *active* overlay so pre-update builds + the activity feed (`AnnotationFeedPolicy.hasMarkup`) stay honest. Inbound sync does a **per-layer recency union** (`MarkupLayerMerge`, shared by InboundProcessor/DataActor/RealtimeProcessor) so a peer's newer server layer AND this device's un-pushed local layer both survive a stale echo. The show/hide eye toggle (`hiddenAuthorIds`) is a LOCAL per-viewer preference — never synced. All layer writes go through the `upsert_markup_layer` SECURITY DEFINER RPC (see `04_API_AND_INTEGRATION.md` §14), never a wholesale `.update(layers).eq(id)` (last-writer-wins, drops peers' layers).

---

### 25. CalendarUserEvent (Supabase-Backed)

**File**: `DataModels/Supabase/CalendarUserEvent.swift`
**Purpose**: User-owned calendar events — personal/custom events and time-off rows. Time off can be submitted by the user as a pending request or booked directly as approved by a user with `time_off.approve`. Separate from project-linked schedule tasks.

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
    var status: String               // CalendarUserEventStatus.rawValue: "none" | "pending" | "approved" | "denied"
    var address: String?
    var teamMemberIds: [String]?     // Personal/custom event invitees
    var reviewedBy: String?          // User ID of admin who reviewed time-off request
    var reviewedAt: Date?
    var createdAt: Date
    var updatedAt: Date?
    var deletedAt: Date?
    var seriesId: String?            // Shared UUID for expanded recurring personal events

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
    case none = "none"             // Personal/custom event; no approval workflow
    case pending = "pending"       // Time off awaiting review
    case approved = "approved"
    case denied = "denied"
}
```

**Key Computed Properties**:
- `eventType: CalendarUserEventType` — typed accessor for `type` string
- `eventStatus: CalendarUserEventStatus` — typed accessor for `status` string
- `isTimeOff: Bool`, `isPersonal: Bool`, `isPending: Bool`
- `overlaps(date:) -> Bool` — used by calendar views to show events on relevant days

**Business Rules**:
- Personal/custom events: `status` is `.none`; optional `teamMemberIds` invite other members and make the row visible/mirror-eligible for them
- Time-off self requests: created as `.pending`; users with `time_off.approve` can approve (`.approved`) or deny (`.denied`)
- Approver-booked time off: users with `time_off.approve` can create company-member time-off rows directly as `.approved`; the insert stamps `reviewedBy` / `reviewedAt`
- Calendar visibility: own rows always appear; invited personal rows appear for invitees; `calendar.view(all)` can see company user events; `time_off.approve` users can see company time-off rows
- Soft-delete via `deletedAt` (consistent with all Supabase-backed models)

**Supabase Table**: `calendar_user_events`

**RLS Note**: The `calendar_user_events` table uses explicit UUID/text casts because `public.users.id` / `public.users.company_id` are UUID columns while `calendar_user_events.user_id` / `calendar_user_events.company_id` are text columns. Standard UUID-to-text comparisons fail without casts. Self-owned rows use the existing owner policy; migration `20260707194500_calendar_user_events_time_off_approver_policies.sql` adds insert/update policies for `time_off.approve` users to book or update active members' company time-off rows.

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

**iOS now reads both columns (2026-07-04, bug burndown I2).** `ProjectNote` gained optional `eventKind` + `contentMetadataJSON` (SwiftData schema **V13**, additive) and the DTO decodes `content_metadata` loosely (`AnyJSON` → raw JSON string). The iOS Activity feed branches on `eventKind`: `status_change` renders as a quiet one-line system row (`FROM → TO` from `{from,to}`), the iOS-authored `site_visit` kind renders as a rich packet card (see below), and any other / unknown `event_kind` falls back to the plain note card. So the "renders as a plain note" caveat above is resolved on iOS ≥ the I2 release.

**iOS writes `event_kind = 'site_visit'`.** The site-visit packet (lead → project conversion) is now one `project_notes` row: `content` keeps the legacy plain-text packet (web + older iOS render it unchanged) and `content_metadata` carries the structured summary the iOS feed card + detail sheet render from — `{ "site_visit_id", "photo_count", "measurements": [{ "label", "value" }], "notes": [...], "checklist": [...], "address", "contact_name", "company_name", "deck_design_id", "recorded_by_user_id" }` (all keys optional and additive, so older packets decode unchanged and a missing key simply renders no section).

The completed record attributes the visit to the capture author, not the teammate who later converts the lead: new packets carry `recorded_by_user_id`; legacy packets fall back to the linked `site_visits.created_by`, then the packet note's `author_id`. The same capture-author identity is written into generated `project_photos.uploaded_by`, photo annotations, and the project packet note. Photos in the sheet resolve from synced `project_photos` rows (`site_visit_id`, else `source = 'site_visit'`) using `rendered_url` before the raw `url` and passing `thumbnail_url` to the remote thumbnail loader. Lead-side local artifacts and project-side remote rows render through the same record sheet.

`deck_design_id` is an internal lookup key only. It is never printed in the record or checklist. A linked design renders one `OPEN DECK DESIGN` action that opens the exact design; if that design is absent locally, iOS performs the existing project/opportunity-scoped self-repair fetch before opening it.

**No currency value is ever written into this blob — this is a hard contract, not a preference.** `content_metadata` syncs, and OPS-Web renders it with no financial gate of its own, so any money-shaped key here is money published past iOS's `finances.view` permission to every viewer of the web activity feed. A first cut of the record shipped `estimated_value` in the packet and was reverted for exactly this reason (2026-07-29). The lead's value is instead resolved at RENDER time from the local `opportunities` row and gated there — permitted viewers with the lead on-device see a `// VALUE` line, everyone else's record simply lacks it. Reading it live also keeps the figure honest: a record opened a month later shows what the lead is worth now, not a number frozen into a note. `OPSTests/SiteVisitPacketNoteTests.testPacketMetadataCarriesNoMoney` enforces the key set as an allowlist, so a future `deck_price` or `quote_total` fails the build rather than leaking. The packet is written through the iOS durable sync queue (`DataController.createProjectNote` → outbound create carrying both columns); the previous direct insert set `needsSync` but recorded no op, and project notes have no `needsSync` sweep, so packets never reached the server.

**`event_kind` discriminator values** — `status_change`, `estimate_sent`, `estimate_approved`, `estimate_declined`, `invoice_sent`, `payment_received`, `expense_logged`, `photo_uploaded`, `project_created`, `project_archived`, `task_completed`, `site_visit` (iOS-written). `NULL` = user-authored note (default). The web `useProjectActivity` hook maps `NULL` to the `kind: 'note'` enum branch and uses non-null values to dispatch icon / color / dot styling on the timeline.

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
| `site_visit` (iOS) | `{ "site_visit_id": "<uuid>", "photo_count": 4, "measurements": [{ "label": "Deck width", "value": "14 ft 6 in" }], "notes": ["..."], "checklist": ["..."], "address": "...", "contact_name": "...", "company_name": "...", "deck_design_id": "<uuid>", "recorded_by_user_id": "<uuid>" }` — deck and recorder UUIDs are internal identity keys and never user-facing; **never any currency value**; see the packet contract above |

**Write paths** — `ProjectLifecycleService.onProjectStageChange` writes `status_change` rows with the `{from, to}` payload. The workspace `useProjectMutations` hook writes `project_created`, `project_archived`, and `photo_uploaded` rows. Estimate / invoice / payment / expense writes happen inside their respective services as those features are wired into the workspace timeline (later phases).

**Read path** — `useProjectActivity` selects `id, content, content_metadata, event_kind, created_at, attachments, mentioned_user_ids, author_id` from `project_notes` ordered by `created_at DESC`, hydrates authors via a follow-up `users` join, and maps each row to a `ProjectActivityEntry` with `kind = event_kind ?? 'note'`. The legacy `activities` table is no longer the primary read source for the workspace timeline.

### `project_note_mention_events` + atomic mention edits (Migration `20260724020000`)

Editing a human-authored project note replaces two authoritative values together: `project_notes.content` and the complete `project_notes.mentioned_user_ids` access list. iOS calls `public.update_project_note_mentions(note_id, content, mentioned_user_ids, event_id)` rather than issuing a direct partial update.

Cross-platform mention content uses canonical persisted tokens: `@[Display Name](<user_uuid>)` for a person and the reserved, exact `@[All Team](all-team)` token for the active-company group. The visible editor renders friendly `@Display Name` copy, but identity is carried separately and serialization restores the canonical token. A UUID embedded in note text is never authority by itself: it must agree with the note's stored mention list and the current active-company roster.

The security-definer RPC:

- locks the note so offline/retried edits serialize;
- requires the current active same-company user to be the note author;
- rejects deleted notes and system timeline rows (`event_kind IS NOT NULL`);
- canonicalizes and deduplicates requested UUIDs in first-seen order, excludes the actor, and rejects inactive or cross-company recipients;
- computes newly added recipients against the prior authoritative list;
- updates content and mentions atomically; and
- records an immutable event for every successful edit, including edits with no newly added recipients.

`project_note_mention_events` stores the raw request for exact replay comparison, before/after snapshots, the server-computed new-recipient delta, actor/project copy snapshots, and the committed note timestamp. Clients cannot read or write the table; only service-role notification resolution can select it. A trigger rejects event updates/deletes. Reusing an event UUID with the exact request returns the stored result without mutating a newer note state; reusing it with different input is rejected.

Mention-edit notification rows use the durable key `mention-edit:<event_uuid>`. The partial unique index on `(user_id, company_id, type, dedupe_key)` is intentionally independent of read/resolved state so a retry cannot create a second rail item.

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

### `projects.title_is_auto` + auto-naming trigger (Migration `20260603020000_won_conversion_dedup_naming`)

Makes `projects.title` a self-healing pointer to `projects.address`. The won→project conversion and the manual create form stop asking the operator to name a project — the name is derived from the site address and re-derives whenever the address (or client) changes, until the operator types their own name.

```sql
ALTER TABLE public.projects
  ADD COLUMN IF NOT EXISTS title_is_auto boolean NOT NULL DEFAULT false;

CREATE INDEX IF NOT EXISTS projects_company_title_active
  ON public.projects (company_id, title) WHERE deleted_at IS NULL;
```

**`title_is_auto` semantics** — `true` = the name is auto-managed (a pointer to the address); `false` (the column default) = a hand-set name that is never auto-modified. **The default `false` is the iOS-safe default**: a naive insert from the App-Store iOS build in the field (which knows nothing of this column) is treated as hand-set, so the trigger never clobbers an operator-typed name. Auto-naming is opt-in — set `true` only by the conversion/create paths that want it.

**`private.derive_project_name(p_address, p_client_name)` (IMMUTABLE)** — the pure base-name rule (no `#N` suffix):

| State | Auto name |
|---|---|
| Address present | **street line** = substring before the first comma, trimmed (`1240 W 6th Ave`); a comma-less address falls back to the whole string |
| No address, client known | **`{Client}'s Project`** |
| No address, no client | **`New project`** |

**`projects_autoname_biud` trigger** (`BEFORE INSERT OR UPDATE ON public.projects FOR EACH ROW EXECUTE FUNCTION private.projects_autoname()`) — the **enforce-always-while-auto** invariant. When `NEW.title_is_auto = true` the trigger body **always** overwrites `NEW.title` with `derive_project_name(NEW.address, client.name)`, on every insert and every update, regardless of which column changed. Consequences:

- A caller that writes a bare `title` to an auto project (an iOS sync push, a stray `UPDATE projects SET title=…`) **cannot make it stick** — the trigger reverts it to the derived name. The only way to set a custom title is to write `title_is_auto = false` in the **same** statement; to revert to auto, set `title_is_auto = true` (optionally null the title) and the next write re-derives.
- **Name collisions → silent `#N`** (auto names only): when the derived base name already exists for another non-deleted project in the same `company_id`, the trigger appends the lowest free ` #2`, ` #3`, … . The collision scan excludes the row itself, so re-deriving an existing `… #2` is idempotent/stable (it does not climb). Hand-set names are never silently suffixed — a hand-set collision is surfaced as a `DUPLICATE NAME` warning in the UI and the operator decides.
- **Silent** — the trigger only sets `title`; it writes no `project_notes` activity row and dispatches no notification.
- **Trigger ordering** — named `projects_autoname_biud` so it sorts alphabetically before `update_projects_timestamp` (both `BEFORE`); they touch disjoint columns. The `projects_company_title_active` partial index keeps the per-write collision scan O(log n).
- **Self-heal** — a project born `Acme's Project` (no address) automatically becomes `1240 W 6th Ave` the instant any writer — web, iOS, or the email-lifecycle address backfill — fills in the address, because the trigger catches *every* writer. This is why the rule lives in the DB, not app code (app-layer logic would have to be re-implemented in each path and would drift).

**SQL normalizers** — `private.normalize_address(p)` / `private.normalize_title(p)` (same migration) are the single source of truth for duplicate matching, used by `get_conversion_preflight` (§09) and mirrored token-for-token by the TS `normalizeAddress`/`normalizeTitle` (`OPS-Web/src/lib/utils/name-normalization.ts`) the nightly duplicate scan uses — shared test vectors (`OPS-Web/tests/unit/name-normalization.test.ts`) guard the parity. `normalize_address` canonicalizes directionals (`w`↔`west`, `ne`↔`northeast`, …) and street types (`ave`↔`avenue`, `st`↔`street`, `rd`↔`road`, `blvd`, `dr`, `cres`, `hwy`, …) to one token; `normalize_title` returns `''` for the auto-name placeholders (`New project` / `proyecto nuevo` / `{Client}'s Project`) so two unnamed projects never produce a false `same_title` signal.

**iOS-additive contract** — `title_is_auto` is nullable-equivalent (`NOT NULL DEFAULT false`); existing rows backfilled `false`; **no existing project name changed on apply** (0 renames on the 293 prod projects). The App-Store iOS build ignores the unknown column; iOS opts in on its next release (`OPS/DataModels/Project.swift` `titleIsAuto`).

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
1. **Supabase RLS** — Data-level floor. All tables enforce company isolation; financial / pipeline tables (`estimates`, `invoices`, `payments`, `opportunities`, `expenses`, `expense_project_allocations`) additionally layer RESTRICTIVE `role_scope_*` permission policies on top. Core operational tables use company isolation only. See § Expense / Payment / Opportunity RLS Hardening (2026-05-31) for the per-table contracts.
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

### Per-Member Permission Overrides (Migration `20260703120000`, 2026-07-03)

**Context** (BUG BURNDOWN W5): `user_permission_overrides` existed with iOS write/resolve support but was inert on web and **ignored by the server** — `public.has_permission()` and the RLS ceilings (`private.current_user_scope_for` → `current_user_has_permission`) consulted only the admin bypass + role grants. The web Team surface also could not render RBAC data: `user_roles` / `role_permissions` had own-row-only read policies, so a company admin saw phantom/blank roles for every member but themselves. Migration `20260703120000_permission_overrides_engine` fixes all of this additively.

**Effective-permission contract** (identical across the DB functions, iOS `PermissionService`, and web `src/lib/permissions/resolve.ts`):

1. **Admin bypass** — account holder ∪ `companies.admin_ids` ∪ `users.is_company_admin` ⇒ every registered permission at scope `all`. Overrides are ignored for admins.
2. **Override** — a `user_permission_overrides` row for `(user, permission)` **in the user's current company**:
   - `granted = false` ⇒ **denied** (revokes a role grant).
   - `granted = true, scope IS NOT NULL` ⇒ that scope is authoritative (widen *or* narrow vs the role).
   - `granted = true, scope IS NULL` ⇒ inert; falls through to the role.
   - Rows whose `company_id` ≠ the user's current company are ignored (stale).
3. **Role** — widest scope among the user's role's `role_permissions` (`all` > `assigned` > `own`).

**iOS account-admin parity (2026-08-18 — bug `bb4775c1`).** iOS previously
entered the role branch first and threw `noRoleAssigned` when an account holder
had no `user_roles` row. `PermissionStore` then loaded an empty cache and every
gate failed closed, even though the database and web correctly treated the same
account as an admin. `PermissionService.fetchPermissions` now resolves
`AdminAuthority` first from the canonical `users` and `companies` rows, using the
same exact-text predicates as `private.current_user_is_admin()`:
`users.is_company_admin`, `companies.account_holder_id`, or
`companies.admin_ids`, with soft-deleted users excluded. An admin receives every
registered client permission at scope `all` without consulting role or override
rows; feature flags still outrank that authority. A failed admin probe is
`unknown`, not `false`, so an initialized store preserves its last-known answer;
an empty cache and an explicit non-admin result continue to fail closed. Sources:
`ops-ios/OPS/Utilities/AdminAuthority.swift`,
`ops-ios/OPS/Network/Supabase/PermissionService.swift`, and
`ops-ios/OPS/Utilities/PermissionStore.swift`; implementation commit `aa40d4a5`,
focused regression cover in `OPSTests/Utilities/AdminAuthorityTests.swift`.
Production's five broken owner rows were independently repaired by
`20260818224814_repair_web_onboarded_owner_role_rows.sql`; a 2026-08-20 live
read found zero active account admins/account holders without a `user_roles`
row. The iOS defense remains required because account authority must not depend
on denormalized role-row completeness.

**Functions changed** (`CREATE OR REPLACE`, signatures unchanged): `public.has_permission(uuid,text,text)` and `private.current_user_scope_for(text)` fold in the override lookup between the admin bypass and the role lookup. `private.current_user_has_permission` composes the latter and needed no edit.

**Read policies added** (permissive, `TO public` — the app executes as anon): `user_roles` SELECT for same-company members; `role_permissions` SELECT for preset-or-same-company roles. These un-break the Team roster + Roles editor + the member access view with **no app release** (iOS reads benefit too).

**Write policies:** the four `user_permission_overrides` admin policies were widened to `current_user_is_admin() OR current_user_has_permission('team.assign_roles','all')` (matches the stated write contract). The `roles` write policies were tightened to **same-company + (admin OR `team.assign_roles`)**, closing a prior cross-tenant hole (any member could previously mutate any company's custom roles). No new anon write grants — RBAC writes go through guarded service-role routes (below).

**Registry rule (load-bearing):** `src/lib/types/permissions.ts` `ALL_PERMISSIONS` must remain a **superset** of every permission string granted in the DB — account holders/admins derive access from the registry via the bypass, so an unregistered DB string is silently denied to the owner while grantable to crew (the inverted-privilege trap). W5 registered the live-but-unregistered strings: `deck_builder.{view,create,edit}`, `projects.view_financials`, `inventory.manage`, `finances.view`, `time_off.approve`, `profile.edit`. **`spec.admin` is deliberately excluded** — registering it would hand the internal SPEC console to every company admin via the bypass; the override write route validates against the registry so the product surface can never display or write it.

**Write routes** (service-role, Firebase-token verified, company-matched — mirror `PATCH /api/users/[id]/role`):
- `PUT /api/users/[id]/permission-overrides` — `{ set:[{permission,scope,granted}], clear:[permission] }`. Rejects bypass-admin targets (409), unregistered permissions, and unsupported scopes; upserts on `(user_id, permission)` with the target's `company_id`; notifies the member. Powers the Team member access editor.
- `PUT /api/roles/[id]/permissions` — transactional replace of a non-preset, same-company role's grants (the prior client-side write bounced off RLS as anon).
- `DELETE /api/users/[id]/role` — removes a `user_roles` row + resets legacy `users.role` to `unassigned`.

**iOS note:** iOS already resolves overrides client-side and writes them via `PermissionAdminService`; this migration aligns the server to that behavior (widen-only for the 18 pre-existing grant rows — zero revokes — so no live traffic is affected). iOS adoption of the guarded web write routes is a future item; today iOS RBAC writes rely on its own direct-table paths.

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

### project_tasks read policy — row-based RETURNING fix (2026-08-17)

Migration `20260818014340_project_tasks_returning_visibility.sql` (applied to prod + mirrored in `migrations/`, bug `06810537`).

**The defect.** `project_tasks.role_scope_read` (RESTRICTIVE · SELECT) called `private.current_user_can_view_task(id)` → `private.user_can_view_task(actor, id)`, which **re-fetches the task row by id**. Postgres evaluates SELECT policies against the NEW row on `INSERT .. RETURNING`, and a STABLE (or any) function's inner query runs under the statement's snapshot — where the row being inserted does not exist yet. `not found` → `false` → `42501 new row violates row-level security policy "role_scope_read"`, rolling back the whole insert. Every PostgREST task insert with `Prefer: return=representation` failed this way for every actor — including the account owner with `tasks.view all` — because the not-found gate fires before any permission arm. Proven by rolled-back probe: the identical insert succeeds without RETURNING, and the very next command's SELECT passes the same policy for the same row.

**The fix.** The policy now judges the candidate row's own column values — no re-fetch:

- `private.user_can_view_task_columns(p_actor_user_id, p_company_id, p_project_id, p_team_member_ids, p_deleted_at)` — mirrors `user_can_view_task` exactly: soft-deleted rows invisible; requires a live same-company project and an active same-company actor; `tasks.view all` → true; `tasks.view assigned` → team membership or `private.user_can_view_project`. `SECURITY DEFINER`, postgres-only ACL.
- `private.current_user_can_view_task_row(company_id, project_id, team_member_ids, deleted_at)` — actor-resolving wrapper, EXECUTE granted to `anon` + `authenticated` (the policy's caller roles).
- `role_scope_read` USING is now `private.current_user_can_view_task_row(company_id, project_id, team_member_ids, deleted_at)`.

**Parity evidence.** 1,383 task × user comparisons on live data (account owner + two crew members; every task of the operator company including soft-deleted rows, plus 300 foreign-company rows): 0 verdict mismatches between the by-id and row-based functions, re-run green post-apply. Live probes: the failing insert echoes its row; soft-deleted tasks remain invisible; owner-visible live rows unchanged.

**Kept / unchanged.** The by-id functions remain for their existing callers (`persist_task_mutation_notification_as_system`, `private.agent_user_can_access_entity`). Shipped-client audit: iOS task updates and soft-deletes are minimal-returning (no RETURNING evaluation), and web does not write `project_tasks` via PostgREST — so the row-based `deleted_at IS NULL` arm cannot regress any live request. A future UPDATE that sets `deleted_at` AND requests representation will (correctly) refuse to echo a row the actor can no longer see — use minimal returning for soft-deletes.

### clients + projects read policies — same row-based RETURNING fix (2026-08-19)

Migration `migrations/20260819152448_client_project_read_policy_row_columns.sql` — **APPLIED to production 2026-08-19, ledger version `20260819152448`.** Verify by object, never by version key.

**The defect is the one above, on two more tables.** The `project_tasks` repair (2026-08-17) fixed one member of a class and left the rest. `public.clients.role_scope_read` resolved its row through `private.current_user_can_view_client(id)` → `private.user_can_view_client(actor, company, client_id)`, whose first gate re-reads `public.clients` by id; `public.projects.role_scope_read` did the same through `private.current_user_can_view_project_scoped(id)` → `private.user_can_view_project(actor, project_id)`, whose first statement reads `public.projects` by id. Postgres applies SELECT policies to an `INSERT … RETURNING` row as an INSERT check, evaluated in `ExecInsert` **before** the tuple is written, so the self-lookup can never find it. The admin arm sits below the existence gate in both, so being the account owner does not help.

**Live impact.** `analytics_events` `sync_parked`, company `a612edc0-5c18-4c4d-af97-55b9410dd077`, 2026-08-19 02:54:40Z: entity `client`, operation `create`, `retry_count 0`, `new row violates row-level security policy "role_scope_read" for table "clients"`. The customer ("Peter athlone Dr") never reached the server and existed only on the founder's phone. iOS `ClientRepository.create` and `ProjectRepository.create` both used `.insert(dto).select().single()` — `.select()` is what appends `Prefer: return=representation`.

**The fix.** Same shape as `current_user_can_view_task_row`, ladder preserved exactly, self-lookup dropped:

- `private.user_can_view_client_columns(p_actor_user_id, p_actor_company_id, p_client_id, p_company_id, p_deleted_at)` — soft-deleted invisible; row's `company_id` must equal the actor's; active company member; admin → true; `clients.view all` → true; `clients.view assigned` → on a task of a project of this client (still deliberately team-assignment-only, no note-mention grant). `SECURITY DEFINER`, postgres-only ACL.
- `private.current_user_can_view_client_row(p_client_id, p_company_id, p_deleted_at)` — actor-resolving wrapper, EXECUTE to `anon` + `authenticated`.
- `private.user_can_view_project_columns(p_actor_user_id, p_project_id, p_company_id, p_deleted_at)` + `private.current_user_can_view_project_row(...)` — same treatment; no explicit admin arm, matching the original (`public.has_permission` short-circuits for admins).
- `role_scope_read` USING becomes `current_user_can_view_client_row(id, company_id, deleted_at)` / `current_user_can_view_project_row(id, company_id, deleted_at)`.

**Replica proof** (PostgreSQL 17.11, prod function + policy bodies loaded verbatim). Before: admin `INSERT … RETURNING` on both tables → `42501 role_scope_read`; the same insert without RETURNING → accepted. After: both accepted. Authorization surface byte-identical across the two runs — admin and `clients.view all` see the same two rows, `clients.view assigned` sees only its linked customer, a foreign-company admin sees only its own company's row, a deactivated member sees nothing, soft-deleted rows stay invisible; cross-tenant `INSERT … RETURNING`, a deactivated member's insert, and an insert of a born-deleted row are all still refused.

**Kept / unchanged.** The by-id functions stay for their many other callers — `user_can_view_sub_client`, `current_user_can_view_activity`, `current_user_can_view_deck_design`, `current_user_can_view_site_visit`, `current_user_can_view_duplicate_review`, `user_can_view_calendar_event`, `user_can_view_task_columns`, `current_user_can_view_job_conversation` — where the lookup targets a table OTHER than the one being written and is correct.

### Remaining read policies — class sweep completed (2026-08-19)

Migration `migrations/20260819163000_remaining_read_policy_row_columns.sql` — **authored, verified on a local replica, NOT YET APPLIED.** Verify by object, never by version key (it has no ledger row until it is applied). This closes the class: a catalog scan of every RESTRICTIVE SELECT policy in `public` confirms these five were the complete remaining set.

**ACL_SELECT, not `RETURNING`, is the real trigger.** The earlier write-ups framed this as an `INSERT … RETURNING` problem. Proven on the replica, the guard also fires for **`INSERT … ON CONFLICT DO UPDATE` carrying no `RETURNING` clause at all** — `rowsecurity.c` attaches SELECT/ALL policies as `WCO_RLS_INSERT_CHECK` whenever the target RTE requires `ACL_SELECT`, and an upsert requires it to resolve the conflicting row. Sending `Prefer: return=minimal` does **not** make an upsert safe from this.

| Table | Policy | Old predicate (self-reads) | New row-shaped predicate |
|-------|--------|----------------------------|--------------------------|
| `sub_clients` | `role_scope_read` | `current_user_can_view_sub_client(id)` → `user_can_view_sub_client` | `current_user_can_view_sub_client_row(client_id, company_id, deleted_at)` |
| `calendar_events` | `calendar_event_read_scope_guard` | `current_user_can_view_calendar_event(id)` | `current_user_can_view_calendar_event_row(company_id, project_id, team_member_ids, deleted_at)` |
| `calendar_user_events` | `calendar_user_event_read_scope_guard` | `current_user_can_view_calendar_user_event(id)` | `current_user_can_view_calendar_user_event_row(user_id, company_id, type, team_member_ids, deleted_at)` |
| `opportunities` | `role_scope_read` (first conjunct only) | `current_user_can_view_opportunity(id)` → `user_can_view_opportunity` | `current_user_can_view_opportunity_row(company_id, assigned_to, deleted_at)` |
| `job_conversations` | `job_conversations_job_scope_select` | `current_user_can_view_job_conversation(id)` | `current_user_can_view_job_conversation_row(id, company_id)` |

**Client reality, corrected against the iOS source (supersedes the earlier audit's read).**

- `sub_clients` — genuinely broken, on exactly one path. `ClientRepository.createSubClient` (`ops-ios/OPS/Network/Supabase/Repositories/ClientRepository.swift:177`) does `.insert(payload).select().single()` and `LeadDetailViewModel.addContactToClient` appends the decoded DTO to its published `subClients` array, so `.select()` cannot simply be dropped — this is the "add contact to client" action. The durable-queue path (`DataActor.genericTablePush`, `DataActor.swift:5652`) is **not** affected: it calls `.insert(payload)` with no `returning:` argument, and supabase-swift's `insert(_:returning:count:)` defaults that to `nil` and emits **no** `Prefer` header, leaving PostgREST on its own `return=minimal` default. Only `.select()` sets `Prefer: return=representation` (`PostgrestTransformBuilder.swift:29`), and `upsert` is the one that defaults to `.representation`.
- `calendar_user_events` — broken, but **not** via `CalendarUserEventRepository.create` as previously recorded. That function's only caller, `PersonalEventSheet`, is unreachable at runtime (superseded by `UserEventSheet`). The live path is `CalendarUserEventRepository.upsertEvent` (`:157`), an upsert sent with `returning: .minimal` — which the ON CONFLICT rule above shows is refused anyway. Prod corroborates: 2 rows total, 0 in 30 days, newest 2026-05-01.
- `calendar_events` — no iOS write path exists at all (the app writes `calendar_user_events` instead). Prod: 0 rows, ever.
- `opportunities` — no direct iOS insert; leads are created through the SECURITY DEFINER RPC `create_opportunity_guarded`, which bypasses RLS. Prod: 75 inserted in 30 days.
- `job_conversations` — `authenticated` holds **SELECT only** (no INSERT grant), so a client insert is refused on privileges before RLS is consulted. The self-lookup is dropped for hygiene and read cost, not to enable a write.

**The `job_conversations` anchor gate is deliberate and is left alone.** Its predicate's second `exists` requires a matching `job_conversation_anchors` row, which by construction cannot exist at the instant the conversation row is inserted. That is an authorization rule, not the class defect; widening it would widen authorization. Writes stay on service-role / SECURITY DEFINER paths.

**Replica proof** (PostgreSQL 17.11, prod function and policy bodies loaded verbatim; clean rebuild, before → migration → after). Before: `sub_clients`, `calendar_events`, `calendar_user_events` and `opportunities` all rejected admin `INSERT … RETURNING` with `42501` naming their own guard, and the `calendar_user_events` upsert-without-RETURNING was rejected too; the same `sub_clients` insert *without* RETURNING was accepted, isolating `ACL_SELECT` as the trigger. After: all five accepted. `job_conversations` is refused identically in both runs (`permission denied for table`, a grant check — not RLS). Authorization surface byte-identical across the runs: 25 visibility cells (5 personas — company admin, scope `all`, scope `assigned`, deactivated member, foreign-company admin — × 5 tables) match exactly, and cross-tenant inserts (A→B and B→A), born-deleted-row inserts, deactivated-member inserts, and `assigned`-scope inserts of rows the actor could not then read (sub-client under an unlinked client, opportunity with `assigned_to` NULL, calendar event with empty team and no project) are all still refused. Zero probe rows persisted.

**Kept / unchanged.** All nine by-id functions stay, for callers where the lookup targets a different table and is correct: `follow_ups`, `stage_transitions` and the `opportunities` merge-target conjunct call `current_user_can_view_opportunity`; `job_conversation_anchors`, `job_conversation_turns`, `job_conversation_redaction_events`, `job_memory_versions` and `job_memory_version_evidence` all call `current_user_can_view_job_conversation(conversation_id)`.

### Auth ID Resolution

**Critical**: `users.id` (the application UUID) differs from the auth identity. The
`users` table carries `auth_id` (provider-agnostic token sub) and `firebase_uid`
(Firebase UID only). Identity is ~100% Firebase: the JWT is a Firebase ID token whose
`sub` claim == the Firebase UID; Supabase Auth (`auth.users`) holds only a handful of rows.

Five SECURITY DEFINER helpers resolve the caller for every RLS policy:
`private.resolve_uid()`, `private.get_current_user_id()`, `private.get_user_company_id()`,
`public.get_user_company_id()`, `private.current_user_is_admin()`. Every RLS policy that
needs identity goes through one of these — as of 2026-06-14, **296 dependent objects**
(228 policies + 58 functions + 1 view + 9 triggers) reach the resolver only through these
five bodies; none inline the comparison.

**Current resolution (email-based — CRIT-3 vulnerability):** the live helpers resolve by
`WHERE email = (auth.jwt() ->> 'email')`. Because OPS historically never sent Firebase
email verification, `email_verified` was permanently false, so an attacker could register a
Firebase account on a victim's email and be resolved as the victim by every policy.

**Re-key to the cryptographic sub (CRIT-3 Phase C — APPLIED to prod 2026-06-14,
migration `20260614083934_crit3_phase_c_rekey_rls_identity_helpers`):** the helpers now
resolve by
`WHERE (auth_id = (auth.jwt() ->> 'sub') OR firebase_uid = (auth.jwt() ->> 'sub'))`.
Since all 296 dependents resolve through the five bodies, this was a `CREATE OR REPLACE` of
five functions; zero policy DDL. Applied only after a bulk Firebase backfill made every
active user that *has a Firebase account* sub-linked (the ~140 still-unlinked rows are
dormant no-Firebase legacy/test accounts that self-heal via the sync-user legacy-link path
on first login). Live post-apply: linked users' access unchanged (verified 310 projects /
362 clients), advisors clean. Forward SQL + rollback + probe matrix:
`ops-ios/docs/superpowers/migrations/2026-06-14-crit3-phase-c-rekey-rls-helpers.sql`;
full plan + execution log: `ops-ios/docs/superpowers/specs/2026-06-13-crit3-identity-rekey-followup.md`.

Linkage convergence (Phase A): `findUserByAuth` opportunistically stamps `auth_id = sub` on
cryptographic matches; a daily `pg_cron` job (`crit3-identity-linkage-daily`) records
`private.identity_linkage_metrics`; `scripts/crit3-backfill-identity.ts` bulk-links from
Firebase Admin. Phase B wired Firebase email verification so `email_verified` is now
meaningful. Phase D (behind env `CRIT3_SUB_IDENTITY`) drops the web email fallbacks and
routes the `/api/setup/progress` privileged write through the sub-resolving
`public.update_company_setup_for_member` RPC (MED-3).

All RLS policies use these helpers (e.g. `private.get_current_user_id()`,
`private.get_user_company_id()`) instead of `auth.uid()` directly.

### Expense / Payment / Opportunity RLS Hardening (2026-05-31)

**Context**: A Books-tab review surfaced a critical multi-tenant data-exposure surface on the expense tables. `expenses`, `expense_project_allocations`, and `expense_categories` each carried a single permissive `USING (true)` policy for role `public` with full CRUD granted to `anon` + `authenticated` — meaning the shipped anon key (no login) could read, insert, update, and delete **every company's** expense data. `payments` and `opportunities` were company-isolated but had **no** permission scoping, so a same-company user without finances / pipeline access could still read them via a direct query.

Two migrations closed the gap, both replacing the old policies with the layered company-isolation + role-scope pattern already used by `invoices` / `estimates`. As with all OPS RLS, every policy targets role `public` (the app executes as the anon role — see § Auth ID Resolution and the Permission Enforcement Matrix), and the layered enforcement uses **one PERMISSIVE `company_isolation` policy `FOR ALL`** (the tenant floor) combined with **per-command RESTRICTIVE `role_scope_*` policies** (the permission ceiling). PERMISSIVE policies are OR'd together; RESTRICTIVE policies are AND'd, so a row is visible only when it passes company isolation **and** every applicable restrictive scope check.

**Migration `20260531200227_fix_expenses_rls_company_and_role_scope`** — replaced the `USING (true)` policies on the three expense tables:

| Table | Policy | Type / Cmd | Predicate |
|-------|--------|------------|-----------|
| `expenses` | `company_isolation` | PERMISSIVE · ALL | `company_id = (SELECT private.get_user_company_id())` |
| `expenses` | `role_scope_read` | RESTRICTIVE · SELECT | `current_user_is_admin() OR CASE current_user_scope_for('expenses.view') WHEN 'all' THEN true WHEN 'own' THEN (get_current_user_id() = submitted_by) ELSE false END` |
| `expenses` | `role_scope_insert` | RESTRICTIVE · INSERT | `WITH CHECK current_user_has_permission('expenses.create','all')` |
| `expenses` | `role_scope_update` | RESTRICTIVE · UPDATE | `current_user_is_admin() OR current_user_has_permission('expenses.approve','all') OR CASE current_user_scope_for('expenses.edit') WHEN 'all' THEN true WHEN 'own' THEN (get_current_user_id() = submitted_by) ELSE false END` |
| `expenses` | `role_scope_delete` | RESTRICTIVE · DELETE | `current_user_is_admin() OR current_user_has_permission('expenses.delete','all')` |
| `expense_categories` | `company_isolation` | PERMISSIVE · ALL | `company_id = (SELECT private.get_user_company_id())` — company reference data, no per-user scope |
| `expense_project_allocations` | `company_isolation` | PERMISSIVE · ALL | `EXISTS (SELECT 1 FROM expenses e WHERE e.id = expense_project_allocations.expense_id AND e.company_id = (SELECT private.get_user_company_id()))` — table has no `company_id`; isolation rides the parent expense |
| `expense_project_allocations` | `role_scope_read` | RESTRICTIVE · SELECT | `current_user_is_admin() OR EXISTS (SELECT 1 FROM expenses e WHERE e.id = expense_project_allocations.expense_id AND CASE current_user_scope_for('expenses.view') WHEN 'all' THEN true WHEN 'own' THEN (get_current_user_id() = e.submitted_by) ELSE false END)` — read scope inherits the parent expense's `expenses.view` scope |

**Expense `own`-scope is now enforced at the database.** Crew and Operator hold `expenses.view` / `expenses.edit` / `expenses.delete` at `own` scope (see § Preset Role Permission Summary); the `submitted_by = get_current_user_id()` branches above mean those users can no longer read or mutate another user's expense rows even via a direct Supabase query — enforcement is no longer app-layer-only. `expense_project_allocations` carries no `role_scope_insert/update/delete`. Shipped direct-table clients remain gated by the parent expense's restrictive policies, and their legacy relation mutations advance the parent expense's strict `updated_at` token through `trg_touch_expense_from_allocation`. The current expense form replaces allocations through the permission-checked `save_expense_atomic` SECURITY DEFINER RPC, inside the same transaction as the expense snapshot, placement, and envelope-total recalculation (§ `09_FINANCIAL_SYSTEM.md` Expense Rules).

**Migration `20260531200501_fix_payments_opportunities_permission_scope`** — added a permission ceiling to two already-isolated tables (their existing `company_isolation` PERMISSIVE `FOR ALL` policies were left intact):

| Table | Policy | Type / Cmd | Predicate |
|-------|--------|------------|-----------|
| `payments` | `role_scope_read` | RESTRICTIVE · SELECT | `current_user_has_permission('invoices.view','all')` |
| `opportunities` | `role_scope_read` | RESTRICTIVE · SELECT | `current_user_can_view_opportunity(id) AND (merged_into_opportunity_id IS NULL OR current_user_can_view_opportunity(merged_into_opportunity_id))` — corrected 2026-08-19 from a long-stale `current_user_has_permission('pipeline.view','all')`; verified against prod. Pending `20260819163000`, the first conjunct becomes `current_user_can_view_opportunity_row(company_id, assigned_to, deleted_at)` |

**Verification (2026-05-31)**: executed as the anon role, all five tables now return 0 rows; an `own`-scope user sees only expenses where `submitted_by` matches their own user id. Migration SQL is mirrored in `migrations/` and the per-table contracts are echoed in `09_FINANCIAL_SYSTEM.md` (Expense Tracking System, Supabase Schema Reference).

### Atomic Expense Save + Strict CAS (2026-07-19)

`migrations/20260720004500_expense_atomic_save.sql` adds the authenticated `public.save_expense_atomic(p_command jsonb)` write boundary used by the current iOS expense form. The command is a complete intended snapshot, not a patch: it validates the caller and company, submitter-owned edit authority, category and project ownership, money/date precision, receipt/project submission policy, exception metadata, allocation uniqueness and exact 100% total, and `per_job` scope before any durable change.

The RPC performs strict compare-and-swap against both `expenses.status` and `expenses.updated_at`, replaces allocations, submits or re-files the line, places it into the correct envelope, and recalculates every affected source/destination envelope in one transaction. An unchanged exact retry returns reconciled live state; a stale status or timestamp is rejected instead of overwriting concurrent work. Receipt and project requirements apply only when `submit=true`, preserving draft compatibility.

`expenses.updated_at` is backfilled, `NOT NULL`, and maintained by `trg_set_expense_updated_at`, which guarantees a strictly advancing token even for rapid writes. `trg_touch_expense_from_allocation` also advances the parent token when shipped direct-table clients mutate allocations. The atomic path uses the same allocation-before-parent lock order as those triggers to prevent deadlocks.

`private.expense_save_requests` is the private hash-only idempotency ledger. It stores request/company/user/expense identifiers, a SHA-256 command hash, completion state, and timestamps—never receipt URLs, OCR text, notes, or monetary content. Completed entries older than the 90-day idempotency window become eligible for opportunistic per-company pruning on a later save; this is not a guaranteed TTL.

The live follow-up `migrations/20260720005500_fix_expense_batch_recalculation_alias.sql` corrects the batch-row alias in `public.recalculate_expense_batch_total` while preserving its same-company authorization, lock order, service-role access, and no-JWT `postgres` cron compatibility.

### Security Posture Sweep — W3 (2026-07-03)

**Context**: bug `c5ff388e` ("31 public tables have RLS disabled") was found **stale** — as of 2026-07-03, 0 of 266 public tables have RLS disabled (verified via `pg_class`). A fresh `get_advisors(security)` sweep (167 lints) was dispositioned against the current posture. The 2026-05-31 hardening (above) fixed the expense/payment/opportunity `USING(true)` exposures; this pass covers the remaining ones. Full per-item disposition: `ops-web/docs/artifacts/w3-security-posture-disposition-2026-07-03.md`.

**Standing model reaffirmed**: the app (web + iOS) executes as the **anon** role under the Firebase JWT bridge; `auth.uid()` is unusable (`sub` is a non-uuid Firebase UID). `private.get_user_company_id()` returns **uuid**; `public.get_user_company_id()` returns **text** — do not confuse them in policy/function predicates. `service_role` and `postgres` carry `rolbypassrls = true`, so cron/agent writes survive removing anon policies.

**Migrations authored on branch `fix/security-posture-sweep` (sentinel-proven; pending operator apply — direct prod DB, no auto-deploy):**

| Migration | Change |
|-----------|--------|
| `20260703170000_sec_w3_fix_always_true_policies` | `qa_bugs` ALL/`true`/`{public}` (full anon CRUD incl. DELETE on 234 rows) → `qa_bugs_ops_admin_all` (`private.is_ops_admin()`); `beta_access_requests` SELECT/`true` (leaked every signup email) → own-rows (`user_id = private.get_current_user_id()::text`); `duplicate_reviews` INSERT/`true` → own-company. |
| `20260703170100_sec_w3_storage_public_bucket_listing` | Dropped 6 broad `storage.objects` SELECT/list policies (client-images, images, logos, product-thumbnails, profiles, project-photos). Public object URLs unaffected (advisor lint 0025); no app `.list()` usage. |
| `20260703170200_sec_w3_revoke_anon_execute_functions` | Revoked anon/authenticated EXECUTE on 7 no-client-caller SECURITY DEFINER fns: `audit_trigger_fn`, `tr_activity_first_log_auto_advance` (triggers), `fire_due_task_reminders` (cron), `resolve_task_reminder_recipients`, `users_with_permission` (internal helpers), `increment_opportunity_correspondence`, `qbo_match_customer_candidates` (server-only; latter leaked cross-company client name/email/phone). service_role retains EXECUTE. |
| `20260703170300_sec_w3_revoke_anon_grants_asc_tables` | Revoked anon/authenticated table grants on 8 `asc_*` App Store Connect tables (service-role-only operator analytics; the grants were a latent RLS-toggle landmine). |
| `20260703170400_sec_w3_harden_secdef_function_bodies` | Added caller guards to `get_inbox_density_per_client` (silent-empty unless `private.get_user_company_id() = p_company_id`) and `remove_seated_employee` (end-user callers must be an admin of the target company; service_role bypasses). Batch 2 — apply after the iOS remove-seat flow is confirmed. |

**`rls_enabled_no_policy` (26 tables)** — all confirmed correct **service-role-only** (RLS-deny + service_role-only grants); no new policy needed. Tables: `ad_briefings`, `ads_daily_account/campaign/keyword/search_term`, `ads_sync_status`, `admin_feature_overrides`, `lifecycle_email_config`, `newsletter_content`, `email_events`, `email_ingest_heartbeat_log`, `onboarding_events`, `portal_sessions`, `portal_tokens`, `project_team_members` + `task_team_members` (both 0 rows — the app uses the denormalized `projects/tasks.team_member_ids` array + the `assign/remove_project_team_member` RPCs; the join tables are reserved), `deck_zoning_parcel_records`, `private.identity_linkage_metrics`. The 8 `asc_*` tables were the only defect (over-broad grants → M4).

**Anon SECURITY DEFINER function surface** — the ~42 remaining anon-executable SECURITY DEFINER functions are the **intentional app RPC surface** under the anon bridge (project/opportunity table-view CRUD, lead/estimate/opportunity conversions, expense + catalog + product import RPCs, `get_user_company_id`/`get_user_id`/`has_permission`/`is_company_admin`, `get_photo_annotations_since` + `upsert_markup_layer`, `record_auto_bug`, `submit_feature_request`). `check_user_exists_by_email` is kept as accepted low-risk email enumeration (boolean only; backs signup/login UX). The `p_company_id`-taking catalog/conversion/product RPCs were not body-audited this pass (owned by active workstreams) — flagged for a follow-up caller-company-enforcement audit.

**Cross-app assessment exposure — re-investigated + FIXED 2026-07-05 (applied to prod)** — `assessment_responses` / `assessment_sessions` / `assessment_submissions` / `enrollments` each carried an anon/public `SELECT USING (true)` policy (plus `assessment_sessions."sessions_update_own"` `UPDATE USING(true)/CHECK(true)`) — a genuine PII leak (`assessment_sessions` exposes email / first_name / ai_analysis). Live anon-visible counts (verified via `SET ROLE anon`): **662 sessions / 9315 responses / 206 enrollments / 1 submission** readable through the public `NEXT_PUBLIC_SUPABASE_ANON_KEY` over PostgREST. The earlier "token-scoped SECURITY DEFINER RPC inside ops-learn" recommendation is **superseded** by the real read pattern: the reader of `assessment_sessions`/`assessment_responses` is **ops-site** (the leadership-assessment lead-gen funnel — `src/lib/assessment/actions.ts`, a `'use server'` module), *not* ops-learn, and it reads/writes exclusively via `getSupabaseAdmin()` (`SUPABASE_SERVICE_ROLE_KEY`); `getResults(token)` resolves the token server-side and returns rows across the server-action boundary, so the browser never queries these tables with the anon key. `enrollments` / `assessment_submissions` are ops-learn's, read via `createServiceClient()` (service role) filtered by the Firebase-verified `user_id`; ops-learn's browser anon client is imported by nothing. No realtime subscription, view, or anon/authenticated client depends on the policies — they are pure attack surface. Because every real accessor is service_role (RLS-bypass), the fix is the exact analog of the Storage finding below: **drop the 5 anon SELECT/UPDATE-`true` policies** — NOT a new RPC and NOT a `TO authenticated` tighten (neither app has an anon/authenticated read path here). No app change, no deploy. The 4 INSERT policies are left intact (out of this finding's scope); an optional service-role-only lockdown (revoke the unused anon/authenticated DML grants + drop the anon INSERT policies) is noted for a follow-on. Migration `20260705184145_drop_assessment_anon_read_policies` (+ rollback) sentinel-proven then **applied to prod 2026-07-05 (operator-approved)**. Post-apply live verification: as anon sessions/responses/submissions/enrollments = **0 / 0 / 0 / 0**; privileged row counts intact (662 / 9315 / 1 / 206 — nothing deleted, only the read path closed); only the 4 INSERT policies remain; `get_advisors(security)` = 148 lints, no ERROR level, no regression. The four tables' residual `rls_policy_always_true` lints are now their INSERT-only anon-submission policies — the same accepted pattern as `newsletter_subscribers` / `analytics_events` / `beta_access_requests` — left in place as the documented optional service-role-only follow-on (operator chose the core fix).

**Storage (§7 additional finding — RESOLVED, applied to prod 2026-07-05)** — the public `images` and `social-media` buckets carried `storage.objects` policies letting the (public) anon key INSERT/UPDATE/DELETE with only a `bucket_id` check and no auth, so an outsider holding the anon key could overwrite or delete objects (for `social-media`, whose graphics auto-publish to Instagram, a brand-integrity vector). Verification confirmed **every real writer is service_role**: ops-web writes both buckets server-side via `getServiceRoleClient()` (`uploads/presign`, `uploads/delete`, `admin/blog/upload`, `email/extract-images`; the default storage backend is S3 regardless), the social-media generator `scripts/social-generators/supabase_upload.py` authenticates with the **service_role** key (`git log -S SUPABASE_ANON_KEY` proves the anon key was never in it — service_role since its first commit 2026-04-15, predating every stored object; the `test-anon-write.jpg`/`probe-*.png` objects are a pre-commit prototype fingerprint), and the Instagram publisher edge function only reads public URLs. Because service_role/postgres bypass RLS, the correct fix is to **drop the 6 anon write policies** — NOT "tighten to `authenticated`" (the app has no `authenticated` write path; it runs as the anon bridge, so an `authenticated`-scoped policy would be dead and misleading). Public serving is unaffected (getPublicUrl bypasses RLS; `images`' listing policy was already dropped by M2, `social-media` never had one). Migration `20260705170000_sec_w3_storage_anon_write_revoke` (+ rollback) was sentinel-proven against prod in rolled-back transactions (baseline anon INSERT ALLOWED on both → post-drop anon INSERT/UPDATE/DELETE BLOCKED, RLS 42501, on both; service_role INSERT still succeeds) and **applied to prod 2026-07-05 (operator-approved)**. Post-apply verified live: all 6 anon write policies dropped, anon INSERT blocked (42501) on both buckets, service_role writes unaffected. Team image uploads were confirmed independent of these buckets — iOS + web route photos through `/api/uploads/presign` to **S3** (service_role), the only iOS direct-to-Supabase upload targets the untouched `product-thumbnails` bucket, and the team image buckets (`profiles`/`logos`/`client-images`/`product-thumbnails`) hold 0 objects.

**Sentinel evidence (all against prod, in rolled-back transactions)** — `request.jwt.claims` simulation across Canpro + Maverick (admin + member each), a pure ops-admin, and raw anon confirmed every scoping predicate; end-to-end `SET ROLE anon` proved qa_bugs row visibility = {operator 234, member 0, anon 0} and the hardened `get_inbox_density_per_client` = {own-company 241, cross-company 0, raw anon 0}.

**Applied 2026-07-03 (operator-approved):** M1–M4 + a follow-up (M6) are **live on prod** (advisor delta 167 → 149; smoke check: a live Canpro admin still sees 332 projects / 407 photos / 395 clients / 437 opportunities). M6 revokes anon/authenticated grants on the `asc_conversion_daily` **security_invoker view** — a 9th App Store object surfaced during post-apply verification; M4 had already closed its read path (base-table revoke), M6 removes the vestigial grant. The seven other anon-granted `security_invoker` views (`inventory_*`, `project_table_rows`) are intentional company-scoped product views and were left in place. M5 (function-body hardening) was **corrected before apply**: `remove_seated_employee`'s only caller is the iOS account-self-deletion cleanup (target already soft-deleted), not admin removal, so its guard was retargeted from "admin of the company" to "target is an already-soft-deleted member" (blocks evicting active members; permits the cleanup). M5 remains **pending operator go**.

### SYSTEMS REPAIR Wave 1 — server-side repairs (2026-07-29)

Wave 1 of the SYSTEMS REPAIR plan (`specs/2026-07-29-systems-repair-plan.md`), which
executes the fixes found by the 2026-07 SYSTEMS AUDIT (settings / sync / database /
photos). Every item here is **server-side only** — no app release was required, so all
shipped iOS builds picked the changes up immediately. Applied directly to prod
`ijeekuhbatykdomumfjx` under the operator's wave approval.

| Migration / action | Change |
|---|---|
| `add_estimates_notes_for_ios_ar_decks` | `ALTER TABLE estimates ADD COLUMN notes text` (nullable, additive). iOS `CreateEstimateDTO` has always carried a `notes` key with no backing column, so every AR-measured deck estimate died on PGRST204 (`DeckBuilder/DeckBuilderViewModel.swift:4169-4177` always sends `arAccuracyNote`). Manual decks survived only because a nil value is omitted from the payload. See `09_FINANCIAL_SYSTEM.md` § EstimateDTOs.swift. |
| `fix_feature_requests_insert_policy_anon_bridge` | Dropped the legacy `auth.role() = 'authenticated'` INSERT policy (dead under the Firebase bridge, which executes as **anon**) and replaced it with `TO anon, authenticated WITH CHECK (company_id = private.get_user_company_id()::text)`, mirroring `bug_reports`. Because the iOS payloads (`Views/Settings/Components/ReportIssueView.swift:166-177` "Report Issue", `Views/Settings/WhatsNewView.swift:254-264` feature voting) send no `user_id`/`company_id` at all, a `BEFORE INSERT` trigger `trg_feature_requests_00_stamp_identity` stamps both from the resolved bridge identity (`private.resolve_uid()`, `private.get_user_company_id()`); RLS `WITH CHECK` evaluates the post-trigger row, so tenancy passes exactly when the requester resolves to a real user with a company. `COALESCE` means service-role callers (the `submit-feature-request` edge function) keep their explicit values. Both iOS feedback flows had produced **zero** rows since launch. |
| `project_photos_update_grants_and_write_guard` | Column-scoped `GRANT UPDATE (deleted_at, is_client_visible, caption)` to `anon, authenticated` + `BEFORE UPDATE` guard `trg_project_photos_00_write_guard`. Full contract and rationale in `07_SPECIALIZED_FEATURES.md` § Synced `project_photos` gallery store. Bug `1154fe67`. |
| Edge-function tombstones (no migration — `deploy_edge_function`) | `delete-user` and `terminate-employee` replaced with `410 Gone` bodies that log the caller, and flipped to `verify_jwt = true`. Bug `ba6a5b79`. |

**Edge-function kill detail.** `delete-user` accepted **any** valid Supabase-auth session and
would soft-delete the named user *and* delete their Supabase Auth account — no admin check,
no company check. `terminate-employee` verified the caller was an admin of the **posted**
`companyId` but never checked that the *target* belonged to that company, so an admin of one
tenant could strip users in any other. Both ran `verify_jwt = false` with CORS `*`. They were
killed rather than hardened because a fresh grep of `ops-ios`, `ops-web` (including
`supabase/functions/`) and `ops-site` found **zero** invocations — the flows are served today
by the web account-deletion route and web team management. The Supabase management API has no
delete operation for edge functions, so a tombstone is the kill; the last deployed sources are
archived with provenance under `migrations/graveyard/`. Verified live: unauthenticated POST →
`401` (jwt verification now on), POST with a valid anon JWT → `410`.

**Policy-drop note.** The RESTRICTIVE `project table photos update requires project edit`
policy was dropped as part of the photo-grant work. It gated updates on
`private.current_user_can_edit_project()`, which every non-admin crew member fails — verified
against prod, where non-admin users resolve to a NULL `projects.edit` scope — so keeping it
would have made the newly-granted, deliberately company-wide visibility toggle unreachable for
exactly the people meant to use it. Tenancy is still enforced by the PERMISSIVE
`company_isolation` policy (an `ALL` policy with only a `USING` clause applies that expression
as its `WITH CHECK` too, so cross-company updates are rejected on both sides), and the
RESTRICTIVE hard-`DELETE` denial is untouched.

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

The Catalog domain replaces the legacy file-only `Inventory*` models with a fully registered, variant-aware schema. Stockable SKUs (variants) and billable templates (Products) are separate concerns bridged by `ProductMaterial` recipe rows. Catalog entities and Product extension models live in `OPS/DataModels/Supabase/Catalog/` and are registered through `OPSSchemaCommon` version groups.

> **Design intent** for the catalog model and guided onboarding — the durable concept (the four entry kinds, units/dimensions, price-vs-cost, variants, reference-not-duplication, and the onboarding philosophy) independent of any specific flow implementation — lives in `07_SPECIALIZED_FEATURES.md` § 13 → *Design Intent — Catalog Model & Guided Onboarding*. The schema below is the structural realization of that model.

```
catalog_categories (nested via parent_id, 2-level UI)
  └─ catalog_items (variant family)
        ├─ catalog_options (variant axis: "Color", "Mount Type")
        │     └─ catalog_option_values (selectable values)
        ├─ catalog_variants (the SKU — has quantity, threshold, unit)
        │     ├─ catalog_stock_units (physical rolls/offcuts/lots under one SKU)
        │     └─ catalog_variant_option_values (M2M: variant ↔ option_value combo)
        └─ catalog_item_tags ─→ catalog_tags (FAMILY-level free-form labels)

catalog_units (renamed from inventory_units)
catalog_snapshots / catalog_snapshot_items (variant-aware point-in-time)
catalog_orders / catalog_order_items (threshold-driven restock — NEW)
company_default_products (component_type → product_id mapping — NEW)
catalog_product_option_mappings (catalog option axis/value ↔ product option axis/value)
```

**IMPORTANT change from legacy:** tags now apply at the **family** level, not the variant level. A "Corner" family carries tags like `discontinued`; not each variant separately. The legacy threshold columns on `catalog_tags` are preserved in storage but no longer surfaced in the iOS UI — effective-threshold compute now flows variant-override → family-default → category-default.

**Web consumer (2026-06-12, OPS-Web overhaul wave 3.2):** `OPS-Web`'s `/catalog` STOCK segment reads these `catalog_*` tables **directly** — `src/lib/api/services/catalog-stock-service.ts` joins `catalog_variants` → `catalog_items` → `catalog_categories` / `catalog_units` and derives each per-variant option-value label from `catalog_variant_option_values` → `catalog_option_values` → `catalog_options` (ordered by `catalog_options.sort_order`). It does **not** use the legacy `inventory_*` compatibility views (which flatten variant→family and are variant-blind). RLS `company_isolation` on `{public}` lets the Firebase-auth browser client read/write directly. Effective-threshold uses the same variant → family → category cascade; tag thresholds are not consulted, and a variant with no effective threshold at any level renders as `UNTRACKED` (never `OK`). Web quantity edits (inline cell, drawer ±/set, bulk) write an `inventory_deductions` audit row with `reason='manual_adjustment'`, `catalog_variant_id` set, and `deducted_by` UUID-guarded (that column has no FK); the drawer ledger reads both `catalog_variant_id` (web) and legacy `inventory_item_id` (iOS) rows. Manual snapshots write `catalog_snapshots` + `catalog_snapshot_items` (with baked-in `family_name` + `variant_label`) directly — the legacy `inventory_snapshots` view is read-only and would silently fail. Per-product CONFIG counts (options + recipe materials) come from `src/lib/api/services/catalog-product-service.ts` (two grouped reads). The web surface ships no ORDERS affordances (`catalog_orders` / `catalog_order_items` are consumed nowhere in `ops-web`).

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

**iOS stock workflow (updated 2026-05-25)**: `CatalogItem.imageUrl` is the item/family image shown in the stock variant sheet. Uploads use the existing public `product-thumbnails` Storage bucket and the verified `{company_id}/{catalog_item_id}/{uuid}.jpg` object path; the returned public URL is patched to `catalog_items.image_url`. No variant-level image column exists.

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

**Variant identity**: there is no separate `name` column on `catalog_variants`. iOS display names are derived from family name + ordered option values (`CatalogItem.name · CatalogOptionValue.value...`); SKU remains secondary metadata and duplicate-SKU warning input, not the primary distinguishing label.

**Threshold fallback** (canonical): variant override → family default → category default → null. **Quantity policy**: mirrored aggregate. `catalog_variants.quantity` remains the operational value read/written by current iOS stock screens, thresholds, and catalog order fulfillment. `catalog_stock_units` provides physical roll/offcut identity; any stock-unit mutation must mirror the available aggregate back into `catalog_variants.quantity`. For dimensional roll/offcut rows, iOS mirrors area when remaining length and width are both present and share a unit (`sq ft`, `sq in`, etc.); otherwise it mirrors a single length unit when available, then falls back to count. **Indexes**: `(catalog_item_id, deleted_at)`, `(sku) WHERE deleted_at IS NULL`, unique `(company_id, lower(btrim(sku))) WHERE deleted_at IS NULL AND sku IS NOT NULL AND btrim(sku) <> ''`. **RLS**: company_isolation joined via `catalog_items.company_id`.

**Duplicate identity policy (verified 2026-05-21)**: normalized SKUs are hard-unique per company at the database layer. The iOS setup validator treats duplicate SKU as warning-level so the user can correct or intentionally proceed to the DB guard; matrix option signatures are blocking in iOS before commit. Matrix signatures are not yet DB-unique: live data has an active Diverter family with two variants sharing the same option-value signature, so a DB constraint would require a separate approved cleanup first.

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

### CatalogStockUnit

**File**: `DataModels/Supabase/Catalog/CatalogStockUnit.swift`
**Purpose**: Physical unit under one `CatalogVariant`. Used for roll/offcut/lotted inventory where variant-level `quantity` is too coarse to track actual usable material.

```swift
@Model
final class CatalogStockUnit: Identifiable {
    @Attribute(.unique) var id: String
    var companyId: String
    var catalogVariantId: String
    var unitKind: CatalogStockUnitKind       // roll / offcut / box / each / lot / pallet / length
    var label: String?
    var lotCode: String?
    var widthValue: Double?
    var widthUnit: String?
    var originalLengthValue: Double?
    var remainingLengthValue: Double?
    var lengthUnit: String?
    var quantityValue: Double
    var location: String?
    var status: CatalogStockUnitStatus       // full / partial / reserved / consumed / scrapped
    var sourceOrderItemId: String?
    var notes: String?

    var lastSyncedAt: Date?
    var needsSync: Bool = false
    var deletedAt: Date?
}
```

Only `full` and `partial` units contribute to available-unit aggregation. Roll/offcut units aggregate to area when `remainingLengthValue`, `widthValue`, `lengthUnit`, and `widthUnit` form one dimensional unit system; the mirrored label must show that basis (for example, `504 sq ft`). If area cannot be computed, length rollups are grouped by `lengthUnit`; if that also cannot produce a single scalar, `quantityValue` is the fallback. SQL migration: `migrations/2026-05-21-04-catalog-stock-units.sql`. RLS: company_isolation. Indexes: `(company_id, updated_at)`, `(catalog_variant_id)`, `(company_id, status)` for active rows.

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

**iOS stock workflow (updated 2026-05-25)**: family tags can be assigned when creating a stock family and edited from the variant sheet. The write path deletes and reinserts `catalog_item_tags` for one `catalog_item_id`; RLS is enforced through the joined `catalog_items.company_id` policy.

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

Phase 2 OPS Decks framing adds additive `components[]` rows with structural strings (`joist`, `beam`, `post`, `rim_joist`, `blocking`), but this enum-backed default-product model still represents the original configured product vocabulary until the adapter/web configuration surface is extended. Unknown or unmapped structural rows must be skipped, not treated as decode failures.

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

**`CatalogProductOptionMapping`** — explicit bridge between stock identity axes and sellable product options.

```swift
enum CatalogProductOptionMappingKind: String, CaseIterable, Codable {
    case axis
    case value
}

@Model
final class CatalogProductOptionMapping: Identifiable {
    @Attribute(.unique) var id: String
    var companyId: String
    var productId: String
    var catalogItemId: String
    var catalogOptionId: String
    var productOptionId: String
    var catalogOptionValueId: String?
    var productOptionValueId: String?
    var mappingKind: CatalogProductOptionMappingKind

    var lastSyncedAt: Date?
    var needsSync: Bool = false
    var deletedAt: Date?
}
```

`axis` rows link one `catalog_options` axis to one `product_options` knob; both value IDs must be null. `value` rows link one `catalog_option_values` row to one `product_option_values` row under the already-linked axes; both value IDs must be present and belong to their parent options. Unique partial indexes prevent duplicate active axis/value mappings, and migration `migrations/2026-05-21-06-catalog-product-option-mapping-fk-indexes.sql` adds leading-column partial FK indexes for the four option/value references flagged by the Supabase advisor. SQL migration: `migrations/2026-05-21-05-catalog-setup-relationships.sql`. RLS: company_isolation.

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
- Non-empty `sku` cannot collide with an existing active variant in the company. The RPC catches this before insert; the live database also has the normalized per-company SKU uniqueness guard.

**Atomicity**: both functions return normally on validation failure (returning the failure object), so the implicit transaction does NOT commit when a failure path is taken. The `apply` function's INSERT statements run only inside the success path; any error during INSERT raises and rolls back the transaction. The client never sees partial state.

**No update path**: import is INSERT-only. Re-importing the same CSV creates duplicate families. Use Snapshots (kebab Setup → Snapshots) to roll back a bad import.

### Catalog Bulk Variant Expansion (prepared 2026-08-07; web production 2026-08-16)

`public.catalog_bulk_expand_variants(p_company_id uuid, p_idempotency_key text, p_payload jsonb) RETURNS jsonb` is the mutation boundary for adding one variant axis across as many as 200 existing stock families in one operation. The behavioral source lives at `ops-ios/OPS/Migrations/2026-08-07-catalog-bulk-variant-expansion.sql` plus `CatalogBulkVariantExpansionPlanner` / `CatalogBulkVariantExpansionService`. The web-compatible migration lives at `ops-web/supabase/migrations/20260812150000_catalog_bulk_variant_expansion.sql`; its browser client builds the same canonical family snapshot in `src/lib/catalog/bulk-variant-expansion.ts` and calls the RPC through `CatalogBulkVariantService`.

The companion `catalog_bulk_variant_requests` table stores `company_id`, the client-generated idempotency key, the exact request payload, and the successful response. `(company_id, idempotency_key)` is unique. RLS permits `authenticated` and Firebase-bridge `anon` callers with `catalog.manage:all` to select and insert receipts only for their own active company. The RPC is `SECURITY INVOKER`, pins its search path, repeats the active-company and granular-permission checks through `private.get_user_company_id()` / `private.current_user_has_permission(...)`, and grants execution only to `anon, authenticated`. It never infers authority from an app role or employee type.

**Deployment status (2026-08-16):** migration `20260812150000_catalog_bulk_variant_expansion.sql` is applied and recorded in the live Supabase project. Independent readback confirmed the receipt table, `SECURITY INVOKER` RPC, two normalized uniqueness indexes, RLS policies, and the intended `anon` / `authenticated` grants. The production RPC rejected an unauthenticated probe with `company_forbidden`, and the receipt table remained empty; no customer catalog mutation was used for release verification. OPS-Web `main` commit `a955a973` is deployed through Vercel at `https://app.opsapp.co`.

**Payload contract**:

```json
{
  "axis_name": "Top profile",
  "existing_value": "Round top",
  "new_values": ["Flat top"],
  "families": [
    {
      "family_id": "uuid",
      "source_fingerprint": "64-character lowercase SHA-256",
      "source": {"id": "uuid", "name": "...", "options": [], "variants": []}
    }
  ]
}
```

The embedded `source` is a canonical snapshot of the family name, active options and values, active variants, every safe-to-copy variant field, and ordered option-value IDs. Before the first write, Postgres locks the selected families and active variants in deterministic UUID order, rebuilds the same snapshot from current rows, and compares it to the client payload exactly. Any difference returns `stale_catalog`; the operator must review the refreshed catalog. The SHA-256 fingerprint is the client's stable draft/review identity, while the full JSON comparison is the server's stale-write guard.

**Expansion rules**:

- When the axis does not exist on a family, the RPC creates it, creates the existing/source value, and attaches that value to every active source variant without changing those variants' IDs.
- When the axis already exists, it must contain exactly one normalized match for the existing/source value. Only variants pinned to that value are expansion sources.
- For each new value, the RPC clones every source combination across the family's other axes. Existing combinations are skipped, so retrying cannot create duplicate matrix rows.
- A clone starts with `quantity = 0` and `sku = null`. It copies price override, unit-cost override, warning and critical thresholds, unit, and active status from its source variant.
- Existing variants retain their IDs, quantities, SKUs, settings, and joins. `catalog_stock_units`, inventory deductions, snapshots, orders, and all other stock/history rows are never copied or reassigned.
- Families with incomplete option assignments, duplicated normalized option names/values, duplicate matrix signatures, missing source values, or stale source snapshots fail preflight before any mutation.

**Atomicity and replay**: validation for every family completes before the mutation phase. Any raised database error rolls back the whole call, so no family can land partially. A successful request and response are written in the same transaction. Repeating the same company/key/payload returns the stored result with `replayed = true`; reusing the key for a different payload returns `idempotency_conflict`. The iOS client syncs the returned rows into SwiftData immediately and treats a successful server response as authoritative even if local reconciliation needs a follow-up refresh. OPS-Web never automatically retries the ambiguous mutation: an operator retry reuses the same durable key, and success does not resolve until the active `catalog.stock(companyId)` and `catalog.bulkVariantFamilies(companyId)` TanStack queries have both refetched.

This RPC is intentionally an **existing-catalog dimensional expansion**, not a general import or arbitrary bulk editor. `catalog_import_apply` remains INSERT-only catalog creation from CSV; interactive `Add Variant` remains the path for a one-off SKU.

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

### Supabase row

Live schema verified 2026-05-12 in project `ijeekuhbatykdomumfjx`: `deck_designs.id`, `company_id`, `project_id`, and `created_by` are PostgreSQL `uuid` columns; `project_id` and `created_by` are nullable. iOS canonicalizes UUID strings to lowercase before queueing sync payloads so local SwiftData ids match the lowercase UUID strings returned by Postgres. Project-create capture starts with `projectId == nil`; once the project id exists, iOS records a deck-design create/upsert or update sync operation carrying the real `project_id` so the drawing does not remain a standalone sketch in Supabase. Inbound sync must also merge `project_id` onto existing local `DeckDesign` rows; otherwise devices that already cached a standalone row will continue showing it outside the project even after Supabase has the corrected association. The project Deck tab performs a targeted `fetchForProject` self-heal when no local design is attached, then inserts/merges the returned rows into SwiftData so repaired server associations appear without waiting for an app-wide sync.

Live data verified 2026-05-20 in project `ijeekuhbatykdomumfjx`: active `deck_designs` rows exist for project-attached designs, and some legacy `drawing_data` payloads omit the top-level `surfaces` key while still carrying valid vertices, edges, footprint, config, levels, and level connections. Active rows also store `drawing_data.footprint.isClosed` as numeric `0`/`1`, not strict JSON booleans. Inbound iOS decoders must treat missing optional/defaulted `DeckDrawingData` fields as empty/default values and tolerate legacy numeric/string/strict boolean values for deck drawing booleans. A single legacy row must not cause the full `[SupabaseDeckDesignDTO]` pull to fail, because a fresh install depends on that inbound pass to repopulate deck designs.

Embedded iOS designer exit-save contract added 2026-07-03: the project DeckBuilder calls `flushBeforeExit()` when the operator closes the designer, when the view disappears, and when the app moves inactive/background. That path persists the current `DeckDrawingData` into SwiftData, queues the `deck_designs` sync operation, and triggers the sync engine immediately. The 2-minute autosave timer is crash-recovery only; it is not the primary save-on-exit mechanism.

Phase 1 standalone OPS Decks contract added 2026-06-26: standalone sketches reuse `deck_designs` with `company_id` scoped to the provisioned deck-only company and `project_id = nil`. The OPS Decks app must not create a project shell just to save a deck. If the operator later upgrades into full OPS and creates a project, the existing repair path attaches `project_id` to the saved `DeckDesign` row. `drawing_data` remains additive and backward-decodable; future framing, parcel/zoning, code overlay, rendering, roofing, wall/opening, railing, stair, and material blocks must round-trip even before those systems are active.

Lead attachment added 2026-07-14 (migration `add_deck_designs_opportunity_id`): `deck_designs.opportunity_id uuid NULL REFERENCES opportunities(id)` + partial index on non-null values. A deck drawn on a LEAD — the lead detail's START DECK DESIGN entry (`OPS/Views/Leads/Components/LeadDeckSection.swift` → `CreationPickerView(opportunityId:)`) or a site-visit sketch for a bound lead (`SiteVisitCaptureView.startDeckDesign`) — carries `opportunity_id`. iOS ships the link on deck create/update sync ops under the same non-nil-only rule as `project_id` (an explicit null from a stale device must never unlink), merges it inbound via `DeckDesign.serverMergeFields`, and the lead detail performs the same targeted `fetchForOpportunity` self-heal the project Deck tab does. At conversion, `convert_opportunity_to_project` re-parents unparented lead decks (`project_id IS NULL`) onto the project and KEEPS `opportunity_id` as provenance — the lead keeps showing its deck after WON, and the iOS site-visit handoff's client-side `project_id` stamp remains as an idempotent second writer. OPS-Web gained a **read-only lead surface** the same day: the pipeline detail's OVERVIEW tab renders a state-aware `// DECK DESIGN` section between Location and Linked (nothing renders when the lead has no deck) via `DeckDesignService.fetchForOpportunity` (`deck-design-service.ts` — selects card columns plus `drawing_data->vertices`/`->edges` JSON paths only, never the full blob; RLS `company_isolation` scopes the read). Each row opens a view-only portaled viewer (`deck-design-viewer.tsx`): raster `thumbnail_url` when present, else a hairline SVG wireframe built from vertices/edges (`src/lib/utils/deck-wireframe.ts` — legacy-tolerant: malformed geometry degrades to `null`/icon, never throws, matching the inbound-decode doctrine above). Decks are still authored exclusively on iOS; the web neither creates nor edits `deck_designs`.

Lead/project deck viewer invalidation contract added 2026-08-19 (`ops-ios`
commits `968a0d06` and `2c30a8c9`): `DeckTabView` owns one owner-scoped local
fetch and receives SwiftData save identifiers. Local main-context saves are
filtered by their context; background `DataActor` consumers observe
`dataActorMainContextDidRefresh`, which `MainContextRefreshBridge` posts only
after the iOS 17.6–25 inserted-identifier visibility workaround has completed.
The view re-evaluates any `DeckDesign` insert or update because an existing
design can be reassigned into or away from the visible owner, but it writes
state only when the selected persistent identity changes. A current-model
delete clears the selection directly. Fetch handling never dereferences a save
identifier with `ModelContext.model(for:)`, because an insert/delete batch can
invalidate that fault before the main-queue notification is delivered.
`LeadDeckScreen` receives the resolved model from `DeckTabView` for fullscreen
instead of mounting a second query. This boundary prevents company-wide
`DeckDesign` Realtime traffic from repeatedly rebuilding the lead deck SwiftUI
graph on the main thread while preserving creation, reassignment, update, and
deletion correctness.

Visit continuation invariant (2026-07-14, same day): the site visit's DECK action CONTINUES an existing design instead of forking — `SiteVisitDeckDesignResolver` opens the visit's own newest active deck-artifact design first, then the lead's display candidate (identical selection rule to the lead page, so both surfaces always open the SAME record), and only creates a fresh canvas when neither exists. `SiteVisitCaptureViewModel.attachDeckDesign` is idempotent per design id (reopening never stacks duplicate DECK artifacts or double-hands the design to conversion). Pre-fix behavior forked a new design on every tap — including the checklist row's EDIT button, which silently re-linked the answer to the new copy.

OPS Decks zoning parcel lookup contract added 2026-07-02: `public.deck_zoning_parcel_records` is a service-role-only verified cache for `POST /api/decks/zoning/parcel`. Rows are keyed by `normalized_site_address`, optional `jurisdiction_id`, optional `company_id`, and `deleted_at IS NULL`; `parcel_zoning` stores DeckKit `ParcelZoningPlan` JSON exactly as the standalone app decodes it. The route may return only verified `available`, `partial`, or `userEntered` plans. It must not infer setbacks, lot coverage, height limits, or code criteria from an address. Missing records return 404 so OPS Decks can switch to manual criteria entry without fabricating zoning data. OPS-Web admins populate the cache through `POST /api/admin/decks/zoning/parcel-records/import`, which supports dry-run validation, rejects mixed valid/invalid batches before writing, and idempotently updates active key matches before inserting new rows.

Phase 2 OPS Decks framing contract added 2026-06-26: `drawing_data.framing` is active and rows with a generated frame stamp schema version 2. `drawing_data.terrain` is active for the ground-cover subset only. Framing is a plausible visualization/scoping model, not an engineered sizing/code result; `FramingMember.sizing` stays nil until the sizing/code phase writes `MemberSizingResult`. Runtime capability split is intentional: embedded OPS uses `DeckCapabilities.light` and must not author framing or ground-cover data; standalone OPS Decks uses `DeckCapabilities.full` for the full authoring surface. Data preservation is independent from capabilities.

Embedded OPS framing read/render contract updated 2026-07-17: `DeckDrawingData.framing` is a typed, read-only projection of the shared `FramingPlan`; embedded OPS exposes no framing mutation or sizing API. During decode, `DeckDrawingData` also retains the original `drawing_data.framing` subtree as `DeckJSONValue` and restores it unchanged on encode/save. This preserves unknown plan, member-set, and member fields, future enum values, malformed members, and exact JSON number spellings even when the typed projection uses defaults or skips an unrenderable member. Unknown top-level drawing blocks are likewise retained in `futureBlocks`. Missing or empty legacy member ids receive deterministic content-derived ids for stable display identity; those ids do not alter the preserved raw payload.

Display completion is separate from persistence. `DeckFramingPreviewPlanner` creates deterministic in-memory member sets only when the entire framing block is absent or a persisted plan lacks a level set. Every persisted `FramingMemberSet` is authoritative, including `members: []`, which explicitly means no structure on that level. Transient sets are never saved, synced, sized, or emitted as authored framing.

Phase 6 OPS Decks surface/overhead contract added 2026-06-30: `drawing_data.surfaceFeatures` and `drawing_data.overhead` are active optional blocks and rows carrying either block stamp schema version 6. `surfaceFeatures` stores per-surface decking patterns, fastener system, finishes, fascia, skirting, built-ins, and lighting. `overhead` stores pergola/louvered/solid-roof structures with optional roof shape, footprint, shared framing members, shade percent, and product model. These blocks are FULL-authoring data owned by standalone OPS Decks; embedded OPS light mode must preserve and display them without exposing the authoring sheets or invoking sizing engines.

Deck materials list contract added 2026-07-06 (embedded OPS): `drawing_data` gains two additive optional keys for the deck-tab vinyl materials list — `materialsSettings` (`DeckMaterialsSettings`: crew-editable `glueCoverageSqFt`/`dripStickFeet`/`ninetyStickFeet`/`clipStickFeet` presets) and `orderedMaterials` (`DeckMaterialsSnapshot`: the full materials list frozen at MARK ORDERED — presets, vinyl settings, color, ordered/surface sq ft, purchased cut groups, drip/clip/90 feet + stick counts, glue area + buckets). Both decode with the DeckGeometry house style (`decodeIfPresent` per field); a corrupt `orderedMaterials` (e.g. missing `orderedAt`) nils the whole node rather than failing the drawing decode. Legacy rows omit both keys and round-trip unchanged. No DB migration — `deck_designs.drawing_data` is `jsonb` and the keys ride inside it. **Extended 2026-07-07** (editable ordered record + full-roll ordering): `DeckMaterialsSettings` gains `orderMode` (`VinylOrderMode`) + `fullRollLengthFeet`; `DeckMaterialsSnapshot` gains `orderMode`, `fullRollLengthFeet`, `orderedRollCount` (`Int?`), `isOrderedEdited`, and `driftCutGroups` (ALL cut pieces — purchased + intra-job reused — the drift basis; `cutGroups` stays purchased-only for display) — all additive, `decodeIfPresent` with calc-fallback defaults (`driftCutGroups` falls back to `cutGroups`) so pre-existing rows round-trip byte-behavior-unchanged. **Extended 2026-07-16** (VINYL ORDERS board): `DeckMaterialsSnapshot` gains `po` (`String?`) — the supplier PO confirmed in the bulk order wizard; nil for single-project orders and legacy snapshots (additive, `decodeIfPresent`). See `07_SPECIALIZED_FEATURES.md` § Deck Materials List for the detection/flashing/snapshot semantics and § VINYL ORDERS Board for the bulk flow.

Standalone company provisioning is defined in `ops-ios/docs/superpowers/specs/2026-06-25-ops-decks-phase-1-backend-contract.md`. The provisioning endpoint creates a company-of-one for the deck-only user and may mark the row with a clear deck origin or `subscription_plan = 'decks'` for routing, but deck entitlement state belongs in the deck subscription mirror. Do not write RevenueCat deck access into `companies.subscription_status`, `trial_end_date`, or other OPS base-plan lockout fields.

### `drawingDataJSON` schema

`drawingDataJSON` is the serialized form of `DeckDrawingData`. The catalog-relevant subset is:

```jsonc
{
  "vertices":         [ ... ],
  "edges":            [ ... ],
  "footprint":        { ... },
  "surfaces":         [ ... ],
  "config":           {
    // Optional Deck Builder vinyl default. When present, this is the
    // active `catalog_items.id` used by Vinyl Order; the order sheet still
    // requires the user to pick an active variant/color before it writes a
    // `catalog_order_items` row. Missing/null means use field text color.
    "vinylCatalogItemId": "<catalog_items.id> | null"
  },
  "scaleFactor":      <Double>,
  // Single-level uniform height (feet). On multi-level drawings this field is
  // legacy-only: heights live on each level's `elevation`, written by the
  // level-scoped Height tool (2026-07-21); `overallElevation` survives purely
  // as the stagger base for old multi-level saves that predate per-level
  // heights. See 07_SPECIALIZED_FEATURES.md § Deck Builder Stairs & Level
  // Heights for the render resolution ladder.
  "overallElevation": <Double>,
  "levels":           [ ... ],          // multi-level only; each carries its own `elevation`
  // Multi-level only. A connection's stairConfig.totalRiseInches stays null —
  // its rise derives from the two levels' resolved heights and re-syncs when
  // either height changes. An edge carries EITHER a stairConfig OR a
  // connection, never both (enforced by DeckBuilderViewModel).
  "levelConnections": [ ... ],

  // PHASE 2 FRAMING - optional, additive, schema version 2 when present.
  // `sizing` is reserved and remains null/nil until the sizing/code engine.
  // Embedded OPS reads a typed projection but preserves this raw subtree verbatim.
  // A present per-level set, including `members: []`, is authoritative; transient
  // display sets for absent levels are never written into `drawing_data`.
  "framing": {
    "members": [
      {
        "levelId": "<level id or empty string>",
        "members": [
          {
            "id": "<uuid>",
            "role": "joist | beam | post | ledger | rimBand | blocking | bridging | cantilever",
            "start": [0, 0],
            "end": [0, 144],
            "nominalSize": "2x6 | 2x8 | 2x10 | 2x12 | 4x4 | 4x6 | 6x6 | null",
            "plyCount": 1,
            "spacingInchesOC": 16,
            "species": "southern_pine | df_l | hem_fir | spf | redwood_cedar | null",
            "grade": "select_structural | no1 | no2 | null",
            "sizing": null,
            "locked": false
          }
        ]
      }
    ],
    "loadPreset": {
      "liveLoadPSF": 40,
      "deadLoadPSF": 10,
      "snowLoadPSF": null,
      "species": "spf",
      "grade": "no2"
    },
    "generationSource": "auto | manual | autoThenEdited",
    "generatedAtSchemaVersion": 2
  },

  // PHASE 2 TERRAIN - ground-cover only. Grade points/slope are for the
  // later footing/grade phase and are not interpreted by Phase 2 framing.
  "terrain": {
    "gradePoints": [],
    "groundCover": [
      {
        "id": "<uuid>",
        "polygon": [[0, 0], [144, 0], [144, 144], [0, 144]],
        "cover": "grass | dirt | gravel | rock | concrete | pavers"
      }
    ],
    "slopeSource": "manual"
  },

  // PHASE 6 SURFACE FEATURES - optional, additive, schema version 6 when present.
  "surfaceFeatures": {
    "patterns": [
      {
        "surfaceId": "<detected/persisted surface id>",
        "pattern": "parallel | diagonal | picture_frame | herringbone | chevron",
        "boardAngleDegrees": 0,
        "pictureFrameCourses": 1
      }
    ],
    "fastenerSystem": "hidden_clip | face_screw | null",
    "finishes": [
      { "kind": "cut-end seal", "coats": 2 }
    ],
    "fascia": true,
    "skirting": {
      "material": "ventilated lattice",
      "ventilated": true
    },
    "builtIns": [
      {
        "id": "<uuid>",
        "kind": "bench | planter | privacyWall",
        "polygon": [[0, 0], [144, 0], [144, 24], [0, 24]],
        "heightInches": 18
      }
    ],
    "lighting": {
      "fixtures": [[0, 0], [144, 0]],
      "transformerWatts": 60,
      "receptacles": []
    }
  },

  // PHASE 6 OVERHEAD - optional, additive, schema version 6 when present.
  "overhead": {
    "structures": [
      {
        "id": "<uuid>",
        "kind": "pergola | louvered_roof | solid_roof",
        "roofShape": "shed | gable | hip | null",
        "footprint": [[0, 0], [144, 0], [144, 120], [0, 120]],
        "framing": [
          {
            "id": "<uuid>",
            "role": "beam | joist | post",
            "start": [0, 0],
            "end": [144, 0],
            "nominalSize": "2x10",
            "plyCount": 1,
            "spacingInchesOC": null,
            "species": "spf",
            "grade": "no2",
            "sizing": null,
            "locked": false
          }
        ],
        "shadePercent": 40,
        "productModel": null
      }
    ]
  },

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
    { "component_type": "gate",      "metadata": { ... } },
    { "component_type": "joist",     "metadata": { ... } },
    { "component_type": "beam",      "metadata": { ... } },
    { "component_type": "post",      "metadata": { ... } },
    { "component_type": "rim_joist", "metadata": { ... } },
    { "component_type": "blocking",  "metadata": { ... } }
  ]
}
```

### `components[]` projection — per-type metadata schema

The original catalog component rows match `DesignComponentType` raw values exactly. Phase 2 framing adds structural component rows as additive strings; they must round-trip and may be mapped by future product-default surfaces, but the current enum-backed adapter skips unknown strings before default lookup. Adding new `component_type` strings is fine; renaming existing strings is a contract break with `DesignToEstimateAdapter`. For mapped rows, metadata keys map 1:1 to the keys the adapter reads via `option_default_source = "$design.<key>"` and via `computeQuantity(unit:metadata:)`.

| `component_type` | Source in geometry | Required metadata keys |
|---|---|---|
| `railing` | One per deck-edge `DeckEdge` with `railingConfig`; house edges never emit railing | `linear_feet` (Double, edge length minus stair span minus all gate widths), `corners_count` (Int — currently always 0; corners live at vertex boundaries, not inside edges, so per-edge attribution would double-count), `color` (String, `RailingConfig.color`), `mount_type` (String, `RailingConfig.mountType`), `mount_surface` (String, `RailingConfig.mountSurface`), `edge_id` (String), optional `level_id` (String), optional `wall_material` (String, only for `parapet_wall`) |
| `post_set` | One per post-supported railing; not emitted for `parapet_wall` | `count` (Int, `DimensionEngine.postCount`), `height` (Double inches, `RailingConfig.postHeight`), `color` (mirrors railing), `mount_type` (mirrors railing), `edge_id`, optional `level_id` |
| `stair_set` | One per `DeckEdge` with `stairConfig`, plus one per `LevelConnection` (multi-level) | `tread_count` (Int, `StairConfig.calculateTreadCount` or override), `width` (Double inches, `StairConfig.width`), `color` (String, `StairConfig.color`), `mount_type` (String — vocabulary `Surface | Top | Side`, distinct from railing), `edge_id` OR `connection_id` + `level_id` (upper level) |
| `deck_board` | One per `DeckSurface` with a detected face match (per-face area), or one per legacy footprint when surfaces empty | `sqft` (Double, `PolygonMath.realWorldArea(face) / 144.0`), `color` (String, `DeckSurface.color`), `material` (String, `DeckSurface.boardMaterial`), `surface_id` (String — the persisted DeckSurface id, or sentinel `"footprint"` for the legacy fallback), optional `level_id` |
| `gate` | One per `isGate=true` AssignedItem on an edge | `count` (Int — 1 per row), `width` (Double inches — default 36), `color` / `mount_type` / `mount_surface` (mirror parent railing or fall back to defaults Black / Topmount / Surface), `edge_id`, optional `level_id` |
| `joist` | One per `FramingMember` with role `.joist` | `linear_feet` (Double), `nominal_size` (String or null), `ply_count` (Int), `count` (Int, always 1 per row), `species` (String or null), `grade` (String or null), `level_id` (String), `member_id` (String) |
| `beam` | One per `FramingMember` with role `.beam` | `linear_feet`, `nominal_size`, `ply_count`, `count`, `species`, `grade`, `level_id`, `member_id` |
| `post` | One per `FramingMember` with role `.post`; length represents modeled post height | `linear_feet`, `nominal_size`, `ply_count`, `count`, `species`, `grade`, `level_id`, `member_id` |
| `rim_joist` | One per `FramingMember` with role `.rimBand` | `linear_feet`, `nominal_size`, `ply_count`, `count`, `species`, `grade`, `level_id`, `member_id` |
| `blocking` | One per `FramingMember` with role `.blocking` | `linear_feet`, `nominal_size`, `ply_count`, `count`, `species`, `grade`, `level_id`, `member_id` |

Framing roles `.ledger`, `.bridging`, and `.cantilever` are valid in `FramingPlan` but intentionally do not emit structural `components[]` rows in Phase 2.

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
var wallMaterial: HouseEdgeMaterial = .parapet // parapet wall finish

// StairConfig (additions)
var color: String = "Black"
var mountType: String = "Surface"       // Surface | Top | Side

// DeckSurface (additions)
var color: String = "Brown"
var boardMaterial: String = "composite" // composite | pvc | cedar | treated | other

// AssignedItem (additions)
var isGate: Bool = false                // drives gate component emission
```

### Canonical deck-surface topology (schema 10 — added 2026-07-25)

`DeckSurface.boundary` is the canonical persisted region definition for each
closed deck face. It stores one directed `outerLoop` and zero or more directed
`holeLoops`; every loop entry is a `DeckBoundaryEdgeReference` containing the
persisted `edgeId`, `startVertexId`, and `endVertexId`. An edge shared by two
surfaces is referenced in opposite directions, so one seam remains one graph
edge while both adjacent regions retain their own winding. `vertexIds` remains
as a compatibility projection for pre-schema-10 rows.

`DeckSchemaMigration` canonicalizes legacy surface membership against the edge
graph and stamps `schemaVersion = 10`. Invalid topology is rejected rather than
silently flattened: loops must close, references must resolve to matching edge
endpoints, no edge may belong to more than two surfaces, and a shared edge must
have opposite direction in its two regions. Sources:
`Packages/DeckKit/Sources/DeckKit/Models/DeckGeometry.swift`,
`Models/DeckSchemaMigration.swift`, and
`Engine/DeckSurfaceTopologyEngine.swift` in `ops-decks-ios`.

`DeckEdge.edgeType` is mutually exclusive with the edge-side finish model: `house_edge` carries `houseEdgeMaterial` and no `railingConfig`; `deck_edge` may carry `railingConfig` and clears `houseEdgeMaterial`. Decoders and AR import sanitize legacy payloads that contain both.

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

### `company_inventory_settings` (Phase 6 draft)

**Purpose**: Explicit company inventory mode for estimate-to-job material behavior. This is the only source of truth for whether accepted estimates create projected material demand.
**SwiftData**: not yet registered locally.
**Schema**:

```sql
company_inventory_settings
  company_id      uuid PK FK companies(id)
  inventory_mode  text NOT NULL DEFAULT 'off'      -- 'off' | 'tracked'
  enabled_at      timestamptz NULL
  disabled_at     timestamptz NULL
  updated_by      uuid FK users(id) NULL
  created_at      timestamptz NOT NULL
  updated_at      timestamptz NOT NULL
```

**RLS**: company isolation on `company_id`. Writes require `catalog.manage` and the `public.set_company_inventory_mode(p_company_id, p_inventory_mode)` RPC boundary so the actor is derived server-side and open projected demand is released when tracking is turned off.

### `project_material_demands` (Phase 6 draft)

**Purpose**: Accepted-job material demand. These rows are projected planning pressure, not stock movement.
**SwiftData**: not yet registered locally.
**Schema highlights**:

```sql
project_material_demands
  id                            uuid PK
  company_id                    uuid FK companies(id)
  project_id                    uuid FK projects(id)
  task_id                       uuid FK project_tasks(id) NULL
  estimate_id                   uuid FK estimates(id) NULL
  line_item_id                  uuid FK line_items(id) NULL
  product_id                    uuid FK products(id) NULL
  product_material_id           uuid FK product_materials(id) NULL
  catalog_variant_id            uuid FK catalog_variants(id) NULL
  unit_id                       uuid FK catalog_units(id) NULL
  demand_key                    text NOT NULL
  source                        text NOT NULL DEFAULT 'estimate_acceptance'
  status                        text NOT NULL DEFAULT 'projected'
  required_quantity             numeric NOT NULL
  available_quantity_at_booking numeric NULL
  projected_overrun_quantity    numeric NOT NULL DEFAULT 0
  resolver_payload              jsonb NOT NULL DEFAULT '{}'
  warning_payload               jsonb NOT NULL DEFAULT '{}'
  deleted_at                    timestamptz NULL
```

**RLS and guards**: company isolation plus same-company guards for project, task, estimate, line item, product, recipe, variant, and unit references. Writes require the `ops.project_material_workflow` guard and either inventory-mode release through `public.set_company_inventory_mode` with `catalog.manage`, or estimate acceptance through `public.accept_estimate_to_job` with same-company and acceptance-adjacent permission checks. Direct ad hoc writes remain blocked. Valid statuses are `projected`, `warning`, `allocated`, `consumed`, `released`, and `superseded`.

### `project_material_snapshots` and `project_material_snapshot_items` (Phase 6 draft)

**Purpose**: Immutable material history for booking projection, inventory-mode release, crew adjustment, task-completion consumption, and release events.
**SwiftData**: not yet registered locally.

Snapshot item rows include `stock_unit_snapshot jsonb NOT NULL DEFAULT '{}'`. This JSON captures the stock-unit label, lot, dimensions, remaining quantity, location, status, and related source event data at snapshot time. It is historical evidence; it is never recomputed from the mutable `catalog_stock_units` row.

**RLS and guards**: headers are company-isolated by `company_id`; items must match the snapshot company and every referenced demand, task material, allocation, deduction, variant, stock unit, stock event, and unit must belong to that same company.

### `task_material_allocations` (Phase 6 draft)

**Purpose**: Link projected demand and task cut-list rows to physical stock units without deducting stock until task completion.
**SwiftData**: not yet registered locally.
**Schema highlights**:

```sql
task_material_allocations
  id                       uuid PK
  company_id               uuid FK companies(id)
  task_material_id          uuid FK task_materials(id) NULL
  demand_id                 uuid FK project_material_demands(id) NULL
  catalog_variant_id        uuid FK catalog_variants(id) NULL
  catalog_stock_unit_id     uuid FK catalog_stock_units(id) NULL
  inventory_deduction_id    uuid FK inventory_deductions(id) NULL
  allocation_key            text NOT NULL
  allocation_status         text NOT NULL DEFAULT 'projected'
  allocated_quantity        numeric NOT NULL DEFAULT 0
  consumed_quantity         numeric NOT NULL DEFAULT 0
  overrun_quantity          numeric NOT NULL DEFAULT 0
  stock_unit_snapshot       jsonb NOT NULL DEFAULT '{}'
  deleted_at                timestamptz NULL
```

**RLS and guards**: company isolation plus same-company checks for task material, demand, variant, stock unit, and deduction. `projected` and `overrun` allocations do not write `inventory_deductions` or `catalog_stock_unit_events`; `consumed` allocations are tied to the task-completion stock movement.

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
  company_id          uuid FK companies(id) NOT NULL
  inventory_item_id   uuid NULL                              -- legacy column name
  catalog_variant_id  uuid FK catalog_variants(id) NULL
  project_id          uuid FK projects(id) NULL
  task_id             uuid FK project_tasks(id) NULL
  line_item_id        uuid FK line_items(id) NULL
  quantity_deducted   double precision NOT NULL
  previous_quantity   double precision NOT NULL
  new_quantity        double precision NOT NULL
  reason              text NOT NULL DEFAULT 'task_completion'
  deducted_by         uuid FK users(id) NULL
  deducted_at         timestamptz NOT NULL
  notes               text
```

**RLS**: company isolation by `company_id` with same-company expectations for variant/task/project references. Phase 6 projected material demand does not write this table; it is reserved for actual stock movement such as task completion consumption, returns, manual adjustments, and snapshots.

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
  component_type  text NOT NULL                  -- enum-backed defaults: 'railing' | 'deck_board' | 'stair_set' | 'gate' | 'post_set'
  product_id      uuid FK products(id) NOT NULL
  created_at      timestamptz NOT NULL
  updated_at      timestamptz NOT NULL
  PRIMARY KEY (company_id, component_type)
```

**RLS**: company_isolation. Only one default per (company, component_type). Missing mapping → adapter logs to `app_events.adapter_skip_component` and continues.

Phase 2 deck framing can emit additive `components[]` rows for `joist`, `beam`, `post`, `rim_joist`, and `blocking`, but this table's iOS SwiftData enum and configuration UI still cover only the original defaults until the catalog adapter is extended. Treat unmapped structural rows as skip-safe projection data.

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
- **SiteVisitStatus**: `scheduled`, `inProgress` (`in_progress`), `completed`, `cancelled`
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

iOS inbound sync must merge active and inactive `products` before `product_options`, `product_option_values`, and `catalog_product_option_mappings`; Catalog Setup `LINKS` reads its picker from local `Product` rows, so option sync without product hydration leaves the picker empty.

| DTO | Purpose |
|-----|---------|
| `ProductDTO` | Read with all 18 fields including `kind`, `pricingUnit`, `sku`, `isFavorite`, `minimumCharge`, `minimumQuantity`, `showBomOnEstimate`, `showInStorefront`, `tieredPricing`, `unitId`. `toModel() -> Product` |
| `CreateProductDTO` | Create — `companyId`, `name`, `basePrice`, `pricingUnit`, etc. |
| `UpdateProductDTO` | Partial update — supports the same fields plus `isActive`, `isFavorite` |
| `RawJSONColumn` | Type-erased jsonb passthrough used by `tieredPricing` |

### CatalogDTOs.swift

DTOs for the catalog tables and the variant ↔ option-value join. All include snake_case `CodingKeys` for Supabase column mapping.

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
| `CatalogStockUnitDTO` / `CreateCatalogStockUnitDTO` / `UpdateCatalogStockUnitDTO` | `catalog_stock_units` (physical rolls/offcuts/lots under variants; gated by `CatalogSchemaCapabilityGate`) |

### ProductExtensionDTOs.swift

DTOs for the four Product-extension tables that drive Configurable Products.

| DTO | Purpose |
|-----|---------|
| `ProductOptionDTO` / `CreateProductOptionDTO` / `UpdateProductOptionDTO` | `product_options` — knob definitions |
| `ProductOptionValueDTO` / `CreateProductOptionValueDTO` / `UpdateProductOptionValueDTO` | `product_option_values` — `kind=select` selectable values |
| `ProductPricingModifierDTO` / `CreateProductPricingModifierDTO` / `UpdateProductPricingModifierDTO` | `product_pricing_modifiers` — price bumps per option/value |
| `ProductMaterialDTO` / `CreateProductMaterialDTO` / `UpdateProductMaterialDTO` | `product_materials` — recipe rows (variant-pinned or family-pinned) |
| `CatalogProductOptionMappingDTO` / `CreateCatalogProductOptionMappingDTO` / `UpdateCatalogProductOptionMappingDTO` | `catalog_product_option_mappings` — catalog axis/value to product option/value bridge; gated by `CatalogSchemaCapabilityGate` |
| `ProductBundleItemDTO` / `CreateProductBundleItemDTO` / `UpdateProductBundleItemDTO` | `product_bundle_items` — bundle composition; relationship fields are encoded only after the capability gate proves those columns exist |

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
| `ExpenseAtomicSaveCommand` / `ExpenseAtomicAllocationCommand` | Current full-snapshot write contract for `save_expense_atomic`; stable request ID, strict status/`updated_at` CAS, explicit nullable fields, complete allocation replacement, and submit intent |
| `CreateExpenseDTO` | Legacy direct-table create compatibility path; do not use for the current expense form |
| `UpdateExpenseDTO` | Legacy direct-table partial-update compatibility path; do not use for the current expense form |
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

Project team members are a read/cache projection of non-deleted task team members. Locally, iOS recomputes the projection with `updateTeamMembersFromTasks(in:)` after task creation, update, or deletion. For server persistence, iOS writes crew changes to `project_tasks.team_member_ids` or uses the project table assignment RPCs; it must not enqueue `projects.team_member_ids` as a project table write.

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

### 5. Logout Data Wipe Contract

`DataController.performCompleteDataWipe()` implements logout cleanup as an explicit per-model deletion list. It is not derived automatically from `OPSSchemaV16.models`; any newly registered model must be audited against that list before the logout wipe can be treated as complete. Source: `OPS/Utilities/DataController.swift`.

---

## Summary

This data architecture provides:

- **Versioned SwiftData schema graph** with immutable compatibility checksums for every declared version
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
- **Sender identity (migration `20260803015347_add_email_connections_outreach_subject`, 2026-08-03)**: `email_connections.outreach_subject` (TEXT, nullable) — operator-configured subject for NEW-thread lead outreach drafts; null falls back to the built-in default. **Custom signature logo (migration `add_email_connections_signature_logo_url`, 2026-08-05)**: `email_connections.signature_logo_url` (TEXT, nullable) — signature-specific mark, resolved custom > `companies.logo_url` server-side; null = company logo. `email_signatures.confirmed_at` (pre-existing column) is now load-bearing: an active operator- or mailbox-scope row with `confirmed_at` set is what opens the contact-form outreach gate (provider-scope imports never do; confirming an import promotes its content into the operator-scope row). See `07_SPECIALIZED_FEATURES.md` § Sender Identity & Outreach Settings (2026-08-05).
- **Migration `20260723214306_email_threads_lead_scan_pending.sql`** adds the nullable positive deferral marker `email_threads.lead_scan_pending_at` plus a partial drain index. It marks only unmatched threads whose lead scan was skipped during an AI-provider outage; `opportunity_id IS NULL` alone never means a scan is pending.
- **Migration `20260723214524_company_mailbox_intake_owner.sql`** adds the guarded company-mailbox owner FK/index, immutable `company_mailbox_default` assignment source, one service-role atomic live create-and-disposition RPC, and the fully private `unassigned_lead_assignment_deliveries` outbox plus service-only lease RPCs. It is forward-only: existing connection owners remain null, existing opportunity source-key rows are returned unchanged, and no historical opportunity is scanned or changed.
- **Migrations `20260723224713_guarded_orphan_outbound_email_activity_adoption.sql` and `20260723225112_shorten_guarded_orphan_outbound_email_activity_rpc.sql`** add one service-role-only adapter for an exact outbound email activity that was inserted before its provider thread acquired a canonical opportunity owner, then give it the PostgreSQL-safe canonical name `adopt_orphan_outbound_email_activity_guarded_as_system`. Callers must use only that canonical identifier; the initial longer identifier exceeded PostgreSQL's 63-byte limit and was server-truncated. The RPC binds the repair to the current physical mailbox lease, active connection mirror, immutable `(connection_id, provider_thread_id)` owner, exact provider message and activity payload, and active target opportunity. It token-gates the single `NULL → canonical opportunity` child update and records canonical outbound correspondence in the same transaction; any ownership, lease, payload, or event conflict rolls the adoption back. It does not change stage, assignment, project state, or provider state, and it runs only during ordinary forward sync rather than as a historical backfill.
- **Migration `20260731183127_fix_manual_outbound_follow_up_lifecycle_conflict_target.sql`** is the repository record of the production hotfix applied on 2026-07-31. `reconcile_manual_outbound_follow_up_cycle_as_system` now targets `opportunity_lifecycle_state_pkey` by constraint name; `ON CONFLICT (opportunity_id)` is invalid in this `RETURNS TABLE` function because its output also exposes `opportunity_id`. Execute remains service-role-only.
- **Migration `20260731203000_email_sync_terminal_checkpoint.sql` is live as of the 2026-08-05 schema readback.** It adds the service-role-only, owner-fenced nonterminal cursor checkpoint that may publish `history_id` but cannot advance `last_synced_at`.
- **Prepared migrations `20260731210000_event_driven_archived_lead_reactivation.sql` and `20260801003000_fix_contact_form_draft_rpc_identifiers.sql` were not applied as of 2026-08-01.** The first adds exact-thread inbound reactivation, mailbox-owner/assignment-review disposition, assignment-version-fenced deliveries, and an archived-stage transition guard. The second exposes PostgreSQL-safe service-only names for the contact-form provider-create reservation and uncertain-outcome reconciliation RPCs; their original 67- and 74-byte declarations exist in the catalog only under server-truncated names and therefore cannot be resolved by PostgREST using the application strings. Neither migration backfills or assigns historical leads.
- **Migration record `20260805190312_email_provider_snapshot_health` is live as of the 2026-08-05 production readback.** Its repository source is `20260805151056_email_provider_snapshot_health.sql`. It adds nullable `email_connections.provider_snapshot_at`, extends the checkpoint RPC with trailing optional `p_provider_snapshot_complete`, and makes terminal completion advance provider health from the database clock. The original positional fourth argument remains `p_clear_recovery`, so the database-first rollout remained backward compatible with the old server.
- **Prepared migration `20260802163538_keep_contact_form_mailbox_busy_retryable.sql` is not applied as of 2026-08-02.** It adds nullable `email_assignment_contact_form_draft_queue.mailbox_busy_since`, a partial operational index, a private canonical physical-mailbox lease predicate, a service-only mailbox-aware claim replacement, and one persistent notification lifecycle after an hour of continuous contention. Due rows are marked once and excluded before the bounded worker limit while the lease is active, preventing attempt churn, repeat model work, provider polling, and healthy-mailbox starvation. A post-claim acquisition race returns to the same wait; provider-create uncertainty and stale assignment retain stricter outcomes. The generalized repair returns only exact `failed` contention rows with both provider-create markers null to the guarded queue. It changes no provider, draft-history, opportunity, or assignment record directly; the normal worker gates run again before provider access. OPS-Web commits: `92344a64`, `865bab6e`.

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
  default_intake_owner_id UUID REFERENCES users(id) ON DELETE SET NULL, -- company-mailbox default for newly created email leads
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

**Current cursor and health authority (2026-08-05 production contract).** The live
column names used by the sync engine are `history_id`, `last_synced_at`,
`history_recovery_anchor`, `history_recovery_page_token`,
`history_recovery_target_token`, `sync_in_progress_at`, and `sync_lock_owner`.
A structured Gmail provider remainder, an M365 folder/message page remainder,
a recovery page token, pending derived lead summaries, or an active sync means
the end-to-end mailbox snapshot is nonterminal. The live
`persist_email_connection_sync_checkpoint_as_system` may publish the
owner-fenced `history_id` continuation but deliberately cannot update
`last_synced_at`; only terminal completion advances that end-to-end timestamp.

Production migration record `20260805190312_email_provider_snapshot_health`,
from repository source `20260805151056_email_provider_snapshot_health.sql`,
adds a second, provider-only health timestamp: nullable
`provider_snapshot_at`.
Checkpoint publication advances it from the database clock only when the
decoded provider cursor is terminal, independently of a remaining derived
lead-summary queue. Gmail structured cursors remain provider-pending. M365 v2
is provider-terminal only when the folder cursor is a Graph `$deltatoken` and
`pendingFolderIds` is empty; folder `$skiptoken`, pending-folder, legacy v1,
and raw URL cursors fail closed as pending. Heartbeat classification uses
`provider_snapshot_at` with `last_synced_at` as the nullable rollout fallback.

Authenticated sync behavior was first runtime-proven on byte-identical repair
commit `146f6d69c4d52d985bc516c0453db6590f92cf97` in production deployment
`dpl_6gxJ4P8dv7ohpXpi1wbbdPuyR7FY`; the derived continuation drained from seven
pending opportunity IDs to zero. The durable customer release is OPS-Web main
commit `17e70559e5db5d51861e4d8bc8d57b2cd490d10b`, served by READY deployment
`dpl_AiDK9ZkSfv6BvbP9pSkZiRwnVgSh` as of `2026-08-06T06:29:26.442Z`.
`app.opsapp.co` resolves to that exact SHA with `aliasError = null`; root and
login returned HTTP 200, the unauthenticated heartbeat correctly returned HTTP
401, and deployment-scoped logs contained no error/fatal entry or HTTP 5xx.
Migration record `20260805190312_email_provider_snapshot_health` remains live.
Current database readback has zero wrapped continuations, locks, or recovery
state, with `last_synced_at` `2026-08-06T03:57:31.91Z` and
`provider_snapshot_at` `2026-08-06T03:57:32.135712Z`. This exact final
deployment was not made to perform a new authenticated sync or provider/email
mutation; behavioral runtime proof remains the earlier byte-identical
deployment.

`default_intake_owner_id` is valid only on `type='company'` connections. The
database requires an active, nondeleted user in the same company with effective
assigned-scope `pipeline.view`, `pipeline.edit`, and `inbox.send` authority.
The nullable FK uses `ON DELETE SET NULL` and a partial non-null owner index.
Configuration is stale-safe and service-role-only: the authenticated route
requires company-wide integration-management and lead-assignment authority,
while the database revalidates the actor, prior owner, mailbox, and proposed
owner under the company assignment lock. Generic connection updates cannot
change this field.

### unassigned_lead_assignment_deliveries

Durable, addressed outbox for a newly created company-mailbox lead that has no
eligible default intake owner. The table is unique on
`(opportunity_id, recipient_user_id, assignment_version)` once the prepared
2026-07-31 reactivation migration is applied, and stores pending/processing/delivered/
failed state, attempt limits, lease token/expiry, retry timing, notification
identity, provider outcome, and terminal/resolution provenance. Enqueue is
idempotent and addresses only active same-company administrators who currently
hold company-wide `pipeline.view`, `pipeline.edit`, and `pipeline.assign`.

RLS is enabled and forced with no client policy. Table privileges are revoked
from `public`, `anon`, `authenticated`, and direct `service_role` callers; only
the narrow service-role integration functions can claim, complete, or fail a
delivery. Claiming reauthorizes the exact recipient, suppresses an assigned,
terminal, inaccessible, or exhausted row, and materializes at most one
persistent notification before exposing a push claim. A canonical non-null
assignment event resolves every delivery and associated notification for that
opportunity.

The widened key lets the same durable mechanism represent a later archived-lead
reactivation without reviving an obsolete prompt. Claim and completion compare
the delivery's exact assignment version with the current opportunity version;
any reassignment makes the older delivery stale. The historical three-argument
enqueue helper remains version-zero-only for genuinely new leads.

No migration scans historical opportunities. Rows are inserted only inside the
same transaction that creates a new live company-mailbox opportunity and either
assigns its configured owner or records the missing/ineligible-owner prompts.
An existing `(company_id, source_thread_key)` winner is returned unchanged and
never becomes a retry-time assignment or prompt backfill. Historical wizard
import retains automatic assignment only for individual mailboxes.

Source: `migrations/20260723214524_company_mailbox_intake_owner.sql`.

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
  subject_preferences     JSONB NOT NULL DEFAULT '{}'::jsonb,
  tone_traits             JSONB,
  emails_analyzed         INT DEFAULT 0,
  updated_at              TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(company_id, user_id, profile_type)
);
```

**Profile types:** client_new_inquiry, client_quoting, client_active_project, client_followup, vendor_ordering, vendor_inquiry, subtrade_coordination, warranty_claim, internal, general. Clustered for galaxy visualization: client, vendor, subtrade, internal, general.

**Subject learning (prepared 2026-07-14, migration `20260713210000_phase_c_learning_signatures`):** `subject_preferences.preferred_patterns` contains ranked `{ pattern, count, examples, last_promoted_at }` objects. `pattern` and `examples` are de-identified templates only, using `{contact}`, `{company}`, `{address}`, `{project}`, `{email}`, and `{number}`. Raw subjects are not retained in preference evidence. A pattern needs three database-verified human examples before promotion; subsequent evidence continues updating its count/examples.

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
-- Live schema (verified against prod 2026-06-03). Columns below reflect the
-- additive P4-B provenance + mailbox-draft migrations layered onto the original.
CREATE TABLE ai_draft_history (
  id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id            UUID NOT NULL,
  user_id               UUID NOT NULL,
  opportunity_id        UUID,
  connection_id         UUID,
  thread_id             TEXT,                  -- provider thread the draft belongs to (see notes)
  original_draft        TEXT NOT NULL,
  final_version         TEXT,
  edit_distance         INT DEFAULT 0,
  changes_made          JSONB DEFAULT '[]',
  sent_without_changes  BOOLEAN DEFAULT false,
  status                TEXT NOT NULL DEFAULT 'drafted'
                          CHECK (status IN ('drafted','sent','discarded','auto_drafted',
                                            'superseded','sent_from_mailbox','discarded_in_mailbox')),
  profile_type          TEXT NOT NULL DEFAULT 'general',
  subject               TEXT,                  -- derived reply/outreach subject (P4-B)
  subject_source        TEXT CHECK (subject_source IS NULL OR subject_source IN ('thread','operator','configured','generated','learned','fallback')),
  source_message_id     TEXT,                  -- provider id of the inbound msg replied to (P4-B)
  origin                TEXT CHECK (origin IS NULL OR origin IN ('operator','template_follow_up','phase_c','system_handoff')),
  mailbox_draft_id      TEXT,                  -- provider Drafts-folder id once pushed (Gmail/M365)
  sent_at               TIMESTAMPTZ,
  edited_at             TIMESTAMPTZ,
  discarded_at          TIMESTAMPTZ,
  created_at            TIMESTAMPTZ NOT NULL DEFAULT now()
);
```

- **`mailbox_draft_id`** (migration `20260602000000`): the provider Drafts-folder id once OPS pushes the draft into the user's real Gmail/Outlook, written alongside `status='auto_drafted'`. Reply-path idempotency keys on `(connection_id, thread_id)`; the forwarded contact-form **new-thread** path keys on `(connection_id, opportunity_id)`.
- **`status` CHECK** expanded (migration `20260602010000`) beyond the original `drafted/sent/discarded`: `auto_drafted` (pushed to mailbox, awaiting outcome), `sent_from_mailbox` (user sent it from their own mail client → reconciliation "used"), `discarded_in_mailbox` (deleted without sending, past TTL), `superseded` (user wrote a fresh reply). Always verify new status values against the live constraint — vitest mocks do not enforce CHECKs.
- **`thread_id`** is the provider thread the draft belongs to. Ordinary replies: the inbound thread. **Forwarded contact-form** auto-draft (2026-06-03): the *new* thread minted by `provider.createNewThreadDraft` (Gmail `message.threadId` / M365 `conversationId`), stamped by `placeNewThreadDraft` so `reconcilePendingMailboxDrafts` (keyed on `thread_id`) still matches the client's reply; that thread is also linked in `opportunity_email_threads`.

- `edit_distance`: Word-level Levenshtein distance between `original_draft` and `final_version`.
- `changes_made`: Structured diff — `{ greeting?: {from, to}, closing?: {from, to}, tone?: string }`.
- When `sent_without_changes` reaches 95% over 20+ drafts, auto-send is suggested to the user.

### email_send_intents follow-up outcome receipt

Migration `20260723233000_operator_one_tap_lead_follow_up.sql` extends the durable send-intent ledger with `follow_up_outcome_applied_at`, nullable `follow_up_comeback_at`, and `follow_up_notification_id`. A provider-confirmed template follow-up writes all three as one immutable reconciliation receipt: the applied timestamp proves the local outcome ran, the notification foreign key proves the operator-visible result exists, and a null comeback means newer opportunity-wide correspondence or lead state won the race and was preserved. Replays return this stored receipt; they do not increment lifecycle counters, reschedule the lead, create another notification, or call the provider again.

### email_outbound_learning_queue + edit evidence

Prepared by migrations `20260713205000_email_outbound_learning_queue` and `20260713210000_phase_c_learning_signatures`. The queue is the durable owner of sent-draft bookkeeping, writing-profile learning, and correction-memory application. Provider message identity is immutable and connection-scoped. Prepared outcomes are receipted before apply, leased for retry, and deduplicated across provider replay.

`learning_authority` is one of `autonomous`, `operator_approved`, or `operator_authored`, but the database derives/upgrades it only from verifiable activity/draft provenance; an RPC caller cannot promote its own authority. `apply_full_body_learning` is separately persisted at preparation time and may be true only for verified `operator_authored` rows. `operator_approved` rows can apply de-identified durable edit evidence without sampling the AI-authored final body; autonomous jobs may complete mandatory draft bookkeeping but cannot train writing profiles or memories. `email_outbound_edit_evidence` stores de-identified repeated changes; promotion receipts make profile mutations exactly once. Provenance enrichment clears any uncommitted prepared writing/memory payload before recomputation. Service role owns all queue RPC execution.

### email_signatures

Prepared by migration `20260713210000_phase_c_learning_signatures`. Stores sanitized HTML, canonical plain text, SHA-256 content hash, source, exact provider identity, active revision, operator/mailbox scope, and actor/fetch/confirmation timestamps for one company + connection.

Resolution order is: active OPS signature for the current operator, active mailbox-wide OPS signature, active provider signature whose identity exactly equals the connected mailbox, then none. Guarded service-only replace/deactivate RPCs derive the active OPS actor and company, lock assignment-dependent company-mailbox authorization, force OPS rows to the actor scope, and force provider rows to the exact mailbox identity. The pre-assignment `replace_email_signature` primitive and direct service-role table mutation are revoked from application callers. Old revisions remain available for exact suffix stripping after provider draft round trips. Gmail source rows come from read-only `sendAs` inspection. Microsoft Graph exposes no mailbox signature, so Microsoft users save/paste an OPS signature. RLS is enabled.

### Mailbox recovery + manual outbound cycle receipts (prepared 2026-07-29)

Migration `20260729230000_pipeline_follow_up_reliability.sql` extends the service-only `email_ingestion_recovery_queue` without weakening any conversion guard. Recovery rows may now use `recovery_kind = 'commercial_outcome'` and carry the exact `opportunity_id` in addition to company, connection, provider message, and provider thread identity. The enqueue RPC proves that the projected meaningful correspondence event, canonical thread, provider message/thread, connection, and opportunity are one canonical tuple before it accepts the item.

Only a typed automatic-project safety hold is eligible for this quarantine path. The original project-address proof, duplicate prevention, active-state, authorization, manual-override, prompt-injection, and commercial classification gates remain unchanged. The blocked item keeps its own deferred state and exact retry authority, while unrelated messages may become durable and the mailbox cursor may progress. A worker retry reauthorizes the same tuple, reruns canonical commercial-outcome evaluation, and refreshes the Phase-C opportunity summary only when Phase C is enabled. Unclassified provider/model failures still hold cursor advancement.

The same migration adds `opportunity_manual_outbound_cycle_receipts`, with RLS enabled and no client policy. Its service-role RPC `reconcile_manual_outbound_follow_up_cycle_as_system(company_id, opportunity_id, event_id)` accepts only a newest, meaningful, projected, non-noise OPS outbound from `sync_activity` whose exact activity/mailbox/thread/message/correspondence linkage still agrees. The transaction locks the lead and lifecycle state, writes one immutable event receipt, stamps handled/timeline truth, advances `next_follow_up_at` by `lead_lifecycle_settings.follow_up_after_days` (default 7) while preserving an explicitly sooner future check-in, satisfies the prior cycle only when `event.occurred_at >= prior next_follow_up_at`, recalculates unanswered/stale chase state, supersedes only an open `template_follow_up` draft, and resolves the matching operator-miss notification. Internal-only, ambiguous, orphaned, duplicate, unprojected, or older outbound mail cannot obtain a receipt or mutate a lead.

### `email_send_intents` one-tap follow-up outcome receipt (2026-07-23)

Migration `20260723233000_operator_one_tap_lead_follow_up.sql` extends the durable provider-send intent with three nullable receipt fields:

```sql
follow_up_outcome_applied_at timestamptz
follow_up_comeback_at        timestamptz
follow_up_notification_id    uuid references notifications(id) on delete restrict
```

`email_send_intents_follow_up_outcome_receipt_check` requires all receipt fields to be empty before apply. A completed receipt requires `follow_up_outcome_applied_at`, `follow_up_notification_id`, and `follow_up_draft_id`; `follow_up_comeback_at` is deliberately nullable when a newer inbound, terminal transition, or operator action already owns the lead's chase state. The receipt is written in the same transaction as the lifecycle transition. A replay returns these stored values before any draft, counter, opportunity, or notification mutation can run again.

The same migration changes the `lead_lifecycle_settings.follow_up_template_body` default to the 2026-07-23 standard copy and updates only rows whose body exactly equals the prior stock default. Any company-customized template remains untouched.

The service-role-only `public.reconcile_operator_template_follow_up_send_as_system(p_intent_id uuid)` accepts only a provider-accepted/reconciling/reconciled intent whose `template_follow_up` draft, company, opportunity, connection, provider thread, recipient, and accepted provider identity still agree. In one locked company → opportunity → intent → draft → lifecycle transaction it:

1. marks the draft `sent`, persists `final_sent_body`, and stamps provider acceptance time;
2. increments `opportunity_lifecycle_state.unanswered_follow_up_count` exactly once when this send is still the latest meaningful lifecycle event, stamps `second_follow_up_sent_at` at count 2+, and clears follow-up-due/operator-miss stale state;
3. resolves the prior `leads_waiting` operator-miss notification only when this send is still the latest meaningful lifecycle fact;
4. if no later meaningful event, operator action, or terminal/project transition won the race, stamps `opportunities.handled_at` from provider acceptance and sets `next_follow_up_at` to acceptance +3 days while preserving only an explicitly chosen sooner comeback on a later company-local calendar day; otherwise it records a null comeback receipt and leaves newer chase truth untouched;
5. creates one standard `lead_follow_up_sent` notification and stores its id on the intent; and
6. writes the immutable receipt and returns it.

The migration also extends the existing `private.guard_system_handoff_email_send_delivery()` prepared→sending trigger for `template_follow_up`. Before provider I/O it rechecks the company-local due day, quote-bearing stage, operator/no-switch authority, frozen draft subject/body, pinned provider thread/source outbound/recipient, and absence of newer correspondence. An opportunity-wide fence blocks every other unresolved template follow-up even after the canonical thread changes. A second live-provider read runs inside the mailbox lease immediately before the provider call; a changed newest message is a definitive pre-delivery rejection. Template drafts are mutation-frozen after the provider boundary until rejection or the exact reconciliation-to-sent transition. The older `system_handoff` authorization branch remains intact.

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
- `ai_summary`: 1-2 sentence AI-generated summary of the opportunity. **Three writers, one field contract (as of 2026-07-21):**
  1. **Import seed** — `POST /api/integrations/email/import` mirrors the classifier's description into `ai_summary` at lead creation.
  2. **Email engine** — each sync cycle that touches a lead's thread refreshes it via `AISyncReviewer.evaluateStagesWithSummary()` (combined stage + summary call, phase_c-gated).
  3. **Activity-driven refresh** — `GET/POST /api/cron/lead-summary-refresh` (`lead-summary-service.ts`) generates and refreshes summaries from the lead's non-email record (activities, stage transitions, site visits, description, and `email_threads.ai_summary` as read-only input) for leads email triggers can't reach: email-born leads predating the engine (one-time backfill) and site-visit/call/manual leads (recurring sweep, `LEAD_SUMMARY_REFRESH_ENABLED`-gated). Same model lane (`gpt-4o-mini` / `OPENAI_API_KEY_SYNC`), same verbatim summary spec, same phase_c gate, summary-fields-only writes. Staleness = newest context timestamp > `ai_summary_updated_at` + 5-minute epsilon (absorbs the engine's own stage-transition echo). Leads with zero substantive context are never summarized — no fabrication from a bare name. See `04_API_AND_INTEGRATION.md` §24a.

  `email_threads.ai_summary` (the inbox thread summary) is a separate feature and field — thread-scoped, written by the thread classifier only; the lead-scoped writers above never touch it.

These columns are used by the sync engine's correspondence-count stage rules (free tier) and AI stage evaluation (gated tier).

**Chase-system columns (iOS Leads redesign; migrations `leads_chase_handled_at_and_summary_stamp`, 2026-07-18, `20260723174912_add_opportunity_action_required_at.sql`, and `20260723175646_allow_lead_quick_touch_activity_types.sql`, 2026-07-23):**

```sql
ALTER TABLE public.opportunities
  ADD COLUMN IF NOT EXISTS handled_at timestamptz NULL,
  ADD COLUMN IF NOT EXISTS ai_summary_updated_at timestamptz NULL;

ALTER TABLE public.opportunities
  ADD COLUMN IF NOT EXISTS operator_action_required_at timestamptz NULL;
```

- `handled_at`: The operator's **WAITING** declaration ("handled — their move now"). iOS writes it via the card/detail HANDLED ✓ action (one PATCH that also sets `next_follow_up_at` to the comeback date: default now+3d, a sooner FUTURE follow-up is kept, past-due dates always replaced). The lead card's fact-only TEXT and EMAIL quick touches atomically advance `handled_at` while logging their outbound activity, so a successful touch immediately becomes **WAITING** even before any correspondence sync updates `last_outbound_at`. The one-tap provider follow-up is the provider-backed path: its service-only reconciliation RPC stamps `handled_at` only after provider acceptance and preserves any later operator/terminal state.
- `operator_action_required_at`: The operator's manual **YOUR MOVE** correction. iOS writes it from the WAITING card/detail `ADJUST` sheet. It does not rewrite `last_message_direction`, erase `handled_at`, or modify correspondence timestamps; a later real correspondence event or later HANDLED action supersedes it.
- `private.stamp_opportunity_chase_events()` is a `BEFORE UPDATE` trigger for `handled_at` and `operator_action_required_at`. A client sends a non-null change sentinel, the trigger replaces it with millisecond-precision `statement_timestamp()`, and the client applies the authoritative returned opportunity row. Manual ownership ordering therefore uses the database clock, not a potentially skewed device clock.
- A quick TEXT/EMAIL is one atomic database action through `public.log_opportunity_quick_touch(...)`: activity creation, ownership advancement, and the exact undo receipt either all commit or all roll back.
- `ai_summary_updated_at`: Freshness stamp for `ai_summary`. All three web summary writers set it whenever they write `ai_summary` (import seed, sync engine, activity-driven refresh — shipped 2026-07-21); clients render the "UPDATED 2D AGO" stamp only when present. It is also the staleness anchor for the activity-driven refresh cron: rows with a summary but a NULL stamp (pre-stamp legacy seeds) are treated as stale and heal on the first enabled sweep.
- `activities.type` gained the checked values `'text_message'` and `'email_compose'`. The additive constraint migration preserves every previously accepted activity type, validates the widened check before replacing the old constraint, and leaves no window for invalid new writes. iOS logs `email_compose` when it launches the local Mail composer because that action has no provider mailbox, message, or thread identity. Provider-backed `'email'` remains reserved for correspondence ingested with those provider identifiers; this boundary prevents a local composer launch from masquerading as a delivered or synced email.
- RLS note: `email_attachments` gained the additive policy `email_attachments_lead_files_select` (`attribution_status = 'attributed' AND opportunity_id IS NOT NULL AND private.current_user_can_view_opportunity(opportunity_id)`) — the pre-existing SELECT policy keys off a `company_id` JWT claim the iOS Firebase bridge does not carry, so iOS lead-file reads returned zero rows. Web service-role reads are unaffected.

**Chase ownership resolution (2026-07-23):**

Resolve `OVERDUE` and `DUE TODAY` first. If neither date bucket applies, `stage = 'new_lead'` remains `FRESH`. Only then do clients compare the newest ownership signal on each side:

- **YOUR MOVE:** `last_inbound_at` and `operator_action_required_at`.
- **WAITING:** `last_outbound_at` and `handled_at`.

The side with the newest timestamp wins. Exact timestamp ties resolve deterministically:

1. `operator_action_required_at` wins any tie, including a tie with `handled_at`; the explicit operator correction is **YOUR MOVE**.
2. Without an operator-action correction at that timestamp, `handled_at` beats `last_inbound_at`; the explicit handled declaration is **WAITING**.
3. A pure `last_inbound_at` / `last_outbound_at` tie uses `last_message_direction`. Direction `'in'` is **YOUR MOVE**; `'out'`, NULL, and unrecognized values default safely to **WAITING**.

When none of the four timestamp signals is present, preserve the legacy direction fallback: `last_message_direction = 'in'` is **YOUR MOVE** and every other value is **WAITING**. Newer signals naturally supersede older manual corrections; no clearing mutation or cron is required.

**Atomic quick-touch and undo contract (2026-07-23):**

`public.log_opportunity_quick_touch(p_request_id, p_opportunity_id, p_type, p_subject)` is the authenticated, four-argument `SECURITY DEFINER` boundary for the card's TEXT and EMAIL quick actions. The client generates a UUID request ID and may safely retry that same request. In one transaction the RPC:

1. authorizes an active company operator with edit access to the opportunity;
2. advances `handled_at` to the authoritative server-stamped **THEIR MOVE** marker;
3. inserts one outbound `text_message` or `email_compose` activity; and
4. records the exact before/after lineage in `private.opportunity_quick_touch_undo`.

The request ID is idempotent and payload-bound. An exact retry by the same actor returns the original activity and current opportunity without duplicating the touch. Reusing it for a different actor, company, opportunity, type, subject, direction, or after undo is rejected.

`private.opportunity_quick_touch_undo` is a server-only durable receipt table keyed by request ID, with a unique activity ID, opportunity/company/actor lineage, the touch's `handled_at`, the exact prior `handled_at`, and `undone_at`. It intentionally has no activity foreign key: deleting the activity leaves a tombstone that makes undo replay idempotent and prevents the original log request from being replayed into a second activity. Restrictive activity UPDATE/DELETE policies protect token-backed rows from direct authenticated mutation while their receipt is active. Trusted reparent/delete triggers consume the receipt so a moved or externally removed activity can never restore chase state on the wrong lead.

Both RPCs take locks in the canonical company → opportunity → user → activity → receipt order. The order is shared with lead-assignment writers and prevents concurrent retries, undo, user deactivation, and activity mutation from deadlocking or bypassing the post-lock authorization check.

`public.undo_opportunity_quick_touch(p_activity_id, p_opportunity_id)` is the authenticated, two-argument `SECURITY DEFINER` reversal boundary. It locks and validates the durable receipt, rejects out-of-order undo when the opportunity's current `handled_at` no longer equals that touch's marker, removes exactly that activity, tombstones the receipt, and restores the receipt's exact prior `handled_at`. It does not synthesize a new `operator_action_required_at` and does not rewrite `last_inbound_at`, `last_outbound_at`, or an existing operator correction, so newer correspondence and manual ownership signals remain authoritative. Repeating a completed undo is idempotent and returns the current opportunity.

iOS keeps the successful quick touch's UNDO toast visible until manual dismissal. Launching Messages or Mail may background OPS, but returning to the app preserves the same undo action so the operator can reverse the atomic touch after completing or cancelling the external composer.
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
  lead_scan_pending_at        timestamptz,              -- positive AI-outage deferral marker; NULL means no deferred scan

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
- `email_threads_lead_scan_pending_idx` — `(company_id, lead_scan_pending_at) WHERE lead_scan_pending_at IS NOT NULL AND opportunity_id IS NULL` — bounded oldest-first recovery after AI-provider outages

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

### Phase C lead-disposition feedback (production)

Migration `ops-web/supabase/migrations/20260727193418_phase_c_lead_disposition_feedback.sql`
adds the authoritative correction contract shared by iOS and email ingestion.
It is additive and forward-only. It was applied to production on 2026-07-27
(recorded by Supabase as
`20260728004810_phase_c_lead_disposition_feedback`). Post-apply verification
confirmed both tables empty, RLS enabled, direct client writes revoked, and no
new security or performance advisories. No historical lead was reinterpreted
or backfilled.

`lead_disposition_feedback` is append-only correction history. Each row binds
the company, opportunity, authenticated actor, structured reason, canonical
outcome, active/retracted learning state, prior and applied lifecycle state,
source mailbox/thread/message keys when unambiguous, sender/domain evidence,
model/policy context, and apply/undo idempotency keys. Optional context is
limited to 500 characters and is audit-only; classifier reads deliberately
exclude it. Direct insert/update/delete is revoked. Authenticated users may
read only feedback for opportunities they can view, while all mutations cross
actor-authorized `SECURITY DEFINER` RPCs.

`lead_classification_reviews` is the service-only durable hold for a future
inbound message whose structured feedback prior makes the lead decision
ambiguous. It stores exact company/connection/provider identities, bounded
scores, structured evidence, and pending/resolved state—never message content
or operator notes. The unique
`(company_id, connection_id, provider_message_id)` key makes a retry converge
on the same hold instead of creating another review.

The mutation RPCs are:

- `get_lead_disposition_context(opportunity_id)` — proves the actor can edit
  the lead and returns the authoritative live Phase C gate plus policy version.
- `apply_lead_disposition_feedback(...)` — locks the opportunity and
  idempotency key, validates the actor/company/gate/reason, writes disposition,
  lifecycle transition, and feedback in one transaction, and rejects terminal
  or already-merged leads.
- `undo_lead_disposition_feedback(...)` — restores the exact prior lifecycle
  and disposition state and retracts the learning row in one transaction.
  Undo is idempotent and fails closed if a later edit changed the lead.

Canonical reason mapping:

| Structured reason | Lifecycle outcome | Learning polarity |
|---|---|---|
| spam, job applicant, vendor sales, internal, platform notification, test traffic | `discarded` | negative |
| duplicate, not a fit, created by error, other | `discarded` | neutral |
| legacy unspecified (Phase C disabled only) | existing `discarded` behavior | neutral |

The mapping was corrected in production on 2026-08-20 by migration
`20260820223332_lead_conversion_photo_selection_and_disposition_repair`.
Every reason offered by a discard surface now performs a discard. In
particular, `not_a_fit` is an unqualified lead and never contributes to Lost;
duplicate, other, and created-by-error cannot leave the lead on the board.

Follow-up migration
`20260821033538_lead_conversion_rpc_permission_hardening` revokes conversion
candidate execution from `public` and `anon`; only `authenticated` may invoke
the project and photo candidate RPCs. Both functions remain `SECURITY DEFINER`
intentionally because they repeat active-user, company, opportunity, and
conversion-permission checks before returning company-scoped rows.

The same migration adds `archived` to the durable opportunity-disposition
vocabulary. Evidence-bound budget/timing deferrals now preserve the active
pipeline stage, set `opportunities.archived_at`, retain a guarded follow-up,
and write disposition `archived` / reason `not_now`. They do not write Lost
fields, close dates, win probability, or a Lost stage transition.

**Won conversion photo selection.**
`get_opportunity_conversion_photo_candidates(opportunity_id)` returns the exact
manual lead URLs and provenance-eligible inbound email attachments available
to the current converter. New clients submit `selected_lead_photo_urls` and
`selected_email_attachment_ids` in conversion evidence. A BEFORE-event guard
locks the opportunity, rejects malformed, duplicate, foreign, or stale keys,
and binds the arrays into the immutable conversion event. The event projection
removes only unselected manual photo rows created by that same transaction and
enqueues only selected email attachments; later attachment reconciliation
honors the same immutable selection. An omitted key remains select-all for
backward compatibility. Existing project media is never pruned.

Source evidence is conservative. The RPC prefers the opportunity's exact
provider thread key. Without one, it records an email-thread identity only
when exactly one company-scoped linked candidate exists; ambiguous historical
links never become arbitrary learning evidence. Exact provider IDs gain exact
prior authority only inside that recorded mailbox connection.

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

## Outbound Email Tables (Web Only)

Eleven Supabase tables back the outbound email subsystem (SendGrid transport, `gatedSend` chokepoint, campaign engine, killswitches, suppression, trial-expiry lifecycle, anomaly detection, admin console). Full schemas, RLS, and lifecycle invariants are canonical in `13_EMAIL_SYSTEM.md` § Data Model — this section is a cross-reference only.

- **`email_log`** — Every `gatedSend` attempt (`sent` / `failed` / `suppression_skipped` / `paused_skipped`). Created via Supabase dashboard pre-migration-system; documented in migrations 083, 088, 094, 098.
- **`email_events`** — SendGrid Event Webhook persistence, idempotent on `(sg_message_id, event, timestamp)`. Migration 079; auto-suppression trigger `trg_email_events_auto_suppress` added by migration 081.
- **`email_suppressions`** — Do-not-send list queried on every send. Global + per-channel scopes (`field_notes`, `product_updates`, `reengagement`, `blog`, `beta`). Migration 080; backfill 082; sweep indexes 097.
- **`email_pause_state`** — Three-scope live killswitch (`global` | `bucket:*` | `campaign:<uuid>`), read on every send. Migration 092.
- **`email_pause_audit_log`** — Append-only audit of every pause / resume / auto_resume. UPDATE/DELETE revoked. Migration 093; severity + `anomaly_log_id` link added migration 104.
- **`email_campaigns`** — Operator-scheduled marketing and lifecycle campaigns with status enum + counters. Migration 086; counter RPC migration 089; audience-template FK migration 095.
- **`email_jobs`** — Per-recipient dispatch queue (one row per `(campaign, recipient)`). Worker claims `pending` via `claim_email_jobs()` RPC. Migration 087; unique constraint migration 091; `template_version` stamp migration 099.
- **`email_audience_templates`** — Reusable saved audience filters. Resolved by `resolve_email_audience()` RPC. Migration 095; resolve RPC migration 096.
- **`email_template_versions`** — Append-only template version history (UPDATE/DELETE revoked). Build-time sync from `@template-version` header + sha256. Migration 102.
- **`email_anomaly_log`** — Deliverability anomalies (`bounce_spike` / `spam_spike` / `delivery_drop` / `volume_drop`) detected by `/api/cron/email/anomaly-check`. Migration 105.
- **`trial_expiry_notifications`** — Dedup table for the trial-expiry cron. Unique on `(company_id, notification_type)`. Migration 053. See `13_EMAIL_SYSTEM.md` § Trial-Expiry Lifecycle.

The `BEFORE INSERT ON companies` trigger `initialize_company_trial` (migrations 065, 066) — which stamps `trial_end_date` and makes the trial-expiry email path possible — is documented in `13_EMAIL_SYSTEM.md` § Data Model.

---

## Schema V6 — Cashflow Forecast + PhotoAnnotation.renderedPhotoURL (2026-05-19)

Consolidated iOS SwiftData schema bump shipped as ops-ios merge commit `41204a5` (cashflow-forecast → main). Purely additive over V5; SwiftData lightweight migration handles the V5 store transparently because no existing column is renamed, retyped, or made non-optional.

**Adds two new `@Model` entities** (`OPSSchemaCommon.v6ForecastModels`):

- `PaymentMilestone` — iOS parity for the existing server `payment_milestones` table (was Supabase-only until V6). Read-side only in v1; estimate-form writes still go via the `EstimateService` payload.
- `RecurringExpense` — owner-managed recurring outflows (rent, insurance, payroll, subscriptions). Drives the recurring layer of the cashflow forecast.

These new model types distinguish V6 from V5 in the migration graph because `v6ForecastModels` is appended. That avoids duplicate adjacent checksums; it does **not** make later edits to a released model safe.

**`PhotoAnnotation.renderedPhotoURL` compatibility note.** The property added by ops-ios commit `6b62f40` is part of the compatibility shape now locked for V1–V14. The former guidance that shifting every historical hash by the same delta is safe was incorrect for any version already installed: Core Data matches an on-disk store against an absolute model checksum, not merely against the differences between adjacent stages. Once a schema is declared for release, its model graph is immutable. Any later persistent-property change requires a frozen pre-change model, a new versioned schema, and an adjacent migration stage.

**The duplicate-checksum crash this resolved.** Pre-merge, a sibling-WIP attempt to mint a V6 whose models list was identical to V5 collapsed the stage chain and produced `Duplicate version checksums detected` at `ModelContainer` initialization. The merge consolidated V6 around the cashflow-forecast model set. This is separate from unknown-version error 134504, which occurs when an installed store's absolute checksum matches no schema in the plan. See the V16 section below for the permanent release rule.

**Migration:** `OPSMigrationPlan.addForecastModelsV5toV6` — `MigrationStage.lightweight(fromVersion: OPSSchemaV5.self, toVersion: OPSSchemaV6.self)`. No data transform.

**Supabase side:** the cashflow tables already shipped earlier (`recurring_expenses`, `forecast_alerts`, additive columns on `payment_milestones` + `expense_settings` — see § Cashflow Forecast below). `renderedPhotoURL` mirrors `project_photo_annotations.rendered_photo_url` (nullable text); sync write lives in `DimensionedPhotoSyncManager`.

## Schema V8 — Catalog Setup Data Foundation (2026-05-21)

This was the current iOS SwiftData schema after the catalog/inventory setup foundation pass. V7 introduced `ProjectVinylOrderMarker`; V8 was the next additive bump. Historical V3-V7 schemas keep a frozen legacy `ProductBundleItem` model, and V8 is the first schema stage that swaps in the live top-level `ProductBundleItem` shape with relationship metadata.

**Adds two new `@Model` entities** (`OPSSchemaCommon.v8CatalogSetupModels`):

- `CatalogStockUnit` — local parity for `catalog_stock_units`, the physical roll/offcut/lot layer under `catalog_variants`.
- `CatalogProductOptionMapping` — local parity for `catalog_product_option_mappings`, the explicit bridge between catalog variant axes and Product option axes/values.

**Extends `ProductBundleItem` additively** with `relationshipKind`, `suggestionReason`, and `compatibilitySelectorJSON`. Existing rows decode as `relationshipKind = .required`. Runtime sync/write paths are schema-capability gated so targets without the 2026-05-21 setup migrations skip `catalog_stock_units` / `catalog_product_option_mappings` and omit bundle relationship columns.

**Migration:** `OPSMigrationPlan.addCatalogSetupModelsV7toV8` — lightweight `V7 → V8`. No data transform; the next catalog sync hydrates server rows.

**Supabase side:** migrations `migrations/2026-05-21-04-catalog-stock-units.sql` and `migrations/2026-05-21-05-catalog-setup-relationships.sql` are additive and must be applied only to an approved target. The second migration intentionally does not add a DB-level matrix-signature uniqueness constraint because live preflight found an active Diverter duplicate signature. iOS validation blocks new duplicate matrix signatures before commit.

**iOS setup UI:** `CatalogSetupFlowSheet` refreshes `CatalogSchemaCapabilityGate` and blocks before the first repository write if the draft includes stock units but `catalog_stock_units` is unavailable. It writes through the existing repository layer only after preflight: `CatalogRepository` creates the family, catalog axes, option values, variants, and variant-option joins; `CatalogStockUnitRepository` creates physical roll/offcut rows with label, lot code, original length, remaining length, width, unit, location, status, and notes; `CatalogProductOptionMappingRepository` creates axis/value bridges only after the capability gate confirms `catalog_product_option_mappings`; `ProductRepository` links an optional sellable Product through `products.linked_catalog_item_id`. Draft validation treats duplicate SKUs as warnings, duplicate matrix signatures as blockers, and product-option value mappings as blockers when a selected product value does not belong to the selected product option. Available stock-unit rows (`full` / `partial`) mirror their aggregate into the created `catalog_variants.quantity`; dimensional roll/offcut rows mirror area when length and width share a unit. Reserved, consumed, and scrapped rows do not inflate availability.

## Schema V16 — App-update migration reliability (2026-07-16)

Ops-ios commit `a554ee7c` repairs app-update launches that failed with `NSCocoaErrorDomain 134504` (`Cannot use staged migration with an unknown model version`). V15 referenced the live `Opportunity` and `DeckDesign` types from every historical schema. Later persisted-property additions changed the absolute checksums of V1–V15 after V15 was already installed:

- `Opportunity.images`, `Opportunity.latitude`, and `Opportunity.longitude` (ops-ios commit `daee6491`)
- `DeckDesign.opportunityId` (ops-ios commit `c06f81b3`)

V1–V15 now register exact frozen pre-addition shapes (`OPSSchemaLegacyOpportunityV15.Opportunity` and `OPSSchemaLegacyDeckDesignV15.DeckDesign`). V16 is the first schema that registers the widened live types. `OPSMigrationPlan.addOpportunityMediaAndDeckLeadV15toV16` is a lightweight V15→V16 stage; the new collection defaults empty and the three new optional values default `nil`, preserving all historical rows. Sources: `OPS/DataModels/Migrations/OPSSchemaCommon.swift`, `OPS/DataModels/Migrations/OPSSchemaV16.swift`, and `OPS/DataModels/Migrations/OPSMigrationPlan.swift`.

Production storage is explicitly pinned to App Group `group.co.opsapp.ops` through `OPSModelStore`. The app-root container uses in-memory storage without an App Group when hosted by XCTest; migration tests use isolated temporary disk stores. Container error 134504 is never a reset signal: startup reports the exact store path and terminates without deleting or replacing `default.store` or its WAL/SHM sidecars. Local-only or not-yet-synced work must never be deleted as recovery. Sources: `OPS/OPSApp.swift` and `OPS/Utilities/OPSModelStore.swift`.

`OPSTests/Fixtures/swiftdata-released-schema-fingerprints.json` locks Core Data's compatibility checksum for every declared schema V1–V16. Any future persistent model change must freeze the prior shape, add a new schema and adjacent stage, then extend the fixture. A copied installed V15 store reported checksum `mFW4cSIxny6ksYQ8VtN0+K4F6DUNqLzqZMwmzYPIQ4k=`, exactly matching the frozen V15 declaration, and migrated to V16 without row loss. Test source: `OPSTests/DataModels/AppUpdateMigrationTests.swift`.

## Schema V25 — Project primary-contact compatibility repair (2026-08-21)

Ops-ios commit `79a5df89` repairs a real-device launch failure introduced when P1-18 persisted `Project.primarySubClientId` directly on the long-lived `Project` model. Because V4–V24 all referenced that live model graph, the new property changed every released compatibility checksum. A valid installed V24 App Group store then failed at startup with `NSCocoaErrorDomain 134504` (`Cannot use staged migration with an unknown model version`). The launch path preserved `default.store` and terminated; it did not delete, replace, or mutate the phone store.

`Project.primarySubClientId` is now `@Transient`. V25 adds the independent `ProjectPrimaryContactSelection` SwiftData entity, keyed by project ID, with the nullable selected sub-client ID and source/sync timestamps. `OPSMigrationPlan.addProjectPrimarySubClientV24toV25` is an additive lightweight V24→V25 stage. The V24 checksum remains `MRC17UrUeJf5F8UUA9R6PxyQGisAb6y/65ntfSBajlI=`; V25 is frozen as `oDrDy3ePGUW2ZiuwOISzdvuUZ8yf5LtXt42AFLxtTrs=`. Sources: `OPS/DataModels/Project.swift`, `OPS/DataModels/Migrations/OPSSchemaV25.swift`, `OPS/DataModels/Migrations/OPSMigrationPlan.swift`, and `OPSTests/Fixtures/swiftdata-released-schema-fingerprints.json`.

The projection is not a disposable cache. Local project-contact changes persist it in the same SwiftData transaction as the durable sync operation. Inbound project insert/update paths upsert it only when the corresponding server field is accepted, and startup/relationship-linking paths hydrate the transient `Project` convenience property from it. This preserves offline and cold-launch behavior without modifying any released Project schema. The focused migration proof creates a V24 disk store, migrates it through the production plan, verifies the Project row, writes and reloads the V25 projection, and asserts all declared schema fingerprints remain immutable. Sources: `OPS/Utilities/DataController.swift`, `OPS/Network/Sync/InboundProcessor.swift`, `OPS/Network/Sync/ProjectCacheMerge.swift`, `OPS/Utilities/DataActor.swift`, and `OPSTests/DataModels/AppUpdateMigrationTests.swift`.

## Expense Auto-Batching — Envelope Schema (2026-06-01)

Additive schema deltas for the server-authoritative expense-batching brain (full behavior in `09_FINANCIAL_SYSTEM.md § Server-Authoritative Expense Envelopes`; RPCs in `04_API_AND_INTEGRATION.md`). All additive — respects the iOS cross-release sync constraint; 3.0.2 unaffected.

### `expense_batches.status` — new value `open`

`expense_batches.status` is plain `text` (no enum, no CHECK constraint, verified on prod), so the new filling-phase value needs no type change. Lifecycle: `open` (filling) → `pending_review` (auto-sent) → `approved` / `auto_approved` (done). `auto_approved` envelopes live in History.

### Payout columns on `expense_batches` (2026-07-10)

| Table | Column | Type | Default | Purpose |
|-------|--------|------|---------|---------|
| `expense_batches` | `paid_at` | `timestamptz NULL` | — | When the operator recorded the envelope as paid out to the submitter. `NULL` on an approved envelope = money still owed. Written only by `mark_expense_batch_paid` / cleared by `unmark_expense_batch_paid`. |
| `expense_batches` | `paid_by` | `uuid NULL` | — | Who recorded the payout (`expenses.approve` holder, derived server-side from the session). |

Additive + nullable — iOS cross-release safe (shipped clients ignore unknown columns). Deliberately **not** a new `status` value: the paid stage is orthogonal to the approval lifecycle, and per-line "paid" rides the existing `expenses.status = 'reimbursed'` value shipped iOS already renders. Migration `migrations/20260710180000_expense_batch_paid.sql`; behavior in `09_FINANCIAL_SYSTEM.md § OPS-Web Expense Console + Paid-Out Lifecycle`.

### Widened active-envelope unique index

`expense_batches_open_unique` — partial unique index on `(company_id, submitted_by, period_start, period_end, scope_project_id)` `NULLS NOT DISTINCT`, widened from `WHERE status = 'pending_review'` to **`WHERE status IN ('open','pending_review') AND amendment_number = 0`** so the new `open` (filling) phase is also one-active-envelope-per-scope (race-safe get-or-create). Migration `migrations/20260601210311_expense_envelope_schema.sql`.

### Additive column on `expense_settings`

| Table | Column | Type | Default | Purpose |
|-------|--------|------|---------|---------|
| `expense_settings` | `auto_submit_grace_days` | `integer NOT NULL` | `7` | Days after a period ends before its `open` envelope auto-sends. Read by `expense_envelope_sweep()`. Short cadences (weekly/biweekly) would set 1–2. |

### Placement trigger, sweep, RLS

- `trg_place_expense` (AFTER INSERT or UPDATE OF status, expense_date, batch_id on `expenses`) → `place_expense(uuid)` files every non-draft, unbatched expense into its envelope by the expense's date. `migrations/20260601210846_place_expense_trigger.sql`.
- pg_cron `expense_envelope_sweep_daily` (15:15 UTC) → `expense_envelope_sweep()` auto-sends due envelopes, adopts orphans (safety net), rolls stragglers forward. `migrations/20260601213757_expense_envelope_sweep_deep_link_expense.sql`.
- `expense_batches_approve_scope` — RESTRICTIVE UPDATE RLS policy gating `approved`/`auto_approved` transitions to `expenses.approve` holders. `migrations/20260601211914_expense_batches_rls_approve_scope.sql`.

## Cashflow Forecast (2026-05-11)

Supabase schema deltas for the Cashflow Forecast feature (Card 6 of the BOOKS hero carousel). All deltas are **additive** — no rename, retype, or drop. Detailed semantics in `09_FINANCIAL_SYSTEM.md § Cashflow Forecast`. iOS SwiftData parity ships in `OPSSchemaV6` (consolidated with the PhotoAnnotation rendered-deliverable property — see § Schema V6 above).

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

Landed in the cashflow-forecast → main merge (ops-ios `41204a5`, 2026-05-19). Purely additive over V5. Adds two new `@Model` entities:

- `PaymentMilestone` — iOS parity for the existing server table (deferred from earlier estimate work). Read-side only in v1; estimate form writes via `EstimateService` payload.
- `RecurringExpense` — CRUD-capable, mirrors the server table.

Migration: `OPSMigrationPlan.addForecastModelsV5toV6` — lightweight `V5 → V6` stage. No data transform, no field rename.

## Durable Email Attachments (prepared 2026-07-15)

Migrations `20260714230000_email_attachment_persistence` and `20260714232000_guarded_email_thread_reassignment` make email files OPS-owned, private, mailbox-scoped records. They are prepared in code and are not live until deployed separately.

`email_attachments` uses canonical identity `(company_id, connection_id, message_id, attachment_id)`. Each row also records the exact `activity_id`, provider thread and MIME-part identity, optional current `opportunity_id`, attribution state, provider/reporting metadata, detected MIME, verified byte count, SHA-256, private object key, ingest state, and retry/error timestamps. The exact-identity trigger locks and re-reads the activity before accepting lead attribution; a stale worker result cannot attach a file to a lead after reassignment. Once stored, detected MIME cannot be downgraded by later provider metadata.

`email_attachment_scans` is one durable exact-message job per activity. `email_attachment_inspection_jobs` is one independently leased acceptance/vision job per canonical attachment. Both queues use generation fencing, `FOR UPDATE SKIP LOCKED`, bounded leases, exponential retry, and terminal `failed` state. The activity-insert trigger queues every email, including provider false negatives for inline content. The private `email-attachments` Storage bucket has no browser object policy; API routes stream authorized bytes through OPS.

Attribution begins only from `(company_id, email_connection_id, email_message_id)`. Inbound sender or outbound external recipients must match the activity's current lead/client/contact identity, and `match_needs_review` always fails closed. Activity reassignment increments scan/inspection generations and re-evaluates cached acceptance. Lead merge uses guarded evidence-bound RPCs. Won conversion needs no duplicate file row because projects retain `opportunity_id`.

**Related-photo reconciliation repair (2026-08-20; applied and runtime-verified 2026-08-21).** Production attachment discovery can create the canonical descriptor before `content_sha256` exists. The prior `private.reconcile_related_email_conversion_photo_sources(uuid, uuid, uuid, text, text)` reused `related_attachment` as both its PL/pgSQL loop record and the `email_attachments` relation alias, so PostgreSQL resolved the unassigned record first and aborted the insert with `record "related_attachment" is not assigned yet`. OPS-Web commit `8c24e50d` adds forward migration `20260820172857_fix_related_attachment_record_shadowing.sql`: it uses a scalar attachment ID and a distinct relation alias, deliberately returns while the hash is NULL or not lowercase 64-character hex, and otherwise preserves the existing company/hash + opportunity-or-thread match and `(occurred_at, id)` order. The signature, `SECURITY DEFINER` boundary, fixed `search_path`, and API-role revokes are unchanged. The exact SQL was applied to production as ledger row `20260821202539_fix_related_attachment_record_shadowing` and is mirrored at `migrations/20260821202539_fix_related_attachment_record_shadowing.sql`. Independent readback at `2026-08-21T20:26:08Z` confirmed the scalar loop, NULL guard, distinct relation alias, deterministic order, no old record/alias collision, and no execute privilege for `anon`, `authenticated`, or `service_role`; all six `email_attachments` triggers remained enabled. The repair is also an ancestor of OPS-Web `main` commit `6b69551a`, which Vercel deployed to `app.opsapp.co` as `dpl_HaQMyTLrfqKZ2tYWD237oZmsJ6vg`. The first unblocked natural attachment-worker run returned HTTP 200 at `2026-08-21T21:03:04Z`, completed three scans, and was followed by three canonical descriptor inserts at `21:04:04Z` through the repaired NULL-hash path with no collision recurrence. Natural production traffic has not yet exercised the later non-NULL hash sibling-matching branch. Previously dropped attachment descriptors are not backfilled by this DDL and require separately approved recovery. Bug: `4501a2dc-2b1a-427a-9c8c-04bd6fcdad74`.

## Phase C Lead Intelligence Workload (production live 2026-08-21)

OPS-Web migration `20260820204454_phase_c_lead_intelligence_workload.sql`
(commits `b293d1dd` through `8c86394e`) adds three server-authoritative tables.
It is applied in production under ledger name
`phase_c_lead_intelligence_workload_20260820204454` (version
`20260821201943`). Companion production migrations
`phase_c_workload_fk_indexes_20260821202230` and
`phase_c_handoff_opportunity_fk_index_20260821202400` cover every introduced
foreign key. Independent readback found 114 existing opportunities fenced at
their manual correction boundary, zero queued workload rows, forced RLS, and
service-role-only worker capability. No opportunity, customer, appointment, or
calendar row was mutated as deployment proof.

### `opportunity_phase_c_work`

One row per opportunity is the durable high-water mark for meaningful,
successfully projected correspondence. The correspondence-event trigger moves
`required_event_id` forward only by `(occurred_at, id)`, clears stale component
errors, and makes the row due again. Four independent event-fenced completion
columns cover `summary`, `lifecycle`, `commercial`, and `event_handoff`.
`component_outcomes` and `component_errors` preserve component-level truth;
one model failure cannot erase the dirty marker or prevent deterministic later
components from committing. Claims use bounded leases and `FOR UPDATE SKIP
LOCKED`; failure records an error and exponential backoff, while an
acknowledgement can clear only the exact event snapshot it leased. A newer
event supersedes the worker without losing work.

### `opportunity_lifecycle_decisions`

Append-only decision evidence precedes every lifecycle mutation. Each receipt
stores company, opportunity, exact source event, decision kind/key, proposed
stage or outcome, confidence, evidence event IDs, evidence provider-message
IDs, reason, initial disposition, and review reason. The evidence columns are
immutable; only settlement fields may move a decision from `proposed` to
`applied`, `skipped`, `review`, or `failed`. The uniqueness key is
`(opportunity_id, source_event_id, decision_kind, decision_key)`, so replay is
idempotent and a conflicting replay fails closed.

### Manual stage correction boundary

`opportunities.stage_manual_boundary_event_id`,
`stage_manual_boundary_at`, and `stage_manual_corrected_at` replace the old
permanent meaning of `stage_manually_set` for active stages. A human stage edit
captures the newest meaningful correspondence as its evidence boundary. Phase
C may advance an active stage only from strictly newer evidence, and the
guarded apply RPC rechecks stage, assignment version, decision receipt, and
boundary under the opportunity row lock. Terminal manual truth remains inert;
an automated apply clears `stage_manually_set` only after it proves newer
evidence and commits the allowed monotonic transition.

### `phase_c_bilateral_event_handoffs`

This is the provider-agnostic P1-16 to P1-17 envelope. A row binds one
idempotency key to the opportunity, immutable lifecycle decision, distinct
proposal and acceptance events, requested OPS owner, event kind/title,
resolved start/end/timezone, location, attendees, and either `ready` or
`review`. A `ready` row structurally requires bilateral evidence, a resolved
owner, time interval, timezone, and both evidence events. `canonical_event_kind`,
`canonical_event_id`, and `consumed_at` are reserved for P1-17's guarded OPS
event/site-visit creation. This table does not create or synchronize a provider
calendar event.

## Lead Intake Identity and Commercial Guards (live 2026-07-29)

These migrations are applied to production and mirrored in `migrations/`:

- `20260728160000_property_address_identity_boundary.sql`
- `20260728161000_authoritative_staff_email_aliases.sql`
- `20260728162000_guarded_customer_decline_lifecycle.sql`
- `20260728163000_guarded_staff_false_lead_correction.sql`
- `20260729170000_exact_recovery_latest_event_lifecycle.sql`
- `20260729173000_fix_staff_false_lead_notification_company_cast.sql`
- `20260729174500_preserve_referenced_staff_false_lead_client.sql`

### Property address qualification

`private.normalize_property_address(address, include_unit)` is the single
database qualification and normalization boundary for relationship identity,
duplicate/preflight checks, and email-to-project conversion. The compatibility
helpers `private.normalize_address` and
`private.normalize_email_project_dedupe_address` delegate to it. Locality,
municipality, neighbourhood, region, area, postal-locality, and PO-box-only
strings return the empty non-identity value. An ordinary civic identity requires
a bounded civic number, street name, and recognized street-type suffix; a
number followed only by a locality or suffix-less label does not qualify.
Supported highway/range-road, rural-route/site/box, lot/concession or
lot/block/plan, and parcel/PID formats also qualify. Units remain part of the
identity when requested, including case-insensitive `Unit`, `Suite`, and `Apt`
forms.

The migration rewrites function behavior only. It does not rewrite existing
opportunity, client, project, activity, or correspondence data.

The application uses the same property qualifier at both customer-contact
resolution and the final client/opportunity enrichment write boundary. Parsed
form labels such as `Location: Victoria`, forwarded-message location fields,
AI/import facts, attachment reprocessing, and recovery replay may retain their
locality text in source metadata or message context, but cannot populate
`clients.address`, `opportunities.address`, or address provenance unless the
value is a qualified civic, rural-property, or parcel identity. Qualified
values retain their original cleaned display string, including unit detail.

### `user_email_aliases`

| Column | Type | Contract |
|---|---|---|
| `id` | `uuid` | Primary key |
| `company_id` | `uuid` | Required company FK; unique identity boundary with normalized email |
| `user_id` | `uuid` | Required active same-company user FK |
| `email` | `text` | Lowercase trimmed exact email; immutable |
| `status` | `text` | `pending`, `verified`, or `rejected` |
| `source` | `text` | `signature_corroborated` while pending/rejected; `operator_verified` after explicit verification |
| `evidence` | `jsonb` | Required object containing auditable provider/roster evidence |
| `first_seen_at`, `last_seen_at` | `timestamptz` | Candidate observation window |
| `reviewed_at`, `reviewed_by` | nullable timestamp/same-company user FK | Required for every final administrator decision |
| `verified_at`, `verified_by` | nullable timestamp/same-company user FK | Equal to the review audit only for `verified`; always null for `pending`/`rejected` |
| `created_at`, `updated_at` | `timestamptz` | Record lifecycle |

`(company_id, email)` is unique. Company/user/email/created identity is
immutable, and a final review decision/audit cannot be rewritten. Composite
foreign keys enforce same-company ownership, reviewer, and verifier identity. A
trigger rejects inactive users and aliases that belong to another registered
teammate. Alias evidence is readable only by same-company administrators or
service processing. The service role has no direct table-write grant:
signature-corroborated candidates can be recorded only through
`record_staff_email_alias_candidate_as_system`, and final review can occur only
through `review_user_email_alias` by a same-company administrator. Rejected
reviews never populate verification authority. Pending evidence never grants
verified staff identity, but the exact pending mailbox remains quarantined as
outbound/review on later messages so it cannot become a lead while awaiting a
decision.

### Guarded customer-decline write

`apply_email_opportunity_declined_disposition(...)` is a service-role-only RPC,
not a client-writable table surface. Under one opportunity row lock it verifies
mailbox, sender, message, projected correspondence, assignment, stage, event
high-water, and terminal precedence. It writes `opportunities`, one
`stage_transitions` row for a new Lost transition, and one active
`opportunity_dispositions` row atomically. Evidence stores the connection,
provider message, decisive event, reason code, signal, and evaluated high-water
event. Exact retry resolves the existing disposition; stale or unauthorized
evidence makes no business-state write. A retry that extracts a more specific
`price` reason from the same decisive rejection may replace an active generic
`customer_declined` disposition without adding another stage transition. The
reverse downgrade is ignored. Every replaced disposition records both
`superseded_at` and `superseded_by`, preserving a complete one-way provenance
chain.

### `lead_intake_correction_runs`

| Column | Type | Contract |
|---|---|---|
| `id` | `uuid` | Primary key |
| `company_id` | `uuid` | Required company FK and correction tenant boundary |
| `correction_key` | `text` | Trimmed stable correction identity; unique within the company |
| `actor_user_id` | `uuid` | Required same-company administrator who authorized the correction |
| `source_opportunity_id` | `uuid` | Required same-company false-lead record retained as the audit source |
| `manifest_sha256` | `text` | Exact 64-character lowercase SHA-256 for the complete frozen manifest |
| `entry_a_sha256`, `entry_b_sha256` | `text` | Exact content addresses for the two provider messages corrected by the run |
| `input_spec` | `jsonb` | Complete immutable expected-row specification supplied to the guarded RPC |
| `result` | `jsonb` | Generated customer/lead ids, moved evidence ids, assignment result, and scan generations |
| `applied_at` | `timestamptz` | Transaction commit timestamp for the correction |

`lead_intake_correction_runs` has RLS enabled and no direct write grant for any
role. The service role may read receipts; only
`apply_staff_authored_false_lead_correction_guarded(...)` can insert one. The
RPC is service-role-only with an empty search path. It locks the company,
mailbox, administrator, active staff roster identity, protected opportunity
snapshots, exact activities/events/thread projections, attachment scan, false
notifications, assignment audit, generated draft, and field provenance before
writing. Any altered selector, row set, timestamp, terminal state, project
link, assignment version, content hash, or retry payload aborts the entire
transaction.

The correction verifies or promotes only the exact alias for the exact active
staff user; it never infers identity from a name, partial phone, shared public
email domain, or location. It creates a new client/opportunity only from an
external recipient plus a property-qualified address and a message-scoped
source key, then assigns through the canonical system assignment RPC. Exact
retry returns the immutable correction receipt and performs no second write.
Staff-authored events become `outbound` / `ops`, their activities, canonical
thread links, inbox cache rows, and customer ownership move together under the
existing child-reparent capabilities, and attachment attribution is requeued
with a required generation increment. A protected existing Won/project target
may receive older correspondence, but its stage, manual flag, assignment,
project mirrors, and `updated_at` must remain byte-for-byte unchanged.

After all customer evidence is retained on the correct records, the RPC
resolves the false notifications, marks the false generated draft discarded in
OPS without changing the provider mailbox, records a discarded disposition and
stage transition, and soft-deletes the false opportunity. The notification
scope comparison explicitly casts the text-backed notification tenant key to
the RPC's UUID company identity. The source client is soft-deleted only after a
schema-wide `client_id`/`client_ref` reference scan proves zero remaining use;
otherwise it is preserved. The immutable result records both
`source_client_deleted` and `source_client_reference_count`, making that
retention decision auditable and replay-stable. Provider mutations are disabled
and recorded as such in both the assignment metadata and immutable correction
receipt.

### Latest-event exact recovery lifecycle fence

`private.assert_exact_message_lifecycle_recomputable(...)` permits an
exact-message recovery to move the current lifecycle high-water only when the
source lifecycle is passive, the durable state points exactly at the message
being moved, an earlier projected meaningful event remains to become the new
high-water, and no unresolved `leads_waiting` notification exists. Drafts,
applied lifecycle actions, follow-up counters, stale/protected state, active
notifications, missing prior history, or a state/event mismatch continue to
raise `exact_recovery_lifecycle_not_reconstructible` before any repair write.

The pre-existing historical-event path remains unchanged: moving a non-latest
event is allowed only when a later meaningful event already owns the
high-water and the event-scoped notification history is inert. The recovery
transaction then recomputes source and target lifecycle projections before it
returns, including when attachment attribution continues asynchronously.

## Review Swipe Safeguard Tables (2026-07-21)

### `payment_review_writeoff_receipts`

Durable exactly-once receipts for Payment Review write-offs. The primary key is `(company_id, project_id, idempotency_key)`. Each row stores the canonical actor, written-off invoice count and balance, and creation timestamp. The table has forced RLS, no client policies or grants, and service-role read access only; the guarded write-off RPC owns writes and replay reads. Foreign-key indexes cover `project_id` and `actor_user_id` for lifecycle operations. Source migrations: `migrations/20260721120000_payment_review_atomic_actions.sql` and `migrations/20260721123000_payment_review_receipt_fk_indexes.sql`; live versions `20260721101658` and `20260721102425`.

### `payment_reminder_generation_claims`

Short-lived service-only claims keyed by `(company_id, source_id)`, where `source_id` is the canonical invoice UUID plus reminder tier. Rows carry an opaque claim token, claim time, and ten-minute expiry. The claim transaction rechecks durable approval actions before acquiring, so concurrent requests do not duplicate paid drafting or queue work. Forced RLS and revoked client grants keep this table outside the browser and iOS data surface. Source migration: `migrations/20260721122000_payment_reminder_delivery_guards.sql`; live version `20260721102146`.

## Agent Control Plane Schema (applied 2026-08-18 UTC)

The gated agent-control-plane wave (Option B, `44f6401c` lineage) landed in prod as twelve migrations applied in one atomic transaction on 2026-08-18 ~05:07 UTC, immediately after the `20260818011925_agent_wave_reshape_to_gated_pre_state` reshape returned prod to the pre-wave base. Ledger rows carry repo version keys; every row's `statements[1]` is md5-identical to its file in `migrations/` (byte-exact, single trailing newline stripped).

Source migrations, in apply order: `migrations/20260807213219_phase_c_auto_send_source_fence.sql`, `20260807220000_agent_job_conversation_memory.sql`, `20260807223000_agent_correspondence_evidence_read.sql`, `20260807224500_agent_provider_delivery_sources.sql`, `20260809180033_approved_action_email_reconciliation_recovery.sql`, `20260809183000_phase_c_auto_send_generation_reservations.sql`, `20260811120000_agent_job_conversation_context_read.sql`, `20260812120000_agent_operational_schedule_readiness.sql`, `20260812121000_agent_schedule_confirmation_delivery_guard.sql`, `20260813120000_agent_job_communication_participants.sql`, `20260814120000_agent_job_catalog_reads.sql`, `20260814190000_agent_phase_c_source_turn_read.sql`.

Schema landed by the wave:

- **Conversation memory (public):** `job_conversations`, `job_conversation_anchors`, `job_conversation_turns`, `job_conversation_redaction_events`, `job_memory_versions`, `job_memory_version_evidence` — gated-lineage column models (`turn_sequence`, `source_state_revision`, `provider_delivery_source_id/sha256`; see the divergence notes in the reshape migration header for how these differ from the dropped release-lineage twins).
- **Provider delivery provenance (private):** `agent_provider_delivery_sources`, `phase_c_auto_send_source_fences`, `phase_c_auto_send_generation_reservations`.
- **Read-revision tracking (private):** `agent_operational_read_revisions`, `agent_job_history_revisions`, `agent_contactability_address_revisions`, plus `bump_*`/`advance_*` trigger families on companies, projects, project_tasks, users, clients, sub_clients, opportunities, task_types, project_photos, estimates, invoices, stage transitions, lifecycle/mutation outboxes, and the conversation tables.
- **Authority (private/public):** `agent_provider_outbound_authority_attestations`, `agent_control_plane_tenant_roots`.
- **Schedule confirmation:** `project_tasks.confirmed_schedule_version` (bigint) with constraint `project_tasks_confirmation_version_current`, the `confirm/unconfirm/prepare` RPC family (see `04_API_AND_INTEGRATION.md`), and delivery guards on `agent_actions` (`guard_purpose_schedule_email_action_update`).
- **Reconciliation recovery:** claim/renew/complete/fail/release RPC family over `approved_action_email_intents` plus the `approved_action_email_reconciliation_alert_outbox` table.

**Post-apply corrective (2026-08-18, ledger `20260818052612`):** the wave added the named version-gate constraint `task_schedule_automation_outbox_task_schedule_version_check` (which exempts the two new dispatch kinds from `task_schedule_version >= 1`) but failed to drop its July-era inline-auto-named twin `task_schedule_automation_outbox_check`, so every schedule confirm/unconfirm on a never-rescheduled task (`schedule_version = 0`) aborted at the dispatch-enqueue insert with `23514`. Caught by the deferred Maverick verification round-trip minutes after deploy, before the first `auto-confirm-schedules` cron firing of the new code — zero customer impact. Fix: `migrations/20260818052612_drop_stale_task_schedule_outbox_version_check.sql` drops the stale twin (successor asserted present first). A full constraint sweep of the wave-touched tables found no other stale twin of this class.

**Timezone deviation (temporary):** `private.agent_assert_operational_timezone_rules()` — asserted at apply time by `20260812120000` and at runtime by the schedule-read RPCs — is date-gated: it raises a WARNING instead of erroring until `2026-09-15 00:00:00+00`, because the Supabase platform image (17.6.1.063) predates tzdata 2026c and returns pre-permanent-DST offsets for November 2026 instants. Booking horizons keep the damage window empty until ~mid-September. A Supabase support ticket is open; when the platform probe returns 04:30/05:30/11:30 for the canonical November instant, the strict assert must be restored by a follow-up migration the same day. Debt row: `bug_reports` `212987a4` (high).

## MCP OAuth Authorization Server Schema (applied 2026-08-18 UTC)

Ledger `20260818155813_mcp_oauth_authorization_server` (mirrored byte-exact in `migrations/`). Storage for the Claude-first MCP mount — see `04_API_AND_INTEGRATION.md` § "OPS Remote MCP Server — P1 Mount". Applied to production and live. The consuming routes are deployed at `https://app.opsapp.co/api/mcp`; a dynamically registered Claude client and one unrevoked grant were verified in production on 2026-08-20.

**Every table lives in `private` with ALL privileges revoked from `public`, `anon`, `authenticated`, and `service_role`.** The only access paths are the eleven owner-executed `SECURITY DEFINER` RPCs below, each gated on `auth.role() = 'service_role'` (raising `42501 access_denied` otherwise) with a pinned `search_path`. PostgREST never sees the tables. Verified live: 5 tables, 11 RPCs, zero table grants to any role, service_role-only EXECUTE, and the non-service gate live-fired against production.

| Table | Purpose |
|-------|---------|
| `private.mcp_oauth_clients` | Dynamically registered public clients. `token_endpoint_auth_method` CHECK-constrained to `'none'` — no confidential client, no secret, ever. |
| `private.mcp_oauth_authorization_codes` | Single-use codes keyed by SHA-256 digest. Carries the PKCE challenge (method CHECK-constrained to `S256`), redirect URI, RFC 8707 resource, and `minted_grant_id` — the last enabling RFC 6749 §4.1.2 replay defense. |
| `private.mcp_oauth_grants` | One grant per `(user, company, client)`, enforced by a unique partial index on live rows, so re-consent rotates rather than accumulates. |
| `private.mcp_oauth_tokens` | Access and refresh tokens as SHA-256 digests, with `family_id` for reuse detection and `rotated_to_hash` for the rotation chain. |
| `private.mcp_request_audit` | Append-only. Its single writer is `append_mcp_request_audit_as_system`; no role holds UPDATE or DELETE. |

**No plaintext credential ever reaches a table** — codes and tokens are stored only as digests.

Key behaviors implemented in the RPCs rather than the application: presenting a consumed authorization code revokes the grant it minted and all of that grant's tokens; presenting an already-rotated refresh token revokes the entire token family and its grant; minting a grant revokes any prior live grant for the same binding; and `revoke_mcp_oauth_token_as_system` follows RFC 7009 by returning true even for an unknown token. All were exercised live during the mount's E2E.

**Legacy identifier note.** The repair of the Task 13 read RPCs (ledger `20260818174706`, `20260818175549`) added `private.agent_uuid_from_legacy_text(text)` — a shape-guarded immutable cast. It exists because `public.projects.id` is `uuid` while eleven child tables (`activities`, `estimates`, `project_notes`, `project_photos`, `project_team_members`, `site_visits`, and others) store `project_id` as `TEXT`, and `projects.opportunity_id` is `TEXT` alongside the `uuid` `projects.opportunity_ref`. Any new SQL joining these columns must cast explicitly; the wave's Task 13 reads did not, and failed at runtime the first time they executed.

**End of Data Architecture Documentation**
