# 06. Technical Architecture

**Document Purpose**: Complete technical reference for OPS iOS app architecture, file organization, state management patterns, and development best practices.

**Last Updated**: July 16, 2026
**iOS Codebase**: 437+ Swift files, SwiftUI + SwiftData architecture
**Target Platform**: iOS 17.6+, iPhone/iPad

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
12. [Dual-Backend Transition Architecture](#dual-backend-transition-architecture)
13. [Crew Location Tracking Architecture](#crew-location-tracking-architecture)

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
├── Network Layer: Supabase Swift SDK + async/await
├── Sync Engine: DataActor (@ModelActor background writes) + SyncEngine (MainActor orchestration); legacy OutboundProcessor/InboundProcessor retained behind FeatureFlags.useDataActor
├── State Management: ObservableObject + @Published + @Observable
├── Navigation: TabView + NavigationStack
├── Maps: Mapbox SDK (MapboxMaps)
├── Background Tasks: BackgroundSyncScheduler (BGTaskScheduler)
├── Image Handling: FileManager (not UserDefaults)
├── Payments: Stripe SDK
└── Authentication: Keychain + UserDefaults
```

### Architectural Layers

```
┌─────────────────────────────────────────────────────┐
│                    Views (SwiftUI)                   │
│   437 .swift files organized by feature domain      │
├─────────────────────────────────────────────────────┤
│              State Management Layer                  │
│   AppState, DataController, ViewModels (7 files)   │
├─────────────────────────────────────────────────────┤
│                  Business Logic                      │
│   Managers, Services, Utilities (25 files)         │
├─────────────────────────────────────────────────────┤
│                   Data Layer                         │
│   Versioned SwiftData models and API DTOs          │
├─────────────────────────────────────────────────────┤
│                  Network Layer                       │
│   SyncEngine, Processors, Supabase Repositories    │
├─────────────────────────────────────────────────────┤
│                 Platform Services                    │
│   CoreLocation, UserNotifications, Mapbox          │
└─────────────────────────────────────────────────────┘
```

---

## Directory Structure

### Complete File Organization (437 Swift Files)

```
ops-ios/OPS/
├── OPSApp.swift                    # App entry point, versioned model container setup
├── AppDelegate.swift               # Remote notifications, background tasks
├── AppState.swift                  # Global app state (project mode, UI flags)
├── ContentView.swift               # Root view, auth routing, PIN gating
│
├── DataModels/ (35 files)
│   ├── Project.swift               # Project entity with computed dates
│   ├── ProjectTask.swift           # Task entity with calendar integration
│   ├── TaskType.swift              # Customizable task categories
│   ├── TaskStatusOption.swift      # Task status configuration
│   ├── Client.swift                # Client management
│   ├── SubClient.swift             # Additional client contacts
│   ├── User.swift                  # Team members with role-based access
│   ├── Company.swift               # Organization entity
│   ├── TeamMember.swift            # Team member legacy model
│   ├── OpsContact.swift            # Contacts integration
│   ├── SyncOperation.swift         # Offline sync queue entries
│   ├── Status.swift                # Project status enum
│   ├── UserRole.swift              # Role-based permissions
│   ├── SubscriptionEnums.swift     # Subscription types
│   ├── InventoryItem.swift         # Inventory item entity
│   ├── InventorySnapshot.swift     # Inventory count snapshots
│   ├── InventorySnapshotItem.swift # Individual snapshot line items
│   ├── InventoryTag.swift          # Inventory tagging/categorization
│   ├── InventoryUnit.swift         # Units of measure
│   ├── Enums/ (3 files)
│   │   ├── ActivityType.swift      # CRM activity type definitions
│   │   ├── FinancialEnums.swift    # Invoice/payment status enums
│   │   └── PipelineStage.swift     # Sales pipeline stage definitions
│   └── Supabase/ (14 files)
│       ├── Opportunity.swift       # Sales pipeline opportunity
│       ├── Activity.swift          # CRM activity log entry
│       ├── FollowUp.swift          # Scheduled follow-up actions
│       ├── StageTransition.swift   # Pipeline stage change history
│       ├── Estimate.swift          # Project cost estimates
│       ├── EstimateLineItem.swift  # Individual estimate line items
│       ├── Invoice.swift           # Client invoices
│       ├── InvoiceLineItem.swift   # Individual invoice line items
│       ├── Payment.swift           # Payment records
│       ├── Product.swift           # Products/materials catalog
│       ├── SiteVisit.swift         # Site visit records
│       ├── ProjectNote.swift       # Project notes
│       ├── PhotoAnnotation.swift   # Photo markup annotations
│       └── CalendarUserEvent.swift # Personal events + time-off requests (added 2026-03-02)
│
├── Network/ (54 files — updated 2026-03-08)
│   ├── Auth/ (6 files)
│   │   ├── AuthManager.swift       # Authentication coordinator
│   │   ├── GoogleSignInManager.swift
│   │   ├── AppleSignInManager.swift
│   │   ├── KeychainManager.swift   # Secure token storage
│   │   ├── SimplePINManager.swift  # 4-digit PIN (iOS)
│   │   └── AuthError.swift
│   ├── DTOs/ (5 files)
│   │   ├── InventoryItemDTO.swift
│   │   ├── InventorySnapshotDTO.swift
│   │   ├── InventorySnapshotItemDTO.swift
│   │   ├── InventoryUnitDTO.swift
│   │   └── InventoryTagDTO.swift
│   ├── Supabase/ (30 files — updated 2026-03-02)
│   │   ├── SupabaseService.swift   # Core Supabase client wrapper
│   │   ├── SupabaseConfig.swift    # Supabase URL/keys configuration
│   │   ├── DTOs/ (12 files)
│   │   │   ├── CoreEntityDTOs.swift           # Project/Task/User/Client/Company DTOs
│   │   │   ├── CoreEntityConverters.swift     # DTO-to-SwiftData model converters
│   │   │   ├── OpportunityDTOs.swift          # Pipeline opportunity DTOs
│   │   │   ├── EstimateDTOs.swift             # Estimate DTOs
│   │   │   ├── InvoiceDTOs.swift              # Invoice DTOs
│   │   │   ├── ProductDTOs.swift              # Product catalog DTOs
│   │   │   ├── InventoryDTOs.swift            # Inventory DTOs
│   │   │   ├── ProjectNoteDTOs.swift          # Project notes DTOs
│   │   │   ├── PhotoAnnotationDTOs.swift      # Photo annotation DTOs
│   │   │   ├── NotificationDTO.swift          # Push notification DTOs
│   │   │   ├── CalendarUserEventDTOs.swift    # Personal event / time-off DTOs (added 2026-03-02)
│   │   │   └── SupabaseDateParsing.swift      # Date format parsing utilities
│   │   └── Repositories/ (16 files)
│   │       ├── ProjectRepository.swift
│   │       ├── TaskRepository.swift
│   │       ├── ClientRepository.swift
│   │       ├── UserRepository.swift
│   │       ├── CompanyRepository.swift
│   │       ├── TaskTypeRepository.swift
│   │       ├── OpportunityRepository.swift
│   │       ├── EstimateRepository.swift
│   │       ├── InvoiceRepository.swift
│   │       ├── ProductRepository.swift
│   │       ├── InventoryRepository.swift
│   │       ├── AccountingRepository.swift
│   │       ├── ProjectNoteRepository.swift
│   │       ├── PhotoAnnotationRepository.swift
│   │       ├── NotificationRepository.swift
│   │       └── CalendarUserEventRepository.swift  # CRUD for calendar_user_events (added 2026-03-02)
│   ├── Sync/ (12 files — rebuilt 2026-03-08, DataActor refactor 2026-04-19, SYNC RECOVERY 2026-07-22)
│   │   ├── SyncEngine.swift             # @MainActor @Observable orchestrator; dispatches through DataActor when FeatureFlags.useDataActor is on (default true 2026-04-19); reenqueueRecoverableOperations() launch/reconnect sweep + one-time deck-link backfill (2026-07-22)
│   │   ├── SyncErrorClassifier.swift    # Pure failure-disposition seam (SYNC RECOVERY 2026-07-22): transient (5xx/429/408/timeouts/40001-class SQLSTATEs) vs permanent (other 4xx, 22xxx/23xxx/42xxx/P000x) vs auth (PGRST3xx/JWT/401). SyncOperationFailurePolicy = the ONE shared post-catch state transition both outbound paths call
│   │   ├── RecoveryInventory.swift      # Pure PENDING WORK model: indefinite retention, STALE · 30D review state, capability-safe discard (scopes: leadDeliveryRequest / localPhotos / queuedSends / quarantinedVisit, only the latter two of which are `isDestructive`), and attention/sending/drafts/unlinked joins across SyncOperations + lead autocreate + LocalPhotos + site-visit packets + orphan decks. `SiteVisitBundle.hasOperationInFlight` is carried explicitly — `members` holds one worst-tone representative per packet stage, so a `failed` sibling would otherwise mask an `inProgress` send from the discard guard
│   │   ├── RecoveryRefreshSignal.swift  # Event-driven refresh for the sync pill + PENDING WORK (2026-08-10): store-change publisher, 500ms RunLoop.main debounce (never DispatchQueue.main), injectable scheduler; RecoveryRefreshMonitor owns the pipeline as @StateObject so re-renders can't drop in-flight events
│   │   ├── OutboundProcessor.swift      # LEGACY @MainActor path for local→server push; retained behind FeatureFlags.useDataActor for rollback
│   │   ├── InboundProcessor.swift       # LEGACY @MainActor path for server→local pull; retained behind FeatureFlags.useDataActor for rollback
│   │   ├── RealtimeProcessor.swift      # @MainActor Supabase Realtime WebSocket subscription (9 merged entity types + 3 notification-only leads tables: opportunities/activities/follow_ups → post .opsLeadsDidChange, no SwiftData merge); SwiftData writes dispatch to DataActor when flag on
│   │   ├── PhotoProcessor.swift         # @MainActor adaptive photo uploads (WiFi 3 concurrent, cellular 1) — moves to PhotoActor in Phase 3
│   │   ├── BackgroundSyncScheduler.swift  # BGTaskScheduler wrapper (refresh 15min, processing 30min)
│   │   ├── SyncTypes.swift              # Shared enums (SyncError, ConnectionState, SyncEntityType — 27 registered, 12 inbound-synced)
│   │   └── SupabaseSyncManager.swift    # Legacy adapter (retained for entity fetch methods not yet migrated)
│   ├── Services/ (1 file)
│   │   └── AppMessageService.swift
│   ├── ConnectivityManager.swift   # @MainActor ObservableObject NWPathMonitor with quality scoring + lying WiFi detection
│   ├── ImageSyncManager.swift      # S3 image upload/download
│   ├── S3UploadService.swift       # Direct S3 upload
│   ├── PresignedURLUploadService.swift
│   └── PhotoAnnotationSyncManager.swift  # Photo annotation sync
│
├── ViewModels/ (7 files)
│   ├── CalendarViewModel.swift     # Calendar state, date selection, filters
│   ├── ProjectsViewModel.swift     # Project list state
│   ├── PipelineViewModel.swift     # Sales pipeline / LEADS state; direct-fetch (outside SwiftData sync). Merge-based auto-refresh: realtime (.opsLeadsDidChange) + foreground-resume + pull-to-refresh funnel through one debounced, coalesced reload that merges server rows into existing Opportunity instances by id (identity preserved, pushed detail stays live)
│   ├── OpportunityDetailViewModel.swift  # Opportunity detail state
│   ├── EstimateViewModel.swift     # Estimate management state
│   ├── InvoiceViewModel.swift      # Invoice management state
│   └── ProjectNotesViewModel.swift # Project notes state
│
├── Views/ (~192 files organized by feature)
│   ├── MainTabView.swift           # Tab navigation root
│   ├── LoginView.swift             # Authentication entry
│   ├── ForgotPasswordView.swift    # Password reset
│   ├── SplashScreen.swift          # App launch screen
│   ├── SimplePINEntryView.swift    # PIN authentication UI
│   ├── ScheduleView.swift          # Calendar/schedule tab root
│   ├── SettingsView.swift          # Settings tab root
│   │
│   ├── Home/ (2 files)
│   │   ├── HomeView.swift          # Project carousel, quick actions
│   │   └── HomeContentView.swift   # Home screen content wrapper
│   │
│   ├── JobBoard/ (21 files)
│   │   ├── JobBoardView.swift             # Main job board — role-based section switcher
│   │   ├── JobBoardProjectListView.swift  # Projects section (office/admin)
│   │   ├── JobBoardMyTasksView.swift      # My Tasks section (field crew)
│   │   ├── JobBoardKanbanView.swift       # Kanban status view (office/admin)
│   │   ├── JobBoardAnalyticsView.swift    # Analytics dashboard
│   │   ├── UniversalJobBoardCard.swift    # Universal project/task/client card
│   │   ├── UniversalSearchBar.swift       # Inline search bar component
│   │   ├── UniversalSearchSheet.swift     # Full-screen role-filtered search sheet
│   │   ├── ProjectFormSheet.swift         # Project create/edit form
│   │   ├── TaskFormSheet.swift            # Task create/edit form
│   │   ├── ClientSheet.swift              # Client form
│   │   ├── ClientListView.swift           # Client directory
│   │   ├── CopyFromProjectSheet.swift
│   │   ├── TaskTypeSheet.swift            # Task type management
│   │   ├── TaskTypeDetailSheet.swift
│   │   ├── QuickActionSheetHeader.swift
│   │   ├── TaskManagementSheets.swift
│   │   ├── ProjectManagementSheets.swift
│   │   ├── ProjectListFilterSheet.swift
│   │   ├── TaskListFilterSheet.swift
│   │   └── SortOptions.swift
│   │
│   ├── Calendar Tab/ (15 files — updated 2026-03-02)
│   │   ├── DayCanvasView.swift     # Horizontal 3-page day pager (replaces ProjectListView)
│   │   ├── MonthGridView.swift     # Full month grid (pinch-to-collapse)
│   │   ├── Components/ (13 files)
│   │   │   ├── CalendarEventCard.swift          # Task card with DayPosition multi-day bleed
│   │   │   ├── CalendarUserEventCard.swift       # Personal event / time-off card (added 2026-03-02)
│   │   │   ├── CalendarHeaderView.swift
│   │   │   ├── CalendarFilterView.swift
│   │   │   ├── CalendarDaySelector.swift        # Week strip + month grid toggle
│   │   │   ├── WeekDayCell.swift                # Day cell with density bars
│   │   │   ├── PersonalEventSheet.swift         # Create personal event bottom sheet (added 2026-03-02)
│   │   │   ├── TimeOffRequestSheet.swift        # Submit time-off request bottom sheet (added 2026-03-02)
│   │   │   ├── ProjectSearchFilterView.swift
│   │   │   ├── ProjectSearchSheet.swift
│   │   │   ├── DatePickerPopover.swift
│   │   │   ├── DayCell.swift
│   │   │   └── SegmentedBorder.swift
│   │   │
│   │   # Deleted: CalendarToggleView.swift (replaced by CalendarDaySelector month toggle)
│   │   # Deleted: ProjectListView.swift (replaced by DayCanvasView)
│   │
│   ├── Settings/ (23 files)
│   │   ├── ProfileSettingsView.swift
│   │   ├── SecuritySettingsView.swift
│   │   ├── NotificationSettingsView.swift
│   │   ├── MapSettingsView.swift
│   │   ├── DataStorageSettingsView.swift
│   │   ├── AppSettingsView.swift
│   │   ├── ProjectSettingsView.swift
│   │   ├── TaskSettingsView.swift
│   │   ├── OrganizationSettingsView.swift
│   │   ├── InventorySettingsView.swift
│   │   ├── IntegrationsSettingsView.swift
│   │   ├── SchedulingTypeExplanationView.swift
│   │   ├── WhatsNewView.swift
│   │   ├── ComingSoonView.swift
│   │   ├── SettingsSearchSheet.swift
│   │   ├── Organization/ (3 files)
│   │   │   ├── OrganizationDetailsView.swift
│   │   │   ├── ManageTeamView.swift
│   │   │   └── ManageSubscriptionView.swift
│   │   └── Components/ (4 files)
│   │       ├── SettingsComponents.swift
│   │       ├── ReportIssueView.swift
│   │       ├── FeatureRequestView.swift
│   │       ├── NotificationSettingsControls.swift
│   │       └── ProjectNotificationPreferences.swift
│   │
│   ├── Components/ (76 files organized by domain)
│   │   ├── Common/ (28 files)
│   │   │   ├── LoadingOverlay.swift
│   │   │   ├── CustomTabBar.swift
│   │   │   ├── TabBarBackground.swift
│   │   │   ├── KeepAliveTabContainer.swift  # Keep-alive tab slots + slide geometry (2026-08-10); every visited tab stays mounted — see § Navigation System
│   │   │   ├── TabActivationKey.swift       # \.isActiveTab environment key + onReceiveWhileActive; the activation protocol hidden tabs are held to
│   │   │   ├── AppHeader.swift
│   │   │   ├── SearchField.swift
│   │   │   ├── AddressSearchField.swift
│   │   │   ├── AddressAutocompleteField.swift
│   │   │   ├── CustomAlert.swift
│   │   │   ├── DeleteConfirmation.swift
│   │   │   ├── DeletionSheet.swift
│   │   │   ├── TacticalLoadingBar.swift
│   │   │   ├── NotificationBanner.swift
│   │   │   ├── NavigationBanner.swift
│   │   │   ├── StorageOptionSlider.swift
│   │   │   ├── ImageSyncProgressView.swift
│   │   │   ├── ExpandableNotesView.swift
│   │   │   ├── UnassignedRolesOverlay.swift
│   │   │   ├── AppMessageView.swift
│   │   │   ├── RefreshIndicator.swift
│   │   │   ├── NavigationControlsView.swift
│   │   │   ├── ContactDetailSheet.swift
│   │   │   ├── PushInMessage.swift
│   │   │   ├── ReassignmentRows.swift
│   │   │   ├── LocationPermissionView.swift
│   │   │   ├── FilterSheet.swift
│   │   │   └── CompanyTeamListView.swift
│   │   ├── Cards/ (5 files)
│   │   │   ├── ClientInfoCard.swift
│   │   │   ├── CompanyContactCard.swift
│   │   │   ├── LocationCard.swift
│   │   │   ├── NotesCard.swift
│   │   │   └── TeamMembersCard.swift
│   │   ├── Project/ (9 files)
│   │   │   ├── ProjectCard.swift
│   │   │   ├── ProjectCarousel.swift
│   │   │   ├── ProjectHeader.swift
│   │   │   ├── ProjectActionBar.swift
│   │   │   ├── ProjectDetailsView.swift
│   │   │   ├── TaskDetailsView.swift
│   │   │   ├── TaskCompletionChecklistSheet.swift
│   │   │   ├── ProjectSheetContainer.swift
│   │   │   ├── ProjectSummaryCard.swift
│   │   │   └── ProjectNotesView.swift
│   │   ├── Images/ (6 files)
│   │   │   ├── ImagePicker.swift
│   │   │   ├── ImagePickerView.swift
│   │   │   ├── ProjectImagesSimple.swift
│   │   │   ├── ProjectImagesSection.swift
│   │   │   ├── ProjectImageView.swift
│   │   │   ├── ProjectPhotosGrid.swift
│   │   │   └── PhotoAnnotationView.swift
│   │   ├── Map/ (4 files)
│   │   │   ├── ProjectMapAnnotation.swift
│   │   │   ├── MiniMapView.swift
│   │   │   ├── ProjectMapView.swift
│   │   │   └── RouteDirectionsView.swift
│   │   ├── User/ (7 files)
│   │   │   ├── CompanyTeamMembersListView.swift
│   │   │   ├── ProjectTeamView.swift
│   │   │   ├── OrganizationTeamView.swift
│   │   │   ├── TeamMemberListView.swift
│   │   │   ├── TaskTeamView.swift
│   │   │   ├── UserProfileCard.swift
│   │   │   └── ContactDetailView.swift
│   │   ├── Contact/ (3 files)
│   │   │   ├── ContactCreatorView.swift
│   │   │   ├── ContactPicker.swift
│   │   │   └── ContactUpdater.swift
│   │   ├── Client/ (2 files)
│   │   │   ├── SubClientListView.swift
│   │   │   └── SubClientEditSheet.swift
│   │   ├── Event/ (1 file)
│   │   │   └── EventCarousel.swift
│   │   ├── Tasks/ (1 file)
│   │   │   └── TaskListView.swift
│   │   ├── Task/ (1 file)
│   │   │   └── TaskSelectorBar.swift
│   │   ├── Scheduling/ (13 files — sheet rebuilt 2026-07-27, refined 2026-07-29)
│   │   │   ├── CalendarSchedulerSheet.swift    # Date picker: chrome, day panel, SchedulerEventRow
│   │   │   ├── SchedulerDayContext.swift       # Availability engine + SchedulerSelection (pure logic)
│   │   │   ├── ComparableJobLength.swift       # Duration from same-type jobs on similar-area decks
│   │   │   ├── SchedulerMonthScroll.swift      # Continuous month list; owns span-outline closure
│   │   │   ├── SchedulerDayCell.swift          # Day cell + signal bars + SchedulerSpanCurve + SpanEdgeStroke + DiagonalHatch
│   │   │   ├── SchedulerFooterBar.swift        # Sticky CLEAR / SAVE bar (single commit point)
│   │   │   ├── SchedulerDaySheet.swift         # Long-press day inspector
│   │   │   ├── CascadePreviewSheet.swift
│   │   │   ├── DependencyPickerSheet.swift
│   │   │   ├── PriorityQueueRow.swift
│   │   │   ├── PriorityQueueView.swift
│   │   │   ├── PrioritySchedulePreviewSheet.swift
│   │   │   └── ScheduleConnectivityStrip.swift
│   │   ├── Sync/ (2 files — updated 2026-03-08)
│   │   │   ├── SyncStatusIndicator.swift
│   │   │   └── SyncRingView.swift         # Rotating arc indicator shown in AppHeader during sync
│   │   ├── Team/ (2 files)
│   │   │   ├── TeamRoleManagementView.swift
│   │   │   └── TeamRoleAssignmentSheet.swift
│   │   ├── FloatingActionMenu.swift
│   │   ├── UserAvatar.swift
│   │   ├── CompanyAvatar.swift
│   │   ├── ProfileImageUploader.swift
│   │   └── OptionalSectionPill.swift
│   │
│   ├── Pipeline/ (12 files)
│   │   ├── PipelineView.swift
│   │   ├── PipelineTabView.swift
│   │   ├── PipelinePlaceholderView.swift
│   │   ├── PipelineStageStrip.swift
│   │   ├── OpportunityCard.swift
│   │   ├── OpportunityDetailView.swift
│   │   ├── OpportunityFormSheet.swift
│   │   ├── OpportunityBadgeView.swift
│   │   ├── ActivityFormSheet.swift
│   │   ├── ActivityRowView.swift
│   │   ├── FollowUpRowView.swift
│   │   └── MarkLostSheet.swift
│   │
│   ├── Inventory/ (12 files)
│   │   ├── InventoryView.swift
│   │   ├── InventoryListView.swift
│   │   ├── InventoryFormSheet.swift
│   │   ├── InventoryManageTagsSheet.swift
│   │   ├── SnapshotListView.swift
│   │   ├── QuantityAdjustmentSheet.swift
│   │   ├── BulkQuantityAdjustmentSheet.swift
│   │   ├── BulkTagsSheet.swift
│   │   └── Import/ (4 files)
│   │       ├── SpreadsheetImportSheet.swift
│   │       ├── ImportConfigView.swift
│   │       ├── ColumnMappingView.swift
│   │       └── ImportPreviewView.swift
│   │
│   ├── Estimates/ (6 files)
│   │   ├── EstimatesListView.swift
│   │   ├── EstimateDetailView.swift
│   │   ├── EstimateFormSheet.swift
│   │   ├── EstimateCard.swift
│   │   ├── LineItemEditSheet.swift
│   │   └── ProductPickerSheet.swift
│   │
│   ├── Invoices/ (4 files)
│   │   ├── InvoicesListView.swift
│   │   ├── InvoiceDetailView.swift
│   │   ├── InvoiceCard.swift
│   │   └── PaymentRecordSheet.swift
│   │
│   ├── Accounting/ (1 file)
│   │   └── AccountingDashboard.swift
│   │
│   ├── Products/ (2 files)
│   │   ├── ProductsListView.swift
│   │   └── ProductFormSheet.swift
│   │
│   ├── Notifications/ (1 file)
│   │   └── NotificationListView.swift  # Includes SyncStatusSection showing pending/failed operations with per-item retry
│   │
│   ├── Debug/ (8 files)
│   │   ├── DeveloperDashboard.swift
│   │   ├── ClearDataView.swift
│   │   ├── ScheduledTasksDebugView.swift
│   │   ├── TaskTypesDebugView.swift
│   │   ├── TaskListDebugView.swift
│   │   ├── TaskTestView.swift
│   │   ├── OnboardingPreviewView.swift
│   │   └── CreateDefaultInventoryUnitsView.swift
│   │
│   └── Subscription/ (4 files)
│       ├── SubscriptionLockoutView.swift
│       ├── GracePeriodBanner.swift
│       ├── SeatManagementView.swift
│       └── PlanSelectionView.swift
│
├── Onboarding/ (rebuilt 2026-06-13 — see note below)
│   # REBUILT EXPRESS FLOW (live as of the 2026-06-13 cutover, flag
│   # FeatureFlags.useRebuiltOnboarding default true):
│   #   Gateway/OnboardingGateway.swift      — the single pre-app mount
│   #   Gateway/*LiveBoundary.swift          — per-screen live auth/data adapters
│   #   Gateway/OnboardingFunnelAnalytics.swift — per-step funnel tracker
│   #   Flow/OnboardingFlowCoordinator.swift — step machine + back map + resume
│   #   Flow/OnboardingFlowStep.swift, Flow/OnboardingResume.swift
│   #   State/OnboardingFlowState.swift      — onboarding_state_v4 blob + v3 migration
│   #   Screens/*StepView.swift              — Welcome/Login/RolePick/CreateAccount/
│   #                                            CompanyName/CrewCode/InviteCheck/
│   #                                            InvitePicker/CodeEntry/ConfirmCompany/
│   #                                            Profile/EmergencyContact/CompletionGate
│   #   Manager/OnboardingManager.swift (hardened, kept), Services/OnboardingService.swift,
│   #   Screens/WorkspacePreloadGate.swift (kept)
│   # The legacy A/B/C tree below (ABTest/, Container/, Coordinators/, ViewModels/,
│   # Views/, the old Screens/ + Components/, OnboardingCopy.swift, State/OnboardingState.swift)
│   # is now DEAD (no longer mounted) and awaits a deletion pass. Flow narrative:
│   # 02_USER_EXPERIENCE_AND_WORKFLOWS.md § iOS Onboarding — The Rebuilt Express Flow.
│   ├── OnboardingCopy.swift        # Copy text constants (legacy, dead)
│   ├── Container/ (1 file)
│   │   └── OnboardingContainer.swift
│   ├── Coordinators/ (1 file)
│   │   └── OnboardingCoordinator.swift
│   ├── Manager/ (1 file)
│   │   └── OnboardingManager.swift
│   ├── State/ (1 file)
│   │   └── OnboardingState.swift
│   ├── Models/ (1 file)
│   │   └── OnboardingModels.swift
│   ├── Services/ (1 file)
│   │   └── OnboardingService.swift
│   ├── ViewModels/ (1 file)
│   │   └── OnboardingViewModel.swift
│   ├── Screens/ (13 files)
│   │   ├── WelcomeScreen.swift
│   │   ├── UserTypeSelectionScreen.swift
│   │   ├── CompanySetupScreen.swift
│   │   ├── SignupScreen.swift
│   │   ├── ProfileScreen.swift
│   │   ├── ProfileJoinScreen.swift
│   │   ├── ProfileCompanyScreen.swift
│   │   ├── CredentialsScreen.swift
│   │   ├── LoginScreen.swift
│   │   ├── ReadyScreen.swift
│   │   ├── PostTutorialCTAScreen.swift
│   │   ├── CodeEntryScreen.swift
│   │   ├── CompanyDetailsScreen.swift
│   │   └── CompanyCodeScreen.swift
│   ├── Views/ (18 files)
│   │   ├── OnboardingPresenter.swift
│   │   ├── OnboardingPreviewHelpers.swift
│   │   ├── OnboardingContainerView.swift
│   │   ├── OnboardingFlowPreview.swift
│   │   ├── Screens/ (10 files)
│   │   │   ├── OrganizationJoinView.swift
│   │   │   ├── FieldSetupView.swift
│   │   │   ├── EmailView.swift
│   │   │   ├── UserInfoView.swift
│   │   │   ├── CompanyCreationLoadingView.swift
│   │   │   ├── CompanyContactView.swift
│   │   │   ├── CompanyAddressView.swift
│   │   │   ├── CompanyBasicInfoView.swift
│   │   │   ├── WelcomeView.swift
│   │   │   ├── CompletionView.swift
│   │   │   ├── CompanyCodeDisplayView.swift
│   │   │   ├── TeamInvitesView.swift
│   │   │   ├── PermissionsView.swift
│   │   │   ├── CompanyCodeInputView.swift
│   │   │   ├── BillingInfoView.swift
│   │   │   ├── CompanyDetailsView.swift
│   │   │   └── UserTypeSelectionView.swift
│   │   └── Components/ (2 files)
│   │       ├── OnboardingComponents.swift
│   │       └── AnimatedOPSLogo.swift
│   └── Components/ (10 files)
│       ├── OnboardingProgressBar.swift
│       ├── OnboardingScaffold.swift
│       ├── PillButtonGroup.swift
│       ├── OnboardingHeader.swift
│       ├── UserTypeSelectionContent.swift
│       ├── SocialAuthButton.swift
│       ├── OnboardingHelpSheet.swift
│       ├── TypewriterText.swift
│       ├── OnboardingPrimaryButton.swift
│       ├── CompanyCodeDisplay.swift
│       └── OnboardingLoadingOverlay.swift
│
├── Tutorial/ (21 files)
│   ├── Analytics/ (1 file)
│   │   └── TutorialAnalyticsService.swift
│   ├── Data/ (6 files)
│   │   ├── TutorialDemoDataManager.swift
│   │   ├── DemoProjects.swift
│   │   ├── DemoClients.swift
│   │   ├── DemoTaskTypes.swift
│   │   ├── DemoTeamMembers.swift
│   │   └── DemoIDs.swift
│   ├── Environment/ (1 file)
│   │   └── TutorialEnvironment.swift
│   ├── State/ (2 files)
│   │   ├── TutorialStateManager.swift
│   │   └── TutorialPhase.swift
│   ├── Flows/ (1 file)
│   │   └── TutorialLauncherView.swift
│   ├── Utilities/ (1 file)
│   │   └── PreferenceKeys.swift
│   ├── Views/ (7 files)
│   │   ├── TutorialOverlayView.swift
│   │   ├── TutorialTooltipView.swift
│   │   ├── TutorialCollapsibleTooltip.swift
│   │   ├── TutorialSwipeIndicator.swift
│   │   ├── TutorialInlineSheet.swift
│   │   ├── TutorialActionBar.swift
│   │   └── TutorialCompletionView.swift
│   └── Wrappers/ (2 files)
│       ├── TutorialCreatorFlowWrapper.swift
│       └── TutorialEmployeeFlowWrapper.swift
│
├── Map/ (19 files)
│   ├── Core/ (6 files)
│   │   ├── OPSMapCoordinator.swift    # Map state management
│   │   ├── OPSNavigationManager.swift # Turn-by-turn navigation
│   │   ├── GeofenceManager.swift      # Geofencing for job sites
│   │   ├── OPSMapStyle.swift          # Custom map styling
│   │   ├── MapStyleApplicator.swift   # Style application logic
│   │   └── MapboxConfig.swift         # Mapbox SDK configuration
│   ├── Models/ (1 file)
│   │   └── CrewLocationUpdate.swift   # Real-time crew position model
│   ├── Annotations/ (2 files)
│   │   ├── CrewAnnotationRenderer.swift   # Crew member map pins
│   │   └── ProjectAnnotationRenderer.swift # Project location pins
│   ├── Services/ (2 files)
│   │   ├── CrewLocationBroadcaster.swift  # Publishes device location to Supabase
│   │   └── CrewLocationSubscriber.swift   # Subscribes to crew locations via Supabase Realtime
│   └── Views/ (8 files)
│       ├── OPSMapView.swift
│       ├── OPSMapContainer.swift
│       ├── MapLocationPermissionView.swift
│       ├── NavigationHeader.swift
│       ├── MapFilterChips.swift
│       ├── ProjectPinCard.swift
│       ├── CrewTooltipCard.swift
│       └── GeofenceBannerView.swift
│
├── Utilities/ (85 Swift files + Analytics/ — key files listed)
│   ├── DataController.swift        # Central data coordinator (~5000 lines; @MainActor, owns DataActor + refresh bridge)
│   ├── ReviewUnlockThresholds.swift  # Single source for the completed-work counts that unlock Task Review + Payment Review (2026-08-10). Distinct from ReviewThresholdService.threshold (rail-notification loudness)
│   ├── ReviewCountRefreshMonitor.swift  # Debounced refresh pipeline for the FAB review badge (2026-08-10); same RunLoop.main scheduler seam as RecoveryRefreshMonitor
│   ├── DataActor.swift             # @ModelActor singleton — owns all sync/cleanup/background SwiftData writes (~2400 lines, Phase 1 2026-04-19)
│   ├── MainContextRefreshBridge.swift  # Sendable notification rebroadcast for @Query refresh (iOS 18.2 FB14750050 insurance; iOS 26 fixed)
│   ├── FeatureFlags.swift          # useDataActor (default true), useActorForDataControllerWrites (Phase 2), usePhotoActor (Phase 3)
│   ├── DataHealthManager.swift     # Data integrity checks
│   ├── AnalyticsManager.swift      # Event tracking
│   ├── ImageFileManager.swift      # File-based image storage
│   ├── ImageCache.swift            # In-memory image cache
│   ├── LocationManager.swift       # Location permissions + updates
│   ├── NotificationManager.swift   # Push notification handling
│   ├── SubscriptionManager.swift   # Stripe subscription sync
│   ├── FieldErrorHandler.swift     # User-facing error display
│   ├── DebugLogger.swift           # Debug logging utilities
│   ├── InProgressManager.swift     # In-progress state tracking
│   ├── NotificationBatcher.swift   # Notification batching
│   ├── OnboardingAnalyticsService.swift  # Onboarding event tracking
│   ├── SpreadsheetParser.swift     # CSV/spreadsheet import parsing
│   ├── AppConfiguration.swift      # App-level config
│   ├── DateHelper.swift            # Date formatting utilities
│   ├── StripeConfiguration.swift   # Stripe SDK configuration
│   ├── UIComponents.swift          # Shared UI helpers
│   ├── TabBarPadding.swift         # Tab bar spacing utilities
│   ├── SwiftDataHelper.swift       # SwiftData convenience methods
│   ├── ArrayTransformer.swift      # Array value transformer
│   ├── SwipeBackGestureModifier.swift  # Swipe-to-go-back modifier
│   ├── SwipeBackGesture.swift      # Swipe gesture recognizer
│   ├── KeyboardDismissalModifier.swift # Keyboard dismiss on tap
│   └── UIColor+Hex.swift           # UIColor hex string conversion
│
├── Styles/ (19 files)
│   ├── OPSStyle.swift              # Design system constants
│   ├── Fonts.swift                 # Typography definitions
│   └── Components/ (17 files)
│       ├── ButtonStyles.swift
│       ├── CardStyles.swift
│       ├── FormInputs.swift
│       ├── FormTextField.swift
│       ├── ExpandableSection.swift
│       ├── IconBadge.swift
│       ├── SectionCard.swift
│       ├── SegmentedControl.swift
│       ├── TaskLineItem.swift
│       ├── StatusBadge.swift
│       ├── ProfileCard.swift
│       ├── OPSComponents.swift
│       ├── CategoryCard.swift
│       ├── ListItems.swift
│       ├── NotesDisplayField.swift
│       ├── SettingsHeader.swift
│       └── StandardSheetToolbar.swift
│
├── Extensions/ (4 files)
│   ├── String+AddressFormatting.swift
│   ├── UIApplication+Extensions.swift
│   ├── UIImage+Extensions.swift
│   └── UIKit+Extensions.swift
│
├── Services/ (2 files)
│   ├── OneSignalService.swift      # Push notification provider
│   └── StripeService.swift         # Stripe payment integration
│
├── V2/ (1 file)
│   └── CertificationsSettingsView.swift  # Future certifications feature
│
└── Tests/ (1 file)
    └── MapTapGestureTest.swift     # Map gesture test
```

### File Count Summary

```
Total: 437 Swift files

By Category:
- Views/UI: ~192 files (44%)
- Onboarding: 56 files (13%)
- Network/API: 50 files (11%)
- DataModels: 35 files (8%)
- Utilities: 25 files (6%)
- Tutorial: 21 files (5%)
- Map: 19 files (4%)
- Styles: 19 files (4%)
- ViewModels: 7 files (2%)
- Root files: 4 files (1%)
- Extensions: 4 files (1%)
- Services: 2 files (<1%)
- V2: 1 file (<1%)
- Tests: 1 file (<1%)
```

---

## SwiftUI + SwiftData Architecture

### SwiftData Model Container Setup

```swift
// OPSApp.swift
@main
struct OPSApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema(versionedSchema: OPSSchemaV16.self)
        let isHostedXCTest = ProcessInfo.processInfo.environment["XCTestBundlePath"] != nil
        let modelConfiguration = OPSModelStore.configuration(
            schema: schema,
            isStoredInMemoryOnly: isHostedXCTest
        )

        do {
            return try ModelContainer(
                for: schema,
                migrationPlan: OPSMigrationPlan.self,
                configurations: modelConfiguration
            )
        } catch {
            fatalError(
                "Failed to open SwiftData store at \(modelConfiguration.url.path). "
                    + "The store was preserved. \(error)"
            )
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(dataController)
                .environmentObject(notificationManager)
                .environmentObject(subscriptionManager)
        }
        .modelContainer(sharedModelContainer)
    }
}
```

`OPSModelStore` is the sole production configuration contract. It selects `ModelConfiguration.GroupContainer.identifier("group.co.opsapp.ops")`, so SwiftData's `default.store` lives in the primary OPS App Group. The app-root container uses in-memory storage without an App Group when hosted by XCTest; migration tests use isolated temporary disk stores.

The schema graph is append-only and released model shapes are immutable. A persistent-property edit to a model referenced by an older `VersionedSchema` changes that version's absolute Core Data checksum and can make installed stores fail with error 134504 (`Cannot use staged migration with an unknown model version`). The required sequence is: freeze the released shape, register the widened live type only in a new schema, add one adjacent migration stage, and extend `OPSTests/Fixtures/swiftdata-released-schema-fingerprints.json`.

Error 134504 is never authorization to delete local data. Bootstrap preserves the SQLite store and sidecars and fails visibly with the exact configuration URL. This protects local-only and not-yet-synced field work. Current implementation: ops-ios commit `a554ee7c`; full data-model history: `03_DATA_ARCHITECTURE.md § Schema V16 — App-update migration reliability`.

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
        tasks.compactMap { $0.startDate }.min()
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
// DTOs handle Supabase ↔ SwiftData conversion
// Core entities use CoreEntityDTOs.swift and CoreEntityConverters.swift
// Domain-specific entities have dedicated DTO files (EstimateDTOs, InvoiceDTOs, etc.)

// Example from CoreEntityDTOs.swift
struct SupabaseProjectDTO: Codable {
    let id: UUID
    let companyId: UUID
    let title: String
    let status: String?
    let address: String?
    let bubbleId: String?
    // ... additional fields

    func toSwiftDataModel() -> Project {
        let project = Project(id: id.uuidString, title: title, companyId: companyId.uuidString)
        project.status = Status(rawValue: status ?? "") ?? .rfq
        project.address = address
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
│ ViewModels   │ │   Managers   │ │ SyncEngine   │
│ (per-screen) │ │  (services)  │ │ (Op Log +    │
│              │ │              │ │  Replay)     │
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

    // MARK: - Map Surface Mirrors
    // OPSMapContainer owns the map coordinator as a private @StateObject, so
    // Home cannot observe it. The container mirrors card visibility here.
    @Published var isShowingMapOverlay: Bool = false          // ANY overlay (hides the FAB)
    @Published var isMapProjectSurfacePresented: Bool = false // PROJECT surfaces only

    // MARK: - Computed Properties
    var isInProjectMode: Bool {
        activeProjectID != nil && !isViewingDetailsOnly
    }

    /// True while ANY project surface is presented over Home — the map pin
    /// card, the stacked-group sheet, or project details. `isInProjectMode`
    /// cannot serve this role: it is false whenever a project is merely being
    /// VIEWED, which is the state all of those surfaces present in. Home hides
    /// its supporting cards on this signal (bug de9099d6).
    var isProjectSurfacePresented: Bool {
        isMapProjectSurfacePresented || isProjectDetailsPresented
    }

    /// Includes the arming window: `showProjectDetailsAfterResetById` sets
    /// `isViewingDetailsOnly` + `activeProjectID` synchronously and flips
    /// `showProjectDetails` a runloop later. Reading `showProjectDetails`
    /// alone would let the Home cards flash back in during that gap.
    private var isProjectDetailsPresented: Bool {
        showProjectDetails || (isViewingDetailsOnly && activeProjectID != nil)
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
    private let keychainManager: KeychainManager
    var modelContext: ModelContext?

    // MARK: - Sync Engine (added 2026-03-08)
    var syncEngine: SyncEngine!           // Central sync orchestrator (created eagerly in setModelContext)
    var connectivity: ConnectivityManager! // NWPathMonitor with quality scoring (created eagerly in setModelContext)

    // MARK: - Legacy Adapter
    var syncManager: SupabaseSyncManager! // Retained for entity fetch methods not yet migrated

    // MARK: - Public Access
    var imageSyncManager: ImageSyncManager!
    @Published var simplePINManager = SimplePINManager()

    // MARK: - Initialization
    init() {
        self.keychainManager = KeychainManager()
        self.authManager = AuthManager()

        Task {
            await checkExistingAuth()
        }
    }

    // MARK: - Setup
    @MainActor
    func setModelContext(_ context: ModelContext) {
        self.modelContext = context
        self.connectivity = ConnectivityManager()
        self.syncEngine = SyncEngine(modelContext: context, connectivity: connectivity)

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

        self.imageSyncManager = ImageSyncManager(
            modelContext: modelContext,
            connectivityMonitor: connectivity
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

### DataActor (Background SwiftData Writes)

**File:** `OPS/Utilities/DataActor.swift` (~2400 lines)
**Status:** Phase 1 complete 2026-04-19; flag-defaulted-on. Phase 2 (DataController CRUD migration) and Phase 3 (PhotoActor split) planned post-bake.
**References:** `docs/superpowers/specs/2026-04-18-model-actor-refactor-design.md` (design), `docs/superpowers/plans/2026-04-18-model-actor-phase1-sync-foundation.md` (Phase 1 plan), `docs/superpowers/verification/2026-04-19-phase1-verification.md` (device verification log).

**Why it exists.** The main-queue `ModelContext` (from `sharedModelContainer.mainContext`) is the binding point for SwiftUI `@Query` and `@Bindable`. Writing to it from any executor other than main corrupts SwiftData's internal state (malloc double-free crashes). Before Phase 1, sync / cleanup / background writes all happened `@MainActor` — safe, but blocks the main thread during full sync (2–5 seconds for mid-size contractor datasets). DataActor moves those writes onto a separate background `ModelContext` owned by an `@ModelActor` singleton, eliminating both the crash class and the main-thread pin.

**Architecture (C-pragmatic per Apple WWDC24 Sessions 10137/10138).**

- **Main context + `@MainActor`** — SwiftUI view-driven edits via `@Bindable`/`@Query`. Autosave on. This is SwiftData's sweet spot; untouched by the refactor.
- **DataActor (`@ModelActor`) + background context** — all bulk/sync/cleanup/background writes. Autosave off; mutations wrapped in `modelContext.transaction { }` for atomicity. Singleton, created once in `DataController.setModelContext` (synchronously, to avoid races with auth-path and network-reconnect sync triggers that run before async Tasks complete).

**Cross-actor contract.**

- Pass `PersistentIdentifier` (Sendable) across the actor boundary. Re-fetch via `modelContext.model(for: id)` on the receiving side. Registry lookup, not a predicate fetch.
- Actors never accept `@Model` instances as parameters. Actors never touch `mainContext`. Main-actor code never touches the actor's context.

**Refresh bridge.** iOS 18.2 has a known bug (FB14750050) where `@Query`-observing views don't auto-refresh when a background actor context inserts rows. `MainContextRefreshBridge` closes it: actor posts a Sendable notification on save with `[PersistentIdentifier]` payload, bridge force-registers inserted IDs in mainContext via `model(for:)`, bumps a `@Published` refresh counter. iOS 26 verification showed Apple appears to have fixed the underlying bug; bridge retained as insurance.

**SyncEngine wiring.** `SyncEngine.configure` accepts `dataActor: DataActor?`. When `FeatureFlags.useDataActor` is on AND actor is non-nil, `fullSync/pullDelta/pushPending/syncCompanyNow/deltaSyncSince` dispatch to actor methods; otherwise legacy `@MainActor InboundProcessor/OutboundProcessor` paths run unchanged. `SyncEngine.setDataActor(_:)` is a late-bind setter used by `DataController.setModelContext` to cover auth-path initialization ordering.

**Rollback.** `UserDefaults.standard.set(false, forKey: "feature.useDataActor")` + relaunch. Legacy paths take over; no data migration required (actor uses the same store file as the main context).

**Phase 1 scope (complete).** InboundProcessor full port (syncCompany, syncUsers, syncClients, syncTaskTypes, syncProjects, syncTasks, syncSubClients, syncProjectNotes, syncPhotoAnnotations, syncDeckDesigns, syncEstimates with deleted-IDs, syncInvoices with line-items + payments + deleted-IDs, linkAllRelationships, field-level `acceptableFields` merge helper); OutboundProcessor full port (processPendingOperations, executeOperation, routeToRepository, entity handlers, coalesceOperations, per-state transactions for backoff correctness); RealtimeProcessor dispatch via `RealtimeUpdate` enum + `handleRealtimeUpdate(_:)` entry point (Supabase channel subscription stays on main per SDK requirement); all five `cleanupDuplicate*` methods; SyncEngine routing + connectivity guard on main + Spotlight snapshot replay.

**Read-path use (2026-08-18).** Home's billable-this-week rollup + needs-tasks count compute on the actor (`OPS/Utilities/DataActor+HomeRollup.swift`): HomeView passes the ids of the exact project list it feeds the map, and the actor fetches those rows in its own context so `project.tasks` faulting leaves the main thread (bug 3d9ead2f follow-up). The actor never re-derives visibility — scoping stays with the caller. Parity with the retired main-thread compute is locked by `OPSTests/HomeRollupDataActorTests.swift`; legacy compute remains in HomeView behind the `useDataActor` flag.

**Phase 2 scope (pending post-bake).** DataController CRUD write methods (`deleteProject/deleteTask/deleteClient/deleteUserAccount/updateUserProfile/updateTaskStatus/updateProjectStatus/saveClient/createProject/createTask/createClient/createTaskType/markForSyncAndAttemptImmediate/performSyncedOperation`) + sync helpers (`syncProjectTeamMembers/syncTaskStatusOptions/backfillOnboardingCompleted/forceRefreshCompany/removeSampleProjects/fetchOpsContacts`). View-driven `@Bindable` edits stay on main. Flag: `useActorForDataControllerWrites`.

**Phase 3 scope (pending).** Extract dedicated `PhotoActor` for `LocalPhoto` writes + photo upload pipeline. Parallel write lane with DataActor. Flag: `usePhotoActor`.

**Known followup.** At dev-account scale, `MainContextRefreshBridge.model(for:)` force-registration adds small per-row overhead with no amortizing benefit (no main-thread pin to relieve at <50 rows). Tracked as Supabase `bug_reports` `914b3945-27f5-4823-9e4b-d42f0407fcc2`; resolved at mid-size scale.

### Task Schedule Write Integrity (2026-06-08)

All-day task schedule dates (`project_tasks.start_date` / `end_date`) are `timestamptz` stored at **local midnight** (→ `07:00Z` PDT / `08:00Z` PST). A midnight-UTC (`00:00Z`) value renders the task one calendar day early on web. Two invariants keep writes correct, each enforced at a choke point so no caller can violate them:

- **Date convention.** Both outbound paths — `DataActor.handleProjectTask` (active; `FeatureFlags.useDataActor` default true) and the legacy `OutboundProcessor.handleProjectTask` — route the task payload through the shared `SupabaseDate.anchoringScheduleDates(_:)`, which re-anchors `start_date`/`end_date` to local midnight (idempotent). Fixing only one path would be dormant in production. `all_day` is always true today and is not in the synced column set; gate the anchor on `all_day` when timed tasks ship.
- **Persistence.** Task sync is driven only by the `recordOperation` queue; `needsSync` is a conflict-resolution flag with **no** outbound sweep for tasks (only photos have one). Schedule writes must go through `DataController.updateTaskSchedule` (records an op). Safety net: `SyncEngine.enqueueOrphanedTaskWrites()` (run at the top of `pushPending`) re-enqueues + logs any task that is `needsSync` with no pending op, so a future bypass self-heals and surfaces instead of silently dropping the write. (iOS commit `281f99ff`.)

**Web read / pagination.** The web calendar grid and unscheduled tray paged tasks by a non-unique `ORDER BY` (`display_order` / `start_date`) with `.range()`; tied rows reshuffled across 100-row page boundaries, so tasks intermittently vanished from the tray/grid (looked like data loss; was a read bug). Fixed with a primary-key tiebreaker `.order("id")` in `TaskService.fetchTasks` (web commit `6321f6da`).

### Project Team Membership Derivation (2026-06-09)

**Invariant: a project's team is the derived union of its non-deleted tasks' crews — never a separately-maintained list.** `projects.team_member_ids` (`text[]`) is a denormalized **cache**, not a source of truth: trigger `project_tasks_sync_project_team_member_ids` (AFTER INSERT/DELETE/UPDATE OF `team_member_ids, deleted_at, project_id` on `project_tasks`) calls `private.recompute_project_team_member_ids(project_id)`, which **full-recomputes** the column as `array_agg(distinct member_id)` over that project's non-deleted tasks (idempotent; writes only on change; recomputes both old & new project on a task move). A table trigger cannot be bypassed by any DML source, so the cache cannot drift. (DB origin: migration `20260512234121_projects_table_v2_phase1_foundation`.)

- **Authorization derives only from the live task union.** `private.current_user_in_project(project_id)` = `EXISTS(non-deleted task WHERE current_user = ANY(team_member_ids))` — the `projects.team_member_ids` cache is **not** consulted for access (migration `20260609180659_derive_project_membership_from_task_union`). Fail-safe: a hypothetically stale cache can never *grant* access. It gates project view/edit (`current_user_can_view_project` / `current_user_can_edit_project`), task read/update (`project_tasks` policies), team assignment (`current_user_can_assign_team_on_project`), and `estimates` / `invoices` / `clients` "assigned"-scope reads. Removing a user from their last task → trigger recomputes → cache and union both exclude them → access revoked.
- **Mention-based view is a separate branch, untouched.** `current_user_can_view_project` = `current_user_in_project(id) OR EXISTS(project_notes mention)`. A user named in a non-deleted comment (`project_notes.mentioned_user_ids`) can view that project (and its tasks, via the task SELECT policy's `OR current_user_can_view_project`) even with no task assignment. Mentions grant **view only**, never edit. This is deliberate: an "assigned"-scope crew member (113 of 171 role-holders) is otherwise hard-blocked from projects they aren't on — a mention is the one exception, not a navigational nicety.
- **The cache is for LIST filters only.** "My projects" reads still use `projects.team_member_ids` for speed (iOS `DataController.getProjects`; web `ProjectService.fetchUserProjects` `.contains("team_member_ids", [userId])`). These run on RLS-filtered data, so the cache is a non-authoritative convenience; correctness comes from the trigger keeping it == the union.
- **Both clients are fenced from writing the cache.** Crew changes flow through the `assign_project_team_member` / `remove_project_team_member` RPCs (which mutate `project_tasks`; the trigger then recomputes). iOS: `ProjectRepository.updateTeamMembers` is `@available(*, unavailable)`, and `team_member_ids` is excluded from `validProjectColumns` on both sync paths (it is in `validProjectTaskColumns`). Web: `ProjectService.mapToDb` no longer maps `data.teamMemberIds` onto the projects row (web commit `3fc096a7`).

**Production state (2026-06-09): 0 drift across 294 live projects; 0 access change from the RLS migration (proven over 330 grants); all 12 mention-only view grants preserved.** Reusable drift-regression check (must return 0):

```sql
with task_union as (
  select pt.project_id pid, array_agg(distinct m) tm
  from project_tasks pt cross join lateral unnest(coalesce(pt.team_member_ids,'{}'::text[])) m
  where pt.deleted_at is null group by pt.project_id
), proj as (select id pid, coalesce(team_member_ids,'{}'::text[]) pm from projects where deleted_at is null)
select count(*) filter (where not (pm <@ coalesce(tm,'{}') and pm @> coalesce(tm,'{}'))) as drifting
from proj left join task_union on task_union.pid = proj.pid;
```

Legacy `project_team_members` / `task_team_members` join tables are empty + unused (no triggers, no client refs); their `sync_*` functions are orphaned Bubble-era scaffolding.

### Per-Screen ViewModels

**Pattern**: ViewModels handle screen-specific state and business logic.

**Example: CalendarViewModel** (updated 2026-03-02)

```swift
class CalendarViewModel: ObservableObject {
    // MARK: - Published Properties
    @Published var selectedDate: Date = Date()
    @Published var isMonthExpanded: Bool = false          // Added: week strip ↔ month grid toggle
    @Published var projectIdsForSelectedDate: [String] = []
    @Published var selectedTeamMemberIds: Set<String> = []
    @Published var selectedTaskTypeIds: Set<String> = []

