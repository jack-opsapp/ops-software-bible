# SPEC — Workflow & State Machine

> **Tier Model v2 (2026-07-14, [10_TIER_MODEL_V2.md](10_TIER_MODEL_V2.md) § 6):** the engagement state machine below survives v2 unchanged, with three per-tier payment deltas layered on top. (1) **SPEC-01 collapses the payment milestones to P1 → P4**: the `scope_signoff` acceptance event still fires (the intake distills into a countersigned work order before build), but **no invoice attaches to it** and there is no midpoint checkpoint — the invoice-issuing side effects at scope sign-off and midpoint are skipped for `tier='spec01'`. (2) **SPEC-03 writes `spec_projects.locked_total_cents` at the `scope_signoff` event** — P2/P3/P4 invoice amounts derive from `computeTierCheckpoints('spec03', locked_total_cents)`; until sign-off, the floor governs. (3) Care-plan state: `care_monthly_cents` is copied from capacity at insert (plus the white-label bump when `white_label = true`), and `care_started_at` stamps when the support window ends. Tier slugs everywhere are `spec01|spec02|spec03`.

The customer journey, start to finish. Every state transition, every timestamp, every side effect. Revised 2026-05-25 (third pass) to:

- Insert the pre-Stripe eligibility-address step so Quebec is rejected server-side BEFORE any Stripe payment session is created (CR-6, fourth-pass tightened Quebec rule).
- Make Path B record TWO acceptance events: the account_holder's `owner_purchase_approved` (at owner-approval), and the buyer's `tos_accepted` (at Stripe checkout completion). Both are kept in the dispute evidence chain (CR-5).
- Spell out the refund-processor procedure that splits actions per milestone state — `refund` for paid charges, `void` for open invoices, `credit_note` for partially paid, `mark_uncollectible` for non-cancellable open positions — and records each action in `spec_refund_requests.refund_breakdown` (CR-4).
- Reflect `spec_module_entitlements.enabled = false` at reservation time, flipped to `true` only at the delivery walkthrough (CR-7).
- Lock the queue-count semantics: queue = `awaiting_deposit` + `deposit_paid` (MJ-1).
- Have the webhook populate `spec_projects.tos_version_accepted` / `tos_accepted_at` (they are null until that point; the CHECK constraint allows that for `awaiting_owner_approval` / `awaiting_deposit`) (CR-2).

## Customer journey (happy path)

**T+0 — Visit**
Visitor lands on `/spec` (ad / organic / referral). UTM + ad-click params (gclid, fbclid) captured into a first-touch cookie (30-day persistence). Reads packages. Hovers, expands cards. Sees the OPS BOARD with the sanitized availability + waitlist + week-of next-start data sourced from `spec_public_board_snapshot` (refreshed every 5 min by pg_cron, edge-cached with `Cache-Control: public, max-age=300`).

**T+0 — Sign-in + tier click**
Clicks "Get started for $X" on a tier card. If not authenticated, redirected to OPS-Web sign-in/sign-up with `returnTo=/spec?tier=X`. Once signed in, control returns to `/spec`.

**T+0 — Eligibility address capture (pre-Stripe)**
Before any Stripe payment session is created, OPS renders a short address form that captures billing line1/line2, city, **province**, postal code, country, plus attestations that Customer has no Quebec head office, Quebec operating address, Quebec establishment, or material SPEC use in Quebec. Server-side rules:

- `country != 'CA'` → reject with explanation (CAD-only at launch).
- `province == 'QC'` → reject with explanation + contact-form link. **The Quebec billing block lives here, not at Stripe.** No `spec_projects` row is created.
- Quebec head office, operating address, establishment, or material SPEC use attested → reject with explanation + contact-form link. Billing address is not the only eligibility rule.
- Otherwise: a `spec_projects` row is created in `status = 'awaiting_owner_approval'` (Path B) or `status = 'awaiting_deposit'` (Path A). `billing_*` columns are populated. `tos_version_accepted` and `tos_accepted_at` remain NULL (allowed by the CHECK constraint in pre-deposit states).

**T+0 — Server resolves authority**
The `POST /api/spec/create-checkout-session` endpoint runs server-side:

1. Validate auth session, resolve `users.id` and `companies.id`.
2. Validate billing form payload and Quebec eligibility attestations; reject non-CA, Quebec billing address, Quebec head office, Quebec operating address, Quebec establishment, or material SPEC use in Quebec.
3. Compare `users.id::text` to `companies.account_holder_id`.
4. Block check: query `spec_blocked_buyers` by email (citext, case-insensitive) and `stripe_customer_id`. If matched and not unblocked, reject with 403.
5. Disqualifier check: optionally surface a pre-checkout prompt asking whether the engagement involves any excluded regulated workflows (PHI, PCI, regulated credit, surveillance, CASL-violating bulk messaging). Customer attestation captured.

If buyer == account_holder: branch to **Path A — direct checkout**.
If buyer ≠ account_holder: branch to **Path B — owner approval required, no charge yet**.

No-company buyer handling is locked (see 07_ROLLOUT.md § Gate resolutions → `SPEC-NO-COMPANY-BUYER-FLOW-LOCK`): `resolveSpecCompanyForProject(buyerUserId, tier)` runs before the address form is rendered. If the buyer has no `users.company_id`, the response is `409 { redirectTo: '/setup?returnTo=/spec?tier=X' }` — the existing OPS-Web `/setup` flow creates the company at `step='company'` (account_holder_id = buyerUserId), then returns the buyer to `/spec`. Every `spec_projects.linked_company_id` is therefore guaranteed non-null at insertion time, and Path A vs Path B branching always has a defined account_holder.

### Path A — Direct checkout (buyer is the account_holder)

