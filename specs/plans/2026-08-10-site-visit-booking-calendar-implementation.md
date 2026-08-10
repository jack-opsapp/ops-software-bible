# Site Visit Booking + Calendar Integration — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use `custom-skills:executing-plans` to implement this plan task-by-task.
> **Spec (read first, it is authoritative):** `ops-software-bible/specs/2026-08-10-site-visit-booking-calendar-design.md`
> **MCP briefing (do NOT implement — it belongs to the agent-control-plane agent):** `specs/2026-08-10-site-visit-mcp-capability-briefing.md`

**Goal:** Site visits become bookable appointments that appear on OPS calendars (iOS + web) and flow one-way to Apple/Google personal calendars, with server-driven heads-up/START prompts and an on-device time-to-leave alert.

**Architecture:** Additive columns give `site_visits`' inert scheduling fields real meaning behind a `booked_at IS NOT NULL` discriminator. Three public RPCs (`book_site_visit`, `reschedule_site_visit`, `cancel_site_visit_booking`) are the ONLY write path for bookings on every surface. A 5-minute Vercel cron fires prompts (rail + OneSignal by external id) with idempotency carried entirely by `notifications.dedupe_key`. Google sync drains the existing (dormant) `google_calendar_sync_queue`; Apple sync extends the existing `CalendarMirrorService`.

**Tech stack:** Supabase (SQL migrations + RPCs), Next.js 15 (`ops-web`), SwiftUI/SwiftData (`ops-ios`), OneSignal, Google Calendar API, EventKit, MapKit.

**Design system:** `ops-design-system/project/DESIGN.md` (+ `mobile/MOBILE.md` for iOS). Web tokens via the project Tailwind tokens (radius convention: 5px = bare `rounded`); iOS via `OPSStyle`. Zero hardcoded values.

**Required skills for executors:** `ops-design`, `custom-skills:mobile-ux-design` (iOS tasks), `frontend-design:frontend-design` + `custom-skills:interface-design` (web tasks), `ops-copywriter:ops-copywriter` (ALL user-facing strings), `superpowers:test-driven-development`, `custom-skills:audit-design-system` (before any UI phase is called done).

**Ground rules (non-negotiable):**
- Every booked-visit read filters `booked_at IS NOT NULL AND deleted_at IS NULL`. Never trust `status='scheduled'` alone (it means *open*, not *booked* — ~20 legacy rows carry junk `scheduled_at`).
- iOS↔Supabase schema changes are **additive-only** (shipping-app constraint).
- Actor resolution in RPCs: copy the pattern from `public.complete_site_visit_guarded` (`migrations/20260731235533_site_visit_cloud_sync.sql:659`) — `auth.uid()` is unusable under the Firebase bridge.
- Permission gates are granular permissions only (the existing `private.current_user_can_edit_site_visit` boundary), never role names.
- Prod is low-tenant: direct prod migrations via MCP `apply_migration` are the accepted path; mirror every migration file into `ops-software-bible/migrations/` in the same session.
- OPS-Web work happens in a worktree with its own `npm ci` — never branch-switch the primary checkout.
- Commit after each task (conventional commits, no AI attribution). Sibling sessions run in parallel — stage by name only.

---

## Phase 1 — Database + RPCs

### Task 1.1: Migration — booking columns + prompt/dedupe infrastructure

**Files:**
- Create: `ops-software-bible/migrations/<timestamp>_site_visit_booking.sql` (apply via Supabase MCP `apply_migration`, name `site_visit_booking`)

**Steps:**
1. Verify current state (MCP `execute_sql`): `site_visits` has no `booked_at`; check whether a unique index exists on `notifications.dedupe_key` (as of 2026-08-10 it does not).
2. Write and apply:

```sql
-- Booking discriminator + per-booking reminder override (additive; iOS-safe)
alter table public.site_visits
  add column if not exists booked_at timestamptz,
  add column if not exists reminder_lead_minutes int
    check (reminder_lead_minutes is null or reminder_lead_minutes between 0 and 1440);

comment on column public.site_visits.booked_at is
  'Non-null = this visit is a real appointment; scheduled_at is then meaningful. NULL = walk-up/legacy (scheduled_at is junk, defaulted to created_at).';

-- Booked-visit scheduling queries (calendars, prompt cron, MCP reads)
create index if not exists site_visits_booked_window_idx
  on public.site_visits (company_id, scheduled_at)
  where booked_at is not null and deleted_at is null;

-- Per-user default heads-up lead (NULL = product default 30)
alter table public.notification_preferences
  add column if not exists site_visit_reminder_lead_minutes int
    check (site_visit_reminder_lead_minutes is null or site_visit_reminder_lead_minutes between 0 and 1440);

-- Prompt idempotency backbone
create unique index if not exists notifications_dedupe_key_uidx
  on public.notifications (dedupe_key) where dedupe_key is not null;
```

