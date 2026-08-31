# 21 - Analytics System

**Last verified:** August 30, 2026
**Scope:** GA4, Search Console, App Store Connect, Firebase conversion telemetry, Supabase product telemetry, first-party attribution, business milestones, and the founder growth surface.

This chapter distinguishes production truth from code that is prepared and verified locally. A local commit, migration file, or passing test is not evidence that production has changed.

## 1. Production status

### Verified live snapshot — August 30, 2026

| Area | Verified production state |
|---|---|
| Marketing GA4 | Property `475051117`; measurement ID `G-HKM7RWVTDV`. The current server identity is denied read access. |
| Logged-in web GA4 | Property `539494652`; measurement ID `G-JJP5SN122V`. The current server identity is denied read access. |
| iOS Firebase / GA4 | Property `514229717`. The current server identity can read it. |
| Search Console | The exact property identity and reader grant are not configured in OPS-Web. No Search Console warehouse facts are live. |
| App Store Connect | Engagement facts exist, but the verified audit found zero download facts. Store conversion is provisional until commerce ingestion is backfilled and reconciled. |
| Supabase product telemetry | `16,044` live `analytics_events`; duplicate event IDs `0`. The newest web event was `2026-05-14T21:05:12.156Z`; no web product events arrived in the preceding seven days. |
| Product-event contract | Production still has the legacy shape. `schema_version`, `environment`, and `received_at` are absent. The staged `analytics_sync_runs` and `touchpoints` tables are also absent. |
| Event privacy | Production is not clean. The verified scan found identifier-bearing properties including `project_id`, UUID values in `error_type`, `deeplinkid`, and generic `id`. Safe boolean keys such as `has_email`, `has_phone`, and `has_address` are not PII findings. No production rows were changed during the audit. |
| Trial attribution | The legacy attribution table exists, but current first-touch coverage is not sufficient for source-to-revenue claims. Historical unknown attribution remains unknown unless deterministic or self-reported evidence exists. |
| Founder growth page | Not live. Production does not yet have the normalized acquisition warehouse, derived milestone tables, or source-health contract required by the page. |

### Locally verified release candidate — not live

The cross-platform analytics hardening branches prepare the following changes:

- Correct, validated GA property mapping on both web surfaces.
- One versioned first-touch payload across `opsapp.co` and `app.opsapp.co`.
- Authenticated, idempotent web product-event delivery with server-derived identity.
- A durable iOS product-event queue, with Firebase narrowed to five conversion signals.
- Search Console and GA4 acquisition warehouse jobs with atomic date replacement.
- Restored App Store commerce traversal and truthful partial/completed status.
- Business milestones derived from Supabase records, not client events.
- A founder growth surface with visible freshness, coverage, and source failure states.
- Automated health transitions, persistent failure notifications, privacy enforcement, and retention aggregation.

None of those changes are production behavior until the relevant branch is pushed, deployed or released, the staged Supabase migrations are explicitly applied, required Google permissions are granted, and live readback succeeds.

## 2. Source ownership

Every source has one job. No dashboard may substitute one source for another.

| Question | Owner | Rule |
|---|---|---|
| What search demand exists? | Google Search Console | Aggregate query/page/country/device facts only. Never user-level attribution. |
| What happened on an anonymous web visit? | GA4 | Sessions and visit behavior for the marketing and logged-in web properties. Not signup, activation, paid, or revenue truth. |
| What happened in the App Store? | App Store Connect | Impressions, product-page views, and downloads. Not person-level identity. |
| Which company started a trial? | Supabase `companies` and `trial_attributions` | Canonical company identity and trial start. |
| Which company activated? | Supabase projects/tasks/business records | Derived milestone. Never inferred from a client analytics event. |
| Which company paid and how much? | Supabase billing records | Confirmed paid events only. |
| How is the product used? | Supabase `analytics_events` | First-party, authenticated product behavior. |
| Which iOS conversion signals reach Google? | Firebase Analytics | Five-event allowlist only. |

The complete formula and precedence contract is in [22_GROWTH_MEASUREMENT_CONTRACT.md](./22_GROWTH_MEASUREMENT_CONTRACT.md).

## 3. Property registry

Property selection is explicit and fail-closed.

| Registry key | Surface | GA property ID | Measurement ID |
|---|---|---:|---|
| `marketing` | `opsapp.co` | `475051117` | `G-HKM7RWVTDV` |
| `web_app` | `app.opsapp.co` | `539494652` | `G-JJP5SN122V` |
| `ios_app` | Firebase iOS app | `514229717` | Managed by Firebase |

OPS-Web must reject a valid-looking ID if it belongs to the wrong registry key. Measurement IDs are trimmed before use; executable or legacy Universal Analytics identifiers are rejected. A dedicated read-only Google service identity is the target owner. The existing Firebase administrator identity is only a transitional fallback for GA reads and currently lacks access to the two web properties.

## 4. Collection contracts

### Web visit analytics

Both web surfaces load `gtag.js` only when a valid GA4 measurement ID exists. The initial configuration:

- excludes the query string from `page_location` and `page_path`;
- templates logged-in UUID and numeric resource segments as `:id`;
- defaults `ad_storage`, `ad_user_data`, and `ad_personalization` to `denied`;
- leaves `analytics_storage` enabled for the approved first-party analytics purpose.

Advertising storage or personalization must not be enabled until the privacy policy and consent implementation explicitly approve it.

### First-party product events

The release-candidate event contract is version `1`:

| Field | Contract |
|---|---|
| `id` | Client-generated UUID; database conflict makes retry idempotent. |
| `event_type` / `event_name` | Bounded allowlisted type and snake-case event name. |
| `platform` | Derived by the server/RPC, never trusted from a web client. |
| `user_id`, `company_id`, `role`, `plan` | Resolved from the authenticated subject on the server. Client identity is discarded. |
| `session_id` | Stable UUID for the client session. |
| `properties` | At most 25 bounded scalar/array values after PII and identifier screening. |
| `schema_version` | `1`. |
| `environment` | Explicit `production`, `preview`, `development`, or `test`. |
| `created_at` / `received_at` | Client occurrence time plus authoritative server receipt time. |

Web queues events durably with a seven-day TTL and a 1,000-event cap. iOS queues them in `UserDefaults` with the same cap, preserves order, retries transient failures, and drops permanent poison events so one bad payload cannot stall the stream. Anonymous iOS events remain local until authentication and bind once to the first verified subject.

### Firebase conversion allowlist

Firebase is conversion QA and Google optimization telemetry, not product or business truth. The iOS release candidate permits only:

1. `sign_up`
2. `begin_trial`
3. `complete_onboarding`
4. `create_first_project`
5. `purchase`

`session_start`, app opens, logins, navigation, screen views, CRUD telemetry, and errors are not key conversions. The deployed Firebase key-event configuration must be verified separately in Google administration; local code cannot prove it.

## 5. Attribution

The release candidate stores one validated first touch for 30 days. It accepts only allowlisted UTM fields, `gclid`, `fbclid`, canonical landing path, referrer domain, captured time, and anonymous ID. It never stores an arbitrary query string.

Deterministic attribution and self-reported acquisition remain separate facts. A later self-reported answer may fill an otherwise unknown classification but may not overwrite stronger first-touch evidence. Direct is an explicit classification; skipped self-report is not silently converted to Direct.

Internal OPS subdomains never count as referrals. Google, Bing, DuckDuckGo, and Yahoo referrers classify as organic search. An organic medium overrides a source name that could otherwise look paid; organic Instagram/Facebook/Meta/YouTube traffic classifies as organic social.

Raw click IDs and raw touchpoints expire after 30 days. The durable classified channel, basis, confidence, and reason remain. Historical unknown rows are not retroactively invented from aggregate Search Console, GA4, or App Store facts.

## 6. Warehouse and freshness

The release candidate uses one `analytics_sync_runs` row per source invocation. A source result is never converted to zero when its API is denied or unavailable.

| Source | Expected finalized date | Daily job |
|---|---|---|
| Search Console | D-3 | 09:24 UTC |
| GA4 marketing | D-2 | 09:44 UTC |
| GA4 web app | D-2 | 09:44 UTC |
| App Store Connect | D-2 when commerce reports exist | 09:04 UTC |
| Analytics health | Evaluates all sources after source jobs | 10:49 UTC |

Search Console and GA4 date partitions are replaced atomically. A restatement either replaces one complete date or leaves the prior facts intact. A bounded App Store walk remains `running` while a cursor is present and becomes `complete` only when the cycle closes.

Before 10:15 UTC, a running/partial source or a normal finalized-date lag is `expected_latency`, not a failure. A denied permission, invalid property mapping, explicit failed run, or stale source after the window is a failure.

## 7. Health and alert rules

The prepared health evaluator checks:

- exact property and measurement mapping;
- read permission on all three GA properties;
- Search Console D-3 and GA/App Store D-2 freshness;
- complete App Store traversal and non-empty downloads when commerce reports exist;
- fresh web product events whenever GA reports web sessions;
- zero schema-invalid events, duplicate IDs, and PII findings;
- explicit reasons for every unknown attribution row;
- zero trial, activation, paid, and revenue reconciliation deltas.

Health state is stored per source. One persistent `analytics_source_failed` notification is created only on a settled `healthy` to `failed` transition. Repeated failures do not duplicate it. Recovery resolves it automatically. `expected_latency` updates the observation without erasing the last settled state and never alerts.

The notification recipient must be an active user in the configured company and must be a company admin or account holder. The canonical environment pair is `OPS_PLATFORM_ALERT_USER_ID` plus `OPS_PLATFORM_ALERT_COMPANY_ID`; the database revalidates that identity on every transition.

## 8. Privacy and retention

Analytics must never contain names, email addresses, phone numbers, street addresses, free-form notes, auth tokens, secrets, full URLs, query strings, or resource/user/company identifiers. Hashing does not make PII appropriate for product analytics.

Appropriate properties are bounded counts, booleans, stable enum values, state transitions, and coarse UI context. Boolean presence fields such as `has_email` are allowed because they do not contain the email.

The staged database check rejects unsafe properties on every new insert/update while leaving legacy rows visible to the health scanner. The constraint is intentionally `NOT VALID` until production legacy findings are remediated.

Retention in the staged migration:

- aggregate raw `analytics_events` older than 12 months into non-identifying daily facts;
- delete the raw rows only after the aggregate write succeeds in the same transaction;
- delete expired raw touchpoints and clear retained click IDs after 30 days;
- remove company-linked raw events, touchpoints, and trial attribution on account deletion;
- preserve non-identifying aggregate facts where legally allowed.

## 9. Operational boundaries

The following are separate states and must be reported separately:

1. local implementation and tests;
2. local commit;
3. integration into local `main`;
4. push;
5. Vercel deployment;
6. production Supabase migration;
7. Google property/consent/key-event configuration;
8. iOS App Store release;
9. live source readback;
10. seven finalized days without unexplained gaps, duplicates, or reconciliation drift.

The system is not “dialed” until the final state is proven. No new paid analytics vendor is required. Incremental cost is existing Vercel cron/function usage, Google API quota, and Supabase storage/compute; plan headroom must be checked before production backfills and retention are enabled.
