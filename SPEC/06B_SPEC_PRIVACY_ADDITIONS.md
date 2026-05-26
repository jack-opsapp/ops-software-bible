# SPEC Privacy Policy Additions — Final Customer-Facing Prose (2026-05-25)

This file is the production-ready Privacy Policy additions that cover SPEC-specific data flows. The follow-up implementation chip merges this content into `ops-site/src/lib/legal-content.ts` under `legalDocuments['privacy']`. Each section below indicates where it lands in the existing Privacy Policy structure.

Review status: Jackson-reviewed. Counsel review is recommended risk mitigation per [07_ROLLOUT.md](07_ROLLOUT.md) § Phase 1 Legal but is not a hard launch blocker.

Open decision flagged inline: the scheduling subprocessor for SPEC discovery and walkthrough sessions is undecided between Calendly and Cal.com per [07_ROLLOUT.md](07_ROLLOUT.md) open items. The prose below names both. Pick one before publishing and remove the other; if both will be used in different stages, leave both named.

---

## Where each addition lands in the existing Privacy Policy

The existing Privacy Policy (`legalDocuments['privacy']` in `ops-site/src/lib/legal-content.ts`, last updated 2026-02-19) has 13 sections numbered 1 through 13 (Who We Are, What Information We Collect, How We Use Your Information, Third-Party Processors, Location Data, Your Rights, Data Security, Data Retention, Cookies, Children, Communications, Changes, Contact). The SPEC additions extend the existing structure as follows:

| Existing section | SPEC addition |
|---|---|
| § 2 — What Information We Collect | New subsection 2.9 "SPEC Engagement Data" |
| § 3 — How We Use Your Information | New row added to the purpose table for SPEC engagement processing and SPEC conversion-tracking |
| § 4 — Third-Party Processors | New entries added to the processors table: SendGrid, Vercel, Meta (CAPI), Google Ads, Calendly and/or Cal.com |
| § 8 — Data Retention | New rows added to the retention table for SPEC engagement records, intake responses + uploads, scope docs, satisfaction ratings, and communications log |
| § 11 — Communications | New paragraph added covering SPEC-specific commercial messages (Retainer offers, referral promotions, SPEC marketing follow-ups) |

The full prose for each addition is below. Section numbers in the additions match the numbering style of the existing Privacy Policy.

---

## § 2.9 — SPEC Engagement Data {#spec-engagement-data}

If you purchase a SPEC engagement, we collect additional categories of data necessary to design, build, and deliver Custom Modules inside your OPS instance.

**Intake responses.** When you complete the SPEC intake form at /spec/intake/[token], we store your answers as structured form data in our database. The intake covers business basics (company name, legal entity type, years operating, primary trade, secondary trades, service area), team composition (size, roles, seasonal vs year-round), revenue band (optional), average job size, current tools you use, your workflow narrative from lead to invoice, top pain points, your 90-day success picture, and regulated-workflow attestations. The intake form is the foundation of the discovery work and the Scope Document.

**File uploads.** The intake form allows you to upload existing process documents — screenshots, PDFs, sample invoices, photos of your current paper workflows, or anything else that helps OPS understand how your business operates today. Files are stored in a Supabase Storage bucket named `spec-intake` under a folder keyed to your engagement record. Maximum size 25 MB per file. Accepted file types are limited by an allow-list (common document, image, and spreadsheet formats). Files are scoped to your engagement and are not shared with other customers.

**Scope Document content.** The Scope Document drafted during discovery and counter-signed at scope sign-off is stored as structured content tied to your engagement record, with a content hash for integrity verification. Each revision is preserved as a versioned record so prior versions remain available to you on request.

**Satisfaction survey responses.** After the midpoint demo and the delivery walkthrough, we may invite you to rate each feature on a 1-to-5 scale and to add free-text comments. The ratings and comments are stored against your engagement and identified to you. They are non-binding feedback under the SPEC Engagement Terms of Service.

**Communications log.** OPS logs the substantive communications associated with each engagement — outbound emails, inbound replies, scheduled and held call summaries, and links to walkthrough recordings. This log forms part of the evidence chain in any Stripe dispute and is retained alongside the engagement record.

**Stripe billing data.** When you complete the SPEC checkout flow, Stripe collects your name, email, phone, billing address (line 1, line 2, city, province, postal code, country), and any GST/HST number you choose to provide. Stripe stores your payment card data; we do not. We receive from Stripe a customer identifier, a payment intent identifier, the billing address recorded at checkout, your consent state for our terms of service, and (where applicable) the GST/HST number you entered. We use the billing address to enforce our Canadian (excluding Quebec) eligibility rules; see the SPEC Engagement Terms of Service for details.

