# Cross-Platform Analytics Reliability & Growth Measurement Implementation Plan

> **For Codex:** REQUIRED SKILL: Use `custom-skills:executing-plans` to execute this plan task-by-task. Use `supabase:supabase` for every database action, the OPS UI skill stack for the admin surface, and `superpowers:verification-before-completion` before any completion claim.

**Goal:** Give OPS one trustworthy view of how people discover the marketing site, web app, and iOS app; which sources produce real companies; whether those companies reach first value; and whether every source is fresh and correctly measured.

**Architecture:** Keep source systems in their proper roles. Google Search Console owns organic search demand. GA4 owns anonymous visit behaviour on the two web surfaces. App Store Connect owns iOS storefront discovery and downloads. Supabase owns customer identity, first-party attribution, activation, product behaviour, and revenue. A normalized acquisition layer reconciles those sources into one founder view without claiming user-level attribution where Apple or privacy controls make it impossible.

**Tech stack:** Next.js App Router, TypeScript, SwiftUI, Firebase Analytics, Google Analytics Data API, Google Search Console API, App Store Connect Analytics API, Supabase/Postgres, Vercel Cron, Vitest, XCTest, Playwright.

---

## 1. Decision

Build one growth measurement system with three distinct truth layers:

1. **Discovery truth** — Search Console, GA4, and App Store Connect.
2. **Customer truth** — Supabase companies, projects, tasks, billing events, and `trial_attributions`.
3. **Behaviour truth** — Supabase `analytics_events`; Firebase receives only the small conversion set required for Google optimization.

The founder-facing question is not “How much traffic did we get?” It is:

> Which sources created companies that reached first value, and can the number be trusted?

Traffic remains visible as the beginning of the funnel, never the headline result.

### Non-goals

- Do not add Mixpanel, Amplitude, PostHog, AppsFlyer, or another paid analytics vendor.
- Do not merge the three GA4 properties into one property.
- Do not treat GA4 as the source of truth for signups, activation, paid conversion, or revenue.
- Do not claim deterministic web-click-to-iOS-install attribution where no deterministic identifier exists.
- Do not ask for ATT/IDFA while paid iOS acquisition is dormant.
- Do not overwrite raw legacy self-reported referral values to make the data appear cleaner.

---

## 2. Verified Baseline — 2026-08-30

This baseline is the release comparison point. Re-run it before implementation and after customer-live deployment.

| Surface / dataset | Verified state | Meaning |
|---|---|---|
| Marketing Search Console, last 90 days | 126 clicks, 26,864 impressions, 0.47% CTR, average position 17.52 | A small but real organic audience exists. |
| Marketing Search Console, last 28 days | 41 clicks, 5,610 impressions, 0.73% CTR, average position 20.08 | Roughly 1.5 clicks/day; flat, not zero. |
| Marketing GA4 | Live tag contains `G-HKM7RWVTDV` plus a raw newline; production throws a script syntax error | GA4 site sessions and engagement are not trustworthy. |
| Web app GA4, last 90 days | 116 sessions; 13 Organic Search; 3 engaged organic sessions | Some users enter the web app organically, but this is not yet connected to trial/activation truth. |
| iOS Firebase/GA, last 90 days | 59 active users, 1,384 sessions, 22,609 events | iOS has meaningful product use, but Firebase acquisition reports Direct/Unassigned. |
| `analytics_events` | 16,027 rows; 15,994 iOS and 33 web; web stopped 2026-05-14 | Product analytics is effectively iOS-only today. |
| `analytics_events` identity | 94.5% user/company; 10.3% role/plan | Identity is mostly present, segmentation context is not. |
| `trial_attributions` | 64 rows, 3 paid, 1 with UTM/landing data, 0 known channels | The table exists, but live acquisition capture is not connected. |
| Companies self-report | 7 legacy values; 48 current non-deleted companies blank | The iOS question exists and persists, but the signal is not reconciled into attribution. |
| App Store Connect | 4,447 engagement rows through 2026-08-21; 0 download rows | The connector is partly alive but cannot measure installs/download conversion. |
| App Store sync | Failed 2026-08-30 because `APP_STORE_COMMERCE` is no longer a valid API filter; Apple now expects `COMMERCE` | This is a current production connector defect. |
| Paid traffic | No recent paid channels in GA4 | Consistent with ads being off for several months. |

### Current data classification

**Computable now**

- Organic search demand: impressions, clicks, CTR, average position, queries, and landing pages from Search Console.
- iOS product behaviour and current active-user counts from Supabase/Firebase.
- Trial count and paid-company count from Supabase.
- App Store discovery engagement through the last successful finalized date.

**Partial / misleading now**

- Marketing-site sessions and engagement because the production tag is broken.
- Web product adoption because its Supabase event stream is stale.
- iOS organic acquisition because App Store downloads are missing and App Store Search is not split from Apple Search Ads.
- Trial-to-source conversion because every trial is `unknown`.

**Missing now**

- Search Console and GA4 daily warehouse history with freshness state.
- Safe cross-subdomain first-touch capture.
- A secure, reliable web product-event ingest path.
- A reconciled source → trial → activation → paid funnel.
- One data-health surface that says whether each number is usable.

---

## 3. Metric Contract

