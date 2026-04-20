# 03: Data Architecture

**Last Updated**: March 19, 2026
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
    var role: UserRole                       // .admin, .owner, .office, .operator, .crew, .unassigned
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

    // Email system columns (Supabase only — not in SwiftData model)
    // stage_manually_set BOOLEAN NOT NULL DEFAULT false — true when user manually drags card to new stage;
    //   prevents AI/deterministic stage override. Cleared to false when new inbound email arrives
    //   (situation evolved, AI can re-evaluate)
    // ai_summary         TEXT — 1-2 sentence AI-generated summary of the opportunity, cached and
    //   refreshed each sync cycle that touches the thread via evaluateStagesWithSummary()
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

    // Email fields (Supabase columns — not in SwiftData model)
    // to_emails       TEXT[] DEFAULT '{}'          — recipient email addresses
    // cc_emails       TEXT[] DEFAULT '{}'          — CC'd email addresses
    // body_text       TEXT                         — full email body (markdown from compose, plain text from sync)
    // has_attachments BOOLEAN NOT NULL DEFAULT false — whether email has attachments
    // attachment_count INT NOT NULL DEFAULT 0      — number of attachments
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
**Purpose**: RBAC+ABAC permission system augmenting the 6-role enum (`UserRole`: admin, owner, office, operator, crew, unassigned) with granular per-permission control, replacing ad-hoc boolean flags.

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
  permission  app_permission NOT NULL,  -- enum of ~59 dot-notation permissions
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
  -- Financial (22)
  'estimates.view', 'estimates.create', 'estimates.edit', 'estimates.delete', 'estimates.send', 'estimates.convert',
  'invoices.view', 'invoices.create', 'invoices.edit', 'invoices.delete',
  'invoices.send', 'invoices.record_payment', 'invoices.void',
  'pipeline.view', 'pipeline.manage', 'pipeline.configure_stages',
  'products.view', 'products.manage',
  'expenses.view', 'expenses.create', 'expenses.edit', 'expenses.delete', 'expenses.approve', 'expenses.configure',
  'accounting.view', 'accounting.manage_connections',
  -- Resources (8)
  'inventory.view', 'inventory.manage', 'inventory.import',
  'photos.view', 'photos.upload', 'photos.annotate', 'photos.delete',
  'documents.view', 'documents.manage_templates',
  -- People & Location (7)
  'team.view', 'team.manage', 'team.assign_roles',
  'map.view', 'map.view_crew_locations',
  'notifications.view', 'notifications.manage_preferences',
  -- Email Integration (4)
  'email.connect', 'email.view', 'email.manage', 'email.configure_ai',
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
| estimates.convert | all | all | all | — | — |
| invoices.view | all | all | all | all | — |
| invoices.void | all | all | all | — | — |
| expenses.view | all | all | all | **own** | **own** |
| expenses.delete | all | all | all | **own** | **own** |
| expenses.approve | all | all | all | — | — |
| expenses.configure | all | all | all | — | — |
| inventory.view | all | all | all | — | — |
| team.assign_roles | all | — | — | — | — |
| settings.company | all | all | — | — | — |
| settings.billing | all | — | — | — | — |
| map.view_crew_locations | all | all | all | — | — |

*This is a subset — see migration 015 for the complete permission grants per role.*

**Scope expansions (added March 2026):**
- `expenses.approve`: now supports `assigned` scope (approve expenses on assigned projects)
- `pipeline.manage`: now supports `own` scope (manage own pipeline deals)

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

### Mention-Based Project Access (Migration 074, 2026-04-20)

**Rule**: a user tagged in any live (non-soft-deleted) `project_notes.mentioned_user_ids` entry for a project gains read-only view access to the project and its tasks, regardless of `projects.team_member_ids` membership.

**Scope of grant**:
- Read: `projects`, `project_tasks` — extended via new helper.
- Write: **no extension**. Mention-granted users cannot edit project fields, tasks, schedule, team, estimates, invoices, or expenses. Enforced at the DB via unchanged `role_scope_update` policies calling the original `current_user_in_project` helper.
- Client-side surfaces: mention-granted projects appear in Universal Search + iOS Spotlight only. Hidden from Job Board "My Projects", Calendar, Schedule, and Map by design — discoverability limited to push-notification deep link and search.

**SQL (Migration 074):**

```sql
-- New read-only helper — superset of current_user_in_project with mention branch.
CREATE OR REPLACE FUNCTION private.current_user_can_view_project(p_project_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
  SELECT private.current_user_in_project(p_project_id)
      OR EXISTS (
        SELECT 1 FROM public.project_notes pn
        WHERE pn.project_id = p_project_id::text
          AND pn.deleted_at IS NULL
          AND private.get_current_user_id()::text = ANY(COALESCE(pn.mentioned_user_ids, ARRAY[]::text[]))
      );
$$;
```

**Policies updated** (read-only — write policies intentionally untouched):
- `projects.role_scope_read` — `assigned` branch now calls `current_user_can_view_project(projects.id)`.
- `project_tasks.role_scope_read` — `assigned` branch now calls `current_user_can_view_project(project_id)`.

**Policies NOT changed** (to keep mention-grant view-only):
- `projects.role_scope_update`, `project_tasks.role_scope_update`, `estimates.role_scope_update`, `invoices.role_scope_update` — continue to call the team-only `current_user_in_project`.

