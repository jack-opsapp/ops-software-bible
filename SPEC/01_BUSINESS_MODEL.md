# SPEC — Business Operating Model

Every locked policy decision for SPEC engagements, organized into 10 categories. Each section captures the rule, the rationale, and the schema implications. Revised 2026-05-25 (fourth pass) to apply the legal/commercial correction pass: Phase 0 is conversation-only, automated live deposits require final legal prose, the guarantee / limitation of liability / IP language is replaced, Quebec exclusion is tightened, and implementation-risk bug_reports are explicit.

For the implementation of these policies, see:
- [02_DATA_MODEL.md](02_DATA_MODEL.md) — schema
- [03_WORKFLOW.md](03_WORKFLOW.md) — state machine
- [04_CUSTOMER_UX.md](04_CUSTOMER_UX.md) — customer-facing surfaces
- [05_ADMIN_UX.md](05_ADMIN_UX.md) — operator-facing surface
- [06_CONTRACT_AND_EMAILS.md](06_CONTRACT_AND_EMAILS.md) — contract document
- [07_ROLLOUT.md](07_ROLLOUT.md) — phased build

---

## 1. Buyer identity & account state

The binding authority on every SPEC engagement is the company's `account_holder_id` (a text column on `public.companies` storing the owner's `users.id` cast to text). All money decisions trace to that user. The buyer is just the person who clicked the button — the buyer is not necessarily authorized to commit company funds.

**Account required before deposit.** The "Pay Deposit" CTA on `/spec` is gated by an authenticated OPS session. Unauthenticated clicks route through OPS-Web sign-in/sign-up with `returnTo=/spec?tier=X`, then back to `/spec` with a session. The Stripe payment flow never fires without a known `users.id` in metadata.

**Owner approval gates Stripe — not the other way around.** This is a hard reversal from the original spec. The flow:

1. Authenticated buyer clicks "Pay Deposit" for tier X on `/spec`.
2. **Eligibility address collected in OPS first.** A short pre-Stripe form (rendered on the marketing site post-CTA) collects billing line1/line2, city, **province**, postal code, country, plus required attestations that Customer has no Quebec head office, Quebec operating address, Quebec establishment, or material SPEC use in Quebec. The form runs server-side validation BEFORE any Stripe payment session is created. Province `QC` is rejected with an explanation and a contact-form link. Billing address is a gate, not the only eligibility rule. The address and attestations are written to `spec_projects.billing_*` / intake evidence at row insert. Stripe never fires for an ineligible Quebec engagement.
3. Server resolves the buyer's active company. Compares `users.id::text` to `companies.account_holder_id`.
4. If buyer == account_holder: server creates the Stripe Checkout Session only after the eligibility gate passes. Per resolved `SPEC-STRIPE-ADDRESS-TAX-SPIKE` (2026-05-25), Checkout is the locked choice. The session is created with `customer` (pre-filled with the OPS Customer's saved address), `customer_email`, `automatic_tax: { enabled: true }` (Stripe Tax derives GST/HST/PST from billing province), `billing_address_collection: 'required'`, `consent_collection: { terms_of_service: 'required' }` (the dedicated ToS mechanism — `custom_fields` doesn't support checkboxes), `phone_number_collection: { enabled: true }`, and `custom_fields` for the optional GST/HST number. The hosted Stripe page allows the customer to edit the pre-filled billing address — the webhook defense in step 8 (below) catches any post-Stripe Quebec leak.
5. If buyer ≠ account_holder: server creates a `spec_owner_approval_requests` row (status `pending`, with an `approved_total_cents`, `approved_deposit_cents`, `approved_tos_version_hash` snapshot), fires `spec.owner_approval_required` email + persistent notification to the account_holder. **No Stripe payment session is created yet.** Buyer sees an in-app confirmation: "Your owner [name] must approve this purchase before payment. We've sent them an email."
6. Account_holder clicks the one-click approve link, lands on `/spec/owner-approval/[token]`, signs in if needed, reviews the tier + total + the current ToS version, approves. The approval action writes a `spec_acceptance_events` row with `event_type = 'owner_purchase_approved'`, capturing the account_holder's IP, user agent, signature method, and the ToS version hash they reviewed. This is a binding acceptance event — the account_holder is on record as having authorized the purchase under the ToS as it stood at approval time. Server generates a short-lived (24h) buyer checkout token (the URL emits the plaintext; the DB stores only the bcrypt/argon2 hash).
7. Buyer receives `spec.owner_approval_granted` email with a link back to `/spec/checkout/[buyer_checkout_token]`. Clicking validates the hash and opens the approved Stripe payment flow for the approved tier. ToS acceptance is still required in that flow — this is the BUYER's acceptance, separate from the account_holder's. Token consumed on session creation.
8. On `checkout.session.completed` (with `metadata.type === 'spec_deposit'`), the webhook FIRST runs the Quebec post-Stripe defense: inspect `session.customer_details.address.state` — if `QC` (or `country !== 'CA'`), refund the captured payment immediately, cancel the project (`cancellation_reason='quebec_billing_at_stripe'`), block the buyer in `spec_blocked_buyers` (misrepresentation per § 3), notify, return. Otherwise: write a second `spec_acceptance_events` row with `event_type = 'tos_accepted'` keyed to the buyer's user_id, IP, user agent, and the build-time `tos_version_hash` from metadata (corroborated by `session.consent.terms_of_service === 'accepted'`).
9. If account_holder declines: approval row → `declined`, buyer notified, no money has moved.

