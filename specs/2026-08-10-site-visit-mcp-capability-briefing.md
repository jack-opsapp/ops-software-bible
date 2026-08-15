# Briefing: Site-Visit Capabilities for the OPS Agent Control Plane (2026-08-10)

> **Audience:** the agent building the MCP / agent-control-plane foundation (worktree `ops-web-agent-control-plane/`, spec `2026-08-07-ops-agent-control-plane-mcp-foundation.md`, capability manifest revision `2026-08-07.capability-manifest.v1`).
> **Ask:** add site-visit capabilities to the manifest. This doc is self-contained — everything you need about how site visits work is here.
> **Companion:** `2026-08-10-site-visit-booking-calendar-design.md` (the approved booking design; its RPCs are the write surface you wrap).

## 1. What a site visit is

A site visit is an on-site field capture session against a **lead** (an `opportunities` row) — photos, markup, dimensioned captures, dictated/typed notes, measurements, checklist answers, optionally a deck design. It is captured on iOS, offline-first; the phone's durable sync queue is authoritative, not any live network call. A visit may start **unlinked** (`opportunity_id NULL` — operator standing at a door with no lead yet) and be bound to a lead later.

As of 2026-08-10 a **booking layer** is being added (see companion design): a visit can be booked for a future time, shows on OPS + personal calendars, and OPS prompts the assignee to start it. You are the third consumer of that layer.

## 2. Data model (verified against prod 2026-08-10)

**`site_visits`** — `id uuid PK`, `company_id text`, `opportunity_id uuid NULL`, `project_id text NULL` / `project_ref uuid NULL` (legacy text + uuid successor), `client_id text NULL` / `client_ref uuid NULL`, `scheduled_at timestamptz NOT NULL`, `duration_minutes int default 60`, `assignee_ids text[]`, `status site_visit_status`, `completed_at`, `notes`, `internal_notes`, `measurements`, `photos text[]`, `activity_id uuid`, `calendar_event_id text`, `google_calendar_event_id` / `google_calendar_id` / `google_calendar_synced_at`, `created_by text`, timestamps, `deleted_at` (soft delete).

`site_visit_status` enum: `scheduled | in_progress | completed | cancelled`.

Satellites: `site_visit_artifacts` (captured evidence; `kind` ∈ photo, annotated_photo, dimensioned_photo, note, transcript, measurement, deck_design), `site_visit_checklist_answers` (immutable per-visit snapshot of the company's `site_visit_types` template), `site_visit_identity_drafts` (who was met, before a lead exists).

## 3. Two traps you must not fall into

1. **`status = 'scheduled'` does NOT mean booked.** It means *open* — every visit is `scheduled` from creation. Likewise `scheduled_at` on historical rows is junk (it silently defaulted to `created_at`; nothing ever set it). **The sole discriminator for a real appointment is the new `booked_at IS NOT NULL`** (added by the booking design). Every read capability must filter on it when answering scheduling questions ("what visits are booked this week"), or you will surface ~20 rows of historical garbage as phantom appointments.
2. **Start and complete are device-only. Do not expose them.** The capture lifecycle (start → capture → `complete_site_visit_guarded`) is owned by the phone's offline sync engine with vault/recovery semantics; a server-side start or complete would desync the device's durable queue. MCP writes are booking-lifecycle only.

## 4. Capabilities to add to the manifest

### Reads

- **`list_site_visits`** — filterable by window (`booked_at IS NOT NULL` for scheduling questions), status, assignee, opportunity. Returns visit + lead identity (name, address from the linked opportunity — `site_visits` has **no address column**; a booking is always lead-attached and address resolves through the lead).
- **`get_site_visit_context`** — one visit with lead context, checklist completion state, artifact counts by kind (respect `included_in_project_review`), and its timeline activity. Note: artifact `asset_url`s are storage-object references — apply your evidence-read authorization layer, same as correspondence evidence.

### Writes — thin wrappers over the booking RPCs, prepare/commit style

The booking design centralizes ALL side effects (timeline activity, `new_lead → qualifying` stage nudge, Google Calendar sync enqueue, reminder arming) inside three public RPCs. **Wrap these; never write `site_visits` rows directly**, or your writes will silently skip calendar sync and prompts:

- **`book_site_visit`** → `public.book_site_visit(p_opportunity_id, p_scheduled_at, p_duration_minutes, p_assignee_ids, p_reminder_lead_minutes)`. One open booking per lead — the RPC rejects a second; surface the existing one and offer reschedule.
- **`reschedule_site_visit`** → `public.reschedule_site_visit(p_site_visit_id, p_scheduled_at, p_duration_minutes, p_assignee_ids, p_reminder_lead_minutes)`. Only a booked, still-`scheduled` visit can move. NULL keeps a field unchanged; **`p_reminder_lead_minutes = -1` is the explicit "clear the override" sentinel** (NULL already means "leave as is").
- **`cancel_site_visit_booking`** → `public.cancel_site_visit_booking(p_site_visit_id)`. Cancelling an already-cancelled booking is a no-op success.

All three enforce company boundary + permission checks server-side and are idempotent, following the `complete_site_visit_guarded` pattern (see `20260731235533_site_visit_cloud_sync.sql:659` and the security hardening in `20260802093608_site_visit_completion_rpc_security_boundary.sql`).

**Error contract** — map SQLSTATE, do not parse message text: `22004` missing argument · `42501` unresolvable actor / permission denied / cross-company · `P0002` target row not found · `22023` failed validation (past time, duration outside 15–480, reminder outside 0–1440, invalid assignee) · `55000` state rule violated (`site_visit_already_booked`, `site_visit_not_a_booking`, `site_visit_not_reschedulable`, `site_visit_already_started`, …).

**Sequencing — RESOLVED 2026-08-11.** ~~These RPCs may not exist yet.~~ All three are **live in production** (migrations `20260810194251_site_visit_booking.sql`, `20260811053942_site_visit_booking_rpcs.sql`, `20260811054117_site_visit_booking_trigger_fn_acl.sql`, mirrored in `migrations/`). Signatures above are verified as-built and no longer subject to change from the booking build — **you can land manifest entries without a `rolloutFlag` gate.** The authoritative source for these contracts is now `04_API_AND_INTEGRATION.md` § *Site-visit booking RPCs*, not the companion design doc.

### Permissions

Gate on the pipeline permission group that covers `pipeline.convert` (the existing start-visit gate — booking uses the same one). Per OPS policy, gate on **granular permissions only, never role names**.

## 5. Conventions that apply to anything user-facing you emit

- Timestamps: visits are timezone-sensitive appointments; render in the company's local time.
- Copy register: terse, no exclamation points ("Site visit booked — Thu Feb 20, 10:00").
- Soft deletes: always filter `deleted_at IS NULL` on `site_visits` and all satellites.
