# Task Groups — One Visit, Many Scopes

**Date:** 2026-09-01
**Status:** Approved direction (brainstorm with Jackson, 2026-08-31 → 09-01)
**Origin:** bug_reports `b99a7659-d087-46ef-9578-94bcf0e10c0f` (2026-08-22): "Figure out bundling tasks or making tasks into subtasks. Eg rail install: glass, picket and 6' tall, all separate tasks? Or sub tasks to a single rail install? Or bundled?"
**Surfaces:** Supabase (schema + composition rules), iOS, OPS-Web, Agent Control Plane (Phase C task composition)

---

## 1. Problem

Creating a mixed-scope visit today means creating N near-identical tasks. Canpro evidence (prod, 2026-08-31):

- 328 tasks across 288 projects; 89 of 166 tasked projects have 2+ tasks.
- The task-type list absorbed the fragmentation: `Rail Install`, `Glass Rail Install`, `Gate Install`, `Frameless Glass`, `6' Tall Glass Install` are all scope variants of one visit.
- Live same-visit clusters exist (2691 Galleon Way: `Glass Rail Install` + `Rail Install`, both 2026-09-01, same 1-man crew; 463 Phelps Ave: `6' Tall Glass Install` + `Glass Rail Install` unscheduled pair). All 10 same-day multi-task clusters in the data share crew.
- The dominant multi-task pattern is **phases weeks apart** (Vinyl → Rail → Glass with shipment lead time, different crew sizes). These are correctly separate tasks and must not change.

Persona validation (30-persona research doc): handyman (5 small jobs, one visit), detailing (interior+exterior+ceramic), cleaning add-ons, 3-day paint jobs (prep/walls/trim, one crew, contiguous) all converge on the same law. The electrician counter-case (rough-in vs finish, inspection between) proves per-scope independent scheduling must NOT exist — separately schedulable pieces are separate visits, i.e. tasks.

**Law: the visit is the schedulable unit; scopes are checkable units inside it.**

## 2. Decision

A task may carry **multiple scopes**. Each scope references a task type. No parent/child tasks, no bundles of flat tasks, no new top-level noun. A single-type task is unchanged and carries zero scope rows.

Rejected alternatives:
- **Parent/child subtasks** — invites phase-nesting (electrician case), recreates calendar clutter inside a hierarchy, touches every task query on every surface.
- **Bundles (flat tasks + visual band)** — keeps N objects (drag, status, sync chatter); fails the creation-friction requirement outright.

## 3. Data model (additive-only — shipped iOS builds still read the old shape)

New table `task_scopes`:

| column | type | notes |
|---|---|---|
| `id` | uuid PK | lowercase-generated (iOS `UUID().uuidString` must be lowercased) |
| `company_id` | uuid NOT NULL | tenant scope, RLS mirror of `project_tasks` |
| `task_id` | uuid NOT NULL → project_tasks | CASCADE follows task soft-delete semantics |
| `task_type_id` | uuid NOT NULL → task_types | the scope's identity, color, materials vocabulary |
| `note` | text NULL | free detail ("20 ft", "upper deck") |
| `display_order` | int NOT NULL | |
| `completed_at` | timestamptz NULL | null = open |
| `completed_by` | uuid NULL | users id |
| `source_line_item_id` | text NULL | estimate lineage, same convention as project_tasks |
| `split_to_task_id` | uuid NULL | set when this scope was split off; scope row is then soft-deleted |
| `created_at` / `updated_at` / `deleted_at` | timestamptz | standard |

`project_tasks` gains **nothing required**. Existing columns keep meaning:
- `task_type_id` = **primary scope's type** (first selected). Every legacy surface (calendar color, lists, sync, reporting) keeps working unmodified. The primary scope also exists as a `task_scopes` row so rendering logic is uniform: a grouped task's scope list is exactly its `task_scopes` rows.
- `custom_title` unchanged. Auto-title for groups when no custom title: primary type display + `+N` (e.g. `RAIL INSTALL +3`).
- Schedule, crew, status, recurrence, `schedule_version` semantics untouched. Scopes never carry dates or crew.

RLS: same company-membership policies as `project_tasks` (anon-role compatible — the app runs as anon; see feedback_anon_role_rls_policies). Writes via the same permission gates as task edit; scope completion via the same gate as task completion. No new permission grants (register nothing new in the client catalog).

## 4. Behavior

**Status law.**
- Completing the last open scope completes the task (success haptic on iOS; standard task-completed notification — scope check-offs log to activity, they do not notify).
- `COMPLETE ALL` on the task stamps every open scope (`completed_at/by`) and completes the task. One tap for the crew.
- Reopening a task does not reopen scopes; reopening any scope of a completed task reopens the task.
- Cancelling a task leaves scope rows untouched (historical record).

**Split-off.** Scope → its own task: new `project_tasks` row (same project; `task_type_id` = scope's type; crew prefilled from the group's crew; unscheduled or user-picked date; `custom_title` null; note copied), scope row gets `split_to_task_id` and is soft-deleted from the group. A group reduced to one scope remains a valid task and renders as a plain single-type task. Split is task creation + task edit — both existing permission gates.

**Dependencies / auto-scheduling.** A grouped task's earliest-start constraint = the **max** across its scope types' dependency constraints (each resolved against the project's other tasks, exactly as today for a single type).

**Pair-spawner (`TaskPairSpawner`).** Evaluates the union of the created task's scope types as predecessors. Never spawns a type that is already a scope of the group (it's already part of the visit). Spawned tasks remain separate tasks, as today.

