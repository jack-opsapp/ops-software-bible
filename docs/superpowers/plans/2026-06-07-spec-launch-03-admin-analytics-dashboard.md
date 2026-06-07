# SPEC Launch 03 Admin Analytics Dashboard Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build `/admin/spec/analytics` with launch metrics, search-term history, funnel reporting, and export packages.

**Architecture:** Reuse OPS-Web admin data access and chart primitives. Add search-term history storage, typed SPEC analytics queries, operator-gated API routes, dense admin components, and ZIP exports with default redaction and explicit sensitive export mode.

**Tech Stack:** Next.js App Router, TypeScript, Supabase service role, Google Ads API, GA4 Data API, fflate ZIP export, Vitest, OPS-Web admin components.

---

## File Structure

- Create: `/Users/jacksonsweet/Projects/OPS/ops-web/supabase/migrations/20260607090000_ads_daily_search_terms.sql`
- Modify: `/Users/jacksonsweet/Projects/OPS/ops-web/src/lib/admin/ads-history-types.ts`
- Modify: `/Users/jacksonsweet/Projects/OPS/ops-web/src/lib/admin/ads-history-queries.ts`
- Modify: `/Users/jacksonsweet/Projects/OPS/ops-web/src/lib/admin/ads-history-sync.ts`
- Create: `/Users/jacksonsweet/Projects/OPS/ops-web/src/lib/admin/spec-analytics-types.ts`
- Create: `/Users/jacksonsweet/Projects/OPS/ops-web/src/lib/admin/spec-analytics-queries.ts`
- Create: `/Users/jacksonsweet/Projects/OPS/ops-web/src/lib/admin/spec-analytics-export.ts`
- Create: `/Users/jacksonsweet/Projects/OPS/ops-web/src/lib/admin/spec-api-auth.ts`
- Create: `/Users/jacksonsweet/Projects/OPS/ops-web/src/app/api/admin/spec/analytics/route.ts`
- Create: `/Users/jacksonsweet/Projects/OPS/ops-web/src/app/api/admin/spec/analytics/export/route.ts`
- Create: `/Users/jacksonsweet/Projects/OPS/ops-web/src/app/admin/spec/analytics/page.tsx`
- Create: `/Users/jacksonsweet/Projects/OPS/ops-web/src/app/admin/spec/analytics/_components/spec-analytics-content.tsx`
- Create: `/Users/jacksonsweet/Projects/OPS/ops-web/src/app/admin/spec/analytics/_components/spec-funnel.tsx`
- Create: `/Users/jacksonsweet/Projects/OPS/ops-web/src/app/admin/spec/analytics/_components/spec-export-rail.tsx`
- Test: `/Users/jacksonsweet/Projects/OPS/ops-web/src/lib/admin/__tests__/spec-analytics-export.test.ts`

## Task 1: Add Search-Term History Storage

**Files:**
- Create: `/Users/jacksonsweet/Projects/OPS/ops-web/supabase/migrations/20260607090000_ads_daily_search_terms.sql`
- Modify: `/Users/jacksonsweet/Projects/OPS/ops-web/src/lib/admin/ads-history-types.ts`

- [ ] **Step 1: Write migration**

Create `/Users/jacksonsweet/Projects/OPS/ops-web/supabase/migrations/20260607090000_ads_daily_search_terms.sql`:

```sql
create table if not exists public.ads_daily_search_term (
  date date not null,
  search_term text not null,
  campaign_name text not null,
  ad_group_name text,
  spend numeric not null default 0,
  clicks integer not null default 0,
  impressions integer not null default 0,
  conversions numeric not null default 0,
  cpa numeric not null default 0,
  ctr numeric not null default 0,
  waste_flag text,
  synced_at timestamptz not null default now(),
  primary key (date, search_term, campaign_name)
);

alter table public.ads_daily_search_term enable row level security;

create policy "service role manages ads_daily_search_term"
  on public.ads_daily_search_term
  for all
  using (auth.role() = 'service_role')
  with check (auth.role() = 'service_role');

create index if not exists ads_daily_search_term_date_idx
  on public.ads_daily_search_term (date desc);

create index if not exists ads_daily_search_term_spend_idx
  on public.ads_daily_search_term (spend desc);
```

- [ ] **Step 2: Add TypeScript type**

