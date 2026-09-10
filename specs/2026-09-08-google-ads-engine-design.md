# Google Ads Engine — Design

**Date:** 2026-09-08
**Status:** APPROVED 2026-09-08. Jackson locked the five calls in §2 on their recommended defaults and is performing the three account actions in §3.1.
**Phase 3 status (2026-09-10): LIVE.** §5, §6, §7 are deployed on `app.opsapp.co` (`main` `3bdc81e00`, PR #120, which also carried phase 1); both engine migrations are applied. Verified live by route contract; the local record is `ops-web/docs/artifacts/ads-engine/p3/local-e2e-2026-09-08/README.md`. The routine `OPS Google Ads engine` (`trig_01LroGoQJLg9GCPEAK3SD4dg`) exists but is DISABLED with connectors cleared and has never run, so the account is untouched. Gate still open: it runs its first cycle only once phase 2 builds the campaigns and Jackson un-pauses it. Record: `scheduled-agents/ops-google-ads-engine.md`.
**Owner surface:** ops-web (`/admin/google-ads`, `/api/internal/ads/engine/*`, crons), try-ops (landing pages + click-id capture), one Claude Cloud Routine.
**Research inputs:** `research/google-ads/2026-09-08-local-findings.md`, `research/google-ads/2026-09-08-google-ads-for-trades-saas.md`, `research/google-ads/2026-09-08-google-ads-api-engineering.md` (all committed alongside this spec).
**Spawn prefix:** `GOOGLE ADS ENGINE - P<phase>-<n>`.

---

## 0. What this is

A closed loop that runs Google Search ads for OPS with a Claude routine doing the thinking and OPS doing the measuring, the guarding, and the applying:

```
Google Ads ──(daily sync, v25 searchStream)──▶ warehouse ──▶ claim brief ──▶ Claude routine
     ▲                                                                            │
     │  apply on approval (googleAds:mutate, validateOnly first, labelled)         ▼
 OPS apply ◀── admin review panel ◀── deterministic validators ◀── typed proposals
     │
     └──(Data Manager events:ingest)◀── conversion outbox ◀── company created / activated / paid
```

Four layers, built in this order: **measurement**, **account rebuild**, **engine**, **console**. The engine is worthless without the first two, which is why they come first.

## 1. Facts this design rests on (verified 2026-09-08)

- The account (`4454506598 "OPS"`, CAD, Vancouver, auto-tagging on) has 22 campaigns, all paused, no spend since 2026-03-09. Lifetime $4,777.80 CAD bought mostly Display and Performance Max page-loads on a Bubble-era page that now redirects to `/plans`. Search burned $1,418 on 228 clicks with zero negative keywords, broad match on off-topic terms, and off-voice copy rated POOR.
- Nothing on the current funnel reports a conversion to Google: no action exists for `app.opsapp.co/register` or the `try.opsapp.co` signup; the enabled actions are three dead Bubble page actions plus three Firebase iOS actions (`first_open`, `sign_up`, and `login` — `login` is marked primary, so every login counts as a conversion).
- `trial_attributions` has 64 rows, all channel `unknown`, zero `gclid`s. try-ops never captures the click id. ops-site captures it into the `.opsapp.co` cookie but every ops-site CTA goes to the App Store, where the click id dies.
- The service account (`firebase-adminsdk-fbsvc@ops-ios-app.iam.gserviceaccount.com`) is **READ_ONLY** on the manager account `5448339076` and absent from the client account. A `validateOnly` mutate returns `AuthorizationError.ACTION_NOT_PERMITTED`. Reads work; writes do not.
- The account has not accepted **Customer data terms** and has **Enhanced conversions for leads** disabled (both unset on `customer.conversion_tracking_setting`). No `UPLOAD_CLICKS` conversion action exists.
- Google Ads API: current major **v25** (v22 sunsets 2026-10-07; our client pins v23). Basic access is confirmed and mutates are not gated by access level; 15,000 ops/day is two orders of magnitude above this loop's need. Since 2026-06-15 the Ads API's `UploadClickConversions` is closed to tokens without prior usage (ours has none); **the Data Manager API (`events:ingest`, scope `https://www.googleapis.com/auth/datamanager`) is the conversion path**, and it accepts gclid/gbraid/wbraid plus SHA-256 hashed email, ≤2,000 events per request, with `validateOnly`.
- RSAs are mutable in place but stats blend across edits, so every measured change is a **new ad + paused old ad**, tagged with a label. Ad Variations are UI-only. Campaign experiments cannot reach significance at this spend. Asset performance labels (`BEST/GOOD/LOW/LEARNING`) are Google's own significance verdict.
- Business volume: 64 companies, 6 paying, 2–7 new companies a month. Every Smart Bidding threshold (15–30 conversions per month) is out of reach today. Value-based and target-based bidding are not available; the honest opening strategy is **Maximize Clicks with a CPC cap** on a tight phrase/exact keyword set.
- The house pattern for routine-authored work already exists and is live: the Instagram Cloud Routine (claim → author → independent editor → deterministic server validation with fixable 422 codes → held draft → policy mode flip) plus the notification rail. This design reuses that contract shape verbatim.

## 2. Jackson's calls (LOCKED 2026-09-08 on the recommended defaults)

| # | Decision | Decision (locked) | Why it was his |
|---|---|---|---|
| 1 | Budget and commitment | **$1,500 CAD/month for 90 days ($4,500)**, Search only. ~~Canada only~~ → **REVISED 2026-09-09: US primary, Canada secondary**, delegated to the agent by Jackson ("I will trust your judgement") after measured demand showed Canada holds 1,520 buyable searches/month against 8,720 in the US and real bids run ~2x the planning assumption. Evidence: `research/google-ads/2026-09-09-keyword-demand.md`; structure: P2 plan Task 2R. **Launch is HELD at Jackson's instruction (2026-09-09) until the web and iOS apps are refined** — everything is built PAUSED and waits. | Money. $370/month buys no information; the budget only becomes readable where the searches actually are |
| 2 | Where paid clicks land | **try.opsapp.co dedicated pages with web signup**; never the App Store; the app is offered after signup | Product direction: paid traffic gets a web-first path while organic keeps its App Store CTAs |
| 3 | Competitor names in ad text | **Yes, in the competitor campaign only**, in "Jobber alternative" form; honest price table on the landing page | Brand posture and trademark-complaint risk (complaint → ad disapproved, engine rewrites) |
| 4 | Approval mode | **Every proposal reviewed by Jackson** for the first cycle; negatives and loser-pauses become automatic only on his later say-so | Control over spend and public copy |
| 5 | No-card trial | **Keep it** and budget against cost per paying customer (roughly 3× harder per dollar than card-required trials) | Brand promise with a quantified cost; revisit at day 90 with real trial→paid data |

## 3. Layer 1 — Measurement (Phase 1)

### 3.1 Access (Jackson, ~10 minutes, before any code can write)

1. Google Ads → manager `5448339076` → Admin → Access and security → change the service account's role from **Read only** to **Standard**. This unlocks both Ads API mutates and Data Manager uploads.
2. Google Ads → client `4454506598` → Goals → Conversions → Settings → **accept Customer data terms** and **turn on Enhanced conversions for leads**.
3. Google Cloud project `ops-ios-app` → **enable the Data Manager API**.
4. Only if the post-change `validateOnly` probe returns a developer-token error: API Center → developer token → request permissible use **Ad creation/management** and **Researching keywords and recommendations** (5 business days).

The build re-runs the probe (`scratchpad/ads-validate-probe.mjs` pattern, `validateOnly: true`, no write possible) and records the result in the runbook before proceeding.

### 3.2 Ads API client

- Upgrade `ops-web/src/lib/analytics/google-ads-client.ts` from v23 to **v25** (one constant). Keep service-account auth and the manager→client resolution.
- Reads move to `googleAds:searchStream` (one operation per report, response is an array of chunks, no `pageSize`).
- Add `mutate(customerId, operations, { validateOnly, partialFailure })` over `googleAds:mutate`, with the camel/snake mapper, int64-as-string parsing, `partialFailureError.details[]` decoded positionally, and `request-id` logged on every call. No third-party Ads library (none supports v25).
- Every write path calls `validateOnly: true` first and only re-sends on a clean pass.

### 3.3 Conversion actions (created through the API, `ConversionActionService`)

| Name | Type | Role | Counting | Lookback | Value |
|---|---|---|---|---|---|
| `OPS · Trial started` | `UPLOAD_CLICKS` | **Primary** — the only action in "Conversions" | ONE_PER_CLICK | 30 days | none |
| `OPS · Trial activated` | `UPLOAD_CLICKS` | Secondary (observation) | ONE_PER_CLICK | 30 days | none |
| `OPS · Paid subscription` | `UPLOAD_CLICKS` | Secondary (observation; future value bidding) | ONE_PER_CLICK | 90 days | plan monthly price × 12, CAD |

Existing actions: the three Bubble-era `WEBPAGE` actions are set to `REMOVED`; the Firebase iOS `first_open`, `sign_up`, `login` actions are set `primary_for_goal = false` and excluded from the Conversions metric (kept for App campaigns if they ever return). Definitions: *trial started* = company row inserted with an owner (any platform); *trial activated* = the company's first project created; *paid* = first `invoice.paid` on `billing_events` (the trigger that already stamps `first_paid_at`).

### 3.4 Click-id capture (every company-creation path)

- **try-ops:** middleware writes the canonical `__ops_first_touch` cookie on `.opsapp.co` with a verbatim copy of ops-site's `src/lib/analytics/first-touch.ts` (identical JSON shape, 30 days, `SameSite=Lax`, legacy `ops_attribution` migrated), capturing `gclid`, `gbraid`, `wbraid`, `fbclid`, the five UTM keys, landing path, referrer domain, first-touch time. **Correction found in code review (2026-09-08):** try-ops's own signup creates companies through the legacy Bubble workflow (`/api/company/update` → Bubble `update_company`), not through Supabase, so it can never feed `trial_attributions`. Paid landing pages therefore send their single CTA to `https://app.opsapp.co/register`, the web signup whose company step already reads the first-touch cookie server-side (`/api/setup/progress`, step `company` → `recordTrialAttribution`). The try-ops native signup stays for the tutorial variants and is not a paid destination.
- **ops-web:** `utm-capture.ts` and `attribution.ts` learn `gbraid`/`wbraid` (both classify as `google_ads`, basis `verified_click_id`). The cookie decoder keeps the bounded decode-until-JSON rule (the double-encoding gotcha from P2).
- **ops-site:** unchanged, other than adding `gbraid`/`wbraid` to `spec/attribution.ts` so all three writers agree.
- Rule: no company-creation path may fail because attribution failed; capture is exception-wrapped exactly like the existing trigger.

### 3.5 Conversion outbox → Data Manager

New table `ads_conversion_events` (service-role only): `id`, `company_id`, `kind` (`trial_started | trial_activated | paid`), `occurred_at`, `gclid`, `gbraid`, `wbraid`, `email_sha256`, `value`, `currency`, `transaction_id` (= `kind:company_id`, so re-sends never double count), `state` (`queued | sent | failed | skipped`), `attempts`, `last_error`, `sent_at`, `google_request_id`.

Writers: the existing company-insert trigger path enqueues `trial_started`; first-project creation enqueues `trial_activated`; the `billing_events` trigger enqueues `paid` with the plan's annualised value. **Every** company enqueues, including iOS-born ones with no click id — Google matches hashed email to a signed-in click when one exists, which is the only cross-device bridge OPS has.

Sender: cron `/api/cron/ads-conversions` every 15 minutes, batches ≤2,000 events to `POST https://datamanager.googleapis.com/v1/events:ingest` with `destinations[].operatingAccount = {GOOGLE_ADS, 4454506598}`, `loginAccount = {GOOGLE_ADS, 5448339076}`, `productDestinationId = <conversion action id>`, `encoding = HEX`, `consent.adUserData = GRANTED`, `eventSource = WEB`, `adIdentifiers.{gclid,gbraid,wbraid}`, `userData.userIdentifiers[].emailAddress` (normalised, SHA-256), `eventTimestamp` ISO-8601 with offset, `conversionValue`/`currency` on `paid`. Bounded retries (5, exponential), then `failed` with the error and a persistent `ADS CONVERSIONS FAILING` notification. `validateOnly: true` in tests and in the first live rehearsal. Scope `https://www.googleapis.com/auth/datamanager` is added to the service-account client; the Data Manager API is enabled on the Firebase Cloud project.

### 3.6 Warehouse extension

Existing `ads_daily_account`, `ads_daily_campaign`, `ads_daily_search_term` stay. New (all service-role only, upsert on natural keys, trailing 3 days re-synced daily and trailing 30 days weekly because Google restates data inside the lookback window):

- `ads_daily_ad_group` (date, campaign_id, ad_group_id, metrics)
- `ads_daily_ad` (date, ad_group_id, ad_id, `ad_strength`, `approval_status`, `review_status`, metrics)
- `ads_daily_asset` (date, ad_id, asset_id, `field_type`, `performance_label`, `pinned_field`, metrics) from `ad_group_ad_asset_view`
- `ads_daily_keyword` (now populated: date, ad_group_id, criterion_id, text, match type, status, quality score, metrics)
- `ads_entities` — a daily snapshot of the live structure (campaigns, budgets, bidding, ad groups, ads with full RSA assets and pins, keywords, negatives, shared sets, labels) keyed by Google resource name, so the engine and the console never need a live call to know what exists.
- `ads_funnel_by_keyword` — a view joining `trial_attributions` (via `gclid` → `ads_click_map`, see below) to keyword/ad/campaign, exposing click → trial → activated → paid per keyword, ad, and campaign. This is the only place "which keyword produced a paying customer" is answered.
- `ads_click_map` (gclid → campaign/ad group/ad/keyword/date) filled from `click_view` daily (Google exposes it for the trailing 90 days; sync daily, keep forever).

The daily sync (`/api/cron/ads-sync`, 08:00 UTC) grows to cover these; the search-term sync is folded in. The PMF `ad_spend_log` sync stays as is.

## 4. Layer 2 — Account rebuild (Phase 2)

### 4.1 Blueprint, not clicks

The account is rebuilt from a declarative blueprint file in the repo (`ops-web/config/ads/blueprint.json`, versioned) that the build applies through the API with `validateOnly` first. The blueprint is the source of truth for structure; the engine may later propose diffs to it, never edit Google by hand.

### 4.2 Structure (Canada, $50/day; US added as separate campaigns after the day-90 gate)

| Campaign | Match | Bidding | Daily | Ad groups (one landing page each) |
|---|---|---|---|---|
| `BRAND · CA` | Exact | Manual CPC, $2 cap | $3 | `opsapp`, `ops app`, `opsapp.co`, `ops job management` |
| `CORE · CA` | Phrase + Exact | Maximize Clicks, $8 CPC cap | $32 | `Job management` → `/job-management`; `Crew scheduling` → `/scheduling`; `Quotes & invoices` → `/quotes-invoices` |
| `COMPETITOR · CA` | Exact + Phrase | Maximize Clicks, $10 CPC cap | $15 | `Jobber alternative` → `/compare/jobber`; `Housecall Pro alternative` → `/compare/housecall-pro` |

Settings on every campaign: Search network only (search partners **off**, Display **off**), location type **presence** (people in Canada), English, all hours, `STANDARD` delivery. No broad match, no Performance Max, no Demand Gen, no AI Max, no App campaigns in this phase. `field service management software` and `servicetitan` terms are deliberately excluded (enterprise buyers). Trade-specific ad groups (`electrician scheduling app`, `hvac job software`, …) are added one at a time from month 2 by the engine's structure duty, starting with trades where OPS has a real customer.

Seed keyword lists are pulled from Google Keyword Planner (Canada) before launch and pruned for zero volume; the SEO research (2026-06-07) and the historical search-term report supply the candidates.

### 4.3 Shared negative lists (applied to all campaigns, engine-maintained)

`NEG · Job seekers` (jobs, hiring, salary, apprenticeship, resume …), `NEG · Homeowner intent` (near me, hire, cost to, how much does, repair, install, emergency, quotes for …), `NEG · Training` (course, certification, exam, red seal, tutorial, how to …), `NEG · Generic waste` (free*, open source, template, excel, spreadsheet, pdf, reddit, crack …), `NEG · Wrong segment` (enterprise, erp, fleet, franchise, salesforce, sap, servicetitan* …). `*free` is excluded from CORE only; `*servicetitan` from CORE and BRAND only. The historical junk (`esign`, `signature`, moving, cleaning-service, hiring terms) is seeded on day one.

### 4.4 Ads

Two RSAs per ad group (control + challenger) written by the routine in the OPS voice under the copy rules in §5.5, 8–12 headlines (never padded to 15), 3–4 descriptions, **2–3 on-message headlines pinned to position 1**, nothing else pinned. Path fields set (`/trades/jobs` style). Sitelinks and callouts drawn from the brand-facts allowlist. Every ad carries labels `engine`, `gen-<run id>`, `role-control|challenger`.

### 4.5 Landing pages (try-ops)

Five dedicated routes: `/job-management`, `/scheduling`, `/quotes-invoices`, `/compare/jobber`, `/compare/housecall-pro`. Each: headline matched to its ad group, **the three real prices above the fold**, "no credit card" as a promise, one single CTA repeated (start free) that links to `https://app.opsapp.co/register` (see §3.4 correction), one **named, real** customer quote adjacent to the CTA (or none; nothing invented), sub-2 s load on rural LTE, the click-id cookie written on arrival. The compare pages carry the honest per-crew arithmetic (Jobber Connect $99/month is one user; five users is $215/month before add-ons; OPS is $140/month for the crew with every feature). Pages are built from the existing try-ops section registry with page-specific configs; the AI-rotated A/B loop stays on `/` and is connected to these pages in Phase 4. Copy is written with the OPS copywriter skill; design follows the OPS design system and the existing try-ops kit.

### 4.6 Legacy

The 22 legacy campaigns stay paused and are labelled `legacy`; nothing is removed, so history remains queryable.

## 5. Layer 3 — The engine (Phase 3)

### 5.1 Contract (mirrors the Instagram routine)

Routes under `/api/internal/ads/engine/`, bearer `ADS_ENGINE_TOKEN` injected by the cloud environment's API credential for host `app.opsapp.co` (the token never enters the routine's sandbox):