This eliminates the original spec's chargeback risk where SPEC charged first and asked the owner second. No refund is required when an owner declines, because no charge ever happened. For Path B engagements, the evidence chain on every dispute carries TWO acceptance events: the account_holder's `owner_purchase_approved` and the buyer's `tos_accepted`.

**Existing OPS subscriber → company auto-attached.** The buyer's active company is captured into Stripe metadata (`company_id`). On webhook completion, `spec_projects.linked_company_id` is populated. Multiple SPEC engagements per company are supported (see §7 on entitlements).

**No-company buyers go through `/setup` first** (resolved per `SPEC-NO-COMPANY-BUYER-FLOW-LOCK`, 2026-05-25). A buyer without a `users.company_id` cannot reach the SPEC deposit form. At the "Pay Deposit" click, the server calls `resolveSpecCompanyForProject(buyerUserId, tier)`; if the user has no company, the response is `409` with `redirectTo: '/setup?returnTo=/spec?tier=X'`. The existing OPS-Web `/setup` flow creates the company at `step='company'` (inserts a `companies` row with `account_holder_id = buyerUserId`, `admin_ids = [buyerUserId]`, calls `initialize_company_defaults()`, links the user as `is_company_admin=true`), then honors the `returnTo` query param and routes back to `/spec?tier=X`. This guarantees `spec_projects.linked_company_id` is non-null on every SPEC engagement and that Path A vs Path B branching always has a defined `account_holder_id`. See 07_ROLLOUT.md § Gate resolutions for the full `resolveSpecCompanyForProject()` pseudocode and the live signup-flow citations.

**Multi-engagement support.** A single company may run multiple SPEC engagements simultaneously or sequentially. Examples: a Build engagement for the field-crew module while a Setup engagement reconfigures dispatcher workflows. Each engagement gets its own `spec_projects` row, its own scope doc version, its own multiplier/surcharge entry in `spec_module_entitlements`, and its own 30-day guarantee window. Refunds, holds, and disputes are per-engagement.

## 2. Payment terms

**Structure: 25 / 25 / 25 / 25 across all three tiers. Locked. No exceptions.**

| Tier | P1 deposit | P2 scope sign-off | P3 midpoint demo | P4 delivery | Total |
|---|---|---|---|---|---|
| Setup | $750 | $750 | $750 | $750 | $3,000 |
| Build | $2,125 | $2,125 | $2,125 | $2,125 | $8,500 |
| Enterprise | $4,500 | $4,500 | $4,500 | $4,500 | $18,000 |

**Payment triggers:**

1. **P1 — Deposit** at click-to-book on `/spec` via the approved Stripe payment flow. Funds discovery + scope work. Refundability governed by the refund matrix in §3.
2. **P2 — Scope sign-off** when the scope doc is countersigned via `spec_acceptance_events.event_type = 'scope_signoff'`. Stripe Invoice, net-15. Funds build kickoff.
3. **P3 — Midpoint demo** when the midpoint deliverable is accepted via `spec_acceptance_events.event_type = 'midpoint_accepted'`. Stripe Invoice, net-15.
4. **P4 — Delivery** when modules are deployed AND the walkthrough has been held AND `walkthrough_completed_at` is stamped. Stripe Invoice, net-15. The walkthrough timestamp is the single canonical anchor for the support window, the 30-day guarantee, referral payout eligibility, and the retainer offer (see §6, §8, §9).

**Midpoint definition per tier** (locked at scope sign-off, written into the versioned scope doc):

- **Setup:** Workflow analysis complete; custom pipeline stages + custom fields deployed to a staging environment for customer review.
- **Build:** Working prototype of the custom module on staging, demonstrating roughly 50 percent of the agreed feature list.
- **Enterprise:** Same as Build, applied to the first of multiple custom modules. Subsequent modules remain in build phase at P3.

**Non-payment policy.** If a milestone invoice is unpaid 7 calendar days past the net-15 due date, the relevant entitlements in `spec_module_entitlements` flip `enabled = false` with `disabled_reason = 'non_payment'`. Work pauses. Re-enable on payment. The 30-day guarantee window does not run during a non-payment disabled period (see §3 anti-abuse rules).

**Currency + tax.**
- CAD-only at launch. USD considered when measurable US demand exists. The published intake form rejects Quebec billing addresses and screens for Quebec head office, operating address, establishment, and material SPEC use (see §3 governing law).
- Stripe Tax enabled — auto-calculates GST/HST/PST. QST is irrelevant because Quebec is excluded.
- Tax shown as a line item on the approved Stripe payment flow + invoices.
- `SPEC-STRIPE-ADDRESS-TAX-SPIKE` resolved 2026-05-25: Stripe Checkout (hosted) is the locked payment UI. Session parameters: `customer + customer_email + automatic_tax.enabled + billing_address_collection: 'required' + consent_collection.terms_of_service: 'required' + phone_number_collection.enabled + custom_fields` (for optional GST/HST). The hosted page lets the customer edit the pre-filled billing address (Stripe has no lock parameter); the webhook MUST defend the Quebec-leak case — see § 10 below and 07_ROLLOUT.md § Gate resolutions.