Append to `/Users/jacksonsweet/Projects/OPS/ops-web/src/lib/admin/ads-history-types.ts`:

```ts
export interface AdsDailySearchTerm {
  date: string;
  search_term: string;
  campaign_name: string;
  ad_group_name: string | null;
  spend: number;
  clicks: number;
  impressions: number;
  conversions: number;
  cpa: number;
  ctr: number;
  waste_flag: string | null;
  synced_at: string;
}
```

- [ ] **Step 3: Run static checks**

Run:

```bash
cd /Users/jacksonsweet/Projects/OPS/ops-web
npx tsc --noEmit
```

Expected: exits 0 or only reports pre-existing unrelated errors. Any error from `ads-history-types.ts` blocks this task.

- [ ] **Step 4: Commit**

Run:

```bash
cd /Users/jacksonsweet/Projects/OPS/ops-web
git add supabase/migrations/20260607090000_ads_daily_search_terms.sql src/lib/admin/ads-history-types.ts
git commit -m "feat(admin): add Google Ads search term history"
```

Expected: commit contains migration and type.

## Task 2: Sync And Query Search Terms

**Files:**
- Modify: `/Users/jacksonsweet/Projects/OPS/ops-web/src/lib/admin/ads-history-queries.ts`
- Modify: `/Users/jacksonsweet/Projects/OPS/ops-web/src/lib/admin/ads-history-sync.ts`
- Modify: `/Users/jacksonsweet/Projects/OPS/ops-web/src/app/api/admin/google-ads/route.ts`

- [ ] **Step 1: Add upsert/read helpers**

Add to `/Users/jacksonsweet/Projects/OPS/ops-web/src/lib/admin/ads-history-queries.ts`:

```ts
export async function upsertDailySearchTerms(rows: Omit<AdsDailySearchTerm, "synced_at">[]): Promise<void> {
  if (rows.length === 0) return;
  const withTimestamp = rows.map((r) => ({ ...r, synced_at: new Date().toISOString() }));
  await db()
    .from("ads_daily_search_term")
    .upsert(withTimestamp, { onConflict: "date,search_term,campaign_name" });
}

export async function getSearchTermsFromHistory(
  startDate: string,
  endDate: string,
  limit = 50
): Promise<SearchTermData[]> {
  const { data } = await db()
    .from("ads_daily_search_term")
    .select("*")
    .gte("date", startDate)
    .lte("date", endDate)
    .order("spend", { ascending: false })
    .limit(limit);

  return (data ?? []).map((row) => ({
    searchTerm: row.search_term,
    campaignName: row.campaign_name,
    adGroupName: row.ad_group_name,
    impressions: Number(row.impressions),
    clicks: Number(row.clicks),
    cost: Number(row.spend),
    conversions: Number(row.conversions),
  }));
}
```

Import `AdsDailySearchTerm` and `SearchTermData`.

- [ ] **Step 2: Wire sync**

First extend `/Users/jacksonsweet/Projects/OPS/ops-web/src/lib/analytics/google-ads-types.ts`:

```ts
export interface SearchTermData {
  searchTerm: string;
  campaignName: string;
  adGroupName: string | null;
  impressions: number;
  clicks: number;
  cost: number;
  conversions: number;
}
```

Then modify `getSearchTerms()` in `/Users/jacksonsweet/Projects/OPS/ops-web/src/lib/analytics/google-ads-client.ts` so its GAQL includes campaign and ad group:

```ts
const rows = await queryGoogleAds(`
  SELECT
    search_term_view.search_term,
    campaign.name,
    ad_group.name,
    metrics.impressions,
    metrics.clicks,
    metrics.cost_micros,
    metrics.conversions
  FROM search_term_view
  WHERE segments.date DURING ${DURING_MAP[days]}
  ORDER BY metrics.impressions DESC
  LIMIT ${limit}
`);
```

Add `adGroup?: { name?: string }` to the local `GoogleAdsRow` interface, then return:

```ts
return rows.map((row) => ({
  searchTerm: String(row.searchTermView?.searchTerm ?? ""),
  campaignName: String(row.campaign?.name ?? "unknown"),
  adGroupName: row.adGroup?.name ? String(row.adGroup.name) : null,
  impressions: Number(row.metrics?.impressions ?? 0),
  clicks: Number(row.metrics?.clicks ?? 0),
  cost: microsToDollars(row.metrics?.costMicros),
  conversions: Number(row.metrics?.conversions ?? 0),
}));
```

