# 01_PRODUCT_REQUIREMENTS.md

## Document Purpose

This document catalogs every feature, user story, business rule, and functional requirement of the OPS application. It serves as the definitive reference for what the app does and why.

---

## Table of Contents

1. [Feature Inventory](#feature-inventory)
2. [User Stories by Role](#user-stories-by-role)
3. [Business Rules & Constraints](#business-rules--constraints)
4. [Offline-First Requirements](#offline-first-requirements)
5. [Field-Specific Requirements](#field-specific-requirements)
6. [Subscription & Access Control](#subscription--access-control)

---

## Feature Inventory

### 1. Authentication & Onboarding

#### Authentication Methods
- **Google Sign-In** - OAuth integration via Firebase
- **Apple Sign-In** - Native OAuth integration
- **Email/Password** - Traditional credentials via Firebase
- **4-Digit PIN** - Local security layer (stored in Keychain, resets on app background)

#### Onboarding Flows

**Company Creator Flow:**
1. Welcome screen
2. Signup method selection
3. Credential entry
4. Profile setup (first name, last name, phone)
5. Company setup (company name)
6. Company details (industry, crew size)
7. Company code display (6-character unique code)
8. Ready screen
9. Interactive tutorial (25 phases)

**Employee Flow:**
1. Welcome screen
2. Signup method selection
3. Credential entry
4. Profile setup (first name, last name, phone)
5. Company code entry (join existing company)
6. Ready screen
7. Interactive tutorial (25 phases)

#### Tutorial System
- **25-Phase Interactive Tutorial** - Comprehensive onboarding covering all app features
- **Demo Mode** - Pre-populated demo data for safe exploration
- **Skip Option** - Users can skip tutorial and access later from settings
- **Contextual Overlays** - Step-by-step guidance with visual highlights
- **Progress Tracking** - Resume tutorial where user left off

### 2. Project Management

#### Project Creation & Editing
- **Create Projects** - Title, client, location, notes, description, status
- **Edit Projects** - Update any field with permission-based restrictions
- **Delete Projects** - Soft delete (marked for deletion, synced to server)
- **Duplicate Projects** - Copy project structure for similar jobs
- **Project Status Workflow** - RFQ → Estimated → Accepted → In Progress → Completed → Closed → Archived
- **Location Management** - Address entry with map preview, GPS coordinates
- **Client Assignment** - Link projects to existing clients or create inline
- **Team Assignment** - Assign multiple crew members to projects
- **Photo Documentation** - Capture and attach photos to projects (S3 storage)
- **Notes & Description** - Long-form text fields for project details
- **Project Notes System (iOS & OPS Web)** - Per-project message board with timestamped notes, @mentions with autocomplete, author attribution (name + avatar), and photo attachments. On iOS, notes are displayed in a scrollable list with a compose bar and mention suggestion overlay. Notes sync to Supabase via `ProjectNoteRepository`. Replaces the legacy plain-text teamNotes field from Bubble. See [07_SPECIALIZED_FEATURES.md](07_SPECIALIZED_FEATURES.md) Section 11.

#### Project Viewing
- **Project Details View** - Comprehensive project overview
- **Status Badge** - Color-coded status indicator
- **Breadcrumb Navigation** - Company → Client → Project hierarchy
- **Location Card** - Address display with "Get Directions" button
- **Client Info Card** - Client contact details with tap-to-call/email
- **Notes Card** - Expandable notes section (iOS & OPS Web: threaded notes with @mentions, author attribution, timestamps — see [07_SPECIALIZED_FEATURES.md](07_SPECIALIZED_FEATURES.md) Section 11)
- **Team Members Card** - Assigned crew with avatars
- **Task List** - All tasks grouped by status
- **Image Gallery** - Project photos with full-screen viewer
- **Previous/Next Navigation** - Swipe between projects

#### Project Scheduling
- **Task-Based Scheduling** - Project dates computed from task calendar events
- **Start/End Dates** - Derived from earliest/latest task dates
- **Duration Calculation** - Automatic duration based on date range
- **All-Day Events** - Toggle for all-day scheduling

### 3. Task Management

#### Task Creation & Editing
- **Create Tasks** - Task type, custom title, notes, team assignment
- **Edit Tasks** - Update any field with permission-based restrictions
- **Delete Tasks** - Soft delete (marked for deletion, synced to server)
- **Task Types** - Customizable categories with colors and icons
- **Task Status Workflow** - Active → Completed (or Cancelled). Legacy values (Booked, Scheduled, In Progress) are mapped to Active on decode.
- **Team Assignment** - Assign multiple crew members to tasks
- **Calendar Integration** - Link tasks to calendar events for scheduling
- **Task Ordering** - Display order within projects
- **Task Index** - Auto-calculated based on start date
- **Custom Titles** - Override default task type name
- **Color Customization** - Visual identification per task

#### Task Viewing
- **Task Details View** - Comprehensive task overview (matches Project Details structure)
- **Status Badge** - Color-coded status indicator
- **Breadcrumb Navigation** - Company → Client → Project → Task hierarchy
- **Location Card** - Project address with "Get Directions"
- **Client Info Card** - Client contact details
- **Notes Card** - Task-specific notes (iOS only; OPS Web removed task-level notes in Feb 2026 — notes are now project-level only)
- **Team Members Card** - Assigned crew for task
- **Dates Section** - Scheduled start/end dates from calendar event
- **Previous/Next Navigation** - Navigate between tasks in project

#### Task Status Updates
- **Swipe-to-Change-Status** - Gesture-based status updates
- **Status Pills** - Quick status change from details view
- **Haptic Feedback** - Tactile confirmation of status changes
- **Permission-Based** - Field crew can update statuses, dates require admin/office

### 4. Calendar & Scheduling

#### Calendar Views
- **Monthly View** - Traditional month grid with event indicators
- **Weekly View** - Week-at-a-glance with hourly time grid (default desktop view)
- **Daily View** - Single-day hourly schedule detail
- **Team Timeline View** - Gantt-style horizontal timeline with one row per crew member (web)
- **Agenda View** - Chronological scrollable list grouped by date (mobile default)

#### Calendar Event Management
- **Create Events** - Click empty slot to quick-create, or click-and-drag time range to create with pre-filled times (web)
- **Edit Events** - Inline detail panel (Sheet, side="right") with title, time range, project, type, team editing (web)
- **Delete Events** - From detail panel, context menu, or keyboard shortcut
- **Drag-and-Drop Scheduling** - Drag events to new times/days with ghost preview and real-time time labels (web, @dnd-kit)
- **Event Resize** - Bottom-edge drag handle with 15-minute snap grid (web)
- **Multi-Day Events** - Span events across multiple days
- **Duration Management** - Calculate duration from start/end dates
- **Team Assignment** - Assign crew to calendar events
- **Color Coding** - Events inherit task type colors (install=blue, repair=amber, inspection=emerald, maintenance=violet, consultation=rose, estimate=cyan, other=slate)
- **Context Menu** - Right-click event for Edit, Duplicate, Delete (web)
- **Conflict Detection** - Red glow on overlapping events per team member, detected via `detectConflicts()` utility

#### Filtering & Organization
- **Filter Sidebar** - Collapsible left panel with multi-select filters (web, 260px)
- **Filter by Team Member** - Checkbox list with avatars
- **Filter by Task Type** - Color-coded checkboxes
- **Filter by Project** - Searchable multi-select
- **Filter by Status** - Upcoming, In Progress, Past checkboxes
- **Unscheduled Tasks Panel** - Draggable tasks with no calendar event; drop onto calendar to schedule (web)
- **Filter Chips** - Active filter count in toolbar
- **Clear All** - One-click reset all filters

#### Keyboard Navigation (Web)
- **View Switching** - D (day), W (week), M (month), T (team), A (agenda)
- **Date Navigation** - ArrowLeft/Right (period-aware: day/week/month)
- **Quick Actions** - Y (today), C (create), E (edit selected), Delete/Backspace (delete selected)
- **Event Navigation** - Tab/Shift+Tab (cycle events), Enter (open detail panel), Escape (close panels)

#### Responsive Layout (Web)
- **Desktop (≥1200px)** - Three-panel: filter sidebar + calendar grid + detail panel
- **Tablet (768–1199px)** - Two-panel, sidebar available
- **Mobile (<768px)** - Agenda view default, filter sidebar hidden, bottom sheets for details

### 5. Job Board (Redesigned March 2026)

The Job Board uses a role-based section system. Each role sees a different set of sections.

#### Role-Based Sections

| Section | Field Crew | Office Crew | Admin |
|---------|-----------|-------------|-------|
| My Tasks | ✅ (default) | ❌ | ❌ |
| My Projects | ✅ | ❌ | ❌ |
| Projects | ❌ | ✅ (default) | ✅ (default) |
| Tasks | ❌ | ✅ | ✅ |
| Kanban | ❌ | ✅ | ✅ |
| Pipeline | ❌ | ✅ (with `pipeline` permission) | ✅ (with `pipeline` permission) |

**Note:** Field crew do not see the section picker. Section switching is not available to field crew.

#### My Tasks Section (Field Crew)
- Shows tasks explicitly assigned to the current user only
- Tasks with no explicit assignment are NOT shown (no fallback to all project tasks)
- Filter chips: ALL / TODAY / UPCOMING / COMPLETED
- Tasks grouped by project, collapsible groups
- Empty state: "No tasks assigned to you"

#### My Projects Section (Field Crew)
- Shows only projects where the user is a team member
- Swipe-to-change-status on cards
- Read access + status update only

#### Projects Section (Office/Admin)
- All company projects with filters (status, team member, search)
- Swipe-to-change-status on cards
- Closed/archived projects in collapsible section

#### Tasks Section (Office/Admin)
- All company tasks across all projects
- Filter by status, type, team member

#### Kanban Section (Office/Admin)
- Project count distribution across statuses: RFQ → Estimated → Accepted → In Progress → Completed
- Proportional fill bars; tap to expand and view project cards per status

#### Pipeline Section (Admin + `pipeline` permission)
- CRM pipeline for lead/deal management
- Gated by `User.specialPermissions.contains("pipeline")`

#### Universal Job Card (`UniversalJobBoardCard`)
- **Project Title** — Primary identifier
- **Client Name** — Associated client
- **Status Badge** — Color-coded using `OPSStyle.Colors.statusColor(for:)`
- **Unscheduled Badge** — Projects with no scheduled active tasks
- **Date Display** — Scheduled start/end dates
- **Team Avatars** — Assigned crew members
- **Location Indicator** — Address snippet
- **Quick Actions** — Swipe gestures for status change
- **Directional Drag** — `DirectionalDragModifier` resolves scroll vs. swipe conflict

#### Universal Search Sheet
- Opened from header search button (`AppState.showingJobBoardSearch`)
- Role-filtered: field crew sees only assigned projects/tasks
- Pipeline-gated: no RFQ/Estimated projects for non-pipeline users
- Searches project title, client name, address, task title, task notes

### 6. Client Management

#### Client Creation & Editing
- **Create Clients** - Name, company, email, phone, address
- **Edit Clients** - Update contact details
- **Delete Clients** - Soft delete (preserves project associations)
- **Import from Contacts** - Pull contacts from device (iOS Contacts integration)
- **Inline Creation** - Create clients directly from project form
- **Multi-Field Support** - Sub-clients for larger organizations
- **Avatar Display** - Auto-generated initials or uploaded images

#### Client Viewing
- **Client List** - Alphabetized list of all clients
- **Search & Filter** - Find clients by name, company, email
- **Client Details** - Contact info with tap-to-call/email
- **Associated Projects** - List of all projects for client
- **Contact Actions** - Direct phone/email integration

### 7. Team Management

#### User Management
- **View Team Members** - List of all company users
- **Role Assignment** - Admin, Office Crew, Field Crew
- **Employee Type** - Additional classification (Admin, Manager, Field Crew, etc.)
- **Company Code Sharing** - Invite employees via 6-character code
- **Admin Designation** - Company owner can designate additional admins
- **User Profiles** - Name, email, phone, role, avatar

#### Team Assignment
- **Project-Level Assignment** - Assign multiple crew to projects
- **Task-Level Assignment** - Assign specific crew to tasks
- **Calendar Event Assignment** - Assign crew to scheduled events
- **Computed Team Members** - Project teams computed from task assignments
- **Team Filtering** - View projects/tasks by assigned crew

### 8. Navigation & Maps

#### Turn-by-Turn Navigation
- **NavEngine** - Custom navigation engine with Kalman filter for GPS smoothing
- **MapKit Integration** - Apple's native mapping framework
- **Route Calculation** - Automatic optimal route to job site
- **ETA Display** - Estimated time of arrival
- **Real-Time Updates** - Live location tracking during navigation
- **Voice Guidance** - Turn-by-turn audio instructions
- **Background Location** - Continue tracking when app backgrounded
- **Haptic Feedback** - Turn notifications via device vibration

#### Map Features
- **Map Preview** - Location display in project/task details
- **Get Directions Button** - One-tap navigation launch
- **Coordinate Storage** - Latitude/longitude stored with projects
- **Offline Maps** - Map tiles cached for offline use
- **Location Permissions** - Request/manage iOS location services

#### MapCoordinator
- **State Management** - Centralized map state handling
- **Route Management** - Store and update navigation routes
- **Location Updates** - Process and smooth GPS data
- **Map Annotations** - Display project/task locations on map

### 9. Image Management

#### Image Capture
- **In-App Camera** - Native camera integration for job photos
- **Photo Library Access** - Select existing photos from device
- **Multiple Image Upload** - Batch upload photos per project
- **Image Compression** - Optimize images for upload
- **Local Storage** - Store unsynced images locally

#### Image Sync
- **S3 Upload** - Direct upload to AWS S3 with presigned URLs
- **Automatic Sync** - Upload images when connectivity available
- **Sync Queue** - Queue unsynced images for later upload
- **Sync Status Tracking** - Visual indicators for upload progress
- **Company/Project Folders** - Organize S3 storage by hierarchy

#### Image Viewing
- **Image Gallery** - Grid view of project images
- **Full-Screen Viewer** - Zoom and pan capabilities
- **Image Metadata** - Capture timestamp and device info
- **Delete Images** - Remove images locally and from S3

### 10. Sync & Offline

#### Sync Strategy
- **Triple-Layer Sync:**
  1. **Immediate Sync** - User actions trigger sync with 2-second debounce
  2. **Event-Driven Sync** - App launch, connectivity restored, app foreground
  3. **Periodic Sync** - 3-minute retry for failed syncs

#### Sync Operations
- **SupabaseSyncManager** - Orchestrates all sync operations (replaced CentralizedSyncManager)
- **Per-Entity Sync** - Individual sync methods for each data model
- **Conflict Resolution** - Push local changes first, then fetch and replace with server
- **Server Wins** - Server data takes precedence in conflicts
- **Soft Delete** - Items missing from server marked as deleted locally
- **Sync Priority** - 0-3 scale (3 = highest priority)
- **Sync Flags** - needsSync, syncPriority, lastSyncedAt on all entities

#### Offline Capabilities
- **Full Offline Access** - All features work without connectivity
- **Local Data Persistence** - SwiftData stores all data locally
- **Offline Queue** - Changes queued for sync when online
- **Connectivity Monitoring** - Track network status and notify user
- **Background Sync** - Sync when app returns online

### 11. Settings & Configuration

#### User Settings
- **Profile Management** - Edit name, email, phone
- **PIN Management** - Set, change, reset 4-digit PIN
- **Notification Preferences** - NotificationSettingsView with per-project notification controls (see Feature 19)
- **Theme Settings** - (Currently dark theme only)

#### Company Settings (Admin Only)
- **Company Profile** - Name, industry, crew size
- **Company Code** - View/share 6-character code
- **Subscription Management** - View current plan, upgrade/downgrade
- **Admin Management** - Designate additional admins
- **Task Type Management** - Create/edit custom task types

#### App Settings
- **Tutorial Access** - Restart tutorial anytime
- **About/Help** - App version, support contact
- **Logout** - Sign out and clear local data
- **Delete Account** - Remove user account (future feature)

### 12. Subscription & Billing

#### Subscription Tiers
- **Trial** - 30 days, 10 seats included
- **Starter** - $90/month, 3 seats
- **Team** - $140/month, 5 seats
- **Business** - $190/month, 10 seats
- **Annual Discount** - 20% off all plans

#### Subscription Management
- **Stripe Integration** - Payment processing via Bubble.io plugin
- **Subscription Enforcement** - SubscriptionManager enforces access
- **Lockout Screen** - Block access for expired subscriptions
- **Upgrade/Downgrade** - Change plans in settings
- **Trial Countdown** - Display remaining trial days

#### Access Control
- **Seat Limit Enforcement** - Block adding users beyond seat limit
- **Feature Access** - Full features for active subscriptions
- **Grace Period** - (Future feature)

### 13. Analytics & Tracking

#### Firebase Analytics
- **Event Tracking** - User actions logged to Firebase
- **Screen Views** - Track navigation patterns
- **User Properties** - Role, company size, subscription tier
- **Google Ads Integration** - Conversion tracking
- **Crash Reporting** - (Future feature)

#### Tracked Events
- **Authentication** - Login, logout, signup
- **Projects** - Create, edit, delete, status change
- **Tasks** - Create, edit, delete, status change
- **Navigation** - Start/stop navigation to job site
- **Images** - Capture, upload, view
- **Subscription** - Trial start, upgrade, downgrade, cancel

---

## User Stories by Role

### Admin (Company Owner)

#### Authentication & Setup
- **As an admin**, I want to create a company account so that I can start managing projects
- **As an admin**, I want to receive a unique company code so that I can invite employees
- **As an admin**, I want to complete an interactive tutorial so that I understand how to use the app

#### Project Management
- **As an admin**, I want to create projects with all details (title, client, location, status) so that I can track jobs
- **As an admin**, I want to edit project details so that I can keep information current
- **As an admin**, I want to assign multiple crew members to projects so that teams know their assignments
- **As an admin**, I want to change project status so that I can track progress through workflow
- **As an admin**, I want to delete projects so that I can remove cancelled or duplicate jobs
- **As an admin**, I want to add photos to projects so that I can document work
- **As an admin**, I want to view all projects regardless of assignment so that I have full oversight

#### Task Management
- **As an admin**, I want to create tasks within projects so that I can break down work into steps
- **As an admin**, I want to assign crew members to specific tasks so that work is delegated clearly
- **As an admin**, I want to schedule tasks with calendar events so that crew knows when work happens
- **As an admin**, I want to customize task types with colors and icons so that tasks are easily identifiable
- **As an admin**, I want to reorder tasks so that work sequence is logical

#### Client Management
- **As an admin**, I want to create client records so that I can track customer information
- **As an admin**, I want to import contacts from my phone so that I don't re-enter data
- **As an admin**, I want to view all projects per client so that I can see customer history
- **As an admin**, I want to call or email clients directly from the app so that communication is quick

#### Team Management
- **As an admin**, I want to view all company employees so that I know who's on the team
- **As an admin**, I want to designate other users as admins so that I can delegate management
- **As an admin**, I want to set employee roles so that permissions are correct
- **As an admin**, I want to share the company code so that new employees can join

#### Scheduling & Calendar
- **As an admin**, I want to view calendar in month/week/day views so that I can see schedule at appropriate granularity
- **As an admin**, I want to filter calendar by team member so that I can see individual schedules
- **As an admin**, I want to create multi-day events so that I can schedule long-duration jobs
- **As an admin**, I want to see all team members' schedules so that I can coordinate work

#### Navigation
- **As an admin**, I want to get turn-by-turn directions to job sites so that I can navigate efficiently
- **As an admin**, I want to see project locations on a map so that I can visualize job distribution

#### Pipeline / CRM
- **As an admin**, I want to manage a pipeline of leads on my phone so that I can track sales opportunities in the field
- **As an admin**, I want to swipe opportunity cards to advance or mark deals as lost so that I can update pipeline status quickly
- **As an admin**, I want to log activities (notes, calls, emails, meetings, site visits) on opportunities so that I have a record of interactions
- **As an admin**, I want to see pipeline metrics (deals count, weighted value, total value) so that I understand my sales pipeline
- **As an admin**, I want to filter opportunities by stage so that I can focus on specific parts of the funnel
- **As an admin**, I want to view estimates, invoices, and accounting from the Pipeline tab so that all CRM data is in one place

#### Inventory
- **As an admin**, I want to track inventory items with quantities and units so that I know what materials I have on hand
- **As an admin**, I want to set warning and critical quantity thresholds so that I know when to reorder supplies
- **As an admin**, I want to organize inventory with tags so that I can categorize materials by type or use
- **As an admin**, I want to import inventory from spreadsheets (CSV/XLSX) so that I can onboard existing inventory quickly
- **As an admin**, I want to adjust quantities with quick +/- buttons so that inventory updates are fast on site
- **As an admin**, I want to view inventory snapshots so that I can see historical inventory levels

#### Photo Annotations
- **As an admin**, I want to draw on project photos so that I can mark up issues or instructions for my crew
- **As an admin**, I want to add text notes to annotated photos so that I can explain the markups

#### Notifications
- **As an admin**, I want to receive in-app notifications for mentions and project updates so that I stay informed
- **As an admin**, I want to tap a notification to navigate to the relevant project so that I can quickly review updates

#### Project Notes
- **As an admin**, I want to post timestamped notes on projects with @mentions so that my team can communicate in context
- **As an admin**, I want to see who posted each note and when so that I can track project communications

#### Crew Location
- **As an admin**, I want to see my crew's live locations on a map so that I can coordinate field operations
- **As an admin**, I want to see crew battery level and last update time so that I know their tracking status

#### Subscription
- **As an admin**, I want to view my subscription plan so that I know what I'm paying for
- **As an admin**, I want to upgrade my plan so that I can add more users
- **As an admin**, I want to see my trial countdown so that I know when payment starts
- **As an admin**, I want to enter payment details so that service continues after trial

#### Settings
- **As an admin**, I want to edit company profile so that information is accurate
- **As an admin**, I want to manage task types so that categories match my business
- **As an admin**, I want to set a PIN so that my data is secure
- **As an admin**, I want to restart the tutorial so that I can refresh my knowledge

### Office Crew

#### Project Management
- **As office crew**, I want to create projects so that I can schedule jobs for field crew
- **As office crew**, I want to edit project details so that information is current
- **As office crew**, I want to assign field crew to projects so that they know their assignments
- **As office crew**, I want to change project status so that I can track workflow
- **As office crew**, I want to view all projects so that I can coordinate schedules

#### Task Management
- **As office crew**, I want to create tasks so that I can break down project work
- **As office crew**, I want to schedule tasks so that field crew knows when to work
- **As office crew**, I want to assign field crew to tasks so that work is delegated
- **As office crew**, I want to update task status based on field reports so that status is accurate

#### Client Management
- **As office crew**, I want to create and edit client records so that I can manage customer data
- **As office crew**, I want to call or email clients so that I can communicate directly
- **As office crew**, I want to view client project history so that I understand relationships

#### Scheduling & Calendar
- **As office crew**, I want to view calendar in multiple formats so that I can plan efficiently
- **As office crew**, I want to filter calendar by crew member so that I can coordinate individual schedules
- **As office crew**, I want to create and edit calendar events so that I can manage schedules

#### Job Board
- **As office crew**, I want to view job board sections so that I can organize work by status
- **As office crew**, I want to see unscheduled projects so that I can prioritize scheduling
- **As office crew**, I want to search for projects so that I can find specific jobs quickly

#### Navigation
- **As office crew**, I want to see project locations so that I can coordinate logistics
- **As office crew**, I want to get directions to job sites so that I can visit in person if needed

#### Settings
- **As office crew**, I want to edit my profile so that my contact info is current
- **As office crew**, I want to set a PIN so that my data is secure
- **As office crew**, I want to access the tutorial so that I can learn features

### Field Crew

#### Authentication
- **As field crew**, I want to join a company using a code so that I can access my assignments
- **As field crew**, I want to complete the tutorial so that I understand how to use the app
- **As field crew**, I want to set a PIN so that my data is secure on my device

#### Job Board (Primary Interface)
- **As field crew**, I want to view job board dashboard so that I can see my assigned projects
- **As field crew**, I want to see only my assigned projects so that I'm not distracted by others' work
- **As field crew**, I want to see project status badges so that I know what stage each job is at
- **As field crew**, I want to see scheduled dates so that I know when work happens
- **As field crew**, I want to tap projects to view details so that I can get complete information

#### Project & Task Viewing
- **As field crew**, I want to view project details so that I understand the job
- **As field crew**, I want to view task details so that I know what work to do
- **As field crew**, I want to see client contact info so that I can communicate if needed
- **As field crew**, I want to see location addresses so that I know where to go
- **As field crew**, I want to see assigned team members so that I know who I'm working with

#### Status Updates
- **As field crew**, I want to change project status so that office knows progress
- **As field crew**, I want to change task status so that I can mark work as in progress or completed
- **As field crew**, I want to use swipe gestures to change status so that updates are quick
- **As field crew**, I want haptic feedback on status changes so that I get confirmation

#### Navigation
- **As field crew**, I want to get turn-by-turn directions to job sites so that I can navigate efficiently
- **As field crew**, I want navigation to work offline so that I can navigate in areas with poor signal
- **As field crew**, I want voice guidance so that I can navigate hands-free
- **As field crew**, I want to see ETA so that I can estimate arrival time

#### Photo Documentation
- **As field crew**, I want to capture photos of work so that I can document progress
- **As field crew**, I want photos to upload automatically when I have signal so that office sees updates
- **As field crew**, I want to view project photos so that I can see previous work
- **As field crew**, I want to annotate photos with drawings and notes so that I can highlight issues on site

#### Notifications
- **As field crew**, I want to receive notifications when I'm mentioned in a project note so that I can respond promptly
- **As field crew**, I want to tap a notification to go directly to the project so that I can see context quickly

#### Project Notes
- **As field crew**, I want to post notes on my assigned projects so that I can communicate updates to the office
- **As field crew**, I want to @mention team members in notes so that they get notified

#### Calendar & Schedule
- **As field crew**, I want to view my calendar so that I know my schedule
- **As field crew**, I want to see today's tasks so that I know what to do
- **As field crew**, I want to see scheduled dates for my tasks so that I can plan my work

#### Offline Work
- **As field crew**, I want the app to work without internet so that I can work anywhere
- **As field crew**, I want changes to sync when signal returns so that office gets updates
- **As field crew**, I want visual indication of sync status so that I know if data is current

#### Restrictions (What Field Crew CANNOT Do)
- **As field crew**, I cannot create projects (must be assigned by admin/office)
- **As field crew**, I cannot edit project dates or schedules (read-only)
- **As field crew**, I cannot edit task dates or schedules (read-only)
- **As field crew**, I cannot delete projects or tasks
- **As field crew**, I cannot create or edit clients
- **As field crew**, I cannot view job board sections (only dashboard view)
- **As field crew**, I cannot manage team members or roles
- **As field crew**, I cannot access company settings or subscription

---

## Business Rules & Constraints

### Data Integrity Rules

1. **Project-Task Relationship**
   - Every task must belong to a project
   - Deleting a project cascades to delete all tasks
   - Projects can exist without tasks (unscheduled projects)

2. **Calendar Event Requirements**
   - All calendar events must be linked to a task (task-only scheduling as of Nov 2025)
   - Calendar events require startDate and taskId
   - Multi-day events must have both startDate and endDate
   - Duration calculated as days between start and end dates

3. **Client-Project Association**
   - Projects can have zero or one client (optional relationship)
   - Clients can have multiple projects (one-to-many)
   - Deleting a client nullifies project.clientId (does not cascade delete projects)

4. **Team Assignment**
   - Users can be assigned to multiple projects and tasks
   - Team members must belong to the same company
   - Team assignments stored as comma-separated user IDs
   - Computed project team members derived from task assignments

5. **Company Membership**
   - All data entities belong to a company (companyId required)
   - Users can only belong to one company at a time
   - Company code is unique and used for employee onboarding
   - Company admins designated via company.adminIds array

### Status Workflow Rules

1. **Project Status Transitions**
   - Forward progression: RFQ → Estimated → Accepted → In Progress → Completed → Closed
   - Can archive from any status
   - Cannot move backwards in workflow (e.g., cannot go from Completed to In Progress)
   - Status changes trigger sync immediately

2. **Task Status Transitions**
   - Active is the initial state (replaces legacy "Booked"/"Scheduled"/"In Progress" which are all mapped to Active on decode)
   - Can move to Completed or Cancelled from Active
   - Cannot revert from Completed (must create new task)
   - Status changes trigger haptic feedback

3. **Task Type Management**
   - Default task types provided by system (cannot be deleted)
   - Custom task types can be created, edited, deleted
   - Task types require name, color, icon
   - Deleting task type does not cascade to tasks (tasks retain reference)

### Scheduling Rules

1. **Task-Only Scheduling (November 2025 Migration)**
   - All scheduling flows through task-linked calendar events
   - Project start/end dates computed from task calendar events
   - computedStartDate = earliest task startDate
   - computedEndDate = latest task endDate
   - Legacy project-level calendar events deleted during migration

2. **Date Calculations**
   - Duration = days between startDate and endDate (inclusive)
   - All-day flag determines time component (ignored if true)
   - Dates stored in UTC, displayed in local timezone

3. **Unscheduled Projects**
   - Projects with no tasks = unscheduled
   - Projects with tasks but no calendar events = unscheduled
   - Unscheduled badge displayed on job cards
   - Unscheduled section in job board shows these projects

### Permission Rules

1. **RBAC+ABAC Permission System (March 2026)**

   OPS uses a granular permission system with 5 preset roles, ~55 dot-notation permissions, and scope support (`all`, `assigned`, `own`). Permissions are stored in Supabase (`roles`, `role_permissions`, `user_roles` tables) and enforced at multiple layers (RLS, route guard, UI gating, API checks).

   **5 Preset Roles (hierarchy 1=highest to 5=lowest):**

   | Role | Hierarchy | Summary |
   |------|-----------|---------|
   | Admin | 1 | Full system access including billing, roles, and all settings |
   | Owner | 2 | Full access except billing and role assignment |
   | Office | 3 | Full project/financial access, no company settings or role management |
   | Operator | 4 | Lead tech — creates projects/estimates, edits assigned work only |
   | Crew | 5 | Field-only — views/edits assigned work, creates expenses |

   **Key Permission Matrix (scope in parentheses):**

   | Feature | Admin | Owner | Office | Operator | Crew |
   |---------|-------|-------|--------|----------|------|
   | View projects | all | all | all | all | assigned |
   | Create projects | all | all | all | all | — |
   | Edit projects | all | all | all | assigned | — |
   | Delete projects | all | all | — | — | — |
   | Create tasks | all | all | all | all | — |
   | Edit tasks | all | all | all | assigned | assigned |
   | Change task status | all | all | all | assigned | assigned |
   | View clients | all | all | all | all | assigned |
   | Create clients | all | all | all | all | — |
   | View calendar | all | all | all | all | own |
   | Edit calendar | all | all | all | own | — |
   | Job board sections | all | all | all | all | assigned |
   | Pipeline | all | all | all | — | — |
   | Estimates (view/create) | all | all | all | all / own | — |
   | Invoices (view) | all | all | all | all | — |
   | Expenses (view/create) | all | all | all | own | own |
   | Expenses (approve) | all | all | all | — | — |
   | Inventory | all | all | all | — | — |
   | Team management | all | all | — | — | — |
   | Assign roles | all | — | — | — | — |
   | Company settings | all | all | — | — | — |
   | Billing settings | all | — | — | — | — |
   | Map crew locations | all | all | all | — | — |
   | Photos (view/upload) | all | all | all | all | assigned |
   | Notifications | own | own | own | own | own |

   *See `03_DATA_ARCHITECTURE.md` > Permissions System Tables for the complete schema and full permission grants per role.*

2. **Role Assignment**
   - Each user has exactly one role (stored in `user_roles` table, 1:1 relationship)
   - Roles are assigned by users with the `team.assign_roles` permission (Admin only by default)
   - New users without a role assignment fall back to the legacy `user.role` field for backward compatibility
   - Custom roles can be created per company with any combination of the ~55 permissions

3. **Legacy Role Detection (being replaced)**
   - The old system checked `company.adminIds` first, then `user.employeeType`, defaulting to Field Crew
   - This is superseded by the `user_roles` table but remains as a fallback during transition

4. **Subscription-Based Access**
   - Trial: 30 days, all features, 10 seats
   - Expired: Lockout screen, no app access
   - Active paid: All features, seat limit enforced

### Sync Rules

1. **Conflict Resolution**
   - Local changes pushed first (needsSync = true)
   - Then fetch from server and replace local data
   - Server always wins in conflicts
   - No merge logic (last write wins)

2. **Sync Priority**
   - Priority 3: Critical updates (status changes, new projects)
   - Priority 2: Important updates (edits to existing data)
   - Priority 1: Low priority (metadata updates)
   - Priority 0: Background updates
   - Higher priority items sync first

3. **Soft Delete**
   - Items missing from server response marked as deleted locally
   - deletedAt timestamp set
   - Items excluded from queries by default
   - Hard delete not implemented (preserves data integrity)

4. **Sync Debouncing**
   - 2-second delay on immediate sync
   - Prevents duplicate syncs from rapid user actions
   - Debounce timer resets with each new change
   - After 2 seconds of inactivity, sync executes

5. **Image Sync**
   - Images sync separately from data entities
   - S3 presigned URLs obtained from backend
   - Local images queued until connectivity available
   - Synced images stored as comma-separated URLs

### BubbleFields Mapping Rules

1. **Field Name Parity**
   - BubbleFields constants must match Bubble database fields exactly (byte-identical)
   - Swift property names can differ (e.g., Swift `title` = Bubble `"title"`)
   - DTO conversion uses BubbleFields constants exclusively

2. **Date Handling**
   - CompanyDTO dates can be UNIX timestamps OR ISO8601 strings (Stripe vs Bubble)
   - Parse both formats, store as Date objects
   - Send dates to Bubble as ISO8601 strings

3. **Phone Number Handling**
   - SubClientDTO phone can be String or Number type
   - Parse both formats, store as String
   - Validate phone format on display

4. **Enum Mapping**
   - Task status enum values: `active`, `completed`, `cancelled`
   - DTOs handle backward compatibility: legacy values "Scheduled", "Booked", "booked", "In Progress", "in_progress" all map to `.active`; "Completed" maps to `.completed`; "Cancelled" maps to `.cancelled`
   - Send lowercase values (`active`, `completed`, `cancelled`) to Supabase

---

## Offline-First Requirements

### Core Principle
The app must function fully without internet connectivity. All features must be accessible and usable offline, with changes queued for sync when connectivity returns.

### Offline Data Access

1. **Local Data Persistence**
   - All data stored locally in SwiftData
   - Read operations always use local data (no API calls for reads)
   - Write operations update local data immediately
   - Sync happens asynchronously in background

2. **Offline Feature Access**
   - ✅ View projects, tasks, clients
   - ✅ Create projects, tasks, clients
   - ✅ Edit projects, tasks, clients
   - ✅ Change status of projects and tasks
   - ✅ View calendar and schedules
   - ✅ Navigate to job sites (offline maps)
   - ✅ Capture photos (stored locally)
   - ❌ Sync data to server (requires connectivity)
   - ❌ Fetch updates from server (requires connectivity)

### Sync Queue Management

1. **Change Tracking**
   - needsSync flag set on all modified entities
   - syncPriority assigned based on change type
   - lastSyncedAt timestamp tracks sync state
   - Changes persist in local database until synced

2. **Connectivity Monitoring**
   - ConnectivityMonitor tracks network status
   - Notifies SupabaseSyncManager when connectivity restored
   - Visual indicator in UI shows sync status
   - User can manually trigger sync

3. **Automatic Sync Triggers**
   - App launch (if connectivity available)
   - App foreground (if connectivity available)
   - Connectivity restored (from offline to online)
   - Manual refresh (pull-to-refresh)

4. **Sync Failure Handling**
   - Failed syncs retry after 3 minutes
   - Max retries: Unlimited (will keep trying)
   - User notified of sync failures
   - Can continue working offline despite failures

### Offline Navigation

1. **Map Tiles**
   - MapKit caches map tiles automatically
   - Previously viewed areas available offline
   - No manual map download required
   - Cached tiles expire per iOS policy

2. **GPS Functionality**
   - GPS works without internet (satellite-based)
   - Kalman filter smooths GPS data
   - Turn-by-turn guidance works offline
   - Route calculation requires initial connectivity (then cached)

### Offline Image Handling

1. **Image Capture**
   - Photos captured and stored locally
   - Images added to unsyncedImagesString
   - Displayed in UI immediately from local storage
   - Upload queued for when connectivity available

2. **Image Sync**
   - Images uploaded to S3 when online
   - S3 URLs replace local URLs in projectImagesString
   - Local images deleted after successful sync
   - Failed uploads retry automatically

### User Experience for Offline State

1. **Visual Indicators**
   - Sync status icon in UI (syncing, synced, offline)
   - "Offline" badge or banner when no connectivity
   - Timestamp of last successful sync
   - Count of pending changes (e.g., "3 changes pending sync")

2. **User Messaging**
   - "You're offline. Changes will sync when you're back online."
   - "Syncing..." during active sync
   - "Last synced: 2 minutes ago"
   - "Sync failed. Will retry automatically."

3. **No Blocking Operations**
   - Never block UI waiting for network
   - Never show loading spinners for network calls
   - Instant feedback for all user actions
   - Graceful degradation if sync fails

---

## Field-Specific Requirements

### Environmental Constraints

1. **Glove Usability**
   - Minimum touch target: 44×44pt (prefer 56×56pt)
   - Large buttons and controls
   - Avoid fine-grain gestures (e.g., small swipe distances)
   - Test with work gloves on actual device

2. **Sunlight Readability**
   - High contrast dark theme (pure black background)
   - Light text (#E5E5E5) on dark background
   - Avoid subtle color differences
   - Status colors distinct and vibrant
   - Test in direct sunlight

3. **Battery Life**
   - Dark theme reduces power consumption
   - Minimize background location tracking
   - Efficient GPS filtering (Kalman filter)
   - Optimize image compression
   - Reduce animation complexity

4. **Poor Connectivity**
   - Offline-first architecture (see above)
   - No reliance on real-time data
   - Graceful degradation without network
   - Automatic retry logic
   - User never blocked by network issues

5. **Device Age**
   - Support older iOS devices (iOS 17+)
   - Optimize performance for slower processors
   - Minimize memory usage
   - Test on oldest supported devices
   - Avoid cutting-edge APIs requiring newest hardware

### Physical Context

1. **Dirty Hands & Devices**
   - Simple navigation requiring minimal taps
   - Swipe gestures for common actions
   - Large, forgiving touch areas
   - No requirement for precise input

2. **Noisy Environments**
   - Haptic feedback for confirmations
   - Visual status indicators (not just audio)
   - Clear, high-contrast UI elements
   - No reliance on audio cues

3. **One-Handed Operation**
   - Critical actions at bottom of screen (thumb zone)
   - Avoid top-corner buttons
   - Bottom navigation tabs
   - Floating action buttons for primary actions

4. **Interrupted Workflows**
   - Auto-save all inputs
   - No data loss on app background
   - Quick resume to last viewed screen
   - PIN resets on background (security without losing work)

### Workflow Optimization

1. **Minimal Text Entry**
   - Prefer pickers and toggles over text fields
   - Autocomplete and suggestions
   - Import from device contacts
   - Reuse data (e.g., copy project details)

2. **Quick Status Updates**
   - Swipe-to-change-status gesture
   - One-tap status pills
   - Immediate haptic feedback
   - No confirmation dialogs for non-destructive actions

3. **Photo-Centric Documentation**
   - In-app camera (no leaving app)
   - Quick capture workflow
   - Automatic upload queue
   - Gallery view with full-screen zoom

4. **Navigation-Centric**
   - "Get Directions" button prominent
   - One-tap to launch navigation
   - Integration with native Maps app
   - ETA display for planning

### Testing Requirements

1. **Field Testing Checklist**
   - ✅ Wear work gloves and test all interactions
   - ✅ Test in direct sunlight at noon
   - ✅ Test in complete darkness (night work)
   - ✅ Test with no connectivity (airplane mode)
   - ✅ Test with intermittent connectivity (toggle on/off rapidly)
   - ✅ Test on 3+ year old device
   - ✅ Test with battery at 20% or less
   - ✅ Test with notifications interrupting workflow
   - ✅ Test with phone calls interrupting navigation
   - ✅ Test in vehicle (moving GPS)

2. **Usability Validation**
   - Can a tradesperson use this without training?
   - Does it work in a work truck between job sites?
   - Can field crew update status without office support?
   - Are all critical features accessible in < 3 taps?

---

## Subscription & Access Control

### Subscription Tiers

1. **Trial (30 Days)**
   - All features enabled
   - 10 seats included
   - No credit card required
   - Trial countdown displayed
   - Ends automatically after 30 days

2. **Starter ($90/month)**
   - All features
   - 3 seats included
   - Additional seats not available
   - Upgrade path to Team

3. **Team ($140/month)**
   - All features
   - 5 seats included
   - Additional seats not available
   - Upgrade path to Business

4. **Business ($190/month)**
   - All features
   - 10 seats included
   - Contact for > 10 seats

5. **Annual Plans**
   - 20% discount on all tiers
   - Starter Annual: $864/year (save $216)
   - Team Annual: $1,344/year (save $336)
   - Business Annual: $1,824/year (save $456)

### Subscription Enforcement

1. **Active Subscription**
   - Full access to all features
   - Can add users up to seat limit
   - Can create unlimited projects, tasks, clients
   - Can upload unlimited photos

2. **Expired Subscription**
   - Lockout screen displayed
   - No access to any app features
   - Data preserved (not deleted)
   - Can reactivate subscription to restore access

3. **Seat Limit Enforcement**
   - Cannot add users beyond seat limit
   - Error message: "Upgrade your plan to add more users"
   - Existing users not affected
   - Can remove users to free seats

### Subscription Manager

1. **SubscriptionManager Service**
   - Checks CompanyDTO subscription fields
   - subscriptionActive: Bool
   - trialEndDate: Date?
   - subscriptionEndDate: Date?
   - maxSeats: Int

2. **Subscription Status Calculation**
   - If in trial: Check trialEndDate > now
   - If paid: Check subscriptionActive && subscriptionEndDate > now
   - Otherwise: Expired

3. **Lockout Behavior**
   - Lockout screen covers entire app
   - Shows expiration message
   - "Renew Subscription" button
   - Links to Stripe payment portal (via Bubble)

---

### 14. Pipeline / CRM (iOS & OPS Web)

#### Pipeline Board — OPS Web
- **9-Stage Kanban Board** — New Lead, Qualifying, Quoting, Quoted, Follow-Up, Negotiation, Won, Lost, Discarded
- **Drag-and-Drop** — Move opportunities between stages via @dnd-kit
- **Stage Transitions** — Every stage move recorded as immutable history
- **Win Probability** — Per-stage default + per-opportunity override
- **Weighted Pipeline Value** — estimatedValue × winProbability
- **Stale Indicators** — Cards flagged if no activity within threshold (7 days default)
- **Days in Stage** — Displayed on each card
- **Won/Lost Prompts** — Loss reason required when moving to Lost; actual value for Won
- **Discard** — Terminal stage for leads not worth pursuing. No confirmation dialog. Discarded leads stay in the system for analytics but are off the active board. Enables ad targeting quality measurement: won+lost (real leads) vs discarded (junk quality).
- **Terminal Columns** — Won, Lost, and Discarded are separate from active stages. Won/Lost shown in metrics bar with expandable deal lists. Discarded count shown in metrics bar for ad quality tracking.

#### Pipeline Tab — iOS
The Pipeline tab on iOS is a dedicated tab that appears conditionally based on the user having the `pipeline` special permission. It contains a segmented nav with four sections: **Pipeline**, **Estimates**, **Invoices**, and **Accounting**.

**Pipeline Section (iOS):**
- **Stage-Filtered List** — Opportunities displayed as cards, filterable by stage via a horizontal scrollable stage strip (PipelineStageStrip). Each stage chip shows a stage-colored dot and count.
- **Metrics Strip** — Displays active deals count, weighted pipeline value, and total pipeline value as metric pills.
- **Search** — Search bar to filter deals by contact name.
- **Opportunity Cards** — Each card shows contact name, estimated value, job description, stage indicator (colored dot + name), days in stage, and stale warning icon. Cards use a left color stripe matching the stage color.
- **Swipe Gestures** — Swipe right to advance to next stage (green reveal); swipe left to mark as lost (red reveal).
- **Opportunity Detail View** — Full detail view with three sub-tabs: Details (contact info, deal info), Activity (logged activities), and Follow-Ups (scheduled reminders). Includes "Advance to [Next Stage]" button and overflow menu (Edit, Mark Won, Mark Lost, Delete).
- **Create/Edit Opportunities** — OpportunityFormSheet with contact fields (name, phone, email), deal details (job description, estimated value, source picker). Source options: Referral, Website, Email, Phone, Walk-in, Social Media, Other.
- **Log Activity** — ActivityFormSheet supports types: Note, Call, Email, Meeting, Site Visit. Each activity includes a notes field.
- **Mark as Lost** — MarkLostSheet requires a loss reason before confirming.

**Estimates Section (iOS):**
- EstimatesListView (content managed in Pipeline tab)

**Invoices Section (iOS):**
- InvoicesListView (content managed in Pipeline tab)

**Accounting Section (iOS):**
- AccountingDashboard (content managed in Pipeline tab)

**Pipeline Stages (Shared iOS & Web):**
- `PipelineStage` enum: newLead, qualifying, quoting, quoted, followUp, negotiation, won, lost, discarded
- Terminal stages: won, lost, and discarded (cannot advance further)
- Discarded = "not worth pursuing" — distinct from lost (which implies a real opportunity that didn't close)
- Each stage has a display name, color, and `next` stage for progression

#### Lead Management
- **Create Leads** — With or without an existing client record (inline contact fields)
- **Lead Sources** — Referral, Website, Email, Phone, Walk-In, Social Media, Repeat Client, Other
- **Priority Levels** — Low, Medium, High
- **Expected Close Date** — With overdue indicators
- **Tags** — Free-form tagging
- **Address** — Job site address for the lead

#### Activity Timeline
- **Activity Types** — Note, Email, Call, Meeting, Estimate Sent/Accepted/Declined, Invoice Sent, Payment Received, Stage Change, Created, Won, Lost, Site Visit, System
- **Direction** — Inbound or Outbound (for calls/emails)
- **Duration** — For calls and meetings

#### Follow-Ups
- **Scheduled Reminders** — Call, Email, Meeting, Quote Follow-Up, Invoice Follow-Up, Custom
- **Auto-Generated** — Created automatically based on stage `autoFollowUpDays` config
- **Assignment** — Assign follow-ups to specific users
- **Status** — Pending, Completed, Skipped
- **Reminder Time** — Separate reminder timestamp before due date

#### Per-Company Stage Configuration
- **Custom Stage Colors** — Per stage, per company
- **Stale Threshold** — Per stage (days before marking as stale)
- **Auto Follow-Up Rules** — Days after stage entry to auto-create follow-up
- **Win Probability Defaults** — Per stage

### 15. Estimates (OPS Web)

#### Estimate Creation & Editing
- **Create Estimates** — Title, client, opportunity link, issue date, expiration date
- **Line Items** — Name, description, quantity, unit, unit price, discount %, taxable flag
- **Optional Line Items** — Items client can include/exclude from the quote
- **Products Catalog** — Auto-fill line items from saved products/services
- **Tax Configuration** — Per-line-item taxable flag, document-level tax rate
- **Discount** — Percentage or fixed-amount at document level
- **Deposit/Payment Schedule** — Deposit type (percentage or fixed) + payment milestones
- **Client Message** — Customer-facing note on the estimate
- **Internal Notes** — Staff-only notes
- **Terms & Conditions** — Custom terms text
- **Version Control** — Revisions tracked via `version` and `parentId`

#### Estimate Workflow
- **Status Flow** — Draft → Sent → Viewed → Approved → Converted (to Invoice)
- **Changes Requested** — Client can request changes, moves back to editable state
- **Expiration** — Estimates expire past their `expirationDate` if not Approved/Converted
- **Send Estimate** — Marks status = Sent with timestamp
- **Convert to Invoice** — Atomic RPC: validates Approved status, creates invoice, copies line items, marks estimate as Converted
- **Estimate Numbers** — Sequential, auto-generated server-side: EST-0001, EST-0002, etc.

#### Estimate Viewing
- **PDF Storage** — PDF path stored in `pdfStoragePath`
- **Filter by Status/Client/Opportunity** — Flexible fetch options

### 16. Invoices (OPS Web)

#### Invoice Creation & Management
- **Create Invoices** — From scratch or by converting an Approved estimate
- **Line Items** — Same structure as estimates (shared `line_items` table)
- **Subject/Footer** — Additional header and footer fields vs. estimates
- **Due Date + Payment Terms** — "Net 30", "Due on Receipt", etc.
- **Link to Project** — Optionally link invoice to a Bubble project
- **Invoice Numbers** — Sequential, auto-generated: INV-0001, INV-0002, etc.

#### Invoice Payment Tracking
- **Record Payments** — Amount, method (Cash, Check, Credit Card, ACH, Bank Transfer, Stripe, Other), reference number, date
- **Balance Calculation** — DB trigger maintains `amount_paid`, `balance_due` after each payment
- **Status Auto-Update** — Trigger updates status: AwaitingPayment → PartiallyPaid → Paid
- **Void Payments** — Set `voided_at`/`voided_by` (NOT deleted_at); trigger recalculates balance
- **Void Invoice** — Sets status = Void (no access to payment recording)
- **Past Due Tracking** — Status transitions to PastDue after dueDate with balance > 0

#### Invoice Status Flow
```
Draft → Sent → AwaitingPayment → PartiallyPaid → Paid
                               → PastDue → Paid | WrittenOff
→ Void (from any non-Paid status)
```

### 17. Products & Services Catalog (OPS Web)

- **Create Products** — Name, description, default price, unit cost, unit, category, taxable flag
- **Active/Inactive** — Deactivate products without deleting them
- **Margin Tracking** — `unitCost` stored for profit margin calculation per line item
- **Catalog Integration** — Line items in estimates/invoices can reference catalog items
- **Soft Delete** — Products soft-deleted; existing line items retain their snapshot data

### 18. Accounting Integrations (OPS Web)

- **QuickBooks OAuth** — Connect company QuickBooks account
- **Sage OAuth** — Connect company Sage account
- **Token Storage** — OAuth tokens, refresh tokens, expiry stored securely in Supabase
- **Sync Control** — Enable/disable sync per connection
- **Webhook Support** — Webhook verifier token stored for incoming webhooks
- *Full bidirectional sync implementation: planned/in progress*

### 19. In-App Notifications (iOS)

#### Notification System
- **Notification List View** — Accessible from the app header, shows recent notifications in a scrollable list with unread indicators (blue dot), notification icon by type, title, body, and relative timestamp.
- **Notification Types** — `mention` (blue accent icon), `assignment` (green icon), `update` (gray icon), and generic/default (gray bell icon).
- **Notification DTO** — Each notification has: id, userId, companyId, type, title, body, optional projectId, optional noteId, isRead flag, and createdAt timestamp.
- **Mark as Read** — Individual notifications marked as read on tap. "Mark All Read" button in toolbar clears all unread.
- **Deep Linking** — Tapping a notification with a projectId dismisses the notification list and navigates to the project details view.
- **Unread Count** — `appState.unreadNotificationCount` tracks unread count, updated on load and on tap.
- **Notification Banner** — Slide-down banner (NotificationBanner) for transient in-app alerts with success/error/info types, auto-dismisses after 2 seconds.

#### Push Notifications
- **OneSignal Integration** — Push notifications via OneSignal SDK.
- **Notification Categories** — Project, Schedule, Team, General, Project Assignment, Project Update, Project Completion, Project Advance.
- **Deep Link Handlers** — Push notifications can deep-link to: project details (OpenProjectDetails), task details (OpenTaskDetails), schedule view (OpenSchedule), job board (OpenJobBoard).
- **Sync on Deep Link** — If the target project/task is not found locally, a full sync is triggered before navigation.

#### Notification Settings
- **NotificationSettingsView** — Allows users to configure notification preferences.
- **Per-Project Preferences** — ProjectNotificationPreferences for granular control.
- **Notification Batching** — NotificationBatcher coalesces rapid notifications.

### 20. Photo Annotations (iOS)

#### Annotation System
- **PencilKit Drawing Canvas** — Full-screen annotation view (PhotoAnnotationView) overlays a PencilKit canvas on top of project photos for freehand drawing.
- **Drawing Tools** — Default tool is a thin white pen (3pt width). Full PencilKit tool picker available (pen, marker, pencil, eraser, ruler, color picker) via the system PKToolPicker.
- **Input Support** — Works with both finger and Apple Pencil (`drawingPolicy = .anyInput`), optimized for field use without a stylus.
- **Undo/Clear** — Undo last stroke button and full clear drawing button.
- **Text Notes** — Bottom bar text field for adding a text note alongside the drawing annotation.
- **Save to Supabase** — Annotations saved via PhotoAnnotationSyncManager. The drawing is rendered as a transparent PNG overlay and uploaded to cloud storage. The annotation URL is stored alongside the original photo URL.
- **Offline Support** — PKDrawing data stored locally (`localDrawingData` on the PhotoAnnotation model) for offline editing. Synced when connectivity is available.

#### Data Model
- **PhotoAnnotation** — SwiftData model: id, projectId, companyId, photoURL, annotationURL (cloud-rendered overlay), note (text), authorId, createdAt, updatedAt, deletedAt, localDrawingData (PKDrawing binary), needsSync flag.
- **Supabase Sync** — PhotoAnnotationRepository handles CRUD operations. PhotoAnnotationSyncManager handles rendering and uploading the drawing overlay.

### 21. Inventory Management (iOS)

#### Inventory Tab
- **Conditional Tab** — The Inventory tab appears in the tab bar only for users with `inventoryAccess` set to `true` on their user profile. Uses the `shippingbox.fill` SF Symbol icon.
- **Inventory View** — Main view (InventoryView) with search, tag filtering, sort options (Tag, Name, Quantity, Threshold), and pinch-to-zoom card scaling (0.8x to 1.5x, persisted in AppStorage).

#### Item Management
- **Create Items** — InventoryFormSheet with name, quantity, unit (from company-defined units), tags, SKU/part number, description, notes, and quantity thresholds (warning + critical levels).
- **Edit Items** — Same form sheet in edit mode with pre-populated fields and delete option.
- **Quantity Adjustment** — Dedicated QuantityAdjustmentSheet with large quantity display, configurable quick-adjust buttons (-100, -50, -10, -1, +1, +10, +50, +100), direct-entry editing, and change indicator showing old → new value. Adjustment settings persisted in UserDefaults.
- **Bulk Quantity Adjustment** — BulkQuantityAdjustmentSheet applies the same adjustment to all selected items simultaneously with preview of each item's new quantity.
- **Selection Mode** — Long-press to enter multi-select mode with selection stripe indicators, enabling bulk operations.

#### Tag System
- **Item Tags** — Free-form tags per item, displayed as monochromatic badges. Tags are company-scoped InventoryTag entities with their own Supabase sync.
- **Tag Management** — InventoryManageTagsSheet for renaming or deleting tags globally across all items, with item count per tag and search.
- **Bulk Tag Editing** — BulkTagsSheet for adding/removing tags across multiple selected items, with create-new-tag inline, pending changes preview, and available/current tag sections.
- **Predictive Tag Input** — Tag input field shows matching suggestions from existing company tags as the user types.

#### Inventory Cards
- **Progressive Disclosure** — Card detail scales with pinch-to-zoom: at minimum scale only name and quantity shown; at 0.9x tags appear; at 1.0x full metadata (SKU, threshold badges) visible.
- **Threshold Status** — Items show color-coded threshold badges (warning/critical) based on per-item or per-tag threshold settings.
- **Long-Press Actions** — Context menu for Select, Edit, Delete on each card.

#### Snapshots
- **Inventory Snapshots** — SnapshotListView displays historical snapshots of inventory state. Each snapshot records item count, creation timestamp, and whether it was automatic or manual.
- **Snapshot Detail** — Shows summary (date, type, items count) and a list of all items at that point in time with their quantities and units.

#### Spreadsheet Import
- **File Import** — SpreadsheetImportSheet supports CSV and XLSX file import via iOS file picker.
- **Import Wizard** — 5-step flow: Select File → Configure (data orientation, import mode) → Map Fields (column-to-field mapping) → Preview (with duplicate detection against existing inventory) → Import (progress bar with per-item status).
- **Import Modes** — Multiple Items (standard row-per-item), Single Item (one item from row data), Variations (grid format where rows are items and columns are variations).
- **Duplicate Detection** — Imported items compared against existing company inventory for name matches.

#### Data Model
- **InventoryItem** — SwiftData model with: id, name, quantity, companyId, unitId, itemDescription, sku, notes, imageUrl, warningThreshold, criticalThreshold, tagIds, tagNames (computed), unit relationship, tags relationship.
- **InventoryTag** — Company-scoped tag entity with name, optional warning/critical thresholds. Synced to Supabase via junction table (item_tags).
- **InventoryUnit** — Company-defined units (e.g., "pcs", "ft", "lbs") with display label and sort order.
- **Supabase Sync** — InventoryRepository handles CRUD for items, tags, units, and snapshots. Tag-item relationships managed via `setItemTags` junction table operations.

### 22. Crew Location Tracking (iOS)

#### Location Broadcasting
- **CrewLocationBroadcaster** — Broadcasts the current user's GPS location when clocked in. Publishes updates locally (via NotificationCenter) and persists to Supabase `crew_locations` table via upsert.
- **Adaptive Frequency** — When moving (speed > 1 m/s): broadcasts every 5 seconds, persists every 10 seconds. When stationary: broadcasts every 30 seconds, persists every 60 seconds.
- **Noise Filtering** — Rejects stale readings (>10s old), inaccurate readings (>50m accuracy), and identical consecutive coordinates.
- **Battery & Background** — Tracks device battery level and foreground/background state in each update.

#### Location Subscribing
- **CrewLocationSubscriber** — Subscribes to crew location updates for the current organization. Loads initial state from Supabase DB, listens for local broadcasts, and polls the DB every 15 seconds for updates from other devices.
- **Live Map** — `crewLocations` dictionary keyed by userId provides real-time crew positions for map display.

#### Location Data Model
- **CrewLocationUpdate** — Struct containing: userId, orgId, firstName, lastName, lat, lng, heading, speed, accuracy, timestamp, batteryLevel, isBackground, currentTaskName, currentProjectName, currentProjectId, currentProjectAddress, phoneNumber.
- **Map Annotations** — CrewAnnotationRenderer and ProjectAnnotationRenderer display crew members and projects on the map with custom annotations.

### 23. Dynamic Tab Bar (iOS)

#### Tab Configuration
The iOS tab bar is **dynamic** — tabs are computed at runtime based on user permissions and company settings. There is **no standalone Map tab**. The tab bar is rendered by `CustomTabBar` which accepts an array of `TabItem` and displays a sliding accent-colored indicator bar.

**Base Tabs (always present):**
1. **Home** — `house.fill` icon. Displays HomeView with map and active project info.
2. **Job Board** — `briefcase.fill` icon. Displays JobBoardView. Visible to all roles (admin, office crew, field crew).
3. **Schedule** — `calendar` icon. Displays ScheduleView.
4. **Settings** — `gearshape.fill` icon. Displays SettingsView. Always the last tab.

**Conditional Tabs:**
- **Pipeline** — `chart.bar.xaxis` icon (OPSStyle.Icons.pipelineChart). Inserted after Home, before Job Board. Visible only to users with `pipeline` in their `specialPermissions` array. Displays PipelineTabView.
- **Inventory** — `shippingbox.fill` icon. Inserted after Job Board, before Schedule. Visible only to users with `inventoryAccess = true`. Displays InventoryView.

**Tab Index Computation:**
- Tab indices are dynamically computed based on which conditional tabs are active.
- `selectedTab` is reset to 0 (Home) if the current tab index becomes invalid after a permission change.
- Tab count changes trigger indicator position recalculation in CustomTabBar.
- The Floating Action Menu is hidden on Settings and Pipeline tabs.

---

## Future Features (Roadmap)

Based on survey feedback from target market, these features are planned:

1. **Email Integration**
   - Send estimates and invoices via email
   - Gmail OAuth integration (underway)
   - Email templates
   - Attachment support (PDFs)

2. **Commission Tracking**
   - Track sales commission for estimators
   - Door-knocker commission
   - Commission reports per user
   - Payment history

3. **Photo Markup** (iOS implementation complete — see Feature 20 below; web planned via Notes Overhaul)
   - ~~Captions on photos~~ (implemented on iOS as text notes per annotation)
   - ~~Arrows and annotations~~ (implemented on iOS via PencilKit drawing canvas)
   - Notes and labels
   - Before/after comparisons

4. **Recurring Schedules**
   - Auto-populate weekly jobs (e.g., every Monday)
   - Bi-weekly schedules
   - Monthly schedules
   - Recurring project templates

5. **Materials/Inventory Tracking** (iOS implementation complete — see Feature 21 below)
   - ~~Inventory management~~ (implemented on iOS with full CRUD, tags, units, thresholds, snapshots, spreadsheet import)
   - Materials list per job (not yet implemented)
   - Purchase orders (not yet implemented)
   - Material cost tracking (not yet implemented)

6. **Time-Specific Scheduling**
   - Schedule tasks with specific times (not just dates)
   - 8:00 AM - 12:00 PM
   - Multiple crews with different start times
   - Time-based calendar views

7. **Full Accounting Sync**
   - QuickBooks/Sage two-way sync
   - Invoice export to accounting software
   - Payment import from accounting software

---

**Last Updated:** February 28, 2026
**Document Version:** 1.3
**iOS App Version:** iOS 17+, SwiftData + SwiftUI. Features include: Pipeline/CRM, Inventory, Photo Annotations, In-App Notifications, Project Notes, Crew Location Tracking, Dynamic Tab Bar.
**Web App:** Pipeline, Estimates, Invoices, Products, Project Notes live in ops-web (Supabase)
