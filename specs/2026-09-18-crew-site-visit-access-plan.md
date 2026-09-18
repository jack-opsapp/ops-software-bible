# Crew Site-Visit Access Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use custom-skills:executing-plans (OPS-tuned) to implement this plan task-by-task.

**Goal:** A site-visit assignee can open, capture and complete that visit with no `pipeline.*` permission, and any holder of the new `site_visits.capture` permission can start a walk-up visit — spec `specs/2026-09-18-crew-site-visit-access.md`.

**Architecture:** Authority stays server-side: new assignee helpers are OR-ed into the existing site-visit view/child helpers and capture RPCs (never into lead RLS); a narrow `read_site_visit_briefs` RPC gives assignees the lead's display fields. iOS opens assigned visits through a root-level capture host instead of the Leads tab and hides lead-authority actions it cannot perform.

**Tech Stack:** Postgres 17 / Supabase (plpgsql, RLS), Next.js 15 TS registry (vitest), SwiftUI + SwiftData (XCTest, not built in worker sessions).

**Design System:** `ops-design-system/project/DESIGN.md` + `mobile/MOBILE.md`. No new visual components: one FAB menu item and dialog buttons reuse existing `FABMenuItem` / `confirmationDialog` styling; icons via `OPSStyle.Icons` (SF Symbols) only.

**Required Skills:** `supabase:supabase` (Task 1), `superpowers:test-driven-development` (Tasks 2–3), `custom-skills:mobile-ux-design` (Task 3 UI gates), `ops-copywriter` (copy below is final — do not rewrite).

**Final copy (ops-copywriter, 2026-09-18):** FAB item `Start Site Visit`; calendar dialog button `RESUME VISIT`; permission label `Start site visits`, category `Site Visits`.

---

### Task 1 — Server migration (principal; prod)

**Files:** ops-web `supabase/migrations/<ledger>_site_visit_assignee_access.sql`; bible `migrations/` mirror; bible `03_DATA_ARCHITECTURE.md`, `04_API_AND_INTEGRATION.md`.

1. Guard block: md5 of every function to be replaced must equal the reviewed live value (captured 2026-09-18 from `pg_get_functiondef`), else raise.
2. Create `private.actor_is_site_visit_assignee`, `private.actor_can_work_site_visit_as_assignee`, `private.current_user_is_site_visit_assignee` (spec § Server). Revoke from public/anon/authenticated.
3. Replace `private.current_user_can_access_site_visit_child` (assignee read/write branch).
4. Replace `public.save_site_visit_capture` (assignee branch with 5 frozen link columns; leadless-new requires `site_visits.capture` or any-scope `pipeline.convert`).
5. Replace answer-branch authority in `private.apply_site_visit_rows`, `private.apply_site_visit_rows_v2`, `private.site_visit_review_rows`, `private.site_visit_review_rows_v2`, and `private.complete_site_visit_guarded` (each a byte-exact copy of the live body with only the authority expression changed).
6. `alter policy assigned_lead_scope_select on public.site_visits using (… OR private.current_user_is_site_visit_assignee(company_id, assignee_ids))`.
7. `public.read_site_visit_briefs(uuid[])` — grant execute to authenticated only.
8. Permission: registry row, 5 preset `role_permissions` rows, `feature_flags('pipeline').permissions` append (idempotent).
9. **Rehearse in a rolled-back transaction**, role-playing via `set_config('request.jwt.claims', …)` + `set local role authenticated`:
   - A crew member assigned to a lead-linked visit: select visit ✓, child select ✓, `apply_site_visit_write_v2` answer ✓, `save_site_visit_capture` same links ✓, changed `opportunity_id` ✗ 42501, `complete_site_visit_capture` ✓, `read_site_visit_briefs` returns lead fields ✓, `delete_site_visit_capture` ✗, `apply_site_visit_stage_command` ✗.
   - A crew member NOT assigned: select ✗ (0 rows), brief ✗ (no row), write ✗.
   - Assignee on a cancelled visit: select ✓ (tombstone sync), write ✗.
   - New leadless visit: crew with `site_visits.capture` ✓; Unassigned role ✗.
   - Owner/office regression: all previous paths ✓.
