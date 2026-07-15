# SPEC DPA Scope Notes — Recommendation and Drafted Updates (2026-05-25; tier terms updated for Tier Model v2, 2026-07-14)

> **2026-07-14 (Tier Model v2):** the Annex B consent-basis example now says "Care Plan offers" (the v2 name for the retainer). DPA scope, subprocessors, and retention are unchanged by v2 — see [10_TIER_MODEL_V2.md](10_TIER_MODEL_V2.md) § 9.

This file documents whether the existing OPS Data Processing Agreement covers SPEC engagement data, and, where it does not, provides the precise drafted changes needed to bring it into scope. The follow-up implementation chip ports these changes into `ops-site/src/lib/legal-content.ts` under `legalDocuments['dpa']`.

Review status: Jackson-reviewed. Counsel review is recommended risk mitigation per [07_ROLLOUT.md](07_ROLLOUT.md) § Phase 1 Legal but is not a hard launch blocker.

## Summary recommendation

**Recommendation: version bump the DPA from v1.0 (lastUpdated 2026-02-01) to v1.1 (lastUpdated 2026-05-25, effectiveDate 2026-06-01 or the actual go-live date).**

Why: the existing DPA covers the OPS base subscription data scope cleanly but is silent on three SPEC-specific surfaces — (a) the SPEC-only data categories (intake responses, file uploads, scope documents, satisfaction surveys, communications log, attribution data, acceptance events), (b) the SPEC-only subprocessors (SendGrid for transactional email, Vercel for hosting, Cal.com for scheduling, Meta CAPI for ad conversion tracking, Google Ads Enhanced for ad conversion tracking), and (c) the longer 7-year retention period for SPEC engagement records driven by CRA tax and accounting record-keeping rules. Without these additions, an enterprise customer signing the DPA for a SPEC engagement could reasonably argue the DPA does not cover the actual processing happening — leaving OPS with a contractual gap exactly where the strongest disclosure rigor is needed.

The cleanest implementation is a minor amendment that (i) extends Annex A with the new SPEC subprocessors, (ii) extends Section 3 (Nature and Purpose of Processing) to include the SPEC data categories and the SPEC data subjects, (iii) carves out an exception to Section 4.7 (Deletion or Return at End of Service) for legally-required retention, and (iv) adds a new Annex B (SPEC Schedule) describing the SPEC-specific processing scope.

A version bump is preferred over a full rewrite because the existing v1.0 sections 4.1 through 4.6 (processor obligations) and 4.8 through 4.9 (compliance information, audit rights) apply cleanly to SPEC data without modification. Rewriting them risks regressing the GDPR Article 28 coverage that is already in place.

## Required changes — section by section

### Annex A — Subprocessors {#annex-a-additions}

Add the following rows to the existing Annex A table. Existing rows (Stripe, Bubble, Supabase, AWS S3, Firebase, Apple, Intuit, Sage) remain unchanged.

| Subprocessor | Purpose | Data types | Location |
|---|---|---|---|
| Twilio, Inc. (SendGrid) | Transactional and commercial email for SPEC engagements (deposit confirmations, owner approvals, intake reminders, milestone invoices, refund confirmations, retainer offers, referral promotions) | Customer email address, name, engagement reference, message content | USA (DPF certified — confirm at port time) |
| Vercel, Inc. | Hosting and edge caching for the SPEC marketing page, the OPS-Web product surface, and the SPEC server routes that handle checkout creation, owner-approval, refund-request submission, and cron-driven nudges | Request metadata, IP addresses, customer-provided form data in transit, edge-cached public SPEC board data | USA, with global edge cache |
| Meta Platforms, Inc. (Meta Conversions API) | Server-side conversion tracking for SPEC ad campaigns on Facebook and Instagram | Hashed email, hashed phone, event metadata, browser cookies fbp and fbc | USA |
| Google LLC (Google Ads Enhanced Conversions) | Server-side conversion tracking for SPEC ad campaigns on Google Search and YouTube | Hashed email, hashed phone, Google Click ID, event metadata | USA (DPF certified) |
| Cal.com, Inc. | Scheduling discovery sessions and delivery walkthroughs for SPEC engagements | Customer name, email, optional phone, scheduled session metadata, time-zone preference | USA/EU depending on Cal.com instance |

