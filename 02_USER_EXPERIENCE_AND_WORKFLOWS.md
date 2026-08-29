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

With Catalog permission (catalog.view):
┌──────┬────────┬─────────┬──────────┬──────────┐
│ Home │  Board │ Catalog │ Schedule │ Settings │
└──────┴────────┴─────────┴──────────┴──────────┘

Maximum (Pipeline + Catalog):
┌──────┬──────────┬────────┬─────────┬──────────┬──────────┐
│ Home │ Pipeline │  Board │ Catalog │ Schedule │ Settings │
└──────┴──────────┴────────┴─────────┴──────────┴──────────┘
```

When the full tab set is wider than the viewport, Settings remains the trailing overflow tab. Selecting or restoring Settings automatically scrolls the tab bar far enough to keep its icon fully visible; returning to a primary tab restores the tab bar to its resting position.

**Resting position (bug df49d9ef, 2026-07-29):** the lane rests at content-x **0** — the primary tabs holding their designed `gap/2` edge padding, with the divider and Settings genuinely off-screen. Both resting scrolls target `leadingEdgeID`, a sentinel on the PADDED primary group (its frame starts at content-x 0). Targeting the first tab *cell* instead rests the lane at `gap/2`, because the cell's leading edge sits that far into the content — the edge padding scrolls away and the trailing divider peeks in. `TabBarSnapshotTests` pins the settled offset at `0 ± 0.5` on initial render and after returning from Settings.

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

4. **Catalog** (`shippingbox.fill` icon) — **Conditional**: shown if user has `catalog.view` permission
   - **STOCK** segment: variant-aware stock list with LIST / GRID / TABLE view modes, threshold banner for undersupplied variants, sort by category/tag/threshold, FAB for new variant / new family / spreadsheet import
   - **PRODUCTS** segment: billable templates (barebones + configurable), search by type/kind/has-recipe, FAB for quick-add (3 fields, ~8s) or full setup on web
   - Kebab menu (grouped): STOCK (Snapshots · Categories · Tags · Units · Thresholds), ORDERS (Suggested · Drafts · Sent), SETUP (Defaults · Import · Export)
   - Admin, Owner, and Office roles have `catalog.view` and `catalog.manage` by default; `catalog.products.manage` and `catalog.orders.manage` available for fine-grained admin/operations splits

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

**Legacy note**: The iOS app's tab visibility uses `can("pipeline.view")` and `can("catalog.view")`. The pre-Phase 13 permission keys (`inventory.view` / `inventory.manage` / `inventory.import`) were renamed to `catalog.*` by migration `2026-05-06-04-permission-rename.sql`; the legacy `user.inventoryAccess` property is no longer authoritative.

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
│   ├── Catalog Tab (conditional — requires can("catalog.view"))
│   │   ├── CatalogView (segmented control: STOCK | PRODUCTS, kebab ⋮)
│   │   │   ├── STOCK segment
│   │   │   │   ├── Threshold banner (when items below warning) → CatalogOrdersSheet
│   │   │   │   ├── View mode: LIST | GRID | TABLE (TABLE is NEW per Bug 217c3d1f)
│   │   │   │   ├── Search bar + category/tag filter chips
│   │   │   │   ├── Sort modes (Category, Name, Quantity, Threshold)
│   │   │   │   ├── CatalogVariant cards (variant-aware; family + variant label)
│   │   │   │   │   ├── Long press → action sheet (Adjust, Edit, Delete, Move to Order)
│   │   │   │   │   ├── → CatalogVariantFormSheet (edit, modal)
│   │   │   │   │   └── → QuantityAdjustmentSheet (modal)
│   │   │   │   ├── → CatalogVariantFormSheet (new variant, modal via FAB)
│   │   │   │   └── → CatalogFamilyFormSheet (new family, modal)
│   │   │   ├── PRODUCTS segment
│   │   │   │   ├── Filter chips: type · kind · has-recipe
│   │   │   │   ├── Product list (price summary, option count, recipe row count)
│   │   │   │   ├── → ProductDetailView (push) — view + light edits, options/modifiers/recipe read-only
│   │   │   │   ├── → ProductQuickAddSheet (FAB → "+ quick add", 3 fields)
│   │   │   │   └── → Web (FAB → "+ full setup") — configurable Product authoring lives on web
│   │   │   └── ⋮ menu
│   │   │       ├── STOCK group: Snapshots · Categories · Tags · Units · Thresholds
│   │   │       │   ├── → CatalogSnapshotListView
│   │   │       │   ├── → CatalogCategoriesSheet
│   │   │       │   ├── → CatalogTagsSheet
│   │   │       │   ├── → CatalogUnitsSheet
│   │   │       │   └── → CatalogThresholdsSheet
│   │   │       ├── ORDERS group: Suggested · Drafts · Sent
│   │   │       │   └── → CatalogOrdersSheet (3-tab)
│   │   │       └── SETUP group: Defaults · Import · Export
│   │   │           ├── → CompanyDefaultProductsSheet (component_type → product mapping)
│   │   │           ├── → SpreadsheetImportSheet (variant-aware)
│   │   │           └── → SpreadsheetExportSheet
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

### Cross-Platform Completion Rules

OPS has one cohesive signup/onboarding contract across ops-site, OPS-Web, and OPS iOS:

- **Server state wins.** `company_id` alone never means onboarding is complete. Clients require server-backed onboarding completion, a valid `company_id`, and a valid `user_type` before entering the main product.
- **Interrupted setup resumes.** If a user loses connection mid-onboarding, the client keeps local draft input, does not advance past the failed server write, and resumes from the last confirmed server step.
- **Company joins require code proof.** User-initiated joins pass both `company_id` and the normalized company code to the hardened `join_user_to_company` RPC.
- **Completion is acknowledged by the backend.** Web completion uses `/api/setup/complete`; iOS completion uses `/api/onboarding/complete` through the OPS-Web API gateway.
- **Handoffs preserve intent.** ops-site and OPS-Web auth/onboarding routes preserve sanitized continuation URLs so signup, login, account-type selection, and setup return users to the route that initiated the flow.

### iOS Onboarding — The Rebuilt Express Flow (2026-06-13 cutover)

> The iOS onboarding was rebuilt from scratch and cut over on **2026-06-13** (spec: `ops-ios/docs/superpowers/specs/2026-06-11-onboarding-rebuild-design.md`). The old three-generation system — an A/B/C experiment coordinator (`OnboardingABTestCoordinator`) mounted in two places, three drifting login forms, a double-welcome, and ~70 dead/superseded screens — was replaced by **one express flow: one welcome, one login, one onboarding instance, one completion path.** The rebuilt module lives at `OPS/Onboarding/` (`Gateway/`, `Flow/`, `Screens/*StepView`, `Gateway/*LiveBoundary`, `Manager/OnboardingManager`, `State/OnboardingFlowState`). The original A/B/C experiment (express vs interactive-tutorial vs workflow-animation) is **deferred** to tracked follow-up work — it is rebuilt properly only when those variants ship; this version ships the express variant alone.

**Architecture.** A single `OnboardingGateway` (SwiftUI) is the only pre-app mount: it owns Welcome, Login, and the one `OnboardingFlowCoordinator` instance for both anonymous and authenticated-but-incomplete users, so a kill/relaunch mid-onboarding resumes the flow rather than landing in the main app. `ContentView` routes into the gateway, flag-gated by **`FeatureFlags.useRebuiltOnboarding` (default `true` as of the 2026-06-13 cutover)**. The coordinator is an explicit step machine (`OnboardingFlowStep`) with a data-driven back map (a no-op Back is structurally impossible) and a server-derived resume table; each screen isolates the live auth/data layer behind an injected `*LiveBoundary` adapter so the screens stay unit-testable. Flow state persists under **`onboarding_state_v4`** (single versioned blob: step position + collected form data), with a one-shot `onboarding_state_v3 → v4` launch migration.

> **Legacy code status (2026-06-13):** the legacy A/B coordinator and its ~70 screens/components remain in the codebase but are **dead** (no longer mounted) pending a legacy-deletion pass. Setting `feature.useRebuiltOnboarding = false` reverts to the legacy flow.

**Screen-count rule:** counts = interactive screens requiring input (auto-advancing transitions and the completion gate are excluded). **Owner: 5. Crew: 6 (single invite) or 7 (picker / manual code).**

#### Shared head (both roles)

**S1 — Welcome** (`WelcomeStepView`) — brand line, one subline, version footer. `GET STARTED` → role pick; `SIGN IN` → Login. Serves new and returning users identically; static-first hero (any motion honors Reduce Motion).

**Login** (`LoginStepView`, one shared implementation; Back → Welcome) — email + password, Apple, Google, forgot-password, inline field-level errors. Outcomes:
- Returning **complete** user → workspace-preload-gate path into the app.
- Returning **incomplete** user → flow resumed at the derived step (see resume table).
- Social sign-in resolving to a **brand-new identity** (no prior `users` row) → `sync-user` runs, then routes into the flow at Role pick with auth already satisfied (Create account is skipped).

**S2 — Role pick** (`RolePickStepView`; Back → Welcome pre-auth; resumed post-auth there is no Back, header carries `SIGN OUT`) — two cards: `RUN A CREW` / `JOIN A CREW`. **Role choice is uncommitted** until a company is created or joined, so it can be revisited via the back-edges below — killing the wrong-role trap.

**S3 — Create account** (`CreateAccountStepView`; Back → Role pick) — Apple / Google / email. **Commit point: the Firebase account + `sync-user` row are created on S3 submit.** No path exits S3 with an empty first or last name (email collects them inline; Apple/Google auto-fill, falling back to required inline fields when the provider returns no name; the Apple name cache lives in Keychain so it survives reinstall). Existing-account handling: email already registered → inline error + one-tap `SIGN IN` handoff (prefilled email); Apple/Google resolving to an existing account → treated as sign-in (complete → app; incomplete → derived resume).

#### Owner path (5 screens)

- **S4o — Company name** (`CompanyNameStepView`; Back → Role pick — the account is committed but the role isn't yet, since no company exists; header `SIGN OUT`) — single name field + optional primary-trade chips → `companies.industries`. **Company-creation commit point:** calls the shared `create_company_for_owner` RPC (see `04_API_AND_INTEGRATION.md`), which returns the DB-truth crew code.
- **S5o — Crew code** (`CrewCodeStepView`; no Back — company is committed) — the payoff. The RPC-returned code in JetBrains Mono, bracketed, identical render to the entry screen; COPY (success haptic); INVITE CREW; "find this code in Settings anytime"; CTA `ENTER OPS →` → completion gate → app.

#### Crew path (6–7 screens)

- **S4c — Invite check** (`InviteCheckStepView`; auto transition) — looks up pending invites by email. Exactly one → Confirm company; 2+ → invite picker; none → code entry. A **fetch/decode failure is a user-visible retry state** (`CHECK AGAIN` / `ENTER CODE INSTEAD`), never silently treated as zero invites; it fires the `onboarding_invite_check_failed` diagnostic.
- **Invite picker** (`InvitePickerStepView`; Back → Role pick; secondary `ENTER A DIFFERENT CODE` → code entry) — cards for each pending invite.
- **S4c-code — Crew code entry** (`CodeEntryStepView`; Back → Role pick when reached via zero invites, Back → picker when reached from the picker — the back map carries provenance; header `SIGN OUT`) — bracket-mono input. **No client-side format rejection** — any non-empty code is accepted (legacy `PREFIX-XXXXXX` codes stay valid); validation is server lookup-only.
- **S5c — Confirm company** (`ConfirmCompanyStepView`; Back → its source: picker or code entry) — branding/team preview before commit; sparse-data fallback gets a deliberate reduced layout. **Crew JOIN commit point:** calls `join_user_to_company`.
- **S6c — Profile** (`ProfileStepView`; no Back — join is committed; header `SIGN OUT`) — first/last (prefilled from S3, editable), phone, photo. **Name + phone required, photo optional.** Avatar upload shows progress and surfaces failure with retry.
- **S7c — Emergency contact** (`EmergencyContactStepView`; Back → Profile; visible `SKIP`) — `FINISH` saves; SKIP advances without saving. Both terminate at the completion gate.

#### Completion gate (both paths, auto)

`CompletionGateView` awaits the server ACK (`POST /api/onboarding/complete` → merges `users.onboarding_completed.ios=true`) behind a loader built to the `WorkspacePreloadGate` standard. **Offline/failure contract (designed for poor connectivity):** if the ACK fails or times out, completion is **queued locally** (`onboarding_completion_pending = true`) with a visible "will finish syncing" state and the user **enters the app**; `shouldShowOnboarding` treats a queued completion as complete; the SyncEngine drains the queued ACK (`retryPendingOnboardingCompletion`) until the server confirms. No blocking, no re-entry loop, no silent failure.

#### Back map (single source of truth — `OnboardingFlowStep.backEdge(context:)`)

`Login→Welcome`, `RolePick→Welcome` (pre-auth only), `CreateAccount→RolePick`, `CompanyName→RolePick`, `InvitePicker→RolePick`, `CodeEntry→RolePick | InvitePicker` (by provenance), `ConfirmCompany→source` (picker or code entry), `EmergencyContact→Profile`. Steps with no back-edge (escape is `SIGN OUT`, which fully clears flow state and returns to Welcome): post-auth RolePick, CrewCode, InviteCheck, Profile, CompletionGate.

#### Server-derived resume (`OnboardingResume.derive` — server state is authority)

The persisted local step is an optimization only; on resume / cross-device the server-observable user row decides placement (strict priority order):

| Observable server state | Resume target |
|---|---|
| No company affiliation (any/no `user_type`) | Role pick — role is uncommitted |
| Company + `onboarding_completed.web = true`, `.ios` ≠ true | Completion gate (silent auto-complete: the gate fires the iOS ACK, zero screens) |
| Company + `role = owner` | Completion gate (NOT the crew-code screen — the code is a one-time reveal and lives in Settings; re-showing it cross-device would render a blank code) |
| Company + employee, profile incomplete (blank first/last/phone) | Profile |
| Company + employee, profile complete | Completion gate (Emergency contact is optional and never re-offered on resume) |

> Note (2026-06-13): the iOS `User` model does not yet expose `onboarding_completed.web`, so the gateway reports `webComplete = false` until a DTO/model change lands. The safe consequence: a user who finished onboarding on web but not iOS is routed by company + role + profile (never skipping a required local step) rather than silently auto-completed.

#### Funnel analytics

The rebuilt flow fires a clean per-step funnel (see `21_ANALYTICS_SYSTEM.md`): `onboarding_step_viewed`, `onboarding_completed`, `onboarding_abandoned` (gateway-observed), plus `onboarding_completion_queued` (offline gate) and `onboarding_invite_check_failed` (the R13 diagnostic). The existing Google Ads conversion points (`sign_up`, `complete_onboarding`) are preserved.

### Sign-In Flow (Returning Users)

Returning users sign in through the shared **Login** screen described above (`LoginStepView`, reached from Welcome's `SIGN IN`):
- **UI Elements:**
  - OPS logo
  - Title (terse/tactical voice; the banned "Welcome back!" / "Enter your credentials" strings are not used)
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

**Web undo contract (updated 2026-08-29):** On `OPS-Web` every pipeline stage
mutation that has a true inverse surfaces a visible UNDO on its toast, rendered
through the canonical `showUndoToast` helper on the olive success rail: active
stage moves, archive, mark-lost (dialog confirm), and discards — both the
Phase-C reason-capture path and the plain/fallback path. Each mutation pushes
its undo entry and hands the toast that entry's **id**, so the toast's UNDO and
the top bar's Cmd+Z consume one and the same entry: whichever the operator
fires first performs the reversal and the other silently no-ops. A stage change
can therefore never be reverted twice, and a stale toast can never undo a newer,
unrelated action.

Two deliberate exceptions. **Won/convert offers no toast undo** — winning a deal
runs the atomic `convert_opportunity_to_project` RPC, and moving the stage back
does not unwind the project it minted, so a visible UNDO would promise a
reversal it cannot deliver (Cmd+Z still restores the stage, as before). And the
**discard capture toast's silent branch stays silent**: that toast already
carried its own UNDO for its whole lifetime, so a second toast after it closes
is noise. The undo entry still reaches the global stack on both branches.

---

### Catalog Journey: Manage Stock + Products (updated 2026-07-21)

**Goal:** Manage variant-aware stock, author Products, draft restock orders, and emit one-click estimates from drawings.

**Prerequisites:** User must have `can("catalog.view")`. Stock edits require `catalog.manage`; Product edits require `catalog.products.manage`; orders require `catalog.orders.manage`.

**STOCK Steps:**

1. **Start Point:** Catalog tab → STOCK segment
2. **Observation:** If any variants are below their effective warning threshold, a compact strip shows separate CRITICAL and LOW counts. Tap → opens CatalogOrdersSheet (Suggested view) when permitted; read-only operators pivot to the low-stock filter.
3. **Action:** Use the labeled workbar to choose one purpose-specific view mode:
   - **LIST — scan + adjust:** one 56pt row per variant. Global family/quantity/low-stock sorts stay global; Category sort groups the same rows by parent → child category.
   - **GRID — find by family:** one family tile with image when available, variant count, and explicit CRITICAL/LOW counts. Single-variant families open Quick Adjust directly; multi-variant families open a compact variant picker. Pinch or the VoiceOver adjustable action changes density between 3/2/1 columns (0.8x–1.5x).
   - **TABLE — audit one family:** a family selector drives one comparison matrix. REFERENCE, ON HAND, and VS LIMIT remain pinned; each row identifies whether its delta uses the warning or critical limit. Only the family option-value band scrolls horizontally. Accessibility text sizes switch to fully labeled stacked variant rows.
4. **Action:** Expand the scoped Stock search or use filter chips. Category and tag menus contain only values represented in live stock; selecting a parent category includes stock in child categories.
5. **Action:** Open the header kebab (⋮) → Add Variant or Add Family
   - Variant flow: pick family (or deep-link to create one), pick option-value combinations, set quantity, unit, SKU. Effective threshold previews based on family/category fallback
   - Family flow: name, category, default price/cost, default unit, default thresholds
   - **Bulk Add Variants:** `STOCK → Bulk Add Variants` opens `FAMILIES → CHANGE → REVIEW`. Search covers family, category, option names, and option values. Structurally unsafe families remain visible but disabled with the exact reason; Select all affects only safe visible rows. The operator names one option axis, identifies its existing/source value, enters 1–20 normalized new values, then reviews exact existing and new combinations before one synchronous apply. The browser keeps a company-scoped local draft; offline editing remains available but Apply is disabled. A successful apply closes only after the active TanStack stock query and the expansion snapshot query have both refetched. This is foreground work and does not create a notification-rail event.
6. **Action:** Tap a LIST row, a single-variant GRID tile, a family-picker row, or a TABLE row → StockQuickAdjustSheet → adjust quantity. Long press a row → Open Full Detail.
7. **Observation:** Status never relies on color alone. CRITICAL and LOW remain explicit text, with mobile-bright rose/tan foregrounds and brick/tan reserved for borders/dots.

**PRODUCTS Steps:**

8. **Action:** Switch to PRODUCTS segment
9. **Action:** Header kebab (⋮) → New Service or New Good
10. **Action:** Tap a Product → ProductDetailView. Edit name/price/unit/tax/active inline. Options/modifiers/recipe sections render read-only (authoring lives on web)
11. **Observation:** Configurable Products show option count and recipe row count next to the price summary

**ORDERS Steps:**

12. **Action:** Tap kebab ⋮ → ORDERS → Suggested → see grouped suggestions
13. **Action:** "Draft all" → status `.suggested` → `.draft`. Edit lines, send (status `.sent`)
14. **Action:** When stock arrives → mark fulfilled → `catalog_variants.quantity` increments by `quantity_requested`

**SNAPSHOTS Steps:**

15. **Action:** Kebab → Snapshots → CatalogSnapshotListView. Detail view shows family name + variant label per row.

**End Point:** Stock variant-tracked, Products authored, orders flowing, snapshots captured.

**Time to Complete:** ~30s per variant, ~8s per quick-add Product, seconds for quantity adjustments

**Gestures:**
- Pinch-to-zoom on stock grid mode (0.8x-1.5x, persisted via `@AppStorage("catalog.stock.cardScale")`); VoiceOver adjustable actions provide the equivalent 3/2/1-column control
- Long press a variant row for full detail
- Tap for quick adjustment / detail

**Pain Points Addressed:**
- Variant model handles "Corner — Black" vs "Corner — White" without forcing two separate items
- Purpose-specific LIST / GRID / TABLE modes avoid rendering the same heavy card three ways
- TABLE keeps stock identity and health pinned while auditing every Bracket SKU across Color × Mount Type
- Threshold cascade (variant → family → category) means setting one number on a category covers every child SKU that hasn't overridden it
- Suggested orders surface undersupplied stock without manual auditing
- Configurable Products + drawing→estimate adapter compress hours of estimate writing into one tap

---

## Screen Catalog

### Home Screen

**Purpose:** Dashboard overview of today's work and recent activity.

**UI Elements:**
- **Today's Date** - Large header with current date
- **Today's Schedule** - Swipeable task-card carousel over the Home map
  - Task title
  - Project name
  - Time range (if specified)
  - Assigned crew avatars
  - Compact pagination occupies a dedicated lane below the 100pt card; it never overlays the title, client, address, or task badge
  - Pagination is informational, centers beneath the card, and shows at most five indicators with a distinct selected state
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
- **Tap task (iOS Project Details):** Opens the quick task sheet at its medium
  detent with identity, status action, dates, and team first. Dragging the sheet
  to full height reveals a dedicated `DESCRIPTION` card before the selection
  and cancellation actions. The card renders the complete normalized
  `project_tasks.task_notes` value without truncation; missing or
  whitespace-only text renders as `—`. The sheet remains scrollable at both
  detents. Source:
  `ops-ios/OPS/Views/Components/Task/TaskDetailPopupSheet.swift`.
- **Duplicate task (iOS, 2026-07-25):** Long-press a task row and choose
  `Duplicate Task`. OPS immediately appends and selects a fresh active,
  unscheduled task. The copy preserves task type/title, notes, color, crew,
  duration, and explicit dependency overrides (including an explicit empty
  override). It resets status, dates/times, estimate and line-item provenance,
  paired-task lineage, schedule lock, deletion state, ID, and creation
  timestamp. No confirmation sheet is shown. The action requires full
  `tasks.create` permission and is unavailable through mention-only project
  access. Source:
  `ops-ios/OPS/Utilities/ProjectTaskDuplication.swift`,
  `ops-ios/OPS/Views/Components/Project/ProjectDetailsViewModel.swift`, and
  `ops-ios/OPS/Views/Components/Project/Tabs/DetailsTabView.swift`.
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

**Updated:** 2026-08-21 — The 2026-03-02 `DayCanvasView` + `CalendarDaySelector` redesign now uses bounded background snapshots so entering Schedule and moving between cached weeks never wait on SwiftData.

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
   - The week-view scroll viewport extends full bleed behind the overlaid global tab bar. Tab-bar clearance belongs inside each day's scroll content so the final card remains reachable without shortening the viewport.
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

**Responsiveness contract (2026-08-21):** Date selection is published immediately. Calendar cells and day pages read prepared caches only; they never fetch SwiftData while rendering or inside the tap/swipe path. The active week snapshot contains the visible week plus one adjacent week on either side, so those week moves render from memory while a cancellable background read recenters the window. Tasks are store-bounded by true date overlap, preserving long-running work that started earlier. Personal events and booked visits use a separate rolling 91-day bounded snapshot. Rapid navigation discards stale generations instead of repainting an older week over the current selection. Sources: `ops-ios/OPS/ViewModels/CalendarViewModel.swift`, `ops-ios/OPS/Utilities/DataActor+CalendarGrid.swift`, `ops-ios/OPS/Utilities/CalendarScheduleSnapshot.swift`; code commit `e1a23244`.

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
│ Filters  │  // DAY · WEEK · MONTH · CREW│ Event   │
│ (only)   │                             │ details  │
└──────────┴─────────────────────────────┴──────────┘
          ↑
Unscheduled tray (left rail, promoted out of filter sidebar
in the 2026-04-27 Phase 1+2 rework)
```

**UI Elements (post 2026-04-27 Phase 1+2 visual + structural rework):**

1. **CalendarHeader** — Date navigation (prev/next), `[ TODAY ]` accent pill (disabled when current view already shows today), filter toggle, view switcher, and auto-schedule action.

   **View switcher labels:** `// DAY` · `// WEEK` · `// MONTH` · `// CREW` (Cake Mono Light). The previous `'timeline'` view is now `'crew'` — Zustand persist v2 migrate function rewrites stored values on read. Default view for new users is `Week`.

   **Auto-schedule:** The header action is enabled only when active, non-deleted, non-completed, non-cancelled tasks exist without `startDate`. It opens the shared auto-schedule ghost-preview + confirm bar flow; it does not write dates until the operator confirms. The project drawer exposes the same action scoped to the selected project's schedulable unscheduled tasks.

2. **CalendarToolbar** — Includes a `// UNSCHEDULED [N]` chip (left of today/week stats) that toggles the unscheduled tray. When `N = 0`, the chip is disabled and reports `No unscheduled tasks`. Event count, active filter chips, the `// TEAM` selector, and the task type `// LEGEND` selector remain. Team and legend selectors are Radix popovers portaled above the scrollable toolbar so they cannot be clipped by toolbar overflow.

3. **FilterSidebar** (left, 260px, collapsible) — Three filter sections only (Team Members, Task Types, Projects). Time-relative status filters (`Past`, `Upcoming`, `In progress`) are intentionally removed because they do not map to useful operator decisions; the persisted calendar store clears any legacy values on migration. Filter rows show a checkbox plus the label, with team avatars only when a real profile image exists. The UnscheduledPanel that previously lived inside has been promoted to a first-class `<UnscheduledTray>`.

4. **UnscheduledTray** (left rail in Day/Week/Month/Crew — mirrors Jobber/Housecall convention):
   - Collapsed: 32px-wide vertical strip with rotated `// UNSCHEDULED [N]` label + grip icon
   - Expanded: 280px wide. Search, group-by (Project / Client / Type / None), sort (Created / Title / Project), scrollable card list with `// GROUP_NAME [N]` headers
   - Empty state: when `N = 0`, the tray is visually collapsed to the 32px rail regardless of the persisted expanded flag, and the rail button is disabled (`aria-label="No unscheduled tasks"`) so the empty tray never consumes planning canvas.
   - Drag source: dnd-kit `data: { type: 'unscheduled-task', task }` — same contract month-grid + week-grid + crew-grid already accept
   - State persisted: collapsed flag, group-by, sort. Search session-scoped.

5. **Calendar Grid** (center, 4 views):
   - **Day** — single-column scrollable card list (will switch to hourly mode in Phase 3 when timed events exist)
   - **Week** — 7-column day stack (Mon–Sun, weekStartsOn: 1). All-day fallback now; hourly mode in Phase 3. Each column: header (weekday + date number) and a vertical stack of `<DayTaskCard>`s. Drag-drop per column.
   - **Month** — traditional grid, event indicators (compact dots / standard bars / expanded cards), click date → Day view, click task → task detail panel. When the sticky month label overlaps an event on the first week row, hovering the label fades it temporarily and lets pointer events pass through to the event.
   - **Crew** — formerly "Timeline." Gantt-style swimlane rows per crew member, unassigned synthetic row. Drag tasks across days and rows; resize edges to extend duration.

6. **Card information design (three-source rule, applied across Day, Week, Month, Crew, popovers):**
   - **Title (line 1):** `task.project?.title ?? task.customTitle ?? taskType.display` — project first because that's how owners think about jobs
   - **Subtitle:** `task.customTitle ?? taskType.display` (only when distinct from title)
   - **Body fill / border:** `STATUS_COLORS[deriveTaskStatusKey(task)]` — earth-tone semantic (olive/tan/mute/brick/rose for scheduled/in_progress/completed/cancelled/overdue)
   - **Left accent stripe:** `TASK_TYPE_COLORS[deriveTaskType(task)].border`, rendered as a 3px sibling div with matching `border-radius: 4px 0 0 4px` (NOT `box-shadow: inset` — the inset variant doesn't respect border-radius and produces a "crescent moon" artifact at the corners)
   - **Type badge:** `taskType.display` (Cake Mono Light, type-color), rendered in the title row for Day/Week cards so narrow columns truncate the title before the badge instead of overlaying it
   - **Crew avatars:** max 3 visible (UserAvatar with tooltip), then `+N` chip
   - **Time label:** `HH:mm → HH:mm` JetBrains Mono tabular-nums, only rendered when `event.allDay === false` (Phase 3)
   - **Address:** hover popover only (too dense for cards)

7. **Today indicator (3 reinforcing signals):**
   - **Day-cell number** in Month / Week / Crew column header: 24×24 rounded-square (radius 4) with solid `var(--ops-accent)` fill and black text. Cake Mono Light 13px. Squares read as tactical (circles read as cute / startup).
   - **Column accent line** in Week + Crew + Day header: `2px solid var(--ops-accent)` on the today column's `border-top`.
   - **Toolbar `[ TODAY ]` pill** in calendar-header: JetBrains Mono 11px tabular-nums, accent border + text, fills accent + black text on hover. Disabled when current view already includes today (computed from view + currentDate vs `new Date()`).

8. **Popover layering (T16/T17 portal rule):**
   - All floating UI portal-rendered to `document.body`
   - Hover popover: Radix HoverCard, `var(--z-dropdown)` (1000), glass-dense surface, 12px radius. Shows project title, task title, type+status badges, time range (Phase 3), date range, crew names, site address
   - Context menu: Radix Popover with virtual anchor at the right-click coords. Same z-layer + surface
   - Inline editor: portaled to body via `createPortal`, fixed positioning, `var(--z-floating-ui)` (1500) — above dropdowns since it's a focused editing affordance
   - Z-scale exposed as CSS custom properties: `--z-content` 1, `--z-interactive` 100, `--z-nav` 500, `--z-dropdown` 1000, `--z-floating-ui` 1500, `--z-window` 2000, `--z-modal` 3000, `--z-map-controls` 5000, `--z-emergency` 9000

**EventBlock states:** normal / hover (brightness 1.18) / selected (1px var(--ops-accent) outline) / dragging (50% opacity) / resizing.

**EventQuickCreate (Popover)** — opens on empty slot click, range drag, or keyboard C. Unchanged.

**Drag-and-Drop:**
- `CalendarDndContext` wraps all grid content with `@dnd-kit/core`
- `PointerSensor` with `distance: 8` activation
- DnD data types per surface:
  - `month-event` / `month-day` (month grid)
  - `week-event` / `week-day` (week grid)
  - `crew-event` / `crew-row` (crew swimlane)
  - `unscheduled-task` (drag source from tray) — accepted by all three day-target types

**Animations:**
- View switching: horizontal slide (±40px, 300ms) via `AnimatePresence`
- Event appear: stagger fade-in (50ms per item)
- Single easing curve `cubic-bezier(0.22, 1, 0.36, 1)` (EASE_SMOOTH). No spring, no bounce
- All honor `prefers-reduced-motion` (opacity-only fallback). Radix HoverCard skips its own animation natively when the media query matches

**Keyboard Shortcuts:**
- D/W/M/C (views), ArrowLeft/Right (navigate), C (create), E (edit), Tab (cycle events), Enter (open detail), Delete (delete selected), Escape (close)

**Responsive:**
- Desktop (≥1200px): three-panel layout (filter sidebar + grid + tray)
- Tablet (768–1199px): two-panel, sidebar/tray available
- Mobile (<768px): Day view forced, sidebar hidden, tray hidden

**State:** `calendar-store.ts` (Zustand + persist v2 → localStorage). Persisted: view, filters, unscheduled tray collapsed/group/sort. Ephemeral: selection, panels, drag state, search query.

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

### BooksTabView (Books Tab Container)

**Purpose:** Money command center for trades operators. The hero is a swipeable 5-card financial carousel of **condensed glance tiles** (uniform height; headline metric + one signature mini-viz) that tap to expand into a detail half-sheet; below it, in one continuous scroll, sits a 3-segment list of the underlying documents (Invoices · Estimates · Expenses) under a pinned section header. Visually rebuilt 2026-05-19 ("Mission Deck", Phase 3), then reworked into the condensed-card + expand-sheet pattern 2026-06-01 (Phase 6).

**Source:** `Views/Books/BooksTabView.swift` (Phase 3 — Mission Deck, 2026-05-19)

**UI Elements (top to bottom):**

1. **AppHeader** — `.books` header type, "BOOKS" title.
2. **Sync banner** (`BooksSyncBanner`) — present only when the dashboard is not fully synced: a pulsing `SYS :: SYNC · HH:mm` while a refresh is in flight, or `SYS :: OFFLINE · CACHED HH:mm` / `SYS :: ERROR · LAST HH:mm` with a RETRY button when the network is down or the last fetch failed.
3. **`HeroCarousel`** — 5-card swipeable, paged carousel of **condensed glance tiles** (one uniform L2 height). Each tile shows the lens's headline metric + one signature mini-viz + a sub-stat; **tapping a tile opens its full content in a half-sheet** (`ExpandedCardSheet`; A/R opens the merged `ARDetailSheet`), where the per-card detail and drill actions live. Swiping fires a light haptic, a tap fires `.selection`; the inline header label, dot pagination, period pill, and scope-hint badges all track the active tile; the last-viewed card persists for next launch. The card descriptions below are the **expanded (sheet)** content; the condensed face surfaces the headline number + mini-viz only.
   - **Card 1 — `PLCard`** ("Am I making money?") — net-cash hero number, a margin meter with a `X% MARGIN` caption, a `PAYMENTS IN` / `EXPENSES OUT` row, and `OUTSTANDING` / `FORECAST` drill tiles.
   - **Card 2 — `CashFlowCard`** ("What's my cash rhythm?") — net-cash hero plus a weekly-net sparkline; any week where money out beat money in gets a rose marker. Tiles: `SALES`, `AVG/WK`, `DAYS`.
   - **Card 3 — `ARCard`** ("Who do I need to chase?") — total-outstanding hero, an aging ramp (0–30 / 31–60 / 61–90 / 90+) with a bucket grid, and a full-width `TOP CHASE` tile. Always all-open — ignores the period.
   - **Card 4 — `ForecastCard`** ("What's coming if pipeline plays out?") — weighted-forecast hero plus per-stage bars with a probability indicator. Tiles: `CLOSE RATE`, `STALE`. Always active-only.
   - **Card 5 — `JobsCard`** ("Which jobs made money? Which lost it?") — diverging profit/loss bars from a center axis, with `PROFITABLE` / `AVG MARGIN` / `LOSERS` tiles.
   - **Inline header** — the active card's label on the left, the period pill on the right. Cards 3 and 4 carry a colored scope-hint badge (`ALL OPEN` / `ACTIVE`) so the user knows they don't track the selected period.
   - **Dot pagination** — the active dot is a wide white capsule; tapping a dot jumps to that card.
4. **`PeriodPill`** — a single tap-target opening a menu of 8 periods (30 DAYS / 90 DAYS / 6 MONTHS / 1 YEAR / THIS MONTH / LAST MONTH / THIS QUARTER / YEAR TO DATE). Choosing a period re-computes Cards 1, 2 and 5; Cards 3 and 4 are unaffected.
5. **`CashflowForecastCard`** — a forward-looking 13-week cashflow preview mounted below the carousel for users with `finances.view` (see `09_FINANCIAL_SYSTEM.md` → Cashflow Forecast).
6. **Segmented control** — inset-pill style, 3 sections **INVOICES | ESTIMATES | EXPENSES**; the active segment is a neutral white pill (no accent). Switching fires a light haptic. Sticky on scroll-collapse.
7. **Drill filter chip** (`BooksDrillFilterChip`) — shown below the segments when a card drill applied a filter (`OVERDUE` for Invoices, `SENT` for Estimates). Tap × to clear it and restore the list's full scope.
8. **Content area** — the selected segment's list view.

**Workflows:**
- *Swipe the carousel* — light haptic; the inline header label and dots update; the last-viewed card is restored on the next launch.
- *Change the period* — tap the pill and pick a window; Cards 1, 2 and 5 morph their numbers; Cards 3 and 4 hold (their scope-hint badges explain why).
- *Scroll-collapse* — scrolling the list collapses the hero into a one-line `CollapsedCarouselStrip` (the active card's primary number, an A/R glance, and dots); the segmented control and any filter chip stick to the top. Scrolling back up re-expands the hero.
- *Drill from a card* — Card 1 `OUTSTANDING` → Invoices filtered to overdue; Card 1 `FORECAST` → Estimates filtered to sent; Card 3 `TOP CHASE` → the A/R aging half-sheet. A drill switches the segment and drops a filter chip; tap the chip's × to clear it.
- *Pull-to-refresh* — pulling down on the content re-runs the dashboard load; progress shows in the sync banner.
- *Recover from an error* — a single failed data fetch shows a card-level error on only the affected card(s) with a RETRY button while sibling cards keep their data; a whole-dashboard failure surfaces in the sync banner with RETRY.

**States:**
- *Cold launch, no cache* — per-card skeleton placeholders render until the first load completes.
- *Empty data* — a card with zero data shows an empty hero (`$0` / `—`) and a `// NO …` label rather than a blank card.
- *Syncing / offline / error* — surfaced by the sync banner; offline keeps the cached numbers on screen with a RETRY action.
- *Reduced motion* — number morphs, bar fills, the sparkline animation and the dot-capsule transition are all suppressed.

**Child Views:**
- `InvoicesListView` (embedded) · `EstimatesListView` (embedded) · `ExpensesListView` (full access) or `MyExpensesView` (own scope).

**Access / role differences:**
- Visible to users with any of `finances.view` / `estimates.view` / `expenses.view`. `pipeline.view` no longer gates BOOKS — Pipeline is its own top-level tab (see `PIPELINE TAB - P1-1`).
- Carousel cards are permission-filtered: PL / Cash Flow / A/R / Jobs need `finances.view`, Forecast needs `pipeline.view`. With neither permission the hero is hidden entirely.
- **Owner** — the full 5-card carousel and all 3 segments. **Operator** (estimates + expenses only) — no carousel; Estimates and Expenses segments. **Crew** (own-scope expenses only) — auto-skipped past the hub straight to `MyExpensesView` (`MainTabView.booksAutoSkipDestination`, triggered when exactly one segment is visible).

**FAB integration:**
- The global `FloatingActionMenu` re-orders its MONEY group via `@AppStorage("books.selectedSegment")` so the active segment's create action floats to the front. `add-lead` stays in the MONEY group (the FAB is global; the Pipeline tab split does not move the create entry).

**Sheets / drill-downs:**
- `ARAgingDetailView` — half-sheet (medium/large detents) from Card 3's `TOP CHASE` tile.
- `CashflowForecastScreen` — full-screen, from the cashflow card and the cashflow notification deep link.
- `EstimateDetailView`, `InvoiceDetailView`, `ExpenseBatchDetailView`, `ExpenseFormSheet`, `PaymentRecordSheet` — reachable from the segment lists.

---

### OPS-Web Books (web financial hub) — 2026-06-11

**Purpose:** The desktop mirror of the iOS BOOKS tab — one surface for the company's money. Shipped in WEB OVERHAUL P3.1 (direction A "Instrument Strip", approved 2026-06-11); replaced the standalone web Estimates, Invoices, and Accounting pages and the `/money/cashflow` placeholder.

**Source:** `ops-web/src/app/(dashboard)/books/page.tsx` + `src/components/books/**` (page orchestrator `books-page.tsx`, `ledger-strip.tsx`, `segment-toolbar.tsx`, `segments/{invoices,estimates,expenses,sync}-segment.tsx`, `segments/ar-aging-view.tsx`, `modals/`). Data: `src/lib/api/services/books-service.ts` (`computeLedger`) via `useBooksLedger`.

**URL contract:** `/books?segment=invoices|estimates|expenses|sync` + `&view=aging|connections|import` + `&status=<doc status>` + `&action=new`. Retired routes 308-redirect param-preserving in `src/middleware.ts` (`/estimates`, `/invoices`, `/accounting` tab-aware, `/money/cashflow`, `/books/cashflow`).

**Layout (top to bottom):**

1. **Ledger strip** — `// LEDGER` + PeriodPill (same 8 windows as iOS) over four glance tiles translating the iOS Mission Deck card faces to desktop: **NET** (whole-dollar hero, margin meter, `IN`/`OUT` row), **CASH FLOW** (avg/week hero, weekly-net sparkline with rose low-week dot, `LOW WK`), **A/R** (`ALL OPEN` scope badge, hero total, 4-bucket aging ramp, `OVERDUE` + `TOP CHASE`), **JOBS** (profitable count, diverging profit/loss bars with the iOS worst-loser floor, `AVG MARGIN` + losers). Gated `accounting.view` (web analog of iOS `finances.view`); whole strip hides without it. Count-ups/draw-ons use the single OPS easing with reduced-motion fallbacks; tiles skeleton on load and fail to a strip-level `// ERROR` + RETRY.
2. **Segment control** — `INVOICES | ESTIMATES | EXPENSES | SYNC` with mono counts; active segment persists (`localStorage books.segment`) as the no-param default. Unlike iOS there is no crew auto-skip (web has no own-scope expense surface; the expenses segment is the review hub).
3. **Active segment** — full parity ports of the absorbed pages (tables, create/edit modals, record-payment, SendEstimateFlow, convert-to-invoice, PDF download, setup gate, `?action=new`), plus: the A/R drill from the strip drops a rose `PAST DUE ×` chip on the invoices list; `?status=` deep links from dashboard widgets are honored; a quiet mono stat line carries the retired per-tab MetricsHeader numbers.

**Per-segment gates** (never roles): invoices `invoices.view` (or `accounting.view` for the A/R-aging-only view), estimates `estimates.view`, expenses `expenses.approve`, sync `accounting.manage_connections`. Route gate = any-of via the nav registry's `anyOfPermissions`.

**Differences from iOS BooksTabView:** four tiles instead of the 5-card carousel (no Pipeline Forecast tile in v1); drills filter the in-page list instead of opening half-sheets; SYNC (QuickBooks/Sage connections + read-only import) is a first-class segment, where iOS keeps integrations in settings; the cashflow forecast preview card is iOS-only (web full build remains separately planned).

---

### OPS-Web Clients (web client roster + workspace window) — 2026-06-13

**Purpose:** The desktop client book. Shipped in WEB OVERHAUL P3.3 (direction B "lean list + tabbed window", approved 2026-06-13). Replaced the standalone web clients list, the `/clients/[id]` detail page, the `/clients/new` page, the floating client-detail popover, and the create/edit client modals — all retired.

**Source:** list `ops-web/src/app/(dashboard)/clients/page.tsx` + `_components/clients-ar-banner.tsx`; window `src/components/ops/clients/workspace/**` (`client-workspace-container.tsx`, `viewing/{client-viewing-body,client-viewing-tabs,contact-tab,projects-tab,money-tab,activity-tab}.tsx`, `edit-create/client-edit-create-body.tsx`). Reuses the generic project workspace shell `components/ops/projects/workspace/shell/project-workspace-window.tsx` directly. Data: existing client/sub-client/project/invoice/opportunity hooks + new cache-shared aggregates `src/lib/hooks/use-client-financials.ts` (`useClientOutstandingMap`, `useClientFinancials`, `useClientActivity`) — no schema changes. Table primitive: shared `components/ui/register-table/` (the P3-5 presentational extraction of table-v2).

**URL contract:** `/clients` (list). The client surface is a floating window, not a route — opened via `useWindowStore.openClientWindow({ clientId, mode })` (`window-store.ts`, type `"client-workspace"`, size 880×620). Deep link `/dashboard?openClient=<id>&mode=view|edit` (and `openClient=new` → creating) handled by `ClientWorkspaceDeepLinkHandler` in `dashboard-layout.tsx`. Retired routes are thin client redirects: `/clients/[id]` → `/dashboard?openClient={id}` (param-preserving), `/clients/new` → `/dashboard?openClient=new`.

**List layout (top to bottom):** (1) **A/R banner** — slim rose bar, "N clients owe $X — oldest Nd" (oldest = oldest *overdue*), `[CHASE →]` sets the OWES filter; rendered only when the operator has `invoices.view` and someone owes. (2) **Workbar** — `// CLIENTS` label + `SearchInput` (name/email/phone/address/sub-contact names) + one accent `+ NEW CLIENT` CTA (gated `clients.create`, setup-gated). (3) **Filter chips** — ALL / WITH PROJECTS / OWES / NEW(≤30d) + mono count. (4) **`RegisterTable`** — columns CLIENT (avatar + name + sub-contact count) · CONTACT (phone · email) · PROJECTS · OUTSTANDING (rose) · LAST SEEN (max of client createdAt + latest project). Row click → `openClientWindow({mode:"viewing"})`. Scope-aware `clients.view` gate preserved verbatim (scope "all" → all company clients; otherwise restricted to clients on the user's accessible projects; fails closed before permissions resolve). Loading = 6 glass skeletons; distinct empty vs filtered-empty states.

**Window (tabbed dossier):** modes viewing / editing / creating via the shared shell's mode footer. Title bar `// CLIENT · <id8> · [owes chip] · <mode pill>` + Cake name. Viewing tabs: **CONTACT** (phone/email/address with copy + tel/mailto/maps, inline sub-contact CRUD gated `clients.edit`/`clients.delete`, notes), **PROJECTS** (active + completed, row → project window), **MONEY** (invoiced/paid/outstanding/overdue tiles + paid-bar + invoice list; tab disabled without `invoices.view`), **ACTIVITY** (composed timeline: project starts + invoices sent/paid/past-due + won opportunities). Editing/creating render a single RHF+zod form (name*/email/phone-autoformat/address+use-my-location/notes — no company field; gated `clients.edit`/`clients.create`, RLS-backstopped). Footer: viewing → EDIT (hidden without `clients.edit`); editing → DELETE (gated `clients.delete`, confirm modal) + DISCARD + CANCEL + SAVE; creating → CANCEL + CREATE. Created → viewing meta swap mirrors the project window.

