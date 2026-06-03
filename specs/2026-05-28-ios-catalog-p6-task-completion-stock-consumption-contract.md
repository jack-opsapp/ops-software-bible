# iOS Catalog P6-20 Task-Completion Stock Consumption Contract

Date: 2026-05-28
Scope: schema and backend contract only. No iOS task-completion write behavior is changed by this spec.

## Decision

Stock consumption belongs inside a public task-completion RPC, not in a separate public consumption RPC.

Chosen contract:

- Public boundary: `public.complete_project_task(p_task_id uuid, p_idempotency_key text, p_material_adjustments jsonb default '{}'::jsonb)`
- Private material helper: `private.consume_task_materials_for_completed_task(p_task_id uuid, p_idempotency_key text, p_material_adjustments jsonb default '{}'::jsonb)`
- Idempotency ledger: `public.task_material_consumption_requests`

Reason:

The current iOS path marks a task complete locally, records a queued `project_tasks.status` update, and lets outbound sync patch Supabase later. Adding a separate public stock-consumption RPC would create a two-write client contract: task status could sync while stock consumption fails, or stock consumption could run against a stale task status. The correct boundary is one server transaction that completes the task and consumes tracked inventory together. The private helper exists so the material-consumption logic remains reusable and guarded, but it only runs under the task-completion RPC guard.

## Live iOS Audit

Audited paths:

- `ops-ios/OPS/Utilities/DataController.swift`
- `ops-ios/OPS/Views/Components/Project/ProjectDetailsViewModel.swift`
- `ops-ios/OPS/Views/Components/Project/ProjectDetailsView.swift`
- `ops-ios/OPS/Views/Components/Project/ProjectActionBar.swift`
- `ops-ios/OPS/Views/Components/Project/TaskCompletionChecklistSheet.swift`
- `ops-ios/OPS/Views/Components/Project/TaskDetailsView.swift`
- `ops-ios/OPS/Views/Review/TaskCompletionReviewView.swift`
- `ops-ios/OPS/Views/Review/UnscheduledTaskReviewView.swift`
- `ops-ios/OPS/Network/Sync/OutboundProcessor.swift`
- `ops-ios/OPS/Network/Supabase/Repositories/TaskRepository.swift`
- `ops-ios/OPS/Network/Supabase/DTOs/CoreEntityDTOs.swift`
- `ops-ios/OPS/Network/Supabase/DTOs/CoreEntityConverters.swift`

Findings:

- `DataController.updateTaskStatus(task:to:)` is the central task status mutation path.
- Completion call sites route through `updateTaskStatus`, including project details, active-task quick action, task detail status picker, task checklist completion, scheduled task review, and unscheduled task review.
- `updateTaskStatus` currently mutates SwiftData, marks `needsSync`, records a `.projectTask` `SyncOperation` with only `["status": newStatus.rawValue]`, then sends analytics and completion notifications.
- `OutboundProcessor.handleProjectTask` sanitizes project-task payloads to direct `project_tasks` fields and then calls `TaskRepository.updateFields`.
- `TaskRepository.updateStatus` and `updateFields` update `public.project_tasks` directly through PostgREST. No completion RPC is called today.
- iOS DTOs do not carry `project_tasks.inventory_deducted`, the outbound column allowlist does not include it, and future iOS paths must not read it for material-consumption state.
- No iOS behavior change is authorized in this task.

## Live Supabase Evidence

Read-only inspection was run against Supabase project `ijeekuhbatykdomumfjx` (`ops-app`), Postgres `17.6.1.063`.

Tables confirmed live and RLS-enabled:

- `project_tasks`
- `project_material_demands`
- `task_material_allocations`
- `project_material_snapshots`
- `project_material_snapshot_items`
- `catalog_stock_units`
- `catalog_stock_unit_events`
- `inventory_deductions`
- `task_materials`
- `company_inventory_settings`

Relevant live columns and constraints:

- `project_tasks.status` is checked to `active`, `completed`, or `cancelled`; `project_tasks.inventory_deducted boolean not null default false` exists live but is not an adequate idempotency ledger.
- `company_inventory_settings.inventory_mode` is checked to `off` or `tracked`; the primary key is `company_id`.
- `project_material_demands.status` supports `projected`, `warning`, `allocated`, `consumed`, `released`, and `superseded`.
- `task_material_allocations.allocation_status` supports `projected`, `overrun`, `consumed`, `released`, and `superseded`.
- `task_material_allocations` already stores `catalog_stock_unit_id`, `consumed_quantity`, `overrun_quantity`, `inventory_deduction_id`, and `stock_unit_snapshot`.
- `project_material_snapshots` uses `snapshot_kind`; `task_completion_consumption` is already an allowed snapshot kind.
- `project_material_snapshot_items` already stores `snapshot_id`, `allocation_id`, `catalog_stock_unit_id`, `inventory_deduction_id`, `source_event_id`, `quantity`, `projected_overrun_quantity`, and `stock_unit_snapshot`.
- `catalog_stock_units` enforces nonnegative `quantity_value` and nonnegative `remaining_length_value`.
- `catalog_stock_unit_events` uses `catalog_stock_unit_id`, requires `catalog_variant_id`, and `event_type` allows `consume`.
- `inventory_deductions` uses `quantity_deducted`, `previous_quantity`, `new_quantity`, and `catalog_variant_id`; `reason` allows `task_completion`.
- `project_tasks.inventory_deducted boolean not null default false` is live only as a deprecated compatibility flag. It does not identify the request, allocation, stock-unit snapshot, overrun, or replay response, so it is not authoritative.

Relevant live functions:

- `public.accept_estimate_to_job(p_estimate_id uuid, p_idempotency_key text)` exists and is caller-scoped.
- `private.persist_estimate_material_booking_projection(p_estimate_id uuid, p_project_id uuid)` exists and writes projected demand only.
- `private.resolve_estimate_material_demand_plan(p_estimate_id uuid, p_project_id uuid)` exists and is read-only planning logic.
- `private.sync_accepted_estimate_project_tasks(p_estimate_id uuid)` exists and handles accepted-estimate project/task sync.
- Read-only source search of live function bodies showed zero references to `inventory_deductions`, `catalog_stock_units`, or `catalog_stock_unit_events` in `accept_estimate_to_job`, `sync_accepted_estimate_project_tasks`, `resolve_estimate_material_demand_plan`, and `persist_estimate_material_booking_projection`.

QA row check:

- `qa_bugs.id = a0ead424-8163-411f-96a9-b38486b5e1c6`
- `status = new`
- `verified = false`
- `fixed_at = null`
- `verified_at = null`

## Contract

### Public Task Completion RPC

`public.complete_project_task` owns the task status transition and stock-consumption transaction.

Required behavior:

- Derive actor server-side through `private.get_current_user_id()`.
- Derive company server-side through `private.get_user_company_id()`.
- Lock the `project_tasks` row for update.
- Verify same-company task ownership.
- Verify the caller can edit the task using the same task-edit scope model as `project_tasks` RLS.
- Set `project_tasks.status = 'completed'` only inside this transaction.
- Set `ops.complete_project_task_rpc = on` and `ops.project_material_workflow = on` for the transaction.
- Call `private.consume_task_materials_for_completed_task`.
- Return task status change, consumption result, consumed quantity, overrun quantity, request id, snapshot id, stock event ids, and deduction ids.

### Private Consumption Helper

`private.consume_task_materials_for_completed_task` owns material movement after the task is completed in the same transaction.

Required behavior:

- Reject calls unless the task is already locked and completed.
- Reject calls unless `ops.complete_project_task_rpc = on`.
- Use `task_material_consumption_requests` to guarantee one completed consumption request per `(company_id, task_id)`.
- Also enforce `(company_id, idempotency_key)` uniqueness and reject same key with different request hash.
- If `company_inventory_settings.inventory_mode` is absent or `off`, complete the request as a no-op and write no stock, allocation, demand, snapshot, event, or deduction rows.
- If mode is `tracked`, derive consumable work from active `project_material_demands` rows for the completed task, not from pre-existing allocation rows. Eligible demand statuses are `projected`, `warning`, and `allocated`.
- Resolve stock at completion from live `catalog_stock_units` by demand `catalog_variant_id` and company. Use only current non-deleted stock units with `status in ('full', 'partial')` and positive current `remaining_length_value` or `quantity_value`; do not trust booking-time `available_quantity_at_booking`.
- Deduct one demand across one or more stock units when the first stock unit cannot cover the requested quantity.
- Accept `p_material_adjustments` as a JSON object. Each value may provide `consumed_quantity` or `final_quantity`.
- Adjustment keys are accepted in this priority order:
  - `project_material_demands.demand_key`
  - raw `project_material_demands.id`
  - `demand:<project_material_demands.id>`
  - `demand_key:<project_material_demands.demand_key>`
  - existing `task_material_allocations.allocation_key`
  - raw `task_material_allocations.id`
  - `allocation:<task_material_allocations.id>`
