# SPEC Launch 02 Analytics Instrumentation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Complete SPEC launch event capture, Google Ads Enhanced Conversion dispatch, and default OPS crossover attribution.

**Architecture:** Keep the existing outbox-first conversion model. Client-side marketing interactions write GA/Vercel events and server-side SPEC milestones enqueue `conversion_event_outbox` rows. A typed Google sender hashes identifiers, dispatches eligible events, and updates outbox status without blocking customer flow.

**Tech Stack:** Next.js App Router, TypeScript, Supabase service role, Google Ads API, Web Crypto or Node crypto, Vercel Analytics, Vitest.

---

## File Structure

- Modify: `/Users/jacksonsweet/Projects/OPS/ops-site/src/lib/spec/conversion-events.ts`
- Create: `/Users/jacksonsweet/Projects/OPS/ops-site/src/lib/spec/google-enhanced-conversions.ts`
- Create: `/Users/jacksonsweet/Projects/OPS/ops-site/src/lib/spec/conversion-hash.ts`
- Modify: `/Users/jacksonsweet/Projects/OPS/ops-site/src/lib/spec/cron/conversion-event-retry.ts`
- Modify: `/Users/jacksonsweet/Projects/OPS/ops-site/src/components/spec/PackageCard.tsx`
- Modify: `/Users/jacksonsweet/Projects/OPS/ops-site/src/components/spec/SpecPageContent.tsx`
- Modify: `/Users/jacksonsweet/Projects/OPS/ops-site/src/components/spec/SpecBottomCTA.tsx`
- Modify: `/Users/jacksonsweet/Projects/OPS/ops-site/src/components/layout/MarketingAnalytics.tsx`
- Modify: `/Users/jacksonsweet/Projects/OPS/ops-site/src/lib/marketing-analytics.ts`
- Test: `/Users/jacksonsweet/Projects/OPS/ops-site/src/lib/spec/__tests__/conversion-hash.test.ts`
- Test: `/Users/jacksonsweet/Projects/OPS/ops-site/src/lib/spec/cron/__tests__/conversion-event-retry.test.ts`

## Task 1: Lock Canonical Event Types

**Files:**
- Modify: `/Users/jacksonsweet/Projects/OPS/ops-site/src/lib/spec/conversion-events.ts`
- Test: `/Users/jacksonsweet/Projects/OPS/ops-site/src/lib/spec/__tests__/conversion-event-types.test.ts`

- [ ] **Step 1: Write the event type test**

Create `/Users/jacksonsweet/Projects/OPS/ops-site/src/lib/spec/__tests__/conversion-event-types.test.ts`:

```ts
import { SPEC_CONVERSION_EVENTS } from '../conversion-events';

it('exports the Phase 1 paid validation event registry', () => {
  expect(SPEC_CONVERSION_EVENTS).toEqual([
    'page_view',
    'spec_card_expand',
    'pay_deposit_click',
    'billing_address_submitted',
    'quebec_rejected',
    'owner_approval_requested',
    'owner_approval_granted',
    'stripe_checkout_opened',
    'stripe_checkout_completed',
    'intake_started',
    'intake_submitted',
    'discovery_booked',
    'spec_default_ops_cta_click',
    'spec_default_ops_signup_started',
    'spec_default_ops_signup_completed',
    'spec_default_ops_trial_activated',
    'refund_invoked',
  ]);
});
```

- [ ] **Step 2: Run the test and verify failure**

Run:

```bash
cd /Users/jacksonsweet/Projects/OPS/ops-site
npm test -- src/lib/spec/__tests__/conversion-event-types.test.ts
```

Expected: failure because `SPEC_CONVERSION_EVENTS` is not exported.

- [ ] **Step 3: Export the event registry**

Modify `/Users/jacksonsweet/Projects/OPS/ops-site/src/lib/spec/conversion-events.ts`:

```ts
export const SPEC_CONVERSION_EVENTS = [
  'page_view',
  'spec_card_expand',
  'pay_deposit_click',
  'billing_address_submitted',
  'quebec_rejected',
  'owner_approval_requested',
  'owner_approval_granted',
  'stripe_checkout_opened',
  'stripe_checkout_completed',
  'intake_started',
  'intake_submitted',
  'discovery_booked',
  'spec_default_ops_cta_click',
  'spec_default_ops_signup_started',
  'spec_default_ops_signup_completed',
  'spec_default_ops_trial_activated',
  'refund_invoked',
] as const;

export type SpecConversionEventName = (typeof SPEC_CONVERSION_EVENTS)[number];
```