**Gates** (never roles): list/route `clients.view` (scope-aware); create `clients.create`; edit `clients.edit`; delete `clients.delete`; MONEY tab + A/R figures `invoices.view`.

**Cross-surface:** FAB `client` action + dashboard-widget client-open retargeted to `openClientWindow`. Notifications stay toast-only for client CRUD (self-action; no rail spam). Per-client outstanding joins `invoices.client_id` (NOT `client_ref`, which is 100% NULL in prod) and excludes paid/void/draft/written_off.

---

### LEADS Tab — Triage Console (2026-08-05 redesign)

**Purpose:** the owner's chase surface (`.all` view scope; the day-sheet branch for `.assigned` delegates is documented in the next section). Opens on "what needs me," carries browse and manipulation controls inline, and demotes business aggregates to a one-line glance. Spec: `ops-ios/docs/superpowers/specs/2026-08-05-leads-console-redesign-design.md`; plan: `ops-ios/docs/plans/2026-08-05-leads-console-redesign.md`. Supersedes both the 2026-05-19 PipelineView description and the 2026-06-30 summary-tile layout.

**Source files:** `Views/Leads/LeadsTabView.swift` (composition), `Views/Leads/Components/LeadsQueueBand.swift` (sticky band), `LeadsSearchBar.swift`, `LeadsControlChips.swift`, `Views/Leads/Triage/LeadsSummary.swift` (command band), `LeadTriageCard.swift`, `Views/Leads/PipelineStageListView.swift` (stage browser), `Utilities/LeadsQueryEngine.swift` (pure list logic; 63 unit tests in `OPSTests/Utilities/LeadsQueryEngineTests.swift`).

