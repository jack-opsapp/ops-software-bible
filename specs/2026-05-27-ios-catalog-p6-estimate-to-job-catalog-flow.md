# iOS Catalog Phase 6 Estimate-to-Job Catalog Flow Specification

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans to implement this plan task-by-task. This document is a specification and implementation plan, not an applied migration. Do not apply schema, write production data, or mark QA rows fixed without the explicit approval gates listed below.

**Goal:** When an estimate is accepted, OPS updates the lead-backed project, verifies required tasks, and, for companies with inventory tracking enabled, creates projected material demand and warnings without deducting stock until task completion.

**Architecture:** Estimate acceptance becomes a single server-authoritative transaction. Company inventory mode is explicit, not inferred from catalog rows or permissions. Booking writes projected demand and immutable snapshots; task completion writes actual stock consumption, stock-unit events, and final material history.

**Tech Stack:** iOS Swift/SwiftUI, Supabase Postgres, Supabase RPC, RLS, OPS catalog schema, OPS notification rail.

---

## Scope And Stop Rules

This Phase 6 spec covers schema/function/iOS implementation planning only.

Hard stops:
- Do not change iOS code from this spec alone.
- Do not apply migrations from this spec alone.
- Do not write Supabase data from this spec alone.
- Do not mark `qa_bugs` or `bug_reports` rows fixed from this spec alone.
- Do not weaken auth/RLS.
- Do not run broad builds/tests unless PM explicitly approves a verification gate.

Approved save path:
- `/Users/jacksonsweet/Projects/OPS/ops-software-bible/specs/2026-05-27-ios-catalog-p6-estimate-to-job-catalog-flow.md`

## Live Audit Summary

### Preflight

- iOS worktree: `/Users/jacksonsweet/Projects/OPS/ops-ios 10f76754 [feat/vinyl-auto-order]`
- iOS branch: `feat/vinyl-auto-order`
- `pgrep -xfl xcodebuild`: process-list inspection was attempted; the local environment returned `sysmond service not found`, so no process-state claim is made from that command.
- Root `AGENTS.md` and `ops-ios/CLAUDE.md` were read before conclusions.
- iOS and Bible worktrees were dirty before this spec save. Unrelated dirty files were not cleaned, staged, stashed, reverted, or edited.

### Supabase Evidence

Live project inspected: `ops-app` / `ijeekuhbatykdomumfjx`.

Read-only queries used:
- `information_schema.columns`
- `pg_policies`
- `pg_indexes`
- `pg_constraint`
- `pg_proc`
- `pg_get_functiondef`
- targeted table row counts
- targeted feature/permission lookups
- targeted `qa_bugs` row lookup

Tables inspected:
- `estimates`
- `line_items`
- `projects`
- `project_tasks`
- `product_materials`
- `task_materials`
- `line_item_materials`
- `catalog_variants`
- `catalog_stock_units`
- `catalog_stock_unit_events`
- `catalog_product_option_mappings`
- `notifications`
- `qa_bugs`
- `companies`
- `company_settings`
- `feature_flags`
- `feature_flag_overrides`

Functions inspected:
- `convert_lead_to_project`
- `catalog_setup_save`
- `users_with_permission`
- material/inventory/stock/deduction function search

Live findings:
- No dedicated company inventory-mode table exists.
- `company_settings` exists but uses `company_id text` and currently carries generic settings such as `auto_generate_tasks`, not catalog inventory operating mode.
- `feature_flags` are rollout controls, not per-company operating mode.
- No projected material demand table exists.
- No dedicated project/task material snapshot table exists.
- No stock-unit allocation table exists.
- `task_materials` has `catalog_variant_id`, but not `catalog_stock_unit_id` or immutable stock-unit snapshot JSON.
- `project_tasks` has `inventory_deducted`, but current iOS project task model/DTO paths do not carry it.
- `catalog_stock_units` and `catalog_stock_unit_events` exist and are the correct stock-unit and ledger foundation.
- `inventory_deductions` exists for actual inventory deduction records, but live function inspection did not find a task-completion stock consumption RPC.
- `convert_lead_to_project` exists and creates/updates projects/tasks from accepted/won opportunity data, but iOS live code does not call it from estimate approval.
- `convert_lead_to_project` is not safe to reuse directly for Phase 6 acceptance: it uses elevated public execution, broad anon/auth grants, a client-supplied actor argument, returns early when a project already exists, and does not enforce idempotent task/photo keys.
- `catalog_setup_save` exists as the Phase 5 atomic catalog setup RPC.
- `users_with_permission` exists and must be used for notification recipients instead of hardcoded role strings.

QA row inspected:
- `qa_bugs.id = a0ead424-8163-411f-96a9-b38486b5e1c6`
- Title: `iOS Catalog P6: persistent setup notification for missing product-to-stock mappings`
- Status: `new`
- Severity: `medium`
- `requires_human_review = true`
- `verified = false`
- The row was not changed.

## Live iOS Code Evidence

Estimate approval/status path:
- `OPS/ViewModels/EstimateViewModel.swift`
  - `markApproved` calls private `updateStatus`.
  - `updateStatus` optimistically updates local status, calls repository status update, then refreshes the estimate.
- `OPS/Network/Supabase/Repositories/EstimateRepository.swift`
  - `updateStatus` directly updates `estimates.status`.
  - No project conversion, task verification, projected demand, or stock logic exists in this path.

Lead/project conversion and task generation:
- `OPS/Views/Leads/LeadsTabView.swift`
  - Existing lead win path calls `viewModel.markWon`.
- `OPS/ViewModels/PipelineViewModel.swift`
  - Delegates opportunity win behavior to `OpportunityRepository`.