- `POST /claim` `{worker}` → `200 {run, brief}` or `{run: null, reason}`; 40-minute lease; at most one active run.
- `POST /runs/{id}/proposals` `{claim_token, proposals[]}` → per-proposal `accepted | rejected {code, issues}`; codes are fixable and the routine may resubmit up to 3 times per proposal.
- `POST /runs/{id}/release` `{claim_token, summary, outcome}` → closes the run; the summary becomes the weekly briefing (the OpenAI briefing cron is retired).

The **brief** is everything the routine needs and nothing it should not have: which duties are due today (hygiene daily; creative every 4–8 weeks per ad group; structure monthly; bidding ladder check monthly), the entity snapshot, 7/28-day metrics per campaign/ad group/ad/asset/keyword/search term (trailing 3 days excluded), the funnel-by-keyword view, open tests with OPS-computed stats, the change ledger (last 90 days with outcomes), pending and rejected proposals with Jackson's reasons, guardrail settings, the copy rules and brand-facts allowlist, the negative-list taxonomy, and a weekly competitor/market digest (the existing Tavily step, run server-side). Every number the routine may quote in copy is in the allowlist; every other number is rejected.

### 5.2 Proposal kinds (v1)

| Kind | Payload | Server rule |
|---|---|---|
| `add_negatives` | terms + list + classification (`job_seeker | homeowner | student | wrong_segment | irrelevant`) + evidence rows | never a term that produced a trial start; term must exist in the search-term report |
| `pause_keyword` | criterion + evidence | ≥30 clicks and 0 trial starts over ≥28 days, or spend ≥3× the target cost-per-trial with 0 starts |
| `add_keywords` | ad group + terms + match (phrase/exact only) | must match the ad group's landing page theme; no broad |
| `create_rsa_challenger` | ad group + assets + pins + final URL + hypothesis | copy rules §5.5; `validateOnly` pass; becomes a test against the current control |
| `promote_challenger` / `pause_ad` | test id / ad | only after the verdict rule §5.4 |
| `adjust_budget`, `adjust_cpc_cap` | campaign + new value + reason | ≤15% per change, ≥14 days since the last change on that campaign, under the monthly cap |
| `set_bidding_strategy` | campaign + strategy | only along the ladder: Max Clicks (cap) → Max Conversions at ≥15 trial starts/30 days for two consecutive months → Target CPA at ≥30/30 days |
| `add_ad_group` | campaign + theme + landing URL + seed keywords | landing URL must exist and be in the allowlist |
| `observation` | text + evidence | no action; surfaces in the console |

