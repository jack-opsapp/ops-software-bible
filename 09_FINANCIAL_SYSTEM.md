# 09_FINANCIAL_SYSTEM.md

**OPS Software Bible - Pipeline, Estimates, Invoices & Financial Architecture**

**Purpose**: Complete documentation of the OPS financial system — pipeline/CRM, estimates, invoices, payments, products catalog, and accounting integrations. All financial data lives in **Supabase** (PostgreSQL), separate from operational data in Bubble.io.

**Last Updated**: February 28, 2026
**Source Reference**: `C:\OPS\ops-web\src\lib\types\pipeline.ts`, `src\lib\api\services\`, iOS source at `OPS/OPS/`

---

## Table of Contents

1. [Dual-Database Architecture](#dual-database-architecture)
2. [Pipeline / CRM System](#pipeline--crm-system)
3. [Estimates System](#estimates-system)
4. [Invoices System](#invoices-system)
5. [Products & Services Catalog](#products--services-catalog)
6. [Payments](#payments)
7. [Expense Tracking System](#expense-tracking-system)
8. [Accounting Integrations](#accounting-integrations)
9. [Activity Timeline & Follow-Ups](#activity-timeline--follow-ups)
10. [Supabase Schema Reference](#supabase-schema-reference)
11. [Service Layer Patterns](#service-layer-patterns)
12. [Business Rules & Constraints](#business-rules--constraints)
13. [iOS Implementation](#ios-implementation)

---

## Dual-Database Architecture

OPS Web uses Supabase as its primary backend, with Bubble.io retained as legacy for some core entities during migration:

| Data Domain | Backend | Rationale |
|---|---|---|
| Projects, Tasks, Clients | Supabase (PostgreSQL) — iOS primary; Bubble legacy on web | Migrating to Supabase |
| Company, Users | Supabase (PostgreSQL) — iOS primary; Bubble legacy on web | Migrating to Supabase |
| Pipeline Opportunities | Supabase (PostgreSQL) | Relational, real-time, complex queries |
| Estimates, Invoices, Line Items | Supabase (PostgreSQL) | Financial data, needs DB triggers |
| Products Catalog | Supabase (PostgreSQL) | Per-company catalog |
| Payments | Supabase (PostgreSQL) | Insert-only, trigger-maintained balances |
| Accounting Connections | Supabase (PostgreSQL) | OAuth token storage |
| Expenses & Receipts | Supabase (PostgreSQL) | Expense tracking, OCR, batch approval |
| Tax Rates | Supabase (PostgreSQL) | Per-company tax config |
| Pipeline Stage Config | Supabase (PostgreSQL) | Per-company customization |

**Env vars required for Supabase:**
```
NEXT_PUBLIC_SUPABASE_URL=<supabase project url>
NEXT_PUBLIC_SUPABASE_ANON_KEY=<supabase anon key>
```

**Client helper** (`src/lib/supabase/helpers.ts`):
- `requireSupabase()` — returns Supabase client, throws if env vars missing
- `parseDate(val)` — parses nullable date string → `Date | null`
- `parseDateRequired(val)` — parses required date string → `Date`

---

## Pipeline / CRM System

### Overview

The pipeline tracks leads from first contact through to a won/lost outcome and project conversion. OPS-Web Pipeline V2 is a dual-mode desktop surface: focused mode is the default command view, and the spatial canvas is the secondary map view for pan/zoom, marquee, and archive/discard tray workflows. Both modes use `@dnd-kit` for drag-and-drop.

### Pipeline Stages

8 ordered stages, divided into **active** and **terminal**:

| Stage | Slug | Color | Win Probability | Auto Follow-Up |
|---|---|---|---|---|
| New Lead | `new_lead` | #BCBCBC | 10% | 2 days |
| Qualifying | `qualifying` | #8195B5 | 20% | 3 days |
| Quoting | `quoting` | #C4A868 | 40% | 3 days |
| Quoted | `quoted` | #B5A381 | 60% | 5 days |
| Follow-Up | `follow_up` | #A182B5 | 50% | 3 days |
| Negotiation | `negotiation` | #B58289 | 75% | 2 days |
| **Won** | `won` | #9DB582 | 100% | — |
| **Lost** | `lost` | #6B7280 | 0% | — |

Active stages (NewLead → Negotiation) appear in the focused mode spine and spatial mode stage stacks. Won and Lost are terminal stages; focused mode renders them as a single terminal tab stack with exactly one selected roving tab, and spatial mode renders them as terminal canvas regions.

Per-company stage configuration is stored in the `pipeline_stage_configs` table, seeded from `PIPELINE_STAGES_DEFAULT`.

### Opportunity Entity

```typescript
interface Opportunity {
  id: string;
  companyId: string;
  clientId: string | null;       // Link to Bubble client (optional - leads may not have a client yet)
  title: string;
  description: string | null;

  // Contact info for leads without a client record
  contactName: string | null;
  contactEmail: string | null;
  contactPhone: string | null;

  // Pipeline tracking
  stage: OpportunityStage;
  source: OpportunitySource | null;  // referral | website | email | phone | walk_in | social_media | repeat_client | other
  assignedTo: string | null;         // User ID
  priority: OpportunityPriority | null; // low | medium | high

  // Financial
  estimatedValue: number | null;
  actualValue: number | null;
  winProbability: number;           // 0-100

  // Dates
  expectedCloseDate: Date | null;
  actualCloseDate: Date | null;
  stageEnteredAt: Date;

  // Conversion
  projectId: string | null;         // Set when Won and converted to project
  lostReason: string | null;        // One of LOSS_REASONS
  lostNotes: string | null;

  address: string | null;
  latitude: number | null;
  longitude: number | null;

  // Denormalized
  lastActivityAt: Date | null;
  nextFollowUpAt: Date | null;
  tags: string[];                      // e.g., ['email-import'] for Gmail-created leads

  createdAt: Date;
  updatedAt: Date;
  deletedAt: Date | null;
}
```

**iOS parity (2026-05, BOOKS tab Phase 1):** The iOS `Opportunity` SwiftData model (`OPS/DataModels/Supabase/Opportunity.swift`) now models the full opportunity schema additively. All 47 columns are now read-side on iOS; AI/location/images fields (`aiSummary`, `aiStageConfidence`, `aiStageSignals`, `detectedValue`, `latitude`, `longitude`, lead image set) remain deferred to a later phase. Implementing commit: `9047b4b` in ops-ios.

### OPS-Web Pipeline V2 Focused / Spatial UI

**Status:** Phase 11 focused/spatial contract updated 2026-05-14. Focused mode is the desktop default for `/pipeline`; spatial mode remains available as the secondary canvas mode.

**Primary route:** `src/app/(dashboard)/pipeline/page.tsx`

**Focused components:**
- `src/app/(dashboard)/pipeline/_components/pipeline-focused-shell.tsx`
- `src/app/(dashboard)/pipeline/_components/pipeline-focused-column.tsx`
- `src/app/(dashboard)/pipeline/_components/pipeline-focused-card.tsx`
- `src/app/(dashboard)/pipeline/_components/pipeline-spine-column.tsx`
- `src/app/(dashboard)/pipeline/_components/pipeline-terminal-stack.tsx`

**Spatial components:**
- `src/app/(dashboard)/pipeline/_components/spatial-canvas.tsx`
- `src/app/(dashboard)/pipeline/_components/spatial-stage-stack.tsx`
- `src/app/(dashboard)/pipeline/_components/spatial-terminal-region.tsx`
- `src/app/(dashboard)/pipeline/_components/spatial-archive-tray.tsx`
- `src/app/(dashboard)/pipeline/_components/spatial-floating-toolbar.tsx`

**Mode state:** `usePipelineModeStore` in `pipeline-mode-store.ts` owns:
- `mode` (`focused` / `spatial`)
- `focusedStage`
- global `sortBy`
- per-stage `stageSortOverrides`
- shared detail panel state: `detailPanelOpportunityId` and `detailPanelActiveTab`

The store persists only mode, focused stage, and sort state under `opsPipeline:v3`. Detail panel state is intentionally not persisted.

**Focused mode model:**
- The focused shell centers one active stage at a time, with neighboring stages rendered as spine columns.
- The focused toolbar is a single bottom-left overlay aligned to the dashboard content edge. It owns the focused/spatial mode toggle, search, stage filter, assignment filter, and lead creation controls. It uses the standard OPS glass/hairline toolbar treatment, restrained monochrome controls, and no accent-as-decoration.
- The search/filter row filters the same opportunity set for both focused and spatial modes.
- Horizontal wheel and Shift+wheel snap the focused stage. Trackpad pinch-out (`ctrl` wheel with positive `deltaY`) switches to spatial after the virtual zoom threshold.
- The `V` shortcut toggles focused/spatial unless a drag is active or the user is typing in an input/menu/modal.
- The accessibility model is a real tablist/tabpanel pair. Active stages and terminal Won/Lost entries are `role="tab"` controls; exactly one tab is `aria-selected="true"` and exactly one tab owns `tabIndex=0`. The single `role="tabpanel"` is labelled by the selected tab.
- Focused cards do not open detail from the card body. The explicit toolbar details action is the only focused-card entry path into the detail window. Card title, client name, and site address are independent inline controls: title saves through `useUpdateOpportunity`, client linking searches existing clients or creates a new client before attaching it through `attachClientToOpportunity`, and address editing uses the existing `opportunities.address`, `latitude`, and `longitude` fields with the shared Mapbox address autocomplete component, biased by the opportunity's current coordinates when present.
- Focused cards expose compact adjacent-stage reassignment controls when the user can manage pipeline stages. Controls are disabled for read-only users and terminal moves still route through the transition dialog.
- Focused drag to an active spine target moves the opportunity. Focused drag to Won/Lost opens the transition dialog before any terminal mutation.

**Spatial mode model:**
- Spatial mode keeps pan, zoom, marquee selection, context menu, archive tray, and discard tray workflows.
- Archive/discard trays are spatial-only and are not rendered in focused mode.
- Empty-canvas card drop is a no-op. Pipeline V2 removed free-positioning for opportunities; dropping on empty spatial canvas no longer writes custom positions.
- `customPositions` / free-positioning state is not part of Pipeline V2. Spatial positions are computed by the layout engine from stages, sort state, and terminal regions.

**Mode transition:** Pipeline V2 uses a manual FLIP transition between focused and spatial modes. Before the mode changes, `PIPELINE_MODE_WILL_CHANGE_EVENT` captures source card rects and a static source clone. After the target mode mounts, target rects are read and temporary card overlays animate with the OPS easing curve (`cubic-bezier(0.22, 1, 0.36, 1)`). Reduced motion skips the FLIP overlay and still changes mode state.

**Drag behavior:**
- `PipelineDndProvider` centralizes `DndContext`, pointer and keyboard sensors, and mode-aware collision handling.
- Focused pointer dragging uses pointer-only collision evidence and a `DragOverlay`; the source card dims in place so visual movement is not clipped by the current list.
- Focused keyboard dragging uses stage-aware coordinates so arrow keys move across active and terminal stage targets.
- `resolvePipelineDragEnd()` is the shared drop contract. Focused mode accepts only intentional focused stage drops marked by `focusedDropIntent: "stage-target"`; neutral release, missing pointer target, or stage-looking drops without that intent cancel/no-op. Spatial mode accepts stage/terminal drops and treats missing drop data as cancel/no-op.
- Normal active-stage moves call `onMoveStage(opportunityId, newStage)`. Won/Lost drops route through the transition dialog.

### OPS-Web Pipeline V2 Detail Panel

**Status:** Phase 11 verified 2026-05-13; focused-window correction verified 2026-05-19; focused card interaction correction verified 2026-05-26. The old tethered multi-window opportunity detail popover/window system was retired for `/pipeline`; `detail-popover.tsx`, `detail-popover-store.ts`, and `detail-popover-tether.tsx` were deleted. Opportunity detail state now lives in `usePipelineModeStore` via `detailPanelOpportunityId`, `detailPanelActiveTab`, `openDetailPanel`, `closeDetailPanel`, and `setDetailPanelActiveTab`.

**Components:**
- `src/app/(dashboard)/pipeline/_components/pipeline-focused-detail-window.tsx` — focused-mode window wrapper.
- `src/app/(dashboard)/pipeline/_components/pipeline-detail-panel.tsx` — shared detail body/actions and spatial drawer.
- `src/components/ops/projects/workspace/shell/project-workspace-window.tsx` — shared project-style window shell.
- `src/stores/window-store.ts` — includes `pipeline-detail` window type and sizing.

- Focused mode renders opportunity detail as a separate `ProjectWorkspaceWindow` surface via the shared window store (`pipeline-detail:<opportunityId>`). It is portaled to `document.body`, uses the same dense glass, traffic-light chrome, drag/resize, z-index, focus, minimize, and mobile sizing model as project details, and never renders inline beside the focused stage list.
- Focused detail is opened only by the explicit card details action. The focused window subtitle and contact strip surface the opportunity site address when present, followed by phone and email.
- Opening focused detail must not apply split-width classes or collapse the focused list. The focused card/list frame remains full width while the detail window floats above the Pipeline canvas.
- Spatial mode always renders the portal drawer. It does not attempt inline/push layout because transformed canvas measurement is brittle.
- Focused window close paths (traffic-light close, `Escape`, external window-store close) synchronize back to `usePipelineModeStore.closeDetailPanel()`. Spatial drawer close paths remain close button, `Escape`, and backdrop.
- Focus enters the panel on open and restores to the originating opportunity card via `data-opportunity-card-id` on close. DOM refs stay local to React components and are not stored in Zustand.
- The focused window root is marked `data-keyboard-scope="modal-or-menu"` so focused-mode stage shortcuts do not fire while the window, title bar, action menu, tabs, or detail content has focus.
- Detail tabs were renamed from `detail-popover-*` to `pipeline-detail-*` and share the mode-store active tab state.
- Motion uses the OPS easing curve (`cubic-bezier(0.22, 1, 0.36, 1)`) and honors `prefers-reduced-motion`.

### Opportunity Helpers

```typescript
// Stage navigation
nextOpportunityStage(current)       // Returns next stage or null
previousOpportunityStage(current)   // Returns previous stage or null
isActiveStage(stage)                // true for NewLead→Negotiation
isTerminalStage(stage)              // true for Won/Lost
getActiveStages()                   // Returns [NewLead..Negotiation]
getAllStages()                       // Returns all 8 stages

// Card data
getWeightedValue(opportunity)       // estimatedValue * winProbability / 100
isOpportunityStale(opportunity, thresholdDays=7)  // true if no activity within threshold
getDaysInStage(opportunity)         // Days since stageEnteredAt
getOpportunityContactName(opp, client?)  // client.name ?? contactName ?? "Unknown Contact"