In `/Users/jacksonsweet/Projects/OPS/ops-web/src/lib/admin/ads-history-sync.ts`, after campaign and keyword sync, call Google Ads search terms and persist:

```ts
const searchTerms = await getCachedSearchTerms(30, 200);
await upsertDailySearchTerms(searchTerms.map((row) => ({
  date,
  search_term: row.searchTerm,
  campaign_name: row.campaignName,
  ad_group_name: row.adGroupName,
  spend: row.cost,
  clicks: row.clicks,
  impressions: row.impressions,
  conversions: row.conversions,
  cpa: row.conversions > 0 ? row.cost / row.conversions : 0,
  ctr: row.impressions > 0 ? row.clicks / row.impressions : 0,
  waste_flag: row.cost >= 100 && row.conversions === 0 ? "spent_100_no_conversion" : null,
})));
```

- [ ] **Step 3: Return history-backed search terms**

Modify `/Users/jacksonsweet/Projects/OPS/ops-web/src/app/api/admin/google-ads/route.ts` so the history branch reads:

```ts
const [summary, campaigns, keywords, searchTerms, dailySpend] = await Promise.all([
  safe(getAccountSummaryFromHistory(startDate, endDate), null),
  safe(getCampaignsFromHistory(startDate, endDate), []),
  safe(getKeywordsFromHistory(startDate, endDate, 50), []),
  safe(getSearchTermsFromHistory(startDate, endDate, 50), []),
  safe(getDailySpendFromHistory(startDate, endDate), []),
]);
```

and returns `searchTerms`.

- [ ] **Step 4: Run build check**

Run:

```bash
cd /Users/jacksonsweet/Projects/OPS/ops-web
npm run build
```

Expected: exit 0. If unrelated build warnings appear, record them; TypeScript errors from touched files block this task.

- [ ] **Step 5: Commit**

Run:

```bash
cd /Users/jacksonsweet/Projects/OPS/ops-web
git add src/lib/admin/ads-history-queries.ts src/lib/admin/ads-history-sync.ts src/lib/analytics/google-ads-types.ts src/app/api/admin/google-ads/route.ts
git commit -m "feat(admin): sync Google Ads search terms"
```

Expected: commit contains search-term sync/read path.

## Task 3: Build SPEC Analytics Query Layer

**Files:**
- Create: `/Users/jacksonsweet/Projects/OPS/ops-web/src/lib/admin/spec-analytics-types.ts`
- Create: `/Users/jacksonsweet/Projects/OPS/ops-web/src/lib/admin/spec-analytics-queries.ts`

- [ ] **Step 1: Create types**

Create `/Users/jacksonsweet/Projects/OPS/ops-web/src/lib/admin/spec-analytics-types.ts`:

```ts
export interface SpecAnalyticsSummary {
  spendCents: number;
  budgetCapCents: number;
  paidDeposits: number;
  checkoutOpens: number;
  defaultOpsSignups: number;
  depositRevenueCents: number;
}

export interface SpecFunnelStep {
  eventName: string;
  label: string;
  count: number;
  rateFromPrevious: number | null;
}

export interface SpecEventLedgerRow {
  id: string;
  eventName: string;
  specProjectId: string | null;
  tier: string | null;
  status: string;
  createdAt: string;
}

export interface SpecAnalyticsPayload {
  summary: SpecAnalyticsSummary;
  funnel: SpecFunnelStep[];
  events: SpecEventLedgerRow[];
}
```

- [ ] **Step 2: Create query functions**

Create `/Users/jacksonsweet/Projects/OPS/ops-web/src/lib/admin/spec-analytics-queries.ts`:

```ts
import { getAdminSupabase } from "@/lib/supabase/admin-client";
import type { SpecAnalyticsPayload, SpecEventLedgerRow, SpecFunnelStep } from "./spec-analytics-types";

const FUNNEL_EVENTS = [
  "page_view",
  "spec_card_expand",
  "pay_deposit_click",
  "billing_address_submitted",
  "stripe_checkout_opened",
  "stripe_checkout_completed",
  "intake_submitted",
  "discovery_booked",
] as const;

export async function getSpecAnalyticsPayload(startDate: string, endDate: string): Promise<SpecAnalyticsPayload> {
  const db = getAdminSupabase();

  const { data: eventRows } = await db
    .from("conversion_event_outbox")
    .select("id,event_name,payload,status,created_at")
    .gte("created_at", `${startDate}T00:00:00.000Z`)
    .lte("created_at", `${endDate}T23:59:59.999Z`)
    .order("created_at", { ascending: false });

  const events: SpecEventLedgerRow[] = (eventRows ?? []).map((row) => {
    const payload = row.payload as Record<string, unknown>;
    return {
      id: row.id,
      eventName: row.event_name,
      specProjectId: typeof payload.spec_project_id === "string" ? payload.spec_project_id : null,
      tier: typeof payload.tier === "string" ? payload.tier : null,
      status: row.status,
      createdAt: row.created_at,
    };
  });

  const counts = new Map<string, number>();
  for (const event of events) counts.set(event.eventName, (counts.get(event.eventName) ?? 0) + 1);

  const funnel: SpecFunnelStep[] = FUNNEL_EVENTS.map((eventName, index) => {
    const count = counts.get(eventName) ?? 0;
    const previous = index === 0 ? null : counts.get(FUNNEL_EVENTS[index - 1]) ?? 0;
    return {
      eventName,
      label: eventName.replaceAll("_", " ").toUpperCase(),
      count,
      rateFromPrevious: previous && previous > 0 ? count / previous : null,
    };
  });

  const paidDeposits = counts.get("stripe_checkout_completed") ?? 0;
  const checkoutOpens = counts.get("stripe_checkout_opened") ?? 0;
  const defaultOpsSignups = counts.get("spec_default_ops_signup_completed") ?? 0;
  const depositRevenueCents = (eventRows ?? []).reduce((sum, row) => {
    if (row.event_name !== "stripe_checkout_completed") return sum;
    const payload = row.payload as Record<string, unknown>;
    return sum + (typeof payload.value_cents === "number" ? payload.value_cents : 0);
  }, 0);

  return {
    summary: {
      spendCents: 0,
      budgetCapCents: 150000,
      paidDeposits,
      checkoutOpens,
      defaultOpsSignups,
      depositRevenueCents,
    },
    funnel,
    events,
  };
}
```

- [ ] **Step 3: Run typecheck**

Run:

```bash
cd /Users/jacksonsweet/Projects/OPS/ops-web
npx tsc --noEmit
```

Expected: no errors in new files.

- [ ] **Step 4: Commit**

Run:

```bash
cd /Users/jacksonsweet/Projects/OPS/ops-web
git add src/lib/admin/spec-analytics-types.ts src/lib/admin/spec-analytics-queries.ts
git commit -m "feat(spec): add analytics query layer"
```

Expected: commit contains SPEC analytics query layer.

## Task 4: Add Operator-Gated API Routes

**Files:**
- Create: `/Users/jacksonsweet/Projects/OPS/ops-web/src/lib/admin/spec-api-auth.ts`
- Create: `/Users/jacksonsweet/Projects/OPS/ops-web/src/app/api/admin/spec/analytics/route.ts`
- Create: `/Users/jacksonsweet/Projects/OPS/ops-web/src/app/api/admin/spec/analytics/export/route.ts`

- [ ] **Step 1: Add SPEC operator API auth helper**

Create `/Users/jacksonsweet/Projects/OPS/ops-web/src/lib/admin/spec-api-auth.ts`:

```ts
import { NextResponse, type NextRequest } from "next/server";
import { requireAdmin } from "@/lib/admin/api-auth";
import { findUserByAuth } from "@/lib/supabase/find-user-by-auth";
import { isSpecOperator } from "@/lib/admin/spec-permissions";

export async function requireSpecOperatorApi(req: NextRequest) {
  const firebaseUser = await requireAdmin(req);
  const email = firebaseUser.email;
  if (!email) {
    throw NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  const opsUser = await findUserByAuth(firebaseUser.uid, email, "id");
  if (!opsUser || typeof opsUser.id !== "string") {
    throw NextResponse.json({ error: "Forbidden" }, { status: 403 });
  }

  const ok = await isSpecOperator(opsUser.id);
  if (!ok) {
    throw NextResponse.json({ error: "Forbidden" }, { status: 403 });
  }

  return { firebaseUser, opsUser };
}

export function withSpecOperator<TRest extends unknown[]>(
  handler: (req: NextRequest, ...rest: TRest) => Promise<NextResponse>,
) {
  return async (req: NextRequest, ...rest: TRest) => {
    try {
      await requireSpecOperatorApi(req);
      return await handler(req, ...rest);
    } catch (err) {
      if (err instanceof NextResponse) return err;
      console.error("[spec-admin-api]", err);
      return NextResponse.json({ error: "Internal server error" }, { status: 500 });
    }
  };
}
```