Excluded from v1 on purpose: campaign creation, geo/language/schedule edits, Performance Max, App campaigns, campaign experiments, anything touching billing.

### 5.3 Approval, application, ledger

- Accepted proposals land in `ads_proposals` (`id, run_id, kind, payload, evidence, rationale, state: proposed|approved|rejected|applied|failed|expired, reviewed_by, review_notes, reviewed_at, google_validation, applied_resource_names, label, expires_at`). They are reviewed on the admin ads page (§6) — **not** in the customer agent queue, whose rows belong to customer companies — using the queue's card, batch bar, and approve/reject affordances.
- Per-kind **mode** in `ads_engine_settings`: `propose` (default for everything), `auto` (apply within guardrails and notify), `off`. Flipping a kind to `auto` is Jackson's call, like the Instagram `publish` flip.
- On approval OPS applies through the Ads client: `validateOnly` → real mutate → labels → `ads_changes` row (`proposal_id, resource names, before, after, applied_at, measure_from, measure_to, verdict, verdict_at`). Expired proposals (14 days) are dropped and the routine is told why.
- Outcome attribution: each change gets a pre/post window (14 days each, trailing 3 days excluded) on the affected entity; the ledger shows the delta with the honest caveat that only CTR is significant at this volume.

### 5.4 Tests (ad pairs, not experiments)

