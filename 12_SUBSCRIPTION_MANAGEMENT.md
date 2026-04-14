# 12_SUBSCRIPTION_MANAGEMENT.md

**OPS Software Bible — Company Subscriptions, Trials, Seats & Stripe Integration**

**Purpose**: Definitive reference for how OPS company subscriptions are created, kept current, gated, and reconciled. Covers the Stripe → Supabase → iOS data path, every column on `companies` that drives gating, every writer and reader, and the cron jobs that protect against drift.

**Last Updated**: 2026-04-14
**Source Reference**: `ops-web/src/app/api/stripe/`, `ops-web/src/app/api/webhooks/stripe/`, `ops-web/src/app/api/cron/`, `ops-web/src/lib/subscription.ts`, `ops-web/supabase/migrations/EXECUTED/004_core_entities.sql`, `opsapp-ios/OPS/DataModels/Company.swift`, `opsapp-ios/OPS/Network/Supabase/DTOs/CoreEntityDTOs.swift`

---

## Table of Contents

1. [Source of Truth](#source-of-truth)
2. [Schema — `companies` Subscription Columns](#schema--companies-subscription-columns)
3. [Status & Plan Enums](#status--plan-enums)
4. [Lifecycle: Sign-up → Trial → Active → Grace → Expired](#lifecycle-signup--trial--active--grace--expired)
5. [Writers — Where Each Field Comes From](#writers--where-each-field-comes-from)
6. [Readers — Gating, Lockout, Display](#readers--gating-lockout-display)
7. [Stripe Webhook Handler](#stripe-webhook-handler)
8. [Idempotency](#idempotency)
9. [Cron Jobs](#cron-jobs)
10. [Seat Enforcement](#seat-enforcement)
11. [iOS Behavior](#ios-behavior)
12. [Android Status](#android-status)
13. [Operational Runbook](#operational-runbook)

---

## Source of Truth

**Stripe is canonical** for everything subscription-related. Supabase mirrors Stripe state via webhooks and is the read source for the web app, iOS, and (eventually) Android. Bubble holds no subscription state — historical fields like `subscription_status` on Bubble Company records are dead.

Two write paths land Stripe data into Supabase:
1. **Live**: `customer.subscription.*` and `invoice.payment_failed` webhooks → `/api/webhooks/stripe`
2. **Initial**: `POST /api/stripe/subscribe` writes the first row when a user upgrades

Two reconciliation paths catch drift from missed webhooks:
1. **Daily cron**: `/api/cron/reconcile-stripe-subscriptions` (02:00 UTC)
2. **Manual backfill**: `scripts/backfill-subscription-dates.ts --apply`

---

## Schema — `companies` Subscription Columns

Defined in `supabase/migrations/EXECUTED/004_core_entities.sql:69-86`.

| Column | Type | Default | Nullable | Purpose |
|---|---|---|---|---|
| `subscription_status` | TEXT (CHECK) | NULL | yes | One of `trial`, `active`, `grace`, `expired`, `cancelled`. Drives lockout. |
| `subscription_plan` | TEXT (CHECK) | NULL | yes | One of `trial`, `starter`, `team`, `business`. Drives feature gates and seat limits. |
| `subscription_period` | TEXT (CHECK) | NULL | yes | `Monthly` or `Annual`. Display only. |
| `subscription_end` | TIMESTAMPTZ | NULL | yes | Current period end (next renewal or expiry date). |
| `subscription_ids_json` | TEXT | NULL | yes | JSON array of Stripe subscription IDs for debugging. |
| `stripe_customer_id` | TEXT | NULL | yes | Stripe `cus_…` ID. Required for any subscription operation. |
| `trial_start_date` | TIMESTAMPTZ | NULL | yes | When the trial started (Stripe `trial_start`). |
| `trial_end_date` | TIMESTAMPTZ | NULL | yes | When the trial ends/ended (Stripe `trial_end`). Drives trial countdown. |
| `seat_grace_start_date` | TIMESTAMPTZ | NULL | yes | When the company first entered `grace`. Drives 7-day grace expiry. |
| `max_seats` | INT | 10 | no | Hard ceiling. Currently set by migration default; not overridden by plan changes. |
| `seated_employee_ids` | TEXT[] | `'{}'` | no | User IDs occupying paid seats. |
| `has_priority_support` | BOOLEAN | FALSE | no | Add-on flag. Not currently enforced. |
| `data_setup_purchased` | BOOLEAN | FALSE | no | Add-on flag. Not currently enforced. |
| `data_setup_completed` | BOOLEAN | FALSE | no | Add-on flag. Not currently enforced. |

---

## Status & Plan Enums

Defined in `ops-web/src/lib/types/models.ts` and mirrored in `opsapp-ios/OPS/DataModels/SubscriptionEnums.swift`.

| `subscription_status` | Stripe equivalent | App can be used? | Notes |
|---|---|---|---|
| `trial` | `trialing` | yes | Countdown shown via `trial_end_date`. |
| `active` | `active` | yes | Normal paying state. |
| `grace` | `past_due` | yes, with warning | 7-day window starting at `seat_grace_start_date`. |
| `expired` | (derived) | no | Set by daily cron after grace exceeds 7 days. Not a Stripe state. |
| `cancelled` | `canceled` | no | Set by `customer.subscription.deleted`. |

| `subscription_plan` | Max seats | Notes |
|---|---|---|
| `trial` | per `max_seats` default | Pre-conversion. |
| `starter` | per `max_seats` (3) | Smallest paid tier. |
| `team` | per `max_seats` (5) | Mid tier. |
| `business` | per `max_seats` (unlimited tier) | Largest tier. |

---

## Lifecycle: Sign-up → Trial → Active → Grace → Expired

```
                              user signs up
                                    │
                                    ▼
                  ┌───────────────────────────────┐
                  │  /api/auth/join-company       │
                  │  Postgres fn join_user_to_    │
                  │  company() — auto-seats user  │
                  └───────────────┬───────────────┘
                                  │
                                  ▼
                  ┌───────────────────────────────┐
                  │  user clicks "Upgrade" in UI  │
                  └───────────────┬───────────────┘
                                  │
                                  ▼
        ┌──────────────────────────────────────────────────┐
        │  POST /api/stripe/subscribe                      │
        │   • Creates Stripe customer (if needed)          │
        │   • Creates Stripe subscription                  │
        │   • Writes: subscription_status=active,          │
        │             subscription_plan, subscription_end, │
        │             trial_start_date, trial_end_date,    │
        │             stripe_customer_id                   │
        │   • Clears: seat_grace_start_date                │
        └──────────────────────────┬───────────────────────┘
                                   │
              ┌────────────────────┼─────────────────────┐
              │                    │                     │
              ▼                    ▼                     ▼
   customer.subscription   customer.subscription   invoice.payment_failed
   .updated                .deleted                
              │                    │                     │
              ▼                    ▼                     ▼
   maps Stripe.status     status = cancelled     status = grace
   → mapped status                                seat_grace_start_date
   trial_start/end                                = NOW() (only if null)
   grace_start (set/clear
   per status)
              │
              ▼
                   nightly /api/cron/reconcile-stripe-subscriptions
                   pulls from Stripe, applies same diffs (drift catch)

                   nightly /api/cron/expire-grace-periods
                   transitions grace → expired after 7 days
```

---

## Writers — Where Each Field Comes From

| Field | Writers |
|---|---|
| `subscription_status` | `POST /api/stripe/subscribe` (initial), `webhooks/stripe customer.subscription.created/updated` (live), `webhooks/stripe customer.subscription.deleted` (cancellation), `webhooks/stripe invoice.payment_failed` (grace), `cron/expire-grace-periods` (grace→expired), `cron/reconcile-stripe-subscriptions` (drift fix) |
| `subscription_plan` | `POST /api/stripe/subscribe` only |
| `subscription_period` | `POST /api/stripe/subscribe` only |
| `subscription_end` | `POST /api/stripe/subscribe`, webhook `subscription.created/updated`, reconcile cron |
| `subscription_ids_json` | `POST /api/stripe/subscribe`, webhook `subscription.created/updated/deleted` |
| `stripe_customer_id` | `POST /api/stripe/subscribe` (one-time) |
| `trial_start_date` | `POST /api/stripe/subscribe`, webhook `subscription.created/updated`, reconcile cron, manual backfill script |
| `trial_end_date` | Same as `trial_start_date` |
| `seat_grace_start_date` | webhook `invoice.payment_failed` (set, only if null), webhook `subscription.created/updated` (set on grace, clear on active/trial), reconcile cron |
| `max_seats` | Migration default 10. Not currently overridden by plan changes — **gap**. |
| `seated_employee_ids` | Postgres function `join_user_to_company()` (auto-seat on join), `CompanyService.addSeatedEmployee()` and `removeSeatedEmployee()` (manual via team UI) |
| `has_priority_support`, `data_setup_*` | Never written by code. **Gap** — add-on flags not yet implemented. |

---

## Readers — Gating, Lockout, Display

The single source of truth for interpretation is `ops-web/src/lib/subscription.ts`. Every gating decision flows through `getSubscriptionInfo(company)` and `getLockoutReason(company, userId)`.

**Lockout precedence** (`subscription.ts:213-232`):
1. `subscription_expired` — `subscription_status` ∈ `{expired, cancelled}` or trial countdown ≤ 0
2. `unseated` — user is not in `seated_employee_ids` and not in `admin_ids`

**Realtime gate**: `components/ops/lockout-overlay.tsx` subscribes to `companies` row changes via Supabase Realtime and re-evaluates `getLockoutReason()` on every update. Non-admin unseated users see the lockout modal; admin unseated users get a self-service link to `/team`.

**Trial countdown**: `subscription.ts:113-142` reads `trial_end_date` and computes `daysRemaining`. If `trial_end_date` is null, countdown is broken (was historically true before the 2026-04 fix).

---

## Stripe Webhook Handler

`ops-web/src/app/api/webhooks/stripe/route.ts` handles the following events. Every handler is keyed on `stripe_customer_id` to find the company.

### `customer.subscription.created` / `customer.subscription.updated`

- Maps Stripe `status` → OPS status (`active`, `trial`, `grace`, `cancelled`, or pass-through).
- Writes `subscription_status`, `subscription_end`, `subscription_ids_json`.
- Writes `trial_start_date` / `trial_end_date` from `subscription.trial_start` / `trial_end` if present.
- If mapped status is `grace`: sets `seat_grace_start_date = NOW()`.
- If mapped status is `active` or `trial`: clears `seat_grace_start_date` to null.

**Note on `cancel_at_period_end`**: when this is true Stripe keeps the subscription `active` until the period end, so we keep it `active` in OPS. The `.deleted` event fires when the period actually ends and that's when we set `cancelled`.

### `customer.subscription.deleted`

- Sets `subscription_status = cancelled`, clears `subscription_ids_json`.

### `invoice.payment_failed`

- Sets `subscription_status = grace`.
- Sets `seat_grace_start_date = NOW()` **only if currently null**. This is critical: subsequent retries of the same failure must not slide the grace window forward.

### `payment_intent.succeeded`

- Unrelated to subscriptions — handles client portal invoice payments. See `09_FINANCIAL_SYSTEM.md`.

---

## Idempotency

Stripe guarantees at-least-once delivery and retries failed deliveries for up to 3 days. The handler dedupes via `stripe_webhook_events` (migration `063_stripe_webhook_events.sql`):

1. Top of handler: `SELECT event_id FROM stripe_webhook_events WHERE event_id = ?`. If found, ack and exit (`{received:true, duplicate:true}`).
2. Bottom of handler (after successful processing): `INSERT` the event_id. A unique-violation here is benign — a concurrent delivery beat us to it.

The dedup row is recorded **after** processing, not before, so a mid-handler failure still gets retried by Stripe instead of being silently skipped.

Most field updates are also idempotent by value (status, dates), so even an undeduped retry produces the same end state. The exception is `seat_grace_start_date` on `invoice.payment_failed`, which is protected by the read-then-write null-check.

---

## Cron Jobs

Configured in `ops-web/vercel.json`. All require `Authorization: Bearer ${CRON_SECRET}`.

| Path | Schedule (UTC) | Purpose |
|---|---|---|
| `/api/cron/reconcile-stripe-subscriptions` | `0 2 * * *` (02:00 daily) | Pulls every company with `stripe_customer_id` from Stripe and patches drift in `subscription_status`, `subscription_end`, `trial_start_date`, `trial_end_date`, `seat_grace_start_date`. Same logic as the live webhook, applied defensively. |
| `/api/cron/expire-grace-periods` | `0 4 * * *` (04:00 daily) | Transitions companies that have been in `grace` for more than 7 days into `expired`. The 7-day window matches `Company.daysRemainingInGracePeriod` on iOS. |

**Trial expiry is not handled by a cron** — Stripe automatically fires `customer.subscription.updated` when a trial ends and transitions the subscription to `active` (if payment succeeds) or `past_due` (if it fails). The reconcile cron catches any missed transitions.

---

## Seat Enforcement

**Read sources**:
- `lib/subscription.ts:170-205` — `canAddSeat()`, `isUserSeated()`
- `components/ops/lockout-overlay.tsx:410` — calls `getLockoutReason()` on every protected page

**Write sources**:
- Postgres function `join_user_to_company()` — `supabase/migrations/031_join_user_to_company_function.sql:140-150`. Atomically appends the joining user to `seated_employee_ids` if a seat is available.
- `CompanyService.addSeatedEmployee()` — `lib/api/services/company-service.ts:149-165`. Used by the team-tab seat toggle.
- `CompanyService.removeSeatedEmployee()` — same file lines 170-182.

**Counting**: total seats in use = `seated_employee_ids.length + admin_ids.length`. Admins are always considered seated and never count against the explicit seat array.

---

## iOS Behavior

iOS reads the subscription columns via `SupabaseCompanyDTO` (`opsapp-ios/OPS/Network/Supabase/DTOs/CoreEntityDTOs.swift`) and stores them on the `Company` SwiftData model. **iOS never writes subscription fields back** — the app is a read-only consumer.

**Computed properties** (`Company.swift:160-199`):
- `subscriptionStatusEnum` — string → `SubscriptionStatus` enum
- `isSubscriptionActive` — true for `active`, `trial`, `grace`
- `shouldShowGracePeriodWarning` — true for `grace`
- `daysRemainingInTrial` — derived from `trial_end_date`
- `daysRemainingInGracePeriod` — `7 - daysSince(seat_grace_start_date)`

If `trial_end_date` or `seat_grace_start_date` is null, the corresponding countdown returns nil and the UI hides it. Prior to 2026-04 these were always null because nothing ever wrote them — countdowns were silently dead.

---

## Android Status

**Android does not currently sync companies from Supabase.** As of 2026-04, `opsapp-android/app/src/main/java/co/opsapp/ops/data/remote/dto/CompanyDto.kt` is the only company DTO and it deserializes Bubble's camelCase JSON. Subscription columns are present on `CompanyEntity` (Room) but populated from Bubble fields that Bubble does not write.

To bring Android to parity:
1. Add a Supabase client (`io.github.jan.supabase:supabase-kt` or Retrofit interface against the Supabase REST endpoint).
2. Add `SupabaseCompanyDto` (snake_case @SerializedName) mirroring iOS's DTO.
3. Wire it into `CentralizedSyncManager.syncCompany()` alongside or replacing the Bubble path.
4. Add the missing Hilt module + secret management for Supabase URL/anon key.

Estimate: 3-5 days. Not in scope for the 2026-04 subscription fix work.

---

## Operational Runbook

### Reconcile a single company by hand

```bash
# Dry-run all companies
npx tsx scripts/backfill-subscription-dates.ts

# Apply all
npx tsx scripts/backfill-subscription-dates.ts --apply
```

### Test a webhook locally

```bash
# Terminal 1
npm run dev

# Terminal 2 — requires Stripe CLI
stripe listen --forward-to localhost:3000/api/webhooks/stripe
stripe trigger customer.subscription.updated
stripe trigger invoice.payment_failed
```

### Manually expire a company's grace period

```sql
UPDATE companies
SET subscription_status = 'expired'
WHERE id = '...';
```

### Force a webhook re-run

The dedup table makes webhook re-delivery a no-op. To replay an event:

```sql
DELETE FROM stripe_webhook_events WHERE event_id = 'evt_…';
```

Then resend from the Stripe Dashboard.

### Check for drift

The reconcile cron logs every drift fix. Search Vercel logs for `[reconcile-stripe] drift fixed`. A spike means webhooks are being missed — investigate webhook secret, signature failures, or Stripe outages.

---

## Known Gaps (as of 2026-04-14)

1. **`max_seats` is not updated when the plan changes.** Currently fixed at the migration default of 10. Plan tier limits (3/5/unlimited) are enforced in app logic via `subscription_plan` reads, not via this column. Either remove the column or wire plan-change logic to update it.
2. **`has_priority_support`, `data_setup_purchased`, `data_setup_completed`** are defined but never written. Add-on features not yet implemented.
3. **Android has no Supabase company sync.** See [Android Status](#android-status).
4. **Reconcile cron is per-row, not paginated.** At >1k companies it will exceed the 300s function timeout. Add pagination or move to a background job before that.
5. **Failed reconcile updates are logged but not alerted.** Add to your monitoring stack.
