# 22 - Task Groups (One Visit, Many Scopes)

**Last Updated:** September 2, 2026
**Status:** Built on branches, not yet shipped (see §9). Database layer LIVE in production since 2026-09-01 with the conversion gate OFF for every company.
**Spec:** `specs/2026-09-01-task-groups-design.md` · **Plan:** `docs/plans/2026-09-01-task-groups.md` · **Origin:** bug `b99a7659-d087-46ef-9578-94bcf0e10c0f`
**Purpose:** The one place that explains how a task carries several scopes of work, how that behaves on every surface (database, iOS, web, agent reads), and the exact ship sequence. Schema and RPC detail live in `03_DATA_ARCHITECTURE.md` and `04_API_AND_INTEGRATION.md` (sections dated 2026-09-01); conversion behavior in `10_JOB_LIFECYCLE_AND_DATA_RELATIONSHIPS.md`.

---

## 1. The law

**The visit is the schedulable unit; scopes are checkable units inside it.**

- A `project_tasks` row may carry N rows in `task_scopes`. Zero rows = an ordinary single-type task (unchanged, byte-identical everywhere). Two or more = a *grouped* task. Exactly one row never occurs by construction on any creation path.
- The task's `task_type_id` is always the **primary** scope's type, so every legacy surface (color, title, sync, reporting, old app builds) keeps working with no knowledge of scopes.
- Scopes never carry dates or crew. When a piece of work needs its own day, it is **split off** into its own task (`task_scopes.split_to_task_id`, scope soft-deleted).
- Phase chains that wait on each other (Canpro: Vinyl → Rail → Glass, weeks apart) stay separate tasks; grouping never touches them.
- **Status law (enforced in Postgres, not per client):** a task set to `completed` by *any* write path stamps every open scope (`completed_at`, `completed_by`). Checking the last open scope completes the task. Reopening a task leaves stamps; unchecking a scope on a completed task reopens it. Cancelling leaves scopes untouched.