- `OPS/Network/Supabase/Repositories/OpportunityRepository.swift`
  - Uses `move_opportunity_stage` and optional opportunity patching.
  - Does not call `convert_lead_to_project`.
- `OPS/Network/Supabase/Repositories/ProjectRepository.swift`
  - Creates/updates projects through client-side table writes.
- `OPS/Network/Supabase/Repositories/TaskRepository.swift`
  - Creates/updates tasks through client-side table writes.

Material resolution:
- `OPS/Services/RecipeResolver.swift`
  - Resolves product material recipes to catalog variants using pinned variant or family selector.
  - Computes required quantity per estimate/task quantity.
  - Throws for missing variants.
- `OPS/Services/CutListMaterializer.swift`
  - Converts line item products/options into `task_materials`.
  - No automatic acceptance hook is installed.
  - No projected demand, allocation, or stock-unit snapshot behavior exists.
- `OPS/Network/Supabase/Repositories/TaskMaterialRepository.swift`
  - Bulk inserts `task_materials`.
  - Caller owns idempotency.
- `OPS/Network/Supabase/DTOs/TaskMaterialDTOs.swift`
  - Carries `catalogVariantId`, not `catalogStockUnitId`.
- `OPS/Network/Supabase/DTOs/ProductExtensionDTOs.swift`
  - Product material DTOs carry product/catalog material recipe fields.
- `OPS/Network/Supabase/Repositories/ProductRichnessRepository.swift`
  - Creates/updates/deletes product material rows.
  - Existing hard-delete comment is stale against live schema, which now has `deleted_at`.

Task completion stock deduction hook points:
- `OPS/Utilities/DataController.swift`
  - `updateTaskStatus` is the central completion path.
  - Completion currently sends notifications/analytics/dependency updates, not stock deduction.
  - `updateProjectStatus` has a catalog materialization note when a project enters progress, but it is not wired.
- `OPS/Network/Supabase/Repositories/TaskRepository.swift`
  - `updateStatus` patches task status only.
- `OPS/Views/Components/Project/TaskCompletionChecklistSheet.swift`
  - Completes selected tasks through `DataController.updateTaskStatus`.
- `OPS/Views/Components/Project/TaskDetailsView.swift`
  - Status chips and completion flows call `updateTaskStatus`.
- `OPS/Views/Components/Project/ProjectDetailsViewModel.swift`
  - Project completion loops through incomplete tasks and calls `updateTaskStatus`.
- `OPS/Views/Components/Project/ProjectActionBar.swift`
  - Completes active task through `DataController.updateTaskStatus`.

Catalog setup/current inventory foundation:
- `OPS/Network/Supabase/CatalogSchemaCapabilityGate.swift`
  - Probes live schema before enabling stock unit and mapping paths.
- `OPS/Network/Supabase/Repositories/CatalogRepository.swift`
  - Calls `catalog_setup_save`.
  - Has variant-level `recordVariantDeduction`, but not stock-unit completion consumption.
- `OPS/Services/CatalogStockUnitAggregator.swift`
  - Aggregates available stock-unit quantity/length/area.
  - Excludes unavailable statuses.
- `OPS/Network/Supabase/Repositories/CatalogStockUnitRepository.swift`
  - Fetches/saves/soft-deletes stock units behind schema capability.
- `OPS/Network/Supabase/Repositories/CatalogProductOptionMappingRepository.swift`
  - Fetches/saves/soft-deletes product option mappings behind schema capability.
- `OPS/Services/CatalogSetupWorkflow.swift`
  - Builds Phase 5 setup payloads, including stock units, events, materials, and mappings.
- `OPS/Views/Catalog/Stock/CatalogSetupFlowSheet.swift`
  - Preflights stock/mapping violations and calls `saveCatalogSetup`.

Notifications:
- `OPS/Network/Supabase/Repositories/NotificationRepository.swift`
  - Create DTO supports `persistent`, `action_url`, and `action_label`.
  - Current cleanup helpers mark read by type or URL pattern, but there is no durable resolution key.
- `OPS/Network/Supabase/DTOs/NotificationDTO.swift`
  - DTO carries action URL/label and deep link fields.
- `OPS/Views/Notifications/NotificationListView.swift`
  - Routes by `deep_link_type`, type fallback, and project fallback.
  - Catalog orders route exists; missing mapping setup route is not defined yet.
- `OPS/Utilities/NotificationManager.swift`
  - Push/local notification categories exist.
- `ops-software-bible/07_SPECIALIZED_FEATURES.md`
  - Notification contract requires specific type, body, deep link, action URL, action label, persistent semantics, and recipient lookup via `users_with_permission`.

## Architecture Decisions

### Decision 1: Add Explicit Company Inventory Mode

OPS must not infer inventory behavior from stock rows, catalog setup state, or permissions.

Add a dedicated company operating-mode table:

```sql
create table public.company_inventory_settings (
  company_id uuid primary key references public.companies(id) on delete cascade,
  inventory_mode text not null default 'off',
  enabled_at timestamptz,
  disabled_at timestamptz,
  updated_by uuid,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint company_inventory_settings_mode_check
    check (inventory_mode in ('off', 'tracked')),
  constraint company_inventory_settings_enabled_at_check
    check (
      (inventory_mode = 'tracked' and enabled_at is not null)
      or inventory_mode = 'off'
    )
);
```

Operational behavior:
- `off`: no projected material demand, no material warnings, no missing-mapping setup notifications, no stock deduction.
- `tracked`: estimate acceptance creates projected demand, overrun warnings, missing-mapping persistent notifications, and task completion stock deduction.

