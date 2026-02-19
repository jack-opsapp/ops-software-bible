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
- **Project Notes System (OPS Web)** - First-class notes with @mentions, author attribution, timestamps, and photo attachments (replaces legacy plain-text teamNotes field from Bubble; see [07_SPECIALIZED_FEATURES.md](07_SPECIALIZED_FEATURES.md) Section 11)

#### Project Viewing
- **Project Details View** - Comprehensive project overview
- **Status Badge** - Color-coded status indicator
- **Breadcrumb Navigation** - Company → Client → Project hierarchy
- **Location Card** - Address display with "Get Directions" button
- **Client Info Card** - Client contact details with tap-to-call/email
- **Notes Card** - Expandable notes section (iOS: plain text; OPS Web: threaded notes with @mentions, author attribution, photo attachments — see [07_SPECIALIZED_FEATURES.md](07_SPECIALIZED_FEATURES.md) Section 11)
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
- **Task Status Workflow** - Booked → In Progress → Completed (or Cancelled)
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
- **Weekly View** - Week-at-a-glance with time slots
- **Daily View** - Single-day schedule detail
- **Timeline View** - Chronological project/task list
- **Today View** - Focus on current day's schedule

#### Calendar Event Management
- **Create Events** - Linked to tasks (task-only scheduling as of Nov 2025)
- **Edit Events** - Update dates, duration, team assignments
- **Delete Events** - Remove scheduling (soft delete)
- **Multi-Day Events** - Span events across multiple days
- **Duration Management** - Calculate duration from start/end dates
- **Team Assignment** - Assign crew to calendar events
- **Color Coding** - Events inherit task type colors

#### Filtering & Organization
- **Filter by Team Member** - View only assigned events
- **Filter by Status** - Show/hide completed, cancelled events
- **Filter by Project** - Isolate events for specific projects
- **Date Range Selection** - Custom date range views

### 5. Job Board

#### View Modes
- **Dashboard View** - Overview of active projects
- **Section View** - Organize by custom sections (Unscheduled, This Week, Next Week, etc.)
- **Search & Filter** - Find projects by title, client, status

#### Job Board Sections
- **Predefined Sections:**
  - Unscheduled (projects with no tasks or no calendar events)
  - This Week (tasks scheduled for current week)
  - Next Week (tasks scheduled for next week)
  - In Progress (tasks marked as in progress)
  - Completed (tasks marked as completed)
  - All Projects (comprehensive list)

- **Custom Sections** - Create user-defined organizational sections
- **Collapsible Sections** - Expand/collapse for focus
- **Section Reordering** - Drag to reorder sections

#### Universal Job Card
- **Project Title** - Primary identifier
- **Client Name** - Associated client
- **Status Badge** - Color-coded project status
- **Unscheduled Badge** - Indicates projects with no scheduled tasks
- **Date Display** - Scheduled start/end dates
- **Team Avatars** - Assigned crew members
- **Location Indicator** - Address snippet
- **Quick Actions** - Swipe actions for common tasks

#### Role-Based Access
- **Admin** - Full access to all projects, all sections
- **Office Crew** - Full access to all projects, all sections
- **Field Crew** - Access only to assigned projects, dashboard view only (no section picker)

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
- **CentralizedSyncManager** - Orchestrates all sync operations
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
- **Notification Preferences** - (Future feature)
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
   - Booked (formerly Scheduled) is initial state
   - Can move to In Progress or Cancelled from Booked
   - Can move to Completed from In Progress
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

1. **Role-Based Permissions**

   | Feature | Admin | Office Crew | Field Crew |
   |---------|-------|-------------|------------|
   | View all projects | ✅ | ✅ | ❌ (assigned only) |
   | Create projects | ✅ | ✅ | ❌ |
   | Edit projects | ✅ | ✅ | ❌ |
   | Delete projects | ✅ | ✅ | ❌ |
   | Change project status | ✅ | ✅ | ✅ |
   | Create tasks | ✅ | ✅ | ❌ |
   | Edit tasks | ✅ | ✅ | ❌ |
   | Delete tasks | ✅ | ✅ | ❌ |
   | Change task status | ✅ | ✅ | ✅ |
   | Schedule tasks | ✅ | ✅ | ❌ |
   | Create clients | ✅ | ✅ | ❌ |
   | Edit clients | ✅ | ✅ | ❌ |
   | Delete clients | ✅ | ✅ | ❌ |
   | View calendar | ✅ | ✅ | ✅ |
   | Edit calendar | ✅ | ✅ | ❌ |
   | View job board sections | ✅ | ✅ | ❌ (dashboard only) |
   | Company settings | ✅ | ❌ | ❌ |
   | Subscription management | ✅ | ❌ | ❌ |
   | Manage team members | ✅ | ❌ | ❌ |
   | Take photos | ✅ | ✅ | ✅ |
   | Get directions | ✅ | ✅ | ✅ |

2. **Role Detection Logic**
   - Check company.adminIds first (explicit admin designation)
   - Then check user.employeeType field
   - Default to Field Crew if no explicit role set

3. **Subscription-Based Access**
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
   - Status enums: "Scheduled" renamed to "Booked" (Nov 2025)
   - DTOs handle backward compatibility (map "Scheduled" to .booked)
   - Send "Booked" to Bubble (API updated Nov 2025)

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
   - Notifies CentralizedSyncManager when connectivity restored
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

### 14. Pipeline / CRM (OPS Web)

#### Pipeline Board
- **8-Stage Kanban Board** — New Lead, Qualifying, Quoting, Quoted, Follow-Up, Negotiation, Won, Lost
- **Drag-and-Drop** — Move opportunities between stages via @dnd-kit
- **Stage Transitions** — Every stage move recorded as immutable history
- **Win Probability** — Per-stage default + per-opportunity override
- **Weighted Pipeline Value** — estimatedValue × winProbability
- **Stale Indicators** — Cards flagged if no activity within threshold (7 days default)
- **Days in Stage** — Displayed on each card
- **Won/Lost Prompts** — Loss reason required when moving to Lost; actual value for Won
- **Terminal Columns** — Won and Lost are narrower, separate from active stages

#### Lead Management
- **Create Leads** — With or without an existing client record (inline contact fields)
- **Lead Sources** — Referral, Website, Email, Phone, Walk-In, Social Media, Repeat Client, Other
- **Priority Levels** — Low, Medium, High
- **Expected Close Date** — With overdue indicators
- **Tags** — Free-form tagging
- **Address** — Job site address for the lead

#### Activity Timeline
- **Activity Types** — Note, Email, Call, Meeting, Estimate Sent/Accepted/Declined, Invoice Sent, Payment Received, Stage Change, Created, Won, Lost, System
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

3. **Photo Markup** (partially underway via Notes Overhaul — see [07_SPECIALIZED_FEATURES.md](07_SPECIALIZED_FEATURES.md) Section 11)
   - Captions on photos (planned for note attachments)
   - Arrows and annotations (canvas markup planned for note photo attachments)
   - Notes and labels
   - Before/after comparisons

4. **Recurring Schedules**
   - Auto-populate weekly jobs (e.g., every Monday)
   - Bi-weekly schedules
   - Monthly schedules
   - Recurring project templates

5. **Materials/Inventory Tracking**
   - Materials list per job
   - Inventory management
   - Purchase orders
   - Material cost tracking

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

**Last Updated:** February 18, 2026
**Document Version:** 1.2
**iOS App Version:** 207 Swift files, iOS 17+, SwiftData + SwiftUI
**Web App:** Pipeline, Estimates, Invoices, Products, Project Notes live in ops-web (Supabase)