    // MARK: - Dependencies
    var dataController: DataController?

    // MARK: - Actions
    func selectDate(_ date: Date, userInitiated: Bool = false) {
        selectedDate = date
        loadProjectsForDate(date)
    }

    func toggleMonthExpanded() {                          // Added: called by AppHeader month icon tap
        withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
            isMonthExpanded.toggle()
        }
    }

    func userEvents(for date: Date) -> [CalendarUserEvent] { ... }  // Added: query CalendarUserEvents
    func loadUserEvents() async { ... }                             // Added: fetch from Supabase

    func applyFilters(teamMemberIds: Set<String>, taskTypeIds: Set<String>) { ... }
}
```

**Removed from CalendarViewModel (2026-03-02)**:
- `shouldShowDaySheet: Bool` — no longer needed (DayCanvasView replaced DayEventsSheet pattern)
- `resetDaySheetState()` — removed with above

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
// MainTabView.swift — index-keyed tab roots, every visited one mounted at once
struct MainTabView: View {
    @State private var selectedTab = 0
    @State private var previousTab = 0
    /// Tabs the operator has visited. Mounted on first visit, never unmounted.
    @State private var mountedTabs: Set<Int> = [0]

    // The tab SET is permission- and flag-gated (LEADS needs `pipeline.view`
    // + the `pipeline` feature flag; CATALOG needs `catalog.view` = all), so
    // the index→tab mapping is computed, not fixed: `leadsTabIndex`,
    // `booksTabIndex`, `jobBoardTabIndex`, `catalogTabIndex`,
    // `scheduleTabIndex`, `settingsTabIndex`. Index 0 is always Home.

    var body: some View {
        ZStack {
            // Keep-alive container: renders every mounted tab and slides
            // between them. See "Keep-Alive Tab Container" below.
            KeepAliveTabContainer(
                selected: selectedTab,
                previous: previousTab,
                mounted: mountedTabIndices
            ) { index in
                tabRoot(for: index)   // Home / Leads / Books / JobBoard /
            }                         // Catalog / Schedule / Settings

            // Custom tab bar overlay — writes through `tabSelection`, never
            // `$selectedTab` (see the same-transaction contract below)
            VStack {
                Spacer()
                CustomTabBar(selectedTab: tabSelection, tabs: tabs)
            }

            // Floating action menu (context-aware)
            FloatingActionMenu()
                .opacity(!isSettingsTab ? 1 : 0)
        }
    }
}
```