// Loss prompt
LOSS_REASONS = ["Price", "Timing", "Competition", "Scope", "No Response", "Other"]
```

### Stage Transitions

Each stage change records an immutable `StageTransition` row:

```typescript
interface StageTransition {
  id: string;
  companyId: string;
  opportunityId: string;
  fromStage: OpportunityStage | null;
  toStage: OpportunityStage;
  transitionedAt: Date;
  transitionedBy: string | null;   // User ID
  durationInStage: number | null;  // Milliseconds in previous stage
}
```

**iOS parity (2026-05, BOOKS tab Phase 1):** iOS now writes `stage_transitions` rows on every stage move via the new `move_opportunity_stage` Postgres RPC. The RPC atomically updates `stage`, `stage_entered_at`, `stage_manually_set`, and INSERTs the transition row in a single transaction — eliminating the prior risk of a stage update landing without a paired transition record on partial network failure. RPC source: `ops-software-bible/migrations/2026-05-07-01-move-opportunity-stage-rpc.sql` (committed `b8db1aa`). iOS calling code: `OpportunityRepository.moveToStage(opportunityId:to:userId:)` (commit `bf26423`).

**Server-side auto-advance trigger (2026-05-20, LEADS polish P1-4):** `tr_activities_first_log_auto_advance` — an `AFTER INSERT ON activities` row-level trigger — implements the bible §10:205 documented behavior that was missing in prod. The LEADS tab rebuild verification (P1-1) proved zero historical system-triggered `new_lead → qualifying` transitions: every transition in `stage_transitions` had been user-initiated, confirming the auto-advance never existed despite being canonical. iOS `LeadLogActivitySheet` (Phase 4) writes activities expecting this trigger to fire. The trigger:

- Bails immediately if `NEW.opportunity_id IS NULL` (non-opp activities contribute nothing).
- Reads the target opp's `stage`, `company_id`, and `stage_entered_at`. Skips if the opp is missing/soft-deleted or already past `new_lead`.
- `UPDATE opportunities SET stage='qualifying', stage_entered_at=NEW.created_at, stage_manually_set=false WHERE id=NEW.opportunity_id AND stage='new_lead'`. The `AND stage='new_lead'` clause is the idempotency guard — if a sibling client advanced the opp between the SELECT and UPDATE, the WHERE matches zero rows and the rest is skipped.
- Only when the UPDATE actually matched (`FOUND` is true), INSERTs a `stage_transitions` row mirroring the `move_opportunity_stage` RPC's column set: `from_stage='new_lead'`, `to_stage='qualifying'`, `transitioned_at=NEW.created_at`, `transitioned_by=NEW.created_by`, `duration_in_stage=NEW.created_at - prior_stage_entered_at`.

`SECURITY DEFINER` so the trigger writes `opportunities` + `stage_transitions` regardless of the inserting client's RLS posture; authorization is upstream — the activity INSERT that fired the trigger already passed the `activities` company-isolation RLS policy. `stage_manually_set=false` marks system-driven advances distinct from manual Kanban drags (which set it true via `move_opportunity_stage`). Coexists cleanly with that RPC under concurrent writes: Postgres serializes the UPDATEs, whichever commits first wins, the other's `WHERE stage='new_lead'` matches zero rows.

Historical backfill deliberately out of scope: leads with activities logged before this migration stay at their current stage. Migration source: `ops-software-bible/migrations/2026-05-20-activities-first-log-auto-advance-trigger.sql`. iOS caller path unchanged: `LeadDetailViewModel.logActivity(...)` writes the activity row, the `LeadActivityLoggedSuccess` notification re-triggers `LeadsTabView.viewModel.loadData()`, the next reload picks up the new stage.

### OpportunityService

Located at `src/lib/api/services/opportunity-service.ts` (wired from `2742b60` commit):
- `fetchOpportunities(companyId, options)` — filter by stage, includeDeleted
- `fetchOpportunity(id)` — with activities, followUps, stageTransitions
- `createOpportunity(data)` — auto-sets stageEnteredAt
- `updateOpportunity(id, data)` — records stage transition if stage changed
- `deleteOpportunity(id)` — soft delete via deleted_at
- `moveToStage(id, newStage, userId)` — wraps updateOpportunity, records transition
- `markWon(id, actualValue, projectId?)` — sets Won + actualCloseDate
- `markLost(id, lostReason, lostNotes?)` — sets Lost + actualCloseDate

**iOS equivalence (2026-05, BOOKS tab Phase 1):** `OpportunityRepository` (`OPS/Network/Supabase/Repositories/OpportunityRepository.swift`, rebuilt in commit `bf26423`) mirrors the web service surface:

| iOS `OpportunityRepository` | Web `opportunity-service` | Notes |
|---|---|---|
| `fetchAll()` | `fetchOpportunities` | iOS pulls all non-deleted; client-side stage filtering |
| `fetchOne(_:)` | `fetchOpportunity` | iOS hydrates activities / follow-ups / transitions via separate fetchers below |
| `create(_:)` | `createOpportunity` | iOS sends explicit `title` when available; DB `trg_opportunities_default_title` still backfills empty titles |
| `update(_:fields:)` | `updateOpportunity` | Diff-PATCH (sparse field set) |
| `softDelete(_:)` | `deleteOpportunity` | Both implementations soft-delete via `deleted_at` |
| `moveToStage(opportunityId:to:userId:)` | `moveToStage` | iOS calls the `move_opportunity_stage` RPC; web still does updateOpportunity + records transition client-side |
| `markWon(opportunityId:actualValue:projectId:userId:)` | `markWon` | — |
| `markLost(opportunityId:reason:notes:userId:)` | `markLost` | — |
| `archive(_:)` / `unarchive(_:)` | — | **iOS-only.** No web equivalent yet — flag for future web parity. |
| `fetchActivities(opportunityId:)` | (included in `fetchOpportunity`) | iOS reads via direct Supabase query against `activities` |
| `fetchFollowUps(opportunityId:)` | (included in `fetchOpportunity`) | iOS reads via direct Supabase query against `follow_ups` |
| `fetchStageTransitions(opportunityId:)` | (included in `fetchOpportunity`) | iOS reads via direct Supabase query against `stage_transitions` |

### LeadConversionService — Lead → Project Conversion (iOS, 2026-05-19)

`LeadConversionService` (`OPS/Services/LeadConversionService.swift`, commit `38c9256` on `feat/leads-tab-rebuild`) orchestrates the conversion that lands when an operator marks a pipeline opportunity won — mirroring the canonical 'won' behavior documented in `10_JOB_LIFECYCLE_AND_DATA_RELATIONSHIPS.md` § `won` (line 282). Backed by the `convert_lead_to_project` Postgres RPC (`migrations/2026-05-19-convert-lead-to-project-rpc.sql`), which runs the entire conversion in one transaction so partial failure is impossible.

**RPC signature:**

```sql
convert_lead_to_project(
  p_opportunity_id uuid,
  p_actual_value   numeric,
  p_title          text,
  p_address        text,
  p_user_id        uuid
) RETURNS uuid  -- the new project id
```

**Behavior (single Postgres transaction, `SECURITY DEFINER`):**

1. Insert `projects` row — `status='accepted'`, `opportunity_id` back-link (legacy text column on projects, no FK), `client_id` carried over from the lead, `created_by = p_user_id`.
2. Forward-link estimates — every `estimates` row where `opportunity_id = p_opportunity_id` AND `project_id IS NULL` gets both `project_id` (text) and `project_ref` (uuid FK) set to the new project id.
3. Materialize each LABOR line item across those estimates as a `project_tasks` row — `task_type_id` from `line_items.task_type_ref` (uuid FK, nullable), `custom_title` from `line_items.name` (NOT NULL on source), `source_line_item_id` + `source_estimate_id` as text back-links, `display_order` from `line_items.sort_order`, `duration = COALESCE(task_types.default_duration, 1)`, `task_color = COALESCE(task_types.color, '#417394')`, `status='active'` (the only valid value per the `project_tasks_status_check` CHECK constraint — `pending` would reject).
4. Auto-attach site visit photos as `project_photos` rows (added 2026-05-20, migration `migrations/2026-05-20-extend-convert-lead-to-project-site-visit-photos.sql`) — for every non-deleted `site_visits` row where `opportunity_id = p_opportunity_id`, each URL in the visit's `photos[]` becomes a `project_photos` row with `source='site_visit'`, `site_visit_id` back-linked, `uploaded_by = site_visits.created_by` (the operator who booked the visit, not the operator winning the lead), `taken_at = NULL` (no EXIF surfaced at this layer — timeline orders by `created_at`), and `is_client_visible = false` (column default; the operator opts each photo into the portal via the per-photo toggle later). Empty/NULL photos arrays unnest to zero rows — visits with no photos contribute nothing. The idempotency guard above ensures a retried conversion does not re-insert photos.
5. Update `opportunities` row — `stage='won'`, `actual_value`, `actual_close_date`, `project_id` (uuid column), `project_ref`, `stage_entered_at = now()`, `stage_manually_set = true`.
6. Insert `stage_transitions` row capturing `duration_in_stage` (mirrors `move_opportunity_stage` pattern from `2026-05-07-01-move-opportunity-stage-rpc.sql`).

**Idempotency.** The RPC returns the existing project id without re-running anything if a project already back-links to `p_opportunity_id`. Guards against double-tap and the iOS-vs-web race when both clients try to convert at once.

**Authorization.** `SECURITY DEFINER` (writes across five tables in one transaction require elevated privileges). Caller is authorized via an explicit same-company check on `p_user_id` against the opportunity's `company_id`. Raises `opportunity_not_found` (SQLSTATE `P0002`) when the lead row is missing or soft-deleted, `access_denied` (SQLSTATE `42501`) when the user isn't a member of the lead's company.

**iOS service surface:**

| Method | Purpose |
|---|---|
| `existingProject(for:in:)` | SwiftData lookup — `Project` where `opportunityId == lead.id` AND `deletedAt == nil`. Drives the DUPLICATE-EXISTS pre-flight state on `ConvertToProjectSheet`. |
| `clientProjectsSummary(for:in:)` | SwiftData lookup — other projects under the same client (excluding the duplicate). Drives the CLIENT-HAS-OTHERS warning banner. |
| `estimates(for:)` | Network fetch — refreshes the estimates linked to the lead. |
| `convertLeadToProject(lead:actualValue:title:address:notes:userId:)` | Calls the RPC, optionally PATCHes notes after (RPC signature doesn't take notes), fetches the new project DTO, returns the SwiftData `Project` model. |
| `markWonNoProject(lead:actualValue:userId:)` | Escape hatch — wraps `OpportunityRepository.markWon` with `projectId: nil`. Used when the operator dismisses `ConvertToProjectSheet` without creating a project (sheet's CANCEL exit). |

**Deferred per plan §9.4** (`docs/superpowers/plans/2026-05-19-leads-tab-rebuild.md`):

- ~~Site-visit photo auto-attach on win (bible §10:289)~~ — **Implemented 2026-05-20.** RPC step 4 above. Historical wins (leads converted before this migration shipped) keep their photos unattached; a one-time backfill is a separate ticket if wanted.
- Task Generation modal (bible §10:290) — the UI for adding/removing tasks pre-materialization. v1 materializes every LABOR line item silently with no per-task toggle.

Web has no direct equivalent of `LeadConversionService` yet — the web app handles the conversion through the existing `opportunity-service.markWon` + the project-service create flow rather than a dedicated transactional service. Flag for future web parity if the RPC becomes the canonical path on web too.

---

## Estimates System

### Estimate Lifecycle

```
Draft → Sent → Viewed → Approved → Converted (to Invoice)
              ↓
         ChangesRequested → (back to Draft)
         Declined
         Expired (auto when expirationDate passes)
         Superseded (when a new version replaces it)
```

### Estimate Entity

```typescript
interface Estimate {
  id: string;
  companyId: string;
  opportunityId: string | null;   // Link to pipeline opportunity
  clientId: string;               // Required - Bubble client ID
  estimateNumber: string;         // Auto-generated via Supabase RPC (e.g. "EST-0001")
  version: number;                // Revision number, starts at 1
  parentId: string | null;        // Reference to previous version

  // Content
  title: string | null;
  clientMessage: string | null;   // Customer-facing message
  internalNotes: string | null;   // Internal notes only
  terms: string | null;           // Terms and conditions text

  // Pricing (snapshots - pre-calculated, not computed at query time)
  subtotal: number;
  discountType: DiscountType | null;  // "percentage" | "fixed"
  discountValue: number | null;
  discountAmount: number;
  taxRate: number | null;         // e.g. 0.0875 for 8.75%
  taxAmount: number;
  total: number;

  // Payment schedule (deposit)
  depositType: DiscountType | null;
  depositValue: number | null;
  depositAmount: number | null;

  // Status tracking
  status: EstimateStatus;
  issueDate: Date;
  expirationDate: Date | null;
  sentAt: Date | null;
  viewedAt: Date | null;
  approvedAt: Date | null;

  pdfStoragePath: string | null;

  createdBy: string | null;
  createdAt: Date;
  updatedAt: Date;
  deletedAt: Date | null;

  // Loaded separately
  lineItems?: LineItem[];
  paymentMilestones?: PaymentMilestone[];
  client?: Client | null;
  opportunity?: Opportunity | null;
}
```

### EstimateService

Located at `src/lib/api/services/estimate-service.ts`:

- `fetchEstimates(companyId, options)` — filter by status, clientId, opportunityId
- `fetchEstimate(id)` — includes line items (ordered by sort_order)
- `createEstimate(data, lineItems[])` — two-step: RPC for estimate number, then insert header + line items
- `updateEstimate(id, data, lineItems?)` — if lineItems provided, delete-all-and-reinsert
- `deleteEstimate(id)` — soft delete via deleted_at
- `sendEstimate(id)` — sets status=Sent, sent_at=now
- `convertToInvoice(estimateId, dueDate?)` — **atomic Supabase RPC** `convert_estimate_to_invoice`

### Document Number Generation

Estimate and invoice numbers are generated server-side via Supabase RPC:

```sql
-- RPC: get_next_document_number(p_company_id, p_document_type)
-- Returns: "EST-0001", "EST-0002", ... or "INV-0001", "INV-0002", ...
```

This ensures sequential, race-condition-free numbering per company.

### Estimate Helpers

```typescript
isEstimateExpired(estimate)     // true if past expirationDate and not Approved/Converted
isEstimateEditable(estimate)    // true only for Draft or ChangesRequested
isEstimateSendable(estimate)    // true only for Draft
```

### Line Items

```typescript
interface LineItem {
  id: string;
  companyId: string;
  estimateId: string | null;    // Exactly one of these must be set
  invoiceId: string | null;

  productId: string | null;     // Optional reference to Products catalog

  // Content
  name: string;
  description: string | null;
  quantity: number;
  unit: string;                 // "each" | "hour" | "sqft" | "linear ft" | "day" | "flat rate"
  unitPrice: number;
  unitCost: number | null;      // For margin tracking
  discountPercent: number;      // 0-100
  isTaxable: boolean;
  taxRateId: string | null;

  lineTotal: number;            // GENERATED ALWAYS by DB: qty * unitPrice * (1 - discountPercent/100)

  // Estimate-specific
  isOptional: boolean;          // Optional line items client can include/exclude
  isSelected: boolean;          // Whether optional item is selected

  sortOrder: number;
  category: string | null;
  serviceDate: Date | null;

  createdAt: Date | null;
}
```

**Critical**: `line_total` is a `GENERATED ALWAYS` column — **never include in INSERT/UPDATE**.

### Payment Milestones

For progress billing on estimates:

```typescript
interface PaymentMilestone {
  id: string;
  estimateId: string;
  name: string;                 // e.g. "Deposit", "Upon Completion"
  type: MilestoneType;          // "percentage" | "fixed"
  value: number;                // Percentage (0-100) or fixed amount
  amount: number;               // Calculated dollar amount
  sortOrder: number;
  invoiceId: string | null;     // Set when milestone is invoiced
  paidAt: Date | null;
}
```

### Line Item Calculation Helpers

```typescript
calculateLineTotal(qty, unitPrice, discountPercent?)
// = qty * unitPrice * (1 - discountPercent/100), rounded to 2 decimals

calculateLineTax(lineTotal, taxRate)
// = lineTotal * taxRate, rounded to 2 decimals

calculateDocumentTotals(lineItems[], taxRate?, discountAmount?)
// Returns { subtotal, taxAmount, total }
// Only includes selected items (isOptional=false OR isSelected=true)

calculateMargin(unitPrice, unitCost)
// Returns profit margin as percentage, null if no unitCost