These definitions are the contract. Dashboards and APIs must not invent alternate versions.

| Metric | Definition | Authoritative source | Freshness |
|---|---|---|---|
| Search impressions | Google search-result impressions for `opsapp.co` | Search Console | D-3 finalized |
| Search clicks | Clicks from Google search results to `opsapp.co` | Search Console | D-3 finalized |
| Organic site sessions | GA4 sessions where default channel group is Organic Search, marketing property only | GA4 property `475051117` | D-1/D-2 |
| Web-app organic entries | GA4 Organic Search sessions entering `app.opsapp.co` | GA4 property `539494652` | D-1/D-2 |
| App Store discovery | Impressions and product-page views by App Store source type | App Store Connect | D-2 finalized |
| App downloads | First-time downloads, with redownloads reported separately | App Store Connect | D-2 finalized |
| Trial started | A real company with a populated trial start date | Supabase `companies` / `trial_attributions` | Real time |
| Activated company | Company creates its first real project within 7 days of trial start | Supabase `projects` joined to company | Real time |
| First value | Company completes its first task or advances its first project into active work within 14 days | Supabase tasks/projects | Real time |
| Paid company | First confirmed paid billing event for the company | Supabase `billing_events` | Real time |
| Product-active company | At least one non-test member produces a qualifying product event in the period | Supabase `analytics_events` | Near real time |
| Attribution coverage | Trials with a classified channel and explicit attribution basis / all trials | Supabase | Real time |

### Attribution precedence

Use the strongest available evidence, never the most flattering source:

1. Verified click ID or deterministic first-party touch.
2. UTM + referrer first touch.
3. App Store source / Apple AdServices when available.
4. Self-reported source (`companies.referral_method`).
5. Direct.
6. Unknown with a stored reason code.

Store `attribution_basis` and `attribution_confidence`; never collapse them into the channel label.

### App Store organic rule

`App Store Search` is not automatically organic because it can include Apple Search Ads. Until spend/campaign data proves the paid share, report it as **App Store search — paid split unavailable**. App Store Browse can be reported separately. Never inflate “organic” by silently assigning all App Store Search to organic.

---

## 4. Target Data Flow

```text
SEARCH CONSOLE ───────────────┐
  queries + landing pages     │
                              │
GA4 MARKETING + WEB APP ──────┼──> RAW DAILY FACTS ──> CHANNEL METRICS ──┐
  sessions + engagement       │                                          │
                              │                                          │
APP STORE CONNECT ────────────┘                                          │
  impressions + views + downloads                                        │
                                                                         ├──> /admin/acquisition
OPS SITE / WEB FIRST TOUCH ─────> TOUCHPOINTS ──> TRIAL ATTRIBUTION ──────┤
IOS SELF-REPORTED SOURCE ───────> companies.referral_method ──────────────┤
                                                                         │
SUPABASE BUSINESS RECORDS ──────> trial + activation + paid truth ────────┤
SUPABASE analytics_events ──────> product behaviour + friction ───────────┘

Every source ──> analytics_sync_runs ──> DATA HEALTH + ALERTS
```

### Property registry

| Key | Surface | Property | Client identifier |
|---|---|---:|---|
| `marketing` | `opsapp.co` | `475051117` | `G-HKM7RWVTDV` |
| `web_app` | `app.opsapp.co` | `539494652` | `G-JJP5SN122V` |
| `ios_app` | Firebase iOS | `514229717` | Firebase configuration |

The server client must require an explicit property key for every report. No default property is allowed.

---

## 5. Repository and Release Strategy

This is a large cross-repository initiative. Execute in isolated worktrees and keep deployment boundaries separate.

- **OPS-Site:** start from the current intended `main`, then reconcile the existing untracked `MarketingAnalytics.tsx` and `marketing-analytics.ts` work. Do not delete, stash, or overwrite it.
- **OPS-Web:** start from local `main`, which contains the App Store connector. The currently checked-out `feat/inbox-dark-launch` branch is behind that code and has unrelated WIP.
- **OPS-iOS:** use an isolated worktree and worktree-local DerivedData. Run iOS builds serially after checking active build processes.
- **Software Bible:** update `21_ANALYTICS_SYSTEM.md` only when implementation behaviour is verified.

Release each repository independently. A local commit, local-main integration, push, Vercel deployment, App Store release, runtime proof, and customer-live proof are separate states.

---

## 6. Workstream A — Repair Measurement Before Adding Features

### Task A1: Harden GA measurement IDs on both web surfaces

**OPS-Site files**

- Create: `ops-site/src/lib/analytics/ga-config.ts`
- Modify: `ops-site/src/components/layout/GoogleAnalytics.tsx`
- Modify: `ops-site/src/app/layout.tsx`
- Create: `ops-site/src/components/layout/__tests__/google-analytics.test.tsx`
- Create: `ops-site/src/lib/analytics/__tests__/ga-config.test.ts`

**OPS-Web files**

- Create: `ops-web/src/lib/analytics/ga-config.ts`
- Modify: `ops-web/src/components/layout/GoogleAnalytics.tsx`
- Create: `ops-web/tests/unit/google-analytics-config.test.ts`

**Implementation**