**iOS client integration**:
- `MentionAccessIndex` (`OPS/Utilities/`) — on-device index of projectIds the current user has mention access to. Rebuilt from cached `ProjectNote` rows on login, sync completion, Realtime note events.
- `ProjectAccessHelper.narrowVisible` vs `.wideVisible` — surface-specific predicates. Job Board uses narrow; Search/Spotlight use wide.
- `PermissionStore.canViewProject(_ project:, userId:)` — per-record check combining base-role scope + mention-grant.
- Mention-only users see a read-locked `ProjectQuickActionsBar` with only the "NOTE" action available (reply-only, per Bug G9 Rule 2).

**Context**: Bug G9 (2026-04-20). Source of truth: `docs/superpowers/plans/2026-04-20-mention-based-project-access.md`.

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

### Permission Enforcement Matrix

Every page, tab, and action button in OPS-Web must be gated. This matrix is the source of truth.

#### Route-Level Gates (layout.tsx → ROUTE_PERMISSIONS)

| Route | Permission | Feature Flag |
|-------|-----------|-------------|
| /projects | projects.view | — |
| /calendar | calendar.view | — |
| /clients | clients.view | — |
| /job-board | job_board.view | — |
| /team | team.view | — |
| /map | map.view | — |
| /pipeline | pipeline.view | pipeline |
| /estimates | estimates.view | estimates |
| /invoices | invoices.view | invoices |
| /products | products.view | products |
| /inventory | inventory.view | inventory |
| /accounting | accounting.view | accounting |
| /portal-inbox | portal.view | portal |

#### Settings Tab Gates (SUB_TAB_PERMISSIONS)

| Tab ID | Permission Required |
|--------|-------------------|
| company-details | settings.company |
| team | team.view |
| roles | team.assign_roles |
| task-types | settings.company |
| inventory | inventory.manage |
| expenses | expenses.configure |
| subscription | settings.billing |
| payment | settings.billing |
| email | settings.integrations |
| portal | portal.manage_branding |
| templates | documents.manage_templates |
| accounting | accounting.manage_connections |
| setup-wizards | settings.company |

Tabs without entries (profile, appearance, notifications, shortcuts, preferences-general, map, data-privacy) are personal settings accessible to all authenticated users.

#### Action Button Gating Pattern

When building any feature with user actions, gate with `<PermissionGate>` or `can()`:

| Action Pattern | Permission Required |
|---------------|-------------------|
| Create [resource] | [module].create |
| Edit [resource] | [module].edit |
| Delete [resource] | [module].delete |
| Send [document] | [module].send |
| Void [document] | [module].void |
| Convert [document] | [module].convert |
| Approve [item] | [module].approve |
| Configure [settings] | [module].configure or settings.* |
| Manage [integration] | [module].manage_connections |

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
    case admin = "admin"
    case owner = "owner"
    case office = "office"
    case operator = "operator"
    case crew = "crew"
    case unassigned = "unassigned"
}
```

Default role for company creator: `.owner`. Default role for new users: `.unassigned`.
Legacy title-case ("Field Crew", "Office Crew", "Admin") and legacy snake_case ("field_crew", "office_crew") handled by custom decoder.

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
    case discarded    = "discarded"      // 0% — lead not worth pursuing (ad quality signal)
}
```

Properties: `displayName`, `isTerminal`, `next`, `winProbability`, `staleThresholdDays`.

Terminal stages: `won`, `lost`, `discarded`. Discarded is a third terminal state meaning "not worth pursuing" — the lead contacted us (counts as an ad conversion) but was junk quality. Used for ad targeting quality analytics: compare won+lost (real leads) vs discarded (bad quality).

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
- **UserRole**: Expanded from 3 roles (admin, office_crew, field_crew) to 6 roles (admin, owner, office, operator, crew, unassigned). Legacy values ("Field Crew", "field_crew", "Office Crew", "office_crew") mapped to `.crew` and `.office` respectively by custom decoder.

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

**For off-main writes, use `DataActor`** (see `06_TECHNICAL_ARCHITECTURE.md` → "DataActor (Background SwiftData Writes)"). Cross the actor boundary with `PersistentIdentifier` (Sendable) and re-fetch via `modelContext.model(for: id)` on the receiving side. Never hand `@Model` instances to an actor.

### 2. Always Fetch Fresh Models

```swift
func processProject(projectId: String) async {
    let context = ModelContext(sharedModelContainer)
    let descriptor = FetchDescriptor<Project>(predicate: #Predicate { $0.id == projectId })
    guard let project = try? context.fetch(descriptor).first else { return }
    // Work with fresh model
}
```

