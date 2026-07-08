# SPEC — Admin UX (OPS-Web)

Operator-facing surface. Lives at `/admin/spec` in OPS-Web alongside existing admin pages (`/admin/companies`, `/admin/shop`, `/admin/email`, etc.). Revised 2026-05-25 (third pass) to:

- Replace the generic `has_permission('spec.admin')` gate with the dedicated `is_spec_operator()` SECURITY DEFINER function (CR-1). Customer-side company admins NEVER satisfy the SPEC operator gate.
- Remove the customer-can-view language from `/admin/spec/[id]`. All `/admin/spec/*` routes are operator-only. The full customer-facing project portal at `/account/spec/[id]` is a Phase 2 deliverable (MJ-3), but the minimal refund-request route `/account/spec/[id]/request-refund` is Phase 1.
- Add a manual "Force refresh board snapshot" button that calls the SECURITY DEFINER `refresh_spec_board_snapshot()` via a server route (CR-3).
- Surface `spec_refund_requests.refund_breakdown` in the refund queue UI — operator sees per-milestone action (refund / void / credit_note / mark_uncollectible) before clicking Process (CR-4).
- Add an Entitlements tab toggle that flips `enabled` between true and false with a reason (CR-7).
- Add a Test-mode toggle that includes `is_test = true` rows in admin queries (MJ-10).

## `/admin/spec` — overview

Top-down layout:
1. TODAY command queue (sticky, scannable in under 5 seconds)
2. Capacity status panel (with "Force refresh board snapshot" affordance)
3. Kanban pipeline view
4. Revenue summary + pipeline velocity (bottom-of-page)

**Page header right rail:**
- `// TEST MODE` toggle — when on, all queries include `is_test = true` rows; when off (default), they exclude them. The toggle's state is read from a cookie scoped to the operator's session.
- `REFRESH BOARD` button — fires `POST /api/admin/spec/board/refresh`, which is gated on `is_spec_operator()` and calls `public.refresh_spec_board_snapshot()` via the service role. Shows the new `refreshed_at` on success.