1. Add a pure `parseMeasurementId(value)` helper that trims whitespace, validates `^G-[A-Z0-9]+$`, and returns `null` when invalid.
2. Serialize the validated value with `JSON.stringify`; never interpolate raw environment text into executable JavaScript.
3. URL-encode the script query parameter.
4. Fail the production build when the configured value is non-empty but invalid.
5. Keep the component absent when analytics is intentionally unconfigured in local/test environments.
6. Remove `page_search` from marketing event payloads and sanitize outbound URLs to origin + pathname before analytics dispatch.
7. Template logged-in web routes before GA dispatch so project/client/task UUIDs never enter GA.

**Environment corrections**

- OPS-Site `NEXT_PUBLIC_GA_MEASUREMENT_ID=G-HKM7RWVTDV`
- OPS-Web `NEXT_PUBLIC_GA_MEASUREMENT_ID=G-JJP5SN122V`
- Remove trailing newlines and spaces in every Vercel environment.

**Proof**

- Tests cover newline, quotes, invalid IDs, missing IDs, and the exact generated config call.
- Production browser console has no GA syntax error.
- `window.dataLayer` exists.
- One DebugView page view lands in the correct property for each surface.
- The same page view does not land in the other property.

**Commit**

- `fix(analytics): harden GA configuration on web surfaces`

### Task A2: Replace the single-property GA Data API client

**Files**

- Create: `ops-web/src/lib/analytics/ga4-properties.ts`
- Modify: `ops-web/src/lib/analytics/ga4-client.ts`
- Modify: `ops-web/src/lib/admin/analytics-queries.ts`
- Modify: `ops-web/src/app/admin/analytics/page.tsx`
- Modify: `ops-web/src/app/admin/acquisition/page.tsx`
- Modify: `ops-web/src/app/api/admin-debug/route.ts`
- Extend: `ops-web/src/lib/analytics/__tests__/ga4-client.test.ts`

**Implementation**

1. Introduce `GA4PropertyKey = "marketing" | "web_app" | "ios_app"`.
2. Replace `GA4_PROPERTY_ID` with:
   - `GA4_MARKETING_PROPERTY_ID=475051117`
   - `GA4_WEB_APP_PROPERTY_ID=539494652`
   - `GA4_IOS_PROPERTY_ID=514229717`
3. Require every report helper to accept a property key. Remove the implicit default.
4. Use a dedicated read-only Analytics service account instead of reusing broad Firebase Admin credentials where possible.
5. Grant that identity Viewer access to all three GA properties.
6. Keep property access failures visible; do not convert a permission error into a zero.

**Proof**

- Unit tests verify property selection and whitespace rejection.
- One read-only Data API query succeeds for each property.
- `/admin/analytics` reads marketing, never iOS.
- `/admin/acquisition` labels the property/source used for every panel.

**Commit**

- `refactor(analytics): make GA property selection explicit`

### Task A3: Repair App Store download ingestion

**Files on OPS-Web `main`**

- Modify: `ops-web/src/lib/admin/app-store-sync.ts`
- Extend: `ops-web/tests/unit/app-store-sync.test.ts`
- Extend: `ops-web/tests/unit/app-store-sync-outage.test.ts`
- Update after proof: `ops-software-bible/04_API_AND_INTEGRATION.md`

**Implementation**

1. Replace the invalid API filter `APP_STORE_COMMERCE` with Apple's current `COMMERCE` category.
2. Preserve `APP_STORE_COMMERCE` as the internal persisted taxonomy only if existing rows require compatibility; API constants and stored labels must be deliberately separate.
3. Add a contract test for Apple's accepted category vocabulary.
4. Resume the cursor from the failed state and backfill all unprocessed commerce instances.
5. Recalculate `asc_conversion_daily` only after download facts exist.

**Proof**

- Sync status becomes `complete`.
- `asc_downloads` is non-empty with a finalized maximum reporting date.
- Re-running the same segments produces no duplicates and no total drift.
- One finalized day matches App Store Connect within the documented privacy/restatement caveat.

**Commit**

- `fix(app-store): restore commerce report ingestion`

### Task A4: Correct GA/Firebase key events

**Admin actions**

- Remove `session_start` as a key event in the iOS property.
- Keep the deliberate OPS-managed conversion set: `sign_up`, `begin_trial`, `complete_onboarding`, `create_first_project`, and `purchase`.
- Accept GA4's locked app defaults (`first_open`, `in_app_purchase`, `app_store_subscription_convert`, and `app_store_subscription_renew`) as Google-managed property state. Do not count them as OPS business outcomes or require an operator to unstar them.
- Treat CTA clicks, screen views, app opens, and logins as diagnostics, not conversions.
- Record the before/after property configuration in `21_ANALYTICS_SYSTEM.md` after live verification.

**Proof**

- Key-event totals no longer rise once per session.
- Each business conversion can be reconciled to a Supabase record.

---

## 7. Workstream B — First-Party Attribution Foundation

### Task B1: Add the normalized acquisition schema

**Files**

- Create with `supabase migration new growth_analytics_foundation`:
  `ops-web/supabase/migrations/<generated>_growth_analytics_foundation.sql`
- Regenerate: `ops-web/src/lib/types/database.types.ts`
- Create: `ops-web/tests/integration/growth-analytics-schema.test.ts`

**Schema changes**

