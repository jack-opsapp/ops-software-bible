# Task Groups Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use `custom-skills:executing-plans` to implement this plan task-by-task.

**Goal:** A task can carry multiple scopes (one visit, many scopes) — created in one pass, checked off individually or completed in one tap, split off when reality slips — identically on iOS, web, and the server composition path.

**Architecture:** New `task_scopes` child table under `project_tasks` (additive-only). `project_tasks.task_type_id` remains the primary scope's type so every legacy surface keeps working. The status law (task completed ⇔ scopes stamped) is enforced in Postgres by trigger + one RPC, never per-client. One deterministic server-side composition function partitions candidate scopes into visits; web preview, estimate conversion RPCs, and (later) the agent all call it.

**Tech Stack:** Postgres/Supabase (plpgsql, RLS), iOS Swift/SwiftUI/SwiftData (schema V26), Next.js 15 + TanStack Query, vitest / XCTest.

**Design System:** iOS: `ops-ios/OPS/Styles/OPSStyle.swift` tokens + `ops-design-system/project/mobile/MOBILE.md`. Web: project Tailwind tokens per `ops-design-system/project/DESIGN.md`. Zero hardcoded values.

**Required Skills:** `ops-design`, `custom-skills:mobile-ux-design` (P3), `frontend-design:frontend-design` + `custom-skills:interface-design` (P4), `ops-copywriter:ops-copywriter` (all user-facing copy), `animation-studio:animation-architect` → `ios-animations`/`web-animations` (scope-check + COMPLETE ALL motion), `custom-skills:audit-design-system` (before any UI phase is called done), `superpowers:verification-before-completion`.

**Spec:** `ops-software-bible/specs/2026-09-01-task-groups-design.md` (bible `98d7a44`). Read it first, fully.

**Ground rules (non-negotiable):**
- Additive-only schema; shipped iOS builds must keep working (`ops-software-bible/03_DATA_ARCHITECTURE.md`).
- iOS ids lowercase at generation. Web writes destructure `{ error }` (PGRST204). CRLF preserved in Swift files.
- iOS builds: workers code+commit only — the bug-reports PM batches builds (`feedback_only_bug_reports_pm_builds`). Verification via `xcodebuild build-for-testing` + targeted `test` in a worktree with `.spm-local` + copied `Secrets.xcconfig`.
- Any `@Model` edit → run `AppUpdateMigrationTests` + `SiteVisitMigrationTests`.
- Prod is low-tenant: migrations apply direct to prod via Supabase MCP `apply_migration`, mirrored into `ops-software-bible/migrations/` per that archive's README in the same session.
- Commits: conventional, atomic, no AI attribution. Spawned sessions: `TASK GROUPS - P<phase>-<n>`.

---

## Phase 1 — Database + composition brain (server truth first)

### Task 1: `task_scopes` table, RLS, guards, revision triggers

**Files:**
- Apply via MCP `apply_migration`, name `task_scopes_table`
- Mirror: `ops-software-bible/migrations/<timestamp>_task_scopes_table.sql`

**Step 1 — write + apply the migration (one statement batch):**

