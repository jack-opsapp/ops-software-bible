# 06. Technical Architecture

**Document Purpose**: Complete technical reference for OPS iOS app architecture, file organization, state management patterns, and development best practices.

**Last Updated**: March 8, 2026
**iOS Codebase**: 437+ Swift files, SwiftUI + SwiftData architecture
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
│   SwiftData Models (24 entities), DTOs (16 types)  │
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
OPS/OPS/
├── OPSApp.swift                    # App entry point, model container setup (24 models)
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
│   ├── Sync/ (9 files — rebuilt 2026-03-08, DataActor refactor 2026-04-19)
│   │   ├── SyncEngine.swift             # @MainActor @Observable orchestrator; dispatches through DataActor when FeatureFlags.useDataActor is on (default true 2026-04-19)
│   │   ├── OutboundProcessor.swift      # LEGACY @MainActor path for local→server push; retained behind FeatureFlags.useDataActor for rollback
│   │   ├── InboundProcessor.swift       # LEGACY @MainActor path for server→local pull; retained behind FeatureFlags.useDataActor for rollback
│   │   ├── RealtimeProcessor.swift      # @MainActor Supabase Realtime WebSocket subscription (9 entity types); SwiftData writes dispatch to DataActor when flag on
│   │   ├── PhotoProcessor.swift         # @MainActor adaptive photo uploads (WiFi 3 concurrent, cellular 1) — moves to PhotoActor in Phase 3
│   │   ├── BackgroundSyncScheduler.swift  # BGTaskScheduler wrapper (refresh 15min, processing 30min)
│   │   ├── SyncTypes.swift              # Shared enums (SyncError, ConnectionState, SyncEntityType — 27 registered, 12 inbound-synced)
│   │   ├── SyncStatusProvider.swift     # UI state bridge for sync indicators
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
│   ├── PipelineViewModel.swift     # Sales pipeline state
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
│   │   ├── Common/ (26 files)
│   │   │   ├── LoadingOverlay.swift
│   │   │   ├── CustomTabBar.swift
│   │   │   ├── TabBarBackground.swift
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
│   │   ├── Scheduling/ (1 file)
│   │   │   └── CalendarSchedulerSheet.swift
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
├── Onboarding/ (56 files)
│   ├── OnboardingCopy.swift        # Copy text constants
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
├── Utilities/ (28 files)
│   ├── DataController.swift        # Central data coordinator (~5000 lines; @MainActor, owns DataActor + refresh bridge)
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
    // Shared model container for entire app (24 models)
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            // Core data models (11)
            User.self,
            Project.self,
            Company.self,
            TeamMember.self,
            Client.self,
            SubClient.self,
            ProjectTask.self,
            TaskType.self,
            TaskStatusOption.self,
            SyncOperation.self,
            OpsContact.self,
            // Supabase-backed models (13)
            Opportunity.self,
            Activity.self,
            FollowUp.self,
            StageTransition.self,
            Estimate.self,
            EstimateLineItem.self,
            Invoice.self,
            InvoiceLineItem.self,
            Payment.self,
            Product.self,
            SiteVisit.self,
            ProjectNote.self,
            PhotoAnnotation.self
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
                .environmentObject(notificationManager)
                .environmentObject(subscriptionManager)
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

**Phase 2 scope (pending post-bake).** DataController CRUD write methods (`deleteProject/deleteTask/deleteClient/deleteUserAccount/updateUserProfile/updateTaskStatus/updateProjectStatus/saveClient/createProject/createTask/createClient/createTaskType/markForSyncAndAttemptImmediate/performSyncedOperation`) + sync helpers (`syncProjectTeamMembers/syncTaskStatusOptions/backfillOnboardingCompleted/forceRefreshCompany/removeSampleProjects/fetchOpsContacts`). View-driven `@Bindable` edits stay on main. Flag: `useActorForDataControllerWrites`.

**Phase 3 scope (pending).** Extract dedicated `PhotoActor` for `LocalPhoto` writes + photo upload pipeline. Parallel write lane with DataActor. Flag: `usePhotoActor`.

**Known followup.** At dev-account scale, `MainContextRefreshBridge.model(for:)` force-registration adds small per-row overhead with no amortizing benefit (no main-thread pin to relieve at <50 rows). Tracked as Supabase `bug_reports` `914b3945-27f5-4823-9e4b-d42f0407fcc2`; resolved at mid-size scale.

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

### Error Handling in Sync Engine (Updated 2026-03-08)

```swift
// SyncTypes.swift — error classification
enum SyncError: Error {
    case network(Error)       // Retryable — OutboundProcessor applies exponential backoff
    case conflict(String)     // Field-level merge — InboundProcessor preserves pending local fields
    case permanent(Error)     // Non-retryable — operation marked failed, surfaced in UI
    case authentication       // Triggers re-auth flow
}

// OutboundProcessor.swift — push error handling
// Each SyncOperation tracks retryCount. On failure:
//   - Retryable errors: increment retryCount, backoff = min(pow(2, retryCount), 60) seconds
//   - Max 20 retries before marking as permanently failed
//   - Permanent errors: mark operation as failed immediately
//   - Failed operations surfaced in SyncStatusSection (NotificationListView)

// InboundProcessor.swift — pull conflict handling
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
- Supabase Realtime WebSocket subscriptions for 9 entity types
- Field-level merge protection same as InboundProcessor
- Tracks disconnect/reconnect timestamps for catch-up delta sync on reconnect

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
    try? modelContext.delete(model: TaskType.self)
    try? modelContext.delete(model: Opportunity.self)
    try? modelContext.delete(model: Estimate.self)
    try? modelContext.delete(model: Invoice.self)
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
| Real-time | Polling (3-min timer) | RealtimeProcessor — Supabase Realtime WebSocket (9 entity types) |
| Offline Queue | `needsSync` flag pattern | **SyncOperation** records in SwiftData with OutboundProcessor coalescing |
| Connectivity | ConnectivityMonitor (basic reachability) | **ConnectivityManager** — NWPathMonitor with quality scoring + lying WiFi detection |
| Background Sync | BackgroundTaskManager | **BackgroundSyncScheduler** — BGTaskScheduler (refresh 15min, processing 30min) |

The offline-first architecture, defensive SwiftData/Room patterns, and operation coalescing will all be preserved. The migration primarily replaces the transport layer, not the application architecture.

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
6. **Realtime WebSocket** - RealtimeProcessor subscribes to 9 entity types with catch-up delta sync on reconnect
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
- Searches: project title, client name, address; task `displayTitle` and `taskNotes`
- Pinned section headers: `[ PROJECTS ]`, `[ TASKS ]`
- Auto-focuses keyboard on appear

### DirectionalDragModifier

```
File: Views/Components/Common/DirectionalDragModifier.swift
```

Resolves the scroll-vs-swipe gesture conflict on `UniversalJobBoardCard` inside `ScrollView`.

```swift
// Commits to a drag axis within the first 10pt of movement:
// - Horizontal intent → captures the swipe for status change
// - Vertical intent → releases gesture to ScrollView for normal scrolling
struct DirectionalDragModifier: ViewModifier {
    let isEnabled: Bool
    var onChanged: ((CGFloat) -> Void)?
    var onEnded: ((CGFloat) -> Void)?

    @GestureState private var dragState: DragAxisState = .undecided
    private let threshold: CGFloat = 10

    // dragState is still valid in onEnded — @GestureState resets AFTER onEnded fires
}
```

Used via the `.directionalDrag(isEnabled:onChanged:onEnded:)` View extension.

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