Turning inventory tracking off:
- Must not delete history.
- Must release open projected demand rows.
- Must preserve material snapshots, stock-unit events, and actual consumption records.
- Must prevent future automatic deduction until tracking is re-enabled.

### Decision 2: Projected Demand Needs A Separate Table

Projected material demand is neither `task_materials` nor `inventory_deductions`.

Recommendation: create `public.project_material_demands`.

Reasoning:
- Booking creates planned demand, not actual stock movement.
- Allocation can go negative as projected overrun without blocking the job.
- Completion consumes actual stock and must remain auditable.
- Demand needs status transitions before and after task completion.

### Decision 3: Material History Needs Dedicated Snapshot Tables

Material history must capture:
- auto-assigned materials
- crew adjustments
- final consumed stock
- exact stock-unit snapshots at booking and completion

Recommendation:
- `public.project_material_snapshots`
- `public.project_material_snapshot_items`

Reasoning:
- A stock unit can change location/status/remaining quantity between booking and completion.
- Project history must show what OPS believed at the time.
- Queryable columns are needed for reporting; immutable JSON is needed for audit fidelity.

### Decision 4: `task_materials` Should Not Link Directly To Stock Units

Do not add `catalog_stock_unit_id` directly to `task_materials`.

Recommendation: use allocation rows:
- `public.task_material_allocations`

Reasoning:
- One task material can consume multiple stock units.
- One stock unit can feed multiple tasks.
- Overrun demand may not have a stock unit.
- Crew final consumption can differ from booking projection.
- Direct FK would conflate recipe demand with physical stock allocation.

### Decision 5: Stock-Unit Snapshots Must Include Immutable JSON

Snapshot item rows must store both queryable columns and immutable JSON.

Minimum JSON payload:

```json
{
  "catalog_stock_unit_id": "uuid",
  "catalog_variant_id": "uuid",
  "unit_kind": "roll",
  "label": "ROLL-001",
  "lot_code": "LOT-123",
  "width_value": 54,
  "width_unit": "in",
  "original_length_value": 150,
  "remaining_length_value": 80,
  "quantity_value": 1,
  "location": "SHOP",
  "status": "partial",
  "captured_at": "2026-05-27T00:00:00Z",
  "source_event_id": "uuid"
}
```

### Decision 6: Missing Mapping Notifications Resolve By Key

Missing product-to-stock mappings must not block estimate acceptance.

Behavior:
- Create or update a persistent setup notification.
- Use deterministic dedupe/resolution key.
- Action links to the catalog setup/mapping fix surface.
- Resolve when the mapping exists and the missing key no longer fails validation.

Current notification cleanup by type is too broad for this requirement. Add resolution columns.

## Proposed Schema

### `company_inventory_settings`

```sql
create table public.company_inventory_settings (
  company_id uuid primary key references public.companies(id) on delete cascade,
  inventory_mode text not null default 'off',
  enabled_at timestamptz,
  disabled_at timestamptz,
  updated_by uuid,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint company_inventory_settings_mode_check
    check (inventory_mode in ('off', 'tracked')),
  constraint company_inventory_settings_enabled_at_check
    check (
      (inventory_mode = 'tracked' and enabled_at is not null)
      or inventory_mode = 'off'
    )
);

alter table public.company_inventory_settings enable row level security;

create policy company_inventory_settings_company_select
on public.company_inventory_settings
for select
using (company_id = private.get_user_company_id());

-- Do not approve a broad company-only direct write policy.
-- Final migration must either mutate this table only through the
-- permission-gated set_company_inventory_mode RPC or restrict direct writes
-- with the same company guard plus private.current_user_has_permission('catalog.manage', 'all').
```

Implementation note:
- Final migration should prefer RPC-owned writes through `public.set_company_inventory_mode`.
- Direct table writes must be revoked/restricted or permission-gated before migration approval.
- Live permission audit found `catalog.manage`; use that existing permission for inventory-mode management. Do not add a new permission unless a fresh live permission audit proves `catalog.manage` cannot cover this control.

### `project_material_demands`

```sql
create table public.project_material_demands (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  project_id uuid not null references public.projects(id) on delete cascade,
  task_id uuid references public.project_tasks(id) on delete set null,
  estimate_id uuid references public.estimates(id) on delete set null,
  line_item_id uuid references public.line_items(id) on delete set null,
  product_id uuid references public.products(id) on delete set null,
  product_material_id uuid references public.product_materials(id) on delete set null,
  catalog_variant_id uuid references public.catalog_variants(id) on delete set null,
  unit_id uuid references public.catalog_units(id) on delete set null,
  demand_key text not null,
  source text not null default 'estimate_acceptance',
  status text not null default 'projected',
  required_quantity numeric not null,
  available_quantity_at_booking numeric,
  projected_overrun_quantity numeric not null default 0,
  resolver_payload jsonb not null default '{}'::jsonb,
  warning_payload jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  constraint project_material_demands_status_check
    check (status in ('projected', 'warning', 'allocated', 'consumed', 'released', 'superseded')),
  constraint project_material_demands_required_quantity_check
    check (required_quantity >= 0),
  constraint project_material_demands_overrun_check
    check (projected_overrun_quantity >= 0)
);

create unique index project_material_demands_active_key
on public.project_material_demands(company_id, demand_key)
where deleted_at is null;

create index project_material_demands_project_status_idx
on public.project_material_demands(company_id, project_id, status)
where deleted_at is null;

create index project_material_demands_task_status_idx
on public.project_material_demands(company_id, task_id, status)
where deleted_at is null;

create index project_material_demands_variant_status_idx
on public.project_material_demands(company_id, catalog_variant_id, status)
where deleted_at is null;
```

### `project_material_snapshots`

