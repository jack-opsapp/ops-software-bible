# 06. Technical Architecture

**Document Purpose**: Complete technical reference for OPS iOS app architecture, file organization, state management patterns, and development best practices.

**Last Updated**: February 15, 2026
**iOS Codebase**: 351 Swift files, SwiftUI + SwiftData architecture
**Target Platform**: iOS 17.0+, iPhone/iPad

---

## Table of Contents

1. [Architecture Overview](#architecture-overview)
2. [Directory Structure](#directory-structure)
3. [SwiftUI + SwiftData Architecture](#swiftui--swiftdata-architecture)
4. [State Management](#state-management)
5. [Navigation System](#navigation-system)
6. [Dependency Injection](#dependency-injection)
7. [Error Handling](#error-handling)
8. [Performance Optimization](#performance-optimization)
9. [Defensive Programming](#defensive-programming)
10. [Code Organization](#code-organization)
11. [Testing Requirements](#testing-requirements)

---

## Architecture Overview

### Core Philosophy

OPS uses a **field-first architecture** designed for reliability, offline capability, and real-world construction site conditions. Every architectural decision prioritizes:

1. **Offline-first operation** - All critical features work without connectivity
2. **SwiftData persistence** - Local-first data storage with background sync
3. **Defensive SwiftData patterns** - Strict rules to prevent crashes and data corruption
4. **Thread safety** - Explicit main actor usage for UI operations
5. **Simple dependency flow** - Clear, unidirectional data dependencies

### Technology Stack

```
├── UI Layer: SwiftUI (declarative, native)
├── Data Layer: SwiftData (persistence, queries)
├── Network Layer: URLSession + async/await
├── State Management: ObservableObject + @Published
├── Navigation: TabView + NavigationStack
├── Background Tasks: BackgroundTaskManager
├── Image Handling: FileManager (not UserDefaults)
└── Authentication: Keychain + UserDefaults
```

### Architectural Layers

```
┌─────────────────────────────────────────────────────┐
│                    Views (SwiftUI)                   │
│   351 .swift files organized by feature domain      │
├─────────────────────────────────────────────────────┤
│              State Management Layer                  │
│   AppState, DataController, ViewModels              │
├─────────────────────────────────────────────────────┤
│                  Business Logic                      │
│   Managers, Services, Utilities (26 files)         │
├─────────────────────────────────────────────────────┤
│                   Data Layer                         │
│   SwiftData Models (9 entities), DTOs (11 types)   │
├─────────────────────────────────────────────────────┤
│                  Network Layer                       │
│   CentralizedSyncManager, APIService, Endpoints     │
├─────────────────────────────────────────────────────┤
│                 Platform Services                    │
│   CoreLocation, UserNotifications, MapKit          │
└─────────────────────────────────────────────────────┘
```

---

## Directory Structure

### Complete File Organization (351 Swift Files)

```
OPS/
├── OPSApp.swift                    # App entry point, model container setup
├── AppDelegate.swift               # Remote notifications, background tasks
├── AppState.swift                  # Global app state (project mode, UI flags)
├── ContentView.swift               # Root view, auth routing, PIN gating
│
├── DataModels/ (19 files)
│   ├── Project.swift               # Project entity with computed dates
│   ├── ProjectTask.swift           # Task entity with calendar integration
│   ├── CalendarEvent.swift         # Calendar display entity (task-linked)
│   ├── TaskType.swift              # Customizable task categories
│   ├── Client.swift                # Client management
│   ├── SubClient.swift             # Additional client contacts
│   ├── User.swift                  # Team members with role-based access
│   ├── Company.swift               # Organization entity
│   ├── TeamMember.swift            # Team member legacy model
│   ├── OpsContact.swift            # Contacts integration
│   ├── Status.swift                # Project status enum
│   ├── UserRole.swift              # Role-based permissions
│   ├── BubbleTypes.swift           # Bubble API type definitions
│   ├── BubbleImage.swift           # S3 image handling
│   ├── SubscriptionEnums.swift     # Subscription types
│   ├── TaskStatusOption.swift      # Task status configuration
│   └── (3 more supporting files)
│
├── Network/ (44 files)
│   ├── API/ (3 files)
│   │   ├── APIService.swift        # Core HTTP client (URLSession)
│   │   ├── BubbleFields.swift      # Field name constants (CRITICAL)
│   │   └── APIError.swift          # Error types
│   ├── Auth/ (6 files)
│   │   ├── AuthManager.swift       # Authentication coordinator
│   │   ├── GoogleSignInManager.swift
│   │   ├── AppleSignInManager.swift
│   │   ├── KeychainManager.swift   # Secure token storage
│   │   ├── SimplePINManager.swift  # 4-digit PIN (iOS)
│   │   └── AuthError.swift
│   ├── DTOs/ (11 files)
│   │   ├── ProjectDTO.swift        # Project API mapping
│   │   ├── TaskDTO.swift           # Task API mapping
│   │   ├── CalendarEventDTO.swift  # Calendar API mapping
│   │   ├── ClientDTO.swift         # Client API mapping
│   │   ├── UserDTO.swift           # User API mapping
│   │   ├── CompanyDTO.swift        # Company API mapping
│   │   └── (5 more DTOs)
│   ├── Endpoints/ (7 files)
│   │   ├── ProjectEndpoints.swift
│   │   ├── TaskEndpoints.swift
│   │   ├── CalendarEventEndpoints.swift
│   │   ├── ClientEndpoints.swift
│   │   └── (3 more endpoint files)
│   ├── Sync/ (2 files)
│   │   ├── CentralizedSyncManager.swift  # Master sync orchestrator (~2,200 lines)
│   │   └── BackgroundTaskManager.swift   # iOS background task scheduling
│   ├── Services/ (1 file)
│   │   └── AppMessageService.swift
│   ├── ConnectivityMonitor.swift   # Network reachability observer
│   ├── ImageSyncManager.swift      # S3 image upload/download
│   ├── S3UploadService.swift       # Direct S3 upload
│   └── PresignedURLUploadService.swift
│
├── ViewModels/ (2 files)
│   ├── CalendarViewModel.swift     # Calendar state, date selection, filters
│   └── ProjectsViewModel.swift     # Project list state
│
├── Views/ (200+ files organized by feature)
│   ├── MainTabView.swift           # Tab navigation root
│   ├── LoginView.swift             # Authentication entry
│   ├── SplashScreen.swift          # App launch screen
│   ├── SimplePINEntryView.swift    # PIN authentication UI
│   │
│   ├── Home/ (2 files)
│   │   ├── HomeView.swift          # Project carousel, quick actions
│   │   └── HomeContentView.swift   # Home screen content wrapper
│   │
│   ├── JobBoard/ (17 files)
│   │   ├── JobBoardView.swift      # Main job board interface
│   │   ├── JobBoardDashboard.swift # Analytics dashboard
│   │   ├── UniversalJobBoardCard.swift  # Project/task card component
│   │   ├── ProjectFormSheet.swift  # Project create/edit form
│   │   ├── TaskFormSheet.swift     # Task create/edit form
│   │   ├── ClientSheet.swift       # Client form
│   │   ├── ClientListView.swift    # Client directory
│   │   ├── CopyFromProjectSheet.swift
│   │   ├── TaskTypeSheet.swift     # Task type management
│   │   └── (8 more job board components)
│   │
│   ├── Calendar Tab/ (14 files)
│   │   ├── MonthGridView.swift     # Month calendar grid
│   │   ├── Components/ (10 files)
│   │   │   ├── CalendarEventCard.swift
│   │   │   ├── CalendarHeaderView.swift
│   │   │   ├── CalendarFilterView.swift
│   │   │   ├── DayCell.swift
│   │   │   └── (6 more components)
│   │   └── ProjectViews/ (2 files)
│   │       ├── ProjectListView.swift
│   │       └── DayEventsSheet.swift
│   │
│   ├── Settings/ (20 files)
│   │   ├── SettingsView.swift      # Settings root
│   │   ├── ProfileSettingsView.swift
│   │   ├── SecuritySettingsView.swift
│   │   ├── NotificationSettingsView.swift
│   │   ├── MapSettingsView.swift
│   │   ├── DataStorageSettingsView.swift
│   │   ├── Organization/ (3 files)
│   │   │   ├── OrganizationDetailsView.swift
│   │   │   ├── ManageTeamView.swift
│   │   │   └── ManageSubscriptionView.swift
│   │   └── (12 more settings views)
│   │
│   ├── Components/ (90+ files organized by domain)
│   │   ├── Common/ (30 files)
│   │   │   ├── LoadingOverlay.swift
│   │   │   ├── CustomTabBar.swift
│   │   │   ├── AppHeader.swift
│   │   │   ├── SearchField.swift
│   │   │   └── (26 more common components)
│   │   ├── Cards/ (5 files)
│   │   │   ├── ClientInfoCard.swift
│   │   │   ├── LocationCard.swift
│   │   │   ├── NotesCard.swift
│   │   │   └── TeamMembersCard.swift
│   │   ├── Project/ (8 files)
│   │   │   ├── ProjectCard.swift
│   │   │   ├── ProjectDetailsView.swift
│   │   │   ├── TaskDetailsView.swift
│   │   │   └── (5 more project components)
│   │   ├── Images/ (6 files)
│   │   ├── Map/ (4 files)
│   │   ├── User/ (8 files)
│   │   └── (30+ more component files)
│   │
│   ├── Debug/ (10 files)
│   │   ├── DeveloperDashboard.swift
│   │   ├── CalendarEventsDebugView.swift
│   │   └── (8 more debug tools)
│   │
│   └── Subscription/ (4 files)
│       ├── SubscriptionLockoutView.swift
│       └── (3 more subscription views)
│
├── Onboarding/ (45 files)
│   ├── Container/
│   │   └── OnboardingContainer.swift
│   ├── Coordinators/
│   │   └── OnboardingCoordinator.swift
│   ├── Manager/
│   │   └── OnboardingManager.swift
│   ├── Screens/ (14 files)
│   │   ├── WelcomeScreen.swift
│   │   ├── UserTypeSelectionScreen.swift
│   │   ├── CompanySetupScreen.swift
│   │   └── (11 more screens)
│   ├── Views/ (15 files)
│   ├── Components/ (9 files)
│   └── (7 more onboarding files)
│
├── Tutorial/ (19 files)
│   ├── Data/ (6 files)
│   │   ├── TutorialDemoDataManager.swift
│   │   ├── DemoProjects.swift
│   │   └── (4 more demo data files)
│   ├── State/ (2 files)
│   │   ├── TutorialStateManager.swift
│   │   └── TutorialPhase.swift
│   ├── Views/ (6 files)
│   │   ├── TutorialOverlayView.swift
│   │   ├── TutorialTooltipView.swift
│   │   └── (4 more tutorial views)
│   └── (5 more tutorial files)
│
├── Map/ (13 files)
│   ├── Core/ (4 files)
│   │   ├── MapCoordinator.swift    # Map state management
│   │   ├── NavigationEngine.swift  # Turn-by-turn navigation
│   │   ├── LocationService.swift   # CoreLocation wrapper
│   │   └── KalmanHeadingFilter.swift  # Heading smoothing
│   └── Views/ (9 files)
│       ├── MapView.swift
│       ├── MapNavigationView.swift
│       └── (7 more map views)
│
├── Utilities/ (26 files)
│   ├── DataController.swift        # Central data coordinator (300+ lines)
│   ├── DataHealthManager.swift     # Data integrity checks
│   ├── AnalyticsManager.swift      # Event tracking
│   ├── ImageFileManager.swift      # File-based image storage
│   ├── ImageCache.swift            # In-memory image cache
│   ├── LocationManager.swift       # Location permissions + updates
│   ├── NotificationManager.swift   # Push notification handling
│   ├── SubscriptionManager.swift   # Stripe subscription sync
│   └── (18 more utility files)
│
├── Styles/ (17 files)
│   ├── OPSStyle.swift              # Design system constants
│   ├── Fonts.swift                 # Typography definitions
│   └── Components/ (15 files)
│       ├── ButtonStyles.swift
│       ├── CardStyles.swift
│       ├── FormInputs.swift
│       └── (12 more style components)
│
├── Extensions/ (4 files)
│   ├── String+AddressFormatting.swift
│   ├── UIApplication+Extensions.swift
│   └── (2 more extensions)
│
├── Services/ (1 file)
│   └── OneSignalService.swift      # Push notification provider
│
└── Navigation/ (1 file)
    └── PersistentNavigationHeader.swift
```

### File Count Summary

```
Total: 351 Swift files

By Category:
- Views/UI: ~200 files (57%)
- Network/API: 44 files (13%)
- Onboarding: 45 files (13%)
- Utilities: 26 files (7%)
- Tutorial: 19 files (5%)
- Data Models: 19 files (5%)
- Map: 13 files (4%)
- Styles: 17 files (5%)
- Other: ~18 files (5%)
```

---

## SwiftUI + SwiftData Architecture

### SwiftData Model Container Setup

```swift
// OPSApp.swift
@main
struct OPSApp: App {
    // Shared model container for entire app
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            User.self,
            Project.self,
            Company.self,
            TeamMember.self,
            Client.self,
            SubClient.self,
            ProjectTask.self,
            TaskType.self,
            TaskStatusOption.self,
            CalendarEvent.self,
            OpsContact.self
        ])

        let modelConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            allowsSave: true
        )

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Failed to create model container: \(error.localizedDescription)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(dataController)
        }
        .modelContainer(sharedModelContainer)
    }
}
```

### Model Definition Pattern

```swift
// Example: Project.swift
@Model
final class Project: Identifiable {
    // MARK: - Stored Properties
    var id: String
    var title: String
    var companyId: String
    var status: Status
    var needsSync: Bool = false
    var deletedAt: Date?           // Soft delete

    // MARK: - Computed Properties
    var computedStartDate: Date? {
        tasks.compactMap { $0.calendarEvent?.startDate }.min()
    }

    // MARK: - Relationships
    @Relationship(deleteRule: .cascade, inverse: \ProjectTask.project)
    var tasks: [ProjectTask] = []

    @Relationship(deleteRule: .nullify)
    var client: Client?

    // MARK: - Transient Properties (not persisted)
    @Transient var lastTapped: Date?
}
```

### SwiftData Query Pattern

```swift
// In Views: Use @Query for automatic UI updates
@Query(
    filter: #Predicate<Project> {
        $0.deletedAt == nil && $0.status != .archived
    },
    sort: \Project.title
) var projects: [Project]

// In Logic: Use FetchDescriptor for manual queries
func fetchActiveProjects() -> [Project] {
    let descriptor = FetchDescriptor<Project>(
        predicate: #Predicate {
            $0.deletedAt == nil && $0.status != .archived
        },
        sortBy: [SortDescriptor(\.title)]
    )
    return try? modelContext.fetch(descriptor) ?? []
}
```

### DTO to Model Conversion

```swift
// DTOs handle API ↔ SwiftData conversion
struct ProjectDTO: Decodable {
    let id: String
    let name: String
    let status: String?

    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case name = "Name"
        case status = "Status"
    }

    func toModel() -> Project {
        let project = Project(id: id, title: name, companyId: "")
        project.status = Status(rawValue: status ?? "") ?? .rfq
        return project
    }
}
```

---

## State Management

### State Architecture Overview

```
┌─────────────────────────────────────────────────────┐
│                   AppState                           │
│   Global UI state (project mode, sheets, flags)    │
│   Published properties for cross-view coordination  │
└─────────────────────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────┐
│                DataController                        │
│   Central data coordinator, dependency manager      │
│   Authentication, sync, current user                │
└─────────────────────────────────────────────────────┘
                         │
            ┌────────────┼────────────┐
            ▼            ▼            ▼
┌──────────────┐ ┌──────────────┐ ┌──────────────┐
│ ViewModels   │ │   Managers   │ │ SyncManager  │
│ (per-screen) │ │  (services)  │ │ (background) │
└──────────────┘ └──────────────┘ └──────────────┘
```

### AppState (Global UI State)

**File**: `OPS/AppState.swift` (~200 lines)

**Purpose**: Manages global UI state that crosses view boundaries (e.g., project mode, sheet visibility).

```swift
class AppState: ObservableObject {
    // MARK: - Active Project State
    @Published var activeProjectID: String?
    @Published var activeTaskID: String?
    @Published var isViewingDetailsOnly: Bool = false
    @Published var showProjectDetails: Bool = false

    // MARK: - UI State Flags
    @Published var isLoadingProjects: Bool = false
    @Published var shouldRestartTutorial: Bool = false

    // MARK: - Project Completion Cascade
    @Published var projectPendingCompletion: Project?
    @Published var showingGlobalCompletionChecklist: Bool = false

    // MARK: - Computed Properties
    var isInProjectMode: Bool {
        activeProjectID != nil && !isViewingDetailsOnly
    }

    // MARK: - Actions
    func enterProjectMode(projectID: String) {
        self.isViewingDetailsOnly = false
        self.activeProjectID = projectID
        NotificationCenter.default.post(
            name: Notification.Name("FetchActiveProject"),
            object: nil,
            userInfo: ["projectID": projectID]
        )
    }

    func viewProjectDetails(_ project: Project) {
        self.isViewingDetailsOnly = true
        self.activeProjectID = project.id
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.showProjectDetails = true
        }
    }

    func exitProjectMode() {
        self.showProjectDetails = false
        self.isViewingDetailsOnly = false
        self.activeProjectID = nil
        self.activeTaskID = nil
    }

    func resetForLogout() {
        // Clear all state on logout
        self.showProjectDetails = false
        self.isViewingDetailsOnly = false
        self.activeProjectID = nil
        self.activeTaskID = nil
        self.isLoadingProjects = false
        self.projectPendingCompletion = nil
        self.showingGlobalCompletionChecklist = false
    }
}
```

**Usage Pattern**:
```swift
struct HomeView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        // Access global state
        if appState.isLoadingProjects {
            LoadingOverlay()
        }
    }
}
```

### DataController (Central Coordinator)

**File**: `OPS/Utilities/DataController.swift` (~800+ lines)

**Purpose**: Central coordinator for data, authentication, sync, and app-wide dependencies.

```swift
class DataController: ObservableObject {
    // MARK: - Published States
    @Published var isAuthenticated = false
    @Published var currentUser: User?
    @Published var isConnected = false
    @Published var isSyncing = false
    @Published var hasPendingSyncs = false
    @Published var isPerformingInitialSync = false

    // MARK: - Dependencies
    let authManager: AuthManager
    let apiService: APIService
    private let keychainManager: KeychainManager
    private let connectivityMonitor: ConnectivityMonitor
    var modelContext: ModelContext?

    // MARK: - Public Access
    var syncManager: CentralizedSyncManager!
    var imageSyncManager: ImageSyncManager!
    @Published var simplePINManager = SimplePINManager()

    // MARK: - Initialization
    init() {
        self.keychainManager = KeychainManager()
        self.authManager = AuthManager()
        self.connectivityMonitor = ConnectivityMonitor()
        self.apiService = APIService(authManager: authManager)

        setupConnectivityMonitoring()

        Task {
            await checkExistingAuth()
        }
    }

    // MARK: - Setup
    @MainActor
    func setModelContext(_ context: ModelContext) {
        self.modelContext = context

        Task {
            await cleanupDuplicateUsers()
            await MainActor.run {
                if isAuthenticated || currentUser != nil {
                    initializeSyncManager()
                }
            }
        }
    }

    @MainActor
    func initializeSyncManager() {
        guard let modelContext = modelContext else { return }
        guard syncManager == nil else { return }

        self.syncManager = CentralizedSyncManager(
            modelContext: modelContext,
            apiService: apiService,
            connectivityMonitor: connectivityMonitor
        )

        self.imageSyncManager = ImageSyncManager(
            modelContext: modelContext,
            apiService: apiService,
            connectivityMonitor: connectivityMonitor
        )
    }

    // MARK: - Data Access
    func getProject(id: String) -> Project? {
        guard let modelContext = modelContext else { return nil }
        let descriptor = FetchDescriptor<Project>(
            predicate: #Predicate { $0.id == id }
        )
        return try? modelContext.fetch(descriptor).first
    }
}
```

**Usage Pattern**:
```swift
struct ContentView: View {
    @EnvironmentObject private var dataController: DataController

    var body: some View {
        if dataController.isAuthenticated {
            MainTabView()
        } else {
            LoginView()
        }
    }
}
```

### Per-Screen ViewModels

**Pattern**: ViewModels handle screen-specific state and business logic.

**Example: CalendarViewModel** (500 lines)

```swift
class CalendarViewModel: ObservableObject {
    // MARK: - Published Properties
    @Published var selectedDate: Date = Date()
    @Published var viewMode: CalendarViewMode = .week
    @Published var projectIdsForSelectedDate: [String] = []
    @Published var calendarEventIdsForSelectedDate: [String] = []
    @Published var selectedTeamMemberIds: Set<String> = []
    @Published var selectedTaskTypeIds: Set<String> = []

    // MARK: - Dependencies
    var dataController: DataController?

    // MARK: - Computed Properties
    var projectsForSelectedDate: [Project] {
        guard let dataController = dataController else { return [] }
        return projectIdsForSelectedDate.compactMap {
            dataController.getProject(id: $0)
        }
    }

    // MARK: - Actions
    func selectDate(_ date: Date, userInitiated: Bool = false) {
        selectedDate = date
        loadProjectsForDate(date)
    }

    func applyFilters(
        teamMemberIds: Set<String>,
        taskTypeIds: Set<String>
    ) {
        selectedTeamMemberIds = teamMemberIds
        selectedTaskTypeIds = taskTypeIds
        clearProjectCountCache()
        loadProjectsForDate(selectedDate)
    }

    private func loadProjectsForDate(_ date: Date) {
        guard let dataController = dataController else { return }
        var events = dataController.getCalendarEventsForCurrentUser(for: date)
        events = applyEventFilters(to: events)

        DispatchQueue.main.async { [weak self] in
            self?.calendarEventIdsForSelectedDate = events.map { $0.id }
        }
    }
}
```

**Usage Pattern**:
```swift
struct ScheduleView: View {
    @StateObject private var viewModel = CalendarViewModel()
    @EnvironmentObject private var dataController: DataController

    var body: some View {
        VStack {
            // UI uses viewModel state
            Text("Selected: \(viewModel.selectedDate)")
        }
        .onAppear {
            viewModel.setDataController(dataController)
        }
    }
}
```

### State Flow Summary

```
User Interaction
    ↓
View calls ViewModel method
    ↓
ViewModel updates @Published properties
    ↓
View automatically re-renders (SwiftUI observation)
    ↓
ViewModel calls DataController for data operations
    ↓
DataController modifies SwiftData via modelContext
    ↓
@Query properties automatically update
    ↓
View re-renders with fresh data
```

---

## Navigation System

### Architecture: TabView + NavigationStack

OPS uses a **hybrid navigation system**:
- **TabView** for top-level app sections (Home, Job Board, Schedule, Settings)
- **NavigationStack** within each tab for hierarchical navigation
- **Sheet presentations** for modal workflows (forms, details)

### Main Navigation Structure

```swift
// MainTabView.swift (~300 lines)
struct MainTabView: View {
    @State private var selectedTab = 0

    private var tabs: [TabItem] {
        var baseTabs: [TabItem] = [
            TabItem(iconName: "house.fill")        // Home
        ]

        // All users get Job Board
        baseTabs.append(TabItem(iconName: "briefcase.fill"))

        // Schedule and Settings for all users
        baseTabs.append(contentsOf: [
            TabItem(iconName: "calendar"),         // Schedule
            TabItem(iconName: "gearshape.fill")    // Settings
        ])

        return baseTabs
    }

    var body: some View {
        ZStack {
            // Tab content with slide transitions
            ZStack {
                switch selectedTab {
                case 0: HomeView()
                case 1: JobBoardView()
                case 2: ScheduleView()
                case 3: SettingsView()
                default: HomeView()
                }
            }
            .transition(slideTransition)
            .animation(.spring(response: 0.3), value: selectedTab)

            // Custom tab bar overlay
            VStack {
                Spacer()
                CustomTabBar(selectedTab: $selectedTab, tabs: tabs)
            }

            // Floating action menu (context-aware)
            FloatingActionMenu()
                .opacity(!isSettingsTab ? 1 : 0)
        }
    }
}
```

### Sheet-Based Navigation Pattern

**Pattern**: Forms and detail views use `.sheet()` for modal presentation.

```swift
struct JobBoardView: View {
    @State private var showingProjectForm = false
    @State private var selectedProject: Project?

    var body: some View {
        VStack {
            // Main content
        }
        .sheet(isPresented: $showingProjectForm) {
            ProjectFormSheet(
                project: selectedProject,
                onSave: { updatedProject in
                    // Handle save
                    showingProjectForm = false
                }
            )
        }
    }
}
```

### Deep Linking via NotificationCenter

**Pattern**: Cross-view navigation uses `NotificationCenter` for decoupling.

```swift
// Posting a navigation request
NotificationCenter.default.post(
    name: Notification.Name("ShowProjectDetailsRequest"),
    object: nil,
    userInfo: ["projectID": project.id]
)

// Listening for navigation request (in MainTabView)
.onReceive(showProjectObserver) { notification in
    if let projectID = notification.userInfo?["projectID"] as? String {
        DispatchQueue.main.async {
            if let project = dataController.getProject(id: projectID) {
                appState.viewProjectDetails(project)
            }
        }
    }
}
```

### Navigation Events

```swift
// Defined in MainTabView.swift
private let fetchProjectObserver = NotificationCenter.default
    .publisher(for: Notification.Name("FetchActiveProject"))

private let showProjectObserver = NotificationCenter.default
    .publisher(for: Notification.Name("ShowProjectDetailsRequest"))

private let navigateToMapObserver = NotificationCenter.default
    .publisher(for: Notification.Name("NavigateToMapView"))

private let openProjectDetailsObserver = NotificationCenter.default
    .publisher(for: Notification.Name("OpenProjectDetails"))

private let openTaskDetailsObserver = NotificationCenter.default
    .publisher(for: Notification.Name("OpenTaskDetails"))
```

### Persistent State Across Navigation

**Pattern**: Use `@StateObject` for view-owned state that persists across navigation.

```swift
struct ScheduleView: View {
    @StateObject private var viewModel = CalendarViewModel()
    // viewModel persists even when view is removed from hierarchy
}
```

---

## Dependency Injection

### Pattern: Environment Objects + Manual Injection

OPS uses a **hybrid dependency injection** approach:
1. **EnvironmentObject** for app-wide singletons (DataController, AppState)
2. **Manual injection** for scoped dependencies (ViewModels, Managers)

### Environment Object Pattern

```swift
// Setup in OPSApp.swift
@main
struct OPSApp: App {
    @StateObject private var dataController = DataController()
    @StateObject private var notificationManager = NotificationManager.shared
    @StateObject private var subscriptionManager = SubscriptionManager.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(dataController)
                .environmentObject(notificationManager)
                .environmentObject(subscriptionManager)
        }
    }
}

// Access in any view
struct AnyView: View {
    @EnvironmentObject private var dataController: DataController
    // Automatically available without manual passing
}
```

### Manual Injection Pattern

```swift
// ViewModels receive dependencies explicitly
struct ScheduleView: View {
    @StateObject private var viewModel = CalendarViewModel()
    @EnvironmentObject private var dataController: DataController

    var body: some View {
        VStack {
            // content
        }
        .onAppear {
            // Inject dependency after view appears
            viewModel.setDataController(dataController)
        }
    }
}
```

### Singleton Services

**Pattern**: Shared services use static `shared` instances.

```swift
// NotificationManager.swift
class NotificationManager: ObservableObject {
    static let shared = NotificationManager()

    private init() {
        // Singleton pattern prevents multiple instances
    }
}

// Usage
let manager = NotificationManager.shared
```

### Dependency Graph

```
OPSApp
  ├── DataController (singleton)
  │     ├── AuthManager
  │     ├── APIService
  │     ├── ConnectivityMonitor
  │     ├── SyncManager (initialized on login)
  │     └── ImageSyncManager (initialized on login)
  │
  ├── AppState (singleton)
  │
  ├── NotificationManager (singleton)
  │
  └── SubscriptionManager (singleton)
        └── DataController (injected)

Views
  ├── Access via @EnvironmentObject
  └── Create @StateObject ViewModels
        └── Inject DataController on appear
```

---

## Error Handling

### Strategy: Graceful Degradation

OPS prioritizes **continuing operation** over crashing. Errors are logged, displayed to users when actionable, and handled gracefully.

### Error Handling Layers

```
┌─────────────────────────────────────────────────────┐
│           User-Facing Error Messages                │
│   Clear, actionable messages in UI                  │
└─────────────────────────────────────────────────────┘
                         ↓
┌─────────────────────────────────────────────────────┐
│              Error Recovery Logic                    │
│   Retry mechanisms, fallbacks, offline queuing     │
└─────────────────────────────────────────────────────┘
                         ↓
┌─────────────────────────────────────────────────────┐
│             Structured Error Types                   │
│   APIError, AuthError, domain-specific errors       │
└─────────────────────────────────────────────────────┘
                         ↓
┌─────────────────────────────────────────────────────┐
│               Logging & Diagnostics                  │
│   Print statements with [TAG] prefixes              │
└─────────────────────────────────────────────────────┘
```

### Error Type Definitions

```swift
// APIError.swift
enum APIError: Error, LocalizedError {
    case networkError(Error)
    case invalidResponse
    case unauthorized
    case serverError(Int)
    case decodingError(Error)
    case rateLimited

    var errorDescription: String? {
        switch self {
        case .networkError:
            return "Network connection failed. Check your internet."
        case .unauthorized:
            return "Session expired. Please log in again."
        case .rateLimited:
            return "Too many requests. Please wait a moment."
        default:
            return "Something went wrong. Please try again."
        }
    }
}

// AuthError.swift
enum AuthError: Error, LocalizedError {
    case invalidCredentials
    case tokenExpired
    case missingToken
    case googleSignInFailed(Error)

    var errorDescription: String? {
        switch self {
        case .invalidCredentials:
            return "Email or password is incorrect."
        case .tokenExpired:
            return "Session expired. Please log in again."
        default:
            return "Authentication failed."
        }
    }
}
```

### Error Handling in Network Layer

```swift
// APIService.swift
func request<T: Decodable>(
    endpoint: String,
    method: HTTPMethod
) async throws -> T {
    // Step 1: Build request
    guard let url = URL(string: baseURL + endpoint) else {
        throw APIError.invalidResponse
    }

    var request = URLRequest(url: url)
    request.httpMethod = method.rawValue

    do {
        // Step 2: Execute request
        let (data, response) = try await URLSession.shared.data(for: request)

        // Step 3: Validate response
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200...299:
            // Success - decode response
            do {
                return try JSONDecoder().decode(T.self, from: data)
            } catch {
                print("[API_ERROR] Decoding failed: \(error)")
                throw APIError.decodingError(error)
            }
        case 401:
            throw APIError.unauthorized
        case 429:
            throw APIError.rateLimited
        default:
            throw APIError.serverError(httpResponse.statusCode)
        }
    } catch let error as APIError {
        // Re-throw APIError as-is
        throw error
    } catch {
        // Wrap unknown errors
        print("[API_ERROR] Network error: \(error)")
        throw APIError.networkError(error)
    }
}
```

### Error Handling in Sync Manager

```swift
// CentralizedSyncManager.swift
func syncProjects() async {
    do {
        // Attempt sync
        let projects = try await apiService.fetchProjects()

        // Update local database
        await MainActor.run {
            for projectDTO in projects {
                let project = projectDTO.toModel()
                modelContext.insert(project)
            }
            try? modelContext.save()
        }
    } catch APIError.unauthorized {
        // Critical: Force logout
        print("[SYNC] Unauthorized - forcing logout")
        await MainActor.run {
            NotificationCenter.default.post(name: .forceLogout, object: nil)
        }
    } catch APIError.rateLimited {
        // Temporary: Schedule retry
        print("[SYNC] Rate limited - scheduling retry in 60s")
        scheduleRetry(delay: 60)
    } catch {
        // Non-critical: Continue with local data
        print("[SYNC] Sync failed: \(error) - continuing with local data")
    }
}
```

### Error Display in Views

```swift
struct ProjectFormSheet: View {
    @State private var errorMessage: String?
    @State private var showingError = false

    var body: some View {
        VStack {
            // Form content
        }
        .alert("Error", isPresented: $showingError) {
            Button("OK") {
                showingError = false
            }
        } message: {
            Text(errorMessage ?? "An error occurred.")
        }
    }

    func saveProject() {
        Task {
            do {
                try await dataController.saveProject(project)
            } catch {
                errorMessage = error.localizedDescription
                showingError = true
            }
        }
    }
}
```

### Logging Pattern

**Convention**: Use `[TAG]` prefixes for searchable logs.

```swift
print("[APP_LAUNCH] Starting app launch sync")
print("[SYNC] Syncing projects...")
print("[AUTH] User logged in: \(user.id)")
print("[DATA_HEALTH] Health check passed")
print("[API_ERROR] Request failed: \(error)")
```

**Common Tags**:
- `[APP_LAUNCH]` - App initialization
- `[SYNC]` - Sync operations
- `[AUTH]` - Authentication
- `[API_ERROR]` - API failures
- `[DATA_HEALTH]` - Data integrity
- `[MIGRATION]` - Data migrations
- `[PROJECT_COMPLETION]` - Project completion flow

---

## Performance Optimization

### Critical Optimizations

OPS implements aggressive performance optimizations for real-world field conditions (older devices, poor connectivity, large datasets).

### 1. Lazy Loading & Pagination

**Problem**: Loading all 200+ projects at once causes lag.

**Solution**: Load projects incrementally, cache counts.

```swift
// CalendarViewModel.swift
private var projectCountCache: [String: Int] = [:]

func projectCount(for date: Date) -> Int {
    // CRITICAL: NEVER do database queries during rendering
    // Always return from cache only, even if 0

    if Calendar.current.isDate(date, inSameDayAs: selectedDate) {
        return calendarEventIdsForSelectedDate.count
    }

    let dateKey = formatDateKey(date)
    return projectCountCache[dateKey] ?? 0
}

func loadProjectsForDate(_ date: Date) {
    // Only load projects for ONE date at a time
    var events = dataController.getCalendarEventsForCurrentUser(for: date)

    // Cache count for calendar rendering
    projectCountCache[formatDateKey(date)] = events.count
}
```

### 2. Avoiding SwiftData Invalidation

**Problem**: Storing SwiftData models in `@Published` properties causes crashes when models update.

**Solution**: Store IDs, fetch fresh models on access.

```swift
// ❌ BAD: Storing models causes invalidation crashes
@Published var projectsForSelectedDate: [Project] = []

// ✅ GOOD: Store IDs, fetch on demand
@Published var projectIdsForSelectedDate: [String] = []

var projectsForSelectedDate: [Project] {
    guard let dataController = dataController else { return [] }
    return projectIdsForSelectedDate.compactMap {
        dataController.getProject(id: $0)
    }
}
```

### 3. Image Optimization

**Problem**: Storing images in UserDefaults causes crashes (>4MB limit).

**Solution**: File-based storage with memory cache.

```swift
// ImageFileManager.swift
class ImageFileManager {
    static let shared = ImageFileManager()

    func saveImage(_ image: UIImage, filename: String) -> Bool {
        let fileURL = getDocumentsDirectory().appendingPathComponent(filename)

        // Compress to JPEG (80% quality)
        guard let data = image.jpegData(compressionQuality: 0.8) else {
            return false
        }

        do {
            try data.write(to: fileURL)
            return true
        } catch {
            print("[IMAGE] Failed to save: \(error)")
            return false
        }
    }

    func loadImage(filename: String) -> UIImage? {
        let fileURL = getDocumentsDirectory().appendingPathComponent(filename)
        return UIImage(contentsOfFile: fileURL.path)
    }
}

// ImageCache.swift (memory cache)
class ImageCache {
    static let shared = ImageCache()
    private var cache = NSCache<NSString, UIImage>()

    func get(_ key: String) -> UIImage? {
        return cache.object(forKey: key as NSString)
    }

    func set(_ image: UIImage, forKey key: String) {
        cache.setObject(image, forKey: key as NSString)
    }
}
```

### 4. Background Sync

**Problem**: Foreground syncs block UI.

**Solution**: Background task scheduling.

```swift
// BackgroundTaskManager.swift
func scheduleBackgroundSync() {
    let request = BGAppRefreshTaskRequest(identifier: "co.opsapp.sync")
    request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60) // 15 min

    do {
        try BGTaskScheduler.shared.submit(request)
    } catch {
        print("[BG_SYNC] Failed to schedule: \(error)")
    }
}

// Handle background task
BGTaskScheduler.shared.register(forTaskWithIdentifier: "co.opsapp.sync") { task in
    Task {
        await syncManager.triggerBackgroundSync()
        task.setTaskCompleted(success: true)
    }
}
```

### 5. Debouncing Sync Triggers

**Problem**: Rapid changes trigger redundant syncs.

**Solution**: 2-second debounce delay.

```swift
// CentralizedSyncManager.swift
private var syncDebounceTimer: Timer?
private let syncDebounceDelay: TimeInterval = 2.0

func markEntityForSync<T: PersistentModel>(_ entity: T) {
    entity.needsSync = true
    entity.syncPriority = 2

    // Debounce: Cancel pending sync, schedule new one
    syncDebounceTimer?.invalidate()
    syncDebounceTimer = Timer.scheduledTimer(withTimeInterval: syncDebounceDelay, repeats: false) { _ in
        Task {
            await self.triggerBackgroundSync()
        }
    }
}
```

### 6. Query Optimization

**Pattern**: Use indexed predicates, avoid complex computed properties in queries.

```swift
// ✅ GOOD: Simple predicate on indexed field
@Query(
    filter: #Predicate<Project> { $0.deletedAt == nil },
    sort: \Project.title
) var projects: [Project]

// ❌ BAD: Complex computed property in predicate (slow)
@Query(
    filter: #Predicate<Project> {
        $0.computedStartDate >= Date() && $0.tasks.count > 0
    }
) var projects: [Project]
```

---

## Defensive Programming

### SwiftData Best Practices

OPS follows **strict defensive patterns** to prevent SwiftData crashes and data corruption.

### 1. Never Pass Models to Background Tasks

```swift
// ❌ INCORRECT: Passing model causes crashes
Task.detached {
    await processProject(project: project)  // CRASH!
}

// ✅ CORRECT: Pass IDs, fetch fresh models
Task.detached {
    await processProject(projectId: project.id)
}

func processProject(projectId: String) async {
    let context = ModelContext(sharedModelContainer)
    guard let project = try? context.fetch(
        FetchDescriptor<Project>(
            predicate: #Predicate { $0.id == projectId }
        )
    ).first else { return }

    // Work with fresh model from this context
    project.needsSync = false
    try? context.save()
}
```

### 2. Always Fetch Fresh Models

```swift
// ❌ BAD: Reusing stale model reference
func updateProject(_ project: Project) {
    project.status = .completed
    try? modelContext.save()
}

// ✅ GOOD: Fetch fresh model
func updateProject(projectId: String) {
    guard let project = getProject(id: projectId) else { return }
    project.status = .completed
    try? modelContext.save()
}
```

### 3. Use @MainActor for UI Operations

```swift
// ✅ CORRECT: All SwiftData operations on main thread
@MainActor
func updateProjectStatus(_ project: Project, status: Status) {
    let context = dataController.modelContext
    project.status = status
    try? context.save()
}
```

### 4. Explicit ModelContext.save()

```swift
// ❌ BAD: Relying on auto-save (unreliable)
project.name = "Updated Name"

// ✅ GOOD: Explicit save
project.name = "Updated Name"
try? modelContext.save()
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
    guard let modelContext = modelContext else { return }

    // Delete all data to prevent cross-user contamination
    try? modelContext.delete(model: Project.self)
    try? modelContext.delete(model: User.self)
    try? modelContext.delete(model: Client.self)
    try? modelContext.delete(model: ProjectTask.self)
    try? modelContext.delete(model: CalendarEvent.self)
    try? modelContext.delete(model: TaskType.self)
    try? modelContext.save()

    // Clear UserDefaults
    UserDefaults.standard.removePersistentDomain(forName: Bundle.main.bundleIdentifier!)

    // Reset state
    isAuthenticated = false
    currentUser = nil
}
```

### 7. Soft Delete Strategy

**Pattern**: Never hard delete - use `deletedAt` timestamp.

```swift
// ❌ BAD: Hard delete
modelContext.delete(project)

// ✅ GOOD: Soft delete
project.deletedAt = Date()
try? modelContext.save()

// Query excludes soft-deleted items
@Query(
    filter: #Predicate<Project> { $0.deletedAt == nil }
) var projects: [Project]
```

### 8. Null-Safe Relationship Access

```swift
// ✅ Safe relationship access
if let client = project.client {
    Text(client.name)
}

// ✅ Safe array access
let taskCount = project.tasks.count  // Safe, never nil

// ❌ Unsafe force unwrap
Text(project.client!.name)  // CRASH if client is nil
```

---

## Code Organization

### File Organization Principles

1. **Feature-based organization** - Group by business domain (JobBoard/, Calendar/, Settings/)
2. **Component reusability** - Shared components in Views/Components/
3. **Flat where possible** - Avoid deep nesting (max 3 levels)
4. **Clear naming** - File names match primary type (ProjectFormSheet.swift contains ProjectFormSheet)

### Naming Conventions

**Files**:
- Views: `ProjectFormSheet.swift`, `CalendarEventCard.swift`
- Models: `Project.swift`, `User.swift`
- ViewModels: `CalendarViewModel.swift`
- Managers: `DataController.swift`, `AuthManager.swift`
- Extensions: `String+AddressFormatting.swift`

**Types**:
- Views: `struct ProjectFormSheet: View`
- Models: `@Model final class Project`
- ViewModels: `class CalendarViewModel: ObservableObject`
- Managers: `class AuthManager`

**Properties**:
- Published: `@Published var isLoading = false`
- Private: `private let apiService: APIService`
- Computed: `var isActive: Bool { status == .inProgress }`

**Functions**:
- Actions: `func saveProject()`, `func deleteClient()`
- Queries: `func getProject(id: String) -> Project?`
- Async: `func syncProjects() async`
- MainActor: `@MainActor func updateUI()`

### Code Style

**SwiftUI View Structure**:
```swift
struct ExampleView: View {
    // MARK: - Environment
    @EnvironmentObject private var dataController: DataController

    // MARK: - State
    @State private var isLoading = false
    @StateObject private var viewModel = ExampleViewModel()

    // MARK: - Computed Properties
    var isActive: Bool {
        viewModel.status == .active
    }

    // MARK: - Body
    var body: some View {
        VStack {
            // Content
        }
        .onAppear {
            setupView()
        }
    }

    // MARK: - Private Methods
    private func setupView() {
        viewModel.setDataController(dataController)
    }
}
```

**Class Structure**:
```swift
class ExampleManager: ObservableObject {
    // MARK: - Published Properties
    @Published var isActive = false

    // MARK: - Private Properties
    private let apiService: APIService

    // MARK: - Initialization
    init(apiService: APIService) {
        self.apiService = apiService
    }

    // MARK: - Public Methods
    func performAction() async {
        // Implementation
    }

    // MARK: - Private Methods
    private func helperMethod() {
        // Implementation
    }
}
```

### Comments Style

```swift
// MARK: - Section Header (for organization)

/// Documentation comment for public API
/// - Parameter id: The project ID
/// - Returns: Project if found, nil otherwise
func getProject(id: String) -> Project?

// Single-line explanation for complex logic
let adjustedDate = calendar.date(byAdding: .day, value: 7, to: date)

// CRITICAL: Important warning
// ❌ Don't do this
// ✅ Do this instead
```

---

## Testing Requirements

### Field Testing Checklist

OPS must be tested in **real field conditions**:

#### 1. Glove Testing
- All touch targets ≥ 44×44pt (prefer 56×56pt)
- Test with thick work gloves
- Swipe gestures work with reduced precision
- No accidental taps on adjacent elements

#### 2. Sunlight Testing
- Test outdoors in direct sunlight
- All text readable with glare
- Contrast ratios: 7:1 for normal text, 4.5:1 for large text
- Dark theme reduces screen glare

#### 3. Offline Testing
- All critical features work without connectivity
- Data syncs when connection restored
- No crashes on network timeout
- Offline indicator visible

#### 4. Old Device Testing
- Test on 3-year-old iPhone (minimum: iPhone X)
- Smooth scrolling with 200+ projects
- No lag on image loading
- Background sync doesn't drain battery

#### 5. Poor Connectivity Testing
- Test with 1 bar LTE
- Sync retries with exponential backoff
- Images load progressively
- No infinite spinners

#### 6. Real Data Testing
- Import 200+ projects
- Create 50+ tasks in one project
- Upload 20+ images to one project
- Test with 10+ team members

### Automated Testing Gaps

**Current State**: OPS has **no automated tests** (UI tests, unit tests, integration tests).

**Reason**: Startup prioritizing shipping features over test coverage.

**Risk**: Regressions caught in production, reliance on manual testing.

**Future**: Add tests for critical paths (auth, sync, offline mode).

---

## Summary

### Architectural Strengths

1. **SwiftUI + SwiftData** - Modern, declarative, native iOS
2. **Offline-first** - Local persistence with background sync
3. **Defensive SwiftData patterns** - Prevents crashes and corruption
4. **Clear separation of concerns** - Views, ViewModels, DataController, Managers
5. **Field-tested optimizations** - Lazy loading, caching, background tasks

### Architectural Challenges

1. **No automated tests** - Regression risk
2. **Complex state management** - Multiple sources of truth (AppState, DataController, ViewModels)
3. **NotificationCenter coupling** - Deep linking via NotificationCenter is brittle
4. **Large ViewModels** - CalendarViewModel is 500+ lines

### Android Conversion Implications

**Easy to Convert**:
- Data models (SwiftData → Room entities)
- Network layer (URLSession → Retrofit)
- State management (ObservableObject → StateFlow/ViewModel)

**Hard to Convert**:
- SwiftUI views (no 1:1 Compose equivalent)
- Navigation system (TabView + sheets → Compose Navigation)
- Environment objects (SwiftUI-specific → Hilt DI)

**Critical Patterns to Preserve**:
- Offline-first architecture
- Defensive data patterns (IDs not models, explicit saves)
- Soft delete strategy
- Background sync debouncing

---

**End of Technical Architecture Documentation**

This document provides complete architectural context for OPS iOS app. Reference alongside:
- `01_IOS_ARCHITECTURE_OVERVIEW.md` - High-level overview
- `02_DATA_MODELS.md` - SwiftData models and relationships
- `03_NETWORKING_AND_SYNC.md` - API and sync details
- `10_ANDROID_CONVERSION_PLAN.md` - Android conversion strategy