3. Before creating `notifications_dedupe_key_uidx`, check for existing duplicate non-null `dedupe_key` values; if any exist, keep the newest row's key and null the older ones in the same migration (write the exact UPDATE after inspecting — do not guess).
4. Regenerate web types later in Task 5.1 (the file is already stale; one regen covers all).
5. Mirror the SQL into `ops-software-bible/migrations/` and commit (`feat(db): site visit booking columns + prompt dedupe index`).

### Task 1.2: RPC `book_site_visit` (TDD via SQL)

**Files:**
- Create: `ops-software-bible/migrations/<timestamp>_site_visit_booking_rpcs.sql`

**Steps:**
1. Read `public.complete_site_visit_guarded` and `public.move_opportunity_stage` in full first (MCP `execute_sql` on `pg_get_functiondef`). Reuse their actor resolution, company-boundary, and permission checks verbatim.
2. Write the failing tests first as a SQL script run via `execute_sql` against throwaway rows in a transaction you roll back (prod is low-tenant; never commit test rows). Cases: happy path; cross-company denial; permission denial; `p_scheduled_at` in the past (>5 min grace) rejected; second booking while one is `status='scheduled'` rejected; booking allowed when prior booked visit is `in_progress`/`completed`/`cancelled`; `new_lead → qualifying` nudge fires exactly once; activity row created with `type='site_visit_scheduled'`; google queue rows enqueued only for assignees with a Google `email_connections` row.
3. Implement:

```sql
create or replace function public.book_site_visit(
  p_opportunity_id uuid,
  p_scheduled_at timestamptz,
  p_duration_minutes int default 60,
  p_assignee_ids text[] default null,
  p_reminder_lead_minutes int default null
) returns uuid
language plpgsql security definer set search_path = public, private
```