Inside `DataActor` methods, use `self.modelContext` (the actor's background context); do not create ad-hoc `ModelContext(sharedModelContainer)` instances from within an actor.

### 3. Use @MainActor for UI Operations

### 4. Context-Specific Save Semantics

**Main context (`sharedModelContainer.mainContext`):** autosave on. Explicit `try context.save()` still required after mutations for deterministic persistence; do not rely solely on autosave timing.

**DataActor's background context:** autosave off. Wrap all mutation sequences in `try modelContext.transaction { ... }` — atomic at the SQLite level, persists on block exit, composes cleanly with SwiftData inverse-relationship cascades. Do NOT call `save()` inside a DataActor method; the transaction block handles commit.

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
- **Defensive patterns** to prevent SwiftData threading crashes, plus `@ModelActor DataActor` isolation for all background writes (Phase 1 of ModelActor refactor complete 2026-04-19)
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

## Email Integration Tables (Web Only)

These tables exist in Supabase only (not in SwiftData). See `10_JOB_LIFECYCLE_AND_DATA_RELATIONSHIPS.md` for full integration documentation including the sync engine, pattern detection, AI classification, and provider abstraction layer.

### Migration Notes

- **`gmail_connections` → `email_connections`** (migration 034): Table renamed. New columns added: `provider` (TEXT, default `'gmail'`), `webhook_subscription_id`, `webhook_expires_at`, `ops_label_id`, `ai_review_enabled`, `ai_memory_enabled`, `status`. All existing rows backfilled with `provider = 'gmail'`. No re-auth required for existing Gmail connections.
- **`gmail_scan_jobs` was NOT renamed.** The table retains its original name `gmail_scan_jobs` in both the database and all code references. Only `gmail_connections` was renamed.
- **`sync_filters` column was NOT renamed.** Migration 034 contains a comment noting the intent to rename `sync_filters` to `sync_profile`, but the rename was deferred. The DB column remains `sync_filters`. The TypeScript type `SyncProfile` maps to this column via the `syncFilters` field on `EmailConnection`.
- **Migration 035** added: `opportunity_email_threads`, `admin_feature_overrides`, and correspondence tracking columns on `opportunities`.
- **Migration 036** added: `agent_memories` (with pgvector), `agent_knowledge_graph`, `agent_writing_profiles`.
- **Migration 037-040** (Phase C Memory Bank): `graph_entities` table, entity FK columns on `agent_knowledge_graph` (source_entity_id, target_entity_id, link_type), `profile_type` on `agent_writing_profiles` (new unique constraint), `entity_id`/`valid_from`/`valid_to` on `agent_memories`.
- **Email compose/auto-send migrations**: New columns on `activities` (to_emails, cc_emails, body_text, has_attachments, attachment_count), new columns on `opportunities` (stage_manually_set, ai_summary), new JSONB column on `email_connections` (auto_send_settings), new tables `email_templates`, `ai_draft_history`, `pending_auto_sends`.

### email_connections

Renamed from `gmail_connections`. Supports Gmail and Microsoft 365 via provider abstraction. Existing Gmail connections backfilled with `provider = 'gmail'` — no re-auth required.

```sql
CREATE TABLE email_connections (
  id                      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id              UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
  provider                TEXT NOT NULL,                   -- 'gmail' | 'microsoft365'
  access_token            TEXT NOT NULL,                   -- encrypted at rest
  refresh_token           TEXT NOT NULL,                   -- encrypted at rest
  token_expires_at        TIMESTAMPTZ NOT NULL,
  user_email              TEXT NOT NULL,
  user_name               TEXT,
  sync_filters            JSONB DEFAULT '{}',              -- pattern detection rules (estimate patterns, company domains, platform senders, etc.)
  sync_interval_minutes   INTEGER DEFAULT 60,
  last_sync_history_id    TEXT,                            -- Gmail historyId or M365 deltaLink
  last_sync_at            TIMESTAMPTZ,
  ops_label_id            TEXT,                            -- Gmail label ID or M365 category ID for "OPS Pipeline" tag
  webhook_subscription_id TEXT,                            -- Gmail Pub/Sub watch ID or M365 subscription ID
  webhook_expires_at      TIMESTAMPTZ,
  ai_review_enabled       BOOLEAN DEFAULT false,           -- ongoing AI classification (feature-gated)
  ai_memory_enabled       BOOLEAN DEFAULT false,           -- memory accumulation (feature-gated)
  auto_send_settings      JSONB,                            -- auto-send config: { enabled, business_hours_start, business_hours_end, timezone, delay_min_minutes, delay_max_minutes, enabled_at }
  status                  TEXT DEFAULT 'setup_incomplete',  -- 'active' | 'paused' | 'error' | 'setup_incomplete'
  created_at              TIMESTAMPTZ DEFAULT NOW(),
  updated_at              TIMESTAMPTZ DEFAULT NOW()
);
```

`sync_filters` stores the pattern detection output as JSONB. **Note:** The DB column retains the name `sync_filters` for backward compatibility (migration 034 commented out the rename). The TypeScript type `SyncProfile` maps to this column via the `syncFilters` field on `EmailConnection`.

```json
{
  "estimateSubjectPatterns": ["Canpro Deck and Rail Estimate"],
  "companyDomains": ["canprodeckandrail.com"],
  "teamForwarders": ["jared@canprodeckandrail.com"],
  "knownPlatformSenders": ["notifications@wix-forms.com"],
  "formSubjectPatterns": ["got a new submission", "new form entry"],
  "userEmailAddresses": ["canprojack@gmail.com"],
  "aiClassificationThreshold": 0.7
}
```

`auto_send_settings` stores the per-connection auto-send configuration as JSONB:

```json
{
  "enabled": true,
  "business_hours_start": "08:00",
  "business_hours_end": "18:00",
  "timezone": "America/Toronto",
  "delay_min_minutes": 30,
  "delay_max_minutes": 60,
  "enabled_at": "2026-03-19T14:30:00Z"
}
```

Token columns (`access_token`, `refresh_token`) are accessed via service role only in API routes — not exposed to client via RLS column-level restrictions.

### gmail_scan_jobs

Tracks async inbox analysis jobs during wizard Step 2. **Note:** This table was NOT renamed during the gmail → email migration (only `gmail_connections` was renamed to `email_connections`). The table name `gmail_scan_jobs` persists in the DB and all code references.

```sql
CREATE TABLE gmail_scan_jobs (
  id                          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  connection_id               UUID NOT NULL,
  company_id                  TEXT NOT NULL,
  status                      TEXT NOT NULL DEFAULT 'pending',
  progress                    JSONB DEFAULT '{"stage": "pending", "current": 0, "total": 0, "message": "Starting scan..."}',
  result                      JSONB,
  error_message               TEXT,
  -- Phase C row-level execution lock (migration 070_phase_c_row_lock.sql).
  -- NULL on both = no lock held. See RPC functions below.
  phase_c_lock_holder_id      TEXT,
  phase_c_lock_expires_at     TIMESTAMPTZ,
  created_at                  TIMESTAMPTZ DEFAULT now(),
  updated_at                  TIMESTAMPTZ DEFAULT now()
);
```

**Phase C lock columns** (added 2026-04-19 via migration `070_phase_c_row_lock.sql`):

- `phase_c_lock_holder_id TEXT` — Opaque string identifying the Phase C runner currently processing this row. Composed by callers as `"<stage>:<uuid>"` (e.g. `"entry:9f3c…"` or `"continuation:b81a…"`) so log grepping can tell which invocation last held the lock. NULL means no lock.
- `phase_c_lock_expires_at TIMESTAMPTZ` — Wall-clock expiry for `phase_c_lock_holder_id`. Covers the crash case where a runner dies mid-chunk without calling release; the next attempt treats an expired lock as free.

Chosen over `pg_try_advisory_xact_lock` because xact-level advisory locks release at transaction end — which for chunked Phase C means per-chunk (too short — doesn't protect the multi-chunk run). Session-level advisory locks are keyed to the Postgres connection, which for a pooled service-role client is ambient and can't be released by a different invocation after a crash. Row-level with an expiry avoids both problems.

**Status values** (set by the analyze route during background processing):
- `pending` — Job created, analysis not yet started
- `analyzing_sent` — Phase 1: scanning sent emails for estimate patterns and company domains
- `detecting_platforms` — Phase 1 complete, known platform senders identified
- `classifying_ai` — Phase 2: OpenAI classifying unmatched personal emails as leads vs noise
- `analyzing_threads` — Phase 3: fetching full threads for AI-detected leads, analyzing stage placement
- `complete` — All phases done, results written
- `error` — Analysis failed (see `error_message`)

**`progress` JSONB structure** (updated at each phase transition):
```json
{
  "stage": "classifying_ai",
  "message": "Classifying 47 emails with AI...",
  "percent": 50
}
```

**`result` JSONB structure** (written on completion):
```json
{
  "estimatePattern": "Canpro Deck and Rail Estimate",
  "estimatePatternConfidence": 0.95,
  "estimateThreadCount": 23,
  "detectedSources": [
    { "type": "form_platform", "sender": "notifications@wix-forms.com", "count": 12 }
  ],
  "companyDomains": ["canprodeckandrail.com"],
  "teamForwarders": ["jared@canprodeckandrail.com"],
  "leads": [
    {
      "id": "lead-threadId123",
      "threadId": "threadId123",
      "client": { "name": "John Smith", "email": "john@example.com", "phone": null, "description": "Deck quote" },
      "stage": "qualifying",
      "stageConfidence": 0.85,
      "estimatedValue": 15000,
      "correspondenceCount": 3,
      "outboundCount": 1,
      "source": "ai",
      "sourceLabel": "AI detected",
      "enabled": true,
      "matchResult": { "existingClientId": null, "existingClientName": null, "action": "create", "confidence": 0.0 }
    }
  ],
  "totalScanned": 450
}
```

**RLS:** None — queried via service-role client only.

**Phase C lock RPC functions** (migration `070_phase_c_row_lock.sql`):

```sql
-- Atomic acquisition. Claims the lock iff currently unheld or expired.
-- Returns TRUE on success, FALSE on contention. The WHERE clause is the
-- atomicity guarantee: PostgreSQL evaluates it under row-level locking,
-- so two concurrent callers see serialized access to the same row.
CREATE FUNCTION acquire_phase_c_lock(
  p_job_id UUID,
  p_holder TEXT,
  p_lease_seconds INT DEFAULT 900
) RETURNS BOOLEAN
LANGUAGE plpgsql
AS $$
DECLARE v_rows INT;
BEGIN
  UPDATE gmail_scan_jobs
  SET phase_c_lock_holder_id = p_holder,
      phase_c_lock_expires_at = NOW() + (p_lease_seconds || ' seconds')::INTERVAL
  WHERE id = p_job_id
    AND (phase_c_lock_holder_id IS NULL
         OR phase_c_lock_expires_at < NOW());
  GET DIAGNOSTICS v_rows = ROW_COUNT;
  RETURN v_rows = 1;
END;
$$;

-- Fenced release. Only clears the lock if the supplied holder still owns
-- it. Calling twice with the same holder, or after another runner has
-- stolen an expired lock, is a no-op.
CREATE FUNCTION release_phase_c_lock(
  p_job_id UUID,
  p_holder TEXT
) RETURNS VOID
LANGUAGE plpgsql
AS $$
BEGIN
  UPDATE gmail_scan_jobs
  SET phase_c_lock_holder_id = NULL,
      phase_c_lock_expires_at = NULL
  WHERE id = p_job_id
    AND phase_c_lock_holder_id = p_holder;
END;
$$;
```

**Lease duration:** 900s (default). Chosen slightly longer than the Phase C route's 800s `maxDuration` so a hard crash between the final `runPhaseCChunks` yield and the outer `finally()` can't block a retry for much more than one invocation lifetime. The TypeScript helper in `OPS-Web/src/lib/api/services/phase-c-pipeline-helpers.ts` (`PHASE_C_LOCK_LEASE_SECONDS = 900`) must match this default.

**Fenced-release semantics:** The release UPDATE matches on both `id` and `phase_c_lock_holder_id`, so a double-release is a no-op. This is critical because the inner Phase C runner releases ahead of dispatching a continuation (so the next runner can acquire immediately instead of racing the still-held lock), then the outer route handler's `finally()` runs a second release as a crash safety net. Without fencing, the outer `finally()` could stomp on a fresh lock acquired in the interim by the next runner.

**Caller contract:** `OPS-Web/src/lib/api/services/phase-c-pipeline-helpers.ts` wraps both RPCs as `acquirePhaseCLock(supabase, jobId, "entry" | "continuation")` (returns the holder ID string or null on contention) and `releasePhaseCLock(supabase, jobId, holderId)`. Both Phase C routes (`/api/integrations/email/analyze-memory`, `/api/integrations/email/analyze-memory-continue`) use this pattern; contention means skip without retrying — duplicate dispatch is treated as benign because the holding runner will carry progress forward.

### opportunity_email_threads

Junction table linking opportunities to email thread IDs. Enables fast O(1) sync lookup ("is this thread already linked to an opportunity?") via unique index on `thread_id`.

```sql
CREATE TABLE opportunity_email_threads (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  opportunity_id  UUID NOT NULL REFERENCES opportunities(id) ON DELETE CASCADE,
  thread_id       TEXT NOT NULL,           -- Gmail threadId or M365 conversationId
  connection_id   UUID REFERENCES email_connections(id),
  created_at      TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(thread_id, connection_id)
);

CREATE INDEX idx_oet_thread ON opportunity_email_threads(thread_id);
CREATE INDEX idx_oet_opportunity ON opportunity_email_threads(opportunity_id);
```

### admin_feature_overrides

Per-company OPS admin toggles for gated AI features. Separate from the product-level feature flags — both must be true for a feature to be active. Accessed via service role only (no user-facing RLS).

```sql
CREATE TABLE admin_feature_overrides (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id   UUID NOT NULL REFERENCES companies(id),
  feature_key  TEXT NOT NULL,       -- 'ai_email_review', 'ai_email_memory'
  enabled      BOOLEAN DEFAULT false,
  enabled_by   UUID,                -- OPS admin user ID
  enabled_at   TIMESTAMPTZ,
  metadata     JSONB,               -- cost tracking, notes
  UNIQUE(company_id, feature_key)
);
```

### graph_entities

First-class entity nodes for the knowledge graph. Every person, company, project, service, and material discovered in emails becomes a UUID-keyed entity. Added in Phase C (memory bank).

```sql
CREATE TABLE graph_entities (
  id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id       UUID NOT NULL REFERENCES companies(id),
  entity_type      TEXT NOT NULL,       -- 'person', 'company', 'project', 'service', 'material', 'document'
  name             TEXT NOT NULL,       -- Display name: "John Henderson", "Vitrum Glass"
  normalized_name  TEXT NOT NULL,       -- Lowercase trimmed for dedup: "john henderson", "vitrum glass"
  email            TEXT,                -- Primary email (nullable — companies/services may not have one)
  properties       JSONB DEFAULT '{}',  -- Flexible: phone, role, address, domain, industry, etc.
  confidence       REAL DEFAULT 1.0,    -- How confident this entity is real/accurate (0.0-1.0)
  source           TEXT DEFAULT 'email_import',
  embedding        vector(1536),        -- For semantic entity matching (future fuzzy dedup)
  created_at       TIMESTAMPTZ DEFAULT now(),
  updated_at       TIMESTAMPTZ DEFAULT now(),
  UNIQUE (company_id, entity_type, normalized_name)
);
```

**Entity types:** person (keyed by email), company (keyed by domain), project (name + client), service (normalized name), material (normalized name), document (reference number).

**Entity resolution:** Deterministic — people by email address, companies by email domain. Longer/more-complete name wins on conflict. Confidence threshold 0.7 minimum.

### agent_memories

Core memory entries with pgvector embeddings. Feature-gated behind `ai_email_memory`. Uses ADD/UPDATE/NOOP conflict resolution inspired by Mem0.

```sql
CREATE TABLE agent_memories (
  id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id       UUID NOT NULL REFERENCES companies(id),
  user_id          UUID REFERENCES users(id),
  memory_type      TEXT,              -- 'fact', 'preference', 'trait', 'relationship', 'correction'
  category         TEXT,              -- 16 categories: pricing, commitment, client_preference, client_behavior, budget_signal, material_usage, supplier_pricing, supplier_relationship, employee_pattern, project_event, seasonal_pattern, service_capability, service_area, process, relationship_health, promotion
  content          TEXT,
  embedding        halfvec(1536),     -- pgvector embedding for semantic search
  confidence       FLOAT DEFAULT 1.0,
  source           TEXT,              -- 'email', 'invoice', 'project', 'user_upload', 'draft_edit'
  source_id        TEXT,
  entity_id        UUID REFERENCES graph_entities(id),  -- Phase C: links fact to entity it's about
  valid_from       TIMESTAMPTZ,       -- Phase C: temporal validity start
  valid_to         TIMESTAMPTZ,       -- Phase C: temporal validity end (null = still valid)
  created_at       TIMESTAMPTZ DEFAULT NOW(),
  last_accessed_at TIMESTAMPTZ,
  access_count     INT DEFAULT 0,
  decay_score      FLOAT DEFAULT 1.0
);
```

**Conflict resolution:** Similar fact exists (first-50-chars ilike match) → NOOP (reinforce confidence +0.05, bump access_count). New fact → ADD. Contradictory facts → keep both with valid_from/valid_to timestamps.

### agent_knowledge_graph

Entity relationship edges with temporal validity. Feature-gated behind `ai_email_memory`. Supports both legacy string-based edges and Phase C entity-ID-based edges.

```sql
CREATE TABLE agent_knowledge_graph (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id        UUID NOT NULL REFERENCES companies(id),
  -- Legacy string-based columns (deprecated, preserved for backward compat)
  subject_type      TEXT,              -- 'person', 'company', 'project', 'invoice'
  subject_id        TEXT,
  predicate         TEXT,              -- 'works_for', 'client_of', 'vendor_of', 'subtrade_of', 'quoted_for', 'uses_material', 'supplied_by', 'worked_on', 'communicates_with', 'contact_for'
  object_type       TEXT,
  object_id         TEXT,
  properties        JSONB,
  -- Phase C entity-ID-based columns
  source_entity_id  UUID REFERENCES graph_entities(id),  -- Source node
  target_entity_id  UUID REFERENCES graph_entities(id),  -- Target node
  link_type         TEXT DEFAULT 'extracted',             -- 'extracted', 'manual', 'inferred'
  -- Temporal
  confidence        NUMERIC,
  valid_from        TIMESTAMPTZ,
  valid_to          TIMESTAMPTZ,
  created_at        TIMESTAMPTZ DEFAULT NOW()
);
-- Constraints: (company_id, subject_type, subject_id, predicate, object_type, object_id) for legacy
-- Constraint: akg_entity_edge_unique (company_id, source_entity_id, predicate, target_entity_id) for Phase C
```

**Relationship predicates:** works_for (person→company), contact_for (person→company), client_of (company→company), vendor_of (company→company), subtrade_of (company→company), quoted_for (person/company→service), uses_material (service→material), supplied_by (material→company), worked_on (person→project), communicates_with (person→person).

### agent_writing_profiles

Per-user per-company per-relationship-type communication style profiles. Feature-gated behind `ai_email_memory`. Phase C builds profiles per relationship type (10 types).

```sql
CREATE TABLE agent_writing_profiles (
  id                      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id              UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
  user_id                 UUID NOT NULL REFERENCES users(id),
  profile_type            TEXT NOT NULL DEFAULT 'general',  -- Phase C: relationship type
  formality_score         FLOAT,
  avg_sentence_length     FLOAT,
  greeting_patterns       JSONB,
  closing_patterns        JSONB,
  vocabulary_preferences  JSONB,   -- Also stores common_phrases, hedging_tendency, punctuation_habits
  tone_traits             JSONB,
  emails_analyzed         INT DEFAULT 0,
  updated_at              TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(company_id, user_id, profile_type)
);
```

**Profile types:** client_new_inquiry, client_quoting, client_active_project, client_followup, vendor_ordering, vendor_inquiry, subtrade_coordination, warranty_claim, internal, general. Clustered for galaxy visualization: client, vendor, subtrade, internal, general.

### email_templates

Company-scoped email templates with merge field support. Used by the compose flow and AI draft generation.

```sql
CREATE TABLE email_templates (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  subject TEXT NOT NULL DEFAULT '',
  body TEXT NOT NULL DEFAULT '',
  category TEXT NOT NULL CHECK (category IN ('follow_up','scheduling','estimate','invoice','introduction','general')),
  sort_order INT NOT NULL DEFAULT 0,
  is_active BOOLEAN NOT NULL DEFAULT true,
  created_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
```

**RLS:** Company-scoped (SELECT/INSERT/UPDATE/DELETE).

**Index:** `(company_id, category, sort_order) WHERE is_active = true`

**Merge fields:** `{{client_name}}`, `{{project_title}}`, `{{company_name}}` — resolved at send time by the compose/draft layer.

### ai_draft_history

Tracks AI-generated email drafts for edit tracking and writing profile learning. Each draft records the original AI output and the final user-edited version, enabling edit distance computation and auto-send confidence scoring.

```sql
CREATE TABLE ai_draft_history (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id UUID NOT NULL,
  user_id UUID NOT NULL,
  opportunity_id UUID,
  connection_id UUID,
  thread_id TEXT,
  original_draft TEXT NOT NULL,
  final_version TEXT,
  status TEXT NOT NULL DEFAULT 'drafted' CHECK (status IN ('drafted','sent','discarded')),
  sent_without_changes BOOLEAN DEFAULT false,
  edit_distance INT DEFAULT 0,
  changes_made JSONB DEFAULT '{}',
  sent_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
```

- `edit_distance`: Word-level Levenshtein distance between `original_draft` and `final_version`.
- `changes_made`: Structured diff — `{ greeting?: {from, to}, closing?: {from, to}, tone?: string }`.
- When `sent_without_changes` reaches 95% over 20+ drafts, auto-send is suggested to the user.

### pending_auto_sends

Auto-send queue for AI-generated email drafts held for randomized delay before sending. Business hours enforced (default 8am-6pm in user's timezone). Processed by cron job `/api/cron/auto-send` every 5 minutes.

```sql
CREATE TABLE pending_auto_sends (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id UUID NOT NULL,
  connection_id UUID NOT NULL,
  opportunity_id UUID,
  thread_id TEXT,
  in_reply_to TEXT,
  to_emails TEXT[] DEFAULT '{}',
  cc_emails TEXT[] DEFAULT '{}',
  subject TEXT NOT NULL,
  draft_text TEXT NOT NULL,
  draft_history_id UUID REFERENCES ai_draft_history(id),
  scheduled_send_at TIMESTAMPTZ NOT NULL,
  status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','sent','cancelled','failed')),
  retry_count INT NOT NULL DEFAULT 0,
  sent_at TIMESTAMPTZ,
  cancelled_at TIMESTAMPTZ,
  error TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
```

- **Delay:** Randomized between `delay_min_minutes` and `delay_max_minutes` from `email_connections.auto_send_settings` (default 30-60 min).
- **Business hours:** Sends only within `business_hours_start`-`business_hours_end` in the user's timezone. If scheduled outside hours, deferred to next business window.
- **Retries:** Max 3 retries, then permanently set to `failed`.
- **Cancellation:** User can cancel pending sends from the UI before `scheduled_send_at`.

### Modified Tables: opportunities

New columns added to `opportunities` for email correspondence tracking:

```sql
ALTER TABLE opportunities ADD COLUMN correspondence_count INT DEFAULT 0;
ALTER TABLE opportunities ADD COLUMN outbound_count INT DEFAULT 0;
ALTER TABLE opportunities ADD COLUMN inbound_count INT DEFAULT 0;
ALTER TABLE opportunities ADD COLUMN last_inbound_at TIMESTAMPTZ;
ALTER TABLE opportunities ADD COLUMN last_outbound_at TIMESTAMPTZ;
ALTER TABLE opportunities ADD COLUMN last_message_direction TEXT;    -- 'in' | 'out'
ALTER TABLE opportunities ADD COLUMN ai_stage_confidence FLOAT;
ALTER TABLE opportunities ADD COLUMN ai_stage_signals TEXT[];
ALTER TABLE opportunities ADD COLUMN detected_value INT;
ALTER TABLE opportunities ADD COLUMN stage_manually_set BOOLEAN NOT NULL DEFAULT false;
ALTER TABLE opportunities ADD COLUMN ai_summary TEXT;
```

- `stage_manually_set`: Set to `true` when user manually drags card to new stage; prevents AI/deterministic stage override. Cleared to `false` when new inbound email arrives (situation evolved, AI can re-evaluate).
- `ai_summary`: 1-2 sentence AI-generated summary of the opportunity, cached and refreshed each sync cycle that touches the thread via `evaluateStagesWithSummary()`.

These columns are used by the sync engine's correspondence-count stage rules (free tier) and AI stage evaluation (gated tier).

### Note: companies.industry Column

The `companies` table has an `industries` column (TEXT array, from migration 004) but does **not** have an `industry` (singular) column. The email pipeline code does `.select("name, industry")` on companies, but PostgREST returns `null` for the nonexistent column. The code falls back to `"trades"` via `(company?.industry as string) || "trades"`. No migration was created to add this column. If per-company industry classification is needed in the future, either use the existing `industries` array or add an `industry TEXT` column via a new migration.

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

Seeded with ~100+ common noise sources across categories.

### email_threads (Inbox v2, migration 071 — 2026-04-20)

Per-thread state for the rebuilt inbox. Every email the company sees gets a
row here — denormalized so list queries are a single-table scan.

```sql
CREATE TABLE public.email_threads (
  id                          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id                  uuid NOT NULL REFERENCES companies(id),
  connection_id               uuid NOT NULL REFERENCES email_connections(id),
  provider_thread_id          text NOT NULL,          -- Gmail threadId | M365 conversationId

  -- Primary classification (exactly one)
  primary_category            text NOT NULL DEFAULT 'OTHER'
    CHECK (primary_category IN ('LEAD','CLIENT','VENDOR','SUBTRADE','PLATFORM_BID',
                                 'LEGAL','JOB_SEEKER','COLLECTIONS','MARKETING',
                                 'RECEIPT','PERSONAL','INTERNAL','OTHER')),
  category_confidence         numeric(3,2) DEFAULT 0.0,
  category_classified_at      timestamptz,
  category_classifier_version text DEFAULT 'v1',
  category_manually_set       boolean NOT NULL DEFAULT false,

  -- Secondary labels (multi)
  labels                      text[] NOT NULL DEFAULT '{}',

  -- Triage
  archived_at                 timestamptz,
  snoozed_until               timestamptz,
  priority_score              numeric(4,2) DEFAULT 0.0,
  ai_summary                  text,

  -- Denormalized summary (updated from latest message on each sync tick)
  subject                     text,
  participants                text[] DEFAULT '{}',
  first_message_at            timestamptz NOT NULL,
  last_message_at             timestamptz NOT NULL,
  message_count               int NOT NULL DEFAULT 0,
  unread_count                int NOT NULL DEFAULT 0,
  latest_direction            text CHECK (latest_direction IN ('inbound','outbound')),
  latest_sender_email         text,
  latest_sender_name          text,
  latest_snippet              text,

  -- Linkage (nullable — VENDOR/LEGAL/etc. threads won't have these)
  opportunity_id              uuid REFERENCES opportunities(id),
  client_id                   uuid REFERENCES clients(id),

  created_at                  timestamptz NOT NULL DEFAULT now(),
  updated_at                  timestamptz NOT NULL DEFAULT now(),

  CONSTRAINT email_threads_unique_provider UNIQUE (connection_id, provider_thread_id)
);
```

**Indexes (migration 071):**
- `idx_email_threads_company_lastmsg` — `(company_id, last_message_at DESC) WHERE archived_at IS NULL AND snoozed_until IS NULL` — drives the Everything rail
- `idx_email_threads_company_category` — `(company_id, primary_category, last_message_at DESC) WHERE archived_at IS NULL` — drives category filter chips
- `idx_email_threads_snoozed` — `(snoozed_until) WHERE snoozed_until IS NOT NULL` — drives `/api/cron/unsnooze`
- `idx_email_threads_opportunity` — `(opportunity_id) WHERE opportunity_id IS NOT NULL` — back-reference from pipeline

The 13 primary categories and the 6 secondary labels (`URGENT`,
`AWAITING_REPLY`, `HAS_ATTACHMENT`, `HAS_QUOTE`, `HAS_INVOICE`,
`FROM_NEW_SENDER`) are enforced only in application code (the CHECK covers
primary only; labels are an application-level contract).

### email_thread_category_corrections (migration 071)

Learning feedback for Phase C. Every time the user recategorizes a thread
manually, we record the from/to categories plus signals (sender email,
domain, participant hash, subject keywords) so the classifier can fan out
the correction to similar threads.

```sql
CREATE TABLE public.email_thread_category_corrections (
  id                   uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id           uuid NOT NULL REFERENCES companies(id),
  thread_id            uuid NOT NULL REFERENCES email_threads(id) ON DELETE CASCADE,
  user_id              uuid NOT NULL REFERENCES users(id),
  from_category        text NOT NULL,
  to_category          text NOT NULL,
  sender_email         text,
  sender_domain        text,
  participants_hash    text,
  subject_keywords     text[],
  note                 text,
  applied_to_similar   boolean NOT NULL DEFAULT false,
  similar_count        int NOT NULL DEFAULT 0,
  created_at           timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX idx_corrections_company_domain
  ON email_thread_category_corrections(company_id, sender_domain)
  WHERE sender_domain IS NOT NULL;
```

### Column additions (migration 071)

```sql
-- First-archive write-back preference per email connection
ALTER TABLE email_connections
  ADD COLUMN archive_writeback_preference text
    CHECK (archive_writeback_preference IN ('ask','archive_in_gmail','mark_read_only','ops_only'))
    DEFAULT 'ask';

-- Per-message classifier provenance
ALTER TABLE activities
  ADD COLUMN classified_at timestamptz,
  ADD COLUMN classifier_version text;
```

### Phase C category autonomy (JSONB on email_connections — no new columns)

Per-primary-category autonomy lives under
`email_connections.auto_send_settings.category_autonomy`, keyed by
`primary:<CATEGORY>`. Example stored value:

```jsonb
{
  "primary:LEAD":         "auto_draft",
  "primary:CLIENT":       "auto_send",
  "primary:VENDOR":       "auto_draft",
  "primary:PLATFORM_BID": "auto_archive",
  "primary:LEGAL":        "draft_on_request",
  "primary:RECEIPT":      "auto_archive",
  "client_new_inquiry":   "auto_send",       // legacy per-relationship key
  "vendor_ordering":      "auto_draft"       // legacy per-relationship key
}
```

The legacy per-relationship keys (`client_new_inquiry`, `vendor_ordering`,
etc.) continue to drive the ai-draft-service writing-profile graduation
checks. Inbox v2 adds the `primary:*` namespace alongside — no migration
touches this column since it's JSONB.

### RPC get_inbox_density_per_client (migration 073)

Used by the Intel galaxy to size client-node thread-density halos.

```sql
CREATE OR REPLACE FUNCTION public.get_inbox_density_per_client(p_company_id uuid)
RETURNS TABLE (client_id uuid, thread_count int, last_message_at timestamptz)
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = public
AS $$
  SELECT client_id, COUNT(*)::int, MAX(last_message_at)
  FROM public.email_threads
  WHERE company_id = p_company_id
    AND client_id IS NOT NULL
    AND archived_at IS NULL
  GROUP BY client_id;
$$;
```

### RLS Policies (Email Integration)

All new tables require Row-Level Security:

```sql
-- email_connections: company-scoped
ALTER TABLE email_connections ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can view own company connections"
  ON email_connections FOR SELECT USING (company_id = auth.jwt()->>'company_id');
CREATE POLICY "Users can manage own company connections"
  ON email_connections FOR ALL USING (company_id = auth.jwt()->>'company_id');

-- opportunity_email_threads: via opportunity's company
ALTER TABLE opportunity_email_threads ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Company-scoped thread access"
  ON opportunity_email_threads FOR ALL
  USING (opportunity_id IN (SELECT id FROM opportunities WHERE company_id = auth.jwt()->>'company_id'));

-- admin_feature_overrides: OPS admin only (service role)
ALTER TABLE admin_feature_overrides ENABLE ROW LEVEL SECURITY;
-- No user-facing RLS — accessed via service role in admin API routes only

-- graph_entities: company-scoped (Phase C)
ALTER TABLE graph_entities ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Company members can view their entities"
  ON graph_entities FOR SELECT USING (company_id = (auth.jwt()->>'company_id')::uuid);
CREATE POLICY "Service role has full access to entities"
  ON graph_entities FOR ALL USING (auth.role() = 'service_role');

-- agent_memories, agent_knowledge_graph, agent_writing_profiles: company-scoped
ALTER TABLE agent_memories ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Company-scoped memories"
  ON agent_memories FOR ALL USING (company_id = auth.jwt()->>'company_id');

ALTER TABLE agent_knowledge_graph ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Company-scoped knowledge graph"
  ON agent_knowledge_graph FOR ALL USING (company_id = auth.jwt()->>'company_id');

ALTER TABLE agent_writing_profiles ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Company-scoped writing profiles"
  ON agent_writing_profiles FOR ALL USING (company_id = auth.jwt()->>'company_id');
```

**End of Data Architecture Documentation**