1. Extend `trial_attributions` with:
   - `referrer`
   - `first_touch_at`
   - `self_reported_source`
   - `attribution_basis`
   - `attribution_confidence`
   - `classification_reason`
   - `capture_version`
2. Extend `analytics_events` with:
   - `schema_version`
   - `environment`
   - `received_at default now()`
3. Create `search_console_daily` at the API's native date/query/page/country/device grain.
4. Create `ga4_daily_acquisition` keyed by property/date/channel/source/medium/campaign/landing path.
5. Create `channel_map` for raw-source-to-canonical-channel rules.
6. Create `channel_metrics` as a long-form normalized fact table. Store the exact grain and source system with every metric to prevent accidental double-counting.
7. Create `touchpoints` for deterministic first-party touches only.
8. Create `analytics_sync_runs` with source, start/finish, status, source maximum date, row count, error, and metadata.
9. Create security-invoker views:
   - `growth_funnel_daily`
   - `growth_channel_performance`
   - `growth_attribution_coverage`
   - `growth_data_health`

**Security**

- Enable RLS on every exposed table.
- Grant no `anon` or ordinary `authenticated` read access to warehouse tables.
- Writes occur through service-role cron/server paths only.
- Admin views use existing admin authorization and security-invoker semantics.
- Run Supabase security and performance advisors after the migration.

**Proof**

- Freshly generated types match the live schema.
- RLS tests prove non-admin clients cannot read raw touchpoints/click IDs.
- View totals reconcile to seeded source rows.
- Migration is idempotent in an isolated database branch before production application.

**Commit**

- `feat(analytics): add growth attribution warehouse`

### Task B2: Capture one first touch across OPS subdomains

**OPS-Site files**

- Create: `ops-site/src/lib/analytics/first-touch.ts`
- Modify: `ops-site/src/components/layout/MarketingAnalytics.tsx`
- Modify carefully: `ops-site/src/middleware.ts`
- Create: `ops-site/src/lib/analytics/__tests__/first-touch.test.ts`

**OPS-Web files**

- Refactor: `ops-web/src/lib/pmf/utm-capture.ts`
- Modify: `ops-web/src/components/pmf/utm-capture-effect.tsx`
- Create: `ops-web/src/lib/pmf/trial-attribution.ts`
- Modify: `ops-web/src/app/api/setup/progress/route.ts`
- Extend: `ops-web/tests/unit/pmf/utm-capture.test.ts`
- Extend: `ops-web/tests/unit/pmf/attribution.test.ts`
- Extend: `ops-web/tests/integration/setup-progress-owner-invariants.test.ts`

**Implementation**

1. Use one versioned, validated first-touch payload on `.opsapp.co`, `Secure`, `SameSite=Lax`, 30-day TTL.
2. Store allowlisted UTM fields, click IDs, canonical landing path, referrer domain, captured time, and anonymous ID. Do not store arbitrary query strings.
3. Exclude internal OPS subdomains from referral classification.
4. Add search-engine referrer classification for Google, Bing, DuckDuckGo, and Yahoo.
5. At company creation, read the cookie server-side and update the trigger-seeded `trial_attributions` row. The row already exists as `unknown`; do not insert and collide.
6. Make the write idempotent and first-touch preserving. A retry may fill blank fields but may not overwrite stronger evidence.
7. Create the corresponding `touchpoints` row in the same server transaction/RPC.
8. Expire raw click IDs after the approved retention window while preserving aggregate channel classification.

**Proof**

- Playwright journey: Google-organic referrer → marketing page → web app → company creation produces `organic_search`, the original landing path, and one touchpoint.
- Direct journey produces `direct`, not `unknown`.
- OPS-site → app.opsapp.co never becomes a referral.
- Repeating company setup does not duplicate or rewrite the first touch.
- No raw query string, email, phone, name, or resource UUID enters GA or the touchpoint payload.

**Commit**

- `feat(attribution): preserve first touch through company creation`

### Task B3: Reconcile the existing iOS self-reported signal

The iOS onboarding already asks “How'd you find us?” in `CompanyNameStepView`, stores a stable `ReferralSource` slug, and writes `companies.referral_method`. Do not add another prompt or another onboarding screen.

**Files**

- Modify: `ops-web/src/lib/pmf/attribution.ts`
- Modify: `ops-web/src/lib/pmf/types.ts`
- Modify: `ops-web/src/lib/pmf/schemas.ts`
- Create: `ops-web/src/lib/admin/referral-normalization.ts`
- Extend: `ops-web/tests/unit/pmf/attribution.test.ts`
- Extend: `ops-ios/OPSTests/OnboardingFunnelAnalyticsTests.swift`

**Implementation**

1. Add canonical channels including `organic_search`, `organic_social`, `referral`, `app_store_search`, `app_store_browse`, `direct`, and `other`.
2. Preserve the raw self-reported slug separately from deterministic attribution.
3. Add a company referral update trigger/server write that stamps `trial_attributions.self_reported_source` without replacing a stronger first touch.
4. Normalize the seven legacy free-text values at read time. Do not rewrite customer-entered history.
5. Add parity tests between `ReferralSource.swift` and the web referral source registry.

**Proof**

