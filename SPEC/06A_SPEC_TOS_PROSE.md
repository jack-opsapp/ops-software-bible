# SPEC Engagement Terms of Service — Final Customer-Facing Prose (2026-05-25)

This file is the production-ready Terms of Service prose for SPEC engagements. A follow-up implementation chip ports this content into `ops-site/src/lib/legal-content.ts` under `legalDocuments['spec-terms']` and registers `spec-terms` in `VALID_TABS` at `ops-site/src/app/legal/page.tsx`. Acceptance happens in the SPEC Stripe Checkout flow via `consent_collection.terms_of_service='required'`; the build-time `SPEC_TERMS_VERSION_HASH` is captured into `spec_projects.tos_version_accepted` and into a `spec_acceptance_events` row with `event_type='tos_accepted'`.

Review status: Jackson-reviewed (founder review). Counsel review by BC business counsel is recommended risk mitigation per [07_ROLLOUT.md](07_ROLLOUT.md) § Phase 1 Legal but is not a hard launch blocker. Mandatory verbatim clauses from [07_ROLLOUT.md](07_ROLLOUT.md) § 2 are embedded in Sections 9, 15, and 19 below — those sentences are inviolable and must port verbatim into `legal-content.ts`.

Section IDs in the heading anchors (`agreement`, `definitions`, etc.) map directly to the kebab-case `id` field on each `LegalSection` when porting.

---

## Front matter (for `legal-content.ts`)

```
title: 'SPEC Engagement Terms of Service'
lastUpdated: '2026-05-25'
effectiveDate: '2026-06-01'   // set to the actual go-live date when the prose ships
```

---

## 1. Agreement {#agreement}

These SPEC Engagement Terms of Service (the "SPEC Terms") form a binding agreement between 1361513 BC LTD. ("OPS," "we," "us"), a British Columbia company at 303-1121 Oscar Street, Victoria BC V8V2X3, and the business or individual purchasing a SPEC engagement ("Customer," "you").

The SPEC Terms apply only to your purchase and use of one or more SPEC engagements. They sit alongside the base OPS Terms of Service at /legal?page=terms (which governs your underlying OPS subscription), the OPS Privacy Policy at /legal?page=privacy, and the OPS Data Processing Agreement at /legal?page=dpa. Each is incorporated by reference. Where the SPEC Terms conflict with the base OPS Terms of Service with respect to a SPEC engagement, the SPEC Terms govern that engagement.

By clicking "I agree to the SPEC Terms of Service" in the SPEC checkout flow and completing payment, you accept the SPEC Terms in the version published at the time of acceptance. The accepted version is captured as a build-time commit hash and stored alongside your engagement record. Future changes to the SPEC Terms do not apply retroactively to engagements with a counter-signed Scope Document — see Section 27 (Amendments) and Section 23 (Version Pinning).

If you are accepting on behalf of a company, you represent that you have authority to bind that company. For SPEC engagements where the buyer is not the account holder of the OPS company, the account holder's electronic approval at the Owner Approval Step is recorded as a separate binding acceptance event before any payment session is created — see Section 6 (Payment Terms).

## 2. Definitions {#definitions}

The following terms have the meanings given below when capitalized in the SPEC Terms.

- "Acceptance Event" — an electronic acceptance action recorded by OPS in its acceptance log, including the accepting user's identifier, IP address, user agent, signature method, and a content hash of the accepted document. Acceptance Events include ToS acceptance, owner purchase approval, scope sign-off, midpoint acceptance, delivery acceptance, and change order acceptance.

- "Change Order" — a written addition or modification to the Scope Document, accepted as an Acceptance Event under Section 7.

- "Custom Modules" or "Modules" — the configurations, integrations, custom data fields, custom pipeline stages, custom user interface components, custom reports, custom data exports, and any other deliverables OPS builds for you under a SPEC engagement, deployed inside your OPS instance and gated by entitlements OPS controls.