A test = one ad group, one control ad, one challenger ad, both enabled. OPS computes the verdict; the routine never eyeballs significance. Verdict rule: ≥14 days, ≥2,000 impressions per ad, two-proportion z-test on CTR with p < 0.05, plus a conversion veto (if the control has ≥5 trial starts and the challenger has 0 on comparable clicks, no promotion). Max 8 weeks; then `no_verdict` and the challenger is retired or kept by judgment (proposal). Winner becomes control; the next challenger is proposed on the 4–8-week cadence. Asset labels (`BEST/LOW`) are shown and used for asset swaps inside an ad only as new-ad-plus-pause, never as in-place edits.

### 5.5 Copy rules (deterministic, server-side; the routine also receives them)

Headlines ≤30 chars, descriptions ≤90; 8–12 headlines, 3–4 descriptions; no duplicates or near-duplicates; no exclamation marks; no emoji or repeated punctuation; no all-caps words other than `OPS`; sentence case; none of the banned words; never "contractor" for the audience; never lead with "AI"; every number from the brand-facts allowlist only (`$90`, `$140`, `$190`, "every feature, every tier", "no credit card", "free to start", crews of one to ten); competitor names only in the competitor campaign and only as `<Brand> alternative` / `Switching from <Brand>?`; final URL from the allowlist; 2–3 headlines pinned to position 1 and nothing else pinned; an independent editor subagent reviews every candidate against the OPS copywriter brief (the same bundled brief the Instagram routine uses) before submission. Google's `validateOnly` policy findings are returned to the routine as `GOOGLE_POLICY` with the topic so it can rewrite.

