# 00_EXECUTIVE_SUMMARY.md

## Document Purpose

This executive summary provides a high-level overview of OPS (Operational Project System) for non-technical stakeholders and serves as the entry point for understanding the product, market, and technical foundation.

---

## Elevator Pitch (Founder's Voice)

OPS is job management software built by a subtrade (deck & railing) for service-based businesses and specialized trades—electricians, plumbers, landscapers, deck builders, cleaners. Not for general contractors.

**Important terminology:** Jack is a subtrade, not a contractor. Subtrades DO the work. Contractors sub out work to others. OPS is for the people who do the work. Never refer to the founder or OPS users as "contractors" or "tradesperson" (sounds forced). Use: tradesmen, trades, owner-operator, operator, crew, team lead, founder, owner, business owner.

I scaled a deck and railing business from $0 to $1.6M in 4 years. In my last year, I tried Jobber, ServiceTitan, Housecall Pro—my crew wouldn't touch any of them. Too complex, too unintuitive. So I built OPS and used it to break the million-dollar mark.

OPS does everything you need—schedule jobs, assign crew, track status, navigate to sites, document with photos—and it works offline when signal cuts out.

We charge $90 to $190 a month based on crew size, and we ship new features every week based on what you actually need. If you tell us you need something, we build it. Direct line to the founder—me.

Try the interactive tutorial on our site in 3 minutes, no download required, and see why crews actually use this.

---

## Target Market

### Industry Verticals
Based on survey data and target market analysis, OPS serves specialized service-based trades:

- **Window cleaning and exterior cleaning**
- **Landscaping and lawn care**
- **Electrical contractors**
- **Plumbing**
- **Mobile automotive detailing**
- **Aluminum railings**
- **Residential and commercial cleaning**

**Not for:** General contractors, project management for construction sites, multi-trade coordination

### User Personas (5 Roles)

OPS uses a granular RBAC+ABAC permissions system with 5 preset roles, ~55 permissions, and scope support (`all`, `assigned`, `own`). See `03_DATA_ARCHITECTURE.md` > Permissions System Tables for the complete schema.

**1. Admin (Hierarchy 1)**
- Full system access including billing, roles, and all settings
- Only role that can assign roles to other users
- Manages company settings, subscription, team structure

**2. Owner (Hierarchy 2)**
- Full access except billing and role assignment
- Can manage company settings and integrations
- Oversees all projects, tasks, crew assignments

**3. Office (Hierarchy 3)**
- Office staff with full project and financial access
- Creates and schedules projects and tasks
- Manages clients, estimates, invoices, pipeline
- No company settings, billing, or role management

**4. Operator (Hierarchy 4)**
- Lead tech / field supervisor
- Creates projects, tasks, clients, estimates
- Edits only assigned work (scoped access)
- No pipeline, inventory, or admin access

**5. Crew (Hierarchy 5)**
- Workers in the field using the app on job sites
- Views and edits only assigned tasks and projects
- Creates expenses and personal calendar events
- Captures and uploads job photos
- Works in environments with poor connectivity, wearing gloves, in bright sunlight

---

## Core Value Propositions

### 1. Built By Trades, For Trades
**Differentiator:** Created by a tradesperson who lived the pain points firsthand. Not a generic software company trying to understand trades after the fact.

### 2. Offline-First Architecture
**Differentiator:** Works seamlessly when connectivity drops. Critical for trades working in basements, underground, rural areas, or areas with poor cell coverage. Changes sync automatically when connection restores.

### 3. Field-Optimized Design
**Differentiator:**
- Dark theme optimized for battery life and sunlight readability
- Large touch targets for glove use
- Simple, intuitive interface requiring minimal training
- Gesture-based workflows (swipe to change status)

### 4. Price Point
**Differentiator:**
- $90-190/month (3-10 seats)
- 30-day free trial
- Competes with Jobber ($300+/month) at 1/3 the cost
- No hidden fees, no feature paywalls

### 5. Direct Founder Access
**Differentiator:**
- Direct line to founder for feature requests
- Weekly feature releases based on customer feedback
- Startup agility vs. enterprise bureaucracy
- "If you tell us you need something, we build it"

### 6. No Feature Bloat
**Differentiator:** Focused on core needs without "ridiculous features you'll never use but pay through your teeth for." Every feature serves a practical field purpose.

---

## Key Statistics