**Stage F.1 implementation status (2026-05-26):** Landed on `feat/spec-admin-overview` (OPS-Web). The overview shell (`/admin/spec`) is operator-gated via `src/app/admin/spec/layout.tsx`, which re-implements `private.is_spec_operator()` in TS at `src/lib/admin/spec-permissions.ts` (Firebase auth doesn't carry the Supabase JWT to `public.get_user_id()`, so the service-role client can't call the SQL helper directly — the TS mirror consults the same two sources: `role_permissions(spec.admin/all)` via `user_roles`, and `user_permission_overrides(spec.admin, granted=true)`). The gate NEVER consults `is_company_admin / account_holder_id / admin_ids`, so customer-side company admins fail closed. Components: `src/app/admin/spec/_components/` (today-queue + capacity-panel + kanban-pipeline + revenue-summary + pipeline-velocity + spec-page-header + test-mode-toggle + refresh-board-button). Data layer at `src/lib/admin/spec-queries.ts` with cache hints (TODAY 30s, capacity 60s, revenue + velocity 5min). Test-mode cookie helper at `src/lib/admin/spec-test-mode.ts`. The `REFRESH BOARD` button calls the operator-gated `POST /api/admin/spec/board/refresh` route, which in turn invokes the `public.refresh_spec_board_snapshot()` wrapper added by migration `2026-05-26-03-spec-stage-f1-board-refresh-wrapper.sql` (the wrapper is needed because `private` is not in PostgREST's default exposed schemas; the wrapper grants EXECUTE to service_role only). Sub-chips F.2 (project detail with 11 tabs), F.3 (refunds + owner-approvals queues), F.4 (capacity config editor) follow this overview shell.

**Stage F.3 implementation status (2026-05-26):** Landed on `feat/spec-admin-queues` (OPS-Web), built on top of F.1's overview shell. Adds two operator processing surfaces: `/admin/spec/refunds` and `/admin/spec/owner-approvals`.

Files:
- Pages: `src/app/admin/spec/refunds/page.tsx`, `src/app/admin/spec/refunds/[id]/page.tsx` (processed-detail), `src/app/admin/spec/owner-approvals/page.tsx`.
- Components: `src/app/admin/spec/refunds/_components/` (`refund-row-card.tsx`, `refund-breakdown-preview.tsx`, `processed-refund-row.tsx`), `src/app/admin/spec/owner-approvals/_components/owner-approval-row.tsx`, `src/app/admin/spec/_components/spec-sub-page-header.tsx` (shared back-link + test-mode chip).
- Server actions: `src/app/admin/spec/refunds/_actions/process-refund.ts`, `src/app/admin/spec/refunds/_actions/deny-refund.ts`, `src/app/admin/spec/owner-approvals/_actions/resend-approval-email.ts`, `src/app/admin/spec/owner-approvals/_actions/cancel-request.ts`. Every action calls `requireSpecOperatorAction()` from `src/lib/admin/spec-operator-guard.ts` to re-check `isSpecOperator(userId)` server-side — the page-layout gate is not sufficient since actions can be invoked from anywhere.
- Refund-breakdown computation: pure function at `src/lib/spec/refund-breakdown.ts` (`computeRefundBreakdownPreview`) — used by both the operator UI (preview) and the process-refund action (plan walker). Output shape `RefundBreakdownExecutedLine[]` matches `spec_refund_requests.refund_breakdown` jsonb.
- Email outbox helper: `src/lib/spec/email-outbox.ts` (`writeSpecEmailOutbox`) — single insert into `public.spec_email_outbox` (operator/service-role only, RLS denies all access). Stage H's email send-cron consumes rows by `template_id`.
- Data layer: `src/lib/admin/spec-queries.ts` extended additively with `getPendingRefundRequests`, `getProcessedRefundRequests`, `getRefundRequestDetail`, `getPendingOwnerApprovals`. Types in `src/lib/admin/spec-types.ts` (`SpecRefundQueueRow`, `SpecRefundPaymentSummary`, `SpecRefundEligibility`, `SpecOwnerApprovalQueueRow`).
- Migration: `migrations/2026-05-26-05-spec-stage-f3-refund-deny-columns.sql` adds `denied_at`, `denial_reason_text`, `denied_by_user_id`, `internal_note` columns + a status/processed_at index to `spec_refund_requests`. **Must be applied before code goes live** — the deny-refund action and the processed-detail view both reference these columns.

**Stage F.5 implementation status (2026-07-08):** Staged on OPS-Web local `main` through the held-merge integration. Adds the operator-only SPEC analytics surface at `/admin/spec/analytics`, backed by Google Ads campaign, keyword, and search-term history plus ZIP export routes.

- Page: `src/app/admin/spec/analytics/page.tsx` with the client surface in `src/app/admin/spec/analytics/_components/spec-analytics-content.tsx`.
- Routes: `GET /api/admin/spec/analytics` returns redacted analytics by default; `GET /api/admin/spec/analytics/export` returns a ZIP with optional sensitive export mode. Both routes are server-only and operator-gated through the same SPEC admin auth path.
- Data layer: `src/lib/admin/spec-analytics-queries.ts`, `src/lib/admin/spec-analytics-types.ts`, and `src/lib/admin/spec-analytics-export.ts`; Google Ads history helpers live in `src/lib/admin/ads-history-*` and `src/lib/analytics/google-ads-*`.
- Storage: production already carries the additive `public.ads_daily_search_term` table from migration history version `20260619052545 ads_daily_search_terms` (singular table name in code and DB). RLS is enabled; no anon/authenticated grants exist; server-side service-role paths own reads/writes.

Refund processing contract (`processRefundAction`):
- Form payload: `refundRequestId`, repeated `milestone` checkboxes, optional `internalNote`, optional `setGoodwill` (operator can flag a post-30-day request as goodwill at process time).
- Idempotency: re-checks `spec_refund_requests.status` before any Stripe call. Already-processed / partial / failed → returns `{ ok: true, status: 'noop' }`.
- Per-milestone walk via `executeMilestone()`:
  - `paid` → `stripe.refunds.create({ payment_intent, amount, reason: 'requested_by_customer' })` → `spec_payments.status='refunded'`, `refunded_at`, `amount_refunded_cents=total_cents`.
  - `partially_refunded` → refund remaining captured balance, stamps `status='refunded'`.
  - `invoiced` / `overdue` → `stripe.invoices.retrieve()` to detect partial payment; partial → `stripe.creditNotes.create()` (unpaid portion) + `stripe.refunds.create()` (paid portion), `status='partially_refunded'`, `credit_note_stripe_id`. Open invoice → `stripe.invoices.voidInvoice()`, `status='voided'`. If void rejects (already-finalized state) → fallback to `stripe.invoices.markUncollectible()`, `status='uncollectible'`.
  - `disputed` / `pending` / already-terminal → noop with breakdown entry `status='skipped'`.
- After the walk: writes `refund_breakdown` jsonb (the executed array), rolls up `total_refund_cents` (sum of `cash_refund_cents`), `stripe_refund_ids` (subset where `action='refund'`). Sets `status='processed'` (all succeeded/skipped), `'partial'` (some succeeded), or `'failed'` (all failed). Stamps `processed_at`, `processed_by_user_id`.
- Entitlement flip: `spec_module_entitlements.enabled=false`, `disabled_reason='refunded'`, `disabled_at=now()` for every row on the project (only when `status != 'failed'`).
- Project flip: `spec_projects.status='refunded'`, `refunded_at=now()`.
- Customer email: writes `spec.refund_processed` to `spec_email_outbox` with `payload` carrying `refund_breakdown` for line-by-line render. Stage H template handles the format.
- Customer notification: best-effort insert into `public.notifications` (`type='spec_refund_processed'`).
- Cash refund cap: refuses if `sum(cash_refund_cents) > sum(total_cents - amount_refunded_cents)` across paid + partially_refunded milestones (defends against operator misclick on a non-guarantee partial refund).

Refund denial contract (`denyRefundAction`):
- Form payload: `refundRequestId`, `denialReason` (20-2000 chars, required; surfaced verbatim in customer email), optional `internalNote`.
- Updates `spec_refund_requests` with `status='denied'`, `denied_at`, `denied_by_user_id`, `denial_reason_text`, optional `internal_note`.
- Writes `spec.refund_denied` to `spec_email_outbox` + customer notification.
- No entitlement / project status changes — denied refunds leave the engagement untouched.

Owner-approval queue contracts:
- `resendApprovalEmailAction`: writes a fresh `spec.owner_approval_required` row to `spec_email_outbox` recipient=account_holder. **Reuses the existing approval_token_hash** — the URL the account_holder receives is the same one as the original email so the customer-side approval route still works.
- `cancelApprovalRequestAction`: flips `spec_owner_approval_requests.status='expired'`, `decided_at=now()`. Flips parent `spec_projects.status='cancelled'`, `cancellation_reason='owner_approval_cancelled_by_operator'`, `cancelled_at=now()`. Writes `spec.owner_approval_declined` to outbox (re-purposed for operator-initiated cancellation — payload carries `cancellation_reason='owner_approval_cancelled_by_operator'` to distinguish from account_holder decline). Customer notification inserted.

Sub-chip F.4 (capacity config editor) follows F.3.

**Stage F.2.a implementation status (2026-05-26):** Landed on `feat/spec-admin-project-detail-a` (OPS-Web). The project-detail page (`/admin/spec/[id]`) inherits the F.1 operator gate (`src/app/admin/spec/layout.tsx`) and renders a tabbed surface at `src/app/admin/spec/[id]/page.tsx` → `src/components/admin/spec/project-detail/ProjectDetail.tsx`. **Tabs implemented: Overview (1) · Timeline (2) · Intake (3) · Scope doc (4) · Milestones (5).** Tabs 6-11 (Change orders / Satisfaction / Tickets / Comms / Entitlements / Notes) render as F.2.b placeholders. Tab 1 Overview: customer + buyer/account_holder identity links (flags Path B), linked company link, key dates, hold state, financial summary (committed / paid / pending / overdue / refunded / polish budget), ETA editor, attribution snapshot. Tab 2 Timeline: chronological log from `spec_acceptance_events`, `spec_communications`, `spec_payments` (state transitions), `spec_change_orders`, `spec_scope_documents` versions, `spec_satisfaction_ratings`, `spec_support_tickets`, plus project-row lifecycle stamps — filter chips (All / Comms / Money / Status / Tickets / Acceptance) + search; Path B engagements surface `owner_purchase_approved` and `tos_accepted` with a paired-evidence pill. Tab 3 Intake: structured render of `intake_responses` jsonb in 8 sections (business basics / team / money / current tools / workflow / pain points / success / regulated-workflow attestation) with file download links via 5-min signed URLs over the `spec-intake` Supabase Storage bucket. Tab 4 Scope doc: version list + current version content + features list with per-feature pass/fail/reset controls (server action `mark-feature`); new-revision button bumps `version` + stamps the prior `superseded_at` + copies feature scaffolding (`new-scope-revision` server action). Tab 5 Milestones: P1-P4 table with tier-canonical 25% amounts; P1 row shows AUTO (Stripe webhook owns it); P2/P3/P4 fire-buttons enabled iff prerequisite acceptance event exists per `getMilestoneFireability` (P2 = `scope_signoff`, P3 = `midpoint_accepted`, P4 = `walkthrough_completed_at IS NOT NULL` + `delivery_accepted`); firing creates `spec_payments` row (pending → invoiced), creates Stripe Invoice (auto_advance + collection_method=send_invoice + days_until_due=15 = net-15; Stripe auto-emails the hosted invoice), enqueues a `spec_email_outbox` row keyed to template `spec.p{2,3,4}_invoice` for the Stage H branded follow-up email, logs a `spec_communications` system entry, and inserts an operator-facing row into `public.notifications` (`type='spec_invoice_fired'`, `company_id=OPS_OPERATIONS_COMPANY_ID`, deep link to the milestones tab). Server actions live under `src/app/admin/spec/[id]/_actions/` (`fire-milestone.ts`, `new-scope-revision.ts`, `mark-feature.ts`, `update-eta.ts`) and re-check `isSpecOperator(userId)` server-side via the `_require-operator.ts` shared helper. `spec-queries.ts` extended additively with `getProjectDetail`, `getMilestoneFireability`, `withIntakeSignedUrls` plus per-tab loaders. Sub-chip F.2.b follows for tabs 6-11.

### TODAY command queue (top of overview)

The first thing Jackson sees when opening `/admin/spec` is a compact "what needs you today" list. Not a dashboard — a queue. Items disappear when handled, surface when triggered. Each row deep-links to the relevant project or settings page.

Sections:

- **Money to collect** — milestone invoices ready to fire (P2 enabled because scope is signed but no P2 row yet; P3 enabled because midpoint accepted but no P3 row; P4 enabled because walkthrough completed but no P4 row), overdue invoices (paid past net-15 + grace), non-payment disable threshold approaching (7 days past due in 2 days).
- **Customers blocked on approval** — owner-approval requests in `pending` status, sorted by age. A 2-day-old request gets a "ping owner" quick action.
- **Decisions due** — refund requests in `pending`, Stripe disputes in `disputed`, no-shows escalating (1st → 2nd this week, 2nd → 3rd in queue), related-entity referral flags awaiting review, regulated-workflow attestations marked yes at intake.
- **SLA misses** — projects in `building` with `last_communication_at` > 7 days, midpoint/delivery/walkthrough scheduled today/this week that haven't been confirmed by Jackson.
- **Refund / dispute risk** — projects in `support` with a satisfaction rating ≤ 2 in the last 7 days, projects with an open critical ticket > 48h old, projects approaching the 30-day guarantee window expiry with no walkthrough recording or open ticket.
- **Next best action** — projects in `awaiting_deposit` with `checkout_token_expires_at` within 24h (nudge buyer), projects in `intake_completed_at` with no `discovery_scheduled_at` after 7 days (send Calendly), `customer_requested` holds approaching their 90-day expiry.

Each item has:
- One-line description ("Scope signed for [Customer], P2 ready to fire — $2,125")
- Age (e.g. "2d", "5h")
- Primary action button ("Fire P2 invoice", "Process refund", "Review", "Send Calendly")
- Secondary "snooze 24h" affordance
- Deep link to `/admin/spec/[id]` or the relevant queue page

Implementation: composed of multiple queries, each a small server action returning a `TodayItem[]`. Updates on revalidate, cached for 30 seconds per query.

### Capacity status panel

Below TODAY. Compact strip:
- Slots consumed per tier (precise — admin RLS, not the sanitized public view) — e.g. `SETUP: 2/4 · BUILD: 3/3 · ENTERPRISE: 1/1`
- Hold breakdown per tier — e.g. `BUILD: 1 ops_blocked · 2 customer_requested`
- Manual next-start override controls per tier (date picker + save)
- Accepting-bookings toggle per tier
- Public-note input per tier (shown on `/spec` board)

### Kanban pipeline view

Columns (left → right, by typical lifecycle):
- `awaiting_owner_approval`
- `awaiting_deposit`
- `deposit_paid`
- `discovery`
- `building`
- `on_hold` (split visually within the column: customer_requested top, ops_blocked bottom, separator)
- `support`
- `on_retainer`
- `completed`

Card content (per project):
- Customer name + tier badge
- Days in current status
- Total $ committed (sum of paid + scheduled milestones)
- Hold-type chip if `on_hold` (`HOLD · CUSTOMER` or `HOLD · BLOCKED`)
- Next action indicator (e.g. "Scope doc due", "Midpoint demo Friday", "P3 ready to fire")

Side panel (collapsed by default):
- `stalled` count
- `stalled_on_hold` count
- `cancelled` count
- `refunded` count

### Revenue summary

Bottom of page:
- Paid this month / quarter / YTD
- Pending invoices total
- Overdue invoices total
- Refunded total
- MoM trend mini-chart

### Pipeline velocity

- Average days at each status
- Slowest projects (longest in their current status)
- Cycle time per tier (deposit → walkthrough)

## `/admin/spec/[id]` — project detail

Tabbed layout. **All `/admin/spec/*` URLs are operator-only**, gated on `public.is_spec_operator()` in both the route layout and the underlying RLS policies. Customer-facing access to their own engagement is deferred to the Phase 2 customer portal route at `/account/spec/[id]` (read-only timeline, acceptance evidence chain, current scope doc — but NOT the operator command surfaces).

### Tab 1: Overview
- Customer info (name, email, phone, GST number if provided)
- Buyer + account_holder identity (link to each user; flag if they differ)
- Linked company (with link to `/admin/companies/[id]`)
- Status badge + last status change date
- Tier + (if upgraded) original_tier
- Key dates: `deposit_paid_at`, `scope_doc_signed_at`, `build_started_at`, `walkthrough_completed_at`, `support_window_ends_at`
- Hold state if on_hold: `hold_type`, `prior_status`, `on_hold_at`, `on_hold_expires_at`, `on_hold_reason`
- Financial summary:
  - Total committed
  - Paid (with breakdown by milestone)
  - Pending invoices
  - Refunded
  - Polish budget: used / total
- Current ETA + `estimated_completion_date` editor
- Attribution: UTM source / medium / campaign / first-touch URL (read from `attribution` JSONB)

### Tab 2: Timeline

Chronological log. Every event:
- Status changes
- `spec_acceptance_events` entries (ToS accepted, owner_purchase_approved on Path B, scope signed, midpoint accepted, delivery accepted, change order accepted) — each row shows the signature method + payload_hash for evidence. Path B engagements show TWO rows at the top of the timeline: the account_holder's `owner_purchase_approved` first, then the buyer's `tos_accepted` at Stripe completion.
- Communications (from `spec_communications`)
- Payments (invoiced, paid, overdue, refunded)
- Change orders (proposed, approved, completed)
- Scope document versions (`drafted_at`, `sent_at`, `superseded_at`)
- Satisfaction ratings (received)
- Support tickets (opened, resolved)
- System events (cron triggers, automated emails)

Filter chips: All / Comms / Money / Status / Tickets / Acceptance. Search box.

### Tab 3: Intake responses

Read-only view of `intake_responses` JSONB rendered as structured form. Sectioned per intake form: business basics, team, money, current tools, workflow, pain points, success, regulated-workflow attestation, files (with download links from Supabase Storage), anything else.

### Tab 4: Scope doc

- List of `spec_scope_documents` versions for this project (current + history). Each row: version, content_hash (truncated for display), drafted_at, sent_at, superseded_at, external_url.
- Current version content rendered (feature list, acceptance criteria, exclusions, midpoint def, delivery def, subscription terms).
- "New scope revision" button → creates a new version, increments `version`, marks the previous `superseded_at`.
- `spec_feature_acceptance` list for the current scope version with pass/fail status per feature.
- Inline "Mark feature passing/failing" controls (Jackson updates as features verified).

### Tab 5: Milestones

- P1-P4 status table from `spec_payments`
- Manual "Fire P2/P3/P4 invoice" buttons (only enabled when prerequisites met — and visible in TODAY queue too):
  - P2 enabled when `spec_acceptance_events` for `scope_signoff` exists
  - P3 enabled when `spec_acceptance_events` for `midpoint_accepted` exists
  - P4 enabled when `walkthrough_completed_at IS NOT NULL` and `spec_acceptance_events` for `delivery_accepted` exists
- For each milestone: amount, status, Stripe invoice ID (link), due date, paid date

### Tab 6: Change orders

- List of all `spec_change_orders` rows
- "New change order" button → wizard (minor hourly or major fixed quote or tier upgrade)
- Per change order: status, customer-approval status (linked `spec_acceptance_events` row), Stripe invoice link, final cost
- Polish-budget tracking (used / remaining)

### Tab 7: Satisfaction ratings

- Per-feature 1-5 ratings at midpoint and delivery
- Customer notes
- Visual heat map (features × ratings) for quick scan
- Filter by milestone

### Tab 8: Support tickets

- Open tickets with severity tags + phase chip (`support` / `retainer` / `ad_hoc`)
- "New ticket" button (Jackson can log on customer's behalf)
- Resolution log
- Escalation control (severity reclassification, escalate to change order)

### Tab 9: Communications

- Full log from `spec_communications`
- Inbound + outbound emails (synced via OPS-Web SendGrid event webhook)
- Manual "Log a call" / "Log a video message" buttons
- "Send email via template" — pulls from `email_template_versions`, dispatches via OPS-Web's gated send

### Tab 10: Entitlements

- List of `spec_module_entitlements` rows for this project (and its linked_company_id)
- Per row: module_key, enabled, disabled_reason, multiplier, surcharge_cents, stripe_subscription_item_id, entitled_at, enabled_at, disabled_at
- **Enabled / disabled toggle** per row:
  - Disable → operator picks reason from the constrained list (`non_payment`, `dispute`, `refunded`, `subscription_lapse`, `customer_request`, `ops_decision`, `not_yet_delivered`). Stamps `disabled_at`. Requires confirmation modal.
  - Enable → only available when `disabled_reason` is one that an operator action can clear. Stamps `enabled_at`. Clears `disabled_reason`.
- Initial state for newly reserved rows is `enabled = false`, `disabled_reason = 'not_yet_delivered'`. The walkthrough completion flow flips them to `enabled = true` automatically (see [03_WORKFLOW.md](03_WORKFLOW.md) Delivery section); the toggle is for manual operator overrides afterwards.
- Useful in dispute, non-payment, subscription-lapse, refund flows.

### Tab 11: Notes

- Jackson's internal notes (textarea, autosave)
- Markdown supported
- Timestamped revisions visible

## Status-change side effects

Each status-transition button in OPS-Web admin fires:
- Updates `spec_projects.status`
- Inserts the relevant timestamp on the matching `_at` field (and `prior_status` + `hold_type` if entering `on_hold`)
- Inserts a `spec_communications` system entry
- Fires the appropriate email template via OPS-Web email infrastructure
- Adds operator work to the TODAY queue AND inserts a row into `public.notifications` per the locked routing in 07_ROLLOUT.md § Gate resolutions → `SPEC-NOTIFICATION-RAIL-DEPRECATED` (rail confirmed active; consumed by the `NotificationsDrawer` edge-tab mounted in `dashboard-layout.tsx`). Customer operational notices use email (primary) + a `public.notifications` row keyed to the customer's `linked_company_id` (secondary, for in-app rail visibility).

Specific transitions with structured side effects:

### `discovery → building` (scope doc countersigned)
- Insert `spec_acceptance_events` row (event_type `scope_signoff`)
- Create `spec_payments` row for P2 (`status = 'invoiced'`)
- Fire Stripe Invoice for P2 (net-15)
- Set `subscription_locked_at = now()`
- Lock `locked_subscription_multiplier` from scope doc
- Lock `locked_module_surcharge_cents` from scope doc
- Create `spec_feature_acceptance` rows from the scope doc (each linked to the current `spec_scope_documents.id`)
- Reserve `spec_module_entitlements` rows (one per module_key in scope), `enabled = false`, `disabled_reason = 'not_yet_delivered'` — access does NOT turn on at sign-off, only at delivery walkthrough
- Email `spec.scope_doc_signed_customer` + `spec.p2_invoice` to customer

### `building → support` (walkthrough completed)
- Stamp `walkthrough_completed_at` (the canonical anchor)
- Insert `spec_acceptance_events` row (event_type `delivery_accepted`)
- Create `spec_payments` row for P4 (`status = 'invoiced'`)
- Fire Stripe Invoice for P4 (net-15)
- Compute + set `support_window_ends_at = walkthrough_completed_at + tier_support_window_days`
- Flip all `spec_module_entitlements` for this project to `enabled = true`, `enabled_at = now()`, `disabled_reason = NULL`
- Update `spec_referrals` row (if any) → `eligible_at = walkthrough_completed_at`
- Email `spec.p4_invoice` + `spec.support_window_open` to customer
- Schedule satisfaction survey
- Server-side conversion event: `delivery_walkthrough_completed`

### `support → on_retainer` (customer subscribes to retainer)
- Create `spec_retainers` row
- Status updated
- `retainer_started_at = now()`

### `support → completed` (support window ends, no retainer)
- `completed_at = now()`
- Schedule `spec.support_ending_14d_after` final retainer reminder email

### Hold entry (any active → `on_hold`)
- `on_hold_at = now()`
- `on_hold_reason = ...`
- `hold_type = 'customer_requested' | 'ops_blocked'` (operator chooses)
- `prior_status = previous status`
- `on_hold_expires_at = on_hold_at + 90 days` (only for `customer_requested`)
- If `customer_requested`: capacity logic releases the slot
- If `ops_blocked`: capacity logic keeps the slot

### Hold exit (`on_hold → prior_status`)
- `resumed_at = now()`
- Status restored to `prior_status`
- `hold_type`, `on_hold_expires_at` cleared

## `/admin/spec/capacity` — capacity config

Edit `spec_capacity` rows. Form per tier:
- Slot ceiling (int)
- Discovery days min/max (int)
- Build days min/max (int)
- Support window days (int)
- Subscription multiplier estimate (numeric, e.g. 0.30)
- Retainer monthly $ (int, cents-based input)
- Polish budget hours (numeric, 0.5 increments)
- Accepting bookings (toggle)
- Manual next-start override (date picker, optional)
- Public note (textarea — surfaces on the `/spec` OPS BOARD)
- Admin notes (textarea, private)

Changes immediately reflect on `/spec` OPS BOARD via RSC re-fetch (no caching at the request level).

## `/admin/spec/owner-approvals` — pending approvals queue

List of `spec_owner_approval_requests` rows in `pending` status.

Per row:
- Buyer name + email
- Account_holder name + email
- Company name
- Tier
- Age (requested_at)
- "Resend approval email" button
- "Cancel request" button (sets status `expired`, project → `cancelled`)

Useful when an account_holder doesn't respond.

## `/admin/spec/refunds` — refund queue

List of `spec_refund_requests` with `status in ('pending')`.

Per row:
- Customer info (name, email, project tier)
- Request source (`customer_initiated` or `stripe_dispute`)
- `is_guarantee_invocation` badge (true = within 30-day window, soft guarantee)
- `is_goodwill` toggle (post-30-day discretionary)
- Reason text (if provided)
- Eligibility check summary: within 30 days? chargeback initiated? non-payment disabled? material breach? (each a small yes/no chip)
- Milestones to act on (P1 / P2 / P3 / P4 checkboxes — pre-checked for the guarantee invocation case)
- **Refund-breakdown preview** — for each checked milestone, the UI computes and displays the action the processor will take based on the current `spec_payments` state:
  - `paid` → `refund` (Stripe Refunds API on the captured Payment Intent)
  - `invoiced` partially paid → `credit_note` (Stripe credit note for the unpaid portion + Stripe refund for the paid portion)
  - `invoiced` open (not paid) → `void` (Stripe void the invoice)
  - `invoiced` open + non-cancellable → `mark_uncollectible` (Stripe mark uncollectible)
  - `pending` (never invoiced) → no action; line greyed out
- Total cash refund amount (sum of action `refund` + the paid-portion of `credit_note` actions)
- Internal note field

Actions:
- "Process refund" — runs the per-milestone refund processor (see [03_WORKFLOW.md](03_WORKFLOW.md) § Refund processing), writes `refund_breakdown` to the request row, updates each `spec_payments` row to the correct state (`refunded`, `partially_refunded`, `voided`, `uncollectible`), flips `spec_module_entitlements.enabled = false` with `disabled_reason = 'refunded'`, fires `spec.refund_processed` email with the breakdown rendered as a line-by-line summary.
- "Deny" — sets `status = 'denied'`, requires reason text, sends explanation email to the customer.

All refunds processed manually per the "no automated refunds" rule from §10 of [01_BUSINESS_MODEL.md](01_BUSINESS_MODEL.md).

Customer request source:
- Phase 1 customer path is `/account/spec/[id]/request-refund`, gated to the buyer or account_holder.
- The customer route creates `spec_refund_requests` through a server route with safe fields only. It does not expose processing controls, Stripe IDs, internal notes, refund amount overrides, or entitlement toggles.
- `/admin/spec/refunds` remains the only refund processing surface.

The processed-refund detail view (clicking a processed row) renders the `refund_breakdown` array as a table — milestone, action, Stripe resource ID, amount, status, executed_at, error (if any). Useful in disputes and for the customer-support trail.

## `/admin/spec/referrals` — referral queue

Rows grouped by `spec_referrals.status`:

**Pending** (deposit paid, awaiting walkthrough)
- Referrer email, referred project, current project status
- Eligible date (= referred project's projected `walkthrough_completed_at` + 30 days)

**Eligible** (walkthrough completed, 30-day window started)
- Same + days until payout
- KYC status (Stripe Connect Express)
- Related-entity flag indicator if set
- "Process payout" button (creates Stripe transfer to referrer's Stripe Connect account → status `paid`, fires email)
- "Hold" button (manual block if Jackson sees a reason)

**kyc_required** (eligible but Stripe Connect not verified)
- "Send KYC reminder" button → emails referrer with the Express onboarding link

**review** (related-entity flag triggered, needs Jackson decision)
- Flag rationale (same domain / address / phone match)
- "Approve and pay" button → moves to `eligible` or directly to `paid` if KYC ready
- "Forfeit" button → sets status `forfeited`

**Paid** (bounty disbursed)
- Stripe transfer ID, paid date, referrer email, T4A-required flag, YTD referrer payout cents

**Forfeited** (referred customer invoked refund OR self-referral OR Jackson decision)
- Reason (linked refund request or note)

**Held** (referred project in dispute / refunded / non-payment disabled — temporary)
- Reason + linked project state

## `/admin/spec/blocked` — block list

Add/remove emails + Stripe customer IDs from `spec_blocked_buyers`. Used for post-dispute customers + others Jackson decides to block.

Per row:
- Email (unique within active block list)
- Stripe customer ID (optional)
- Blocked at + by
- Blocked reason
- "Unblock" button (sets `unblocked_at`)

Block list check happens in the Stripe payment-session creation API — a pre-flight query rejects payment if the email or customer ID is on the active block list.

## Permissions

Per "Never filter by role; only granular permission" (CLAUDE.md memory):

- All `/admin/spec/*` routes gated by `private.is_spec_operator()` — the dedicated SECURITY DEFINER function defined in [02_DATA_MODEL.md](02_DATA_MODEL.md) § Operator gate. Lives in the `private` schema per resolved `SPEC-SECURITY-DEFINER-PRIVATE-SCHEMA` (2026-05-25). The generic `has_permission(...)` check is NOT used here because `has_permission()` short-circuits to true for any customer-side company admin (verified live: the function consults `is_company_admin`, `account_holder_id`, and `admin_ids` before `role_permissions`). A customer-side admin must NEVER satisfy the SPEC operator gate.
- `private.is_spec_operator()` consults `role_permissions` (filtered to `permission='spec.admin', scope='all'`) and `user_permission_overrides` (filtered to `permission='spec.admin', granted=true`) only — never customer-company admin status. The `spec.admin` permission is granted to the dedicated `SPEC Operator` role (UUID `00000000-0000-0000-0000-0000000000a1`) at migration time, with Jackson added via `user_roles`. Future delegated SPEC operators are granted via `user_permission_overrides` with `company_id = OPS_OPERATIONS_COMPANY_ID` (the `company_id` column is NOT NULL on that table).
- No `.in("role", [...])` checks anywhere; always permission-based.
- The `admins` table (legacy, columns: `id`, `email`, `name`) is NOT used for SPEC admin gating. That table is a separate concept (staff directory).

Server-side: every admin server action checks `is_spec_operator()` before mutating. Client-side: the route segment `/admin/spec/layout.tsx` calls `is_spec_operator()` server-side and redirects to `/` on false.

The customer-facing project portal at `/account/spec/[id]` (Phase 2) is read-only and gated on project membership (buyer_user_id or account_holder_user_id), not on `is_spec_operator()`.

## Mobile

Per "No hit targets on OPS-Web" (CLAUDE.md memory): OPS-Web is mouse-driven desktop. Don't inflate icons or buttons to touch-friendly hit targets. Header icons 12-14px, inline 10-12px. Composer 14-16px max. Same applies to `/admin/spec/*` — Jackson reviews on his laptop. The iOS app is the exception.