**Command band (state-aware, `LeadsQueryEngine.bandState`):**
- *Working* (`needActionCount > 0`): `N NEED ACTION` hero (Mohave-Light 34; rose while overdue > 0, else tan) + toned breakdown (`2 OVERDUE · 1 DUE TODAY · 1 YOUR MOVE`) + metrics line + stage bar.
- *Quiet* (0 due, open leads exist): single line `// ALL QUIET — NO FOLLOW-UPS DUE` + metrics + stage bar. No numeral hero.
- *Empty pipeline*: metrics only; the queue's `LeadsCaughtUp` block owns the message.
- Metrics line (replaced the three bordered KPI tiles): `PIPELINE $X · OPEN N · WON <MMM> $Y` — JetBrains Mono 11, WON segment rendered only when > 0.
- Stage bar: 8pt distribution of open stages; whole row (bar + `BY STAGE ▸`) is one 44pt button pushing the stage browser at its largest stage. The old `LeadsByStageRow` tile strip is deleted.

**Sticky band (pins under the header):** search field + `URGENCY ▾` sort chip + `CREW ▾` crew chip on one row, above the unchanged `TacticalChipRow` bucket chips (ALL / OVERDUE / DUE TODAY / YOUR MOVE / FRESH / WAITING with raw counts).
- **Search** (`LeadsSearchBar`): persistent, per-keystroke, in-memory. Matches folded case/diacritics across contact name, title, description, address, email, source, last-6 id; tokens AND; a ≥3-digit token also digit-matches phone. Population while searching = all open leads + unconverted wins (terminal lost/discarded live only in the stage browser).
- **Search suspends browse filters:** bucket chip + crew filter stop constraining and dim to 40% / lose hit-testing; sort stays live; results render flat under `// MATCHES ─── N`; zero hits → `0` + `// NO MATCHES` + `[ CLEAR SEARCH ]`. Clearing restores prior chip/crew state.
- **Sort:** URGENCY (default; grouped queue) / NEWEST (`createdAt` desc, flat) / VALUE (`estimatedValue` desc, unpriced last, ties newest). Session-state only — remount resets to URGENCY.
- **Crew filter:** ALL CREW / MINE / UNASSIGNED / per-member. ANDs into buckets when not searching. Roster = active company users (`deletedAt == nil`, `isActive != false`) ∪ lead-referenced assignees resolvable to a `User` row; ids fold to lowercase (uppercase-UUID gotcha). **Gate:** all assignment chrome (crew chip + card assignee tokens) renders only when roster > 1 — a solo operator never sees it.

