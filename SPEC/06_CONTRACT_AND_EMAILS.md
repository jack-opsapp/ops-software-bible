# SPEC — Contract Drafting Requirements + Email & Event Triggers

## SPEC Terms drafting requirements

Lives at `/legal?page=spec-terms` on ops-site (a new tab on the existing `/legal` page). The final output must be a customer-facing Terms of Service document, not just this section outline. Click-to-accept happens in the approved Stripe payment flow. Versioned via build-time commit hash. The customer's accepted version is stored in `spec_projects.tos_version_accepted` and mirrored as a `spec_acceptance_events` row with `event_type = 'tos_accepted'`, IP, user agent, payload_hash. For Path B engagements, a second `spec_acceptance_events` row carries `event_type = 'owner_purchase_approved'` recording the account_holder's binding approval at the owner-approval step.

Revised 2026-05-25 (fourth pass) to:
- Mark this file as drafting requirements plus required final-prose clauses. Automated live SPEC deposits are blocked until final customer-facing ToS / Privacy / DPA prose exists.
- Replace the Guarantee Refund, limitation of liability, and IP/license clauses with the legal/pro review language.
- Tighten Quebec exclusion, CASL handling, support/retainer duties, and audit language.
- `SPEC-NOTIFICATION-RAIL-DEPRECATED` resolved 2026-05-25: the OPS-Web notification rail is alive (edge-tab `NotificationsDrawer` mounted in `dashboard-layout.tsx`, table actively used). Customer operational notices use email (primary) + `public.notifications` row (secondary, in-app rail). Operator work uses the admin TODAY queue + `public.notifications` row keyed to `OPS_OPERATIONS_COMPANY_ID`. See 07_ROLLOUT.md § Gate resolutions.
- State that outside counsel review is recommended risk mitigation, not a hard launch blocker per Jackson's owner decision.

### Phase 1 legal launch gate

Phase 0 conversation-only launch is approved. Automated live SPEC deposits are not approved until:

- Final customer-facing ToS prose exists at `/legal?page=spec-terms`.
- Final Privacy Policy prose covers SPEC data collection, processing, retention, subprocessors, and customer rights.
- Final DPA prose exists or the current DPA is versioned to cover SPEC scope.
- The final legal text includes the required fourth-pass clauses below.

Counsel review is recommended before deposits and strongly recommended before volume scaling or the first dispute, but it is not a hard launch blocker per Jackson's decision. Final legal prose is a hard Phase 1 blocker. A 29-section outline is not launch-ready ToS text.

### Required customer-facing clauses

The final ToS must include these concepts in customer-facing prose:

**Guarantee Refund.** "Customer may request the Guarantee Refund within 30 days after the Walkthrough Date by written notice stating dissatisfaction. OPS will not require Customer to prove a defect or allow OPS a cure period. The guarantee is unavailable after a chargeback, fraud, material misrepresentation, prohibited workflow, material breach, or continued use after refund. The guarantee clock is tolled while modules are disabled for non-payment. Valid guarantee requests are processed within 7 business days."

**Limitation of liability.** "Except for Excluded Claims, during the Guarantee Period Customer's sole and exclusive remedy for dissatisfaction with the SPEC engagement is the Guarantee Refund. Excluded Claims means fraud, willful misconduct, gross negligence, breach of confidentiality, breach of privacy or security obligations, and OPS's express IP indemnity obligations. After the Guarantee Period, OPS's aggregate liability for non-Excluded Claims is capped at SPEC fees paid in the 12 months before the claim, less refunds."

**IP and license.** "OPS owns all code, configurations, designs, templates, and reusable know-how created for SPEC. Customer owns its business data. While Customer maintains an active OPS subscription and is not in breach, OPS grants Customer a limited, non-exclusive, non-transferable license to use the delivered modules inside OPS. The license ends when the OPS subscription ends or the engagement is refunded."

### Section structure

**1. Preamble + definitions** — Parties (OPS Ltd. + Customer), "Engagement", "Package Tier", "Milestones", "Custom Modules", "Scope Document", "Acceptance Event", "Support Window", "Retainer", "Walkthrough Date".

