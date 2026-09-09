# Google Ads Engine — Phase 1: Measurement — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use `custom-skills:executing-plans` to implement this plan task-by-task. Read the design spec first: `ops-software-bible/specs/2026-09-08-google-ads-engine-design.md` (§1, §3 are this phase). Spawn title for this plan: `GOOGLE ADS ENGINE - P1-1`.

**Goal:** Make a paid click measurable end to end: capture the Google click id on every signup path, send trial-started / trial-activated / paid events to Google through the Data Manager API, rebuild the conversion actions through a v25 client that can write safely, extend the warehouse to ad-group / ad / asset / keyword / click grain, and show the account's readiness on the admin ads page.

**Architecture:** Additive. The existing v23 read client becomes a v25 read+write client with `validateOnly` on every write. Conversion events are enqueued by database triggers into an outbox and sent hourly by a cron. try-ops gains the same first-touch cookie writer ops-site already has. The console gets a readiness ledger while the account is dark. Nothing in this phase spends money or enables a campaign.

**Tech Stack:** Next.js 15 (ops-web, try-ops), Supabase Postgres (`ijeekuhbatykdomumfjx`), Google Ads API v25 REST, Google Data Manager API v1 REST, `google-auth-library` service account, Vitest, the PG17 SQL harness (`tests/sql/*.mjs` pattern).

**Design System:** `ops-web/.interface-design/system.md` (tokens: `.glass-surface`, `text-text` / `text-text-2` / `text-text-3` / `text-text-mute`, `olive` positive, `rose` negative, `tan` attention, JetBrains Mono micro labels with `//` prefix, `EASE_SMOOTH`, no accent outside the primary CTA). Also read `ops-design-system/project/DESIGN.md`.

**Required Skills:** `custom-skills:executing-plans`, `ops-design`, `custom-skills:interface-design` (Task 10), `ops-copywriter:ops-copywriter` (Task 10 labels), `custom-skills:audit-design-system` (before Task 10 is called done), `supabase:supabase` (migrations), `superpowers:test-driven-development`, `superpowers:verification-before-completion`.

**Repos and worktrees:**

| Repo | Worktree to create | Branch |
|---|---|---|
| ops-web | `/Users/jacksonsweet/Projects/OPS/ops-web-ads-engine-p1` | `feat/ads-engine-p1` off `origin/main` |
| try-ops | work on the primary checkout `/Users/jacksonsweet/Projects/OPS/try-ops` (no sibling sessions use it) | `feat/first-touch-capture` off `origin/main` |
| ops-site | `/Users/jacksonsweet/Projects/OPS/ops-site-ads-engine-p1` | `feat/first-touch-gbraid` off `origin/main` (the primary ops-site checkout is 46 commits behind — never work there) |
| ops-software-bible | primary checkout, `main` | commits by name only; sibling WIP (`.DS_Store`, `.worktrees/`, `specs/future/`) is not yours |

**Hard rules for this phase:** every Google write goes through `validateOnly: true` first; never enable, create, or edit a campaign; never push (Jackson pushes; ops-web main auto-deploys to customers); commit by name, never `git add -A`; no `Co-Authored-By` trailers; every claim of "done" ships with the artifact under `ops-web/docs/artifacts/ads-engine/p1/`.

**Verified facts you must not re-derive** (2026-09-08 22:00 UTC probe):

- `validateOnly` mutate on `customers/4454506598/campaignBudgets:mutate` with `login-customer-id: 5448339076` → `403 authorizationError.ACTION_NOT_PERMITTED`. The service account `firebase-adminsdk-fbsvc@ops-ios-app.iam.gserviceaccount.com` is `READ_ONLY` on manager `5448339076` (`customer_user_access` id `6460209801`). Jackson is changing it to Standard; Task 1 re-probes.
- `customer.conversion_tracking_setting` returns only `conversionTrackingStatus: CONVERSION_TRACKING_MANAGED_BY_SELF`; `acceptedCustomerDataTerms` and `enhancedConversionsForLeadsEnabled` are absent (= false). Jackson is flipping both.
- `projects`: 349 rows across 4 companies; 57 were created within 2 minutes of their company's birth (bulk import). `projects.source` is null for all but 16 rows (`email` 10, `other` 6). Activation therefore excludes projects created within 2 minutes of company creation.
- `billing_events` columns: `id, stripe_event_id, event_type, company_id, stripe_customer_id, amount_cents, currency, occurred_at, received_at, raw`. Trigger `billing_events_first_paid` (`pmf_update_first_paid_at`) already stamps `trial_attributions.first_paid_at`.
- `companies` triggers include `companies_seed_trial_attribution` (`seed_trial_attribution_for_company`, AFTER INSERT) — the hook for `trial_started`.
- `trial_attributions` columns (prod): `id, company_id, utm_source, utm_medium, utm_campaign, utm_content, utm_term, gclid, fbclid, landing_url, trial_started_at, first_paid_at, attributed_channel, created_at, updated_at, referrer, first_touch_at, self_reported_source, attribution_basis, attribution_confidence, classification_reason, capture_version`. No `gbraid` / `wbraid` yet.
- RPC `record_first_touch_attribution(p_company_id uuid, p_touch jsonb)` (migration `20260831011800_first_touch_attribution_rpc.sql`) validates `anonymous_id`, `captured_at`, `landing_path`, `channel`, `basis`, `confidence`, `reason`, `version`; reads `gclid`/`fbclid`; nulls click ids older than 30 days.
- ops-web reads the cookie server-side in `src/app/api/setup/progress/route.ts` (step `company`) via `readServerFirstTouch(req.headers.get("cookie"))` → `recordTrialAttribution(db, companyId, touch)`. Both cookie names are read: `__ops_first_touch` (canonical) and `ops_attribution` (legacy).
- ops-site `origin/main` middleware already writes `__ops_first_touch` on `.opsapp.co` via `src/lib/analytics/first-touch.ts` (`resolveFirstTouch`, `serializeFirstTouchPayload`). try-ops writes nothing.
- try-ops's native signup creates companies through Bubble (`app/api/company/update/route.ts` → `${NEXT_PUBLIC_BUBBLE_BASE_URL}/api/1.1/wf/update_company`). It is not a Supabase company-creation path. Paid landing CTAs (P2) point at `https://app.opsapp.co/register`.
- Data Manager API: `POST https://datamanager.googleapis.com/v1/events:ingest`; OAuth scope `https://www.googleapis.com/auth/datamanager`; request `{ destinations: [{ operatingAccount: { accountType: "GOOGLE_ADS", accountId }, loginAccount: { accountType: "GOOGLE_ADS", accountId }, productDestinationId }], events: [Event], consent?, validateOnly?, encoding: "HEX" | "BASE64" }`; `Event` fields used: `transactionId`, `eventTimestamp` (RFC 3339 with offset), `eventSource: "WEB"`, `adIdentifiers: { gclid | gbraid | wbraid }`, `userData: { userIdentifiers: [{ emailAddress: <sha256 hex> }] }`, `consent: { adUserData: "CONSENT_GRANTED", adPersonalization: "CONSENT_GRANTED" }`, `conversionValue` (double), `currency`. ≤ 2,000 events per request. Response `{ requestId, fieldWarnings[] }`.
- Google Ads API v25 REST: `POST /v25/customers/{id}/googleAds:searchStream` returns a JSON array of `{ results, fieldMask, requestId }` chunks; `POST /v25/customers/{id}/googleAds:mutate` takes `{ mutateOperations: [{ conversionActionOperation: { create | update+updateMask | remove } | campaignBudgetOperation … }], partialFailure, validateOnly }`. Do not send `pageSize` anywhere.
- Cron minutes already taken hourly in `ops-web/vercel.json`: 17, 19, 37, 38, 39 plus `*/5` grids; `41 * * * *` is free.

