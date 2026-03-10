# OPS Software Bible

**Complete Technical Documentation for the OPS Application**

This documentation serves as the comprehensive reference for the OPS (Operational Project System) iOS application. It is designed to enable any developer or AI agent with **zero prior context** to understand and rebuild the entire application with 100% feature parity.

---

## Document Navigation

### Getting Started

Start with the Executive Summary to understand the business context, then proceed through the documents in order for a complete understanding.

---

### 📋 [00_EXECUTIVE_SUMMARY.md](00_EXECUTIVE_SUMMARY.md)
**High-level overview for stakeholders and context-setting**

- Elevator pitch (founder's authentic voice)
- Target market and user personas (Admin, Office Crew, Field Crew)
- Core value propositions and competitive advantages
- Key statistics (437 Swift files, 24 SwiftData models, pricing)
- Technology stack overview
- Product vision and roadmap

**Start here for:** Business context, market positioning, product strategy

---

### 📝 [01_PRODUCT_REQUIREMENTS.md](01_PRODUCT_REQUIREMENTS.md)
**Complete feature inventory and user stories**

- Feature-by-feature catalog (authentication, projects, tasks, calendar, navigation, etc.)
- User stories for all 3 roles
- Business rules and constraints
- Offline-first requirements
- Field-specific requirements (gloves, sunlight, poor connectivity)
- Subscription and access control rules

**Start here for:** Understanding what the app does and why

---

### 🎨 [02_USER_EXPERIENCE_AND_WORKFLOWS.md](02_USER_EXPERIENCE_AND_WORKFLOWS.md)
**Navigation flows and user journeys**

- Navigation architecture (tab bar + sheets)
- Onboarding flows (Company Creator vs Employee)
- 25-phase interactive tutorial system
- User journey maps for common workflows
- Complete screen catalog with UI elements
- Gesture patterns (swipe-to-change-status, pull-to-refresh)
- Role-based UI differences

**Start here for:** Understanding how users interact with the app

---

### 🗄️ [03_DATA_ARCHITECTURE.md](03_DATA_ARCHITECTURE.md)
**Complete data model reference**

- All 24 SwiftData models (11 core + 13 Supabase-backed) with full property lists
- Entity relationships and cardinality
- BubbleFields.swift constants (byte-perfect API mappings)
- All DTOs with conversion logic
- Soft delete strategy (30-day window)
- Computed properties and business logic
- Migration history (Scheduled→Booked, task-only calendar)
- Query predicates and filtering patterns

**Start here for:** Implementing the data layer

**Lines:** ~1,200 | **Models:** 24 | **DTOs:** 8+

---

### 🔄 [04_API_AND_INTEGRATION.md](04_API_AND_INTEGRATION.md)
**API endpoints and sync strategy**

- Supabase as primary backend: 15 repositories, 30 tables, Realtime WebSocket subscriptions
- Triple-layer sync strategy (immediate, event-driven, periodic)
- SupabaseSyncManager (replaced CentralizedSyncManager)
- Image upload/S3 integration
- Stripe subscription integration
- Firebase Analytics (30+ tracked events)
- OneSignal push notifications
- Error handling and retry logic
- Rate limiting and 2-second debouncing
- Bubble.io legacy API reference (for historical context)

**Start here for:** Implementing backend integration and sync

**Lines:** ~1,284 | **Repositories:** 15 | **Tables:** 30 | **Events:** 30+

---

### 🎨 [05_DESIGN_SYSTEM.md](05_DESIGN_SYSTEM.md)
**Complete visual design reference**

- **Verified production colors** from Asset Catalog
  - Primary: #417394 (steel blue)
  - Secondary: #C4A868 (amber/gold)
  - Background: #000000 (pure black)
  - Text: #E5E5E5 (off-white)
- Typography system (Mohave, Kosugi, Bebas Neue)
- 50+ reusable UI components with usage examples
- Layout grid (8pt) and spacing rules (56pt touch targets)
- Icon system (50+ SF Symbols)
- Status colors and badges
- Field-first design principles

**Start here for:** Implementing the UI layer

**Lines:** ~900 | **Components:** 50+ | **Icons:** 50+

---

### 🏗️ [06_TECHNICAL_ARCHITECTURE.md](06_TECHNICAL_ARCHITECTURE.md)
**Code structure and architectural patterns**

- Complete directory structure (437 Swift files)
- SwiftUI + SwiftData architecture
- State management (AppState, DataController, ViewModels)
- Navigation system (TabView + NavigationStack)
- Dependency injection patterns
- Error handling strategies
- Performance optimization techniques
- SwiftData defensive programming (8 critical patterns)
- Testing requirements

**Start here for:** Understanding code organization and patterns

**Lines:** ~800 | **Files:** 437 | **Patterns:** 8

---

### ⚙️ [07_SPECIALIZED_FEATURES.md](07_SPECIALIZED_FEATURES.md)
**Complex feature implementations**

- Turn-by-turn navigation with Kalman filter GPS smoothing
- 25-phase interactive tutorial system
- Calendar event scheduling (task-only architecture)
- Image capture and S3 sync with offline queue
- PIN management (4-digit, Keychain storage)
- Job Board sections and filtering
- Swipe-to-change-status gesture implementation
- Form sheets with progressive disclosure
- Floating Action Menu
- Advanced UI patterns
- **Project Notes System (OPS Web)** — first-class notes with @mentions, author attribution, photo attachments, legacy migration

**Start here for:** Implementing complex features

**Lines:** ~1,100 | **Features:** 11

---

### 💰 [09_FINANCIAL_SYSTEM.md](09_FINANCIAL_SYSTEM.md)
**Pipeline, Estimates, Invoices & Financial Architecture (OPS Web)**

- Supabase as primary backend for all data (financial + operational)
- Pipeline/CRM: 8-stage Kanban, drag-and-drop, stage transitions, follow-ups, activity timeline
- Estimates: quote builder, line items, optional items, deposit/milestones, estimate→invoice RPC
- Invoices: billing documents, payment recording, DB-trigger-maintained balances, payment voiding
- Products & Services catalog with margin tracking
- Accounting integrations (QuickBooks, Sage OAuth)
- Supabase schema: 13+ tables, RLS, DB triggers, RPCs
- Service layer patterns (camelCase↔snake_case, TanStack Query)
- All business rules and DB constraints

**Start here for:** Implementing the financial system (web)

**Lines:** ~600 | **Tables:** 13 | **Services:** 5

---

### 🔄 [10_JOB_LIFECYCLE_AND_DATA_RELATIONSHIPS.md](10_JOB_LIFECYCLE_AND_DATA_RELATIONSHIPS.md)
**Complete Job Lifecycle: Inquiry → Close — Entity Relationships & Automation**

- End-to-end flow: lead → pipeline → estimate → project → tasks → invoice → closed
- Pipeline as the job spine: all 8 stages with auto-advance triggers and manual overrides
- Zero duplicate entry design: estimate sends create client + project; approval creates tasks
- New entities: TaskTemplate, ActivityComment, SiteVisit, ProjectPhoto, GmailConnection
- Modified entities: LineItem (type/taskTypeId), TaskType (defaultTeamMemberIds), Project (opportunityId), CalendarEvent (removed — scheduling now on ProjectTask), Estimate (projectId), Invoice (projectId/estimateId), Product (type/taskTypeId), Activity (email threading/attachments)
- Automation rules: client auto-creation, project auto-creation, task generation, status cascades, auto follow-ups
- Communication logging: manual (call/email/meeting/note) + Gmail auto-logging + activity comments
- Site visits: schedulable, on-site photo/note capture, lifecycle status, photo continuity to project
- Gmail integration: company inbox + per-user, incremental sync, inbox leads queue, 6-step setup wizard, AI email classification (GPT-4o-mini), 3-tier client matching, historical import with approved contacts, domain-based company grouping, existing client detection, structured email filter rules
- Complete Supabase ALTER TABLE statements and new table SQL
- 4-phase implementation priority order

**Start here for:** Implementing any feature that spans multiple entities (estimates→tasks, leads→clients, site visits, Gmail)

**Lines:** ~700 | **New Entities:** 5 | **Modified Entities:** 9 | **Automation Rules:** 7

---

### 🌐 [11_CLIENT_PORTAL.md](11_CLIENT_PORTAL.md)
**Client-Facing Portal: Estimates, Invoices, Questions, Payments & Messaging (OPS Web)**

- Client portal architecture: separate auth (magic link + email verification), 30-day sessions
- 6 new Supabase tables: portal_tokens, portal_sessions, portal_branding, line_item_questions, line_item_answers, portal_messages
- Line-item questions: unique feature — 5 answer types (text, select, multiselect, color, number) attached to estimate line items
- Company-customizable branding: 3 templates (Modern, Classic, Bold), light/dark mode, accent color, logo
- Estimate approve/decline, Stripe invoice payments, project photos + timeline, two-way messaging
- Admin features: branding settings tab, question editor in estimate builder, portal inbox, share button
- SendGrid email templates, TanStack Query hooks, activity logging
- ~50 new files, 6 services, 13 API routes

**Start here for:** Implementing the client portal (web)

**Lines:** ~600 | **Tables:** 6 | **Pages:** 8 | **Components:** 14

---

### 🚀 [08_DEPLOYMENT_AND_OPERATIONS.md](08_DEPLOYMENT_AND_OPERATIONS.md)
**Production deployment and operations**

- Build configuration (Xcode, iOS 17+)
- Environment variables and secrets
  - Bubble.io API (base URL, token)
  - AWS S3 credentials
  - Firebase configuration
  - Stripe price IDs
- Subscription tiers ($90-$190/month)
- Analytics tracking (Firebase)
- Testing requirements (field-first checklist)
- App Store deployment process
- Data migrations (SwiftData patterns)
- Bubble.io backend configuration
- Production checklist

**Start here for:** Deploying to production

**Lines:** ~730 | **Tiers:** 4 | **Events:** 30+

---

## Quick Reference

### By Use Case

**"I need to understand the business"**
→ Start with [00_EXECUTIVE_SUMMARY.md](00_EXECUTIVE_SUMMARY.md)

**"I need to know what features exist"**
→ Read [01_PRODUCT_REQUIREMENTS.md](01_PRODUCT_REQUIREMENTS.md)

**"I need to build the UI"**
→ Read [02_USER_EXPERIENCE_AND_WORKFLOWS.md](02_USER_EXPERIENCE_AND_WORKFLOWS.md) + [05_DESIGN_SYSTEM.md](05_DESIGN_SYSTEM.md)

**"I need to implement the data layer"**
→ Read [03_DATA_ARCHITECTURE.md](03_DATA_ARCHITECTURE.md)

**"I need to implement sync"**
→ Read [04_API_AND_INTEGRATION.md](04_API_AND_INTEGRATION.md)

**"I need to understand the codebase"**
→ Read [06_TECHNICAL_ARCHITECTURE.md](06_TECHNICAL_ARCHITECTURE.md)

**"I need to implement navigation"**
→ Read [07_SPECIALIZED_FEATURES.md](07_SPECIALIZED_FEATURES.md)

**"I need to implement pipeline, estimates, or invoices"**
→ Read [09_FINANCIAL_SYSTEM.md](09_FINANCIAL_SYSTEM.md)

**"I need to implement project notes or @mentions"**
→ Read [07_SPECIALIZED_FEATURES.md](07_SPECIALIZED_FEATURES.md) Section 11

**"I need to understand how entities connect (leads → clients → projects → tasks → invoices)"**
→ Read [10_JOB_LIFECYCLE_AND_DATA_RELATIONSHIPS.md](10_JOB_LIFECYCLE_AND_DATA_RELATIONSHIPS.md)

**"I need to implement site visits, Gmail logging, or activity comments"**
→ Read [10_JOB_LIFECYCLE_AND_DATA_RELATIONSHIPS.md](10_JOB_LIFECYCLE_AND_DATA_RELATIONSHIPS.md)

**"I need to implement the client portal (magic links, estimates, payments, messaging)"**
→ Read [11_CLIENT_PORTAL.md](11_CLIENT_PORTAL.md)

**"I need to deploy to production"**
→ Read [08_DEPLOYMENT_AND_OPERATIONS.md](08_DEPLOYMENT_AND_OPERATIONS.md)

---

## Documentation Statistics

- **Total Documents:** 12 (including this README)
- **Total Lines:** ~9,100+ lines of documentation
- **Total Code Examples:** 120+ code snippets
- **Coverage:** 437 Swift files, 24 SwiftData models, 30 Supabase tables, 15 repositories, 50+ UI components, full financial system, complete job lifecycle, project notes system, client portal, inventory system, photo annotations, in-app notifications

---

## Key Principles

This documentation was created with the following principles:

1. **Code is Truth** - When documentation conflicts with code, code wins
2. **Zero Context Assumption** - An agent with no prior knowledge can build the entire app
3. **Byte-Perfect Accuracy** - BubbleFields constants, colors, and dimensions are exact
4. **Field-First** - Always emphasize practical field worker needs
5. **Complete Coverage** - Every feature, screen, and component documented
6. **Cross-Referenced** - Documents reference each other for context

---

## Success Criteria

This documentation is considered complete when:

✅ An agent with **zero prior context** can read these documents and build a fully functional OPS web application with 100% feature parity to iOS

✅ All 24 SwiftData models documented with complete property lists and relationships

✅ All API endpoints cataloged with request/response formats

✅ All 50+ UI components documented with usage patterns

✅ Color palette, typography, and design constants verified from production code

✅ Business rules and constraints explicitly documented

✅ User workflows for all 3 roles comprehensively mapped

✅ Sync strategy and conflict resolution fully explained

✅ No contradictions between documents

✅ Code examples provided for complex implementations

---

## Android Conversion Notes

Throughout these documents, you'll find Android-specific guidance for converting the iOS app to Android:

- **Data Models:** Room equivalents for SwiftData
- **API Layer:** Retrofit + OkHttp equivalents
- **UI Components:** Jetpack Compose equivalents
- **State Management:** ViewModel + StateFlow patterns
- **Navigation:** Compose Navigation equivalents
- **Critical Gaps:** PIN digit mismatch (iOS=4, Android=6), missing FloatingActionMenu

See `C:\OPS\android-plan-v2\` for the complete Android conversion plan.

---

## Maintenance

**Last Updated:** February 28, 2026

**iOS App Version:** 437 Swift files, 24 SwiftData models, iOS 17+, Supabase primary backend

**Web App Version:** Next.js, Supabase (30 tables, 13 migrations), Pipeline/Estimates/Invoices/Project Notes/Inventory/Notifications/Client Portal live

**Ecosystem:** ops-site (marketing website), ops-learn (learning platform), try-ops (interactive tutorial/demo)

**Document Version:** 1.5 — Updated to reflect Supabase as primary backend, 437 Swift files, 24 SwiftData models, ecosystem apps, inventory/notifications/photo annotations

**Maintainer:** Update these documents when making architectural changes, adding features, or modifying business rules. Keep code examples in sync with actual implementation.

---

## Contact

For questions about this documentation or the OPS app:

- **Project Location:** `C:\OPS\opsapp-ios\`
- **Android Plan:** `C:\OPS\android-plan-v2\`
- **This Documentation:** `C:\OPS\ops-software-bible\`

---

**Built By Trades, For Trades** 🛠️