**Chargeback policy.** Contested aggressively. Standard evidence package: `spec_acceptance_events` rows (ToS acceptance, scope signoff, midpoint accept, delivery accept), `intake_responses`, the versioned `spec_scope_documents` content_json + content_hash, the walkthrough recording URL, the full `spec_communications` log.

**Stripe payment collected fields.**
- Email + name (required, prefilled from signed-in OPS user)
- Billing address — already collected pre-payment in OPS and used for the eligibility gate. The Stripe Checkout Session is created with `customer` set to a Stripe Customer object that has the OPS-collected address pre-populated; `billing_address_collection: 'required'` shows the address on the hosted page. Stripe does not support locking the address — the customer can edit it. The webhook Quebec-defense path (per resolved `SPEC-STRIPE-ADDRESS-TAX-SPIKE`, see § 10 and 07_ROLLOUT.md § Gate resolutions) catches any post-Stripe edit to `QC` or non-`CA`: refund, cancel, block-list, notify.
- Phone (required)
- GST/HST number (optional, captured as custom field, attached to Stripe customer for input-tax-credit invoices)
- "I agree to the SPEC Terms of Service v[hash]" (required, recorded as a `spec_acceptance_events` row with `event_type='tos_accepted'`, the IP, user agent, and the build-time hash of the ToS commit). On Path B, this is the second of two acceptance events — the first is the account_holder's `owner_purchase_approved` at the owner-approval step.

**UTM + ad attribution.** Every checkout session captures `utm_source`, `utm_medium`, `utm_campaign`, `utm_content`, `utm_term`, `gclid`, `fbclid` into Stripe metadata at session creation. UTM values come from a first-touch cookie set on ops-site (30-day persistence). The webhook copies them into `spec_projects.attribution`. See [04_CUSTOMER_UX.md](04_CUSTOMER_UX.md) § Conversion tracking.

## 3. Contract / legal

**Contract form.** A single comprehensive Terms of Service document at `/legal?page=spec-terms` (a new tab on the existing `/legal` page). Click-to-accept happens in the approved Stripe payment flow via the "I agree to the SPEC Terms of Service" field. The build-time hash of the ToS commit is captured in `spec_acceptance_events`. No separate MSA or SOW required for standard engagements. Enterprise customers who request a DocuSigned MSA can get one case-by-case (billable hours).

**Quebec exclusion.** Service available in Canada excluding Quebec. A customer is ineligible if it has a Quebec billing address, Quebec head office, Quebec operating address, Quebec establishment, or material SPEC use in Quebec. The pre-payment billing-province block remains mandatory, but billing address is not the only eligibility rule. Intake must screen for Quebec operations and material use. Misrepresenting Quebec eligibility is a material breach and makes the guarantee unavailable. Rationale: Consumer Protection Act, French-language requirements, and Quebec privacy/commercial obligations add legal complexity not justified at launch volume.

**Regulated workflows excluded.** SPEC will not build:
- HIPAA / PHIPA / health-data workflows (medical records, PHI flowing through OPS)
- PCI raw card capture (Stripe handles tokenization; SPEC modules do not touch raw PAN)
- Regulated credit decisions (adverse-action notices, FCRA equivalents)
- Unlawful surveillance (employee tracking beyond labour-law-compliant timesheet + location features)
- CASL- or TCPA-violating bulk-messaging automation

These are intake form disqualifiers and ToS prohibitions. Jackson can decline an engagement post-intake without refund obligation if any of these surface during discovery; refund is governed by the §3 matrix.

**30-day Guarantee Refund — single invocation per engagement.** Customer may request the Guarantee Refund within 30 days after the Walkthrough Date by written notice stating dissatisfaction. OPS will not require Customer to prove a defect or allow OPS a cure period. Valid guarantee requests are processed within 7 business days. Modules feature-flagged off in `spec_module_entitlements`. Base OPS subscription unaffected.

Because milestones are net-15 invoiced, refund mechanics split by per-milestone payment state:

| Milestone state at refund time | Action |
|---|---|
| Paid via Stripe Payment Intent | Stripe Refunds API reverses the captured charge |
| Invoice issued, fully paid | Stripe Refunds API on the underlying Payment Intent |
| Invoice issued, partially paid | Stripe credit note for the unpaid portion + Stripe refund for the paid portion |
| Invoice issued, not paid (open) | Stripe void on the open invoice |
| Invoice issued, not paid, non-cancellable | Stripe `mark_uncollectible` (book closes; no further collection effort) |