```sql
create table public.task_scopes (
  id uuid primary key,
  company_id uuid not null,
  task_id uuid not null references public.project_tasks(id) on delete cascade,
  task_type_id uuid not null references public.task_types(id),
  note text,
  display_order integer not null default 0,
  completed_at timestamptz,
  completed_by uuid,
  source_line_item_id text,
  split_to_task_id uuid references public.project_tasks(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);
create index task_scopes_task_id_idx on public.task_scopes(task_id) where deleted_at is null;
create index task_scopes_company_id_idx on public.task_scopes(company_id);

alter table public.task_scopes enable row level security;

-- Read: visible iff the parent task is visible (mirrors project_tasks role_scope_read).
create policy scope_read on public.task_scopes for select using (
  exists (select 1 from public.project_tasks t where t.id = task_scopes.task_id
    and private.current_user_can_view_task_row(t.company_id, t.project_id, t.team_member_ids, t.deleted_at))
);
-- Writes: company isolation + the parent task's edit rule (admin OR tasks.edit scope-aware).
create policy scope_write on public.task_scopes for all using (
  company_id = (select private.get_user_company_id())
  and exists (select 1 from public.project_tasks t where t.id = task_scopes.task_id
    and t.deleted_at is null
    and (private.current_user_is_admin() or
      case private.current_user_scope_for('tasks.edit')
        when 'all' then true
        when 'assigned' then ((private.get_current_user_id())::text = any(coalesce(t.team_member_ids, array[]::text[]))
                              or private.current_user_in_project(t.project_id))
        else false end))
) with check (
  company_id = (select private.get_user_company_id())
);

-- Guards: parent task alive + same company; type same company + not deleted (mirrors
-- private.guard_project_task_task_type_reference).
create or replace function private.guard_task_scope_refs() returns trigger
language plpgsql security definer set search_path to 'public','private','pg_temp' as $$
declare v_task public.project_tasks%rowtype;
begin
  select * into v_task from public.project_tasks where id = new.task_id;
  if not found or v_task.deleted_at is not null then
    raise exception 'scope_parent_task_missing' using errcode = '23503';
  end if;
  if v_task.company_id <> new.company_id then
    raise exception 'scope_company_mismatch' using errcode = '42501';
  end if;
  if not exists (select 1 from public.task_types tt where tt.id = new.task_type_id
                 and tt.company_id = new.company_id and tt.deleted_at is null) then
    raise exception 'scope_task_type_invalid' using errcode = '23503';
  end if;
  return new;
end $$;
create trigger task_scopes_guard_refs before insert or update of task_id, task_type_id, company_id
  on public.task_scopes for each row execute function private.guard_task_scope_refs();

create trigger update_task_scopes_timestamp before update on public.task_scopes
  for each row execute function update_timestamp();
-- Agent read-domain freshness (same as project_tasks):
create trigger task_scopes_bump_agent_task_revision after insert or delete or update
  on public.task_scopes for each row
  execute function private.bump_agent_read_domain_revision('tasks', 'company_id');
```

**Step 2 — verify:** `select` from `information_schema.columns` for the 13 columns; insert a scope under a Canpro task via SQL as service role, confirm guard rejects a cross-company `task_type_id` (expect `scope_task_type_invalid`).

**Step 3 — mirror the SQL into the bible archive + commit** (`feat(db): task_scopes table with RLS, guards, revision bump`).

### Task 2: status-law trigger on `project_tasks`

**Files:** migration `task_scope_status_law` (+ bible mirror).

**Step 1:** trigger function + trigger:

```sql
create or replace function private.stamp_scopes_on_task_completion() returns trigger
language plpgsql security definer set search_path to 'public','private','pg_temp' as $$
begin
  if new.status = 'completed' and old.status is distinct from 'completed' then
    update public.task_scopes
       set completed_at = coalesce(completed_at, now()),
           completed_by = coalesce(completed_by, private.get_current_user_id()),
           updated_at = now()
     where task_id = new.id and deleted_at is null and completed_at is null;
  end if;
  return new;
end $$;
create trigger project_tasks_stamp_scopes_on_completion after update of status
  on public.project_tasks for each row execute function private.stamp_scopes_on_task_completion();
```

`private.get_current_user_id()` may be null in service contexts — `completed_by` stays null there; that is acceptable (audit shows system completion).

**Step 2 — verify with SQL:** create task + 3 scopes, `update … set status='completed'` directly (the web path), assert all 3 scopes stamped. Reopen (`status='active'`) — scopes must stay stamped (spec §4). Commit mirror.

### Task 3: `set_task_scope_completion` RPC (check/uncheck + auto-complete parent)

**Files:** migration `set_task_scope_completion_rpc` (+ mirror).

Contract: `set_task_scope_completion(p_scope_id uuid, p_completed boolean, p_expected_updated_at timestamptz, p_idempotency_key text) returns jsonb`.