```sql
create table public.project_material_snapshots (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  project_id uuid not null references public.projects(id) on delete cascade,
  task_id uuid references public.project_tasks(id) on delete set null,
  estimate_id uuid references public.estimates(id) on delete set null,
  snapshot_kind text not null,
  created_by uuid,
  notes text,
  payload jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  constraint project_material_snapshots_kind_check
    check (snapshot_kind in (
      'booking_projection',
      'inventory_mode_released',
      'crew_adjustment',
      'task_completion_consumption',
      'release'
    ))
);

create index project_material_snapshots_project_idx
on public.project_material_snapshots(company_id, project_id, created_at desc);

create index project_material_snapshots_task_idx
on public.project_material_snapshots(company_id, task_id, created_at desc);
```

### `project_material_snapshot_items`

```sql
create table public.project_material_snapshot_items (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  snapshot_id uuid not null references public.project_material_snapshots(id) on delete cascade,
  demand_id uuid references public.project_material_demands(id) on delete set null,
  task_material_id uuid references public.task_materials(id) on delete set null,
  inventory_deduction_id uuid references public.inventory_deductions(id) on delete set null,
  catalog_variant_id uuid references public.catalog_variants(id) on delete set null,
  catalog_stock_unit_id uuid references public.catalog_stock_units(id) on delete set null,
  unit_id uuid references public.catalog_units(id) on delete set null,
  quantity numeric not null default 0,
  projected_overrun_quantity numeric not null default 0,
  stock_unit_snapshot jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  constraint project_material_snapshot_items_quantity_check
    check (quantity >= 0),
  constraint project_material_snapshot_items_overrun_check
    check (projected_overrun_quantity >= 0)
);

create index project_material_snapshot_items_snapshot_idx
on public.project_material_snapshot_items(company_id, snapshot_id);

create index project_material_snapshot_items_demand_idx
on public.project_material_snapshot_items(company_id, demand_id);

create index project_material_snapshot_items_stock_unit_idx
on public.project_material_snapshot_items(company_id, catalog_stock_unit_id);
```

### `task_material_allocations`

```sql
create table public.task_material_allocations (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  task_material_id uuid references public.task_materials(id) on delete set null,
  demand_id uuid references public.project_material_demands(id) on delete set null,
  catalog_variant_id uuid references public.catalog_variants(id) on delete set null,
  catalog_stock_unit_id uuid references public.catalog_stock_units(id) on delete set null,
  allocation_key text not null,
  allocation_status text not null default 'projected',
  allocated_quantity numeric not null default 0,
  consumed_quantity numeric not null default 0,
  overrun_quantity numeric not null default 0,
  stock_unit_snapshot jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  constraint task_material_allocations_status_check
    check (allocation_status in ('projected', 'overrun', 'consumed', 'released', 'superseded')),
  constraint task_material_allocations_allocated_quantity_check
    check (allocated_quantity >= 0),
  constraint task_material_allocations_consumed_quantity_check
    check (consumed_quantity >= 0),
  constraint task_material_allocations_overrun_quantity_check
    check (overrun_quantity >= 0)
);

create unique index task_material_allocations_active_key
on public.task_material_allocations(company_id, allocation_key)
where deleted_at is null;

create index task_material_allocations_task_material_idx
on public.task_material_allocations(company_id, task_material_id)
where deleted_at is null;

create index task_material_allocations_demand_idx
on public.task_material_allocations(company_id, demand_id)
where deleted_at is null;

create index task_material_allocations_stock_unit_idx
on public.task_material_allocations(company_id, catalog_stock_unit_id)
where deleted_at is null;
```

### Notification Resolution Columns

```sql
alter table public.notifications
  add column if not exists dedupe_key text,
  add column if not exists resolved_at timestamptz,
  add column if not exists resolved_by uuid references public.users(id) on delete set null,
  add column if not exists resolution_reason text;

drop index if exists public.idx_notifications_unread_dedup;

create unique index if not exists notifications_unread_title_dedup_without_key
on public.notifications(user_id, company_id, type, title)
where is_read = false
  and dedupe_key is null;

create unique index if not exists notifications_open_dedupe_key
on public.notifications(user_id, company_id, type, dedupe_key)
where is_read = false
  and resolved_at is null
  and dedupe_key is not null;

create index if not exists notifications_company_type_dedupe_idx
on public.notifications(company_id, type, dedupe_key)
where resolved_at is null
  and dedupe_key is not null;
```

Notification type proposal:
- `catalog_mapping_needed`

Deep link proposal:
- `catalogSetup`

Action label:
- `FIX MAPPING`

Action URL pattern:
- `ops://catalog/setup?missingMapping=<encoded-key>`

Live SQL audit correction:
- Production already has `idx_notifications_unread_dedup` on `(user_id, company_id, type, title)` for unread rows. Keyed mapping notifications can share one title while representing different mapping gaps, so the Phase 6 migration must replace that index with title-only dedupe for rows where `dedupe_key is null` and key-specific dedupe for rows where `dedupe_key is not null`.
- `resolved_by` must reference `public.users(id)` and the resolving actor must be derived server-side.

## RLS Requirements

Every new table must have RLS enabled.

Company isolation rule:
- Rows are visible only when `company_id = private.get_user_company_id()`.
- Inserts/updates must use the same company guard.

Same-company FK guard:
- For snapshot/allocation rows, referenced project/task/demand/variant/stock-unit rows must belong to the same company.
- Match the stricter `catalog_stock_unit_events` pattern rather than relying only on plain FKs.

