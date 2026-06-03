# 04 - API AND INTEGRATION

**OPS Software Bible - Complete API and Integration Architecture**

**Purpose**: This document provides comprehensive documentation of the OPS backend integration, sync architecture, and network operations. It covers the Supabase backend, repository layer, sync strategies, realtime subscriptions, conflict resolution, image handling, push notifications, and integration patterns. This enables any developer or AI agent to implement the entire sync system from scratch with complete fidelity to the iOS implementation.

**Last Updated**: June 2, 2026
**iOS Reference**: `OPS/OPS/Network/` (Supabase/, Sync/, Auth/, Services/)
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
15. [Error Handling & Retry Logic](#error-handling--retry-logic)
16. [Rate Limiting & Debouncing](#rate-limiting--debouncing)
17. [Supabase Table Reference](#supabase-table-reference)
18. [Bubble.io (Legacy)](#bubbleio-legacy)
19. [Bubble-to-Supabase Migration API](#bubble-to-supabase-migration-api)
20. [Email Pipeline Integration Routes (24 Routes)](#email-pipeline-integration-routes-24-routes)
21. [OpenAI API Key Separation](#openai-api-key-separation)

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
- OneSignal push notification routing (`/api/notifications/send`)
- Stripe subscription management

**Bubble.io** is **legacy** -- see the [Bubble.io (Legacy)](#bubbleio-legacy) section for details on what remains.

### System Diagram

```
iOS App (SwiftData)                   OPS Web (Next.js)
    |                                      |
    |-- supabase-swift SDK ------------->  Supabase (PostgreSQL + Auth + Realtime)
    |                                      |
    |-- HTTPS --------> app.opsapp.co ----+--- /api/uploads/presign --> AWS S3
    |                                      +--- /api/notifications/send --> OneSignal
    |                                      +--- /api/stripe/* --> Stripe
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
5. Server-side API calls to OPS-Web pass the Supabase `accessToken` as `Bearer` header

### Cross-Platform Onboarding & Signup Contract

Onboarding completion is server-authoritative across OPS-Web, ops-site handoff paths, and OPS iOS. A user is not considered fully onboarded by any client unless the server-backed `users.onboarding_completed` map confirms the relevant platform and the user also has a valid `company_id` and `user_type`.

**Web setup routes (`OPS-Web`):**

| Route | Purpose | Contract |
|-------|---------|----------|
| `POST /api/setup/progress` | Persist web setup drafts and partial progress | Idempotent per step. Reuses an existing owner company by `companies.account_holder_id` before creating a new company. Company creation/updates are limited to company users who are owner/admin-capable. Runs `initialize_company_defaults(company_id)` on company-step retry so interrupted setup can self-heal missing defaults. |
| `POST /api/setup/complete` | Complete owner/company web setup | Requires a company-attached owner/admin-capable user. Rejects employee users. Merges `onboarding_completed.web=true`; clients must not mark web onboarding complete locally until this response succeeds. |
| `POST /api/auth/join-company` | Join an existing company by code | Calls `join_user_to_company(p_user_id, p_company_id, p_company_code)` and must pass the normalized company-code proof. |
| `POST /api/onboarding/complete` | Complete iOS onboarding through the web API gateway | Accepts Firebase `idToken`/`token` plus `platform:"ios"`, verifies the OPS user, requires `company_id` and `user_type`, rejects non-admin company users when completing company-owner onboarding, merges `onboarding_completed.ios=true`, and records `setup_progress.steps.ios_onboarding=true`. |

**Database RPC hardening:** `public.join_user_to_company` takes `(p_user_id uuid, p_company_id uuid, p_company_code text default null)`. For authenticated callers, `auth.uid()` must match `p_user_id`, `p_company_code` is required, and the normalized proof must match the locked `companies.company_code`. Service-role callers may still perform controlled server-side joins.

**Client rules:**

- Partial web setup is resume-safe. `/setup` writes each step before advancing; if the network drops, the UI stays on the current step and keeps the draft local instead of skipping ahead.
- Web setup accepts a sanitized `redirect`/`continue` destination. Production only permits same-origin or explicit OPS-owned destinations; development-only localhost allowances are disabled when `NODE_ENV` or `NEXT_PUBLIC_VERCEL_ENV` is production.
- iOS must call `/api/onboarding/complete` and wait for the server ACK before setting local onboarding completion. A cached `companyId` is not proof of completion.
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

---

## Supabase Repositories

**Source**: `OPS/Network/Supabase/Repositories/`

All 15 repository classes follow the same pattern: each takes a `companyId` on init (except `CompanyRepository` and `NotificationRepository`), holds a reference to `SupabaseService.shared.client`, and provides typed CRUD methods against specific Supabase tables.

### 1. ProjectRepository

**Table**: `projects`
**Init**: `ProjectRepository(companyId:)`
**Audit Columns** (2026-05-10, bug 9d5c2535): `created_at` (TIMESTAMPTZ, Supabase default `now()`) and `created_by` (UUID FK → `auth.users.id`, populated by iOS on insert, immutable). Both are round-tripped through `SupabaseProjectDTO`. The combined index `idx_projects_created_by_created_at (created_by, created_at DESC) WHERE deleted_at IS NULL` powers the "start from recent" suggestions strip on the project form.
**Vinyl Order Marker Columns** (2026-05-21): `vinyl_order_status` (`not_ordered` / `ordered`, default `not_ordered`), `vinyl_ordered_at` (TIMESTAMPTZ), and `vinyl_ordered_by` (UUID FK → `auth.users.id`). These are marker-only project fields for Deck Builder companies and are round-tripped through `SupabaseProjectDTO`; they do not create catalog orders, inventory deductions, or task materials.

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

Also provides `NewCompanyPayload` struct and `generateCompanyCode()` helper (8-char alphanumeric, no ambiguous chars like 0/O/1/I).

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
| `fetchForProject` | `(_ projectId: String) -> [PhotoAnnotationDTO]` | All annotations for a project |
| `fetchForPhoto` | `(projectId:, photoURL:) -> PhotoAnnotationDTO?` | Single annotation for a specific photo |
| `upsert` | `(_ dto: UpsertPhotoAnnotationDTO) -> PhotoAnnotationDTO` | Upsert annotation |
| `create` | `(_ dto: UpsertPhotoAnnotationDTO) -> PhotoAnnotationDTO` | Insert annotation |
| `updateAnnotation` | `(_ annotationId:, annotationUrl:, note:)` | Update annotation URL and note |
| `softDelete` | `(_ annotationId: String)` | Soft delete |

### 15. NotificationRepository

**Table**: `notifications`
**Init**: `NotificationRepository()` (no companyId -- queries filter by userId)

| Method | Signature | Description |
|--------|-----------|-------------|
| `fetchUnreadCount` | `(userId: String) -> Int` | Server-side count (no row transfer, uses `head: true, count: .exact`) |
| `fetchRecent` | `(userId:, limit: Int) -> [NotificationDTO]` | Recent notifications (default 50) |
| `markAsRead` | `(_ notificationId: String)` | Mark single notification as read |
| `markAllAsRead` | `(userId: String)` | Mark all unread notifications as read for a user |

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

RealtimeProcessor subscribes to Postgres changes on 9 entity tables filtered by `company_id`. When an INSERT, UPDATE, or DELETE event arrives, it decodes the payload into the appropriate DTO, converts to a SwiftData model, and performs a field-by-field upsert with merge protection.

### Configuration

```swift
func configure(modelContext: ModelContext, companyId: String)
func startListening() async
func stopListening() async
```

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

Push notifications use a server-side routing pattern:
1. iOS calls OPS-Web API route: `POST https://app.opsapp.co/api/notifications/send`
2. OPS-Web forwards the request to OneSignal REST API (server-side, where the OneSignal API key is stored)
3. OneSignal delivers the push to the target device(s)

The iOS app receives pushes via the `OneSignalFramework` SDK, configured in `AppDelegate`.

### Request Format

```swift
POST /api/notifications/send
Authorization: Bearer {supabase_access_token}
Content-Type: application/json

{
    "recipientUserIds": ["userId1", "userId2"],
    "title": "Notification Title",
    "body": "Notification body text",
    "data": {
        "type": "taskAssignment",
        "taskId": "...",
        "projectId": "...",
        "screen": "taskDetails"
    }
}
```

### 6 Notification Event Types

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

## Error Handling & Retry Logic

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
    case presignError(statusCode: Int)
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
- Some onboarding workflows still reference Bubble field names (visible in `OnboardingManager.swift`, `OnboardingViewModel.swift`)
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

**Behavior:** If `connectionId` is provided, syncs that single connection. If `companyId`, syncs all active connections for that company. Each `SyncResult` contains `{ connectionId, activitiesCreated, newLeads }`. Sync-created opportunity titles use the shared email title helper. Inbound leads prefer parsed contact-form submitters and inbound sender identity before linked client display names; sent-folder safety-net leads use the external recipient identity and never the operator sender. Subjects remain activity/thread context.

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
| Response | `{ ok: true, synced: number, staleSweepChanges: number, results: SyncResult[] }` |
| Service calls | `SyncEngine.runSync()`, `SyncEngine.sweepStaleLeads()` |

**Behavior:** Queries all active email connections, batch-fetches companies and filters by active subscription via `getSubscriptionInfo()` before running sync — expired/cancelled companies are silently skipped. Checks each connection against its `sync_interval_minutes` + `last_synced_at` to determine if sync is due, runs `SyncEngine.runSync()` for each. Also runs `SyncEngine.sweepStaleLeads()` to detect follow-up-needed opportunities based on correspondence age (independent of new email arrival). Manual sync (`POST /api/integrations/email/manual-sync`) also checks subscription status before proceeding. Each `SyncResult`: `{ connectionId, email, provider, activitiesCreated, newLeads, error? }`.

### 15. POST /api/cron/webhook-renewal

**Purpose:** Renews expiring Gmail Pub/Sub watches and M365 subscriptions. Runs daily via Vercel Cron.

| Field | Value |
|-------|-------|
| Auth | Cron secret (`Authorization: Bearer $CRON_SECRET`) |
| Response | `{ ok: true, renewed: number, results: [{ id, provider, renewed, error? }] }` |
| Service calls | `EmailService.getConnection()`, provider `renewWebhook()`, `EmailService.updateConnection()` |

**Behavior:** Finds active connections with webhooks expiring within 2 days, renews each via the provider abstraction (Gmail: re-register Pub/Sub watch with 7-day expiry; M365: renew subscription with 3-day expiry), updates `webhook_subscription_id` and `webhook_expires_at`.

### 16. POST /api/integrations/email/send

**Purpose:** Sends an email via the user's connected Gmail or M365 account.

| Field | Value |
|-------|-------|
| Auth | Service role (subscription check + rate limit 100/hour) |
| Request body | `{ userId, companyId, connectionId, to: string[], cc?: string[], subject, body, format?: "markdown"\|"plain", opportunityId?, inReplyTo?, threadId? }` |
| Response | `{ ok: true, messageId, threadId }` |
| Service calls | `EmailService.getConnection()`, provider `sendMessage()`, `OpportunityService.createActivity()`, `EmailMatchingServiceV2.match()` |

**Behavior:** When `format="markdown"`, converts `**bold**`, `*italic*`, `[link](url)` to HTML via `markdownToEmailHtml()` before sending. Creates an outbound activity record with `body_text`, `to_emails`, `cc_emails`, `has_attachments`. Updates opportunity correspondence counts if `opportunityId` is provided. Links thread via `opportunity_email_threads` upsert. Applies "OPS Pipeline" label to the thread (non-fatal if label application fails). Gmail: RFC 2822 encoding with `In-Reply-To` + `References` headers for threading. M365: Graph API `/createReply` for threading, `/sendMail` for new emails.

### 17. GET /api/integrations/email/inbox

**Purpose:** Proxy inbox requests to Gmail/M365 for the in-app email viewer.

| Field | Value |
|-------|-------|
| Auth | Service role |
| Query params | `companyId` (required), `threadId?` (single thread), `q?` (search), `maxResults?` (default 50) |
| Response (inbox) | `{ threads: InboxThread[], nextPageToken? }` |
| Response (thread) | `{ messages: ThreadMessage[] }` |
| Service calls | `EmailService.getConnection()`, provider `listThreads()` / `getThread()` |

**Behavior:** Two modes: inbox listing (deduped by `threadId`) or thread detail (all messages in chronological order). Uses `EmailProviderInterface` abstraction, handles token refresh automatically. Permission: `email.view` required for All Mail tab access.

### 18. POST /api/integrations/email/ai-draft

**Purpose:** Generates an AI email draft using writing profile + thread context + memory facts.

| Field | Value |
|-------|-------|
| Auth | Service role (ungated — any user with email connected) |
| Request body | `{ companyId, userId, connectionId, opportunityId?, threadId?, recipientEmail?, recipientName? }` |
| Response | `{ available: boolean, draft: string (markdown), draftHistoryId: string, confidence: number, sources: string[], reason?: string }` |
| Service calls | `WritingProfileService.getProfile()`, `MemoryService.getFacts()` (if Phase C enabled), `DraftGenerator.generateDraft()` |

**Behavior:** Assembles context from: writing profile + thread messages (last 20 from `activities.body_text`) + opportunity summary + memory facts (if `ai_email_memory` feature gate enabled). Model: `gpt-5.4-mini` via `OPENAI_API_KEY_DRAFTING`. Creates an `ai_draft_history` record with `status='drafted'` for tracking draft outcomes.

### 19. POST /api/integrations/email/draft-feedback

**Purpose:** Records the outcome of an AI-generated draft (sent or discarded) and triggers writing profile learning.

| Field | Value |
|-------|-------|
| Auth | Service role |
| Request body | `{ draftHistoryId, companyId, userId, outcome: "sent"\|"discarded", finalVersion? }` |
| Response | `{ ok: true, editDistance?: number, changesDetected?: string[] }` |
| Service calls | Direct queries on `ai_draft_history`, `WritingProfileService.learn()` |

**Behavior:** Computes edit distance (word-level Levenshtein) between original draft and `finalVersion`. Detects specific changes: greeting modifications, closing modifications, tone shifts. Updates the `ai_draft_history` record with outcome and edit metrics. Triggers writing profile learning if 3+ consistent changes are detected across recent drafts.

### 20. GET /api/integrations/email/draft-stats

**Purpose:** Returns AI draft approval statistics for a user.

| Field | Value |
|-------|-------|
| Auth | Service role |
| Query params | `companyId` (required), `userId` (required) |
| Response | `{ totalSent: number, sentWithoutChanges: number, approvalRate: number, commonChanges: string[], suggestAutoSend: boolean }` |
| Service calls | Direct queries on `ai_draft_history` |

**Behavior:** Aggregates draft outcomes for the user. `suggestAutoSend` returns `true` when `approvalRate >= 0.95` AND `totalSent >= 20`, indicating the user trusts AI drafts enough to enable automatic sending.

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

### Inbox Dark-Launch (2026-06-02)

The in-app `/inbox` screen is hidden behind a per-company flag while the email engine keeps running. Built on branch `feat/inbox-dark-launch-iso`; `inbox_ui` defaults OFF (public). Design + plan + verification live in `OPS-Web/docs/specs/2026-06-01-inbox-dark-launch-design.md`, `OPS-Web/docs/plans/2026-06-01-inbox-dark-launch.md`, `OPS-Web/docs/inbox-dark-launch-verification.md`.

**Gating flags**
- `inbox_ui` — per-company `admin_feature_overrides` key (default OFF). Gates the inbox SCREEN only. Read server-side via `AdminFeatureOverrideService.isFeatureEnabled(companyId, "inbox_ui")` (`src/lib/feature-flags/inbox-ui-gate.ts`); surfaced to the client through `GET /api/feature-flags`; toggled per company at `/admin/system` (`PATCH /api/admin/ai-features/[companyId]` with `feature:"inbox_ui"` → generic `setFeatureOverride`, no phase_c wizard side-effect). When off: `/inbox` + `/inbox/[threadId]` redirect to `/pipeline` server-side, the sidebar Inbox item is hidden, and the inbox-leads widget CTA repoints to `/pipeline`. `getSlugForRoute("/inbox")` resolves to `inbox_ui` (the stale `portal:["/inbox"]` mapping was removed).
- `phase_c` — unchanged; gates automatic drafting + AI enrichment. Does NOT gate the inbox screen or lead import.
- `INBOX_AUTO_SEND_ENABLED` (env, default unset) — fail-closed master switch on `POST /api/cron/auto-send`; the cron no-ops (returns `{ skipped: true }`) unless set to `"true"`. Nothing auto-sends at launch.

**NOT gated:** automatic lead import (inbound client + opportunity creation in the sync engine, `sync-engine.ts`) runs for every connected mailbox regardless of `inbox_ui`/`phase_c` — current functionality, preserved.

**Auto-draft into the mailbox** — `sync-engine.ts` `maybeAutoGenerateDraft` (phase_c-gated): on inbound client mail, after generating a voice-matched reply via `AIDraftService.generateDraft`, OPS pushes it into the user's real Gmail/Outlook Drafts folder via `provider.createDraft`/`updateDraft` (idempotent on `(connection_id, thread_id)` via `pickExistingMailboxDraft`), persisting `ai_draft_history.mailbox_draft_id`. Threaded to the original (Gmail `threadId` / M365 `conversationId`). Never auto-sends.

**Forwarded contact-form submissions → NEW thread (2026-06-03)** — a website contact-form submission forwarded into a connected mailbox (sender ∈ team forwarders, or a known form platform) lives on the *forwarder's* thread; a reply must instead start a clean new thread to the actual client. `maybeAutoGenerateDraft(email, connection, opportunityId, submitter?)` takes a fourth `submitter` arg (the parsed `contactFormSubmitter` from `extractContactFormSubmission`, already computed in `processInboundEmail`). When present it branches: `AIDraftService.generateDraft` **new-email path** (recipient = submitter, no inbound thread, grounded in the form message via `userInstruction`) → `placeNewThreadDraft` (`src/lib/api/services/mailbox-draft-push.ts`) → `provider.createNewThreadDraft(to, subject, body)` (no threadId; captures the provider-minted Gmail `message.threadId` / M365 `conversationId`). The minted thread id is persisted to `ai_draft_history.thread_id` **and** linked via `opportunity_email_threads` — so the user's eventual send creates an outbound activity on that thread and `reconcilePendingMailboxDrafts` (keyed on `thread_id`) classifies it `used → sent_from_mailbox`. Subject is a fresh `Thanks for reaching out` (ops-copywriter; never "Re:"); idempotency keys on `(connection_id, opportunity_id)`; never auto-sends (cold first contact is review-only). Brand-new contact-form leads (the sync `create_new` branch, previously un-drafted) now draft too, gated to `contactFormSubmitter`. The category gate classifies contact forms as `general` — the forwarder's junk subject ("New submission") otherwise matches `sub` → `subtrade_coordination` → `draft_on_request`, silently suppressing the draft.

**Learning loop re-wired through sync** — `src/lib/api/services/draft-reconciliation.ts`. Because the operator sends from their own mail client (not the OPS composer), `reconcilePendingMailboxDrafts` runs in the outbound-sync path, after the sent reply is ingested as an `activities` row. For each pending auto-draft (`status='auto_drafted'`, `mailbox_draft_id` set) it classifies the outcome via `classifyDraftOutcome` from (a) whether the draft is still in the mailbox (`provider.listDrafts`) and (b) whether an outbound reply exists after the draft's `created_at`:
- **used** (draft gone + outbound after) → strip quoted chain/signature (`stripPriorMessageOverlap`), feed `AIDraftService.recordDraftOutcome("sent", …)` (the existing edit-distance + writing-profile learning), set `status='sent_from_mailbox'`.
- **from_scratch** (draft still present + a different outbound) → `status='superseded'`; does NOT call `recordDraftOutcome` (the all-outbound learner at `learnFromOutboundEmail` already captured the reply as a voice sample — avoids a bogus 100%-rewrite edit signal).
- **discarded** (draft gone, no outbound within 14-day TTL) → `status='discarded_in_mailbox'`.

**Manual drafting (the public's path)** — the Pipeline "Draft" button (`POST /api/integrations/email/draft`) now generates + pushes the draft into the mailbox in one step, works WITHOUT phase_c (uses `AIDraftService.generateDraft`, replacing the old phase_c-gated `DraftGenerator`), and persists `mailbox_draft_id` + `status='auto_drafted'` so the same reconciliation learns from manual drafts. It also detects a forwarded contact-form lead (re-parsing the latest inbound activity with `extractContactFormSubmission`) and routes it through the same `placeNewThreadDraft` new-thread path as the sync engine — fresh subject, new thread to the client, not a "Re:" on the forwarder's thread.

**Notifications:** when `inbox_ui` is off, the per-draft "Draft ready" notification is suppressed (silent), the email-sync-complete notification repoints from `/inbox` to `/pipeline`, and a one-time "Replies, drafted" explainer fires on the first mailbox draft for the company.

**Schema:** `ai_draft_history.mailbox_draft_id` + the status-CHECK expansion (`sent_from_mailbox`, `discarded_in_mailbox`) — migrations `20260602000000` and `20260602010000` (see `03_DATA_ARCHITECTURE.md` → `ai_draft_history`).

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

**Auth**: Reads OPS user from any of: `Authorization: Bearer <token>` header, `__session` cookie, `ops-auth-token` cookie, `sb-<ref>-auth-token` cookie. Verifies via Supabase or Firebase JWKS (jose). Matches against `public.users` by auth_id → firebase_uid → email.

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

---

**End of Document**

This completes the comprehensive API and Integration documentation for the OPS Software Bible. Any developer or AI agent should now have complete context to implement the entire Supabase-backed sync system, repository layer, realtime subscriptions, image handling, push notifications, email pipeline integration, and error management with full fidelity to the current implementation.
