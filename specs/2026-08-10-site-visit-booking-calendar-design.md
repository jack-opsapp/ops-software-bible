# Site Visit Booking + Calendar Integration (2026-08-10)

> **Status:** Approved design. Nothing in this document is implemented yet.
> Companion doc: `2026-08-10-site-visit-mcp-capability-briefing.md` (handoff to the agent-control-plane MCP agent).

## 1. Problem

Site visits are a mature capture system (iOS, offline-first, `site_visits` + artifact/checklist/identity satellites) but **booking does not exist**. `site_visits.scheduled_at` is NOT NULL yet never meaningfully written — `SiteVisitCaptureViewModel.createVisit()` sets no date, so the model initializer falls back to `scheduledAt = createdAt` (`ops-ios/OPS/DataModels/Supabase/SiteVisit.swift:67`). `status = 'scheduled'` means *open*, not *booked* (documented in `ops-ios/OPS/Views/Leads/DaySheet/LeadSiteVisitPanel.swift:33-36`). Visits appear on no calendar. No reminder fires. The bible's "BOOK SITE VISIT" lifecycle (`10_JOB_LIFECYCLE_AND_DATA_RELATIONSHIPS.md` § Site Visits) is aspirational spec.

This design gives the existing columns real meaning: a visit can be **booked** for a future time, appears on the OPS calendars (iOS + web) and the operator's personal calendars (Apple + Google, one-way outward), and OPS prompts the assigned operator to start it when the time comes.

## 2. Decisions (locked with Jackson, 2026-08-10)