RPC guard:
- Server functions must verify the caller's company before writing.
- Prefer `SECURITY INVOKER`.
- If elevated execution is required for an atomic workflow, explicitly validate `private.get_user_company_id()` and do not grant broader data access.
- SQL functions must not accept a client-supplied actor for audit or permission decisions. Derive the actor inside the function with `private.get_current_user_id()` and use that server-derived value for audit columns.
- `company_inventory_settings` writes must be permission-gated through `public.set_company_inventory_mode` or direct table writes must be revoked/restricted with equivalent `catalog.manage` checks before migration approval.
- Projected-demand, snapshot, and allocation writes must pass `ops.project_material_workflow` plus `private.current_user_can_write_project_material_workflow(company_id)`.
- That material-workflow authorization has only two write paths: inventory-mode release through `ops.company_inventory_settings_rpc` plus `catalog.manage`, or estimate acceptance through `ops.accept_estimate_to_job_rpc` plus same-company and acceptance-adjacent permissions.
- Direct ad hoc writes to projected-demand, snapshot, and allocation tables remain blocked by RLS and trigger guards.

## Proposed Functions

### `public.set_company_inventory_mode`

Purpose:
- Toggle explicit inventory tracking mode.
- Release open projected demand when switching from `tracked` to `off`.
- Preserve all history.

Signature:

```sql
public.set_company_inventory_mode(
  p_company_id uuid,
  p_inventory_mode text
) returns jsonb
```

Required behavior:
- Reject mode values outside `off` and `tracked`.
- Verify caller company.
- Verify caller has existing `catalog.manage` permission.
- Derive `updated_by` from `private.get_current_user_id()` before writing.
- Upsert `company_inventory_settings`.
- When turning `off`, update only open `project_material_demands` to `released`.
- When turning `off`, write `project_material_snapshots.snapshot_kind = 'inventory_mode_released'`.
- Do not delete `inventory_deductions`, `catalog_stock_unit_events`, snapshots, or consumed demand.

### `public.accept_estimate_to_job`

Purpose:
- Replace client-side estimate status-only approval with one server-authoritative transaction.

Signature:

```sql
public.accept_estimate_to_job(
  p_estimate_id uuid,
  p_idempotency_key text
) returns jsonb
```

Required behavior:
- Verify caller company.
- Derive actor server-side with `private.get_current_user_id()`.
- Verify estimate belongs to company.
- Mark estimate approved.
- Convert/update lead-backed project inside this transaction.
- Reuse/refactor existing `convert_lead_to_project` logic as a private/protected helper. Do not orchestrate project/task/material writes from the iOS client.
- Verify or create required project tasks from accepted estimate lines.
- Read `company_inventory_settings.inventory_mode`.
- If mode is `off`, skip all material demand behavior and return `inventory_mode = 'off'`.
- If mode is `tracked`, resolve accepted line item materials.
- Suggested add-ons affect job materials only if accepted into estimate lines.
- Missing product-to-stock mappings create warnings, not blockers.
- Insert/upsert projected demand rows.
- Compare demand to currently available stock-unit totals.
- Create overrun allocation rows where demand exceeds available stock.
- Write booking snapshot rows.
- Create/update persistent missing-mapping notifications.
- Return structured `warnings`, `overruns`, `missing_mappings`, `project_id`, `task_ids`, and `demand_ids`.

### `private.sync_accepted_estimate_project_tasks`

Purpose:
- Provide the protected project/task sync layer needed by the P6-6 public acceptance RPC without exposing incomplete estimate acceptance from P6-3 alone.

Draft migration:
- `migrations/2026-05-27-03-ios-catalog-p6-estimate-acceptance-task-sync.sql`

Contract:
- Private helper only; no public RPC is exposed by the P6-3 migration.
- Execute grant is for `authenticated`. Live permission helpers used by this function require an authenticated actor, so the public wrapper must remain caller-scoped and call this helper as that actor.
- Derives the actor server-side with `private.get_current_user_id()` and `auth.uid()`.
- Verifies actor company against `private.get_user_company_id()`.
- Requires live acceptance-adjacent permissions: `estimates.edit`, `projects.create`, `projects.edit`, `tasks.create`, and `pipeline.manage`.
- Does not use `catalog.manage`; that permission remains reserved for inventory-mode management and missing-mapping notification recipients.
- Requires an opportunity-backed estimate.
- Creates or reuses the existing opportunity-backed project.
- Links the accepted estimate to `projects.id` through `estimates.project_id` and `estimates.project_ref`.
- Marks eligible estimates approved while preserving `converted` status for repeat syncs after invoice conversion.
- Moves the opportunity to `won` only once and writes one stage transition only when the stage changes.
- Creates or verifies one non-deleted `project_tasks` row per selected LABOR line item using deterministic `source_estimate_id` + `source_line_item_id` keys.
- Links site visits to the project and attaches site-visit photos idempotently.
- Inserts attached `project_photos.uploaded_by` as the accepting actor (`private.get_current_user_id()`), not the original `site_visits.created_by`, because live `project_photos` INSERT RLS requires `uploaded_by` to equal the current authenticated user.
- Does not compute projected demand, allocations, snapshots, missing-mapping notifications, or stock movement.

Public RPC gate:
- `public.accept_estimate_to_job` is exposed only by the P6-6 draft, where this helper and tracked-inventory material demand run in the same transaction.

### `private.resolve_estimate_material_demand_plan`

Purpose:
- Provide the side-effect-free material-demand plan needed before booking can persist warnings and projected demand.

Draft migration:
- `migrations/2026-05-27-04-ios-catalog-p6-material-demand-engine.sql`

