# 21 - Analytics System

**Last Updated:** March 30, 2026
**OPS Version:** iOS v1.7+, Android Planning Phase, Web App Active
**Purpose:** Complete reference for the unified cross-platform analytics system. Covers database schema, event taxonomy, platform-specific implementation guides, offline queue patterns, identity resolution, and admin panel dashboard specifications.

---

## Table of Contents

1. [Architecture Overview](#1-architecture-overview)
2. [Database Schema](#2-database-schema)
3. [Event Taxonomy](#3-event-taxonomy)
4. [Identity Resolution](#4-identity-resolution)
5. [iOS Implementation](#5-ios-implementation)
6. [Android Implementation Guide](#6-android-implementation-guide)
7. [Web Implementation Guide](#7-web-implementation-guide)
8. [Offline Event Queue Specification](#8-offline-event-queue-specification)
9. [Admin Panel Dashboard Specification](#9-admin-panel-dashboard-specification)
10. [Firebase Analytics (Google Ads Conversions)](#10-firebase-analytics-google-ads-conversions)
11. [Existing Analytics Systems (Legacy)](#11-existing-analytics-systems-legacy)
12. [Data Retention & Performance](#12-data-retention--performance)
13. [Adding New Events](#13-adding-new-events)
14. [Privacy & Compliance](#14-privacy--compliance)

---

## 1. Architecture Overview

### Design Principles

- **Single table, all platforms.** Every platform (iOS, Android, Web) writes to the same `analytics_events` Supabase table with a `platform` discriminator.
- **Admin panel is the single source of truth for product analytics.** No third-party product analytics tools (no Mixpanel, Amplitude, PostHog). Feature adoption, funnels, retention, and engagement dashboards live in the OPS admin panel at `/admin`, reading from the Supabase `analytics_events` table.
- **No new dependencies.** Uses existing Supabase client libraries on each platform.
- **Offline-first.** Mobile platforms queue events locally and flush when connectivity returns.
- **Firebase Analytics stays for Google Ads only.** The 5 conversion events that feed Google Ads attribution continue to fire via Firebase Analytics. Everything else goes to Supabase.
- **GA4 handles visit + traffic data on web surfaces only (added 2026-05-25).** ops-site (marketing), try-ops (acquisition landing), and OPS-Web (logged-in product) fire the GA4 gtag.js snippet client-side. Captures sessions, page_view, device, geography, referrer — the visit-grade surface that product analytics is not designed to expose. Does NOT receive product-analytics events; those still go to Supabase. iOS and Android do NOT use GA4. Env var: `NEXT_PUBLIC_GA_MEASUREMENT_ID`. See § 7 for the OPS-Web install and production-host boundary.

### Data Flow

```
┌─────────────────────────────────────────────────────────┐
│                    USER PLATFORMS                        │
│                                                         │
│  ┌─────────┐    ┌───────────┐    ┌──────────────────┐  │
│  │   iOS   │    │  Android  │    │    Web (Next.js)  │  │
│  │         │    │           │    │                    │  │
│  │ Analytics│    │ Analytics │    │ Analytics          │  │
│  │ Service  │    │ Service   │    │ Service            │  │
│  └────┬────┘    └─────┬─────┘    └────────┬───────────┘  │
│       │               │                   │              │
│  ┌────▼────┐    ┌─────▼─────┐             │              │
│  │ Offline │    │  Offline  │             │              │
│  │  Queue  │    │   Queue   │             │              │
│  └────┬────┘    └─────┬─────┘             │              │
│       │               │                   │              │
└───────┼───────────────┼───────────────────┼──────────────┘
        │               │                   │
        ▼               ▼                   ▼
┌─────────────────────────────────────────────────────────┐
│              SUPABASE: analytics_events                  │
└─────────────────────────┬───────────────────────────────┘
                          │
                          ▼
┌─────────────────────────────────────────────────────────┐
│                  OPS ADMIN PANEL                         │
│  /admin/app-analytics                                   │
│  ┌──────────┐  ┌──────────────┐  ┌──────────────────┐  │
│  │Engagement│  │Feature       │  │Funnels &         │  │
│  │Overview  │  │Adoption      │  │Friction          │  │
│  └──────────┘  └──────────────┘  └──────────────────┘  │
└─────────────────────────────────────────────────────────┘
```

### What Stays on Firebase Analytics

Only these 5 conversion events fire to Firebase Analytics (for Google Ads attribution):

1. `sign_up` — Primary acquisition conversion
2. `purchase` — Revenue/subscription conversion
3. `create_first_project` — High-intent engagement
4. `complete_onboarding` — Onboarding completion
5. `task_completed` — Productivity signal

These 5 events are **dual-written**: they fire to both Firebase Analytics AND Supabase `analytics_events`.

---

## 2. Database Schema

### Table: `analytics_events`

```sql
CREATE TABLE analytics_events (
  id              uuid          PRIMARY KEY DEFAULT gen_random_uuid(),
  -- Identity
  user_id         uuid          NULL,
  company_id      uuid          NULL,
  role            text          NULL,
  plan            text          NULL,
  -- Event
  event_type      text          NOT NULL,
  event_name      text          NOT NULL,
  -- Context
  platform        text          NOT NULL,
  app_version     text          NULL,
  device_type     text          NULL,
  os_version      text          NULL,
  -- Session
  session_id      uuid          NOT NULL,
  -- Data
  properties      jsonb         DEFAULT '{}',
  duration_ms     int           NULL,
  -- Timestamp
  created_at      timestamptz   NOT NULL DEFAULT now()
);
```

### Column Reference

| Column | Type | Nullable | Description | Valid Values |
|--------|------|----------|-------------|--------------|
| `id` | uuid | NO | Primary key | Auto-generated |
| `user_id` | uuid | YES | `users.id` from Supabase | Supabase user UUID (NOT Firebase UID) |
| `company_id` | uuid | YES | `companies.id` | Supabase company UUID |
| `role` | text | YES | User's role at time of event | `'Admin'`, `'Office Crew'`, `'Field Crew'` |
| `plan` | text | YES | Company's subscription plan at time of event | `'trial'`, `'starter'`, `'team'`, `'business'` |
| `event_type` | text | NO | Event category | `'screen_view'`, `'action'`, `'feature_use'`, `'lifecycle'`, `'error'` |
| `event_name` | text | NO | Specific event identifier | See Event Taxonomy (Section 3) |
| `platform` | text | NO | Source platform | `'ios'`, `'android'`, `'web'` |
| `app_version` | text | YES | App version string | e.g. `'2.4.1'`, `'1.0.0-beta'` |
| `device_type` | text | YES | Device model or browser | e.g. `'iPhone 15 Pro'`, `'Pixel 8'`, `'Chrome 124'` |
| `os_version` | text | YES | Operating system version | e.g. `'iOS 18.3'`, `'Android 15'`, `'macOS 15.3'` |
| `session_id` | uuid | NO | Unique per app launch / browser session | UUID generated on app launch or page load |
| `properties` | jsonb | NO | Event-specific key-value data | See Event Taxonomy for per-event schemas |
| `duration_ms` | int | YES | Time on screen or time to complete action | Milliseconds |
| `created_at` | timestamptz | NO | When event occurred on client | Defaults to `now()` but clients should send local timestamp |

### Indexes

```sql
CREATE INDEX idx_analytics_events_company_created ON analytics_events (company_id, created_at DESC);
CREATE INDEX idx_analytics_events_type_name_created ON analytics_events (event_type, event_name, created_at DESC);
CREATE INDEX idx_analytics_events_user_created ON analytics_events (user_id, created_at DESC);
CREATE INDEX idx_analytics_events_session ON analytics_events (session_id, created_at ASC);
CREATE INDEX idx_analytics_events_platform_created ON analytics_events (platform, created_at DESC);
```

### RLS Policy & Grants

RLS is **enabled**, with an append-only write model. OPS clients authenticate with
Firebase and reach PostgREST through the **`anon`** database role (the Firebase JWT
bridge — `auth.uid()` is NULL, `persistSession:false`), so client writes must be
permitted for `anon` — **not** `authenticated`.

| Policy | Command | Roles | Check | Purpose |
|--------|---------|-------|-------|---------|
| `analytics_events_client_insert` | INSERT | `anon`, `authenticated` | `WITH CHECK (true)` | Client-side event ingestion. Append-only. |
| `analytics_events_ops_admin_all` | ALL | `authenticated` | `private.is_ops_admin()` | Ops-admin management/read of all events. |

Table grants: `anon` has **INSERT only** (write-only — no SELECT/UPDATE/DELETE);
`authenticated` and `service_role` retain full DML. This means:
- **iOS app** writes events **directly** to the Data API as the Firebase-bridged `anon`
  role, via `INSERT ... ON CONFLICT (id) DO NOTHING` (idempotent retry on the
  client-generated UUID `id`; see `AnalyticsService.swift`).
- **Web app** buffers events and writes through a **service-role** server action /
  `/api/analytics/flush` endpoint (`getAdminSupabase()`), which bypasses RLS.
- **Reads are admin-only** — via `getAdminSupabase()` (service role) in the admin panel,
  or for ops admins through the `is_ops_admin()` policy. No client role can read events.

> **History / gotcha:** Legacy migration `048` created the table `TO authenticated`
> only, with no grant for `anon`. Because every OPS client connects as the
> Firebase-bridged `anon` role, the iOS app's direct appends were rejected with
> `42501 permission denied for table analytics_events` (~every 30s, per device) until
> migration `20260604201500_grant_anon_insert_analytics_events` added the `anon` INSERT
> grant + the `analytics_events_client_insert` policy — mirroring the
> `onboarding_analytics` / `tutorial_analytics` client-sink pattern. The web pipeline
> was never affected because it writes on the service role.

---

## 3. Event Taxonomy

### Event Types

| event_type | Purpose | Example |
|---|---|---|
| `lifecycle` | App/user lifecycle moments | `app_open`, `sign_up`, `logout` |
| `screen_view` | Screen/page impressions with dwell time | `home`, `task_form`, `pipeline` |
| `action` | Discrete user actions (CRUD, navigation) | `task_created`, `photo_captured` |
| `feature_use` | Feature engagement signals | `search_performed`, `wizard_started` |
| `error` | Errors, failures, friction moments | `sync_failed`, `api_error` |

### Lifecycle Events (`event_type: 'lifecycle'`)

| event_name | properties schema | trigger | dual-write Firebase? |
|---|---|---|---|
| `app_open` | `{launch_type: 'cold' \| 'warm'}` | App enters foreground | NO |
| `app_close` | `{session_duration_ms: int}` | App enters background | NO |
| `sign_up` | `{method: 'email' \| 'apple' \| 'google'}` | Account creation | YES |
| `login` | `{method: 'email' \| 'apple' \| 'google'}` | Login success | YES |
| `logout` | `{}` | User logs out | NO |
| `begin_trial` | `{trial_days: int}` | Trial starts | YES |
| `subscribe` | `{plan: string, price: number, currency: string, period: 'Monthly' \| 'Annual'}` | Subscription purchase | YES |
| `complete_onboarding` | `{has_company: bool}` | Onboarding finished | YES |
| `onboarding_step_viewed` | `{step: string, path: 'owner' \| 'crew' \| 'unknown'}` | Entry to each onboarding step (rebuilt iOS flow; deduped once per step entry) | NO |
| `onboarding_completed` | `{path: string, step_count: int, duration_ms: int}` | Rebuilt iOS onboarding flow completed (admit) | NO |
| `onboarding_abandoned` | `{last_step: string, path: string}` | User signed out mid-onboarding | NO |
| `onboarding_completion_queued` | `{}` | Completion ACK failed/timed out and was queued offline (`CompletionGateView`) | NO |
| `onboarding_invite_check_failed` | `{}` | Invite lookup fetch/decode failed (distinct from "zero invites"; `InviteCheckStepView`) | NO |

### Screen Views (`event_type: 'screen_view'`)

All screen view events should populate `duration_ms` with time-on-screen in milliseconds (calculated from `.onAppear` to `.onDisappear` on iOS, `onResume`/`onPause` on Android, or route change timing on Web).

| event_name | properties schema |
|---|---|
| `home` | `{}` |
| `job_board` | `{segment: 'dashboard' \| 'projects' \| 'tasks' \| 'clients'}` |
| `schedule` | `{view_mode: 'day' \| 'week' \| 'month'}` |
| `settings` | `{tab: 'profile' \| 'organization' \| 'notifications' \| 'app' \| 'team' \| 'subscription'}` |
| `project_details` | `{project_id: string}` |
| `task_details` | `{task_id: string}` |
| `client_details` | `{client_id: string}` |
| `inventory` | `{}` |
| `task_form` | `{mode: 'create' \| 'edit'}` |
| `client_form` | `{mode: 'create' \| 'edit'}` |
| `pipeline` | `{}` |
| `accounting` | `{}` |
| `photos` | `{}` |

### Actions (`event_type: 'action'`)

| event_name | properties schema |
|---|---|
| `task_created` | `{task_type: string, has_schedule: bool, team_size: int}` |
| `task_edited` | `{task_id: string}` |
| `task_deleted` | `{task_id: string}` |
| `task_status_changed` | `{old_status: string, new_status: string}` |
| `task_completed` | `{task_type: string}` |
| `client_created` | `{has_email: bool, has_phone: bool, has_address: bool, import_method: 'manual' \| 'contactImport'}` |
| `client_edited` | `{client_id: string}` |
| `client_deleted` | `{client_id: string}` |
| `project_created` | `{project_count: int}` |
| `project_status_changed` | `{old_status: string, new_status: string}` |
| `project_edited` | `{project_id: string}` |
| `project_deleted` | `{project_id: string}` |
| `photo_captured` | `{count: int, context: 'project' \| 'task' \| 'note'}` |
| `expense_logged` | `{amount: number, category: string}` |
| `expense_abandoned` | `{fields_filled: int}` |
| `note_created` | `{has_mentions: bool, has_photos: bool}` |
| `invoice_created` | `{amount: number, line_item_count: int}` |
| `estimate_created` | `{amount: number, line_item_count: int}` |
| `team_member_invited` | `{role: string, team_size: int}` |
| `team_member_removed` | `{}` |
| `team_member_role_changed` | `{old_role: string, new_role: string}` |
| `tab_selected` | `{tab_name: string, tab_index: int}` |

### Feature Use (`event_type: 'feature_use'`)

| event_name | properties schema |
|---|---|
| `search_performed` | `{section: string, results_count: int}` |
| `filter_applied` | `{section: string, filter_type: string}` |
| `calendar_view_changed` | `{view_mode: string}` |
| `calendar_day_selected` | `{events_count: int}` |
| `navigation_started` | `{project_id: string}` |
| `voice_activity_logged` | `{duration_ms: int, contacts_parsed: int}` |
| `pipeline_stage_changed` | `{opportunity_id: string, old_stage: string, new_stage: string}` |
| `wizard_started` | `{wizard_id: string}` |
| `wizard_completed` | `{wizard_id: string, steps_skipped: int}` |
| `push_notification_opened` | `{notification_type: string}` |
| `offline_sync_triggered` | `{events_queued: int}` |

### Errors (`event_type: 'error'`)

| event_name | properties schema |
|---|---|
| `sync_failed` | `{error_type: string, retry_count: int}` |
| `api_error` | `{endpoint: string, status_code: int, error_message: string}` |
| `crash_recovered` | `{screen: string, error_type: string}` |
| `form_validation_failed` | `{form_type: string, field: string, reason: string}` |

---

## 4. Identity Resolution

### Per-Platform Identity Sources

| Field | iOS Source | Android Source | Web Source |
|---|---|---|---|
| `user_id` | `UserDefaults.standard.string(forKey: "user_id")` | `SharedPreferences.getString("user_id")` | Supabase Auth session `user.id` |
| `company_id` | `UserDefaults.standard.string(forKey: "company_id")` | `SharedPreferences.getString("company_id")` | Supabase Auth session or API lookup |
| `role` | `UserDefaults.standard.string(forKey: "user_role")` | `SharedPreferences.getString("user_role")` | User profile from Supabase |
| `plan` | `UserDefaults.standard.string(forKey: "subscription_plan")` | `SharedPreferences.getString("subscription_plan")` | Company record from Supabase |

### Identity Lifecycle

1. **Pre-auth events** (app_open, screen_view during onboarding): `user_id` and `company_id` are NULL. Session is tracked by `session_id` only.
2. **On login/signup**: Identity fields are populated from UserDefaults/SharedPreferences/Supabase session. All subsequent events carry identity.
3. **On logout**: Identity fields are cleared. Events revert to session-only tracking.
4. **Role/plan changes**: The analytics service reads identity on each `track()` call, so changes are reflected immediately.

### Important: user_id is Supabase UUID, NOT Firebase UID

The `users` table has both `id` (UUID, primary key) and `auth_id` (UUID, Supabase Auth). The `user_id` in analytics events MUST be `users.id`, which is what `UserDefaults["user_id"]` contains after `AuthManager.loadUserFromSupabase()` runs.

---

## 5. iOS Implementation

### File Locations

| File | Purpose |
|---|---|
| `OPS/Utilities/AnalyticsService.swift` | Singleton. Public `track()` API. Auto-attaches identity + context. |
| `OPS/Utilities/AnalyticsEventQueue.swift` | UserDefaults-backed offline queue. Batch flush. |
| `OPS/Utilities/AnalyticsSession.swift` | Session ID generation. Session duration tracking. |

### AnalyticsService API

```swift
// Track an event
AnalyticsService.shared.track(
    eventType: .action,
    eventName: "task_created",
    properties: ["task_type": "maintenance", "has_schedule": true, "team_size": 3]
)

// Track a screen view (typically called from .onAppear)
AnalyticsService.shared.trackScreenView(
    screenName: "job_board",
    properties: ["segment": "projects"]
)

// Called from .onDisappear — calculates and records duration_ms
AnalyticsService.shared.endScreenView(screenName: "job_board")
```

### Flush Strategy

| Trigger | When |
|---|---|
| App foreground | `sceneDidBecomeActive` — flush queued offline events |
| Periodic | Every 30 seconds while app is active (Timer) |
| App background | `sceneWillResignActive` — flush before backgrounding |
| Network restored | Reachability monitor detects offline → online |

### Supabase Write Pattern

```swift
// Batch insert (max 50 events per flush)
try await SupabaseService.shared.client
    .from("analytics_events")
    .insert(batch)
    .execute()
```

### Relationship to Existing Systems

| System | Status | Relationship |
|---|---|---|
| `AnalyticsManager.swift` (Firebase) | UNCHANGED | Continues firing 5 Google Ads conversion events |
| `OnboardingSupabaseAnalytics.swift` | UNCHANGED | Continues writing to `onboarding_analytics` table |
| `WizardAnalyticsService.swift` | UNCHANGED | Continues writing to `wizard_analytics` table |
| `TutorialAnalytics.swift` | UNCHANGED | Continues writing to `tutorial_analytics` table |
| `AnalyticsService.swift` (NEW) | NEW | Writes to `analytics_events` table |

The new AnalyticsService does NOT replace or wrap any existing analytics. It is a parallel, additive system.

---

## 6. Android Implementation Guide

> **For the Android agent implementing this system.**

### Overview

The Android app at `ops-android/` uses Kotlin, Hilt (DI), Room (local DB), and the Supabase Kotlin SDK. Firebase Analytics SDK (`firebase-analytics-ktx`) is already included but dormant (no `logEvent()` calls).

### What to Build

1. **`AnalyticsService`** — Hilt `@Singleton`. Same API shape as iOS: `track(eventType, eventName, properties, durationMs)`. Auto-attaches identity from SharedPreferences.

2. **`AnalyticsEventQueue`** — Room entity + DAO for offline persistence (more robust than SharedPreferences for Android). Max 1000 events. Batch flush of 50.

3. **`AnalyticsSession`** — Object that generates `session_id` UUID in `Application.onCreate()`. Tracks session start time.

### Identity Access on Android

```kotlin
// User ID (set by auth flow after Supabase user lookup)
val userId = sharedPreferences.getString("user_id", null)

// Company ID
val companyId = sharedPreferences.getString("company_id", null)

// Role — must be cached to SharedPreferences on login (from users table)
val role = sharedPreferences.getString("user_role", null)  // 'Admin', 'Office Crew', 'Field Crew'

// Plan — must be cached to SharedPreferences on login (from companies table)
val plan = sharedPreferences.getString("subscription_plan", null) // 'trial', 'starter', 'team', 'business'
```

**If `user_role` and `subscription_plan` are not currently cached to SharedPreferences on Android, you must add that caching as part of the auth flow.** Check `AuthRepository` or equivalent for the login success handler.

### Device Context on Android

```kotlin
val platform = "android"
val appVersion = BuildConfig.VERSION_NAME          // e.g. "1.0.0"
val deviceType = "${Build.MANUFACTURER} ${Build.MODEL}" // e.g. "Google Pixel 8"
val osVersion = "Android ${Build.VERSION.RELEASE}"      // e.g. "Android 15"
```

### Flush Strategy

Same as iOS:
- On `Activity.onResume()` (app foregrounded)
- Every 30 seconds via `CoroutineScope` + `delay`
- On `Activity.onPause()` (app backgrounded)
- On `ConnectivityManager.NetworkCallback` (network restored)

### Supabase Write Pattern

```kotlin
// Using Supabase Kotlin SDK
supabaseClient.from("analytics_events").insert(batch)
```

### Screen View Tracking on Android

Use `Lifecycle` observers or `NavController.addOnDestinationChangedListener` to automatically track screen views. Calculate `duration_ms` from `onResume` to `onPause`.

### Firebase Analytics Dual-Write

Activate the dormant Firebase Analytics SDK for the 5 conversion events only:

```kotlin
// In AnalyticsService, for dual-write events:
firebaseAnalytics.logEvent(FirebaseAnalytics.Event.SIGN_UP) { ... }
```

The 5 events: `sign_up`, `purchase`, `create_first_project`, `complete_onboarding`, `task_completed`.

### Key Files to Reference

| File | What's There |
|---|---|
| `app/build.gradle.kts` | Firebase dependencies (line ~98) |
| `core/core-network/` | Supabase client setup |
| `feature/feature-auth/` | Auth flow, where identity gets set |
| `core/core-network/src/.../TutorialAnalyticsRepository.kt` | Existing Supabase analytics pattern (fire-and-forget) |
| `app/src/.../OpsApplication.kt` | Application class, Timber logging init |

---

## 7. Web Implementation Guide

> **For the Web agent implementing this system.**

### Overview

The web app at `ops-web/` is Next.js (App Router) with Supabase. Analytics events should be tracked client-side (user interactions happen in the browser) and flushed to Supabase.

### What to Build

1. **`AnalyticsService`** — TypeScript singleton (or React context). Same API: `track(eventType, eventName, properties, durationMs)`. Auto-attaches identity from Supabase auth session.

2. **`useScreenView` hook** — React hook that tracks screen_view on mount and duration_ms on unmount. Used in page components.

3. **Session management** — Generate `session_id` UUID on page load (store in `sessionStorage`). Resets on new tab/window.

### Identity Access on Web

```typescript
// From Supabase auth session (client-side)
const { data: { session } } = await supabase.auth.getSession()
const userId = session?.user?.id  // This is Supabase Auth UUID

// IMPORTANT: This is auth_id, not users.id
// You need to look up the users table row to get the actual user_id, company_id, role
// Cache this in a React context or zustand store after login

// From cached user profile (fetched on login)
const { userId, companyId, role, plan } = useUserProfile()
```

### Web-Specific Considerations

- **No offline queue needed** for web (users are always online when using the dashboard)
- **Batch events** using `requestIdleCallback` or a 5-second flush interval to avoid excessive Supabase writes
- **Route change tracking**: Use Next.js `usePathname()` to detect navigation and fire screen_view events
- **Tab visibility**: Use `document.visibilityState` to pause/resume session duration tracking

### Device Context on Web

```typescript
const platform = "web"
const appVersion = process.env.NEXT_PUBLIC_APP_VERSION || "unknown"
const deviceType = /Mobile/.test(navigator.userAgent) ? "mobile" : "desktop"
const osVersion = navigator.userAgent // or parse with a lightweight UA parser
```

### Supabase Write Pattern

```typescript
// Client-side insert (needs appropriate RLS or use server action)
const { error } = await supabase
  .from('analytics_events')
  .insert(batch)

// Alternative: Server Action for writes (bypasses RLS)
// app/actions/analytics.ts
'use server'
import { getAdminSupabase } from '@/lib/supabase/admin'

export async function trackEvents(events: AnalyticsEvent[]) {
  const supabase = getAdminSupabase()
  await supabase.from('analytics_events').insert(events)
}
```

### Key Files to Reference

| File | What's There |
|---|---|
| `src/lib/admin/admin-queries.ts` | Existing admin query patterns (service role) |
| `src/lib/admin/app-flow-queries.ts` | Existing `app_events` query patterns |
| `src/lib/firebase/admin-sdk.ts` | Current DAU/WAU/MAU calculation (to be replaced) |
| `src/app/admin/engagement/page.tsx` | Current engagement dashboard (to be enhanced) |
| `src/app/admin/_components/charts/` | Chart components (line, bar, donut, funnel, sparkline, stat-card) |

### GA4 Visit + Traffic Tracking (added 2026-05-25 — OPS-Web `ae429101`)

In addition to the Supabase `analytics_events` pipeline above, OPS-Web fires the GA4 gtag.js snippet on every page load. This is a visit/traffic-grade surface (sessions, page_view, device, geo, referrer) that product analytics is not designed to expose. Runs in parallel to — does NOT replace — the Supabase pipeline.

| Item | Value |
|---|---|
| Component | `src/components/layout/GoogleAnalytics.tsx` (mirror of the ops-site implementation) |
| Mount point | `src/app/layout.tsx`, inside `<body>`, after `<Providers>` |
| Env var | `NEXT_PUBLIC_GA_MEASUREMENT_ID` (same name as ops-site) |
| Conditional render | Component returns `null` if the env var is unset; runtime configuration also exits unless the browser hostname exactly matches the surface's production allowlist |
| Load strategy | `next/script` with `strategy="afterInteractive"` (post-hydration, non-blocking) |
| Identity attachment | None. GA4 manages its own client_id cookie. Do not pipe Supabase `user_id` into `gtag('config', ..., { user_id })` without an explicit privacy review — internal UUIDs in GA dimension data create downstream PII handling obligations. |

**Production property registry.** Property selection is explicit and fail-closed:

| Registry key | Surface | GA property ID | Measurement ID |
|---|---|---:|---|
| `marketing` | `opsapp.co` + `try.opsapp.co` | `475051117` | `G-HKM7RWVTDV` |
| `web_app` | `app.opsapp.co` | `539494652` | `G-JJP5SN122V` |
| `ios_app` | Firebase iOS app | `514229717` | Managed by Firebase |

**Production-host boundary (production verified 2026-09-05).** Browser configuration has an exact allowlist before `dataLayer` is created or `gtag('config')` is called. The primary marketing deployment accepts only `opsapp.co` and `www.opsapp.co`; the acquisition landing app accepts only `try.opsapp.co`; the logged-in product accepts only `app.opsapp.co`. Localhost, loopback addresses, Vercel previews, and arbitrary aliases do not configure GA or Google Ads. The acquisition landing app also suppresses its `onboarding_events` and `tutorial_analytics` writes outside `try.opsapp.co`, at both the client and API-route boundaries. Preview analytics require a separate QA property rather than writing into production reporting.

**GA4 hostname filter and repair replay (production verified 2026-09-05).** `src/lib/analytics/ga4-report-filter.ts` composes each web property's exact production `hostName` allowlist into the acquisition warehouse request and every direct admin, blog, shared, and SPEC GA4 Data API report. Filtering occurs before aggregation and does not add hostname to persisted fact grain. Native iOS conversion QA has no hostname and remains unchanged; the analytics-health property-permission probe is intentionally unfiltered because it tests access, not traffic. GA4 sync metadata carries `hostname_filter_version: 1`; older state restarts at the 14-month retention boundary. The existing atomic replacement RPC removes contaminated `ga4_daily_acquisition` and derived `channel_metrics` rows as each date replays, while D-8 through D-2 are restated on the first post-release run.

**Release verification (2026-09-05).** The production aliases resolved to READY deployments: OPS-Web `dpl_CTSMvUZksuStAK6yxFNxp5hWPmco` at `3a89c08ca1f5b827ccac2f6194842e83f8f7abc8`, ops-site `dpl_Hm3hYDVsxmm3v4vSGtw566oVWJ9a` at `5c2701a015d000923a6b9a8c60fe0da756966c0b`, and try-ops `dpl_5XMczex3WnTKANsRF19dvhBETqU2` at `55dea47d948f7ebe63999a0c5ec57efda717b9d2`. The live OPS-Web commit contains analytics repair `77b9e34c5` and admin-session repair `557366e07`; the inspected analytics/auth files are unchanged from release source `83ef947d0`.

- The latest `ga4_marketing` and `ga4_web_app` runs completed at approximately 09:44 UTC with `hostname_filter_version: 1`, `backfill_complete: true`, no cursor, and finalized data through September 3. This proves completion of the planned retained-history replay, not a rewrite of rows predating its retention boundary.
- Independent warehouse readback for September 1–2 found 63 marketing sessions, 17 engaged sessions, and 15 Organic Search sessions. September 3 had 23 sessions, 4 engaged sessions, and 4 Organic Search sessions.
- A live `/admin?analytics_verification=1` request with a malformed cookie returned `307 /login?redirect=%2Fadmin%3Fanalytics_verification%3D1` and expired both auth cookies. Login with the same rejected cookie returned `200`, not a Dashboard redirect; unauthenticated `/api/admin-debug` returned `401`. This verifies the rejected-session routing boundary, not a signed-in browser account flow.
- Fifteen dependency-free execution assertions passed against the unchanged release helpers, covering blocked hosts, production GA initialization, expired/malformed token rejection, token-lifetime skew, and canonical-cookie precedence. The complete Vitest suite was not rerun because the isolated release checkout no longer has its installed dependencies.
- The broader App Store reporting gap remains: the September 5 health snapshot reports `app_store.sync_status` failed (`running`, expected `complete`) and zero commerce reports. GA web/iOS property checks remain healthy. This release does not establish complete App Store download coverage or a signed iOS customer release.

**Privacy.** OPS-Web URLs can contain resource UUIDs (project IDs, client IDs) which are not direct PII but should not be retained indefinitely. `anonymize_ip` is GA4-default. Query-param exclusion + path scrubbing for resource UUIDs is configured at the GA4 admin level for the OPS-Web data stream — **do not encode** this in the client-side component, since admin-level config is overridable per-stream while code changes require a redeploy.

**What this does NOT replace.**
- Feature-adoption events (project_created, task_completed, photo_uploaded, etc.) → still Supabase `analytics_events`.
- Funnel/retention/cohort dashboards → still admin panel reading from Supabase.
- Google Ads conversion attribution → still Firebase Analytics (§ 10), narrow scope.

---

## 8. Offline Event Queue Specification

### Requirements

- Events persist across app kills and crashes
- Maximum 1000 events in queue (FIFO — oldest dropped when full)
- Flush in batches of 50 events
- Retry on network failure (keep events in queue)
- Clear only after confirmed Supabase insert success

### iOS Implementation Pattern

```swift
// Storage: UserDefaults (JSON-encoded array)
// Key: "analytics_event_queue"
// Pattern: Same as WizardAnalyticsService offline queue

struct QueuedEvent: Codable {
    let id: UUID
    let userId: String?
    let companyId: String?
    let role: String?
    let plan: String?
    let eventType: String
    let eventName: String
    let platform: String
    let appVersion: String?
    let deviceType: String?
    let osVersion: String?
    let sessionId: UUID
    let properties: [String: AnyCodable]
    let durationMs: Int?
    let createdAt: Date
}
```

### Android Implementation Pattern

```kotlin
// Storage: Room database (more robust than SharedPreferences for structured data)
@Entity(tableName = "analytics_queue")
data class QueuedEvent(
    @PrimaryKey val id: String = UUID.randomUUID().toString(),
    val userId: String?,
    val companyId: String?,
    val role: String?,
    val plan: String?,
    val eventType: String,
    val eventName: String,
    val platform: String = "android",
    val appVersion: String?,
    val deviceType: String?,
    val osVersion: String?,
    val sessionId: String,
    val properties: String, // JSON string
    val durationMs: Int?,
    val createdAt: Long = System.currentTimeMillis()
)
```

### Web: No Offline Queue

Web users are always online. Use a simple in-memory buffer with periodic flush (every 5 seconds or on `beforeunload`).

---

## 9. Admin Panel Dashboard Specification

> **For the admin panel agent building the analytics dashboards.**

### New Route: `/admin/app-analytics`

Add to the admin sidebar navigation (`NAV_ITEMS` in `src/app/admin/_components/sidebar.tsx`).

### Tab 1: Engagement Overview

**Metrics to display:**

| Metric | Query | Replaces |
|---|---|---|
| DAU | Count distinct `user_id` from `analytics_events` where `created_at >= today` | `calcActiveUsers()` from Firebase Auth |
| WAU | Count distinct `user_id` where `created_at >= 7 days ago` | `calcActiveUsers()` from Firebase Auth |
| MAU | Count distinct `user_id` where `created_at >= 30 days ago` | `calcActiveUsers()` from Firebase Auth |
| Active users sparkline | Daily distinct user counts over last 13 weeks | New |
| Platform breakdown | Group by `platform`, count distinct users | New |
| Avg session duration | Avg of `duration_ms` from `app_close` lifecycle events | New |
| Sessions per user (daily) | Count `session_id` / count distinct `user_id` per day | New |

**Charts:**
- Line chart: DAU/WAU/MAU trend (use existing `line-chart.tsx`)
- Donut chart: Platform breakdown (use existing `donut-chart.tsx`)
- Stat cards: DAU, WAU, MAU, avg session duration (use existing `stat-card.tsx`)

### Tab 2: Feature Adoption

**Metrics to display:**

| Metric | Query |
|---|---|
| Feature usage count | Count events where `event_type = 'action'` grouped by `event_name` |
| Companies using feature | Count distinct `company_id` per `event_name` |
| Adoption rate | `(companies_using / total_companies) * 100` |
| Usage frequency | Average events per user per week, per feature |
| Platform breakdown per feature | Group by `event_name` + `platform` |

**Charts:**
- Table: Feature name, adoption %, usage frequency, platform icons (use existing `table` pattern)
- Bar chart: Top 10 features by usage (use existing `bar-chart.tsx`)
- Sparkline per feature: Weekly trend

### Tab 3: Funnels & Friction

**Funnel builder:**

Allow selecting a sequence of events to build a conversion funnel. Default funnels:

1. **First Project Funnel**: `sign_up` → `complete_onboarding` → `project_created` → `task_created`
2. **Task Completion Funnel**: `task_form` (screen_view) → `task_created` → `task_completed`
3. **Expense Logging Funnel**: `accounting` (screen_view) → `expense_logged` (vs `expense_abandoned`)

**Friction metrics:**
- Top errors by frequency (from `event_type = 'error'`)
- Error rate by screen (join error events with preceding screen_view)
- Sync failure rate trend
- Form abandonment rate by form type

**Charts:**
- Funnel chart (use existing `funnel-chart.tsx`)
- Table: Error inventory with count, last occurrence, affected users
- Line chart: Error rate over time

### API Routes

All routes follow existing patterns in `src/app/api/admin/`:

```
GET /api/admin/app-analytics/active-users
  Query params: from, to, granularity (daily|weekly|monthly), platform (ios|android|web|all)
  Returns: { dau, wau, mau, sparkline: [{date, count}] }

GET /api/admin/app-analytics/feature-usage
  Query params: from, to, platform
  Returns: [{ event_name, total_count, companies_using, adoption_rate, avg_per_user_per_week }]

GET /api/admin/app-analytics/funnels
  Query params: from, to, platform, steps (comma-separated event_names)
  Returns: [{ step, event_name, count, drop_off_rate }]

GET /api/admin/app-analytics/errors
  Query params: from, to, platform, limit
  Returns: [{ event_name, count, last_seen, affected_users, properties }]

GET /api/admin/app-analytics/sessions
  Query params: from, to, platform
  Returns: { avg_duration_ms, sessions_per_user, total_sessions, platform_breakdown }
```

### Query Patterns

Use `getAdminSupabase()` (service role) for all queries. Follow caching patterns from existing `admin-queries.ts` (Next.js `unstable_cache()`).

**Distinct user count (DAU) example:**

```typescript
// Using Supabase RPC for distinct count (more efficient than client-side dedup)
const { data } = await supabase.rpc('count_distinct_users', {
  start_date: startOfDay,
  end_date: endOfDay,
  platform_filter: platform || null
})
```

You'll need a Supabase SQL function for efficient distinct counts:

```sql
CREATE OR REPLACE FUNCTION count_distinct_users(
  start_date timestamptz,
  end_date timestamptz,
  platform_filter text DEFAULT NULL
) RETURNS bigint AS $$
  SELECT COUNT(DISTINCT user_id)
  FROM analytics_events
  WHERE created_at >= start_date
    AND created_at < end_date
    AND user_id IS NOT NULL
    AND (platform_filter IS NULL OR platform = platform_filter);
$$ LANGUAGE sql STABLE;
```

---

## 10. Firebase Analytics (Google Ads Conversions)

### Server-side conversion path (2026-09-09, authoritative for bidding)

The Firebase events below still fire, but since 2026-09-09 the conversions Google bids on come from the **server**: database triggers enqueue `trial_started` (company created, any platform), `trial_activated` (first real project), and `paid` (first `invoice.paid`) into `ads_conversion_events`, and `/api/cron/ads-conversions` sends them hourly to the Data Manager API against the three OPS `UPLOAD_CLICKS` actions, matched by `gclid` / `gbraid` / `wbraid` from `trial_attributions` or the owner's hashed email. Only `OPS · Trial started` is primary; the Firebase iOS `sign_up` / `login` / `first_open` actions are secondary (observation) so an app login no longer counts as a conversion. Contract and setup: `04_API_AND_INTEGRATION.md` § Google Ads Conversion Events; tables: `03_DATA_ARCHITECTURE.md` § Google Ads Engine Tables; operations: `ops-web/docs/ads/runbook.md`.

### iOS: `AnalyticsManager.swift`

**Location:** `ops-ios/OPS/Utilities/AnalyticsManager.swift`

This file is UNCHANGED by the new analytics system. It continues to:
- Fire 5 conversion events to Firebase Analytics
- Set user properties (`user_type`, `subscription_status`)
- Track screen views for Firebase (separate from Supabase screen_view events)

### Android: Firebase Analytics (Dormant → Activate for 5 events)

Firebase Analytics SDK is already in `app/build.gradle.kts`. Activate it for the 5 conversion events only. Do not add broad Firebase event tracking — Supabase is the primary system.

### Conversion Event Parameter Reference

| Event | Firebase Event Name | Parameters |
|---|---|---|
| Sign Up | `AnalyticsEventSignUp` | `method` |
| Purchase | `AnalyticsEventPurchase` | `item_name`, `price`, `currency` |
| First Project | `"create_first_project"` | `user_type`, `project_count` |
| Complete Onboarding | `"complete_onboarding"` | `user_type`, `has_company` |
| Task Completed | `"task_completed"` | `task_type` |

---

## 11. Existing Analytics Systems (Legacy)

These systems continue operating independently. They are NOT replaced by `analytics_events`.

| System | Table | Purpose | Status |
|---|---|---|---|
| Onboarding Analytics | `onboarding_analytics` | Legacy step-by-step onboarding funnel (written by the pre-rebuild A/B/C flow). The rebuilt express flow (2026-06-13) emits its funnel as `lifecycle` events on `analytics_events` instead — see § 3 `onboarding_step_viewed` / `onboarding_completed` / `onboarding_abandoned`. | Legacy (dead path) |
| Wizard Analytics | `wizard_analytics` | Guided tour engagement with offline queue | Active (iOS) |
| Tutorial Analytics | `tutorial_analytics` | Tutorial phase progression | Active (iOS + Android) |
| GA4 (server-side) | N/A | Marketing site traffic, used in admin `/analytics` | Active (Web) |
| Google Ads | `ads_daily_account/campaign/search_term/ad_group/ad/asset/keyword`, `ads_entities`, `ads_click_map`, view `ads_funnel_by_keyword`, `ads_conversion_events` | Campaign → keyword → click grain warehoused daily; conversions sent server-side through the Data Manager API; readiness ledger + engine surfaces on admin `/google-ads` | Active (Web, 2026-09-09) |
| `app_events` | `app_events` | Website user flow analysis (Flow Galaxy) | Active (Web) |

---

## 12. Data Retention & Performance

### Retention Policy

A Supabase cron job runs daily to delete events older than 90 days:

```sql
-- pg_cron job
SELECT cron.schedule(
  'analytics_events_cleanup',
  '0 3 * * *',  -- 3 AM daily
  $$DELETE FROM analytics_events WHERE created_at < now() - interval '90 days'$$
);
```

### Performance Considerations

- **Expected volume:** ~100-500 events per user per day across all platforms
- **At 1000 users:** ~50K-500K events/day, ~4.5M-45M rows before retention kicks in
- **Index strategy:** Composite indexes on (company_id, created_at) and (event_type, event_name, created_at) keep common queries fast
- **Batch writes:** Max 50 events per insert keeps write transactions small
- **Future optimization:** If query performance degrades, add materialized views for DAU/WAU/MAU aggregates refreshed via cron

---

## 13. Adding New Events

To add a new event to the taxonomy:

1. **Choose `event_type`**: `screen_view`, `action`, `feature_use`, `lifecycle`, or `error`
2. **Name the event**: Use `snake_case`. Be specific: `invoice_sent` not `send`.
3. **Define properties**: Document the JSONB shape in this file (Section 3).
4. **Implement on each platform**: Call `AnalyticsService.track()` at the appropriate code point.
5. **No schema migration needed**: The `properties` JSONB column handles any shape.
6. **Update this document**: Add the new event to the taxonomy table in Section 3.

---

## 14. Privacy & Compliance

### What We Track

- User actions within the app (screens viewed, features used, errors encountered)
- Device metadata (device model, OS version, app version)
- Session duration and engagement patterns

### What We Do NOT Track

- No PII in event properties (no names, emails, phone numbers, addresses)
- No location data in analytics (crew location tracking is a separate system)
- No content of user data (no project names, task descriptions, client details)
- No third-party tracking pixels or cross-app identifiers

### Data Ownership

All analytics data is stored in OPS's own Supabase instance. No data leaves OPS infrastructure. No third-party analytics services have access.

### User Opt-Out

Currently not implemented. Future consideration: add an "Analytics" toggle in Settings → App Settings that sets a UserDefaults flag checked by `AnalyticsService.track()` before enqueueing.