Each per-milestone action is recorded as one element in `spec_refund_requests.refund_breakdown` (jsonb) with `milestone`, `stripe_resource_id`, `action`, `amount_cents`, `status`, `executed_at`. The `spec_payments` row for the milestone is updated to the matching status (`refunded`, `partially_refunded`, `voided`, `uncollectible`).

Anti-abuse rules:
- **One invocation per SPEC engagement.** A customer with multiple SPEC engagements can invoke the guarantee separately for each, but not twice for the same engagement.
- **Unavailable after chargeback, fraud, material misrepresentation, prohibited workflow, material breach, or continued use after refund.** Examples: evading the Quebec exclusion with a false address, concealing a Quebec establishment, attempting to use modules for an excluded regulated workflow, or continuing workaround use after refund.
- **Clock tolled during non-payment disablement.** The guarantee clock is tolled while modules are disabled for non-payment.
- **Customer must stop using the modules upon refund issuance.** Entitlements flip to `enabled = false` with `disabled_reason = 'refunded'`. Continued workaround use (e.g. exporting custom-built data + reinserting it elsewhere in OPS) is a breach.

**Refund matrix.** Single source of truth, used by §10 and the contract in §6.

| When | What is refundable |
|---|---|
| Pre-discovery (before the first discovery session is held) | Full P1 deposit at OPS's discretion — typically yes, no work done |
| Post-discovery, pre-scope-signoff | Pro-rated. P1 partially earned by discovery work. Jackson assesses. |
| Post-scope-signoff, pre-delivery | Pro-rated. Completed milestones non-refundable; unstarted milestones refundable. |
| Within 30 days of walkthrough_completed_at | Guarantee Refund on Customer's written request stating dissatisfaction. No defect proof and no cure period. One invocation per engagement, subject to exclusions. |
| After 30 days post-walkthrough | Build fees non-refundable. Customer may request goodwill refund — Jackson's discretion. Flagged `is_goodwill=true`. |

All refunds are manual customer-initiated requests processed by Jackson. No automated refunds, ever.

**Limitation of Liability (revised — locked).**

Except for Excluded Claims, during the Guarantee Period Customer's sole and exclusive remedy for dissatisfaction with the SPEC engagement is the Guarantee Refund. Excluded Claims means fraud, willful misconduct, gross negligence, breach of confidentiality, breach of privacy or security obligations, and OPS's express IP indemnity obligations. After the Guarantee Period, OPS's aggregate liability for non-Excluded Claims is capped at SPEC fees paid in the 12 months before the claim, less refunds.

The Excluded Claims carve-outs apply during and after the 30-day guarantee window. The guarantee cannot swallow fraud, willful misconduct, gross negligence, confidentiality breaches, privacy/security obligations, or OPS's express IP indemnity obligations.

Consequential, incidental, indirect, special, punitive, or exemplary damages are excluded always — including lost profits, lost revenue, lost data, lost opportunity, business interruption.

**Indemnification.** Customer indemnifies OPS against third-party claims arising from Customer's use of the software, Customer's data, Customer's employees, or Customer's clients. OPS gives the express IP indemnity obligations stated in the final SPEC Terms; those obligations are Excluded Claims and sit outside the non-Excluded Claim cap.

**IP ownership.** OPS owns all code, configurations, designs, templates, and reusable know-how created for SPEC. Customer owns its business data. While Customer maintains an active OPS subscription and is not in breach, OPS grants Customer a limited, non-exclusive, non-transferable license to use the delivered modules inside OPS. The license ends when the OPS subscription ends or the engagement is refunded. OPS may reuse anonymized patterns and reusable know-how, never Customer business data, in future SPEC engagements without compensation.

**Confidentiality.** Mutual NDA built into the ToS. Each party agrees not to disclose the other's confidential information except as required by law. Survives termination by 3 years.

**Acceptable use, prohibited use, subprocessors.** Explicit clauses in the ToS, listed in [06_CONTRACT_AND_EMAILS.md](06_CONTRACT_AND_EMAILS.md). Subprocessors at launch: Stripe (payments), Supabase (data), SendGrid (email), Vercel (hosting). Customer authorization to use these subprocessors is granted by ToS acceptance.

**Privacy + DPA.** The existing `/legal` Privacy Policy tab is updated to cover SPEC-specific data: intake responses (JSONB), file uploads to Supabase Storage, scope doc content_json, satisfaction-survey responses, communications log. A lightweight DPA already lives in the `dpa` tab and is referenced by the ToS. Final customer-facing ToS / Privacy / DPA prose is required before automated live deposits. Outside counsel review is recommended risk mitigation, not a hard launch blocker per Jackson's owner decision.

**Governing law + dispute resolution.**
- British Columbia, Canada
- Disputes ≤ $35,000 CAD → BC Small Claims Court, Vancouver
- Disputes > $35,000 CAD → Supreme Court of British Columbia, Vancouver
- No mandatory arbitration

## 4. Scope & change orders

**Scope is the SOW.** The scope doc is the binding statement of work. It must be defensible in a chargeback or dispute. Implementation: a versioned `spec_scope_documents` row with `content_json` (full feature list, acceptance criteria, exclusions, midpoint definition, delivery definition, subscription terms, surcharge if any), a SHA-256 `content_hash` of the content_json, an optional `external_url` for the human-readable Notion or Google Doc, and timestamps. Each revision is a new row with `version = previous + 1`; the previous row gets `superseded_at`.

