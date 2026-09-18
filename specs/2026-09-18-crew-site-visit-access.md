# Crew site-visit access (2026-09-18)

**Initiative:** CREW SITE VISITS · P1
**Trigger:** Canpro crew member (Crew role, zero `pipeline.*` grants) could neither carry out a site visit assigned to him nor start a walk-up visit. Jackson approved the fix 2026-09-18 ("yes go please").

## Outcome

1. **Assignment is the grant.** A user listed in `site_visits.assignee_ids` can see that visit, see the lead's name / address / inquiry summary on it, capture (checklist, photos, notes, measurements, identity drafts) and complete it — with no `pipeline.*` permission.
2. **Walk-up capture is a permission.** New permission `site_visits.capture` ("Start site visits", scope `all`) lets a user start a new visit with no lead from the + menu. Granted by default to Admin, Owner, Office, Operator, Crew (every preset that fields work). `pipeline.convert` (any scope) continues to allow it, so no existing user loses the ability.

## What an assignee may NOT do (unchanged, lead/project authority only)

- Re-link the visit to a different lead, project or client (`opportunity_id`, `project_id`, `project_ref`, `client_id`, `client_ref` frozen for assignee-only authority).
- Book, reschedule, cancel, reassign, delete or discard the visit (booking columns are already token-guarded by `guard_site_visit_booking_write`; `delete_/discard_site_visit_capture` and `*_site_visit_for_actor` keep `actor_can_edit_site_visit`).
- Move the lead's pipeline stage (`apply_site_visit_stage_command` keeps `user_can_edit_opportunity`), create a lead, convert to a project, search or attach other leads, or edit the lead's address.
- Read the full lead row. The lead brief is a narrow projection (below), never `opportunities` RLS widening — `estimated_value`, correspondence, notes stay private.

**Read vs write.** Assignee READ has no status/deleted filter — cancellations and deletion tombstones must reach the assignee's phone through the delta sync (the lead-based view helper doesn't filter them either). Assignee WRITE exists only while the visit is live: not deleted, status ≠ `cancelled`, actor an active member of the visit's company. After completion an assignee may land late child writes (artifact URL settlement); capture RPCs already refuse answer/visit writes to completed visits.

**Losing access.** The phone never prunes rows it can no longer read (true today for lead reassignment too). The Schedule therefore asks the server which of its local booked visits the user can still read (`read_site_visit_briefs`) and hides the rest whenever that answer is authoritative (a successful response). Offline, the last successful answer stands.

## Server (one migration, prod `ijeekuhbatykdomumfjx`)

New helpers (`private`, SECURITY DEFINER, `search_path ''`, revoked from app roles):
- `actor_is_site_visit_assignee(p_actor uuid, p_company text, p_assignee_ids text[]) → boolean` — actor is an active, non-deleted member of `p_company` (company not deleted) and `lower(p_actor::text) = any(lower(ids))`. READ authority.
- `current_user_is_site_visit_assignee(company text, assignee_ids text[])` — READ wrapper over `private.get_current_user_id()`, company must equal the caller's.