Stripe's existing Annex A row remains accurate; for SPEC the scope expands to include Stripe Tax for GST/HST/PST calculation, Stripe Connect for referral payouts (Phase 2), and Stripe customer Tax IDs for GST/HST customer-supplied numbers. Supabase's existing row remains accurate; for SPEC the scope expands to include SPEC engagement records, intake responses, scope documents, satisfaction ratings, communications log, acceptance events, and the `spec-intake` Storage bucket for file uploads.

### Section 3 — Nature and Purpose of Processing (revised) {#section-3-revised}

Replace the existing Section 3 table with the table below. The intent is to extend the existing scope to SPEC engagement data without losing the base-subscription scope.

| Element | Detail |
|---|---|
| Nature | Storage, retrieval, display, transmission, and synchronization of operational data; transactional and commercial email delivery; ad-campaign conversion tracking via server-side hashed identifiers; scheduling assistance |
| Purpose | Providing job management, scheduling, CRM, billing, and SPEC engagement design-build-deliver services to the Customer |
| Types of Personal Data — base subscription | Employee names and contact information; end-client names, addresses, phone numbers, email addresses; job site GPS coordinates; job photos; financial records (estimates, invoices) |
| Types of Personal Data — SPEC engagement | Customer business profile data and self-reported workflow data collected at SPEC intake; files uploaded to the SPEC intake Storage bucket; Scope Document content and revisions; satisfaction survey ratings and comments; SPEC communications log (outbound emails, inbound replies, call summaries, walkthrough recording URLs); SPEC milestone payment records and refund records; SPEC acceptance event metadata (IP address, user agent, content hash, signature method); SPEC attribution data (UTM parameters, Google Click ID, Meta Click ID, landing URL, first-touch timestamp) |
| Categories of Data Subjects — base subscription | Customer's employees (Admin, Office Crew, Field Crew); Customer's end-clients |
| Categories of Data Subjects — SPEC engagement | The SPEC buyer; the OPS account holder of the Customer company (where different from the buyer); the Customer's employees and end-clients whose data flows through the Custom Modules built by SPEC; referrers participating in the SPEC referral program; visitors to the SPEC marketing page whose attribution cookies persist into a SPEC purchase |

### Section 4.4 — Subprocessors (clarification) {#section-4-4-clarification}

The existing Section 4.4 language ("The Customer grants OPS general authorization to engage the subprocessors listed in Annex A. OPS will notify the Customer at least 30 days before adding or replacing a subprocessor. The Customer may object to a new subprocessor in writing within 14 days...") applies unchanged. The v1.1 amendment adds a clarifying sentence at the end of the section:

> "For SPEC engagements with an active counter-signed Scope Document, OPS will not add a new SPEC-specific subprocessor that introduces a new category of data processing (for example, a new advertising-platform subprocessor or a new scheduling subprocessor) without 30 days' notice and the Customer's right to object as described above. Non-material subprocessor changes — including replacement of an existing subprocessor with a substantially equivalent provider in the same processing category, or addition of a sub-subprocessor within an existing processor's stack — may proceed with notice but without an objection right."

### Section 4.7 — Deletion or Return at End of Service (revised) {#section-4-7-revised}

The existing Section 4.7 deletion timeline ("delete all Customer Personal Data from production systems within 30 days of the end of the export period") cannot apply to SPEC engagement records because the Canada Revenue Agency requires retention of business records (including engagement contracts, payment records, refund records, and supporting documentation) for at least 6 years from the end of the tax year to which they relate. Add the following carve-out to the end of Section 4.7:

> "Notwithstanding the deletion timeline above, OPS retains SPEC engagement records — including SPEC engagement metadata, intake responses, file uploads to the SPEC intake Storage bucket, Scope Document content (all versions), milestone payment records, refund records, acceptance events, and the SPEC communications log — for 7 years from the date the engagement closes (delivery, refund, cancellation, or termination, whichever is earlier), as required by the Income Tax Act (Canada), the Excise Tax Act (Canada), and applicable provincial accounting record-retention rules. After the 7-year retention period elapses, OPS deletes the SPEC engagement records on its standard purge schedule. OPS may retain anonymized aggregate metrics derived from SPEC engagements indefinitely; aggregated metrics that cannot identify a Data Subject are not Personal Data under this DPA."

### New Annex B — SPEC Schedule {#annex-b-spec-schedule}

Add the following new Annex B at the end of the DPA, after Annex A.

