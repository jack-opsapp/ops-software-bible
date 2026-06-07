# OPS SPEC Phase 1 Paid Validation Launch

**Date:** 2026-06-07  
**Launch window:** Week of 2026-06-08, with a 14-day paid validation run  
**Decision:** Target full Phase 1 live-deposit launch, not Phase 0 conversation-only  
**Budget cap:** 1,500 CAD in Google Search spend for the first 14 days  
**Primary goal:** Validate whether contractors will pay a real SPEC deposit for custom OPS build work.

## 1. Launch Thesis

OPS SPEC should launch as a controlled market test, not as an unrestricted public rollout. The campaign should make an honest attempt to sell live SPEC engagements: qualified traffic arrives on `/spec`, selects a tier, passes the eligibility gate, pays a deposit, completes intake, and books discovery.

The test succeeds if it produces either:

- 2-5 paid deposits within the two-week window, or
- clear evidence that qualified buyers are moving deep into the funnel but blocking at a specific fixable step.

The test fails if paid traffic is meaningful and qualified but does not create deposit intent, checkout starts, direct inquiries, default OPS signups, or strong workflow-specific conversations.

## 2. Operating Guardrails

- Spend cap is 1,500 CAD total for the first 14 days.
- Run Google Search only for the first test. No Performance Max, display, YouTube, Meta, or broad-match expansion before the first readout.
- Target Canada and exclude Quebec.
- Published SPEC capacity should remain capped at 5 visible slots.
- `SPEC_LIVE_DEPOSITS_ENABLED` remains false until all launch blockers in § 9 pass.
- Every launch metric must separate production traffic from test traffic using `is_test = false`.
- Do not lower prices during the first 72 hours unless the funnel proves a price-specific block.
- Review the dashboard daily during the 14-day window.

## 3. Current Pricing Baseline

The launch uses the current Phase 1 pricing model.

| Tier | Total | Deposit | Primary signal |
|---|---:|---:|---|
| Setup | 3,000 CAD | 750 CAD | Workflow configuration demand |
| Build | 8,500 CAD | 2,125 CAD | Custom module demand |
| Enterprise | 18,000 CAD | 4,500 CAD | Multi-module operating-system demand |

All tiers use the locked 25 / 25 / 25 / 25 milestone structure.

## 4. Pricing Decision Rules

Pricing changes must be based on funnel evidence, not emotion.

| Signal | Interpretation | Action |
|---|---|---|
| Low impressions | Keyword volume or targeting problem | Do not change price |
| Impressions but low CTR | Ad copy or keyword intent problem | Rewrite ads / tighten keywords |
| Clicks but weak `/spec` engagement | Landing page or message problem | Fix page before price |
| Package expansion but no deposit click | Offer clarity or package mismatch | Improve package copy / proof |
| Deposit click and billing start but no checkout open | Eligibility, trust, or form friction | Fix gate and reassurance |
| Checkout open but no deposit paid | Price, trust, tax, or payment friction | Review recordings and Stripe data |
| 2-5 paid deposits in 14 days | Directionally valid pricing | Hold pricing |
| More than 5 paid deposits or waitlist pressure | Price likely too low or capacity too open | Raise Build/Enterprise 15-25% |
| Qualified traffic and strong engagement but no deposit intent | Price may be too high or trust proof too weak | Add founder proof first; consider smaller deposit second |

Lowering price is a last move. First prove the traffic is qualified, the page is clear, and the checkout is trusted.

## 5. Campaign Design

### 5.1 Channel

Use Google Search for the first launch window because it captures active intent. Campaigns should focus on contractors looking for trade software, job management tools, field service workflow software, and custom software for trade businesses.

### 5.2 Budget

- Total cap: 1,500 CAD.
- Daily average cap: about 107 CAD/day across 14 days.
- Pause rules:
  - Pause if spend exceeds 60% of budget with zero qualified on-page signals.
  - Pause any keyword that spends 100 CAD with no package expansion, deposit click, inquiry, or default OPS signup.
  - Pause any search term that clearly indicates consumer, student, job seeker, competitor employment, free template, or non-trade intent.

### 5.3 Conversion Ladder

Google Ads should receive a conversion ladder, not only the final deposit event.

| Event | Optimization role | Value |
|---|---|---:|
| `/spec` qualified visit | Diagnostic only | 0 |
| package expanded | Micro-conversion | 5 |
| pay deposit click | High-intent conversion | 50 |
| billing address submitted | High-intent conversion | 100 |
| checkout opened | High-intent conversion | 150 |
| deposit paid | Primary conversion | deposit amount |
| intake submitted | Quality conversion | deposit amount |
| discovery booked | Quality conversion | deposit amount |
| default OPS signup from SPEC | Secondary win | estimated first-year subscription value |

The campaign should not optimize directly on low-value visits once enough deeper events exist.

## 6. Analytics Requirements

The launch requires a SPEC-specific analytics command page inside OPS-Web admin. It should be built as an operator cockpit, not a generic analytics dashboard.

### 6.1 Route

Recommended route:

`/admin/spec/analytics`

If the SPEC admin surface has not yet been merged into the active shipping branch, this route ships with that reconciliation work and is gated by `private.is_spec_operator()`.

### 6.2 Data Sources

| Source | Current state | Required launch state |
|---|---|---|
| `spec_projects` | Live table exists; rows are currently 0 | Read project status, tier, deposit, attribution, intake, discovery, `is_test` |
| `conversion_event_outbox` | Live table exists; rows are currently 0 | Read all SPEC funnel events and export raw payloads |
| `ads_daily_account` | Live table exists; rows are currently 0 | Daily spend, clicks, impressions, conversions |
| `ads_daily_campaign` | Live table exists; rows are currently 0 | Campaign-level spend and conversion performance |
| `ads_daily_keyword` | Live table exists; rows are currently 0 | Keyword performance and waste detection |
| Google Ads live API | Admin client exists | Pull current-day data and conversion action breakdown |
| GA4 Data API | Admin client exists | Pull `/spec` traffic, source, page path, device, engagement |
| Vercel Analytics | Marketing helper emits Vercel events | Use as supporting page-event source |
| Stripe | SPEC webhook writes deposit completion | Reconcile deposit-paid totals against Stripe |

### 6.3 Funnel Events

The launch funnel must support these canonical event names:

- `spec_page_view`
- `spec_package_expand`
- `pay_deposit_click`
- `billing_address_submitted`
- `quebec_rejected`
- `owner_approval_requested`
- `owner_approval_granted`
- `stripe_checkout_opened`
- `stripe_checkout_completed`
- `intake_started`
- `intake_submitted`
- `discovery_booked`
- `spec_to_default_signup`
- `refund_invoked`

The code already includes server-side SPEC conversion event names for most deposit and intake steps. It does not yet prove a complete client-side page-view/package-expansion/default-signup bridge.

### 6.4 Metrics

The analytics page should show:

- Spend used vs 1,500 CAD cap.
- Remaining budget.
- Impressions, clicks, CTR, CPC.
- `/spec` sessions, engaged sessions, bounce rate, device split.
- Funnel conversion rate by step.
- Cost per package expansion.
- Cost per deposit click.
- Cost per checkout open.
- Cost per paid deposit.
- Deposit revenue collected.
- Pipeline value booked by tier.
- Default OPS signups attributed to SPEC.
- Search terms wasting spend.
- Campaigns or keywords producing qualified behavior.
- Export freshness and data-latency warnings.

Numbers must be formatted, mono, and scoped to selected date range.

### 6.5 Visualization Layout

The admin page should be dense and operational:

1. **Command strip:** spend, paid deposits, checkout opens, default OPS signups, budget remaining.
2. **Funnel:** horizontal step funnel from visit to discovery booked.
3. **Spend vs signal:** daily bar/line pairing spend with deepest conversion reached that day.
4. **Campaign/keyword table:** sorted by spend, with CTR, CPC, conversions, and waste flags.
5. **Traffic table:** `/spec` sources, devices, top paths, and default OPS crossover.
6. **Raw event ledger:** filterable event stream for SPEC events and project IDs.
7. **Export rail:** CSV and JSON export buttons for the whole readout package.

Use existing OPS-Web admin chart components and OPS design-system tokens. Do not introduce a new dashboard design language.

## 7. Exportable Raw Data

The export must let an external analysis agent reconstruct the full launch story without database access.

### 7.1 Export Package

The admin page should expose one ZIP download containing:

- `manifest.json`
- `ads_daily_account.csv`
- `ads_daily_campaign.csv`
- `ads_daily_keyword.csv`
- `ga4_spec_traffic.csv`
- `conversion_event_outbox.csv`
- `spec_projects.csv`
- `spec_funnel_summary.csv`
- `default_ops_crossover.csv`
- `readme.md`

### 7.2 Manifest

`manifest.json` must include:

- export generated timestamp
- date range
- environment
- timezone
- campaign budget cap
- currency
- included tables
- row counts
- known data latency
- whether Google Ads live API was configured
- whether GA4 was configured
- whether conversion sender dispatch was active

### 7.3 Privacy Boundary

Raw exports may include emails, phone numbers, billing province, attribution, and project status because the owner may send them to an analysis agent. The export UI must label the file as sensitive operational data. Do not include intake free-text responses or uploaded file contents in the default analytics export.

## 8. Default OPS Conversion Capture

SPEC traffic can still validate OPS if visitors decide they need the default software rather than bespoke work. That is a win and must be tracked.

Required events:

- `spec_default_ops_cta_click`
- `spec_default_ops_signup_started`
- `spec_default_ops_signup_completed`
- `spec_default_ops_trial_activated`

Attribution should preserve:

- original `/spec` landing URL
- UTM fields
- `gclid`
- `fbclid`
- selected package, if any
- last SPEC interaction before default signup

The SPEC analytics page must report these separately from SPEC deposits.

## 9. Hard Launch Blockers

Full Phase 1 launch is blocked until every item below passes.

