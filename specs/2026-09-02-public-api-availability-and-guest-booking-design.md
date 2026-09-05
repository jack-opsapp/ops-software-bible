# OPS Public API — P2: Availability & Guest Booking (Design)

**Date:** 2026-09-02
**Status:** Approved direction. Product decisions D9–D11 answered by Jackson 2026-09-02. Parent: `specs/2026-09-01-public-api-customer-identity-design.md` (read it first — invariants I1–I10 bind here unchanged).
**Program tag:** `PUBLIC API - P2-<n>`
**Owner:** PM session (Fable). Executors: Opus per task card.

---

## 1. Outcome

A homeowner on a trades business's own website can see safe, OPS-controlled availability, pick a time, prove one contact channel with a six-digit code, and end up with a real site visit on the crew's calendar — with no OPS account required, and with the business in control of whether that booking is confirmed instantly or held for their say-so.

## 2. Product decisions (Jackson, 2026-09-02)

| # | Decision | Consequence |
|---|----------|-------------|
| **D9** | **Whether customers may book at all is the business's choice, and so is how firmly.** One control, three states: `off` (no public booking; the website can still submit leads), `request` (the homeowner proposes a time; staff confirm), `instant` (the homeowner's pick is confirmed on the spot and lands on the calendar). | One entry point, not two toggles. Default `off` — no business gets public booking on their calendar without choosing it. |
| **D10** | **Availability is windows the business sets, never a read of the crew's real calendar.** The owner defines the days, hours, notice period, how far ahead, and visit length. OPS subtracts what is already booked and what is currently held. | No internal schedule shape leaks to the public. No drive-time or job-length modelling needed to be trustworthy. Slot supply is predictable. |
| **D11** | **Guest booking stays account-optional** (carried from P1 §5.2). Verify one channel by code, booking is real, account creation offered but never required, later sign-in claims it. | Unchanged from P1. |

## 3. Non-negotiable invariants (additional to I1–I10)

- **I11 — The public never selects or sees crew.** Assignment is server-side from policy. No response, page, or email names an assignee. (Strengthens I10.)
- **I12 — A slot is only real when the database says so.** The signed slot descriptor a page holds is a *proposal*. Confirmation re-checks policy, existing bookings, holds, and per-day caps under the company lock, and can refuse with `slot_no_longer_available`. A page must never be able to book a time the policy forbids by replaying an old descriptor.
- **I13 — Holds cannot starve a calendar.** Hold ≤ 5 minutes; ≤ 3 concurrent unverified holds per network fingerprint; ≤ 10 per company; a staff booking always wins over a hold. Expired holds are swept and never block.
- **I14 — Request mode never touches the calendar.** A `request`-mode submission creates the lead and a pending request only. Nothing appears on any calendar, no reminder arms, and no calendar sync enqueues until a staff member confirms.
- **I15 — Confirmation and management need proof every time.** The confirmation email carries a link that requires a fresh code on use. No long-lived management capability is ever emailed.
- **I16 — Public booking reuses the lead spine.** Every booking creates or matches a client per P1 §5.3, creates a lead through `create_opportunity_guarded` with `source='website'`, and attaches the visit to that lead. No parallel booking-only record exists.

## 4. Data model

### 4.1 `public.site_visit_booking_policies` — company configuration

Public schema (not `private`) because staff read and write it through the normal settings surface; it is configuration, not a credential. RLS: `company_isolation` PERMISSIVE ALL on `company_id = private.get_user_company_id()`, plus `role_scope_write` RESTRICTIVE requiring `settings.company`. Targets role `public` (the app runs as anon).