**Attribution data.** When you arrive on the SPEC marketing page from an advertising source, we store first-touch attribution data on a 30-day cookie set on your browser. The cookie holds the campaign parameters in the URL (utm_source, utm_medium, utm_campaign, utm_content, utm_term, Google Click ID `gclid`, Meta Click ID `fbclid`), the landing URL, and the time of first touch. The cookie is `SameSite=Lax` and is not shared with third parties from the browser. At deposit time, the cookie values are written into your engagement record as the attribution context for that engagement.

**Owner-approval and acceptance events.** For SPEC engagements where the buyer is not the OPS account holder, we record the account holder's electronic approval — including the IP address, user agent, signature method, and a content hash of the version of the SPEC Engagement Terms of Service they reviewed — as a binding acceptance event. Each substantive acceptance step in the engagement lifecycle (terms of service acceptance, scope sign-off, midpoint acceptance, delivery acceptance, change order acceptance) is recorded as a separate acceptance event with the same fields.

We collect the SPEC engagement data above to perform the SPEC engagement under contract with you (PIPEDA lawful basis: necessary for performance of a contract). We use the data for the limited purposes described in § 3 below.

## § 3 — How We Use Your Information (additions) {#how-we-use-additions}

Add the following rows to the purpose-of-processing table:

| Purpose | Legal basis (PIPEDA) |
|---|---|
| Delivering a SPEC engagement: discovery, scope drafting, build, midpoint demo, walkthrough, support window, retainer support | Contract performance |
| Processing SPEC milestone payments and refunds via Stripe | Contract performance |
| Sending operational SPEC emails (deposit confirmations, owner approvals, intake reminders, invoices, refund confirmations, dispute notices, support-window notices) | Contract performance |
| Sending commercial SPEC emails (Retainer offers, referral program promotions, SPEC marketing follow-ups) | Express or implied CASL consent, as applicable |
| Enforcing eligibility rules — including the Canada-excluding-Quebec geographic restriction and the regulated-workflow exclusions | Legitimate interest; legal obligation |
| Measuring SPEC ad-campaign performance through conversion tracking to Meta and Google | Legitimate interest; consent where required by applicable law |
| Detecting fraud and misuse of the SPEC pipeline — including chargeback fraud, self-referral attempts, and Quebec-misrepresentation cases | Legitimate interest |
| Preserving an evidence chain for Stripe disputes and refund decisions | Legitimate interest |

We do not sell SPEC engagement data, and we do not use intake content, scope content, communications, or satisfaction ratings for advertising targeting. Conversion tracking sends only hashed identifiers (email, phone) and aggregate event signals (deposit click, deposit completed, intake submitted, discovery booked) to Meta and Google; the raw intake content, scope content, and communications never leave OPS infrastructure or its DPA-covered subprocessors.

## § 4 — Third-Party Processors (additions) {#third-party-processors-additions}

Add the following entries to the processors table. Existing entries (Bubble, AWS S3, Intuit, Sage, Apple, Firebase) continue to apply where relevant. Stripe and Supabase, already listed, expand their scope to cover the SPEC engagement data described in § 2.9.

| Processor | Purpose for SPEC | Data shared | Location |
|---|---|---|---|
| Stripe, Inc. (existing) | SPEC milestone payments and invoices; Stripe Tax for GST/HST/PST; Stripe Connect for referral payouts (Phase 2); Stripe Tax IDs for GST/HST customer numbers | Customer name, email, phone, billing address, GST/HST number, transaction history, terms-of-service consent state | USA |
| Supabase, Inc. (existing) | Storage of SPEC engagement records, intake responses, scope documents, satisfaction ratings, communications log, acceptance events, and the `spec-intake` Storage bucket for file uploads | All SPEC engagement data described in § 2.9 | USA |
| Twilio, Inc. (SendGrid) — new | Transactional and commercial SPEC emails (deposit confirmations, owner approvals, intake reminders, milestone invoices, refund confirmations, retainer offers, referral promotions) | Customer email address, name, engagement reference, message content | USA |
| Vercel, Inc. — new | Hosting of the SPEC marketing page (/spec), the OPS-Web product surface, and the SPEC server routes that handle checkout creation, owner-approval, refund-request submission, and cron-driven nudges. Edge cache for the OPS Board public read | Request metadata, IP addresses, customer-provided form data in transit | USA, with global edge cache |
| Meta Platforms, Inc. (Meta Conversions API) — new | Server-side conversion tracking for SPEC ad campaigns on Facebook and Instagram | Hashed email address, hashed phone number, event metadata (event name, value, currency, deduplication ID), browser cookies `fbp` and `fbc` | USA |
| Google LLC (Google Ads Enhanced Conversions) — new | Server-side conversion tracking for SPEC ad campaigns on Google Search and YouTube | Hashed email address, hashed phone number, Google Click ID (`gclid`), event metadata | USA |
| Calendly, LLC and/or Cal.com, Inc. — new | Scheduling discovery sessions and delivery walkthroughs for SPEC engagements. *(Open decision flagged for Jackson: SPEC will name one provider before publishing — pick Calendly or Cal.com. If both are used at different stages, both are listed.)* | Customer name, email, optional phone, scheduled session metadata, time-zone preference | USA (Calendly) or USA/EU (Cal.com, depending on instance) |