### Keep-Alive Tab Container (2026-08-10)

**Problem it solves.** The router this replaced wrapped the tab content in
`Group { tabContent }.id(selectedTab)` — the `.id()` was what made the slide
transition fire at all, and it also forced SwiftUI to destroy and cold-rebuild
the whole tab on every switch. Home reconstructed its entire Mapbox stack, Leads
and Books threw away their view models and refetched behind a spinner, scroll
positions died. Tab switching is the app's primary navigation, so that teardown
was the single largest source of navigation lag.

**Slot architecture.** `OPS/Views/Components/Common/KeepAliveTabContainer.swift`
renders every mounted tab at once inside a `ZStack` and moves them with
`offset`: the selected tab sits at `0`, every other mounted tab parks exactly
one measured container width to the side its index lives on
(`TabContainerWidthKey`, a `max`-reducing preference). Direction of travel is a
straight index comparison. Only the arriving and departing slots animate — every
other mounted slot merely flips which side it is parked on, and animating that
would drag whole screens across the display on a non-adjacent jump. First visit
to a tab has no offset to animate from, so an asymmetric insertion transition
supplies the identical slide (removal is `.identity`; slots are never removed).
Reduce Motion pins every offset to `0` and carries the switch on opacity alone.

The container owns **geometry only**. Selection policy — what the indices mean,
how a tab is chosen, when the mounted set is rebuilt — stays in `MainTabView`.