**Card assignee token** (`LeadTriageCard.assigneeLabel`, defaulted nil): meta-row trailing cluster `JASON W · REFERRAL` — first name + last initial uppercased, `UNASSIGNED` (muted) for nil/blank, `UNKNOWN` for unresolvable ids. Day-sheet rows don't pass it; console and stage browser do.

**Stage browser** (`PipelineStageListView`): pushed from the stage bar (or deep code paths that previously fed `footerStage`). In-place scrolling stage tabs (`LABEL · n`, white 2pt underline, never accent) across all six open stages **plus WON and LOST** — first browse path for terminal leads on iOS. Entry stage = `LeadsQueryEngine.entryStage` (max open count, ties → pipeline order). Won/Lost sort by close date desc.

**Unchanged by the redesign:** TriageBucket engine + bucketize rules, chase strip / HANDLED / follow-up send, swipe-to-stage grammar, won-convert nudge, pull-to-refresh + realtime + foreground refresh listeners, deep links, all sheets, and the entire day-sheet branch.

**Proof pack:** `ops-ios/docs/artifacts/leads-console-redesign/` (six PNGs: working band, quiet band, search matches, no matches, newest sort with assignee tokens, stage browser WON tab).

#### Lead detail actions and Won conversion (2026-08-20)

The lead dossier's CONTACT and ASSIGNED TO rows are ordinary tappable controls;
holding still opens their inline editors. Tap recognition is owned by a real
button so the long-press recognizer cannot swallow the action on a physical
device.

