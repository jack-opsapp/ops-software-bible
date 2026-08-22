# 04 - API AND INTEGRATION

**OPS Software Bible - Complete API and Integration Architecture**

**Purpose**: This document provides comprehensive documentation of the OPS backend integration, sync architecture, and network operations. It covers the Supabase backend, repository layer, sync strategies, realtime subscriptions, conflict resolution, image handling, push notifications, and integration patterns. This enables any developer or AI agent to implement the entire sync system from scratch with complete fidelity to the iOS implementation.

**Last Updated**: August 7, 2026
**iOS Reference**: `ops-ios/OPS/Network/` (Supabase/, Sync/, Auth/, Services/)
**Android Reference**: C:\OPS\opsapp-android\app\src\main\java\co\opsapp\ops\data\ (planned)

---

## Table of Contents

1. [Backend Overview](#backend-overview)
2. [Supabase Configuration](#supabase-configuration)
3. [Supabase Repositories](#supabase-repositories)
4. [SyncEngine (Offline-First Orchestrator)](#syncengine-offline-first-orchestrator)
5. [SupabaseSyncManager (Legacy Adapter)](#supabasesyncmanager-legacy-adapter)
6. [OutboundProcessor (Push Queue)](#outboundprocessor-push-queue)
7. [InboundProcessor & Conflict Resolution (Field-Level Merge)](#inboundprocessor--conflict-resolution-field-level-merge)
8. [RealtimeProcessor (WebSocket)](#realtimeprocessor-websocket)
9. [BackgroundSyncScheduler](#backgroundsyncscheduler)
10. [PhotoProcessor & Image Upload](#photoprocessor--image-upload)
11. [ConnectivityManager](#connectivitymanager)
12. [OneSignal Push Notifications](#onesignal-push-notifications)
13. [Firebase Analytics](#firebase-analytics)
14. [Stripe Subscription Integration](#stripe-subscription-integration)
15. [Accounting Edge Functions (Expense Push)](#accounting-edge-functions)
16. [QuickBooks Read-Only Sync — Pull → Stage → Review → Apply](#quickbooks-read-only-sync--pull--stage--review--apply-2026-06-04)
17. [Error Handling & Retry Logic](#error-handling--retry-logic)
18. [Rate Limiting & Debouncing](#rate-limiting--debouncing)
19. [Supabase Table Reference](#supabase-table-reference)
20. [Bubble.io (Legacy)](#bubbleio-legacy)
21. [Bubble-to-Supabase Migration API](#bubble-to-supabase-migration-api)
22. [Email Pipeline Integration Routes (24 Routes)](#email-pipeline-integration-routes-24-routes)
23. [OpenAI API Key Separation](#openai-api-key-separation)

---

## Backend Overview

### Architecture Summary

OPS uses **Supabase (PostgreSQL)** as the primary backend for both the iOS app and the OPS Web app. Supabase provides:
- PostgreSQL database with Row-Level Security (RLS)
- Native authentication (Apple Sign-In + Google Sign-In via `signInWithIdToken`)
- Realtime WebSocket subscriptions for push-based data updates
- RESTful PostgREST API consumed via the `supabase-swift` SDK

**OPS-Web** (`https://app.opsapp.co`) serves as the API gateway for operations that require server-side secrets, including:
- Presigned URL generation for S3 image uploads (`/api/uploads/presign`)
- Atomic, idempotent Share Extension photo filing (`/api/uploads/share-photo`)
- OneSignal push notification routing (`/api/notifications/send`)
- Stripe subscription management
- OPS Decks verified zoning parcel lookup (`/api/decks/zoning/parcel`)
- OPS Decks verified zoning parcel import (`/api/admin/decks/zoning/parcel-records/import`)

**Bubble.io** is **legacy** -- see the [Bubble.io (Legacy)](#bubbleio-legacy) section for details on what remains.

### System Diagram

```
iOS App (SwiftData)                   OPS Web (Next.js)
    |                                      |
    |-- supabase-swift SDK ------------->  Supabase (PostgreSQL + Auth + Realtime)
    |                                      |
    |-- HTTPS --------> app.opsapp.co ----+--- /api/uploads/presign --> AWS S3
    |                                      +--- /api/uploads/share-photo --> AWS S3 + project filing
    |                                      +--- /api/notifications/send --> OneSignal
    |                                      +--- /api/stripe/* --> Stripe
    |                                      +--- /api/decks/zoning/parcel --> Verified zoning cache
    |                                      +--- /api/admin/decks/zoning/parcel-records/import --> Verified zoning cache ingest
    |                                      +--- /api/integrations/email/* --> Email Pipeline (17 routes)
    |                                      +--- /api/integrations/microsoft365/* --> M365 OAuth (2 routes)
    |                                      +--- /api/cron/auto-send --> Auto-send cron (5 min)
    |                                      +--- /api/admin/ai-features/* --> AI Feature Admin (3 routes)
    |                                      +--- /api/cron/email-sync --> Scheduled email sync
    |                                      +--- /api/cron/webhook-renewal --> Webhook renewal
    |                                      +--- /api/admin/migrate-bubble --> Bubble migration
    |
    |-- OneSignalFramework (receive push)
    |-- FirebaseAnalytics (event tracking)
```

### Authentication Flow

1. User signs in with Apple or Google via native iOS SDK
2. The ID token is passed to Supabase Auth via `signInWithIdToken`
3. Supabase creates or matches a user, returns a session JWT
4. All subsequent Supabase requests use the session JWT automatically (anon key + RLS)
5. Most server-side API calls to OPS-Web pass the Supabase `accessToken` as the `Bearer` header.
6. `/api/uploads/share-photo` is an intentional exception: both Share Extension paths use a Firebase ID token. OPS-Web verifies it, then resolves the OPS user through `users.auth_id` / `users.firebase_uid` before applying the company and permission boundary.

### OPS Decks Zoning Parcel Lookup

`POST /api/decks/zoning/parcel` is the standalone OPS Decks gateway route for address-based site-plan import. The app sends `Authorization: Bearer <Supabase/Firebase access token>` and JSON `{ site_address, jurisdiction_id?, source_app: "ops_decks" }`. OPS-Web verifies the token with the shared Supabase/Firebase verifier, resolves the caller through `users.auth_id` / `users.firebase_uid` / `users.email`, and uses the caller's `company_id` for the lookup boundary.

The route reads `public.deck_zoning_parcel_records` via service role only. It first checks company-specific verified records, then global verified records. A hit returns DeckKit's native shape: `{ request: { siteAddress, jurisdictionId? }, parcelZoning }`, where `parcelZoning` is a `ParcelZoningPlan` JSON object with `status` in `available`, `partial`, or `userEntered`. A miss returns `404 { error: "Parcel zoning record not found" }` so the standalone app can open manual criteria entry. The route must never invent setbacks, lot coverage, height limits, parcel geometry, or jurisdiction rules from an address.

`POST /api/admin/decks/zoning/parcel-records/import` is the OPS-Web admin-only ingest route for verified zoning cache rows. The body is `{ dry_run?: boolean, records: [...] }`; each record must include `site_address` and a DeckKit `parcel_zoning` object with `siteAddress`, valid `status`, and either `parcel` or `criteria` for `available` / `partial` sources. The route normalizes the address, derives provider/source URL/jurisdiction from the record when possible, supports dry-run previews with no writes, rejects the whole batch when any row is invalid, and idempotently updates active matches before inserting new rows. This route is for controlled OPS ingestion only; standalone clients consume the read route above.

### Cross-Platform Onboarding & Signup Contract

Onboarding completion is server-authoritative across OPS-Web, ops-site handoff paths, and OPS iOS. A user is not considered fully onboarded by any client unless the server-backed `users.onboarding_completed` map confirms the relevant platform and the user also has a valid `company_id` and `user_type`.

**Web setup routes (`OPS-Web`):**

| Route | Purpose | Contract |
|-------|---------|----------|
| `POST /api/setup/progress` | Persist web setup drafts and partial progress | Idempotent per step. The company step calls **`create_company_for_owner_by_id`** (service-role only) so the company, its `company_code`, the Owner `user_roles` row, the owner labels (`company_id`, `is_company_admin`, `role='owner'`, `user_type='company'`) and `initialize_company_defaults` all commit in **one transaction**. `create_company_for_owner` is not reachable from this route — it identifies its caller via `auth.jwt() ->> 'sub'` and raises `NO_JWT` under the service-role client — hence the by-id twin. The RPC **adopts** an existing unlinked company held by the same `account_holder_id` rather than inserting a second one, which is what makes a retry after a partial failure safe. Typed errors map to status: `NO_USER_ROW`/`ALREADY_IN_COMPANY` → 409, `INVALID_NAME` → 400, `USER_INACTIVE` → 403, anything else → 500. |
| `POST /api/setup/complete` | Complete owner/company web setup | Requires a company-attached owner/admin-capable user. Rejects employee users. Merges `onboarding_completed.web=true`; clients must not mark web onboarding complete locally until this response succeeds. |
| `POST /api/auth/join-company` | Join an existing company by code | Calls `join_user_to_company(p_user_id, p_company_id, p_company_code)` and must pass the normalized company-code proof. **The route's own admin-rail notification fan-out was removed (2026-06, ops-web commit `bc61f062`)** — the per-admin rail rows are now written inside the RPC. The route **keeps** its OneSignal push fan-out. |
| `POST /api/onboarding/complete` | Complete iOS onboarding through the web API gateway | Accepts Firebase `idToken`/`token` plus `platform:"ios"`, verifies the OPS user, requires `company_id` and `user_type`, rejects non-admin company users when completing company-owner onboarding, merges `onboarding_completed.ios=true`, and records `setup_progress.steps.ios_onboarding=true`. |

#### Owner role seeding — write order is load-bearing (2026-08-18)

`public.user_roles` carries the deferrable constraint trigger
`trg_user_roles_final_state` → `private.guard_user_roles_final_state()`, which rejects any
direct write whose target is already a company admin (`target_is_admin`, SQLSTATE `42501`).
It decides admin-ness via `private.permission_user_is_admin(u.id, u.company_id)`, whose body
compares `u.company_id = p_company_id`. When `users.company_id` is NULL that comparison is
NULL, so the user reads as a non-admin and the write is permitted. Two consequences:

- **The Owner `user_roles` row must be written *before* the update that sets `company_id` +
  `is_company_admin`.** Reversing the order raises `target_is_admin`. The web route no longer does
  this ordering itself — since 2026-08-18 `create_company_for_owner_by_id` owns it, using the same
  detach → immediate-check → restore sequence. Regression cover:
  `tests/integration/setup-progress-owner-role.test.ts` (ops-web).
- **`create_company_for_owner` reaches the same state from the other side** — it clears
  `company_id`/`is_company_admin`, wraps its insert in
  `set constraints trg_user_roles_final_state immediate` … `deferred` so the guard evaluates
  while the user is detached, then restores the final owner state.

Repairing an *existing* admin therefore cannot be done with a plain INSERT; it requires the
RPC's detach → immediate-check → restore sequence in a single transaction. See
`migrations/20260818224814_repair_web_onboarded_owner_role_rows.sql`.

**Incident (bug `bb4775c1-07a5-444c-a9b2-952e9b9b2f0e`).** Until 2026-08-18 the company step
wrote the company and linked the user but never wrote a `user_roles` row, never set
`role`/`user_type`, and never minted a `company_code`. Every one of the 5 web-onboarded
account holders was affected; 0 of the iOS-onboarded ones were. All five were repaired by the
migration above, which also back-filled their missing join codes.

**Incident 2 — orphan companies (same route, 2026-08-18).** Closing the role-write hole left a
second gap: the company step still spanned four autocommit statements (insert `companies` →
`initialize_company_defaults` → upsert `user_roles` → update `users`). A failure in the last two
returned 500 with the company already committed and `users.company_id` still NULL — and the retry
re-entered the create branch and inserted **another** company. One production account holder
(`johndanielkilpatrick@gmail.com`) accumulated five orphan companies in 33 seconds on 2026-06-29
and never reached the product. Closed by `create_company_for_owner_by_id` (one transaction +
adopt-on-retry). The 9 real orphan companies in prod — all holding zero operator-authored data —
were retired by `migrations/20260818233813_retire_orphan_signup_companies.sql`; the two
`TOCTOU RACE …` fixtures are synthetic and deliberately kept.
| `POST /api/auth/sync-user` | Provision/repair the `users` row from the verified Firebase token | Verifies the Firebase `idToken`, looks up by `auth_id` → `firebase_uid` → `email`. **Sets `users.firebase_uid` from the verified token at row creation** (gated to Firebase-issued tokens) and backfills/repairs legacy rows. This guarantees `firebase_uid` is present for the JWT-`sub`-keyed identity lookup used by `create_company_for_owner` and `join_user_to_company`. **CRIT-3 application-layer hardening (staged 2026-07-07, ops-web `fix/auth-identity-hardening`, pending prod deploy):** the email fallback resolves on the VERIFIED TOKEN email — never the caller-supplied body email; an unverified email-only match against a row already bound to a *different* identity (`auth_id`/`firebase_uid` ≠ this token's sub) is refused with `403` instead of being rewritten or handed back; the 23505 insert-race recovery re-queries by `auth_id` first, then `firebase_uid`, so a Supabase-token race row (whose `firebase_uid` is null) is still recovered. |
| `POST /api/auth/send-verification` | Send the OPS-branded Firebase email-verification message | **Staged 2026-07-07 (CRIT-3 Phase B), pending prod deploy.** Verifies the Firebase `idToken`, no-ops when `email_verified` is already true, generates the verification action link via the Admin SDK (no send), rebuilds the URL through OPS's own `/auth/action?mode=verifyEmail` handler so the branded SendGrid template is used, and sanitizes auth errors to a generic `401`. Best-effort/soft UX — the user is never gated on deliverability. Wires the previously-dormant verification stack so `email_verified` can eventually be trusted by the identity model. |

**Database RPC: `create_company_for_owner` (shared owner-creation path, 2026-06).** One atomic `SECURITY DEFINER` Postgres function used by **both iOS and OPS-Web**, replacing iOS's direct PostgREST company insert and web's bespoke insert (which had diverged: iOS set `role='owner'` + a `user_roles` Owner row; web set only `is_company_admin=true`, leaving owners in inconsistent permission states).

```
create_company_for_owner(
  p_name text,
  p_industries text[] default null,
  p_email text default null,
  p_phone text default null,
  p_address text default null
) returns jsonb  -- { company_id uuid, company_code text, already_existed boolean }
```

- **Caller identity is derived from the JWT inside the RPC** — `auth.jwt()->>'sub'` (Firebase UID) → `users.firebase_uid`. No caller-supplied user id is accepted. Missing `sub` → `NO_JWT`; no matching `users` row (sync-user race) → `NO_USER_ROW` (the client re-runs `sync-user` and retries once).
- **Server-generated company code:** 8 chars from `ABCDEFGHJKLMNPQRSTUVWXYZ23456789` (I/O/0/1 excluded), uniqueness-looped against `companies.company_code` and backstopped by the `idx_companies_company_code` unique index. Legacy codes (e.g. web's old `PREFIX-XXXXXX`, 6-char codes) remain valid forever — validation is lookup-only.
- **Writes (atomic):** inserts `companies` (name, optional industries/contact, `admin_ids=[owner]`, `seated_employee_ids=[owner]`, `account_holder_id`, trial pinned: `subscription_status='trial'`, `subscription_plan='trial'`, `trial_start_date=now()`, `trial_end_date=now()+30d`, `max_seats=10`); updates `users` (`company_id`, `role='owner'`, `is_company_admin=true`, `user_type='company'`); upserts `user_roles` → preset Owner role on conflict `(user_id)`; calls `initialize_company_defaults`.
- **Idempotent:** if the caller already owns a company, returns the existing company + its real stored code with `already_existed=true` (kills client/server code divergence). A concurrency guard serializes per-caller via an advisory lock; a member of another live company is rejected with `ALREADY_IN_COMPANY`.
- **Typed errors (raised as exception tokens, surfaced by the iOS `CreateCompanyError` mapper):** `NO_JWT`, `NO_USER_ROW`, `ALREADY_IN_COMPANY`, `INVALID_NAME`, `OWNER_ROLE_MISSING`, `CODE_GENERATION_EXHAUSTED`.
- Granted to `authenticated`; revoked from `anon`. Called via each platform's Supabase client (`supabase-swift` / `supabase-js`) over the existing Firebase-bridged session, exactly like `join_user_to_company`.

**Database RPC: `create_company_for_owner_by_id` (service-role twin, 2026-08-18).** Reaches the same final state as `create_company_for_owner`, but the owner is named explicitly instead of derived from the JWT — which is what makes it usable from `/api/setup/progress`, a service-role route.

```
create_company_for_owner_by_id(
  p_user_id uuid,
  p_name text,
  p_industries text[] default null,
  p_company_size text default null,
  p_company_age text default null,
  p_weather_dependent boolean default null,
  p_referral_method text default null
) returns jsonb  -- { company_id uuid, company_code text, already_existed boolean }
```

- **Granted to `service_role` ONLY** (`revoke … from public, anon, authenticated`), backed by an in-body `NOT_SERVICE_ROLE` (42501) check. Because the caller names the owner, granting it to `authenticated` would let any signed-in user bootstrap a company onto an arbitrary user id.
- **Writes (one transaction):** `companies` (name, industries, the web-only profile fields `company_size`/`company_age`/`weather_dependent`/`referral_method`, `company_code`, `admin_ids=[owner]`, `seated_employee_ids=[owner]`, `account_holder_id`); the Owner `user_roles` row; `users` (`company_id`, `role='owner'`, `is_company_admin=true`, `user_type='company'`); then `initialize_company_defaults`. Trial fields are pinned by the `initialize_company_trial` trigger, not by the RPC.
- **Adopts rather than duplicates:** when an unlinked, non-deleted company already carries this `account_holder_id`, it is claimed and completed (profile updated, missing join code minted) and `already_existed=true` is returned. This is the property that makes a retry after a partial failure safe.
- **Join-code entropy is `extensions.gen_random_bytes` (pgcrypto CSPRNG), not `random()`** — the code is a bearer credential. Alphabet, length, and retry bound match `create_company_for_owner`; 256 is an exact multiple of 32, so byte→symbol carries no modulo bias.
- Serializes on the **same** advisory-lock key as `create_company_for_owner` (`hashtext('create_company_for_owner')`, `hashtext(user_id)`), so a concurrent web and iOS attempt for one owner cannot interleave.
- **Typed errors:** `NOT_SERVICE_ROLE`, `NO_USER_ROW`, `USER_INACTIVE`, `ALREADY_IN_COMPANY`, `INVALID_NAME`, `OWNER_ROLE_MISSING`, `CODE_GENERATION_EXHAUSTED`.
- **Seating the owner (2026-08-18).** The owner is written to **both** `admin_ids` and `seated_employee_ids`, matching `create_company_for_owner`; the web path previously wrote only `admin_ids`, leaving the roster missing the one person guaranteed to be using the product. Nobody was ever locked out by this — `isUserSeated()` passes on `adminIds` OR `seatedEmployeeIds` — it was a roster/accounting gap. Backfilled for all existing companies; the synthetic `TOCTOU RACE …` fixtures are excluded.
- **Seat counting is DISTINCT PEOPLE, not array length.** Because the owner sits in both arrays, ops-web's `getSubscriptionInfo()` counts `new Set([...seatedEmployeeIds, ...adminIds]).size`. It previously SUMMED the two arrays, so every iOS-created company had been reading one seat over its true usage since seats existed — which nagged solo owners to upgrade and could refuse a seat they were entitled to (`currentSeats` drives `canAddSeat`/`shouldShowUpgrade`/`shouldShowBanner`). The change only ever lowers the count, so it cannot lock anyone out. Cover: `tests/unit/subscription-seat-count.test.ts` (ops-web).
- Applied as `migrations/20260818233110_create_company_for_owner_by_id_service_role.sql`, amended by `migrations/20260819003055_seat_owner_on_company_bootstrap.sql`.

**Database RPC hardening: `join_user_to_company`.** Takes `(p_user_id uuid, p_company_id uuid, p_company_code text default null)`. For authenticated (non-service-role) callers, identity is matched by JWT `email`/`sub` against `users.email`/`firebase_uid`/`auth_id` (never `auth.uid()`, since the Firebase `sub` is not a UUID); `p_company_code` proof must match the locked `companies.company_code` when supplied. Service-role callers may still perform controlled server-side joins. **2026-06 amendment (shared with the iOS rebuild):**
- Sets `user_type='employee'` and `is_company_admin=false` on the joining user **atomically inside the RPC** (removing the iOS client's former fire-and-forget post-RPC writes), with an **owner/admin non-demotion guard** — a re-join by the company's owner/admin never overwrites their pinned `user_type='company'`/`is_company_admin=true`.
- **Fans out the per-admin "team member joined" rail notifications server-side** via `create_notification_if_new` (type `role_needed`), mirroring the copy/dedupe scheme the web route used; the web route's own fan-out was removed so web joins don't double-notify. Push delivery (OneSignal) stays client/route-side.
- **Return shape (13 keys):** `success`, `user_id`, `company_id`, `role_id`, `role_name`, `seat_granted`, `invitation_found`, `admin_ids`, `invited_by`, `new_member_id`, `new_member_name`, `new_member_first_name`, `company_name`.

**Client rules:**

- Partial web setup is resume-safe. `/setup` writes each step before advancing; if the network drops, the UI stays on the current step and keeps the draft local instead of skipping ahead.
- Web setup accepts a sanitized `redirect`/`continue` destination. Production only permits same-origin or explicit OPS-owned destinations; development-only localhost allowances are disabled when `NODE_ENV` or `NEXT_PUBLIC_VERCEL_ENV` is production.
- iOS must call `/api/onboarding/complete` and wait for the server ACK before setting local onboarding completion. A cached `companyId` is not proof of completion. **Offline tolerance (iOS rebuild):** when the ACK fails or times out, iOS queues it locally (`onboarding_completion_pending`) and admits the user; the SyncEngine drains the queued ACK until the server confirms (`shouldShowOnboarding` treats pending as complete).
- iOS and web both pass company-code proof when joining an existing company. Company ID alone is not enough for user-initiated joins.
- Login/account-type handoffs preserve the safe continuation URL so ops-site, OPS-Web auth, and onboarding can interoperate without dropping the intended destination.

---

## Supabase Configuration

**Source**: `OPS/Network/Supabase/SupabaseConfig.swift`

```swift
enum SupabaseConfig {
    static let url = URL(string: "https://ijeekuhbatykdomumfjx.supabase.co")!
    static let anonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9..."
}
```

- The anon key is safe to embed in the mobile client; data is protected by Row-Level Security policies
- RLS policies enforce company-scoped isolation using the JWT `app_metadata.company_id`
- The `private.get_user_company_id()` Postgres function extracts the company ID from the authenticated user's JWT

### SupabaseService

**Source**: `OPS/Network/Supabase/SupabaseService.swift`

Singleton `@MainActor` class that owns the `SupabaseClient` instance and manages auth state.

**Published State**:
- `isAuthenticated: Bool`
- `currentUserId: String?`

**Key Methods**:
| Method | Description |
|--------|-------------|
| `restoreSession()` | Restores a previous Supabase session from disk on init |
| `signInWithGoogle(idToken:)` | Authenticates with Supabase using a Google ID token |
| `signInWithApple(identityToken:)` | Authenticates with Supabase using an Apple identity token |
| `signOut()` | Signs out of Supabase, clears auth state |

**Error Types**:
- `ServiceError.notAuthenticated` -- no active session
- `ServiceError.networkError(Error)` -- wrapped network failure

### AppConfiguration

**Source**: `OPS/Utilities/AppConfiguration.swift`

Central configuration for the app. Key values:

| Setting | Value |
|---------|-------|
| `apiBaseURL` | `https://app.opsapp.co` |
| `Sync.syncOnLaunch` | `true` |
| `Sync.backgroundSyncInterval` | 15 minutes |
| `Sync.maxBatchSize` | 50 |
| `Sync.minimumSyncInterval` | 5 minutes |
| `Sync.jobHistoryDays` | 30 |
| `Sync.jobFutureDays` | 60 |

### Lead summary activity refresh (2026-08-07, staged)

`POST /api/opportunities/[id]/summary-refresh` is the authenticated iOS-to-OPS-Web handoff after a human Lead Details activity has already been saved. Source: `ops-web/src/app/api/opportunities/[id]/summary-refresh/route.ts` (code commit `d4c04e0d`).

The route requires a Firebase bearer token, validates the opportunity UUID, and calls `authorize_lead_summary_refresh` through the actor's access-token client. That RPC derives actor/company identity and requires live edit authority. Only then does the route use the service-role client to call `refreshLeadSummariesForOpportunities` for exactly one opportunity. No request body may supply actor or company authority.

Responses: `200` when the targeted refresh writes or legitimately completes without a write; `202` when Phase C is disabled; `401` for missing/invalid authentication; `400` for malformed opportunity ids; `403`/`404` for denied/missing opportunities; `503` when generation is deferred or unavailable. The iOS activity save is authoritative and never rolls back on a refresh failure; the recurring server refresh remains the recovery boundary.

**Release state (updated 2026-08-17):** `20260807123500_authorize_lead_summary_refresh.sql` is applied in production and the OPS-Web route ships with the bugfix wave of 2026-08-17 (branch `fix/ios-bug-batch-server-20260807` merged via `release/web-bugfix-wave-20260817`). The iOS caller remains gated on its App Store release. Each successful human lead-activity save can add one existing Phase C model invocation, with its normal token cost; no new provider or subscription is introduced.

### Durable Phase C lead intelligence drain (production 2026-08-21)

The existing `GET /api/cron/email-sync` route now drains at most two
`opportunity_phase_c_work` rows under the existing mailbox-sync execution
boundary after ingestion and pending lead-scan recovery. Source:
`ops-web/src/lib/api/services/phase-c-lead-intelligence-work-service.ts`,
`phase-c-lead-intelligence-work-runtime.ts`, and OPS-Web commit `8c86394e`.

The response includes `leadIntelligence` counts for claimed, completed,
superseded, retrying, failed, component-applied/reviewed/skipped, plus bounded
errors, and `leadIntelligenceError` for a top-level worker failure. Retained or
failed work contributes to the route's existing HTTP 503 health signal; it is
not reduced to a log-only warning. No new route, scheduler, provider, or
subscription is introduced.

The production migration exposes service-role-only RPCs:

| RPC | Contract |
|---|---|
| `claim_opportunity_phase_c_work` | Leases due high-water rows with bounded batch/lease values and skip-locked concurrency. |
| `acknowledge_opportunity_phase_c_component` | Acknowledges one committed component only when company, opportunity, leased worker, and exact required event still match. |
| `fail_opportunity_phase_c_work` | Persists component errors, releases the lease, and schedules bounded retry without clearing the marker. |
| `record_opportunity_lifecycle_decision` | Creates or replays one immutable proposed/review decision receipt; conflicting evidence is rejected. |
| `settle_opportunity_lifecycle_decision` | Settles only the recorded receipt after the guarded effect returns. |
| `apply_phase_c_opportunity_stage_decision` | Applies an allowed active-stage advance under stage, assignment-version, decision, and manual-evidence-boundary guards. |
| `record_phase_c_bilateral_event_handoff` | Persists one immutable ready/review envelope for P1-17; it creates no OPS or provider calendar event. |

Component order is summary, lifecycle, deterministic commercial outcome, then
bilateral-event handoff. Components settle independently: a model refusal or
outage keeps summary/lifecycle due but does not block the guarded commercial or
event evaluator from recording its result. Already acknowledged components do
not replay on retry. Phase C disabled is an explicit durable skip for all four
components.

**Release state (2026-08-21):** the migration and its two foreign-key index
follow-ups are applied and verified in production. OPS-Web commit `6b69551a` is
deployed READY at `https://app.opsapp.co`; the deployment returned HTTP 200 and
no runtime errors in the release window. Runtime cost remains the existing
Phase C model usage plus retry invocations for unresolved work; there is no new
fixed vendor cost. Exact incremental model spend depends on message volume and
token count.

### Phase C bilateral appointment consumption (production 2026-08-21)

P1-17 adds a bounded consumer after the P1-16 lead-intelligence drain in the
existing email-sync cron. The server claims only due `ready` or already
`consumed` handoffs through service-role RPCs. It rechecks cancellation,
company/opportunity identity, active assignee identity, operator and customer
attendees, `calendar.create`, timezone, title, location, future time, duration,
conflicts, and the handoff lease before an effect. Any absent or ambiguous
authority settles the handoff to durable `review`; it never books silently.

`consume_phase_c_bilateral_event_handoff` is the one atomic booking boundary.
It inserts exactly one booked `site_visits` row keyed by the handoff, records
the scheduled activity, nudges only `new_lead` to `qualifying`, and marks the
handoff consumed in the same transaction. Retries read the same visit back;
notification acknowledgement and retry/failure state are fenced by the same
lease owner. Provider synchronization remains downstream of canonical
`site_visits`: the existing Google queue trigger/drain handles a connected
Google calendar, while the iOS EventKit mirror presents the canonical title
and location to any writable Apple, Google, or Microsoft calendar configured
on that device. Arbitrary inbound provider events are not imported into OPS.

Migration `20260820222016_phase_c_bilateral_event_consumption.sql` is applied
in production under ledger name
`phase_c_bilateral_event_consumption_20260820222016` (version
`20260821202009`). The worker is customer-live in OPS-Web production commit
`6b69551a`. Release readback confirmed zero existing handoff rows and zero
handoff-linked visits, so deployment created no appointment or provider event.
The iOS bindings are merged and pushed on `main` commit `677850ee`; Apple/device
distribution remains Jackson's separate signed-build step.

---

## Supabase Repositories

**Source**: `OPS/Network/Supabase/Repositories/`

All 15 repository classes follow the same pattern: each takes a `companyId` on init (except `CompanyRepository` and `NotificationRepository`), holds a reference to `SupabaseService.shared.client`, and provides typed CRUD methods against specific Supabase tables.

### 1. ProjectRepository

**Table**: `projects`
**Init**: `ProjectRepository(companyId:)`
**Audit Columns** (2026-05-10, bug 9d5c2535): `created_at` (TIMESTAMPTZ, Supabase default `now()`) and `created_by` (UUID FK → `auth.users.id`, populated by iOS on insert, immutable). Both are round-tripped through `SupabaseProjectDTO`. The combined index `idx_projects_created_by_created_at (created_by, created_at DESC) WHERE deleted_at IS NULL` powers the "start from recent" suggestions strip on the project form.
**Vinyl Order Marker Columns** (2026-05-21; extended 2026-07-16): `vinyl_order_status` (`not_ordered` / `ordered`, default `not_ordered`), `vinyl_ordered_at` (TIMESTAMPTZ), `vinyl_ordered_by` (UUID FK → `public.users.id`, retargeted 2026-07-04), plus `vinyl_color` (TEXT NULL) and `vinyl_po` (TEXT NULL) — the ordered color + supplier PO record written by the VINYL ORDERS board and every MARK ORDERED path (migration `add_projects_vinyl_color_po`). All five are marker-only project fields for Deck Builder companies, round-tripped through `SupabaseProjectDTO`, written in one atomic `updateProjectFields` payload, and nulled together by CLEAR ORDERED; they do not create catalog orders, inventory deductions, or task materials.
**Primary Project Contact (production schema live 2026-08-21; iOS distribution pending):**
`primary_sub_client_id UUID NULL REFERENCES sub_clients(id) ON DELETE SET NULL`
selects one explicit active contact from the project's current client. Generic
`updateFields` writes it as a UUID string or JSON null in the same durable
project outbox used by other project edits. The assignment-specific iOS writer
commits the local choice and outbox row atomically, and the cross-entity queue
barrier holds that project update behind any unresolved local create for the
selected sub-client. The existing `projects.edit` row policy remains the write
authority. A private validation trigger rejects a
deleted, cross-client, or cross-company selection (`23514`), while compatibility
and cleanup triggers clear a selection when the project client changes through
an older caller or the chosen contact is deleted/re-parented. Migration
`20260821185843_project_primary_sub_client.sql` is applied and verified, so the
database-first release gate is satisfied. The iOS writer is merged and pushed
on `main` commit `677850ee`; it is not Apple-distributed by this rollout.

| Method | Signature | Description |
|--------|-----------|-------------|
| `fetchAll` | `(since: Date?) -> [SupabaseProjectDTO]` | Fetch all company projects, optionally since a date |
| `fetchOne` | `(_ id: String) -> SupabaseProjectDTO` | Fetch single project by ID |
| `create` | `(_ dto: SupabaseProjectDTO) -> SupabaseProjectDTO` | Insert, returns created record. DTO must include `created_at` (ISO8601) and `created_by` (current user id). |
| `upsert` | `(_ dto: SupabaseProjectDTO)` | Upsert (insert or update on conflict). `created_at` and `created_by` are immutable after first insert — server preserves originals on update. |
| `updateStatus` | `(_ projectId: String, status: String)` | Update status + updated_at |
| `updateNotes` | `(_ projectId: String, notes: String)` | Update notes + updated_at |
| `updateDates` | `(_ projectId: String, startDate: Date?, endDate: Date?)` | Update start/end dates |
| `updateAddress` | `(_ projectId: String, address: String)` | Update address |
| `createProjectTableAssignmentTask` | `(_ projectId: String, title: String, expectedUpdatedAt: String) -> ProjectTeamAssignmentRPCResult` | Create a task-backed assignment row for project-level team edits when no active tasks exist |
| `assignProjectTeamMember` | `(_ projectId: String, userId: String, taskIds: [String], expectedUpdatedAt: String) -> ProjectTeamAssignmentRPCResult` | Add a user to task-backed project assignment via RPC/conflict token |
| `removeProjectTeamMember` | `(_ projectId: String, userId: String, taskIds: [String]?, expectedUpdatedAt: String) -> ProjectTeamAssignmentRPCResult` | Remove a user from task-backed project assignment via RPC/conflict token |
| `updateFields` | `(_ projectId: String, fields: [String: AnyJSON])` | Generic field update |
| `softDelete` | `(_ projectId: String)` | Set deleted_at + updated_at |

### 2. TaskRepository

**Table**: `project_tasks`
**Init**: `TaskRepository(companyId:)`
**Column Notes**: `task_notes` (not `notes`), `custom_title` (not `title`), `task_color` (not `color`). Scheduling dates (`start_date`, `end_date`, `duration`) and manual schedule ownership (`schedule_locked`) are stored directly on `project_tasks`.

| Method | Signature | Description |
|--------|-----------|-------------|
| `fetchAll` | `(since: Date?) -> [SupabaseProjectTaskDTO]` | All company tasks, ordered by display_order |
| `fetchForProject` | `(_ projectId: String) -> [SupabaseProjectTaskDTO]` | Tasks for a specific project |
| `fetchOne` | `(_ id: String) -> SupabaseProjectTaskDTO` | Single task by ID |
| `create` | `(_ dto: SupabaseProjectTaskDTO) -> SupabaseProjectTaskDTO` | Insert, returns created record |
| `upsert` | `(_ dto: SupabaseProjectTaskDTO)` | Upsert |
| `updateStatus` | `(_ taskId: String, status: String)` | Update status |
| `updateNotes` | `(_ taskId: String, notes: String)` | Updates `task_notes` column |
| `updateFields` | `(_ taskId: String, fields: [String: AnyJSON])` | Generic field update |
| `updateTeamMembers` | `(_ taskId: String, memberIds: [String])` | Replace team_member_ids array |
| `softDelete` | `(_ taskId: String)` | Soft delete |

### 3. UserRepository

**Table**: `users`
**Init**: `UserRepository(companyId:)`

| Method | Signature | Description |
|--------|-----------|-------------|
| `fetchAll` | `(since: Date?) -> [SupabaseUserDTO]` | All company users |
| `fetchOne` | `(_ id: String) -> SupabaseUserDTO` | Single user by ID |
| `fetchByEmail` | `(_ email: String) -> SupabaseUserDTO?` | Lookup user by email (limit 1) |
| `upsert` | `(_ dto: SupabaseUserDTO)` | Upsert |
| `updateUser` | `(userId:, firstName:, lastName:, phone:)` | Update user profile fields |
| `updateProfileImageUrl` | `(userId:, url: String)` | Update profile_image_url |
| `updateFields` | `(userId:, fields: [String: AnyJSON])` | Generic field update |
| `softDelete` | `(_ id: String)` | Soft delete |

### 4. ClientRepository

**Tables**: `clients`, `sub_clients`
**Init**: `ClientRepository(companyId:)`
**Column Note**: Phone is stored as `phone_number` in both tables.

| Method | Signature | Description |
|--------|-----------|-------------|
| `fetchAll` | `(since: Date?) -> [SupabaseClientDTO]` | All company clients |
| `fetchOne` | `(_ id: String) -> SupabaseClientDTO` | Single client by ID |
| `create` | `(_ dto: SupabaseClientDTO) -> SupabaseClientDTO` | Insert, returns created |
| `upsert` | `(_ dto: SupabaseClientDTO)` | Upsert |
| `updateContact` | `(clientId:, name:, email:, phone:, address:)` | Update client contact info |
| `softDelete` | `(_ id: String)` | Soft delete |
| `fetchSubClients` | `(for clientId: String) -> [SupabaseSubClientDTO]` | Sub-clients for a client |
| `createSubClient` | `(clientId:, name:, title:, email:, phone:, address:) -> SupabaseSubClientDTO` | Create sub-client |
| `deleteSubClient` | `(_ id: String)` | Hard delete sub-client |

### 5. CompanyRepository

**Table**: `companies`
**Init**: `CompanyRepository()` (no companyId -- the company IS the entity being fetched)

| Method | Signature | Description |
|--------|-----------|-------------|
| `fetch` | `(companyId: String) -> SupabaseCompanyDTO` | Fetch company by ID |
| `fetchByCode` | `(_ code: String) -> SupabaseCompanyDTO?` | Lookup by company_code (case-insensitive, for join flow) |
| `insert` | `(_ payload: NewCompanyPayload) -> SupabaseCompanyDTO` | Create new company |
| `update` | `(companyId:, updates: [String: String])` | Freeform string field updates |
| `updateSeatedEmployees` | `(companyId:, userIds: [String])` | Replace seated_employee_ids array |

Also provides `NewCompanyPayload` struct and `generateCompanyCode()` helper (8-char alphanumeric, no ambiguous chars like 0/O/1/I). **Note (2026-06):** owner company creation now routes through the shared `create_company_for_owner` RPC (server-generated code), not this client-side `insert` + `generateCompanyCode` path; `fetchByCode` remains the crew-join lookup.

### 6. TaskTypeRepository

**Table**: `task_types`
**Init**: `TaskTypeRepository(companyId:)`
**Column Note**: Display name column is `display` (not `name`).

| Method | Signature | Description |
|--------|-----------|-------------|
| `fetchAll` | `(since: Date?) -> [SupabaseTaskTypeDTO]` | All task types, ordered by display_order |
| `fetchOne` | `(_ id: String) -> SupabaseTaskTypeDTO` | Single task type |
| `create` | `(_ dto: SupabaseTaskTypeDTO) -> SupabaseTaskTypeDTO` | Insert, returns created |
| `upsert` | `(_ dto: SupabaseTaskTypeDTO)` | Upsert |
| `softDelete` | `(_ id: String)` | Soft delete |

### 7. InvoiceRepository

**Tables**: `invoices`, `invoice_line_items`, `payments`
**Init**: `InvoiceRepository(companyId:)`

| Method | Signature | Description |
|--------|-----------|-------------|
| `fetchAll` | `() -> [InvoiceDTO]` | All invoices with nested line_items and payments |
| `fetchOne` | `(_ invoiceId: String) -> InvoiceDTO` | Single invoice with children |
| `recordPayment` | `(_ dto: CreatePaymentDTO) -> PaymentDTO` | Insert payment (DB trigger maintains balance) |
| `updateStatus` | `(_ invoiceId: String, status: InvoiceStatus)` | Update invoice status |
| `voidInvoice` | `(_ invoiceId: String)` | Set status to void |

**Important**: Never update `invoice.amount_paid` or `invoice.balance_due` manually -- a DB trigger maintains these automatically when payments are inserted.

### 8. EstimateRepository

**Tables**: `estimates`, `line_items`
**Init**: `EstimateRepository(companyId:)`

| Method | Signature | Description |
|--------|-----------|-------------|
| `fetchAll` | `() -> [EstimateDTO]` | All estimates with nested line_items |
| `fetchOne` | `(_ estimateId: String) -> EstimateDTO` | Single estimate with line_items |
| `updateTitle` | `(_ estimateId: String, title: String)` | Update estimate title |
| `create` | `(_ dto: CreateEstimateDTO) -> EstimateDTO` | Create estimate |
| `addLineItem` | `(_ dto: CreateLineItemDTO) -> EstimateLineItemDTO` | Add line item |
| `updateLineItem` | `(_ id: String, fields: UpdateLineItemDTO) -> EstimateLineItemDTO` | Update line item |
| `deleteLineItem` | `(_ id: String)` | Hard delete line item |
| `updateStatus` | `(_ estimateId: String, status: EstimateStatus) -> EstimateDTO` | Update status |
| `convertToInvoice` | `(estimateId: String) -> InvoiceDTO` | Atomic RPC `convert_estimate_to_invoice` |

**Important**: Estimate-to-invoice conversion uses a Postgres RPC function -- never do this manually.

### 9. OpportunityRepository

**Tables**: `opportunities`, `activities`, `follow_ups`
**Init**: `OpportunityRepository(companyId:)`
**Priority contract**: live Supabase accepts only `low`, `medium`, or `high` for `opportunities.priority`. Client-created lead autocreation defaults to `medium`.

| Method | Signature | Description |
|--------|-----------|-------------|
| `fetchAll` | `() -> [OpportunityDTO]` | All pipeline opportunities |
| `fetchOne` | `(_ opportunityId: String) -> OpportunityDTO` | Single opportunity |
| `fetchActivities` | `(for opportunityId: String) -> [ActivityDTO]` | Activity log for an opportunity |
| `fetchFollowUps` | `(for opportunityId: String) -> [FollowUpDTO]` | Follow-up reminders |
| `create` | `(_ dto: CreateOpportunityDTO) -> OpportunityDTO` | Create opportunity |
| `logActivity` | `(_ dto: CreateActivityDTO) -> ActivityDTO` | Log an activity (call, email, note) |
| `createFollowUp` | `(_ dto: CreateFollowUpDTO) -> FollowUpDTO` | Create follow-up reminder |
| `advanceStage` | `(opportunityId:, to stage:, lossReason:) -> OpportunityDTO` | Move deal to new stage |
| `update` | `(_ opportunityId:, fields: UpdateOpportunityDTO) -> OpportunityDTO` | Update fields |
| `delete` | `(_ opportunityId: String)` | Hard delete |

### 10. ProductRepository

**Table**: `products`
**Init**: `ProductRepository(companyId:)`

| Method | Signature | Description |
|--------|-----------|-------------|
| `fetchAll` | `() -> [ProductDTO]` | All active products, ordered by name |
| `create` | `(_ dto: CreateProductDTO) -> ProductDTO` | Create product |
| `update` | `(_ id: String, fields: UpdateProductDTO) -> ProductDTO` | Update product |
| `deactivate` | `(_ id: String)` | Set is_active = false |

### 11. AccountingRepository

**Table**: `invoices` (read-only queries)
**Init**: `AccountingRepository(companyId:)`

| Method | Signature | Description |
|--------|-----------|-------------|
| `fetchAllInvoices` | `() -> [InvoiceDTO]` | All invoices with line_items and payments for aging/status dashboard |

### 12. InventoryRepository

**Tables**: `inventory_items`, `inventory_units`, `inventory_tags`, `inventory_item_tags`, `inventory_snapshots`, `inventory_snapshot_items`
**Init**: `InventoryRepository(companyId:)`

| Method | Signature | Description |
|--------|-----------|-------------|
| `fetchAllItems` | `() -> [InventoryItemReadDTO]` | All non-deleted items |
| `createItem` | `(_ dto: CreateInventoryItemDTO) -> InventoryItemReadDTO` | Create item |
| `updateItem` | `(_ id:, fields: UpdateInventoryItemDTO) -> InventoryItemReadDTO` | Update item |
| `softDeleteItem` | `(_ id: String)` | Soft delete item |
| `fetchAllUnits` | `() -> [InventoryUnitReadDTO]` | All non-deleted units |
| `createUnit` | `(_ dto: CreateInventoryUnitDTO) -> InventoryUnitReadDTO` | Create unit |
| `softDeleteUnit` | `(_ id: String)` | Soft delete unit |
| `createDefaultUnits` | `() -> [InventoryUnitReadDTO]` | Create 12 default units (ea, box, ft, m, kg, lb, gal, L, roll, sheet, bag, pallet) |
| `fetchAllTags` | `() -> [InventoryTagReadDTO]` | All non-deleted tags |
| `createTag` | `(_ dto: CreateInventoryTagDTO) -> InventoryTagReadDTO` | Create tag |
| `updateTag` | `(_ id:, fields: UpdateInventoryTagDTO) -> InventoryTagReadDTO` | Update tag |
| `softDeleteTag` | `(_ id: String)` | Soft delete tag |
| `fetchAllItemTags` | `() -> [InventoryItemTagReadDTO]` | All item-tag junction rows |
| `setItemTags` | `(itemId:, tagIds: [String])` | Replace item's tags (delete all, insert new) |
| `fetchSnapshots` | `() -> [InventorySnapshotReadDTO]` | All snapshots |
| `fetchSnapshotItems` | `(snapshotId:) -> [InventorySnapshotItemReadDTO]` | Items in a snapshot |
| `createFullSnapshot` | `(userId:, isAutomatic:, items:, notes:) -> InventorySnapshotReadDTO` | Create snapshot header + all snapshot items |

### 13. ProjectNoteRepository

**Table**: `project_notes`
**Init**: `ProjectNoteRepository(companyId:)`

| Method | Signature | Description |
|--------|-----------|-------------|
| `fetchForProject` | `(_ projectId: String) -> [ProjectNoteDTO]` | Notes for a project (non-deleted, newest first) |
| `create` | `(_ dto: CreateProjectNoteDTO) -> ProjectNoteDTO` | Create note |
| `softDelete` | `(_ noteId: String)` | Soft delete |

### 14. PhotoAnnotationRepository

**Table**: `project_photo_annotations`
**Init**: `PhotoAnnotationRepository(companyId:)`

| Method | Signature | Description |
|--------|-----------|-------------|
| `fetchAll` | `(since: Date?) -> [PhotoAnnotationDTO]` | Sync pull via the `get_photo_annotations_since` SECURITY DEFINER RPC (lets tombstones flow to local SwiftData). Used by `InboundProcessor`/`DataActor` delta + full sync. |
| `fetchForProject` | `(_ projectId: String) -> [PhotoAnnotationDTO]` | All annotations for a project |
| `fetchForPhoto` | `(projectId:, photoURL:) -> PhotoAnnotationDTO?` | Single annotation for a specific photo |
| `upsert` | `(_ dto: UpsertPhotoAnnotationDTO) -> PhotoAnnotationDTO` | Upsert annotation |
| `create` | `(_ dto: UpsertPhotoAnnotationDTO) -> PhotoAnnotationDTO` | Insert annotation |
| `updateAnnotation` | `(_ annotationId:, annotationUrl:, note:)` | Legacy single-overlay update — now only the offline-sweep fallback for pre-collab queued rows |
| `updateNote` | `(_ annotationId:, note:)` | Note-only update (the shared scalar); `annotation_url` is owned by `upsertLayer` |
| `upsertLayer` | `(annotationId:, layer: MarkupLayer, changeEvent:, beforeSnapshotURL:, afterSnapshotURL:) -> PhotoAnnotationDTO` | **Collaborative markup write path.** Merges the caller's OWN layer into the shared row via the `upsert_markup_layer` RPC and returns the fully-merged row. Layer fields are passed as hand-built `AnyJSON` (no Bool/Int ambiguity); camelCase jsonb keys; ISO dates |
| `softDelete` | `(_ annotationId: String)` | Soft delete |

> **Sync contract — `updated_at` must never be NULL (fixed 2026-06-04).** Delta sync pulls filter on `updated_at` (`get_photo_annotations_since` uses `updated_at >= p_since`; `project_notes` uses `.gte("updated_at", since)`). A freshly inserted row with `updated_at = NULL` fails `NULL >= p_since` and is **silently excluded from every delta sync** — the author sees it (composited locally) but it never reaches other devices ("local only"). Root cause: `project_photo_annotations.updated_at` and `project_notes.updated_at` lacked a DEFAULT and update trigger. Fix migration `fix_photo_annotation_and_note_updated_at_propagation`: both columns now `DEFAULT now()` + a `BEFORE UPDATE … update_timestamp()` trigger (matching `projects`/`expenses`), existing NULL rows backfilled to `created_at`, and `get_photo_annotations_since` hardened to `COALESCE(updated_at, created_at) >= p_since`. **`rendered_photo_url` — resolved 2026-06-04.** The `rendered_photo_url` column referenced by the DTOs (and its sibling `project_photos.rendered_url`) was authored in `20260519000000_dimensioned_photo_rendered_deliverable.sql` (committed to ops-web 2026-05-19) but **was never applied to production**. Because the dimensioned-capture write path (`DimensionedPhotoSyncManager`) sends both columns as **non-optional** strings — unlike the PencilKit DTOs, where nil optionals are omitted on encode — every dimensioned-capture insert would have failed with PostgREST `PGRST204` ("column not found"). The feature was flag-gated OFF (`feature.measurement.dimensioned_capture`) the entire time, so no production rows were lost (0 dimensioned annotations / 0 `source = 'measurement'` photos at time of fix). Applied to prod 2026-06-04 (ledger version `20260519000000`, name `dimensioned_photo_rendered_deliverable`); both `project_photo_annotations.rendered_photo_url` and `project_photos.rendered_url` are now present (`text`, nullable, additive — safe under the iOS additive-sync constraint).

> **`upsert_markup_layer` RPC — collaborative markup write path (2026-06-23).** `public.upsert_markup_layer(p_annotation_id uuid, p_layer jsonb, p_change_event jsonb, p_before_url text, p_after_url text) RETURNS project_photo_annotations`, SECURITY DEFINER, granted to `anon, authenticated, service_role`. Merges the caller's layer into `layers` server-side by `layerId` (jsonb rebuild) and appends the change event ATOMICALLY — **never** a wholesale `.update(layers).eq(id)`, which is last-writer-wins and would drop a peer's just-landed layer. Identity resolves via the established `private.get_current_user_id()` / `private.get_user_company_id()` Firebase-bridge helpers (**never `auth.uid()`**). **Security invariant:** the RPC enforces `p_layer.layerId == caller's users.id`, so a client can only ever write its own layer — a spoofed peer layerId is rejected (`42501`). It re-derives `annotation_url` from the newest active overlay, and soft-deletes the whole row ONLY when every layer is cleared AND `dimensions IS NULL`. **Legacy seed** (migration `upsert_markup_layer_legacy_seed`): when the first layer lands on a pre-collab row (`annotation_url` set, `layers` empty), the existing overlay is seeded as a layer owned by the row's original `author_id` before merging — so a second author's edit can't drop the legacy author's marks. `get_photo_annotations_since` is `RETURNS SETOF … select *`, so the new columns auto-surface on the existing delta/full pull with no RPC change. Verified via rolled-back two-author + author-scoped-clear + spoof-rejection + legacy-seed tests on prod.

> **Photo-annotation soft-delete unblocked + durable write path (2026-07-04, bugs 452bab04 / 0415504f).** Soft-deleting an annotation was structurally impossible for EVERY client from 2026-05-12. The SELECT policy `Users can read company annotations` carried `deleted_at IS NULL`, and Postgres enforces SELECT policies as WITH CHECK against the NEW row of any UPDATE that reads the table (the `WHERE id = …` alone requires SELECT), so every `deleted_at` write raised `42501 new row violates row-level security policy` — regardless of identity or company. Ordinary saves passed (they leave `deleted_at` NULL), which is why only clears/soft-deletes failed; the original "firebase_uid self-heal gap" hypothesis was disproven by live reproduction (the reporting user resolves fine and note-only updates return `rows=1`). **Fix migration `photo_annotations_tombstone_writes`:** the SELECT policy drops the `deleted_at IS NULL` clause and keeps company scoping only. Tombstones are same-company rows (no cross-tenant leak) and every reader already filters `deleted_at` explicitly (`PhotoAnnotationRepository.fetchForProject/fetchForPhoto` use `.is("deleted_at", nil)`; delta pulls use `get_photo_annotations_since`, which returns tombstones by design). Unblocks every already-installed phone with **no App Store release**; realtime UPDATE events for tombstoned rows now also reach same-company subscribers, so removals propagate live. **There is deliberately NO DELETE policy** — client hard-delete stays impossible; `deleted_at` tombstones are the only removal mechanism. **Durable write path — `soft_delete_photo_annotation(p_annotation_id uuid) RETURNS uuid`** (migration `soft_delete_photo_annotation_rpc`), SECURITY DEFINER, granted `anon, authenticated, service_role`; identity via `private.get_user_company_id()` / `private.get_current_user_id()` (**never `auth.uid()`**), company-scoped, idempotent (a retry after a half-acknowledged success keeps the original tombstone time), raises `42501` / `P0002` on unresolved-identity / not-found. `PhotoAnnotationRepository.softDelete` calls it first and falls back to the direct UPDATE on `PGRST202`, so app + migration ship in any order; both paths carry zero-row detection so an RLS-filtered no-op can never report success. iOS shares one inbound-merge rule (`PhotoAnnotationMergePolicy.shouldPreserveLocalTombstone`) across `InboundProcessor`/`DataActor`/`RealtimeProcessor` so a not-yet-synced local tombstone survives a live-row echo, and parks a row after 3 permanent rejections (one retry/launch) so the sweep stops re-filing dead writes. Verified live 2026-07-04 via rolled-back reproduction (pre-fix `42501` → post-fix `rows=1` for the reporting user) and by landing the reported row `e975c1fb` (`deleted_at` set after ~13 months stuck). **Auth companion — `heal_user_identity() RETURNS uuid`** (migration `heal_user_identity_rpc`, SECURITY DEFINER, same grants): links an unlinked `users` row by the Firebase-signed VERIFIED email — only fills NULL identities, requires `email_verified`, never re-keys a linked account — closing the email/password `firebase_uid` gap (~32/79 active users) that otherwise blocks those users' own writes. `AuthManager` calls it when the direct backfill's read-back fails.

### 15. NotificationRepository

**Table**: `notifications`
**Init**: `NotificationRepository()` (no companyId -- queries filter by userId)

| Method | Signature | Description |
|--------|-----------|-------------|
| `fetchUnreadCount` | `(userId: String) -> Int` | Server-side count (no row transfer, uses `head: true, count: .exact`) |
| `fetchRecent` | `(userId:, limit: Int) -> [NotificationDTO]` | Recent notifications (default 50) |
| `markAsRead` | `(_ notificationId: String)` | Mark single notification as read |
| `markAllAsRead` | `(userId: String)` | Mark all unread notifications as read for a user |

**Creation (2026-08-17):** all iOS rail-row creation goes through the repository's "Narrow creation RPCs" + "Legacy call-site RPCs" extensions — one typed method per RPC of § "iOS notification-surface RPCs" and its legacy call-site wave (plus `syncReviewStack` for the review stacks). The legacy `createNotification(_:)` direct INSERT fails `42501` for app roles under the 2026-07-15 hardening; since the 2026-08-17 legacy call-site wave it has zero production call sites and survives only as a documented dead shape.

---

## SyncEngine (Offline-First Orchestrator)

**Source**: `OPS/Network/Sync/SyncEngine.swift`
**Added**: March 8, 2026
**Purpose**: Central coordinator for the offline-first sync system. Replaces the monolithic SupabaseSyncManager as the primary sync orchestrator.

### Architecture

`SyncEngine` is a `@MainActor @Observable` class that delegates work to four specialized processors:

```
SyncEngine (coordinator)
    |-- OutboundProcessor   (push local changes to server)
    |-- InboundProcessor    (pull server changes to local)
    |-- RealtimeProcessor   (WebSocket subscriptions)
    |-- PhotoProcessor      (image upload queue)
```

All mutations flow through `SyncEngine.recordOperation()`, which creates a `SyncOperation` SwiftData model. The processors handle the actual network I/O. ConnectivityManager gates all network attempts.

### Published State

| Property | Type | Description |
|----------|------|-------------|
| `syncInProgress` | `Bool` | Guard against concurrent syncs |
| `lastSyncDate` | `Date?` | Timestamp of last completed sync |
| `pendingOperationCount` | `Int` | Number of unsynced local changes |
| `isConnected` | `Bool` | Delegates to ConnectivityManager |

### Recording Operations

Every local mutation (create, update, delete) calls:

```swift
func recordOperation(
    entityType: String,
    entityId: String,
    operationType: String,       // "create", "update", "delete"
    changedFields: [String],
    previousValues: [String: Any]?,
    priority: Int = 5,
    dependsOnId: String? = nil
)
```

This creates a `SyncOperation` SwiftData model with:
- `entityType` / `entityId` -- what entity
- `operationType` -- "create", "update", "delete"
- `payload` (JSON `Data`) -- serialized entity data
- `changedFields` -- list of changed field names
- `previousValues` -- snapshot of previous values (for conflict detection)
- `status` -- "pending", "inProgress", "completed", "failed"
- `retryCount` -- number of failed attempts
- `lastError` -- error message from last failure
- `priority` -- processing priority (lower = higher priority)
- `dependsOnId` -- ID of another SyncOperation that must complete first

After recording, if the device is connected, `OutboundProcessor.processPendingOperations()` is triggered immediately.

### Sync Triggers

| Trigger | Method | Behavior |
|---------|--------|----------|
| App launch | `triggerSync()` | Full inbound pull + push pending |
| Network restored | `triggerSync()` | Full inbound pull + push pending |
| User mutation | `recordOperation()` | Enqueue + immediate push attempt |
| Realtime reconnect | `deltaSyncSince(disconnectedAt:)` | Incremental pull since disconnect |
| Background refresh | `pushPending()` | Push only, no pull |

**Delta cursor safety (2026-05-11):** `SyncEngine` stores the pull cursor from
the start of a successful pull and subtracts a 5-minute overlap from each
subsequent delta query. This prevents rows updated while a device is mid-sync
from being skipped forever when the cursor advances after the row's
`updated_at`. The fix specifically protects `projects.project_images` updates,
where crew could keep seeing old project photos but miss new URLs appended
during another device's upload.
| Background processing | `triggerSync()` + photo uploads + cleanup | Full cycle |

---

## SupabaseSyncManager (Legacy Adapter)

**Source**: `OPS/Network/Sync/SupabaseSyncManager.swift`
**Status**: Legacy adapter -- retained for entity-specific fetch methods not yet migrated to the SyncEngine processor pattern.

### Retained Methods

The following methods are still called by views and other managers that have not yet been migrated:

- `fetchUser(userId:)` -- fetches a single user from Supabase
- `fetchCompany(companyId:)` -- fetches a single company from Supabase
- `syncAll()` -- full 7-step sync (company, users, clients, task types, projects, tasks, link relationships)
- `syncAppLaunch()` -- launch-time sync (critical data foreground, rest deferred)
- `syncCompanyTeamMembers(companyId:)` -- fetches users, applies admin roles
- `linkAllRelationships()` -- wires SwiftData relationships after sync

### Relationship to SyncEngine

- SyncEngine is the **primary orchestrator** for all new sync flows
- SupabaseSyncManager's write methods (e.g., `updateProjectStatus`, `createProject`) are being migrated to use `syncEngine.recordOperation()` internally
- Entity-specific fetch/sync methods remain on SupabaseSyncManager until fully migrated to InboundProcessor

### Repositories

The sync manager still holds 6 repository instances initialized from `UserDefaults.companyId`:

```swift
private var projectRepo: ProjectRepository?
private var taskRepo: TaskRepository?
private var clientRepo: ClientRepository?
private var userRepo: UserRepository?
private var companyRepo: CompanyRepository?
private var taskTypeRepo: TaskTypeRepository?
```

---

## OutboundProcessor (Push Queue)

**Source**: `OPS/Network/Sync/OutboundProcessor.swift`
**Added**: March 8, 2026
**Purpose**: Processes pending SyncOperations by pushing local changes to the server via the repository layer

### Processing Pipeline

`processPendingOperations()` executes the following steps:

1. **Fetch**: Queries SwiftData for all SyncOperations with `status == "pending"`, ordered by priority then creation date
2. **Coalesce**: Multiple operations targeting the same `(entityType, entityId)` are merged -- changed fields are unioned and payloads are overlaid in creation order. When a local `create` is followed by immediate updates, every update payload is merged into the create before it is pushed, so quick-add task scheduling fields (`start_date`, `end_date`, `duration`, `schedule_locked`) survive later display-order updates.
3. **Dependency ordering**: Operations with `dependsOnId` are deferred until their dependency completes
4. **Push**: Each operation is dispatched to the appropriate repository method based on `entityType` and `operationType`
5. **Status update**: On success, status is set to "completed". On failure, status remains "pending", `retryCount` is incremented, and `lastError` is recorded

### Exponential Backoff

Failed operations use exponential backoff before the next retry attempt:

```swift
let delay = min(pow(2.0, Double(retryCount)), 60.0)  // caps at 60 seconds
```

**Max retries**: 20 attempts. After 20 failures, the operation is marked as "failed" and will not be retried automatically.

### Auth Error Detection

`classifySyncError()` inspects the error to determine if it is an authentication failure (expired token, 401 response, etc.). When an auth error is detected:

```swift
NotificationCenter.default.post(name: .syncAuthExpired)
```

This notification triggers the app to re-authenticate before further sync attempts.

### Cleanup

`cleanupCompletedOperations()` deletes SyncOperations with `status == "completed"` that are older than a configurable threshold.

---

## InboundProcessor & Conflict Resolution (Field-Level Merge)

**Source**: `OPS/Network/Sync/InboundProcessor.swift`
**Added**: March 8, 2026
**Purpose**: Pulls server data into local SwiftData with field-level conflict protection that never overwrites pending local changes

### Field-Level Merge Strategy

When InboundProcessor receives server data for an entity, it does NOT blindly overwrite local fields. Instead, it checks the SyncOperation table for pending outbound changes:

```swift
func acceptableFields(entityType: String, entityId: String) -> Set<String>?
```

**Logic**:
1. Query SyncOperation table for records matching `(entityType, entityId, status == "pending")`
2. Collect all `changedFields` from those pending operations into a `pendingSet`
3. Return only fields that are **NOT** in the `pendingSet`
4. If no pending operations exist, return `nil` (meaning all fields are acceptable for overwrite)

**Result**: Local changes are never overwritten by server data until they have been successfully pushed. This replaces the previous `needsSync` boolean guard with precise field-level protection.

### Inbound Sync Flow

1. `pullChanges(since: Date?)` fetches updated records from Supabase via repository `fetchAll(since:)` methods
2. For each record, `acceptableFields()` is called to determine which fields can be overwritten
3. Only acceptable fields are applied to the local SwiftData model
4. `lastSyncedAt` is updated on the local model
5. After all entities are processed, `linkAllRelationships()` wires SwiftData relationships

### Legacy ConflictResolver

The previous `ConflictResolver.merge()` static method (timestamp-based, whole-record comparison) is superseded by the field-level merge in InboundProcessor. The `ConflictResolver.swift` file may still exist in the codebase but is no longer called in the active sync path.

---

## RealtimeProcessor (WebSocket)

**Source**: `OPS/Network/Sync/RealtimeProcessor.swift`
**Added**: March 8, 2026 (replaces RealtimeManager)
**Purpose**: Push-based data updates via Supabase Realtime WebSocket subscriptions with field-level merge protection

### Architecture

RealtimeProcessor subscribes to Postgres changes on 9 merged entity tables filtered by `company_id`. When an INSERT, UPDATE, or DELETE event arrives, it decodes the payload into the appropriate DTO, converts to a SwiftData model, and performs a field-by-field upsert with merge protection.

It additionally subscribes to 3 **notification-only** tables — `opportunities`, `activities`, `follow_ups` (added 2026-07-03, bug `0b7e9b17`) — which follow the `expenses`/`expense_batches` idiom: no DTO decode, no SwiftData merge, they simply post the `.opsLeadsDidChange` NotificationCenter event. LEADS is deliberately outside the SwiftData sync engine (direct-fetch via `OpportunityRepository`), so the event drives a debounced, coalesced REST re-fetch in `PipelineViewModel.scheduleRefresh` that merges server rows into the existing `Opportunity` instances by id. All three are in the `supabase_realtime` publication with `REPLICA IDENTITY FULL` + a `company_id` column (verified 2026-07-03).

### Configuration

```swift
func configure(modelContext: ModelContext, companyId: String)
func startListening() async
func stopListening() async
```

### Realtime cancellation watchdog safety (2026-08-19)

The iOS dependency floor is `supabase-swift` 2.54.1. Earlier resolved version
2.41.1 can deadlock while cancelling the socket-status `AsyncStream`: one path
resumes a continuation while holding the subject lock while cancellation holds
the Swift task-status lock and re-enters the subject. Because
`RealtimeProcessor`, `SyncEngine.stopRealtime()`, and the app lifecycle stop
path are main-actor isolated, that lock inversion becomes a foreground
`0x8BADF00D` scene-update watchdog rather than a recoverable socket failure.
Supabase 2.54.1 resumes continuations outside the lock and removes the affected
subject implementation. OPS enforces the version in
`OPS.xcodeproj/project.pbxproj` and `Package.resolved` (commit `968a0d06`).

### Subscribed Tables (9 entity tables)

All subscriptions are scoped to a single Supabase channel named `"company-{companyId}"`, with each table filtered by `company_id=eq.{companyId}` (except `companies` which filters on `id=eq.{companyId}`).

- `projects`
- `project_tasks`
- `users`
- `clients`
- `companies`
- `task_types`
- `sub_clients`
- `project_notes`
- `project_photo_annotations`

### Field-Level Merge Protection

Every upsert triggered by a realtime event uses the same field-level merge pattern as InboundProcessor:

```swift
func pendingFieldsForEntity(entityType: String, entityId: String) -> Set<String>
```

This queries the SyncOperation table for pending operations on the entity and returns the set of fields with local pending changes. Those fields are skipped during the realtime upsert, preventing server data from overwriting unsynced local edits.

### Disconnect Tracking & Catch-Up

When the WebSocket connection drops:

1. `handleDisconnect()` records the disconnection timestamp
2. When the connection is re-established, a `.realtimeNeedsCatchUp` notification is posted
3. SyncEngine observes this notification and calls `deltaSyncSince(disconnectedAt:)` to pull all changes that occurred during the disconnect window

This replaces the previous no-op `catchUpSync()` placeholder with an active catch-up mechanism.

### Change Handling

Each change event routes through the same pattern:

```
INSERT/UPDATE -> upsertRecord with field-level merge protection
  - Decodes record payload into the appropriate DTO
  - Converts DTO to SwiftData model via dto.toModel()
  - Checks pendingFieldsForEntity() to determine which fields to skip
  - Applies only non-pending fields to the local model
  - Sets lastSyncedAt = Date()

DELETE -> softDeleteRecord
  - Decodes old_record for the ID
  - Fetches existing SwiftData model
  - Sets deletedAt = Date()
```

For `project_notes`, a `NotificationCenter.default.post(name: .projectNoteReceived)` notification is fired after upsert to trigger UI updates.

For `sub_clients`, the parent client relationship is linked during upsert by looking up the `parentClientId` in the model context.

---

## BackgroundSyncScheduler

**Source**: `OPS/Network/Sync/BackgroundSyncScheduler.swift`
**Added**: March 8, 2026 (replaces BackgroundTaskManager)
**Purpose**: BGTaskScheduler-based background sync with two task types for periodic sync and heavy processing

### Task Types

| Task Type | Identifier | Interval | Work Performed |
|-----------|-----------|----------|----------------|
| **Refresh** | `com.ops.sync.refresh` | 15 minutes | `pushPending()` only -- pushes queued SyncOperations |
| **Processing** | `com.ops.sync.processing` | 30 minutes | `triggerSync()` + `processPhotoUploads()` + `cleanupCompletedOperations()` |

### Info.plist Registration

Both task identifiers must be registered in `Info.plist` under `BGTaskSchedulerPermittedIdentifiers`:

```xml
<key>BGTaskSchedulerPermittedIdentifiers</key>
<array>
    <string>com.ops.sync.refresh</string>
    <string>com.ops.sync.processing</string>
</array>
```

### Scheduling

- **Refresh task**: Registered as a `BGAppRefreshTaskRequest` with `earliestBeginDate` set to 15 minutes from now
- **Processing task**: Registered as a `BGProcessingTaskRequest` with `earliestBeginDate` set to 30 minutes from now, `requiresNetworkConnectivity = true`
- Both tasks re-schedule themselves upon completion to maintain the periodic cycle

### Legacy BackgroundTaskManager

The previous `BackgroundTaskManager` (UIKit `beginBackgroundTask` approach, 25-second timeout) is superseded by `BackgroundSyncScheduler`. The BGTaskScheduler approach provides longer execution windows and system-managed scheduling.

---

## PhotoProcessor & Image Upload

**Source**: `OPS/Network/Sync/PhotoProcessor.swift`
**Added**: March 8, 2026 (replaces ImageSyncManager)
**Purpose**: Offline-first photo save, resize, upload queue with quality-aware concurrency

### savePhoto()

When a user takes or selects a photo:

1. **Resize**: Image is resized to a maximum of 2048px on the longest edge
2. **Adaptive JPEG compression**: Quality varies by megapixel count:
   - `> 4MP` -- 0.5 quality
   - `> 2MP` -- 0.6 quality
   - `> 1MP` -- 0.7 quality
   - `<= 1MP` -- 0.8 quality
3. **Local save**: Full-size JPEG is saved to the app's local file system
4. **Thumbnail generation**: A smaller thumbnail is generated and saved alongside

### processUploadQueue()

Processes the queue of locally-saved photos awaiting upload:

- **Concurrency**: Quality-aware based on network type:
  - WiFi: up to 3 concurrent uploads
  - Cellular: 1 concurrent upload (to conserve bandwidth)
- **Upload mechanism**: Each photo is uploaded via `PresignedURLUploadService` (presigned URL from OPS-Web, then PUT to S3)
- **Post-upload**: The local `project_images` array URL is replaced with the S3 public URL, and Supabase is updated

### cleanupSyncedPhotos()

After a photo has been successfully uploaded to S3:

- The **full-size local file** is deleted to reclaim storage
- The **thumbnail** is kept for offline display

### PresignedURLUploadService (Unchanged)

**Source**: `OPS/Network/PresignedURLUploadService.swift`
Singleton `@MainActor` class. Upload flow is unchanged:

```
1. POST https://app.opsapp.co/api/uploads/presign
   Headers: Authorization: Bearer {supabase_access_token}
   Body: { filename, contentType: "image/jpeg", folder: "projects/{companyId}/{projectId}" }

2. Response: { uploadUrl: "https://s3...presigned", publicUrl: "https://s3...public" }

3. PUT {uploadUrl} with raw JPEG data

4. Store publicUrl in project's project_images array

5. Update Supabase: UPDATE projects SET project_images = [...] WHERE id = {projectId}
```

**Public Methods**:

| Method | Description |
|--------|-------------|
| `uploadProjectImages(_ images:, for project:, companyId:)` | Upload multiple images, returns array of `(url, filename)` |
| `uploadProfileImage(_ image:, userId:, companyId:)` | Upload user profile image (800x800 max), returns URL |
| `uploadCompanyLogo(_ image:, companyId:)` | Upload company logo (1000x1000 max), returns URL |

**Presign Folder Patterns**:
- Project images: `projects/{companyId}/{projectId}`
- Profile images: `profiles/{companyId}`
- Company logos: `logos/{companyId}`

### "Add to OPS" Share-Extension Upload (reliability hardening 2026-07-23)

**Sources:** `ops-web/src/app/api/uploads/share-photo/route.ts`, `ops-web/src/app/api/uploads/share-photo/recovery/route.ts`, `ops-web/src/lib/uploads/share-photo-permission.ts`, `ops-web/supabase/migrations/20260723193000_atomic_share_photo_filing.sql`, `ops-ios/Shared/SharePhotoEndpoint.swift`, `ops-ios/Shared/ShareUploadRecoveryStore.swift`, `ops-ios/OPSShareExtension/ShareBackgroundUploader.swift`, `ops-ios/OPS/ShareExtension/SharePhotoEndpointUploader.swift`, and `ops-ios/OPS/ShareExtension/SharePhotoRecoveryReporter.swift`.

This flow is deliberately separate from `PresignedURLUploadService`. The extension and the app-side recovery drain send the same raw-file request:

```http
POST https://app.opsapp.co/api/uploads/share-photo?projectId={projectUUID}&jobId={jobUUID}&takenAt={ISO8601}
Authorization: Bearer {firebase_id_token}
Content-Type: image/jpeg

{raw JPEG bytes}
```

`projectId` and `jobId` must be UUIDs. The endpoint accepts only JPEG bodies of at most 15 MiB. It verifies the Firebase token, resolves an active OPS user strictly through the token's cryptographic user id (`users.auth_id` / `users.firebase_uid`; no email fallback), confirms that the project is active and belongs to that user's company, and evaluates the canonical project-level all/assigned boundary through `private.user_can_edit_project(user_id, project_id)`. The extension's cached project list and coarse permission snapshot are picker hints only and are never trusted as server authorization.

`jobId` is the idempotency key. The server stores the bytes at the deterministic key `projects/{companyId}/{projectId}/share-{jobId}.jpg`, then calls the service-role-only `file_share_photo_as_system` RPC. That transaction serializes the job identity, locks and re-authorizes the active project, inserts or resolves the matching non-deleted `project_photos` row (`source = in_progress`, `uploaded_by` = authenticated OPS user, `taken_at` = the request timestamp), and appends the URL to `projects.project_images` without losing a concurrent update or duplicating an existing value. Identity conflicts fail instead of overwriting or resurrecting a soft-deleted photo.

The route returns `{ success: true, url }` only after it also creates the deduped uploader-facing `photo_uploaded` completion notification for the stable 15-minute capture-time bucket. If notification creation fails after the database transaction committed, the route returns `503`; the durable iOS job remains queued. Its replay resolves the existing photo identity and retries completion without uploading the JPEG or attaching it again.

`POST /api/uploads/share-photo/recovery` is the permanent-failure reporting path. It accepts bounded legacy identifiers as opaque values and hashes a non-UUID job identifier into a stable dedupe key. It links a recovery notice to a project only when that project is active, in the user's company, and currently editable by that user; a foreign-company project is rejected with `403`, while an unavailable or no-longer-editable project produces generic unlinked guidance. The notice is standard and dismissible, not persistent: title `Photo upload needs attention`; linked body `Open {project title} and share the photo again.` with action `VIEW PROJECT`; otherwise `A shared photo could not be attached. Share it again to an active project.` Permanent dedupe prevents retries from creating another notice after the first one is read or dismissed.

**Cross-process durability:**

1. The extension downscales every selected image, writes all JPEGs to the App Group inbox, then appends the complete job batch to the file-coordinated manifest in one mutation.
2. If any selected image fails to stage, or the manifest cannot be written and read back completely, the extension removes the staged subset and shows failure. It reports success only after every selected JPEG and manifest row is durable.
3. With a usable bridged token, the extension starts a best-effort background POST. The durable manifest remains the guaranteed recovery path.
4. A running app drains immediately after the Darwin notification; otherwise it drains on launch, foreground, or restored connectivity. The app obtains a fresh Firebase token and force-refreshes it once after a `401` or `403`, then sends the identical `projectId` / `jobId` / `takenAt` request. It does not block the drain on a stale global `projects.edit` snapshot.
5. Connectivity, refreshable authentication, throttling, and `5xx` failures remain queued without consuming the parking budget. A `403` after the forced token refresh is deterministic evidence that the current project-level authorization was revoked; it consumes the parking budget instead of retrying forever.
6. After 10 deterministic failures the job is parked with its manifest row and JPEG bytes retained, then reported through `/api/uploads/share-photo/recovery`. Recovery reporting itself remains retryable and permanently deduped.
7. Legacy deployed jobs carrying `s3PublicUrl` decode into `uploadedURL` and use `SharePhotoFinalizer` against that exact URL. They are finalized idempotently and never re-uploaded through the deterministic endpoint.

### Filename Generation

**Pattern**: `{StreetAddress}_IMG_{unixTimestamp}_{index}.jpg`

Duplicate checking: filenames are validated against existing project image URLs. If a collision is detected, a `_{attemptCount}` suffix is appended.

---

## ConnectivityManager

**Source**: `OPS/Network/ConnectivityManager.swift`
**Added**: March 8, 2026 (replaces ConnectivityMonitor)
**Purpose**: Network quality monitoring with lying WiFi detection and quality scoring

### Architecture

ConnectivityManager wraps `NWPathMonitor` with additional performance tracking and quality assessment.

### Key Properties

| Property | Type | Description |
|----------|------|-------------|
| `isConnected` | `Bool` | Whether network is reachable |
| `connectionType` | `ConnectionType` | `.none`, `.wifi`, `.cellular`, `.wiredEthernet` |
| `connectionQuality` | `ConnectionQuality` | `.excellent`, `.good`, `.poor`, `.unusable` |
| `shouldAttemptSync` | `Bool` (computed) | `true` when quality is `.good` or better |
| `shouldUploadPhotos` | `Bool` (computed) | `true` when quality is `.good` or better AND connection is WiFi or wired |

### Lying WiFi Detection

ConnectivityManager detects "lying WiFi" -- situations where the device reports a WiFi connection but cannot actually reach the server (common with captive portals, congested networks, etc.):

1. When WiFi is detected, a lightweight health check is performed against the Supabase endpoint
2. If the health check fails, `connectionQuality` is set to `.unusable` despite the WiFi status
3. This prevents the sync engine from wasting cycles on requests that will fail

### Quality Scoring

Connection quality is assessed based on response times and success rates:

| Quality | Criteria |
|---------|----------|
| `.excellent` | Consistent sub-200ms responses, no failures |
| `.good` | Responses under 1s, occasional failures acceptable |
| `.poor` | Responses over 1s or intermittent failures |
| `.unusable` | Cannot reach server or consistent timeouts |

### Integration with SyncEngine

SyncEngine and its processors check `ConnectivityManager.shouldAttemptSync` before initiating any network I/O. PhotoProcessor additionally checks `shouldUploadPhotos` before starting uploads to avoid consuming metered data.

### Notifications

- Posts connectivity change notifications via NotificationCenter when connection type or quality changes
- DataController observes these changes and triggers sync when connection is restored

---

## OneSignal Push Notifications

**Source**: `OPS/Services/OneSignalService.swift`
**App ID**: `0fc0a8e0-9727-49b6-9e37-5d6d919d741f`

### Architecture

New notification work uses the proof-only OPS-Web dispatcher:

1. The client submits a persisted event identifier to `POST https://app.opsapp.co/api/notifications/dispatch`.
2. OPS-Web resolves the authenticated actor and company from Firebase identity.
3. The service-role resolver loads the persisted event, reauthorizes its relationship, derives recipients/copy/navigation server-side, reapplies current active-company and notification-preference filters, and writes the notification rail.
4. OPS-Web sends the derived push through OneSignal. Durable events reuse one UUID as both rail identity and OneSignal `idempotency_key`.

The iOS app receives pushes via the `OneSignalFramework` SDK, configured in `AppDelegate`.

`POST /api/notifications/send` is the retired body-trusted proxy. `OneSignalService.swift` still contains legacy wrappers for older call sites, but new code must not send recipient IDs, titles, bodies, or navigation supplied by a client.

### Mention-edit request

```swift
POST /api/notifications/dispatch
Authorization: Bearer {firebase_id_token}
Content-Type: application/json

{
    "eventType": "mention_edit",
    "mentionEventId": "<uuid>"
}
```

The resolver accepts only those two keys. It loads `project_note_mention_events`, verifies actor/company ownership, rejects proofs older than 29 days, confirms the note is still an editable human note, intersects the event's newly added recipients with the note's current mention list, and revalidates active same-company users. The derived rail key is `mention-edit:<uuid>`; push retries reuse the event UUID within OneSignal's 30-day idempotency window. Notification previews humanize canonical mention tokens back to `@Display Name` / `@All Team`, so recipient UUIDs and reserved authority targets never appear in rail or push copy.

### Legacy iOS wrapper methods

| Method | Type | Title | Self-Skip |
|--------|------|-------|-----------|
| `notifyTaskAssignment(userId:, taskName:, projectName:, taskId:, projectId:)` | `taskAssignment` | "New Task Assignment" | Yes |
| `notifyScheduleChange(userIds:, taskName:, projectName:, taskId:, projectId:)` | `scheduleChange` | "Schedule Update" | Yes |
| `notifyTaskCompletion(userIds:, taskName:, projectName:, taskId:, projectId:, completedByName:)` | `taskCompletion` | "Task Completed" | Yes |
| `notifyProjectCompletion(userIds:, projectName:, projectId:)` | `projectCompletion` | "Project Completed" | Yes |
| `notifyProjectAssignment(userId:, projectName:, projectId:)` | `projectAssignment` | "Added to Project" | Yes |
| `notifyProjectNoteMention(userId:, authorName:, notePreview:, projectName:, projectId:, noteId:)` | `projectNoteMention` | "{authorName} mentioned you" | Yes |

**Self-Skip**: All notification methods filter out `currentUserId` to prevent self-notifications.

### OneSignal User Linking

In `NotificationManager.swift`:
- `linkUserToOneSignal()` -- called after login, calls `OneSignal.login(userId)` and adds `role` and `companyId` tags for segmentation
- `unlinkUserFromOneSignal()` -- called on logout, calls `OneSignal.logout()`

---

## Firebase Analytics

Firebase is used **only for analytics** (Google Ads conversion tracking). It is NOT used for authentication or database.

**SDK**: `FirebaseCore` + `FirebaseAnalytics`
**Config File**: `GoogleService-Info.plist`
**Initialization**: `FirebaseApp.configure()` in `AppDelegate.didFinishLaunchingWithOptions` (must be first)

### AnalyticsManager

**Source**: `OPS/Utilities/AnalyticsManager.swift`
Singleton for tracking conversion events via Firebase Analytics. Events flow to Google Ads via the Firebase Analytics integration.

### Event Categories

#### Authentication Events

| Event | Parameters | Description |
|-------|------------|-------------|
| `sign_up` | `method`, `user_type` | New user account creation |
| `login` | `method`, `user_type` | Returning user login |

#### Onboarding Events

| Event | Parameters | Description |
|-------|------------|-------------|
| `complete_onboarding` | `user_type`, `has_company` | User completes onboarding |
| `begin_trial` | `user_type`, `trial_days` | Company owner starts trial |

#### Subscription Events

| Event | Parameters | Description |
|-------|------------|-------------|
| `purchase` | `item_name`, `price`, `currency`, `user_type` | Subscription purchase |
| `subscribe` | `item_name`, `price`, `currency`, `user_type` | Custom subscription event |

#### CRUD Events

| Event | Parameters | Description |
|-------|------------|-------------|
| `create_project` | `project_count`, `user_type` | Project created |
| `create_first_project` | `user_type` | First project (high-intent) |
| `project_edited` | `project_id` | Project updated |
| `project_deleted` | - | Project deleted |
| `task_created` | `task_type`, `has_schedule`, `team_size` | Task created |
| `task_edited` | `task_id` | Task updated |
| `task_completed` | `task_type` | Task marked complete |
| `client_created` | `has_email`, `has_phone`, `import_method` | Client created |

#### Screen View Events

| Event | Parameters | Description |
|-------|------------|-------------|
| `screen_view` | `screen_name`, `screen_class` | Screen viewed |
| `tab_selected` | `tab_name`, `tab_index` | Tab navigation |

#### Engagement Events

| Event | Parameters | Description |
|-------|------------|-------------|
| `navigation_started` | `project_id` | User starts navigation |
| `search_performed` | `section`, `results_count` | Search executed |
| `image_uploaded` | `image_count`, `context` | Photo uploaded |

### Google Ads Conversion Events

These events are automatically sent to Google Ads:
1. `sign_up` - Primary acquisition conversion
2. `purchase` - Revenue conversion
3. `create_first_project` - High-intent engagement
4. `complete_onboarding` - Onboarding completion
5. `task_completed` - Productivity signal

### Google Ads Reporting Integration (admin analytics)

**Status: LIVE — activated 2026-08-05, 2-year history imported.** The developer token received Google Basic API access approval on 2026-08-05; before that every sync failed with `DEVELOPER_TOKEN_NOT_APPROVED` and all warehouse tables sat empty. Activation surfaced three latent defects, all fixed and deployed to prod the same day:

1. `PAGE_SIZE_NOT_SUPPORTED` (400) — the client sent `pageSize: 10000`, which the API no longer accepts (fixed pages of 10k rows, `nextPageToken` pagination). Removed — commit `d3442792`.
2. `REQUESTED_METRICS_FOR_MANAGER` (400) — `GOOGLE_ADS_CUSTOMER_ID` (5448339076 "OPS LTD") is the **manager** account that holds the developer token; metrics live in the serving client account underneath (**4454506598 "OPS"**). The client now auto-resolves a configured manager id to its single enabled non-manager client via `customer_client` and sends `login-customer-id` (memoized; ambiguous hierarchies throw listing candidates; `GOOGLE_ADS_LOGIN_CUSTOMER_ID` optional override) — commit `ea800fe8`.
3. Backfill chain froze at 16% with status stuck on `running` — the chunk worker ran one 30-day chunk per invocation and handed off via an **unchecked** fetch; one non-2xx handoff killed the chain silently. Redesigned: multi-chunk loop within a 240s budget (2yr = 1–3 invocations), verified + retried handoffs via `src/lib/admin/ads-backfill-dispatch.ts`, loud `failed` status on exhausted retries, and the daily ads-sync cron doubles as a watchdog reviving any `running` run with a heartbeat older than 10 min — commit `7e42ac71` (rebased). Unit coverage: `tests/unit/analytics/google-ads-client.test.ts`, `tests/unit/api/google-ads-backfill-chunk.test.ts`.

**History imported 2026-08-05 21:13 UTC (730/730 days):** `ads_daily_account` 197 rows, `ads_daily_campaign` 467 rows, `ads_daily_search_term` 5,274 rows. Activity spans 2025-02-20 → 2026-03-09 (no spend after 2026-03-09): $4,777.80 CAD, 8,495 clicks, 355 conversions (account and campaign totals cross-check exactly).

**Token designation (2026-08-05):** Google's approval notice names the **"App Conversion Tracking and Remarketing API"** and warns that full access provisioning "may take up to two weeks to propagate." Empirically this restricts nothing OPS depends on — every production query surface was exercised against the live account the same day and returned HTTP 200: account summary, campaign, `keyword_view`, `search_term_view`, `conversion_action` (resource + segmented), and the daily-spend series. If provisioning changes behavior mid-propagation, the daily cron records the failure in `ads_sync_status.error`, which the page's sync bar renders — no extra monitoring needed.

**Conversion tiles (2026-08-05, commit `a3be19be`):** `COST PER SIGNUP` / `COST PER INSTALL` had never rendered a value. Three defects, all masked by the pre-approval 403 and by `safe()` swallowing the error:
1. The breakdown query selected `metrics.cost_micros` alongside `segments.conversion_action_name` — rejected with `PROHIBITED_SEGMENT_WITH_METRIC_IN_SELECT_OR_WHERE_CLAUSE`. **Google does not attribute cost to individual conversion actions.** The window's total account spend is the only honest numerator (this is also how the Ads UI computes cost/conv. when segmenting), so `ConversionBreakdown.cost` now carries that window total and `cpa = windowSpend / action conversions`.
2. Install selection matched names containing `"install"`; the account's actual action is **"OPS APP First open"**. Selection is now by Google's own `conversion_action.category` (SIGNUP / DOWNLOAD), fetched from the `conversion_action` resource, with name matching kept only as a fallback for rows lacking a category.
3. Tiles used `.find()` — one action, rest ignored. All matching actions now sum (`src/lib/admin/ads-conversion-tiles.ts`, pure + client-safe; tests `tests/unit/admin/ads-conversion-tiles.test.ts`).

Live conversion actions on the account (2025-02-20 → 2026-03-09): "Join Ops SIgnup" 202 · "Quiz Signup v2" 18 · "Homepage Signup" 6 (all SIGNUP) · "OPS APP First open" 129 (DOWNLOAD) = 355, reconciling exactly to the account total. Renders as **cost per signup $21.14 (226)** and **cost per install $37.04 (129)**.

**Page ranges (2026-08-05, commit `a24a5630` deployed as `160f85f0`):** `/admin/google-ads` offers 7D/30D/90D/12M/ALL (ALL spans from the first warehouse-activity day). One shared assembly (`src/lib/admin/google-ads-page-data.ts`) serves the server-rendered page AND `/api/admin/google-ads` (`?preset=`, legacy `?days=` accepted): warehouse-first for summary/campaigns/search-terms/daily-spend, always-live explicit-date queries for keywords + conversion actions (not warehoused), fully-live fallback for unsynced windows. Empty windows render `[all campaigns paused — last activity <date>]` from `getHistoryBounds()`. `DateRangeControl` emits its `preset` in `DateRangeParams` (optional field). Tests: `tests/unit/admin/google-ads-page-data.test.ts`.

The reporting direction (Google Ads → OPS) is entirely separate from the conversion events above (OPS → Google Ads).

**Client** — `ops-web/src/lib/analytics/google-ads-client.ts`:
- REST (not gRPC), Google Ads API `v23`, paginated `googleAds:search`
- Auth: the Firebase admin **service account** (`firebase-adminsdk-fbsvc@ops-ios-app.iam.gserviceaccount.com`) with the `adwords` OAuth scope — the SA is added as a user on the Google Ads account, so there is no refresh-token flow to expire
- Env: `GOOGLE_ADS_DEVELOPER_TOKEN`, `GOOGLE_ADS_CUSTOMER_ID` (5448339076), plus the Firebase admin credentials (already set in Vercel prod; token approval did not change the token string)

**Consumers:**
| Surface | Source | Notes |
|---------|--------|-------|
| `/admin/google-ads` page | Live API, 5-min `unstable_cache` | KPIs, campaigns, keywords, search terms, daily spend, conversion breakdown (30-day default) |
| `ads_daily_account/campaign/search_term` tables | `/api/cron/ads-sync` daily 08:04 UTC | Warehouse history; `ads_daily_keyword` exists but is not populated by design (keywords render live) |
| 2-year history backfill | `IMPORT HISTORY` button on the page → `/api/admin/google-ads/backfill` → self-chaining 30-day chunk workers (CRON_SECRET auth) | Idempotent upserts; progress in `ads_sync_status` |
| Weekly AI briefing | `/api/cron/ads-briefing` Mondays 12:34 UTC | Writes to briefings surface at `/admin/google-ads/briefings` |
| `ad_spend_log` (PMF CAC/payback) | `/api/cron/pmf/google-ads-sync` daily 10:24 UTC | One account-level row per day, zero-row on no-spend days |

**Sync state** lives in `ads_sync_status` (`daily-sync` + `backfill` rows). Cost: Google Ads API Basic access is free (15k operations/day quota; OPS usage is single-digit calls per day).

### Attribution Capture (Unified Attribution P2 — 2026-08-06)

The spend side above records what OPS *pays*. This records where a *customer* came from. Both feed the eventual unified attribution screen (P4).

**Every company gets an attribution row at birth.** Trigger `companies_seed_trial_attribution` (`AFTER INSERT ON companies` → `seed_trial_attribution_for_company()`) inserts a `trial_attributions` row with `attributed_channel = 'unknown'`, on **every** creation path — web, iOS, or anything added later.

This is deliberately a trigger and **not** part of `create_company_for_owner`. That RPC is the shared, atomic owner-setup path for both platforms; an analytics side-effect does not justify changing it. Two consequences depend on universal coverage:
- attribution rates are computed against **all** companies, so a missing row silently understates every rate;
- `billing_events_first_paid` only **UPDATEs** an existing row, so a company with no row can never be counted as a paid conversion.

The insert is wrapped in an exception handler that logs a warning and continues — **company creation must never fail because analytics failed.**

**First-touch cookie.** `ops-site` middleware writes `ops_attribution` on first visit (all four locale-routing branches), scoped **`Domain=.opsapp.co`** so it reaches `app.opsapp.co`. Before 2026-08-06 it was host-only, so the app never received it and signup attribution captured nothing. First touch is never overwritten. The domain is omitted outside production (a dotted domain is invalid on localhost).

| Cookie | Written by | Shape |
|---|---|---|
| `ops_attribution` | `ops-site` middleware (primary — most real first touches) | `utm_*`, `gclid`, `fbclid`, `landing_url` (path+query), `first_touch_at` |
| `__ops_first_touch` | `ops-web` client `captureOnLanding()` (defensive — tagged URL hitting `app.opsapp.co` directly) | same + `referrer`, `captured_at` |

**Read at signup.** `POST /api/setup/progress` (step `company`) calls `readServerFirstTouch(req.headers.get("cookie"))`, which parses **both** cookie names off the raw `Cookie` header and returns the **earliest** `captured_at`/`first_touch_at`. Raw-header parsing is deliberate: duplicates of one name can coexist (host-only alongside `.opsapp.co`), and a parsed cookie store surfaces only whichever the browser ordered first — so first-touch would be ordering-dependent.

`recordTrialAttribution()` then UPDATEs the row, scoped to `attributed_channel = 'unknown'` so a first touch is never overwritten. It skips only when the cookie carries **no signal at all** — not when the channel fails to classify, because `deriveAttributionChannel()` returns `unknown` for real-but-unrecognized sources (e.g. `utm_source=newsletter`), and gating on the channel would discard their UTM data. Never throws.

**`first_paid_at` needs no application code.** Trigger `billing_events_first_paid` → `pmf_update_first_paid_at()` stamps it whenever the Stripe webhook inserts a `billing_events` row with `event_type = 'invoice.paid'` and a resolved `company_id`. This predates P2 and was already correct; it was a no-op only because `trial_attributions` was empty.

**"How'd you find us" (`companies.referral_method`).** The only acquisition signal that survives an App Store install. Optional single-select on **both** the web company setup step and iOS `CompanyNameStepView`; never gates the CTA, and re-tapping the selection clears it (deselection is the skip). Stores a **slug**, not the label, so copy can change without breaking aggregation. Vocabulary is shared verbatim — `ops-web/src/lib/data/referral-sources.ts` and `ops-ios/OPS/Onboarding/Models/ReferralSource.swift`; **keep them in step or the platforms' answers stop aggregating**:

`instagram` · `facebook` · `youtube` · `google` · `app_store` · `word_of_mouth` · `other`

iOS writes it as a follow-up update after `create_company_for_owner` returns (the RPC does not accept it) — same pattern web uses for `company_size` / `company_age`. Both platforms validate against the known slug set before writing.

Seven Bubble-era companies carry legacy free-text values (`Instagram`, `Word of Mouth (Onsite)`, `Internet Advertisement`, `Other`). These are **intentionally not migrated** — `Internet Advertisement` cannot be mapped to a slug without guessing. **Normalize at read time in P4.**

**Known coverage limit.** Every primary CTA on `ops-site` points at the App Store, and no click id survives an install. Measured over companies created since 2026-03-01, only ~26% (5 of 19) were born through web setup. Cookie-based attribution therefore covers a minority of signups by construction; the referral question is what covers the rest. `try-ops` (ad landing pages) does not yet write the cookie — a `.opsapp.co` cookie written there would reach the app, so that remains an open follow-up.

---

## Stripe Subscription Integration

### Architecture

Stripe subscription management is handled server-side via OPS-Web. The iOS app reads subscription status from the `Company` entity synced via Supabase.

**Key Company Fields** (from `SupabaseCompanyDTO`):
- `subscriptionStatus` -- "active", "trialing", "past_due", "cancelled", etc.
- `subscriptionPlan` -- plan identifier
- `subscriptionEnd` -- subscription end date
- `subscriptionPeriod` -- billing period
- `trialStartDate` / `trialEndDate` -- trial window
- `maxSeats` -- maximum seats allowed by plan
- `seatedEmployeeIds` -- array of user IDs with active seats
- `stripeCustomerId` -- Stripe customer ID
- `hasPrioritySupport` -- boolean flag

### Subscription Status Logic

**Trial Check**:
```swift
var isInTrial: Bool {
    guard let trialEnd = company.trialEndDate else { return false }
    return Date() < trialEnd
}
```

**Active Subscription Check**:
```swift
var hasActiveSubscription: Bool {
    if isInTrial { return true }
    if company.subscriptionStatus == "active" || company.subscriptionStatus == "trialing" {
        return true
    }
    return false
}
```

**Seat Management**:
- `CompanyRepository.updateSeatedEmployees(companyId:, userIds:)` replaces the `seated_employee_ids` array

---

## Accounting Edge Functions

Three Supabase Edge Functions handle accounting integrations. All deployed via `deploy_edge_function`, using shared `_shared/supabase-client.ts` and `_shared/cors.ts` modules.

### accounting-oauth

OAuth flow for QuickBooks and Sage. Actions: `authorize`, `callback`, `refresh`, `disconnect`.

- **authorize**: Returns provider-specific OAuth redirect URL with `companyId` in state param
- **callback**: Exchanges authorization code for tokens, upserts `accounting_connections`
- **refresh**: Refreshes expired access tokens using refresh token (called internally by sync)
- **disconnect**: Clears tokens, sets `is_connected = false`

**Env vars**: `QB_CLIENT_ID`, `QB_CLIENT_SECRET`, `QB_REDIRECT_URI`, `SAGE_CLIENT_ID`, `SAGE_CLIENT_SECRET`, `SAGE_REDIRECT_URI`

### accounting-sync-expense

Syncs an approved expense to connected accounting system(s). Called by iOS app after expense approval.

**Flow**: Fetch connection → refresh token if expired → map to provider format → POST to API → update sync status → log result.

- **QB mapping**: OPS expense → QBO `Purchase` with vendor lookup/create, category → `AccountRef`, project → `CustomerRef`
- **Sage mapping**: OPS expense → Sage `OtherPayment` with contact lookup/create, category → `LedgerAccountId`
- **Retry**: 3x exponential backoff on 429/5xx

### accounting-batch-create *(deprecated 2026-05-08; fully superseded 2026-06-01)*

This cron-driven Edge Function was the original lazy batcher. It was deprecated 2026-05-08 (it had a latent bug — references to a nonexistent `expense_count` column and `accounting_sync_log` table made every invocation fail silently) and is **fully superseded** by the server-authoritative expense-batching brain shipped 2026-06-01. It should be removed via the Supabase dashboard.

Batching is now entirely in-database (Postgres), so no client version can strand an expense:

- **Placement** — `trg_place_expense` (AFTER INSERT/UPDATE OF status, expense_date, batch_id on `expenses`) → `place_expense(uuid)`: files every non-draft, unbatched expense into its per-person/per-period envelope (`expense_batches`, status `open`) by the expense's date, rolling forward when the home period's envelope is already approved.
- **Auto-send + reconciliation** — `pg_cron` job `expense_envelope_sweep_daily` (15:15 UTC) → `expense_envelope_sweep()`: auto-sends each `open` envelope past `period_end + expense_settings.auto_submit_grace_days` (flip to `pending_review` + one `expense_submitted` notification per envelope to `expenses.approve` holders), sweeps in completed drafts, adopts any orphaned `submitted/NULL` expense (the permanent safety net), and rolls stragglers forward.
- **Period math** — `public.expense_envelope_period(date, text)` (SQL port of `ExpenseBatchPeriod.swift`).

Server functions (`place_expense`, `expense_envelope_sweep`) are locked to `service_role` (REVOKEd from public/anon/authenticated). Full lifecycle: `09_FINANCIAL_SYSTEM.md § Server-Authoritative Expense Envelopes (2026-06-01)`. Migrations: `migrations/20260601210311_expense_envelope_schema.sql` … `20260601211914_expense_batches_rls_approve_scope.sql`.

---

## QuickBooks Sync — Pull Import, Webhook Apply, and Queue-Owned Full CRUD (2026-06-04; hardened 2026-06-08)

The QuickBooks Online (QBO) system has three deliberately separate paths: a guaranteed **read-only, pull-only** import; an inbound webhook apply path that fetches changed QBO records and updates OPS; and a full-CRUD outbound write queue for OPS-originated changes. The import pulls customers, invoices, estimates, payments (+ the item catalog), lands them in per-run `qbo_*` staging tables, lets an owner review proposed customer matches and a QB-vs-OPS reconciliation, and — on approval — writes them into the live `clients` / `sub_clients` / `estimates` / `invoices` / `line_items` / `payments` tables so iOS Books (P&L, Cash Flow, A/R) shows real money. QBO ItemRef line items are preserved and resolved against OPS products/task types/catalog recipes before live line replacement. Accepted QBO estimates are treated as first-class acceptance events: OPS ensures an opportunity link, stores the accepted estimate, and runs the existing estimate-to-job transaction to create/reuse the project, tasks, and projected material demand. The import and webhook fetch paths issue **zero** create/update/delete calls to Intuit; every QB call is a `GET`, and a `qb_write_calls` counter that must stay `0` is asserted and persisted per run.

This is "Sub-project A" of a two-part initiative (Sub-project B = profit/revenue-per-employee, gated after A). It lives entirely in `ops-web` (Next.js + Supabase); iOS is an unchanged read consumer of the resulting `invoices`/`payments`.

### Architecture & data flow

```
QuickBooks Online (READ ONLY, GET /v3/company/{realmId}/query)
        │
[1] PULL   QuickBooksPullService (GET-only; qb_write_calls must stay 0)
        ▼
[2] STAGE  qbo_staging_* tables (per run_id) + computed customer matches
        ▼
[3] REVIEW /accounting → "QuickBooks Import" tab: reconciliation strip + match table; owner picks link/create/skip
        ▼
[4] APPLY  idempotent on (company_id, qb_id) → live clients/sub_clients/estimates/invoices/line_items/payments
        ▼
iOS Books lights up with real money
```

- **The engine is service-role.** `QuickBooksImportService` and the apply path use `getServiceRoleClient()` (RLS bypassed). The review UI reads staging back as the **anon** role (Firebase-bridged), so every `qbo_*` table + `accounting_connections` carries a company-scoped, `accounting.view`-gated anon `SELECT` policy (see *Schema → RLS*).
- **Pull-only is enforced four ways:** `accounting_connections.sync_direction = 'pull_only'` (set at OAuth callback unless the operator explicitly enables Full CRUD); a separate import entry point (no push code path); `sync_enabled = false` for pull-only connections; and the apply step only writes Supabase, never Intuit. The legacy `POST /api/sync` still returns `409` for a `pull_only` connection and returns `202 queue_managed` for QuickBooks write-enabled connections; QuickBooks writes are owned by `accounting_sync_queue`, not by legacy direct sync.

### Pull service (read-only)

`QuickBooksPullService` (`src/lib/api/services/quickbooks-pull-service.ts`) is a GET-only client for the QBO query API.

- **Construction:** `new QuickBooksPullService(realmId, accessToken, environment, fetchImpl = fetch)`. `baseUrl = ${host}/v3/company/${realmId}`; queries hit `${baseUrl}/query?query=<url-encoded SQL>`.
- **Host by provider environment:** `host` = `https://quickbooks.api.intuit.com` only when `environment === "production"`, else `https://sandbox-quickbooks.api.intuit.com`. `getQuickBooksProviderEnvironment()` (`quickbooks-config.ts`) is the active-profile switch: `QB_ACTIVE_PROFILE` → `QB_ACTIVE_PROFILE_DEFAULT` → legacy `QB_ENVIRONMENT`; unset/empty defaults to `sandbox` (dev-safe). Explicit `production`/`sandbox` are honored; any other value throws.
- **GET-only guarantee:** `qboQuery(sql)` issues `GET` with `Authorization: Bearer`. The instance tracks `qbWriteCalls` (must stay `0`); the import service throws `Read-only violation: QB write calls = N` after a pull if non-zero, and persists the value to `qbo_import_runs.qb_write_calls`.
- **Pagination:** `paginate(baseSql, entityKey)` appends `STARTPOSITION n MAXRESULTS 1000` (1-based) and loops until a short page.
- **Entities & windows** (cutoff = today − 24 months, a bare `YYYY-MM-DD` validated by regex before interpolation):
  - `pullCustomers()` → `SELECT * FROM Customer` (all)
  - `pullInvoices(cutoff)` → union of `WHERE TxnDate >= '<cutoff>'` **and** `WHERE Balance > '0'` (all still-open), deduped by `Id`
  - `pullEstimates(cutoff)` / `pullPayments(cutoff)` → `WHERE TxnDate >= '<cutoff>'`
  - `pullItems()` → `SELECT * FROM Item` (all; feeds the Item.Id→Item.Type map)
- **`fetchEntityById(entityType, id)`** — single-record fetch used by the webhook. Hard-guarded: `entityType` ∈ `{Customer, Invoice, Payment, Estimate}` (allowlist) and `id` matches `/^\d+$/` (SQL-injection guard); otherwise throws. Customer fetches include `Active IN (true, false)` so Intuit inactivate/delete events can still retrieve the inactive record and apply the OPS soft-delete.

### Import service: lifecycle & apply order

`QuickBooksImportService` (`src/lib/api/services/quickbooks-import-service.ts`). Constants: `FUZZY_THRESHOLD = 0.6`, `HISTORY_MONTHS = 24`.

| Method | Responsibility |
|---|---|
| `startImportRun(companyId)` | Insert `qbo_import_runs` (`status: 'pending'`, `provider_environment` = active QuickBooks profile, `history_cutoff` = today−24mo, `qb_write_calls: 0`). |
| `pullAndStage(runId)` | Resolve the run's `provider_environment`, fetch the matching connection + valid token (`AccountingTokenService.getValidToken`), pull all entities, normalize (`qbo-normalize`), **upsert** customers/estimates/invoices/payments on `onConflict: "run_id,qb_id"` and **insert** line items. On a mid-pull 401, refresh the token once and re-run; assert `qbWriteCalls === 0`. Ends the run `staged`. |
| `computeCustomerMatches(runId)` | Propose a match per staged customer via `resolveCustomerMatch`; upsert `qbo_customer_matches` on `onConflict: "run_id,customer_qb_id"`. Writes nothing to `clients`. |
| `getImportReview(runId)` | Aggregate `{ run, matches, matchCounts, stagedCounts, reconciliation }` (`qbo-reconcile`), joining each match to its staged customer for the company/contact label. |
| `applyImport(runId, decisions)` | Apply the staged run in the locked order below; finish `applied` with `totals` = counts and `error` = `;`-joined non-fatal warnings (subtotal divergence, rejected cross-tenant links). Zero QB calls. |

**Apply order** (a `toShape(cust)` adapter maps each snake_case staged row to the `CustomerShape` consumed by the shared field-shaping helpers):

1. **STEP 1 — Clients (link / create / skip).** Per the owner's `customer_qb_id` decision (default `skip`): `skip`/`needs_review` → null client id; `link` → verify the target client belongs to `companyId` (cross-tenant link rejected + warned), then write the QBO identity + lifecycle state (`qb_id`, `deleted_at` from `Active=false`) without overwriting name/email/phone/address; `create` → idempotent on `(company_id, qb_id)`, upsert `...clientFieldsFromCustomer(toShape(cust))` and tombstone inactive QBO customers with `deleted_at`. Builds `clientIdByCustomerQbId`.
2. **STEP 1b — Contact sub_clients.** Upsert one `sub_clients` row per company-type customer keyed `(company_id, qb_id)` with `...subClientFieldsFromCustomer(toShape(cust))` and the same QBO lifecycle state as the parent. Runs for linked **and** created parents; null for individuals, contact-less companies, and QB Jobs.
3. **STEP 2 — Estimate + invoice headers.** Upsert on `(company_id, qb_id)` with QB-authoritative `subtotal`/`tax_amount`/`tax_rate`/`total`; status via `mapEstimateStatus`/`deriveInvoiceStatus` (provisional). Doc number falls back to `QB-<qb_id>`; `issue_date` sent only when QB supplies `txn_date` (else `CURRENT_DATE` default — never null); invoice `due_date` falls back to `txn_date`. Voided/zero-total invoices (`derived_status = 'skipped'`) are never applied.
4. **STEP 3 — Line items (delete-by-parent, then reinsert).** QBO `ItemRef.value/name` is carried into `qbo_staging_line_items.qb_item_id/qb_item_name`, then `qbo_item_product_mappings` resolves the line to an OPS `product_id`, `type`, `task_type_ref`/`task_type_id`, `unit`, and `unit_id` when a mapping exists. QBO remains the source of truth for description, quantity, unit price, amount, and tax. Unmapped ItemRefs still import as lines, but the run records a non-fatal "QuickBooks item mapping needed" warning. `line_total` is omitted (GENERATED column on `line_items`).
5. **STEP 4 — Payments.** One OPS `payments` row per applied invoice line, composite `qb_id = "<paymentQbId>:<invoiceQbId>"`, upsert on `(company_id, qb_id)`. A later QBO import for the same raw payment voids any old composite payment rows no longer present in QBO's latest `applied_lines`, so edited/unapplied QBO payments cannot leave stale OPS paid amounts behind. Each insert/update/void runs under QuickBooks-origin suppression before invoice balance triggers fire.
6. **STEP 5 — Reconcile invoices to QB Balance.** `amount_paid = round(total − balance, 2)`, `balance_due = balance`, `status = deriveInvoiceStatus(...)`, `paid_at` set when `balance <= 0` — aligning OPS to QB's authoritative `Balance`.

### Company → client + contact → sub_client mapping

A QB Customer with a `CompanyName` imports as a **parent `clients` row (named the company) + a `sub_clients` contact (the person)**; individuals stay flat. (bug `d6951b82`, 2026-06-04.) The shaping is two pure helpers in `qbo-normalize.ts`, used as the **single source of truth by BOTH `applyImport` and the inbound webhook** so a customer can never import two different ways:

- **`normalizeCustomer`** derives `company_name` (`CompanyName`), `display_name` (`DisplayName`), `contact_name` (`GivenName`+`FamilyName`, falling back to `DisplayName` **only** when it is a real person — differs from the company name, contains no `:` path, and is not a Job), `is_job` (`Job === true`), `parent_qb_id` (`ParentRef.value`). `contact_title` is always `null` (QB `Title` is a salutation, not a job role).
- **`clientFieldsFromCustomer(c)`** → `{name, email, phone_number, address}`. Company **with** a contact (`company_name` + `contact_name` + not a Job): `name = CompanyName`, `email`/`phone_number = null` (they move to the contact), `address` kept. Contact-less company: `name = CompanyName`, email/phone kept on the client. Individual: `name = display_name` (else `"QuickBooks customer"`), all kept.
- **`subClientFieldsFromCustomer(c)`** → contact row, or `null` for individuals (no `company_name`), contact-less companies (no `contact_name`), and **all QB Jobs** (`is_job === true`).
- **Invoices/payments attach to the parent client only** — there is no `sub_client_id` on the money tables; the contact is metadata.
- **QB Jobs / sub-customers are recorded, not acted on** (`parent_qb_id`, `is_job` captured in staging; surfaced as a non-blocking review flag) — they do not become projects or contacts this phase.

### Field mappings, matching & shared helpers

`qbo-normalize.ts` (pure QB→OPS shaping), `qbo-match.ts` (match resolver), `qbo-reconcile.ts` (review aggregation) — all pure, no I/O.

**Customer / Invoice / Estimate / Payment / line mappings** (selected; full source in `qbo-normalize.ts`):

| OPS staging | QB source |
|---|---|
| customer `address` | `BillAddr` joined `"Line1, City, CountrySubDivisionCode PostalCode"` |
| invoice `subtotal` | `SubTotalLineDetail` line `Amount` |
| invoice/estimate `tax_amount` / `tax_rate` | `TxnTaxDetail.TotalTax` / `TaxLine[0].TaxLineDetail.TaxPercent` |
| invoice `total` / `balance` | `TotalAmt` / `Balance` |
| invoice `estimate_qb_id` | `LinkedTxn[]` where `TxnType = "Estimate"` |
| estimate `txn_status` | `mapEstimateStatus`: Accepted→approved, Closed→converted, Rejected→declined, Pending→sent/expired |
| payment `applied_lines[]` | per `Line[].LinkedTxn[TxnType="Invoice"]` → `{invoice_qb_id, amount, reference_number}` |
| line `name` / `qty` / `unit_price` / `amount` | `Description ?? ItemRef.name`, `Qty` (def 1), `UnitPrice` (def 0), `Line.Amount ?? qty*unitPrice` |
| line `is_taxable` | `TaxCodeRef.value` present and `!= "NON"` |
| line `qb_item_id` / `qb_item_name` / `qb_item_type` | `ItemRef.value`, `ItemRef.name`, and the Item.Id→Item.Type map |

Only `SalesItemLineDetail` lines are kept (`GroupLineDetail` flattened; `SubTotal`/`Discount`/`DescriptionOnly` skipped). Invoices are **skipped** when `total <= 0` (zero_total) or voided (`Voided === true` / `PrivateNote` contains "voided"). Header totals are **not** recomputed from lines — they come from QB; the staging tables store a non-generated `amount` per line (the GENERATED `line_total` is only on the live `line_items` apply target).

**Match algorithm** (`resolveCustomerMatch`, fed `company_name ?? display_name` as the match name):

1. **Email exact** (trim/lowercase) → `link`, `high`.
2. **Normalized-name exact** (`normalizeCompanyName`: suffix-strip/lowercase/alphanumeric) — single hit → `link`, `medium`; multiple → `needs_review`, `medium`.
3. **Fuzzy** (`pg_trgm` ≥ 0.6 via RPC `qbo_match_customer_candidates`, only called when no email hit) → `link`, `low`.
4. **No match** → `create`, `none`.

`match_basis` ∈ {email, name_exact, name_fuzzy, none}; `proposed_action` ∈ {link, create, skip, needs_review}. (Note: the RPC ranks on raw `lower(name)` while the in-process exact step uses suffix-stripped `normalizeCompanyName` — a deliberate asymmetry.)

**Reconciliation & counts** (`qbo-reconcile.ts`): `buildReconciliation` → `qbOpenAr` (Σ open balances), `openInvoiceCount`, `collectedInWindow` (Σ applied-line amounts), `opsToBeOpenAr = qbOpenAr` (QB authoritative), `arMatched`. `buildStagedCounts` → `subClientsToCreate` (company + contact, **excluding Jobs**) and `jobsDetected` (`is_job === true`), mirroring the helper's Job exclusion.

### Schema

All staging/run/match data is service-role-written; the `qbo_*` tables expose only company-scoped `SELECT` gated on `accounting.view`. The `qbo_*` tables are **web-only / service-role** staging (not iOS SwiftData models), so they are catalogued here rather than in `03_DATA_ARCHITECTURE.md`; the additive columns on iOS-synced tables (`sub_clients.qb_id`, the `qb_id` link columns) are noted in `03_DATA_ARCHITECTURE.md`.

- **`qbo_import_runs`** — one row per cycle: `connection_id`, `provider_environment` CHECK ∈ {production, sandbox}, `status` CHECK ∈ {pending, pulling, staged, applying, applied, error}, `qb_write_calls` (must stay 0), `history_cutoff`, `totals jsonb`, `error`, `created_by`, `finished_at`. Staging/match tables FK `run_id → qbo_import_runs(id) ON DELETE CASCADE`.
- **`qbo_staging_customers`** — `qb_id`, `display_name`/`email`/`phone`/`address`, `active`, `raw jsonb`, **+ `company_name`, `contact_name`, `contact_title`, `parent_qb_id`, `is_job`** (added for the company/sub-client mapping). UNIQUE `(run_id, qb_id)`.
- **`qbo_staging_invoices`** — `qb_id`, `doc_number`, `customer_qb_id`, `estimate_qb_id`, `txn_date`, `due_date`, `subtotal`/`tax_amount`/`tax_rate`/`total`/`balance`, `derived_status`, `raw`. UNIQUE `(run_id, qb_id)`.
- **`qbo_staging_estimates`** — like invoices + `expiration_date`, `txn_status`. UNIQUE `(run_id, qb_id)`.
- **`qbo_staging_line_items`** — `parent_type` CHECK ∈ {invoice, estimate}, `parent_qb_id`, `qb_line_id`, `name`/`description`, `quantity`/`unit_price`/`amount`, `is_taxable`, `qb_item_id`, `qb_item_name`, `qb_item_type`, `sort_order`. **PK only** (no `(run_id, qb_id)` unique; re-running uses a fresh `run_id`).
- **`qbo_staging_payments`** — `qb_id`, `customer_qb_id`, `txn_date`, `total_amt`, `unapplied_amt`, `applied_lines jsonb` (per-invoice allocations), `raw`. UNIQUE `(run_id, qb_id)`.
- **`qbo_customer_matches`** — `customer_qb_id`, `proposed_action` CHECK ∈ {link, create, skip, needs_review}, `matched_client_id`, `match_basis` CHECK ∈ {email, name_exact, name_fuzzy, none}, `confidence` CHECK ∈ {high, medium, low}, `candidates jsonb`, `decided_action`/`decided_client_id` (reviewer overrides). UNIQUE `(run_id, customer_qb_id)`.
- **`accounting_connections`** (direction guard + environment split): `provider_environment text NOT NULL DEFAULT 'production'` CHECK ∈ {production, sandbox}; uniqueness is `(company_id, provider, provider_environment)` so one company can hold separate production and sandbox QuickBooks connections. A partial unique index permits only one connected, sync-enabled, non-`pull_only` QuickBooks row per `(company_id, provider)`, and settings writes downgrade the sibling environment before enabling Full CRUD. `sync_direction text NOT NULL DEFAULT 'pull_only'` CHECK ∈ {pull_only, push_only, bidirectional} (a CHECK-constrained text column, **not** a Postgres enum); `realm_id_lookup text` (SHA-256 hex of the realm id — `realm_id` itself is encrypted/unqueryable). `company_id` is **text** here (cast `::text` in joins).
- **`qbo_item_product_mappings`** — company-owned, service-role-written mapping from QBO ItemRef to OPS product: `company_id`, optional `connection_id` (connection-specific mapping wins; company-level null fallback is allowed), `qb_item_id`, `qb_item_name`, `qb_item_type`, `product_id`, `match_source`, `last_seen_at`, timestamps, soft delete. Active uniqueness is `(company_id, connection_id, qb_item_id) WHERE deleted_at IS NULL`. Authenticated clients have `SELECT` only; anon has no grant; service_role has full table access.
- **`qbo_estimate_opportunity_links`** — service-role-owned bridge for QBO-created estimates that did not originate from an OPS estimate. Unique `(company_id, connection_id, qb_estimate_id)`, stores `opportunity_id`, optional `estimate_id`, `client_id`, QBO doc metadata, and timestamps. The RPC `ensure_qbo_estimate_opportunity(p_company_id, p_connection_id, p_client_id, p_qb_estimate_id, p_estimate_id, p_estimate_number, p_title, p_total)` runs under `service_role`, takes an advisory transaction lock, reuses or creates one quoted opportunity, and backfills the link with the OPS estimate id once available.
- **`accounting_sync_queue`** (full-CRUD outbound): trigger-owned queue for OPS-originated client/contact/invoice/estimate/payment/line-item changes. The active pending uniqueness key is `(company_id, connection_id, provider, entity_type, entity_id, operation, idempotency_key) WHERE status='pending'`, so sandbox and production connections cannot suppress each other's queued work. `enqueue_accounting_sync()` only selects a QuickBooks connection when `is_connected=true`, `sync_enabled=true`, and `sync_direction <> 'pull_only'`; QuickBooks-originated webhook/import writes are suppressed through `accounting_sync_suppressions`. `sub_clients` changes enqueue the parent `client_id` as the customer entity while preserving the changed contact row id in `payload_snapshot.sourceRowId`; sub-client tombstones enqueue a customer update, while parent client tombstones enqueue QBO customer inactivation. Estimate tombstones enqueue QBO estimate `delete`, invoice/payment tombstones enqueue QBO voids, all gated by `propagate_deletes`.
- **`notifications` accounting issue dedupe**: unread notification dedupe includes `dedupe_key` when present: `(user_id, company_id, type, coalesce(dedupe_key, title)) WHERE is_read=false AND resolved_at IS NULL`. This prevents one QuickBooks sync issue from suppressing unrelated sync issues of the same notification type.
- **Idempotency indexes** — partial unique `(company_id, qb_id) WHERE qb_id IS NOT NULL` on `clients`, `invoices`, `estimates`, `payments`, **and `sub_clients`** (`sub_clients_company_qb_id_uniq`). `sub_clients.qb_id` is nullable text — non-QB contacts (the majority) keep `qb_id = NULL` and never collide.
- **RPC** `qbo_match_customer_candidates(p_company_id uuid, p_name text, p_threshold numeric DEFAULT 0.6)` — SQL, `SECURITY DEFINER`, returns ≤10 ranked active-client candidates where `similarity(lower(name), lower(p_name)) >= 0.6` (requires `pg_trgm`).

**RLS.** All seven `qbo_*` tables + `accounting_connections` have RLS enabled and carry a `{public}`/anon `SELECT` policy `company_id = (SELECT private.get_user_company_id()) AND has_permission((SELECT private.get_current_user_id()), 'accounting.view', 'all')` (so the anon-role web client can read the review; `accounting_connections` casts company to text and stores only ciphertext). There are deliberately **no** anon write policies — all writes go through the service role. `sub_clients` keeps its existing `company_isolation` ALL policy.

### Routes, OAuth/token security & inbound webhook

All routes under `src/app/api/integrations/quickbooks/`:

| Route | Methods | Purpose |
|---|---|---|
| `route.ts` | POST / DELETE | OAuth initiate (build Intuit authorize URL + store CSRF state) / authenticated disconnect (revoke + clear tokens for the selected `provider_environment`) |
| `callback/route.ts` | GET | Exchange auth code → tokens, persist **encrypted**, set `sync_direction='pull_only'`, `sync_enabled=false` |
| `import/route.ts` | POST / GET | Pull→stage→match (`POST` → `{ runId }`) / review aggregate (`GET ?runId=`) |
| `import/apply/route.ts` | POST | **Background job (2026-07-04):** validate + scope, mark the run `applying`, open a **persistent** `accounting_import_complete` rail notification, respond `202 { status:'applying', runId }`, then run the apply in Next `after()` and resolve that same notification to a completion (or failure) state. The review UI polls run status instead of blocking on the write, so the operator can navigate away. The apply engine/mappers are unchanged. |
| `webhook/route.ts` | POST | Inbound Intuit change-event receiver (unauthenticated, signature-verified) |

`src/middleware.ts` excludes `api` from its matcher, so Intuit's unauthenticated webhook reaches the route directly; the authenticated OAuth-initiate/disconnect/import/apply routes self-gate (`verifyAdminAuth` → `findUserByAuth` → company-scope (+ run-ownership for apply/review) → `checkPermissionById(userId, "accounting.manage_connections")`). Disconnect accepts optional `providerEnvironment: "production" | "sandbox"` so the UI can clear the exact QuickBooks row the operator is looking at; it returns 404 when no matching row is updated instead of reporting a no-op as success.

**One active provider per company (2026-07-04).** A trade business runs one accounting system; two live connections would give the sync engine conflicting write targets. Both the QuickBooks and Sage OAuth **initiate** routes and their **callbacks** call `findConflictingActiveProvider` (`src/lib/api/services/accounting-connection-guard.ts`) and refuse — initiate returns `409 { conflictingProvider }`, the callback aborts before token exchange — when a *different* provider is already `is_connected`. Same-provider rows never conflict (a sandbox+production pair, or re-authorising the current provider). This is the server-side half of the single-entry-point connect UI (Books SYNC segment + Settings › Accounting), which already hides the second provider once one is connected.

- **Token-at-rest encryption** (`token-cipher.ts`): AES-256-GCM, envelope `enc:v1:<iv>:<tag>:<ciphertext>` (base64), key from env `QB_TOKEN_ENC_KEY` (base64, must decode to 32 bytes). **Fail-closed** — `getKey()` throws on missing/invalid key, so a token can never be silently persisted in plaintext. `decryptToken` tolerates legacy plaintext (no `enc:v1:` prefix returned as-is). `realmIdLookup(realmId) = SHA-256 hex`.
- **Centralized token read** (`accounting-token-service.ts`): `getValidToken(supabase, connectionId)` reads `provider_environment`, decrypts + refreshes with the matching credential bundle within a 5-min pre-expiry buffer; refresh retries once on 429/5xx; `400 invalid_grant` → flips `is_connected=false` and throws `ReconnectRequiredError`. Raw provider bodies are never logged.
- **`sync_direction` enforcement:** `POST /api/sync` returns `409` for a `pull_only` connection and `202 queue_managed` for QuickBooks write-enabled connections; the legacy sync orchestrator no longer emits QuickBooks push results. The outbound queue is the only QuickBooks write path once `ACCOUNTING_WRITE_ENABLED=true` and the connection is `sync_enabled=true` with `sync_direction <> 'pull_only'`.
- **Outbound full-CRUD worker** (`api/cron/accounting/quickbooks/push-queue`): service-role/cron-secret only. Invoice void uses `POST /invoice?operation=void` with `{Id, SyncToken}`. Payment void uses `POST /payment?operation=update&include=void` with `{Id, SyncToken, sparse:true}`. Estimate delete uses `POST /estimate?operation=delete` with `{Id, SyncToken}`; estimate void has no supported QBO void operation and stays `needs_review`. Payment create/update writes back the canonical local `paymentQbId:invoiceQbId` after successful QBO finalization, so moving a payment to a different invoice cannot leave the old composite key. If a provider write succeeds but queue finalization fails, the worker terminally marks that exact claimed row `needs_review` with `external_id` and never schedules a retry, preventing duplicate accounting writes.
- **Outbound customer payload mapping** (2026-06-30, `qbo-push-mappers.ts` `mapClientToQboCustomer`, commit `ccd63ccb`): `CompanyName`/`DisplayName` = `clients.name`; `GivenName`/`FamilyName` come from the primary `sub_clients` contact, falling back to a whitespace split of `clients.name` when no contact exists; `PrimaryEmailAddr`/`PrimaryPhone` prefer the contact then the client. `BillAddr` is parsed from the free-form `clients.address` into structured `Line1`/`City`/`CountrySubDivisionCode`/`PostalCode`/`Country` (trailing tokens classified country→postal→region; the full street is always retained in `Line1`; single-token addresses stay `Line1`-only). Replaces the prior payload that emitted only `DisplayName` + one unparsed `BillAddr.Line1`.
- **Worker scheduling** (2026-06-30, commit `07b1d587`): the push-queue route is registered in `OPS-Web/vercel.json` crons at `*/5 13-23,0-4 * * *`. Before this it existed but was unscheduled, so the queue drained only on manual `POST`/test invocation (which is why outbound sync silently stalled between manual runs); outbound writes still require `ACCOUNTING_WRITE_ENABLED=true`.
- **Inbound webhook** (`webhook/route.ts` + `quickbooks-webhook-apply-service.ts`): verifies base64 `HMAC-SHA256(rawBody)` keyed by the active profile's verifier token (`QB_WEBHOOK_VERIFIER_TOKEN` or `QB_SANDBOX_WEBHOOK_VERIFIER_TOKEN`) against the `intuit-signature` header with `timingSafeEqual` (fail-closed: missing verifier → 500, bad/missing signature → 401). Routes by `realm_id_lookup` + active `provider_environment`. For changed `Customer`/`Invoice`/`Payment`/`Estimate` it GET-fetches the one record (`fetchEntityById`, asserts `qbWriteCalls === 0`) and applies it via the **same** canonical mapping as `applyImport` (`applyCustomer` writes both `clients` and a contact `sub_clients`, including `Active=false` tombstones and `Active=true` reactivation; invoice/estimate line replacement uses QBO ItemRef→OPS product mapping). Delete/Void are soft: invoice→`status='void'`, customer→`deleted_at` on both parent client and mirrored contact, estimate→`deleted_at`, and payment→matching OPS payments `voided_at` (matching both direct `qb_id` and composite `<paymentQbId>:<invoiceQbId>` rows, with invoice/payment suppressions before the balance trigger fires). Payment updates also void stale composite rows no longer present in QBO's latest split and reconcile affected invoices back to QBO `Balance`. Accepted QBO estimates (`TxnStatus='Accepted'`) are treated as `approved`: OPS ensures a QBO estimate→opportunity link, writes the mapped line items, then calls `accept_estimate_to_job_from_quickbooks`. If any ItemRef lacks a product mapping, the webhook returns `needs_review` with `missingQboItemMappings` even when the estimate row itself is stored; mapped accepted estimates proceed to project/task/material-demand creation. Verified requests always `200 {received, processed}` (per-entity errors caught + logged to `accounting_sync_log` so a poison record can't trigger Intuit's retry storm); all responses send `Cache-Control: no-store`. **Never writes to QB.**

**Env vars:** production uses unsuffixed `QB_CLIENT_ID`, `QB_CLIENT_SECRET`, `QB_REDIRECT_URI` (default `${appUrl}/api/integrations/quickbooks/callback`), and `QB_WEBHOOK_VERIFIER_TOKEN`; sandbox uses `QB_SANDBOX_CLIENT_ID`, `QB_SANDBOX_CLIENT_SECRET`, optional `QB_SANDBOX_REDIRECT_URI` (falls back to `QB_REDIRECT_URI`), and `QB_SANDBOX_WEBHOOK_VERIFIER_TOKEN`. The single switch is `QB_ACTIVE_PROFILE=production|sandbox` (legacy `QB_ENVIRONMENT` still works as fallback). Financial push line fallback mirrors the same split: production may use unsuffixed `QBO_FALLBACK_SERVICE_ITEM_ID` / `QBO_FALLBACK_SERVICE_ITEM_NAME`, while sandbox may override with `QBO_SANDBOX_FALLBACK_SERVICE_ITEM_ID` / `QBO_SANDBOX_FALLBACK_SERVICE_ITEM_NAME` (legacy `QB_*` aliases remain accepted). `QB_TOKEN_ENC_KEY` is the shared 32-byte base64 token-encryption key and fails closed. Sage shares the same connection table/token service/cipher and is scoped as `provider_environment='production'`.

### Review UI & access control

The **"QuickBooks Import"** tab of `/accounting` (`src/app/(dashboard)/accounting/page.tsx`, `?tab=import`) renders `QuickBooksImportTab` (`src/components/accounting/qbo/`), composing `reconciliation-strip.tsx` + `customer-match-table.tsx`. Data flows through `use-qbo-import.ts` (review/apply) and `use-accounting.ts` (connection).

- **PULL** → `useStartImport` → `POST …/import` (`startImportRun` → `pullAndStage` → `computeCustomerMatches`). Header shows connection dot, last-pulled time, and a read-only badge: olive "0 — read-only confirmed" when `qbWriteCalls === 0`, rose "{n} — read-only breach" otherwise.
- **Review** → `useImportReview(runId)` polls `GET …/import?runId=`. Renders: the **reconciliation strip** (QB-vs-OPS open A/R [the only independent pair], open-invoice count, collected-24mo, customers — olive when equal to the cent, rose on delta); the **records grid** (estimates/invoices/payments/line items/skipped/orphans) with a **non-blocking jobs flag** when `jobsDetected > 0`; the **customer match table** — name cell shows `companyName ?? displayName` with a **contact sub-line** (`qbo.customers.contactLabel`) when both company + contact exist, an action `<select>` offering link/create/skip (`needs_review` is a disabled, system-proposed value — never an operator choice), and a candidate picker for link/needs_review rows.
- **APPLY** → `useApplyImport` → `POST …/import/apply` with `{ runId, decisions }`. **Hard-blocked while any decision is still `needs_review`** (inline `qbo.needsReviewBlock` hint). The apply route inserts the completion notification server-side and invalidates the Books queries.
- **Permission gating (never role-filtered):** route access to `/accounting` requires `accounting.view`; the Import + Integrations tabs require `accounting.manage_connections`; all three import routes re-check `accounting.manage_connections` server-side. The whole surface is also behind the global `accounting` feature flag (currently `enabled=false`; per-user `feature_flag_overrides` unlock it) — both flag and permission must pass; the flag store fails closed.
- **i18n:** all strings under the `qbo.*` namespace in `src/i18n/dictionaries/{en,es}/accounting.json` (at parity), via `useDictionary("accounting")`.

### Migrations (repo files)

| File | Contents |
|---|---|
| `20260602000000_qbo_readonly_sync_a0_schema.sql` | 7 `qbo_*` tables + RLS, `accounting_connections.sync_direction`, owner flag override |
| `20260602100000_qbo_match_customer_candidates_rpc.sql` | `qbo_match_customer_candidates` `pg_trgm` RPC |
| `20260602200000_qbo_qb_id_unique_indexes.sql` | partial `(company_id, qb_id)` unique indexes on clients/invoices/estimates/payments |
| `20260603000000_qbo_realm_lookup.sql` | `accounting_connections.realm_id_lookup` + index |
| `20260603010000_accounting_connections_read_policy.sql` | anon `SELECT` policy on `accounting_connections` (fixes bug `eb70d803` — connected-but-shows-NOT-CONNECTED) |
| `20260603100000_qbo_company_subclient_mapping.sql` | `sub_clients.qb_id` + partial index; staging-customer `company_name`/`contact_name`/`contact_title`/`parent_qb_id`/`is_job` |
| `20260606062000_qbo_provider_environment.sql` | `provider_environment` on `accounting_connections` + `qbo_import_runs`; unique `(company_id, provider, provider_environment)` |
| `20260607070000_qbo_sync_queue_connection_scope.sql` | queue pending uniqueness includes `connection_id`; enqueue requires `sync_enabled=true` |
| `20260607071000_notifications_dedupe_key_scope.sql` | unread notification dedupe scopes by `dedupe_key` when present |
| `20260607073000_qbo_subclient_queue_parent_entity.sql` | `sub_clients` contact changes enqueue the parent customer `client_id` |
| `20260607174000_qbo_item_product_mapping.sql` | QBO ItemRef→OPS product mapping table; staging line ItemRef columns; locked line replacement accepts product/task/unit metadata |
| `20260607174500_qbo_item_product_mapping_acl_hardening.sql` | hardens mapping table grants to anon none, authenticated SELECT only, service_role full |
| `20260607175000_qbo_estimate_opportunity_link.sql` | QBO-created estimate→opportunity link table and service-role `ensure_qbo_estimate_opportunity` RPC |
| `20260607175500_qbo_mapping_link_index_hardening.sql` | direct FK-covering indexes for QBO import-run connection, item mapping connection, estimate-link connection, and estimate-link estimate references |
| `20260608010000_qbo_estimate_delete_operation.sql` | extends queue/audit operation checks with `delete`; maps estimate tombstones to QBO estimate delete while invoices remain void |
| `20260608011000_qbo_subclient_delete_updates_customer.sql` | maps sub-client tombstones to parent customer update instead of QBO customer inactivation |
| `20260608012000_qbo_single_writable_connection.sql` | enforces one connected, sync-enabled, non-`pull_only` QuickBooks row per company/provider |

Live apply status must be verified during rollout. Supabase MCP records its own apply-time version in `supabase_migrations.schema_migrations`, so tracked versions can differ from these filenames — **treat the repo files as canonical**. Every migration is additive (nullable columns / new tables / new indexes / CHECK replacement), hence iOS-sync-safe and idempotent. Archived in `migrations/`.

---

## Site-visit cloud sync contract (production database live 2026-08-02)

**Release status:** migrations `20260731235533_site_visit_cloud_sync.sql`, `20260802093608_site_visit_completion_rpc_security_boundary.sql`, and `20260802102853_site_visit_fk_indexes.sql` are applied in production and mirrored in this Bible. Production-generated web database types include the new tables and RPC. The iOS implementation remains outside customer distribution pending its signed device/App Store gate.

### `public.complete_site_visit_guarded(p_site_visit_id uuid, p_completion jsonb) → jsonb`

One transaction owns completion and its timeline effect. The public Data API function is SECURITY INVOKER and delegates to a pinned SECURITY DEFINER implementation in `private`, which is not exposed through the Data API. The private function validates an allowlisted, bounded completion object (`notes`, `measurements`, `photos`, `internal_notes`), locks the visit, authorizes through the existing Firebase-aware site-visit edit helper, requires exact caller-company equality, rejects deleted/cancelled visits, refreshes legacy notes/measurements/photos from normalized children, moves status monotonically to `completed`, and preserves the first `completed_at`.

If the visit has an opportunity, client, or project parent, the transaction inserts or updates its single `activities(type='site_visit', site_visit_id=visit.id)` row and writes the resulting id to `site_visits.activity_id`. Partial unique index `activities_site_visit_completion_uidx` and `ON CONFLICT (site_visit_id) WHERE type='site_visit'` make retry after an interrupted response idempotent. Return shape: `{ "visit": <site_visits row>, "activity_id": <uuid|null> }`. Execute is granted only to `anon, authenticated`; the function has a pinned search path. Callers: `ops-ios/OPS/Network/Supabase/Repositories/SiteVisitRepository.swift` and `ops-web/src/lib/api/services/site-visit-service.ts`.

### `POST /api/uploads/presign` — `targetType=site_visit`

Site-visit media uses the existing authenticated presign endpoint with a closed target contract:

- request: canonical lowercase `siteVisitId` and `artifactId`, `variant` in `original | rendered | thumbnail`, approved image MIME type, and `fileSize` from 1 byte through the exact 10 MiB endpoint maximum;
- the request cannot supply `folder`; the server resolves the Firebase bridge identity, rate-limits the actor, requires a canonical UUID company id, and reads the active visit through the user's scoped Supabase client with exact `(id, company_id)` equality;
- unauthorized lookup failures are non-revealing (`403` authorization failure or `404` unavailable); the phone never receives another tenant's path;
- derived key: `site-visits/{company_uuid}/{site_visit_uuid}/{artifact_uuid}/{variant}.{ext}`;
- backend: the existing S3 or Supabase-storage presign implementation; the artifact row is updated only after upload success.

Account deletion invokes `eraseSiteVisitPrefix(companyId)` after the transactional database purge. It paginates and deletes only `site-visits/{company_uuid}/`, rejects out-of-prefix results and partial deletes, and is idempotent on an empty prefix. There is deliberately no server-side upload receipt, delivery, event, queue, or outbox table.

### Mobile transport and reconciliation

`SiteVisitPersistenceCoordinator` commits local model mutations and their `SyncOperation` rows atomically. Dependencies enforce parent → artifacts/checklist/identity → media → completion. `SiteVisitOutboundSync` maps each operation to `SiteVisitRepository`; `InboundProcessor` and `RealtimeProcessor` fetch/subscribe to all four tables; `SiteVisitServerMerge` preserves unsent dirty fields while accepting authoritative server state. The local queue is retry machinery only and is encrypted into `SiteVisitRecoveryVault` during forced logout; it is not a Supabase company-data table.

The iOS outbound media boundary (code commit `b3795976`) matches the route's
10 MiB limit without altering durable source evidence. Files already within the
limit upload byte-for-byte. Only an oversized raster is decoded into an
ephemeral outbound JPEG, capped to a 2,048 px longest edge and stepped down
until it is at most 10 MiB; the phone-local original is never overwritten.
Newly rendered annotation composites use the same bounded JPEG policy before
being saved for upload. If preparation cannot prove a compliant image, the
operation fails visibly while the original remains on the phone.

For a non-2xx presign response, iOS accepts operator-facing detail only from an
exact JSON `{ "error": string }` envelope. It collapses whitespace and limits
the detail to 240 characters; HTML and other arbitrary response bodies are not
surfaced or persisted as error text.

### Approval-controlled historical site-visit settlement (local source only, 2026-08-21)

Code commit `59f14bd8` adds a deliberately non-automatic recovery boundary for
the five audited, pre-incident, server-unlinked visits. It is not wired into
`SyncEngine`, launch/reconnect sweeps, the retry timer, or PENDING WORK's RETRY
ALL action. The exact immutable manifest is:

| Visit | Expected server status | Permitted outcome |
|---|---|---|
| `984c6847-2ac6-4bf3-a56e-9eb08f120fdf` | `in_progress` | Recover active link |
| `b1e9cea3-4c1a-4247-8a1f-c21aa721bbe2` | `in_progress` | Recover active link |
| `0de1fc17-61d8-4b23-8534-27f7a529b1ce` | `in_progress` | Recover active link |
| `4e73b982-c7ad-4303-9f1f-680b26edc10e` | `scheduled` | Recover active link |
| `df4016c4-6269-49d1-aec2-76e7934600c2` | `completed` | Settle device history only |

`HistoricalSiteVisitSettlementEvidence` derives the target opportunity only
from the retained phone visit and the complete matching unresolved queue
envelopes, then requires exact visit/company/relationship identity, active
same-company target, row-scoped edit capability, no in-flight operation, and a
fresh server bundle at the manifest's exact status/version. Any missing,
foreign, extra, duplicate, already-linked, deleted, stale, or conflicting
evidence fails closed. `prepare` binds those facts and the exact operation ids
into a deterministic approval digest; `execute` accepts only an approval that
repeats every immutable plan identity.

For the three in-progress visits and one scheduled visit, execution performs a
single-row compare-and-set of `site_visits.opportunity_id` only, filtered by the
exact id, company, status, `updated_at`, `deleted_at IS NULL`, and
`opportunity_id IS NULL`. A full server relationship readback must agree before
only the captured phone operations are re-armed. The completed visit never
enters a server mutation path: fresh server content must fingerprint exactly
against the retained phone packet, after which only rejected local relationship
intent and the exact queue operations are accounted as locally settled with
`serverConfirmedAt = nil`. File-protected prepared/applied receipts make both
paths auditable and idempotent. This mechanism has not been executed against
the five live visits; customer settlement remains a separately approved,
one-visit-at-a-time operation.

Checklist answers reconcile by active logical identity
`(site_visit_id, field_id)`, not UUID alone. When Supabase returns the same
logical answer under a canonical UUID different from the phone's provisional
UUID, the merge migrates the one local active answer and every unresolved queue
operation/routing envelope to the canonical identity atomically. The complete
incoming bundle is validated before mutation. Duplicate active logical rows,
canonical-ID queue collisions, unknown operation lifecycles/types, or malformed
tenant/visit/entity routing fail closed into recovery instead of choosing a row
or overwriting local evidence. Source:
`ops-ios/OPS/Network/Sync/SiteVisitServerMerge.swift` (code commit `a6a49da7`).

`SiteVisitRepositoryError.server` preserves the PostgREST `code`, `message`,
`detail`, and `hint` and exposes all four through `LocalizedError`. The sync
classifier still reads the typed code/message to decide transient, permanent,
or auth disposition, while Pending Work retains the same full operator-facing
failure text rather than collapsing it to a generic transport message.
Source: `ops-ios/OPS/Network/Supabase/Repositories/SiteVisitRepository.swift`.

### Reusable checklist templates (production backend/web live 2026-08-06)

Migration `20260806103000_site_visit_checklist_templates.sql` adds `public.site_visit_types` for reusable company checklists. Its field JSON is bounded to 1–100 unique, nonblank definitions, requires at least one shown field, allowlists the eight supported field kinds, and caps the encoded document at 128 KiB. Partial unique indexes enforce one active row per company/slug and at most one active default. All members of the exact company can read; insert/update requires `settings.company`; authenticated/anonymous app roles cannot hard-delete. Service role retains hard-delete for eventual account closure. The table publishes full-row Realtime changes.

iOS routes the entity through `SiteVisitTypeRepository`, `InboundProcessor`, `OutboundProcessor`, `RealtimeProcessor`, and `DataActor`. Settings mutations are local-first `SyncOperation` writes. One merge rule accepts authoritative server columns except fields still covered by a pending local operation. Template deletion is a tombstone. Per-visit `site_visit_checklist_answers` stay independent snapshots, so a definition change cannot mutate completed or already-answered visits.

Operator UI is `Settings → Operations → Site Visit Types` and requires `settings.company`. The editor can create a type, choose the default, add/reorder fields, select field kinds, set required, and show/hide each field. The Site Visit type chooser ends with an `EDIT TYPES` route to the same screen. On the first eligible Site Visit open, a user-scoped guide points to this location with `NOT NOW` and `NEVER SHOW AGAIN`; opening Settings also suppresses future prompts.

Rollout order is strict: apply the migration; regenerate live database types and the live company-data scope snapshot; add `site_visit_types` to the export/account-closure manifest; deploy the compatible web contract; then distribute the signed iOS client. The first four gates completed on 2026-08-06: production migration version `20260806211208`, live-derived scope/privilege snapshots, lifecycle manifest/tests, and OPS-Web production commit `7e41c289`. Verified iOS source is published on `main` at `fd6d6e7d`; all eight focused checklist/settings simulator tests pass. Signed device/App Store distribution remains pending and must not be inferred from the source push.

## Site-visit booking RPCs (production live 2026-08-11)

**Release status:** migrations `20260810194251_site_visit_booking.sql` (columns, indexes, trigger gate), `20260811053942_site_visit_booking_rpcs.sql` (the three functions), and `20260811054117_site_visit_booking_trigger_fn_acl.sql` (trigger-function grant hygiene) are applied in production and mirrored in `migrations/`. Design: `specs/2026-08-10-site-visit-booking-calendar-design.md`.

These three RPCs are the **only** write path for a booking on any surface — iOS, OPS-Web, and the future MCP tools. Every side effect (timeline activity, stage nudge, Google Calendar enqueue) is centralized in them, so no caller can produce a divergent visit and a new surface inherits the full behavior for free. All three are `security definer` with a pinned `search_path`, resolve the actor through the `complete_site_visit_guarded` pattern (`private.get_current_user_id()` / `private.get_user_company_id()` match the JWT `sub` against `users.auth_id` OR `users.firebase_uid` — `auth.uid()` is unusable under the Firebase bridge), and authorize through the existing `private.current_user_can_edit_site_visit` boundary (granular permission, never a role name).

Booking columns and the `booked_at` discriminator are documented in `03_DATA_ARCHITECTURE.md` § 22.

### `public.book_site_visit(p_opportunity_id uuid, p_scheduled_at timestamptz, p_duration_minutes int default 60, p_assignee_ids text[] default null, p_reminder_lead_minutes int default null) → uuid`

Locks the opportunity `for update`, asserts the edit boundary and exact company equality, then validates: `p_scheduled_at > now() - interval '5 minutes'`; duration 15–480; reminder override null or 0–1440; every assignee a parseable UUID belonging to an undeleted user in the caller's company (empty/NULL array defaults to the booker alone, deduplicated and sorted). The **one-open-booking rule** rejects a second booking only while an existing booked visit on that opportunity is `status='scheduled'` — once it is `in_progress`, `completed`, or `cancelled` the slot is free (booking a follow-up while on site is legal).

On success it inserts the visit (`status='scheduled'`, `booked_at=now()`, `created_by=actor`), inserts one `activities` row (`type='site_visit_scheduled'`, subject `Site visit booked`, content the ISO-8601 UTC appointment time, `site_visit_id` linked), nudges the opportunity from `new_lead` to `qualifying` via `public.move_opportunity_stage` (only from `new_lead`), and returns the new visit id. Google Calendar enqueue is **not** performed here — the deployed `trg_site_visits_google_calendar_sync` trigger observes exactly the writes these RPCs make.

### `public.reschedule_site_visit(p_site_visit_id uuid, p_scheduled_at timestamptz, p_duration_minutes int default null, p_assignee_ids text[] default null, p_reminder_lead_minutes int default null) → uuid`

Only a **booked** (`booked_at IS NOT NULL`), still-`scheduled` visit can move — a started visit is history, not a plan. NULL keeps a field unchanged; `p_reminder_lead_minutes = -1` is the explicit **clear** sentinel for the per-booking override (NULL means "leave as is", so a separate sentinel is required). Logs a `site_visit_scheduled` activity (`Site visit rescheduled`). The changed `scheduled_at` re-arms every prompt by construction because dedupe keys carry the epoch. An identical call writes nothing (idempotent).

### `public.cancel_site_visit_booking(p_site_visit_id uuid) → uuid`

Flips a booked visit to `cancelled` (which fires the trigger's remote `delete`), then **neutralizes any still-pending `create`/`update` queue rows** for that visit to `status='skipped'`, `skip_reason='booking_cancelled'` — a cancelled booking must never materialize remotely by draining stale work enqueued moments earlier. Logs a `site_visit_scheduled` activity (`Site visit cancelled`). Cancelling an already-cancelled booking is a no-op success; a completed or already-started visit is refused.

### Error contract (SQLSTATE → meaning)

Clients map these to presentable errors rather than parsing message text. `ops-web/src/lib/api/services/site-visit-service.ts` raises `SiteVisitBookingError`; `ops-ios/OPS/Services/SiteVisitBookingService.swift` maps to terse operator copy.

| SQLSTATE | Raised as | Meaning |
|---|---|---|
| `22004` | `opportunity_id_required`, `scheduled_at_required`, `site_visit_id_required` | Missing required argument |
| `42501` | `site_visit_actor_not_found`, `site_visit_edit_denied`, `site_visit_company_mismatch` | Unresolvable actor, permission denied, or cross-company attempt |
| `P0002` | `opportunity_not_found`, `site_visit_not_found` | Target row absent (or invisible to this tenant) |
| `22023` | `site_visit_time_in_past`, `site_visit_duration_out_of_range`, `site_visit_reminder_out_of_range`, `site_visit_assignees_invalid` | Argument failed validation |
| `55000` | `site_visit_already_booked`, `site_visit_not_a_booking`, `site_visit_not_reschedulable`, `site_visit_already_started`, `cannot_cancel_completed_site_visit`, `cannot_cancel_deleted_site_visit`, `cannot_reschedule_deleted_site_visit` | State rule violated |

## Review-stack rail RPC + task INSERT..RETURNING fix (2026-08-17)

Two prod contract changes landed together (migrations `20260818014340_project_tasks_returning_visibility.sql`, `20260818014657_review_stack_notification_rpc.sql` — archived in `migrations/`, byte-exact against the ledger).

### `public.sync_review_stack_notification(p_stack text, p_count integer) → text`

The **only** creation path for the three iOS review-stack rail notifications (`task_review_stack`, `payment_review_stack`, `unscheduled_review_stack`) — the notification-creation hardening (§14, `07_SPECIALIZED_FEATURES.md`) revoked app-role INSERT on `notifications`, and the legacy client-side insert in `ReviewThresholdService` died `42501` on every launch from 2026-07-17 until this fix (bug `88a0a1e3`).

`security definer`, pinned `search_path`, granted to `anon` + `authenticated`. Narrow by construction: recipient is always the resolved actor (self-notification only), company derives from the actor's row, copy is a fixed server-side template per stack kind (the clamped non-negative count is the only caller data that reaches the row), `type` is constrained to the three stack kinds, and rows carry `deep_link_type` only (`taskReview` / `paymentReview` / `unscheduledReview`) — `action_url` stays NULL because these are phone-workflow surfaces and the `notification_action_url_internal` CHECK forbids the legacy `ops://` scheme anyway.

Semantics (all server-owned; threshold = 5): count ≥ 5 → insert one persistent unread row unless one already stands (`created` / `kept`, at-most-one-unread dedupe under a per-user+stack advisory xact lock); count < 5 → mark unread rows of that stack read (`cleared` / `noop`) so the rail clears without user action. Raises `42501` (no actor), `22023` (unknown stack). iOS caller: `NotificationRepository.syncReviewStack(stack:count:)` from `ReviewThresholdService.evaluate` after each sync, reporting honest counts including zero.

### `project_tasks` INSERT..RETURNING no longer self-voids

`role_scope_read` (RESTRICTIVE SELECT) used to call `private.current_user_can_view_task(id)`, which re-fetches the task row by id — invisible under the statement snapshot during the INSERT's own RETURNING evaluation, so **every** PostgREST task insert with `Prefer: return=representation` (iOS `TaskRepository.create` = `.insert().select().single()`) failed `42501` regardless of permissions, rolling back the just-created task (bug `06810537`). The policy now evaluates the candidate row's own columns via `private.current_user_can_view_task_row(company_id, project_id, team_member_ids, deleted_at)`; semantics are proven identical on live data (1,383 task × user parity comparisons, 0 mismatches). Full detail: `03_DATA_ARCHITECTURE.md` § "project_tasks read policy".

## iOS notification-surface RPCs (2026-08-17)

Eleven narrow RPCs (migrations `20260818023254_ios_notification_surface_rpcs.sql` + dedupe-key follow-up `20260818023657_measurement_notification_dedupe_keys.sql` — archived in `migrations/`, byte-exact against the ledger) close bug `e302355c`: the twelve iOS notification surfaces that kept direct-INSERTing `notifications` after the 2026-07-15 hardening and died `42501` silently. One RPC per surface shape, all `security definer` with pinned `search_path`, granted to `anon` + `authenticated` (revoked from `service_role` — the service lane keeps its own creators). Shared doctrine: actor from `private.get_current_user_id()`; company from the actor's row; recipients derived server-side (never caller input); fixed server-side copy templates (caller data limited to clamped counts / validated dimension integers); server-literal `type`; `action_url` internal-path-or-NULL (web click-through mirrors the live service lane: `/dashboard?openProject=<id>&mode=view`); iOS navigation via the shipped `deep_link_type` values. All raise `42501` (no actor / not authorized for the anchor row) and `22023` (invalid input or unrecorded state). iOS bindings live in `NotificationRepository` § "Narrow creation RPCs"; each call site keeps its OneSignal push lane client-side, targeted by the RPC's returned recipient ids where the server owns recipient selection.

| RPC | Surface (iOS caller) | Recipients | Returns / semantics |
|---|---|---|---|
| `sync_review_reminder_notification(p_kind, p_count, p_threshold_days=null)` | AppState periodic reminders (`projects_needing_tasks` "TASKS MISSING" / `stale_estimate_review` "Stale Estimates") | actor (self) | `created`/`kept`/`noop`; at-most-one-unread per kind under an advisory lock; cadence stays client-side (UserDefaults window — the reminder-frequency knobs have no server columns) |
| `sync_overdue_invoice_notifications()` | AppState `checkOverdueInvoices` | `users_with_permission(company,'invoices.record_payment','all')` minus actor, active only | `text[]` of ids that received NEW rows; overdue set computed server-side (mirror of `Invoice.isOverdue`: due date passed at UTC-midnight, `balance_due > 0`, status ≠ void); copy `N invoices overdue totalling $X`; stable per-company `dedupe_key` + 24h per-recipient window; push targets the returned ids |
| `notify_share_photos_finalized(p_project_id, p_photo_count)` | Share-extension `SharePhotoFinalizer` | actor (self) | `created`/`noop`; type `photo_uploaded`; project title from the project row; count clamped 1..500; replaces the constraint-invalid `ops://` action_url |
| `notify_note_created(p_note_id)` | `ProjectNotesViewModel` + `PhotoCommentsViewModel` after note create | mentions from `project_notes.mentioned_user_ids`; photo note → owner from `project_photos.uploaded_by`; plain note → `projects.team_member_ids` minus author minus mentioned | jsonb `{kind, mention_user_ids, photo_owner_id, team_user_ids}` = recipients that received NEW rows; actor must BE the note's author; system-event notes never notify; idempotent per note (`note_id` anchor + per-note `dedupe_key`s); types `mention` / `photo_comment` / `project_note` with the shipped iOS copy templates |
| `notify_expense_batch_decision(p_batch_id, p_decision, p_count=null)` | `ExpenseViewModel.notifySubmitter` after `approve_expense_batch` / send-back flow / `mark_expense_batch_paid` | `expense_batches.submitted_by` (skip self/inactive) | `created`/`noop`; actor must hold `expenses.approve` all-scope AND the decision must be recorded on the batch row (status / amendment / `paid_at`); types `expense_approved`/`expense_rejected`/`expense_paid`, batch vocabulary copy, per-batch+decision `dedupe_key`; web is NOT this lane (web dispatches its own service-lane notification after the shared operation RPCs) |
| `notify_time_off_decision(p_event_id)` | `CalendarUserEventRepository.updateStatusWithNotification` | event row's requester (skip self) | `created`/`noop`; event must be `time_off` with recorded `approved`/`denied` and the actor as its `reviewed_by`; per-event+status `dedupe_key` |
| `notify_project_photos_added(p_project_id, p_photo_count)` | `ImageSyncManager` crew broadcast | `projects.team_member_ids` minus actor, active only | `text[]` of ids that received NEW rows; type `photo_uploaded`, uploader name + project title from server rows; push targets the returned ids |
| `sync_threshold_alert_notification(p_count)` | `InboundProcessor` end-of-sync inventory reconcile | actor (self) | `created`/`kept`/`cleared`/`noop`; persistent review-stack shape — at-most-one-unread, zero clears; copy `// N ITEMS BELOW THRESHOLD`, `catalogOrders` deep link, REVIEW label, `action_url` NULL |
| `notify_measurement_captured(p_project_id, p_kind, …dims)` | `DimensionedPhotoSyncManager` (LiDAR spec §6) | actor (self) | `created`/`noop`; kind `opening` (width/height/sill + window/door) or `wall_section` (feet/inches); server renders the spec-verbatim body (`<PROJECT> · 36″×60″ WINDOW · SILL 28″` / `WALL SECTION · 14′6″ × 8′`); content-hash `dedupe_key` so distinct captures never collapse while unread (the `20260818023657` fix) |
| `sync_measurement_pending_notification(p_queue_depth)` | `DimensionedPhotoSyncManager` offline queue | actor (self) | `created`/`kept`/`cleared`/`noop`; persistent `// SYNC QUEUED` banner; depth zero clears — the auto-clear lane the legacy client never had |
| `notify_measurement_sync_failed(p_project_id)` | `DimensionedPhotoSyncManager` retries exhausted | actor (self) | `created`/`noop`; project-anchored (the annotation row may not exist server-side when the insert failed); per-project `dedupe_key` |

### iOS notification-surface RPCs — legacy call-site wave (2026-08-17)

Twenty-one further narrow RPCs (migration `20260818043043_ios_legacy_notification_surface_rpcs.sql`, archived in `migrations/`, byte-exact against the ledger) close the bug `e302355c` ADDENDUM: the twenty-nine `createNotification` call sites feature work added after the origin/main audit. Same doctrine and plumbing as the table above, with two constrained extensions: a caller-supplied id list may only SUBSET the anchor row's recorded membership (`notify_task_assigned` / `notify_project_assigned` — the "freshly added members" delta is client knowledge, but the row's `team_member_ids` bounds who is addressable), and `sync_photo_storage_limit_notification` carries the wave's one sanitized caller string (the device name — load-bearing per bug d5da3d51, undeniable server-side, sanitized/clamped, and rendered only on a row its author receives). Mutation-driven task/project surfaces are dispatched AFTER `SyncEngine.pushPending()` so the recorded state the RPC validates (task completed, schedule present, spawn rows) exists server-side; offline the call fails and is contained (best-effort parity with the direct-INSERT era). iOS bindings in `NotificationRepository` § "Legacy call-site RPCs".

| RPC | Surface (iOS caller) | Recipients | Returns / semantics |
|---|---|---|---|
| `notify_task_completed(p_task_id)` | `DataController.updateTaskStatus` | PROJECT `team_member_ids` minus actor | `text[]` of ids with NEW rows (push targets); task must be recorded `completed` (22023 otherwise); type `task_completion`; body `{actor} completed "{task}" on {project}`; dedupe `task-completed:{task}` |
| `notify_project_completed(p_project_id)` | `DataController.updateProjectStatus` | project team minus actor | `text[]`; project must be recorded `completed`; type `project_completion`; body `"{project}" has been marked as completed`; dedupe per project |
| `notify_task_rescheduled(p_task_id)` | `DataController.updateTaskSchedule` | TASK team minus actor | `text[]`; terminal tasks and missing dates 22023; type `schedule_change`, title `Schedule Update`; dedupe per task (unread-collapse) |
| `notify_dependency_ready(p_completed_task_id)` | `DataController.sendDependencyCompletionNotifications` | per dependent task: its team minus actor; dependents derived from effective deps (`dependency_overrides` array — even empty — else task type's `dependencies`; key `dependsOnTaskTypeId`) | jsonb `[{task_id, user_ids}]` created-only; type `dependency_completed`, title `Ready to start`, body `{dependent} on {project} — {completed} is complete`; dedupe per (completed, dependent) pair |
| `notify_task_assigned(p_task_id, p_user_ids=null)` | `DataController.updateTaskTeamMembers` (delta) + `ProjectFormSheet.createTask` (NULL = full crew) | input ∩ task row's `team_member_ids`, minus actor | `text[]`; type `task_assignment`; body `You've been assigned to "{task}" on {project}`; dedupe per task |
| `notify_project_assigned(p_project_id, p_user_ids)` | `ProjectFormSheet` project-only members | input ∩ project `team_member_ids`, minus actor | `text[]`; type `project_assignment`, title `Added to Project`; dedupe per project |
| `notify_task_pair_spawned(p_task_id)` | `DataController.spawnPairsForPredecessor` (after pushPending) | predecessor task's crew; fallback actor; actor NOT excluded (system-initiated info) | `text[]`; spawn must carry `paired_from_task_id` (22023); type `task_pair_spawned`, title `// NEW TASK`, body `Auto-scheduled {TYPE}[ for {Dy Mon D}] — paired from {predecessor}`; dedupe per spawn |
| `notify_schedule_run_summary(p_task_ids)` | `DataController.sendScheduleRunSummaries` (bulk auto-schedule; rows already pushed) | per-member counts from the named rows' crews, minus actor | jsonb `[{user_id, moved_count}]` created-only (push map); 1..500 ids; type `schedule_change`, title `Schedule updated`, body `{n} of your tasks was/were rescheduled`; dedupe = md5 of sorted id list |
| `notify_vinyl_order_drafted(p_project_id, p_note_id, p_ordered_sq_ft)` | `VinylOrderSheet` | actor (self) | `created`/`noop`; note must be actor's own on that project; sq ft clamped 1..1e6; type `catalog_order_drafted`, body `{PROJECT} · {N} SQ FT READY`; action_url NULL (legacy `ops://` dropped), label `REVIEW`, deep_link `catalogOrders`; dedupe per note |
| `notify_vinyl_bulk_ordered(p_marked_count)` | `VinylBulkOrderWizardView` summary | actor (self) | `created`/`noop`; type `vinyl_bulk_ordered`, body `{N} PROJECT[S] · {MMM. D}` (server clock, uppercased) |
| `notify_vinyl_offcut_banked(p_stock_unit_id, p_project_id=null)` | `VinylOffcutInventoryService` | actor (self) | `created`/`noop`; stock unit must be an offcut; ft→inch conversion + shipped inch/feet-and-inches rendering (`27" × 8' 4.5" BANKED TO STOCK`); type `standard`, action `/catalog?segment=stock` / `VIEW STOCK`; dedupe per stock unit |
| `notify_guided_setup_completed(p_kind, …counts)` | Guided product/catalog/stock setup flows | actor (self) | `created`/`noop`; kinds `product_setup` / `catalog_setup` / `stock_setup` with per-kind shipped templates (clamped counts, nonzero-part ` · ` joins); type `standard`; catalog links per kind; sum-zero and unknown kinds 22023 |
| `notify_role_assigned(p_member_id)` | `ManageTeamView.updateMemberRole` | the member (self-assign → noop) | `created`/`noop`; actor must hold `team.assign_roles` all-scope; announced role read from latest `user_roles`→`roles.name` (fallback `users.role`), preset names mapped to display case; body `You've been assigned the {Role} role`; push (`sendToUser`) only on `created` |
| `notify_team_invites_sent(p_emails, p_phones)` | `ManageTeamView` invite flow | actor (self) | `created`/`noop`; contacts count only when a fresh `team_invitations` row (invited_by=actor, <10 min, not cancelled) records them; body `Invitation sent to {c}.` / `{n} invitations sent to {c} + {n-1} more.`; action_url NULL (legacy `ops://` dropped), label `VIEW TEAM`, deep_link `team` |
| `notify_time_off_booked(p_event_id)` | `UserEventSheet` direct book | event row's user (self-booking confirms to actor) | `created`/`noop`; actor must hold `time_off.approve` all-scope; event must be recorded `approved` time_off (22023); body `Your time off for {range} is on the schedule.` / `{actor} booked you off for {range}.`; range `Mon D[ – Mon D]` UTC; push to target only when created and target ≠ actor |
| `notify_time_off_requested(p_event_id)` | `UserEventSheet` + `TimeOffRequestSheet` submit | requester = ACTOR (no creator column exists); target = event row's user; approvers = `users_with_permission(time_off.approve,'all')` minus actor minus target | jsonb `{approver_user_ids (created-only, push targets), target_notified}`; event must be recorded `pending` time_off; three fixed lanes (requester `Time Off Submitted`, on-behalf target `Time Off Submitted For You`, approvers `Time Off Request`); idempotent per event via per-lane dedupe keys checked at any read state |
| `notify_inventory_threshold_crossed(p_item_id)` | `QuantityAdjustmentSheet` post-save | `users_with_permission(inventory.manage,'all')` minus actor | `text[]` (push targets); server recomputes item-level threshold state — normal quantity returns `{}` (race-safe honest recount); types `inventory_critical`/`inventory_warning` with shipped copy (`{name} is critically low ({n} remaining)`); dedupe per item+status |
| `sync_photo_storage_limit_notification(p_photos_remaining, p_device_name)` | `PhotoPrefetchService` cap banner | actor (self, persistent) | `created`/`kept`; at-most-one-unread PER DEVICE (dedupe `photo-storage-limit:md5(device)`); device sanitized (btrim, control-strip, 64-char clamp, fallback `this device`); resolution stays client `markAllAsReadByType` |
| `sync_billable_week_notification(p_project_count, p_amount, p_week_start)` | `HomeBillableThisWeekNotificationDispatcher` | actor (self) | `created`/`kept`; actor must hold `finances.view` all-scope; week validated (−14d..+7d); at-most-one per week at ANY read state (the shipped remote-check semantics); body `{n} job[s] ready for billing` / `{n} job[s] / ${X} billable`; action_url NULL (legacy `ops://` dropped), label `OPEN HOME` |
| `sync_forecast_dip_notification(p_lowest_balance, p_week_start)` | `ForecastNotificationDispatcher` danger path | `users_with_permission(finances.view,'own')` INCLUDING actor (company condition) | `text[]` created-only; persistent; replace-unread per recipient (changed body resolves the stale row, identical body keeps it) under a company advisory lock; body `Balance drops to {[-]$X} the week of {Mon D}.`; action `/books/cashflow` / `REVIEW FORECAST`; fire cadence stays with the client `forecast_alerts` ledger |
| `sync_forecast_cleared_notification()` | `ForecastNotificationDispatcher` clear path | same audience | `text[]`; resolves ALL the company's unread `forecast_dip` rows (a persistent row must not outlive its condition — the legacy client left them dangling), then writes the non-persistent `forecast_cleared` confirmation |

## Guarded Sync-Recovery RPCs (2026-07-22)

Two prod contract changes landed with the SYNC RECOVERY initiative (migrations
`extend_create_opportunity_source_thread_key`, `create_link_deck_design_to_opportunity_guarded`
(+ ACL-hardening companion) — archived in `migrations/`; applied 2026-07-22).

### `create_opportunity_guarded` — idempotent via `source_thread_key`

`private.create_opportunity_company_serialized_internal` now allowlists and writes
`p_opportunity.source_thread_key` (nullable text; UNIQUE per
`(company_id, source_thread_key)`). When the key already exists — pre-insert
readback or `unique_violation` catch — the RPC returns the EXISTING row as
`{ok: true, conflict: true, opportunity: <row>, ...}` (same shape as success)
instead of raising, so a retried create after a lost response reconciles to one
lead. iOS senders: `ClientLeadAutocreate` (`client-autocreate:<client uuid>`) and
the site-visit direct create (`SiteVisitCaptureViewModel.createLeadFromIdentityDraft`,
same key — direct + queued paths can never duplicate). Before this change the
allowlist rejected the key (`unsupported_opportunity_field`, 22023 → HTTP 400),
which was root cause RC1 of the 2026-07-22 stuck-lead incident.

### `link_deck_design_to_opportunity_guarded(p_design_id uuid, p_target_opportunity_id uuid) → jsonb`

Sanctioned path for linking an ORPHAN deck design (opportunity_id IS NULL) to a
lead — direct PATCH of `deck_designs.opportunity_id` is blocked by
`trg_deck_designs_guard_opportunity_reparent`. SECURITY DEFINER; grants mirror
`create_opportunity_guarded` (`{authenticated, postgres}`). Mints a one-row
`private.opportunity_child_reparent_tokens` entry (NULL → target), performs the
guarded UPDATE, deletes tokens (exception-safe). Authorization:
`private.current_user_can_edit_deck_design(company, NULL, project_id, 'deck_builder.edit')`
AND `private.user_can_edit_opportunity(actor, target)`; target must be same-company,
non-archived, non-deleted. Returns `{ok, already_linked, design_id, opportunity_id}`;
re-linking the same target → `already_linked: true` (idempotent). Cross-linking a
design already on ANOTHER lead → 23514 (forbidden by design). iOS caller:
`DeckDesignRepository.linkToOpportunity` via SyncOperation operationType
`"linkOpportunity"` (payload `{"opportunity_id": <uuid>}`); a one-time
`SyncEngine.enqueueDeckDesignLinkBackfillOnce()` sweep (UserDefaults flag
`deckDesignLinkBackfill.v1`) heals designs orphaned by pre-fix builds, which
stripped `opportunity_id` from every deck-design payload (RC3).

---

## Error Handling & Retry Logic

> **2026-07-22:** outbound-push failures are now classified (transient / permanent /
> auth) with permanent rejections parking immediately — see
> `06_TECHNICAL_ARCHITECTURE.md` § "Error Handling in Sync Engine" for the full
> disposition table, the `parked` SyncOperation status, and the launch/reconnect
> recovery sweeps.

### Error Types

```swift
enum SyncError: Error {
    case notConnected
    case alreadySyncing
    case missingUserId
    case missingCompanyId
    case apiError(Error)
    case dataCorruption
    case unauthorized
}

enum UploadError: LocalizedError {
    case invalidResponse
    case invalidURL
    case presignError(statusCode: Int, message: String?)
    case s3Error(statusCode: Int)
}

enum OneSignalError: Error {
    case notAuthenticated
    case invalidEndpoint
    case invalidResponse
    case apiError(statusCode: Int, message: String)
}
```

### Retry Pattern

The OutboundProcessor uses exponential backoff: `delay = min(pow(2.0, Double(retryCount)), 60.0)` (caps at 60 seconds, max 20 retries).

Auth errors are classified by `classifySyncError()` and trigger a `.syncAuthExpired` notification instead of retrying -- the user must re-authenticate.

### Error Handling Pattern (SyncEngine)

```swift
// 1. Optimistic local update (immediate UI feedback)
project.status = newStatus
try modelContext.save()

// 2. Record the operation for outbound processing
syncEngine.recordOperation(
    entityType: "project",
    entityId: project.id,
    operationType: "update",
    changedFields: ["status"],
    previousValues: ["status": oldStatus.rawValue],
    priority: 3
)
// OutboundProcessor will push when connected, retry on failure
```

---

## Connectivity Monitoring

See [ConnectivityManager](#connectivitymanager) above for the current implementation. The previous `ConnectivityMonitor` (basic `NWPathMonitor` wrapper without quality scoring or lying WiFi detection) has been replaced.

---

## Rate Limiting & Debouncing

### Sync Debouncing

SyncEngine guards against concurrent syncs via the `syncInProgress` boolean. All sync triggers check this flag and `ConnectivityManager.shouldAttemptSync` before initiating work.

### Sync Timing Summary

| Trigger | Function | When | Data Synced |
|---------|----------|------|-------------|
| **Manual Sync** | `syncAll()` (via SupabaseSyncManager) | User taps sync button | Everything (7 steps + relationship linking) |
| **App Launch** | `syncEngine.triggerSync()` | After authentication | Full inbound pull + push pending |
| **Network Restored** | `syncEngine.triggerSync()` | Connection detected (quality >= good) | Full inbound pull + push pending |
| **User Mutation** | `syncEngine.recordOperation()` | Immediate on change | Single entity enqueued + immediate push attempt |
| **Realtime** | RealtimeProcessor WebSocket event | Push from server | Single record upsert with field-level merge |
| **Realtime Reconnect** | `syncEngine.deltaSyncSince(disconnectedAt:)` | After WebSocket reconnect | Incremental pull since disconnect timestamp |
| **Background Refresh** | BackgroundSyncScheduler (15min) | BGTaskScheduler | Push pending operations only |
| **Background Processing** | BackgroundSyncScheduler (30min) | BGTaskScheduler | Full sync + photo uploads + cleanup |

### Configuration Reference

| Setting | Value | Source |
|---------|-------|--------|
| Background refresh interval | 15 minutes | `BackgroundSyncScheduler` / `com.ops.sync.refresh` |
| Background processing interval | 30 minutes | `BackgroundSyncScheduler` / `com.ops.sync.processing` |
| Minimum sync interval | 5 minutes | `AppConfiguration.Sync.minimumSyncInterval` |
| Max batch size | 50 | `AppConfiguration.Sync.maxBatchSize` |
| Job history | 30 days | `AppConfiguration.Sync.jobHistoryDays` |
| Job future | 60 days | `AppConfiguration.Sync.jobFutureDays` |
| Status update cooldown | 2 seconds | `AppConfiguration.UX.statusUpdateCooldown` |
| Outbound backoff | `min(2^retryCount, 60)` seconds | `OutboundProcessor` |
| Outbound max retries | 20 | `OutboundProcessor` |
| Photo concurrency (WiFi) | 3 concurrent uploads | `PhotoProcessor` |
| Photo concurrency (cellular) | 1 concurrent upload | `PhotoProcessor` |

---

## Supabase Table Reference

### Core Entity Tables

| Table | Purpose |
|-------|---------|
| `companies` | Organizations/tenants |
| `users` | All app users (admins, office crew, field crew) |
| `clients` | Customers that companies serve |
| `sub_clients` | Additional contacts under a client |
| `task_types` | Work categories (Framing, Painting, etc.) |
| `projects` | Jobs/projects for clients |
| `project_tasks` | Individual tasks within projects |
| `project_notes` | Threaded notes on projects |
| `project_photo_annotations` | Photo markup annotations |
| `notifications` | In-app notification records |

### Pipeline & Financial Tables

| Table | Purpose |
|-------|---------|
| `pipeline_stage_configs` | Kanban stages per company |
| `opportunities` | Sales pipeline deals |
| `stage_transitions` | History of deal stage changes |
| `estimates` | Quotes/proposals for clients |
| `invoices` | Client billing |
| `invoice_line_items` | Individual items on invoices |
| `line_items` | Individual items on estimates |
| `products` | Reusable catalog of services/materials |
| `tax_rates` | Per-company tax configurations |
| `payments` | Payment records against invoices |
| `payment_milestones` | Deposit/milestone schedules |
| `activities` | Activity log (calls, emails, notes) |
| `follow_ups` | Scheduled follow-up reminders |
| `document_sequences` | Gapless numbering for EST-/INV- |
| `accounting_connections` | QuickBooks/Sage OAuth tokens |
| `accounting_sync_log` | Sync event log (success/error) |
| `accounting_category_mappings` | OPS category → external account mapping |
| `expenses` | Expense records with receipt images, OCR data |
| `expense_project_allocations` | Multi-project expense attribution |
| `expense_categories` | Company-configurable expense categories |
| `expense_settings` | Per-company expense policy configuration |
| `expense_batches` | Grouped expenses for batch review |

### Catalog Tables

The Catalog domain replaces the legacy `inventory_*` tables. Variant families (`catalog_items`) carry default price/cost/threshold; SKUs (`catalog_variants`) override per-variant. Recipes (`product_materials`) bridge billable Products to stockable variants. Tags now apply at the FAMILY level. Migration `2026-05-06-01-catalog-schema.sql` (RENAME inventory_* → catalog_*) and `2026-05-06-02-catalog-views-triggers.sql` (cycle-prevention trigger, base_price ↔ default_price mirror).

| Table | Purpose | RLS | Common reads/writes |
|-------|---------|-----|---------------------|
| `catalog_categories` | Nested category (parent_id self-FK, 2-level UI). `default_warning_threshold` / `default_critical_threshold` cascade to families/variants. | company_isolation | List on Catalog tab; create/edit via Categories sheet |
| `catalog_items` | Variant family — name, description, `image_url`, default price/cost/threshold, default unit. | company_isolation | List in CATALOG tab; FAB creates new family; variant sheet patches `image_url` after Storage upload to `product-thumbnails/{company_id}/{catalog_item_id}/{uuid}.jpg`; recipe rows reference via `catalog_item_id` |
| `catalog_options` | Variant axis on a family ("Color", "Mount Type"). | via `catalog_items.company_id` | Authored at family creation; rarely edited after |
| `catalog_option_values` | Selectable values for a CatalogOption. | via parent option | Same as above |
| `catalog_variants` | The SKU row — `catalog_item_id` + quantity + price/unit_cost overrides + threshold overrides + `unit_id` + sku. No variant name column; display identity derives from family + ordered option values. | via `catalog_items.company_id` | Quantity adjusts on stock changes; threshold reads cascade to family/category; option-value joins can be replaced from iOS variant editor |
| `catalog_variant_option_values` | M2M variant ↔ option_value combo. | via parent variant | Insert at variant creation; immutable after |
| `catalog_tags` | Free-form FAMILY-level label. Legacy threshold columns preserved but unused. | company_isolation | List in tag picker; CRUD via Tags sheet |
| `catalog_item_tags` | Junction family ↔ tag. | via `catalog_items.company_id` | Delete/reinsert on iOS family tag edit |
| `catalog_units` | Unit of measure (ea, ft, sqft, hour, …). Exposes `dimension` and `abbreviation`. | company_isolation | Read by family/variant editors and pricing |
| `catalog_snapshots` | Variant-aware historical stock snapshot — header. | company_isolation | Insert on manual snapshot, daily auto-snapshot |
| `catalog_snapshot_items` | One row per variant in a snapshot, denormalized `family_name` + `variant_label`. | via parent snapshot | Insert with snapshot; never edit |
| `catalog_orders` | Threshold-driven restock order. Status: `suggested` / `draft` / `sent` / `fulfilled` / `cancelled`. | company_isolation | Compute `suggested` on demand; user drafts/sends; fulfillment increments variant qty |
| `catalog_order_items` | One line per variant on an order; cost snapshotted at creation. | via parent order | Insert with order; rare edits |
| `company_inventory_settings` | Explicit company inventory mode for estimate-to-job material planning. | company_isolation + `catalog.manage` writes | `set_company_inventory_mode` toggles `off` / `tracked`; tracked mode enables projected material demand |
| `project_material_demands` | Accepted-job projected material demand. Separate from actual stock deduction. | company_isolation + same-company guards | Written by estimate-to-job material workflow; read by job planning and completion checks |
| `project_material_snapshots` | Immutable material-history header for booking, release, crew-adjustment, and task-completion states. | company_isolation + same-company guards | Inserted by material workflow; never used to mutate live stock |
| `project_material_snapshot_items` | Snapshot rows with immutable stock-unit JSON. | via snapshot company + same-company guards | Inserted with snapshots for audit/history views |
| `task_material_allocations` | Links demand/task material rows to `catalog_stock_units`. Projected rows do not deduct stock. | company_isolation + same-company guards | Projected/overrun on booking; consumed at task completion |

### Bridge & Audit Tables

| Table | Purpose | RLS | Common reads/writes |
|-------|---------|-----|---------------------|
| `product_materials` | Recipe row — variant-pinned OR family-pinned with `variant_selector` jsonb. `quantity_per_unit` per Product's `pricing_unit`. `scaled_by_option_id` for integer-kind option scaling. | via `products.company_id` | Authored on web (Product detail); read by `RecipeResolver` at install task creation |
| `task_materials` | Cut-list row pinned to a `catalog_variant_id`, written at install task creation. Carries legacy `inventory_item_id` for back-compat (null on new rows). | via `project_tasks → projects.company_id` | Insert by `CutListMaterializer`; read by task material list; deductions audit on consumption |
| `line_item_materials` | Optional per-line-item materials snapshot for one-off custom builds. | via `line_items → estimates/invoices` | Rare — manual override path only |
| `inventory_deductions` | Audit trail of actual stock movement. Projected demand never writes here. | company_isolation by `inventory_deductions.company_id` + same-company guards | Insert on task completion consumption, returns, manual adjust, or snapshot |
| `client_product_overrides` | Per-client price override for a Product. | via `clients.company_id` | Read at line-item creation when client has overrides |
| `product_tax_rates` | M2M Products ↔ tax rates (multiple jurisdictions). | via `products.company_id` | Read at line-item tax computation |
| `company_default_products` | (company_id, component_type) → product_id. Drives drawing→estimate adapter. | company_isolation | Authored once per company; read on every "Generate Estimate" action |

### Phase 6 Estimate-to-Job Material RPCs

Phase 6 moves inventory-mode and projected material planning behind server-owned functions. The iOS client must not orchestrate multi-table project, task, demand, allocation, snapshot, or notification writes.

| RPC | Status | Contract |
|-----|--------|----------|
| `public.set_company_inventory_mode(p_company_id uuid, p_inventory_mode text)` | Drafted in migration `2026-05-27-02-ios-catalog-p6-inventory-mode-and-material-demand.sql` | Derives actor via `private.get_current_user_id()`, verifies caller company, requires `catalog.manage`, upserts `company_inventory_settings`, and when mode changes from `tracked` to `off` releases open projected demand **and the `task_material_allocations` attached to it** (`2026-05-30-04`), returning `released_demands`, `released_allocations`, and `release_snapshots`. |
| `private.sync_accepted_estimate_project_tasks(p_estimate_id uuid)` | Drafted in migration `2026-05-27-03-ios-catalog-p6-estimate-acceptance-task-sync.sql` | Private helper only. Derives actor via `private.get_current_user_id()` + `auth.uid()`, verifies caller company, requires `estimates.edit`, `projects.create`, `projects.edit`, `tasks.create`, and `pipeline.manage`, reuses or creates the lead-backed project, links the accepted estimate, verifies LABOR-derived tasks, links site visits/photos, and performs no material demand work. |
| `private.resolve_estimate_material_demand_plan(p_estimate_id uuid, p_project_id uuid)` | Drafted in migration `2026-05-27-04-ios-catalog-p6-material-demand-engine.sql` | Private helper only. Reads accepted estimate lines, product recipes, product-to-catalog mappings, variants, and stock-unit availability, then returns deterministic `demands`, `warnings`, `missing_mappings`, and `overruns` JSONB without writing projected demand, notifications, stock events, or stock balances. |
| `private.persist_estimate_material_booking_projection(p_estimate_id uuid, p_project_id uuid)` | Drafted in migration `2026-05-27-05-ios-catalog-p6-booking-warnings.sql` | Private helper only. Calls the P6-4 plan inside the P6-6 acceptance transaction, uses the P6-2 `ops.project_material_workflow` and `ops.accept_estimate_to_job_rpc` guards, upserts `project_material_demands` by `demand_key`, supersedes stale projected/warning rows for the same estimate/project, releases open rows when inventory mode is `off`, writes a `booking_projection` snapshot and items, and creates only non-deductive overrun `task_material_allocations`. It emits no persistent setup notifications directly and does not mutate stock. |
| `public.accept_estimate_to_job(p_estimate_id uuid, p_idempotency_key text)` | Drafted in migration `2026-05-27-06-ios-catalog-p6-acceptance-transaction-and-mapping-notifications.sql` | Owns the full accepted-estimate transaction: approve estimate, create/update project and tasks, skip material writes when inventory mode is `off`, resolve and persist material demand only when inventory mode is `tracked`, and insert keyed persistent `catalog_mapping_needed` notifications from the P6-5 `missing_mappings` array only. It requires acceptance-adjacent estimate/project/task/pipeline permissions, not `catalog.manage`; `catalog.manage` remains the recipient filter for missing-mapping notifications. |
| `public.complete_project_task(p_task_id uuid, p_idempotency_key text, p_material_adjustments jsonb)` + `private.consume_task_materials_for_completed_task(p_task_id uuid, p_idempotency_key text, p_material_adjustments jsonb)` | Applied in migration `2026_05_28_02_ios_catalog_p6_task_completion_consumption_contract` (version `20260529062017`) from `2026-05-28-02-ios-catalog-p6-task-completion-consumption-contract.sql`; execute ACL hardened in `2026-05-29-02-ios-catalog-p6-complete-project-task-acl-hardening.sql` | Owns task-completion stock movement inside the same transaction that completes the task. The public wrapper updates `project_tasks.status = 'completed'`; the private helper derives consumable work from task-scoped `project_material_demands`, applies crew adjustments, resolves live stock units at completion, writes consumed/unavailable `task_material_allocations` evidence, writes `inventory_deductions`, writes allowed `catalog_stock_unit_events`, updates stock units without negative physical quantities, and snapshots the result. Non-inventory companies are no-op for stock movement. `EXECUTE` is granted to `anon` and `authenticated` (the app's PostgREST requests execute as `anon`); the `task_material_consumption_requests` insert/select/update policies are scoped `to public` so the anon runtime role passes RLS — authenticated-only policies silently rolled back every completion until `2026-05-30-03-ios-catalog-p6-completion-requests-anon-rls.sql`. |
| `private.resolve_catalog_mapping_needed_notifications_for_product_link()` + `private.resolve_catalog_mapping_needed_notifications_for_mapping()` | Applied in migration `2026-05-29-01-ios-catalog-p6-mapping-notification-resolution.sql` | Trigger-only P6-23 resolver contract. Product links and product-option mapping saves resolve only the exact matching keyed `catalog_mapping_needed` notifications by `dedupe_key`; actors are derived server-side, the saved row company must match `private.get_user_company_id()`, and there is no public follow-on resolver RPC. |

As of iOS Catalog OPS P6-22, the iOS task-completion path routes `TaskStatus.completed` through `TaskRepository.completeProjectTask(...)` / `public.complete_project_task` instead of patching `project_tasks.status` directly. Offline local completion still records a `.projectTask` sync operation, but outbound replay detects completed task payloads, strips the direct status patch, and calls the completion RPC with a stable per-task idempotency key plus `{}` material adjustments unless real adjusted-material data is present.

Every Phase 6 material RPC derives the actor server-side, validates `private.get_user_company_id()`, and enforces same-company integrity for projects, tasks, estimates, products, recipes, stock units, and companies. Inventory-mode management remains gated by `catalog.manage`. Estimate acceptance is not gated by `catalog.manage`; projected-demand writes are authorized by the acceptance transaction guard, same-company checks, and the live estimate/project/task/pipeline permissions listed above. Projected material rows are never actual stock deductions; only the completion RPC writes stock movement.

#### Phase 6 production hotfixes (2026-05-30)

Three corrections landed after the P6 audit. All are additive Supabase changes (safe between iOS releases):

- **`private.try_parse_uuid` regex restored.** The live function had drifted to a 4-group regex (`^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$`) that rejected every canonical (5-group) uuid, so it returned `NULL` for all valid ids. `public.accept_estimate_to_job` parses its synced project id through this helper and raises `accepted_project_id_missing` (`23514`) when it is null — so **every** estimate acceptance aborted and rolled back (clean uuid or legacy id alike), and the material-demand resolver collapsed. Restored to the canonical 5-group pattern (matching source migration `2026-05-27-04` line 35) in `2026-05-30-02-ios-catalog-p6-fix-try-parse-uuid-regex.sql`. The migration archive always carried the correct pattern; the live drift was out-of-band and is unreproducible from source control — re-running the tracked migration fixes it.
- **Completion RLS opened to the `anon` runtime role.** `task_material_consumption_requests` had RLS enabled with all three policies scoped `to authenticated`; the app executes PostgREST calls as `anon`, which inherits no `authenticated` policy, so `complete_project_task` rolled back with `42501` in every inventory mode (the status flip to `completed` precedes the failing request-row insert). Policies retargeted `to public` in `2026-05-30-03-ios-catalog-p6-completion-requests-anon-rls.sql`, matching every peer P6 write table.
- **Anon execute/table grants.** The P6 function layer + the `accept_estimate_to_job_requests` table were granted to `anon` in `2026-05-29-03-ios-catalog-p6-anon-role-grants.sql` and `2026-05-30-01-ios-catalog-p6-accept-request-anon-grant.sql` (both now tracked in `schema_migrations`).
- **Inventory-off allocation release.** When a company switched inventory mode to `off`, `set_company_inventory_mode` released its open `project_material_demands` but left the attached `task_material_allocations` dangling in `projected`/`overrun`, diverging from the demand state. `2026-05-30-04-ios-catalog-p6-inventory-off-release-allocations.sql` grafts a `released_allocations` CTE (mirroring `private.persist_estimate_material_booking_projection`'s own off-branch) into the toggle path and returns `released_allocations`.

### Configurable Product Extensions

| Table | Purpose | RLS | Common reads/writes |
|-------|---------|-----|---------------------|
| `product_options` | Knob on a Product. `kind` ∈ `select` / `integer` / `boolean`. `affects_price` / `affects_recipe` flags. `option_default_source` (e.g. `$design.color`) read by drawing adapter. | via `products.company_id` | Authored on web and iOS Product detail / Catalog Setup LINKS; read by line-item editor + adapter |
| `product_option_values` | Selectable values for `kind=select`. | via parent option | Authored on web and iOS; value parent validation is strict |
| `product_pricing_modifiers` | Price bump rule per option/value match. `modifier_kind` ∈ `add_per_unit` / `add_flat` / `add_per_count` / `multiply_unit_price`. | via parent option | Authored on web and iOS; read by `ProductConfigurationResolver` |

### Calendar Tables

| Table | Purpose |
|-------|---------|
| `calendar_user_events` | User-owned personal events and time-off requests |

**Added**: 2026-03-02 (Schedule Tab Redesign)

`calendar_user_events` columns: `id`, `user_id` (text), `company_id`, `type` (`personal` / `time_off`), `title`, `start_date`, `end_date`, `all_day`, `notes`, `status` (`confirmed` / `pending` / `approved` / `rejected`), `reviewed_by`, `reviewed_at`, `created_at`, `updated_at`, `deleted_at`, `last_synced_at`, `needs_sync`.

**RLS Special Case**: The `user_id` column is text, while `auth.uid()` returns a UUID. RLS policies on this table use `CAST(auth.uid() AS TEXT) = user_id` to avoid type mismatch failures. This is intentional and must be preserved on any schema changes.

### Row-Level Security (RLS)

All core entity tables enforce company-scoped isolation:

```sql
ALTER TABLE {table} ENABLE ROW LEVEL SECURITY;
CREATE POLICY "company_isolation" ON {table}
  FOR ALL USING (company_id = (SELECT private.get_user_company_id()));
```

This means:
- A user from Company A can never read or write Company B's data
- No application-level filtering is needed; the database enforces isolation
- The `private` schema helper function reads `auth.jwt() -> 'app_metadata' ->> 'company_id'`

### Permission-Based RLS (Migration 016)

Financial and sensitive tables have an additional **permission-based RLS layer** on top of company isolation. Both layers must pass for access. This applies to:

**Tables with permission-based RLS:**
- `invoices` — requires `invoices.view` / `invoices.create` / `invoices.edit` / `invoices.delete`
- `estimates` — requires `estimates.view` / `estimates.create` / `estimates.edit` / `estimates.delete`
- `payments` — requires `invoices.view` (read) / `invoices.record_payment` (write)
- `line_items` — requires `invoices.view OR estimates.view` (read), corresponding create/edit/delete
- `accounting_connections` — requires `accounting.view` (read) / `accounting.manage_connections` (write)
- `expenses` — requires `expenses.view` / `expenses.create` / `expenses.edit`
- `expense_project_allocations` — tied to parent expense visibility
- `expense_categories` — requires `expenses.view` (read) / `expenses.approve` (write)
- `expense_settings` — requires `expenses.view` (read) / `expenses.approve` (write)
- `expense_batches` — requires `expenses.view` (read) / `expenses.approve` (write)

**Core operational tables** (projects, tasks, clients, calendar_events) do NOT have permission-based RLS — they rely on company isolation + client-side gating. Over-restricting these at the DB level causes poor UX (empty pages instead of access-denied redirects).

**Permission check helper** (cached per transaction for performance):

```sql
CREATE OR REPLACE FUNCTION private.current_user_has_permission(
  p_permission app_permission
) RETURNS boolean LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = '' AS $$
DECLARE
  v_user_id uuid;
BEGIN
  -- Try cached user ID from session variable
  v_user_id := current_setting('app.current_user_id', true)::uuid;

  -- If not cached, resolve and cache for this transaction
  IF v_user_id IS NULL THEN
    v_user_id := (SELECT private.get_current_user_id());
    IF v_user_id IS NULL THEN
      RETURN false;
    END IF;
    PERFORM set_config('app.current_user_id', v_user_id::text, true);
  END IF;

  RETURN public.has_permission(v_user_id, p_permission);
END;
$$;
```

**Example policy pattern** (invoices):
```sql
CREATE POLICY "invoices_select" ON invoices FOR SELECT USING (
  company_id = (SELECT private.get_user_company_id())
  AND private.current_user_has_permission('invoices.view')
);

CREATE POLICY "invoices_insert" ON invoices FOR INSERT WITH CHECK (
  company_id = (SELECT private.get_user_company_id())
  AND private.current_user_has_permission('invoices.create')
);
```

### Permission Tables RLS

The permission system tables (`roles`, `role_permissions`, `user_roles`) have their own RLS:
- **Read**: Anyone can read preset roles; company members can read their custom roles
- **Write**: Only users with `team.assign_roles` permission can modify roles and assignments
- **Preset protection**: `NOT is_preset` check prevents modification of preset roles

---

## Bubble.io (Legacy)

### Status

Bubble.io was the original backend for OPS. As of February 2026, the iOS app has been migrated to Supabase as the primary backend. Bubble references remain in the codebase in the following areas:

**Still referenced** (but being phased out):
- `BubbleFields.swift` -- field name constants used in some DTO mappings and onboarding code
- Some onboarding workflows still reference Bubble field names (visible in `OnboardingManager.swift`; the old `OnboardingViewModel.swift` is dead post-2026-06-13 rebuild and awaits deletion)
- Inventory-related DTOs and views still contain `bubble_id` references for backwards compatibility
- `CoreEntityDTOs.swift` contains `bubble_id` fields on Supabase DTOs for migration mapping

**No longer used**:
- The `CentralizedSyncManager` (Bubble-backed sync) has been replaced by `SupabaseSyncManager`
- Direct Bubble REST API calls for CRUD operations have been replaced by Supabase repository methods
- Image registration with Bubble has been replaced by presigned URL uploads to S3 + direct Supabase updates

### Legacy API Details

For historical reference, Bubble used:

**Base URL**: `https://opsapp.co/version-test/api/1.1/`
**Authentication**: Static API token (Bearer token, not user-specific)
**Data API Pattern**: `GET/POST/PATCH /api/1.1/obj/{dataType}`
**Workflow API Pattern**: `POST /api/1.1/wf/{workflowName}`

---

## Bubble-to-Supabase Migration API

### Overview

The migration API is a **one-shot bulk data transfer** endpoint that copies all entity data from Bubble.io into the corresponding Supabase core entity tables. It was used during the transition period while both backends coexisted.

**Endpoint**: `POST /api/admin/migrate-bubble`
**Source File**: `ops-web/src/app/api/admin/migrate-bubble/route.ts` (~1,134 lines)
**Authentication**: Requires `devPermission === true` on the requesting user's Bubble record
**Trigger**: Developer Settings tab in the web app (only visible when `devPermission` is true)

### Migration Process (10 Phases)

The migration executes in **strict dependency order** (parents before children) so that foreign key references can be resolved:

```
Phase 1:  Companies        -> builds companyIdMap
Phase 2:  Users            -> builds userIdMap (uses companyIdMap)
Phase 3:  Clients          -> builds clientIdMap (uses companyIdMap)
Phase 4:  Sub-Clients      -> uses clientIdMap + companyIdMap
Phase 5:  Task Types       -> builds taskTypeIdMap (uses companyIdMap)
Phase 6:  Projects         -> builds projectIdMap (uses companyIdMap + clientIdMap)
Phase 7:  Calendar Events  -> builds calendarEventIdMap (uses companyIdMap + projectIdMap)
Phase 8:  Project Tasks    -> uses projectIdMap + taskTypeIdMap + calendarEventIdMap + companyIdMap
Phase 9:  OPS Contacts     -> standalone (no company scope)
Phase 10: Pipeline Refs    -> updates _ref columns using all IdMaps
```

### IdMap Pattern (bubble_id to UUID)

Every entity uses **upsert on `bubble_id` conflict**, making the migration safe to re-run:
- First run: INSERT new rows
- Subsequent runs: UPDATE existing rows (matched by `bubble_id`)
- No duplicates, no data loss

### Post-Migration Steps

1. **User Admin Flag Update**: Sets `is_company_admin = true` for users in company admin_ids
2. **Project Team Member Computation**: Collects unique team_member_ids from tasks and writes to projects
3. **Pipeline Reference Updates (Phase 10)**: Updates `_ref` UUID columns on pipeline tables

### Error Handling

- Each entity migration is wrapped in a try/catch
- Individual record failures are logged but do not abort the entire migration
- The `stats.errors` array accumulates error messages
- The migration returns partial stats even on failure

---

## Email Pipeline Integration Routes (24 Routes)

The Email Pipeline system adds 24 API routes across 6 route groups. All routes live in `OPS-Web/src/app/api/`. Unless noted, all routes use `getServiceRoleClient()` with `setSupabaseOverride()` for Supabase access (bypassing RLS). All long-running routes set `maxDuration = 300` (5 min, Vercel Pro limit).

### 1. POST /api/integrations/email/analyze

**Purpose:** Starts wizard Step 2 inbox analysis — pattern detection + AI classification.

| Field | Value |
|-------|-------|
| Auth | Service role (no user auth check — connectionId ownership implied) |
| Request body | `{ connectionId: string, companyId: string }` |
| Response | `{ jobId: string }` |
| Service calls | `EmailService.getConnection()`, `PatternDetectionService.detect()`, `EmailAIClassifier.classifyBatch()`, `EmailAIClassifier.analyzeThreads()`, `EmailMatchingServiceV2.match()` |

**Behavior:** Creates a `gmail_scan_jobs` row with status `pending`, then runs analysis in the background via `after()` (Next.js background task). Phases: analyzing_sent → detecting_platforms → classifying_ai → analyzing_threads → complete. On error, sets status to `error` with `error_message`. On success, writes `result` JSONB with `{ estimatePattern, estimatePatternConfidence, estimateThreadCount, detectedSources, companyDomains, teamForwarders, leads: AnalyzedLead[], totalScanned }`.

### 2. GET /api/integrations/email/analyze-status

**Purpose:** Polls analysis job progress for the wizard Step 2 UI.

| Field | Value |
|-------|-------|
| Auth | Service role (no user auth check) |
| Query params | `jobId` (required) |
| Response | `{ jobId, status, progress: { stage, message, percent }, result?: object, error?: string }` |
| Service calls | Direct Supabase query on `gmail_scan_jobs` |

**Behavior:** Returns the current state of the analysis job. `result` is only included when `status === "complete"`. `error` is only included when `status === "error"`.

### 3. POST /api/integrations/email/import

**Purpose:** Imports confirmed leads from wizard Step 4. Creates clients, opportunities, activity records, and thread links.

| Field | Value |
|-------|-------|
| Auth | Service role |
| Request body | `ImportPayload: { connectionId, companyId, leads: ImportLead[] }` |
| Response | `ImportResult: { clientsCreated, leadsCreated, activitiesLogged, labelsApplied, errors: string[] }` |
| Service calls | `EmailService.getConnection()`, `ClientService.createClient()`, `OpportunityService.createOpportunity()`, `OpportunityService.createActivity()`, `EmailMatchingServiceV2.match()`, provider `applyLabel()` |

Each `ImportLead` has: `id, threadId, clientName, clientEmail, clientPhone?, stage, description?, estimatedValue?, action ("create" | "link" | "create_subclient"), existingClientId?, mergeWithLeadId?`.

**Behavior:** For each lead: resolves or creates client (with merge/link/subclient logic), creates opportunity with AI-detected stage, inserts `opportunity_email_threads` junction row, creates email activity record, applies "OPS Pipeline" label to the Gmail/M365 thread. Opportunity titles are generated from customer identity only via `OPS-Web/src/lib/email/opportunity-title.ts`; wizard-provided `lead.title`, email subjects, company names, and AI summaries are never persisted as `opportunities.title`. Imported estimate leads use the customer-based form `"{customerName} — Estimate"`. The AI summary remains in `description` and is mirrored to `ai_summary` after creation.

**Direct inbound webhook (`POST /api/integrations/email-webhook`)**: Legacy parsed inbound email webhook inserts opportunities with `title` generated from safe sender identity (`"{customerName} — Email Inquiry"`). The webhook passes the matched company name, email, and website domain into the unsafe identity filter so company/operator senders fall back to `New Lead` instead of becoming the opportunity title. The inbound `subject` is not a title source; it is context only. The body is stored in `description` with the existing 5,000-character cap.

### 4. POST /api/integrations/email/activate

**Purpose:** Saves sync profile, creates "OPS Pipeline" label, sets up webhook, activates ongoing sync. Called by wizard Step 5.

| Field | Value |
|-------|-------|
| Auth | Service role |
| Request body | `ActivationPayload: { connectionId, companyId, syncIntervalMinutes, syncProfile: SyncProfile }` |
| Response | `{ ok: true, labelId, webhookActive: boolean, syncIntervalMinutes }` |
| Service calls | `EmailService.getConnection()`, `EmailService.updateConnection()`, provider `listLabels()`, `createLabel()`, `setupWebhook()` |

**Behavior:** Creates/finds "OPS Pipeline" label in user's inbox, sets up Gmail Pub/Sub watch or M365 subscription for push notifications, saves sync profile to `sync_filters` column (with `wizardCompleted: true`), sets connection status to `active`.

### 5. POST /api/integrations/email/manual-sync

**Purpose:** Triggers a manual sync cycle. Called by user button, webhook push, or internal API.

| Field | Value |
|-------|-------|
| Auth | Service role |
| Request body | `{ connectionId?: string, companyId?: string, source?: string }` |
| Response | `{ ok: true, source, connectionsProcessed, results: SyncResult[] }` |
| Service calls | `SyncEngine.runSync()` |

**Behavior:** If `connectionId` is provided, syncs that single connection. If `companyId`, syncs all active connections for that company. Each `SyncResult` contains `{ connectionId, activitiesCreated, newLeads }`. Sync-created opportunity titles and canonical contact names use the shared mailbox-name authority boundary. Parsed contact-form and operator-confirmed names are authoritative; a full name after an explicit same-sender authored sign-off outranks a provisional header; mailbox handles/local-parts never become canonical identity or title text. Sent-folder safety-net leads evaluate the external recipient and never the operator sender. Stronger same-email name evidence can promote the canonical opportunity/client name and its OPS-generated title through provenance-checked enrichment; human titles remain protected. Subjects remain activity/thread context.

### 6. POST /api/integrations/email/draft

**Purpose:** Generates an AI draft reply for a pipeline lead using memory + writing profile. Feature-gated behind `ai_email_memory`.

| Field | Value |
|-------|-------|
| Auth | Service role |
| Request body | `{ companyId, userId, opportunityId, checkOnly?: boolean }` |
| Response (checkOnly) | `{ available: boolean, confidence: number, draft: "", sources: [], reason?: string }` |
| Response (generate) | `DraftGeneratorResult: { draft, confidence, sources }` |
| Service calls | `AdminFeatureOverrideService.isAIFeatureEnabled()`, `WritingProfileService.getProfile()`, `DraftGenerator.generateDraft()` |

**Behavior:** When `checkOnly: true`, returns availability without calling the LLM — checks feature gate and writing profile confidence (requires ≥50%, ~100+ emails). When generating, fetches opportunity + client + last inbound email, calls `DraftGenerator` which uses the writing profile + memory facts + knowledge graph to produce a contextual reply draft.

### 6a. POST /api/integrations/email/analyze-memory (Phase C entry)

**Purpose:** Kicks off the Phase C pipeline — extracts business intelligence from classified email threads, populates `agent_memories` + `agent_knowledge_graph` + `agent_writing_profiles`. Fire-and-forget from Phase B completion; background via `after()`.

| Field | Value |
|-------|-------|
| Auth | Service role |
| Request body | `{ jobId, connectionId, companyId }` (UUIDs) |
| Response | `{ ok: true }` or `{ skipped: true }` (feature gate) |
| Max duration | 800s (Vercel) |
| Service calls | `AdminFeatureOverrideService.isAIFeatureEnabled()`, `EmailService.getConnection()`/`getProvider()`, `MemoryService.initPhaseCPipelineState()`/`runPhaseCChunks()`, `finalizePhaseC()` |
| File | `OPS-Web/src/app/api/integrations/email/analyze-memory/route.ts` |

**Feature gate:** `phase_c` (renamed from `ai_email_memory`). Route short-circuits with `{ skipped: true }` when disabled.

**Chunked pipeline architecture:** A single invocation cannot reliably finish Phase C for non-trivial inboxes (hundreds of threads × per-thread gpt-4o-mini extraction call + DB upserts). The route instead:

1. **Bootstrap (entry only):** Read Phase B `leads` + `notLeadReasons` off `gmail_scan_jobs.result`, re-fetch every referenced thread from Gmail (concurrency 5, retry-with-backoff 3×), classify each thread into `{ classification, profileType, messages[] }`, build the `PhaseCPipelineState`, persist to `gmail_scan_jobs.result.phaseCPipeline`.
2. **Entity resolution (once per pipeline):** Deterministic DB-upsert pass over ALL threads — fast, no LLM — sets `state.entityResolutionDone = true`, persists.
3. **Chunked extraction:** Process `CHUNK_SIZE = 12` threads per chunk. Each thread = one gpt-4o-mini call + downstream upserts (~3–8s). After each chunk, persist `state.startIndex` advanced to the next unprocessed thread, then re-check the `CHUNK_TIME_BUDGET_MS = 550_000` in-call budget. If exhausted, yield (persist + dispatch continuation); otherwise continue.
4. **Finalize:** When `runPhaseCChunks` returns `done: true`, call `finalizePhaseC()` — build writing profiles, strip `phaseCPipeline`/`phaseCError` from `result`, write `phaseCComplete: true` + `phaseCStats`, fire the completion notification.

**Time budgets:** `maxDuration = 800s` per Vercel invocation; `CHUNK_TIME_BUDGET_MS = 550_000` leaves ~250s headroom for either the finalize path (writing-profile gpt-4o-mini calls, ~45–60s with concurrency 2) or a continuation dispatch.

**Row-level execution lock:** Both entry and continuation handlers wrap the pipeline invocation in `acquirePhaseCLock(…, "entry" | "continuation")` / `releasePhaseCLock()`. On contention (another runner already holds an unexpired lock), the route logs and returns without retrying — duplicate dispatches (webhook retry, user double-click on retry, overlapping entry routes) are treated as benign since the holding runner carries progress forward. Lock release happens inline before dispatching the next continuation (so the next runner can acquire immediately) AND in an outer `finally()` as a crash safety net. The outer release is idempotent because `release_phase_c_lock` is fenced by holder ID. See `03_DATA_ARCHITECTURE.md` → `gmail_scan_jobs` → Phase C lock RPC functions, migration `070_phase_c_row_lock.sql`, and helper `OPS-Web/src/lib/api/services/phase-c-pipeline-helpers.ts`.

**Error marker:** On exception, the route writes `result.phaseCError = { message, at, stage: "entry" | "continuation", failedAtIndex }` via `writePhaseCError()` WITHOUT clearing `phaseCPipeline`. The wizard UI reads `(phaseCError && phaseCPipeline)` as "indexing paused — retry", and a user-initiated retry re-POSTs `/analyze-memory`, which detects the existing `phaseCPipeline` and dispatches a continuation from `state.startIndex` — no re-processed threads. This diverges from Phase B's error pattern on purpose: Phase B writes `status: "error"` and treats failure as terminal; Phase C has a native resume path via the chunked pipeline, so `status` is left alone (Phase B owns that column) and only `result.phaseCError` is marked. `finalizePhaseC()` strips `phaseCError` on success, so a stale error from a prior failed attempt can't mislead the wizard.

**Resume-on-reentry:** If entry is called and `priorResult.phaseCPipeline` already exists (e.g. a prior invocation wrote it before crashing), entry releases its own lock and dispatches `/analyze-memory-continue` rather than re-running bootstrap. If `priorResult.phaseCComplete` is true, both handlers skip immediately.

### 6b. POST /api/integrations/email/analyze-memory-continue (Phase C continuation)

**Purpose:** Resumes a chunked Phase C run from `gmail_scan_jobs.result.phaseCPipeline.startIndex`. Fired by the entry route and by itself (self-dispatch) whenever a single invocation's budget is exhausted before all threads are processed.

| Field | Value |
|-------|-------|
| Auth | Service role |
| Request body | `{ jobId, connectionId, companyId }` (UUIDs) |
| Response | `{ ok: true }` or `{ skipped: true }` (feature gate) |
| Max duration | 800s (Vercel) |
| Service calls | `AdminFeatureOverrideService.isAIFeatureEnabled()`, `MemoryService.runPhaseCChunks()`, `finalizePhaseC()` |
| File | `OPS-Web/src/app/api/integrations/email/analyze-memory-continue/route.ts` |

**Behavior:** Reads `priorResult.phaseCPipeline` (typed as `PhaseCPipelineState`) off the job row — no parameters travel in the POST body beyond the ID triple. Continuation:

1. Acquire the Phase C row lock as `continuation:<uuid>` (return if held by another runner).
2. Load state; if `phaseCComplete` already set, skip. If `phaseCPipeline` missing, log and abort (entry route may have failed during bootstrap — user must retry).
3. Call `runPhaseCChunks(companyId, state, { chunkSize: 12, timeBudgetMs: 550_000, persistState })` which resumes at `state.startIndex`. Returns `{ done, state: finalState }`.
4. If `done`, re-read `priorResult` (to capture concurrent writes) and call `finalizePhaseC()`. Otherwise release the lock inline, then fire-and-forget `dispatchPhaseCContinuation(jobId, connectionId, companyId)`.

**Finalize behavior** (`finalizePhaseC` in `OPS-Web/src/lib/api/services/phase-c-pipeline-helpers.ts`):

- Builds per-relationship-type writing profiles via `MemoryService.buildWritingProfiles()` — a concurrency-2 work-stealing pool over the accumulated `emailsByProfileType` map. Serialized finalize was ~90s for 9 profile types; two workers bring it to ~45s, well inside the ~250s finalize headroom. Concurrency is explicitly capped at 2 (defined as `CONCURRENCY = 2` at `memory-service.ts:1078`) to mirror `email-ai-classifier.ts` and stay inside OpenAI tier-1 rate limits (~30k TPM on gpt-4o-mini; each profile call is ~4–6k tokens). Work-stealing (vs lock-step batching) matters because 2-sample vs 10-sample analyses have wide latency variance.
- Writes `result.phaseCStats = { factsExtracted, entitiesCreated, edgesCreated, profilesBuilt, profilesByTypeStats, processingTimeMs, threadsProcessed }` and sets `phaseCComplete: true`.
- Strips both `phaseCPipeline` (several-MB JSONB working buffer — leaving it in place would bloat every future read of the job row) and `phaseCError` (stale markers from prior failed attempts).
- Inserts a standard `notifications` row — `type: "mention"`, `title: "Indexing complete"`, `body: "<N> data points captured"`, `action_url: "/intel"`.

### 7. POST /api/integrations/email/webhook/gmail

**Purpose:** Receives Gmail Pub/Sub push notifications and triggers sync.

| Field | Value |
|-------|-------|
| Auth | None (Gmail Pub/Sub sends unauthenticated; always returns 200) |
| Request body | Gmail Pub/Sub notification: `{ message: { data: base64({ emailAddress }) } }` |
| Response | `{ ok: true }` |
| Service calls | Internal fetch to `/api/integrations/email/manual-sync` (fire-and-forget) |

**Behavior:** Decodes the Pub/Sub payload to get the email address, looks up active connections for that email, debounces (skips if synced within last 30 seconds), then triggers manual-sync for each matching connection. Always returns 200 to avoid Pub/Sub retries.

**OIDC token verification:** Pub/Sub push requests are authenticated via a Google-signed OIDC token in the `Authorization: Bearer …` header. The route decodes the token, verifies the signature against Google's JWKS, then strict-equals (`===`) the `aud` claim to `GOOGLE_PUBSUB_PUSH_AUDIENCE` and the `email` claim to `GOOGLE_PUBSUB_SERVICE_ACCOUNT`. Mismatch → 401 dropped silently; Pub/Sub treats 401 as "don't retry" (correct for auth-misconfig cases, wrong for transient ones — acceptable tradeoff here).

**Env var hygiene:** All three Gmail webhook env vars (`GOOGLE_PUBSUB_TOPIC`, `GOOGLE_PUBSUB_PUSH_AUDIENCE`, `GOOGLE_PUBSUB_SERVICE_ACCOUNT`) are defensively `.trim()`'d on read — a trailing newline in the Vercel-stored value silently broke `users.watch` with an "Invalid topicName does not match projects/…" error (Gmail validates topic names against a regex) and silently 401'd every real push delivery (strict-equality comparators don't tolerate whitespace). Trim is applied at `webhook/gmail/route.ts:24-25` (audience, service account) and `gmail-provider.ts:412` (topic). The Microsoft and Gmail OAuth client ID/secret env vars (`MICROSOFT_CLIENT_ID/SECRET`, `GOOGLE_GMAIL_CLIENT_ID/SECRET`) are also trimmed at the call site since they pass through to external OAuth token endpoints as URL-encoded form values where a newline produces an opaque 400.

### Gmail Real-Time Webhook Architecture (GCP Project Split)

Gmail push notifications require the Pub/Sub topic and the Gmail OAuth client to live in the **same GCP project** — a hard Gmail API requirement, not a soft suggestion. iOS and Web do not share a GCP project for this infrastructure.

| Resource | GCP Project | Notes |
|----------|-------------|-------|
| iOS Gmail OAuth client + topic | `ops-app-ios` | iOS uses a separate project — do not touch from web deploys. |
| Web Gmail OAuth client | `civic-champion-439517-e7` | Auto-generated GCP project ID; the project display name can be renamed in the GCP console (to e.g. "OPS App Web") without migrating any resources since only the ID is immutable. |
| Web Pub/Sub topic | `projects/civic-champion-439517-e7/topics/gmail-push` | Same project as the OAuth client (Gmail requirement). |
| Web push subscription | `gmail-push-sub-web` | Push delivery to `https://app.opsapp.co/api/integrations/email/webhook/gmail`, OIDC auth enabled. |
| Web push service account | `gmail-pubsub-pusher@civic-champion-439517-e7.iam.gserviceaccount.com` | The `email` claim on every incoming OIDC token. Matched against `GOOGLE_PUBSUB_SERVICE_ACCOUNT`. |
| Gmail Pub/Sub publisher SA | `gmail-api-push@system.gserviceaccount.com` | Google-managed. Must have `roles/pubsub.publisher` on the topic or `users.watch` silently succeeds but no messages publish. |
| Audience | `https://app.opsapp.co/api/integrations/email/webhook/gmail` | Configured on the subscription (step 1.3 of the runbook) and in `GOOGLE_PUBSUB_PUSH_AUDIENCE`. |

**Env vars on Vercel:**

- `GOOGLE_PUBSUB_TOPIC` — passed to Gmail `/watch` as `topicName`. Must match `projects/<project>/topics/<name>` exactly (Gmail regex-validates).
- `GOOGLE_PUBSUB_PUSH_AUDIENCE` — strict-equals compared to the OIDC `aud` claim in the webhook route.
- `GOOGLE_PUBSUB_SERVICE_ACCOUNT` — strict-equals compared to the OIDC `email` claim in the webhook route.
- All three are `.trim()`'d on read (defensive layer shipped 2026-04-19). Setting the values via `printf` + `vercel env add` is the safe path; pasting into the Vercel UI can introduce trailing newlines.

**Manual runbook for initial setup or topic migration:** `OPS-Web/docs/runbooks/gmail-pubsub-webhook-fix.md`. Covers GCP console steps (topic creation, Gmail publisher IAM grant, push subscription with OIDC auth), Vercel env-var steps (with `wc -c` byte-count verification that values have no trailing newline), redeploy, per-user reconnect, and end-to-end verification (`email_connections.webhook_subscription_id` populated + Vercel logs show successful `users.watch` + live test email delivery).

### 8. POST /api/integrations/email/webhook/microsoft365

**Purpose:** Receives M365 Graph API change notifications and triggers sync. Also handles subscription validation handshake.

| Field | Value |
|-------|-------|
| Auth | None (M365 sends unauthenticated; always returns 200) |
| Request body | M365 change notification: `{ value: [{ clientState: connectionId }] }` |
| Query params | `validationToken` (present during subscription creation) |
| Response | 200 OK (text/plain with validationToken during handshake, JSON otherwise) |
| Service calls | Internal fetch to `/api/integrations/email/manual-sync` (fire-and-forget) |

**Behavior:** During M365 subscription creation, responds with `validationToken` in plain text. For change notifications, reads `clientState` (set to connectionId during subscription setup), debounces (30s), triggers manual-sync.

### 9. GET /api/integrations/microsoft365

**Purpose:** Initiates M365 OAuth flow by redirecting to Microsoft login.

| Field | Value |
|-------|-------|
| Auth | None (redirect-based; state param carries companyId/userId) |
| Query params | `companyId` (required), `userId`, `type` (default `"individual"`) |
| Response | 302 redirect to `login.microsoftonline.com` |
| Env vars | `MICROSOFT_CLIENT_ID` |

**Behavior:** Encodes `{ companyId, userId, type }` as base64 state param, builds Microsoft OAuth URL with `Mail.Read Mail.ReadWrite offline_access` scopes, redirects user.

### 10. GET /api/integrations/microsoft365/callback

**Purpose:** M365 OAuth callback — exchanges auth code for tokens, stores connection.

| Field | Value |
|-------|-------|
| Auth | None (OAuth callback) |
| Query params | `code`, `state` (base64-encoded), `error` |
| Response | 302 redirect to `/settings?tab=integrations&status=...` |
| Env vars | `MICROSOFT_CLIENT_ID`, `MICROSOFT_CLIENT_SECRET` |

**Behavior:** Decodes state to get companyId/userId/type, exchanges code for tokens via Microsoft token endpoint, fetches user profile for email, inserts into `email_connections` with `provider: "microsoft365"` and `status: "setup_incomplete"`, redirects to settings with success/error status.

### 11. GET /api/admin/ai-features

**Purpose:** Lists all companies with their AI feature override status.

| Field | Value |
|-------|-------|
| Auth | Admin (Firebase token + admin email whitelist via `withAdmin()` wrapper) |
| Response | `Array<{ id, name, aiEmailReview: { enabled, enabledAt }, aiEmailMemory: { enabled, enabledAt } }>` |
| Service calls | Direct queries on `companies` and `admin_feature_overrides` |

### 12. GET + PATCH /api/admin/ai-features/[companyId]

**Purpose:** View or toggle AI features for a specific company.

**GET:**

| Field | Value |
|-------|-------|
| Auth | Admin (Firebase token + admin email whitelist) |
| Response | `{ company: { id, name }, features: { ai_email_review, ai_email_memory }, memory: { facts, graphEdges, profiles, writingProfiles } }` |
| Service calls | `MemoryService.getStats()`, direct queries on `admin_feature_overrides`, `agent_writing_profiles` |

**PATCH:**

| Field | Value |
|-------|-------|
| Auth | Admin |
| Request body | `{ ai_email_review?: boolean, ai_email_memory?: boolean }` |
| Response | `{ ok: true, updated: [{ feature, enabled }] }` |
| Service calls | `admin_feature_overrides` upsert (on conflict: `company_id, feature_key`) |

### 13. GET + DELETE /api/admin/ai-features/[companyId]/memory

**Purpose:** View or reset AI memory for a company.

**GET:**

| Field | Value |
|-------|-------|
| Auth | Admin |
| Response | `{ facts: AgentMemory[], edges: KnowledgeGraphEdge[] }` (max 100 each, newest first) |
| Service calls | Direct queries on `agent_memories` and `agent_knowledge_graph` |

**DELETE:**

| Field | Value |
|-------|-------|
| Auth | Admin |
| Response | `{ ok: true, message: "Memory reset complete" }` |
| Service calls | `MemoryService.resetMemory()` |

### 14. POST /api/cron/email-sync

**Purpose:** Scheduled email sync cron job. Runs every 15 minutes via Vercel Cron.

| Field | Value |
|-------|-------|
| Auth | Cron secret (`Authorization: Bearer $CRON_SECRET`) |
| Response | `{ ok: true, synced: number, staleSweepChanges: number, pendingLeadScanSweep, results: SyncResult[] }` |
| Service calls | `SyncEngine.runSync()`, `SyncEngine.sweepStaleLeads()`, `SyncEngine.retryPendingLeadScans()` |

**Behavior:** Queries all active email connections, batch-fetches companies and filters by active subscription via `getSubscriptionInfo()` before running sync — expired/cancelled companies are silently skipped. Checks each connection against its `sync_interval_minutes` + `last_synced_at` to determine if sync is due, runs `SyncEngine.runSync()` for each. It also runs `SyncEngine.sweepStaleLeads()` to detect follow-up-needed opportunities based on correspondence age and a bounded `SyncEngine.retryPendingLeadScans()` drain for unmatched threads whose AI classification was explicitly deferred during a provider outage. Manual sync (`POST /api/integrations/email/manual-sync`) also checks subscription status before proceeding. Each `SyncResult`: `{ connectionId, email, provider, activitiesCreated, newLeads, error? }`.

### 14a. GET /api/cron/email-ingest-heartbeat

**Purpose:** Detects provider-connection failures and stalled OPS ingestion without using inbox quietness as an outage signal.

| Field | Value |
|-------|-------|
| Auth | Cron secret (`Authorization: Bearer $CRON_SECRET`) |
| Response | `{ ok, checked, failed, alerted, deliveryFailures? }` |
| Failure reasons | `webhook_expired`, `webhook_setup_failed`, `sync_stale` |

`webhook_expired` and `webhook_setup_failed` are provider-connection incidents. Their email and persistent rail alert may direct an authorized integrations manager to the exact reconnect flow.

`sync_stale` is different: the connection may still be `status='active'`, `sync_enabled=true`, and hold valid access/refresh tokens while the OPS worker stops completing provider catch-up. Its alert must say the inbox is still connected, report delayed OPS processing and automatic retry, and link only to inbox status. It must never call the mailbox disconnected or prescribe OAuth reconnection. Live production migration record `20260805190312_email_provider_snapshot_health`, from repository source `20260805151056_email_provider_snapshot_health.sql`, adds `provider_snapshot_at`; operational provider health reads it with `last_synced_at` as the nullable rollout fallback. This prevents a healthy provider cursor plus still-pending derived lead summaries from generating a false mailbox outage. Current sync locks/leases, heartbeat history, recovery queue state, recent downstream thread/draft records, and runtime errors remain corroborating evidence; connection status alone is never health proof. The connection-scoped persistent incident resolves only after the exact mailbox becomes healthy.

**Production release (2026-08-05/06):** authenticated continuation behavior was runtime-proven on byte-identical repair commit `146f6d69c4d52d985bc516c0453db6590f92cf97` in deployment `dpl_6gxJ4P8dv7ohpXpi1wbbdPuyR7FY`, where the derived queue drained from seven IDs to zero. The durable release is OPS-Web main commit `17e70559e5db5d51861e4d8bc8d57b2cd490d10b` in READY deployment `dpl_AiDK9ZkSfv6BvbP9pSkZiRwnVgSh` (`2026-08-06T06:29:26.442Z`). `app.opsapp.co` resolves to that exact SHA with `aliasError = null`; root/login returned HTTP 200, an unauthenticated heartbeat returned the expected HTTP 401, and deployment-scoped logs contained no error/fatal entry or HTTP 5xx. The migration remains live. Current database readback has zero wrapped continuations, locks, or recovery state, with `last_synced_at` `2026-08-06T03:57:31.91Z` and `provider_snapshot_at` `2026-08-06T03:57:32.135712Z`. No new authenticated sync or provider/email mutation was invoked on this exact final deployment; the earlier byte-identical deployment remains the behavioral runtime proof.

### 15. POST /api/cron/webhook-renewal

**Purpose:** Renews expiring Gmail Pub/Sub watches and M365 subscriptions. Runs daily via Vercel Cron.

| Field | Value |
|-------|-------|
| Auth | Cron secret (`Authorization: Bearer $CRON_SECRET`) |
| Response | `{ ok: true, renewed: number, results: [{ id, provider, renewed, error? }] }` |
| Service calls | `EmailService.getConnection()`, provider `renewWebhook()`, `EmailService.updateConnection()` |

**Behavior:** Finds active connections with webhooks expiring within 2 days, renews each via the provider abstraction (Gmail: re-register Pub/Sub watch with 7-day expiry; M365: renew subscription with 3-day expiry), updates `webhook_subscription_id` and `webhook_expires_at`.

### Email actor, assignment, and delivery contract (prepared 2026-07-16)

Every browser email route resolves the Firebase subject to one active canonical OPS `public.users.id`. Request `userId` and `companyId` values are mismatch checks only; mailbox addresses never identify an OPS actor. `email_connections.company_id` and `user_id` remain legacy text columns. Only `type='individual'` may treat an exact, valid `user_id` UUID as mailbox ownership. A company connection's legacy `user_id` is connector metadata and grants no authority.

Lead-linked reads require the intersection of canonical `pipeline.view` and `inbox.view`; sends, provider-draft mutations, and learning-authoritative actions require canonical `pipeline.edit` and `inbox.send`. Assigned scope is evaluated against the opportunity's current `assigned_to` under the guarded assignment contract. Standalone Inbox lists, thread detail, lead correspondence, drafts, sibling context, attachments, and send routes use the same opportunity + inbox helpers. An existing provider thread remains pinned to its original connection. Explicitly selecting another authorized sender starts a new provider thread linked to the same lead; it never changes or impersonates the original provider thread.

Before provider I/O, the send route persists `email_send_intents` with a deterministic idempotency key, canonical actor, connection, internal/provider thread identity, opportunity, assignment snapshot, draft provenance, request fingerprint, and delivery state. After provider acceptance, database reconciliation is idempotent and may retry without invoking the provider again. Provider rejection preserves the draft and writes no sent activity. An accepted-but-not-yet-reconciled intent returns a pending/recovery result instead of risking a duplicate send.

#### Provider proof and immutable-turn RPC boundary (2026-08-10) — local only, unapplied

OPS Web commit `1e866814` adds the service-role-only RPC boundary for exact provider source capture and job-turn ingestion. The SQL is in `20260807220000_agent_job_conversation_memory.sql`, `20260807223000_agent_correspondence_evidence_read.sql`, and `20260807224500_agent_provider_delivery_sources.sql`; none is applied or customer-live.

| RPC family | Contract |
|---|---|
| `capture_agent_provider_delivery_source_as_system` | Stores one bounded exact Gmail/Microsoft MIME source after verifying provider, company, connection, message, recipients, headers, attachments, source hash, and first-observation projection. Replays must match the immutable source exactly. |
| `reserve_*_prepared_provider_recovery` + `claim_*_provider_send_request` | Reserves a deterministic recovery identity, then atomically binds provider, connection, expected thread, request revision, and request hash immediately before provider I/O. Final claim rechecks the current source/action authorization. |
| `mark_*_provider_accepted`, `mark_*_provider_rejected`, `mark_approved_action_email_delivery_unknown`, `recover_prepared_provider_delivery_as_system` | Advances the durable intent only with the bound provider proof. Ambiguous/legacy attempts are reconciliation-only and cannot be resent through the direct path. |
| `read_agent_provider_delivery_source_receipt_as_system` + `read_agent_provider_delivery_source_as_system` | Returns the immutable capture receipt or the exact source projection for the same company/connection/message/activity tuple; no caller-supplied tenant scope is trusted. |
| `ingest_job_conversation_turn_as_system` | Idempotently inserts one delivered turn and resolves its job anchor. Provider thread identity is evidence, never the conversation key. Drafts and unconfirmed intents are ineligible. |
| `read_agent_correspondence_evidence_as_system` | Returns bounded, deterministic, prompt-safe evidence only after actor/capability/entity authorization and exact evidence-id lookup. |

Private triggers independently freeze the source/send proof, enforce source-to-turn integrity, and re-run current authorization at final claim. Application services also bind the immutable provider instance's company and connection before any raw fetch, attachment read, provider call, or RPC. Live PostgreSQL execution/RLS proof remains a required pre-apply gate.

#### POST `/api/leads/[opportunityId]/follow-up` — one-tap lead follow-up (implemented 2026-07-23)

The authenticated operator sends only a UUID `idempotencyKey`; the server derives the recipient, mailbox, signature, template body, current provider subject, reply target, source event, and linked opportunity. The action is available only for due, active `quoted`, `follow_up`, or `negotiation` leads with a single authorized mailbox and a provider-backed conversation whose newest meaningful message is OPS outbound.

The stock follow-up copy is stage-neutral and does not assume a quote exists. Sequence one asks whether the lead still wants to move ahead; sequence two is a distinct final check-in. Runtime compatibility upgrades the retired quote-assuming stock template, while company-authored templates remain unchanged. Implemented in ops-web commit `cae90581` (2026-08-07; not deployed at documentation time).

Immediately before the irreversible provider claim, OPS revalidates every provider thread linked to the opportunity under the same mailbox lease. Any missing or multiply resolved thread, second mailbox, customer response, or equal/newer message on any linked conversation blocks the send. The database claim trigger independently fences equal/newer meaningful inbound or OPS outbound events across the whole opportunity, not only the selected provider thread.

Provider rejection and pre-provider authorization failures return `delivered: false` with `definitiveNoDelivery: true`. Provider acceptance is reconciled atomically through `reconcile_operator_template_follow_up_send_as_system`: the template draft becomes sent, lifecycle counters advance only if this send remains current, a current lead receives the effective comeback, and one `lead_follow_up_sent` notification is receipted on the intent. A durable equal/newer correspondence event preserves the newer truth and yields a null `comebackAt`. The success response is built from a freshly re-read reconciled intent, so retries return the stored provider and lifecycle receipt without another send.

#### Replay-stable correspondence direction (2026-07-23)

Provider inbox/sent labels are transport hints, not historical correspondence
authority. After connection-scoped provider-message deduplication,
`SyncEngine.runSync()` loads any exact existing activity before partitioning the
batch. A valid persisted `inbound` or `outbound` direction wins on every replay;
the current authoritative teammate roster classifies only a provider message
with no persisted activity. The same resolved envelope is reused for
inbox/sent partitioning, outbound learning, thread reconciliation, lifecycle
evaluation, and activity/event projection.

This prevents a teammate roster change from turning an older inbound activity
into outbound correspondence and tripping the immutable database identity
guard before later mail can be checkpointed. A malformed persisted direction
still fails closed, the database guard remains unchanged, and no historical
activity is rewritten or backfilled.

#### Authoritative staff secondary email identity (live 2026-07-29)

Migration `20260728161000_authoritative_staff_email_aliases` and ops-web
commits `90f14226` + `cd901503` are deployed.
`SyncEngine` loads one
company-scoped staff identity authority at the start of every normal sync,
historical import, exact-message recovery, and sent-folder safety-net pass.
Exact registered emails and exact active verified aliases are staff identities;
registered connection/profile authority is included only through those exact
records.

An unknown sender can become only a pending alias candidate when signature
evidence exactly matches one active teammate's normalized full name and full
roster phone. The service-role-only
`record_staff_email_alias_candidate_as_system(...)` verifies the active
mailbox, roster match, exact provider thread/message, and immutable
company/user/email ownership. A same-company administrator then makes the
audited one-time `verified` or `rejected` decision through
`review_user_email_alias(...)`. Pending aliases always fail closed into review:
they may quarantine the exact corroborated message on the outbound/review path
so the staff sender cannot become a lead, but they do not enter the durable
authoritative staff email set until verified.

The classifier applies this boundary before relationship matching, contact-form
routing, alternate-participant selection, enrichment, assignment, notification,
or recovery. A verified secondary address is outbound/internal staff mail, and
its exact external recipients remain eligible customer contacts. A registered
team address in To/CC and an exact signature phone may corroborate a candidate;
names, phone fragments, shared public email domains, and fuzzy private-domain
matches never confer staff identity.

#### Property-level address identity boundary (live 2026-07-29)

Migration `20260728160000_property_address_identity_boundary` and ops-web
commits `d6426b51` + `2e7acb93` are deployed.
Every email relationship, recovery, participant, enrichment,
duplicate/preflight, and project-conversion path now calls the same
property-address qualifier before an address can enter an identity set. City,
municipality, neighbourhood, region, postal locality, area label, and
PO-box-only values normalize to no identity.

Supported property evidence is a numbered street identity, a structured rural
route/site/box identity, a lot/concession or lot/block/plan identity, or an
explicit parcel/PID identity. Street suffixes and cardinal directions are
canonicalized. Unit identifiers are retained in the identity key, preventing
two suites at the same building from collapsing. Locality may remain in source
metadata or presentation context, but it cannot establish a client,
opportunity, merge, dedupe, relationship, assignment, notification, or project
link.

Ops-web commit `743b9319` also applies the qualifier at contact resolution and
the canonical enrichment persistence boundary. Locality-only form, forwarded,
AI/import, attachment, and recovery facts therefore cannot populate a client
or opportunity job-address field even after later asynchronous enrichment.
Qualified street, unit, rural-property, and parcel values retain their cleaned
display form.

#### Guarded decisive rejection commit (live 2026-07-29)

Migration `20260728162000_guarded_customer_decline_lifecycle` and ops-web
commit `d24b41f7` are deployed.
`apply_email_opportunity_declined_disposition(...)` is a service-role-only
commercial boundary. It accepts exact company, opportunity, mailbox, provider
message, expected assignment/stage snapshot, and a closed evidence object
containing the reason, decisive signal, provider-message list, and evaluated
correspondence high-water event.

The RPC locks the opportunity and proves active mailbox identity, projected
meaningful inbound customer correspondence, persisted customer sender,
assignment stability, high-water freshness, and terminal precedence. A decisive
rejection writes Lost plus one evidence-backed disposition atomically; financial
reasons map to `price`, otherwise an unequivocal rejection maps to
`customer_declined`. Won/discarded and manual terminal states are protected.
A historical manual nonterminal repair does not permanently suppress newer
decisive customer evidence. Exact replay is a no-op; newer/out-of-order evidence
forces a full re-evaluation instead of accepting a stale write.

Lead summaries use the same deterministic commercial outcome. An unequivocal
customer decline clears both current-fact and commercial next actions and marks
the previously pending operator request as superseded, so model validation
rejects summaries that repeat an already-answered question. A temporary
budget/timing deferral retains its legitimate comeback action, and Won leads
retain schedule/deposit actions; only a true decline closes the prior ask.

#### Exact-message latest-event lifecycle recovery (live 2026-07-29)

Migration `20260729170000_exact_recovery_latest_event_lifecycle` and ops-web
commit `8c0e428e` extend the existing guarded recovery path without weakening its
fail-closed boundary. A misplaced message may be the source lead's current
lifecycle high-water. Recovery is allowed only when the lifecycle state is
passive and exactly matches that message, an earlier meaningful projected event
exists, and every historical `leads_waiting` notification is resolved.

The guard still rejects unresolved lifecycle notifications, generated follow-up
drafts, applied lifecycle actions, nonzero follow-up counters, stale/protected
state, missing prior event history, or any state/event mismatch. The move and
both source/target lifecycle recomputations remain one transaction. Gmail or
Microsoft 365 is never mutated by this database recovery operation.

#### Staff false-lead correction compatibility guards (live 2026-07-29)

Migrations `20260729173000_fix_staff_false_lead_notification_company_cast` and
`20260729174500_preserve_referenced_staff_false_lead_client` retain the original
content-addressed, service-only correction contract. The first makes the
notification tenant comparison explicit across the existing text-backed
notification company key and UUID correction input. The second performs a
schema-wide post-reparent client reference count: it deletes the false source
client only at zero references and otherwise preserves the shared client. The
immutable correction result records the deletion decision and remaining
reference count, so exact retries return the same audited outcome.

#### GET / PATCH `/api/integrations/email/connection` — company intake owner

Company mailbox configuration includes nullable `defaultIntakeOwnerId` only for
an actor with `settings.integrations:all`; other descriptors redact it to
`null`. A company-owner change is an isolated PATCH:

```json
{
  "connectionId": "uuid",
  "expectedDefaultIntakeOwnerId": "uuid-or-null",
  "data": { "defaultIntakeOwnerId": "uuid-or-null" }
}
```

The route additionally requires `pipeline.assign:all`, rejects personal
mailboxes and mixed-field updates, and calls
`configure_company_mailbox_intake_owner_as_system`. The service-role-only RPC
locks the company and mailbox, reauthorizes the active actor, validates the
same-company eligible target, and compares the expected owner. A stale
expectation returns HTTP 409; generic `email_connections` updates do not write
the owner field. Source:
`ops-web/supabase/migrations/20260723214524_company_mailbox_intake_owner.sql`
and `ops-web/src/app/api/integrations/email/connection/route.ts`.

#### Atomic live company-mailbox creation and fallback delivery

Live sync and exact-message recovery create a new company-mailbox lead through
the service-role-only
`create_company_mailbox_email_opportunity_as_system` operation. The caller
supplies a tightly allow-listed opportunity payload, the exact connection and
provider-thread identity, ingestion source (`email_sync` or
`email_recovery`), and the provider-mutation recovery fence—never an assignee.
Under one company-serialized database transaction, the operation validates the
source key and active sync-enabled company mailbox, inserts the opportunity,
derives the target from `email_connections.default_intake_owner_id`, and either
records the canonical guarded `company_mailbox_default` assignment event or
enqueues the missing/ineligible-owner prompts. A failure in any part rolls the
new opportunity back, so retry cannot strand a created-but-undispositioned row.

If the owner is valid, the canonical assignment event unlocks the existing
assigned-mailbox draft actor and normal assignment delivery. If the owner is
missing or no longer eligible, that same transaction leaves the lead unassigned
and enqueues one `unassigned_lead_assignment_deliveries` row per currently
authorized company administrator. `GET /api/cron/lead-assignment-deliveries`
claims those rows through service-role-only lease RPCs, materializes the
persistent `lead_assignment_required` notification, and sends an idempotent
OneSignal push only when the recipient's `lead_assignments.push` preference is
enabled. Push failure is retried by the delivery lease and never replays email
ingestion.

The `(company_id, source_thread_key)` key is the idempotency boundary. If it
already exists—including on a retry—the atomic operation returns that exact
row with `created=false` and no assignment result; it does not assign, prompt,
or otherwise mutate the winner. Historical wizard import keeps automatic
assignment on its existing individual-mailbox-only path; company-mailbox
historical rows are not routed through the live atomic operation. No migration
or bulk backfill is performed. Any later canonical manual assignment marks all
outstanding prompt rows and their persistent notifications resolved.

### 16. POST /api/integrations/email/send

**Purpose:** Sends an email via the user's connected Gmail or M365 account.

| Field | Value |
|-------|-------|
| Auth | Firebase operator with `inbox.send`, or exact cron secret for internal auto-send (subscription check + rate limit 100/hour) |
| Request body | `{ userId, companyId, connectionId, to: string[], cc?: string[], subject, body, format?: "markdown"\|"plain", opportunityId?, inReplyTo?, threadId?, draftHistoryId?, followUpDraftId? }` |
| Response | `{ ok: true, messageId, threadId, idempotencyKey }`, or a delivery/reconciliation-pending response that is safe to retry |
| Service calls | `EmailService.getConnection()`, provider `sendMessage()`, `OpportunityService.createActivity()`, `EmailMatchingServiceV2.match()` |

**Behavior:** Validates the tenant/user/connection/opportunity/draft relationships before the irreversible provider call. When `format="markdown"`, converts the authored body to HTML, strips any exact known prior signature revision, and appends the effective signature once. The signature-free authored body remains the canonical activity/learning sample. Creates an outbound activity with provider identity and draft provenance, projects correspondence idempotently, and enqueues the immutable outcome for post-delivery learning. Gmail uses RFC 2822 threading; M365 uses `/createReply` or `/sendMail`. Provider delivery is never retried merely because a later database write failed.

### 16a. GET / POST `/api/leads/:opportunityId/follow-up` (2026-07-23; hardened 2026-07-29)

**Purpose:** Previews and sends the standardized operator-triggered lead follow-up from the iOS Due/Overdue chase control without allowing the client to author transport facts.

| Field | Value |
|-------|-------|
| Auth | Firebase bearer token resolved to the canonical active OPS actor; requires effective lead-send access (`pipeline.edit` and `inbox.send`) for the selected opportunity/thread/mailbox |
| GET | Read-only provider-fresh preflight. Returns `{ recipient: { name, email }, from, subject, body, previewFingerprint, templateSettingsPath }` and creates no draft, intent, correspondence, lifecycle, notification, or provider mutation |
| Request body | `{ idempotencyKey: string, previewFingerprint?: string }`, where the key is a client UUID and the optional SHA-256 fingerprint is the opaque server-issued value from GET |
| Success response | HTTP 200 with `{ ok: true, delivered: true, reconciliationPending: false, intentId, messageId, threadId, sentAt, opportunityId, outcomeAppliedAt, notificationId, comebackAt, opportunity? }`; `comebackAt` is nullable when newer lifecycle truth won |
| Nonterminal response | HTTP 202 with the durable `intentId` plus `delivered`, `reconciliationPending`, and `deliveryUnknown`; this is not permission to advance local lead state |
| Primary sources | `ops-web/src/app/api/leads/[opportunityId]/follow-up/route.ts`; `ops-web/src/lib/api/services/lead-follow-up-send-service.ts`; `ops-web/src/lib/api/services/email-send-reconciliation-service.ts`; `ops-ios/OPS/Services/LeadFollowUpService.swift` |

The server derives the actor, company, opportunity, active connected mailbox, canonical linked provider thread, recipient, subject/body template, any deliberate edit on the exact still-bound stock draft, effective signature, source correspondence event, and reply headers. GET's body is the fully rendered message including that signature. It does not accept a client-supplied company id, user id, mailbox id, thread id, recipient, subject, or body. The optional `previewFingerprint` is not authority or transport input: it is a digest of the exact server-derived mailbox, thread, reply source, recipient, sender, subject, and rendered body shown by GET. POST recomputes it after its own fresh preflight and refuses with `LEAD_FOLLOW_UP_REVIEW_CHANGED` before provider work when any reviewed fact changed; it checks the final bound draft content again before delivery to close a concurrent-edit race. Skip-review sends omit it and still pass every normal provider, authorization, and cycle gate. The lead must be active, unconverted, in `quoted`, `follow_up`, or `negotiation`, due on or before today in the company's valid IANA timezone, have a contact email, and have one unambiguous existing provider thread linked to it. A due cycle is valid only when `next_follow_up_at >= stage_entered_at`, canonical `last_outbound_at < next_follow_up_at`, and the provider source outbound also predates the due boundary. This prevents a due date inherited from a prior stage or a newer manual outbound from authorizing the same stock follow-up.

GET and POST both perform a live provider preflight. The provider thread is checked again inside the mailbox lease immediately before POST delivery. Its newest message must still be the same OPS outbound from the pinned connection address or configured sender alias, and the lead contact must be a participant. Missing, ambiguous, stale, inbound-newest, cross-thread, cross-mailbox, cycle-satisfied, or changed conversation state fails closed; the shortcut never starts a new provider thread. Migration `20260729230000_pipeline_follow_up_reliability.sql` adds a final prepared→sending database trigger that independently rechecks the stage/due/outbound cycle immediately before provider I/O.

The reply retains the live provider conversation subject so Gmail/M365 keep it in the existing thread. Its body uses `lead_lifecycle_settings.follow_up_template_body` when configured, otherwise `Hi {{first_name}}, just checking in to see if you had any questions about the quote. No pressure — I wanted to make sure you had everything you needed.` Template placeholders are rendered server-side and the effective mailbox signature is appended once.

The UUID is persisted on-device by company + actor + opportunity + chase cycle and binds to the durable `email_send_intents` record. Authentication changes, permission failures, timeouts, unavailable provider state, provider acceptance, and incomplete reconciliation retain the same UUID. A new UUID is created only after canonical handled/outbound progress proves that a later due cycle has begun. After ordinary provider-send reconciliation, the route calls the service-role-only `reconcile_operator_template_follow_up_send_as_system(intent_id)` from migration `20260723233000_operator_one_tap_lead_follow_up.sql`. That transaction marks the bound draft sent, advances only still-current lifecycle/chase state, creates one deduplicated `lead_follow_up_sent` notification, and stores the immutable outcome/optional-comeback/notification receipt on the intent. An exact replay returns that receipt before mutable lead/thread/access state is rebuilt or any second mutation can run.

HTTP 200 is returned only after provider acceptance and both canonical reconciliation layers complete. HTTP 202 means delivery was accepted-but-still-reconciling or cannot yet be proven; iOS keeps the lead in its current bucket and retains the same idempotency key. A definitive provider rejection writes no sent activity and leaves the draft retryable. An opportunity-wide database fence plus the actor/company/cycle-scoped device key prevents a second provider boundary even if the thread, assignment, permission, app process, or network response changes. This endpoint therefore cannot duplicate a provider send merely because the response or a post-send database write failed.

The iOS control is deliberately not a tap-to-send button. A bounded 0.8-second hold either opens the server-rendered review sheet or, when that company+operator has explicitly enabled `Skip review next time`, sends after the hold. The first review shows recipient, sender, subject/body, and the customization path `Settings → Comms → Lifecycle`; delivery still requires an explicit `SEND FOLLOW-UP`. The hold is recognized simultaneously with the lead card's existing horizontal stage gesture and cancels on movement, so it cannot steal or ambiguously compete with stage advancement/regression. VoiceOver uses the standard explicit double-tap action.

### 17. GET /api/integrations/email/inbox

**Purpose:** Proxy inbox requests to Gmail/M365 for the in-app email viewer.

| Field | Value |
|-------|-------|
| Auth | Firebase operator; canonical per-thread `pipeline.view ∩ inbox.view` authorization |
| Query params | `companyId` (required), `threadId?` (single thread), `q?` (search), `maxResults?` (default 50) |
| Response (inbox) | `{ threads: InboxThread[], nextPageToken? }` |
| Response (thread) | `{ messages: ThreadMessage[] }` |
| Service calls | `EmailService.getConnection()`, provider `listThreads()` / `getThread()` |

**Behavior:** Two modes: inbox listing (deduped by `threadId`) or thread detail (all messages in chronological order). Uses `EmailProviderInterface` abstraction, handles token refresh automatically. Permission: `email.view` required for All Mail tab access.

### 18. POST /api/integrations/email/ai-draft

**Purpose:** Generates an AI email draft using writing profile + thread context + memory facts.

| Field | Value |
|-------|-------|
| Auth | Firebase operator; canonical lead/mailbox draft authorization |
| Request body | `{ companyId, userId, connectionId, opportunityId?, threadId?, recipientEmail?, recipientName?, subject?, configuredSubject? }` |
| Response | `{ available: boolean, draft: string (markdown), draftHistoryId: string, confidence: number, sources: string[], subject?, subjectSource?, noReplyWarranted?, reason? }` |
| Service calls | `WritingProfileService.getProfile()`, `MemoryService.getFacts()` (if Phase C enabled), `DraftGenerator.generateDraft()` |

**Behavior:** Manual thread drafts assemble context from the connection-scoped newest 20 thread messages. A source-bound autonomous opportunity reply instead loads the complete authorized opportunity conversation across provider-thread fragments, capped at 200 messages and 120,000 characters; the exact triggering activity must be present. The prompt uses that conversation, the writing profile, opportunity/client facts, and enabled memories, but excludes the mutable `opportunities.ai_summary` from draft context.

Before an autonomous model call, the deterministic conversation router assigns a response disposition and mode. Closed-loop acknowledgements, sign-offs, and completion-only updates return `available: false, noReplyWarranted: true` without creating draft history or a provider draft. Schedule/availability requests without verified calendar context are held for operator input. First replies may establish context once; ongoing replies are constrained to the latest semantic change, one to three short sentences, at most 55 words before the sign-off, and no repeated greeting, recap, or generic call to action. Only genuinely new, non-decorative attachments on the latest customer message are acknowledged. Promoted edit-derived `more_direct` and `shorter` preferences override historical averages. Implemented in ops-web commit `cae90581` (2026-08-07; not deployed at documentation time).

Replies normalize the existing thread subject to one `Re:`. New-thread precedence is explicit operator subject, configured/template subject, qualifying de-identified learned template filled only from the current lead, contextual generation, then `Your inquiry`. The subject remains editable and AI fills it only when blank. The history insert is authoritative: an error or missing ID fails draft generation instead of returning an untracked draft.

### 19. POST /api/integrations/email/draft-feedback

**Purpose:** Lets an authenticated operator discard an owned AI draft.

| Field | Value |
|-------|-------|
| Auth | Service role |
| Request body | `{ draftHistoryId, companyId, userId, outcome: "discarded" }` |
| Response | `{ ok: true }` |
| Service calls | Owned `ai_draft_history` update |

**Behavior:** The browser cannot claim that a draft was sent. Sent outcomes are established only by the authenticated send route or immutable provider/draft reconciliation, then processed through the durable learning queue. This prevents fabricated human authority and Phase C self-training.

### 19a. GET / PUT / POST /api/integrations/email/signature

**Purpose:** Reads the effective signature, saves/removes the current operator's OPS signature, or imports the exact Gmail `sendAs` signature read-only.

| Field | Value |
|-------|-------|
| Auth | Firebase operator. Individual connections require exact OPS owner UUID. Company connections require integration-admin authority or a currently sendable assigned lead. |
| GET | `companyId`, `userId`, `connectionId` → effective/OPS/provider signature state |
| PUT | `{ companyId, userId, connectionId, opsText }` |
| POST | `{ companyId, userId, connectionId, action: "import_provider" }` (Gmail only) |

OPS operator signature wins over mailbox OPS, which wins over the exact provider identity. Microsoft import returns unavailable because Graph has no signature API. Signature controls live in Settings → Profile so assigned Operators do not need integration-admin access. Writes cross service-only guarded RPCs that derive the actor's company and signature scope, ignore company-mailbox connector identity, lock assignment-dependent authorization, and reject cross-mailbox provider identities. Every read/save/import reconciles the persistent `email_signature_required` notification for that operator/mailbox; the prompt resolves when an effective signature exists. Gmail `not_configured` and provider-read failures are reported as failures rather than successful imports.

### 20. GET /api/integrations/email/draft-stats

**Purpose:** Returns AI draft approval statistics for a user.

| Field | Value |
|-------|-------|
| Auth | Service role |
| Query params | `companyId` (required), `userId` (required) |
| Response | `{ totalSent: number, sentWithoutChanges: number, approvalRate: number, commonChanges: string[], suggestAutoSend: boolean }` |
| Service calls | Direct queries on `ai_draft_history` |

**Behavior:** Reads only durable, actor-attributed human decisions. A draft counts as correct only when the operator sends it unchanged; any edit is an error signal. Autonomous sends and provider Sent-folder rows without exact OPS provenance cannot train a profile or contribute to graduation. `suggestAutoSend` returns `true` only at `approvalRate >= 0.95` over at least 20 verified human outcomes. OPS then creates a persistent prompt to enable automatic sending; it does not enable sending automatically.

### 21. GET /api/integrations/email/auto-send/settings

**Purpose:** Returns auto-send configuration for the user's email connection.

| Field | Value |
|-------|-------|
| Auth | Service role |
| Query params | `companyId` (required), `userId` (required) |
| Response | `{ featureEnabled: boolean, settings: { enabled: boolean, businessHoursStart: string, businessHoursEnd: string, timezone: string, delayMinMinutes: number, delayMaxMinutes: number } }` |
| Service calls | `AdminFeatureOverrideService.isAIFeatureEnabled()`, direct query on `email_auto_send_settings` |

**Behavior:** Feature-gated by `ai_auto_send` admin flag. If the feature is not enabled for the company, returns `{ featureEnabled: false, settings: null }`.

### 22. PUT /api/integrations/email/auto-send/settings

**Purpose:** Updates auto-send configuration for the user's email connection.

| Field | Value |
|-------|-------|
| Auth | Service role |
| Request body | Partial settings object (any subset of: `enabled`, `businessHoursStart`, `businessHoursEnd`, `timezone`, `delayMinMinutes`, `delayMaxMinutes`) |
| Response | `{ ok: true, settings: AutoSendSettings }` |
| Service calls | `AdminFeatureOverrideService.isAIFeatureEnabled()`, upsert on `email_auto_send_settings` |

**Behavior:** Feature-gated by `ai_auto_send` admin flag. Accepts partial updates — only the provided fields are modified.

### 23. POST /api/integrations/email/auto-send/cancel

**Purpose:** Cancels a pending auto-send email before it is dispatched.

| Field | Value |
|-------|-------|
| Auth | Service role |
| Request body | `{ id: string, companyId: string }` |
| Response | `{ ok: true, cancelled: boolean }` |
| Service calls | Direct update on `pending_auto_sends`, `ai_draft_history` |

**Behavior:** Sets the pending auto-send record status to `"cancelled"` and marks the associated `ai_draft_history` entry as `"discarded"`.

### 24. POST /api/cron/auto-send

**Purpose:** Processes pending auto-send emails. Runs every 5 minutes via Vercel Cron.

| Field | Value |
|-------|-------|
| Auth | Cron secret (`Authorization: Bearer $CRON_SECRET`) |
| Response | `{ processed: number, sent: number, failed: number, errors: string[] }` |
| Service calls | Direct query on `pending_auto_sends`, internal `POST /api/integrations/email/send`, `AdminFeatureOverrideService.isAIFeatureEnabled()` |

**Behavior:** Finds `pending_auto_sends` records where `scheduled_send_at <= now()`, limit 50 per run. Verifies auto-send is still enabled for each connection's company before dispatching. Sends via internal `POST /api/integrations/email/send`. Failed sends are retried up to 3 times, then permanently marked as `"failed"`.

### 24a. GET + POST /api/cron/lead-summary-refresh (2026-07-21)

**Purpose:** Activity-driven `opportunities.ai_summary` coverage — the non-email counterpart to the sync engine's per-thread summary writer. `GET` is the recurring Vercel cron (hourly at :40 inside the email-sync window, `40 13-23,0-4 * * *`); `POST` is the one-time operator backfill.

| Field | Value |
|-------|-------|
| Auth | Cron secret (`Authorization: Bearer $CRON_SECRET`), both verbs |
| GET gate | `LEAD_SUMMARY_REFRESH_ENABLED` env (fail-closed; unset → `{ ok, skipped, reason: "lead_summary_refresh_disabled" }`) |
| POST body | `{ "mode": "backfill", "companyId"?: uuid, "dryRun"?: boolean }` — 400 without the explicit mode; NOT gated by the env switch (single explicit invocation, not recurring spend) |
| Response | `{ ok, mode, dryRun, companiesConsidered, companiesEnabled, leadsScanned, candidates, summariesWritten, skippedInsufficientContext, failed[], written[], candidatesPreview[] }` |
| Service | `runLeadSummaryRefresh` in `OPS-Web/src/lib/api/services/lead-summary-service.ts` |
| Per-company gate | `AdminFeatureOverrideService.isAIFeatureEnabled(companyId, "phase_c")` — identical to the sync engine |

**Behavior:** For each phase_c company (discovered via `admin_feature_overrides`, or scoped by `companyId`), scans open-stage leads (`new_lead…negotiation`, not deleted/archived/merged) and their context tables — `activities`, `stage_transitions`, `site_visits`, plus `email_threads.ai_summary` as READ-ONLY input. A lead is refreshed when its newest context timestamp exceeds `ai_summary_updated_at` by more than a 5-minute epsilon (absorbs the sync engine's own stage-transition echo, which lands seconds after the summary stamp in the same pass); leads with no summary get a first one. Backfill mode restricts candidates to `ai_summary IS NULL` at the database layer. Leads with zero substantive context (no activities, no site visits, no real stage moves, no description) are counted `skippedInsufficientContext` and never sent to the model — a summary is generated the moment real activity lands. Generation reuses the shipped engine's lane end-to-end: `gpt-4o-mini` on `getSyncOpenAI()` (`OPENAI_API_KEY_SYNC`), temperature 0.1, strict `json_schema` with a server-owned singleton alias key, refusal/finish_reason/contract checks with one contract retry, and the verbatim shipped summary field specification. Writes exactly `ai_summary` + `ai_summary_updated_at` (scoped `id` + `company_id`) — never stage, `ai_stage_signals`, terminal flags, or `email_threads.ai_summary`. Per-lead failures isolate into `failed[]`; the sweep continues. Budget: 40 leads/run, stalest first (never-stamped leads lead the queue); the remainder is caught next run. Cost at Canpro volume (~40 open leads): ≈$0.0005/summary ceiling; expected $0.05–0.60/month at the hourly cadence; structural worst case (budget saturated every run) $9.60/month. `opportunities.last_activity_at` is deliberately NOT trusted (no maintaining trigger in prod); `opportunities.updated_at` is deliberately ignored (the summary write itself bumps it — reading it would self-trigger). Tests: `OPS-Web/tests/integration/lead-summary-refresh-cron.test.ts`.

### Inbox Dark-Launch (2026-06-02)

The in-app `/inbox` screen is hidden behind a per-company flag while the email engine keeps running. Built on branch `feat/inbox-dark-launch-iso`; `inbox_ui` defaults OFF (public). Design + plan + verification live in `OPS-Web/docs/specs/2026-06-01-inbox-dark-launch-design.md`, `OPS-Web/docs/plans/2026-06-01-inbox-dark-launch.md`, `OPS-Web/docs/inbox-dark-launch-verification.md`.

**Gating flags**
- `inbox_ui` — per-company `admin_feature_overrides` key (default OFF). Gates the inbox SCREEN only. Read server-side via `AdminFeatureOverrideService.isFeatureEnabled(companyId, "inbox_ui")` (`src/lib/feature-flags/inbox-ui-gate.ts`); surfaced to the client through `GET /api/feature-flags`; toggled per company at `/admin/system` (`PATCH /api/admin/ai-features/[companyId]` with `feature:"inbox_ui"` → generic `setFeatureOverride`, no phase_c wizard side-effect). When off: `/inbox` + `/inbox/[threadId]` redirect to `/pipeline` server-side, the sidebar Inbox item is hidden, and the inbox-leads widget CTA repoints to `/pipeline`. `getSlugForRoute("/inbox")` resolves to `inbox_ui` (the stale `portal:["/inbox"]` mapping was removed).
- `phase_c` — unchanged; gates automatic drafting + AI enrichment. Does NOT gate the inbox screen or lead import.
- `INBOX_AUTO_SEND_ENABLED` (env, default unset) — fail-closed master switch on `POST /api/cron/auto-send`; the cron no-ops (returns `{ skipped: true }`) unless set to `"true"`. Nothing auto-sends at launch.

**NOT gated:** automatic lead import (inbound client + opportunity creation in the sync engine, `sync-engine.ts`) runs for every connected mailbox regardless of `inbox_ui`/`phase_c` — current functionality, preserved.

**Auto-draft into the mailbox** — `sync-engine.ts` `maybeAutoGenerateDraft` (phase_c-gated): on inbound client mail, after generating a voice-matched reply via `AIDraftService.generateDraft`, OPS resolves and appends the effective signature once, then pushes it into Gmail/Outlook Drafts via `provider.createDraft`/`updateDraft`. Transactional reassignment ensures one provider draft belongs to one current `ai_draft_history` row while superseding the prior row. Threaded to the original (Gmail `threadId` / M365 `conversationId`). Never auto-sends.

**Forwarded contact-form submissions → NEW thread (2026-06-03; subject policy hardened 2026-07-14)** — a forwarded form lives on the forwarder's thread, so OPS starts a clean provider thread to the parsed client. `placeNewThreadDraft` persists the provider-minted thread and immutable opportunity link. The subject follows the new-thread policy above and is never `Re:` merely because the forwarder used one. Cold first contact remains review-only and never auto-sends.

**Learning loop re-wired through sync** — `src/lib/api/services/draft-reconciliation.ts`. Because the operator may send from their native client, reconciliation runs after the sent activity is ingested. Each pending provider draft is checked by immutable `provider.getDraft(id)`; the bounded Drafts list is never treated as proof of deletion. Exact current/historical signatures and quoted content are removed before the queue receives authored/clean bodies. One provider Sent message can bind to one canonical draft history only:
- **used** (draft gone + the first post-placement activity after the persisted source is outbound) → enqueue the exact draft/message pair as `operator_approved`; the durable worker applies the sent state and the operator's repeated-edit evidence exactly once, but never samples the full AI-authored body into the writing profile. A consumed draft does not need verbatim overlap: a total rewrite is still the operator's edit lesson.
- **from_scratch** (draft still present + a different outbound) → supersede the draft without treating the unrelated message as a 100% rewrite.
- **discarded** (draft gone, no outbound within 14-day TTL) → `status='discarded_in_mailbox'`.

The source-message fence rejects a candidate if the first activity after the exact source predates/equalled draft placement or is inbound. It permits only an outbound that follows placement to reach the immutable provider-draft check. This prevents a later reply from being paired across an intervening customer message while keeping send recognition independent from edit magnitude. Shared-mailbox actor resolution, exact signature removal, assignment/permission proof, durable idempotency, and profile-promotion thresholds remain unchanged.

Significant-edit analysis is required before the durable worker may complete an operator-approved rewrite. The OpenAI call uses a strict JSON schema with bounded arrays and enough completion headroom for the full response; refusal, truncation, a non-`stop` finish, malformed JSON, or missing required fields fails preparation so the queue retries instead of silently completing with only the deterministic diff. Legacy synchronous feedback remains fail-open so a post-send analysis outage cannot turn a successful customer send into an operator-facing failure.

Generic provider Sent mail is recorded as autonomous/no-training unless an exact OPS activity proves an authenticated operator. A provider Sent-folder row alone is not human-authority evidence.

The 12-month historical profile scan is stricter: it requests `operator_authored` learning only after removing an exact connection-scoped known signature revision. A signature lookup failure or unmatched historical footer skips the learning enqueue entirely, so raw/signature-bearing history cannot enter the durable queue.

**Manual drafting (the public's path)** — the Pipeline "Draft" button (`POST /api/integrations/email/draft`) now generates + pushes the draft into the mailbox in one step, works WITHOUT phase_c (uses `AIDraftService.generateDraft`, replacing the old phase_c-gated `DraftGenerator`), and persists `mailbox_draft_id` + `status='auto_drafted'` so the same reconciliation learns from manual drafts. It also detects a forwarded contact-form lead (re-parsing the latest inbound activity with `extractContactFormSubmission`) and routes it through the same `placeNewThreadDraft` new-thread path as the sync engine — fresh subject, new thread to the client, not a "Re:" on the forwarder's thread.

**Notifications:** when `inbox_ui` is off, the per-draft "Draft ready" notification is suppressed (silent), the email-sync-complete notification repoints from `/inbox` to `/pipeline`, and a one-time "Replies, drafted" explainer fires on the first mailbox draft for the company.

**Schema:** `ai_draft_history.mailbox_draft_id` + the status-CHECK expansion (`sent_from_mailbox`, `discarded_in_mailbox`) — migrations `20260602000000` and `20260602010000` (see `03_DATA_ARCHITECTURE.md` → `ai_draft_history`).

### 25. GET /api/cron/site-visit-prompts (2026-08-11)

**Source:** `ops-web/src/app/api/cron/site-visit-prompts/route.ts`. **Schedule:** `*/5 * * * *` — **full-day, deliberately NOT the `13-23,0-4` email window.** Appointments are time-critical; a heads-up that only fires in the overnight window is worthless.

| Field | Value |
|-------|-------|
| Auth | Cron secret (`Authorization: Bearer $CRON_SECRET`) |
| Runtime | `maxDuration = 60`, `runWithCronWorkloadControl` durable lease (mandatory for every new cron) |
| Client | `getServiceRoleClient()` |
| Caps | 200 visits per run; candidate window `now − 20 min` → `now + 24 h` (covers the 15-minute START grace plus cron latency, and the 1440-minute maximum heads-up lead) |

Selects booked visits through the `site_visits_booked_window_idx` partial index, runs the pure engine `src/lib/site-visits/prompt-engine.ts` per assignee, inserts rail notifications, and pushes via OneSignal external ids **for freshly created rows only**.

**Engine rules (pure, unit-tested):** heads-up is due on `[scheduled_at − lead, scheduled_at)`; START is due on `[scheduled_at, scheduled_at + 15 min)`; nothing is due when `status ≠ 'scheduled'`, `booked_at` is NULL, or `deleted_at` is set. Lead resolution is `visit.reminder_lead_minutes ?? user.site_visit_reminder_lead_minutes ?? 30`. Dedupe keys are exactly `site_visit:<visitId>:<heads_up|start>:<userId>:<epochSeconds(scheduled_at)>`.

**Idempotency.** PostgREST cannot express the partial arbiter of `notifications_site_visit_prompt_dedupe_uidx` in `ON CONFLICT`, and the key must suppress re-fires *even after the row is read*. The route therefore inserts plainly and treats SQLSTATE `23505` as "already prompted" — precisely the semantics the index provides. `create_notification_if_new_with_identity` is **unfit** here: its conflict reconcile only re-reads unread rows, so it raises `55000` once a prompt has been read.

**Gating.** The rail row is inserted for **all** active assignees — the rail has no opt-out (house rule) and is the durable audit surface. `notification_preferences.channel_preferences['site_visit_reminder']` is `{push, email}`-shaped, so it gates **the push only**. **Quiet hours are intentionally bypassed**: the operator chose this appointment time themselves (design § 4.5).

**Copy and routing** (`type = 'site_visit_reminder'` for both kinds):

| Kind | Title | Body | `action_label` | `deep_link_type` |
|---|---|---|---|---|
| Heads-up | `Site visit in <n> min — <lead title>` | lead address, else `No address on the lead.` | `OPEN LEAD` | `site_visit_heads_up` |
| START | `Site visit — <address, else lead title>` | `Start now?` | `START VISIT` | `site_visit_start` |

`action_url` is `/pipeline?opportunityId=<id>` for both; the lead name column is `opportunities.title`. Push data carries `{deep_link_type, leadId, siteVisitId}`. See `07_SPECIALIZED_FEATURES.md` § 14.3.7.

### 26. GET /api/cron/google-calendar-sync (2026-08-12)

**Source:** `ops-web/src/app/api/cron/google-calendar-sync/route.ts` + `src/lib/site-visits/google-calendar.ts`. **Schedule:** `*/5 * * * *`, full-day — booked appointments propagate outward whenever they change. Drains `public.google_calendar_sync_queue` against the Google Calendar API using the company's calendar-scoped Gmail connection. Full feature narrative: `07_SPECIALIZED_FEATURES.md` § 19c.

**Queue contract** (`google_calendar_sync_queue`, service-role only; migration `20260807010510_google_calendar_sync_queue.sql`):

- `operation ∈ {create, update, delete}` — **never `upsert`**; the enqueue is a trigger, not a caller.
- `status ∈ {pending, succeeded, failed, skipped}` — the success terminal is **`succeeded`**, not `done`.
- Partial unique `(site_visit_id, operation) WHERE status='pending'` collapses repeated saves into one Google write.
- Retry ladder 5 → 10 → 20 → 40 minutes on `attempts`; the fifth attempt settles `failed`.

**Skips are never errors** — each records a `skip_reason`: `missing_calendar_scope` (mail-only grant), `grant_revoked` (typed `GmailTokenRefreshError.isGrantRevoked`, i.e. `invalid_grant` on the shared refresher, or a provider 401), `connection_missing` / `connection_inactive`, `visit_not_syncable` (the drain re-reads the visit, so a cancellation between enqueue and drain cannot orphan a remote event; completed visits *do* keep patching — they happened), and `booking_cancelled` (written by `cancel_site_visit_booking`, not the drain).

`create`/`update` upsert on the connection's `primary` calendar — patch when an event id is known, insert otherwise, and a 404/410 on patch recreates, because OPS is the source of truth. The event id is written back to `site_visits.google_calendar_event_id` / `google_calendar_id` / `google_calendar_synced_at`; `delete` clears them, and a 404/410 counts as done. **Concurrency:** PostgREST cannot express `FOR UPDATE SKIP LOCKED`, so the durable cron lease serializes whole runs instead and the plain select-then-update cannot double-send.

**`*/5` grid budget is now exhausted.** `tests/unit/api/heavy-cron-schedule-isolation.test.ts` keeps an exhaustive cron inventory, a guard regex, and a minute-collision simulator. These two crons plus `fire_due_task_reminders` occupy all **three** full-day lanes the simulator permits on the `*/5` grid. **Any further full-day cron needs a different grid** (offset minutes or a coarser interval) — adding a fourth `*/5` lane fails that test by design. Every new cron must also be registered in that inventory.

### 26a. GET /api/integrations/gmail?include_calendar=1 — calendar consent lane (2026-08-12)

**Source:** `ops-web/src/app/api/integrations/gmail/route.ts` + `callback/route.ts`; migration `20260812170628_email_oauth_calendar_source.sql`.

Calendar access is a **separate, opt-in consent**, not a widening of the mail connect flow. Without `include_calendar=1` the authorization URL requests the mail scope alone. With it, the URL requests the existing mail scope **plus** `https://www.googleapis.com/auth/calendar.events`, bound to one exact connection via `connectionId`. **All** Gmail auth URLs now carry `include_granted_scopes=true`, so any re-consent returns the union of previously granted scopes and the flow is self-healing.

The callback persists the token response's actual `scope` list into `email_connections.granted_scopes` on **every** path. That column is the source of truth for what the stored refresh token can actually do — a mail-only reconnect will honestly narrow it, and a calendar upgrade restores it. `src/lib/email/calendar-scope.ts` (`hasCalendarScope`) is the TypeScript half of the scope agreement the enqueue trigger enforces in SQL.

A new OAuth state `source='calendar'` binds to one exact connection like `'alert'` does, and updates **credentials, grant, and status only** — it never touches `sync_enabled` or `auto_send`, and never demotes an active mailbox to `setup_incomplete`. (The wizard upsert path *does* demote; that trap is precisely why the calendar branch exists.) Upgrade is allowed for status `active` or `needs_reconnect` regardless of `sync_enabled`, because the sync toggle governs mail while the grant governs the credential.

Operator surface: one state-aware `CALENDAR SYNC — OFF/ON` row on the connected Gmail card in Settings → COMMS (`src/components/settings/integrations-tab.tsx`), Gmail-only and status-gated; return params `calendar=connected|error` raise a toast and are stripped. Until a company connects, the enqueue trigger finds no calendar-scoped connection and the whole feature is simply **inert** — no queue rows, no errors.

---

## Review Swipe Mutation APIs (2026-07-21)

Payment Review and Unassigned Task Review use server-authoritative mutations. A card advances only after the RPC or authenticated route confirms the requested action. The iOS callers are `OPS/Network/Supabase/Repositories/PaymentReviewRepository.swift` and `OPS/Network/Supabase/Repositories/UnscheduledReviewRepository.swift`; the implementation landed in ops-ios commit `5b918ade` and ops-web commit `eb8752ee`.

### Payment Review RPCs

| RPC | Caller | Contract |
|-----|--------|----------|
| `close_project_from_payment_review(p_project_id uuid)` | iOS through the Firebase/Supabase anon bridge | Derives the active actor and company, requires project edit plus full invoice/financial view, locks and revalidates authorization, rejects any positive unresolved invoice balance, and closes only the eligible completed project. |
| `write_off_project_from_payment_review(p_project_id uuid, p_idempotency_key uuid)` | iOS through the Firebase/Supabase anon bridge | Requires project edit plus full `invoices.view`, `finances.view`, and `invoices.edit`. Atomically writes off eligible OPS-owned outstanding invoices and closes the project. Positive QuickBooks/Sage-linked balances are rejected for provider-side handling. A durable receipt keyed by company, project, and UUID makes a lost-response or concurrent same-key retry replay the committed result exactly once. |

Both functions are `SECURITY DEFINER`, granted only to `anon` and `authenticated` app transport roles plus `service_role`, and perform their own canonical actor, tenant, permission, project-state, invoice-state, and post-lock revalidation. Invoice locks precede the project lock so the invoice close guard and review RPCs share one lock order. Source: `migrations/20260721120000_payment_review_atomic_actions.sql`; receipt foreign-key indexes: `migrations/20260721123000_payment_review_receipt_fk_indexes.sql`. Live Supabase versions are `20260721101658` and `20260721102425`.

### POST `/api/review/payment/reminder`

**Source:** `ops-web/src/app/api/review/payment/reminder/route.ts`

| Field | Value |
|-------|-------|
| Auth | Verified Firebase operator with full `projects.edit`, `invoices.view`, `invoices.send`, and `finances.view` |
| Request | `{ projectId: uuid }` |
| Success | `201` when a reminder approval action is created; `200` when the same reminder is already durably queued |
| Controlled refusal | `400` invalid project, `401` unauthenticated, `403` forbidden, `409` no reminder due, `422` feature/settings/mailbox/client-email prerequisite, `503` partial queue failure |

The route queues an approval-first `send_payment_reminder` action; it never claims the client was emailed. Eligibility uses the company's timezone, locale, currency, reminder tiers, current invoice due date/status/balance, canonical project reference, company mailbox, and current client email. `payment_reminder_generation_claims` prevents duplicate paid draft generation. The final service-role-only `claim_approved_action_email_delivery(p_intent_id)` fence rechecks authorization and the exact reminder snapshot immediately before provider I/O, so a paid, voided, written-off, rescheduled, partially paid, disabled, reassigned, or otherwise stale reminder cannot send. Source: `migrations/20260721122000_payment_reminder_delivery_guards.sql`; live version `20260721102146`.

Normal reminder creation invokes the configured drafting model and therefore consumes ordinary model usage. Duplicate or already-queued work is claimed before generation to avoid duplicate spend.

### Unassigned Task Review RPC

`mutate_task_from_unassigned_review(p_task_id uuid, p_expected_updated_at timestamptz, p_action text, p_expected_team_member_ids uuid[], p_patch jsonb, p_idempotency_key text)` is the sole authoritative swipe mutation for `assign`, `schedule`, `complete`, and `cancel`. It derives the actor/company, validates action-specific payload keys, applies exact task/calendar/status/assignment scope, compares both `updated_at` and the crew snapshot, rejects terminal/deleted/closed-project conflicts, and returns the committed task snapshot. Completion uses the canonical task-completion path so inventory consumption and automation outboxes remain exactly once; scheduling persists the explicit schedule lock in the same transaction. Source: `migrations/20260721121000_review_swipe_task_mutations.sql`; live Supabase version `20260721101710`.

---

## OpenAI API Key Separation

The email pipeline uses **separate OpenAI API keys** for different workloads to enable independent rate limiting, cost tracking, and key rotation:

| Key | Purpose | Used By |
|-----|---------|---------|
| `OPENAI_API_KEY_IMPORT` | Initial inbox scan — Phase A triage (`gpt-4o-mini`) + Phase B extraction (`gpt-5.4-mini`) | `POST /api/integrations/email/analyze`, `POST /api/integrations/email/import` |
| `OPENAI_API_KEY_SYNC` | Ongoing sync — stage evaluation, memory extraction, writing profiles | `POST /api/cron/email-sync`, `POST /api/integrations/email/manual-sync` |
| `OPENAI_API_KEY_DRAFTING` | AI email draft generation | `POST /api/integrations/email/ai-draft` |

All three keys fall back to `OPENAI_API_KEY` if the specific key is not set in the environment.

**Factory**: `src/lib/api/services/openai-clients.ts` exports three functions:
- `getImportOpenAI()` — returns client configured with `OPENAI_API_KEY_IMPORT`
- `getSyncOpenAI()` — returns client configured with `OPENAI_API_KEY_SYNC`
- `getDraftingOpenAI()` — returns client configured with `OPENAI_API_KEY_DRAFTING`

---

## SPEC Phase 1 Routes (ops-site)

Public-facing SPEC funnel endpoints live in `ops-site/src/app/api/spec/`. Every customer-facing surface goes through a server route that uses the service-role Supabase client + explicit auth checks + narrow projections — see SPEC/07_ROLLOUT.md § Gate resolutions → `SPEC-SERVER-ROUTES-VS-RAW-RLS-DECISION` for the locked posture.

### POST `/api/spec/create-checkout-session` (Stage C.1)

**Source**: `ops-site/src/app/api/spec/create-checkout-session/route.ts`. Landed 2026-05-26 on `feat/spec-checkout-flow`.

**Purpose**: Auth-gated, billing-validated entry into the SPEC deposit funnel. Returns either a Stripe Checkout Session URL (Path A) or an `awaiting_approval` signal (Path B). Master gate: `SPEC_LIVE_DEPOSITS_ENABLED=true` (default false → 503).

**Request body (JSON)**:

```jsonc
{
  "tier": "setup" | "build" | "enterprise",
  "billing": {
    "line1": "...",
    "line2": "... | null",
    "city": "...",
    "province": "BC",          // ISO-3166-2 subdivision code
    "postal_code": "V5K 0A1",
    "country": "CA"
  },
  "attestations": {
    "no_qc_head_office": true,
    "no_qc_operating_address": true,
    "no_qc_establishment": true,
    "no_material_qc_use": true
  },
  "referrer_email": "..."        // optional
}
```

**Auth**: Reads OPS user from any of: `Authorization: Bearer <token>` header, `__session` cookie, `ops-auth-token` cookie, `sb-<ref>-auth-token` cookie. Verifies the **Firebase ID token** (jose, Google JWKS). OPS authenticates every client — web dashboard AND both iOS apps — with Firebase Auth; Supabase is only the database (the Firebase JWT is bridged to Postgres via third-party auth). No client presents a Supabase-issued auth token. Matches against `public.users` by auth_id → firebase_uid → email. *(The legacy Supabase-token verifier — dead since no caller issued one — is retired in ops-web `fix/auth-identity-hardening`, staged 2026-07-07, pending prod deploy; `verifyAuthToken` is now Firebase-only.)*

**Status codes**:

| Code | Meaning | Body |
|---|---|---|
| 200 | Success | `{ stripe_url }` (Path A) or `{ awaiting_approval: true }` (Path B) |
| 400 | Bad request | `{ error, field? }` |
| 401 | Not signed in | `{ error }` — UI redirects to OPS-Web sign-in |
| 403 | spec_blocked_buyers hit | `{ error }` — generic message only (never discloses block reason) |
| 409 | Company gate failed | `{ error, redirectTo, reason }` — UI navigates to `redirectTo` (`/setup?returnTo=/spec?tier=X` for no_company) |
| 422 | Validation failed | `{ error, field, code }` — codes: `country_not_ca`, `province_quebec`, `province_invalid`, `postal_code_invalid`, `missing_field`, `attestation_not_confirmed` |
| 500 | Internal error | `{ error }` |
| 502 | Stripe upstream error | `{ error }` |
| 503 | Deposits paused | `{ error, contactUrl }` — UI navigates to contact form |

**Side effects on 200 (Path A)**:

1. Inserts `spec_projects` row with `status='awaiting_deposit'`, `billing_*`, `quebec_eligibility_payload`, `attribution`, `is_test=(STRIPE_SECRET_KEY starts with sk_test_)`.
2. Gets-or-creates Stripe Customer with pre-collected address; stores id on `companies.stripe_customer_id`.
3. Creates Stripe Checkout Session per the locked SPEC-STRIPE-ADDRESS-TAX-SPIKE field set (`customer`, `automatic_tax`, `billing_address_collection='required'`, `consent_collection.terms_of_service='required'`, `phone_number_collection`, GST/HST `custom_fields`, `metadata.tos_version_hash`, attribution metadata).
4. Updates `spec_projects` with `stripe_session_id`, `stripe_customer_id`.
5. Writes `billing_address_submitted` + `stripe_checkout_opened` to `conversion_event_outbox`.

**Side effects on 200 (Path B)**:

1. Inserts `spec_projects` row with `status='awaiting_owner_approval'`, same billing/attribution fields.
2. Inserts `spec_owner_approval_requests` row with `approval_token_hash` (SHA-256 of a high-entropy `<uuid_v4>.<32_hex_chars>` plaintext token — the plaintext is emitted only in the email link, never stored). Snapshots `approved_total_cents`, `approved_deposit_cents`, `approved_tos_version_hash`.
3. Stamps `spec_projects.owner_approval_requested_at`.
4. Enqueues `spec.owner_approval_required` in `spec_email_outbox` for OPS-Web (via Stage H templates + Stage C.5 cron) to dispatch.
5. Writes `billing_address_submitted` + `owner_approval_requested` to `conversion_event_outbox`.

**Locked field-set proof** (per SPEC-STRIPE-ADDRESS-TAX-SPIKE):

The Checkout Session create call passes — verbatim from `route.ts`:

```ts
stripe.checkout.sessions.create({
  mode: 'payment',
  customer: stripeCustomerId,            // pre-collected address attached to Customer
  automatic_tax: { enabled: true },       // CAD/GST/HST/PST per billing province
  billing_address_collection: 'required',
  consent_collection: { terms_of_service: 'required' },
  phone_number_collection: { enabled: true },
  custom_fields: [{
    key: 'gst_hst_number',
    label: { type: 'custom', custom: 'GST/HST number (optional)' },
    type: 'text',
    optional: true,
  }],
  customer_update: { address: 'auto', name: 'auto', shipping: 'auto' },
  line_items: [{ price_data: { currency: 'cad', product_data: {...}, unit_amount: depositCents, tax_behavior: 'exclusive' }, quantity: 1 }],
  metadata: { type: 'spec_deposit', spec_project_id, user_id, company_id, tier, tos_version_hash, utm_*, gclid, fbclid },
  payment_intent_data: { metadata: { /* same */ } },
  success_url: '${origin}/spec/confirmation?session_id={CHECKOUT_SESSION_ID}',
  cancel_url: '${origin}/spec',
})
```

The webhook handler extension (Stage C.2) inspects `session.customer_details.address.state` first — any `QC` or non-`CA` post-Stripe edit triggers the locked refund + cancel + block-list defense per SPEC-STRIPE-ADDRESS-TAX-SPIKE.

### Stage C.1 supporting tables (Supabase migration `2026-05-26-01-spec-stage-c1-outboxes.sql`)

- `public.conversion_event_outbox` — Meta CAPI + Google Enhanced events queued by ops-site; processed by the Stage C.5 cron once ad-platform credentials are provisioned (SPEC/07_ROLLOUT.md open item #8).
- `public.spec_email_outbox` — SPEC transactional emails queued by ops-site; processed by OPS-Web via the Stage H template registry + Stage C.5 cron.

Both tables are RLS-locked with a single `for all using (false)` policy; only service-role connections read/write.

### POST `/api/shop/webhook` — SPEC dispatch (Stage C.2)

**Source**: `ops-site/src/app/api/shop/webhook/route.ts` (modified). SPEC handlers in `ops-site/src/lib/spec/webhook-handlers.ts` + `ops-site/src/lib/spec/notifications.ts`. Landed on `feat/spec-webhook-extension`.

**Purpose**: Extends the existing consolidated `/api/shop/webhook` endpoint so it dispatches `checkout.session.completed` events whose `metadata.type` is `spec_deposit` (legacy `tailored_deposit` accepted during cutover) and `charge.dispute.created` events that match a SPEC payment. Shop event branches (`payment_intent.succeeded`, `payment_intent.payment_failed`) are unchanged.

**Event-type dispatch table**:

| Stripe event | Matcher | SPEC handler | Side effects (summary) |
|---|---|---|---|
| `checkout.session.completed` | `session.metadata.type === 'spec_deposit'` | `handleSpecCheckoutSessionCompleted` | Quebec post-Stripe defense (FIRST) OR normal deposit_paid flow |
| `charge.dispute.created` | matched against `spec_payments.stripe_payment_intent_id` | `handleSpecChargeDisputeCreated` | Disable entitlements, flip payment to disputed, notify operator + buyer |
| `payment_intent.succeeded` | shop-only | shop branch (unchanged) | Confirm shop order, decrement stock |
| `payment_intent.payment_failed` | shop-only | shop branch (unchanged) | Cancel shop order, release inventory |

**Idempotency**: every SPEC branch consults `public.stripe_webhook_events` for the incoming `event.id` before mutating. If the row exists, the handler returns `{ ok: true, status: 'duplicate' }` without side effects. The dedup row is INSERTED at the END of a successful branch, so a mid-handler failure leaves the row absent and Stripe re-delivers (matches OPS-Web's existing webhook dedup contract).

**Quebec post-Stripe defense (locked per `SPEC-STRIPE-ADDRESS-TAX-SPIKE`)** — fires FIRST, BEFORE any deposit_paid mutation. Triggers when `session.customer_details.address.state === 'QC'` OR `country !== 'CA'`. Side effects:

1. `stripe.refunds.create({ payment_intent, reason: 'requested_by_customer', metadata: { reversal_reason: 'spec_quebec_post_stripe_leak', spec_project_id } })` — full refund, with one retry on transient Stripe API failure.
2. `update spec_projects set status='cancelled', cancellation_reason='quebec_billing_at_stripe', cancelled_at=now()` — `deposit_paid_at` is NEVER stamped on a Quebec leak.
3. `insert spec_blocked_buyers` with `email=session.customer_details.email`, `stripe_customer_id=session.customer`, `blocked_reason='quebec_misrepresented_billing_address_post_stripe'`.
4. `queueSpecEmail('spec.quebec_rejected_post_stripe', ...)` with the Stage H `SpecQuebecRejectedPostStripeProps` payload (buyerName, amountRefundedFormatted, refundedAtFormatted, stripeRefundReceiptUrl).
5. `dispatchSpecOperatorNotification('spec_quebec_leak_refunded', persistent=true)` — every SPEC operator gets a rail row with `company_id=OPS_OPERATIONS_COMPANY_ID`.
6. Internal-only `quebec_rejected` conversion event written to `conversion_event_outbox` — NEVER sent to ad platforms.
7. `spec_communications` system audit row with the dispute reason + refund id + billing state for evidence.

**Normal deposit_paid flow** (locked per SPEC/07_ROLLOUT.md § 5):

1. Update `spec_projects`: `status='deposit_paid'`, `deposit_paid_at`, `tos_version_accepted` (from `metadata.tos_version_hash`), `tos_accepted_at`, `tos_accepted_ip` (NULL — Stripe Checkout doesn't expose the customer's IP on the Session payload; documented limitation), back-fill `customer_name`/`customer_phone`/`customer_gst_number` from `customer_details` + `custom_fields.gst_hst_number`.
2. Back-fill `companies.stripe_customer_id` if null (first-time SPEC customer mapping for future subscription billing).
3. Insert `spec_acceptance_events` row: `event_type='tos_accepted'`, `accepted_by_user_id=metadata.user_id`, `signature_method='click_in_app'` (the live check constraint allows only `click_in_app`/`docusign`/`email_reply` — `click_in_app` is the closest semantic match for Stripe `consent_collection`), `signature_evidence_url` pinned to the Stripe payment receipt, `payload_hash=metadata.tos_version_hash`.
4. Insert `spec_payments` deposit milestone marked paid (`milestone='deposit'` — matches live `spec_payment_milestone` enum, not the spec's "P1" shorthand; `status='paid'`, `paid_at=now()`).
5. Insert `spec_referrals` row when `spec_projects.referrer_email` is non-null (status='pending', eligible_at=null).
6. `queueSpecEmail('spec.deposit_confirmed', ...)` with the Stage H `SpecDepositConfirmedProps` payload (buyerName, companyName, tier capitalized, depositAmountFormatted with CAD locale, totalAmountFormatted, paidAtFormatted in `America/Vancouver` time, stripeReceiptUrl, intakeUrl).
7. `dispatchSpecCustomerNotification`: buyer rail row (`company_id=linked_company_id`, `type='spec_deposit_confirmed'`, `persistent=false`, `action_url=/account/spec/{id}/request-refund`).
8. `dispatchSpecOperatorNotification`: one rail row per SPEC operator (`company_id=OPS_OPERATIONS_COMPANY_ID`, `type='spec_deposit_received'`, `persistent=true`, `action_url=/admin/spec/{id}`).
9. `sendConversionEvent('stripe_checkout_completed', ...)` — primary funnel conversion, written to `conversion_event_outbox`.
10. `spec_communications` system audit row.

**Charge dispute branch**:

1. Lookup `spec_payments` by `stripe_payment_intent_id`. No match → return `{ ok: true, status: 'skipped' }` (let any non-SPEC dispute handler take it — none exists today on ops-site).
2. Flip the matched `spec_payments.status='disputed'`.
3. Update all `spec_module_entitlements` for the engagement: `enabled=false, disabled_reason='dispute', disabled_at=now()` (the `disabled_reason` check constraint allows the value).
4. `spec_communications` system row with `summary='Stripe dispute opened — {reason}'` + dispute id + payment_intent + charge id + `guarantee_window_closed: true` flag. **The live `spec_projects` schema does NOT carry `has_active_dispute`/`dispute_opened_at`/`guarantee_window_closed_at` columns; this is the canonical Phase 1 representation.** Dispute evidence is the union of: `spec_payments.status='disputed'` + `spec_module_entitlements.disabled_reason='dispute'` + this `spec_communications` row + the operator/customer notifications. See [SPEC/02A_SCHEMA_CORRECTIONS_2026-05-26.md § 4](SPEC/02A_SCHEMA_CORRECTIONS_2026-05-26.md) for the decision rationale.
5. `dispatchSpecOperatorNotification('spec_dispute_opened', persistent=true)` — every SPEC operator + a direct dispute-alert email enqueued via `spec_email_outbox` to `jack@opsapp.co` (templated via the `spec.refund_denied` slot with an `__operator_alert` payload flag; the dedicated dispute template is Phase 2 evidence-package work).
6. `dispatchSpecCustomerNotification('spec_dispute_opened', persistent=true)` — buyer gets a rail row so the dispute isn't a silent state change.

**Notification routing (locked per `SPEC-NOTIFICATION-RAIL-DEPRECATED`)**:

| Audience | `company_id` | `persistent` | `action_url` |
|---|---|---|---|
| Customer (buyer/account_holder) | `linked_company_id` (non-null per `SPEC-NO-COMPANY-BUYER-FLOW-LOCK`) | `false` (deposit confirmed); `true` (dispute) | `/account/spec/{id}/request-refund` (Phase 1 only customer-facing route) |
| Operator (every SPEC operator) | `OPS_OPERATIONS_COMPANY_ID` = `00000000-0000-0000-0000-00000000000a` | `true` | `/admin/spec/{id}` |

SPEC operators are enumerated by `getSpecOperatorUserIds()` — the union of:
- `user_roles` joined to `role_permissions(permission='spec.admin', scope='all')` via the `SPEC Operator` role (`id='00000000-0000-0000-0000-0000000000a1'`)
- `user_permission_overrides(permission='spec.admin', granted=true)` (by convention every override row carries `company_id=OPS_OPERATIONS_COMPANY_ID`)

This matches the data source of `private.is_spec_operator()` (SQL function) — the TS helper is a parallel implementation for service-role server routes that need to fan out operator notifications.

**Test infrastructure**:

- `ops-site/scripts/spec-webhook-test.ts` — Node built-in assert unit tests. 15/15 pass. Covers: `isQuebecPostStripeLeak` predicate (state/country variants + null/undefined); idempotency dedup (both branches); Quebec defense (QC + non-CA both trigger refund + cancel + block-list + operator notification + audit row); normal deposit_paid flow (all the side effects above except email_outbox + conversion_event_outbox, which go through C.1's service-role-singleton helpers); malformed-metadata error path; dispute handler positive + skipped + duplicate paths.
- `ops-site/scripts/spec-webhook-integration.ts` — end-to-end script against a real Supabase env. Inserts an `is_test=true` `spec_projects` fixture under OPS Operations company with Jackson as buyer, runs both handlers, verifies all rows landed, cascade-cleans on teardown. Smoke-tested env validation; couldn't be executed end-to-end in this session because Supabase MCP wasn't exposed.

**Phase 1 documented invariants** (locked 2026-05-26; not follow-ups):

- `spec_projects` schema deliberately lacks `has_active_dispute`/`dispute_opened_at`/`guarantee_window_closed_at` columns for Phase 1. The dispute handler writes evidence across `spec_payments.status='disputed'` + `spec_module_entitlements.disabled_reason='dispute'` + `spec_communications` (system row) + operator/customer notifications — this is the canonical four-table representation. Three flag columns are deferred to Phase 2 and added only if dispute-evidence assembly (operator dashboard JOIN reads) exceeds ~250ms p95 at higher volume. Rationale: [SPEC/02A_SCHEMA_CORRECTIONS_2026-05-26.md § 4](SPEC/02A_SCHEMA_CORRECTIONS_2026-05-26.md).
- `tos_accepted_ip` is always NULL for Stripe-completed acceptance events because Stripe Checkout Sessions do not propagate the customer IP on the `checkout.session.completed` payload. `spec_acceptance_events.accepted_ip` is also NULL for the same Path A event. Path B owner-approval (Stage C.3) DOES capture the request IP from the inbound POST headers; it is NOT a Path A limitation. Rationale: [SPEC/02A_SCHEMA_CORRECTIONS_2026-05-26.md § 3](SPEC/02A_SCHEMA_CORRECTIONS_2026-05-26.md).

### `/spec/awaiting-approval` (Stage C.3)

**Source**: `ops-site/src/app/spec/awaiting-approval/page.tsx`. Landed on `feat/spec-owner-approval`.

Path B intermediate wait state for buyers whose purchase is pending owner approval. Server component, auth-gated. Looks up the most-recent `spec_owner_approval_requests` row where `buyer_user_id = <signed-in user>` and `status = 'pending'`. No pending row → redirect to `/spec` (defensive — the buyer probably hit the URL out-of-band). Pending row → renders the owner name + company + tier + cost copy. No CTA — this is a wait state. When the owner approves, the buyer receives the `spec.owner_approval_granted` email with the checkout link.

### `/spec/owner-approval/[approval_token]` (Stage C.3)

**Source**: `ops-site/src/app/spec/owner-approval/[approval_token]/page.tsx`. Landed on `feat/spec-owner-approval`.

Account-holder approval landing page reached via the `spec.owner_approval_required` email link. The URL token is bcrypt/argon2-equivalent — SHA-256 hashed (192-bit entropy plaintext) — and never stored in plaintext. Lookup chain (every check is a security boundary):

1. SHA-256 the URL segment; select from `spec_owner_approval_requests` where `approval_token_hash = <hash>`. No match → `notFound()` (never disclose which side failed).
2. Status gate: `approved` / `declined` / `expired` → render already-acted state, no CTAs.
3. Soft expiry: `requested_at + 7 days < now()` → render expired state even if cron hasn't flipped status yet.
4. Auth gate: no signed-in user → redirect to OPS-Web sign-in with `returnTo` back to this URL.
5. Account-holder match: signed-in `users.id != account_holder_user_id` → friendly wrong-user error (never reveal the right account).
6. Render buyer name + tier + 4-milestone cost breakdown + ToS reference + the `<OwnerApprovalForm />` client component.

The page itself is read-only; the writes happen via `POST /api/spec/owner-approval/[token]`.

### POST `/api/spec/owner-approval/[token]` (Stage C.3)

**Source**: `ops-site/src/app/api/spec/owner-approval/[token]/route.ts`. Landed on `feat/spec-owner-approval`.

Server-only handler for the Approve / Decline action. Hard rules — every one is a security boundary:

1. **Auth first**: verify Firebase / Supabase ID token via `getCurrentUserFromRequest`. No user → 401.
2. **Token lookup**: SHA-256 hash + `eq('approval_token_hash', ...)`. No match → 404 (never disclose).
3. **Account-holder match**: `currentUser.id !== row.account_holder_user_id` → 403. We do NOT trust anything in the URL or body to identify the actor.
4. **Status check**: must be `pending` → 409 with reason code if not.
5. **TTL check**: `requested_at + 7 days < now()` → 410 Gone; the status is also flipped to `expired` so future hits short-circuit.
6. **Branch on action**:

**Approve**:
- Update `spec_owner_approval_requests` (`status='approved'`, `decided_at`, `decided_ip`, `decided_user_agent`, `buyer_checkout_token_hash`, `buyer_checkout_expires_at = now() + 24h`). The `.eq('status', 'pending')` race-guard prevents double-approval.
- Update `spec_projects` (`status='awaiting_deposit'`, `owner_approved_at`, `checkout_token_issued_at`, `checkout_token_expires_at`).
- Insert `spec_acceptance_events` row with `event_type='owner_purchase_approved'`, `signature_method='click_in_app'` (per the live DB CHECK constraint — `owner_approval_click` is NOT in the allowed enum), `payload_hash = approved_tos_version_hash`. This is the binding acceptance event for the account-holder; the buyer's `tos_accepted` event lands later at Stripe payment completion (Stage C.2).
- Generate a 192-bit plaintext `buyer_checkout_token` via `generateApprovalToken()`; store ONLY the SHA-256 hash in `buyer_checkout_token_hash`.
- Queue `spec.owner_approval_granted` to the buyer's email with the plaintext token in the URL.
- Emit `owner_approval_requested` conversion event with `outcome='approved'`.
- Returns `{ status: 'approved' }`.

**Decline**:
- Update `spec_owner_approval_requests` (`status='declined'`, `decided_at`, IP, UA).
- Update `spec_projects` (`status='cancelled'`, `cancellation_reason='owner_declined'` plus optional free-text suffix, `cancelled_at`, `owner_declined_at`).
- Queue `spec.owner_approval_declined` to the buyer.
- Emit `owner_approval_requested` conversion event with `outcome='declined'`.
- Returns `{ status: 'declined' }`.

All DB writes use the service-role client (SPEC tables are RLS-locked).

### `/spec/checkout/[buyer_checkout_token]` (Stage C.3)

**Source**: `ops-site/src/app/spec/checkout/[buyer_checkout_token]/page.tsx`. Landed on `feat/spec-owner-approval`.

Path B final step. The buyer clicks the checkout link in the `spec.owner_approval_granted` email and lands here. Server component / loader:

1. SHA-256 the URL segment; select `spec_owner_approval_requests` where `buyer_checkout_token_hash = <hash>`. No match → "invalid link" page.
2. Soft expiry: `buyer_checkout_expires_at <= now()` → "expired" page with "Request a new approval" CTA.
3. Status check: must be `approved`. `declined` → friendly declined page; anything else → invalid.
4. Auth gate: no signed-in user → redirect to OPS-Web sign-in.
5. Buyer match: `currentUser.id !== buyer_user_id` → wrong-user page.
6. Project sanity: `spec_projects.status` must be `awaiting_deposit`; billing fields must be populated (C.1 wrote them).
7. **Single-use lock**: atomic `update ... set buyer_checkout_token_hash = null where id = ? and status = 'approved' and buyer_checkout_token_hash = ?`. If no row updated, the token was consumed by a parallel race → "already used" page.
8. Create Stripe Checkout Session via the shared `createSpecStripeCheckoutSession()` helper (locked SPEC-STRIPE-ADDRESS-TAX-SPIKE field set).
9. Emit `stripe_checkout_opened` conversion event with `path='path_b_post_approval'`.
10. `302` redirect to the Stripe URL.

If Stripe fails after the token was consumed, the route best-effort restores the hash so the buyer can retry (status still `approved`, expiry not yet hit).

### Shared helper — `src/lib/spec/stripe-session.ts` (Stage C.3 extraction)

`createSpecStripeCheckoutSession()` is the single enforcement point for the locked SPEC-STRIPE-ADDRESS-TAX-SPIKE contract. Used by:
- `/api/spec/create-checkout-session` Path A (buyer == account_holder)
- `/spec/checkout/[buyer_checkout_token]` Path B post-approval (buyer ≠ account_holder)

The helper owns: Stripe Customer get-or-create (persists `companies.stripe_customer_id` on first creation), Checkout Session creation with the full locked field set (`automatic_tax`, `billing_address_collection`, `consent_collection.terms_of_service`, `phone_number_collection`, GST/HST `custom_fields`, full metadata payload incl. `tos_version_hash` + attribution UTMs/click ids), and `spec_projects` update with `stripe_customer_id` + `stripe_session_id`.

### GET `/spec/intake/[token]` (Stage C.4)

**Source**: `ops-site/src/app/spec/intake/[token]/page.tsx`. Landed 2026-05-26 on `feat/spec-intake-form`.

Token-gated SPEC intake form. The plaintext token is emitted in the `spec.deposit_confirmed` email (Path A) or `spec.owner_approval_granted` checkout-token consumption (Path B); the DB stores only `spec_projects.intake_token_hash` (SHA-256 hex). Issuance happens in Stage C.2's webhook + Stage C.3's approval handler — not here. This page consumes the token: marks the intake completed on submit by stamping `intake_completed_at`.

**Behavior**:
- SHA-256 the URL segment; look up `spec_projects` where `intake_token_hash = <hash>`. No match → `notFound()` (never disclose).
- If `intake_completed_at` is set → friendly "you're done" panel with the Calendly link (no re-disclosure of project data beyond tier).
- Otherwise render `IntakeForm` (client component) prefilled with any autosaved `intake_responses` + the uploaded-files list.

**Calendly**: env `SPEC_DISCOVERY_CALENDLY_URL` (configurable without code deploy). If unset, the form still submits; the post-submit panel says scheduling arrives by email.

**SEO**: `robots: { index: false, follow: false }`. Pages keyed by token must never appear in search results.

### POST `/api/spec/intake/submit` (Stage C.4)

**Source**: `ops-site/src/app/api/spec/intake/submit/route.ts`.

The canonical SPEC intake submission endpoint. Token-gated. Three independent gates run in order; failing any of them returns 422 with operator notification + NO intake_completed_at flip:

1. **Regulated-workflow attestation** — if any of `phi_phipa` / `pci_raw_card` / `regulated_credit` / `surveillance` / `casl_bulk_messaging` is `true`, the submission is blocked. The server stamps `spec_projects.regulated_workflow_flagged_at = now()`, stores the attestations in `regulated_workflow_flags`, and fans out a **persistent** operator notification per SPEC operator with `type='spec_intake_regulated_workflow_flagged'` and `action_url='/admin/spec/{id}'`. The response carries `code='regulated_workflow_blocked'`, the failing keys, and `refund_path='/account/spec/{id}/request-refund'`.
2. **Quebec intake re-check** — if any of `qc_head_office` / `qc_operating_address` / `qc_establishment` / `qc_material_use` is `true`, the submission is blocked. Persistent operator notification with `type='spec_intake_quebec_flagged'`. Response carries `code='quebec_intake_blocked'`, the failing keys, and the same `refund_path`.
3. **File path traversal** — every entry in `uploaded_file_paths` must start with `{spec_project_id}/`, contain no `..` segments, and end in one of the allowed extensions (`pdf`, `png`, `jpg`, `jpeg`, `docx`, `xlsx`). Failure → 422 with `code='file_path_invalid'`.

**Happy path**:
1. `update spec_projects set intake_responses = {...full payload with attestations + submitted_at}, intake_completed_at = now(), intake_files = <paths jsonb> where id = ? and intake_completed_at is null` (concurrent-safe; the second submitter sees `null` rowcount).
2. Queue `spec.intake_completed_customer` in `spec_email_outbox` for the buyer.
3. Insert customer notification (`type='spec_intake_completed'`, `action_url='/account/spec/{id}'`).
4. Fan out operator notifications (`type='spec_intake_completed_operator'`, non-persistent, `action_url='/admin/spec/{id}'`) to every SPEC operator (members of role `00000000-0000-0000-0000-0000000000a1` + `user_permission_overrides` for `spec.admin granted=true`). Operator rows carry `company_id = OPS_OPERATIONS_COMPANY_ID`.
5. Enqueue `intake_submitted` in `conversion_event_outbox`.
6. Respond `200 { ok: true, redirect_to: SPEC_DISCOVERY_CALENDLY_URL | null }`.

### POST `/api/spec/intake/upload` (Stage C.4)

**Source**: `ops-site/src/app/api/spec/intake/upload/route.ts`. `runtime = 'nodejs'` so Buffer + crypto are available.

Multipart upload to Supabase Storage bucket `spec-intake`. The Phase 1 storage migration (`2026-05-25-spec-phase1-08-storage.sql`) makes the bucket operator-only at the RLS layer, so customer uploads go through this server route — the service-role client (RLS bypass) writes the object on the customer's behalf.

**Request**: `multipart/form-data`
- `token` (string, plaintext intake token)
- `file` (File, single per request)

**Server-authoritative checks (never trust the client)**:
- 25 MB cap (`SPEC_INTAKE_MAX_BYTES = 26214400`)
- MIME whitelist: `application/pdf`, `image/png`, `image/jpeg`, `application/vnd.openxmlformats-officedocument.wordprocessingml.document`, `application/vnd.openxmlformats-officedocument.spreadsheetml.sheet`
- Filename sanitization: `[^A-Za-z0-9._-]+` → `_`, max 60 chars stem, extension derived from MIME (never from filename).
- Path layout: `{spec_project_id}/{random_hex}-{sanitized_filename}.{ext}` — the random hex prevents collisions and obscures from object-listing brute force.

**Response**: `200 { path, content_type, size_bytes, original_filename }`. The form holds the returned `path` array; the submission route validates that every path is under the project's prefix before stamping `spec_projects.intake_files`.

### POST `/api/spec/intake/autosave` (Stage C.4)

**Source**: `ops-site/src/app/api/spec/intake/autosave/route.ts`.

Per-field debounced save into `spec_projects.intake_responses` jsonb. The client side debounces 500ms per field and fires on blur (text) / change (checkbox + select).

**Request**: `{ token, field_path, value }`
- `field_path` must match `/^[a-zA-Z][a-zA-Z0-9_]{0,30}(?:\.[a-zA-Z][a-zA-Z0-9_]{0,30}){0,4}$/` — at most 5 dotted segments, alphanumeric + underscore only.
- Top-level keys `regulated_workflow_attestations`, `quebec_intake_attestations`, `uploaded_file_paths`, `submitted_at` are **reserved** for the submit endpoint and rejected from autosave (preventing operational fields from being client-driven mid-intake).
- Submission blocked when `intake_completed_at` is non-null (404).

**Response**: `200 { saved_at: ISO-8601 }`. Lightweight, idempotent.

### Schema additions — Stage C.4 (`2026-05-26-03-spec-phase1-intake-columns.sql`)

Additive migration on `spec_projects` (all `add column if not exists` — Stage C.2 and Stage C.4 can land in either order):

| Column | Type | Notes |
|---|---|---|
| `intake_token_hash` | text | SHA-256 hex (64 chars) of the plaintext URL token. Unique partial index when not null. Set by Stage C.2 webhook at `deposit_paid`. |
| `intake_token_issued_at` | timestamptz | When the token was issued. |
| `intake_files` | jsonb default `'[]'::jsonb` | Array of Supabase Storage object paths uploaded under `spec-intake/{id}/`. Stamped on submit. |
| `regulated_workflow_flagged_at` | timestamptz | Set if intake submission triggered the regulated-workflow gate. NEVER flipped to non-null alongside `intake_completed_at`. |
| `regulated_workflow_flags` | jsonb | The 5-key attestation payload as submitted, for the operator review queue. |

### Supabase Storage usage — `spec-intake`

Bucket configured by `2026-05-25-spec-phase1-08-storage.sql`:
- `public: false` — signed URLs only (24h TTL, regenerated each time the operator detail page opens).
- `file_size_limit: 26214400` (25 MB).
- `allowed_mime_types: [application/pdf, image/png, image/jpeg, .docx, .xlsx]`.
- RLS on `storage.objects`: operator-only `select`, `insert`, `update`, `delete` via `private.is_spec_operator()`.

Customer uploads go through `/api/spec/intake/upload` (token-gated, service-role write). The submit route validates every returned path against the project's prefix before persisting `intake_files`. Path traversal (`..`, leading `/`, escape into another project's folder) is hard-rejected.

Object retention: 90 days after the engagement reaches a terminal state (`completed`, `cancelled`, `refunded`). A future weekly cron prunes; customers may request earlier deletion via the off-boarding flow.

### Environment variables — Stage C.4

- `SPEC_DISCOVERY_CALENDLY_URL` (optional) — the live discovery scheduling link. Read at request time so it can rotate without a code deploy. Falls back to "scheduling arrives by email" copy when unset.

### POST `/api/account/spec/[id]/request-refund` (Stage D — OPS-Web)

**Source**: `OPS-Web/src/app/api/account/spec/[id]/request-refund/route.ts`. Landed 2026-05-26 on `feat/spec-refund-request` (OPS-Web).

**Purpose**: Phase 1 minimal customer-facing route for filing a Guarantee Refund or post-window goodwill request. Every operational field on `spec_refund_requests` is server-computed; the customer cannot influence eligibility, refund amount, Stripe IDs, internal notes, processing controls, or entitlement toggles. Admin processing remains in `/admin/spec/refunds` (Stage F).

**Auth**: Firebase ID token (web) or Supabase JWT (iOS) via Authorization header or `__session` / `ops-auth-token` cookie. The verified user MUST match `spec_projects.buyer_user_id` OR `spec_projects.account_holder_user_id` — non-members get a 404 (never 403) to avoid existence disclosure per SPEC-SERVER-ROUTES-VS-RAW-RLS-DECISION.

**Request body (JSON)**:

```jsonc
{
  "reason_text": "string (50–2000 chars; C0 control bytes stripped server-side, \\t \\n \\r preserved)"
}
```

**Response codes**:

| Status | Reason | Body |
|---|---|---|
| 201 | Request filed | `{ request_id: uuid }` |
| 400 | Malformed JSON | `{ error }` |
| 401 | Missing / invalid auth | `{ error: "Unauthorized" }` |
| 404 | Project not found OR caller is neither buyer nor account_holder | `{ error: "Not found" }` |
| 409 | A Guarantee invocation is already open for this engagement (partial-unique index `spec_refund_one_guarantee_per_project_idx`) | `{ error }` |
| 422 | `reason_text` missing / under 50 / over 2000 chars | `{ error }` |
| 500 | Project load or insert failure | `{ error }` |

**Server-computed eligibility** (`src/lib/spec/refund-eligibility.ts`):

```
isGuaranteeInvocation =
   walkthrough_completed_at IS NOT NULL
   AND walkthrough_completed_at + interval '30 days' > now()
   AND status NOT IN ('refunded', 'cancelled')
   AND no spec_payments row for this project has status = 'disputed'

isGoodwill = NOT isGuaranteeInvocation
```

Window states surfaced to the read-only UI: `active`, `expired`, `no_walkthrough`, `terminal`, `disputed`. The customer cannot influence which one applies.

**Side effects on 201**:

1. Inserts `spec_refund_requests` with `spec_project_id`, `request_source='customer_initiated'`, `customer_reason_text` (sanitized), `is_guarantee_invocation` + `is_goodwill` (server-computed), `status='pending'`. Stripe IDs, refund amounts, internal notes, processing controls, and entitlement toggles are NEVER set from this route.
2. Inserts a customer-facing in-app notification: `user_id=caller`, `company_id=spec_projects.linked_company_id` (skipped if null), `type='spec_refund_requested'`, `persistent=false`, `action_url=/account/spec/{id}/request-refund`.
3. Inserts a persistent operator notification PER spec operator returned by `getSpecOperatorUserIds()` (mirror of `private.is_spec_operator()`): `user_id=operator`, `company_id=OPS_OPERATIONS_COMPANY_ID` (`00000000-0000-0000-0000-00000000000a`), `type='spec_refund_request_pending'`, `persistent=true`, `action_url=/admin/spec/refunds`.
4. Writes an internal-only `refund_invoked` row to `conversion_event_outbox` (`internal_only=true`). Explicitly excluded from Meta CAPI + Google Enhanced ad-platform conversion signals per SPEC/04_CUSTOMER_UX.md § Failure modes — refund volume must never be used as an optimization signal.

**Idempotency**: the partial-unique index `spec_refund_one_guarantee_per_project_idx` (one `is_guarantee_invocation=true` row per project in `pending`/`processed`/`partial` status) enforces single-fire at the DB layer. The route detects the resulting `23505` error and maps it to HTTP 409.

**Page**: `OPS-Web/src/app/account/spec/[id]/request-refund/page.tsx` (server component). Verifies auth via cookie, loads the project + active dispute state + existing-guarantee state, renders the read-only eligibility context block + the client `RefundRequestForm`. Unauthenticated callers redirect to `/login?returnTo=/account/spec/{id}/request-refund`; non-members 404.

**Voice**: tactical, terse. Header `// REFUND REQUEST`; eligibility block `// ELIGIBILITY`; submit CTA "Submit refund request"; filed-state confirms request ID. Numbers in JetBrains Mono with `tabular-nums`. No emoji.

### POST `/api/admin/spec/board/refresh` (Stage F.1 — OPS-Web)

**Source**: `OPS-Web/src/app/api/admin/spec/board/refresh/route.ts`. Landed 2026-05-26 on `feat/spec-admin-overview` (OPS-Web).

**Purpose**: Operator-only manual force-refresh of `public.spec_public_board_snapshot`. The pg_cron job (`spec_board_snapshot_refresh`) handles the 5-minute background cadence; this route is the operator's "give me fresh numbers right now" affordance from the `/admin/spec` REFRESH BOARD header button.

**Auth**: Firebase ID token (web) or Supabase JWT (iOS) via Authorization header or `__session` / `ops-auth-token` cookie. After verifying the token + resolving the OPS user, the route re-checks `isSpecOperator(opsUser.id)` (the TS mirror of `private.is_spec_operator()`) — the `/admin/spec/layout.tsx` gate does NOT carry through to API routes, so the check is explicit and additive here. Customer-side company admins (those satisfying `is_company_admin / account_holder_id / admin_ids` but with no `spec.admin` role/override) are rejected with 403.

**Response codes**:

| Status | Reason | Body |
|---|---|---|
| 200 | Snapshot refreshed | `{ refreshed_at: ISO-8601 }` |
| 401 | Missing / invalid auth | `{ error: "Unauthorized" }` |
| 403 | Authenticated but not a SPEC operator | `{ error: "Forbidden" }` |
| 500 | Service-role env not configured | `{ error: "Service role not configured" }` |
| 502 | PostgREST RPC failed (e.g. wrapper migration not applied) | `{ error: "Snapshot refresh failed", detail }` |

**Side effects on 200**:

1. Calls `public.refresh_spec_board_snapshot()` (added by the Stage F.1 wrapper migration `2026-05-26-03-spec-stage-f1-board-refresh-wrapper.sql`) via the service-role supabase-js client. The wrapper is SECURITY DEFINER and delegates to `private.refresh_spec_board_snapshot()`; EXECUTE on the wrapper is granted to `service_role` only, so anon/authenticated cannot fire a refresh.
2. Reads the new `refreshed_at` back from `public.spec_public_board_snapshot` and returns it to the caller.
3. Calls `revalidateTag('spec-capacity')` so the next `/admin/spec` overview render reflects the updated snapshot.

**Why the wrapper exists**: `private.refresh_spec_board_snapshot()` lives in the `private` schema per `SPEC-SECURITY-DEFINER-PRIVATE-SCHEMA`. Default Supabase PostgREST only exposes `public, storage, graphql_public` — `private` is intentionally not exposed so anon/authenticated cannot reach SECURITY DEFINER helpers. The wrapper provides a PostgREST-callable surface that the operator-gated server route can hit via supabase-js without exposing the `private` schema publicly.

**Page surface**: `OPS-Web/src/app/admin/spec/_components/refresh-board-button.tsx` is the client component that posts to this route and re-renders the capacity panel with the new `refreshed_at` ("UPDATED [N min ago]" copy ticks live until the next manual or cron refresh).

### GET `/spec/confirmation` (Stage D — ops-site)

**Source**: `ops-site/src/app/spec/confirmation/page.tsx` + `ops-site/src/components/spec/SpecConfirmation.tsx` + `ops-site/src/components/spec/SpecMilestoneTimeline.tsx`. Landed 2026-05-26 on `feat/spec-confirmation-rewrite` (ops-site).

**Purpose**: Post-Stripe success surface. Server-side retrieves the Stripe Checkout Session (`expand: ['payment_intent', 'customer']`), verifies `metadata.type === 'spec_deposit'` and `payment_status === 'paid'`, and (when `spec_project_id` is in metadata + Supabase env is configured) loads the matching `spec_projects` row for milestone state and intake-token presence.

**Render modes**:

- `?session_id` missing → soft "no payment session detected" state.
- Session metadata.type ≠ `spec_deposit` or Stripe retrieve failure → soft "could not verify payment" state.
- `payment_status !== 'paid'` → soft "processing your payment" state.
- Verified + paid → full confirmation surface.

**Full confirmation surface**:

- `// DEPOSIT CONFIRMED` header + tactical session ID tail.
- `You're in.` hero (Cake Mono Light, sentence case; i18n key `confirmation.heading`).
- Session card (Package / Paid / Total) — Cake Mono Light for package, JetBrains Mono with `tabular-nums` for currency. Receipt sent line shows the customer email.
- Founder welcome block (`// OPERATOR :: JACKSON`). Optional `founderVideoUrl` prop drives the embed; default fallback is a placeholder pane with `[video shipping shortly]` per SPEC/07_ROLLOUT.md open item 1.
- 4-milestone timeline (`SpecMilestoneTimeline.tsx`): steel-blue rail strokes left-to-right; markers pop sequentially; current marker has a subtle 2.2s opacity pulse. Reduced-motion: instant final state, no pulse. Single easing curve `cubic-bezier(0.22, 1, 0.36, 1)`. Statuses derived from `spec_projects` timestamps (`scope_doc_signed_at`, `midpoint_accepted_at`, `walkthrough_completed_at`) or default to P1=paid, P2=current when no project row is available (Phase 0 fallback).
- Primary CTA `Open your intake link` → `/spec/intake/{plaintext_token}` when Stripe metadata carries an `intake_token` plaintext; otherwise `Check your inbox` fallback (the canonical intake-link delivery path is the `spec.deposit_confirmed` email; the DB stores only `intake_token_hash`).
- Secondary CTA `Book your discovery session` → `SPEC_DISCOVERY_CALENDLY_URL` server-side env (Stage C.4). Disabled-style fallback when unset.
- 30-day Guarantee Refund reminder anchored to walkthrough delivery, with link to `/legal?page=spec-terms` (Stage G port). Exclusion list inlined per SPEC/01_BUSINESS_MODEL.md § 3.
- Stripe receipt link (`payment_intent.latest_charge.receipt_url`).

**`force-dynamic` directive**: kept from Stage E. The page is keyed on `?session_id=` and must not be statically prerendered.

**Voice / typography**: tactical OPS — `// SECTION` slash prefixes, `[brackets]` for metadata, sentence case for body, Cake Mono Light 300 for uppercase display, JetBrains Mono for numbers with `font-variant-numeric: tabular-nums`. No emoji.

**i18n**: `src/i18n/dictionaries/{en,es}/spec.json` — `confirmation.heading`, `confirmation.subtitle`. Per-tier `confirmation.timeline.{setup|build|enterprise}` keys retained but not currently rendered (kept for future tier-specific copy).

### POST `/api/cron/spec-nudges` (Stage C.5 — ops-site)

**Source**: `ops-site/src/app/api/cron/spec-nudges/route.ts` + `ops-site/src/lib/spec/cron/*`. Landed 2026-05-26 on `feat/spec-cron-nudges` (ops-site). Migration: `ops-software-bible/migrations/2026-05-26-04-spec-stage-c5-cron-columns.sql` (applied to live ops-app on 2026-05-26 via Supabase MCP).

**Purpose**: SPEC Phase 1 daily nudge / status-flip / outbox-retry processor. Single Vercel cron endpoint that drives every time-anchored SPEC side effect. Replaces the placeholder cron commitment in 07_ROLLOUT.md § 12.

**Vercel cron schedule** (`ops-site/vercel.json`):

```json
{
  "$schema": "https://openapi.vercel.sh/vercel.json",
  "crons": [
    { "path": "/api/cron/spec-nudges", "schedule": "0 17 * * *" }
  ]
}
```

`0 17 * * *` UTC ≈ 09:00 America/Vancouver during PST (UTC-8). Drifts to 10:00 local during PDT (UTC-7). The one-hour DST drift is acceptable because none of the nudges are minute-sensitive (intake-reminder copy reads "your intake is waiting", not "your intake is waiting at 9am"). Vercel cron evaluates schedules in fixed UTC; there is no native local-TZ cron expression. **Cost note**: Vercel cron is free on Pro tier. The route is invoked once per day, finishes in seconds, well under the 300s default function timeout.

**Auth**: Vercel automatically attaches `Authorization: Bearer ${CRON_SECRET}` when `CRON_SECRET` is set as an env var on the project. The route validates the header with `crypto.timingSafeEqual` and 401s on mismatch. Missing `CRON_SECRET` env returns 500. The check is constant-time to avoid timing-leak inference of the secret. **Required env var for live deployment**: `CRON_SECRET`.

**Response shape (200)**:

```jsonc
{
  "status": "ok",
  "summary": {
    "ranAt": "2026-06-01T17:00:00.000Z",
    "durationMs": 482,
    "total": { "considered": 12, "fired": 7, "errored": 0 },
    "tasks": [
      { "task": "intake_reminders", "considered": 4, "fired": 2, "errored": 0, "details": [...] },
      // ... 7 more
    ]
  }
}
```

The route always returns 200 with this summary once `CRON_SECRET` validation passes — even if every task errored. The per-task `errored` counts surface failures without triggering Vercel's cron retry, which would compound a partial-success day.

**Tasks (executed sequentially, each in its own try/catch)**:

1. **`intake_reminders`** — `spec_projects` rows where `status='deposit_paid'` AND `intake_completed_at IS NULL`. Walks D14 / D21 / D28 cadence via `template_id IN (spec.intake_reminder_1, _2, _3)`. Idempotency via the new `intake_reminder_count` + `last_intake_reminder_at` columns (added by migration `2026-05-26-04`). Stages emails into `spec_email_outbox`; task 7 dispatches them on the same run.

2. **`intake_no_discovery_nudges`** — `spec_projects` where `intake_completed_at IS NOT NULL` AND `discovery_scheduled_at IS NULL`. Walks D7 / D14 / D21 cadence via `template_id IN (spec.intake_completed_no_discovery_1, _2, _3)`. Idempotency via new `intake_no_discovery_reminder_count` + `last_intake_no_discovery_reminder_at` columns.

3. **`owner_approval_expiry`** — `spec_owner_approval_requests` where `status='pending'` AND `expires_at < now()`. Flips approval `status='expired'`, stamps `decided_at=now()`. Flips parent `spec_projects.status='cancelled'` with `cancellation_reason='owner_approval_expired'`, `cancelled_at=now()`. The CHECK constraint `spec_projects_tos_required_after_deposit` requires TOS evidence outside the pre-deposit states; cancelling from `awaiting_owner_approval` requires stamping synthetic TOS placeholders (`tos_version_accepted='owner_approval_expired'`, `tos_accepted_at=now()`). The placeholder string is unambiguously distinguishable from real buyer-signed evidence both lexically and via the adjacent `cancellation_reason`. Sends `spec.owner_approval_expired_buyer` + `spec.owner_approval_expired_owner` (templates not yet registered in Stage H — open item below). Notifies buyer + account_holder via in-app rail + email. Notifies operators.

4. **`customer_requested_hold_expiry`** — `spec_projects` where `status='on_hold'` AND `hold_type='customer_requested'` AND `on_hold_expires_at < now()`. Flips `status='stalled_on_hold'`, stamps `stalled_at` + `stalled_reason='customer_requested_hold_expired'`. Per locked capacity semantics (03_WORKFLOW.md § Capacity-consuming states), customer_requested holds already freed the slot at hold-entry — no capacity change here. Sends `spec.hold_expired_customer_requested` (template not yet registered — open item below). In-app notification + operator notification.

5. **`ops_blocked_review_reminder`** — `spec_projects` where `status='on_hold'` AND `hold_type='ops_blocked'` AND `on_hold_at < now() - 14 days`. Dispatches a persistent operator notification (no customer-facing action) suggesting Jackson decide: convert to `customer_requested` (frees slot) or escalate to stall. Idempotency via new `ops_blocked_review_reminder_sent_at` column — won't refire for the same `ops_blocked` spell.

6. **`non_payment_disable`** — `spec_payments` where `status IN ('invoiced','overdue')` AND `due_date < (now() - 7 days)`. For each unique `spec_project_id`, flips every `spec_module_entitlements` row that isn't already at `disabled_reason='non_payment'` to `enabled=false, disabled_reason='non_payment', disabled_at=now()`. Detects "first-time" disable by checking if any entitlement row is still `enabled=true` OR has a different `disabled_reason` — won't notify twice. Sends `spec.modules_disabled_non_payment` (template not yet registered — open item below). Persistent customer + operator notifications.

7. **`spec_email_outbox_retry`** — `spec_email_outbox` rows where `status IN ('pending','failed')` AND `attempts < 5` AND `(last_attempt_at IS NULL OR last_attempt_at < now() - 1h)`. Capped at 500 rows per run. For each row, calls `dispatchSpecEmail()` which POSTs to OPS-Web's internal SPEC send endpoint (see Topology below). On success: `status='sent', sent_at=now()`. On transient failure: bump attempts, `status='failed'`. On permanent failure (4xx from OPS-Web): bump attempts; at attempt ≥ 5 mark `status='permanent_failure'` + operator notification. On not-configured (env vars missing): operator notification, task aborts without bumping attempts so a misconfiguration doesn't walk every row to permanent_failure.

8. **`conversion_event_outbox_retry`** — `conversion_event_outbox` rows with the same eligibility predicate. Per 07_ROLLOUT.md open item #8 (Meta CAPI + Google Enhanced credentials not yet provisioned at Phase 1 launch), the task short-circuits with a no-op when both env credential sets are absent — rows stay pending without bumping attempts. When credentials are present, the task invokes the Meta CAPI + Google Enhanced senders (currently a stub returning a `sender_not_implemented` transient failure — to be replaced when ad-platform sender modules land). The cron loop is in place and will start succeeding the moment the senders are wired.

**Run summary** is persisted via `persistRunSummary()` as a `spec_communications` system-channel row attached to the most-recently-created `spec_projects` row. The full JSON summary lands in the `body` column for replay. If there are zero `spec_projects` rows in the system, the persistence step is skipped (nothing to attach to via FK).

#### Topology decision — email dispatch (locked Stage C.5)

ops-site is the only place that owns `spec_email_outbox` writes (Stage C.1 onward — every checkout, webhook, owner-approval, intake-submit, refund-request path enqueues there). OPS-Web is the only place that owns SendGrid + the React Email `Spec*.tsx` templates (Stage H, commit `dec9c71d`). Rather than duplicate the template + SendGrid stack on the ops-site side OR cross-import OPS-Web modules (different repo, different package, different deploy target), the Stage C.5 cron drains `spec_email_outbox` by HTTP POSTing each pending row to OPS-Web's internal endpoint:

```
POST {OPS_WEB_INTERNAL_BASE_URL}/api/internal/spec/send-email
Authorization: Bearer ${OPS_INTERNAL_DISPATCH_SECRET}
Content-Type: application/json

{
  "template_id": "spec.intake_reminder_1",
  "recipient_email": "buyer@example.com",
  "recipient_user_id": "uuid-or-null",
  "spec_project_id": "uuid-or-null",
  "payload": { ... template-specific shape ... },
  "is_test": false
}
```

The OPS-Web endpoint (to be added as a separate sibling chip — see open items) resolves `template_id` → typed `sendSpec*()` sender from `OPS-Web/src/lib/email/sendgrid.tsx` (Stage H), invokes it, returns `{ status: 'sent' | 'suppression_skipped' | 'paused_skipped', messageId: string | null }` on 200. 4xx = permanent failure (template unknown, payload invalid). 5xx / timeout = transient failure (retry next cron run).

**Required env vars** on `ops-site` for live email dispatch:
- `OPS_WEB_INTERNAL_BASE_URL` (e.g. `https://app.opsapp.co`)
- `OPS_INTERNAL_DISPATCH_SECRET` (high-entropy shared secret matched on the OPS-Web endpoint via constant-time compare)

If either is missing, the cron logs a clear warning, posts a persistent operator notification (`spec_email_dispatch_misconfigured`), and skips the outbox-retry task — without bumping attempts. The rest of the cron (status flips, notifications, freshly-enqueued nudges) runs normally.

#### Schema additions (migration `2026-05-26-04`)

```sql
alter table public.spec_projects
  add column if not exists last_intake_reminder_at timestamptz,
  add column if not exists intake_reminder_count int not null default 0,
  add column if not exists last_intake_no_discovery_reminder_at timestamptz,
  add column if not exists intake_no_discovery_reminder_count int not null default 0,
  add column if not exists ops_blocked_review_reminder_sent_at timestamptz;

alter table public.spec_owner_approval_requests
  add column if not exists expires_at timestamptz;

-- Backfill + default-on-insert for new rows
update public.spec_owner_approval_requests
  set expires_at = requested_at + interval '7 days'
  where expires_at is null;

alter table public.spec_owner_approval_requests
  alter column expires_at set default (now() + interval '7 days');
```

Indexes added for the three cron candidate queries (intake-reminder lookup, no-discovery lookup, owner-approval expiry lookup). All ADDs are idempotent.

#### Notification model

Operator notifications fan out by reading `role_permissions` (`permission='spec.admin' AND scope='all'`) joined with `user_roles`, plus `user_permission_overrides` (`permission='spec.admin' AND granted=true`) — the same membership the `private.is_spec_operator()` function consults. Cron is service_role so it cannot call the SECURITY DEFINER function (no JWT); the explicit join is the correct approach. Operator rows are inserted with `company_id = OPS_OPERATIONS_COMPANY_ID` per the locked notification contract.

Customer notifications use the project's `linked_company_id` (guaranteed non-null per `SPEC-NO-COMPANY-BUYER-FLOW-LOCK`).

#### Cadence notes (documentation drift caught)

03_WORKFLOW.md § "Ghosted post-deposit (no intake)" describes a D14 / D30 / D60 / D90 cadence. 06_CONTRACT_AND_EMAILS.md cron-jobs table specifies D14 / D30 / D60. The Stage H template registry ships three reminder templates (`_1`, `_2`, `_3`). The Stage C.5 cron implements D14 / D21 / D28 to match the brief and to keep the cadence inside a single calendar month for ad-funnel optics. The drift will be reconciled in the next bible consolidation pass — flagged here for awareness.

#### Open items — Stage H templates not yet registered

The following template_ids are enqueued by the Stage C.5 cron but are NOT in the Stage H migration `2026-05-26-02-spec-phase1-email-templates.sql`:

- `spec.owner_approval_expired_buyer`
- `spec.owner_approval_expired_owner`
- `spec.hold_expired_customer_requested`
- `spec.modules_disabled_non_payment`

The OPS-Web internal dispatch endpoint will respond with a 4xx `invalid_template` for these until they ship; the outbox row will land in `permanent_failure` after 5 attempts and the operator notification path will surface the gap. **Follow-up chip** (`SPEC - P1-2-13` or higher): add these four templates to the Stage H registry + migration.

#### Open item — OPS-Web `/api/internal/spec/send-email` endpoint

The HTTP target of `dispatchSpecEmail()` does not yet exist in OPS-Web. The contract is locked above. **Follow-up chip**: implement the endpoint as a Bearer-gated route in OPS-Web that:

1. Verifies `Authorization: Bearer ${OPS_INTERNAL_DISPATCH_SECRET}` via constant-time compare.
2. Validates body shape (template_id known, recipient_email valid, payload is an object).
3. Resolves `template_id` → typed sender from `template-registry.ts`. Calls the typed sender with the payload.
4. Returns `{ status, messageId }` per the contract above.

Until that endpoint ships, the Stage C.5 cron writes the outbox row but cannot dispatch — pending rows accumulate. The persistent operator notification keeps the gap visible.

#### Verification artifacts

- Migration applied to live `ijeekuhbatykdomumfjx` via Supabase MCP on 2026-05-26 (`spec_stage_c5_cron_columns`).
- 19 unit tests in `ops-site/src/lib/spec/cron/__tests__/` cover the five critical tasks (intake reminders fire-once + thresholds + skip-rules; owner-approval expiry with synthetic-TOS placeholder; customer_requested hold expiry; non-payment 7-day threshold incl. idempotency; CRON_SECRET 401/500/200 paths). All pass.
- `tsc --noEmit` exits clean on the worktree.
- `npm run lint` adds zero new errors/warnings inside the new cron files (the prior 108 base-branch problems are unchanged and tracked separately).
- `npm run build` fails on the pre-existing `/spec/confirmation` Suspense boundary issue (Stage D scope), not on Stage C.5 code. Confirmed identical failure exists on `feat/spec` HEAD without the C.5 changes.

---

## SPEC `/admin/spec/[id]` server actions (Stage F.2.a — 2026-05-26)

OPS-Web `/admin/spec/[id]` ships four server actions for the F.2.a sub-chip. Every action re-checks `isSpecOperator(userId)` server-side via the shared `requireSpecOperatorUserId()` helper in `src/app/admin/spec/[id]/_actions/_require-operator.ts` — the route layout enforces the gate for the rendered page, but server actions can be invoked by any logged-in client, so the gate is re-applied at write time. None of these endpoints accept customer callers.

| Action file | Form fields | Effects |
|---|---|---|
| `_actions/fire-milestone.ts` | `project_id`, `milestone` (`scope_signoff` \| `midpoint` \| `delivery`) | Re-derives fireability against live data (`getMilestoneFireability`), ensures Stripe customer for `linked_company_id`, creates Stripe Invoice (`collection_method=send_invoice`, `auto_advance=true`, `days_until_due=15` = net-15 — Stripe auto-emails the hosted invoice), inserts `spec_payments` row (`status=invoiced`, `invoiced_at=now()`, `due_date=now()+15d`, `stripe_invoice_id=…`), enqueues `spec_email_outbox` row keyed `spec.p{2,3,4}_invoice` for the Stage H branded follow-up, logs a `spec_communications` system row, and inserts an operator-facing `public.notifications` row (`type='spec_invoice_fired'`, `company_id=OPS_OPERATIONS_COMPANY_ID`). Rolls back the `spec_payments` row if Stripe creation fails so the operator can retry. P1 is never accepted here (Stripe webhook owns it). |
| `_actions/new-scope-revision.ts` | `project_id` | Reads the current `spec_scope_documents` row, stamps `superseded_at=now()` on it, inserts a new row with `version = prior + 1`, carries over `content_json` (operator can then edit externally), copies the feature acceptance scaffold from the prior version (reset to `status='pending'`). Inherits `is_test` from the project. Idempotency under concurrent operator clicks is the table's unique `(spec_project_id, version)` index — the slow writer surfaces an error. |
| `_actions/mark-feature.ts` | `project_id`, `feature_id`, `target_status` (`passing` \| `failing` \| `pending`) | Verifies the feature row's `spec_project_id` matches the supplied project (prevents cross-project writes). Updates `status`, `verified_at` (now or null), `verified_by_user_id` (operator or null), clears `failure_notes` when transitioning away from `failing`. Logs a `spec_communications` system entry. |
| `_actions/update-eta.ts` | `project_id`, `estimated_completion_date` (YYYY-MM-DD or empty) | Validates ISO date format, updates `spec_projects.estimated_completion_date` + `updated_at`. Empty string clears the column. Logs a `spec_communications` system entry. |

**Operator-gate contract** (locked, do not deviate): never call `public.has_permission(...)` — that helper short-circuits to true for any customer-company admin via `is_company_admin`, `account_holder_id`, or `admin_ids`. Use the dedicated TS mirror `isSpecOperator(userId)` from `src/lib/admin/spec-permissions.ts`, which only consults `role_permissions(permission='spec.admin', scope='all')` via `user_roles` AND `user_permission_overrides(permission='spec.admin', granted=true)`. The shared `requireSpecOperatorUserId()` helper applies this gate identically across all four actions and returns `null` for non-operators — actions translate that into a thrown `Error("SYS :: SPEC OPERATOR GATE DENIED")`.

**Email-outbox contract.** Branded SPEC milestone emails (Stage H templates `spec.p2_invoice` / `spec.p3_invoice` / `spec.p4_invoice` / `spec.scope_doc_ready` / `spec.scope_doc_signed_customer`) are queued via `spec_email_outbox` (`status='pending'`, `payload` jsonb carrying `tier`, `milestone`, `amount_cents`, `invoice_number`, `stripe_invoice_url`, `due_date`, `buyer_name`, `company_name`). Stage H's worker drains the queue. Until Stage H merges, Stripe's own hosted-invoice email (sent by `auto_advance=true` on invoice finalize) handles customer notification and the outbox rows accumulate as a clean audit trail.

**Cache invalidation.** Every action ends with `revalidatePath('/admin/spec/${id}')`. Fire-milestone additionally revalidates `/admin/spec` so the overview Kanban + TODAY queue reflect the new invoiced row.

**Stripe Dashboard linkout.** The Tab 5 Milestones table renders `stripe_invoice_id` as a click-through to `${NEXT_PUBLIC_STRIPE_DASHBOARD_BASE}/invoices/${id}` (defaults to `https://dashboard.stripe.com`); set the env var to `https://dashboard.stripe.com/test` in non-prod environments.

## SPEC `/admin/spec/[id]` server actions (Stage F.2.b — 2026-05-26)

Tab 6-11 (Change orders / Satisfaction / Tickets / Comms / Entitlements / Notes) ship seven additional server actions. Same operator-gate contract as F.2.a — `requireSpecOperatorUserId()` re-validates before every mutation; the gate is enforced both at the route layout (rendered page) AND at write time (action body) so any direct POST is rejected.

| Action file | Form fields | Effects |
|---|---|---|
| `_actions/create-change-order.ts` | `project_id`, `change_type` (`minor_hourly` \| `major_fixed` \| `tier_upgrade`), `title`, `description`, `estimated_hours` (minor only, 0.5–3.5h required), `fixed_price_cents` (major/tier-upgrade required, > 0), `delivery_impact_days` | Branches on `change_type`. Inserts `spec_change_orders` row (`status=proposed`, `hourly_rate_cents=22500` locked at $225 CAD/hr per § 6, half-hour bucketing enforced by the input step). Inserts `spec_communications` system row + operator notification. Customer acceptance is recorded later via `spec_acceptance_events.change_order_accepted`; Stripe invoice firing happens AFTER acceptance via a future chip — F.2.b's wizard ends at proposed. Hours ≥ 4 are rejected with a directive to use `major_fixed` instead. |
| `_actions/create-ticket.ts` | `project_id`, `severity` (`critical` \| `high` \| `cosmetic_enhancement`), `phase` (`support` \| `retainer` \| `ad_hoc`), `title`, `description` | Inserts `spec_support_tickets` row (`status=open`). Inserts `spec_communications` system row + operator notification. Phase 1: operator can log on the customer's behalf; customer-side filing UI ships Phase 2 (`/account/spec/[id]`). |
| `_actions/escalate-ticket.ts` | `project_id`, `ticket_id`, `op` (`reclassify` \| `escalate_to_change_order`), `new_severity` (reclassify only) | Two branches: `reclassify` stamps the original `customer_classification` once and updates `severity`; `escalate_to_change_order` creates a `proposed` `spec_change_orders` row (defaults to `change_type=minor_hourly`, title prefixed `[ESCALATED]`), sets the ticket `status=escalated_to_change_order` and `linked_change_order_id`, stamps `resolved_at=now()`. The escalation path rolls back the change order if the ticket update fails so the operator can retry without a dangling proposed row. |
| `_actions/log-communication.ts` | `project_id`, `channel` (`call_log` \| `video_message` \| `admin_note`), `direction` (`outbound` \| `inbound`), `summary`, `body` (optional) | Inserts `spec_communications` row with `logged_by_user_id=operator`. Only manual channels are accepted — `email` flows through `send-template-email`, `system` rows are auto-written by other actions. |
| `_actions/send-template-email.ts` | `project_id`, `template_id` (must be a registered SPEC key in `src/lib/email/constants.ts`), `recipient_email_override` (optional; defaults to `customer_email`), `operator_note` (optional payload field) | Validates template against the registered Stage H SPEC block (20 keys), writes a `spec_email_outbox` row via `writeSpecEmailOutbox()` carrying `tier`, `customer_name`, `operator_note`. Stage H cron drains the queue and ships via SendGrid. Inserts `spec_communications.email` row (`logged_by_user_id=operator`) so the send is visible in Tab 9 immediately, before the cron drains. |
| `_actions/toggle-entitlement.ts` | `project_id`, `entitlement_id`, `intended_state` (`enabled` \| `disabled`), `disabled_reason` (disable only) | **OPERATIONALLY CRITICAL.** Updates `spec_module_entitlements.enabled` + stamps `enabled_at` / `disabled_at` + `disabled_reason`. Disabling validates the reason against the `CHECK` constraint enum (`non_payment` / `dispute` / `refunded` / `subscription_lapse` / `customer_request` / `ops_decision` / `not_yet_delivered`). Enabling rejects the action when `disabled_reason` is terminal (`refunded` or `subscription_lapse`) — only the refund/Stripe flow can clear those. Side-effects on every successful toggle: (1) `audit_log` row keyed `table_name='spec_module_entitlements'`, `record_id=<entitlement_id>`, `company_id=OPS_OPERATIONS_COMPANY_ID`, `action='UPDATE'`, full `old_data` + `new_data`; (2) `spec_communications` system row; (3) customer-facing `public.notifications` row (`company_id=linked_company_id`, `persistent=true` on disable) — the customer sees the access change in the in-app rail; (4) `spec_email_outbox` row keyed `spec.entitlement_disabled` / `spec.entitlement_enabled` (these template_ids are **NOT yet registered in Stage H** — flagged as a follow-up; the outbox row queues correctly and ships once Stage H adds the renderer); (5) operator-facing notification. |
| `_actions/save-notes.ts` | `project_id`, `body` (text up to 50KB, raw — leading/trailing whitespace preserved) | Append-only revision log. Each save inserts a new row in `spec_internal_notes` (additive migration `20260526220200_spec_internal_notes.sql` — operator-only RLS via `private.is_spec_operator()`). Skips the insert when the incoming body matches the latest revision verbatim — idempotent under autosave-on-blur. Operator-only; never surfaced to the customer side. |

**Hard rules locked at the action layer (do not deviate):**
- Every action re-applies the operator gate via `requireSpecOperatorUserId()`. No `has_permission()` shortcut.
- Every action narrows by `project_id`. Cross-project writes are explicitly rejected (escalate-ticket validates the ticket's `spec_project_id` matches the supplied project; toggle-entitlement does the same for the entitlement row).
- Every change order, ticket, communication, and entitlement toggle inherits `is_test` from the parent `spec_projects` row so test-mode boundary holds.
- Entitlement toggle audit_log writes use `record_id = entitlement uuid` (not a hand-rolled per-tier UUID like `spec_capacity`), per the audit_log table's `uuid NOT NULL` shape.

**Open items flagged for follow-up chips:**
- `spec.entitlement_disabled` / `spec.entitlement_enabled` email templates are queued in the outbox but **not yet rendered by Stage H**. A future Stage H drop must add the React Email components + register the keys in `src/lib/email/constants.ts` SPEC block. Until then, the customer sees the in-app notification (which works today) but no email.
- Change order Stripe invoice firing is OUT OF SCOPE for F.2.b — the existing milestone-fire pattern from F.2.a is the model. A future chip wires `customer_approved` acceptance → invoice fire for change orders.
- Customer-facing ticket filing UI is Phase 2 (`/account/spec/[id]`).

**spec_internal_notes additive migration:** `2026-05-26-06-spec-stage-f2b-internal-notes.sql` (mirrored at `ops-software-bible/migrations/`). Table is operator-only (RLS via `private.is_spec_operator()`). Row shape: `id uuid PK`, `spec_project_id uuid FK`, `body text NOT NULL`, `created_at timestamptz`, `created_by_user_id uuid FK to users`, `is_test boolean`. Index on `(spec_project_id, created_at desc)`.

## Canonical Email Attachment Routes (prepared 2026-07-15)

| Route | Contract |
|-------|----------|
| `GET /api/cron/email-attachment-worker` | Cron-secret-only bounded dispatcher. Claims durable scan and inspection jobs; never sends mail or mutates provider mailboxes. |
| `GET /api/inbox/threads/[id]/attachments` | Authenticated, company/mailbox-scoped canonical metadata for the thread. Reads OPS rows only and chunks large attachment-ID lookups. |
| `GET /api/integrations/email/attachment?id=<uuid>` | Authenticated byte stream by canonical attachment UUID. Requires `inbox.view` or `pipeline.view`, verifies tenant/mailbox ownership, ignores caller MIME/provider identifiers, and reads only private OPS storage. Conservative raster types may render inline; everything else downloads with `nosniff`, restrictive CSP/sandbox, and private caching. |
| `POST /api/integrations/email/extract-images` | Backward-compatible import dispatcher. Resolves exact activities and enqueues canonical scans; it no longer uploads public images or overwrites `opportunities.images`. |

Email sync persists the activity and correspondence state, then advances its provider cursor without downloading files or running vision. The database activity trigger owns durable scan enqueue, so a slow/large attachment cannot replay or stall ordinary mail ingestion. The five-minute worker cron performs bounded read-only provider enumeration/download and private copy afterward. Gmail and Microsoft provider requests have abort deadlines; enumeration/file/aggregate budgets produce retry or explicit review provenance instead of unbounded work.

No attachment route or worker calls Gmail/Graph send, draft, label, delete, move, or modify operations.

---

## Internal Agent Operational, Communication, and Participant Reads (local, externally dark 2026-08-14)

`OpsAgentDomainService` locally exposes four transport-neutral operational methods in addition to `getJobConversationContext`: `listScheduledJobs(actor, input, options?)`, `listJobReadinessIssues(actor, input, options?)`, `getJobCommunicationContext(actor, input, options?)`, and `resolveJobParticipants(actor, input, options?)`. The same frozen facade owns manifest parsing, capability authorization, specialized read proof minting, repository selection, cancellation, result validation, prompt-safety marking, and the 60,000-character reduction boundary. Callers supply only a nominal `ActorContext`, canonical input, and optional `AbortSignal`; they cannot supply tenant ids, permission scopes, policies, repositories, database clients, clocks, projection kinds, `as_of` values, or authorization proofs.

`list_scheduled_jobs` is project-task-only in v1. It uses a half-open UTC window of at most 90 days, default limit 25/maximum 50, source-stable signed keyset pagination, company-local schedule authority, and a separate display-timezone projection. Task lifecycle, derived timing, and current confirmation are orthogonal. Output includes only bounded customer-shareable crew identity; employee email, phone, HR role, profile, and other private roster data never cross the domain boundary.

`list_job_readiness_issues` evaluates `SITE_PHOTOS_MISSING`, `CUSTOMER_RECORD_UNRESOLVED`, `SCHEDULE_UNCONFIRMED`, `CREW_UNASSIGNED`, and `ADDRESS_INCOMPLETE`. A request may scan at most five physical pages of 50 authorized candidates under one immutable source fence. The SQL repository returns safe raw facts and one job projection proof; `readiness-rules.ts` alone derives fixed facts, severity, rule revision, and `issue | clear | not_evaluated`. Missing authorization or truncated source evidence is `not_evaluated`, never a negative fact. Customer and photo scopes are conditionally required only when their rule is selected.

`get_job_communication_context` is a current-only read for one opportunity or project. `general` returns bounded job/contact facts without schedule or photo claims. `schedule_notice` adds the current bounded task schedule and customer-shareable assignment names. `photo_request` adds that schedule plus the existing TypeScript-owned `SITE_PHOTOS_MISSING` evaluation; SQL returns only the same bounded raw photo-source shape used by readiness. An unavailable or bounded schedule/photo source is explicit `not_evaluated`, not a false zero/absence claim.

`resolve_job_participants` is also current-only. Its purpose defaults to `general`; `schedule` and `assignment` conditionally authorize active task-assignment users, while `general` and `communication` cannot include assignment-only nodes. Current primary clients and sub-clients may use concrete IDs. Conversation-derived ambiguous/unresolved participants use `unknown:sha256:<digest>`; redacted participants use `redacted:sha256:<digest>`. The schema reserves a concrete related-contact type, but v1 never confirms one from conversation evidence alone. A resolved-but-nonconcrete source remains unresolved and emits `RELATED_CONTACT_UNCONFIRMED`.

Contactability is email-only in v1. The primary client is eligible only when its current identity is confirmed and one normalized address is uniquely owned and not globally suppressed. A contactable sub-client is `selection_required`; the caller cannot silently add it as another recipient. Suppression, duplicate ownership, absence, ambiguity, unavailable/query-bounded/invalid data, unresolved identity, and redaction all withhold the address and produce a matching non-recipient state. Preferred channel is always null. No phone/SMS consent, contact preference, generic opt-out, private employee contact, or employee-role claim is asserted. OPS delivery actors and Phase C remain assistant-side; OPS may expose only a safe display name, and neither exposes contact fields.

Each participant references exactly one authoritative projection evidence atom. Collection/context proofs bind actor, company, job, purpose, permission snapshot, manifest/source/contactability revisions, ordered participant proof sources, lower-bound truth, and fixed gaps. Business strings are marked untrusted and accompanied by a fixed prompt-safety directive. The service retains complete claims with proof/evidence under 60,000 characters; communication context retains the maximal ordered schedule prefix before the maximal participant prefix.

The capability manifest revision advances locally to `2026-08-13.capability-manifest.v5`. Exactly `get_job_conversation_context`, `list_scheduled_jobs`, `list_job_readiness_issues`, `get_job_communication_context`, and `resolve_job_participants` are internally implemented; all external exposure remains disabled. V5 compatibility wrappers preserve the earlier v4 conversation/evidence/schedule/readiness implementations privately and do not permit callers to select an old revision. There is no MCP handler, REST adapter, remote catalogue entry, external advertisement, deployment, or customer-live proof for these reads.

Schedule confirmation routes and workers are locally redirected through exact-version database receipts and durable purpose events because readiness cannot truthfully infer current confirmation from a timestamp alone. Retryable pre-provider email work returns to the pending queue; provider-owned states remain with durable transport reconciliation. This supporting write-path hardening is part of the same local gate and is not live.

Implemented locally in OPS Web commit `5bba3c5e`. The final focused matrix passed 47 files / 784 tests, the company-data manifest passed 71/71, TypeScript and formatting/diff hygiene passed, and the independent final security review found no P0/P1 issue. The full repository run passed 11,495 tests and retained 82 known email/provider fixture failures that reproduce unchanged on baseline `73712b4f`; Task 11 adds no deterministic full-suite failure.

Task 12 is implemented locally in OPS Web commit `dc91a349`. Its exact focused matrix passed 12 files / 169 tests; Node 22 TypeScript `--noEmit` and diff hygiene passed; an independent frozen cross-boundary review found no P0/P1 issue. This is source/test evidence only and does not prove that the migration compiles or behaves correctly in PostgreSQL.

**Release prerequisite:** `20260813120000_agent_job_communication_participants.sql` depends on the Task 9/Task 11 schema and both Task 11 migrations. The migrations deliberately fail closed until production PostgreSQL and the pinned Node runtime agree with current timezone rules, including permanent UTC-7 for Vancouver after the 2026 final clock change. After that platform gate, an isolated Supabase branch must prove ordered apply/rollback, function compilation, grants, same-statement authority, tenant/collision isolation, suppression/source freshness, bounds, projection hashes, and compatibility wrappers before any adapter or rollout flag is enabled. Platform update cost and downtime have not been established. No Supabase branch, migration apply, push, deploy, or production mutation occurred during this implementation checkpoint, and the unapplied Task 12 migration is not mirrored into the Bible archive.

## Internal Agent Job Catalog Reads (local, externally dark 2026-08-14)

Task 13 extends the same `OpsAgentDomainService` with four transport-neutral methods:

| Domain method | Capability | Contract |
|---|---|---|
| `listCustomerJobs(actor, input, options?)` | `list_customer_jobs` | Lists bounded opportunity/project jobs for one authorized current client or sub-client with signed source-stable pagination. |
| `getJobSummary(actor, input, options?)` | `get_job_summary` | Returns one current job plus the complete requested set of independently authorized `identity`, `schedule`, `readiness`, `participants`, `financials`, `activity`, and `conversation` sections. |
| `searchJobHistory(actor, input, options?)` | `search_job_history` | Searches an explicit or default one-year half-open window across selected authorized source kinds with a signed history cursor. |
| `getCorrespondenceEvidence(actor, input, options?)` | `get_correspondence_evidence` | Resolves 1–20 exact evidence selectors for one visible job in `excerpt` or all-or-error `full_text` mode. |

All four methods accept only a server-minted nominal `ActorContext`, canonical public input, and optional `AbortSignal`. The factory captures a complete nominal repository bundle once. The authorizer proves every manifest variant selected by the input and mints one merged nominal proof; the repository receives that proof and calls one fixed RPC with its exact bound scope fields. No transport may inject a database client, repository, clock, company id, scope, proof, source fence, policy JSON, or legacy manifest revision.

`list_customer_jobs` filters opportunity/project sources before reciprocal conversion collapse. Each returned row states whether the counterpart formed a visible canonical pair, does not exist, or was not returned; hidden counterpart IDs never cross the boundary. Project date fields are validated civil `YYYY-MM-DD` values, not fabricated UTC-midnight instants. The signed cursor binds actor, company, customer, permission and manifest revisions, canonical filters, source fence, last ordering key, and expiry.

`get_job_summary` authorizes the full requested section set before reading. Schedule output uses the Task 11 occurrence contract; readiness is derived by the Task 11 TypeScript rule module; participants use the Task 12 safe current identity mapping without contact channels. Financials, typed task/status activity, and actor-visible conversation facts have independent conditional permissions and source caps. A selected source that cannot be evaluated remains represented by a fixed proof-bound gap. Reducers preserve all selected sections and trim only permitted ordered child prefixes.

`search_job_history` returns current-redaction-aware immutable delivered correspondence, bounded structured memory fragments, lifecycle/status events, typed task events, and permitted estimate/project-financial facts. Every result requires a primary query/phrase/job-identity relevance reason; recency is supplemental. Exact source-data/query-bound gaps survive the 60,000-character reducer. The history cursor binds the effective window, selected sources, authorization variants, source/history fences, last rank/time/opaque id, and expiry.

`get_correspondence_evidence` accepts only selectors already bound to the requested job and current mailbox/redaction authority. It returns normalized plain text, bounded safe attachment references, immutable source identity, content hash, and trust metadata—never MIME, HTML, scripts, tracking content, or hidden markup. Excerpt mode returns fixed bounded excerpts. Full-text mode is atomic: if the requested page would exceed 60,000 characters, the domain result is non-retryable `INVALID_ARGUMENT` with `PROMPT_BUDGET_EXCEEDED`, message `Requested evidence is too large.`, and guidance to request fewer evidence items or use excerpt mode. Near-miss database errors remain `TEMPORARILY_UNAVAILABLE`; only the exact database error `code` plus `message` sentinel maps to the invalid-argument result.

The local capability manifest is `2026-08-14.capability-manifest.v6`. All nine implemented reads are `implementation=available` for internal composition only and `externalExposure=disabled`. The v6 wrappers reprove exact public capability/revision/manifest identity before invoking frozen private earlier implementations. A Phase C internal adapter and metrics-only shadow consumer now exist locally, but they have not been pushed, deployed, configured, enabled, or observed in production. No REST route, MCP handler/catalogue, OAuth surface, remote host integration, or customer-live control-plane caller exists.

Task 13 is implemented locally in OPS Web commit `d4118344`. The final source gate passed 57 files / 1,141 tests, Node 22 TypeScript `--noEmit`, Prettier, and diff hygiene; an independent frozen cross-boundary review found no remaining P0/P1 issue. A PostgreSQL 18 ECPG grammar audit parsed all 132 statements in the frozen migration and found no declared RPC-arity, generated-column, or custom-function-arity mismatch. This remains source/static evidence only.

**Release prerequisite:** `20260814120000_agent_job_catalog_reads.sql` depends on the unapplied Task 9, Task 11, and Task 12 schema/functions and inherits the Task 11 timezone gate for schedule-bearing summaries. After PostgreSQL and the pinned Node runtime agree with the current BC permanent-UTC-7 rules, an isolated Supabase branch must prove ordered apply/rollback, catalog compilation, grants, RLS and same-statement authorization, tenant/customer/job/mailbox isolation, source/history revision triggers, FTS/index/query-plan behavior, bounds/error sentinels, projection hashes, signed cursors, compatibility wrappers, and runtime timezone vectors. Platform update, branch, and downtime costs have not been established. No Supabase branch, migration apply, push, deploy, or production mutation occurred, and the unapplied Task 13 migration is not mirrored into the Bible archive.

## Phase C Internal Context Adapter and Reply Shadow (local, gated, not deployed 2026-08-16)

Commit `77c79996` adds the current v6 Phase C internal consumer without granting ambient service authority. The runtime resolves the routed actor through the current Phase C source repository, mints the nominal internal principal/actor context, and invokes the same nine-repository `OpsAgentDomainService` used by the other internal reads. The database wrapper `read_agent_phase_c_job_conversation_context_as_system` re-proves the exact actor, opportunity assignment version, mailbox/thread, immutable inbound source turn, correspondence event, provider-delivery source hash, and conversation anchor in the same statement as the generic v6 context read. The adapter accepts the result only when the requested opportunity, source conversation, and one `freshness_and_gaps` section agree that the exact source turn is summarized. Pending memory is `STALE_CONTEXT`; this integration deliberately does not invoke the generic memory catch-up path because that would introduce a second unfenced mutation/read.

Commit `3da161d3` adds the opt-in company flag `agent_memory_reply_shadow`. The live whole-history context remains the only input to the customer-facing draft. When enabled, a detached observer loads the bounded shared context and returns aggregate comparison metrics only. It cannot create a model, generate or persist a second draft, write memory, send mail, mutate a provider mailbox, or feed the bounded context back into the current reply. A single ten-second deadline begins before feature lookup and covers the entire observation; feature and RPC work are outer-raced so a non-cooperative promise cannot keep the detached task alive indefinitely. Any missing actor proof, configuration, authority, source proof, stale context, timeout, or read error returns no observation and leaves the live draft path unchanged.

The bridge requires server-only `OPS_AGENT_OPERATIONAL_READ_CURSOR_KEY`, exactly 32 bytes encoded as 64 lowercase hexadecimal characters, to construct the nominal operational-read cursor codec. No key was provisioned in this checkpoint. Live prompt assembly and shadow measurement share `src/lib/prompt-safety/untrusted-json.ts`, which serializes untrusted JSON and escapes only the structural `<`, `>`, and `&` delimiters; this keeps measured and actual prompt character counts identical. Offline schedule-quality fixtures accept a separate structured `verifiedSchedule` source rather than treating conversation or memory text as schedule authority. The runner always emits literal `releaseGatePassed: false`, even when its mechanics-only quality checks pass.

Integrated verification passed 61 agent-control-plane files / 1,306 tests, 29 Phase C files / 271 tests, four agent migration-contract files / 69 tests, Node 22 TypeScript, diff hygiene, and independent P0/P1 review. A repository-wide rerun passed 12,230 tests and reproduced the same 82 pre-existing email/provider fixture failures already isolated on baseline `73712b4f`: four `lead-lifecycle-send-route`, seven `pipeline-draft-mailbox`, one `email-opportunity-title-live-pattern`, and 70 `email-opportunity-title-sync-engine` failures. No deterministic failure was attributed to the integrated control-plane/Phase C work.

**Release prerequisite:** migration `20260814190000_agent_phase_c_source_turn_read.sql` must first compile and apply in ledger order after its unapplied Task 9–13 prerequisites, then pass isolated apply/rollback, function/grant readback, real catalog/RLS/authority, tenant/job/mailbox/source isolation, query-bound, concurrency, and runtime tests. Production must provision and read back the dedicated cursor key without exposing it, keep `agent_memory_reply_shadow` disabled by default, and collect a bounded production shadow sample before any release decision. Task 16 still requires explicit measured quality/safety thresholds, rollback proof, and a separately authorized context switch. No migration apply, environment change, flag change, push, deploy, shadow observation, or customer-facing switch occurred in this checkpoint.

## Agent Control Plane Cutover — Applied and Deployed (2026-08-18)

The release prerequisites above were satisfied and executed on 2026-08-18 (UTC). Current production state, superseding the "not applied / not deployed" statements in the two preceding sections:

- **Database:** all twelve gated wave migrations applied to prod in one atomic transaction (upfront `ACCESS EXCLUSIVE` locks on the 21 pre-existing target tables, single ledger-keyed commit) on top of reshape `20260818011925`. Object verification ran against live catalogs, both `public` and `private`: the full 104-function / 14-table expected manifest returned zero missing objects; `project_tasks.confirmed_schedule_version`, `private.phase_c_auto_send_generation_reservations`, and the three schedule RPCs (`confirm_project_task_schedule_as_system`, `confirm_automatic_project_task_schedule_as_system`, `prepare_schedule_dispatch_as_system`) all exist; the July trigger `email_send_intents_phase_c_queue_fence` is untouched and enabled. All twelve ledger `statements[1]` md5s equal their `migrations/` files.
- **Code:** ops-web `main` `9103efcf` pushed to origin (history: gated `44f6401c` + origin test-fix merge `5a36192e` + reserved-word alias fix `c2e6a49c` + tzdata date-gate `3b231f91` + SQL parse repairs `9103efcf`), auto-deployed to Vercel production. Gate on the pushed tree: `tsc --noEmit` clean; `email-opportunity-title-live-pattern`, `email-opportunity-title-sync-engine`, and `email-projection-stuck-check-cron` suites 107/107 (the stuck-check timing assertion flaked once under concurrent load — 59 ms drift against a 50 ms budget — and passed 12/12 in isolation).
- **Parse repairs shipped in `9103efcf`:** fifteen `coalesce(...)[1:100]` array slices lacked the parentheses PostgreSQL requires around a function call before subscripting (`20260812120000`, `20260813120000`, `20260814120000`), and `private.read_agent_job_participant_snapshot`'s `context_raw` projection opened a `case` on `p_projection_kind` that was never closed. Found by the failed first prod apply plus a full local PostgreSQL 17.11 parse sweep of all twelve files (transaction wrappers stripped so every statement validates independently; composite-type stubs so every plpgsql body compiles). The applied ledger rows contain the repaired text.
- **Timezone date-gate:** `private.agent_assert_operational_timezone_rules()` WARNs instead of failing until 2026-09-15 (platform tzdb predates 2026c; Supabase ticket open; restore duty tracked as `bug_reports` `212987a4`). The apply emitted the expected WARNING and committed.
- **Outbound posture at the control-plane cutover checkpoint:** auto-send remained OFF (`INBOX_AUTO_SEND_ENABLED` unset — the cron no-ops); `public.claim_email_send_provider_delivery(uuid)` EXECUTE was re-granted to `service_role` after deploy verification (out-of-ledger; `migrations/20260818052155_restore_claim_email_send_provider_delivery_grant.sql`), closing the last deliberately-held outbound revoke. MCP was still unmounted at this checkpoint; the production mount described immediately below superseded that state later the same day.
- **Deferred verification pass (Maverick Projects, 2026-08-18):** the pass immediately caught one wave defect — the stale July version-gate twin on `task_schedule_automation_outbox` aborting confirm/unconfirm on `schedule_version = 0` tasks (`23514`) — fixed by ledger `20260818052612` before the first new-code `auto-confirm-schedules` cron firing (schedule `39 * * * *`; zero customer impact; see `03_DATA_ARCHITECTURE.md`). After the fix: full schedule-confirm round-trip green through the new RPC path on a Maverick task under service-role claims (`confirm_project_task_schedule_as_system` → `newly_confirmed: true`, row proof bound, one `schedule_confirmation_dispatch` outbox row; `unconfirm_project_task_schedule_as_system` → `newly_unconfirmed: true`, proof cleared). Phase-10 canary validation layers re-proven live: reserve without service claims → `42501 access_denied`; reserve with malformed hashes → `22023 PHASE_C_AUTO_SEND_SOURCE_FENCE_INVALID`; resolve of unknown reservation → `23505 PHASE_C_AUTO_SEND_IDEMPOTENCY_CONFLICT`. No `email_connections` rows were created and nothing was sent (Maverick has zero connections). All test rows removed: both pending dispatch outbox rows, the temporary `phase_c` feature override, zero reservation residue; the test task restored to its exact pre-test state.

## OPS Remote MCP Server — P1 Mount, Claude First (production-live 2026-08-18; reverified 2026-08-20)

Supersedes the "MCP transport remains unmounted and dark" statements above. The mount is **deployed and operational in production**. The MCP merge `a860f5ee` is in the ancestry of the current READY Vercel production deployment, which serves `app.opsapp.co`. Claude completed dynamic registration and OAuth consent against the live endpoint. Scope: `specs/2026-08-18-mcp-mount-claude-first-scope.md`; plan: `specs/plans/2026-08-18-mcp-mount-claude-first-P1-plan.md`.

### Topology

| Role | Value |
|------|-------|
| Protected resource | `https://app.opsapp.co/api/mcp` |
| Authorization-server issuer | `https://app.opsapp.co` |
| Transport | Streamable HTTP, stateless, via `@modelcontextprotocol/server@2.0.0` `createMcpHandler` |
| Protocol eras | 2026-07-28 native + 2025-era legacy (`2024-10-07`…`2025-11-25`) from one factory |

The dedicated `mcp.opsapp.co` hostname from the foundation design is deliberately deferred: a new audience forces re-consent, which is free while exactly one connection exists. No DNS or Vercel domain change in P1.

**Claude-side facts verified live on 2026-08-18** (Anthropic docs, not cached knowledge): Claude clients still speak the 2025-era handshake (they send `initialize`); 2026-07-28 is announced but not confirmed shipped in any Claude surface. Claude sends RFC 8707 `resource` on authorize and token requests and requires PKCE S256 on every request. Connector callback: `https://claude.ai/api/mcp/auth_callback`. Discovery documents are cached ~5 minutes globally. Tool results cap at ~150,000 characters (our contract's 60,000-char ceiling sits inside it); tool calls time out at 300s. On Team/Enterprise plans only an Owner may add a connector, and there is no staging surface — connector testing happens against production claude.ai.

### Routes

| Route | Method | Purpose |
|-------|--------|---------|
| `/api/mcp` | POST | The MCP endpoint. GET/DELETE pass the same auth gate, then answer 405. |
| `/.well-known/oauth-protected-resource/api/mcp` | GET | RFC 9728 metadata (Claude's first probe location) |
| `/.well-known/oauth-protected-resource` | GET | RFC 9728 root fallback, identical document |
| `/.well-known/oauth-authorization-server` | GET | RFC 8414 metadata. CIMD deliberately **not** advertised. |
| `/api/mcp/oauth/register` | POST | RFC 7591 dynamic registration, 10/hour/IP |
| `/api/mcp/oauth/token` | POST | `authorization_code` + `refresh_token`, form-encoded, 60/min/IP |
| `/api/mcp/oauth/revoke` | POST | RFC 7009, always 200 |
| `/oauth/authorize` | GET | Firebase-authenticated consent panel |
| `/api/mcp/oauth/authorize/context` | POST | Consent-panel data (client, company, scope labels) |
| `/api/mcp/oauth/authorize/decision` | POST | Mints the authorization code after approval |
| `/api/mcp/oauth/grants` | GET/DELETE | Operator's own grants; powers Settings → Integrations → CONNECTED AGENTS |

### Token model

Opaque 256-bit credentials, stored only as SHA-256 digests, never signed. The authorization server and resource server are the same deployment sharing one database, so every claim resolves from the grant row on presentation — which is exactly what the foundation design requires ("the access token does not contain a trusted permission snapshot; current OPS authorization is reloaded on every call"). A signature would add key management without adding security, and revocation must bind on the next call regardless. Access tokens live 600s; refresh tokens rotate on every use with family reuse detection. Authorization codes are single-use, PKCE-S256-bound, redirect-bound, resource-bound, 300s.

### Authority

`/api/mcp` resolves the bearer to its grant, mints a `ValidatedMcpPrincipal` through the existing branded boundary (`createMcpPrincipalFromValidatedGrant`), and re-resolves actor authority per call via `resolve_agent_actor_authority_as_system`. **Company scope derives from the grant, never from tool arguments.** A removed role, lost membership, or revoked grant takes effect on the next call regardless of token expiry. The MCP layer invents no authority — it is the third adapter onto the same `OpsAgentDomainService` the Phase C internal adapter uses.

### Capability surface

The transport registers exactly the manifest entries with `implementation = available` **and** `externalExposure = enabled`. Exactly eleven manifest-v7 reads are enabled; the original nine retain their v6/v7 database bridge, while every write family and the two dark site-visit contracts remain disabled. The manifest constant is the rollout control — nothing in the transport can widen past it. Results and error envelopes both pass through `serializeUntrustedPromptData` before entering any model context.

#### Customer and job discovery expansion (production-live 2026-08-22 UTC)

Capability-manifest `2026-08-20.capability-manifest.v7` exposes `search_customers` and `search_jobs` alongside the original nine reads. `search_customers` resolves visible clients/sub-clients by canonical name or an exact permission-gated email/NANP phone selector; contact selectors never appear in results, evidence, cursors, warnings, or errors. `search_jobs` resolves visible opportunities/projects by safe title, address, lifecycle, status, and created/updated windows, preserving current reciprocal conversion identity and non-leaking linked-side states. Existing UUID-bound reads remain the only detail surface.

Production ledger `20260822015049_agent_discovery_reads_20260820220000` installed the two service-role-only RPCs, 40 valid/ready indexes, and the v6/v7 same-statement reproof bridge. Indexed-writer repair ledger `20260822015939_agent_discovery_index_writer_acl_20260822015828` grants the existing table-writer roles only the exact eight scalar helpers PostgreSQL must execute to maintain those indexes; `PUBLIC` and all non-index discovery helpers remain denied. OPS-Web release commit `5eb4b561c14cf8dace2b906d50ebcd34a0ba13db` was served by READY deployment `dpl_6ZMAhdXuweX9jSuVG8T58Z5gzWko` at `app.opsapp.co`.

Live authenticated acceptance listed exactly eleven tools and exercised all eleven through the production endpoint. Nine calls returned successful results; conversation context and correspondence evidence returned their expected privacy-safe `NOT_FOUND` outcomes because the selected canary job had no matching records. The disposable grant was revoked, its next bearer request returned `401`, and all temporary OAuth client, code, grant, and token rows were deleted with zero-row readback. The immutable request audit remains. Claude's permanent client/grant was not changed. Every write family and both site-visit capabilities remain dark. A future v6-removal migration remains separate until old instances, jobs, cursors, and prepared calls drain.

### Safety rails

- **Rate limits** (foundation § 13.3): `lightweight_read` 120/min/grant + 600/min/company; `evidence_search` 30/min/grant + 120/min/company; plus a coarse 300/min/grant transport ceiling. Backed by the shared limiter — Vercel KV is **not** provisioned, so enforcement degrades to per-instance in-memory (documented, accepted at current scale).
- **Audit**: every tool call including denials appends to `private.mcp_request_audit` — actor, company, grant, client, tool, protocol era, outcome, error code, SHA-256 input digest, result bytes, latency. Never raw input, never tokens, never message bodies.
- **Dark to unauthenticated traffic**: the bearer gate answers before any JSON-RPC parsing (Claude's OAuth is triggered only by a transport-level 401 — a 200 with `isError` never triggers it). Missing bearer → 401 + `WWW-Authenticate: Bearer resource_metadata="…", scope="…"`; invalid bearer adds `error="invalid_token"`. Response bytes on these paths are asserted free of every capability name.
- **Auto-send posture untouched**: nothing in the mount reads or writes `INBOX_AUTO_SEND_ENABLED` or any outbound surface.

### Verification (2026-08-18, Maverick Projects `ddee107c-33cd-483e-8278-0f8d8a180181`)

37/37 live end-to-end checks against a local server bound to production Supabase: dynamic registration; consent context resolving "MAVERICK PROJECTS LTD"; approve and deny; token exchange; authorization-code replay revoking the grant it minted; refresh rotation; refresh reuse killing the token family; legacy-era `initialize`; `tools/list` returning exactly the nine; **all nine reads exercised against real Maverick data**; **seven tenant-isolation probes with another company's identifiers, every one returning a privacy-safe `NOT_FOUND` sentinel and no data**; unauthenticated and malformed-bearer rejection with zero capability disclosure; settings revoke followed by a 401 on the next call. All OAuth test rows were deleted afterward — zero residue. Suites: 71 files / 1787 tests green; `tsc --noEmit` exit 0; eslint clean.

### Production deployment and host proof (reverified 2026-08-20)

- **Deployment:** Vercel production deployment `dpl_6NLRbVXSjKsAHPEhcjXAbtnLnJGx` is READY on ops-web commit `f6f7f5c8440e5c20caad9539d522cab9ccb03caf`, with `app.opsapp.co` attached and no alias error. The transport, external-exposure, and OAuth commits are ancestors of that deployed revision.
- **Live route:** `/.well-known/oauth-authorization-server` and `/.well-known/oauth-protected-resource/api/mcp` return 200 with issuer/resource `https://app.opsapp.co` / `https://app.opsapp.co/api/mcp`. An unauthenticated request to `/api/mcp` returns the required 401 bearer challenge and protected-resource metadata pointer.
- **Database:** production contains ledger `20260818155813_mcp_oauth_authorization_server`, all five private MCP tables, all eleven service-role RPCs, and the nine fixed read RPCs.
- **Claude connection:** one dynamically registered client named `Claude` has one unrevoked full-read grant. The grant and its rotating refresh credential were used on 2026-08-20; the current refresh family remains valid through 2026-09-19.
- **Real tool use:** the immutable audit contains 16 requests: 11 successful tool calls, three privacy-safe domain errors, and two rejected invalid-token probes. Successful modern-protocol calls cover schedules, readiness, customer jobs, participants, job history, communication context, conversation context, and job summaries. The evidence read was also exercised and correctly returned `NOT_FOUND` for the supplied absent selector.
- **Surface:** exactly nine read capabilities are externally enabled. Every write family and both site-visit capabilities remain disabled.

### Four production defects this work found and fixed

The mount's E2E was the **first production execution of the Task 13 job-catalog read RPCs**. PostgreSQL validates plpgsql statement semantics lazily, so the wave's parse verification could not have caught these; each was invisible until a real call ran. Repaired by ledger `20260818174706` and `20260818175549` (both mirrored byte-exact in `migrations/`):

1. **uuid/legacy-TEXT mixing** between `projects.opportunity_ref` (uuid) and `projects.opportunity_id` (TEXT) in `read_agent_customer_jobs_as_system`, `read_agent_job_history_as_system`, `read_agent_correspondence_evidence_page_as_system`, and `read_agent_job_summary_as_system` — `42804`/`42883` at runtime. Repaired with `private.agent_uuid_from_legacy_text(text)`, a shape-guarded immutable cast: a non-uuid legacy value reads as "no linked opportunity" in fallbacks and as a mirror conflict when a real `opportunity_ref` disagrees.
2. **`estimates.project_id` is TEXT** against a uuid job id in summary and history (`42883`), repaired by casting the uuid side — the pattern the wave already used correctly for `project_photos`.
3. **`read_agent_job_summary_as_system` rejected every request** that omitted `readiness_rule_codes` or `financial_components` (`22023`): its scope-coupling block evaluated `NULL && array[...]` and `'X' = any(NULL)` to NULL, and `NULL IS DISTINCT FROM false` is true. An identity-only summary could never succeed for any caller through any adapter.
4. **`read_agent_customer_jobs_as_system` left a UNION arm expression unaliased** (`42703`), so `source_data_invalid` materialized as `?column?` and every downstream reference failed.

Both repairs are guarded transformations of the live definitions: each site must occur an asserted number of times or the migration aborts without changing anything. Round 1 was proven byte-equivalent to a reviewed whole-body corrective on a local PostgreSQL 17 cluster before being applied.

Two TypeScript contracts were also wrong against production reality (commit `eca40f47`): the job-catalog lifecycle refinement demanded stage `discarded` for an archived opportunity, but `opportunities.archived_at` is a dimension independent of stage — an archived `new_lead` failed the entire `list_customer_jobs` read; and the job-history repository's not-found matcher expected a message the shipped RPC never raises, downgrading privacy-safe `NOT_FOUND` answers to `TEMPORARILY_UNAVAILABLE`.

### Evidence redaction defect found after the mount went live (fixed 2026-08-18)

`get_job_conversation_context` and `get_correspondence_evidence` returned correct structure, provenance and participants but no readable subject or body for HTML email. Bug `6504b27b-ded1-4560-95c0-1934eb367164`.

The cause was at **ingest, not read**. The visibility guard in `src/lib/agent-control-plane/evidence/normalize-correspondence.ts` rejected any element carrying a `dir` attribute, without inspecting the direction value. The intent was sound — `dir="rtl"` reorders neutral characters, so a reviewer can read a different string than the characters actually say, which is a real spoofing and prompt-injection vector — but `dir="auto"` is the Apple Mail default on every message body and `dir="ltr"` is common from other clients. `normalizeCorrespondence` threw, `provider-delivery-source-service.ts` caught it, and `private.agent_provider_delivery_sources` stored `[SUBJECT OMITTED: UNSAFE SOURCE]` / `[CONTENT OMITTED: UNSAFE SOURCE]` with `normalization_status = 'rejected'`. The read path faithfully returned those placeholders.

The guard now resolves direction instead of detecting its presence: `ltr` is accepted, `rtl` is rejected, and `auto` resolves per the HTML directionality algorithm — the first strong directional character in the element's own text, skipping descendants that carry their own `dir` and subtrees that render no text — and is rejected only when it actually resolves RTL. An unrecognised `dir` value stays rejected, because mail clients disagree on that fallback. `bdi`, `bdo`, `unicode-bidi`, the `direction` CSS property and every other entry in the guard are unchanged.

The same blunt-value comparison existed a second time in `renderedSeparator`, which walked ancestors reading raw `dir` strings and tested `=== "rtl"`. That was unreachable while the guard rejected every `dir`, but narrowing the guard would have opened it: a `dir="auto"` table or flex container resolving RTL would have passed. Both sites now share one memoized resolver.

Second defect, fixed with it: the catch site in `provider-delivery-source-service.ts` was bare, so in production every rejection looked identical and its cause was unrecoverable. It now emits one structured `console.warn` with company, connection, provider message id, media type, content byte count, and the thrown reason — identifiers and reason only, never message content.

**The `dir` guard was not the only cause of HTML rejection.** Measured against the six `text/html` sources in production on 2026-08-18: one (1,303 bytes) was blocked by `dir` alone and recovers; three carry Outlook conditional markup (`<!--[if …]>`); and two more carry CSS declarations outside the supported set (`text-transform`, `letter-spacing`, `text-decoration`). Those are independent, intentional guards with their own test coverage and were deliberately left alone. All three `text/plain` sources normalized correctly throughout. Any backfill estimate must start from this breakdown, not from the raw rejected count.

Coverage: `src/lib/agent-control-plane/evidence/__tests__/normalize-correspondence.test.ts` gains a direction block — `ltr` accepted; `auto` with Latin text accepted; `auto` resolving RTL from Arabic and from Hebrew rejected; `auto` resolving RTL past a directed descendant rejected; `rtl` in any letter case rejected; inherited direction in both directions; a weak Arabic-Indic digit correctly not treated as strong; `bdi`/`bdo` still rejected under an accepted direction; and a realistic Apple Mail body read end to end. 231 evidence tests, 1,756 agent-control-plane tests, `tsc --noEmit` exit 0, eslint clean.

Already-ingested rows keep their stored placeholders. Recovering them means re-normalizing from the retained `content_value` bytes — a separate backfill decision, Jackson's call, because it reprocesses real customer email.

### P1 release gates — complete (verified 2026-08-20)

1. `OPS_AGENT_OPERATIONAL_READ_CURSOR_KEY` is provisioned in Vercel production. Its value was not read or exposed; successful authenticated paged reads prove the runtime accepted it.
2. The MCP mount is merged to `main` and deployed at `https://app.opsapp.co/api/mcp`.
3. Claude is dynamically registered and connected through an active OPS OAuth grant.

No further release gate remains for the Claude-first read-only P1. Expanding to another host, enabling site-visit tools, adding any write capability, or changing the Phase C customer-facing context path is a separate initiative with its own authorization and proof gates.

**End of Document**

This completes the comprehensive API and Integration documentation for the OPS Software Bible. Any developer or AI agent should now have complete context to implement the entire Supabase-backed sync system, repository layer, realtime subscriptions, image handling, push notifications, email pipeline integration, and error management with full fidelity to the current implementation.