**Scope lock point.** Customer countersignature on the scope doc — recorded as a `spec_acceptance_events` row with `event_type = 'scope_signoff'`, `scope_document_id` pointing at the specific version they accepted, IP, user agent, signature method (`click_in_app` or `docusign` or `email_reply`), and `payload_hash` matching the scope doc's `content_hash`. P2 invoice does not fire until this row exists.

**Scope doc contains:**
- Feature list with brief descriptions
- Per-feature acceptance criteria ("complete = X is true") — seeds `spec_feature_acceptance` rows
- Midpoint deliverable definition (roughly 50 percent of the feature list)
- Delivery deliverable definition
- Explicit exclusions ("we are NOT building X, Y, Z")
- Estimated start date + delivery window
- Subscription multiplier locked at this version
- Module surcharge locked at this version
- Reference to the active ToS version hash

**Core engagement is fixed-price.** No hours tracking, no overage proofs, no "demonstrate your time" disputes. P1-P4 milestones are flat amounts agreed at scope sign-off. If OPS gets it done faster, both win. If it takes longer, OPS absorbs (subject to the delay clauses in §6).

**Change requests during build.**
- **Minor changes (Jackson estimates < ~4 hours):** Billed hourly at $225/hr CAD. Customer pre-approves the estimate before work begins; the pre-approval is recorded as a `spec_acceptance_events` row with `event_type = 'change_order_accepted'`. Bucketed to nearest 30 minutes. Invoiced at the end of the milestone or project, net-15.
- **Major changes (Jackson estimates ≥ ~4 hours):** Billed as a fixed-price quote. Jackson writes up scope + price + delivery impact; customer accepts in writing (`spec_acceptance_events` row, same `event_type`). Tracked as its own row in `spec_change_orders`. Invoiced on completion, net-15.

OPS determines the estimate and the classification using the signed scope and acceptance criteria. The customer's option is accept or decline; estimates are not negotiable.

**Tier upgrade mid-engagement.**
- **Pre-scope-signoff (during discovery):** Full pro-rated upgrade. Customer pays (new tier price − payments already made). Discovery work counts toward the new tier. `tier` updates, `original_tier` recorded, `tier_upgraded_at` stamped.
- **Post-scope-signoff:** Case-by-case. Some work is redundant. Jackson assesses and provides a fixed-price upgrade quote, tracked as a `spec_change_orders` row with `change_type = 'tier_upgrade'`.

## 5. Acceptance & quality

**Delivery (P4 trigger) definition.**
- Modules deployed to customer's OPS instance, entitlements active in `spec_module_entitlements`
- A 30-60 min live walkthrough call (Zoom / Meet), recorded
- Recording link stored in `spec_projects.walkthrough_recording_url`
- `walkthrough_completed_at` stamped at the end of the call
- P4 invoice fires immediately after the walkthrough
- The 30-day guarantee window, the support window, the referral payout window, and the subscription multiplier first-bill date all anchor on `walkthrough_completed_at`

**Three-layer acceptance + quality model.**

**Layer 1 — Per-feature acceptance criteria (objective bar for invoice).** Each feature in the signed scope doc has a written acceptance test in `spec_feature_acceptance`. Passing criteria = scope met = invoice fires. Failing criteria = free fix until passing. Verified-pass is recorded as a `spec_acceptance_events` row when bundled at midpoint/delivery acceptance.

**Layer 2 — Satisfaction survey (subjective feedback, non-binding).** After P3 midpoint and P4 delivery, customer rates each feature 1-5:
- 5 / 4 — Done, move on.
- 3 — Scope met, customer has minor preferences. Use polish budget or billable change order.
- 2 — Customer thinks scope isn't quite met. Jackson reviews against criteria. Free fix if criteria fail; polish or change order if criteria pass.
- 1 — Customer claims scope violation. Jackson reviews criteria. Free fix if objectively failing; escalate to dispute resolution if criteria pass (rare; the ultimate out is the 30-day refund).

Ratings are feedback, not contractual leverage. A 1-star feature with passing criteria still triggers the invoice.

**Layer 3 — Polish budget (goodwill cap on free iteration).** OPS-absorbed polish hours after scope is met:
- Setup: 2 hours
- Build: 4 hours
- Enterprise: 8 hours

Polish budget logged but not invoiced. Used for satisfaction-driven minor tweaks. Exhausted budget = changes flow through the standard change-order process. Written into the ToS as discretionary ("OPS may include up to N hours of post-scope polish") to preserve legal flexibility.