Remove the older hand-written union so the registry is the single source of truth.

- [ ] **Step 4: Run the test and verify pass**

Run:

```bash
cd /Users/jacksonsweet/Projects/OPS/ops-site
npm test -- src/lib/spec/__tests__/conversion-event-types.test.ts
```

Expected: exit 0.

- [ ] **Step 5: Commit**

Run:

```bash
cd /Users/jacksonsweet/Projects/OPS/ops-site
git add src/lib/spec/conversion-events.ts src/lib/spec/__tests__/conversion-event-types.test.ts
git commit -m "feat(spec): lock paid launch conversion event registry"
```

Expected: commit contains event registry and test.

## Task 2: Add Identifier Hashing

**Files:**
- Create: `/Users/jacksonsweet/Projects/OPS/ops-site/src/lib/spec/conversion-hash.ts`
- Test: `/Users/jacksonsweet/Projects/OPS/ops-site/src/lib/spec/__tests__/conversion-hash.test.ts`

- [ ] **Step 1: Write hashing tests**

Create `/Users/jacksonsweet/Projects/OPS/ops-site/src/lib/spec/__tests__/conversion-hash.test.ts`:

```ts
import { normalizeEmail, normalizePhone, sha256Hex } from '../conversion-hash';

it('normalizes email before hashing', () => {
  expect(normalizeEmail('  JACK@OPSAPP.CO  ')).toBe('jack@opsapp.co');
});

it('normalizes phone to digits only', () => {
  expect(normalizePhone('+1 (778) 535-7941')).toBe('17785357941');
});

it('hashes using sha256 lowercase hex', () => {
  expect(sha256Hex('jack@opsapp.co')).toMatch(/^[a-f0-9]{64}$/);
});
```

- [ ] **Step 2: Run tests and verify failure**

Run:

```bash
cd /Users/jacksonsweet/Projects/OPS/ops-site
npm test -- src/lib/spec/__tests__/conversion-hash.test.ts
```

Expected: failure because module does not exist.

- [ ] **Step 3: Implement hashing module**

Create `/Users/jacksonsweet/Projects/OPS/ops-site/src/lib/spec/conversion-hash.ts`:

```ts
import { createHash } from 'crypto';

export function normalizeEmail(value: string): string {
  return value.trim().toLowerCase();
}

export function normalizePhone(value: string): string {
  return value.replace(/\D/g, '');
}

export function sha256Hex(value: string): string {
  return createHash('sha256').update(value, 'utf8').digest('hex');
}

export function hashEmail(value: string | null | undefined): string | null {
  if (!value) return null;
  const normalized = normalizeEmail(value);
  return normalized ? sha256Hex(normalized) : null;
}

export function hashPhone(value: string | null | undefined): string | null {
  if (!value) return null;
  const normalized = normalizePhone(value);
  return normalized ? sha256Hex(normalized) : null;
}
```

- [ ] **Step 4: Run tests and verify pass**

Run:

```bash
cd /Users/jacksonsweet/Projects/OPS/ops-site
npm test -- src/lib/spec/__tests__/conversion-hash.test.ts
```

Expected: exit 0.

- [ ] **Step 5: Commit**

Run:

```bash
cd /Users/jacksonsweet/Projects/OPS/ops-site
git add src/lib/spec/conversion-hash.ts src/lib/spec/__tests__/conversion-hash.test.ts
git commit -m "feat(spec): add conversion identifier hashing"
```

Expected: commit contains hashing module and tests.

## Task 3: Implement Google Enhanced Conversion Sender

**Files:**
- Create: `/Users/jacksonsweet/Projects/OPS/ops-site/src/lib/spec/google-enhanced-conversions.ts`
- Modify: `/Users/jacksonsweet/Projects/OPS/ops-site/src/lib/spec/cron/conversion-event-retry.ts`
- Test: `/Users/jacksonsweet/Projects/OPS/ops-site/src/lib/spec/cron/__tests__/conversion-event-retry.test.ts`

- [ ] **Step 1: Write retry test for configured Google sender**

Create or extend `/Users/jacksonsweet/Projects/OPS/ops-site/src/lib/spec/cron/__tests__/conversion-event-retry.test.ts`:

```ts
import { runConversionEventOutboxRetry } from '../conversion-event-retry';

it('marks eligible Google conversion rows sent when Google sender succeeds', async () => {
  process.env.GOOGLE_ADS_CONVERSION_ID = 'AW-123';
  process.env.GOOGLE_ADS_DEVELOPER_TOKEN = 'dev-token';
  process.env.GOOGLE_ADS_CUSTOMER_ID = '1234567890';
  process.env.GOOGLE_ADS_REFRESH_TOKEN = 'refresh-token';
  process.env.GOOGLE_ADS_CLIENT_ID = 'client-id';
  process.env.GOOGLE_ADS_CLIENT_SECRET = 'client-secret';

  const updates: unknown[] = [];
  const db = makeFakeConversionDb({
    rows: [{
      id: '11111111-1111-1111-1111-111111111111',
      event_name: 'stripe_checkout_completed',
      payload: {
        email: 'buyer@example.com',
        phone: '+1 778 535 7941',
        gclid: 'gclid-1',
        value_cents: 75000,
        currency: 'CAD',
      },
      attempts: 0,
      last_attempt_at: null,
    }],
    onUpdate: (patch) => updates.push(patch),
  });

  const result = await runConversionEventOutboxRetry(db as never, new Date('2026-06-07T12:00:00.000Z'));

  expect(result.fired).toBe(1);
  expect(updates).toContainEqual(expect.objectContaining({ status: 'sent' }));
});
```

Implement `makeFakeConversionDb` in the same test file using the existing fake Supabase test style from `src/lib/spec/cron/__tests__/fake-supabase.ts`.

- [ ] **Step 2: Run test and verify failure**

Run:

```bash
cd /Users/jacksonsweet/Projects/OPS/ops-site
npm test -- src/lib/spec/cron/__tests__/conversion-event-retry.test.ts
```

Expected: failure because sender is still stubbed.

- [ ] **Step 3: Add Google sender**

Create `/Users/jacksonsweet/Projects/OPS/ops-site/src/lib/spec/google-enhanced-conversions.ts`:

```ts
import { hashEmail, hashPhone } from './conversion-hash';
import type { ConversionEventPayload, SpecConversionEventName } from './conversion-events';

const GOOGLE_ADS_API_VERSION = process.env.GOOGLE_ADS_API_VERSION ?? 'v23';

const GOOGLE_PRIMARY_EVENTS = new Set<SpecConversionEventName>(['stripe_checkout_completed']);
const GOOGLE_SECONDARY_EVENTS = new Set<SpecConversionEventName>([
  'pay_deposit_click',
  'billing_address_submitted',
  'stripe_checkout_opened',
  'intake_submitted',
  'discovery_booked',
  'spec_default_ops_signup_completed',
  'spec_default_ops_trial_activated',
]);

const GOOGLE_CONVERSION_ACTION_ENV: Partial<Record<SpecConversionEventName, string>> = {
  pay_deposit_click: 'GOOGLE_ADS_CONVERSION_ACTION_PAY_DEPOSIT_CLICK',
  billing_address_submitted: 'GOOGLE_ADS_CONVERSION_ACTION_BILLING_ADDRESS_SUBMITTED',
  stripe_checkout_opened: 'GOOGLE_ADS_CONVERSION_ACTION_STRIPE_CHECKOUT_OPENED',
  stripe_checkout_completed: 'GOOGLE_ADS_CONVERSION_ACTION_STRIPE_CHECKOUT_COMPLETED',
  intake_submitted: 'GOOGLE_ADS_CONVERSION_ACTION_INTAKE_SUBMITTED',
  discovery_booked: 'GOOGLE_ADS_CONVERSION_ACTION_DISCOVERY_BOOKED',
  spec_default_ops_signup_completed: 'GOOGLE_ADS_CONVERSION_ACTION_DEFAULT_OPS_SIGNUP_COMPLETED',
  spec_default_ops_trial_activated: 'GOOGLE_ADS_CONVERSION_ACTION_DEFAULT_OPS_TRIAL_ACTIVATED',
};

export interface GoogleSendResult {
  ok: boolean;
  sent: boolean;
  error: string | null;
}

interface GoogleAccessTokenResponse {
  access_token?: string;
  error?: string;
  error_description?: string;
}

interface GoogleConversionRequest {
  conversions: Array<{
    conversionAction: string;
    conversionDateTime: string;
    conversionValue: number;
    currencyCode: string;
    orderId?: string;
    gclid?: string;
    userIdentifiers?: Array<
      | { hashedEmail: string; userIdentifierSource: 'FIRST_PARTY' }
      | { hashedPhoneNumber: string; userIdentifierSource: 'FIRST_PARTY' }
    >;
  }>;
  partialFailure: true;
  validateOnly: boolean;
  debugEnabled: false;
}

export function isGoogleConversionConfigured(): boolean {
  return Boolean(
    process.env.GOOGLE_ADS_DEVELOPER_TOKEN &&
    process.env.GOOGLE_ADS_CUSTOMER_ID &&
    process.env.GOOGLE_ADS_REFRESH_TOKEN &&
    process.env.GOOGLE_ADS_CLIENT_ID &&
    process.env.GOOGLE_ADS_CLIENT_SECRET,
  );
}

export function googleConversionRole(eventName: SpecConversionEventName): 'primary' | 'secondary' | 'internal' {
  if (GOOGLE_PRIMARY_EVENTS.has(eventName)) return 'primary';
  if (GOOGLE_SECONDARY_EVENTS.has(eventName)) return 'secondary';
  return 'internal';
}

function cleanCustomerId(): string {
  const customerId = process.env.GOOGLE_ADS_CUSTOMER_ID?.replace(/\D/g, '');
  if (!customerId) throw new Error('missing_google_ads_customer_id');
  return customerId;
}

function conversionActionResource(eventName: SpecConversionEventName): string | null {
  const envName = GOOGLE_CONVERSION_ACTION_ENV[eventName];
  const actionId = envName ? process.env[envName] : null;
  if (!actionId) return null;
  return `customers/${cleanCustomerId()}/conversionActions/${actionId.replace(/\D/g, '')}`;
}

export function formatGoogleAdsDateTime(date: Date): string {
  return date.toISOString().replace('T', ' ').replace(/\.\d{3}Z$/, '+00:00');
}

async function fetchGoogleAccessToken(): Promise<string> {
  const response = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'content-type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      client_id: process.env.GOOGLE_ADS_CLIENT_ID ?? '',
      client_secret: process.env.GOOGLE_ADS_CLIENT_SECRET ?? '',
      refresh_token: process.env.GOOGLE_ADS_REFRESH_TOKEN ?? '',
      grant_type: 'refresh_token',
    }),
  });

  const data = (await response.json()) as GoogleAccessTokenResponse;
  if (!response.ok || !data.access_token) {
    throw new Error(`google_oauth_${response.status}_${data.error ?? 'missing_access_token'}`);
  }
  return data.access_token;
}

export function buildGoogleConversionRequest(
  eventName: SpecConversionEventName,
  payload: ConversionEventPayload,
  now = new Date(),
): GoogleConversionRequest | null {
  const role = googleConversionRole(eventName);
  if (role === 'internal') return null;

  const conversionAction = conversionActionResource(eventName);
  if (!conversionAction) return null;

  const hashedEmail = hashEmail(typeof payload.email === 'string' ? payload.email : null);
  const hashedPhone = hashPhone(typeof payload.phone === 'string' ? payload.phone : null);
  const userIdentifiers = [
    hashedEmail ? { hashedEmail, userIdentifierSource: 'FIRST_PARTY' as const } : null,
    hashedPhone ? { hashedPhoneNumber: hashedPhone, userIdentifierSource: 'FIRST_PARTY' as const } : null,
  ].filter(Boolean) as NonNullable<GoogleConversionRequest['conversions'][number]['userIdentifiers']>;

  const gclid = typeof payload.gclid === 'string' && payload.gclid.trim() ? payload.gclid.trim() : null;
  if (!gclid && userIdentifiers.length === 0) {
    throw new Error('missing_match_key');
  }

  return {
    conversions: [{
      conversionAction,
      conversionDateTime: formatGoogleAdsDateTime(now),
      conversionValue: typeof payload.value_cents === 'number' ? payload.value_cents / 100 : 0,
      currencyCode: typeof payload.currency === 'string' ? payload.currency : 'CAD',
      orderId: typeof payload.spec_project_id === 'string' ? payload.spec_project_id : undefined,
      ...(gclid ? { gclid } : {}),
      ...(userIdentifiers.length > 0 ? { userIdentifiers } : {}),
    }],
    partialFailure: true,
    validateOnly: process.env.GOOGLE_ADS_VALIDATE_ONLY === 'true',
    debugEnabled: false,
  };
}

export async function sendGoogleEnhancedConversion(
  eventName: SpecConversionEventName,
  payload: ConversionEventPayload,
): Promise<GoogleSendResult> {
  if (!isGoogleConversionConfigured()) {
    return { ok: true, sent: false, error: null };
  }

  let body: GoogleConversionRequest | null;
  try {
    body = buildGoogleConversionRequest(eventName, payload);
  } catch (err) {
    return { ok: false, sent: false, error: err instanceof Error ? err.message : String(err) };
  }

  if (!body) {
    return { ok: true, sent: false, error: null };
  }

  const accessToken = await fetchGoogleAccessToken();
  const customerId = cleanCustomerId();

  const response = await fetch(`https://googleads.googleapis.com/${GOOGLE_ADS_API_VERSION}/customers/${customerId}:uploadClickConversions`, {
    method: 'POST',
    headers: {
      authorization: `Bearer ${accessToken}`,
      'content-type': 'application/json',
      'developer-token': process.env.GOOGLE_ADS_DEVELOPER_TOKEN ?? '',
      ...(process.env.GOOGLE_ADS_LOGIN_CUSTOMER_ID
        ? { 'login-customer-id': process.env.GOOGLE_ADS_LOGIN_CUSTOMER_ID.replace(/\D/g, '') }
        : {}),
    },
    body: JSON.stringify(body),
  });

  const responseBody = await response.json().catch(() => null) as { partialFailureError?: { message?: string } } | null;
  if (!response.ok) {
    return { ok: false, sent: false, error: `google_ads_${response.status}` };
  }
  if (responseBody?.partialFailureError?.message) {
    return { ok: false, sent: false, error: responseBody.partialFailureError.message };
  }

  return { ok: true, sent: true, error: null };
}
```

This matches the Google Ads upload-click-conversions REST shape: one `conversions` array, `partialFailure: true`, optional `validateOnly`, `gclid` when available, and first-party `hashedEmail` / `hashedPhoneNumber` user identifiers.

- [ ] **Step 4: Wire retry cron to sender**

Modify `/Users/jacksonsweet/Projects/OPS/ops-site/src/lib/spec/cron/conversion-event-retry.ts` so the file imports the sender and event type:

```ts
import { sendGoogleEnhancedConversion } from '@/lib/spec/google-enhanced-conversions';
import type { SpecConversionEventName } from '@/lib/spec/conversion-events';
```

Update Google credential detection:

```ts
const hasGoogle = Boolean(
  process.env.GOOGLE_ADS_DEVELOPER_TOKEN &&
  process.env.GOOGLE_ADS_CUSTOMER_ID &&
  process.env.GOOGLE_ADS_REFRESH_TOKEN &&
  process.env.GOOGLE_ADS_CLIENT_ID &&
  process.env.GOOGLE_ADS_CLIENT_SECRET,
);
```

Delete `sendConversionEventStub()` and use this row-loop body:

```ts
const sendOutcome = await sendGoogleEnhancedConversion(
  row.event_name as SpecConversionEventName,
  row.payload,
);