- A new iOS owner selecting Google creates a self-reported source visible in trial attribution.
- Deterministic campaign/referrer evidence still wins when present.
- Blank/skipped answers remain explicit, not silently converted to Direct.

**Commit**

- `feat(attribution): reconcile self-reported acquisition source`

---

## 8. Workstream C — Restore Trustworthy Product Behaviour

### Task C1: Secure and harden OPS-Web product-event ingestion

**Files**

- Modify: `ops-web/src/lib/analytics/analytics-types.ts`
- Modify: `ops-web/src/lib/analytics/analytics-service.ts`
- Retire or narrow: `ops-web/src/lib/analytics/analytics-actions.ts`
- Rewrite: `ops-web/src/app/api/analytics/flush/route.ts`
- Create: `ops-web/src/lib/analytics/event-contract.ts`
- Create: `ops-web/src/lib/analytics/event-sanitizer.ts`
- Modify: `ops-web/src/components/providers/analytics-provider.tsx`
- Create: `ops-web/tests/unit/analytics-service.test.ts`
- Create: `ops-web/tests/unit/analytics-sanitizer.test.ts`
- Create: `ops-web/tests/integration/analytics-flush-auth.test.ts`

**Problems to close**

- The beacon route currently accepts an unauthenticated body, trusts supplied user/company IDs, and writes through the service role.
- The in-memory queue loses data on refresh/failure.
- Web events do not carry client IDs, so retries can duplicate.
- Most web screen tracking still calls the disabled Firebase helper rather than Supabase product analytics.

**Implementation**

1. Generate a UUID for every event on the client.
2. Persist the bounded queue locally with a seven-day TTL and a 1,000-event cap.
3. Replace `beforeunload` beacon delivery with authenticated `fetch(..., { keepalive: true })` on visibility/page-hide plus the periodic flush.
4. Verify the Firebase/Supabase token server-side.
5. Resolve user, company, role, and plan on the server. Ignore identity claimed by the client.
6. Validate event name/type/properties against the contract; cap batch size, property count, string length, and payload bytes.
7. Insert by client-generated event ID with idempotent retry semantics.
8. Rate-limit per authenticated user and reject production events from localhost/test builds.
9. Add automatic route-template screen views and migrate existing `analytics.ts` product call sites to `analyticsService`.
10. Keep the Firebase web helper only for deliberate Google conversion events, or remove it if the web app does not need those events.

**Proof**

- Anonymous flush returns 401 and writes zero rows.
- A user cannot attribute an event to another company.
- Retrying an identical event produces one row.
- Offline → online flush restores events in order.
- A production web session produces fresh `platform=web` events with server-resolved identity.
- No PII test corpus passes the sanitizer.

**Commit**

- `fix(analytics): restore secure web product telemetry`

### Task C2: Align iOS Firebase and Supabase contracts

**Files**

- Modify: `ops-ios/OPS/Utilities/AnalyticsManager.swift`
- Modify: `ops-ios/OPS/Utilities/Analytics/AnalyticsService.swift`
- Modify: `ops-ios/OPS/Utilities/Analytics/AnalyticsEventQueue.swift`
- Create: `ops-ios/OPSTests/Analytics/AnalyticsContractTests.swift`
- Create: `ops-ios/OPSTests/Analytics/FirebaseConversionContractTests.swift`
- Update after proof: `ops-ios/ANALYTICS.md`

**Implementation**

1. Keep detailed behaviour in Supabase only.
2. Keep Firebase's deliberate conversion set only; remove duplicated screen/CRUD telemetry from Firebase where it is not needed for ad optimization.
3. Attach the same schema version and stable event IDs as web.
4. Keep the existing offline queue and poison-batch handling.
5. Guard console analytics logs to debug builds and redact identifiers.
6. Add property allowlists and length caps before enqueue.
7. Confirm role/plan hydration so segmentation completeness rises above the current 10.3%.

**Proof**

- Contract tests lock the five Firebase conversion events.
- Supabase receives detailed product events once.
- Release builds do not print user IDs or raw analytics payloads.
- Offline/retry/duplicate tests continue to pass.

**Commit**

- `refactor(analytics): separate iOS product and conversion telemetry`

---

## 9. Workstream D — Daily Source Ingestion and Reconciliation

### Task D1: Add Search Console ingestion

**Files**

- Create: `ops-web/src/lib/analytics/search-console-client.ts`
- Create: `ops-web/src/lib/admin/search-console-sync.ts`
- Create: `ops-web/src/app/api/cron/search-console-sync/route.ts`
- Modify: `ops-web/vercel.json`
- Create: `ops-web/tests/unit/search-console-client.test.ts`
- Create: `ops-web/tests/unit/search-console-sync.test.ts`
- Add fixtures under: `ops-web/tests/fixtures/analytics/search-console/`

**Implementation**

1. Use the dedicated read-only service account and grant it access to the `opsapp.co` Search Console property.
2. Backfill the maximum available history, then pull D-7 through D-3 daily so late restatements converge.
3. Persist query/page/country/device rows at their native grain.
4. Preserve Search Console privacy suppression; never infer hidden query counts.
5. Record every run in `analytics_sync_runs` under `search_console`.
6. Run under `runWithCronWorkloadControl` with cursoring, idempotent upserts, and bounded pages.

**Proof**