**Bug vs feature classification during support window (severity-based).**
- **Critical** (breaks core workflow, blocks daily operation): always free regardless of scope. Same-business-day response, 48-hour resolution target.
- **High** (degrades but doesn't block): free if in scope. Billable if customer wants enhancement beyond scope. 3-business-day resolution.
- **Cosmetic / enhancement requests:** billable change order. No free fixes.

Customer files tickets via OPS-Web admin or email. Jackson tags severity. Customer can dispute the tag; ultimate arbiter is the acceptance criteria in the signed scope doc.

## 6. Timeline & SLA

**Delivery dates are aspirational, not firm deadlines.** The scope doc states "estimated to deliver between [date min] and [date max]". OPS commits to proactive communication, not penalty-backed dates.

ToS clause: "Delivery windows are good-faith estimates. OPS will notify Customer of any delay greater than 7 days within 48 hours and provide a revised estimate. No automatic credits, refunds, or penalties apply to delivery slips."

**Unresponsive customer escalation (post-deposit, pre-scope-signoff).**

| Days since last contact | Trigger | Status |
|---|---|---|
| 14 days | `spec.intake_reminder_1` email | `deposit_paid` |
| 30 days | `spec.intake_reminder_2` email + status → `stalled`. Slot freed. | `stalled` |
| 60 days | `spec.intake_reminder_3` email. Final. Status stays `stalled` indefinitely. No further nudges, no auto-refund. Customer keeps deposit on file. | `stalled` |

Customer can always cancel earlier via written request (refund per §3).

**Pause (hold) — two distinct types.** This is a clarification of the original spec's contradiction.

Holds have a `hold_type` field with two values:

- **`customer_requested`** — Customer asks to pause for any reason (vacation, busy season, internal alignment). Slot is freed and returned to the capacity pool. Other customers can book into the slot. Customer rejoins the queue on resume at the next available slot. Up to 90 calendar days. After 90 days, status flips to `stalled_on_hold`. No auto-refund.

- **`ops_blocked`** — OPS is waiting on the customer for something work cannot proceed without (intake fields, file uploads, third-party credentials, integration delays, internal customer decisions). Slot is consumed; nobody else can take it because the build is still active in Jackson's queue. Communication cadence guarantee continues. Resolution typically a few days to two weeks. After 30 days of `ops_blocked` with no customer response, Jackson can convert it to `customer_requested` (frees the slot) or escalate to a stall.

In both cases:
- `on_hold_at` stamped at entry
- `on_hold_reason` populated
- `hold_type` set
- `prior_status` recorded (so resume returns to the right state)
- `on_hold_expires_at` = `on_hold_at + 90 days` for `customer_requested`; not auto-set for `ops_blocked` (Jackson manages manually)
- `resume_requested_at` stamped when the resume trigger fires
- `resumed_at` stamped when status flips back to `prior_status`

Capacity logic in [02_DATA_MODEL.md](02_DATA_MODEL.md) and the workflow in [03_WORKFLOW.md](03_WORKFLOW.md) read `hold_type` to decide slot consumption. The OPS BOARD on `/spec` aggregates `customer_requested` holds as "freed" and `ops_blocked` as "consumed."

**OPS-caused delay.**
- OPS notifies the customer within 48 hours of any anticipated delay > 7 days.
- Notification: reason (general), revised ETA, customer action if any.
- No automatic credits, refunds, or polish-budget bonuses.
- Unacceptable delay = customer invokes cancellation + refund per §3.

**Communication cadence guarantee.** Status update from OPS at least every 7 calendar days during active build phase. Missed cadence = customer can ping; not contractual breach.

## 7. OPS subscription interaction

**Multi-engagement entitlements.** A company may run multiple SPEC engagements over time. Each engagement gets one or more entries in `spec_module_entitlements`, keyed by `(spec_project_id, company_id, module_key)`. The original spec's two booleans on `companies` (`spec_subscription_active`, `spec_modules_enabled`) cannot represent partial entitlement, one disputed engagement coexisting with one retained engagement, or a feature-flagged subset; they are removed. All subscription premium math and module enable/disable flags read `spec_module_entitlements`.

Each entitlement row carries:
- `enabled` boolean (feature-flag state)
- `disabled_reason` text (`non_payment`, `dispute`, `refunded`, `subscription_lapse`, `customer_request`, `ops_decision`, null)
- `stripe_subscription_item_id` (the Stripe line item driving the multiplier surcharge)
- `multiplier` (the per-engagement multiplier locked at scope sign-off — typically the tier estimate or a renegotiated value)
- `surcharge_cents` (the per-engagement flat-monthly surcharge, if any)
- `entitled_at`, `disabled_at`, `updated_at`

**Billing start (new SPEC customer, no existing subscription).**
- Discovery + build phase: free
- Subscription billing begins on the customer's first billing cycle after `walkthrough_completed_at + 30 days` (soft post-delivery trial)
- Default base tier: "Starter" at customer's team size at delivery
- Customer can upgrade base tier voluntarily

**Subscription tier change (existing OPS subscriber buys SPEC).** At `walkthrough_completed_at`, the customer is offered the subscription adjustment: keep current base tier + add the SPEC multiplier surcharge (sum of all enabled entitlements in `spec_module_entitlements`).
- Accept: new rate applies on the billing cycle following `walkthrough_completed_at + 30 days`
- Decline: that engagement's entitlements all flip to `enabled = false` after a 30-day grace; base subscription continues unchanged

**SPEC subscription premium (published estimate — actual locked at P2).**

| SPEC tier | Published estimate (on `/spec`) |
|---|---|
| Setup | +15% on base OPS subscription |
| Build | +30% on base OPS subscription |
| Enterprise | +50% on base OPS subscription |

The actual locked multiplier (plus any module-specific surcharge) is determined during discovery + scope phase and written into the scope doc at P2 sign-off. Locked rate is fixed for 12 months from `walkthrough_completed_at`; renegotiable at the 12-month mark if actual infra cost diverges materially.

**Annual subscriber proration.** If a customer is on an annual OPS subscription with N months remaining when SPEC delivers, the SPEC multiplier applies prorated to the remaining annual period: `additional_charge = annual_subscription × multiplier × (N / 12)`, charged as a one-time line item at `walkthrough_completed_at + 30 days`. The next annual renewal applies the full multiplier from day one. Surcharge cents are similarly prorated as a one-time `surcharge_cents × (N / 12)` line item.

**Module-specific surcharge (heavy infra cases).** If during discovery a proposed module is significantly more infra-heavy than the tier multiplier covers, Jackson identifies it before scope sign-off. A flat $/mo line is added to the scope doc subscription section and stored in `spec_module_entitlements.surcharge_cents`. At scope sign-off, the customer's options are accept the surcharge, descope the feature, or cancel (refund per the §3 matrix, pre-scope-signoff row).

**Subscription lapse post-delivery.**
- All enabled entitlements for the lapsed company flip to `enabled = false` with `disabled_reason = 'subscription_lapse'` immediately on cancellation.
- All module code + customer data retained on OPS infra (not deleted).
- Resume subscription → entitlements come back online with `enabled = true`, no re-onboarding fee.
- No time limit on the paused state.

## 8. Maintenance retainer

**Enrollment.** Opt-in. Email offer with a one-click Stripe subscription/payment link after support window closes. No silent enrollment. Retainer offer emails are commercial electronic messages and must include OPS sender identity, mailing/contact information, unsubscribe mechanism, and a documented consent basis.

**Retainer pricing (fixed monthly per tier).**

| SPEC tier | Retainer | Coverage |
|---|---|---|
| Setup | $250 / mo | Bug fixes + minor enhancements within scope + platform-update compat patches |
| Build | $450 / mo | Same as Setup, applied to the custom module |
| Enterprise | $750 / mo | Same scope, applied to all delivered modules |

**Coverage.**
- **Bug fixes** — anything that violates the signed scope's acceptance criteria. Critical/high severity prioritized.
- **Minor enhancements** — small tweaks within an existing module's scope. Jackson's judgment. < 4 hours per change.
- **Platform-update compat patches** — when OPS releases an update that affects the module, Jackson patches at no extra charge.
- **NOT covered:** new features, scope expansions, third-party integrations, module rewrites. These flow through the change-order process.

**Retainer hour budget.** No formal monthly cap. If a client consistently consumes abnormal hours (> 10/mo Build, > 20/mo Enterprise), Jackson proposes a tier bump or moves to billable change orders. Discretionary.

**Customer without retainer post-support.**
- Billed at standard $225/hr (minor < 4hr) or fixed-price quote (major).
- No response-time guarantee. Could be 2 days, could be 6 weeks.
- After the support window, ordinary bugs and enhancements can be billable unless covered by an active retainer or a still-active accepted support obligation.
- OPS does not disclaim duties for security/privacy obligations, confidentiality, willful misconduct, gross negligence, or defects covered by a still-active express warranty or accepted support obligation.
- The retainer's value is priority, predictable cost, and continued compatibility coverage for ordinary post-support work.

**Retainer billing.**
- Separate Stripe subscription product, monthly recurring
- Customer pauses/cancels via Stripe portal
- Cancellation effective end of current period
- No proration on cancellation
- Re-enrollment available anytime

**Retainer carryover.** None. Retainer is access, not banked hours.

**Retainer + support tickets are the same table.** A single `spec_support_tickets` table with a `phase` enum field (`support` | `retainer` | `ad_hoc`) handles both phases. The original spec referenced a separate `spec_retainer_tickets` table; that's merged in.

## 9. Off-boarding & ongoing rights

**Customer leaves OPS entirely (cancels OPS subscription).**
- All entitlements flip to `enabled = false` with `disabled_reason = 'subscription_lapse'` immediately.
- Business data exported on request as CSV/JSON via OPS-Web admin or support email.
- Module code stays with OPS per the IP clause.
- Resume subscription anytime → entitlements re-enable automatically, no re-onboarding fee.

**Platform feature sunset (OPS deprecates something the module depends on).**
- **With active retainer:** OPS rebuilds the affected functionality free. Maintains the original acceptance criteria.
- **Without retainer:** Rebuild billable at $225/hr or a fixed quote. 90-day advance notice given; customer can subscribe to the retainer before sunset to get the rebuild free.
- Customer declines rebuild → that functionality unavailable; other module features keep working.

**Module portability.** Not allowed. Per the IP clause, OPS owns all code, configurations, designs, templates, and reusable know-how created for SPEC. Customer owns its business data. Customer's license is limited, non-exclusive, non-transferable, usable only inside OPS while Customer maintains an active OPS subscription and is not in breach. The license ends when the OPS subscription ends or the engagement is refunded. No portability license at launch.

**Customer business pivot (wants new SPEC instead of existing).**
- Treated as a new engagement. New deposit, new scope, new milestones, new `spec_projects` row, new `spec_module_entitlements`.
- If the customer has paid the retainer ≥ 6 months at the time of the new SPEC purchase, $500 credit on the new engagement (loyalty gesture).

**Referral program ($500 bounty).**

- Anyone refers a new customer who completes a SPEC engagement.
- Bounty paid 30 days post-`walkthrough_completed_at` (cleared refund window) AND if the referred customer hasn't invoked a refund.
- $500 CAD per referred completed engagement, regardless of tier.
- Referral program is link-based. OPS should not email referred third-party prospects until they submit a form, start checkout, or otherwise expressly opt in. Referrer identity is captured from a referral link or from the referred customer's checkout/intake form, then validated against the buyer's email/company to detect self-referral.
- Bounty row created in `spec_referrals` on deposit (`status='pending'`), moves to `eligible` on `walkthrough_completed_at`, payout authorized 30 days later if no refund.

Referral payout prerequisites:
- Referrer completes Stripe Connect KYC (Express account). Without verified KYC, the bounty sits at `eligible` indefinitely.
- T4A reporting if referrer is Canadian and cumulative payouts to that referrer exceed $500 CAD in a calendar year. OPS issues T4A in Q1 of the following year.
- Self-referral detection: same email address as the buyer, same company as the buyer's `linked_company_id`, or same Stripe customer ID. Self-referrals auto-`forfeited`.
- Related-entity detection: simple match on shared domain, address, or phone. Flagged for Jackson's manual review before payout.
- Payout hold: if the referred project is in dispute, refunded, or non-payment-disabled, the bounty sits at `eligible` until resolution. Disputes that resolve in OPS's favour can release the bounty (Jackson's call); refunds permanently forfeit.