**2. Engagement scope** — What SPEC is, what tiers exist, what's included per tier (cross-references published pricing on `/spec`). Multi-engagement clause: Customer may run multiple SPEC engagements over time; each is governed independently by its own scope document.

**3. Eligibility + geographic scope**
- Service available in Canada excluding Quebec.
- Customer is not eligible if it has a Quebec billing address, Quebec head office, Quebec operating address, Quebec establishment, or material SPEC use in Quebec. The pre-payment billing-province block is mandatory, but billing address is not the only eligibility rule.
- Customer warrants it has authority to enter this agreement on behalf of any business entity it represents.
- Misrepresenting Quebec eligibility is a material breach and makes the Guarantee Refund unavailable.

**4. Acceptable use + prohibited use**
- Acceptable use: business operations consistent with Customer's trade.
- Prohibited use: SPEC will not build workflows requiring HIPAA / PHIPA-grade health-data processing, PCI raw card capture, regulated credit decisions (FCRA equivalents), unlawful surveillance, or CASL-violating bulk-messaging automation.
- Customer warrants its proposed workflow does not require any prohibited category. Misrepresentation is a material breach.
- OPS may decline an engagement at any point during discovery if a prohibited workflow surfaces; pre-discovery refunds proceed per the refund policy.

**5. Payment terms** — 25/25/25/25 milestone structure with specific triggers:
- P1 (deposit) at click-to-book via the approved Stripe payment flow
- P2 (scope sign-off) when the scope document is countersigned (a `spec_acceptance_events` row with `event_type = 'scope_signoff'` exists)
- P3 (midpoint demo) when Customer accepts the midpoint deliverable
- P4 (delivery) when modules are deployed AND the live walkthrough is completed AND the `walkthrough_completed_at` timestamp is recorded
- Net-15 invoicing
- CAD only
- Stripe Tax handles GST/HST/PST
- Non-payment: modules disabled after 7 calendar days past the net-15 due date

**6. Scope, change orders, and pricing**
- Scope is locked at the countersigned scope document (P2 milestone trigger).
- Minor changes (< ~4 hours) billed at $225/hr CAD after pre-approval, bucketed to nearest 30 minutes.
- Major changes (≥ ~4 hours) require a fixed-price quote + Customer acceptance, kick off as a separate `change order`.
- Pre-scope tier upgrades pro-rated; post-scope upgrades quoted case-by-case.
- OPS determines the estimate and the classification using the signed scope and the acceptance criteria. Customer's option is accept or decline; estimates are not negotiable.

**7. Acceptance & quality**
- Per-feature acceptance criteria in the signed scope document are the objective bar.
- Passing criteria = scope met = invoice fires.
- Customer satisfaction survey (1-5 per feature) is non-binding feedback.
- OPS may include polish hours at its discretion (2 / 4 / 8 by tier).

**8. Delivery & 30-day Guarantee Refund**
- Delivery = modules deployed + live walkthrough completed + recording sent.
- Customer may request the Guarantee Refund within 30 days after the Walkthrough Date by written notice stating dissatisfaction.
- OPS will not require Customer to prove a defect or allow OPS a cure period.
- Because milestones are invoiced on net-15 terms and some may be unpaid at refund time, OPS's refund obligation is fulfilled by, for each milestone: (i) refunding all captured charges to the original payment method, (ii) voiding all open unpaid invoices, (iii) issuing credit notes for the unpaid portion of any partially paid invoice and refunding the paid portion, and (iv) marking uncollectible any open invoice that cannot be voided. The aggregate effect is to leave Customer owing nothing for the refunded engagement and to leave OPS with no further collection rights for that engagement. Each per-milestone action is recorded by OPS in the refund-breakdown record associated with the request.
- Valid guarantee requests are processed within 7 business days.
- Modules disabled on refund (entitlements feature-flagged off in the platform).
- Base OPS subscription unaffected.
- Anti-abuse limits:
  - One invocation per SPEC engagement.
  - The guarantee is unavailable after a chargeback, fraud, material misrepresentation, prohibited workflow, material breach, or continued use after refund.
  - The guarantee clock is tolled while modules are disabled for non-payment.
  - Upon refund issuance, Customer agrees to cease use of the modules and the disabled feature flags. Continued workaround use after refund is a breach.

