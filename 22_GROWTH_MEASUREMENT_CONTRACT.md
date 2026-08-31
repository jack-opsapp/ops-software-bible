# 22 - Growth Measurement Contract

**Last verified:** August 31, 2026
**Deployment state:** Web/site source is pushed and deployed; production Supabase is migrated and read back; all three GA properties and `sc-domain:opsapp.co` are directly readable by the production identity; GA4 and Search Console retained-history backfills are complete with zero duplicate grains. Four extra Google key events, the iOS App Store release, Apple commerce completion, and seven-day certification remain open.

This is the canonical definition of every growth number OPS shows. Production qualification and outstanding source gates are recorded in [21_ANALYTICS_SYSTEM.md](./21_ANALYTICS_SYSTEM.md).

## 1. Non-negotiable rules

1. Business outcomes come from Supabase business records, never client analytics events.
2. Aggregate discovery sources remain aggregate. Search Console, GA4, and App Store facts must not be synthesized into user-level attribution.
3. A source failure is a failure state, not zero traffic.
4. Every response carries `asOf`, `finalizedThrough`, coverage, and source state.
5. Channel and evidence strength are separate fields. A channel label never implies deterministic attribution.
6. Unknown history remains unknown unless a deterministic or customer-reported fact exists.
7. Web and iOS use the same company milestone definitions.

## 2. Metric formulas

All company funnel metrics use a **trial-start cohort grain**. A company belongs to the reporting date of its canonical `companies.trial_start_date`, even when activation or payment happens later. Historical cohort totals can therefore mature as later milestones arrive.

| Metric | Exact formula | Owner | Freshness |
|---|---|---|---|
| Search impressions | Sum of Search Console impressions for the exact `opsapp.co` property over the selected dates. Privacy-suppressed queries are absent, not zero-filled. | Search Console | D-3 |
| Search clicks | Sum of Search Console clicks over the selected dates. | Search Console | D-3 |
| Search CTR | `search clicks / search impressions`; `null` when impressions are zero. | Search Console | D-3 |
| Organic site sessions | GA4 sessions in property `475051117` where default channel group is `Organic Search`. | GA4 marketing | D-2 |
| Web-app organic entries | GA4 sessions in property `539494652` where default channel group is `Organic Search`. | GA4 web app | D-2 |
| App Store discovery | App Store Connect impressions and product-page views grouped by source type. | App Store Connect | D-2 |
| First-time downloads | Sum of first-time download breakdown rows. Redownloads remain separate. A total row is excluded when breakdown rows exist so it cannot double-count. | App Store Connect | D-2 |
| Trial started | One non-deleted company with non-null `trial_start_date`. | Supabase `companies` | Real time |
| Classified trial | Trial whose canonical channel and attribution basis are both not `unknown`. | Supabase `trial_attributions` | Real time |
| First project | Earliest non-deleted project `created_at` for the company. The funnel stage counts any eventual first project. | Supabase `projects` | Real time |
| Activated company | Earliest non-deleted project was created at or after trial start and before `trial_start + 7 days`. | Supabase `projects` | Real time |
| First value | Earliest qualifying completed task or active project at or after trial start and before `trial_start + 14 days`. | Supabase task/project lifecycle records | Real time |
| Paid company | Company has at least one positive `billing_events` row with `event_type = 'invoice.paid'`. | Supabase `billing_events` | Real time |
| Revenue | Sum of positive `amount_cents` from confirmed `invoice.paid` rows for companies in the cohort. | Supabase `billing_events` | Real time |
| Attribution coverage | `(total trials - unknown trials) / total trials`; `null` when there are no trials. | Supabase | Real time |
| Activation rate | `activated companies / trials started`; `null` when there are no trials. | Supabase | Real time |
| App Store conversion rate | `first-time downloads / product-page views`; `null` when product-page views are zero. | App Store Connect | D-2 |

### Activation evidence

Activation uses project creation time only. A project created after the seven-day boundary does not retroactively activate that trial cohort, even if it later becomes active.

### First-value evidence

The first qualifying timestamp wins:

- preferred completed-task evidence: `task_mutation_events.event_type = 'task_completed'`;
- fallback completed-task evidence: current non-deleted task with `status = 'completed'`, using `updated_at`;
- preferred active-project evidence: `project_status_lifecycle_outbox.new_status` in `accepted`, `in_progress`, `completed`, or `closed`, using `requested_at`;
- fallback active-project evidence: current non-deleted project in one of those statuses, using `updated_at`.

Fallback evidence is labelled. Client telemetry cannot create, delete, or change a business milestone.

## 3. Attribution precedence

Use the strongest available evidence, not the most flattering channel:

1. `verified_click_id` — current `gclid` or `fbclid`; confidence `1.000`.
2. `deterministic_first_party` — explicit first-party provider evidence such as Apple Search Ads; expected confidence up to `0.950`.
3. `utm_referrer` — validated first-touch UTM and/or external referrer classification.
4. `app_store` — deterministic App Store/AdServices evidence when a future user-level integration can legally and technically supply it.
5. `self_reported` — the onboarding referral answer; confidence `0.550` for stable current slugs and `0.450` for a safe legacy label mapped only at read time.
6. `direct` — no campaign or external referrer in a validated first touch; confidence `1.000`.
7. `unknown` — no classifiable evidence; a non-empty reason code is mandatory.