- A known date reconciles to the Search Console UI.
- Re-running the same range is a no-op except legitimate restatements.
- The latest finalized date is visible in data health.

**Commit**

- `feat(analytics): ingest organic search performance`

### Task D2: Add GA4 daily acquisition ingestion

**Files**

- Create: `ops-web/src/lib/admin/ga4-acquisition-sync.ts`
- Create: `ops-web/src/app/api/cron/ga4-acquisition-sync/route.ts`
- Modify: `ops-web/vercel.json`
- Create: `ops-web/tests/unit/ga4-acquisition-sync.test.ts`
- Add fixtures under: `ops-web/tests/fixtures/analytics/ga4/`

**Implementation**

1. Pull marketing and web-app acquisition by date, channel group, source, medium, campaign, and sanitized landing path.
2. Pull iOS Firebase events only for conversion QA, not as product/business truth.
3. Backfill available retained history and restate the trailing seven days.
4. Store raw daily facts, then normalize into `channel_metrics` through a single channel map.
5. Record API quota/permission failures as failed sync runs, never zero traffic.

**Proof**

- Each property produces rows tagged with the correct property key.
- Marketing organic sessions and web-app organic entries remain distinguishable.
- A denied property renders a data-health failure and leaves prior facts intact.

**Commit**

- `feat(analytics): warehouse GA acquisition data`

### Task D3: Derive business milestones from records, not tracking calls

**Files**

- Create: `ops-web/src/lib/admin/growth-milestones.ts`
- Create or update via migration: `growth_funnel_daily`, `growth_channel_performance`
- Create: `ops-web/tests/integration/growth-funnel-reconciliation.test.ts`

**Implementation**

1. Derive trial starts from company trial dates.
2. Derive first project and first value from persisted project/task state.
3. Derive first paid from `billing_events`.
4. Use analytics events only to explain behaviour and friction between milestones.
5. Keep web and iOS activation definitions identical because the business record, not the client event, defines success.
6. Add current-period and immediately preceding equal-period comparisons.

**Proof**

- Funnel counts equal direct source-table queries exactly.
- Deleting/retiring a duplicate client event cannot change the company milestone funnel.
- Paid-company count equals distinct companies with confirmed paid events.

**Commit**

- `feat(analytics): derive canonical growth milestones`

---

## 10. Workstream E — One Founder Growth Surface

### Dashboard intent

**Human:** Jackson checking growth between other founder work, not an analyst exploring dimensions.

**Primary task:** See whether earned discovery is creating activated companies and immediately know if any source is broken.

**Feel:** A mission-control readout: calm, dense, decisive. No equal-weight card wall. No decorative data colour. No paid-acquisition acreage while paid spend is zero.

### Four structural variants considered

#### Variant 1 — Hierarchical outcome spine

```text
[ACTIVATED COMPANIES + PERIOD CHANGE]
                |
[DISCOVERY] -> [TRIAL] -> [ACTIVATION] -> [PAID]
                |
[CHANNEL TABLE]
[LANDING PAGE TABLE]
[DATA HEALTH]
```

Strong outcome hierarchy; weak at showing web and App Store discovery differences.

#### Variant 2 — Equal dashboard grid

```text
[KPI] [KPI] [KPI] [KPI]
[SEARCH CHART] [APP STORE CHART]
[FUNNEL]       [CHANNEL DONUT]
[TABLE]        [HEALTH]
```

Scannable but generic. Equal cards make traffic vanity metrics look as important as activation.

#### Variant 3 — Single continuous funnel

```text
[ALL DISCOVERY]
      ↓
[ALL VISITS / DOWNLOADS]
      ↓
[TRIALS]
      ↓
[ACTIVATED]
      ↓
[PAID]
```

Clear, but mathematically dishonest because Search Console clicks, GA sessions, and App Store downloads have different identities and grains.

#### Variant 4 — Outcome spine with source lanes — RECOMMENDED

```text
// GROWTH                         [30D] [ORGANIC]
┌──────────────────────────────────────────────────────┐
│ ACTIVATED COMPANIES     trend     attribution cover │
└──────────────────────────────────────────────────────┘

WEB SEARCH LANE              APP STORE LANE
impressions -> clicks        impressions -> views
-> site sessions -> trials   -> downloads -> trials

┌──────────────────────────────────────────────────────┐
│ TRIAL -> FIRST PROJECT -> FIRST VALUE -> PAID        │
└──────────────────────────────────────────────────────┘

CHANNEL PERFORMANCE TABLE
LANDING / CONTENT PERFORMANCE
SYS :: DATA HEALTH
```

This keeps the business outcome dominant, preserves source-specific math, and gives one place to inspect trust.

### Task E1: Build the normalized admin query layer

**Files**

- Create: `ops-web/src/lib/admin/growth-analytics-types.ts`
- Create: `ops-web/src/lib/admin/growth-analytics-queries.ts`
- Create: `ops-web/src/lib/admin/growth-analytics-export.ts`
- Create: `ops-web/src/app/api/admin/acquisition/overview/route.ts`
- Create: `ops-web/src/app/api/admin/acquisition/search/route.ts`
- Create: `ops-web/src/app/api/admin/acquisition/app-store/route.ts`
- Create: `ops-web/src/app/api/admin/acquisition/health/route.ts`
- Create: `ops-web/tests/unit/growth-analytics-queries.test.ts`
- Create: `ops-web/tests/integration/growth-analytics-auth.test.ts`

