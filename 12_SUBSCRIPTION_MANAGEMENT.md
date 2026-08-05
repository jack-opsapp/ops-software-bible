# 12_SUBSCRIPTION_MANAGEMENT.md

**OPS Software Bible — Company Subscriptions, Trials, Seats & Stripe Integration**

**Purpose**: Definitive reference for how OPS company subscriptions are created, kept current, gated, and reconciled. Covers the Stripe → Supabase → iOS data path, every column on `companies` that drives gating, every writer and reader, and the cron jobs that protect against drift.

**Last Updated**: 2026-08-04
**Source Reference**: `ops-web/src/app/api/stripe/`, `ops-web/src/app/api/decks/`, `ops-web/src/app/api/webhooks/stripe/`, `ops-web/src/app/api/cron/`, `ops-web/src/lib/decks/billing/stripe-deckset.ts`, `ops-web/src/lib/subscription.ts`, `ops-ios/OPS/DataModels/Company.swift`, `ops-ios/OPS/Network/Supabase/DTOs/CoreEntityDTOs.swift`, `ops-decks-ios/OPSDecks/DecksSubscriptionMirrorService.swift`

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

### OPS Decks Standalone Exception

OPS Decks standalone billing is not an OPS company subscription. Stripe Checkout is canonical for Deckset Pro, with Apple Pay surfaced by Stripe Checkout when the Stripe payment method/domain setup supports it. Supabase mirrors Stripe state only for app gating, support visibility, and cross-device consistency.

OPS Decks standalone authentication follows the main OPS iOS model: Firebase Auth owns identity, and Firebase ID tokens are passed to Supabase/PostgREST and deck-specific API routes. OPS Decks must not use Supabase Auth sessions as its primary mobile auth stack.

The mirror table is `deck_subscriptions`:

| Column | Purpose |
|---|---|
| `company_id` | Owning deck-only company. |
| `entitlement` | Deckset entitlement key. P0 is `deck_pro`. |
| `status` | Deckset entitlement status. `active`, `trialing`, and `in_grace` unlock Pro; `expired`, `cancelled`, and `revoked` do not. |
| `product_id` | Deckset product key such as `deck_pro_monthly` or `deck_pro_annual`. |
| `store` / `provider` | Billing channel. Stripe-backed rows use `stripe`. |
| `customer_id` / `stripe_customer_id` | Stripe customer id for support and reconciliation. |
| `stripe_subscription_id` | Stripe subscription id; unique when present. |
| `stripe_price_id` | Stripe price id that maps to the Deckset monthly or annual SKU. |
| `stripe_checkout_session_id` | Last checkout session that produced or refreshed the mirror row. |
| `current_period_end` / `expires_at` | Stripe current period end, mirrored for app gating. |
| `last_event_at` | Last processed Stripe webhook timestamp. |

RLS allows company-scoped reads for the owning company. Writes are server-only through Stripe Checkout/webhook code paths. Deckset may use `companies.stripe_customer_id` as the shared Stripe customer pointer, but it must not write Deckset entitlement state into `companies.subscription_status`, `trial_end_date`, `subscription_end`, `subscription_plan`, `subscription_period`, or `subscription_ids_json`.

Company-of-one provisioning for OPS Decks creates or links a `users` row and one deck-only `companies` row. The endpoint may return `subscription_plan = 'decks'` or an explicit deck-origin field so the full OPS app can route the operator to an upgrade surface. Full contract: `ops-ios/docs/superpowers/specs/2026-06-25-ops-decks-phase-1-backend-contract.md`.

#### As-built — web backend (2026-07-03)

The web side of the Stripe path is implemented and hardened. Source: `ops-web/src/app/api/decks/`, `ops-web/src/lib/decks/billing/stripe-deckset.ts`, `ops-web/src/app/api/webhooks/stripe/route.ts`.

**Endpoints**
- `POST /api/decks/provision-company` — idempotent company-of-one keyed on the verified Firebase subject. Existing user with a company returns it untouched; otherwise it creates the `users` row and delegates company creation to the `provision_deck_company` RPC (service-role only), which wraps the hardened `create_company_for_owner` path and stamps the deck origin. Always links `users.firebase_uid` (fill-only, never clobbered) so the mirror's RLS resolves. Returns `company_id`/`user_id` lowercased and `subscription_plan: "decks"`. Migration `20260703211000_deck_provisioning.sql`.
- `POST /api/decks/checkout` — creates the Stripe Checkout subscription session (Monthly/Annual). Company scope is compared case-insensitively against the provisioned lowercase `company_id`.
- `GET /decks/checkout/result?status=success|cancelled` — standalone, auth-free Stripe return surface (`ops-web/src/app/decks/`). Success tells the operator Pro unlocks on the app's next foreground refresh; cancel confirms nothing was charged.