**Same-transaction contract.** `selectedTab` is never assigned directly.
Every selection routes through `MainTabView.selectTab(_:with:)` (or the
`tabSelection` binding that wraps it), which sets `previousTab`, inserts the
arriving index into `mountedTabs`, and sets `selectedTab` in the SAME
transaction. `previous` is load-bearing, not bookkeeping: it is the only way to
know which slot is leaving, and a stale value teleports the outgoing tab
off-screen instead of sliding it. Updating it in a later `onChange` pass also
mounts an arriving tab a frame too late to animate in.

**Never-evict RAM trade.** A tab mounts on first visit and is never unmounted;
there is no eviction policy. This is a deliberate memory-for-responsiveness
trade — the whole point is that returning to a tab costs nothing. The mounted
set is reset only by `remapMountedTabs()`, on a role or permission change,
because those rewrite which tab each index maps to and a slot mounted under the
old map would render the wrong root.

**Activation protocol.** `OPS/Views/Components/Common/TabActivationKey.swift`
defines `\.isActiveTab`, injected per slot by the container and defaulting to
`true` so sheets, pushed screens, previews, and tests behave exactly as before.
The keep-alive trade only holds if hidden tabs stay quiet, so work that used to
ride `onAppear` is reclassified:

| Class | Where it runs | Examples |
|---|---|---|
| Mount-once | `onAppear` only | one-time wiring; first-visit loads |
| Per-visit | `onAppear` (first visit) + `onChange(of: isActiveTab)` | `HomeView.beginVisit()` / `loadTodaysProjects(silent:)`, `ScheduleView`, `LeadsTabView`, `BooksTabView`, `JobBoardView`, `ExpensesListView`, `MyExpensesView`, `SettingsView`, `MonthGridView` |
| Defer-while-hidden | guarded by `isActiveTab`, recomputed on activation | signal-driven refetches; a hidden tab sets a pending flag and consumes it when it comes back |

Mount and activation coincide on a first visit, so the `onAppear` +
`onChange(of: isActiveTab)` pair does not double-fire. Return-visit refreshes are
silent (`loadTodaysProjects(silent: true)`) — the data is already on screen, and
re-showing the loading state would flash the carousel and, through
`appState.isLoadingProjects`, blink the tab bar and FAB out on every visit.

**Cross-tab broadcasts.** `onReceiveWhileActive(_:perform:)` is `onReceive`
gated on `isActiveTab`. Some notifications are answered by more than one tab —
`ShowCalendarTaskDetails` is posted by Home's event carousel and by the calendar
grids, and answered by both Home and Schedule. That was safe when exactly one tab
existed; with every visited tab mounted an ungated handler runs twice and
presents the same sheet twice. Two classes of listener were audited and
deliberately left ungated, documented at their sites: `AppHeader`'s unread-count
refresh (idempotent recount onto shared `AppState`; gating it risks a stale
badge) and wizard listeners on PUSHED screens (wizards drive the tab themselves).
The two wizard listeners that sit in tab BODIES and genuinely collide
(`JobBoardProjectListView` and `ScheduleView`, both answering
`WizardEvaluatePrerequisites` with different count sets) ARE gated.

**Header height.** Every mounted tab's `AppHeader` is alive at once and
`AppHeaderHeightKey` reduces with `max`, so inactive headers report the default
floor (`AppHeader` gates its own contribution on `isActiveTab`). Without that,
the tallest header ever mounted would pin the status band for the rest of the
session.

**Screen breadcrumbs.** `ScreenTrackingModifier`
(`OPS/Services/BugReport/BugReportCaptureService.swift`) claims the bug-report
breadcrumb on `isActiveTab` rather than on `onAppear`: with several tab roots
mounted, the last writer would otherwise win nondeterministically — quite
possibly a parked tab. Known residual: a pushed screen and its tab root both
track, and on re-activation both fire with no ordering contract, so the deeper
screen is not guaranteed to win. Inherent to a per-view breadcrumb, and strictly
better than the wrong tab winning.

**Tests:** `OPSTests/Views/KeepAliveTabContainerTests.swift` hosts the real
wiring (offsets, per-slot animation eligibility, insertion direction, Reduce
Motion, mount-set growth).

### Tab Bar Touch Targets (2026-08-11)

Source: `OPS/Views/Components/Common/CustomTabBar.swift`. The tab bar is a
manual overlay, not a `TabView` bar, so it owns its own hit geometry and its own
touch-down timing. Both were wrong, and both read to the operator as lag rather
than as a miss.

**Rule: a SwiftUI `Button` is tappable across its LABEL's bounds only.**
`.frame(...)` and `.contentShape(...)` applied to the `Button` itself position
the same small label inside a bigger box — they do not grow the responsive area.
The tab bar had exactly that shape: each tab published a 28×50 interactive region
(the glyph) inside a 60pt cell, with a 32pt dead gap between neighbours, under
the 44pt field minimum from `MOBILE.md`. The fix moves the frame and the content
shape INSIDE the `Button` label, sized to the cell width the lane already
computes and passes down (`TabBarItem.cellWidth`), with the cell height tokenized
as `OPSStyle.Layout.tabBarItemHeight` (50pt — the same value the lane's divider
matches). Lane geometry, `PeekSnapBehavior` math, and VoiceOver traits are
unchanged; only the responsive area grows. Tests measure the published
accessibility frames rather than the layout intent:
`OPSTests/Views/TabBarHitTargetTests.swift`.