1. Booked visits live on the OPS calendar **and** flow one-way to personal calendars (Apple via the existing EventKit mirror, Google via direct API push). OPS is the source of truth; reschedules happen in OPS.
2. Prompting = **remote push + persistent in-app START card**, to all assignees.
3. Push timing: configurable **default heads-up lead time in settings, overridable per booking**; a second push **at the booked time**; plus an on-device **time-to-leave alert 5 minutes before required departure** (drive-time computed on device).
4. The lead-surface VISIT affordance branches: **NOW** (today's walk-up capture, unchanged) or **BOOK A VISIT**.
5. MCP: no server built here. Deliverable is a briefing doc for the agent already building the agent control plane. Capabilities to expose: read + **book / reschedule / cancel** (writes). Start/complete stay device-only.

## 3. Data model

All changes are **additive** (iOS sync constraint: additive-only between releases).

### `site_visits` — new columns

| Column | Type | Meaning |
|---|---|---|
| `booked_at` | `timestamptz NULL` | When the booking was made. **`booked_at IS NOT NULL` is the sole discriminator for "this is a real appointment."** Walk-up (NOW) visits and all ~20 legacy rows keep `NULL`; their junk `scheduled_at` values are thereby inert. No backfill — legacy rows genuinely are not bookings. |
| `reminder_lead_minutes` | `int NULL` | Per-booking heads-up override. `NULL` = use the user's default. |

Existing columns gain real semantics for booked visits: `scheduled_at` = appointment start, `duration_minutes` = appointment length (picker default 60), `assignee_ids` = who is going (default: booker). `status` enum is **unchanged**: a booked visit is `scheduled` until started; `cancelled` covers cancellation; reschedule = update `scheduled_at`.

### Settings

Default heads-up lead time is a per-user notification preference (stored with the existing `notification_preferences` mechanism; exact shape verified at plan time). Product default: 30 minutes.

### Server RPCs — the single write path

Three new public RPCs, used by **every** surface (iOS, web, and the future MCP tools) so side effects are centralized and never diverge:

- `book_site_visit(p_opportunity_id, p_scheduled_at, p_duration_minutes, p_assignee_ids, p_reminder_lead_minutes)` — creates the visit (`status='scheduled'`, `booked_at=now()`), logs one timeline activity ("Site visit booked — Thu Feb 20, 10:00"), nudges a `new_lead` opportunity to `qualifying`, enqueues Google Calendar sync.
- `reschedule_site_visit(p_site_visit_id, p_scheduled_at, p_duration_minutes, p_assignee_ids, p_reminder_lead_minutes)` — guarded update; logs a reschedule activity; re-enqueues calendar sync; resets fired-reminder state.
- `cancel_site_visit_booking(p_site_visit_id)` — status → `cancelled`, logs activity, removes/updates external calendar events.

All three follow the `complete_site_visit_guarded` pattern: company + permission checks (`pipeline.convert` gate, matching the existing start-visit gate), status monotonicity, idempotency. Activity `type` uses the existing `site_visit` activity type (no enum addition; allowed values verified against the `activities` constraint at plan time).

## 4. Product behavior

### 4.1 Booking (iOS)

Every **lead-attached** visit affordance (leads-tab VISIT chip, lead detail START SITE VISIT, day sheet panel, add-lead sheet save action) presents a two-option branch on press: **NOW** → existing immediate capture, unchanged. **BOOK A VISIT** → booking sheet: date, time, duration, assignees (defaults: booker, 60 min), heads-up override row (default from settings). The FAB "Site Visit" stays immediate-capture only — it exists for the walk-up standing at a door; a booking always has a lead, so booking entry points are lead surfaces.

Booking a lead that already has an open booked visit surfaces that visit (reschedule/cancel) instead of stacking a second — one open booking per lead at a time; a completed/cancelled visit frees the slot.

### 4.2 Booking (web)

Pipeline lead detail gets the same BOOK A VISIT action → modal with identical fields, calling the same RPC. The two dead components (`create-site-visit-modal.tsx`, `site-visit-detail.tsx`) are **not** resurrected — they describe a flow that never existed; new components are built to this spec. (Web types regen required first: `site_visit_*` satellite tables are missing from `database.types.ts`.)

### 4.3 OPS calendars

Booked visits (`booked_at IS NOT NULL`, status `scheduled`/`in_progress`) render as a **third source** on both calendars — iOS `CalendarViewModel` (alongside `ProjectTask` + `CalendarUserEvent`) and web `calendar-service.ts` (alongside `project_tasks` + `calendar_user_events`). Distinct site-visit visual treatment per design-system tokens (styling decided in plan phase under the design skills). Tapping/clicking opens the visit (lead context, reschedule, cancel; START when it's today). Visits are **not** materialized as tasks — they must never enter crew scheduling, auto-schedule, cascade, or task reminders.

### 4.4 Personal calendars (one-way outward)

- **Apple:** `CalendarMirrorService` gains the reserved `siteVisit` mirror source (`CalendarMirrorMap.swift:16`) — booked visits mirror into the on-device "OPS" calendar with title, lead name, address as location, and the booked window. Same reconcile-and-revert drift handling as existing sources.
- **Google:** wire the dormant `google_calendar_sync_queue` — a worker (Vercel cron) drains the queue and pushes events via the Google Calendar API for accounts with a connected Google mailbox, writing back `google_calendar_event_id` / `google_calendar_id` / `google_calendar_synced_at`. **Open verification item for the plan:** whether the existing mailbox OAuth grant includes calendar scope; if not, a one-time incremental re-consent flow is required and must be designed (compact settings affordance, not a permanent card). Reschedule/cancel propagate (patch/delete the remote event).
- Event location = the linked lead's address, resolved at sync time (no address column exists on `site_visits`; a booking is always lead-attached). Lead without an address → event without location.

Costs: Google Calendar API is free at this volume; the sync worker is one small Vercel cron on the existing plan; MapKit drive-time is free on-device; OneSignal push is already in use. No new paid services.

### 4.5 Prompts

Per assignee, per booked visit:

1. **Heads-up push** at `scheduled_at − lead` (user default, per-booking override) — remote push (OneSignal) driven by a server fire function on the existing pg_cron 5-minute cadence, plus a rail notification (web) with `actionUrl` to the lead. Site visits get their own fire path — the task-anchored `task_reminders` engine is not polymorphed.
2. **START push** at `scheduled_at` — "Site visit — 123 Main St. Start now?" Tap deep-links (existing `routeToScreen` routing) straight into `SiteVisitCaptureView` with the lead bound.
3. **Time-to-leave alert (iOS local):** for today's booked visits, the device computes drive-time ETA from current location to the visit address (MapKit `MKDirections`), schedules a local notification at `scheduled_at − ETA − 5 min`, and refreshes it on foreground + background refresh. Requires location permission and a lead address; absent either, this alert silently does not exist (heads-up and START pushes are unaffected). Never fires after the visit is started.
4. **START card (in-app):** on the visit day, from the morning, a card sits at the top of the day sheet / leads surface — lead name, time, address, START. Persists until the visit is started, dismissed, or the day ends. Dismissal kills the card, not the pushes.

Dedupe: notifications use `dedupe_key` (`site_visit:<id>:<kind>`); reschedules reset fired state so prompts re-arm for the new time. Local notifications are cancelled/rescheduled on any booking change and on visit start. Quiet-hours/priority gating flows through the existing `NotificationManager` policy.

### 4.6 What does not change

Walk-up capture, the capture console, artifact sync, completion (`complete_site_visit_guarded`), stage defaults on save, and project handoff are untouched. Booking is a front porch on the existing house.

## 5. Legacy data guard

Every booked-visit query (calendars, prompts, MCP reads, START cards) filters `booked_at IS NOT NULL`. The ~20 legacy rows (and every future NOW visit) are invisible to all scheduling surfaces. The 15 stale `in_progress` legacy visits are unaffected by this feature.

## 6. MCP handoff

Deliverable: `specs/2026-08-10-site-visit-mcp-capability-briefing.md` — self-contained briefing for the agent building the agent control plane (worktree `ops-web-agent-control-plane/`, capability manifest `2026-08-07.capability-manifest.v1`, which currently has zero site-visit entries). It specifies read capabilities (`list_site_visits`, `get_site_visit_context`) and write capabilities (`book_site_visit`, `reschedule_site_visit`, `cancel_site_visit_booking`) as thin wrappers over the §3 RPCs in the manifest's prepare/commit style, and states explicitly that start/complete are device-only and out of MCP scope. Side effects (activity, stage nudge, calendar sync, reminders) live in the RPCs, so MCP tools inherit them for free and can never write a divergent visit.

## 7. Testing

- RPC suite: book/reschedule/cancel — permission boundaries, cross-company denial, idempotency, activity uniqueness, stage-nudge only from `new_lead`, one-open-booking rule.
- iOS: booking sheet flow, NOW/BOOK branch, calendar third source, mirror round-trip (visit → EventKit event → reschedule → drift revert), local-notification scheduling/cancellation matrix (book, reschedule, cancel, start, permission-denied, no-address), START card lifecycle.
- Web: booking modal, calendar rendering, rail notifications.
- Server: fire-function window correctness (no double-fire, reschedule re-arm), Google queue drain including failure/retry and revoked-grant handling.
- Legacy guard: seeded legacy-shaped rows (booked_at NULL, scheduled_at=created_at) must appear nowhere.

## 8. Explicitly out of scope

- Two-way personal-calendar sync (editing in Google/Apple does not move the OPS booking).
- Booking from the FAB or from empty calendar slots.
- Client-facing visit confirmations/reminders (the appointment-reminder email cron stays task-anchored).
- Any MCP server implementation (owned by the other agent).
