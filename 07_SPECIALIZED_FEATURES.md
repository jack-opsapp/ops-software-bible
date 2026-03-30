# 07 - Specialized Features

**Last Updated:** March 19, 2026
**OPS Version:** iOS v1.7, Android Planning Phase
**Purpose:** Complete reference for specialized features including navigation, tutorial system, calendar scheduling, image management, PIN security, project notes system, photo annotations, inventory management, notifications, crew location tracking, and advanced UI patterns.

---

## Table of Contents

1. [Turn-by-Turn Navigation System](#1-turn-by-turn-navigation-system)
2. [Tutorial & Demo Mode](#2-tutorial--demo-mode)
3. [Calendar Event Scheduling](#3-calendar-event-scheduling)
4. [Image Capture & S3 Sync](#4-image-capture--s3-sync)
5. [PIN Management](#5-pin-management)
6. [Job Board Features](#6-job-board-features)
7. [Swipe-to-Change-Status Gestures](#7-swipe-to-change-status-gestures)
8. [Form Sheets with Progressive Disclosure](#8-form-sheets-with-progressive-disclosure)
9. [Floating Action Menu](#9-floating-action-menu)
10. [Advanced UI Patterns](#10-advanced-ui-patterns)
11. [Project Notes System (OPS Web)](#11-project-notes-system-ops-web)
12. [Photo Annotations](#12-photo-annotations)
13. [Inventory Management](#13-inventory-management)
14. [Notification System](#14-notification-system)
15. [Crew Location Tracking](#15-crew-location-tracking)
16. [Schedule Tab Redesign](#16-schedule-tab-redesign)
17. [Feature Flags System](#17-feature-flags-system)
18. [Intel Galaxy Visualization (Web)](#18-intel-galaxy-visualization-web)
19. [In-App Email System (Web)](#19-in-app-email-system-web)
20. [Mobile Wizard System](#20-mobile-wizard-system)

---

## 1. Turn-by-Turn Navigation System

### Overview
OPS provides field-ready turn-by-turn navigation with GPS smoothing using a Kalman filter for optimal accuracy in challenging field conditions.

### Architecture Components

#### NavigationEngine (iOS)
**Location:** `OPS/OPS/Map/Core/NavigationEngine.swift` (451 lines)

**Responsibilities:**
- Route calculation using Apple Maps (MKDirections)
- Navigation state management
- Real-time progress tracking
- Automatic rerouting when off-course
- Alternative route suggestions

**Key Properties:**
```swift
@Published var navigationState: NavigationState = .idle
@Published var currentRoute: MKRoute?
@Published var alternativeRoutes: [MKRoute] = []
@Published var currentStepIndex: Int = 0
@Published var distanceToNextStep: CLLocationDistance = 0
@Published var estimatedTimeRemaining: TimeInterval = 0
@Published var estimatedArrivalTime: Date?
```

**Navigation States:**
```swift
enum NavigationState: Equatable {
    case idle           // Not navigating
    case calculating    // Computing route
    case navigating     // Active navigation
    case rerouting      // Recalculating due to deviation
    case arrived        // Destination reached
    case error(Error)   // Navigation failure
}
```

**Core Methods:**

1. **Route Calculation**
```swift
func calculateRoute(from origin: CLLocationCoordinate2D,
                   to destination: CLLocationCoordinate2D) async throws {
    navigationState = .calculating

    let request = MKDirections.Request()
    request.source = MKMapItem(placemark: MKPlacemark(coordinate: origin))
    request.destination = MKMapItem(placemark: MKPlacemark(coordinate: destination))
    request.transportType = .automobile
    request.requestsAlternateRoutes = true

    let directions = MKDirections(request: request)
    let response = try await directions.calculate()
    handleRouteResponse(response)
}
```

2. **Location Updates During Navigation**
```swift
func updateUserLocation(_ location: CLLocation) {
    lastKnownLocation = location

    // Check arrival (within 30 meters)
    if distanceToDestination < 30 {
        navigationState = .arrived
        NotificationCenter.default.post(
            name: Notification.Name("UserArrivedAtDestination"),
            object: nil
        )
        return
    }

    // Check if off-route
    if let distanceFromRoute = distanceFromRoute(location: location, route: route) {
        if distanceFromRoute > rerouteThreshold && !isRerouting {
            Task {
                try? await recalculateRoute(from: location.coordinate, to: destination)
            }
        }
    }

    updateCurrentStep(for: location)
}
```

3. **Off-Route Detection**
```swift
private let rerouteThreshold: CLLocationDistance = 20 // meters
private let minRerouteInterval: TimeInterval = 2 // seconds

private func distanceFromRoute(location: CLLocation, route: MKRoute) -> CLLocationDistance? {
    var minDistance = CLLocationDistance.infinity
    let polyline = route.polyline
    let points = polyline.points()

    // Check distance to each line segment
    for i in 0..<polyline.pointCount - 1 {
        let segmentStart = points[i].coordinate
        let segmentEnd = points[i + 1].coordinate

        let distance = distanceFromPointToLineSegment(
            point: location.coordinate,
            lineStart: segmentStart,
            lineEnd: segmentEnd
        )

        minDistance = min(minDistance, distance)

        // Early exit if on route
        if minDistance < 5 { return minDistance }
    }

    return minDistance
}
```

#### KalmanHeadingFilter (iOS)
**Location:** `OPS/OPS/Map/Core/KalmanHeadingFilter.swift` (125 lines)

**Purpose:** Sensor fusion for smooth heading estimation, combining compass (magnetometer) and gyroscope data to eliminate jitter and improve accuracy.

**Implementation:**
```swift
class KalmanHeadingFilter {
    // State Variables
    private var heading: Double = 0
    private var angularVelocity: Double = 0
    private var covarianceHeading: Double = 1.0
    private var covarianceVelocity: Double = 1.0

    // Filter Parameters
    private let processNoiseHeading: Double = 0.01
    private let processNoiseVelocity: Double = 0.1
    private let compassNoise: Double = 5.0      // degrees
    private let gyroNoise: Double = 0.5         // degrees/second

    func update(compassHeading: Double?, gyroZ: Double?, timestamp: TimeInterval) -> Double {
        let dt = lastUpdateTime > 0 ? timestamp - lastUpdateTime : 0.016
        lastUpdateTime = timestamp

        // PREDICTION STEP (using gyroscope)
        if let gyroZ = gyroZ, dt > 0 {
            let gyroDegreesPerSec = gyroZ * 180.0 / .pi
            heading += angularVelocity * dt
            angularVelocity = gyroDegreesPerSec

            // Uncertainty grows with prediction
            covarianceHeading += dt * dt * covarianceVelocity + processNoiseHeading
            covarianceVelocity += processNoiseVelocity
        }

        // CORRECTION STEP (using compass)
        if let compassHeading = compassHeading {
            var innovation = compassHeading - heading

            // Handle angle wrapping
            if innovation > 180 { innovation -= 360 }
            else if innovation < -180 { innovation += 360 }

            // Kalman gain
            let innovationCovariance = covarianceHeading + compassNoise * compassNoise
            let kalmanGain = covarianceHeading / innovationCovariance

            // Update state
            heading += kalmanGain * innovation
            covarianceHeading *= (1 - kalmanGain)
        }

        // Normalize to [0, 360)
        while heading < 0 { heading += 360 }
        while heading >= 360 { heading -= 360 }

        return heading
    }

    var confidence: Double {
        let maxCovariance = 10.0
        return max(0, min(1, 1.0 - (covarianceHeading / maxCovariance)))
    }
}
```

**Benefits:**
- Eliminates compass jitter from magnetic interference
- Provides smooth heading updates for map rotation
- Combines high-frequency gyro with absolute compass reference
- Adaptive confidence metric for UI feedback

#### MapCoordinator (iOS)
**Location:** `OPS/OPS/Map/Core/MapCoordinator.swift` (885 lines)

**Responsibilities:**
- Map display state (region, camera, orientation)
- Project markers and selection
- Navigation session management
- Auto-centering logic
- User interaction tracking

**Navigation Integration:**
```swift
func startNavigation() async throws {
    guard let project = selectedProject,
          let destination = project.coordinate else {
        throw NavigationError.noDestination
    }

    guard let userLocation = userLocation else {
        throw NavigationError.locationUnavailable
    }

    // Calculate route BEFORE setting navigation state
    try await navigationEngine.calculateRoute(
        from: userLocation.coordinate,
        to: destination
    )

    isNavigating = true

    // Sync with InProgressManager for UI consistency
    if !InProgressManager.shared.isRouting {
        InProgressManager.shared.startRouting(to: destination, from: userLocation.coordinate)
    }

    navigationEngine.startNavigation()
    startRouteRefreshTimer()
    updateMapForNavigation()
}
```

**Orientation Modes:**
```swift
@AppStorage("mapOrientationMode") var mapOrientationMode = "north" // "north" or "course"

func toggleOrientationMode() {
    mapOrientationMode = mapOrientationMode == "north" ? "course" : "north"

    withAnimation(.easeInOut(duration: 0.6)) {
        if mapOrientationMode == "course" {
            // Use GPS course if moving, otherwise device heading
            if locationManager.userCourse >= 0 && userLocation?.speed ?? 0 > 1.25 {
                targetHeading = locationManager.userCourse
            } else {
                targetHeading = locationManager.deviceHeading
            }
            updateMapHeading(animated: true)
        } else {
            // Reset to north
            targetHeading = 0
            updateMapHeading(animated: true)
        }
    }
}
```

**Camera Management:**
```swift
var navigationZoomDistance: CLLocationDistance {
    // Use 75% of normal zoom for navigation
    return zoomDistance * 0.75
}

private func updateMapForNavigation() {
    guard let userLocation = userLocation else { return }

    withAnimation(.easeInOut(duration: 0.8)) {
        if mapOrientationMode == "course" {
            let camera = MapCamera(
                centerCoordinate: userLocation.coordinate,
                distance: navigationZoomDistance,
                heading: currentHeading,
                pitch: 45.0  // Tilt for better navigation view
            )
            mapCameraPosition = .camera(camera)
        } else {
            let region = MKCoordinateRegion(
                center: userLocation.coordinate,
                latitudinalMeters: navigationZoomDistance,
                longitudinalMeters: navigationZoomDistance
            )
            mapCameraPosition = .region(region)
            mapRegion = region
        }
    }
}
```

### Android Conversion Notes

**Required Components:**
1. **NavigationEngine** → Kotlin class using Google Maps Directions API
2. **KalmanFilter** → Port algorithm directly (math is platform-agnostic)
3. **MapCoordinator** → ViewModel managing Google Maps integration
4. **LocationService** → Fused Location Provider + sensor access

**Key Android Libraries:**
- Google Maps SDK for Android
- Fused Location Provider (Play Services)
- Sensor API for gyroscope/magnetometer access

**Implementation Challenges:**
- Android sensors require manual registration/unregistration
- Google Maps camera updates differ from MapKit
- Need to handle Google Play Services availability

---

## 2. Tutorial & Demo Mode

### Overview
Interactive tutorial system with 30 phase definitions (excluding `notStarted` and `completed`) across two flows plus a pipeline extension: Company Creator (~30 seconds), Employee (~20 seconds), and Pipeline phases (admin/office crew only). Features demo data, overlay tooltips, and progressive task guidance.

### Architecture Components

#### TutorialPhase Enum (iOS)
**Location:** `OPS/OPS/Tutorial/State/TutorialPhase.swift` (637 lines)

**Flow Types:**
```swift
enum TutorialFlowType: String, CaseIterable {
    case companyCreator  // Admin/Owner/Office flow
    case employee        // Crew/Operator flow
}
```

**Company Creator Flow (19 phases):**
```swift
case jobBoardIntro           // Highlight FAB
case fabTap                  // User taps FAB
case projectFormClient       // Select client
case projectFormName         // Enter project name
case projectFormAddTask      // Add task button
case taskFormType            // Select task type
case taskFormCrew            // Assign crew member
case taskFormDate            // Set date
case taskFormDone            // Save task
case projectFormComplete     // Save project
case dragToAccepted          // Drag to accepted status
case projectListStatusDemo   // Watch status animate
case projectListSwipe        // Swipe to close
case closedProjectsScroll    // Scroll to closed section
case calendarWeek            // Week view intro
case calendarMonthPrompt     // Tap "Month" button
case calendarMonth           // Month view exploration
case tutorialSummary         // Final summary
case completed               // Tutorial finished
```

**Employee Flow (12 phases):**
```swift
case homeOverview            // Today's jobs overview
case tapProject              // Tap job card
case projectStarted          // Job started
case tapDetails              // Tap Details button
case addNote                 // Add note
case addPhoto                // Take photo
case completeProject         // Mark complete
case jobBoardBrowse          // Browse job board
case calendarWeek            // Week view
case calendarMonthPrompt     // Month view
case calendarMonth           // Month exploration
case tutorialSummary         // Summary
case completed               // Finished
```

**Pipeline Phases (3 phases, admin/office crew only):**
```swift
case pipelineOverview           // "YOUR PIPELINE" — introduces the Pipeline tab
case estimatesOverview          // "BUILD ESTIMATES ON-SITE" — building quotes
case invoicesOverview           // "ESTIMATES TO INVOICES" — converting to invoices
```

Pipeline phases show a Continue button immediately (`showsContinueButtonImmediately = true`) and do not require user action. They provide informational overviews of the Pipeline, Estimates, and Invoices features. Tooltip descriptions:
- `pipelineOverview`: "Here's where you manage leads from first contact to closed deal. Drag cards between stages as deals progress."
- `estimatesOverview`: "Build a quote on-site and send it to your client in minutes. Add line items from your product catalog or create custom ones."
- `invoicesOverview`: "Convert approved estimates to invoices with one tap -- no re-entry. Record payments and track what's outstanding."

**Phase Properties:**
```swift
var tooltipText: String {
    switch self {
    case .jobBoardIntro:
        return "TAP THE + BUTTON"
    case .projectFormClient:
        return "SELECT A CLIENT"
    case .taskFormCrew:
        return "ASSIGN A CREW MEMBER"
    // ... all phases have tooltip text
    }
}

var tooltipDescription: String? {
    switch self {
    case .projectFormClient:
        return "These are sample clients. Pick any one—this is just for practice."
    case .taskFormType:
        return "Pick any one for now. Types help you organize different kinds of work."
    // ... contextual descriptions
    }
}

var autoAdvances: Bool {
    switch self {
    case .projectListStatusDemo,  // Status animation auto-advances
         .closedProjectsScroll:   // Scroll animation auto-advances
        return true
    default:
        return false
    }
}

var autoAdvanceDelay: TimeInterval {
    switch self {
    case .projectListStatusDemo: return 4.0
    case .closedProjectsScroll: return 3.0
    default: return 0
    }
}
```

#### TutorialStateManager (iOS)
**Location:** `OPS/OPS/Tutorial/State/TutorialStateManager.swift` (309 lines)

```swift
@MainActor
class TutorialStateManager: ObservableObject {
    @Published var currentPhase: TutorialPhase = .notStarted
    @Published var isActive: Bool = false
    @Published var showSwipeHint: Bool = false
    @Published var swipeDirection: TutorialSwipeDirection = .right
    @Published var currentCutout: CGRect = .zero
    @Published var tooltipText: String = ""
    @Published var tooltipDescription: String? = nil
    @Published var showTooltip: Bool = false
    @Published var showContinueButton: Bool = false

    let flowType: TutorialFlowType

    func start() {
        isActive = true
        startTime = Date()
        currentPhase = TutorialPhase.firstPhase(for: flowType)
        updateForCurrentPhase()

        if currentPhase.autoAdvances {
            scheduleAutoAdvance()
        } else if currentPhase.showsContinueButtonAfterDelay {
            scheduleContinueButton()
        }
    }

    func advancePhase() {
        autoAdvanceTask?.cancel()
        showContinueButton = false

        guard let nextPhase = currentPhase.next(for: flowType) else {
            complete()
            return
        }

        if nextPhase == .completed {
            complete()
            return
        }

        currentPhase = nextPhase
        updateForCurrentPhase()

        if currentPhase.autoAdvances {
            scheduleAutoAdvance()
        } else if currentPhase.showsContinueButtonAfterDelay {
            scheduleContinueButton()
        }
    }

    func complete() {
        guard let start = startTime else { return }
        completionTime = Date().timeIntervalSince(start)
        currentPhase = .completed
        isActive = false
        TutorialHaptics.success()
    }
}
```

**Haptic Feedback:**
```swift
struct TutorialHaptics {
    static func lightTap() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    static func mediumImpact() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    static func error() {
        UINotificationFeedbackGenerator().notificationOccurred(.error)
    }
}
```

#### TutorialDemoDataManager (iOS)
**Location:** `OPS/OPS/Tutorial/Data/TutorialDemoDataManager.swift`

**Responsibilities:**
- Creates realistic demo data (clients, projects, tasks, team members)
- Populates calendar with sample events
- Provides data isolation from production data
- Cleans up demo data after tutorial completion

**Demo Data Structure:**
```swift
// Demo clients (3 total)
- "Acme Construction" (commercial)
- "Green Valley Residential" (residential)
- "Downtown Office Park" (commercial)

// Demo projects (5 total)
- "Kitchen Remodel" (Acme, In Progress)
- "Bathroom Update" (Green Valley, Accepted)
- "Office Electrical" (Downtown, Booked)
- "Parking Lot Repair" (Acme, Completed)
- "Roof Inspection" (Green Valley, RFQ)

// Demo tasks (12 total)
- Various task types: electrical, plumbing, carpentry, painting
- Assigned to demo crew members
- Scheduled across next 2 weeks

// Demo team members (4 total)
- "John Smith" (Crew, Electrician)
- "Sarah Johnson" (Crew, Plumber)
- "Mike Davis" (Office)
- "Emily Brown" (Admin)
```

#### Tutorial UI Components

**TutorialOverlayView:**
- Dark overlay with cutout for highlighted elements
- Animated tooltips with instruction text
- Shimmer effects for swipe hints
- Continue button for user-paced phases

**TutorialTooltipView:**
- Instruction text (uppercase, bold)
- Optional description (normal weight)
- Adaptive positioning (above/below cutout)
- Animated entry/exit

**TutorialSwipeIndicator:**
- Directional arrows (left/right/up/down)
- Shimmer animation for swipe gesture hints
- Appears on cards during swipe phases

### Android Conversion Notes

**Required Components:**
1. **TutorialPhase** → Sealed class hierarchy
2. **TutorialStateManager** → ViewModel with StateFlow
3. **TutorialDemoDataManager** → Repository pattern for demo data
4. **TutorialOverlay** → Custom composable with Canvas for cutout
5. **Tutorial wrapper screens** → Tutorial-aware versions of main screens

**Key Challenges:**
- Android doesn't have SwiftUI's overlay modifier system
- Need custom drawing for spotlight cutouts using Canvas API
- Demo data needs separate Room database or in-memory storage
- State management via Hilt + ViewModel scoping

---

## 3. Calendar Event Scheduling

### Overview
Task-only scheduling architecture (as of November 2025 migration). All calendar events are linked to tasks, project dates are computed from task ranges.

> **Note (2026-03-02):** The Schedule Tab view layer was redesigned. `CalendarSchedulerSheet` (documented below) remains the tool used for *setting* task dates from within TaskFormSheet/ProjectFormSheet. The Schedule Tab itself — how tasks are *displayed* across days — was rebuilt with `DayCanvasView` and `CalendarDaySelector`. See [Section 16: Schedule Tab](#16-schedule-tab-redesign) for the full view architecture.

### CalendarSchedulerSheet (iOS)
**Location:** `OPS/OPS/Views/Components/Scheduling/CalendarSchedulerSheet.swift` (968 lines)

**Features:**
- Visual calendar grid with event dots
- Conflict detection and warnings
- Team member filtering
- Project task filtering
- Date range selection with visual feedback

**Core Implementation:**
```swift
struct CalendarSchedulerSheet: View {
    @Binding var isPresented: Bool
    let itemType: ScheduleItemType
    let currentStartDate: Date?
    let currentEndDate: Date?
    let onScheduleUpdate: (Date, Date) -> Void
    let onClearDates: (() -> Void)?

    @State private var selectedStartDate: Date
    @State private var selectedEndDate: Date
    @State private var viewMode: ViewMode = .selecting
    @State private var conflictingEvents: [ProjectTask] = []
    @State private var showOnlyTeamEvents = true
    @State private var showOnlyProjectTasks = true

    enum ViewMode {
        case selecting   // Picking dates
        case reviewing   // Reviewing conflicts
    }

    enum ScheduleItemType {
        case project(Project)
        case task(ProjectTask)
        case draftTask(taskTypeId: String, teamMemberIds: [String], projectId: String?)
    }
}
```

**Date Selection Flow:**
```swift
private func handleDateSelection(_ date: Date) {
    let generator = UIImpactFeedbackGenerator(style: .light)
    generator.impactOccurred()

    if selectedStartDate == selectedEndDate {
        // Second date selected - auto-sort
        let firstDate = selectedStartDate
        let secondDate = date

        if secondDate < firstDate {
            selectedStartDate = secondDate
            selectedEndDate = firstDate
        } else {
            selectedStartDate = firstDate
            selectedEndDate = secondDate
        }

        checkForConflicts()
        viewMode = .reviewing
    } else {
        // Reset to single date
        selectedStartDate = date
        selectedEndDate = date
        conflictingEvents = []
        viewMode = .selecting
    }
}
```

**Conflict Detection:**
```swift
private func checkForConflicts() {
    let tasksToCheck = (showOnlyTeamEvents || showOnlyProjectTasks)
        ? filteredScheduledTasks
        : allScheduledTasks

    conflictingEvents = tasksToCheck.filter { scheduledTask in
        // Don't count current item as conflict
        let isSameItem: Bool
        switch itemType {
        case .task(let task):
            isSameItem = scheduledTask.id == task.id
        case .draftTask:
            isSameItem = false
        case .project:
            isSameItem = false
        }

        // Check date overlap
        if !isSameItem, let taskStart = scheduledTask.startDate, let taskEnd = scheduledTask.endDate {
            let taskRange = taskStart...taskEnd
            let selectedRange = selectedStartDate...selectedEndDate
            return taskRange.overlaps(selectedRange)
        }
        return false
    }.sorted { ($0.startDate ?? Date.distantPast) < ($1.startDate ?? Date.distantPast) }
}
```

**Team Filtering:**
```swift
private func filterScheduledTasks() {
    if showOnlyProjectTasks {
        if let projectId = itemType.projectId {
            filteredScheduledTasks = allScheduledTasks.filter { task in
                task.projectId == projectId && task.id != currentTaskId
            }
            return
        }
    }

    guard showOnlyTeamEvents else {
        filteredScheduledTasks = allScheduledTasks
        return
    }

    let currentTeamMembers: Set<String>
    switch itemType {
    case .project(let project):
        currentTeamMembers = Set(project.getTeamMemberIds())
    case .task(let task):
        currentTeamMembers = Set(task.getTeamMemberIds())
    case .draftTask(_, let teamMemberIds, _):
        currentTeamMembers = Set(teamMemberIds)
    }

    filteredScheduledTasks = allScheduledTasks.filter { task in
        let taskTeamMembers = Set(task.getTeamMemberIds())
        return !currentTeamMembers.isDisjoint(with: taskTeamMembers)
    }
}
```

**Day Cell Component:**
```swift
private struct SchedulerDayCell: View {
    let date: Date
    let isInCurrentMonth: Bool
    let events: [ProjectTask]
    let isSelected: Bool
    let isInRange: Bool
    let isStartDate: Bool
    let isEndDate: Bool
    let hasConflicts: Bool
    let hasTeamConflicts: Bool
    let isToday: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            ZStack {
                // Today background
                if isToday {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(OPSStyle.Colors.primaryAccent)
                }

                // Selection border (animated)
                if isStartDate && isEndDate {
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(OPSStyle.Colors.primaryText, lineWidth: 2)
                } else if isStartDate {
                    UnevenRoundedRectangle(
                        topLeadingRadius: 8,
                        bottomLeadingRadius: 8
                    )
                    .strokeBorder(OPSStyle.Colors.primaryText, lineWidth: 2)
                } else if isEndDate {
                    UnevenRoundedRectangle(
                        bottomTrailingRadius: 8,
                        topTrailingRadius: 8
                    )
                    .strokeBorder(OPSStyle.Colors.primaryText, lineWidth: 2)
                }

                // Conflict indicator
                if hasConflicts {
                    Circle()
                        .fill(OPSStyle.Colors.warningStatus.opacity(0.3))
                        .padding(4)
                }

                VStack(spacing: 2) {
                    Text(dayNumber)
                        .font(OPSStyle.Typography.bodyBold)
                        .foregroundColor(textColor)

                    // Event dots (max 3)
                    if !events.isEmpty {
                        HStack(spacing: 1) {
                            ForEach(Array(events.prefix(3).enumerated()), id: \.offset) { _, event in
                                Circle()
                                    .fill(event.swiftUIColor)
                                    .frame(width: 4, height: 4)
                            }
                        }
                    }
                }
            }
            .frame(height: 44)
        }
        .disabled(!isInCurrentMonth)
    }
}
```

### Android Conversion Notes

**Required Components:**
1. **CalendarSchedulerSheet** → Full-screen composable with LazyVerticalGrid
2. **Day cell** → Custom composable with Canvas for selection borders
3. **Conflict detection** → Port business logic to ViewModel
4. **Date utilities** → Use java.time.LocalDate

**Key Challenges:**
- Android Calendar composables are less mature than iOS
- Custom drawing for selection borders using Canvas
- Date range handling with LocalDate/LocalDateTime
- Conflict highlighting animations

---

## 4. Image Capture & S3 Sync

### Overview
Two-tier image storage: local file system for offline, S3 for cloud sync. Automatic queue-based upload when connectivity available.

### ImageSyncManager (iOS)
**Location:** `OPS/OPS/Network/ImageSyncManager.swift` (570 lines)

**Architecture:**
```swift
@MainActor
class ImageSyncManager: ObservableObject {
    private let modelContext: ModelContext?
    private let apiService: APIService
    private let connectivityMonitor: ConnectivityMonitor
    private let s3Service = S3UploadService.shared
    private let presignedURLService = PresignedURLUploadService.shared

    private var pendingUploads: [PendingImageUpload] = []
    @Published private var isSyncing = false
    @Published var syncProgress: Double = 0
}

struct PendingImageUpload: Codable {
    let localURL: String      // "local://project_images/local_project_123_timestamp.jpg"
    let projectId: String
    let companyId: String
    let timestamp: Date
}
```

**Save Flow:**
```swift
func saveImages(_ images: [UIImage], for project: Project) async -> [String] {
    let companyId = project.companyId
    var savedURLs: [String] = []

    if connectivityMonitor.isConnected {
        do {
            // Upload to S3
            let s3Results = try await s3Service.uploadProjectImages(
                images,
                for: project,
                companyId: companyId
            )

            let imageURLs = s3Results.map { $0.url }

            // Register with Bubble API
            let requestBody: [String: Any] = [
                "project_id": project.id,
                "images": imageURLs
            ]

            let uploadURL = URL(string: "\(AppConfiguration.bubbleBaseURL)/api/1.1/wf/upload_project_images")!
            var request = URLRequest(url: uploadURL)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("Bearer \(AppConfiguration.bubbleAPIToken)", forHTTPHeaderField: "Authorization")
            request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

            let (_, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                // Rollback S3 uploads
                for result in s3Results {
                    try? await s3Service.deleteImageFromS3(
                        url: result.url,
                        companyId: companyId,
                        projectId: project.id
                    )
                }
                throw S3Error.bubbleAPIFailed
            }

            savedURLs = imageURLs

            // Update project
            var currentImages = project.getProjectImages()
            currentImages.append(contentsOf: savedURLs)
            project.setProjectImageURLs(currentImages)
            project.needsSync = true

            try? modelContext?.save()
        } catch {
            // Fallback to local storage
            for (index, image) in images.enumerated() {
                if let localURL = await saveImageLocally(image, for: project, index: index) {
                    savedURLs.append(localURL)
                }
            }
        }
    } else {
        // Offline - save locally
        for (index, image) in images.enumerated() {
            if let localURL = await saveImageLocally(image, for: project, index: index) {
                savedURLs.append(localURL)
            }
        }
    }

    return savedURLs
}
```

**Local Storage:**
```swift
private func saveImageLocally(_ image: UIImage, for project: Project, index: Int) async -> String? {
    // Resize if needed (max 2048px)
    let resizedImage = resizeImageIfNeeded(image)

    // Adaptive compression (0.5-0.8 based on resolution)
    let compressionQuality = getAdaptiveCompressionQuality(for: resizedImage)

    guard let imageData = resizedImage.jpegData(compressionQuality: compressionQuality) else {
        return nil
    }

    let timestamp = Date().timeIntervalSince1970
    let filename = "local_project_\(project.id)_\(timestamp)_\(index).jpg"
    let localURL = "local://project_images/\(filename)"

    let success = ImageFileManager.shared.saveImage(data: imageData, localID: localURL)
    if success {
        // Queue for sync
        let pendingUpload = PendingImageUpload(
            localURL: localURL,
            projectId: project.id,
            companyId: project.companyId,
            timestamp: Date()
        )
        pendingUploads.append(pendingUpload)
        savePendingUploads()

        project.addUnsyncedImage(localURL)
        return localURL
    }

    return nil
}

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

private func getAdaptiveCompressionQuality(for image: UIImage) -> CGFloat {
    let pixelCount = image.size.width * image.size.height

    if pixelCount > 4_000_000 { return 0.5 }      // > 4MP
    else if pixelCount > 2_000_000 { return 0.6 } // > 2MP
    else if pixelCount > 1_000_000 { return 0.7 } // > 1MP
    else { return 0.8 }
}
```

**Sync When Online:**
```swift
func syncPendingImages() async {
    guard !isSyncing, connectivityMonitor.isConnected else { return }
    if pendingUploads.isEmpty { return }

    isSyncing = true

    // Group by project
    var uploadsByProject: [String: [PendingImageUpload]] = [:]
    for upload in pendingUploads {
        uploadsByProject[upload.projectId, default: []].append(upload)
    }

    // Process each project
    for (projectId, uploads) in uploadsByProject {
        await syncImagesForProject(projectId: projectId, uploads: uploads)
    }

    isSyncing = false
}

private func syncImagesForProject(projectId: String, uploads: [PendingImageUpload]) async {
    guard let project = getProject(by: projectId) else { return }

    let images = uploads.compactMap { upload in
        if let imageData = ImageFileManager.shared.getImageData(localID: upload.localURL) {
            return UIImage(data: imageData)
        }
        return nil
    }

    guard !images.isEmpty else { return }

    do {
        // Upload to S3
        let s3Results = try await s3Service.uploadProjectImages(
            images,
            for: project,
            companyId: project.companyId
        )

        let imageURLs = s3Results.map { $0.url }

        // Register with Bubble
        let requestBody: [String: Any] = [
            "project_id": projectId,
            "images": imageURLs
        ]

        let uploadURL = URL(string: "\(AppConfiguration.bubbleBaseURL)/api/1.1/wf/upload_project_images")!
        var request = URLRequest(url: uploadURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(AppConfiguration.bubbleAPIToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

        let (_, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            // Rollback
            for result in s3Results {
                try? await s3Service.deleteImageFromS3(
                    url: result.url,
                    companyId: project.companyId,
                    projectId: projectId
                )
            }
            throw S3Error.bubbleAPIFailed
        }

        // Success - replace local URLs with S3 URLs
        var currentImages = project.getProjectImages()
        for (index, upload) in uploads.enumerated() {
            if let localIndex = currentImages.firstIndex(of: upload.localURL),
               index < s3Results.count {
                currentImages[localIndex] = s3Results[index].url
                project.markImageAsSynced(upload.localURL)
            }
        }

        project.setProjectImageURLs(currentImages)
        project.needsSync = true

        // Remove from pending
        pendingUploads.removeAll { upload in
            uploads.contains { $0.localURL == upload.localURL }
        }
        savePendingUploads()

        try? modelContext?.save()
    } catch {
        print("❌ Image sync failed: \(error)")
    }
}
```

### Android Conversion Notes

**Required Components:**
1. **ImageSyncManager** → Kotlin class with Hilt injection
2. **PendingImageUpload** → Room entity for queue persistence
3. **ImageFileManager** → File I/O wrapper for local storage
4. **S3UploadService** → AWS SDK for Android integration
5. **WorkManager** → Background sync scheduling

**Key Libraries:**
- AWS SDK for Android (S3 uploads)
- Coil or Glide (image loading)
- WorkManager (background sync)
- Kotlin Coroutines + Flow

---

## 5. PIN Management

### Overview
Simple 4-digit PIN for app entry barrier. Stored in Keychain (iOS) / EncryptedSharedPreferences (Android).

### SimplePINManager (iOS)
**Location:** `OPS/OPS/Network/Auth/SimplePINManager.swift` (56 lines)

**Implementation:**
```swift
class SimplePINManager: ObservableObject {
    @Published var requiresPIN = false
    @Published var isAuthenticated = false

    @AppStorage("appPIN") private var storedPIN: String = ""
    @AppStorage("hasPINEnabled") var hasPINEnabled = false

    func checkPINRequirement() {
        requiresPIN = hasPINEnabled && !storedPIN.isEmpty
        isAuthenticated = !requiresPIN
    }

    func setPIN(_ pin: String) {
        storedPIN = pin
        hasPINEnabled = !pin.isEmpty
        checkPINRequirement()
    }

    func validatePIN(_ pin: String) -> Bool {
        let isValid = pin == storedPIN
        if isValid {
            // Delay for success animation
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                self?.isAuthenticated = true
                self?.objectWillChange.send()
            }
        }
        return isValid
    }

    func resetAuthentication() {
        if hasPINEnabled {
            isAuthenticated = false
        }
    }

    func removePIN() {
        storedPIN = ""
        hasPINEnabled = false
        isAuthenticated = true
    }
}
```

**Critical Android Difference:**
- **iOS:** 4-digit PIN (as shown above)
- **Android (current):** 6-digit PIN in SecurePreferences
- **ACTION REQUIRED:** Android must be changed to 4-digit for parity

**Android Implementation (needs update):**
```kotlin
// CURRENT (WRONG - 6 digits)
class PinManager @Inject constructor(
    private val securePreferences: SecurePreferences
) {
    fun validatePin(pin: String): Boolean {
        val stored = securePreferences.getPin()
        return pin.length == 6 && pin == stored  // WRONG
    }
}

// REQUIRED (CORRECT - 4 digits)
class PinManager @Inject constructor(
    private val securePreferences: SecurePreferences
) {
    fun validatePin(pin: String): Boolean {
        val stored = securePreferences.getPin()
        return pin.length == 4 && pin == stored  // CORRECT
    }
}
```

---

## 6. Job Board Features

### Overview
Central hub for projects, tasks, clients, and dashboard. Section-based navigation with filtering, sorting, and bulk operations.

### JobBoardView (iOS)
**Location:** `OPS/OPS/Views/JobBoard/JobBoardView.swift` (1,211 lines)

**Sections:**
```swift
enum JobBoardSection: String, CaseIterable {
    case dashboard = "Dashboard"
    case clients = "Clients"
    case projects = "Projects"
    case tasks = "Tasks"
}
```

**Section Picker:**
```swift
struct JobBoardSectionSelector: View {
    @Binding var selectedSection: JobBoardSection
    @Environment(\.tutorialMode) private var tutorialMode

    var body: some View {
        HStack(spacing: 8) {
            ForEach(JobBoardSection.allCases, id: \.self) { section in
                Button(action: {
                    guard !tutorialMode else { return }
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        selectedSection = section
                    }
                }) {
                    Text(section.rawValue.uppercased())
                        .font(OPSStyle.Typography.cardBody)
                        .foregroundColor(
                            selectedSection == section
                                ? OPSStyle.Colors.cardBackgroundDark
                                : OPSStyle.Colors.secondaryText
                        )
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(
                                    selectedSection == section
                                        ? OPSStyle.Colors.primaryText
                                        : .clear
                                )
                        )
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(OPSStyle.Colors.cardBackgroundDark)
        )
    }
}
```

**Task Filtering:**
```swift
private var filteredTasks: [ProjectTask] {
    // Cache lookups to avoid O(n*m)
    let allProjects = dataController.getAllProjects()
    let projectsById = Dictionary(uniqueKeysWithValues: allProjects.map { ($0.id, $0) })
    let taskTypesById = Dictionary(uniqueKeysWithValues: allTaskTypes.map { ($0.id, $0) })

    var filtered = allTasks

    // Filter by status
    if !selectedStatuses.isEmpty {
        filtered = filtered.filter { selectedStatuses.contains($0.status) }
    }

    // Filter by task type
    if !selectedTaskTypeIds.isEmpty {
        filtered = filtered.filter { selectedTaskTypeIds.contains($0.taskTypeId) }
    }

    // Filter by team members
    if !selectedTeamMemberIds.isEmpty {
        filtered = filtered.filter { task in
            let taskTeamMemberIds = Set(task.getTeamMemberIds())
            return !taskTeamMemberIds.intersection(selectedTeamMemberIds).isEmpty
        }
    }

    // Search text
    if !searchText.isEmpty {
        filtered = filtered.filter { task in
            let taskTypeName = taskTypesById[task.taskTypeId]?.display ?? ""
            let projectName = projectsById[task.projectId]?.title ?? ""

            return taskTypeName.localizedCaseInsensitiveContains(searchText) ||
                   projectName.localizedCaseInsensitiveContains(searchText) ||
                   (task.taskNotes?.localizedCaseInsensitiveContains(searchText) ?? false)
        }
    }

    // Sort
    switch sortOption {
    case .scheduledDateDescending:
        return filtered.sorted {
            ($0.scheduledDate ?? Date.distantPast) > ($1.scheduledDate ?? Date.distantPast)
        }
    case .scheduledDateAscending:
        return filtered.sorted {
            ($0.scheduledDate ?? Date.distantPast) < ($1.scheduledDate ?? Date.distantPast)
        }
    case .statusAscending:
        return filtered.sorted { $0.status.sortOrder < $1.status.sortOrder }
    case .statusDescending:
        return filtered.sorted { $0.status.sortOrder > $1.status.sortOrder }
    }
}
```

**Crew Restrictions:**
```swift
private var isCrew: Bool {
    return dataController.currentUser?.role == .crew
}

// In body:
if !isCrew {
    JobBoardSectionSelector(selectedSection: $selectedSection)
        .padding(.top, 70)
} else {
    // Crew only sees dashboard
    Spacer().frame(height: 70)
}
```

### UniversalJobBoardCard (iOS)
**Location:** `OPS/OPS/Views/JobBoard/UniversalJobBoardCard.swift` (1,826 lines)

**Card Types:**
```swift
enum JobBoardCardType {
    case project(Project)
    case client(Client)
    case task(ProjectTask)
}
```

**Badge Logic:**
```swift
// Unscheduled badge
private func shouldShowUnscheduledBadge(for project: Project) -> Bool {
    // No tasks = unscheduled
    if project.tasks.isEmpty {
        return true
    }

    // Filter out completed/cancelled
    let relevantTasks = project.tasks.filter { task in
        task.status != .completed && task.status != .cancelled
    }

    // All tasks completed/cancelled = hide badge
    if relevantTasks.isEmpty {
        return false
    }

    // Check if any unscheduled
    let unscheduledTasks = relevantTasks.filter { task in
        task.calendarEvent?.startDate == nil
    }
    return !unscheduledTasks.isEmpty
}
```

**Metadata Row:**
```swift
private var metadataItems: [(icon: String, text: String)] {
    switch cardType {
    case .project(let project):
        var items: [(icon: String, text: String)] = []

        // Address (truncates at 35% width)
        if let address = project.address, !address.isEmpty {
            items.append((OPSStyle.Icons.location, formatAddressStreetOnly(address)))
        } else {
            items.append((OPSStyle.Icons.location, "NO ADDRESS"))
        }

        // Calendar
        if let startDate = project.startDate {
            items.append((OPSStyle.Icons.calendar, DateHelper.simpleDateString(from: startDate)))
        } else {
            items.append((OPSStyle.Icons.calendar, "-"))
        }

        // Team members
        let teamCount = project.teamMembers.count
        items.append((OPSStyle.Icons.personTwo, "\(teamCount)"))

        return items

    case .task(let task):
        var items: [(icon: String, text: String)] = []

        // Address from parent project
        if let project = dataController.getAllProjects().first(where: { $0.id == task.projectId }) {
            if let address = project.address, !address.isEmpty {
                items.append((OPSStyle.Icons.location, formatAddressStreetOnly(address)))
            } else {
                items.append((OPSStyle.Icons.location, "NO ADDRESS"))
            }
        }

        // Calendar
        if let startDate = task.calendarEvent?.startDate {
            items.append((OPSStyle.Icons.calendar, DateHelper.simpleDateString(from: startDate)))
        } else {
            items.append((OPSStyle.Icons.calendar, "-"))
        }

        // Team members
        let teamMemberCount = task.getTeamMemberIds().count
        items.append((OPSStyle.Icons.personTwo, "\(teamMemberCount)"))

        return items
    }
}
```

---

## 7. Swipe-to-Change-Status Gestures

### Overview
Industry-first swipe gesture for status changes. Right swipe = forward status, left swipe = backward status. 40% threshold with haptic feedback and visual confirmation.

### Implementation (UniversalJobBoardCard)

**Swipe Detection:**
```swift
@State private var swipeOffset: CGFloat = 0
@State private var isChangingStatus = false
@State private var hasTriggeredHaptic = false
@State private var confirmingStatus: Any? = nil
@State private var confirmingDirection: SwipeDirection? = nil

enum SwipeDirection {
    case left
    case right
}

private func canSwipe(direction: SwipeDirection) -> Bool {
    switch cardType {
    case .project(let project):
        return direction == .right
            ? project.status.canSwipeForward
            : project.status.canSwipeBackward
    case .task(let task):
        return direction == .right
            ? task.status.canSwipeForward
            : task.status.canSwipeBackward
    case .client:
        return false
    }
}

private func getTargetStatus(direction: SwipeDirection) -> Any? {
    switch cardType {
    case .project(let project):
        return direction == .right
            ? project.status.nextStatus()
            : project.status.previousStatus()
    case .task(let task):
        return direction == .right
            ? task.status.nextStatus()
            : task.status.previousStatus()
    case .client:
        return nil
    }
}
```

**Gesture Handler:**
```swift
.simultaneousGesture(
    DragGesture(minimumDistance: 20)
        .onChanged { value in
            handleSwipeChanged(value: value, cardWidth: geometry.size.width)
        }
        .onEnded { value in
            handleSwipeEnded(value: value, cardWidth: geometry.size.width)
        }
)

private func handleSwipeChanged(value: DragGesture.Value, cardWidth: CGFloat) {
    guard !isChangingStatus else { return }

    let horizontalDrag = abs(value.translation.width)
    let verticalDrag = abs(value.translation.height)

    // Only activate if horizontal is dominant
    guard horizontalDrag > verticalDrag else { return }

    let direction: SwipeDirection = value.translation.width > 0 ? .right : .left

    // Tutorial mode: block left swipe
    if tutorialMode && tutorialPhase == .projectListSwipe && direction == .left {
        if !showingWrongSwipeHint {
            showingWrongSwipeHint = true
            TutorialHaptics.error()
            NotificationCenter.default.post(name: Notification.Name("TutorialWrongAction"), object: nil)

            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                withAnimation {
                    self.showingWrongSwipeHint = false
                }
            }
        }
        return
    }

    guard canSwipe(direction: direction) else { return }

    withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
        swipeOffset = value.translation.width
    }

    // Haptic at 40% threshold
    let swipePercentage = abs(swipeOffset) / cardWidth
    if swipePercentage >= 0.4 && !hasTriggeredHaptic {
        let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
        impactFeedback.impactOccurred()
        hasTriggeredHaptic = true
    }
}

private func handleSwipeEnded(value: DragGesture.Value, cardWidth: CGFloat) {
    guard !isChangingStatus else { return }

    let swipePercentage = abs(value.translation.width) / cardWidth
    let direction: SwipeDirection = value.translation.width > 0 ? .right : .left

    if swipePercentage >= 0.4, canSwipe(direction: direction), let targetStatus = getTargetStatus(direction: direction) {
        confirmingStatus = targetStatus
        confirmingDirection = direction
        isChangingStatus = true

        // Snap back to center
        withAnimation(.spring(response: 0.2, dampingFraction: 0.85)) {
            swipeOffset = 0
        }

        // Brief flash (0.15s), then perform change
        let flashDelay: Double = tutorialMode ? 0.05 : 0.15
        DispatchQueue.main.asyncAfter(deadline: .now() + flashDelay) {
            performStatusChange(to: targetStatus)

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                withAnimation(.spring(response: 0.2, dampingFraction: 0.85)) {
                    isChangingStatus = false
                    confirmingStatus = nil
                    confirmingDirection = nil
                }
                hasTriggeredHaptic = false
            }
        }
    } else {
        // Snap back without change
        withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
            swipeOffset = 0
        }
        hasTriggeredHaptic = false
    }
}
```

**Visual Feedback:**
```swift
struct RevealedStatusCard: View {
    let status: Any
    let direction: SwipeDirection

    private var statusText: String {
        if let projectStatus = status as? Status {
            return projectStatus.displayName.uppercased()
        } else if let taskStatus = status as? TaskStatus {
            return taskStatus.displayName.uppercased()
        }
        return ""
    }

    private var statusColor: Color {
        if let projectStatus = status as? Status {
            return projectStatus.color
        } else if let taskStatus = status as? TaskStatus {
            return taskStatus.color
        }
        return OPSStyle.Colors.primaryAccent
    }

    var body: some View {
        HStack {
            if direction == .left { Spacer() }

            Text(statusText)
                .font(OPSStyle.Typography.bodyBold)
                .foregroundColor(statusColor)
                .frame(maxHeight: .infinity)
                .padding(.horizontal, 20)

            if direction == .right { Spacer() }
        }
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(statusColor.opacity(0.1))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(statusColor, lineWidth: 1)
        )
    }
}

// In card body:
ZStack(alignment: .leading) {
    // Revealed status (behind card)
    if swipeOffset > 0, let targetStatus = getTargetStatus(direction: .right) {
        RevealedStatusCard(status: targetStatus, direction: .right)
            .opacity(min(abs(swipeOffset) / (geometry.size.width * 0.4), 1.0))
    } else if swipeOffset < 0, let targetStatus = getTargetStatus(direction: .left) {
        RevealedStatusCard(status: targetStatus, direction: .left)
            .opacity(min(abs(swipeOffset) / (geometry.size.width * 0.4), 1.0))
    }

    // Card content (offset by swipe)
    cardContent
        .offset(x: swipeOffset)
        .opacity(isChangingStatus ? 0 : 1)

    // Confirmation flash
    if isChangingStatus, let confirmingStatus = confirmingStatus, let direction = confirmingDirection {
        RevealedStatusCard(status: confirmingStatus, direction: direction)
            .opacity(isChangingStatus ? 1 : 0)
    }
}
```

---

## 8. Form Sheets with Progressive Disclosure

### Overview
Multi-section forms with collapsible sections that reorder when opened via pill buttons. Smart scrolling and dynamic layout.

### Key Features (November 2025 Updates)

**Dynamic Section Reordering:**
- Sections auto-move to top when opened via pill buttons
- Auto-scroll with delay to position expanded sections at top
- Maintains user focus without jarring transitions

**Unified Input Card Layout:**
- All form inputs grouped into single card sections
- Consistent across ProjectFormSheet, TaskFormSheet, ClientFormSheet
- Border consistency: `Color.white.opacity(0.1)` for all cards

**Button Placement:**
- Save/Cancel buttons at bottom
- Secondary actions (Copy from Project, Import from Contacts) also at bottom
- Clear visual hierarchy

### Example: ProjectFormSheet
```swift
struct ProjectFormSheet: View {
    @State private var expandedSection: ProjectFormSection? = nil
    @State private var scrollTarget: Int? = nil

    enum ProjectFormSection: String, CaseIterable {
        case client = "Client"
        case details = "Details"
        case location = "Location"
        case tasks = "Tasks"
        case team = "Team"
        case schedule = "Schedule"
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 16) {
                    // Pill buttons
                    sectionPillButtons

                    // Sections (reordered based on expandedSection)
                    ForEach(orderedSections, id: \.self) { section in
                        CollapsibleSection(
                            title: section.rawValue,
                            isExpanded: expandedSection == section,
                            onToggle: {
                                withAnimation {
                                    expandedSection = expandedSection == section ? nil : section
                                }
                            }
                        ) {
                            sectionContent(for: section)
                        }
                        .id(section.rawValue)
                    }

                    // Save/Cancel buttons
                    actionButtons
                }
                .padding()
            }
            .onChange(of: expandedSection) { _, newSection in
                if let section = newSection {
                    // Delay scroll to allow reordering animation
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        withAnimation {
                            proxy.scrollTo(section.rawValue, anchor: .top)
                        }
                    }
                }
            }
        }
    }

    private var orderedSections: [ProjectFormSection] {
        guard let expanded = expandedSection else {
            return ProjectFormSection.allCases
        }

        // Move expanded section to top
        var sections = ProjectFormSection.allCases.filter { $0 != expanded }
        sections.insert(expanded, at: 0)
        return sections
    }

    private var sectionPillButtons: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(ProjectFormSection.allCases, id: \.self) { section in
                    Button {
                        withAnimation {
                            expandedSection = section
                        }
                    } label: {
                        Text(section.rawValue.uppercased())
                            .font(OPSStyle.Typography.smallCaption)
                            .foregroundColor(
                                expandedSection == section
                                    ? OPSStyle.Colors.primaryText
                                    : OPSStyle.Colors.secondaryText
                            )
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                Capsule()
                                    .fill(
                                        expandedSection == section
                                            ? OPSStyle.Colors.primaryAccent
                                            : OPSStyle.Colors.cardBackgroundDark
                                    )
                            )
                    }
                }
            }
        }
    }
}
```

**CollapsibleSection Component:**
```swift
struct CollapsibleSection<Content: View>: View {
    let title: String
    let isExpanded: Bool
    let onToggle: () -> Void
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 0) {
            // Header
            Button(action: onToggle) {
                HStack {
                    Text(title.uppercased())
                        .font(OPSStyle.Typography.captionBold)
                        .foregroundColor(OPSStyle.Colors.primaryText)

                    Spacer()

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                        .font(.system(size: 14, weight: .semibold))
                }
                .padding(16)
                .background(OPSStyle.Colors.cardBackgroundDark)
                .cornerRadius(8, corners: isExpanded ? [.topLeft, .topRight] : .allCorners)
            }

            // Content
            if isExpanded {
                VStack(spacing: 12) {
                    content
                }
                .padding(16)
                .background(OPSStyle.Colors.cardBackgroundDark.opacity(0.6))
                .cornerRadius(8, corners: [.bottomLeft, .bottomRight])
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
        )
    }
}
```

---

## 9. Floating Action Menu

### Overview
Expandable FAB with role-based and context-based item visibility. Admin and office see full create menus. Crew see only schedule-specific items when on the Schedule tab.

**Updated:** 2026-03-02 — Added `isScheduleTab` parameter; crew now see the FAB on the Schedule tab.

### FloatingActionMenu (iOS)
**Location:** `OPS/OPS/Views/Components/FloatingActionMenu.swift`

**Key Behavior Changes (2026-03-02):**
- Added `isScheduleTab: Bool = false` parameter
- `canShowFAB` now returns `true` for **all roles** when `isScheduleTab == true`
- When `isScheduleTab == true`, the menu shows only: "Request Time Off" and "Personal Event"
- `ScheduleView` passes `isScheduleTab: true` to `FloatingActionMenu`

**Permission System Update (March 2026):**
- FAB visibility and menu items are being migrated from `role == .admin || role == .office` checks to the granular RBAC permission system
- Each menu item should be individually gated by permission (e.g., "Create Project" → `projects.create`, "New Estimate" → `estimates.create`)
- The `canShowFAB` logic should check if the user has ANY create permission for the current tab context
- See `03_DATA_ARCHITECTURE.md` > Permissions System Tables for the complete permission schema

**Current Implementation (being migrated to permissions):**
```swift
struct FloatingActionMenu: View {
    var isScheduleTab: Bool = false                       // Added 2026-03-02
    @EnvironmentObject private var dataController: DataController
    @Environment(\.tutorialMode) private var tutorialMode
    @State private var showCreateMenu = false

    // LEGACY: Being replaced by permissionStore.can() checks
    private var canShowFAB: Bool {
        guard let user = dataController.currentUser else { return false }
        if isScheduleTab { return true }                 // All roles can use schedule FAB
        return user.role == .admin || user.role == .office
    }

    var body: some View {
        ZStack {
            // Dimmed overlay
            if showCreateMenu {
                LinearGradient(
                    colors: [Color(OPSStyle.Colors.background).opacity(0.85), .clear],
                    startPoint: .trailing,
                    endPoint: .leading
                )
                .ignoresSafeArea()
                .onTapGesture {
                    guard !tutorialMode else { return }
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        showCreateMenu = false
                    }
                }
            }

            if canShowFAB {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()

                        VStack(alignment: .trailing, spacing: 24) {
                            // Menu items (staggered animation)
                            if showCreateMenu {
                                FloatingActionItem(
                                    icon: OPSStyle.Icons.taskType,
                                    label: "New Task Type",
                                    action: { showingCreateTaskType = true }
                                )
                                .transition(.move(edge: .trailing).combined(with: .opacity))
                                .animation(.easeInOut(duration: 0.3).delay(0.8), value: showCreateMenu)

                                FloatingActionItem(
                                    icon: OPSStyle.Icons.task,
                                    label: "Create Task",
                                    action: { showingCreateTask = true }
                                )
                                .transition(.move(edge: .trailing).combined(with: .opacity))
                                .animation(.easeInOut(duration: 0.3).delay(0.6), value: showCreateMenu)

                                FloatingActionItem(
                                    icon: OPSStyle.Icons.project,
                                    label: "Create Project",
                                    action: { showingCreateProject = true }
                                )
                                .transition(.move(edge: .trailing).combined(with: .opacity))
                                .animation(.easeInOut(duration: 0.3).delay(0.4), value: showCreateMenu)

                                FloatingActionItem(
                                    icon: OPSStyle.Icons.client,
                                    label: "Create Client",
                                    action: { showingCreateClient = true }
                                )
                                .transition(.move(edge: .trailing).combined(with: .opacity))
                                .animation(.easeInOut(duration: 0.3).delay(0.2), value: showCreateMenu)
                            }

                            // Main FAB
                            Button {
                                withAnimation(.easeInOut(duration: 0.3)) {
                                    showCreateMenu.toggle()
                                }
                            } label: {
                                Image(systemName: "plus")
                                    .font(.system(size: 30))
                                    .foregroundColor(OPSStyle.Colors.buttonText)
                                    .rotationEffect(.degrees(showCreateMenu ? 225 : 0))
                                    .frame(width: 64, height: 64)
                                    .background {
                                        Circle().fill(.ultraThinMaterial.opacity(0.8))
                                    }
                                    .clipShape(Circle())
                                    .shadow(color: OPSStyle.Colors.background.opacity(0.4), radius: 8)
                                    .overlay {
                                        Circle()
                                            .stroke(OPSStyle.Colors.buttonText, lineWidth: 2)
                                    }
                            }
                        }
                        .padding(.trailing, 36)
                        .padding(.bottom, 140) // Above tab bar
                    }
                }
            }
        }
    }
}

struct FloatingActionItem: View {
    let icon: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Text(label.uppercased())
                    .font(OPSStyle.Typography.bodyBold)
                    .foregroundColor(OPSStyle.Colors.primaryText)

                Image(systemName: icon)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                    .frame(width: 48, height: 48)
                    .background(.clear)
                    .clipShape(Circle())
                    .overlay(
                        Circle()
                            .stroke(OPSStyle.Colors.secondaryText, lineWidth: 1)
                    )
            }
        }
    }
}
```

### Android Status
**CRITICAL GAP:** FloatingActionMenu is completely missing in Android implementation.

**Required Android Implementation:**
```kotlin
@Composable
fun FloatingActionMenu(
    dataController: DataController,
    modifier: Modifier = Modifier
) {
    val currentUser by dataController.currentUser.collectAsState()
    val canShowFAB = currentUser?.role in listOf(UserRole.ADMIN, UserRole.OFFICE)

    var showCreateMenu by remember { mutableStateOf(false) }

    if (canShowFAB) {
        Box(modifier = modifier.fillMaxSize()) {
            // Dimmed overlay
            if (showCreateMenu) {
                Box(
                    modifier = Modifier
                        .fillMaxSize()
                        .background(
                            Brush.horizontalGradient(
                                colors = listOf(
                                    OpsTheme.colors.background.copy(alpha = 0.85f),
                                    Color.Transparent
                                )
                            )
                        )
                        .clickable { showCreateMenu = false }
                )
            }

            Column(
                modifier = Modifier
                    .align(Alignment.BottomEnd)
                    .padding(end = 36.dp, bottom = 140.dp),
                horizontalAlignment = Alignment.End,
                verticalArrangement = Arrangement.spacedBy(24.dp)
            ) {
                // Menu items
                AnimatedVisibility(
                    visible = showCreateMenu,
                    enter = fadeIn() + slideInHorizontally(initialOffsetX = { it }),
                    exit = fadeOut() + slideOutHorizontally(targetOffsetX = { it })
                ) {
                    Column(
                        horizontalAlignment = Alignment.End,
                        verticalArrangement = Arrangement.spacedBy(24.dp)
                    ) {
                        FloatingActionItem("New Task Type", OpsIcons.TaskType) { }
                        FloatingActionItem("Create Task", OpsIcons.Task) { }
                        FloatingActionItem("Create Project", OpsIcons.Project) { }
                        FloatingActionItem("Create Client", OpsIcons.Client) { }
                    }
                }

                // Main FAB
                FloatingActionButton(
                    onClick = { showCreateMenu = !showCreateMenu },
                    containerColor = OpsTheme.colors.cardBackgroundDark,
                    modifier = Modifier.size(64.dp)
                ) {
                    Icon(
                        imageVector = Icons.Default.Add,
                        contentDescription = "Create",
                        modifier = Modifier.rotate(if (showCreateMenu) 225f else 0f)
                    )
                }
            }
        }
    }
}
```

### Log Activity (Voice Quick Logger)

**Location:** FAB → WORK group (top item)
**Permission:** `pipeline.manage` + `pipeline` feature flag
**File:** `Views/Pipeline/LogActivitySheet.swift`

Voice-first quick logger for recording correspondence with leads. Users speak a natural sentence (e.g., "Call with John Smith, spoke about adding stairs, 13 treads") and the app parses it into structured activity data.

**Components:**
- `SpeechRecognitionManager` — SFSpeechRecognizer wrapper with contextual string boosting from SwiftData
- `VoiceActivityParser` — Local keyword/name extraction with fuzzy Levenshtein matching
- `LogActivityViewModel` — Sheet state management, opportunity loading, save orchestration
- `LogActivitySheet` — Main UI with mic hero, type chips, opportunity picker, notes field
- `OpportunityPickerView` — Searchable opportunity list with inline "+ New Lead" creation

**Voice Parsing Flow:**
1. Type extraction — keyword match at start (call, email, meeting, note, site visit)
2. Contact extraction — "with [1-3 words]" pattern → fuzzy match against active opportunities
3. Notes extraction — remainder cleaned (filler words removed, capitalized)

**Match Confidence Levels:**
- Exact (score >= 0.9): auto-selects opportunity
- High (score >= 0.7): auto-selects opportunity
- Ambiguous (multiple matches): shows disambiguation picker
- No match: pre-fills inline lead creation with parsed name
- No contact pattern: user selects manually

**Speech Recognition:**
- Engine: SFSpeechRecognizer (Apple built-in)
- Server-based when online, on-device offline fallback
- contextualStrings populated from: active opportunity names, client names, team member names
- Auto-stop after 3 seconds of silence
- Audio session: .playAndRecord + .voiceChat (noise suppression, echo cancellation)

**Activity Types (user-loggable):** call, email, meeting, note, site_visit
**Optional Metadata:** direction (inbound/outbound), outcome, duration (minutes)

---

## 10. Advanced UI Patterns

### Custom Alerts
```swift
struct CustomAlertConfig {
    let title: String
    let message: String
    let color: Color
}

.customAlert($customAlert)
```

### Delete Confirmation
```swift
.deleteConfirmation(
    isPresented: $showingDeleteConfirmation,
    itemName: "Project ABC",
    onConfirm: deleteItem
)
```

### Loading Overlay
```swift
// CORRECT (no parameters)
if isLoading {
    OpsLoadingOverlay()
}

// WRONG (don't pass isLoading parameter)
OpsLoadingOverlay(isLoading: isLoading)  // ❌
```

### Status Badge
```swift
OpsStatusBadge(status: project.status)
```

### Empty State
```swift
OpsEmptyState(
    icon: OpsStyle.Icons.task,
    title: "No Tasks Yet",
    subtitle: "Create tasks from projects to get started"
)
```

---

## 11. Project Notes System (OPS Web)

### Overview

Project notes were overhauled in February 2026. Notes are now **project-level only** (task-level notes UI was removed) and are first-class entities stored in the Supabase `project_notes` table, replacing the legacy plain-text `teamNotes` field from Bubble.

Each note supports: author attribution, timestamps, @mentions of team members, and photo attachments with captions and markup.

### Architecture

**Data layer:** Supabase `project_notes` table
**Service:** `src/lib/api/services/project-note-service.ts`
**Hooks:** `src/lib/hooks/use-project-notes.ts`
**Components:** `note-card.tsx`, `notes-list.tsx`, `note-composer.tsx`, `mention-textarea.tsx`
**Types:** `NoteAttachment`, `ProjectNote`, `CreateProjectNote`, `UpdateProjectNote` in `src/lib/types/pipeline.ts`

### Database Table

**Table:** `project_notes`
**Migration:** `supabase/migrations/EXECUTED/003_create_project_notes.sql`

```sql
CREATE TABLE IF NOT EXISTS project_notes (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  project_id TEXT NOT NULL,
  company_id TEXT NOT NULL,
  author_id TEXT NOT NULL,
  content TEXT NOT NULL DEFAULT '',
  attachments JSONB NOT NULL DEFAULT '[]'::jsonb,
  mentioned_user_ids TEXT[] NOT NULL DEFAULT '{}',
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ,
  deleted_at TIMESTAMPTZ
);
```

**Indexes:**
- `idx_project_notes_project_id` -- Partial index on `project_id` WHERE `deleted_at IS NULL` (most common query)
- `idx_project_notes_mentions` -- GIN index on `mentioned_user_ids` WHERE `deleted_at IS NULL` (for notification queries)
- `idx_project_notes_company_id` -- Partial index on `company_id` WHERE `deleted_at IS NULL`

**RLS:** Enabled. Policies allow all authenticated users to read, create, and update. Soft delete via `deleted_at` column.

### TypeScript Types

```typescript
interface NoteAttachment {
  url: string;
  thumbnailUrl?: string | null;
  caption: string | null;
  markedUpUrl?: string | null;
  width?: number;
  height?: number;
}

interface ProjectNote {
  id: string;
  projectId: string;
  companyId: string;
  authorId: string;
  content: string;
  attachments: NoteAttachment[];
  mentionedUserIds: string[];
  createdAt: Date;
  updatedAt: Date | null;
  deletedAt: Date | null;
}

type CreateProjectNote = {
  projectId: string;
  companyId: string;
  authorId: string;
  content: string;
  attachments?: NoteAttachment[];
  mentionedUserIds?: string[];
};

type UpdateProjectNote = {
  id: string;
  content?: string;
  attachments?: NoteAttachment[];
  mentionedUserIds?: string[];
};
```

### ProjectNoteService

Located at `src/lib/api/services/project-note-service.ts`. Follows the same pattern as other Supabase services.

**Methods:**
- `fetchNotes(projectId, companyId)` -- Returns all non-deleted notes for a project, ordered by `created_at` descending
- `createNote(input: CreateProjectNote)` -- Inserts a new note with content, attachments, and mention IDs
- `updateNote(input: UpdateProjectNote)` -- Partial update; sets `updated_at` timestamp
- `deleteNote(id)` -- Soft delete via `deleted_at` timestamp
- `fetchNotesForMentionedUser(userId, companyId)` -- Returns all notes that @mention a specific user (uses GIN index with `contains` operator)
- `migrateFromLegacy(projectId, companyId, legacyNotes, authorId)` -- One-time migration of legacy `project.notes` (Bubble `teamNotes`) to a `project_notes` row; idempotent (checks if any notes already exist for the project before creating)

**DB-to-TS mapping:** `mapRowToProjectNote(row)` converts snake_case DB rows to camelCase TypeScript objects.

### TanStack Query Hooks

Located at `src/lib/hooks/use-project-notes.ts`. Query key: `projectNotes`.

```typescript
useProjectNotes(projectId)         // useQuery — fetches notes for a project
useCreateProjectNote()             // useMutation — creates a note, invalidates project query
useUpdateProjectNote()             // useMutation — updates a note, invalidates project query
useDeleteProjectNote()             // useMutation — soft deletes, invalidates project query
```

All mutation hooks invalidate `queryKeys.projectNotes.byProject(projectId)` on success.

### @Mention System

**Syntax:** `@[Display Name](userId)` -- Markdown-link style with `@` prefix

**Parsing utilities** (in `mention-textarea.tsx`):
- `extractMentionedUserIds(text)` -- Parses content with regex `/@\[([^\]]+)\]\(([^)]+)\)/g` and returns unique user IDs
- `parseMentions(text)` -- Returns array of `{ type: "text", value }` and `{ type: "mention", name, userId }` segments

**MentionTextArea component:**
- Shows user suggestion dropdown when typing `@` followed by text
- Triggers when `@` is preceded by a space, newline, or is at position 0
- Filters users by first/last name match (case-insensitive, max 5 suggestions)
- Arrow keys navigate suggestions, Enter/Tab selects, Escape dismisses
- Inserts mention in `@[First Last](userId)` format and positions cursor after it
- Auto-resizes textarea height (max 200px)
- Dropdown appears above the textarea with dark theme styling (`bg-[#1a1a1a]`)

**Mention rendering** (in `note-card.tsx`):
- `NoteContent` component parses mention syntax and renders `@DisplayName` as styled spans
- Mention spans styled with `bg-[#417394]/20 text-[#8BB8D4]` (steel blue accent)

### UI Components

#### NoteCard (`src/components/ops/note-card.tsx`)
- Displays a single note with author avatar (UserAvatar), display name, time-ago (date-fns `formatDistanceToNow`), and "(edited)" indicator
- Content rendered with @mention highlighting via `NoteContent` component
- Photo attachments displayed as a grid of 128x128 thumbnails; uses `markedUpUrl` if available, falls back to `url`
- Attachment captions shown as overlay at bottom of image
- Edit/Delete dropdown (three-dot menu) visible on hover, only for the note author (`isOwn` check)

#### NotesList (`src/components/ops/notes-list.tsx`)
- Renders a list of `NoteCard` components
- Loading state: 3 skeleton pulse rectangles
- Empty state: StickyNote icon with "No notes yet" message
- Builds a `userMap` from the users array for efficient author lookups

#### NoteComposer (`src/components/ops/note-composer.tsx`)
- Text input using `MentionTextArea` for @mention autocomplete
- Submit via "Post" button or Ctrl+Enter (Cmd+Enter on Mac) keyboard shortcut
- Calls `extractMentionedUserIds()` on submit to extract mention IDs from content
- Resets textarea content and height after submit
- Submit button styled with `bg-[#417394]` (primary accent) with Send icon
- Placeholder: "Write a note... (type @ to mention someone)"
- Disabled state while `isSubmitting`

### Project Details Integration

The Notes tab in the project details page (`src/app/(dashboard)/projects/[id]/page.tsx`) contains:

1. **NoteComposer** at the top for creating new notes
2. **NotesList** below showing all existing notes

**Legacy migration:** On first visit to the Notes tab, if the project has a legacy `project.notes` string (from Bubble's `teamNotes` field) and no `project_notes` rows exist yet, it automatically calls `ProjectNoteService.migrateFromLegacy()` to create one note from the legacy text. This is idempotent and uses a `useRef` flag (`migrated`) to prevent duplicate calls.

### Changes to Task UI

As part of this overhaul, task-level notes were removed:
- **task-form.tsx** -- The `taskNotes` field was removed from the form schema and UI
- **task-list.tsx** -- The `taskNotes` display and mutation references were removed

Notes are now exclusively at the project level, accessed via the Notes tab on the project details page.

### Remaining Work (Tasks 13-20)

The following features are planned but not yet implemented:
- **Photo attachments in composer** -- Upload, preview, and remove photos when composing a note
- **Photo caption dialog** -- Add captions to attached photos
- **Cross-post note photos to project gallery** -- Note photos auto-appear in the project photo gallery
- **Photo markup** -- Canvas-based annotation with freehand drawing on attached photos
- **Notification service for @mentions** -- Alert users when they are @mentioned in a note
- **Edit and delete notes UI** -- Full edit/delete flow (backend supports it, UI wiring pending)

---

## 12. Photo Annotations

### Overview
PencilKit-based photo annotation feature that allows crew members to draw on project photos and attach text notes. Annotations render as transparent PNG overlays stored in S3, with the drawing data kept locally in SwiftData for offline editing. Backed by the `project_photo_annotations` Supabase table.

### Architecture Components

#### PhotoAnnotation Model (iOS)
**Location:** `OPS/OPS/DataModels/Supabase/PhotoAnnotation.swift`

SwiftData model with the following fields:
```swift
@Model
class PhotoAnnotation: Identifiable {
    @Attribute(.unique) var id: String
    var projectId: String
    var companyId: String
    var photoURL: String           // The original photo being annotated
    var annotationURL: String?      // S3 URL of the rendered PNG overlay
    var note: String                // Free-text note attached to the annotation
    var authorId: String
    var createdAt: Date
    var updatedAt: Date?
    var deletedAt: Date?            // Soft delete

    // Sync tracking
    var lastSyncedAt: Date?
    var needsSync: Bool = false

    // Local-only: PKDrawing data for offline editing
    var localDrawingData: Data?
}
```

#### PhotoAnnotationView (iOS)
**Location:** `OPS/OPS/Views/Components/Images/PhotoAnnotationView.swift`

Full-screen annotation view with three layers:
1. **Original photo** -- AsyncImage loaded from the photo URL
2. **Existing annotation overlay** -- rendered PNG from S3, shown when not editing
3. **PencilKit canvas** -- active drawing surface, shown in editing mode

**UI elements:**
- **Toolbar:** Close button, Undo stroke, Clear all, Cancel editing, Done (save)
- **Bottom bar:** Text field for adding a note to the annotation
- **Drawing tool:** Default tool is a thin white pen (`PKInkingTool(.pen, color: .white, width: 3)`)
- **Input mode:** `drawingPolicy = .anyInput` -- works with both finger and Apple Pencil
- **Tool picker:** System `PKToolPicker` shown via `UIViewRepresentable` wrapper

**PencilKitCanvas:** UIViewRepresentable wrapper around `PKCanvasView` with:
- Transparent background (`.clear`, `.isOpaque = false`)
- Coordinator that syncs `canvasViewDrawingDidChange` back to the SwiftUI `@Binding`
- Tool picker visibility managed via `showToolPicker` binding

#### PhotoAnnotationSyncManager (iOS)
**Location:** `OPS/OPS/Network/PhotoAnnotationSyncManager.swift`

Singleton (`PhotoAnnotationSyncManager.shared`) that handles:
1. **Rendering** -- `renderDrawingToPNG(drawing:size:)` uses `UIGraphicsImageRenderer` to render `PKDrawing` strokes onto a transparent PNG at the image's native size
2. **S3 upload** -- Requests a presigned URL from `AppConfiguration.apiBaseURL/api/uploads/presign`, then PUTs the PNG to S3 with content type `image/png`. Files stored at `annotations/{companyId}/{projectId}/annotation_{timestamp}.png`
3. **Supabase record** -- Creates or updates a row in `project_photo_annotations` via `PhotoAnnotationRepository`
4. **Offline fallback** -- If S3 upload fails, the `PKDrawing` data is stored locally in `localDrawingData`, and `needsSync` is set to `true`
5. **Pending sync** -- `syncPendingAnnotations(modelContext:)` fetches all annotations where `needsSync == true`, re-renders and uploads them

#### PhotoAnnotationRepository (iOS)
**Location:** `OPS/OPS/Network/Supabase/Repositories/PhotoAnnotationRepository.swift`

**Table:** `project_photo_annotations`

**Methods:**
- `fetchForProject(projectId)` -- all non-deleted annotations for a project, ordered by `created_at` descending
- `fetchForPhoto(projectId, photoURL)` -- single annotation for a specific photo
- `create(dto)` / `upsert(dto)` -- insert or upsert annotation
- `updateAnnotation(id, annotationUrl, note)` -- partial update with `updated_at` timestamp
- `softDelete(id)` -- sets `deleted_at` and `updated_at`

#### PhotoAnnotationDTOs (iOS)
**Location:** `OPS/OPS/Network/Supabase/DTOs/PhotoAnnotationDTOs.swift`

```swift
struct PhotoAnnotationDTO: Codable, Identifiable {
    let id: String
    let projectId: String       // project_id
    let companyId: String       // company_id
    let photoUrl: String        // photo_url
    let annotationUrl: String?  // annotation_url (S3 PNG)
    let note: String?
    let authorId: String        // author_id
    let createdAt: String
    let updatedAt: String?
    let deletedAt: String?
}

struct UpsertPhotoAnnotationDTO: Codable {
    let projectId: String
    let companyId: String
    let photoUrl: String
    let annotationUrl: String?
    let note: String
    let authorId: String
}
```

---

## 13. Inventory Management

### Overview
Materials and supplies tracking system with items, tags, units, quantity thresholds, snapshots, bulk operations, and spreadsheet import. Uses a tactical minimalist design with pinch-to-zoom card scaling.

### Architecture Components

#### InventoryView (iOS)
**Location:** `OPS/OPS/Views/Inventory/InventoryView.swift`

Main inventory view with:
- **Search** -- text-based item search
- **Tag filtering** -- filter by selected tags
- **Sort modes** -- TAG, NAME, QUANTITY, THRESHOLD
- **Selection mode** -- multi-select for bulk operations
- **Pinch-to-zoom** -- `@AppStorage("inventoryCardScale")` with range 0.8 to 1.5, persisted
- **Import** -- spreadsheet import button
- **Manage tags** -- global tag rename/delete

**Bulk operations (selection mode):**
- **Bulk quantity adjustment** -- apply +/- amount to all selected items
- **Bulk tag editing** -- add/remove tags from all selected items
- **Bulk delete** -- soft delete multiple items with confirmation

#### InventoryListView (iOS)
**Location:** `OPS/OPS/Views/Inventory/InventoryListView.swift`

LazyVStack of `InventoryItemCard` components with:
- **Progressive disclosure via scale:**
  - Scale >= 0.9: show tag badges (up to 4 visible, "+N" for overflow)
  - Scale >= 1.0: show metadata (SKU) and full threshold badge with unit display
- **Quantity display** -- large Mohave font, colored by threshold status
- **Threshold badges** -- "LOW", "CRITICAL" labels with colored pill background
- **Long press** -- confirmation dialog with Edit, Select, Delete options
- **Item count footer** -- "[ N ITEMS ]"

#### InventoryFormSheet (iOS)
**Location:** `OPS/OPS/Views/Inventory/InventoryFormSheet.swift`

Form for creating and editing inventory items with:
- **Item Details section** (always expanded): Name, Quantity + Unit picker, Tags (with inline add, predictive suggestions, and existing tag pills)
- **Additional Details section** (collapsible): Description, SKU/Part Number, Notes, Quantity Thresholds (warning + critical levels with colored indicators)
- **Tag creation:** Tags are created in Supabase first to obtain server IDs, then linked locally. `findOrCreateTag()` handles both sync and local creation.
- **Tag junction sync:** `repo.setItemTags(itemId:tagIds:)` syncs the item-to-tag relationship

#### QuantityAdjustmentSheet (iOS)
**Location:** `OPS/OPS/Views/Inventory/QuantityAdjustmentSheet.swift`

Quick quantity adjustment with:
- Large Mohave-Bold (56pt) quantity display, tappable for direct text entry
- Horizontal scroll of quick-adjust pills: [-100, -50, -10, -1, +1, +10, +50, +100] (configurable via `AdjustmentSettings`)
- Change indicator showing `current -> new` with color coding (green for increase, red for decrease)
- Auto-scroll to center pill on appear
- Haptic feedback on each adjustment

#### BulkQuantityAdjustmentSheet (iOS)
**Location:** `OPS/OPS/Views/Inventory/BulkQuantityAdjustmentSheet.swift`

Applies the same +/- adjustment to all selected items:
- Same quick-adjust pills as single-item sheet
- Preview toggle to show/hide affected items with current-to-new quantities
- Syncs each item individually to Supabase, reports failures

#### BulkTagsSheet (iOS)
**Location:** `OPS/OPS/Views/Inventory/BulkTagsSheet.swift`

Add/remove tags from multiple selected items:
- **Pending changes section** -- shows tags to add ("+") and tags to remove ("-") as badges
- **Create new tag** -- inline text field to create and add a new tag
- **Add existing tags** -- pills for all available company tags not yet on all items
- **Remove tags** -- pills for tags currently on any selected items, with item count
- Creates new tags in Supabase, syncs junction table for each item

#### InventoryManageTagsSheet (iOS)
**Location:** `OPS/OPS/Views/Inventory/InventoryManageTagsSheet.swift`

Global tag management:
- Search/filter tags
- Status bar showing total tags and total items tagged
- Per-tag row with rename (alert dialog) and delete (confirmation) actions
- Rename applies across all items; delete removes from all items

#### SnapshotListView (iOS)
**Location:** `OPS/OPS/Views/Inventory/SnapshotListView.swift`

Point-in-time inventory snapshots:
- List of snapshots with date, item count, and type (Automatic/Manual)
- Detail view with summary card and itemized list (quantity, unit, name, SKU)
- Fetched from Supabase via `repo.fetchSnapshots()` and `repo.fetchSnapshotItems(snapshotId:)`

#### Spreadsheet Import (iOS)
**Location:** `OPS/OPS/Views/Inventory/Import/SpreadsheetImportSheet.swift`

Multi-step import wizard:
1. **Select File** -- file picker for CSV or XLSX via `fileImporter`
2. **Configure** -- orientation (rows-are-items or columns-are-items), import mode (multiple items, single item, or variations)
3. **Map Fields** -- interactive column-to-field mapping (`ColumnMappingView`)
4. **Preview** -- parsed items with validation, duplicate detection, selection, inline editing (`ImportPreviewView`)
5. **Importing** -- progress bar, syncs each item to Supabase with tags
6. **Complete** -- results summary (created, skipped, failed)

Supporting files:
- `OPS/OPS/Views/Inventory/Import/ImportConfigView.swift` -- orientation and mode selection
- `OPS/OPS/Views/Inventory/Import/ColumnMappingView.swift` -- column-to-field mapping
- `OPS/OPS/Views/Inventory/Import/ImportPreviewView.swift` -- preview with editing and filtering

---

## 14. Notification System

### Overview
Multi-layer notification system combining local (UNUserNotificationCenter), push (OneSignal), and in-app (Supabase `notifications` table) notifications. Features batching during sync, deep linking to projects, unread tracking, quiet hours, and per-type preference controls.

### Architecture Components

#### NotificationManager (iOS)
**Location:** `OPS/OPS/Utilities/NotificationManager.swift`

Singleton (`NotificationManager.shared`) managing all notification operations.

**Notification Categories:**
```swift
enum NotificationCategory: String {
    case project = "PROJECT_NOTIFICATION"
    case schedule = "SCHEDULE_NOTIFICATION"
    case team = "TEAM_NOTIFICATION"
    case general = "GENERAL_NOTIFICATION"
    case projectAssignment = "PROJECT_ASSIGNMENT_NOTIFICATION"
    case projectUpdate = "PROJECT_UPDATE_NOTIFICATION"
    case projectCompletion = "PROJECT_COMPLETION_NOTIFICATION"
    case projectAdvance = "PROJECT_ADVANCE_NOTIFICATION"
}
```

**Notification Actions:**
```swift
enum NotificationAction: String {
    case view = "VIEW_ACTION"
    case accept = "ACCEPT_ACTION"
    case decline = "DECLINE_ACTION"
    case dismiss = "DISMISS_ACTION"
}
```

**Priority Levels:**
```swift
enum NotificationPriorityLevel: String {
    case normal = "normal"
    case important = "important"
    case critical = "critical"
}
```

**Key Responsibilities:**
- Permission request and authorization status tracking
- OneSignal integration (`OneSignalFramework`) for push notifications
- Local notification scheduling: project assignment, schedule update, project completion, advance notice
- `shouldSendNotification(priority:)` -- filters based on user settings (quiet hours, mute, priority level)
- Significant location change listener for geofence-based notifications
- Combines `UNUserNotificationCenter.delegate` for foreground notification handling

#### NotificationBatcher (iOS)
**Location:** `OPS/OPS/Utilities/NotificationBatcher.swift`

Singleton that collects notifications during sync and sends grouped summaries to avoid notification spam.

**Batch Types:**
```swift
enum NotificationType: String, CaseIterable {
    case assignment = "assignment"
    case scheduleChange = "scheduleChange"
    case completion = "completion"
    case taskAssignment = "taskAssignment"
    case taskUpdate = "taskUpdate"
}
```

**Batch Lifecycle:**
1. `startBatch()` -- begins collecting (called at sync start)
2. `add(type:projectId:projectName:taskId:details:)` -- queues a notification; if not in batch mode, sends immediately via NotificationManager
3. `flushBatch()` -- groups by type, generates one summary notification per type (single items get specific detail, multiple get count summary)
4. `cancelBatch()` -- discards all pending without sending

#### NotificationRepository (iOS)
**Location:** `OPS/OPS/Network/Supabase/Repositories/NotificationRepository.swift`

**Table:** `notifications`

**Methods:**
- `fetchUnreadCount(userId:)` -- server-side count via `head: true, count: .exact` (no row transfer)
- `fetchRecent(userId:, limit: 50)` -- last 50 notifications ordered by `created_at` descending
- `markAsRead(notificationId)` -- sets `is_read = true` for a single notification
- `markAllAsRead(userId:)` -- sets `is_read = true` for all unread notifications for a user

#### NotificationDTO (iOS)
**Location:** `OPS/OPS/Network/Supabase/DTOs/NotificationDTO.swift`

```swift
struct NotificationDTO: Codable, Identifiable {
    let id: String
    let userId: String        // user_id
    let companyId: String     // company_id
    let type: String          // "mention", "assignment", "update"
    let title: String
    let body: String
    let projectId: String?    // project_id (for deep linking)
    let noteId: String?       // note_id (for @mention notifications)
    var isRead: Bool          // is_read
    let createdAt: String     // created_at
}
```

#### NotificationListView (iOS)
**Location:** `OPS/OPS/Views/Notifications/NotificationListView.swift`

In-app notification list:
- Fetches from `NotificationRepository.fetchRecent(userId:)`
- Each row shows: unread dot indicator, type-specific icon (mention = primaryAccent, assignment = successStatus, update = secondaryText), title (bold if unread), body (2 lines), relative time
- Tap action: marks as read locally and on server, deep links to project if `projectId` is set via `appState.viewProjectDetailsById()`
- "Mark All Read" toolbar button
- Empty state with bell.slash icon

#### NotificationSettingsView (iOS)
**Location:** `OPS/OPS/Views/Settings/NotificationSettingsView.swift`

User notification preferences stored in `@AppStorage`:
- **Per-type toggles:** Project Assignment, Schedule Changes, Project Completion
- **Advance notice:** configurable days (1st required, 2nd/3rd optional), time of day
- **Quiet hours:** enabled/disabled, start hour (default 22:00), end hour (default 07:00)
- **Priority filter:** "all", "important", "critical"
- **Temporary mute:** mute for N hours

#### Web Notification Rail (OPS Web)

The web app surfaces notifications via a horizontal rail in the TopBar header, replacing the old page action buttons (now handled by the FAB).

**Components:**
- `src/components/layouts/notification-rail.tsx` — Container with collapsed/expanded toggle
- `src/components/layouts/notification-pill.tsx` — Collapsed indicator (6×14px rounded pill, color-coded)
- `src/components/layouts/notification-mini-card.tsx` — Expanded inline card (180px, frosted glass, 36px tall)
- `src/components/layouts/notification-card-full.tsx` — Full card for modal view (title, body, timestamp, action button)
- `src/components/layouts/notification-modal.tsx` — Centered dialog with grouped notifications (Today/Yesterday/Earlier)

**States:**
- **Collapsed (default):** Row of small pills stacking left-to-right (oldest first). Gray = standard, accent (#597794) = persistent. Count label after pills. Click to expand.
- **Expanded:** Pills animate into mini cards with horizontal scroll. Each card shows title, optional action button, optional dismiss X. "View all" button at end.
- **Modal:** Triggered by bell icon or "View all". Full notification cards grouped by date. "Dismiss all" for non-persistent.

**Data Model Extensions (Web):**
```typescript
interface AppNotification {
  // ... base fields (id, userId, companyId, type, title, body, projectId, noteId, isRead, createdAt) ...
  persistent: boolean;       // true = cannot be dismissed by user
  actionUrl: string | null;  // deep-link (e.g. "/projects/abc")
  actionLabel: string | null; // button label (e.g. "View Results")
}
```

Supabase columns: `persistent` (BOOLEAN DEFAULT false), `action_url` (TEXT), `action_label` (TEXT).

**State Management:**
- `src/stores/notification-rail-store.ts` — Zustand store for collapsed/expanded/modal UI state
- `src/lib/hooks/use-notifications.ts` — TanStack Query hook with 30s stale time, optimistic dismiss mutations (`useDismissNotification`, `useDismissAllNotifications`)

**Service Methods (Web):**
- `NotificationService.fetchUnread(userId, companyId)` — ascending order, limit 50
- `NotificationService.markAsRead(notificationId)` — single dismiss
- `NotificationService.markAllAsRead(userId, companyId)` — mark all read
- `NotificationService.dismissAllDismissible(userId, companyId)` — dismiss only non-persistent

**Animation:** All variants in `src/lib/utils/motion.ts` with `EASE_SMOOTH` easing and reduced-motion fallbacks. No spring/bounce.

**Integration Pattern:** Any feature that produces a user-facing event should insert a row into the `notifications` table. The rail picks it up automatically via the polling hook.

---

## 15. Crew Location Tracking

### Overview
Real-time crew location broadcasting and subscribing system for the map view. Active crew members broadcast their GPS position to the `crew_locations` Supabase table. Admins and office crew subscribe to see all org members on the map. Includes throttling, noise filtering, battery level reporting, and background state tracking.

### Architecture Components

#### CrewLocationUpdate Model
**Location:** `OPS/OPS/Map/Models/CrewLocationUpdate.swift`

```swift
struct CrewLocationUpdate: Codable {
    let userId: String
    let orgId: String
    let firstName: String
    var lastName: String?
    let lat: Double
    let lng: Double
    let heading: Double
    let speed: Double
    let accuracy: Double
    let timestamp: Date
    let batteryLevel: Float
    let isBackground: Bool
    var currentTaskName: String?
    var currentProjectName: String?
    var currentProjectId: String?
    var currentProjectAddress: String?
    var phoneNumber: String?
}
```

#### CrewLocationBroadcaster (iOS)
**Location:** `OPS/OPS/Map/Services/CrewLocationBroadcaster.swift`

`@MainActor` singleton that publishes the current user's location.

**Broadcast behavior:**
- Subscribes to `LocationManager.$currentLocation` via Combine
- **Throttling:** broadcast every 5 seconds when moving (speed > 1 m/s), every 30 seconds when stationary
- **Persist throttling:** writes to Supabase every 10 seconds when moving, every 60 seconds when stationary
- **Noise filtering:** rejects readings older than 10 seconds, accuracy worse than 50m, and identical coordinates
- Reports battery level and background/foreground state

**Local broadcast:** Posts `crewLocationDidUpdate` NotificationCenter notification for same-device subscribers (e.g., the map view)

**Supabase persistence:** Upserts to `crew_locations` table via `CrewLocationUpsertDTO` with fields: `user_id`, `org_id`, `first_name`, `last_name`, `lat`, `lng`, `heading`, `speed`, `accuracy`, `battery_level`, `is_background`, `phone_number`, `updated_at`

#### CrewLocationSubscriber (iOS)
**Location:** `OPS/OPS/Map/Services/CrewLocationSubscriber.swift`

`@MainActor` observable that maintains a dictionary of `[userId: CrewLocationUpdate]` for all org members.

**Subscription behavior:**
1. `subscribe(orgId:)` -- loads initial state from `crew_locations` table, then:
   - Listens for local `crewLocationDidUpdate` notifications (from the broadcaster on the same device)
   - Polls the DB every 15 seconds via `Timer` for updates from other devices
2. `unsubscribe()` -- clears all data, cancels subscriptions and timer

**DB row mapping:**
```swift
struct CrewLocationRow: Codable {
    let user_id: String
    let org_id: String
    let first_name: String
    let last_name: String?
    let lat: Double
    let lng: Double
    let heading: Double?
    let speed: Double?
    let accuracy: Double?
    let battery_level: Float?
    let is_background: Bool?
    let current_task_name: String?
    let current_project_name: String?
    let current_project_id: String?
    let current_project_address: String?
    let phone_number: String?
    let updated_at: Date
}
```

#### LocationManager (iOS)
**Location:** `OPS/OPS/Utilities/LocationManager.swift`

Core location wrapper providing:
- Authorization status tracking with `@Published var authorizationStatus`
- User coordinate, full CLLocation (with course), device heading, and GPS course
- Configured with `kCLLocationAccuracyNearestTenMeters`, 10m distance filter, automotive activity type
- Heading updates with 5-degree filter
- `requestPermissionIfNeeded(requestAlways:)` with session-level deduplication

---

## 16. Schedule Tab Redesign

**Added:** 2026-03-02
**Scope:** Complete replacement of the Schedule Tab view layer.

### Overview

The Schedule Tab was redesigned to replace the old week/month toggle pattern with a continuous day-based pager and personal event support. The `CalendarSchedulerSheet` (used for setting task dates) was not changed.

### Deleted Components

| File | Replaced By |
|------|-------------|
| `CalendarToggleView.swift` | `CalendarDaySelector` (week strip + month grid toggle) |
| `ProjectListView.swift` | `DayCanvasView` (horizontal day pager) |

### New Components

#### DayCanvasView
**File:** `Views/Calendar Tab/DayCanvasView.swift`

Horizontal 3-page `TabView` pager using the infinite-scroll trick:
- Pages are always `[selectedDate - 1 day, selectedDate, selectedDate + 1 day]`
- On page change, `selectedDate` is updated and `pageIndex` snaps back to 1 after a 50ms `DispatchQueue` delay
- An `isSnappingBack` boolean guards against re-triggering the page change handler during the snap-back
- Each page renders a `DayPageView` containing:
  - Day header (day-of-week string, date string, task count badge)
  - "New" tasks section — tasks whose `startDate` is on this day, with staggered card entry animation
  - "Ongoing" tasks section — tasks started before this day, separated by a labeled divider
  - `CalendarUserEventCard` rows for personal events and time-off requests
  - Empty state when no tasks or events exist

#### CalendarDaySelector
**File:** `Views/Calendar Tab/Components/CalendarDaySelector.swift`

Combined week strip and month grid:
- Default state: horizontal `WeekDayCell` row (7 days visible, centered on `selectedDate`)
- `isMonthExpanded == true`: expands to `MonthGridView` via `matchedGeometryEffect` hero animation
- Pinch gesture on the month grid collapses it back to the week strip

#### WeekDayCell
**File:** `Views/Calendar Tab/Components/WeekDayCell.swift`

Day cell in the week strip:
- Shows day abbreviation and day number
- Up to 4 colored density bars — one per distinct task color for tasks on that day
- If >4 tasks exist, the fourth slot shows `···` overflow indicator instead of a bar
- Today is highlighted with a distinct background

#### CalendarEventCard
**File:** `Views/Calendar Tab/Components/CalendarEventCard.swift`

Task card in `DayPageView`. Has a `DayPosition` enum: `.single`, `.start`, `.middle`, `.end` — used to visually connect multi-day tasks with open leading/trailing edges.

#### CalendarUserEventCard
**File:** `Views/Calendar Tab/Components/CalendarUserEventCard.swift`

Card for personal events and time-off requests:
- Shows event title, type badge ("Personal" / "Time Off"), date range
- Time-off cards show status badge ("Pending" / "Approved" / "Rejected")
- Supports swipe-to-delete

#### PersonalEventSheet
**File:** `Views/Calendar Tab/Components/PersonalEventSheet.swift`

Bottom sheet for creating a personal calendar event:
- Fields: title, start date, end date, all-day toggle, notes
- Creates `CalendarUserEvent` with `type: .personal`, `status: .confirmed`
- Syncs to `calendar_user_events` Supabase table immediately

#### TimeOffRequestSheet
**File:** `Views/Calendar Tab/Components/TimeOffRequestSheet.swift`

Bottom sheet for submitting a time-off request:
- Fields: title, start date, end date, notes
- Uses amber color scheme (distinct from blue personal event sheet)
- Wrapped in `ScrollView` so the submit button remains visible above keyboard
- Creates `CalendarUserEvent` with `type: .timeOff`, `status: .pending`
- Syncs to `calendar_user_events` Supabase table immediately

#### MonthGridView
**File:** `Views/Calendar Tab/MonthGridView.swift`

Full month calendar grid:
- Accessible by tapping the month icon in `AppHeader`
- Supports pinch-to-collapse gesture that restores week strip
- Animates open/close via `matchedGeometryEffect` tied to `CalendarDaySelector`

### ScheduleView Orchestration

**File:** `Views/ScheduleView.swift`

- Renders `CalendarDaySelector` above `DayCanvasView` (no more view-mode switch)
- Passes `onMonthTapped: { viewModel.toggleMonthExpanded() }` to `AppHeader`
- Listens for `ShowPersonalEventSheet` notification → sets `showPersonalEventSheet = true`
- Listens for `ShowTimeOffRequestSheet` notification → sets `showTimeOffRequestSheet = true`
- Passes `isScheduleTab: true` to `FloatingActionMenu`

### CalendarViewModel Changes

| Change | Detail |
|--------|--------|
| Added `isMonthExpanded: Bool` | Drives week strip ↔ month grid toggle |
| Added `toggleMonthExpanded()` | Called by AppHeader month icon tap; uses spring animation |
| Added `userEvents(for:) -> [CalendarUserEvent]` | Returns personal events/time-off for a given date |
| Added `loadUserEvents() async` | Fetches `CalendarUserEvent` records from Supabase |
| Removed `shouldShowDaySheet` | No longer needed (DayEventsSheet pattern eliminated) |
| Removed `resetDaySheetState()` | Removed with the above |

### Data Layer

- **SwiftData model:** `CalendarUserEvent` — see `03_DATA_ARCHITECTURE.md` section 25
- **Supabase table:** `calendar_user_events`
- **Repository:** `CalendarUserEventRepository.swift`
- **DTOs:** `CalendarUserEventDTOs.swift`
- **RLS note:** Uses `CAST(auth.uid() AS TEXT) = user_id` due to UUID/text type mismatch

---

## 17. Web Calendar Overhaul (OPS-Web)

**Added:** 2026-03-02
**Scope:** Complete rebuild of the OPS-Web calendar from a 1119-line monolith into a modular 18-component interactive scheduling system.

### Overview

The web calendar was rebuilt across 4 phases to match best-in-class scheduling UX from Jobber, ServiceTitan, and Google Calendar. Key capabilities: drag-and-drop scheduling, event resize, 5 view modes, multi-filter sidebar, team Gantt timeline, conflict detection, and full keyboard navigation.

### Architecture

```
calendar-store.ts  →  page.tsx (orchestrator)  →  Grid components
     (Zustand)         ↕                           ↕
                    TanStack Query hooks         event-block.tsx
                    (useCalendarEventsForRange)   (draggable via @dnd-kit)
                       ↕
                    Supabase CRUD
```

**State management:** Zustand store (`calendar-store.ts`) with `persist` middleware. Persisted to localStorage `"ops-calendar"`: view preference, filter selections. Ephemeral: selected event, panel states, quick-create anchor, drag state.

### File Structure

```
src/app/(dashboard)/calendar/
  page.tsx                          — Orchestrator (~420 lines)
  _components/
    calendar-header.tsx             — Nav, view switcher, filter toggle
    calendar-toolbar.tsx            — Stats bar + filter chips
    calendar-grid-month.tsx         — Month grid view
    calendar-grid-week.tsx          — Week time grid (7 cols)
    calendar-grid-day.tsx           — Day time grid (1 col)
    calendar-grid-team.tsx          — Team Gantt timeline
    calendar-agenda.tsx             — Agenda list view
    time-grid-column.tsx            — Shared column for week/day
    current-time-indicator.tsx      — Red line for current time
    event-block.tsx                 — Draggable + resizable event
    event-block-month.tsx           — Compact event for month cells
    event-tooltip.tsx               — Hover tooltip
    event-detail-panel.tsx          — Right Sheet for editing
    event-context-menu.tsx          — Right-click menu
    event-quick-create.tsx          — Click-to-create popover
    filter-sidebar.tsx              — Left filter panel
    unscheduled-panel.tsx           — Drag source for unscheduled tasks
    calendar-dnd-context.tsx        — @dnd-kit provider + overlay

src/stores/calendar-store.ts        — Zustand store
src/lib/hooks/use-calendar-dnd.ts   — DnD handlers + snap logic
src/lib/utils/calendar-utils.ts     — Positioning, snapping, overlap, conflict detection
src/lib/utils/calendar-constants.ts — HOURS, HOUR_HEIGHT (60px), FIRST_HOUR (6), task type colors
```

### Constants

| Constant | Value | Purpose |
|----------|-------|---------|
| `HOUR_HEIGHT` | 60px | Pixels per hour in time grids |
| `FIRST_HOUR` | 6 | Grid starts at 6 AM |
| `HOURS` | 6–23 | Array of rendered hours |
| `TEAM_HOUR_COLUMN_WIDTH` | 80px | Pixels per hour in team timeline |
| Snap interval | 15 min | All DnD and resize operations snap to 15 minutes |
| `ROW_HEIGHT` (team) | 56px | Height per team member row |
| `MEMBER_GUTTER_WIDTH` | 180px | Team member name column width |

### Drag-and-Drop System

**Provider:** `CalendarDndContext` wraps all grid content.

**Sensor:** `PointerSensor` from `@dnd-kit/core` with `activationConstraint: { distance: 8 }`.

**Flow:**
1. `handleDragStart` — sets `draggedEventId` in store, finds event data
2. `handleDragMove` — computes pixel→time delta (view-aware axis), updates `dragPreview` in store for real-time time labels on `DragOverlay`
3. `handleDragEnd` — snaps to 15-min grid, calls `useUpdateCalendarEvent()` mutation, clears drag state

**Axis awareness:**
- Week/Day views: `deltaMinutes = (delta.y / HOUR_HEIGHT) * 60`
- Team view: `deltaMinutes = (delta.x / TEAM_HOUR_COLUMN_WIDTH) * 60`

**Unscheduled task drop:** When a task from the UnscheduledPanel is dropped onto the grid, a new calendar event is created and linked to the task via `useCreateCalendarEvent()`.

### Event Resize

Bottom-edge resize uses native mouse events (not @dnd-kit, which doesn't support resize):
- 6px hit area at bottom of `EventBlock` with `cursor-ns-resize`
- `mousedown` → captures start Y position
- `mousemove` on document → computes delta, snaps to `HOUR_HEIGHT / 4` (15 min)
- `mouseup` → calls `onResize(event, newEndDate)` → `useUpdateCalendarEvent()`
- Minimum height enforced at 15 minutes (one snap unit)
- DnD listeners disabled during resize via `{...(isResizing ? {} : listeners)}`

### Click-and-Drag Range Selection

In `TimeGridColumn`:
- `DRAG_THRESHOLD = 8` pixels before triggering range mode
- `mousedown` starts tracking, `mousemove` shows blue highlight (`bg-ops-accent/15 border border-ops-accent/40`) with time labels
- `mouseup` fires `onRangeSelect(startDate, endDate, clientX, clientY)` → opens quick-create popover
- `data-event-block` attribute on events prevents range drag from triggering on event elements
- `isDraggingRef` prevents click handler from firing after a drag

### Conflict Detection

`detectConflicts()` in `calendar-utils.ts`:
- Groups events by team member ID
- For each member, sorts events by start time
- Checks if any event's start time falls before the previous event's end time
- Returns `Set<string>` of conflicting event IDs
- `conflictIds` passed to grid components → `EventBlock` shows red ring + glow: `ring-1 ring-red-500/60 shadow-[0_0_8px_rgba(239,68,68,0.3)]`

### Team Timeline (Gantt View)

`CalendarGridTeam`:
- Y-axis: one row per team member (56px height) with avatar + name in left gutter (180px)
- X-axis: hours of the day (80px per hour)
- Events rendered as horizontal bars positioned by `(startHour - FIRST_HOUR) * 80` with width `durationHours * 80`
- `TeamEventBar` component uses `useDraggable` with horizontal-only transform: `translate3d(${transform.x}px, 0px, 0)`
- Availability heatmap: each row has a background div with opacity `= Math.min(totalScheduledMinutes / 480, 1) * 0.12` — 8 hours (480 min) = fully loaded
- Unassigned row for events with no team member assignment

### Animations

Defined in `src/lib/utils/motion.ts`:

| Variant | Behavior | Duration |
|---------|----------|----------|
| `calendarViewVariants` | Horizontal slide ±40px + fade | 300ms ease |
| `calendarViewVariantsReduced` | Opacity-only fade | 150ms |
| `calendarEventVariants` | Scale 0.95→1 + fade | 150ms ease |
| `calendarEventVariantsReduced` | Opacity-only | 100ms |
| `SPRING_CALENDAR_DRAG` | Spring stiffness: 400, damping: 30 | N/A |

All animations use `useReducedMotion()` from framer-motion to select reduced variants when the user has `prefers-reduced-motion` enabled.

### Keyboard Shortcuts

| Key | Action |
|-----|--------|
| D / W / M / T / A | Switch view (day/week/month/team/agenda) |
| ArrowLeft / ArrowRight | Navigate prev/next (period-aware) |
| Y | Go to today |
| C | Create event (opens quick-create at viewport center) |
| E | Edit selected event (opens detail panel) |
| Tab / Shift+Tab | Cycle through events |
| Enter | Open detail panel for selected event |
| Delete / Backspace | Delete selected event |
| Escape | Close panels, deselect, dismiss menus |

Shortcuts are disabled when focus is in an `<input>` or `<textarea>`.

### Responsive Breakpoints

| Breakpoint | Layout | Behavior |
|------------|--------|----------|
| Desktop ≥1200px | Three-panel | Filter sidebar + calendar grid + detail panel |
| Tablet 768–1199px | Two-panel | All views available, sidebar toggleable |
| Mobile <768px | Single panel | Agenda view forced, filter sidebar hidden, view switcher hidden |

### Dependencies

| Package | Version | Usage |
|---------|---------|-------|
| `@dnd-kit/core` | 6.3.0 | DnD provider, sensors, draggable, overlay |
| `framer-motion` | — | View transitions, event animations, reduced motion |
| `@radix-ui/react-popover` | — | Quick-create popover |
| `date-fns` | — | All date math (addMinutes, differenceInMinutes, format, etc.) |
| Zustand | — | Client-side state with persist middleware |
| TanStack Query | — | Server state, optimistic updates |

---

## Android Implementation Priority

**CRITICAL (must implement):**
1. FloatingActionMenu (completely missing)
2. PIN Manager (must change to 4-digit)
3. SwipeToChangeStatus gesture system
4. Tutorial system (30 phase definitions + pipeline phases)
5. CalendarSchedulerSheet with conflict detection
6. Schedule Tab redesign: DayCanvasView, CalendarDaySelector, WeekDayCell density bars

**HIGH (feature parity):**
7. ImageSyncManager with S3 integration
8. NavigationEngine with Kalman filter
9. Job Board filtering and sorting
10. Form sheets with progressive disclosure
11. Inventory management system
12. Notification system with OneSignal
13. Crew location tracking
14. CalendarUserEvent (personal events + time-off)

**MEDIUM (polish):**
15. Advanced UI patterns (custom alerts, etc.)
16. Photo annotation with PencilKit equivalent

---

## 17. Feature Flags System

### Overview

Feature flags provide a master on/off toggle for entire product modules, independent of RBAC permissions. An admin can disable a flag to hide an entire feature from all users, or grant individual user overrides for early access/beta testing.

Feature flags and RBAC permissions work together:
1. **Feature flag** must be enabled (or user must have an override) for the feature's routes and permissions to be accessible
2. **RBAC permission** must be granted to the user's role for them to see/use specific actions within that feature

If either check fails, the feature is inaccessible. Feature flags are the "master switch"; RBAC is the "granular control."

### Database Schema

#### `feature_flags` Table

| Column | Type | Description |
|--------|------|-------------|
| `slug` | text (PK) | Unique identifier (e.g., "pipeline", "estimates") |
| `label` | text | Human-readable name |
| `description` | text | Feature description |
| `enabled` | boolean | Master on/off switch |
| `routes` | text[] | Route paths gated by this flag |
| `permissions` | text[] | RBAC permissions gated by this flag |
| `created_at` | timestamptz | |
| `updated_at` | timestamptz | |

#### `feature_flag_overrides` Table

| Column | Type | Description |
|--------|------|-------------|
| `id` | uuid (PK) | |
| `flag_slug` | text (FK) | References feature_flags.slug |
| `user_id` | uuid (FK) | References users.id |
| `created_at` | timestamptz | |

Constraint: UNIQUE(flag_slug, user_id)

### Current Feature Flags

| Slug | Label | Routes | Permissions Gated | Default |
|------|-------|--------|-------------------|---------|
| `pipeline` | Pipeline CRM | /pipeline | pipeline.view, pipeline.manage, pipeline.configure_stages | Enabled |
| `accounting` | Accounting | /accounting | accounting.view, accounting.manage_connections | Enabled |
| `estimates` | Estimates | /estimates | estimates.view, estimates.create, estimates.edit, estimates.delete, estimates.send, estimates.convert | Enabled |
| `invoices` | Invoices | /invoices | invoices.view, invoices.create, invoices.edit, invoices.delete, invoices.send, invoices.record_payment, invoices.void | Enabled |
| `products` | Products & Services | /products | products.view, products.manage | Enabled |
| `inventory` | Inventory | /inventory | inventory.view, inventory.manage, inventory.import | Enabled |
| `portal` | Client Portal | /inbox (portal channel) | portal.view, portal.manage_branding | Enabled |
| `ai_email_review` | AI Email Review | /settings/integrations | email.configure_ai | Disabled |
| `ai_email_memory` | AI Email Memory | /settings/integrations | email.configure_ai | Disabled |

### Client-Side Implementation

**Zustand Store** (`feature-flags-store.ts`):
- `canAccessFeature(slug)` — true if flag enabled OR user has override
- `isPermissionUnlocked(permission)` — true if permission's flag is enabled (or permission not gated)
- `isRouteUnlocked(pathname)` — true if route's flag is enabled (or route not gated)
- `fetchFlags(userId)` — fetches from `/api/feature-flags?userId=...`

**Fail-Closed Behavior**: If API fails after 1 retry, all gated features default to DISABLED.

**Static Fallback** (`feature-flag-definitions.ts`): Hardcoded route/permission maps used when API unreachable.

### Enforcement Layers

1. **Sidebar** (`sidebar.tsx`): Filters nav items by `isPermissionUnlocked(permission)` then `can(permission)`. Both must pass.
2. **Route layout** (`layout.tsx`): Checks `isRouteUnlocked(pathname)` and `can(requiredPermission)`. Shows 404 if either fails.
3. **Widget tray** (`widget-tray.tsx`): Filters available widgets by permission (indirectly gated by flags).

### Admin Management

Managed at `/admin/feature-releases`:
- Toggle flag enabled/disabled
- Edit routes and permissions a flag gates
- Grant/revoke per-user overrides (early access)
- Create new flags
- Search users by name/email

**API Endpoints:**
- `GET /api/feature-flags?userId={uuid}` — Client: fetch flags
- `GET /api/admin/feature-flags` — Admin: list all with override counts
- `PATCH /api/admin/feature-flags` — Admin: update flag
- `POST /api/admin/feature-flags` — Admin: create flag
- `GET /api/admin/feature-flags/overrides?flagSlug={slug}` — Admin: list overrides
- `POST /api/admin/feature-flags/overrides` — Admin: grant override
- `DELETE /api/admin/feature-flags/overrides` — Admin: revoke override

### Adding a New Feature Flag

1. Insert row into `feature_flags` with slug, routes, permissions
2. Update static fallback in `feature-flag-definitions.ts`
3. Ensure sidebar nav item has `permission` field matching a gated permission
4. Verify `ROUTE_PERMISSIONS` in `layout.tsx` maps the route correctly
5. Test: disable flag → route returns 404, sidebar hides item, widgets filtered

### Admin Feature Overrides

Some features require a **dual gate**: the product-level feature flag must be enabled AND an OPS admin must explicitly grant access to a specific company. This pattern is distinct from the existing user-level overrides (`feature_flag_overrides`) which grant individual users early access.

**Why this pattern exists:** AI-powered features (email review, memory system) have ongoing per-company costs. The product-level flag controls whether the feature exists in the product at all, while the admin override controls which companies have been granted access by OPS admin. Both must be true for the feature to be active.

**Database table:** `admin_feature_overrides` (see `03_DATA_ARCHITECTURE.md` for schema)

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

**Code-level gate check:**

```typescript
async function isAIFeatureEnabled(
  companyId: string,
  feature: 'ai_email_review' | 'ai_email_memory'
): Promise<boolean> {
  const productEnabled = await canAccessFeature(feature)  // existing feature flag system
  const adminEnabled = await checkAdminOverride(companyId, feature)  // admin_feature_overrides table
  return productEnabled && adminEnabled
}
```

**Current features using this pattern:**

| Feature Key | Description | Admin Panel Location |
|---|---|---|
| `ai_email_review` | Ongoing AI classification, stage evaluation, win/loss detection, AI duplicate detection | Company detail → AI Email Review toggle |
| `ai_email_memory` | Memory accumulation, draft suggestions, auto-draft | Company detail → AI Memory toggle |

**Admin panel controls** (per-company, at `/admin/companies/{id}`):

```
Company: {name}
├── AI Email Review:  [Enabled] / Disabled
├── AI Memory:        [Enabled] / Disabled
├── Memory Stats:
│   ├── Emails analyzed: {N}
│   ├── Confidence: {0.0-1.0}
│   └── Last updated: {timestamp}
├── Memory Actions:
│   ├── [View Memory Document]
│   ├── [Reset Memory]
│   └── [Export Memory]
└── Cost Tracking:
    ├── AI tokens this month: {N}
    ├── Estimated monthly cost: ${N}
    └── [View Usage History]
```

### Email Integration Permissions

New permission module for the email integration, registered in the existing permission system (`permissions.ts`):

| Permission | Scopes | Description |
|---|---|---|
| `email.connect` | `["all"]` | Connect/disconnect email accounts (Gmail, Microsoft 365) |
| `email.view` | `["all", "own"]` | View imported leads and email activities |
| `email.manage` | `["all"]` | Run wizard, edit sync profile, trigger manual sync |
| `email.configure_ai` | `["all"]` | Toggle AI features on connection (requires admin override to be enabled) |

**Preset Role Grants:**

| Permission | Admin | Owner | Office | Operator | Crew |
|---|---|---|---|---|---|
| email.connect | all | all | all | — | — |
| email.view | all | all | all | all | — |
| email.manage | all | all | all | — | — |
| email.configure_ai | all | all | — | — | — |

---

## 18. Intel Galaxy Visualization (Web)

### Overview

Full-bleed 3D galaxy visualization at `/intel` — the visual manifestation of Phase C (OPS AI intelligence layer). Renders every entity in the user's business network as an interactive orbital constellation.

**Route:** `/intel` (sidebar: "Intel" with Radar icon, visible to all users)
**Feature gate:** `phase_c` (renamed from `ai_email_memory`)
**Tech:** React Three Fiber (lazy loaded, ~150KB gzip not in critical path)

### Data Sources

The galaxy merges Phase C entities with live OPS data:

| Source | Gate | Entities |
|--------|------|----------|
| `graph_entities` | Phase C | People, companies, services, materials from email |
| `agent_knowledge_graph` | Phase C | Relationship edges between entities |
| `agent_writing_profiles` | Phase C | Voice/tone profile nodes |
| `projects` | Always | Active projects |
| `clients` | Always | Client records |
| `invoices` | Always | Financial documents |
| `estimates` | Always | Financial documents |

### API Endpoints

**`GET /api/intel/graph?companyId=X`** — unified graph (Phase C + live OPS data). Returns `{ entities, edges, voiceProfiles, stats, phaseCEnabled }`.

**`GET /api/intel/entity/[entityId]?type=X&companyId=X`** — entity detail for drill-down. Returns `{ entity, facts, edges, details }`.

### Cluster Architecture

| Cluster | Color | Orbital Radius | Contents |
|---------|-------|---------------|----------|
| Voice | `#597794` (accent) | 3 | Writing profile nodes per relationship type |
| Internal | `#8E8E93` | 5 | Team members, employees |
| Clients | `#8195B5` | 8 | Client records + email contacts |
| Projects | `#B58289` | 8 | Active projects |
| Vendors | `#C4A868` | 11 | Vendor entities from email |
| Subtrades | `#9DB582` | 11 | Subtrade entities from email |
| Financials | `#BCBCBC` | Orbits parent projects | Invoices, estimates |

### 3D Gating

Without Phase C: galaxy renders in 2D only. OrbitControls rotation disabled. Attempted rotation triggers snap-back + frosted-glass prompt: "Unlock the ██████ dimension. [ Request Early Access ]"

With Phase C: full 3D orbit unlocked. Nodes gain z-depth positioning on first rotation.

### Interaction Model

- **Tier 1 (hover):** Borderless label near node — name + type. Dark-halo legibility treatment.
- **Tier 2 (click):** Borderless inline info — entity-type-specific summary. `[ MORE ]` button.
- **Tier 3 (expand):** Frosted-glass card with full detail from drill-down API (facts, edges, timeline).
- **Edges:** Proximity-revealed — invisible by default, fade in near camera or selected node.

### Activation Animation

New entities (created since `intel_last_viewed_at` in localStorage) trigger a 3-beat ignition sequence:
1. Existing nodes dim to 30%, new nodes brighten by cluster (staggered)
2. Edges between new nodes draw in
3. Existing nodes restore, galaxy settles

Phase C toast: "New intel available" → "View Intel" CTA → navigates to `/intel`.

### Redacted Copy

~50% of Phase C-related copy is redacted with `████` bars. Bars are `#1a1a1a` background with `box-shadow: 0 0 8px rgba(89,119,148,0.3)` accent glow. Redacted words are the capability words — structure stays readable. Builds intrigue for ungated users.

### Key Files

| File | Purpose |
|------|---------|
| `src/app/(dashboard)/intel/page.tsx` | Page route |
| `src/components/intel/galaxy-scene.tsx` | Main R3F Canvas + scene assembly |
| `src/components/intel/galaxy-layout.ts` | Orbital position calculator |
| `src/components/intel/galaxy-nodes.tsx` | Instanced point-sprite nodes |
| `src/components/intel/galaxy-edges.tsx` | Proximity-revealed edges |
| `src/components/intel/galaxy-center.tsx` | Self/company center node |
| `src/components/intel/galaxy-starfield.tsx` | Ambient background stars |
| `src/components/intel/hud/*.tsx` | Floating HUD overlays |
| `src/components/intel/node-info.tsx` | Tier 2/3 drill-down panel |
| `src/stores/intel-store.ts` | Zustand state |
| `src/lib/hooks/use-intel-graph.ts` | TanStack Query hook |
| `src/app/api/intel/graph/route.ts` | Graph API |
| `src/app/api/intel/entity/[entityId]/route.ts` | Entity detail API |

---

## 19. In-App Email System (Web)

### Overview

The OPS web app provides a full in-app email client so users never need to open Gmail/M365. Built across 5 sprints (completed 2026-03-19). Connects to the email pipeline integration documented in `10_JOB_LIFECYCLE_AND_DATA_RELATIONSHIPS.md` §10 for sync, pattern detection, and AI classification.

### Unified Inbox View (`/inbox`)

Three-panel layout merging email threads and client portal messages into a single conversation view. Replaces the old two-tab (Pipeline/All Mail) and separate `/portal-inbox` page.

**Architecture:**
- Left panel (320px fixed): Conversation list with search, channel badges (EMAIL/PORTAL/UNMATCHED)
- Center panel (flex): Message thread with iMessage-style bubbles, floating toolbar filter
- Right panel (320px, collapsible): Client context — contact info, projects, estimates, invoices

**Data Sources (merged into `InboxConversation`):**

| Source | Data | Grouping |
|--------|------|----------|
| `activities` table | Email threads grouped by `email_thread_id`, linked to opportunities via `opportunity_id` | By `client_id` (from opportunity) |
| `portal_messages` table | Client portal messages | By `client_id` |
| Email provider API (Gmail/M365) | Full email thread bodies via `provider.fetchThread(threadId)` | By thread ID |

**Conversation Normalization (`useUnifiedConversations`):**
- Groups pipeline threads by `clientId` (from the linked opportunity's `client_id`)
- Merges portal conversations by matching `clientId`
- Unmatched threads (no `clientId`) grouped by sender email address
- Each `InboxConversation` carries its `emailThreadIds[]` — single data source, no desync
- 30-second polling interval

**Thread View (`useUnifiedThread`):**
- Fetches email content from provider API (`/api/integrations/email/inbox?threadId=...`) — returns actual email bodies, not activity table stubs
- Falls back to `activities` table if provider is unavailable
- Fetches portal messages from `portal_messages` table for matched clients
- Channel filter toolbar (ALL/EMAIL/PORTAL) floats as overlay on the message area
- Messages sorted chronologically with date dividers and channel dividers
- Direction detection: compares sender domain against current user's domain

**Unread Count:**
- Combined email + portal unread count on sidebar "Inbox" badge
- Email: from `InboxService.getUnreadCount()` (activities table)
- Portal: from `portal_messages` where `sender_type = 'client'` and `read_at IS NULL`
- 60-second polling interval

**Removed:**
- `/portal-inbox` page (deleted — portal messages now in unified inbox)
- Separate "Pipeline" and "All Mail" tabs (replaced by channel filter toolbar)
- `pipeline-thread-list.tsx`, `all-mail-list.tsx`, `portal-inbox.tsx` components (deleted)

### Compose Modal

**Trigger Points:**
- Pipeline card action menu
- Inbox thread reply button
- FAB (Floating Action Button)
- Direct compose from inbox

**Modes:**

| Mode | Behavior |
|------|----------|
| **New email** | Blank compose — all fields empty |
| **Reply** | Pre-fills `to`, `subject` (with "Re:" prefix), quoted original message, `threadId`, `inReplyTo` header |

**Sender Dropdown:**
- Resolves available senders from `email_connections` table
- Supports multiple connected accounts (e.g., personal Gmail + company M365)

**Fields:**
- **From** — sender dropdown
- **To** — email address input
- **CC** — collapsible, hidden by default
- **Subject** — text input
- **Body** — markdown-capable text area

**Markdown Toolbar:**
- Bold: `**text**`
- Italic: `*text*`
- Link: `[text](url)`

**Send Flow:**
- Body stored as markdown during composition
- Converted to HTML at send time via `markdownToEmailHtml()`
- Sent through the connected provider's API (Gmail or M365)

### Email Templates

**Table:** `email_templates` (company-scoped, RLS-protected)

**Categories:**
| Category Slug | Display Name |
|---------------|-------------|
| `follow_up` | Follow Up |
| `scheduling` | Scheduling |
| `estimate` | Estimate |
| `invoice` | Invoice |
| `introduction` | Introduction |
| `general` | General |

**Merge Fields:**

| Field | Resolved From |
|-------|--------------|
| `{{client_name}}` | Linked opportunity's client name |
| `{{project_title}}` | Linked opportunity's project title |
| `{{company_name}}` | Current user's company name |

**Behavior:**
- Template picker in compose modal — dropdown grouped by category
- If body is non-empty when selecting a template, confirmation prompt before replacing
- Variables resolved at compose time from linked opportunity/client context
- Unresolvable variables (e.g., composing without opportunity context) highlighted in amber with a warning banner

**Management:**
- CRUD via Settings → Email Templates tab

### AI Email Drafting (3-Phase Progression)

#### Phase 1 — Profile Building

`WritingProfileService` captures tone, style, greeting, and closing patterns from the user's outbound emails. After 5+ analyzed emails, AI drafting becomes available. Profile data stored in `agent_writing_profiles` table.

#### Phase 2 — AI Draft + Human Review

**Trigger:** "AI Draft" button (Sparkles icon) in compose modal.

**Context Assembly:**
1. Writing profile (tone, greeting, closing patterns)
2. Thread messages (last 20 in conversation)
3. Opportunity `ai_summary` (if linked)
4. Memory facts from `agent_memories` (if Phase C enabled)

**Model:** `gpt-5.4-mini` via `OPENAI_API_KEY_DRAFTING`

**Output:** Markdown draft matching the user's voice and writing style.

**Edit Tracking:**
- Word-level Levenshtein diff records original AI draft vs user's final version in `ai_draft_history`
- Tracked change categories: greeting changes, closing changes, tone shifts
- Writing profile learning: 3+ consistent changes to the same pattern automatically updates the profile

**User Metrics:**
- Approval rate (% of drafts sent without changes)
- Common change patterns
- Declining edit frequency over time (learning indicator)

#### Phase 3 — Auto-Send (Feature-Gated)

**Feature gate:** `ai_auto_send`

**Activation:** Suggested when approval rate reaches 95% over 20+ drafts ("you only changed 1 of the last 20").

**When enabled:**
1. New inbound email arrives on a linked thread
2. AI draft generated automatically
3. Draft held for randomized delay before sending

**Delay Configuration:**
- Configurable min/max (default 30-60 minutes)
- Randomized within range to avoid suspicious patterns
- Business hours enforcement: default 8am-6pm in user's timezone, configurable

**Cron:** `/api/cron/auto-send`
- Runs every 5 minutes
- Processes up to 50 pending auto-sends per cycle
- Max 3 retries for failed sends, then permanently marked as failed

**User Controls:**
- Cancel pending auto-sends from inbox UI
- Disable auto-send at any time (reverts to Phase 2 behavior)

### Stage Manual Override System

**Column:** `opportunities.stage_manually_set` (BOOLEAN, default `false`)

**Set to `true`:** When user drags a pipeline card to a new stage on the Kanban board.

**Effect:** When `true`, both the deterministic `StageEvaluator` (correspondence-count rules) AND the AI `evaluateStagesWithSummary()` skip stage changes for this opportunity. The user's manual placement is respected.

**Cleared to `false`:** When a new inbound email arrives. Specifically, `processInboundEmail()` → `updateCorrespondenceCounts()` detects `direction = inbound` and clears the flag, allowing automated stage evaluation to resume.

**Exception:** Terminal flag notifications (`likely_won` / `likely_lost`) are always sent regardless of the manual override flag — the user should always know about win/loss signals even if they've manually placed the opportunity.

### Sync Engine Hardening (2026-03-19)

Improvements to the email sync engine reliability and data completeness:

**Subscription Gating:**
- Cron batch-fetches companies, filters by `getSubscriptionInfo().isActive` before running sync
- Manual sync checks subscription status, returns 403 if inactive
- Webhook handlers (Gmail Pub/Sub, M365 Change Notifications) pass `CRON_SECRET` Bearer token when calling manual-sync endpoint

**Activity Data Enrichment:**
- Activities now store: `body_text` (full email body), `to_emails`, `cc_emails`, `has_attachments`, `attachment_count`

**Timestamp Validation:**
- `last_inbound_at` / `last_outbound_at` on opportunities only updated if the email date is newer than the existing value
- `stage_entered_at` set on ALL stage changes (count-based, AI eval, stale sweep)
- `last_activity_at` uses the email's actual date, not the sync timestamp

**Sent Safety Net:**
- Prevents duplicate thread link constraint violations
- Processes CC recipients on outbound emails

**AI Evaluation Optimization:**
- `evaluateStagesWithSummary()` returns both stage and 1-2 sentence summary in a single API call
- Summary written to `opportunities.ai_summary`

**Stale Lead Sweep:**
- Runs on every cron cycle
- Respects `stage_manually_set` flag (skips manually placed opportunities)

### OpenAI API Key Separation

Three separate API keys for granular cost tracking in the OpenAI dashboard:

| Key | Env Variable | Purpose |
|-----|-------------|---------|
| Import | `OPENAI_API_KEY_IMPORT` | Initial inbox scan (Phase A triage + Phase B extraction) |
| Sync | `OPENAI_API_KEY_SYNC` | Ongoing sync (stage evaluation + summary, memory extraction, writing profiles) |
| Drafting | `OPENAI_API_KEY_DRAFTING` | AI email draft generation |

**Factory:** `src/lib/api/services/openai-clients.ts`
- Exports: `getImportOpenAI()`, `getSyncOpenAI()`, `getDraftingOpenAI()`
- All fall back to `OPENAI_API_KEY` if the specific key is not set

---

## 20. Mobile Wizard System

Cross-platform reference for the in-app guided wizard system. Both iOS and Android implementations conform to this dock.

**Design spec:** `docs/superpowers/specs/2026-03-10-in-app-wizard-system-design.md`

### Principles

- **Real data, not demo data.** Wizards guide users through actual creation flows.
- **Lightweight.** Persistent instruction bar at bottom — no overlays, spotlights, or dimming.
- **Deferrable.** Every wizard supports "Maybe Later" and "Don't show again."
- **Offline-first.** All trigger conditions and step detection use local state only.

### Role & Permission Gating

Three wizard-access tiers mapped from five user roles:

| UserRole | Wizard Tier |
|---|---|
| `.admin`, `.owner` | Admin |
| `.office`, `.operator` | Office |
| `.crew`, `.unassigned` | Field |

**Tier visibility:**
- **Field:** Project Lifecycle, Scheduling, Job Board, Navigation, Photo Documentation, Project Notes, Settings
- **Office:** All field + Team Management, Inventory, Expenses
- **Admin:** All + Crew Location, Pipeline, Estimates, Invoices, Permissions

Wizards with `requiredPermission` are hidden entirely if the user lacks that permission, regardless of tier.

### Wizard Inventory

#### Sequenced (prompted proactively)

| # | wizardId | Display Name | Trigger | Min Tier | Permission | Status |
|---|----------|-------------|---------|----------|------------|--------|
| 1 | `project_lifecycle` | PROJECT LIFECYCLE | First session, 0 projects | Field | — | **Built** |

#### Contextual (triggered on first feature encounter)

| # | wizardId | Display Name | Trigger | Min Tier | Permission | Status |
|---|----------|-------------|---------|----------|------------|--------|
| 2 | `scheduling_calendar` | SCHEDULING & CALENDAR | First Calendar tab visit | Field | — | **Built** |
| 3 | `job_board` | JOB BOARD | First Job Board tab visit | Field | — | **Built** |
| 4 | `team_management` | TEAM MANAGEMENT | First team settings visit | Office | — | **Built** |
| 5 | `navigation_directions` | NAVIGATION & DIRECTIONS | First "Get Directions" tap | Field | — | Not built |
| 6+7 | `documentation` | DOCUMENTATION & DETAILS | First project detail visit | Field | — | **Built** |
| 8 | `crew_location` | CREW LOCATION TRACKING | First map view | Admin | `crew_location.view` | Not built |
| 9 | `inventory_setup` | INVENTORY SETUP | First Inventory tab visit, 0 items | Office | `inventory.manage` | **Built** |
| 10 | `pipeline_crm` | PIPELINE / CRM | First Pipeline tab visit | Admin | `pipeline.view` | Not built |
| 11 | `estimates` | ESTIMATES | First estimate creation | Admin | `estimates.create` | Not built |
| 12 | `invoices` | INVOICES | First invoice action | Admin | `estimates.create` | Not built |
| 13 | `expenses_accounting` | EXPENSES & ACCOUNTING | First expense visit | Office | `expenses.create` | Not built |
| 14 | `permissions_roles` | PERMISSIONS & ROLES | First permissions settings visit | Admin | `settings.company` | **Built** |
| 15 | `settings_security` | SETTINGS & SECURITY | First settings visit | Field | — | **Built** |

#### Data-Condition (triggered by accumulated state)

| # | wizardId | Display Name | Trigger | Min Tier | Permission | Status |
|---|----------|-------------|---------|----------|------------|--------|
| 16 | `task_review` | TASK REVIEW | 5+ overdue tasks | Field | `tasks.view` | **Built** |
| 17 | `payment_review` | PAYMENT REVIEW | 5+ completed projects | Office | `finances.view` | **Built** |

### Built Wizard Definitions

#### 1. Project Lifecycle (`project_lifecycle`)

**Type:** Sequenced | **Icon:** `hammer.circle` | **Tier:** Field | **Banner:** "Want help creating your first project?"

| Step | id | Instruction | Target Screen | Notification | Skippable |
|------|-----|------------|---------------|-------------|-----------|
| 1 | `open_fab` | TAP THE + BUTTON | JobBoard | `WizardFABTapped` | Yes |
| 2 | `select_create_client` | TAP "CREATE CLIENT" | FABMenu | `WizardCreateClientTapped` | Yes |
| 3 | `fill_client_name` | ENTER THE CLIENT'S NAME | ClientForm | `WizardClientSaved` | Yes |
| 4 | `open_fab_project` | TAP THE + BUTTON AGAIN | JobBoard | `WizardFABTapped` | Yes |
| 5 | `select_create_project` | TAP "CREATE PROJECT" | FABMenu | `WizardCreateProjectTapped` | Yes |
| 6 | `select_client` | SELECT YOUR CLIENT | ProjectForm | `WizardProjectClientSelected` | Yes |
| 7 | `enter_project_name` | ENTER A PROJECT NAME | ProjectForm | `WizardProjectNameEntered` | Yes |
| 8 | `add_task` | ADD A TASK | ProjectForm | `WizardTaskAdded` | Yes |
| 9 | `assign_date` | SET A DATE FOR THE TASK | TaskForm | `WizardTaskDateSet` | Yes |
| 10 | `assign_crew` | ASSIGN A CREW MEMBER | TaskForm | `WizardTaskCrewAssigned` | Yes |
| 11 | `save_project` | SAVE YOUR PROJECT | ProjectForm | `WizardProjectSaved` | Yes |
| 12 | `view_on_board` | FIND YOUR PROJECT ON THE BOARD | JobBoard | `WizardProjectStatusChanged` | Yes |

**Notification sources (iOS):**
| Notification | Posted From |
|---|---|
| `WizardFABTapped` | `FloatingActionMenu.swift` — FAB button tap |
| `WizardCreateClientTapped` | `FloatingActionMenu.swift` — "New Client" menu item |
| `WizardClientSaved` | `ClientSheet.swift` — after client saved |
| `WizardCreateProjectTapped` | `FloatingActionMenu.swift` — "New Project" menu item |
| `WizardProjectClientSelected` | `ProjectFormSheet.swift` — client row tapped |
| `WizardProjectNameEntered` | `ProjectFormSheet.swift` — title onChange (empty → non-empty) |
| `WizardTaskAdded` | `ProjectFormSheet.swift` — new task saved from inline TaskFormSheet |
| `WizardTaskDateSet` | `TaskFormSheet.swift` — scheduler confirmed |
| `WizardTaskCrewAssigned` | `TaskFormSheet.swift` — selectedTeamMemberIds onChange (empty → non-empty) |
| `WizardProjectSaved` | `ProjectFormSheet.swift` — project create success |
| `WizardProjectStatusChanged` | `UniversalJobBoardCard.swift` — status swipe success |

#### 9. Inventory Setup (`inventory_setup`)

**Type:** Contextual | **Icon:** `shippingbox.fill` | **Tier:** Office | **Permission:** `inventory.manage` | **Banner:** "Let's set up your inventory"

| Step | id | Instruction | Notification | Skippable |
|------|-----|------------|-------------|-----------|
| 1 | `choose_method` | ADD YOUR ITEMS | — (coordinator-driven) | Yes |
| 2 | `add_items` | ADD YOUR ITEMS | — (coordinator-driven) | Yes |
| 3 | `set_thresholds` | SET STOCK ALERTS | — (coordinator-driven) | Yes |
| 4 | `take_snapshot` | TAKE FIRST SNAPSHOT | — (coordinator-driven) | Yes |

**Note:** Inventory wizard uses a dedicated `InventoryWizardCoordinator` that calls `wizardStateManager.completeCurrentStep()` / `skipCurrentStep()` directly instead of NotificationCenter. Triggered from `InventoryView.checkInventoryWizard()` when the user has `inventory.manage` permission and 0 company items.

#### 16. Task Review (`task_review`)

**Type:** Data-condition | **Icon:** `rectangle.stack.fill` | **Tier:** Field | **Permission:** `tasks.view` | **Banner:** "You have overdue tasks — want a quick walkthrough of task review?"

| Step | id | Instruction | Notification | Skippable |
|------|-----|------------|-------------|-----------|
| 1 | `open_task_review` | OPEN TASK REVIEW | `WizardTaskReviewOpened` | No |
| 2 | `demo_swipe_right` | SWIPE RIGHT → COMPLETE | `WizardTaskSwipedRight` | Yes |
| 3 | `demo_swipe_left` | SWIPE LEFT → SKIP | `WizardTaskSwipedLeft` | Yes |
| 4 | `demo_swipe_up` | SWIPE UP → RESCHEDULE | `WizardTaskSwipedUp` | Yes |
| 5 | `free_review` | YOU'RE ALL SET — KEEP REVIEWING | `WizardTaskReviewDismissed` | Yes |

**Notification sources (iOS):**
| Notification | Posted From |
|---|---|
| `WizardTaskReviewOpened` | `TaskCompletionReviewView.swift` — onAppear |
| `WizardTaskSwipedRight` | `TaskCompletionReviewView.swift` — handleSwipe `.right` |
| `WizardTaskSwipedLeft` | `TaskCompletionReviewView.swift` — handleSwipe `.left` |
| `WizardTaskSwipedUp` | `TaskCompletionReviewView.swift` — handleSwipe `.up` |
| `WizardTaskReviewDismissed` | `TaskCompletionReviewView.swift` — onDisappear |

#### 17. Payment Review (`payment_review`)

**Type:** Data-condition | **Icon:** `creditcard.circle` | **Tier:** Office | **Permission:** `finances.view` | **Banner:** "You have completed projects to review — want a quick walkthrough?"

| Step | id | Instruction | Notification | Skippable |
|------|-----|------------|-------------|-----------|
| 1 | `open_payment_review` | OPEN PAYMENT REVIEW | `WizardPaymentReviewOpened` | No |
| 2 | `demo_swipe_right` | SWIPE RIGHT → CLOSE PROJECT | `WizardProjectSwipedRight` | Yes |
| 3 | `demo_swipe_left` | SWIPE LEFT → SKIP | `WizardProjectSwipedLeft` | Yes |
| 4 | `demo_swipe_up` | SWIPE UP → SEND REMINDER | `WizardProjectSwipedUp` | Yes |
| 5 | `free_review` | YOU'RE ALL SET — KEEP REVIEWING | `WizardPaymentReviewDismissed` | Yes |

**Notification sources (iOS):**
| Notification | Posted From |
|---|---|
| `WizardPaymentReviewOpened` | `ProjectPaymentReviewView.swift` — onAppear |
| `WizardProjectSwipedRight` | `ProjectPaymentReviewView.swift` — handleSwipe `.right` |
| `WizardProjectSwipedLeft` | `ProjectPaymentReviewView.swift` — handleSwipe `.left` |
| `WizardProjectSwipedUp` | `ProjectPaymentReviewView.swift` — handleSwipe `.up` |
| `WizardPaymentReviewDismissed` | `ProjectPaymentReviewView.swift` — onDisappear |

#### 2. Scheduling & Calendar (`scheduling_calendar`)

**Type:** Contextual | **Icon:** `calendar` | **Tier:** Field | **Banner:** "Want a quick tour of your schedule?"

| Step | id | Instruction | Notification | Skippable |
|------|-----|------------|-------------|-----------|
| 1 | `scroll_week` | SWIPE TO BROWSE THE WEEK | `WizardCalendarWeekScrolled` | Yes |
| 2 | `tap_day` | TAP A DAY TO SEE ITS TASKS | `WizardCalendarDayTapped` | Yes |
| 3 | `toggle_month` | SWITCH TO MONTH VIEW | `WizardCalendarMonthToggled` | Yes |
| 4 | `explore_month` | EXPLORE THE MONTH | `WizardCalendarMonthExplored` | Yes |
| 5 | `tap_task` | TAP A TASK FOR DETAILS | `WizardCalendarTaskTapped` | Yes |

**Notification sources (iOS):**
| Notification | Posted From |
|---|---|
| `WizardCalendarWeekScrolled` | `ScheduleView.swift` — onReceive CalendarWeekViewScrolled |
| `WizardCalendarDayTapped` | `CalendarDaySelector.swift` — day cell onTap |
| `WizardCalendarMonthToggled` | `ScheduleView.swift` — onChange viewMode to .month |
| `WizardCalendarMonthExplored` | `ScheduleView.swift` — onReceive CalendarMonthViewScrolled/Pinched |
| `WizardCalendarTaskTapped` | `DayCanvasView.swift` — task card tap (ShowCalendarTaskDetails) |

#### 3. Job Board (`job_board`)

**Type:** Contextual | **Icon:** `list.clipboard` | **Tier:** Field | **Banner:** "Want a quick tour of the job board?"

| Step | id | Instruction | Notification | Skippable |
|------|-----|------------|-------------|-----------|
| 1 | `browse_projects` | SCROLL THROUGH YOUR PROJECTS | `WizardJobBoardScrolled` | Yes |
| 2 | `open_filters` | TAP THE FILTER BUTTON | `WizardJobBoardFilterOpened` | Yes |
| 3 | `swipe_status` | SWIPE A PROJECT CARD RIGHT | `WizardProjectStatusChanged` | Yes |
| 4 | `tap_project` | TAP A PROJECT TO OPEN IT | `WizardJobBoardProjectTapped` | Yes |
| 5 | `view_closed` | CHECK YOUR CLOSED PROJECTS | `WizardJobBoardClosedViewed` | Yes |

**Notification sources (iOS):**
| Notification | Posted From |
|---|---|
| `WizardJobBoardScrolled` | `JobBoardProjectListView.swift` — onAppear |
| `WizardJobBoardFilterOpened` | `JobBoardView.swift` — filter button action |
| `WizardProjectStatusChanged` | `UniversalJobBoardCard.swift` — status swipe success |
| `WizardJobBoardProjectTapped` | `ProjectDetailsView.swift` — handleOnAppear |
| `WizardJobBoardClosedViewed` | `JobBoardProjectListView.swift` — closed section button |

#### 6+7. Documentation & Details (`documentation`)

**Type:** Contextual | **Icon:** `doc.text.image` | **Tier:** Field | **Banner:** "Want to learn how to document your jobs?"

| Step | id | Instruction | Notification | Skippable |
|------|-----|------------|-------------|-----------|
| 1 | `view_activity` | VIEW THE ACTIVITY TAB | `WizardActivityTabViewed` | Yes |
| 2 | `view_details` | SWITCH TO THE DETAILS TAB | `WizardDetailsTabViewed` | Yes |
| 3 | `write_note` | WRITE A NOTE | `WizardNotePosted` | Yes |
| 4 | `capture_photo` | CAPTURE A PHOTO | `WizardPhotoCaptured` | Yes |
| 5 | `annotate_photo` | ANNOTATE A PHOTO | `WizardPhotoAnnotated` | Yes |

**Notification sources (iOS):**
| Notification | Posted From |
|---|---|
| `WizardActivityTabViewed` | `ActivityTabView.swift` — onAppear |
| `WizardDetailsTabViewed` | `DetailsTabView.swift` — onAppear |
| `WizardNotePosted` | `ProjectNotesViewModel.swift` — postNote() optimistic insert |
| `WizardPhotoCaptured` | `ProjectDetailsView.swift` — CameraBatchView completion |
| `WizardPhotoAnnotated` | `PhotoAnnotationView.swift` — saveAnnotation() |

#### 4. Team Management (`team_management`)

**Type:** Contextual | **Icon:** `person.3.fill` | **Tier:** Office | **Banner:** "Want help setting up your team?"

| Step | id | Instruction | Notification | Skippable |
|------|-----|------------|-------------|-----------|
| 1 | `view_team` | BROWSE YOUR TEAM | `WizardTeamListViewed` | Yes |
| 2 | `view_company_code` | FIND YOUR COMPANY CODE | `WizardCompanyCodeViewed` | Yes |
| 3 | `send_invite` | INVITE A TEAM MEMBER | `WizardTeamInviteSent` | Yes |
| 4 | `assign_role` | ASSIGN A ROLE | `WizardTeamRoleAssigned` | Yes |

**Notification sources (iOS):**
| Notification | Posted From |
|---|---|
| `WizardTeamListViewed` | `ManageTeamView.swift` — onAppear |
| `WizardCompanyCodeViewed` | `ManageTeamView.swift` — invite sheet onAppear |
| `WizardTeamInviteSent` | `ManageTeamView.swift` — after sendInvitations() |
| `WizardTeamRoleAssigned` | `ManageTeamView.swift` — after updateMemberRole() |

#### 15. Settings & Security (`settings_security`)

**Type:** Contextual | **Icon:** `gearshape.fill` | **Tier:** Field | **Banner:** "Want to set up your profile and security?"

| Step | id | Instruction | Notification | Skippable |
|------|-----|------------|-------------|-----------|
| 1 | `open_profile` | OPEN YOUR PROFILE | `WizardProfileViewed` | Yes |
| 2 | `open_company` | VIEW COMPANY SETTINGS | `WizardCompanyInfoViewed` | Yes |
| 3 | `enable_pin` | SET UP A PIN | `WizardPINEnabled` | Yes |
| 4 | `configure_notifications` | CONFIGURE NOTIFICATIONS | `WizardNotificationsConfigured` | Yes |

**Notification sources (iOS):**
| Notification | Posted From |
|---|---|
| `WizardProfileViewed` | `ProfileSettingsView.swift` — onAppear |
| `WizardCompanyInfoViewed` | `OrganizationDetailsView.swift` — onAppear |
| `WizardPINEnabled` | `SecuritySettingsView.swift` — PINSetupSheet after PIN set |
| `WizardNotificationsConfigured` | `NotificationSettingsView.swift` — onAppear |

#### 14. Permissions & Roles (`permissions_roles`)

**Type:** Contextual | **Icon:** `lock.shield` | **Tier:** Admin | **Permission:** `settings.company` | **Banner:** "Want a walkthrough of permissions?"

| Step | id | Instruction | Notification | Skippable |
|------|-----|------------|-------------|-----------|
| 1 | `view_roles` | BROWSE THE ROLES | `WizardRolesTabViewed` | Yes |
| 2 | `view_role_detail` | TAP A ROLE TO SEE ITS PERMISSIONS | `WizardRoleDetailViewed` | Yes |
| 3 | `switch_to_team` | SWITCH TO THE TEAM TAB | `WizardTeamPermissionsViewed` | Yes |
| 4 | `view_member_overrides` | TAP A TEAM MEMBER | `WizardMemberOverrideViewed` | Yes |

**Notification sources (iOS):**
| Notification | Posted From |
|---|---|
| `WizardRolesTabViewed` | `PermissionsManagementView.swift` — onAppear |
| `WizardRoleDetailViewed` | `RoleDetailView.swift` — onAppear |
| `WizardTeamPermissionsViewed` | `PermissionsManagementView.swift` — onChange tab to .team |
| `WizardMemberOverrideViewed` | `UserPermissionDetailView.swift` — onAppear |

### Trigger Types

| Type | Evaluation Method | Called From |
|------|------------------|------------|
| **Sequenced** | `WizardTriggerService.evaluateSequencedWizards(projectCount:)` | `MainTabView.onAppear` (4s delay) |
| **Contextual** | `WizardTriggerService.evaluateTrigger(for:context:)` | Feature-area view `.onAppear` |
| **Data-condition** | `WizardTriggerService.evaluateDataConditions(overdueTaskCount:completedProjectCount:)` | `MainTabView.onAppear` (4s delay) |

### State Machine

```
notStarted ──[start]──→ inProgress
notStarted ──[dismiss + doNotShow]──→ notStarted (doNotShow = true)
inProgress ──[all steps done]──→ completed
inProgress ──[exit]──→ inProgress (progress saved)
completed  ──[restart from settings]──→ inProgress (step 0, new sessionId)
dismissed  ──[re-enable in settings]──→ notStarted (doNotShow = false)
```

### Persistence

**iOS:** `WizardState` SwiftData model (registered in `OPSApp.sharedModelContainer`)
**Android:** Room entity (same schema)
**Sync:** Supabase `wizard_states` table, last-active-wins conflict resolution

### Architecture (iOS)

| Component | File | Purpose |
|---|---|---|
| `WizardDefinitionProtocol` | `Wizard/Models/WizardDefinition.swift` | Protocol all wizard definitions conform to |
| `WizardStepDefinition` | `Wizard/Models/WizardDefinition.swift` | Step data (id, instruction, notification, skippable) |
| `WizardRegistry` | `Wizard/Definitions/WizardRegistry.swift` | Central registry of all wizard definitions |
| `WizardStateManager` | `Wizard/State/WizardStateManager.swift` | State machine — active wizard, step progression, analytics |
| `WizardTriggerService` | `Wizard/State/WizardTriggerService.swift` | Evaluates trigger conditions, role/permission gating |
| `WizardAnalyticsService` | `Wizard/Analytics/WizardAnalyticsService.swift` | Event recording |
| `WizardState` | SwiftData model | Per-user persistence (status, step, doNotShow, duration) |
| `WizardEnvironment` | `Wizard/Environment/WizardEnvironment.swift` | SwiftUI environment keys for stateManager + triggerService |
| `WizardBanner` | `Wizard/Views/WizardBanner.swift` | Top banner UI |
| `WizardPromptOverlay` | `Wizard/Views/WizardPromptOverlay.swift` | Start/dismiss modal |
| `WizardInstructionBar` | `Wizard/Views/WizardInstructionBar.swift` | Bottom instruction bar (active wizard) |

### Adding a New Wizard

1. Create a new struct conforming to `WizardDefinitionProtocol` in `Wizard/Definitions/`
2. Add it to `WizardRegistry.allWizards`
3. For **contextual** wizards: call `wizardTriggerService.evaluateTrigger(for:context:)` from the feature view's `.onAppear`
4. For **data-condition** wizards: add evaluation logic to `evaluateDataConditions()` or create a new evaluation method
5. Post `NotificationCenter` notifications from the views where each step is completed
6. Update this dock with the full step table and notification sources

**End of Document**