**Rule: a control hosted in a `UIScrollView` must release
`delaysContentTouches` or its press state arrives ~150 ms late.** The tab lane is
a horizontal `ScrollView` (it scrolls to reveal the Settings peek). A scroll view
withholds touches from its content while it decides whether the gesture is a
scroll, so every quick tap spent that window with nothing on screen changing —
the action always fired on lift, but the acknowledgment did not. `ImmediateTouchDown`
(a private `UIViewRepresentable` in the same file) walks up from its own
superview to the enclosing `UIScrollView` and clears the flag, on both
`didMoveToSuperview` and `didMoveToWindow` because SwiftUI can attach the
representable before the scroll view is an ancestor.

`canCancelContentTouches` is deliberately left ON: a touch that becomes a drag
must still cancel the press so swipe-to-reveal and the peek snap behave exactly
as before. Only the moment of acknowledgment moves earlier. The introspector is
non-interactive at both layers (`isUserInteractionEnabled = false` plus
`.allowsHitTesting(false)`), idempotent, and harmless when the lane is hosted
without an enclosing scroll view (previews, tests).

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
  │     ├── ConnectivityManager (created eagerly in setModelContext)
  │     ├── SyncEngine (created eagerly in setModelContext)
  │     │     ├── OutboundProcessor (push with coalescing + backoff)
  │     │     ├── InboundProcessor (pull with field-level merge)
  │     │     ├── RealtimeProcessor (WebSocket subscriptions)
  │     │     ├── PhotoProcessor (adaptive photo uploads)
  │     │     └── BackgroundSyncScheduler (BGTask scheduling)
  │     ├── SupabaseSyncManager (legacy adapter — retained for entity fetches)
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
// SupabaseService.swift - Supabase client handles network errors
// Repository pattern wraps Supabase calls with error handling

// Example: ProjectRepository.swift
func fetchProjects(companyId: String) async throws -> [SupabaseProjectDTO] {
    do {
        let response: [SupabaseProjectDTO] = try await supabase
            .from("projects")
            .select()
            .eq("company_id", value: companyId)
            .is("deleted_at", value: nil)
            .execute()
            .value
        return response
    } catch {
        print("[API_ERROR] Failed to fetch projects: \(error)")
        throw error
    }
}
```

### Error Handling in Sync Engine (Updated 2026-07-22 — SYNC RECOVERY)

Every failed outbound push is classified by `SyncErrorClassifier.disposition(for:)`
(`OPS/Network/Sync/SyncErrorClassifier.swift`) into one of three dispositions, and
`SyncOperationFailurePolicy.apply` — the ONE shared post-catch state transition — is
called identically by both outbound paths (`DataActor.executeOperation`,
`OutboundProcessor.executeOperation`) so they cannot drift:

| Disposition | Trigger | SyncOperation transition |
|---|---|---|
| `transient` | URLError offline/timeout; HTTP 5xx/429/408; SQLSTATE 40001/40P01/55P03/57014; anything unknown | `retryCount += 1`; backoff `min(2^retryCount, 60)`s; at 20 → `status="failed"` (recoverable) |
| `permanent` | other HTTP 4xx; SQLSTATE classes 22/23/42; P0001/P0002; `SiteVisitPayloadError` (payload never reached the server) | `status="parked"` immediately, no retry consumed, `sync_parked` analytics. Only an explicit user recovery action moves it; Discard is exposed only when that work unit's policy can prove it safe |
| `auth` | PGRST3xx / JWT / 401 | `status="failed"` + `.syncAuthExpired` → re-auth (unchanged) |

`status` values: `pending → inProgress → completed / failed / parked`, plus two
terminal states written outside the processor — `quarantined` (identity review,
`SiteVisitOrphanRecovery`) and `declined` (see below). PK-violation
idempotency (23505 `_pkey` on create retry → treat as completed) still runs BEFORE
classification. The 2026-07-22 outage motivated the split: a permanent 400
(auto-lead `source_thread_key` rejection, RC1) previously burned the same 20-retry
budget as a transient 504, then sat invisible.

**Provably obsolete task updates settle locally (2026-08-20, code commit
`b3795976`).** `DeletedProjectTaskOperationSettlement` runs before orphan
recovery and recognizes only a `projectTask` update already `parked` with the
stable `serverRowMissing` marker plus an exact same-company local soft-delete
tombstone. That operation becomes `completed` with `serverConfirmedAt = nil`:
the server has no row and the phone no longer intends one. Every other entity,
operation type, status, error, company, and local-row state remains untouched
for operator review.

**Payload-build failures park (2026-08-13, bug 70db7ed6).** A DTO that cannot be
built from its local row (`SiteVisitPayloadError`) never reached the server, and
rebuilding it from the same row fails identically — so a retry can only burn the
budget, and `reenqueueRecoverableOperations` revives a `failed` op on every launch.
That combination made one authorless site-visit row retry forever. Such failures
now classify `permanent` and park: visible in PENDING WORK, user-retryable, never
automatic. `SiteVisitPayloadError` conforms to `LocalizedError` so the detail
sheet's DETAILS disclosure states plainly what is missing.

**Authorship heal — legacy site-visit rows (2026-08-13, bug 70db7ed6).**
`created_by` arrived with the V19→V20 lightweight migration, which could only
default existing rows to nil — parents included, since the V19 `SiteVisit` carried
no author field either. Those rows can never satisfy the wire contract, so they
threw at payload build before every send, and an unresolved CHILD is a live barrier
in `SiteVisitOutboundSync.isReady`, damming its visit's `siteVisitComplete` (the
operator's completion notes) behind it. `SiteVisitAuthorHeal`
(`OPS/Network/Sync/SiteVisitAuthorHeal.swift`) resolves an author — the row's own
value, else the parent visit's, else the signed-in operator (`currentUserId`) — at
the outbound boundary for visits, artifacts, checklist answers and identity drafts,
and persists it. `SyncEngine.healSiteVisitAuthorshipOnce()` clears the whole backlog
ahead of the drain, gated by UserDefaults `siteVisitAuthorBackfill.v1`; the flag
flips only after a pass that leaves NOTHING unresolved, so a launch that runs before
sign-in completes retries next launch instead of retiring having healed no one. Both
paths write `created_by` ONLY — flipping `needsSync` would enqueue a fresh write for
every legacy row on the device at once. Soft-deleted rows are skipped: they sync as
a delete, which carries no author.

**`declined` — the operator stopped a send (2026-08-13, bug f7431c17).** PENDING
WORK is a sync-recovery surface: its rows are queued SENDS, so DELETE there means
"stop trying to send this", never "delete the record". Declining sets
`status="declined"` and clears `lastError` / `lastAttemptedAt` / `completedAt` on
every operation in the work unit, and touches NO model row — no `deletedAt`, no
status change, no tombstone operation. It is refused outright while any operation
in the unit is `inProgress`.

Before this existed, discarding one stuck child send ran a whole-visit teardown:
it cancelled the parent `SiteVisit`, tombstoned every artifact, checklist answer
and identity draft, and enqueued durable soft-DELETEs for all of them — wiping a
COMPLETED visit's server copy from a sync list. Deleting a visit is now only ever
a decision made on the visit's own surface.

Consumers that must know the status:
- `OutboundProcessor` fetches `status == "pending"` only, so declined work is
  never drained and never counted by `SyncEngine.getPendingOperations()`.
- `SyncEngine.reenqueueRecoverableOperations()` touches only `inProgress`/`failed`,
  and PENDING WORK's RETRY ALL only `failed`/`parked` — neither revives a decline.
- `RecoveryInventory.isConsidered` excludes it, so the row leaves the screen at the
  next rebuild.
- `SiteVisitPersistenceCoordinator.unresolvedStatuses` **includes** it. This is
  load-bearing: `queueDirtyGraphs(onlyOrphans:)` runs before every drain and
  re-derives a send from any still-dirty row — and media sends are re-derived from
  a still-local asset URL regardless of `needsSync`, so no model flag can stop
  them. Counting `declined` as unresolved is what makes the decline stick, and it
  also makes a genuine later edit revive that same operation via `enqueue` instead
  of duplicating it.
- `SiteVisitServerMerge.checklistResolvedStatuses` = `{completed, declined}`.
  Checklist-id canonicalization fails closed on unrecognized lifecycles, so a
  declined operation must read as settled — never migrated, never a collision.

Site-visit failures retain their structured origin through this pipeline.
`SiteVisitRepositoryError.server(code:message:detail:hint:)` preserves the four
PostgREST fields and composes them through `LocalizedError`, so the stored
`SyncOperation.lastError` and Pending Work details show the real rejection. The
classifier reads the same typed error to choose retry disposition; display
fidelity and retry policy are separate responsibilities.

**Recovery sweeps** (`SyncEngine.reenqueueRecoverableOperations()`): at launch
(once, from `configure()`) and on genuine reconnect (`DataController` connectivity
hook) — stale/nil-attempt `inProgress` ops → `pending` (crash recovery); `failed`
ops → `pending` with a fresh retry budget (`retryCount=0`, `lastError` kept);
`parked` ops untouched. Never driven by the 180s retry timer. The lead-autocreate
queue (`ClientLeadAutocreateQueue`) applies the same disposition policy per request:
permanent → `parkedAt` (user-only retry), transient → exponential backoff
`min(60·2^min(attempts,4), 900)`s.

```swift
// InboundProcessor.swift — pull conflict handling (unchanged 2026-03-08)
// Before overwriting any field from server data:
//   - Checks for pending SyncOperations targeting that field
//   - If pending local change exists, server value is skipped (local wins)
//   - If no pending local change, server value is applied

// RealtimeProcessor.swift — WebSocket error handling
// On disconnect: records timestamp, stops subscriptions
// On reconnect: performs catch-up delta sync from disconnect timestamp
// Falls back gracefully to polling if WebSocket unavailable
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
- `[SYNC]` - Sync operations (SyncEngine)
- `[SYNC_PUSH]` - OutboundProcessor push operations
- `[SYNC_PULL]` - InboundProcessor pull operations
- `[SYNC_RT]` - RealtimeProcessor WebSocket events
- `[SYNC_PHOTO]` - PhotoProcessor upload operations
- `[SYNC_BG]` - BackgroundSyncScheduler task events
- `[CONNECTIVITY]` - ConnectivityManager state changes
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
    var scheduledTasks = dataController.getScheduledTasksForCurrentUser(for: date)

    // Cache count for calendar rendering
    projectCountCache[formatDateKey(date)] = scheduledTasks.count
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

### 4. Offline-First Sync Engine (Rebuilt 2026-03-08)

**Problem**: Foreground syncs block UI; offline mutations could be lost.

**Solution**: Operation Log + Replay pattern. Every mutation creates an immutable `SyncOperation` record, applies optimistically to SwiftData, and queues for push.

**Core architecture:**

```swift
// SyncEngine.swift — @MainActor @Observable central orchestrator
// Key methods:
//   triggerSync()      — debounced push+pull cycle
//   fullSync()         — called on app launch via performAppLaunchSync()
//   pushPending()      — delegates to OutboundProcessor
//   pullDelta()        — delegates to InboundProcessor
//   recordOperation()  — creates SyncOperation, called by DataController mutation methods
//   startRealtime()    — starts RealtimeProcessor WebSocket subscriptions
//   stopRealtime()     — stops subscriptions (called on background transition)
//   registerBackgroundTasks() — registers BGTask identifiers
//   scheduleBackgroundSync()  — schedules next background run
```

**Outbound push (OutboundProcessor.swift):**
- Operation coalescing: merges multiple updates to the same entity into one push
- Dependency ordering: creates are pushed before child entities
- Exponential backoff: `min(pow(2, retryCount), 60)` seconds, max 20 retries
- Errors classified as retryable vs. permanent via `SyncTypes.swift` helper

**Inbound pull (InboundProcessor.swift):**
- Field-level merge: before overwriting any field, checks for pending `SyncOperation` records on that field
- Fields with pending local changes are preserved (local wins for pending ops)

**Realtime (RealtimeProcessor.swift):**
- Supabase Realtime WebSocket subscriptions for 9 merged entity types
- Field-level merge protection same as InboundProcessor
- Tracks disconnect/reconnect timestamps for catch-up delta sync on reconnect
- **Notification-only tables (no merge):** `opportunities`, `activities`,
  `follow_ups` (added 2026-07-03, bug 0b7e9b17) post `.opsLeadsDidChange`
  exactly like `expenses`/`expense_batches` — no DTO decode, no actor dispatch,
  no SwiftData write. LEADS is outside the sync engine (direct-fetch); the event
  triggers a debounced REST re-fetch in `PipelineViewModel.scheduleRefresh`.
  All three are in the `supabase_realtime` publication with REPLICA IDENTITY
  FULL + `company_id` (verified 2026-07-03).
- `calendar_user_events` events are merged live on the actor path (own-user rows
  only, matching `fetchForUser` visibility) via `RealtimeUpdate.calendarUserEvent`
  with a Supabase-tolerant date decoder (`SupabaseDate.makeISODecoder()`), and
  iPhone-Calendar mirror parity (mirrorEvent / unmirrorEvent / reconcileAll)
  matches the legacy path on task and user-event upserts/deletes

**Inbound change signal (InboundChangeSignal.swift, 2026-06-09):**
- Problem it solves: SwiftUI `@Query` screens pick up in-place updates from
  background saves natively, but snapshot caches do not.
  `CalendarViewModel.dayTaskCache` buckets tasks per day once and only rebuilt
  on LOCAL edit signals — a teammate's reschedule landed in SwiftData but never
  repainted the schedule until week-change / pull-to-refresh / relaunch.
- Contract: every inbound merge path (Realtime, delta, full sync — DataActor
  AND legacy InboundProcessor/RealtimeProcessor) posts `.inboundDataMerged`
  with the merged SwiftData model class names after a successful save.
  Realtime merges post per-event; batch syncs accumulate per entity type and
  post ONCE after `linkAllRelationships()` so a repaint can never observe
  unlinked relationships.
- `InboundChangeRouter` (owned by DataController, main-confined) coalesces
  bursts — trailing 250 ms debounce with a 1 s max-latency starvation guard —
  and fans out to the EXISTING refresh chains only:
  - `ProjectTask` / `Project` / `TaskType` → `DataController.scheduledTasksDidChange`
    (ScheduleView → `reloadCalendarData()`, MonthGridView, CalendarDaySelector
    already observe it)
  - `CalendarUserEvent` → `"CalendarUserEventsDidChange"` notification
    (ScheduleView `loadUserEvents()`, MonthGridView, CalendarDaySelector)
- `.calendarUserEvent` was also restored to DataActor's `syncOrder` (it existed
  only in legacy InboundProcessor's order, so user events never synced inbound
  while `FeatureFlags.useDataActor` — default true — was on).
- Tests: `OPSTests/Network/InboundChangeRouterTests.swift` (coalescing, routing,
  starvation guard) and `InboundChangeSignalDataActorTests.swift` (merge → signal
  integration, user-event merge semantics).

**Photo uploads (PhotoProcessor.swift):**
- Adaptive concurrency: 3 concurrent uploads on WiFi, 1 on cellular
- Local save with thumbnail generation
- Cleanup of synced originals to reclaim storage