Behavior (single transaction; lock parent task `for update` **before** the scope row, matching `complete_project_task`'s lock order to avoid deadlocks):
1. Load scope + parent; company check vs `private.get_user_company_id()`; permission = the same predicate `complete_project_task` uses (`private.current_user_can_complete_task_material_consumption(company, task)`) — scope check-off is a completion act.
2. Concurrency: if `p_expected_updated_at is not null` and differs from the scope's `updated_at`, raise `scope_conflict` (errcode `40001` style, matching `update_task_with_event`'s optimistic pattern).
3. `p_completed = true`: stamp `completed_at/by`. If no open, non-deleted sibling scopes remain and the task is not completed → call `public.complete_project_task(task_id, p_idempotency_key, '{}')` so material consumption + its RPC settings fire exactly once (idempotency key is caller-supplied, required).
4. `p_completed = false`: clear `completed_at/by`; if parent task is `completed` → set it `active` (direct update; consumed materials stay consumed — same semantics as today's reopen).
5. Return `jsonb`: `{scope_id, completed, task_status, task_auto_completed}`.

**Step 1** write+apply. **Step 2** SQL-verify all four branches (check, last-check auto-complete, uncheck, uncheck-reopens) plus the conflict branch. **Step 3** commit mirror.

### Task 4: scopes ride the task-creation RPCs

**Files:** migration `task_creation_scopes` (+ mirror). Functions: `create_task_with_event`, `create_task_with_event_as_system`.

- Extend the `p_payload jsonb` contract with optional `"scopes": [{"id","task_type_id","note","display_order","source_line_item_id"}]`. Absent/empty ⇒ exactly today's behavior (old clients unaffected).
- Inside the same tx after the task insert: insert each scope with the task's `company_id`; ids from payload (client-generated, lowercase) or `gen_random_uuid()` when absent. First scope's `task_type_id` must equal the task's `task_type_id` — enforce, `errcode 23514 scope_primary_mismatch` (spec: primary scope mirrors the task's type).
- Do NOT touch `update_task_with_event` — scope edits go through direct table writes (RLS-gated) or Task 3's RPC.

**Verify:** call with a 3-scope payload as an authenticated test user; assert task + 3 scopes + event row. Regression: call with no `scopes` key — byte-identical behavior. Commit mirror.

### Task 5: `compose_task_scopes` — the deterministic composition function

**Files:** migration `compose_task_scopes_rpc` (+ mirror).

`compose_task_scopes(p_company_id uuid, p_candidates jsonb) returns jsonb`
- Input candidates: `[{"task_type_id","note","source_line_item_id"}]`.
- Rule (spec §6, exactly): resolve each type's `dependencies` from `task_types`; build an undirected connectivity graph among candidate types (edge when either declares a dependency on the other, resolved transitively); each connected component of size >1 → **separate single tasks in dependency order**; the remaining unconnected candidates partition into visit groups keyed by compatible `default_team_member_ids` (null/empty crew is compatible with anything; non-empty sets must be equal to share a group).
- Output: `{"visits":[{"kind":"group"|"single","primary_task_type_id",…,"scopes":[…],"reason":"…"}]}` — `reason` is the explainability string (spec: every decision explainable).
- `stable`, company-scoped read; callable by authenticated users of that company (guard `p_company_id = private.get_user_company_id()` unless service role).

**Verify with the Canpro fixture:** candidates = Vinyl Install + Glass Rail Install + Gate Install + 6' Tall Glass Install ⇒ expect Vinyl separate (Glass Rail + Gate depend on it), and the three rail variants… **note:** Glass Rail and Gate both depend on Vinyl but not on each other — they are dependency-*connected through Vinyl*. The rule must treat "connected to a candidate predecessor" as sequencing vs that predecessor only, not as separation from each other: partition = {Vinyl} then {Glass Rail, Gate, 6' Tall} as one group scheduled after Vinyl. Encode exactly this case as the acceptance fixture (spec §10.6). Commit mirror.

### Task 6: estimate/lead conversion produces grouped tasks

