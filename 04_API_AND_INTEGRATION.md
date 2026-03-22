# 04 - API AND INTEGRATION

**OPS Software Bible - Complete API and Integration Architecture**

**Purpose**: This document provides comprehensive documentation of the OPS backend integration, sync architecture, and network operations. It covers the Supabase backend, repository layer, sync strategies, realtime subscriptions, conflict resolution, image handling, push notifications, and integration patterns. This enables any developer or AI agent to implement the entire sync system from scratch with complete fidelity to the iOS implementation.

**Last Updated**: March 19, 2026
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

| Method | Signature | Description |
|--------|-----------|-------------|
| `fetchAll` | `(since: Date?) -> [SupabaseProjectDTO]` | Fetch all company projects, optionally since a date |
| `fetchOne` | `(_ id: String) -> SupabaseProjectDTO` | Fetch single project by ID |
| `create` | `(_ dto: SupabaseProjectDTO) -> SupabaseProjectDTO` | Insert, returns created record |
| `upsert` | `(_ dto: SupabaseProjectDTO)` | Upsert (insert or update on conflict) |
| `updateStatus` | `(_ projectId: String, status: String)` | Update status + updated_at |
| `updateNotes` | `(_ projectId: String, notes: String)` | Update notes + updated_at |
| `updateDates` | `(_ projectId: String, startDate: Date?, endDate: Date?)` | Update start/end dates |
| `updateAddress` | `(_ projectId: String, address: String)` | Update address |
| `updateTeamMembers` | `(_ projectId: String, memberIds: [String])` | Replace team_member_ids array |
| `updateFields` | `(_ projectId: String, fields: [String: AnyJSON])` | Generic field update |
| `softDelete` | `(_ projectId: String)` | Set deleted_at + updated_at |

### 2. TaskRepository

**Table**: `project_tasks`
**Init**: `TaskRepository(companyId:)`
**Column Notes**: `task_notes` (not `notes`), `custom_title` (not `title`), `task_color` (not `color`). Scheduling dates (`start_date`, `end_date`, `duration`) are stored directly on `project_tasks`.

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
2. **Coalesce**: Multiple update operations targeting the same `(entityType, entityId)` are merged -- changed fields are unioned, payload is replaced with the latest
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

### accounting-batch-create

Cron-triggered (daily at 00:00 UTC). Creates expense batches based on each company's `review_frequency`.

**Flow**: Query `expense_settings` → check if batch due → collect unbatched `submitted` expenses → create `expense_batch` → assign `batch_id` → calculate total → log.

**Optional env var**: `CRON_SECRET` for authenticated cron invocations.

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

### Inventory Tables

| Table | Purpose |
|-------|---------|
| `inventory_items` | Physical inventory items |
| `inventory_units` | Measurement units (ea, box, ft, etc.) |
| `inventory_tags` | Categorization tags |
| `inventory_item_tags` | Item-tag junction (many-to-many) |
| `inventory_snapshots` | Point-in-time inventory records |
| `inventory_snapshot_items` | Items captured in a snapshot |

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

**Behavior:** For each lead: resolves or creates client (with merge/link/subclient logic), creates opportunity with AI-detected stage, inserts `opportunity_email_threads` junction row, creates email activity record, applies "OPS Pipeline" label to the Gmail/M365 thread.

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

**Behavior:** If `connectionId` is provided, syncs that single connection. If `companyId`, syncs all active connections for that company. Each `SyncResult` contains `{ connectionId, activitiesCreated, newLeads }`.

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

### 7. POST /api/integrations/email/webhook/gmail

**Purpose:** Receives Gmail Pub/Sub push notifications and triggers sync.

| Field | Value |
|-------|-------|
| Auth | None (Gmail Pub/Sub sends unauthenticated; always returns 200) |
| Request body | Gmail Pub/Sub notification: `{ message: { data: base64({ emailAddress }) } }` |
| Response | `{ ok: true }` |
| Service calls | Internal fetch to `/api/integrations/email/manual-sync` (fire-and-forget) |

**Behavior:** Decodes the Pub/Sub payload to get the email address, looks up active connections for that email, debounces (skips if synced within last 30 seconds), then triggers manual-sync for each matching connection. Always returns 200 to avoid Pub/Sub retries.

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

**End of Document**

This completes the comprehensive API and Integration documentation for the OPS Software Bible. Any developer or AI agent should now have complete context to implement the entire Supabase-backed sync system, repository layer, realtime subscriptions, image handling, push notifications, email pipeline integration, and error management with full fidelity to the current implementation.
