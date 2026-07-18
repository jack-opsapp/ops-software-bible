# 07 - Specialized Features

**Last Updated:** July 7, 2026
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
13. [Catalog Management](#13-catalog-management)
14. [Notification System](#14-notification-system)
15. [Crew Location Tracking](#15-crew-location-tracking)
16. [Schedule Tab Redesign](#16-schedule-tab-redesign)
17. [Feature Flags System](#17-feature-flags-system)
18. [Intel Galaxy Visualization (Web)](#18-intel-galaxy-visualization-web)
19. [In-App Email System (Web)](#19-in-app-email-system-web)
20. [Mobile Wizard System](#20-mobile-wizard-system)
21. [Blog & Content Marketing Pipeline](#21-blog--content-marketing-pipeline)
22. [Social Media Generation & Publishing](#22-social-media-generation--publishing)
23. [Quick Add Task Suggestions (iOS)](#23-quick-add-task-suggestions-ios-2026-05-10)
24. [Task Reminders](#24-task-reminders-2026-05-10)
25. [Task Pairs — Auto-Create](#25-task-pairs--auto-create-2026-05-11)
26. [iPhone Calendar Mirror (iOS)](#26-iphone-calendar-mirror-ios-2026-05-11--bug-68123654)
27. [LiDAR Dimensioned Photo Capture (iOS)](#27-lidar-dimensioned-photo-capture)
28. [Auto Bug Reporting (iOS)](#28-auto-bug-reporting-ios-2026-05-15--may-12-outage-follow-up)

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
- Day-detail inspector for the focused day/range, showing scheduled task context without leaving the sheet

**Schedule Entry Contracts (iOS):**
- Task schedule writes use `DataController.updateTaskSchedule(task:startDate:endDate:)` and write `project_tasks.start_date` / `project_tasks.end_date`.
- Project rows are not manual scheduling targets. Project start/end dates are computed from the project's task schedule span; `projects.start_date` / `projects.end_date` are maintained as task-derived sync/cache fields, not operator-editable schedule inputs.
- Universal Search project-row quick schedule only targets active, non-deleted, non-terminal tasks. If the project has zero schedulable tasks, the schedule control is hidden/disabled. If it has one schedulable task, the scheduler opens that task. If it has multiple schedulable tasks, the operator must choose the task before the scheduler opens.
- `UnscheduledTaskReviewView` auto-schedule placement failures are persistent recovery states: the toast uses operator-readable copy and opens `CalendarSchedulerSheet` for manual task scheduling instead of ending at a no-action error.
- **iOS month-grid quick actions (2026-07-07):** `EventDetailCard` restores the same field actions as day view: Push, Extend, Cascade, and Pick new date. Cascade actions use `DataController.planCascade` + `CascadePreviewSheet` before committing with `pushTaskWithCascade`, so the preview and write path stay identical.

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

### Synced `project_photos` gallery store (V9)

**Problem (fixed 2026-06-04).** The gallery carousel historically rendered only
`projects.project_images` — a comma-separated CSV column on the project row. That
CSV is unreliable: it is a whole-array overwrite (clobber-prone), its update is
gated by the project-edit RLS, the web app does not maintain it, and the update
does not bump `updated_at`. The uploader saw their own photo only because the app
*optimistically* appends the new URL to its **local** `projectImagesString`. Other
assigned crew sync the server CSV, which never received the new URL — so a
teammate's photo appeared in **comments** (which read the canonical
`project_photos` table) but was **missing from the gallery list**.

**Fix.** `project_photos` is now a first-class **synced entity**, mirroring
`project_notes`. The carousel unions the synced rows with the legacy CSV.

| Piece | Location |
|-------|----------|
| `@Model ProjectPhoto` | `OPS/DataModels/Supabase/ProjectPhoto.swift` |
| `ProjectPhotoDTO` (read; optional-heavy decode) | `OPS/Network/Supabase/DTOs/ProjectPhotoDTOs.swift` |
| `ProjectPhotoRepository` (`fetchAll(since:)`, `fetchForProject`) | `OPS/Network/Supabase/Repositories/ProjectPhotoRepository.swift` |
| `SyncEntityType.projectPhoto` → `project_photos`, priority 7 | `OPS/Network/Sync/SyncTypes.swift` |
| SwiftData schema **V9** (additive lightweight V8→V9) | `OPS/DataModels/Migrations/OPSSchemaV9.swift`, `OPSSchemaCommon.v9ProjectPhotoModels`, `OPSMigrationPlan` |
| Inbound full/delta sync | `InboundProcessor` (`syncProjectPhotos`/`mergeProjectPhoto`) **and** `DataActor` (actor copy) |
| Realtime | `RealtimeProcessor` (legacy + actor-dispatch paths, `upsertProjectPhoto`) + `DataActor.RealtimeUpdate.projectPhoto` / `softDeleteFromRealtime` |
| Logout wipe + project-purge cascade | `OPS/Utilities/DataController.swift` |
| Merged gallery source of truth | `Project.mergedGalleryImageURLs(...)` in `OPS/DataModels/Project+Gallery.swift` |

**Read-only from the sync engine.** Photo rows are still *written* exclusively by
`ImageSyncManager.insertProjectPhotoRows`; nothing locally creates a `ProjectPhoto`
with `needsSync = true`, so the OutboundProcessor never pushes it. Per-photo
client-portal visibility continues to round-trip through
`project_photos.is_client_visible` (`setPhotoClientVisibility` /
`refreshClientVisibility`).

**Carousel + viewer.** `ProjectPhotosCarousel` (Activity tab) reads a live
`@Query` of `ProjectPhoto` (filtered `projectId`, `deletedAt == nil`, sorted
`createdAt`) and merges via `Project.mergedGalleryImageURLs(syncedPhotoURLs:)` —
legacy CSV order first, then synced-only URLs, deduped by URL. The full-screen
viewer (`photoViewerContent` → `PhotoCommentViewer`) uses the **same** merge
(`mergedGalleryImageURLs(using:)`) so a tapped index opens the correct photo.
`isImageSynced` (no spurious fail badge — teammates have an empty
`unsyncedImagesString`) and `isImageClientVisible` work unchanged on merged URLs.

**Required DB migration (applied 2026-06-04, prod `ijeekuhbatykdomumfjx`).**
`project_photos` had no `updated_at`, which incremental sync (`.gte("updated_at", since)`)
needs. Added additively, mirroring `update_project_notes_timestamp`:

```sql
ALTER TABLE public.project_photos ADD COLUMN IF NOT EXISTS updated_at timestamptz;
UPDATE public.project_photos SET updated_at = COALESCE(created_at, now()) WHERE updated_at IS NULL;
ALTER TABLE public.project_photos ALTER COLUMN updated_at SET DEFAULT now();
ALTER TABLE public.project_photos ALTER COLUMN updated_at SET NOT NULL;
CREATE TRIGGER update_project_photos_timestamp
  BEFORE UPDATE ON public.project_photos
  FOR EACH ROW EXECUTE FUNCTION update_timestamp();
```

`project_photos` columns: `id` (uuid), `project_id` (text), `company_id` (text),
`url` (text), `thumbnail_url`, `rendered_url`, `source` (`photo_source` enum),
`site_visit_id` (uuid), `uploaded_by` (text), `taken_at`, `caption`, `deleted_at`,
`created_at`, `updated_at`, `is_client_visible` (bool). RLS is company-wide read
(`company_isolation`), so every teammate can read all rows.

### Capture UI — one standardized camera (iOS)

**`CameraBatchView` is the single photo-capture surface** across every flow
(`OPS/Views/Components/Images/CameraBatchView.swift`). It is an
AVCaptureSession-backed multi-shot camera: the live preview stays running
between captures, shots accumulate into a bottom-right stack, and one DONE
press returns the whole batch. Library import (PHPicker) lives inside its HUD,
so a single entry point covers both capture and library paths. Call sites:
project action bar (home bar + Project Details PHOTO — bug 56c37df2 routed
both here), site-visit capture, and lead detail.

`ImagePicker` (`.../Images/ImagePicker.swift`) is now a **library-only PHPicker
wrapper** — its camera source was removed when the action bar migrated to
`CameraBatchView`; remaining callers (expense receipts, client/company/org
avatars, project-form gallery) only ever pick from the library.

**Lens/zoom labels use user-facing magnification, not raw AVFoundation zoom
factors** (bug 56c37df2). A virtual multi-camera device anchors raw
`videoZoomFactor` 1.0 to its **widest** constituent lens, so on any
ultra-wide-bearing iPhone raw 1.0 is the "0.5x" lens and the "1x" wide lens
engages at the device's first `virtualDeviceSwitchOverVideoZoomFactors` value
(2.0 on every ultra-wide iPhone to date). `CameraLensOptionPlanner`
(`.../Images/CameraLensOptionPlanner.swift`, pure/tested) computes stops and
labels in magnification space (raw ÷ wide-lens baseline) and converts back to
raw factors for the device; `CameraBatchView` detects the baseline from the
constituent lenses, opens at true 1x, and scales its digital-zoom ceiling to
it. Telephoto switch-overs surface at their true magnification (a 5x tele on a
Pro Max labels "5x", not "10x").

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

Project status writes cross an authenticated server boundary. `Archived` additionally requires `projects.archive:all`; a restrictive project policy blocks direct browser bypasses, and service workflows use the actor-aware `change_project_status_as_system` bridge. Every real transition increments the trigger-owned monotonic `projects.status_version` and atomically inserts `project_status_lifecycle_outbox`. The immutable outbox event—not an editable timeline note—is the historical-actor, current-version, recipient, and permanent-dedupe proof for the leased minute worker. A later actor permission change does not strand an event that was authorized when written, while every recipient must still pass current project-view authorization. Timeline projections cannot be forged or rewritten, and notification plus Phase C task/invoice actions retain event-key uniqueness after rows are read, approved, or executed. The browser callback is only an eager drain, so a callback, retry, or process failure cannot lose or duplicate lifecycle work.

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

Classic markup overlays are rendered in the fitted display-canvas coordinate space, then composited by scaling the transparent overlay over the original source image. Do not render the PencilKit drawing at the raw source-photo pixel size unless the display canvas size is unavailable; doing so makes marks appear tiny or misaligned on other devices.

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

Full-screen annotation view with a zoomable photo/canvas pair:
1. **Original photo** -- loaded from local image cache when available, otherwise from the normalized photo URL (`//` URLs become `https:`)
2. **PencilKit canvas** -- fitted to the same aspect-fit rect as the photo and zoomed/panned with it
3. **Display-canvas size binding** -- persisted into the save path so the overlay PNG matches the coordinate space where the crew actually drew

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
- `ZoomablePhotoAnnotationCanvas` reports its fitted canvas size back to SwiftUI. `PhotoAnnotationRenderGeometry.renderSize(displayedCanvasSize:sourceImageSize:)` uses that fitted size first and falls back to source image size only when the view has not laid out yet.

#### PhotoAnnotationSyncManager (iOS)
**Location:** `OPS/OPS/Network/PhotoAnnotationSyncManager.swift`

Singleton (`PhotoAnnotationSyncManager.shared`) that handles:
1. **Rendering** -- `renderDrawingToPNG(drawing:size:)` uses `UIGraphicsImageRenderer` to render `PKDrawing` strokes onto a transparent PNG at the fitted annotation canvas size
2. **S3 upload** -- Requests a presigned URL from `AppConfiguration.apiBaseURL/api/uploads/presign`, then PUTs the PNG to S3 with content type `image/png`. Files stored at `annotations/{companyId}/{projectId}/annotation_{timestamp}.png`
3. **Supabase record** -- Creates or updates a row in `project_photo_annotations` via `PhotoAnnotationRepository`
4. **Offline fallback** -- If S3 upload fails, the `PKDrawing` data is stored locally in `localDrawingData`, and `needsSync` is set to `true`
5. **Pending sync** -- `syncPendingAnnotations(modelContext:)` fetches all annotations where `needsSync == true`, re-renders and uploads them
6. **Visibility composite** -- `preCompositeAnnotations(projectId:modelContext:)` normalizes source/overlay URLs, loads the original source image from local cache or remote URL, loads the overlay from local cache or remote URL, scales the overlay over the original source image, writes the composited result to `ImageCache` keyed by the normalized source URL, then posts `.annotationsComposited` **per photo, immediately after each composite is cached** — not once after the whole loop. Composites are full source resolution (a 12 MP photo ≈ 48 MB) and `ImageCache` is an `NSCache` with a 50 MB cost limit, so inserting the next composite can evict the previous one right away; the per-photo post lets each mounted thumbnail capture its own image while it is still the freshest cache entry. The cache key is `url.hasPrefix("//") ? "https:" + url : url`, matching what every reader (`PhotoThumbnail`, `ZoomablePhotoView`) computes. **It also persists each composite to disk** (`ImageFileManager.saveCompositedImage`, JPEG q0.9) so markup survives `NSCache` eviction and late mounts — see *Durable Composited Markup* below. To keep large galleries responsive it **skips re-rendering** a photo whose on-disk composite is newer than the annotation's `updatedAt` (freshness), and after the loop runs a **reconciliation pass** that deletes composites for soft-deleted annotations.

When updating an existing annotation id, the save path updates the existing SwiftData row instead of creating a second remote row. If the local row is missing but the remote id is known, iOS recreates the local SwiftData model with that id so follow-up edits remain attached to the same Supabase row.

**Clearing markup (empty-drawing save).** `renderDrawingToPNG` returns `nil` for a stroke-less drawing, so a save after the user taps CLEAR must NOT fall through to the upload path — doing so keeps the old `annotation_url` on the row and the stale markup stays visible (it only "cleared" once the user drew new strokes that overwrote it). Instead, `saveAnnotation` routes an empty drawing through `AnnotationClearPlanner`: a pure PencilKit annotation is **soft-deleted** (markup disappears here and, via the company-scoped sync + the preComposite reconciliation pass, on teammates' devices), its overlay + durable composite are dropped, and the photo reverts to the raw original; a **dimensioned capture is preserved** (its markup is the dimensions, shown via the rendered deliverable); a brand-new empty save is a no-op (no junk empty row).

**Cross-device overlay visibility (storage ACL contract).** A teammate's device renders another user's markup by downloading that user's overlay PNG from `annotation_url` during `preCompositeAnnotations` (the author's own device uses its local `overlay_<id>` cache, so it always sees its own marks even when the remote object is unreadable). Therefore the overlay objects MUST be publicly readable, exactly like project photos. Annotation rows are already shared company-wide (the `get_photo_annotations_since` SECURITY DEFINER RPC + the `company_id`-scoped SELECT policy — no author filter), so a 403 on the overlay is the only thing that blocks cross-user markup. **Storage requirement:** the S3 bucket `ops-app-files-prod` must grant public `s3:GetObject` to the `annotations/*` prefix, the same as `projects/*`. The Supabase Storage → S3 migration (`/api/uploads/presign`) originally granted the photo prefixes but not `annotations/*`, so overlays returned `403 AccessDenied` and teammates saw the raw photo while each author still saw their own marks. Existing overlay objects need no re-upload once the prefix is made public — the next gallery open re-composites them.

#### Thumbnail Display & Markup Retention (iOS)

**Location:** `OPS/Views/Components/Images/ProjectPhotosGrid.swift` (`PhotoThumbnail`)

`PhotoThumbnail(url:project:)` is the shared thumbnail used by the activity-feed carousel (`ProjectPhotosCarousel`), the full-screen photo grid (`ProjectPhotosGrid`), the activity-feed annotation cards (`AnnotationEntryView`), and the bio/picker sheets. It resolves its image by normalized URL: in-memory `ImageCache` first (where the freshest composite lands), then the **durable on-disk composite** (`ImageFileManager.loadCompositedImage`), then the on-disk raw original via `ImageFileManager`, then network. The composite tier sits ahead of the raw so markup resolves the instant the thumbnail mounts regardless of `NSCache` eviction or mount timing. It listens for `.annotationsComposited` and re-reads (`reloadFromCache` — in-memory then durable composite) so a composite that finishes after first paint swaps in. The full-screen viewers (`ZoomablePhotoView`, `SinglePhotoView`) use the same composite-first ladder.

**Retention invariant (Bug — markup vanished from every thumbnail):** the thumbnail's SwiftUI identity must be the photo **URL alone** (`.id(url)`). It must NOT mix a per-instance `UUID()` into the identity. A `UUID()` regenerated on each struct init makes every parent re-render mint a fresh identity, which discards the thumbnail's `@State` (the composited image it captured from `.annotationsComposited`) and tears down the notification subscription — so the raw photo reloads and the markup disappears. The gallery carousel re-renders constantly because it is reactive (`@Query` over synced `project_photos` + an `@ObservedObject` `ImageSyncManager`), so the churn wiped the markup on every sync tick. The full-screen viewer (`PhotoCommentViewer` → `ZoomablePhotoView`) was unaffected because it has stable identity and force-reloads via an explicit `imageRefreshToken` after compositing. Once identity is stable, the captured composite survives both re-renders and later `NSCache` eviction.

#### Durable Composited Markup (iOS)

**Locations:** `OPS/Utilities/ImageFileManager.swift`, `OPS/Network/PhotoAnnotationSyncManager.swift`, the readers (`ProjectPhotosGrid.swift`, `ZoomablePhotoView.swift`, `PhotoCommentViewer.swift`), `OPS/Utilities/PhotoDownloadManager.swift`.

The in-memory `ImageCache` is an `NSCache` with a 50 MB cost limit — barely one full-resolution composite. Identity stability (above) keeps a *mounted* thumbnail's captured composite alive, but a `LazyVGrid` cell scrolled into view long after the per-photo posts fired has no captured copy and would resolve the raw photo once the composite is evicted. The fix is a **durable on-disk composite tier**.

- **On-disk key.** `preCompositeAnnotations` persists every composite via `ImageFileManager.saveCompositedImage(_:forURL:)` → on-disk filename `composited_<encodeRemoteURL(url)>`, **keyed by the same `plan.cacheKey`** the in-memory composite uses. This is a *separate* asset from the raw original (`remote_<hash>`); the two coexist so readers resolve composite-first while base-image loaders and the annotation editor always read the raw. Encoded as **JPEG q0.9** (opaque) — ~5–6× smaller than a lossless PNG of the same 12 MP frame, which matters for the storage budget. `getFileURL` was taught the `composited_` (and `overlay_`) prefixes; previously it returned `nil` for them, so the long-standing "cache overlay PNG for instant compositing" was a **silent no-op** (overlays re-downloaded every pass) — now fixed too.
- **Reader order.** `PhotoThumbnail`, `SinglePhotoView`, and `ZoomablePhotoView` all check in-memory `ImageCache` → `loadCompositedImage(forURL:)` → on-disk raw → network. `PhotoCommentViewer.shareCurrentPhoto` prefers the composite too (share what you see).
- **Invalidation (edit).** `saveAnnotation` deletes the photo's durable composite before re-compositing (deterministic), and `preCompositeAnnotations` independently regenerates any composite older than the annotation's `updatedAt` (freshness check — covers remote edits arriving via sync without hooking the sync processors).
- **Invalidation (delete).** The gallery delete path (`markMatchingAnnotationsDeleted`) drops the composite immediately; `preCompositeAnnotations` also runs a reconciliation pass that deletes composites for any soft-deleted annotation with no surviving markup sibling (covers local + remote deletes centrally, driven by SwiftData `deletedAt`).
- **Base-loader hardening.** `loadBaseImage` (compositor) and `PhotoAnnotationView.loadImage` (editor) no longer fall back to the ambiguous in-memory `ImageCache[cacheKey]` — that slot holds the composite, and using it as a drawing base would double the markup. They source the raw only (url-keyed disk → network).
- **Storage budget.** Composites live in `Documents/ProjectImages`, so `StorageProfiler.currentUsageBytes()` (and therefore `PhotoPrefetchService`'s budget checks) count them automatically. `composited_` keys are remote-cache keys, so `saveImage` budget-enforces them and `evictRemoteImagesIfNeeded` treats them as reclaimable candidates (they regenerate from raw+overlay). A **pinned** photo's composite is pinned too. `PhotoDownloadManager.removeFromDevice` deletes the composite alongside the raw, and `enforceCapacityPolicy`/`previewEviction` count both raw + composite bytes when reporting/reclaiming. `clearRemoteImageCache` sweeps `composited_` files.
- **Dimensioned-capture orthogonality.** A pure LiDAR/visual dimensioned capture has `annotationURL == nil`, so `PhotoAnnotationCompositePlan.init?` returns `nil` and no composite is ever made — the gallery shows the server-rendered `renderedPhotoURL` deliverable (a distinct remote image under its own key, see `ProjectPhotoDisplayMapper`). Because the durable composite reuses the *identical* key contract as the pre-existing in-memory composite, this feature only makes the existing composite durable; it does not change **which** photos composite or under what key, so the dimensioned path is unaffected. A photo annotated with PencilKit markup composites under its own `photoURL` key regardless of any separate dimensioned deliverable.

#### PhotoAnnotationRepository (iOS)
**Location:** `OPS/OPS/Network/Supabase/Repositories/PhotoAnnotationRepository.swift`

**Table:** `project_photo_annotations`

**Methods:**
- `fetchForProject(projectId)` -- all non-deleted annotations for a project, ordered by `created_at` descending
- `fetchForPhoto(projectId, photoURL)` -- single annotation for a specific photo
- `create(dto)` / `upsert(dto)` -- insert or upsert annotation
- `upsertLayer(annotationId, layer, changeEvent, ...)` -- **collaborative markup write path**; merges the caller's own layer via the `upsert_markup_layer` RPC, returns the merged row
- `updateNote(id, note)` -- note-only update (the shared scalar; `annotation_url` is RPC-owned)
- `updateAnnotation(id, annotationUrl, note)` -- legacy single-overlay update (offline-sweep fallback for pre-collab rows)
- `softDelete(id)` -- sets `deleted_at` and `updated_at`

**Collaborative markup — author-scoped layers (2026-06-23).** Fixes "user B opens markup on a photo user A marked up and sees a blank canvas / overwrites A." Markup is now per-author *layers* (`MarkupLayer`, `layerId == authorId == users.id`) on the shared row; the editor (`PhotoAnnotationView` + `ZoomablePhotoAnnotationCanvas`) composites visible peers' overlays as a NON-editable base under the current user's canvas via `MarkupOverlayCompositor`, and seeds the own canvas from the synced `strokeRef` (`MarkupStrokeStore`, an S3 stroke blob) when the local canvas is empty. `saveAnnotation` uploads the overlay PNG + stroke blob then merges the author's layer through the `upsert_markup_layer` SECURITY DEFINER RPC (atomic server-side merge by layerId — never a wholesale overwrite). An empty-drawing save is an **author-scoped clear** (`AnnotationClearPlanner` layer-aware overload): it sets only the current user's `layer.clearedAt`; the whole-row soft-delete fires ONLY when the last active layer is cleared AND no dimensioned capture remains — opening a *peer's* row and tapping DONE with no marks of your own is a no-op (`.ignore`). A `MarkupChangeLogSheet` (toolbar `square.stack.3d.up`, shown only when a peer's marks are present) lists each author with a per-viewer eye toggle (`hiddenAuthorIds`, LOCAL — never synced) and an expandable ACTIVITY history. `preCompositeAnnotations` + the offline sweep are layer-aware (composite ALL active layers; push the own layer via the RPC). Legacy `annotation_url`-only rows synthesize a layer for display (`PhotoAnnotation.effectiveMarkupLayers()`) and are server-seeded into a real layer on the first write. Before/after activity-feed *snapshots* are deferred (columns ship null, forward-ready). See `03_DATA_ARCHITECTURE.md` (schema) + `04_API_AND_INTEGRATION.md` §14 (RPC).

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

## 13. Catalog Management

### Overview

The CATALOG tab replaces the legacy Inventory tab. It is variant-aware, recipe-aware, and integrates the drawing→estimate adapter and threshold-driven order suggestions. The IA splits into two segments — **STOCK** (variants and quantities) and **PRODUCTS** (billable templates) — with all advanced operations grouped under a kebab menu. SwiftData models live in `OPS/DataModels/Supabase/Catalog/`; see `03_DATA_ARCHITECTURE.md` § Catalog & Variant Model for full schema.

### Design Intent — Catalog Model & Guided Onboarding (2026-06-10)

This subsection records the durable *intent* behind the catalog and its onboarding — the model and principles that hold across implementations. The specific iOS guided-onboarding flow that realizes this intent (screens, survey routing, module gates) is expected to evolve and is **not** enumerated here; see the iOS design spec `ops-ios/docs/superpowers/specs/2026-06-09-guided-catalog-setup-design.md`, `03_DATA_ARCHITECTURE.md` § Catalog & Variant Model for schema, § 13a for recipe/resolver semantics, and § 13b for the stock-counting sub-flow.

**What a catalog is.** A company's catalog is the model of everything it sells and everything it consumes to deliver it. Four kinds of entry:

- **Service** — labor / time / expertise sold to the customer. Priced flat (per job, per call) or per-unit (per hour, per day, per area). The company's cost is optional; when present it yields margin.
- **Good** — a physical item resold, typically marked up over cost. Carries a SKU and may carry variants (brand, model, size).
- **Package (assembly)** — a fixed customer-facing offering that bundles materials + labor under one price. The customer sees a single number; the backend may price per unit (per linear foot, per square foot) and rolls component costs up into margin. Persisted as a `kind=package` product (`bundle_pricing_mode=override`) with child `product_bundle_items` / `product_materials` rows.
- **Stock** — tracked inventory: `catalog_items` (families) → `catalog_variants` (the counted SKU) with on-hand quantity, thresholds, and reorder. A material may be stocked or ordered per job; offcuts/rolls carry their own physical identity (`catalog_stock_units`).

**Cross-cutting primitives (durable vocabulary).**

- **Units & dimensions** — every quantity carries a unit; units group by dimension (`count`, `length`, `area`, `volume`, `mass`, `time`). A company prices and counts in its real units (linear ft, sq ft, cubic yard, ton, hour). Units are first-class: available (seeded) and able to drive pricing, never silently dropped to flat-rate.
- **Price vs cost** — customer-facing price and the company's cost are always distinct; margin is the difference. Cost tracking is optional per company.
- **Variants & options** — one entity in several forms (color, size, thickness, tier). The variant is the priced/counted SKU; options (`catalog_options` / `catalog_option_values`) are the axes.
- **Pricing mode** — flat total, or per-unit rate × measured quantity. Applies to services, packages, and labor lines alike.
- **Reference, not duplication** — a material used in two packages is the same stock entity referenced twice, never two copies.

**Onboarding intent.** Catalog setup is the highest-effort, highest-abandonment step for a new company. Guided onboarding exists to take an operator from zero to a usable catalog quickly by *meeting them where they are*:

1. **Ask, don't assume** — a short adaptive survey establishes how the company prices (flat / per-unit / depends), what it sells (services / goods / packages / a mix), and whether it tracks cost and stock.
2. **Derive, don't dump** — only the modules implied by the answers are shown. A services-only business never sees the package builder; a flat-price business is not asked to model materials.
3. **Progressive, not exhaustive** — capture the minimum that makes the catalog usable; the rest is opt-in. Every module is skippable.
4. **Show the payoff** — surface a real result (margin, a finished line) rather than a wall of fields. Per the brand test, the step should read as a lifeline, not a tech demo.

**Invariants (the yardstick any implementation must hold).**

1. Meet the operator where they are — never force a business shape on them (services-only ≠ assembly builder).
2. Customer-facing price and backend cost/unit are both expressible and kept distinct.
3. Units are first-class — seeded/creatable and able to drive pricing; never dropped to flat-rate silently.
4. Cost tracking is the operator's choice — honor "just set prices" in every module.
5. Reference existing catalog entities; never duplicate stock.
6. The catalog models what a company *sells and stocks*, not *when* work happens — recurrence/cadence belongs to scheduling; onboarding routes there rather than absorbing it.

### IA — CATALOG tab

```
CATALOG
─────────────────────────────────────────────
[ STOCK ]  [ PRODUCTS ]                     ⋮
─────────────────────────────────────────────

STOCK
  ├─ Banner (when applicable):
  │     "// 6 ITEMS BELOW THRESHOLD [REVIEW →]"
  │     ↳ tap opens Orders sheet (Suggested view)
  ├─ View mode:  [ LIST ] [ GRID ] [ TABLE ]
  │   LIST  = variant-aware list (cards)
  │   GRID  = pinch-to-zoom grid
  │   TABLE = NEW (Bug 217c3d1f) — rows=variants, columns=family attributes
  ├─ Sort/filter: category · tags · option values · threshold · sort · search
  ├─ Category sections (collapsible, nested 2-level):
  │     // HARDWARE
  │       ▸ HARDWARE LEVEL
  │         • Corner — Black · 288
  │         • Corner — White · 70
  │       ▸ HARDWARE STAIR
  │     // FASTENERS
  │       • 2" Screw — Black · 3000
  └─ ⋮ STOCK: Guided Setup · Stock Setup · Add Variant · Add Family · Import · Snapshots

PRODUCTS
  ├─ Filter: type · kind · "has recipe"
  ├─ Search
  ├─ List
  │     • PICKET RAIL · $2500 · flat
  │     • Custom Composite Railing · $48/ft · 4 options · 7 recipe rows
  │     • Service Call · $150/hr · service
  ├─ Empty state: `// NO PRODUCTS YET` + `SET UP PRODUCTS`
  └─ ⋮ PRODUCTS: Guided Setup · New Service · New Good · New Bundle

⋮ menu (grouped):
  ── STOCK ──     Guided Setup · Stock Setup · Add Variant · Add Family · Import · Snapshots
  ── PRODUCTS ──  Guided Setup · New Service · New Good · New Bundle
  ── MANAGE ──    Categories… · Tags… · Units… · Thresholds… · Defaults…
  ── ORDERS ──    Suggested · Drafts · Sent
```

### Variant-Aware View Modes

**LIST** (default) — `CatalogVariantCard` per row. Renders family name, variant label ("Black · Topmount"), quantity colored by threshold status, unit, SKU. Tap opens the medium-detent `StockQuickAdjustSheet`; the sheet's detail control and row context menu open `VariantDetailView`.

**GRID** — pinch-to-zoom grid. `@AppStorage("catalogCardScale")` range 0.8–1.5. Same progressive-disclosure rules as legacy Inventory: at scale ≥ 0.9 show family tags; at scale ≥ 1.0 show SKU + threshold badge. Tap opens `StockQuickAdjustSheet`.

**TABLE** (NEW per Bug 217c3d1f) — rows are variants, columns are family attributes (Family · Option 1 · Option 2 · … · Quantity · Threshold · Unit · SKU). Designed for fast bulk audits where a user wants to compare every "Bracket" SKU across Color × Mount Type. Horizontal scroll for families with 5+ option values; tap opens `StockQuickAdjustSheet`.

### Stock Filtering, Sorting, and Detail Editing (iOS)

`StockView` builds `EnrichedVariantRow` from `CatalogVariant`, `CatalogItem`, unit, category, tags, and option-value join rows. The STOCK filter rail supports:
- Category filter
- Tag filter
- Threshold filter
- Dynamic option-value filters keyed by option name (for example Color, Mount Type, Finish)
- Sort modes: Family, Low Stock, Quantity
- Search across family name, description, SKU, unit, category, tags, and option values

Low-stock sorting ranks rows by `quantity / effective_threshold`, using variant warning threshold first, then critical threshold as the fallback reference when no warning threshold exists. TABLE mode includes a `THRESH` column that shows the percent of threshold and the current delta from the threshold reference.

`StockQuickAdjustSheet` is the default row tap surface for LIST, GRID, and TABLE. It opens at a medium detent for preset deltas, exact set count, and custom add/subtract quantities. `VariantDetailView` is the full detail/edit surface opened from the quick-adjust sheet, row context menu, and Universal Search; SKU, unit, warning threshold, and critical threshold remain editable inline there.

Variant identity is option-value based. `catalog_variants` does not have a separate display-name column, so editing the human-readable variant label opens `VariantFormSheet` and replaces the variant's `catalog_variant_option_values` join rows. Variant images are family-level images stored on `catalog_items.image_url`; the detail surface displays and uploads that family image rather than writing an image field to `catalog_variants`.

### Threshold-Driven Order Suggestions (NEW per Bug e08c63a2)

Variants where `quantity < effective_warning_threshold` (variant override → family default → category default) are surfaced via:

1. **Banner** at top of STOCK list — `// N ITEMS BELOW THRESHOLD [REVIEW →]`. Tap opens the Orders sheet on the Suggested tab.
2. **Suggested orders sheet** — groups undersupplied variants by a heuristic (preferred-supplier convention from `catalog_tags` if present, else single combined order). Each row shows variant label, current quantity, effective threshold, restock target (default: 2× warning threshold).
3. **Persistent notification rail** entry — when first computed, the rail surfaces a `persistent: true` notification "// 6 items below threshold — review orders" with `actionUrl` deep-linking to the Orders sheet. Resolved when the user drafts/sends the order.

`CatalogOrder` lifecycle: `suggested` (computed on demand) → `draft` (user committed from Suggested sheet) → `sent` (PO emitted to supplier) → `fulfilled` (stock arrives; `catalog_variants.quantity` increments by `quantity_requested`). When `catalog_stock_units` is live, receiving flows also create/update physical unit rows and mirror their available aggregate back to the same variant quantity. Final state: `cancelled` for abandoned orders.

### OPS Decks Standalone Phase 1 Foundation (iOS — added 2026-06-26)

`OPSDecks` exists in the standalone `ops-decks-ios/OPSDecks.xcodeproj` repo. It is not a target inside the main OPS app repo; the main OPS app should consume only standardized deck objects and LIGHT viewer/editor surfaces.

`DeckKit` is the local Swift package boundary for shared deck models, runtime seams, rendering/planning logic, and package tests. The standalone app supplies the FULL runtime factory so it can launch without the full OPS project/job shell. Any main OPS integration must stay at the LIGHT capability layer and must not own full authoring workflows.

`OPSDesignKit` is the local Swift package boundary for shared OPS design tokens. Standalone app surfaces must route color, typography, spacing, radii, border, and motion through `OPSStyle`/`OPSDesignKit`; hardcoded UI styling is blocked by `ops-decks-ios/scripts/verify-ops-decks-style-tokens.sh`.

`OPSDecksTests` is hosted by the `OPSDecks` app target, not `OPSTests`. Standalone provisioning, entitlement, upgrade-surface, and deletion tests should live there so they do not depend on the main OPS app host.

Standalone persistence is local-first with an account-ready remote seam. `OPSDecksDeckLibraryStore` remains the synchronous local/cache contract; `OPSDecksRemoteSyncingDeckLibraryStore` adds async `deck_designs` refresh, upsert, and soft-delete behavior for account-backed sessions. `OPSDecksAccountContext` stores the deck-only Firebase/user/company identity using the backend provisioning contract, `OPSDecksFileAccountContextStore` persists and clears that context under app support, and `OPSDecksLibraryBootstrap` chooses the local draft store before account creation or a Supabase-backed syncing store once an account context plus token provider is available. `OPSDecksDesignSession` exposes async create/update/delete/refresh methods that use the remote-sync path when the store supports it, while preserving the synchronous local API for previews, tests, and pre-account drafting. `OPSDecksRootView` calls the async path for startup refresh, create, autosave, and delete so the standalone app can sync through Supabase without importing the main OPS app shell.

`OPSDecksAccountCoordinator` is the standalone auth/provisioning seam. It depends on `OPSDecksAuthProvider`, `DecksCompanyProvisioningClient`, and `OPSDecksAccountContextStore` protocols, so real Sign in with Apple, Firebase, and backend implementations can plug in without hardwiring platform credentials into the tested domain path. The coordinator loads existing context without starting auth, signs in through the auth provider, sends a deck-only `DecksCompanyProvisioningRequest`, stores the resulting `OPSDecksAccountContext`, and clears local context plus provider session on sign-out.

`DecksCompanyProvisioningService` decodes the backend provisioning response behind the `DecksCompanyProvisioningTransport` seam. `DecksCompanyProvisioningURLSessionTransport` posts the deck-only request to an injected ops-web endpoint URL with a Firebase bearer token, JSON accept/content headers, and non-2xx status handling, keeping the standalone app's account creation path testable without hardcoded endpoint configuration.

**Web backend counterpart (2026-07-03).** The ops-web endpoint the iOS transport targets is now live: `POST /api/decks/provision-company` (`ops-web/src/app/api/decks/provision-company/route.ts`) implements the idempotent company-of-one, sets `users.firebase_uid`, stamps `companies.source_app = 'ops_decks'`, and returns `company_id` lowercased with `subscription_plan: "decks"`. The Stripe Checkout endpoint (`POST /api/decks/checkout`) and the standalone checkout return page (`/decks/checkout/result`) are also live. Full billing/webhook/RLS detail — including the guarantees that keep Deckset billing from touching OPS company state — lives in `12_SUBSCRIPTION_MANAGEMENT.md` § "OPS Decks Standalone Exception". **Still unbuilt:** the ops-web account-deletion endpoint that `DecksAccountDeletionURLSessionTransport` targets.

`DecksEntitlementResolver` is the standalone deck billing gate seam. It maps only RevenueCat's `deck_pro` active entitlement, or an active `deck_subscriptions` mirror row with `entitlement = 'deck_pro'`, to `DecksEntitlement.pro`; missing, expired, cancelled, revoked, or unknown statuses remain on the one-deck free cap. `DecksRevenueCatEntitlementProvider` wraps an injected customer-info reader and keeps the cached entitlement when refresh fails, preserving offline-tolerant gating without importing the RevenueCat SDK into the tested domain path.

`CompanyOfOneProvisioner` is the pure standalone account planner for first-save/sign-in. It accepts the Apple/Firebase identity plus an optional existing `users` row and returns a `ProvisioningPlan`: existing users with a company are no-op, existing users without a company get attached to a new `subscription_plan = 'decks'` company, and brand-new users create both the deck-only company and linked admin user. The actual backend write remains behind `ProvisioningBackend` so the planner is unit-tested without network or main OPS auth dependencies.

`AccountDeletionPlanner` is the pure standalone teardown planner for deck-only accounts. It blocks upgraded OPS companies, companies with more than one member, and callers who are not the sole admin. Only a sole-admin `subscription_plan = 'decks'` company produces an executable plan with deck IDs for soft delete plus company/user deletion flags; backend execution remains separate from the planner.

`DecksAccountDeletionService` decodes backend deletion receipts behind the `DecksAccountDeletionTransport` seam. `DecksAccountDeletionURLSessionTransport` posts the deletion request to an injected ops-web endpoint URL with a Firebase bearer token, JSON accept/content headers, and non-2xx status handling, keeping standalone account teardown executable without hardcoded endpoint configuration or main OPS auth coupling.

`OPSDecksAccountDeletionCoordinator` binds the deletion planner to executable account teardown. It loads the stored deck-only account context, rejects missing context, rejects company snapshot mismatches, applies `AccountDeletionPlanner` before any network call, sends the backend deletion request only for an allowed sole-admin decks company, then clears local account context and signs out after the backend receipt returns.

`UpgradeContinuity` is the DeckKit pure planner for deck-only-to-full-OPS continuity. It identifies `subscription_plan = 'decks'` companies so the OPS app can route them to upgrade instead of trial/lockout logic, and it produces a conversion plan that changes only the target subscription plan while preserving the existing company id and all `deck_designs` rows.

`WasteSettings` persists as an optional `drawing_data.wasteSettings` block for standalone and shared DeckKit estimates. `EstimateGeneratorService` resolves the stored setting, falling back to the 10% default, and applies waste only to square-foot surface material quantities; per-surface `boardMaterial` can select a `perPatternWastePercent` override, while linear-foot, each, set, railing, stair, and hardware quantities remain unadjusted.

`DeckMaterial` is the brand-neutral DeckKit catalog model that generalizes shipped `BuiltInMaterial` standards without renaming their stable ids. It stores family, profile, available lengths, coverage, fastener system, finish, and display name, with defensive decode defaults so older material JSON stays readable; `DeckMaterial.from(builtIn:)` bridges existing standard area/linear materials into the richer catalog surface.

`ClientProposalBuilder` is the DeckKit sales-proposal builder for standalone OPS Decks. It accepts package-safe `ClientProposalDeck` metadata, generated estimate line items, and `ProposalBranding`, then returns grouped priced sections, required subtotal/total, optional add-on totals, formatted U.S. currency strings, and terse proposal copy. The artifact is intentionally LIGHT: it carries no code, structural, permit, safety, guarantee, or engineer-stamp claims.

`ClientRenderComposer` creates the upgraded client hero render as a deterministic DeckKit raster composite: a platform image alias (`UIImage` on iOS, `NSImage` in package tests), a full-bleed 3D/share scene image, and a proposal header with company, proposal title, and price. Rendering dimensions, typography roles, spacing, hairlines, and accent-line values are exposed through `ClientRenderTokens`; colors resolve from `OPSStyle` tokens plus the proposal branding accent, keeping visual styling tokenized rather than hardcoded.

Phase 1 preserves, but does not yet implement, the future structural/code/zoning/rendering systems. `drawing_data` unknown blocks round-trip for `framing`, `parcelZoning`, `codeOverlay`, `rendering`, `roofing`, `walls`, `openings`, `railings`, `stairs`, and `materials` so future engine payloads survive older clients. Phase 2 activates `framing` and the ground-cover subset of `terrain`; Phase 5 starts the first-class `house` block. The remaining future blocks stay preserve-only until their phases land.

### OPS Decks Phase 2 Framing Foundation (iOS — added 2026-06-26)

`drawing_data.framing` is now a first-class optional `FramingPlan` block on `DeckDrawingData`; rows that carry a frame stamp `generatedAtSchemaVersion = 2`. The block contains per-level `FramingMemberSet` arrays. Members support roles `joist`, `beam`, `post`, `ledger`, `rimBand`, `blocking`, `bridging`, and `cantilever`, with canvas-space `start`/`end`, optional `nominalSize`, `plyCount`, optional `spacingInchesOC`, optional `species`, optional `grade`, optional `sizing`, and `locked`.

Phase 2 does not perform span, footing, frost, soil, or code validation. `FramingMember.sizing` remains `nil`; `MemberSizingResult` is reserved for the Phase 3 sizing/code engine. `LoadPreset` records live load, dead load, optional snow load, species, and grade so the future engine has the user's assumptions, but Phase 2 treats those as scoping metadata rather than engineering approval.

`drawing_data.terrain` is also first-class and additive. Phase 2 only uses `terrain.groundCover`: `GroundZone(id, polygon, cover)` where `cover` is `grass`, `dirt`, `gravel`, `rock`, `concrete`, or `pavers`. `gradePoints` and `slopeSource` are declared for the later grade/footing phase but are not interpreted by the Phase 2 frame.

`DeckCapabilities.light` is embedded OPS viewer/materials-only. `DeckCapabilities.full` is the standalone OPS Decks authoring surface and includes `.materials`, `.plausibleFrame`, and `.groundCover`. Main OPS must decode, preserve, and display standardized deck design objects without exposing full framing or ground-cover authoring controls; standalone OPS Decks owns generate/edit/regenerate actions. Capability flags gate authoring surfaces and write actions only; they must never be used to delete or strip persisted deck data.

`AutoFramingEngine` is pure/offline and derives a plausible frame from the persisted outline, house edge, scale, elevation, and load preset. Regeneration follows the auto-then-preserve contract: locked/manual members survive, fresh derived members are regenerated, and the plan can move to `FramingSource.autoThenEdited`. `DeckBuilderViewModel` exposes generate/regenerate actions, load-preset restamping, ground-cover selection, per-layer visibility, and a `framingNeedsRegeneration` stale flag after footprint-affecting edits.

The 3D viewer now renders the persisted frame through `FramingSceneBuilder` and layer gates through `FramingLayerToggle`: decking, joists, beams, posts, footings, rim, and blocking. `GroundTextureFactory` creates token-aligned SceneKit materials for the ground-cover set. The SwiftUI controls live in `FramingControlsView` and must stay tokenized through `OPSStyle`/`OPSDesignKit`; raw colors, fonts, radii, and spacing are blocked by `ops-decks-ios/scripts/verify-ops-decks-style-tokens.sh`.

Framing also feeds scoping output. `FramingTakeoff` produces rough lumber rows grouped by role, nominal size, and ply count, plus rough hardware/footing counts (`joist_hanger`, `post_base`, `footing`). `ComponentEmitter` preserves the original catalog rows and adds structural `components[]` rows for `joist`, `beam`, `post`, `rim_joist`, and `blocking`; `ledger`, `bridging`, and `cantilever` are intentionally not emitted to the adapter projection in Phase 2. Missing company default mappings still skip silently, so these additive rows are safe for companies that have not configured structural products.

### OPS Decks Phase 5 House Model Foundation (iOS — added 2026-06-29)

`drawing_data.house` is now a first-class optional `HouseModel` block on `DeckDrawingData`; rows that carry house data stamp `schemaVersion = 5`. The block stores `floorLineFeet`, `storyHeights`, `openings`, and an optional `ledger` detail. It is the storage contract for wall heights, doors, windows, and cladding-driven ledger context before the Phase 5 editor, elevation renderer, opening geometry engine, and ledger strategy engine are layered on top.

`WallOpening` stores an opening on a `houseEdge` by `edgeId`, `kind`, width, height, sill height, and offset along the edge, all in inches except the floor-line datum. `OpeningKind` supports `patioDoor`, `frenchDoor`, `sliderDoor`, and `window`. `LedgerDetail` stores the existing `HouseEdgeMaterial`, an objective `attachmentAllowed` flag, and future detail fields for fastener schedule and lateral connector count. The model uses defensive decode defaults, and `DeckDrawingData` wraps the optional `house` decode so malformed house payloads drop only that block rather than failing the whole deck design.

`DeckSchemaMigration.currentSchemaVersion` is 5. New `DeckDesign` rows created by this build default to the current deck schema version, while older designs without `house` continue to decode with `house == nil`. Capability gating remains separate from persistence: OPS Decks will own full house/opening authoring; embedded OPS must preserve standardized deck data and avoid exposing full-authoring surfaces unless explicitly added as a light viewer.

### OPS Decks Phase 6 Surface Features, Patterns & Overhead (iOS — added 2026-06-30)

`drawing_data.surfaceFeatures` is now a first-class optional `SurfaceFeaturePlan` block on `DeckDrawingData`; rows that carry surface-feature data stamp `schemaVersion = 6`. The block stores per-surface decking pattern specs (`surfaceId`, `pattern`, `boardAngleDegrees`, `pictureFrameCourses`), a `FastenerSystem`, finish specs, a fascia flag, optional skirting, built-ins, and lighting. It is additive and defensively decoded; malformed feature sub-blocks drop only that optional block rather than failing the whole deck design.

`drawing_data.overhead` is now a first-class optional `OverheadStructurePlan` block on `DeckDrawingData`; rows that carry overhead data stamp `schemaVersion = 6`. Each `OverheadStructure` stores `kind` (`pergola`, `louvered_roof`, `solid_roof`), optional `roofShape`, footprint, shared `FramingMember` rows, optional shade percent, and optional product model. Pergola sizing can reuse `OverheadSizingCoordinator` and `StructuralSizingEngine`; solid and louvered roof paths hard-stop to licensed-engineer or manufacturer-stamped-table review until validated code/manufacturer packages exist.

Phase 6 adds pure DeckKit engines for board pattern layouts, board nesting, stair detail sizing, lighting takeoff, fastener/finish takeoff, overhead sizing, estimate integration, and render layers. `ComponentEmitter` now emits additive Phase 6 component rows including `decking_pattern`, `fascia`, `skirting`, `built_in`, `lighting_fixture`, `transformer`, `fastener`, `finish`, `railing_part`, `overhead_member`, and `stair_detail`. Existing component type names remain stable; consumers must skip unknown additive rows instead of failing decode.

`DeckCapabilities.light` remains the embedded OPS viewer/materials-only surface. `DeckCapabilities.full` now also includes `.surfacePatterns`, `.stairDetails`, `.surfaceFeatures`, and `.overheadStructures`. Main OPS must decode, preserve, and display standardized surface/overhead data without exposing these authoring controls. Standalone OPS Decks owns the FULL editor surfaces. Capability flags gate authoring and engine reachability only; they must never delete, strip, or down-convert persisted design data.

The FULL editor chrome lives in `DeckDrawingEditorView` and presents four public DeckKit SwiftUI sheets: `SurfacePatternSheet`, `StairDetailSheet`, `SurfaceFeaturesSheet`, and `OverheadStructureSheet`. LIGHT mode hides the pattern/stair/features/overhead entry points and shows a single passive "Available in OPS Decks Pro" stub. The internal `DeckSurfaceEditorEngineRunner` is the test seam proving LIGHT cannot invoke overhead/stair sizing engines or produce sizing numbers. All editor surfaces must stay tokenized through `OPSStyle`/`OPSDesignKit`; raw colors, fonts, spacing, radii, shadows, and spring motion are blocked by `ops-decks-ios/scripts/verify-ops-decks-style-tokens.sh`.

### OPS Decks Phase 8 Parcel Zoning Foundation (iOS — added 2026-07-01)

`drawing_data.parcelZoning` is now a first-class optional `ParcelZoningPlan` block on `DeckDrawingData`; rows that carry parcel-zoning data stamp `schemaVersion = 8`. The block stores optional site address, source metadata (`provider`, jurisdiction id, retrieval timestamp, source URL), source status (`notConfigured`, `unavailable`, `partial`, `available`, `userEntered`), parcel geometry, per-lot-line setback criteria, high-level zoning criteria, and the last cached zoning report. Malformed parcel-zoning payloads drop only that optional block rather than failing the whole deck design.

`ZoningCheckEngine` is a pure/offline DeckKit engine for the first site-plan checks. It evaluates deck footprint distance to required lot-line setbacks and deck lot-coverage percentage against a parcel boundary, returning objective `ZoningFinding` rows with current value, target value, source, and advisory copy. Unavailable zoning data returns a not-assessable zoning item instead of a false pass. This is the local engine contract that a future address-to-parcel GIS resolver will populate; the persisted model is already ready for live municipal/parcel providers without changing the deck JSON shape.

`DeckDrawingEditorModel.runZoningCheck` is gated behind FULL compliance capability. Standalone OPS Decks can run and cache zoning reports on `parcelZoning.lastReport`; embedded OPS LIGHT mode may decode and preserve the block but must not run zoning evaluation or expose full zoning authoring.

### OPS Decks P11 Builder Redesign (standalone iOS — added 2026-07-10)

The standalone OPS Decks FULL builder (`appSurface == .opsDecks`, `DeckCapabilities.full`) was rebuilt ground-up across P11-1…P11-9 (spec: `ops-decks-ios/docs/superpowers/specs/2026-07-05-ops-decks-p11-builder-redesign-design.md`, rev 3). The prior stacked-toolbars editor (`DeckDrawingEditorView`, `FramingControlsView`) is DELETED. The `deck_designs` table schema and entitlements are unchanged; new authoring state travels in the existing drawing JSON and remains FULL-capability-gated, so the LIGHT surfaces consumed by main OPS do not expose these controls. The main OPS app's own DeckBuilder (`ops-ios/OPS/DeckBuilder/`) is also untouched — P11 copied its proven interaction core into DeckKit (provenance recorded per-commit as `ported-from: … @ 28440097`); converging ops-ios onto DeckKit is a separate, later initiative.

**Architecture — one drawing system, two cockpits over one session.** `DeckBuilderView` (public, `Packages/DeckKit/Sources/DeckKit/Editor/DeckBuilderView.swift`) branches on `horizontalSizeClass` over ONE shared `DeckBuilderSession` (model + `DeckEditController` + viewport + `DeckInputEnvironment`), so iPad-multitasking size-class swaps keep the drawing, viewport, and undo history. Regular width (iPad, and Mac via "Designed for iPad") renders `DeckBuilderContent`: a full-bleed canvas under a heads-up display — top strip (back/name, five-stage ladder OUTLINE→FRAME→SURFACE→CHECK→DELIVER, status ledger, undo/redo, SHARE), floating tool cluster (SELECT · DRAW · ⊞ QUICK · MEASURE, + STAIR/RAIL in SURFACE), zoom chip + PLAN|3D toggle bottom-leading, and an on-demand glass inspector (selection properties or the stage console; never docked, never reflows the drawing). Compact width (iPhone, iPad split view) renders `DeckCompactBuilderContent`: the same canvas under two postures — DRAW (thumb tool pill, stage chip, chip ledger; state-aware opening: content→VIEW, empty→DRAW with the quick-draw template sheet leading) and VIEW (PLAN|3D toggle, member/edge cards on tap, findings sheet with zoom-to, two-tap MEASURE, MARK fronting the as-built audit, PRESENT client-safe fade) — one flip control fixed in the same corner in both postures. Every HUD cluster recedes to near-transparent while a draw/drag gesture is in flight (`DeckHUDRecede`, `DrawingMode != .idle`); pointer hover and 3D orbit never recede.

**Ported interaction core** (`Editor/DeckEditController.swift` + state machine, from the main app's "80% there" system): unified tap-select with marquee/lasso, vertex drag with merge, group move under compound snap locks, delete with orphan cleanup, copy/paste with staged repositionable preview, snapshot-stack undo/redo with adaptive cap, zoom-scaled hit thresholds `max(22, 25/canvasScale)`, edge auto-pan, drag-to-draw with start-vertex-on-commit, quick-draw perimeter walk (long-press → direction wheel → typed length) + 8 templates, typed dimension entry on any edge label. Haptic map (spec §2.8): selection tick on discrete selections, snap-ENGAGE tick on the guide none→some transition only, medium impact on commits + GENERATE/REGENERATE FRAME + permit-set export success, success notification reserved for valid (non-self-intersecting) closures — never ambient.

**Pointer layer (P11-7).** `DeckInputEnvironment` resolves touch-vs-pointer from HOVER capability, not device family (iPad + trackpad gets it live): hover pre-highlight, click-click chain drawing with Esc, typed segment lengths mid-draw (digits/Tab/Return), scroll-wheel zoom about the cursor, space-drag pan, right-click context menus, arrow-key nudge. Mac ships via "Designed for iPad" on Apple Silicon (app-target flag enabled).

**3D viewport (P11-8).** `DeckSceneBuilder` (`Scene3D/DeckSceneBuilder.swift`, ported + re-tokenized) assembles the full presentation scene from `DeckDrawingData`: per-surface decking (pattern-spec'd faces render through the P2 `DeckPatternMeshBuilder` — finally surfaced), five railing infill types + parapet walls, stairs with cut stringers, multi-level connections against one shared centroid, cladding-driven house walls with grade skirts, terrain-driven ground (`GroundTextureFactory`), overhead structures (`OverheadSceneNodes`), schematic no-shadow lighting, and a camera framed on deck + stair footprints. A generated frame renders the REAL engine members (`FramingSceneBuilder`) and drops the synthesized post/rim stand-ins. `buildCalibratedScene(from:)` guarantees uncalibrated drawings (no `scaleFactor` — the common case) render via `effectiveScaleFactor`; the primitive `buildScene` keeps its empty-for-nil-scale contract for a future AR flow. `DeckSceneView` (`Editor/DeckSceneView.swift`, UIKit-only) is the view-only viewport: SceneKit stock camera control, zero edit gestures, rebuild-on-data-equality, FRAME-console layer toggles as a live x-ray (surfaces mount under `FramingLayer.decking`), member tap → the same member card as PLAN (compact only; `DeckSceneHitMap` maps node names), Reduce Motion disables orbit inertia. PLAN|3D (`DeckViewMode`) is live on both cockpits; drafting instruments stand down in 3D; MEASURE is plan-only (renders disabled in 3D); the toggle appears only when the deck has content. Attached stairs also render in PLAN now (`DeckStairRenderPlanner`, shared 2D/3D geometry) so the two views never disagree.

**Motion + accessibility (P11-8).** Every animation rides the one OPS curve at the spec tiers (150 recede / 200 panels+wheels / 250 PRESENT + mode swaps), pinned by token-identity tests; the viewport glide runs a CADisplayLink at the display's natural rate on the same numeric curve (`OPSStyle.Animation.easeSmoothProgress`); the legacy off-curve/spring aliases are deleted. Reduce Motion: tokens soften to a 150ms crossfade, the glide steps instantly (pinned), orbit inertia off. Every HUD control/finding row/console row carries labels/values with selected/disabled traits; `DeckVitalCell` speaks label+value as one element; the compact chip ledger's semantic text uses the mobile-bright variants (`Deck.code*Mobile`), the iPad strip keeps base tones; the type ramp scales with Dynamic Type on all reading surfaces.

**iPhone functional parity (P11-9, completed 2026-07-13).** Compact width now executes the same five-stage OUTLINE→FRAME→SURFACE→CHECK→DELIVER workflow through the DRAW/VIEW cockpit. `DeckToolRack` exposes only tools valid for the active stage, while `DeckCompactSelectionActionRack` appears immediately above the thumb rack for selected geometry or a pending duplicate. PLAN and 3D now resolve framing members, outline edges, and surfaces through the same `DeckViewElementReference` / `DeckViewElementProjection` card path (`Editor/DeckViewParity.swift`; `Scene3D/DeckSceneHitMap.swift`), so direct taps and CHECK focus land on the same element/card in either view.

**Durable data + offline code.** Persisted edits are atomically cached under Application Support by `OPSDecksFileDeckLibraryStore`; signed-in sessions also append/coalesce a company-scoped, file-backed outbound queue before updating the cache, then replay mutations in order until remote acknowledgement (`OPSDecks/OPSDecksDeckLibraryStore.swift`; `OPSDecks/OPSDecksDeckOutboundQueue.swift`). `DeckProductionCodeCatalog` bundles sourced `US-IRC-2021` and `CA-BC-2024` subset packages for offline use. Missing source tables and unsupported combinations stay explicit `NOT ASSESSABLE — VERIFY ON SITE`; absent framing is `NOT ASSESSABLE — GENERATE FRAME`, and an unavailable jurisdiction never inherits a guessed package.

**Authoring + materials.** `DeckMaterialAssignmentSheet` / `DeckMaterialAssignmentEngine` route configured-edge products to explicit `EDGE`, `STAIR`, or `RAIL` destinations so estimates and takeoff retain the physical role; `OPSDecksProductCatalogClient` supplies the active company's material catalog alongside built-in standards. `DeckHouseEditorSheet` / `HouseEditingIntentEngine` author house-edge cladding, floor/story data, ledger strategy, and wall openings. `TerrainEditingIntentEngine`, the FRAME ground control, and `DeckTerrainGradeSheet` author ground cover and validated grade control points. These changes run through undoable controller transactions and persist through the same drawing-data path as geometry.

**Deliver artifacts + workspace continuity.** FULL DELIVER generates a branded client-proposal PDF from `EstimateGeneratorService`, a client-safe 3D PNG with permit/zoning/as-built metadata removed, and the permit-set PDF. Client exports use request-isolated temporary directories; all three expose sharing only after `DeckExportFileWriter` verifies exact on-disk readback (`DeckClientDeliverSheets.swift`; `DeckComplianceEditorSheets.swift`; `Rendering/ClientProposalPDFRenderer.swift`; `Rendering/ClientSceneImageRenderer.swift`). `DeckBuilderWorkspaceState` owns the active stage, compact posture, PLAN/3D mode, framing-layer visibility, and the single initial viewport fit across width-class swaps; live jurisdiction/package refresh updates `DeckBuilderSession` in place, preserving the drawing, selection, viewport, undo/redo history, and workspace.

**Verification.** Per-phase gates: `scripts/verify-ops-decks-style-tokens.sh` (zero hardcoded styling), both package suites, full `xcodebuild test`, a permanent snapshot harness (`OPSDecksTests/DeckBuilderSnapshotTests.swift`) at 393×852 / 834×1194 / 1194×834 (3D proof via `SCNRenderer` — `drawHierarchy` cannot capture SCNView; `ImageRenderer` mis-renders asset colors), and a `custom-skills:audit-design-system` pass. Compliance copy stays objective-negative (banned-word test in suite).

**Deferred (recorded, not scheduled):** MARK photo pins / note annotations require a `deck_designs` schema decision (schema frozen through P11; no `DeckDrawingData` field supports them); per-tool pointer cursor shapes (iOS-18 API for SwiftUI — the hover reticle is the precision cue on 17.6); middle-drag pan (no clean iOS-17.6 middle-button API; space-drag covers it); scroll-wheel zoom direction tuned blind in a headless sim (`zoomPerScrollPoint = 0.0035`, up = zoom in) — verify on a physical Mac/trackpad and flip if inverted; a fully native Mac idiom (menu bar, multi-window) stays demand-gated; converging ops-ios's DeckBuilder onto the DeckKit core is a separate initiative.

### Deck Builder Viewer + Selection Editing (iOS — updated 2026-06-26)

**Selection editing contract:** The Deck Builder toolbar exposes `Properties` as the single canonical selection editor. Material assignment is still available, but it opens from inside the Properties sheet rather than as a second peer toolbar option. Edge material operations batch across every compatible selected edge in one undoable change:

- House-edge cladding applies only to selected `houseEdge` edges.
- Parapet finish applies only to selected deck edges that already have `RailingType.parapetWall`.
- Built-in deck material/gate selections continue to assign catalog-backed `AssignedItem` rows to the selected geometry.

Mixed selections route through Properties so field users do not have to choose between two competing editor modes.

**Perimeter entry mode:** Deck Builder now supports a perimeter-first drawing path for field use on iPhone. Long-pressing blank canvas creates a starting vertex; long-pressing an existing vertex starts from that vertex. Selecting a single vertex also exposes a compact `Draw` toolbar action that enters the same flow. For long-press entry, the viewport does not pan while the finger is still selecting direction; the radial wheel stays centered on the original press point until lift, then the canvas animates the selected vertex back to center for length entry. The selected anchor is drawn with a steel-blue reticle so the active point remains visible while controls are open. The direction wheel has no center hub and no solid disk; it uses floating arrow/label nodes only. First-segment labels use compass language (`NORTH`, `NORTHEAST`, etc.); continuation labels use signed angles relative to the existing connected edge (`0°`, `+45°`, `-45°`, etc.). Dragging through the wheel highlights the closest sector and lifting commits that direction. During speed draw, the normal deck toolbar is hidden and the controls float over the canvas in the lower touch zone. Direction selection keeps only a floating exit control; length entry uses the standardized frosted-glass `DeckMeasurementPickerView` with an imperial/metric toggle above larger wheel pickers, the live length readout and back/commit/dictation buttons below the wheels, and a separate floating exit control that stops at the last confirmed vertex. Wheel motion publishes live length values while the user spins, driving the canvas draft preview through the same endpoint math as commit so the line length updates before the edge is saved. During active perimeter entry, canvas tap/draw/select gestures remain blocked; during length entry, two-finger pan/zoom stays available and snaps the viewport back to the selected vertex with animation when the gesture ends while preserving the adjusted zoom. While length entry is active, dragging the current preview line reorients it to the nearest allowed compass or relative angle without losing the entered length. After pressing commit/continue, the next direction wheel remains tap/drag selectable without requiring a new long press. Dictation is the length panel's hands-free default (bug 722b1606): when speech access is already granted, the panel opens the mic automatically as it lands (deferred one panel-transition beat, `OPSStyle.Animation.durationPanel` + 0.05s, so the audio-session spin-up cannot hitch the slide-in) and the spoken length fills the wheels live. The picker is recreated for every edge, so `VoiceDimensionInput` seeds its published authorization status from `SFSpeechRecognizer.authorizationStatus()` at init — the previous `.notDetermined` default silently swallowed the first mic tap of every edge (the reported "dictate button ignores taps"). A first-ever tap chains the system grant straight into listening (`requestAuthorization(thenStartListening:)`); a denied/restricted status surfaces `SYS :: DICTATION BLOCKED — ALLOW IN SETTINGS`. Tapping the mic to stop mutes auto-start for the remainder of that walk (`dictationSuppressedForSession` on `DeckBuilderViewModel`, reset by `beginPerimeterEntry`); the persisted kill switch is `deckBuilder.dictateAutoStart` (UserDefaults, default ON), surfaced as a DICTATION toggle in the deck settings sheet. The mic and continue buttons sit on the 56pt standard touch target (`DeckMeasurementPickerTokens.standardTouch`); continue keeps its 44pt visual accent circle inside the larger hit zone. The measurement UI is standardized as `DeckMeasurementPickerView` backed by `DeckMeasurementValue`; Deck Builder measurement prompts should reuse it rather than creating local wheel pickers. The Project Details `DECK` quick action resolves through the same project-attached display candidate as the deck tab: open the existing attached design when present; otherwise launch deck creation. Committed perimeter lines persist as normal `DeckVertex`/`DeckEdge` geometry with `dimensionSource = manual`; the next anchor advances to the new endpoint unless the edge snaps closed to an existing vertex.

**Copy/paste contract:** Selection toolbars expose Copy. When a clipboard exists, Paste stages a semi-transparent preview above the drawing instead of immediately committing geometry into the model. The user can drag the staged preview, then choose `Place` to commit one undoable insert or `Cancel` to discard it. Cloned vertices, edges, surfaces, assigned items, edge types, railings, stairs, labels, house materials, and surface materials receive new ids while preserving their geometry and metadata.

**Project Details 2D viewer:** `DeckTab2DView` resolves every detected surface face back to persisted `DeckSurface` payloads, including disconnected faces. The viewer provides two read-only field tools:

- Ruler mode: tap two points to show distance in feet/inches.
- Surface inspect mode: tap a face to show its square footage, perimeter, material summary, and level.

**Project Details 3D viewer:** House/wall edges render as roughly 8 ft tall walls above the deck plane. When the deck level is elevated above grade, the same house/wall edge also renders a lower wall-to-grade panel from ground level up to the deck elevation, so elevated decks do not visually float away from the house face.

### Drawing → Estimate Adapter (NEW)

**Entry point**: Deck Builder canvas → toolbar `Estimate` button → `EstimatePreviewSheet` → "Create Estimate". Same single button drives both adapter-aware and legacy-only companies; the merge logic below decides which path actually fires per row. (UX decision per spec § 7 — no second button, no parallel surface.)

**Pipeline**:

```
DeckBuilderViewModel.save()                      (writes drawingDataJSON
            ↓                                     including up-to-date components[])
DeckBuilderViewModel.mergedCatalogLineItems()
            ↓
   ┌────────┴────────┐
   ▼                 ▼
DesignToEstimateAdapter   EstimateGeneratorService
(adapter pass)            (legacy pass — geometry only,
                           no Product/options/recipe)
   ▼                 ▼
       CatalogEstimateMerger.merge(...)
            ↓
   [CatalogEstimateMerger.LineItem]
            ↓
EstimatePreviewSheet (display)   →   generateEstimate() (persist)
                                              ↓
                                     parent + child line_items rows
                                     with configured_options +
                                     resolved_unit_price +
                                     resolved_options_label snapshotted
```

**Adapter pass** (`OPS/Services/DesignToEstimateAdapter.swift`):

1. Parse `deck_designs.drawing_data` → walk the `components[]` projection (one row per visible railing / deck_board / stair_set / gate / post_set, emitted by `ComponentEmitter` on every save).
2. For each component, look up `company_default_products[component_type]` to find the default `Product`.
3. For each `ProductOption` on that product, read `option_default_source` (e.g. `$design.color`) and pull the matching value from the component's `metadata`. Fall back to `default_value` if missing.
4. Compute quantity from geometry: `linear_feet` for railing, `sqft` for deck_board, `count`/`tread_count` for others.
5. Apply `ProductPricingModifier` rows whose triggers match the resolved options. Compute `resolved_unit_price`.
6. Emit `DesignToEstimateAdapter.GeneratedLineItem` carrying the snapshot (`productId`, `componentType`, `quantity`, `configuredOptions`, `resolvedUnitPrice`, `resolvedOptionsLabel`, `lineTotal`).

Missing `company_default_products` mapping → adapter skips the component silently. Empty result is the no-op signal; the merger then falls through to legacy.

**Legacy pass** (`OPS/DeckBuilder/Engine/EstimateGeneratorService.swift`):

Walks the same drawing geometry (vertices/edges/surfaces/levels/connections) and emits flat `GeneratedLineItem` rows with categories `Surface`, `Substructure`, `Railing`, `Stairs`, `Connecting Stairs`, `Other`. Carries warning rows the adapter cannot produce (missing elevation, AR accuracy notes, multi-level connection narratives). House edges are cladding/wall boundaries, not railing targets, so they do not emit railing rows. `parapet_wall` is the built-in deck-edge railing default and emits a continuous railing/wall row without a paired `post_set`.

**Merge** (`OPS/Services/CatalogEstimateMerger.swift`):

For each `component_type` covered by an adapter row, the merger drops the corresponding legacy categories:

| Adapter component_type covered | Legacy categories dropped |
|---|---|
| `railing` or `post_set` | `Railing` |
| `stair_set` | `Stairs`, `Connecting Stairs` |
| `deck_board` | `Surface` |
| `gate` | none (gates have no dedicated legacy category) |

Uncovered types → legacy passes through. Warning rows always pass through regardless of category drop. Adapter rows always sort first; sort_order is contiguous.

**Persistence** (`DeckBuilderViewModel.generateEstimate()`):

Groups merged rows by `taskTypeId` via `CatalogEstimateMerger.groupByTaskType` (mirrors the legacy `EstimateGeneratorService.groupByTaskType` shape so the parent/child structure is identical between paths). For each child, `CreateLineItemDTO` flows the snapshot fields through to `line_items.configured_options` (jsonb) / `resolved_unit_price` / `resolved_options_label` so `CutListMaterializer` can resolve recipes at install time.

**Backwards compatibility**: companies without any `CompanyDefaultProduct` rows see the legacy preview unchanged — adapter returns `[]`, merger passes legacy through, persistence path is identical to pre-catalog behavior.

### Vinyl Auto Order (iOS — added 2026-05-20)

**Entry points:**
- Selected surfaces: Deck Builder canvas → select one or more closed surfaces → toolbar `Order Vinyl` → `VinylOrderSheet`.
- Whole design: Deck Builder settings → `ORDER ALL VINYL` → `VinylOrderSheet` with all surfaces on all levels.

The sheet converts selected deck surfaces, or every surface in the design, into a vinyl membrane cut list and order draft for field ordering. It supports single-level and multi-level drawings by resolving persisted `DeckSurface` ids back to detected face polygons after `DeckBuilderViewModel.reconcileSurfaces()`.

**Defaults:**
- Roll width: 72 in
- Seam overlap: 1.5 in
- Edge wrap: 6 in
- Run direction: `automatic`
- Direction changes: locked to one run direction by default; field user can allow turned runs for solid/non-linear colors.
- Product / variant: optional. Deck Builder settings stores `drawingData.config.vinylCatalogItemId` as the default active catalog product for vinyl. In the Vinyl Order sheet the user then picks one active variant; that variant supplies the order color and optional catalog order item. If no product is selected in settings, color stays a field-confirmed free-text input and no catalog item is written.

**Cut-list engine:** `OPS/OPS/DeckBuilder/Engine/VinylCutListEngine.swift`

For each order scope, the engine:
1. Expands measured face geometry by edge wrap and sweeps the actual polygon by roll-width bands.
2. Emits variable-length cuts by band. L-shaped and stepped surfaces do not collapse to one repeated maximum length.
3. Resolves run direction. `automatic` compares lengthwise vs widthwise waste. When directional changes are allowed, rectilinear sub-regions may rotate runs if that lowers purchased cut area.
4. Packs all cuts across all ordered surfaces against purchased roll offcut lanes. Reuse is allowed only when one continuous offcut lane has enough width and full length for the target cut; no butt-to-butt joints are planned.
5. Computes cut count, purchased square feet, reused square feet, waste square feet, and offcut reuse notes.
6. Renders length-only cut-list lines for the sheet, text handoff, and order-note cut-list section. Cut lengths render as feet/inches. Square-foot metrics stay in the summary/order totals, not in the cut-list rows.
7. Exposes each cut's band/run geometry and each face's perimeter edge types so the sheet preview can draw clipped cut bands, length labels, house-edge labels, and deck/house lap callouts with leader lines instead of evenly dividing the surface bounds.

**Preview contract:** `VinylCutPreview` uses `VinylPreviewAnnotationPlanner` for callout geometry. House-edge wrap bands use neutral gray hatching/strokes, compact monospaced labels, and a small inside offset from the house edge. Lap leader lines terminate before the text bounds rather than drawing through the label center. This applies to non-right-angle polygons as well as rectilinear layouts because all anchors derive from the selected perimeter edge midpoint plus its outward normal.

**Order persistence:** `VinylOrderSheet.createOrderAndNote()`

On `CREATE ORDER + NOTE`, iOS writes:
- `catalog_orders` row with status `draft`, title `VINYL ORDER - <PROJECT>`, and the full cut list in `notes`. If the item or project-note write fails after order creation, iOS rolls back the item and soft-deletes the draft order to avoid orphan drafts.
- Optional `catalog_order_items` row only when the user explicitly configured a local active company catalog product and picked one of its active variants. The prior heuristic text match is not used for ordering because vinyl colors/SKUs must come from the user's inventory selection.
- `project_notes` row containing the cut list and created order id.
- Standard `notifications` row for the current user with `type = catalog_order_drafted`, `deep_link_type = catalogOrders`, and `action_url = ops://catalog/orders?tab=draft`.

**Tracked inventory integration (iOS, 2026-06-22 — supersedes the marker-only v1 boundary):** The vinyl draft no longer stops at `catalog_order_items`. For companies running `inventory_mode = tracked` with the `catalog_stock_units` schema capability live, the Vinyl Order sheet bridges the cut flow into the modern stock-unit inventory via `VinylOffcutInventoryService` (`OPS/DeckBuilder/Services/`). Every write below is a SILENT no-op for untracked companies; order/marker behaviour is otherwise unchanged. This is a DISTINCT surface from the authoritative server consumption pipeline (`public.complete_project_task`) and never duplicates it.

- **Roll receipt (Phase 1).** After a successful order draft with a resolved variant + created `catalog_order_items.id`, the sheet prompts a roll-receipt confirmation (`VinylRollReceiptSheet`: roll count / length / width). Each physical roll becomes one `catalog_stock_units` row (`unit_kind = roll`, `quantity_value = 1`, `status = full`, `original_length_value = remaining_length_value = length`, `source_order_item_id` → the drafted line), plus a `receive` lifecycle event.
- **Offcut banking (Phase 2).** `VinylCutListEngine.assignOffcuts` surfaces the leftover-width remnants it computes as `VinylCutPlan.producedOffcuts` (the former hardcoded 6″ minimum is promoted to `VinylOrderSettings.offcutMinWidthInches`), and seeds the planner from on-hand offcut stock units so reuse spans jobs (banked offcuts are preferred over new purchase). Tapping BANK debits the source roll (`remaining_length_value -=`, `full → partial`), creates an `offcut` stock unit (qty 1, `status = partial`), and writes the ledger: `offcut_create` on the offcut + `adjust` on the source roll, cross-linked via `related_catalog_stock_unit_id`. An OFFCUT BANKED rail notification deep-links to `/catalog?segment=stock`.
- **Units & mirror.** Vinyl stock is measured in square feet (matching the order's sq-ft world): widths and lengths are stored in feet, and after every mutation the variant's mirrored `catalog_variants.quantity` is recomputed from the available stock units via `CatalogStockUnitAggregator` + `CatalogStockQuantityPolicy` (web `/catalog` STOCK reads the variant directly).
- **Gating.** All stock writes require `company_inventory_settings.inventory_mode == tracked` (`CompanyInventoryModeRepository`) AND `CatalogSchemaCapabilityGate.current.catalogStockUnits`. Ledger rows carry a source marker (`ios_deck_builder_cut` / `ios_vinyl_order_receipt`) so a future reconciliation can dedupe against task-completion deductions.

**`catalog_stock_unit_events` (lifecycle ledger).** The append-only parentage trail behind every stock unit. Columns: `catalog_stock_unit_id`, `catalog_variant_id`, `related_catalog_stock_unit_id`, `event_type` (CHECK allows exactly `receive, consume, scrap, offcut_create, adjust, reserve, release, restore, delete`), `from_status`/`to_status`, `quantity_delta`, `remaining_length_delta`, `payload` jsonb, `marker` (idempotency/provenance), `notes`, `created_by` (defaults `private.get_current_user_id()`), `created_at`. `company_id` is NOT NULL and enforced by anon (firebase-bridge) RLS, which also requires the referenced stock unit + variant to already exist for the company — so callers MUST create the stock unit server-side before emitting its events. The table is IMMUTABLE: no `updated_at`/`deleted_at`. iOS mirrors it as the `CatalogStockUnitEvent` @Model (schema **V10**) through `CatalogStockUnitEventRepository`, registered in `SyncTypes` at sync **priority 13** (after stock units = 12, variants = 11) as an inbound-fetch-only entity keyed off `created_at` (insert-or-skip merge, no tombstone path).

**Project marker:** The project Details tab and the Vinyl Order sheet expose a
Deck Builder-gated `VINYL` marker. Users with project edit access can toggle
`projects.vinyl_order_status` between `not_ordered` and `ordered`; `ordered`
also stamps `vinyl_ordered_at` and `vinyl_ordered_by`. This marker is a status
field only. It does not create catalog orders, inventory deductions, recipes, or
task material rows.

### VINYL ORDERS Board + Bulk Order Wizard (iOS — 2026-07-16)

Cross-project vinyl procurement console replacing the Job Board's inline
vinyl filter mode (the `VinylOrderStrip` and `vinylFilter` plumbing were
deleted; `VinylTaskFilter` detection stays). The `VINYL` pill presents
`VinylOrdersBoardView` as a full-height sheet:

- **Population:** company projects `status ∈ {accepted, in_progress}` with ≥1
  non-deleted vinyl task not `TaskStatus.completed` — quotes are not
  procurement, finished jobs are history, and a job whose vinyl tasks are all
  done has left the vinyl phase. Pure grouping/sort in `VinylOrdersBoardModel`
  (unit-tested): `// TO ORDER` by earliest incomplete vinyl-task start
  (unscheduled after scheduled, newest created first), `// ORDERED` by
  `vinyl_ordered_at` desc. Glance rows are marker-driven — zero geometry work
  at list render; materials decode lazily on expand (memoized per design
  revision).
- **Expanded row:** order record (design's frozen `DeckMaterialsSnapshot`
  first — color, PO, sq ft or `N ROLLS @ L'`, cut-group lines, stick/bucket
  counts — falling back to marker `vinyl_color`/`vinyl_po`), client, address,
  `OPEN PROJECT` (dismiss → `AppState.viewProjectDetailsById`), and
  `CLEAR ORDERED` (confirmation → `DeckMaterialsOrderService.clearOrdered`,
  which nulls all five marker fields).
- **Bulk MARK ORDERED** (`projects.edit`): serial commits through
  `VinylBulkMarkService` — full snapshot freeze where the display-candidate
  design resolves materials (identical to the Details-tab path), marker-fields
  write otherwise (config-carried color still recorded). Partial failures
  collect into an `n MARKED · m FAILED` banner whose RETRY reruns only the
  failed subset.
- **Bulk ORDER wizard** (deck_builder feature + `deck_builder.view` +
  `projects.edit`): one review page per job — `// COLOR` (catalog variant via
  the shared `VinylCatalogSelection` helpers, free-text + `USE FIELD CONFIRM`
  fallback), `// PO` (defaults to project title), `// CUTS` + extracted
  `VinylCutPreview` roll visualization, collapsed `// LAYOUT` knobs (direction/
  pattern/roll/seam/wrap session-transient; order mode + roll length persist to
  `materialsSettings`). Degenerate jobs (no drawing / unconfirmed scale) order
  color + PO only, honestly labeled. CONFIRM writes the color pick through to
  the design config exactly like the order sheet.
- **Consumables + send:** `VinylConsumablesAggregator` (unit-tested) sums
  sticks ACROSS jobs then ceils once per type — drip + 90 flash tubes at
  `flashingPerTube` (default 30), clip tubes at `clipPerTube` (default 50),
  both device-level @AppStorage (`deckBuilder.vinylOrder.*`); glue sums
  per-design area/coverage ratios with one final ceil. Steppers seed from the
  suggestion; zero lines are omitted. `VinylBulkOrderComposer` (unit-tested
  against Jackson's exact format) assembles per-job sections (`PO [project]` /
  `Color: [color]` / cut lines through the user's existing cut template +
  separator; full-roll jobs emit their rolls line) plus a consumables tail with
  no stick lengths on tube lines. `TEXT ORDER` opens Messages (recipient chosen
  there — no supplier entity); on `.sent` every job commits through
  `VinylBulkMarkService` with the page's color/PO/settings frozen into each
  snapshot (snapshot gains additive `po`). `COPY ORDER` fallback requires the
  explicit `COPIED. MARK n ORDERED?` confirm. ONE summary notification
  (`vinyl_bulk_ordered`, `// VINYL ORDERED`, `n PROJECTS · <date>`) — never n.
- **Ordered rows are not selectable** — re-ordering requires CLEAR ORDERED
  first, so double-ordering is structurally impossible.

Spec: `ops-ios/docs/superpowers/specs/2026-07-16-vinyl-orders-board-design.md`.
Snapshot proofs: `ops-ios/docs/artifacts/vinyl-orders/`.

### Deck Materials List (iOS — added 2026-07-06; editable ordered record + full-roll ordering added 2026-07-07)

The project Deck tab (`DeckTabView`) carries the auto-calculated materials
list as a full sibling tab — the mode row reads `3D | 2D | ☰`
(`DeckTabViewMode.materials`, 2026-07-16; previously a `// MATERIALS` section
scrolling below the viewport). The picker owns the LEADING ~3/5 of the screen
(`containerRelativeFrame`), the materials segment is a `list.bullet` glyph
(the shared `SegmentedControl` gained icon-capable options on the same
underline grammar, with a VoiceOver label), and the EDIT verb anchors the far
right. The MATERIALS tab body is the vinyl cut list, drip edge / clip / 90°
flashing totals + stick counts, and glue buckets; the card's `// MATERIALS`
header is gone (the segment names it). Pull-to-expand (and its cue) is inert
while the materials tab is showing — it is a canvas affordance, and the
viewport→card height collapse would otherwise stream a transient "pull"
through the overscroll probe and open fullscreen on a plain segment tap. Non-vinyl designs show a quiet empty state
("NO VINYL ON THIS DESIGN" + the assign-vinyl path) instead of a blank tab —
`DeckMaterialsSection.body` hangs its recompute `.task` off a real `VStack`
container, never `Group` (a childless `Group` forwards modifiers to nothing,
so the task would never fire and `resolved` would deadlock nil). The
fullscreen viewer stays canvas-only: its presenter remaps `.materials` to
`.twoD` on open and its own control keeps just 3D/2D.

**Pure engine stack** (`OPS/DeckBuilder/Engine/`), each a pure, unit-tested
function composed by `DeckMaterialsResolver.resolve`:

- `VinylOrderScaleResolver` — the strict vinyl-order scale, extracted verbatim
  from `DeckBuilderViewModel` so read-only surfaces resolve scale without the
  editor view model. Any stale/disagreeing dimension → nil (CONFIRM ONE EDGE
  LENGTH).
- `DeckMaterialsInputBuilder` — read-only equivalent of
  `vinylOrderSurfaceInputs`: persisted `DeckSurface` ↔ detected-face Jaccard
  matching WITHOUT `reconcileSurfaces()` mutation, plus a detected-faces fallback
  for legacy empty stores. Returns each input paired with its assigned area items.
- `DeckVinylDetection` — smart auto-detect (spec § 5). A surface is **vinyl** iff
  it carries a vinyl-ish area item (`id == "std.decking.vinyl"`, OR name contains
  "vinyl", OR its `productId` resolves — through `Product.linkedCatalogItemId` — to
  a linked `CatalogItem` whose name/description contains "vinyl"). The detector is
  pure: callers inject a `productId → vinyl-hint` map built by `DeckVinylHintBuilder`
  (keyed by `Product.id` — what an `AssignedItem.productId` references — with each
  product's own name folded together with its linked catalog item's name +
  description). NB: an `AssignedItem.productId` is a **Products**-table id, not a
  `CatalogItem.id` — the two are distinct id spaces bridged by
  `Product.linkedCatalogItemId`; a map keyed by `CatalogItem.id` never matches. A surface
  with a non-vinyl area material is **excluded** even under a job signal. An
  **unassigned** surface joins the vinyl set only when the job carries a vinyl
  signal: a non-deleted `ProjectTask` whose `taskType.display` contains "vinyl"
  (case/diacritic-insensitive), OR `drawing_data.config.vinylCatalogItemId` is
  set. Adds the `std.decking.vinyl` "Vinyl Membrane" built-in area standard.
- `DeckMaterialsEngine` — classifies each vinyl-face edge (first match wins):
  interior seam (vertex pair shared by ≥2 detected faces on the level) → no
  flashing; house edge → 90 flash; parapet-wall railing → 90 flash; otherwise
  (incl. stair-carrying edges, full span) → drip edge + clip. Drip and clip share
  the same edge set and feet; each has its own stick length. `sticks =
  ceil(exactFeet / stickFeet)`; totals display as whole feet rounded up; a
  zero-length class shows `—`. Glue = `ceil(vinyl surface area ÷ coverage)` on the
  actual `PolygonMath.realWorldArea` (not ordered-with-waste area). The vinyl
  block reuses `VinylCutListEngine.makePlan` (no offcut seeds in the tab's
  read-only context).

**Presets.** `drawing_data.materialsSettings` (`DeckMaterialsSettings`) holds
crew-editable presets: `glueCoverageSqFt` (default 400, clamp 100–1000 step 25),
`dripStickFeet` (8), `ninetyStickFeet` (8), `clipStickFeet` (10, all clamp 4–20
step 1), plus the two full-roll fields `orderMode` (`VinylOrderMode`: `.cutList`
default / `.fullRolls`) and `fullRollLengthFeet` (default 75, clamp 25–300 step 5).
The live section adds an `ORDER` segmented control (`CUT LIST | FULL ROLLS`) and,
in roll mode only, a `ROLL LENGTH` stepper. Inline steppers/controls write the
whole node back to the design JSON (marks `needsSync` → syncs company-wide). The
same `orderMode`/`fullRollLengthFeet` fields are read/written by the Vinyl Order
sheet SETTINGS section, so the card and the sheet are one source of truth. Preset
editing is allowed at `deck_builder.view` (a calculator preference, not geometry).

**Editable ordered record (confirm step).** MARK ORDERED must capture what was
*actually* ordered, not just the calculator's suggestion. Both entry points, when
a materials list resolves, present `VinylOrderConfirmSheet` (`// CONFIRM ORDER`)
first: every orderable quantity — vinyl (sq ft in cut-list mode, ROLLS with a
read-only ≈ SQ FT echo in roll mode), drip/clip/90 stick counts, glue buckets — is
pre-filled with the calc value and nudgeable, with a `RESET TO CALCULATED` action
and a medium-haptic `CONFIRM ORDERED`. Confirming returns a
`DeckMaterialsOrderConfirmation` that `DeckMaterialsOrderService.markOrdered(confirmed:)`
freezes as the ordered truth. The snapshot's display quantity fields
(`vinylOrderedSqFt`, `dripSticks`, `clipSticks`, `ninetySticks`, `glueBuckets`,
plus `orderedRollCount` in roll mode) now carry the CONFIRMED values, while the
drift-relevant geometry fields (`cutGroups`, flashing exact feet, `glueAreaSqFt`,
`vinylSurfaceCount`) stay calc-derived. `isOrderedEdited` (true when any confirmed
value ≠ its calc value at order time) drives a subtle `ADJUSTED` tag by the stamp.
An `EDIT ORDER` action on the ordered card re-opens the confirm sheet pre-filled
with the *current* stored values (RESET still targets the calculator) and rewrites
via `DeckMaterialsOrderService.editOrder` — a local-only path that overwrites only
the confirmed quantity fields and preserves the frozen geometry, order timestamp
and orderer verbatim, so the drift key is byte-identical (a correction never needs
CLEAR + re-order and never touches `DESIGN CHANGED SINCE ORDER`). Human quantity
edits are never a drift input.

**Ordered snapshot + drift.** MARK ORDERED (both entry points — the Vinyl Order
sheet PROJECT MARKER section and the Details-tab `VinylOrderMarkerSection`) routes
through the shared `DeckMaterialsOrderService`, which freezes the full materials
list into `drawing_data.orderedMaterials` (`DeckMaterialsSnapshot`) FIRST
(local-only), then writes the `projects.vinyl_order_*` marker trio; if the marker
write throws it reverts the local snapshot so the two never disagree. CLEAR
ORDERED removes the snapshot node and clears the marker. While a snapshot exists
the section renders the frozen values, locks the presets, and stamps `ORDERED
<DATE>` (roll-mode orders read `N ROLLS @ L' × W"`). Drift is detected by recomputing the live list with the snapshot's own
settings and comparing a seed-/label-independent `DeckMaterialsDriftKey` (the
multiset of all cut pieces by length × roll width, flashing exact feet ±0.1',
glue area ±0.1, and vinyl surface count) — surface renames and stock changes do
NOT flag drift; geometry / classification / scale changes surface `DESIGN CHANGED
SINCE ORDER`. The vinyl surface count is **stored** on the snapshot
(`DeckMaterialsSnapshot.vinylSurfaceCount`, frozen from the live `vinylInputs.count`
at order time), NOT reconstructed from `cutGroups` — two surfaces sharing a label
collapse to one cut group and a degenerate face produces no cuts, so a rebuilt
count would diverge from the live side and false-flag drift the instant the design
was ordered. Likewise the cut-pair multiset is **stored** as
`DeckMaterialsSnapshot.driftCutGroups` (ALL cut pieces — purchased + intra-job
reused), NOT reconstructed from the purchased-only `cutGroups`: the live drift key
counts every cut piece (`plan.surfaces.flatMap(\.cuts)`), so a deck with intra-job
offcut reuse (a small surface's strip cut from a larger surface's leftover, no
banked offcuts needed) would otherwise drop the reused strip on the snapshot side
and false-flag the instant it was ordered. `cutGroups` stays purchased-only for the
ordered display ("what was ordered"); `driftCutGroups` and `vinylSurfaceCount` are
the drift basis. Both MARK ORDERED entry points compute the snapshot over the whole
drawing via the same detection pipeline the tab uses, so their vinyl set matches
the tab's recompute and never false-flags drift.

**Full-roll ordering.** A `CUT LIST ⇄ FULL ROLLS` mode (persisted on the design as
`materialsSettings.orderMode`) lets a crew buy whole rolls instead of an exact cut
list. `VinylRollPacker.rollsNeeded(stripLengthsFeet:rollLengthFeet:)` — a pure
first-fit-decreasing bin-packer — packs the plan's purchased strips
(`plan.surfaces.flatMap(\.purchasedCuts).map { $0.lengthInches / 12 }`) into the
fewest whole rolls of `fullRollLengthFeet` (a strip never spans two rolls; a strip
longer than a roll is counted as `overlengthStripCount`, never dropped).
`DeckMaterialsEngine.compute` emits `rollCount` + `overlengthStripCount` on
`DeckMaterialsList` in roll mode (both 0 in cut-list mode). The materials card and
the Vinyl Order sheet show the order line as `N ROLLS @ L' × W"` and keep the
itemized cut list below as the on-site cutting guide; a `CUT LONGER THAN ROLL`
banner appears when `overlengthStripCount > 0`. The Vinyl Order sheet's SUMMARY,
CREATE ORDER + NOTE body, and text-message body express whole rolls in roll mode
(the catalog line-item quantity stays sq ft — the catalog unit). Roll length
(default 75') is distinct from the inventory `receiveRolls` physical-roll default
(150'); they are not merged. **Order mode is a purchasing choice, never a design
change** — `DeckMaterialsDriftKey` is geometry-only, so switching modes on an
ordered design never flags drift. Sticks and glue are unaffected by roll mode.

**New `drawing_data` JSON fields (additive, zero migration):**
`DeckMaterialsSettings.orderMode` + `.fullRollLengthFeet`; `DeckMaterialsSnapshot.orderMode`,
`.fullRollLengthFeet`, `.orderedRollCount` (`Int?`, roll mode only), `.isOrderedEdited`.
All decode with `decodeIfPresent` + calc-fallback defaults (`.cutList`, 75, nil,
false), so every legacy design/snapshot round-trips byte-behavior-unchanged.

**Text handoff:** The sheet can open `MFMessageComposeViewController` with no prefilled recipients. The user chooses the contact. The default message body contains only color and purchased cut lengths:

```
Color: [color]
[cuts]
```

The default cut row template is:

```
-[quantity] @ [length]
```

The `// TEXT TEMPLATE` section in `VinylOrderSheet` lets the user edit the message template, the per-cut row template, and the cut joiner (`lines` or `comma`). Message tokens: `[color]`, `[cuts]`, `[cut_count]`, `[rolls]` (the full-roll summary `N ROLLS @ L'` in roll mode; empty in cut-list mode, so an unused `[rolls]` token quietly disappears). Cut row tokens: `[quantity]`, `[length]`, `[surface]`, `[roll_width]`. Legacy `{{color}}`, `{{cuts}}`, and `{{cut_count}}` tokens still render. If the device cannot send SMS, it copies the rendered text to the clipboard.

### Cut-List Materialization (NEW)

Recipes resolve at install-task creation, **not** at estimate creation. When a project transitions to `.inProgress` and install tasks are generated:

1. For each `ProjectTask` with a `sourceLineItemId`, load the line's `configured_options` snapshot.
2. Walk every `ProductMaterial` row for the line's product:
   - Variant-pinned (`catalog_variant_id` non-null) → emit one `task_materials` row with that variant.
   - Family-pinned (`catalog_item_id` non-null) → resolve `variant_selector` against `configured_options`, find the matching `catalog_variant`, emit one `task_materials` row.
3. Multiply `quantity_per_unit` by line `quantity` (and by `configured_options[scaled_by_option_id]` if `scaled_by_option_id` is non-null).
4. Insert `task_materials` rows in a single transaction. The field crew sees the cut list pinned to specific SKUs ready for stock deduction.

`CutListMaterializer` lives in `OPS/Network/Sync/`. The flow is idempotent — re-running the materializer for the same task replaces the existing rows.

### Architecture Components

#### CatalogView (iOS)
**Location:** `OPS/OPS/Views/Catalog/CatalogView.swift`

Top-level container hosting the STOCK / PRODUCTS segmented control + kebab menu. Drives the threshold banner + persistent notification.

#### CatalogStockListView / CatalogStockGridView / CatalogStockTableView / StockQuickAdjustSheet / VariantDetailView (iOS)
**Location:** `OPS/OPS/Views/Catalog/Stock/`

Three view modes for the variant list share `EnrichedVariantRow` for sort/filter/search state and differ in row rendering. TABLE mode uses `Grid` with horizontal scroll for wide families. `StockQuickAdjustSheet` is the default tap target and stays focused on stock count changes. `VariantDetailView` is the full detail drill-in for SKU/unit/threshold edits, family image upload, and variant option-value editing.

#### VariantFormSheet (iOS)
**Location:** `OPS/OPS/Views/Catalog/Stock/VariantFormSheet.swift`

Form for creating/editing a variant. Sections:
- **Variant Details** (always expanded): family picker (`CatalogItem`), option-value selectors per option on the family, quantity, unit, SKU.
- **Pricing & Thresholds** (collapsible): price override, unit cost override, warning/critical threshold (with effective-threshold preview from family/category fallback).
- **Notes**.

Family creation deep-link: tap "+ add family" within the family picker to open `CatalogFamilyFormSheet`. Editing an existing variant replaces its option-value join rows through `CatalogRepository.replaceVariantOptionValues`.

#### Catalog Setup Data Foundation (iOS — data only, added 2026-05-21)

Phase 2 of the catalog/inventory setup redesign adds the local/server data surface required for the future setup UI without changing the visible catalog screens.

**Server migrations**:
- `migrations/2026-05-21-04-catalog-stock-units.sql` creates `catalog_stock_units` for physical rolls/offcuts/lots under `catalog_variants`.
- `migrations/2026-05-21-05-catalog-setup-relationships.sql` adds `product_bundle_items.relationship_kind`, `suggestion_reason`, `compatibility_selector`, creates `catalog_product_option_mappings`, and leaves the existing normalized SKU database guard aligned with live production.

**iOS data layer**:
- SwiftData V8 adds `CatalogStockUnit` and `CatalogProductOptionMapping` through `OPSSchemaCommon.v8CatalogSetupModels`; V3-V7 keep a frozen legacy `ProductBundleItem` model so the V8 relationship fields do not alter historical schema fingerprints.
- `ProductBundleItem` sync carries `relationshipKind`, `suggestionReason`, and `compatibilitySelectorJSON` only after `CatalogSchemaCapabilityGate` proves the target has those columns. Legacy targets still write required bundle rows without the new columns.
- `SyncEntityType` includes `catalogStockUnit`, `catalogProductOptionMapping`, and `productBundleItem`; `InboundProcessor` and `DataActor` merge/tombstone those rows with the standard `needsSync` guard. `catalogStockUnit` and `catalogProductOptionMapping` are skipped until `CatalogSchemaCapabilityGate` proves the target tables exist.
- `CatalogStockUnitAggregator` rolls up available physical units by variant. Only `full` and `partial` units count as available; consumed/reserved/scrapped rows remain synced history but do not inflate availability. Roll/offcut units mirror area when remaining length and width share a unit; otherwise they mirror one length unit or fall back to count.
- `CatalogStockQuantityPolicy` is mirrored aggregate: current stock/order screens keep reading and writing `catalog_variants.quantity`; stock-unit mutations must mirror their available aggregate back to that variant quantity with the basis shown to the operator.
- `ProductBundleCompositionGrouping` groups bundle rows into required vs suggested children. Required rows participate in bundle rollup pricing/materialization; suggested rows render as add-ons and are preserved separately by the edit surface.
- `CatalogProductOptionMappingValidator` and `CatalogVariantIdentityValidator` enforce mapping shape and duplicate matrix signature conflicts. Duplicate SKUs are warning-level in the iOS setup helper because live DB uniqueness remains the final write guard.

**Identity policy**: normalized SKU is database-unique per company on live production, so submitting a duplicate can still fail server-side. iOS setup validation warns on duplicate SKU but does not treat it like a matrix blocker. Matrix signatures are blocked in iOS only for now; no DB uniqueness constraint is applied because live Supabase verification on 2026-05-21 found an active Diverter family with duplicate option-value signatures that would fail the constraint.

#### Catalog Setup Flow (iOS — added 2026-05-21)

`OPS/Views/Catalog/Stock/CatalogSetupFlowSheet.swift` is the field setup surface launched from Catalog `⋮ -> STOCK -> Stock Setup`. It is additive to the existing single-family and single-variant sheets.

- Family step captures the stock family name, description, image URL, category, default unit, and default thresholds.
- Attributes step creates company-defined axes and values. The flow is generic; vinyl membrane is only one possible material system.
- Matrix step generates variant drafts from the cartesian product and lets the operator mark invalid value combinations before variants exist.
- Variant step assigns SKUs, unit overrides, and threshold overrides. Duplicate SKU conflicts render as warning-level; duplicate matrix signatures block commit.
- Stock step adds physical roll/offcut/unit rows per enabled variant, including label, lot code, original length, remaining length, width, unit, quantity, location, status, notes, and an on-screen mirrored quantity summary. For dimensional roll/offcut rows, the summary states that variant quantity mirrors area when length and width use the same unit.
- Product Link step can link the new family to a sellable Product and, when the schema capability gate is live, map catalog axes/values to existing Product option axes/values. It also opens the shared iOS Product option authoring sheet for the selected Product so newly authored `select` options and values become available to the mapping pickers without changing the Catalog Setup commit boundary.
- Review step summarizes axes, variants, units, SKU warnings, and matrix blockers. Offline and save-error states keep the draft on screen and do not dismiss the sheet.

Commit order is repository-backed and normal app-path only. Before the first write, `CatalogSetupFlowSheet` refreshes `CatalogSchemaCapabilityGate`; if the draft has stock units and `catalog_stock_units` is unavailable, commit is blocked before family/options/variants can be created. Product-option mappings are validator-backed before commit so stale value selections cannot write bridges under the wrong product option. Current Phase 5 iOS save uses the `saveCatalogSetup` RPC boundary; Product option authoring is a separate explicit Product workflow through `ProductRichnessRepository` and existing tables. Suggested bundle add-ons remain outside required rollup pricing via `ProductBundleCompositionGrouping.requiredRollupTotal`, and the bundle edit/read-only surfaces continue to render suggested rows separately.

**Local runtime QA** (DEBUG only): launch the iOS app with environment `OPS_CATALOG_SETUP_QA_LOCAL_ONLY=1` or argument `-OPS_CATALOG_SETUP_QA_LOCAL_ONLY` to mount `CatalogSetupQALocalHost` instead of the authenticated production shell. The host uses an in-memory SwiftData V8 container, generic panel-system fixture data, local catalog permissions, and no Supabase repositories. In this mode `CatalogSetupFlowSheet` preloads a draft that reaches Family, Attributes, Matrix, Variants, Stock, Links, and Review; the final button runs a no-write QA check and leaves live catalog data untouched. The switch is compiled to `false` in non-DEBUG builds.

#### Estimate-to-Job Inventory Mode (iOS — Phase 6 draft, added 2026-05-27)

Phase 6 separates booked material demand from actual stock deduction so a company can decide whether OPS should track physical inventory before the estimate-to-job flow starts writing stock planning rows.

- `company_inventory_settings` stores the explicit company mode: `off` or `tracked`. The mode is managed through `public.set_company_inventory_mode(p_company_id, p_inventory_mode)`, derives the actor server-side, and requires `catalog.manage`.
- `project_material_demands` stores accepted-job demand as projected planning pressure. These rows do not deduct stock and do not mutate `catalog_variants.quantity`.
- `task_material_allocations` links demand and task cut-list rows to `catalog_stock_units`. Projected and overrun allocation rows are reservation/planning evidence only; consumption is written by `public.complete_project_task` through the private material helper so task status and stock movement share one transaction.
- `project_material_snapshots` and `project_material_snapshot_items` store immutable booking, release, crew-adjustment, and completion snapshots. Snapshot items keep a JSON stock-unit snapshot so later roll/offcut edits cannot rewrite what was visible when the job was booked.
- Missing product-to-stock mappings are warnings, not blockers. The workflow inserts keyed persistent `catalog_mapping_needed` notifications for operators with `catalog.manage`; resolving the mapping gap resolves only matching notification `dedupe_key` rows.
- Estimate acceptance itself is not gated by `catalog.manage`. Material projection is authorized by the acceptance transaction, same-company checks, and estimate/project/task/pipeline permissions; `catalog.manage` remains the setup permission and notification-recipient filter.

#### UniversalSearchSheet Inventory Search (iOS)
**Location:** `OPS/OPS/Views/JobBoard/UniversalSearchSheet.swift`

Universal Search includes active catalog variants from the V3 catalog model before legacy inventory rows. Search text uses the same `EnrichedVariantRow.searchText` contract as STOCK, and tapping a catalog result opens `VariantDetailView`.

#### CatalogProductsListView (iOS)
**Location:** `OPS/OPS/Views/Catalog/Products/CatalogProductsListView.swift`

List of `Product` rows showing pricing summary ($X / unit), option count, recipe row count. Filters by type / kind / "has recipe". Tap row → `ProductDetailView`. When the company has no active products and the operator has `catalog.products.manage`, the empty state exposes `SET UP PRODUCTS` and opens the guided product setup flow.

#### GuidedProductSetupFlow (iOS)
**Location:** `OPS/OPS/Views/Catalog/Products/GuidedProductSetupFlow.swift`

First-run product setup flow launched from Catalog `⋮ -> PRODUCTS -> Guided Setup` or the no-products empty state. It is a seven-stage full-screen wizard:
1. Prime the operator on the product setup target.
2. Pick the setup mix: services, goods, bundles.
3. Create a service row with name, price, unit, category, and required task-type linkage.
4. Create a good row with name, sell price, optional unit cost, unit, and category.
5. Assemble a bundle from saved service/good children with AUTO or OVERRIDE pricing and optional task-type linkage.
6. Write the recipe/material requirements for the saved product or bundle. The recipe stage explains the rail-install pattern explicitly: package -> task link -> required stock rows such as posts, rails, brackets, screws, and caps. It can pick existing stock variants or open the draft material sheet to create/select stock-backed requirements from scratch before saving `product_materials`.
7. Review the rows saved in this run, including recipe row count, and finish.

The flow commits directly through the same repository/DTO contracts used by the tailored product sheets: `ProductRepository.create` for service/good/bundle rows, `ProductBundleItemRepository.create` for bundle child rows, and `ProductRichnessRepository.createMaterial` for variant-pinned recipe rows. It writes `task_type_id` and `task_type_ref` for guided service rows, supports optional bundle task-type linkage, and inserts returned DTOs into SwiftData immediately so later stages can use newly-created children. Bundle child partial failures keep the bundle row and expose a retry path for unflushed children rather than silently losing composition. Recipe row partial failures keep only the failed draft rows in the stage so the operator can retry without duplicating successful material requirements.

The guide includes explicit `EXIT`, per-stage back/skip behavior, validation copy in the fixed footer, a completion notification (`PRODUCT SETUP COMPLETE`), a `DONE` close action, and a `SET UP STOCK` bridge for operators who want to bulk-build physical inventory after the sellable rows exist. Product and recipe creation are disabled while offline because these rows write through Supabase repositories rather than a queued draft path.

#### ProductDetailView (iOS — view + light edits)
**Location:** `OPS/OPS/Views/Catalog/Products/ProductDetailView.swift`

iOS exposes light edits only — full configurable-Product authoring lives on web. Quick-edit fields: name, base_price, pricing_unit, type, taxable, active. Read-only sections (collapsed if empty): Options · Pricing modifiers · Recipe. Recipe rows are tappable → drill to the linked `CatalogVariant` or family selector.

#### Product Create Sheets (iOS)
**Location:** `OPS/OPS/Views/Catalog/Products/NewServiceSheet.swift`, `NewGoodSheet.swift`, `NewBundleSheet.swift`

Tailored product create sheets remain the dedicated freeform creation surfaces from the PRODUCTS menu. Guided setup uses the same repository/DTO save contract in a staged onboarding flow rather than opening the sheets. Services lock `kind='service'` and `type='LABOR'`; goods lock `kind='material'` and `type='MATERIAL'`; bundles lock `kind='package'`, support composition through `product_bundle_items`, and support richer task-type linkage in `NewBundleSheet`.

#### CatalogOrdersSheet (iOS)
**Location:** `OPS/OPS/Views/Catalog/Orders/CatalogOrdersSheet.swift`

Three-tab sheet: Suggested · Drafts · Sent.
- **Suggested** — variants below threshold, grouped by supplier heuristic. Bulk action: "Draft all" → creates a `catalog_orders` row with status `.draft`.
- **Drafts** — editable orders not yet sent. Per-order actions: edit lines, send (status → `.sent`), cancel.
- **Sent** — read-only history. Per-order action: mark fulfilled (status → `.fulfilled`, increment `catalog_variants.quantity` by each `quantity_requested`; when stock units are live, receiving also creates/updates physical unit rows and mirrors the aggregate back to the variant).

#### CatalogSnapshotListView (iOS)
**Location:** `OPS/OPS/Views/Catalog/Snapshots/CatalogSnapshotListView.swift`

Variant-aware snapshot history. Detail view shows family name + variant label per row.

#### Catalog CSV Import (iOS — added 2026-05-08)
**Locations:**
- Sheet: `OPS/OPS/Views/Catalog/Import/CatalogImportSheet.swift`
- Parser: `OPS/OPS/Services/CSVParser.swift`
- Mapper: `OPS/OPS/Services/CatalogCSVMapper.swift`
- DTOs: `OPS/OPS/Network/Supabase/DTOs/CatalogImportDTOs.swift`
- Repository: `OPS/OPS/Network/Supabase/Repositories/CatalogImportRepository.swift`
- RPC SQL: `OPS/OPS/Migrations/2026-05-08-catalog-import-rpc.sql`

Atomic CSV import of catalog families + variants. Replaces the prior `CatalogImportStub` placeholder. Entry point: catalog `⋮ -> STOCK -> Import`, gated on `catalog.import`.

Four-step flow, single sheet, large detent:
1. **PICK** — `.fileImporter` for `.csv` files (single file at a time). UTF-8 / ASCII decoding.
2. **MAP** — column-mapping. Auto-suggests bindings from header names (fuzzy match). Required: `family_name`, `quantity`. Optional family-level: description, category, default unit, default price, default unit cost. Optional variant-level: SKU, variant unit, price/cost overrides, warning/critical thresholds.
3. **PREVIEW** — calls `catalog_import_validate` (the dry-run RPC). Shows per-row errors with line numbers + the offending field, or a green totals card on success. **Never writes.** "FIX & RETRY" returns to MAP; "APPLY" advances to step 4.
4. **APPLY** — calls `catalog_import_apply`. Atomic: validates + INSERTs every family + variant in a single transaction. Success haptic + dismiss-to-Done; failure shows error with RETRY (safe — same payload either re-fails or lands).

**RPC contract** (`OPS/Migrations/2026-05-08-catalog-import-rpc.sql`):

- `public.catalog_import_validate(p_company_id uuid, p_payload jsonb) -> jsonb` — pure validator, never INSERTs.
- `public.catalog_import_apply(p_company_id uuid, p_payload jsonb) -> jsonb` — runs the same validation, then INSERTs in one transaction. Both SECURITY DEFINER, GRANT EXECUTE TO authenticated, guarded by `private.get_user_company_id() = p_company_id`.

Payload schema: `{families: [{row_index, name, description?, category_id?, default_unit_id?, default_price?, ...}], variants: [{row_index, family_row_index, sku?, quantity, price_override?, ...}]}`. Variants reference families by `family_row_index`; the apply RPC resolves that index to the new family uuid post-INSERT and returns both maps in `created_family_ids` / `created_variant_ids`.

Result schema: success → `{success: true, created_family_ids, created_variant_ids, totals}`; failure → `{success: false, errors: [{scope, row_index, field, reason}, ...]}`. Scopes: `family` | `variant` | `payload` | `mapping` (mapping errors are local-only; never returned by the server).

**Validation rules** (enforced by both RPCs):
- Family `name` non-empty after trim; `category_id` / `default_unit_id` (if set) must resolve to active rows in the same company; numeric fields >= 0.
- Variant `quantity` required, numeric, >= 0; `family_row_index` must reference a family in the same payload; `sku` collisions against active variants in the company are rejected by the RPC before insert and by the live normalized per-company SKU uniqueness guard if they reach the database.

**CSV SKU collision policy**: any non-empty SKU that matches an existing active variant in the company is rejected. Fix the CSV (or remove the SKU column from the mapping) and retry. This stricter import policy is separate from the interactive setup helper, where duplicate SKUs are warning-level until submit.

**What gets created**: one `catalog_items` row per unique `family_name` (case-insensitive after trim) + one `catalog_variants` row per CSV data row, pointing at the new family. Family-level fields are taken from the FIRST CSV row that introduces a given family_name; later rows for the same family contribute additional variants only.

**What gets skipped**: the import never modifies existing rows — only INSERTs. There is no upsert path. Re-importing the same CSV creates duplicate families (each with their own new uuid). The kebab Snapshots feature is the right path to roll back a bad import.

#### Spreadsheet Import — legacy (iOS)
**Location:** `OPS/OPS/Views/Inventory/Import/SpreadsheetImportSheet.swift`

Older multi-step wizard from the inventory era — supports CSV or XLSX, row/column orientation, variation-matrix import. Still in the codebase but no longer wired into the FAB or kebab as of 2026-05-08; superseded by the simpler atomic CSV flow above. Kept for reference only.

### Permissions

| Old | New | Purpose |
|---|---|---|
| `inventory.view` | `catalog.view` | Gate the CATALOG tab |
| `inventory.manage` | `catalog.manage` | Adjust quantity, edit variants, manage categories/tags/units |
| `inventory.import` | `catalog.import` | Bulk import |
| — | `catalog.products.manage` | NEW — author/edit Products (options, modifiers, recipes). Rich admin |
| — | `catalog.orders.manage` | NEW — draft/send/fulfill orders. Operational role |

Permission rename SQL is in migration `2026-05-06-04-permission-rename.sql`. iOS callers (`PermissionStore`) and ops-web (`auth-store`) both updated; no alias layer.

---

## 13a. Configurable Products & Recipes

### Overview

A Product carries optional layers, each `0..N`. A "barebones" Product has zero rows in every optional layer and behaves identically to today's flat product (name + base_price + pricing_unit + tax). A "configurable" Product expresses option-driven pricing, modifier rules, and recipe templates that materialize into cut lists at install time.

```
Product (always)
  ├─ ProductOption                          (0..N — knobs the user configures)
  │     ├─ kind ∈ {select, integer, boolean}
  │     ├─ affects_price · affects_recipe   (flags)
  │     ├─ option_default_source            ("$design.color" → drawing adapter)
  │     └─ ProductOptionValue (0..N)        (when kind=select)
  ├─ ProductPricingModifier                 (0..N)
  │     └─ kind ∈ {add_per_unit, add_flat, add_per_count, multiply_unit_price}
  └─ ProductMaterial                        (0..N — recipe rows)
        ├─ catalog_variant_id (pinned)  XOR  catalog_item_id + variant_selector
        ├─ quantity_per_unit              (per Product's pricing_unit)
        └─ scaled_by_option_id            (multiply by integer-kind option count)
```

### Resolver Semantics

**`ProductConfigurationResolver`** runs at line-item creation (or on every option change in the line-item editor). Given a Product and the user's `configured_options` choices, it computes:

1. Start with `product.base_price`.
2. For each `ProductPricingModifier` whose trigger matches:
   - `add_per_unit` → `unit_price += amount`
   - `add_flat` → `unit_price += amount` (single-shot, doesn't multiply by quantity downstream)
   - `add_per_count` → `unit_price += amount * configured_options[option_id]` (integer kind)
   - `multiply_unit_price` → `unit_price *= amount`
3. Snapshot `unit_price` to `line_items.resolved_unit_price`. Snapshot the chosen options to `line_items.configured_options` (jsonb). Render a printed-estimate-friendly summary into `line_items.resolved_options_label` ("TM · Black · Concrete · 4 corners").

**`RecipeResolver`** runs at install task creation (not estimate creation). Given a line item with snapshot options, it walks the product's `ProductMaterial` rows:

- Variant-pinned (`catalog_variant_id` non-null) → emit `task_materials` row with that variant directly.
- Family-pinned (`catalog_item_id` non-null) → resolve `variant_selector` against `configured_options` (`{"color":"$option.color"}` → look up `configured_options.color` → find the variant on that family with that color option-value).
- Multiply `quantity_per_unit` by the line's `quantity` (and `configured_options[scaled_by_option_id]` if set).

### Worked Example

Canpro's "Custom Composite Railing" Product:

```
Product:
  pricing_unit = linear_foot
  base_price   = $48.00

Options:
  Mount Type     select   affects_price=false  affects_recipe=true
                 source=$design.mount_type     default=Topmount
                 values: Topmount, Sidemount
  Mount Surface  select   affects_price=true   affects_recipe=false
                 source=$design.mount_surface  default=Surface
                 values: Surface, Concrete
  Color          select   affects_price=false  affects_recipe=true
                 source=$design.color          default=Black
                 values: Black, White
  Corners        integer  affects_price=false  affects_recipe=true
                 source=$design.corners_count  default=0

Pricing modifiers:
  (Mount Surface = Concrete)  →  add_per_unit  +$5.00

Recipe:
  family=Composite Board     selector={color:$color}                   qty=1.05/ft
  family=Bracket             selector={color:$color, mount:$mount_type} qty=2.5/ft
  family=Picket              selector={color:$color}                   qty=4.0/ft
  family=Top Rail            selector={color:$color, mount:$mount_type} qty=1.0/ft
  family=Screws              selector={color:$color}                   qty=18/ft
  family=Corner Hardware Kit selector={color:$color, mount:$mount_type} qty=1   scaled_by=Corners
  variant=Galvanized Anchor  pinned                                    qty=4   scaled_by=Corners
```

A 24 ft / 4 corners / Topmount / Black / Concrete configuration resolves to:
- **Unit price**: $48 + $5 (Concrete) = $53/ft → 24 × $53 = $1,272 (frozen on the line item)
- **Cut list** (rendered into `task_materials` at install task creation):

| Variant | Qty |
|---|---|
| Composite Board — Black | 25.2 ft |
| Bracket — Black — Topmount | 60 |
| Picket — Black | 96 |
| Top Rail — Black — Topmount | 24 ft |
| Screws — Black | 432 |
| Corner Hardware Kit — Black — Topmount | 4 |
| Galvanized Anchor (pinned) | 16 |

### Recipe Authoring Lives on Web

iOS exposes options/modifiers/recipe rows as **read-only** in `ProductDetailView`. Authoring requires the rich tabular editor — that experience is delivered in the next ops-web session. The named follow-up is in plan `2026-05-06-ios-catalog-variant-model.md` § 6.3 step 4.

---

## 13b. Guided Stock Setup (iOS, 2026-06-01) — Bug 5b3d4c39

### Overview
A conversational, multiple-choice, first-run inventory setup flow. The Advanced flow (`CatalogSetupFlowSheet`, § 13) is organized around the **schema** (FAMILY / ATTRIBUTES / MATRIX / VARIANTS / STOCK) and only makes sense to an operator who already thinks in OPS terms (founder rating 4/10). The reporter hit the exact failure: setting up Vinyl, they could not model "how many cuts at what lengths," and building one item at a time invites the **structure trap** (log "black vinyl", log "white vinyl", then realize too late it should have been one Vinyl family with color as a variant). Guided Stock Setup asks about the operator's physical reality in plain English, infers the correct catalog structure across the **whole** list, teaches the OPS equivalent at each step (`// IN OPS:` lines), and creates the data through the proven engine.

**Positioning:** This is a self-contained full-screen flow, a sibling to the Advanced sheet. It is **NOT** an OPS *Wizard* (the coach-mark / instruction-bar system in `OPS/Wizard/`). It uses steel-blue `OPSStyle.Colors.primaryAccent` on the single bottom CTA per screen and **never** `wizardAccent` (orange stays reserved for coach-marks). It registers no `WizardDefinition`. Colloquially the team calls it "the wizard"; in code it is `GuidedStockSetup*`.

### Flow
Full-screen push (MOBILE.md § 6.3). Five stages, driven by `GuidedStockSetupModel.stage`:
```
entry ─▶ PRIME ─▶ CAPTURE ─▶ STRUCTURE ─▶ BLUEPRINT ─▶ DONE
         intro    brain-dump  conversational  confirm    commit + summary
                  everything  per-group Qs    + warnings  + notification
```
- **PRIME** — sets expectation, removes fear. `START →`.
- **CAPTURE** — brain-dump every item (name + `STOCK · SELL · BOTH` chip). Prevents the structure trap by getting the full list out first. `ORGANIZE →` enabled at ≥1 named item.
- **STRUCTURE** — the anti-trap engine. Deterministic clustering proposes groupings; the operator confirms via multiple choice. Internal sub-steps (single self-contained sub-flow with its own back/CTAs): **grouping** (per cluster: `YES — ONE ITEM` / `NO — KEEP SEPARATE`; per single: `ONE THING` / `DIFFERENT VERSIONS`) → **attributes** (multi-select difference chips → editable value lists, prefilled from clustering; shows resulting variant count) → **measurement** (`BY THE PIECE` / `BY LENGTH` / `BY AREA`) → **stock** (per-variant counts, or full-unit dims + count + repeating offcut lengths) → **products** (capability-gated, § below).
- **BLUEPRINT** — per-family review cards (variant count, stock summary, non-blocking warnings, product/bundle summary); tap a card to route back to STRUCTURE. `BUILD IT →` (disabled offline / when nothing committable).
- **DONE** — `STOCK SYSTEM BUILT` + summary line (`2 families · 6 variants · 7 rolls · 1 offcut · 1 product · 1 bundle`), success haptic, completion notification (§ 14), actions `DONE` / `REFINE IN ADVANCED` / `ADD MORE`.

### Architecture — reuse the engine, no parallel write path
All new code under `OPS/Services/Catalog/` and `OPS/Views/Catalog/Stock/GuidedStockSetup/`:

| File | Responsibility |
|---|---|
| `CatalogSetupCommitService.swift` | **Shared** commit + reconcile, extracted verbatim from `CatalogSetupFlowSheet`. `commit(payload:saveAttempt:)` → atomic, idempotent RPC; `reconcile(payload:response:)` → merge server ids into SwiftData. Used by **both** Advanced and Guided. Conforms to `CatalogSetupCommitting` (a test seam). |
| `GuidedStockSetupModel.swift` | `@MainActor ObservableObject` state machine + the guided data types (`GuidedStockStage`, `GuidedCapturedItem`/`GuidedItemKind`, `GuidedStructuredGroup`, `GuidedAttribute`, `GuidedMeasurement`, `GuidedStockEntry`, `GuidedProductAnswers`/`GuidedBundleChild`, `GuidedCommitProgress`, `GuidedStockSummary`). Owns `commitAll(...)`. |
| `GuidedStockSetupDraftStore.swift` | File-based JSON snapshot (mirrors `CatalogSetupDraftStore`), `Documents/GuidedStockSetupDrafts/`, context key company+user+`guided` (distinct from Advanced — never clobbers). |
| `GuidedStockStructuring.swift` | Pure deterministic clustering (normalize → leading-stem buckets → similarity threshold → differing-token positions). Proposes; never auto-merges. |
| `GuidedStockDraftBuilder.swift` | Pure: confirmed group → `[CatalogSetupAttributeDraft]` + variant matrix (via `generateVariantDrafts`) + per-variant stock-unit drafts. **Deterministic client ids** (no `UUID()`) so rebuilt payloads fingerprint identically (idempotent retries). |
| `GuidedStockUnitResolver.swift` | D2: maps measurement → dimension (piece→`count`/ea, length→`length`/ft, area→`area`/sq ft), finds an active `catalog_units` row or creates one via `CatalogRepository.createUnit`. |
| `GuidedStockProductBuilder.swift` | Pure: group product answers → `[CatalogSetupSavePayload.ProductPayload]` (sell-link, recipe, bundle) using **client-id references**. |
| `GuidedStockSetupFlow.swift` + `GuidedStock{Prime,Capture,Structure,Blueprint,Done}View.swift` | Full-screen container + stage views; `primaryAccent`, top progress, offline/permission banners, resume guard, one curve (`OPSStyle.Animation.page`, reduced-motion fallback). |

**Commit orchestration (D1 — per-family loop).** `commitAll` loops confirmed groups (non-bundle families first, then bundles), per family: `GuidedStockDraftBuilder` (stock core via `makeSavePayload(selectedProduct: nil, …)`) + `GuidedStockProductBuilder` (product section injected into `payload.products`) → `CatalogSetupSaveAttempt.resolve` → `service.commit` → `service.reconcile`. Each call is atomic + idempotent, so the loop is **resumable** (committed group ids recorded in the draft; retry re-sends only unfinished families). `CommitProgress`: `idle → running(done,total) → complete(summary)` or `partial(failedGroupIds)`. Offline → held (no calls).

**Why client-id references (verified against the `catalog_setup_save` RPC 2026-06-01):** the Advanced flow only ever *links existing* products, so `makeSavePayload`'s product builder emits server ids. Guided creates everything first-run, so the product section is built directly: new products via `id:nil` + `client_id` (RPC upserts by id), product→family link via `linked_catalog_item_client_id`, recipe (`product_materials`) pinned to the new family/variant via `catalog_item_client_id` / `catalog_variant_client_id`, bundle children via `child_product_id` (sibling product's resolved **server** id — bundles commit after their children). Same structs, same RPC, same commit service — not a parallel write path.

**`products.unit_cost` persists at the RPC level (fixed 2026-06-16, migration `20260616205309_catalog_setup_save_persist_unit_cost`).** Until then `catalog_setup_save` silently dropped `unit_cost` — it was absent from the products INSERT (column list + VALUES) and from BOTH `ON CONFLICT (id) DO UPDATE` clauses (create-mode + edit-mode blocks) — so a cost an operator entered landed `NULL`. The RPC now reads `v_product_doc->>'unit_cost'` in the INSERT, mirroring `minimum_charge` (`case … else null end` → `NULL` when the doc omits it, so an explicit `0` still writes while omission stays `NULL`; deliberately NOT the `coalesce(…,0)` form used by the NOT-NULL `default_price`/`base_price`), and updates it as `coalesce(excluded.unit_cost, public.products.unit_cost)` so a conflict-update that omits cost can never wipe an existing value (a deliberate deviation from the function's uniform bare-`excluded` pattern, scoped to `unit_cost` only). Surface impact: OPS-Web's Catalog Setup Wizard already emits `unit_cost` in the payload doc (`payload-builder.ts`), so it now round-trips atomically and the wizard branch's post-commit `cost-stamp.ts` workaround was removed on reconcile (2026-06-16, commit `c4aeef8c` on `feat/catalog-setup-wizard` — the file + its tests, the route's collect/stamp call, and the `cost_stamp_failed`/`commitCostWarning` plumbing all deleted). The iOS `CatalogSetupSavePayload.ProductPayload` carries **no** cost field — iOS Guided-Catalog cost is written straight to `products.unit_cost` via `ProductRepository.create` (REST), so this RPC change does not alter current iOS behavior — but the coalesce-preserve specifically protects those REST-set costs from being nulled when the iOS Advanced "edit" flow re-upserts an existing product by id with no cost field. Body-only change; signature unchanged (`(uuid, text, jsonb) → jsonb`), so it is safe across all live iOS App Store versions sharing this DB.

### Deterministic structuring (no LLM)
Normalize each captured name (lowercase, trim, tokenize). Bucket by leading token; propose a merge when `sharedLeadingTokenCount / minMemberTokenCount ≥ threshold`. Stem → family-name candidate; differing token positions → candidate attributes; differing tokens → candidate values. Confirmation is mandatory; over-grouping is safe (`NO — KEEP SEPARATE`), under-grouping is safe (singles fall to the one-thing/versions path). Singular/plural are NOT stemmed ("screws" ≠ "screw gun").

### The Vinyl fix (stock reality)
By-length/area, **each full unit and each offcut is its own `catalog_stock_units` row** (`.roll`/`.full` and `.offcut`/`.partial`, qty 1, `remaining_length` = its own length). This is required because the mirrored-quantity aggregate (`CatalogStockUnitVariantAggregate`) sums each row's `remaining_length` **once** (it does not multiply by `quantity_value`); seven 75 ft rolls must be seven rows to aggregate to 525 ft. By-the-piece is one `.each` row with `quantity_value` = on-hand count. Zero/blank answers produce no row (never a zero-quantity unit; `CatalogSetupWorkflow.validateStockQuantities` is the commit-path guard).

### Permissions (granular — never role)
- `catalog.manage` — required to enter; gates the entry points + the flow itself.
- `catalog.products.manage` — gates the products/bundles/recipes sub-step (silently skipped if absent; stock-only path completes cleanly).
- `catalog.stock.adjust` — stock counts (held in practice by anyone who can run setup).

### Entry points
All post `Notification.Name("OpenGuidedStockSetup")`, which `CatalogView` presents as a `.fullScreenCover`: Stock empty state `SET UP STOCK` (with `// ADVANCED` posting `OpenCatalogSetup`); Catalog header `⋮ -> STOCK -> Guided Setup`; and the Advanced sheet toolbar `GUIDED` (so a stuck operator can switch down). Catalog/Product creation actions no longer live in the global FAB.

### Existing-flow hardenings (shipped here, benefit both flows)
1. **Reconcile-after-success is not a failure** — if local reconcile throws *after* `response.ok`, the server already committed; the service logs, requests a catalog resync, and returns `.resynced` (success), never reports a committed save as failed.
2. **Capability-probe transient errors** — `CatalogSchemaCapabilityGate` distinguishes a definitively-missing table (`.missing` → capability false) from a transient network error (`.unknown` → keep last-known), so a flaky network can't block a stock commit.
3. **Positive stock-unit quantity** — `validateStockQuantities` rejects ≤ 0 before commit.

### Tests
`OPSTests/Catalog/`: `CatalogSetupCommitServiceTests`, `CatalogSchemaCapabilityGateTests`, `CatalogSetupWorkflowValidationTests`, `GuidedStockSetupModelTests`, `GuidedStockStructuringTests`, `GuidedStockDraftBuilderTests`, `GuidedStockUnitResolverTests`, `GuidedStockUnitDraftTests`, `GuidedStockProductBuilderTests`, `GuidedStockCommitOrchestrationTests` (multi-family success, mid-loop partial + resume, idempotent retry, offline hold, bundle ordering).

### Android conversion notes
Mirror the deterministic structuring + the per-family idempotent commit loop. The structuring engine + draft builders are pure (no SwiftUI/SwiftData) and port directly. Reuse the same `catalog_setup_save` RPC with client-id references for new products/recipes/bundles.

---

## 14. Notification System

### Overview
Multi-layer notification system combining local (UNUserNotificationCenter), push (OneSignal), and in-app (Supabase `notifications` table) notifications. Features batching during sync, deep linking to projects, unread tracking, quiet hours, and per-type preference controls.

**In-app rail events (iOS-originated)** are created with `NotificationRepository.createNotification(_:)` (Supabase `notifications` table) followed by a `NotificationCenter.default.post(name: .notificationReceived, object: nil)` to refresh the rail. Current iOS-originated rail events:
- **Stock system built (Guided Stock Setup, 2026-06-01):** on a fully-successful guided build, a **standard** notification — title `STOCK SYSTEM BUILT`, body the summary counts (e.g. `2 families · 6 variants · 7 rolls · 1 offcut`), `action_url` `/catalog?segment=stock`, `action_label` `VIEW STOCK`, `deep_link_type` `catalog_stock`. Partial commits post **no** success notification (the in-flow RETRY governs). See § 13b.

### Task Reschedule → Push (cross-client, both origins)

When a task's schedule changes, assigned crew are notified on **both** clients — and the push is fired **server-side (ops-web → OneSignal REST)**, so it reaches a backgrounded/locked teammate independent of the Realtime socket (which iOS tears down ~30s after backgrounding). This is the background-delivery counterpart to the live foreground repaint (ops-ios `deafa95f`).

**iOS-originated** — `DataController.updateTaskSchedule(task:startDate:endDate:manualEdit:)`:
1. On a real date change of a **non-terminal** task, inserts one `notifications` row per assigned member **except the editor** (`memberId != currentUserId`) via `NotificationRepository.createNotification` → web rail.
2. Calls `OneSignalService.notifyScheduleChange(...)` → `POST {apiBaseURL}/api/notifications/send` (Firebase bearer) → `sendOneSignalPush` → OneSignal REST `include_aliases:{external_id}`, `target_channel:"push"`. Push `data:{type:"scheduleChange", taskId, projectId, screen:"taskDetails"}`.

**Web-originated** — `useUpdateTask` → `dispatchScheduleChange` → `POST /api/notifications/dispatch`:
- Fires on start/end **date, time, or all-day** change of a non-terminal task; recipients = union(prior, new `team_member_ids`).
- The dispatch route inserts `notifications` rows, checks `notification_preferences` (`schedule_changes` channel + global `push_enabled`), then sends the OneSignal push. The route is shared by other event types (`task_assigned`, `task_completed`, `project_*`, `mention`, `expense_*`).

**Identity (critical):** OneSignal `external_id` == `project_tasks.team_member_ids[]` == `notifications.user_id` == `public.users.id` (uuid). The JWT `sub` is a **Firebase uid** (iOS bridges its Firebase token into Supabase via the `accessToken` callback; ops-web verifies Firebase/Supabase tokens) and is **NOT** `users.id` (auth uid matches 0/204 rows; `firebase_uid` populated for ~51/204). Editor self-exclusion must therefore key off an explicit app-level `users.id`, never the token `sub`. This is also why the reschedule push is client-initiated rather than a `project_tasks` DB trigger — a trigger only sees the token `sub` and cannot reliably resolve the editor.

**Editor self-exclusion + terminal skip (2026-06-09):**
- `/api/notifications/dispatch` now excludes a client-supplied `actorUserId` (the actor's `users.id`, stamped centrally in `notification-dispatch.ts` from `useAuthStore`), with the token uid kept as a backstop. Previously it filtered only on `user.uid` (the Firebase `sub`), which never matched the `users.id` recipients — so a crew member rescheduling their own task on web self-notified.
- Both clients now **skip terminal tasks** (`completed`/`cancelled`) for the schedule-change ping (iOS `TaskStatus.isTerminal`; web case-insensitive status check).

**Deprecated:** the `send-push-notification` Edge Function (project `ijeekuhbatykdomumfjx`) is **orphaned** — zero callers, legacy `include_external_user_ids`/`users.device_token` targeting, inserts no rail row. Superseded by `/api/notifications/send` (iOS) and `/api/notifications/dispatch` (web). Safe to delete.

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

#### Web Notifications Drawer (OPS Web — rebuilt 2026-06-11, WEB OVERHAUL P2)

The web app surfaces notifications via a right-edge vertical drawer, triggered by a reusable `<EdgeTab>` primitive. Rebuilt in the P2 shell overhaul (`OPS-Web/docs/specs/2026-06-11-web-overhaul-p2-shell-design.md` §4.4) — the earlier hover-grow + sibling-push choreography was removed as an approved design decision: tabs are fixed-height instruments and hover only brightens + shows a tooltip.

**Components:**
- `src/components/ui/edge-tab.tsx` + `edge-tab.types.ts` + `edge-rail-layout.ts` — 28px fixed-height right-edge tab primitive + shared rail geometry/z constants (consumed by Notifications, Quick Actions, and Bug Report)
- `src/components/layouts/notifications-tab.tsx` — Notifications tab wrapper (count + severity accent/tint + `N` shortcut)
- `src/components/layouts/notifications-drawer.tsx` — 360×520 glass-dense panel: `// NOTIFICATIONS` + count header, segmented tone filters (ALL/CRIT/ATTN/INFO), row list, `SYS :: SYNC hh:mm` + CLEAR ALL footer
- `src/components/layouts/notifications-row.tsx` — row with hover-revealed primary action + dismiss × (one step); click expands body + actions for keyboard/touch
- `src/components/layouts/quick-actions-tab.tsx` + `quick-actions-drawer.tsx` — Quick Actions tab and action drawer (content-driven height, capped 452; actions carry i18n labelKeys from `quick-actions.json`)
- `src/components/ops/bug-report-tab.tsx` + `bug-report-drawer.tsx` — Bug Report tab and report form drawer (shares the rail constants)
- `src/components/layouts/edge-tab-outside-dismiss.tsx` — the single outside-click dismiss listener for the rail (drawer-local duplicates were removed)
- `src/lib/notifications/notification-meta.ts` — NOTIF_TYPE_META registry mapping NotificationType values to `{label, icon, tone}`
- `src/lib/notifications/translate-copy.ts` — i18n-keyed notification content translator (shared util)
- `src/stores/edge-tab-store.ts` — Zustand single-slot mutual-exclusion store (`activeTab: 'notifications' | 'quick-actions' | 'bug-report' | null`)

**States:**
- **Closed (default):** 28px tab flush right, fixed heights stacked with 8px gaps and group-centered on the rail: Notifications 164 (`stackOffset −126`), Quick Actions 140 (`+34`), Bug Report 96 (`+160`). Vertical Cake Mono wordmark + upright glyph; Notifications renders a count badge; severity drives the 2px accent stripe + optional 0.12-alpha tint glaze.
- **Hover:** glass brightens + tooltip (title + shortcut chip). Nothing grows, nothing pushes.
- **Open:** drawer slides in (260ms, OPS easing); the tab travels left flush with it, glyph rotates/swaps, wordmark reads CLOSE. The open drawer covers sibling tabs (z: rest tabs 1540 < drawer 1550 < active tab 1560). All drawers are 360px, clamped to `calc(100vw − 36px)` on narrow viewports, anchored inside the rail (`top:72`, `bottom:16`).
- **Row hover:** primary action button + dismiss × reveal inline (timestamp yields). Persistent rows expose no dismiss.
- **Row expanded:** click expands body + action + DISMISS (non-persistent only). Snooze/mute controls were cut until snooze ships.
- **Surface:** `var(--glass-dense)`, `var(--glass-border)`, zero box-shadows, square right edge, left-corner radius 10 (drawers) / 6 (tabs).

**Behavior rules:**
- Action clicks auto-dismiss **non-persistent** rows only — persistent notifications stay until resolved programmatically (`is_read = true` by the server path).
- Footer CLEAR ALL = `useDismissAllNotifications` (disabled when nothing is dismissible). The old VIEW ALL filter-reset is gone.

**Keyboard:** `N` notifications · `Q` quick actions · `` ` `` bug report (all suppressed in inputs) · `Escape` closes · Arrow `Up`/`Down` move row focus.

**Mutual exclusion:** `useEdgeTabStore` keeps one drawer open at a time; `EdgeTabOutsideDismiss` closes the active drawer on canvas clicks while ignoring portaled menus/dialogs.

**Data Model:** unchanged — existing `AppNotification` + `notifications` table (columns `persistent`, `action_url`, `action_label`).

**Motion:** `drawerVariants` / `rowVariants` / `chipVariants` in `src/lib/utils/motion.ts`, all with reduced-motion fallbacks.

**Integration:** any feature that produces a user-facing event inserts a row into the `notifications` table. The drawer picks it up automatically via TanStack Query's `useNotifications()` hook.

**Recipient lookup — permission, never role.** Server-side dispatch (iOS in-app + push, Web in-app) MUST resolve recipients via `public.users_with_permission(p_company_id, p_permission, p_required_scope)`, not by filtering `users.role`. The RPC honors role grants, per-user overrides (`user_permission_overrides`), and the company-admin escape hatches (`users.is_company_admin`, `companies.account_holder_id`, `companies.admin_ids`). Hardcoding role strings ignores custom roles, skips overrides, and silently excludes users whom the operator company has explicitly granted approval rights. Permission keys live in `role_permissions.permission` — examples: `expenses.approve`, `inventory.manage`, `time_off.approve`, `invoices.record_payment`. iOS callers wrap the RPC via `RecipientLookupService.usersWithPermission(companyId:permission:requiredScope:)`.

#### Server-authoritative creation boundary (production 2026-07-17)

Notification creation is a trusted-server operation. Browser sessions may read and resolve notifications available through their own RLS scope, but may not insert, delete, or call the generic recipient/copy/navigation RPC. Server paths create rows with `createTrustedNotifications`; its service-only `create_notification_if_new_with_status` RPC reports whether the durable insert won so push delivery occurs only for the first accepted event, not a retry.

The database accepts only internal `action_url` values: a trimmed, single-leading-slash app path with no protocol-relative prefix, backslash, or control character. Legacy unsafe destinations are cleared before the constraint is enabled. Feature routes must derive actor, company, recipients, copy, persistence, and navigation on the server; request bodies cannot override them.

Two narrow self-service paths preserve legitimate browser-triggered behavior without restoring generic creation authority:

- `POST /api/notifications/setup-prompts` accepts no body, resolves the active OPS actor from the bearer token, reads current permissions and setup state, and creates or resolves only deterministic prompts for that actor.
- `sync_email_signature_notification_as_system(actor_user_id, connection_id)` is service-role only. It accepts the canonical OPS actor UUID, ignores a company mailbox's legacy connector `user_id`, requires an active sync-enabled connection plus effective inbox-send authority, and points the user to the Profile signature editor.

The production hardening migration is `ops-web/supabase/migrations/20260715180500_notification_creation_hardening.sql`. It ran before `20260715180900_internal_spec_permission_guard.sql` and `20260715181000_lead_assignment_operator_activation.sql`, so any hardening failure would have left Operator grants fail-closed. All three migrations were applied to production on 2026-07-17 in that order.

### §14.3.1 Standardized Notification Spec (2026-05-10)

Every notification inserted into the `notifications` table MUST satisfy this contract so the in-app rail (web + iOS) routes it correctly and the user has a clear next action. Added in response to bb63c37e — earlier code shipped `type: "mention"` for an "Email sync complete" event with a body of bare counts and no useful deep link.

**Required fields:**

| Field | Rule |
|-------|------|
| `type` | Specific event type (e.g. `expense_submitted`, `email_sync_complete`, `projects_needing_tasks`) — NOT a catch-all like `"mention"` or `"update"`. Must exist in `NOTIF_TYPE_META` (web) and the `notificationIcon(for:)` switch (iOS). |
| `title` | ≤ 32 chars, sentence case for content / UPPERCASE for authority (matches OPS voice). Names what happened, not the system that did it. |
| `body` | ≤ 140 chars. Includes at least one **concrete reference** the user can act on: a sender name, a count + unit, an amount, a deadline, an entity name. Never bare counts ("3 new"). |
| `deep_link_type` | Required when the action is anything other than "mark read". Free-form short identifier — both clients route on it. Current values: `subscription` / `trial_expiry` / `paymentReview` / `taskReview` / `unscheduledReview` / `photoStorage` / `catalogOrders` / `expense` / `invoice` / `lead` / `leads` / `opportunity` / `opportunities` / `inbox` / `projectsNeedingTasks` / `billableThisWeek` / `email_sync_complete` / `cashflow_forecast`. |
| `action_url` | Web URL or `ops://` deep link. Web reads it directly, iOS uses it as supplementary info (e.g. `?tab=...` query strings). |
| `action_label` | UPPERCASE imperative verb phrase (e.g. `REVIEW`, `VIEW PLAN`, `PLAN THE WORK`). The action button label. |
| `persistent` | `true` only for long-running operations the user is waiting on (scans, imports, threshold rail entries that auto-clear). `false` (dismissible) for everything else. |
| `dedupe_key` | Required for persistent notifications that represent a specific unresolved condition. The key must identify the condition, not the title, so several open rows can share copy without blocking each other. |
| `resolved_at` / `resolved_by` / `resolution_reason` | Required for self-resolving persistent notifications. Resolution must be written by the server path that recomputes the condition as closed. |
| Entity FKs | Set `project_id` / `expense_id` / `batch_id` / `note_id` whenever the underlying object exists. Routing fallbacks use these (e.g. an `expense_submitted` row with no `deep_link_type` still resolves to the expense list). |

**iOS routing order (NotificationListView.handleNotificationTap):**
1. `deep_link_type` switch — first-class routing.
2. Falls through to a `notification.type` switch — covers legacy rows inserted before `deep_link_type` existed.
3. Final fallback: `project_id` → `viewProjectDetailsById`.

**iOS push routing (AppDelegate):** mirrors the in-app switch by posting `NotificationCenter` events (`OpenExpenses`, `OpenInvoices`, `OpenJobBoard`, etc.). Every posted event MUST have a corresponding listener mounted on `MainTabView` — a post with no listener is a dead deep link (the original 8ed0d2ed bug).

Lead and opportunity notifications route through `OpenLeadDetails`. iOS resolves IDs from `ops://leads/<id>`, `ops://opportunities/<id>`, or query parameters named `leadId`, `opportunityId`, or `id`, switches to the Pipeline tab, loads the current opportunities, and opens the matching detail sheet. If the ID is missing or inaccessible, iOS falls back to the Job Board or access-denied rail instead of dropping the tap.

**When adding a new notification type:**
1. Pick an explicit `type` string and add it to:
   - `OPS-Web/src/lib/api/services/notification-service.ts` (`NotificationType` union)
   - `OPS-Web/src/lib/notifications/notification-meta.ts` (`NOTIF_TYPE_META` registry)
   - `OPS/OPS/Views/Notifications/NotificationListView.swift` (`notificationIcon(for:)` switch)
2. If it has a deep link, pick a `deep_link_type` and add a routing case to:
   - `OPS/OPS/Views/Notifications/NotificationListView.swift` (`handleNotificationTap`)
   - `OPS/OPS/AppDelegate.swift` (push handler) — only if you also fire pushes for it
3. Document the type + deep_link in the table above.

**`catalog_mapping_needed` (Phase 6 estimate-to-job catalog flow):**

| Field | Value |
|-------|-------|
| `type` | `catalog_mapping_needed` |
| `deep_link_type` | `catalogSetup` |
| `action_label` | `FIX MAPPING` |
| `action_url` | `ops://catalog/setup?missingMapping=<encoded-key>` |
| `persistent` | `true` |
| `dedupe_key` | Deterministic mapping-gap key emitted by the estimate acceptance resolver. |
| Recipients | `public.users_with_permission(company_id, 'catalog.manage', 'all')` |

This notification is non-blocking. Estimate acceptance can continue with warning payloads, but every unresolved mapping gap gets a keyed persistent row. When Catalog Setup or product mapping save closes the gap, the server recomputes mapping existence and resolves only matching `dedupe_key` rows by setting `resolved_at`, `resolved_by`, `resolution_reason`, and `is_read = true`.

### §14.3.2 Forecast Dip Notification (2026-05-11)

Persistent notification fired when the Cashflow Forecast (a preview mounted below the BOOKS hero carousel — see `09_FINANCIAL_SYSTEM.md § Cashflow Forecast`) projects any week below zero.

**Notification shape:**

| Field | Value |
|-------|-------|
| `type` | `forecast_dip` (persistent) — and `forecast_cleared` (non-persistent, one-shot) |
| `deep_link_type` | `cashflow_forecast` |
| `title` | `// CASH DIP PROJECTED` |
| `body` | `Balance drops to $X the week of MMM D.` (concrete amount + week reference) |
| `action_url` | iOS deep link → `CashflowForecastScreen`. Web ships a placeholder route at `/money/cashflow` initially. |
| `action_label` | `REVIEW FORECAST` |
| `persistent` | `true` for `forecast_dip`; `false` for the one-shot `forecast_cleared` follow-up |

**Trigger:**

Inserted by `ForecastNotificationDispatcher` (iOS) on every forecast recompute when:
1. The newly-computed `ForecastResult.state == .danger` (any week's running balance < 0), AND
2. Anti-spam rules permit re-fire (see below).

Forecast recomputes are triggered on app foreground (after >5 min in background) and on any data mutation that changes inflow/outflow timing: invoice sent/paid, estimate approved/converted, payment_milestone added/edited, recurring_expense added/edited/deleted, starting balance updated.

**Anti-spam rules** — backed by the per-company `forecast_alerts` ledger (`company_id` PK, columns: `last_dip_notified_at`, `last_dip_min_balance`, `last_dip_min_week_start`, `last_cleared_at`, `dismissed_until_balance`):

1. **First dip** — fire if no prior `last_dip_notified_at`, OR if `last_cleared_at > last_dip_notified_at` (dip cleared and a new one started).
2. **Worsening dip** — re-fire only if `now() - last_dip_notified_at > 24h` AND `new_min_balance < last_dip_min_balance × 0.9` (10% worse or more).
3. **Dip cleared** — when state transitions from `.danger` to `.healthy` or `.lowWater`, fire a one-shot **non-persistent** `forecast_cleared` notification and set `last_cleared_at = now()`. The existing persistent `forecast_dip` row stays in the rail until the user dismisses it (it will not refire for the same dip event).
4. **"Don't show again"** — when the user dismisses the persistent row with "don't show again", set `dismissed_until_balance = current_min`. Suppresses re-fire while subsequent `min_balance ≥ dismissed_until_balance × 0.9`. A genuinely new / materially worse dip clears the dismissal.

**Recipients:**

Looked up via `public.users_with_permission(p_company_id, 'finances.view')` — never filter by `users.role`. One row inserted per recipient user (notifications.user_id is a single FK); the dedup ledger is keyed by `company_id` so all users in a company see the same dip event at the same trigger.

**Where the recompute runs:**

iOS-only for v1. The engine + dispatcher live on-device; the dispatcher writes to the `notifications` table directly via the Supabase client. Edge-Function-based recompute is a v2 consideration when OPS-Web parity lands.

---

### §14.3.3 Billable This Week Notification (2026-05-25)

Monday-morning summary for the Home `BILLABLE THIS WEEK` rollup (see `09_FINANCIAL_SYSTEM.md § Home Billable This Week Rollup`). It is dismissible because the card itself remains live on Home all week.

**Notification shape:**

| Field | Value |
|-------|-------|
| `type` | `billable_this_week` |
| `deep_link_type` | `billableThisWeek` |
| `title` | `BILLABLE THIS WEEK` |
| `body` | `N jobs / $X billable` when a known amount exists; otherwise `N jobs ready for billing`. |
| `action_url` | `ops://home/billable-this-week?weekStart=YYYY-MM-DD` |
| `action_label` | `OPEN HOME` |
| `persistent` | `false` |

**iOS routing:** `NotificationListView` routes `billableThisWeek` to Home via `NavigateToMap`; `AppDelegate` mirrors that route for push/local notification taps. `NotificationManager` also schedules the local iOS notification under `BILLABLE_THIS_WEEK_NOTIFICATION`.

**Trigger:** `HomeBillableThisWeekNotificationDispatcher` fires at most once per user/company/week, only on Monday, only when the rollup has items and the current user has `finances.view`. It first confirms or creates the in-app notification row for the current user, then schedules the local iOS notification and commits the weekly UserDefaults suppression key. Failed remote lookups or creates must leave the week retryable so the notification rail cannot permanently miss the row.

---

### §14.3.3b Lead-conversion notification (`lead_converted`, durable event delivery, production 2026-07-17)

Every successful conversion path—human, approval queue, accepted customer email, or likely-won email—commits one immutable `public.opportunity_conversion_events` row in the same transaction as the lead/project relationship. Migration `20260715181700_opportunity_conversion_notification_delivery.sql` uses that event as the sole notification proof. Browser callbacks and editable disposition rows are not dispatch authority.

The event-time lead assignee receives one addressed delivery. A minute worker claims it with a fenced lease, rechecks the immutable event, current lead relationship, active recipient, and current opportunity visibility, then creates one permanent-dedupe rail row. Project navigation is included only when that recipient can currently view the project; otherwise the notification routes to the still-authorized lead. Push is optional and preference-gated, while the in-app rail remains authoritative. A permission or relationship change before completion resolves the row as suppressed instead of leaking a hidden project or retrying a stale destination.

The durable delivery key is `(conversion_event_id, recipient_user_id)`, and the notification key is tied to that delivery. Provider or worker failure can retry persistence without repeating conversion or creating a second rail row. Client-side `Project created` self-notifications and the generic `lead_converted` dispatch policy are retired so linking an existing project, retrying conversion, and browser timing cannot double-notify.

The migration was applied to production after the assignment/email/notification chain on 2026-07-17. It adds no customer-email send and performs no provider write.

---

### §14.3.4 Project collaboration notifications (iOS, 2026-06-04)

Three field-crew collaboration events were silently notifying nobody — only @mentions reached teammates. All three are now created client-side on iOS via `NotificationRepository.createNotification(_:)` (in-app rail) + `OneSignalService` (push), matching the existing mention pattern. Recipients are the project's assigned crew (`Project.getTeamMemberIds()`); the actor and anyone already @mentioned are excluded so a single action never double-notifies.

| Event | `type` | Recipients | Source |
|-------|--------|-----------|--------|
| New project comment/note (activity tab) | `project_note` | assigned crew − author − @mentioned | `ProjectNotesViewModel.sendNoteAddedNotifications` |
| Photos added to project (gallery) | `photo_uploaded` | assigned crew − uploader | `ImageSyncManager.notifyCrewOfAddedPhotos` (fires from `saveImages`; the note-attachment path passes `notifyCrew: false`) |
| Comment on a photo | `photo_comment` | photo's `uploaded_by` (− commenter − @mentioned) | `PhotoCommentsViewModel.sendPhotoOwnerNotification` (resolves the uploader from `project_photos.uploaded_by`) |

All three set `deep_link_type = projectNotes` and `project_id`, so both clients route them to the project. iOS rail icons added to `NotificationListView.notificationIcon(for:)` — `photo_uploaded` → `photo.on.rectangle`, `photo_comment` → `text.bubble`.

**Removed gate (bug fix):** `sendNoteAddedNotifications` was gated behind a `notifyProjectNoteAdded` UserDefaults flag that was never written and had no settings UI — it suppressed every team note/comment notification. The gate is removed; assigned crew are always notified of new comments (on by default, no toggle).

**Push deep-link cold-start fix:** `AppDelegate`'s push-tap handler previously posted `OpenProjectDetails` directly to `NotificationCenter` after a fixed 0.5 s delay. On a cold launch (app still booting through splash/sync/PIN) no observer is mounted yet, so the post was dropped and the app landed on Home — the "notification opens the main screen, not the project" bug. Project taps now route through `DeepLinkCoordinator.receive(entity: "projects", …)`, which stashes the intent and is re-drained by `MainTabView.onAppear` / PIN-unlock. Only projects route this way (`openProjectWithSync`/`denyProject` clear the stash); client/invoice/estimate/task taps remain direct posts because their handlers do not clear it.

**Web parity (NOT yet done):** `ops-web` does not generate these three notifications (it only notifies on project-note @mentions), and `photo_uploaded` / `photo_comment` are not yet in the web `NOTIF_TYPE_META` registry. A comment/photo posted from the desktop app will not notify iOS crew, and web-rail rows for these two types fall back to default rendering, until web parity lands.

---

**Task mutation notifications (`task_assigned`, `task_completed`, `schedule_change`; production 2026-07-17):**

Migration `20260715181600_task_mutation_automation_outbox.sql` moves ordinary task notifications off browser hooks and recurrence callbacks. Each qualifying task write atomically creates an immutable `task_mutation_events` proof plus a mutable leased outbox row. The minute worker derives recipients, copy, navigation, preferences, and permanent dedupe from that proof; neither a request body nor a stale client chooses them.

- `task_assigned` goes only to newly added, still-assigned users with current task visibility. Rapid add/remove/add sequences keep only the latest relevant assignment proof.
- `task_completed` goes to current assigned users with task visibility only while completion remains current.
- `schedule_change` uses the union of the before/after assignee snapshots for real schedule changes. A removed user still receives a generic no-link rail notice, while current authorized users receive the task/project destination. Removal-only changes never claim that the task was rescheduled.

The immutable monotonic event sequence closes same-timestamp and UUID-order races. Later per-recipient events suppress stale ABA deliveries, and the `task-mutation:<event-id>` unique notification key survives read/resolution state and worker retries. The in-app rail is always created for eligible recipients; push alone respects per-event and global push preferences. The recurrence generator relies on the same database trigger and no longer emits a second direct notification.

This migration was applied to production after Operator activation on 2026-07-17.

---

#### Web Quick Actions Edge Tab (OPS Web — 2026-04-25)

The Quick Actions tab replaces the prior bottom-right circular FAB (`floating-action-button.tsx`, removed 2026-04-25). It mounts on the right edge between Notifications and Bug Report and pairs with a 308px panel-anchored drawer whose height is content-driven and floored at the resting tab height. Spec source: `ops-design-system-v2/project/fab/variants.jsx` V1 — selected per the design brief at `ops-design-system-v2/project/fab/FAB Redesign.html` for "lowest intrusion / ops-iest shape." Long-press edit mode is dropped in favor of a persistent `CUSTOMIZE →` footer routing to `/settings?tab=quick-actions`.

**Components:**
- `src/components/layouts/quick-actions-tab.tsx` — wraps `<EdgeTab>`. `restHeight=132`, `hoverHeight=188`, `stackOffset=+34`, accent always `--ops-accent`, plus glyph rotates 0°→45° on open. `Q` keyboard shortcut.
- `src/components/layouts/quick-actions-drawer.tsx` — 308px panel-anchored drawer. Header `// QUICK ACTIONS` + `Q` KeyHint, action list (icon + label + 3-letter hint), footer `CUSTOMIZE →`.
- `src/lib/hooks/use-quick-actions.ts` — returns the user's filtered actions (permission + feature-flag + user-prefs filtering, lifted from the deleted FAB component).
- `src/lib/constants/fab-actions.ts` — extended with `hintCode` field per action: `EXP / LED / EST / INV / CLI / PRJ / TSK / TTY / ITM`.

**Drawer surface:**
- Background: `var(--glass-dense)`
- Border: `1px solid var(--glass-border)`, `border-right: none`
- Backdrop: `blur(28px) saturate(1.3)`
- Top-edge highlight gradient applied (matches all glass surfaces)
- Position: anchored to tab vertical center via shared `edge-rail-layout.ts` math and clamped inside the rail

**States:**
- **Closed:** 28×132 tab. Vertical "QUICK ACTIONS" wordmark + `+` glyph. Steel-blue (`--ops-accent`) accent stripe always.
- **Open:** drawer slides in from right (260ms); tab grows to drawer height, glyph rotates 45° → `×`, wordmark reads "CLOSE". Drawer shows action list + customize footer.
- **Hover (closed):** tab reveals to `hoverHeight=188` when no other edge drawer is active, and shows tooltip with `Q` KeyHint.

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

### §14.3.4 Expenses Ready for Review — server-side auto-send (2026-06-01)

Emitted by the daily envelope sweep (`public.expense_envelope_sweep()`, pg_cron `expense_envelope_sweep_daily` at 15:15 UTC) when an `open` expense envelope passes `period_end + expense_settings.auto_submit_grace_days` and is auto-sent (flipped `open → pending_review`). **One notification per envelope per approver** — not per expense. This is the server-authoritative replacement for the iOS client's on-submit notification: even a stale app version's expenses now get an envelope and a single review notification when the sweep sends. See `09_FINANCIAL_SYSTEM.md § Server-Authoritative Expense Envelopes (2026-06-01)`.

| Field | Value |
|-------|-------|
| `type` | `expense_submitted` |
| `title` | `Expenses ready for review` |
| `body` | `<batch_number> — <Mon YYYY> (<total>)` — e.g. `EXP-BATCH-0003 — May 2026 ($59.32)` |
| `deep_link_type` | `expense` |
| `action_url` | `/accounting?tab=expenses&batch=<batch_id>` — written by the DB sweep. Since the web BOOKS absorption (P3.1, 2026-06-11) this 308s param-preserving to `/books?segment=expenses&batch=<batch_id>`, where the review hub now lives; retargeting the writer would need a prod migration of `expense_envelope_sweep`, and the middleware redirect is the designed permanent guard. (History: the earlier `/expenses?batch=` 404'd, corrected 2026-06-02.) |
| `action_label` | `REVIEW` |
| `batch_id` | the envelope's id |
| `dedupe_key` | `expense_batch_review:<batch_id>` — per-envelope, so multiple envelopes auto-sent to one approver in a single sweep don't collide on `notifications_unread_title_dedup_without_key` (the title-dedup index for keyless rows); a non-null key routes dedup to `notifications_open_dedupe_key (user_id, company_id, type, dedupe_key)` instead. Insert uses `ON CONFLICT DO NOTHING` so the daily cron can never abort on a duplicate. |
| Recipients | `public.users_with_permission(company_id, 'expenses.approve')` — never by `users.role` |
| `persistent` | `false` (dismissible) |

Migration: `migrations/20260601213757_expense_envelope_sweep_deep_link_expense.sql` (supersedes the initial `…211633` cut that used the non-routable `invoice_detail`).

### §14.3.4b Expenses Paid Out (`expense_paid`, 2026-07-10)

Dispatched **client-side by OPS-Web** (`notification-dispatch.ts → dispatchExpensePaid`, fired from `useMarkBatchPaid` after the `mark_expense_batch_paid` RPC succeeds) to tell the submitter their approved batch was settled up. Registered in the web rail meta (`NOTIF_TYPE_META.expense_paid` — `PAID` / `receipt-text` / ambient) and safe on shipped iOS via the type-switch `default:` fallbacks (renders with the generic icon + `OPEN`). Rides the `expense_approved` channel preference in the dispatch route — a submitter who wants approval pings wants payout pings; no separate settings toggle.

| Field | Value |
|-------|-------|
| `type` | `expense_paid` |
| `title` | `Expenses Paid Out` |
| `body` | `Your expense batch <batch_number> has been paid out` |
| `action_url` | `/expenses` (middleware 308s to `/books?segment=expenses` on web; iOS routes via pushData `screen: expenses`) |
| `action_label` | `View` |
| Recipient | the batch's `submitted_by` only |
| `persistent` | `false` (dismissible) |

Undoing a payout (`unmark_expense_batch_paid`) intentionally sends nothing — a correction shouldn't ping the crew twice.

### §14.3.5 Lead / Opportunity lifecycle notification contract (2026-06-09)

Hardens the **write contract** for every lead/opportunity lifecycle notification (types `leads_waiting` and `role_needed`) so a lead is recoverable from the row alone — no `email_threads` join at tap time. Prompted by an iOS lead-notification deep-link bug (`bug_reports` `2c51ca25-a718-4cfe-977f-4ecd31d74ccc`, fixed iOS-side in ops-ios `1ff9c2dc`): production rows shipped `deep_link_type = NULL` with an `action_url` pointing at an inbox *thread* id, so the only reliable opportunity id lived in the trailing UUID of `dedupe_key`. iOS is now self-sufficient (it resolves the opportunity from `action_url` query params, the `dedupe_key` UUID, or an `email_threads.opportunity_id` lookup); this change removes the dependency on that last, brittle fallback by making the web builders stamp the id and a routable `deep_link_type` directly. **iOS was not changed.**

**Four OPS-Web builders write these rows. All now stamp a non-null `deep_link_type`; the three lifecycle/classification builders also carry the entity id in `action_url`:**

| Builder | Notification | `deep_link_type` | `action_url` |
|---------|-------------|------------------|--------------|
| `opportunity-lifecycle-action-service.ts` → `createOperatorFollowUpMissNotification` | `Lead reply waiting // <id>` (persistent) | `lead` | `/inbox/<thread>?opportunityId=<id>` when a thread resolves, else `/pipeline?opportunityId=<id>` |
| `lead-lifecycle-cron-service.ts` → `emitDestructiveReviewNotification` | `REVIEW // <disposition> — <lead>` (persistent) | `lead` | same inbox-or-pipeline shape, both carrying `?opportunityId=<id>` |
| `email-thread-service.ts` → `fireThreadNotifications` | `New lead: <sender>` / `Platform bid: <x>` / `Urgent reply needed` (the last is type `role_needed`) | `inbox` | `/inbox?thread=<thread_id>` (+ `&opportunityId=<id>` when the thread is already linked) |
| `settings/integrations-tab.tsx` (web onboarding CTA) | `You have leads waiting` (persistent) | `inbox` | `/settings?tab=integrations` — fires pre-import, before any opportunity entity exists, so it carries no `opportunityId`; the `inbox` deep link keeps it out of the legacy NULL fallback |

**Rules baked in:**
- The two **lifecycle** builders own a definite opportunity, so they route `lead` and always append `?opportunityId=<id>` — even when the primary link is the inbox thread surface (web keeps the thread; iOS routes to the lead via `deep_link_type`).
- The **thread-classification** builder fires the moment a conversation lands; an opportunity may not exist yet, so it routes `inbox` (the always-present thread id is the resolution key) and attaches `opportunityId` only when the thread is already linked.
- `dedupe_key` is unchanged (`lead_lifecycle:operator_follow_up_miss:<id>`, `lead_lifecycle:destructive_candidate:<id>:<action>`); the id it carries now also lives in `action_url`.

**RPC change.** The thread-classification builder writes through `create_notification_if_new` (the `ON CONFLICT DO NOTHING` dedup RPC). Migration `20260609181500_create_notification_if_new_deep_link_type.sql` drops the 9-arg signature and recreates it with a trailing `p_deep_link_type text default null` that persists the column, re-granting `execute` to `anon, authenticated, service_role`. The new arg defaults to null, so the currently-deployed 9-arg callers (stripe webhook, join-company, data-setup, inventory-deduction) keep resolving to it unchanged. **No backfill** — the ~257 pre-existing rows keep `deep_link_type = NULL` and are already covered by the iOS fallbacks; only new rows get the hardened contract.

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
- **Webhook hardening:** `email_events` now has `uq_email_events_idempotency` so SendGrid retries don't duplicate rows. Production migration `20260715181800_sendgrid_email_events_idempotency.sql`, applied on 2026-07-17, replaced the non-inferable partial index with a full NULL-distinct unique index, allowing PostgREST's `ON CONFLICT (sg_message_id,event,timestamp)` upsert to resolve the correct arbiter. The webhook uses `ignoreDuplicates: true` and is rate-limited to 600 req/min/IP via Vercel KV.
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

### Lockout-driven request flow (added 2026-05-07)

When a member triggers a "Request reactivation" or "Request access" CTA on the lockout surface, `components/lockout/request-button.tsx` inserts one row per admin into `notifications` with `type='role_needed'`, `persistent=true`, and `action_url='/settings?tab=subscription'` (reactivation) or `'/team'` (seat). The 24h cooldown lives in `localStorage` under `ops-lockout-request-${userId}` (preserved across the 2026-05-07 redesign — extracted to `components/lockout/hooks/use-request-cooldown.ts`). Schema unchanged.

Design spec: `OPS-Web/docs/superpowers/specs/2026-05-07-lockout-redesign-design.md`.

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
- Shows event title, date range, semantic badge, and leading icon
- Custom/personal events render as `CUSTOM` with a dashed custom-event treatment so they do not read as work cards
- Time-off cards render with clock icons and semantic status treatment (`PENDING`, `APPROVED`, `DENIED`, `TIME OFF`)
- Supports tap-to-edit, context-menu edit/delete, and span resize where wired by `DayCanvasView`

#### UserEventSheet
**File:** `Views/Calendar Tab/Components/UserEventSheet.swift`

Unified bottom sheet for personal/custom events and time off:
- Create mode toggles between `EVENT` and `TIME OFF`; edit mode locks to the existing row type
- Personal/custom events require schedule-edit permission, require a title, support all-day/time-of-day, team invites, recurrence expansion, notes, and `status: .none`
- Time-off create mode is self-submit by default; it does not require `calendar.edit`
- Users with `time_off.approve` see a tappable `FOR` row and can book one or more active company members off directly
- Approver-booked time off creates `CalendarUserEvent` rows with `type: .timeOff`, `status: .approved`, `reviewedBy`, and `reviewedAt`
- Non-approver time-off submissions create `status: .pending` and notify `time_off.approve` recipients
- Saves insert locally first for instant calendar feedback, then sync to `calendar_user_events` and replace local ids with server ids
- First successful save still triggers the iPhone Calendar Mirror permission prompt when needed

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
- Uses the schedule-mode floating action menu to present `UserEventSheet` as either `EVENT` or `TIME OFF`
- Passes `isScheduleTab: true` to `FloatingActionMenu`

### CalendarViewModel Changes

| Change | Detail |
|--------|--------|
| Added `isMonthExpanded: Bool` | Drives week strip ↔ month grid toggle |
| Added `toggleMonthExpanded()` | Called by AppHeader month icon tap; uses spring animation |
| Added `userEvents(for:) -> [CalendarUserEvent]` | Returns visible personal/custom events and time off for a given date |
| Added `loadUserEvents()` | Loads visible local `CalendarUserEvent` rows: own rows, invited rows, all rows for `calendar.view(all)`, and company time-off for `time_off.approve` |
| Removed `shouldShowDaySheet` | No longer needed (DayEventsSheet pattern eliminated) |
| Removed `resetDaySheetState()` | Removed with the above |

### Data Layer

- **SwiftData model:** `CalendarUserEvent` — see `03_DATA_ARCHITECTURE.md` section 25
- **Supabase table:** `calendar_user_events`
- **Repository:** `CalendarUserEventRepository.swift`
- **DTOs:** `CalendarUserEventDTOs.swift`
- **RLS note:** Uses explicit UUID/text casts due to `users.id/company_id` UUID columns and `calendar_user_events.user_id/company_id` text columns. Self-owned rows use the owner policy; migration `20260707194500_calendar_user_events_time_off_approver_policies.sql` adds `time_off.approve` insert/update policies for company time-off rows.

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
- Z-scale CSS custom properties added to globals.css and `ops-design-system/project/colors_and_type.css`. See § 15 of 05_DESIGN_SYSTEM.md.

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

### iOS offline resolution (cache-first)

The iOS client resolves flags **cache-first**, and a failed *fresh* fetch is treated as "unknown", never "disabled":

- On launch, `PermissionStore.loadCachedPermissions()` hydrates the last cached flag state from the Keychain, so entitlements are available instantly and offline.
- `PermissionStore.fetchPermissions()` fetches RBAC and flags in parallel. `FeatureFlagService.fetchFlags` **throws** on a network failure (it is two extra round-trips, so it drops out first under weak reception). On a throw, `fetchPermissions` keeps the last-known-good flag state via `FeatureFlagService.resolve(fresh:lastKnown:)` rather than failing closed.
- **Fail-closed** (`failClosedResult()`, which disables every known flag) applies **only** when there is genuinely no prior state — a fresh install with an empty cache.

Rationale (bug `d5c899e6`): overwriting cached entitlements with a fail-closed result on any reception wobble hid DECK / pipeline / estimates / accounting for entitled field users mid-job ("the tab disappears as if it's live-syncing my permissions"). Absence of a fresh permission fetch is not absence of permission. **Do not "restore" fail-closed-on-fetch-failure** — it is a regression.

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

The OPS web inbox at `/inbox` is the operator panel for **Phase C**, OPS's AI executive-assistant agent. Every email — not just pipeline leads — flows through the inbox, gets AI-classified into one of twelve primary categories, and is surfaced to the user with the right triage affordances (archive, snooze, recategorize, Phase C-drafted reply, etc.). Rebuilt 2026-04-20 (plan: `docs/superpowers/plans/...`, commits `f05627ff` → `2430fbdc`); rail model collapsed to ball-in-court 2026-05-12 (audit `docs/superpowers/research/2026-05-12-inbox-category-audit.md`, commits `951a0659` → `ce91e96c`).

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

Twelve values, enforced by the `email_threads.primary_category` CHECK constraint (post `20260428061836_collapse_lead_client_to_customer`). The legacy `LEAD` + `CLIENT` values were collapsed into `CUSTOMER` in that migration and were dropped from the TypeScript union 2026-05-12 (commit `ce91e96c`).

| Category | When it applies |
|----------|-----------------|
| `CUSTOMER` | Anyone the company sells work to — covers the full arc from first inquiry through warranty / repeat / referral. The lead-vs-client distinction is handled by the linked opportunity stage, not this category. |
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

`AWAITING_REPLY` post-v3 (2026-05-12) is mechanically derived from the classifier's explicit `ball_in_court` resolution: present when `ball_in_court='operator'`, absent otherwise. The label is the operational signal the rail predicate trusts; `ball_in_court` itself lives only on the wire (`ClassifyResult.ballInCourt`), not in a column.

### Rail model (2026-05-19 audience IA)

The left rail of `/inbox` is a three-option audience filter, not a reply-state control. The 2026-05-19 IA pass replaced the ball-in-court primary rails (`YOUR MOVE` / `WAITING`) with `CLIENTS` / `EVERYTHING ELSE` / `ALL` because reply debt is more useful as row/detail state than as disconnected top-level buckets. Single source of truth: `src/lib/inbox/rail-predicates.ts`.

| Rail | Predicate | Keyboard |
|------|-----------|----------|
| **CLIENTS** | `archived_at IS NULL AND (client_id IS NOT NULL OR opportunity_id IS NOT NULL OR primary_category IN ('CUSTOMER','PLATFORM_BID'))` | `1` |
| **EVERYTHING ELSE** | `archived_at IS NULL AND client_id IS NULL AND opportunity_id IS NULL AND (primary_category IS NULL OR primary_category NOT IN ('CUSTOMER','PLATFORM_BID'))` | `2` |
| **ALL** | `archived_at IS NULL` | `3` |

Default landing is the operator's starred primary rail, persisted in the web inbox layout preference store (`ops-inbox-layout.defaultRailFilter`). If no star exists, the default is `CLIENTS`. `ARCHIVED` and `SNOOZED` remain utility filters opened from secondary surfaces, not primary rail buttons.

Reply debt remains row/detail state. `isYourMove(...)` still computes the operator-obligation signal from unresolved commitments, `AWAITING_REPLY`, unread inbound, and Phase C blocking questions; it powers the row state tag and floating `// YOUR TURN` badge but does not determine `CLIENTS` vs `EVERYTHING ELSE` membership. The left list renders the active rail as a flat feed; there are no `NEEDS REPLY`, `DRAFTS READY`, `AWAITING THEM`, or `LATER` section headers. Unread remains visual-only read state.

#### Demoted rails

- **DRAFTS** → header counter chip `// {n} DRAFTS ▾` next to the rail dropdown, plus the existing per-row `// DRAFT` pill on thread rows. Chip renders only when count > 0; popover lists every unsent draft (provider + Phase C) with discard / open affordances. Source endpoint unchanged (`/api/inbox/drafts`).
- **SCHEDULED** → snooze stays as a per-thread action (via `SnoozePicker`). Header counter chip `// {n} SNOOZED ▾` renders only when at least one thread is currently snoozed; popover lists each with unsnooze + open. Internal `RailFilter` value `SNOOZED` (not in the rail nav buttons) backs the popover.

Below the rails, a horizontal strip of **category filter chips** (ALL + 12 categories) narrows the active rail by `primary_category`. Category strip is unchanged by the collapse — Phase 4 visual rework owns any redesign there.

#### URL/legacy parsing

`parseRailFilter` (in `rail-predicates.ts`) accepts the canonical audience values and gracefully maps legacy strings forward so existing bookmarks/links don't 404: `everything → ALL`, `needs_reply → ALL`, `commitments → ALL`, `drafts → ALL`, `scheduled → ALL`, `done → ARCHIVED`, `YOUR_MOVE → ALL`, `WAITING → ALL`. Unknown/missing values fall through to the configured fallback (default `CLIENTS`, `ALL` for the route handler).

### Thread classifier

- Service: `src/lib/api/services/thread-classifier-service.ts`
- Model: `gpt-5.4-mini` via `OPENAI_API_KEY_SYNC`
- Invocation: fire-and-forget from `EmailThreadService.upsertFromEmail` (sync step 7.5)
- Output: `primary_category` (one of 12), `confidence`, secondary `labels[]`, `ball_in_court` (`'operator' | 'counterparty' | 'none'`), `ai_summary`, `reasoning`
- `CLASSIFIER_VERSION = 'v3'` (2026-05-12) — adds explicit ball-in-court resolution. The LLM decides whose turn it is BEFORE the AWAITING_REPLY label, then the service post-processes (`reconcileLabelsToBallInCourt`) to enforce label coherence — operator forces AWAITING_REPLY in, counterparty/none forces it out. Forward-fix only; the 3,257 historical rows are NOT backfilled.
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
| `auto_follow_up` | CUSTOMER — auto-nudge after configurable quiet days |

**Global AUTO_SEND gate:** The router caps any category-level `auto_send` / `auto_follow_up` to `auto_draft` behavior until the global Phase C autonomy level in `AutonomyMilestoneService` reaches AUTO_SEND (level 4). This prevents any email from being sent before the overall writing profile is proven.

#### Human-authority learning, subjects, and signatures (production 2026-07-17)

Phase C learns only from an outcome whose human authority the database can verify. Authenticated in-app manual sends are `operator_authored` and may update the full writing profile; a matched OPS/provider draft that the operator sends is `operator_approved` and may teach only the operator's durable edits, never the unchanged AI-authored body. Autonomous sends and generic provider Sent-folder mail do bookkeeping but cannot train profiles or memories. The browser feedback endpoint may discard a draft but may not claim it was sent. Repeated edits are stored as de-identified evidence and need three consistent human examples before promotion; receipts make profile/memory application exactly once across retries.

Reply subjects retain the provider thread subject with exactly one `Re:`. A blank new-thread subject resolves in this order: operator input, configured/template subject, a three-example learned template populated only with current-lead facts, contextual current-lead generation, then `Your inquiry`. Learned templates contain placeholders (`{contact}`, `{company}`, `{address}`, `{project}`, `{email}`, `{number}`), never another lead's raw subject. The subject field remains visible/editable; a manual edit becomes operator provenance.

Every OPS draft/send uses one effective signature: current-operator OPS, mailbox OPS, exact Gmail provider identity, then none. Gmail import is read-only. Microsoft Graph has no Office-signature API, so Microsoft users save/paste an OPS signature. Missing signatures create one persistent operator/mailbox notification that deep-links to Email Settings and resolves/reopens with signature availability. Provider draft hydration strips any exact historical signature revision before appending the current one, preventing duplicate footers and signature contamination in learning. Historical profile scans skip a message entirely unless an exact connection-scoped known signature revision is removed; lookup failures and unmatched footers never enter the learning queue.

**Allowed levels per category:**

| Category | Valid levels |
|----------|--------------|
| CUSTOMER | off · draft_on_request · auto_draft · auto_send · auto_follow_up |
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
| `1` / `2` / `3` | Switch primary rail |
| `z` | Undo last toast action |
| `Esc` | Back to list |

### Command palette (⌘K)

Full-screen overlay built on `cmdk`. Type to fuzzy-search threads (live API query when ≥2 chars). Also exposes: archive / snooze / recategorize / mark unread / AI draft / compose new / switch primary rail / filter category. All commands collapse into the same keyboard flow as the inline shortcuts.

### Notifications

Fired from `EmailThreadService.classifyAndUpdate` post-hook:

| Event | Type | Persistent |
|-------|------|------------|
| Thread newly classified as CUSTOMER | `leads_waiting` — "New customer: {sender}" | No |
| Thread newly classified as PLATFORM_BID | `leads_waiting` — "Platform bid: {platform}" | No |
| URGENT label appears on an inbound thread | `role_needed` — "Urgent reply needed: {sender}" | No |
| Category ready to graduate to auto_send | `ai_milestone` — persistent until user acts | Yes |

Graduation check runs daily via `/api/cron/phase-c-graduation-check`.

### Dashboard integration

Two widgets ship with Inbox v2:

1. `inbox-leads` — unread CUSTOMER count + 7-day daily sparkline + median inbound-to-first-outbound response time. Clicks deep-link to `/inbox?category=CUSTOMER&filter=CLIENTS`.
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
| `/api/inbox/threads` | GET | Paginated list (cursor-based, 30s refetch). Query params: `scope=own\|company`, `filter=CLIENTS\|EVERYTHING_ELSE\|ALL\|ARCHIVED\|SNOOZED` (legacy six-tab and ball-in-court strings are accepted and degraded forward), `category=<one of 12>`, `search`, `cursor`, `limit`. Predicate built by `applyRailPredicate` in `src/lib/inbox/rail-predicates.ts`. |
| `/api/inbox/threads/[id]` | GET | Thread detail incl. provider messages. Live-fetches Gmail/M365 for full bodies and derives direction server-side against the connection email; falls back to `activities` if the provider call fails. Each message carries `direction`, `bodyText`, and `cleanBodyText` (quoted reply chain stripped via `stripQuotedContent`). |
| `/api/inbox/threads/[id]` | PATCH | Actions: `archive` / `unarchive` / `snooze` / `unsnooze` / `recategorize` / `markRead`. |
| `/api/inbox/writeback-preference` | POST | Set `archive_writeback_preference` on a connection. |
| `/api/inbox/backfill` | POST | Pulls historical mailbox content into `email_threads` one list-page at a time. Provider-agnostic (Gmail `messages.list`, M365 `/me/messages`). Body: `{ connectionId, monthsBack?=12, maxPages?=1, startPageToken?, classify?=false, dryRun?=false }`. Response reports `threadsSeen / threadsAlreadyPresent / threadsBackfilled / messagesUpserted / nextPageToken / completed`. Idempotent via `(connection_id, provider_thread_id)` unique constraint — safe to re-run and interleave with live sync. Clients loop until `completed: true` or `nextPageToken: null`. |
| `/api/cron/unsnooze` | GET | 5-min cron — re-applies INBOX to snoozed threads past their `snoozed_until`. |
| `/api/cron/stale-leads` | GET | Hourly cron — invokes router on CUSTOMER threads >7d quiet with outbound-last. |
| `/api/cron/phase-c-graduation-check` | GET | Daily cron — fires `ai_milestone` notifications for categories ready to graduate. |

### Key files

| File | Role |
|------|------|
| `src/app/(dashboard)/inbox/page.tsx` | Three-panel page layout + command palette + undo toast host |
| `src/lib/inbox/rail-predicates.ts` | Single source of truth for rail filter logic — `RailFilter` union, `InboxPrimaryRail`, `parseRailFilter`, `applyRailPredicate`, `classifyRail`, and row-state `isYourMove` / `classifyThreadState`. Shared by server query, in-memory classification, row state, and analytics. |
| `src/components/ops/inbox/inbox-route.tsx` | Integration layer — owns thread list fetch + selection, header chips, detail panes, ContextRail |
| `src/components/ops/inbox/thread-list.tsx` | Thread list (infinite query, hover actions, keyboard shortcuts) |
| `src/components/ops/inbox/thread-row.tsx` | Thread row card — subject, state tag, inline `// DRAFT` pill |
| `src/components/ops/inbox/thread-detail.tsx` | Center pane shell (header, four-button action cluster, scroll region) |
| `src/components/ops/inbox/context-rail/context-rail.tsx` | Right rail with Phase C / client / pipeline insights |
| `src/components/ops/inbox/category-chip.tsx` | 12-category display chip + interactive (RecategorizeMenu trigger) |
| `src/components/ops/inbox/recategorize-menu.tsx` | Popover with all 12 categories + "Tell Phase C why" note |
| `src/components/ops/inbox/thread-column-header.tsx` | Column header — rail filter dropdown + drafts / snoozed chips + refresh / archived / settings menu |
| `src/components/ops/inbox/header-chip.tsx` | Shared `// {n} {LABEL} ▾` chip shell used by DraftsChip + SnoozedChip |
| `src/components/ops/inbox/drafts-chip.tsx` | Header counter + popover for unsent drafts (provider + Phase C) |
| `src/components/ops/inbox/snoozed-chip.tsx` | Header counter + popover for currently-snoozed threads |
| `src/components/ops/inbox/snooze-picker.tsx` | Per-thread snooze presets + custom datetime picker |
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
| `images` | Yes | Blog thumbnails, in-post images | Public read (URL); **service_role** write (server upload routes). Anon write policies revoked — W3 §7 (`03_DATA_ARCHITECTURE.md`) |
| `social-media` | Yes | Generated social graphics | Public read (URL); **service_role** write (`supabase_upload.py`). Anon write policies revoked — W3 §7 |

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

Auth: Uses the **service_role** key (env override `SUPABASE_SERVICE_ROLE_KEY`, else a hardcoded service_role fallback, lines 35–38), which **bypasses storage RLS**. The `social-media` (and `images`) buckets' legacy `{anon}`/`{public}` write policies were vestigial from an early anon prototype (the `test-anon-write.jpg`/`probe-*.png` objects are its fingerprint) and were revoked by W3 §7 migration `20260705170000_sec_w3_storage_anon_write_revoke` (applied to prod 2026-07-05) — service_role writes are unaffected. See `03_DATA_ARCHITECTURE.md` § Storage.

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

The iOS app indexes user-accessible data into iPhone Spotlight so OPS records appear in the system-wide search. Projects, Clients, Contacts (sub-clients), Tasks, Invoices, Estimates, and Leads (pipeline opportunities) are indexed with thumbnails, phone-number / email metadata, and permission gating. Search works offline for the on-device (SwiftData) entities, and taps route into the app via the existing deep-link notification system.

**Leads are the one network-only domain.** Every other entity is SwiftData-backed and rides the sync engine's `SpotlightSyncTracker` for incremental updates. Pipeline opportunities are *not* in SwiftData (they're fetched on demand from Supabase), so they are sourced from `OpportunityRepository.fetchAll` and reconciled from `PipelineViewModel` instead — see **Leads (network-only)** below.

### Architecture

- `SpotlightIndexManager` (`OPS/OPS/Services/Spotlight/SpotlightIndexManager.swift`) — singleton, permission-gated index writer. Bulk backfill + per-entity incremental methods with scope-aware removal.
- `SpotlightItemBuilder` — converts entities to `CSSearchableItem` (SwiftData models for most domains; the in-memory `Opportunity` for leads)
- `SpotlightThumbnailRenderer` — produces 256×256 JPEG thumbnails from cached project images / client avatars, with SF Symbol fallbacks
- `SpotlightSyncTracker` — collects per-sync-pass dirty / deleted entity IDs so incremental updates are targeted, not full re-indexes
- `SpotlightBackfillCoordinator` — runs the initial indexing pass with a live iOS local notification showing progress, under a `UIBackgroundTask` so it survives app-background mid-run
- `SpotlightTapRouter` — handles `CSSearchableItemActionType` continuations, re-checks permissions, routes to detail views via existing `OpenXxxDetails` notifications
- `SpotlightDomainIdentifiers` — domain identifier constants (`co.opsapp.spotlight.project` etc.) used for targeted removal and tap decoding
- `AccessDeniedSheet` — shown when a tapped result is no longer permitted (e.g. role changed after indexing)

### Trigger points

- **Initial backfill:** after first successful full sync post-login, via `SpotlightBackfillCoordinator.runIfNeeded(context:)` called from `DataController` login flow
- **Incremental updates (SwiftData domains):** after every `InboundProcessor.linkAllRelationships` — dispatches the `SpotlightSyncTracker` diff (upserts + removals). Every merge method for an indexed entity (project, client, sub-client, task, invoice, estimate) calls `markDirty` or `markDeleted` based on whether the server soft-deleted the entity.
- **Lead freshness (network-only domain):** leads never touch `SpotlightSyncTracker`. `SpotlightIndexManager.reconcileLeads(_:)` is called from `PipelineViewModel.loadData` after every successful load, passing the full company opportunity set already in hand (no extra fetch). Because every lead change — create, edit, archive, delete, stage move, plus Supabase realtime and foreground-resume — funnels through that one load (`Lead*Success` listeners + `scheduleRefresh`), the single reconcile keeps system search current. It upserts every non-deleted / non-archived lead and prunes anything written last pass that is now absent, using a per-user persisted written-id set (`spotlight.indexedLeadIds.<userId>`). No-op until the initial backfill flag is set (mirrors the SwiftData incremental gate).
- **Role change:** when `PermissionStore.fetchPermissions` detects a new `roleId`, posts `SpotlightReindexRequested` notification → MainTabView clears and re-runs backfill (which re-fetches leads via `OpportunityRepository`)
- **Logout:** `DataController.logout()` clears the entire index via `SpotlightIndexManager.clearAll()`

### Permission gates (index time + tap time)

Using the existing `PermissionStore` keys:
- `projects.view` → Projects + Tasks (tasks inherit projects gate)
- `clients.view` → Clients + Contacts (sub-clients inherit the client gate)
- `pipeline.view` → Invoices + Estimates (same gate as the Money tab where these live)
- `estimates.view` → Estimates (also honored if a role grants it without pipeline access)
- `pipeline.view` **AND** the `pipeline` feature flag → Leads. Both are required — this mirrors `hasLeadsAccess` (the LEADS tab's own gate) exactly, so a lead is never indexed for a user who can't open it. If the feature flag is later turned off, `reconcileLeads` drops the whole lead domain on the next load.

Field crew (without `hasFullAccess("projects.view")`) only gets their assigned projects / tasks indexed. Projects in RFQ/Estimated status are hidden from users without `pipeline.view`.

**Permission checks happen twice:** at index time (we only write items the user is allowed to see) AND at tap time (in `SpotlightTapRouter`, in case the role changed between indexing and the tap). A tapped result the user is no longer permitted to see shows the `AccessDeniedSheet`.

### Domain identifiers

- `co.opsapp.spotlight.project`
- `co.opsapp.spotlight.client`
- `co.opsapp.spotlight.subclient`
- `co.opsapp.spotlight.task`
- `co.opsapp.spotlight.invoice`
- `co.opsapp.spotlight.estimate`
- `co.opsapp.spotlight.lead`

Item IDs are `"<domain>:<entityId>"` — decoded on tap to determine which entity type to open.

### Deep linking

Spotlight taps post the same notifications used by push notifications and universal links:
- `OpenProjectDetails` / `OpenClientDetails` / `OpenSubClientDetails` / `OpenTaskDetails` / `OpenInvoiceDetails` / `OpenEstimateDetails` / `OpenLeadDetails`

`MainTabView` observes each and routes to the appropriate detail sheet via `AppState`:
- `showClientDetails` → `ClientSheet(mode: .edit(client))`
- `showInvoiceDetails` → `InvoiceDetailViewDeepLinkWrapper`
- `showEstimateDetails` → `EstimateDetailViewDeepLinkWrapper`
- `OpenLeadDetails` (`userInfo["leadId"]`) → re-checks `hasLeadsAccess`, stashes `AppState.pendingLeadDeepLinkId`, switches to the LEADS tab; `LeadsTabView` drains it and resolves the opportunity from memory or a `fetchOne` network call (leads aren't in SwiftData), then presents `LeadDetailView`. Same route the notification rail and in-app universal search use.
- `showAccessDenied` → `AccessDeniedSheet`

The `ops://` URL scheme is registered in Info.plist for direct deep-link access: `ops://projects/{id}`, `ops://clients/{id}`, `ops://invoices/{id}`, `ops://estimates/{id}`. Handled in `AppDelegate.application(_:open:options:)`.

### Thumbnails

- **Projects:** first cached image from `ImageFileManager.shared` (`Documents/ProjectImages/`) — iterates through all cached images until one renders successfully, falling back to a briefcase SF Symbol
- **Clients:** avatar from `ClientAvatarCache.shared` (`Documents/ClientAvatars/`) — **new in this release**, required because avatars were previously memory-only. Falls back to `person.crop.circle.fill`.
- **Tasks:** parent project's thumbnail, or `checklist` SF Symbol
- **Invoices / Estimates:** SF Symbols (`doc.text.fill` / `doc.plaintext.fill`)
- **Leads:** the OPS opportunity glyph (`OPSStyle.Icons.opportunity`) on the steel-blue `AccentPrimary` brand token. Every lead shares this one static glyph, so it is rendered once and cached (leads re-reconcile on every pipeline load — per-lead rendering would be wasted work).
- All rendered at 256×256 JPEG quality 0.7

### Invoice & Estimate local persistence (companion architectural change)

Previously invoices, estimates, line items, and payments were fetched on-demand from Supabase via `InvoiceViewModel` / `EstimateViewModel` and held in in-memory `@Published` arrays. This meant they did not work offline and had no sync chokepoint for Spotlight indexing.

**Now they are locally persisted in SwiftData via `InboundProcessor`.** The sync engine pulls these entities with field-level merge (respecting pending `SyncOperation`s), same pattern as Projects/Clients/Tasks. View models are thin filter/action layers that read from SwiftData via explicit `@Query` or `FetchDescriptor`.

Sync order: `.estimate` before `.invoice` because invoices can reference estimates via `estimate_id`.

Call sites that previously used `invoiceVM.setup(companyId:)` / `estimateVM.setup(companyId:)` now pass a `modelContext`: `setup(companyId:modelContext:)`.

### Leads (network-only)

Pipeline leads (opportunities) are the only indexed domain that is **not** SwiftData-backed. The app fetches them on demand from Supabase (`OpportunityRepository`) and never persists them locally, so they cannot ride the sync engine's `SpotlightSyncTracker` delta path. The lead index is instead **reconciled from the full company set** on the same cadence the LEADS surface refreshes.

**Sourcing.**
- **Backfill** (`SpotlightIndexManager.indexAllLeads`): during the initial post-login backfill (and the role-change rebuild), the manager instantiates its own `OpportunityRepository(companyId:)` and calls `fetchAll()`, so leads are indexed even if the user never opens the LEADS tab. Runs last in the backfill so a slow network round-trip never delays the on-device SwiftData domains. A failed fetch leaves any prior lead index intact.
- **Catch-up for existing users** (`backfillLeadsIfNeeded`): leads shipped after the other domains, so a user whose initial backfill already completed would skip the full backfill entirely (its flag is set). `SpotlightBackfillCoordinator.runIfNeeded` therefore calls `backfillLeadsIfNeeded` on that path — a one-time lead index (no banner, no re-churn of the other domains), gated to fire exactly once via the absence of the written-id set and retried next launch if the network fetch fails. Fires at login / reinstall; on a warm relaunch where a local user row already exists the login flow is skipped, so those users pick leads up on first LEADS-tab open instead (via `reconcileLeads`).
- **Ongoing** (`SpotlightIndexManager.reconcileLeads(_:)`): called from `PipelineViewModel.loadData` after every successful load with the full `allOpportunities` set already in hand — **no extra network call**. Every lead mutation (create/edit/archive/delete/stage move) and every automatic refresh (Supabase realtime, foreground resume, pull-to-refresh) funnels through that load, so one reconcile keeps system search current.

**Reconcile algorithm.** `fetchAll` already excludes `deleted_at` rows server-side; `indexableLeads(_:)` additionally drops archived leads (the one gate that keeps them out of search). The manager then upserts every desired lead and diffs the desired id set against a **per-user persisted written-id set** (`spotlight.indexedLeadIds.<userId>`), issuing targeted removals for anything written last pass that is now gone (server-deleted, archived, or converted-away). The set is cleared on logout and role change alongside the backfill flag. This delta approach avoids a clear-and-rebuild flash and mirrors the "targeted, minimal updates" philosophy the SwiftData domains use.

**Gate.** `reconcileLeads` is a no-op until the initial backfill flag is set (same gate the SwiftData incremental path uses), and drops the entire lead domain via `deleteSearchableItems(withDomainIdentifiers:)` if it ever runs without pipeline access (mid-session role / feature-flag revocation).

**Item shape.** `SpotlightItemBuilder.buildLead` titles the item with the human label (`Opportunity.displayContactName` — contact name, falling back to the inquiry subject, then "Unnamed lead"); the subtitle scans stage → street → contact channel; `contactPhone` / `contactEmail` populate the native searchable `phoneNumbers` / `emailAddresses` attributes so a query on a number or address surfaces the lead.

### Caps & scaling

No arbitrary caps — Core Spotlight scales to millions of items. Bulk-index methods sort by `updatedAt` / `lastSyncedAt` descending so that if Spotlight ages items out under memory pressure, the most-recently-touched ones stay. Leads carry no such sort — the company's active pipeline is small (tens to low hundreds), reconciled whole on each pipeline load.

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

## Project Workspace as a Reusable Pattern

The unified `ProjectWorkspaceWindow` (shipped on `feature/project-workspace-modal`, 2026-05-08) is the template for every future entity workspace — client workspace, estimate workspace, invoice workspace. The shell is mode-aware so a single floating window handles `viewing`, `editing`, and `creating` for one entity, replacing the legacy pattern of separate detail / create / edit modals per entity.

### Why this is a pattern, not a one-off

The project rebuild collapsed five surfaces (`project-detail-modal`, `project-detail-sheet`, `create-project-modal`, `edit-project-modal`, `project-detail-popover`) into one. The same collapse applies to clients (where today there is a separate detail sheet, edit modal, and create modal) and to estimates / invoices (where the detail page is a full route and editing is a separate flow). The win is consistency: the operator sees the same chrome, the same mode pill, the same footer grammar regardless of entity.

### Reusable building blocks

When implementing the next entity workspace, reuse rather than re-derive:

| Building block | Lives at | What it gives the next workspace |
|---|---|---|
| Phase 5 atom kit | `OPS-Web/src/components/ops/projects/workspace/atoms/` | Token-bound primitives — `Mono`, `Cake`, `Body`, `Stack`, `Inline`, `Hairline`, `Btn`, `IconBtn`, `Chip`, `Section`, `Field`, `FieldRow`, `TextInput`, `TextArea`, `Select`, `Segmented`. Lift to `OPS-Web/src/components/ops/workspace/atoms/` when reused. |
| Window shell | `OPS-Web/src/components/ops/projects/workspace/project-workspace-window.tsx` | Generic floating-window shell — drag, 8-direction resize, traffic lights, mode pill, persistence keying. Genericize to `EntityWorkspaceWindow` on second clone. |
| `ConfirmModal` (destructive variant) | `OPS-Web/src/components/ops/projects/workspace/confirm-modal.tsx` | Workspace-scoped destructive confirm — glass-dense, rose accent stripe, sanctioned `--shadow-window` exception. Reusable for delete / revert / cancel flows on any entity. |
| Mode-aware footer config | shape: `ModeFooterConfig = { destructive | meta | spacer | secondary[] | ghost | primary }` | One primary per footer, declarative per-mode config drives layout. Shell reads config; new modes are config-only. |
| Activity timeline pattern | `project_notes` + nullable `event_kind` discriminator | One canonical table per entity (notes / events combined) is iOS-additive and avoids the unified-`activities`-table direction that breaks iOS sync. Apply the same shape for client_notes, estimate_notes, invoice_notes if needed. |
| Notification dispatcher pattern | `OPS-Web/src/lib/notifications/notification-dispatch.ts` | One helper per event kind (`dispatchProjectStatusChange`, `dispatchProjectArchived`, …). Single preference key per category. Replicate per entity. |

### Phase progression for the next entity workspace

The project rebuild ran 16 phases. The next entity workspace should follow the same skeleton — most phases stay identical, only the entity-specific bodies change:

1. **Schema** — add nullable columns / discriminator; iOS-additive contract holds
2. **Types** — entity TypeScript types + `EntityActivityEntry` discriminated union
3. **Hooks** — `useEntity`, `useEntityActivity`, `useEntityMutations`
4. **Primitives** — only if the atom kit needs a new shape; otherwise skip
5. **Atoms** — verify the kit covers the new entity; extract any new atom into the shared kit
6. **Shell** — mount `EntityWorkspaceWindow` with mode-aware footer config
7. **Bodies** — viewing dossier, editing tabs, creating tabs (entity-specific)
8. **Wiring** — open via `useWindowStore.openEntityWindow`, mount in `FloatingWindows`
9. **Deletion of legacy** — remove the old detail-modal / create-modal / edit-modal / route page surfaces; redirect any deep links to the new window
10. **Notifications** — one dispatcher per event kind; deep-link to `/?openEntity={id}&mode=view`
11. **Polish** — status-driven chrome (per-entity status colors), reduced-motion, keyboard
12. **Copy** — i18n dictionary `entity-workspace.json` (en + es)
13. **Tests** — unit (atoms + hooks), integration (mode switch, persistence, notification dispatch)
14. **Test gate** — type-check, lint, vitest green
15. **Docs** — bible `03`, `05`, `07` updates; OPS-Web `CLAUDE.md`; `.interface-design/system.md` patterns
16. **Verification** — manual visual walkthrough; PR

### Anti-pattern: don't fork the shell

If an entity needs a fundamentally different layout (e.g. estimate line-item editor or invoice ledger), the right move is **extending** the shell with a new mode (e.g. `editing-line-items`) and a new mode-aware footer config — not forking the shell into a parallel `EstimateWorkspaceWindow`. The shell is generic precisely so each new entity rides the same drag / resize / persistence / accessibility code path.

---

## 23. Quick Add Task Suggestions (iOS, 2026-05-10)

**Surfaces:** the TASKS section card on Project Details -> Details tab, the
Project Form task section, and each expanded project card in Projects Needing
Tasks.

**Source bug:** `e3996ac3-4180-4bdf-9423-f1d3b0c7b6de` — "Create suggested actions (like if user commonly adds 'rail install' task with Jake Strickler assigned, then allow user to add that with one tap)".

### Behavior

A horizontal scrollable chip rail sits inside the TASKS section card, between the last existing task row and the ADD TASK button. Each chip represents a `(taskTypeId, sortedTeamMemberIds)` combination the company uses frequently and recently.

- **Tap a chip** → creates a new `ProjectTask` on the current project immediately. No sheet, no confirm. Medium impact haptic. Status `active`, no dates, no notes. `taskType.color` becomes the task's color. Sync queued via `DataController.createTask(dto:)`.
- **Long-press chip → "Edit Before Adding"** → opens `TaskFormSheet(mode: .create)` with the task type + team members preselected via two new optional init params (`prefilledTaskTypeId`, `prefilledTeamMemberIds`).
- **Long-press chip → "Dismiss Suggestion"** → suppresses just this chip for just this project. Stored locally in `UserDefaults` under `quickadd.dismissed.<projectId>` as an array of SHA-256 base64 hashes. Never synced. Dismissal is per-project scope: a chip dismissed on Project A still surfaces on Project B.

### Shared project task composer (2026-07-13)

Project Form and Projects Needing Tasks use the same `ProjectTaskComposer`
instead of separate compact task rows.

- Suggestions appear first as horizontally scrolling task-type + crew cards.
  One tap adds the complete suggestion.
- Added tasks remain visible as two-line summary rows. Saving another task does
  not clear or replace the existing list.
- Tapping a summary expands a full-width editor inside that task row. Task type,
  crew, and schedule are stacked fields with field-sized touch targets rather
  than compressed horizontal chips.
- A manual `ADD TASK` action opens the same editor as an unsaved row. The row is
  appended only after a valid task type is selected and the user confirms.
- Existing rows can be edited, opened in the advanced `TaskFormSheet`, or
  deleted. Edits replace the row in place and preserve its stable local id.
- Project Form owns an in-memory `[LocalTask]` until the project is saved, then
  uses its existing reconciliation path. Projects Needing Tasks persists every
  add/edit/delete immediately and maps the returned `ProjectTask.id` into
  `LocalTask.existingTaskId` so later changes update the same record.
- The composer is rendered inside the expanded project card in Projects Needing
  Tasks, beneath client, crew, start date, address, phone, and email details.
  The task controls never detach visually from their owning project.
- The tutorial keeps the existing `add_task` wizard target and scripted
  `TutorialAddTaskTapped` handoff; live suggestions are hidden during tutorial
  mode.

### Signal model

- **Source set:** `project_tasks WHERE company_id = current AND deleted_at IS NULL`. No status filter — cancelled tasks count, since "rail install with Jake" being cancelled doesn't mean the setup isn't a habit.
- **Window:** 60 days, measured by the stable `createdAt` stamp on the local
  `ProjectTask` row, falling back to `lastSyncedAt` for older records.
- **Suggestion key:** `(taskTypeId, sortedTeamMemberIds.joined(","))`. Two tasks count as the same suggestion only if they share both task type AND the exact crew composition (order-insensitive).
- **Threshold:** ≥ 2 occurrences within the window.
- **Ranking:** `score = sum(exp(-daysAgo / 30))` across all occurrences in the window. Tiebreak by most-recent occurrence desc, then alphabetical task-type display.
- **Cap:** top 3 suggestions after dedup.
- **Dedup against current project:** drop any suggestion whose key already exists on the current project's tasks (ignoring status).

### Files

| File | Role |
|------|------|
| `OPS/Utilities/TaskSuggestionEngine.swift` | Pure SwiftData read. `TaskSuggestion` struct + `suggestions(context:companyId:for:)` static method + dismissal storage helpers. Uses `CryptoKit.SHA256` for the per-project dismiss key. |
| `OPS/Views/Components/Project/QuickAddSuggestionsRail.swift` | The chip rail view. `@Query`s `[TaskType]` + `[User]` for chip rendering, builds the DTO + enqueues sync on commit. |
| `OPS/Views/Components/Project/Tabs/DetailsTabView.swift` | Inserts the rail in `TaskListSection.body` above the ADD TASK row, gated by `canEdit`. |
| `OPS/Views/JobBoard/TaskFormSheet.swift` | Init gains `prefilledTaskTypeId`, `prefilledTeamMemberIds` optionals for the long-press path. |
| `OPS/Styles/Components/ProjectTaskComposer.swift` | Houses the shared suggestion rail, persistent summaries, stacked editor, picker sheets, advanced editor, and delete confirmation. |
| `OPS/Views/JobBoard/ProjectFormSheet.swift` | Binds the composer to the form's draft `[LocalTask]` and preserves tutorial gating plus final project/task reconciliation. |
| `OPS/Views/Review/ProjectsWithoutTasksReviewView.swift` | Binds one composer to each expanded project card and adapts local rows to immediate `DataController` create/update/delete operations. |

### Gates (no rail rendered)

- `canEdit == false` (read-only role).
- `tutorialMode == true` (tutorial uses scripted demo data; recency would surface the wrong cards).
- Engine returns `[]` (no qualifying suggestions, or all dismissed, or all already on this project).
- Task-type lookup misses for all candidates (orphaned `task_type_id`s).

### Design tokens

- Chip frame: 168 × 56pt, `OPSStyle.Colors.cardBackground` fill, `OPSStyle.Colors.cardBorder` 1pt stroke, `OPSStyle.Layout.cardCornerRadius` (10pt).
- 3pt colored left bar uses `taskType.color` to anchor the chip to its task type.
- Rail header `QUICK ADD` — `OPSStyle.Typography.smallCaption`, `tertiaryText`. Subdued — chips compete with neither the task rows above nor the ADD TASK button below.
- Animation: `OPSStyle.Animation.fast` for chip removals (dismiss / commit). Scale + opacity transition on enter/exit.

### Why on-device

`project_tasks` is already synced to SwiftData. Compute is cheap (a single fetch + a 60-day filter + an aggregation over a few hundred rows max for a typical trades company). Works offline. No new Supabase tables, no edge functions, no server-side suggestion API. The trade-off — every device computes the same suggestions independently — is acceptable for v1; consolidating to a server view is a follow-up if the row count grows large or per-user personalization becomes required.

---

## 24. Task Reminders (2026-05-10)

### Purpose

Pre-task prep work — "order vinyl," "order glass," "buy paint" — used to live in human memory and sticky notes. Reminders attach configurable lead-time pings to a TaskType (template) and materialize per-task instances every time a ProjectTask of that type is scheduled. Instances surface in the OPS notification rail and as a checklist on the project detail view. Bug 4f00c2d7.

### Decisions

1. Reminders attach to **tasks** via the TaskType template — set once on the TaskType, inherited to every task of that type.
2. `requires_ack` is **per-template configurable**. Non-ack reminders are informational pings, dismissible without a tick.
3. Recipients are **per-template configurable**: `task_crew | admins | permission | users`. Per CLAUDE.md, recipient resolution never filters by `users.role` — uses `users_with_permission` RPC + `is_company_admin` escape hatches.
4. **Shared checkbox.** One `acknowledged_at` + `acknowledged_by` per instance. First person to tick it clears it for everyone.
5. **Template-only.** No ad-hoc per-task reminders. One-off items live in `project_tasks.task_notes`.
6. **Live link** propagation: edits to a TaskType reminder template flow to every unacknowledged reminder on every open (non-completed, non-cancelled) task of that type. Completed/cancelled tasks freeze.

### Schema (Postgres)

**`task_type_reminders`** — template, attached to a TaskType
```sql
id                uuid PK
task_type_id      uuid FK → task_types(id) ON DELETE CASCADE
company_id        uuid
label             text                           -- e.g. "Order vinyl"
lead_time_days    int  DEFAULT 1 CHECK (>= 0)
fire_time_local   time DEFAULT '09:00:00'        -- in companies.timezone
requires_ack      boolean DEFAULT true
recipient_mode    text  CHECK IN ('task_crew','admins','permission','users')
recipient_config  jsonb DEFAULT '{}'             -- {permission:"k"} | {user_ids:[uuid]}
display_order     int  DEFAULT 0
created_at, updated_at, deleted_at
```

**`task_reminders`** — per-task instance
```sql
id                  uuid PK
task_id             uuid FK → project_tasks(id) ON DELETE CASCADE
company_id          uuid
source_template_id  uuid FK → task_type_reminders(id) ON DELETE SET NULL
-- snapshotted from template (live-linked while task is open + unack'd):
label, lead_time_days, fire_time_local, requires_ack, recipient_mode, recipient_config
-- state:
fires_at            timestamptz   -- computed via compute_reminder_fires_at()
acknowledged_at, acknowledged_by, dismissed_at, notified_at
created_at, updated_at, deleted_at
```

Indexes: `(task_id) WHERE deleted_at IS NULL`, `(fires_at) WHERE not-yet-acked-or-notified`, `(source_template_id) WHERE deleted_at IS NULL`, `(company_id)`. RLS scoped to `private.get_user_company_id()`.

### Triggers (live-link propagation)

| Trigger | When | Effect |
|---|---|---|
| `trg_project_tasks_after_insert_reminders` | AFTER INSERT on `project_tasks` | Materialize one `task_reminders` row per active `task_type_reminders` row for that task's type. |
| `trg_project_tasks_after_update_reminders` | AFTER UPDATE on `project_tasks` when `start_date`/`start_time` changes | Recompute `fires_at` for unacked reminders on open tasks. Reset `notified_at` if new time > now. Freeze on completed/cancelled. |
| `trg_task_type_reminders_after_insert` | AFTER INSERT on `task_type_reminders` | Materialize an instance for every open task of that type. |
| `trg_task_type_reminders_after_update` | AFTER UPDATE on `task_type_reminders` (deleted_at NULL) | Re-snapshot template fields to all unacked reminders on open tasks. Recompute `fires_at` if lead-time or fire-time changed. |
| `trg_task_type_reminders_after_soft_delete` | AFTER UPDATE when deleted_at transitions NULL → NOT NULL | Soft-delete unacked instances on open tasks. Acked rows stay as history. |

### Helper functions

- **`compute_reminder_fires_at(start_date, lead_time_days, fire_time_local, company_id)`** — STABLE. Converts task start to company-local date, subtracts lead days, combines with fire time, converts back to timestamptz via `companies.timezone`. Returns NULL when `start_date IS NULL` (dormant reminder).
- **`resolve_task_reminder_recipients(company_id, task_team_members, recipient_mode, recipient_config)`** — SECURITY DEFINER. Returns `SETOF uuid` resolved per mode. Used only by the cron dispatcher.

### Cron dispatch — `fire_due_task_reminders()`

SECURITY DEFINER function returning `int`. Scans for rows where `fires_at <= now() AND notified_at IS NULL AND acknowledged_at IS NULL AND dismissed_at IS NULL AND deleted_at IS NULL` and the parent task is not completed/cancelled. For each, resolves recipients and inserts one `notifications` row per recipient:

```
type           = 'task_reminder'
title          = label
body           = "{lead_days}d before {task_type_display} — {project_title}"
project_id     = project_id (text)
deep_link_type = 'project_task_reminder'
action_url     = '/projects/{project_id}?task={task_id}&reminder={reminder_id}'
action_label   = 'CONFIRM' (requires_ack) | 'OPEN TASK'
persistent     = requires_ack
```

Then stamps `notified_at = now()`. Wrapped in `FOR UPDATE … SKIP LOCKED` so parallel cron invocations don't double-fire.

Scheduled via pg_cron every 5 min if extension present; web cron endpoint can call the function directly otherwise.

### iOS implementation

- **SwiftData V4** — `OPSSchemaV4` adds `TaskTypeReminder` + `TaskReminder` @Model classes; lightweight migration from V3. Inverse relationships: `TaskType.reminderTemplates: [TaskTypeReminder]`, `ProjectTask.reminders: [TaskReminder]`.
- **DTOs** in `Network/Supabase/DTOs/TaskReminderDTOs.swift` — `TaskTypeReminderDTO`, `TaskReminderDTO`, `CreateTaskTypeReminderDTO`, `UpdateTaskTypeReminderDTO`, `AcknowledgeReminderDTO`, `DismissReminderDTO`, `SoftDeleteDTO`. Time-of-day encoded as `HH:mm:ss` over the wire, seconds-since-midnight in SwiftData (`fireTimeLocalSeconds`). `recipient_config` jsonb decoded into typed `ReminderRecipientConfig`.
- **Repository** — `TaskReminderRepository.shared` exposes `fetchTemplates(companyId:since:)`, `createTemplate`, `updateTemplate`, `softDeleteTemplate`, `fetchInstances(companyId:since:)`, `fetchInstancesForTask`, `acknowledge(id:userId:)`, `unacknowledge`, `dismiss`.
- **Sync** — `SyncEntityType` gained `.taskTypeReminder` (priority 5) and `.taskReminder` (priority 7). Both `InboundProcessor` and `DataActor` implement the merge path. After every reminder pull, `NotificationManager.refreshTaskReminderSchedules(context:)` is called to reschedule on-device pushes.
- **Local notifications** — `NotificationCategory.taskReminder = "TASK_REMINDER_NOTIFICATION"` with an `OPEN TASK` action. `NotificationManager.refreshTaskReminderSchedules` enumerates open reminders, filters to those targeting the current user (via on-device `reminderTargets(...)` mirror of the server-side resolution), schedules `UNCalendarNotificationTrigger` at `fires_at`, and cancels stale identifiers. `cancelTaskReminder(id)` removes the pending schedule on acknowledge/dismiss. Tap routes through `userNotificationCenter(_:didReceive:)` and posts `.openTaskReminder`.

### iOS UI

- **Template editor** — `TaskTypeReminderListSection` embedded in `TaskTypeDetailSheet` shows existing templates with edit/delete affordances and an ADD button. `TaskTypeReminderEditorSheet` is the per-template form: label, lead-time stepper with 1D/2D/3D/1W/2W presets, fire-time DatePicker, requires-ack toggle, recipient picker (segmented: task crew / admins / permission / users) with config field that varies by mode.
- **Checklist** — `ProjectReminderChecklist` embedded in `DetailsTabView` between Tasks and Description. Groups reminders by parent task (open tasks only); each row shows label + lead-time + due-date subhead. `requires_ack` rows render as a square checkbox (tap to confirm); non-ack rows show a circle + DISMISS button. Optimistic local writes with revert-on-server-failure via `refreshFromServer()`. Haptics on every interaction. Section auto-hides when no open reminders exist for the project.

### Edge cases

| Case | Behavior |
|------|----------|
| `project_tasks.start_date IS NULL` | `fires_at` = NULL. Dormant. Populated by reschedule trigger when the task gets a start date. |
| `fires_at` is already in the past at materialization | `notified_at` stays NULL — cron picks it up on next pass, fires immediately. |
| Task rescheduled into the past | Same as above. |
| Already-acked reminder, template lead-time edited | Acked rows are immutable. Template edit skips them. |
| Recipient `users` mode + user deactivated | They never resolve into the recipient set; no rail row inserted for them. |
| Recipient `permission` mode + zero users hold the permission | Zero rail rows inserted; reminder still visible to anyone reading the project. |

### Files

| Path | Purpose |
|------|---------|
| migration `task_reminders_schema` | Tables, indexes, triggers, helper + cron functions |
| `OPS/OPS/DataModels/TaskTypeReminder.swift` | Template @Model |
| `OPS/OPS/DataModels/TaskReminder.swift` | Instance @Model |
| `OPS/OPS/DataModels/Migrations/OPSSchemaV4.swift` | Schema bump |
| `OPS/OPS/Network/Supabase/DTOs/TaskReminderDTOs.swift` | Wire format |
| `OPS/OPS/Network/Supabase/Repositories/TaskReminderRepository.swift` | CRUD + ack/dismiss |
| `OPS/OPS/Views/JobBoard/TaskTypeReminderEditorSheet.swift` | Admin template editor surfaces |
| `OPS/OPS/Views/Components/Project/ProjectReminderChecklist.swift` | Crew-facing checklist |
| spec `docs/superpowers/specs/2026-05-10-task-reminders-design.md` | Approved design |

### Out of scope (follow-ups)

- Web admin UI for template editing (admins use iOS today; web tabular editor can land later).
- Recurring reminders (every X days, repeats) — single-shot only.
- Per-reminder snooze in the rail.
- User picker UI for `recipient_mode = 'users'` (current iOS surface is a comma-separated id field; web-side picker is the proper home).

---

## 25. Task Pairs — Auto-Create (2026-05-11)

### Overview

Configure pairs of task types so that creating one auto-creates the other on the
same project, with rich scheduling rules. Motivating example: "Glass Panel install
is auto-scheduled the first Wednesday on or after 1 week after Glass Rail install
ends, with the same crew."

Spec: `docs/superpowers/specs/2026-05-10-task-pairs-auto-create-design.md`.
Triggering bug: `f4bbd11c-7e79-482f-843d-b286052f3477`.

### Configuration

Pair behavior is configured at the **task type level** — never per-instance.
Reuses the existing `TaskTypeDependency` model in `TaskType.dependenciesJSON`,
extended with four new fields:

| Field | Type | Default | Purpose |
|-------|------|---------|---------|
| `auto_create` | bool | false | When the predecessor is created, auto-spawn this task |
| `inherit_crew` | bool | true | Spawn copies predecessor's `team_member_ids` |
| `min_gap_days_after_end` | int | 0 | Days after predecessor's end date before this task starts (`after_end` mode) |
| `weekday_constraint` | int? | nil | ISO 1=Mon…7=Sun; round up to next occurrence after the gap |

The existing `overlap_mode` enum gains a third value `after_end` alongside the
unchanged `percentage` and `constant` modes. Set on the **dependent** type's
dependency entry (the relationship is stored backward in the model — "Glass
Panel depends on Glass Rail with auto_create=true").

### Scheduling Rule Evaluation (`after_end`)

```
predEnd      = predecessorStart + (predecessorDuration - 1) days
dayAfterEnd  = predEnd + 1 day
gappedStart  = dayAfterEnd + max(min_gap_days_after_end, 0) days
result       = roundUpToWeekday(gappedStart, weekday_constraint)
```

`roundUpToWeekday` advances 0–6 days until it hits the target ISO weekday.
nil constraint returns the gapped date unchanged.

### Spawning Pipeline

`TaskPairSpawner.spawnPairs(forPredecessor:in:companyId:)`:

1. Fetch all non-deleted task types for the company.
2. Filter to types whose `dependencies` contain an entry with
   `dependsOnTaskTypeId == predecessor.taskTypeId && autoCreate`.
3. For each candidate, skip if:
   - A task with `pairedFromTaskId == predecessor.id && taskTypeId == candidate.id`
     already exists on the project (idempotency).
   - `SchedulingEngine.wouldCreateCycle` would create a loop.
4. Compute crew (inherit if requested + non-empty; else type's `defaultTeamMemberIds`).
5. Compute dates via `dep.earliestStart()` if predecessor has dates; else nil.
6. Insert the spawn with `paired_from_task_id` set and emit a sync op.

Spawner is invoked from **outbound** task creation paths only:
- `DataController.createTask(task:)`
- `DataController.createTask(dto:)` (the single source of truth for UI)

Spawner is **never** invoked from `InboundProcessor` — inbound tasks have
already been spawned on the source client and arrive via normal sync.

### Cascade Behavior

`SchedulingEngine.calculateCascade` was extended to skip tasks where
`schedulingLocked == true`. The lock is set automatically by
`DataController.updateTaskSchedule(... manualEdit: true)` (the default for
user-driven calls). System-driven calls — `pushTaskWithCascade` for affected
dependents, `undoCascade` for reverted tasks, `autoScheduleProject` for system
placements — pass `manualEdit: false` to preserve auto-tracking.

Once a paired task is locked, predecessor moves no longer auto-shift it.
The lock is only cleared by deleting and re-spawning.

### Delete / Cancel Cascade

One-way cascade from predecessor to paired descendants (matched by
`pairedFromTaskId`):

- `DataController.deleteTask(_:)` (hard delete) → soft-delete cascading children first
- `DataController.deleteTask(taskId:)` (soft delete) → soft-delete cascading children
- `DataController.updateTaskStatus(... to: .cancelled)` → cancel cascading children

Deleting / cancelling a paired task does NOT affect its predecessor.

### Notifications

On every successful spawn, `spawnPairsForPredecessor` creates an in-app
notification of type `task_pair_spawned` for each crew member assigned to the
spawn:

```
// NEW TASK
Auto-scheduled GLASS PANEL INSTALL for Wed Mar 11 — paired from Glass Rail install
```

Deep-links to the project details screen.

### UX — `TaskTypeSheet`

The existing dependency editor was extended:

- **3-way mode toggle**: `PERCENTAGE · CONSTANT · AFTER END` (sliding underline tabs).
- **After-End controls**: snap slider for gap days (presets `0, 1, 3, 7, 14, 21, 28`)
  + 8-segment weekday picker (`ANY · M · T · W · TH · F · SA · SU`).
- **Pair Behavior section** (always visible in edit mode):
  - `AUTO-CREATE THIS TASK WHEN [predecessor] IS CREATED` — toggle.
  - `INHERIT CREW FROM [predecessor]` — toggle, disabled while auto-create is off.
- **Auto-create badge** in view mode: `// AUTO-CREATED FROM [predecessor]`.
- **Visualization bars**: `after_end` mode renders predecessor → dashed gap line
  with `+Nd` label → dependent (with weekday prefix if constrained).

### Files Touched

| File | Change |
|------|--------|
| `OPS/DataModels/TaskTypeDependency.swift` | +4 fields, `after_end` case in `earliestStart`, `roundUpToWeekday` helper |
| `OPS/DataModels/ProjectTask.swift` | +`pairedFromTaskId`, `scheduleLocked`, `schedulingLocked` (protocol) |
| `OPS/DataModels/TaskType.swift` | +`defaultDuration` |
| `OPS/Utilities/SchedulingEngine.swift` | `SchedulableTask.schedulingLocked` + cascade guard |
| `OPS/Utilities/TaskPairSpawner.swift` | NEW |
| `OPS/Utilities/DataController.swift` | `spawnPairsForPredecessor`, `cascadeSoftDeleteToPaired`, `cascadeCancelToPaired`, `updateTaskSchedule(... manualEdit:)` |
| `OPS/Network/Supabase/DTOs/CoreEntityDTOs.swift` | DTO fields |
| `OPS/Network/Supabase/DTOs/CoreEntityConverters.swift` | DTO → model round-trip |
| `OPS/Views/JobBoard/TaskTypeSheet.swift` | 3-way mode toggle, after-end controls, pair toggles, after-end bars, description text |
| Migration `task_pairs_auto_create` | Adds `project_tasks.paired_from_task_id`, `project_tasks.schedule_locked`, `task_types.default_duration` |
| `docs/superpowers/specs/2026-05-10-task-pairs-auto-create-design.md` | Spec |

### Out of scope (follow-ups)

- OPS-Web parity for the pair-config UI (web reads/respects pair behavior via sync
  but the edit surface is iOS-only in this iteration).
- Multi-weekday rules ("M/W/F") — single weekday only.
- Time-of-day component to the rule (existing `startTime/endTime` defaults apply).
- Reactivating a cancelled predecessor auto-reactivating cancelled paired tasks
  (one-way cascade by design; user must reactivate manually).

---

## 26. iPhone Calendar Mirror (iOS, 2026-05-11) — Bug 68123654

One-way mirror from OPS schedule rows to a dedicated `OPS` calendar in the user's iPhone Calendar app. Powered by `EventKit` + `BGTaskScheduler` + a SwiftData side-table.

### Scope (current)

- `CalendarUserEvent` (personal events, time off — **any status**; title prefix reflects status)
- `ProjectTask` where the current user is in `schedulingTeamMemberIds`

### Excluded

- `SiteVisit` — iOS model is unwired (no DTO, no repository, no sync wiring; 0 production rows). Re-add as a follow-up once SiteVisit sync ships.
- Direct Google Calendar / Outlook OAuth sync — provider credentials, token storage, consent copy, and per-provider write semantics belong to the backend integrations layer. iOS uses EventKit; Apple, Google, and Outlook accounts are supported when they are configured in the device Calendar app and exposed as writable EventKit sources.
- Two-way sync — researched and rejected for the iOS EventKit mirror; the spec at `ops-ios/docs/superpowers/specs/2026-05-10-iphone-calendar-mirror-design.md` documents the rejected design space.

### Sync direction

One-way (OPS → device). Edits the user makes inside iPhone Calendar are **silently reverted** on next reconcile (reconcile-and-revert pattern). `EKCalendar.allowsContentModifications` is a read-only reflection of the source's capability — Apple offers no public API to mark our calendar read-only to the user, so we enforce the invariant by reconciling.

### Calendar destination

Dedicated `OPS` calendar, created in the device's default writable calendar source when possible. If no default source is available, iOS prefers CalDAV, then Exchange, then local storage. This lets the mirror land in Apple/iCloud, Google, or Outlook/Exchange when the user has configured that account as a writable iOS Calendar source. Calendar is recreated automatically if the user deletes it from iOS Calendar. Color: `OPSStyle.Colors.opsAccent` (#6F94B0 steel blue — iCloud may normalize slightly).

### Permission API

`EKEventStore.requestFullAccessToEvents()` (iOS 17+). Info.plist key: `NSCalendarsFullAccessUsageDescription`. **Full access** (not write-only) is required so the reconciler can read back its own events — write-only access blocks event reads, breaking reconciliation.

### Mirror window

Past 30 days → future 12 months from `Date()`. Prevents history dumps. Outside-window rows are excluded on backfill and pruned on reconcile.

### Architecture

| Component | Path |
|---|---|
| Singleton service (`@MainActor`-isolated, holds `EKEventStore`) | `OPS/Services/CalendarMirrorService.swift` |
| Pure title/body/hash builder | `OPS/Services/CalendarMirror/CalendarMirrorContent.swift` |
| Eligibility predicates (window + membership) | `OPS/Services/CalendarMirror/CalendarMirrorEligibility.swift` |
| Bridge for non-View access to ModelContainer | `OPS/Services/CalendarMirror/ModelContainerHolder.swift` |
| First-event-save permission sheet | `OPS/Views/CalendarMirror/CalendarMirrorPromptSheet.swift` |
| Settings toggle (integration card) | `OPS/Views/Settings/IntegrationsSettingsView.swift` (CALENDAR section) |
| Dismissable "mirror disabled" banner | `OPS/Views/ScheduleView.swift` |
| Side-table model | `OPS/DataModels/CalendarMirrorMap.swift` (see `03_DATA_ARCHITECTURE.md` §28) |

### Triggers

Mirror writes are fired from:

1. `CalendarUserEventRepository` — after successful `create`, `updateStatus`, `updateEvent`, `softDelete`, `softDeleteSeries`, `softDeleteSeriesFromDate`.
2. `DataController.updateTaskSchedule` — after schedule change.
3. `DataController.updateTaskTeamMembers` — after team change (may add/remove current-user eligibility).
4. `DataController.deleteTask` and cascaded soft-deletes — fires `unmirrorEvent`.
5. `RealtimeProcessor` — after applying remote `project_tasks` changes. For `calendar_user_events` realtime, the branch triggers a full `reconcileAll()` because the local SwiftData write happens later via fetcher.

Reconcile runs on app launch, `UIApplication.didBecomeActiveNotification`, `.EKEventStoreChanged` (debounced 1s via Combine), Supabase realtime for `calendar_user_events`, and opportunistic `BGAppRefreshTask` registered as `com.ops.calendar.mirror.refresh` (Info.plist `BGTaskSchedulerPermittedIdentifiers`).

### Reconcile-and-revert algorithm

1. Verify OPS calendar still exists (`EKEventStore.calendar(withIdentifier:)`). If nil, recreate and full backfill.
2. Iterate every `CalendarMirrorMap` row:
   - Source row still eligible? Compare EKEvent fields to source-of-truth. On drift, overwrite with source values. On hash change, update + bump hash.
   - Source row missing / soft-deleted / out of window / user no longer eligible? Delete EKEvent, delete map row.
   - EKEvent missing (user deleted in iOS Calendar)? Recreate from source.
3. Backfill any eligible source row that has no map entry.
4. Orphan sweep: events in OPS calendar with no map entry. Try to recover by parsing `EKEvent.url` (`ops://event/<id>`). If unrecoverable, delete.

The `contentHash` (SHA-256 of canonical "title|start|end|notes|allDay") makes idempotent reconcile near-free.

### Event title format

| Source | Title format | Example |
|---|---|---|
| `CalendarUserEvent.personal` | `{title}` | `Dentist` |
| `CalendarUserEvent.timeOff` (approved) | `Time Off — {title}` | `Time Off — Cottage` |
| `CalendarUserEvent.timeOff` (pending) | `[Pending] {title}` | `[Pending] Cottage` |
| `CalendarUserEvent.timeOff` (denied) | `[Denied] {title}` | `[Denied] Cottage` |
| `ProjectTask` | `{project.title} — {taskType.display}` | `Smith Deck — Plumbing rough-in` |

Approver-booked time off is created as `approved`, so it mirrors through the approved title path immediately after `CalendarUserEventRepository.create`.

`EKEvent.url` = `ops://event/<calendarUserEventId>` or `ops://projects/<projectId>/tasks/<taskId>` — doubles as deep-link tap-through and reconciler recovery anchor.

### Deep link

`ops://event/<calendarUserEventId>` routes through `AppDelegate.handleDeepLink` (new `event` entity case), posts `Notification.Name("OpenCalendarUserEvent")` with `eventId` in `userInfo`. Project task mirror uses the existing `ops://projects/<projectId>/tasks/<taskId>` form.

### Permission UX

1. **First-event-save prompt** — after the user taps Save on their first `CalendarUserEvent` post-update, gated on `ops.calendar.mirror.hasShownPrompt` UserDefault. Modal sheet (`CalendarMirrorPromptSheet`).
2. **Settings toggle** — `IntegrationsSettingsView` CALENDAR section. Confirm-alert on disconnect.
3. **Dismissable banner** — `ScheduleView`, shows when `hasShownPrompt && !isEnabled && status != .denied && dismissCount < 2`. Tap → enable.

### Logout / company switch

`CalendarMirrorService.handleLogout()` deletes the entire `OPS` calendar from EventKit (cascades to all mirrored events) and clears `CalendarMirrorMap`. Wired into `DataController.logout()`.

### Schema migration

`OPSSchemaV3` (`OPSSchemaCommon.unchangedModels + [WizardState, CalendarMirrorMap]`). Lightweight migration from V2 (purely additive).

### Side-table

See `03_DATA_ARCHITECTURE.md` §28 for the full `CalendarMirrorMap` shape.

### Background refresh

`BGAppRefreshTask` registered as `com.ops.calendar.mirror.refresh` in `AppDelegate.application(_:didFinishLaunchingWithOptions:)`. Opportunistic top-up only — primary path is foreground reconcile.

---

## 27. LiDAR Dimensioned Photo Capture

**Spec:** `ops-software-bible/specs/2026-05-10-lidar-dimensioned-photo-capture-design.md`
**Implementation plan:** `ops-software-bible/specs/plans/2026-05-10-lidar-dimensioned-photo-capture-plan.md`
**Status (2026-06-27):** Phases A–G complete. Phase H (acceptance testing) pending hardware validation against the §10.2 9-criterion table on iPhone 15 Pro + iPhone SE 3rd gen + iPad Pro M4. Feature flag `feature.measurement.dimensioned_capture` ships default **OFF**; flips ON after the §10.2 table goes green and 48 hrs of crash-free operation per §10.3. Simulator/build verification is not hardware validation.

### Summary

iOS-only feature. Tap **MEASURE** from `ProjectActionBar` on an active project → live AR view → shutter triggers AVFoundation+LiDAR synchronized capture (48 MP photo + 768×576 depth map + camera intrinsics) → opens `DimensionedAnnotationView` for tap-to-measure or auto-detected dimensions on classified windows/doors. Optional **reference-object precision mode** upgrades accuracy from `±1″ LIDAR` to `±5 MM CALIBRATED`. Output: PNG with burned-in Hover-style external-leader labels (2048 long-edge); optional PDF via PDFKit; structured `dimensions jsonb` row in `project_photo_annotations`.

**Operator path (2026-06-29):** `PROJECT → MEASURE → AIM → SHUTTER → TAP TWO POINTS → SAVE`. MEASURE can appear from active project action bar, project quick actions, and site visit capture. Release builds hide the entry while the feature flag is OFF. Debug builds keep a developer/test entry visible for AR-capable devices and show `// DEV FLAG OVERRIDE · FLAG OFF` inside capture. No-AR/simulator devices show a hardware requirement state instead of silently hiding or crashing. During live aim, the centered corner reticle is the capture target. The shutter enables once AR tracking reaches `.ready`/`.searching`; wall/opening detection can improve confidence and later expose AUTO, but it does not block manual point-to-point capture. The rolling level line stays hidden during normal aim and appears only after an opening lock.

### Wedge (why this exists)

Every other LiDAR measurement app forces a full room scan (Magicplan, Polycam), manual line-drawing per dimension (CompanyCam), or 8–12 guided cloud-processed photos (Hover). OPS is the only **one-shot snap → quote-ready dimensioned image in 5 seconds** flow for trades quoting.

### Architecture

| Component | File | Responsibility |
|---|---|---|
| Live aim phase | `ARWorldTrackingConfiguration` w/ `.smoothedSceneDepth` + `.meshWithClassification` | Mesh overlay + opening detection |
| Shutter handoff | `LiDARCaptureCoordinator` (5-step ARKit→AVCapture sequence) | Pause ARKit, snapshot anchors, activate AVCapture |
| Capture | `AVCaptureDevice.builtInLiDARDepthCamera` + `AVCapturePhotoOutput.depthData` | 48 MP photo + exact 768×576 FP32 depth-in-meters + intrinsics |
| Measurement engine | `DepthRaycaster` + `OpeningClassifier` + `ReferenceObjectCalibrator` + custom DLT `PnPSolver` | World-point extraction + auto-detection + scale calibration |
| Rendering | `RenderedPhotoComposer` + `DimensionsRenderer` (Hover-style external leaders) | 2048 long-edge PNG burn + on-screen overlay |
| Persistence | `DimensionedPhotoSyncManager` via existing `PresignedURLUploadService` | HEIC+embedded disparity → `project_photos.url`, rendered PNG → `project_photos.rendered_url` + `project_photo_annotations.rendered_photo_url`, sidecar JSON + FP32 depth-in-meters → S3 |
| UI | `DimensionedCaptureView` + `DimensionedAnnotationView` | SwiftUI views with 6-tool toolbar, calibrate flow, accuracy badge |

**Capture to annotation handoff (2026-05-13, updated 2026-06-27):** `.lidar` captures build a `DimensionedAnnotationHandoff` before presenting `DimensionedAnnotationView`. Live AR frame updates remain lightweight; full `ARKitSnapshot.meshFaces` extraction happens once at shutter, while ARKit is still running and immediately before `arSession.pause()`. The handoff loads the exact 768×576 standalone FP32 depth-in-meters asset from `CapturedAssets.depthURL`, converts the captured `meshFaces` into `AnchorSnapshot`, runs `OpeningClassifier`, validates candidates through `AutoMeasurer`, and passes `preloadedDepthMap`, `anchors`, and `detectedOpenings` into annotation. AUTO is shown only when real measured openings exist. If depth loading, anchor conversion, or classification produces no candidates, annotation still opens for manual measurement with AUTO hidden. `.visual` fallback bypasses auto-detect entirely, requires no depth, keeps AUTO hidden, and leaves CALIBRATE visible.

**Calibration continuity (2026-05-13, updated 2026-06-27):** CALIBRATE snapshots the current `DimensionsData` before returning to `DimensionedCaptureView` in `.calibration` mode. The calibration recapture is used only as reference-object input for `ReferenceObjectCalibrator`; the original annotation handoff, photo, and measurements remain the state of record. CANCEL reopens annotation unchanged. A successful credit-card or OPS-marker detection reopens annotation on the original photo with all prior measurements preserved and `calibration.method = reference_object`, `referenceObject`, `scaleFactor`, `estimatedAccuracyMeters`, `planeNormal`, and `planeOffset` copied from `CalibrationResult`. LiDAR calibrated sessions stay full-depth. Visual-SLAM calibrated sessions reopen with `COPLANAR ONLY`, and manual point-to-point measurement uses the stored reference plane through `PlaneRaycaster`; if no depth map or calibrated plane is present, annotation shows the limitation state instead of silently failing. If no supported reference is found, capture stays in calibration mode, shows `// ERROR — REFERENCE NOT FOUND · INCREASE LIGHT · RETRY`, and offers `USE UNCALIBRATED` to return to the unchanged annotation.

### Data model

- New `dimensions jsonb` column on `project_photo_annotations` (additive, NULL on legacy rows). Schema in spec §4.1.
- New `project_photos.rendered_url` and `project_photo_annotations.rendered_photo_url` text columns hold the derived 2048-long-edge PNG deliverable. `project_photos.url` and `project_photo_annotations.photo_url` remain the source HEIC/photo pointers.
- New `'measurement'` value in `photo_source` enum.
- SwiftData `PhotoAnnotation` extended with `dimensionsData: Data?` and `renderedPhotoURL: String?` (synced) + `localDepthMapPath`, `localSidecarPath`, `localCaptureFinishedAt` (local-only working state).
- `dimensions.calibration` now persists optional `planeNormal` and `planeOffset` for reference-object calibration. Visual/manual measurements depend on this plane and are valid only for points on the calibrated surface.

### Device fallback ladder

| Tier | Accuracy | UX |
|---|---|---|
| LiDAR (iPhone 12 Pro+, iPad Pro 2020+) | ±1″ uncalibrated, ±5 MM calibrated | Full pipeline + auto-detect + reference-object option |
| Non-LiDAR with ARKit | ±2″ in-plane only | Manual measurement only (no auto-detect); reference-object option is in-plane-only with `COPLANAR ONLY` badge |
| No AR support / simulator | Unavailable | Clear hardware requirement state; no crash, no silent hide in debug/test paths |

### Feature flag

`feature.measurement.dimensioned_capture` — default OFF in initial release, flips ON after 48 hrs of crash-free operation post-launch. Static fallback is fail-closed (`[]` in `FeatureFlagService`), so a failed flag fetch hides MEASURE in release. Shared entry policy lives in `MeasureActionButton`: flag ON + `.lidar`/`.visual` opens capture; flag ON + `.noDepth` opens the unavailable state; flag OFF + release hides the entry; flag OFF + debug opens capture for `.lidar`/`.visual` with the dev override warning and opens the combined flag/hardware limitation state for `.noDepth`.

### Out of scope (v1)

Multi-photo stitching, volume/3D measurement, third-party AR markers, web-side editing of measurements, voice annotations on dimensioned photos, auto-detection beyond windows/doors/wall-sections.

### Pre-existing security follow-up

`project_photo_annotations` RLS is wide open (all 3 policies evaluate to `true`). This spec inherits the gap but does NOT widen it. Tracked as separate ticket `RLS HARDENING - P1-1` — must complete before flipping the feature flag ON for production traffic.

---

## 28. Auto Bug Reporting (iOS, 2026-05-15) — May-12 outage follow-up

Automated silent-catch failure detection. Files a `bug_reports` row from any catch site in the iOS sync layer when a permanent error fires (RLS rejection, validation, 4xx) so the dev team sees the failure the day it starts instead of after a multi-day silent outage.

### The May-12 outage

On 2026-05-13 a migration tightened `project_photos.INSERT` RLS to require `projects.edit`. Crew and Unassigned users hold only `projects.view`, so all their photo uploads silently rejected for 3 days. The iOS app's catch site at `ImageSyncManager.insertProjectPhotoRows` swallowed the 42501 with a bare `print(...)` — the photo appeared in the iOS carousel (S3 + `projects.project_images` updates had succeeded) but never reached the client portal. No user could tell anything was wrong. No bug ticket was filed.

The RLS fix shipped in migration [`project_photos_insert_requires_view_not_edit`](https://github.com/canprojack/ops/blob/main/ops-web/supabase/migrations/20260515194437_project_photos_insert_requires_view_not_edit.sql). This subsection documents the second leg of the fix: the iOS auto-bug-reporting helper that ensures the next silent-catch shape can't sit for 3 days.

### Schema additions (`public.bug_reports`)

Migration [`20260515201615_bug_reports_add_dedupe_key_and_count`](https://github.com/canprojack/ops/blob/main/ops-web/supabase/migrations/20260515201615_bug_reports_add_dedupe_key_and_count.sql):

| Column | Type | Purpose |
|--------|------|---------|
| `times_reported` | `integer NOT NULL DEFAULT 1` | Occurrence count. Auto-filed bugs increment on every re-fire of the same dedupe hash. User-filed bugs stay at 1. |
| `last_reported_at` | `timestamptz NOT NULL DEFAULT now()` | Most recent occurrence timestamp. Distinct from `updated_at`, which also moves on triage / status changes by the dev team. |
| `dedupe_key` | `text NULL` | Stable SHA-256 hash with `auto:` prefix. Computed from `(category, screen_name, suspected_file, error_code)`. NULL for user-filed bugs. |

Partial unique index `idx_bug_reports_dedupe_key_active` on `(company_id, dedupe_key) WHERE dedupe_key IS NOT NULL AND status IN ('new', 'triaged', 'in_progress')` — dedupes only active tickets. A resolved/closed/duplicate bug whose hash re-fires later creates a NEW row, signaling a regression.

### `public.record_auto_bug` RPC

Migration [`20260515201643_bug_reports_record_auto_bug_rpc`](https://github.com/canprojack/ops/blob/main/ops-web/supabase/migrations/20260515201643_bug_reports_record_auto_bug_rpc.sql). SECURITY DEFINER, authenticated-role-only after migration [`20260515201810_bug_reports_record_auto_bug_revoke_anon`](https://github.com/canprojack/ops/blob/main/ops-web/supabase/migrations/20260515201810_bug_reports_record_auto_bug_revoke_anon.sql).

**Signature:**

```sql
record_auto_bug(
  p_category text,         -- always 'bug' from iOS
  p_priority text,         -- always 'high' from iOS
  p_screen text,           -- logical surface, e.g. 'ImageSyncManager.saveImages'
  p_suspected_file text,   -- Swift filename, e.g. 'ImageSyncManager.swift'
  p_error_code text,       -- SQLSTATE / HTTP / typed-error code
  p_summary text,          -- human-readable description
  p_metadata jsonb,        -- caller-controlled context (project_id, retry count, etc.)
  p_app_version text,
  p_build_number text,
  p_os_version text,
  p_device_model text,
  p_network_type text
) returns jsonb -- { id: uuid, created: bool, times_reported: int }
```

**Behavior:**

1. Resolves caller via `private.get_current_user_id()` + `private.get_user_company_id()`. Raises 42501 if either is null.
2. Computes `dedupe_key = 'auto:' || sha256(category:screen:suspected_file:error_code)`.
3. Looks up an active row matching `(company_id, dedupe_key)` against the partial unique index.
4. **If found:** increments `times_reported`, sets `last_reported_at = now()`, returns `{ created: false, times_reported: <new count> }`.
5. **If not found:** inserts a new row with `reporter_name = 'OPS iOS (auto-filed)'`, returns `{ created: true, times_reported: 1 }`.

A resolved/closed bug doesn't match step 3 because the partial index excludes those statuses — a regression after resolution lands as a new ticket.

### iOS — `AutoBugReporter` helper

[`OPS/Services/AutoBugReporter.swift`](https://github.com/canprojack/ops/blob/main/ops-ios/OPS/Services/AutoBugReporter.swift). `@MainActor` singleton.

**Configuration.** `DataController.setModelContext` calls `AutoBugReporter.shared.configure(connectivity: self.connectivity)` once at app launch so `network_type` can be derived from the live `ConnectivityManager`.

**Entry points.**

- `report(screen:suspectedFile:errorCode:summary:metadata:)` — base entry; classifies + fires unconditionally.
- `reportIfPermanent(_:screen:suspectedFile:summary:metadata:)` — classifies the `Error` via `UploadErrorClassifier` and fires only if the error is permanent. Returns the classified `UploadErrorKind` so the caller can drive retry / UI logic without re-classifying.
- `reportRetryExhausted(kind:attempts:screen:suspectedFile:summary:metadata:)` — fires when an in-session retry loop hits its cap with a non-pure-transient cause. Pure transient (bad signal) is normal in the field and never auto-bugs.

**Never throws.** Every entry point swallows RPC failures internally and logs to `DebugLogger.shared` instead of `print()`. The auto-bug fire must never break the caller's retry / UI flow.

**Client-side dedupe TTL.** 1-hour in-memory cache keyed by the same dedupe hash the server uses. Skips the RPC entirely if the same hash fired within the last hour. Server-side partial unique index handles the deduplication regardless; the client cache saves the round-trip during offline-drain storms (when the queue retries every 30s).

### iOS — `UploadErrorClassifier`

[`OPS/Utilities/UploadErrorClassifier.swift`](https://github.com/canprojack/ops/blob/main/ops-ios/OPS/Utilities/UploadErrorClassifier.swift). Triages any `Error` into a `UploadErrorKind` bucket:

| Bucket | Examples | Auto-bug? | Retry? |
|--------|----------|-----------|--------|
| `.transient(reason:)` | URLError offline / timeout / DNS / unreachable host; HTTP 5xx; HTTP 408/425/429; Postgres class 08/53/57/58 | Never. Bad signal is normal. | Yes — 1s/5s/15s/60s in-session, then cross-session queue. |
| `.permanent(errorCode:reason:)` | Postgres class 23 (integrity) / 42 (incl 42501 RLS) / 22 (data exception); HTTP 4xx (except 408/425/429); local `UploadError.invalidURL`; `SupabaseService.ServiceError.notAuthenticated`; `URLError.badURL` / `.badServerResponse` | Immediately. | No — won't succeed on retry. |
| `.unknown(reason:)` | Anything not matched above | Only after in-session retry exhaustion (`reportRetryExhausted` upgrades it). | Yes — same backoff as transient. |

### Catch sites instrumented (Phase 1)

9 logical sites across 4 files; 10 `AutoBugReporter` call points total — `PhotoProcessor.processOneUpload` fires twice (permanent short-circuit inside the retry loop AND retry-exhausted at the bottom).

| File | Site | Action |
|------|------|--------|
| `ImageSyncManager.saveImages` (catch) | After S3 + `projects.project_images` update | Classify; if permanent → auto-bug + mark `InFlightUpload.failed=true` + keep tile rendered. Transient → existing offline-fallback path (`saveImageLocally`). |
| `ImageSyncManager.insertProjectPhotoRows` (the May-12 site) | Best-effort `project_photos` insert | Classify; if permanent → auto-bug + return `false`. Callers flip `InFlightUpload.failed=true` so the user sees the red badge. |
| `ImageSyncManager.syncImagesForProject` (offline drain catch) | Periodic retry of pending uploads | Classify; if permanent → auto-bug + **drop the poisoned items from `pendingUploads`** so the 30s retry timer doesn't burn forever on a rejection. Transient → keep queued. |
| `PhotoProcessor.processOneUpload` | Cross-session upload queue worker | **Split retry semantics:** in-session 4-attempt backoff (1s/5s/15s/60s) with permanent short-circuit; cross-session `uploadRetryCount >= 20` threshold preserved. Auto-bug on permanent OR on in-session exhaustion with non-pure-transient cause (2 RPC call points in this one function). |
| `DimensionedPhotoSyncManager.insertProjectPhotoRow` (LiDAR) | Same shape as May-12 site | `reportIfPermanent` + DebugLogger. |
| `DimensionedPhotoSyncManager.insertAnnotationRow` | Authoritative annotation insert | `reportIfPermanent` + existing queue-for-retry path. |
| `DimensionedPhotoSyncManager.retryQueued` | Background retry sweeper | `reportIfPermanent` so poisoned annotations don't loop forever. |
| `PhotoAnnotationSyncManager.uploadAnnotationPNG` | S3 upload of annotation overlay | `reportIfPermanent` + existing local-save fallback. |
| `PhotoAnnotationSyncManager.syncPendingAnnotations` | Background retry of cached annotations | `reportIfPermanent` to surface poisoned-row regressions. |

### Race-safe RPC (post-review fix)

Migration `20260515205350_bug_reports_record_auto_bug_race_safe` wraps the INSERT branch in `BEGIN ... EXCEPTION WHEN unique_violation`. Two concurrent fires of the same dedupe hash can both pass the initial SELECT before either inserts; the partial unique index makes one win and one raise `23505`. The EXCEPTION block catches the loser and replays the dedupe as an UPDATE so neither call is silently dropped. The original SELECT-then-INSERT path stays as the happy path (no exception overhead when there's no race).

### UI — failed-tile carousel

`InFlightUpload` (defined in `ImageSyncManager`) gains `failed: Bool` and `lastError: String?`. The activity tab's `ProjectPhotosCarousel` renders failed tiles with a red border + corner badge + "RETRY" label instead of removing them from the list. Tap-to-retry calls `ImageSyncManager.retryFailedInFlightUpload(id:for:)`. Long-press (context menu) dismisses without retry.

The cross-session `LocalPhoto.status = "failed"` path remains unchanged — PhotoProcessor flips photos to `"failed"` after in-session exhaustion, the next `processUploadQueue` pass picks them up.

### Retry semantics summary

| Layer | Scope | Cap | Backoff | When auto-bug fires |
|-------|-------|-----|---------|---------------------|
| In-session (within a single upload attempt) | One `processOneUpload` invocation | 4 attempts | 1s / 5s / 15s / 60s | Permanent error AT ANY attempt; OR cap exhausted with non-pure-transient cause |
| Cross-session (between app launches) | `LocalPhoto.uploadRetryCount` | 20 attempts → `permanently_failed` | None (waits for next app launch + good connectivity) | Never directly. The in-session loop within each attempt fires its own auto-bugs as needed. |

The two caps are independent on purpose. A photo with 4 transient failures across 4 days of bad signal isn't permanently broken — it's just waiting for the truck to drive somewhere with bars. Don't conflate.

### Out of scope (Phase 1)

180+ catches in `SyncEngine`, `InboundProcessor`, `OutboundProcessor`, `RealtimeProcessor`, `DataController`, auth managers, repository wrappers — these may contain other silent-catch shapes. Tracked as a separate audit phase.

---

## 27. Project Priority Queue & Auto-Schedule (iOS, 2026-06-04)

The Priority Queue is an office/admin screen that ranks **active projects** and
auto-schedules each ranked project's unscheduled tasks in priority order. It
superseded the earlier task-level priority queue (the pivot removed
`ScheduleRequest.Mode.taskPriorityQueue` and all task-level `priority_rank`
plumbing; `project_tasks.priority_rank` still exists in Postgres but is **dead**
— it is no longer read or written by iOS).

### Data contract

| Column | Type | Semantics |
|--------|------|-----------|
| `projects.priority_rank` | `double precision`, nullable | Company-wide manual rank. **Lower = higher priority.** `NULL` = unranked. Fractional indexing (`FractionalRank`, default step 1024) so a single drag dirties a single row. Synced via `SupabaseProjectDTO.priorityRank` ↔ `priority_rank`. |

Ranking is local-first: drag writes go through `DataController.reorderProjectPriority` / `bulkSetProjectPriority` (SwiftData save + `recordOperation`), then sync to Supabase. The waterline UI splits projects into **ranked** (above, numbered) and **unranked** (below, default order).

### Engine — `AutoScheduleManager`

Pure logic, no DB writes (returns a `SchedulePlan` the caller commits). The queue uses `Mode.projectPriorityQueue(orderedProjectIds:)` → `scheduleBatch(respectOrder: true)`. Per project, in caller order, it places each **active, still-unscheduled** task (`start_date == nil || end_date == nil`) through `placeNext`:

1. **Dependency floor** — earliest start from predecessors (matched by `taskTypeId` via `effectiveDependencies`), considering both DB tasks and already-placed batch tasks. *Note: as of 2026-06, no company has any task-type dependencies configured, so this pass is a no-op in practice and sequencing rides entirely on crew availability.*
2. **Crew availability** — `findAvailableSlot` scans forward for the first contiguous block where every assigned crew member is free, treating existing DB commitments **and** earlier batch placements that share crew as booked. Same-crew tasks serialize; different-crew tasks run in parallel.
3. **Geographic grouping** — optional later alternative when same-crew work clusters within `proximityGroupingRadiusKm`.
4. **Gap days** — reported in `ScheduleMetadata`.

**Granularity & rules:**
- **Whole-day** placements only. `start_time`/`end_time` are not set by the batch path; `SchedulingWindow`/`preciseScheduling` are built into `ScheduleConstraints` but not yet applied here.
- `skipWeekends` defaults to **true** (`Company.skipWeekendsInAutoSchedule`). End dates are computed in **weekdays** when skip-weekends is on — a 2-day task starting Friday ends the following Monday (the days it actually reserves), never Saturday.
- Only `status == .active` tasks are placed; completed/cancelled tasks with null dates are excluded but remain visible as commitments.
- **No crew assigned:** the task is still placed (a `noCrewAssigned` conflict is attached as a warning) on the dependency floor; multiple crewless tasks **within the same project** stack back-to-back rather than colliding, while crewless work **across** projects still parallelizes. (Design decision — crew can be assigned after the plan is committed.)
- Anchor is clamped to `max(startOfDay(anchorDate), today)` — auto-schedule never places in the past.

### Workflow

- **SCHEDULE ALL** → `buildPlan()` builds a `SchedulePlan` over ranked (plus unranked when **INCLUDE UNRANKED** is on) → preview sheet (`PrioritySchedulePreviewSheet`, grouped task + project + dates + conflicts) → commit writes each placement via `DataController.updateTaskSchedule(... manualEdit: false)` (system-driven, does not lock the task). A confirmation banner shows the committed count.
- **SCHEDULE NEXT** → `tapToPlaceNext()` schedules the single top ranked project that still has unscheduled tasks (`autoScheduleProjectV2`).
- Both run buttons are gated on whether a candidate project actually has a schedulable task (`hasSchedulableTask`), so neither enables when there is nothing to place, and **SCHEDULE ALL respects INCLUDE UNRANKED.**

### Key files (iOS)

- `OPS/Views/Components/Scheduling/PriorityQueueView.swift` — waterline list + run bar
- `OPS/Views/Components/Scheduling/PrioritySchedulePreviewSheet.swift` — review/commit sheet
- `OPS/ViewModels/PriorityQueueViewModel.swift` — ranked/unranked state, run orchestration
- `OPS/Utilities/AutoScheduleManager.swift` — placement engine
- `OPS/Utilities/ScheduleTypes.swift` — `ScheduleRequest` / `SchedulePlan` / provider protocol
- `OPS/Utilities/DataController.swift` — `ScheduleDataProvider` conformance + priority writes
- `OPSTests/PriorityQueueSchedulingTests.swift` — engine regression tests

---

## 29. Phase-C Suggested Calendar Events (iOS, 2026-06-22) — item 63144953

Second half of the "connect calendar + auto-add detected events" feature request. **Part A** (mirror the OPS schedule → iPhone Calendar) shipped 2026-05-11 as [§26 iPhone Calendar Mirror](#26-iphone-calendar-mirror-ios-2026-05-11--bug-68123654). **Part B** surfaces the upcoming commitments **Phase C detected in a company's email** as confirm-to-add suggestions on the iOS Schedule tab — **without coupling the app to the Phase C engine.**

### The decoupling problem

Phase-C detected events are `agent_memories` rows (`category = 'commitment'`, nullable `due_date` = the detected time). That table's RLS is `company_id = (auth.jwt() ->> 'company_id')::uuid`, which is **NULL for the Firebase-bridged iOS JWT** — so a direct iOS read returns zero rows. Phase C itself is headless / Canpro-only / not live-deployed, and **the app must never depend on it running.**

### Server: two SECURITY DEFINER RPCs (additive)

Applied to `ijeekuhbatykdomumfjx` as migration `phasec_suggested_calendar_events_rpc` (recorded at `ops-ios/docs/superpowers/migrations/2026-06-22-phasec-suggested-calendar-events-rpc.sql`):

| RPC | Returns | Purpose |
|-----|---------|---------|
| `get_suggested_calendar_events()` | `setof (id, content, due_date, entity_id, confidence, resolved_at)` | The caller company's **unresolved, upcoming (`due_date >= now()`), time-bearing** commitments, `confidence >= 0.5`, soonest first, capped 100 |
| `resolve_suggested_calendar_event(p_memory_id uuid)` | `jsonb {resolved, id}` | Idempotently stamps `resolved_at` so a confirmed/dismissed commitment isn't re-offered |

Both resolve the caller's company via the canonical `get_user_company_id()` helper (matches `auth.jwt()->>'sub'` against `users.auth_id` / `users.firebase_uid` — **never `auth.uid()`, never the absent JWT `company_id` claim**). `EXECUTE` granted to `authenticated` only; `anon`/`public` revoked.

**Why this reads `agent_memories` despite that table's broken RLS:** the functions are `SECURITY DEFINER` **owned by `postgres`**, which has `rolbypassrls = true`. A definer function executes as its owner, so the query inside runs with RLS **bypassed** — the explicit `WHERE company_id = get_user_company_id()::uuid` is the entire authorization boundary. (Same mechanism the schema's `get_user_company_id()` helper already relies on against the RLS-protected `users` table. Verified end-to-end by calling the RPC under `SET ROLE authenticated` + a simulated iOS JWT — it returns the company's rows; cross-tenant callers get none.) **Do not** "fix" this by rewriting the `agent_memories` RLS policy — that's unnecessary and would touch live Phase-C tables.

### iOS: dormant-when-empty review surface

`get_suggested_calendar_events()` returning `[]` is the **normal, healthy state** — iOS only ever reads a list, and an empty list renders nothing. That contract is what satisfies "the app never depends on Phase C": no engine → no rows → no surface, no errors.

| Concern | File |
|---------|------|
| RPC DTOs (resilient confidence/date decode) | `OPS/Network/Supabase/DTOs/SuggestedCalendarEventDTOs.swift` |
| RPC repository (swallows all errors → `[]`) | `OPS/Network/Supabase/Repositories/SuggestedCalendarEventRepository.swift` |
| Load / dedup / confirm / dismiss + timing map | `OPS/ViewModels/CalendarViewModel+SuggestedEvents.swift` |
| Review sheet + confirm cards | `OPS/Views/Calendar Tab/Components/SuggestedEventsReviewSheet.swift` |
| Dormant banner + entry point | `OPS/Views/ScheduleView.swift` (`suggestedEventsBanner`) |

**Flow:** Schedule-tab on-appear (and pull-to-refresh) calls `loadSuggestedEvents()`. Non-empty → a compact `// SUGGESTED EVENTS · N` banner appears above the calendar → opens the review sheet. Each card shows the detected commitment + due date with **ADD / DISMISS**:
- **ADD** → creates a personal `CalendarUserEvent` via `CalendarUserEventRepository.create` (which fires the mirror → the event lands on the connected iPhone Calendar) **and** calls `resolve_suggested_calendar_event` so it isn't re-offered. Local-insert → server-id flow matches `UserEventSheet.save` exactly (the mirror fetches the *local* row by `id == opsId`, so the local id is reassigned to the server id before the explicit mirror call). First add with mirroring off reuses the `CalendarMirrorPromptSheet` consent gate.
- **DISMISS** → resolves the commitment (no event created) so it isn't re-offered.

**Timing:** Phase C stores deadline-style commitments at an end-of-day boundary in **UTC** (`00:00` / `23:59`), so `eventTiming` detects all-day via **UTC** components (a `23:59Z` deadline must stay all-day even though it reads as ~`16:59` locally in North America); a genuine time-of-day becomes a 30-minute block. All-day events anchor to the local day of the instant.

**Dedup** ("not already in the calendar"): the server omits `resolved_at`-stamped rows; the client additionally skips any suggestion whose title+day already matches an existing `CalendarUserEvent`, and re-resolves any already-on-calendar commitment that came back unresolved (closes the offline-confirm gap).

---

## 30. "Add to OPS" Share Extension (iOS, 2026-06-22) — item 1e3c6fa8

Lets a user push photos into a project straight from the iOS share sheet (Camera, Photos, Files, Messages, etc.) without opening OPS. New `OPSShareExtension.appex` app-extension target embedded in the OPS app.

**Targets / project layout (Xcode-16 synchronized groups, `OPS.xcodeproj`):**
- `OPSShareExtension/` — the extension (own synchronized root group, Info.plist with `com.apple.share-services` + `NSExtensionActivationSupportsImageWithMaxCount`, bundled brand fonts, `OPSShareExtension.entitlements`). Bundle id `co.opsapp.ops.OPS.ShareExtension`.
- `Shared/` — a synchronized root group compiled into **both** the app and the extension (the cross-process data contract).
- App target gains an "Embed Foundation Extensions" copy-files phase + a dependency on the extension.

**App Group `group.co.opsapp.ops`** on both entitlements is the only cross-process channel. The extension **never runs Firebase, Supabase, or SwiftData.**

**Session bridge (`Shared/ShareSessionBridge.swift`).** The app writes a snapshot to the App Group on login (`DataController.fetchUserFromAPI`) and every foreground (`OPSApp` scenePhase `.active` → `DataController.refreshShareSessionBridge` → `ShareSessionBridgeWriter`), cleared on logout: `userId`, `companyId`, a short-lived Firebase ID token + expiry (`FirebaseAuthService.getIDTokenResult`), `canEditProjects` (`projects.edit`), and the editable-project list (team-scoped, or all for full-access roles; archived/closed/deleted excluded).

**Capture → upload.** The picker (searchable, single-select, OPS-styled via a self-contained `ShareTheme` mirroring `OPSStyle`) gates to the bridge's editable projects. On confirm the extension downscales each image (ImageIO thumbnail, ≤2048px, JPEG 0.8 — bounded for the ~120MB extension ceiling), writes it to the App Group inbox, and appends a job to the file-coordinated manifest (`Shared/ShareUploadManifest.swift`). If the bridged token is usable it presigns (`/api/uploads/presign`, folder `projects/{companyId}/{projectId}`) and starts a **background `URLSession`** PUT (shared container, same session id as the app); otherwise the job stays `pendingPresign` for the app to upload.

**Finalize (app side).** `ShareUploadCoordinator` re-attaches to the background session so iOS delivers S3 completions to the app after the extension is gone, then drains on launch + foreground + a Darwin nudge + background-session finish. `SharePhotoFinalizer` is **REST-only (no SwiftData)** so it works when iOS relaunches the app in the background: appends to `projects.project_images` (`text[]`), inserts `project_photos` rows (`source = in_progress`, matching the in-app gallery add — the `photo_source` enum has no share-specific label), and posts a completion notification to the uploader deep-linking to the project (`ops://projects/<id>`). Defense-in-depth `projects.edit` re-check when permissions are loaded; idempotent; per-project batched notifications.

**External gate (Apple Developer portal — not in code):** register the App Group `group.co.opsapp.ops`, enable it on the app's App ID + a new App ID for `co.opsapp.ops.OPS.ShareExtension`, and create/refresh provisioning profiles for both. Code compiles with `CODE_SIGNING_ALLOWED=NO`; device install / TestFlight need the portal step.

---

## 31. App Update Gate (iOS + Web, 2026-06-23)

Version-aware in-app messages shown on launch: force-update walls, optional update nudges, maintenance notices, and announcements. An admin authors a message in the web panel and toggles it live; the iOS app evaluates it against the installed version and shows the right sheet. Replaces the prior all-or-nothing app-message check (which had no version awareness and a stale DB schema).

**`public.app_messages` table** (RLS, **anon SELECT** so the kill-switch works pre-login — content is broadcast/update copy only, no customer/company data; writes are service-role only):
- `title`, `body`, `message_type` (`mandatory_update | optional_update | maintenance | announcement | info`)
- `active` (NOT NULL default **false** — drafts start inactive; one active at a time, enforced in the web layer)
- `dismissable` (false = blocking wall, true = dismissable overlay)
- `app_store_url`, `target_user_types text[]` (role allowlist; null/empty = all)
- `minimum_version` / `maximum_version` — half-open targeting range **[min, max)**: applies iff `installed >= min` AND `installed < max` (either null = open)
- `platform` (`ios`/`android`; null = all), `start_date` / `end_date` (schedule window)

**Version model.** A force-update for "everyone below the fix 3.1.0" sets `maximum_version = 3.1.0` (+ `mandatory_update`, `dismissable=false`). Everyone below is walled; the moment a user updates to 3.1.0+ they leave the range and the wall **self-resolves** — no admin cleanup, and already-updated users are never blocked. `minimum_version` is the optional inclusive lower bound for narrow targeting. Comparison is component-wise numeric (`3.10.0 > 3.9.0`, `3.1 == 3.1.0`).

**iOS (`OPS/Network/Services/`):**
- `AppMessageGate` — pure evaluator (`applies`, `resolve`, `semVerCompare`, `parseTimestamp`). Range/platform/schedule/role checks; picks one blocking + one dismissable by priority (`mandatory > optional > maintenance > announcement > info`) then recency. Fully unit-tested (`OPSTests/AppMessageGateTests.swift`). Role is enforced only when known — pre-auth a targeted message still applies so a wall is never let through for an unclassified user.
- `AppMessageService.fetchActiveMessages()` — **anonymous** PostgREST GET (anon key, no Firebase token) because the shared `SupabaseService.client` throws when unauthenticated. Works in every auth state; fails open (empty) on error.
- `AppStoreVersionService` — Apple iTunes Lookup (`itunes.apple.com/lookup?bundleId=`) for the live App Store version. When installed < store and no published message covers it, the gate synthesizes a dismissable "New version ready" nudge → solves "users don't notice updates" with zero admin action. Free, fails open.
- `AppUpdateGate` (`@MainActor ObservableObject`) — orchestrates fetch + lookup + evaluate, publishes `blockingMessage` / `dismissableMessage`, session-dismiss tracking, 60s foreground throttle.
- Wiring: `OPSApp` owns the gate, refreshes on cold launch (`.task`, `force`) and every foreground (scenePhase `.active`, throttled), and renders `blockingMessage` as a root `.overlay` **before sign-in** (pre-auth kill-switch). `PINGatedView` renders the role-aware `dismissableMessage` post-auth. `AppMessageView` renders all four states (blocking+URL = UPDATE NOW; dismissable+URL = DISMISS/UPDATE NOW; dismissable no-URL = DISMISS; blocking no-URL = `[ ACCESS SUSPENDED ]`). Fail-open throughout — a backend outage or offline device never blocks the app.

**Web admin** (`OPS-Web/src/app/admin/app-messages/`): full CRUD; activating deactivates others (one live at a time); min/max version inputs (semver-validated), platform select, schedule pickers, and a one-click **Force update** preset (sets `mandatory_update` + non-dismissable, focuses `maximum_version` = "block versions below the fix"). Queries insert/update wholesale, so adding a field to the `AppMessage` type flows end-to-end.

**No automatic version detection beyond the App Store nudge** — the force-update floor is admin-set and bumped only for blocker bugs; the app never force-updates on every release.

## 32. Email File Capture and Lead Attribution (Web, production 2026-07-17)

Every synced Gmail or Microsoft 365 activity receives a durable attachment scan, even when the provider says `hasAttachments=false`. Gmail recursion retains nested parts, CID/inline images, filename-less body data, documents, and small real photos. Microsoft enumeration retains inline, file, item, and reference attachments across validated same-message pagination. Pathological responses are capped at five Graph pages / 500 descriptors, 20 reference-metadata calls, or 500 Gmail parts; truncation creates an explicit review marker. Enumeration is time-bounded and raw downloads are byte- and request-bounded.

Each worker run copies at most 20 provider files and 50 MiB aggregate. Work beyond that budget is deferred without burning a per-file retry. Provider 404/410 is terminal unavailable; 400/413/422 are not blindly discarded. Oversize and unsupported external references remain visible provenance. Stored raster images flow into the lead/project Photos surfaces; all canonical files appear in Inbox Files and document surfaces. Existing manual lead photos are never overwritten.

Vision runs only from verified OPS-stored bytes and is cached per canonical attachment. Reattribution replays acceptance against the cached inspection rather than paying for vision twice. Eight exhausted attempts terminalize scan/inspection jobs and create one internal notification deep-linking to the affected inbox thread. Auth failures park only the mailbox scan and create a persistent reconnect notification; resource-specific attachment denial does not pause an otherwise healthy Microsoft mailbox.

Costs are usage-based: private Supabase Storage/egress, Vercel worker invocations, provider read calls, and vision tokens for eligible stored images. Bounded idempotent work prevents duplicate storage and repeat vision charges. This subsystem has no provider write or email-send capability.

---

## 33. Lead Assignment and Scoped Lead Access (backend + Web production 2026-07-17; iOS implementation staged)

Lead responsibility is a nullable, single-user relationship on `public.opportunities.assigned_to` with an optimistic concurrency counter in `opportunities.assignment_version`. It does not create a project owner or project assignee. When a lead converts, the opportunity retains its assignee, while the resulting project and project tasks remain unassigned. Task assignees continue to be managed only through the task system.

### Permission contract

Lead permissions are independently scoped as `pipeline.create`, `pipeline.view`, `pipeline.edit`, `pipeline.assign`, and `pipeline.convert`. `view`, `edit`, `assign`, and `convert` accept `all | assigned`; `create` accepts `all`. Effective dependencies are enforced in both the permission editor and the database: edit cannot exceed view, and assign/convert cannot exceed edit. Explicit granular role rows or per-user overrides suppress legacy `pipeline.manage` compatibility, including explicit revocations and inert `granted=true, scope=NULL` override rows.

The reviewed Operator preset activates only after the complete assignment and email hardening chain. Its exact lead/mail matrix is:

- `pipeline.create:all`
- `pipeline.view:assigned`
- `pipeline.edit:assigned`
- `pipeline.assign:assigned`
- `pipeline.convert:assigned`
- `inbox.view:assigned`
- `inbox.send:assigned`

The activation replaced the legacy Operator `inbox.view:all` row, did not add `pipeline.manage` or `inbox.view_company`, and preserved unrelated Operator capabilities. `20260715180900_internal_spec_permission_guard.sql` ran after notification hardening and before activation. It waits out writers to `role_permissions`, `user_permission_overrides`, and `user_roles`; preserves only the canonical internal `SPEC Operator / spec.admin:all` role grant and the exact `OPS_OPERATIONS_COMPANY_ID / spec.admin:all / granted=true` override tuple; and makes those protected grants and SPEC-role membership immutable to generic permission and role-assignment writes. Any future SPEC grant or revocation requires a separately reviewed SPEC-only operation. `20260715181000_lead_assignment_operator_activation.sql` then acquired every affected company boundary before role/member rows and retained its retryable abort if the membership company set changes during the pre-lock gap. The complete 36-migration email, assignment, notification, project, and task chain through `20260715181700_opportunity_conversion_notification_delivery.sql` was applied to production on 2026-07-17 with exact canonical migration-history entries.

### Guarded writes and identity

All human assignment changes call `public.change_opportunity_assignment(opportunity_id, expected_assignment_version, expected_assigned_to, new_assigned_to, source, suggestion_id, metadata)`. Trusted ingestion and lifecycle workers call the service-role-only `public.change_opportunity_assignment_as_system(...)`. Direct writes to `opportunities.assigned_to` are rejected. Each successful change creates an immutable `opportunity_assignment_events` row and addressed `opportunity_assignment_deliveries` rows. If an assigned-only actor submits a stale write after another actor has already transferred the locked lead, the RPC raises the state-free `assignment_access_lost` outcome. Clients purge the revoked lead without receiving the replacement assignee; ordinary permission denials do not trigger that destructive path.

An assigned-scope actor can reassign an active, nonterminal lead currently assigned to them to another eligible team member. They cannot unassign it or change a terminal lead. An all-scope actor can assign, reassign, and unassign eligible leads according to the same guarded concurrency contract. Assignment targets must be active, nondeleted users in the same company with effective assigned-lead visibility.

Mailbox addresses never establish OPS identity. A personal connection is authorized only by its canonical OPS `email_connections.user_id` owner, and only when `type='individual'`; a company connection's legacy connector `user_id` is never treated as authority. Lead-linked reads and sends use the actor-aware `private.user_can_view_opportunity_inbox` and `private.user_can_send_opportunity_inbox` helpers, which intersect opportunity access, mailbox ownership/type, company, inbox scope, and current assignment.

### Product behavior

The production Web lead-detail surface displays the current assignee and exposes the guarded picker only when the current actor can change that row. The staged iOS implementation follows the same contract. Both clients send the assignment version and expected assignee, wait for the server response, and refresh on conflict; assignment is never optimistic or queued offline. Assigned-only users see their assigned leads in the Leads tab and do not receive a company-wide assignee filter or assignee column. Company-wide viewers can filter by Mine, Unassigned, or a specific eligible team member.

Assignment changes invalidate actor/scope-keyed lead and aggregate caches and are replayable through durable realtime events. Canonical role, role-permission, user-override, user-admin, and company-admin changes enqueue one recipient-only `user_permission_change_deliveries` row per user/transaction. An open web session synchronously clears lead and email caches and closes lead-backed surfaces before refreshing its permission store. The new assignee receives one deduplicated in-app notification (and push when enabled); the former assignee receives no user-facing notification and their now-inaccessible cached lead is purged. Manual self-assignment is silent. If a conversion succeeds but the actor cannot view the resulting project, the client treats it as committed success without exposing the project identity, navigating to it, or retrying conversion.

Primary implementation sources: `ops-web/supabase/migrations/20260715160000_lead_assignment_foundation.sql`, `20260715160500_lead_assignment_scoped_rls.sql`, `20260715160700_lead_assignment_child_scope.sql`, `20260715161500_lead_assignment_realtime_fanout.sql`, `20260715161600_lead_assignment_delivery_worker.sql`, `20260715180900_internal_spec_permission_guard.sql`, and `20260715181000_lead_assignment_operator_activation.sql`; `ops-web/src/lib/permissions/lead-access-policy.ts`; `ops-web/src/lib/api/services/lead-assignment-service.ts`; `ops-web/src/lib/hooks/use-lead-assignment.ts`; and the iOS lead assignment repository/detail-view integration under `ops-ios/OPS/`.

---

**End of Document**
