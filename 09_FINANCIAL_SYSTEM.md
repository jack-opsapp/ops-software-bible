# 09_FINANCIAL_SYSTEM.md

**OPS Software Bible - Pipeline, Estimates, Invoices & Financial Architecture**

**Purpose**: Complete documentation of the OPS financial system — pipeline/CRM, estimates, invoices, payments, products catalog, and accounting integrations. All financial data lives in **Supabase** (PostgreSQL), separate from operational data in Bubble.io.

**Last Updated**: July 19, 2026
**Source Reference**: `C:\OPS\ops-web\src\lib\types\pipeline.ts`, `src\lib\api\services\`, iOS source at `ops-ios/OPS/`

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

### LeadConversionService — Lead → Project Conversion (iOS, 2026-05-19; unified across platforms 2026-06-03)

`LeadConversionService` (`OPS/Services/LeadConversionService.swift`) orchestrates the conversion that lands when an operator marks a pipeline opportunity won — the canonical 'won' behavior documented in `10_JOB_LIFECYCLE_AND_DATA_RELATIONSHIPS.md` § `won`.

**Lineage** — the original iOS RPC `convert_lead_to_project` (migrations `2026-05-19-convert-lead-to-project-rpc.sql` + `2026-05-20-extend-convert-lead-to-project-site-visit-photos.sql`) and the web RPC `execute_opportunity_project_conversion_guarded` (lead-lifecycle P6) were two divergent paths. As of 2026-06-03 they are replaced by one shared brain (below); `convert_lead_to_project` survives only as a shim.

#### Unified conversion brain (2026-06-03, migration `20260603020000_won_conversion_dedup_naming`)

A single shared Postgres brain backs the conversion on **both** platforms — drift becomes impossible. Two functions:

**`get_conversion_preflight(p_opportunity_id uuid, p_company_id uuid DEFAULT NULL) RETURNS jsonb`** — read-only dedup detection, called before the convert UI commits. Auth: `service_role` trusts `p_company_id`, otherwise company is derived from the JWT and `pipeline.manage` is required. Returns:

```jsonc
{
  "existing_linked_project": { "id": "...", "title": "..." } | null,   // this opp already converted
  "duplicate_candidates": [                                             // likely the SAME job
    { "project_id","title","address","confidence": "high"|"medium","signals": ["same_client","same_address"] }
  ],
  "other_client_projects": [ { "project_id","title","address","status" } ],
  "suggested_name": "1240 W 6th Ave"                                    // derive_project_name preview (base, no #N)
}
```

Matching uses `private.normalize_address` (§03): same normalized address + same `client_id` ⇒ **high**; same address, different/unknown client ⇒ **medium**.

**`convert_opportunity_to_project(...) RETURNS jsonb`** — the unified write transaction (`SECURITY DEFINER`, all-or-nothing), a superset of both retired RPCs. Full signature:

```sql
convert_opportunity_to_project(
  p_company_id        uuid,
  p_opportunity_id    uuid,
  p_actual_value      numeric  DEFAULT NULL,
  p_expected_stage    text     DEFAULT NULL,   -- snapshot guard
  p_decided_by        uuid     DEFAULT NULL,
  p_notes             text     DEFAULT NULL,
  p_title_override    text     DEFAULT NULL,    -- non-null ⇒ hand-set name (title_is_auto=false)
  p_link_to_project_id uuid    DEFAULT NULL,    -- link an existing project instead of creating
  p_source_path       text     DEFAULT NULL,    -- 'won_dialog' | 'approval_queue' | 'ios'
  p_win_opportunity   boolean  DEFAULT true,
  p_project_status    text     DEFAULT NULL,    -- null → 'accepted' if winning else 'rfq'
  p_evidence          jsonb    DEFAULT '{}'
) RETURNS jsonb
-- → { converted, already_converted, project_id, disposition_id, relinked_estimates,
--     materialized_tasks, attached_photos, linked_existing, won, guard_reason? }
```

**The shim (migration `20260603020001`).** `convert_lead_to_project(p_opportunity_id, p_actual_value, p_title, p_address, p_user_id) RETURNS uuid` is rewritten as a thin wrapper that calls `convert_opportunity_to_project(p_title_override := p_title, p_source_path := 'ios', p_win_opportunity := true)` and returns `(result->>'project_id')::uuid`, preserving the original return type + error codes. **The App-Store iOS build in the field converges on the unified logic with no release.** `p_address` is accepted for signature compatibility but **ignored** — the unified RPC reads `address`/`latitude`/`longitude` from the opportunity row (the next iOS release persists an edited address to the opportunity before converting).

**Web parity.** `OPS-Web` `ProjectConversionService` (`src/lib/api/services/project-conversion-service.ts`) now calls `convert_opportunity_to_project` directly through a service-role route (`POST /api/opportunities/[id]/convert`) plus `getConversionPreflight` (`GET …/preflight`); the Won dialog wins **and** converts in one atomic call (no separate `moveStage(won)`). The legacy `execute_opportunity_project_conversion_guarded` is superseded and was **`DROP`ped 2026-06-04** (migration `20260604212206_drop_guarded_conversion_rpc.sql`) after the unified path was deployed and proven in production — verified beforehand as 0 DB dependents + 0 code callers (the TS caller switched in Phase 2). `src/lib/types/database.types.ts` was regenerated to remove the stale type, and `ProjectConversionService` now uses literal RPC-name consts (the typed `rpc` overload).

#### Conversion transaction (what `convert_opportunity_to_project` does)

`SECURITY DEFINER`, one transaction:

1. **Auth** — `service_role` trusts `p_company_id`; else company from the JWT must match and `private.current_user_has_permission('pipeline.manage','all')` holds. (Never `auth.uid()` — the OPS JWT `sub` is a non-UUID Firebase UID; identity is resolved via `private.get_user_company_id()`.)
2. **Lock** the opportunity `FOR UPDATE`; not-found/soft-deleted ⇒ error. **Idempotency**: `project_ref` already set ⇒ `{converted:false, already_converted:true, project_id}`. **Snapshot guard**: `p_expected_stage` mismatch ⇒ `{converted:false, guard_reason:'snapshot_mismatch'}`, nothing written.
3. **Status** = `COALESCE(p_project_status, p_win_opportunity ? 'accepted' : 'rfq')`.
4. **Link-existing** (`p_link_to_project_id`): validate the target is a non-deleted in-scope project `FOR UPDATE`, use it, and do **not** touch its status/title. **Create** (default): insert `projects` with `title_is_auto = (p_title_override IS NULL)`, `title = COALESCE(p_title_override, 'New project')` (the `projects_autoname_biud` trigger overwrites the title when auto — see §03), `address` **+ `latitude`/`longitude`** (fixes the dropped geocode), `client_id`, `opportunity_id` (text) + `opportunity_ref` (uuid), `status`, `estimated_value`, `notes`, `created_by` (**stored only when `p_decided_by` is a genuine `auth.users` id, else `NULL`** — `projects.created_by` FKs `auth.users(id)`, but OPS operators authenticate via Firebase and are absent from `auth.users`. An earlier build inserted the `public.users` operator id directly, violating `projects_created_by_fkey` and rolling back **every** web win ("Deal won, but the project could not be created"); fixed in `20260604205950_fix_convert_created_by_fkey.sql`. Operator attribution is preserved on the disposition `decided_by` + `stage_transitions.transitioned_by`, neither of which FKs `auth.users`).
5. **Four-column link contract** on the opportunity (`project_ref` + `project_id`, guarded `WHERE project_ref IS NULL` against a concurrent win).
6. **Relink estimates** — `project_ref` (uuid) **and** `project_id` (text mirror); the web Estimates tab keys off the text column.
7. **Materialize** LABOR line items → `project_tasks`, **deduped by `source_line_item_id`** (correct for both create and link-existing).
8. **Attach** non-deleted site-visit `photos[]` → `project_photos` (`source='site_visit'`, `site_visit_id` back-link, `uploaded_by = sv.created_by`, `is_client_visible=false`), **deduped by `(site_visit_id, url)`**.
9. **Attach lead photos** (added 2026-07-14, migration `convert_rpc_lead_deck_and_photo_carryover`) — the lead's own `opportunities.images[]` → `project_photos` (`source='other'`, no `site_visit_id`, `uploaded_by = COALESCE(p_decided_by::text,'')`), **deduped by URL** against anything already copied, so a photo that arrived via a site visit is never duplicated.
10. **Re-parent lead deck designs** (same migration) — `deck_designs SET project_id = <project> WHERE opportunity_id = <opp> AND project_id IS NULL AND deleted_at IS NULL`. Only unparented decks move (a deck already attached to some project is never stolen); `opportunity_id` is KEPT as provenance so the lead still shows its deck after WON.
11. **Win** (only when `p_win_opportunity`) — always set `actual_value`; **only if `stage <> 'won'`** set `stage='won'`, `stage_entered_at`, `stage_manually_set`, `actual_close_date` and insert ONE `stage_transitions` row. An already-won opp (estimate-approval path) writes **no** second transition. `p_win_opportunity=false` (approval queue) ⇒ stage untouched, status `rfq`.
12. **Disposition** — supersede prior active dispositions; insert `'converted_to_project'` with evidence (`source_path`, `actual_value`, `relinked_estimates`, `linked_existing`, `won`).

The RPC's jsonb result carries `relinked_estimates`, `materialized_tasks`, `attached_photos`, and (2026-07-14, additive) `attached_lead_photos` + `relinked_decks`.

**Why `p_win_opportunity` / `p_project_status` exist** — the approval-queue path creates a project at `rfq` **without** winning the opp, and the estimate-approval path wins an opp **without** converting (so the convert RPC is routinely called on an already-won opp). Hard-coding `stage='won'` would wrongly force-win approval-queue projects and double-write `stage_transitions`; these params plus the idempotent stage logic in step 11 prevent both. Defaults: `won_dialog`/`ios` ⇒ win=true, `accepted`; `approval_queue` ⇒ win=false, `rfq`.

**Authorization & errors** — `SECURITY DEFINER`; `GRANT EXECUTE … TO authenticated, service_role`. Raises `opportunity_not_found` (SQLSTATE `P0002`) and `access_denied` (SQLSTATE `42501`); the shim preserves both.

#### iOS service surface

| Method | Purpose |
|---|---|
| `getConversionPreflight(for:)` | Server preflight (next iOS release) — replaces the old local-SwiftData `existingProject` / `clientProjectsSummary` dedup, which missed unsynced projects (new device, partial sync, another operator's just-created project). |
| `convertOpportunityToProject(lead:actualValue:titleOverride:notes:userId:)` | Calls `convert_opportunity_to_project` directly (`p_source_path='ios'`); `titleOverride = nil` ⇒ auto-named (`title_is_auto=true`), a typed name ⇒ hand-set. |
| `estimates(for:)` / `estimateBundles(for:)` | Network fetch for the estimates list + the LABOR tasks preview. |
| `markWonNoProject(lead:actualValue:userId:)` | **iOS-only** escape hatch — win without a project (sheet CANCEL exit). Web does **not** mirror it. |
| `markWonWithExistingProject(lead:projectId:actualValue:userId:)` | **iOS-only** — mark won while keeping an existing linked project (the DUPLICATE-EXISTS "open project" action). Web does **not** mirror it. |

The previous App-Store release's `convert_lead_to_project(... p_address ...)` call keeps working via the shim. The next iOS release adopts `get_conversion_preflight` + `convert_opportunity_to_project` directly and sets `title_is_auto`. Task Generation modal (per-task toggle pre-materialization) remains deferred — v1 materializes every LABOR line item silently.

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
-- Returns "PREFIX-YEAR-NNNNN": "EST-2026-00001", ... or "INV-2026-00001", ...
-- (v_prefix || '-' || v_year || '-' || LPAD(v_next::text, 5, '0');
--  sequence resets per fiscal_year — 001_pipeline_schema.sql:682)
```