| Column | Type | Meaning |
|---|---|---|
| `company_id` | `uuid` PK → `companies(id)` | One row per company. |
| `mode` | `text NOT NULL DEFAULT 'off'` CHECK in (`off`,`request`,`instant`) | **D9.** |
| `windows` | `jsonb NOT NULL DEFAULT '[]'` | Array of `{weekday:0-6, start:"08:00", end:"16:00"}`. Validated by a CHECK-backed function: ≤ 14 entries, `start < end`, no overlap within a weekday. |
| `timezone` | `text NOT NULL` | Seeded from `companies.timezone`; the policy owns it thereafter. IANA name, validated against `pg_timezone_names`. |
| `min_notice_hours` | `int NOT NULL DEFAULT 48` CHECK 0–720 | Nothing bookable sooner than this. |
| `horizon_days` | `int NOT NULL DEFAULT 21` CHECK 1–120 | Nothing bookable further out. |
| `visit_duration_minutes` | `int NOT NULL DEFAULT 60` CHECK 15–480 | Matches the `book_site_visit` range. |
| `slot_granularity_minutes` | `int NOT NULL DEFAULT 60` CHECK in (15,30,60,120) | Slot start spacing within a window. |
| `max_bookings_per_day` | `int NULL` CHECK ≥ 1 | NULL = uncapped. Counts booked visits with `booked_at` on that local date. |
| `default_owner_id` | `uuid NULL` → `users(id)` | Same validation as the intake `default_intake_owner_id`: live, in-company, assignment-authorized. NULL or ineligible → the unassigned queue. |
| `created_at` / `updated_at` | `timestamptz` | Trigger-maintained. |

Absent row = `mode='off'`. No migration needs to backfill 64 companies.

### 4.2 `private.guest_booking_intents`

| Column | Meaning |
|---|---|
| `id`, `company_id`, `integration_id` | Scope. |
| `state` | `held` → `verified` → `confirmed` \| `submitted` \| `expired` \| `cancelled`. `submitted` is the request-mode terminal (I14). |
| `slot_start_at`, `duration_minutes` | The proposed window, stored in UTC. |
| `hold_expires_at` | I13. |
| `contact_name`, `contact_email_digest`, `contact_phone_raw`, `contact_email_encrypted` | Email is matched on (verified); phone is stored evidence only (I1). |
| `verified_channel`, `verified_at` | Which channel was proved. |
| `answers` | Bounded jsonb of the website's own questions — same shape rules as the intake ledger (≤ 100 entries, scalar values). |
| `resolved_client_id`, `resolved_opportunity_id`, `resolved_site_visit_id` | Written at confirm, never before. |
| `network_fingerprint` | HMAC, for I13 caps. Never a raw IP. |
| `created_at`, `updated_at` | |

### 4.3 `private.customer_booking_claims`

`UNIQUE(intent_id)`. A claim requires the intent's verified channel to be verified on the claiming identity. Claiming attaches the identity to the intent's already-resolved client and never creates one (P1 §5.3, D6).

### 4.4 Slot descriptors

Opaque, HMAC-signed with the existing customer-identity key ring: `sl_` + base64url(`company_id`[16] ‖ `slot_start_epoch`[8] ‖ `kid`[2] ‖ tag[16]). Carries no client, crew, or lead identifier. Validity is 10 minutes. **A valid signature proves only that OPS offered this slot — never that it is still free (I12).**

## 5. Server surface

All SECURITY DEFINER, service-role gated, `search_path` pinned — the house pattern.

- `read_public_availability_as_system(p_company_id uuid, p_from date, p_to date)` → set of `(slot_start_at timestamptz)`. Expands windows across the requested range in the policy timezone, drops anything inside `min_notice_hours` or beyond `horizon_days`, drops slots colliding with a live booked visit (`booked_at IS NOT NULL AND status='scheduled'`), drops slots held by a live intent, drops days at `max_bookings_per_day`. Returns nothing when `mode='off'`. Never reads crew rows.
- `hold_booking_slot_as_system(...)` → `(intent_id, hold_expires_at, allowed, retry_after_seconds)` — enforces I13 caps; refusal is shaped identically to success minus the intent (I5).
- `confirm_guest_booking_as_system(...)` — **the atomic core.** Under `pg_advisory_xact_lock` on the company: re-validate the slot against live policy and bookings (I12); resolve the client per P1 §5.3; `create_opportunity_guarded` with `source='website'` and the integration's provenance; then **branch on `mode`** — `instant` books the visit through the system booking path and returns `confirmed`; `request` leaves the visit uncreated and returns `submitted` (I14). Either way the intent is stamped and a staff notification is written.
- `book_site_visit_as_system(p_opportunity_id, p_scheduled_at, p_duration_minutes, p_assignee_ids, p_reminder_lead_minutes, p_actor_user_id, p_source)` — the actorless twin of the live `book_site_visit`. Same one-open-booking rule, same `new_lead → qualifying` nudge, same activity row, same calendar-sync enqueue. Assignee comes from `default_owner_id` or is empty (unassigned queue) — **never from caller input on a public path** (I11). The staff-actor `book_site_visit` is untouched.
- `confirm_booking_request_as_system(p_intent_id, p_staff_user_id, p_scheduled_at)` — request-mode acceptance: books the visit for real, honouring a staff-chosen time if they moved it.
- `reschedule_guest_booking_as_system` / `cancel_guest_booking_as_system` — customer-side management after a fresh code proof (I15). Reschedule re-runs slot validation.