**Rules**

- Admin auth on every route.
- Date range and channel filter included in cache keys.
- Every response carries `asOf`, `finalizedThrough`, `coverage`, and source status.
- Missing/failed source data returns an explicit state, never zeros.
- CSV export contains sanitized aggregate data by default. Raw identifiers require a separate explicit admin-only path if ever added.

### Task E2: Rebuild `/admin/acquisition` as the founder view

**Files**

- Modify: `ops-web/src/app/admin/acquisition/page.tsx`
- Replace/refactor: `ops-web/src/app/admin/acquisition/_components/acquisition-charts.tsx`
- Create: `ops-web/src/app/admin/acquisition/_components/growth-overview.tsx`
- Create: `ops-web/src/app/admin/acquisition/_components/source-lanes.tsx`
- Create: `ops-web/src/app/admin/acquisition/_components/company-funnel.tsx`
- Create: `ops-web/src/app/admin/acquisition/_components/channel-performance-table.tsx`
- Create: `ops-web/src/app/admin/acquisition/_components/content-performance-table.tsx`
- Create: `ops-web/src/app/admin/acquisition/_components/data-health-rail.tsx`
- Modify: `ops-web/src/app/admin/_components/sidebar.tsx`
- Create: `ops-web/tests/integration/admin-growth-page.test.tsx`
- Create: `ops-web/tests/e2e/admin-growth.spec.ts`

**Presentation rules**

- Header: `GROWTH`; caption: `ACQUISITION → ACTIVATION → PAID`.
- Hero metric: activated companies, default period 30 days. Channel is a filter; Organic is the default lens once coverage is healthy.
- Search lane: impressions, clicks, CTR, site sessions, trials.
- App Store lane: impressions, product page views, first-time downloads, trials; keep paid-split caveat visible when unresolved.
- Business funnel: trial, first project, first value, paid.
- Channel table is the centerpiece: discovery, trials, activated, paid, conversion, confidence.
- Hide/collapse paid spend panels when recent spend is zero. Do not reserve permanent prime space for dormant ads.
- Data health is always visible but quiet when healthy.
- Use horizontal bars for channel comparison, lines for time trends, and proportional funnel bars for stage conversion. Avoid donut charts for decisions.
- All numbers use JetBrains Mono and formatted values. Empty is `—`.
- Use neutral data tokens; earth tones only for actual status. Steel blue remains CTA/focus only.
- Every chart has a screen-reader table and keyboard-accessible details.
- Motion uses the OPS curve `cubic-bezier(0.22, 1, 0.36, 1)` and honors reduced motion. Do not use the generic visualization skill's spring recommendations.

**Proof**

- Server-rendered initial data and filtered client data reconcile.
- 375, 768, 1024, and 1440 layouts have no horizontal overflow.
- Keyboard, screen-reader, reduced-motion, and contrast checks pass.
- Design-system audit finds no hardcoded colours, spacing, radii, or fonts in new files.
- Screenshot proof covers healthy, partial, failed-source, empty, and provisional states.

**Commit**

- `feat(admin): unify growth analytics around activation`

---

## 11. Workstream F — Data Quality, Privacy, and Operations

### Task F1: Add automated health rules

**Files**

- Create: `ops-web/src/lib/admin/analytics-health.ts`
- Create: `ops-web/src/app/api/cron/analytics-health/route.ts`
- Modify: `ops-web/vercel.json`
- Create: `ops-web/tests/unit/analytics-health.test.ts`

**Health rules**

- GA property permission succeeds for all three properties.
- Marketing and web measurement IDs are valid and mapped to the right properties.
- Search Console finalized-through date is no older than expected D-3.
- GA4 warehouse finalized-through date is no older than expected D-2.
- App Store sync is complete and finalized through expected D-2.
- App Store downloads are not empty when commerce reports exist.
- Web product events are fresh when web app sessions exist.
- Schema-invalid events: zero.
- Duplicate event IDs: zero.
- Unknown attribution: explicit count and reason.
- Trial, activation, paid, and revenue reconciliation deltas: zero.
- PII scan across event properties: zero findings.

Send one persistent admin notification only when a source crosses from healthy to failed. Resolve it automatically when the source recovers. Do not notify on expected source latency.

### Task F2: Privacy and retention controls

**Implementation**

- No email, phone, name, address, free-form notes, auth tokens, or full resource URLs in GA/Firebase/Supabase analytics properties.
- Hashing does not make PII safe for product analytics; do not collect it unless a documented external conversion API requires it.
- Strip query strings and normalize logged-in resource routes.
- Keep click IDs/raw touchpoints only for the approved attribution window, then delete while retaining aggregates.
- Keep `analytics_events` raw rows for 12 months, then retain daily aggregates unless the privacy policy sets a shorter period.
- Honour deletion requests by removing user-linked raw touchpoints/events while preserving non-identifying aggregates where legally allowed.
- Configure Google Consent Mode and cookie behaviour against the approved privacy policy before enabling advertising storage or personalization.
- Do not enable advertising identifiers or ATT while ads remain off.

### Task F3: Update the source of truth

**Files**