---

## Task 0: Worktrees, dependencies, baselines

**Files:** none (environment)

**Step 1: ops-web worktree with its own dependencies**

```bash
cd /Users/jacksonsweet/Projects/OPS/ops-web && git fetch origin && git worktree add /Users/jacksonsweet/Projects/OPS/ops-web-ads-engine-p1 -b feat/ads-engine-p1 origin/main
cd /Users/jacksonsweet/Projects/OPS/ops-web-ads-engine-p1 && npm ci && cp -L /Users/jacksonsweet/Projects/OPS/ops-web/.env.local .env.local
```

Expected: `npm ci` completes; `.env.local` is a real file (not a symlink). Never print its values.

**Step 2: baselines**

```bash
cd /Users/jacksonsweet/Projects/OPS/ops-web-ads-engine-p1 && npx tsc --noEmit -p tsconfig.json 2>&1 | tail -3
cd /Users/jacksonsweet/Projects/OPS/ops-web-ads-engine-p1 && npx vitest run tests/unit/analytics tests/unit/admin tests/unit/pmf 2>&1 | tail -6
```

Record the pre-existing `tsc` error count in `docs/artifacts/ads-engine/p1/baseline.txt` (main is known to carry a few errors in bug-report picker test files; they are not yours to fix).

**Step 3: ops-site and try-ops branches**

```bash
cd /Users/jacksonsweet/Projects/OPS/ops-site && git fetch origin && git worktree add /Users/jacksonsweet/Projects/OPS/ops-site-ads-engine-p1 -b feat/first-touch-gbraid origin/main
cd /Users/jacksonsweet/Projects/OPS/try-ops && git fetch origin && git status -sb && git checkout -b feat/first-touch-capture origin/main
```

If try-ops has uncommitted changes you did not make, stop and report; do not stash.

---

## Task 1: Write-access probe (gate)

**Files:**
- Create: `ops-web/scripts/ads/validate-probe.mjs`
- Create: `ops-web/docs/ads/runbook.md`
- Create: `ops-web/docs/artifacts/ads-engine/p1/probe-<YYYY-MM-DD>.json`

**Step 1: write the probe** — a standalone Node script (no `@/` imports) that reads `.env.local` (handle the raw-base64 private key exactly as `src/lib/firebase/parse-private-key.ts` does), obtains an access token with scope `https://www.googleapis.com/auth/adwords`, and performs three read-only calls with `login-customer-id: 5448339076`:

1. `POST /v25/customers/4454506598/campaignBudgets:mutate` with `{ operations: [{ create: { name: "probe <ts>", amountMicros: "1000000", deliveryMethod: "STANDARD" } }], validateOnly: true }` — expect `200` once Jackson's role change lands; `403 ACTION_NOT_PERMITTED` before.
2. `googleAds:search` on customer `4454506598`: `SELECT customer.conversion_tracking_setting.accepted_customer_data_terms, customer.conversion_tracking_setting.enhanced_conversions_for_leads_enabled FROM customer`.
3. `googleAds:search` on manager `5448339076`: `SELECT customer_user_access.email_address, customer_user_access.access_role FROM customer_user_access`.

Write `{ probedAt, mutateValidateOnly: { status, errorCode }, acceptedCustomerDataTerms, enhancedConversionsForLeadsEnabled, serviceAccountRole }` to the artifact path and print it.

**Step 2: run it**

```bash
cd /Users/jacksonsweet/Projects/OPS/ops-web-ads-engine-p1 && node scripts/ads/validate-probe.mjs
```

**Step 3: gate.** If `mutateValidateOnly.status !== 200` or either setting is not `true`: write the result into `docs/ads/runbook.md` under "Readiness probe", commit, and **stop the phase at the end of Task 9** (everything up to the warehouse and console work can proceed; Tasks 4's live-ingest rehearsal and Task 11's proof cannot). Report to Jackson exactly which of the three account actions is still missing.

**Step 4: commit**

```bash
git add scripts/ads/validate-probe.mjs docs/ads/runbook.md docs/artifacts/ads-engine/p1/probe-*.json
git commit -m "chore(ads): add write-access probe and engine runbook"
```

---

## Task 2: Ads API client → v25, searchStream, mutate

**Files:**
- Modify: `ops-web/src/lib/analytics/google-ads-client.ts`
- Modify: `ops-web/tests/unit/analytics/google-ads-client.test.ts`
- Modify: `ops-web/src/lib/admin/ads-provider-health.ts` (only if the error class shape changes; keep `GoogleAdsApiError` message template byte-identical)

**Step 1: failing tests** — add to the existing suite (keep its mocking style: `vi.mock("google-auth-library")`, `vi.stubGlobal("fetch")`, `vi.resetModules()` + dynamic import):