- Convert each demand into final allocation evidence:
  - Physical stock movement rows use deterministic allocation keys: `<demand_key>:stock_unit:<catalog_stock_unit_id>`.
  - Unavailable or uncovered remainder uses `<demand_key>:overrun`, updating the booking-created overrun allocation when one exists.
  - `consumed_quantity` is the physical quantity actually removed from a stock unit.
  - `overrun_quantity` is the required quantity not covered by available stock.
  - `stock_unit_snapshot` records the before/after stock-unit state, requested quantity, consumed quantity, overrun quantity, shortfall quantity, deduction id, and stock event id.
- Missing stock, soft-deleted stock, exhausted stock, non-consumable stock status, and unmapped `catalog_variant_id` are not task-completion blockers. They produce zero physical consumption for the unavailable portion, preserve that portion as `overrun_quantity`, and record `stock_unit_available = false` plus `stock_unit_unavailable_reason` in both `task_material_allocations.stock_unit_snapshot` and `project_material_snapshot_items.stock_unit_snapshot`.
- Unavailable evidence leaves `project_material_snapshot_items.catalog_stock_unit_id` null because no live physical stock unit was consumed.
- Insert `inventory_deductions` only when `consumed_quantity > 0`.
- Insert `catalog_stock_unit_events` with `event_type = 'consume'` only when physical stock moved.
- Update `catalog_stock_units.quantity_value` or `remaining_length_value` with `greatest(..., 0)` semantics; physical values never go negative.
- Write `project_material_snapshots.snapshot_kind = 'task_completion_consumption'`.
- Write one `project_material_snapshot_items` row per allocation, preserving stock-unit snapshot JSON.
- Mark touched `project_material_demands` as `consumed` from per-demand aggregation in the same transaction. Completion quantity and overrun fields must be summed from snapshot items grouped by `demand_id`, never from whole-task totals.
- Return the same response on repeated task completion or idempotent request replay without a second deduction.

## Idempotency Strategy

Idempotency has two layers:

1. Request key idempotency: `(company_id, idempotency_key)` stores the request hash and response. Same key plus same payload returns the stored response; same key plus different payload raises `idempotency_conflict`.
2. Task idempotency: `(company_id, task_id)` is unique in `task_material_consumption_requests`. A task can have at most one completed stock-consumption result. Repeated task completion with a new idempotency key returns the original task consumption response.

`project_tasks.inventory_deducted` is explicitly deprecated and non-authoritative. Future iOS paths must not read it for task-completion material state, idempotency, or UI confirmation. The authoritative contract is `task_material_consumption_requests` for replay/idempotency plus `task_material_allocations` and `project_material_snapshot_items` for per-demand and per-stock-unit evidence.

The draft migration records this in a database column comment and does not set the flag as a compatibility marker. Setting it would collapse "tracked request completed," "physical stock moved," "all demand covered," and "overrun/unavailable evidence recorded" into one ambiguous boolean.

Deterministic allocation keys make the helper replay-safe inside the request transaction: a consumed stock-unit evidence row is keyed by demand plus stock unit, and unavailable evidence reuses the booking overrun key. The request ledger still remains the primary double-deduction guard; repeated completion for the same task returns the original response before any allocation, deduction, event, or stock-unit update can run again.

## Auth And RLS Strategy

- Functions are caller-scoped and rely on existing RLS.
- No client-supplied user id is accepted.
- The public boundary grants execute only to `authenticated`.
- The private helper stays invoker-scoped and transaction-guarded; direct calls without `ops.complete_project_task_rpc = on` are rejected. Definer-rights functions are intentionally not used.
- The request ledger has RLS enabled, select is same-company only, and writes require `private.current_user_can_complete_task_material_consumption`.
- Material workflow RLS is extended only for the transaction-local `ops.complete_project_task_rpc` guard.
- No catalog management permission is required to complete a task. `catalog.manage` remains the inventory-mode management permission.
- Non-inventory companies do not get stock-consumption writes.

## Non-Goals For This Task

- No iOS implementation of `public.complete_project_task`.
- No outbound sync changes.
- No stock deduction at estimate acceptance, booking, or project acceptance.
- No QA status changes.

## Applied Artifact

SQL migration:

- `migrations/2026-05-28-02-ios-catalog-p6-task-completion-consumption-contract.sql`

Applied to `ops-app` as migration `2026_05_28_02_ios_catalog_p6_task_completion_consumption_contract` (version `20260529062017`). Rollback-only SQL smoke `OPS_P6_TASK_COMPLETION_SMOKE_20260529T064613Z` verified the request ledger, RLS path, off-mode no-op, tracked-mode stock consumption, multi-unit consumption, shortfall evidence, and idempotent replay with zero marker residue after rollback.
