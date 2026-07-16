# SPEC — Customer-facing UX

> **Superseded in part 2026-07-14: the `/spec` page composition and all package copy are now governed by [10_TIER_MODEL_V2.md](10_TIER_MODEL_V2.md) § 8 (implemented on `feat/spec-tier-model-v2`).** v2 section order: hero (guide entry as the secondary CTA) → the ladder (SPEC-01/02/03 escalation with per-tier payment shapes) → live OPS BOARD → white-label strip → included/ongoing (flat numbers) → guarantees (per-tier levers) → FAQ (14 v2 items) → bottom CTA. The tier guide is the 09-v3.1 method with v2 outcomes ({ops, data_setup rider, spec01, spec02, spec03-conversation}). The route inventory, checkout/intake/approval/refund flows, and conversion tracking below survive v2; the "marketing page" section reflects the v1 page and is retained for history.

Every customer-touching surface on ops-site. Maps to the existing `/spec` scaffold and adds new routes. Revised 2026-05-25 (third pass) to:

- Insert a pre-Stripe billing-address form (Quebec rejection happens here, not at Stripe).
- Switch the OPS BOARD data path from a view to the `spec_public_board_snapshot` table (edge-cached read, `refreshed_at` exposed).
- Keep the full customer-facing project portal (`/account/spec/[id]`) out of Phase 1, but add the minimal customer refund-request route `/account/spec/[id]/request-refund` in Phase 1. `/admin/spec/*` remains operator-only.
- Replace off-brand intake template copy with tactical OPS voice (`// INTAKE READY`).
- Replace adversarial "no goalpost moving / disputes resolved by reading the doc" copy with neutral acceptance language.
- Add a brief Path B reference: the owner-approval page captures an `owner_purchase_approved` event, distinct from the buyer's later `tos_accepted` at Stripe.

## `/spec` — the marketing page

Existing structure stays. Section-by-section changes.

### 1. Hero (existing)
Keep current hero composition. Founder presence is a Phase 1 deliverable (asset dependency — see [07_ROLLOUT.md](07_ROLLOUT.md) Phase 1 list).

### 2. HowItWorks (existing — copy revision)
Step copy updated to reflect locked policy:
- **Step 1:** "Pick your package, sign in, lock your spot." (mentions auth requirement)
- **Step 2:** "Tell us how you work." (intake)
- **Step 3:** "We meet. We build. You pay at four checkpoints." (mentions 25/25/25/25)
- **Step 4:** "Go live with a 30-day Guarantee Refund." (guarantee prominent; exclusions disclosed nearby)

### 3. OPS BOARD (between HowItWorks and Pricing)

Full-width section. Reads from the `spec_public_board_snapshot` TABLE (refreshed every 5 min by pg_cron, single row, anon SELECT granted). The data column holds coarse signals only — availability bucket, waitlist range, ISO-week of next-start, accepting-bookings flag, public note. `refreshed_at` is exposed in the read payload so the UI can show "UPDATED [N min ago]" and shift the timestamp to amber after 72h staleness.

The serving route at `/api/spec/board` emits `Cache-Control: public, max-age=300, s-maxage=300, stale-while-revalidate=60` so most reads land on the Vercel edge cache (Supabase round-trip happens at most once every 5 min per edge region).

```
// OPS BOARD                          // LIVE  • UPDATED [timestamp]

CURRENT INTAKE

TIER          AVAILABILITY   WAITLIST   NEXT INTAKE          YOUR DELIVERY
──────────────────────────────────────────────────────────────────────────
›  SETUP        OPEN           0        WEEK OF JUN 03       JUN 14 — JUN 21
›  BUILD        LIMITED        1-2      WEEK OF JUN 10       JUL 01 — JUL 08
›  ENTERPRISE   WAITLIST       1-2      WEEK OF JUN 17       JUL 29 — AUG 12

TIMELINE
──●─────────────●────────────────────●─────────────●────────●──
  TODAY         DISCOVERY            BUILD          DELIVERY
  MAY 25        JUN 17 — JUL 01      JUL 01 — JUL 22 AUG 12
```

