# 03: Data Architecture

**Last Updated**: February 18, 2026
**Status**: Comprehensive Reference
**Purpose**: Complete data layer specification for OPS iOS/Android applications

---

## Table of Contents

1. [Overview](#overview)
2. [SwiftData Models (9 Entities)](#swiftdata-models-9-entities)
3. [BubbleFields Constants](#bubblefields-constants)
4. [Data Transfer Objects (DTOs)](#data-transfer-objects-dtos)
5. [Soft Delete Strategy](#soft-delete-strategy)
6. [Computed Properties & Business Logic](#computed-properties--business-logic)
7. [Migration History](#migration-history)
8. [Query Predicates & Filtering](#query-predicates--filtering)
9. [Defensive Programming Patterns](#defensive-programming-patterns)

---

## Overview

### Data Layer Architecture

The OPS data layer follows a **three-tier architecture**:

1. **SwiftData Models**: Persistent entities stored locally (iOS: SwiftData, Android: Room)
2. **DTOs (Data Transfer Objects)**: API response mapping layer
3. **BubbleFields Constants**: Byte-perfect field name mappings to Bubble.io backend

### Core Principles

- **Soft Delete**: All entities support `deletedAt: Date?` for reversible deletion
- **Offline-First**: All data persists locally with sync tracking
- **Type Safety**: DTOs handle field name mapping and type conversion
- **Backward Compatibility**: DTOs handle API changes (e.g., "Scheduled" → "Booked")

### The 9 Core Entities

1. **Project** - Central entity for field crew work
2. **ProjectTask** - Task-based scheduling (Nov 2025 migration)
3. **CalendarEvent** - Single source of truth for calendar display
4. **TaskType** - Reusable task templates per company
5. **Client** - Customer/client management
6. **SubClient** - Additional client contacts
7. **User** - Team members with role-based permissions
8. **Company** - Organization/subscription management
9. **TeamMember** - Lightweight user cache (company-scoped)

**Additional Entities**:
- **OpsContact** - Support contact information from Bubble option set

---

## SwiftData Models (9 Entities)

### 1. Project

**Purpose**: Central entity representing a construction/trade project.

**Complete Property List**:

```swift
@Model
final class Project: Identifiable {
    // MARK: - Identity
    var id: String                          // Bubble _id
    var title: String                       // Project name
    var companyId: String                   // Parent company
    var clientId: String?                   // Client Bubble ID

    // MARK: - Location
    var address: String?                    // Full formatted address
    var latitude: Double?                   // Coordinate (validated -90 to 90)
    var longitude: Double?                  // Coordinate (validated -180 to 180)

    // MARK: - Stored Dates (from API)
    var startDate: Date?                    // Project start from API
    var endDate: Date?                      // Project end from API
    var duration: Int?                      // Duration in days from API

    // MARK: - Project Details
    var status: Status                      // RFQ, Estimated, Accepted, InProgress, Completed, Closed, Archived
    var notes: String?                      // Team notes
    var projectDescription: String?         // Project description
    var allDay: Bool                        // All-day scheduling flag

    // MARK: - Images (comma-separated strings)
    var projectImagesString: String = ""    // S3 URLs joined by ","
    var unsyncedImagesString: String = ""   // Local URLs pending upload

    // MARK: - Team (comma-separated string)
    var teamMemberIdsString: String = ""    // User IDs joined by ","

    // MARK: - Sync Metadata
    var lastSyncedAt: Date?                 // Last successful sync
    var needsSync: Bool = false             // Pending changes flag
    var syncPriority: Int = 1               // 1-3, higher = more urgent
    var deletedAt: Date?                    // Soft delete timestamp

    // MARK: - Relationships
    @Relationship(deleteRule: .nullify)
    var client: Client?                     // Link to client entity

    @Relationship(deleteRule: .noAction)
    var teamMembers: [User]                 // Team member references

    @Relationship(deleteRule: .cascade, inverse: \ProjectTask.project)
    var tasks: [ProjectTask] = []           // Child tasks

    // MARK: - Transient Properties (not persisted)
    @Transient var lastTapped: Date?        // UI interaction tracking
    @Transient var coordinatorData: [String: Any]?  // Map coordinator data
}
```

**Computed Properties**:

```swift
// MARK: - Task-Based Scheduling (Nov 2025 Migration)

/// Project start date computed from earliest task
var computedStartDate: Date? {
    tasks.compactMap { $0.calendarEvent?.startDate }.min()
}

/// Project end date computed from latest task
var computedEndDate: Date? {
    tasks.compactMap { $0.calendarEvent?.endDate }.max()
}

/// Client name from relationship
var effectiveClientName: String {
    client?.name ?? ""
}

/// Client email (checks client, then sub-clients)
var effectiveClientEmail: String? {
    if let email = client?.email, !email.isEmpty {
        return email
    }
    return client?.subClients.first(where: { $0.email != nil })?.email
}

/// Client phone (checks client, then sub-clients)
var effectiveClientPhone: String? {
    if let phone = client?.phoneNumber, !phone.isEmpty {
        return phone
    }
    return client?.subClients.first(where: { $0.phoneNumber != nil })?.phoneNumber
}

/// Location coordinate with validation
var coordinate: CLLocationCoordinate2D? {
    guard let lat = latitude, let lon = longitude else { return nil }
    let validLat = max(-90.0, min(90.0, lat))
    let validLon = max(-180.0, min(180.0, lon))
    // Reject 0,0 as likely invalid
    if abs(validLat) < 0.0001 && abs(validLon) < 0.0001 { return nil }
    return CLLocationCoordinate2D(latitude: validLat, longitude: validLon)
}
```

**Array Accessors**:

```swift
func getTeamMemberIds() -> [String] {
    teamMemberIdsString.isEmpty ? [] : teamMemberIdsString.components(separatedBy: ",")
}

func setTeamMemberIds(_ ids: [String]) {
    teamMemberIdsString = ids.joined(separator: ",")
}

func getProjectImageURLs() -> [String] {
    projectImagesString.isEmpty ? [] : projectImagesString.components(separatedBy: ",")
}

func setProjectImageURLs(_ urls: [String]) {
    projectImagesString = urls.joined(separator: ",")
}
```

**Key Methods**:

```swift
/// Update project team members from all tasks
/// Returns true if changes were made
@discardableResult
func updateTeamMembersFromTasks(in context: ModelContext) -> Bool {
    // Collect all unique team member IDs from tasks
    var allIds = Set<String>()
    for task in tasks {
        allIds.formUnion(task.getTeamMemberIds())
    }

    // Check if update needed
    let currentIds = Set(getTeamMemberIds())
    if currentIds == allIds { return false }

    // Fetch User objects and update
    let predicate = #Predicate<User> { allIds.contains($0.id) }
    let users = try? context.fetch(FetchDescriptor<User>(predicate: predicate))
    teamMembers = users ?? []
    setTeamMemberIds(Array(allIds))
    return true
}
```

---

### 2. ProjectTask

**Purpose**: Task within a project, linked to CalendarEvent for scheduling.

**Complete Property List**:

```swift
@Model
final class ProjectTask {
    // MARK: - Identity
    var id: String                          // Bubble _id
    var projectId: String                   // Parent project
    var companyId: String                   // Parent company
    var taskTypeId: String                  // Reference to TaskType

    // MARK: - Task Details
    var customTitle: String?                // Optional override of taskType.display
    var taskNotes: String?                  // Task-specific notes
    var status: TaskStatus                  // Booked, InProgress, Completed, Cancelled
    var taskColor: String                   // Hex color code (e.g., "#59779F")

    // MARK: - Ordering
    var taskIndex: Int?                     // Legacy index (based on startDate)
    var displayOrder: Int = 0               // Display order within project

    // MARK: - Team (comma-separated string)
    var teamMemberIdsString: String = ""    // User IDs joined by ","

    // MARK: - Calendar Integration
    var calendarEventId: String?            // Link to CalendarEvent

    // MARK: - Sync Metadata
    var lastSyncedAt: Date?                 // Last successful sync
    var needsSync: Bool = false             // Pending changes flag
    var deletedAt: Date?                    // Soft delete timestamp

    // MARK: - Relationships
    @Relationship(deleteRule: .nullify)
    var project: Project?                   // Parent project

    @Relationship(deleteRule: .cascade)
    var calendarEvent: CalendarEvent?       // Linked calendar event

    @Relationship(deleteRule: .nullify)
    var taskType: TaskType?                 // Task template

    @Relationship(deleteRule: .noAction)
    var teamMembers: [User] = []            // Assigned team members
}
```

**TaskStatus Enum**:

```swift
enum TaskStatus: String, Codable, CaseIterable {
    case booked = "Booked"          // Formerly "Scheduled"
    case inProgress = "In Progress"
    case completed = "Completed"
    case cancelled = "Cancelled"

    // Custom decoder for backward compatibility
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)

        // Map legacy "Scheduled" to "Booked"
        if rawValue == "Scheduled" {
            self = .booked
        } else if let status = TaskStatus(rawValue: rawValue) {
            self = status
        } else {
            throw DecodingError.dataCorruptedError(...)
        }
    }

    var color: Color {
        switch self {
        case .booked: return Color("StatusAccepted")
        case .inProgress: return Color("StatusInProgress")
        case .completed: return Color("StatusCompleted")
        case .cancelled: return Color("StatusInactive")
        }
    }
}
```

**Computed Properties**:

```swift
/// Display title (custom or from TaskType)
var displayTitle: String {
    if let customTitle = customTitle, !customTitle.isEmpty {
        return customTitle
    }
    return taskType?.display ?? "Task"
}

/// Effective color (from TaskType or taskColor)
var effectiveColor: String {
    if let typeColor = taskType?.color, !typeColor.isEmpty {
        return typeColor
    }
    return taskColor
}

/// Scheduled date from calendar event
var scheduledDate: Date? {
    calendarEvent?.startDate
}

/// Completion date from calendar event
var completionDate: Date? {
    calendarEvent?.endDate
}

/// Check if task is overdue
var isOverdue: Bool {
    guard status != .completed && status != .cancelled,
          let endDate = completionDate else { return false }
    return Date() > endDate
}
```

---

### 3. CalendarEvent

**Purpose**: Single source of truth for all calendar display. As of Nov 2025, all events are task-based.

**Complete Property List**:

```swift
@Model
final class CalendarEvent {
    // MARK: - Identity
    var id: String                          // Bubble _id
    var companyId: String                   // Parent company
    var projectId: String                   // Parent project
    var taskId: String?                     // Link to task (required post-migration)

    // MARK: - Display
    var title: String                       // Event title
    var color: String                       // Hex color code

    // MARK: - Dates
    var startDate: Date?                    // Start date/time
    var endDate: Date?                      // End date/time
    var duration: Int                       // Days (calculated from dates)

    // MARK: - Team (comma-separated string)
    var teamMemberIdsString: String = ""    // User IDs joined by ","

    // MARK: - Sync Metadata
    var lastSyncedAt: Date?                 // Last successful sync
    var needsSync: Bool = false             // Pending changes flag
    var deletedAt: Date?                    // Soft delete timestamp

    // MARK: - Relationships
    @Relationship(deleteRule: .nullify)
    var project: Project?                   // Parent project

    @Relationship(deleteRule: .nullify, inverse: \ProjectTask.calendarEvent)
    var task: ProjectTask?                  // Linked task

    @Relationship(deleteRule: .noAction)
    var teamMembers: [User] = []            // Assigned team members
}
```

**Computed Properties**:

```swift
/// Check if event spans multiple days
var isMultiDay: Bool {
    guard let start = startDate, let end = endDate else { return false }
    return !Calendar.current.isDate(start, inSameDayAs: end)
}

/// All dates this event spans
var spannedDates: [Date] {
    guard let start = startDate, let end = endDate else { return [] }
    var dates: [Date] = []
    let calendar = Calendar.current
    var current = calendar.startOfDay(for: start)
    let endDay = calendar.startOfDay(for: end)

    // Single-day event
    if calendar.isDate(start, inSameDayAs: end) {
        return [current]
    }

    // Multi-day event
    while current <= endDay {
        dates.append(current)
        current = calendar.date(byAdding: .day, value: 1, to: current) ?? current
    }
    return dates
}
```

---

### 4. TaskType

**Purpose**: Reusable task templates with visual identity.

**Complete Property List**:

```swift
@Model
final class TaskType: Identifiable {
    // MARK: - Identity
    var id: String                          // Bubble _id
    var companyId: String                   // Parent company

    // MARK: - Display
    var display: String                     // Display name (e.g., "Framing")
    var color: String                       // Hex color code
    var icon: String?                       // SF Symbol name

    // MARK: - Metadata
    var isDefault: Bool                     // System-provided vs custom
    var displayOrder: Int = 0               // Sort order

    // MARK: - Sync Metadata
    var lastSyncedAt: Date?                 // Last successful sync
    var needsSync: Bool = false             // Pending changes flag
    var deletedAt: Date?                    // Soft delete timestamp

    // MARK: - Relationships
    @Relationship(deleteRule: .nullify, inverse: \ProjectTask.taskType)
    var tasks: [ProjectTask] = []           // Tasks using this type
}
```

**Default Task Types**:

```swift
static func createDefaults(companyId: String) -> [TaskType] {
    return [
        TaskType(id: UUID().uuidString, display: "Site Estimate",
                 color: "#A5B368", companyId: companyId, isDefault: true, icon: "clipboard.fill"),
        TaskType(id: UUID().uuidString, display: "Quote/Proposal",
                 color: "#59779F", companyId: companyId, isDefault: true, icon: "doc.text.fill"),
        TaskType(id: UUID().uuidString, display: "Material Order",
                 color: "#C4A868", companyId: companyId, isDefault: true, icon: "shippingbox.fill"),
        TaskType(id: UUID().uuidString, display: "Installation",
                 color: "#931A32", companyId: companyId, isDefault: true, icon: "hammer.fill"),
        TaskType(id: UUID().uuidString, display: "Inspection",
                 color: "#7B68A6", companyId: companyId, isDefault: true, icon: "magnifyingglass"),
        TaskType(id: UUID().uuidString, display: "Completion",
                 color: "#4A4A4A", companyId: companyId, isDefault: true, icon: "checkmark.circle.fill")
    ]
}
```

---

### 5. Client

**Purpose**: Customer/client management with sub-client support.

**Complete Property List**:

```swift
@Model
final class Client: Identifiable {
    // MARK: - Identity
    var id: String                          // Bubble _id
    var companyId: String?                  // Parent company

    // MARK: - Client Info
    var name: String                        // Client name
    var email: String?                      // Email address
    var phoneNumber: String?                // Phone number
    var notes: String?                      // Client notes

    // MARK: - Address
    var address: String?                    // Full formatted address
    var latitude: Double?                   // Coordinate
    var longitude: Double?                  // Coordinate

    // MARK: - Media
    var profileImageURL: String?            // Avatar/thumbnail S3 URL

    // MARK: - Sync Metadata
    var lastSyncedAt: Date?                 // Last successful sync
    var needsSync: Bool = false             // Pending changes flag
    var createdAt: Date?                    // Creation timestamp from Bubble
    var deletedAt: Date?                    // Soft delete timestamp

    // MARK: - Relationships
    @Relationship(deleteRule: .noAction, inverse: \Project.client)
    var projects: [Project]                 // Projects for this client

    @Relationship(deleteRule: .cascade)
    var subClients: [SubClient]             // Additional contacts
}
```

**Computed Properties**:

```swift
var coordinate: CLLocationCoordinate2D? {
    guard let lat = latitude, let lng = longitude else { return nil }
    return CLLocationCoordinate2D(latitude: lat, longitude: lng)
}

var hasContactInfo: Bool {
    email != nil || phoneNumber != nil
}
```

---

### 6. SubClient

**Purpose**: Additional contacts for a client.

**Complete Property List**:

```swift
@Model
final class SubClient: Identifiable {
    // MARK: - Identity
    var id: String                          // Bubble _id

    // MARK: - Contact Info
    var name: String                        // Contact name
    var title: String?                      // Job title/role
    var email: String?                      // Email address
    var phoneNumber: String?                // Phone number
    var address: String?                    // Address

    // MARK: - Metadata
    var createdAt: Date                     // Creation timestamp
    var updatedAt: Date                     // Last update timestamp

    // MARK: - Sync Metadata
    var lastSyncedAt: Date?                 // Last successful sync
    var needsSync: Bool = false             // Pending changes flag
    var deletedAt: Date?                    // Soft delete timestamp

    // MARK: - Relationships
    var client: Client?                     // Parent client
}
```

**Computed Properties**:

```swift
/// Display name with title
var displayName: String {
    if let title = title, !title.isEmpty {
        return "\(name) - \(title)"
    }
    return name
}

/// Initials for avatar
var initials: String {
    let names = name.components(separatedBy: " ")
    let first = names.first?.first?.uppercased() ?? ""
    let last = names.count > 1 ? names.last?.first?.uppercased() ?? "" : ""
    return "\(first)\(last)"
}
```

---

### 7. User

**Purpose**: Team member with role-based permissions.

**Complete Property List**:

```swift
@Model
final class User {
    // MARK: - Identity
    var id: String                          // Bubble _id
    var companyId: String?                  // Parent company

    // MARK: - Personal Info
    var firstName: String                   // First name
    var lastName: String                    // Last name
    var email: String?                      // Email address
    var phone: String?                      // Phone number
    var homeAddress: String?                // Home address

    // MARK: - Profile
    var profileImageURL: String?            // Avatar S3 URL
    var profileImageData: Data?             // Cached avatar data
    var userColor: String?                  // User's unique color (hex)

    // MARK: - Role & Permissions
    var role: UserRole                      // .admin, .officeCrew, .fieldCrew
    var isCompanyAdmin: Bool = false        // Determined by company.adminIds
    var userType: UserType?                 // Company, Employee, Client, Admin

    // MARK: - Onboarding
    var hasCompletedAppOnboarding: Bool = false  // Onboarding flow completed
    var hasCompletedAppTutorial: Bool = false    // Interactive tutorial completed
    var devPermission: Bool = false              // Dev features enabled

    // MARK: - Location (optional)
    var latitude: Double?                   // Current location
    var longitude: Double?                  // Current location
    var locationName: String?               // Location description

    // MARK: - Client Mode (future)
    var clientId: String?                   // If user is a client
    var isActive: Bool?                     // Active status

    // MARK: - Stripe Integration
    var stripeCustomerId: String?           // Stripe customer ID (for plan holders)

    // MARK: - Push Notifications
    var deviceToken: String?                // APNs device token

    // MARK: - Sync Metadata
    var lastSyncedAt: Date?                 // Last successful sync
    var needsSync: Bool = false             // Pending changes flag
    var deletedAt: Date?                    // Soft delete timestamp

    // MARK: - Relationships
    @Relationship(deleteRule: .noAction, inverse: \Project.teamMembers)
    var assignedProjects: [Project]         // Projects user is assigned to
}
```

**UserRole Enum**:

```swift
enum UserRole: String, Codable {
    case admin = "Admin"                    // Full access
    case officeCrew = "Office Crew"         // Management access
    case fieldCrew = "Field Crew"           // Limited access
}
```

**Role Hierarchy**:

```
Admin (company.adminIds check)
├── Billing/subscriptions
├── Team member termination
└── All Office Crew permissions

Office Crew
├── Client/project/task CRUD
├── Job Board access
└── Analytics viewing

Field Crew
├── View assigned projects
└── Update task status
```

**Computed Properties**:

```swift
var fullName: String {
    "\(firstName) \(lastName)"
}

func isPlanHolder(for company: Company) -> Bool {
    guard let userStripeId = stripeCustomerId,
          let companyStripeId = company.stripeCustomerId else {
        return false
    }
    return userStripeId == companyStripeId
}
```

---

### 8. Company

**Purpose**: Organization entity managing subscription and defaults.

**Complete Property List**:

```swift
@Model
final class Company {
    // MARK: - Identity
    var id: String                          // Bubble _id
    var name: String                        // Company name
    var externalId: String?                 // Bubble's companyId field

    // MARK: - Company Info
    var companyDescription: String?         // Description
    var website: String?                    // Website URL
    var phone: String?                      // Phone number
    var email: String?                      // Email address

    // MARK: - Location
    var address: String?                    // Full formatted address
    var latitude: Double?                   // Coordinate
    var longitude: Double?                  // Coordinate

    // MARK: - Business Hours
    var openHour: String?                   // Opening time
    var closeHour: String?                  // Closing time

    // MARK: - Branding
    var logoURL: String?                    // Logo S3 URL
    var logoData: Data?                     // Cached logo data
    var defaultProjectColor: String = "#9CA3AF"  // Default project color (hex)

    // MARK: - Company Details
    var industryString: String = ""         // Comma-separated industries
    var companySize: String?                // Company size category
    var companyAge: String?                 // Company age category
    var referralMethod: String?             // How they heard about OPS

    // MARK: - Team Management (comma-separated strings)
    var projectIdsString: String = ""       // Project IDs joined by ","
    var teamIdsString: String = ""          // Team member IDs joined by ","
    var adminIdsString: String = ""         // Admin user IDs joined by ","
    var accountHolderId: String?            // Company owner user ID

    // MARK: - Subscription Management
    var subscriptionStatus: String?         // "trial", "active", "grace", "expired", "cancelled"
    var subscriptionPlan: String?           // "trial", "starter", "team", "business"
    var subscriptionEnd: Date?              // Subscription expiration
    var subscriptionPeriod: String?         // "Monthly", "Annual"
    var maxSeats: Int = 10                  // Maximum team seats
    var seatedEmployeeIds: String = ""      // Comma-separated seated user IDs
    var seatGraceStartDate: Date?           // Grace period start
    var subscriptionIdsJson: String?        // JSON array of subscription objects

    // MARK: - Trial Management
    var trialStartDate: Date?               // Trial start
    var trialEndDate: Date?                 // Trial end

    // MARK: - Add-Ons
    var hasPrioritySupport: Bool = false    // Priority support purchased
    var dataSetupPurchased: Bool = false    // Data setup purchased
    var dataSetupCompleted: Bool = false    // Data setup completed
    var dataSetupScheduledDate: Date?       // Data setup appointment

    // MARK: - Stripe Integration
    var stripeCustomerId: String?           // Stripe customer ID

    // MARK: - Sync Metadata
    var lastSyncedAt: Date?                 // Last successful sync
    var needsSync: Bool = false             // Pending changes flag
    var deletedAt: Date?                    // Soft delete timestamp
    var teamMembersSynced: Bool = false     // Team members sync flag

    // MARK: - Relationships
    @Relationship(deleteRule: .cascade)
    var teamMembers: [TeamMember] = []      // Lightweight team cache

    @Relationship(deleteRule: .cascade)
    var taskTypes: [TaskType] = []          // Company task types
}
```

**Array Accessors**:

```swift
func getAdminIds() -> [String] {
    adminIdsString.isEmpty ? [] : adminIdsString.components(separatedBy: ",")
}

func setAdminIds(_ ids: [String]) {
    adminIdsString = ids.joined(separator: ",")
}

func getSeatedEmployeeIds() -> [String] {
    seatedEmployeeIds.isEmpty ? [] : seatedEmployeeIds.components(separatedBy: ",")
}

func setSeatedEmployeeIds(_ ids: [String]) {
    seatedEmployeeIds = ids.joined(separator: ",")
}

func hasAvailableSeats() -> Bool {
    getSeatedEmployeeIds().count < maxSeats
}
```

**Subscription Helpers**:

```swift
var isSubscriptionActive: Bool {
    subscriptionStatusEnum?.allowsAccess ?? false
}

var shouldShowGracePeriodWarning: Bool {
    subscriptionStatusEnum?.showsWarning ?? false
}

var daysRemainingInTrial: Int? {
    guard let endDate = trialEndDate else { return nil }
    let days = Calendar.current.dateComponents([.day], from: Date(), to: endDate).day ?? 0
    return max(0, days)
}
```

---

### 9. TeamMember

**Purpose**: Lightweight team member cache (reduces need for full User fetches).

**Complete Property List**:

```swift
@Model
final class TeamMember {
    // MARK: - Identity
    var id: String                          // User ID

    // MARK: - Personal Info
    var firstName: String                   // First name
    var lastName: String                    // Last name
    var role: String                        // Role as string

    // MARK: - Contact
    var email: String?                      // Email address
    var phone: String?                      // Phone number
    var avatarURL: String?                  // Avatar S3 URL

    // MARK: - Metadata
    var lastUpdated: Date                   // Cache freshness

    // MARK: - Relationships
    @Relationship(deleteRule: .cascade, inverse: \Company.teamMembers)
    var company: Company?                   // Parent company
}
```

**Factory Method**:

```swift
static func fromUserDTO(_ dto: UserDTO, isAdmin: Bool = false) -> TeamMember {
    let email = dto.authentication?.email?.email ?? dto.email

    let role: String
    if isAdmin {
        role = "Admin"
    } else if dto.userType == "Admin" {
        role = "Admin"
    } else if let employeeType = dto.employeeType {
        role = employeeType
    } else {
        role = "Unassigned"
    }

    return TeamMember(
        id: dto.id,
        firstName: dto.nameFirst ?? "",
        lastName: dto.nameLast ?? "",
        role: role,
        avatarURL: dto.avatar,
        email: email,
        phone: dto.phone
    )
}
```

---

### 10. OpsContact

**Purpose**: OPS support contact information from Bubble option set.

**Complete Property List**:

```swift
@Model
final class OpsContact {
    // MARK: - Identity
    var id: String                          // Bubble _id

    // MARK: - Contact Info
    var name: String                        // Contact name
    var email: String                       // Email address
    var phone: String                       // Phone number
    var display: String                     // Display name
    var role: String                        // "jack", "priority support", "data setup", etc.

    // MARK: - Metadata
    var lastSynced: Date                    // Cache freshness
}
```

**OpsContactRole Enum**:

```swift
enum OpsContactRole: String, CaseIterable {
    case jack = "jack"
    case prioritySupport = "Priority Support"
    case dataSetup = "Data Setup"
    case generalSupport = "General Support"
    case webAppAutoSend = "Web App Auto Send"
}
```

---

## BubbleFields Constants

### Overview

`BubbleFields.swift` contains **byte-perfect field name mappings** between Bubble.io and Swift models. **Never hardcode field names** - always use these constants.

### Complete BubbleFields.swift

```swift
struct BubbleFields {

    // MARK: - Entity Types
    struct Types {
        static let client = "Client"
        static let company = "Company"
        static let project = "Project"
        static let user = "User"
        static let subClient = "Sub Client"
        static let task = "Task"
        static let taskType = "TaskType"
        static let calendarEvent = "calendarevent"
    }

    // MARK: - Job Status Values
    struct JobStatus {
        static let rfq = "RFQ"
        static let estimated = "Estimated"
        static let accepted = "Accepted"
        static let inProgress = "In Progress"
        static let completed = "Completed"
        static let closed = "Closed"
        static let archived = "Archived"

        static func toSwiftEnum(_ bubbleStatus: String) -> Status {
            switch bubbleStatus {
            case rfq: return .rfq
            case estimated: return .estimated
            case accepted: return .accepted
            case inProgress: return .inProgress
            case completed: return .completed
            case closed: return .closed
            case archived: return .archived
            default: return .rfq
            }
        }
    }

    // MARK: - Employee Type Values
    struct EmployeeType {
        static let officeCrew = "Office Crew"
        static let fieldCrew = "Field Crew"
        static let admin = "Admin"

        static func toSwiftEnum(_ bubbleType: String) -> UserRole {
            switch bubbleType {
            case officeCrew: return .officeCrew
            case fieldCrew: return .fieldCrew
            case admin: return .admin
            default: return .fieldCrew
            }
        }
    }

    // MARK: - Task Status Values
    struct TaskStatus {
        static let booked = "Booked"
        static let inProgress = "In Progress"
        static let completed = "Completed"
        static let cancelled = "Cancelled"
    }

    // MARK: - Project Fields
    struct Project {
        static let id = "_id"
        static let address = "address"
        static let allDay = "allDay"
        static let calendarEvent = "calendarEvent"
        static let client = "client"
        static let company = "company"
        static let completion = "completion"
        static let description = "description"
        static let eventType = "eventType"           // Legacy - removed Nov 2025
        static let projectName = "projectName"
        static let startDate = "startDate"
        static let status = "status"
        static let teamMembers = "teamMembers"       // Legacy - computed from tasks
        static let teamNotes = "teamNotes"
        static let clientName = "clientName"
        static let tasks = "tasks"
        static let projectImages = "projectImages"
        static let duration = "duration"
        static let deletedAt = "deletedAt"
    }

    // MARK: - Task Fields
    struct Task {
        static let id = "_id"
        static let calendarEventId = "calendarEventId"
        static let companyId = "companyId"
        static let completionDate = "completionDate"
        static let projectId = "projectId"           // lowercase 'Id'
        static let scheduledDate = "scheduledDate"
        static let status = "status"
        static let taskColor = "taskColor"
        static let taskIndex = "taskIndex"
        static let taskNotes = "taskNotes"
        static let teamMembers = "teamMembers"
        static let type = "type"                     // TaskType ID
        static let deletedAt = "deletedAt"
    }

    // MARK: - CalendarEvent Fields
    struct CalendarEvent {
        static let id = "_id"
        static let active = "active"                 // Legacy - removed Nov 2025
        static let color = "color"
        static let companyId = "companyId"           // lowercase 'c'
        static let duration = "duration"
        static let endDate = "endDate"
        static let projectId = "projectId"           // lowercase 'p'
        static let startDate = "startDate"
        static let taskId = "taskId"                 // lowercase 't'
        static let teamMembers = "teamMembers"
        static let title = "title"
        static let eventType = "eventType"           // Legacy - removed Nov 2025
        static let deletedAt = "deletedAt"
    }

    // MARK: - User Fields
    struct User {
        static let id = "_id"
        static let clientID = "clientId"
        static let company = "company"
        static let currentLocation = "currentLocation"
        static let employeeType = "employeeType"     // "Office Crew" or "Field Crew"
        static let nameFirst = "nameFirst"
        static let nameLast = "nameLast"
        static let userType = "userType"
        static let avatar = "avatar"
        static let profileImageURL = "profileImageURL"
        static let email = "email"
        static let phone = "phone"
        static let homeAddress = "homeAddress"
        static let deviceToken = "deviceToken"
        static let hasCompletedAppTutorial = "hasCompletedAppTutorial"
        static let deletedAt = "deletedAt"
    }

    // MARK: - Company Fields
    struct Company {
        static let id = "_id"
        static let companyName = "companyName"
        static let companyID = "companyId"
        static let location = "location"
        static let logo = "logo"
        static let logoURL = "logoURL"
        static let defaultProjectColor = "defaultProjectColor"
        static let projects = "projects"
        static let teams = "teams"
        static let clients = "clients"
        static let taskTypes = "taskTypes"
        static let calendarEventsList = "calendarEventsList"
        static let admin = "admin"                   // Array of admin user IDs
        static let seatedEmployees = "seatedEmployees"
        static let subscriptionStatus = "subscriptionStatus"
        static let subscriptionPlan = "subscriptionPlan"
        static let deletedAt = "deletedAt"
    }

    // MARK: - Client Fields
    struct Client {
        static let id = "_id"
        static let address = "address"
        static let balance = "balance"
        static let clientIdNo = "clientIdNo"
        static let subClients = "subClients"         // Changed from "Sub Clients"
        static let emailAddress = "emailAddress"
        static let estimates = "estimates"           // Changed from "Estimates List"
        static let invoices = "invoices"
        static let isCompany = "isCompany"
        static let name = "name"
        static let parentCompany = "parentCompany"
        static let phoneNumber = "phoneNumber"
        static let projectsList = "projectsList"
        static let status = "status"
        static let avatar = "avatar"                 // Changed from "Thumbnail"
        static let unit = "unit"
        static let userId = "userId"
        static let notes = "notes"
        static let deletedAt = "deletedAt"
    }

    // MARK: - SubClient Fields
    struct SubClient {
        static let id = "_id"
        static let address = "address"
        static let emailAddress = "emailAddress"
        static let name = "name"
        static let parentClient = "parentClient"
        static let phoneNumber = "phoneNumber"
        static let title = "title"
        static let deletedAt = "deletedAt"
    }

    // MARK: - TaskType Fields
    struct TaskType {
        static let id = "_id"
        static let color = "color"
        static let display = "display"
        static let isDefault = "isDefault"
        static let deletedAt = "deletedAt"
    }
}
```

### Critical Notes

1. **Case Sensitivity**: Field names must match exactly (e.g., `projectId` not `projectID`)
2. **Legacy Fields**: `eventType` and `active` still exist in BubbleFields for API compatibility but are not used post-migration
3. **Team Members**: Project `teamMembers` field is legacy - team is now computed from task assignments
4. **Status Mapping**: TaskStatus "Scheduled" maps to "Booked" for backward compatibility

---

## Data Transfer Objects (DTOs)

### Overview

DTOs provide **clean separation** between Bubble API responses and SwiftData models. They handle:

- Field name mapping (Bubble → Swift)
- Type conversion (String dates → Date objects)
- Backward compatibility (status naming changes)
- Soft delete support

### DTO Architecture Pattern

```swift
struct SomeDTO: Codable {
    // 1. Properties matching Bubble response
    let id: String
    let someField: String?

    // 2. CodingKeys for exact Bubble field names
    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case someField = "someField"
    }

    // 3. Custom decoder for special handling (optional)
    init(from decoder: Decoder) throws {
        // Handle flexible types, backward compatibility, etc.
    }

    // 4. Conversion to SwiftData model
    func toModel() -> SomeModel {
        // Map DTO → Model
    }

    // 5. Reverse conversion from model
    static func from(_ model: SomeModel) -> SomeDTO {
        // Map Model → DTO
    }
}
```

---

### ProjectDTO

```swift
struct ProjectDTO: Codable {
    let id: String
    let projectName: String
    let company: BubbleReference?
    let client: String?                      // Client ID
    let status: String
    let address: BubbleAddress?
    let allDay: Bool?
    let completion: String?                  // ISO8601 date
    let description: String?
    let startDate: String?                   // ISO8601 date
    let teamNotes: String?
    let teamMembers: [String]?               // User IDs (legacy - not used)
    let projectImages: [String]?             // S3 URLs
    let duration: Int?
    let deletedAt: String?                   // ISO8601 date

    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case projectName = "projectName"
        case company = "company"
        case client = "client"
        case status = "status"
        case address = "address"
        case allDay = "allDay"
        case completion = "completion"
        case description = "description"
        case startDate = "startDate"
        case teamNotes = "teamNotes"
        case teamMembers = "teamMembers"
        case projectImages = "projectImages"
        case duration = "duration"
        case deletedAt = "deletedAt"
    }

    func toModel() -> Project {
        let project = Project(
            id: id,
            title: projectName,
            status: BubbleFields.JobStatus.toSwiftEnum(status)
        )

        // Map address
        if let bubbleAddress = address {
            project.address = bubbleAddress.formattedAddress
            project.latitude = bubbleAddress.lat
            project.longitude = bubbleAddress.lng
        }

        // Store client reference
        project.clientId = client

        // Store company reference
        if let companyRef = company {
            project.companyId = companyRef.stringValue
        }

        // Parse dates
        project.startDate = DateFormatter.dateFromBubble(startDate)
        project.endDate = DateFormatter.dateFromBubble(completion)
        project.duration = duration

        // Other fields
        project.notes = teamNotes
        project.projectDescription = description
        project.allDay = allDay ?? false

        // Images
        if let images = projectImages {
            project.projectImagesString = images.joined(separator: ",")
        }

        // CRITICAL: Do NOT store teamMembers from Bubble
        // Team members are computed from task assignments

        // Soft delete
        if let deletedAtString = deletedAt {
            let formatter = ISO8601DateFormatter()
            project.deletedAt = formatter.date(from: deletedAtString)
        }

        project.lastSyncedAt = Date()
        return project
    }
}
```

---

### TaskDTO

```swift
struct TaskDTO: Codable {
    let id: String
    let projectId: String?
    let companyId: String?
    let calendarEventId: String?
    let status: String?
    let taskColor: String?
    let taskIndex: Int?
    let taskNotes: String?
    let teamMembers: [String]?               // User IDs
    let type: String?                        // TaskType ID
    let scheduledDate: String?               // ISO8601
    let completionDate: String?              // ISO8601
    let deletedAt: String?                   // ISO8601

    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case projectId = "projectId"         // lowercase 'Id'
        case companyId = "companyId"
        case calendarEventId = "calendarEventId"
        case status = "status"
        case taskColor = "taskColor"
        case taskIndex = "taskIndex"
        case taskNotes = "taskNotes"
        case teamMembers = "teamMembers"
        case type = "type"
        case scheduledDate = "scheduledDate"
        case completionDate = "completionDate"
        case deletedAt = "deletedAt"
    }

    func toModel(defaultColor: String = "#59779F") -> ProjectTask {
        // Validate color
        let validColor = taskColor?.hasPrefix("#") == true ? taskColor! : "#\(taskColor ?? defaultColor)"

        // Map status with backward compatibility
        let taskStatus: TaskStatus
        if let statusValue = status {
            if statusValue == "Scheduled" {
                // Backward compatibility: "Scheduled" → "Booked"
                taskStatus = .booked
            } else {
                taskStatus = TaskStatus(rawValue: statusValue) ?? .booked
            }
        } else {
            taskStatus = .booked
        }

        let task = ProjectTask(
            id: id,
            projectId: projectId ?? "",
            taskTypeId: type ?? "",
            companyId: companyId ?? "",
            status: taskStatus,
            taskColor: validColor
        )

        task.calendarEventId = calendarEventId
        task.taskNotes = taskNotes
        task.displayOrder = taskIndex ?? 0

        if let teamMembers = teamMembers, !teamMembers.isEmpty {
            task.setTeamMemberIds(teamMembers)
        }

        // Soft delete
        if let deletedAtString = deletedAt {
            let formatter = ISO8601DateFormatter()
            task.deletedAt = formatter.date(from: deletedAtString)
        }

        return task
    }

    static func from(_ task: ProjectTask) -> TaskDTO {
        let dateFormatter = ISO8601DateFormatter()
        return TaskDTO(
            id: task.id,
            projectId: task.projectId,
            companyId: task.companyId,
            calendarEventId: task.calendarEventId,
            status: task.status.rawValue,
            taskColor: task.taskColor,
            taskIndex: task.displayOrder,
            taskNotes: task.taskNotes,
            teamMembers: task.getTeamMemberIds(),
            type: task.taskTypeId,
            scheduledDate: task.scheduledDate.map { dateFormatter.string(from: $0) },
            completionDate: task.completionDate.map { dateFormatter.string(from: $0) },
            deletedAt: task.deletedAt.map { dateFormatter.string(from: $0) }
        )
    }
}
```

---

### CalendarEventDTO

```swift
struct CalendarEventDTO: Codable {
    let id: String
    let companyId: String?                   // lowercase 'c'
    let projectId: String?                   // lowercase 'p'
    let taskId: String?                      // lowercase 't'
    let color: String?
    let title: String?
    let startDate: String?                   // ISO8601
    let endDate: String?                     // ISO8601
    let duration: Double?                    // Can be decimal
    let teamMembers: [String]?               // User IDs
    let deletedAt: String?                   // ISO8601

    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case companyId = "companyId"
        case projectId = "projectId"
        case taskId = "taskId"
        case color = "color"
        case title = "title"
        case startDate = "startDate"
        case endDate = "endDate"
        case duration = "duration"
        case teamMembers = "teamMembers"
        case deletedAt = "deletedAt"
    }

    func toModel() -> CalendarEvent? {
        // Parse dates with multiple format attempts
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        var startDateObj: Date?
        var endDateObj: Date?

        if let startDateString = startDate {
            startDateObj = dateFormatter.date(from: startDateString)
        }

        if let endDateString = endDate {
            endDateObj = dateFormatter.date(from: endDateString)
        }

        // Validate date order
        if let start = startDateObj, let end = endDateObj, end < start {
            endDateObj = start
        }

        // Validate required fields
        guard let projectIdValue = projectId, !projectIdValue.isEmpty,
              let companyIdValue = companyId, !companyIdValue.isEmpty else {
            return nil
        }

        // Validate color
        let validColor = color?.hasPrefix("#") == true ? color! : "#\(color ?? "59779F")"

        let event = CalendarEvent(
            id: id,
            projectId: projectIdValue,
            companyId: companyIdValue,
            title: title ?? "Untitled Event",
            startDate: startDateObj,
            endDate: endDateObj,
            color: validColor
        )

        event.taskId = taskId
        event.duration = Int(duration ?? 1)

        if let teamMembers = teamMembers {
            event.setTeamMemberIds(teamMembers)
        }

        // Soft delete
        if let deletedAtString = deletedAt {
            let formatter = ISO8601DateFormatter()
            event.deletedAt = formatter.date(from: deletedAtString)
        }

        return event
    }

    static func from(_ event: CalendarEvent) -> CalendarEventDTO {
        let dateFormatter = ISO8601DateFormatter()
        return CalendarEventDTO(
            id: event.id,
            companyId: event.companyId,
            projectId: event.projectId,
            taskId: event.taskId,
            color: event.color,
            title: event.title,
            startDate: event.startDate.map { dateFormatter.string(from: $0) },
            endDate: event.endDate.map { dateFormatter.string(from: $0) },
            duration: Double(event.duration),
            teamMembers: event.getTeamMemberIds(),
            deletedAt: event.deletedAt.map { dateFormatter.string(from: $0) }
        )
    }
}
```

---

### UserDTO

```swift
struct UserDTO: Codable {
    let id: String
    let nameFirst: String?
    let nameLast: String?
    let employeeType: String?                // "Office Crew" or "Field Crew"
    let userType: String?
    let company: String?                     // Company ID
    let email: String?
    let phone: String?
    let avatar: String?
    let homeAddress: BubbleAddress?
    let userColor: String?
    let devPermission: Bool?
    let hasCompletedAppOnboarding: Bool?
    let hasCompletedAppTutorial: Bool?
    let stripeCustomerId: String?
    let deviceToken: String?
    let authentication: Authentication?
    let deletedAt: String?

    struct Authentication: Codable {
        let email: EmailAuth?

        struct EmailAuth: Codable {
            let email: String?
            let emailConfirmed: Bool?

            enum CodingKeys: String, CodingKey {
                case email
                case emailConfirmed = "email_confirmed"
            }
        }
    }

    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case nameFirst = "nameFirst"
        case nameLast = "nameLast"
        case employeeType = "employeeType"
        case userType = "userType"
        case company = "company"
        case email
        case phone = "phone"
        case avatar = "avatar"
        case homeAddress = "homeAddress"
        case userColor = "userColor"
        case devPermission = "devPermission"
        case hasCompletedAppOnboarding = "hasCompletedAppOnboarding"
        case hasCompletedAppTutorial = "hasCompletedAppTutorial"
        case stripeCustomerId = "stripeCustomerId"
        case deviceToken = "deviceToken"
        case authentication
        case deletedAt = "deletedAt"
    }

    func toModel(companyAdminIds: [String]? = nil) -> User {
        // CRITICAL: Determine role from company.adminIds FIRST
        let role: UserRole
        if let adminIds = companyAdminIds, adminIds.contains(id) {
            role = .admin
        } else if let employeeTypeString = employeeType {
            role = BubbleFields.EmployeeType.toSwiftEnum(employeeTypeString)
        } else {
            role = .fieldCrew  // Default
        }

        let user = User(
            id: id,
            firstName: nameFirst ?? "",
            lastName: nameLast ?? "",
            role: role,
            companyId: company ?? ""
        )

        // Email from authentication or direct field
        if let emailAuth = authentication?.email?.email {
            user.email = emailAuth
        } else {
            user.email = email
        }

        // Other fields
        user.phone = phone
        user.profileImageURL = avatar
        user.userColor = userColor
        user.devPermission = devPermission ?? false
        user.hasCompletedAppOnboarding = hasCompletedAppOnboarding ?? false
        user.hasCompletedAppTutorial = hasCompletedAppTutorial ?? false
        user.stripeCustomerId = stripeCustomerId
        user.deviceToken = deviceToken

        // Address
        if let address = homeAddress {
            user.homeAddress = address.formattedAddress
        }

        // Soft delete
        if let deletedAtString = deletedAt {
            let formatter = ISO8601DateFormatter()
            user.deletedAt = formatter.date(from: deletedAtString)
        }

        user.lastSyncedAt = Date()
        return user
    }
}
```

**Critical Bug Fix (Nov 3, 2025)**: iOS was checking for wrong employeeType values ("Office", "Crew") instead of actual Bubble values ("Office Crew", "Field Crew"). Always check `company.adminIds` first before falling back to `employeeType`.

---

### CompanyDTO

```swift
struct CompanyDTO: Codable {
    let id: String
    let companyName: String?
    let logo: BubbleImage?
    let location: BubbleAddress?
    let defaultProjectColor: String?
    let admin: [BubbleReference]?            // Admin user IDs
    let seatedEmployees: [BubbleReference]?  // Seated user IDs
    let subscriptionStatus: String?
    let subscriptionPlan: String?
    let subscriptionEnd: Date?               // Can be UNIX timestamp OR ISO8601
    let maxSeats: Int?
    let deletedAt: String?
    // ... (many more fields - see full implementation)

    // Custom decoder to handle UNIX timestamps OR ISO8601 dates
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // ... decode fields

        // CRITICAL: Handle flexible date formats
        self.subscriptionEnd = Self.decodeFlexibleDate(
            from: container,
            forKey: .subscriptionEnd,
            isStripeField: true
        )
    }

    private static func decodeFlexibleDate(
        from container: KeyedDecodingContainer<CodingKeys>,
        forKey key: CodingKeys,
        isStripeField: Bool
    ) -> Date? {
        // Try UNIX timestamp (Double)
        if let timestamp = try? container.decodeIfPresent(Double.self, forKey: key) {
            return Date(timeIntervalSince1970: timestamp)
        }

        // Try UNIX timestamp (Int)
        if let timestamp = try? container.decodeIfPresent(Int.self, forKey: key) {
            return Date(timeIntervalSince1970: Double(timestamp))
        }

        // Try ISO8601 string
        if let dateString = try? container.decodeIfPresent(String.self, forKey: key) {
            return DateFormatter.dateFromBubble(dateString)
        }

        return nil
    }

    func toModel() -> Company {
        let company = Company(id: id, name: companyName ?? "Unknown")

        // CRITICAL: Normalize subscription status to lowercase
        if let status = subscriptionStatus {
            company.subscriptionStatus = status.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // CRITICAL: Normalize subscription plan to lowercase
        if let plan = subscriptionPlan {
            company.subscriptionPlan = plan.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // Admin IDs
        if let adminRefs = admin {
            let adminIds = adminRefs.compactMap { $0.stringValue }
            company.adminIdsString = adminIds.joined(separator: ",")
        }

        // Seated employees
        if let seatedRefs = seatedEmployees {
            let seatedIds = seatedRefs.compactMap { $0.stringValue }
            company.setSeatedEmployeeIds(seatedIds)
        }

        company.maxSeats = maxSeats ?? 0
        company.defaultProjectColor = defaultProjectColor ?? "#9CA3AF"

        // ... map other fields

        company.lastSyncedAt = Date()
        return company
    }
}
```

**Critical Notes**:
- CompanyDTO dates can be **UNIX timestamps** (from Stripe) **OR** ISO8601 strings (from Bubble)
- Subscription status/plan must be normalized to lowercase to match enums
- `maxSeats` defaults to 0 if not provided

---

### ClientDTO

```swift
struct ClientDTO: Codable {
    let id: String
    let name: String?
    let emailAddress: String?
    let phoneNumber: String?
    let address: BubbleAddress?
    let thumbnail: String?                   // Avatar URL (renamed from "Thumbnail" to "avatar")
    let subClientIds: [String]?              // Sub-client IDs
    let deletedAt: String?

    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case name = "name"
        case emailAddress = "emailAddress"
        case phoneNumber = "phoneNumber"
        case address = "address"
        case thumbnail = "avatar"            // Field renamed in Bubble
        case subClientIds = "subClients"     // Field renamed in Bubble
        case deletedAt = "deletedAt"
    }

    func toModel() -> Client {
        let client = Client(
            id: id,
            name: name ?? "Unknown Client",
            email: emailAddress,
            phoneNumber: phoneNumber,
            address: address?.formattedAddress
        )

        client.profileImageURL = thumbnail

        if let bubbleAddress = address {
            client.latitude = bubbleAddress.lat
            client.longitude = bubbleAddress.lng
        }

        // Soft delete
        if let deletedAtString = deletedAt {
            let formatter = ISO8601DateFormatter()
            client.deletedAt = formatter.date(from: deletedAtString)
        }

        client.lastSyncedAt = Date()
        return client
    }
}
```

---

### SubClientDTO

```swift
struct SubClientDTO: Codable {
    let id: String
    let name: String?
    let title: String?
    let emailAddress: String?
    let phoneNumber: PhoneNumberType?        // Can be String OR Number from API
    let address: BubbleAddress?
    let deletedAt: String?

    // Handle phone as String OR Number
    enum PhoneNumberType: Codable {
        case string(String)
        case number(Double)

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let stringValue = try? container.decode(String.self) {
                self = .string(stringValue)
            } else if let numberValue = try? container.decode(Double.self) {
                self = .number(numberValue)
            } else {
                throw DecodingError.typeMismatch(...)
            }
        }

        var stringValue: String? {
            switch self {
            case .string(let value): return value
            case .number(let value): return String(format: "%.0f", value)
            }
        }
    }

    func toSubClient() -> SubClient {
        let subClient = SubClient(
            id: id,
            name: name ?? "Unknown",
            title: title,
            email: emailAddress,
            phoneNumber: phoneNumber?.stringValue,
            address: address?.formattedAddress
        )

        // Soft delete
        if let deletedAtString = deletedAt {
            let formatter = ISO8601DateFormatter()
            subClient.deletedAt = formatter.date(from: deletedAtString)
        }

        return subClient
    }
}
```

**Critical Note**: SubClient `phoneNumber` can be either String or Number type from Bubble API.

---

### TaskTypeDTO

```swift
struct TaskTypeDTO: Codable {
    let id: String
    let display: String
    let color: String
    let isDefault: Bool?
    let deletedAt: String?

    // Handle both "id" (POST) and "_id" (GET) responses
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let dynamicContainer = try decoder.container(keyedBy: DynamicCodingKey.self)

        // Try "id" first, fall back to "_id"
        if let idValue = try? container.decode(String.self, forKey: .id) {
            self.id = idValue
        } else {
            self.id = try dynamicContainer.decode(String.self, forKey: DynamicCodingKey(stringValue: "_id")!)
        }

        // Try lowercase "display" first, fall back to "Display"
        if let displayValue = try? container.decode(String.self, forKey: .display) {
            self.display = displayValue
        } else {
            self.display = try dynamicContainer.decode(String.self, forKey: DynamicCodingKey(stringValue: "Display")!)
        }

        self.color = try container.decode(String.self, forKey: .color)
        self.isDefault = try container.decodeIfPresent(Bool.self, forKey: .isDefault)
        self.deletedAt = try container.decodeIfPresent(String.self, forKey: .deletedAt)
    }

    func toModel() -> TaskType {
        let taskType = TaskType(
            id: id,
            display: display,
            color: color,
            companyId: "",  // Set by caller
            isDefault: isDefault ?? false,
            icon: nil  // Not in Bubble - assigned locally
        )

        // Soft delete
        if let deletedAtString = deletedAt {
            let formatter = ISO8601DateFormatter()
            taskType.deletedAt = formatter.date(from: deletedAtString)
        }

        return taskType
    }
}
```

---

## Soft Delete Strategy

### Overview

All models support **soft delete** via `deletedAt: Date?` timestamp. This preserves historical data while hiding deleted items from normal queries.

### 30-Day Window

- **Items deleted < 30 days ago**: Kept with `deletedAt` timestamp
- **Items deleted > 30 days ago**: Permanently deleted (future enhancement)

### Default Query Pattern

**Always exclude soft-deleted items** unless explicitly querying for them:

```swift
// ✅ CORRECT
@Query(
    filter: #Predicate<Project> { $0.deletedAt == nil }
) var projects: [Project]

// ❌ INCORRECT - shows deleted items
@Query var projects: [Project]
```

### Sync Manager Soft Delete

```swift
func syncProjects() async {
    // Fetch from API
    let remoteDTOs = try await apiService.fetchProjects()
    let remoteIds = Set(remoteDTOs.map { $0.id })

    // Fetch local non-deleted projects
    let descriptor = FetchDescriptor<Project>(
        predicate: #Predicate { $0.deletedAt == nil }
    )
    let localProjects = try? modelContext.fetch(descriptor)

    // Soft delete items not in remote set
    let now = Date()
    for project in localProjects ?? [] {
        if !remoteIds.contains(project.id) {
            project.deletedAt = now
        }
    }

    // Upsert remote items
    for dto in remoteDTOs {
        let project = dto.toModel()
        modelContext.insert(project)
    }

    try? modelContext.save()
}
```

---

## Computed Properties & Business Logic

### Project Computed Dates (Task-Based)

As of **November 2025**, all projects use task-based scheduling. Project dates are computed from task calendar events:

```swift
/// Project start = earliest task start
var computedStartDate: Date? {
    tasks.compactMap { $0.calendarEvent?.startDate }.min()
}

/// Project end = latest task end
var computedEndDate: Date? {
    tasks.compactMap { $0.calendarEvent?.endDate }.max()
}
```

**Critical**: Do NOT use stored `startDate` and `endDate` fields for display. These are legacy fields from API that may not reflect current task schedules.

### Client Contact Cascading

Client contact info checks client first, then sub-clients:

```swift
var effectiveClientEmail: String? {
    // Check main client
    if let email = client?.email, !email.isEmpty {
        return email
    }
    // Check sub-clients
    return client?.subClients.first(where: { $0.email != nil })?.email
}

var effectiveClientPhone: String? {
    // Check main client
    if let phone = client?.phoneNumber, !phone.isEmpty {
        return phone
    }
    // Check sub-clients
    return client?.subClients.first(where: { $0.phoneNumber != nil })?.phoneNumber
}
```

### Role Detection Logic

**CRITICAL**: Role assignment must follow this exact order:

```swift
// 1. Check company.adminIds array FIRST
if let adminIds = companyAdminIds, adminIds.contains(userId) {
    role = .admin
}
// 2. Then check employeeType field
else if let employeeType = dto.employeeType {
    role = BubbleFields.EmployeeType.toSwiftEnum(employeeType)
}
// 3. Default to Field Crew
else {
    role = .fieldCrew
}
```

**Bug Fixed Nov 3, 2025**: iOS was checking for wrong values ("Office", "Crew") instead of actual Bubble values ("Office Crew", "Field Crew").

### Project Team Computation

Project team members are computed from task team members:

```swift
@discardableResult
func updateTeamMembersFromTasks(in context: ModelContext) -> Bool {
    // Collect unique team member IDs from all tasks
    var allIds = Set<String>()
    for task in tasks {
        allIds.formUnion(task.getTeamMemberIds())
    }

    // Check if update needed
    let currentIds = Set(getTeamMemberIds())
    if currentIds == allIds { return false }

    // Fetch User objects
    let predicate = #Predicate<User> { allIds.contains($0.id) }
    let users = try? context.fetch(FetchDescriptor<User>(predicate: predicate))

    // Update relationships
    teamMembers = users ?? []
    setTeamMemberIds(Array(allIds))
    return true
}
```

**Critical**: Call `project.updateTeamMembersFromTasks()` after any task creation, update, or deletion.

---

## Migration History

### Task-Only Scheduling Migration (November 18, 2025)

**Changes**:
- ✅ Removed `project.eventType` field
- ✅ Removed `project.primaryCalendarEvent` field
- ✅ Removed `CalendarEvent.type` enum
- ✅ Removed `CalendarEvent.active` boolean
- ✅ Added `project.computedStartDate` computed property
- ✅ Added `project.computedEndDate` computed property
- ✅ One-time migration: deleted all project-level calendar events
- ✅ Simplified calendar filtering logic
- ✅ Updated all DTOs to exclude removed fields

**Impact**:
- All calendar display now flows through task calendar events
- Project dates dynamically computed from tasks
- Simpler architecture, less complexity
- No dual-mode logic required

**Backward Compatibility**:
- BubbleFields still contains `eventType` and `active` for API compatibility
- DTOs gracefully ignore these fields if present

### Status Renaming Migration (November 11, 2025)

**Change**: Task status "Scheduled" → "Booked"

**Backward Compatibility**:

```swift
// TaskStatus enum custom decoder
init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    let rawValue = try container.decode(String.self)

    if rawValue == "Scheduled" {
        self = .booked  // Map legacy value
    } else {
        self = TaskStatus(rawValue: rawValue) ?? .booked
    }
}
```

**TODO**: Update Bubble backend to use "Booked" consistently (not yet complete).

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

### User's Assigned Projects (Field Crew)

```swift
func userProjects(userId: String) -> [Project] {
    let descriptor = FetchDescriptor<Project>(
        predicate: #Predicate {
            $0.deletedAt == nil &&
            $0.teamMemberIds.contains(userId)
        }
    )
    return try? modelContext.fetch(descriptor) ?? []
}
```

### Today's Calendar Events

```swift
@Query(
    filter: #Predicate<CalendarEvent> {
        $0.deletedAt == nil &&
        $0.startDate >= startOfToday &&
        $0.startDate < startOfTomorrow
    }
) var todaysEvents: [CalendarEvent]
```

### Calendar Events for Date Range

```swift
func eventsInRange(start: Date, end: Date) -> [CalendarEvent] {
    let descriptor = FetchDescriptor<CalendarEvent>(
        predicate: #Predicate {
            $0.deletedAt == nil &&
            $0.startDate != nil &&
            $0.startDate! >= start &&
            $0.startDate! <= end
        }
    )
    return try? modelContext.fetch(descriptor) ?? []
}
```

### Tasks by Status

```swift
func tasksByStatus(_ status: TaskStatus) -> [ProjectTask] {
    let descriptor = FetchDescriptor<ProjectTask>(
        predicate: #Predicate {
            $0.deletedAt == nil &&
            $0.status == status
        }
    )
    return try? modelContext.fetch(descriptor) ?? []
}
```

---

## Defensive Programming Patterns

### 1. Never Pass Models to Background Tasks

```swift
// ✅ CORRECT: Pass IDs
Task.detached {
    await processProject(projectId: project.id)
}

// ❌ INCORRECT: Passing model causes crashes
Task.detached {
    await processProject(project: project)  // CRASH!
}
```

**Reason**: SwiftData models are tied to their ModelContext. Passing models across thread boundaries causes crashes.

### 2. Always Fetch Fresh Models

```swift
func processProject(projectId: String) async {
    let context = ModelContext(sharedModelContainer)
    let descriptor = FetchDescriptor<Project>(
        predicate: #Predicate { $0.id == projectId }
    )
    guard let project = try? context.fetch(descriptor).first else { return }

    // Work with fresh model from this context
    project.needsSync = false
    try? context.save()
}
```

### 3. Use @MainActor for UI Operations

```swift
@MainActor
func updateProject() {
    let context = dataController.modelContext
    // All SwiftData operations on main thread
}
```

### 4. Explicit ModelContext.save()

```swift
// Always save explicitly after changes
project.name = "Updated Name"
try? modelContext.save()  // Don't rely on auto-save
```

### 5. Avoid .id() Modifiers

```swift
// ❌ INCORRECT: Causes view recreation and SwiftData issues
TabView(selection: $selectedTab)
    .id(selectedTab)

// ✅ CORRECT: Let SwiftUI manage identity
TabView(selection: $selectedTab)
```

### 6. Complete Data Wipe on Logout

```swift
func logout() {
    // Delete all data to prevent cross-user contamination
    try? modelContext.delete(model: Project.self)
    try? modelContext.delete(model: User.self)
    try? modelContext.delete(model: Client.self)
    try? modelContext.delete(model: ProjectTask.self)
    try? modelContext.delete(model: CalendarEvent.self)
    try? modelContext.delete(model: Company.self)
    try? modelContext.delete(model: TaskType.self)
    try? modelContext.delete(model: SubClient.self)
    try? modelContext.delete(model: TeamMember.self)
    try? modelContext.save()

    // Clear UserDefaults
    UserDefaults.standard.removePersistentDomain(forName: Bundle.main.bundleIdentifier!)
}
```

---

## Android Conversion Notes

### Room Entity Equivalents

SwiftData models map to Room entities:

```kotlin
@Entity(tableName = "projects")
data class Project(
    @PrimaryKey val id: String,
    val title: String,
    val companyId: String,
    // ... all other properties
    val deletedAt: Long? = null  // UNIX timestamp
)
```

### Key Differences

1. **Relationships**: Room uses `@Relation` annotations instead of `@Relationship`
2. **Comma-Separated Strings**: Consider using TypeConverters for `List<String>` instead
3. **Computed Properties**: Implement as Kotlin `val` with getters
4. **Enums**: Use Kotlin sealed classes or enums with TypeConverters

### DTO Conversion

Kotlin data classes with kotlinx.serialization:

```kotlin
@Serializable
data class ProjectDTO(
    @SerialName("_id") val id: String,
    @SerialName("projectName") val name: String,
    // ... all fields with @SerialName annotations
) {
    fun toEntity(): Project {
        // Conversion logic
    }
}
```

---

---

## Supabase Schema (Bubble Migration)

### Overview

As of February 2026, OPS is migrating operational data from Bubble.io into Supabase (PostgreSQL). The web app (`ops-web`) is the first platform to transition. The iOS and Android apps remain on Bubble until separately converted.

The Supabase schema is organized into two tiers:

1. **Pipeline/Financial Tables** (migrations 001-003) -- Already in production for the web CRM/estimates/invoices system.
2. **Core Entity Tables** (migration 004) -- Mirrors the 9 Bubble entities into Supabase with proper UUID primary keys, foreign key relationships, and RLS.
3. **Reference Linking** (migration 005) -- Connects the pre-existing pipeline tables to the new core entity tables via `_ref` UUID foreign key columns.

### Key Architecture Decisions

- **UUID Primary Keys**: All Supabase tables use `UUID PRIMARY KEY DEFAULT gen_random_uuid()`.
- **`bubble_id TEXT UNIQUE`**: Every core entity table has a `bubble_id` column that stores the original Bubble `_id` string. This enables idempotent migration (upsert on `bubble_id`) and allows services to look up records by either ID system during the transition period.
- **Row-Level Security (RLS)**: All company-scoped tables use `private.get_user_company_id()` to enforce company isolation. This function extracts `company_id` from the Supabase Auth JWT `app_metadata`.
- **`updated_at` Triggers**: All tables have `BEFORE UPDATE` triggers that auto-set `updated_at = NOW()` via the shared `update_timestamp()` function.
- **Soft Delete**: All tables include `deleted_at TIMESTAMPTZ` for soft delete, consistent with the Bubble data model.

### Migration SQL Files

| Migration | File | Status | Description |
|-----------|------|--------|-------------|
| 001 | `001_pipeline_schema.sql` | EXECUTED | Pipeline stages, opportunities, estimates, invoices, payments, products, tax rates, activities, follow-ups, document sequences, audit log |
| 002 | `002_lifecycle_entities.sql` | EXECUTED | Task templates, activity comments, site visits, project photos, Gmail connections, company settings |
| 003 | `003_create_project_notes.sql` | EXECUTED | Project notes with @mention support |
| 004 | `004_core_entities.sql` | Pending | 9 core entity tables mirroring Bubble data |
| 005 | `005_update_pipeline_references.sql` | Pending | Adds `_ref` UUID FK columns to pipeline tables |

---

### Pipeline & Financial Tables (Migrations 001-003)

These tables power the web app's CRM and financial features. They were designed before core entities existed in Supabase, so they reference Bubble IDs via TEXT columns.

**Migration 001 -- Pipeline Schema:**

| Table | Purpose | Key Columns |
|-------|---------|-------------|
| `pipeline_stage_configs` | Customizable Kanban stages per company | `company_id`, `name`, `slug`, `sort_order`, `is_won_stage`, `is_lost_stage` |
| `opportunities` | Pipeline deals/leads | `company_id`, `client_id`, `stage`, `estimated_value`, `project_id` |
| `stage_transitions` | Immutable log of stage changes | `opportunity_id`, `from_stage`, `to_stage`, `duration_in_stage` |
| `products` | Service/material catalog | `company_id`, `name`, `default_price`, `unit_cost`, `unit` |
| `tax_rates` | Tax rate definitions | `company_id`, `name`, `rate` |
| `estimates` | Quotes/proposals with versioning | `company_id`, `client_id`, `estimate_number`, `version`, `status`, `total` |
| `invoices` | Bills with DB-trigger-maintained balances | `company_id`, `client_id`, `invoice_number`, `total`, `amount_paid`, `balance_due` |
| `line_items` | Polymorphic: belongs to estimate OR invoice | `estimate_id`/`invoice_id`, `quantity`, `unit_price`, `line_total` (generated) |
| `payments` | Payment records (trigger updates invoice balance) | `invoice_id`, `amount`, `payment_method`, `payment_date` |
| `payment_milestones` | Progress billing schedule on estimates | `estimate_id`, `name`, `type`, `value`, `amount` |
| `activities` | Communication/event log | `opportunity_id`, `type`, `subject`, `content`, `direction` |
| `follow_ups` | Scheduled follow-up tasks | `opportunity_id`, `type`, `due_at`, `status` |
| `document_sequences` | Gapless numbering (EST-2026-00042) | `company_id`, `document_type`, `prefix`, `last_number` |
| `audit_log` | Append-only financial audit trail | `table_name`, `record_id`, `action`, `old_data`, `new_data` |
| `valid_status_transitions` | State machine enforcement | `entity_type`, `from_status`, `to_status` |

**Key Database Functions:**
- `get_next_document_number(company_id, type)` -- Returns gapless document numbers like `EST-2026-00042`
- `convert_estimate_to_invoice(estimate_id, due_date)` -- Atomic estimate-to-invoice conversion (copies line items, marks estimate as converted, logs activity)
- `update_invoice_balance()` -- Trigger function that auto-updates `amount_paid`, `balance_due`, and `status` on invoices when payments change

**Migration 002 -- Lifecycle Entities:**

| Table | Purpose |
|-------|---------|
| `task_templates` | Default sub-tasks per TaskType (e.g., "Deck Work" -> Footings, Framing, Vinyl) |
| `activity_comments` | Threaded internal comments on activities |
| `site_visits` | Scheduled job site visits with photo/note capture |
| `project_photos` | Structured photo gallery replacing `projectImages` string |
| `gmail_connections` | OAuth tokens for Gmail auto-logging |
| `company_settings` | Per-company feature toggles (auto-generate tasks, follow-up days) |

Also adds columns to existing tables: `line_items.type` (LABOR/MATERIAL/OTHER), `line_items.task_type_id`, `products.type`, `products.task_type_id`, `estimates.project_id`, `activities.email_thread_id`, etc.

**Migration 003 -- Project Notes:**

| Table | Purpose |
|-------|---------|
| `project_notes` | Per-project notes with @mentions, attachments (JSONB), and soft delete |

---

### Core Entity Tables (Migration 004)

These 9 tables mirror the Bubble data model documented in the SwiftData section above. Each table has a `bubble_id TEXT UNIQUE` column for migration mapping.

#### `companies`

```sql
CREATE TABLE companies (
  id                      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  bubble_id               TEXT UNIQUE,
  name                    TEXT NOT NULL,
  external_id             TEXT,
  description             TEXT,
  website                 TEXT,
  phone                   TEXT,
  email                   TEXT,
  address                 TEXT,
  latitude                DOUBLE PRECISION,
  longitude               DOUBLE PRECISION,
  open_hour               TEXT,
  close_hour              TEXT,
  logo_url                TEXT,
  default_project_color   TEXT DEFAULT '#9CA3AF',
  industries              TEXT[] DEFAULT '{}',
  company_size            TEXT,
  company_age             TEXT,
  referral_method         TEXT,
  account_holder_id       TEXT,
  admin_ids               TEXT[] DEFAULT '{}',
  seated_employee_ids     TEXT[] DEFAULT '{}',
  max_seats               INT DEFAULT 10,
  subscription_status     TEXT CHECK (...),  -- trial, active, grace, expired, cancelled
  subscription_plan       TEXT CHECK (...),  -- trial, starter, team, business
  subscription_end        TIMESTAMPTZ,
  subscription_period     TEXT CHECK (...),  -- Monthly, Annual
  trial_start_date        TIMESTAMPTZ,
  trial_end_date          TIMESTAMPTZ,
  seat_grace_start_date   TIMESTAMPTZ,
  has_priority_support    BOOLEAN DEFAULT FALSE,
  data_setup_purchased    BOOLEAN DEFAULT FALSE,
  data_setup_completed    BOOLEAN DEFAULT FALSE,
  data_setup_scheduled    TIMESTAMPTZ,
  stripe_customer_id      TEXT,
  subscription_ids_json   TEXT,
  created_at              TIMESTAMPTZ DEFAULT NOW(),
  updated_at              TIMESTAMPTZ DEFAULT NOW(),
  deleted_at              TIMESTAMPTZ
);
-- RLS: id = private.get_user_company_id()
```

**Notes:**
- `industries` uses PostgreSQL `TEXT[]` array instead of Bubble's comma-separated string.
- `admin_ids` and `seated_employee_ids` also use `TEXT[]` arrays (storing Bubble user IDs during transition).

#### `users`

```sql
CREATE TABLE users (
  id                          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  bubble_id                   TEXT UNIQUE,
  company_id                  UUID REFERENCES companies(id) ON DELETE SET NULL,
  auth_id                     UUID UNIQUE,  -- Links to Supabase Auth (future)
  first_name                  TEXT NOT NULL,
  last_name                   TEXT NOT NULL,
  email                       TEXT,
  phone                       TEXT,
  home_address                TEXT,
  profile_image_url           TEXT,
  user_color                  TEXT,
  role                        TEXT DEFAULT 'Field Crew' CHECK (role IN ('Admin','Office Crew','Field Crew')),
  user_type                   TEXT CHECK (user_type IN ('Employee','Company','Client','Admin')),
  is_company_admin            BOOLEAN DEFAULT FALSE,
  has_completed_onboarding    BOOLEAN DEFAULT FALSE,
  has_completed_tutorial      BOOLEAN DEFAULT FALSE,
  dev_permission              BOOLEAN DEFAULT FALSE,
  latitude                    DOUBLE PRECISION,
  longitude                   DOUBLE PRECISION,
  location_name               TEXT,
  client_id                   TEXT,
  is_active                   BOOLEAN DEFAULT TRUE,
  stripe_customer_id          TEXT,
  device_token                TEXT,
  created_at                  TIMESTAMPTZ DEFAULT NOW(),
  updated_at                  TIMESTAMPTZ DEFAULT NOW(),
  deleted_at                  TIMESTAMPTZ
);
-- RLS: company_id = private.get_user_company_id()
-- Indexes: company_id, auth_id, email
```

**Notes:**
- `auth_id UUID UNIQUE` links to Supabase Auth. Will be populated during the auth migration phase (not yet implemented).
- TeamMember from Bubble is NOT a separate table in Supabase -- it is just a view of the `users` table.

#### `clients`

```sql
CREATE TABLE clients (
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  bubble_id           TEXT UNIQUE,
  company_id          UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
  name                TEXT NOT NULL,
  email               TEXT,
  phone_number        TEXT,
  notes               TEXT,
  address             TEXT,
  latitude            DOUBLE PRECISION,
  longitude           DOUBLE PRECISION,
  profile_image_url   TEXT,
  created_at          TIMESTAMPTZ DEFAULT NOW(),
  updated_at          TIMESTAMPTZ DEFAULT NOW(),
  deleted_at          TIMESTAMPTZ
);
-- RLS: company_id = private.get_user_company_id()
-- Indexes: company_id, (company_id, name)
```

#### `sub_clients`

```sql
CREATE TABLE sub_clients (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  bubble_id       TEXT UNIQUE,
  client_id       UUID NOT NULL REFERENCES clients(id) ON DELETE CASCADE,
  company_id      UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
  name            TEXT NOT NULL,
  title           TEXT,
  email           TEXT,
  phone_number    TEXT,
  address         TEXT,
  created_at      TIMESTAMPTZ DEFAULT NOW(),
  updated_at      TIMESTAMPTZ DEFAULT NOW(),
  deleted_at      TIMESTAMPTZ
);
-- RLS: company_id = private.get_user_company_id()
-- CASCADE: deleting a client deletes its sub_clients
```

#### `task_types_v2`

```sql
CREATE TABLE task_types_v2 (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  bubble_id       TEXT UNIQUE,
  company_id      UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
  display         TEXT NOT NULL,
  color           TEXT NOT NULL DEFAULT '#417394',
  icon            TEXT,
  is_default      BOOLEAN DEFAULT FALSE,
  display_order   INT DEFAULT 0,
  default_team_member_ids TEXT[] DEFAULT '{}',
  created_at      TIMESTAMPTZ DEFAULT NOW(),
  updated_at      TIMESTAMPTZ DEFAULT NOW(),
  deleted_at      TIMESTAMPTZ
);
-- Named `task_types_v2` to avoid conflict with any existing `task_types` from pipeline
```

#### `projects`

```sql
CREATE TABLE projects (
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  bubble_id           TEXT UNIQUE,
  company_id          UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
  client_id           UUID REFERENCES clients(id) ON DELETE SET NULL,
  title               TEXT NOT NULL,
  address             TEXT,
  latitude            DOUBLE PRECISION,
  longitude           DOUBLE PRECISION,
  status              TEXT NOT NULL DEFAULT 'RFQ'
                        CHECK (status IN ('RFQ','Estimated','Accepted','In Progress','Completed','Closed','Archived')),
  notes               TEXT,
  description         TEXT,
  all_day             BOOLEAN DEFAULT FALSE,
  project_images      TEXT[] DEFAULT '{}',
  team_member_ids     TEXT[] DEFAULT '{}',
  opportunity_id      TEXT,
  start_date          TIMESTAMPTZ,  -- Legacy, computed from tasks in practice
  end_date            TIMESTAMPTZ,
  duration            INT,
  created_at          TIMESTAMPTZ DEFAULT NOW(),
  updated_at          TIMESTAMPTZ DEFAULT NOW(),
  deleted_at          TIMESTAMPTZ
);
-- Indexes: company_id, client_id, (company_id, status)
```

#### `calendar_events`

```sql
CREATE TABLE calendar_events (
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  bubble_id           TEXT UNIQUE,
  company_id          UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
  project_id          UUID REFERENCES projects(id) ON DELETE CASCADE,
  title               TEXT NOT NULL,
  color               TEXT DEFAULT '#417394',
  start_date          TIMESTAMPTZ,
  end_date            TIMESTAMPTZ,
  duration            INT DEFAULT 1,
  team_member_ids     TEXT[] DEFAULT '{}',
  created_at          TIMESTAMPTZ DEFAULT NOW(),
  updated_at          TIMESTAMPTZ DEFAULT NOW(),
  deleted_at          TIMESTAMPTZ
);
-- Indexes: company_id, project_id, (company_id, start_date, end_date)
```

#### `project_tasks`

```sql
CREATE TABLE project_tasks (
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  bubble_id           TEXT UNIQUE,
  company_id          UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
  project_id          UUID NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
  task_type_id        UUID REFERENCES task_types_v2(id) ON DELETE SET NULL,
  calendar_event_id   UUID REFERENCES calendar_events(id) ON DELETE SET NULL,
  custom_title        TEXT,
  task_notes          TEXT,
  status              TEXT NOT NULL DEFAULT 'Booked'
                        CHECK (status IN ('Booked','In Progress','Completed','Cancelled')),
  task_color          TEXT DEFAULT '#417394',
  display_order       INT DEFAULT 0,
  team_member_ids     TEXT[] DEFAULT '{}',
  source_line_item_id TEXT,   -- Traceability: Supabase line item that generated this task
  source_estimate_id  TEXT,   -- Traceability: Supabase estimate that generated this task
  created_at          TIMESTAMPTZ DEFAULT NOW(),
  updated_at          TIMESTAMPTZ DEFAULT NOW(),
  deleted_at          TIMESTAMPTZ
);
-- Indexes: project_id, company_id, (project_id, status)
```

#### `ops_contacts`

```sql
CREATE TABLE ops_contacts (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  bubble_id   TEXT UNIQUE,
  name        TEXT NOT NULL,
  email       TEXT NOT NULL,
  phone       TEXT,
  display     TEXT,
  role        TEXT NOT NULL,
  created_at  TIMESTAMPTZ DEFAULT NOW(),
  updated_at  TIMESTAMPTZ DEFAULT NOW()
);
-- NOT company-scoped (no RLS). Global OPS support contact list.
```

---

### Pipeline Reference Columns (Migration 005)

Migration 005 adds `_ref` UUID foreign key columns to existing pipeline tables, linking them to the new core entity tables from migration 004. The original TEXT ID columns are preserved for backward compatibility.

| Table | New Column | References |
|-------|-----------|------------|
| `opportunities` | `client_ref UUID` | `clients(id) ON DELETE SET NULL` |
| `opportunities` | `project_ref UUID` | `projects(id) ON DELETE SET NULL` |
| `estimates` | `client_ref UUID` | `clients(id) ON DELETE SET NULL` |
| `estimates` | `project_ref UUID` | `projects(id) ON DELETE SET NULL` |
| `invoices` | `client_ref UUID` | `clients(id) ON DELETE SET NULL` |
| `invoices` | `project_ref UUID` | `projects(id) ON DELETE SET NULL` |
| `line_items` | `task_type_ref UUID` | `task_types_v2(id) ON DELETE SET NULL` |
| `task_templates` | `task_type_ref UUID` | `task_types_v2(id) ON DELETE SET NULL` |
| `products` | `task_type_ref UUID` | `task_types_v2(id) ON DELETE SET NULL` |
| `site_visits` | `client_ref UUID` | `clients(id) ON DELETE SET NULL` |
| `site_visits` | `project_ref UUID` | `projects(id) ON DELETE SET NULL` |

All new columns have B-tree indexes for fast lookups.

---

### Supabase ↔ Bubble Field Mapping

| Supabase Column | Bubble Field | Notes |
|----------------|-------------|-------|
| `id` (UUID) | N/A | New Supabase-generated primary key |
| `bubble_id` (TEXT) | `_id` | Bubble's original string ID |
| `company_id` (UUID FK) | `company` / `Company` | Resolved via `bubble_id → UUID` map |
| `client_id` (UUID FK) | `client` / `parentCompany` | Resolved via map |
| `deleted_at` (TIMESTAMPTZ) | `deletedAt` | ISO8601 in Bubble, TIMESTAMPTZ in Supabase |
| `created_at` (TIMESTAMPTZ) | `Created Date` | Auto-set by Supabase |
| `updated_at` (TIMESTAMPTZ) | `Modified Date` | Auto-set by trigger |

### Dual-Backend Transition Pattern

During the migration period, the system operates in a dual-backend mode:

```
                    ┌─────────────────┐
                    │   Bubble.io     │
                    │  (source of     │
                    │   truth for     │
                    │   iOS/Android)  │
                    └────────┬────────┘
                             │
                    Migration API
                    (one-time bulk copy)
                             │
                    ┌────────▼────────┐
                    │    Supabase     │
                    │  (source of     │
                    │   truth for     │
                    │   web app)      │
                    └─────────────────┘
```

**Key rules during transition:**
1. **Web app reads/writes Supabase** for all core entities.
2. **iOS app reads/writes Bubble** (unchanged until mobile migration phase).
3. **Migration is one-directional**: Bubble -> Supabase. Changes made in the web app do NOT sync back to Bubble.
4. **The migration endpoint is idempotent**: Uses `upsert` with `ON CONFLICT bubble_id`, so it is safe to run multiple times.
5. **Pipeline tables retain both ID systems**: TEXT Bubble IDs in original columns, UUID references in new `_ref` columns.

---

## Summary

This data architecture provides:

- **9 core entities** covering all business logic (documented in both SwiftData and Supabase schemas)
- **Soft delete support** for data integrity
- **DTOs for clean API separation** (Bubble -> mobile apps)
- **BubbleFields for byte-perfect mapping** (critical for iOS/Android)
- **Computed properties for task-based scheduling**
- **Defensive patterns to prevent crashes**
- **Supabase PostgreSQL schema** with UUID PKs, RLS, and `bubble_id` migration mapping
- **Pipeline/financial tables** with triggers, audit logging, and atomic operations

**Key Principles**:
1. Always use BubbleFields constants (mobile apps)
2. Always filter out soft-deleted items
3. Never pass models across threads (mobile)
4. Compute project dates from tasks
5. Check company.adminIds for role detection
6. Use `bubble_id` for cross-system entity resolution during migration
7. Web services should query Supabase; mobile services should query Bubble (until mobile migration)

**End of Data Architecture Documentation**