**Background scheduling (BackgroundSyncScheduler.swift):**
```swift
// BGTaskScheduler wrapper
// Refresh task: 15-minute interval
// Processing task: 30-minute interval
// Identifiers registered in Info.plist

func scheduleBackgroundSync() {
    let refreshRequest = BGAppRefreshTaskRequest(identifier: "co.opsapp.sync.refresh")
    refreshRequest.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)

    let processingRequest = BGProcessingTaskRequest(identifier: "co.opsapp.sync.processing")
    processingRequest.earliestBeginDate = Date(timeIntervalSinceNow: 30 * 60)
    processingRequest.requiresNetworkConnectivity = true

    try? BGTaskScheduler.shared.submit(refreshRequest)
    try? BGTaskScheduler.shared.submit(processingRequest)
}
```

**Connectivity (ConnectivityManager.swift):**
```swift
// @MainActor ObservableObject
// NWPathMonitor with:
//   - Performance tracking and quality scoring
//   - Lying WiFi detection (connected but no internet)
//   - Publishes ConnectionState enum with quality level
//   - Triggers sync on connectivity restore via NotificationCenter
```

**OPSApp.swift lifecycle integration:**
```swift
// scenePhase handler:
//   .active  → triggerSync() + startRealtime() on return from background
//   .background → scheduleBackgroundSync() + stopRealtime() after 30s delay
// ConnectivityManager notification handler triggers sync on connectivity restore
```

### 5. Mutation Recording (replaces debounced sync triggers)

**Problem**: Rapid changes trigger redundant syncs; offline mutations must survive app termination.

**Solution**: Every mutation creates an immutable `SyncOperation` persisted in SwiftData, then triggers a coalesced push cycle.

```swift
// DataController mutation methods now call:
syncEngine.recordOperation(
    entityType: .project,
    entityId: project.id,
    operationType: .update,
    fields: ["status": "In Progress"]
)
// SyncOperation is persisted immediately in SwiftData
// OutboundProcessor coalesces multiple updates to the same entity before pushing
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

### 7. Fetch Predication on Hot Paths (2026-08-10)

**Rule: an unpredicated `FetchDescriptor` on a hot path is a defect.** "Hot path"
means anything re-run on inbound data change, sync completion, badge refresh, or
render — which covers most main-context reads in this app.

- **`deletedAt == nil` belongs in the `#Predicate`, never in a trailing
  `.filter`.** Same rows out either way; the difference is that the in-memory
  form materializes every tombstoned row on the main thread first.
- **Every gate that CAN ride the predicate must** — dated gates
  (`startDate != nil`), lower bounds (`startDate >= cutoff`), scope columns.
  Each excluded row is also relationship-faulting work not done, because the
  permission filters that follow fault `teamMembers` and `project` per surviving
  row.
- **Relationship-walking filters stay in memory** and must be named as residual
  cost at the call site, not quietly left to look free. Task assignment is a
  comma-joined string (`ProjectTask.teamMemberIdsString`, parsed by
  `getTeamMemberIds()`) OR'd with a to-many traversal; neither is expressible in
  a `#Predicate`. **The CSV column is the schema constraint that blocks the
  unlock** — normalizing assignment into a queryable form is the future schema
  work that would let these filters follow the gates into the predicate.

Predicated in this pass: `DataController.getProjects`, `getAllTasks`,
`getAllScheduledTasks(from:)`, `CalendarViewModel.rebuildWeekCache`, the month
grid. Two behavior corrections rode along, both previously-undocumented bugs:
`getProjects` now excludes tombstones (the completed-work counters gating the
review stacks were counting deleted jobs toward the unlock), and
`getAllScheduledTasks` now gates `deletedAt` (a deleted task kept drawing a
month-grid badge until the next launch — it was the only calendar fetcher that
did not). `CalendarViewModel.rebuildWeekCache` takes **no** date bound on
purpose: its per-day filter admits a task by overlap, tasks carry no maximum
span, and any lower bound on `startDate` would silently drop long-running work
off the canvas.

`DataController.getProjectsForToday` was deleted in the same pass — dead code,
no call sites. Tests: `OPSTests/Sync/CalendarFetchPredicationTests.swift`,
`OPSTests/Sync/TaskReviewQueryParityTests.swift`.

**Related: single-fetch count derivation.** `TaskReviewQuery` and
`ProjectReviewQuery` each expose two shapes per queue — one that fetches the
table, and one that takes an already-fetched array. The fetching shape is a
one-line delegate onto the array shape so scoping cannot diverge between them.
The FAB badge derived five counts from four entry points, each re-fetching the
whole task table on the main thread on every sync completion and every schedule
mutation, from every tab; one fetch now feeds them all.

### 8. Event-Driven Sync Pill (2026-08-10)

**Problem**: The sync pill (`SyncStatusIndicator`) and the PENDING WORK screen
both polled `RecoveryInventory` every 2 seconds in `.common` runloop mode —
forever, whether or not anything had changed and whether or not the pill was on
screen. `.common` mode fires *during scroll tracking*, so a six-fetch
main-context load ran with the operator's finger down.

**Solution**: `OPS/Network/Sync/RecoveryRefreshSignal.swift`. The inventory only
changes when the store changes, so the surfaces listen for that instead:
`.dataActorDidSave` (background saves), `ModelContext.didSave` (main-context
saves), and `.opsLeadsDidChange` (realtime lead rows), merged and debounced
500 ms so a sync pass's save storm costs one load. `ModelContext.didSave` is
subscribed name-wide, so DataActor's own saves arrive twice; the debounce
collapses the overlap. A 60 s fallback timer self-heals inputs that reach no save
notification (notably recovery-vault quarantine entries, which live outside
SwiftData); it is merged *after* the debounce, never through it, so continuous
store activity cannot postpone it indefinitely.

**Rule: debounce UI-adjacent work on `RunLoop.main`, never `DispatchQueue.main`.**
Main-QUEUE blocks drain during scroll tracking too, so a save landing mid-gesture
delivers mid-gesture — the exact hitch being removed. `RunLoop.main` in
`.default` mode defers delivery to gesture end. Nothing is dropped; it arrives
when it can be paid for. Trailing-edge with no max-latency bound is a deliberate
divergence from `InboundChangeSignal`'s router (which forces a flush after 1 s):
starvation is bounded twice over here by the fallback tick and by the fact that a
storm long enough to matter is a sync pass, which the pill is already displaying
as SYNCING off `DataController` state.

**Ownership is load-bearing.** `RecoveryRefreshMonitor` is an `ObservableObject`
held as `@StateObject`, not a chain stored on the view struct. Stored on the
struct, SwiftUI rebuilds the pipeline on every re-evaluation and `.onReceive`
drops the previous subscription — along with any event still inside the 500 ms
window, which is precisely the sync completion the pill needs. The same applies
to the fallback timer: a struct-stored timer restarts its 60 s countdown on every
re-render and never reaches its deadline. The scheduler is injectable
(`publisher(center:scheduler:)`); production always passes `RunLoop.main`, and
tests pass `OPSTests/Sync/VirtualScheduler.swift` because wall-clock debounce
tests were outrun by parallel-build load.

**Empty-guard on the capture scan.** `RecoveryInventory.captureSnapshots` fetches
site-visit artifacts and checklist answers — two whole-live-table scans, because
the visit-id match cannot ride a `#Predicate` (stored casing varies: 
`UUID().uuidString` is uppercase, Postgres `uuid` columns are lowercase). Both
tables grow without bound (server artifacts merge in and are never pruned), so an
empty visit-id set **short-circuits before either fetch runs** rather than
filtering to empty after. The fetches are injected so that skip is directly
assertable. Ids are normalized inside the function, never trusted from the call
site. Tests: `RecoveryRefreshSignalTests`, `ReviewCountRefreshMonitorTests`,
`RecoveryInventoryCaptureScanTests`.

### 9. Batched Operation Recording (2026-08-10)

**Rule: any flow that mutates more than one item records through
`SyncEngine.recordOperations`, never a per-item `recordOperation` loop.** A
per-op loop is N context saves plus N push triggers on the main thread; the
batch is one save and one push cycle. A per-item loop in a multi-item flow is a
defect, not a style preference.

**Invariant**: when the caller lets the batch commit its own model edits, it must
first confirm `syncEngine.sharesModelContext(with: context)` — the single save
inside `recordOperations` only commits pending edits made on the engine's own
context. This mirrors the `===` guard in `stageOperationsForTransaction`.

Converted in this pass: project cascade-delete (project tombstone + every child
task in one batch) and task reorder. Tests:
`OPSTests/Sync/BulkOperationBatchingTests.swift`.

### 10. Diff-Gated Inbound Merges (2026-08-10)

**Rule: every full-fetch inbound sync compares before it assigns.** Thirteen
catalog-family merges run on EVERY delta pass (`pullDelta` seeds epoch cursors
for all entity types, so they never skip). Un-gated they rewrote `lastSyncedAt`
on every local row — and the variant↔option-value junction wiped and reinserted
its whole company scope — which saved the DataActor context and broadcast
`.dataActorDidSave` even when the server returned byte-identical data. Every such
save wakes the main-context merge, `@Query` invalidation, and the sync-pill
inventory refresh. Products were the quiet case: they carry no `lastSyncedAt`, so
their cost was pure same-value reassignment — which SwiftData dirties anyway.

The gate pattern, per entity: a `<entity>Differs(dto:from:accepting:)` predicate
paired with an `apply<Entity>(dto:to:accepting:)` writer, the diff computed from
fetches alone, and **the transaction skipped entirely** when nothing differs —
never opened and left empty. (`test_emptyTransactionDoesNotPostDidSave` pins
which of those two SwiftData actually requires, so a behavior change surfaces
there first.)

**Drift guards are part of the pattern.** A differ that stops listing a field the
applier writes silently reintroduces the bug — the merge would skip a real
change. The suite therefore walks the production field lists and asserts
flip-and-converge for each: mutate one field, prove the merge writes, prove a
second identical pass writes nothing. Keyed diffs cover junction rows whose only
identity is the pair itself. Reference implementation and required shape:
`OPSTests/Sync/CatalogMergeDiffGateTests.swift` — new full-fetch merges are
expected to bring their own equivalent.

### 11. Local-First Screen Opens (2026-08-11)

**Rule: navigation NEVER triggers a whole-app sync.** Opening a screen is a
read of data already on the device. A screen that needs one row current fetches
that one row; it does not start a push+pull pass over every entity type because
one of them happens to contain what it wants.

**The canonical failure.** `DataController.refreshSingleClient(clientId:)` —
called on EVERY open of a project's details — was literally
`await syncEngine.triggerSync()`: push plus pull across all 40
`SyncEntityType`s, main-actor orphan sweeps, and a photo-prefetch kickoff, to
refresh one `clients` row. The method name said "single client"; the body said
"sync the app." A rename is not the lesson — the lesson is that the targeted
entry point did not exist, so the nearest available hammer was used.

**The targeted-fetch pattern.** `SyncEngine.syncClientNow(clientId:)` is the
shape every future one-entity refresh should copy:

- Fetches ONE row by id and merges it through the SAME merge path the pull and
  realtime paths use — `DataActor.syncClientOnly` when `FeatureFlags.useDataActor`
  is on, `InboundProcessor.syncClient` otherwise — so conflict handling and the
  `InboundChangeSignal` post are not re-implemented per call site.
- Gated on `connectivity?.shouldAttemptSync`, matching the offline behavior of
  the full pass it replaces: an airplane-mode open fails fast instead of riding a
  URLSession timeout, and the screen renders from local data.
- Does **not** acquire the `syncInProgress` lock and never writes `statusText` /
  `isSyncing`. A single-row read is not a sync pass and must not present itself
  to the operator as one — the pill stays quiet.

Scope honestly, or leave it whole and say why: `triggerProjectTasksSync` is
still a full pass, documented at its site as such, because no scoped
project-task inbound entry point exists (the task repository fetches by company
+ cursor, not by project) and its only caller is the debug-only `TaskTestView`.
A half-scoped fetch that silently drops rows is worse than an honest full one.

**Local-first paint.** A screen whose data is already on disk paints from disk
first, synchronously, then repaints when the network merge lands.
`ProjectNotesViewModel.loadNotes` calls `loadNotesFromLocal()` before it touches
the network; the activity feed's spinner condition
(`isLoading && notes.isEmpty && annotations.isEmpty`) then yields on its own, so
no UI change was needed to suppress the spinner. The read half of the repository
is injectable (`ProjectNoteFetching`) precisely so the paint ORDER is assertable
against a fetch that deliberately has not resolved yet — ordering that only holds
by luck of timing is not a guarantee.

**Image work belongs off the main actor.** Annotation compositing and photo
download moved their decode / JPEG encode / disk writes off the main actor.
Compositing runs on `PhotoCompositeRenderer`, a serial `actor`
(`OPS/Network/PhotoAnnotationSyncManager.swift`), which preserves the durable-write
serialization that main-actor isolation used to provide for free.

**Per-key generation guard (the race the move widened).** A render suspended on
a base-image or overlay download can resume AFTER a later render — started
because the annotation changed — has already persisted its result, overwriting
the fresh composite with pre-edit pixels. The stale write also refreshes the
file's mtime, so it then passes the freshness check and the operator keeps seeing
pre-edit markup until the next edit. The race predates the off-main move; the
move only widened the window.

`beginRender(for:)` hands out a per-key token and the renderer drops any write
whose token is no longer the newest claim on that key. The check and the write
stay one synchronous stretch on the actor, so no render can interleave between
them. A superseded render also returns `nil`, so its stale pixels never reach the
display cache. A failed disk write is distinguished from supersession and still
publishes, as before. **Any actor-serialized cache that can be re-entered for the
same key needs this guard; serialization alone does not order the results.**

Tests: `OPSTests/Sync/ProjectDetailsLocalFirstTests.swift` (targeted fetch vs.
full sync, offline gating, local-first paint order, renderer supersession). It
seeds the inert warm-up `SyncOperation` row described in § Defensive Programming
→ "The `SyncOperation` `#Predicate` Warm-Up Trap", so no test reaching the merge's
conflict guards is green by luck of ordering.

### 12. List Row Rendering (2026-08-11)

Scroll-heavy lists are the app's most expensive surface: everything a row does is
paid per row, per render pass, and again on every scroll recycle.

**Rule: a card reads its RELATIONSHIPS, never the whole table.** The job board's
task card re-fetched the whole project table twice and the whole task-type table
three times just to name its own title, subtitle, stripe, and metadata — eight
visible cards meant roughly 16 project fetches and 16 task-type fetches per render
pass. `ProjectTask` already owns `project` and `taskType` SwiftData relationships,
wired from the same id columns those fetches were matching on
(`InboundProcessor.linkAllRelationships`), so the lookups are gone entirely.

The replaced fetch was `deletedAt`-predicated, so the relationship read must
reproduce that: `JobBoardCardText.liveProject(of:)` returns `nil` for a tombstoned
parent, preserving the same "No project" fallback and the same suppressed address
cell. **When replacing a fetch with a relationship, port the fetch's predicate
into the accessor** — otherwise deleted rows quietly reappear on screen.

**Rule: derive sections ONCE per body, then bind.** The task list ran its full
filter+sort pipeline about six times per render (once per partition, once per
`isEmpty` check); the project list read its three partitions seven times, each
read re-running a comparator that touches four or five `Date` properties per
side. Both compute once at the top of `body` and bind. The same applies inside a
row: the progress bars and the UNSCHEDULED rule were three and four separate
walks of `project.tasks`, now one pass each, and the assignee CSV is split once
and serves both the badge and the crew count. The derivations live in
`OPS/Views/JobBoard/JobBoardCardModels.swift` as plain values with no SwiftUI in
them, which is what makes them testable on their own.

**Rule: row identity is the entity id — never a mutable field of it.** Both job
board lists folded the crew CSV into row identity, so any crew change destroyed
and rebuilt the row with fresh `@State`. Identity is the project id; the card
observes the `@Model`, so a crew edit still redraws it. (Fixed on the active list
and on the `ProjectListSheet` CLOSED/ARCHIVED rows.)