## 10. Marketing-traffic edge cases

**Core principle: no automated refunds, ever.** OPS does not proactively refund. Refunds are always initiated by an explicit customer request. Auto-cancellation of stalled engagements happens (stop emails, free slot) but deposits/payments stay with OPS until the customer asks. Applies to every flow below.

**Account + eligibility-address + owner-approval gate before Stripe.** Sign-up / sign-in MUST happen before Pay Deposit is clickable. Authenticated user required. Billing address and Quebec eligibility attestations are collected in OPS BEFORE any Stripe payment session is created. Quebec billing address, head office, operating address, establishment, or material SPEC use is rejected. If buyer ≠ account_holder, owner-approval flow gates Stripe entirely (per §1). Stripe is never charged speculatively.

**Customer pays deposit, doesn't complete intake.**
- Day 14: nudge email #1
- Day 30: nudge email #2 + status → `stalled`
- Day 60: nudge email #3 (final)
- Day 90: stop emailing. Project stays `stalled` indefinitely. No auto-refund.
- Customer re-engages anytime → Jackson decides re-slot or fresh.
- Refund requested → manual, Jackson's discretion (refund matrix pre-discovery row).

**Customer completes intake, doesn't book discovery.**
- Day 7: nudge email
- Day 21: nudge email #2 + status → `stalled`
- Day 60: nudge email #3 (final)
- Day 90: stop emailing. No auto-refund.