Won conversion loads one authoritative project list. Address and client match
flags rank the rows but never invalidate the list, including leads or projects
with no linked client. The create-project address uses the shared MapKit-backed
tokenized input. A selected suggestion carries its coordinates; a manual edit
explicitly clears coordinates that belonged to older text so the new project
cannot inherit a stale map pin.

Before commit, the sheet shows every settled lead photo and eligible inbound
email image in one selected-by-default strip. The operator may toggle items or
choose ALL/NONE. The exact URL and attachment-ID arrays travel inside the
guarded conversion evidence and are revalidated under the opportunity lock.
Omitted arrays retain the legacy select-all contract for older app versions;
explicit empty arrays mean copy none. Photos still queued on the phone are
identified as not included and cannot be silently represented as selectable.

---

### LEADS Tab — Permission Branch + Delegate Day Sheet (2026-07-28)

**Purpose:** the LEADS tab renders a different surface per the operator's pipeline scope. Owners keep the triage console; assigned-scope delegates get a **day sheet** — their leads grouped by whose move it is, with contact/route verbs on every row and a stage-aware milestone button. Spec: `ops-ios/docs/superpowers/specs/2026-07-27-my-leads-day-sheet-design.md` (Jackson-approved).

**Branch rule (`LeadsTabView.showsDaySheet`):** `leadAccessPolicy.scope(for: .view)` — `nil` → no LEADS tab (unchanged `hasLeadsAccess` gate); `.all` → triage console (unchanged); `.assigned` → day sheet. Never branches on role names. One shared shell (AppHeader, `.task` load, all refresh listeners, navigation destinations, every sheet) — only the scroll body swaps, so both surfaces share one data engine (`PipelineViewModel`) and one refresh cadence.