### 5.6 Guardrails on money and pace

Monthly cap and daily cap in settings (defaults $1,500 CAD and $60); no proposal may push the sum of daily budgets above the daily cap; budget and cap changes ≤15% and ≥14 days apart per campaign; at most 3 structural proposals per run; hygiene may propose any number of negatives. Any `DISAPPROVED` ad is paused by OPS immediately (not proposed) and reported.

### 5.7 The routine

`OPS Google Ads engine`, model `claude-opus-5`, tools `Bash, Read, Write, Edit, Agent`, no repositories, no connectors, environment `Default` with the API credential. Schedule `0 15 * * *` UTC (08:00 Vancouver, after the 08:00 UTC sync); OPS decides per run which duties are due, so one daily routine covers hygiene (daily), creative (per ad group every 4–8 weeks), structure and bidding (monthly). Prompt source of truth: `ops-web/docs/ads/engine-routine.md`, versioned like the Instagram prompt. Usage draws the subscription; a refused run leaves work queued and OPS raises `ADS ENGINE STALLED` after 50 hours of silence while ads are live.

## 6. Layer 4 — Console (`/admin/google-ads`)

State-aware, one page, no new sidebar item:

- **Dark account** (today): a setup ledger — access, terms, Data Manager, conversion actions, click-id capture, landing pages — each with live pass/fail from probes, and nothing else. The current KPI tiles stay below with the `[all campaigns paused]` line.
- **Live account:** (1) funnel by keyword/ad group/campaign (click → trial → activated → paid, spend, cost per trial, cost per paying customer); (2) proposals needing Jackson (card per proposal with a Google-style ad preview for RSAs, the evidence, approve/reject with a reason, batch bar); (3) tests running (control vs challenger CTR, impressions, days, OPS's verdict state); (4) change ledger with outcomes; (5) engine health (last run, duties done, next due, stall state) and guardrail settings with per-kind mode toggles.

Visuals follow the OPS design system and the dataviz rules (numbers in mono, `—` for empty, one easing). The briefings archive stays readable; the OpenAI briefing cron is removed once the first engine run summary lands.

## 7. Notifications (admin rail, recipients `PMF_OPERATOR_*`)

`ADS PROPOSALS READY · n` (standard, action → console), `AD DISAPPROVED` (persistent), `ADS CONVERSIONS FAILING` (persistent), `ADS ENGINE STALLED` (persistent, once per day), `ADS BUDGET PACING` (standard, when a campaign is capped by budget three days running).

## 8. Phases, gates, spawn names

| Phase | Scope | Gate to pass |
|---|---|---|
| **P1 Measurement** | §3 entirely (access, v25 client with mutate, conversion actions, click-id capture on try-ops/ops-web/ops-site, outbox + Data Manager sender, warehouse extension, dark-state console ledger) | A rehearsal `trial_started` event with `validateOnly: false` shows as a conversion in Google Ads; a `validateOnly` mutate passes; `trial_attributions` carries a gclid from a try-ops test signup |
| **P2 Account rebuild** | §4 (blueprint, Keyword Planner pull, campaigns via API, negatives, first ad pairs, five landing pages) | Campaigns exist paused and validated; landing pages live; Jackson approves the first ad pairs; then campaigns are enabled on his GO |
| **P3 Engine** | §5 + live console + notifications + routine (created disabled, run once manually, then scheduled) | One full cycle: routine claims, proposes, Jackson approves one negative set and one challenger, OPS applies, ledger shows the change; stall alarm proven by a skipped run |
| **P4 Loop closure** | Landing-page variant ↔ ad group linkage, US campaigns, trade ad groups by evidence, value-based bidding when the ladder allows, retire the OpenAI briefing and the try-ops OpenAI rotation into the routine | Day-90 review against the decision gates in the research (§8.10) |

P1 and P3 can be built in parallel worktrees; P2 needs P1's access and client. First spawns: `GOOGLE ADS ENGINE - P1-1` (measurement), `GOOGLE ADS ENGINE - P3-1` (engine core) once the plan is written.

## 9. Cost

Google Ads API, Data Manager API, Vercel crons: no incremental cost. Claude routine: Jackson's subscription (daily routine allowance; no API fallback). Tavily: existing free tier. Ad spend: the §2 budget, $1,500 CAD/month recommended, $4,500 over the first 90 days. Keyword Planner: free with the token's research permissible use, else one manual export from the Ads UI.

## 10. Verification

Unit tests for every validator and the stats rule; SQL harness for the new tables, view, and triggers (the existing PG17 harness); contract tests for the three internal routes (auth, lease, 422 codes, idempotent transaction ids); a full local rehearsal of the routine prompt against a disposable stack (the Instagram rehearsal recipe) before the routine ever touches production; Google-side proofs with `validateOnly`; a shadow week in P3 where the engine proposes against the rebuilt account before anything is approved. Screenshots of the console states and the rehearsal transcripts go to `docs/artifacts/ads-engine/`.

## 11. Out of scope (v1)

Performance Max, Demand Gen, Display, App campaigns, AI Max, campaign experiments, Meta and Apple Search Ads connectors (the attribution initiative's P3c/P3e), multi-account support, any change to ops-site's App Store CTAs, a card-required trial.