A first-touch transaction may replace only `unknown` or `self_reported`. Self-report always remains in `self_reported_source`, but it cannot replace a stronger basis. Repeating setup with the same first-touch dedupe key may fill blank raw fields; a different later touch is ignored.

## 4. Channel classification

Canonical channels:

- `google_ads`
- `meta_ads`
- `apple_search_ads`
- `organic_search`
- `organic_social`
- `referral`
- `app_store_search`
- `app_store_browse`
- `direct`
- `other`
- `unknown`

Classification order for a validated web first touch:

1. `gclid` → `google_ads`.
2. `fbclid` → `meta_ads`.
3. explicit `apple_search_ads` / `asa` source → `apple_search_ads`.
4. organic/search medium → `organic_social` for Facebook, Meta, Instagram, or YouTube sources; otherwise `organic_search`.
5. Google source without an organic medium → `google_ads`.
6. Facebook, Meta, or Instagram source without an organic medium → `meta_ads`.
7. Google/Bing/DuckDuckGo/Yahoo external referrer → `organic_search`.
8. other external referrer or referral medium → `referral`.
9. no campaign and no external referrer → `direct`.
10. otherwise → `unknown` with `unclassified_campaign`.

Any `opsapp.co` subdomain is internal and never a referral.

### Self-reported mapping

| Stable answer | Channel |
|---|---|
| `instagram`, `facebook`, `youtube` | `organic_social` |
| `google` | `organic_search` |
| `app_store` | `app_store_browse` |
| `word_of_mouth` | `referral` |
| `other` | `other` |

Legacy free text stays unchanged in `companies.referral_method`. Only known, unambiguous legacy labels normalize at read time. Ambiguous history remains unknown.

### App Store search caveat

`App Store Search` is not automatically organic because it can include Apple Search Ads. Until spend/campaign evidence resolves the paid split, the founder surface must show `App Store search — paid split unavailable`. App Store Browse remains separate.

## 5. Founder surface contract

The default period is the last 30 calendar days, compared with the immediately preceding equal-length period. Valid ranges are 1–366 days.

The surface is outcome-first:

1. Activated companies and the equal-period change.
2. One company funnel: trial → first project → first value → paid.
3. Separate web-search and App Store discovery lanes.
4. Channel performance: discovery, trials, activated, paid, activation rate, revenue, and evidence confidence.
5. Quiet but always visible source health, freshness, and coverage.

The automatic channel lens selects `organic_search` only when attribution coverage is at least `80%`; below that threshold it defaults to all channels so an incomplete taxonomy cannot present a misleading organic story. User-selected channels are always respected.

Paid panels collapse when recent paid spend is zero. Dormant acquisition does not receive permanent prime space.

## 6. Source state contract

| State | Meaning |
|---|---|
| `ready` | Source completed and is fresh enough for the requested period. |
| `empty` | Source completed successfully and returned no rows. This is a known zero/no-data state. |
| `partial` | A resumable source walk or coverage window is incomplete. |
| `provisional` | Facts exist but a required backfill or reconciliation has not certified them. |
| `stale` | The latest finalized date is older than the source contract. |
| `missing` | No usable run/fact set exists. |
| `failed` | Permission, configuration, provider, schema, or reconciliation failure. Prior valid facts remain visible with the failure state. |

An API envelope never catches a source error and substitutes numeric zero. Source-specific failures stay source-specific; a healthy business-record funnel may coexist with failed Search Console or App Store discovery.

## 7. Reconciliation

Daily automated health requires zero deltas between normalized growth views and direct business records:

- trial delta: attribution rows joined to a non-deleted company with a trial start, minus those same eligible companies; orphaned/deleted-company history and rows without a canonical trial start are excluded from both sides;
- activation delta: `growth_funnel_daily.activated_companies` minus company milestones with `activated_at`;
- paid delta: funnel paid companies minus company milestones with `first_paid_at`;
- revenue delta: funnel revenue minus positive confirmed `invoice.paid` amounts.

The current migration also requires zero invalid event contracts, duplicate event IDs, and privacy findings. Every unknown attribution row must contribute to exactly one explicit reason count.

## 8. Release certification

The web/database contract is production truth. Full cross-platform release certification still requires all of the following to be proven independently:

- three GA property permissions succeed for the dedicated read-only identity;
- exact Search Console property identity and permission succeed;
- App Store commerce traversal is complete and download facts reconcile to one UI readback;
- staged Supabase migrations are applied explicitly and read back from production;
- web and iOS releases are live;
- the founder surface reports the correct property/source identities;
- seven finalized production days pass without unexplained gaps, duplicates, privacy findings, or reconciliation drift.

There is no new analytics-vendor subscription. Production backfills and retention still consume current Vercel, Google API, and Supabase capacity, so plan headroom and quotas must be confirmed before enablement.