**Files:** migration `conversion_grouped_tasks` (+ mirror) editing `convert_opportunity_to_project` (called by `ops-ios/OPS/Services/LeadConversionService.swift:328`) and the estimate-acceptance task materialization (locate via `\df+`/`pg_get_functiondef` search for the function inserting `project_tasks` with `source_line_item_id` — the one whose results decode into `AcceptEstimateProjectTaskResultDTO`, `ops-ios/OPS/Network/Supabase/DTOs/EstimateDTOs.swift:244`).

- Route LABOR line items through `compose_task_scopes`; each visit-group becomes one task (primary type = first scope) + `task_scopes` rows carrying `source_line_item_id`; singles unchanged.
- Result shape returned to iOS must stay decodable by the shipped app: keep one row per created *task*.
- **Rollout gate (amended 2026-09-01):** automatic grouping is gated per company by a new additive column `companies.task_groups_conversion_enabled boolean not null default false`. When false (every company today) both conversion RPCs behave byte-identically to today (one task per LABOR line item). The flag is flipped per company only after that company's crew build renders scopes (P2+P3 shipped via TestFlight) — otherwise crew on an older build would open a converted project and silently not see the non-primary scopes. Manual group creation on new clients is a human choice and is not gated. The flag is a rollout control, never a product setting: no UI, flipped by SQL at build time, documented in `03_DATA_ARCHITECTURE.md`.

**Verify:** seeded estimate with 1 vinyl + 3 rail-variant LABOR items converts to 2 tasks (1 single + 1 group of 3) with provenance intact (spec §10.6). Commit mirror.

### Task 7: regen web types + bible data-architecture docs

- Regen `ops-web/src/lib/types/database.types.ts` via the pg-meta recipe (`reference_ops_web_types_regen_recipe`).
- Bible: add `task_scopes` to `03_DATA_ARCHITECTURE.md` (table, law, RPC contracts) and cross-link from `10_JOB_LIFECYCLE_AND_DATA_RELATIONSHIPS.md`. Commit (`docs(bible): task_scopes data architecture`).

---

## Phase 2 — iOS data + sync

> Worktree off `ops-ios` main; `.spm-local`; copy `Secrets.xcconfig`. Run `AppUpdateMigrationTests` for every task here.

### Task 8: `TaskScope` @Model + schema V26

**Files:**
- Create `OPS/DataModels/TaskScope.swift` (CRLF)
- Create `OPS/DataModels/Migrations/OPSSchemaV26.swift`
- Modify `OPS/DataModels/Migrations/OPSSchemaCommon.swift` (add `v26TaskScopeModel` group near `v4TaskModels:1473`)
- Modify `OPS/DataModels/Migrations/OPSMigrationPlan.swift` (`schemas:154`, `stages:184`, add `addTaskScopesV25toV26`)
- Modify `OPS/DataModels/Migrations/OPSSchemaCurrent.swift:23` → `typealias OPSSchemaCurrent = OPSSchemaV26` (same commit — file header documents this)
- Modify `OPS/DataModels/ProjectTask.swift` — add `@Relationship(deleteRule: .cascade, inverse: \TaskScope.task) var scopes: [TaskScope] = []` + helpers `openScopes`, `isGrouped` (`scopes.filter { $0.deletedAt == nil }.count > 1`), `scopeCountBadge`
- Test: `OPSTests/DataModels/AppUpdateMigrationTests.swift` — add `testV26AddsTaskScopesWithoutChangingReleasedTask` + V25→V26 store-migration test mirroring `testV24StoreMigratesToV25` (`:123`)

Model fields mirror the table (String id lowercase, `completedAt`/`completedBy`, `note`, `displayOrder`, `sourceLineItemId`, `splitToTaskId`, sync stamps `lastSyncedAt`/`needsSync`, `deletedAt`, `createdAt`). Beware `reference_swift_let_default_memberwise_decodable` — use `var` + explicit init.

Steps: failing migration test → model+schema → tests pass → run full `AppUpdateMigrationTests` + `SiteVisitMigrationTests` → commit (`feat(ios): TaskScope model + schema V26`).

### Task 9: DTO + converters + inbound sync (both mirrors) + realtime