Contract:
- Private helper only; no public RPC is exposed by the P6-4 migration.
- Execute grants are for `authenticated`, not `service_role` alone, so the future `SECURITY INVOKER` acceptance transaction can call the resolver chain while preserving authenticated-user company scope.
- Requires the P6-2 inventory-mode foundation before tracked demand can run.
- Returns `inventory_mode = 'off'` with no demand when company tracking is off.
- For tracked companies, resolves selected estimate lines into JSONB `demands`, `warnings`, `missing_mappings`, and `overruns`.
- Missing product-to-stock mappings and projected overruns are warnings, not blockers.
- Does not insert projected demand, allocations, snapshots, notifications, stock-unit events, or physical stock changes.

### `private.persist_estimate_material_booking_projection`

Purpose:
- Persist booking warnings and projected-demand rows from the P6-4 JSONB plan inside the public estimate-acceptance transaction.

Draft migration:
- `migrations/2026-05-27-05-ios-catalog-p6-booking-warnings.sql`

Contract:
- Private helper only; no public RPC is exposed by the P6-5 migration.
- Execute grant is for `authenticated`. The helper must run inside `public.accept_estimate_to_job`, under the same authenticated transaction as P6-3/P6-4.
- Derives the actor server-side and requires the acceptance RPC guard plus same-company and acceptance-adjacent permission checks for material-planning writes.
- Calls `private.resolve_estimate_material_demand_plan(p_estimate_id, p_project_id)`.
- Uses P6-2's `ops.project_material_workflow` guard before writing projected-demand tables.
- If inventory mode is `off`, releases open projected/warning rows for the same estimate/project and creates no booked-job material rows.
- If inventory mode is `tracked`, upserts `project_material_demands` idempotently by `demand_key` without regressing existing `allocated` or `consumed` demand rows back to `projected` or `warning`.
- Marks stale projected/warning rows for the same estimate/project as `superseded` so repeat booking does not leave duplicate active warnings.
- Writes `project_material_snapshots.snapshot_kind = 'booking_projection'` and snapshot items for durable booking-warning evidence.
- Creates `task_material_allocations` only for projected overruns, with `allocation_status = 'overrun'`, no stock-unit link, no deduction link, and no stock balance mutation.
- On repeated booking projection after consumption, consumed overrun allocation rows preserve their consumed status, deduction link, quantities, stock-unit link, and snapshot instead of being rewritten as projection-only overrun rows.
- Persists overruns in demand warning metadata and overrun allocation rows, not blockers.
- Does not create persistent setup notifications directly; P6-6 creates them inside `public.accept_estimate_to_job` from this helper's returned `missing_mappings` array only.
- Missing-mapping notifications are persistent, keyed by `dedupe_key`, deduped by the notification unique index, and routed only to `catalog.manage` recipients.

Public RPC gate:
- `public.accept_estimate_to_job` is exposed only by the P6-6 draft after the project/task sync helper, booking projection helper, and notification contract run in one reviewed transaction.

### `public.complete_project_task` + `private.consume_task_materials_for_completed_task`

Purpose:
- Complete a task and consume tracked stock in one server transaction.

Signature:

```sql
public.complete_project_task(
  p_task_id uuid,
  p_idempotency_key text,
  p_material_adjustments jsonb default '{}'::jsonb
) returns jsonb

private.consume_task_materials_for_completed_task(
  p_task_id uuid,
  p_idempotency_key text,
  p_material_adjustments jsonb default '{}'::jsonb
) returns jsonb
```

Required behavior:
- Verify caller company.
- Derive actor server-side with `private.get_current_user_id()`.
- Verify task/project belongs to company.
- Complete `project_tasks.status` inside the public RPC before the private material helper runs.
- Treat absent or `off` company inventory mode as a no-op for stock movement.
- Use `task_material_consumption_requests` to idempotently prevent duplicate stock deduction for the same task.
- Convert projected allocations into consumed allocations.
- Apply crew adjustments.
- Write `inventory_deductions`.
- Write `catalog_stock_unit_events` with `event_type = 'consume'` or other exact event types already allowed by live constraints.
- Update `catalog_stock_units.remaining_length_value` or `quantity_value` without allowing physical stock unit values below zero.
- Represent shortage as overrun allocation, not negative stock-unit quantity.
- Write `project_material_snapshots.snapshot_kind = 'task_completion_consumption'`.
- Return consumed quantities, remaining stock, and overrun quantities.

### Applied P6-23 Mapping Notification Trigger Resolvers

Purpose:
- Resolve persistent setup notifications automatically when saved product links or product-option mappings close the exact keyed mapping gap.

Applied objects:
- `private.resolve_catalog_mapping_needed_notifications_for_product_link()` runs from `trg_products_resolve_catalog_mapping_notifications` after `public.products` insert/update.
- `private.resolve_catalog_mapping_needed_notifications_for_mapping()` runs from `trg_catalog_product_option_mappings_resolve_notifications` after `public.catalog_product_option_mappings` insert/update.

Required behavior:
- No public follow-on RPC. Any product save path or product-option mapping save path that writes the closing row triggers resolution.
- Verify the row company against `private.get_user_company_id()`.
- Derive the actor server-side with `private.get_current_user_id()`.
- Product links resolve only `catalog_mapping_needed:product:<product_id>:linked_catalog_item`.
- Axis mappings resolve only `catalog_mapping_needed:product:<product_id>:catalog_item:<catalog_item_id>:option:<product_option_id>`.
- Value mappings resolve only `catalog_mapping_needed:product:<product_id>:catalog_item:<catalog_item_id>:option:<product_option_id>:value:<product_option_value_id>`.
- Stamp `resolved_at`, `resolved_by`, `resolution_reason`, and `is_read = true`.
- Do not resolve unrelated notification types, companies, or `dedupe_key` rows.

## Implementation Sequence

### Task 1: Schema Draft And Migration Review Gate