```ts
it("targets v25 for every request", async () => {
  installFetch([customerClientRow(MANAGER_ID, 0, true), customerClientRow(CLIENT_ID, 1, false)], []);
  const client = await importClient();
  await client.getAccountSummaryForRange(new Date("2026-09-01"), new Date("2026-09-07"));
  for (const r of requests) expect(r.url).toContain("/v25/");
});

it("reads reports through searchStream and merges chunks in order", async () => {
  // discovery answers on :search; data answers on :searchStream as an ARRAY of chunks
  installStreamFetch([customerClientRow(MANAGER_ID, 0, true), customerClientRow(CLIENT_ID, 1, false)], [
    { results: [{ segments: { date: "2026-09-01" }, metrics: { costMicros: "1000000", clicks: "1", conversions: 0 } }] },
    { results: [{ segments: { date: "2026-09-02" }, metrics: { costMicros: "2000000", clicks: "2", conversions: 0 } }] },
  ]);
  const client = await importClient();
  const rows = await client.getDailySpendForRange(new Date("2026-09-01"), new Date("2026-09-02"));
  expect(rows.map((r) => r.date)).toEqual(["2026-09-01", "2026-09-02"]);
  const stream = requests.find((r) => r.url.endsWith("googleAds:searchStream"));
  expect(stream).toBeDefined();
  expect(stream!.body).not.toHaveProperty("pageSize");
});

it("mutate sends validateOnly + partialFailure and login-customer-id, and decodes partial failures by operation index", async () => {
  installMutateFetch({
    partialFailureError: { details: [{ errors: [{ errorCode: { policyFindingError: "POLICY_FINDING" }, message: "x", location: { fieldPathElements: [{ fieldName: "mutate_operations", index: 1 }] } }] }] },
    mutateOperationResponses: [{ campaignBudgetResult: { resourceName: "customers/1/campaignBudgets/2" } }, {}],
  });
  const client = await importClient();
  const result = await client.mutateGoogleAds([{ campaignBudgetOperation: { create: { name: "a" } } }, { campaignBudgetOperation: { create: { name: "b" } } }], { validateOnly: true });
  const req = requests.find((r) => r.url.endsWith("googleAds:mutate"))!;
  expect(req.body.validateOnly).toBe(true);
  expect(req.body.partialFailure).toBe(true);
  expect(req.loginCustomerId).toBe(MANAGER_ID);
  expect(result.results[0]?.campaignBudgetResult?.resourceName).toBe("customers/1/campaignBudgets/2");
  expect(result.failures).toEqual([{ index: 1, code: "POLICY_FINDING", message: "x" }]);
});
```

**Step 2: run to confirm they fail** — `npx vitest run tests/unit/analytics/google-ads-client.test.ts` → the three new tests fail (`/v23/`, no searchStream, `mutateGoogleAds is not a function`).

**Step 3: implement**

- `const ADS_API_VERSION = "v25";`
- Add `rawSearchStream(accessToken, customerId, gaql, loginCustomerId)`: POST `googleAds:searchStream`, body `{ query }`, parse the JSON array, concatenate `chunk.results` in order, log `chunk.requestId` on failure. `queryGoogleAds` switches to it; `resolveServingCustomer` keeps `rawSearch` (tiny result).
- Add and export:

```ts
export interface MutateOperation { [service: `${string}Operation`]: Record<string, unknown> }
export interface MutateFailure { index: number | null; code: string; message: string }
export interface MutateResult { results: Array<Record<string, unknown>>; failures: MutateFailure[]; requestId?: string }

export async function mutateGoogleAds(
  operations: MutateOperation[],
  options: { validateOnly?: boolean; partialFailure?: boolean } = {}
): Promise<MutateResult>
```

  It resolves the serving customer, POSTs `{ mutateOperations: operations, partialFailure: options.partialFailure ?? true, validateOnly: options.validateOnly ?? false, responseContentType: "MUTABLE_RESOURCE" }` to `googleAds:mutate`, throws `GoogleAdsApiError` on non-2xx, and decodes `partialFailureError.details[].errors[]` into `failures` using `location.fieldPathElements[0].index` (null when absent) and the first key of `errorCode` as `code`.
- Export `getServingCustomerIds(): Promise<{ servingId: string; loginId?: string }>` for the Data Manager client (Task 5).

**Step 4: run the suite** — `npx vitest run tests/unit/analytics/google-ads-client.test.ts` → all green, including the existing PAGE_SIZE and manager-resolution tests.

**Step 5: typecheck + commit**

```bash
npx tsc --noEmit -p tsconfig.json 2>&1 | tail -3
git add src/lib/analytics/google-ads-client.ts tests/unit/analytics/google-ads-client.test.ts
git commit -m "feat(ads): move the Google Ads client to v25 with searchStream reads and validateOnly mutates"
```

---

## Task 3: Conversion actions — planner + idempotent setup route

**Files:**
- Create: `ops-web/src/lib/ads/conversion-actions.ts`
- Create: `ops-web/src/app/api/internal/ads/setup/conversion-actions/route.ts`
- Create: `ops-web/tests/unit/ads/conversion-actions.test.ts`

**Design:** a pure planner turns the live list of conversion actions into mutate operations; a CRON_SECRET-protected internal route runs the plan (`?validateOnly=1` first, then real) and records the resulting resource names in `ads_conversion_actions` (table from Task 4). Idempotent: running it twice produces zero operations the second time.

**Target state (from spec §3.3):**

| kind | name | type | category | primaryForGoal | includeInConversionsMetric | countingType | clickThroughLookbackWindowDays |
|---|---|---|---|---|---|---|---|
| `trial_started` | `OPS · Trial started` | `UPLOAD_CLICKS` | `SIGNUP` | true | true | `ONE_PER_CLICK` | 30 |
| `trial_activated` | `OPS · Trial activated` | `UPLOAD_CLICKS` | `QUALIFIED_LEAD` | false | false | `ONE_PER_CLICK` | 30 |
| `paid` | `OPS · Paid subscription` | `UPLOAD_CLICKS` | `SUBSCRIBE_PAID` | false | false | `ONE_PER_CLICK` | 90 |