**Files:**
- Modify `OPS/Network/Supabase/DTOs/CoreEntityDTOs.swift` (add `SupabaseTaskScopeDTO` near `SupabaseProjectTaskDTO:289`)
- Modify `OPS/Network/Supabase/DTOs/CoreEntityConverters.swift` (`toModel()`)
- Modify `OPS/Network/Supabase/Repositories/TaskRepository.swift` (`fetchAllScopes(since:)`, scope create/update/softDelete wire methods)
- Modify `OPS/Network/Sync/SyncTypes.swift:226` (`case .taskScope: return "task_scopes"`)
- Modify `OPS/Network/Sync/InboundProcessor.swift` (`syncTaskScopes` beside `syncTasks:1218`; merge with `acceptableFields` gate + insert branch, lowercase ids, wire `task` relationship; dedupe helper beside `dedupeProjectTasks:1898`)
- Modify `OPS/Utilities/DataActor.swift` (mirror: `syncTaskScopes` beside `:1232`, merge beside `:1252`)
- Modify `OPS/Network/Sync/RealtimeProcessor.swift` (subscribe `task_scopes` in table list `:206` + row handlers beside the four `project_tasks` sites)
- Modify `OPS/Network/Sync/InboundChangeSignal.swift:79` (`"task_scopes" → "TaskScope"`)
- Test: new `OPSTests/Sync/TaskScopeSyncTests.swift` (seed one warm-up `SyncOperation` per `reference` gotcha; retain containers)

TDD per file cluster; commit per cluster (`feat(ios): task_scopes inbound sync + realtime`).

### Task 10: outbound sync + DataController scope operations

**Files:**
- Modify `OPS/Network/Sync/OutboundProcessor.swift` — `validTaskScopeColumns` beside `:1133`, `handleTaskScope` beside `:1197`, dispatch beside `:1060`, sanitizer beside `:1258`
- Modify `OPS/Utilities/DataActor.swift` — mirror allowlist `:6157`, dispatch `:5625`, sanitizer `:5689`
- Modify `OPS/Utilities/DataController.swift`:
  - `projectTaskCreateFields:5746` — no change (scopes are separate ops)
  - New `createTask(dto:scopes:)` overload: insert task + scope models locally, enqueue task create op **then** scope create ops (mirror the existing cross-entity parent-first pattern used by site-visit children; see `OPSTests/Sync/SyncCrossEntityDependencyTests.swift` for the contract)
  - New `setScopeCompletion(scope:completed:)` — local stamp + enqueue RPC-backed op calling `set_task_scope_completion` (route through `TaskRepository`, mirroring `completeProjectTask:231`); when the last open scope closes locally, drive the parent through `updateTaskStatus(task:to:stagingOperationsWith:)` (`:4052`) so the durable completion path (idempotency key, materials) runs exactly as today
  - Completion seam: in `updateTaskStatus…:4052`, stamp local open scopes when status → completed (mirror of the server trigger, for offline correctness); on reopen, leave scopes
  - New `splitScope(_:)` — create new task (type = scope type, crew = parent's, unscheduled, `customTitle` nil), soft-delete scope with `splitToTaskId`, enqueue both ops
  - `spawnPairsForPredecessor:5817` / `TaskPairSpawner` — evaluate union of scope types; skip spawn when the dependent type is already a scope of the created task
- Test: `OPSTests/Sync/TaskScopeOutboundTests.swift` — ops persist (executeOperation claim gate: tests must persist ops per `reference_outbound_executeoperation_claim_gate_tests`), payload allowlist, split op pair, spawner union + dedupe

Commit per cluster (`feat(ios): task scope outbound ops + status law seam + split`).

### Task 11: scheduling — group earliest-start = max over scope types

**Files:** locate the cascade's constraint computation (callers of `effectiveDependencies` / `earliestStart` — `SchedulingEngine`, `CalendarSchedulerSheet.swift:757` context) and widen: a task's constraint set = union of `effectiveDependencies` of ALL non-deleted scope types (single-type tasks unchanged by construction). Test in `OPSTests/` with the Canpro fixture (group {glass rail, gate} after vinyl → start = max of the two constraints).

---

## Phase 3 — iOS UI

> Skills first: `ops-design` (read DESIGN.md + MOBILE.md), `custom-skills:mobile-ux-design`, `ops-copywriter` for every string, `animation-studio:animation-architect` → `ios-animations` for scope-check + COMPLETE ALL motion (one easing, earned haptics per the existing inventory — medium impact on check, success notification on group completion, mirroring `UniversalSearchSheet:1165/1169`). `custom-skills:audit-design-system` before phase close.

### Task 12: composer multi-select (creation = tapping more types)

**Files:**
- Modify `OPS/Views/JobBoard/ProjectFormSheet.swift:3420` — `LocalTask` gains `var scopeTypeIds: [String] = []` (primary stays `taskTypeId`); reconciliation (`createTask…:3127`, DTO `:3229`, `:2578`) builds scope DTOs → `createTask(dto:scopes:)`
- Modify `OPS/Styles/Components/ProjectTaskComposer.swift` — `taskTypeField:390`: replace single-select `Menu` with a multi-select type sheet (checkmark rows, first-selected = primary, reorder respects tap order); row summary shows `RAIL INSTALL +3` via a shared `ProjectTask.displayTitle` extension (auto-title per spec §3)
- Modify `OPS/Views/JobBoard/TaskFormSheet.swift` (`saveTask:1532`, DTO `:1671`, create call `:1698`) — same multi-select
- Single-type flow must remain byte-identical (spec §10.4): no new UI when one type selected.

### Task 13: combo Quick Add chips

**Files:**
- Modify `OPS/Utilities/TaskSuggestionEngine.swift` — key becomes sorted `typeSet` (`[String]`) + crew; mine grouped tasks' scope-type sets; keyHash extends to `typeIds.joined("+") + ":" + crew`; singles keep working (typeSet of one ⇒ today's behavior; `windowDays`/`minOccurrences`/`maxResults` unchanged)
- Modify `OPS/Views/Components/Project/QuickAddSuggestionsRail.swift` — chip renders primary type + `· N SCOPES` + crew avatars; `commit:219` builds the grouped task via `createTask(dto:scopes:)`
- When the project has an estimate with unconverted LABOR scopes, the rail's first chip reflects the estimate (call `compose_task_scopes` result cached on project load), not habit — spec §5
- Test: engine unit tests for typeSet mining, dismissal-hash stability for existing single suggestions (must not resurrect dismissed singles)

