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

The app uses a bottom tab bar with 5 tabs for primary navigation:

```
┌─────────────────────────────────────────────┐
│                                             │
│           Screen Content Area               │
│                                             │
│                                             │
├─────┬─────┬─────┬─────┬─────────────────────┤
│ Home│Board│Cal. │Map  │Settings             │
└─────┴─────┴─────┴─────┴─────────────────────┘
```

**Tab Bar Items:**

1. **Home** (house icon)
   - Dashboard view
   - Quick access to recent projects
   - Today's schedule
   - Quick actions

2. **Job Board** (clipboard icon)
   - Project organization by sections
   - Search and filter
   - Dashboard view (Field Crew only)

3. **Calendar** (calendar icon)
   - Month/Week/Day views
   - Event management
   - Schedule overview

4. **Map** (map icon)
   - Project locations
   - Navigation hub
   - Route planning

5. **Settings** (gear icon)
   - User profile
   - Company settings (Admin only)
   - PIN management
   - Tutorial access

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
├── Tab Bar (Main Container)
│   ├── Home Tab
│   │   ├── Dashboard Screen
│   │   ├── → Project Details (push)
│   │   ├── → Task Details (push)
│   │   └── → Form Sheets (modal)
│   │
│   ├── Job Board Tab
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
│   ├── Calendar Tab
│   │   ├── Calendar Screen
│   │   │   ├── Month/Week/Day Picker
│   │   │   ├── Event List
│   │   │   ├── → Project Details (push via event tap)
│   │   │   └── → Task Details (push via event tap)
│   │   │
│   │   └── Calendar Event Form (Admin/Office)
│   │
│   ├── Map Tab
│   │   ├── Map Screen
│   │   │   ├── Project Pins
│   │   │   ├── → Project Details (tap pin)
│   │   │   └── → Navigation (tap "Get Directions")
│   │   │
│   │   └── Navigation View (fullscreen)
│   │       ├── Turn-by-turn guidance
│   │       ├── ETA display
│   │       └── End navigation button
│   │
│   └── Settings Tab
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
└── Floating Action Buttons (contextual)
    ├── + New Project (Home, Board)
    ├── + New Task (Project Details)
    ├── + New Client (Clients List)
    └── Photo Camera (Project Details)
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

**Phase 11: Calendar Tab**
- Overlay: "Let's check the Calendar to see your schedule."
- Highlight: Calendar tab
- Action: Tap Calendar tab

**Phase 12: Calendar View Options**
- Overlay: "Switch between Month, Week, and Day views."
- Highlight: View picker
- Action: Tap "Week" view

**Phase 13: Calendar Event Tap**
- Overlay: "Tap any event to view its project or task."
- Highlight: Calendar event
- Action: Tap event → Goes to task details

**Phase 14: Map Tab**
- Overlay: "The Map shows all your project locations."
- Highlight: Map tab
- Action: Tap Map tab

**Phase 15: Map Pins**
- Overlay: "Each pin is a project. Tap a pin for details."
- Highlight: Map pin
- Action: Tap pin → Goes to project details

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
19. **Verification:** Check calendar tab → Event appears on tomorrow's date
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

### Job Board Screen

**Purpose:** Organize and view all projects by custom sections.

**UI Elements (Admin/Office):**
- **Section Picker** - Dropdown to select section
  - Unscheduled
  - This Week
  - Next Week
  - In Progress
  - Completed
  - All Projects
  - (Custom sections if created)
- **Search Bar** - Search projects by title, client
- **Filter Button** - Filter by status, team member
- **Job Cards** - Universal project cards
  - Title
  - Client name
  - Status badge
  - Unscheduled badge (if applicable)
  - Date range
  - Team avatars
  - Location indicator
- **Floating Action Button** - + New Project

**UI Elements (Field Crew):**
- **Dashboard Title** - "My Projects"
- **No Section Picker** - Only dashboard view
- **Job Cards** - Assigned projects only (filtered automatically)
- **No FAB** - Cannot create projects

**Actions:**
- Tap section picker → Change section
- Tap search → Enter search query
- Tap filter → Open filter sheet
- Tap job card → Project details
- Tap FAB → Project form sheet (Admin/Office)
- Pull to refresh → Sync data

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

### Calendar Screen