Existing actions: names `Join Ops SIgnup`, `Homepage Signup`, `Quiz Signup v2` → `remove`; names ending `sign_up`, `login` and `OPS APP First open` → `update` with `updateMask: "primaryForGoal,includeInConversionsMetric"` to `false,false`. Everything else untouched.

**Step 1: failing tests** for `planConversionActionOperations(existing)`:

```ts
it("creates the three OPS actions when none exist", () => {
  const ops = planConversionActionOperations([]);
  expect(ops.map((o) => o.conversionActionOperation.create?.name)).toEqual(["OPS · Trial started", "OPS · Trial activated", "OPS · Paid subscription"]);
  expect(ops[0].conversionActionOperation.create).toMatchObject({ type: "UPLOAD_CLICKS", category: "SIGNUP", primaryForGoal: true, includeInConversionsMetric: true, countingType: "ONE_PER_CLICK", clickThroughLookbackWindowDays: 30, status: "ENABLED" });
});
it("is idempotent once the actions exist with the right settings", () => { /* existing = target → [] */ });
it("demotes the Firebase iOS actions and removes the Bubble-era ones", () => { /* update ops with updateMask, remove ops by resourceName */ });
it("never touches unknown actions", () => { /* an unrelated ENABLED action yields no op */ });
```

**Step 2: run to fail.** **Step 3: implement** the planner (pure) plus:

```ts
export async function ensureConversionActions(opts: { validateOnly: boolean }): Promise<{ operations: MutateOperation[]; result: MutateResult; recorded: Array<{ kind: string; resourceName: string }> }>
```

which runs `SELECT conversion_action.resource_name, conversion_action.id, conversion_action.name, conversion_action.type, conversion_action.category, conversion_action.status, conversion_action.primary_for_goal, conversion_action.include_in_conversions_metric, conversion_action.counting_type, conversion_action.click_through_lookback_window_days FROM conversion_action WHERE conversion_action.status != 'REMOVED'`, plans, mutates, and — when not `validateOnly` — upserts `ads_conversion_actions (kind, resource_name, google_id, name)` for the three kinds (resolving by name after the mutate).

Route: `POST /api/internal/ads/setup/conversion-actions?validateOnly=1` — `Authorization: Bearer ${CRON_SECRET}` (reuse the exact header check from `src/app/api/cron/ads-sync/route.ts`), `runtime = "nodejs"`, returns the operations, failures, and recorded rows; 405 on GET; `cache-control: no-store`.

**Step 4: tests green; typecheck; commit** `feat(ads): plan and apply the OPS conversion actions idempotently`.