const nextAttempts = row.attempts + 1;
const reachedCap = nextAttempts >= MAX_ATTEMPTS;

if (sendOutcome.ok) {
  const { error: upErr } = await db
    .from('conversion_event_outbox')
    .update({
      status: 'sent',
      sent_at: now.toISOString(),
      last_attempt_at: now.toISOString(),
      last_error: null,
    })
    .eq('id', row.id);
  if (upErr) throw new Error(`success update failed: ${upErr.message}`);
  result.fired += sendOutcome.sent ? 1 : 0;
  if (!sendOutcome.sent) result.details.push(`processed without Google dispatch: ${row.id}`);
  return;
}

const { error: upErr } = await db
  .from('conversion_event_outbox')
  .update({
    status: reachedCap ? 'permanent_failure' : 'failed',
    attempts: nextAttempts,
    last_attempt_at: now.toISOString(),
    last_error: (sendOutcome.error ?? 'google_send_failed').slice(0, 400),
  })
  .eq('id', row.id);
if (upErr) throw new Error(`failure update failed: ${upErr.message}`);
```

Internal-only events should become `sent` because they were intentionally processed and skipped for ad dispatch.

- [ ] **Step 5: Run tests and verify pass**

Run:

```bash
cd /Users/jacksonsweet/Projects/OPS/ops-site
npm test -- src/lib/spec/__tests__/conversion-hash.test.ts src/lib/spec/cron/__tests__/conversion-event-retry.test.ts
```

Expected: exit 0.

- [ ] **Step 6: Commit**

Run:

```bash
cd /Users/jacksonsweet/Projects/OPS/ops-site
git add src/lib/spec/google-enhanced-conversions.ts src/lib/spec/cron/conversion-event-retry.ts src/lib/spec/cron/__tests__/conversion-event-retry.test.ts
git commit -m "feat(spec): dispatch Google enhanced conversions"
```

Expected: commit includes sender and retry wiring.

## Task 4: Add Client-Side SPEC Page And Card Events

**Files:**
- Modify: `/Users/jacksonsweet/Projects/OPS/ops-site/src/components/spec/PackageCard.tsx`
- Modify: `/Users/jacksonsweet/Projects/OPS/ops-site/src/components/spec/SpecPageContent.tsx`
- Modify: `/Users/jacksonsweet/Projects/OPS/ops-site/src/lib/marketing-analytics.ts`

- [ ] **Step 1: Add typed marketing event helper**

Modify `/Users/jacksonsweet/Projects/OPS/ops-site/src/lib/marketing-analytics.ts`:

```ts
export function trackSpecMarketingEvent(name: string, properties: AnalyticsProperties = {}) {
  trackMarketingEvent(name, {
    surface: 'spec',
    ...properties,
  });
}
```

- [ ] **Step 2: Track page view from SPEC content**

In `/Users/jacksonsweet/Projects/OPS/ops-site/src/components/spec/SpecPageContent.tsx`, import `useEffect` and `trackSpecMarketingEvent`, then fire:

```ts
useEffect(() => {
  trackSpecMarketingEvent('page_view', { spec_surface: 'landing' });
}, []);
```

If the component is currently a server component, create a small client child `SpecPageAnalytics.tsx` and render it once from the page content.

- [ ] **Step 3: Track card expansion**

In `/Users/jacksonsweet/Projects/OPS/ops-site/src/components/spec/PackageCard.tsx`, call:

```ts
trackSpecMarketingEvent('spec_card_expand', {
  tier,
  deposits_enabled: depositsEnabled,
});
```

inside the expansion handler only when a collapsed card opens.

- [ ] **Step 4: Commit**

Run:

```bash
cd /Users/jacksonsweet/Projects/OPS/ops-site
git add src/lib/marketing-analytics.ts src/components/spec
git commit -m "feat(spec): track landing page and package expansion"
```

Expected: commit contains client analytics instrumentation.

## Task 5: Track Default OPS Crossover

**Files:**
- Modify: `/Users/jacksonsweet/Projects/OPS/ops-site/src/components/spec/SpecBottomCTA.tsx`
- Modify: `/Users/jacksonsweet/Projects/OPS/ops-site/src/components/layout/MarketingAnalytics.tsx`
- Modify: `/Users/jacksonsweet/Projects/OPS/ops-web/src/app/(onboarding)/setup/page.tsx`

- [ ] **Step 1: Add SPEC return parameters to default OPS links**

Where `/spec` links to normal OPS signup, include:

```ts
const href = `/signup?source=spec&spec_last_interaction=${encodeURIComponent(lastInteraction)}&returnTo=/setup`;
```

Use the existing signup route shape in the codebase; keep `source=spec` and `spec_last_interaction` as the stable keys.

- [ ] **Step 2: Track CTA click**

On the default OPS CTA, call:

```ts
trackSpecMarketingEvent('spec_default_ops_cta_click', {
  spec_last_interaction: lastInteraction,
});
```

- [ ] **Step 3: Track setup start and completion in OPS-Web**

In `/Users/jacksonsweet/Projects/OPS/ops-web/src/app/(onboarding)/setup/page.tsx`, when `source=spec` is present, emit app analytics events:

```ts
analyticsService.track('action', 'spec_default_ops_signup_started', {
  source: 'spec',
  spec_last_interaction: params.get('spec_last_interaction') ?? 'unknown',
});
```

On successful company setup completion, emit:

```ts
analyticsService.track('action', 'spec_default_ops_signup_completed', {
  source: 'spec',
});
```

- [ ] **Step 4: Run focused tests**

Run:

```bash
cd /Users/jacksonsweet/Projects/OPS/ops-web
npm test -- src/lib/analytics/__tests__/analytics.test.ts
```

Expected: exit 0.

- [ ] **Step 5: Commit**

Run:

```bash
cd /Users/jacksonsweet/Projects/OPS/ops-web
git add src/app/\(onboarding\)/setup/page.tsx
git commit -m "feat(spec): track default OPS crossover signup"
```

Expected: commit contains default OPS crossover attribution.
