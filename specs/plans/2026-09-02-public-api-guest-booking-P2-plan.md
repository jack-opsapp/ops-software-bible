# PUBLIC API — P2 Availability & Guest Booking Implementation Plan (2026-09-02)

> **For Claude:** REQUIRED SUB-SKILL: `custom-skills:executing-plans`. Design authority: `specs/2026-09-02-public-api-availability-and-guest-booking-design.md`, and its parent `specs/2026-09-01-public-api-customer-identity-design.md` (invariants I1–I16 are requirements, not suggestions). Read both in full before touching anything.

**Goal:** A homeowner books a site visit from a trades business's own website — safe availability, one verified contact channel, a real visit on the crew's calendar — with the business choosing whether bookings confirm instantly, wait for their say-so, or are off entirely.

**Architecture:** Business-defined availability windows (never a crew-calendar read) expand into signed, opaque slot proposals. A hold, then a six-digit code on one channel, then one atomic confirm that resolves the client, creates the lead through `create_opportunity_guarded`, and either books the visit (`instant`) or stops at a pending request (`request`). All writes go through service-role `*_as_system` RPCs; the staff-actor `book_site_visit` family is untouched.

**Tech Stack:** as P1 — Next.js 15 App Router, `private`-schema SECURITY DEFINER RPCs (house pattern), the customer-identity broker library and its HMAC key ring, vitest, Playwright.

**Design System:** `ops-design-system/project/DESIGN.md`; hosted pages inherit the P1 shell (`src/components/customer/customer-shell.tsx`) and `portal_branding` theme.

**Required Skills:** `custom-skills:executing-plans`, `superpowers:test-driven-development`, `supabase:supabase` (DB tasks), `ops-design` + `frontend-design:frontend-design` + `custom-skills:interface-design` + `ops-copywriter:ops-copywriter` (P2-3, P2-4), `animation-studio:animation-architect` before any motion, `custom-skills:audit-design-system` before any UI is called done, `superpowers:verification-before-completion`.

**Branch:** `feat/public-api-booking-p2`, cut from `feat/public-api-identity-p1` (tip `bd052d2d`) — P2 depends on the P1 broker library and hosted shell, which are not yet on `main`. Fresh worktree, own `npm ci`, `NODE_OPTIONS=--max-old-space-size=8192`. Atomic commits, no AI attribution, never push.

---

## Verified starting state (2026-09-02, live)

- `site_visits`: `company_id`/`client_id`/`project_id` are **TEXT**; `client_ref`/`project_ref`/`opportunity_id` are uuid; `booked_at`, `assignee_ids text[]`, `reminder_lead_minutes`, `status` (enum), `google_calendar_*`. Cast through `private.try_parse_uuid` / `private.agent_uuid_from_legacy_text` when joining.
- `book_site_visit(p_opportunity_id, p_scheduled_at, p_duration_minutes, p_assignee_ids, p_reminder_lead_minutes)` — SECURITY DEFINER, resolves the actor from `private.get_current_user_id()`, requires `private.current_user_can_edit_site_visit`, enforces one open booking per lead, nudges `new_lead → qualifying` via `move_opportunity_stage`, writes an `activities` row with type `site_visit_scheduled`, and lets the status trigger enqueue Google sync. **Read its body before writing the `_as_system` twin and mirror every guard.**
- `reschedule_site_visit` reminder semantics: NULL = keep, `-1` = clear to default, 0–1440 = set.
- `companies`: `timezone`, `open_hour`, `close_hour` (all text), `public_handle` (P1). No booking-settings table exists.
- P1 landed and live: `private.customer_*` + `company_client_memberships` (8 tables), 15 `*_as_system` RPCs incl. `resolve_customer_membership_as_system`, `begin_customer_otp_challenge_as_system`, `record_customer_otp_attempt_as_system`. Ledgers `20260902010242`, `20260902044746`.
- P1 broker library: `src/lib/customer-identity/{config,credentials,rpc,otp,session,membership,handle,index}.ts`; routes under `src/app/api/customer/` with `_lib/broker-request.ts` (handle grammar, per-IP limits, opaque `ch_` refs); hosted shell at `src/app/c/[handle]/`.
- `create_opportunity_guarded(p_opportunity jsonb, p_assignment_mode text, p_initial_assigned_to uuid, p_metadata jsonb)` is the only lead-creation path. `opportunities_source_check` allows `website`.
- `create_notification_if_new_with_identity(p_user_id, p_company_id, p_type, p_title, p_body, p_persistent, p_action_url, p_action_label, p_project_id, p_deep_link_type, p_dedupe_key)`. **Verify `notifications.type` CHECK before choosing a type.**
- `google_calendar_sync_queue` is trigger-driven off `site_visits`; `cancel_site_visit_booking` neutralizes pending create/update rows with `skip_reason='booking_cancelled'`.