The endpoint:
1. Creates a `spec_projects` row with `status = 'awaiting_deposit'`, `buyer_user_id`, `account_holder_user_id = buyer_user_id`, `linked_company_id`, attribution (UTM + gclid/fbclid from cookie), the captured billing address, and `tos_version_accepted = NULL` / `tos_accepted_at = NULL` (populated by the webhook).
2. Creates a Stripe Checkout Session (locked per resolved `SPEC-STRIPE-ADDRESS-TAX-SPIKE`, 2026-05-25). Parameters: `customer` (pre-filled with the OPS Customer's saved address), `customer_email`, `automatic_tax: { enabled: true }`, `billing_address_collection: 'required'`, `consent_collection: { terms_of_service: 'required' }` (Stripe's dedicated ToS checkbox — `custom_fields` doesn't support checkboxes), `phone_number_collection: { enabled: true }`, `custom_fields: [{ key: 'gst_hst_number', type: 'text', optional: true }]`. Metadata: `{ type: 'spec_deposit', spec_project_id, user_id, company_id, tier, tos_version_hash, utm_*, gclid, fbclid }`.
3. Returns the Stripe URL. Browser redirects.
4. Stripe collects phone (if not pre-filled), optional GST number via custom_field, and ToS acceptance via `consent_collection`. The hosted page allows the customer to edit the pre-filled billing address — Stripe has no parameter to lock it; the webhook step 5 defends against post-Stripe Quebec leakage.
5. On `checkout.session.completed` with `metadata.type === 'spec_deposit'`, the consolidated `/api/shop/webhook` runs the Quebec defense FIRST — if `session.customer_details.address.state === 'QC'` OR `country !== 'CA'`, refund the captured payment via Stripe Refunds API, cancel the project, add buyer to `spec_blocked_buyers`, notify operator, send `spec.quebec_rejected_post_stripe` email to customer, return. Otherwise:
   - Updates the `spec_projects` row: `status = 'deposit_paid'`, `deposit_paid_at = now()`, `tos_version_accepted = metadata.tos_version_hash`, `tos_accepted_at = session.created_at`, `tos_accepted_ip = session.client_ip` (from Stripe's recorded IP if available, else from the API route's request headers at session creation).
   - Inserts a `spec_acceptance_events` row with `event_type = 'tos_accepted'`, `accepted_by_user_id = buyer_user_id`, the IP, user agent, `signature_method = 'click_in_app'`, `payload_hash = tos_version_hash`.
   - Inserts a P1 row into `spec_payments` (`status = 'paid'`, `amount_cents = tier total * 0.25`).
   - Inserts a `spec_referrals` row (`status = 'pending'`) if `referrer_email` was captured. Self-referral / related-entity flags set per §9 of [01_BUSINESS_MODEL.md](01_BUSINESS_MODEL.md).
   - Fires `spec.deposit_confirmed` email to the customer.
   - Inserts an operator-facing notification (`company_id = OPS_OPERATIONS_COMPANY_ID`, `type='spec_deposit_received'`, `persistent=true`, `action_url=/admin/spec/{id}`) — renders in the OPS-Web edge-tab `NotificationsDrawer` and the `/admin/spec` TODAY queue — plus email to Jackson for high-urgency events.
   - Server-side conversion events sent to Meta CAPI + Google Enhanced Conversions (see [04_CUSTOMER_UX.md](04_CUSTOMER_UX.md) § Conversion tracking).
   - Customer redirected to `/spec/confirmation?session_id=...`.

### Path B — Owner approval required (buyer ≠ account_holder)

The endpoint:
1. Creates a `spec_projects` row with `status = 'awaiting_owner_approval'`, `buyer_user_id`, `account_holder_user_id`, `linked_company_id`, the captured billing address, attribution. **No Stripe call yet.** `tos_version_accepted` / `tos_accepted_at` remain NULL.
2. Creates a `spec_owner_approval_requests` row with `status = 'pending'`, `approved_total_cents` + `approved_deposit_cents` snapshot of the tier's pricing at request time, `approved_tos_version_hash = current ToS version hash`, a plaintext approval token emitted in the URL (bcrypt/argon2 hash of the token stored as `approval_token_hash`), `requested_at = now()`.
3. Fires `spec.owner_approval_required` email + persistent notification (recipient: account_holder) deep-linked to `/spec/owner-approval/[approval_token]`.
4. Buyer is redirected to `/spec/awaiting-approval` — a calm, no-pressure page showing: "Your owner [name] must approve this purchase before payment. We've sent them an email. You'll get a notification when they decide."
5. Account_holder clicks the link, lands on `/spec/owner-approval/[approval_token]`, signs in if not already, sees: "[Buyer name] is purchasing SPEC [tier] for [Company] for [CAD amount]. Review the current SPEC Terms of Service and approve or decline." A summary of the tier, the snapshotted total + deposit, and the ToS version hash are rendered. The full ToS is linked.
6. Approve action:
   - Server validates the bcrypt/argon2 hash of the inbound URL token against `approval_token_hash`. If no match or already used, error.
   - `spec_owner_approval_requests.status = 'approved'`, `decided_at`, `decided_ip`, `decided_user_agent` stamped.
   - **`spec_acceptance_events` insert with `event_type = 'owner_purchase_approved'`**, `accepted_by_user_id = account_holder_user_id`, the IP, user agent, `signature_method = 'click_in_app'`, `payload_hash = approved_tos_version_hash`. This row records the account_holder's binding acceptance of the purchase under the ToS as it stood at approval time. It is part of every dispute evidence package.
   - `spec_projects.status = 'awaiting_deposit'`, `owner_approved_at = now()`.
   - A new plaintext `buyer_checkout_token` is generated; the URL emits the plaintext, the DB stores `buyer_checkout_token_hash`. `buyer_checkout_expires_at = now() + interval '24 hours'`.
   - Fires `spec.owner_approval_granted` email to the buyer with a link to `/spec/checkout/[buyer_checkout_token]`.
7. Buyer clicks the link → server validates the token hash, creates the approved Stripe payment session (same metadata as Path A, with `tos_version_hash` carrying the version current at THAT moment — typically the same as the account_holder's, but if the ToS was updated between approval and buyer payment, the buyer accepts the newer version), redirects to Stripe. Token consumed on session creation (single-use).
8. After Stripe checkout completes, the webhook flow is identical to Path A — **with the second `spec_acceptance_events` row**: `event_type = 'tos_accepted'`, `accepted_by_user_id = buyer_user_id`, the IP, user agent, `payload_hash = the version the buyer actually accepted at Stripe`. The dispute evidence package for a Path B engagement carries BOTH the account_holder's `owner_purchase_approved` and the buyer's `tos_accepted` events.
9. Decline action: `spec_owner_approval_requests.status = 'declined'`, `spec_projects.status = 'cancelled'`, `cancellation_reason = 'owner_declined'`. No charge ever happened. Buyer notified via `spec.owner_approval_declined` email. No refund needed; no refund row created.

Token expiry: if the buyer doesn't click within 24h, the buyer_checkout_token hash is left in place but the server rejects on `buyer_checkout_expires_at < now()`. The buyer can request a new one from `/admin/spec` (Jackson) or simply re-trigger the flow (which produces a new approval request with a fresh approval_token + buyer_checkout_token).

### T+0 — Confirmation page

Customer lands on `/spec/confirmation?session_id=...`. Sees:
- Founder welcome video (Jackson, 60-90s) — embedded
- Visualized 4-milestone timeline with current position highlighted
- Primary CTA: open the intake (link from email is mirrored here for resilience)
- Secondary CTA: book discovery (greyed until intake is done)
- 30-day Guarantee Refund reminder anchored on "starts on the Walkthrough Date"
- Stripe receipt link

### T+0 to T+72h — Intake

Customer opens emailed intake link `/spec/intake/[token]`. Fills the 30-45 min form: business basics, team, money, current tools, workflow, pain points, success criteria, file uploads (Supabase Storage `spec-intake/{spec_project_id}/`, signed-URL access, 25MB per file, MIME-whitelisted). Autosaves per field. Regulated-workflow disqualifier surfaced again at intake submission with a hard block. Submits.

Submission:
- Updates `spec_projects.intake_completed_at`
- Stores `intake_responses` JSONB
- Server-side conversion event: `intake_submitted`
- Fires `spec.intake_completed_customer` email
- Inserts an operator notification (company_id = `OPS_OPERATIONS_COMPANY_ID`) + email to Jackson

### T+2-5 days — Discovery scheduling

Jackson reviews intake in `/admin/spec/[id]`. Sends Calendly/Cal.com link via email (logged in `spec_communications`). Customer books → `discovery_scheduled_at` updated. Server-side conversion event: `discovery_booked`.

### T+~7 days — Discovery session(s)

First session held → status → `discovery`, `discovery_started_at = now()`. Jackson drafts the scope doc. The scope doc is created as a `spec_scope_documents` row with `version = 1`, `content_hash = sha256(content_json)`, optional `external_url` for the Notion or Google Doc human-readable version, `drafted_at = now()`.

Scope doc sent to customer → `spec_scope_documents.sent_at = now()`, `scope_doc_sent_at` mirrored on `spec_projects`. Customer reviews and accepts in-app or via DocuSign or by email reply. Acceptance is recorded as a `spec_acceptance_events` row with `event_type = 'scope_signoff'`, `scope_document_id` pointing at the version they accepted, `payload_hash = the scope doc's content_hash`, IP, user agent, `signature_method`.

Scope sign-off triggers:
- Status → `building`
- `scope_doc_signed_at` mirrored on `spec_projects`
- `subscription_locked_at` set, `locked_subscription_multiplier`, `locked_module_surcharge_cents` finalized from the scope doc
- P2 row created in `spec_payments` (`status = 'invoiced'`); Stripe Invoice fires (net-15)
- `spec_feature_acceptance` rows seeded from the scope doc's feature list, each linked to `scope_document_id`
- **`spec_module_entitlements` rows reserved for each module key in the scope, with `enabled = false`, `disabled_reason = 'not_yet_delivered'`.** The row reserves the multiplier + surcharge under the scope; access does NOT turn on at sign-off. Access flips on only at the delivery walkthrough.
- Fires `spec.scope_doc_signed_customer` email + P2 invoice notification
- `build_started_at` set when work begins (immediately after P2 paid or on Jackson's start-date commitment)
- `estimated_completion_date` computed from `build_started_at + build_days_max`

If the scope is revised after signoff (rare; usually a small clarification), a new `spec_scope_documents` row with `version = 2` is created and the old row gets `superseded_at`. The customer signs the new version, producing a new `spec_acceptance_events` row pointing at version 2.

### T+~10-21 days — Build

Jackson builds. Logs progress in `spec_communications` weekly. Updates `estimated_completion_date` as the build progresses.

Side-states possible:
- `on_hold` with `hold_type = 'customer_requested'` — customer-paused. Slot freed.
- `on_hold` with `hold_type = 'ops_blocked'` — waiting on the customer for something OPS cannot proceed without. Slot still consumed.
- Scope-change mid-flight → new `spec_change_orders` row, customer accepts via `spec_acceptance_events` (event_type `change_order_accepted`), work continues.

### T+~halfway — Midpoint demo

Jackson schedules the midpoint demo. `midpoint_demo_at` set. Demo runs (showing ~50% of scope on staging). Customer reviews + accepts.

Acceptance is recorded as a `spec_acceptance_events` row with `event_type = 'midpoint_accepted'`, IP, user agent. `midpoint_accepted_at` mirrored on `spec_projects`. P3 row created in `spec_payments`, Stripe Invoice fires (net-15). Satisfaction survey sent (rate each feature 1-5). `spec.p3_invoice` email + notification fire.

### T+~build complete — Delivery

Jackson deploys modules to the customer's OPS instance. **`spec_module_entitlements.enabled = true` for each module row at this point, `enabled_at = now()`, `disabled_reason = NULL`.** This is when access turns on — not at scope sign-off. Schedules the live walkthrough call.

Walkthrough call held + recorded:
- `walkthrough_completed_at` stamped — **the canonical anchor for everything downstream**
- `walkthrough_recording_url` stored
- Acceptance recorded as `spec_acceptance_events` row with `event_type = 'delivery_accepted'`
- Status → `support`
- `support_window_ends_at = walkthrough_completed_at + tier_support_window_days`
- P4 row created, Stripe Invoice fires (net-15)
- Satisfaction survey #2 sent
- `spec_referrals` row (if any) → `eligible_at = walkthrough_completed_at` (payout authorized 30 days later, gated on KYC + no refund)
- Fires `spec.p4_invoice` + `spec.support_window_open` emails
- Server-side conversion event: `delivery_walkthrough_completed`

### T+support window — Support phase

Customer uses modules. Files `spec_support_tickets` (phase = `support`) via OPS-Web admin or email. Jackson tags severity, resolves critical/high free, escalates cosmetic/enhancement to billable change orders.

7 days before support window ends → `spec.support_ending_7d` email (retainer preview).

### T+support end — Path decision

Customer offered the retainer via `spec.support_ending_0d` email with one-click Stripe subscription/payment link. Two paths:

**Path A — Subscribes to retainer:**
- `spec_retainers` row created + Stripe subscription
- Status → `on_retainer`
- `retainer_started_at = now()`
- Future tickets filed with `phase = 'retainer'`

**Path B — Declines retainer:**
- Status → `completed`
- `completed_at = now()`
- 14d later, final retainer-offer reminder email
- Future work is ad-hoc (`phase = 'ad_hoc'`) billable at $225/hr with no response-time guarantee

### T+30d post-walkthrough — Referral payout

If `spec_referrals` row exists for this project, no refund invoked, KYC verified, and no related-entity hold pending:
- Status → `paid`
- Stripe Transfer to the referrer's Stripe Connect Express account
- `paid_at = now()`
- `spec.referrer_bounty_paid` email fires
- T4A reporting flag updated if referrer is Canadian and YTD payouts to that referrer (derived from `sum(bounty_cents) WHERE referrer_email = X AND status = 'paid' AND paid_at >= date_trunc('year', now())`) exceed $500 CAD

If KYC missing: status → `kyc_required`, email referrer with KYC link, hold indefinitely.
If related-entity flag set: status → `review`, notify Jackson, manual decision.

## Refund processing — per-milestone procedure (CR-4)

When Jackson clicks "Process refund" on `/admin/spec/refunds` for a guarantee invocation (or any other approved refund), the server-side processor walks each of the four milestones and applies the correct action based on the `spec_payments` row's state:

```
for milestone in [deposit, scope_signoff, midpoint, delivery]:
    payment = spec_payments.where(spec_project_id=X, milestone=Y).first()
    if not payment:
        # Milestone never invoiced — nothing to refund.
        continue

    breakdown_entry = {milestone: Y, stripe_resource_id: ..., action: ..., amount_cents: ..., status: ..., executed_at: ...}

    if payment.status == 'paid':
        # Stripe Refunds API on the underlying Payment Intent.
        result = stripe.refunds.create(payment_intent=payment.stripe_payment_intent_id, amount=payment.total_cents)
        payment.status = 'refunded'
        payment.refunded_at = now()
        payment.amount_refunded_cents = payment.total_cents
        breakdown_entry.action = 'refund'
        breakdown_entry.stripe_resource_id = result.id

    elif payment.status == 'invoiced' and invoice_is_partially_paid(payment.stripe_invoice_id):
        # Refund the paid portion, credit-note the unpaid portion.
        paid_amount = stripe_invoice_paid_amount(payment.stripe_invoice_id)
        # Step 1: refund the paid portion.
        refund_result = stripe.refunds.create(payment_intent=payment.stripe_payment_intent_id, amount=paid_amount)
        # Step 2: issue a credit note for the unpaid portion to close the invoice.
        cn_result = stripe.credit_notes.create(invoice=payment.stripe_invoice_id, amount=payment.total_cents - paid_amount)
        payment.status = 'partially_refunded'
        payment.refunded_at = now()
        payment.amount_refunded_cents = paid_amount
        payment.credit_note_stripe_id = cn_result.id
        breakdown_entry.action = 'credit_note'   # the credit note closes it; refund is recorded separately
        breakdown_entry.stripe_resource_id = cn_result.id

    elif payment.status == 'invoiced':
        # Open invoice. Try to void; if the invoice has been finalized in a way that prevents
        # voiding (e.g. uncollectible-already), mark uncollectible instead.
        try:
            stripe.invoices.void_invoice(payment.stripe_invoice_id)
            payment.status = 'voided'
            payment.voided_at = now()
            breakdown_entry.action = 'void'
            breakdown_entry.stripe_resource_id = payment.stripe_invoice_id
        except stripe.InvoiceNotVoidableError:
            stripe.invoices.mark_uncollectible(payment.stripe_invoice_id)
            payment.status = 'uncollectible'
            payment.marked_uncollectible_at = now()
            breakdown_entry.action = 'mark_uncollectible'
            breakdown_entry.stripe_resource_id = payment.stripe_invoice_id

    elif payment.status == 'overdue':
        # Same logic as 'invoiced' — overdue is just an unpaid invoice past due_date + grace.
        # Try void; fall back to mark_uncollectible.
        ...

    elif payment.status == 'pending':
        # Never invoiced; nothing to do.
        continue

    elif payment.status in ('refunded', 'partially_refunded', 'voided', 'uncollectible'):
        # Already handled in a prior refund pass.
        continue

    refund_breakdown.append(breakdown_entry)

# After all four milestones processed:
spec_refund_requests.refund_breakdown = refund_breakdown
spec_refund_requests.total_refund_cents = sum(b.amount_cents for b in refund_breakdown if b.action in ('refund', 'credit_note'))
spec_refund_requests.stripe_refund_ids = [b.stripe_resource_id for b in refund_breakdown if b.action == 'refund']
spec_refund_requests.processed_at = now()
spec_refund_requests.status = 'processed' if all(b.status == 'succeeded' for b in refund_breakdown) else 'partial'
# Disable entitlements
spec_module_entitlements.where(spec_project_id=X).update(enabled=False, disabled_reason='refunded', disabled_at=now())
spec_projects.status = 'refunded'
spec_projects.refunded_at = now()
# Fire customer email
send_email('spec.refund_processed', recipient=customer_email, breakdown=refund_breakdown)
```

The admin refund queue UI surfaces a preview of `refund_breakdown` before the operator clicks Process, so Jackson sees exactly which action will be taken per milestone.

## Sideways branches (must all be supported)

### Owner declines (Path B above)
- `spec_owner_approval_requests.status = 'declined'`
- `spec_projects.status = 'cancelled'`
- `cancellation_reason = 'owner_declined'`
- Buyer notified via `spec.owner_approval_declined`
- No charge happened → no refund needed

### Owner approval token expires
- 7-day expiration on the `approval_token_hash`
- Cron at expiry: `spec_owner_approval_requests.status = 'expired'`, `spec_projects.status = 'cancelled'` (if no other path forward), buyer + account_holder both notified

### Ghosted post-deposit (no intake)
- T+14d: nudge email #1
- T+30d: nudge email #2 + status → `stalled`
- T+60d: final nudge email
- T+90d: stop emailing. No auto-refund.
- Customer re-engages anytime → Jackson decides re-slot vs fresh

### Intake completed, no discovery booked
- T+7d: nudge email
- T+21d: nudge email #2 + status → `stalled`
- T+60d: final nudge
- T+90d: stop emailing

### Discovery no-shows
- 1st: free reschedule (≥ 24h advance notice required for future)
- 2nd: $100 reschedule fee invoiced via Stripe, net-15
- 3rd: engagement cancelled. Deposit forfeited. `forfeit_at` set. Modules disabled (already disabled if never delivered; explicitly flipped to `disabled_reason = 'ops_decision'` if any were).

### Customer-requested pause (`hold_type = 'customer_requested'`)
- Customer requests via email or admin → status `on_hold`, `hold_type = 'customer_requested'`
- `on_hold_at`, `on_hold_reason`, `prior_status` (e.g. `building`) set
- `on_hold_expires_at = on_hold_at + 90 days`
- **Slot freed** (others can book into it; capacity snapshot re-derives at next 5-min cron)
- Customer resumes any time → status restored to `prior_status`, `resumed_at` stamped, rejoins queue
- After 90d: cron flips status → `stalled_on_hold`, no auto-refund

### OPS-blocked (`hold_type = 'ops_blocked'`)
- OPS waiting on customer for input/files/credentials/integration → status `on_hold`, `hold_type = 'ops_blocked'`
- `on_hold_at`, `on_hold_reason`, `prior_status` set
- `on_hold_expires_at` not auto-set (Jackson manages manually; typical 1-2 weeks)
- **Slot still consumed** (build is still active in Jackson's queue)
- Customer provides the blocker → `resume_requested_at`, then `resumed_at`, status → `prior_status`
- After 30 days of `ops_blocked` with no movement: Jackson decides to convert to `customer_requested` (frees slot) or escalate to stall

### Refund pre-delivery (customer-initiated)
- Refund matrix from §3 of [01_BUSINESS_MODEL.md](01_BUSINESS_MODEL.md):
  - Pre-discovery: typically full deposit refund (Jackson's discretion)
  - Post-discovery, pre-scope-signoff: pro-rated (deposit minus discovery work)
  - Post-scope-signoff, pre-delivery: pro-rated (unstarted milestones refundable)
- All refunds manual via `/admin/spec/refunds`. `is_guarantee_invocation = false`.
- Per-milestone actions run through the same refund processor above — for example, if P2 has been invoiced but not paid, the processor voids it; the refund_breakdown records the void.

### 30-day Guarantee Refund invoked
- Customer requests via `/account/spec/[id]/request-refund` or written notice by email
- Pre-check: within 30 days after the Walkthrough Date? No chargeback? No fraud? No material misrepresentation? No prohibited workflow? No material breach? No continued use after refund? Guarantee clock tolled for any non-payment disabled period. If any fail, status `denied` with reason.
- `spec_refund_requests` row created: `request_source = 'customer_initiated'`, `is_guarantee_invocation = true`, `is_goodwill = false`. The unique partial index enforces one-per-engagement.
- Jackson clicks "Process refund" → refund processor runs per-milestone (above)
- All `spec_module_entitlements` for the project → `enabled = false`, `disabled_reason = 'refunded'`
- Status → `refunded`
- Referral (if any) → `forfeited`
- Customer receives `spec.refund_processed` email with the refund_breakdown shown line-by-line

### Post-30-day refund request (goodwill)
- Same row mechanic but `is_goodwill = true`, `is_guarantee_invocation = false`
- Build fees non-refundable as a matter of policy (Jackson decides how much to refund; partial refunds run through the same processor with the milestones to-be-acted-on selected in the UI)
- LIL 12-month-fees cap from §3 of [01_BUSINESS_MODEL.md](01_BUSINESS_MODEL.md) applies if the customer claims damages

### Stripe dispute (chargeback)
- Stripe `charge.dispute.created` webhook fires
- All `spec_module_entitlements` for the project → `enabled = false`, `disabled_reason = 'dispute'`
- Persistent notification to Jackson (company_id = `OPS_OPERATIONS_COMPANY_ID`)
- `spec_payments` row status → `disputed`
- Guarantee Refund for that engagement closed (anti-abuse rule)
- Evidence package assembled: ToS acceptance event (and `owner_purchase_approved` if Path B), scope signoff event, scope_document content_json + content_hash, all subsequent acceptance events, intake responses, walkthrough recording URL, full communications log
- OPS wins: engagement cancelled, customer added to `spec_blocked_buyers`
- OPS loses: full reversal, engagement cancelled, customer added to `spec_blocked_buyers`

### Tier upgrade mid-engagement
- Pre-scope-signoff: full pro-rated. `original_tier` recorded, `tier` updates, `tier_upgraded_at` set. New deposit balance computed. Stripe Invoice for delta.
- Post-scope-signoff: case-by-case. `spec_change_orders` row with `change_type = 'tier_upgrade'`, customer accepts via `spec_acceptance_events`.

### Platform feature sunset
- 90 days advance notice email to affected customers
- With retainer: rebuild free via new `spec_change_orders` row (`change_type = 'platform_compat_rebuild'`)
- Without retainer: rebuild billable at $225/hr or a fixed quote
- Customer declines rebuild → that functionality unavailable

## State machine diagram

```
                 ┌─────────────────────────────┐
   buyer ≠       │ awaiting_owner_approval     │  (Stripe NOT charged yet)
   owner    ───▶ └──────────┬──────────────────┘
                            │ owner approves (no charge)
                            │ + owner_purchase_approved event
                            ▼
                 ┌─────────────────────────────┐
                 │ awaiting_deposit            │  (buyer has short-lived checkout token)
                 └──────────┬──────────────────┘
                            │ buyer completes Stripe payment
                            │ + tos_accepted event (buyer)
                            ▼
   buyer ==      ┌─────────────────────────────┐
   owner    ───▶ │      deposit_paid           │
                 └──────────┬──────────────────┘
                            │ first discovery session held
                            ▼
                 ┌─────────────────────────────┐
                 │       discovery             │
                 └──────────┬──────────────────┘
                            │ scope doc signed (P2 fires)
                            │ entitlement rows reserved (enabled=false)
                            ▼
                 ┌─────────────────────────────┐
                 │       building              │◀────┐
                 └──────────┬──────────────────┘     │ resume
                            │                        │
                            │ pause request          │
                            ▼                        │
                 ┌─────────────────────────────┐     │
                 │       on_hold               ├─────┘
                 │  (hold_type:                │
                 │   customer_requested OR     │
                 │   ops_blocked)              │
                 └──────────┬──────────────────┘
                            │ 90d expiry (customer_requested only)
                            ▼
                 ┌─────────────────────────────┐
                 │   stalled_on_hold           │  (terminal-ish, no auto-refund)
                 └─────────────────────────────┘

                 ┌─────────────────────────────┐
                 │       building              │
                 └──────────┬──────────────────┘
                            │ walkthrough_completed_at (P4 fires)
                            │ entitlements flip enabled=true
                            ▼
                 ┌─────────────────────────────┐
                 │       support               │
                 └──────────┬──────────────────┘
                            │ support window ends
                            ▼
              ┌─────────────┴─────────────┐
              ▼                           ▼
   ┌────────────────────┐         ┌────────────────────┐
   │    on_retainer     │         │     completed      │
   └────────────────────┘         └────────────────────┘

  From any non-terminal state, by customer action or escalation:
  → cancelled (with manual refund decision)
  → refunded (after refund processor runs per-milestone)
  → stalled (no contact for 30+ days during deposit_paid/discovery)
```

## Capacity-consuming states

A SPEC project consumes one slot in `spec_capacity.slot_ceiling[tier]` when status is one of:
- `discovery`
- `building`
- `on_hold` with `hold_type = 'ops_blocked'` (slot still consumed because the build is alive in Jackson's queue)

A project is in **queue** but not consuming a slot when status is one of (locked: MJ-1):
- `awaiting_deposit` (approval granted or Path A pre-Stripe-redirect; checkout pending)
- `deposit_paid`

A `customer_requested` hold frees the slot:
- `on_hold` with `hold_type = 'customer_requested'` does NOT consume a slot

Terminal / no-capacity-impact statuses:
- `completed`, `on_retainer`, `stalled`, `stalled_on_hold`, `cancelled`, `refunded`, `awaiting_owner_approval` (paid nothing, not committed)

The `refresh_spec_board_snapshot()` function uses these same definitions — `active_ct` counts the slot-consuming three; `queue_ct` counts `awaiting_deposit` + `deposit_paid`.