### Task 14: scope UI on task surfaces + COMPLETE ALL + split

**Files:**
- Modify `OPS/Views/Components/Project/TaskDetailsView.swift` — scopes section above Status Update (`:942`): check-off rows (44pt+, medium haptic), `COMPLETE ALL` primary action when >1 open, split behind long-press (`MOVE TO ITS OWN DAY` → scheduler sheet or unscheduled)
- Modify `OPS/Views/Components/Project/Tabs/DetailsTabView.swift` task rows (`:970-1105`) — scope count affordance (`+3`) + per-scope quick-check in the row's disclosure; context menu gains COMPLETE ALL for groups
- Swipe-complete on `UniversalJobBoardCard` and review deck need **no change** — they call `updateTaskStatus`, and the Task 10 seam stamps scopes (verify by test, don't touch the cards)
- Calendar surfaces (`DayCanvasView.taskRow:684`, `MonthGridView`, `DayEventsSheet`) — scope-count badge only; one bar stays one bar
- Snapshot proofs via `FixedSizeSnapshot` harness (grouped row, detail checklist, badge) — xcresult export per `reference_fixed_size_snapshot_harness`

### Task 15: iOS regression + law tests

New `OPSTests/Tasks/TaskScopeLawTests.swift`: last-scope-check completes task; COMPLETE ALL stamps all; task-complete-by-swipe stamps scopes; reopen leaves scopes; split creates task + tombstones scope; single-type task lifecycle untouched (assert zero scope rows and unchanged payloads). Run targeted suites + `build-for-testing`; hand to PM for the batch build.

---

## Phase 4 — Web parity

> Skills: `frontend-design`, `custom-skills:interface-design`, `ops-copywriter`, `web-animations` for check/complete transitions. Full-suite vitest lies (`reference_ops_web_vitest_full_suite_cross_file_pollution`) — verify per-file.

### Task 16: types + service layer

**Files:**
- Modify `src/lib/types/models.ts` — `TaskScope` interface + `ProjectTask.scopes?: TaskScope[]` (`L288-336`); extend `getTaskDisplayTitle` for the `+N` auto-title
- Modify `src/lib/api/services/task-service.ts` — `mapFromDb`/`mapToDb` (`L170-235`) + fetch joins gain `task_scopes(*)`; `createTask`/`createTaskWithEvent` route scope payloads through the extended `create_task_with_event` RPC (atomicity — no client-side two-step insert); new `setScopeCompletion` calling the Task 3 RPC; destructure `{ error }` everywhere
- Modify `src/lib/hooks/use-tasks.ts` — scope mutations with optimistic updates across the three caches (`detail`/`lists`/`calendar.all`, pattern at `L236-421`)
- Modify `src/lib/hooks/use-project-tasks-grouped.ts` — join scopes in the direct query (`L99-110`), expose `scopeCount`/`openScopeCount`
- Tests: `tests/unit/` per service function (status collapse rules stay: DB three-value constraint, `task-service.ts:27-44`)

### Task 17: web creation + scope check-off UI

**Files:**
- Modify `src/components/ops/task-form.tsx` — type field becomes multi-select (zod `TaskFormValues:28-40` gains `scopeTypeIds: string[]`; type→color autofill `:537-551` keys off primary)
- Modify `src/components/ops/create-task-modal.tsx` (FAB quick-add) — same
- Modify `src/components/ops/projects/workspace/viewing/details-tab.tsx` `TaskRow` (`L118-152`) — scope count + expandable check-off list; COMPLETE ALL
- Modify calendar side panel `task-detail-panel.tsx` — scopes section with check-off (hook from Task 16)
- Copy per `ops-copywriter`; tokens only (bare `rounded` = 5px convention)

### Task 18: web calendar + estimate conversion

**Files:**
- Modify `src/lib/utils/calendar-utils.ts` `mapTaskToInternalEvent` (`L297-414`) — carry `scopeCount`/`openScopeCount` on `InternalCalendarEvent` (contract `L47-88`); title unchanged
- Modify `month-event-bar.tsx` (badge at the three display levels), `day/day-task-card.tsx`, `crew/crew-task-block.tsx`, `unscheduled-tray.tsx` — count affordance only
- Modify `src/components/ops/review-tasks-modal.tsx` (`L153-252`) + `src/lib/api/services/task-template-service.ts` — proposals go through `compose_task_scopes` RPC; preview shows visit groups; `createTasksFromProposals` (`task-service.ts:680-714`) becomes an RPC call creating grouped tasks with scope provenance
- Verify in a worktree preview (DEV_BYPASS_AUTH recipe): create grouped task, check scopes, complete-all, screenshot; calendar badge screenshot

---

## Phase 5 — Agent exposure + bible

### Task 19: agent reads include scopes
Extend `read_agent_task_context_as_system` (+ `read_agent_tasks_as_system` list rows minimally) with a `scopes` section (additive, capability-revision bumped per that RPC's conventions). Migration + mirror + regen. The agent *write*/conversion flow itself belongs to OPS MCP BUILDOUT — this initiative ships the composition RPC + read exposure it will consume (spec §6 contract stands as its acceptance).

### Task 20: docs + closeout
Bible: update `07_SPECIALIZED_FEATURES.md`/`10_…` feature sections; flip spec status to Built with evidence links; resolve bug `b99a7659` with fix notes + proofs; update memory. Acceptance checklist = spec §10, every line with evidence.

---

## Execution notes

- Phase order is dependency order; within P2–P4, tasks are sequential per surface but P3/P4 can run as parallel spawned sessions once P1+P2 land.
- Session naming: `TASK GROUPS - P<phase>-<n>`.
- Every task ends with its own atomic commit; iOS builds batched by the PM session.
- Nothing pushes/deploys without Jackson's explicit GO (`ops-web` main auto-deploys).
