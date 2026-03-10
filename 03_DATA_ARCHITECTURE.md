# 03: Data Architecture

**Last Updated**: March 2, 2026
**Status**: Comprehensive Reference
**Purpose**: Complete data layer specification for OPS iOS/Android applications

---

## Table of Contents

1. [Overview](#overview)
2. [SwiftData Models (24 Registered Entities)](#swiftdata-models-24-registered-entities)
3. [Inventory Models (5 Entities -- File-Only, Not in Schema)](#inventory-models-5-entities----file-only-not-in-schema)
4. [Enums Reference](#enums-reference)
5. [Relationship Map](#relationship-map)
6. [BubbleFields Constants (Legacy/Deprecated)](#bubblefields-constants-legacydeprecated)
7. [Data Transfer Objects (DTOs)](#data-transfer-objects-dtos)
8. [Supabase DTOs](#supabase-dtos)
9. [Soft Delete Strategy](#soft-delete-strategy)
10. [Computed Properties & Business Logic](#computed-properties--business-logic)
11. [Migration History](#migration-history)
12. [Query Predicates & Filtering](#query-predicates--filtering)
13. [Defensive Programming Patterns](#defensive-programming-patterns)

---

## Overview

### Data Layer Architecture

The OPS data layer follows a **three-tier architecture**:

1. **SwiftData Models**: Persistent entities stored locally (iOS: SwiftData, Android: Room)
2. **DTOs (Data Transfer Objects)**: API response mapping layer (both Bubble legacy and Supabase)
3. **Supabase Backend**: PostgreSQL database accessed via Supabase DTOs with snake_case column mapping

### Core Principles

- **Soft Delete**: Most entities support `deletedAt: Date?` for reversible deletion
- **Offline-First**: All data persists locally with sync tracking (`needsSync`, `lastSyncedAt`)
- **Type Safety**: DTOs handle field name mapping and type conversion
- **Task-Based Scheduling**: Project dates are computed from task start/end dates (CalendarEvent entity has been removed)

### The 25 Registered Schema Models

As defined in `OPSApp.swift` Schema:

**Core Entities (11):**
1. **User** -- Team member with role-based permissions
2. **Project** -- Central entity for field crew work
3. **Company** -- Organization/subscription management
4. **TeamMember** -- Lightweight user cache (company-scoped)
5. **Client** -- Customer/client management
6. **SubClient** -- Additional client contacts
7. **ProjectTask** -- Task-based scheduling within projects
8. **TaskType** -- Reusable task templates per company
9. **TaskStatusOption** -- Company-customizable task status colors
10. **SyncOperation** -- Queued offline sync operations
11. **OpsContact** -- OPS support contact information

**Supabase-Backed Entities (14):**
12. **Opportunity** -- Pipeline deal/lead
13. **Activity** -- Timeline event per opportunity
14. **FollowUp** -- Scheduled reminder
15. **StageTransition** -- Immutable stage history record
16. **Estimate** -- Quote document
17. **EstimateLineItem** -- Line item on an estimate
18. **Invoice** -- Billing document
19. **InvoiceLineItem** -- Line item on an invoice
20. **Payment** -- Payment record (insert-only)
21. **Product** -- Service/product catalog item
22. **SiteVisit** -- Scope assessment visit
23. **ProjectNote** -- Per-project message board note
24. **PhotoAnnotation** -- Drawing overlay and text note for project photos
25. **CalendarUserEvent** -- User-owned personal events and time-off requests

**Not Registered in Schema (exist as files only):**
- InventoryItem, InventorySnapshot, InventorySnapshotItem, InventoryTag, InventoryUnit (5 models)

---

## SwiftData Models (25 Registered Entities)

### 1. Project

**File**: `DataModels/Project.swift`
**Purpose**: Central entity representing a construction/trade project.

**Properties**:

```swift
@Model
final class Project: Identifiable {
    var id: String
    var title: String
    var address: String?
    var latitude: Double?
    var longitude: Double?
    var startDate: Date?
    var endDate: Date?
    var duration: Int?
    var status: Status
    var notes: String?
    var companyId: String
    var clientId: String?
    var opportunityId: String?       // Supabase Opportunity UUID
    var allDay: Bool
    var projectDescription: String?
    var projectImagesString: String = ""
    var unsyncedImagesString: String = ""
    var teamMemberIdsString: String = ""

    // Relationships
    @Relationship(deleteRule: .nullify) var client: Client?
    @Relationship(deleteRule: .noAction) var teamMembers: [User]
    @Relationship(deleteRule: .cascade, inverse: \ProjectTask.project) var tasks: [ProjectTask] = []

    // Sync
    var lastSyncedAt: Date?
    var needsSync: Bool = false
    var syncPriority: Int = 1
    var deletedAt: Date?

    // Transient
    @Transient var lastTapped: Date?
    @Transient var coordinatorData: [String: Any]?
}
```

**Key Computed Properties**:

```swift
var computedStartDate: Date? { tasks.compactMap { $0.startDate }.min() }
var computedEndDate: Date? { tasks.compactMap { $0.endDate }.max() }
var effectiveClientName: String { client?.name ?? "" }
var effectiveClientEmail: String? { ... }   // Cascades to sub-clients
var effectiveClientPhone: String? { ... }   // Cascades to sub-clients
var coordinate: CLLocationCoordinate2D? { ... }  // Validates ranges, rejects 0,0
var computedStatus: Status { ... }          // Derives from task statuses
var hasTasks: Bool { !tasks.isEmpty }
var effectiveEndDate: Date? { ... }         // Falls back to duration
var isMultiDay: Bool { ... }
var daySpan: Int { ... }
var spannedDates: [Date] { ... }
```

**Array Accessors**: `getTeamMemberIds()`, `setTeamMemberIds(_:)`, `getProjectImageURLs()`, `setProjectImageURLs(_:)`, `getUnsyncedImages()`, `addUnsyncedImage(_:)`, `markImageAsSynced(_:)`, `clearUnsyncedImages()`

**Key Methods**: `updateTeamMembersFromTasks(in:)` -- collects unique team member IDs from all tasks and updates project.

---

### 2. ProjectTask

**File**: `DataModels/ProjectTask.swift`
**Purpose**: Task within a project. Scheduling dates are stored directly on the task (CalendarEvent has been removed).

**Properties**:

```swift
@Model
final class ProjectTask {
    var id: String
    var projectId: String
    var companyId: String
    var status: TaskStatus               // .active, .completed, .cancelled
    var taskColor: String                // Hex color code
    var taskNotes: String?
    var taskTypeId: String
    var taskIndex: Int?
    var displayOrder: Int = 0
    var customTitle: String?
    var sourceLineItemId: String?        // Supabase LineItem UUID
    var sourceEstimateId: String?        // Supabase Estimate UUID

    // Scheduling (merged from former CalendarEvent)
    var startDate: Date?
    var endDate: Date?
    var duration: Int = 1

    var teamMemberIdsString: String = ""

    // Relationships
    @Relationship(deleteRule: .nullify) var project: Project?
    @Relationship(deleteRule: .nullify) var taskType: TaskType?
    @Relationship(deleteRule: .noAction) var teamMembers: [User] = []

    // Sync
    var lastSyncedAt: Date?
    var needsSync: Bool = false
    var deletedAt: Date?
}
```

**TaskStatus Enum** (defined in ProjectTask.swift):

```swift
enum TaskStatus: String, Codable, CaseIterable {
    case active = "active"
    case completed = "completed"
    case cancelled = "cancelled"

    // Custom decoder handles legacy values:
    // "Scheduled", "Booked", "booked", "In Progress", "in_progress" -> .active
    // "Completed" -> .completed
    // "Cancelled" -> .cancelled
}
```

**Key Computed Properties**:

```swift
var displayTitle: String { customTitle ?? taskType?.display ?? "Task" }
var effectiveColor: String { taskType?.color ?? taskColor }
var scheduledDate: Date? { startDate }
var completionDate: Date? { endDate }
var isOverdue: Bool { ... }
var isToday: Bool { ... }
var isMultiDay: Bool { ... }
var spannedDates: [Date] { ... }
var swiftUIColor: Color { Color(hex: effectiveColor) }
var displayIcon: String? { taskType?.icon }
```

---

### 3. TaskType

**File**: `DataModels/TaskType.swift`
**Purpose**: Reusable task templates with visual identity.

**Properties**:

```swift
@Model
final class TaskType: Identifiable {
    var id: String
    var color: String                        // Hex color code
    var display: String                      // Display name (e.g., "Installation")
    var icon: String?                        // SF Symbol name
    var isDefault: Bool
    var companyId: String
    var displayOrder: Int = 0
    var defaultTeamMemberIdsString: String = "" // Default crew user IDs

    @Relationship(deleteRule: .nullify, inverse: \ProjectTask.taskType)
    var tasks: [ProjectTask] = []

    var lastSyncedAt: Date?
    var needsSync: Bool = false
    var deletedAt: Date?
}
```

**NOTE**: The display property is `display`, NOT `name`.

**Default Task Types**: Site Estimate, Quote/Proposal, Material Order, Installation, Inspection, Completion.

---

### 4. Client

**File**: `DataModels/Client.swift`
**Purpose**: Customer/client management with sub-client support.

**Properties**:

```swift
@Model
final class Client: Identifiable {
    var id: String
    var name: String
    var email: String?                       // Property is `email`, NOT `emailAddress`
    var phoneNumber: String?
    var address: String?
    var latitude: Double?
    var longitude: Double?
    var profileImageURL: String?
    var notes: String?
    var companyId: String?

    @Relationship(deleteRule: .noAction, inverse: \Project.client)
    var projects: [Project]
    @Relationship(deleteRule: .cascade)
    var subClients: [SubClient]

    var lastSyncedAt: Date?
    var needsSync: Bool = false
    var createdAt: Date?
    var deletedAt: Date?
}
```

**NOTE**: The email property is `email`, NOT `emailAddress`.

---

### 5. SubClient

**File**: `DataModels/SubClient.swift`
**Purpose**: Additional contacts for a client.

**Properties**:

```swift
@Model
final class SubClient: Identifiable {
    var id: String
    var name: String
    var title: String?
    var email: String?
    var phoneNumber: String?
    var address: String?
    var client: Client?

    var createdAt: Date
    var updatedAt: Date
    var lastSyncedAt: Date?
    var needsSync: Bool = false
    var deletedAt: Date?
}
```

---

### 6. User

**File**: `DataModels/User.swift`
**Purpose**: Team member with role-based permissions.

**Properties**:

```swift
@Model
final class User {
    var id: String
    var firstName: String                    // Property is `firstName`, NOT `nameFirst`
    var lastName: String                     // Property is `lastName`, NOT `nameLast`
    var email: String?
    var phone: String?
    var profileImageURL: String?
    var profileImageData: Data?
    var role: UserRole                       // .admin, .officeCrew, .fieldCrew
    var companyId: String?
    var userType: UserType?                  // .employee, .company
    var latitude: Double?
    var longitude: Double?
    var locationName: String?
    var homeAddress: String?
    var clientId: String?
    var isActive: Bool?
    var userColor: String?
    var devPermission: Bool = false
    var hasCompletedAppOnboarding: Bool = false
    var hasCompletedAppTutorial: Bool = false
    var isCompanyAdmin: Bool = false
    var inventoryAccess: Bool = false
    var specialPermissions: [String] = []    // Beta feature flags (e.g. "pipeline")
    var stripeCustomerId: String?
    var deviceToken: String?

    @Relationship(deleteRule: .noAction, inverse: \Project.teamMembers)
    var assignedProjects: [Project]

    var lastSyncedAt: Date?
    var needsSync: Bool = false
    var deletedAt: Date?
}
```

**NOTE**: Properties are `firstName`/`lastName`, NOT `nameFirst`/`nameLast` (those are Bubble field names, not model properties).

**PERMISSION SYSTEM (March 2026)**: The legacy fields `role`, `isCompanyAdmin`, `inventoryAccess`, `specialPermissions`, and `devPermission` on the User model are being superseded by a proper RBAC+ABAC permissions system stored in Supabase (see [Permissions System Tables](#permissions-system-tables) below). The new system uses three dedicated tables (`roles`, `role_permissions`, `user_roles`) with 5 preset roles and ~55 granular permissions. The legacy fields remain on the User model for backward compatibility during the transition but are no longer the source of truth for access control. UI gating should use the `PermissionStore` (web) or equivalent iOS permission service, not these fields.

---

### 7. Company

**File**: `DataModels/Company.swift`
**Purpose**: Organization entity managing subscription and defaults.

**Properties**:

```swift
@Model
final class Company {
    var id: String
    var name: String
    var logoURL: String?
    var logoData: Data?
    var externalId: String?
    var companyDescription: String?
    var address: String?
    var phone: String?
    var email: String?
    var website: String?
    var latitude: Double?
    var longitude: Double?
    var openHour: String?
    var closeHour: String?
    var industryString: String = ""
    var companySize: String?
    var companyAge: String?
    var referralMethod: String?
    var projectIdsString: String = ""
    var teamIdsString: String = ""
    var adminIdsString: String = ""
    var accountHolderId: String?
    var defaultProjectColor: String = "#9CA3AF"
    var teamMembersSynced: Bool = false

    // Subscription
    var subscriptionStatus: String?          // "trial", "active", "grace", "expired", "cancelled"
    var subscriptionPlan: String?            // "trial", "starter", "team", "business"
    var subscriptionEnd: Date?
    var subscriptionPeriod: String?          // "Monthly", "Annual"
    var maxSeats: Int = 10
    var seatedEmployeeIds: String = ""
    var seatGraceStartDate: Date?
    var subscriptionIdsJson: String?
    var trialStartDate: Date?
    var trialEndDate: Date?
    var hasPrioritySupport: Bool = false
    var dataSetupPurchased: Bool = false
    var dataSetupCompleted: Bool = false
    var dataSetupScheduledDate: Date?
    var stripeCustomerId: String?

    // Relationships
    @Relationship(deleteRule: .cascade) var teamMembers: [TeamMember] = []
    @Relationship(deleteRule: .cascade) var taskTypes: [TaskType] = []
    @Relationship(deleteRule: .cascade) var inventoryUnits: [InventoryUnit] = []

    // Sync
    var lastSyncedAt: Date?
    var needsSync: Bool = false
    var deletedAt: Date?
}
```

---

### 8. TeamMember

**File**: `DataModels/TeamMember.swift`
**Purpose**: Lightweight team member cache (reduces need for full User fetches).

**Properties**:

```swift
@Model
final class TeamMember {
    var id: String
    var firstName: String
    var lastName: String
    var role: String                         // Role as plain String (not enum)
    var avatarURL: String?
    var email: String?
    var phone: String?
    var lastUpdated: Date

    @Relationship(deleteRule: .cascade, inverse: \Company.teamMembers)
    var company: Company?
}
```

**Factory Method**: `static func fromUser(_ user: User) -> TeamMember`

---

### 9. TaskStatusOption

**File**: `DataModels/TaskStatusOption.swift`
**Purpose**: Company-customizable display colors for task statuses.

**Properties**:

```swift
@Model
final class TaskStatusOption {
    var id: String
    var display: String
    var color: String
    var index: Int
    var companyId: String

    var lastSyncedAt: Date?
    var needsSync: Bool = false
}
```

Extends `TaskStatus` with `func color(from options: [TaskStatusOption]) -> Color` to look up custom colors.

---

### 10. SyncOperation

**File**: `DataModels/SyncOperation.swift`
**Purpose**: Queued sync operations for offline-first outbound sync.

**Properties**:

```swift
@Model
final class SyncOperation {
    var id: UUID
    var entityType: String
    var entityId: String
    var operationType: String
    var payload: Data
    var changedFields: String                // Comma-separated
    var createdAt: Date
    var retryCount: Int = 0
    var status: String = "pending"           // "pending", "inProgress", "failed", "completed"
    var lastError: String?
}
```

**Computed**: `isPending`, `isInProgress`, `isFailed`, `isCompleted`, `canRetry` (retryCount < 5).

---

### 11. OpsContact

**File**: `DataModels/OpsContact.swift`
**Purpose**: OPS support contact information.

**Properties**:

```swift
@Model
final class OpsContact {
    var id: String
    var email: String
    var name: String
    var phone: String
    var display: String
    var role: String                         // "jack", "priority support", etc.
    var lastSynced: Date
}
```

**OpsContactRole Enum**: `.jack`, `.prioritySupport`, `.dataSetup`, `.generalSupport`, `.webAppAutoSend`

---

### 12. Opportunity (Supabase-Backed)

**File**: `DataModels/Supabase/Opportunity.swift`
**Purpose**: Pipeline deal/lead.

**Properties**:

```swift
@Model
class Opportunity: Identifiable {
    @Attribute(.unique) var id: String
    var companyId: String
    var contactName: String
    var contactEmail: String?
    var contactPhone: String?
    var jobDescription: String?
    var estimatedValue: Double?
    var stage: PipelineStage
    var source: String?
    var projectId: String?
    var clientId: String?
    var lossReason: String?
    var createdAt: Date
    var updatedAt: Date
    var lastActivityAt: Date?
}
```

**Computed**: `weightedValue`, `daysInStage`, `isStale`.

---

### 13. Activity (Supabase-Backed)

**File**: `DataModels/Supabase/Activity.swift`
**Purpose**: Timeline event per opportunity.

**Properties**:

```swift
@Model
class Activity: Identifiable {
    @Attribute(.unique) var id: String
    var opportunityId: String
    var companyId: String
    var type: ActivityType
    var body: String?
    var createdBy: String?
    var createdAt: Date
    var metadata: String?
}
```

---

### 14. FollowUp (Supabase-Backed)

**File**: `DataModels/Supabase/FollowUp.swift`
**Purpose**: Scheduled reminder.

**Properties**:

```swift
@Model
class FollowUp: Identifiable {
    @Attribute(.unique) var id: String
    var opportunityId: String
    var companyId: String
    var type: FollowUpType
    var status: FollowUpStatus
    var dueAt: Date
    var assignedTo: String?
    var notes: String?
    var createdAt: Date
}
```

**Computed**: `isOverdue`, `isDueToday`.

---

### 15. StageTransition (Supabase-Backed)

**File**: `DataModels/Supabase/StageTransition.swift`
**Purpose**: Immutable stage history record.

**Properties**:

```swift
@Model
class StageTransition: Identifiable {
    @Attribute(.unique) var id: String
    var opportunityId: String
    var fromStage: PipelineStage
    var toStage: PipelineStage
    var changedBy: String?
    var createdAt: Date
}
```

---

### 16. Estimate (Supabase-Backed)

**File**: `DataModels/Supabase/Estimate.swift`
**Purpose**: Quote document.

**Properties**:

```swift
@Model
class Estimate: Identifiable {
    @Attribute(.unique) var id: String
    var companyId: String
    var estimateNumber: String
    var status: EstimateStatus
    var clientId: String?
    var projectId: String?
    var opportunityId: String?
    var title: String?
    var clientMessage: String?
    var internalNotes: String?
    var taxRate: Double
    var discountPercent: Double
    var subtotal: Double
    var taxAmount: Double
    var total: Double
    var validUntil: Date?
    var sentAt: Date?
    var version: Int
    var parentId: String?
    var createdAt: Date
    var updatedAt: Date
}
```

---

### 17. EstimateLineItem (Supabase-Backed)

**File**: `DataModels/Supabase/EstimateLineItem.swift`
**Purpose**: Line item on an estimate.

**Properties**:

```swift
@Model
class EstimateLineItem: Identifiable {
    @Attribute(.unique) var id: String
    var estimateId: String
    var productId: String?
    var name: String
    var itemDescription: String?
    var type: LineItemType
    var quantity: Double
    var unit: String?
    var unitPrice: Double
    var discountPercent: Double
    var taxable: Bool
    var optional: Bool
    var lineTotal: Double
    var displayOrder: Int
    var taskTypeId: String?
    var createdAt: Date
}
```

---

### 18. Invoice (Supabase-Backed)

**File**: `DataModels/Supabase/Invoice.swift`
**Purpose**: Billing document.

**Properties**:

```swift
@Model
class Invoice: Identifiable {
    @Attribute(.unique) var id: String
    var companyId: String
    var invoiceNumber: String
    var status: InvoiceStatus
    var clientId: String?
    var projectId: String?
    var opportunityId: String?
    var estimateId: String?
    var title: String?
    var subtotal: Double
    var taxAmount: Double
    var total: Double
    var amountPaid: Double
    var balanceDue: Double
    var taxRate: Double
    var dueDate: Date?
    var sentAt: Date?
    var paidAt: Date?
    var createdAt: Date
    var updatedAt: Date
}
```

**Computed**: `isOverdue` -- checks `balanceDue > 0 && due < Date() && status != .void`.

---

### 19. InvoiceLineItem (Supabase-Backed)

**File**: `DataModels/Supabase/InvoiceLineItem.swift`
**Purpose**: Line item on an invoice.

**Properties**:

```swift
@Model
class InvoiceLineItem: Identifiable {
    @Attribute(.unique) var id: String
    var invoiceId: String
    var name: String
    var itemDescription: String?
    var type: LineItemType
    var quantity: Double
    var unit: String?
    var unitPrice: Double
    var lineTotal: Double
    var displayOrder: Int
    var createdAt: Date
}
```

---

### 20. Payment (Supabase-Backed)

**File**: `DataModels/Supabase/Payment.swift`
**Purpose**: Payment record (insert-only).

**Properties**:

```swift
@Model
class Payment: Identifiable {
    @Attribute(.unique) var id: String
    var invoiceId: String
    var companyId: String
    var amount: Double
    var method: PaymentMethod
    var paidAt: Date
    var notes: String?
    var voidedAt: Date?
    var voidedBy: String?
    var createdAt: Date
}
```

**Computed**: `isVoided` -- `voidedAt != nil`.

---

### 21. Product (Supabase-Backed)

**File**: `DataModels/Supabase/Product.swift`
**Purpose**: Service/product catalog item.

**Properties**:

```swift
@Model
class Product: Identifiable {
    @Attribute(.unique) var id: String
    var companyId: String
    var name: String
    var productDescription: String?
    var type: LineItemType
    var defaultPrice: Double
    var unitCost: Double?
    var unit: String?
    var taxable: Bool
    var isActive: Bool
    var taskTypeId: String?
    var createdAt: Date
}
```

**Computed**: `marginPercent` -- `((defaultPrice - cost) / defaultPrice) * 100`.

---

### 22. SiteVisit (Supabase-Backed)

**File**: `DataModels/Supabase/SiteVisit.swift`
**Purpose**: Scope assessment visit.

**Properties**:

```swift
@Model
class SiteVisit: Identifiable {
    @Attribute(.unique) var id: String
    var opportunityId: String
    var companyId: String
    var status: SiteVisitStatus
    var scheduledAt: Date?
    var completedAt: Date?
    var notes: String?
    var address: String?
    var assignedTo: String?
    var createdAt: Date
}
```

---

### 23. ProjectNote (Supabase-Backed)

**File**: `DataModels/Supabase/ProjectNote.swift`
**Purpose**: Per-project message board note with @mentions and attachments.

**Properties**:

```swift
@Model
class ProjectNote: Identifiable {
    @Attribute(.unique) var id: String
    var projectId: String
    var companyId: String
    var authorId: String
    var content: String
    var attachmentsJSON: String              // JSON array of URL strings
    var mentionedUserIdsString: String       // Comma-separated user IDs
    var createdAt: Date
    var updatedAt: Date?
    var deletedAt: Date?

    var lastSyncedAt: Date?
    var needsSync: Bool = false
}
```

**Computed Accessors**: `mentionedUserIds: [String]` (get/set), `attachments: [String]` (get/set via JSON).

---

### 24. PhotoAnnotation (Supabase-Backed)

**File**: `DataModels/Supabase/PhotoAnnotation.swift`
**Purpose**: Drawing overlay and text note for a project photo.

**Properties**:

```swift
@Model
class PhotoAnnotation: Identifiable {
    @Attribute(.unique) var id: String
    var projectId: String
    var companyId: String
    var photoURL: String
    var annotationURL: String?
    var note: String
    var authorId: String
    var createdAt: Date
    var updatedAt: Date?
    var deletedAt: Date?

    var lastSyncedAt: Date?
    var needsSync: Bool = false
    var localDrawingData: Data?              // PKDrawing data for offline editing
}
```

---

### 25. CalendarUserEvent (Supabase-Backed)

**File**: `DataModels/Supabase/CalendarUserEvent.swift`
**Purpose**: User-owned calendar events — personal events (birthdays, appointments) and time-off requests requiring admin approval. Separate from project-linked CalendarEvents.

**Properties**:

```swift
@Model
class CalendarUserEvent: Identifiable {
    @Attribute(.unique) var id: String
    var userId: String
    var companyId: String
    var type: String                 // CalendarUserEventType.rawValue: "personal" | "time_off"
    var title: String
    var startDate: Date
    var endDate: Date
    var allDay: Bool
    var notes: String?
    var status: String               // CalendarUserEventStatus.rawValue: "confirmed" | "pending" | "approved" | "rejected"
    var reviewedBy: String?          // User ID of admin who reviewed time-off request
    var reviewedAt: Date?
    var createdAt: Date
    var updatedAt: Date?
    var deletedAt: Date?

    var lastSyncedAt: Date?
    var needsSync: Bool = false
}
```

**Supporting Enums**:
```swift
enum CalendarUserEventType: String, Codable {
    case personal = "personal"
    case timeOff = "time_off"
}

enum CalendarUserEventStatus: String, Codable {
    case confirmed = "confirmed"   // No approval needed (personal events)
    case pending = "pending"       // Time-off awaiting admin review
    case approved = "approved"
    case rejected = "rejected"
}
```

**Key Computed Properties**:
- `eventType: CalendarUserEventType` — typed accessor for `type` string
- `eventStatus: CalendarUserEventStatus` — typed accessor for `status` string
- `isTimeOff: Bool`, `isPersonal: Bool`, `isPending: Bool`
- `overlaps(date:) -> Bool` — used by calendar views to show events on relevant days

**Business Rules**:
- Personal events: `status` is set to `.confirmed`, no approval workflow
- Time-off requests: created as `.pending`, admin approves (`.approved`) or rejects (`.rejected`)
- Only the owning user (`userId`) can create/edit their own events
- Admin can review (approve/deny) time-off requests from any user in their company
- Soft-delete via `deletedAt` (consistent with all Supabase-backed models)

**Supabase Table**: `calendar_user_events`

**RLS Note**: The `calendar_user_events` table uses `CAST(auth.uid() AS TEXT)` in its RLS policies because `users.id` is a UUID type while `calendar_user_events.user_id` is a text column. Standard `auth.uid() = user_id` comparisons fail without the explicit cast.

**Added**: 2026-03-02 (Schedule Tab Redesign)

---

## Permissions System Tables

**Added**: March 2026 (Migration 015 + 016)
**Purpose**: RBAC+ABAC permission system replacing the legacy 3-role enum (`UserRole`) and ad-hoc boolean flags.

### Architecture Overview

The permissions system uses three Supabase tables and an RPC function to provide granular, role-based access control with scope support:

- **`roles`** — Defines preset and custom roles with a hierarchy
- **`role_permissions`** — Maps each role to specific permissions with scopes
- **`user_roles`** — Assigns one role per user (1:1 mapping)
- **`has_permission()` RPC** — Server-side permission check function

**Four enforcement layers:**
1. **Supabase RLS** — Data-level floor (financial tables only; core operational tables use company isolation only)
2. **Client-side route guard** — Blocks navigation to unauthorized pages (web)
3. **UI gating** — Hides unauthorized UI elements (sidebar, PermissionGate, FAB, tabs)
4. **Server-side API checks** — Guards mutations via `checkPermission()` (web API routes)

### Roles Table

```sql
CREATE TABLE roles (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name        text NOT NULL,
  description text,
  is_preset   boolean DEFAULT false,
  company_id  uuid REFERENCES companies(id) ON DELETE CASCADE,
  hierarchy   integer NOT NULL,  -- 1=Admin (highest), 5=Crew (lowest)
  created_at  timestamptz DEFAULT now(),
  updated_at  timestamptz DEFAULT now(),

  CONSTRAINT roles_unique_name UNIQUE (company_id, name),
  CONSTRAINT roles_preset_no_company CHECK (NOT is_preset OR company_id IS NULL)
);
```

**5 Preset Roles (fixed UUIDs, `is_preset=true`, `company_id=NULL`):**

| UUID | Name | Hierarchy | Description |
|------|------|-----------|-------------|
| `00000000-0000-0000-0000-000000000001` | Admin | 1 | Full system access including billing and roles |
| `00000000-0000-0000-0000-000000000002` | Owner | 2 | Full access, company settings and integrations |
| `00000000-0000-0000-0000-000000000003` | Office | 3 | Office staff, full project and financial access |
| `00000000-0000-0000-0000-000000000004` | Operator | 4 | Lead tech, quotes jobs, manages assigned work |
| `00000000-0000-0000-0000-000000000005` | Crew | 5 | Basic field access, view assigned work only |

**Custom roles**: Companies can create custom roles (`is_preset=false`, `company_id` set). Custom roles cannot use the same name as preset roles within the same company. Preset roles cannot be edited or deleted.

### Role Permissions Table

```sql
CREATE TABLE role_permissions (
  role_id     uuid REFERENCES roles(id) ON DELETE CASCADE,
  permission  app_permission NOT NULL,  -- enum of ~55 dot-notation permissions
  scope       permission_scope DEFAULT 'all',  -- enum: 'all', 'assigned', 'own'

  PRIMARY KEY (role_id, permission)
);
```

### User Roles Table

```sql
CREATE TABLE user_roles (
  user_id     uuid PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
  role_id     uuid NOT NULL REFERENCES roles(id) ON DELETE RESTRICT,
  assigned_at timestamptz DEFAULT now(),
  assigned_by uuid REFERENCES users(id)
);
```

**One role per user** — the `user_id` is the primary key, enforcing a 1:1 relationship.

### Permission Enums

```sql
CREATE TYPE app_permission AS ENUM (
  -- Core Operations (20)
  'projects.view', 'projects.create', 'projects.edit', 'projects.delete',
  'projects.archive', 'projects.assign_team',
  'tasks.view', 'tasks.create', 'tasks.edit', 'tasks.delete',
  'tasks.assign', 'tasks.change_status',
  'clients.view', 'clients.create', 'clients.edit', 'clients.delete',
  'calendar.view', 'calendar.create', 'calendar.edit', 'calendar.delete',
  'job_board.view', 'job_board.manage_sections',
  -- Financial (18)
  'estimates.view', 'estimates.create', 'estimates.edit', 'estimates.delete', 'estimates.send',
  'invoices.view', 'invoices.create', 'invoices.edit', 'invoices.delete',
  'invoices.send', 'invoices.record_payment',
  'pipeline.view', 'pipeline.manage', 'pipeline.configure_stages',
  'products.view', 'products.manage',
  'expenses.view', 'expenses.create', 'expenses.edit', 'expenses.approve',
  'accounting.view', 'accounting.manage_connections',
  -- Resources (8)
  'inventory.view', 'inventory.manage', 'inventory.import',
  'photos.view', 'photos.upload', 'photos.annotate', 'photos.delete',
  'documents.view', 'documents.manage_templates',
  -- People & Location (7)
  'team.view', 'team.manage', 'team.assign_roles',
  'map.view', 'map.view_crew_locations',
  'notifications.view', 'notifications.manage_preferences',
  -- Admin (7)
  'settings.company', 'settings.billing', 'settings.integrations', 'settings.preferences',
  'portal.view', 'portal.manage_branding',
  'reports.view'
);

CREATE TYPE permission_scope AS ENUM ('all', 'assigned', 'own');
```

### Scope Hierarchy

Scopes follow a containment hierarchy: `all` > `assigned` > `own`.

- **`all`** — Can perform the action on any record in the company
- **`assigned`** — Can only perform the action on records the user is assigned to (team member on project)
- **`own`** — Can only perform the action on records the user created/owns

Having scope `all` automatically satisfies checks for `assigned` and `own`. Having `assigned` satisfies `own`.

### Preset Role Permission Summary

| Permission | Admin | Owner | Office | Operator | Crew |
|-----------|-------|-------|--------|----------|------|
| projects.view | all | all | all | all | **assigned** |
| projects.create | all | all | all | all | — |
| projects.edit | all | all | all | **assigned** | — |
| projects.delete | all | all | — | — | — |
| tasks.view | all | all | all | all | **assigned** |
| tasks.create | all | all | all | all | — |
| tasks.edit | all | all | all | **assigned** | **assigned** |
| tasks.change_status | all | all | all | **assigned** | **assigned** |
| clients.view | all | all | all | all | **assigned** |
| clients.create | all | all | all | all | — |
| pipeline.view | all | all | all | — | — |
| estimates.view | all | all | all | all | — |
| invoices.view | all | all | all | all | — |
| expenses.view | all | all | all | **own** | **own** |
| expenses.approve | all | all | all | — | — |
| inventory.view | all | all | all | — | — |
| team.assign_roles | all | — | — | — | — |
| settings.company | all | all | — | — | — |
| settings.billing | all | — | — | — | — |
| map.view_crew_locations | all | all | all | — | — |

*This is a subset — see migration 015 for the complete permission grants per role.*

### has_permission() RPC Function

```sql
CREATE OR REPLACE FUNCTION has_permission(
  p_user_id uuid,
  p_permission app_permission,
  p_required_scope permission_scope DEFAULT 'all'
) RETURNS boolean
LANGUAGE plpgsql SECURITY DEFINER STABLE
AS $$
BEGIN
  RETURN EXISTS (
    SELECT 1
    FROM user_roles ur
    JOIN role_permissions rp ON rp.role_id = ur.role_id
    WHERE ur.user_id = p_user_id
      AND rp.permission = p_permission
      AND (
        rp.scope = 'all'
        OR rp.scope = p_required_scope
        OR (p_required_scope = 'own' AND rp.scope IN ('own', 'assigned', 'all'))
        OR (p_required_scope = 'assigned' AND rp.scope IN ('assigned', 'all'))
      )
  );
END;
$$;
```

### RLS on Permission Tables

Permission tables have their own RLS policies:
- **Read**: All authenticated users can read preset roles and their own company's custom roles
- **Write**: Only users with `team.assign_roles` permission can create/modify custom roles, assign roles, and modify role permissions
- Preset roles cannot be updated or deleted (enforced by `NOT is_preset` checks on write policies)

### Auth ID Resolution

**Critical**: Supabase `auth.uid()` returns the Supabase Auth UUID, which is different from `users.id` (the application-level UUID). The `users` table has an `auth_id` column that maps the Supabase Auth UUID to the app user. A helper function resolves this:

```sql
CREATE OR REPLACE FUNCTION private.get_current_user_id()
RETURNS uuid LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = '' AS $$
  SELECT id FROM public.users
  WHERE auth_id = (SELECT auth.uid())::text
  LIMIT 1
$$;
```

All RLS policies on permission tables use `private.get_current_user_id()` instead of `auth.uid()` directly.

### Web Implementation Reference

The web app (OPS-Web) implements the permission system with:
- **`permissions-store.ts`** — Zustand store with `can(permission, scope?)` method
- **`permission-gate.tsx`** — React component that conditionally renders children based on permissions
- **`check-permission.ts`** — Server-side utility calling `has_permission()` RPC
- **`roles-service.ts`** — CRUD operations for roles, role permissions, and user role assignments
- **Sidebar** — Nav items filtered by permission (e.g., `permission: "invoices.view"`)
- **Route guard** — Dashboard layout blocks render of gated routes until permissions load
- **Settings** — Roles sub-tab gated behind `team.assign_roles`

### Legacy Fields Being Replaced

| Legacy Field | Replaced By | Status |
|-------------|-------------|--------|
| `user.role` (UserRole enum) | `user_roles` table + `roles` table | Kept for backward compat, no longer source of truth |
| `user.isCompanyAdmin` | `settings.company` + `settings.billing` permissions | Kept for backward compat |
| `user.inventoryAccess` | `inventory.view` permission | Never synced from Supabase, always `false` |
| `user.specialPermissions` (pipeline flag) | `pipeline.view` permission | Only set on first insert, not updated on sync |
| `user.devPermission` | No replacement needed | Synced but never checked in any view logic |

---

## Inventory Models (5 Entities -- File-Only, Not in Schema)

These models exist as SwiftData files but are **NOT registered in the OPSApp.swift Schema array**. They are referenced via Company relationships.

### InventoryItem

**File**: `DataModels/InventoryItem.swift`

```swift
@Model
final class InventoryItem: Identifiable {
    var id: String
    var name: String
    var itemDescription: String?
    var quantity: Double
    var unitId: String?
    var companyId: String
    var sku: String?
    var notes: String?
    var imageUrl: String?
    var tagIds: [String] = []
    var warningThreshold: Double?
    var criticalThreshold: Double?

    @Relationship(deleteRule: .nullify) var unit: InventoryUnit?
    @Relationship(deleteRule: .nullify) var tags: [InventoryTag] = []

    var lastSyncedAt: Date?
    var needsSync: Bool = false
    var deletedAt: Date?
}
```

**ThresholdStatus Enum**: `.normal`, `.warning`, `.critical` -- used for low-stock alerts.

**Key Computed**: `quantityDisplay`, `thresholdStatus`, `effectiveThresholdStatus()` (considers tag thresholds), `isLowStock`.

### InventorySnapshot

**File**: `DataModels/InventorySnapshot.swift`

```swift
@Model
final class InventorySnapshot: Identifiable {
    var id: String
    var companyId: String
    var createdAt: Date
    var createdById: String?
    var isAutomatic: Bool
    var itemCount: Int
    var notes: String?

    @Relationship(deleteRule: .cascade, inverse: \InventorySnapshotItem.snapshot)
    var items: [InventorySnapshotItem]?

    var lastSyncedAt: Date?
    var needsSync: Bool = false
}
```

### InventorySnapshotItem

**File**: `DataModels/InventorySnapshotItem.swift`

```swift
@Model
final class InventorySnapshotItem: Identifiable {
    var id: String
    var snapshotId: String
    var originalItemId: String
    var name: String
    var quantity: Double
    var unitDisplay: String?
    var sku: String?
    var tagsString: String = ""
    var itemDescription: String?

    @Relationship(deleteRule: .nullify) var snapshot: InventorySnapshot?

    var lastSyncedAt: Date?
    var needsSync: Bool = false
}
```

### InventoryTag

**File**: `DataModels/InventoryTag.swift`

```swift
@Model
final class InventoryTag: Identifiable {
    var id: String
    var name: String
    var warningThreshold: Double?
    var criticalThreshold: Double?
    var companyId: String

    @Relationship(deleteRule: .nullify, inverse: \InventoryItem.tags)
    var items: [InventoryItem] = []

    var lastSyncedAt: Date?
    var needsSync: Bool = false
    var deletedAt: Date?
}
```

### InventoryUnit

**File**: `DataModels/InventoryUnit.swift`

```swift
@Model
final class InventoryUnit: Identifiable {
    var id: String
    var display: String                      // e.g. "ea", "box", "ft"
    var companyId: String
    var isDefault: Bool
    var sortOrder: Int = 0

    @Relationship(deleteRule: .nullify, inverse: \InventoryItem.unit)
    var items: [InventoryItem] = []

    @Relationship(deleteRule: .cascade, inverse: \Company.inventoryUnits)  // via Company
    // (inverse managed through Company.inventoryUnits)

    var lastSyncedAt: Date?
    var needsSync: Bool = false
    var deletedAt: Date?
}
```

---

## Enums Reference

### Status (Project Status)

**File**: `DataModels/Status.swift`

```swift
enum Status: String, Codable, CaseIterable {
    case rfq = "rfq"
    case estimated = "estimated"
    case accepted = "accepted"
    case inProgress = "in_progress"
    case completed = "completed"
    case closed = "closed"
    case archived = "archived"
}
```

Legacy title-case values ("Pending", "RFQ", "Estimated", etc.) are handled by custom decoder.

### TaskStatus

**File**: `DataModels/ProjectTask.swift` (defined inline)

```swift
enum TaskStatus: String, Codable, CaseIterable {
    case active = "active"
    case completed = "completed"
    case cancelled = "cancelled"
}
```

Legacy mapping: "Scheduled"/"Booked"/"booked"/"In Progress"/"in_progress" all map to `.active`.

### UserRole

**File**: `DataModels/UserRole.swift`

```swift
enum UserRole: String, Codable {
    case fieldCrew = "field_crew"
    case officeCrew = "office_crew"
    case admin = "admin"
}
```

Legacy title-case ("Field Crew", "Office Crew", "Admin") handled by custom decoder.

### UserType

**File**: `DataModels/UserRole.swift`

```swift
enum UserType: String, CaseIterable, Codable {
    case employee = "employee"
    case company = "company"
}
```

### PipelineStage

**File**: `DataModels/Enums/PipelineStage.swift`

```swift
enum PipelineStage: String, Codable, CaseIterable, Identifiable {
    case newLead      = "new_lead"       // 10% win probability
    case qualifying   = "qualifying"     // 20%
    case quoting      = "quoting"        // 40%
    case quoted       = "quoted"         // 60%
    case followUp     = "follow_up"      // 50%
    case negotiation  = "negotiation"    // 75%
    case won          = "won"            // 100%
    case lost         = "lost"           // 0%
}
```

Properties: `displayName`, `isTerminal`, `next`, `winProbability`, `staleThresholdDays`.

### ActivityType

**File**: `DataModels/Enums/ActivityType.swift`

Cases: `note`, `email`, `call`, `meeting`, `estimateSent`, `estimateApproved`, `estimateDeclined`, `invoiceSent`, `paymentReceived`, `stageChange`, `created`, `won`, `lost`, `siteVisit`, `system`.

Properties: `icon` (SF Symbol), `isSystemGenerated`.

### Financial Enums

**File**: `DataModels/Enums/FinancialEnums.swift`

- **EstimateStatus**: `draft`, `sent`, `viewed`, `approved`, `converted`, `declined`, `expired`
- **InvoiceStatus**: `draft`, `sent`, `awaitingPayment`, `partiallyPaid`, `paid`, `pastDue`, `void`
- **PaymentMethod**: `cash`, `check`, `creditCard`, `ach`, `bankTransfer`, `stripe`, `other`
- **LineItemType**: `labor` ("LABOR"), `material` ("MATERIAL"), `other` ("OTHER")
- **FollowUpType**: `call`, `email`, `meeting`, `quoteFollowUp`, `invoiceFollowUp`, `custom`
- **FollowUpStatus**: `pending`, `completed`, `skipped`
- **SiteVisitStatus**: `scheduled`, `completed`, `cancelled`
- **ExpenseStatus**: `draft`, `submitted`, `approved`, `rejected`, `reimbursed`
- **ExpensePaymentMethod**: `cash`, `personalCard` ("personal_card"), `companyCard` ("company_card")
- **ReviewFrequency**: `perJob` ("per_job"), `weekly`, `biweekly`, `monthly`, `quarterly`
- **AccountingSyncStatus**: `pending`, `synced`, `error`

### Subscription Enums

**File**: `DataModels/SubscriptionEnums.swift`

- **SubscriptionStatus**: `trial`, `active`, `grace`, `expired`, `cancelled`
- **SubscriptionPlan**: `trial`, `starter`, `team`, `business` (with `maxSeats`, pricing, Stripe IDs)
- **PaymentSchedule**: `monthly` ("Monthly"), `annual` ("Annual")

---

## Relationship Map

Built from actual `@Relationship` declarations in the source code:

```
Company
├── teamMembers: [TeamMember]          (cascade)
├── taskTypes: [TaskType]              (cascade)
└── inventoryUnits: [InventoryUnit]    (cascade)

Project
├── client: Client?                     (nullify)
├── teamMembers: [User]                 (noAction)
└── tasks: [ProjectTask]                (cascade, inverse: ProjectTask.project)

ProjectTask
├── project: Project?                   (nullify)
├── taskType: TaskType?                 (nullify)
└── teamMembers: [User]                 (noAction)

Client
├── projects: [Project]                 (noAction, inverse: Project.client)
└── subClients: [SubClient]             (cascade)

SubClient
└── client: Client?                     (implicit inverse)

User
└── assignedProjects: [Project]         (noAction, inverse: Project.teamMembers)

TeamMember
└── company: Company?                   (cascade, inverse: Company.teamMembers)

TaskType
└── tasks: [ProjectTask]                (nullify, inverse: ProjectTask.taskType)

InventoryItem
├── unit: InventoryUnit?                (nullify)
└── tags: [InventoryTag]                (nullify)

InventoryTag
└── items: [InventoryItem]              (nullify, inverse: InventoryItem.tags)

InventoryUnit
└── items: [InventoryItem]              (nullify, inverse: InventoryItem.unit)

InventorySnapshot
└── items: [InventorySnapshotItem]?     (cascade, inverse: InventorySnapshotItem.snapshot)

InventorySnapshotItem
└── snapshot: InventorySnapshot?        (nullify)
```

**Supabase-backed models** (Opportunity, Estimate, Invoice, etc.) use **String foreign keys** (e.g., `opportunityId`, `companyId`, `projectId`) rather than `@Relationship` declarations. They are linked by ID lookup, not SwiftData relationships.

---

## BubbleFields Constants (Legacy/Deprecated)

`BubbleFields.swift` has been **removed from the codebase**. The file no longer exists. It previously contained byte-perfect field name mappings between Bubble.io and Swift models.

The system has migrated to Supabase DTOs with snake_case `CodingKeys` for API communication. Legacy Bubble DTOs (ProjectDTO, TaskDTO, CalendarEventDTO, UserDTO, CompanyDTO, ClientDTO, SubClientDTO, TaskTypeDTO) documented in earlier versions of this file may still exist in the codebase but are no longer the primary data pathway.

---

## Data Transfer Objects (DTOs)

### Legacy Bubble DTOs

The Bubble DTOs (ProjectDTO, TaskDTO, UserDTO, CompanyDTO, ClientDTO, SubClientDTO, TaskTypeDTO) were the original API mapping layer between Bubble.io and SwiftData models. These may still exist for backward compatibility but are being superseded by Supabase DTOs.

---

## Supabase DTOs

All Supabase DTOs live under `Network/Supabase/DTOs/`. They use snake_case `CodingKeys` to match Supabase column names and include `toModel()` methods for conversion to SwiftData objects.

### CoreEntityDTOs.swift

Contains DTOs for the 9 core entities migrated from Bubble:

| DTO | Target Model | Key CodingKeys Notes |
|-----|-------------|---------------------|
| `SupabaseCompanyDTO` | `Company` | `bubble_id`, `logo_url`, `admin_ids`, `seated_employee_ids`, `stripe_customer_id` |
| `SupabaseUserDTO` | `User` | `first_name`, `last_name`, `profile_image_url`, `user_color`, `is_company_admin`, `special_permissions` |
| `SupabaseClientDTO` | `Client` | `phone_number` (not `phone`), `profile_image_url` |
| `SupabaseSubClientDTO` | `SubClient` | `client_id`, `phone_number`; exposes `parentClientId` for relationship wiring |
| `SupabaseTaskTypeDTO` | `TaskType` | Table is `task_types_v2`; column is `display` (not `name`) |
| `SupabaseProjectDTO` | `Project` | `team_member_ids`, `project_images` as arrays; `opportunity_id` |
| `SupabaseProjectTaskDTO` | `ProjectTask` | `task_type_id`, `custom_title`, `task_notes`, `source_line_item_id`, `source_estimate_id`, `start_date`, `end_date` |
| `SupabaseOpsContactDTO` | `OpsContact` | `bubble_id` |

### CoreEntityConverters.swift

Extension methods `toModel()` on each DTO. Key deviations documented in code comments:

- Company: `adminIdsString` is comma-separated (not array), `logoURL` (not `logoUrl`)
- User: init requires `(id:firstName:lastName:role:companyId:)` -- role and companyId not optional
- SubClient: No `clientId` stored property -- parent Client relationship set by sync layer
- TaskType: Uses `display` not `name`

### OpportunityDTOs.swift

| DTO | Purpose |
|-----|---------|
| `OpportunityDTO` | Read; `toModel() -> Opportunity` |
| `CreateOpportunityDTO` | Create |
| `UpdateOpportunityDTO` | Partial update |
| `ActivityDTO` | Read; `toModel() -> Activity` |
| `CreateActivityDTO` | Create |
| `FollowUpDTO` | Read; `toModel() -> FollowUp` |
| `CreateFollowUpDTO` | Create |

### EstimateDTOs.swift

| DTO | Purpose |
|-----|---------|
| `EstimateDTO` | Read with nested `lineItems`; `toModel() -> Estimate` |
| `EstimateLineItemDTO` | Read; `toModel() -> EstimateLineItem` |
| `CreateEstimateDTO` | Create |
| `CreateLineItemDTO` | Create line item |
| `UpdateLineItemDTO` | Partial update |

### InvoiceDTOs.swift

| DTO | Purpose |
|-----|---------|
| `InvoiceDTO` | Read with nested `lineItems` and `payments`; `toModel() -> Invoice` |
| `InvoiceLineItemDTO` | Read; `toModel() -> InvoiceLineItem` |
| `PaymentDTO` | Read; `toModel() -> Payment` |
| `CreatePaymentDTO` | Create |

### ProductDTOs.swift

| DTO | Purpose |
|-----|---------|
| `ProductDTO` | Read; `toModel() -> Product` |
| `CreateProductDTO` | Create |
| `UpdateProductDTO` | Partial update |

### ExpenseDTOs.swift

| DTO | Purpose |
|-----|---------|
| `ExpenseDTO` | Read with nested `allocations` and `category` |
| `CreateExpenseDTO` | Create expense |
| `UpdateExpenseDTO` | Partial update (draft editing) |
| `ExpenseAllocationDTO` | Read project allocation |
| `CreateExpenseAllocationDTO` | Create allocation |
| `ExpenseCategoryDTO` | Read category |
| `CreateExpenseCategoryDTO` | Create custom category |
| `ExpenseBatchDTO` | Read batch |
| `ExpenseSettingsDTO` | Read/write company settings |
| `AccountingCategoryMappingDTO` | Read accounting category mapping (QB/Sage) |
| `CreateAccountingCategoryMappingDTO` | Create/upsert mapping |

### InventoryDTOs.swift

| DTO | Purpose |
|-----|---------|
| `InventoryUnitReadDTO` | Read; `toModel() -> InventoryUnit` |
| `InventoryTagReadDTO` | Read; `toModel() -> InventoryTag` |
| `InventoryItemReadDTO` | Read; `toModel() -> InventoryItem` |
| `InventoryItemTagReadDTO` | Junction table read (item_id, tag_id) |
| `InventorySnapshotReadDTO` | Read; `toModel() -> InventorySnapshot` |
| `InventorySnapshotItemReadDTO` | Read; `toModel() -> InventorySnapshotItem` |
| `CreateInventoryUnitDTO` | Create |
| `CreateInventoryTagDTO` | Create |
| `CreateInventoryItemDTO` | Create |
| `CreateInventorySnapshotDTO` | Create |
| `CreateInventorySnapshotItemDTO` | Create |
| `UpdateInventoryItemDTO` | Partial update |
| `UpdateInventoryTagDTO` | Partial update |
| `UpdateInventoryUnitDTO` | Partial update |

### ProjectNoteDTOs.swift

| DTO | Purpose |
|-----|---------|
| `ProjectNoteDTO` | Read; `toModel() -> ProjectNote` |
| `CreateProjectNoteDTO` | Create (includes `mentioned_user_ids`) |

### PhotoAnnotationDTOs.swift

| DTO | Purpose |
|-----|---------|
| `PhotoAnnotationDTO` | Read; `toModel() -> PhotoAnnotation` |
| `UpsertPhotoAnnotationDTO` | Create/update |

### NotificationDTO.swift

```swift
struct NotificationDTO: Codable, Identifiable {
    let id: String
    let userId: String          // user_id
    let companyId: String       // company_id
    let type: String
    let title: String
    let body: String
    let projectId: String?      // project_id
    let noteId: String?         // note_id
    var isRead: Bool            // is_read
    let createdAt: String       // created_at
}
```

No corresponding SwiftData model -- used for push notification display only.

### SupabaseDateParsing.swift

Shared date parsing utility:

```swift
enum SupabaseDate {
    static func parse(_ string: String) -> Date?
    // Tries ISO8601 with fractional seconds first, then without
}
```

---

## Soft Delete Strategy

### Overview

Most models support **soft delete** via `deletedAt: Date?` timestamp.

### Default Query Pattern

**Always exclude soft-deleted items** unless explicitly querying for them:

```swift
// CORRECT
@Query(filter: #Predicate<Project> { $0.deletedAt == nil }) var projects: [Project]

// INCORRECT - shows deleted items
@Query var projects: [Project]
```

---

## Computed Properties & Business Logic

### Project Computed Dates (Task-Based)

Project dates are computed from task start/end dates directly (CalendarEvent entity removed):

```swift
var computedStartDate: Date? {
    tasks.compactMap { $0.startDate }.min()
}
var computedEndDate: Date? {
    tasks.compactMap { $0.endDate }.max()
}
```

### Client Contact Cascading

Client contact info checks client first, then sub-clients:

```swift
var effectiveClientEmail: String? {
    if let clientEmail = client?.email, !clientEmail.isEmpty { return clientEmail }
    // Falls through to sub-clients...
}
```

### Role Detection Logic

Role is determined by the `role: UserRole` property on the User model. The Supabase DTO maps `role` string directly.

### Project Team Computation

Project team members are computed from task team members via `updateTeamMembersFromTasks(in:)`. Call after any task creation, update, or deletion.

---

## Migration History

### CalendarEvent Removal (February 2026)

CalendarEvent is no longer a model in the codebase. Scheduling dates (`startDate`, `endDate`, `duration`) are now stored directly on `ProjectTask`. The CalendarEvent model file has been deleted. All calendar display flows through ProjectTask properties.

### Task-Only Scheduling Migration (November 2025)

- Removed project-level calendar events
- Added `computedStartDate` / `computedEndDate` computed properties on Project
- Simplified calendar filtering to use task dates

### Status Value Migration

- **Project Status**: Changed from title-case ("RFQ", "In Progress") to snake_case ("rfq", "in_progress"). Custom decoders handle both.
- **TaskStatus**: Simplified to 3 states: `.active`, `.completed`, `.cancelled`. Legacy values ("Scheduled", "Booked", "In Progress") all map to `.active`.
- **UserRole**: Changed from title-case ("Field Crew") to snake_case ("field_crew"). Custom decoder handles both.

---

## Query Predicates & Filtering

### Active Projects

```swift
@Query(
    filter: #Predicate<Project> {
        $0.deletedAt == nil &&
        $0.status != .closed &&
        $0.status != .archived
    }
) var activeProjects: [Project]
```

### Tasks by Status

```swift
func tasksByStatus(_ status: TaskStatus) -> [ProjectTask] {
    let descriptor = FetchDescriptor<ProjectTask>(
        predicate: #Predicate { $0.deletedAt == nil && $0.status == status }
    )
    return try? modelContext.fetch(descriptor) ?? []
}
```

---

## Defensive Programming Patterns

### 1. Never Pass Models to Background Tasks

```swift
// CORRECT: Pass IDs
Task.detached { await processProject(projectId: project.id) }

// INCORRECT: Passing model causes crashes
Task.detached { await processProject(project: project) }
```

SwiftData models are tied to their ModelContext. Passing models across thread boundaries causes crashes.

### 2. Always Fetch Fresh Models

```swift
func processProject(projectId: String) async {
    let context = ModelContext(sharedModelContainer)
    let descriptor = FetchDescriptor<Project>(predicate: #Predicate { $0.id == projectId })
    guard let project = try? context.fetch(descriptor).first else { return }
    // Work with fresh model
}
```

### 3. Use @MainActor for UI Operations

### 4. Explicit ModelContext.save()

Always save explicitly after changes -- do not rely on auto-save.

### 5. Complete Data Wipe on Logout

Delete all 24 model types to prevent cross-user contamination.

---

## Summary

This data architecture provides:

- **24 registered SwiftData entities** (11 core + 13 Supabase-backed) plus 5 inventory models
- **Soft delete support** for data integrity
- **Supabase DTOs** for clean API separation with snake_case column mapping
- **Task-based scheduling** with dates stored directly on ProjectTask (CalendarEvent removed)
- **Computed properties** for project dates, client contact cascading, and team aggregation
- **Defensive patterns** to prevent SwiftData threading crashes
- **Complete enum system** for statuses, roles, pipeline stages, and financial types

**Key Principles**:
1. Always filter out soft-deleted items
2. Never pass models across threads
3. Compute project dates from tasks
4. TaskType uses `display` property (not `name`)
5. Client uses `email` property (not `emailAddress`)
6. User uses `firstName`/`lastName` (not `nameFirst`/`nameLast`)
7. TaskStatus has 3 states: `.active`, `.completed`, `.cancelled`

---

## Gmail Integration Tables (Web Only)

These tables exist in Supabase only (not in SwiftData). See `10_JOB_LIFECYCLE_AND_DATA_RELATIONSHIPS.md` for full integration documentation.

### gmail_connections

```sql
CREATE TABLE gmail_connections (
  id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id            UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
  user_id               UUID REFERENCES users(id),
  type                  TEXT NOT NULL DEFAULT 'company',  -- 'company' | 'individual'
  email                 TEXT NOT NULL,
  access_token          TEXT NOT NULL,
  refresh_token         TEXT NOT NULL,
  expires_at            TIMESTAMPTZ NOT NULL,
  history_id            TEXT,                             -- Gmail incremental sync cursor
  sync_enabled          BOOLEAN DEFAULT true,
  last_synced_at        TIMESTAMPTZ,
  sync_interval_minutes INTEGER DEFAULT 15,
  sync_filters          JSONB DEFAULT '{}',               -- GmailSyncFilters object
  created_at            TIMESTAMPTZ DEFAULT NOW(),
  updated_at            TIMESTAMPTZ DEFAULT NOW(),
  deleted_at            TIMESTAMPTZ
);
```

`sync_filters` stores a `GmailSyncFilters` JSON object containing label IDs, exclude lists, structured filter rules, wizard state, and scan results.

### gmail_import_jobs

```sql
CREATE TABLE gmail_import_jobs (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id        UUID NOT NULL REFERENCES companies(id),
  connection_id     UUID NOT NULL REFERENCES gmail_connections(id),
  status            TEXT NOT NULL DEFAULT 'pending',  -- pending | running | completed | failed
  import_after      DATE NOT NULL,
  total_emails      INTEGER DEFAULT 0,
  processed         INTEGER DEFAULT 0,
  matched           INTEGER DEFAULT 0,
  unmatched         INTEGER DEFAULT 0,
  needs_review      INTEGER DEFAULT 0,
  clients_created   INTEGER DEFAULT 0,
  leads_created     INTEGER DEFAULT 0,
  error_message     TEXT,
  created_at        TIMESTAMPTZ DEFAULT NOW(),
  completed_at      TIMESTAMPTZ
);
```

### gmail_scan_jobs

```sql
CREATE TABLE gmail_scan_jobs (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id        UUID NOT NULL REFERENCES companies(id),
  connection_id     UUID NOT NULL REFERENCES gmail_connections(id),
  status            TEXT NOT NULL DEFAULT 'pending',  -- pending | running | completed | failed
  stage             TEXT DEFAULT 'pending',           -- pending | listing | fetching | pre_filtering | classifying | complete | error
  current           INTEGER DEFAULT 0,
  total             INTEGER DEFAULT 0,
  message           TEXT,
  results           JSONB,                            -- ScannedEmail[] when complete
  ai_filters        JSONB,                            -- AI-recommended GmailSyncFilters
  summary           TEXT,                             -- AI analysis summary
  error_message     TEXT,
  created_at        TIMESTAMPTZ DEFAULT NOW(),
  completed_at      TIMESTAMPTZ
);
```

### email_filter_presets

```sql
CREATE TABLE email_filter_presets (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  category    TEXT NOT NULL,          -- e.g., 'newsletters', 'notifications', 'retailers'
  type        TEXT NOT NULL,          -- 'domain' | 'keyword'
  value       TEXT NOT NULL,          -- e.g., 'noreply.github.com' or 'unsubscribe'
  is_active   BOOLEAN DEFAULT true,
  created_at  TIMESTAMPTZ DEFAULT NOW()
);
```

Seeded with ~100+ common noise sources across categories. Used by `EmailFilterService.buildBlocklist()` when `usePresetBlocklist` is true.

**End of Data Architecture Documentation**