### Technical Metrics (As of Feb 2026)
- **iOS App:** 437 Swift files
- **Data Models:** 25 SwiftData entities (11 core + 14 Supabase-backed)
- **UI Components:** 50+ reusable components
- **Backend (Primary):** Supabase PostgreSQL — 15 repositories, 33 tables (10 core + 14 pipeline/financial + 6 inventory + 3 permissions), RLS (company isolation + permission-based on financial tables), Realtime WebSocket subscriptions, 16 migration files
- **Permissions:** RBAC+ABAC system — 5 preset roles, ~55 granular permissions, scope support (all/assigned/own), 4 enforcement layers (RLS, route guard, UI gating, API checks)
- **Backend (Legacy):** Bubble.io — still used for some onboarding flows, being phased out
- **Image Storage:** AWS S3 with Lambda presigned URLs
- **Architecture:** Offline-first, triple-layer sync strategy, Supabase as primary backend
- **Minimum iOS:** iOS 17+ (modern SwiftUI + SwiftData)
- **Authentication:** Google Sign-In, Apple Sign-In, Email/Password, 4-digit PIN
- **Analytics:** Firebase Analytics (analytics only)
- **Push Notifications:** OneSignal

### Business Metrics (As of Feb 15, 2026)
- **Stage:** Early-stage, actively iterating
- **Downloads (Last 3 Months):** 209
- **Active Users:** Founder's company (5 users: 4 crew + 1 operator)
- **Status:** Struggling with activation and conversion
- **Development Approach:** Feature development driven by founder's company + survey feedback from target market

### Pricing Structure
- **Trial:** 30 days, 10 seats included
- **Starter Tier:** $90/month (3 seats)
- **Team Tier:** $140/month (5 seats)
- **Business Tier:** $190/month (10 seats)
- **Annual Discount:** 20% off
- **Payment Processing:** Stripe via Bubble.io plugin

---

## Technology Stack Overview