**9. Support window**
- 30 / 60 / 90 days by tier
- Anchors on the walkthrough date
- Critical/high bugs in scope: free
- Cosmetic / enhancement: billable change order
- After the support window, ordinary bugs and enhancements can be billable unless covered by retainer or a still-active accepted support obligation.
- OPS does not disclaim duties for security/privacy obligations, confidentiality, willful misconduct, gross negligence, or defects covered by a still-active express warranty or accepted support obligation.

**10. Maintenance retainer**
- Opt-in only
- Monthly Stripe subscription
- Covers bug fixes + minor enhancements + platform-update compat patches
- New features = change orders
- Retainer offers are commercial electronic messages and must include sender identity, mailing/contact information, unsubscribe, and the consent basis.

**11. Subscription terms**
- SPEC subscription premium = base OPS subscription × multiplier, locked at scope sign-off (estimates 15% / 30% / 50%)
- Optional module-specific surcharge if infra-heavy (disclosed pre-scope-signoff)
- Billing starts on Customer's first billing cycle after walkthrough date + 30 days
- Annual subscribers prorate: multiplier and surcharge apply to remaining annual period as a one-time line item; full multiplier applies from the next annual renewal
- Lapse = modules disabled, code retained

**12. IP ownership**
- OPS owns all code, configurations, designs, templates, and reusable know-how created for SPEC
- Customer owns its business data
- While Customer maintains an active OPS subscription and is not in breach, OPS grants Customer a limited, non-exclusive, non-transferable license to use the delivered modules inside OPS
- The license ends when the OPS subscription ends or the engagement is refunded
- OPS may reuse anonymized patterns and reusable know-how, never Customer business data

**13. Confidentiality**
- Mutual NDA built in
- Survives 3 years post-termination

**14. Limitation of liability (revised)**
- Except for Excluded Claims, during the Guarantee Period Customer's sole and exclusive remedy for dissatisfaction with the SPEC engagement is the Guarantee Refund.
- Excluded Claims means fraud, willful misconduct, gross negligence, breach of confidentiality, breach of privacy or security obligations, and OPS's express IP indemnity obligations.
- After the Guarantee Period, OPS's aggregate liability for non-Excluded Claims is capped at SPEC fees paid in the 12 months before the claim, less refunds.
- Excluded Claims sit outside the cap during and after the Guarantee Period.
- Consequential, incidental, indirect, special, punitive, or exemplary damages excluded — lost profits, lost revenue, lost data, lost opportunity, business interruption.

**15. Indemnification**
- Customer indemnifies OPS against third-party claims arising from Customer's use of the software, Customer's data, Customer's employees, or Customer's clients
- OPS provides the express IP indemnity obligations stated in the final SPEC Terms; those obligations are Excluded Claims and sit outside the non-Excluded Claim cap

**16. Privacy + data processing**
- Customer data handled per the Privacy Policy at `/legal?page=privacy` (incorporated by reference).
- Data processing governed by the DPA at `/legal?page=dpa` (incorporated by reference).
- The Privacy Policy is updated in Phase 1 to cover SPEC-specific data: intake responses, file uploads to Supabase Storage, scope document content, satisfaction survey responses, communications log.

**17. Subprocessors**
- Stripe, Inc. (payment processing)
- Supabase, Inc. (data storage)
- SendGrid (Twilio, Inc.) (transactional email)
- Vercel, Inc. (hosting)
- Customer authorizes OPS's use of these subprocessors by accepting this ToS. OPS may update the subprocessor list with 30 days' notice by email and via the OPS-Web in-app notification rail. Objection may be raised in writing.