For Meta and Google conversion tracking, we hash email and phone with SHA-256 before sending. Raw identifiers are not transmitted to the advertising platforms. We use this data solely to optimize SPEC ad campaigns; we do not allow Meta or Google to use the data for retargeting beyond the campaigns we run.

We will update this list when we add or replace SPEC-specific subprocessors. Notice is given 30 days in advance to active engagements by email and through the in-app notification rail, except where the change is non-material (for example, a sub-subprocessor change within an existing processor's stack that does not change the data-handling category).

## § 8 — Data Retention (additions) {#data-retention-additions}

Add the following rows to the retention table:

| Data type | Retention |
|---|---|
| SPEC engagement record (project, scope versions, milestone payments, acceptance events, refund records) | 7 years from the date of engagement close, then deleted. Retention is anchored on the Canada Revenue Agency 6-year minimum for tax and accounting records, with a one-year buffer for dispute resolution. |
| SPEC intake responses and file uploads in the `spec-intake` Storage bucket | Retained for the active life of the engagement plus 7 years from engagement close. Intake responses are part of the evidence chain for any chargeback or refund dispute, and are treated as engagement records for retention purposes. |
| Scope Document content (all versions, including superseded versions) | 7 years from engagement close, same as engagement records. |
| SPEC communications log (emails sent, replies received, call summaries, walkthrough recording URLs) | 7 years from engagement close, same as engagement records. |
| Satisfaction survey ratings and comments | Identifiable form for 2 years, then anonymized into aggregate metrics. Anonymized aggregates may be retained indefinitely. |
| Attribution data (UTM, gclid, fbclid, landing URL, first-touch timestamp) | Stored on the engagement record for 7 years; deleted on engagement-record deletion. |
| SPEC ad-campaign conversion-tracking outbox (retried sends to Meta and Google) | 30 days after the event was successfully transmitted or permanently failed. |
| SPEC blocked-buyer records (for Quebec-misrepresentation and other ToS-breach cases) | 7 years from the date of blocking, then deleted. Used solely to prevent re-purchase under a different account by the same individual or entity. |

You may request earlier deletion of your data at any time by contacting info@opsapp.co. Where retention is required by law (Canadian tax and accounting record-retention rules, in particular), we are obligated to retain the records for the legally required period regardless of your deletion request; we will tell you when this applies to a specific category of data.

After deletion, we may retain anonymized aggregate metrics that cannot be re-identified to you — for example, conversion rates by ad source, average time from deposit to walkthrough, refund rates by package tier — for the indefinite purpose of improving the SPEC service.

## § 11 — Communications (additions) {#communications-additions}

Add the following paragraph after the existing CASL paragraphs in § 11:

For SPEC engagements specifically, you receive two categories of email:

- Operational/transactional messages — deposit receipts, owner-approval requests and decisions, intake reminders, scope-sign-off confirmations, milestone invoices, refund confirmations, Stripe dispute notices, support-window notices, and Custom Module status alerts. These messages are required to complete the SPEC contract and are not subject to CASL consent requirements. You receive them regardless of marketing preferences.
- Commercial messages — Retainer offers around the close of the support window, SPEC referral-program promotions, and SPEC marketing follow-ups. Each commercial message identifies OPS as sender, includes our mailing address (303-1121 Oscar Street, Victoria BC V8V2X3), provides a functional unsubscribe link processed within 10 business days, and states the consent basis (express or implied under the existing-business-relationship two-year window).

The SPEC referral program is link-based. We do not send commercial messages on your behalf to your referrals. Messages to referred prospects start only after the referred party submits a form, starts checkout, or otherwise expressly opts in to OPS communications.

---

## Cross-references for the porting chip

- The terms "engagement record," "Scope Document," "Walkthrough Date," "Support Window," "Retainer," and "Custom Modules" used here are defined in the SPEC Engagement Terms of Service at /legal?page=spec-terms. The Privacy Policy itself does not need to re-define them; readers can cross-reference.
- The Meta and Google conversion-tracking flows are operationally implemented at `ops-site/src/lib/spec/conversion-events.ts` (per [07_ROLLOUT.md](07_ROLLOUT.md) Phase 1 file list). The hashing pre-send happens server-side in that module — confirm during porting that the implementation matches the disclosure here.
- The Calendly vs Cal.com decision must be resolved before the Privacy Policy update goes live. Track this against the open items list in [07_ROLLOUT.md](07_ROLLOUT.md) and update the entry above accordingly.
- The 7-year retention period for SPEC engagement records is the Canadian standard for tax and accounting records under the Income Tax Act (Canada) and the Excise Tax Act (Canada). If the OPS bookkeeping policy adopts a longer period for any record type (some compliance regimes extend to 10 years), update the retention rows to match.