**Recurrence.** Allowed. Materialized instances copy the scope set fresh (all open). Exceptions untouched.

**Materials / inventory.** Unchanged in this build: `task_materials` and consumption stay task-level. `task_scopes.source_line_item_id` preserves the lineage needed to partition later without a migration.

## 5. Creation — the one-tap paths

**Composer (iOS first, web parity in the same initiative).** In the existing type picker, tapping a second type creates a group — no mode, no toggle, no new control. Checkmarks accumulate; first tap = primary. Single-type flow is byte-for-byte today's flow.

**Quick Add combo chips.** `TaskSuggestionEngine` extends its key from `(taskTypeId, crew)` to `(typeSet, crew)` — same recency × frequency scoring (60-day window, exp decay, min 2 occurrences, max 3 chips), mined from grouped tasks once they exist. Chip renders primary type + `· N scopes` + crew avatars; one tap commits the whole grouped task. Human-facing only: a tapped chip is the human asserting today's reality, so habit-based suggestion is legitimate here — and when the project has an estimate, the chip reflects the estimate's scopes, not habit.

**From the estimate.** Estimate → tasks conversion partitions sold line items by the composition rules (§6) and proposes grouped tasks in the existing conversion preview.

## 6. Composition rules — one brain, three hands

One deterministic rule set, defined server-side (ops-web service + RPC, mirrored in Swift for offline composer parity), consumed by: (a) Quick Add chips, (b) estimate conversion, (c) the Agent Control Plane. Given a set of candidate scopes for a project:

1. Map evidence to task types (line item → type via existing catalog linkage; explicit type references otherwise).
2. Types connected by a dependency edge (either direction, resolved transitively) are **different visits** → separate tasks, sequenced by the dependency engine.
3. Remaining dependency-unconnected types partition into one visit-group per compatible default-crew set; incompatible crew defaults → separate tasks.
4. Output is explainable: every grouping decision carries its reason ("no dependency between Glass Rail and Gate; both default to Jake").

**Agent contract (Phase C / lead→project conversion).** Evidence ladder for *what scopes exist*:
1. Sold scope — estimate/quote line items on the lead. Authoritative.
2. Observed/stated scope — site-visit record, lead notes, customer correspondence (the email chain is a first-class source; when an estimate also exists, the estimate wins — discussed ≠ sold).
3. Neither → **ask one clarifying question. Never pattern-fill scope from history** (not every job has glass; not every job has a privacy screen — Jackson, 2026-09-01). Company history may inform only *defaults around confirmed scopes* (crew, duration), never scope existence.

Authority (per 2026-08-30 MCP vision handoff §5.1): agent-composed tasks are reversible internal filing — unscheduled or draft-dated with `schedule_confirmed_at` null, receipted with the composition reason, one-tap confirm, one-tap reverse. Auto-file only under an explicit bounded owner policy. Golden-task coverage: composition rules are deterministic → 100% assertion coverage per the vision spec.

## 7. Presentation (design-system work, per ops-design + mobile MOBILE.md)

- **Calendar / schedule sheet / day sheet:** one bar, primary type color, unchanged geometry. Grouped tasks show a scope-count affordance (e.g. `+3`) — exact treatment resolved in the design pass; nothing else changes on scan surfaces (verbs stay off them).
- **Task card / detail:** scope rows with tap-to-check (44pt targets), note inline, `COMPLETE ALL` as the primary action when >1 scope open. Split lives behind the row (long-press / swipe), not on the scan surface.
- **Copy:** via ops-copywriter; terse register (`SCOPES`, `COMPLETE ALL`, `MOVE TO ITS OWN DAY`).

## 8. Non-goals

- No nested groups. No per-scope dates, crew, or status beyond open/complete (need independence → split).
- No per-scope material allocation in this build (lineage preserved for later).
- No changes to phase workflows, dependency engine semantics, or the type catalog. Scope-variant types remain full task types — they are the scope vocabulary.
- No new notification types (scope checks = activity only).

## 9. Sync + platform constraints (verified against current schema/code 2026-08-31)

- Additive-only schema (shipped iOS builds): new table + no required-column changes. ✓
- iOS: new `TaskScope` SwiftData model + migration (run `AppUpdateMigrationTests` — V23 incident rule), sync ops for scope create/check/uncheck/delete, spawner + composer changes. Lowercase UUIDs at generation.
- Web: destructure `{ error }` on every scope write (PGRST204 phantom-column gotcha); types regen via pg-meta recipe.
- Group completion echo: `COMPLETE ALL` is one task update + N scope updates — must land atomically server-side (RPC) so a mid-flight offline client can't sync a half-completed group.

## 10. Acceptance (proof, not claim)

1. Create a grouped Rail Install (glass + picket + gate + 6' tall) in one composer pass on iOS; one calendar bar; screenshot.
2. Check scopes individually → task auto-completes on the last one; `COMPLETE ALL` from fresh group → same end state; both under test.
3. Split glass to its own day → original keeps 3 scopes, new task carries type/crew/note; screenshot both.
4. Single-type task lifecycle byte-identical to today (regression suite).
5. Combo chip appears after 2 grouped creations within window; one tap reproduces the group.
6. Estimate with 4 rail line items + 1 vinyl line item converts to: 1 vinyl task + 1 grouped rail task (dependency partition proof).
7. Agent conversion with no estimate/site-visit scope evidence produces a clarifying question, never a scope guess (golden task).