- [ ] **Step 2: Add analytics route**

Create `/Users/jacksonsweet/Projects/OPS/ops-web/src/app/api/admin/spec/analytics/route.ts`:

```ts
import { NextRequest, NextResponse } from "next/server";
import { withSpecOperator } from "@/lib/admin/spec-api-auth";
import { getSpecAnalyticsPayload } from "@/lib/admin/spec-analytics-queries";

function readDate(value: string | null, fallback: string): string {
  return value && /^\d{4}-\d{2}-\d{2}$/.test(value) ? value : fallback;
}

export const GET = withSpecOperator(async (req: NextRequest) => {
  const now = new Date();
  const end = now.toISOString().slice(0, 10);
  const startDate = new Date(now);
  startDate.setDate(startDate.getDate() - 13);
  const start = startDate.toISOString().slice(0, 10);

  const from = readDate(req.nextUrl.searchParams.get("from"), start);
  const to = readDate(req.nextUrl.searchParams.get("to"), end);

  const payload = await getSpecAnalyticsPayload(from, to);
  return NextResponse.json(payload);
});
```

- [ ] **Step 3: Add export route shell**

Create `/Users/jacksonsweet/Projects/OPS/ops-web/src/app/api/admin/spec/analytics/export/route.ts`:

```ts
import { NextRequest, NextResponse } from "next/server";
import { withSpecOperator } from "@/lib/admin/spec-api-auth";
import { buildSpecAnalyticsExport } from "@/lib/admin/spec-analytics-export";

export const GET = withSpecOperator(async (req: NextRequest) => {
  const mode = req.nextUrl.searchParams.get("mode") === "sensitive" ? "sensitive" : "default";
  const archive = await buildSpecAnalyticsExport({
    mode,
    from: req.nextUrl.searchParams.get("from"),
    to: req.nextUrl.searchParams.get("to"),
  });

  return new NextResponse(archive.bytes, {
    headers: {
      "content-type": "application/zip",
      "content-disposition": `attachment; filename="${archive.filename}"`,
    },
  });
});
```

- [ ] **Step 4: Run route typecheck**

Run:

```bash
cd /Users/jacksonsweet/Projects/OPS/ops-web
npx tsc --noEmit
```

Expected: route imports resolve.

- [ ] **Step 5: Commit**

Run:

```bash
cd /Users/jacksonsweet/Projects/OPS/ops-web
git add src/lib/admin/spec-api-auth.ts src/app/api/admin/spec/analytics
git commit -m "feat(spec): add analytics admin APIs"
```

Expected: commit contains two API routes.

## Task 5: Build Export Helper

**Files:**
- Modify: `/Users/jacksonsweet/Projects/OPS/ops-web/package.json`
- Modify: `/Users/jacksonsweet/Projects/OPS/ops-web/package-lock.json`
- Create: `/Users/jacksonsweet/Projects/OPS/ops-web/src/lib/admin/spec-analytics-export.ts`
- Test: `/Users/jacksonsweet/Projects/OPS/ops-web/src/lib/admin/__tests__/spec-analytics-export.test.ts`

- [ ] **Step 1: Add ZIP dependency**

Run:

```bash
cd /Users/jacksonsweet/Projects/OPS/ops-web
npm install fflate@0.8.2
```

Expected: `package.json` lists `fflate` and `package-lock.json` records `fflate@0.8.2`. `fflate` is an open-source package dependency; this adds no metered service cost.

- [ ] **Step 2: Write export tests**

Create `/Users/jacksonsweet/Projects/OPS/ops-web/src/lib/admin/__tests__/spec-analytics-export.test.ts`:

```ts
import { unzipSync } from "fflate";
import { redactEmail, redactPhone, buildExportManifest, buildZipArchive } from "../spec-analytics-export";

it("hashes email in default export mode", () => {
  expect(redactEmail("JACK@OPSAPP.CO")).toMatch(/^[a-f0-9]{64}$/);
});

it("hashes phone in default export mode", () => {
  expect(redactPhone("+1 (778) 535-7941")).toMatch(/^[a-f0-9]{64}$/);
});

it("marks sensitive manifests", () => {
  expect(buildExportManifest({ mode: "sensitive", rowCounts: { spec_projects: 1 } }).sensitive).toBe(true);
});

it("builds a real zip archive", () => {
  const bytes = buildZipArchive({
    "manifest.json": JSON.stringify({ ok: true }),
    "events.csv": "id,event\n1,stripe_checkout_completed\n",
  });

  const files = unzipSync(bytes);
  expect(Object.keys(files).sort()).toEqual(["events.csv", "manifest.json"]);
});
```

- [ ] **Step 3: Run test and verify failure**

Run:

```bash
cd /Users/jacksonsweet/Projects/OPS/ops-web
npm test -- src/lib/admin/__tests__/spec-analytics-export.test.ts
```

Expected: failure because helper does not exist.

- [ ] **Step 4: Implement export helper**

Create `/Users/jacksonsweet/Projects/OPS/ops-web/src/lib/admin/spec-analytics-export.ts`:

```ts
import { createHash } from "crypto";
import { strToU8, zipSync } from "fflate";
import { getAdminSupabase } from "@/lib/supabase/admin-client";

export type SpecExportMode = "default" | "sensitive";
type CsvValue = unknown;
type CsvRow = Record<string, CsvValue>;

export function redactEmail(value: string): string {
  return createHash("sha256").update(value.trim().toLowerCase()).digest("hex");
}

export function redactPhone(value: string): string {
  return createHash("sha256").update(value.replace(/\D/g, "")).digest("hex");
}

function csvCell(value: CsvValue): string {
  if (value == null) return "";
  const raw = typeof value === "object" ? JSON.stringify(value) : String(value);
  return /[",\n]/.test(raw) ? `"${raw.replaceAll('"', '""')}"` : raw;
}

export function toCsv(rows: CsvRow[]): string {
  const headers = Array.from(rows.reduce((set, row) => {
    for (const key of Object.keys(row)) set.add(key);
    return set;
  }, new Set<string>()));
  return [
    headers.join(","),
    ...rows.map((row) => headers.map((header) => csvCell(row[header])).join(",")),
  ].join("\n");
}

export function buildZipArchive(files: Record<string, string>): Uint8Array {
  const encoded = Object.fromEntries(
    Object.entries(files).map(([name, body]) => [name, strToU8(body)]),
  );
  return zipSync(encoded, { level: 6 });
}

export function buildExportManifest(args: { mode: SpecExportMode; rowCounts: Record<string, number> }) {
  return {
    generated_at: new Date().toISOString(),
    date_range: null,
    environment: process.env.VERCEL_ENV ?? process.env.NODE_ENV ?? "unknown",
    timezone: "America/Vancouver",
    campaign_budget_cap_cents: 150000,
    currency: "CAD",
    sensitive: args.mode === "sensitive",
    row_counts: args.rowCounts,
    known_latency: {
      google_ads: "current day may be partial",
      ga4: "24-48 hours",
    },
    configured: {
      google_ads: Boolean(process.env.GOOGLE_ADS_DEVELOPER_TOKEN),
      ga4: Boolean(process.env.GA4_PROPERTY_ID),
      conversion_dispatch: Boolean(process.env.GOOGLE_ADS_CONVERSION_ID),
    },
  };
}

async function loadRows(table: string, from: string | null, to: string | null) {
  const db = getAdminSupabase();
  const isDailyTable = table === "ads_daily_search_term";
  const orderColumn = isDailyTable ? "date" : "created_at";
  const fromValue = isDailyTable ? from : from ? `${from}T00:00:00.000Z` : null;
  const toValue = isDailyTable ? to : to ? `${to}T23:59:59.999Z` : null;
  const query = db.from(table).select("*").order(orderColumn, { ascending: false });
  const ranged = fromValue && toValue ? query.gte(orderColumn, fromValue).lte(orderColumn, toValue) : query;
  const { data, error } = await ranged.limit(5000);
  if (error) throw new Error(`${table} export failed: ${error.message}`);
  return data ?? [];
}

