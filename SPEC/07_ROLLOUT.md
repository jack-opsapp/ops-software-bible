# SPEC — Phased Rollout, Verification & Open Items

Four implementation phases, full verification plan, critical file list, and outstanding items. Fourth revision pass (2026-05-25) locks the external legal/pro verdict: Phase 0 conversation-only launch is approved; automated live SPEC deposits are not approved until final customer-facing legal prose exists and this pass's legal fixes are applied. Counsel review is recommended risk mitigation, not a hard launch blocker per Jackson's decision.

## Phase 0 — Make live `/spec` safe (immediate)

The live `/spec` page on opsapp.co currently charges 50% deposits, lacks an auth gate, lacks ToS acceptance, omits required Stripe metadata, and has no Stripe Tax. Running paid ads or automated live deposits against this URL is unsafe. Phase 0 conversation-only launch is approved while Phase 1 builds out the real flow.

**Approved Phase 0 posture: conversation-only.**

The three Pay Deposit buttons on `/spec` are replaced with "Talk to the founder" CTAs. The Stripe payment API route is mothballed or feature-flagged off. Customer flows through a contact form or a Cal.com link. Jackson can handle paid work manually only after final legal text exists for that manual engagement path.

Time: hours. Risk: zero (no automated payment flow).

**Optional safety flag while Phase 1 is built.**

A new env flag `SPEC_LIVE_DEPOSITS_ENABLED` (default `false`) may gate the create-checkout-session route. When false, the route returns a 503 with a UI message redirecting to a contact form. The page rendering reads the same flag — when false, the Pay Deposit buttons render as "Talk to the founder" CTAs. The flag can only flip true after Phase 1 launch gates pass.

Time: < 1 hour. Risk: low (flag default is off).

**Phase 0 also:**
- Updates the `/spec` page metadata to remove any claim that "we're accepting deposits today" if it exists in copy
- Confirms that ads and automated deposits are paused until Phase 1 launch gates pass

## Phase 1 — Ads-launch-ready

Everything required to safely run a paid ads campaign and automated live deposits. Must ship before any ad spend or automated live deposit.

### 1. Schema migrations

Eight migration files (split for clarity):
- `migrations/YYYYMMDD_spec_phase1_enums_and_capacity.sql` — enums + `spec_capacity` seed + `citext` extension
- `migrations/YYYYMMDD_spec_phase1_internal_company.sql` — "OPS Operations" company seed (constant UUID exported to application code as `OPS_OPERATIONS_COMPANY_ID`)
- `migrations/YYYYMMDD_spec_phase1_operator_gate.sql` — `private.is_spec_operator()` SECURITY DEFINER function in the `private` schema + grants (USAGE on `private` to `authenticated, service_role`; EXECUTE on the function to `public`) + dedicated `SPEC Operator` role (UUID `00000000-0000-0000-0000-0000000000a1`, hierarchy `0`, `is_preset = true`, `company_id = null`) + `spec.admin / all` row in `role_permissions` + Jackson added via `user_roles`. Resolved per `SPEC-SECURITY-DEFINER-PRIVATE-SCHEMA` and `SPEC-LIVE-SCHEMA-MISMATCHES`.
- `migrations/YYYYMMDD_spec_phase1_core_tables.sql` — `spec_projects` (with `billing_*` columns, CHECK constraints, `is_test`), `spec_owner_approval_requests` (with `approval_token_hash` / `buyer_checkout_token_hash`, snapshotted totals, `is_test`), `spec_scope_documents`, `spec_acceptance_events` (incl. `owner_purchase_approved`), `spec_module_entitlements` (default `enabled = false`)
- `migrations/YYYYMMDD_spec_phase1_money_tables.sql` — `spec_payments` (extended status enum: `voided`, `partially_refunded`, `uncollectible`), `spec_change_orders`, `spec_refund_requests` (with `refund_breakdown` jsonb), `spec_referrals` (no YTD denorm), `spec_retainers`
- `migrations/YYYYMMDD_spec_phase1_workflow_tables.sql` — `spec_feature_acceptance`, `spec_satisfaction_ratings`, `spec_support_tickets`, `spec_communications`, `spec_blocked_buyers` (email as citext)
- `migrations/YYYYMMDD_spec_phase1_snapshot_and_rls.sql` — `spec_public_board_snapshot` table + `private.refresh_spec_board_snapshot()` function in the `private` schema (EXECUTE granted to `service_role` only) + `pg_cron` schedule (runs as `postgres`, no grant needed) + CONCRETE RLS policies per table that call `private.is_spec_operator()` (no placeholders, no `public.*` references) + grants. The legacy `spec_board_counts` view is NOT created.
- `migrations/YYYYMMDD_spec_phase1_storage.sql` — `spec-intake` Supabase Storage bucket + RLS + MIME whitelist + 25MB size limit

No `companies` table extensions (the original two booleans are removed before they shipped; entitlement state lives in `spec_module_entitlements`).

### 2. Legal (Phase 1, before any deposit fires)

- `/legal?page=spec-terms` final customer-facing ToS prose drafted and published (per [06_CONTRACT_AND_EMAILS.md](06_CONTRACT_AND_EMAILS.md)). A section outline is not enough.
- `/legal?page=privacy` final Privacy Policy prose updated to cover SPEC-specific data (intake responses, file uploads, scope docs, satisfaction surveys, communications log).
- `/legal?page=dpa` final DPA prose reviewed for SPEC scope; if changes needed, version bump.
- Jackson owner self-review against the fourth-pass legal/commercial corrections.
- Outside counsel review by Jackson's BC business counsel is recommended risk mitigation, not a hard launch blocker per Jackson's decision.
- Build-time hash captured + exported as `SPEC_TERMS_VERSION_HASH` constant.
- Click-to-accept checkbox in the approved Stripe payment flow.

### 3. `/spec` marketing page revisions

- OPS BOARD section (between HowItWorks and Pricing) — reads from `spec_public_board_snapshot` table via `/api/spec/board` (Cache-Control public, max-age=300); exposes `refreshed_at` to the UI
- Pricing card rewrite: show P1 amount as headline (25% of total), 4-milestone breakdown on expand, subscription multiplier estimate, retainer cost, money-back badge
- "Standing Behind The Work" section (per [04_CUSTOMER_UX.md](04_CUSTOMER_UX.md)) with the revised "Pay as work clears review" copy
- HowItWorks step copy revisions
- FAQ rewrite per [04_CUSTOMER_UX.md](04_CUSTOMER_UX.md) — must use `<details>/<summary>` or pre-rendered-visible pattern so answers ship in initial HTML
- SocialProof unverified-stats removed (en + es dictionaries + `SocialProof.tsx`)
- Founder presence (hero or dedicated section — asset dependency, see open items)
- Numbers compliance audit (JetBrains Mono tabular-lining slashed-zero everywhere)

### 4. Auth + billing-address + owner-approval gate