**Step 5 (only after Task 1's gate is green):** run against production with `validateOnly=1` from a local dev server (`npm run dev -- -p 3210` in the worktree; `curl -sS -X POST -H "Authorization: Bearer $CRON_SECRET" "http://localhost:3210/api/internal/ads/setup/conversion-actions?validateOnly=1"`), save the JSON to `docs/artifacts/ads-engine/p1/conversion-actions-validate.json`, then run it for real and save `conversion-actions-apply.json`. Re-run once more and confirm `operations: []`.

---

## Task 4: Migration — conversion outbox, click-id columns, activation trigger

**Files:**
- Create: `ops-web/supabase/migrations/20260909120000_ads_conversion_outbox.sql`
- Create: `ops-web/tests/sql/ads-conversion-outbox-runtime.mjs` (PG17 harness, same shape as `tests/sql/social-editorial-assignments-runtime.mjs`: start the disposable server with `LC_ALL=C`, stub only the tables the migration references)
- Mirror: `ops-software-bible/migrations/20260909120000_ads_conversion_outbox.sql` (byte-identical)

**Step 1: write the harness test first** (assertions): after applying the migration on a database that has minimal `companies`, `projects`, `billing_events`, `trial_attributions`, `users` stubs:
1. inserting a company enqueues exactly one `trial_started` row with `transaction_id = 'trial_started:<company_id>'`; inserting the same company id twice (second insert must fail on PK — instead call `ads_enqueue_conversion_event` twice) yields one row.
2. inserting a project 60 seconds after company creation enqueues nothing; inserting one 3 minutes after enqueues `trial_activated` once; a second project enqueues nothing.
3. inserting `billing_events (event_type='invoice.paid', company_id, amount_cents=14000, occurred_at)` for a company with `subscription_plan='team'` stamps `first_paid_at` (existing behaviour) and enqueues `paid` with `value = 1680`, `currency='CAD'`; a second `invoice.paid` enqueues nothing.
4. `ads_plan_annual_value('starter', null) = 1080`, `('team', null) = 1680`, `('business', null) = 2280`, `(null, 9000) = 1080` (cents × 12 / 100), `(null, null) is null`.
5. `trial_attributions` has `gbraid` and `wbraid` columns; `record_first_touch_attribution` stores them from `p_touch` and nulls them for touches older than 30 days exactly like `gclid`.
6. RLS is enabled on both new tables and `anon`/`authenticated` have no privileges (query `has_table_privilege`).

**Step 2: run the harness → fails (relation does not exist).**

**Step 3: write the migration** (complete SQL; keep the house style of `20260619052545_ads_daily_search_terms.sql`):

```sql
-- Google Ads engine, phase 1: conversion outbox + click-id columns + activation trigger.
-- Service-role only tables; triggers never abort the business write they observe.

create table if not exists public.ads_conversion_actions (
  kind text primary key check (kind in ('trial_started','trial_activated','paid')),
  resource_name text not null,
  google_id text not null,
  name text not null,
  synced_at timestamptz not null default now()
);
alter table public.ads_conversion_actions enable row level security;
revoke all on public.ads_conversion_actions from anon, authenticated;

create table if not exists public.ads_conversion_events (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  kind text not null check (kind in ('trial_started','trial_activated','paid')),
  occurred_at timestamptz not null,
  value numeric(12,2),
  currency text not null default 'CAD',
  transaction_id text not null unique,
  state text not null default 'queued' check (state in ('queued','sent','failed','skipped')),
  attempts integer not null default 0,
  next_attempt_at timestamptz not null default now(),
  last_error text,
  sent_at timestamptz,
  google_request_id text,
  created_at timestamptz not null default now()
);
alter table public.ads_conversion_events enable row level security;
revoke all on public.ads_conversion_events from anon, authenticated;
create index if not exists ads_conversion_events_ready_idx
  on public.ads_conversion_events (state, next_attempt_at) where state = 'queued';

alter table public.trial_attributions
  add column if not exists gbraid text,
  add column if not exists wbraid text;

create or replace function public.ads_plan_annual_value(p_plan text, p_amount_cents bigint)
returns numeric language sql immutable as $$
  select case p_plan
    when 'starter' then 1080::numeric
    when 'team' then 1680::numeric
    when 'business' then 2280::numeric
    else case when p_amount_cents is null then null else round(p_amount_cents::numeric * 12 / 100, 2) end
  end
$$;

create or replace function public.ads_enqueue_conversion_event(
  p_company_id uuid, p_kind text, p_occurred_at timestamptz, p_value numeric
) returns void language plpgsql security definer set search_path to 'public', 'pg_temp' as $$
begin
  begin
    insert into public.ads_conversion_events (company_id, kind, occurred_at, value, transaction_id)
    values (p_company_id, p_kind, coalesce(p_occurred_at, now()), p_value, p_kind || ':' || p_company_id::text)
    on conflict (transaction_id) do nothing;
  exception when others then
    raise warning 'ads_enqueue_conversion_event(%, %) failed: %', p_kind, p_company_id, sqlerrm;
  end;
end $$;
revoke all on function public.ads_enqueue_conversion_event(uuid, text, timestamptz, numeric) from public, anon, authenticated;

-- trial_started: ride the existing seed trigger so every platform is covered.
create or replace function public.seed_trial_attribution_for_company()
returns trigger language plpgsql security definer set search_path to 'public', 'pg_temp' as $$
begin
  begin
    insert into public.trial_attributions (company_id, trial_started_at, attributed_channel)
    values (new.id, coalesce(new.trial_start_date, new.created_at, now()), 'unknown')
    on conflict (company_id) do nothing;
  exception when others then
    raise warning 'seed_trial_attribution_for_company failed for company %: %', new.id, sqlerrm;
  end;
  perform public.ads_enqueue_conversion_event(new.id, 'trial_started', coalesce(new.trial_start_date, new.created_at, now()), null);
  return new;
end $$;

-- trial_activated: the company's first real project, excluding bulk imports.
create or replace function public.ads_enqueue_trial_activation()
returns trigger language plpgsql security definer set search_path to 'public', 'pg_temp' as $$
declare v_company_created timestamptz;
begin
  if new.deleted_at is not null then return new; end if;
  select c.created_at into v_company_created from public.companies c where c.id = new.company_id;
  if v_company_created is null or new.created_at < v_company_created + interval '2 minutes' then return new; end if;
  if exists (select 1 from public.projects p where p.company_id = new.company_id and p.id <> new.id and p.deleted_at is null and p.created_at < new.created_at) then
    return new;
  end if;
  perform public.ads_enqueue_conversion_event(new.company_id, 'trial_activated', new.created_at, null);
  return new;
end $$;
drop trigger if exists projects_ads_enqueue_trial_activation on public.projects;
create trigger projects_ads_enqueue_trial_activation
  after insert on public.projects for each row execute function public.ads_enqueue_trial_activation();

-- paid: extend the existing first-paid stamp.
create or replace function public.pmf_update_first_paid_at()
returns trigger language plpgsql set search_path to 'public', 'pg_temp' as $$
declare v_plan text; v_stamped boolean := false;
begin
  if new.event_type = 'invoice.paid' and new.company_id is not null then
    update public.trial_attributions
       set first_paid_at = new.occurred_at, updated_at = now()
     where company_id = new.company_id and first_paid_at is null;
    v_stamped := found;
    if v_stamped then
      select c.subscription_plan into v_plan from public.companies c where c.id = new.company_id;
      perform public.ads_enqueue_conversion_event(new.company_id, 'paid', new.occurred_at, public.ads_plan_annual_value(v_plan, new.amount_cents));
    end if;
  end if;
  return new;
end $$;
```

Then `create or replace function public.record_first_touch_attribution(...)` — copy the full body from `20260831011800_first_touch_attribution_rpc.sql` and add `v_gbraid`/`v_wbraid` alongside `v_gclid` (declare, read `p_touch ->> 'gbraid'` / `'wbraid'` with the same 512-char cap, null both when older than 30 days, and include them in both `update` branches with `coalesce(gbraid, v_gbraid)` semantics). Do not change any validation rule.

**Step 4: harness green** (`node tests/sql/ads-conversion-outbox-runtime.mjs`). **Step 5:** mirror the file into the bible `migrations/` (byte-identical; `md5` both). **Step 6: commit** (ops-web) `feat(ads): conversion outbox, activation trigger, and gbraid/wbraid capture` and (bible) `docs(migrations): mirror 20260909120000_ads_conversion_outbox`.

**Step 7: apply to production** through the Supabase MCP `apply_migration` (name `ads_conversion_outbox`) — prod is low-tenant and direct migrations are the house rule. Verify by object, never by ledger version: `select proname from pg_proc where proname in ('ads_enqueue_conversion_event','ads_enqueue_trial_activation','ads_plan_annual_value')`, `select tgname from pg_trigger where tgname='projects_ads_enqueue_trial_activation'`, `select column_name from information_schema.columns where table_name='trial_attributions' and column_name in ('gbraid','wbraid')`. Save the verification output to `docs/artifacts/ads-engine/p1/migration-verify.txt`.

---

## Task 5: Data Manager client + outbox sender + hourly cron

**Files:**
- Create: `ops-web/src/lib/ads/identifier-hashing.ts`
- Create: `ops-web/src/lib/ads/data-manager-client.ts`
- Create: `ops-web/src/lib/ads/conversion-outbox.ts`
- Create: `ops-web/src/app/api/cron/ads-conversions/route.ts`
- Modify: `ops-web/vercel.json` (add `{ "path": "/api/cron/ads-conversions", "schedule": "41 * * * *" }`)
- Create: `ops-web/tests/unit/ads/identifier-hashing.test.ts`, `ops-web/tests/unit/ads/conversion-outbox.test.ts`, `ops-web/tests/unit/ads/data-manager-client.test.ts`
- Modify: `ops-web/tests/unit/cron-inventory*.test.ts` if a cron-inventory test enumerates `vercel.json` (search `grep -rl "vercel.json" tests/`) — add the new path to its expected list

**Step 1: failing tests**

`identifier-hashing.test.ts`:
```ts
it("normalizes then SHA-256-hex hashes an email", () => {
  expect(hashEmail("  Jack.Sweet@Gmail.com ")).toBe(sha256hex("jacksweet@gmail.com")); // gmail dots removed
  expect(hashEmail("Owner@Example.com")).toBe(sha256hex("owner@example.com"));         // non-gmail keeps dots
  expect(hashEmail("")).toBeNull();
});
```

`conversion-outbox.test.ts` (pure builder + state machine, repository injected):
```ts
it("builds one ingest request per kind with the kind's destination and ≤2000 events", ...);
it("attaches gclid/gbraid/wbraid from trial_attributions and hashed owner email; skips events with neither identifier as 'skipped'", ...);
it("uses transaction_id, eventSource WEB, CONSENT_GRANTED, HEX encoding, RFC3339 timestamps with offset, and value+currency only for paid", ...);
it("marks sent with requestId on success; on failure increments attempts with backoff 15m·2^n and sets failed after 5", ...);
it("only picks queued rows whose next_attempt_at <= now and created_at <= now - 10 minutes", ...);
```

`data-manager-client.test.ts`: fetch stub asserting URL `https://datamanager.googleapis.com/v1/events:ingest`, `Authorization` bearer, JSON body passthrough, `validateOnly` honoured, non-2xx → typed `DataManagerApiError { status, body }`.

**Step 2: run → fail.** **Step 3: implement**

- `identifier-hashing.ts`: `normalizeEmail` (trim, lowercase; for `gmail.com`/`googlemail.com` remove `.` in the local part), `hashEmail` → `createHash("sha256").update(normalized).digest("hex")` or null.
- `data-manager-client.ts`: its own `GoogleAuth` instance (same credential loader as the Ads client — extract the credential-building code into `src/lib/google/service-account-credentials.ts` and reuse it from both) with scope `https://www.googleapis.com/auth/datamanager`; `ingestEvents(request, { validateOnly })` → POST; returns `{ requestId, fieldWarnings }`.
- `conversion-outbox.ts`:
  - `selectReadyEvents(db, limit=2000)`: `state='queued' and next_attempt_at <= now() and created_at <= now() - interval '10 minutes'` ordered by `created_at`.
  - `resolveIdentifiers(db, companyIds)`: owner email = `users` row for the company ordered by `is_company_admin desc, created_at asc` limit 1; click ids from `trial_attributions`.
  - `buildIngestRequests(events, identifiers, actions, accounts)` → one request per kind: `destinations: [{ operatingAccount: { accountType: "GOOGLE_ADS", accountId: servingId }, loginAccount: { accountType: "GOOGLE_ADS", accountId: loginId }, productDestinationId: actions[kind].google_id }]`, `encoding: "HEX"`, events as in the spec. Event `eventTimestamp` = `occurred_at` formatted `YYYY-MM-DDTHH:mm:ss-07:00`-style in `America/Vancouver` (use `Intl.DateTimeFormat` with `timeZoneName: "longOffset"` or a small formatter; assert in tests).
  - `processOutbox({ validateOnly })`: select → resolve → build → send → persist per event (`sent` + `google_request_id`, or `attempts+1`, `next_attempt_at = now + 15min * 2^attempts`, `last_error`, `failed` at 5). Events lacking both a click id and an email → `skipped` with `last_error='no_identifier'`.
  - On any `failed` transition, raise the in-app notification `ADS CONVERSIONS FAILING` (persistent, dedupe key `ads-conversions:failed`, action `/admin/google-ads`) through the PMF operator sender in `src/lib/notifications/pmf-send.ts` (read the file for its exported function name; kind `threshold_alert`, `inAppTitle`, `inAppBody`, `inAppActionUrl`).
- Cron route: same skeleton as `ads-sync` (CRON_SECRET, `runWithCronWorkloadControl({ workloadKey: "ads-conversions", leaseSeconds: 120 })`), returns `{ sent, failed, skipped, requestIds }`. `maxDuration = 60`.

**Step 4: green; typecheck; commit** `feat(ads): send trial, activation, and paid events to Google through the Data Manager API`.

**Step 5: rehearsal (after Task 1's gate is green and Task 3 applied):** insert a synthetic queued event for a real test company you own (or the PMF persona pool company; see memory `reference_persona_test_pool_prod_fixture`) with a fake `gclid`, run `processOutbox({ validateOnly: true })` through a one-off `curl` to the cron route with `?validateOnly=1` support (add the flag to the route, honoured only when the bearer is CRON_SECRET), capture the `requestId` and any `fieldWarnings` to `docs/artifacts/ads-engine/p1/data-manager-validate.json`. Then run it for real once and capture `data-manager-live.json`. Do not delete the synthetic event; mark it `skipped` afterwards with `last_error='rehearsal'` so the ledger stays honest.

---

## Task 6: try-ops — first-touch cookie on `.opsapp.co`

**Files (try-ops):**
- Create: `lib/analytics/first-touch.ts` (copy `ops-site` `origin/main:src/lib/analytics/first-touch.ts` verbatim, then add `'gbraid', 'wbraid'` to `CLICK_ID_KEYS`, to `FirstTouchPayload`, and to the `prioritized` list right after `gclid`)
- Modify: `middleware.ts` — add `attachFirstTouch(request, response)` exactly as ops-site's middleware does (cookie `__ops_first_touch`, `domain: '.opsapp.co'` when the host is `opsapp.co` or a subdomain, 30 days, `SameSite=Lax`, `httpOnly: false`), applied on every matched path; extend `matcher` to also cover `/job-management`, `/scheduling`, `/quotes-invoices`, `/compare/:path*` (P2 creates them; the cookie must be there on day one)
- Create: `vitest.config.ts`, `tests/first-touch.test.ts`, `tests/middleware.test.ts`; `package.json` devDependency `vitest` + script `"test": "vitest run"`

**Step 1: failing tests** — port the relevant cases from `ops-site/src/lib/analytics/__tests__/first-touch.test.ts` (extracts gclid/gbraid/wbraid/utm; ignores OPS referrers; caps oversized payloads) plus a middleware test that builds a `NextRequest` for `https://try.opsapp.co/?gclid=abc&utm_source=google&utm_medium=cpc` and asserts the response `Set-Cookie` contains `__ops_first_touch=`, `Domain=.opsapp.co`, `Max-Age=2592000`, `SameSite=Lax`, and that a second request carrying the cookie does not rewrite it.

**Step 2: fail → Step 3: implement → Step 4: green** (`npm test`). **Step 5:** `npx tsc --noEmit` clean. **Step 6: commit** `feat(attribution): capture Google click ids into the shared first-touch cookie`.

---

## Task 7: gbraid/wbraid everywhere the click id is read

**Files:**
- ops-web: `src/lib/pmf/utm-capture.ts` (`CLICK_ID_KEYS` → `["gclid","gbraid","wbraid","fbclid"]`; `FirstTouch` gains `gbraid?`, `wbraid?`; `cookieSafeTouch` prioritized list adds both after `gclid`), `src/lib/pmf/attribution.ts` (`if (input.gclid || input.gbraid || input.wbraid) → google_ads / verified_click_id / reason "google_click_id_present"`; `AttributionInput` gains both), `src/lib/pmf/trial-attribution.ts` (pass both through to the RPC payload — it already spreads `touch`), tests `tests/unit/pmf/utm-capture.test.ts`, `tests/unit/pmf/attribution.test.ts`
- ops-site (worktree): `src/lib/analytics/first-touch.ts` and `src/lib/spec/attribution.ts` — add both keys; `src/lib/analytics/__tests__/first-touch.test.ts` cases

**Steps:** failing tests → implement → green → typecheck → commits: ops-web `feat(attribution): recognise gbraid and wbraid as Google click ids`; ops-site `feat(attribution): capture gbraid and wbraid in the first-touch cookie`.

---

## Task 8: Warehouse extension (ad group / ad / asset / keyword / click grain, entity snapshot, funnel view)

**Files:**
- Create: `ops-web/supabase/migrations/20260909123000_ads_warehouse_grain.sql` (+ bible mirror)
- Modify: `ops-web/src/lib/analytics/google-ads-client.ts` (new report queries), `ops-web/src/lib/admin/ads-history-types.ts`, `ops-web/src/lib/admin/ads-history-queries.ts`, `ops-web/src/lib/admin/ads-history-sync.ts`, `ops-web/src/app/api/cron/ads-sync/route.ts`
- Create: `ops-web/tests/unit/admin/ads-history-sync-grain.test.ts`, `ops-web/tests/sql/ads-warehouse-grain-runtime.mjs`

**Migration contents:**

- `ads_daily_ad_group (date, campaign_id text, campaign_name, ad_group_id text, ad_group_name, status, spend, clicks, impressions, conversions, ctr, synced_at; pk (date, ad_group_id))`
- `ads_daily_ad (date, ad_group_id, ad_id text, ad_type, status, ad_strength, approval_status, review_status, final_url, spend, clicks, impressions, conversions, ctr, synced_at; pk (date, ad_id))`
- `ads_daily_asset (date, ad_id, asset_id text, field_type, performance_label, pinned_field, text, impressions, clicks, conversions, synced_at; pk (date, ad_id, asset_id, field_type))`
- `ads_daily_keyword`: `drop table` and recreate with pk `(date, ad_group_id, criterion_id)` and columns `campaign_id, campaign_name, ad_group_id, ad_group_name, criterion_id text, keyword, match_type, status, quality_score, spend, clicks, impressions, conversions, average_cpc, synced_at` (the table has 0 rows and its old key `(date, keyword)` cannot hold one keyword in two ad groups)
- `ads_entities (resource_name text primary key, entity_type text, parent_resource_name text, name text, status text, payload jsonb, labels text[], snapshot_at timestamptz)` — one row per campaign, campaign budget, ad group, ad, keyword, negative keyword, shared set, label
- `ads_click_map (gclid text primary key, click_date date, campaign_id text, ad_group_id text, ad_id text, criterion_id text, keyword text, synced_at)`
- view `ads_funnel_by_keyword`: join `trial_attributions` (via `gclid` → `ads_click_map`) to companies and the outbox states, grouped by campaign / ad group / keyword / ad: `clicks` (from `ads_daily_keyword`), `trials`, `activated`, `paid`, `spend`, `cost_per_trial`, `cost_per_paid` — `security_invoker` is NOT used; service-role only like the tables
- RLS deny-all + revokes on every new table; indexes on `(date desc)`.

**Sync code:** `queryDailyAdGroupData`, `queryDailyAdData` (from `ad_group_ad` with `ad_group_ad.ad_strength`, `ad_group_ad.policy_summary.approval_status/review_status`, `ad_group_ad.ad.final_urls`), `queryDailyAssetData` (`ad_group_ad_asset_view` with `performance_label`, `pinned_field`, `asset.text_asset.text`), `queryDailyKeywordData` (`keyword_view` with `ad_group_criterion.criterion_id`, `quality_info.quality_score`, `metrics.average_cpc`), `queryClickMap(date)` (`click_view` — must be filtered to exactly one `segments.date` per query: `click_view.gclid, click_view.ad_group_ad, click_view.keyword, campaign.id, ad_group.id, segments.date`), `queryEntitySnapshot()` (campaign, campaign_budget, ad_group, ad_group_ad with full RSA assets + pins, ad_group_criterion keywords, campaign_criterion negatives, shared_set + shared_criterion, label). `syncDay` grows to write all grains; new `syncEntitySnapshot()`; `ads-sync` route runs: entity snapshot, trailing 3 days of every grain, and on Mondays the trailing 30 days. Keep the `search_term` sync. Budget: this is ≤ 12 `searchStream` calls per day; note it in the runbook.

**Tests:** unit tests stub the client functions and assert row shapes + upsert `onConflict` keys; the SQL harness proves the view arithmetic with seeded rows (2 clicks, 1 trial, 1 paid → `cost_per_trial = spend/1`).

**Commit** `feat(ads): warehouse the ad-group, ad, asset, keyword, and click grains with a funnel view`, mirror + apply the migration as in Task 4 (verify by object), save verification output.

---

## Task 9: Readiness state + probe route

**Files:**
- Create: `ops-web/src/lib/ads/readiness.ts`
- Create: `ops-web/src/app/api/internal/ads/setup/probe/route.ts` (CRON_SECRET; runs the Task 1 checks server-side and stores the result in `ads_sync_status` row `id = 'engine-readiness'` as `error = null`, `backfill_progress = <json>` — reuse the existing jsonb column rather than adding schema; document the reuse)
- Create: `ops-web/src/app/api/admin/google-ads/readiness/route.ts` (`withAdmin`, returns the stored readiness plus live counts: `ads_conversion_actions` rows, `trial_attributions` with any click id, `ads_conversion_events` by state)
- Modify: `ops-web/src/app/api/cron/ads-sync/route.ts` — call the probe logic once per run so the ledger refreshes daily without a UI action
- Tests: `tests/unit/ads/readiness.test.ts` — pure `computeReadiness(inputs)` → the seven checks with `state: "ready" | "blocked" | "pending"` and a `reason` string

The seven checks: `service_account_role` (Standard on the manager), `customer_data_terms`, `enhanced_conversions_for_leads`, `data_manager_api` (a `validateOnly` ingest of an empty-identifier event returns 200 or a 4xx that is not `PERMISSION_DENIED`/`SERVICE_DISABLED`), `conversion_actions` (three rows in `ads_conversion_actions`), `click_id_capture` (any `trial_attributions` row with `gclid|gbraid|wbraid` in the last 30 days — `pending` until real traffic arrives), `first_event_sent` (any `ads_conversion_events.state='sent'`).

**Commit** `feat(ads): readiness checks for the engine`.

---

## Task 10: Console — readiness ledger while the account is dark

**Skills:** `ops-design`, `custom-skills:interface-design`, `ops-copywriter:ops-copywriter`, `custom-skills:audit-design-system`. Design tokens: `.glass-surface` panel, `font-mono text-micro uppercase tracking-[0.16em] text-text-3` for the `// ENGINE READINESS` label, `font-mohave text-body text-text` for row titles, `text-text-2` for reasons, 8px dots `bg-olive` (ready) / `bg-rose` (blocked) / `bg-fill-neutral` (pending), hairline `border-line` row dividers, `EASE_SMOOTH` 200 ms fade-up on mount honouring `prefers-reduced-motion`, no accent anywhere, `—` for unknown values, numbers in `font-mono` with `tnum`.

**Files:**
- Create: `ops-web/src/app/admin/google-ads/_components/readiness-ledger.tsx` (client; fetches `/api/admin/google-ads/readiness`; skeleton while `isPending`; the `ops-web` rule is `isPending` gates skeleton so a paused fetch never reads as empty)
- Modify: `ops-web/src/app/admin/google-ads/page.tsx` — render `ReadinessLedger` directly under the header when `defaultAdsPreset(bounds) === "all"` (the account is dark); keep everything else as is
- Create: `ops-web/src/app/admin/google-ads/__tests__/readiness-ledger.test.tsx` (renders the seven rows from a fixture; blocked row shows its reason; pending shows `—`)

**Copy (product register, sentence case content, uppercase authority):** label `// ENGINE READINESS`; rows `Service account can write`, `Customer data terms accepted`, `Enhanced conversions for leads`, `Data Manager API reachable`, `Conversion actions in place`, `Click ids arriving`, `First event delivered`; states `READY` / `BLOCKED` / `PENDING`; blocked reasons are one short sentence from the probe (e.g. `Role is Read only on the manager account`).

**Steps:** failing render test → component → green → `npx tsc --noEmit` → run `custom-skills:audit-design-system` on the two touched files (zero literals) → screenshot the dark-state page at 1440×900 from a local dev server with the dev bypass (recipe in memory `reference_ops_web_worktree_preview`) to `docs/artifacts/ads-engine/p1/readiness-ledger.png` → commit `feat(admin): show Google Ads engine readiness while the account is dark`.

---

## Task 11: Bible, runbook, evidence, hand-off

**Files (bible):**
- Modify `03_DATA_ARCHITECTURE.md` (new tables + view + `trial_attributions.gbraid/wbraid`, dated `2026-09-09`, cite both migration filenames)
- Modify `04_API_AND_INTEGRATION.md` § "Google Ads Reporting Integration" (v25, searchStream, mutate contract, the two internal setup routes, the conversions cron, Data Manager) and § "Google Ads Conversion Events" (the three `UPLOAD_CLICKS` actions; iOS Firebase actions demoted to secondary)
- Modify `21_ANALYTICS_SYSTEM.md` § 10 (server-side conversion path) and § 11 (Google Ads row)
- Modify `07_SPECIALIZED_FEATURES.md` § 14 (add `ADS CONVERSIONS FAILING`, persistent, dedupe key, action URL)
- `README.md` nav if a new section anchor is added
- `migrations/` already mirrored in Tasks 4 and 8

**Files (ops-web):** `docs/ads/runbook.md` — sections: readiness probe results (dated), how to run the setup routes, the outbox states and how to requeue (`update ads_conversion_events set state='queued', next_attempt_at=now() where id=…`; never delete), cron schedule, what each artifact proves.

**Verification before claiming done (all with output captured to `docs/artifacts/ads-engine/p1/`):**
1. `npx vitest run tests/unit/analytics tests/unit/ads tests/unit/admin tests/unit/pmf` — green.
2. `node tests/sql/ads-conversion-outbox-runtime.mjs && node tests/sql/ads-warehouse-grain-runtime.mjs` — PASS.
3. `npx tsc --noEmit` — error count equals the Task 0 baseline.
4. try-ops `npm test` green and `npx tsc --noEmit` clean; ops-site worktree `npm test` (its runner is `node --test`; check `package.json`) green.
5. Production objects verified (Task 4 and Task 8 outputs).
6. Data Manager `validateOnly` and live rehearsal JSON (Task 5) — the live one is the phase gate; if Task 1's gate never went green, say so in the hand-off and list which account action is still missing.
7. Readiness ledger screenshot.

**Hand-off message to Jackson (plain language):** what now gets measured, what the probe says about his three account actions, that nothing spends money yet, and that Phase 2 (account rebuild) can start once the probe is green. Commit the bible by name: `docs(ads): document the engine's measurement layer`.

**Do not:** push any repo; merge to main; enable any campaign; create the routine; touch the Instagram or agent-queue code; edit files under `ops-web/.worktrees/` or any sibling worktree.