**Purpose:** View and manage scheduled events across time.

**UI Elements:**

1. **View Picker** (Top)
   - Month button
   - Week button
   - Day button

2. **Month View**
   - Traditional month grid
   - Day numbers
   - Event indicators (colored dots)
   - Selected date highlighted
   - Event list below grid for selected date

3. **Week View**
   - 7 columns (Mon-Sun)
   - Time slots (7 AM - 8 PM)
   - Event blocks in time slots
   - All-day events at top
   - Scrollable vertically

4. **Day View**
   - Single day time slots
   - Event blocks with full details
   - Hourly grid
   - All-day events at top

5. **Event List (Below Calendar)**
   - Date header
   - Event rows:
     - Task title
     - Project name
     - Time range
     - Team avatars
   - Empty state: "No events scheduled"

**Actions:**
- Tap view picker → Change calendar view
- Tap date in month view → Load events for that date
- Tap event → Task details (if task-based) or Project details
- Tap + button → Calendar event form (Admin/Office)
- Pull to refresh → Sync data

**Role Differences:**
- Admin/Office: Can create/edit events, see all events
- Field Crew: View only, see only assigned events

---

### Map Screen

**Purpose:** Visualize project locations and access navigation.

**UI Elements:**

1. **Map View**
   - Apple MapKit map
   - Project pins (color-coded by status)
   - User location (blue dot)
   - Zoom controls

2. **Pin Callout** (On tap)
   - Project title
   - Client name
   - Address
   - "View Details" button

3. **Filter Button** (Top right)
   - Filter by status
   - Filter by team member

4. **Recenter Button** (Bottom right)
   - Returns to user location

**Actions:**
- Tap pin → Show callout
- Tap "View Details" in callout → Project details
- Tap "Get Directions" in project details → Navigation view
- Pinch to zoom
- Drag to pan
- Tap filter → Open filter sheet

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

**Location:** All list screens (home, job board, calendar)

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

**Location:** Project/task cards (future feature)

**Gesture:**
- Press and hold on card

**Action:**
- Opens context menu with quick actions
  - Edit
  - Delete
  - Duplicate
  - Share

---

### Pinch to Zoom

**Location:** Map screen, image gallery

**Gesture:**
- Two-finger pinch in/out

**Action:**
- Zoom in/out on map or image

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

### Workflow 5: View and Filter Calendar

**Time:** ~30 seconds

**Steps:**
1. Calendar tab → Month view loads
2. Tap date → See events for that date
3. Tap event → Goes to task details
4. Return to calendar → Switch to Week view
5. Scroll through week
6. Tap filter → Filter by team member
7. Calendar shows only that member's events

---

## Role-Based UI Differences

### Admin

**Full Access:**
- All tabs visible
- All form sheets accessible
- Floating action buttons on all screens
- Can create, edit, delete all entities
- Can assign team members
- Can manage company settings
- Can upgrade/downgrade subscription
- Job Board: All sections visible

**Unique Features:**
- Company Settings in Settings tab
- Subscription management
- Designate other admins
- View all projects (not just assigned)

---

### Office Crew

**Full Project Management:**
- All tabs visible
- All form sheets accessible (except company settings)
- Floating action buttons on all screens
- Can create, edit, delete projects, tasks, clients
- Can assign team members
- Cannot manage company settings
- Cannot manage subscription
- Job Board: All sections visible

**Restrictions:**
- No company settings access
- No subscription management
- No admin designation

---

### Field Crew

**View-Only with Status Updates:**
- All tabs visible
- Job Board: Dashboard view only (no section picker)
- No floating action buttons
- Cannot create, edit, delete any entities
- Can change status of assigned tasks/projects
- Can view calendar (assigned events only)
- Can navigate to job sites
- Can capture photos

**Restrictions:**
- No form sheets (cannot create/edit)
- Cannot schedule tasks or events
- Cannot assign team members
- Cannot delete anything
- Cannot view unassigned projects
- No company settings access

**Permitted Actions:**
- Swipe to change status (assigned tasks only)
- Get directions to job sites
- Capture photos for assigned projects
- View assigned schedules

---

**Last Updated:** February 18, 2026
**Document Version:** 1.1
**iOS App Version:** 207 Swift files, iOS 17+, SwiftData + SwiftUI