**Deck-origin marker.** `companies.source_app` (`'ops'` default, `'ops_decks'` for Deckset-provisioned companies) is the concrete deck-origin field; set by `provision_deck_company` only on companies it creates. Migration `20260703211000_deck_provisioning.sql`.

**RLS reality.** The Deckset app queries PostgREST with a Firebase ID token that carries no `role` claim, so it executes as the `anon` role. The `deck_subscriptions` read policy is therefore `TO public` with `USING (company_id = private.get_user_company_id())` and `anon` holds a `SELECT` grant — mirroring the working `deck_designs` pattern. Without this, entitlement reads 42501 and paid Pro never unlocks. Writes stay service-role only. Migration `20260703210000_deck_subscriptions_anon_read.sql`. (General rule: the app executes as `anon`, so RLS policies must target `public`/anon, not `authenticated`.)

**Webhook isolation guarantees** (enforced in `route.ts`, so Deckset billing can never affect OPS company state):
- `invoice.payment_failed` flips a company to `grace` **only** when the failed invoice bills the OPS base plan (tracked base-plan subscription id, or a configured base-plan price on first failure). Deckset, priority-support add-on, and one-off invoice failures never touch `companies.subscription_status`.
- The `deck_subscriptions` mirror write goes through the `mirror_deck_subscription(jsonb)` RPC — a single atomic conditional upsert (`ON CONFLICT (company_id) DO UPDATE ... WHERE last_event_at <= incoming`, under the conflict's row lock). A delayed out-of-order `subscription.updated` (older `event.created`) is skipped in SQL, so it cannot resurrect a cancelled Pro even under concurrent same-company deliveries. Migration `20260703212000_deck_subscription_mirror_rpc.sql`.
- Deckset checkout on a comp-granted company (the durable-grant signature: `status=active` + `plan=business` + far-future `subscription_end` + NULL `stripe_customer_id`) creates a **dedicated** Stripe customer stored only on `deck_subscriptions.stripe_customer_id`; `companies.stripe_customer_id` stays NULL so the grant survives (a NULL `stripe_customer_id` alongside the far-future `subscription_end` is the durable comp-grant signature — see § 09 financial notes on comp grants).
- Deckset events (subscription / checkout / invoice; charge refunds/disputes traced via the invoice payment, fail-open) are excluded from the PMF `billing_events` ledger, so deck revenue never inflates OPS MRR or trips `billing_events_first_paid`.

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
| `has_priority_support` | BOOLEAN | FALSE | no | Priority Support add-on entitlement. Flipped by the Stripe webhook (`handlePrioritySupportCheckout`) on add-on checkout. See § 07 Subscription Add-ons. |
| `data_setup_purchased` | BOOLEAN | FALSE | no | Data Setup add-on entitlement (one-time). Flipped `true` by the Stripe webhook (`handleDataSetupCheckout`) on `checkout.session.completed`; also files a `data_setup_requests` row for ops fulfillment. See § 07 Subscription Add-ons / `03_DATA_ARCHITECTURE.md`. |
| `data_setup_completed` | BOOLEAN | FALSE | no | Flipped by ops staff in `/admin/data-setup` once the data migration is fulfilled. |

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
| `has_priority_support` | Stripe webhook `handlePrioritySupportCheckout` (set on add-on `checkout.session.completed`; cleared on add-on `subscription.deleted/updated`). |
| `data_setup_purchased` | Stripe webhook `handleDataSetupCheckout` (set on one-time `checkout.session.completed`). |
| `data_setup_completed` | Ops staff via `/admin/data-setup` (request lifecycle → `completed`). |

---

## Readers — Gating, Lockout, Display

The single source of truth for interpretation is `ops-web/src/lib/subscription.ts`. Every gating decision flows through `getSubscriptionInfo(company)` and `getLockoutReason(company, userId)`.

**Lockout precedence** (`subscription.ts:213-232`):
1. `subscription_expired` — `subscription_status` ∈ `{expired, cancelled}` or trial countdown ≤ 0
2. `unseated` — user is not in `seated_employee_ids` and not in `admin_ids`

**Realtime gate**: `components/ops/lockout-overlay.tsx` keeps the backdrop, `AnimatePresence`, and `pathname`-based route exemptions, then delegates content to `components/lockout/lockout-resolver.tsx`. The resolver:

1. Reads `company` + `currentUser` from `useAuthStore`.
2. Computes `getLockoutReason(company, userId)` (this file unchanged).
3. Picks one of four state modules under `components/lockout/states/`:
   - `expired-admin.tsx` — pricing row + reactivation CTAs (recommended tier highlighted, no ribbon, no checkmarks)
   - `expired-member.tsx` — admin tag + request reactivation (24h cooldown via `useRequestCooldown`)
   - `unseated-admin.tsx` — `/team` self-service link
   - `unseated-member.tsx` — admin tag + request access
4. Wraps the chosen module in `LockoutShell` (top rail / heading / body / divider / state slot / footer + fingerprint).

The same resolver also drives the standalone `/locked` page — page mode redirects to `/dashboard` when `getLockoutReason` returns `null` (fixes a prior bug where the page rendered admin-expired pricing regardless of state). Realtime company-row subscription lives in `components/lockout/hooks/use-realtime-company.ts` and patches `subscription_status`, `subscription_plan`, `subscription_end`, `trial_end_date`, `max_seats`, `seated_employee_ids`, and `admin_ids` in the auth store.

Design rationale and visual contract: `OPS-Web/docs/superpowers/specs/2026-05-07-lockout-redesign-design.md`.

**Trial countdown**: `subscription.ts:113-142` reads `trial_end_date` and computes `daysRemaining`. If `trial_end_date` is null, countdown is broken (was historically true before the 2026-04 fix).

---

## Payment-Method Default Contract (lockout recovery)

The Stripe customer's `invoice_settings.default_payment_method` is the linchpin of re-subscribe / recovery. Subscribe resolves the charge card in this order:

- `POST /api/stripe/subscribe` **with** `paymentMethodId` → attaches it and sets it as the customer default.
- `POST /api/stripe/subscribe` **without** `paymentMethodId` (what `subscription-tab.tsx` sends on Upgrade) → requires `invoice_settings.default_payment_method` to already exist, else returns **402 `payment_method_required`** ("Add a card in Settings → Billing first").

Writers of `invoice_settings.default_payment_method`:

| Writer | When |
|---|---|
| `POST /api/stripe/subscribe` | When called with an explicit `paymentMethodId`. |
| `POST /api/stripe/payment-methods` `{ action: "set_default" }` | Idempotently attaches the card (resolved off the PM's own `customer` field — a card attached to a *different* customer is refused with 409, never silently moved) and promotes it to the default. Returns `{ success, defaultPaymentMethodId }`. Fronted by `useSetDefaultPaymentMethod`. |
| `AddCardForm` (Settings → Billing) | After a successful SetupIntent, auto-calls `set_default` **when the customer has no default yet**. Non-default saved cards expose an explicit "Set as default" action. |

**Recovery flow:** a locked/churned customer adds a card via SetupIntent in Settings → Billing → the card is auto-promoted to default → a subsequent `POST /api/stripe/subscribe` (no `paymentMethodId`) finds the default and succeeds. Before the 2026-06 fix, the SetupIntent attached the card but never set the default, so subscribe stayed stuck at 402 against a card the customer had already added — a revenue-blocking dead loop.

`/api/stripe/payment-methods` surface: `GET` (list, with `isDefault`), `POST` (`action: "set_default"`), `DELETE` (detach).

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

**Trial-expiry *emails* are handled by a separate cron** — `/api/cron/trial-expiry` (`0 14 * * *` UTC, 7am PT) fires the warning/discount/reengagement sequence at the 7/5/3/1 day pre-expiry and 7/30 day post-expiry marks, deduplicated via `trial_expiry_notifications`. This is independent of the Stripe-driven subscription state transitions above. See `13_EMAIL_SYSTEM.md` § Trial-Expiry Lifecycle.

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
2. **Add-on entitlement flags are fulfillment markers, not feature gates.** `has_priority_support`, `data_setup_purchased`, and `data_setup_completed` ARE written — Stripe webhooks (`handlePrioritySupportCheckout` / `handleDataSetupCheckout`) on add-on checkout, and ops staff for `data_setup_completed`. The **Data Setup** and **Priority Support** add-ons are implemented end-to-end (§ 07 Subscription Add-ons; the `data_setup_requests` ops queue, `03_DATA_ARCHITECTURE.md`). What remains true: no app feature *gates* on these columns — they drive ops fulfillment + Subscription-tab display, not access control. *(Corrected 2026-06-13 — the prior "never written / not yet implemented" note was stale.)*
3. **Android has no Supabase company sync.** See [Android Status](#android-status).
4. **Reconcile cron is per-row, not paginated.** At >1k companies it will exceed the 300s function timeout. Add pagination or move to a background job before that.
5. **Failed reconcile updates are logged but not alerted.** Add to your monitoring stack.