**18. Security practices**
- Data encrypted in transit (TLS 1.2+) and at rest (Supabase managed encryption)
- Access to production systems gated by OPS staff with appropriate role + permission
- Backups retained per Supabase project defaults
- Security incidents communicated to Customer per applicable law (BC PIPA, federal PIPEDA)

**19. Warranty disclaimer**
- The Service is provided "as is" without warranties of merchantability, fitness for a particular purpose, non-infringement, or uninterrupted service, except as expressly stated in this ToS (acceptance criteria + 30-day guarantee).

**20. Termination**
- Customer may cancel anytime (refund per the refund policy in §22)
- OPS may terminate for non-payment (after the 7-day grace) or breach of this ToS
- No-show policy: 3rd no-show = engagement cancelled + deposit forfeited
- On termination, modules disabled but code retained; data export available on request

**21. Off-boarding + data retention**
- Customer business data exported on request (CSV/JSON) within 30 days of request
- Module code stays with OPS per the IP clause
- Customer data retained for 90 days post-termination unless legally required to retain longer; thereafter deleted on request

**22. Refund policy (summary; full matrix governs)**
- Pre-discovery: typically full deposit refund (OPS's discretion)
- Post-discovery, pre-scope-signoff: pro-rated
- Post-scope-signoff, pre-delivery: pro-rated
- Within 30 days post-walkthrough: Guarantee Refund on Customer's written request stating dissatisfaction; no defect proof and no cure period
- After 30 days post-walkthrough: build fees non-refundable; goodwill refunds at OPS's discretion
- Refund mechanics (per §8): each milestone is acted on by Stripe refund, Stripe void, Stripe credit note, or Stripe mark-uncollectible, depending on the milestone's payment state at refund time. The combined effect leaves Customer with no further obligation for the refunded engagement.
- All refunds are manual, customer-initiated. No automated refunds.

**23. Non-solicitation (mild)**
- For 12 months following termination, Customer agrees not to directly solicit any OPS staff for employment. Does not restrict general public advertising or unsolicited applications.

**24. Audit rights**
- No customer-driven financial, code, or system audits are included by default.
- OPS may provide reasonable privacy/security documentation, the current subprocessor list, and DPA-related information needed for Customer's procurement or compliance review.
- Customer may engage OPS for an optional enterprise paid audit engagement at standard hourly rates, subject to scope, confidentiality, security, and scheduling limits.

**25. Feedback**
- Any feedback, suggestions, or ideas Customer provides regarding OPS or the Service may be used by OPS without restriction or compensation.

**26. Assignment**
- Customer may not assign this agreement without OPS's prior written consent.
- OPS may assign this agreement, in whole or in part, in connection with a merger, acquisition, reorganization, or sale of all or substantially all of its assets.

**27. Governing law + dispute resolution**
- British Columbia, Canada
- Disputes ≤ $35,000 CAD → BC Small Claims Court, Vancouver
- Disputes > $35,000 → BC Supreme Court, Vancouver
- No mandatory arbitration

**28. Order of precedence**
- In the event of conflict between documents, the order of precedence is:
  1. This ToS (`/legal?page=spec-terms`)
  2. The signed Scope Document (current version per `spec_scope_documents`)
  3. Other written communications (email, in-app messages)
- A change order accepted via a `spec_acceptance_events` row amends only the scope it explicitly modifies; this ToS continues to govern all other matters.

**29. Boilerplate**
- Force majeure
- Notice (email = valid notice; to OPS at jackson@opsapp.co; to Customer at the email on file in the approved Stripe payment flow)
- Amendment: OPS may update this ToS with 30 days' notice by email and via the OPS-Web in-app notification rail for existing engagements; new engagements are bound by the then-current ToS. **Carve-out for active engagements:** amendments to material terms — pricing, scope, IP ownership, refund mechanics, limitation of liability — do not apply to engagements where a scope document has been countersigned prior to the amendment effective date, except with the Customer's affirmative written acceptance of the amendment. Non-material amendments (clarifications, formatting, subprocessor list additions with no change in data-handling category) apply automatically after the 30-day notice.
- Severability
- Entire agreement (this ToS + the Scope Document + accepted change orders)
- No-waiver

### Implementation

- File: `ops-site/src/lib/legal-content.ts` registers `legalDocuments['spec-terms']` with the section content.
- `src/app/legal/page.tsx` extends `VALID_TABS` to include `spec-terms`.
- Build-time hash captured into a constant (`SPEC_TERMS_VERSION_HASH`) exported alongside the content, used in the approved Stripe payment flow as the accepted version.
- New version = new commit = new hash = new `tos_version_accepted` value for future customers.
- Customers can always retrieve their accepted version via the timestamp + hash in their `spec_projects` row.

### Pre-launch requirement

Final customer-facing ToS / Privacy / DPA prose must exist before any automated live SPEC deposits. Counsel review by Jackson's BC business counsel is recommended risk mitigation, not a hard blocker per Jackson's owner decision. Open item and bug_report tracking lives in [07_ROLLOUT.md](07_ROLLOUT.md).

---

## Email triggers (customer-facing)

All emails route through OPS-Web's existing SendGrid + `email_campaigns` / `email_jobs` infrastructure, using `email_template_versions` build-time hash check. Suppressions, pause state, and event tracking work automatically.

Subject lines follow OPS voice: UPPERCASE for authority, terse, tactical. Pass every subject + body draft through the `ops-copywriter` skill before shipping.

CASL handling:
- Transactional/service emails remain required operational notices: receipts, owner approval, deposit confirmation, intake reminders, invoices, refund processing, dispute notices, support-window notices, and security/service notices.
- Retainer offers, referral promotions, ToS-update messages with promotional content, and other upsell/promotional emails are commercial electronic messages. They need sender identity, mailing/contact information, unsubscribe mechanism, and a documented consent basis.
- Referral program is link-based. OPS does not email referred third-party prospects until they submit a form, start checkout, or otherwise expressly opt in.

| Template | Fires when | Subject example | Contents |
|---|---|---|---|
| `spec.owner_approval_required` | Buyer ≠ account_holder, on deposit click (no Stripe yet) | `SPEC APPROVAL REQUESTED` | "[Buyer] wants to purchase SPEC [tier] for [Company]. Review + approve to allow payment." |
| `spec.owner_approval_granted` | Account_holder approves | `SPEC APPROVED — COMPLETE PAYMENT` | "Approval received. Complete payment within 24 hours: [checkout link]" |
| `spec.owner_approval_declined` | Account_holder declines | `SPEC PURCHASE DECLINED` | "Your purchase was not approved. No charge was made. Contact your account holder for details." |
| `spec.deposit_confirmed` | Approved Stripe payment success webhook for SPEC deposit | `SPEC DEPOSIT RECEIVED` | Receipt, intake link, "what happens next" timeline, founder welcome video link |
| `spec.intake_reminder_1` | Day 14 post-deposit, no intake | `SPEC INTAKE WAITING` | Soft nudge: "Your intake is waiting. Tap here to start." |
| `spec.intake_reminder_2` | Day 30 post-deposit, no intake | `SPEC PAUSED` | "Project paused. Reply when ready." |
| `spec.intake_reminder_3` | Day 60 post-deposit, no intake | `SPEC — FINAL CHECK-IN` | "We'll stop reaching out. Reply anytime to pick up." |
| `spec.intake_completed_customer` | Intake form submitted | `INTAKE RECEIVED — BOOK DISCOVERY` | Confirmation + next steps (Calendly book) |
| `spec.intake_completed_no_discovery_1` | Day 7 post-intake, no discovery | `BOOK YOUR DISCOVERY SESSION` | Nudge |
| `spec.intake_completed_no_discovery_2` | Day 21 post-intake | `SPEC PAUSED` | Status update: stalled |
| `spec.intake_completed_no_discovery_3` | Day 60 post-intake | `SPEC — FINAL CHECK-IN` | Final nudge |
| `spec.discovery_no_show_1` | First discovery no-show | `MISSED DISCOVERY — RESCHEDULE` | "Reschedule here." |
| `spec.discovery_no_show_2` | Second no-show | `$100 RESCHEDULE FEE` | "Pay here to continue." |
| `spec.discovery_no_show_3` | Third no-show | `ENGAGEMENT CANCELLED` | "Deposit forfeited per terms." |
| `spec.scope_doc_ready` | Scope doc drafted, sent for signature | `SCOPE READY FOR SIGN-OFF` | DocuSign / in-app accept link + summary of scope |
| `spec.scope_doc_signed_customer` | Customer countersigns | `SCOPE LOCKED — P2 INCOMING` | "Build kicks off [date]. P2 invoice incoming." |
| `spec.p2_invoice` | P2 invoice fired (Stripe) | `P2 INVOICE — $X` | Stripe invoice link |
| `spec.midpoint_demo_scheduled` | Demo booked | `MIDPOINT DEMO — [DATE]` | Calendar invite + agenda preview |
| `spec.midpoint_accept_request` | Demo done, awaiting accept | `MIDPOINT — ACCEPT TO PROCEED` | One-click accept + satisfaction survey link |
| `spec.p3_invoice` | P3 invoice fired | `P3 INVOICE — $X` | Stripe invoice link |
| `spec.delivery_walkthrough_scheduled` | Walkthrough booked | `WALKTHROUGH — [DATE]` | Calendar invite + what to expect |
| `spec.p4_invoice` | P4 invoice fired (post-walkthrough) | `P4 INVOICE — $X` | Stripe invoice + 30-day guarantee reminder |
| `spec.support_window_open` | Day after walkthrough | `SUPPORT WINDOW OPEN` | Support window started; how to file tickets; guarantee anchor date |
| `spec.support_ending_7d` | 7 days before support window ends | `SUPPORT ENDING IN 7 DAYS` | Retainer offer preview |
| `spec.support_ending_0d` | Day support window ends | `RETAINER OFFER` | Retainer enrollment link; treated as a commercial electronic message with identity, contact/mailing info, unsubscribe, and consent basis |
| `spec.support_ending_14d_after` | 14 days post-support-end with no retainer | `FINAL RETAINER OFFER` | Last reminder; same CASL footer and consent-basis requirements |
| `spec.retainer_active` | Retainer Stripe subscription activates | `RETAINER ACTIVE` | "Your retainer is active. SPEC work now uses the response window in your agreement. Here's how to file tickets." |
| `spec.retainer_cancelled` | Customer cancels retainer | `RETAINER CANCELLED` | Confirmation + reminder that future work is ad-hoc billable |
| `spec.refund_processed` | Refund completed | `REFUND PROCESSED` | Confirmation, timeline ("funds land in 5-7 business days"), feedback request |
| `spec.refund_denied` | Refund request denied | `REFUND REQUEST DENIED` | Reason text + appeal path |
| `spec.referrer_bounty_paid` | Day 30 post-walkthrough with no refund | `REFERRAL BOUNTY PAID — $500` | Stripe Connect payout confirmation |
| `spec.referrer_kyc_required` | Referral eligible but Stripe Connect not verified | `REFERRAL — VERIFY TO RECEIVE PAYOUT` | Stripe Connect Express onboarding link |
| `spec.platform_sunset_notice` | Platform feature sunset affecting customer's module | `PLATFORM SUNSET — 90 DAYS NOTICE` | 90-day notice + retainer offer + scope of rebuild |
| `spec.tos_update_notice` | OPS amends ToS (30 days advance) | `TERMS UPDATED — REVIEW` | What changed + link to new version + effective date |

## Internal events and OPS notification channel

`SPEC-NOTIFICATION-RAIL-DEPRECATED` resolved 2026-05-25: the rail is confirmed active. Customer operational notices use email (primary) + an in-app row in `public.notifications` (secondary). Operator workflow events use a `public.notifications` row keyed to `OPS_OPERATIONS_COMPANY_ID` (which renders in the admin TODAY queue at `/admin/spec` AND in the OPS-Web edge-tab `NotificationsDrawer`), plus email for high-urgency events. See 07_ROLLOUT.md § Gate resolutions for the full per-event channel table.

Internal events insert into the existing `public.notifications` table (`user_id text NOT NULL`, `company_id text NOT NULL`, `type text NOT NULL`, `title text NOT NULL`, `body text NOT NULL`, `persistent boolean DEFAULT false`, `action_url text`, `action_label text`). `action_url` is `/admin/spec/{spec_project_id}` for operator rows and `/account/spec/{spec_project_id}/request-refund` (Phase 1) or `/account/spec/{spec_project_id}` (Phase 2) for customer rows. `action_label` is `'OPEN'` by default. Persistent vs standard based on urgency.

**`company_id` routing rules (locked per resolved `SPEC-NOTIFICATION-RAIL-DEPRECATED` and `SPEC-NO-COMPANY-BUYER-FLOW-LOCK`):**

- **Operator-facing events** (to Jackson or any SPEC operator): `company_id = OPS_OPERATIONS_COMPANY_ID` (the internal company seeded by the Phase 1 migration). Recipients are members of OPS Operations and see these in the admin TODAY queue AND the OPS-Web in-app notification rail.
- **Customer-facing notifications** to a buyer or account_holder: `company_id = linked_company_id`. Per resolved `SPEC-NO-COMPANY-BUYER-FLOW-LOCK`, `linked_company_id` is guaranteed non-null on every `spec_projects` row (the deposit gate requires the buyer to have a company first, via the existing `/setup` flow). The no-company case is eliminated.

| Event | Persistent? | Content |
|---|---|---|
| Owner approval requested | Yes | "Approve [Buyer]'s SPEC purchase for [Company]." |
| New SPEC deposit | Yes | "[Buyer] paid $X for SPEC [tier]." |
| Owner declined approval | Standard | "[Account_holder] declined [Buyer]'s SPEC purchase." |
| Buyer checkout token expiring | Standard | "[Buyer]'s checkout token expires in 4 hours." |
| Intake completed | Yes (until acknowledged) | "[Customer] completed intake. Review + schedule discovery." |
| Customer responded to email | Standard | "[Customer] replied to [thread]." |
| Discovery scheduled | Standard | "Discovery with [Customer] booked for [date]." |
| Scope doc signed by customer | Yes | "Scope signed by [Customer]. Fire P2 invoice when ready." |
| Customer accepted midpoint | Yes | "Midpoint accepted. Fire P3 invoice when ready." |
| Customer rated feature ≤ 2 at delivery | Yes | "Low rating on [feature]. Review needed." |
| Refund requested | Yes | "Refund request from [Customer] — $X." |
| Refund denied (auto-eligibility failure) | Standard | "[Customer]'s refund auto-failed eligibility: [reason]." |
| Stripe dispute opened | Yes | "Stripe dispute from [Customer]. Evidence package needed within 7 days." |
| 7-day communication cadence missed | Standard | "Reminder: send weekly update to [Customer]." |
| On_hold (customer_requested) approaching 90d | Standard | "[Customer] paused 80 days. Reach out before auto-stall." |
| On_hold (ops_blocked) > 14 days | Standard | "[Customer] OPS-blocked 14 days. Decide: convert to customer_requested or escalate." |
| Customer past 30d unresponsive | Standard | "[Customer] not responsive. Project flipped to stalled." |
| Referral became eligible | Standard | "Referral bounty eligible for [Referrer email] — $500." |
| Referral KYC outstanding | Standard | "Referrer [email] has not completed Stripe Connect KYC." |
| Referral related-entity flag | Yes | "Referral [Referrer email] flagged as related entity — manual review." |
| Regulated workflow attestation flagged | Yes | "[Customer] flagged a regulated workflow at intake. Review before discovery." |

## Cron jobs

Daily at 9am Vancouver time (Vercel cron):

- Check `spec_projects` for nudge thresholds (14d / 30d / 60d / 90d) and fire appropriate emails
- Check `on_hold` projects with `hold_type = 'customer_requested'` approaching 90d expiry → notify customer + Jackson; flip to `stalled_on_hold` at expiry
- Check `on_hold` projects with `hold_type = 'ops_blocked'` > 14 days → notify Jackson to decide
- Check active builds (status = `building`) with `last_communication_at` > 7d → notify Jackson
- Check `spec_referrals` reaching eligibility (30d post-`walkthrough_completed_at` with no refund) → flip status to `eligible` (or `kyc_required` / `review` / `held` per rules), notify Jackson
- Check `spec_payments` overdue (due_date + 7d past) → email customer reminder + notify Jackson; at +7d, flip relevant `spec_module_entitlements.enabled = false` with `disabled_reason = 'non_payment'`
- Check `spec_projects` at 60d unresponsive → flip status to `stalled` (no auto-refund per Category 10 of [01_BUSINESS_MODEL.md](01_BUSINESS_MODEL.md))
- Check `spec_owner_approval_requests` past 7d in `pending` → flip to `expired`, parent project to `cancelled` if no other path forward, notify all parties
- Check buyer `checkout_token_expires_at` within 4h → notify buyer (one-shot reminder)
- Conversion-tracking outbox flush — retry any failed Meta CAPI / Google Enhanced sends from the last 24h

---

## Implementation status (2026-05-26)

The final customer-facing SPEC legal prose drafted in Stage G ([06A_SPEC_TOS_PROSE.md](06A_SPEC_TOS_PROSE.md), [06B_SPEC_PRIVACY_ADDITIONS.md](06B_SPEC_PRIVACY_ADDITIONS.md), [06C_SPEC_DPA_NOTES.md](06C_SPEC_DPA_NOTES.md)) has been ported into the live ops-site `/legal` route at commit `61acc9a` on branch `feat/spec-legal-content` (chip `SPEC - P1-2-5`).

Routes affected:

- `/legal?page=spec-terms` — new tab; 31 sections; all three locked verbatim clauses (Guarantee Refund / Limitation of Liability / IP and License) reproduced verbatim. `lastUpdated: 2026-05-25`, `effectiveDate: 2026-06-01` (placeholder — set to actual go-live date when published), `version: v1.0`.
- `/legal?page=privacy` — bumped to v1.1, `lastUpdated: 2026-05-25`. § 2.9 (SPEC Engagement Data), § 3 purpose-table additions, § 4 processor additions (SendGrid, Vercel, Meta CAPI, Google Ads, Calendly/Cal.com — Calendly vs Cal.com decision still flagged inline), § 8 retention additions (7-year CRA anchor), § 11 SPEC commercial-message paragraph all live.
- `/legal?page=dpa` — bumped to v1.1, `lastUpdated: 2026-05-25`, `effectiveDate: 2026-06-01` (placeholder). Section 3 (Nature and Purpose) table revised with base-vs-SPEC split. Section 4.4 SPEC subprocessor clarifying sentence appended. Section 4.7 7-year CRA carve-out appended. Annex A expanded with 5 new SPEC subprocessor rows plus Stripe + Supabase scope expansions. New Annex B (SPEC Schedule, B.1–B.9) appended after Annex A.
- `src/lib/spec/tos-version.ts` (new) — exports `SPEC_TERMS_VERSION_HASH` (sha256 of the SPEC ToS canonical string, computed at module-evaluate time). Stage C.1 (`/api/spec/create-checkout-session`) imports this constant and stamps it on `checkout.session.metadata.tos_version_hash`. Build-time pinned; no async, no env lookups.

Pre-launch operational task remaining (Jackson, in the Stripe console — not a code task): set the Stripe Dashboard **Customer emails → Terms of Service URL** to `https://opsapp.co/legal?page=spec-terms` before live SPEC deposits flip on. The `consent_collection.terms_of_service='required'` flag on the Checkout Session reads from that Dashboard URL.

Open content decision still flagged inline in `/legal?page=privacy` and `/legal?page=dpa` Annex A: Calendly vs Cal.com (or both) — pick one and update both legal docs plus Stage G source files before publishing.