10. Apply; read back ledger md5 = file; re-run the rehearsal without the migration step (still rolled back).
11. Commit migration + rehearsal script reference; bible mirror + chapters.

### Task 2 — OPS-Web registry (Opus agent, worktree)

**Files:** Modify `src/lib/types/permissions.ts` (new `siteVisitsModule` in `PERMISSION_CATEGORIES`, placed after pipeline), the pipeline feature-flag → permission mapping (find with `git grep -n "pipeline.configure_stages" -- src`), any i18n dictionary keyed by permission id (find with `git grep -n "\"pipeline.convert\"" -- src/i18n`). Test: extend the existing registry tests that pin `ALL_PERMISSIONS` / `PERMISSION_EDITOR_REGISTRY` (find with `git grep -ln PERMISSION_EDITOR_REGISTRY -- tests`).

Steps: failing test asserting `site_visits.capture` ∈ `ALL_PERMISSIONS` and `PERMISSION_EDITOR_REGISTRY` with scopes `["all"]` and label `Start site visits` → implement → vitest green on permission tests → `npx tsc --noEmit` shows no new errors vs origin/main → commit `feat(permissions): register site_visits.capture`.

### Task 3 — iOS (Opus agent, worktree; NO xcodebuild)

**Files (verify each before editing):**
- Create `OPS/Utilities/SiteVisitAccess.swift` + `OPSTests/SiteVisits/SiteVisitAccessTests.swift`.
- Modify `OPS/Utilities/PermissionEditorPolicy.swift` (register permission), `OPS/Network/Supabase/FeatureFlagService.swift` (pipeline list).
- Modify `OPS/Views/MainTabView.swift` (root capture host; `StartSiteVisit` relay order; heads-up/reminder routing for users without leads access).
- Modify `OPS/Views/Calendar Tab/DayCanvasView.swift` (dialog: START NOW / RESUME VISIT pass `siteVisitId`; OPEN LEAD needs leads access; RESCHEDULE needs `canConvertAny`).
- Modify `OPS/Services/CalendarSiteVisitLeadResolver.swift` + `OPS/ViewModels/CalendarViewModel.swift` (brief RPC, readable-visit set, filter).
- Add RPC call in the opportunity/site-visit repository layer: `read_site_visit_briefs(p_site_visit_ids)`.
- Modify `OPS/Views/Components/FloatingActionMenu.swift` (walk-up item for `site_visits.capture`-only users).
- Modify `OPS/Views/SiteVisits/SiteVisitCaptureView.swift` / `SiteVisitCaptureViewModel.swift` (lead-authority gates).
- Push/deep-link: `OPS/Utilities/NotificationManager.swift`, `OPS/Utilities/DeepLinkCoordinator.swift`, `OPS/AppDelegate.swift` — forward `siteVisitId` into the relay userInfo.

TDD targets (pure logic lives in `SiteVisitAccess` / resolver so it is unit-testable without UI):
- `isAssignee` case-insensitive; `canStartWalkUp` true for capture-only, convert-any, false otherwise.
- Relay resolution: leads access → `.leadsTab`; else assigned open visit by id → `.rootCapture(visitId)`; else by lead id → `.rootCapture`; else `.denied`.
- Calendar dialog actions per (status, isToday, hasLeadsAccess, canConvertAny).
- Resolver: successful response → readable set = returned ids; error → previous set retained; lead details mapped by opportunity id exactly as before.
- Capture gates: stage card / create project / create lead / lead search / address-to-lead / discard hidden without the matching lead authority; no stage command queued when the user lacks lead edit.

Commit per concern; report "code-complete, NOT BUILT" and hand to the bug-reports PM session.

### Task 4 — Review & close (principal)

Read every diff against the spec; run web vitest; `swiftc -parse` on touched Swift files; bible update (09/07 as applicable, 03 permission, 04 RPC); memory; plain-language report to Jackson.