**Customer books discovery, no-shows.**
- 1st no-show: free reschedule (≥ 24h advance notice required for future).
- 2nd no-show: $100 CAD reschedule fee (invoiced via Stripe, net-15) before next slot.
- 3rd no-show: engagement cancelled. Deposit forfeited per ToS. Modules disabled if any work was done.
- Reschedules with ≥ 24h advance notice not counted (free, unlimited).

**Customer disputes a Stripe charge (chargeback).**
- OPS contests immediately with the evidence package.
- Entitlements feature-flagged off immediately on dispute notification (`disabled_reason = 'dispute'`).
- OPS wins: engagement cancelled. No goodwill restoration. Customer would re-purchase to re-engage.
- OPS loses: full reversal, engagement cancelled, customer added to `spec_blocked_buyers`.

**Pre-delivery refund requests.** Governed by the refund matrix in §3. All manual.

**Post-delivery refund within 30 days.** Guarantee Refund from §3. The Stripe refund/void/credit-note actions run only after Jackson clicks Process in the admin queue; the request is customer-initiated through the customer route or by written notice.

**Post-delivery refund 30+ days after walkthrough.** No contractual refund. Customer can ask for a goodwill refund; Jackson decides. If granted, flagged `is_goodwill = true` in `spec_refund_requests`.

**Buyer's remorse (paid deposit accidentally / wrong tier / wrong company).**
- Within 24h: full refund + cancellation on request.
- 24+ hours: standard refund policy.
- Wrong tier: tier swap before discovery starts (pre-scope upgrade rules from §4).