> **Annex B — SPEC Schedule**
>
> This Annex B applies in addition to the rest of this DPA when the Customer purchases one or more SPEC engagements. The terms used here have the meanings given in the SPEC Engagement Terms of Service at /legal?page=spec-terms.
>
> **B.1 Scope.** Each SPEC engagement is processed under this DPA. The SPEC engagement data categories and subprocessors are listed in Section 3 and Annex A respectively, as amended in v1.1.
>
> **B.2 Lawful basis under PIPEDA and Canadian provincial law.** OPS processes SPEC engagement data primarily under the lawful basis of contract performance — the data is necessary to perform the SPEC engagement Customer has purchased. OPS additionally relies on legitimate interest for fraud detection, eligibility enforcement (Canada excluding Quebec, regulated-workflow exclusions), and evidence preservation for Stripe dispute defence; and on consent (express or implied under CASL's existing-business-relationship two-year window) for commercial electronic messages such as Care Plan offers, referral promotions, and SPEC marketing follow-ups.
>
> **B.3 Ad conversion tracking.** OPS sends server-side conversion events to Meta Conversions API and Google Ads Enhanced Conversions for the purpose of optimizing SPEC ad campaigns. Personal data sent to these platforms is limited to SHA-256 hashed email and hashed phone identifiers plus event metadata (event name, value, currency, deduplication ID). Raw identifiers are never transmitted. OPS does not authorize the advertising platforms to retarget the SPEC engagement audience beyond the campaigns OPS itself runs.
>
> **B.4 Hashed identifiers as Personal Data.** OPS treats hashed identifiers as Personal Data under this DPA. Hashing reduces re-identification risk but does not eliminate it. Customer rights described in the OPS Privacy Policy apply to hashed identifiers to the same extent they apply to the underlying raw identifiers, subject to the practical limits of identifying the corresponding records given only a hash.
>
> **B.5 Cross-border processing.** SPEC engagement data is stored primarily in Canada and the United States by OPS's Supabase, Vercel, Stripe, SendGrid, Meta, Google, and Cal.com subprocessors. By accepting the SPEC Engagement Terms of Service and this DPA, Customer consents to cross-border processing of SPEC engagement data. OPS relies on Standard Contractual Clauses, the EU-US Data Privacy Framework where applicable, and equivalent UK and Canadian transfer mechanisms.
>
> **B.6 Retention.** Retention periods specific to SPEC engagement data are set out in Section 4.7 as amended in v1.1. SPEC engagement records and supporting documentation are retained for 7 years from engagement close, after which they are deleted.
>
> **B.7 Data Subject requests for SPEC data.** Where a Data Subject request relates to SPEC engagement data — for example, a request for access to an intake response, a correction of a Scope Document detail, or a deletion request — OPS will assist Customer in fulfilling the request to the extent technically feasible. Deletion requests against SPEC engagement records held under the 7-year retention rule will be honoured by anonymizing the records where possible or by securely retaining them with no further processing until the retention period elapses.
>
> **B.8 Breach notification — SPEC scope.** A breach of security safeguards involving SPEC engagement data triggers the existing breach-notification obligations under Section 4.6, with the additional requirement that OPS notify Customer of any breach affecting the SPEC intake Storage bucket or the SPEC communications log within 72 hours of becoming aware, given the typically sensitive nature of intake content.
>
> **B.9 Order of precedence.** This Annex B supplements the body of this DPA and does not replace any obligation. Where this Annex B and the body of the DPA conflict with respect to SPEC engagement data, this Annex B governs. The order of precedence remains: SPEC Engagement Terms of Service, then this DPA (with Annex B prevailing for SPEC scope), then the Scope Document, then any other written agreement.

## Implementation notes for the porting chip

- Increment the DPA `lastUpdated` field to `'2026-05-25'` and set `effectiveDate` to the actual go-live date when the prose ships.
- The DPA carries no separate version string field in `legal-content.ts` today; if the porting chip introduces one, set it to `v1.1`.
- The Stripe Annex A row in the existing DPA already covers SPEC payments at a high level. The v1.1 amendment broadens the scope without changing the row title; if the porting chip prefers, the row can be split into two entries (one for base subscription, one for SPEC) — both approaches are acceptable.
- The 7-year retention figure is the safe Canadian floor for tax and accounting records. If OPS adopts a longer internal retention for other compliance reasons (some sectors extend to 10 years), align the figure across the DPA, the Privacy Policy, and the SPEC Engagement Terms of Service.
- After porting, run the build and verify the DPA renders cleanly at /legal?page=dpa with the new Annex B section appearing after Annex A.
