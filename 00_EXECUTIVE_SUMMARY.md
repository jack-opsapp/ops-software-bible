# 00_EXECUTIVE_SUMMARY.md

## Document Purpose

This executive summary provides a high-level overview of OPS (Operational Project System) for non-technical stakeholders and serves as the entry point for understanding the product, market, and technical foundation.

---

## Elevator Pitch (Founder's Voice)

OPS is job management software built by a railings contractor for specialized trades—electricians, plumbers, landscapers, deck builders. Not for general contractors.

I spent 10 years in commercial railings and got sick of apps like Jobber that cost $300+ a month, crash when you're underground with no signal, and are so complicated your crew won't use them.

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

### User Personas

**1. Admin (Company Owner)**
- Full system access
- Manages company settings, subscription, billing
- Oversees all projects, tasks, crew assignments
- Sets up employees and client records
- Views analytics and company performance

**2. Office Crew**
- Office staff managing scheduling and coordination
- Creates and schedules projects and tasks
- Assigns field crews to jobs
- Manages client communication
- Updates job status based on field reports
- No field work responsibilities

**3. Field Crew**
- Workers in the field using the app on job sites
- Views assigned tasks and schedules
- Navigates to job sites with turn-by-turn directions
- Updates task status (Unstarted, In Progress, Completed, Billed)
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
- **iOS App:** 207 Swift files
- **Data Models:** 9 SwiftData entities with relationships
- **UI Components:** 50+ reusable components
- **Backend:** Bubble.io REST API + AWS S3 image storage
- **Architecture:** Offline-first, triple-layer sync strategy
- **Minimum iOS:** iOS 17+ (modern SwiftUI + SwiftData)
- **Authentication:** Google Sign-In, Apple Sign-In, Email/Password, 4-digit PIN
- **Analytics:** Firebase Analytics with Google Ads integration

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
- **Bubble.io:** No-code platform with REST API
  - Base URL: `https://opsapp.co/version-test/api/1.1/`
  - Handles operational data: Projects, Tasks, Clients, Calendar, Company, Users
- **Supabase (PostgreSQL):** Financial data layer (Web only)
  - Pipeline/CRM, Estimates, Invoices, Payments, Products, Tax Rates, Accounting Connections
  - 13+ tables with RLS, DB triggers for payment balance tracking, RPCs for atomic operations
- **AWS S3:** Image storage with direct upload and Lambda presigned URLs
- **Firebase:** Analytics tracking, Google Sign-In authentication

### Data Layer
- **SwiftData:** Apple's modern data persistence (iOS 17+)
  - 9 @Model entities with relationships
  - Offline-first architecture with sync flags
  - Soft delete pattern (deleted items marked, not removed)
  - Migration system via UserDefaults flags

### Authentication & Security
- **OAuth:** Google Sign-In + Apple Sign-In via Firebase
- **Local Security:** 4-digit PIN (stored in Keychain, resets on app background)
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

### Current State (iOS App + Web App)

**iOS App (207 Swift files):**
- Job scheduling and crew assignment
- Offline-first architecture
- Turn-by-turn navigation to job sites
- Photo documentation with in-app camera
- Task status tracking (Unstarted, In Progress, Completed, Billed)
- Calendar/timeline views
- Dark theme optimized for field use
- 4-digit PIN security
- Google Sign-In authentication
- Interactive 25-phase tutorial system

**OPS Web (ops-web — Next.js, Feb 2026):**
- Full web command center mirroring iOS features
- **Pipeline/CRM system:** 8-stage Kanban board (New Lead → Qualifying → Quoting → Quoted → Follow-Up → Negotiation → Won → Lost) with drag-and-drop, activity timeline, follow-up tracking
- **Estimates system:** Full quote builder with line items, optional items, deposit schedules, payment milestones, PDF storage, version control, atomic estimate→invoice conversion
- **Invoices system:** Full billing with line items, payment recording, DB-trigger-maintained balances, payment voiding, partial payments
- **Products/Services catalog:** Reusable catalog items for estimate and invoice line items, margin tracking
- **Accounting integrations:** QuickBooks + Sage OAuth connection layer
- Real-time sync indicators, bulk actions, CSV export
- Keyboard shortcuts (Cmd+B sidebar, command palette)
- Floating window system (draggable, minimizable create forms)

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
2. ✅ All 9 SwiftData models are documented with complete property lists and relationships
3. ✅ All API endpoints are cataloged with request/response formats
4. ✅ All 50+ UI components are documented with usage patterns
5. ✅ Color palette, typography, and design constants are verified from production code
6. ✅ Business rules and constraints are explicitly documented
7. ✅ User workflows for all 3 roles are comprehensively mapped
8. ✅ Sync strategy and conflict resolution are fully explained
9. ✅ No contradictions exist between documents
10. ✅ Code examples are provided for complex implementations

---

**Last Updated:** February 17, 2026
**Document Version:** 1.1
**iOS App Version:** 207 Swift files, iOS 17+, SwiftData + SwiftUI
**Web App Version:** Next.js, Supabase financial system, Pipeline/Estimates/Invoices live
