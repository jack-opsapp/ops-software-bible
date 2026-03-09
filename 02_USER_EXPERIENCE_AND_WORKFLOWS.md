# 02_USER_EXPERIENCE_AND_WORKFLOWS.md

## Document Purpose

This document maps the complete user experience of OPS, including screen-by-screen navigation, user journeys for each role, gesture patterns, and common workflows. It provides a comprehensive guide to how users interact with the app.

---

## Table of Contents

1. [Navigation Architecture](#navigation-architecture)
2. [Onboarding Flows](#onboarding-flows)
3. [Tutorial System](#tutorial-system)
4. [User Journey Maps](#user-journey-maps)
5. [Screen Catalog](#screen-catalog)
6. [Gesture Patterns](#gesture-patterns)
7. [Common Workflows](#common-workflows)
8. [Role-Based UI Differences](#role-based-ui-differences)

---

## Navigation Architecture

### Tab Bar Navigation (Primary)

The app uses a **dynamic bottom tab bar** whose tabs vary based on user permissions. The tab bar is rendered by `CustomTabBar` (in `Views/Components/Common/CustomTabBar.swift`) and configured dynamically in `MainTabView.swift`.

**Tab Bar Configurations:**

The tabs array is built dynamically at runtime. Visibility is driven by the RBAC permission system (see `03_DATA_ARCHITECTURE.md` > Permissions System Tables):

```
Minimum (all users):
┌──────┬────────┬──────────┬──────────┐
│ Home │  Board │ Schedule │ Settings │
└──────┴────────┴──────────┴──────────┘

With Pipeline permission (pipeline.view):
┌──────┬──────────┬────────┬──────────┬──────────┐
│ Home │ Pipeline │  Board │ Schedule │ Settings │
└──────┴──────────┴────────┴──────────┴──────────┘

With Inventory permission (inventory.view):
┌──────┬────────┬───────────┬──────────┬──────────┐
│ Home │  Board │ Inventory │ Schedule │ Settings │
└──────┴────────┴───────────┴──────────┴──────────┘

Maximum (Pipeline + Inventory):
┌──────┬──────────┬────────┬───────────┬──────────┬──────────┐
│ Home │ Pipeline │  Board │ Inventory │ Schedule │ Settings │
└──────┴──────────┴────────┴───────────┴──────────┴──────────┘
```

**Tab Items (in insertion order):**

1. **Home** (`house.fill` icon) — Always shown
   - Dashboard view
   - Quick access to recent projects
   - Today's schedule
   - Quick actions

2. **Pipeline** (`OPSStyle.Icons.pipelineChart` icon) — **Conditional**: shown if user has `pipeline.view` permission
   - CRM / sales pipeline
   - Segmented control: Pipeline | Estimates | Invoices | Accounting
   - Admin, Owner, and Office roles have this by default; Operator and Crew do not

3. **Job Board** (`briefcase.fill` icon) — Always shown (all roles have `job_board.view`)
   - Project organization by sections
   - Search and filter
   - Crew role: assigned projects only (scope = `assigned`)

4. **Inventory** (`shippingbox.fill` icon) — **Conditional**: shown if user has `inventory.view` permission
   - Material and supply tracking
   - Tag-based organization
   - Quantity management
   - Admin, Owner, and Office roles have this by default

5. **Schedule** (`calendar` icon) — Always shown
   - Week/Month views
   - Event management
   - Project list for selected date

6. **Settings** (`gearshape.fill` icon) — Always shown (always last tab)
   - User profile
   - Company settings (requires `settings.company` permission)
   - Subscription management (requires `settings.billing` permission)
   - PIN management
   - Tutorial access

**Legacy note**: The iOS app currently uses `specialPermissions.contains("pipeline")` and `inventoryAccess == true` for tab visibility. These are being migrated to `can("pipeline.view")` and `can("inventory.view")` as part of the permissions system rollout.

**Important:** There is no standalone Map tab. Map/navigation functionality is accessed from within Project Details ("Get Directions") and is not a top-level tab.

### Navigation Patterns

**Sheet Presentation:**
- Form sheets for create/edit (projects, tasks, clients)
- Detail views for full-screen context
- Dismissible via swipe down or cancel button

**Push Navigation:**
- Details views (project details, task details, client details)
- Hierarchical navigation with back button
- Breadcrumb trails for context

**Full-Screen Covers:**
- Onboarding flow (non-dismissible)
- Tutorial mode (dismissible after completion)
- Lockout screen (non-dismissible)
- Image gallery viewer

### Navigation Hierarchy

```
Root
├── Tab Bar (Main Container — dynamic tabs)
│   ├── Home Tab (always)
│   │   ├── Dashboard Screen
│   │   ├── → Project Details (push)
│   │   ├── → Task Details (push)
│   │   └── → Form Sheets (modal)
│   │
│   ├── Pipeline Tab (conditional — requires "pipeline" special permission)
│   │   ├── PipelineTabView (container with segmented control)
│   │   │   ├── PIPELINE segment → PipelineView
│   │   │   │   ├── Search bar
│   │   │   │   ├── Metrics strip (Deals, Weighted, Total)
│   │   │   │   ├── Stage filter strip
│   │   │   │   ├── Opportunity cards
│   │   │   │   ├── → OpportunityDetailView (push)
│   │   │   │   │   ├── Details / Activity / Follow-Ups tabs
│   │   │   │   │   ├── → OpportunityFormSheet (edit)
│   │   │   │   │   ├── → ActivityFormSheet (modal)
│   │   │   │   │   └── → MarkLostSheet (modal)
│   │   │   │   └── → OpportunityFormSheet (new lead, modal)
│   │   │   │
│   │   │   ├── ESTIMATES segment → EstimatesListView
│   │   │   │   ├── Search bar + filter chips (All, Draft, Sent, Approved)
│   │   │   │   ├── Estimate cards (swipe right to send/convert)
│   │   │   │   ├── → EstimateDetailView (push)
│   │   │   │   └── → EstimateFormSheet (modal, FAB)
│   │   │   │
│   │   │   ├── INVOICES segment → InvoicesListView
│   │   │   │   ├── Filter chips (All, Unpaid, Overdue, Paid) + search
│   │   │   │   ├── Invoice cards (swipe right → record payment, swipe left → void)
│   │   │   │   ├── → InvoiceDetailView (push)
│   │   │   │   └── → PaymentRecordSheet (modal)
│   │   │   │
│   │   │   └── ACCOUNTING segment → AccountingDashboard
│   │   │       ├── AR Aging bar chart (0-30d, 31-60d, 61-90d, 90d+)
│   │   │       ├── Invoice Status tiles (Awaiting, Overdue, Paid, Outstanding)
│   │   │       └── Top Outstanding clients list
│   │   │
│   │   └── (Pipeline tab has its own FAB, main FAB is hidden)
│   │
│   ├── Job Board Tab (always — all user roles)
│   │   ├── Board Screen (Admin/Office)
│   │   │   ├── Section Picker
│   │   │   ├── Search/Filter
│   │   │   ├── Job Cards
│   │   │   ├── → Project Details (push)
│   │   │   └── → Form Sheets (modal)
│   │   │
│   │   └── Dashboard Screen (Field Crew)
│   │       ├── Assigned Projects Only
│   │       ├── → Project Details (push)
│   │       └── No form sheets
│   │
│   ├── Inventory Tab (conditional — requires user.inventoryAccess == true)
│   │   ├── InventoryView
│   │   │   ├── Search bar + tag filter chips
│   │   │   ├── Sort modes (Tag, Name, Quantity, Threshold)
│   │   │   ├── Inventory item cards (pinch-to-zoom scalable)
│   │   │   │   ├── Selection mode (long press → bulk actions)
│   │   │   │   ├── → InventoryFormSheet (edit, modal)
│   │   │   │   └── → QuantityAdjustmentSheet (modal)
│   │   │   ├── → InventoryFormSheet (new item, modal via FAB)
│   │   │   ├── → SpreadsheetImportSheet (import items)
│   │   │   ├── → SnapshotListView (view snapshots)
│   │   │   ├── → BulkQuantityAdjustmentSheet (bulk adjust)
│   │   │   ├── → BulkTagsSheet (bulk tag)
│   │   │   └── → InventoryManageTagsSheet (manage tags)
│   │
│   ├── Schedule Tab (always — renamed from "Calendar")
│   │   ├── Schedule Screen (ScheduleView)
│   │   │   ├── Day selector / month toggle (CalendarDaySelector)
│   │   │   │   ├── Week strip: WeekDayCell rows with density bars
│   │   │   │   └── Month grid: MonthGridView (pinch-to-collapse)
│   │   │   ├── Day canvas pager (DayCanvasView — horizontal 3-page TabView)
│   │   │   │   ├── DayPageView: "New" tasks + "Ongoing" tasks + CalendarUserEventCards
│   │   │   │   └── Swipe left/right → navigate days (infinite scroll pattern)
│   │   │   ├── → Project Details (via task card tap)
│   │   │   ├── → Task Details (via task card tap)
│   │   │   ├── → PersonalEventSheet (FAB → "Personal Event")
│   │   │   ├── → TimeOffRequestSheet (FAB → "Request Time Off")
│   │   │   └── → CalendarFilterView (modal, filter button)
│   │
│   └── Settings Tab (always — always last tab)
│       ├── Settings Screen
│       │   ├── User Profile
│       │   ├── Company Settings (Admin)
│       │   ├── PIN Management
│       │   ├── Tutorial Access
│       │   └── Logout
│       │
│       ├── → Profile Edit (push)
│       ├── → Company Edit (push, Admin)
│       ├── → PIN Setup (modal)
│       └── → Tutorial (fullscreen)
│
├── Onboarding (fullscreen, first launch)
│   ├── Welcome
│   ├── Signup
│   ├── Credentials
│   ├── Profile
│   ├── Company Setup / Code Entry
│   ├── Ready
│   └── Tutorial
│
├── Floating Action Buttons (contextual — hidden on Settings and Pipeline tabs)
│   ├── + New Project (Home, Board)
│   ├── + New Task (Project Details)
│   ├── + New Client (Clients List)
│   └── Photo Camera (Project Details)
│
├── Notification List (modal — accessed from AppHeader bell icon)
│   ├── Unread/read notification rows
│   ├── "Mark All Read" button
│   └── → Deep link to Project Details (tap notification with projectId)
│
├── Photo Annotation (fullscreen modal — accessed from project photo gallery)
│   ├── Full-screen photo display
│   ├── PencilKit drawing canvas (editing mode)
│   ├── Undo/Clear drawing controls
│   └── Note text field
│
└── Project Notes (embedded within Project Details)
    ├── Notes list (ProjectNoteRow cards with author, timestamp, @mention highlighting)
    ├── Mention suggestion bar (@mention autocomplete)
    └── Compose bar (text input + send button)
```

---

## Onboarding Flows

### Company Creator Flow (Owner/Admin)

Presented on first launch when user has no account.

**Step 1: Welcome Screen**
- **UI Elements:**
  - OPS logo
  - Tagline: "Job Management for Trades"
  - "Get Started" button
  - "Already have an account? Sign In" text button
- **Actions:**
  - Tap "Get Started" → Step 2

**Step 2: Signup Method Selection**
- **UI Elements:**
  - "Create Your Account" title
  - Google Sign-In button (with Google logo)
  - Apple Sign-In button (with Apple logo)
  - "Or use email" divider
  - Email/Password form fields
  - "Continue" button
  - "Already have an account? Sign In" text button
- **Actions:**
  - Tap Google → Google OAuth flow → Step 3
  - Tap Apple → Apple OAuth flow → Step 3
  - Enter email/password + Tap Continue → Step 3

**Step 3: Profile Setup**
- **UI Elements:**
  - "Tell us about yourself" title
  - First name text field
  - Last name text field
  - Phone number text field (optional)
  - "Continue" button
- **Actions:**
  - Fill fields + Tap Continue → Step 4

**Step 4: Company Setup**
- **UI Elements:**
  - "Create Your Company" title
  - Company name text field
  - "Continue" button
- **Actions:**
  - Enter company name + Tap Continue → Step 5

**Step 5: Company Details**
- **UI Elements:**
  - "Tell us about your company" title
  - Industry picker (dropdown)
  - Crew size picker (dropdown: 1-3, 4-5, 6-10, 11+)
  - "Continue" button
- **Actions:**
  - Select options + Tap Continue → Step 6

**Step 6: Company Code Display**
- **UI Elements:**
  - "Your Company Code" title
  - Large display of 6-character code (e.g., "ABC123")
  - "Share this code with your employees so they can join your company"
  - Copy to clipboard button
  - Share button (iOS share sheet)
  - "Continue" button
- **Actions:**
  - Copy/share code for later use
  - Tap Continue → Step 7

**Step 7: Ready Screen**
- **UI Elements:**
  - "You're All Set!" title
  - "Start managing your projects" subtitle
  - "Start Tutorial" button
  - "Skip Tutorial" text button
- **Actions:**
  - Tap Start Tutorial → Tutorial Mode
  - Tap Skip Tutorial → Home Screen (tutorial accessible later)

### Employee Flow (Field Crew, Office Crew)

Presented when user joins via company code.

**Steps 1-3:** Same as Company Creator (Welcome, Signup, Profile)

**Step 4: Company Code Entry**
- **UI Elements:**
  - "Join a Company" title
  - "Enter the 6-character code provided by your company administrator"
  - 6-character code input field (auto-uppercase, formatted)
  - "Join" button
  - "Don't have a code? Contact your administrator" help text
- **Actions:**
  - Enter code + Tap Join → Validates code with server
  - If valid → Step 5
  - If invalid → Error message "Invalid code. Please check and try again."

**Step 5: Ready Screen**
- Same as Company Creator Step 7

### Sign-In Flow (Returning Users)

**Sign-In Screen:**
- **UI Elements:**
  - OPS logo
  - "Welcome Back" title
  - Google Sign-In button
  - Apple Sign-In button
  - Email/Password fields
  - "Sign In" button
  - "Forgot password?" text button
  - "Don't have an account? Get Started" text button
- **Actions:**
  - Sign in with saved credentials → PIN Entry → Home Screen
  - Or full OAuth flow → PIN Entry → Home Screen

### PIN Entry (Returning Users)

Shown after sign-in or app relaunch if PIN is set.

**PIN Entry Screen:**
- **UI Elements:**
  - "Enter PIN" title
  - 4 circle indicators (empty → filled as digits entered)
  - Number pad (0-9)
  - "Forgot PIN?" text button
- **Actions:**
  - Enter 4 digits → Auto-validates
  - If correct → Home Screen
  - If incorrect → Shake animation + "Incorrect PIN. Try again."
  - Tap Forgot PIN → Logout + Re-authentication required

---

## Tutorial System

### 25-Phase Interactive Tutorial

The tutorial is a **fully interactive, hands-on guide** that walks users through the app using demo data. It's not a passive video or slideshow—users actually perform actions in a sandboxed environment.

### Tutorial Manager Architecture

**TutorialManager:**
- Tracks current phase (0-24)
- Manages demo data injection
- Controls tutorial overlays
- Persists progress
- Can be paused/resumed/restarted

**Demo Data:**
- Pre-populated company, projects, tasks, clients
- Safe environment (changes don't sync to production)
- Realistic data for context
- Deleted after tutorial completion or skip

### Tutorial Phases

**Phase 0: Welcome**
- Overlay: "Welcome to OPS! Let's take a quick tour."
- Action: Tap "Start Tour"

**Phase 1: Home Screen Overview**
- Overlay: "This is your Home screen. See today's schedule and recent projects here."
- Highlight: Home tab
- Action: Tap "Next"

**Phase 2: Job Board Introduction**
- Overlay: "The Job Board organizes your projects. Let's explore it."
- Highlight: Job Board tab
- Action: Tap Job Board tab

**Phase 3: Job Board Sections**
- Overlay: "Organize projects by sections like Unscheduled, This Week, etc."
- Highlight: Section picker
- Action: Tap section picker, select "This Week"

**Phase 4: Project Card Tap**
- Overlay: "Tap any project to view details."
- Highlight: First project card
- Action: Tap project card

**Phase 5: Project Details Overview**
- Overlay: "Here's everything about this project—client, location, tasks, photos."
- Highlight: Entire screen
- Action: Tap "Next"

**Phase 6: Task List**
- Overlay: "Tasks break down the project into steps. Tap a task to see details."
- Highlight: Task list section
- Action: Tap first task

**Phase 7: Task Details Overview**
- Overlay: "Task details show status, schedule, and assigned crew."
- Highlight: Entire screen
- Action: Tap "Back" to return to project

**Phase 8: Status Change Gesture**
- Overlay: "Swipe left/right on a task to change its status quickly."
- Highlight: Task row
- Action: Swipe task row → Status changes

**Phase 9: Get Directions**
- Overlay: "Tap 'Get Directions' to navigate to the job site."
- Highlight: Location card "Get Directions" button
- Action: Tap button

**Phase 10: Navigation Preview**
- Overlay: "Turn-by-turn navigation helps you reach the site. It works offline!"
- Highlight: Navigation view
- Action: Tap "End Navigation" to return

**Phase 11: Schedule Tab**
- Overlay: "Let's check the Schedule to see your upcoming work."
- Highlight: Schedule tab
- Action: Tap Schedule tab

**Phase 12: Schedule Day Canvas**
- Overlay: "Swipe left or right to move between days and see what's scheduled."
- Highlight: DayCanvasView pager
- Action: Swipe to next day

**Phase 13: Schedule Event Tap**
- Overlay: "Tap any task card to view its details."
- Highlight: CalendarEventCard
- Action: Tap card → Goes to task details

**Phase 14-15: (Map phases — removed)**
- Map is no longer a standalone tab. Navigation is accessed from within Project Details via "Get Directions."

**Phase 16: Settings Tab**
- Overlay: "Settings let you manage your profile and preferences."
- Highlight: Settings tab
- Action: Tap Settings tab

**Phase 17: PIN Setup**
- Overlay: "Set a PIN to secure your data."
- Highlight: PIN management row
- Action: Tap row → Goes to PIN setup

**Phase 18: Create Project (Admin/Office Only)**
- Overlay: "Let's create a new project. Tap the '+' button."
- Highlight: Floating action button
- Action: Tap FAB → Opens project form sheet

**Phase 19: Project Form Fields**
- Overlay: "Fill in project details—title, client, location, status."
- Highlight: Form fields
- Action: Fill fields

**Phase 20: Save Project**
- Overlay: "Tap 'Save' to create the project."
- Highlight: Save button
- Action: Tap Save → Project created

**Phase 21: Add Task to Project**
- Overlay: "Now add a task to the project. Tap 'Add Task'."
- Highlight: Add Task button in project details
- Action: Tap button → Opens task form sheet

**Phase 22: Task Form Fields**
- Overlay: "Select task type, assign crew, and schedule dates."
- Highlight: Form fields
- Action: Fill fields

**Phase 23: Save Task**
- Overlay: "Tap 'Save' to add the task."
- Highlight: Save button
- Action: Tap Save → Task created

**Phase 24: Tutorial Complete**
- Overlay: "Great job! You're ready to use OPS. All demo data will be cleared."
- Action: Tap "Finish" → Demo data deleted → Home screen

### Tutorial Controls

**Pause/Resume:**
- Tutorial can be paused at any time via Settings
- Progress saved, resumes from last phase

**Skip:**
- "Skip Tutorial" button available at any phase
- Confirmation dialog: "Are you sure? You can access the tutorial later from Settings."
- If confirmed: Demo data deleted, go to Home

**Restart:**
- Available in Settings → "Restart Tutorial"
- Clears progress, starts from Phase 0

---

## User Journey Maps

### Admin Journey: Creating a Scheduled Project

**Goal:** Create a new project, add tasks, assign crew, and schedule work.

**Steps:**

1. **Start Point:** Home screen
2. **Action:** Tap floating action button (+)
3. **Transition:** Project form sheet opens
4. **Action:** Enter project title "Install Deck Railing"
5. **Action:** Tap "Select Client" → Search "John Smith" → Select
6. **Action:** Tap "Add Location" → Enter address "123 Main St" → Confirm
7. **Action:** Tap "Status" → Select "Accepted"
8. **Action:** Tap "Save"
9. **Transition:** Form closes, project list refreshes, new project appears
10. **Action:** Tap new project card
11. **Transition:** Project details view opens
12. **Action:** Tap "Add Task" button
13. **Transition:** Task form sheet opens
14. **Action:** Tap "Task Type" → Select "Installation"
15. **Action:** Tap "Assign Team" → Select "Bob (Field Crew)" and "Alice (Field Crew)"
16. **Action:** Tap "Schedule" → Select start date (tomorrow) and end date (tomorrow)
17. **Action:** Tap "Save"
18. **Transition:** Form closes, task appears in project task list
19. **Verification:** Check Schedule tab → Event appears on tomorrow's date
20. **End Point:** Project created, task scheduled, crew assigned

**Time to Complete:** ~2 minutes

**Pain Points Addressed:**
- Quick inline client selection (no leaving form)
- Address autocomplete (no typing full address)
- Single-form task creation (no multi-step wizard)
- Automatic calendar event creation (no separate step)

### Office Crew Journey: Scheduling Next Week's Jobs

**Goal:** Review unscheduled projects and assign to field crew for next week.

**Steps:**

1. **Start Point:** Job Board screen
2. **Action:** Tap section picker → Select "Unscheduled"
3. **View:** See list of projects with no scheduled tasks
4. **Action:** Tap first unscheduled project
5. **Transition:** Project details view opens
6. **Action:** Scroll to tasks section
7. **Observation:** Tasks exist but have no calendar events (red "Unscheduled" badge)
8. **Action:** Tap first task
9. **Transition:** Task details view opens
10. **Action:** Tap "Schedule" row (dates section)
11. **Transition:** Calendar event form sheet opens
12. **Action:** Select start date (next Monday)
13. **Action:** Select end date (next Monday)
14. **Action:** Tap "Assign Team" → Select field crew members
15. **Action:** Tap "Save"
16. **Transition:** Form closes, dates appear in task details
17. **Action:** Navigate back to project details
18. **Observation:** Task now shows scheduled dates, no longer unscheduled
19. **Action:** Repeat for remaining tasks in project
20. **Verification:** Return to Job Board → Project moved from "Unscheduled" to "Next Week"
21. **End Point:** All tasks scheduled, crew assigned

**Time to Complete:** ~1 minute per project

**Pain Points Addressed:**
- Clear visual indicator of unscheduled projects (badge)
- Section filtering makes unscheduled projects easy to find
- Quick scheduling from task details (no multi-step process)

### Field Crew Journey: Completing a Task

**Goal:** Navigate to job site, mark task as in progress, complete work, upload photos, mark as completed.

**Steps:**

1. **Start Point:** Job Board screen (dashboard view)
2. **View:** See only assigned projects
3. **Action:** Tap today's project
4. **Transition:** Project details view opens
5. **Action:** Tap "Get Directions"
6. **Transition:** Navigation view launches
7. **Navigation:** Follow turn-by-turn directions to site
8. **Action:** Tap "End Navigation" upon arrival
9. **Transition:** Return to project details
10. **Action:** Scroll to tasks section
11. **Action:** Swipe right on task row
12. **Feedback:** Haptic vibration
13. **State Change:** Task status changes to "In Progress" (orange badge)
14. **Work:** Perform physical work on site
15. **Action:** Tap "Add Photos" button
16. **Transition:** Camera opens
17. **Action:** Capture 3 photos of completed work
18. **Transition:** Return to project details
19. **Observation:** Photos appear in gallery (local, not yet synced)
20. **Action:** Swipe right on task row again
21. **Feedback:** Haptic vibration
22. **State Change:** Task status changes to "Completed" (green badge)
23. **Background:** When connectivity available, photos upload to S3 automatically
24. **End Point:** Task completed, photos uploaded, office notified

**Time to Complete:** ~5 minutes (excluding actual work)

**Pain Points Addressed:**
- One-tap navigation (no leaving app)
- Swipe gesture for status changes (no opening forms)
- In-app camera (no switching apps)
- Automatic photo upload (no manual sync)
- Works offline (no blocking on connectivity)

---

### Pipeline Journey: Lead to Invoice

**Goal:** Track a new lead through the pipeline from initial contact to invoice and payment.

**Prerequisites:** User must have `"pipeline"` in specialPermissions.

**Steps:**

1. **Start Point:** Pipeline tab → PIPELINE segment
2. **Action:** Tap FAB (+) → OpportunityFormSheet opens
3. **Action:** Enter contact name, phone, email, job description, estimated value, source
4. **Action:** Tap "CREATE"
5. **Transition:** New opportunity appears in NEW LEAD stage
6. **Action:** Work the lead — log activities via OpportunityDetailView → Activity tab
7. **Action:** Swipe right on opportunity card to advance through stages:
   - NEW LEAD → QUALIFYING → QUOTING → QUOTED → FOLLOW-UP → NEGOTIATION → WON
8. **Branch (Lost):** Swipe left → MarkLostSheet → enter loss reason → opportunity moves to LOST
9. **Action (at QUOTING stage):** Switch to ESTIMATES segment → Tap FAB → EstimateFormSheet
10. **Action:** Create estimate with line items, associate with client
11. **Action:** Swipe right on draft estimate card → Estimate status changes to SENT
12. **Transition:** Client reviews estimate externally
13. **Action:** When client approves, update estimate status to APPROVED
14. **Action:** Swipe right on approved estimate → Confirmation dialog → "Convert to Invoice"
15. **Transition:** Invoice created from estimate, appears in INVOICES segment
16. **Action:** Switch to INVOICES segment → invoice visible with UNPAID status
17. **Action:** When payment received, swipe right on invoice card → PaymentRecordSheet
18. **Action:** Record payment amount → invoice moves to PAID
19. **Verification:** Switch to ACCOUNTING segment → see updated AR aging, status tiles, and outstanding balances
20. **End Point:** Lead converted to revenue, fully tracked from first contact to payment

**Time to Complete:** Minutes for data entry (days/weeks in real elapsed time)

**Pain Points Addressed:**
- Single tab houses entire sales-to-cash workflow (no switching between apps)
- Swipe gestures for stage advancement (fast, one-handed)
- Estimate-to-invoice conversion is a single swipe action
- Accounting dashboard provides at-a-glance financial health

---

### Inventory Journey: Track Materials and Supplies

**Goal:** Manage inventory items, track quantities, organize with tags, and create snapshots.

**Prerequisites:** User must have `inventoryAccess == true`.

**Steps:**

1. **Start Point:** Inventory tab → InventoryView
2. **Action:** Tap FAB (+) → InventoryFormSheet opens
3. **Action:** Enter item name, SKU, description, unit, initial quantity, threshold values
4. **Action:** Tap "Save" → Item appears in inventory list
5. **Action:** Apply tags to organize — tap item → InventoryFormSheet → add tag names
6. **Observation:** Items grouped/sorted by tag when sort mode is TAG
7. **Action:** Tap item card → QuantityAdjustmentSheet → adjust quantity up or down
8. **Observation:** Threshold badges appear on cards:
   - Items at/below low threshold show warning badge
   - Items at zero show critical/out badge
9. **Action (Bulk operations):** Long press item → "Select" → enters selection mode
10. **Action:** Select multiple items (tap cards, or use tag/keyword selection filter)
11. **Action:** Tap bulk action: Adjust Quantity, Adjust Tags, or Delete
12. **Action (Import):** Tap import button → SpreadsheetImportSheet → select file → map columns → import items
13. **Action (Snapshots):** Access SnapshotListView to view historical inventory snapshots (automatic and manual)
14. **End Point:** Inventory organized, quantities tracked, thresholds alerting

**Time to Complete:** ~1 minute per item, seconds for quantity adjustments

**Gestures:**
- Pinch-to-zoom on inventory list to scale card size (0.8x-1.5x, persisted)
- Long press for context menu (Select, Edit, Delete)
- Tap for quick quantity adjustment

**Pain Points Addressed:**
- Pinch-to-zoom lets users see more items at a glance or zoom in for detail
- Bulk operations save time for large inventories
- Tag-based organization flexible enough for any trade
- Threshold badges provide visual early warning for low stock
- Spreadsheet import for migrating existing inventory data

---

## Screen Catalog

### Home Screen

**Purpose:** Dashboard overview of today's work and recent activity.

**UI Elements:**
- **Today's Date** - Large header with current date
- **Today's Schedule** - List of calendar events for today
  - Task title
  - Project name
  - Time range (if specified)
  - Assigned crew avatars
- **Recent Projects** - Last 5 viewed/edited projects
  - Project card with title, client, status badge
- **Quick Actions** - Floating action button (+)
  - New Project
  - New Client
- **Tab Bar** - Bottom navigation

**Actions:**
- Tap calendar event → Task details
- Tap recent project → Project details
- Tap FAB → Project form sheet
- Pull to refresh → Sync data

**Role Differences:**
- Admin/Office: See all today's events
- Field Crew: See only assigned events

---

### Job Board Screen (Redesigned March 2026)

**Purpose:** Role-based operational hub for managing projects, tasks, and pipeline.

The Job Board uses a **role-based section system**. Each role sees a different set of sections and a different default view.

---

#### Role: Field Crew

**Default section:** My Tasks
**Available sections:** My Tasks, My Projects
**Section picker:** Hidden — field crew cannot switch sections manually

**My Tasks Section:**
- Shows only tasks with an **explicit assignment** to the current user (`task.getTeamMemberIds().contains(userId)`)
- Tasks from projects where the user has no explicit task assignment are NOT shown
- Filter chips: `[ ALL ]` `[ TODAY ]` `[ UPCOMING ]` `[ COMPLETED ]`
- Tasks grouped by project, collapsible per group
- Empty state: "No tasks assigned to you" (ALL filter) / "No [FILTER] tasks" (other filters)

**My Projects Section:**
- Shows only projects where the user is a team member
- Swipe-to-change-status on project cards
- No create/edit permissions — read and status update only

**Actions (Field Crew):**
- Tap task card → Task details
- Swipe card → Change status
- Tap project → Project details
- Search button (header) → Universal Search Sheet (pipeline content hidden)

---

#### Role: Office Crew

**Default section:** Projects
**Available sections:** Projects, Tasks, Kanban
**Section picker:** Horizontal pill selector at top of screen

**Projects Section:**
- All company projects, sorted by scheduled date or status
- Filter by: status set, team member IDs, search text
- Closed/archived projects in a separate collapsible section (sheet presentation)
- Swipe-to-change-status on project cards

**Tasks Section:**
- All company tasks across all projects
- Filter by: status, task type, team member
- Split into active / completed / cancelled groups

**Kanban Section:**
- Proportional fill bars showing project count across 5 statuses:
  - RFQ → Estimated → Accepted → In Progress → Completed
- Fill width is proportional to count / total (excluding Closed)
- Tap a bar → expands inline to show project cards for that status

**Actions (Office Crew):**
- Tap section pill → Switch section
- Search button (header) → Universal Search Sheet (no pipeline content)
- FAB → Create project / task (context-dependent)
- Swipe card → Change status
- Filter button → Filter sheet

---

#### Role: Admin

**Default section:** Projects
**Available sections:** Projects, Tasks, Kanban + Pipeline (if `specialPermissions.contains("pipeline")`)
**Section picker:** Horizontal pill selector

Same as Office Crew plus:

**Pipeline Section** *(requires `specialPermissions.contains("pipeline")`):*
- CRM pipeline for managing deals/opportunities
- Stage transitions, activity timeline, follow-up reminders
- Access controlled via `User.specialPermissions: [String]` containing `"pipeline"`

**Actions (Admin):**
- Same as Office Crew
- Pipeline section only visible if user has the `"pipeline"` special permission

---

#### Universal Search Sheet

Opened from the search button in the header (`AppState.showingJobBoardSearch = true`).

- Full-screen modal with auto-focused keyboard
- Searches: project title, client name, address; task `displayTitle`, `taskNotes`
- Results in pinned sections: `[ PROJECTS ]`, `[ TASKS ]`
- **Role filtering:**
  - Field crew: only sees their assigned projects/tasks
  - Non-pipeline users: RFQ and Estimated projects are hidden from results
  - Pipeline users (`specialPermissions.contains("pipeline")`): all projects visible

---

### Project Details Screen

**Purpose:** Comprehensive view of a single project with all related data.

**UI Structure (Top to Bottom):**

1. **Header**
   - Color stripe (status-dependent)
   - Status badge (top right)
   - Breadcrumb: Company → Client → Project
   - Project title (large)
   - Floating action buttons (Edit, Delete)

2. **Location Card**
   - Map icon
   - "LOCATION" section header
   - Address text
   - "Get Directions" button (primary accent)

3. **Client Info Card**
   - Person icon
   - "CLIENT" section header
   - Client name
   - Email (tap to email)
   - Phone (tap to call)
   - Address (tap to map)

4. **Notes Card** (iOS) / **Notes Tab** (OPS Web)
   - **iOS:** Note icon, "NOTES" section header, Notes text (expandable), "Show more" / "Show less" toggle
   - **OPS Web (Feb 2026 overhaul):** Full threaded notes tab with NoteComposer (text input with @mention autocomplete, Ctrl+Enter submit), NotesList (list of NoteCards with author avatar, time-ago, @mention rendering, photo grid, edit/delete dropdown), legacy migration from Bubble teamNotes on first visit. Notes are project-level only (task-level notes removed). See [07_SPECIALIZED_FEATURES.md](07_SPECIALIZED_FEATURES.md) Section 11 for full details.

5. **Description Card**
   - Document icon
   - "DESCRIPTION" section header
   - Description text (expandable)

6. **Team Members Card**
   - People icon
   - "TEAM MEMBERS" section header
   - Avatar row with names
   - "+Add" button (Admin/Office)

7. **Tasks Section**
   - Checklist icon
   - "TASKS" section header
   - Task list grouped by status:
     - Booked (blue)
     - In Progress (orange)
     - Completed (green)
     - Cancelled (gray)
   - Each task shows:
     - Task type icon
     - Task title
     - Scheduled dates
     - Team avatars
     - Swipeable for status change
   - "Add Task" button (Admin/Office)

8. **Images Section**
   - Camera icon
   - "IMAGES" section header
   - Photo grid (3 columns)
   - Full-screen viewer on tap
   - "Add Photos" button

9. **Previous/Next Navigation Cards**
   - "Previous Project" card (if exists)
   - "Next Project" card (if exists)

**Actions:**
- Tap Edit → Project form sheet
- Tap Delete → Confirmation dialog → Soft delete
- Tap Get Directions → Navigation view
- Tap email/phone → iOS native actions
- Tap team member → User profile (future)
- Tap task → Task details
- Swipe task → Change status (Field Crew only for assigned tasks)
- Tap Add Task → Task form sheet (Admin/Office)
- Tap Add Photos → Camera or photo library
- Tap Previous/Next → Navigate to adjacent project

**Role Differences:**
- Admin/Office: Edit, delete, add tasks, add photos, assign team
- Field Crew: View only (except status changes for assigned tasks)

---

### Task Details Screen

**Purpose:** Detailed view of a single task with scheduling and status.

**UI Structure (Top to Bottom):**

1. **Header**
   - Color stripe (task type color)
   - Status badge (top right)
   - Breadcrumb: Company → Client → Project → Task
   - Task title (large)
   - Floating action buttons (Edit, Delete) - Admin/Office only

2. **Dates Section**
   - Calendar icon
   - "SCHEDULED DATES" section header
   - Start date
   - End date
   - Duration (X days)
   - Chevron (Admin/Office only)

3. **Location Card**
   - Map icon
   - "LOCATION" section header
   - Project address
   - "Get Directions" button

4. **Client Info Card**
   - Person icon
   - "CLIENT" section header
   - Client name
   - Email (tap to email)
   - Phone (tap to call)

5. **Notes Card**
   - Note icon
   - "NOTES" section header
   - Task notes text (expandable)

6. **Team Members Card**
   - People icon
   - "TEAM MEMBERS" section header
   - Avatar row with names
   - "+Add" button (Admin/Office)

7. **Previous/Next Navigation Cards**
   - "Previous Task" card (if exists in project)
   - "Next Task" card (if exists in project)

**Actions:**
- Tap Edit → Task form sheet (Admin/Office)
- Tap Delete → Confirmation dialog → Soft delete (Admin/Office)
- Tap Dates section → Calendar event form (Admin/Office)
- Tap Get Directions → Navigation view
- Tap email/phone → iOS native actions
- Tap Previous/Next → Navigate to adjacent task

**Role Differences:**
- Admin/Office: Edit, delete, schedule, assign team
- Field Crew: View only, dates section not tappable

---

### Schedule Screen (ScheduleView)

**Purpose:** View and manage scheduled work across time. Formerly called "Calendar"; the tab and view are now named "Schedule."

**Updated:** 2026-03-02 — Full redesign replacing `CalendarToggleView` + `ProjectListView` with `DayCanvasView` + `CalendarDaySelector`.

**UI Elements:**

1. **AppHeader** (Top)
   - Schedule header type
   - Month icon button → tapping calls `viewModel.toggleMonthExpanded()` to show/hide the full month grid
   - Filter button → opens CalendarFilterView (badge shows active filter count)

2. **CalendarDaySelector** (Week strip + Month grid)
   - **Week strip** (default): horizontal row of `WeekDayCell`s showing day abbreviation, day number, and up to 4 colored density bars (one per task color). If >4 tasks exist on a day, the fourth bar is replaced by `···`.
   - **Month grid** (`isMonthExpanded == true`): `MonthGridView` expands via `matchedGeometryEffect` hero animation. Pinch gesture collapses back to week strip.
   - Selecting any date updates `viewModel.selectedDate` and the day canvas snaps to that date.

3. **DayCanvasView** (Horizontal day pager)
   - A 3-page `TabView` with pages `[selectedDate - 1 day, selectedDate, selectedDate + 1 day]`.
   - Swiping left or right advances/retreats `selectedDate` by one day; `pageIndex` snaps back to 1 via a 50ms `DispatchQueue` delay guarded by `isSnappingBack` to prevent loops.
   - Each page is a `DayPageView` containing:
     - **Day header**: day of week, date string, and task count badge
     - **"New" tasks section**: tasks whose `startDate` falls on this day, shown as `CalendarEventCard` rows with staggered entry animation
     - **"Ongoing" tasks section**: tasks that started before this day but are still active, separated by a divider
     - **`CalendarUserEventCard` rows**: personal events and time-off requests for the day
     - **Empty state**: shown when no tasks or events exist for the day

4. **CalendarEventCard**
   - Displays a single task. Has `DayPosition` variants: `.single`, `.start`, `.middle`, `.end` — used to visually indicate multi-day task spans with connecting edges.

5. **CalendarUserEventCard**
   - Displays a personal event or time-off request. Shows type badge (Personal / Time Off) and status for time-off items. Supports swipe-to-delete.

**Sheets:**
- **PersonalEventSheet**: bottom sheet for creating a personal calendar event (title, date, all-day toggle, notes)
- **TimeOffRequestSheet**: bottom sheet for submitting a time off request (title, start/end date, notes). Uses amber color scheme. Keyboard-safe via `ScrollView` wrapper. Creates a `CalendarUserEvent` with `type: .timeOff`, `status: .pending`, and syncs immediately to Supabase.
- **CalendarFilterView**: filter by team member

**Actions:**
- Swipe day canvas left → advance to next day
- Swipe day canvas right → retreat to previous day
- Tap day in week strip → jump to that date
- Tap month icon in header → toggle month grid expansion
- Pinch month grid → collapse to week strip
- Tap task card → Task Details
- Tap filter → CalendarFilterView
- FAB → "Personal Event" (all roles) or "Request Time Off" (all roles); admin/office additionally see task/project create items

**Role Differences:**
- Admin/Office: See all events; FAB shows full menu (New Task Type, Create Task, Create Project, Create Client, New Estimate, New Lead, Add Expense, Personal Event, Request Time Off)
- Field Crew: See only assigned task events; FAB is now visible and shows only "Personal Event" and "Request Time Off"

---

### Web Calendar (OPS-Web)

**Purpose:** Full-featured scheduling command center for desktop and tablet browsers. 18-component modular architecture replacing the original monolithic calendar page.

**Added:** 2026-03-02 — Complete 4-phase rebuild.

**Three-Panel Desktop Layout:**
```
┌──────────┬─────────────────────────────┬──────────┐
│ Filter   │                             │ Detail   │
│ Sidebar  │     Calendar Grid           │ Panel    │
│ (260px)  │     (flexible)              │ (400px)  │
│          │                             │          │
│ Filters  │  [Month|Week|Day|Team|Agenda]│ Event   │
│ + Unsched│                             │ details  │
│ Tasks    │                             │ + edit   │
└──────────┴─────────────────────────────┴──────────┘
```

**UI Elements:**

1. **CalendarHeader** — Date navigation (prev/next, Today), view switcher (Month|Week|Day|Team|Agenda), filter toggle with active count badge. View switcher and filter button hidden on mobile.

2. **CalendarToolbar** — Event count, task type color legend, active filter chips. Legend hidden on mobile.

3. **FilterSidebar** (left, 260px, collapsible) — Four filter sections (Team Members with avatars, Task Types with color dots, Projects with search, Status: upcoming/in-progress/past), each collapsible. Includes UnscheduledPanel at bottom. Clear All button. Hidden on mobile.

4. **Calendar Grid** (center, 5 views):
   - **Month**: traditional grid, event indicators, click date → Day view
   - **Week**: 7-column hourly time grid (56px gutter), today highlight, auto-scroll to current hour
   - **Day**: single-column hourly time grid, full event detail
   - **Team**: Gantt-style rows per crew member (56px height, 180px name gutter, 80px/hour), availability heatmap (workload opacity), unassigned row
   - **Agenda**: chronological list grouped by date, sticky headers, 14-day window (mobile default)

5. **EventBlock** (draggable + resizable) — @dnd-kit `useDraggable`, bottom-edge resize (6px, 15-min snap), visual states: normal / hover / selected (blue ring) / dragging (ghost) / conflict (red glow). Shows time, title, project, team.

6. **EventDetailPanel** (right Sheet) — Opens on click/Enter. Editable: title, start/end datetime, project link, type badge, team chips. Save + Delete actions.

7. **EventQuickCreate** (Popover) — Opens on empty slot click, range drag, or keyboard C. Fields: title, datetime range, project search, task type.

8. **EventContextMenu** — Right-click: Edit, Duplicate, Delete. Keyboard-navigable.

**Drag-and-Drop:**
- `CalendarDndContext` wraps all grid content with `@dnd-kit/core`
- `PointerSensor` with `distance: 8` activation
- Ghost overlay with real-time time labels during drag
- 15-minute snap grid via `snapToGrid()`
- Axis-aware: Y-axis for week/day (`delta.y / 60px`), X-axis for team (`delta.x / 80px`)
- Unscheduled task drop → creates calendar event linked to task

**Animations:**
- View switching: horizontal slide (±40px, 300ms) via `AnimatePresence`
- Event appear: scale 0.95→1 + fade (150ms)
- All respect `prefers-reduced-motion` (opacity-only fallback)

**Keyboard Shortcuts:**
- D/W/M/T/A (views), ArrowLeft/Right (navigate), Y (today), C (create), E (edit), Tab (cycle events), Enter (open detail), Delete (delete selected), Escape (close)

**Responsive:**
- Desktop (≥1200px): three-panel layout
- Tablet (768–1199px): two-panel, sidebar available
- Mobile (<768px): agenda forced, sidebar hidden, view switcher hidden

**State:** `calendar-store.ts` (Zustand + persist → localStorage). Persisted: view, filters. Ephemeral: selection, panels, drag state.

---

### Navigation View

**Purpose:** Turn-by-turn navigation to job site.

**UI Elements:**

1. **Map View** (Full screen)
   - Route line (blue)
   - User location (blue dot with heading)
   - Destination pin
   - Next turn preview

2. **Instruction Banner** (Top)
   - Next turn icon (left/right/straight arrow)
   - Distance to turn
   - Street name

3. **ETA Panel** (Bottom)
   - Estimated time of arrival
   - Distance remaining
   - Current speed

4. **End Navigation Button** (Bottom)
   - "End" button (destructive red)

**Actions:**
- Real-time location updates
- Voice guidance for turns
- Haptic feedback for turns
- Auto-rerouting if off course
- Tap "End" → Return to project details

---

### PipelineTabView (Pipeline Tab Container)

**Purpose:** Container for the Pipeline/CRM feature area. Houses four sub-sections via a segmented control.

**Source:** `Views/Pipeline/PipelineTabView.swift`

**UI Elements:**

1. **AppHeader** — pipeline header type
2. **Segmented Control** — 4 sections: PIPELINE | ESTIMATES | INVOICES | ACCOUNTING
3. **Content Area** — swaps between child views based on selected segment

**Child Views:**
- `PipelineView` (Pipeline segment)
- `EstimatesListView` (Estimates segment)
- `InvoicesListView` (Invoices segment)
- `AccountingDashboard` (Accounting segment)

**Access:** Conditional — only visible to users with `"pipeline"` in their `specialPermissions` array. The main FAB is hidden when on the Pipeline tab (Pipeline manages its own FAB).

---

### PipelineView (Pipeline Segment)

**Purpose:** CRM pipeline view showing sales opportunities filtered by stage.

**Source:** `Views/Pipeline/PipelineView.swift`

**UI Elements:**

1. **Search Bar** — search deals by contact name / description
2. **Metrics Strip** — three pills showing:
   - DEALS (count of active deals)
   - WEIGHTED (weighted pipeline value based on stage probability)
   - TOTAL (total pipeline value)
3. **Stage Filter Strip** (PipelineStageStrip) — horizontal scrollable filter by pipeline stage
4. **Opportunity Cards** — list of OpportunityCard entries

**Pipeline Stages (PipelineStage enum):**
- NEW LEAD (10% probability, stale after 3 days)
- QUALIFYING (20%, stale after 7 days)
- QUOTING (40%, stale after 5 days)
- QUOTED (60%, stale after 7 days)
- FOLLOW-UP (50%, stale after 3 days)
- NEGOTIATION (75%, stale after 2 days)
- WON (100%, terminal)
- LOST (0%, terminal)

**Swipe Gestures on Opportunity Cards:**
- Swipe right → Advance to next stage
- Swipe left → Mark as Lost (opens MarkLostSheet for reason)

**Empty State:** "NO LEADS YET" with prompt to use + button.

**Navigation:**
- Tap card → push to OpportunityDetailView
- MarkLostSheet → modal for entering loss reason

---

### OpportunityDetailView

**Purpose:** Full detail view for a single pipeline opportunity.

**Source:** `Views/Pipeline/OpportunityDetailView.swift`

**UI Elements:**

1. **Header** — contact name, job description, estimated value, stage indicator with color dot, days in stage counter, stale warning icon
2. **Advance Action Button** — "ADVANCE TO [next stage]" (hidden for terminal stages)
3. **Segmented Control** — DETAILS | ACTIVITY | FOLLOW-UPS

**Details Tab:**
- CONTACT section (phone and email with tap-to-call/tap-to-email)
- DEAL INFO section (estimated value, weighted value, source, created date, last activity)

**Activity Tab:**
- List of activity entries (ActivityRowView)
- "LOG THE FIRST NOTE" empty state with button
- Most recent 5 shown with "+N MORE" overflow

**Follow-Ups Tab:**
- List of follow-up reminders (FollowUpRowView)
- Empty state: "NO FOLLOW-UPS"

**Overflow Menu (ellipsis toolbar button):**
- Edit Deal → OpportunityFormSheet
- Mark as Won
- Mark as Lost → MarkLostSheet
- Delete (destructive)

---

### EstimatesListView (Estimates Segment)

**Purpose:** List all company estimates with filtering, search, and swipe actions.

**Source:** `Views/Estimates/EstimatesListView.swift`

**UI Elements:**

1. **Search Bar** — "Search estimates..."
2. **Filter Chips** — horizontal scrollable: ALL | DRAFT | SENT | APPROVED
3. **Estimate Cards** (EstimateCard) — list of estimates with swipe actions
4. **FAB** (+) — create new estimate → EstimateFormSheet

**Swipe Actions on Estimate Cards:**
- Swipe right on DRAFT → Send estimate
- Swipe right on APPROVED → Convert to Invoice (with confirmation dialog)

**Navigation:**
- Tap card → push to EstimateDetailView
- FAB → EstimateFormSheet (modal)

**Empty State:** "NO ESTIMATES YET" with "NEW ESTIMATE" button, or "NO ESTIMATES MATCH FILTER" when filtering.

**Related Sheets:**
- EstimateFormSheet (create/edit estimate)
- EstimateDetailView (full estimate detail with line items)
- LineItemEditSheet (edit individual line items)
- ProductPickerSheet (select products for line items)

---

### InvoicesListView (Invoices Segment)

**Purpose:** List all company invoices with filtering, search, and payment recording.

**Source:** `Views/Invoices/InvoicesListView.swift`

**UI Elements:**

1. **Filter Chips** — horizontal scrollable: ALL | UNPAID | OVERDUE | PAID
2. **Search Bar** — "Search invoices..."
3. **Invoice Cards** (InvoiceCard) — list of invoices with swipe actions

**Swipe Actions on Invoice Cards:**
- Swipe right → Record payment (opens PaymentRecordSheet)
- Swipe left → Void invoice (destructive confirmation dialog)

**Navigation:**
- Tap card → push to InvoiceDetailView

**Empty State:** "NO INVOICES YET" with "Invoices appear here when estimates are converted", or "NO MATCHES" when filtering.

**Related Sheets:**
- PaymentRecordSheet (record partial or full payment)
- InvoiceDetailView (full invoice detail)

---

### AccountingDashboard (Accounting Segment)

**Purpose:** Read-only financial health overview showing AR aging, invoice status, and top outstanding clients.

**Source:** `Views/Accounting/AccountingDashboard.swift`

**UI Elements:**

1. **AR AGING Section** — horizontal bar chart (Swift Charts) with 4 buckets:
   - 0-30 days (primary accent color)
   - 31-60 days (primary accent color)
   - 61-90 days (warning color)
   - 90+ days (error color)
   - Each bar shows dollar amount annotation

2. **INVOICE STATUS Section** — 2x2 grid of tiles:
   - AWAITING (count, warning color)
   - OVERDUE (count, error color)
   - PAID (count, success color)
   - OUTSTANDING (dollar amount, primary accent)

3. **TOP OUTSTANDING Section** — ranked list of up to 5 clients with highest outstanding balances
   - Client name + dollar amount per row

**Actions:**
- Pull to refresh → Reload invoice data
- Tap to retry on error state

**Data Source:** Fetches all invoices via AccountingRepository, then computes metrics client-side.

---

### InventoryView (Inventory Tab)

**Purpose:** Main inventory management screen for tracking materials and supplies.

**Source:** `Views/Inventory/InventoryView.swift`

**UI Elements:**

1. **Search Bar** — search by item name, SKU, or description
2. **Tag Filter Chips** — horizontal scrollable tag-based filter
3. **Sort Controls** — sort by TAG | NAME | QUANTITY | THRESHOLD
4. **Inventory Item Cards** (via InventoryListView) — scalable cards with:
   - Item name (uppercase)
   - Tags (shown at scale >= 0.9)
   - SKU and metadata (shown at scale >= 1.0)
   - Quantity display with threshold status coloring (normal/low/critical/out)
   - Unit display
5. **Selection Mode** — long press activates multi-select with:
   - Selection stripe (accent color bar on left edge of selected cards)
   - Bulk actions toolbar: Adjust Quantity, Adjust Tags, Delete
   - Selection filters (by tag or keyword)
6. **FAB** (+) — new item → InventoryFormSheet

**Gestures:**
- **Pinch-to-zoom** — scales inventory cards between 0.8x-1.5x (persisted via `@AppStorage`)
- **Long press** on item card → action sheet (Select, Edit, Delete)
- **Tap** item card → opens QuantityAdjustmentSheet (or toggles selection in selection mode)

**Related Sheets:**
- InventoryFormSheet (create/edit item)
- QuantityAdjustmentSheet (adjust single item quantity)
- BulkQuantityAdjustmentSheet (adjust quantity for multiple selected items)
- BulkTagsSheet (add/remove tags for multiple items)
- InventoryManageTagsSheet (rename/delete tags)
- SpreadsheetImportSheet (import items from spreadsheet with column mapping)
- SnapshotListView (view historical inventory snapshots — automatic and manual)

---

### NotificationListView

**Purpose:** In-app notification list showing recent mentions, assignments, and updates.

**Source:** `Views/Notifications/NotificationListView.swift`

**UI Elements:**

1. **Navigation Title** — "NOTIFICATIONS"
2. **Toolbar** — "Done" button (leading), "Mark All Read" button (trailing, shown when notifications exist)
3. **Notification Rows** — each row contains:
   - Unread indicator (blue dot, 8pt circle)
   - Type icon (mention → primary accent, assignment → success, update → secondary, default → bell)
   - Title (bold if unread)
   - Body text (2 line limit)
   - Relative timestamp
   - Chevron (if notification has a linked projectId)
4. **Dividers** between rows (indented 56pt from leading edge)

**Actions:**
- Tap notification → Mark as read + deep link to Project Details (if projectId present)
- "Mark All Read" → marks all notifications read on server, resets unread count

**Empty State:** Bell slash icon + "NO NOTIFICATIONS" + "You'll see mentions and updates here"

**Data:** Fetches from NotificationRepository using current userId.

---

### PhotoAnnotationView

**Purpose:** Full-screen photo annotation view with PencilKit drawing and text notes.

**Source:** `Views/Components/Images/PhotoAnnotationView.swift`

**UI Elements:**

1. **Toolbar** (top) — Close button, Undo/Clear drawing controls (editing mode), Cancel/Done buttons (editing mode), "ANNOTATE" button (view mode)
2. **Photo Display** — AsyncImage with aspect-fit scaling
3. **Annotation Overlay** — existing annotation image overlaid on photo (view mode)
4. **PencilKit Canvas** — transparent drawing canvas over photo (editing mode)
   - Default tool: thin white pen (3pt width)
   - Works with finger and Apple Pencil (`drawingPolicy = .anyInput`)
   - iOS PencilKit tool picker available
5. **Bottom Bar** — note text field ("Add a note...") with notes icon

**Actions:**
- Tap "ANNOTATE" → enters editing mode with PencilKit canvas and tool picker
- Draw on canvas → strokes saved as PKDrawing
- Undo → removes last stroke
- Clear → removes all strokes
- Done → saves annotation (drawing + note) via PhotoAnnotationSyncManager
- Cancel → restores original drawing
- Close → dismiss view

**Data:** Saves/loads via PhotoAnnotationSyncManager. Drawing data stored locally (PKDrawing data) and annotation image uploaded to server.

---

### ProjectNotesView

**Purpose:** Per-project message board where team members post timestamped notes with @mention support.

**Source:** `Views/Components/Project/ProjectNotesView.swift`

**UI Elements:**

1. **Notes List** (ScrollView with LazyVStack) — list of ProjectNoteRow cards:
   - Author avatar (initials in circle, 32pt)
   - Author name (uppercase, bold)
   - Timestamp (relative: "h:mm a" for today, "Yesterday h:mm a", "MMM d, h:mm a" for older)
   - Content text with @mention highlighting (mentions in primaryAccent color)
   - Delete button (trash icon, shown only for own notes)
   - Delete confirmation dialog

2. **Mention Suggestion Bar** — horizontal scrollable row of team member pills
   - Avatar (initials, 24pt) + full name
   - Appears when typing "@" in compose bar

3. **Compose Bar** (bottom) — text input + send button
   - "Write a note..." placeholder
   - Send icon (primaryAccent when text present, tertiaryText when empty)
   - Disabled when text is empty/whitespace
   - Submit on Enter key or send button tap

**Actions:**
- Type "@" → shows mention suggestion bar with team members
- Tap team member suggestion → inserts @mention into text
- Tap send → posts note via ProjectNotesViewModel
- Tap delete on own note → confirmation dialog → delete note
- Auto-scrolls to newest note when list updates

**Empty State:** Notes icon + "NO NOTES YET" + "Post a note for your team"

---

### Settings Screen

**Purpose:** Manage user profile, company settings, and app preferences.

**UI Elements:**

1. **User Profile Section**
   - Avatar (initials or photo)
   - Name
   - Email
   - Phone
   - "Edit Profile" chevron

2. **Company Section** (Admin only)
   - Company name
   - Industry
   - Company code
   - "Manage Company" chevron

3. **Security Section**
   - "PIN Management" row with chevron
   - "Change PIN" or "Set PIN"

4. **Subscription Section**
   - Current plan name
   - "Upgrade" button (if not on highest tier)
   - Trial countdown (if in trial)

5. **Help & Support Section**
   - "Tutorial" row with chevron
   - "Help Center" row with chevron (future)
   - "Contact Support" row with chevron (future)

6. **About Section**
   - App version
   - "Terms of Service" row
   - "Privacy Policy" row

7. **Logout Button** (Bottom)
   - Red destructive button
   - "Log Out"

**Actions:**
- Tap Edit Profile → Profile form
- Tap Manage Company → Company settings (Admin)
- Tap PIN Management → PIN setup/change
- Tap Upgrade → Stripe payment portal
- Tap Tutorial → Restart tutorial
- Tap Log Out → Confirmation dialog → Logout

---

## Gesture Patterns

### Swipe to Change Status

**Location:** Task rows in project details, task list views

**Gesture:**
- **Swipe Right** → Advance status forward
  - Booked → In Progress
  - In Progress → Completed
- **Swipe Left** → Revert status (or cancel)
  - In Progress → Booked
  - Any status → Cancelled

**Feedback:**
- Haptic vibration on status change
- Smooth animation of status badge color change
- Immediate UI update (no loading spinner)

**Permissions:**
- Field Crew: Can change status for assigned tasks only
- Admin/Office: Can change any task status

---

### Pull to Refresh

**Location:** All list screens (home, job board, schedule, estimates, invoices, accounting, inventory)

**Gesture:**
- Pull down from top of scroll view
- Release to trigger sync

**Feedback:**
- Loading spinner during sync
- "Last synced: X minutes ago" text
- Success/failure toast message

---

### Swipe to Dismiss

**Location:** All modal sheets (form sheets, detail sheets)

**Gesture:**
- Swipe down from top of sheet
- Dismisses sheet

**Behavior:**
- If form has unsaved changes → Confirmation dialog
- If no changes → Dismisses immediately

---

### Long Press

**Location:** Inventory item cards

**Gesture:**
- Press and hold on card (minimum 0.3 seconds)
- Scale animation (0.95x) provides visual feedback during press

**Action:**
- Opens action sheet with options:
  - Select (enters selection mode)
  - Edit (opens InventoryFormSheet)
  - Delete (destructive, with confirmation dialog)

---

### Pinch to Zoom

**Location:** Navigation view (via Project Details "Get Directions"), image gallery, inventory list

**Gesture:**
- Two-finger pinch in/out

**Action:**
- Navigation/gallery: Zoom in/out on map or image
- Inventory: Scale inventory item cards between 0.8x and 1.5x. At smaller scales, tags and metadata are progressively hidden for a denser view. Scale is persisted via `@AppStorage("inventoryCardScale")`.

---

## Common Workflows

### Workflow 1: Create Project → Schedule Tasks → Assign Crew

**Time:** ~3 minutes

**Steps:**
1. Job Board → Tap FAB
2. Enter project title, select client, add location
3. Set status to "Accepted"
4. Save project
5. Tap new project → Project details
6. Tap "Add Task"
7. Select task type, enter custom title if needed
8. Tap "Schedule" → Select dates
9. Tap "Assign Team" → Select crew members
10. Save task
11. Repeat steps 6-10 for additional tasks
12. Verify calendar → All events appear

---

### Workflow 2: Update Project Status Throughout Lifecycle

**Time:** ~10 seconds per update

**Steps:**
1. Job Board → Tap project
2. Tap status badge → Status picker sheet opens
3. Select new status (RFQ → Estimated → Accepted → In Progress → Completed)
4. Status updates immediately
5. Haptic feedback
6. Changes sync to server

---

### Workflow 3: Navigate to Job Site and Complete Task

**Time:** ~5 minutes (excluding travel)

**Steps:**
1. Home or Job Board → Tap today's project
2. Project details → Tap "Get Directions"
3. Follow turn-by-turn navigation
4. Arrive at site → Tap "End Navigation"
5. Swipe task to "In Progress"
6. Perform work
7. Tap "Add Photos" → Capture documentation
8. Swipe task to "Completed"
9. Photos upload when connectivity available

---

### Workflow 4: Schedule Next Week's Jobs (Office Crew)

**Time:** ~1 minute per project

**Steps:**
1. Job Board → Select "Unscheduled" section
2. Tap first project
3. Tap first unscheduled task
4. Tap "Schedule" row
5. Select start date (next week)
6. Select end date
7. Assign crew if not already assigned
8. Save
9. Repeat for remaining tasks
10. Back to Job Board → Project moved to "Next Week" section

---

### Workflow 5: View and Filter Schedule

**Time:** ~30 seconds

**Steps:**
1. Schedule tab → today's date selected, DayCanvasView shows today's tasks
2. Tap a different day in the week strip → DayCanvasView snaps to that day
3. Tap a task card → Goes to Task Details
4. Return to Schedule → Tap month icon in header → Month grid expands
5. Tap a date in the month grid → DayCanvasView shows that day's tasks
6. Pinch the month grid → collapses back to week strip
7. Tap filter button in header → CalendarFilterView opens
8. Apply filter by team member → day canvas shows only that member's tasks

---

## Role-Based UI Differences

**Note**: OPS uses 5 roles (Admin, Owner, Office, Operator, Crew) with ~55 granular permissions and scopes. See `03_DATA_ARCHITECTURE.md` > Permissions System Tables for the complete schema. Below describes each role's default UI experience.

### Admin (Hierarchy 1)

**All permissions granted with scope `all`.** Full system control including billing and role assignment.

- All tabs visible (Pipeline, Inventory included)
- All form sheets accessible
- Floating action buttons on all applicable screens
- Can create, edit, delete all entities
- Can assign team members and roles
- Can manage company settings and subscription
- Job Board: All sections visible
- Pipeline: Full access to CRM, estimates, invoices, accounting
- Inventory: Full management access
- **Unique**: Only role with `team.assign_roles` and `settings.billing` by default

---

### Owner (Hierarchy 2)

**All permissions except `team.assign_roles` and `settings.billing`.**

- All tabs visible (Pipeline, Inventory included)
- All form sheets accessible
- Floating action buttons on all applicable screens
- Can create, edit, delete all entities
- Can assign team members (but not assign roles)
- Can manage company settings and integrations
- Cannot manage subscription/billing
- Job Board: All sections visible
- Pipeline: Full access
- Inventory: Full access

---

### Office (Hierarchy 3)

**Full project and financial access. No company settings or role management.**

- All tabs visible (Pipeline, Inventory included)
- All form sheets accessible (except company settings)
- Floating action buttons on applicable screens
- Can create, edit projects/tasks/clients (no project delete)
- Can assign team members
- Cannot manage company settings, billing, or roles
- Job Board: All sections visible
- Pipeline: Full access (view + manage, no stage configuration)
- Inventory: Full management access

---

### Operator (Hierarchy 4)

**Lead tech — creates projects/estimates, edits assigned work. Scoped access.**

- Pipeline tab: NOT shown (no `pipeline.view` permission)
- Inventory tab: NOT shown (no `inventory.view` permission)
- Floating action buttons on applicable screens
- Can create projects/tasks/clients/estimates
- Can edit only assigned projects and tasks (scope = `assigned`)
- Can view all projects but edit only assigned ones
- Job Board: All sections except Pipeline
- Estimates: Can view all, create, edit own
- Invoices: View only
- Expenses: Can view/create/edit own expenses (no approve)
- Photos: Full access, delete own only

---

### Crew (Hierarchy 5)

**Field-only access. Views and edits assigned work, creates expenses.**

- Pipeline tab: NOT shown
- Inventory tab: NOT shown
- Floating action button visible on Schedule tab only
- Cannot create projects, tasks, or clients
- Can edit and change status of assigned tasks (scope = `assigned`)
- Can view only assigned projects (scope = `assigned`)
- Job Board: Assigned projects/tasks only (no section picker)
- Calendar: Own events only (scope = `own`)
- Expenses: Can view/create/edit own expenses
- Photos: Can view assigned, upload, annotate (no delete)
- No company settings, billing, team management, or role assignment

**Permitted Actions:**
- Swipe to change status (assigned tasks only)
- Get directions to job sites
- Capture and annotate photos for assigned projects
- Create personal calendar events and time-off requests
- Submit expenses
- View assigned schedules
- Create personal calendar events via Schedule FAB
- Submit time-off requests via Schedule FAB

---

**Last Updated:** March 2, 2026
**Document Version:** 1.3
**iOS App Version:** 207+ Swift files, iOS 17+, SwiftData + SwiftUI