Evidence for the law (2026-08-31, prod): Canpro's task-type list had exploded into five rail variants (`Rail Install`, `Glass Rail Install`, `Gate Install`, `Frameless Glass`, `6' Tall Glass Install`); all 10 same-day multi-task clusters shared crew; the 30-persona research doc converges on the same shape (handyman visits strongest; the electrician rough-in/finish case proves per-scope dates must not exist).

## 2. Database (LIVE)

Migrations, all applied direct to prod on 2026-09-01 and mirrored byte-exact under `migrations/`:

| Ledger version | Name | What it does |
|---|---|---|
| `20260901184459` | `task_scopes_table` | Table, RLS (readable iff the parent task is; writes = parent task's edit rule), guards, agent read-revision bump |
| `20260901184710` | `task_scope_status_law` | Trigger `project_tasks_stamp_scopes_on_completion` |
| `20260901185254` | `set_task_scope_completion_rpc` | Check/uncheck with idempotency key; last check → `complete_project_task`; uncheck reopens; stale `p_expected_updated_at` returns `{ok:false, conflict:true}` |
| `20260901185510` + `20260901190151` | `compose_task_scopes` (+ reason grammar) | Deterministic visit composition: candidates connected by dependency edges become sequenced singles; leaves group by crew compatibility; every visit carries a reason string |
| `20260901185630` | `task_creation_scopes` | `create_task_with_event` payload `scopes[]` (first scope's type must equal the task's type; scopes insert only on a fresh task, so retries never duplicate); `create_task_with_event_as_system` gains `p_scopes` |
| `20260901191611` | `conversion_grouped_tasks` | Lead/estimate conversion composes visits **only when `companies.task_groups_conversion_enabled = true`** (default false = byte-identical legacy); `resolve_estimate_material_demand_plan` maps scope-carried lines to their grouped task |
| `20260901193928` | `enable_realtime_for_task_scopes` | Realtime publication + `REPLICA IDENTITY FULL` (an unpublished table subscribed by iOS kills the shared CDC channel) |
| `20260901232945` | `task_creation_provenance` | `create_task_with_event` payload accepts `source_line_item_id` + `source_estimate_id` (validated lineage) |

Every migration was rehearsed in a `begin; … rollback;` transaction against production with Test Company fixtures, verified with structural line-diffs against the previous function bodies, and left zero residue.

**The rollout gate.** `companies.task_groups_conversion_enabled` is not a product setting: it is flipped per company by SQL only after that company's crew build renders scopes. Otherwise an older phone would open a converted project and silently not see the non-primary scopes. Manual group creation on a new build is a human choice and is not gated.

**Material ledgers.** `complete_project_task` consumes through the catalog ledger (`project_material_demands` / `catalog_stock_units`); the web app's `InventoryDeductionService` writes the legacy ledger (`task_materials` / `inventory_items`). They are distinct tables and cannot double-count, but a client must complete a task through exactly **one** server path — the iOS rule is: non-last scope checks use the scope RPC; the last check and COMPLETE ALL use the existing durable task completion path (idempotency key + material adjustments), never both.

## 3. iOS (branch `feat/task-groups`)

- **Model:** `OPS/DataModels/TaskScope.swift`, schema V26 (`OPSSchemaV26`, migration stage `addTaskScopesV25toV26`). There is deliberately **no SwiftData relationship** between `TaskScope` and `ProjectTask`: any inverse (or a `@Transient` of `@Model` type) shifts all 25 released schema checksums and makes installed stores unrecognisable. Scopes are fetched by `taskId` through `TaskScopeProjection` (predicate-free, filtered in Swift); scan surfaces read primitive `@Transient` counts (`liveScopeCount`, `openScopeCount`, `isGrouped`, `scopeCountBadge`) filled by `TaskScopeProjection.hydrate(tasks:in:)` — one fetch per list, never per row. Auto-title: `displayTitle` = `RAIL INSTALL +3` for a group with no custom title; `displayTitleBase` for surfaces that add their own badge.
- **Sync:** inbound merge in both pipelines (`InboundProcessor` and `DataActor`), realtime subscription, outbound `.taskScope` ops on both mirrors with parent-first ordering enforced by `SyncCrossEntityDependency` (`task_id` and `split_to_task_id` are reference keys). Scope completion ops carry `completed_at`/`completed_by` in `changedFields` (so `SyncFieldGuard` protects the local stamp from a stale echo) and strip them before the wire; the RPC is called with `expectedUpdatedAt = nil` because queued ops are stale by construction and the idempotency key makes replay safe.
- **Behavior:** `DataController.createTask(dto:scopes:)`, `setScopeCompletion(scope:completed:)`, `splitScope(_:)`; completion seam in `updateTaskStatus(task:to:…)` stamps local scopes on completion; `TaskPairSpawner` evaluates the union of a visit's scope types and never spawns a type already in the visit; scheduling constraints = union of every live scope type's dependencies (`@Transient scopeDependencyUnion`), hydrated once per scheduling pass.
- **Creation UI:** the TASK TYPE menu keeps today's single-select behavior; once a type is selected it gains `ADD SCOPES` → `TaskScopePickerSheet` (house twin of the crew picker; primary pinned; tap order = display order). `LocalTask.normalizedScopes()` drops anything below two entries, which is what keeps the single-type path byte-identical. Quick Add chips are keyed on the task's sorted type set (single-type hashes unchanged, dismissals honored); grouped chips title themselves with the auto-title grammar and carry crew in the meta line; when the project has an approved estimate with unfiled LABOR lines, the first chip is composed by `compose_task_scopes` and carries `· FROM ESTIMATE` (falls back silently offline).
- **Working UI:** task detail gains a `SCOPES` section for grouped tasks — `OPSCheckControl` rows (44pt targets, olive check), notes, mono `DONE 10:42` / `DONE AUG 28` stamps, `COMPLETE ALL` (the screen's one accent, shown while >1 scope is open), long-press `Move to its own day` → split + day picker when the user holds `calendar.edit`. Project rows and calendar cards show a mono `+N` badge; the project row's badge discloses quick-check rows; the context menu reads `Complete all` on a group.
- **Tests:** `TaskScopeSyncTests`, `TaskScopeOutboundTests`, `TaskScopeSchedulingTests`, `TaskScopeLawTests`, `ProjectTaskComposerLogicTests`, `TaskSuggestionEngineTests`, snapshot suites `TaskScopeSurfaceSnapshotTests` / `TaskGroupCreationSnapshotTests`, plus the migration suites.

## 4. Web (branch `feat/task-groups-web`)

- Types: `TaskScope` in `src/lib/types/models.ts`; `getTaskDisplayTitle` auto-titles groups. `task-service.ts` joins `task_scopes(*)`, creates grouped tasks through the `create_task_with_event` RPC (strict allow-listed payload), and calls `set_task_scope_completion` with a fresh idempotency key per call; a stale token throws `ScopeConflictError`.
- Creation: the type picker is state-aware — nothing selected → today's single-select picker (a seeded default is not a selection; the first pick replaces it and closes); a selection made → reopening accumulates, chips appear at two or more, first pick stays primary. Edit mode stays single-select.
- Working: project rows show `+N` with a disclosure of 36px check rows and `COMPLETE ALL`; the schedule side panel has a `SCOPES` section. Every web-initiated completion settles the legacy inventory ledger (shared `deductTaskInventory`/`reverseTaskInventory` helpers; COMPLETE ALL settles regardless of cache warmth).
- Calendar: `mapTaskToInternalEvent` carries `scopeCount`/`openScopeCount`; month/day/crew cards render a `+N` badge only — one bar stays one bar.
- Conversion: the review-tasks modal previews visits from `compose_task_scopes` and creates one task per visit with scope provenance; `inventory-deduction-service` attributes per line using scope provenance. Note: that modal has no mount site today and no company has task templates, so the web conversion path is unreachable by customers until product decides to revive it.
- Agent reads (`feat/task-groups-agent-reads`, merged into the web branch): `get_task_context` gains an opt-in `scopes` section and both task reads gain `scope_summary`; capability revisions bump to `2026-09-01.v2`. The SQL is **staged** at `supabase/migrations/staged/20260901T000000_agent_task_reads_scopes_v2.sql` and must be applied in the same deploy as the web push — the task tools pin the exact revision on both sides.

## 5. Agent contract (decided, partially built)

Scope existence comes only from evidence about *this* job: sold line items first, then site-visit notes / lead notes / customer correspondence (the estimate wins when both exist), else the agent asks one clarifying question. Company history may inform defaults (crew, duration) but **never** scope existence ("5 of 10 jobs have glass" is banned as evidence). Agent-composed tasks land unconfirmed and receipted per the MCP vision §5.1. This initiative shipped the composition RPC and the read exposure; the agent *write* flow belongs to the OPS MCP buildout and its acceptance (spec §10.7) is carried there.

## 6. What stays untouched

Single-type tasks (zero scope rows, unchanged payloads and UI), phase chains and the dependency engine, recurrence templates (single-type; a materialized instance may gain scopes later), the task-type catalog (scope-variant types are the scope vocabulary), notifications (scope checks are activity, not notifications; group completion uses the standard task-completed notification).

## 7. Proofs

- Database: rollback rehearsals with pasted outputs for every branch of every RPC; Canpro-shaped fixture (vinyl + glass rail + gate + 6' tall + untyped line) converts to 3 tasks / 3 scopes with the gate on and 5 tasks / 0 scopes with it off.
- iOS: 80 + 71 tests across the two Phase-3 branches, 172 on the Phase-2 head; snapshot PNGs under `ops-ios/docs/artifacts/task-groups/` (and the surfaces worktree's copy).
- Web: 40 test files / 332 tests green after merging the live main; browser screenshots under `ops-web/docs/artifacts/task-groups/` including the live check-off → auto-complete → reopen round trip against production (test rows soft-deleted).

## 8. Known follow-ups (filed as chips)

- `TASK GROUPS - P4-4`: web task delete returns 403 (RLS applied to the RETURNING row after `deleted_at` is set) — pre-existing, affects every web deletion, user sees nothing.
- `TASK GROUPS - P4-5`: web `Button` primary variant is filled at rest (60 files) vs DESIGN.md's outlined-at-rest rule.
- `TASK GROUPS - P3-1` (chip): `TaskDetailsView` spends the steel-blue accent on its prev/next navigation pills (banned by DESIGN.md §3 / MOBILE.md §13); now that the screen has a real primary action the accent should pull back to it.
- Repo hygiene: `ops-ios/.gitignore` does not cover `.derived/`, the DerivedData path every worktree uses.

## 9. Ship sequence (Jackson's GO)

1. `git fetch` and re-merge `origin/main` into `feat/task-groups-web`; regenerate `database.types.ts` (PUBLIC API objects landed after both regens).
2. Push `feat/task-groups-web` to `main` **and, in the same deploy, apply** `supabase/migrations/staged/20260901T000000_agent_task_reads_scopes_v2.sql` (its README carries the checklist). Neither half alone: the live MCP task tools fail on a revision skew.
3. PM batches the iOS build from `feat/task-groups` (worktree `ops-ios/.worktrees/task-groups-p2`) → TestFlight to crew.
4. Only after the crew build is on phones: `update companies set task_groups_conversion_enabled = true where id = '<company>'` per company. Until then, converted estimates keep producing one task per line item.
5. Delete the Phase-3 worktrees' build directories (~18 GB each) once the batch build lands.