**Rule: presentation modifiers do not belong per row.** Ten stacked presentations
per card (eight sheets, a dialog, a delete confirmation), installed on every
visible row, collapse to one `.sheet(item:)` driven by a route enum plus one
dialog and one confirmation shared by all three card kinds. In the same pass, the
wizard's scroll-tracking `GeometryReader` — which re-measured on every scroll
frame, forever, to serve a one-shot wizard step — now mounts only while a wizard
is running and the notification is still owed, and the duplicate-task dedup log
(fired per duplicate inside a main-thread list build) is DEBUG-only.

`JobBoardView`'s `.id(selectedSection)` is deliberately kept: the section slide
needs it, and the rebuild it triggers is now cheap.

**Rule: live materials belong on overlays and sheets, not on rows.** Every job
board row painted `.ultraThinMaterial`, and so did each of its badges — eight
rows meant 16 to 40 live blur layers recomposited every scroll frame, over a
pure-black canvas with nothing behind them worth blurring. The design system now
carries an opaque L1 variant for exactly this case: `.glassSurface(.listRow)`,
with `listRowBadgeFill` as the badge counterpart. Same hairline, same radius,
same top-edge gradient, `surfaceRaised` instead of the material. Founder-approved
and applied at the job-board card call sites only — every full-screen surface,
sheet, overlay, and detail panel keeps true glass. Full token detail:
`05_DESIGN_SYSTEM.md` § 20.1.

Tests: `OPSTests/JobBoard/JobBoardCardModelTests.swift` and
`OPSTests/JobBoard/JobBoardSectionBindingParityTests.swift` pin the new
derivations against oracles that run the ORIGINAL code verbatim over the same
store — including a tombstoned parent project, a task with no resolvable type, a
task reachable through two projects, and every filter and sort shape the list can
be in. A parity test whose fixture cannot produce the anomaly it guards is
vacuous; seed the anomaly.

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

### 6. Logout Data Wipe Contract

`DataController.performCompleteDataWipe()` owns logout cleanup through an explicit per-model deletion list, followed by authentication/default-state cleanup. It does not derive its list from `OPSSchemaV16.models`. Every new registered model therefore requires a matching audit of this method; do not infer completeness from an older example or model count. Source: `OPS/Utilities/DataController.swift`; data-layer contract: `03_DATA_ARCHITECTURE.md § Logout Data Wipe Contract`.

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

`Project`, `Client`, and `ProjectTask` tombstones are recoverable through
Settings → Trash. Restore is ledger-first recovery, not a local flag flip:
`DataController.restoreTrash` clears the ordered entity tombstones and
`SyncEngine.stageOperationsForTransaction` stages the matching parent-first
`update` operations with exact `{ "deleted_at": null }` payloads inside the same
`ModelContext` transaction. The transaction verifies count, unique fresh
operation ids, entity/order/routing, pending state, changed fields, and null
payload before commit. Zero/partial/malformed staging, encoding/context failure,
or a later entity failure rolls back both the model mutations and all inserted
outbox rows. Sync notification, toast, and push may occur only after that shared
transaction commits. Sources: `ops-ios/OPS/Utilities/DataController.swift` and
`ops-ios/OPS/Network/Sync/SyncEngine.swift` (code commit `39afa7c4`).

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

### 9. The `SyncOperation` `#Predicate` Warm-Up Trap (2026-08-10)

A `#Predicate` fetch of `SyncOperation` **traps** against a table that has never
held a row: an uncatchable `EXC_BREAKPOINT` inside SwiftData, not a thrown error,
so `try?` does not save the caller. It reproduces in every fresh in-memory
container, which means any test whose code path reaches the inbound conflict
guards (`acceptableFields`, `hasPendingOperations`) dies on the fetch rather than
failing an assertion.

Two remedies, by context:

- **Tests** seed one inert warm-up `SyncOperation` into the container before
  exercising those paths — see `makeContainer` in
  `OPSTests/Sync/CatalogMergeDiffGateTests.swift`.
- **Production code that must stay crash-proof** fetches predicate-free and
  filters in Swift — see the note on `ProjectCacheMerge.operations`
  (`OPS/Network/Sync/ProjectCacheMerge.swift`).