function redactSpecProject(row: Record<string, unknown>, mode: SpecExportMode): CsvRow {
  if (mode === "sensitive") return row as CsvRow;
  return {
    ...row,
    customer_email: typeof row.customer_email === "string" ? redactEmail(row.customer_email) : null,
    customer_phone: typeof row.customer_phone === "string" ? redactPhone(row.customer_phone) : null,
    customer_name: row.customer_name ? "[redacted]" : null,
    stripe_customer_id: row.stripe_customer_id ? "[redacted]" : null,
  } as CsvRow;
}

export async function buildSpecAnalyticsExport(args: { mode: SpecExportMode; from: string | null; to: string | null }) {
  const [specProjects, conversionEvents, analyticsEvents, searchTerms] = await Promise.all([
    loadRows("spec_projects", args.from, args.to),
    loadRows("conversion_event_outbox", args.from, args.to),
    loadRows("analytics_events", args.from, args.to),
    loadRows("ads_daily_search_term", args.from, args.to),
  ]);

  const manifest = buildExportManifest({
    mode: args.mode,
    rowCounts: {
      spec_projects: specProjects.length,
      conversion_event_outbox: conversionEvents.length,
      analytics_events: analyticsEvents.length,
      ads_daily_search_term: searchTerms.length,
    },
  });

  const bytes = buildZipArchive({
    "manifest.json": JSON.stringify(manifest, null, 2),
    "spec_projects.csv": toCsv(specProjects.map((row) => redactSpecProject(row, args.mode))),
    "conversion_event_outbox.csv": toCsv(conversionEvents as CsvRow[]),
    "analytics_events.csv": toCsv(analyticsEvents as CsvRow[]),
    "ads_daily_search_term.csv": toCsv(searchTerms as CsvRow[]),
  });

  return {
    filename: `spec-analytics-${args.mode}-${new Date().toISOString().slice(0, 10)}.zip`,
    bytes,
  };
}
```

- [ ] **Step 5: Run tests and verify pass**

Run:

```bash
cd /Users/jacksonsweet/Projects/OPS/ops-web
npm test -- src/lib/admin/__tests__/spec-analytics-export.test.ts
```

Expected: exit 0.

- [ ] **Step 6: Commit**

Run:

```bash
cd /Users/jacksonsweet/Projects/OPS/ops-web
git add package.json package-lock.json src/lib/admin/spec-analytics-export.ts src/lib/admin/__tests__/spec-analytics-export.test.ts
git commit -m "feat(spec): add analytics export builder"
```

Expected: commit contains export helper and tests.

## Task 6: Build Admin UI

**Files:**
- Create: `/Users/jacksonsweet/Projects/OPS/ops-web/src/app/admin/spec/analytics/page.tsx`
- Create: `/Users/jacksonsweet/Projects/OPS/ops-web/src/app/admin/spec/analytics/_components/spec-analytics-content.tsx`
- Create: `/Users/jacksonsweet/Projects/OPS/ops-web/src/app/admin/spec/analytics/_components/spec-funnel.tsx`
- Create: `/Users/jacksonsweet/Projects/OPS/ops-web/src/app/admin/spec/analytics/_components/spec-export-rail.tsx`

- [ ] **Step 1: Add page**

Create `/Users/jacksonsweet/Projects/OPS/ops-web/src/app/admin/spec/analytics/page.tsx`:

```tsx
import { AdminPageHeader } from "../../_components/admin-page-header";
import { getSpecAnalyticsPayload } from "@/lib/admin/spec-analytics-queries";
import { SpecAnalyticsContent } from "./_components/spec-analytics-content";

export default async function SpecAnalyticsPage() {
  const now = new Date();
  const to = now.toISOString().slice(0, 10);
  const fromDate = new Date(now);
  fromDate.setDate(fromDate.getDate() - 13);
  const from = fromDate.toISOString().slice(0, 10);
  const payload = await getSpecAnalyticsPayload(from, to);

  return (
    <div>
      <AdminPageHeader title="SPEC ANALYTICS" caption="paid validation command view" />
      <SpecAnalyticsContent initialData={payload} from={from} to={to} />
    </div>
  );
}
```

- [ ] **Step 2: Add content component**

Create `/Users/jacksonsweet/Projects/OPS/ops-web/src/app/admin/spec/analytics/_components/spec-analytics-content.tsx` with a client component that renders:

```tsx
"use client";

