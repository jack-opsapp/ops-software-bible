# SYSTEMS REPAIR — Master Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use `custom-skills:executing-plans` to implement this plan task-by-task. Before ANY task, read the four audit records listed under "Source of Truth" — they carry the line-level evidence this plan is built on. Audit line numbers are anchors from 2026-07-28/29; re-verify against current code before editing (files drift; findings don't).

**Goal:** Repair every defect found by the 2026-07 SYSTEMS AUDIT (photos, settings, sync, database) in seven ordered waves — data-loss and security first, performance second, discipline and honesty third, hygiene last.

**Architecture:** No new systems. Every fix routes existing features into the machinery the audit proved sound: the SyncOperation op-log for offline writes, the web dispatch route for notifications, StorageProfiler + oldest-project-first eviction for photos, RLS RESTRICTIVE pattern for tenancy. The disease was features built AROUND good machinery; the cure is plugging them IN.

**Tech Stack:** iOS (SwiftUI/SwiftData, `ops-ios/OPS/`), Web (Next.js 15, `ops-web/`), Supabase prod `ijeekuhbatykdomumfjx` (MCP tools), OneSignal, S3 via ops-web presign.

**Design System:** `ops-design-system/project/DESIGN.md` + `MOBILE.md`; iOS tokens `ops-ios/OPS/Styles/OPSStyle.swift`. Zero hardcoded values in any UI task.

**Required Skills (load per task type):** `custom-skills:executing-plans` (all), `ops-design` + `custom-skills:mobile-ux-design` + `custom-skills:audit-design-system` (any iOS UI), `ops-copywriter:ops-copywriter` (any user-facing copy), `superpowers:test-driven-development` (all code), `superpowers:verification-before-completion` (all), `supabase:supabase` + `supabase:supabase-postgres-best-practices` (all DB work).

---

## Source of Truth (read before executing)

Auto-memory dir: `/Users/jacksonsweet/.claude/projects/-Users-jacksonsweet-Projects-OPS/memory/`

1. `project_photo_storage_audit.md` — photo lag/leak/eviction findings
2. `project_systems_audit_initiative.md` — P1 settings findings + wave summary
3. `project_systems_audit_p2_sync_findings.md` — RECONCILED sync audit (two independent passes merged)
4. `project_systems_audit_p3_database_findings.md` — database audit + Jackson's photo-permission policy

**Bug rows to update on fix (bug_reports):** `ef5a69e6` (calendar silent loss, urgent) → W2-1; `241830b2` (deletion/export cascade, urgent) → W1-6; `ba6a5b79` (open edge fns, urgent) → W1-1; `1154fe67` (photo grants, high) → W1-4 + W2-3.

## Decisions Log (Jackson — locked, do not relitigate)

- **2026-07-28:** Audit everything before fixing; one coordinated repair wave.
- **2026-07-29 (photo permissions, recorded in P3 findings §3):** crews CAN toggle client visibility on any company photo; crews CAN soft-delete OWN photos only (`uploaded_by` = requester); admins delete any via existing paths; hard DELETE stays denied.
- **2026-07-29 (expenses):** BUILD TRUE OFFLINE EXPENSES — local model + inbound sync + queued writes + offline receipt capture (W4-4). Not the honest-online-only option.
- **2026-07-29 (wave GO):** approved contingent on this document existing. It exists; the wave is live.

## Drift Guards (every executor, every task)