## Tasks

### P2-1 — Migration + server core (Fable writes the SQL)
**Files:** `ops-web/supabase/migrations/<ts>_public_booking_foundation.sql`, byte-exact mirror in `ops-software-bible/migrations/`, bible section in `03_DATA_ARCHITECTURE.md`.

Objects per design §4 and §5:
- `public.site_visit_booking_policies` with the `company_isolation` PERMISSIVE + `role_scope_write` RESTRICTIVE (`settings.company`) pattern, targeting role `public`. Window validation via a `private` immutable function used in a CHECK.
- `private.guest_booking_intents`, `private.customer_booking_claims` — zero grants, `updated_at` triggers.
- `read_public_availability_as_system`, `hold_booking_slot_as_system`, `confirm_guest_booking_as_system`, `book_site_visit_as_system`, `confirm_booking_request_as_system`, `reschedule_guest_booking_as_system`, `cancel_guest_booking_as_system`.
- A hold sweeper on the existing controlled-cron runner (mirror `customer_identity_dormancy_daily`), every 5 minutes.

**`book_site_visit_as_system` is the risk.** Read `book_site_visit`'s live body first and mirror: opportunity row lock as the booking mutex, company match, past-time rule, duration range, assignee validation, one-open-booking check, `site_visits` insert shape, activity insert, `activity_id` back-write, stage nudge. Differences only: actor supplied as a parameter (nullable → `created_by` records the system source), assignees derived from policy not caller input (I11), and no `current_user_can_edit_site_visit` gate (there is no current user).

**Acceptance:** contract suite inside `begin`/`rollback` covering — availability off/request/instant, notice and horizon edges, per-day cap, slot collision with an existing booking, slot collision with a live hold, I12 replay of a stale descriptor refused, I13 hold caps per fingerprint and per company, staff booking overriding a hold, `instant` producing a real `site_visits` row with a calendar-sync queue entry, `request` producing **no** `site_visits` row and no queue entry (I14), request acceptance later booking it, reschedule and cancel, DST boundary in a non-UTC policy timezone. Then: advisors clean, zero non-owner grants on the two `private` tables, non-service gate live-fired.

### P2-2 — Broker library + public routes
**Files:** `src/lib/customer-identity/booking-*.ts`, `src/app/api/customer/booking/**`, tests under `tests/unit/customer-identity/` and `tests/api/`.
Slot descriptor mint/verify using the existing key ring (mirror the `ch_` challenge-ref binding in `_lib/broker-request.ts` — constant-time compare, key rotation, 10-minute validity). The six routes in design §6, all `no-store`, all enumeration-safe, none returning a UUID. Reuse `_lib/broker-request.ts` for handle resolution and per-IP limits; add booking-specific limits. Tests run the real library against an extended `tests/utils/customer-identity-fake.ts`.

### P2-3 — Hosted booking flow
**Files:** `src/app/c/[handle]/book/**`, `src/components/customer/booking/**`, `tests/e2e/customer-booking.spec.ts`, screenshots to `docs/artifacts/`.
Three steps in the P1 shell, two terminal states (§7). Sold-out days are absent, not disabled-with-explanation. The hold countdown is honest and quiet. Motion: house easing only, `prefers-reduced-motion` honored — load `animation-studio:animation-architect` first. Every string through `ops-copywriter` and the `customer` i18n namespace (en + es). `custom-skills:audit-design-system` before done. Mobile is the primary target.

### P2-4 — Staff settings + request handling
**Files:** `src/components/settings/booking-settings-tab.tsx` (+ registration in `settings-domains.tsx` under Comms, permission `settings.company`), routes for policy read/write, request accept/decline on the lead surface, tests, screenshots.
**Design judgment:** the three-state control is one control, not two toggles. Windows are a weekly grid, not twenty-one inputs. Everything below the mode control is irrelevant when mode is `off` — do not render dead configuration. Hide the whole section when the company has no public integration.

### P2-5 — Live E2E + bible
Against Maverick (`ddee107c-33cd-483e-8278-0f8d8a180181`) with the P1 login project configured: set a policy, list availability, hold, verify by real code, confirm in `instant`, see the visit on the staff calendar, reschedule, cancel; repeat in `request` mode proving I14 (nothing on the calendar until acceptance); prove a stale descriptor is refused and a hold cannot be starved. Zero residue. Bible: `04_API_AND_INTEGRATION.md` (routes + RPCs), `10_JOB_LIFECYCLE_AND_DATA_RELATIONSHIPS.md` (public booking in the lead lifecycle).

## Verification bar — P2 is done when
Every invariant I11–I16 has at least one automated test; the request/instant branch is proven at the database level, not just the route level; zero grants on the new `private` tables; the live E2E evidence is in `docs/artifacts/`; the bible is current; the branch awaits Jackson's push GO.