This ensures sequential, race-condition-free numbering per company and fiscal year.

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

### Payment Review Closeout Contract (2026-07-21)

The iOS Payment Review sheet is an authoritative closeout surface, not a local status shortcut. `close_project_from_payment_review` closes a completed project only after deriving the current actor/company, checking project edit plus full invoice/financial view, locking the relevant records, and proving that no positive unresolved invoice balance remains. The closed-project invoice guard rejects any later invoice mutation that would leave positive debt on a closed project.

`write_off_project_from_payment_review` additionally requires full `invoices.edit` and atomically writes eligible OPS-owned outstanding invoices to `written_off`, zeros those balances, and closes the project. Positive QuickBooks/Sage-linked balances are provider-owned and always rejected for accounting-side resolution; a local write-off may not hide upstream debt. The UUID request key is persisted in `payment_review_writeoff_receipts`, so lost responses and concurrent same-key retries replay the original invoice count/balance instead of applying again.

The up-swipe queues an approval-first `send_payment_reminder` action through `POST /api/review/payment/reminder`; it does not send immediately or report delivery. Eligibility and copy snapshot the current company timezone, locale, currency, reminder settings/tier, company mailbox, client email, invoice status, balance, due date, and version. A service-only generation claim prevents duplicate paid drafting. Immediately before provider I/O, `claim_approved_action_email_delivery` revalidates the exact snapshot and refuses a reminder that became paid, void, written off, rescheduled, partially paid, disabled, reassigned, or otherwise stale.

Sources: `04_API_AND_INTEGRATION.md` § Review Swipe Mutation APIs; migrations `20260721120000_payment_review_atomic_actions.sql`, `20260721122000_payment_reminder_delivery_guards.sql`, and `20260721123000_payment_review_receipt_fk_indexes.sql`.

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

Full expense submission, receipt OCR scanning, batch approval workflow, payout tracking, and accounting sync system. All roles can submit expenses; office/admin approve field crew submissions. On OPS-Web, expenses live in **Books → EXPENSES segment** (`/books?segment=expenses` — the batch review console, 2026-07-10); on iOS the owner-side surface is the **batch console** (`ExpensesListView`, 2026-07-11 — reached from Books → EXPENSES ledger marker `BATCHES` link, Settings, or as the Books tab root for single-segment users) plus the crew-side `MyExpensesView`.

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

- **Single Add, one transaction (hardened 2026-07-19).** `ExpenseFormSheet` has one **ADD** action. The current iOS client uploads any new receipt first, then sends the complete intended expense snapshot to `save_expense_atomic`: create/update, allocation replacement, submit/refile placement, and both affected envelope totals either commit together or do not commit. The command carries a stable request ID plus the row's expected status and `updated_at`; exact retries are idempotent, while a genuinely stale form is rejected instead of overwriting newer work. No client `get_or_create_open_batch`, `ExpenseBatchPeriod` placement, under-threshold auto-approve, batch-clear sequence, or per-submit notification remains in this path. Editing a pending line keeps it `submitted` and the RPC re-files it so the envelope total stays live; a rejected line re-files into the current open envelope on resubmit. Already-shipped clients remain compatible with the additive RPC and existing table APIs.
- **Snap-a-stack drafts.** The multi-receipt scan queue still saves `draft`s (SAVE & NEXT); `MyExpensesView` shows a quiet "finish your receipt" nudge for unfinished drafts. The bulk SUBMIT button, selection sheet, and swipe-to-submit were removed.
- **State display.** `ExpenseCard` shows the line's state + envelope phase quietly ("filling" / "with the office" / "approved" / "paid" / "needs fix"); `MyExpensesView` shows a low-key running total for the current filling envelope.
- **Review hub** *(superseded 2026-07-11 by the iOS batch console below — the period-pill / NEEDS REVIEW / HISTORY layout is gone)*.
- **Realtime.** `RealtimeProcessor` subscribes `expense_batches` (plus the existing `expenses`); both were added to the `supabase_realtime` publication with `REPLICA IDENTITY FULL` (they were not published before — the `expenses` subscription had been silently dead). The processor posts `.expenseUpdated`; as of 2026-07-11 the batch console subscribes to it (debounced reload) — before that, nothing listened and the hub was not actually live.