1. **Additive-only schema** between iOS releases: new nullable columns and new tables only. NO renames, drops, or type changes (shipped builds read the old shape). Server-side policies/grants/functions may change anytime.
2. **Prod DB is low-tenant; direct prod migrations are authorized** for the tasks in this plan (Jackson's wave GO). Verify actual schema via Supabase MCP before every migration — never trust this doc's column names over the live database.
3. **Pushes/deploys require Jackson's explicit go per event.** ops-web main auto-deploys to customers. Commit locally without asking; never push without asking.
4. **Parallel sessions exist.** Never stage files you didn't author (bible working tree is mixed RIGHT NOW). Stage by name. Worktrees for ops-web (never branch-switch the primary checkout); `.spm-local` + Secrets.xcconfig for ios worktrees.
5. **UUID case:** `UUID().uuidString` is UPPERCASE; Postgres is lowercase. Lowercase at generation; normalize on comparison.
6. **App runs as anon role** under the Firebase bridge; `auth.uid()` is unusable in RLS/RPC (non-UUID sub). Policies target anon/public; match by email/firebase_uid/`private.resolve_uid()`.
7. **Verification before completion:** every task ships with proof (test output, SQL result, screenshot). Update the bug row when its defect is fixed.
8. **Spawn naming:** `SYSTEMS REPAIR - P<wave>-<n>` (photos: `PHOTO STORAGE - P1-<n>`). Sub-spawns append `-<subtask>`.
9. **Copy:** any user-visible text goes through `ops-copywriter` (terse, tactical, no exclamation points).

---

# WAVE 1 — Server-side, immediate (no app release; all fixes reach shipped builds instantly)

### W1-1: Kill the open destructive edge functions
**Defect (P3 §2, bug ba6a5b79):** `delete-user` lets ANY Supabase-auth session soft-delete any user + delete their auth account (no admin/company check). `terminate-employee` lets an admin of company A strip users in ANY tenant (target membership never checked). Both `verify_jwt=false`, CORS `*`, ZERO callers in current ios/web/site code.
**Fix:** Replace both function bodies with a tombstone that returns `410 Gone` and logs the caller (deploy via `mcp deploy_edge_function`; there is no delete tool — tombstone IS the kill). Do NOT harden-and-keep: zero callers means the correct end-state is dead.
**Steps:** (1) `list_edge_functions` + `get_edge_function` both — archive current bodies into `ops-software-bible/migrations/graveyard/` with a README. (2) Grep ios/web/site/functions once more for invocations — expect zero; abort and escalate if found. (3) Deploy tombstones with `verify_jwt=true`. (4) Invoke each unauthenticated + authenticated — expect 401/410. (5) Update bug ba6a5b79 (resolved + evidence). Commit archive to bible.

### W1-2: Un-break AR-deck estimates (one additive column)
**Defect (P3 landmines):** `CreateEstimateDTO.notes` has no backing column; `DeckBuilderViewModel.swift:4177` sends non-nil `arNote` → PGRST204 → **every AR-measured deck fails estimate creation today**. Manual decks pass only because nil is omitted.
**Fix:** `ALTER TABLE estimates ADD COLUMN notes text;` (nullable, additive-safe). Shipped builds unbreak instantly; web unaffected.
**Steps:** (1) Verify via `execute_sql` information_schema that `estimates.notes` is absent. (2) `apply_migration` named `add_estimates_notes_for_ios_ar_decks`. (3) Prove: insert a test estimate row with notes via SQL, then delete it. (4) Bible 09/03 note the new column.

### W1-3: Revive iOS feedback (feature_requests policy)
**Defect (P3):** INSERT policy is `auth.role()='authenticated'`; the Firebase bridge is anon → both iOS flows dead (`ReportIssueView.swift:167`, `WhatsNewView.swift:255`; zero "iOS mobile" rows ever).
**Fix:** Migration: drop the legacy policy; recreate INSERT for anon+authenticated with tenancy check consistent with sibling tables (use `private.get_user_company_id()` pattern; verify how `bug_reports` INSERT policy is written and mirror it).
**Steps:** verify current policy text via `pg_policies` → write migration → apply → prove with an anon-key REST insert (then delete the test row) → bible 03 policy note.

### W1-4: Photo grants per Jackson's decided policy
**Defect (P3 §3, bug 1154fe67):** anon/authenticated have INSERT,SELECT only on `project_photos`; all three iOS UPDATE paths fail 42501 (soft-delete ×2, `is_client_visible`). Evidence: 0/826 rows ever client-visible; iOS "deleted" photos resurface.
**Fix (policy as decided):** column-scoped `GRANT UPDATE (deleted_at, is_client_visible, caption) ON project_photos TO anon, authenticated;` + write-guard trigger (repo `trg_*_00_write_guard` naming pattern — find an existing one via `pg_trigger` and copy its shape) enforcing: `is_client_visible`/`caption` changes allowed company-wide; `deleted_at` changes require `lower(uploaded_by) = lower(private.resolve_uid()::text)` (uploaded_by is text; normalize case) OR the requester's permission check for admin paths (`private.current_user_has_permission(...)` — verify the exact helper signature before use). Keep the RESTRICTIVE DELETE-denied policy untouched.
**Steps:** verify grants (`information_schema.role_table_grants`) → verify helper fn signatures → migration → test as anon: visibility toggle on another user's photo (expect OK), soft-delete another's (expect reject), soft-delete own (expect OK) → update bug 1154fe67 → bible 03/07.

### W1-5: Quiet hours into the web dispatch gate
**Defect (P1 §8):** `ops-web/src/app/api/notifications/dispatch/route.ts` checks per-event prefs but NOT `quiet_hours_start/end` — no sender anywhere respects quiet hours; settings copy promises silence.
**Fix:** In dispatch, after fetching `notification_preferences` (route already selects the table at ~:150-156), also select quiet-hours columns; suppress PUSH for recipients inside their window (midnight-spanning logic — port the correct comparison from iOS `NotificationManager.shouldSendNotification:846-865`); email unaffected; add a `deferred_quiet_hours` log line.
**Steps (worktree, TDD):** failing route test (recipient inside window gets no push, outside does, spanning-midnight case) → implement → tests green → commit. **Deploy needs Jackson's go (W2 batches it).**

### W1-6: Deletion + export cascade rebuild
**Defect (P3 §1, bug 241830b2):** `ops-web/src/app/api/data/{delete-account,export}/route.ts` reference nonexistent `estimate_line_items`/`invoice_line_items` (real: `line_items`) and `tasks` (real: `project_tasks`); errors swallowed per-step; cascade list frozen years ago — misses expenses, project_photos, project_notes, site_visits, sub_clients, follow_ups, activities, calendar_user_events, deck_designs. Deletion reports success while leaving most modern data; export omits tasks and all line items.
**Fix:** Rebuild both routes table-driven: one shared manifest of user-owned tables derived by QUERYING the live schema for user-scoped FKs (document the manifest in the route; add a test that diffs manifest vs live schema so future tables can't silently drop out). No swallowed errors: any step failure → 500 with step named, nothing reported deleted that wasn't.
**Steps (worktree, TDD):** schema query → manifest → failing tests (wrong-table names caught; completeness diff; error propagation) → implement → green → commit → update bug 241830b2. **Deploy with W1-5 on Jackson's go.**

# WAVE 2 — Next iOS build (all client-side; ride one TestFlight/App Store release)

### W2-1: Calendar events onto the op-log (bug ef5a69e6 — THE urgent one)
**Defect (P2 Tier-3 §1):** creates `TimeOffRequestSheet.swift:295-341` + `UserEventSheet.swift:1288/1328` swallow `try? await repo.create` → false success (+ admin notification pointing at a nonexistent row). `DataController+RecurringEvents.syncEditToSupabase(:268+)/syncDeleteToSupabase(:405+)` unconditionally clear `needsSync` after `try?` calls → failed edits REVERT on next pull; failed deletes RESURRECT. `mergeCalendarUserEvent` (DataActor:879-901) skips dirty rows, never prunes ghosts. Not in RecoveryInventory.
**Fix:** Route ALL calendarUserEvent writes through `SyncEngine.recordOperation` (entity already falls to `genericTablePush` — verify payload columns against live `calendar_user_events` schema first; add a dedicated handler only if sanitization demands it). Delete the `try?` direct-sync paths entirely. `needsSync` clears ONLY on op completion. Add calendarUserEvent to RecoveryInventory/PENDING WORK. One-time launch sweep: existing dirty local events → enqueue ops (create-if-absent semantics; `errorIndicatesPrimaryKeyViolation` already handles the already-exists race).
**Steps (TDD):** failing tests — offline create queues op + survives relaunch (virtual-clock pattern per `reference_inbound_router_virtual_clock_deflake`); failed edit does NOT clear needsSync; delete resurrection case; sweep picks up a pre-seeded dirty row → implement → full suite green → update bug ef5a69e6.

### W2-2: Phone-sent pushes respect preferences
**Defect (P1 §7):** 12+ `OneSignalService` methods send directly, zero pref checks; iOS never calls `/api/notifications/dispatch`.
**Fix:** Replace OneSignalService's direct REST sends with calls to the dispatch route (single chokepoint — quiet hours from W1-5 then covers phone events too). Map each of the 12 methods to a dispatch event type; extend dispatch's event-type→preference-key map for any missing types (verify against `channel_preferences` JSONB keys in prod rows). Offline sends: skip silently (a push about an event that will sync later is not worth queuing — in-app rail rows already persist).
**Steps (TDD per method):** contract test against a dispatch stub → migrate methods → delete the direct-send code (no fallback path left behind) → suite green.

### W2-3: iOS photo-delete affordance per policy
**Fix (pairs with W1-4):** scope the delete affordance (`ProjectPhotosGrid` long-press, `ProjectNotesViewModel.swift:593` path) to own-photos for non-admin (permission store, never role names — `feedback_never_filter_by_role`); visibility toggle enabled company-wide; surface the server rejection (until W1-4 lands, UPDATEs fail 42501 — after it, they succeed; test both). Skills: `ops-design`, `mobile-ux-design`, `ops-copywriter` for any new copy.

### W2-4: Payments/estimates landmine defusal
**Defect (P3 landmines):** iOS `PaymentDTO`/`CreatePaymentDTO` carry phantom `reference`/`is_void` (live: `reference_number`, `voided_at/voided_by`) — works only because nil is omitted; voided payments render as normal. Estimate status decoder maps `changes_requested`/`superseded` → DRAFT (portal change-requests invisible); payments `debit_card` → other; activities `site_visit_scheduled` unknown.
**Fix:** DTOs to real columns; decode + RENDER void state (design pass on the payment row — `ops-design`); extend status enums with proper display for the drifted values (copy via `ops-copywriter`); send `payment_date` so backdating works. TDD decode/encode round-trips against live column names (verify via MCP first).

# WAVE 3 — PHOTO STORAGE P1 (the original complaint)

> Full defect detail in `project_photo_storage_audit.md`. Skills: `ops-design`, `mobile-ux-design`, `audit-design-system` on every UI-touching task.

- **W3-1 Lag:** `AllPhotosGalleryView.allPhotoItems` becomes state computed ONCE off-main (recompute on data-change signals, not per-render); kill the per-render disk stats in `storageRow`/cells (cached `onDevice` index + cached usage tally, invalidated by `cacheVersion`); `PhotoDownloadManager.downloadPhoto` disk write + decode + `saveImage` eviction walk OFF the main actor; batch `activeDownloads` @Published updates. Acceptance: gallery interaction stays fluid during an active prefetch of 100+ photos on a 1,500-photo library (measure with Instruments or signpost logs; attach evidence).
- **W3-2 One eviction policy:** delete mtime-based `evictRemoteImagesIfNeeded` ordering; single oldest-project-first policy (reuse `enforceCapacityPolicy` candidate logic) running AUTOMATICALLY at cap (prefetch pause→notify stays, but on-demand saves evict correctly); pins respected; candidates from the MERGED gallery list (not legacy CSV).
- **W3-3 Leak:** delete `local://` originals after successful drain (`syncImagesForProject` + handoff heal path); one-time launch sweep for orphaned local files whose URL no longer appears in any gallery/queue; `clearRemoteImageCache` extended to them. Acceptance: sweep logs reclaimed bytes; new drains leave zero orphans.
- **W3-4 Bandwidth:** pass `remoteThumbnailURL` in `AllPhotosGalleryView` + `ProjectPhotosGrid` (rows already carry `thumbnailURL`); disk tile path uses `downsample(data:)` (ImageIO) not full-decode; prefetch from `mergedGalleryImageURLs`.
- **W3-5 Viewer:** `SinglePhotoView`/`GalleryZoomablePhotoView` async load (no main-thread disk reads/decodes in `onAppear`, no main-thread `saveImage` in completions).

# WAVE 4 — Sync discipline

- **W4-1 Inventory writes → op-log:** every write site (`InventoryFormSheet:788/850/908`, `BulkQuantityAdjustmentSheet:312`, `BulkTagsSheet:308-361`, `InventoryView:781`, delete path :1004) records ops (genericTablePush handles inventory_* tables — verify payload column allowlists against live schema). Fix the lying comment. TDD: offline edit → relaunch → drain.
- **W4-2 Catalog writes → op-log:** same treatment for catalog sheets; resolve `TODO(catalog-outbound)` (OutboundProcessor:650, DataActor:4528).
- **W4-3 Leads single discipline:** one persistence model for opportunities (SwiftData as truth; PipelineViewModel's detached in-memory list reads from it; kill the triple-write divergence — see P2 "LEADS TRIPLE-DISCIPLINE" for the three sites); prune ghosts; realtime updates the store, not just the in-memory list.
- **W4-4 OFFLINE EXPENSES (Jackson-approved build):** local `Expense`/`ExpenseCategory`/`ExpenseBatch` @Models + DataActor inbound sync sections (mirror the estimates pattern at DataActor:1616-1712) + writes through op-log (the atomic RPC at ExpenseViewModel:300 needs an offline-queueable equivalent — design decision for the executor: queue the RPC call itself as an op payload) + receipt photos through ImageSyncManager's existing queue + ExpenseViewModel reads local-first. Registry entries stop being dead. UI states for queued/unsynced per design system. This is the largest single task — spawn as its own `SYSTEMS REPAIR - P4-4` with a sub-plan.
- **W4-5 Queue purge starvation:** `cleanupCompletedOperations` (currently BGProcessing-only, SyncEngine:223) also runs on launch + foreground; add a test that completed ops older than retention are gone after a launch cycle.

# WAVE 5 — Settings truth (P1 findings §1-6, 9)

Implement for real: **historicalDataMonths** actually windows delta/full sync fetches (DataActor fetch predicates; "All" = current behavior); **auto-snapshot scheduler** honoring `SnapshotFrequency` (BGTask or launch-check against `lastSnapshotDate`); **matchInvoiceTerms** consumed by `ProjectReviewQuery`/`OverdueProjectDetector` (invoice net-terms replace fixed threshold when on — read the invoice terms field, verify column exists); **mapAutoZoom** read by `ProjectMapView` camera logic. REMOVE: `syncOnLaunch` + `backgroundSyncEnabled` toggles (delete rows + keys + the lying header comment). **QB card** reads real connection state (same source Books/web uses — `accounting_connections`-family; verify table name via MCP). Orphans deleted: `NotificationSettingsControls.swift`, `ProjectNotificationPreferences.swift`, `ComingSoonView.swift`, `mapTrafficDisplay` phantom. Copy changes via `ops-copywriter`.

# WAVE 6 — Security/RLS batch (server-side, anytime)

Per P3 §RLS: (1) `projects.role_scope_read` PERMISSIVE→RESTRICTIVE to match clients/expenses/invoices — **verify with a matrix test across an assigned-only user before AND after; this can hide projects from users currently (wrongly) seeing them — that is the intent, but prove no legitimate role loses access**; (2) migrate the 9 legacy `auth.role()` policies to bridge-compatible equivalents (feature_requests already done in W1-3); (3) `course_grades` SELECT scoped to owner+admin; (4) `email_log` INSERT tightened; (5) SECURITY DEFINER sweep — audit EXECUTE grants on the 144 anon/authenticated-executable fns, revoke PUBLIC default, grant per-need (spot-check bodies of anything destructive); (6) pin `search_path` on the 4 flagged fns; (7) enable leaked-password protection. Each its own migration + proof query.

# WAVE 7 — Hygiene + docs (last, after behavior is fixed)

- **Dead code purge (iOS):** PhotoProcessor + LocalPhoto (NOTE: PendingWorkView:430/444 renders LocalPhoto rows and BGProcessing drains it — remove those hookups in the same commit), TimeEntry (+logout wipe DataController:1407), FormSubmission, SignatureCapture (verify zero producers again at execution time), TaskStatusOption no-op sync (:2741), `performSyncedOperation` (deprecated, zero callers, :3540-3614), legacy Inbound/OutboundProcessor retirement (currently byte-identical rollback twins behind `feature.useDataActor` — retire only after W2/W4 prove stable on DataActor for a full release cycle; this is the ONE deliberately deferred item, gated not forgotten), dead registry entries for removed types.
- **Dead tables:** drop `valid_status_transitions`, `location_history`, `ops_contacts`, `humor_queue` (re-verify zero refs at execution; export row snapshots to bible/migrations/graveyard first).
- **Web:** remove `pipeline_references` queries (admin-queries.ts ×5 + 2 pages — admin pipeline stats need a real source or removal; check with Jackson only if the stats widget itself should die), `task_types_v2` → `task_types` (financial-intelligence-service.ts:382,493), regen database.types.ts (app_messages ghost fields).
- **Bible refresh:** index the 101 unmentioned tables (families: core-product ones fully; learn/shop/ads as one-line registry entries), fix the 2 wrong claims (ch.10 gmail_scan_jobs; ch.04 invoice_line_items), add verified column omissions (P3 list), update 06/07 for everything this plan changed. Regenerate AGENTS.md via `scripts/sync-agent-docs.sh` if CLAUDE.md files change.

---

## Definition of Done (program level)

1. All four bug rows resolved with evidence. 2. Offline conformance: every entity either queues durably or fails loudly — zero silent-strand paths (re-run the P2 tier classification; Tier 3 must be empty). 3. Settings: every control traced to a live consumer (re-run the P1 sweep; dead count = 0). 4. Photos: fluid under prefetch load, one eviction policy, zero orphaned bytes. 5. Notifications: one preference-checking chokepoint, quiet hours honored by every sender. 6. DB: no phantom columns in any client DTO, RESTRICTIVE tenancy consistent, advisors clean of the named items. 7. Bible current (drift list empty). 8. Every wave's work committed atomically; deploys/pushes each had Jackson's explicit go.