import { StatCard } from "../../../_components/stat-card";
import type { SpecAnalyticsPayload } from "@/lib/admin/spec-analytics-types";
import { SpecFunnel } from "./spec-funnel";
import { SpecExportRail } from "./spec-export-rail";

export function SpecAnalyticsContent({ initialData, from, to }: { initialData: SpecAnalyticsPayload; from: string; to: string }) {
  const { summary } = initialData;
  return (
    <div className="p-8 space-y-6">
      <div className="grid grid-cols-5 gap-4">
        <StatCard label="SPEND" value={`$${(summary.spendCents / 100).toLocaleString("en-CA")}`} />
        <StatCard label="DEPOSITS" value={summary.paidDeposits.toLocaleString("en-CA")} />
        <StatCard label="CHECKOUTS" value={summary.checkoutOpens.toLocaleString("en-CA")} />
        <StatCard label="DEFAULT OPS" value={summary.defaultOpsSignups.toLocaleString("en-CA")} />
        <StatCard label="BUDGET LEFT" value={`$${((summary.budgetCapCents - summary.spendCents) / 100).toLocaleString("en-CA")}`} />
      </div>
      <SpecFunnel steps={initialData.funnel} />
      <SpecExportRail from={from} to={to} />
    </div>
  );
}
```

- [ ] **Step 3: Add funnel and export rail components**

Create `/Users/jacksonsweet/Projects/OPS/ops-web/src/app/admin/spec/analytics/_components/spec-funnel.tsx`:

```tsx
import type { SpecFunnelStep } from "@/lib/admin/spec-analytics-types";

export function SpecFunnel({ steps }: { steps: SpecFunnelStep[] }) {
  return (
    <section className="border border-border bg-background">
      <div className="border-b border-border px-4 py-3">
        <h2 className="font-mono text-xs uppercase tracking-normal text-muted-foreground">FUNNEL</h2>
      </div>
      <div className="divide-y divide-border">
        {steps.map((step) => (
          <div key={step.eventName} className="grid grid-cols-[1fr_96px_96px] items-center gap-4 px-4 py-3">
            <div>
              <div className="font-mono text-sm uppercase tracking-normal">{step.label}</div>
              <div className="font-mono text-xs text-muted-foreground">{step.eventName}</div>
            </div>
            <div className="text-right font-mono tabular-nums">{step.count.toLocaleString("en-CA")}</div>
            <div className="text-right font-mono tabular-nums text-muted-foreground">
              {step.rateFromPrevious == null ? "—" : `${Math.round(step.rateFromPrevious * 100)}%`}
            </div>
          </div>
        ))}
      </div>
    </section>
  );
}
```

Create `/Users/jacksonsweet/Projects/OPS/ops-web/src/app/admin/spec/analytics/_components/spec-export-rail.tsx`:

```tsx
export function SpecExportRail({ from, to }: { from: string; to: string }) {
  const qs = `from=${encodeURIComponent(from)}&to=${encodeURIComponent(to)}`;
  return (
    <section className="border border-border bg-background p-4">
      <div className="flex items-center justify-between gap-4">
        <div>
          <h2 className="font-mono text-xs uppercase tracking-normal text-muted-foreground">EXPORT</h2>
          <p className="mt-1 text-sm text-muted-foreground">Default export is redacted. Sensitive export is owner-only evidence.</p>
        </div>
        <div className="flex gap-2">
          <a className="border border-border px-3 py-2 font-mono text-xs uppercase tracking-normal" href={`/api/admin/spec/analytics/export?${qs}&mode=default`}>
            REDACTED ZIP
          </a>
          <a className="border border-border px-3 py-2 font-mono text-xs uppercase tracking-normal" href={`/api/admin/spec/analytics/export?${qs}&mode=sensitive`}>
            SENSITIVE ZIP
          </a>
        </div>
      </div>
    </section>
  );
}
```

- [ ] **Step 4: Run build**

Run:

```bash
cd /Users/jacksonsweet/Projects/OPS/ops-web
npm run build
```

Expected: exit 0 and route list includes `/admin/spec/analytics`.

- [ ] **Step 5: Commit**

Run:

```bash
cd /Users/jacksonsweet/Projects/OPS/ops-web
git add src/app/admin/spec/analytics
git commit -m "feat(spec): add paid validation analytics dashboard"
```

Expected: commit contains dashboard UI.