**Day sheet anatomy** (`Views/Leads/DaySheet/`):
- Sub-line `// N LEADS · M YOUR MOVE`; groups `// YOUR MOVE · n` (overdue + due-today + waiting-on-you buckets, most-late first) / `// NEW · n` (fresh, newest first) / `// WAITING · n` (waiting-on-them, soonest comeback first). Empty groups collapse. Pure transform: `DaySheetViewModel.groups(from:policy:now:)` over the console's `TriageBuckets` — no cadence fork, row-filtered defensively with `can(.view, assignedTo:)`.
- Collapsed row (`DaySheetLeadRow`): 56pt thumb (newest photo → map snapshot at coords → initial tile), name, address, compact stage chip (`shortLabel`, long-press = `LeadStatusMenu`, tap = expand) + urgency token (`3D LATE` rose / `TODAY` tan / `YOUR MOVE` neutral / plain `XH AGO` / `BACK FRI`), 44pt CALL + ROUTE verbs. `ViewThatFits` ladder degrades chip detail before ever truncating.
- Expanded card (`DaySheetLeadCard`, accordion, one open): photo strip (shared `LeadPhotosSection`, offline-queued adds) → deck tile (`DeckDesign.thumbnailURL`, tap → `DeckBuilderView`) → agent summary band → contact block (context menus COPY/CALL/TEXT/MAIL) → CALL·TEXT·EMAIL do-and-stamp (`LeadQuickTouchLogger` contracts) → milestone button → `EST $X` (finances.view only) → `FULL LEAD →` (pushes `LeadDetailView`).
- **Milestone button** (`LeadMilestoneEngine` + `LeadMilestoneCommitter`): one stage-aware verb — NEW LEAD→`CONTACTED`→qualifying, QUALIFYING→`SITE VISITED`→quoting, QUOTING→`QUOTE SENT`→quoted, late stages→`WON` (routes to the convert flow; **no won-stamp path exists without convert scope**, so the WON verb hides for edit-only delegates — their stamped run ends at QUOTE SENT). Press = medium haptic + optimistic `move_opportunity_stage` + fact-only activity stamp (subject = verb; `.siteVisit` type for visits, outbound `.note` otherwise) + 5s inline `UNDO` (full revert: stage restored via same RPC, activity hard-deleted). While a press is pending the sheet renders from a pre-press snapshot so the card can't regroup out from under the thumb; on expiry it posts `LeadUpdatedSuccess` and the card glides to its new group (300ms).
- **Offline** (`DaySheetCache` + `MilestoneWriteQueue`): last-good fetch persisted as `[OpportunityDTO]` JSON keyed user+company (Application Support, atomic); renders with `SYS :: OFFLINE — LAST SYNC <T>`; milestone presses queue (requestId-deduped) and drain on connectivity/timer/executor-install — the drain re-checks current stage and skips honestly if the lead moved (`conflictSkipped`). Thumbs prefetched via `PhotoDownloadManager` and served cache-first.
- **Arrival:** the live `lead_assigned` delivery chain (assignment RPC → outbox → cron → rail row + OneSignal push) deep-links through `pendingLeadDeepLinkId`; on the day sheet the drain expands + scrolls to the row (push fallback if unloaded).
- Motion: single OPS curve — expand 250ms, regroup 300ms, undo morph 150ms; reduce-motion falls back to 150ms crossfades (token-level). Haptics: light expand, medium press, success on WON completion (fired by the convert flow).