**Files:**
- Create: `/Users/jacksonsweet/Projects/OPS/ops-software-bible/migrations/<timestamp>-ios-catalog-p6-inventory-mode-and-material-demand.sql`
- Modify: `ops-software-bible/10_JOB_LIFECYCLE_AND_DATA_RELATIONSHIPS.md`
- Modify: `ops-software-bible/07_SPECIALIZED_FEATURES.md`
- Modify: `ops-software-bible/05_DESIGN_SYSTEM.md` only if UI copy/state documentation is required.

Steps:
- [ ] Re-run read-only Supabase schema inspection for every table/function named in this spec.
- [ ] Draft migration for `company_inventory_settings`.
- [ ] Draft migration for projected demand, snapshots, snapshot items, and allocations.
- [ ] Draft notification resolution columns/indexes.
- [ ] Draft RLS policies.
- [ ] Draft same-company guard triggers or RPC-local validations.
- [ ] Stop before applying migration.

Gate:
- PM must explicitly approve migration application.

Hard stop:
- Do not apply migration in this task.

### Task 2: Focused Resolver Tests

**Files:**
- Modify: `ops-ios/OPSTests/Catalog/RecipeResolverTests.swift`
- Create: `ops-ios/OPSTests/Catalog/EstimateMaterialDemandResolverTests.swift`
- Modify or create implementation files only after failing tests exist.

Required test cases:
- [ ] Inventory mode `off` returns no projected demand.
- [ ] Inventory mode `tracked` resolves accepted estimate lines into projected demand.
- [ ] Suggested add-ons do not affect materials unless accepted into line items.
- [ ] Missing product-to-stock mappings return soft warning payloads.
- [ ] Demand greater than available stock produces projected overrun.
- [ ] Resolver does not deduct stock.

Gate:
- Run only focused unit tests for the resolver.

Hard stop:
- Do not run broad builds without PM approval.

### Task 3: Acceptance RPC And Repository Boundary

**Files:**
- Create migration function draft for `public.accept_estimate_to_job`.
- Modify later: `ops-ios/OPS/Network/Supabase/Repositories/EstimateRepository.swift`
- Modify later: `ops-ios/OPS/ViewModels/EstimateViewModel.swift`

Required implementation behavior:
- [ ] Replace status-only approval path for accepted estimates with one RPC call.
- [ ] Keep optimistic UI only after RPC contract is clear.
- [ ] Return structured warnings to the view model.
- [ ] Do not perform client-side multi-write project/task/material orchestration.

Gate:
- SQL function reviewed against live RLS.
- Focused repository tests or mocked RPC contract tests pass.

Hard stop:
- Do not mark estimate/job conversion complete until a real runtime gate is approved and run.

### Task 4: Booking Demand, Overrun, And Missing Mapping UI

**Files:**
- Modify later: estimate approval surfaces.
- Modify later: project/task material summary surfaces.
- Modify later: catalog setup/mapping deep-link surface.
- Modify later: `OPS/Views/Catalog/Stock/CatalogSetupFlowSheet.swift`.
- Modify later: `OPS/Views/Settings/InventorySettingsView.swift`.
- Modify later: `OPS/Views/Notifications/NotificationListView.swift`
- Modify later: `OPS/Network/Supabase/DTOs/NotificationDTO.swift` only if new columns need DTO support.

UI rules:
- Show overrun chips only for inventory-tracked companies.
- Do not show booked-job materials for non-inventory companies.
- Missing mappings are soft alerts with click-through fix.
- Expose inventory mode in both Catalog Setup and Company Settings.
- Copy must stay terse and tactical.
- Use OPS design system tokens.

Notification copy:
- Title: `Mapping needed`
- Body pattern: `<product or line name> needs a stock mapping before inventory can track it.`
- Action label: `FIX MAPPING`

Gate:
- Static UI review and focused preview/runtime proof only after PM approval.

### Task 5: Task Completion Consumption

**Files:**
- Modify later: `ops-ios/OPS/Utilities/DataController.swift`
- Modify later: `ops-ios/OPS/Network/Supabase/Repositories/TaskRepository.swift`
- Modify later: `ops-ios/OPS/Views/Components/Project/TaskCompletionChecklistSheet.swift`
- Modify later: `ops-ios/OPS/Views/Components/Project/TaskDetailsView.swift`
- Modify later: `ops-ios/OPS/Views/Components/Project/ProjectDetailsViewModel.swift`
- Modify later: `ops-ios/OPS/Views/Components/Project/ProjectActionBar.swift`

Required behavior:
- [ ] Deduct stock only on task completion.
- [ ] Use one idempotent task-completion RPC for status and consumption.
- [ ] Crew adjustments are recorded in snapshots.
- [ ] Overrun stays visible as overrun, not failed task completion.
- [ ] Do not allow physical stock-unit quantity/length to go negative.

Gate:
- Focused tests prove no deduction before completion and no double deduction.

### Task 6: Notification Resolution

**Files:**
- Modify later: `ops-ios/OPS/Network/Supabase/Repositories/NotificationRepository.swift`
- Modify later: `ops-ios/OPS/Views/Notifications/NotificationListView.swift`
- Modify later: `ops-software-bible/07_SPECIALIZED_FEATURES.md`

Required behavior:
- [ ] Create or update persistent notification for missing mapping.
- [ ] Use `users_with_permission`.
- [ ] Resolve only matching `dedupe_key`.
- [ ] Resolve when catalog setup save/mapping save closes the missing mapping gap.
- [ ] Preserve notification history through `resolved_at`.

Gate:
- Focused notification tests and read-only verification of matching live notification schema.

### Task 7: Verification And Release Gate