Changed:
- RLS `site_visits.assigned_lead_scope_select` (restrictive) → `current_user_can_view_site_visit(...) OR current_user_is_site_visit_assignee(company_id, assignee_ids)`. Insert/update/delete policies unchanged (assignee writes go through definer RPCs).
- `current_user_can_access_site_visit_child` → add the assignee branch for read and write; the helper already requires a non-deleted parent. (As built: a single assignee predicate; closed/cancelled refusals come from each capture RPC's own checks — `SITE_VISIT_CAPTURE_CLOSED`, `capture_closed` conflicts, `cannot_complete_cancelled_site_visit` — so phones settle gracefully instead of parking on 42501.) Covers artifacts / answers / identity-draft RLS and `apply_site_visit_write(_v2)`.
- `save_site_visit_capture` → existing visit: allowed if lead/project authority on current AND proposed links (today), OR assignee of the current row AND all five link columns unchanged. New visit: lead/project authority as today; additionally a leadless, projectless new visit requires `site_visits.capture` or any-scope `pipeline.convert` (`has_permission(actor,'site_visits.capture','all')` or `private.effective_pipeline_scope_for_user(actor, company, 'pipeline.convert') is not null`).
- `apply_site_visit_rows`, `apply_site_visit_rows_v2`, `site_visit_review_rows`, `site_visit_review_rows_v2` (answer branch) → `actor_can_edit_site_visit(...) OR actor_is_site_visit_assignee(...)` on the locked visit row.
- `complete_site_visit_guarded` → `current_user_can_edit_site_visit(...) OR current_user_is_site_visit_assignee(...)`.
- New `public.read_site_visit_briefs(p_site_visit_ids uuid[]) → setof (site_visit_id uuid, opportunity_id uuid, contact_name text, title text, address text, ai_summary text, description text)`; SECURITY DEFINER; `authenticated` only; ≤ 200 distinct ids. One row per requested visit the caller can currently READ (lead/project view OR assignee), same company, visit not deleted; lead columns filled from the linked, non-deleted opportunity (null for a leadless visit). Lead columns mirror `CalendarSiteVisitLeadDetails` exactly. Absence of a requested id = the caller cannot read that visit.
- Assignee branches in `save_site_visit_capture`, answer rows, review rows and completion use `actor_is_site_visit_assignee` on the row locked `for update`; each function's existing closed/cancelled checks then apply.
- **Delivery split (as built):** part A (everything above except the permission) is ledger `20260918054412`, live. Part B (registry row, preset grants, pipeline flag) ships with the OPS-Web registry release because web role saves require both registries to match exactly.
- Permission `site_visits.capture`: `private.lead_permission_editor_registry` row (`{all}`), `role_permissions` rows for the five presets, added to `feature_flags('pipeline').permissions`.
- Every replaced function is md5-guarded against its reviewed live definition.

## OPS-Web

- `src/lib/types/permissions.ts`: new `siteVisitsModule` → `site_visits.capture` "Start site visits" (`all`). Required by the admin-bypass rule (unregistered ⇒ owner silently denied).
- Pipeline feature-flag permission mapping mirrors the DB list.
- No other web surface changes: the presign route's RLS read now admits assignees automatically.

## iOS

- `PermissionEditorPolicy`: register `site_visits.capture` ("Start site visits", "Site Visits", `[.all]`); `FeatureFlagService` pipeline list gains it.
- New `SiteVisitAccess` (pure, tested): `isAssignee(visit,userId)`, `canStartWalkUp` (`site_visits.capture` or `canConvertAny`), `leadAuthority(lead assignedTo)` → view/edit/convert/create flags from `LeadAccessPolicy`.
- New root-level capture host in `MainTabView` (`.fullScreenCover`) for visits opened WITHOUT the Leads tab: `SiteVisitCaptureView(opportunity: briefSnapshot, resumingSiteVisitId: visit.id, …)`.
- `StartSiteVisit` relay carries `siteVisitId` when known (calendar, push payload already has it). Order: leads access → existing Leads-tab path; else a local open visit where the user is an assignee (by `siteVisitId`, else by lead id) → root host; else the existing access-denied rail.
- Heads-up / reminder pushes for a user without leads access route to Schedule on the visit's day instead of the denied lead.
- Calendar card dialog: START NOW (scheduled, today) and RESUME VISIT (in progress) open the visit; OPEN LEAD only with leads access; RESCHEDULE only with `canConvertAny`.
- `CalendarSiteVisitLeadResolver` reads through `read_site_visit_briefs` keyed by the visible booked visit ids: lead details keep their per-opportunity cache and authoritative-empty semantics; a successful response also yields the set of still-readable visit ids, and `CalendarViewModel` drops booked visits outside that set (last successful set stands offline).
- FAB: users with `canConvertAny` keep "Book Site Visit" (START NOW / BOOK A VISIT); users with only `site_visits.capture` get "Start Site Visit" → capture directly.
- Capture screen gates for users without authority on the bound lead: hide lead search/attach (needs view), CREATE LEAD (needs create), CREATE PROJECT NOW (needs convert on the lead), stage card (needs edit on the lead → no stage command queued, no "review lead stage" toast), address edit persisting to the lead (needs edit), DISCARD/DELETE of an assigned visit (needs lead edit).

## Delivery

- Server: applied directly (low-tenant prod, md5-guarded), proved with rolled-back role-play transactions as an assigned crew member and as a non-assigned crew member.
- Web: branch + tests; push/merge = Jackson's go.
- iOS: code + unit tests on a branch; built by the bug-reports PM session (worker sessions do not run xcodebuild). Reaches crews at the next App Store release; Jackson's phone at his next Xcode build after merge.
- Shipped iOS 3.0.5 after the server change: assigned lead visits sync down and appear on Schedule; opening them still needs the new app build. No regression for existing users.
