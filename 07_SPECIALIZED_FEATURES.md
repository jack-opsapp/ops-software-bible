# 07 - Specialized Features

**Last Updated:** March 29, 2026
**OPS Version:** iOS v1.7, Android Planning Phase
**Purpose:** Complete reference for specialized features including navigation, tutorial system, calendar scheduling, image management, PIN security, projects spatial canvas, spreadsheet view, project notes system, photo annotations, inventory management, notifications, crew location tracking, and advanced UI patterns.

---

## Table of Contents

1. [Turn-by-Turn Navigation System](#1-turn-by-turn-navigation-system)
2. [Tutorial & Demo Mode](#2-tutorial--demo-mode)
3. [Calendar Event Scheduling](#3-calendar-event-scheduling)
4. [Image Capture & S3 Sync](#4-image-capture--s3-sync)
5. [PIN Management](#5-pin-management)
6. [Projects Spatial Canvas & Spreadsheet View (Web)](#6-projects-spatial-canvas--spreadsheet-view-web)
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
21. [Blog & Content Marketing Pipeline](#21-blog--content-marketing-pipeline)
22. [Social Media Generation & Publishing](#22-social-media-generation--publishing)

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

> **Note (2026-04-27 — Phase 3, Web only):** OPS-Web's `/calendar` gained two capabilities documented in [Section 3a: Time Precision and Recurrence (Web)](#3a-time-precision-and-recurrence-web). iOS retains the existing all-day model — these features ship to web first.

### 3a. Time Precision and Recurrence (Web)

Phase 3 on `OPS-Web/src/app/(dashboard)/calendar/`. Spec at `docs/superpowers/specs/2026-04-27-calendar-time-precision-recurrence.md`.

**Time precision (all-day vs timed)**:
- Source of truth is the new `project_tasks.all_day` column (`BOOLEAN NOT NULL DEFAULT TRUE`). Pre-Phase-3 tasks are all-day even though they carry hardcoded `start_time = 08:00:00` and `end_time = 17:00:00`.
- Toggling `all_day = false` on a task seeds `start_time` / `end_time` from `companies.default_work_start` / `default_work_end` (defaults `08:00–17:00`).
- The task detail panel renders an "ALL-DAY ON / OFF" segmented control plus two `<input type="time" step="900">` inputs (15-min snap, JetBrains Mono with tabular-nums).
- Time labels render on Day, Week (via DayTaskCard), Crew, and Month-expanded cards when `event.allDay === false`.

**Hourly Day view**:
- `CalendarGridDay` switches to `DayHourlyGrid` whenever any event in the visible day has `allDay === false`.
- 16-hour vertical column (FIRST_HOUR=6 → LAST_HOUR=22) with 60-min rows and 15-min sub-grid.
- All-day events render in a fixed-height strip above the hourly grid so they remain visible.
- Drag = vertical reschedule, snapped to 15-min increments via `Math.round(deltaY / SNAP_PX) * SNAP_PX`.
- Resize handles (top + bottom, 6px) edit `start_time` and `end_time` independently. Minimum 15-min duration enforced.

**Repeat picker (RFC 5545 RRULE)**:
- Lives in the task detail panel below the Schedule section. Six presets (Off, Daily, Weekly on `<weekday>`, Biweekly on `<weekday>`, Monthly on `<day>`, Custom).
- Custom editor supports FREQ + INTERVAL + BYDAY (weekly) / BYMONTHDAY (monthly) + end condition (Never / Until / Count).
- Driven by `rrule@^2.8.1`. Strings are stored verbatim on `task_recurrences.rrule` so the cron parses them with `RRule.parseString`.
- Enabling repeat on a one-off task: creates a `task_recurrences` template seeded from the task, then soft-deletes the seed task. Cron materializes the first occurrence (and every future occurrence in the 60-day window) within minutes.

**Edit-this / Following / All scope prompt**:
- `<RecurrenceEditPrompt>` (Radix AlertDialog at z-modal=3000) appears whenever a user edits a series-bound task — drag in any view, or change the repeat rule in the panel.
- Three options:
  - **This** → upsert a `task_recurrence_exceptions` row with `action='reschedule'` (or `skip` for delete) for the original date. Live task row patched in place.
  - **This and following** → cap original template's `end_anchor` at `originalDate - 1`, fork a new template from `originalDate` with the patch applied, re-point future generated tasks to it.
  - **Entire series** → patch the original template directly. Cron regenerates everything from `next_generation_at = NOW()`.
- Cancel returns no-op; the calling mutation is aborted.

**Cron generation (`/api/cron/recurrence-generate`)**:
- Vercel cron registered in `vercel.json` at `0 */4 * * *` (every 4 hours). Bearer token = `CRON_SECRET`.
- For every active `task_recurrences` row whose `next_generation_at <= NOW()`:
  1. Build `RRule.fromString(rrule)` with `dtstart = start_anchor`, optional `until = end_anchor`.
  2. Expand `between(NOW(), NOW() + 60 days)` (the `RECURRENCE_HORIZON_DAYS` window).
  3. For each candidate date: look up exception → skip / apply override / use template defaults. Compute `start_date`, `end_date`, `start_time`, `end_time`, `team_member_ids`. Insert into `project_tasks` with `recurrence_id`, `recurrence_origin_date`. Skip on unique-conflict (idempotent).
  4. Emit one `schedule_change` notification per assigned crew member per generated task.
  5. Update `next_generation_at = NOW() + 4h`.

**Performance**: At 100 active recurrences with ~9 occurrences each over 60 days, the cron writes ~900 rows per 4h run. Vercel Pro plan covers the cost; Supabase impact is negligible.

---

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

## 6. Projects Spatial Canvas & Spreadsheet View (Web)

**Added:** 2026-03-29
**Scope:** Unified `/projects` route replacing both the old `/projects` list page and the `/job-board` kanban board. Two view modes: spatial canvas (default) and spreadsheet.

> **Route removal:** The `/job-board` route directory (`src/app/(dashboard)/job-board/`) was deleted. The `/projects` route was rewritten from a list page to the spatial canvas. All sidebar references to "Job Board" were removed. The iOS app retains its own `JobBoardView` (documented in prior revisions of this section).

### Architecture

```
page.tsx (orchestrator)
  ├── ProjectFloatingToolbar (search, filters, sort, view toggle, bulk bar)
  ├── MetricsHeader (active count, total value, completed, overdue)
  ├── DndContext (dnd-kit)
  │   ├── [canvas mode]
  │   │   ├── ProjectCanvas (viewport: pan/zoom/marquee/dot-grid)
  │   │   │   ├── ProjectStageStack (one per active status column)
  │   │   │   │   └── ProjectCard (collapsed 60px / bird's-eye 8px pill)
  │   │   │   │       └── ProjectCardExpanded (inline detail + quick actions)
  │   │   │   ├── ProjectTerminalRegion (Closed — grid layout)
  │   │   │   └── ProjectMarqueeSelect (AABB selection rectangle)
  │   │   ├── ProjectArchiveTray (bottom drawer for Archived projects)
  │   │   ├── ProjectDragOverlay (ghost card during drag)
  │   │   ├── ProjectDragConfirmation (first-time status-change dialog)
  │   │   └── ProjectContextMenu (right-click actions)
  │   └── [spreadsheet mode]
  │       └── ProjectSpreadsheet (table with inline editing)
  │           ├── SpreadsheetHeader (sortable column headers + visibility dropdown)
  │           ├── SpreadsheetRow (per-project row with editable cells)
  │           └── SpreadsheetBulkBar (selection actions bar)
  └── ProjectDetailPopover (tabbed floating window, tethered to card)
```

### Layout Architecture — HUD Overlay Pattern

The topbar (56px) and sidebar (72px on md+) are fixed glass overlays that float above page content. Pages render full-bleed behind them. This allows spatial canvas pages (pipeline, projects, intel) to use the entire viewport for pan/zoom surfaces.

| Element | CSS | Purpose |
|---------|-----|---------|
| Sidebar | `fixed left-0 top-0 w-[72px] h-full z-[500]` | Navigation rail, hidden on mobile |
| Topbar | `fixed top-0 right-0 h-[56px] left-0 md:left-[72px] z-10` | Header with notifications and user menu |
| Main content | `h-screen w-full pl-0 md:pl-[72px]` | Content area, padded for sidebar on desktop |
| Full-bleed pages | No `pt-[56px]` — content renders behind topbar | Canvas/intel pages that own the viewport |
| Standard pages | `pt-[56px]` on container | Pages that need topbar clearance (e.g., inbox) |

### Canvas View

#### Stage Columns (Left to Right)

| Column | Status | Color Source |
|--------|--------|-------------|
| 1 | RFQ | `PROJECT_STATUS_COLORS[ProjectStatus.RFQ]` |
| 2 | Estimated | `PROJECT_STATUS_COLORS[ProjectStatus.Estimated]` |
| 3 | Accepted | `PROJECT_STATUS_COLORS[ProjectStatus.Accepted]` |
| 4 | In Progress | `PROJECT_STATUS_COLORS[ProjectStatus.InProgress]` |
| 5 | Completed | `PROJECT_STATUS_COLORS[ProjectStatus.Completed]` |

**Terminal region (right side):** Closed projects in a 3-column grid layout.
**Archive tray:** Bottom drawer for Archived projects, toggled from toolbar.

#### Layout Constants

| Constant | Value | Notes |
|----------|-------|-------|
| `CARD_WIDTH` | 200px | Matches pipeline for layout engine compatibility |
| `CARD_HEIGHT` | 60px | Taller than pipeline (44px) — two lines + progress bar |
| `CARD_PILL_HEIGHT` | 8px | Bird's-eye mode pill height |
| `STACK_GAP` | 10px | Vertical gap between cards |
| `STACK_HORIZONTAL_GAP` | 80px | Horizontal gap between columns |
| `STACK_HEADER_HEIGHT` | 52px | Column header height |
| `CANVAS_PADDING` | 200px | Padding around canvas content |
| `TERMINAL_COLS` | 3 | Columns in terminal region grid |
| `TERMINAL_GAP` | 80px | Gap between terminal grid cells |
| `MIN_ZOOM` | 0.3 | Minimum zoom level |
| `MAX_ZOOM` | 1.5 | Maximum zoom level |
| `DEFAULT_ZOOM` | 0.8 | Initial zoom on load |
| `BIRD_EYE_THRESHOLD` | 0.5 | Zoom below this renders pills instead of cards |

#### Viewport & Interaction

- **Pan:** Middle-click drag, clamped to keep content visible
- **Zoom:** Wheel (trackpad or mouse) toward cursor, range 0.3x-1.5x
- **Marquee select:** Left-drag on empty canvas, AABB intersection test
- **Bird's-eye mode:** Zoom < 0.5 renders cards as 8px colored pills, hides region chrome
- **Dot grid background:** 24px spacing, 0.7px dots at `rgba(255,255,255,0.06)`
- **Auto-fit:** `fitAll()` on first load, scales to 90% of viewport
- **Keyboard:** Escape clears selection, context menu, and marquee

#### Card Design

**Collapsed state (~60px):**

| Element | Position | Content |
|---------|----------|---------|
| Title | Line 1 left | `project.title ?? formatStreetAddress(project.address) ?? "Untitled Project"` |
| Value | Line 1 right | Formatted currency (accounting permission only) |
| Client name | Line 2 | Dimmed `text-text-tertiary`, empty if no client |
| Progress bar | Bottom 2px | `completedTasks / totalTasks`, status color fill |
| Left border | 3px solid | Status color from `PROJECT_STATUS_COLORS` |

**Surface:** `rgba(13,13,13,0.6)` + `backdrop-blur(20px) saturate(1.2)` + `1px solid rgba(255,255,255,0.08)`

**States:** Selected (2px solid status color + glow), Hovered (1px solid at 50% opacity), Bird's-eye (8px pill)

**Expanded state (inline below card):** Task summary, team avatars, date range, days in status. Quick actions: Open Detail, Add Task (permission-gated), Record Payment (permission-gated), Archive.

**Staleness:** Cards dim based on recency of activity, calculated by `calculateBatchProjectStaleness()`.

#### Stage Stack Headers

Each column header shows status name, card count, and total value (accounting permission only). Hover reveals average days in status and oldest project. Bottom border animates left-to-right on hover with the status color.

#### Drag & Drop

**Status change via drag:** Drag cards between columns to change project status. First-time drag shows a confirmation dialog (stored in localStorage as `ops_projects_drag_confirmed`). After confirmation, all subsequent drags are silent. Fires `useUpdateProjectStatus` mutation with optimistic update and toast on error.

**Free-form positioning:** Drop on empty canvas saves a custom position (Finder-style). Custom positions override layout engine positions. Stored in `customPositions` map.

**Multi-select drag:** Shift/Meta click for multi-select. Drag all selected cards together with batch count badge on overlay.

**Archive drop:** Archive tray appears at bottom during drag. Drop on tray sets status to Archived.

#### Context Menu

Right-click on card(s) shows: Open Detail, Change Status (submenu), Add Task, Record Payment (permission-gated), Archive, Delete (permission-gated with confirmation). Multi-select shows batch actions.

#### Detail Popover

Floating window tethered to the expanded card, managed by `useProjectDetailPopoverStore` (Zustand). Supports multiple concurrent popovers with z-index stacking, minimize/restore, drag repositioning, and resize.

| Constant | Value |
|----------|-------|
| `POPOVER_DEFAULT_WIDTH` | 440px |
| `POPOVER_DEFAULT_HEIGHT` | 520px |
| `POPOVER_MIN_WIDTH` | 360px |
| `POPOVER_MIN_HEIGHT` | 320px |
| `POPOVER_Z_BASE` | 2000 |

**Tabs:**

| Tab | Content |
|-----|---------|
| Overview | Title, address, client info, status, dates, team, description, notes |
| Tasks | Task list grouped by status with progress |
| Financial | Estimates + invoices linked to project (permission-gated: `accounting.view`) |
| Photos | Project photos grid |

**Actions:** Edit project, Delete (soft delete with confirmation), Get Directions (maps link), Add Task, Record Payment (permission-gated).

### Canvas Store (Zustand)

**Store:** `useProjectCanvasStore` — `src/app/(dashboard)/projects/_components/project-canvas-store.ts`

| State | Type | Purpose |
|-------|------|---------|
| `viewportX`, `viewportY` | `number` | Pan position |
| `zoom` | `number` | Current zoom level (0.3-1.5) |
| `canvasWidth`, `canvasHeight` | `number` | Computed canvas dimensions |
| `sortBy` | `ProjectSortOption` | Global sort: `"title" \| "client" \| "date" \| "value" \| "progress"` |
| `statusSortOverrides` | `Map<string, ProjectSortOption>` | Per-column sort override |
| `selectedCardIds` | `Set<string>` | Currently selected project IDs |
| `expandedCardIds` | `Set<string>` | Currently expanded project IDs |
| `hoveredCardId` | `string \| null` | Hovered card ID |
| `isDragging` | `boolean` | Drag in progress |
| `dragCardIds` | `string[]` | IDs being dragged |
| `dragOrigin` | `CardPosition \| null` | Drag start coordinates |
| `isMarqueeActive` | `boolean` | Marquee selection in progress |
| `marqueeStart`, `marqueeEnd` | `CardPosition \| null` | Marquee rectangle bounds |
| `contextMenu` | `ContextMenuState \| null` | Context menu state (position, type, target) |
| `customPositions` | `Map<string, CardPosition>` | Finder-style free-form card positions |
| `isArchiveTrayOpen` | `boolean` | Archive tray visibility |
| `firstDragConfirmed` | `boolean` | Whether user has confirmed first drag (persisted to localStorage) |

### Layout Engine

**File:** `src/app/(dashboard)/projects/_components/project-layout-engine.ts`

The layout engine computes card positions for the canvas. Active statuses are arranged as vertical columns left-to-right. Terminal statuses (Closed) use a multi-column grid. The engine accepts projects grouped by status, sort options, and custom positions, and returns `ProjectCanvasLayout` with:

- `stacks[]` — one `StackLayout` per active status with header position, card positions, and region bounds
- `terminalRegions[]` — one `TerminalRegionLayout` per terminal status with grid positions
- `canvasWidth`, `canvasHeight` — total computed canvas dimensions

Sort function `sortProjects()` supports sorting by title (alpha), client (alpha), date (newest first), value (highest first), and progress (highest first). Per-column sort overrides allow different sort orders per status column.

### Spreadsheet View

Toggled via the toolbar's view mode control (Canvas / Spreadsheet icons). The spreadsheet replaces the canvas with a full-width table.

**Component:** `ProjectSpreadsheet` — `src/app/(dashboard)/projects/_components/project-spreadsheet.tsx`

#### Columns (21 total)

Column definitions live in `src/app/(dashboard)/projects/_components/spreadsheet/spreadsheet-columns.ts`.

| Column ID | Header | Width | Sortable | Editable | Default Visible | Permission |
|-----------|--------|-------|----------|----------|----------------|------------|
| `actions` | (menu) | 40px | No | No | Yes | — |
| `status` | Status | 120px | Yes | Status picker | Yes | — |
| `title` | Title | 200px | Yes | Text | Yes | — |
| `client` | Client | 150px | Yes | No | Yes | — |
| `address` | Address | 180px | Yes | Text | Yes | — |
| `startDate` | Start Date | 100px | Yes | Date | Yes | — |
| `endDate` | End Date | 100px | Yes | Date | Yes | — |
| `progress` | Progress | 120px | Yes | No | Yes | — |
| `estimateTotal` | Estimate Total | 100px | Yes | No | Yes | `accounting.view` |
| `invoiceTotal` | Invoice Total | 100px | Yes | No | No | `accounting.view` |
| `tasks` | Tasks | 100px | Yes | No | No | — |
| `duration` | Duration | 80px | Yes | Number | No | — |
| `team` | Team | 100px | No | No | No | — |
| `images` | Images | 100px | No | No | No | — |
| `clientEmail` | Client Email | 160px | No | No | No | — |
| `clientPhone` | Client Phone | 120px | No | No | No | — |
| `notes` | Notes | 200px | No | No | No | — |
| `description` | Description | 200px | Yes | Textarea | No | — |
| `pipeline` | Pipeline | 80px | No | No | No | — |
| `daysInStatus` | Days in Status | 90px | Yes | No | No | — |
| `created` | Created | 100px | Yes | No | No | — |

#### Column Visibility

Users toggle column visibility via a dropdown in the header. Visibility state is persisted to localStorage (`ops_projects_spreadsheet_columns`). Functions: `loadColumnVisibility()`, `saveColumnVisibility()`, `getDefaultColumnVisibility()`.

#### Inline Editing

Click a cell to edit. Edit types per column:

| Edit Type | Component | Behavior |
|-----------|-----------|----------|
| `text` | `SpreadsheetCellText` | Single-line text input, blur/Enter to save |
| `textarea` | `SpreadsheetCellTextarea` | Multi-line text, blur to save |
| `date` | `SpreadsheetCellDate` | Date input |
| `number` | `SpreadsheetCellNumber` | Numeric input |
| `status` | `SpreadsheetCellStatus` | Dropdown with all project statuses, color-coded |

All edits fire `useUpdateProject` or `useUpdateProjectStatus` mutations. Changes are optimistic.

#### Bulk Actions

Checkbox column for row selection. Shift-click for range select. When rows are selected, the `SpreadsheetBulkBar` appears in the toolbar with:

- **Change Status** — dropdown with all statuses (RFQ through Closed)
- **Archive** — moves selected projects to Archived
- **Delete** — soft delete with confirmation (permission-gated: `projects.delete`)
- **Clear selection** — deselects all

#### Status Filters

The toolbar provides three status filter tabs in spreadsheet mode:

| Filter | Shows |
|--------|-------|
| `active` | RFQ, Estimated, Accepted, InProgress, Completed |
| `archived` | Archived projects |
| `closed` | Closed projects |

#### Sorting

Click column header to cycle: none -> ascending -> descending. Sort indicator arrow shown in header. Sorting is client-side on the filtered dataset.

### Toolbar

**Component:** `ProjectFloatingToolbar` — `src/app/(dashboard)/projects/_components/project-floating-toolbar.tsx`

Frosted glass bar below the metrics header. Contains:

- **Search input** — filters across title, client name, address (case-insensitive substring)
- **Team member filter** — dropdown to filter by assigned team member
- **Client filter** — dropdown to filter by client
- **Sort control** — title, client, date, value (permission-gated), progress (canvas mode only)
- **View toggle** — Canvas (`LayoutGrid` icon) / Spreadsheet (`Table2` icon)
- **Archive toggle** — show/hide archived projects tray (canvas mode only)
- **Closed toggle** — show/hide closed projects (canvas mode only)
- **Bulk action bar** — appears when spreadsheet rows are selected

### Metrics Header

Pipeline-style metrics header at top of page (reuses `MetricsHeader` component).

| Metric | Source |
|--------|--------|
| Active projects | Count of projects with status in RFQ, Estimated, Accepted, InProgress |
| Total value | Sum of invoice totals for active projects (`accounting.view` required) |
| Completed | Count of Completed projects |
| Overdue | Projects past `endDate` that are not Completed/Closed/Archived |

### Data Hooks

| Hook | Purpose |
|------|---------|
| `useScopedProjects()` | Permission-aware project list |
| `useClients()` | Client name/email/phone lookup |
| `useTeamMembers()` | Team member avatars and names |
| `useProjectMetrics()` | Metrics header data |
| `useInvoices()` | Project value calculation (group by `projectId`, sum totals) |
| `useEstimates()` | Estimate totals per project |
| `useTasks()` | Task counts (total + completed) per project |
| `useUpdateProjectStatus()` | Status change mutation (drag, context menu, spreadsheet) |
| `useUpdateProject()` | Field-level edit mutation (spreadsheet inline editing) |
| `useDeleteProject()` | Soft delete mutation |

### Permission Matrix

| Action | Permission Required |
|--------|-------------------|
| View canvas / spreadsheet | `projects.view` |
| See all projects | `projects.view` scope `"all"` |
| See only assigned | `projects.view` scope `"assigned"` |
| Drag to change status | `projects.edit` |
| Inline edit cells (spreadsheet) | `projects.edit` |
| Add task from expanded card | `tasks.create` |
| Record payment | `accounting.edit` |
| See project value / financial columns | `accounting.view` |
| Archive project | `projects.edit` |
| Delete project | `projects.delete` |
| Bulk actions (spreadsheet) | `projects.edit` / `projects.delete` |
| Edit project (in popover) | `projects.edit` |

### Key Files

| File | Purpose |
|------|---------|
| `src/app/(dashboard)/projects/page.tsx` | Page orchestrator — data fetching, DnD context, view mode routing |
| `src/app/(dashboard)/projects/_components/project-canvas-store.ts` | Zustand store for canvas state (viewport, selection, drag, sort) |
| `src/app/(dashboard)/projects/_components/project-canvas.tsx` | Viewport container (pan/zoom/marquee/dot-grid) |
| `src/app/(dashboard)/projects/_components/project-layout-engine.ts` | Layout calculator (columns, terminal grid, canvas dimensions) |
| `src/app/(dashboard)/projects/_components/project-card.tsx` | Card rendering (collapsed + bird's-eye pill) |
| `src/app/(dashboard)/projects/_components/project-card-expanded.tsx` | Expanded card info rows + quick actions |
| `src/app/(dashboard)/projects/_components/project-stage-stack.tsx` | Column rendering with header + droppable zone |
| `src/app/(dashboard)/projects/_components/project-terminal-region.tsx` | Closed region (3-column grid layout) |
| `src/app/(dashboard)/projects/_components/project-drag-overlay.tsx` | Ghost card during drag |
| `src/app/(dashboard)/projects/_components/project-marquee-select.tsx` | Selection rectangle with AABB intersection |
| `src/app/(dashboard)/projects/_components/project-context-menu.tsx` | Right-click menu (single + multi-select) |
| `src/app/(dashboard)/projects/_components/project-floating-toolbar.tsx` | Toolbar (search/filter/sort/view toggle/bulk bar) |
| `src/app/(dashboard)/projects/_components/project-archive-tray.tsx` | Bottom drawer for archived projects |
| `src/app/(dashboard)/projects/_components/project-detail-popover.tsx` | Detail popover (tabbed floating window) |
| `src/app/(dashboard)/projects/_components/project-detail-popover-store.ts` | Popover state (Zustand) — position, z-index, tabs, minimize |
| `src/app/(dashboard)/projects/_components/project-drag-confirmation.tsx` | First-time drag confirmation dialog |
| `src/app/(dashboard)/projects/_components/project-staleness.ts` | Staleness opacity calculator |
| `src/app/(dashboard)/projects/_components/project-spreadsheet.tsx` | Spreadsheet view — table with inline editing, sorting, selection |
| `src/app/(dashboard)/projects/_components/spreadsheet/spreadsheet-columns.ts` | Column definitions, visibility persistence |
| `src/app/(dashboard)/projects/_components/spreadsheet/spreadsheet-header.tsx` | Sortable column headers + column visibility dropdown |
| `src/app/(dashboard)/projects/_components/spreadsheet/spreadsheet-row.tsx` | Per-project row with editable cells |
| `src/app/(dashboard)/projects/_components/spreadsheet/spreadsheet-bulk-bar.tsx` | Bulk action bar (status change, archive, delete) |
| `src/app/(dashboard)/projects/_components/spreadsheet/spreadsheet-cell-text.tsx` | Inline text cell editor |
| `src/app/(dashboard)/projects/_components/spreadsheet/spreadsheet-cell-textarea.tsx` | Inline textarea cell editor |
| `src/app/(dashboard)/projects/_components/spreadsheet/spreadsheet-cell-date.tsx` | Inline date cell editor |
| `src/app/(dashboard)/projects/_components/spreadsheet/spreadsheet-cell-number.tsx` | Inline number cell editor |
| `src/app/(dashboard)/projects/_components/spreadsheet/spreadsheet-cell-status.tsx` | Inline status picker cell |

### iOS Job Board (Legacy Reference)

The iOS app retains its own `JobBoardView` (`OPS/OPS/Views/JobBoard/JobBoardView.swift`) with section-based navigation (Dashboard, Clients, Projects, Tasks) and `UniversalJobBoardCard` (`OPS/OPS/Views/JobBoard/UniversalJobBoardCard.swift`). The iOS job board is a separate implementation from the web projects canvas and operates on SwiftData/SwiftUI. See prior revisions of this section for full iOS job board documentation.

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

#### Web Notifications Drawer (OPS Web — 2026-04-23)

The web app surfaces notifications via a right-edge vertical drawer, triggered by a reusable `<EdgeTab>` primitive. Replaces the 2026-03-09 horizontal topbar rail. See `docs/superpowers/specs/2026-04-23-vertical-notification-system.md` for design rationale.

**Components:**
- `src/components/ui/edge-tab.tsx` + `edge-tab.types.ts` — reusable 28px right-edge tab primitive (consumed by Notifications and Quick Actions)
- `src/components/layouts/notifications-tab.tsx` — Notifications-specific tab wrapper (count + accent + `N` shortcut)
- `src/components/layouts/notifications-drawer.tsx` — 360px drawer with chip-filter buckets (ALL/CRITICAL/ATTENTION/AMBIENT), row list, header actions (mute/clear-all), footer
- `src/components/layouts/notifications-row.tsx` — expandable row (icon + title + timestamp; click expands body + action buttons + dismiss)
- `src/lib/notifications/notification-meta.ts` — NOTIF_TYPE_META registry mapping 18 NotificationType values to `{label, icon, tone}`
- `src/lib/notifications/translate-copy.ts` — i18n-keyed notification content translator (shared util)
- `src/stores/edge-tab-store.ts` — Zustand single-slot mutual-exclusion store (`activeTab: 'notifications' | 'quick-actions' | null`)

**States:**
- **Closed (default):** 28px edge tab flush right. Vertical "NOTIFICATIONS" wordmark + count badge + bell glyph. Left accent stripe is rose if any CRITICAL, tan if any ATTENTION, steel-blue (accent) otherwise.
- **Open:** 360px drawer slides in from right (260ms); tab grows to drawer-area height, glyph rotates to ×, wordmark reads "CLOSE". Drawer shows chip filters, scrollable row list, footer.
- **Row expanded:** click any row to inline-expand body + inline actions (ACTION button, SNOOZE stub, DISMISS).

**Keyboard:**
- `N` toggles the drawer (global; suppressed in inputs/textareas/contenteditable).
- `Escape` closes the drawer.
- Arrow `Up`/`Down` move focus between rows.

**Mutual exclusion:** `useEdgeTabStore` ensures only one edge tab drawer is open at a time. Opening Notifications atomically closes Quick Actions and vice versa.

**Data Model:** unchanged — existing `AppNotification` + `notifications` table (columns `persistent`, `action_url`, `action_label` already present).

**Motion:** `drawerVariants` / `rowVariants` / `chipVariants` in `src/lib/utils/motion.ts`, all with reduced-motion fallbacks.

**Integration:** any feature that produces a user-facing event inserts a row into the `notifications` table. The drawer picks it up automatically via TanStack Query's `useNotifications()` hook.

**`schedule_change` notification (Phase 3 — 2026-04-27):**
- Emitted by `useUpdateTask` when the union of (`startDate`, `endDate`, `startTime`, `endTime`, `allDay`) changes on a task. Recipients = union of prior + new `team_member_ids` so removed crew also see the move.
- Emitted by `/api/cron/recurrence-generate` for each newly-materialized occurrence — one row per assigned crew member.
- Title: "Task rescheduled" (`useUpdateTask`) or "Recurring task scheduled" (cron). Body includes project title and date.
- `action_url = /calendar?date=YYYY-MM-DD&task=<uuid>` so clicking deep-links to the affected day with the task panel open.
- `persistent = false` (standard, dismissible). Use a `task_review_stack` persistent variant only for batch-confirm flows.

---

#### Web Quick Actions Edge Tab (OPS Web — 2026-04-25)

The Quick Actions tab replaces the prior bottom-right circular FAB (`floating-action-button.tsx`, removed 2026-04-25). It mounts on the right edge below Notifications and pairs with a 308×452 panel-anchored drawer. Spec source: `ops-design-system-v2/project/fab/variants.jsx` V1 — selected per the design brief at `ops-design-system-v2/project/fab/FAB Redesign.html` for "lowest intrusion / ops-iest shape." Long-press edit mode is dropped in favor of a persistent `CUSTOMIZE →` footer routing to `/settings?tab=quick-actions`.

**Components:**
- `src/components/layouts/quick-actions-tab.tsx` — wraps `<EdgeTab>`. `restHeight=132`, `stackOffset=+94` (mirrors notif `-94`), accent always `--ops-accent`, plus glyph rotates 0°→45° on open. `Q` keyboard shortcut.
- `src/components/layouts/quick-actions-drawer.tsx` — 308×452 panel-anchored drawer. Header `// QUICK ACTIONS` + `Q` KeyHint, action list (icon + label + 3-letter hint), footer `CUSTOMIZE →`.
- `src/lib/hooks/use-quick-actions.ts` — returns the user's filtered actions (permission + feature-flag + user-prefs filtering, lifted from the deleted FAB component).
- `src/lib/constants/fab-actions.ts` — extended with `hintCode` field per action: `EXP / LED / EST / INV / CLI / PRJ / TSK / TTY / ITM`.

**Drawer surface (denser than Notifications by spec):**
- Background: `rgba(32, 34, 38, 0.92)` (denser, slightly lighter tone for action-list legibility)
- Border: `1px solid rgba(255, 255, 255, 0.18)`, `border-right: none`
- Backdrop: `blur(28px) saturate(1.3)`
- Top-edge highlight gradient applied (matches all glass surfaces)
- Position: anchored to tab vertical center via `stackOffset` math, NOT full-rail like Notifications

**States:**
- **Closed:** 28×132 tab. Vertical "QUICK ACTIONS" wordmark + `+` glyph. Steel-blue (`--ops-accent`) accent stripe always.
- **Open:** drawer slides in from right (260ms); tab grows to drawer height, glyph rotates 45° → `×`, wordmark reads "CLOSE". Drawer shows action list + customize footer.
- **Hover (closed):** tab brightens, glow shadow on accent stripe, tooltip with `Q` KeyHint flies out left.

**Action click:**
1. Permission check (`usePermissionStore.can(action.requiredPermission)`).
2. Feature flag check (`canAccessFeature(getSlugForRoute(...))`).
3. SetupGate check — if incomplete, opens `SetupInterceptionModal` with the action queued via `pendingAction`.
4. On gated approval: `handler === "window"` → `useWindowStore.openWindow(...)`; `handler === "route"` → `router.push(...)`.
5. Drawer closes via `useEdgeTabStore.close('quick-actions')`.

**Keyboard:**
- `Q` toggles the drawer (global; suppressed in inputs/textareas/contenteditable; no modifiers).
- `Escape` closes.

**Hide conditions:** identical to the prior FAB — hidden on `/intel`, when dashboard customizing, when a wizard is open, or when the duplicate-review sheet is open. Returns `null` from both tab and drawer when any condition is true.

**Customize:** the `CUSTOMIZE →` footer button routes to `/settings?tab=quick-actions` and closes the drawer. Settings tab provides reorder + add/remove for the user's `fabActions` preference array (existing `updateFabActions` mutation in `auth-store.ts`).

**Motion:** `quickActionsDrawerVariants` / `quickActionsRowVariants` in `src/lib/utils/motion.ts`, both with reduced-motion fallbacks (opacity-only at 150ms).

**Removed:**
- `src/components/ops/floating-action-button.tsx` (deleted 2026-04-25)
- Long-press edit mode (replaced by routed customize)
- The bottom-right 52px circular FAB position

### §14.4 Email infrastructure (typed React Email)

OPS-Web sends every transactional and marketing email through
`src/lib/email/sendgrid.tsx`. The chokepoint exposes one typed function per
email kind (`sendPasswordReset`, `sendTeamInvite`, `sendBetaAccessRequest`,
`sendTrialExpiryWarning`, etc.) and routes each through one of four sender
buckets defined in `src/lib/email/senders.ts`:

| Bucket | Address | Purpose |
|--------|---------|---------|
| DISPATCH | `dispatch@opsapp.co` | Product, team, beta, trial, billing, ads briefing |
| GATE | `gate@opsapp.co` | Security, auth, password, email verification |
| FIELD_NOTES | `field@opsapp.co` | Newsletter, long-form content |
| PORTAL | per-company name + `SENDGRID_FROM_EMAIL` | Whitelabel portal emails |

Templates are React components under `src/lib/email/react/templates/`
(17 today: `PasswordReset`, `EmailVerification`, `EmailChangeConfirmation`,
`TeamInvite`, `RoleNeeded`, `BetaAccessRequest`, `BetaAccessDecision`,
`AdsBriefing`, `BlogNewsletter`, `FieldNotesNewsletter`,
`TrialExpiryWarning`, `TrialExpiryDiscount`, `TrialExpiryReengagement`,
`PortalEstimateReady`, `PortalInvoiceReady`, `PortalMagicLink`,
`PortalQuestionsReminder`). Each template is composed of layout primitives
in `src/lib/email/react/primitives/` (`Body`, `Button`, `Divider`, `Footer`,
`Headline`, `Hero`, `InfoBlock`, `Paragraph`, `Spacer`) and wrapped in
either `OpsEmailLayout` or `PortalEmailLayout`.

Tokens live in `src/lib/email/react/primitives/tokens.ts` (`emailTokens`
const). The token shape is intentionally email-constrained — only inline
styles, only web-safe fonts, no `backdrop-filter`. The web-app glass
surface (`rgba(18,18,20,0.58)` + `backdrop-blur(28px)`) is replaced with an
opaque `rgba(10,10,10,0.70)` fill since `backdrop-filter` does not render
in any major email client.

Fonts: **Mohave** for body and headings (uppercase headings use
`letter-spacing: 0.04em`, `font-weight: 400`), **JetBrains Mono** for
micro-labels and numbers. Cake Mono is Adobe Typekit-only and is not
available in email. Kosugi was retired 2026-04-17.

PMF re-render: `src/lib/email/pmf-bridge.tsx` selects between the legacy
`src/emails/pmf/*` templates and the new typed templates
(`PmfThresholdAlert`, `PmfDailyDigest`, `PmfWeeklyDigest`) based on
`EMAIL_PMF_NEW_TEMPLATES`. Defaults to legacy. Set to `true` in staging
during the bake; flip in production after a one-week soak.

Operator setup: `OPS-Web/docs/email/sendgrid-senders-setup.md`. Until DNS
is aligned, every typed sender falls back to `SENDGRID_FROM_EMAIL`.

### §14.5 Email suppressions

Full doc: `OPS-Web/docs/email/suppressions.md`.

- **Source of truth:** `public.email_suppressions` (added 2026-04-27 via migrations `079`–`083`). Every send checks this table before dispatch.
- **Auto-population:** trigger `trg_email_events_auto_suppress` fans `bounce` (hard/blocked), `spamreport`, `unsubscribe`, and `group_unsubscribe` events from the SendGrid webhook into the suppression list. Soft bounces and dropped events are not auto-suppressed.
- **Send-time gate:** every `sendXxx` in `src/lib/email/sendgrid.tsx` routes through `gatedSend`, which calls `isSuppressed(email, list)` and silently skips suppressed recipients. Skipped sends emit `email_log.status='suppression_skipped'` for observability.
- **Webhook hardening:** `email_events` now has `uq_email_events_idempotency` so SendGrid retries don't duplicate rows. The webhook upserts with `ignoreDuplicates: true` and is rate-limited to 600 req/min/IP via Vercel KV.
- **Operator controls:** `POST /api/admin/email/suppressions` to add manual entries (single or batch up to 1000), `DELETE /api/admin/email/suppressions/{email}?list=` to unblock.

### §14.6 Email compliance — CAN-SPAM + CASL

Every OPS email carries a compliance footer (legal name + physical address +
unsubscribe link) and `List-Unsubscribe` / `List-Unsubscribe-Post` headers
(RFC 2369 + RFC 8058). The unsubscribe token is HMAC-SHA256 over
`email|list|expiresAt`, signed with `EMAIL_UNSUBSCRIBE_SECRET`. POST to
`/api/email/unsubscribe` (JSON or form-urlencoded for Gmail one-click)
verifies and inserts into `email_suppressions` (PR 1 / §14.5).

CASL consent is recorded in `newsletter_subscribers.consent_at` /
`consent_ip` / `consent_source` (migration 084). Newsletter signup form
lives in `ops-site` — those routes write the consent columns; OPS-Web only
reads them for inquiry response.

Whitelabel portal emails use the customer's `companies.physical_address`
(migration 085) — the OPS address is the fallback when the company hasn't
filled it in.

- Source of truth for legal identifiers: `OPS-Web/src/lib/email/constants.ts`.
- Compliance footer primitive: `src/lib/email/react/primitives/ComplianceFooter.tsx`.
- Header injection: `buildComplianceHeaders()` inside `src/lib/email/sendgrid.tsx`.
- Public POST endpoint: `src/app/api/email/unsubscribe/route.ts`.
- Public confirmation page: `src/app/unsubscribe/page.tsx` (en + es).
- Operator runbook: `OPS-Web/docs/email/compliance.md`.

### §14.7 Email campaigns — dispatcher + worker pipeline (PR 3)

The marketing/lifecycle campaign system. Two-stage pipeline: a **dispatcher**
cron picks scheduled campaigns whose `scheduled_for` has passed, resolves
the audience, and enqueues one `email_jobs` row per recipient. A separate
**worker** cron atomically claims pending jobs (`FOR UPDATE SKIP LOCKED`),
calls the registered template's `gatedSend` wrapper for each, and updates
campaign counters via an allowlisted RPC. When all jobs for a campaign are
terminal, the campaign flips to `completed` and a notification rail entry
fires for the operator.

#### Tables

- `public.email_campaigns` (migration 086) — schema-of-record. One row per
  send (or scheduled send). Counters live on the row and are mutated only
  via the `increment_campaign_counter` RPC.
- `public.email_jobs` (migration 087) — one row per recipient per campaign.
  Idempotent unique constraint `(campaign_id, recipient_email)` (091, after
  the original 087 expression-index was switched to a column-based UNIQUE
  for PostgREST upsert compatibility — emails are pre-lowercased upstream).
- `public.email_log.campaign_id` (migration 088) — set by `gatedSend` when
  `campaignId` flows through. NULL for transactional sends. ON DELETE SET
  NULL preserves the log when a campaign is hard-deleted.

#### Enums

- `email_campaign_status`: `draft | scheduled | in_flight | completed | failed | cancelled | paused`
- `email_job_status`: `pending | dispatching | sent | bounced | failed | cancelled | skipped_suppressed`

#### Campaign state machine

```
draft → scheduled → in_flight → completed
                       │
                       ├─ paused ─→ in_flight (resume)
                       │
                       └─ cancelled

draft / scheduled / paused → cancelled
in_flight → failed (terminal — dispatcher could not enqueue)
```

#### RPCs (service-role only)

- `increment_campaign_counter(p_campaign_id, p_field, p_delta)` (migration 089)
  — allowlisted field name (`sent_count | delivered_count | bounced_count |
  opened_count | clicked_count | suppressed_skipped_count | failed_count`).
  Avoids read-modify-write race when concurrent worker batches finalize.
- `claim_email_jobs(p_limit)` (migration 090) — `FOR UPDATE SKIP LOCKED`
  claim of up to `p_limit` pending jobs from in-flight campaigns; transitions
  rows to `dispatching` so a parallel worker invocation skips them.

#### Service module

`OPS-Web/src/lib/email/campaigns.ts` — single TypeScript surface used by API
routes and crons:

- `createCampaign` / `scheduleCampaign` / `cancelCampaign` / `pauseCampaign` /
  `resumeCampaign`: state-machine transitions with prior-status guards.
- `enqueueCampaignJobs`: lowercases emails, calls `filterSuppressed`
  (PR 1 §14.5), upserts `email_jobs` with `ignoreDuplicates`, and either
  sets the campaign to `in_flight` or — when the audience is fully
  suppressed — flips straight to `completed`.
- `completeCampaignIfDone`: counts remaining `pending | dispatching` jobs;
  if zero AND status is non-terminal, transitions to `completed`.

#### Audience resolver (PR 3 starter — replaced by PR 5)

`OPS-Web/src/lib/email/audiences.ts` — three hardcoded segments:

- `all_users` — `is_active=true AND removed_from_email_list IS NOT TRUE`
- `trial_users` — same + `companies.subscription_status='trial'`  *(verified — not 'trialing')*
- `active_subscribers` — same + `companies.subscription_status IN ('active','grace')`

PR 5 replaces this module with a saved-template predicate engine.

#### Template registry

`OPS-Web/src/lib/email/campaign-templates.ts` (registry) +
`campaign-templates-bootstrap.ts` (idempotent wiring) — four starter
template_ids:

- `product_update` → `sendProductUpdate` (new sender + template)
- `trial_expiry_campaign` → `sendTrialExpiryWarning` (existing PR β sender, now
  campaign-aware)
- `feature_announcement` → `sendFeatureAnnouncement` (new)
- `reengagement` → `sendReengagement` (new — distinct from
  `sendTrialExpiryReengagement` which targets post-trial wins)

Every campaign sender accepts `campaignId` so `gatedSend` can write it to
`email_log.campaign_id` and forward it as a SendGrid `customArgs.campaign_id`
for webhook attribution (consumed by PR 6 engagement RPC).

#### Crons (`vercel.json`, every 1 min — Pro tier)

| Path | Schedule | Purpose |
|------|----------|---------|
| `/api/cron/email/dispatcher` | `*/1 * * * *` | Resolve audience + enqueue jobs for ready campaigns |
| `/api/cron/email/worker` | `*/1 * * * *` | Claim batch of 200, gatedSend each, increment counters, complete + notify |

Worker tunables: `BATCH_LIMIT=200`, `INTER_SEND_DELAY_MS=10`,
`MAX_RETRIES=3`. Auth: `Authorization: Bearer ${CRON_SECRET}`.

#### Admin API surface (all `withAdmin` + `requireAdmin`-gated)

- `GET  /api/admin/email/campaigns` — paginated list with optional status filter
- `POST /api/admin/email/campaigns` — create draft, returns campaign + estimated audience count
- `GET  /api/admin/email/campaigns/[id]` — campaign + jobs slice (50 by default)
- `POST /api/admin/email/campaigns/[id]/schedule` — set `scheduled_for`
- `POST /api/admin/email/campaigns/[id]/cancel` — cancel + sweep pending jobs
- `POST /api/admin/email/campaigns/[id]/pause` — `in_flight → paused`
- `POST /api/admin/email/campaigns/[id]/resume` — `paused → in_flight`
- `POST /api/admin/email/campaigns/audience-estimate` — recipient count for a filter

All `[id]` routes use Next.js 15's `params: Promise<{...}>` shape.

#### Admin UI

- Tab: **Admin → Email → Scheduled Sends** (`scheduled-sends-tab.tsx`)
- Components in `src/app/admin/email/_components/`:
  - `campaign-status-pill.tsx` — 7 states, Cake Mono Light 11px, earth-tone palette
  - `campaign-progress-bar.tsx` — segmented olive (sent) / rose (bounced) / brick (failed)
  - `campaign-create-modal.tsx` — name, slug auto-suggest, template, segment, schedule datetime, live audience count
  - `campaign-detail-modal.tsx` — 5s polling while `scheduled` or `in_flight`, counters animate on every value change, Pause/Resume/Cancel actions
- All animations: `EASE_SMOOTH` (`[0.22, 1, 0.36, 1]`), reduced-motion fallbacks centralized in `src/lib/utils/motion.ts`.

#### Notification rail

When a campaign completes, the worker inserts a `notifications` row for the
`created_by_user_id`:

- `type: "campaign_done"`, `persistent: false`
- `action_url: /admin/email?campaign=<id>`, `action_label: "VIEW CAMPAIGN"`
- Body summarises sent / bounced / failed / suppressed for the final batch

#### Gotchas

- **Pause is best-effort in PR 3**: a paused campaign's already-claimed
  batch still sends. Mid-batch the worker re-pends jobs whose campaign
  flipped to paused. PR 4 introduces the killswitch state machine that
  also gates `gatedSend` itself.
- **Campaign template registry is in-memory + idempotent.** `bootstrapCampaignTemplates()`
  is safe to call from every cron tick because workers run cold.
- **Recipient email is lowercased upstream** (in `enqueueCampaignJobs`) —
  the unique constraint is on the raw column. Don't insert mixed-case
  emails directly via SQL or upserts will dupe.
- **Audience filter is JSONB**. PR 3 supports the starter shape
  `{segment: "all_users" | "trial_users" | "active_subscribers"}`.

#### Source files

- Migrations: `supabase/migrations/086_email_campaigns.sql`, `087_email_jobs.sql`,
  `088_email_log_campaign_link.sql`, `089_increment_campaign_counter_rpc.sql`,
  `090_claim_email_jobs_rpc.sql`, `091_email_jobs_unique_constraint.sql`.
- Service: `OPS-Web/src/lib/email/campaigns.ts`.
- Audience: `OPS-Web/src/lib/email/audiences.ts`.
- Template registry: `OPS-Web/src/lib/email/campaign-templates.ts` +
  `campaign-templates-bootstrap.ts`.
- New senders: `OPS-Web/src/lib/email/sendgrid.tsx` (`sendProductUpdate`,
  `sendFeatureAnnouncement`, `sendReengagement`) + corresponding React
  Email templates in `src/lib/email/react/templates/`.
- Crons: `src/app/api/cron/email/dispatcher/route.ts`, `src/app/api/cron/email/worker/route.ts`.
- Admin API: `src/app/api/admin/email/campaigns/`.
- Admin UI: `src/app/admin/email/_components/`.

#### Tests

- Unit: `tests/unit/email/campaigns.test.ts` (14 tests).
- Integration: `tests/integration/email-dispatcher-cron.test.ts` (5 tests),
  `tests/integration/email-worker-cron.test.ts` (4 tests).
- E2E (skipped by default — needs staging admin + seeded audience):
  `tests/e2e/email-campaign.spec.ts`.

### §14.8 Email killswitches — pause state + audit (PR 4)

Operators can pause email at three scopes:

| Scope | Notation |
|-------|----------|
| Global | `global` |
| Sender bucket | `bucket:dispatch` / `bucket:gate` / `bucket:field_notes` / `bucket:portal` |
| Per-campaign | `campaign:<uuid>` |

Pause is the **first** check in `gatedSend` (before suppression). A paused
send writes `email_log.status='paused_skipped'` and never calls SendGrid.

#### Tables

- `email_pause_state` (migration 092) — one row per scope. CHECK constraint
  enforces the three scope shapes. Partial index `idx_email_pause_state_active`
  serves the banner's "list all active pauses" query.
- `email_pause_audit_log` (migration 093) — append-only. UPDATE/DELETE
  revoked from `anon` and `authenticated`; service role bypasses these so
  the pause/resume APIs can still write.
- `email_log.status` (migration 094) — column comment updated to document
  `paused_skipped` as a canonical value.

#### Service module — `src/lib/email/pause.ts`

| Function | Returns | Throws? |
|----------|---------|---------|
| `getActivePauseScope({kind, campaignId?})` | First active pause in `[global, bucket:<resolved>, campaign:<id>]` order | NEVER |
| `getPauseState(scope)` | Single scope's row or null | NEVER |
| `getActivePauses()` | All `is_paused=true` rows for the banner | NEVER |
| `pause({scope, reason, pausedUntil?, actorUserId, actorEmail})` | Updated `PauseState` | YES — admin route surfaces failure |
| `resume({scope, reason?, actorUserId, actorEmail})` | void | YES |
| `autoResume(scope)` | void — used by cron | YES |
| `listAuditLog({scope?, limit?, offset?})` | Audit rows | YES |

Reads NEVER throw — `gatedSend` reads on every send; a transient DB
failure must not crash a send. The trade-off is that a Supabase outage
fails open (no pause). The audit log captures any sends during such a
window.

#### Bucket resolution

`resolveEmailBucket(kind)` maps an email kind to its sender bucket:

- `gate` — `password_reset`, `email_verification`, `email_change_confirmation`
- `field_notes` — `field_notes_newsletter`, `blog_newsletter`
- `portal` — `portal_*`
- `dispatch` — everything else (default)

Keep in lockstep with `src/lib/email/senders.ts`.

#### Worker integration

`/api/cron/email/worker` batch-fetches `getPauseState('campaign:<id>')` for
every campaign in its claimed batch. Jobs whose campaign is paused are
left in `pending` and reconsidered next minute. Pauses are reversible, so
we never flip jobs to a terminal status from the killswitch path.

#### Auto-resume cron

`/api/cron/email/auto-resume` (every 5 min) selects rows where
`is_paused=true AND paused_until < now()`, calls `autoResume()` on each.
That writes the `auto_resume` audit row, clears the flag, and resolves
any persistent rail notifications for that scope.

#### Admin API

| Method | Path | Purpose |
|--------|------|---------|
| POST | `/api/admin/email/pause` | Pause a scope (reason >= 3 chars; optional ISO `paused_until`) |
| POST | `/api/admin/email/resume` | Resume a scope |
| GET | `/api/admin/email/pauses` | Active pauses (`?audit=1` to include 100 most recent audit rows) |

All three are `withAdmin(handler)` + `requireAdmin(req)`.

#### UI

- `/admin/email` → 8th tab `Killswitches`. Three sections: Global / Sender
  Buckets / Campaigns (note pointing to Scheduled Sends for per-campaign).
- `ActivePauseBanner` (sticky, top: 0, z: 30) is rendered above SubTabs and
  shows whenever ANY scope is paused. Polls `/api/admin/email/pauses` every
  10 seconds. olive `#9DB582` border + tan `#C4A868` eyebrow — never red.
- `PauseConfirmationModal` (z-3000) requires reason and offers Indefinite /
  In 1h / In 24h auto-resume. Brick `#93321A` outline on the destructive
  PAUSE button.

#### Notifications

Every successful pause inserts a persistent `email_pause` notification for
every admin (joined via `admins.email` → `users.email`). Resume / auto-
resume mark those notifications `is_read=true` by matching the title
`Email paused: <scope>`.

#### Tests

- Unit: `tests/unit/email/pause.test.ts` (4 tests — bucket resolver),
  `tests/unit/email/killswitches-tab.test.tsx` (3 tests — UI render).
- Integration: `tests/integration/email-pause-routes.test.ts`
  (12 tests — pause/resume/pauses validation + service calls).

---

### §14.9 Suppression manager + Audience builder (PR 5)

**Added:** 2026-04-27. Two new admin tabs ship under `/admin/email`:
**Suppressions** (browse / search / sort / paginate / bulk-add /
bulk-remove / CSV import / CSV export the `email_suppressions` list from
PR 1) and **Audience** (visual nested AND/OR predicate editor with a
400ms-debounced live count and "Save as template"). Saved templates can
be referenced from any campaign via `email_campaigns.audience_template_id`
(FK added in migration 092).

Migrations: **092** `email_audience_templates` table + FK +
`increment_audience_template_usage` RPC. **093** `email_audience_filter`
+ `email_audience_count` RPCs (recursive AND/OR walker). **094**
performance indexes for hot predicate paths.

#### Suppression manager — routes

| Method | Path | Purpose |
|--------|------|---------|
| GET | `/api/admin/email/suppressions` | Paginated list. Query: `limit`, `offset`, `reason`, `list`, `emailLike` (alias `email`) |
| POST | `/api/admin/email/suppressions` | Add one (`email`) or many (`emails[]`, ≤1000) |
| GET | `/api/admin/email/suppressions/[email]` | Single row by email + `?list=` |
| DELETE | `/api/admin/email/suppressions/[email]` | Remove by email + `?list=` |
| POST | `/api/admin/email/suppressions/bulk` | `{action:'add'\|'remove', emails[], list?, reason?}` |
| GET | `/api/admin/email/suppressions/export` | Streamed CSV, 5k-row pages |
| GET | `/api/admin/email/suppressions/lists` | Unique `list` values + counts |

All routes wrapped in `withAdmin` + `requireAdmin`. CSV export streams
in 5k batches — well under Supabase's 1MB cap. Above ~10k rows, swap to
a paginated download UI (followup).

UI: `suppressions-tab.tsx` (paginated 50/page, 300ms-debounced search,
multi-select bulk remove), `suppression-detail-drawer.tsx` (right-edge
slide-in, 400px, glass-dense, `z-3001`),
`suppression-bulk-add-modal.tsx`, `suppression-import-modal.tsx` (CSV
drag-drop, 100-row batches, live progress bar).

#### Audience builder — filter grammar

```
node ::= leaf | group | combinator
leaf ::= { field, op, value? }
group ::= { group: <node> }                 -- explicit grouping
combinator ::= { and: [<node>...] } | { or: [<node>...] }
```

Empty filter (`{}`) or empty combinator (`{and: []}`) matches all
emailable users (active + email NOT NULL + not opted out).

#### Allowlists

| Allowlisted field | SQL column |
|-------------------|------------|
| `email`, `role`, `user_type`, `is_company_admin`, `is_active`, `removed_from_email_list`, `company_id`, `created_at` | `users.<column>` |
| `plan` | `companies.subscription_plan` |
| `subscription_status` | `companies.subscription_status` |
| `trial_end_date` | `companies.trial_end_date` |

| Allowlisted op | Notes |
|----------------|-------|
| `eq`, `neq`, `lt`, `gt`, `lte`, `gte` | Standard comparisons. `eq null` → `IS NULL`. |
| `in`, `not_in` | Value must be a JSON array. |
| `gte_days`, `lte_days` | Relative to `now()`. Value is integer days. |
| `is_null`, `is_not_null` | No value. |
| `like` | Wraps value in `%..%` and uses `ILIKE`. |

Anything outside the allowlist raises `audience_clause: field X not in allowlist` (HTTP 400 from `/audience/preview`).

#### Audience builder — RPCs (migration 093)

- `email_audience_clause_to_sql(jsonb, ...) → text` — converts a single
  leaf to a parameterised SQL expression. `IMMUTABLE`.
- `email_audience_node_to_sql(jsonb, ...) → text` — recursive walker.
  `IMMUTABLE`.
- `email_audience_filter(jsonb) → TABLE(user_id uuid, email text)` —
  `SECURITY DEFINER`. Builds the SELECT, executes via `EXECUTE`, returns
  matched users. `service_role`-only.
- `email_audience_count(jsonb) → int` — same shape but returns just the
  count (cheap for the live preview).

`SECURITY DEFINER` + the field/op allowlist are the SQL-injection fence
— a malicious filter like `{field: "email; DROP TABLE users--", ...}`
raises the allowlist exception before any SQL is constructed.

#### Audience templates

`email_audience_templates(id, name UNIQUE, description, filter jsonb,
last_used_count int, last_resolved_at timestamptz, created_by_user_id,
created_at, updated_at)`. FK from `email_campaigns.audience_template_id`
with `ON DELETE SET NULL`.

`increment_audience_template_usage(uuid)` — `SECURITY DEFINER`. Called
by the dispatcher (`/api/cron/email/dispatcher`) when a campaign with
`audience_template_id` is resolved.

Indexes (094): `idx_users_active_emailable (is_active, removed_from_email_list) WHERE email IS NOT NULL`,
`idx_users_role`, `idx_users_company_id`,
`idx_companies_subscription_status`, `idx_companies_subscription_plan`.

#### Audience builder — API routes

| Method | Path | Purpose |
|--------|------|---------|
| POST | `/api/admin/email/audience/preview` | `{filter}` → `{count, sample[≤10]}` |
| GET | `/api/admin/email/suppressions/templates` | List saved templates |
| POST | `/api/admin/email/suppressions/templates` | Create `{name, description?, filter}` |
| PATCH | `/api/admin/email/suppressions/templates/[id]` | Partial update |
| DELETE | `/api/admin/email/suppressions/templates/[id]` | Remove |

#### Audience builder — UI components

- `audience-builder-tab.tsx` — combinator toggle (ALL / ANY), filter
  rows, big-number recipient count (Cake Mono Light 28px, olive
  `#9DB582`, `audienceCountVariants`), 10-row sample, saved-templates
  list.
- `audience-filter-row.tsx` — field/op/value editor backed by
  `audience-filter-config.ts` (`FIELD_OPTIONS`, `OP_OPTIONS`).
- `audience-save-template-modal.tsx` — name + description.
- "USE IN CAMPAIGN" dispatches a
  `CustomEvent('ops:audience-use-in-campaign')` with `{filter}`.
  `ScheduledSendsTab` listens, opens `CampaignCreateModal` with
  `audienceFilterOverride={filter}` — the modal swaps the segment
  dropdown for a "[custom predicate from audience builder]" stub and
  POSTs the predicate as `audienceFilter`.

#### Dispatcher integration (`src/app/api/cron/email/dispatcher/route.ts`)

When a campaign has `audience_template_id`, the dispatcher loads the
template's `filter`, calls `increment_audience_template_usage`
(errors logged, never throw), and dispatches via `resolveAudience` →
`email_audience_filter` RPC. Legacy starter segments
(`{segment: 'all_users' | 'trial_users' | 'active_subscribers'}`) still
flow through the hardcoded resolvers in `audiences.ts`. `estimateAudience`
uses the dedicated count RPC for predicate filters (cheaper than
fetching rows).

#### Tests

- Unit: `tests/unit/email/audience-filter.test.ts` (filter shape, 5
  tests), `tests/unit/email/suppressions-tab.test.tsx` (UI render, 3
  tests).
- Integration: `tests/integration/email-audience-rpc.test.ts` (live RPC,
  gated by `RUN_DB_INTEGRATION=1`).
- E2E: `tests/e2e/email-audience.spec.ts` (admin login fixture pending
  — `describe.skip`).

---

### §14.10 Campaign analytics (PR 6)

`/admin/email` → **Campaign Analytics** tab (2nd tab, after Overview). Lists
every campaign and lets each row expand inline to a detail panel with:

- **8 metric cards** (Cake Mono Light 28px numerics): Sent, Delivered (with
  bounce % secondary), Open rate, Click rate, CTOR, Spam, Unsub, Suppressed
  (with in-flight secondary). Cards stagger in at 60ms.
- **Animated Sankey funnel**: enqueued → dispatched → delivered → opened →
  clicked. Recharts `<Sankey>` with framer-motion `<motion.path>` linking
  pathLength 0→1 staggered 80ms per link. Empty state when fewer than 2
  stages have data.
- **Top-10 bouncing domains** as horizontal Recharts BarChart. First bar
  uses tan, remainder use steel-blue accent.
- **Template-version compare** card (`TemplateVersionCompareCard`) hidden
  when fewer than 2 versions sent. Side-by-side table comparing sent / open
  rate / click rate / bounce rate; winning column rendered olive.
- All animations honor `useReducedMotion()` — fall back to opacity-only.

#### Data flow

| Source | RPC | Returns |
|---|---|---|
| `email_campaigns` + `email_jobs` + `email_events` | `campaign_engagement_stats(p_campaign_id uuid)` | Single jsonb of all 16 metric values + `per_domain_bounce_summary` (top 10) |
| same | `campaign_funnel_stages(p_campaign_id uuid)` | One row per stage `(stage text, value bigint)` |
| `email_jobs` joined to `email_campaigns` (template_id = email_type) + `email_events` | `template_version_compare(p_email_type, p_version_a, p_version_b, p_since)` | jsonb with `versions[v]` keyed by version string |

All three RPCs are `SECURITY DEFINER`. EXECUTE revoked from `anon` and
`authenticated` — admin/service-role only.

Note on schema: `email_log` does NOT have `sg_message_id` — the version
compare RPC therefore sources from `email_jobs` (which carries
template_version, sg_message_id, status, recipient_email, created_at) and
joins `email_campaigns` to filter by `template_id = email_type`. Spam and
unsubscribe counts are derived from event aggregation since `email_campaigns`
has no counter columns for those events.

#### Routes

- `GET /api/admin/email/campaigns/[id]/engagement` — returns
  `{ ok, stats, funnel }`. UUID-validated (400 on invalid). 60s
  `Cache-Control: private, max-age=60`.
- `GET /api/admin/email/templates/[type]/versions/compare?a=X&b=Y&since=ISO`
  — returns `{ ok, result }`. 60s cache.
- `GET /api/admin/email/campaigns?include_versions=1` — extends PR 3's list
  route with `templateVersionsSent: string[]` per row by aggregating distinct
  `template_version` values from `email_jobs`.

Both new routes wrap `withAdmin` + `requireAdmin` and use Next.js 15 dynamic
route handler signature (`params: Promise<{...}>`, `await ctx.params`).

#### Migrations

| File | Effect |
|---|---|
| `098_email_log_template_version.sql` | Adds `template_version text` + partial index on `(email_type, template_version)` |
| `099_email_jobs_template_version.sql` | Adds `template_version text` + partial index on `(campaign_id, template_version)` |
| `100_campaign_engagement_rpcs.sql` | Adds `campaign_engagement_stats` + `campaign_funnel_stages` + 3 supporting indexes |
| `101_template_version_compare_rpc.sql` | Adds `template_version_compare` |

#### Motion variants

Centralized in `src/lib/utils/motion.ts`:
- `campaignMetricGridVariants` — 60ms stagger, 320ms duration
- `sankeyLinkVariants` — pathLength 0→1, 80ms stagger, 420ms duration
- `sankeyNodeVariants` — opacity + scale, 280ms
- `animatedCountVariants` — opacity + 4px lift

All use `EASE_SMOOTH` (`[0.22, 1, 0.36, 1]`).

#### Tests

- Unit: `tests/unit/email/campaign-query-mappers.test.ts` (3 tests — funnel
  numeric coercion + null/error handling).
- Unit: `tests/unit/email/campaign-detail-panel.test.tsx` (Sankey empty-state
  rendering — fewer than 2 stages collapses to tactical empty card).
- Integration: `tests/integration/campaign-engagement-route.test.ts`
  (3 tests — UUID validation, 404 on missing, 200 + 60s Cache-Control).

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
**Updated:** 2026-04-27 (Phase 1+2 visual + structural rework)
**Scope:** Complete rebuild of the OPS-Web calendar. Originally a 1119-line monolith; refactored into a modular component system. Phase 1+2 (2026-04-27) reworked the visual identity, view structure, and floating-UI portal layer.

### Phase 1+2 Visual + Structural Rework (2026-04-27)

The 22-task rework lives in `docs/superpowers/specs/2026-04-27-calendar-visual-structural-rework.md`. Key changes:

**View structure:** `Day · Week · Month · Crew` (was `Timeline · Month · Day`).
- `'timeline'` renamed to `'crew'` everywhere. Zustand persist v2 migrate function rewrites stored values on read; defensive fallback to `'week'` for unknown view values.
- New `Week` view: 7-column day stack (Mon–Sun, weekStartsOn: 1), all-day fallback layout reusing `<DayTaskCard>`. Hourly mode ships with Phase 3.
- `Crew` (formerly Timeline) folder/symbol/data-type rename: `timeline/` → `crew/`, `TimelineGrid` → `CrewGrid`, `useTimelineDnd` → `useCrewDnd`, `'timeline-event'` → `'crew-event'`, `'timeline-row'` → `'crew-row'`, `TIMELINE_*` → `CREW_*`.
- Default view for new users: `Week`.
- Mobile (<768px): `Day` forced (preserved).

**Card information design — three-source rule** (applied uniformly across Day, Week, Month, Crew, popovers):
| Slot | Source |
|---|---|
| Title (line 1) | `task.project?.title ?? task.customTitle ?? taskType.display` |
| Subtitle | `task.customTitle ?? taskType.display` (when distinct) |
| Body fill / border | `STATUS_COLORS[deriveTaskStatusKey(task)]` (status, not type) |
| Left accent stripe | `TASK_TYPE_COLORS[deriveTaskType(task)].border` |
| Type badge | `taskType.display` (Cake Mono Light, type colors) |
| Time label | `HH:mm → HH:mm` mono tabular-nums (only when `allDay = false`) |
| Crew avatars | `task.teamMemberIds[0..2]`, then `+N` |
| Site address | hover popover only |

**Status palette** (`TASK_STATUS_COLORS` in `calendar-constants.ts`) — earth-tone semantic translated to fill at low alpha:
| Status | Hex | Body fill | Border | Source |
|---|---|---|---|---|
| `scheduled` (active, future) | `#9DB582` olive | `rgba(157,181,130,0.10)` | `rgba(157,181,130,0.30)` | stored: 'active' |
| `in_progress` (start ≤ now ≤ end) | `#C4A868` tan | `rgba(196,168,104,0.12)` | `rgba(196,168,104,0.40)` | computed |
| `completed` | `#6A6A6A` mute | `rgba(106,106,106,0.08)` | `rgba(106,106,106,0.25)` | stored |
| `cancelled` | `#93321A` brick | `rgba(147,50,26,0.06)` | `rgba(147,50,26,0.40)` | stored |
| `overdue` (active AND end < now) | `#B58289` rose | `rgba(181,130,137,0.12)` | `rgba(181,130,137,0.40)` | computed |

`deriveTaskStatusKey()` in `calendar-utils.ts` does the computation. Production `project_tasks.status` only stores `'active' | 'completed' | 'cancelled'` — `in_progress` and `overdue` are derived from start/end vs `new Date()`.

**Crescent border fix:** Replaced `box-shadow: inset 3px 0 0 0 ${color}` with absolutely-positioned 3px sibling div with matching `border-radius: 4px 0 0 4px`. Inset box-shadow doesn't respect border-radius and produces a "crescent moon" artifact at the corners. Sibling-div approach yields pixel-perfect curve continuity. Applied uniformly across month-event-bar, day-task-card, crew-task-block.

**Today indicator (3 reinforcing signals):**
1. Day-cell number — 24×24 rounded-square (radius 4) with solid `var(--ops-accent)` fill and black text. Cake Mono Light 13px. Squares (not circles) — circles read as cute / startup, squares read as tactical.
2. Column accent line — `2px solid var(--ops-accent)` on the today column's `border-top` in Week, Crew, and Day header.
3. Toolbar `[ TODAY ]` pill — JetBrains Mono 11px tabular-nums, accent border + text, fills accent + black text on hover. Disabled when current view already includes today.

**Unscheduled tray promotion:**
- Promoted out of `filter-sidebar.tsx` to a first-class `<UnscheduledTray>` component
- Collapsed: 32px-wide vertical strip with rotated `// UNSCHEDULED [N]` label
- Expanded: 280px wide with search, group-by (project / client / type / none), sort (created / title / project), grouped scrollable card list
- **Day view: docks LEFT** (mirrors Jobber/Housecall convention). **Week / Month / Crew: docks RIGHT.**
- State persisted in `calendar-store`: collapsed flag, group-by, sort. Search session-scoped.
- `// UNSCHEDULED [N]` chip in calendar-toolbar toggles collapse.

**Popover layering rule (T16/T17/T18):**
- All floating UI portal-rendered to `document.body`
- Hover popover: Radix HoverCard, glass-dense, `var(--z-dropdown)` (1000), 12px radius. Replaces inline `EventTooltip` portal pattern.
- Context menu: Radix Popover with virtual anchor at right-click coords (preserves position-based API while gaining Radix focus / dismiss). Same z-layer + surface.
- Inline editor: portaled via `createPortal`, fixed positioning, `var(--z-floating-ui)` (1500) — above dropdowns since it's a focused editing affordance.
- Z-scale CSS custom properties added to globals.css and `.interface-design/colors_and_type.css`. See § 15 of 05_DESIGN_SYSTEM.md.

**Architecture (post-rework):**

The unified `InternalCalendarEvent` shape returned by `mapTaskToInternalEvent()` is the single source of truth. Consumers don't re-derive colors or titles. New fields:
- `projectTitle: string | null`
- `taskTitle: string`
- `typeLabel: string`
- `typeColors: { bg, border, text }` (TASK_TYPE_COLORS lookup)
- `statusColors: { bg, border, text }` (TASK_STATUS_COLORS lookup)
- `statusKey: TaskStatusKey`
- `crewIds: string[]`
- `address: string | null`
- `startTime / endTime: string | null` (Phase 3 provisioned)
- `allDay: boolean` (Phase 3 — currently always true; Phase 3 spec implements toggle)

**Original 2026-03-02 build below (kept for history; some details — view names, file paths — were superseded by the 2026-04-27 rework above).**

### Original Overhaul Notes (2026-03-02)

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
9. Job Board filtering and sorting (iOS — web replaced by Projects Spatial Canvas, see §6)
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

### Pipeline Execution (how Phase C actually runs)

Phase C kicks off from Phase B completion as fire-and-forget, and runs as a **chunked, self-dispatching pipeline** across multiple Vercel invocations. The pipeline is durable — state lives on the `gmail_scan_jobs` row between invocations, so a crash or timeout never loses progress.

**Routes:**

- `/api/integrations/email/analyze-memory` — entry. Bootstraps the pipeline (re-fetches threads, classifies, initializes state) then runs the first chunk batch.
- `/api/integrations/email/analyze-memory-continue` — self-dispatching continuation. Resumes from `state.startIndex` off the persisted `gmail_scan_jobs.result.phaseCPipeline`.

**Per-invocation budgets:** Vercel `maxDuration = 800s`; in-call chunk budget `CHUNK_TIME_BUDGET_MS = 550_000`. The 250s headroom covers either the finalize path (concurrency-2 writing-profile build, ~45–60s) or a continuation dispatch. Chunk size is 12 threads — small enough that a Lambda kill loses < 2 min of work.

**Row-level execution lock (migration `070_phase_c_row_lock.sql`):** Before running, each invocation acquires a row lock on the `gmail_scan_jobs` row via `acquire_phase_c_lock(jobId, "entry:<uuid>" | "continuation:<uuid>", 900)`. Contention means another runner is active — skip without retrying. Duplicate dispatches (webhook retry, user double-click on retry button, overlapping entry routes) are thus benign: the holding runner carries progress forward. Release happens inline before dispatching the next continuation (so the next runner can acquire immediately instead of racing the still-held lock), with an outer `finally()` as crash safety net. Release is fenced by holder ID, so the outer release is idempotent.

**Error marker:** On exception, `writePhaseCError` sets `result.phaseCError = { message, at, stage, failedAtIndex }` WITHOUT clearing `phaseCPipeline`. Wizard reads `(phaseCError && phaseCPipeline)` as "indexing paused — retry"; user retry re-POSTs the entry route, which detects existing pipeline state and dispatches a continuation from `state.startIndex` — no re-processed threads. Diverges from Phase B's terminal error pattern on purpose (Phase C has a native resume path). `finalizePhaseC` strips both `phaseCPipeline` and `phaseCError` on success so a stale error can't mislead the wizard.

**Finalize:** When `runPhaseCChunks` returns `done: true`, `finalizePhaseC()`:

1. Builds per-relationship-type writing profiles via `MemoryService.buildWritingProfiles()` — a concurrency-2 work-stealing pool (defined `CONCURRENCY = 2` at `memory-service.ts:1078`). Matches `email-ai-classifier.ts` to stay inside OpenAI tier-1 rate limits (~30k TPM on gpt-4o-mini; each profile call ~4–6k tokens). Work-stealing over lock-step batching because 2-sample vs 10-sample analyses have wide per-call latency variance.
2. Writes `result.phaseCStats = { factsExtracted, entitiesCreated, edgesCreated, profilesBuilt, profilesByTypeStats, processingTimeMs, threadsProcessed }`, sets `phaseCComplete: true`.
3. Strips `phaseCPipeline` (several-MB JSONB working buffer) and `phaseCError` from `result`.
4. Fires `notifications` row — `title: "Indexing complete"`, `action_url: "/intel"`.

**Validation (Canpro 2026 runs, same session, idempotency check):**

| Run | Threads | Facts | Profiles | Edges | Processing time |
|-----|---------|-------|----------|-------|-----------------|
| 1 | 143 | 432 | 4 | 166 | 21:17 |
| 2 | 157 | 267 new | 4 | 170 | 21:12 |

Run 2 against a largely overlapping thread set produced only incremental new facts (upserts are idempotent) with proportional new edges, confirming the chunked pipeline + row lock + upsert-safe DB writes deliver at-least-once semantics without duplicate accumulation.

**Helper module:** `OPS-Web/src/lib/api/services/phase-c-pipeline-helpers.ts` — `acquirePhaseCLock`, `releasePhaseCLock`, `writePhaseCError`, `buildPersistStateFn`, `dispatchPhaseCContinuation`, `finalizePhaseC`.

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
| `src/components/intel/galaxy-thread-density-halos.tsx` | Inbox v2 — ring halos around client nodes sized by thread count, colored by recency |
| `src/components/intel/hud/*.tsx` | Floating HUD overlays |
| `src/components/intel/node-info.tsx` | Tier 2/3 drill-down panel |
| `src/stores/intel-store.ts` | Zustand state |
| `src/lib/hooks/use-intel-graph.ts` | TanStack Query hook |
| `src/app/api/intel/graph/route.ts` | Graph API |
| `src/app/api/intel/entity/[entityId]/route.ts` | Entity detail API |

### Inbox v2 thread-density halos (added 2026-04-20)

Every CLIENT node in the galaxy carries a translucent ring rendered by `galaxy-thread-density-halos.tsx`. The ring encodes two signals:

- **Radius** = `log(thread_count) / log(26)` → min 0.18, max 0.95 (log scale so 1 vs 3 threads matters more than 20 vs 50)
- **Color** = recency of `last_message_at`:
  - `<= 24h` → `#6F94B0` (fresh — ops-accent blue)
  - `<= 7d` → `#9DB582` (warm — olive)
  - `<= 30d` → `#C4A868` (tepid — tan)
  - `> 30d` → `#6A6A6A` (cold — muted)
- **Opacity** = 0.28 → 0.60 on the same log scale
- **Interaction** = none — `raycast={() => null}` so pointer events pass through to the node hit targets

Data source: `public.get_inbox_density_per_client(p_company_id uuid)` RPC (migration 073), which returns `(client_id, thread_count, last_message_at)` for every client with active (`archived_at IS NULL`) threads in `email_threads`. Query refresh: 60s stale / 5 min interval. Rings are billboarded to the camera every frame.

---

## 19. In-App Email System (Web) — Inbox v2

### Overview

The OPS web inbox at `/inbox` is the operator panel for **Phase C**, OPS's AI executive-assistant agent. Every email — not just pipeline leads — flows through the inbox, gets AI-classified into one of thirteen primary categories, and is surfaced to the user with the right triage affordances (archive, snooze, recategorize, Phase C-drafted reply, etc.). Rebuilt 2026-04-20 (plan: `docs/superpowers/plans/...`, commits `f05627ff` → `2430fbdc`).

### Design intent

The previous inbox (§19 v1, 2026-03-19) was *pipeline-only* — only threads that already had an `opportunity_id` were visible, which meant every vendor, subtrade, legal, receipt, and internal email stayed in Gmail. The v2 rebuild makes the inbox Phase C's UI: the agent does the work (triage, classify, draft, follow up), the user reviews and overrides. Fyxer/Superhuman tier ergonomics are the explicit target.

### Data model

All thread state lives on the `email_threads` table. Messages still live on `activities` (unchanged). See §03_DATA_ARCHITECTURE.md for the full schema — tables `email_threads` and `email_thread_category_corrections` were added in migration `071_email_threads_and_corrections.sql` (2026-04-20).

### Cache-fill strategy

Inbox v2 is a **cache-first** design (Superhuman/Fyxer model): the inbox list is always served from `email_threads`, never from a live Gmail/M365 list call. Thread detail opens live-fetch the provider for full bodies, then fall back to `activities` on provider failure. Three pipelines populate the cache:

1. **Live delta sync** (`src/lib/api/services/sync-engine.ts`, Step 7.5) — every email flowing through `createActivity` is upserted into `email_threads` via `EmailThreadService.upsertFromEmail`, then classified. This is the steady-state path for mail arriving after the connection is linked.

2. **Activities backfill** (`migration 076_backfill_email_threads.sql`, 2026-04-20) — SQL-only, idempotent. Walks the existing `activities` table (filtered to real emails via `email_message_id IS NOT NULL`, skipping synthetic "Pipeline import:" rows), derives direction from `from_email = connection.email`, seeds `AWAITING_REPLY`/`HAS_ATTACHMENT` labels via the same regex heuristics as `evaluateLabelsFromMessages`, and upserts one row per unique `(connection_id, provider_thread_id)` pair. Covers everything in `activities` but misses mail that was never synced (e.g. non-opportunity-linked threads from before the v2 rebuild).

3. **Historical Gmail/M365 backfill** (`POST /api/inbox/backfill`, endpoint added 2026-04-20) — the missing Superhuman-style "on-connect full sync". Walks the provider's full mailbox via the new `EmailProviderInterface.listThreadIds({ pageSize, after, pageToken })` method — Gmail implementation uses `/messages?q=in:anywhere after:<epoch>` with `nextPageToken`, M365 uses `/me/messages?$select=conversationId&$orderby=receivedDateTime desc` with `@odata.nextLink`. For each thread not already cached, the endpoint pulls full content via `provider.fetchThread` and runs every message through `EmailThreadService.upsertFromEmail`. One call = one list page, processed end-to-end; clients loop until `completed: true`. Verified at 200–300 threads / ~100s per call — safe inside Vercel's 300 s limit on mailboxes up to a few thousand unseen threads. Classification is off by default; backfilled threads land as `OTHER` and get classified on the next inbound message or via explicit reclassify.

### Primary categories (exactly one per thread)

| Category | When it applies |
|----------|-----------------|
| `LEAD` | Potential customer inquiring about work, receiving a quote, in pre-win conversations |
| `CLIENT` | Existing/past customer — post-win, warranty, referrals, repeat work |
| `VENDOR` | Supplier selling materials/products TO the company |
| `SUBTRADE` | Another trade/crew pitching services or coordinating as a subcontractor |
| `PLATFORM_BID` | Automated bid invitations (Procore, BuilderTrend, PlanHub, SmartBidNet, BuildingConnected) |
| `LEGAL` | Lawyers, settlements, liens, disputes, insurance claims with legal implications |
| `JOB_SEEKER` | Someone seeking employment with the company |
| `COLLECTIONS` | AR disputes, overdue payment chases, credit agencies |
| `MARKETING` | Promotional emails, newsletters, cold outreach |
| `RECEIPT` | Transactional confirmations, shipping, order receipts, invoice copies |
| `PERSONAL` | Non-business correspondence |
| `INTERNAL` | Emails between employees of the company |
| `OTHER` | Does not fit any category |

Categories are **LAW** — adding / removing / renaming requires a migration and a plan-level decision.

### Secondary labels (multi-valued)

`URGENT` · `AWAITING_REPLY` · `HAS_ATTACHMENT` · `HAS_QUOTE` · `HAS_INVOICE` · `FROM_NEW_SENDER`. Also **LAW** — the classifier prompt and the UI chip set are keyed off this exact list.

### Split-inbox rails

The left rail of `/inbox` is a four-rail segmented control:

| Rail | Query | Keyboard |
|------|-------|----------|
| **Needs reply** | `labels @> '{AWAITING_REPLY}' AND archived_at IS NULL AND snoozed_until IS NULL` | `1` |
| **Everything** | `archived_at IS NULL AND snoozed_until IS NULL` | `2` |
| **Scheduled** | `snoozed_until IS NOT NULL AND snoozed_until > now()` | `3` |
| **Done** | `archived_at IS NOT NULL` | `4` |

Below the rails, a horizontal strip of **category filter chips** (ALL + 13 categories) narrows the active rail by `primary_category`.

### Thread classifier

- Service: `src/lib/api/services/thread-classifier-service.ts`
- Model: `gpt-5.4-mini` via `OPENAI_API_KEY_SYNC`
- Invocation: fire-and-forget from `EmailThreadService.upsertFromEmail` (sync step 7.5)
- Skip rule: only reclassify when `category_confidence < 0.6` or the thread is new; user corrections (`category_manually_set = true`) are never overwritten
- Learned rules: corrections keyed by `sender_domain` and `participants_hash` are fed back as priors so Phase C learns per-sender taxonomy
- Cost: ~$0.50–2.00 per 1000 threads at backfill; ~$0.30/week per active inbox

### Phase C autonomy router

`src/lib/api/services/phase-c-autonomy-router.ts` — runs after every classify and every new inbound on a classified thread. Dispatches per the per-category autonomy level stored in `email_connections.auto_send_settings.category_autonomy["primary:<CATEGORY>"]`.

| Level | Behavior |
|-------|----------|
| `off` | Phase C does nothing beyond classifying |
| `draft_on_request` | User can click "AI Draft"; no background work |
| `auto_draft` | Phase C drafts on every inbound, holds in `ai_draft_history` |
| `auto_send` | Phase C drafts + schedules via `AutoSendService` with business-hour delay |
| `auto_archive` | Phase C archives (RECEIPT / MARKETING / PLATFORM_BID reject) |
| `auto_follow_up` | LEAD/CLIENT — auto-nudge after configurable quiet days |

**Global AUTO_SEND gate:** The router caps any category-level `auto_send` / `auto_follow_up` to `auto_draft` behavior until the global Phase C autonomy level in `AutonomyMilestoneService` reaches AUTO_SEND (level 4). This prevents any email from being sent before the overall writing profile is proven.

**Allowed levels per category:**

| Category | Valid levels |
|----------|--------------|
| LEAD | off · draft_on_request · auto_draft · auto_send · auto_follow_up |
| CLIENT | off · draft_on_request · auto_draft · auto_send · auto_follow_up |
| VENDOR / SUBTRADE | off · draft_on_request · auto_draft · auto_send |
| PLATFORM_BID | off · draft_on_request · auto_draft · auto_send · auto_archive |
| LEGAL / COLLECTIONS / JOB_SEEKER | off · draft_on_request |
| MARKETING / RECEIPT / PERSONAL / INTERNAL / OTHER | off · auto_archive |

### Write-back preference

On the first archive action per connection, a modal asks: when I archive in OPS, what should happen in Gmail / Outlook?

| Value | Gmail | M365 |
|-------|-------|------|
| `archive_in_gmail` | Remove `INBOX` label | Move to Archive folder |
| `mark_read_only` | Add `READ` label (no INBOX change) | PATCH `isRead=true` |
| `ops_only` | No provider call | No provider call |
| `ask` *(default)* | First action forces the modal | First action forces the modal |

Persisted on `email_connections.archive_writeback_preference`. Snooze always removes the INBOX label regardless of preference; unsnooze re-adds it via the `/api/cron/unsnooze` cron (every 5 min).

### Keyboard shortcuts

| Key | Action |
|-----|--------|
| `j` / `↓` | Next thread |
| `k` / `↑` | Previous thread |
| `Enter` / `→` | Open selected |
| `e` | Archive |
| `s` | Snooze picker |
| `l` | Recategorize menu |
| `u` | Toggle read/unread |
| `r` | Reply |
| `⇧D` | Phase C AI draft |
| `c` | Compose new |
| `/` | Focus search |
| `⌘K` | Open command palette |
| `1` / `2` / `3` / `4` | Switch rail |
| `z` | Undo last toast action |
| `Esc` | Back to list |

### Command palette (⌘K)

Full-screen overlay built on `cmdk`. Type to fuzzy-search threads (live API query when ≥2 chars). Also exposes: archive / snooze / recategorize / mark unread / AI draft / compose new / switch rail / filter category. All commands collapse into the same keyboard flow as the inline shortcuts.

### Notifications

Fired from `EmailThreadService.classifyAndUpdate` post-hook:

| Event | Type | Persistent |
|-------|------|------------|
| Thread newly classified as LEAD | `leads_waiting` — "New lead: {sender}" | No |
| Thread newly classified as PLATFORM_BID | `leads_waiting` — "Platform bid: {platform}" | No |
| URGENT label appears on an inbound thread | `role_needed` — "Urgent reply needed: {sender}" | No |
| Category ready to graduate to auto_send | `ai_milestone` — persistent until user acts | Yes |

Graduation check runs daily via `/api/cron/phase-c-graduation-check`.

### Dashboard integration

Two widgets ship with Inbox v2:

1. `inbox-leads` — unread LEAD count + 7-day daily sparkline + median inbound-to-first-outbound response time. Clicks deep-link to `/inbox?category=LEAD&filter=needs_reply`.
2. `phase-c-autonomy` — weekly AUTO / DRAFTS / SURFACED tallies + per-category autonomy-level bars. Clicks deep-link to `/settings/email-category-autonomy`.

Registered in `src/lib/types/dashboard-widgets.ts` under category `alerts` with `requiredPermission: "inbox.view"`.

### Intel galaxy integration

Each CLIENT node in `/intel` carries a thread-density halo (billboarded ring). Radius scales `log(thread_count)`; color grades fresh → warm → tepid → cold by `last_message_at` recency. Fed by the `get_inbox_density_per_client(company_id)` RPC (migration 073).

### Permissions

All gating flows through `inboxModule` in `src/lib/types/permissions.ts`:

| Permission | Admin | Owner | Office | Operator | Crew |
|-----------|-------|-------|--------|----------|------|
| `inbox.view` | ✓ | ✓ | ✓ | ✓ | — |
| `inbox.view_company` | ✓ | ✓ | ✓ | — | — |
| `inbox.archive` | ✓ | ✓ | ✓ | ✓ | — |
| `inbox.snooze` | ✓ | ✓ | ✓ | ✓ | — |
| `inbox.categorize` | ✓ | ✓ | ✓ | — | — |
| `inbox.send` | ✓ | ✓ | ✓ | — | — |
| `inbox.configure_phase_c` | ✓ | ✓ | — | — | — |

### API surface

| Route | Method | Purpose |
|-------|--------|---------|
| `/api/inbox/threads` | GET | Paginated list (cursor-based, 30s refetch). Scope + rail + category + search query params. |
| `/api/inbox/threads/[id]` | GET | Thread detail incl. provider messages. Live-fetches Gmail/M365 for full bodies and derives direction server-side against the connection email; falls back to `activities` if the provider call fails. Each message carries `direction`, `bodyText`, and `cleanBodyText` (quoted reply chain stripped via `stripQuotedContent`). |
| `/api/inbox/threads/[id]` | PATCH | Actions: `archive` / `unarchive` / `snooze` / `unsnooze` / `recategorize` / `markRead`. |
| `/api/inbox/writeback-preference` | POST | Set `archive_writeback_preference` on a connection. |
| `/api/inbox/backfill` | POST | Pulls historical mailbox content into `email_threads` one list-page at a time. Provider-agnostic (Gmail `messages.list`, M365 `/me/messages`). Body: `{ connectionId, monthsBack?=12, maxPages?=1, startPageToken?, classify?=false, dryRun?=false }`. Response reports `threadsSeen / threadsAlreadyPresent / threadsBackfilled / messagesUpserted / nextPageToken / completed`. Idempotent via `(connection_id, provider_thread_id)` unique constraint — safe to re-run and interleave with live sync. Clients loop until `completed: true` or `nextPageToken: null`. |
| `/api/cron/unsnooze` | GET | 5-min cron — re-applies INBOX to snoozed threads past their `snoozed_until`. |
| `/api/cron/stale-leads` | GET | Hourly cron — invokes router on LEAD/CLIENT threads >7d quiet with outbound-last. |
| `/api/cron/phase-c-graduation-check` | GET | Daily cron — fires `ai_milestone` notifications for categories ready to graduate. |

### Key files

| File | Role |
|------|------|
| `src/app/(dashboard)/inbox/page.tsx` | Three-panel page layout + command palette + undo toast host |
| `src/components/ops/inbox/conversation-list.tsx` | Thread list (infinite query, hover actions, keyboard shortcuts) |
| `src/components/ops/inbox/thread-detail-view.tsx` | Center pane (header, Phase C strip, AI summary, messages, action bar) |
| `src/components/ops/inbox/thread-context-panel.tsx` | Right rail with Phase C insights |
| `src/components/ops/inbox/category-chip.tsx` | 13-category display chip + interactive (RecategorizeMenu trigger) |
| `src/components/ops/inbox/recategorize-menu.tsx` | Popover with all categories + "Tell Phase C why" note |
| `src/components/ops/inbox/split-inbox-tabs.tsx` | Four-rail segmented control |
| `src/components/ops/inbox/category-filter-chips.tsx` | Horizontal category filter strip |
| `src/components/ops/inbox/snooze-picker.tsx` | Presets + custom datetime picker |
| `src/components/ops/inbox/writeback-preference-modal.tsx` | First-archive preference modal |
| `src/components/ops/inbox/command-palette.tsx` | ⌘K overlay |
| `src/components/ops/inbox/undo-toast.tsx` | Portaled 5s undo toast + `z` hotkey |
| `src/components/ops/inbox/phase-c-status-strip.tsx` | Thread-top banner surfacing Phase C state |
| `src/lib/api/services/email-thread-service.ts` | Thread CRUD, classify dispatcher, notifications hook |
| `src/lib/api/services/thread-classifier-service.ts` | 13-category classifier (gpt-5.4-mini) |
| `src/lib/api/services/phase-c-autonomy-router.ts` | Per-category action router |
| `src/lib/api/services/phase-c-category-autonomy-service.ts` | Per-category level CRUD + graduation check |
| `src/lib/api/services/phase-c-learning-service.ts` | Apply corrections to similar threads |
| `src/lib/hooks/use-inbox-threads.ts` | TanStack Query hooks (list, detail, actions, unread count) |
| `src/lib/types/email-thread.ts` | TypeScript types + DB mapper |

### What replaced the old §19

The pre-rebuild inbox used `InboxService.getPipelineThreads()` (pipeline-only) and grouped threads into `InboxConversation` by client. Legacy files removed in Phase 7 cleanup: `inbox-service.ts`, `use-unified-inbox.ts`, `use-inbox.ts`, `unified-inbox.ts` types, and nine legacy inbox components. The `ComposeEmailModal` and thread message fetching via provider `fetchThread` are retained and reused by v2.

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

---

## 21. Blog & Content Marketing Pipeline

### Overview

OPS runs a fully automated weekly content pipeline orchestrated by Cowork scheduled tasks, with human review/veto checkpoints via Slack. The pipeline covers topic research → drafting → publishing → newsletter → social media generation → Instagram publishing. Jackson's only required actions are optional: pick a blog topic, approve/revise drafts, or veto social posts with a ❌ reaction. Everything else auto-fires on schedule.

### Weekly Cadence

Content is generated in two phases: blog on Saturday–Sunday, social on Sunday evening. Jackson reviews all social content in a single Sunday batch. Posts publish on their scheduled days throughout the week.

**Phase 1 — Blog (Saturday → Monday)**

| Day | Time | Task ID | What Happens | Slack Channel | Human Action |
|-----|------|---------|--------------|---------------|--------------|
| Saturday | 8:00 AM | `blog-topic-scout` | Researches trending trades topics, suggests 3–5 options | `#blog-drafts` | Pick a topic (or #1 auto-selects) |
| Sunday | 8:01 PM | `blog-auto-draft` | Writes full HTML post + newsletter + LinkedIn + image, saves as draft (`is_live=false`) | `#blog-drafts` | Approve, request revisions, or ignore (auto-publishes Mon) |
| Monday | 5:09 AM | `blog-auto-publish` | Sets `is_live=true` + `published_at` if approved or no response | `#blog-drafts` | None (or request revisions to hold) |
| Tuesday | 10:00 AM | `blog-newsletter-sender` | Sends newsletter for posts published in last 6 days, checks `email_log` for dupes | `#blog-drafts` | None |

**Phase 2 — Social Content Batch (Sunday evening → week)**

All social content is generated Sunday evening and posted to `#social-media` for batch review. Each post includes a `publish_day` tag. Jackson reviews everything at once on Sunday night.

| Day | Time | Task ID | What Happens | Publishes | Slack Channel |
|-----|------|---------|--------------|-----------|---------------|
| Sunday | 8:30 PM | `social-blog-promo` | IG carousel (4–5 slides, 1080×1350) + LinkedIn post from blog draft | Monday 9 AM | `#social-media` |
| Sunday | 8:45 PM | `opp-weekly` | OPS Performance Protocol graphic (1080×1080) + caption | Thursday 9 AM | `#social-media` |
| Sunday | 9:00 PM | `social-feature-release` | Even ISO weeks: feature carousel (3–5 slides, 1080×1350) | Wednesday 9 AM | `#social-media` |
| Sunday | 9:00 PM | `social-insight` | Odd ISO weeks: data insight graphic (1080×1080) | Wednesday 9 AM | `#social-media` |

**Phase 3 — Scheduled Publishing**

| Day | Time | Task ID | What Publishes |
|-----|------|---------|----------------|
| Monday | 9:00 AM | `social-auto-publish` | Blog carousel → Instagram |
| Wednesday | 9:00 AM | `social-auto-publish` | Feature release or Insight → Instagram |
| Thursday | 9:00 AM | `social-auto-publish` | OPP → Instagram |

### Approval / Veto Mechanics

- **Blog drafts:** Post to `#blog-drafts`. "approve" publishes immediately. Revision requests hold the post. No response → auto-publishes Monday 5 AM.
- **Social posts:** All generated Sunday evening, posted to `#social-media` with scheduled publish day. ❌ reaction kills the post. Text replies with revisions trigger re-generation. Posts publish on their scheduled day at 9 AM unless killed. Jackson reviews the entire week's content in one Sunday session.
- **Newsletter:** Fully automatic. Checks `app_settings.blog_newsletter_enabled` kill switch and `email_log` for duplicate prevention. No approval needed.

### Architecture Components

| Component | Location | Purpose |
|-----------|----------|---------|
| Blog Admin Dashboard | `OPS-Web/src/app/admin/blog/page.tsx` | Manual list, create, edit, delete posts |
| Blog Post Editor | `OPS-Web/src/app/admin/blog/_components/blog-post-editor.tsx` | Rich text editor with FAQ, slug, categories |
| Image Upload Route | `OPS-Web/src/app/api/admin/blog/upload/route.ts` | Uploads to `images` bucket at `blog/{timestamp}-{random}.{ext}` |
| Public Blog (OPS-Web) | `OPS-Web/src/app/blog/page.tsx`, `[slug]/page.tsx` | ISR-cached public rendering, JSON-LD schema |
| Public Blog (ops-site) | `ops-site/src/lib/blog.ts` | Static marketing site reads same `blog_posts` table |
| Blog API | `OPS-Web/src/app/api/blog/posts/route.ts` | GET (list), POST (create), PUT (update) |
| Newsletter API | `OPS-Web/src/app/api/blog/newsletter/route.ts` | Send post to subscribers via SendGrid |
| Scheduled Tasks | `~/Documents/Claude/Scheduled/` | Cowork automation — 11 tasks orchestrate the full pipeline |

### Database Tables

**`blog_posts`** — Core content table:
- `id` (uuid pk), `title`, `subtitle`, `slug` (unique), `author`, `content` (HTML), `summary`, `teaser`, `meta_title`
- `thumbnail_url` — public URL in `images` bucket
- `category_id`, `category2_id` — FK to `blog_categories`
- `is_live` (boolean) — draft/published toggle
- `display_views` (int), `word_count` (int)
- `faqs` (jsonb) — array of `{question, answer}` for FAQ schema
- `published_at`, `created_at`, `updated_at`

**`blog_categories`** — `id`, `name`, `slug` (unique), `created_at`

**`blog_topics`** — Content idea backlog: `id`, `topic`, `author`, `image_url`, `used` (boolean), `created_at`, `updated_at`

**`newsletter_subscribers`** — `id`, `email` (unique), `first_name`, `source`, `is_active`, `subscribed_at`, `unsubscribed_at`

**`newsletter_content`** — Monthly product update emails: `id`, `month`, `year`, `shipped` (array), `in_progress` (array), `bug_fixes` (array), `coming_up` (array), `custom_intro`, `custom_outro`, `status`, `created_at`, `updated_at`

**`email_log`** — Audit trail: `id`, `user_id`, `email_type`, `recipient_email`, `subject`, `sent_at`, `status`, `error_message`, `metadata` (jsonb)

**`app_settings`** — Kill switches: `key` (text pk), `value` (jsonb), `updated_at`. Key `blog_newsletter_enabled` gates newsletter sends.

### Storage Conventions

| Bucket | Public | Purpose | RLS |
|--------|--------|---------|-----|
| `images` | Yes | Blog thumbnails, in-post images | Anon read; admin write via upload route |
| `social-media` | Yes | Generated social graphics | Anon upload restricted to generator paths |

- Blog thumbnails: `images/blog-thumbnails/{name}.webp`
- In-post images: `images/blog/{timestamp}-{random}.{ext}`
- Social images: `social-media/{prefix}/{timestamp}/slide_*.png`

### Auth Gating

Blog admin routes require Firebase auth + `isAdminEmail()` check (`verifyAdminAuth`). Public `/blog/*` routes and ops-site reads are unauthenticated. Newsletter send requires Bearer token (`BLOG_API_KEY` env var).

### Public Rendering

Both OPS-Web and ops-site render the same `blog_posts` data:
- **OPS-Web** `/blog/[slug]` — ISR with 300s revalidation, full OpenGraph/Twitter cards, JSON-LD Article + FAQPage schema
- **ops-site** — static build via `getLatestPosts()`, `getPostBySlug()` from `ops-site/src/lib/blog.ts` (service role key)

### Newsletter Flow (Automated)

1. `blog-newsletter-sender` fires Tuesday 10 AM
2. Queries Supabase for blog posts published in last 6 days
3. Checks `email_log` to prevent duplicate sends
4. Verifies `app_settings.blog_newsletter_enabled` kill switch
5. Calls `POST /api/blog/newsletter` with `post_id`
6. Route queries `newsletter_subscribers` where `is_active = true`
7. Sends via SendGrid using post's `title`, `teaser`, `thumbnail_url`, `content`
8. Logs each send to `email_log` with status and error
9. Posts status summary to `#blog-drafts` (sent count, errors, or skip reason)

---

## 22. Social Media Generation & Publishing

### Overview

Social media assets are generated by Cowork scheduled tasks using Python CLI scripts, uploaded to Supabase Storage, reviewed via Slack, and auto-published to Instagram via an edge function. The pipeline is fully automated with a human-veto model: content posts to `#social-media` for review, and auto-publishes after a 6-hour window unless killed with ❌.

### Social Generators

Located at `OPS-Web/scripts/social-generators/`:

| Generator | CLI Entry | Output | Dimensions |
|-----------|-----------|--------|------------|
| `carousel_generator.py` | `--post-number --title --subtitle --slug --slides --thumbnail` | Multi-slide PNG set (title + content + CTA) | 1080×1350 (4:5) |
| `feature_generator.py` | `--feature-name --tagline --slides --version --slug` | Multi-slide PNG set (update/feature announcement) | 1080×1350 (4:5) |
| `insight_generator.py` | `--headline --stat --stat-label --stat-color --context --source --output` | Single PNG (data insight card) | 1080×1080 (1:1) |
| `opp_generator.py` | `--number --title --lines` | Single PNG (field manual style) | 1080×1080 (1:1) |

All generators:
- Use the OPS portal color palette: `C_SUCCESS` (#9DB582), `C_NEGATIVE` (#B58289), `C_ALERT` (#C4A868)
- Support inline color markup: `{green:+32%}` renders colored text
- Require fonts at `$OPS_FONT_DIR` (default `OPS-Web/public/fonts`): Kosugi-Regular, Mohave-Bold, Mohave-Regular
- Output PNGs to local disk; scheduled tasks handle upload automatically

### Upload Utility

`supabase_upload.py` — Uploads generated PNGs to the `social-media` bucket.

```
python supabase_upload.py --prefix blog-carousel slide_1.png slide_2.png
```

Returns public URLs: `https://ijeekuhbatykdomumfjx.supabase.co/storage/v1/object/public/social-media/{prefix}/{timestamp}/slide_*.png`

Auth: Uses anon key (hardcoded in file, lines 25–26). RLS restricts anon uploads to generator-convention paths within `social-media` bucket.

### Automated Social Content Schedule

**Sunday Generation Batch** — all content created and posted to `#social-media` for review:

| Task ID | Generates At | Content Type | Publishes | Frequency |
|---------|-------------|-------------|-----------|-----------|
| `social-blog-promo` | Sunday 8:30 PM | Blog carousel (4–5 slides) + LinkedIn post | Monday 9 AM | Weekly |
| `opp-weekly` | Sunday 8:45 PM | OPS Performance Protocol graphic (square) | Thursday 9 AM | Weekly |
| `social-feature-release` | Sunday 9:00 PM | Feature/update carousel (3–5 slides) | Wednesday 9 AM | Biweekly (even ISO weeks) |
| `social-insight` | Sunday 9:00 PM | Data insight graphic (square) | Wednesday 9 AM | Biweekly (odd ISO weeks) |

**Scheduled Publishing** — `social-auto-publish` runs Mon/Wed/Thu at 9 AM, publishing only posts tagged for that day.

Each generator task: creates content → runs brand voice enforcement → uploads to Supabase Storage → posts to `#social-media` (C0ASCNEHMAS) with publish metadata JSON (`publish_day`, `urls`, `caption`) for the auto-publisher to read.

### Instagram Publishing

Edge function: `OPS-Web/supabase/functions/social-publish-instagram/index.ts`

**Trigger:** Called by `social-auto-publish` scheduled task (Mon/Wed/Thu 9 AM) or manual HTTP POST.

**Required Secrets** (set in Supabase Dashboard → Edge Functions):
- `INSTAGRAM_ACCESS_TOKEN` — Long-lived Meta user token (60-day expiry)
- `INSTAGRAM_USER_ID` — IG Business Account ID
- `SOCIAL_PUBLISH_SECRET` — Bearer token for auth

**Request:**
```json
{
  "image_urls": ["https://...social-media/...slide_01.png"],
  "caption": "Post caption #OPS",
  "post_type": "carousel" | "single"
}
```

**Workflow:**
1. Single image → create container → poll until ready → publish
2. Carousel (2–10 images) → create child containers in parallel → create carousel container → poll → publish
3. Polling: up to 60s (20 attempts × 3s) per container
4. Returns `X-Token-Warning` header when token expiry < 7 days

**Response:**
```json
{
  "success": true,
  "post_id": "17999...",
  "type": "carousel",
  "image_count": 5,
  "token_days_remaining": 45
}
```

### Auto-Publish Logic (`social-auto-publish`)

Runs Mon/Wed/Thu at 9 AM. Checks `#social-media` for posts tagged with today's `publish_day` and applies these rules:
1. **❌ reaction** → post is killed, not published
2. **Replacement image attached** → re-uploads and uses new image
3. **Text revision reply** → re-generates caption or swaps content
4. **No `publish_day` match** → skipped (not scheduled for today)
5. **No objection** → publishes via `social-publish-instagram` edge function
6. Posts summary to `#social-media` only if activity occurred (publish, skip, or kill)
7. **Legacy posts** (no `publish_day` metadata) → treated as immediately eligible if 6+ hours old, for backward compatibility

### Known Gaps

1. **No social queue table** — published posts are tracked only via Slack history. No DB record of what was generated, when, or the resulting IG post ID.
2. **No web admin notifications** — no OPS-Web rail notification for pipeline events. All status reporting goes to Slack.
3. **No retry logic** — if Instagram publish fails, the `social-auto-publish` task reports the error to Slack but does not automatically retry on next run.
4. **No draft preview** — blog posts only visible publicly when `is_live = true`.
5. **Hardcoded anon key** in `supabase_upload.py` — should use env var.
6. **Token management** — Instagram token expires every 60 days. `social-auto-publish` checks the `X-Token-Warning` header and posts a warning to Slack when < 7 days remain, but there is no auto-refresh. Jackson must manually rotate the token via Meta Developer Console.
7. **Missing migration files** — `newsletter_subscribers`, `newsletter_content`, `email_log`, and `app_settings` tables exist in Supabase but have no corresponding migration files in the repo. Should be captured in migrations for reproducibility.

---

## iOS Core Spotlight Indexing (2026-04-14)

The iOS app indexes user-accessible data into iPhone Spotlight so OPS records appear in the system-wide search. Projects, Clients, Tasks, Invoices, and Estimates are indexed with thumbnails, phone-number / email metadata, and permission gating. Search works offline (the index is on-device), and taps route into the app via the existing deep-link notification system.

### Architecture

- `SpotlightIndexManager` (`OPS/OPS/Services/Spotlight/SpotlightIndexManager.swift`) — singleton, permission-gated index writer. Bulk backfill + per-entity incremental methods with scope-aware removal.
- `SpotlightItemBuilder` — converts SwiftData entities to `CSSearchableItem`
- `SpotlightThumbnailRenderer` — produces 256×256 JPEG thumbnails from cached project images / client avatars, with SF Symbol fallbacks
- `SpotlightSyncTracker` — collects per-sync-pass dirty / deleted entity IDs so incremental updates are targeted, not full re-indexes
- `SpotlightBackfillCoordinator` — runs the initial indexing pass with a live iOS local notification showing progress, under a `UIBackgroundTask` so it survives app-background mid-run
- `SpotlightTapRouter` — handles `CSSearchableItemActionType` continuations, re-checks permissions, routes to detail views via existing `OpenXxxDetails` notifications
- `SpotlightDomainIdentifiers` — domain identifier constants (`co.opsapp.spotlight.project` etc.) used for targeted removal and tap decoding
- `AccessDeniedSheet` — shown when a tapped result is no longer permitted (e.g. role changed after indexing)

### Trigger points

- **Initial backfill:** after first successful full sync post-login, via `SpotlightBackfillCoordinator.runIfNeeded(context:)` called from `DataController` login flow
- **Incremental updates:** after every `InboundProcessor.linkAllRelationships` — dispatches the `SpotlightSyncTracker` diff (upserts + removals). Every merge method for an indexed entity (project, client, task, invoice, estimate) calls `markDirty` or `markDeleted` based on whether the server soft-deleted the entity.
- **Role change:** when `PermissionStore.fetchPermissions` detects a new `roleId`, posts `SpotlightReindexRequested` notification → MainTabView clears and re-runs backfill
- **Logout:** `DataController.logout()` clears the entire index via `SpotlightIndexManager.clearAll()`

### Permission gates (index time + tap time)

Using the existing `PermissionStore` keys:
- `projects.view` → Projects + Tasks (tasks inherit projects gate)
- `clients.view` → Clients
- `pipeline.view` → Invoices + Estimates (same gate as the Money tab where these live)
- `estimates.view` → Estimates (also honored if a role grants it without pipeline access)

Field crew (without `hasFullAccess("projects.view")`) only gets their assigned projects / tasks indexed. Projects in RFQ/Estimated status are hidden from users without `pipeline.view`.

**Permission checks happen twice:** at index time (we only write items the user is allowed to see) AND at tap time (in `SpotlightTapRouter`, in case the role changed between indexing and the tap). A tapped result the user is no longer permitted to see shows the `AccessDeniedSheet`.

### Domain identifiers

- `co.opsapp.spotlight.project`
- `co.opsapp.spotlight.client`
- `co.opsapp.spotlight.task`
- `co.opsapp.spotlight.invoice`
- `co.opsapp.spotlight.estimate`

Item IDs are `"<domain>:<entityId>"` — decoded on tap to determine which entity type to open.

### Deep linking

Spotlight taps post the same notifications used by push notifications and universal links:
- `OpenProjectDetails` / `OpenClientDetails` / `OpenTaskDetails` / `OpenInvoiceDetails` / `OpenEstimateDetails`

`MainTabView` observes each and routes to the appropriate detail sheet via `AppState`:
- `showClientDetails` → `ClientSheet(mode: .edit(client))`
- `showInvoiceDetails` → `InvoiceDetailViewDeepLinkWrapper`
- `showEstimateDetails` → `EstimateDetailViewDeepLinkWrapper`
- `showAccessDenied` → `AccessDeniedSheet`

The `ops://` URL scheme is registered in Info.plist for direct deep-link access: `ops://projects/{id}`, `ops://clients/{id}`, `ops://invoices/{id}`, `ops://estimates/{id}`. Handled in `AppDelegate.application(_:open:options:)`.

### Thumbnails

- **Projects:** first cached image from `ImageFileManager.shared` (`Documents/ProjectImages/`) — iterates through all cached images until one renders successfully, falling back to a briefcase SF Symbol
- **Clients:** avatar from `ClientAvatarCache.shared` (`Documents/ClientAvatars/`) — **new in this release**, required because avatars were previously memory-only. Falls back to `person.crop.circle.fill`.
- **Tasks:** parent project's thumbnail, or `checklist` SF Symbol
- **Invoices / Estimates:** SF Symbols (`doc.text.fill` / `doc.plaintext.fill`)
- All rendered at 256×256 JPEG quality 0.7

### Invoice & Estimate local persistence (companion architectural change)

Previously invoices, estimates, line items, and payments were fetched on-demand from Supabase via `InvoiceViewModel` / `EstimateViewModel` and held in in-memory `@Published` arrays. This meant they did not work offline and had no sync chokepoint for Spotlight indexing.

**Now they are locally persisted in SwiftData via `InboundProcessor`.** The sync engine pulls these entities with field-level merge (respecting pending `SyncOperation`s), same pattern as Projects/Clients/Tasks. View models are thin filter/action layers that read from SwiftData via explicit `@Query` or `FetchDescriptor`.

Sync order: `.estimate` before `.invoice` because invoices can reference estimates via `estimate_id`.

Call sites that previously used `invoiceVM.setup(companyId:)` / `estimateVM.setup(companyId:)` now pass a `modelContext`: `setup(companyId:modelContext:)`.

### Caps & scaling

No arbitrary caps — Core Spotlight scales to millions of items. Bulk-index methods sort by `updatedAt` / `lastSyncedAt` descending so that if Spotlight ages items out under memory pressure, the most-recently-touched ones stay.

### Known limitations (2026-04-14)

1. **Universal links not wired** — the `applinks:app.opsapp.co` entitlement is not set up. Web-based deep links would need this added. For now, only the `ops://` scheme is supported.
2. **Task deep-link context** — task details require a parent project ID. A tap on a Spotlight task result currently routes via `OpenTaskDetails` without the project context; MainTabView falls back to opening the project. A future enhancement can encode both IDs in the Spotlight item identifier.
3. **Tests not automated** — Core Spotlight has no test-accessible read API. See `OPS/OPS/Services/Spotlight/SPOTLIGHT_MANUAL_TESTS.md` for the manual checklist.

---

## Auth Action Handler (Firebase OOB)

**Location:** `OPS-Web/src/app/(auth)/auth/action/page.tsx`
**URL:** `https://app.opsapp.co/auth/action`
**Firebase config:** `notification.sendEmail.callbackUri` set to the above URL via Identity Toolkit admin API (`OPS-Web/scripts/firebase/update-auth-config.ts`).

### What it handles

Every Firebase Auth out-of-band (OOB) email link points at this page. Four modes, one page, one card:

1. `mode=resetPassword` → `ResetFlow.tsx` — validates via `verifyPasswordResetCode`, collects new password with strength meter, submits via `confirmPasswordReset`.
2. `mode=verifyEmail` → `VerifyFlow.tsx` — applies the action code via `applyActionCode`.
3. `mode=recoverEmail` → `RecoverFlow.tsx` — shows old/new email confirmation, applies the action code to revert.
4. `mode=signIn` → `SignInFlow.tsx` — email-link sign-in (dormant; no flow currently emits email-link sign-in links).

### Visual design

The handler page is a product surface, not a marketing surface. It uses the OPS-Web interface design system directly: `background #000000`, frosted-glass card `rgba(10,10,10,0.70) + backdrop-blur(20px) saturate(1.2)`, `ops-accent #597794`, Mohave + Kosugi, 2.5px button radius, 5px card radius, borders-only depth, `cubic-bezier(0.22, 1, 0.36, 1)` easing. Every field-first rule applies: 60pt touch targets, 16px+ text, no spinner spam, graceful reduced-motion.

### Smart-split success flow

After a successful action, the page detects `navigator.userAgent`:

- **iOS** → primary CTA `OPEN OPS` → `https://app.opsapp.co/open?from=<action>` (Universal Link → iOS app opens → Keychain auto-fills the new password)
- **Android / Desktop** → primary CTA `SIGN IN ON WEB` → `/login`

iOS Keychain autofill works because `webcredentials:app.opsapp.co` is declared in `OPS/OPS/OPS.entitlements`.

### Web-to-app bridge (`/open`)

`OPS-Web/src/app/(auth)/open/page.tsx` is a Universal Link landing page. iOS intercepts the path via the AASA file and hands it to `OPSApp.swift`'s `handleUniversalLink` function, which posts `OpenAppFromWeb` notification. If the iOS app isn't installed, the page renders a fallback with App Store link and "Continue on web" options.

### Ship sequence

Never flip Firebase `callbackUri` without first: (1) shipping the handler page to production, (2) deploying the AASA update at least 24h earlier, (3) shipping the iOS app update with the `/open` route handler. The config update script read-back-verifies the flip; rollback is a single API call reverting `callbackUri` to the Firebase default.

### Key files

| File | Role |
|---|---|
| `OPS-Web/src/app/(auth)/auth/action/page.tsx` | Route + mode dispatcher |
| `OPS-Web/src/app/(auth)/auth/action/HandlerShell.tsx` | Card visual shell |
| `OPS-Web/src/app/(auth)/auth/action/ResetFlow.tsx` | Password reset state machine |
| `OPS-Web/src/app/(auth)/auth/action/VerifyFlow.tsx` | Email verify |
| `OPS-Web/src/app/(auth)/auth/action/RecoverFlow.tsx` | Email recovery |
| `OPS-Web/src/app/(auth)/auth/action/SignInFlow.tsx` | Email-link sign-in |
| `OPS-Web/src/app/(auth)/auth/action/HandlerError.tsx` | 6 error kinds |
| `OPS-Web/src/app/(auth)/auth/action/SuccessState.tsx` | Smart-split success |
| `OPS-Web/src/app/(auth)/auth/action/copy.ts` | Locked ops-copywriter voice strings |
| `OPS-Web/src/app/(auth)/open/page.tsx` | Web-to-app bridge fallback |
| `OPS-Web/public/.well-known/apple-app-site-association` | AASA with `/open` patterns |
| `OPS/OPS/OPSApp.swift` (line ~283) | iOS `handleUniversalLink` dispatcher |
| `OPS-Web/scripts/firebase/update-auth-config.ts` | Firebase config update script |
| `OPS-Web/scripts/firebase/firebase-stock-templates.ts` | Handcrafted HTML for stock templates |

---

### §14.11 Email template preview + versioning (PR 7)

Every typed email template carries a `// @template-version: X.Y.Z` comment as
its first line plus an exported `previewProps` const. The build-time script
`npm run email:sync-versions` (chained to `prebuild`) reads each template,
computes sha256 of the source, and upserts to `email_template_versions`. If
the same `(template_id, version)` already exists with a different hash, the
build fails — bumping the version is required to ship a copy change.

The script no-ops when `SUPABASE_URL` / `SUPABASE_SERVICE_ROLE_KEY` aren't
present (logs a warning), so local builds work without touching the DB. CI /
Vercel builds set `SYNC_REQUIRE_DB=1` along with the credentials to enforce
the contract — missing env then exits 1.

**Tables:**

- `email_template_versions` — append-only registry. `(template_id, version)`
  unique. Stores `content_hash`, `rendered_sample_html`, `preview_props`.
  No UPDATE/DELETE for non-service-role roles.
- `email_campaigns.template_version` — column added so analytics can compare
  open/click rates between template versions.

**Admin UI:**

- `/admin/email/templates` — list of all 17 templates with current version
  and version count.
- `/admin/email/templates/[templateId]` — three sub-tabs:
  - **Preview**: edit JSON props in a textarea, iframe re-renders 600ms
    debounced via `POST /api/admin/email/templates/[id]/preview`.
  - **Versions**: accordion timeline; each version's `rendered_sample_html`
    is shown in an inline iframe.
  - **Send Test**: send the rendered template to any recipient. Logged
    with `email_log.metadata.is_test=true` and `metadata.via='admin_test'`.
- A "Templates" sub-tab on `/admin/email` links into the registry.

**Suppression:** test sends use the back-compat shim `sendTransactionalEmail`,
which flows through `gatedSend`'s suppression check. Operators who need to
send to a suppressed address must remove the suppression first via
`DELETE /api/admin/email/suppressions/[email]`.

**Key files:**

| File | Role |
|---|---|
| `OPS-Web/supabase/migrations/102_email_template_versions.sql` | Append-only registry table |
| `OPS-Web/supabase/migrations/103_email_campaigns_template_version.sql` | `email_campaigns.template_version` column |
| `OPS-Web/src/lib/email/template-registry.ts` | 17-entry typed registry + `renderTemplate` |
| `OPS-Web/scripts/email-template-version-sync.ts` | Build-time sync script |
| `OPS-Web/src/lib/admin/email-template-queries.ts` | Server-side list/detail queries |
| `OPS-Web/src/app/api/admin/email/templates/route.ts` | GET list |
| `OPS-Web/src/app/api/admin/email/templates/[templateId]/route.ts` | GET detail |
| `OPS-Web/src/app/api/admin/email/templates/[templateId]/preview/route.ts` | POST props → HTML |
| `OPS-Web/src/app/api/admin/email/templates/[templateId]/send-test/route.ts` | POST recipient + props → SendGrid + log |
| `OPS-Web/src/app/admin/email/templates/page.tsx` | List page |
| `OPS-Web/src/app/admin/email/templates/[templateId]/page.tsx` | Detail page (3 sub-tabs) |
| `OPS-Web/src/components/admin/email/template-preview-tab.tsx` | JSON editor + 600ms-debounced iframe |
| `OPS-Web/src/components/admin/email/template-versions-tab.tsx` | Accordion of stored renders |
| `OPS-Web/src/components/admin/email/template-send-test-tab.tsx` | Send-to-self with prop overrides |

---

### §14.12 Event Monitor + Anomaly Alerts (PR 8)

Live operational dashboard inside `/admin/email?tab=event-monitor` plus a
5-minute cron that detects deliverability anomalies, writes an
audit-grade log, fires notification rail entries, and — for critical
bounce / spam spikes — auto-pauses global sending via PR 4's `pause()`.

**Thresholds** (`src/lib/email/anomaly-thresholds.ts`):

| Kind | Warn | Critical | Notes |
|---|---|---|---|
| `bounce_spike` | bounce_pct ≥ 5% | bounce_pct ≥ 10% | Min 5 sends/window |
| `spam_spike` | spam_pct ≥ 0.1% | spam_pct ≥ 0.5% | Min 5 delivered/window |
| `delivery_drop` | delivered/sent < 80% | < 60% | Min 5 sends/window |
| `volume_drop` | sent/baseline < 10% | < 1% | Requires 60-min baseline |

The pure `evaluateThresholds(snapshot)` returns the full list of breaches.
`MIN_SENDS_FOR_PCT = 5` suppresses noise from tiny windows.

**Anomaly cron — `/api/cron/email/anomaly-check` (every 5 min):**

1. Calls `email_event_metrics(15)` + `email_event_metrics(60)` (baseline).
2. Runs `evaluateThresholds`.
3. Reads recent `email_anomaly_log` (60 min) — dedup map keyed by `kind`.
4. Skips evals where same kind already logged at ≥ severity within 60 min.
5. Inserts new anomaly into `email_anomaly_log`.
6. For `severity = critical` AND kind ∈ {`bounce_spike`, `spam_spike`}:
   calls `pause('global', reason, severity='critical', anomalyLogId=<id>)` —
   actor identity from `PMF_OPERATOR_USER_ID` / `PMF_NOTIFICATION_EMAIL`.
7. Inserts `notifications` row (type `email_anomaly`) — persistent for
   critical, dismissible for warn. `action_url = /admin/email?tab=event-monitor`.
8. Updates the anomaly row with `pause_audit_id`, `notification_id`,
   `action_taken` (human-readable description).

**Action chain (auditable in SQL):**

```
email_anomaly_log.id
    │
    ├── notification_id    → notifications.id (rail entry)
    ├── pause_audit_id     → email_pause_audit_log.id
    │       │
    │       └── (where action='pause', severity='critical',
    │            anomaly_log_id=email_anomaly_log.id ← back-pointer)
    │
    └── action_taken        (text describing the chain)
```

**Tables / RPCs:**

- `email_anomaly_log` — append-only log. Indexed `(kind, detected_at DESC)`,
  partial `(... WHERE resolved_at IS NULL)`. UPDATE/DELETE revoked from
  non-service roles.
- `email_pause_audit_log` — extended in PR 8 with optional `severity` +
  `anomaly_log_id` columns. Manual pauses from killswitch admin route leave
  both NULL; cron pauses populate both.
- `email_event_metrics(p_minutes_back, p_bucket)` — SECURITY DEFINER, returns
  JSONB blob: `{window_minutes, total_sent, total_delivered, total_bounced,
  bounce_pct, total_spam, spam_pct, total_open, open_pct, total_click,
  click_pct, error_events, by_minute[]}`. Bucket sizes: `1m | 5m | 15m | null`.
- `email_top_bounce_domains(p_minutes_back, p_limit)` — SECURITY DEFINER,
  returns `(domain, bounce_count, bounce_pct)` ordered DESC.
- `idx_email_events_timestamp_event` — composite covering index on the
  metrics RPC hot path.

**Admin UI — Event Monitor tab:**

| Component | Role |
|---|---|
| `BounceGauge` | Semicircular SVG arc 0..15% with green/yellow/red zones. Needle animates with `EASE_SMOOTH` over 0.6s. Always 15-min window regardless of UI filter. |
| `MonitorMetricBar` | 6 metric cards (sent / delivered / bounced / spam / opened / clicked) with 60-min sparklines from `by_minute` buckets. JetBrains Mono `tnum`. |
| `EventStream` | AnimatePresence list, last 50 rows, polls every 5s while visible. Each row colored by event type. |
| `TopBounceDomains` | Top 10 with horizontal `#B58289` fill bars, polls every 10s. |
| `AnomalyHistory` | Paginated table (25/page), expandable JSON context rows, polls every 15s. |
| `MonitorFilters` | Window (15m/1h/6h/24h), bucket (1m/5m/15m), event types (chips). |

All polling pauses on `document.visibilityState !== 'visible'` to avoid
wasted calls when the operator is on another tab.

**Cron schedule (in `vercel.json`):**

| Path | Schedule (UTC) |
|---|---|
| `/api/cron/email/anomaly-check` | `*/5 * * * *` |

**Env vars (no new ones):**

| Name | Use |
|---|---|
| `CRON_SECRET` | Cron auth (Bearer token) |
| `PMF_OPERATOR_USER_ID` | Actor on auto-pause + recipient of rail notification |
| `PMF_NOTIFICATION_EMAIL` | Actor email on auto-pause audit row |
| `PMF_OPERATOR_COMPANY_ID` | `notifications.company_id` (NOT NULL) |

**Migrations:**

| File | Role |
|---|---|
| `OPS-Web/supabase/migrations/104_email_pause_audit_log_anomaly_columns.sql` | severity + anomaly_log_id columns |
| `OPS-Web/supabase/migrations/105_email_anomaly_log.sql` | Anomaly log table + FK back from pause audit log |
| `OPS-Web/supabase/migrations/106_email_event_metrics_rpc.sql` | RPC pair |
| `OPS-Web/supabase/migrations/107_email_events_timestamp_event_idx.sql` | Composite covering index |

**Key files:**

| File | Role |
|---|---|
| `OPS-Web/src/lib/email/anomaly-thresholds.ts` | Pure evaluator + constants |
| `OPS-Web/src/lib/email/pause.ts` | Extended `pause()` with severity + anomalyLogId, returns `pauseAuditId` |
| `OPS-Web/src/app/api/cron/email/anomaly-check/route.ts` | The 5-min cron |
| `OPS-Web/src/app/api/admin/email/monitor/metrics/route.ts` | Live metrics |
| `OPS-Web/src/app/api/admin/email/monitor/stream/route.ts` | Recent events |
| `OPS-Web/src/app/api/admin/email/monitor/domains/route.ts` | Top bounce domains |
| `OPS-Web/src/app/api/admin/email/monitor/anomalies/route.ts` | Paginated anomaly log |
| `OPS-Web/src/app/admin/email/_components/event-monitor-tab.tsx` | Orchestrator |
| `OPS-Web/src/app/admin/email/_components/bounce-gauge.tsx` | Gauge |
| `OPS-Web/src/app/admin/email/_components/event-stream.tsx` | Live tail |
| `OPS-Web/src/app/admin/email/_components/monitor-metric-bar.tsx` | 6 metric cards |
| `OPS-Web/src/app/admin/email/_components/top-bounce-domains.tsx` | Domain list |
| `OPS-Web/src/app/admin/email/_components/anomaly-history.tsx` | Anomaly log UI |
| `OPS-Web/src/app/admin/email/_components/monitor-filters.tsx` | Filter chips |

---

## Subscription Add-ons (Web)

**Added**: 2026-04-29
**Location**: `OPS-Web/src/components/settings/addons-section.tsx` + supporting endpoints, hooks, webhook branches.
**Bugs closed**: `9bcdbe02-e13b-4cc8-9184-308e459cb9ac` (Data Setup), `c0eb2e2c-ca3d-461c-8efb-05fca08ab833` (Priority Support).

### What it is

Two paid add-ons sit alongside the base subscription, surfaced as cards in the Subscription tab below the plan list:

| Add-on | Stripe mode | Entitlement column | Stripe price env var |
|---|---|---|---|
| Data Setup | `payment` (one-time) | `companies.data_setup_purchased` (+ `data_setup_requests` row) | `STRIPE_PRICE_DATA_SETUP` |
| Priority Support — monthly | `subscription` | `companies.has_priority_support` | `STRIPE_PRICE_PRIORITY_SUPPORT_MONTHLY` |
| Priority Support — annual | `subscription` | `companies.has_priority_support` | `STRIPE_PRICE_PRIORITY_SUPPORT_ANNUAL` |

The fulfillment inbox is `ADDON_FULFILLMENT_EMAIL` (defaults to `jack@opsapp.co`). All three Stripe price IDs and the fulfillment address are environment variables — no hardcoded values.

### Purchase flow — Data Setup

```
User clicks "Purchase" on the Data Setup card
   → POST /api/stripe/addon/data-setup       (Bearer Firebase token)
       → Creates Checkout Session, mode=payment, line_item=data_setup price
       → Idempotency key: company-{id}-checkout-data-setup
       → Returns { url }
   → Browser hard-navigates to Stripe Checkout
   → User pays → Stripe fires checkout.session.completed
       → /api/webhooks/stripe handleDataSetupCheckout()
           → companies.data_setup_purchased = true
           → INSERT data_setup_requests (status=pending, payment_intent_id, amount, contact)
           → DataSetupRequest email → ADDON_FULFILLMENT_EMAIL
           → notifications insert (persistent: true) for every company admin
   → Browser returns to /settings?tab=subscription&addon=data_setup&result=success
       → Toast confirmation, query strip
```

### Purchase flow — Priority Support

```
User clicks "Purchase" on the Priority Support card (with monthly/annual toggle)
   → POST /api/stripe/addon/priority-support  body: { period: 'monthly' | 'annual' }
       → Creates Checkout Session, mode=subscription, price=monthly|annual
       → Returns { url }
   → Browser hard-navigates to Stripe Checkout
   → User pays → Stripe fires:
       1. checkout.session.completed
            → handlePrioritySupportCheckout()
                → companies.has_priority_support = true (belt-and-suspenders flip)
                → PrioritySupportActivated email → buyer
                → notifications insert (persistent: false) for company admins
       2. customer.subscription.created/updated
            → Routed via isPrioritySupportPrice(price) — does NOT clobber base plan columns
            → companies.has_priority_support = entitled (active|trialing|past_due|paused)
   → Browser returns to /settings?tab=subscription&addon=priority_support&result=success
```

### Cancellation

`customer.subscription.updated` (status → canceled/incomplete_expired/unpaid) and `customer.subscription.deleted` flow through `isPrioritySupportPrice()` and flip `companies.has_priority_support = false`. Base-plan handlers are explicitly skipped for add-on subscriptions to avoid clobbering `subscription_status` / `subscription_plan` / `max_seats`.

The "Manage in billing portal" link uses `/api/stripe/billing-portal` (Stripe Billing Portal session) — users cancel from there.

### "Contact priority support" button

Active-state-only mailto: `jack@opsapp.co?subject=[OPS Priority] {companyName}&body=...` with prefilled user name, company, plan period, and current page URL. No Intercom integration — the founder's inbox is the support queue while volume is low.

### Notification rail entries

Per `Section 14: Notifications`. Recipients = every user in the company with `is_company_admin = TRUE`.

- **Data Setup** → `persistent: true`. Stays on the rail until ops marks the request `scheduled` / `completed`.
- **Priority Support active** → `persistent: false` (standard dismissible).

### Files

| File | Role |
|---|---|
| `OPS-Web/supabase/migrations/20260429120000_data_setup_requests.sql` | New `data_setup_requests` table + RLS |
| `OPS-Web/src/lib/stripe/subscription-mapping.ts` | `ADDON_PRICE_MAP`, `addonFromPriceId`, `isPrioritySupportPrice` |
| `OPS-Web/src/lib/stripe/checkout-helpers.ts` | Shared customer-provisioning + return-URL builders |
| `OPS-Web/src/app/api/stripe/addon/data-setup/route.ts` | Checkout session, mode=payment |
| `OPS-Web/src/app/api/stripe/addon/priority-support/route.ts` | Checkout session, mode=subscription |
| `OPS-Web/src/app/api/stripe/addon/prices/route.ts` | Server-side Stripe price fetch (1h edge cache) |
| `OPS-Web/src/app/api/stripe/billing-portal/route.ts` | Billing portal session for cancellations |
| `OPS-Web/src/app/api/webhooks/stripe/route.ts` | `checkout.session.completed` handler + add-on subscription routing |
| `OPS-Web/src/lib/email/react/templates/DataSetupRequest.tsx` | React Email — ops fulfillment notification |
| `OPS-Web/src/lib/email/react/templates/PrioritySupportActivated.tsx` | React Email — customer confirmation |
| `OPS-Web/src/lib/email/sendgrid.tsx` | `sendDataSetupRequest` + `sendPrioritySupportActivated` (Dispatch sender) |
| `OPS-Web/src/components/settings/addons-section.tsx` | Two-card UI mounted in the Subscription tab |
| `OPS-Web/src/lib/hooks/use-addons.ts` | `useAddOns()` + `useAddOnPrices()` hooks (TanStack + Supabase realtime) |

---

**End of Document**