- Auth check on "Pay Deposit" click → redirect to OPS-Web sign-in/sign-up with `returnTo=/spec?tier=X`
- **Company gate on "Pay Deposit" click.** After auth, server-side calls `resolveSpecCompanyForProject(buyerUserId, tier)`. If the user has no `company_id` (or the company is soft-deleted), 409 + redirect to `/setup?returnTo=/spec?tier=X`. The existing OPS `/setup` flow creates the company at `step='company'`, then resumes `/spec`. Resolved per `SPEC-NO-COMPANY-BUYER-FLOW-LOCK`. No-company buyer paths through SPEC are eliminated — every `spec_projects.linked_company_id` is guaranteed non-null.
- **Pre-Stripe eligibility-address form** on `/spec/billing-address`: captures line1/line2, city, province, postal code, country, plus attestations for no Quebec head office, operating address, establishment, or material SPEC use in Quebec. Server-side rejects `province == 'QC'`, `country != 'CA'`, or any Quebec eligibility attestation failure. No `spec_projects` row is created for rejected addresses. This is the canonical Quebec block.
- Server resolves buyer's `users.id` vs `companies.account_holder_id` after address validation.
- Path A (buyer = account_holder) → Stripe Checkout Session opens. Per resolved `SPEC-STRIPE-ADDRESS-TAX-SPIKE`, the session is created with: `customer` (pre-filled with the Customer's saved address from OPS), `customer_email`, `automatic_tax: { enabled: true }`, `billing_address_collection: 'required'`, `consent_collection: { terms_of_service: 'required' }`, `phone_number_collection: { enabled: true }`, `custom_fields` for optional GST/HST number, `metadata`: `{ type: 'spec_deposit', spec_project_id, user_id, company_id, tier, tos_version_hash, utm_*, gclid, fbclid }`.
- Path B (buyer ≠ account_holder) → owner-approval flow, NO Stripe call until owner approves. Owner-approval action writes a `spec_acceptance_events` row with `event_type = 'owner_purchase_approved'`. Tokens stored as bcrypt/argon2 hashes; URL emits plaintext.
- GST/HST number optional field via `custom_fields`; phone required via `phone_number_collection`; ToS-accept via `consent_collection.terms_of_service='required'` (writes the buyer's `tos_accepted` event on Stripe completion using `session.consent.terms_of_service === 'accepted'`).

**Stage C.1 implementation status (2026-05-26):** Landed on `feat/spec-checkout-flow` (ops-site) + `feat/spec-setup-returnto` (OPS-Web). New files: `src/lib/auth/{verify-token,find-user-by-auth,get-current-user}.ts`; `src/lib/spec/{resolve-company,quebec-validation,attribution,conversion-events,pricing,token-hash,email-outbox,tos-version}.ts`; `src/components/spec/BillingAddressForm.tsx`; `src/app/spec/billing-address/page.tsx`; `src/app/api/spec/create-checkout-session/route.ts` (rewritten). OPS-Web `src/app/(onboarding)/setup/page.tsx` honors the `returnTo` query param after the company step (same-origin relative paths only — schemes and protocol-relative rejected). Migration `ops-software-bible/migrations/2026-05-26-01-spec-stage-c1-outboxes.sql` adds `conversion_event_outbox` + `spec_email_outbox` (both operator/service-role only). Master gate `SPEC_LIVE_DEPOSITS_ENABLED` remains the kill switch — the route 503s while false. Approval-token hashing uses SHA-256 of high-entropy (192-bit) tokens; constant-time compare; equivalent security to bcrypt for this entropy class. `tos-version.ts` exports a placeholder hash pending the Stage G port (P1-2-5) — `SPEC_TERMS_VERSION_HASH = 'pending-stage-g-port'` until the legal-content registration lands.

### 5. Stripe webhook handler

Extension to existing `/api/shop/webhook`, dispatched on `event.type === 'checkout.session.completed'` AND `metadata.type === 'spec_deposit'`:

- **Quebec post-Stripe defense (FIRST, before any deposit_paid mutation).** Inspect `session.customer_details.address.state` and `.country`. If `state === 'QC'` OR `country !== 'CA'`, immediately refund the captured payment via `stripe.refunds.create({ payment_intent: session.payment_intent, reason: 'requested_by_customer' })`, update `spec_projects.status='cancelled'` with `cancellation_reason='quebec_billing_at_stripe'`, insert the buyer into `spec_blocked_buyers` (misrepresentation per ToS § 3), send email `spec.quebec_rejected_post_stripe`, dispatch persistent operator notification, and return. Resolved per `SPEC-STRIPE-ADDRESS-TAX-SPIKE`.
- Otherwise: update the pre-existing `spec_projects` row (created by the create-checkout-session API after address validation): `status = 'deposit_paid'`, `deposit_paid_at = now()`, `tos_version_accepted = metadata.tos_version_hash`, `tos_accepted_at = now()`, `tos_accepted_ip` populated. The CHECK constraint on `spec_projects` permits these fields being NULL pre-deposit; this webhook is where they become NOT NULL.
- Insert `spec_acceptance_events` row for `tos_accepted` (buyer's user_id). For Path B engagements, the `owner_purchase_approved` row was already inserted at owner-approval time — this is the second of two acceptance events.
- Create P1 `spec_payments` row marked paid.
- If `companies.stripe_customer_id IS NULL`, populate it from `session.customer` (first-time customer mapping for future SPEC subscription billing).
- Insert `spec_referrals` row if referrer captured.
- **Notifications dispatch (per resolved `SPEC-NOTIFICATION-RAIL-DEPRECATED`).** Send customer email `spec.deposit_confirmed`. Insert customer notification (`user_id=buyer_user_id, company_id=linked_company_id, type='spec_deposit_confirmed', persistent=false, action_url=/account/spec/{id}/request-refund`). Insert operator notification (`user_id=each_spec_operator, company_id=OPS_OPERATIONS_COMPANY_ID, type='spec_deposit_received', persistent=true, action_url=/admin/spec/{id}`).
- Server-side conversion event sends (Meta CAPI + Google Enhanced).
- Handle `charge.dispute.created` — flip entitlements off, notify (in-app rail + email to Jackson), log, close 30-day guarantee window.

### 6. Owner-approval flow

- `POST /api/spec/owner-approval/[token]` (approve / decline)
- `/spec/owner-approval/[approval_token]` page
- `/spec/awaiting-approval` page (wait state for the buyer)
- `/spec/checkout/[buyer_checkout_token]` page (post-approval checkout)

### 7. Intake form `/spec/intake/[token]`

- Token-gated, single-page form with autosave per field
- All sections per [04_CUSTOMER_UX.md](04_CUSTOMER_UX.md), including the regulated-workflow attestation
- File upload to Supabase Storage bucket `spec-intake/{spec_project_id}/`
- Submission updates `intake_completed_at`, fires emails, inserts notifications
- Server-side conversion event: `intake_submitted`

### 8. Confirmation page rewrite `/spec/confirmation`

- Founder welcome video embed (asset dependency — see open items)
- Timeline visualization (4 milestones, current position highlighted)
- Intake link + Calendly booking
- Receipt + 30-day guarantee reminder (anchored on "starts at your delivery walkthrough")

### 9. Admin in OPS-Web `/admin/spec`

- TODAY command queue (top of the overview page)
- Kanban pipeline view with owner-approval and hold-type columns
- Project detail page with all tabs per [05_ADMIN_UX.md](05_ADMIN_UX.md), including the Entitlements tab (with enabled/disabled toggle + reason picker) and the test-mode toggle in the page header
- Capacity config editor + manual "Force refresh board snapshot" button (calls `private.refresh_spec_board_snapshot()` via service-role)
- Owner-approvals queue
- Manual refund processing page with eligibility chips + per-milestone `refund_breakdown` preview
- Reuse existing OPS-Web admin auth + layout; **gate every route on `private.is_spec_operator()`** (the function lives in the `private` schema per resolved `SPEC-SECURITY-DEFINER-PRIVATE-SCHEMA`) — NOT the generic `has_permission(...)` (which short-circuits through customer-company admin checks)

### 9A. Customer refund request route

- Add `/account/spec/[id]/request-refund` as a Phase 1 minimal route.
- Gate to buyer/account_holder only.
- Server route creates `spec_refund_requests` with safe fields only: `spec_project_id`, `request_source='customer_initiated'`, `customer_reason_text`, `is_guarantee_invocation` computed server-side, and `is_goodwill` computed server-side.
- No customer access to processing controls, Stripe IDs, refund amount overrides, internal notes, or entitlement toggles.
- Admin processing remains in `/admin/spec/refunds`.

### 10. Conversion tracking infra

- First-touch UTM + gclid/fbclid cookie set on `ops_attribution` (30-day Max-Age, SameSite=Lax)
- Server-side event sends to Meta CAPI + Google Enhanced for: `pay_deposit_click`, `owner_approval_requested`, `stripe_checkout_opened`, `stripe_checkout_completed` (primary), `intake_started`, `intake_submitted`, `discovery_booked`
- Vercel Analytics for client events
- Outbox pattern for failed sends (Supabase queue table, retried hourly)

### 11. Phase 1 email templates

Essential templates added to `email_template_versions`:
- `spec.owner_approval_required`, `spec.owner_approval_granted`, `spec.owner_approval_declined`
- `spec.deposit_confirmed`
- `spec.intake_reminder_1` / `_2` / `_3`
- `spec.intake_completed_customer`
- `spec.intake_completed_no_discovery_1` / `_2` / `_3`
- `spec.scope_doc_ready`
- `spec.scope_doc_signed_customer`
- `spec.p2_invoice` / `p3_invoice` / `p4_invoice`
- `spec.support_window_open`
- `spec.refund_processed`, `spec.refund_denied`

All subject lines + bodies pass through the `ops-copywriter` skill before shipping.

CASL requirements:
- Retainer offers and other promotional emails are commercial electronic messages. Include sender identity, mailing/contact information, unsubscribe mechanism, and consent basis.
- Transactional/service emails remain required operational notices.
- Referral program is link-based; OPS does not email referred third-party prospects until they submit a form, start checkout, or otherwise expressly opt in.

### 12. Cron jobs

Two cron schedules:

- **`pg_cron`** every 5 min: `select public.refresh_spec_board_snapshot();`. Owned by the database; lives inside Supabase. The `spec_public_board_snapshot` row gets rewritten with the latest aggregates.
- **Vercel cron** daily at 9am Vancouver time, route `/api/cron/spec-nudges` — runs all nudge / status-flip / outbox-retry logic per [06_CONTRACT_AND_EMAILS.md](06_CONTRACT_AND_EMAILS.md) cron jobs section. Includes the owner-approval expiry check.

### 13. RLS audit follow-up (Phase 1 launch gate, NOT an open item)

The Supabase advisory flagged 31 unprotected tables in `ops-app` at the time of the original spec — including `admins`, `stripe_webhook_events`, `contact_messages`, and the email-infrastructure tables. Running paid ads while those tables remain world-readable is an unacceptable risk; the leaks intersect with the SPEC funnel (Stripe events, contact-form data, audit logs). This work was previously listed as an open item; in the third revision pass it is **moved into the Phase 1 pre-ad-launch checklist** (see "Manual checklist before first ad goes live" below).

Scope of the audit:
- Identify all tables without RLS enabled (Supabase advisory).
- For each: enable RLS + add concrete read/write policies (operator-only for ops-internal tables; project-membership-or-operator for engagement-scoped tables).
- Re-run advisory; the SPEC Phase 1 verification gate requires zero unprotected tables.

### 13A. Server routes vs raw RLS decision

Resolved per `SPEC-SERVER-ROUTES-VS-RAW-RLS-DECISION` (see the Gate resolutions section). Phase 1 posture is locked conservative:
- Customer-facing SPEC reads/writes use server routes returning narrow projections.
- Raw SPEC tables are operator/service-role owned. Anon/authenticated cannot SELECT/INSERT/UPDATE/DELETE on any SPEC table except `spec_public_board_snapshot` (sanitized public read).
- Customer refund requests, support tickets, and satisfaction ratings go through server routes. The migration includes tests proving anon and authenticated clients cannot bypass.

### 13B. Security-definer and live-schema migration gates

Both resolved on 2026-05-25 (see the Gate resolutions section for full details):
- `SPEC-SECURITY-DEFINER-PRIVATE-SCHEMA`: `is_spec_operator()` and `refresh_spec_board_snapshot()` placed in the existing `private` schema, matching the OPS convention (`private.current_user_has_permission`, `private.resolve_uid`, etc.). Grants follow the existing pattern.
- `SPEC-LIVE-SCHEMA-MISMATCHES`: all schema assumptions verified against live `ijeekuhbatykdomumfjx`. Two new findings folded in: `user_permission_overrides.company_id` is NOT NULL (every SPEC operator override row must carry `company_id = OPS_OPERATIONS_COMPANY_ID`), and `public.roles` requires `name`, `hierarchy`, `is_preset` on the SPEC Operator role seed.

### 14. Test-mode column

`is_test boolean not null default false` is added to every SPEC engagement table by the Phase 1 migration (see migrations list). The `/admin/spec` page header gets a TEST MODE toggle that flips a session cookie; all admin queries read the cookie and either include or exclude `is_test = true` rows. Stripe test-mode keys at the server set the field on newly created rows. Test rows are NEVER counted in the public board snapshot.

## Phase 2 — Volume-handling polish

Added once Phase 1 proves the pipeline works (after 5-10 deposits):

- **Customer-facing project portal at `/account/spec/[id]`** — read-only view of a buyer or account_holder's engagement: timeline (status changes, acceptance events, payments, scope versions, communications), current scope doc with feature acceptance status, satisfaction-survey UI, support-ticket filing. Gated on project membership (buyer_user_id or account_holder_user_id), NOT on `is_spec_operator()`. The portal does NOT expose operator command surfaces (no refund processing, no entitlements toggles, no internal notes).
- Live walkthrough demo recording infra (Loom/Zoom integration + URL capture)
- Satisfaction survey UI (post-midpoint + post-delivery)
- Support ticket UI at `/admin/spec/[id]/tickets` + customer-facing ticket filing (via the new portal)
- Retainer Stripe subscription product creation + webhook handling
- Retainer enrollment flow (`spec.support_ending_*` email templates + checkout)
- Stripe dispute evidence package assembly UI (auto-builds the package from `spec_acceptance_events` (incl. `owner_purchase_approved` and `tos_accepted` for Path B) + scope versions)
- Block list management UI at `/admin/spec/blocked`
- Referral capture + bounty payout flow (Stripe Connect Express onboarding, KYC, T4A flagging). YTD payout derived at query time (never denormalized). Referral acquisition is link-based; no referred-prospect email until express opt-in.
- Platform sunset notification system
- Phase 2 email templates: `discovery_no_show_*`, `midpoint_*`, `delivery_walkthrough_scheduled`, `support_ending_*`, `retainer_active` / `_cancelled`, `referrer_bounty_paid`, `referrer_kyc_required`, `platform_sunset_notice`, `tos_update_notice`

## Phase 3 — Scale enhancements

Post-launch optimization, after SPEC has steady volume:

- Custom intake form analytics (drop-off, time-to-complete by field)
- A/B testing on `/spec` hero copy + pricing display (via existing `ab_tests` table)
- Customer-facing project portal in OPS-Web (read-only view of their SPEC project, including the timeline and acceptance evidence chain)
- Automated scope doc generation (intake → draft scope_document content_json via LLM)
- USD pricing option + multi-currency Stripe Tax
- DocuSign integration for scope doc signing (records into `spec_acceptance_events`)
- More granular reporting in `/admin/spec` (pipeline velocity, conversion by ad source)
- Per-trade SPEC landing pages (`/spec/for-roofers`, `/spec/for-hvac`, etc.) for ad targeting

---

## Verification plan

End-to-end verification of Phase 1 before any ad spend. Each scenario walked through manually against a test environment (Stripe test mode + a way to isolate test rows).

### Test scenarios (must all pass)

**Scenario 1: Happy path — existing OPS account_holder buys Build SPEC**
- Sign in to OPS-Web as the account_holder of a test company
- Navigate to /spec, expand Build card, click "Get started for $2,125"
- `POST /api/spec/create-checkout-session` resolves buyer == account_holder
- `spec_projects` row inserted with `status = 'awaiting_deposit'`
- Approved Stripe payment flow opens with metadata: `tier=build`, `user_id`, `company_id`, `tos_version_hash`, UTM cookies merged
- Pay via Stripe test card (4242 4242 4242 4242)
- Webhook flips `spec_projects.status = 'deposit_paid'`, stamps `deposit_paid_at`
- Inserts `spec_acceptance_events` for `tos_accepted`
- Inserts P1 `spec_payments` (status `paid`)
- Customer receives `spec.deposit_confirmed` email
- Jackson receives persistent notification + email
- Customer opens intake link, fills out (including regulated-workflow attestation = no), submits
- `intake_completed_at` populated, `intake_responses` JSONB stored, conversion event fires
- Jackson notified, schedules discovery
- Discovery sessions happen (manual)
- Jackson drafts `spec_scope_documents` version 1, sends
- Customer accepts → `spec_acceptance_events` for `scope_signoff`, status `building`, P2 invoice fires
- Midpoint demo + acceptance → P3 invoice fires
- Walkthrough → `walkthrough_completed_at` stamped, P4 invoice fires, status `support`, all `spec_module_entitlements` flip `enabled = true`
- All status transitions reflected on Kanban + TODAY queue

**Scenario 2: Buyer ≠ account_holder — team member purchases SPEC**
- Sign in as a team member (NOT account_holder) of an existing company
- Click Pay Deposit for Setup tier
- `POST /api/spec/create-checkout-session` resolves buyer ≠ account_holder
- `spec_projects` row inserted with `status = 'awaiting_owner_approval'`, NO Stripe call
- `spec_owner_approval_requests` row inserted with token
- Account_holder receives `spec.owner_approval_required` email + persistent notification
- Buyer lands on `/spec/awaiting-approval`
- Account_holder opens approval link, signs in, sees details
- Approve path:
  - `spec_owner_approval_requests.status = 'approved'`
  - `spec_projects.status = 'awaiting_deposit'`, `owner_approved_at` stamped
  - `buyer_checkout_token` issued (24h)
  - Buyer receives `spec.owner_approval_granted` with link
  - Buyer clicks → approved Stripe payment flow opens → completes → webhook normal flow
- Test decline path:
  - Account_holder declines
  - `spec_owner_approval_requests.status = 'declined'`
  - `spec_projects.status = 'cancelled'`, `cancellation_reason = 'owner_declined'`
  - Buyer receives `spec.owner_approval_declined`
  - **No charge ever happened, no refund row created**

**Scenario 3: New user without OPS account (no-company buyer path)**

Resolved per `SPEC-NO-COMPANY-BUYER-FLOW-LOCK` — the no-company buyer is routed through the existing `/setup` flow before they can reach the SPEC deposit form. The scenario tests:

- Visit `/spec` as unauthenticated user, click Pay Deposit → redirect to OPS-Web sign-up with `returnTo=/spec?tier=build`
- Complete sign-up (Firebase + `/api/auth/sync-user` creates `users` row with `company_id=null`)
- Land back on `/spec?tier=build`
- Click Pay Deposit again — `/api/spec/create-checkout-session` calls `resolveSpecCompanyForProject(buyer_user_id, 'build')` which returns `{ ok: false, reason: 'no_company', redirectTo: '/setup?returnTo=/spec?tier=build' }`
- 409 + redirect to `/setup` (existing OPS-Web onboarding flow)
- Complete the identity + company steps in `/setup`. The `company` step at `POST /api/setup/progress` creates the `companies` row (`account_holder_id = buyer_user_id`, `admin_ids = [buyer_user_id]`) and links the user (`users.company_id = <new>`, `users.is_company_admin = true`)
- `/setup` post-company-step honors the `returnTo` query param and pushes back to `/spec?tier=build`
- Click Pay Deposit a third time — `resolveSpecCompanyForProject` now returns `{ ok: true, isBuyerAccountHolder: true }` → proceeds to `/spec/billing-address` → Stripe Checkout → deposit_paid
- Verify `spec_projects.linked_company_id` is the newly-created company id
- Verify the buyer is treated as Path A (`isBuyerAccountHolder: true`) — no owner-approval needed

**Scenario 4: Quebec address rejection (pre-Stripe)**
- Buyer fills the pre-Stripe billing-address form on `/spec/billing-address` with `province = 'QC'`
- Server-side validation rejects with explanation + contact-form link
- **No `spec_projects` row is ever created**
- **No Stripe payment session is ever created**
- Internal `quebec_rejected` event logged (not sent to ad platforms)
- Toggle scenarios:
  - Change billing province to `BC` but attest Quebec head office / operating address / establishment / material SPEC use → rejected, no row, no Stripe session.
  - Change all Quebec eligibility answers to false → row + approved Stripe payment flow create normally; toggle test-mode on → row carries `is_test = true`.
  - Misrepresentation discovered later → material breach, Guarantee Refund unavailable.

**Scenario 5: Regulated-workflow attestation flagged**
- Buyer completes deposit normally
- At intake, marks "HIPAA / PHIPA" attestation as yes
- Intake submission blocked with explanation
- Notification fires to Jackson
- Jackson reviews and decides to refund (pre-discovery, full refund) via `/admin/spec/refunds`

**Scenario 6: 30-day guarantee invocation with mixed payment states**
- Test project at `status=support`, `walkthrough_completed_at` 5 days ago, with: P1 paid, P2 paid, P3 invoiced but unpaid (overdue past net-15), P4 invoiced and partially paid (50%)
- Customer submits refund request via `/account/spec/[id]/request-refund` or written notice by email
- Eligibility chips: within 30 days ✓, no chargeback ✓, no fraud/material misrepresentation/prohibited workflow/material breach ✓, no continued use after refund ✓, non-payment tolling accounted for ✓
- `spec_refund_requests` row created with `is_guarantee_invocation = true`
- Unique partial index enforces one-per-engagement
- Admin sees the refund-breakdown preview: P1 → `refund`, P2 → `refund`, P3 → `void`, P4 → `credit_note` + `refund` for the paid 50%
- Jackson clicks "Process refund" → processor walks each milestone and applies the right action
- `spec_payments` rows: P1 = `refunded`, P2 = `refunded`, P3 = `voided`, P4 = `partially_refunded` with `credit_note_stripe_id` populated
- `refund_breakdown` written with each line containing action, stripe_resource_id, amount_cents, status, executed_at
- Project status → `refunded`
- All `spec_module_entitlements` flip `enabled = false`, `disabled_reason = 'refunded'`
- Customer receives `spec.refund_processed` email with the breakdown rendered as a line-by-line summary
- Second invocation attempt blocked by the unique index

**Scenario 7: Stripe dispute**
- Simulate `charge.dispute.created` event in test mode
- Webhook handler:
  - Sets payment status to `disputed`
  - Inserts persistent notification for Jackson
  - Flips entitlements `enabled = false`, `disabled_reason = 'dispute'`
  - Closes 30-day guarantee window for that engagement
  - Logs to `spec_communications` as `system` event
- Jackson opens `/admin/spec/[id]`, sees dispute alert + evidence-package preview

**Scenario 8: OPS BOARD on /spec reflects reality (snapshot table path)**
- With various active builds + queued projects (mix of tiers; some `is_test = true`), wait at most 5 min for `pg_cron` to refresh `spec_public_board_snapshot`, OR click `REFRESH BOARD` in `/admin/spec` to force-refresh
- Verify per-tier rows show coarse availability + waitlist_bucket + ISO-week next-start
- Verify Enterprise tier with `slot_ceiling = 1` and 1 queued project shows `WAITLIST · 1-2` (not "QUEUE: 1")
- Verify `is_test = true` rows are excluded from the aggregation
- Verify `refreshed_at` is exposed on the `/api/spec/board` payload and renders as "UPDATED [N min ago]"; force the snapshot row to be 73h stale → UI shifts to amber
- Toggle `is_accepting_bookings = false` on `setup` tier → row shows "CLOSED — RESUMES [public_note]"
- Verify the `/api/spec/board` response Cache-Control: `public, max-age=300, s-maxage=300, stale-while-revalidate=60`
- Verify anon SELECT against `spec_public_board_snapshot` succeeds; anon SELECT against `spec_projects` continues to be RLS-blocked

**Scenario 9: 14-day intake nudge cron**
- Insert test project with `deposit_paid_at = now() - interval '14 days 1 hour'`, no intake completed
- Run cron job manually
- Verify customer receives `spec.intake_reminder_1` email
- Verify `spec_communications` row inserted with `direction = 'outbound'`, `channel = 'email'`

**Scenario 10: 90-day customer_requested hold expiry**
- Insert test project at `status = 'on_hold'`, `hold_type = 'customer_requested'`, `on_hold_at = now() - interval '90 days 1 hour'`
- Run cron
- Status flips to `stalled_on_hold`
- Capacity logic confirms the slot was already freed (no change)
- Customer + Jackson receive notification (no auto-refund)

**Scenario 11: ops_blocked hold keeps slot consumed**
- Insert test projects: 3 builds active + 1 build on `ops_blocked` hold (slot_ceiling = 3)
- OPS BOARD shows `BUILD · WAITLIST` (3+1 = 4 consuming slots > 3 ceiling)
- Convert the ops_blocked hold to `customer_requested` → recheck → `BUILD · LIMITED` or `OPEN` depending on queue

**Scenario 12: ToS version pinning**
- Customer A accepts ToS v1 on deposit
- ToS spec-terms file updated (commit hash changes)
- Customer A's `tos_version_accepted` still reads v1 hash
- Customer B accepts on deposit → `tos_version_accepted` reads new hash
- `spec_acceptance_events` rows for A and B reference their respective hashes
- Verify both customers can be served their accepted version on demand

**Scenario 13: Discovery no-show escalation**
- Schedule discovery for test customer
- Mark no-show
- 1st: `spec.discovery_no_show_1` fires, `no_show_count = 1`
- Schedule again, no-show
- 2nd: `spec.discovery_no_show_2` fires with $100 fee Stripe invoice
- Schedule again, no-show
- 3rd: `spec.discovery_no_show_3` fires, status `cancelled`, `forfeit_at` set, deposit forfeited (NO refund)

**Scenario 14: Owner approval expiry**
- Path B engagement, owner doesn't respond in 7 days
- Cron flips `spec_owner_approval_requests.status = 'expired'`
- `spec_projects.status = 'cancelled'`, `cancellation_reason = 'owner_approval_expired'`
- Buyer + account_holder both notified

**Scenario 15: Operator gate denies customer-side admin**
- Sign in as a user who IS a customer-side `is_company_admin = true` (so `public.has_permission(...)` would return true for them) but has NO `spec.admin` in `role_permissions` and no `user_permission_overrides` entry
- Navigate to `/admin/spec`
- `private.is_spec_operator()` returns FALSE (the function never trusts customer-company admin status — verified against the live `has_permission` body which short-circuits via `is_company_admin / account_holder_id / admin_ids` before consulting `role_permissions`)
- Route redirects to `/` (or shows 403, per layout decision)
- Repeat with a user who IS in `role_permissions(permission='spec.admin', scope='all')` via the SPEC Operator role → access granted
- Repeat with a user who has `user_permission_overrides(permission='spec.admin', granted=true, company_id=OPS_OPERATIONS_COMPANY_ID)` → access granted
- Sanity check: confirm `public.has_permission(<customer_admin_user>, 'spec.admin', 'all')` returns TRUE (wrong) and `private.is_spec_operator()` returns FALSE (correct) for the same user

**Scenario 16: Dual ToS acceptance recorded for Path B**
- Path B engagement: buyer ≠ account_holder
- Owner approves → confirm `spec_acceptance_events` has a row with `event_type = 'owner_purchase_approved'`, `accepted_by_user_id = account_holder_user_id`, IP, UA, payload_hash = approved_tos_version_hash
- Buyer completes the approved Stripe payment flow → confirm a SECOND `spec_acceptance_events` row exists with `event_type = 'tos_accepted'`, `accepted_by_user_id = buyer_user_id`, IP, UA, payload_hash = build-time ToS hash
- Confirm `spec_projects.tos_version_accepted` + `tos_accepted_at` are populated by the webhook (not at row insert)
- Simulate a Stripe dispute → evidence package assembler pulls BOTH events into the chargeback response

**Scenario 17: Token-hash storage**
- Path B engagement: owner-approval URL emits a plaintext `approval_token`
- Confirm the DB row has `approval_token_hash` populated and the plaintext is NOT in the row
- Re-submit the URL with the plaintext → server bcrypt/argon2-hashes it, compares to `approval_token_hash` → match → approval proceeds
- Attempt to submit a fabricated token → no match → 403
- Same end-to-end test for `buyer_checkout_token` after approval

**Scenario 18: Snapshot force-refresh**
- Operator (with `private.is_spec_operator() = true`) clicks `REFRESH BOARD` in `/admin/spec` header
- Confirm `POST /api/admin/spec/board/refresh` succeeds; the route uses the service-role client to call `private.refresh_spec_board_snapshot()`; returns the new `refreshed_at`
- Non-operator user attempts the same POST → 403 (route layer rejects via `private.is_spec_operator()` check before the service-role call)
- pg_cron job continues firing every 5 min independently, running as `postgres` with direct schema access (no grant needed)

**Scenario 19: Webhook Quebec post-Stripe defense**
- Buyer passes the pre-Stripe address form with `province='BC'`, gets `spec_projects` row inserted in `awaiting_deposit` and Stripe Checkout opens
- On the hosted Stripe Checkout page, buyer edits the billing form and switches province to `QC` (Stripe allows this — there is no API parameter to lock it)
- Buyer completes payment with the QC address
- `checkout.session.completed` webhook fires with `session.customer_details.address.state='QC'`
- Webhook detects QC, calls `stripe.refunds.create({ payment_intent: session.payment_intent, reason: 'requested_by_customer' })` — full refund
- `spec_projects.status='cancelled'`, `cancellation_reason='quebec_billing_at_stripe'`
- `spec_blocked_buyers` row inserted with the buyer's email + Stripe customer_id and `blocked_reason='quebec_misrepresented_billing_address_post_stripe'`
- Customer receives `spec.quebec_rejected_post_stripe` email
- Operator receives persistent notification "Quebec leak refunded for [Customer]"
- Verify: Stripe Dashboard shows the original payment as Refunded; `spec_projects.deposit_paid_at` is NULL (never stamped); no `spec_acceptance_events` row for `tos_accepted` was inserted

**Scenario 20: No-company buyer hits the company gate**
- Sign up fresh user via `/register` → routed to `/account-type` → click "Run a Crew" → `/setup`
- Abandon `/setup` partway through (close tab before the `company` step submits)
- Open a new tab, navigate to `/spec`, click Pay Deposit
- `/api/spec/create-checkout-session` calls `resolveSpecCompanyForProject(buyer_user_id, 'setup')` → returns `{ ok: false, reason: 'no_company', redirectTo: '/setup?returnTo=/spec?tier=setup' }`
- Browser receives 409 with redirect target → UI sends user to `/setup`
- Complete the company step in `/setup` → `users.company_id` populated → returnTo handler sends user back to `/spec?tier=setup`
- Click Pay Deposit a second time → `resolveSpecCompanyForProject` returns `{ ok: true }` → proceeds normally
- Verify NO `spec_projects` row was created during the abandoned attempt

### Build verification

- `npm run build` passes in ops-site
- `npm run build` passes in OPS-Web
- `npm run lint` passes in both
- Visual smoke test of `/spec` on desktop + mobile + reduced motion
- Lighthouse on `/spec`: LCP < 2.5s, INP < 200ms, CLS < 0.1
- SEO: dynamic OG image renders, JSON-LD validates (`Service` + `Offer` + `BreadcrumbList` + `FAQPage`)
- Email template hash check passes (build-time validation against `email_template_versions`)
- Supabase advisory check passes — no new unprotected tables (all SPEC tables have RLS enabled and policies defined)

### Manual checklist before first ad goes live

- [ ] Phase 0 conversation-only mitigation deployed until Phase 1 ready; automated live SPEC deposits disabled
- [ ] All 18 test scenarios pass
- [ ] **Supabase RLS audit completed**: zero tables flagged by the Supabase advisory as unprotected (this is no longer in open items — it is a Phase 1 launch gate)
- [ ] Final customer-facing ToS + Privacy + DPA prose published and self-reviewed by Jackson against the fourth-revision-pass spec. Counsel review is recommended risk mitigation, not a hard launch blocker.
- [ ] Stripe Checkout flow validated end-to-end in test mode per the locked `SPEC-STRIPE-ADDRESS-TAX-SPIKE` resolution: pre-filled customer address, `automatic_tax`, `consent_collection.terms_of_service='required'`, `phone_number_collection`, optional GST/HST custom_field, and the webhook Quebec-defense path (try changing province to QC at the hosted page — verify refund + cancellation + block-list insert)
- [ ] Stripe account in live mode with one $1 deposit `consent_collection`-accept flow validated end-to-end after final legal prose exists; ToS URL set in Stripe Dashboard pointing to `https://opsapp.co/legal?page=spec-terms`
- [ ] SendGrid templates approved + suppression list confirmed clean
- [ ] OPS BOARD snapshot validated — pg_cron schedule active calling `private.refresh_spec_board_snapshot()`, `/api/spec/board` Cache-Control header set, manual force-refresh works for operators only via the `private.*` function
- [ ] OPS Operations company seeded with the constant UUID `00000000-0000-0000-0000-00000000000a`; Jackson + any operators are members
- [ ] `private.is_spec_operator()` deployed in the `private` schema; tested against a customer-side company admin (must fail) and against the SPEC operator role (must pass); `private` schema USAGE granted to `authenticated, service_role`; function EXECUTE granted to `public`
- [ ] SPEC Operator role seed verified: row in `public.roles` with UUID `00000000-0000-0000-0000-0000000000a1`, `hierarchy=0`, `is_preset=true`, `company_id=null`; row in `public.role_permissions` with `permission='spec.admin', scope='all'`; row in `public.user_roles` linking Jackson
- [ ] `user_permission_overrides` convention enforced: any future SPEC operator override row carries `company_id = OPS_OPERATIONS_COMPANY_ID`
- [ ] `resolveSpecCompanyForProject()` deployed and exercised: no-company buyer → 409 + redirect to `/setup?returnTo=/spec?tier=X`; `/setup` post-company-step honors the returnTo and lands the buyer back on `/spec`
- [ ] `spec_projects.linked_company_id` confirmed non-null on every test row produced by the deposit flow (the no-company case is no longer reachable)
- [ ] Notification dispatch verified: customer rows write `company_id = linked_company_id`, operator rows write `company_id = OPS_OPERATIONS_COMPANY_ID`, both render in the active edge-tab `NotificationsDrawer` in OPS-Web
- [ ] Server-route posture verified: anon/authenticated client SDKs cannot SELECT/INSERT/UPDATE/DELETE on any SPEC table except `spec_public_board_snapshot` (sanitized public read). Phase 1 customer routes enumerated in the resolved `SPEC-SERVER-ROUTES-VS-RAW-RLS-DECISION` section all use service-role + buyer/account_holder authorization check
- [ ] Owner-approval flow tested with a real second team member — both `owner_purchase_approved` and `tos_accepted` rows visible in `spec_acceptance_events`
- [ ] Quebec rejection tested with a real Quebec postal code (H1A 0A1), Quebec head office, Quebec operating address, Quebec establishment, and material SPEC use cases in the pre-Stripe form — no `spec_projects` row created. Webhook QC defense also exercised: simulate a Stripe Checkout where the customer pre-passes BC and switches to QC on the hosted page — refund fires, project cancels, buyer blocked
- [ ] Refund flow tested end-to-end in test mode (P1 paid only; P1 paid + P2 open invoice — verify void; P1 paid + P2 partial paid — verify credit-note + refund; full P1-P4 in mixed states)
- [ ] Conversion-tracking events visible in Meta Events Manager + Google Ads conversion tracker for test purchases (including the new `billing_address_submitted` step)
- [ ] First ad campaign budget cap set ($X/day) with daily review for first 14 days
- [ ] Founder welcome video recorded + uploaded
- [ ] Spanish dictionary updated (es/spec.json) to match English content revisions
- [ ] `is_test` column on every SPEC engagement table; test rows confirmed excluded from public snapshot and from default admin queries

---

## Critical files to be modified or created

### ops-site (marketing)

| File | Status | Purpose |
|---|---|---|
| `src/app/spec/page.tsx` | MODIFY | Wire OPS BOARD, auth gate, ToS acceptance via new checkout API |
| `src/components/spec/SpecPageContent.tsx` | MODIFY | New section composition |
| `src/components/spec/SpecOpsBoard.tsx` | NEW | Capacity + queue + delivery visualization (reads sanitized view) |
| `src/components/spec/SpecPricing.tsx` | MODIFY | Rewrite for 4-milestone display |
| `src/components/spec/PackageCard.tsx` | MODIFY | Headline P1 (25%), expanded milestones, multiplier, retainer, money-back badge; JetBrains Mono number compliance |
| `src/components/spec/SpecFAQ.tsx` | MODIFY | New FAQ list, `<details>/<summary>` pattern so answers ship in initial HTML |
| `src/components/spec/SpecGuarantees.tsx` | NEW | "Standing Behind The Work" section with the revised "Pay as work clears review" copy |
| `src/components/spec/SocialProof.tsx` | MODIFY | Remove unverified stat block; placeholder for future real testimonials |
| `src/components/spec/SpecHero.tsx` | MODIFY | Founder presence add (Phase 1 if assets ready) |
| `src/app/spec/intake/[token]/page.tsx` | NEW | Intake form route |
| `src/components/spec/intake/IntakeForm.tsx` | NEW | Form with autosave + regulated-workflow attestation |
| `src/app/spec/billing-address/page.tsx` | NEW | Pre-Stripe billing-address form (Path A or pre-owner-approval); Quebec rejection lives here |
| `src/app/spec/awaiting-approval/page.tsx` | NEW | Path B wait state |
| `src/app/spec/owner-approval/[approval_token]/page.tsx` | NEW | Owner approval UI; writes `owner_purchase_approved` event |
| `src/app/spec/checkout/[buyer_checkout_token]/page.tsx` | NEW | Post-approval Stripe payment launcher (token validated via bcrypt/argon2 hash) |
| `src/app/spec/confirmation/page.tsx` | MODIFY | Rewrite |
| `src/components/spec/SpecConfirmation.tsx` | MODIFY | Founder video, timeline, guarantee reminder |
| `src/lib/legal-content.ts` | MODIFY | Register `spec-terms` document |
| `src/app/legal/page.tsx` | MODIFY | Extend `VALID_TABS` to include `spec-terms` |
| `src/app/api/spec/create-checkout-session/route.ts` | MODIFY | Auth gate, owner-approval branching, ToS version, GST, Quebec block, conversion events |
| `src/app/api/spec/owner-approval/[token]/route.ts` | NEW | Approve / decline handler |
| `src/app/api/spec/intake/submit/route.ts` | NEW | Intake submission handler |
| `src/i18n/dictionaries/en/spec.json` | MODIFY | Copy updates; remove unverified stats; new FAQ; new milestone copy |
| `src/i18n/dictionaries/es/spec.json` | MODIFY | Mirror English revisions in Spanish |
| `src/lib/spec/board.ts` | NEW | Data fetch + derivation for OPS BOARD from sanitized view |
| `src/lib/spec/pricing.ts` | NEW | Milestone amount calcs (25% per milestone) |
| `src/lib/spec/attribution.ts` | NEW | First-touch UTM + gclid/fbclid cookie handling |
| `src/lib/spec/conversion-events.ts` | NEW | Meta CAPI + Google Enhanced server-side senders |

### OPS-Web (product + admin)

| File | Status | Purpose |
|---|---|---|
| `src/app/admin/spec/page.tsx` | NEW | Overview with TODAY queue + Kanban + test-mode toggle + force-refresh-board button |
| `src/app/admin/spec/[id]/page.tsx` | NEW | Operator-only project detail with tabs (incl. Entitlements tab with toggle) |
| `src/app/admin/spec/capacity/page.tsx` | NEW | Capacity config editor |
| `src/app/admin/spec/owner-approvals/page.tsx` | NEW | Pending owner-approval queue |
| `src/app/admin/spec/refunds/page.tsx` | NEW | Refund queue with eligibility chips + per-milestone refund_breakdown preview |
| `src/app/account/spec/[id]/request-refund/page.tsx` | NEW | Phase 1 customer refund request route, buyer/account_holder gated |
| `src/app/api/account/spec/[id]/request-refund/route.ts` | NEW | Creates `spec_refund_requests` with safe fields only |
| `src/app/api/admin/spec/board/refresh/route.ts` | NEW | Operator-gated POST that runs `refresh_spec_board_snapshot()` via service role |
| `src/app/account/spec/[id]/page.tsx` | NEW (Phase 2) | Customer-facing read-only project portal |
| `src/app/admin/spec/referrals/page.tsx` | NEW (Phase 2) | Referral queue with KYC/related-entity flags |
| `src/app/admin/spec/blocked/page.tsx` | NEW (Phase 2) | Block list |
| `src/app/admin/spec/layout.tsx` | NEW | `is_spec_operator()` gate (NOT the generic `has_permission(...)` which short-circuits through customer-company admin) |
| `src/components/admin/spec/*` | NEW | Component tree |
| `src/components/admin/spec/TodayQueue.tsx` | NEW | The TODAY command queue composition |
| `src/lib/admin/spec-queries.ts` | NEW | Data fetching |
| `src/lib/admin/spec-mutations.ts` | NEW | Status transitions, payment fires, refund processing, entitlement toggling |
| `src/app/api/shop/webhook/route.ts` | MODIFY | Extend with SPEC handler + dispute handler |
| `src/lib/email/templates/spec.*.ts` | NEW | All SPEC email templates |
| `src/app/api/cron/spec-nudges/route.ts` | NEW | Daily nudge / status-flip / outbox-retry processor |
| `vercel.json` | MODIFY | Cron schedule for daily 9am Vancouver run |

### Supabase migrations

| File | Status | Purpose |
|---|---|---|
| `migrations/YYYYMMDD_spec_phase1_enums_and_capacity.sql` | NEW | enums + `spec_capacity` seed + `citext` extension |
| `migrations/YYYYMMDD_spec_phase1_internal_company.sql` | NEW | OPS Operations company seed (constant UUID) |
| `migrations/YYYYMMDD_spec_phase1_operator_gate.sql` | NEW | `is_spec_operator()` function + role + permission seed |
| `migrations/YYYYMMDD_spec_phase1_core_tables.sql` | NEW | core tables with FKs, CHECK constraints, `is_test`, default-disabled entitlements |
| `migrations/YYYYMMDD_spec_phase1_money_tables.sql` | NEW | payment / change order / refund (with refund_breakdown) / referral / retainer tables; extended payment status enum |
| `migrations/YYYYMMDD_spec_phase1_workflow_tables.sql` | NEW | feature acceptance / satisfaction / tickets / comms / blocked (citext email) |
| `migrations/YYYYMMDD_spec_phase1_snapshot_and_rls.sql` | NEW | `spec_public_board_snapshot` table + `refresh_spec_board_snapshot()` + pg_cron schedule + CONCRETE RLS policies per table + grants |
| `migrations/YYYYMMDD_spec_phase1_storage.sql` | NEW | `spec-intake` bucket + RLS + MIME whitelist + size limit |

---

## Gate resolutions (2026-05-25)

The six fourth-pass bug_reports were resolved in a dedicated investigation pass on 2026-05-25 against the live `ops-app` Supabase project (`ijeekuhbatykdomumfjx`), the live OPS-Web signup/company-provisioning code, the live OPS-Web `dashboard-layout.tsx` + `notifications-drawer.tsx` mount, and the current Stripe Checkout API documentation. Every gate has a locked answer below. The previous open-items list (Fourth-pass bug_reports) is removed; resolved findings live here as the historical and forward-looking record.

### SPEC-STRIPE-ADDRESS-TAX-SPIKE — Resolved 2026-05-25

**Decision: Stripe Checkout (hosted Session) is approved.** Payment Element is not needed.

**Proof.** The Checkout Session API supports the full SPEC requirement set in one composed call:

1. **Pre-collected address + Customer reuse.** Pass `customer` (an existing Stripe Customer ID with `address` set on the Customer object) plus `customer_email`. Checkout pre-fills the billing form with the saved address. (https://docs.stripe.com/api/checkout/sessions/create)
2. **Stripe Tax.** Pass `automatic_tax: { enabled: true }`. With Canada-only at launch, Stripe Tax derives GST/HST/PST from country + province on the recorded billing address. (https://docs.stripe.com/tax/customer-locations.md — Canada uses billing address province as the canonical input.)
3. **ToS acceptance.** Use the dedicated `consent_collection: { terms_of_service: 'required' }` mechanism (NOT a `custom_fields` checkbox — custom_fields only supports `text`, `numeric`, `dropdown` types; checkboxes are not supported in hosted Checkout). The accepted-terms URL is set in the Stripe Dashboard and the build-time `SPEC_TERMS_VERSION_HASH` is appended to the URL fragment so the version is captured. `consent_collection` adds an enforced checkbox; the resulting `session.consent.terms_of_service === 'accepted'` is recorded by the webhook. (https://docs.stripe.com/api/checkout/sessions/object — `consent_collection.terms_of_service`; https://docs.stripe.com/payments/checkout/custom-fields — confirms no native checkbox custom field.)
4. **Phone capture.** `phone_number_collection: { enabled: true }`. (https://docs.stripe.com/api/checkout/sessions/create)
5. **GST/HST number (optional).** `custom_fields: [{ key: 'gst_hst_number', label: { type: 'custom', custom: 'GST/HST number (optional)' }, type: 'text', optional: true }]`. Read from `session.custom_fields` in the webhook; attach to the Customer via `tax_ids` if present.
6. **Compatibility.** `customer_email + customer + customer_creation + billing_address_collection + automatic_tax + consent_collection + phone_number_collection + custom_fields` all compose. The only documented constraints are (a) if the Customer has a valid email on file the `customer_email` field becomes non-editable in Checkout (acceptable — OPS controls the customer email), and (b) `consent_collection.terms_of_service='required'` requires a valid terms URL set in the Stripe Dashboard (one-time configuration task).

**Quebec leakage — webhook defense (mandatory).** Stripe does NOT support locking a pre-filled billing address. The customer can edit the billing form at the hosted Checkout page and switch province from `BC` to `QC` after we pre-rejected. The Stripe webhook MUST defend this:

```
// /api/shop/webhook — extending the existing handler on metadata.type === 'spec_deposit'
// Pre-conditions: session.payment_status === 'paid' AND session.payment_intent is set.

const billing = session.customer_details?.address;
if (billing && (billing.state === 'QC' || billing.country !== 'CA')) {
  // Refund the charge (full amount) immediately. Stripe Refunds API.
  await stripe.refunds.create({
    payment_intent: session.payment_intent,
    reason: 'requested_by_customer',
    metadata: { reversal_reason: 'spec_quebec_post_stripe_leak', spec_project_id }
  });

  // Cancel the spec_projects row (was inserted at /api/spec/create-checkout-session
  // before redirect, then expected to flip to 'deposit_paid' here).
  await supabase.from('spec_projects').update({
    status: 'cancelled',
    cancellation_reason: 'quebec_billing_at_stripe',
    cancelled_at: new Date().toISOString(),
  }).eq('id', spec_project_id);

  // Add buyer to spec_blocked_buyers — misrepresentation per ToS § 3.
  await supabase.from('spec_blocked_buyers').insert({
    email: session.customer_details.email,
    stripe_customer_id: session.customer,
    blocked_reason: 'quebec_misrepresented_billing_address_post_stripe',
    blocked_by_user_id: null,
  });

  // Email customer (template spec.quebec_rejected_post_stripe — added to Phase 1 list)
  // Persistent operator notification: "Quebec leak refunded for [Customer]."
  // Log internal `quebec_rejected_post_stripe` event (not sent to ad platforms).
  return;
}
// Otherwise: continue with normal deposit_paid flow.
```

**Implication for other docs.** Quebec block now lives in THREE places:
- Pre-Stripe address form (`/spec/billing-address`) — canonical block, no `spec_projects` row, no Stripe call (§ 04_CUSTOMER_UX.md, § 03_WORKFLOW.md).
- Stripe Checkout `automatic_tax` — still calculates correctly for BC/ON/etc; doesn't itself reject QC.
- **Webhook post-Stripe defense (new)** — refund + cancel + block-list + notify if the customer edited to QC on the hosted page.

The fallback "if Checkout doesn't fit, use Payment Element" language is removed throughout the spec. Checkout is the answer.

**Stripe Dashboard prerequisites (one-time):**
- Set the SPEC ToS URL in Stripe Dashboard → Settings → Customer emails → Terms of service: `https://opsapp.co/legal?page=spec-terms`. The build-time `SPEC_TERMS_VERSION_HASH` is appended via URL fragment.
- Enable Stripe Tax for Canada in Dashboard → Tax → Settings, with origin address set to OPS Ltd. Vancouver BC office.
- Confirm Stripe account is in CAD as default currency for SPEC line items.

### SPEC-LIVE-SCHEMA-MISMATCHES — Resolved 2026-05-25

**Verification method.** Direct queries against `ijeekuhbatykdomumfjx.public.*` via Supabase MCP on 2026-05-25.

**Confirmed clean (already correctly handled in spec):**

| Reference | Live state | Status |
|---|---|---|
| `public.users.id` | `uuid NOT NULL` | OK |
| `public.companies.id` | `uuid NOT NULL` | OK |
| `public.companies.account_holder_id` | `text` (nullable) | OK |
| `public.companies.admin_ids` | `text[]` default `'{}'` | OK |
| `public.companies.name` | `text NOT NULL` | OK (seed includes name) |
| `public.companies` NOT NULL columns with defaults (`timezone`, `locale`, `ai_enabled`, `currency_code`, `default_work_start`, `default_work_end`) | All have defaults; seed need not set them | OK |
| `public.role_permissions(permission, scope, role_id)` | All NOT NULL; `scope IN ('all','own','assigned')` at current data — `'all'` is the canonical value (280 of 314 rows) | OK |
| `public.user_roles.user_id` | `text NOT NULL` (matches `users.id::text`) | OK |
| `public.user_roles.role_id` | `uuid NOT NULL` | OK |
| `public.has_permission(p_user_id uuid, p_permission text, p_required_scope text DEFAULT 'all')` | Exists; SECURITY DEFINER; **confirmed short-circuits through `is_company_admin` / `account_holder_id` / `admin_ids` BEFORE `role_permissions`** — making it unsafe as the SPEC operator gate, exactly as the spec already documents | OK (do not use for SPEC) |
| `public.get_user_id()` | Returns `text`; SECURITY DEFINER; reads `auth.jwt() ->> 'email'` | OK |
| `public.notifications.user_id` | `text NOT NULL` | OK |
| `public.notifications.company_id` | `text NOT NULL` | OK (OPS Operations company_id required) |
| `pg_cron` extension | Installed (v1.6.4); `cron.schedule()` lives in `cron` schema | OK |
| `citext` extension | NOT installed; spec's `create extension if not exists citext` covers this | OK |
| `companies.slug` | **Does not exist.** The spec's seed correctly does NOT reference it | Resolved |
| `user_permission_overrides.expires_at` | **Does not exist.** The spec correctly does NOT reference it | Resolved |

**NEW findings requiring spec changes:**

1. **`public.user_permission_overrides.company_id` is `uuid NOT NULL`.** The spec's `is_spec_operator()` overrides clause queries `user_permission_overrides` by `(user_id, permission='spec.admin', granted=true)` without filtering company. Because `company_id` is NOT NULL on inserts, every override row MUST carry a company_id. **Locked answer:** all SPEC operator overrides are inserted with `company_id = OPS_OPERATIONS_COMPANY_ID` (the constant UUID `00000000-0000-0000-0000-00000000000a`). The `is_spec_operator()` body keeps the existing structure — no scope or company filter needed on the override clause, because by convention the only `spec.admin` overrides that exist are the OPS Operations rows.

2. **`public.roles` requires `name`, `hierarchy` (int NOT NULL), `is_preset` (boolean NOT NULL), and supports nullable `company_id`.** The SPEC operator role seed in `migrations/YYYYMMDD_spec_phase1_operator_gate.sql` must provide all four:
   ```sql
   insert into public.roles (id, name, hierarchy, is_preset, company_id, created_at)
   values (
     '00000000-0000-0000-0000-0000000000a1',  -- constant UUID for SPEC Operator role
     'SPEC Operator',
     0,                                        -- highest precedence (matches Admin=0..n preset convention)
     true,                                      -- preset, not customer-created
     null,                                      -- global, not company-scoped
     now()
   )
   on conflict (id) do nothing;

   insert into public.role_permissions (id, role_id, permission, scope, created_at)
   values (
     gen_random_uuid(),
     '00000000-0000-0000-0000-0000000000a1',
     'spec.admin',
     'all',
     now()
   )
   on conflict do nothing;

   insert into public.user_roles (id, user_id, role_id, created_at)
   values (
     gen_random_uuid(),
     '<JACKSON_USER_ID>',                       -- replaced at migration time from a config table or env
     '00000000-0000-0000-0000-0000000000a1',
     now()
   )
   on conflict do nothing;
   ```
   The existing preset roles (`Admin`, `Owner`, `Operator`, `Office`, `Crew`, `Unassigned`) have UUIDs `00000000-0000-0000-0000-000000000001..6`. The SPEC Operator role uses `..00a1` to clearly separate the SPEC namespace from the customer-role namespace.

3. **`public.has_permission()` body confirmed.** The retrieved definition shows the exact short-circuit logic: it `RETURN true` as soon as any of `is_company_admin`, `account_holder_id`, or `admin_ids` matches. The function then consults `role_permissions` ordered by scope precedence (`'all'` → `'assigned'` → `'own'`). This confirms the SPEC requirement to define an independent `is_spec_operator()`.

4. **No SPEC-related permissions exist in `role_permissions` today.** The seed in `migrations/YYYYMMDD_spec_phase1_operator_gate.sql` is the first SPEC permission insert. No conflict, no precondition.

**Migration handoff checklist (operator-gate migration):**
- `create schema if not exists private;` (already exists in live DB, idempotent).
- Move `is_spec_operator()` into `private` (see next gate).
- Seed `SPEC Operator` role with all NOT NULL columns populated.
- Seed `(permission='spec.admin', scope='all')` row in `role_permissions`.
- Add Jackson's `users.id` to `user_roles` for that role.
- Future delegated SPEC operators: insert `user_permission_overrides(user_id, company_id=OPS_OPERATIONS_COMPANY_ID, permission='spec.admin', scope='all', granted=true)`.

### SPEC-SECURITY-DEFINER-PRIVATE-SCHEMA — Resolved 2026-05-25

**Decision: place `is_spec_operator()` and `refresh_spec_board_snapshot()` in the existing `private` schema.**

**Proof.** Live DB inspection confirmed:
- The `private` schema already exists in `ops-app`, owned by `postgres`.
- The existing OPS convention is to put SECURITY DEFINER functions used by RLS into `private` (examples: `private.current_user_has_permission`, `private.resolve_uid`, `private.current_user_is_admin`, `private.get_user_company_id`).
- `private` schema has `USAGE` granted to `authenticated` (verified via `has_schema_privilege('authenticated','private','USAGE')` → true) but NOT to `anon` (verified → false).
- The existing pattern grants `EXECUTE` on the private function to `PUBLIC` (which resolves to anything-with-USAGE-on-private — i.e., authenticated only).
- Existing RLS policies reference these functions directly via fully-qualified name (e.g., `private.resolve_uid()`, `private.current_user_has_permission(...)`). The pattern is proven in production.
- `pg_cron` jobs run as the `postgres` superuser; postgres has access regardless of schema placement.

**Locked SQL (replaces the spec's `public.is_spec_operator()` definition):**

```sql
-- Migration: YYYYMMDD_spec_phase1_operator_gate.sql

-- Schema is created by Supabase / existing OPS migrations. Idempotent here.
create schema if not exists private;

create or replace function private.is_spec_operator()
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select exists (
    select 1
    from public.role_permissions rp
    join public.user_roles ur on ur.role_id = rp.role_id
    where ur.user_id = public.get_user_id()
      and rp.permission = 'spec.admin'
      and rp.scope = 'all'
  )
  or exists (
    select 1
    from public.user_permission_overrides upo
    where upo.user_id::text = public.get_user_id()
      and upo.permission = 'spec.admin'
      and upo.granted = true
      -- company_id is NOT NULL on the table; spec.admin override rows always
      -- carry company_id = OPS_OPERATIONS_COMPANY_ID by convention. No filter
      -- needed here — the convention is enforced at insert time.
  );
$$;

-- Grant pattern matches existing private.* functions (verified live):
--   private schema USAGE → authenticated (already granted, idempotent here)
--   function EXECUTE → public (resolves to authenticated, since anon lacks USAGE)
grant usage on schema private to authenticated, service_role;
grant execute on function private.is_spec_operator() to public;
```

```sql
-- Migration: YYYYMMDD_spec_phase1_snapshot_and_rls.sql

create or replace function private.refresh_spec_board_snapshot()
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_data jsonb;
begin
  -- ... (body identical to the spec's prior public.refresh_spec_board_snapshot)
end;
$$;

grant execute on function private.refresh_spec_board_snapshot() to service_role;
-- anon and authenticated do not get EXECUTE; the manual force-refresh button
-- is an operator-gated server route that uses service_role to call this function.

-- pg_cron: schedule the refresh.
select cron.schedule(
  'spec_board_snapshot_refresh',
  '*/5 * * * *',
  $cron$ select private.refresh_spec_board_snapshot(); $cron$
);
```

**RLS policy updates.** Every RLS policy in `migrations/YYYYMMDD_spec_phase1_snapshot_and_rls.sql` calls `private.is_spec_operator()` instead of `public.is_spec_operator()`. Example:

```sql
create policy "spec_projects operator all" on public.spec_projects
  for all using (private.is_spec_operator())
  with check (private.is_spec_operator());
```

The Storage RLS policies in the spec for the `spec-intake` bucket likewise update to `private.is_spec_operator()`.

**Server-route invocation.** The admin `POST /api/admin/spec/board/refresh` route uses the Supabase service-role client to call:
```sql
select private.refresh_spec_board_snapshot();
```
service_role has USAGE on `private` (granted above) and EXECUTE on the function.

### SPEC-NO-COMPANY-BUYER-FLOW-LOCK — Resolved 2026-05-25

**Decision: a buyer MUST have `users.company_id` populated before they can submit the `/spec/billing-address` form. No-company buyers are redirected to the existing OPS-Web `/setup` flow, then return to `/spec?tier=X` after the company step completes.** Option (b) "defer until intake" and option (a) "create stub company at deposit" are both rejected.

**Proof — live OPS-Web signup flow on 2026-05-25:**

1. `OPS-Web/src/app/api/auth/sync-user/route.ts` creates a `users` row with `company_id = null`, `is_company_admin = false` on first Firebase sign-in. The response shape is `{ user, company: null }`.
2. `OPS-Web/src/app/(auth)/register/page.tsx` routes the new user to `/account-type` after `sync-user` returns.
3. `OPS-Web/src/components/account-type/AccountTypeScreen.tsx` (`handleContinue` line ~156) routes the "Run a Crew" choice to `/setup`.
4. `OPS-Web/src/app/api/setup/progress/route.ts` (lines 103–161) creates the company on `step='company'`:
   - Inserts `companies` row with `account_holder_id = userId`, `admin_ids = [userId]`, plus `name`, `industries`, `company_size`, `company_age`, `weather_dependent` from the form data.
   - Calls `initialize_company_defaults(p_company_id)` RPC to seed task types, units, and settings.
   - Updates the user: `company_id = <new>`, `is_company_admin = true`.
5. The "Join a Crew" path goes through `/api/auth/join-company` which sets `users.company_id` to the joined company's id (employee role).

**Why a stub company at deposit time is wrong:** the existing `account_holder_id` model requires the company to point at exactly one user as the account holder. A SPEC buyer who later turns out to be a team-member joining another existing company would create a phantom owner-less company that pollutes admin queries, billing surface, and the multi-engagement model. The existing `/setup` flow is the proven path; SPEC reuses it.

**`resolveSpecCompanyForProject(buyerUserId)` — locked:**

```typescript
// Server-side, called from POST /api/spec/create-checkout-session before the
// billing-address form even renders. If this throws, the route 409s with a
// redirect target so the UI sends the buyer to /setup.

type ResolveResult =
  | { ok: true; companyId: string; companyName: string; accountHolderUserId: string; isBuyerAccountHolder: boolean }
  | { ok: false; reason: 'no_company' | 'company_deleted' | 'no_account_holder'; redirectTo: string };

async function resolveSpecCompanyForProject(buyerUserId: string, tier: 'setup'|'build'|'enterprise'): Promise<ResolveResult> {
  const db = getServiceRoleClient();

  const { data: user } = await db.from('users')
    .select('id, company_id, deleted_at')
    .eq('id', buyerUserId)
    .is('deleted_at', null)
    .single();

  if (!user || !user.company_id) {
    // Case A: brand-new OPS user, no company yet (just finished register flow).
    // Case B: orphaned user whose company was deleted (rare, but possible if a
    //         company is soft-deleted while a user is still pointed at it).
    return { ok: false, reason: 'no_company', redirectTo: `/setup?returnTo=${encodeURIComponent(`/spec?tier=${tier}`)}` };
  }

  const { data: company } = await db.from('companies')
    .select('id, name, account_holder_id, deleted_at')
    .eq('id', user.company_id)
    .is('deleted_at', null)
    .single();

  if (!company) {
    return { ok: false, reason: 'company_deleted', redirectTo: `/setup?returnTo=${encodeURIComponent(`/spec?tier=${tier}`)}` };
  }

  if (!company.account_holder_id) {
    // Defensive — should never happen in practice (the /setup company step
    // sets account_holder_id = userId at insert), but handle the corner
    // case rather than 500.
    return { ok: false, reason: 'no_account_holder', redirectTo: '/account-type' };
  }

  return {
    ok: true,
    companyId: company.id,
    companyName: company.name,
    accountHolderUserId: company.account_holder_id,
    isBuyerAccountHolder: company.account_holder_id === buyerUserId,
  };
}
```

The `isBuyerAccountHolder` flag drives Path A vs Path B branching (see § 03_WORKFLOW.md).

**`/setup` returnTo support.** This requires a one-line addition to `OPS-Web/src/app/(onboarding)/setup/page.tsx` (or its corresponding completion handler): after `step='company'` succeeds, check the `returnTo` query param and, if present, push the user there instead of the default post-setup destination. Implementation cost: trivial. This is in the OPS-Web critical files list and tracked as a Phase 1 implementation task.

**Stage C.1 implementation status (2026-05-26):** Landed on OPS-Web `feat/spec-setup-returnto`. `handleCompanyNext` now calls `readSafeReturnTo()` after the `/api/setup/progress` POST. The helper reads `returnTo` from `window.location.search` and only honors **same-origin relative paths** (must start with `/`, must not start with `//`, must not contain a URL scheme). Protocol-relative URLs and absolute schemes are rejected to prevent open-redirect phishing. When honored, the navigation uses `window.location.assign(returnTo)`; otherwise the flow continues to `setPhase("starfield")` as before. The matching ops-site `resolveSpecCompanyForProject()` lives at `ops-site/src/lib/spec/resolve-company.ts` on `feat/spec-checkout-flow` (Stage C.1, P1-2-6).

**The no-company buyer path is REMOVED from `spec_projects`. Every `spec_projects` row has a non-null `linked_company_id`.** The schema's existing `linked_company_id uuid references public.companies(id) on delete set null` stays, but the API never inserts a row without that field populated.

**Subscription billing implication.** Because the company exists at deposit time but `companies.stripe_customer_id` may be null (set on first OPS subscription bill), Phase 1 also adds: at the approved-Stripe-payment-success webhook, if `companies.stripe_customer_id IS NULL`, populate it from `session.customer`. Future SPEC subscription multiplier billing reads this field.

### SPEC-NOTIFICATION-RAIL-DEPRECATED — Resolved 2026-05-25

**Decision: the notification rail is NOT deprecated. It is actively used.** The earlier reviewer flag was a false alarm caused by the rail being moved from the TopBar into an edge-tab drawer pattern.

**Proof — live OPS-Web state on 2026-05-25:**

- `OPS-Web/src/components/layouts/dashboard-layout.tsx:15` imports `NotificationsDrawer`.
- `OPS-Web/src/components/layouts/dashboard-layout.tsx:291` mounts `<NotificationsDrawer />`.
- `OPS-Web/src/components/layouts/dashboard-layout.tsx:292` mounts `<NotificationsTab />` (the edge tab that toggles the drawer).
- `OPS-Web/src/components/layouts/notifications-drawer.tsx:41` calls `useNotifications()` which reads from `public.notifications`.
- Live data: `public.notifications` has 291 rows, max `created_at = 2026-05-19`, 16 distinct `type` values active in the last 30 days (e.g. `mention`, `task_review_stack`, `system_alert`, `gmail_sync`, `trial_expiry`, `expense_submitted`, `payment_review_stack`, `leads_waiting`, `task_completion`).
- The PMF system writes `type='pmf_alert'` rows to the same table (`OPS-Web/CLAUDE.md` § PMF Dashboard → Notifications pipeline).
- The TopBar (`OPS-Web/src/components/layouts/top-bar.tsx`) does NOT contain a notification icon — the rail UI was moved to the edge-tab drawer pattern. This is the only thing the "deprecated" flag was right about: the visual placement changed. The notification *system* is alive.

**Locked routing for SPEC events (replaces all "after live-code verification" hedge language):**

| Event recipient | Channel | Notes |
|---|---|---|
| **Customer (buyer, account_holder)** — operational notices (deposit_confirmed, intake reminders, scope_doc_ready, P2/P3/P4 invoice, support_window_open, refund_processed, refund_denied, owner_approval_*, retainer_*, platform_sunset, tos_update) | **Email (primary) + in-app rail (secondary)** | Email always fires. In-app row inserted into `public.notifications` with `user_id = buyer_user_id` (or account_holder_user_id for owner_approval_*), `company_id = linked_company_id` (guaranteed non-null per [[SPEC-NO-COMPANY-BUYER-FLOW-LOCK]]), `type = 'spec_*'`, `persistent` per urgency, `action_url = /account/spec/{id}` (Phase 1: `/account/spec/{id}/request-refund` for refund-related; Phase 2: full portal). |
| **Operator (Jackson, future SPEC operators)** — workflow events (owner approval requested, new SPEC deposit, intake completed, scope signed by customer, midpoint accepted, customer rated ≤ 2, refund requested, Stripe dispute, on_hold escalation, regulated-workflow flagged, referral KYC required, related-entity flag) | **In-app rail (primary) + TODAY queue + email (escalation only)** | In-app row inserted with `user_id = each_spec_operator_user_id`, `company_id = OPS_OPERATIONS_COMPANY_ID`, `type = 'spec_*'`, `persistent` per urgency, `action_url = /admin/spec/{id}`. Email fires ONLY for: Stripe dispute opened, refund requested, regulated workflow flagged, related-entity flag, 7-day comms cadence missed (the high-urgency subset). The TODAY queue at `/admin/spec` reads from the same `notifications` rows plus computed views; rows render in both places. |
| **Customer or operator** — informational (referral became eligible, retainer activated/cancelled) | **In-app rail only** | No email noise. |

**`company_id` routing rules (locked):**
- Operator-facing rows: `company_id = OPS_OPERATIONS_COMPANY_ID = '00000000-0000-0000-0000-00000000000a'`.
- Customer-facing rows: `company_id = linked_company_id` (non-null guaranteed by [[SPEC-NO-COMPANY-BUYER-FLOW-LOCK]]).
- No-company case is now impossible — the deposit gate enforces a company exists.

**Updated dispatch pattern (Phase 1 implementation):**

```typescript
// OPS-Web/src/lib/notifications/spec-dispatch.ts (NEW)
// Mirrors the existing notification-dispatch.ts helpers but for SPEC.

export async function dispatchSpecOperatorNotification(args: {
  type: `spec_${string}`;          // e.g. 'spec_deposit_received', 'spec_refund_requested'
  title: string;                    // tactical OPS voice — pass through ops-copywriter skill at build time
  body: string;
  persistent: boolean;
  specProjectId: string;
  actionLabel?: string;             // defaults to 'OPEN'
}): Promise<void> {
  const db = getServiceRoleClient();
  const operatorUserIds = await getSpecOperatorUserIds(); // from private.is_spec_operator's data source
  for (const userId of operatorUserIds) {
    await db.from('notifications').insert({
      user_id: userId,
      company_id: OPS_OPERATIONS_COMPANY_ID,
      type: args.type,
      title: args.title,
      body: args.body,
      persistent: args.persistent,
      action_url: `/admin/spec/${args.specProjectId}`,
      action_label: args.actionLabel ?? 'OPEN',
    });
  }
}

export async function dispatchSpecCustomerNotification(args: {
  recipientUserId: string;          // buyer_user_id OR account_holder_user_id
  linkedCompanyId: string;          // non-null guaranteed
  type: `spec_${string}`;
  title: string;
  body: string;
  persistent: boolean;
  actionUrl: string;                // /account/spec/{id} or specific sub-route
  actionLabel?: string;
}): Promise<void> {
  const db = getServiceRoleClient();
  await db.from('notifications').insert({
    user_id: args.recipientUserId,
    company_id: args.linkedCompanyId,
    type: args.type,
    title: args.title,
    body: args.body,
    persistent: args.persistent,
    action_url: args.actionUrl,
    action_label: args.actionLabel ?? 'OPEN',
  });
}
```

**Side effect for root `CLAUDE.md`.** The line "The web app has a notification rail in the header" is now stale (the rail is in an edge-tab drawer). That correction is a separate CLAUDE.md hygiene task — out of scope for this gate, but worth flagging.

### SPEC-SERVER-ROUTES-VS-RAW-RLS-DECISION — Resolved 2026-05-25

**Decision: Phase 1 exposes ZERO raw SPEC table reads/writes to anon or authenticated client SDKs, except `spec_public_board_snapshot` (sanitized aggregate, public read).** Every customer-facing surface goes through a server route that uses the service-role Supabase client + explicit authorization checks + narrow projections.

**Authorization pattern (every customer route, no exceptions):**

```typescript
// 1. Verify Firebase ID token from Authorization header
const decoded = await verifyAuthToken(req.headers.get('authorization')?.replace(/^Bearer /, ''));

// 2. Resolve OPS user_id via existing helper
const user = await findUserByAuth(decoded.uid, decoded.email, 'id, company_id');
if (!user) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });

// 3. For project-scoped routes: load the spec_projects row with service-role and
//    verify the caller is the buyer_user_id OR the account_holder_user_id.
const db = getServiceRoleClient();
const { data: project } = await db.from('spec_projects')
  .select('id, buyer_user_id, account_holder_user_id, status, walkthrough_completed_at')
  .eq('id', params.id)
  .single();

if (!project || (project.buyer_user_id !== user.id && project.account_holder_user_id !== user.id)) {
  return NextResponse.json({ error: 'Not found' }, { status: 404 });  // 404 not 403 to avoid existence-disclosure
}

// 4. Apply route-specific business logic with service-role client.
// 5. Return narrow projection (specific fields only — never the whole row).
```

**Phase 1 customer-facing server routes (complete enumeration):**

| Path | Method | Auth | Input (narrow) | Output (narrow) | DB writes | Notes |
|---|---|---|---|---|---|---|
| `/api/spec/board` | GET | None (public) | — | `{ tiers: [{ tier, availability, waitlist_bucket, next_start_week, is_accepting_bookings, public_note }], refreshed_at }` | None (reads `spec_public_board_snapshot` only) | Cache-Control: `public, max-age=300, s-maxage=300, stale-while-revalidate=60`. The snapshot table is the only SPEC table with public SELECT. |
| `/api/spec/create-checkout-session` | POST | Firebase ID token (signed-in OPS user) | `{ tier: 'setup'|'build'|'enterprise', billing: { line1, line2?, city, province, postal_code, country }, attestations: { no_qc_head_office, no_qc_operating_address, no_qc_establishment, no_material_qc_use }, referrer_email? }` | Path A: `{ stripe_url }` ; Path B: `{ awaiting_approval: true }` | Inserts `spec_projects` (status=awaiting_owner_approval OR awaiting_deposit), optionally `spec_owner_approval_requests` | Calls `resolveSpecCompanyForProject()` first; 409+redirect if no company. Pre-Stripe Quebec rejection lives here. |
| `/api/spec/owner-approval/[token]` | POST | Firebase ID token (signed-in OPS user, must match `account_holder_user_id`) | `{ action: 'approve'|'decline' }` | `{ status: 'approved'|'declined', checkout_url? }` | Updates `spec_owner_approval_requests`, updates `spec_projects.status`, inserts `spec_acceptance_events` (event_type='owner_purchase_approved' on approve) | Token comparison is bcrypt/argon2 hash. |
| `/api/spec/checkout/[buyer_checkout_token]` | GET | Firebase ID token (signed-in OPS user, must match `buyer_user_id`) | — (token in URL) | `302 → stripe_url` | Updates `spec_owner_approval_requests` (token consumed) | Validates token hash; creates Stripe Checkout Session. |
| `/api/spec/intake/submit` | POST | Token-gated (intake token from `spec.intake_completed_customer` email link) | `{ intake_token, responses: jsonb, regulated_workflow_attestations: {...}, uploaded_file_paths: [...] }` | `{ ok: true }` | Updates `spec_projects.intake_completed_at`, `intake_responses`, fires emails | Token bound to a specific `spec_projects.id` at issuance. |
| `/api/account/spec/[id]/request-refund` | POST | Firebase ID token (must be buyer or account_holder of project) | `{ reason_text: string }` | `{ request_id: uuid }` | Inserts `spec_refund_requests` with `request_source='customer_initiated'`, `customer_reason_text`, server-computed `is_guarantee_invocation` / `is_goodwill`, `status='pending'` | NO processing controls exposed — Jackson processes via `/admin/spec/refunds`. |
| `/api/admin/spec/board/refresh` | POST | Firebase ID token + `private.is_spec_operator()` check | — | `{ refreshed_at: ISO }` | Calls `private.refresh_spec_board_snapshot()` via service-role client | Manual force-refresh for operators. |

**Phase 1 operator routes** (gated on `private.is_spec_operator()` — the same authorization helper):

Every `/api/admin/spec/*` route checks `is_spec_operator()` (re-implemented in TS as a service-role query for the layout/middleware gate, plus the SQL function for any direct-from-Supabase calls). Customer-side company admins do NOT satisfy this gate. The full /admin/spec/* surface (TODAY queue, Kanban, project detail, refunds queue, owner-approvals queue, capacity config) all operate through this gate.

**Phase 2 (deferred — explicitly NOT shipping in Phase 1):**

| Path | Reason for Phase 2 |
|---|---|
| `/account/spec/[id]` (read-only portal: timeline, acceptance evidence, scope doc, satisfaction-survey UI, ticket filing) | Volume polish, not blocking ads launch |
| `/api/account/spec/[id]/support-tickets` | Same |
| `/api/account/spec/[id]/satisfaction-ratings` | Same |

The Phase 2 portal still goes through server routes — the locked Phase 1 posture (no raw client-SDK access to SPEC tables) carries forward unchanged. Any later decision to expose a constrained raw-RLS path (e.g., a direct `select` for the customer's own scope_documents) requires a deliberate migration with column-level grants, CHECK constraints, immutability guarantees on server-computed fields, and a test that anon/authenticated cannot bypass the constraint.

**RLS posture verification (the spec is already correct on this; this is the explicit lock):**

| Table | anon SELECT | authenticated SELECT | anon/auth INSERT | anon/auth UPDATE | anon/auth DELETE |
|---|---|---|---|---|---|
| `spec_projects` | ❌ | ❌ | ❌ | ❌ | ❌ |
| `spec_owner_approval_requests` | ❌ | ❌ | ❌ | ❌ | ❌ |
| `spec_scope_documents` | ❌ | ❌ | ❌ | ❌ | ❌ |
| `spec_acceptance_events` | ❌ | ❌ | ❌ | ❌ | ❌ |
| `spec_module_entitlements` | ❌ | ❌ | ❌ | ❌ | ❌ |
| `spec_payments` | ❌ | ❌ | ❌ | ❌ | ❌ |
| `spec_change_orders` | ❌ | ❌ | ❌ | ❌ | ❌ |
| `spec_feature_acceptance` | ❌ | ❌ | ❌ | ❌ | ❌ |
| `spec_satisfaction_ratings` | ❌ | ❌ | ❌ | ❌ | ❌ |
| `spec_support_tickets` | ❌ | ❌ | ❌ | ❌ | ❌ |
| `spec_retainers` | ❌ | ❌ | ❌ | ❌ | ❌ |
| `spec_communications` | ❌ | ❌ | ❌ | ❌ | ❌ |
| `spec_refund_requests` | ❌ | ❌ | ❌ | ❌ | ❌ |
| `spec_referrals` | ❌ | ❌ | ❌ | ❌ | ❌ |
| `spec_blocked_buyers` | ❌ | ❌ | ❌ | ❌ | ❌ |
| `spec_capacity` | ❌ | ❌ | ❌ | ❌ | ❌ |
| **`spec_public_board_snapshot`** | ✅ | ✅ | ❌ | ❌ | ❌ |

The only "✅" anywhere is `spec_public_board_snapshot` SELECT — which is sanitized aggregate-only data.

**Migration handoff verification.** The Phase 1 RLS migration must include tests that prove (a) anon connections cannot SELECT/INSERT/UPDATE/DELETE on any SPEC table except snapshot read, and (b) authenticated (non-operator) connections same. The tests run against a freshly-applied migration in a Supabase branch.

## Known open items — Brand calls for "built by a contractor, for contractors" feel. Currently no Jackson photo, name, story, or video on `/spec`. Confirmation page calls for a 60-90s founder welcome video. Asset dependency: requires recording. Decision: include in Phase 1 if video is recorded in time, otherwise text-only Phase 1 with video added in Phase 2.

2. **Final legal prose + counsel review.** Final customer-facing ToS + Privacy + DPA prose is a Phase 1 blocker before automated live deposits. Counsel review of those documents is recommended risk mitigation, not a launch blocker per Jackson's decision. Counsel review before volume scaling is still the recommended path. Costs are unknown until counsel is briefed.

3. **Calendly / Cal.com choice** — discovery + walkthrough scheduling. Decision needed; integration code differs slightly.

4. **Founder video on confirmation page** — content assumed, but recording is a real asset task (script, record, edit, upload, embed). Tracked under open item 1.

5. **Phased subscription billing rollout** — OPS-Web billing engine must read `spec_module_entitlements` for multiplier + surcharge and produce a combined invoice line. Schema is ready; the billing-engine wiring is its own task outside this SPEC spec's strict scope. Confirm it lands before any SPEC engagement reaches `walkthrough_completed_at + 30 days`.

6. **Per-trade SPEC landing pages (`/spec/for-roofers`)** — moved to Phase 3 but may be valuable in Phase 1 for ad targeting. Brief decision needed.

7. **Block-list before payment** — `spec_blocked_buyers` check happens in the Stripe payment-session creation API (after billing-address validation, before Stripe call). Implementation requires intercepting before the Stripe call. Confirm pattern with existing shop blocklist if one exists; otherwise build fresh. `spec_blocked_buyers.email` is `citext` (case-insensitive), so the query lowercases nothing — direct compare works.

8. **Meta CAPI + Google Enhanced credentials** — API tokens needed in Vercel env. Procurement task: Meta Business → Events Manager → CAPI access token; Google Ads → Conversion Linker + Enhanced Conversions API key.

9. **Stripe Connect Express setup** — required for referral payouts in Phase 2. Procurement + Stripe-side onboarding.

10. **T4A issuance flow** — Phase 2+. Manual at low volume (Jackson issues from QuickBooks); automate when referral volume justifies. YTD payout derived from `spec_referrals` at query time — no denormalized column.

11. **Verification that `role_permissions.scope` accepts `'all'`** — confirmed at migration time. If a `'global'` scope value is added to the production database before SPEC launch, the `is_spec_operator()` body is updated to consult both `'all'` and `'global'`. The currently-shipped revision consults only `'all'`.