- Update: `ops-software-bible/21_ANALYTICS_SYSTEM.md`
- Update: `ops-software-bible/04_API_AND_INTEGRATION.md`
- Update: `ops-ios/ANALYTICS.md`
- Add: `ops-software-bible/22_GROWTH_MEASUREMENT_CONTRACT.md`

Document only verified, live behaviour. Include property registry, metric formulas, attribution precedence, source freshness, privacy rules, alert rules, and exact ownership.

---

## 12. Backfill and Rollout Sequence

Execute in this dependency order:

1. **Foundation repair:** A1, A2, A3, A4.
2. **Database contract:** B1.
3. **First-party attribution:** B2, B3.
4. **Product telemetry:** C1, C2.
5. **Source warehouse:** D1, D2.
6. **Business reconciliation:** D3.
7. **Founder surface:** E1, E2.
8. **Health/privacy/docs:** F1, F2, F3.
9. **Backfill:** Search Console, GA4 retained history, App Store commerce backlog, trial attribution basis, and derived milestones.
10. **Release proof:** local tests → preview/staging → production deploy → live source readback → seven finalized days of stable data.

Do not wait seven days to ship repairs. Ship each verified foundation repair as soon as its own proof passes; use the seven-day window only to certify the new dashboard's trend and coverage claims.

### Backfill rules

- Preserve raw source values and the `as_of` time.
- Backfills are idempotent and resumable.
- Do not synthesize user-level touchpoints from aggregate Search Console, GA4, or App Store data.
- Historical `unknown` remains unknown unless deterministic or self-reported evidence exists.
- Mark pre-repair marketing GA4 dates as unreliable; do not silently chart them as comparable to post-repair dates.
- Mark App Store download dates provisional until the backfill and one UI reconciliation succeed.

---

## 13. Test Matrix

| Layer | Required tests |
|---|---|
| Config | Measurement ID trimming, validation, property mapping, missing env, wrong-property rejection |
| Client collection | Route templates, event registry, sanitizer, queue durability, offline/retry, duplicate IDs |
| Auth/security | Anonymous rejection, cross-company spoof rejection, admin route gates, RLS denial, payload/rate limits |
| Attribution | UTM, click ID, organic referrer, referral, direct, self-report, precedence, retry/idempotency |
| Source clients | Pagination, quota error, 401/403, restatement, malformed row, unknown column, no-data state |
| Warehouse | Unique grains, no duplicate upserts, aggregate reconciliation, provisional/finalized state |
| Business funnel | Trial/project/first-value/paid counts equal direct source-table queries |
| UI | Healthy/partial/error/empty/provisional states; date/channel filters; export; responsive; a11y; reduced motion |
| Live | Correct GA property, Search Console date, App Store download facts, fresh web/iOS product events, attribution write/readback |

### Required commands during execution

Use each repository's current package scripts rather than guessing. At minimum:

```bash
cd /Users/jacksonsweet/Projects/OPS/ops-site
npm test -- <touched analytics tests>
npm run build

cd /Users/jacksonsweet/Projects/OPS/ops-web
npm test -- <touched analytics tests>
npx tsc --noEmit
npm run build

cd /Users/jacksonsweet/Projects/OPS/ops-ios
xcodebuild test -scheme OPS -derivedDataPath <worktree-local-path> -only-testing:<analytics test targets>
```

Broad-suite pre-existing failures must be reported separately; any failure in touched analytics code blocks release.

---

## 14. Definition of Done

Analytics are “dialed” only when all of the following are true:

- Both production web tags load without errors and report to the correct properties.
- The read-only service identity can query all three GA properties.
- App Store download ingestion is healthy and backfilled.
- Search Console and GA4 daily facts refresh automatically with visible finalized dates.
- New web and iOS trials carry deterministic, self-reported, direct, or explicitly unknown attribution basis.
- The web product event stream is fresh, authenticated, idempotent, and cannot be spoofed across companies.
- Firebase key events contain the five OPS-managed conversion signals plus Google's automatic app defaults; `session_start` is not a key event.
- Core trial/activation/paid counts reconcile exactly to Supabase business records.
- The founder page shows web search and App Store discovery separately, then converges on one company funnel.
- Every number exposes freshness, coverage, and source state.
- No raw PII, secret, full query string, or resource UUID is present in analytics payloads.
- Automated health checks catch a broken tag, denied property, stale source, empty download feed, or attribution regression.
- Seven finalized production days pass without unexplained gaps, duplicates, or reconciliation drift.

---

## 15. Cost and External Access

No new paid analytics vendor is proposed. The design uses existing GA4, Search Console, Firebase, App Store Connect, Supabase, and Vercel infrastructure. The expected incremental cost is API/cron/database usage inside current plans; confirm plan headroom before enabling historical backfills and retention.

External access required during execution:

1. Add the dedicated analytics-reader identity to all three GA properties.
2. Add the same identity to the `opsapp.co` Search Console property.
3. Correct Vercel environment values and deploy each web repository only with explicit push/deploy authorization.
4. Change GA key-event configuration in the Google admin UI.
5. Release iOS changes through the normal App Store process only after explicit release authorization.

These are the only founder/credential gates. All code, schema, tests, backfills, dashboards, and technical decisions remain engineering-owned.