1. SPEC admin/operator surface is reconciled into the active shipping OPS-Web branch.
2. `/admin/spec/analytics` exists, is gated by `private.is_spec_operator()`, and can export the raw readout package.
3. Google Ads account sync is configured and writes non-test rows to ads history tables.
4. GA4 is configured for opsapp.co and can report `/spec` traffic.
5. SPEC conversion sender is no longer a stub for Google Ads Enhanced Conversions at minimum.
6. `spec_to_default_signup` attribution is implemented and visible in the admin page.
7. `ops-site` production build passes with real Vercel environment variables.
8. `ops-web` production build passes on the actual shipping branch that contains SPEC admin.
9. Stripe test-mode deposit succeeds end to end for account-holder purchase.
10. Owner-approval path succeeds end to end.
11. Quebec rejection succeeds before Stripe and post-Stripe defense is verified.
12. Refund path is verified in test mode.
13. Final SPEC ToS / Privacy / DPA are live and linked in Stripe Checkout.
14. Supabase security advisor warnings are triaged so no paid launch runs against known public-data exposure.
15. `SPEC_LIVE_DEPOSITS_ENABLED` is flipped only after all evidence is recorded.

## 10. Customer-Facing Page Review

Before campaign activation, run a production-facing browser review for:

- `/spec`
- package expansion states
- package CTA labels
- OPS Board capacity display
- normal OPS signup crossover links
- billing address form
- Quebec rejection state
- owner approval request state
- owner approval approval/decline state
- checkout token page
- Stripe Checkout handoff
- confirmation page
- intake form
- legal tabs for SPEC terms, privacy, and DPA

Review criteria:

- The value proposition is clear in the first viewport.
- The visitor understands that SPEC is custom work built inside OPS.
- The visitor understands default OPS is available without buying SPEC.
- Pricing, deposit, total, guarantee, and milestone terms are not ambiguous.
- Quebec exclusion is clear without sounding hostile.
- The page feels like OPS: tactical, direct, trustworthy, not a startup splash page.
- Mobile layout works for a contractor on a phone.
- Every CTA has one clear next action.
- Analytics events fire at the expected interaction points.

## 11. Operational Daily Review

During the 14-day test, review these daily:

- spend used
- impressions
- clicks
- CTR
- CPC
- top search terms
- `/spec` engaged sessions
- package expansion rate
- deposit click rate
- billing submission rate
- checkout open rate
- deposit-paid count
- default OPS signup count
- inquiry count
- disqualified Quebec/prohibited-workflow count
- current capacity and booked slots
- raw notes on page friction or buyer questions

Daily decisions should be limited to:

- pause wasteful keywords
- add negative keywords
- adjust ad copy
- fix obvious page friction
- raise price if demand exceeds capacity
- leave pricing alone if evidence is inconclusive

## 12. Cost Transparency

The launch has direct and indirect costs:

- Google Ads: capped at 1,500 CAD for the first 14 days.
- Stripe: card processing, invoicing, and Stripe Tax costs apply to deposits, milestone invoices, refunds, and tax calculation.
- Vercel: hosting, builds, serverless routes, analytics, and cron usage may increase during the campaign.
- SendGrid: transactional and lifecycle email volume increases with deposits, owner approvals, intake reminders, and confirmations.
- Google Ads API / GA4 API: API usage and credential management must be configured before launch.
- Legal: counsel review is recommended before scaling beyond the first controlled test; cost is unknown until scoped.

Do not claim the validation run is free or cheap. It is a capped paid test with deliberate downside control.

## 13. Acceptance Criteria

The Phase 1 paid validation launch is ready when:

- A production build of `ops-site` passes with real launch env.
- A production build of the shipping `ops-web` branch passes with SPEC admin and analytics.
- Supabase SPEC schema, RLS posture, cron, and storage are verified live.
- Google Ads sync and GA4 reads are verified with non-test data.
- SPEC conversion outbox rows are dispatched to Google Ads, not only stored.
- The admin analytics page displays launch metrics and exports raw data.
- Production customer-facing pages pass desktop and mobile browser review.
- Stripe test-mode proof covers account-holder purchase, owner approval, Quebec rejection, confirmation, intake, and refund.
- Final legal pages are live and linked from checkout.
- The daily operating checklist is ready for the 14-day campaign.

## 14. Implementation Decomposition

This launch spec should become separate implementation plans, because it spans independent subsystems:

1. **Code readiness and branch reconciliation:** get SPEC admin/operator surface into the shipping OPS-Web branch and make builds green.
2. **Analytics instrumentation:** complete SPEC client/server funnel events, default OPS crossover attribution, and Google conversion dispatch.
3. **SPEC analytics admin page:** build `/admin/spec/analytics`, metric queries, charts, ledgers, and exports.
4. **Customer-page review and copy/design corrections:** browser-audit `/spec` and related pages, then fix friction.
5. **Launch operations:** configure Google Ads, GA4, Stripe live/test proof, legal links, budget caps, and daily review cadence.

Each plan should be independently testable and should preserve existing dirty worktree state.