**Test coverage:** 8 suites / 76 cases (engine map, grouping/ordering/permissions, committer press/undo/expiry/offline/executor, cache round-trip + drain, snapshot proofs for rows/cards/states). Proof pack: `ops-ios/docs/artifacts/my-leads-day-sheet/`.

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

### Unified Log Activity Capture

**Purpose:** One OPS-native capture for every logged interaction — replaces the three former loggers (generic "Log Activity", "Log a Call", and the lead-detail LOG action).

**Source:** `Views/Pipeline/UnifiedLogActivitySheet.swift` + `ViewModels/UnifiedLogActivityViewModel.swift` (single write path: `ActivityRepository`).

**Entry points (all land in the same sheet):**
- **FAB → Log Activity** — opens unbound; operator picks the target (lead / client / job) from `ActivityTargetPickerView`, or a new lead is created inline when nothing matches.
- **Lead detail → LOG** — target locked to that opportunity.
- **Post-call return / Siri / App Shortcut** — target + call provenance (`call_source`, `caller_number`, `call_started_at`) carried in; live phone dedup resolves the lead for the unbound capture path.

**Sheet anatomy (top→bottom):** header (+ optional `// CALLED <name>` provenance subline) · NOTE with an inline DICTATE voice pill · TYPE chips (CALL / EMAIL / MEETING / NOTE — correspondence only; no SITE VISIT, no TEXT) · AGAINST (locked chip or picker row) · DETAIL (DIRECTION for call/email, DURATION for call/meeting, OUTCOME for all but note, optional SUBJECT) · optional FOLLOW-UP row · footer CANCEL / LOG. The steel-blue accent appears once (the primary CTA); selection is a white surface shift, never green.

**Voice capture:** dictation streams a live transcript; on stop it folds into the NOTE body and `VoiceActivityParser` infers type, target, and a follow-up suggestion (date + title). A dictation that ends in an *error* still flushes the partial words (never silently discarded). Follow-up suggestions are never auto-persisted — the operator taps SET (opportunity targets only; `follow_ups` has no client/job parent).

**First-log auto-advance:** the first activity on a `new_lead` opportunity advances it to `qualifying` and writes a `stage_transitions` row — free server behavior preserved by threading `opportunity_id` + `created_by`.

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

**EstimateDetailView document rendering (2026-07-15, bug a8e156a2):**
- Every standalone line-item row shows its math: `TYPE · qty unit × unit price` (JetBrains Mono metadata). Configured products display their resolved snapshot price — the price the server-generated `line_total` was computed from.
- Bundle rows (deck-flow parent/child): parents carry the money (`[N items]` tag), children live behind the header's BREAKDOWN ⇄ BUNDLED toggle as indented breakdown rows.
- All money shows exact cents (`$1,223.58`, never `$1,224`) — line totals, subtotal, tax, total, header amount. Matches web `formatCurrency` (2 fraction digits).
- Tax rates render at true precision (`TAX (7.5%)`, never rounded to `8%`); `tax_rate` is numeric(_,4) and fractional rates are live in prod.
- A derived DISCOUNT row (`subtotal + tax − total`, with `(X%)` when `discountPercent` is synced) sits between SUBTOTAL and TAX so the totals card arithmetic always closes on screen.
- Shared formatting lives in `OPS/Utilities/LineItemDisplay.swift` (also used by InvoiceDetailView and EstimateFormSheet).
- The screen calls `.hidesGlobalTabBar()`; per bug ce6da104 the FAB yields with the tab bar (`MainTabView.fabVisible` folds `tabBarVisibility.isHidden` into the FAB decision — any screen that owns the bottom edge hides both).

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

**InvoiceDetailView document rendering (2026-07-15, bug a8e156a2):**
- Mirrors EstimateDetailView's line-item contract: `TYPE · qty unit × unit price` row meta via `LineItemDisplay`, exact cents on all money (line totals, subtotal, tax, total, PAID, BALANCE DUE, footer), true-precision tax rate, derived DISCOUNT row.
- Bundle-aware: `convert_estimate_to_invoice` copies parent/child line items across (children with remapped parent ids), so the invoice groups them exactly like the estimate — parents bundled by default, BREAKDOWN toggle expands children. The previous flat render visually double-counted every converted bundle.
- The screen calls `.hidesGlobalTabBar()`; the FAB yields with the tab bar (bug ce6da104).

---

### ARAgingDetailView (A/R Drill-Down Sheet)