### iOS Batch Console (2026-07-11)

`ExpensesListView` was rebuilt as the phone-native counterpart of the OPS-Web expense console — same lifecycle vocabulary and server contract, phone-first presentation (not a port). Files: `OPS/Views/Expenses/ExpensesListView.swift` (stateful wrapper) + `OPS/Views/Expenses/Console/` (`ExpenseInstrumentStrip`, `ExpenseBucketQueue`, `ExpenseBulkCTABar`) + `OPS/DataModels/Helpers/ExpenseBuckets.swift` (pure derivation, unit-tested in `OPSTests/ExpenseBucketsTests.swift`).

- **Instrument tiles ARE the bucket switcher.** A spend hero card (`// SPEND · THIS MONTH` + MoM trend where up = cost-negative rose, jobs/overhead split, 6-month micro bars) sits over three money tiles — TO REVIEW ($ + batch count, tan when nonzero) / TO PAY ($ owed + people) / PAID ($ this month). The tiles are simultaneously the macro metrics and the segmented control for the queue below; the console lands on the first bucket with work. Metrics derive from the same two fetches the queue renders (`ExpenseBuckets.computeMetrics` — port of web `expense-metrics.ts`), so strip and queue can never disagree.
- **Buckets** (`ExpenseBuckets.bucket(for:lineCount:)` — exact `expense-buckets.ts` parity incl. the drained-returned-batch rule and unknown-status → crew). TO REVIEW groups by person, oldest outstanding period leads, batches oldest-first; TO PAY groups by person, largest owed first (`owedAmount` — approved_amount authoritative only for `partially_approved`, else positive-else-total fallback); PAID is month-sectioned by payout date, newest first; WITH CREW renders as a quiet expandable footer under every bucket (filling envelopes with `AUTO-SENDS <date>` foresight from `expense_settings.auto_submit_grace_days`, per-job envelopes say "sends after the job wraps"; returned batches show `SENT BACK · n LEFT` and disappear when drained).
- **Actions.** Swipe (leading, olive) = APPROVE on clean review rows / PAID on pay rows; per-person `APPROVE n` / `PAY n` compact buttons and the floating `APPROVE ALL · $X` / `PAY ALL · $Y` CTA confirm via dialog — **flagged batches are always excluded from bulk approval** and the dialog says so. Non-approvers (full-access `expenses.view` without `expenses.approve`) get a read-only console.
- **Atomic approval.** iOS whole-envelope approval now calls the `approve_expense_batch` RPC (the Phase-2a direct-write path is gone), followed by best-effort `accounting-sync-expense` per approved line — full web parity. Per-line early clear (`early_clear_expense_line`) is a quiet `CLEAR NOW` in a filling envelope's line detail.
- **Paid-out lifecycle.** Batch detail is bucket-aware: review batches keep the flag-driven APPROVE ALL / SEND BACK n footer (send-back = the amendment flow, recopied from "revisions"); TO PAY batches get `MARK PAID · $owed` (`mark_expense_batch_paid`); PAID batches show `PAID <date> · <name>` + an UNDO ghost (`unmark_expense_batch_paid`), and the mark-paid toast carries UNDO (mis-tap recovery, web parity). Header stats lead with the number that matters per bucket (OWED / PAID / SO FAR / TOTAL).
- **Notifications.** iOS dispatches submitter notifications in batch vocabulary: `expense_approved` ("Expenses Approved"), `expense_rejected` ("Expenses Sent Back"), `expense_paid` ("Expenses Paid Out" — exact web copy) — the legacy `invoice_approved` / `invoice_revisions` types are no longer dispatched (existing rows still route). The rail renders `expense_paid` first-class (banknote icon, VIEW EXPENSES, batch-aware routing); `AppDelegate` routes both the web's `expensePaid` pushData type and the iOS `expense_paid` twin. The approver-side local "immediate feedback" notification was dropped (the toast is the approver feedback).
- **Books entry.** The EXPENSES ledger-marker link is state-aware: `BATCHES · n TO REVIEW` (tan) → `BATCHES · n TO PAY` → `BATCHES`. Deep links (`BooksOpenBatchReview` / batch-scoped pushes) still auto-open the batch's detail inside the console.
- **Snapshot proof:** `OPSTests/Views/ExpenseConsoleSnapshotTests.swift` renders every console + detail state to PNGs (artifacts under `ops-ios/docs/artifacts/expense-console/`).

### OPS-Web Expense Console + Paid-Out Lifecycle (2026-07-10)

The Books EXPENSES segment (`ops-web/src/components/books/segments/expenses-segment.tsx`) is the batch review console — it replaced the period-pill / review-history split (`expense-review-dashboard.tsx`, `invoice-card.tsx`, `invoice-detail-panel.tsx`, `expense-line-item-table.tsx`, `expense-filters.tsx` all deleted). User-facing noun is **batch** ("invoice" was retired on this surface — it collided with A/R invoices one segment over).

**Lifecycle buckets** (`ops-web/src/lib/utils/expense-buckets.ts` — every batch lands in exactly one; workbar chips + URL `&view=`):