Required checks:
- [ ] Focused unit tests for resolver/demand/allocation/notification behavior.
- [ ] SQL smoke tests in transaction/rollback form.
- [ ] `git diff --check`.
- [ ] PM-approved iOS build gate.
- [ ] PM-approved runtime walkthrough gate.
- [ ] PM-approved QA row update gate.

Hard stop:
- Do not mark `qa_bugs.id = a0ead424-8163-411f-96a9-b38486b5e1c6` fixed until runtime proof exists and PM approves the row update.

## iOS Touchpoints For Later Agents

Estimate acceptance:
- `ops-ios/OPS/ViewModels/EstimateViewModel.swift`
- `ops-ios/OPS/Network/Supabase/Repositories/EstimateRepository.swift`

Lead conversion and project/task sync:
- `ops-ios/OPS/Network/Supabase/Repositories/OpportunityRepository.swift`
- `ops-ios/OPS/ViewModels/PipelineViewModel.swift`
- `ops-ios/OPS/Views/Leads/LeadsTabView.swift`
- `ops-ios/OPS/Network/Supabase/Repositories/ProjectRepository.swift`
- `ops-ios/OPS/Network/Supabase/Repositories/TaskRepository.swift`
- `ops-ios/OPS/Network/Supabase/DTOs/CoreEntityDTOs.swift`
- `ops-ios/OPS/Network/Supabase/DTOs/CoreEntityConverters.swift`
- `ops-ios/OPS/DataModels/ProjectTask.swift`

Materials:
- `ops-ios/OPS/Services/RecipeResolver.swift`
- `ops-ios/OPS/Services/CutListMaterializer.swift`
- `ops-ios/OPS/Network/Supabase/Repositories/TaskMaterialRepository.swift`
- `ops-ios/OPS/Network/Supabase/DTOs/TaskMaterialDTOs.swift`
- `ops-ios/OPS/Network/Supabase/DTOs/ProductExtensionDTOs.swift`
- `ops-ios/OPS/Network/Supabase/Repositories/ProductRichnessRepository.swift`

Task completion:
- `ops-ios/OPS/Utilities/DataController.swift`
- `ops-ios/OPS/Network/Supabase/Repositories/TaskRepository.swift`
- `ops-ios/OPS/Views/Components/Project/TaskCompletionChecklistSheet.swift`
- `ops-ios/OPS/Views/Components/Project/TaskDetailsView.swift`
- `ops-ios/OPS/Views/Components/Project/ProjectDetailsViewModel.swift`
- `ops-ios/OPS/Views/Components/Project/ProjectActionBar.swift`

Catalog setup/current inventory:
- `ops-ios/OPS/Network/Supabase/CatalogSchemaCapabilityGate.swift`
- `ops-ios/OPS/Services/CatalogSetupWorkflow.swift`
- `ops-ios/OPS/Network/Supabase/Repositories/CatalogRepository.swift`
- `ops-ios/OPS/Services/CatalogStockUnitAggregator.swift`
- `ops-ios/OPS/Network/Supabase/Repositories/CatalogStockUnitRepository.swift`
- `ops-ios/OPS/Network/Supabase/Repositories/CatalogProductOptionMappingRepository.swift`
- `ops-ios/OPS/Views/Catalog/Stock/CatalogSetupFlowSheet.swift`

Notifications:
- `ops-ios/OPS/Network/Supabase/Repositories/NotificationRepository.swift`
- `ops-ios/OPS/Network/Supabase/DTOs/NotificationDTO.swift`
- `ops-ios/OPS/Views/Notifications/NotificationListView.swift`
- `ops-ios/OPS/Utilities/NotificationManager.swift`

## Test Plan

Focused tests first:
- Resolver unit tests.
- Demand aggregation tests.
- Inventory-mode branching tests.
- Stock availability/overrun tests.
- Missing mapping warning tests.
- Notification dedupe/resolution tests.
- Task completion idempotency tests.
- No deduction before completion test.
- No double deduction test.

SQL tests:
- Use transaction/rollback smoke tests.
- Verify RLS company isolation.
- Verify same-company FK guards.
- Verify `accept_estimate_to_job` idempotency.
- Verify `complete_project_task` and `consume_task_materials_for_completed_task` idempotency.
- Verify inventory mode `off` skips demand.
- Verify turning inventory mode off releases open demand without deleting history.

Build/runtime gates:
- Do not run broad build until PM approval.
- Do not run simulator/runtime walkthrough until PM approval.
- Do not mark QA fixed until runtime walkthrough proves behavior.

## Closed PM Decisions

1. Inventory-mode management uses existing `catalog.manage`. Do not add a new permission unless a fresh live permission audit proves `catalog.manage` cannot cover this control.
2. `public.accept_estimate_to_job` owns the full estimate-acceptance transaction. Reuse/refactor existing lead-to-project logic as a private/protected helper; do not perform client-side multi-write project/task/material orchestration.
3. Missing mapping notifications route to Catalog Setup with a key-specific action URL: `ops://catalog/setup?missingMapping=<encoded-key>`.
4. Inventory mode is exposed in both Catalog Setup and Company Settings.
5. Turning inventory mode `off` is allowed after consumption. Preserve all history and release only open projected demand; do not delete stock-unit events, actual deductions, snapshots, or consumed demand.

## Recommendation

Phase 6 should ship the explicit inventory-mode foundation first. Without it, every downstream estimate-to-job material behavior is forced to guess whether a company actually wants inventory tracking. That guess is unsafe.

The correct implementation boundary is:
- Company inventory mode decides whether estimate acceptance performs material demand work.
- Booking writes projected demand, allocation warnings, and snapshots.
- Completion writes stock deduction, stock-unit events, final snapshots, and history.
- Missing mappings never block acceptance; they create persistent, resolvable setup notifications.