## 6. Public routes (broker, hosted only)

`GET /api/customer/booking/availability?handle&from&to` → `{ slots: ["sl_…"] , timezone, durationMinutes }` — no crew, no counts, no internal ids.
`POST /api/customer/booking/hold` `{handle, slot}` → `{ intentRef, holdExpiresAt }`.
`POST /api/customer/booking/contact` `{handle, intentRef, name, email, phone?, answers?}` → starts the same OTP challenge machinery as sign-in, bound to the intent.
`POST /api/customer/booking/verify` `{handle, intentRef, challengeId, code, email}` → `{ outcome: "confirmed" | "submitted", bookingRef }`.
`POST /api/customer/booking/manage/start` and `/verify` → reschedule/cancel behind a fresh code (I15).

Every response is enumeration-safe, `no-store`, and free of UUIDs.

## 7. Hosted pages

`/c/<handle>/book` — a three-step flow in the P1 shell (same branding, same voice): **pick a time** (days across the horizon, times within the day, sold out days simply absent), **your details**, **confirm by code**. Terminal states differ by mode: `instant` → "You're booked" with the date and what happens next; `request` → "Request sent" with an honest promise about confirmation. A booking made as a guest offers account creation once, as a quiet line, never a wall.

## 8. Staff surface

- **Settings → Comms → Booking** (new section, permission `settings.company`): the one three-state control, the weekly windows, notice, horizon, duration, per-day cap, and who new bookings go to. Copy via `ops-copywriter`. Hidden entirely when the company has no public integration.
- **Request queue:** a `request`-mode submission raises a persistent notification (`create_notification_if_new_with_identity`, dedupe `booking_request:<intent_id>`) linking to the lead, where staff accept (optionally moving the time) or decline. No new inbox.
- Booked public visits appear on the existing calendars exactly like staff-booked ones — they are ordinary `site_visits` rows (I16).

## 9. Phases within P2

| Task | Scope |
|---|---|
| **P2-1** | Migration: policy table + RLS, guest intent/claim tables, availability RPC, `book_site_visit_as_system`, confirm/hold/manage RPCs, notification wiring. Contract tests for every outcome incl. I12 replay refusal and I13 caps. |
| **P2-2** | Broker library extension + the six public routes, slot descriptor signing, tests against a fake RPC client. |
| **P2-3** | Hosted `/c/<handle>/book` flow, three steps + two terminal states, Playwright smoke, screenshots. |
| **P2-4** | Staff settings section + request accept/decline on the lead, tests, screenshots. |
| **P2-5** | Live E2E against Maverick: policy set, slot listed, held, verified, booked, visible on the staff calendar, rescheduled, cancelled, zero residue. Bible chapters 04 + 10. |

## 10. Open items requiring Jackson
- Nothing blocking P2-1 through P2-4. The live E2E (P2-5) needs the P1 login-project configuration, since guest verification uses the same code machinery.
- Whether a `request`-mode decline sends the homeowner anything is a taste call, deferred to P2-4 review.

## 11. Verified state (2026-09-02)
`site_visits` columns confirmed live (TEXT `company_id`/`client_id`/`project_id`, uuid `client_ref`/`project_ref`/`opportunity_id`, `booked_at`, `assignee_ids`, `reminder_lead_minutes`, `google_calendar_*`). `companies` carries `timezone`, `open_hour`, `close_hour` (text) — the policy seeds from `timezone` and does **not** inherit the hour columns, which are display-only elsewhere. No booking-settings table exists. `book_site_visit` / `reschedule_site_visit` / `cancel_site_visit_booking` are staff-actor RPCs reading `private.get_current_user_id()` — hence the `_as_system` twins. Calendar sync rides `google_calendar_sync_queue`, already triggered by `site_visits` status changes.