**Purpose:** Read-only A/R drill — aging buckets + top outstanding clients. Presented as a sheet from the BOOKS carousel's A/R card and the OUTSTANDING drill on the P&L card.

**Source:** `Views/Books/ARAgingDetailView.swift` (replaced the deleted `AccountingDashboard.swift` in an earlier session — bible drift D1, reconciled in Books Phase 2)

**UI Elements:**

1. **Aging Buckets Section** — horizontal bar chart (Swift Charts) with 4 buckets:
   - 0–30 days (`accountingReceivables`)
   - 31–60 days (`accountingReceivables`)
   - 61–90 days (`warningStatus`)
   - 90d+ (`accountingOverdue`)
   - Each bar annotated with the dollar total.

2. **Top Outstanding Section** — ranked list of up to 5 clients with the highest outstanding balances. Client name + dollar amount per row.

**Loaded from:** `AccountingRepository.fetchAllInvoices()` (computes aging client-side).

**Invoice status counts** (Awaiting / Overdue / Paid / Outstanding amount) — these now surface on the BOOKS carousel's PLCard tiles (Outstanding) and ARCard summary line, no longer in a separate dashboard.

**Actions:**
- Pull to refresh → Reload invoice data
- Tap to retry on error state

**Data Source:** Fetches all invoices via AccountingRepository, then computes metrics client-side.

---

### CatalogView (Catalog Tab)

**Purpose:** Variant-aware catalog management — STOCK and PRODUCTS in a single segmented surface, with kebab-grouped advanced operations and an integrated drawing→estimate adapter entrypoint.

**Source:** `Views/Catalog/CatalogView.swift`

**UI Elements:**

1. **Segmented control** — STOCK | PRODUCTS
2. **Kebab menu (⋮)** — STOCK group (Snapshots, Categories, Tags, Units, Thresholds), ORDERS group (Suggested, Drafts, Sent), SETUP group (Defaults, Import, Export)
3. **Threshold banner** — `// N ITEMS BELOW THRESHOLD [REVIEW →]` when applicable; tap → CatalogOrdersSheet
4. **STOCK segment**
   - Compact labeled workbar: LIST · GRID · TABLE, expandable search, filtered/total variant count
   - Stock-scoped category/tag/attribute/threshold filter chips; parent category selection includes descendants
   - Sort controls: Category, Family, Quantity, Low Stock
   - LIST: dense 56pt variant register for fast scan + Quick Adjust
   - GRID: family-first tiles, optional family image, explicit severity counts, 3/2/1-column density
   - TABLE: one selected family, fixed REFERENCE + ON HAND + VS LIMIT columns, horizontally scrollable option-value band; each row identifies WARN or CRIT and stacks at accessibility text sizes
   - Kebab actions: Guided Setup · Stock Setup · Add Variant · Add Family · Import · Snapshots
5. **PRODUCTS segment**
   - Filter chips: type · kind · has-recipe
   - Search
   - Product list — name, price summary, option count, recipe row count
   - FAB: + quick add (3 fields) · + full setup (web)

**Gestures:**
- **Pinch-to-zoom** — scales GRID family tiles between 0.8x-1.5x (persisted via `@AppStorage("catalog.stock.cardScale")`); accessibility adjustable action changes the same density
- **Long press** on a LIST/family-picker row → Open Full Detail
- **Tap** a variant row → StockQuickAdjustSheet; tap a multi-variant GRID family → variant picker
- **Tap** Product row → ProductDetailView

**Related Sheets:**
- CatalogVariantFormSheet (create/edit variant — option-value selectors per family option)
- CatalogFamilyFormSheet (create/edit family — name, category, defaults)
- QuantityAdjustmentSheet (single-variant quick adjust)
- BulkQuantityAdjustmentSheet (bulk adjust selected variants)
- BulkTagsSheet (add/remove family-level tags across selected variants' families)
- CatalogTagsSheet (rename/delete tags globally)
- CatalogCategoriesSheet (manage nested categories)
- CatalogUnitsSheet (manage `catalog_units`)
- CatalogThresholdsSheet (set category-level defaults)
- CatalogOrdersSheet (Suggested · Drafts · Sent)
- CompanyDefaultProductsSheet (component_type → product mapping for drawing adapter)
- SpreadsheetImportSheet (variant-aware import wizard)
- CatalogBulkVariantExpansionFlow (guided FAMILIES → CHANGE → REVIEW dimensional expansion)
- CatalogSnapshotListView (variant-aware historical snapshots)
- ProductDetailView (Product detail — view + light edits; options/modifiers/recipe read-only)
- ProductQuickAddSheet (3-field FAB flow for barebones Products)

**Web sibling (updated 2026-08-16):** `OPS-Web` ships a matching `/catalog` surface (`src/components/catalog/`) with the same PRODUCTS / STOCK segments. It is the variant-aware replacement for the retired `/products` + `/inventory` pages (Direction D "Workbench"): a 3-tile supply strip (STOCK HEALTH / ON-HAND / PRODUCTS), inline quantity editing that writes audited `inventory_deductions` rows keyed by `catalog_variant_id`, a stock detail drawer (quick-adjust + unit-cost + threshold-cascade sources + used-in + adjustment ledger), and a full product editor at `/catalog/products/[id]` (base fields + options + modifiers + recipe) — which is the 308 redirect target of the iOS `ProductDetailView` "VIEW ON WEB →" link (`https://app.ops.dev/products/{id}` → `/catalog/products/{id}`, `ProductDetailView.swift:1054`). Unlike iOS, web authors the configurable layer (options/modifiers/recipe) fully. Its STOCK kebab also exposes the permission-gated Bulk Add Variants workflow described above. Web has no ORDERS surface (`catalog_orders` is consumed nowhere on web) — the buy-run exit is a filter pivot + COPY LIST/PRINT, not a restock order. Threshold status uses the canonical 3-level cascade (variant → family → category); legacy tag thresholds are not consulted (web/iOS agree). Threshold-less variants render as `UNTRACKED`, never `OK`.

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

**Location:** All list screens (home, job board, schedule, estimates, invoices, accounting, catalog)

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

**Location:** Catalog variant cards

**Gesture:**
- Press and hold on card (minimum 0.3 seconds)
- Scale animation (0.95x) provides visual feedback during press

**Action:**
- Opens action sheet with options:
  - Select (enters selection mode)
  - Edit (opens CatalogVariantFormSheet)
  - Delete (destructive, with confirmation dialog)
  - Move to Order (deep-link into CatalogOrdersSheet draft flow)

---

### Pinch to Zoom

**Location:** Navigation view (via Project Details "Get Directions"), image gallery, Catalog STOCK grid mode

**Gesture:**
- Two-finger pinch in/out

**Action:**
- Navigation/gallery: Zoom in/out on map or image
- Catalog grid: Scale CatalogVariant cards between 0.8x and 1.5x. At smaller scales, tags and metadata are progressively hidden for a denser view. Scale is persisted via `@AppStorage("catalogCardScale")`.

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

- All tabs visible (Pipeline, Catalog included)
- All form sheets accessible
- Floating action buttons on all applicable screens
- Can create, edit, delete all entities
- Can assign team members and roles
- Can manage company settings and subscription
- Job Board: All sections visible
- Pipeline: Full access to CRM, estimates, invoices, accounting
- Catalog: Full STOCK + PRODUCTS + ORDERS management (`catalog.view`, `catalog.manage`, `catalog.import`, `catalog.products.manage`, `catalog.orders.manage`)
- **Unique**: Only role with `team.assign_roles` and `settings.billing` by default

---

### Owner (Hierarchy 2)

**All permissions except `team.assign_roles` and `settings.billing`.**

- All tabs visible (Pipeline, Catalog included)
- All form sheets accessible
- Floating action buttons on all applicable screens
- Can create, edit, delete all entities
- Can assign team members (but not assign roles)
- Can manage company settings and integrations
- Cannot manage subscription/billing
- Job Board: All sections visible
- Pipeline: Full access
- Catalog: Full STOCK + PRODUCTS + ORDERS access

---

### Office (Hierarchy 3)

**Full project and financial access. No company settings or role management.**

- All tabs visible (Pipeline, Catalog included)
- All form sheets accessible (except company settings)
- Floating action buttons on applicable screens
- Can create, edit projects/tasks/clients (no project delete)
- Can assign team members
- Cannot manage company settings, billing, or roles
- Job Board: All sections visible
- Pipeline: Full access (view + manage, no stage configuration)
- Catalog: STOCK + PRODUCTS + ORDERS management access

---

### Operator (Hierarchy 4)

**Lead tech — creates projects/estimates, edits assigned work. Scoped access.**

- Pipeline tab: NOT shown (no `pipeline.view` permission)
- Catalog tab: NOT shown (no `catalog.view` permission)
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
- Catalog tab: NOT shown
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

**Last Updated:** May 20, 2026
**Document Version:** 1.4
**iOS App Version:** 207+ Swift files, iOS 17+, SwiftData + SwiftUI