| Bucket | Contents | Actions |
|---|---|---|
| TO REVIEW | `pending_review` + legacy `submitted`, **cross-period** (the old month pills hid prior-month pending batches), grouped by person (oldest outstanding period leads; batches oldest-first) | hover APPROVE (clean rows), APPROVE n per person, APPROVE ALL workbar CTA (flagged batches always excluded from bulk runs), detail APPROVE ALL / flag-driven REJECT |
| TO PAY | `approved` / `partially_approved` / `auto_approved` with `paid_at IS NULL`, grouped by person (largest owed first) | hover MARK PAID, PAY n per person, PAY ALL CTA, detail MARK PAID |
| PAID | `paid_at IS NOT NULL` — month subheaders by payout date, newest first | UNDO PAID (detail footer + toast action) |
| WITH CREW | `open` (filling; shows the sweep's auto-send date = `period_end + auto_submit_grace_days`) + `rejected` batches still holding ≥1 line (a drained returned batch disappears as the crew re-files its lines) | none — read-only + per-line early CLEAR |

**Owed amount rule** (`batchOwedAmount`): `approved_amount` is authoritative only for `partially_approved` (the reject flow writes clean-total there). `approve_expense_batch` never writes it, so a zero/absent figure on a full approval means the whole envelope — fall back to `total_amount`.

**Instrument row** (`expense-instrument-row.tsx`, shared `MetricsStrip`, stacked under the LedgerStrip in the scroll-away metrics tier): SPEND · THIS MONTH (6-mo sparkline, MoM trend where up=cost-negative, jobs/overhead split from allocations) · TO REVIEW ($, tan) · TO PAY ($ owed) · PAID · THIS MONTH ($, olive). Computed by `expense-metrics.ts` from the same two queries the list renders (`useExpenseBatches` + `useAllExpenses`) so the strip and queue can never disagree. Unit-tested: `tests/unit/expenses/`.

**Web client parity with the DB contract** (previously trapped on the inbox branch): `useApproveBatch` now calls the atomic `approve_expense_batch` RPC + best-effort `accounting-sync-expense` per line (replacing the two direct writes on main); `useEarlyClearLine` added. `useExpenseRealtime` subscribes `expense_batches` + `expenses` postgres_changes and invalidates the query namespace — the console is live-wired.

**Paid-out flow**: MARK PAID → `mark_expense_batch_paid` RPC (stamps `paid_at`/`paid_by`, lines `approved → reimbursed`) → client dispatches `expense_paid` to the submitter → toast carries an UNDO action (`unmark_expense_batch_paid` reverses everything). iOS renders `reimbursed` lines as "paid" natively — the feature shipped with zero iOS changes and holds the cross-release sync constraint (nullable columns only, no new status values on `expense_batches.status`). *(2026-07-11: iOS now has the full first-class flow — see § iOS Batch Console.)*

**Deep link**: `/books?segment=expenses&batch=<id>` selects the batch and switches to its home bucket (consumed once). Stored `expense_submitted` action_urls (`/accounting?tab=expenses&batch=…`) keep resolving through the middleware's param-preserving 308.

### Receipt OCR (Apple Vision)

On-device OCR using Apple's Vision framework (`VNRecognizeTextRequest` with `.accurate` recognition level). No external vendor dependency.

**Extracted fields**: merchant name, date, total, subtotal, tax amount, payment method (cash/card detection), raw text.

**Architecture**: Protocol-based (`ExpenseOCRServiceProtocol`) for future swappability (e.g., Veryfi integration).

### Multi-Project Expense Splitting

Expenses can be attributed to zero or more projects via `expense_project_allocations`:
- Each allocation has an `expense_id`, `project_id`, and `percentage` (0-100)
- Percentages must sum to 100% if any allocations exist. The form validates this for immediate feedback, and `save_expense_atomic` independently enforces unique projects, positive percentages with at most two decimal places, and a 100% total.
- Project assignment is optional (company-configurable via `require_project_assignment`)
- **`per_job` companies allow exactly one allocation per expense** — the form blocks the "ADD PROJECT" button after the first project is selected, since per-job batches are project-scoped

### Currency Handling

`expenses.currency` (text, default `'USD'`) stores the ISO 4217 code. The form's currency picker defaults from `Locale.current.currency?.identifier` (locale-aware) and is overridable per-expense. Canadian crews logging CAD receipts in a USD-default world were silently mis-recording before 2026-05-08 — this fix surfaces currency in the form and persists it through the current full-snapshot `ExpenseAtomicSaveCommand`. `CreateExpenseDTO` / `UpdateExpenseDTO` remain legacy direct-table compatibility paths.

### Supabase Tables (6)

| Table | Purpose |
|---|---|
| `expenses` | Core expense records (amount, merchant, status, receipt URL, OCR data, **currency**) |
| `expense_project_allocations` | Many-to-many linking expenses to projects with percentage split |
| `expense_categories` | Company-configurable categories with icons (9 defaults seeded) |
| `expense_settings` | Per-company settings (review frequency, thresholds, policy toggles) |
| `expense_batches` | Per-person/per-period **envelopes**. `status`: `open` (filling) → `pending_review` (sent) → `approved` / `auto_approved` (done; auto-approved live in History). **`paid_at` / `paid_by` (nullable, 2026-07-10)** record the payout stage after approval — `paid_at IS NULL` on an approved envelope = money still owed to the submitter (`migrations/20260710180000_expense_batch_paid.sql`). **`scope_project_id` (nullable uuid)** identifies per-job envelopes; NULL for period envelopes. One active (`open`/`pending_review`) envelope per scope via `expense_batches_open_unique` |
| `accounting_category_mappings` | Maps OPS categories to external chart of accounts (QB/Sage) |

`private.expense_save_requests` is an implementation ledger, not a seventh public financial table. It retains only request/company/user/expense identifiers, a SHA-256 command hash, and timestamps; receipt URLs, OCR text, notes, and monetary content are never copied into it. Completed entries older than the 90-day idempotency window are pruned opportunistically for that company on a later save, not by a guaranteed TTL job.

### Supabase Functions (expense-related)

| Function | Purpose |
|---|---|
| `public.users_with_permission(p_company_id, p_permission, p_required_scope)` | Returns user IDs in a company holding a permission. Honors role grants, per-user overrides, and the `is_company_admin`/`account_holder_id`/`admin_ids` escape hatches. **Use for all recipient lookups — never filter by `users.role`.** |
| `public.get_or_create_open_batch(p_company_id, p_submitted_by, p_period_start, p_period_end, p_scope_project_id)` | Returns the user's not-yet-approved envelope for the scope (matching `open` **or** `pending_review`) or creates one as **`open`** (race-safe via `expense_batches_open_unique` + on-conflict re-select). `migrations/20260601210601_get_or_create_open_batch_v2.sql`. |
| `public.expense_envelope_period(p_expense_date date, p_review_frequency text)` | Returns `(period_start, period_end)` for an expense given its date + cadence — SQL port of `ExpenseBatchPeriod.swift` (Postgres week starts Monday). `migrations/20260601210428_expense_envelope_period_fn.sql`. |
| `public.place_expense(p_expense_id uuid)` *(service_role)* | Files one non-draft, unbatched expense into its envelope by date; rolls forward if the home period is approved. Invoked by the `trg_place_expense` trigger. `migrations/20260601210846_place_expense_trigger.sql`. |
| `public.expense_envelope_sweep()` *(service_role)* | Daily pg_cron `expense_envelope_sweep_daily` (15:15 UTC): auto-sends due `open` envelopes (one `expense_submitted` notification each), sweeps in completed drafts, adopts orphans (safety net), rolls stragglers forward. `migrations/20260601213757_expense_envelope_sweep_deep_link_expense.sql`. |
| `public.recalculate_expense_batch_total(p_batch_id)` | Locks the target envelope before reading its lines, then recomputes and persists `expense_batches.total_amount` from non-deleted attached expenses. Same-company authorization preserves shipped iOS callers while blocking cross-tenant SECURITY DEFINER access; trusted `service_role` and the no-JWT `postgres` pg_cron sweep remain supported. Hardened in `migrations/20260720004500_expense_atomic_save.sql`; live-body alias correction in `migrations/20260720005500_fix_expense_batch_recalculation_alias.sql`. |
| `public.save_expense_atomic(p_command jsonb)` | Authenticated, submitter-owned create/edit RPC for the current iOS client. Validates a strict full-snapshot command, company policy, category/project ownership, money/date precision, and `per_job` allocation rules; compare-and-swaps `expected_status` + `expected_updated_at`; atomically replaces allocations, submits/refiles, and recalculates source/destination envelopes. A private SHA-256 request ledger gives same-command retries a 90-day idempotency window, with opportunistic per-company pruning, without duplicating receipt/OCR data. `migrations/20260720004500_expense_atomic_save.sql`; verified live with the alias correction above via rollback-wrapped create/replay/edit/submit/tenant-denial scenarios. |
| `public.has_permission(p_user_id, p_permission, p_required_scope)` | Single-user permission check. Note: does NOT currently apply `user_permission_overrides` — only `user_roles → role_permissions` plus the admin escape hatches. iOS `PermissionService.fetchPermissions` applies overrides client-side. (Latent inconsistency — flagged for follow-up.) |
| `public.get_next_expense_batch_number(p_company_id)` | Returns next sequential batch number, format `EXP-BATCH-NNNN`. |
| `public.approve_expense_batch(p_batch_id uuid)` | Atomic whole-envelope approve — permission-checked (`expenses.approve` via `has_permission`), sets the batch + its non-rejected lines `approved` + recalc in one txn. **Both clients call this** (OPS-Web 2026-07-10, iOS 2026-07-11) — the two-direct-write path is retired. `migrations/20260602042258_expense_approval_rpcs.sql`. |
| `public.early_clear_expense_line(p_expense_id uuid)` | Early-clear — permission-checked; approves a single line, leaves the envelope `open`, recalcs, notifies the submitter (`expense_approved`). `migrations/20260602042258_expense_approval_rpcs.sql`. |
| `public.mark_expense_batch_paid(p_batch_id uuid)` | Records a payout — permission-checked (`expenses.approve`); requires status ∈ (`approved`,`partially_approved`,`auto_approved`) and `paid_at IS NULL`; stamps `paid_at`/`paid_by` and flips the envelope's `approved` lines to **`reimbursed`** (shipped iOS already renders that as "paid" — zero iOS changes). OPS-Web dispatches the `expense_paid` notification client-side after success. `migrations/20260710180000_expense_batch_paid.sql`. |
| `public.unmark_expense_batch_paid(p_batch_id uuid)` | Payout undo (mis-click recovery) — permission-checked; clears `paid_at`/`paid_by` and returns the envelope's `reimbursed` lines to `approved`. Same migration. |

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

Located at `src/lib/api/services/accounting-service.ts`. Stores OAuth connections for QuickBooks and Sage. Expense push runs via Supabase Edge Functions (below); the QuickBooks import, webhook apply, and full-CRUD queue run in `ops-web` (see *QuickBooks Sync*).

**Additional columns (2026-06, not in the legacy interface above):** `provider_environment text NOT NULL DEFAULT 'production'` (CHECK ∈ {`production`, `sandbox`}) lets one company hold separate QuickBooks production and sandbox rows; uniqueness is `(company_id, provider, provider_environment)`. `sync_direction text NOT NULL DEFAULT 'pull_only'` (CHECK ∈ {`pull_only`, `push_only`, `bidirectional`}) governs which half of the sync engine may run — a `pull_only` connection can never push to the provider; `realm_id_lookup text` (SHA-256 hex of the realm id) is the deterministic routing column for inbound webhooks, since `realm_id` itself is encrypted. **Token security:** `access_token` / `refresh_token` / `realm_id` are AES-256-GCM encrypted at rest (`token-cipher.ts`, key env `QB_TOKEN_ENC_KEY`, fail-closed); decryption is centralized in `AccountingTokenService.getValidToken`, which refreshes with the credential bundle matching the connection's `provider_environment`. The web client reads this table as the anon role, so an anon company-scoped `SELECT` policy gated on `accounting.view` exists alongside the `service_role` write policy (migration `20260603010000_accounting_connections_read_policy.sql`, bug `eb70d803`).

### QuickBooks Sync — import, webhook, and full CRUD queue (2026-06-04; hardened 2026-06-08)

The QuickBooks system includes a read-only Pull → Stage → Review → Apply draw, an inbound webhook apply path, and a full-CRUD outbound queue. Import/webhook fetches issue **zero** writes to Intuit; OPS-originated creates/updates/voids/inactivations only leave through `accounting_sync_queue` when `ACCOUNTING_WRITE_ENABLED=true`, the selected QuickBooks row is connected, `sync_enabled=true`, and `sync_direction <> 'pull_only'`. Full engineering reference (services, routes, apply order, schema, token security, webhook, queue, review UI): **`04_API_AND_INTEGRATION.md § QuickBooks Sync — Pull Import, Webhook Apply, and Queue-Owned Full CRUD`**.

Financial-data view:

- **Customer mapping** — a QB customer with a `CompanyName` becomes a parent `clients` row (named the company) **plus** a `sub_clients` contact (the person), idempotent on `sub_clients.qb_id`; individuals stay flat. Invoices/payments attach to the **parent client** only. QB Jobs/sub-customers are recorded but not converted to projects this phase. (bug `d6951b82`.)
- **What lights up in iOS Books** — **P&L** (`payments in`, 24-mo window), **Cash Flow** (weekly net from imported payments), **A/R aging** (open invoices, balances reconciled to QB's authoritative `Balance` in apply STEP 5). The per-job profit (Jobs) card does **not** populate — QB invoices carry no OPS `project_id` (the boundary that motivates Sub-project B).
- **Apply correctness** — payments insert before the final invoice reconcile so `trg_payment_balance → update_invoice_balance()` and the QB-authoritative `Balance` reconcile agree; voided/zero-total QB invoices are skipped, never imported as live A/R.
- **Stable identity and replay safety** — QBO import/webhook writes no longer use PostgREST live-table upsert for `clients`, `sub_clients`, `estimates`, `invoices`, or `payments`; insert conflicts reselect the existing row and update non-identity columns only, so duplicate webhooks/import retries cannot mutate primary keys under child rows. QBO line replacement runs through service-role-only `replace_qbo_line_items_locked`, which takes a transaction-scoped advisory lock and parent `FOR UPDATE` before delete/reinsert.
- **Outbound safety** — legacy manual sync/cron cannot push QuickBooks writes; Full CRUD writes are queue-owned, environment/connection-scoped, and terminally marked `needs_review` rather than retried when provider write succeeds but local finalization fails. Contact (`sub_clients`) changes queue against the parent customer, not the contact row id; sub-client tombstones update the QBO customer rather than inactivating it. Only one QuickBooks environment can be writable for a company at a time. Queue stale-claim and retry duplicate checks are connection-scoped, so sandbox and production rows cannot cancel each other. OPS estimate soft-delete maps to QBO Estimate delete; invoice/payment tombstones map to supported QBO void operations.
- **Inbound payment safety** — linked QBO payments are canonicalized as `paymentQbId:invoiceQbId` in OPS, while outbound void/update calls parse the raw payment id before calling QBO and then refresh the local composite key. Delayed inbound payment webhooks update a legacy raw payment row instead of inserting a duplicate. QuickBooks Payment `Void` webhooks mark matching OPS payments `voided_at`; Payment `Update` also voids stale composite rows that disappeared from QBO's latest split and reconciles affected invoices to QBO `Balance`, so QBO-side payment edits/reversals do not leave OPS A/R overstated.

### Edge Functions (3)

All deployed to Supabase, invoked via `SUPABASE_URL/functions/v1/<function-name>`. All use `verify_jwt: false` with manual auth header validation internally.

#### `accounting-oauth`

Handles OAuth flows for QuickBooks and Sage.

**Actions** (via `action` field in JSON body):
- `authorize` — Returns OAuth redirect URL for the provider
- `callback` — Exchanges authorization code for tokens, upserts `accounting_connections`
- `refresh` — Refreshes expired access token using refresh token
- `disconnect` — Clears tokens, sets `is_connected = false`; QuickBooks web OAuth initiate and disconnect are authenticated, permission-gated, and scoped to the selected `provider_environment` (`production` or `sandbox`)

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
   - **Uploader-only edit + submitter-or-admin delete (2026-06-09, DB-enforced).** An expense's **content** may be edited only by its **submitter** — a teammate's line opens **VIEW ONLY** even for Owner/Admin/Office, who review via approve/reject rather than editing it. **Soft-delete** (setting `deleted_at`) is allowed for the **submitter or a company admin** (`is_company_admin` / account holder / `admin_ids`). Each expense also shows an **"ADDED BY {NAME}"** attribution line (iOS form + project expense card). Enforcement layers:
     - **Database (authoritative):** `private.enforce_expense_edit_authority()` — a `BEFORE UPDATE` trigger on `public.expenses` (migrations `enforce_expense_uploader_only_edit` + `_backend_exempt`, 2026-06-09). It raises `42501` when any **content column** (`merchant_name, description, amount, tax_amount, currency, expense_date, payment_method, category_id, receipt_image_url, receipt_thumbnail_url, ocr_raw_data, ocr_confidence`) changes and `get_current_user_id() <> submitted_by`, or when `deleted_at` is set by a non-(submitter|admin). It is **additive over** the existing `role_scope_update` policy — status transitions, `approved_by`/`rejected_by`/`flagged_*`, `batch_id`, and accounting-sync columns are untouched, so **approve/reject/flag/submit and the placement pipeline (`place_expense`, sweep, approval RPCs) are unaffected**. Trusted backend/cron contexts (no `request.jwt.claims`) are exempted; anon requests never reach the trigger (RLS `company_isolation` blocks them first). Verified 2026-06-09 via 8 rollback-wrapped scenarios (submitter edits own ✓, admin/Office edit another's content ✗, admin approves ✓, submitter/admin delete ✓, Office/Operator delete another's ✗).
     - **iOS:** `ExpenseFormSheet` gates EDIT to the submitter; `ExpenseCard` swipe-to-delete is shown only to submitter-or-admin (`ProjectDetailsViewModel.canDeleteExpense`).
     - **OPS-Web:** no change required — the web app is **approval-only** for expenses (`expense-approval-service.ts` writes only status/flag/approval columns); it never edits expense content or sets `deleted_at`, so it neither trips the trigger nor needs UI gating.
3. Under-threshold auto-clear is server-owned: `place_expense` places the line in its envelope and then marks it `approved`, so it remains present in the books and envelope total.
4. Expenses above `admin_approval_threshold` require admin approval specifically (user must have `expenses.approve` permission)
5. A submitted expense is filed immediately by `trg_place_expense`; the daily sweep only repairs historical/legacy orphans and advances due envelopes.
6. `accounting_sync_status`: `pending` (no connection), `synced` (pushed to QB/Sage), `error` (sync failed)
7. Receipt images upload through the authenticated OPS-Web presign API to S3. For the current client, the server derives `expenses/{companyId}/{userId}/{expenseId}/{uploadId}-{full|thumbnail}.jpg` from the authenticated OPS user plus validated UUIDs; client folder/filename input cannot select the key. Retrying the same tuple overwrites the same object instead of leaking duplicates, and deterministic keys may be deleted only by that user. Legacy presign classes retain random server-generated keys, but the prepared delete-route hardening is resource-specific and default-deny: recognized receipt, profile, logo, lead-photo, and project-photo keys are checked against their canonical owner/edit/admin rules; unknown or unresolvable keys are rejected. This web hardening is committed locally but is not deployed until OPS-Web `main` is explicitly pushed.
8. OCR data (raw text, extracted fields, confidence) stored in `ocr_raw_data` (JSONB) and `ocr_confidence` (0-1) for audit trail — captured from `AppleVisionOCRService` via `OCRResult.rawDataDict`
9. The current iOS save replaces project allocations inside `save_expense_atomic`'s transaction. If allocation validation, placement, or total recalculation fails, neither expense content nor allocations persist. Legacy relation mutations advance the parent expense's strict `updated_at` token; the atomic path locks allocation rows before the parent to match shipped-client trigger order and avoid deadlocks.
10. Default categories seeded automatically on first load per company

11. **Receipt requirement enforcement + no-receipt escape hatch (hardened 2026-07-19).** When `expense_settings.require_receipt_photo = true`, iOS blocks submission without either a receipt photo or a deliberate **No receipt available** reason (`lost` | `cash` | `digital` | `other`, plus optional note). Policy loading is fail-closed; a missing settings row resolves to the database default (`require_receipt_photo=true`) instead of disabling the rule. `ExpenseFormSheet` provides the immediate gate, and `save_expense_atomic` authoritatively enforces the same rule for the new client. Enforcement lives in this additive RPC rather than a global table trigger so already-shipped clients remain operational. A real photo always clears exception metadata. OPS-Web surfaces the reason to approvers in the expense detail.
12. **No silent or partial receipt save (hardened 2026-07-19).** A new receipt uploads before any database write. Upload failure keeps the complete form on screen with `// RECEIPT UPLOAD FAILED` and a receipt-specific retry; no placeholder draft is created. If the database response is uncertain after upload, the form locks the saved intent, shows `// SAVE NOT CONFIRMED`, and retries the exact same idempotency command. A definitive 4xx/Postgres rejection unlocks the form with actionable copy, clears the retry command, and best-effort deletes only that attempt's user-owned staged objects. Only a confirmed atomic response dismisses the form. Thumbnail timeouts retry the same key once before falling back to the full image.
13. **Project requirement enforcement + no-project escape hatch (hardened 2026-07-19).** When `require_project_assignment` is on, submission requires either allocations or a deliberate reason (`overhead` | `general` | `other`, plus optional note). Policy loading fails closed, while a missing row resolves to the database default (`false`). The form gates for immediate feedback and `save_expense_atomic` enforces the rule, clears exception metadata when allocations exist, validates every project belongs to the company, and limits `per_job` companies to one allocation. Already-shipped direct-table clients remain compatible.

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

**Location**: `ops-ios/OPS/Views/Estimates/`, `ops-ios/OPS/Views/Invoices/`, `ops-ios/OPS/Views/Accounting/`

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

**Location**: `ops-ios/OPS/Views/Expenses/`

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

**Location**: `ops-ios/OPS/ViewModels/`

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
- **Operations**: `loadAll()` (parallel: expenses + categories + settings + batches), `loadExpenses()`, `saveExpenseAtomically(_:)`, `fetchExpense(_:)` (authoritative ambiguous-response readback), `deleteExpense(_:)`, `approveExpense(_:)`, `rejectExpense(_:reason:)`, `loadCategories()`, `loadBatches()`, `toggleCategory(_:isActive:)`, `scanReceipt(image:)` (OCR via AppleVisionOCRService), `loadSettings()`, `ensureSettingsLoaded()`, `saveSettings(_:)`, `createCategory(companyId:name:icon:)`
- **Project-scoped**: `loadExpensesForProject(projectId:)` — loads expenses allocated to a specific project
- **Repository**: `ExpenseRepository`

#### ClientLeadsViewModel / Client Profile Leads Surface (2026-07-21)

`ClientLeadsViewModel` (`ops-ios/OPS/ViewModels/ClientLeadsViewModel.swift`) backs the **Leads** section on the client profile — `ClientLeadsSection` + `ClientLeadRow` (`ops-ios/OPS/Views/Components/Client/`), spliced into `ContactDetailView` above Projects and gated on `permissionStore.leadAccessPolicy.canViewAny`.

- **Data**: loads via `OpportunityRepository.fetchAllLinked(toClientId:)`, then a pure `apply(...)` transform filters row-by-row on `leadAccessPolicy.can(.view, assignedTo:)`, drops deleted/archived, and splits into open (non-terminal, activity-desc) and closed (won/lost/discarded, close-date-desc) with outcome tallies. Opportunities are not SwiftData-synced, so the section reloads on appear, on the lead-mutation notifications `LeadsTabView` observes (`LeadCreatedSuccess`, `LeadUpdatedSuccess`, `LeadMarked{Lost,Won}Success`, `LeadConvertedSuccess`, `LeadLinkedProjectSuccess`, `LeadArchivedSuccess`, `LeadDeletedSuccess`, `.opsLeadsDidChange`), and when the detail/action sheets dismiss.
- **Presentation**: header count = open leads; open rows lead with the job (`title` → `displayContactName`) + value + stage badge, capped at 5 with a show-more; a collapsed history peek (`// N WON · M LOST`) expands the terminal leads; empty state mirrors Projects ("No leads yet / Create one?").
- **Actions**: tap → `LeadDetailView` (edit / mark-lost / convert routed through a local `LeadsSheet` host); header "Add" → `AddLeadSheet(seedClient:)`, which pre-fills the form from the client and binds the client id directly (bypassing name-based `resolveClientId`, so the new lead links to exactly that client). No new data model, migration, or schema change — a read/create surface over existing `opportunities`.

#### OpportunityDetailViewModel

Manages activities and follow-ups for a single opportunity detail screen.

- **Published state**: `activities`, `followUps`, `isLoading`, `error`
- **Operations**: `loadDetails(for:)` (parallel fetch of activities + follow-ups via `async let`), `logActivity(opportunityId:companyId:type:body?:)`, `createFollowUp(opportunityId:companyId:type:dueAt:notes?:)`
- **Repository**: `OpportunityRepository`

### iOS Supabase Repositories

**Location**: `ops-ios/OPS/Network/Supabase/Repositories/`

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
- `saveAtomically(ExpenseAtomicSaveCommand)` -- calls `save_expense_atomic` with a full snapshot, stable request ID, and expected status/`updated_at`; returns the authoritative expense with allocations/category
- `approve(expenseId, approvedBy)` -- sets status=approved, approved_by, approved_at
- `reject(expenseId, rejectedBy, reason)` -- sets status=rejected, rejection_reason
- `softDelete(expenseId)` -- sets `deleted_at` timestamp
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
- `fetchAllLinked(toClientId:)` -- all non-deleted opportunities for a client across every stage (open + terminal), `created_at` desc. Backs the client-profile Leads section (2026-07-21). Mirror of `fetchFirstActiveLinked` without the `.limit(1)`.
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

**Location**: `ops-ios/OPS/Network/Supabase/DTOs/`

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

**Location**: `ops-ios/OPS/DataModels/Enums/FinancialEnums.swift`

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

**Location**: `ops-ios/OPS/Services/ExpenseOCRService.swift`

Protocol-based architecture for receipt OCR:

```swift
protocol ExpenseOCRServiceProtocol {
    func extractReceiptData(from image: UIImage) async throws -> OCRResult
}
```

**OCRResult** struct: `merchantName`, `date`, `total`, `subtotal`, `taxAmount`, `paymentMethod`, `rawText`, `confidenceScores` (per-field confidence 0-1).

**AppleVisionOCRService**: Uses `VNRecognizeTextRequest` with `.accurate` recognition level. Processes all recognized text through `ReceiptParser` which uses regex patterns and heuristics to extract structured fields from raw OCR text.

### iOS BOOKS Tab (Command Grid, June 2026)

**Status:** Current architecture is the **"1b · Command Grid" redesign** (2026-06-30, Claude Design handoff `ops-money-and-leads-redesign`, merged `36eb2130`) plus the **ledger-actions deepen** (2026-07-01: row swipe actions, real receipt thumbnails, batch-review entry, UTC date fix). The swipeable hero carousel is **superseded on the tab** — replaced by a single scannable KPI grid — but `HeroCarousel.CardID` and the `ExpandedCardSheet` family survive as the tile drill-down sheets. Pure view layer throughout: no schema, migration, or `MoneyDashboardViewModel` math changes. Lineage: Phase 1 4-segment hub (2026-05-07) → Phase 2 carousel command center (2026-05-11) → Phase 3 Mission Deck visual rebuild (2026-05-19) → Phase 6 condensed-card + expand-sheet overhaul (2026-06-01) → **Command Grid + flat ledger (2026-06-30)** → **ledger actions deepen (2026-07-01)**.

**Surface:**
- Rendered by `MainTabView`; container `BooksTabView` (`OPS/Views/Books/BooksTabView.swift`). Header `AppHeader.HeaderType.books` (title "BOOKS").
- Top-to-bottom in one scroll surface: AppHeader → optional `BooksSyncBanner` → (`LazyVStack(pinnedViews: [.sectionHeaders])`) `PeriodPill` (when `finances.view`) → **`BooksCommandGrid`** → a **pinned ledger band** (`BooksLedgerSegments` + `TacticalChipRow` filter chips + a `// LABEL · count` marker + hairline) → **`BooksLedger`** flat rows. Active segment persists via `@AppStorage("books.selectedSegment")` (also read by the global FAB).

**Command grid** — `BooksCommandGrid` (`OPS/Views/Books/CommandGrid/`): a full-width **NET CASH hero** (`CountUpText` Mohave-Light 42, margin caption, weekly-nets sparkline), a 2×2 of **CASH FLOW** (weekly in/out bars + net-per-week) · **RUNWAY** (tan-toned tile, forecast line + LOW $ · WK n + ON TRACK/WATCH/DANGER badge) · **RECEIVABLES** (total + overdue + 4-bucket aging ramp) · **FORECAST** (weighted pipeline + open count), and a full-width **JOB PROFITABILITY strip** (avg margin + per-job margin bars + profit/loss counts). Every number is the SAME value its lens already computes (derived helpers mirror the lens math exactly — margin `netCash/totalPayments`, aging split 31/61/91). Mini-charts live in `BooksMiniCharts.swift`; the `.commandCard()` surface + `BooksFormat` + `CountUpText` in `BooksCommandKit.swift`. Skeleton grid on the cold no-cache path only (`isLoading && !hasEverLoaded`).

**Tile drill-downs** (light impact on tap):
- NET CASH hero → `ExpandedCardSheet(.pl)`; CASH FLOW → `.cashFlow`; RECEIVABLES → `.ar` (merged `ARDetailSheet`); FORECAST → `.forecast`; JOB PROFITABILITY → `.jobs` — all `.medium/.large` detents.
- RUNWAY → `CashflowForecastScreen` full-screen cover (the full runway/forecast surface; `CashflowForecastCard` no longer mounts on the tab itself).
- Sheet drills back into the ledger: `onDrillOutstanding` → Invoices segment + `overdue` filter; `onDrillForecast` → Estimates segment + `out` filter.
- `PeriodPill` (8 periods) drives the same `MoneyDashboardViewModel.selectedPeriod` recalculation as before (hero/cash-flow/jobs re-scope; A/R and forecast are period-independent).

**Ledger** — `BooksLedger` + `BooksLedgerRows` + `BooksLedgerControls` (`OPS/Views/Books/Ledger/`): the segments render **flat hairline rows directly off the shared VMs** (`InvoiceViewModel` / `EstimateViewModel` / `ExpenseViewModel`) — the old `embedded: true` list-view mounting is gone. Books owns its own filter state so the chip sets differ from the standalone lists: invoices **ALL · UNPAID · OVERDUE · PAID**, estimates **ALL · OUT · WON**, expenses **ALL · NO RECEIPT · NEEDS OK** (tone-tinted counts). Sort ranks urgency first (overdue → partial → out → draft → terminal; estimates approved → viewed → sent; expenses no-receipt → needs-OK). Client/crew names resolve via `@Query [Client]` / `[TeamMember]`. Row tap → `InvoiceDetailView` / `EstimateDetailView` / `ExpenseFormSheet` (edit). Empty states carry create CTAs (`NEW ESTIMATE` → `EstimateFormSheet`, `LOG EXPENSE` → `ExpenseFormSheet`).

**Row swipe actions (2026-07-01)** — `BooksSwipeRow` (`OPS/Views/Books/Ledger/BooksRowActions.swift`) implements the MOBILE.md §7.2 spec on LazyVStack rows (SwiftUI `.swipeActions` is List-only): 80pt strips (max 2/side), olive positive / rose destructive, follow-the-finger reveal with 150ms one-curve snaps, snap-open past 50% of the strip, one open row ledger-wide, full **right**-swipe past 75% committing the non-destructive primary, long-press context menus + VoiceOver rotor actions mirroring every strip, reduced-motion snap fallback.
- **Invoice**: leading `PAYMENT` (gate `status.needsPayment`) → `PaymentRecordSheet`; trailing `VOID` (gate not paid/void/written-off) → destructive confirm → `voidInvoice`. Write-off intentionally stays in `InvoiceDetailView` (rare, heavy).
- **Estimate**: leading `SEND` (draft → `sendEstimate`, immediate + success haptic) or `CONVERT` (approved → confirm → `convertToInvoice`, then reloads invoices so the new invoice lands in the ledger).
- **Expense**: trailing `DELETE` (gate = submitter or admin/owner AND not approved/reimbursed — mirrors the server soft-delete authorization) → destructive confirm → `deleteExpense` (soft delete; posts `opsExpensesDidChange`).
- VM errors surface via `.errorToast` on all three VMs; destructive dialogs reuse the standalone lists' exact copy.

**Expense rows**: real receipt thumbnails — `AsyncImage(receipt_thumbnail_url ?? receipt_image_url)` at 34×42 (same resolution order as the batch-review hub); the abstract receipt block is the loading/failure stand-in, and only a missing URL renders the rose dashed no-receipt state. Date metadata formats **date-only columns in UTC** (`BooksLedgerStatus.shortDate`) — parsing anchors midnight UTC, so local-time formatting read yesterday west of Greenwich (same class of bug the web ledger's unit suite caught; both surfaces now display the literal stored day).

**Batch-review entry**: approvers (`expenses.approve` — same gate as the Settings row) get a discreet `REVIEW BATCHES →` affordance (`BooksReviewBatchesLink`) in the expenses ledger marker — tan with a count when envelopes need review (same pending/submitted predicate as the hub's NEEDS REVIEW tab, computed off `expenseVM.batches`) — pushing `ExpensesListView` inside the Books stack. The hub is no longer a Money embed; Settings retains its entry.

**States** (`OPS/Views/Books/Components/`): `BooksSyncBanner` (`SYS :: SYNC/OFFLINE/ERROR` + RETRY) above the grid; skeleton grid on cold start; ledger empty states (`$0` / `—` + `// NO …` + hint, or `NO MATCHES` when a filter empties a non-empty ledger); native `.refreshable` (dashboard first, then the three ledgers in parallel, then the runway forecast).

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

**Permission gating:**
- Tab visible (`MainTabView.hasBooksAccess`) with any of `finances.view` / `estimates.view` / `expenses.view`; `pipeline.view` gates the separate Pipeline tab, not BOOKS.
- Grid: `finances.view` gates the NET CASH hero, CASH FLOW, RUNWAY, RECEIVABLES, JOB PROFITABILITY (and the PeriodPill); `pipeline.view` gates FORECAST; hidden tiles **reflow** the 2×2; the whole grid hides when the user holds neither.
- Segments filtered by `BooksSection.requiredPermission` (Invoices `finances.view`, Estimates `estimates.view`, Expenses `expenses.view`); the selection auto-switches when the active segment loses visibility. Deep links (`BooksSelectSegment`, `OpenCashflowForecast`) honor the same gates.
- The expenses ledger renders `expenseVM.expenses` **directly for every role** — RLS decides the row set (verified live 2026-07-01: `role_scope_read` = admin OR `expenses.view` scope `all` → company-wide, scope `own` → `submitted_by = current user`). The old MyExpensesView-vs-ExpensesListView embed split is gone from Books; `MainTabView.booksAutoSkipDestination` still routes a single-segment user (e.g. own-scope-expenses crew) straight to `MyExpensesView` / standalone lists, so such users never see the Books ledger at all.
- Role outcomes: **Owner** — full grid + 3 segments + batch-review entry; **Operator** (estimates + expenses, no finances/pipeline) — no grid, Estimates/Expenses segments, own-scope expense rows; **Crew** (own-scope `expenses.view` only) — auto-skipped to `MyExpensesView`.

**Accessibility:**
- Grid tiles carry composed labels + hints (e.g. "Net cash $X, Y percent margin — opens the profit and loss detail"); the ledger band, chips, and sync-banner RETRY are individually navigable.
- Swipe strips are mirrored as VoiceOver rotor actions on each row (custom strips aren't reachable by swipe under VoiceOver); long-press context menus give a third path.
- Dynamic Type — hero numbers scale down via `minimumScaleFactor`; 44pt hit targets on the period pill, ledger rows, strip buttons, and the REVIEW BATCHES link.

**FAB integration:**
- The global `FloatingActionMenu` (`OPS/Views/Components/FloatingActionMenu.swift`) re-orders its MONEY group via `@AppStorage("books.selectedSegment")` so the create action for the active segment floats to the front. `add-lead` stays in the MONEY group — the FAB is global and the Pipeline tab split does not move the create action.

**Deferred / known gaps (as-built):**
- `BooksPTRIndicator` (OPS-mark + spin-arc + `SYNCING` label) is built but **not wired in** — it is a standalone view, not a `ProgressViewStyle`, so it cannot drive the system refresh control. Pull-to-refresh ships on native `.refreshable`.
- Invoice amounts render `.currency(code: "USD")`-style regardless of locale (a CA-locale device shows `US$4,800`); invoices carry no currency column (expenses do). A multi-currency pass is future scope.
- Estimates have no trailing swipe action — estimate void/withdraw is unimplemented app-wide (`EstimatesListView` has the same gap).

**History:** the Phase 2–6 carousel architecture (5 condensed `PLCard`/`CashFlowCard`/`ARCard`/`ForecastCard`/`JobsCard` glance tiles, dot pagination, `CollapsedCarouselStrip`, per-card skeleton/error states) is superseded on the tab; `ExpandedCardSheet`/`ARDetailSheet` and the card lens math live on as the tile drill-downs. Phase 1's `MoneyDashboardHeader` / `SmartStatCarousel` / `FinancialHealthBar` / `PeriodToggle` were removed in the Phase 2 cleanup.

**Spec & plan:**
- Command Grid redesign: Claude Design handoff `ops-money-and-leads-redesign` ("1b · Command Grid" direction), merged 2026-06-30; ledger-actions deepen 2026-07-01.
- Phase 3 Mission Deck visual rebuild: `ops-ios/docs/superpowers/specs/2026-05-19-books-tab-mission-deck-rebuild.md`.
- Phase 2 carousel architecture: `ops-ios/docs/superpowers/specs/2026-05-11-books-ui-reconstruction-design.md` + plan `2026-05-11-books-ui-reconstruction.md`.
- Phase 1 (superseded): `ops-ios/docs/superpowers/specs/2026-05-07-books-tab-design.md`.

---

## OPS-Web Books Surface (2026-06-11)

**Status:** Shipped in WEB OVERHAUL P3.1 on `feat/web-overhaul` (local program branch). `/books` absorbed the web Estimates, Invoices, and Accounting pages, the orphan-adjacent expense review hub, and the `/money/cashflow` placeholder; the old page directories are deleted and `src/middleware.ts` owns param-preserving 308s (`/estimates`→`segment=estimates` · `/invoices`→`segment=invoices` · `/accounting`→`segment=invoices&view=aging`, `?tab=expenses`→`segment=expenses`, `?tab=integrations`→`segment=sync`, `?tab=import`→`segment=sync&view=import` · `/money/cashflow` + `/books/cashflow`→`/books`). UX reference: `02_USER_EXPERIENCE_AND_WORKFLOWS.md § OPS-Web Books`.

### Ledger service (`books-service.ts`)

`BooksService.fetchLedger(companyId, period)` gathers in parallel and delegates to the pure `computeLedger` (unit-tested at `tests/unit/services/books-service.test.ts`):

- **Periods** — the iOS PeriodPill set (`30d/90d/6m/1y/this_month/last_month/this_quarter/ytd`); NET, CASH FLOW, JOBS re-scope, A/R is always all-open.
- **NET** — `payments` in window (non-voided, by `payment_date`) minus `expenses` in window (non-deleted, status ∈ submitted/approved/reimbursed — drafts and rejected lines never count); margin = net/paymentsIn.
- **CASH FLOW** — weekly nets bucketed by Monday-start weeks. Postgres DATE strings are parsed as **local** dates (UTC parsing shifted a day west of Greenwich — caught by the unit suite).
- **A/R** — non-deleted invoices, status ∉ {paid, void, draft, written_off}, `balance_due > 0`; 4 ramp buckets by days overdue where 0–30 includes not-yet-due (iOS ARCard convention; the in-page aging *view* keeps the old 5-bucket CURRENT split); top chase = largest per-client open balance (name resolved client-side via `useClients`).
- **JOBS** — revenue = in-window payments joined through `invoices.project_id`; cost = `expense_project_allocations.amount` with `expense.amount × percentage/100` fallback (string-on-string join — allocations `project_id` is text); display slice = top 4 by net with the iOS −$500 worst-loser displacement.

### Swap mechanics

The nav registry entry (`key: books`, order 6, lucide `Calculator` per the icon brief's `nav-finance` concept) introduced `anyOfPermissions` — `["invoices.view","estimates.view","expenses.approve","accounting.view"]` — consumed by the dashboard layout gate, sidebar (flag dimming + RBAC hiding), and command palette. `/books` joined the `accounting` feature flag's route list (flag-off companies stay gated across the redirect hop). FAB retargets: expense → `/books?segment=expenses`, invoice → `/books?segment=invoices&action=new`. The QBO import-apply notification now writes `action_url: "/books?segment=sync&view=import"`. ~20 dashboard-widget links deep-link straight to segments (expense contexts → expenses; payment/A-R contexts → invoices aging).

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
- OPS-Web cashflow forecast — tracked at `ops-web/docs/bugs/2026-05-11-cashflow-forecast-web-followup.md`. Web ships a placeholder route initially; full web build is a separate plan.

### Spec & plan

- Design spec: `docs/superpowers/specs/2026-05-11-cashflow-forecast-design.md`
- Implementation plan: `docs/superpowers/plans/2026-05-11-cashflow-forecast.md`

---

**Last Updated**: 2026-05-25
**Document Version**: 1.5
**Source**: ops-web git commits `0b268fd`, `2742b60`, `f5a01f1`, `81577c4`; iOS source `ops-ios/OPS/`; Supabase Edge Functions `accounting-oauth`, `accounting-sync-expense`, `accounting-batch-create`. Cashflow Forecast addition based on iOS branch `cashflow-forecast` + Supabase migration `add_cashflow_forecast_tables`.
