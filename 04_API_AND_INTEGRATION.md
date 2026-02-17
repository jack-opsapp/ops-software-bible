# 04 - API AND INTEGRATION

**OPS Software Bible - Complete API and Integration Architecture**

**Purpose**: This document provides comprehensive documentation of the OPS backend integration, sync architecture, and network operations. It covers all API endpoints, sync strategies, conflict resolution, image handling, and integration patterns. This enables any developer or AI agent to implement the entire sync system from scratch with complete fidelity to the iOS implementation.

**Last Updated**: February 15, 2026
**iOS Reference**: C:\OPS\opsapp-ios\OPS\Network\
**Android Reference**: C:\OPS\opsapp-android\app\src\main\java\co\opsapp\ops\data\

---

## Table of Contents

1. [Backend Overview](#backend-overview)
2. [API Endpoints Catalog](#api-endpoints-catalog)
3. [Sync Architecture](#sync-architecture)
4. [CentralizedSyncManager](#centralizedsyncmanager)
5. [Image Upload & S3 Integration](#image-upload--s3-integration)
6. [Stripe Subscription Integration](#stripe-subscription-integration)
7. [Firebase Analytics](#firebase-analytics)
8. [Error Handling & Retry Logic](#error-handling--retry-logic)
9. [Connectivity Monitoring](#connectivity-monitoring)
10. [Rate Limiting & Debouncing](#rate-limiting--debouncing)

---

## Backend Overview

### Bubble.io REST API

OPS uses Bubble.io as the backend platform, providing a fully-managed REST API for all data operations.

**Base URL**: `https://opsapp.co/version-test/api/1.1/`

**Alternative URL** (legacy): `https://ops-app-36508.bubbleapps.io/version-test/api/1.1`

**Authentication**: Bearer token (API token-based, not user-based)
```
Authorization: Bearer f81e9da85b7a12e996ac53e970a52299
```

**API Token**: `f81e9da85b7a12e996ac53e970a52299` (hardcoded in AppConfiguration)

**Important**: Unlike typical REST APIs, Bubble does NOT require user-specific auth tokens. The API token is static and shared across all requests. User context is determined by passing user IDs in request parameters.

### API Architecture Types

Bubble provides two distinct API endpoint types:

#### 1. Data API (CRUD Operations)
**Pattern**: `/api/1.1/obj/{dataType}`

**Operations**:
- **GET**: Fetch records (with optional constraints, pagination, sorting)
- **POST**: Create new records
- **PATCH**: Update existing records (by ID)
- **DELETE**: Hard delete records (DEPRECATED - use workflow soft delete instead)

**Response Format**:
```json
{
  "response": {
    "cursor": 0,
    "results": [...],
    "remaining": 25,
    "count": 100
  }
}
```

#### 2. Workflow API (Custom Operations)
**Pattern**: `/api/1.1/wf/{workflowName}`

**Method**: POST only

**Use Cases**:
- Complex multi-step operations
- Batch updates
- Soft deletes with cascade logic
- Image registration
- Custom business logic

**Response Format**:
```json
{
  "response": {
    "status": "success",
    ...
  }
}
```

### Field Conditions & Rate Limiting

**Timeout**: 30 seconds (field workers may have poor connectivity)

**Rate Limiting**:
- Minimum 0.5 seconds between requests
- Automatic exponential backoff on failures
- Retry logic: 3 attempts with 2s, 4s delays

**Network Optimization**:
- HTTP/2 for better performance
- Connection pooling (max 5 per host)
- `waitsForConnectivity = true` (don't fail immediately on network loss)

---

## API Endpoints Catalog

### Project Endpoints

#### Fetch Company Projects (Admin/Office Crew)

**Endpoint**: `GET /api/1.1/obj/project`

**Query Parameters**:
```json
{
  "constraints": [
    {
      "key": "Company",
      "constraint_type": "equals",
      "value": "{companyId}"
    },
    {
      "key": "Deleted Date",
      "constraint_type": "is_empty"
    }
  ],
  "limit": 100,
  "cursor": 0
}
```

**Returns**: Array of ProjectDTO

**BubbleFields Mapping**:
- `Company` → `BubbleFields.Project.company`
- `Deleted Date` → `BubbleFields.Project.deletedDate`

#### Fetch User Projects (Field Crew)

**Endpoint**: `GET /api/1.1/obj/project`

**Query Parameters**:
```json
{
  "constraints": [
    {
      "key": "Team Members",
      "constraint_type": "contains",
      "value": "{userId}"
    },
    {
      "key": "Deleted Date",
      "constraint_type": "is_empty"
    }
  ]
}
```

**Note**: Field crew ONLY see projects where they're assigned as team members. This is critical for permission filtering.

#### Create Project

**Endpoint**: `POST /api/1.1/obj/project`

**Request Body**:
```json
{
  "Name": "Project Name",
  "Company": "{companyId}",
  "Client": "{clientId}",
  "Status": "RFQ",
  "Color": "#59779F",
  "Street Address": "123 Main St",
  "City": "Austin",
  "State": "TX",
  "Zip": "78701",
  "Lat": 30.2672,
  "Long": -97.7431,
  "Team Members": ["{userId1}", "{userId2}"],
  "Notes": "Project description"
}
```

**Response**:
```json
{
  "id": "{newProjectId}",
  "status": "success"
}
```

**BubbleFields Mapping**:
- `Name` → `BubbleFields.Project.name`
- `Company` → `BubbleFields.Project.company`
- `Client` → `BubbleFields.Project.client`
- `Status` → `BubbleFields.Project.status`
- `Color` → `BubbleFields.Project.color`
- `Street Address` → `BubbleFields.Project.streetAddress`
- `City` → `BubbleFields.Project.city`
- `State` → `BubbleFields.Project.state`
- `Zip` → `BubbleFields.Project.zip`
- `Lat` → `BubbleFields.Project.latitude`
- `Long` → `BubbleFields.Project.longitude`
- `Team Members` → `BubbleFields.Project.teamMembers`
- `Notes` → `BubbleFields.Project.notes`

#### Update Project

**Endpoint**: `PATCH /api/1.1/obj/project/{projectId}`

**Request Body**: Same fields as create (only include fields to update)

**Response**:
```json
{
  "status": "success"
}
```

**Note**: PATCH requests may return just `{"status": "success"}` without the full object. In this case, fetch the updated object with a GET request.

#### Update Project Status

**Endpoint**: `POST /api/1.1/wf/update_project_status`

**Request Body**:
```json
{
  "project_id": "{projectId}",
  "status": "In Progress"
}
```

**Status Values**:
- `RFQ` (Request for Quote)
- `Pending` (Quote sent, awaiting approval)
- `Accepted` (Quote accepted)
- `In Progress` (Active work)
- `Completed` (Work finished)
- `Cancelled` (Project cancelled)

#### Soft Delete Project

**Endpoint**: `POST /api/1.1/wf/delete_project`

**Request Body**:
```json
{
  "project_id": "{projectId}"
}
```

**Action**: Sets `deletedAt` field to current timestamp. Does NOT hard delete the record.

**Cascade Behavior**: Also soft-deletes all related tasks and calendar events.

---

### Task Endpoints

#### Fetch Company Tasks

**Endpoint**: `GET /api/1.1/obj/task`

**Query Parameters**:
```json
{
  "constraints": [
    {
      "key": "Project.Company",
      "constraint_type": "equals",
      "value": "{companyId}"
    },
    {
      "key": "Deleted Date",
      "constraint_type": "is_empty"
    }
  ]
}
```

**Note**: Uses nested relationship query `Project.Company` to fetch all tasks for a company.

#### Create Task

**Endpoint**: `POST /api/1.1/obj/task`

**Request Body**:
```json
{
  "Project": "{projectId}",
  "Title": "Task title",
  "Task Type": "{taskTypeId}",
  "Status": "Booked",
  "Task Index": 0,
  "Team Members": ["{userId1}"],
  "Calendar Event": "{calendarEventId}",
  "Notes": "Task notes"
}
```

**Critical**: Post-migration (Nov 2025), all tasks MUST have an associated CalendarEvent. The `Calendar Event` field is required, not optional.

**Status Values**:
- `Booked` (Scheduled but not started) ← RENAMED from "Scheduled" in Nov 2025
- `In Progress` (Active work)
- `Completed` (Finished)
- `Cancelled` (Cancelled)

**BubbleFields Mapping**:
- `Project` → `BubbleFields.Task.project`
- `Title` → `BubbleFields.Task.title`
- `Task Type` → `BubbleFields.Task.taskType`
- `Status` → `BubbleFields.Task.status`
- `Task Index` → `BubbleFields.Task.taskIndex`
- `Team Members` → `BubbleFields.Task.teamMembers`
- `Calendar Event` → `BubbleFields.Task.calendarEvent`
- `Notes` → `BubbleFields.Task.notes`

#### Update Task

**Endpoint**: `PATCH /api/1.1/obj/task/{taskId}`

**Request Body**: Fields to update

#### Update Task Status

**Endpoint**: `POST /api/1.1/wf/update_task_status`

**Request Body**:
```json
{
  "task_id": "{taskId}",
  "status": "In Progress"
}
```

#### Update Task Notes

**Endpoint**: `POST /api/1.1/wf/update_task_notes`

**Request Body**:
```json
{
  "task_id": "{taskId}",
  "notes": "Updated notes text"
}
```

---

### CalendarEvent Endpoints

#### Fetch Company Calendar Events

**Endpoint**: `GET /api/1.1/obj/calendarevent`

**Query Parameters**:
```json
{
  "constraints": [
    {
      "key": "Company",
      "constraint_type": "equals",
      "value": "{companyId}"
    },
    {
      "key": "Deleted Date",
      "constraint_type": "is_empty"
    },
    {
      "key": "Start Date",
      "constraint_type": "greater than",
      "value": "2025-01-01T00:00:00Z"
    }
  ]
}
```

**Date Filter**: Typically fetch events starting from current year to avoid loading historical data.

#### Create Calendar Event

**Endpoint**: `POST /api/1.1/obj/calendarevent`

**Request Body**:
```json
{
  "Company": "{companyId}",
  "Project": "{projectId}",
  "Task": "{taskId}",
  "Title": "Event title",
  "Start Date": "2025-11-18T09:00:00Z",
  "End Date": "2025-11-18T17:00:00Z",
  "Color": "#59779F"
}
```

**CRITICAL MIGRATION NOTE** (November 2025):
- All calendar events MUST have a `Task` field (taskId)
- The `eventType` field is REMOVED (no longer exists)
- The `active` field is REMOVED (no longer exists)
- The `type` field is REMOVED (no longer exists)
- Project-level events were deleted during migration

**BubbleFields Mapping**:
- `Company` → `BubbleFields.CalendarEvent.company`
- `Project` → `BubbleFields.CalendarEvent.project`
- `Task` → `BubbleFields.CalendarEvent.task`
- `Title` → `BubbleFields.CalendarEvent.title`
- `Start Date` → `BubbleFields.CalendarEvent.startDate`
- `End Date` → `BubbleFields.CalendarEvent.endDate`
- `Color` → `BubbleFields.CalendarEvent.color`

---

### Client Endpoints

#### Fetch Company Clients

**Endpoint**: `GET /api/1.1/obj/client`

**Query Parameters**:
```json
{
  "constraints": [
    {
      "key": "Company",
      "constraint_type": "equals",
      "value": "{companyId}"
    },
    {
      "key": "Deleted Date",
      "constraint_type": "is_empty"
    }
  ]
}
```

**Response**: Array of ClientDTO (includes embedded `subClients` array)

#### Create Client

**Endpoint**: `POST /api/1.1/obj/client`

**Request Body**:
```json
{
  "Company": "{companyId}",
  "Name": "Client Name",
  "Email": "client@example.com",
  "Phone Number": "512-555-1234",
  "Street Address": "123 Main St",
  "City": "Austin",
  "State": "TX",
  "Zip": "78701",
  "avatar": "https://s3.amazonaws.com/..."
}
```

#### Update Client Contact Info

**Endpoint**: `POST /api/1.1/wf/update_client_contact`

**Request Body**:
```json
{
  "client_id": "{clientId}",
  "email": "newemail@example.com",
  "phone": "512-555-5678"
}
```

#### Create Sub-Client

**Endpoint**: `POST /api/1.1/wf/create_subclient`

**Request Body**:
```json
{
  "client_id": "{clientId}",
  "name": "Sub-client Name",
  "email": "subcontact@example.com",
  "phone": "512-555-9999",
  "role": "Manager"
}
```

**Returns**:
```json
{
  "response": {
    "subClient": { ... }
  }
}
```

#### Edit Sub-Client

**Endpoint**: `POST /api/1.1/wf/edit_sub_client`

**Request Body**:
```json
{
  "subClient": "{subClientId}",
  "name": "Updated Name",
  "email": "updated@example.com",
  "phone": "512-555-8888",
  "title": "Senior Manager",
  "address": "New address"
}
```

#### Delete Sub-Client

**Endpoint**: `POST /api/1.1/wf/delete_sub_client`

**Request Body**:
```json
{
  "subClient": "{subClientId}"
}
```

---

### User Endpoints

#### Fetch Company Users

**Endpoint**: `GET /api/1.1/obj/user`

**Query Parameters**:
```json
{
  "constraints": [
    {
      "key": "Company",
      "constraint_type": "equals",
      "value": "{companyId}"
    },
    {
      "key": "Deleted Date",
      "constraint_type": "is_empty"
    }
  ]
}
```

#### Update User

**Endpoint**: `PATCH /api/1.1/obj/user/{userId}`

**Request Body**: Fields to update (e.g., `{"Employee Type": "Office Crew"}`)

#### Delete User

**Endpoint**: `POST /api/1.1/wf/delete_user`

**Request Body**:
```json
{
  "user": "{userId}"
}
```

#### Terminate Employee

**Endpoint**: `POST /api/1.1/wf/terminate_employee`

**Request Body**:
```json
{
  "user": "{userId}"
}
```

**Action**: Removes user from company, revokes access, soft deletes user record.

#### Role Assignment Logic (CRITICAL - Fixed Nov 3, 2025)

**Three-Tier Role Detection**:

1. **Check `company.adminIds` array** (highest priority)
   - If userId exists in company's `Admin Ids` array → role = `.admin`

2. **Check `employeeType` field** (medium priority)
   - Map Bubble value to app role:
     - `"Office Crew"` → `.officeCrew`
     - `"Field Crew"` → `.fieldCrew`
     - `"Admin"` → `.admin`

3. **Default to `.fieldCrew`** (lowest priority)
   - If no match found, default to field crew role

**BugFix Context**: Original implementation checked wrong values ("Office" instead of "Office Crew") and didn't check adminIds first, causing admin users to be downgraded to field crew, which then filtered their project access and caused data loss during sync.

**BubbleFields Mapping**:
- `Employee Type` → `BubbleFields.User.employeeType`
- Admin IDs checked via `company.adminIds` array

---

### Company Endpoints

#### Fetch Company

**Endpoint**: `GET /api/1.1/obj/company/{companyId}`

**Response**: CompanyDTO with all company fields

#### Update Company

**Endpoint**: `PATCH /api/1.1/obj/company/{companyId}`

**Request Body**:
```json
{
  "Company Name": "Updated Name",
  "Default Project Color": "#59779F",
  "logo": "https://s3.amazonaws.com/...",
  "seatedEmployees": ["{userId1}", "{userId2}"]
}
```

**Subscription Fields** (from Stripe plugin):
- `billingPeriodEnd` - Unix timestamp OR ISO8601 string
- `subscriptionEnd` - Unix timestamp OR ISO8601 string
- `trialStartDate` - Unix timestamp OR ISO8601 string
- `trialEndDate` - Unix timestamp OR ISO8601 string
- `seatGraceStartDate` - Unix timestamp OR ISO8601 string
- `seatGraceEndDate` - Unix timestamp OR ISO8601 string

**Date Parsing Note**: Bubble returns dates in MIXED formats:
- Stripe-synced fields: Unix timestamps (milliseconds)
- Bubble native fields: ISO8601 strings

Both formats MUST be supported in DTOs.

#### Update Company Seated Employees

**Endpoint**: `PATCH /api/1.1/obj/company/{companyId}`

**Request Body**:
```json
{
  "seatedEmployees": ["{userId1}", "{userId2}", "{userId3}"]
}
```

**Use Case**: Subscription seat management. Only seated employees count toward subscription limits.

---

### TaskType Endpoints

#### Fetch Company Task Types

**Endpoint**: `GET /api/1.1/obj/tasktype`

**Query Parameters**:
```json
{
  "constraints": [
    {
      "key": "Company",
      "constraint_type": "equals",
      "value": "{companyId}"
    },
    {
      "key": "Deleted Date",
      "constraint_type": "is_empty"
    }
  ]
}
```

#### Create Task Type

**Endpoint**: `POST /api/1.1/obj/tasktype`

**Request Body**:
```json
{
  "Company": "{companyId}",
  "Display": "Custom Task",
  "Color": "#FF5733",
  "Icon": "hammer.fill",
  "Is Default": false,
  "Display Order": 10
}
```

---

### Image Endpoints

#### Upload Project Images

**Endpoint**: `POST /api/1.1/wf/upload_project_images`

**Request Body**:
```json
{
  "project_id": "{projectId}",
  "images": [
    "https://s3.amazonaws.com/ops-app-files-prod/company-123/project-456/photos/image1.jpg",
    "https://s3.amazonaws.com/ops-app-files-prod/company-123/project-456/photos/image2.jpg"
  ]
}
```

**Process**:
1. Upload images to S3 first (using direct S3 API)
2. Register S3 URLs with Bubble using this endpoint
3. Bubble associates URLs with project

**Critical**: If S3 upload succeeds but Bubble fails, MUST clean up S3 (delete uploaded files) to avoid orphaned data.

---

## Sync Architecture

### Triple-Layer Sync Strategy

OPS uses a sophisticated three-tiered sync approach to balance responsiveness with reliability in field conditions.

#### Layer 1: Immediate Sync (User Actions)

**Trigger**: User makes a change (status update, notes edit, create/delete)

**Strategy**: Immediate API call if online

**Fallback**: Mark `needsSync = true` if offline

**Implementation Pattern**:
```swift
func updateProjectStatus(project: Project, newStatus: Status) async {
    // 1. Optimistic update (immediate UI feedback)
    project.status = newStatus
    try? modelContext.save()

    // 2. Immediate sync if online
    if isConnected {
        do {
            try await apiService.updateProjectStatus(
                projectId: project.id,
                status: newStatus.rawValue
            )
            project.needsSync = false
            project.lastSyncedAt = Date()
        } catch {
            print("[SYNC_ERROR] Failed to sync status: \(error)")
            project.needsSync = true  // Retry later in Layer 3
        }
    } else {
        project.needsSync = true  // Queue for sync when online
    }

    try? modelContext.save()
}
```

**User Experience**: Instant UI response regardless of network state. Changes appear immediately, sync happens in background.

#### Layer 2: Event-Driven Sync

**Triggers**:
- App launches (after successful authentication)
- Network connectivity restored (WiFi/Cellular comes online)
- App returns to foreground (from background state)
- Subscription status changes (subscription activated/cancelled)

**Strategy**: Sync critical data immediately

**Implementation**:
```swift
// In DataController.swift
func setupConnectivityMonitoring() {
    connectivityMonitor.onConnectionTypeChanged = { [weak self] connectionType in
        guard connectionType != .none else { return }

        // Ignore first callback (initialization - bugfix Nov 15, 2025)
        guard self?.hasHandledInitialConnection == true else {
            self?.hasHandledInitialConnection = true
            return
        }

        // Connection restored - trigger sync
        print("[CONNECTIVITY] Connection restored: \(connectionType)")
        Task { @MainActor in
            await self?.syncManager?.triggerBackgroundSync()
        }
    }
}
```

**App Launch Sync**:
```swift
func performAppLaunchSync() async {
    guard isAuthenticated, isConnected else { return }

    do {
        try await syncManager.syncAppLaunch()
        print("[SYNC_LAUNCH] ✅ App launch sync complete")
    } catch {
        print("[SYNC_LAUNCH] ❌ Sync failed: \(error)")
    }
}
```

#### Layer 3: Periodic Retry Sync

**Trigger**: Timer-based check every 3 minutes (180 seconds)

**Condition**: Only runs if pending syncs exist (`needsSync = true`)

**Strategy**: Sync items that failed in Layers 1 & 2

**Implementation**:
```swift
// Periodic timer in DataController
func startPeriodicSyncTimer() {
    syncTimer = Timer.scheduledTimer(
        withTimeInterval: 180,  // 3 minutes
        repeats: true
    ) { [weak self] _ in
        Task { @MainActor in
            await self?.checkPendingSyncs()
        }
    }
}

func checkPendingSyncs() async {
    guard isConnected else {
        print("[PERIODIC_SYNC] Skipping - offline")
        return
    }

    // Check for unsynced items across all entities
    let hasPendingProjects = try? modelContext.fetch(
        FetchDescriptor<Project>(
            predicate: #Predicate { $0.needsSync == true }
        )
    ).count ?? 0 > 0

    let hasPendingTasks = try? modelContext.fetch(
        FetchDescriptor<Task>(
            predicate: #Predicate { $0.needsSync == true }
        )
    ).count ?? 0 > 0

    if hasPendingProjects || hasPendingTasks {
        print("[PERIODIC_SYNC] Found pending syncs - triggering background sync")
        await syncManager?.triggerBackgroundSync()
    } else {
        print("[PERIODIC_SYNC] No pending syncs")
    }
}
```

### Conflict Resolution Strategy

**Philosophy**: "Server wins" - Remote data always takes precedence over local changes in conflicts.

**Process**:
1. **Push local changes first** (all `needsSync = true` items)
2. **Then fetch remote data** (pull from server)
3. **Server overwrites local** if conflicts exist
4. **Clear `needsSync` flag** on successful push

**Rationale**: Multi-user collaboration requires a single source of truth. Local changes are pushed, but if server data differs (e.g., another user updated), server version is authoritative.

**Implementation**:
```swift
func syncProjects() async throws {
    // STEP 1: Push local changes
    let unsyncedProjects = try modelContext.fetch(
        FetchDescriptor<Project>(
            predicate: #Predicate { $0.needsSync == true }
        )
    )

    for project in unsyncedProjects {
        do {
            try await pushProjectToServer(project)
            project.needsSync = false
            project.lastSyncedAt = Date()
        } catch {
            print("[SYNC] Failed to push project \(project.id): \(error)")
            // Keep needsSync = true for retry
        }
    }

    // STEP 2: Fetch remote data
    let remoteDTOs = try await apiService.fetchProjects(companyId: companyId)

    // STEP 3: Upsert (server wins)
    for dto in remoteDTOs {
        let project = getOrCreateProject(id: dto.id)
        // Overwrite ALL fields from server (server wins)
        project.name = dto.name
        project.status = dto.status
        project.lastSyncedAt = Date()
        project.needsSync = false  // In sync with server
    }

    try modelContext.save()
}
```

### Soft Delete Handling

**30-Day Window**: Items deleted within last 30 days are soft-deleted locally. Older items are preserved as historical data.

**Deletion Detection**: If item exists locally but NOT in remote response, it was likely deleted on server.

**Implementation**:
```swift
private func handleProjectDeletions(keepingIds: Set<String>) async throws {
    let allProjects = try? modelContext.fetch(FetchDescriptor<Project>())

    let now = Date()
    let thirtyDaysAgo = Calendar.current.date(byAdding: .day, value: -30, to: now)!

    for project in allProjects ?? [] {
        if !keepingIds.contains(project.id) {
            // Only soft delete if:
            // 1. Not already deleted
            // 2. Synced within last 30 days (recently active)
            // 3. Not a historical project (> 1 year old)

            if project.deletedAt == nil &&
               (project.lastSyncedAt ?? .distantPast) > thirtyDaysAgo {

                print("[DELETION] 🗑️ Soft deleting: \(project.name)")
                project.deletedAt = now

                // Cascade to related entities
                for task in project.tasks {
                    task.deletedAt = now
                }
                for event in project.calendarEvents {
                    event.deletedAt = now
                }
            }
        }
    }
}
```

**Cascade Behavior**:
- Deleting Project → deletes Tasks → deletes CalendarEvents
- Deleting Client → does NOT delete Projects (projects remain orphaned)
- Deleting User → does NOT delete assignments (user ID remains in arrays)

---

## CentralizedSyncManager

**Location**: `OPS/Network/Sync/CentralizedSyncManager.swift` (iOS)
**Size**: ~1,801 lines of code
**Purpose**: Single source of truth for ALL sync operations

### Master Sync Functions

#### 1. syncAll() - Manual Complete Sync

Called when user taps "Sync" button or performs pull-to-refresh.

**Syncs**: EVERYTHING in dependency order

**Implementation**:
```swift
@MainActor
func syncAll() async throws {
    guard !syncInProgress, isConnected else {
        throw SyncError.alreadySyncing
    }

    syncInProgress = true
    defer { syncInProgress = false }

    print("[SYNC_ALL] 🔄 Starting complete sync...")

    // Sync in dependency order (parents before children)
    try await syncCompany()         // 1. Company & subscription
    try await syncUsers()           // 2. Team members
    try await syncClients()         // 3. Clients
    try await syncTaskTypes()       // 4. Task type templates
    try await syncProjects()        // 5. Projects
    try await syncTasks()           // 6. Tasks (requires projects)
    try await syncCalendarEvents()  // 7. Calendar events (requires projects/tasks)

    lastSyncDate = Date()
    print("[SYNC_ALL] ✅ Complete sync finished")
}
```

**Dependency Order Critical**: Must sync parents before children to avoid foreign key errors.

#### 2. syncAppLaunch() - App Startup Sync

Called after successful authentication during app launch.

**Prioritization**:
- **Blocking**: Critical data (company, users, projects, calendar)
- **Background**: Less critical data (clients, task types, tasks)

**Implementation**:
```swift
@MainActor
func syncAppLaunch() async throws {
    guard !syncInProgress, isConnected else { return }

    syncInProgress = true
    defer { syncInProgress = false }

    print("[SYNC_LAUNCH] 🚀 Starting app launch sync...")

    // Critical data first (blocking UI)
    try await syncCompany()
    try await syncUsers()
    try await syncProjects()
    try await syncCalendarEvents()

    // Less critical data in background (non-blocking)
    Task.detached(priority: .background) {
        try? await self.syncClients()
        try? await self.syncTaskTypes()
        try? await self.syncTasks()
    }

    lastSyncDate = Date()
    print("[SYNC_LAUNCH] ✅ App launch sync finished")
}
```

**User Experience**: App becomes usable faster by deferring non-critical data to background.

#### 3. syncBackgroundRefresh() - Periodic Refresh

Called by timer or connectivity restoration.

**Optimization**: Only syncs data likely to have changed (with date filters)

**Implementation**:
```swift
@MainActor
func syncBackgroundRefresh() async throws {
    guard !syncInProgress, isConnected else { return }

    syncInProgress = true
    defer { syncInProgress = false }

    print("[SYNC_BG] 🔄 Background refresh...")

    // Only sync data likely to have changed (with date filter)
    try await syncProjects(sinceDate: lastSyncDate)
    try await syncTasks(sinceDate: lastSyncDate)
    try await syncCalendarEvents(sinceDate: lastSyncDate)

    lastSyncDate = Date()
    print("[SYNC_BG] ✅ Background refresh complete")
}
```

**Date Filtering**: Passes `Modified Date > lastSyncDate` constraint to Bubble API to only fetch changed records.

#### 4. triggerBackgroundSync() - Debounced Trigger

Public method with debouncing to prevent duplicate syncs.

**Critical**: 2-second minimum interval between syncs

**Implementation**:
```swift
func triggerBackgroundSync(forceProjectSync: Bool = false) {
    // Debounce: Don't trigger if sync occurred < 2 seconds ago
    if let lastTrigger = lastSyncTriggerTime,
       Date().timeIntervalSince(lastTrigger) < minimumSyncInterval {
        print("[TRIGGER_BG_SYNC] ⏭️ Skipping - sync triggered recently")
        return
    }

    lastSyncTriggerTime = Date()
    guard !syncInProgress, isConnected else { return }

    Task { @MainActor in
        if forceProjectSync {
            try? await syncAll()
        } else {
            try? await syncBackgroundRefresh()
        }
    }
}
```

**Debouncing** (Added Nov 15, 2025):
- Minimum 2-second interval between sync triggers
- Prevents duplicate syncs during app launch
- Fixes issue where connectivity monitor and app launch both triggered sync simultaneously

**Bug Context**: Before debouncing, app launch could trigger 2-4 concurrent syncs:
1. App launch → syncAppLaunch()
2. Connectivity monitor initialization → triggerBackgroundSync()
3. Connectivity state change → triggerBackgroundSync()
4. Foreground event → triggerBackgroundSync()

This caused 900+ records to sync instead of 296, wasting bandwidth and battery.

### Individual Entity Sync Functions

All entity sync functions follow this pattern:

```swift
@MainActor
func syncProjects() async throws {
    print("[SYNC_PROJECTS] Starting...")

    // 1. Fetch from Bubble API
    let projectDTOs = try await apiService.fetchProjects(companyId: companyId)
    print("[SYNC_PROJECTS] Fetched \(projectDTOs.count) projects")

    // 2. Handle soft deletions
    let remoteIds = Set(projectDTOs.map { $0.id })
    try await handleProjectDeletions(keepingIds: remoteIds)

    // 3. Upsert each project (update or insert)
    for dto in projectDTOs {
        let project = getOrCreateProject(id: dto.id)

        // Update all properties from DTO
        project.name = dto.name
        project.status = dto.status
        project.color = dto.color
        project.address = dto.streetAddress
        project.city = dto.city
        project.state = dto.state
        project.zip = dto.zip
        project.latitude = dto.latitude
        project.longitude = dto.longitude
        project.notes = dto.notes
        project.clientId = dto.clientId

        // Parse and set deleted date
        if let deletedDateStr = dto.deletedAt {
            project.deletedAt = parseDate(deletedDateStr)
        }

        // Mark as synced
        project.needsSync = false
        project.lastSyncedAt = Date()
    }

    // 4. Save to local database
    try modelContext.save()

    print("[SYNC_PROJECTS] ✅ Synced \(projectDTOs.count) projects")
}
```

**getOrCreateProject() Pattern**:
```swift
private func getOrCreateProject(id: String) -> Project {
    // Try to fetch existing
    let descriptor = FetchDescriptor<Project>(
        predicate: #Predicate { $0.id == id }
    )

    if let existing = try? modelContext.fetch(descriptor).first {
        return existing
    }

    // Create new if not found
    let newProject = Project(id: id)
    modelContext.insert(newProject)
    return newProject
}
```

### Sync State Management

**Properties**:
```swift
private(set) var syncInProgress = false
private var lastSyncDate: Date?
private var lastSyncTriggerTime: Date?
private let minimumSyncInterval: TimeInterval = 2.0  // 2 seconds

// Published for UI observation
let syncStateSubject = PassthroughSubject<Bool, Never>()
```

**State Publishing**:
```swift
private(set) var syncInProgress = false {
    didSet {
        syncStateSubject.send(syncInProgress)
    }
}
```

**UI Observation**:
```swift
// In SwiftUI view
.onReceive(syncManager.syncStateSubject) { isSyncing in
    if isSyncing {
        // Show loading indicator
    } else {
        // Hide loading indicator
    }
}
```

### Debug Logging System

**Master Killswitch**:
```swift
static var debugLoggingEnabled: Bool = true
```

**Per-Function Flags**:
```swift
struct DebugFlags {
    static var syncAll: Bool = true
    static var syncCompany: Bool = true
    static var syncUsers: Bool = true
    static var syncClients: Bool = true
    static var syncTaskTypes: Bool = true
    static var syncProjects: Bool = true
    static var syncTasks: Bool = true
    static var syncCalendarEvents: Bool = true
    static var updateOperations: Bool = true
    static var deleteOperations: Bool = true
    static var modelConversion: Bool = true
}
```

**Debug Helper**:
```swift
private func debugLog(_ message: String, function: String = #function, enabled: Bool = true) {
    guard CentralizedSyncManager.debugLoggingEnabled && enabled else { return }
    print("[SYNC_DEBUG] [\(function)] \(message)")
}
```

**Usage**:
```swift
debugLog("Fetched \(dtos.count) projects", enabled: DebugFlags.syncProjects)
```

---

## Image Upload & S3 Integration

### Multi-Tier Image Architecture

**Storage Tiers**:
1. **AWS S3** - Primary remote storage (permanent)
2. **Local File System** - Offline cache and pending uploads
3. **Memory Cache** - Fast re-display during session
4. **UserDefaults** - Legacy (migrated to file system)

### S3 Configuration

**Bucket**: `ops-app-files-prod`
**Region**: `us-west-2`
**Path Pattern**: `company-{companyId}/{projectId}/photos/{filename}`

**Credentials**: Stored in `Secrets.xcconfig` (NOT committed to Git)
- `AWS_ACCESS_KEY_ID`
- `AWS_SECRET_ACCESS_KEY`
- `AWS_S3_BUCKET`
- `AWS_REGION`

**Authentication**: AWS Signature Version 4 (SigV4)

### Image Flow

#### 1. Capture/Select Images

```swift
// User selects up to 10 images
ImagePicker(selectedImages: $selectedImages, limit: 10)

// Process and compress
for (index, image) in selectedImages.enumerated() {
    let resizedImage = resizeImageIfNeeded(image)
    let quality = getAdaptiveCompressionQuality(for: resizedImage)
    let imageData = resizedImage.jpegData(compressionQuality: quality)
    // ... upload or save locally
}
```

**Image Constraints**:
- Maximum 10 images per upload
- Maximum dimension: 2048px (resized if larger)
- Format: JPEG only
- Adaptive compression: 0.5 - 0.8 quality based on resolution

#### 2. Filename Generation

**Pattern**: `{StreetAddress}_IMG_{timestamp}_{index}.jpg`

**Example**: `123MainSt_IMG_20251118_143022_0.jpg`

**Implementation**:
```swift
func generateFilename(project: Project, timestamp: Date, index: Int) -> String {
    let streetPrefix = extractStreetAddress(from: project.address ?? "")

    let formatter = DateFormatter()
    formatter.dateFormat = "yyyyMMdd_HHmmss"
    let dateStr = formatter.string(from: timestamp)

    return "\(streetPrefix)_IMG_\(dateStr)_\(index).jpg"
}

private func extractStreetAddress(from address: String) -> String {
    // Remove commas and get first part
    let streetPart = address.components(separatedBy: ",").first ?? ""

    // Remove spaces, periods, special chars
    var cleaned = streetPart
        .replacingOccurrences(of: " ", with: "")
        .replacingOccurrences(of: ".", with: "")
        .replacingOccurrences(of: ",", with: "")

    // Default if empty
    if cleaned.isEmpty {
        cleaned = "NoAddress"
    }

    return cleaned
}
```

#### 3. Upload Decision

**Online**: Upload to S3 → Register with Bubble
**Offline**: Save locally → Queue for later sync

```swift
func saveImages(project: Project, images: [UIImage]) async {
    if isConnected {
        // Online: Upload to S3
        await uploadToS3(project: project, images: images)
    } else {
        // Offline: Save locally with local:// prefix
        await saveLocally(project: project, images: images)
    }
}
```

#### 4A. Online Upload to S3

**Process**:
1. Compress image to JPEG (adaptive quality)
2. Generate unique filename
3. Generate AWS v4 signature
4. PUT request to S3
5. Register S3 URL with Bubble
6. Update project in local database

**Implementation**:
```swift
func uploadToS3(project: Project, images: [UIImage]) async {
    for (index, image) in images.enumerated() {
        // 1. Compress image
        let resizedImage = resizeImageIfNeeded(image)
        let quality = getAdaptiveCompressionQuality(for: resizedImage)
        guard let imageData = resizedImage.jpegData(compressionQuality: quality) else {
            continue
        }

        // 2. Generate filename
        let filename = generateFilename(project: project, index: index)

        // 3. Upload to S3
        let objectKey = "company-\(companyId)/\(project.id)/photos/\(filename)"
        let s3URL = try await uploadImageToS3(
            imageData: imageData,
            objectKey: objectKey
        )

        // 4. Register with Bubble
        try await apiService.addProjectImage(
            projectId: project.id,
            imageURL: s3URL
        )

        // 5. Update project
        project.addImage(s3URL)
        project.needsSync = false
    }

    try? modelContext.save()
}

private func uploadImageToS3(imageData: Data, objectKey: String) async throws -> String {
    let endpoint = "https://\(bucketName).s3.\(region).amazonaws.com/\(objectKey)"

    var request = URLRequest(url: URL(string: endpoint)!)
    request.httpMethod = "PUT"
    request.httpBody = imageData
    request.setValue("image/jpeg", forHTTPHeaderField: "Content-Type")

    // Add AWS authentication headers (SigV4)
    addAWSAuthHeaders(to: &request, method: "PUT", path: "/\(objectKey)", payload: imageData)

    let (_, response) = try await URLSession.shared.data(for: request)

    guard let httpResponse = response as? HTTPURLResponse,
          (200...299).contains(httpResponse.statusCode) else {
        throw S3Error.uploadFailed
    }

    return endpoint
}
```

**AWS Signature v4**:
```swift
private func addAWSAuthHeaders(to request: inout URLRequest, method: String, path: String, payload: Data? = nil) {
    let dateFormatter = DateFormatter()
    dateFormatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
    dateFormatter.timeZone = TimeZone(identifier: "UTC")
    let dateTime = dateFormatter.string(from: Date())
    let dateStamp = String(dateTime.prefix(8))

    // Canonical request
    let canonicalHeaders = "host:\(bucketName).s3.\(region).amazonaws.com\nx-amz-date:\(dateTime)\n"
    let signedHeaders = "host;x-amz-date"
    let payloadHash = payload?.sha256Hash() ?? "UNSIGNED-PAYLOAD"

    let canonicalRequest = """
    \(method)
    \(path)

    \(canonicalHeaders)
    \(signedHeaders)
    \(payloadHash)
    """

    // String to sign
    let algorithm = "AWS4-HMAC-SHA256"
    let credentialScope = "\(dateStamp)/\(region)/s3/aws4_request"
    let canonicalRequestHash = canonicalRequest.sha256Hash()

    let stringToSign = """
    \(algorithm)
    \(dateTime)
    \(credentialScope)
    \(canonicalRequestHash)
    """

    // Calculate signature
    let signature = calculateSignature(
        stringToSign: stringToSign,
        dateStamp: dateStamp,
        region: region,
        service: "s3"
    )

    // Authorization header
    let authorization = "\(algorithm) Credential=\(accessKeyId)/\(credentialScope), SignedHeaders=\(signedHeaders), Signature=\(signature)"

    request.setValue(authorization, forHTTPHeaderField: "Authorization")
    request.setValue(dateTime, forHTTPHeaderField: "X-Amz-Date")
    request.setValue(payloadHash, forHTTPHeaderField: "X-Amz-Content-SHA256")
}
```

#### 4B. Offline Save Locally

**Process**:
1. Compress image to JPEG
2. Generate unique filename
3. Save to `Documents/ProjectImages/` directory
4. Create local URL with `local://` prefix
5. Add to pending uploads queue
6. Update project with local URL

**Implementation**:
```swift
private func saveImageLocally(_ image: UIImage, for project: Project, index: Int) async -> String? {
    let resizedImage = resizeImageIfNeeded(image)
    let quality = getAdaptiveCompressionQuality(for: resizedImage)

    guard let imageData = resizedImage.jpegData(compressionQuality: quality) else {
        return nil
    }

    let timestamp = Date().timeIntervalSince1970
    let filename = "local_project_\(project.id)_\(timestamp)_\(index).jpg"
    let localURL = "local://project_images/\(filename)"

    // Store in file system
    let success = ImageFileManager.shared.saveImage(data: imageData, localID: localURL)

    if success {
        // Create pending upload
        let pendingUpload = PendingImageUpload(
            localURL: localURL,
            projectId: project.id,
            companyId: project.companyId,
            timestamp: Date()
        )

        pendingUploads.append(pendingUpload)
        savePendingUploads()

        // Mark as unsynced
        project.addUnsyncedImage(localURL)

        return localURL
    }

    return nil
}
```

**File Manager**:
```swift
class ImageFileManager {
    static let shared = ImageFileManager()

    private let documentsDirectory = FileManager.default.urls(
        for: .documentDirectory,
        in: .userDomainMask
    ).first!

    func saveImage(data: Data, localID: String) -> Bool {
        let filename = extractFilename(from: localID)
        let imageDir = documentsDirectory.appendingPathComponent("ProjectImages")

        // Create directory if needed
        try? FileManager.default.createDirectory(at: imageDir, withIntermediateDirectories: true)

        let fileURL = imageDir.appendingPathComponent(filename)

        do {
            try data.write(to: fileURL)
            return true
        } catch {
            print("[FILE_MANAGER] Failed to save image: \(error)")
            return false
        }
    }

    func getImageData(localID: String) -> Data? {
        let filename = extractFilename(from: localID)
        let fileURL = documentsDirectory
            .appendingPathComponent("ProjectImages")
            .appendingPathComponent(filename)

        return try? Data(contentsOf: fileURL)
    }
}
```

#### 5. Background Sync (Offline → Online)

**Trigger**: Connectivity restored or periodic timer

**Process**:
1. Load pending uploads from UserDefaults
2. Group by project ID
3. Upload each image to S3
4. Register batch with Bubble
5. Replace local URLs with S3 URLs in project
6. Remove from pending queue

**Implementation**:
```swift
func syncPendingImages() async {
    guard !isSyncing, connectivityMonitor.isConnected else { return }

    isSyncing = true
    defer { isSyncing = false }

    let pending = loadPendingUploads()
    let grouped = Dictionary(grouping: pending, by: { $0.projectId })

    for (projectId, uploads) in grouped {
        await syncImagesForProject(projectId: projectId, uploads: uploads)
    }
}

private func syncImagesForProject(projectId: String, uploads: [PendingImageUpload]) async {
    guard let project = getProject(by: projectId) else { return }

    var uploadedURLs: [String] = []

    // Upload each image to S3
    for upload in uploads {
        if let imageData = ImageFileManager.shared.getImageData(localID: upload.localURL) {
            do {
                let s3URL = try await uploadImageToS3(
                    imageData: imageData,
                    objectKey: generateObjectKey(upload)
                )
                uploadedURLs.append(s3URL)
            } catch {
                print("[IMAGE_SYNC] Failed to upload: \(error)")
            }
        }
    }

    // Register all with Bubble
    if !uploadedURLs.isEmpty {
        do {
            try await apiService.addProjectImages(
                projectId: projectId,
                imageURLs: uploadedURLs
            )

            // Update project: replace local URLs with S3 URLs
            var currentImages = project.getProjectImages()
            for (local, s3) in zip(uploads.map { $0.localURL }, uploadedURLs) {
                if let index = currentImages.firstIndex(of: local) {
                    currentImages[index] = s3
                }
                project.markImageAsSynced(local)
            }
            project.setProjectImageURLs(currentImages)
            project.needsSync = false

            // Remove from pending queue
            pendingUploads.removeAll { upload in
                uploads.contains { $0.localURL == upload.localURL }
            }
            savePendingUploads()

            try? modelContext.save()
        } catch {
            print("[IMAGE_SYNC] Failed to register with Bubble: \(error)")
        }
    }
}
```

### Image Fetching (Display)

**Multi-tier cache check**:

```swift
func loadImage(url: String) async -> UIImage? {
    // 1. Check memory cache (fastest)
    if let cached = imageCache.get(url) {
        return cached
    }

    // 2. Check file system (local:// URLs)
    if url.hasPrefix("local://") {
        if let image = loadFromFileSystem(url) {
            imageCache.set(url, image)
            return image
        }
    }

    // 3. Check file system (cached remote URLs)
    if let image = loadCachedRemoteImage(url) {
        imageCache.set(url, image)
        return image
    }

    // 4. Download from network
    if let image = try? await downloadImage(url) {
        saveToFileSystem(url, image)
        imageCache.set(url, image)
        return image
    }

    return nil
}
```

### Image Deletion

**Process**:
1. Delete from S3 (if S3 URL)
2. Delete from Bubble (via API)
3. Delete from local cache
4. Remove from project

**Implementation**:
```swift
func deleteImage(_ urlString: String, from project: Project) async -> Bool {
    // Check if local URL
    if urlString.starts(with: "local://") {
        _ = ImageFileManager.shared.deleteImage(localID: urlString)
        pendingUploads.removeAll { $0.localURL == urlString }
        savePendingUploads()
        return true
    }

    // Delete from S3
    if urlString.contains("s3") && urlString.contains("amazonaws.com") {
        do {
            try await s3Service.deleteImageFromS3(
                url: urlString,
                companyId: project.companyId,
                projectId: project.id
            )
            _ = ImageFileManager.shared.deleteImage(localID: urlString)
            return true
        } catch {
            return false
        }
    }

    return false
}

// In S3UploadService
func deleteImageFromS3(url: String, companyId: String, projectId: String) async throws {
    guard let urlComponents = URL(string: url) else {
        throw S3Error.invalidURL
    }

    // Extract object key from URL
    let objectKey = String(urlComponents.path.dropFirst())

    let endpoint = "https://\(bucketName).s3.\(region).amazonaws.com/\(objectKey)"

    var request = URLRequest(url: URL(string: endpoint)!)
    request.httpMethod = "DELETE"

    // Add AWS auth headers
    addAWSAuthHeaders(to: &request, method: "DELETE", path: "/\(objectKey)")

    let (_, response) = try await URLSession.shared.data(for: request)

    guard let httpResponse = response as? HTTPURLResponse,
          (200...299).contains(httpResponse.statusCode) else {
        throw S3Error.deleteFailed
    }
}
```

### Image Processing Utilities

#### Resize Image If Needed
```swift
private func resizeImageIfNeeded(_ image: UIImage) -> UIImage {
    let maxDimension: CGFloat = 2048

    guard image.size.width > maxDimension || image.size.height > maxDimension else {
        return image
    }

    let aspectRatio = image.size.width / image.size.height
    let newSize: CGSize

    if image.size.width > image.size.height {
        newSize = CGSize(width: maxDimension, height: maxDimension / aspectRatio)
    } else {
        newSize = CGSize(width: maxDimension * aspectRatio, height: maxDimension)
    }

    UIGraphicsBeginImageContextWithOptions(newSize, false, 1.0)
    image.draw(in: CGRect(origin: .zero, size: newSize))
    let resizedImage = UIGraphicsGetImageFromCurrentImageContext() ?? image
    UIGraphicsEndImageContext()

    return resizedImage
}
```

#### Adaptive Compression Quality
```swift
private func getAdaptiveCompressionQuality(for image: UIImage) -> CGFloat {
    let pixelCount = image.size.width * image.size.height

    if pixelCount > 4_000_000 { // > 4MP
        return 0.5
    } else if pixelCount > 2_000_000 { // > 2MP
        return 0.6
    } else if pixelCount > 1_000_000 { // > 1MP
        return 0.7
    } else {
        return 0.8
    }
}
```

---

## Stripe Subscription Integration

### Architecture

OPS uses Bubble's Stripe plugin to handle subscriptions. All subscription data is managed by Bubble, and the app reads subscription status via the Company entity.

**Stripe Integration**: Server-side via Bubble Stripe plugin
**App Role**: Read-only subscription status consumer

### Subscription Fields (in CompanyDTO)

**Date Fields** (MIXED FORMAT WARNING):
- `billingPeriodEnd` - Unix timestamp OR ISO8601 string
- `subscriptionEnd` - Unix timestamp OR ISO8601 string
- `trialStartDate` - Unix timestamp OR ISO8601 string
- `trialEndDate` - Unix timestamp OR ISO8601 string
- `seatGraceStartDate` - Unix timestamp OR ISO8601 string
- `seatGraceEndDate` - Unix timestamp OR ISO8601 string

**String Fields**:
- `subscriptionStatus` - "active", "trialing", "past_due", "cancelled", etc.
- `stripePlanId` - Stripe plan identifier

**Array Fields**:
- `seatedEmployees` - Array of user IDs who have active seats

**Integer Fields**:
- `maxSeats` - Maximum seats allowed by plan

### Date Parsing (CRITICAL)

Bubble returns dates in TWO formats:
1. **Stripe-synced fields**: Unix timestamps (milliseconds since epoch)
2. **Bubble native fields**: ISO8601 strings

**Both formats MUST be supported**:

```swift
struct CompanyDTO: Codable {
    let billingPeriodEnd: FlexibleDate?
    let trialEndDate: FlexibleDate?

    // FlexibleDate handles both formats
    enum FlexibleDate: Codable {
        case timestamp(Double)  // Unix timestamp (milliseconds)
        case string(String)     // ISO8601 string

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()

            if let timestamp = try? container.decode(Double.self) {
                self = .timestamp(timestamp)
            } else if let string = try? container.decode(String.self) {
                self = .string(string)
            } else {
                throw DecodingError.typeMismatch(
                    FlexibleDate.self,
                    DecodingError.Context(
                        codingPath: decoder.codingPath,
                        debugDescription: "Expected Double or String"
                    )
                )
            }
        }

        func toDate() -> Date? {
            switch self {
            case .timestamp(let value):
                return Date(timeIntervalSince1970: value / 1000.0)  // Convert ms to seconds
            case .string(let value):
                let formatter = ISO8601DateFormatter()
                return formatter.date(from: value)
            }
        }
    }
}
```

### Subscription Status Logic

**Trial Check**:
```swift
var isInTrial: Bool {
    guard let trialEnd = company.trialEndDate?.toDate() else {
        return false
    }
    return Date() < trialEnd
}
```

**Active Subscription Check**:
```swift
var hasActiveSubscription: Bool {
    // Check trial first
    if isInTrial {
        return true
    }

    // Check subscription status
    if company.subscriptionStatus == "active" ||
       company.subscriptionStatus == "trialing" {
        return true
    }

    // Check billing period end
    if let billingEnd = company.billingPeriodEnd?.toDate(),
       Date() < billingEnd {
        return true
    }

    return false
}
```

**Seat Management**:
```swift
var availableSeats: Int {
    let maxSeats = company.maxSeats ?? 0
    let seatedCount = company.seatedEmployees?.count ?? 0
    return max(0, maxSeats - seatedCount)
}

var isOverSeatedLimit: Bool {
    let maxSeats = company.maxSeats ?? 0
    let seatedCount = company.seatedEmployees?.count ?? 0
    return seatedCount > maxSeats
}
```

### Updating Seated Employees

**Endpoint**: `PATCH /api/1.1/obj/company/{companyId}`

**Process**:
```swift
func updateSeatedEmployees(userIds: [String]) async throws {
    let fields: [String: Any] = [
        "seatedEmployees": userIds
    ]

    try await apiService.updateCompanyFields(
        companyId: companyId,
        fields: fields
    )

    // Fetch updated company
    let updatedCompany = try await apiService.fetchCompany(id: companyId)

    // Update local company
    company.seatedEmployees = updatedCompany.seatedEmployees
    try? modelContext.save()
}
```

---

## Firebase Analytics

OPS uses Firebase Analytics to track user behavior and conversion events for Google Ads.

**SDK Version**: 12.6.0+
**Project ID**: `ops-ios-app`
**Bundle ID**: `co.opsapp.ops.OPS`
**Config File**: `GoogleService-Info.plist`

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

**Screen Names**:
- Main tabs: `home`, `job_board`, `schedule`, `settings`
- Job Board: `job_board_dashboard`, `job_board_projects`, `job_board_tasks`, `job_board_clients`
- Details: `project_details`, `task_details`, `client_details`
- Forms: `project_form`, `task_form`, `client_form`

#### Engagement Events

| Event | Parameters | Description |
|-------|------------|-------------|
| `navigation_started` | `project_id` | User starts navigation |
| `search_performed` | `section`, `results_count` | Search executed |
| `image_uploaded` | `image_count`, `context` | Photo uploaded |

### Implementation

**AnalyticsManager** (Singleton):
```swift
class AnalyticsManager {
    static let shared = AnalyticsManager()

    func trackScreenView(screenName: ScreenName, screenClass: String) {
        let parameters: [String: Any] = [
            "screen_name": screenName.rawValue,
            "screen_class": screenClass
        ]
        Analytics.logEvent(AnalyticsEventScreenView, parameters: parameters)
        print("[ANALYTICS] Tracked screen_view - screen: \(screenName.rawValue)")
    }

    func trackProjectCreated(projectCount: Int, userType: String) {
        let parameters: [String: Any] = [
            "project_count": projectCount,
            "user_type": userType
        ]
        Analytics.logEvent("create_project", parameters: parameters)

        // Track first project separately (high-value conversion)
        if projectCount == 1 {
            Analytics.logEvent("create_first_project", parameters: ["user_type": userType])
        }
    }
}
```

**Usage**:
```swift
// In view
.onAppear {
    AnalyticsManager.shared.trackScreenView(
        screenName: .projectDetails,
        screenClass: "ProjectDetailsView"
    )
}

// In action
func createProject() {
    // ... create project logic

    let projectCount = projects.count
    AnalyticsManager.shared.trackProjectCreated(
        projectCount: projectCount,
        userType: currentUser.type.rawValue
    )
}
```

### Google Ads Conversion Events

These events are automatically sent to Google Ads:
1. `sign_up` - Primary acquisition conversion
2. `purchase` - Revenue conversion
3. `create_first_project` - High-intent engagement
4. `complete_onboarding` - Onboarding completion
5. `task_completed` - Productivity signal

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

enum APIError: Error {
    case invalidURL
    case invalidResponse
    case httpError(statusCode: Int)
    case rateLimited
    case unauthorized
    case serverError
    case networkError
    case decodingFailed
}

enum S3Error: LocalizedError {
    case uploadFailed
    case deleteFailed
    case invalidURL
    case bubbleAPIFailed
    case imageConversionFailed
}
```

### Retry with Exponential Backoff

```swift
func syncWithRetry<T>(
    operation: () async throws -> T,
    maxRetries: Int = 3
) async throws -> T {
    var lastError: Error?

    for attempt in 1...maxRetries {
        do {
            return try await operation()
        } catch {
            lastError = error
            print("[SYNC] ⚠️ Attempt \(attempt) failed: \(error)")

            if attempt < maxRetries {
                // Exponential backoff: 2^attempt seconds
                let delay = UInt64(pow(2.0, Double(attempt)) * 1_000_000_000)
                try await Task.sleep(nanoseconds: delay)
            }
        }
    }

    throw lastError ?? SyncError.apiError(NSError(domain: "Unknown", code: -1))
}
```

**Retry Schedule**:
- Attempt 1: Immediate
- Attempt 2: 2 seconds delay
- Attempt 3: 4 seconds delay
- Give up: Throw error, mark `needsSync = true`

### Error Handling Pattern

```swift
func updateProject(_ project: Project) async {
    do {
        try await syncWithRetry {
            try await apiService.updateProject(
                projectId: project.id,
                fields: [
                    "Name": project.name,
                    "Status": project.status
                ]
            )
        }

        // Success
        project.needsSync = false
        project.lastSyncedAt = Date()

    } catch {
        // Failure - mark for retry
        print("[ERROR] Failed to update project: \(error)")
        project.needsSync = true

        // Show user-friendly error
        if let apiError = error as? APIError {
            switch apiError {
            case .unauthorized:
                showError("Your session has expired. Please log in again.")
            case .networkError:
                showError("No internet connection. Changes will sync when online.")
            case .serverError:
                showError("Server error. We'll try again automatically.")
            default:
                showError("Update failed. Changes will sync automatically.")
            }
        }
    }

    try? modelContext.save()
}
```

---

## Connectivity Monitoring

**Location**: `OPS/Network/ConnectivityMonitor.swift`

**Purpose**: Track network availability for offline-first operations

### Implementation

```swift
class ConnectivityMonitor {
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "NetworkMonitor")

    static let connectivityChangedNotification = Notification.Name("ConnectivityMonitorDidChangeConnectivity")

    private(set) var isConnected = false
    private(set) var connectionType: ConnectionType = .none

    var onConnectionTypeChanged: ((ConnectionType) -> Void)?

    enum ConnectionType {
        case none
        case wifi
        case cellular
        case wiredEthernet
    }

    init() {
        setupMonitor()
    }

    private func setupMonitor() {
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self = self else { return }

            self.isConnected = path.status == .satisfied

            let newConnectionType: ConnectionType
            if path.usesInterfaceType(.wifi) {
                newConnectionType = .wifi
            } else if path.usesInterfaceType(.cellular) {
                newConnectionType = .cellular
            } else if path.usesInterfaceType(.wiredEthernet) {
                newConnectionType = .wiredEthernet
            } else {
                newConnectionType = .none
            }

            // Only notify if connection type changed
            if self.connectionType != newConnectionType {
                self.connectionType = newConnectionType

                DispatchQueue.main.async {
                    self.onConnectionTypeChanged?(newConnectionType)

                    NotificationCenter.default.post(
                        name: ConnectivityMonitor.connectivityChangedNotification,
                        object: self,
                        userInfo: ["connectionType": newConnectionType]
                    )
                }
            }
        }

        monitor.start(queue: queue)
    }
}
```

### Usage

```swift
// In DataController
func setupConnectivityMonitoring() {
    connectivityMonitor.onConnectionTypeChanged = { [weak self] connectionType in
        print("[CONNECTIVITY] Type changed: \(connectionType)")

        guard connectionType != .none else { return }

        // Ignore first callback (initialization)
        guard self?.hasHandledInitialConnection == true else {
            self?.hasHandledInitialConnection = true
            return
        }

        // Connection restored - trigger sync
        Task { @MainActor in
            await self?.syncManager?.triggerBackgroundSync()
        }
    }
}
```

---

## Rate Limiting & Debouncing

### API Rate Limiting

**Minimum Request Interval**: 0.5 seconds

**Implementation**:
```swift
class APIService {
    private var lastRequestTime: Date?
    private let minRequestInterval: TimeInterval = 0.5

    func executeRequest<T: Decodable>(...) async throws -> T {
        // Rate limiting
        if let lastRequest = lastRequestTime {
            let elapsed = Date().timeIntervalSince(lastRequest)
            if elapsed < minRequestInterval {
                let delayTime = UInt64((minRequestInterval - elapsed) * 1_000_000_000)
                try await Task.sleep(nanoseconds: delayTime)
            }
        }
        lastRequestTime = Date()

        // ... execute request
    }
}
```

### Sync Debouncing

**Minimum Sync Interval**: 2 seconds

**Purpose**: Prevent duplicate syncs during app launch

**Implementation**:
```swift
class CentralizedSyncManager {
    private var lastSyncTriggerTime: Date?
    private let minimumSyncInterval: TimeInterval = 2.0

    func triggerBackgroundSync(forceProjectSync: Bool = false) {
        // Debounce check
        if let lastTrigger = lastSyncTriggerTime,
           Date().timeIntervalSince(lastTrigger) < minimumSyncInterval {
            print("[TRIGGER_BG_SYNC] ⏭️ Skipping - sync triggered recently")
            return
        }

        lastSyncTriggerTime = Date()
        guard !syncInProgress, isConnected else { return }

        Task { @MainActor in
            if forceProjectSync {
                try? await syncAll()
            } else {
                try? await syncBackgroundRefresh()
            }
        }
    }
}
```

**Bug Context**: Before debouncing (Nov 15, 2025), app launch could trigger 2-4 concurrent syncs:
1. App launch → syncAppLaunch()
2. Connectivity monitor init → triggerBackgroundSync()
3. Connectivity state change → triggerBackgroundSync()
4. Foreground event → triggerBackgroundSync()

Result: 900+ records synced instead of 296 (3x unnecessary bandwidth).

---

## Sync Timing Summary

| Trigger | Function | When | Data Synced | Debounced |
|---------|----------|------|-------------|-----------|
| **Manual Sync** | `syncAll()` | User taps sync button | Everything | No |
| **App Launch** | `syncAppLaunch()` | After authentication | Critical data first, rest in background | No |
| **Network Restored** | `triggerBackgroundSync()` | Connection detected | Changed data only | Yes (2s) |
| **Periodic Retry** | Timer + `checkPendingSyncs()` | Every 3 min if pending | Items with `needsSync=true` | No |
| **User Action** | Individual update API | Immediate on change | Single item | No |

---

## Critical Implementation Notes

### BubbleFields Constants
**Byte-Identical Requirement**: Field names MUST match Bubble exactly (case-sensitive, spacing, etc.)

**Example**:
```swift
struct BubbleFields {
    struct Project {
        static let teamMembers = "Team Members"  // NOT "team_members" or "teamMembers"
        static let streetAddress = "Street Address"  // NOT "street_address"
        static let deletedDate = "Deleted Date"  // NOT "deletedAt"
    }
}
```

### Status Migration (November 2025)
- **Old**: "Scheduled"
- **New**: "Booked"
- **DTOs**: Must handle both for backward compatibility
- **TODO**: Update Bubble to use "Booked" consistently

### CalendarEvent Migration (November 2025)
- All events MUST have `taskId`
- No more `eventType`, `active`, or `type` fields
- Project-level events were deleted

### Project Team Members
**Computed from Task Assignments**: NOT from Bubble's legacy `Team Members` field

**Correct Logic**:
```swift
var projectTeamMembers: [String] {
    let taskMembers = tasks.flatMap { $0.teamMemberIds }
    return Array(Set(taskMembers))  // Unique IDs
}
```

### AWS Credentials
**Never Commit**: S3 credentials in `Secrets.xcconfig` MUST NOT be committed to Git

**Template**:
```
// Secrets.xcconfig.template
AWS_ACCESS_KEY_ID = your_access_key_here
AWS_SECRET_ACCESS_KEY = your_secret_key_here
AWS_S3_BUCKET = ops-app-files-prod
AWS_REGION = us-west-2
```

---

## Android Implementation Considerations

### Kotlin Equivalents

**Swift Async/Await** → **Kotlin Coroutines**:
```kotlin
// Swift
func syncAll() async throws { ... }

// Kotlin
suspend fun syncAll() { ... }
```

**Swift Combine** → **Kotlin Flow**:
```kotlin
// Swift
let syncStateSubject = PassthroughSubject<Bool, Never>()

// Kotlin
private val _syncInProgress = MutableStateFlow(false)
val syncInProgress: StateFlow<Bool> = _syncInProgress.asStateFlow()
```

**SwiftData** → **Room**:
```kotlin
// Swift
@Model class Project { ... }

// Kotlin
@Entity(tableName = "projects")
data class Project( ... )
```

### Retrofit for API Service

**BubbleApiService.kt**:
```kotlin
interface BubbleApiService {
    @GET("api/1.1/obj/project")
    suspend fun fetchProjects(
        @Query("constraints") constraints: String,
        @Query("limit") limit: Int = 100
    ): BubbleListResponse<ProjectDTO>

    @POST("api/1.1/obj/project")
    suspend fun createProject(@Body project: ProjectDTO): BubbleObjectResponse<ProjectDTO>

    @PATCH("api/1.1/obj/project/{id}")
    suspend fun updateProject(
        @Path("id") id: String,
        @Body fields: Map<String, Any>
    ): BubbleObjectResponse<ProjectDTO>
}
```

### OkHttp Interceptors

**AuthInterceptor** (for API token):
```kotlin
class AuthInterceptor : Interceptor {
    override fun intercept(chain: Interceptor.Chain): Response {
        val request = chain.request().newBuilder()
            .addHeader("Authorization", "Bearer ${AppConfiguration.BUBBLE_API_TOKEN}")
            .build()
        return chain.proceed(request)
    }
}
```

**RateLimitInterceptor** (0.5s minimum):
```kotlin
class RateLimitInterceptor : Interceptor {
    private var lastRequestTime: Long = 0
    private val minInterval = 500L // milliseconds

    override fun intercept(chain: Interceptor.Chain): Response {
        val now = System.currentTimeMillis()
        val elapsed = now - lastRequestTime

        if (elapsed < minInterval) {
            Thread.sleep(minInterval - elapsed)
        }

        lastRequestTime = System.currentTimeMillis()
        return chain.proceed(chain.request())
    }
}
```

### WorkManager for Background Sync

**SyncWorker.kt**:
```kotlin
class SyncWorker(
    context: Context,
    params: WorkerParameters
) : CoroutineWorker(context, params) {

    override suspend fun doWork(): Result {
        return try {
            val syncManager = CentralizedSyncManager.getInstance(applicationContext)
            syncManager.syncBackgroundRefresh()
            Result.success()
        } catch (e: Exception) {
            if (runAttemptCount < 3) {
                Result.retry()
            } else {
                Result.failure()
            }
        }
    }
}
```

**Periodic Sync Setup**:
```kotlin
val syncRequest = PeriodicWorkRequestBuilder<SyncWorker>(
    repeatInterval = 3,
    repeatIntervalTimeUnit = TimeUnit.MINUTES
).setConstraints(
    Constraints.Builder()
        .setRequiredNetworkType(NetworkType.CONNECTED)
        .build()
).build()

WorkManager.getInstance(context).enqueueUniquePeriodicWork(
    "periodic_sync",
    ExistingPeriodicWorkPolicy.KEEP,
    syncRequest
)
```

---

**End of Document**

This completes the comprehensive API and Integration documentation for the OPS Software Bible. Any developer or AI agent should now have complete context to implement the entire sync system, API integration, image handling, and error management with full fidelity to the iOS implementation.