### Frontend
- **iOS:** SwiftUI (Apple's declarative framework), iOS 17+, Xcode build
- **Web:** Next.js 14+ (App Router), TypeScript, Tailwind CSS, shadcn/ui, TanStack Query
- **Android:** In development (Kotlin + Jetpack Compose, see android-plan-v2)

### Backend
- **Supabase (PostgreSQL):** Primary backend for both iOS and Web
  - 15 Supabase repository classes (typed CRUD, company-scoped)
  - 33 tables: 10 core entity + 14 pipeline/financial + 6 inventory + 3 permissions
  - Row-Level Security (RLS) on all tables — company isolation on core tables, permission-based RLS on financial tables
  - RBAC+ABAC permissions system: 5 preset roles, ~55 permissions, scope support
  - Realtime WebSocket subscriptions for live data sync
  - 16 migration files
  - Migration API (`POST /api/admin/migrate-bubble`) for bulk Bubble-to-Supabase data transfer
- **Bubble.io (Legacy):** Original no-code backend, now being phased out
  - Still referenced in some onboarding workflows (BubbleFields.swift has been removed)
  - CentralizedSyncManager (Bubble-backed) replaced by SupabaseSyncManager
- **AWS S3:** Image storage with direct upload and Lambda presigned URLs
- **Firebase:** Analytics tracking only (Google Sign-In handled via OAuth)
- **OneSignal:** Push notifications

### Data Layer
- **SwiftData:** Apple's modern data persistence (iOS 17+)
  - 25 @Model entities (11 core + 14 Supabase-backed) registered in Schema
  - Offline-first architecture with sync flags (`needsSync`, `lastSyncedAt`)
  - Soft delete pattern (deleted items marked, not removed)
  - Migration system via UserDefaults flags

### Authentication & Security
- **OAuth:** Google Sign-In + Apple Sign-In via Firebase
- **Local Security:** 4-digit PIN (stored in Keychain, resets on app background)
- **Permissions:** RBAC+ABAC system — 5 preset roles, ~55 permissions with scopes (all/assigned/own), enforced at DB (RLS), route, UI, and API layers
- **Subscription Enforcement:** Stripe integration via Bubble.io

### Mapping & Navigation
- **MapKit:** Apple's native mapping framework
- **Turn-by-Turn Navigation:** NavEngine with Kalman filter for GPS smoothing
- **Offline Maps:** Map tiles cached for offline use
- **Background Location:** Continues tracking when app backgrounded

### Sync Strategy
- **Triple-Layer Sync:**
  1. Immediate (user actions with 2-second debounce)
  2. Event-driven (app launch, connectivity restored, app foreground)
  3. Periodic (3-minute retry for failed syncs)
- **Conflict Resolution:** Push local changes first, then fetch and replace with server data (server wins)
- **Offline Queue:** Changes persist locally until connectivity restored

---

## Development Philosophy

### "Built By Trades, For Trades"
Every design decision reflects real-world field experience:
- **Dark Theme:** Battery life + sunlight readability
- **Large Touch Targets:** Usable with work gloves
- **Offline-First:** Works in basements, underground, rural areas
- **Simple Navigation:** Minimal training required
- **Gesture-Based:** Swipe to change status, pull to refresh
- **Photo-Centric:** Document work with in-app camera
- **Turn-by-Turn:** Navigate directly to job sites

### Iteration Model
- **Rapid Releases:** Weekly feature updates
- **Customer-Driven:** Features based on direct customer feedback
- **Founder's Company as Lab:** Real-world testing in production environment
- **Survey Insights:** Target market surveys guide roadmap

### Field-First Testing Requirements
- **Offline Testing:** All features must work without connectivity
- **Glove Testing:** UI must be usable with work gloves
- **Sunlight Testing:** Screen must be readable in direct sunlight
- **Old Device Testing:** Must perform well on older iOS devices
- **Battery Testing:** Must minimize battery drain for all-day field use

---

## Product Vision: Current State + Roadmap

### Current State (iOS App + Web App + Ecosystem)

**iOS App (437 Swift files, 25 SwiftData models):**
- Job scheduling and crew assignment
- Offline-first architecture with Supabase as primary backend
- Turn-by-turn navigation to job sites
- Photo documentation with in-app camera
- Photo annotations (markup, labels on job photos)
- Task status tracking (Unstarted, In Progress, Completed, Billed)
- Calendar/timeline views with personal events and time-off requests
- **Job Board (redesigned March 2026):** Role-based section system
  - Field crew: My Tasks (filtered by explicit assignment) + My Projects (assigned projects only)
  - Office crew: Projects list + Tasks list + Kanban status view
  - Admin + pipeline permission: all of the above + Pipeline CRM section
  - Universal search sheet (role-filtered, pipeline-gated) accessible from header
  - `DirectionalDragModifier` for conflict-free horizontal swipe within scroll views
  - Accessibility-aware animations via `Animation.accessibleEaseInOut()` — respects iOS Reduce Motion setting
- Pipeline CRM (iOS — opportunities, stage transitions; pipeline section in Job Board)
- Inventory system (items, units, tags, snapshots)
- In-app notifications (OneSignal push + local notification records)
- Dark theme optimized for field use
- 4-digit PIN security
- Google Sign-In authentication
- Interactive 25-phase tutorial system

**OPS Web (ops-web — Next.js, Feb 2026):**
- Full web command center mirroring iOS features
- **Email Pipeline Import:** AI-powered inbox scanning that detects leads from Gmail and Microsoft 365, classifies them with OpenAI, matches to existing clients, and imports into the pipeline CRM. Includes a 5-step wizard for initial setup, ongoing scheduled sync (every 15 min), real-time webhook push, and feature-gated AI draft replies with memory/writing-profile support. See `04_API_AND_INTEGRATION.md` §20 and `10_JOB_LIFECYCLE_AND_DATA_RELATIONSHIPS.md` §10 for full architecture.
- **Pipeline/CRM system:** 8-stage Kanban board (New Lead → Qualifying → Quoting → Quoted → Follow-Up → Negotiation → Won → Lost) with drag-and-drop, activity timeline, follow-up tracking
- **Estimates system:** Full quote builder with line items, optional items, deposit schedules, payment milestones, PDF storage, version control, atomic estimate→invoice conversion
- **Invoices system:** Full billing with line items, payment recording, DB-trigger-maintained balances, payment voiding, partial payments
- **Products/Services catalog:** Reusable catalog items for estimate and invoice line items, margin tracking
- **Accounting integrations:** QuickBooks + Sage OAuth connection layer
- Real-time sync indicators, bulk actions, CSV export
- Keyboard shortcuts (Cmd+B sidebar, command palette)
- Floating window system (draggable, minimizable create forms)
- **Project Notes system:** first-class threaded notes with @mentions, author attribution, photo attachments, legacy migration from Bubble teamNotes
- **Calendar/Schedule system:** 5-view calendar (month, week, day, team timeline, agenda) with drag-and-drop scheduling, event resize, click-to-create, detail panel, multi-filter sidebar, conflict detection, keyboard shortcuts, responsive (mobile/tablet/desktop)

**Ecosystem Apps:**
- **ops-site** — Marketing website (Next.js)
- **ops-learn** — Learning platform (Next.js, Supabase)
- **try-ops** — Interactive tutorial/demo, browser-based (Next.js), no download required

### Active Development (Based on Survey Feedback)
Survey of target audience revealed critical missing features driving roadmap:

1. **Email Integration:** Send estimates and invoices via email directly from app (Gmail OAuth underway)
2. **Commission Tracking:** Track sales commission for estimators and door-knockers
3. **Photo Markup:** Captions, arrows, notes, labels on job photos (not just gallery)
4. **Recurring Schedules:** Auto-populate weekly/bi-weekly jobs for cleaning businesses
5. **Materials/Inventory Tracking:** Per-job inventory management
6. **Multi-Crew Time-Specific Scheduling:** Not just dates, but specific start times per crew
7. **Accounting Sync:** Full QuickBooks/Sage two-way sync (connection layer built, sync logic pending)

### Long-Term Vision
OPS will become a **full-stack end-to-end solution** for service-based businesses, competing directly with Jobber ($300+/month) at $90-190/month price point. Survey shows Jobber has strong adoption in target market, validating demand for comprehensive job management software. OPS will win on:
- **Price:** 1/3 the cost of Jobber
- **Direct Founder Access:** Immediate responsiveness to customer needs
- **Startup Agility:** Weekly releases vs. enterprise bureaucracy

---

## Competitive Landscape

### Primary Competitor: Jobber
- **Price:** $300+/month
- **Market Position:** Strong adoption in trades (validated by survey data)
- **Weaknesses (OPS advantages):**
  - High cost
  - Requires constant connectivity (crashes offline)
  - Complex UI requiring significant training
  - Enterprise company with slow response to customer needs

### OPS Competitive Advantages
1. **Price:** $90-190/month (70% cheaper)
2. **Offline-First:** Works seamlessly without connectivity
3. **Simplicity:** Intuitive UI, minimal training
4. **Direct Access:** Founder responds directly to customers
5. **Rapid Iteration:** Weekly feature releases
6. **Field-Optimized:** Built by tradesperson for tradespeople

---

## Document Navigation

This executive summary is the entry point for the OPS Software Bible. For detailed technical and functional documentation, see:

- **[01_PRODUCT_REQUIREMENTS.md](01_PRODUCT_REQUIREMENTS.md)** - Complete feature list, user stories, business rules
- **[02_USER_EXPERIENCE_AND_WORKFLOWS.md](02_USER_EXPERIENCE_AND_WORKFLOWS.md)** - Navigation flows, user journeys, permissions
- **[03_DATA_ARCHITECTURE.md](03_DATA_ARCHITECTURE.md)** - Data models, relationships, BubbleFields mapping
- **[04_API_AND_INTEGRATION.md](04_API_AND_INTEGRATION.md)** - API endpoints, sync strategy, authentication
- **[05_DESIGN_SYSTEM.md](05_DESIGN_SYSTEM.md)** - Colors, typography, components, patterns
- **[06_TECHNICAL_ARCHITECTURE.md](06_TECHNICAL_ARCHITECTURE.md)** - Code structure, patterns, best practices
- **[07_SPECIALIZED_FEATURES.md](07_SPECIALIZED_FEATURES.md)** - Navigation, maps, calendar, tutorial
- **[08_DEPLOYMENT_AND_OPERATIONS.md](08_DEPLOYMENT_AND_OPERATIONS.md)** - Build, deploy, testing, monitoring

---

## Success Criteria for This Documentation

This Software Bible is considered complete when:

1. ✅ An agent with **zero prior context** can read these documents and build a fully functional OPS web application with 100% feature parity to iOS
2. ✅ All 25 SwiftData models are documented with complete property lists and relationships
3. ✅ All API endpoints are cataloged with request/response formats
4. ✅ All 50+ UI components are documented with usage patterns
5. ✅ Color palette, typography, and design constants are verified from production code
6. ✅ Business rules and constraints are explicitly documented
7. ✅ User workflows for all 3 roles are comprehensively mapped
8. ✅ Sync strategy and conflict resolution are fully explained
9. ✅ No contradictions exist between documents
10. ✅ Code examples are provided for complex implementations

---

**Last Updated:** March 16, 2026
**Document Version:** 1.6
**iOS App Version:** 437 Swift files, 25 SwiftData models, iOS 17+, Supabase primary backend
**Web App Version:** Next.js, Supabase (33 tables, 16 migrations), Pipeline/Estimates/Invoices/Project Notes/Inventory/Notifications/Permissions/Calendar live
**Ecosystem:** ops-site (marketing), ops-learn (learning platform), try-ops (interactive tutorial)