formatCurrency(amount, currency?)     // "USD" default → "$1,234.56"
formatTaxRate(rate)                   // 0.0875 → "8.75%"
```

---

## Invoices System

### Invoice Lifecycle

```
Draft → Sent → AwaitingPayment → PartiallyPaid → Paid
                                ↓
                              PastDue → Paid | WrittenOff
     → Void (from any status)
```

### Invoice Entity

```typescript
interface Invoice {
  id: string;
  companyId: string;
  clientId: string;
  estimateId: string | null;      // Set if converted from estimate
  opportunityId: string | null;   // Link to pipeline opportunity
  projectId: string | null;       // Link to Bubble project
  invoiceNumber: string;          // Auto-generated via RPC (e.g. "INV-0001")

  // Content
  subject: string | null;
  clientMessage: string | null;
  internalNotes: string | null;
  footer: string | null;
  terms: string | null;

  // Pricing
  subtotal: number;
  discountType: DiscountType | null;
  discountValue: number | null;
  discountAmount: number;
  taxRate: number | null;
  taxAmount: number;
  total: number;

  // Payment tracking (maintained by DB trigger — NEVER update manually)
  amountPaid: number;
  balanceDue: number;
  depositApplied: number;

  // Status & dates
  status: InvoiceStatus;
  issueDate: Date;
  dueDate: Date;
  paymentTerms: string | null;    // "Net 30", "Due on Receipt", etc.
  sentAt: Date | null;
  viewedAt: Date | null;
  paidAt: Date | null;

  pdfStoragePath: string | null;

  createdBy: string | null;
  createdAt: Date;
  updatedAt: Date;
  deletedAt: Date | null;
}
```

### InvoiceService

Located at `src/lib/api/services/invoice-service.ts`:

- `fetchInvoices(companyId, options)` — filter by status, clientId, projectId, opportunityId
- `fetchInvoice(id)` — includes line items and non-voided payments
- `createInvoice(data, lineItems[])` — RPC for invoice number, then insert header + line items
- `updateInvoice(id, data, lineItems?)` — replace line items if provided
- `deleteInvoice(id)` — soft delete via deleted_at
- `sendInvoice(id)` — sets status=Sent, sent_at=now
- `voidInvoice(id)` — sets status=Void
- `recordPayment(data)` — insert into `payments` table; DB trigger updates invoice balance
- `fetchInvoicePayments(invoiceId)` — non-voided payments, desc by date
- `voidPayment(paymentId, userId)` — sets voided_at + voided_by; DB trigger recalculates balance

### Invoice Payment Balance (DB Triggers)

The `amount_paid`, `balance_due`, and `status` on invoices are **maintained by Supabase DB triggers**. Do NOT update them manually. The flow:

1. Insert a `payment` row → trigger recalculates `amount_paid`, `balance_due`, updates status (PartiallyPaid / Paid)
2. Void a payment (set `voided_at`) → trigger recalculates again
3. Never call `updateInvoice` to change payment amounts

### Invoice Helpers

```typescript
isInvoiceOverdue(invoice)    // true if past dueDate, balance > 0, not Paid/Void/WrittenOff
isInvoicePayable(invoice)    // true if balance > 0 and not Draft/Void/WrittenOff
getDaysUntilDue(invoice)     // Negative = overdue, positive = days remaining
```

### Payment Entity

```typescript
interface Payment {
  id: string;
  companyId: string;
  invoiceId: string;
  clientId: string;
  amount: number;
  paymentMethod: PaymentMethod | null;  // credit_card | debit_card | ach | cash | check | bank_transfer | stripe | other
  referenceNumber: string | null;       // Check number, transaction ID, etc.
  notes: string | null;
  paymentDate: Date;
  stripePaymentIntent: string | null;   // For Stripe payments
  createdBy: string | null;
  createdAt: Date;
  voidedAt: Date | null;               // NOT deleted_at — use voided_at for voiding
  voidedBy: string | null;
}
```

### Payment Terms Options

```
"Due on Receipt", "Net 7", "Net 10", "Net 15", "Net 30", "Net 45", "Net 60", "Net 90"
```

---

## Products & Services Catalog

The catalog supports two tiers of richness:

- **Barebones Products** — name + base_price + pricing_unit + tax. Behave like the original flat Product model. A "PICKET RAIL" Product at $2500 flat is one form-fill away (~8s in `ProductQuickAddSheet`).
- **Configurable Products** — carry options, pricing modifiers, and recipe rules. Used for cases like Canpro's "Custom Composite Railing" where a single Product expresses per-foot pricing, modifiers (Concrete +$5/ft), recipe templates (Color cascades through every BOM row), and quantity-scaling counts (Corners → corner hardware kits).

See `03_DATA_ARCHITECTURE.md` § 21 (Product) for the full SwiftData model with all 18 fields, and `07_SPECIALIZED_FEATURES.md` § 13a for resolver semantics and the worked Canpro example.

### Product Entity (post-Phase 13)

```typescript
type ProductPricingUnit =
  | 'each' | 'flat_rate' | 'linear_foot' | 'sqft' | 'hour' | 'day';

// On the wire: 'service' | 'material' | 'package'. The Swift enum case
// names `.good` and `.package` map to the wire values `material` and
// `package` respectively (`.good` is legacy — kept for source stability).
type ProductKind = 'service' | 'material' | 'package';

type LineItemType = 'LABOR' | 'MATERIAL' | 'OTHER';

// User-facing iOS taxonomy (added 2026-05-10, bug 164e0595). Derives
// kind + type on save. See § Catalog UI below for the mapping table.
type ProductCategory = 'service' | 'material' | 'fee' | 'bundle';

interface Product {
  id: string;
  companyId: string;
  name: string;
  description: string | null;

  type: LineItemType;
  kind: ProductKind;

  basePrice: number;              // primary unit price (replaces default_price)
  unitCost: number | null;        // for margin tracking
  pricingUnit: ProductPricingUnit;

  unit: string | null;            // legacy free-text unit (kept for back-compat)
  category: string | null;        // legacy free-text category (separate from catalog_categories)
  sku: string | null;

  taxable: boolean;
  isActive: boolean;
  isFavorite: boolean;

  minimumCharge: number | null;
  minimumQuantity: number | null;
  showBomOnEstimate: boolean;
  showInStorefront: boolean;
  tieredPricing: jsonb | null;    // power-user passthrough

  taskTypeId: string | null;
  taskTypeRef: string | null;
  unitId: string | null;                // FK catalog_units.id
  linkedCatalogItemId: string | null;   // FK catalog_items.id (added 2026-05-10, bug 164e0595)

  createdAt: Date | null;
  updatedAt: Date | null;
  deletedAt: Date | null;
}
```

**Wire-field fix**: earlier builds wrote `unit_price`/`cost_price` — columns that do not exist in Supabase. The DTO now correctly maps `base_price`/`unit_cost`. The legacy `default_price` column is preserved with a Postgres trigger mirroring `base_price` ↔ `default_price` (see `migrations/2026-05-06-02-catalog-views-triggers.sql`) until ops-web cuts over to `base_price`.

### iOS Catalog UI — New Product Sheet (post bug 164e0595)

The legacy iOS New Product sheet forced two overlapping pickers (`Kind` Service/Good + `Line item type` Labor/Material/Other). The 2026-05-10 redesign collapses these into a single 4-way `ProductCategory` picker. The form derives `kind` + `type` on save so old App Store builds and the web app keep reading sensible values without any client-side change.

| User picks | wire `kind` | wire `type` | Default `taxable` | Task type | Components | Stock link |
|---|---|---|---|---|---|---|
| Service  | `service`  | `LABOR`    | `true`  | required | optional | — |
| Material | `material` | `MATERIAL` | `true`  | — | — | optional |
| Fee      | `service`  | `OTHER`    | `false` | — | — | — |
| Bundle   | `package`  | `OTHER`    | `true`  | required | optional | — |

Per-category form affordances:
- **Service / Bundle**: required `Task Type` picker writes `task_type_ref`. Optional `// COMPONENTS` disclosure stages recipe rows (variant-pinned only) via `AddProductMaterialSheet` in draft mode; rows commit to `product_materials` after Product create.
- **Material**: optional `// SHOW IN STOCK` toggle. When ON, the operator either picks an existing `catalog_items` row or creates one (plus a default `catalog_variants` row) via `CatalogRepository.createDefaultItemForProduct`. The chosen id is written to `linked_catalog_item_id`.
- **Fee**: no extras — minimises the form so a permit / passthrough entry stays an 8-second flow.