The original spec's exact "ACTIVE 2/4, QUEUE 1" numbers and percentage utilization bar are removed for the public board — those leak occupancy for low-volume tiers (Enterprise has `slot_ceiling = 1`). The admin OPS BOARD in `/admin/spec` shows the precise numbers under admin RLS.

**Interaction:** Clicking a row sets it as "selected" and animates the timeline to that tier's dates. Default selected: BUILD (recommended).

**Animation choreography** (per animation-architect + data-visualization skills):
- On-enter (Intersection Observer 30% threshold): header fades 200ms, tier rows stagger 80ms apart at 400ms each, timeline strokes left-to-right then markers pop sequentially.
- On row selection: 2px steel-blue left rail (200ms), other rows dim 40% (200ms), timeline markers slide to new positions (350ms).
- Ambient: "LIVE" indicator dot 2s soft pulse. Only ambient motion on the page.
- Single easing curve: `cubic-bezier(0.22, 1, 0.36, 1)`. No spring/bounce.
- Reduced-motion: instant final state, single 200ms fade, no pulse.

**Edge cases:**
- All tiers `OPEN` → no "WAITLIST" row in UI
- Tier `WAITLIST` → row in amber + "Join waitlist" CTA on the pricing card
- Tier closed (`is_accepting_bookings = false`) → "CLOSED — RESUMES [public_note or date]"
- Supabase unreachable → graceful degradation to static fallback from the dictionary, "LIVE" hidden
- `refreshed_at` > 72h old → timestamp amber + "UPDATED [N] DAYS AGO" (the snapshot row's `refreshed_at` is the authoritative freshness signal)

**Mobile (< 768px):** Tier rows stack as cards. Timeline strip stays at bottom.

### 4. Pricing — major copy revision

Each `PackageCard` rewrite:

**Collapsed state:**
```
SETUP                              Get started for $750
We configure OPS around your...    $3,000 total · 4 milestones
```

**Expanded state:**
```
SETUP                              Get started for $750
We configure OPS around your...    $3,000 total · 4 milestones

[ Feature list — existing ]

[ Trade-specific examples — existing ]

──●──────●──────●──────●──
  P1     P2     P3     P4
  $750   $750   $750   $750
  Deposit Scope  Demo   Delivery

ESTIMATED SUBSCRIPTION  +15% on base OPS sub
                        Locked at scope sign-off
RETAINER (optional)     $250/mo after support window

[ 30-DAY GUARANTEE REFUND BADGE ]

[ Pay $750 Deposit ]
```

The "Get started for $X" headline replaces "$1,500 deposit" — friendlier as ad copy. The headline number is P1 (25% of total), not 50%.

**Numbers formatting compliance** (per CLAUDE.md): every numeric value rendered on the page uses JetBrains Mono with `tabular-nums` and `font-variant-numeric: slashed-zero`. Always formatted ("$1,000" not "$1000.00"). Empty state is `—`, not "N/A". Audit `SocialProof.tsx`, `PackageCard.tsx`, and the new timeline visualizations against this rule before shipping.

### 5. WhatsIncluded (existing — keep)

### 6. SocialProof — REMOVED (Phase 1)

The existing "500+ active businesses, 12,000+ projects, 85,000+ tasks, $14M+ revenue generated" stat block is unverified and presents an ads-compliance + credibility risk. Strip the entire stat block from both `SocialProof.tsx` and the `en/spec.json` + `es/spec.json` dictionaries.

Phase 1 replacement: a single founder-credibility block ("built by a contractor running OPS at his own company" or similar), no stats. When real testimonials or genuinely countable metrics exist post-launch, add a new SocialProof composition in Phase 2 or 3.

### 7. Standing Behind The Work (NEW section)

Between WhatsIncluded and the (removed) SocialProof slot. Three columns:

- **"30 days to walk away"** — Guarantee Refund explainer (3 sentences). "If you're not satisfied within 30 days after the walkthrough, send written notice. No defect proof. No cure period. Exclusions apply for chargebacks, fraud, misrepresentation, prohibited workflows, breach, non-payment disablement, and continued use after refund."
- **"Pay as work clears review"** — 25/25/25/25 milestone explainer (3 sentences). Replacement copy for the original false claim: "Four checkpoints. Deposit funds discovery. Scope sign-off funds build kickoff. Midpoint and delivery bill when the work clears review."
- **"Scope is written before build"** — Acceptance criteria explainer (3 sentences). "Every feature has a written acceptance test in the scope doc, signed before build kicks off. Acceptance is measured against that written scope. If a feature fails its written test, OPS rebuilds it free."

Footer link: "Full terms at [/legal?page=spec-terms](/legal?page=spec-terms)."

### 8. FAQ — heavy rewrite, SSR-visible by default

Replace the current 8 questions with the list below. The component must use the `<details>/<summary>` HTML pattern (or pre-rendered `aria-expanded` content) so all answer text lives in the initial HTML payload — SEO crawlers and LLM crawlers can read it without executing JS. Today's client-side accordion hides answers from the indexed HTML; that breaks AI-discovery hooks.

Each answer ≤ 4 sentences. JSON-LD `FAQPage` schema included.

Questions:
- What happens after I pay the deposit?
- How does the 4-milestone payment structure work?
- What is the 30-day Guarantee Refund, exactly?
- What's the intake interview?
- What does "scope sign-off" mean — and what if I want changes after?
- What's the difference between a "minor change" and a "major change order"?
- Do I need an OPS subscription? When does it start?
- What's the subscription premium and how is it calculated?
- What is the maintenance retainer?
- What happens if my build takes longer than estimated?
- Can I refer someone? Do I get anything for it?
- Is there a contract? Where can I read it?
- What if I am not sure which package I need?
- Who owns the code you write?

The FAQ answer for "Who owns the code you write?" must say: OPS owns all code, configurations, designs, templates, and reusable know-how created for SPEC. Customer owns its business data. While Customer maintains an active OPS subscription and is not in breach, Customer has a limited, non-exclusive, non-transferable license to use delivered modules inside OPS; the license ends when the OPS subscription ends or the engagement is refunded.

Per OPS voice: terse, tactical, sentence case content. No emoji.

### 9. SpecBottomCTA (existing — keep)

## Conversion tracking (Phase 1)

Single instrumentation contract. Every page-served prospect can be reconstructed from these events. UTM + ad-click parameters persist via cookies; GCLID + FBCLID also persist into Stripe metadata at checkout for downstream attribution in Meta and Google.

### Event list

| Event | Surface | Server or Client | Sent to |
|---|---|---|---|
| `page_view` | `/spec` and `/es/spec` | Client (Vercel Analytics) | Vercel Analytics, Meta CAPI (deduped), Google Enhanced Conversions |
| `spec_card_expand` | Pricing card open | Client | Vercel Analytics |
| `pay_deposit_click` | Pay Deposit CTA | Client + Server | Vercel Analytics, Meta CAPI, Google Enhanced |
| `billing_address_submitted` | Pre-Stripe address form server-side validation passes | Server | Vercel Analytics, Meta CAPI (intermediate funnel step) |
| `quebec_rejected` | Pre-Stripe address form rejects QC | Server | Internal log only (no ad-platform send) |
| `owner_approval_requested` | Path B server-side after creating approval row | Server | Internal log + Meta CAPI (as intermediate funnel step) |
| `stripe_checkout_opened` | Server creates session (post-address-validation) | Server | Meta CAPI, Google Enhanced |
| `stripe_checkout_completed` | Approved Stripe payment success webhook | Server | Meta CAPI (primary conversion), Google Enhanced (primary conversion), Vercel Analytics |
| `intake_started` | `/spec/intake/[token]` first field interaction | Client + Server | Meta CAPI, Google Enhanced |
| `intake_submitted` | Intake submission endpoint | Server | Meta CAPI, Google Enhanced |
| `discovery_booked` | Discovery scheduling webhook (Calendly/Cal.com) | Server | Meta CAPI, Google Enhanced |
| `refund_invoked` | Refund processing | Server | Internal only — explicitly excluded from optimization signals |

### UTM + ad-click persistence

- On first visit to ops-site, a `ops_attribution` first-touch cookie is set: `{utm_source, utm_medium, utm_campaign, utm_content, utm_term, gclid, fbclid, landing_url, first_touch_at}`. 30-day Max-Age. SameSite=Lax.
- Subsequent visits do not overwrite the cookie (first-touch model). If a visitor arrives without UTM params, the cookie is preserved.
- At checkout session creation, the cookie's values are read server-side (via the `cookies()` helper in the API route) and attached to:
  - Stripe metadata
  - The `spec_projects.attribution` JSONB column on webhook insert
- Meta CAPI events use `fbp` + `fbc` browser cookies (set by the Meta pixel) and server-side hashed email + phone for advanced match.
- Google Enhanced Conversions use `gclid` + hashed email + hashed phone passed via the Stripe metadata into a server-side conversion send.

### Failure modes

- Meta CAPI / Google Enhanced unavailable → queued in a Vercel Edge Config or Supabase outbox; retried hourly. Never blocks the primary user flow.
- Conversion send fails entirely → logged but the customer's checkout completes normally. No customer-facing impact.

## `/spec/billing-address` — pre-Stripe billing capture (NEW)

Rendered between the "Pay Deposit" CTA click and the redirect to the approved Stripe payment flow. The route is server-side at the `/api/spec/create-checkout-session` boundary — Stripe is NOT contacted until the form submits successfully.

**Content:**
- Header: "// BILLING ADDRESS"
- Subhead: "We collect this here so we can confirm CAD eligibility before payment."
- Fields: Address line 1 (required), Address line 2 (optional), City (required), Province (required — dropdown of all 13 Canadian subdivisions), Postal code (required, server-validated against Canadian format), Country (locked to Canada at launch).
- Submit CTA: "Continue to payment"

**Server-side validation:**
- `country != 'CA'` → "We're CAD-only at launch. [Contact form link]"
- `province == 'QC'` → "We're not currently serving Quebec engagements. [Contact form link]. Learn more in [our terms]."
- Customer must also attest that it has no Quebec head office, Quebec operating address, Quebec establishment, or material SPEC use in Quebec. Billing address is not the only eligibility rule. Misrepresentation is a material breach and makes the Guarantee Refund unavailable.
- Postal-code format mismatch → "Please enter a valid Canadian postal code (e.g. V5K 0A1)."

On valid submit:
- Path A: creates `spec_projects` row with `status = 'awaiting_deposit'` + billing_* populated, then creates the approved Stripe payment session and 302s to the Stripe URL.
- Path B: creates `spec_projects` row with `status = 'awaiting_owner_approval'` + billing_* populated, creates `spec_owner_approval_requests` row, fires owner-approval email, 302s to `/spec/awaiting-approval`.

Stripe Checkout (hosted Session) is the locked payment UI (resolved per `SPEC-STRIPE-ADDRESS-TAX-SPIKE`, 2026-05-25 — see 07_ROLLOUT.md § Gate resolutions). The session is created with `customer` (pre-filled with the OPS Customer's saved address), `customer_email`, `automatic_tax: { enabled: true }`, `billing_address_collection: 'required'`, `consent_collection: { terms_of_service: 'required' }` (the dedicated ToS mechanism), `phone_number_collection: { enabled: true }`, and `custom_fields` for the optional GST/HST number. The hosted Stripe page allows the customer to edit the pre-filled billing address; the post-Stripe webhook defense (in `/api/shop/webhook`) catches any QC leak — refunding, cancelling the project, and adding the buyer to `spec_blocked_buyers`.

**Mobile + reduced motion:** standard. No animation beyond the OPS-baseline 200ms field-focus transitions.

## `/spec/intake/[token]` — custom intake form

Token-gated form, link emailed after deposit (Path A) or after owner approval + buyer checkout (Path B). Single-page with autosave per field.

**Sections:**

1. **Welcome** —
   ```
   // INTAKE READY
   [Tier] build file opened for [company].
   This intake takes 30-45 min. Complete at your pace. Save and return anytime.
   ```
   (Tactical OPS voice; no "Hey [name]" warm openings.)

2. **Business basics** — company name (pre-filled if existing OPS subscriber), legal entity type, years operating, primary trade, secondary trades, service area (cities/regions). Quebec checks: if Customer has a Quebec billing address, head office, operating address, establishment, or material SPEC use in Quebec, hard block with explanation. The pre-payment billing province check remains mandatory, but it is not the only eligibility rule.

3. **Team** — team size, roles (owner, admin, crew leads, field crew), seasonal vs year-round

4. **Money** — revenue band (range, optional), avg job size, typical payment terms with customers

5. **Current tools** — multi-select (ServiceTitan, Jobber, Buildertrend, FieldEdge, Housecall Pro, QuickBooks, paper, etc.) + free-text. Per tool: "what works, what doesn't"

6. **Workflow** — multi-stage textarea: "Walk us through how a job goes from first lead to invoice paid." Examples shown.

7. **Pain points** — top 3 pain points (free-text)

8. **Success in 90 days** — "What would 'amazing' look like 90 days from now?"

9. **Regulated workflow attestation** — explicit yes/no checkboxes for each excluded category (PHI/PHIPA, PCI raw card capture, regulated credit, surveillance, CASL-violating bulk messaging). If any are checked, intake submission is blocked with explanation + path to a refund per §3 of [01_BUSINESS_MODEL.md](01_BUSINESS_MODEL.md) (pre-discovery row).

10. **Existing process docs** — file upload (Supabase Storage bucket `spec-intake/{spec_project_id}/`)

11. **Anything else** — free-text

12. **Discovery scheduling** — Calendly/Cal.com embed at the end

**Solo buyer addition:** No-company buyer handling is locked (see 07_ROLLOUT.md § Gate resolutions → `SPEC-NO-COMPANY-BUYER-FLOW-LOCK`, 2026-05-25). A buyer without `users.company_id` cannot reach this intake form — they are intercepted at the "Pay Deposit" click by `resolveSpecCompanyForProject()` and redirected to OPS-Web `/setup?returnTo=/spec?tier=X` where the company is created via the existing `step='company'` flow. By the time the buyer lands on the intake form, `spec_projects.linked_company_id` is populated and the intake form does NOT need a company-setup section.

**Submission:**
- Updates `spec_projects.intake_completed_at`
- Stores `intake_responses` JSONB
- Fires `spec.intake_completed_customer` email + Jackson notification
- Server-side conversion event: `intake_submitted`

## `/spec/confirmation?session_id=...`

After Stripe payment success (Path A directly; Path B after the buyer used their post-approval checkout token).

**Content (per-tier since Tier Model v2 — 2026-07-16 rework):**
- "You're in." header (existing voice)
- Payment summary card — three cells:
  - **Package** — the dictionary designation lockup (`packages.<tier>.designation`, e.g. `SPEC-01 · WORKFLOWS`), Stripe long-form display name as fallback. Never the raw slug.
  - **Paid** — Stripe `amount_total` (deposit + tax), formatted CAD.
  - **Total** — per tier: SPEC-01 `$2,000 [50/50 · second half at delivery]`; SPEC-02 `$7,500 [across 4 checkpoints]`; SPEC-03 `from $25,000 [locks at scope sign-off]` until `spec_projects.locked_total_cents` is set, the locked total `[locked at scope sign-off]` after.
- Founder welcome video (Jackson, 60-90s) — embedded
- Checkpoint rail — per-tier shapes (10_TIER_MODEL_V2 § 2/§ 5), current position highlighted:
  - **SPEC-01 — 3 stops:** Deposit $1,000 → Scope sign-off → Delivery walkthrough $1,000. Scope sign-off renders as the evidence event it is: no amount, "no invoice here" detail, completed chip reads **SIGNED** (payment stops read PAID). Plain 01/02/03 ordinals — SPEC-01 checkout copy never sold P-language, and a P1/P2/P4 rail reads as a mistake.
  - **SPEC-02 — 4 stops:** P1-P4, $1,875 each.
  - **SPEC-03 — 4 stops:** P1 fixed $6,250 "against the floor"; P2-P4 render the `—` empty state with "Your total locks here." on P2 until `locked_total_cents` exists, exact thirds (residual cents on P4) after.
  - Status derivation is monotone over `scope_doc_signed_at` / `midpoint_accepted_at` / `walkthrough_completed_at` (a later timestamp completes earlier stops); SPEC-01 ignores midpoint timestamps — no midpoint stop exists in its journey.
  - Per-tier delivery-window line under the rail (dictionary `confirmation.timeline.<tier>`).
  - Malformed/unknown tier metadata degrades to a generic 4-stop rail with no amounts — never invented numbers.
  - Implementation: `ops-site/src/lib/spec/confirmation-schedule.ts` (pure, unit-tested) feeding `SpecMilestoneTimeline`; every amount derives from `lib/spec/pricing.ts` — no local price maps on the page.
- Primary CTA: open intake link
- Secondary CTA: book discovery (greyed until intake done)
- Refund window reminder: "Your 30-day Guarantee Refund window starts on the Walkthrough Date. Exclusions apply."
- Stripe receipt link

## `/account/spec/[id]/request-refund` — customer refund request (Phase 1 minimal)

Minimal customer-accessible route for Guarantee Refund requests. This is not the full project portal. It is buyer/account_holder gated and uses a server route to create a `spec_refund_requests` row with safe fields only:

- `spec_project_id`
- `request_source = 'customer_initiated'`
- `customer_reason_text`
- `is_guarantee_invocation` computed server-side from the Walkthrough Date and exclusions
- `is_goodwill` computed server-side for post-window requests

The route does not expose processing controls, eligibility override fields, internal notes, refund amounts, Stripe IDs, or entitlement toggles. Admin processing remains in `/admin/spec/refunds`.

## `/spec/awaiting-approval` (NEW — Path B intermediate state)

When the buyer is not the account_holder and no Stripe payment session has been created.

**Content:**
- "[Owner name] needs to approve this purchase." header
- "We've sent them an email. Once they approve, you'll get an email with a link to complete payment."
- No CTA — this is a wait state
- Secondary text: "If you don't hear back within 24 hours, ping them or contact us."

## `/spec/owner-approval/[approval_token]` — owner approval (NEW)

When buyer ≠ account_holder, the account_holder receives the notification + email with this link. Server validates the token and the signed-in user (must match `spec_owner_approval_requests.account_holder_user_id`).

**Content:**
- "[Buyer name] requested SPEC [tier] for [Company name] on [date]."
- Tier details + total cost + 4-milestone breakdown
- Reference to the ToS
- Approve / Decline buttons (with confirmation modal on Decline)

**On approve:**
- `spec_owner_approval_requests.status = 'approved'`
- `spec_projects.status = 'awaiting_deposit'`
- `owner_approved_at` set
- **`spec_acceptance_events` row written with `event_type = 'owner_purchase_approved'`**, `accepted_by_user_id = account_holder_user_id`, IP, user agent, signature method, `payload_hash = approved_tos_version_hash`. This is the binding acceptance event for the account_holder. The buyer's `tos_accepted` is a separate event recorded later at Stripe payment completion. Both rows live in the dispute evidence chain.
- Short-lived `buyer_checkout_token_hash` written; plaintext emitted in the email link (24h expiry)
- `spec.owner_approval_granted` email fires to the buyer with the checkout link
- Account_holder sees confirmation screen

**On decline:**
- `spec_owner_approval_requests.status = 'declined'`
- `spec_projects.status = 'cancelled'`, `cancellation_reason = 'owner_declined'`
- Buyer notified via `spec.owner_approval_declined`
- No money has moved → no refund needed
- Account_holder sees confirmation screen

## `/spec/checkout/[buyer_checkout_token]` (NEW — Path B final step)

The link the buyer receives after the account_holder approves. Server bcrypt/argon2-hashes the URL token, compares to `spec_owner_approval_requests.buyer_checkout_token_hash`, validates the buyer is signed in, checks `buyer_checkout_expires_at > now()`, then creates the approved Stripe payment session and redirects. Token is single-use (the request row's status moves to a consumed state on session creation).

If expired or already-used: friendly error page with a "Request a new approval" CTA that re-triggers the Path B flow.

## `/legal?page=spec-terms` — SPEC Terms of Service (NEW tab on existing page)

The existing `/legal` page already supports `terms / privacy / eula / dpa` tabs via the `VALID_TABS` constant in `src/app/legal/page.tsx`. Add `spec-terms` to `VALID_TABS` and register a `legalDocuments.spec-terms` entry in `src/lib/legal-content.ts` (content per [06_CONTRACT_AND_EMAILS.md](06_CONTRACT_AND_EMAILS.md)).

Build-time hash of the spec-terms commit is stored as an exported constant. The approved Stripe payment flow uses this hash as the accepted version. New commit = new hash = new acceptance value for future customers.

The existing Privacy Policy tab gets a Phase 1 update to cover SPEC-specific data (intake responses, file uploads, scope docs, satisfaction surveys, communications log). The DPA tab is referenced by the spec-terms ToS as the data-processing contract.

## Voice + content guidance

Per `ops-copywriter` skill and OPS brand:
- Terse, tactical. "// OPERATOR :: JACKSON", not "Welcome back!"
- No emoji, no exclamation points
- Sentence case for content, UPPERCASE for authority
- Numbers always JetBrains Mono, tabular-lining, slashed zero. Always formatted ("$1,000" not "$1000.00")
- Empty states: `—`, not "N/A"
- All copy must trace through `ops-copywriter` skill before shipping
- Tactical email subject lines per OPS voice: `SPEC INTAKE WAITING`, `SPEC PAUSED`, `REFUND PROCESSED` (UPPERCASE for authority — see [06_CONTRACT_AND_EMAILS.md](06_CONTRACT_AND_EMAILS.md))

## Spanish dictionary update

`src/i18n/dictionaries/es/spec.json` must receive the same content revisions as English:
- All "$1,500 deposit" / "$4,250 deposit" / "$9,000 deposit" lines become 25% values: `$750 / $2,125 / $4,500`.
- "50% deposit" / "50% restante" language stripped.
- `proof.stat1` through `proof.stat4` removed (the four unverified-stat keys).
- FAQ block aligned to the English FAQ list above (translated).
- Step 3 copy changed to mention "4 pagos" / "checkpoints" rather than the old "50% / 50%" framing.
- "Standing Behind The Work" section translations added.

## SEO + AI-discovery additions

- New JSON-LD types on `/spec`:
  - `Service` (custom software development service)
  - `Offer` with `priceSpecification` per tier — `price` reflects P1 deposit (25% of total), `priceCurrency='CAD'`
  - `FAQPage` for the FAQ section (now visible in initial HTML)
  - `BreadcrumbList` (existing — keep)
- Internal links to `/compare` (vs competitors), `/industries` (per-trade), `/platform` (product overview)
- Body-copy mentions of ServiceTitan, Jobber, Buildertrend by name (AI-discovery hooks)
- Per-trade SPEC landing pages (`/spec/for-roofers`, etc.) — deferred to Phase 3; may move up