Behavior (in order): resolve actor + company (guarded pattern) → assert edit boundary via `private.current_user_can_edit_site_visit` → validate inputs (`p_scheduled_at > now() - interval '5 minutes'`, duration 15–480) → one-open-booking check (`for update` on the opportunity's booked `scheduled` visits) → insert `site_visits` row (`status='scheduled'`, `booked_at=now()`, `created_by=actor`, `assignee_ids=coalesce(p_assignee_ids, array[actor])`) → insert `activities` row (`type='site_visit_scheduled'`, subject `'Site visit booked'`, content carrying the ISO time; link `site_visits.activity_id`) → if opportunity stage is `new_lead`, advance to `qualifying` via the existing stage RPC/update path used by `move_opportunity_stage` → enqueue one `google_calendar_sync_queue` row (`operation='upsert'`) per assignee having a non-revoked Google `email_connections` row → return the visit id.

4. Run the test script; all green. Mirror + commit.

### Task 1.3: RPCs `reschedule_site_visit` + `cancel_site_visit_booking`

Same file/pattern as 1.2. Reschedule: only on `booked_at IS NOT NULL` visits with status `scheduled` (started visits can't move); updates time/duration/assignees/override; logs `site_visit_scheduled` activity ("Site visit rescheduled"); enqueues `upsert` queue rows; the changed `scheduled_at` re-arms prompts by construction (dedupe key includes the epoch). Cancel: status → `cancelled`, activity logged, queue `delete` rows enqueued for any assignee connection that has a `google_calendar_event_id` written back. Both idempotent (cancel of cancelled = no-op success). TDD as in 1.2. Mirror + commit.

---

## Phase 2 — Prompt engine (ops-web, worktree)

> **Skills:** `ops-copywriter` for every push/rail string. No UI in this phase.

### Task 2.1: Shared query — due prompts

**Files:**
- Create: `ops-web/src/lib/site-visits/prompt-engine.ts`
- Test: `ops-web/src/lib/site-visits/__tests__/prompt-engine.test.ts`

Pure function first, TDD: given a visit row (+ per-assignee lead minutes) and `now`, return which prompts are due per assignee:
- heads-up due when `scheduled_at - lead <= now < scheduled_at`
- start due when `scheduled_at <= now < scheduled_at + 15 min`
- nothing when status ≠ `scheduled`, `booked_at` null, or `deleted_at` set
- lead = `visit.reminder_lead_minutes ?? user.site_visit_reminder_lead_minutes ?? 30`
- dedupe keys exactly `site_visit:<visitId>:heads_up:<userId>:<epoch(scheduled_at)>` / `...:start:...`

Cover the reschedule re-arm case explicitly (same visit, new epoch → new keys). Run `npx vitest run src/lib/site-visits` (or the repo's configured runner — check `package.json` first). Commit.

### Task 2.2: Cron route `/api/cron/site-visit-prompts`

**Files:**
- Create: `ops-web/src/app/api/cron/site-visit-prompts/route.ts`
- Modify: `ops-web/vercel.json` (add `{"path": "/api/cron/site-visit-prompts", "schedule": "*/5 * * * *"}` — full-day, NOT the `13-23,0-4` window: appointments are time-critical)
- Modify: `ops-web/src/lib/notifications/onesignal.ts` (extend the canonical helper to target `include_aliases.external_id` — do NOT touch the legacy `src/lib/integrations/onesignal.ts` duplicate)

Pattern-match `src/app/api/cron/unsnooze/route.ts`: GET, `Bearer CRON_SECRET`, `getServiceRoleClient()`, `maxDuration = 60`, per-run cap. Flow: select candidate visits via the Task 1.1 partial index (window `now - 20min .. now + 24h` is plenty) joined to assignees' `notification_preferences` → run the Task 2.1 engine → for each due prompt: gate on `push_enabled` + `channel_preferences['site_visit_reminder']` (default true; visit prompts intentionally bypass quiet hours) → insert `notifications` row (`type='site_visit_reminder'`, `dedupe_key`, `actionUrl` to the lead, `actionLabel: 'OPEN LEAD'` / `'START VISIT'`) with `on conflict (dedupe_key) do nothing` → on successful insert only, send OneSignal push (external id = user id; data payload `{deep_link_type: 'site_visit_start'|'site_visit_heads_up', leadId, siteVisitId}`). Copy (ops-copywriter register): heads-up `"Site visit in 30 min — <lead name>"` / body address; START `"Site visit — <address>"` body `"Start now?"`.

Test: route-level test with mocked Supabase/OneSignal covering gate-off, dedupe conflict (no push), and started-visit skip. Add `site_visit_reminder` to the web `NotificationType` union (`notification-service.ts`) and the rail's icon mapping. Run repo verification per `ops-web/CLAUDE.md` (lint gates tests in CI — run tests directly). Commit.

---

## Phase 3 — Google Calendar sync (ops-web, same worktree)

> **Skills:** `interface-design` + `ops-design` for the settings affordance; `ops-copywriter` for consent copy. Verified: no calendar scope exists on any grant — re-consent is mandatory.

### Task 3.1: Incremental consent

**Files:**
- Modify: `ops-web/src/app/api/integrations/gmail/route.ts` + `callback/route.ts` — accept `?include_calendar=1`; when set, request the existing mail scope **plus** `https://www.googleapis.com/auth/calendar.events` with `include_granted_scopes=true`; persist the full granted scope list into `email_connections.granted_scopes` on callback (today it records only mail).
- Settings surface: one compact row in the existing integrations/settings area (find the Gmail connection card's home first; follow its established layout): status line `CALENDAR SYNC — OFF` with a CONNECT affordance → OAuth round-trip → `CALENDAR SYNC — ON`. One entry point, state-aware, no permanent acreage (design-judgment rule).

Test: callback unit test asserting scopes persistence. Commit.

### Task 3.2: Queue drain worker `/api/cron/google-calendar-sync`

**Files:**
- Create: `ops-web/src/app/api/cron/google-calendar-sync/route.ts` (+ vercel.json entry, `*/5 * * * *` full-day)
- Create: `ops-web/src/lib/site-visits/google-calendar.ts` (event build + Google API client using the connection's refresh token; reuse the token-refresh helper the Gmail sync already uses — find it, don't duplicate)

Flow per pending queue row (`status='pending' and next_attempt_at <= now()`, `for update skip locked` semantics via `select ... limit N`): load connection → if `granted_scopes` lacks `calendar.events` → `status='skipped'`, `skip_reason='missing_calendar_scope'` (never an error) → else upsert/patch/delete the event on calendar `primary`; event: summary `"Site visit — <lead name>"`, location = lead address, description = OPS deep link, times from `scheduled_at`/`duration_minutes`. Write back `google_calendar_event_id/-_id/-synced_at` on the visit; queue row → `done`. Failures: increment `attempts`, exponential `next_attempt_at`, `last_error`; `attempts >= 5` → `status='failed'`. Revoked grant (401/invalid_grant) → `skipped`/`grant_revoked`.

Test: worker logic with mocked Google client (upsert, patch on reschedule, delete on cancel, missing-scope skip, retry backoff). Commit. **Cost note for Jackson's summary: Google Calendar API and the two new crons are $0 at OPS volume — no new paid services anywhere in this build.**

---

## Phase 4 — iOS (ops-ios, worktree; remember `.spm-local` + `Secrets.xcconfig` gotchas)

> **Skills:** `custom-skills:mobile-ux-design` + `ops-design` (+ `MOBILE.md`) before ANY screen; `ops-copywriter` for every string; house component library only (stock Picker/Stepper/tinted Toggle are banned). Motion: the single OPS curve, `prefers-reduced-motion` honored. Verify per `feedback_no_xcodebuild` caveats (check parallel sessions; xcresult over stdout — `xcodebuild` prints SUCCEEDED on zero tests).

### Task 4.1: Model + sync (additive)

`ops-ios/OPS/DataModels/Supabase/SiteVisit.swift`: add optional `bookedAt: Date?`, `reminderLeadMinutes: Int?` (beware the Swift let-default memberwise/Decodable trap — follow the existing optional-field pattern in this file). Thread through `SiteVisitSyncPayload`/`SiteVisitServerMerge` (encode/decode round-trip test in the existing sync test suites). `isBookedAppointment` computed property = `bookedAt != nil`. TDD in the site-visit sync test files. Commit.

### Task 4.2: Booking service

`ops-ios/OPS/Services/SiteVisitBookingService.swift` (new): thin async wrappers calling the three RPCs via the existing Supabase client pattern, mapping errors to user-presentable cases (`bookingConflict`, `permissionDenied`, `offline`). Booking requires connectivity (RPC-only by design — side effects are server-owned); offline → clear terse error, no local queueing. Unit tests with the repo's Supabase mock harness. Commit.

### Task 4.3: NOW / BOOK branch + booking sheet

**Files:** `LeadsTabView.swift:266` (VISIT chip), `LeadDetailView.swift:418`, `DaySheet/LeadSiteVisitPanel.swift`, `Sheets/AddLeadSheet.swift:349`; new `Views/SiteVisits/BookSiteVisitSheet.swift`.

Each lead-attached visit affordance presents a two-option branch (confirmationDialog-equivalent from the house component library): **NOW** → existing capture path unchanged; **BOOK A VISIT** → sheet. Sheet fields top-to-bottom: date, time, duration, WHO'S GOING (defaults booker; company members picker), HEADS-UP row (default from settings, per-booking override). Primary CTA `BOOK VISIT` (single accent use). If the lead already has an open booking, the sheet opens in reschedule mode showing it (one entry point, state-aware — never two stacked bookings offered). FAB stays immediate-capture only. Existing-booking state on lead surfaces: the panel/row shows `BOOKED — THU 10:00` instead of the bare VISIT verb. Snapshot tests via the `FixedSizeSnapshot` harness; flow tests for both branches. Commit per surface touched.

### Task 4.4: Calendar third source

`ops-ios/OPS/ViewModels/CalendarViewModel.swift`: fetch booked visits (`isBookedAppointment`, not cancelled) for the visible period alongside tasks + user events; distinct site-visit chip treatment from `OPSStyle` tokens (mobile status-tag token pattern — fill+ink move together). Tap → visit detail context (lead, time, RESCHEDULE / CANCEL / START-when-today). Commit.

### Task 4.5: EventKit mirror

`ops-ios/OPS/Services/CalendarMirrorService.swift` + `CalendarMirrorMap.swift:16`: fill the reserved `siteVisit` `MirrorSource`. Mirror booked, non-cancelled visits assigned to the current user: title `Site visit — <lead>`, location = lead address, window from `scheduled_at`/`duration_minutes`. Same reconcile-and-revert drift handling as existing sources; cancellation/reschedule reconciles on next pass. Extend the mirror test suite. Commit.

### Task 4.6: Time-to-leave alert

New `ops-ios/OPS/Services/SiteVisitDepartureAlertScheduler.swift`: on foreground + the existing BG refresh hook, for today's booked visits assigned to me with a lead address: geocode (CLGeocoder), `MKDirections` driving ETA from current location, schedule local notification id `site-visit-departure-<id>` at `scheduled_at − ETA − 5min` (only if in the future); copy: `"Time to leave — <lead name>"` / `"~<n> min drive. Visit at <time>."`. Cancel on start/cancel/reschedule/unassign. No location permission or no address → silently absent (never prompt for location just for this; use the app's existing location authorization state). Route through `NotificationManager` policy (this alert also bypasses quiet hours). Unit-test the scheduling math with injected ETA/clock. Commit.

### Task 4.7: Push routing + START card

- `NotificationManager.routeByType`/`routeToScreen` (`:1180`, `:1224`): handle `site_visit_start` / `site_visit_heads_up` payloads → open lead, START deep-link lands in `SiteVisitCaptureView` with the lead bound (reuse the `activeSiteVisitLead` cover mechanism).
- START card: on the visit day from the morning, a card at the top of the day sheet (and leads tab when day sheet isn't the entry surface) — lead name, time, address, START. Persists until started/dismissed/day-end; dismissal is per-visit and kills the card only, never the pushes. Terse copy register (`SITE VISIT — 10:00`, not a paragraph).
- Full-suite iOS verification: build + targeted test classes; confirm counts from the xcresult, screenshots of sheet/calendar/card for the proof pack. Commit.

---

## Phase 5 — Web surface (same ops-web worktree)

> **Skills:** `frontend-design` + `interface-design` + `ops-design`; tables/calendar follow existing OPS-Web conventions (full-bleed, metrics scroll away); `audit-design-system` before calling the phase done.

### Task 5.1: Types regen + service

Regenerate `database.types.ts` (Supabase MCP `generate_typescript_types`) — this also picks up the missing `site_visit_*` satellites. Extend `src/lib/api/services/site-visit-service.ts` with `bookSiteVisit`/`rescheduleSiteVisit`/`cancelSiteVisitBooking` (RPC calls) + `getBookedVisitsInRange` (guarded query). Delete the two dead components (`create-site-visit-modal.tsx`, `site-visit-detail.tsx`) — they describe a flow that never existed. Unit tests. Commit.

### Task 5.2: Booking modal on pipeline lead detail

Same field set and one-open-booking behavior as iOS (4.3), same copy. Entry point on the lead detail next-steps area (where the read-only visit references already live: `pipeline-detail-next-steps.tsx:175`). Booked state renders as `BOOKED — THU 10:00` with reschedule/cancel behind it. Commit.

### Task 5.3: Calendar third source

`src/app/(dashboard)/calendar/` + `calendar-service.ts`: render booked visits alongside tasks/user events in day/week/month (distinct treatment via tokens; **excluded from drag-reschedule, cascade, auto-schedule, and the unscheduled tray** — visits are not tasks). Click → compact visit popover (lead link, reschedule, cancel). Live-verify in the worktree preview (`DEV_BYPASS_AUTH` recipe), screenshots for the proof pack. Run `custom-skills:audit-design-system` over all new web UI. Commit.

---

## Phase 6 — Bible + wrap

1. Update `10_JOB_LIFECYCLE_AND_DATA_RELATIONSHIPS.md` (site-visit lifecycle: booking is now real — replace the aspirational BOOK section with as-built), `03_DATA_ARCHITECTURE.md` (new columns), `04_API_AND_INTEGRATION.md` (three RPCs + two crons), `07_SPECIALIZED_FEATURES.md` § 14 (`site_visit_reminder` notification type). Cite migration filenames. Commit.
2. Confirm the MCP briefing doc still matches as-built RPC signatures; amend if anything drifted, and tell Jackson it's ready to hand over (it references `rolloutFlag` sequencing so the other agent can land manifest entries before the RPCs go live).
3. Proof pack for Jackson: booking sheet → phone calendar (OPS + Apple) screenshots, Google event screenshot after consent, push screenshots (heads-up, START, time-to-leave), START card, web calendar. Plain-language summary, no mechanics.

## Execution notes

- Phases 1→2→3 are sequential (RPCs feed the cron; consent feeds the drain). Phase 4 and Phase 5 can run in parallel worktrees **after Phase 1 lands**, per the parallel-session rules. Suggested spawn titles: `SITE VISIT BOOKING - P1-1` (db+rpcs), then `P2-1` (prompt engine + google), `P4-1` (iOS), `P5-1` (web).
- Pushing `ops-web` main deploys to customers — everything merges locally and holds for Jackson's explicit GO, per standing policy. (Local `ops-web` main is currently ~72 behind origin — executors must fetch/rebase their worktree from origin/main, not local main.)
- No new paid services anywhere in this plan. Vercel crons + Google API + MapKit + OneSignal are all $0 at OPS volume on existing plans.