- "Engagement" — a single SPEC purchase, identified by one engagement record. Each Engagement is governed independently by its own Scope Document and its own copy of the SPEC Terms (the version accepted at the Engagement's deposit).

- "Excluded Claims" — fraud, willful misconduct, gross negligence, breach of confidentiality, breach of privacy or security obligations, and OPS's express IP indemnity obligations.

- "Guarantee Period" — the 30-day period beginning on the Walkthrough Date.

- "Guarantee Refund" — the customer-initiated refund described in Section 9 (Delivery and 30-Day Guarantee Refund).

- "Milestones" — the four payment milestones P1 (Deposit), P2 (Scope Sign-Off), P3 (Midpoint Demo), and P4 (Delivery), described in Section 6.

- "Owner Approval Step" — the workflow described in Section 6 for engagements where the buyer is not the OPS account holder. The account holder's approval is recorded as a binding "owner_purchase_approved" Acceptance Event.

- "Package Tier" — the SPEC tier you purchase (Setup, Build, or Enterprise), as published on the SPEC marketing page at /spec.

- "Retainer" — the optional monthly maintenance subscription described in Section 11.

- "Scope Document" — the versioned written statement of work for an Engagement, including the feature list, per-feature acceptance criteria, midpoint deliverable definition, delivery deliverable definition, explicit exclusions, estimated delivery window, locked SPEC subscription multiplier, locked module surcharge (if any), and a reference to the active version of the SPEC Terms. Each Scope Document is identified by a content hash. Counter-signature is recorded as a "scope_signoff" Acceptance Event.

- "Support Window" — the post-delivery support period described in Section 10. Setup tier: 30 days. Build tier: 60 days. Enterprise tier: 90 days. The Support Window anchors on the Walkthrough Date.

- "Walkthrough Date" — the calendar date on which OPS holds the live delivery walkthrough call with you, recorded as `walkthrough_completed_at` on your engagement record. The Walkthrough Date is the single anchor for the Guarantee Period, the Support Window, the Retainer offer window, and the SPEC subscription premium billing-start date.

Capitalized terms not defined here have the meanings given to them in the body of these SPEC Terms or in the Scope Document.

## 3. The SPEC Engagement {#the-spec-engagement}

SPEC is OPS's custom software service for trade businesses. Through a SPEC Engagement, OPS designs, builds, and deploys Custom Modules inside your OPS instance to match how your business operates. SPEC is not a separate product — it is a service that extends the OPS platform you subscribe to.

Each SPEC purchase is a single Engagement. You may run multiple Engagements simultaneously or sequentially. Each Engagement has its own Scope Document, its own Milestones, its own Guarantee Period, and its own Custom Module entitlement set inside your OPS instance.

The published Package Tiers and the deliverables expected for each tier are described on the SPEC marketing page at /spec. The Scope Document is the binding statement of what is included for your specific Engagement — if the Scope Document and the marketing page disagree, the Scope Document governs that Engagement.

OPS may update Package Tier pricing, feature lists, and tier definitions on /spec for future Engagements. Pricing and scope for an Engagement that has already opened are locked at deposit time and at scope sign-off respectively (see Sections 6 and 7).

## 4. Eligibility and Geographic Scope {#eligibility}

SPEC is available to businesses operating in Canada, excluding the province of Quebec.

You are not eligible to purchase a SPEC Engagement if any of the following apply to you or to the business entity on whose behalf you are purchasing:

- Your billing address is in Quebec.
- Your head office is in Quebec.
- Your primary operating address is in Quebec.
- You maintain a Quebec establishment.
- You expect material use of the Custom Modules to occur in Quebec.

OPS enforces this exclusion in three places: a pre-payment billing-province check on the OPS-collected address form, the billing address recorded by Stripe at checkout, and the attestations you complete at intake. If you misrepresent your Quebec status to evade the exclusion, the misrepresentation is a material breach of these SPEC Terms, the Guarantee Refund becomes unavailable for that Engagement, and OPS may immediately cancel the Engagement, refund the captured deposit, and add you to the SPEC blocked-buyers list.

The reason for the exclusion is the additional legal and operational complexity created by Quebec's Consumer Protection Act, French-language commercial-relations requirements, and Quebec privacy and data-localization rules under Law 25 and An Act respecting the protection of personal information in the private sector. OPS may revisit this exclusion as the business matures. Customers outside Canada are not eligible at launch; CAD is the only supported currency.

You warrant that you have authority to enter into the SPEC Terms on behalf of any business entity you represent. If you are purchasing as an individual sole proprietor, the business entity is you and your representations apply to you personally.

## 5. Acceptable and Prohibited Use {#acceptable-and-prohibited-use}

You may use SPEC and the resulting Custom Modules only to operate your own trade business in the ordinary course. SPEC is designed for owner-operated trade businesses such as residential and light-commercial construction, HVAC, plumbing, electrical, landscaping, deck and rail, painting, cleaning services, and adjacent trades.

You may not use SPEC to design, configure, or operate workflows that require any of the following:

- Processing of health information subject to HIPAA, PHIPA, or any comparable provincial or federal health-privacy regime — including any workflow that handles protected health information (PHI), patient medical records, treatment records, diagnostic data, or insurance claims involving health data.
- Raw payment card capture (PAN). Payment card data flows through Stripe; Custom Modules do not receive, store, or transit raw card numbers.
- Regulated credit decisions, including credit scoring, adverse-action notices, processing covered by FCRA-equivalent regimes, or any workflow that determines whether to extend credit to a natural person based on their personal financial data.
- Unlawful surveillance of employees or third parties, including tracking that exceeds labour-law-compliant timesheet and on-the-job location features under applicable Canadian employment and privacy law.
- Bulk messaging that violates CASL, the TCPA, or any analogous statute — including automated SMS or email sends to recipients without lawful consent, without sender identification, or without a functional unsubscribe mechanism.

You warrant that the workflow you describe at intake and during discovery does not require any of the categories above. If a prohibited workflow surfaces at any point during discovery or build, OPS may decline or terminate the Engagement; refund consequences are governed by Section 22 (Refund Mechanics). Misrepresenting the nature of your workflow is a material breach that disqualifies the Engagement from the Guarantee Refund.

OPS may decline any prospective Engagement, or terminate an active Engagement, that it determines materially conflicts with the SPEC Terms or with applicable law. Termination for prohibited workflow is governed by Section 20.

## 6. Payment Terms {#payment-terms}

SPEC Engagements are billed in four equal Milestones across all Package Tiers. The Milestone structure is locked; no Engagement is billed on any other cadence.

| Milestone | Trigger | Amount |
|---|---|---|
| P1 — Deposit | Click-to-book in the SPEC checkout flow | 25% of total |
| P2 — Scope Sign-Off | Customer counter-signs the Scope Document; recorded as a "scope_signoff" Acceptance Event | 25% of total |
| P3 — Midpoint Demo | Customer accepts the midpoint deliverable; recorded as a "midpoint_accepted" Acceptance Event | 25% of total |
| P4 — Delivery | Modules are deployed to your OPS instance, the live walkthrough is held, and `walkthrough_completed_at` is recorded | 25% of total |

P1 is paid through Stripe Checkout at deposit time. P2, P3, and P4 are issued as Stripe Invoices with net-15 payment terms.

For Engagements where the buyer is not the OPS account holder, the Owner Approval Step gates the payment session. The account holder must approve the purchase electronically before any Stripe Checkout Session is created. The approval is recorded as an "owner_purchase_approved" Acceptance Event capturing the account holder's identifier, IP, user agent, signature method, and a hash of the version of these SPEC Terms they reviewed. The buyer's later ToS acceptance at Stripe Checkout is a separate "tos_accepted" Acceptance Event. Both events are part of the Engagement's evidence chain in any dispute.

Currency is Canadian dollars (CAD) only. Stripe Tax calculates and collects GST, HST, and PST based on the billing address recorded at Stripe Checkout. QST does not apply because Quebec is excluded (Section 4). You may optionally provide a GST/HST number at checkout, which OPS attaches to your Stripe customer record so input-tax-credit-eligible invoices reflect it.

If a Milestone invoice is unpaid more than 7 calendar days past its net-15 due date, OPS may disable the affected Custom Modules in your OPS instance until the invoice is paid in full. Disablement is recorded with the reason "non_payment" and is reversed immediately on payment. The Guarantee Period clock is tolled while Modules are disabled for non-payment (Section 9).

OPS may decline to begin work on a subsequent Milestone while a prior Milestone invoice is overdue. Repeated non-payment is a material breach and may result in termination under Section 20.

## 7. Scope, Change Orders, and Pricing {#scope-and-change-orders}

The signed Scope Document is the binding statement of what OPS will build for your Engagement. The Engagement is fixed-price at the Milestone amounts shown in Section 6; there is no hours-tracking, hourly-overage billing, or "demonstrate your time" reconciliation on the core engagement. If OPS completes the Scope Document faster than estimated, the Milestone amounts do not change. If OPS takes longer than estimated (subject to Section 8 delivery-date language), OPS absorbs the additional time.

After scope sign-off you may request changes. OPS classifies each requested change into one of two categories:

- A minor change is one OPS estimates at less than approximately 4 hours of work. Minor changes are billed at $225 CAD per hour, in 30-minute increments. You pre-approve the estimate; the pre-approval is recorded as a "change_order_accepted" Acceptance Event. Minor changes are invoiced at the end of the current Milestone or at the end of the Engagement, net-15.
- A major change is one OPS estimates at 4 hours or more. Major changes are quoted as a fixed price for a defined scope. OPS provides the scope, the price, and the impact on the delivery window; you accept in writing as a "change_order_accepted" Acceptance Event. Major changes are tracked as separate Change Order records and invoiced on completion, net-15.

OPS determines the estimate and the minor-versus-major classification using the signed Scope Document and the per-feature acceptance criteria. Your option is to accept or decline the estimate; estimates are not negotiable.

Tier upgrades requested before scope sign-off are full pro-rated upgrades: you pay the difference between the new tier total and the amounts already paid, and discovery work counts toward the new tier. Tier upgrades requested after scope sign-off are case-by-case fixed-price quotes tracked as Change Orders.

## 8. Acceptance and Quality {#acceptance-and-quality}

Each feature in the Scope Document carries a written acceptance criterion. A feature is "accepted" when it meets the written criterion. Acceptance of all features required for a Milestone triggers the Milestone invoice.

After the midpoint demo and after the delivery walkthrough, OPS may invite you to rate each feature on a 1-to-5 satisfaction scale. The rating is non-binding feedback. A passing acceptance criterion triggers the Milestone invoice regardless of rating. OPS reviews 1-star and 2-star ratings against the acceptance criterion and repairs or rebuilds the feature at no charge if the criterion objectively fails. Subjective preferences with passing acceptance criteria are handled through the polish budget (described below) or through the Change Order process in Section 7.

OPS may include a discretionary post-scope polish budget on each Engagement — typically 2 hours for Setup, 4 hours for Build, and 8 hours for Enterprise. Polish hours are at OPS's sole discretion, are not billed, and may be exhausted before all subjective preferences are addressed. Once polish is exhausted, additional changes flow through the Change Order process.

Delivery dates in the Scope Document are good-faith estimates, not firm deadlines. OPS will notify you of any anticipated delay greater than 7 days within 48 hours of identifying the delay, and will provide a revised estimate. No automatic credits, refunds, or penalties apply to delivery-window slips. If a delay is unacceptable to you, you may invoke the cancellation and refund process in Section 22.

## 9. Delivery and 30-Day Guarantee Refund {#delivery-and-guarantee}

Delivery of an Engagement consists of all of the following:

- The Custom Modules are deployed to your OPS instance and the corresponding entitlements are activated.
- OPS holds a 30 to 60 minute live delivery walkthrough on a video call. The walkthrough is recorded and the recording link is stored on your engagement record.
- The `walkthrough_completed_at` timestamp is recorded on your engagement record.

P4 fires immediately on delivery. The Walkthrough Date is the calendar date on which the live walkthrough was held.

**Guarantee Refund.** Customer may request the Guarantee Refund within 30 days after the Walkthrough Date by written notice stating dissatisfaction. OPS will not require Customer to prove a defect or allow OPS a cure period. The guarantee is unavailable after a chargeback, fraud, material misrepresentation, prohibited workflow, material breach, or continued use after refund. The guarantee clock is tolled while modules are disabled for non-payment. Valid guarantee requests are processed within 7 business days.

You may submit a Guarantee Refund request through the in-app refund route at /account/spec/[id]/request-refund or by emailing jackson@opsapp.co. The request must come from the buyer or the OPS account holder.

On issuance of a Guarantee Refund:

- OPS disables the Custom Modules covered by the Engagement (entitlements set to disabled, with reason "refunded"). You agree to stop using the disabled Modules immediately. Continued workaround use of refunded Modules — including exporting Module-built data and reinserting it elsewhere in OPS — is a material breach.
- Your underlying base OPS subscription is unaffected. Only the SPEC-built Modules and the SPEC subscription premium for those Modules are removed.
- Each Milestone is settled according to the per-state mechanics in Section 22 so that you owe nothing further for the refunded Engagement.

The Guarantee Refund may be invoked once per Engagement. If you have multiple Engagements, each Engagement carries its own Guarantee Refund right. The Guarantee Refund does not extend to the base OPS subscription, to Retainer fees that have already accrued for support rendered, or to Change Order fees already billed for work delivered.

The Guarantee Refund is your sole and exclusive remedy for dissatisfaction with the SPEC Engagement during the Guarantee Period, except as provided in Sections 15, 17, 18, and 19 with respect to Excluded Claims.

## 10. Support Window {#support-window}

OPS provides a Support Window beginning on the Walkthrough Date.

| Package Tier | Support Window length |
|---|---|
| Setup | 30 days |
| Build | 60 days |
| Enterprise | 90 days |

During the Support Window:

- Critical defects (defects that break a core workflow or block daily operation) are repaired at no charge regardless of cause. OPS targets same-business-day response and 48-hour resolution.
- High-severity defects (defects that degrade but do not block) are repaired at no charge if the defect violates an acceptance criterion in the Scope Document. OPS targets 3-business-day resolution.
- Cosmetic and enhancement requests are billable Change Orders under Section 7.

After the Support Window closes, ordinary bugs and enhancement requests are billable unless covered by an active Retainer or by a still-active accepted support obligation. OPS does not disclaim its duties for security obligations, privacy obligations, confidentiality obligations, willful misconduct, gross negligence, or defects covered by a still-active express warranty or an accepted support obligation.

OPS targets but does not guarantee specific response or resolution times for tickets filed during the Support Window. Targets are good-faith service levels, not contractual commitments backed by credits.

## 11. Maintenance Retainer {#maintenance-retainer}

The Retainer is an opt-in monthly subscription you may purchase as the Support Window approaches its close. Retainer enrollment is never silent — you must affirmatively subscribe through a Stripe-hosted subscription link.

| Package Tier | Retainer | Coverage |
|---|---|---|
| Setup | $250 CAD per month | Bug fixes, minor enhancements within the original scope, and OPS platform-update compatibility patches |
| Build | $450 CAD per month | Same as Setup, applied to the Custom Module |
| Enterprise | $750 CAD per month | Same as Setup, applied to all delivered Modules under the Engagement |

The Retainer does not cover new features, scope expansions, third-party integrations, or module rewrites — those flow through the Change Order process. There is no formal hour cap on the Retainer; OPS may propose a tier change or a transition to billable Change Orders if usage materially exceeds normal patterns (for example, more than ten hours per month on a Build Retainer or more than twenty hours per month on an Enterprise Retainer).

Retainer cancellations take effect at the end of the current billing period. There is no proration on cancellation, and the Retainer does not bank unused hours into future months.

Retainer-offer emails sent at or near the close of the Support Window are commercial electronic messages under CASL and comply with the requirements in Section 24.

## 12. SPEC Subscription Premium {#subscription-premium}

Each SPEC Engagement adds a SPEC subscription premium to your base OPS subscription. The published estimate is +15% (Setup), +30% (Build), and +50% (Enterprise) of your base OPS subscription. The actual premium for an Engagement is locked in the Scope Document at scope sign-off and may differ from the published estimate based on the final feature list and the infrastructure footprint of the Custom Modules.

Premium billing begins on your first regular OPS billing cycle that occurs after the Walkthrough Date plus 30 days. The first 30 days after the Walkthrough Date are a soft post-delivery trial during which the premium is not charged. If you are on a monthly base subscription, the premium is added to your monthly invoice from the first eligible cycle. If you are on an annual base subscription, OPS prorates the premium to the remaining annual term as a one-time line item, and applies the full premium from the next annual renewal.

OPS may add a module-specific surcharge for Engagements with infrastructure-heavy Modules — for example, modules that require dedicated background processing, frequent external API calls, or significant storage. Surcharges are disclosed before scope sign-off and locked in the Scope Document.

The locked premium and surcharge for an Engagement are fixed for 12 months following the Walkthrough Date. After 12 months, OPS may propose a revised premium if actual infrastructure cost diverges materially from the locked figure. Any revised premium takes effect prospectively on your next billing cycle following 30 days' notice.

If your base OPS subscription lapses, the SPEC-built Custom Modules are disabled automatically (disabled reason "subscription_lapse"). The Module code is retained on OPS infrastructure; resuming your subscription re-enables the Modules at no charge. The license granted in Section 15 ends when the base OPS subscription ends or when the Engagement is refunded.

## 13. Confidentiality {#confidentiality}

OPS and Customer each agree to keep the other's Confidential Information confidential. "Confidential Information" means non-public information disclosed by one party to the other in connection with an Engagement, marked or reasonably understood as confidential — including business operations, customer lists, financial data, source code, configurations, internal documents, and the contents of the Scope Document.

Each party will (a) use the other's Confidential Information only to perform under these SPEC Terms; (b) protect it with at least the same degree of care it uses for its own confidential information of similar sensitivity, but in no event less than a reasonable degree of care; and (c) not disclose it to any third party except to its personnel, advisors, and subprocessors who have a need to know and who are bound by confidentiality obligations at least as protective as those in this section.

The confidentiality obligation does not apply to information that (i) is or becomes publicly available through no breach by the receiving party, (ii) the receiving party already lawfully possessed without confidentiality obligations, (iii) the receiving party independently developed without reference to the disclosing party's Confidential Information, or (iv) is rightfully received from a third party without confidentiality obligations.

Disclosure compelled by law is permitted, provided the disclosing party gives prior notice to the other party where lawful and cooperates in any reasonable effort to limit the disclosure.

Confidentiality obligations survive termination of an Engagement for three years, except that obligations regarding trade secrets continue for as long as the information remains a trade secret under applicable law.

## 14. Privacy and Data Protection {#privacy-and-data-protection}

OPS processes personal information about you, your team, and your end-clients in connection with each SPEC Engagement. The OPS Privacy Policy at /legal?page=privacy describes the data collected, the purposes of processing, the subprocessors used, the retention periods, and your rights under the Personal Information Protection and Electronic Documents Act (PIPEDA) and applicable provincial law. The Privacy Policy is incorporated into the SPEC Terms by reference.

Customer-to-OPS data processing is governed by the Data Processing Agreement at /legal?page=dpa, also incorporated by reference. The DPA covers OPS's obligations as a processor of personal data on your behalf, including the use of subprocessors, breach notification, and assistance with data-subject requests.

SPEC-specific personal data — including intake form responses, file uploads to the SPEC intake storage bucket, scope document content, satisfaction survey responses, the communications log, and attribution data — is described in the Privacy Policy and processed in accordance with the DPA. You consent to these processing activities by accepting the SPEC Terms and by authorizing your team and end-clients' data to flow through OPS for the SPEC Engagement.

Your data may be processed outside the province of British Columbia and outside Canada by OPS's subprocessors. OPS relies on contractual safeguards with each subprocessor to protect the data. The Privacy Policy lists the subprocessors and their processing locations.

If OPS becomes aware of a breach of security safeguards involving your personal information that creates a real risk of significant harm, OPS will notify you and the Office of the Privacy Commissioner of Canada as required by PIPEDA and any applicable provincial law.

## 15. Intellectual Property and License {#intellectual-property-and-license}

**IP and license.** OPS owns all code, configurations, designs, templates, and reusable know-how created for SPEC. Customer owns its business data. While Customer maintains an active OPS subscription and is not in breach, OPS grants Customer a limited, non-exclusive, non-transferable license to use the delivered modules inside OPS. The license ends when the OPS subscription ends or the engagement is refunded.

Expanding on the license grant: the license is non-sublicensable, non-assignable, restricted to your own internal business operations, and exercisable only inside the OPS platform. You may not extract, decompile, reverse-engineer, copy, or re-host the Custom Modules outside OPS. You may not white-label or resell access to the Custom Modules to third parties. You may use the operational outputs of the Custom Modules — your invoices, your customer records, your project data, your photos, your reports — freely; the license restriction applies to the Module code and configuration, not to the data the Modules produce.

OPS may reuse anonymized patterns, generic configurations, and reusable know-how learned across SPEC Engagements in future SPEC work. OPS will never reuse your business data — customer names, employee names, financials, project records, photos, or any other identifying information — in any other customer's Engagement.

OPS provides the following express IP indemnity. If a third party claims that the OPS-developed Custom Modules, as delivered, infringe the third party's intellectual property rights, OPS will defend you against the claim and indemnify you against damages awarded against you, provided that you (a) promptly notify OPS of the claim, (b) give OPS sole control of the defence and settlement, and (c) reasonably cooperate at OPS's expense. OPS's obligations under this paragraph do not apply to claims arising from (i) your modification of the Modules, (ii) your combination of the Modules with third-party software or data not provided or approved by OPS, or (iii) your use of the Modules other than as described in the Scope Document and the SPEC Terms. This IP indemnity is the express IP indemnity obligation referenced in the Excluded Claims definition and sits outside the liability cap in Section 19.

OPS may use de-identified, aggregated information about platform usage patterns derived from the Custom Modules to improve the OPS platform. Any feedback, suggestions, or ideas you provide regarding the Modules or the OPS platform may be used by OPS without restriction or compensation, subject to the confidentiality obligations in Section 13.

## 16. Customer Warranties {#customer-warranties}

You warrant to OPS that:

- You have full authority to enter into the SPEC Terms and to commit your business to the obligations they create.
- The business information you provide at intake and during discovery — including your trade, your team size, your tools, your workflow, your revenue band, your billing address, and your regulated-workflow attestations — is accurate and complete in all material respects.
- The data you provide to OPS for use in the Custom Modules was collected lawfully and may be processed by OPS on your behalf for the purposes described in the OPS Privacy Policy and the DPA.
- You have the right and consent to provide personal data about your employees and end-clients that flows into OPS, including consent required by applicable privacy and employment law regarding workplace location data, time tracking, and similar information.
- Your business and the Custom Modules will be operated in compliance with applicable law, including CASL, applicable provincial privacy law, applicable employment law, and applicable tax law.
- You are not located in Quebec, do not have a Quebec head office, do not have a Quebec primary operating address, do not maintain a Quebec establishment, and do not expect material use of the Custom Modules to occur in Quebec.
- You are not subject to a Canadian or U.S. government economic sanctions list and are not located in a jurisdiction subject to comprehensive economic sanctions.

## 17. OPS Warranties and Disclaimer {#ops-warranties}

OPS warrants that the Custom Modules will substantially conform to the acceptance criteria in the Scope Document at the time of delivery. Your exclusive remedy for breach of this warranty during the Guarantee Period is the Guarantee Refund described in Section 9. Your exclusive remedy for breach during the Support Window is repair as described in Section 10.

EXCEPT AS EXPRESSLY STATED IN THESE SPEC TERMS, THE SPEC ENGAGEMENT AND THE CUSTOM MODULES ARE PROVIDED ON AN "AS IS" AND "AS AVAILABLE" BASIS. TO THE FULLEST EXTENT PERMITTED BY APPLICABLE LAW, OPS DISCLAIMS ALL WARRANTIES, EXPRESS OR IMPLIED, INCLUDING WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE, NON-INFRINGEMENT, AND UNINTERRUPTED OR ERROR-FREE OPERATION.

Some provinces do not allow the exclusion of certain implied warranties. The above disclaimer applies only to the extent permitted by applicable law in your jurisdiction.

## 18. Indemnification {#indemnification}

You will defend, indemnify, and hold harmless OPS, its directors, officers, employees, and contractors against any third-party claim, damage, loss, liability, or expense (including reasonable legal fees) arising from or relating to:

- Your use of the OPS platform or the Custom Modules in violation of the SPEC Terms or applicable law.
- Your business data, including any claim that the data was collected, stored, or processed in violation of privacy law, intellectual property law, employment law, or contract.
- The acts or omissions of your employees, contractors, or end-clients in connection with the Custom Modules.
- Your operation of, or attempt to operate, a workflow prohibited by Section 5.
- Your misrepresentation of Quebec eligibility or any other warranty under Section 16.

OPS provides the express IP indemnity described in Section 15 against third-party claims that the Module code, as delivered, infringes a third party's intellectual property rights. That express IP indemnity is an Excluded Claim and sits outside the liability cap in Section 19.

## 19. Limitation of Liability {#limitation-of-liability}

**Limitation of liability.** Except for Excluded Claims, during the Guarantee Period Customer's sole and exclusive remedy for dissatisfaction with the SPEC engagement is the Guarantee Refund. Excluded Claims means fraud, willful misconduct, gross negligence, breach of confidentiality, breach of privacy or security obligations, and OPS's express IP indemnity obligations. After the Guarantee Period, OPS's aggregate liability for non-Excluded Claims is capped at SPEC fees paid in the 12 months before the claim, less refunds.

Excluded Claims sit outside the cap during and after the Guarantee Period. TO THE FULLEST EXTENT PERMITTED BY APPLICABLE LAW, NEITHER PARTY IS LIABLE TO THE OTHER FOR CONSEQUENTIAL, INCIDENTAL, INDIRECT, SPECIAL, PUNITIVE, OR EXEMPLARY DAMAGES — INCLUDING LOST PROFITS, LOST REVENUE, LOST DATA, LOST OPPORTUNITY, OR BUSINESS INTERRUPTION — EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGES.

Some provinces do not allow the exclusion or limitation of certain damages. The above limitations apply only to the extent permitted by applicable law in your jurisdiction.

## 20. Term and Termination {#term-and-termination}

The SPEC Terms apply to each Engagement from the date you accept them through the close of the Engagement (delivery, refund, cancellation, or termination, whichever occurs first), plus the survival periods in Section 30.

You may cancel an Engagement at any time by written notice to jackson@opsapp.co. The refund consequences of cancellation are governed by Section 22 (Refund Mechanics).

OPS may terminate an Engagement immediately on written notice if:

- You materially breach the SPEC Terms and fail to cure the breach within 10 days of written notice, where the breach is curable.
- You miss three scheduled discovery sessions without 24 hours' advance notice (the "third no-show" cancellation; the deposit is forfeited per Section 22).
- You misrepresent your Quebec eligibility (Section 4) or your regulated-workflow status (Section 5).
- A Stripe chargeback is filed in connection with the Engagement and OPS elects to terminate.
- You become insolvent, file for bankruptcy, become subject to receivership, or take comparable steps under applicable insolvency law.

OPS may also terminate an Engagement for convenience on 30 days' written notice; in that case OPS will refund unearned Milestone amounts as if you had invoked the pre-delivery refund matrix in Section 22.

Termination under this Section does not relieve either party of obligations that, by their nature, survive termination — see Section 30 (Survival).

## 21. Effect of Termination {#effect-of-termination}

On termination of an Engagement:

- All entitlements for the Custom Modules under that Engagement are disabled in your OPS instance.
- The Module code is retained by OPS per Section 15.
- Your business data flowing through the disabled Modules remains in your OPS instance and is exportable on request as CSV or JSON within 30 days of the termination.
- Your base OPS subscription continues unchanged unless you separately cancel it.
- The sections listed in Section 30 (Survival) remain in effect.

OPS may retain operational logs, communications, and metadata associated with the Engagement on its standard retention schedule (see the Privacy Policy), and may retain financial records as required by Canadian tax and accounting law.

## 22. Refund Mechanics {#refund-mechanics}

All SPEC refunds are manually initiated by you. OPS does not issue automated refunds. OPS does not proactively refund stalled or abandoned Engagements; until you submit a refund request, your captured deposit and Milestone payments stay on file.

Refund eligibility depends on where the Engagement is in its lifecycle:

| Refund stage | Eligibility |
|---|---|
| Pre-discovery — before the first discovery session is held | Typically a full deposit refund at OPS's discretion, since no work has been done. |
| Post-discovery, pre-scope sign-off | Pro-rated. OPS retains the portion of the deposit corresponding to discovery work performed; the remainder is refunded. |
| Post-scope sign-off, pre-delivery | Pro-rated. Completed Milestones are non-refundable; unstarted Milestones are refundable. |
| Within the Guarantee Period (30 days after the Walkthrough Date) | Guarantee Refund per Section 9 on your written request stating dissatisfaction. No defect proof and no cure period. One invocation per Engagement, subject to the Section 9 exclusions. |
| After the Guarantee Period | Build fees are non-refundable. You may request a goodwill refund; OPS may grant or deny at its sole discretion. Granted goodwill refunds are flagged accordingly in the refund record. |

Because Milestones are issued on net-15 invoicing, some Milestones may be unpaid at the time a refund is granted. OPS's refund obligation is fulfilled by, for each Milestone, taking the action below that matches the Milestone's payment state at refund time:

| Milestone payment state | OPS action |
|---|---|
| Paid via Stripe Payment Intent | Stripe refund reversing the captured charge to the original payment method. |
| Invoice issued and fully paid | Stripe refund on the underlying Payment Intent. |
| Invoice issued and partially paid | Stripe credit note for the unpaid portion plus Stripe refund for the paid portion. |
| Invoice issued and unpaid | Stripe void on the open invoice. |
| Invoice issued, unpaid, and non-cancellable | Stripe "mark uncollectible" — the invoice is closed and OPS pursues no further collection. |

The aggregate effect of these actions is that you owe nothing further for the refunded Engagement and OPS has no further collection rights for that Engagement. Each per-Milestone action is recorded in the Engagement's refund breakdown for evidentiary purposes.

Refunds are processed within 7 business days of the date OPS confirms the request is valid. Funds typically settle into your account 5 to 7 business days after the refund is issued, depending on your card issuer or bank.

If you have paid no-show fees, Change Order fees, or Retainer fees for work that was delivered, those amounts are not refunded under the Guarantee Refund. The Guarantee Refund covers the SPEC build fees for the refunded Engagement only.

If your Engagement is cancelled under Section 20 for three discovery no-shows, the deposit is forfeited and no refund is issued.

## 23. Version Pinning {#version-pinning}

Each Engagement is governed by the version of the SPEC Terms in effect at the moment you accepted them at deposit. The accepted version is captured as a build-time commit hash and stored alongside the Engagement record. The full text of the accepted version is preserved in OPS's source-controlled legal-content registry and is available to you on request.

Future amendments to the SPEC Terms do not apply retroactively to Engagements with a counter-signed Scope Document dated before the amendment's effective date, except where you affirmatively accept the amendment in writing or where the amendment is non-material under Section 27 (Amendments).

If you run multiple Engagements over time, each Engagement may carry a different accepted version, depending on when each was opened. The version applicable to a dispute is the version associated with the Engagement that the dispute concerns. Where a dispute spans multiple Engagements, the version associated with each Engagement governs the corresponding portion of the dispute.

## 24. CASL and Commercial Electronic Messages {#casl-and-commercial-messages}

OPS sends two categories of email in connection with SPEC Engagements: operational/transactional messages and commercial electronic messages.

Operational/transactional messages include deposit receipts, owner-approval requests and decisions, intake reminders, scope-sign-off confirmations, Milestone invoices, refund confirmations, Stripe dispute notices, Support Window notices, service-disruption notices, and Custom Module status alerts. Operational messages are required to complete the contractual relationship under the SPEC Terms and are not subject to CASL consent requirements. You receive these messages regardless of your marketing preferences.

Commercial electronic messages include Retainer offers, referral-program promotions, SPEC marketing follow-ups, and any future cross-sell offers. Each commercial message complies with CASL by identifying OPS as sender, including OPS's mailing address (303-1121 Oscar Street, Victoria BC V8V2X3), providing a functional unsubscribe mechanism processed within 10 business days, and stating the consent basis on which OPS sent the message (express consent, implied consent under the existing-business-relationship two-year window, or otherwise).

You give your consent to receive operational messages by accepting the SPEC Terms, and that consent applies for as long as the Engagement is active. You may give or withdraw consent for commercial messages independently of operational messages. Operational messages will continue even if you have unsubscribed from commercial messages.

The SPEC referral program (when active) is link-based. OPS does not send commercial messages on your behalf to your referrals. Messages to referred prospects start only after the referred party submits a form, starts checkout, or otherwise expressly opts in.

## 25. Governing Law and Disputes {#governing-law-and-disputes}

The SPEC Terms are governed by the laws of the Province of British Columbia and the federal laws of Canada applicable in British Columbia, without regard to conflict-of-law principles.

Any dispute arising out of or relating to the SPEC Terms or a SPEC Engagement is subject to the exclusive jurisdiction of the courts located in Vancouver, British Columbia. Specifically:

- Disputes for claims of $35,000 CAD or less are resolved in the British Columbia Provincial Court (Small Claims), Vancouver Registry.
- Disputes for claims greater than $35,000 CAD are resolved in the Supreme Court of British Columbia, Vancouver Registry.

The parties expressly waive any right to a jury trial to the extent any such right would otherwise apply. The SPEC Terms do not contain a mandatory arbitration provision; either party may bring suit in the courts identified above. Each party bears its own costs in any dispute, except as otherwise ordered by the court.

The SPEC Terms are written in English. If a translation is provided for convenience, the English version governs.

## 26. Force Majeure {#force-majeure}

Neither party is liable for a failure or delay in performance caused by an event beyond its reasonable control, including acts of God, natural disasters, wildfires, floods, earthquakes, pandemics, war, terrorism, civil unrest, government action, embargoes, major internet outages, failures of upstream cloud providers, labour disputes, and similar events ("Force Majeure"). The affected party will notify the other promptly and will resume performance as soon as reasonably practicable.

Force Majeure does not excuse payment obligations for work already delivered or for refunds already due. If a Force Majeure event prevents performance for more than 60 consecutive days, either party may terminate the affected Engagement on written notice; refunds for terminated Engagements are governed by Section 22.

## 27. Amendments {#amendments}

OPS may amend the SPEC Terms from time to time. OPS will notify customers with active Engagements of any amendment at least 30 days before the amendment's effective date, by email to the address on file and via the OPS in-app notification rail.

For Engagements with a counter-signed Scope Document dated before the amendment's effective date, the amendment applies only with your affirmative written acceptance, except for non-material amendments — which include clarifications, formatting changes, subprocessor list additions that do not change a data-handling category, and corrections of typographical errors — which apply automatically 30 days after notice. Material amendments — including changes to pricing structure, the scope of the SPEC Engagement, intellectual property ownership, refund mechanics, or limitation of liability — never apply retroactively without your affirmative written acceptance.

New Engagements that open after an amendment's effective date are governed by the amended SPEC Terms in effect at the time of the new Engagement's deposit.

## 28. Notices {#notices}

Notices under the SPEC Terms are valid when sent by email:

- To OPS: jackson@opsapp.co for SPEC engagement notices, or info@opsapp.co for general legal notices.
- To Customer: the email address on file for the buyer and (for Engagements with an Owner Approval Step) the OPS account holder, as captured in the SPEC checkout flow.

A notice is deemed received on the next business day after it is sent, provided the sending party does not receive a delivery-failure bounce. You are responsible for keeping your email address current in your OPS account. Notices addressed to a stale email do not relieve you of the underlying obligation.

OPS may also serve notices through the in-app notification rail in OPS-Web; such in-app notifications are valid notice in addition to (not instead of) email. Court process and other notices required by law to be served in writing in physical form may be sent to OPS at 303-1121 Oscar Street, Victoria BC V8V2X3.

## 29. Assignment, Severability, and Entire Agreement {#assignment-and-general}

You may not assign the SPEC Terms or any rights or obligations under them, in whole or in part, without OPS's prior written consent. OPS may assign the SPEC Terms, in whole or in part, in connection with a merger, acquisition, reorganization, or sale of all or substantially all of its assets, on written notice to you.

If any provision of the SPEC Terms is held unenforceable by a court of competent jurisdiction, the unenforceable provision is severed and the remaining provisions remain in full force and effect. The court is authorized to modify the unenforceable provision to the minimum extent necessary to make it enforceable while preserving the parties' original intent.

The SPEC Terms, together with the Scope Document for the Engagement, any accepted Change Orders, the OPS Terms of Service, the OPS Privacy Policy, and the OPS Data Processing Agreement, constitute the entire agreement between OPS and Customer regarding the Engagement. They supersede any prior or contemporaneous communications, proposals, or representations on the same subject. In the event of conflict, the order of precedence is:

1. The SPEC Terms.
2. The signed Scope Document (current version on file).
3. Accepted Change Orders.
4. Other written communications between the parties.

A Change Order amends only the scope it explicitly modifies; the SPEC Terms continue to govern all other matters of the Engagement.

OPS's failure to enforce any provision of the SPEC Terms is not a waiver of that provision or of OPS's right to enforce it later. No course of dealing or course of performance between the parties modifies the SPEC Terms unless reduced to a written amendment under Section 27.

You agree that for 12 months following the termination of an Engagement you will not directly solicit any OPS employee or contractor for employment. This non-solicitation restriction does not apply to general public advertising or to unsolicited applications submitted by OPS personnel without inducement from you.

## 30. Survival {#survival}

The following provisions survive termination of an Engagement: Section 13 (Confidentiality), Section 14 (Privacy and Data Protection), Section 15 (Intellectual Property and License), Section 16 (Customer Warranties, to the extent applicable to pre-termination conduct), Section 17 (OPS Warranties and Disclaimer, with respect to delivered Modules), Section 18 (Indemnification), Section 19 (Limitation of Liability), Section 22 (Refund Mechanics, to the extent refunds remain pending or outstanding), Section 23 (Version Pinning), Section 24 (CASL and Commercial Electronic Messages, with respect to messages relating to surviving rights and obligations), Section 25 (Governing Law and Disputes), Section 28 (Notices), Section 29 (Assignment, Severability, and Entire Agreement), and this Section 30.

## 31. Contact {#contact}

For SPEC Engagement notices, refund requests, and operational questions:

jackson@opsapp.co

1361513 BC LTD.
303-1121 Oscar Street
Victoria BC V8V2X3
Canada

For general OPS legal, privacy, and account questions:

info@opsapp.co

---

## Implementation notes for the follow-up porting chip

- Each `## N. Title {#anchor-id}` heading maps to a `LegalSection` entry with `id: 'anchor-id'`, `title: 'N. Title'`, and `content` derived from the prose below the heading.
- Preserve all UPPERCASE legal-language passages in Sections 17 and 19 — they are intentional and load-bearing.
- The Section 9 Guarantee Refund clause, the Section 15 IP and license clause, and the Section 19 limitation of liability clause are reproduced verbatim from [07_ROLLOUT.md](07_ROLLOUT.md) § 2. They must port verbatim into `legal-content.ts`. The bolded label sentences (`**Guarantee Refund.**`, `**IP and license.**`, `**Limitation of liability.**`) immediately precede each verbatim block.
- The `consent_collection.terms_of_service` URL configured in the Stripe Dashboard must point at `https://opsapp.co/legal?page=spec-terms`. The build-time `SPEC_TERMS_VERSION_HASH` is appended via URL fragment so the version is captured at acceptance.
- After porting, run the build and confirm the new `SPEC_TERMS_VERSION_HASH` constant exists and that the `/legal?page=spec-terms` route renders all 31 sections in initial HTML (no JS gating).