This is the one documented exception to the fetch-predication rule in
§ Performance Optimization → "Fetch Predication on Hot Paths"; it applies to
`SyncOperation` specifically, not to model tables generally.

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
- Private: `private let supabaseService: SupabaseService`
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
    private let supabaseService: SupabaseService

    // MARK: - Initialization
    init(supabaseService: SupabaseService) {
        self.supabaseService = supabaseService
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

## Dual-Backend Transition Architecture

### Current State (February 2026)

OPS is in a **dual-backend transition** from Bubble.io to Supabase. This is the most significant architectural change in the platform's history and affects every layer of the system.

```
┌────────────────────────────────────────────────────────────────────────┐
│                         CURRENT STATE (Feb 2026)                       │
├────────────────────────────────────────────────────────────────────────┤
│                                                                        │
│  ┌──────────────┐           ┌──────────────────────────────────────┐  │
│  │  iOS App     │──────────►│          Bubble.io REST API           │  │
│  │  (SwiftData) │           │  - Legacy CRUD for core entities     │  │
│  └──────────────┘           │  - Authentication (API token)        │  │
│                              │  - Soft delete workflows             │  │
│  ┌──────────────┐           │  - Source of truth for mobile        │  │
│  │  Android App │──────────►│                                      │  │
│  │  (Room)      │           └──────────────────────────────────────┘  │
│  └──────────────┘                                                      │
│                                                                        │
│  ┌──────────────┐           ┌──────────────────────────────────────┐  │
│  │  OPS Web     │──────────►│        Supabase (PostgreSQL)          │  │
│  │  (Next.js)   │           │  - Pipeline/CRM (est. 001-003)      │  │
│  └──────────────┘           │  - Core entities (migr. 004)         │  │
│                              │  - Pipeline refs (migr. 005)         │  │
│  ┌──────────────┐           │  - RLS company isolation             │  │
│  │  AWS S3      │           │  - Source of truth for web           │  │
│  │  (images)    │           └──────────────────────────────────────┘  │
│  └──────────────┘                                                      │
│                                                                        │
│  ┌──────────────┐                                                      │
│  │  Firebase    │  Analytics + Google Sign-In (iOS/Android)            │
│  └──────────────┘                                                      │
│                                                                        │
│  ┌──────────────┐                                                      │
│  │  Stripe      │  Subscriptions (via Bubble plugin currently)        │
│  └──────────────┘                                                      │
└────────────────────────────────────────────────────────────────────────┘
```

### Why Transition?

Bubble.io has served well as a rapid-prototyping backend, but it introduces limitations as OPS scales:

1. **Performance**: Bubble API has high latency compared to Supabase PostgREST
2. **Cost**: Bubble pricing increases with data volume and API calls
3. **Control**: No raw database access, no custom indexes, no stored procedures
4. **Real-time**: Bubble has no real-time subscription capability; Supabase has built-in realtime
5. **Authentication**: Bubble uses a static API token (not user-scoped); Supabase uses JWT with per-user claims
6. **Scalability**: Row-level security in Supabase provides automatic multi-tenant isolation

### Migration Strategy

The transition follows a **non-breaking incremental approach**:

**Phase 1 (Complete): Pipeline & Financial Tables**
- Supabase tables for opportunities, estimates, invoices, payments, products, etc.
- Web app reads/writes these directly
- Mobile apps do not interact with these tables

**Phase 2 (Complete): Core Entity Tables**
- Migration 004 creates Supabase mirrors of core Bubble entity types
- Migration 005 links pipeline tables to core entities via `_ref` FK columns
- Bulk migration API copies Bubble data into Supabase (`POST /api/admin/migrate-bubble`)
- Web app can now read/write core entities from Supabase

**Phase 3 (Planned): Supabase Auth**
- Replace Firebase + Bubble authentication with Supabase Auth
- JWT tokens will carry `app_metadata.company_id` for RLS enforcement
- Mobile apps will authenticate against Supabase instead of Bubble
- The `private.get_user_company_id()` RLS helper is already built for this

**Phase 4 (In Progress): Mobile App Migration**
- iOS and Android apps switch from Bubble API to Supabase PostgREST
- SyncEngine (rebuilt 2026-03-08) handles all Supabase sync via Operation Log + Replay pattern; remaining Bubble endpoints to be retired
- Offline-first architecture preserved; SyncEngine adapts to new API format
- SwiftData/Room models remain the same; only the network layer changes

**Phase 5 (Planned): Bubble Decommission**
- All clients (web, iOS, Android) use Supabase exclusively
- Direct S3 presigned URLs replace Bubble-mediated image uploads
- Direct Stripe integration replaces Bubble's Stripe plugin
- Bubble.io subscription cancelled

### Key Architectural Decisions

**1. bubble_id Column on Every Entity Table**
Every Supabase core entity table has a `bubble_id TEXT UNIQUE` column. This is the bridge between the old and new systems. During the transition, it enables:
- Idempotent migration via `ON CONFLICT (bubble_id)`
- Cross-referencing between Bubble and Supabase records
- Gradual migration without data loss

**2. _ref Columns Instead of Overwriting**
Migration 005 adds new `_ref` UUID columns to pipeline tables rather than modifying existing TEXT ID columns. This ensures:
- Existing pipeline queries continue to work
- The migration is non-breaking
- Both ID systems coexist during transition

**3. Service Role Client for Migration**
The migration API uses Supabase's service role client (bypasses RLS) because:
- It migrates data across ALL companies in one pass
- RLS company isolation would block cross-company bulk operations
- The service role is never exposed to the browser

**4. RLS Helper in Private Schema**
The `private.get_user_company_id()` function lives in a `private` schema inaccessible to API users:
```sql
CREATE SCHEMA IF NOT EXISTS private;

CREATE OR REPLACE FUNCTION private.get_user_company_id()
RETURNS UUID AS $$
  SELECT (auth.jwt() -> 'app_metadata' ->> 'company_id')::UUID;
$$ LANGUAGE sql STABLE SECURITY DEFINER;
```
This prepares for Phase 3 (Supabase Auth) while being callable from RLS policies today.

**5. Permission System RLS Helpers (Migration 015-016)**
Two additional private functions support the RBAC permission system:

```sql
-- Resolves app-level user UUID from Supabase auth.uid()
-- (auth.uid() is the Supabase Auth UUID, different from users.id)
CREATE OR REPLACE FUNCTION private.get_current_user_id()
RETURNS uuid LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = '' AS $$
  SELECT id FROM public.users
  WHERE auth_id = (SELECT auth.uid())::text
  LIMIT 1
$$;

-- Cached permission check — resolves user ID once per transaction
CREATE OR REPLACE FUNCTION private.current_user_has_permission(
  p_permission app_permission
) RETURNS boolean LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = '' AS $$
DECLARE v_user_id uuid;
BEGIN
  v_user_id := current_setting('app.current_user_id', true)::uuid;
  IF v_user_id IS NULL THEN
    v_user_id := (SELECT private.get_current_user_id());
    IF v_user_id IS NULL THEN RETURN false; END IF;
    PERFORM set_config('app.current_user_id', v_user_id::text, true);
  END IF;
  RETURN public.has_permission(v_user_id, p_permission);
END;
$$;
```

These are used by permission-based RLS policies on financial tables (invoices, estimates, payments, line_items, expenses, accounting_connections). See `04_API_AND_INTEGRATION.md` > Permission-Based RLS for details.

### Impact on Mobile Architecture

When mobile apps eventually migrate (Phase 4), the changes will be concentrated in the **network layer** only:

| Component | Current (Bubble) | Current/Future (Supabase) |
|-----------|------------------|-------------------|
| Data Models | SwiftData / Room | **No change** |
| Local Storage | SwiftData / Room | **No change** |
| Sync Strategy | Triple-layer sync | **SyncEngine** — Operation Log + Replay (rebuilt 2026-03-08) |
| API Client | SupabaseService + Repositories (partially migrated) | Supabase Swift/Kotlin client (full) |
| Auth | Static API token + Firebase | Supabase Auth JWT |
| Image Upload | Direct S3 + Bubble registration | Direct S3 (presigned URLs) via PhotoProcessor |
| Real-time | Polling (3-min timer) | RealtimeProcessor — Supabase Realtime WebSocket (9 merged entity types + 3 notification-only leads tables) |
| Offline Queue | `needsSync` flag pattern | **SyncOperation** records in SwiftData with OutboundProcessor coalescing |
| Connectivity | ConnectivityMonitor (basic reachability) | **ConnectivityManager** — NWPathMonitor with quality scoring + lying WiFi detection |
| Background Sync | BackgroundTaskManager | **BackgroundSyncScheduler** — BGTaskScheduler (refresh 15min, processing 30min) |

The offline-first architecture, defensive SwiftData/Room patterns, and operation coalescing will all be preserved. The migration primarily replaces the transport layer, not the application architecture.

### OPS-Web App Shell (rebuilt 2026-06-11 — WEB OVERHAUL P2)

The web app shell was rebuilt from scratch in P2 of the web overhaul (master plan: `ops-web/docs/specs/2026-06-11-web-overhaul-master-plan.md`; shell design + parity inventory: `ops-web/docs/specs/2026-06-11-web-overhaul-p2-shell-design.md`).

**Route registry — single source of truth.** `src/lib/navigation/route-registry.ts` owns every top-level route's href, icon, i18n label key (`navigation.json`, en + es), nav placement/order/group, RBAC permission, Phase C posture, badge binding, full-height layout mode, palette search aliases, and P3 absorption schedule (`absorbedBy`). Consumers: sidebar, top-bar titles, mobile drawer, command-palette nav section, 1–9 number shortcuts, the `(dashboard)/layout.tsx` route-permission gate, and `dashboard-layout.tsx` full-height modes. It replaced six drifted parallel tables (sidebar dict keys, top-bar hardcoded titles, breadcrumbs dict, layout permission map, palette literals, shortcut map). 42 invariant tests at `tests/unit/navigation/route-registry.test.ts`. Transition rule: nav entries exist only for routes that exist; each P3 wave swaps its absorbed entries + adds redirects in its landing commit.

**Shell composition** (`src/components/layouts/`):
- **Sidebar (`sidebar.tsx`)** — 72px HUD rail → 240px glass-dense hover overlay (120ms hover-intent, 80ms collapse grace, keyboard-focus parity, reduced-motion fallback). `// COMMAND` + `// OPS` group marks, Cake Mono 300 labels, 2px text-2 active bar (no accent on nav), company header, OPS mark + `package.json` version footer. Mobile <768px: 280px drawer + scrim + Escape. Gating: RBAC `can()` hides; commercial flag locks dim (request-access modal flow); `phaseCOnly` entries (Calibration, Agent Queue + pending badge) render only when `canAccessFeature("phase_c")`.
- **Operator menu (`operator-menu.tsx`)** — avatar/user section opens a 248px glass-dense menu: `// OPERATOR :: NAME` identity block (email + role tag), Settings, external destinations with ↗ (OPS Website, Courses, iOS App Store listing — `src/lib/constants/external-links.ts`), rose Sign Out.
- **Top bar (`top-bar.tsx`)** — registry-fed i18n page titles (en/es), breadcrumb store for nested routes, undo (⌘Z + stack), ⌘K search dispatch, live sync indicator, minute-tick 24h deck clock.
- **Edge rail** — see 07_SPECIALIZED_FEATURES §14 (Web Notifications Drawer) for the rebuilt fixed-height tab + drawer system.

**Schedule rename.** `/calendar` → `/schedule` (route dir moved; query-preserving 308 in `src/middleware.ts` keeps old notification `action_url`s resolving). All internal links, dictionaries (es: "Agenda"), palette, shortcuts, and widget CTAs re-pointed.

**Phase C company gating (client).** Prod `feature_flags` has no global `phase_c` row, and unknown slugs default to accessible in `useFeatureFlagsStore` — so `/api/feature-flags` appends **synthetic per-company flags** from `admin_feature_overrides`: `inbox_ui` (routes `/inbox`) and `phase_c` (routes `/calibration`, `/agent`). Fail-closed on errors. This is the mechanism that keeps Phase C operator surfaces invisible AND unreachable (in-place 404) for non-flagged companies; today only Canpro Deck and Rail carries `phase_c: true`.

**Z-index (nav band, per OPS-Web CLAUDE.md scale):** top bar 500 · mobile scrim 502 · sidebar 505 · dropdowns 1000 · edge rail 1540/1550/1560 (rest tab / drawer / active tab).

**Inbox posture (master plan §3):** no nav entry for anyone; the route survives behind the per-company `inbox_ui` flag (page-level server gate + synthetic client flag) so old links keep resolving for flagged companies.

### Web App Supabase Patterns

The web app already implements the Supabase patterns that mobile will eventually adopt:

**Query Pattern (TanStack Query + Supabase):**
```typescript
// Fetch projects for current company (RLS handles company isolation)
const { data: projects } = await supabase
  .from("projects")
  .select(`
    *,
    client:clients(*),
    tasks:project_tasks(*, task_type:task_types_v2(*))
  `)
  .is("deleted_at", null)
  .order("created_at", { ascending: false });
```

**Mutation Pattern:**
```typescript
// Create a project (company_id injected server-side by RLS context)
const { data, error } = await supabase
  .from("projects")
  .insert({
    company_id: user.company_id,
    client_id: selectedClientId,
    title: formData.title,
    status: "RFQ",
    address: formData.address,
  })
  .select()
  .single();
```

**Realtime Pattern (future mobile):**
```typescript
// Subscribe to project changes for current company
const subscription = supabase
  .channel("project-changes")
  .on("postgres_changes", {
    event: "*",
    schema: "public",
    table: "projects",
    filter: `company_id=eq.${companyId}`,
  }, (payload) => {
    // Handle insert/update/delete
  })
  .subscribe();
```

---

## Crew Location Tracking Architecture

### Overview

OPS includes a real-time crew location tracking system that enables admins/office crew to see field crew positions on the map. The architecture spans several files across Map/ and Utilities/.

### Key Components

| File | Path | Purpose |
|------|------|---------|
| `LocationManager.swift` | `Utilities/` | Core CLLocationManager wrapper. Publishes user coordinates, heading, and course. Handles permission requests and location update lifecycle. |
| `CrewLocationBroadcaster.swift` | `Map/Services/` | Broadcasts the current device's location via Supabase Realtime and persists to the `crew_locations` table. Active only when the user is clocked in. |
| `CrewLocationSubscriber.swift` | `Map/Services/` | Subscribes to crew location updates for the current org. Loads initial state from Supabase DB, then polls every 15 seconds for updates from other devices. |
| `CrewLocationUpdate.swift` | `Map/Models/` | Data model for a single crew location update (userId, lat/lng, heading, speed, accuracy, battery level, current task/project info). |
| `GeofenceManager.swift` | `Map/Core/` | Monitors the nearest 18 job sites using CLCircularRegion. Surfaces clock-in/out banners on region entry/exit with 15-second auto-dismiss. |
| `CrewAnnotationRenderer.swift` | `Map/Annotations/` | Renders crew member pins on the Mapbox map. |
| `LocationPermissionView.swift` | `Views/Components/Common/` | UI for requesting location permissions. |
| `MapLocationPermissionView.swift` | `Map/Views/` | Map-specific location permission prompt. |

### Data Flow

```
LocationManager (CoreLocation)
    │
    ▼
CrewLocationBroadcaster
    │ (publishes to Supabase crew_locations table)
    │ (posts NotificationCenter .crewLocationDidUpdate)
    ▼
Supabase crew_locations table
    │
    ▼
CrewLocationSubscriber (polls DB every 15s)
    │ (also receives local NotificationCenter updates)
    ▼
@Published crewLocations: [String: CrewLocationUpdate]
    │
    ▼
CrewAnnotationRenderer → Mapbox map pins
CrewTooltipCard → crew detail popups
```

### Geofencing

GeofenceManager uses iOS region monitoring (`CLCircularRegion`) for the nearest 18 project sites. On entry/exit, it publishes `pendingArrival` or `pendingDeparture` events, which trigger the `GeofenceBannerView` clock-in/out UI.

---

## Summary

### Architectural Strengths

1. **SwiftUI + SwiftData** - Modern, declarative, native iOS
2. **Offline-first with Operation Log** - Immutable SyncOperation records survive app termination, coalesced push on reconnect
3. **Field-level merge protection** - InboundProcessor and RealtimeProcessor preserve pending local changes during server pulls
4. **Defensive SwiftData patterns** - Prevents crashes and corruption
5. **Clear separation of concerns** - Views, ViewModels, DataController, SyncEngine, Processors
6. **Field-tested optimizations** - Lazy loading, caching, adaptive photo uploads, background tasks
7. **Dual-backend transition** - Non-breaking incremental migration from Bubble to Supabase

### Architectural Strengths (Sync Engine — Added 2026-03-08)

1. **Operation coalescing** - OutboundProcessor merges multiple updates to the same entity before pushing
2. **Dependency ordering** - Creates are pushed before child entities
3. **Exponential backoff** - `min(pow(2, retryCount), 60)` seconds with max 20 retries
4. **Adaptive photo uploads** - 3 concurrent on WiFi, 1 on cellular
5. **Lying WiFi detection** - ConnectivityManager detects connected-but-no-internet states
6. **Realtime WebSocket** - RealtimeProcessor subscribes to 9 merged entity types with catch-up delta sync on reconnect, plus 3 notification-only leads tables (opportunities/activities/follow_ups → `.opsLeadsDidChange`, debounced REST re-fetch, no merge)
7. **UI sync visibility** - SyncRingView in AppHeader, SyncStatusSection in NotificationListView

### Architectural Challenges

1. **No automated tests** - Regression risk (1 test file exists: MapTapGestureTest.swift)
2. **Complex state management** - Multiple sources of truth (AppState, DataController, 7 ViewModels)
3. **NotificationCenter coupling** - Deep linking via NotificationCenter is brittle
4. **Large ViewModels** - CalendarViewModel is 500+ lines
5. **Dual-backend complexity** - During transition, some data flows through Bubble while new features use Supabase directly
6. **Legacy sync adapter** - SupabaseSyncManager retained for entity fetch methods not yet migrated to SyncEngine

### Android Conversion Implications

**Easy to Convert**:
- Data models (SwiftData -> Room entities)
- Network layer (Supabase Swift SDK -> Supabase Kotlin SDK)
- State management (ObservableObject -> StateFlow/ViewModel)

**Hard to Convert**:
- SwiftUI views (no 1:1 Compose equivalent)
- Navigation system (TabView + sheets -> Compose Navigation)
- Environment objects (SwiftUI-specific -> Hilt DI)

**Critical Patterns to Preserve**:
- Offline-first architecture with Operation Log + Replay
- Defensive data patterns (IDs not models, explicit saves)
- Soft delete strategy
- Operation coalescing and field-level merge protection
- Adaptive connectivity handling (WiFi vs. cellular concurrency)

---

## Job Board Architecture (Redesigned March 2026)

### Overview

The Job Board is the central operational hub of OPS. It was redesigned in March 2026 to support a fully role-based section system replacing the old single-view approach.

### JobBoardSection Enum

```swift
// File: Views/JobBoard/JobBoardView.swift
enum JobBoardSection: String, CaseIterable {
    case myTasks    = "MY TASKS"      // Crew: tasks explicitly assigned to user
    case myProjects = "MY PROJECTS"   // Crew: projects user is a team member of
    case projects   = "PROJECTS"      // Office/Admin: all company projects with filters
    case tasks      = "TASKS"         // Office/Admin: all company tasks with filters
    case kanban     = "KANBAN"        // Office/Admin: project distribution by status
    case pipeline   = "PIPELINE"      // Admin + specialPermissions("pipeline"): CRM pipeline
}
```

### Role-Based Section Visibility

**Legacy implementation** (being migrated to permission-based checks):

```swift
// LEGACY: Uses UserRole enum. Being replaced by permission checks:
// - job_board.manage_sections → shows section picker
// - pipeline.view → shows Pipeline section
// - projects.view scope=assigned → limits to My Tasks / My Projects
func visibleSections(for user: User?) -> [JobBoardSection] {
    guard let user = user else { return [.projects] }
    switch user.role {
    case .crew:
        return [.myTasks, .myProjects]
    case .office:
        return [.projects, .tasks, .kanban]
    case .admin:
        var sections: [JobBoardSection] = [.projects, .tasks, .kanban]
        if user.specialPermissions.contains("pipeline") {
            sections.append(.pipeline)
        }
        return sections
    }
}

// Default starting section per role
func defaultSection(for user: User?) -> JobBoardSection {
    guard let user = user else { return .projects }
    return user.role == .crew ? .myTasks : .projects
}
```

**Permission-based replacement**: With the new RBAC system, section visibility should use `can("job_board.manage_sections")` for the section picker and `can("pipeline.view")` for the Pipeline section. Users with `projects.view` scoped to `assigned` see only My Tasks / My Projects.

**Key business rules:**
- Crew: Section picker is hidden. Always shows `.myTasks` (no toggle to other sections)
- Office: Sees projects, tasks, kanban — no pipeline unless granted
- Admin: Sees pipeline section only if `specialPermissions.contains("pipeline")`
- Tutorial mode: Forces `.projects` section for tutorial phases that require it

### Section Views

| Section | View | Purpose |
|---------|------|---------|
| `.myTasks` | `JobBoardMyTasksView` | Crew personal task list, filtered by explicit assignment |
| `.myProjects` | `JobBoardProjectListView` (filtered) | Crew project list, filtered to assigned projects only |
| `.projects` | `JobBoardProjectListView` | All company projects with status/team filters |
| `.tasks` | `JobBoardTasksView` (inline in JobBoardView) | All company tasks with status/type filters |
| `.kanban` | `JobBoardKanbanView` | Project distribution across statuses as proportional bars |
| `.pipeline` | `PipelineView()` | CRM pipeline — uses `@EnvironmentObject`, takes no init parameters |

### Shared JobBoard List Rules

```
File: OPS/Utilities/JobBoardListRules.swift
```

- `JobBoardTaskFiltering.visibleTasks(from:)` is the source of truth for the office/admin `.tasks` section.
- Task cards are shown only when the parent project is non-deleted and in an active operational status: `.rfq`, `.estimated`, `.accepted`, `.inProgress`.
- Tasks from `.completed`, `.closed`, `.archived`, or soft-deleted projects are hidden from active task lists.
- Task rows are deduplicated by `ProjectTask.id` before rendering.
- `ProjectListOrdering.activeFirst(_:)` is the source of truth for client/contact project lists. It drops soft-deleted projects, sorts active lifecycle projects first, then `.closed`, then `.archived`, with newest project dates first inside each group.
- RFQ and Estimated remain active lifecycle statuses in iOS list filtering. Their removal is not implemented until the lifecycle decision is explicitly unshelved.

### JobBoardMyTasksView

```
File: Views/JobBoard/JobBoardMyTasksView.swift
```

- Shows tasks from `assignedProjects` where `task.getTeamMemberIds().contains(userId)`
- **No fallback for unassigned tasks** — tasks with no explicit assignment are NOT shown
- `MyTasksFilter` enum: `.all`, `.today`, `.upcoming`, `.completed`
- Groups tasks by project using collapsible `ProjectTaskGroup`
- Has skeleton loading state and retry error state

### JobBoardKanbanView

```
File: Views/JobBoard/JobBoardKanbanView.swift
```

- Shows proportional fill bars for 5 project statuses: `.rfq`, `.estimated`, `.accepted`, `.inProgress`, `.completed`
- Fill width = `count / totalActiveProjects` (excludes `.closed`)
- Tap a bar → expands inline with project cards on a tinted backdrop
- Uses `.accessibleEaseInOut(duration: 0.25)` for all transitions

### UniversalSearchSheet

```
File: Views/JobBoard/UniversalSearchSheet.swift
```

- Opened via `AppState.showingJobBoardSearch = true` from the header search button
- Role-filtered: field crew sees only their assigned projects
- **Pipeline-gated**: users without `specialPermissions.contains("pipeline")` cannot see `.rfq` or `.estimated` projects in search results
- Indexed sections (each a titled group): **projects** (title, client name, address), **tasks** (`displayTitle`, `taskNotes`), **clients**, **team**, **leads**, **invoices**, **estimates**, and **catalog / inventory**
  - **Leads** (bug ac2ace7a): opportunities are network-only (not in SwiftData), so the sheet loads them via a `PipelineViewModel` on appear, gated on `pipeline` access. Matched by contact name, title, email, phone, address, or linked client name. Active leads show first; terminal stages (won / lost / discarded) sit behind a "WON, LOST & DISCARDED" disclosure. A one-tap Call action dials the contact; tapping the row posts `OpenLeadDetails` (MainTabView re-checks pipeline access and pushes `LeadDetailView`).
  - **Invoices & estimates** match their number / title **plus resolved client name and project title** — a customer or job search now surfaces the paperwork attached to it, and each row shows the client for scannability.
  - Lead / invoice / estimate match predicates live in the pure, unit-tested `OPS/Utilities/UniversalSearchMatching.swift` (extracted like `UniversalSearchScheduleTargeting`), covered by `OPSTests/Views/JobBoard/UniversalSearchMatchingTests.swift`.
- Auto-focuses keyboard on appear

### DirectionalDragModifier

```
File: Views/Components/Common/DirectionalDragModifier.swift
```

Resolves the scroll-vs-swipe gesture conflict on `UniversalJobBoardCard` inside `ScrollView`.

```swift
// Commits only after movement exceeds 12pt:
// - Horizontal intent requires width > height * 3
// - Vertical or diagonal intent releases the row to the ScrollView
struct DirectionalDragModifier: ViewModifier {
    let isEnabled: Bool
    var onChanged: ((CGFloat) -> Void)?
    var onEnded: ((CGFloat) -> Void)?

    @State private var resolvedAxis: DirectionalDragAxis = .undecided
}
```

Used via the `.directionalDrag(isEnabled:onChanged:onEnded:)` View extension.
The axis decision is centralized in `DirectionalDragClassifier`, and long-press menus on `UniversalJobBoardCard` require a 0.55s stationary press with a 12pt maximum distance so slow vertical scrolling does not open the menu.

### AppState.showingJobBoardSearch

`AppState` (file: `AppState.swift`) publishes `showingJobBoardSearch: Bool` to trigger the search sheet from any context (e.g., header button in `AppHeader`).

```swift
// In AppHeader, search button:
Button { appState.showingJobBoardSearch = true } label: { ... }

// In JobBoardView, sheet binding:
.sheet(isPresented: $appState.showingJobBoardSearch) {
    UniversalSearchSheet()
}
```

### Accessibility-Aware Animations

All Job Board animations use `Animation.accessibleEaseInOut()` from `Extensions/Animation+Accessible.swift`:

```swift
extension Animation {
    static func accessibleEaseInOut(duration: Double = 0.25) -> Animation? {
        UIAccessibility.isReduceMotionEnabled ? nil : .easeInOut(duration: duration)
    }
}
```

**Never use `.spring()` in any Job Board view** — or anywhere in OPS. Spring animations do not respect the Reduce Motion accessibility setting.

---

**End of Technical Architecture Documentation**

This document provides complete architectural context for OPS iOS app, the offline-first sync engine (rebuilt 2026-03-08), and the dual-backend transition. Reference alongside:
- `01_IOS_ARCHITECTURE_OVERVIEW.md` - High-level overview
- `02_DATA_MODELS.md` - SwiftData models and relationships
- `03_DATA_ARCHITECTURE.md` - Data models, Bubble fields, and Supabase schema
- `04_API_AND_INTEGRATION.md` - API endpoints, sync details, and migration API
- `10_ANDROID_CONVERSION_PLAN.md` - Android conversion strategy