The `Taxable` toggle pre-defaults per category (Service/Material/Bundle → ON, Fee → OFF). Once the operator flips it manually, the override sticks across category switches (`taxableUserOverridden` flag in the form's view-state).

**Inventory deduction on sale is not yet wired** — see § P1-28 scope for `inventory_deductions` integration. The `linked_catalog_item_id` column is present so that work can land without further iOS changes.

Products are soft-deleted. `ProductService.fetchProducts(companyId, activeOnly=true)` returns only active, non-deleted products by default. Line items reference a product via `productId`. When a product is added to an estimate, it pre-fills the line item name, description, `resolved_unit_price`, unit cost, unit, taxable flag, type, and `taskTypeId`.

### Line Item Snapshot (NEW post-Phase 13)

`line_items` gained three columns to capture per-line configuration at the moment of creation. Estimates and invoices are signed contracts — once a line is written, later edits to the Product must not retroactively change the historical estimate.

```sql
ALTER TABLE line_items
  ADD COLUMN configured_options       jsonb        NULL,
  ADD COLUMN resolved_unit_price      numeric      NULL,
  ADD COLUMN resolved_options_label   text         NULL;
```

| Column | Purpose |
|---|---|
| `configured_options` | Per-line jsonb of `{option_id: option_value_id_or_int_or_bool}`. Captured at line creation. Read by `RecipeResolver` at install task creation to materialize the cut list. |
| `resolved_unit_price` | Snapshot of `base_price + applicable modifiers`. Frozen at line creation; never re-resolves. |
| `resolved_options_label` | Printed-estimate-friendly summary ("TM · Black · Concrete · 4 corners"). |

**Pricing freeze**: pricing modifiers are evaluated and folded into `resolved_unit_price` at line-item creation. Modifying the Product after the estimate is sent does not change the estimate's totals.

**Recipe lazy-resolution**: recipes do **not** resolve at estimate creation. They resolve at install task creation by reading `configured_options` and walking `product_materials`. This is intentional — the cut list must reflect the configuration the customer signed, not whatever the Product looks like today.

### Recipe Semantics

`product_materials` rows are either:

- **Variant-pinned** — `catalog_variant_id` non-null, `catalog_item_id` null. The recipe always pulls this exact SKU regardless of options.
- **Family-pinned with selector** — `catalog_item_id` non-null, `catalog_variant_id` null, `variant_selector` jsonb populated. The selector references option keys (`{"color":"$option.color","mount":"$option.mount_type"}`) — at resolution time, the resolver walks the line's `configured_options`, matches values, and finds the variant on that family with those option-value combos.

CHECK constraint `(catalog_variant_id IS NOT NULL) <> (catalog_item_id IS NOT NULL)` enforces mutual exclusion.

`scaled_by_option_id` lets a recipe row scale by an integer-kind option's value. Example: a "Corner Hardware Kit" row with `scaled_by_option_id = corners_count` and `quantity_per_unit = 1` yields 4 kits when the line specifies 4 corners.

### Resolution Timing

| Event | What runs | Output |
|---|---|---|
| Line item created (manually or via adapter) | `ProductConfigurationResolver` | `configured_options`, `resolved_unit_price`, `resolved_options_label` |
| Estimate sent / approved | (no-op for catalog) | — |
| Project transitions to `.inProgress` and install tasks generated | `CutListMaterializer` per task → `RecipeResolver` per line | `task_materials` rows pinned to specific `catalog_variants` |
| Cut-list materialization is idempotent | re-running replaces the existing rows | — |

---

## Expense Tracking System

### Overview

Full expense submission, receipt OCR scanning, batch approval workflow, and accounting sync system. All roles can submit expenses; office/admin approve field crew submissions. Expenses live in the Pipeline tab under a dedicated "EXPENSES" segment.

### Expense Lifecycle

```
draft → submitted → approved → reimbursed
                  ↘ rejected
```

- **Draft**: Created by user, not yet submitted for review
- **Submitted**: Sent for approval (auto-approve if under threshold)
- **Approved**: Approved by office/admin, triggers accounting sync if connected
- **Rejected**: Rejected with reason, can be edited and resubmitted
- **Reimbursed**: Payment confirmed (terminal state)

### Threshold-Based Approval

Company-configurable via `expense_settings`:

1. **Auto-approve threshold**: Expenses under this amount auto-approve on submission
2. **Admin approval threshold**: Expenses above this amount require admin (not just office crew)
3. Expenses between the two thresholds require office crew or admin approval

### Server-Authoritative Expense Envelopes (2026-06-01)

Batching and submission are owned by the **database**, not the client, so no app version can strand an expense and envelopes auto-submit for review on a per-org schedule. This replaced the client-authoritative "always-bundle on submit" model (and the dead `accounting-batch-create` cron) below.

**Envelope lifecycle** (`expense_batches.status`):

| Phase | `status` | Meaning | Accepts new items? |
|---|---|---|---|
| Filling | `open` *(value added 2026-06-01)* | Current period, silently accruing | Yes |
| With the office | `pending_review` | Auto-sent on schedule | Yes — same-period late items, until approved |
| Done | `approved` / `auto_approved` | Office approved (auto-approved envelopes live in History) | No → late items roll forward |

**Placement (instant, server-side).** `trg_place_expense` (AFTER INSERT or UPDATE OF status, expense_date, batch_id on `expenses`) → `place_expense(uuid)`: for any non-draft, unbatched expense it derives the period from the expense's *date* + the company's `review_frequency` (`expense_envelope_period`), finds the not-yet-approved envelope for `(submitted_by, period, scope_project_id)` or creates one `open` (`get_or_create_open_batch`), attaches the expense, and recalculates the envelope total. If the home-period envelope is already `approved`, it **rolls forward** into the current period's open envelope. `draft` expenses are never placed.

**Daily sweep.** `expense_envelope_sweep()` via pg_cron `expense_envelope_sweep_daily` (15:15 UTC) does three jobs: (1) **safety net** — adopts any expense left `submitted / batch_id = NULL` (orphans from any client/version) and places it; (2) **auto-send** — every `open` envelope past `period_end + expense_settings.auto_submit_grace_days` flips to `pending_review`, sweeping in that person's completed (`amount > 0`) drafts first, then firing **one** `expense_submitted` notification per envelope to `expenses.approve` holders (see `07_SPECIALIZED_FEATURES.md §14.3.4`); (3) **roll-forward** — stragglers whose home period is already approved move to the current open envelope. The `open → pending_review` flip is the idempotency guard — a sent envelope is never re-picked.

**Grace / cadence.** `expense_settings.auto_submit_grace_days` (int, default 7) = days after a period ends before its envelope auto-sends. `per_job` envelopes have no calendar period — the sweep sends them `projects.completed_at + auto_submit_grace_days` after the linked job completes (join `scope_project_id → projects.id`); an envelope whose job isn't done stays `open` (office can send manually). **Under-threshold auto-clear:** on placement, if `amount < expense_settings.auto_approve_threshold`, the line still lands in its envelope (books stay complete) but is set `approved` immediately, server-side in `place_expense` — replacing the old iOS client bypass.

**Security.** `place_expense` and `expense_envelope_sweep` are `SECURITY DEFINER` locked to `service_role` (REVOKEd from public/anon/authenticated). `get_or_create_open_batch` stays broadly executable (shipped iOS clients still call it on submit during the transition). Direct client writes that move an envelope to `approved`/`auto_approved` are gated to `expenses.approve` holders by the `expense_batches_approve_scope` RESTRICTIVE RLS policy. Approval itself runs through the `approve_expense_batch` / `early_clear_expense_line` RPCs (SECURITY DEFINER, permission-checked, atomic) rather than client double-writes — the RLS policy remains as defense for any stray direct write.

**Back-compat.** All changes additive — the iOS cross-release sync constraint holds; 3.0.2 keeps working, it simply starts seeing its expenses batched. Migrations `20260601210311_expense_envelope_schema` … `20260601215540_lock_tg_place_expense_to_trigger_only` (Phase 1) plus the Phase-2 server deltas `20260602042258_expense_approval_rpcs`, `20260602042530_expense_envelope_sweep_v3_deeplink_perjob`, `20260602042658_place_expense_under_threshold_autoclear` + the cron. A one-time backfill (`20260601212520_backfill_expense_orphans`) placed the 53 pre-existing orphans.

### Batch Review Workflow

**Envelope scoping by cadence (server-authoritative since 2026-06-01).** Placement files every non-draft, unbatched expense into an envelope (`expense_batches`, created `open`) by the expense's *date*. The `review_frequency` setting controls how an envelope is *scoped*:

| Frequency | Batch scope | Period window |
|---|---|---|
| `per_job` | One batch per `(submitted_by, scope_project_id)` — multi-allocation forbidden in the form for these companies | Single-day (`expense_date` to `expense_date`) |
| `weekly` | One batch per `(submitted_by, week)` | Mon–Sun containing `expense_date` |
| `biweekly` | One batch per `(submitted_by, half-month)` | 1–14 or 15–end-of-month containing `expense_date` |
| `monthly` | One batch per `(submitted_by, month)` | First-to-last day of the month containing `expense_date` |
| `quarterly` | One batch per `(submitted_by, quarter)` | First-to-last day of the quarter containing `expense_date` |

Subsequent expenses by the same user in the same scope accumulate into the same not-yet-approved envelope (whether still `open` or already auto-sent to `pending_review`) until it is **approved**. Once approved, further same-scope expenses **roll forward** into the current period's open envelope (created on demand) — see § Server-Authoritative Expense Envelopes above.

**Atomic get-or-create.** Placement (and iOS submit, during the transition) go through `public.get_or_create_open_batch(p_company_id, p_submitted_by, p_period_start, p_period_end, p_scope_project_id)`, which now creates the envelope as **`open`** and matches an existing `open` *or* `pending_review` envelope. The race-safety partial unique index `expense_batches_open_unique` on `(company_id, submitted_by, period_start, period_end, scope_project_id)` (NULLS NOT DISTINCT) was widened to `WHERE status IN ('open','pending_review') AND amendment_number=0` so the filling phase is also one-per-scope.

**Per-expense auto-approve — now server-side.** The old iOS client bypass (`draft → approved` directly, no envelope) was removed in Phase 2a (2026-06-02). Under-threshold lines now auto-clear **server-side** in `place_expense` while staying counted in their envelope (see § Grace / cadence above) so books stay complete.

**Notification dispatch — now server-side, one per envelope.** The iOS client no longer fires a per-submit `expense_submitted` notification (removed Phase 2a). The daily sweep fires **one** `expense_submitted` per envelope on auto-send (deep link `expense`), with recipients looked up via `public.users_with_permission(company_id, 'expenses.approve')` — never by `users.role`. Other role-gated sites (`TimeOffRequestSheet.swift`, `QuantityAdjustmentSheet.swift`) likewise use the permission-gated lookup.

**Orphan recovery — now server-side and permanent.** The placement trigger fires for every client/version, and the daily sweep's safety net adopts any expense left `submitted / batch_id = NULL` and places it — permanently ending the stranding class of bug regardless of app version. The iOS `BUNDLE` banner + client recovery path (`recoverOrphans` / `loadOrphanCount`) were removed in Phase 2a (2026-06-02) — recovery is entirely server-owned. A one-time backfill on 2026-06-01 placed the 53 pre-existing orphans (`migrations/20260601212520_backfill_expense_orphans.sql`); Maverick's 51 historical orphans were filed to History (`auto_approved`) per operator decision so its approvers weren't blasted with back-dated review notifications.

**`accounting-batch-create` Edge Function** *(deprecated 2026-05-08; fully superseded 2026-06-01)* — the cron-driven lazy batcher is gone. It had a latent bug (references to a nonexistent `expense_count` column and `accounting_sync_log` table made every invocation fail silently — zero batches with `status='pending'` ever existed). It is replaced by the in-database placement trigger + `expense_envelope_sweep` pg_cron job; remove it via the Supabase dashboard. See `04_API_AND_INTEGRATION.md § accounting-batch-create`.

### iOS field + review (Phase 2a, 2026-06-02)

`ops-ios` was brought in line with the server-authoritative model (`ExpenseBatchStatus.open` added; realtime migration `20260602202519_expense_realtime_publication.sql`):

- **Single Add.** `ExpenseFormSheet` has one **ADD** action — a complete add writes `status='submitted'` and the `place_expense` trigger files it. No client `get_or_create_open_batch`, `ExpenseBatchPeriod` placement, under-threshold auto-approve, or per-submit notification. Editing a pending line keeps it `submitted` and re-files via batch-clear (`ExpenseViewModel.refileEditedExpense`) so the envelope total stays live (no revert-to-draft); a rejected line re-files into the current open envelope on resubmit.
- **Snap-a-stack drafts.** The multi-receipt scan queue still saves `draft`s (SAVE & NEXT); `MyExpensesView` shows a quiet "finish your receipt" nudge for unfinished drafts. The bulk SUBMIT button, selection sheet, and swipe-to-submit were removed.
- **State display.** `ExpenseCard` shows the line's state + envelope phase quietly ("filling" / "with the office" / "approved" / "paid" / "needs fix"); `MyExpensesView` shows a low-key running total for the current filling envelope.
- **Review hub.** `ExpensesListView` excludes `open` (filling) envelopes from review, hero totals, and period pills (no iOS peek surface); `auto_approved` envelopes live under the **History** tab; `ExpenseBatchDetailView.isReviewable` is false for filling envelopes (no APPROVE). The dead `CrewInvoiceHistoryView` was removed. iOS whole-envelope approval still uses direct writes (succeeds for a real approver under the `expense_batches_approve_scope` RLS policy); the atomic `approve_expense_batch` RPC is the OPS-Web path.
- **Realtime.** `RealtimeProcessor` subscribes `expense_batches` (plus the existing `expenses`); both were added to the `supabase_realtime` publication with `REPLICA IDENTITY FULL` (they were not published before — the `expenses` subscription had been silently dead), so envelope status flips (filling → with the office, auto-approved) and total recalcs render live in the review hub + crew list.

### Receipt OCR (Apple Vision)

On-device OCR using Apple's Vision framework (`VNRecognizeTextRequest` with `.accurate` recognition level). No external vendor dependency.

**Extracted fields**: merchant name, date, total, subtotal, tax amount, payment method (cash/card detection), raw text.

**Architecture**: Protocol-based (`ExpenseOCRServiceProtocol`) for future swappability (e.g., Veryfi integration).

### Multi-Project Expense Splitting

Expenses can be attributed to zero or more projects via `expense_project_allocations`:
- Each allocation has an `expense_id`, `project_id`, and `percentage` (0-100)
- Percentages must sum to 100% if any allocations exist (validated client-side in `ExpenseFormSheet.validate`)
- Project assignment is optional (company-configurable via `require_project_assignment`)
- **`per_job` companies allow exactly one allocation per expense** — the form blocks the "ADD PROJECT" button after the first project is selected, since per-job batches are project-scoped

### Currency Handling

`expenses.currency` (text, default `'USD'`) stores the ISO 4217 code. The form's currency picker defaults from `Locale.current.currency?.identifier` (locale-aware) and is overridable per-expense. Canadian crews logging CAD receipts in a USD-default world were silently mis-recording before 2026-05-08 — this fix surfaces currency in the form and persists it through `CreateExpenseDTO`/`UpdateExpenseDTO`.

### Supabase Tables (6)

| Table | Purpose |
|---|---|
| `expenses` | Core expense records (amount, merchant, status, receipt URL, OCR data, **currency**) |
| `expense_project_allocations` | Many-to-many linking expenses to projects with percentage split |
| `expense_categories` | Company-configurable categories with icons (9 defaults seeded) |
| `expense_settings` | Per-company settings (review frequency, thresholds, policy toggles) |
| `expense_batches` | Per-person/per-period **envelopes**. `status`: `open` (filling) → `pending_review` (sent) → `approved` / `auto_approved` (done; auto-approved live in History). **`scope_project_id` (nullable uuid)** identifies per-job envelopes; NULL for period envelopes. One active (`open`/`pending_review`) envelope per scope via `expense_batches_open_unique` |
| `accounting_category_mappings` | Maps OPS categories to external chart of accounts (QB/Sage) |

### Supabase Functions (expense-related)

| Function | Purpose |
|---|---|
| `public.users_with_permission(p_company_id, p_permission, p_required_scope)` | Returns user IDs in a company holding a permission. Honors role grants, per-user overrides, and the `is_company_admin`/`account_holder_id`/`admin_ids` escape hatches. **Use for all recipient lookups — never filter by `users.role`.** |
| `public.get_or_create_open_batch(p_company_id, p_submitted_by, p_period_start, p_period_end, p_scope_project_id)` | Returns the user's not-yet-approved envelope for the scope (matching `open` **or** `pending_review`) or creates one as **`open`** (race-safe via `expense_batches_open_unique` + on-conflict re-select). `migrations/20260601210601_get_or_create_open_batch_v2.sql`. |
| `public.expense_envelope_period(p_expense_date date, p_review_frequency text)` | Returns `(period_start, period_end)` for an expense given its date + cadence — SQL port of `ExpenseBatchPeriod.swift` (Postgres week starts Monday). `migrations/20260601210428_expense_envelope_period_fn.sql`. |
| `public.place_expense(p_expense_id uuid)` *(service_role)* | Files one non-draft, unbatched expense into its envelope by date; rolls forward if the home period is approved. Invoked by the `trg_place_expense` trigger. `migrations/20260601210846_place_expense_trigger.sql`. |
| `public.expense_envelope_sweep()` *(service_role)* | Daily pg_cron `expense_envelope_sweep_daily` (15:15 UTC): auto-sends due `open` envelopes (one `expense_submitted` notification each), sweeps in completed drafts, adopts orphans (safety net), rolls stragglers forward. `migrations/20260601213757_expense_envelope_sweep_deep_link_expense.sql`. |
| `public.recalculate_expense_batch_total(p_batch_id)` | Recomputes and persists `expense_batches.total_amount` from non-deleted attached expenses. Called after attaching expenses on submission. |
| `public.has_permission(p_user_id, p_permission, p_required_scope)` | Single-user permission check. Note: does NOT currently apply `user_permission_overrides` — only `user_roles → role_permissions` plus the admin escape hatches. iOS `PermissionService.fetchPermissions` applies overrides client-side. (Latent inconsistency — flagged for follow-up.) |
| `public.get_next_expense_batch_number(p_company_id)` | Returns next sequential batch number, format `EXP-BATCH-NNNN`. |
| `public.approve_expense_batch(p_batch_id uuid)` | Atomic whole-envelope approve — permission-checked (`expenses.approve` via `has_permission`), sets the batch + its non-rejected lines `approved` + recalc in one txn. OPS-Web calls this instead of two direct writes. `migrations/20260602042258_expense_approval_rpcs.sql`. |
| `public.early_clear_expense_line(p_expense_id uuid)` | Early-clear — permission-checked; approves a single line, leaves the envelope `open`, recalcs, notifies the submitter (`expense_approved`). `migrations/20260602042258_expense_approval_rpcs.sql`. |

### Default Expense Categories (9)

Seeded on first load via `ExpenseRepository.seedDefaultCategories()`:

| Category | Icon |
|---|---|
| Materials & Supplies | shippingbox.fill |
| Equipment Rental | wrench.and.screwdriver.fill |
| Fuel & Mileage | fuelpump.fill |
| Subcontractor | person.2.fill |
| Permits & Fees | doc.text.fill |
| Tools | hammer.fill |
| Safety Equipment | shield.checkered |
| Office Supplies | paperclip |
| Other | ellipsis.circle |

### Entry Points

1. **Pipeline tab → Expenses → + FAB** — General submission, no project pre-selected
2. **Project Details → Expenses section** — Pre-fills project allocation
3. **Project Action Bar → Receipt button** — Opens camera, pre-fills project on capture

---

## Accounting Integrations

### AccountingConnection Entity

```typescript
interface AccountingConnection {
  id: string;
  companyId: string;
  provider: AccountingProvider;   // "quickbooks" | "sage"
  accessToken: string | null;     // OAuth access token
  refreshToken: string | null;    // OAuth refresh token
  tokenExpiresAt: Date | null;
  realmId: string | null;         // QuickBooks realm/company ID
  isConnected: boolean;
  lastSyncAt: Date | null;
  syncEnabled: boolean;
  webhookVerifierToken: string | null;
  createdAt: Date | null;
  updatedAt: Date | null;
}
```

Located at `src/lib/api/services/accounting-service.ts`. Stores OAuth connections for QuickBooks and Sage. Expense push runs via Supabase Edge Functions (below); the read-only QuickBooks draw runs in `ops-web` (see *QuickBooks Read-Only Sync*).

**Additional columns (2026-06, not in the legacy interface above):** `sync_direction text NOT NULL DEFAULT 'pull_only'` (CHECK ∈ {`pull_only`, `push_only`, `bidirectional`}) governs which half of the sync engine may run — a `pull_only` connection can never push to the provider; `realm_id_lookup text` (SHA-256 hex of the realm id) is the deterministic routing column for inbound webhooks, since `realm_id` itself is encrypted. **Token security:** `access_token` / `refresh_token` / `realm_id` are AES-256-GCM encrypted at rest (`token-cipher.ts`, key env `QB_TOKEN_ENC_KEY`, fail-closed); decryption is centralized in `AccountingTokenService.getValidToken`. The web client reads this table as the anon role, so an anon company-scoped `SELECT` policy gated on `accounting.view` exists alongside the `service_role` write policy (migration `20260603010000_accounting_connections_read_policy.sql`, bug `eb70d803`).

### QuickBooks Read-Only Sync (pull-only) — 2026-06-04

The **inbound** side of QuickBooks: a read-only Pull → Stage → Review → Apply draw that imports a company's QuickBooks customers, invoices, estimates, and payments into OPS so iOS Books shows real money. It is the inverse of the push-only `accounting-sync-expense` function below — it issues **zero** writes to Intuit. Full engineering reference (services, routes, apply order, schema, token security, webhook, review UI): **`04_API_AND_INTEGRATION.md § QuickBooks Read-Only Sync — Pull → Stage → Review → Apply`**.

Financial-data view:

- **Customer mapping** — a QB customer with a `CompanyName` becomes a parent `clients` row (named the company) **plus** a `sub_clients` contact (the person), idempotent on `sub_clients.qb_id`; individuals stay flat. Invoices/payments attach to the **parent client** only. QB Jobs/sub-customers are recorded but not converted to projects this phase. (bug `d6951b82`.)
- **What lights up in iOS Books** — **P&L** (`payments in`, 24-mo window), **Cash Flow** (weekly net from imported payments), **A/R aging** (open invoices, balances reconciled to QB's authoritative `Balance` in apply STEP 5). The per-job profit (Jobs) card does **not** populate — QB invoices carry no OPS `project_id` (the boundary that motivates Sub-project B).
- **Apply correctness** — payments insert before the final invoice reconcile so `trg_payment_balance → update_invoice_balance()` and the QB-authoritative `Balance` reconcile agree; voided/zero-total QB invoices are skipped, never imported as live A/R.

### Edge Functions (3)

All deployed to Supabase, invoked via `SUPABASE_URL/functions/v1/<function-name>`. All use `verify_jwt: false` with manual auth header validation internally.

#### `accounting-oauth`

Handles OAuth flows for QuickBooks and Sage.

**Actions** (via `action` field in JSON body):
- `authorize` — Returns OAuth redirect URL for the provider
- `callback` — Exchanges authorization code for tokens, upserts `accounting_connections`
- `refresh` — Refreshes expired access token using refresh token
- `disconnect` — Clears tokens, sets `is_connected = false`

**Token management**:
- QuickBooks: Access tokens expire every 60 minutes, refresh tokens every 100 days
- Sage: Access tokens expire every 60 minutes
- Token refresh called automatically by `accounting-sync-expense` before sync operations

**Required env vars**: `QB_CLIENT_ID`, `QB_CLIENT_SECRET`, `QB_REDIRECT_URI`, `SAGE_CLIENT_ID`, `SAGE_CLIENT_SECRET`, `SAGE_REDIRECT_URI`

#### `accounting-sync-expense`

Syncs an approved expense to the company's connected accounting system.

**Trigger**: Called from iOS via `client.functions.invoke("accounting-sync-expense")` in `ExpenseRepository.triggerAccountingSync()`. Fires automatically from two paths in `ExpenseViewModel`:
- `approveExpense()` — after office/admin manually approves an expense
- `submitExpense()` — after auto-approve (expense amount < `expense_settings.auto_approve_threshold`)

Both paths are fire-and-forget (`Task { await ... }`), so the approval UX is never blocked by accounting sync.

**Flow**:
1. Fetch `accounting_connections` for the company
2. If no active connection → exit silently (no side effects for non-integrated companies)
3. Refresh token if expired (calls `accounting-oauth` refresh endpoint)
4. Map expense fields to provider format using `accounting_category_mappings`
5. POST to provider API
6. Update `accounting_sync_status` and `accounting_sync_id` on expense
7. Log to `accounting_sync_log`

**QuickBooks mapping**: OPS expense → QBO `Purchase` object
- `merchant_name` → `EntityRef` (vendor lookup/create)
- `amount` → `TotalAmt`
- `expense_date` → `TxnDate`
- Category → `AccountRef` via `accounting_category_mappings`
- Project allocation → `CustomerRef` for job costing

**Sage mapping**: OPS expense → Sage `OtherPayment` object
- `merchant_name` → `ContactId` (contact lookup/create)
- Category → `LedgerAccountId` via `accounting_category_mappings`

**Retry logic**: On transient failures (429, 5xx), retry up to 3 times with exponential backoff.

#### `accounting-batch-create`

Cron-triggered function that creates expense batches. Runs daily at 00:00 UTC.

**Flow**:
1. Query all companies with `expense_settings`
2. For each company, check if a batch is due based on `review_frequency`
3. Collect `submitted` expenses not yet in a batch
4. Create `expense_batch`, assign `batch_id` on expenses, calculate total
5. Log to `accounting_sync_log`

**Optional env var**: `CRON_SECRET` — shared secret for cron invocations via `X-Cron-Secret` header.

### accounting_category_mappings

When a company connects QB or Sage, they map each OPS expense category to an external chart of accounts entry. The mapping is stored in `accounting_category_mappings` and used on every sync to route expenses to the correct account.

| Column | Purpose |
|---|---|
| `company_id` | Company owning the mapping |
| `expense_category_id` | OPS expense category ID |
| `provider` | "quickbooks" or "sage" |
| `external_account_id` | Account ID in external system |
| `external_account_name` | Human-readable account name |

If no mapping exists for a category, the sync uses a fallback "Uncategorized Expenses" account.

---

## Activity Timeline & Follow-Ups

### Activity Entity

Communication and event log for opportunities and clients:

```typescript
interface Activity {
  id: string;
  companyId: string;
  opportunityId: string | null;
  clientId: string | null;
  estimateId: string | null;
  invoiceId: string | null;

  type: ActivityType;  // note | email | call | meeting | estimate_sent | estimate_accepted |
                       // estimate_declined | invoice_sent | payment_received | stage_change |
                       // created | won | lost | system
  subject: string;
  content: string | null;
  outcome: string | null;
  direction: "inbound" | "outbound" | null;
  durationMinutes: number | null;

  createdBy: string | null;
  createdAt: Date;
}
```

### Follow-Up Entity

Scheduled reminders attached to opportunities or clients:

```typescript
interface FollowUp {
  id: string;
  companyId: string;
  opportunityId: string | null;
  clientId: string | null;

  type: FollowUpType;  // call | email | meeting | quote_follow_up | invoice_follow_up | custom
  title: string;
  description: string | null;
  dueAt: Date;
  reminderAt: Date | null;
  completedAt: Date | null;
  assignedTo: string | null;    // User ID
  status: FollowUpStatus;       // pending | completed | skipped
  completionNotes: string | null;
  isAutoGenerated: boolean;     // True if created by pipeline stage auto-follow-up rules
  triggerSource: string | null;

  createdBy: string | null;
  createdAt: Date;
}
```

Auto-generated follow-ups are triggered by stage transitions based on `autoFollowUpDays` in `PipelineStageConfig`.

### Follow-Up Helpers

```typescript
isFollowUpOverdue(followUp)   // true if Pending and past dueAt
isFollowUpToday(followUp)     // true if Pending and due today
```

---

## Supabase Schema Reference

### Tables (22 total)

| Table | Purpose |
|---|---|
| `opportunities` | Pipeline deals/leads |
| `stage_transitions` | Immutable stage change history |
| `pipeline_stage_configs` | Per-company stage configuration |
| `estimates` | Quotes/proposals |
| `invoices` | Billing documents |
| `line_items` | Line items for estimates and invoices (polymorphic) |
| `payment_milestones` | Progress billing milestones |
| `payments` | Payment records (insert-only, trigger-maintained) |
| `products` | Products/services catalog |
| `tax_rates` | Per-company tax rate configurations |
| `accounting_connections` | QuickBooks/Sage OAuth connections |
| `accounting_sync_log` | Sync event log (success/error tracking) |
| `accounting_category_mappings` | OPS category → external chart of accounts mapping |
| `expenses` | Core expense records with receipt images and OCR data |
| `expense_project_allocations` | Multi-project expense attribution with percentage split |
| `expense_categories` | Company-configurable expense categories with icons |
| `expense_settings` | Per-company expense policy (thresholds, frequency, toggles) |
| `expense_batches` | Grouped expenses for batch review by office/admin |
| `activities` | Communication and event log |
| `follow_ups` | Scheduled follow-up reminders |
| `project_notes` | Project-level notes with @mentions and attachments (Feb 2026) |

### DB Conventions

- All tables use `snake_case` column names
- All monetary values: `NUMERIC(12,2)`
- Tax rates: stored as decimals (e.g. `0.0875` for 8.75%)
- `line_total` on line_items: `GENERATED ALWAYS AS (quantity * unit_price * (1 - discount_percent / 100.0)) STORED`
- `amount_paid`, `balance_due`, invoice `status` on invoices: maintained by payment triggers
- Soft deletes: `deleted_at TIMESTAMPTZ` (null = active)
- Payment voiding: `voided_at` + `voided_by` (NOT `deleted_at`)
- Row-Level Security (RLS) enabled on all tables

### RLS / Access Model

Every financial table enforces tenant isolation via a PERMISSIVE `company_isolation` policy `FOR ALL` (`company_id = (SELECT private.get_user_company_id())`); the financial/pipeline tables additionally layer RESTRICTIVE `role_scope_*` permission policies on top. Canonical per-table policy definitions live in `03_DATA_ARCHITECTURE.md` (§ Expense / Payment / Opportunity RLS Hardening, § Permissions System Tables) — the summary below is the financial-chapter cross-reference.

| Table | Tenant floor | Permission ceiling |
|-------|--------------|--------------------|
| `estimates` | `company_isolation` | `role_scope_*` keyed off `estimates.*` permissions |
| `invoices` | `company_isolation` | `role_scope_*` keyed off `invoices.*` permissions |
| `payments` | `company_isolation` | `role_scope_read` → `invoices.view` (added 2026-05-31) |
| `opportunities` | `company_isolation` | `role_scope_read` → `pipeline.view` (added 2026-05-31) |
| `expenses` | `company_isolation` | `role_scope_read/insert/update/delete` keyed off `expenses.view/create/edit/approve/delete`; `view`/`edit` `own`-scope branch compares `submitted_by` to `private.get_current_user_id()` |
| `expense_categories` | `company_isolation` | none (company reference data) |
| `expense_project_allocations` | `company_isolation` via parent expense (table has no `company_id`) | `role_scope_read` inherits the parent expense's `expenses.view` scope (`own` → parent `submitted_by`) |

**Security remediation (2026-05-31).** Migration `20260531200227_fix_expenses_rls_company_and_role_scope` replaced prior single permissive `USING (true)` policies on `expenses`, `expense_project_allocations`, and `expense_categories` — those policies had granted full CRUD to `anon` + `authenticated`, exposing every company's expense data to the shipped anon key with no login (cross-tenant breach). Migration `20260531200501_fix_payments_opportunities_permission_scope` added the `payments` / `opportunities` read ceiling. As a result, **expense `own`-scope (Crew / Operator) is now enforced at the database** via `submitted_by`, not app-layer-only: an `own`-scope user can no longer read or mutate another user's expense rows even by querying Supabase directly. Verified 2026-05-31 — the anon role returns 0 rows from all five tables, and an `own`-scope user sees only their own expenses.

### RPC Functions

```sql
get_next_document_number(p_company_id UUID, p_document_type TEXT)
-- Returns sequential document number: "EST-0001", "INV-0001" etc.
-- Atomic, race-condition-safe

convert_estimate_to_invoice(p_estimate_id UUID, p_due_date TIMESTAMPTZ)
-- Atomically: validates estimate=approved, creates invoice, copies line items,
-- marks estimate as converted. Returns invoice UUID.

get_next_expense_batch_number(p_company_id UUID)
-- Returns next sequential batch number for the company.
-- Counts existing batches + 1. Used by accounting-batch-create Edge Function.
```

---

## Service Layer Patterns

### camelCase ↔ snake_case Conversion

All conversion happens at the service layer:
- DB rows come in as `snake_case` objects
- TypeScript interfaces use `camelCase`
- Each service has `mapEntityFromDb(row)` and `mapEntityToDb(data)` functions
- Never include `GENERATED ALWAYS` columns in writes

### Shared Helpers

```typescript
// src/lib/supabase/helpers.ts
requireSupabase(): SupabaseClient  // Throws if env vars not set
parseDate(val: unknown): Date | null
parseDateRequired(val: unknown): Date
```

### TanStack Query Integration

Hooks are in `src/lib/hooks/`:
- `useEstimates(companyId, options)` — `useQuery` wrapper
- `useInvoices(companyId, options)` — `useQuery` wrapper
- `useProducts(companyId)` — `useQuery` wrapper
- `useAccounting(companyId)` — `useQuery` wrapper
- Mutation hooks use optimistic updates for pipeline drag-and-drop

---

## Business Rules & Constraints

### Pipeline Rules

1. Every opportunity must have either `clientId` (Bubble client) or at least `contactName`
2. Stage transitions are always recorded as immutable `stage_transitions` rows
3. Moving to Won should set `actualCloseDate` and optionally `projectId`
4. Moving to Lost requires a `lostReason` (prompted in UI)
5. Win probability is per-stage by default but can be overridden per opportunity
6. Stale threshold: 7 days default (configurable per stage in `pipeline_stage_configs`)
7. Auto follow-ups generated based on `autoFollowUpDays` on stage config

### Estimate Rules

1. Estimates link to a Bubble `clientId` (required) and optionally an `opportunityId`
2. `estimateNumber` generated by RPC — never set manually
3. Editing only allowed in `Draft` or `ChangesRequested` status
4. Sending sets status → `Sent` + `sent_at = now`
5. `convertToInvoice` RPC is the only valid way to convert — validates estimate is `Approved`
6. Line items: `line_total` is DB-generated — never write this column
7. Optional line items: `isOptional=true, isSelected=true/false`; only selected items count in totals
8. Pricing stored as snapshots on estimate header, not recomputed from line items at runtime

### Invoice Rules

1. `invoiceNumber` generated by RPC — never set manually
2. `amount_paid`, `balance_due`, `status` maintained by DB triggers — never update manually
3. Payment voiding uses `voided_at`/`voided_by`, NOT `deleted_at`
4. Payment insert → trigger recalculates invoice balance and status
5. Payment void → trigger recalculates invoice balance and status
6. Invoices can link to an estimate, opportunity, and/or project
7. `voidInvoice` = sets status=Void; soft delete = sets deleted_at

### Product Rules

1. Products soft-deleted via `deleted_at`
2. Inactive products (`isActive=false`) excluded from catalog by default
3. Deleting a product does NOT cascade to line items (line items retain snapshot data)
4. `unitCost` is optional, used for margin calculation only

### Expense Rules

1. All roles can create and submit expenses (requires `expenses.create` permission — all preset roles have it)
2. Only users with `expenses.approve` permission can approve/reject expenses (Admin, Owner, Office by default). Enforced at the app layer and at the database via the `expenses.role_scope_update` RLS policy. As of the 2026-05-31 security remediation, expense access is fully DB-enforced: `own`-scope users (Crew / Operator) can only read/edit/delete expenses where `submitted_by` matches their own user id, and the anon key can read nothing — see the § RLS / Access Model table above and `03_DATA_ARCHITECTURE.md` § Expense / Payment / Opportunity RLS Hardening (2026-05-31)
3. Auto-approve logic: if amount < `auto_approve_threshold`, status goes directly to `approved` on submission
4. Expenses above `admin_approval_threshold` require admin approval specifically (user must have `expenses.approve` permission)
5. `batch_id` is null until the expense is collected into a batch by the cron Edge Function
6. `accounting_sync_status`: `pending` (no connection), `synced` (pushed to QB/Sage), `error` (sync failed)
7. Receipt images uploaded to S3 via `S3UploadService.shared.uploadExpenseReceipt()` — full-size (max 2048px) at `company-{companyId}/expenses/receipt_{expenseId}_{timestamp}.jpg` plus 512px thumbnail variant
8. OCR data (raw text, extracted fields, confidence) stored in `ocr_raw_data` (JSONB) and `ocr_confidence` (0-1) for audit trail — captured from `AppleVisionOCRService` via `OCRResult.rawDataDict`
9. Expense allocations (project splits) use delete-and-reinsert pattern when updated
10. Default categories seeded automatically on first load per company

### Accounting Integration Rules

1. QuickBooks and Sage are the supported providers
2. OAuth tokens stored in `accounting_connections` — refresh token rotation handled server-side via `accounting-oauth` Edge Function
3. Approved expenses auto-sync to connected accounting when `sync_enabled = true`
4. Category mapping via `accounting_category_mappings` — each OPS category maps to an external account
5. Vendor/contact lookup-or-create pattern used for `merchant_name` in both QB and Sage
6. Sync retries up to 3x with exponential backoff on transient failures (429, 5xx)
7. All sync operations logged in `accounting_sync_log` for audit trail
8. Payment voiding uses `voided_at` not `deleted_at`

---

## iOS Implementation

The full Pipeline, Estimates, Invoices, and Accounting system is implemented natively on iOS using SwiftUI, with Supabase as the backend via dedicated Repository classes and DTOs.

### iOS View Layer

**Location**: `OPS/OPS/Views/Estimates/`, `OPS/OPS/Views/Invoices/`, `OPS/OPS/Views/Accounting/`

#### Estimates Views (6 files)

| File | Purpose |
|---|---|
| `EstimatesListView.swift` | List of all company estimates with search, filter chips (ALL/DRAFT/SENT/APPROVED), pull-to-refresh, and a FAB for creating new estimates. Swipe-right on draft to send, swipe-right on approved to convert to invoice. |
| `EstimateDetailView.swift` | Full detail for a single estimate showing header (estimate number, title, total, status badge, age), line items section, totals section (subtotal/tax/total), and a context-dependent sticky footer (EDIT/SEND for draft, RESEND/MARK APPROVED for sent, CONVERT TO INVOICE for approved). Overflow menu provides additional actions. |
| `EstimateFormSheet.swift` | Create or edit an estimate with collapsible sections (Client & Project, Line Items, Payment & Terms, Notes & Attachments). Line items always expanded. Sticky footer shows running subtotal/tax/total and a SEND EST button. Auto-creates estimate on first open in create mode. |
| `EstimateCard.swift` | Card component for estimate list showing estimate number, title, total, status badge with color, and age. Supports swipe-right (SEND for draft, CONVERT for approved) and swipe-left (VOID). |
| `LineItemEditSheet.swift` | Bottom sheet for creating or editing a line item. Fields: description, type picker (LABOR/MATERIAL/OTHER), quantity, unit, unit price, optional toggle, taxable toggle. Shows computed line total. Delete button in edit mode. |
| `ProductPickerSheet.swift` | Bottom sheet to select a product from the catalog. Search field filters products by name. Tapping a product adds it as a line item (pre-fills name, type, default price, productId). Loads products via `ProductRepository.fetchAll()`. |

#### Invoice Views (4 files)

| File | Purpose |
|---|---|
| `InvoicesListView.swift` | List of all invoices with filter chips (ALL/UNPAID/OVERDUE/PAID), search, pull-to-refresh. Swipe-right to record payment, swipe-left to void. No FAB (invoices are created via estimate conversion). |
| `InvoiceDetailView.swift` | Full detail for a single invoice showing header (invoice number, title, total, status badge, due/overdue date), line items section, totals section (subtotal/tax/total/paid/balance due), payments section. Sticky footer is context-dependent: SEND INVOICE for draft, BALANCE DUE + RECORD PAYMENT for unpaid, PAID IN FULL for paid, VOIDED for void. Toolbar menu provides Send/Record Payment/Void actions. |
| `InvoiceCard.swift` | Card component showing invoice number, title, total, status badge with color, and due/overdue date. Overdue invoices get a red border. Swipe-right reveals PAYMENT action, swipe-left reveals VOID. |
| `PaymentRecordSheet.swift` | Bottom sheet to record a payment. Shows invoice context (number + balance). Fields: amount (pre-filled with balance due), payment method picker (all `PaymentMethod` cases with checkmark selection), optional notes. Calls `InvoiceViewModel.recordPayment()`. |

#### Expense Views (7 files)

**Location**: `OPS/OPS/Views/Expenses/`

| File | Purpose |
|---|---|
| `ExpensesListView.swift` | List of all company expenses with search, filter chips (ALL/PENDING/APPROVED/REJECTED), pull-to-refresh, and FAB for creating new. Swipe-right on draft to submit, swipe-left to delete. |
| `ExpenseDetailView.swift` | Full detail for a single expense: receipt image (tappable for full-screen), OCR-extracted fields, project allocations with percentages, approval status/history. Context-dependent action footer (EDIT/SUBMIT for draft, APPROVE/REJECT for office/admin). |
| `ExpenseFormSheet.swift` | Create/edit sheet with camera capture button, OCR auto-fill, detail fields (merchant, amount, tax, date, category, payment method), project allocation section with percentage sliders, notes. Accepts optional `prefilledProjectId`. Sticky footer with submit. |
| `ExpenseCard.swift` | Card for list: merchant name + amount, category icon + name, date, status badge. Swipe-right = SUBMIT (drafts), swipe-left = DELETE. |
| `ExpenseBatchReviewView.swift` | Office/admin batch review. Header with batch info (period, count, total). Expandable expense cards with receipt thumbnail + details. Approve/reject per item. "Approve All" toolbar button. |
| `ExpenseCategorySettingsView.swift` | Category management: icon + name list, active toggle, add custom category sheet. |
| `ExpenseSettingsView.swift` | Company expense settings: review frequency picker, threshold amount fields, policy toggles (require receipt, require project), save button. |

#### A/R Views (1 file)

| File | Purpose |
|---|---|
| `ARAgingDetailView.swift` | Read-only A/R drill-down. Two sections: (1) **Aging Buckets** horizontal bar chart (0–30d, 31–60d, 61–90d, 90d+) using Swift Charts, (2) **Top Outstanding** list of top 5 clients by outstanding balance. Loaded via `AccountingRepository.fetchAllInvoices()`. Presented as a sheet from the BOOKS carousel's A/R card top-chase tile and from the carousel's OUTSTANDING tile. Pull-to-refresh. (Note: `AccountingDashboard.swift` was replaced by this view in an earlier session — bible drift D1 caught and reconciled 2026-05-11 during Books Phase 2 work.) |

### iOS ViewModels

**Location**: `OPS/OPS/ViewModels/`

All ViewModels are `@MainActor` `ObservableObject` classes. Each exposes `@Published` state, sets up a repository via `setup(companyId:)`, and provides async methods for data operations.

#### PipelineViewModel

Manages the pipeline CRM opportunity list.

- **Published state**: `opportunities`, `selectedStage` (filter, nil = ALL), `searchText`, `isLoading`, `error`
- **Computed properties**: `filteredOpportunities` (by stage + search on contactName/jobDescription/source), `totalPipelineValue`, `weightedPipelineValue`, `activeDealsCount`, `stagesWithCounts`
- **Operations**: `loadOpportunities()`, `advanceStage(opportunity:)` (optimistic update), `markLost(opportunity:reason:)`, `markWon(opportunity:)`, `createOpportunity(...)`, `updateOpportunity(...)`, `deleteOpportunity(...)`
- **Repository**: `OpportunityRepository`

#### EstimateViewModel

Manages the estimate list, line items, filtering, and status actions.

- **Published state**: `estimates`, `selectedFilter` (ALL/DRAFT/SENT/APPROVED enum), `searchText`, `isLoading`, `error`
- **Internal state**: `lineItemDTOs` dictionary keyed by estimate ID
- **Computed**: `filteredEstimates` (by filter + search on title/estimateNumber)
- **Operations**: `loadEstimates()`, `lineItems(for:)`, `createEstimate(title:companyId:opportunityId?:clientId?:)`, `addLineItem(estimateId:description:type:quantity:unitPrice:isOptional:productId?:)`, `updateLineItem(id:estimateId:description?:quantity?:unitPrice?:isOptional?:)`, `deleteLineItem(id:estimateId:)`, `updateTitle(estimateId:title:)`, `sendEstimate(_:)`, `markApproved(_:)`, `convertToInvoice(_:)`
- **Repository**: `EstimateRepository`

#### InvoiceViewModel

Manages the invoice list, line items, payments, filtering, and status actions.

- **Published state**: `invoices`, `selectedFilter` (ALL/UNPAID/OVERDUE/PAID enum), `searchText`, `isLoading`, `error`
- **Internal state**: `lineItemDTOs` and `paymentDTOs` dictionaries keyed by invoice ID
- **Computed**: `filteredInvoices` (by filter + search on title/invoiceNumber)
- **Operations**: `loadInvoices()`, `lineItems(for:)`, `payments(for:)`, `recordPayment(invoiceId:companyId:amount:method:notes?:)`, `voidInvoice(_:)`, `sendInvoice(_:)`
- **Critical pattern**: After `recordPayment`, the ViewModel re-fetches the invoice from Supabase to get DB-trigger-updated `amountPaid`, `balanceDue`, and `status`. Never manually updates these fields.
- **Repository**: `InvoiceRepository`

#### ExpenseViewModel

Manages expense list, categories, batches, OCR scanning, and approval actions.

- **Published state**: `expenses`, `categories`, `batches`, `selectedFilter` (ALL/PENDING/APPROVED/REJECTED enum), `searchText`, `isLoading`, `error`, `settings`
- **Computed**: `filteredExpenses` (by filter + search on merchantName/description)
- **Operations**: `loadAll()` (parallel: expenses + categories + settings + batches), `loadExpenses()`, `createExpense(...)`, `updateExpense(...)`, `deleteExpense(_:)`, `submitExpense(_:)` (with auto-approve threshold check), `approveExpense(_:)`, `rejectExpense(_:reason:)`, `setAllocations(_:allocations:)`, `loadCategories()`, `loadBatches()`, `toggleCategory(_:isActive:)`, `scanReceipt(image:)` (OCR via AppleVisionOCRService), `loadSettings()`, `saveSettings(_:)`, `createCategory(companyId:name:icon:)`
- **Project-scoped**: `loadExpensesForProject(projectId:)` — loads expenses allocated to a specific project
- **Repository**: `ExpenseRepository`

#### OpportunityDetailViewModel

Manages activities and follow-ups for a single opportunity detail screen.

- **Published state**: `activities`, `followUps`, `isLoading`, `error`
- **Operations**: `loadDetails(for:)` (parallel fetch of activities + follow-ups via `async let`), `logActivity(opportunityId:companyId:type:body?:)`, `createFollowUp(opportunityId:companyId:type:dueAt:notes?:)`
- **Repository**: `OpportunityRepository`

### iOS Supabase Repositories

**Location**: `OPS/OPS/Network/Supabase/Repositories/`

All repositories take `companyId` in their initializer and use `SupabaseService.shared.client` for the Supabase connection.

#### EstimateRepository

- `fetchAll()` -- selects `*, line_items(*)` filtered by `company_id`, ordered by `created_at` desc
- `fetchOne(estimateId)` -- selects `*, line_items(*)` for single estimate
- `create(CreateEstimateDTO)` -- inserts estimate, returns with line items
- `updateTitle(estimateId, title)` -- updates title field only
- `updateStatus(estimateId, status)` -- updates status, returns full estimate with line items
- `addLineItem(CreateLineItemDTO)` -- inserts into `line_items` table
- `updateLineItem(id, UpdateLineItemDTO)` -- updates line item fields
- `deleteLineItem(id)` -- hard deletes from `line_items` table
- `convertToInvoice(estimateId)` -- calls Supabase RPC `convert_estimate_to_invoice`, returns `InvoiceDTO`

#### InvoiceRepository

- `fetchAll()` -- selects `*, invoice_line_items(*), payments(*)` filtered by `company_id`, ordered by `created_at` desc
- `fetchOne(invoiceId)` -- selects `*, invoice_line_items(*), payments(*)` for single invoice
- `recordPayment(CreatePaymentDTO)` -- inserts into `payments` table (DB trigger maintains invoice balance/status)
- `updateStatus(invoiceId, status)` -- updates status field
- `voidInvoice(invoiceId)` -- sets status to void (calls `updateStatus` internally)

#### AccountingRepository

- `fetchAllInvoices()` -- selects `*, invoice_line_items(*), payments(*)` filtered by `company_id`, ordered by `created_at` desc. Used exclusively by `AccountingDashboard` for read-only financial health computations (AR aging, status counts, top outstanding).

#### ExpenseRepository

- `fetchAll()` -- selects `*, expense_project_allocations(*), expense_categories(*)` filtered by `company_id`, ordered by `created_at` desc
- `fetchOne(expenseId)` -- single expense with allocations and category
- `create(CreateExpenseDTO)` -- inserts expense
- `update(expenseId, UpdateExpenseDTO)` -- updates draft expense fields
- `updateStatus(expenseId, status)` -- updates status field
- `approve(expenseId, approvedBy)` -- sets status=approved, approved_by, approved_at
- `reject(expenseId, rejectedBy, reason)` -- sets status=rejected, rejection_reason
- `softDelete(expenseId)` -- sets `deleted_at` timestamp
- `setAllocations(expenseId, [CreateExpenseAllocationDTO])` -- delete existing + insert new (transactional)
- `fetchByProject(projectId)` -- expenses allocated to a project (via allocation join)
- `fetchCategories()` -- active categories for the company
- `createCategory(CreateExpenseCategoryDTO)` -- add custom category
- `updateCategory(id, name, icon, isActive)` -- modify category
- `seedDefaultCategories()` -- seeds 9 default categories if none exist for company
- `fetchBatches()` -- all batches for the company
- `fetchBatchExpenses(batchId)` -- expenses in a specific batch
- `fetchSettings()` -- company expense settings
- `upsertSettings(ExpenseSettingsDTO)` -- save/update settings
- `triggerAccountingSync(expenseId)` -- fire-and-forget call to `accounting-sync-expense` Edge Function via `client.functions.invoke()`; logs errors but does not throw
- `fetchCategoryMappings(provider)` -- accounting category mappings for a provider (quickbooks/sage)
- `upsertCategoryMapping(CreateAccountingCategoryMappingDTO)` -- upsert mapping (unique on company_id + category_id + provider)
- `deleteCategoryMapping(id)` -- remove a mapping

#### OpportunityRepository

- `fetchAll()` -- selects all opportunities filtered by `company_id`, ordered by `created_at` desc
- `fetchOne(opportunityId)` -- single opportunity
- `fetchActivities(for opportunityId)` -- selects activities for an opportunity, ordered by `created_at` desc
- `fetchFollowUps(for opportunityId)` -- selects follow-ups for an opportunity, ordered by `due_at` asc
- `create(CreateOpportunityDTO)` -- inserts new opportunity
- `logActivity(CreateActivityDTO)` -- inserts into `activities` table
- `createFollowUp(CreateFollowUpDTO)` -- inserts into `follow_ups` table
- `advanceStage(opportunityId, to stage, lossReason?)` -- updates `stage` (and optionally `loss_reason`) on the opportunity
- `update(opportunityId, UpdateOpportunityDTO)` -- updates opportunity fields
- `delete(opportunityId)` -- hard deletes opportunity

#### ProductRepository

- `fetchAll()` -- selects active products (`is_active = true`) filtered by `company_id`, ordered by `name` asc
- `create(CreateProductDTO)` -- inserts new product
- `update(id, UpdateProductDTO)` -- updates product fields
- `deactivate(id)` -- sets `is_active` to false (soft deactivation)

### iOS Financial DTOs

**Location**: `OPS/OPS/Network/Supabase/DTOs/`

7 DTO files cover the financial system. All use `Codable` with `CodingKeys` for `snake_case` <-> `camelCase` mapping. Each read-DTO has a `toModel()` method to convert to the local domain model.

#### ExpenseDTOs.swift

| DTO | Purpose |
|---|---|
| `ExpenseDTO` | Read DTO for expenses table. Fields: id, companyId, submittedBy, status, categoryId, merchantName, description, amount, taxAmount, currency, expenseDate, paymentMethod, receiptImageUrl, receiptThumbnailUrl, ocrRawData, ocrConfidence, batchId, approvedBy, approvedAt, rejectedBy, rejectionReason, accountingSyncStatus, accountingSyncId, deletedAt, createdAt, updatedAt. Nested: `allocations: [ExpenseAllocationDTO]?`, `category: ExpenseCategoryDTO?`. |
| `CreateExpenseDTO` | Write DTO. Fields: companyId, submittedBy, categoryId, merchantName, description, amount, taxAmount, expenseDate, paymentMethod, receiptImageUrl. |
| `UpdateExpenseDTO` | Partial update DTO. Optional fields: categoryId, merchantName, description, amount, taxAmount, expenseDate, paymentMethod, receiptImageUrl. |
| `ExpenseAllocationDTO` | Read DTO for expense_project_allocations. Fields: id, expenseId, projectId, percentage, createdAt. |
| `CreateExpenseAllocationDTO` | Write DTO. Fields: expenseId, projectId, percentage. |
| `ExpenseCategoryDTO` | Read DTO for expense_categories. Fields: id, companyId, name, icon, isActive, isDefault, sortOrder, createdAt. |
| `CreateExpenseCategoryDTO` | Write DTO. Fields: companyId, name, icon. |
| `ExpenseBatchDTO` | Read DTO for expense_batches. Fields: id, companyId, batchNumber, periodStart, periodEnd, status, totalAmount, expenseCount, reviewedBy, reviewedAt, createdAt. |
| `ExpenseSettingsDTO` | Read/Write DTO. Fields: id, companyId, reviewFrequency, autoApproveThreshold, adminApprovalThreshold, requireReceiptPhoto, requireProjectAssignment, createdAt, updatedAt. |

#### EstimateDTOs.swift

| DTO | Purpose |
|---|---|
| `EstimateDTO` | Read DTO for estimates table. Fields: id, companyId, estimateNumber, opportunityId, projectId, clientId, title, status, subtotal, taxRate, taxAmount, discountPercent, discountAmount, total, notes, validUntil, version, createdAt, updatedAt. Nested: `lineItems: [EstimateLineItemDTO]?`. |
| `EstimateLineItemDTO` | Read DTO for line_items table. Fields: id, estimateId, productId, description, quantity, unitPrice, unit, total, sortOrder, isOptional, taskTypeId, type. |
| `CreateEstimateDTO` | Write DTO. Fields: companyId, opportunityId, clientId, title. |
| `CreateLineItemDTO` | Write DTO. Fields: estimateId, productId, description, quantity, unitPrice, sortOrder, isOptional, taskTypeId, type. |
| `UpdateLineItemDTO` | Partial update DTO. Optional fields: description, quantity, unitPrice, sortOrder, isOptional. |

#### InvoiceDTOs.swift

| DTO | Purpose |
|---|---|
| `InvoiceDTO` | Read DTO for invoices table. Fields: id, companyId, estimateId, opportunityId, projectId, clientId, invoiceNumber, title, status, subtotal, taxRate, taxAmount, total, amountPaid, balanceDue, dueDate, sentAt, paidAt, notes, createdAt, updatedAt. Nested: `lineItems: [InvoiceLineItemDTO]?`, `payments: [PaymentDTO]?`. Note: `lineItems` CodingKey maps to `invoice_line_items`. |
| `InvoiceLineItemDTO` | Read DTO for invoice_line_items table. Fields: id, invoiceId, productId, description, quantity, unitPrice, unit, type, total, sortOrder. |
| `PaymentDTO` | Read DTO for payments table. Fields: id, invoiceId, companyId, amount, method, reference, notes, isVoid, paidAt, createdAt. |
| `CreatePaymentDTO` | Write DTO. Fields: invoiceId, companyId, amount, method, reference, notes. |

#### ProductDTOs.swift

| DTO | Purpose |
|---|---|
| `ProductDTO` | Read DTO for products table. Fields: id, companyId, name, description, unitPrice, costPrice, unit, type, taxable, taskTypeId, isActive, createdAt, updatedAt. |
| `CreateProductDTO` | Write DTO. Fields: companyId, name, description, unitPrice, costPrice, unit, type, taxable. |
| `UpdateProductDTO` | Partial update DTO. Optional fields: name, description, unitPrice, costPrice, unit, type, taxable. |

#### OpportunityDTOs.swift

| DTO | Purpose |
|---|---|
| `OpportunityDTO` | Read DTO for opportunities table. Fields: id, companyId, contactName, contactEmail, contactPhone, jobDescription, estimatedValue, stage, source, projectId, clientId, lossReason, createdAt, updatedAt, lastActivityAt. |
| `CreateOpportunityDTO` | Write DTO. Fields: companyId, contactName, contactEmail, contactPhone, jobDescription, estimatedValue, source. |
| `UpdateOpportunityDTO` | Partial update DTO. Optional fields: contactName, contactEmail, contactPhone, jobDescription, estimatedValue, source, clientId, projectId. |
| `ActivityDTO` | Read DTO for activities table. Fields: id, opportunityId, companyId, type, body, createdBy, createdAt. |
| `CreateActivityDTO` | Write DTO. Fields: opportunityId, companyId, type, body. |
| `FollowUpDTO` | Read DTO for follow_ups table. Fields: id, opportunityId, companyId, type, status, dueAt, assignedTo, notes, createdAt. |
| `CreateFollowUpDTO` | Write DTO. Fields: opportunityId, companyId, type, dueAt, notes. |

### iOS Financial Enums

**Location**: `OPS/OPS/DataModels/Enums/FinancialEnums.swift`

All enums are `String`-backed, `Codable`, and match Supabase column values.

#### EstimateStatus

Cases: `draft`, `sent`, `viewed`, `approved`, `converted`, `declined`, `expired`

Computed helpers:
- `displayName` -- uppercased raw value
- `canSend` -- true for `.draft`
- `canApprove` -- true for `.sent` or `.viewed`
- `canConvert` -- true for `.approved`

#### InvoiceStatus

Cases: `draft`, `sent`, `awaitingPayment` ("awaiting_payment"), `partiallyPaid` ("partially_paid"), `paid`, `pastDue` ("past_due"), `void`

Computed helpers:
- `displayName` -- custom: "AWAITING" for awaitingPayment, "PARTIAL" for partiallyPaid, uppercased raw value otherwise
- `isPaid` -- true for `.paid`
- `needsPayment` -- true for `.awaitingPayment`, `.partiallyPaid`, or `.pastDue`

#### PaymentMethod

Cases: `cash`, `check`, `creditCard` ("credit_card"), `ach`, `bankTransfer` ("bank_transfer"), `stripe`, `other`

Computed helper: `displayName` -- custom formatting for multi-word names (CREDIT CARD, ACH, BANK TRANSFER), uppercased raw value otherwise.

#### LineItemType

Cases: `labor` ("LABOR"), `material` ("MATERIAL"), `other` ("OTHER")

Note: Raw values are uppercase (matches Supabase column values).

#### FollowUpType

Cases: `call`, `email`, `meeting`, `quoteFollowUp` ("quote_follow_up"), `invoiceFollowUp` ("invoice_follow_up"), `custom`

Computed helper: `icon` -- returns SF Symbol name for each type (phone.fill, envelope.fill, person.2.fill, doc.text.fill, receipt, bell.fill).

#### FollowUpStatus

Cases: `pending`, `completed`, `skipped`

#### SiteVisitStatus

Cases: `scheduled`, `completed`, `cancelled`

#### ExpenseStatus

Cases: `draft`, `submitted`, `approved`, `rejected`, `reimbursed`

Computed helpers:
- `displayName` -- uppercased raw value
- `color` -- status-appropriate color (tertiaryText for draft, warning for submitted, success for approved, error for rejected, primaryAccent for reimbursed)

#### ExpensePaymentMethod

Cases: `cash`, `personalCard` ("personal_card"), `companyCard` ("company_card")

Computed helper: `displayName` -- "CASH", "PERSONAL CARD", "COMPANY CARD"

#### ReviewFrequency

Cases: `perJob` ("per_job"), `weekly`, `biweekly`, `monthly`, `quarterly`

Computed helper: `displayName` -- "PER JOB", "WEEKLY", "BIWEEKLY", "MONTHLY", "QUARTERLY"

#### AccountingSyncStatus

Cases: `pending`, `synced`, `error`

### iOS OCR Service

**Location**: `OPS/OPS/Services/ExpenseOCRService.swift`

Protocol-based architecture for receipt OCR:

```swift
protocol ExpenseOCRServiceProtocol {
    func extractReceiptData(from image: UIImage) async throws -> OCRResult
}
```

**OCRResult** struct: `merchantName`, `date`, `total`, `subtotal`, `taxAmount`, `paymentMethod`, `rawText`, `confidenceScores` (per-field confidence 0-1).

**AppleVisionOCRService**: Uses `VNRecognizeTextRequest` with `.accurate` recognition level. Processes all recognized text through `ReceiptParser` which uses regex patterns and heuristics to extract structured fields from raw OCR text.

### iOS BOOKS Tab (Phase 3 — Mission Deck, May 2026)

**Status:** Visual rebuild landed 2026-05-19 on branch `feat/books-mission-deck` (spec `ops-ios/docs/superpowers/specs/2026-05-19-books-tab-mission-deck-rebuild.md`, Phases A–H; Phase I is build verification + this bible update). The Phase 2 carousel architecture — 5-card hero + 3-segment list — is unchanged; every visual treatment was rebuilt against the approved "Mission Deck" design, and an entire new state layer was added (sync banner, skeletons, card-level error, drill filter chip, scope-hint badges, per-card empty states). No schema or migration changes — all Phase 3 ViewModel additions are computed. Lineage: Phase 1 4-segment hub (2026-05-07) → Phase 2 carousel command center (2026-05-11) → Phase 3 Mission Deck visual rebuild (2026-05-19) → Phase 6 condensed-card + expand-sheet UX overhaul (2026-06-01).

**Phase 6 overhaul (2026-06-01, branch `feat/books-ux-overhaul`, spec `2026-06-01-books-condensed-cards-ux-overhaul-design.md`):** the hero carousel was rebuilt from inline full-rich cards (variable height) into **condensed cards + expand-to-sheet** — each lens is now a uniform-height compact L2 glance tile (headline metric + one signature mini-viz + a sub-stat) that taps to open its full content in a reused half-sheet (`ExpandedCardSheet`; A/R opens the merged `ARDetailSheet`). The in-card drill actions moved into the sheet. The below-picker area became a **single-scroll page** (embedded lists drop their inner `ScrollView`) with a **pinned section header** (picker + drill chip + `// SEGMENT · count` + hairline). The carousel paging bleed was fixed (`containerRelativeFrame(count:span:spacing:)`), and the redundant in-view expense FAB was removed in favour of the global `FloatingActionMenu` (with a new `opsExpensesDidChange` notification so embedded lists refresh after a global-FAB create). No `MoneyDashboardViewModel` math changed — purely presentation/interaction.

**Surface:**
- Rendered by `MainTabView` (tab icon `chart.line.uptrend.xyaxis`); container `BooksTabView` (`OPS/Views/Books/BooksTabView.swift`). Header `AppHeader.HeaderType.books` (title "BOOKS").
- Top-to-bottom in **one scroll surface** (P6): AppHeader → optional sync banner → `HeroCarousel` (condensed glance strip) → `CashflowForecastCard` (when `finances.view`) → a **pinned section header** (`Section` header inside a `LazyVStack(pinnedViews: [.sectionHeaders])`) carrying the inset-pill segmented control + optional drill filter chip + a `// SEGMENT · count` label + a hairline → the selected segment's list rendered **inline** (no nested `ScrollView`). On scroll the carousel collapses to `CollapsedCarouselStrip` shown inside the pinned header.

**Hero carousel** — `HeroCarousel` (`OPS/Views/Books/HeroCarousel.swift`): swipeable 5-card paged surface of **condensed glance tiles** (one uniform L2 height), `ScrollView(.horizontal)` + `.scrollTargetBehavior(.paging)` + `.containerRelativeFrame(.horizontal, count: 1, span: 1, spacing:)` (P6 — paging width accounts for the inter-card gap, fixing the cumulative rightward bleed) + `.scrollPosition` (iOS 17+), **not** `TabView(.page)` (avoids spring physics per the OPS motion rule). Each tile shows the lens's headline metric + one signature mini-viz + a sub-stat; **tapping it opens the lens's full content in a half-sheet** (`ExpandedCardSheet`, or the merged `ARDetailSheet` for A/R) — the drill actions live in the sheet. Light impact haptic on each swap, `.selection` on tap. Cards are permission-filtered; the last-viewed card persists via `@AppStorage("books.lastViewedCard")`.

| Card | Question | Period scope | Permission |
|------|----------|--------------|------------|
| `PLCard` | "Am I making money this period?" | Follows period pill | `finances.view` |
| `CashFlowCard` | "What's my cash rhythm?" | Follows period pill | `finances.view` |
| `ARCard` | "Who do I need to chase?" | Always all-open | `finances.view` |
| `ForecastCard` | "What's coming if pipeline plays out?" | Always active | `pipeline.view` |
| `JobsCard` | "Which jobs made me money? Which lost it?" | Follows period pill | `finances.view` |

Per-card composition (`OPS/Views/Books/Cards/`):
- **Card 1 — `PLCard`.** Hero `NET CASH` = `viewModel.netCash` (Mohave Light 60pt, rose when negative). Below: a margin meter (olive fill over a tan-soft track), a sign-keyed `X% MARGIN` caption, and a `PAYMENTS IN` / `EXPENSES OUT` row. Drill tiles: `OUTSTANDING` (overdue invoices value + count) and `FORECAST` (pending estimates value + count). Source: in-period payments + expenses.
- **Card 2 — `CashFlowCard`.** Hero `NET CASH · {N}W TRAILING`. Body: a weekly-net sparkline drawn with SwiftUI `Canvas` — zero-axis hairline, olive line + olive-soft area fill, per-point dots; any week where expenses-out exceeded payments-in gets a rose marker (bad-week rule). Drill tiles: `SALES`, `AVG/WK`, `DAYS`. Source: `paymentsByWeek` / `expensesByWeek` (ISO-week buckets).
- **Card 3 — `ARCard`.** Hero `TOTAL OUTSTANDING` (rose) with a `{open} OPEN · {overdue} OVERDUE` subline. Body: a single continuous aging ramp of four colored segments sized by bucket amount (0–30 olive, 31–60 receivables-tan, 61–90 warning-tan, 90+ overdue-brick) and a 4-column bucket grid. A full-width `TOP CHASE` tile surfaces the most-overdue invoice. Period-independent. Source: `outstandingInvoiceBreakdown`, `overdueInvoicesCount`.
- **Card 4 — `ForecastCard`.** Hero `WEIGHTED FORECAST` (steel-blue accent) with a `{N} ACTIVE OPPORTUNITIES` subline. Body: per-stage bars in funnel order — each row shows the stage name, an `×{avgProbability}%` indicator, and the weighted dollar value. Drill tiles: `CLOSE RATE`, `STALE`. Source: `weightedForecastByStage` (`[StageForecast]`).
- **Card 5 — `JobsCard`.** No hero number — label `TOP 5 JOBS BY NET`. Body: diverging profit/loss bars from a center axis (olive extends right for profit, rose left for loss); each row shows job title, signed margin %, signed net $. Drill tiles: `PROFITABLE`, `AVG MARGIN` (read-only), `LOSERS`. Source: `topProjectsByNet` (`[JobNet]`).

**Carousel chrome:**
- Inline header — the active card's label (JetBrains Mono 11pt, 0.16em, semibold, uppercase) left-aligned, `PeriodPill` right-aligned.
- Scope-hint badges (`BooksScopeHintBadge`) — rendered beside the header label on Card 3 (`ALL OPEN`, rose) and Card 4 (`ACTIVE`, accent), signalling that those two cards do not respond to the period pill.
- Dot pagination — the active dot is a 22×6 white capsule, inactive dots are 6×6 muted; the capsule width animates over the canonical 200ms easing. Each dot carries a 44pt hit target and jumps to its card on tap.
- `PeriodPill` (`OPS/Views/Books/Components/PeriodPill.swift`) — a single 44pt-minimum tap-target opening a `Menu` of 8 periods (30 DAYS / 90 DAYS / 6 MONTHS / 1 YEAR / THIS MONTH / LAST MONTH / THIS QUARTER / YEAR TO DATE). Drives Cards 1, 2, 5; Cards 3 and 4 ignore it.

**Segmented control + drill filter chip:**
- Inset-pill control — 3 segments **INVOICES · ESTIMATES · EXPENSES**, replacing the Phase 2 underline control. The active segment is a neutral white-fill pill with a 1pt inset top-light and no accent color (OPS "no accent on toggles" rule). Light haptic on switch. Each segment renders its existing list view in `embedded: true` mode.
- `BooksDrillFilterChip` — appears below the segmented control when a carousel drill applied a filter (`OVERDUE` for Invoices, `SENT` for Estimates). Tapping × clears the filter.

**Drill interactions** — three carousel drills are wired; the remaining five tiles are present and VoiceOver-labelled but have deferred no-op handlers:
- Card 1 `OUTSTANDING` → Invoices segment, `overdue` filter applied.
- Card 1 `FORECAST` → Estimates segment, `sent` filter applied.
- Card 3 `TOP CHASE` → `ARAgingDetailView` presented as a half-sheet (`.presentationDetents([.medium, .large])`, drag indicator visible).
- Deferred no-ops: Card 2 `DAYS`, Card 4 `CLOSE RATE` / `STALE`, Card 5 `PROFITABLE` / `LOSERS` — full-screen reports and Pipeline-tab drills are future scope.

**States** — sync banner, skeleton, card-level error, per-card empty (`OPS/Views/Books/Components/`):
- `BooksSyncBanner` — slim banner above the carousel whenever `MoneyDashboardViewModel.syncState != .synced`: a pulsing-dot `SYS :: SYNC · HH:mm` while syncing, or `SYS :: OFFLINE · CACHED HH:mm` / `SYS :: ERROR · LAST HH:mm` with a RETRY action.
- `BooksSkeleton` — per-card skeleton placeholders for the cold-paint, no-cache path (`!hasEverLoaded && isLoading`); each card's skeleton mirrors its real layout.
- `BooksCardError` — card-level fail-soft error. A failed repository fetch routes only the affected cards into an error state (`— / // ERROR — LOAD FAILED / [RETRY →]`) while sibling cards keep rendering live data.
- Per-card empty states — a card with zero data (after a load completed) renders an empty hero (`$0` / `—`) and a `// NO …` tactical label instead of a blank card.
- Pull-to-refresh — native SwiftUI `.refreshable` on the scroll view, runs `loadData()`.

**`MoneyDashboardViewModel` Phase 3 additions** (`OPS/ViewModels/MoneyDashboardViewModel.swift`, all computed — no schema change):
- `StageForecast` — replaces the Phase 2 `(stage, value)` tuple for Card 4: `id` (PipelineStage), `value` (weighted dollars), `avgProbability` (unweighted mean win-probability — the `×62%` indicator), `count`. A `stage` computed alias keeps legacy call-sites compiling.
- Per-card error tracking — `BooksCard` enum (`pl`/`cashFlow`/`ar`/`forecast`/`jobs`), `failedCards: Set<BooksCard>`, `cardError(_:)`, `retry(_:)`. `loadData()` is fail-soft: each repository fetch is a `Result`; an invoice failure flags PL/Cash Flow/A/R/Jobs, expenses flags PL/Cash Flow/Jobs, opportunities flags Forecast, allocations flags Jobs.
- Sync state — `SyncState` (`syncing`/`synced`/`offline`/`error`) and `lastSyncedAt`. A `URLError` of `.notConnectedToInternet` / `.networkConnectionLost` / `.timedOut` downgrades to `.offline`; any other error to `.error`.
- `hasEverLoaded` — gates the skeleton path. Flips true on the first `loadData()` that runs to completion — including a load with per-card failures, so a transient first-launch error does not trap the user in skeleton.
- Worst-loser floor — `computeJobNets` builds a top-5-by-net display slice, then displaces the 5th entry with the period's worst loser when one exists below the `worstLossFloor` noise guard (−$500) and is not already shown. Aggregates (`profitableProjectCount` / `losersProjectCount` / `avgProjectMargin`) always count the full project set, not the display slice.

**Per-job profitability** (Card 5) — `MoneyDashboardViewModel.computeJobNets(periodStart:periodEnd:)`:
- Revenue = `sum(payments.amount)` for non-void invoices carrying a `project_id`, paid in-period.
- Cost = `sum(expense_project_allocations.amount)` (fallback `expense.amount × percentage / 100` when `amount` is null) for non-deleted in-period expenses.
- `expense_project_allocations.project_id` is `text` in Supabase while `invoices.project_id` is `uuid`; both arrive as `String` in Swift DTOs, so the join is string-on-string.

**Permission gating:**
- Tab visible (`MainTabView.hasBooksAccess`) with any of `finances.view` / `estimates.view` / `expenses.view`. `pipeline.view` does not gate BOOKS — it gates the separate Pipeline tab.
- Carousel cards filtered per-card (table above); the hero is hidden entirely when the user has neither `finances.view` nor `pipeline.view`.
- Segments filtered by `BooksSection.requiredPermission`: Invoices `finances.view`, Estimates `estimates.view`, Expenses `expenses.view`. Expenses renders `MyExpensesView` for own-scope users, `ExpensesListView` for full access.
- Role outcomes: an **Owner** sees all 5 cards and all 3 segments; an **Operator** (estimates + expenses, no finances/pipeline) gets no carousel and the Estimates/Expenses segments only; a **Crew** member (own-scope `expenses.view` only) is auto-skipped — `MainTabView.booksAutoSkipDestination` routes the BOOKS tab straight to `MyExpensesView` whenever exactly one segment is visible.

**Accessibility:**
- The carousel container is one VoiceOver element (`.contain` children, heading trait): "Books dashboard, N cards, swipe with two fingers to navigate" (N is permission-filtered).
- Each card folds its non-tile content into a single composed summary (e.g. "P and L. Net cash $X this 30D. Y% margin."); drill tiles, the period pill, the dots, the segmented control and the sync-banner RETRY each remain individually navigable with their own labels and hints.
- Dynamic Type — hero numbers clamp at `accessibility3` and scale down via `minimumScaleFactor(0.7)`; card-header and tile labels clamp at `accessibility2`.

**FAB integration:**
- The global `FloatingActionMenu` (`OPS/Views/Components/FloatingActionMenu.swift`) re-orders its MONEY group via `@AppStorage("books.selectedSegment")` so the create action for the active segment floats to the front. `add-lead` stays in the MONEY group — the FAB is global and the Pipeline tab split does not move the create action.

**Deferred / known gaps (as-built):**
- `BooksPTRIndicator` (OPS-mark + spin-arc + `SYNCING` label) is built but **not wired in** — it is a standalone view, not a `ProgressViewStyle`, so it cannot drive the system refresh control. Pull-to-refresh ships on native `.refreshable`; adopting the custom indicator is a future polish phase (spec § 7.5).
- Five of the eight carousel drill tiles (`DAYS`, `CLOSE RATE`, `STALE`, `PROFITABLE`, `LOSERS`) have deferred no-op handlers pending their full-screen report / Pipeline-tab drill targets.
- `CashflowForecastCard` is mounted **below** the carousel rather than as an in-carousel card; integrating it as a 6th card is future scope (see the Cashflow Forecast section below).

**History:** Phase 1's `MoneyDashboardHeader` / `SmartStatCarousel` / `FinancialHealthBar` / `PeriodToggle` were removed in the Phase 2 cleanup; the 2026-05-07 spec is superseded.

**Spec & plan:**
- Phase 3 Mission Deck visual rebuild: `ops-ios/docs/superpowers/specs/2026-05-19-books-tab-mission-deck-rebuild.md`.
- Phase 2 carousel architecture: `ops-ios/docs/superpowers/specs/2026-05-11-books-ui-reconstruction-design.md` + plan `2026-05-11-books-ui-reconstruction.md`.
- Phase 1 (superseded): `ops-ios/docs/superpowers/specs/2026-05-07-books-tab-design.md`.

---

## Home Billable This Week Rollup (2026-05-25)

**Status:** iOS Home implementation landed for `IOS BUG BACKLOG - P1-7`. This is a Home-level billing-context surface, separate from the BOOKS carousel. It answers: "what should I be invoicing this week?" without forcing the operator into Books or project detail.

**Surface:**
- `HomeBillableThisWeekRollupEngine` computes the model from local SwiftData `Project`, `ProjectTask`, `Invoice`, and `Estimate` rows.
- `HomeView` recomputes after the Home project load finishes, then renders `HomeBillableThisWeekCard` when the operator has `finances.view`.
- The card stays live all week and has two sections: `CLOSING` and `READY TO BILL`.
- Row tap priority: draft invoice detail when present, else estimate detail when present, else project detail.

**Week rules:**
- The week is Monday-start through Sunday-end, using the device calendar/time zone.
- `CLOSING` includes active projects whose remaining non-cancelled tasks all have `endDate` inside the current week.
- `READY TO BILL` includes projects whose non-cancelled tasks are all complete.
- Deleted projects/tasks are ignored. Archived and closed projects are ignored.
- A project with any posted invoice is excluded from both sections. Posted means any non-draft, non-void invoice. Draft invoices are allowed and are treated as billable work not yet posted.

**Amount priority:**
1. Newest draft invoice total.
2. Approved or converted estimate total.
3. Sent or viewed estimate total.
4. Draft estimate total.
5. No amount: show the project title and task count with `—` for the dollar value.

**Monday notification:**
- iOS dispatches one Monday notification per user/company/week when the rollup has items and the user has `finances.view`.
- Local notification + in-app rail type: `billable_this_week`.
- `deep_link_type = billableThisWeek`, `action_url = ops://home/billable-this-week?weekStart=YYYY-MM-DD`, `action_label = OPEN HOME`.
- The in-app rail route and local push tap both switch to Home so the operator lands on the same live rollup card.

---

## Cashflow Forecast (2026-05-11)

**Status:** Initiative `CASHFLOW FORECAST - P1` — design and additive Supabase schema landed 2026-05-11; iOS engine + UI in flight. Surfaced as a preview card mounted below the BOOKS hero carousel; integrating it as a 6th in-carousel card is future scope. Forward-looking complement to the retrospective Pipeline Forecast (Card 4).

**The question this card answers:** "Given the jobs I already have on the books — sent invoices, approved estimates, weighted pipeline — what does my cash position look like over the next 13 weeks?"

### Surface

- **Card preview** (`CashflowForecastCard`) — mounted below the BOOKS hero carousel. Shows end-of-horizon balance, sparkline of running balance, lowest projected point, state badge (`ON TRACK` / `WATCH` / `DIP DETECTED`).
- **Full screen** (`CashflowForecastScreen`) — opens on tap. 13-week running-balance line chart, layer toggles, 4w/13w horizon zoom, drill-into-week sheet.
- **Bottom sheet** (`WeekBreakdownSheet`) — tap any data point. Lists every contributing invoice / milestone / recurring expense / opportunity for that week, grouped by inflow/outflow. Each row deep-links to its source entity.
- **Settings sheet** (`ForecastSettingsSheet`) — gear icon on the full screen. CRUD on recurring expenses + low-water threshold + current-balance refresh.

### Algorithm (summary)

For each week `i ∈ [0, 13)`, compute weekly net = inflows − outflows; running balance starts at the manually-entered `forecast_current_balance`.

Inflows (toggleable layers):
- **Committed** — sent / partially-paid invoices projected onto (`invoices.due_date + company avgDaysToPayment`).
- **Contracted** — non-paid `payment_milestones` projected onto (`expected_date + avgDaysToPayment`); estimates without milestones lump on (project end + 30d + avgDaysToPayment).
- **Pipeline** — weighted opportunities: `estimated_value × win_probability ÷ 100`, projected onto (`expected_close_date + avgDaysToPayment`).

Outflows (toggleable layer):
- **Recurring** — `recurring_expenses` iterated via cadence (weekly / biweekly / monthly / quarterly / annually) within horizon, respecting `end_date`.

State determination:
- Any week balance < 0 → `.danger` (chart shifts to brick-red, persistent notification fires).
- Any week below `forecast_low_water_threshold` (default $5,000) → `.lowWater` (chart shifts to amber).
- Otherwise → `.healthy` (steel-blue).

`avgDaysToPayment` is the company-wide average already computed by `MoneyDashboardViewModel`. Per-client learning is a v2 follow-up.

### Schema deltas (additive — 2026-05-11 migration `add_cashflow_forecast_tables`)

| Change | Detail |
|--------|--------|
| New table `recurring_expenses` | Per-company recurring outflows. Columns: `id, company_id, name, amount, currency, cadence, next_due_date, end_date, category_id, notes, created_by, created_at, updated_at, deleted_at`. RLS via `private.get_user_company_id()`. |
| New table `forecast_alerts` | Per-company anti-spam ledger for the persistent dip notification. Columns: `company_id (PK), last_dip_notified_at, last_dip_min_balance, last_dip_min_week_start, last_cleared_at, dismissed_until_balance, updated_at`. RLS same pattern. |
| New column `payment_milestones.expected_date date NULL` | When each milestone is expected to invoice. Existing rows backfill to NULL; engine falls back to project-span derivation when null. |
| 3 new columns on `expense_settings` | `forecast_low_water_threshold numeric DEFAULT 5000`, `forecast_current_balance numeric NULL`, `forecast_balance_updated_at timestamptz NULL`. All nullable. |

All migrations are additive only — older iOS clients (prior App Store releases) continue to function unchanged.

### Persistent dip notification

When any week of the forecast projects below zero, `ForecastNotificationDispatcher` inserts a `notifications` row with:

- `type = 'forecast_dip'`
- `persistent = true`
- `title = '// CASH DIP PROJECTED'`
- `body = 'Balance drops to $X the week of MMM D.'`
- `action_url = '/books/cashflow'`
- `action_label = 'REVIEW FORECAST'`

Recipients lookup via `public.users_with_permission(company_id, 'finances.view')` — never filter by `users.role`. One notification row per recipient user; the anti-spam ledger is keyed by `company_id`.

**Anti-spam rules** (full taxonomy in `07_SPECIALIZED_FEATURES.md § 14.3.2`):
- First dip (no prior `last_dip_notified_at`, or `last_cleared_at > last_dip_notified_at`) → fire.
- Persisting dip → re-fire only if >24h since last AND new min balance ≥ 10% worse than `last_dip_min_balance`.
- Cleared (transition out of `.danger`) → fire one-shot non-persistent "DIP CLEARED" notification, set `last_cleared_at`, leave the persistent row in the rail until user dismisses.
- "Don't show again" sets `dismissed_until_balance = current_min`; suppresses re-fire while next min ≥ that × 0.9.

### What-if controls (v1)

- **Layer toggles** — 4 switches (Committed / Contracted / Pipeline / Recurring) re-run the projection live. Persisted per-user via `@AppStorage`.
- **Horizon zoom** — 4W / 13W toggle (both weekly buckets; daily granularity in 4W is a v2 deferral).
- **Low-water threshold** — configurable in settings sheet, drives the amber-warning trigger.

### Out of scope for v1 (explicit)

- Per-invoice late-payer override slider — v2.
- Per-client days-to-payment learning — v2.
- Auto-detection of recurring expenses from history — v2.
- Auto-creation of expense rows when a recurring entry hits its due date — v2.
- Outflow projection from labor cost / open POs / catalog allocations (iOS has no labor-cost or PO model today).
- OPS-Web cashflow forecast — tracked at `OPS-Web/docs/bugs/2026-05-11-cashflow-forecast-web-followup.md`. Web ships a placeholder route initially; full web build is a separate plan.

### Spec & plan

- Design spec: `docs/superpowers/specs/2026-05-11-cashflow-forecast-design.md`
- Implementation plan: `docs/superpowers/plans/2026-05-11-cashflow-forecast.md`

---

**Last Updated**: 2026-05-25
**Document Version**: 1.5
**Source**: ops-web git commits `0b268fd`, `2742b60`, `f5a01f1`, `81577c4`; iOS source `OPS/OPS/`; Supabase Edge Functions `accounting-oauth`, `accounting-sync-expense`, `accounting-batch-create`. Cashflow Forecast addition based on iOS branch `cashflow-forecast` + Supabase migration `add_cashflow_forecast_tables`.
